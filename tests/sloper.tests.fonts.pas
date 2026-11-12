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

// Note fonts (annotations stage 3): the font, bold and italic in pattern and
// layout files, finding and measuring fonts, cutting a font down to its
// glyphs, embedding it in PDF, naming it in SVG, and the warning for a font
// that prints in the default font. Uses the bundled fonts, so it gives the
// same result on every machine.
unit Sloper.Tests.Fonts;

{$mode ObjFPC}{$H+}

interface

uses
  SysUtils, fpcunit, testregistry, Sloper.Tests.TestCase, Sloper.Core.Pattern, Sloper.Core.Note;

type
  TTestFonts = class(TOSTestCase)
  private
    FPattern: TPattern;
    function AddNote: TNoteObject;
    function PDFOf(const AText: string; const Style: TTextStyle): rawbytestring;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestStyleRoundTrip;
    procedure TestDefaultStyleNotWritten;
    procedure TestFontNameChecked;
    procedure TestLoadRefusesBadFont;
    procedure TestSheetNoteStyleRoundTrip;
    procedure TestFindsBundledFont;
    procedure TestMissingFont;
    procedure TestMeasuresNamedFont;
    procedure TestBoldEstimateWider;
    procedure TestCodePoints;
    procedure TestSubsetKeepsGlyphNumbers;
    procedure TestSubsetIsStable;
    procedure TestPDFDefaultFontIsHelvetica;
    procedure TestPDFHelveticaStyles;
    procedure TestPDFEmbedsNamedFont;
    procedure TestPDFDrawsMissingStyle;
    procedure TestPDFNonLatinEmbedsBundledFont;
    procedure TestPDFMissingFontFallsBack;
    procedure TestPDFIsStable;
    procedure TestSVGNamesFont;
    procedure TestLayoutWarnsOnce;
  end;

implementation

uses
  Classes, fpparsettf, Sloper.Core.AppPaths, Sloper.Core.PatternFile, Sloper.Core.TextFields, Sloper.Output.Fonts, Sloper.Output.FontSubset,
  Sloper.Output.PDFWriter, Sloper.Output.DraftSVG, Sloper.Output.Layout;

const
  BUNDLED_FAMILY = 'DejaVu Sans';
  MISSING_FAMILY = 'No Such Font Xyzzy';
  NOTE_PATTERN_HEAD = '{"format": "pattern", "version": 1, "objects": [' +
    '{"id": 1, "type": "note", "name": "N", "x": "0", "y": "0", "text": "x"';

function StyleOf(const AFont: string; ABold, AItalic: boolean): TTextStyle;
begin
  Result := Default(TTextStyle);
  Result.Font := AFont;
  Result.Bold := ABold;
  Result.Italic := AItalic;
end;

function Contains(const Text, Part: rawbytestring): boolean;
begin
  Result := Pos(Part, Text) > 0;
end;

// Only the bundled fonts, whatever the machine has installed
procedure TTestFonts.SetUp;
begin
  FPattern := TPattern.Create;
  UseFontFolders([TAppPaths.FontDir]);
end;

procedure TTestFonts.TearDown;
begin
  UseFontFolders(nil);
  FreeAndNil(FPattern);
end;

function TTestFonts.AddNote: TNoteObject;
begin
  Result := FPattern.AddNote('', 'Hem', naFree, '', '', '5', '6');
  AssertNotNull(FPattern.LastError, Result);
end;

function TTestFonts.PDFOf(const AText: string; const Style: TTextStyle): rawbytestring;
var
  Writer: TPDFWriter;
begin
  Writer := TPDFWriter.Create;
  try
    Writer.BeginPage(100, 100);
    Writer.Text(10, 20, 12, AText, Style);
    Result := Writer.Finish;
  finally
    FreeAndNil(Writer);
  end;
end;

procedure TTestFonts.TestStyleRoundTrip;
var
  Loaded: TPattern;
  Text, Err: string;
  Note: TNoteObject;
begin
  AssertTrue(FPattern.LastError, FPattern.SetNoteStyle(AddNote, StyleOf('Georgia', True, True)));
  Text := SavePatternToText(FPattern);
  AssertTrue(Text, Contains(Text, '"font": "Georgia"'));
  Loaded := TPattern.Create;
  try
    AssertTrue(Err, LoadPatternFromText(Loaded, Text, Err));
    Note := TNoteObject(Loaded.FindObject('Note'));
    AssertEquals('font', 'Georgia', Note.Style.Font);
    AssertTrue('bold', Note.Style.Bold);
    AssertTrue('italic', Note.Style.Italic);
    AssertEquals('same again', Text, SavePatternToText(Loaded));
  finally
    FreeAndNil(Loaded);
  end;
end;

procedure TTestFonts.TestDefaultStyleNotWritten;
var
  Text: string;
begin
  AddNote;
  Text := SavePatternToText(FPattern);
  AssertFalse('font', Contains(Text, '"font"'));
  AssertFalse('bold', Contains(Text, '"bold"'));
  AssertFalse('italic', Contains(Text, '"italic"'));
end;

procedure TTestFonts.TestFontNameChecked;
var
  Note: TNoteObject;
begin
  Note := AddNote;
  AssertTrue('trimmed', FPattern.SetNoteStyle(Note, StyleOf('  Noto Sans ', False, False)));
  AssertEquals('Noto Sans', Note.Style.Font);
  AssertFalse('two families', FPattern.SetNoteStyle(Note, StyleOf('Arial, Helvetica', False, False)));
  AssertTrue(FPattern.LastError, Pos(',', FPattern.LastError) > 0);
  AssertFalse('a quote', FPattern.SetNoteStyle(Note, StyleOf('Bad"Name', False, False)));
  AssertFalse('a line break', FPattern.SetNoteStyle(Note, StyleOf('Two' + #10 + 'Lines', False, False)));
  AssertFalse('too long', FPattern.SetNoteStyle(Note, StyleOf(StringOfChar('a', MAX_FONT_NAME_LENGTH + 1), False, False)));
  AssertEquals('kept after a refusal', 'Noto Sans', Note.Style.Font);
  AssertTrue('back to the default', FPattern.SetNoteStyle(Note, StyleOf('', False, False)));
  AssertEquals('', Note.Style.Font);
end;

procedure TTestFonts.TestLoadRefusesBadFont;
var
  Loaded: TPattern;
  Err: string;
begin
  Loaded := TPattern.Create;
  try
    AssertFalse('two families', LoadPatternFromText(Loaded, NOTE_PATTERN_HEAD + ', "font": "A, B"}]}', Err));
    AssertFalse('not a string', LoadPatternFromText(Loaded, NOTE_PATTERN_HEAD + ', "font": 3}]}', Err));
    AssertFalse('bold not a flag', LoadPatternFromText(Loaded, NOTE_PATTERN_HEAD + ', "bold": "yes"}]}', Err));
    AssertTrue(Err, LoadPatternFromText(Loaded, NOTE_PATTERN_HEAD + ', "font": "Noto Sans", "italic": true}]}', Err));
    AssertTrue('italic', TNoteObject(Loaded.FindObject('N')).Style.Italic);
  finally
    FreeAndNil(Loaded);
  end;
end;

procedure TTestFonts.TestSheetNoteStyleRoundTrip;
var
  Layout, Loaded: TLayout;
  Text, Err: string;
  Index: integer;
begin
  Layout := nil;
  Loaded := nil;
  try
    Layout := TLayout.Create;
    Index := Layout.AddNote('Cut 2', 10, 10, 12);
    Layout.Notes[Index].Style := StyleOf(BUNDLED_FAMILY, True, False);
    Text := Layout.SaveToText;
    AssertTrue(Text, Contains(Text, '"font": "' + BUNDLED_FAMILY + '"'));
    Loaded := TLayout.Create;
    AssertTrue(Err, Loaded.LoadFromText(Text, Err));
    AssertTrue('same style', SameTextStyle(Layout.Notes[Index].Style, Loaded.Notes[0].Style));
    AssertEquals('same again', Text, Loaded.SaveToText);
    AssertFalse('a bad name is refused', Loaded.LoadFromText(StringReplace(Text, BUNDLED_FAMILY, 'A;B', []), Err));
  finally
    FreeAndNil(Loaded);
    FreeAndNil(Layout);
  end;
end;

procedure TTestFonts.TestFindsBundledFont;
var
  Face: TFontFace;
begin
  AssertTrue('found', FindFontFace(StyleOf(BUNDLED_FAMILY, False, False), Face) = flFound);
  AssertTrue('the bundled file', Pos('DejaVuSans.ttf', Face.FileName) > 0);
  AssertFalse('regular', Face.Bold);
  AssertEquals('PDF name', 'DejaVuSans', Face.PostScriptName);
  AssertEquals('no problem', '', FontProblem(StyleOf(BUNDLED_FAMILY, False, False)));
  // Only the regular face is bundled; bold is drawn from it
  AssertTrue('bold found', FindFontFace(StyleOf('dejavu sans', True, False), Face) = flFound);
  AssertFalse('as the regular face', Face.Bold);
  AssertNotNull('bundled for the default font', BundledFontFace);
  AssertEquals('no glyph past its map', 0, Face.GlyphOf($10FFFF));
end;

procedure TTestFonts.TestMissingFont;
var
  Face: TFontFace;
begin
  AssertTrue('missing', FindFontFace(StyleOf(MISSING_FAMILY, False, False), Face) = flMissing);
  AssertNull('no face', Face);
  AssertTrue(FontProblem(StyleOf(MISSING_FAMILY, False, False)), Pos(MISSING_FAMILY, FontProblem(StyleOf(MISSING_FAMILY, False, False))) > 0);
  AssertEquals('the default font is never a problem', '', FontProblem(Default(TTextStyle)));
  AssertTrue('no name, no search', FindFontFace(Default(TTextStyle), Face) = flMissing);
end;

// DejaVu Sans is wider than the Helvetica estimate
procedure TTestFonts.TestMeasuresNamedFont;
var
  Face: TFontFace;
  Measured: double;
begin
  AssertTrue(FindFontFace(StyleOf(BUNDLED_FAMILY, False, False), Face) = flFound);
  Measured := TextWidth('Hello', 10, StyleOf(BUNDLED_FAMILY, False, False));
  AssertNear('from the font', Face.TextWidth('Hello', 10), Measured);
  AssertTrue('not the estimate', Abs(Measured - TextWidth('Hello', 10)) > 0.1);
  AssertNear('the default is estimated', TextWidth('Hello', 10), TextWidth('Hello', 10, Default(TTextStyle)));
  AssertNear('a missing font is estimated', TextWidth('Hello', 10), TextWidth('Hello', 10, StyleOf(MISSING_FAMILY, False, False)));
  AssertNear('widths add up', Face.TextWidth('He', 10) + Face.TextWidth('llo', 10), Measured);
end;

procedure TTestFonts.TestBoldEstimateWider;
begin
  AssertTrue(TextWidth('Hello', 10, StyleOf('', True, False)) > TextWidth('Hello', 10));
end;

procedure TTestFonts.TestCodePoints;
var
  Points: TCodePointArray;
begin
  Points := TextCodePoints('aé日😀');
  AssertEquals('count', 4, Length(Points));
  AssertEquals('a', int64(Ord('a')), int64(Points[0]));
  AssertEquals('é', int64($E9), int64(Points[1]));
  AssertEquals('日', int64($65E5), int64(Points[2]));
  AssertEquals('past the BMP, joined', int64($1F600), int64(Points[3]));
end;

procedure TTestFonts.TestSubsetKeepsGlyphNumbers;
var
  Face: TFontFace;
  Data, Subset: rawbytestring;
  Info: TTFFileInfo;
  Stream: TStringStream;
begin
  AssertTrue(FindFontFace(StyleOf(BUNDLED_FAMILY, False, False), Face) = flFound);
  Data := Face.FileData;
  AssertTrue('subset', SubsetTrueType(Data, [Face.GlyphOf(Ord('A')), Face.GlyphOf(Ord('b'))], Subset));
  AssertTrue('much smaller', Length(Subset) * 4 < Length(Data));
  AssertTrue('still TrueType', HasTrueTypeOutlines(Subset));
  Info := TTFFileInfo.Create;
  Stream := TStringStream.Create(Subset);
  try
    Info.LoadFromStream(Stream);
    AssertEquals('every glyph number kept', integer(Face.Info.MaxP.numGlyphs), integer(Info.MaxP.numGlyphs));
    AssertEquals('widths kept', integer(Face.Info.GetAdvanceWidth(Face.GlyphOf(Ord('A')))), integer(Info.GetAdvanceWidth(Face.GlyphOf(Ord('A')))));
  finally
    FreeAndNil(Stream);
    FreeAndNil(Info);
  end;
  AssertFalse('not a font', SubsetTrueType('not a font', [1], Subset));
end;

procedure TTestFonts.TestSubsetIsStable;
var
  Face: TFontFace;
  First, Second: rawbytestring;
begin
  AssertTrue(FindFontFace(StyleOf(BUNDLED_FAMILY, False, False), Face) = flFound);
  AssertTrue(SubsetTrueType(Face.FileData, [Face.GlyphOf(Ord('x'))], First));
  AssertTrue(SubsetTrueType(Face.FileData, [Face.GlyphOf(Ord('x'))], Second));
  AssertTrue('same bytes', First = Second);
end;

// So files written before fonts stay as they were
procedure TTestFonts.TestPDFDefaultFontIsHelvetica;
var
  Bytes: rawbytestring;
begin
  Bytes := PDFOf('Plain é', Default(TTextStyle));
  AssertTrue(Bytes, Contains(Bytes, '/F1 12 Tf'));
  AssertTrue(Bytes, Contains(Bytes, '/Resources << /Font << /F1 3 0 R >> >>'));
  AssertFalse('nothing embedded', Contains(Bytes, '/FontFile2'));
end;

procedure TTestFonts.TestPDFHelveticaStyles;
var
  Bytes: rawbytestring;
begin
  Bytes := PDFOf('Bold', StyleOf('', True, False));
  AssertTrue(Bytes, Contains(Bytes, '/BaseFont /Helvetica-Bold '));
  AssertTrue(Bytes, Contains(Bytes, '/F2 12 Tf'));
  Bytes := PDFOf('Both', StyleOf('', True, True));
  AssertTrue(Bytes, Contains(Bytes, '/BaseFont /Helvetica-BoldOblique '));
  Bytes := PDFOf('Italic', StyleOf('', False, True));
  AssertTrue(Bytes, Contains(Bytes, '/BaseFont /Helvetica-Oblique '));
end;

procedure TTestFonts.TestPDFEmbedsNamedFont;
var
  Bytes: rawbytestring;
  Face: TFontFace;
begin
  AssertTrue(FindFontFace(StyleOf(BUNDLED_FAMILY, False, False), Face) = flFound);
  Bytes := PDFOf('Ab', StyleOf(BUNDLED_FAMILY, False, False));
  AssertTrue('a CID font', Contains(Bytes, '/Subtype /CIDFontType2'));
  AssertTrue('a subset of it', Contains(Bytes, '+DejaVuSans '));
  AssertTrue('its file', Contains(Bytes, '/FontFile2 '));
  AssertTrue('copy and paste', Contains(Bytes, '/ToUnicode '));
  AssertTrue('glyphs by number', Contains(Bytes, '<' + IntToHex(Face.GlyphOf(Ord('A')), 4) + IntToHex(Face.GlyphOf(Ord('b')), 4) + '> Tj'));
  AssertTrue('A maps back', Contains(Bytes, '<' + IntToHex(Face.GlyphOf(Ord('A')), 4) + '> <0041>'));
  AssertTrue('its width', Contains(Bytes, IntToStr(Face.GlyphOf(Ord('A'))) + ' [' + IntToStr(Face.GlyphWidth(Face.GlyphOf(Ord('A')))) + ']'));
  AssertTrue('Helvetica stays first', Contains(Bytes, '/F1 3 0 R /F2 '));
  AssertFalse('no drawn bold', Contains(Bytes, ' 2 Tr '));
end;

procedure TTestFonts.TestPDFDrawsMissingStyle;
var
  Bytes: rawbytestring;
begin
  Bytes := PDFOf('Ab', StyleOf(BUNDLED_FAMILY, True, True));
  AssertTrue('stroked and filled', Contains(Bytes, ' Tf 2 Tr '));
  AssertTrue('slanted', Contains(Bytes, '1 0 0.213 1 '));
  AssertTrue('in its own state', Contains(Bytes, ' Tj ET Q'));
end;

procedure TTestFonts.TestPDFNonLatinEmbedsBundledFont;
var
  Bytes: rawbytestring;
begin
  Bytes := PDFOf('Привет', Default(TTextStyle));
  AssertTrue('the bundled font', Contains(Bytes, '+NotoSans-Regular '));
  AssertFalse('no question marks', Contains(Bytes, '(??????)'));
  AssertTrue('П maps back', Contains(Bytes, '<041F>'));
end;

procedure TTestFonts.TestPDFMissingFontFallsBack;
var
  Bytes: rawbytestring;
begin
  Bytes := PDFOf('Hem', StyleOf(MISSING_FAMILY, True, False));
  AssertTrue('Helvetica, bold', Contains(Bytes, '/BaseFont /Helvetica-Bold '));
  AssertFalse('nothing embedded', Contains(Bytes, '/FontFile2'));
end;

procedure TTestFonts.TestPDFIsStable;
begin
  AssertTrue('same bytes', PDFOf('Same Привет', StyleOf(BUNDLED_FAMILY, False, False)) = PDFOf('Same Привет', StyleOf(BUNDLED_FAMILY, False, False)));
end;

procedure TTestFonts.TestSVGNamesFont;
begin
  AssertEquals('default', 'font-family="Helvetica, Arial, sans-serif"', NoteFontAttributes(Default(TTextStyle)));
  AssertEquals('named and styled', 'font-family="''Noto Sans'', Helvetica, Arial, sans-serif" font-weight="bold" font-style="italic"',
    NoteFontAttributes(StyleOf('Noto Sans', True, True)));
end;

procedure TTestFonts.TestLayoutWarnsOnce;
var
  Layout: TLayout;
  Problem: TLayoutProblem;
  Count, Index: integer;
begin
  Layout := TLayout.Create;
  try
    Index := Layout.AddNote('One', 0, 0, 12);
    Layout.Notes[Index].Style := StyleOf(MISSING_FAMILY, False, False);
    Index := Layout.AddNote('Two', 0, 50, 12);
    Layout.Notes[Index].Style := StyleOf(MISSING_FAMILY, False, False);
    Index := Layout.AddNote('Three', 0, 100, 12);
    Layout.Notes[Index].Style := StyleOf(BUNDLED_FAMILY, False, False);
    Count := 0;
    for Problem in Layout.Problems do
      if Pos(MISSING_FAMILY, Problem.Text) > 0 then
      begin
        Inc(Count);
        AssertFalse('a warning', Problem.Blocking);
      end
      else
        AssertTrue(Problem.Text, Pos(BUNDLED_FAMILY, Problem.Text) = 0);
    AssertEquals('once', 1, Count);
  finally
    FreeAndNil(Layout);
  end;
end;

initialization
  RegisterTest(TTestFonts);

end.
