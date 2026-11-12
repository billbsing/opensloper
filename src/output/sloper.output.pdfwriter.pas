{
  OpenSloper - parametric sewing pattern drafting
  Copyright (C) 2026 The OpenSloper authors

  This program is free software: you can redistribute it and/or modify
  it under the terms of the GNU General Public License as published by
  the Free Software Foundation, either version 3 of the License, or
  (at your option) any later version.

  This program is distributed in the hope that it will be useful,
  but WITHOUT ANY WARRANTY; without even the implied warranty of
  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
  GNU General Public License for more details.

  You should have received a copy of the GNU General Public License
  along with this program.  If not, see <https://www.gnu.org/licenses/>.
}

// A small PDF writer: stroked lines and text on pages sized in millimetres.
// Written here rather than through fcl-pdf so that scale is exact and the same
// layout always gives the same bytes. Coordinates are millimetres from the
// page's top left, y down. Pages are not compressed, so tests can read them.

// Text in the default font is Helvetica, a font every PDF reader has, in its
// bold and oblique forms as asked. A named font is embedded from its TrueType
// file, cut down to the glyphs used (Sloper.Output.FontSubset), and so is the
// bundled Noto Sans for default-font text Helvetica cannot print. A face the
// family lacks is drawn: bold as text stroked as well as filled, italic as
// slanted text. A named font that cannot be embedded prints in the default
// font (see FontProblem).
unit Sloper.Output.PDFWriter;

{$mode ObjFPC}{$H+}

interface

uses
  SysUtils, Sloper.Core.Geometry, Sloper.Core.Note, Sloper.Output.Fonts;

type
  // Helvetica in one of its four forms, or a face embedded from its file
  TPDFFont = record
    StandardName: string;
    Face: TFontFace;
    // For each glyph, 1 + the code point it was first used for; 0 when unused
    Used: array of cardinal;
  end;

  TIntegerArray = array of integer;

  TPDFWriter = class
  private
    FPageWidths, FPageHeights: array of double;
    FContents: array of rawbytestring;
    FFonts: array of TPDFFont;
    function StandardFont(const AName: string): integer;
    function EmbeddedFont(Face: TFontFace): integer;
    procedure StandardText(AX, AY, Size: double; const AText: string; ABold, AItalic: boolean);
    procedure EmbeddedText(AX, AY, Size: double; const AText: string; Face: TFontFace; ABold, AItalic: boolean);
    function FontObjects(FirstId: integer; out Resources: rawbytestring; out Offsets: TIntegerArray): rawbytestring;
    function GetPageCount: integer;
    procedure Add(const Text: rawbytestring);
    function PageX(Value: double): string;
    function PageY(Value: double): string;
  public
    procedure BeginPage(AWidth, AHeight: double);
    procedure SetLineWidth(Millimetres: double);
    // Dashes and gaps this long; 0 for a solid line
    procedure SetDash(Millimetres: double);
    // Dash, gap, dash, gap... in mm; a solid line when the first is 0
    procedure SetDashPattern(const Lengths: array of double);
    // Lines and text from here on, from 0 for black to 1 for white
    procedure SetGray(Level: double);
    // The same in colour, each part from 0 to 1
    procedure SetColor(Red, Green, Blue: double);
    procedure FillRectangle(const Area: TRect2);
    procedure FillPolygon(const Points: TVec2Array);
    procedure Polyline(const Points: TVec2Array; Closed: boolean);
    procedure Line(const From, Target: TVec2);
    procedure Rectangle(const Area: TRect2);
    // Baseline at (AX, AY); Size in points; in the default font
    procedure Text(AX, AY, Size: double; const AText: string); overload;
    // In Style's font, or the default font when it cannot be embedded
    procedure Text(AX, AY, Size: double; const AText: string; const Style: TTextStyle); overload;
    // Everything until PopClip is cut off at Area
    procedure PushClip(const Area: TRect2);
    procedure PopClip;
    // The finished file, as bytes
    function Finish: rawbytestring;
    property PageCount: integer read GetPageCount;
  end;

implementation

uses
  Classes, zstream, crc, fpparsettf, Sloper.Output.FontSubset;

const
  POINTS_PER_MM = 72 / 25.4;
  VALUE_DECIMALS = '0.###';
  FONT_ID = 3;
  FIRST_PAGE_ID = 4;
  // The four forms of Helvetica, by bold then italic
  HELVETICA_NAMES: array[boolean, boolean] of string = (('Helvetica', 'Helvetica-Oblique'), ('Helvetica-Bold', 'Helvetica-BoldOblique'));
  // A drawn italic slants by tan 12°, as an oblique face does
  FAKE_ITALIC_SLANT = 0.2126;
  // A drawn bold strokes the letters this wide, as a share of the size
  FAKE_BOLD_STROKE = 0.03;
  // A subset font's name starts with six capitals, then +
  SUBSET_TAG_LETTERS = 6;
  ALPHABET_LETTERS = 26;
  // bfchar entries per block, the most a CMap allows
  CMAP_BLOCK = 100;
  // FontDescriptor flags: nonsymbolic, and italic
  FLAG_NONSYMBOLIC = 32;
  FLAG_ITALIC = 64;
  MILLE = 1000;
  // What Helvetica prints in WinAnsi: Latin-1 less the control characters
  LATIN_PRINTABLE_LAST = 126;
  LATIN_UPPER_FIRST = 160;
  LATIN_UPPER_LAST = 255;
  SPACE_CODE = 32;
  SUPPLEMENTARY_FIRST = $10000;
  HIGH_SURROGATE_FIRST = $D800;
  LOW_SURROGATE_FIRST = $DC00;
  SURROGATE_BITS = 10;
  SURROGATE_MASK = $3FF;

function PointsText(Value: double): string;
var
  Settings: TFormatSettings;
begin
  Settings := DefaultFormatSettings;
  Settings.DecimalSeparator := '.';
  Result := FormatFloat(VALUE_DECIMALS, Value, Settings);
  if Result = '-0' then
    Result := '0';
end;

function HexWord(Value: cardinal): rawbytestring;
begin
  Result := IntToHex(Value, 4);
end;

// A code point as UTF-16 in hex, for a ToUnicode map
function UTF16Hex(Code: cardinal): rawbytestring;
begin
  if Code < SUPPLEMENTARY_FIRST then
    Exit(HexWord(Code));
  Dec(Code, SUPPLEMENTARY_FIRST);
  Result := HexWord(HIGH_SURROGATE_FIRST + (Code shr SURROGATE_BITS)) + HexWord(LOW_SURROGATE_FIRST + (Code and SURROGATE_MASK));
end;

function TPDFWriter.GetPageCount: integer;
begin
  Result := Length(FContents);
end;

procedure TPDFWriter.Add(const Text: rawbytestring);
begin
  FContents[High(FContents)] := FContents[High(FContents)] + Text + #10;
end;

function TPDFWriter.PageX(Value: double): string;
begin
  Result := PointsText(Value * POINTS_PER_MM);
end;

// PDF's y points up, from the bottom of the page
function TPDFWriter.PageY(Value: double): string;
begin
  Result := PointsText((FPageHeights[High(FPageHeights)] - Value) * POINTS_PER_MM);
end;

// Six capitals from the font and the glyphs it uses, so a subset's name says
// which subset it is and stays the same for the same glyphs
function SubsetTag(const Font: TPDFFont): string;
var
  Sum: cardinal;
  Index: integer;
  Key: rawbytestring;
begin
  Key := Font.Face.PostScriptName;
  for Index := 0 to High(Font.Used) do
    if Font.Used[Index] <> 0 then
      Key := Key + HexWord(Index);
  Sum := crc32(crc32(0, nil, 0), pbyte(PChar(Key)), Length(Key));
  Result := '';
  for Index := 1 to SUBSET_TAG_LETTERS do
  begin
    Result := Result + chr(Ord('A') + Sum mod ALPHABET_LETTERS);
    Sum := Sum div ALPHABET_LETTERS;
  end;
end;

function Compressed(const Data: rawbytestring): rawbytestring;
var
  Output: TMemoryStream;
  Packer: TCompressionStream;
begin
  Result := '';
  Packer := nil;
  Output := TMemoryStream.Create;
  try
    Packer := TCompressionStream.Create(clMax, Output);
    if Length(Data) > 0 then
      Packer.WriteBuffer(Data[1], Length(Data));
    FreeAndNil(Packer);
    SetLength(Result, Output.Size);
    if Output.Size > 0 then
      Move(Output.Memory^, Result[1], Output.Size);
  finally
    FreeAndNil(Packer);
    FreeAndNil(Output);
  end;
end;

// In thousandths of the font's size
function Natural(Face: TFontFace; FontUnits: integer): string;
begin
  Result := IntToStr(Round(FontUnits * MILLE / Face.Info.Head.UnitsPerEm));
end;

function ToUnicodeMap(const Font: TPDFFont): rawbytestring;
var
  Entries: array of rawbytestring;
  Index, First, Last: integer;
begin
  Entries := nil;
  for Index := 0 to High(Font.Used) do
    if Font.Used[Index] <> 0 then
      Insert('<' + HexWord(Index) + '> <' + UTF16Hex(Font.Used[Index] - 1) + '>', Entries, Length(Entries));
  Result := '/CIDInit /ProcSet findresource begin' + #10 + '12 dict begin' + #10 + 'begincmap' + #10 +
    '/CIDSystemInfo << /Registry (Adobe) /Ordering (UCS) /Supplement 0 >> def' + #10 + '/CMapName /Adobe-Identity-UCS def' + #10 +
    '/CMapType 2 def' + #10 + '1 begincodespacerange' + #10 + '<0000> <FFFF>' + #10 + 'endcodespacerange' + #10;
  First := 0;
  while First <= High(Entries) do
  begin
    Last := First + CMAP_BLOCK - 1;
    if Last > High(Entries) then
      Last := High(Entries);
    Result := Result + IntToStr(Last - First + 1) + ' beginbfchar' + #10;
    for Index := First to Last do
      Result := Result + Entries[Index] + #10;
    Result := Result + 'endbfchar' + #10;
    First := Last + 1;
  end;
  Result := Result + 'endcmap' + #10 + 'CMapName currentdict /CMap defineresource pop' + #10 + 'end' + #10 + 'end' + #10;
end;

// The objects of every font but Helvetica (FONT_ID), numbered from FirstId,
// where each starts in the result, and the page resources naming them all
function TPDFWriter.FontObjects(FirstId: integer; out Resources: rawbytestring; out Offsets: TIntegerArray): rawbytestring;
var
  Index, Glyph, Id, Flags: integer;
  Font: TPDFFont;
  Name, Widths, Data, Subset, FontFile: rawbytestring;
  Glyphs: array of word;
  Info: TTFFileInfo;

  procedure AddObject(const Body: rawbytestring);
  begin
    Insert(Length(Result), Offsets, Length(Offsets));
    Result := Result + IntToStr(Id) + ' 0 obj' + #10 + Body + #10 + 'endobj' + #10;
    Inc(Id);
  end;

begin
  Result := '';
  Offsets := nil;
  Resources := '/F1 ' + IntToStr(FONT_ID) + ' 0 R';
  Id := FirstId;
  for Index := 1 to High(FFonts) do
  begin
    Font := FFonts[Index];
    Resources := Resources + ' /F' + IntToStr(Index + 1) + ' ' + IntToStr(Id) + ' 0 R';
    if not Assigned(Font.Face) then
    begin
      AddObject('<< /Type /Font /Subtype /Type1 /BaseFont /' + Font.StandardName + ' /Encoding /WinAnsiEncoding >>');
      Continue;
    end;
    Info := Font.Face.Info;
    Name := SubsetTag(Font) + '+' + Font.Face.PostScriptName;
    Widths := '';
    Glyphs := nil;
    for Glyph := 0 to High(Font.Used) do
      if Font.Used[Glyph] <> 0 then
      begin
        Widths := Widths + IntToStr(Glyph) + ' [' + IntToStr(Font.Face.GlyphWidth(Glyph)) + '] ';
        Insert(Glyph, Glyphs, Length(Glyphs));
      end;
    Flags := FLAG_NONSYMBOLIC;
    if Font.Face.Italic then
      Flags := Flags or FLAG_ITALIC;
    AddObject('<< /Type /Font /Subtype /Type0 /BaseFont /' + Name + ' /Encoding /Identity-H /DescendantFonts [' + IntToStr(Id + 1) +
      ' 0 R] /ToUnicode ' + IntToStr(Id + 4) + ' 0 R >>');
    AddObject('<< /Type /Font /Subtype /CIDFontType2 /BaseFont /' + Name +
      ' /CIDSystemInfo << /Registry (Adobe) /Ordering (Identity) /Supplement 0 >> /FontDescriptor ' + IntToStr(Id + 1) +
      ' 0 R /CIDToGIDMap /Identity /DW ' + IntToStr(Font.Face.GlyphWidth(0)) + ' /W [' + Trim(Widths) + '] >>');
    // A file that can no longer be read is left out, and the reader stands in
    // a font of its own
    Data := Font.Face.FileData;
    if not SubsetTrueType(Data, Glyphs, Subset) then
      Subset := '';
    FontFile := '';
    if Subset <> '' then
      FontFile := ' /FontFile2 ' + IntToStr(Id + 1) + ' 0 R';
    AddObject('<< /Type /FontDescriptor /FontName /' + Name + ' /Flags ' + IntToStr(Flags) + ' /FontBBox [' + Info.BBox +
      '] /ItalicAngle ' + PointsText(Info.ItalicAngle) + ' /Ascent ' + Natural(Font.Face, Info.Ascender) + ' /Descent ' +
      Natural(Font.Face, Info.Descender) + ' /CapHeight ' + Natural(Font.Face, Info.CapHeight) + ' /StemV ' + IntToStr(Info.StemV) +
      FontFile + ' >>');
    // Written even when empty, so every embedded font takes the same objects
    Data := Compressed(Subset);
    AddObject('<< /Length ' + IntToStr(Length(Data)) + ' /Length1 ' + IntToStr(Length(Subset)) + ' /Filter /FlateDecode >>' + #10 +
      'stream' + #10 + Data + #10 + 'endstream');
    Data := ToUnicodeMap(Font);
    AddObject('<< /Length ' + IntToStr(Length(Data)) + ' >>' + #10 + 'stream' + #10 + Data + 'endstream');
  end;
end;

procedure TPDFWriter.BeginPage(AWidth, AHeight: double);
begin
  SetLength(FPageWidths, Length(FPageWidths) + 1);
  FPageWidths[High(FPageWidths)] := AWidth;
  SetLength(FPageHeights, Length(FPageHeights) + 1);
  FPageHeights[High(FPageHeights)] := AHeight;
  SetLength(FContents, Length(FContents) + 1);
end;

procedure TPDFWriter.SetLineWidth(Millimetres: double);
begin
  Add(PointsText(Millimetres * POINTS_PER_MM) + ' w');
end;

procedure TPDFWriter.SetDash(Millimetres: double);
begin
  if Millimetres <= 0 then
    Add('[] 0 d')
  else
    Add('[' + PointsText(Millimetres * POINTS_PER_MM) + '] 0 d');
end;

procedure TPDFWriter.SetDashPattern(const Lengths: array of double);
var
  Pattern: rawbytestring;
  Index: integer;
begin
  Pattern := '';
  for Index := 0 to High(Lengths) do
    if Lengths[Index] > 0 then
    begin
      if Pattern <> '' then
        Pattern := Pattern + ' ';
      Pattern := Pattern + PointsText(Lengths[Index] * POINTS_PER_MM);
    end;
  if (Length(Lengths) = 0) or (Lengths[0] <= 0) then
    Pattern := '';
  Add('[' + Pattern + '] 0 d');
end;

procedure TPDFWriter.SetGray(Level: double);
begin
  Add(PointsText(Level) + ' G ' + PointsText(Level) + ' g');
end;

procedure TPDFWriter.SetColor(Red, Green, Blue: double);
var
  Parts: string;
begin
  Parts := PointsText(Red) + ' ' + PointsText(Green) + ' ' + PointsText(Blue);
  Add(Parts + ' RG ' + Parts + ' rg');
end;

procedure TPDFWriter.FillRectangle(const Area: TRect2);
begin
  Add(PageX(Area.MinX) + ' ' + PageY(Area.MaxY) + ' ' + PointsText((Area.MaxX - Area.MinX) * POINTS_PER_MM) + ' ' +
    PointsText((Area.MaxY - Area.MinY) * POINTS_PER_MM) + ' re f');
end;

procedure TPDFWriter.FillPolygon(const Points: TVec2Array);
var
  Index: integer;
begin
  for Index := 0 to High(Points) do
    if Index = 0 then
      Add(PageX(Points[Index].X) + ' ' + PageY(Points[Index].Y) + ' m')
    else
      Add(PageX(Points[Index].X) + ' ' + PageY(Points[Index].Y) + ' l');
  Add('h f');
end;

procedure TPDFWriter.Polyline(const Points: TVec2Array; Closed: boolean);
var
  Index: integer;
begin
  if Length(Points) < 2 then
    Exit;
  Add(PageX(Points[0].X) + ' ' + PageY(Points[0].Y) + ' m');
  for Index := 1 to High(Points) do
    Add(PageX(Points[Index].X) + ' ' + PageY(Points[Index].Y) + ' l');
  if Closed then
    Add('s')
  else
    Add('S');
end;

procedure TPDFWriter.Line(const From, Target: TVec2);
begin
  Add(PageX(From.X) + ' ' + PageY(From.Y) + ' m ' + PageX(Target.X) + ' ' + PageY(Target.Y) + ' l S');
end;

procedure TPDFWriter.Rectangle(const Area: TRect2);
begin
  Add(PageX(Area.MinX) + ' ' + PageY(Area.MaxY) + ' ' + PointsText((Area.MaxX - Area.MinX) * POINTS_PER_MM) + ' ' +
    PointsText((Area.MaxY - Area.MinY) * POINTS_PER_MM) + ' re S');
end;

// WinAnsi matches Latin-1 for what is kept here
function EscapedText(const AText: string): rawbytestring;
var
  Code: cardinal;
begin
  Result := '';
  for Code in TextCodePoints(AText) do
    if Code in [Ord('('), Ord(')'), Ord('\')] then
      Result := Result + '\' + chr(Code)
    else if (Code >= SPACE_CODE) and (Code <= LATIN_PRINTABLE_LAST) or (Code >= LATIN_UPPER_FIRST) and (Code <= LATIN_UPPER_LAST) then
      Result := Result + chr(Code)
    else
      Result := Result + '?';
end;

// Whether Helvetica can print it all; control characters print as "?" either way
function HelveticaPrints(const AText: string): boolean;
var
  Code: cardinal;
begin
  for Code in TextCodePoints(AText) do
    if (Code > LATIN_PRINTABLE_LAST) and ((Code < LATIN_UPPER_FIRST) or (Code > LATIN_UPPER_LAST)) then
      Exit(False);
  Result := True;
end;

function TPDFWriter.StandardFont(const AName: string): integer;
begin
  for Result := 0 to High(FFonts) do
    if FFonts[Result].StandardName = AName then
      Exit;
  Result := Length(FFonts);
  SetLength(FFonts, Result + 1);
  FFonts[Result] := Default(TPDFFont);
  FFonts[Result].StandardName := AName;
end;

function TPDFWriter.EmbeddedFont(Face: TFontFace): integer;
begin
  for Result := 0 to High(FFonts) do
    if FFonts[Result].Face = Face then
      Exit;
  Result := Length(FFonts);
  SetLength(FFonts, Result + 1);
  FFonts[Result] := Default(TPDFFont);
  FFonts[Result].Face := Face;
  SetLength(FFonts[Result].Used, Face.Info.MaxP.numGlyphs);
end;

// Helvetica is always font 1, so a file with no other font is as it always was
procedure TPDFWriter.StandardText(AX, AY, Size: double; const AText: string; ABold, AItalic: boolean);
var
  Font: integer;
begin
  StandardFont(HELVETICA_NAMES[False, False]);
  Font := StandardFont(HELVETICA_NAMES[ABold, AItalic]);
  Add('BT /F' + IntToStr(Font + 1) + ' ' + PointsText(Size) + ' Tf ' + PageX(AX) + ' ' + PageY(AY) + ' Td (' + EscapedText(AText) +
    ') Tj ET');
end;

// Each glyph by its number in the face (Identity-H); a style the face lacks
// is drawn
procedure TPDFWriter.EmbeddedText(AX, AY, Size: double; const AText: string; Face: TFontFace; ABold, AItalic: boolean);
var
  Font: integer;
  Code: cardinal;
  Glyph: word;
  Glyphs, Place: rawbytestring;
  FakeBold: boolean;
begin
  StandardFont(HELVETICA_NAMES[False, False]);
  Font := EmbeddedFont(Face);
  Glyphs := '';
  for Code in TextCodePoints(AText) do
  begin
    Glyph := Face.GlyphOf(Code);
    if (Glyph <= High(FFonts[Font].Used)) and (FFonts[Font].Used[Glyph] = 0) then
      FFonts[Font].Used[Glyph] := Code + 1;
    Glyphs := Glyphs + HexWord(Glyph);
  end;
  if AItalic and not Face.Italic then
    Place := '1 0 ' + PointsText(FAKE_ITALIC_SLANT) + ' 1 ' + PageX(AX) + ' ' + PageY(AY) + ' Tm'
  else
    Place := PageX(AX) + ' ' + PageY(AY) + ' Td';
  FakeBold := ABold and not Face.Bold;
  if FakeBold then
    Add('q ' + PointsText(Size * FAKE_BOLD_STROKE) + ' w BT /F' + IntToStr(Font + 1) + ' ' + PointsText(Size) + ' Tf 2 Tr ' + Place +
      ' <' + Glyphs + '> Tj ET Q')
  else
    Add('BT /F' + IntToStr(Font + 1) + ' ' + PointsText(Size) + ' Tf ' + Place + ' <' + Glyphs + '> Tj ET');
end;

procedure TPDFWriter.Text(AX, AY, Size: double; const AText: string);
begin
  Text(AX, AY, Size, AText, Default(TTextStyle));
end;

procedure TPDFWriter.Text(AX, AY, Size: double; const AText: string; const Style: TTextStyle);
var
  Face: TFontFace;
begin
  if (Style.Font <> '') and (FindFontFace(Style, Face) = flFound) then
    EmbeddedText(AX, AY, Size, AText, Face, Style.Bold, Style.Italic)
  else if not HelveticaPrints(AText) and Assigned(BundledFontFace) then
    EmbeddedText(AX, AY, Size, AText, BundledFontFace, Style.Bold, Style.Italic)
  else
    StandardText(AX, AY, Size, AText, Style.Bold, Style.Italic);
end;

procedure TPDFWriter.PushClip(const Area: TRect2);
begin
  Add('q ' + PageX(Area.MinX) + ' ' + PageY(Area.MaxY) + ' ' + PointsText((Area.MaxX - Area.MinX) * POINTS_PER_MM) + ' ' +
    PointsText((Area.MaxY - Area.MinY) * POINTS_PER_MM) + ' re W n');
end;

procedure TPDFWriter.PopClip;
begin
  Add('Q');
end;

function TPDFWriter.Finish: rawbytestring;
var
  Offsets: array of integer;
  Index, ObjectCount, FontsId, Position: integer;
  Kids, Resources, Fonts: rawbytestring;
  FontOffsets: TIntegerArray;

  procedure AddObject(Id: integer; const Body: rawbytestring);
  begin
    Offsets[Id] := Length(Result);
    Result := Result + IntToStr(Id) + ' 0 obj' + #10 + Body + #10 + 'endobj' + #10;
  end;

begin
  FontsId := FIRST_PAGE_ID + 2 * Length(FContents);
  Fonts := FontObjects(FontsId, Resources, FontOffsets);
  ObjectCount := FontsId + Length(FontOffsets);
  Offsets := nil;
  SetLength(Offsets, ObjectCount);
  Result := '%PDF-1.4' + #10;
  Kids := '';
  for Index := 0 to High(FContents) do
    Kids := Kids + IntToStr(FIRST_PAGE_ID + 2 * Index) + ' 0 R ';
  AddObject(1, '<< /Type /Catalog /Pages 2 0 R >>');
  AddObject(2, '<< /Type /Pages /Count ' + IntToStr(Length(FContents)) + ' /Kids [' + Trim(Kids) + '] >>');
  AddObject(FONT_ID, '<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica /Encoding /WinAnsiEncoding >>');
  for Index := 0 to High(FContents) do
  begin
    AddObject(FIRST_PAGE_ID + 2 * Index, '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 ' + PointsText(FPageWidths[Index] * POINTS_PER_MM) +
      ' ' + PointsText(FPageHeights[Index] * POINTS_PER_MM) + '] /Resources << /Font << ' + Resources + ' >> >> /Contents ' +
      IntToStr(FIRST_PAGE_ID + 2 * Index + 1) + ' 0 R >>');
    AddObject(FIRST_PAGE_ID + 2 * Index + 1, '<< /Length ' + IntToStr(Length(FContents[Index])) + ' >>' + #10 + 'stream' + #10 +
      FContents[Index] + 'endstream');
  end;
  Position := Length(Result);
  Result := Result + Fonts;
  for Index := 0 to High(FontOffsets) do
    Offsets[FontsId + Index] := Position + FontOffsets[Index];
  Index := Length(Result);
  Result := Result + 'xref' + #10 + '0 ' + IntToStr(ObjectCount) + #10 + '0000000000 65535 f ' + #10;
  for ObjectCount := 1 to High(Offsets) do
    Result := Result + Format('%.10d 00000 n ', [Offsets[ObjectCount]]) + #10;
  Result := Result + 'trailer' + #10 + '<< /Size ' + IntToStr(Length(Offsets)) + ' /Root 1 0 R >>' + #10 + 'startxref' + #10 +
    IntToStr(Index) + #10 + '%%EOF' + #10;
end;

end.
