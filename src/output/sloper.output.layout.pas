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
  SysUtils, Generics.Collections, Sloper.Core.Geometry, Sloper.Core.Measurements, Sloper.Core.Pattern, Sloper.Core.Piece,
  Sloper.Output.Tiling;

const
  LayoutFormat = 'layout';
  LayoutVersion = 1;
  LayoutExtension = '.slayout';

type
  TLayoutMarks = (lkDiamond, lkNone);

  TLayoutOutput = record
    Paper: string;
    Tiles: TTileSettings;
    Marks: TLayoutMarks;
    CalibrationX, CalibrationY: double;
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

  // A placed piece in layout space, ready to draw
  TPlacedPiece = record
    Placement: integer;
    Caption: string;
    CutLine, SeamLine: TVec2Array;
    // Grainline, fold bracket and notches
    Marks: array of TLine2;
    LabelAt: TVec2;
    Bounds: TRect2;
  end;

  TPlacedPieceArray = array of TPlacedPiece;

  // Blocking problems stop export; the others are only warnings
  TLayoutProblem = record
    Text: string;
    Blocking: boolean;
  end;

  TLayoutProblemArray = array of TLayoutProblem;

  TLayout = class
  private
    FSources: TLayoutSourceList;
    FNextId: integer;
    function ResolvePath(const Stored: string): string;
    procedure LoadSource(Source: TLayoutSource);
    function FindPlacedPiece(const Placement: TPlacement; out Source: TLayoutSource; out Piece: TPieceObject): boolean;
    function IsPlaced(SourceId: integer; const PieceKey: string; Copy: integer): boolean;
    procedure AddOverlapProblems(var Problems: TLayoutProblemArray);
  public
    Name: string;
    // Where the layout is saved; relative paths start from its folder
    FileName: string;
    Output: TLayoutOutput;
    Placements: TPlacementArray;
    constructor Create;
    destructor Destroy; override;
    procedure Clear;
    function AddSource(const APatternFile, AMeasurementFile, ASize: string): TLayoutSource;
    // Reads and evaluates every source's files
    procedure LoadSources;
    function SaveToText: string;
    function LoadFromText(const Text: string; out ErrorMessage: string): boolean;
    function SaveToFile(const AFileName: string; out ErrorMessage: string): boolean;
    function LoadFromFile(const AFileName: string; out ErrorMessage: string): boolean;
    // Every copy of a piece with no placement yet, one per line, by source and piece
    function Unplaced: TStringArray;
    // Adds a placement for every copy without one, in rows below what is
    // already placed. Plain rows, not packing. Returns how many were added.
    function PlaceNewPieces: integer;
    function PlacedPieces: TPlacedPieceArray;
    // The pages Shapes need, with the empty ones marked Blank
    function Pages(const Shapes: TPlacedPieceArray; out RowCount, ColumnCount: integer): TTilePageArray;
    function Problems: TLayoutProblemArray;
    property Sources: TLayoutSourceList read FSources;
  end;

// What the publish app should open for a pattern: its layout, when there is
// one beside it, otherwise the pattern itself
function PublishTargetFor(const PatternFile: string): string;
// The width and height of a named paper; False when the name is unknown
function PaperSize(const AName: string; out AWidth, AHeight: double): boolean;

resourcestring
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
  rsLayoutBadCalibration = 'Calibration factors must be above zero';
  rsLayoutNoFile = 'File not found: %s';
  rsLayoutSizeTable = 'Size tables are not supported yet, so size "%s" cannot be used';
  rsLayoutSourceProblem = '%s: %s';
  rsLayoutPieceGone = '%s: piece %s no longer exists';
  rsLayoutPieceFailing = '%s: %s cannot be printed: %s';
  rsLayoutOffGrain = '%s: %s is turned %d°, off its grainline';
  rsLayoutUnplaced = '%s: %s (copy %d of %d) is not placed';
  rsLayoutOverlap = '%s overlaps %s';
  rsLayoutOffSheet = '%s runs off the sheet';

implementation

uses
  Math, crc, fpjson, Clipper, Clipper.Core, Sloper.Core.JSON, Sloper.Core.EvalTypes, Sloper.Core.PatternFile;

const
  DefaultPaper = 'A4';
  CustomPaper = 'custom';
  DefaultMargin = 6;
  DefaultOverlap = 10;
  MarksNames: array[TLayoutMarks] of string = ('diamond', 'none');
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

function DefaultOutput: TLayoutOutput;
begin
  Result := Default(TLayoutOutput);
  Result.Paper := DefaultPaper;
  PaperSize(DefaultPaper, Result.Tiles.PaperWidth, Result.Tiles.PaperHeight);
  Result.Tiles.Margin := DefaultMargin;
  Result.Tiles.Overlap := DefaultOverlap;
  Result.Marks := lkDiamond;
  Result.CalibrationX := 1;
  Result.CalibrationY := 1;
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
  if Source.Size <> '' then
  begin
    Source.LoadError := Format(rsLayoutSizeTable, [Source.Size]);
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
begin
  Result := TJSONObject.Create;
  try
    Result.Add('kind', 'tiled');
    Result.Add('paper', Output.Paper);
    if Output.Paper = CustomPaper then
    begin
      Result.Add('paperWidth', JSONFloat(Output.Tiles.PaperWidth));
      Result.Add('paperHeight', JSONFloat(Output.Tiles.PaperHeight));
    end;
    Result.Add('margin', JSONFloat(Output.Tiles.Margin));
    Result.Add('overlap', JSONFloat(Output.Tiles.Overlap));
    Result.Add('marks', MarksNames[Output.Marks]);
    Result.Add('calibrationX', JSONFloat(Output.CalibrationX));
    Result.Add('calibrationY', JSONFloat(Output.CalibrationY));
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
  if Item.Find(AName) <> nil then
    GetJSONNumber(Item, AName, Value);
end;

function ReadOutput(Item: TJSONObject; var Output: TLayoutOutput; out ErrorMessage: string): boolean;
var
  MarksText: string;
  Mark: TLayoutMarks;
  Found: boolean;
begin
  ErrorMessage := '';
  if (Item.Find('paper') <> nil) and GetJSONString(Item, 'paper', Output.Paper) and not PaperSize(Output.Paper,
    Output.Tiles.PaperWidth, Output.Tiles.PaperHeight) then
    if not (GetJSONNumber(Item, 'paperWidth', Output.Tiles.PaperWidth) and GetJSONNumber(Item, 'paperHeight', Output.Tiles.PaperHeight)) then
    begin
      ErrorMessage := Format(rsLayoutBadPaper, [Output.Paper]);
      Exit(False);
    end;
  ReadOptionalNumber(Item, 'margin', Output.Tiles.Margin);
  ReadOptionalNumber(Item, 'overlap', Output.Tiles.Overlap);
  ReadOptionalNumber(Item, 'calibrationX', Output.CalibrationX);
  ReadOptionalNumber(Item, 'calibrationY', Output.CalibrationY);
  if not TilesAreUsable(Output.Tiles) then
  begin
    ErrorMessage := rsLayoutNoPrintArea;
    Exit(False);
  end;
  if (Output.CalibrationX <= 0) or (Output.CalibrationY <= 0) then
  begin
    ErrorMessage := rsLayoutBadCalibration;
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
    if (Data = nil) or (Data.JSONType <> jtArray) then
      Exit(Fail(Format(rsLayoutList, ['sources'])));
    Top := 0;
    for Index := 0 to Data.Count - 1 do
    begin
      if Data.Items[Index].JSONType <> jtObject then
        Exit(Fail(Format(rsLayoutList, ['sources'])));
      Item := TJSONObject(Data.Items[Index]);
      if not GetJSONInteger(Item, 'id', Id) or (Id < 1) or (FindSourceById(FSources, Id) <> nil) or not GetJSONString(Item, 'pattern', TextValue) then
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
    if Root.Find('nextId') <> nil then
    begin
      if not GetJSONInteger(Root, 'nextId', Saved) or (Saved < FNextId) then
        Exit(Fail(rsLayoutBadNextId));
      FNextId := Saved;
    end;

    Data := Root.Find('output');
    if (Data <> nil) and (Data.JSONType = jtObject) and not ReadOutput(TJSONObject(Data), Output, TextValue) then
      Exit(Fail(TextValue));

    Data := Root.Find('placements');
    if Data <> nil then
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
        if FindSourceById(FSources, Placement.SourceId) = nil then
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

function TLayout.Unplaced: TStringArray;
var
  Source: TLayoutSource;
  Index, Copy: integer;
  Piece: TPieceObject;
begin
  Result := nil;
  for Source in FSources do
    if Source.Pattern <> nil then
      for Index := 0 to Source.Pattern.ObjectCount - 1 do
        if Source.Pattern.Objects[Index] is TPieceObject then
        begin
          Piece := TPieceObject(Source.Pattern.Objects[Index]);
          for Copy := 1 to Piece.CutCount do
            if not IsPlaced(Source.Id, Piece.Key, Copy) then
            begin
              SetLength(Result, Length(Result) + 1);
              Result[High(Result)] := Format(rsLayoutUnplaced, [ExtractFileName(Source.PatternFile), Piece.DisplayName, Copy, Piece.CutCount]);
            end;
        end;
end;

function TLayout.FindPlacedPiece(const Placement: TPlacement; out Source: TLayoutSource; out Piece: TPieceObject): boolean;
var
  Node: TObject;
begin
  Piece := nil;
  Source := FindSourceById(FSources, Placement.SourceId);
  if (Source = nil) or (Source.Pattern = nil) then
    Exit(False);
  Node := Source.Pattern.FindNode(Placement.PieceKey);
  Result := Node is TPieceObject;
  if Result then
    Piece := TPieceObject(Node);
end;

// Model space (y up) to layout space (y down) with the top left of the
// cutting line at (X, Y). A flip mirrors left to right before the rotation.
function PlaceShape(Piece: TPieceObject; const Placement: TPlacement): TPlacedPiece;
var
  Offset: TVec2;

  function Turned(const P: TVec2): TVec2;
  begin
    Result := P;
    if Placement.Flipped then
      Result.X := -Result.X;
    Result := RotatePoint(Result, Vec2(0, 0), Placement.Rotation);
    Result.Y := -Result.Y;
  end;

  function Moved(const P: TVec2): TVec2;
  begin
    Result := Turned(P) + Offset;
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

  procedure AddMark(const Stroke: TLine2);
  begin
    SetLength(Result.Marks, Length(Result.Marks) + 1);
    Result.Marks[High(Result.Marks)] := Line2(Moved(Stroke.P1), Moved(Stroke.P2));
  end;

var
  P: TVec2;
  Stroke: TLine2;
  Mark: TNotchMark;
begin
  Result := Default(TPlacedPiece);
  Result.Bounds.MinX := Infinity;
  Result.Bounds.MinY := Infinity;
  for P in Piece.CutLine do
  begin
    Result.Bounds.MinX := Min(Result.Bounds.MinX, Turned(P).X);
    Result.Bounds.MinY := Min(Result.Bounds.MinY, Turned(P).Y);
  end;
  Offset := Vec2(Placement.X - Result.Bounds.MinX, Placement.Y - Result.Bounds.MinY);
  Result.Bounds := Default(TRect2);
  Result.Bounds.MinX := Infinity;
  Result.Bounds.MinY := Infinity;
  Result.Bounds.MaxX := -Infinity;
  Result.Bounds.MaxY := -Infinity;
  Result.CutLine := MovedAll(Piece.CutLine);
  Result.SeamLine := MovedAll(Piece.Outline);
  for P in Result.CutLine do
  begin
    Result.Bounds.MinX := Min(Result.Bounds.MinX, P.X);
    Result.Bounds.MinY := Min(Result.Bounds.MinY, P.Y);
    Result.Bounds.MaxX := Max(Result.Bounds.MaxX, P.X);
    Result.Bounds.MaxY := Max(Result.Bounds.MaxY, P.Y);
  end;
  for Stroke in Piece.GrainArrow do
    AddMark(Stroke);
  for Stroke in Piece.FoldArrow do
    AddMark(Stroke);
  for Mark in Piece.NotchMarks do
    AddMark(Line2(Mark.Cut, Mark.Tip));
  Result.LabelAt := Moved(Piece.Middle);
  Result.Caption := Piece.CutCaption;
end;

function TLayout.PlaceNewPieces: integer;
var
  Source: TLayoutSource;
  Index, Copy: integer;
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
  for Source in FSources do
    if Source.Pattern <> nil then
      for Index := 0 to Source.Pattern.ObjectCount - 1 do
      begin
        if not (Source.Pattern.Objects[Index] is TPieceObject) or (Source.Pattern.Objects[Index].State <> esValid) then
          Continue;
        Piece := TPieceObject(Source.Pattern.Objects[Index]);
        for Copy := 1 to Piece.CutCount do
        begin
          if IsPlaced(Source.Id, Piece.Key, Copy) then
            Continue;
          Placement := Default(TPlacement);
          Placement.SourceId := Source.Id;
          Placement.PieceKey := Piece.Key;
          Placement.Copy := Copy;
          // Even copies are the other side of a mirrored pair
          Placement.Flipped := Piece.Mirrored and not Piece.OnFold and not Odd(Copy);
          Shape := PlaceShape(Piece, Placement);
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
end;

function TLayout.PlacedPieces: TPlacedPieceArray;
var
  Index, Count: integer;
  Source: TLayoutSource;
  Piece: TPieceObject;
begin
  Result := nil;
  SetLength(Result, Length(Placements));
  Count := 0;
  for Index := 0 to High(Placements) do
    if FindPlacedPiece(Placements[Index], Source, Piece) and Piece.HasResult and (Piece.CutLine <> nil) then
    begin
      Result[Count] := PlaceShape(Piece, Placements[Index]);
      Result[Count].Placement := Index;
      Inc(Count);
    end;
  SetLength(Result, Count);
end;

function TLayout.Pages(const Shapes: TPlacedPieceArray; out RowCount, ColumnCount: integer): TTilePageArray;
var
  Extent: TVec2;
  Shape: TPlacedPiece;
  Index: integer;
begin
  Extent := Vec2(0, 0);
  for Shape in Shapes do
  begin
    Extent.X := Max(Extent.X, Shape.Bounds.MaxX);
    Extent.Y := Max(Extent.Y, Shape.Bounds.MaxY);
  end;
  Result := TilePages(Extent, Output.Tiles, RowCount, ColumnCount);
  for Index := 0 to High(Result) do
  begin
    Result[Index].Blank := True;
    for Shape in Shapes do
      if PolygonTouches(Shape.CutLine, Result[Index].Area) then
      begin
        Result[Index].Blank := False;
        Break;
      end;
  end;
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

procedure TLayout.AddOverlapProblems(var Problems: TLayoutProblemArray);
var
  Shapes: TPlacedPieceArray;
  First, Second: integer;

  procedure Add(const Text: string);
  begin
    SetLength(Problems, Length(Problems) + 1);
    Problems[High(Problems)].Text := Text;
    Problems[High(Problems)].Blocking := False;
  end;

begin
  Shapes := PlacedPieces;
  for First := 0 to High(Shapes) do
  begin
    if (Shapes[First].Bounds.MinX < -DefaultTolerance) or (Shapes[First].Bounds.MinY < -DefaultTolerance) then
      Add(Format(rsLayoutOffSheet, [Shapes[First].Caption]));
    for Second := First + 1 to High(Shapes) do
      if (Shapes[First].Bounds.MaxX > Shapes[Second].Bounds.MinX) and (Shapes[Second].Bounds.MaxX > Shapes[First].Bounds.MinX) and
        (Shapes[First].Bounds.MaxY > Shapes[Second].Bounds.MinY) and (Shapes[Second].Bounds.MaxY > Shapes[First].Bounds.MinY) and
        (Abs(Area(Intersect(ClipperPaths(Shapes[First].CutLine), ClipperPaths(Shapes[Second].CutLine), frNonZero))) > OverlapArea) then
        Add(Format(rsLayoutOverlap, [Shapes[First].Caption, Shapes[Second].Caption]));
  end;
end;

function TLayout.Problems: TLayoutProblemArray;
var
  Source: TLayoutSource;
  Placement: TPlacement;
  Piece: TPieceObject;
  Line: string;

  procedure Add(const Text: string; Blocking: boolean);
  begin
    SetLength(Result, Length(Result) + 1);
    Result[High(Result)].Text := Text;
    Result[High(Result)].Blocking := Blocking;
  end;

begin
  Result := nil;
  for Source in FSources do
    if Source.LoadError <> '' then
      Add(Format(rsLayoutSourceProblem, [ExtractFileName(Source.PatternFile), Source.LoadError]), True);
  for Placement in Placements do
  begin
    Source := FindSourceById(FSources, Placement.SourceId);
    if (Source = nil) or (Source.Pattern = nil) or (Source.LoadError <> '') then
      Continue;
    if not FindPlacedPiece(Placement, Source, Piece) then
    begin
      Add(Format(rsLayoutPieceGone, [ExtractFileName(Source.PatternFile), Placement.PieceKey]), True);
      Continue;
    end;
    if Piece.State <> esValid then
      Add(Format(rsLayoutPieceFailing, [ExtractFileName(Source.PatternFile), Piece.DisplayName, Piece.Message]), True);
    if (Placement.Rotation mod 180) <> 0 then
      Add(Format(rsLayoutOffGrain, [ExtractFileName(Source.PatternFile), Piece.DisplayName, Placement.Rotation]), False);
  end;
  for Line in Unplaced do
    Add(Line, False);
  AddOverlapProblems(Result);
end;

end.
