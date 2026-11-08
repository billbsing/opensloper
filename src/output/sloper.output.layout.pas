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

// Layout files (.slayout): which patterns to print and where each copy of
// each piece goes. A layout evaluates its patterns itself, from the saved
// files. Layout space is millimetres from the top left, y down; a placement
// gives the top left of a piece's cutting line once rotated and flipped, so
// it stays put when the piece changes size. The file is described in the
// design document under "Publish app".
unit Sloper.Output.Layout;

{$mode ObjFPC}{$H+}

interface

uses
  SysUtils, Generics.Collections, Sloper.Core.Geometry, Sloper.Core.Materials, Sloper.Core.MachineProfiles, Sloper.Core.OutputProfiles,
  Sloper.Core.Measurements,
  Sloper.Core.Pattern, Sloper.Core.Piece, Sloper.Core.Settings, Sloper.Core.Draft, Sloper.Core.TextFields, Sloper.Core.Note,
  Sloper.Output.Tiling;

const
  LayoutFormat = 'layout';
  LayoutVersion = 1;
  LayoutExtension = '.slayout';
  // The paper name for a size given by hand
  CustomPaper = 'custom';

type
  TLayoutMarks = (lkDiamond, lkNone, lkHalfCircle);
  // lfHatch hatches them, which suits black-and-white printers.
  // lfTint fills pieces with a light tint in print; on projector output, which
  // is dark, it does nothing
  TLayoutFill = (lfNone, lfTint, lfHatch);
  // okTiled prints on pages of paper; okLarge on one sheet off a roll;
  // okProjector is one dark sheet with thick light lines, shown on the material;
  // okMaterial is the material or board itself, cut as the pieces lie
  TOutputKind = (okTiled, okLarge, okProjector, okMaterial);

  TLayoutOutput = record
    Kind: TOutputKind;
    // The width of the sheet for okLarge; its length follows the layout
    RollWidth: double;
    // Captions of the pages not to print
    ExcludedPages: TStringArray;
    Paper: string;
    Tiles: TTileSettings;
    Marks: TLayoutMarks;
    Fill: TLayoutFill;
    // A machine profile's name; empty for plain output
    Profile: string;
    // An output profile's name; empty to print everything
    OutputProfile: string;
    // okMaterial's sheet; MaterialLength is 0 for a roll
    MaterialWidth, MaterialLength: double;
    // Whether packing may turn pieces across a material with no grain
    AllowTurns: boolean;
    // Limits the layout to this material, by name; empty for all
    Material: string;
  end;

  // A pattern file with its measurement set. The stored paths are as written
  // in the layout file; empty MeasurementFile means the one the pattern names.
  TLayoutSource = class
  public
    Id: integer;
    PatternFile, MeasurementFile, Size: string;
    Pattern: TPattern;
    Measurements: TMeasurementSet;
    // Why the source could not be read; empty when it is ready
    LoadError: string;
    // The files read, and their stamps when they were
    PatternPath, MeasurementPath, LoadedStamp: string;
    // The files' stamps now; differs from LoadedStamp once either is saved
    function CurrentStamp: string;
    destructor Destroy; override;
    procedure Unload;
  end;

  TLayoutSourceList = specialize TObjectList<TLayoutSource>;

  TPlacement = record
    SourceId, Copy: integer;
    PieceKey: string;
    X, Y: double;
    Rotation: integer;
    Flipped: boolean;
  end;

  TPlacementArray = array of TPlacement;

  // Text on the layout, with its top left at (X, Y) and Size in points. It may
  // run to several lines, and may hold fields such as {date}. A pattern's
  // callout printed with its piece also has a leader to Tip.
  TSheetNote = record
    Text: string;
    X, Y, Size: double;
    Align: TTextAlign;
    Boxed: boolean;
    Leader: TNoteLeader;
    Tip: TVec2;
  end;

  TSheetNoteArray = array of TSheetNote;

  // A hole in layout space. Machines cut it as one true circle
  TPlacedHole = record
    Centre: TVec2;
    Diameter: double;
  end;

  TPlacedHoleArray = array of TPlacedHole;

  // A marking line in layout space, drawn on paper in its role's style
  TPlacedLine = record
    Role: TEdgeRole;
    Points: TVec2Array;
    // The output profile's look for its role on paper, if it sets one
    Style: TRoleStyle;
  end;

  TPlacedLineArray = array of TPlacedLine;

  // A placed piece in layout space, ready to draw
  TPlacedPiece = record
    Placement: integer;
    Caption: string;
    Look: TPieceLook;
    CutLine, SeamLine: TVec2Array;
    // Grainline, fold, notches and holes as plain strokes, for paper
    Marks: TLine2Array;
    // Marking lines, each whole, for paper and the preview
    Lines: TPlacedLineArray;
    // The marks apart by line type, for machines; see the design document.
    // Cut lines inside the piece are slits, cut with the cutting line.
    MarkLines, ScoreLines, SlitLines: TLine2Array;
    Holes: TPlacedHoleArray;
    LabelAt: TVec2;
    // False when the output profile leaves labels out; Caption still names it
    ShowLabel: boolean;
    Bounds: TRect2;
    // The pattern's notes that print with the piece, upright in layout space
    Notes: TSheetNoteArray;
  end;

  TPlacedPieceArray = array of TPlacedPiece;

  // Which corner of the page the title block sits in. The cover's top left
  // holds the test square, so it is not offered.
  TTitleCorner = (tcBottomRight, tcBottomLeft, tcTopRight);

  TTitleBlock = record
    Enabled: boolean;
    Corner: TTitleCorner;
    // Field names, in the order they print
    Fields: TStringArray;
    // A copy on every tile as well as the cover
    EveryPage: boolean;
  end;

  // Blocking problems stop export; the others are only warnings
  TLayoutProblem = record
    Text: string;
    Blocking: boolean;
    // It says a copy is waiting to be placed, which the window's tray shows
    Unplaced: boolean;
  end;

  // A copy of a piece with no placement yet
  TUnplacedCopy = record
    SourceId, Copy: integer;
    PieceKey: string;
    Caption: string;
    // Failing pieces wait here too, but cannot be placed until they work
    CanPlace: boolean;
  end;

  TUnplacedCopyArray = array of TUnplacedCopy;

  TLayoutProblemArray = array of TLayoutProblem;

  TLayout = class
  private
    FSources: TLayoutSourceList;
    FNextId: integer;
    function ResolvePath(const Stored: string): string;
    procedure LoadSource(Source: TLayoutSource);
    function NewPlacement(const Item: TUnplacedCopy; out Piece: TPieceObject): TPlacement;
    function IsPlaced(SourceId: integer; const PieceKey: string; Copy: integer): boolean;
    procedure AddOverlapProblems(var Problems: TLayoutProblemArray);
    function PageIsExcluded(const Caption: string): boolean;
  public
    Name: string;
    // Where the layout is saved; relative paths start from its folder
    FileName: string;
    Output: TLayoutOutput;
    Placements: TPlacementArray;
    Title: TTitleBlock;
    Notes: TSheetNoteArray;
    // The date to print, as text; empty for today. Not saved.
    PrintDate: string;
    // Known to this user, from the settings. Not saved.
    MachineProfiles: TMachineProfileArray;
    // The user's own, besides the built-in ones, from the settings. Not saved.
    OutputProfiles: TOutputProfileArray;
    // The user's printer, from the settings, since it belongs to the printer
    // rather than the layout. Not saved; older layouts' factors are ignored.
    Calibration: TCalibration;
    constructor Create;
    destructor Destroy; override;
    procedure Clear;
    function AddSource(const APatternFile, AMeasurementFile, ASize: string): TLayoutSource;
    // Takes the source and its placements out
    procedure RemoveSource(Source: TLayoutSource);
    // A path as stored in the layout: relative to its folder when it has one
    function StoredPath(const Path: string): string;
    // Reads and evaluates every source's files
    procedure LoadSources;
    function SaveToText: string;
    function LoadFromText(const Text: string; out ErrorMessage: string): boolean;
    function SaveToFile(const AFileName: string; out ErrorMessage: string): boolean;
    function LoadFromFile(const AFileName: string; out ErrorMessage: string): boolean;
    // Every copy of a piece with no placement yet, by source and piece
    function Unplaced: TUnplacedCopyArray;
    // Adds a placement for each of these that can be placed, in rows below
    // what is already placed. Plain rows, not packing. Returns how many.
    function PlaceCopies(const Copies: TUnplacedCopyArray): integer;
    // PlaceCopies for every copy without a placement
    function PlaceNewPieces: integer;
    // Adds a placement with the copy centred on At, kept on the sheet and
    // rounded to Step. Returns its index, or -1 when it cannot be placed.
    function PlaceCopyAt(const Item: TUnplacedCopy; const At: TVec2; Step: double): integer;
    // Puts a placed copy back among the unplaced
    procedure RemovePlacement(Index: integer);
    function PlacedPieces: TPlacedPieceArray;
    // The source and piece a placement stands for; False when either has gone
    function FindPiece(const Placement: TPlacement; out Source: TLayoutSource; out Piece: TPieceObject): boolean;
    // The pages Shapes need, with the empty ones marked Blank
    function Pages(const Shapes: TPlacedPieceArray; out RowCount, ColumnCount: integer): TTilePageArray;
    // Turns on the usual title block, for a new layout
    procedure UseDefaultTitle;
    // Page and Pages empty leave {page} and {pages} as typed
    function FieldValues(const APage, APages: string): TFieldValues;
    // The title block's lines, each with its caption
    function TitleLines(const Values: TFieldValues): TStringArray;
    // Adds a note, returning its index
    function AddNote(const AText: string; AX, AY, ASize: double): integer;
    procedure RemoveNote(Index: integer);
    // Leaves the page out of the print, or puts it back
    procedure TogglePage(const Caption: string);
    function Problems: TLayoutProblemArray;
    // The layout's machine profile, or Standard if it has none. False when it
    // names one not known, which only stops the exports that need it.
    function ChosenProfile(out Profile: TMachineProfile): boolean;
    // The layout's output profile, or everything if it has none. False when
    // it names one not known, which blocks every export.
    function ChosenOutputProfile(out Profile: TOutputProfile): boolean;
    // Whether pieces are cut as they lie, so fold pieces open out to whole ones
    function OpensFolds: boolean;
    // The chosen output profile, or everything when it has none or is unknown
    function ActiveOutputProfile: TOutputProfile;
    // Whether the piece is on the material the layout is limited to, if any
    function InMaterial(Source: TLayoutSource; Piece: TPieceObject): boolean;
    // How wide a sheet pieces can be laid across; large format and material only
    function UsableWidth: double;
    // For a material sheet, how much of it the pieces take; '' for other kinds
    function MaterialUse: string;
    // The blocking problems as one message, or empty when export can go ahead
    function Refusal: string;
    property Sources: TLayoutSourceList read FSources;
  end;

// The rough area a note's text covers, in layout space
function NoteBounds(const Note: TSheetNote; const Values: TFieldValues): TRect2;
// The same, with its white box when it has one
function NoteFrameBounds(const Note: TSheetNote; const Values: TFieldValues): TRect2;
// Where each line of the note starts across, in layout space
function NoteLineLeft(const Note: TSheetNote; const Values: TFieldValues; const Line: string): double;
// The layout's own notes, then the pattern notes printed with each piece
function PrintedNotes(Layout: TLayout; const Shapes: TPlacedPieceArray): TSheetNoteArray;

// What the publish app should open for a pattern: its layout, when there is
// one beside it, otherwise the pattern itself
function PublishTargetFor(const PatternFile: string): string;
// The width and height of a named paper; False when the name is unknown
function PaperSize(const AName: string; out AWidth, AHeight: double): boolean;
// False with the reason when the file cannot be written
function WriteBytesToFile(const FileName: string; const Bytes: rawbytestring; out ErrorMessage: string): boolean;

resourcestring
  rsLayoutRefused = 'The layout cannot be exported:';
  rsLayoutWrongFormat = 'This is not a layout file';
  rsLayoutNewerVersion = 'This file was made by a newer version of OpenSloper (file version %d)';
  rsLayoutUnits = 'Units "%s" are not supported; use mm';
  rsLayoutList = 'The file has no valid "%s" list';
  rsLayoutBadSource = 'Source %d has a missing, invalid or repeated ID, or no pattern';
  rsLayoutBadPlacement = 'Placement %d is not valid';
  rsLayoutUnknownSource = 'Placement %d uses source %d, which is not in the file';
  rsLayoutBadPaper = 'Paper "%s" is not known; give paperWidth and paperHeight for custom paper';
  rsLayoutBadNextId = '"nextId" must be a whole number above every source ID';
  rsLayoutNoPrintArea = 'The margin and overlap leave nothing to print on';
  rsLayoutNoFile = 'File not found: %s';
  rsLayoutSetAndSize = '%s, size %s';
  rsLayoutSourceProblem = '%s: %s';
  rsLayoutPieceGone = '%s: piece %s no longer exists';
  rsLayoutPieceFailing = '%s: %s cannot be printed: %s';
  rsLayoutOffGrain = '%s: %s is turned %d°; pieces turn in 90° steps, to keep the grainline square to the sheet';
  rsLayoutUnplaced = '%s: %s (copy %d of %d) is not placed';
  rsLayoutNoPieces = '%s has no pieces. Make them in the drafting app and save the pattern';
  rsLayoutNothingPlaced = 'Nothing is placed, so there is nothing to print';
  rsLayoutTrayItem = '%s (copy %d of %d)';
  rsLayoutExtraCopy = '%s: %s is cut %d times now, but copy %d is still placed';
  rsLayoutOverlap = '%s overlaps %s';
  rsLayoutNoteOverlap = 'The note "%s" lies over %s';
  rsTitlePattern = 'Pattern: %s';
  rsTitleMeasurements = 'Measurements: %s';
  rsTitleLayout = 'Layout: %s';
  rsTitleDate = 'Date: %s';
  rsTitleCutList = 'Cut list: %s';
  rsTitleMaterials = 'Materials: %s';
  rsLayoutOffSheet = '%s runs off the sheet';
  rsLayoutPastSheet = '%s runs past the %s by %s mm sheet';
  rsLayoutPastWidth = '%s is wider than the %s mm material';
  rsLayoutNoMaterial = 'No pattern here has a material named %s';
  rsLayoutBadMaterial = 'A material sheet needs a width above 0 and a length of 0 or more';
  rsLayoutRollUsed = 'Uses %s mm of the %s mm wide material';
  rsLayoutSheetUsed = 'Pieces take %s%% of the %s by %s mm sheet';
  rsLayoutUnknownProfile = 'The machine profile %s is not in the settings';
  rsLayoutUnknownOutputProfile = 'The output profile %s is not in the settings, so nothing can be exported';
  rsLayoutCutAcross = '%s: %s lies across the material''s grain here, and a machine would cut it that way';
  rsLayoutProjectedAcross = '%s: %s lies across the material''s grain here. Projected as it is, it would be cut that way';
  rsLayoutWiderThanRoll = '%s runs past the %s mm roll';
  rsLayoutBadRoll = 'The roll is too narrow for its margins';

implementation

uses
  Classes, Math, crc, fpjson, Clipper, Clipper.Core, Sloper.Core.JSON, Sloper.Core.Names, Sloper.Core.EvalTypes, Sloper.Core.PatternFile;

const
  CornerNames: array[TTitleCorner] of string = ('bottomRight', 'bottomLeft', 'topRight');
  DefaultSheetNoteSize = 12;
  DefaultPaper = 'A4';
  DefaultMargin = 6;
  DefaultOverlap = 10;
  MarksNames: array[TLayoutMarks] of string = ('diamond', 'none', 'halfCircle');
  FillNames: array[TLayoutFill] of string = ('none', 'tint', 'hatch');
  KindNames: array[TOutputKind] of string = ('tiled', 'large', 'projector', 'material');
  // 36 inches, a common copy-shop width
  DefaultRollWidth = 914;
  DefaultMaterialWidth = 1500;
  // New rows are this wide before wrapping, and this far apart
  ShelfWidth = 1000;
  ShelfGap = 10;
  SeamFlatness = 0.05;
  // Overlaps smaller than this (in mm²) are rounding, not a problem
  OverlapArea = 1;

function PublishTargetFor(const PatternFile: string): string;
begin
  Result := ChangeFileExt(PatternFile, LayoutExtension);
  if not FileExists(Result) then
    Result := PatternFile;
end;

function PaperSize(const AName: string; out AWidth, AHeight: double): boolean;
begin
  Result := True;
  case AName of
    'A4':
    begin
      AWidth := 210;
      AHeight := 297;
    end;
    'A3':
    begin
      AWidth := 297;
      AHeight := 420;
    end;
    'Letter':
    begin
      AWidth := 215.9;
      AHeight := 279.4;
    end;
    else
    begin
      AWidth := 0;
      AHeight := 0;
      Result := False;
    end;
  end;
end;

function NoteBounds(const Note: TSheetNote; const Values: TFieldValues): TRect2;
var
  Lines: TStringArray;
  Line: string;
  Widest: double;
begin
  Lines := TextLines(ExpandFields(Note.Text, Values));
  Widest := 0;
  for Line in Lines do
    Widest := Max(Widest, TextWidth(Line, Note.Size));
  Result.MinX := Note.X;
  Result.MinY := Note.Y;
  Result.MaxX := Note.X + Widest;
  Result.MaxY := Note.Y + Length(Lines) * LineHeight(Note.Size);
end;

function NoteFrameBounds(const Note: TSheetNote; const Values: TFieldValues): TRect2;
begin
  Result := NoteBounds(Note, Values);
  if Note.Boxed then
    Result := PaddedBox(Result);
end;

function NoteLineLeft(const Note: TSheetNote; const Values: TFieldValues; const Line: string): double;
var
  Box: TRect2;
begin
  Box := NoteBounds(Note, Values);
  Result := AlignedLeft(Box.MinX, Box.MaxX - Box.MinX, TextWidth(Line, Note.Size), Note.Align);
end;

function PrintedNotes(Layout: TLayout; const Shapes: TPlacedPieceArray): TSheetNoteArray;
var
  Shape: TPlacedPiece;
begin
  Result := Copy(Layout.Notes);
  for Shape in Shapes do
    Result := Concat(Result, Shape.Notes);
end;

function DefaultOutput: TLayoutOutput;
begin
  Result := Default(TLayoutOutput);
  Result.Paper := DefaultPaper;
  Result.RollWidth := DefaultRollWidth;
  PaperSize(DefaultPaper, Result.Tiles.PaperWidth, Result.Tiles.PaperHeight);
  Result.Tiles.Margin := DefaultMargin;
  Result.Tiles.Overlap := DefaultOverlap;
  Result.Marks := lkDiamond;
  Result.MaterialWidth := DefaultMaterialWidth;
end;

{ TLayoutSource }

destructor TLayoutSource.Destroy;
begin
  Unload;
  inherited Destroy;
end;

// A checksum of the contents: file times only go to the second, and these
// files are small enough to read each time. '-' when the file cannot be read.
function FileStamp(const Path: string): string;
var
  Text, Reason: string;
begin
  Result := '-';
  if (Path <> '') and FileExists(Path) and ReadTextFile(Path, Text, Reason) then
    Result := IntToStr(crc32(crc32(0, nil, 0), pbyte(PChar(Text)), Length(Text)));
end;

function TLayoutSource.CurrentStamp: string;
begin
  Result := FileStamp(PatternPath) + ' ' + FileStamp(MeasurementPath);
end;

// The pattern reads the measurement set, so it goes first
procedure TLayoutSource.Unload;
begin
  FreeAndNil(Pattern);
  FreeAndNil(Measurements);
end;

{ TLayout }

constructor TLayout.Create;
begin
  FSources := TLayoutSourceList.Create;
  Calibration := NoCalibration;
  Clear;
end;

destructor TLayout.Destroy;
begin
  FreeAndNil(FSources);
  inherited Destroy;
end;

procedure TLayout.Clear;
begin
  FSources.Clear;
  FNextId := 1;
  Name := '';
  Output := DefaultOutput;
  Placements := nil;
  Title := Default(TTitleBlock);
  Notes := nil;
end;

procedure TLayout.UseDefaultTitle;
begin
  Title := Default(TTitleBlock);
  Title.Enabled := True;
  Insert(FieldPatternName, Title.Fields, 0);
  Insert(FieldMeasurementsName, Title.Fields, 1);
  Insert(FieldDate, Title.Fields, 2);
end;

function TLayout.FieldValues(const APage, APages: string): TFieldValues;
var
  Source: TLayoutSource;
  SetName: string;
begin
  Result := Default(TFieldValues);
  Result.LayoutName := Name;
  Result.Page := APage;
  Result.Pages := APages;
  Result.Date := PrintDate;
  if Result.Date = '' then
    Result.Date := FieldDateText;
  for Source in FSources do
  begin
    if Result.PatternName <> '' then
      Result.PatternName := Result.PatternName + ', ';
    Result.PatternName := Result.PatternName + ChangeFileExt(ExtractFileName(Source.PatternFile), '');
    SetName := '';
    if Assigned(Source.Measurements) then
      SetName := Source.Measurements.Name;
    if SetName = '' then
      SetName := ChangeFileExt(ExtractFileName(Source.MeasurementPath), '');
    if Assigned(Source.Measurements) and (Source.Measurements.SizeName <> '') then
      SetName := Format(rsLayoutSetAndSize, [SetName, Source.Measurements.SizeName]);
    if (SetName <> '') and (Pos(SetName, Result.MeasurementsName) = 0) then
    begin
      if Result.MeasurementsName <> '' then
        Result.MeasurementsName := Result.MeasurementsName + ', ';
      Result.MeasurementsName := Result.MeasurementsName + SetName;
    end;
    if not Assigned(Source.Pattern) then
      Continue;
    if (Result.CutList <> '') and (Source.Pattern.CutList <> '') then
      Result.CutList := Result.CutList + ' · ';
    Result.CutList := Result.CutList + Source.Pattern.CutList;
    if Pos(Source.Pattern.MaterialNames, Result.Materials) = 0 then
    begin
      if Result.Materials <> '' then
        Result.Materials := Result.Materials + ', ';
      Result.Materials := Result.Materials + Source.Pattern.MaterialNames;
    end;
  end;
end;

function TLayout.TitleLines(const Values: TFieldValues): TStringArray;
var
  Field, Line: string;
begin
  Result := nil;
  for Field in Title.Fields do
  begin
    case Field of
      FieldPatternName: Line := Format(rsTitlePattern, [Values.PatternName]);
      FieldMeasurementsName: Line := Format(rsTitleMeasurements, [Values.MeasurementsName]);
      FieldLayoutName: Line := Format(rsTitleLayout, [Values.LayoutName]);
      FieldDate: Line := Format(rsTitleDate, [Values.Date]);
      FieldCutList: Line := Format(rsTitleCutList, [Values.CutList]);
      FieldMaterials: Line := Format(rsTitleMaterials, [Values.Materials]);
      else
        Continue;
    end;
    Insert(Line, Result, Length(Result));
  end;
end;

function TLayout.AddNote(const AText: string; AX, AY, ASize: double): integer;
begin
  Result := Length(Notes);
  SetLength(Notes, Result + 1);
  Notes[Result].Text := AText;
  Notes[Result].X := AX;
  Notes[Result].Y := AY;
  Notes[Result].Size := ASize;
end;

procedure TLayout.RemoveNote(Index: integer);
begin
  System.Delete(Notes, Index, 1);
end;

function TLayout.AddSource(const APatternFile, AMeasurementFile, ASize: string): TLayoutSource;
begin
  Result := TLayoutSource.Create;
  FSources.Add(Result);
  Result.Id := FNextId;
  Inc(FNextId);
  Result.PatternFile := APatternFile;
  Result.MeasurementFile := AMeasurementFile;
  Result.Size := ASize;
end;

procedure TLayout.RemoveSource(Source: TLayoutSource);
var
  Index: integer;
begin
  for Index := High(Placements) downto 0 do
    if Placements[Index].SourceId = Source.Id then
      System.Delete(Placements, Index, 1);
  FSources.Remove(Source);
end;

function TLayout.StoredPath(const Path: string): string;
var
  Folder: string;
begin
  Folder := ExtractFilePath(ExpandFileName(FileName));
  if FileName = '' then
    Result := Path
  else
    Result := ExtractRelativePath(Folder, ExpandFileName(Path));
end;

function TLayout.ResolvePath(const Stored: string): string;
var
  Folder: string;
begin
  Result := SetDirSeparators(Stored);
  Folder := ExtractFileDir(FileName);
  if (Result <> '') and (Result[1] <> PathDelim) and (ExtractFileDrive(Result) = '') and (Folder <> '') then
    Result := ConcatPaths([Folder, Result]);
end;

procedure TLayout.LoadSource(Source: TLayoutSource);
var
  Err: string;
begin
  Source.Unload;
  Source.LoadError := '';
  Source.PatternPath := ResolvePath(Source.PatternFile);
  Source.MeasurementPath := '';
  // Taken before reading, so a save during the read is not missed
  Source.LoadedStamp := Source.CurrentStamp;
  if not FileExists(Source.PatternPath) then
  begin
    Source.LoadError := Format(rsLayoutNoFile, [Source.PatternPath]);
    Exit;
  end;
  Source.Pattern := TPattern.Create;
  Source.Measurements := TMeasurementSet.Create;
  if not LoadPatternFromFile(Source.Pattern, Source.PatternPath, Err) then
  begin
    Source.LoadError := Err;
    Exit;
  end;
  Source.MeasurementPath := ResolvePath(Source.MeasurementFile);
  if Source.MeasurementPath = '' then
    Source.MeasurementPath := MeasurementFilePath(Source.Pattern, Source.PatternPath);
  Source.LoadedStamp := Source.CurrentStamp;
  if Source.MeasurementPath <> '' then
  begin
    if not FileExists(Source.MeasurementPath) then
    begin
      Source.LoadError := Format(rsLayoutNoFile, [Source.MeasurementPath]);
      Exit;
    end;
    if not Source.Measurements.LoadFromFile(Source.MeasurementPath, Err) then
    begin
      Source.LoadError := Err;
      Exit;
    end;
    Source.Pattern.Measurements := Source.Measurements;
  end;
  if (Source.Size <> '') and not Source.Measurements.SelectSize(Source.Size) then
  begin
    Source.LoadError := Format(rsMeasurementUnknownSize, [Source.Size]);
    Exit;
  end;
  Source.Pattern.Evaluate;
end;

procedure TLayout.LoadSources;
var
  Source: TLayoutSource;
begin
  for Source in FSources do
    LoadSource(Source);
end;

function SaveOutput(const Output: TLayoutOutput): TJSONObject;
var
  Excluded: TJSONArray;
  Caption: string;
  KnownWidth, KnownHeight: double;
begin
  Result := TJSONObject.Create;
  try
    Result.Add('kind', KindNames[Output.Kind]);
    Result.Add('rollWidth', JSONFloat(Output.RollWidth));
    Result.Add('paper', Output.Paper);
    if not PaperSize(Output.Paper, KnownWidth, KnownHeight) then
    begin
      Result.Add('paperWidth', JSONFloat(Output.Tiles.PaperWidth));
      Result.Add('paperHeight', JSONFloat(Output.Tiles.PaperHeight));
    end;
    Result.Add('margin', JSONFloat(Output.Tiles.Margin));
    Result.Add('overlap', JSONFloat(Output.Tiles.Overlap));
    Result.Add('marks', MarksNames[Output.Marks]);
    if Output.Fill <> lfNone then
      Result.Add('fill', FillNames[Output.Fill]);
    if Output.Profile <> '' then
      Result.Add('profile', Output.Profile);
    if Output.OutputProfile <> '' then
      Result.Add('outputProfile', Output.OutputProfile);
    if Output.MaterialWidth <> DefaultMaterialWidth then
      Result.Add('materialWidth', JSONFloat(Output.MaterialWidth));
    if Output.MaterialLength > 0 then
      Result.Add('materialLength', JSONFloat(Output.MaterialLength));
    if Output.AllowTurns then
      Result.Add('allowTurns', True);
    if Output.Material <> '' then
      Result.Add('material', Output.Material);
    if Length(Output.ExcludedPages) > 0 then
    begin
      Excluded := TJSONArray.Create;
      Result.Add('excludedPages', Excluded);
      for Caption in Output.ExcludedPages do
        Excluded.Add(Caption);
    end;
  except
    FreeAndNil(Result);
    raise;
  end;
end;

function TLayout.SaveToText: string;
var
  Root, Item: TJSONObject;
  List: TJSONArray;
  Source: TLayoutSource;
  Placement: TPlacement;
  Note: TSheetNote;
  Field: string;
begin
  Root := TJSONObject.Create;
  try
    Root.Add('format', LayoutFormat);
    Root.Add('version', LayoutVersion);
    Root.Add('units', 'mm');
    Root.Add('name', Name);
    Root.Add('nextId', FNextId);
    List := TJSONArray.Create;
    Root.Add('sources', List);
    for Source in FSources do
    begin
      Item := TJSONObject.Create;
      List.Add(Item);
      Item.Add('id', Source.Id);
      Item.Add('pattern', Source.PatternFile);
      if Source.MeasurementFile <> '' then
        Item.Add('measurementFile', Source.MeasurementFile);
      if Source.Size <> '' then
        Item.Add('size', Source.Size);
    end;
    Root.Add('output', SaveOutput(Output));
    List := TJSONArray.Create;
    Root.Add('placements', List);
    for Placement in Placements do
    begin
      Item := TJSONObject.Create;
      List.Add(Item);
      Item.Add('source', Placement.SourceId);
      Item.Add('piece', StrToInt(Placement.PieceKey));
      Item.Add('copy', Placement.Copy);
      Item.Add('x', JSONFloat(Placement.X));
      Item.Add('y', JSONFloat(Placement.Y));
      Item.Add('rotation', Placement.Rotation);
      Item.Add('flipped', Placement.Flipped);
    end;
    if Length(Notes) > 0 then
    begin
      List := TJSONArray.Create;
      Root.Add('sheetNotes', List);
      for Note in Notes do
      begin
        Item := TJSONObject.Create;
        List.Add(Item);
        Item.Add('text', Note.Text);
        Item.Add('x', JSONFloat(Note.X));
        Item.Add('y', JSONFloat(Note.Y));
        Item.Add('size', JSONFloat(Note.Size));
        if Note.Align <> taLeft then
          Item.Add('align', TextAlignNames[Note.Align]);
        if Note.Boxed then
          Item.Add('box', True);
      end;
    end;
    if Title.Enabled then
    begin
      Item := TJSONObject.Create;
      Root.Add('titleBlock', Item);
      Item.Add('corner', CornerNames[Title.Corner]);
      List := TJSONArray.Create;
      Item.Add('fields', List);
      for Field in Title.Fields do
        List.Add(Field);
      Item.Add('everyPage', Title.EveryPage);
    end;
    Result := JSONToText(Root);
  finally
    FreeAndNil(Root);
  end;
end;

function FindSourceById(List: TLayoutSourceList; Id: integer): TLayoutSource;
var
  Source: TLayoutSource;
begin
  for Source in List do
    if Source.Id = Id then
      Exit(Source);
  Result := nil;
end;

// The GetJSON functions clear their result when a member is missing
procedure ReadOptionalNumber(Item: TJSONObject; const AName: string; var Value: double);
begin
  if Assigned(Item.Find(AName)) then
    GetJSONNumber(Item, AName, Value);
end;

function ReadNotes(Data: TJSONData; var Notes: TSheetNoteArray): boolean;
var
  Index: integer;
  Item: TJSONObject;
  Note: TSheetNote;
  AlignText: string;
  Align: TTextAlign;
begin
  if Data.JSONType <> jtArray then
    Exit(False);
  for Index := 0 to Data.Count - 1 do
  begin
    if Data.Items[Index].JSONType <> jtObject then
      Exit(False);
    Item := TJSONObject(Data.Items[Index]);
    Note := Default(TSheetNote);
    Note.Size := DefaultSheetNoteSize;
    if not GetJSONString(Item, 'text', Note.Text) or not GetJSONNumber(Item, 'x', Note.X) or not GetJSONNumber(Item, 'y', Note.Y) then
      Exit(False);
    ReadOptionalNumber(Item, 'size', Note.Size);
    if GetJSONString(Item, 'align', AlignText) then
      for Align := Low(TTextAlign) to High(TTextAlign) do
        if TextAlignNames[Align] = AlignText then
          Note.Align := Align;
    GetJSONBoolean(Item, 'box', Note.Boxed);
    Insert(Note, Notes, Length(Notes));
  end;
  Result := True;
end;

procedure ReadTitle(Item: TJSONObject; var Title: TTitleBlock);
var
  CornerText: string;
  Corner: TTitleCorner;
  List: TJSONData;
  Index: integer;
begin
  Title.Enabled := True;
  if GetJSONString(Item, 'corner', CornerText) then
    for Corner := Low(TTitleCorner) to High(TTitleCorner) do
      if CornerText = CornerNames[Corner] then
        Title.Corner := Corner;
  GetJSONBoolean(Item, 'everyPage', Title.EveryPage);
  List := Item.Find('fields');
  if Assigned(List) and (List.JSONType = jtArray) then
    for Index := 0 to List.Count - 1 do
      if List.Items[Index].JSONType = jtString then
        Insert(List.Items[Index].AsString, Title.Fields, Length(Title.Fields));
end;

function ReadOutput(Item: TJSONObject; var Output: TLayoutOutput; out ErrorMessage: string): boolean;
var
  MarksText, FillText, KindText: string;
  Fill: TLayoutFill;
  Mark: TLayoutMarks;
  Kind: TOutputKind;
  Found: boolean;
  Excluded: TJSONData;
  Index: integer;
begin
  ErrorMessage := '';
  if GetJSONString(Item, 'kind', KindText) then
    for Kind := Low(TOutputKind) to High(TOutputKind) do
      if KindText = KindNames[Kind] then
        Output.Kind := Kind;
  ReadOptionalNumber(Item, 'rollWidth', Output.RollWidth);
  if not GetJSONString(Item, 'profile', Output.Profile) then
    Output.Profile := '';
  if not GetJSONString(Item, 'outputProfile', Output.OutputProfile) then
    Output.OutputProfile := '';
  if not GetJSONString(Item, 'material', Output.Material) then
    Output.Material := '';
  ReadOptionalNumber(Item, 'materialWidth', Output.MaterialWidth);
  ReadOptionalNumber(Item, 'materialLength', Output.MaterialLength);
  if not GetJSONBoolean(Item, 'allowTurns', Output.AllowTurns) then
    Output.AllowTurns := False;
  if (Output.MaterialWidth <= 0) or (Output.MaterialLength < 0) then
  begin
    ErrorMessage := rsLayoutBadMaterial;
    Exit(False);
  end;
  Excluded := Item.Find('excludedPages');
  if Assigned(Excluded) and (Excluded.JSONType = jtArray) then
    for Index := 0 to Excluded.Count - 1 do
      if Excluded.Items[Index].JSONType = jtString then
        Insert(Excluded.Items[Index].AsString, Output.ExcludedPages, Length(Output.ExcludedPages));
  if Assigned(Item.Find('paper')) and GetJSONString(Item, 'paper', Output.Paper) and not PaperSize(Output.Paper,
    Output.Tiles.PaperWidth, Output.Tiles.PaperHeight) then
    if not (GetJSONNumber(Item, 'paperWidth', Output.Tiles.PaperWidth) and GetJSONNumber(Item, 'paperHeight', Output.Tiles.PaperHeight)) then
    begin
      ErrorMessage := Format(rsLayoutBadPaper, [Output.Paper]);
      Exit(False);
    end;
  ReadOptionalNumber(Item, 'margin', Output.Tiles.Margin);
  ReadOptionalNumber(Item, 'overlap', Output.Tiles.Overlap);
  if not TilesAreUsable(Output.Tiles) then
  begin
    ErrorMessage := rsLayoutNoPrintArea;
    Exit(False);
  end;
  if Output.RollWidth <= 2 * Output.Tiles.Margin then
  begin
    ErrorMessage := rsLayoutBadRoll;
    Exit(False);
  end;
  if GetJSONString(Item, 'marks', MarksText) then
  begin
    Found := False;
    for Mark := Low(TLayoutMarks) to High(TLayoutMarks) do
      if MarksText = MarksNames[Mark] then
      begin
        Output.Marks := Mark;
        Found := True;
      end;
    if not Found then
      Output.Marks := lkNone;
  end;
  if GetJSONString(Item, 'fill', FillText) then
    for Fill := Low(TLayoutFill) to High(TLayoutFill) do
      if FillText = FillNames[Fill] then
        Output.Fill := Fill;
  Result := True;
end;

function TLayout.LoadFromText(const Text: string; out ErrorMessage: string): boolean;
var
  Root, Item: TJSONObject;
  Data: TJSONData;
  TextValue: string;
  Version, Index, Id, Saved, Top: integer;
  Source: TLayoutSource;
  Placement: TPlacement;
  PieceId: integer;

  function Fail(const Msg: string): boolean;
  begin
    ErrorMessage := Msg;
    Clear;
    Result := False;
  end;

begin
  Clear;
  ErrorMessage := '';
  if not ParseJSONObject(Text, Root, ErrorMessage) then
    Exit(False);
  try
    if not GetJSONString(Root, 'format', TextValue) or (TextValue <> LayoutFormat) or not GetJSONInteger(Root, 'version', Version) then
      Exit(Fail(rsLayoutWrongFormat));
    if Version > LayoutVersion then
      Exit(Fail(Format(rsLayoutNewerVersion, [Version])));
    if GetJSONString(Root, 'units', TextValue) and (TextValue <> 'mm') then
      Exit(Fail(Format(rsLayoutUnits, [TextValue])));
    GetJSONString(Root, 'name', Name);

    Data := Root.Find('sources');
    if not Assigned(Data) or (Data.JSONType <> jtArray) then
      Exit(Fail(Format(rsLayoutList, ['sources'])));
    Top := 0;
    for Index := 0 to Data.Count - 1 do
    begin
      if Data.Items[Index].JSONType <> jtObject then
        Exit(Fail(Format(rsLayoutList, ['sources'])));
      Item := TJSONObject(Data.Items[Index]);
      if not GetJSONInteger(Item, 'id', Id) or (Id < 1) or Assigned(FindSourceById(FSources, Id)) or not GetJSONString(Item, 'pattern', TextValue) then
        Exit(Fail(Format(rsLayoutBadSource, [Index + 1])));
      Source := TLayoutSource.Create;
      FSources.Add(Source);
      Source.Id := Id;
      Source.PatternFile := TextValue;
      GetJSONString(Item, 'measurementFile', Source.MeasurementFile);
      GetJSONString(Item, 'size', Source.Size);
      Top := Max(Top, Id);
    end;
    FNextId := Top + 1;
    if Assigned(Root.Find('nextId')) then
    begin
      if not GetJSONInteger(Root, 'nextId', Saved) or (Saved < FNextId) then
        Exit(Fail(rsLayoutBadNextId));
      FNextId := Saved;
    end;

    Data := Root.Find('output');
    if Assigned(Data) and (Data.JSONType = jtObject) and not ReadOutput(TJSONObject(Data), Output, TextValue) then
      Exit(Fail(TextValue));

    Data := Root.Find('placements');
    if Assigned(Data) then
    begin
      if Data.JSONType <> jtArray then
        Exit(Fail(Format(rsLayoutList, ['placements'])));
      for Index := 0 to Data.Count - 1 do
      begin
        if Data.Items[Index].JSONType <> jtObject then
          Exit(Fail(Format(rsLayoutList, ['placements'])));
        Item := TJSONObject(Data.Items[Index]);
        Placement := Default(TPlacement);
        if not GetJSONInteger(Item, 'source', Placement.SourceId) or not GetJSONInteger(Item, 'piece', PieceId) or not
          GetJSONNumber(Item, 'x', Placement.X) or not GetJSONNumber(Item, 'y', Placement.Y) then
          Exit(Fail(Format(rsLayoutBadPlacement, [Index + 1])));
        if not Assigned(FindSourceById(FSources, Placement.SourceId)) then
          Exit(Fail(Format(rsLayoutUnknownSource, [Index + 1, Placement.SourceId])));
        Placement.PieceKey := IntToStr(PieceId);
        if not GetJSONInteger(Item, 'copy', Placement.Copy) then
          Placement.Copy := 1;
        GetJSONInteger(Item, 'rotation', Placement.Rotation);
        GetJSONBoolean(Item, 'flipped', Placement.Flipped);
        SetLength(Placements, Length(Placements) + 1);
        Placements[High(Placements)] := Placement;
      end;
    end;

    Data := Root.Find('sheetNotes');
    if Assigned(Data) and not ReadNotes(Data, Notes) then
      Exit(Fail(Format(rsLayoutList, ['sheetNotes'])));
    Data := Root.Find('titleBlock');
    if Assigned(Data) and (Data.JSONType = jtObject) then
      ReadTitle(TJSONObject(Data), Title);
    Result := True;
  finally
    FreeAndNil(Root);
  end;
end;

function TLayout.SaveToFile(const AFileName: string; out ErrorMessage: string): boolean;
begin
  Result := WriteTextFile(AFileName, SaveToText, ErrorMessage);
  if Result then
    FileName := AFileName;
end;

function TLayout.LoadFromFile(const AFileName: string; out ErrorMessage: string): boolean;
var
  Text: string;
begin
  Clear;
  if not ReadTextFile(AFileName, Text, ErrorMessage) then
    Exit(False);
  Result := LoadFromText(Text, ErrorMessage);
  if Result then
    FileName := AFileName;
end;

function TLayout.IsPlaced(SourceId: integer; const PieceKey: string; Copy: integer): boolean;
var
  Placement: TPlacement;
begin
  for Placement in Placements do
    if (Placement.SourceId = SourceId) and (Placement.PieceKey = PieceKey) and (Placement.Copy = Copy) then
      Exit(True);
  Result := False;
end;

function TLayout.Unplaced: TUnplacedCopyArray;
var
  Source: TLayoutSource;
  Index, Copy: integer;
  Piece: TPieceObject;
  Item: TUnplacedCopy;
begin
  Result := nil;
  for Source in FSources do
    if Assigned(Source.Pattern) then
      for Index := 0 to Source.Pattern.ObjectCount - 1 do
        if Source.Pattern.Objects[Index] is TPieceObject then
        begin
          Piece := TPieceObject(Source.Pattern.Objects[Index]);
          if not InMaterial(Source, Piece) then
            Continue;
          for Copy := 1 to Piece.CutCount do
            if not IsPlaced(Source.Id, Piece.Key, Copy) then
            begin
              Item := Default(TUnplacedCopy);
              Item.SourceId := Source.Id;
              Item.PieceKey := Piece.Key;
              Item.Copy := Copy;
              Item.Caption := Format(rsLayoutTrayItem, [Piece.DisplayName, Copy, Piece.CutCount]);
              Item.CanPlace := (Piece.State = esValid) and (Length(Piece.CutLine) > 0);
              SetLength(Result, Length(Result) + 1);
              Result[High(Result)] := Item;
            end;
        end;
end;

function TLayout.FindPiece(const Placement: TPlacement; out Source: TLayoutSource; out Piece: TPieceObject): boolean;
var
  Node: TObject;
begin
  Piece := nil;
  Source := FindSourceById(FSources, Placement.SourceId);
  if not Assigned(Source) or not Assigned(Source.Pattern) then
    Exit(False);
  Node := Source.Pattern.FindNode(Placement.PieceKey);
  Result := Node is TPieceObject;
  if Result then
    Piece := TPieceObject(Node);
end;

function ClipperPaths(const Points: TVec2Array): TPathsD;
var
  Index: integer;
begin
  Result := nil;
  SetLength(Result, 1);
  SetLength(Result[0], Length(Points));
  for Index := 0 to High(Points) do
  begin
    Result[0][Index].X := Points[Index].X;
    Result[0][Index].Y := Points[Index].Y;
  end;
end;

// A half piece with its mirror image across the fold, joined into one outline
function WholeOutline(const Points: TVec2Array; const Fold: TLine2): TVec2Array;
const
  // Clipper rounds to this many decimals, and a cut line deserves better than 0.01 mm
  KeptDecimals = 4;
var
  Mirrored: TVec2Array;
  Joined: TPathsD;
  Index, Best: integer;
begin
  Mirrored := nil;
  SetLength(Mirrored, Length(Points));
  for Index := 0 to High(Points) do
    Mirrored[Index] := MirrorPoint(Points[Index], Fold.P1, Fold.P2);
  Joined := Union(ClipperPaths(Points), ClipperPaths(Mirrored), frNonZero, KeptDecimals);
  Best := 0;
  for Index := 1 to High(Joined) do
    if Abs(Area(Joined[Index])) > Abs(Area(Joined[Best])) then
      Best := Index;
  Result := nil;
  SetLength(Result, Length(Joined[Best]));
  for Index := 0 to High(Result) do
    Result[Index] := Vec2(Joined[Best][Index].X, Joined[Best][Index].Y);
end;

// Only what the output profile includes; with its allowance none, the seam
// line is the cutting line, so every export, overlap check and packing agrees
// Notes are placed upright, centred where their text's middle goes
function PlaceShape(Piece: TPieceObject; const Placement: TPlacement; Whole: boolean; const Profile: TOutputProfile;
  const Notes: TNoteObjectArray = nil): TPlacedPiece;
var
  Offset: TVec2;
  Opened, Mirroring: boolean;

// Model space to layout space, both y down, with the top left of the
// cutting line at (X, Y). A flip mirrors left to right before the rotation,
// which turns anticlockwise as seen on the page.
  function Turned(const Point: TVec2): TVec2;
  begin
    Result := Point;
    if Placement.Flipped then
      Result.X := -Result.X;
    Result := RotatePoint(Result, Vec2(0, 0), Placement.Rotation);
  end;

  function Moved(const Point: TVec2): TVec2;
  begin
    Result := Turned(Point) + Offset;
  end;

  function MovedAll(const Points: TVec2Array): TVec2Array;
  var
    Index: integer;
  begin
    Result := nil;
    SetLength(Result, Length(Points));
    for Index := 0 to High(Points) do
      Result[Index] := Moved(Points[Index]);
  end;

  function Mirror(const Point: TVec2): TVec2;
  begin
    Result := MirrorPoint(Point, Piece.FoldLine.P1, Piece.FoldLine.P2);
  end;

  function OnTheFold(const Point: TVec2): boolean;
  begin
    Result := Distance(Point, Mirror(Point)) < DefaultTolerance;
  end;

  // An opened piece has each mark on both halves, unless it lies on the fold
  procedure AddTo(var Lines: TLine2Array; const Stroke: TLine2);
  begin
    SetLength(Lines, Length(Lines) + 1);
    Lines[High(Lines)] := Line2(Moved(Stroke.P1), Moved(Stroke.P2));
    if Mirroring and not (OnTheFold(Stroke.P1) and OnTheFold(Stroke.P2)) then
    begin
      SetLength(Lines, Length(Lines) + 1);
      Lines[High(Lines)] := Line2(Moved(Mirror(Stroke.P1)), Moved(Mirror(Stroke.P2)));
    end;
  end;

  procedure AddHole(const Centre: TVec2; Diameter: double);
  begin
    SetLength(Result.Holes, Length(Result.Holes) + 1);
    Result.Holes[High(Result.Holes)].Centre := Moved(Centre);
    Result.Holes[High(Result.Holes)].Diameter := Diameter;
  end;

  procedure AddMark(const Stroke: TLine2);
  begin
    AddTo(Result.Marks, Stroke);
    AddTo(Result.MarkLines, Stroke);
  end;

  procedure AddLine(Role: TEdgeRole; const Points: TVec2Array);
  begin
    SetLength(Result.Lines, Length(Result.Lines) + 1);
    Result.Lines[High(Result.Lines)].Role := Role;
    Result.Lines[High(Result.Lines)].Points := MovedAll(Points);
    Result.Lines[High(Result.Lines)].Style := Profile.Styles[Role];
  end;

  // On both halves of an opened piece, unless it runs along the fold
  procedure AddWholeLine(Role: TEdgeRole; const Points: TVec2Array);
  var
    Index: integer;
    Mirrored: TVec2Array;
    OnFold: boolean;
  begin
    AddLine(Role, Points);
    if not Mirroring then
      Exit;
    OnFold := True;
    Mirrored := nil;
    SetLength(Mirrored, Length(Points));
    for Index := 0 to High(Points) do
    begin
      Mirrored[Index] := Mirror(Points[Index]);
      OnFold := OnFold and OnTheFold(Points[Index]);
    end;
    if not OnFold then
      AddLine(Role, Mirrored);
  end;

  procedure AddMarkingTypes(const Marking: TMarkingMark);
  var
    Index: integer;
    Stroke: TLine2;
    Hole: TVec2;
  begin
    case Marking.Kind of
      mkLine:
        if not (Marking.Role in Profile.Roles) then
          Exit;
      mkPoint:
        if not (pkHoles in Profile.PieceMarks) then
          Exit;
      else
        if not (pkStitchHoles in Profile.PieceMarks) then
          Exit;
    end;
    // Paper draws holes, buttons and match dots as strokes
    for Hole in Marking.Holes do
      for Stroke in MarkerStrokes(pmHole, Hole, Marking.HoleSize) do
        AddTo(Result.Marks, Stroke);
    for Hole in Marking.Centres do
      for Stroke in MarkerStrokes(Marking.Marker, Hole, Marking.HoleSize) do
        AddTo(Result.Marks, Stroke);
    if Length(Marking.Line) > 1 then
      AddWholeLine(Marking.Role, Marking.Line);
    for Index := 1 to High(Marking.Line) do
    begin
      Stroke := Line2(Marking.Line[Index - 1], Marking.Line[Index]);
      case Marking.Role of
        erFold: AddTo(Result.ScoreLines, Stroke);
        erCut: AddTo(Result.SlitLines, Stroke);
        else
          AddTo(Result.MarkLines, Stroke);
      end;
    end;
    for Hole in Marking.Holes do
    begin
      AddHole(Hole, Marking.HoleSize);
      // Stitch holes can run along the fold, and must not be cut twice
      if Mirroring and not OnTheFold(Hole) then
        AddHole(Mirror(Hole), Marking.HoleSize);
    end;
    // Buttons and match dots are drawn, not cut
    for Hole in Marking.Centres do
      for Stroke in MarkerStrokes(Marking.Marker, Hole, Marking.HoleSize) do
        AddTo(Result.MarkLines, Stroke);
  end;

var
  Point: TVec2;
  Stroke: TLine2;
  Mark: TNotchMark;
  Marking: TMarkingMark;
  Cut, Seam: TVec2Array;
  Note: TNoteObject;
  Box: TRect2;
  Placed: TSheetNote;
begin
  Result := Default(TPlacedPiece);
  Opened := Whole and Piece.OnFold;
  Mirroring := False;
  Cut := Piece.CutLine;
  Seam := Piece.Outline;
  if Profile.Allowance = apNone then
    Cut := Seam;
  if Opened then
  begin
    Cut := WholeOutline(Cut, Piece.FoldLine);
    Seam := WholeOutline(Seam, Piece.FoldLine);
  end;
  Result.Bounds.MinX := Infinity;
  Result.Bounds.MinY := Infinity;
  for Point in Cut do
  begin
    Result.Bounds.MinX := Min(Result.Bounds.MinX, Turned(Point).X);
    Result.Bounds.MinY := Min(Result.Bounds.MinY, Turned(Point).Y);
  end;
  Offset := Vec2(Placement.X - Result.Bounds.MinX, Placement.Y - Result.Bounds.MinY);
  Result.Bounds := Default(TRect2);
  Result.Bounds.MinX := Infinity;
  Result.Bounds.MinY := Infinity;
  Result.Bounds.MaxX := -Infinity;
  Result.Bounds.MaxY := -Infinity;
  Result.CutLine := MovedAll(Cut);
  // Cut on the seam line, it is not drawn again
  if (pkSeamLine in Profile.PieceMarks) and (Profile.Allowance = apKeep) then
    Result.SeamLine := MovedAll(Seam);
  for Point in Result.CutLine do
  begin
    Result.Bounds.MinX := Min(Result.Bounds.MinX, Point.X);
    Result.Bounds.MinY := Min(Result.Bounds.MinY, Point.Y);
    Result.Bounds.MaxX := Max(Result.Bounds.MaxX, Point.X);
    Result.Bounds.MaxY := Max(Result.Bounds.MaxY, Point.Y);
  end;
  // One piece has one grainline, even opened out
  if pkGrainline in Profile.PieceMarks then
    for Stroke in Piece.GrainArrow do
      AddMark(Stroke);
  Mirroring := Opened;
  if pkFoldBracket in Profile.PieceMarks then
    if Opened then
      AddMark(Piece.FoldLine)
    else
      for Stroke in Piece.FoldArrow do
        AddMark(Stroke);
  for Marking in Piece.MarkingMarks do
    AddMarkingTypes(Marking);
  // Cut on the seam line, a notch starts there
  if pkNotches in Profile.PieceMarks then
    for Mark in Piece.NotchMarks do
      if Profile.Allowance = apNone then
        AddMark(Line2(Mark.Seam, Mark.Seam + (Mark.Tip - Mark.Cut)))
      else
        AddMark(Line2(Mark.Cut, Mark.Tip));
  Result.ShowLabel := pkLabels in Profile.PieceMarks;
  Result.LabelAt := Moved(Piece.Middle);
  if Opened then
    Result.LabelAt := Moved(Lerp(Piece.Middle, Mirror(Piece.Middle), 0.5));
  for Note in Notes do
    if Note.HasResult then
    begin
      Box := NoteBox(Note, Default(TFieldValues));
      Point := Moved(Vec2((Box.MinX + Box.MaxX) / 2, (Box.MinY + Box.MaxY) / 2));
      Placed := Default(TSheetNote);
      Placed.Text := Note.ShownText;
      Placed.Size := Note.Size;
      Placed.X := Point.X - (Box.MaxX - Box.MinX) / 2;
      Placed.Y := Point.Y - (Box.MaxY - Box.MinY) / 2;
      Placed.Align := Note.Align;
      Placed.Boxed := Note.Boxed;
      Placed.Leader := Note.Leader;
      if Note.Leader <> nlNone then
        Placed.Tip := Moved(Note.AnchorPosition);
      Insert(Placed, Result.Notes, Length(Result.Notes));
    end;
end;

// Even copies are the other side of a mirrored pair
function TLayout.NewPlacement(const Item: TUnplacedCopy; out Piece: TPieceObject): TPlacement;
var
  Source: TLayoutSource;
begin
  Result := Default(TPlacement);
  Result.SourceId := Item.SourceId;
  Result.PieceKey := Item.PieceKey;
  Result.Copy := Item.Copy;
  FindPiece(Result, Source, Piece);
  Result.Flipped := Piece.Mirrored and not Piece.OnFold and not Odd(Item.Copy);
end;

function TLayout.PlaceCopies(const Copies: TUnplacedCopyArray): integer;
var
  Item: TUnplacedCopy;
  Piece: TPieceObject;
  Placement: TPlacement;
  Shape: TPlacedPiece;
  RowX, RowY, RowHeight: double;
begin
  Result := 0;
  RowX := 0;
  RowY := 0;
  RowHeight := 0;
  for Shape in PlacedPieces do
    RowY := Max(RowY, Shape.Bounds.MaxY + ShelfGap);
  for Item in Copies do
  begin
    if not Item.CanPlace then
      Continue;
    Placement := NewPlacement(Item, Piece);
    Shape := PlaceShape(Piece, Placement, OpensFolds, ActiveOutputProfile);
    if (RowX > 0) and (RowX + Shape.Bounds.MaxX - Shape.Bounds.MinX > ShelfWidth) then
    begin
      RowX := 0;
      RowY := RowY + RowHeight + ShelfGap;
      RowHeight := 0;
    end;
    Placement.X := RowX;
    Placement.Y := RowY;
    RowX := RowX + Shape.Bounds.MaxX - Shape.Bounds.MinX + ShelfGap;
    RowHeight := Max(RowHeight, Shape.Bounds.MaxY - Shape.Bounds.MinY);
    SetLength(Placements, Length(Placements) + 1);
    Placements[High(Placements)] := Placement;
    Inc(Result);
  end;
end;

function TLayout.PlaceNewPieces: integer;
begin
  Result := PlaceCopies(Unplaced);
end;

function TLayout.PlaceCopyAt(const Item: TUnplacedCopy; const At: TVec2; Step: double): integer;
var
  Piece: TPieceObject;
  Placement: TPlacement;
  Shape: TPlacedPiece;
begin
  if not Item.CanPlace then
    Exit(-1);
  Placement := NewPlacement(Item, Piece);
  Shape := PlaceShape(Piece, Placement, OpensFolds, ActiveOutputProfile);
  Placement.X := Max(0, Round((At.X - (Shape.Bounds.MaxX - Shape.Bounds.MinX) / 2) / Step) * Step);
  Placement.Y := Max(0, Round((At.Y - (Shape.Bounds.MaxY - Shape.Bounds.MinY) / 2) / Step) * Step);
  SetLength(Placements, Length(Placements) + 1);
  Result := High(Placements);
  Placements[Result] := Placement;
end;

procedure TLayout.RemovePlacement(Index: integer);
begin
  System.Delete(Placements, Index, 1);
end;

function TLayout.PlacedPieces: TPlacedPieceArray;
var
  Index, Count: integer;
  Source: TLayoutSource;
  Piece: TPieceObject;
  Profile: TOutputProfile;
begin
  Profile := ActiveOutputProfile;
  Result := nil;
  SetLength(Result, Length(Placements));
  Count := 0;
  for Index := 0 to High(Placements) do
    if FindPiece(Placements[Index], Source, Piece) and Piece.HasResult and (Length(Piece.CutLine) > 0) and InMaterial(Source, Piece) then
    begin
      Result[Count] := PlaceShape(Piece, Placements[Index], OpensFolds, Profile, Source.Pattern.PieceNotes(Piece));
      Result[Count].Placement := Index;
      Result[Count].Caption := Source.Pattern.PieceCaption(Piece, OpensFolds);
      Result[Count].Look := Source.Pattern.PieceLook(Piece);
      Inc(Count);
    end;
  SetLength(Result, Count);
end;

function TLayout.ActiveOutputProfile: TOutputProfile;
begin
  ChosenOutputProfile(Result);
end;

function TLayout.OpensFolds: boolean;
begin
  Result := (Output.Kind = okMaterial) or (Output.Profile <> '');
end;

function TLayout.InMaterial(Source: TLayoutSource; Piece: TPieceObject): boolean;
var
  Material: TPatternMaterial;
begin
  if Output.Material = '' then
    Exit(True);
  Material := Source.Pattern.MaterialOf(Piece);
  Result := Assigned(Material) and SameName(Material.Name, Output.Material);
end;

function TLayout.UsableWidth: double;
begin
  if Output.Kind = okMaterial then
    Result := Output.MaterialWidth
  else
    Result := Output.RollWidth - 2 * Output.Tiles.Margin;
end;

function TLayout.MaterialUse: string;
var
  Shape: TPlacedPiece;
  Used, Bottom: double;
begin
  if Output.Kind <> okMaterial then
    Exit('');
  Used := 0;
  Bottom := 0;
  for Shape in PlacedPieces do
  begin
    Used := Used + Abs(SignedArea(Shape.CutLine));
    Bottom := Max(Bottom, Shape.Bounds.MaxY);
  end;
  if Output.MaterialLength > 0 then
    Result := Format(rsLayoutSheetUsed, [FormatFloat('0.#', 100 * Used / (Output.MaterialWidth * Output.MaterialLength)),
      FormatFloat('0.#', Output.MaterialWidth), FormatFloat('0.#', Output.MaterialLength)])
  else
    Result := Format(rsLayoutRollUsed, [FormatFloat('0.#', Bottom), FormatFloat('0.#', Output.MaterialWidth)]);
end;

function TLayout.ChosenOutputProfile(out Profile: TOutputProfile): boolean;
begin
  Profile := FullOutputProfile;
  Result := (Output.OutputProfile = '') or FindOutputProfile(OutputProfiles, Output.OutputProfile, Profile);
end;

function TLayout.ChosenProfile(out Profile: TMachineProfile): boolean;
begin
  if Output.Profile = '' then
    Result := FindMachineProfile(MachineProfiles, StandardProfileName, Profile)
  else
    Result := FindMachineProfile(MachineProfiles, Output.Profile, Profile);
end;

function TLayout.Refusal: string;
var
  Problem: TLayoutProblem;
begin
  Result := '';
  for Problem in Problems do
    if Problem.Blocking then
      Result := Result + LineEnding + '  ' + Problem.Text;
  if Result <> '' then
    Result := rsLayoutRefused + Result;
end;

function WriteBytesToFile(const FileName: string; const Bytes: rawbytestring; out ErrorMessage: string): boolean;
var
  Stream: TFileStream;
begin
  ErrorMessage := '';
  try
    Stream := TFileStream.Create(FileName, fmCreate);
    try
      Stream.WriteBuffer(Bytes[1], Length(Bytes));
    finally
      FreeAndNil(Stream);
    end;
    Result := True;
  except
    on Failure: EStreamError do
    begin
      ErrorMessage := Failure.Message;
      Result := False;
    end;
  end;
end;

function TLayout.PageIsExcluded(const Caption: string): boolean;
var
  Excluded: string;
begin
  for Excluded in Output.ExcludedPages do
    if Excluded = Caption then
      Exit(True);
  Result := False;
end;

procedure TLayout.TogglePage(const Caption: string);
var
  Kept: TStringArray;
  Excluded: string;
begin
  if not PageIsExcluded(Caption) then
  begin
    Insert(Caption, Output.ExcludedPages, Length(Output.ExcludedPages));
    Exit;
  end;
  Kept := nil;
  for Excluded in Output.ExcludedPages do
    if Excluded <> Caption then
      Insert(Excluded, Kept, Length(Kept));
  Output.ExcludedPages := Kept;
end;

function TLayout.Pages(const Shapes: TPlacedPieceArray; out RowCount, ColumnCount: integer): TTilePageArray;
var
  Extent: TVec2;
  Shape: TPlacedPiece;
  Index: integer;
  Note: TSheetNote;
  Spread: TRect2;
  Values: TFieldValues;
begin
  Extent := Vec2(0, 0);
  for Shape in Shapes do
  begin
    Extent.X := Max(Extent.X, Shape.Bounds.MaxX);
    Extent.Y := Max(Extent.Y, Shape.Bounds.MaxY);
  end;
  Values := FieldValues('', '');
  for Note in Notes do
  begin
    Spread := NoteBounds(Note, Values);
    Extent.X := Max(Extent.X, Spread.MaxX);
    Extent.Y := Max(Extent.Y, Spread.MaxY);
  end;
  if Output.Kind <> okTiled then
  begin
    RowCount := 1;
    ColumnCount := 1;
    SetLength(Result, 1);
    Result[0] := Default(TTilePage);
    if Output.Kind in [okLarge, okMaterial] then
      Result[0].Area.MaxX := UsableWidth
    else
      Result[0].Area.MaxX := Extent.X;
    Result[0].Area.MaxY := Extent.Y;
    if Output.Kind = okMaterial then
      Result[0].Area.MaxY := Max(Extent.Y, Output.MaterialLength);
    Result[0].Blank := (Length(Shapes) = 0) and (Length(Notes) = 0);
    Exit;
  end;
  Result := TilePages(Extent, Output.Tiles, RowCount, ColumnCount);
  for Index := 0 to High(Result) do
  begin
    Result[Index].Excluded := PageIsExcluded(Result[Index].Caption);
    Result[Index].Blank := True;
    for Shape in Shapes do
      if PolygonTouches(Shape.CutLine, Result[Index].Area) then
      begin
        Result[Index].Blank := False;
        Break;
      end;
    for Note in Notes do
    begin
      Spread := NoteBounds(Note, Values);
      if (Spread.MaxX > Result[Index].Area.MinX) and (Spread.MinX < Result[Index].Area.MaxX) and
        (Spread.MaxY > Result[Index].Area.MinY) and (Spread.MinY < Result[Index].Area.MaxY) then
        Result[Index].Blank := False;
    end;
  end;
end;

procedure TLayout.AddOverlapProblems(var Problems: TLayoutProblemArray);
var
  Shapes: TPlacedPieceArray;
  First, Second: integer;
  Note: TSheetNote;
  Values: TFieldValues;

  procedure Add(const Text: string);
  begin
    SetLength(Problems, Length(Problems) + 1);
    Problems[High(Problems)].Text := Text;
    Problems[High(Problems)].Blocking := False;
  end;

begin
  Shapes := PlacedPieces;
  Values := FieldValues('', '');
  for Note in Notes do
    for First := 0 to High(Shapes) do
      if PolygonTouches(Shapes[First].CutLine, NoteBounds(Note, Values)) then
        Add(Format(rsLayoutNoteOverlap, [TextLines(Note.Text)[0], Shapes[First].Caption]));
  for First := 0 to High(Shapes) do
  begin
    if (Shapes[First].Bounds.MinX < -DefaultTolerance) or (Shapes[First].Bounds.MinY < -DefaultTolerance) then
      Add(Format(rsLayoutOffSheet, [Shapes[First].Caption]));
    if (Output.Kind = okLarge) and (Shapes[First].Bounds.MaxX > Output.RollWidth - 2 * Output.Tiles.Margin + DefaultTolerance) then
      Add(Format(rsLayoutWiderThanRoll, [Shapes[First].Caption, FormatFloat('0.#', Output.RollWidth)]));
    if (Output.Kind = okMaterial) and (Output.MaterialLength > 0) and ((Shapes[First].Bounds.MaxX > Output.MaterialWidth + DefaultTolerance) or
      (Shapes[First].Bounds.MaxY > Output.MaterialLength + DefaultTolerance)) then
      Add(Format(rsLayoutPastSheet, [Shapes[First].Caption, FormatFloat('0.#', Output.MaterialWidth), FormatFloat('0.#', Output.MaterialLength)]))
    else if (Output.Kind = okMaterial) and (Shapes[First].Bounds.MaxX > Output.MaterialWidth + DefaultTolerance) then
      Add(Format(rsLayoutPastWidth, [Shapes[First].Caption, FormatFloat('0.#', Output.MaterialWidth)]));
    for Second := First + 1 to High(Shapes) do
      if (Shapes[First].Bounds.MaxX > Shapes[Second].Bounds.MinX) and (Shapes[Second].Bounds.MaxX > Shapes[First].Bounds.MinX) and
        (Shapes[First].Bounds.MaxY > Shapes[Second].Bounds.MinY) and (Shapes[Second].Bounds.MaxY > Shapes[First].Bounds.MinY) and
        (Abs(Area(Intersect(ClipperPaths(Shapes[First].CutLine), ClipperPaths(Shapes[Second].CutLine), frNonZero))) > OverlapArea) then
        Add(Format(rsLayoutOverlap, [Shapes[First].Caption, Shapes[Second].Caption]));
  end;
end;

function HasPieces(Source: TLayoutSource): boolean;
var
  Index: integer;
begin
  for Index := 0 to Source.Pattern.ObjectCount - 1 do
    if Source.Pattern.Objects[Index] is TPieceObject then
      Exit(True);
  Result := False;
end;

function TLayout.Problems: TLayoutProblemArray;
var
  Source: TLayoutSource;
  Placement: TPlacement;
  Piece: TPieceObject;
  Item: TUnplacedCopy;
  Node: TPieceObject;
  Found: TLayoutSource;
  Probe: TPlacement;
  AllRead: boolean;
  Profile: TMachineProfile;
  Chosen: TOutputProfile;

  procedure Add(const Text: string; Blocking: boolean);
  begin
    SetLength(Result, Length(Result) + 1);
    Result[High(Result)].Text := Text;
    Result[High(Result)].Blocking := Blocking;
    Result[High(Result)].Unplaced := False;
  end;

  function MaterialExists: boolean;
  var
    Named: TLayoutSource;
  begin
    for Named in FSources do
      if Assigned(Named.Pattern) and Assigned(Named.Pattern.FindMaterialNamed(Output.Material)) then
        Exit(True);
    Result := False;
  end;

begin
  Result := nil;
  AllRead := True;
  if (Output.Profile <> '') and not ChosenProfile(Profile) then
    Add(Format(rsLayoutUnknownProfile, [Output.Profile]), False);
  // Never a quiet fallback: a print missing its stitch lines would be cut
  // and sewn wrongly
  if not ChosenOutputProfile(Chosen) then
    Add(Format(rsLayoutUnknownOutputProfile, [Output.OutputProfile]), True);
  for Source in FSources do
    if Source.LoadError <> '' then
    begin
      Add(Format(rsLayoutSourceProblem, [ExtractFileName(Source.PatternFile), Source.LoadError]), True);
      AllRead := False;
    end;
  for Placement in Placements do
  begin
    Source := FindSourceById(FSources, Placement.SourceId);
    if not Assigned(Source) or not Assigned(Source.Pattern) or (Source.LoadError <> '') then
      Continue;
    if not FindPiece(Placement, Source, Piece) then
    begin
      Add(Format(rsLayoutPieceGone, [ExtractFileName(Source.PatternFile), Placement.PieceKey]), True);
      Continue;
    end;
    if Piece.State <> esValid then
      Add(Format(rsLayoutPieceFailing, [ExtractFileName(Source.PatternFile), Piece.DisplayName, Piece.Message]), True);
    if (Placement.Rotation mod 90) <> 0 then
      Add(Format(rsLayoutOffGrain, [ExtractFileName(Source.PatternFile), Piece.DisplayName, Placement.Rotation]), False);
    if not InMaterial(Source, Piece) then
      Continue;
    if (Output.Kind = okProjector) and ((Placement.Rotation mod 180) <> 0) then
      Add(Format(rsLayoutProjectedAcross, [ExtractFileName(Source.PatternFile), Piece.DisplayName]), False)
    else if OpensFolds and ((Placement.Rotation mod 180) <> 0) then
      Add(Format(rsLayoutCutAcross, [ExtractFileName(Source.PatternFile), Piece.DisplayName]), False);
    if Placement.Copy > Piece.CutCount then
      Add(Format(rsLayoutExtraCopy, [ExtractFileName(Source.PatternFile), Piece.DisplayName, Piece.CutCount, Placement.Copy]), False);
  end;
  for Item in Unplaced do
  begin
    Probe := Default(TPlacement);
    Probe.SourceId := Item.SourceId;
    Probe.PieceKey := Item.PieceKey;
    FindPiece(Probe, Found, Node);
    Add(Format(rsLayoutUnplaced, [ExtractFileName(Found.PatternFile), Node.DisplayName, Item.Copy, Node.CutCount]), False);
    Result[High(Result)].Unplaced := True;
  end;
  for Source in FSources do
    if Assigned(Source.Pattern) and (Source.LoadError = '') and not HasPieces(Source) then
      Add(Format(rsLayoutNoPieces, [ExtractFileName(Source.PatternFile)]), False);
  // A source that failed already says why; this is for a sheet that would print blank
  if AllRead and ((Length(Placements) = 0) or ((Output.Material <> '') and (Length(PlacedPieces) = 0))) then
    Add(rsLayoutNothingPlaced, True);
  if AllRead and (Output.Material <> '') and not MaterialExists then
    Add(Format(rsLayoutNoMaterial, [Output.Material]), False);
  AddOverlapProblems(Result);
end;

end.
