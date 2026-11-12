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

// The fonts notes print in. A family is looked for in the bundled fonts
// (data/fonts) first, so tests and the default font give the same result
// everywhere, then in the system's font folders, which FCL's fpttf cache
// lists. A face is read with fpttf's TrueType parser, for its glyphs and
// widths. Using this unit measures named fonts for Sloper.Core.TextFields.
// No LCL dependency.
unit Sloper.Output.Fonts;

{$mode ObjFPC}{$H+}

interface

uses
  SysUtils, fpparsettf, Sloper.Core.Note;

type
  // What became of a font asked for: found and embeddable, or why it prints
  // in the default font instead
  TFontLookup = (flFound, flMissing, flPostScriptOutlines, flNotEmbeddable);

  TCodePointArray = array of cardinal;

  // One font file, read
  TFontFace = class
  private
    FFileName, FPostScriptName: string;
    FInfo: TTFFileInfo;
    FBold, FItalic: boolean;
  public
    // Takes AInfo, read from AFileName
    constructor Create(const AFileName: string; AInfo: TTFFileInfo; ABold, AItalic: boolean);
    destructor Destroy; override;
    // 0, the missing glyph, when the font has none for it
    function GlyphOf(CodePoint: cardinal): word;
    // In thousandths of the font's size
    function GlyphWidth(Glyph: word): integer;
    // In mm, at Size points
    function TextWidth(const Text: string; Size: double): double;
    // The file's bytes; empty when it can no longer be read
    function FileData: rawbytestring;
    property FileName: string read FFileName;
    // Letters, digits and hyphens only, so it can be a PDF name
    property PostScriptName: string read FPostScriptName;
    property Info: TTFFileInfo read FInfo;
    // The face's own style; a style it lacks is drawn by the PDF writer
    property Bold: boolean read FBold;
    property Italic: boolean read FItalic;
  end;

// The face for Style's family, nearest its bold and italic; Face is nil unless
// flFound. Style's font must not be empty. The face is kept for later calls.
function FindFontFace(const Style: TTextStyle; out Face: TFontFace): TFontLookup;
// The first bundled font, for text in the default font that Helvetica cannot
// print; nil when data/fonts has none
function BundledFontFace: TFontFace;
// Why text in Style prints in the default font instead; empty when it prints
// as asked, or asks for the default font
function FontProblem(const Style: TTextStyle): string;
// Looks only in Folders from here on, for tests; nil goes back to the bundled
// and system folders. Faces already found stay valid.
procedure UseFontFolders(const Folders: TStringArray);
// Text as Unicode code points, surrogate pairs joined
function TextCodePoints(const Text: string): TCodePointArray;

resourcestring
  rsFontMissing = 'The font %s is not installed, so text in it prints in the default font';
  rsFontPostScript = 'The font %s has PostScript (CFF) outlines, which cannot be embedded, so text in it prints in the default font';
  rsFontNotEmbeddable = 'The font %s does not allow embedding, so text in it prints in the default font';

implementation

uses
  Classes, SyncObjs, Generics.Collections, fpttf, Sloper.Core.AppPaths, Sloper.Core.TextFields, Sloper.Output.FontSubset;

type
  // A font file in the folders, read once on first need
  TFontFile = record
    Path: string;
    // Squashed file name, to try likely files first
    Hint: string;
    Read, Usable: boolean;
    Family: string;
    Bold, Italic, TrueType, Embeddable: boolean;
  end;

  TFontFileArray = array of TFontFile;

  TFoundFont = record
    Lookup: TFontLookup;
    Face: TFontFace;
  end;

  TFoundFonts = specialize TDictionary<string, TFoundFont>;
  TFaceList = specialize TObjectList<TFontFace>;

const
  // fsSelection bits in OS/2, and macStyle bits in head
  SELECTION_ITALIC = $0001;
  SELECTION_BOLD = $0020;
  SELECTION_OBLIQUE = $0200;
  MAC_BOLD = $0001;
  MAC_ITALIC = $0002;
  // The bundled fonts, best first
  BUNDLED_FILES: array[0..1] of string = ('NotoSans-Regular.ttf', 'DejaVuSans.ttf');
  // Unicode's surrogates, which UTF-16 pairs for code points past $FFFF
  HIGH_SURROGATE_FIRST = $D800;
  HIGH_SURROGATE_LAST = $DBFF;
  LOW_SURROGATE_FIRST = $DC00;
  LOW_SURROGATE_LAST = $DFFF;
  SUPPLEMENTARY_FIRST = $10000;
  SURROGATE_BITS = 10;
  // The largest code point a TrueType cmap format 4 table maps
  BMP_LAST = $FFFF;
  MILLE = 1000;
  GLYF_TABLE = 'glyf';
  LOCA_TABLE = 'loca';

var
  Lock: TCriticalSection;
  Indexed: boolean;
  Files: TFontFileArray;
  Found: TFoundFonts;
  Faces: TFaceList;
  Bundled: TFontFace;
  BundledLooked: boolean;
  ChosenFolders: TStringArray;
  FoldersChosen: boolean;

function SafePostScriptName(const AName: string): string;
var
  Letter: char;
begin
  Result := '';
  for Letter in AName do
    if Letter in ['A'..'Z', 'a'..'z', '0'..'9', '-'] then
      Result := Result + Letter;
  if Result = '' then
    Result := 'Font';
end;

// Lower case, without spaces, hyphens or underscores
function Squashed(const Text: string): string;
var
  Letter: char;
begin
  Result := '';
  for Letter in LowerCase(Text) do
    if not (Letter in [' ', '-', '_']) then
      Result := Result + Letter;
end;

function TextCodePoints(const Text: string): TCodePointArray;
var
  Wide: unicodestring;
  Index, Count: integer;
  Code: cardinal;
begin
  Result := nil;
  Wide := UTF8Decode(Text);
  SetLength(Result, Length(Wide));
  Count := 0;
  Index := 1;
  while Index <= Length(Wide) do
  begin
    Code := Ord(Wide[Index]);
    if (Code >= HIGH_SURROGATE_FIRST) and (Code <= HIGH_SURROGATE_LAST) and (Index < Length(Wide)) and
      (Ord(Wide[Index + 1]) >= LOW_SURROGATE_FIRST) and (Ord(Wide[Index + 1]) <= LOW_SURROGATE_LAST) then
    begin
      Code := SUPPLEMENTARY_FIRST + ((Code - HIGH_SURROGATE_FIRST) shl SURROGATE_BITS) + (Ord(Wide[Index + 1]) - LOW_SURROGATE_FIRST);
      Inc(Index);
    end;
    Result[Count] := Code;
    Inc(Count);
    Inc(Index);
  end;
  SetLength(Result, Count);
end;

{ TFontFace }

constructor TFontFace.Create(const AFileName: string; AInfo: TTFFileInfo; ABold, AItalic: boolean);
begin
  FFileName := AFileName;
  FInfo := AInfo;
  FBold := ABold;
  FItalic := AItalic;
  FPostScriptName := SafePostScriptName(AInfo.PostScriptName);
end;

destructor TFontFace.Destroy;
begin
  FreeAndNil(FInfo);
  inherited Destroy;
end;

function TFontFace.GlyphOf(CodePoint: cardinal): word;
begin
  // A font without a Unicode cmap has no Chars at all
  if (CodePoint > BMP_LAST) or (CodePoint >= cardinal(Length(FInfo.Chars))) then
    Exit(0);
  Result := FInfo.Chars[CodePoint];
end;

function TFontFace.GlyphWidth(Glyph: word): integer;
begin
  if (Length(FInfo.Widths) = 0) or (FInfo.Head.UnitsPerEm = 0) then
    Exit(0);
  Result := Round(FInfo.GetAdvanceWidth(Glyph) * MILLE / FInfo.Head.UnitsPerEm);
end;

function TFontFace.TextWidth(const Text: string; Size: double): double;
var
  CodePoint: cardinal;
  Units: int64;
begin
  if (Length(FInfo.Widths) = 0) or (FInfo.Head.UnitsPerEm = 0) then
    Exit(0);
  Units := 0;
  for CodePoint in TextCodePoints(Text) do
    Inc(Units, FInfo.GetAdvanceWidth(GlyphOf(CodePoint)));
  Result := Units / FInfo.Head.UnitsPerEm * Size * POINTS_TO_MM;
end;

function TFontFace.FileData: rawbytestring;
var
  Stream: TFileStream;
begin
  Result := '';
  try
    Stream := TFileStream.Create(FFileName, fmOpenRead or fmShareDenyNone);
    try
      SetLength(Result, Stream.Size);
      if Stream.Size > 0 then
        Stream.ReadBuffer(Result[1], Stream.Size);
    finally
      FreeAndNil(Stream);
    end;
  except
    on EStreamError do
      Result := '';
  end;
end;

// Every font file in the folders, the bundled ones first, each folder's in
// name order, so the same files are always tried in the same order
procedure IndexFonts;
var
  Folders: TStringArray;
  Folder: string;
  Cache: TFPFontCacheList;
  Names: TStringList;
  Index: integer;
begin
  if Indexed then
    Exit;
  Indexed := True;
  Files := nil;
  if FoldersChosen then
    Folders := ChosenFolders
  else
    Folders := Concat([TAppPaths.FontDir], TAppPaths.SystemFontDirs);
  for Folder in Folders do
  begin
    if (Folder = '') or not DirectoryExists(Folder) then
      Continue;
    Cache := nil;
    Names := nil;
    try
      Cache := TFPFontCacheList.Create;
      Names := TStringList.Create;
      Cache.SearchPath.Add(Folder);
      try
        Cache.BuildFontCache;
      except
        // A folder that cannot be listed adds nothing
        on Exception do ;
      end;
      for Index := 0 to Cache.Count - 1 do
        Names.Add(Cache.Items[Index].FileName);
      Names.Sort;
      for Index := 0 to Names.Count - 1 do
      begin
        SetLength(Files, Length(Files) + 1);
        Files[High(Files)] := Default(TFontFile);
        Files[High(Files)].Path := Names[Index];
        Files[High(Files)].Hint := Squashed(ExtractFileName(Names[Index]));
      end;
    finally
      FreeAndNil(Names);
      FreeAndNil(Cache);
    end;
  end;
end;

// The style a face says it has, from OS/2 or else head
procedure FaceStyle(Info: TTFFileInfo; out ABold, AItalic: boolean);
begin
  ABold := (Info.OS2Data.fsSelection and SELECTION_BOLD <> 0) or (Info.Head.MacStyle and MAC_BOLD <> 0);
  AItalic := (Info.OS2Data.fsSelection and (SELECTION_ITALIC or SELECTION_OBLIQUE) <> 0) or (Info.Head.MacStyle and MAC_ITALIC <> 0);
end;

// Reads a file's names and style; one fpttf cannot read is never usable
function ReadInfo(const Path: string): TTFFileInfo;
begin
  Result := TTFFileInfo.Create;
  try
    Result.LoadFromFile(Path);
  except
    FreeAndNil(Result);
  end;
end;

procedure ReadFile(var Entry: TFontFile);
var
  Info: TTFFileInfo;
  Table: TTableDirectoryEntry;
begin
  if Entry.Read then
    Exit;
  Entry.Read := True;
  Info := ReadInfo(Entry.Path);
  if not Assigned(Info) then
    Exit;
  try
    Entry.Family := Info.FamilyName;
    FaceStyle(Info, Entry.Bold, Entry.Italic);
    Entry.Embeddable := Info.Embeddable;
    Entry.Usable := (Entry.Family <> '') and (Length(Info.Widths) > 0) and (Info.Head.UnitsPerEm > 0);
    // An OpenType font with PostScript outlines has CFF in place of glyf
    Table := Default(TTableDirectoryEntry);
    Entry.TrueType := Info.GetTableDirEntry(GLYF_TABLE, Table) and Info.GetTableDirEntry(LOCA_TABLE, Table);
  finally
    FreeAndNil(Info);
  end;
end;

// How near a face comes to the style asked for: bold counts most
function StyleScore(const Entry: TFontFile; ABold, AItalic: boolean): integer;
begin
  Result := 0;
  if Entry.Bold = ABold then
    Inc(Result, 2);
  if Entry.Italic = AItalic then
    Inc(Result);
end;

// The best face of Family among the files read so far; -1 when none
function BestFile(const Family: string; ABold, AItalic: boolean): integer;
var
  Index, Score, BestScore: integer;
begin
  Result := -1;
  BestScore := -1;
  for Index := 0 to High(Files) do
    if Files[Index].Read and Files[Index].Usable and SameText(Files[Index].Family, Family) then
    begin
      Score := StyleScore(Files[Index], ABold, AItalic);
      if Score > BestScore then
      begin
        Result := Index;
        BestScore := Score;
      end;
    end;
end;

// Files named like the family are read first; the rest only when they hold
// no face of the exact style
function FindFile(const Family: string; ABold, AItalic: boolean): integer;
var
  Index: integer;
  Hint: string;
begin
  IndexFonts;
  Hint := Squashed(Family);
  for Index := 0 to High(Files) do
    if Pos(Hint, Files[Index].Hint) > 0 then
      ReadFile(Files[Index]);
  Result := BestFile(Family, ABold, AItalic);
  if (Result >= 0) and (StyleScore(Files[Result], ABold, AItalic) = 3) then
    Exit;
  for Index := 0 to High(Files) do
    ReadFile(Files[Index]);
  Result := BestFile(Family, ABold, AItalic);
end;

// The face for a file, read again in full and kept
function FaceFor(const Entry: TFontFile): TFontFace;
var
  Info: TTFFileInfo;
begin
  for Result in Faces do
    if Result.FileName = Entry.Path then
      Exit;
  Result := nil;
  Info := ReadInfo(Entry.Path);
  if not Assigned(Info) then
    Exit;
  Result := TFontFace.Create(Entry.Path, Info, Entry.Bold, Entry.Italic);
  Faces.Add(Result);
end;

function Lookup(const Style: TTextStyle): TFoundFont;
var
  Key: string;
  Index: integer;
begin
  Key := LowerCase(Style.Font) + '|' + BoolToStr(Style.Bold, True) + '|' + BoolToStr(Style.Italic, True);
  if Found.TryGetValue(Key, Result) then
    Exit;
  Result.Face := nil;
  Result.Lookup := flMissing;
  Index := FindFile(Style.Font, Style.Bold, Style.Italic);
  if Index >= 0 then
  begin
    if not Files[Index].TrueType then
      Result.Lookup := flPostScriptOutlines
    else if not Files[Index].Embeddable then
      Result.Lookup := flNotEmbeddable
    else
    begin
      Result.Face := FaceFor(Files[Index]);
      if Assigned(Result.Face) then
        Result.Lookup := flFound;
    end;
  end;
  Found.Add(Key, Result);
end;

function FindFontFace(const Style: TTextStyle; out Face: TFontFace): TFontLookup;
var
  Answer: TFoundFont;
begin
  Face := nil;
  // Would read every font file looking for a family with no name
  if Style.Font = '' then
    Exit(flMissing);
  Lock.Enter;
  try
    Answer := Lookup(Style);
  finally
    Lock.Leave;
  end;
  Face := Answer.Face;
  Result := Answer.Lookup;
end;

function BundledFontFace: TFontFace;
var
  Folder, FileName: string;
  Info: TTFFileInfo;
  Entry: TFontFile;
begin
  Lock.Enter;
  try
    if not BundledLooked then
    begin
      BundledLooked := True;
      Folder := TAppPaths.FontDir;
      for FileName in BUNDLED_FILES do
      begin
        if (Folder = '') or not FileExists(ConcatPaths([Folder, FileName])) then
          Continue;
        Entry := Default(TFontFile);
        Entry.Path := ConcatPaths([Folder, FileName]);
        ReadFile(Entry);
        if not Entry.Usable or not Entry.TrueType then
          Continue;
        Info := ReadInfo(Entry.Path);
        if not Assigned(Info) then
          Continue;
        Bundled := TFontFace.Create(Entry.Path, Info, Entry.Bold, Entry.Italic);
        Faces.Add(Bundled);
        Break;
      end;
    end;
    Result := Bundled;
  finally
    Lock.Leave;
  end;
end;

procedure UseFontFolders(const Folders: TStringArray);
begin
  Lock.Enter;
  try
    ChosenFolders := Copy(Folders);
    FoldersChosen := Length(Folders) > 0;
    Indexed := False;
    Files := nil;
    Found.Clear;
  finally
    Lock.Leave;
  end;
end;

function FontProblem(const Style: TTextStyle): string;
var
  Face: TFontFace;
begin
  Result := '';
  if Style.Font = '' then
    Exit;
  case FindFontFace(Style, Face) of
    flMissing: Result := Format(rsFontMissing, [Style.Font]);
    flPostScriptOutlines: Result := Format(rsFontPostScript, [Style.Font]);
    flNotEmbeddable: Result := Format(rsFontNotEmbeddable, [Style.Font]);
  end;
end;

// A font that prints in the default font is measured as that font is
function MeasureText(const Style: TTextStyle; const Text: string; Size: double; out Width: double): boolean;
var
  Face: TFontFace;
begin
  Width := 0;
  Result := FindFontFace(Style, Face) = flFound;
  if Result then
    Width := Face.TextWidth(Text, Size);
end;

initialization
  Lock := TCriticalSection.Create;
  Found := TFoundFonts.Create;
  Faces := TFaceList.Create;
  SetTextMeasurer(@MeasureText);

finalization
  SetTextMeasurer(nil);
  FreeAndNil(Found);
  FreeAndNil(Faces);
  FreeAndNil(Lock);

end.
