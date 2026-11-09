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

// Pattern files (.sloper): a pattern's definitions as JSON. Only
// definitions are written (operations, inputs and formulas in stored form);
// geometry is computed after loading. The layout is described in the design
// document under "File format and storage". No LCL dependency.
unit Sloper.Core.PatternFile;

{$mode ObjFPC}{$H+}

interface

uses
  SysUtils, Generics.Collections, fpjson, Sloper.Core.Draft, Sloper.Core.Materials, Sloper.Core.Pattern, Sloper.Core.Variables;

const
  PatternFormat = 'pattern';
  PatternVersion = 1;

type
  // IDs as the model keeps them, as text: the ID in a file to the ID it takes
  TPatternIdMap = specialize TDictionary<string, string>;

// WithNextId False leaves out the ID counter and the view state, for undo
// snapshots, which restore definitions but neither of those
function SavePatternToText(Pattern: TPattern; WithNextId: boolean = True): string;
// Replaces the pattern's contents. On failure the pattern is left empty and
// ErrorMessage says why. A formula that does not parse is kept as text and
// shows as an error when evaluated. Call Evaluate afterwards.
function LoadPatternFromText(Pattern: TPattern; const Text: string; out ErrorMessage: string): boolean;
function SavePatternToFile(Pattern: TPattern; const FileName: string; out ErrorMessage: string): boolean;
// View state as text, and put back after an undo has replaced the pattern
function PatternViewToText(Pattern: TPattern): string;
procedure RestorePatternView(Pattern: TPattern; const Text: string);
// The object's "type" in a pattern file, such as offsetPoint
function PatternObjectTypeName(DraftObject: TDraftObject): string;
function LoadPatternFromFile(Pattern: TPattern; const FileName: string; out ErrorMessage: string): boolean;
// A variable or object as a pattern file writes it
function PatternVariableToJSON(Variable: TVariable): TJSONObject;
function PatternObjectToJSON(DraftObject: TDraftObject): TJSONObject;
// Adds variables and objects, as a pattern file lists them, to what Pattern
// already holds. Every ID they hold, their own or one they refer to, in an
// input or a formula, is read through IdMap, so they can take new IDs and
// refer to objects already in the pattern; an ID not in the map is read as it
// is. Names must be free. On failure the pattern may hold some of them and
// ErrorMessage says why. Call Evaluate afterwards.
function AddPatternItems(Pattern: TPattern; Variables, Objects: TJSONArray; IdMap: TPatternIdMap; out ErrorMessage: string): boolean;
// Formula text in stored form with every {id} read through IdMap
function MapStoredFormula(const Text: string; IdMap: TPatternIdMap): string;
// The pattern's measurement file as a path: relative to the folder of
// PatternFileName unless absolute. Stored with "/" on every platform. Empty
// when the pattern names none.
function MeasurementFilePath(Pattern: TPattern; const PatternFileName: string): string;

resourcestring
  rsPatternFileWrongFormat = 'This is not a pattern file';
  rsPatternFileNewerVersion = 'This file was made by a newer version of OpenSloper (file version %d)';
  rsPatternFileUnits = 'Units "%s" are not supported; use mm, cm or in';
  rsPatternFileList = 'The file has no valid "%s" list';
  rsPatternFileBadId = 'Item %d of "%s" has a missing, invalid or repeated ID';
  rsPatternFileBadRepeatPoint = 'Repeat %s has a point that is not valid';
  rsPatternFileBadNextId = '"nextId" must be a whole number above every ID in the file';
  rsPatternVariableMissing = 'Variable %s has no valid "%s"';
  rsPatternVariableBadName = 'Variable %s: %s';
  rsPatternObjectMissing = 'Object %s has no valid "%s"';
  rsPatternObjectUnknownType = 'Object %s has an unknown type "%s"';
  rsPatternObjectNotBefore = 'Object %s uses object %s, which is not defined before it';
  rsPatternObjectProblem = 'Object %s: %s';
  rsPatternMaterialProblem = 'Material %s: %s';

implementation

uses
  Math, Sloper.Core.JSON, Sloper.Core.Evaluator, Sloper.Core.Names, Sloper.Core.Piece, Sloper.Core.Seam, Sloper.Core.Transform,
  Sloper.Core.Note, Sloper.Core.Units, Sloper.Core.PatternMaterials;

const
  TypeFreePoint = 'freePoint';
  TypeOffsetPoint = 'offsetPoint';
  TypeAlongEdgePoint = 'alongEdgePoint';
  TypeBetweenPoint = 'betweenPoint';
  TypeRepeat = 'repeat';
  // Only for reports: a repeat's points are saved inside it
  TypeRepeatPoint = 'repeatPoint';
  RepeatEndNames: array[0..1] of string = ('include', 'exclude');
  TypeIntersectPoint = 'intersectPoint';
  TypeCircleEdgePoint = 'circleEdgePoint';
  TypeProjectPoint = 'projectPoint';
  TypeLine = 'line';
  TypeCurve = 'curve';
  TypeCircle = 'circle';
  TypeArc = 'arc';
  TypeCircleCirclePoint = 'circleCirclePoint';
  TypeOffsetEdge = 'offsetEdge';
  TypeCornerArc = 'cornerArc';
  TypeCornerPoint = 'cornerPoint';
  OffsetSideNames: array[TOffsetSide] of string = ('left', 'right');
  TypeCurvePath = 'curvePath';
  TypeSplitPart = 'splitPart';
  TypePiece = 'piece';
  TypeSeam = 'seam';
  TypeNote = 'note';
  TypePointCopy = 'pointCopy';
  TypeEdgeCopy = 'edgeCopy';
  TransformTypes: array[TTransformKind] of string = ('rotate', 'mirror', 'move');

  // Marking kinds as read: older files marked placement and fold lines on
  // the piece, and these become the edge's role; and holes, which become
  // the point's marker
  ReadMarkingKindNames: array[0..5] of string = ('point', 'line', 'stitch', 'placement', 'fold', 'hole');
  OldMarkingRoles: array[3..4] of TEdgeRole = (erPlacement, erFold);
  OldHoleKind = 5;
  OffsetModeNames: array[TOffsetMode] of string = ('polar', 'cartesian');
  AlongModeNames: array[TAlongMode] of string = ('length', 'ratio');
  DirectionNames: array[TProjectDirection] of string = ('perpendicular', 'angle');
  EdgeEndNames: array[boolean] of string = ('start', 'end');

type
  TPatternLoader = class
  private
    FPattern: TPattern;
    FError: string;
    FId: string;  // the object being loaded, for messages
    FIdMap: TPatternIdMap;  // nil when IDs are read as they are
    function MapKey(Id: integer): string;
    function MapFormula(const Text: string): string;
    function ReadFreeId(Item: TJSONObject; out Id: string): boolean;
    function Fail(const Msg: string): boolean;
    function Missing(const AName: string): boolean;
    function Problem(const Msg: string): boolean;
    function ReadInput(Item: TJSONObject; const AName: string; WantEdge: boolean; out Key: string): boolean;
    function ReadMarkedPoint(Item: TJSONObject; out Key: string): boolean;
    function ReadRun(Item: TJSONObject; out Run: TRunEdgeArray): boolean;
    function RunStartKey(const Run: TRunEdgeArray): string;
    function RunEndKey(const Run: TRunEdgeArray): string;
    function ReadBoolean(Item: TJSONObject; const AName: string; out Value: boolean): boolean;
    function ReadChoice(Item: TJSONObject; const AName: string; const Choices: array of string; out Choice: integer): boolean;
    function ReadPick(Item: TJSONObject; out Pick: integer): boolean;
    function ReadFormula(Item: TJSONObject; const AName: string; Node: TEvalNode; const AField: string): boolean;
    function LoadVariables(Data: TJSONData): boolean;
    function LoadObjects(Data: TJSONData): boolean;
    function CreateObject(Item: TJSONObject; const TypeText: string): TDraftObject;
    function ReadRepeatPoints(Item: TJSONObject; ARepeat: TRepeatObject): boolean;
    function CreateCurvePath(Item: TJSONObject): TDraftObject;
    function CreatePiece(Item: TJSONObject): TDraftObject;
    function ReadSeamSide(Item: TJSONObject; const AName: string; out Side: TSeamSide): boolean;
    function CreateSeam(Item: TJSONObject): TDraftObject;
    function CreateNote(Item: TJSONObject): TDraftObject;
    function ReadNoteValues(Item: TJSONObject; Note: TNoteObject): boolean;
    function ReadSources(Item: TJSONObject; out Sources: TStringArray): boolean;
    function ReadTransformKey(Item: TJSONObject; out Key: string): boolean;
    function CreateTransform(Item: TJSONObject; Kind: TTransformKind): TDraftObject;
    function CreatePointCopy(Item: TJSONObject): TDraftObject;
    function CreateEdgeCopy(Item: TJSONObject): TDraftObject;
    function ReadGrainline(Item: TJSONObject; Piece: TPieceObject): boolean;
    function ReadNotches(Item: TJSONObject; Piece: TPieceObject): boolean;
    function ReadMarkings(Item: TJSONObject; Piece: TPieceObject): boolean;
    function ReadCut(Item: TJSONObject; Piece: TPieceObject): boolean;
    function ReadFold(Item: TJSONObject; Piece: TPieceObject): boolean;
    function ReadMaterial(Item: TJSONObject; Piece: TPieceObject): boolean;
    function ReadFill(Item: TJSONObject; Piece: TPieceObject): boolean;
    function LoadMaterials(Data: TJSONData): boolean;
    procedure RetireDraftIds(Data: TJSONData);
    function LoadObject(Item: TJSONObject): boolean;
  public
    constructor Create(APattern: TPattern; AIdMap: TPatternIdMap = nil);
    function Load(const Text: string): boolean;
    function AddItems(Variables, Objects: TJSONArray): boolean;
    property Error: string read FError;
  end;

function PatternObjectTypeName(DraftObject: TDraftObject): string;
begin
  if DraftObject is TFreePoint then
    Result := TypeFreePoint
  else if DraftObject is TOffsetPoint then
    Result := TypeOffsetPoint
  else if DraftObject is TAlongEdgePoint then
    Result := TypeAlongEdgePoint
  else if DraftObject is TBetweenPoint then
    Result := TypeBetweenPoint
  else if DraftObject is TRepeatObject then
    Result := TypeRepeat
  else if DraftObject is TRepeatPoint then
    Result := TypeRepeatPoint
  else if DraftObject is TIntersectPoint then
    Result := TypeIntersectPoint
  else if DraftObject is TCircleEdgePoint then
    Result := TypeCircleEdgePoint
  else if DraftObject is TProjectPoint then
    Result := TypeProjectPoint
  else if DraftObject is TLineObject then
    Result := TypeLine
  else if DraftObject is TCurveObject then
    Result := TypeCurve
  else if DraftObject is TCircleObject then
    Result := TypeCircle
  else if DraftObject is TOffsetEdge then
    Result := TypeOffsetEdge
  else if DraftObject is TCornerArc then
    Result := TypeCornerArc
  else if DraftObject is TCornerPoint then
    Result := TypeCornerPoint
  else if DraftObject is TArcObject then
    Result := TypeArc
  else if DraftObject is TCircleCirclePoint then
    Result := TypeCircleCirclePoint
  else if DraftObject is TCurvePathObject then
    Result := TypeCurvePath
  else if DraftObject is TSplitPart then
    Result := TypeSplitPart
  else if DraftObject is TPieceObject then
    Result := TypePiece
  else if DraftObject is TSeamObject then
    Result := TypeSeam
  else if DraftObject is TNoteObject then
    Result := TypeNote
  else if DraftObject is TTransformObject then
    Result := TransformTypes[TTransformObject(DraftObject).Kind]
  else if DraftObject is TPointCopy then
    Result := TypePointCopy
  else if DraftObject is TEdgeCopy then
    Result := TypeEdgeCopy
  else
    raise Exception.CreateFmt('No file type for %s', [DraftObject.ClassName]);
end;

{ Saving }

// IDs are kept as text in the model and written as JSON numbers
function JSONId(const Key: string): TJSONData;
begin
  Result := TJSONIntegerNumber.Create(StrToInt(Key));
end;

function SaveVariable(Variable: TVariable): TJSONObject;
begin
  Result := TJSONObject.Create;
  try
    Result.Add('id', JSONId(Variable.Key));
    Result.Add('name', Variable.Name);
    Result.Add('formula', Variable.Formula.StoredText);
    Result.Add('description', Variable.Description);
  except
    FreeAndNil(Result);
    raise;
  end;
end;

function SaveCurvePathNodes(Path: TCurvePathObject): TJSONArray;
var
  Index: integer;
  NodeItem: TJSONObject;
  NodeName: string;
begin
  Result := TJSONArray.Create;
  try
    for Index := 0 to High(Path.NodeKeys) do
    begin
      NodeName := 'node' + IntToStr(Index + 1);
      NodeItem := TJSONObject.Create;
      Result.Add(NodeItem);
      NodeItem.Add('point', JSONId(Path.NodeKeys[Index]));
      NodeItem.Add('angle', Path.Field(NodeName + '.angle').StoredText);
      if Index > 0 then
        NodeItem.Add('lengthIn', Path.Field(NodeName + '.lengthIn').StoredText);
      if Index < High(Path.NodeKeys) then
        NodeItem.Add('lengthOut', Path.Field(NodeName + '.lengthOut').StoredText);
    end;
  except
    FreeAndNil(Result);
    raise;
  end;
end;

function SaveRun(const Run: TRunEdgeArray): TJSONArray;
var
  Item: TRunEdge;
  Entry: TJSONObject;
begin
  Result := TJSONArray.Create;
  try
    for Item in Run do
    begin
      Entry := TJSONObject.Create;
      Result.Add(Entry);
      Entry.Add('edge', JSONId(Item.EdgeKey));
      Entry.Add('reversed', Item.Reversed);
    end;
  except
    FreeAndNil(Result);
    raise;
  end;
end;

function SavePiecePath(Piece: TPieceObject): TJSONArray;
var
  Index: integer;
  Item: TJSONObject;
begin
  Result := TJSONArray.Create;
  try
    for Index := 0 to High(Piece.Path) do
    begin
      Item := TJSONObject.Create;
      Result.Add(Item);
      Item.Add('edge', JSONId(Piece.Path[Index].EdgeKey));
      Item.Add('reversed', Piece.Path[Index].Reversed);
      if Piece.HasOverride(Index) then
        Item.Add(PieceAllowanceField, Piece.Field(Piece.OverrideField(Index)).StoredText);
    end;
  except
    FreeAndNil(Result);
    raise;
  end;
end;

function SaveSeamSide(const Side: TSeamSide): TJSONArray;
var
  Entry: TSeamEntry;
  Item: TJSONObject;
begin
  Result := TJSONArray.Create;
  try
    for Entry in Side do
    begin
      Item := TJSONObject.Create;
      Result.Add(Item);
      Item.Add('piece', JSONId(Entry.PieceKey));
      Item.Add('edge', JSONId(Entry.EdgeKey));
    end;
  except
    FreeAndNil(Result);
    raise;
  end;
end;

procedure SaveTransform(Transform: TTransformObject; Into: TJSONObject);
var
  List: TJSONArray;
  Axis: TJSONObject;
  Key: string;
begin
  List := TJSONArray.Create;
  Into.Add('sources', List);
  for Key in Transform.Sources do
    List.Add(JSONId(Key));
  Into.Add('suffix', Transform.Suffix);
  if Transform.PivotKey <> '' then
    Into.Add('pivot', JSONId(Transform.PivotKey));
  if Transform.Kind = tkMove then
    Into.Add('mode', OffsetModeNames[TOffsetMode(Ord(not Transform.Polar))]);
  if Transform.Kind <> tkMirror then
    Exit;
  Axis := TJSONObject.Create;
  Into.Add('axis', Axis);
  if Transform.AxisEdgeKey <> '' then
    Axis.Add('edge', JSONId(Transform.AxisEdgeKey))
  else
    Axis.Add('a', JSONId(Transform.AxisAKey));
  if Transform.AxisBKey <> '' then
    Axis.Add('b', JSONId(Transform.AxisBKey));
end;

function SaveGrainline(Piece: TPieceObject): TJSONObject;
begin
  Result := TJSONObject.Create;
  try
    if Piece.GrainKind = gkAngle then
      Result.Add('angle', Piece.Field(GrainAngleField).StoredText)
    else
    begin
      Result.Add('start', JSONId(Piece.GrainStartKey));
      Result.Add('end', JSONId(Piece.GrainEndKey));
    end;
  except
    FreeAndNil(Result);
    raise;
  end;
end;

function SavePieceFill(Piece: TPieceObject): TJSONObject;
begin
  Result := TJSONObject.Create;
  try
    if Piece.FillColor <> '' then
      Result.Add('color', Piece.FillColor);
    if Piece.FillStyle <> pfMaterial then
      Result.Add('style', PieceFillNames[Ord(Piece.FillStyle)]);
  except
    FreeAndNil(Result);
    raise;
  end;
end;

function SaveCut(Piece: TPieceObject): TJSONObject;
begin
  Result := TJSONObject.Create;
  try
    Result.Add('count', Piece.CutCount);
    Result.Add('mirrored', Piece.Mirrored);
  except
    FreeAndNil(Result);
    raise;
  end;
end;

function SaveMarkings(Piece: TPieceObject): TJSONArray;
var
  Index: integer;
  Item: TJSONObject;
  Marking: TPieceMarking;

  procedure AddPart(const Part: string);
  begin
    Item.Add(Part, Piece.Field(Piece.MarkingField(Index, Part)).StoredText);
  end;

begin
  Result := TJSONArray.Create;
  try
    for Index := 0 to High(Piece.Markings) do
    begin
      Marking := Piece.Markings[Index];
      Item := TJSONObject.Create;
      Result.Add(Item);
      Item.Add('kind', MarkingKindNames[Ord(Marking.Kind)]);
      if Marking.PointKey <> '' then
        Item.Add('point', JSONId(Marking.PointKey))
      else
        Item.Add('edge', JSONId(Marking.EdgeKey));
      if Marking.Kind = mkStitchHoles then
      begin
        AddPart(MarkingSpacingField);
        AddPart(MarkingSizeField);
      end;
    end;
  except
    FreeAndNil(Result);
    raise;
  end;
end;

function SaveNotches(Piece: TPieceObject): TJSONArray;
var
  Index: integer;
  Item: TJSONObject;
begin
  Result := TJSONArray.Create;
  try
    for Index := 0 to High(Piece.Notches) do
    begin
      Item := TJSONObject.Create;
      Result.Add(Item);
      if Piece.Notches[Index].PointKey <> '' then
        Item.Add('point', JSONId(Piece.Notches[Index].PointKey))
      else
      begin
        Item.Add('edge', JSONId(Piece.Notches[Index].EdgeKey));
        Item.Add('position', Piece.Field(Piece.NotchField(Index)).StoredText);
      end;
    end;
  except
    FreeAndNil(Result);
    raise;
  end;
end;

procedure SaveRepeat(ARepeat: TRepeatObject; Into: TJSONObject);
var
  List: TJSONArray;
  Entry: TJSONObject;
  Item: TRepeatPoint;
begin
  if ARepeat.Edge <> '' then
    Into.Add('edge', JSONId(ARepeat.Edge))
  else
  begin
    Into.Add('a', JSONId(ARepeat.FirstPoint));
    Into.Add('b', JSONId(ARepeat.LastPoint));
  end;
  if ARepeat.IncludeEnds then
    Into.Add('ends', RepeatEndNames[0])
  else
    Into.Add('ends', RepeatEndNames[1]);
  if Length(ARepeat.UsedItems) = 0 then
    Exit;
  List := TJSONArray.Create;
  Into.Add('points', List);
  for Item in ARepeat.UsedItems do
  begin
    Entry := TJSONObject.Create;
    List.Add(Entry);
    Entry.Add('index', Item.Index);
    Entry.Add('id', JSONId(Item.Key));
  end;
end;

// id, type and name; then inputs and options; then formulas under their
// field names; then the role of an edge
// The anchor, with an edge's position, then the offset or place, the text,
// its size and whether it prints
procedure SaveNote(Note: TNoteObject; Into: TJSONObject);
var
  Anchor: TJSONObject;
  FieldName: string;
begin
  if Note.Anchor <> naFree then
  begin
    Anchor := TJSONObject.Create;
    Into.Add('anchor', Anchor);
    Anchor.Add(NoteAnchorNames[Note.Anchor], JSONId(Note.AnchorKey));
    if Note.Anchor = naEdge then
      Anchor.Add(NotePositionField, Note.Field(NotePositionField).StoredText);
  end;
  for FieldName in Note.PlaceFields do
    Into.Add(FieldName, Note.Field(FieldName).StoredText);
  Into.Add('text', Note.StoredText);
  Into.Add('size', JSONFloat(Note.Size));
  Into.Add('print', Note.Print);
  // Each left out at its plain value
  if Note.Leader <> nlNone then
    Into.Add('leader', NoteLeaderNames[Note.Leader]);
  if Note.Align <> taLeft then
    Into.Add('align', TextAlignNames[Note.Align]);
  if Note.Boxed then
    Into.Add('box', True);
end;

function SaveObject(DraftObject: TDraftObject): TJSONObject;
var
  Index: integer;
  Offset: TOffsetPoint;
  Along: TAlongEdgePoint;
  Between: TBetweenPoint;
  Intersect: TIntersectPoint;
  Circle: TCircleEdgePoint;
  Project: TProjectPoint;
  Part: TSplitPart;
begin
  Result := TJSONObject.Create;
  try
    Result.Add('id', JSONId(DraftObject.Key));
    Result.Add('type', PatternObjectTypeName(DraftObject));
    // A derived name (Line_A_B) is recomputed on loading
    if not ((DraftObject is TEdgeObject) and TEdgeObject(DraftObject).NameIsDerived) then
      Result.Add('name', DraftObject.Name);

    if DraftObject is TOffsetPoint then
    begin
      Offset := TOffsetPoint(DraftObject);
      Result.Add('base', JSONId(Offset.Base));
      Result.Add('mode', OffsetModeNames[Offset.Mode]);
    end
    else if DraftObject is TAlongEdgePoint then
    begin
      Along := TAlongEdgePoint(DraftObject);
      Result.Add('edge', JSONId(Along.Edge));
      Result.Add('from', EdgeEndNames[Along.FromEnd]);
      Result.Add('mode', AlongModeNames[Along.Mode]);
    end
    else if DraftObject is TBetweenPoint then
    begin
      Between := TBetweenPoint(DraftObject);
      Result.Add('a', JSONId(Between.PointA));
      Result.Add('b', JSONId(Between.PointB));
      Result.Add('mode', AlongModeNames[Between.Mode]);
    end
    else if DraftObject is TRepeatObject then
      SaveRepeat(TRepeatObject(DraftObject), Result)
    else if DraftObject is TIntersectPoint then
    begin
      Intersect := TIntersectPoint(DraftObject);
      Result.Add('edgeA', JSONId(Intersect.EdgeA));
      Result.Add('edgeB', JSONId(Intersect.EdgeB));
      Result.Add('extendA', Intersect.ExtendA);
      Result.Add('extendB', Intersect.ExtendB);
      Result.Add('pick', Intersect.Pick);
    end
    else if DraftObject is TCornerArc then
    begin
      Result.Add('vertex', JSONId(TCornerArc(DraftObject).Vertex));
      Result.Add('edgeA', JSONId(TCornerArc(DraftObject).EdgeA));
      Result.Add('edgeB', JSONId(TCornerArc(DraftObject).EdgeB));
    end
    else if DraftObject is TCornerPoint then
    begin
      Result.Add('arc', JSONId(TCornerPoint(DraftObject).Arc));
      Result.Add('end', TCornerPoint(DraftObject).EndNumber);
    end
    else if DraftObject is TOffsetEdge then
    begin
      // One edge, followed forwards, is written as before runs
      if (Length(TOffsetEdge(DraftObject).Run) = 1) and not TOffsetEdge(DraftObject).Run[0].Reversed then
        Result.Add('edge', JSONId(TOffsetEdge(DraftObject).Source))
      else
        Result.Add('edges', SaveRun(TOffsetEdge(DraftObject).Run));
      Result.Add('side', OffsetSideNames[TOffsetEdge(DraftObject).Side]);
    end
    else if DraftObject is TRoundEdge then
      Result.Add('centre', JSONId(TRoundEdge(DraftObject).Centre))
    else if DraftObject is TCircleCirclePoint then
    begin
      Result.Add('centreA', JSONId(TCircleCirclePoint(DraftObject).CentreA));
      Result.Add('centreB', JSONId(TCircleCirclePoint(DraftObject).CentreB));
      Result.Add('pick', TCircleCirclePoint(DraftObject).Pick);
    end
    else if DraftObject is TCircleEdgePoint then
    begin
      Circle := TCircleEdgePoint(DraftObject);
      Result.Add('centre', JSONId(Circle.Centre));
      Result.Add('edge', JSONId(Circle.Edge));
      Result.Add('extend', Circle.Extend);
      Result.Add('pick', Circle.Pick);
    end
    else if DraftObject is TProjectPoint then
    begin
      Project := TProjectPoint(DraftObject);
      Result.Add('point', JSONId(Project.Source));
      Result.Add('edge', JSONId(Project.Edge));
      Result.Add('direction', DirectionNames[Project.Direction]);
      Result.Add('extend', Project.Extend);
    end
    else if DraftObject is TSplitPart then
    begin
      Part := TSplitPart(DraftObject);
      Result.Add('edge', JSONId(Part.Source));
      Result.Add('point', JSONId(Part.Point));
      Result.Add('part', Part.Part);
    end
    else if DraftObject is TTransformObject then
      SaveTransform(TTransformObject(DraftObject), Result)
    else if DraftObject is TPointCopy then
    begin
      Result.Add('transform', JSONId(TPointCopy(DraftObject).TransformKey));
      Result.Add('source', JSONId(TPointCopy(DraftObject).Source));
    end
    else if DraftObject is TEdgeCopy then
    begin
      Result.Add('transform', JSONId(TEdgeCopy(DraftObject).TransformKey));
      Result.Add('source', JSONId(TEdgeCopy(DraftObject).Source));
      Result.Add('start', JSONId(TEdgeCopy(DraftObject).StartKey));
      Result.Add('end', JSONId(TEdgeCopy(DraftObject).EndKey));
    end
    else if DraftObject is TSeamObject then
    begin
      Result.Add('sideA', SaveSeamSide(TSeamObject(DraftObject).SideA));
      Result.Add('sideB', SaveSeamSide(TSeamObject(DraftObject).SideB));
      Result.Add('reversed', TSeamObject(DraftObject).Reversed);
    end
    else if (DraftObject is TLineObject) or (DraftObject is TCurveObject) then
    begin
      Result.Add('start', JSONId(TEdgeObject(DraftObject).StartKey));
      Result.Add('end', JSONId(TEdgeObject(DraftObject).EndKey));
    end;

    if DraftObject is TCurvePathObject then
      Result.Add('nodes', SaveCurvePathNodes(TCurvePathObject(DraftObject)))
    else if DraftObject is TPieceObject then
    begin
      Result.Add('path', SavePiecePath(TPieceObject(DraftObject)));
      Result.Add(PieceAllowanceField, DraftObject.Field(PieceAllowanceField).StoredText);
      if TPieceObject(DraftObject).GrainKind <> gkNone then
        Result.Add('grainline', SaveGrainline(TPieceObject(DraftObject)));
      if Length(TPieceObject(DraftObject).Notches) > 0 then
        Result.Add('notches', SaveNotches(TPieceObject(DraftObject)));
      if Length(TPieceObject(DraftObject).Markings) > 0 then
        Result.Add('markings', SaveMarkings(TPieceObject(DraftObject)));
      Result.Add('cut', SaveCut(TPieceObject(DraftObject)));
      if TPieceObject(DraftObject).OnFold then
        Result.Add('foldEdge', JSONId(TPieceObject(DraftObject).FoldEdgeKey));
      if TPieceObject(DraftObject).MaterialKey <> '' then
        Result.Add('material', JSONId(TPieceObject(DraftObject).MaterialKey));
      if (TPieceObject(DraftObject).FillColor <> '') or (TPieceObject(DraftObject).FillStyle <> pfMaterial) then
        Result.Add('fill', SavePieceFill(TPieceObject(DraftObject)));
    end
    else if DraftObject is TNoteObject then
      SaveNote(TNoteObject(DraftObject), Result)
    else
      for Index := 0 to DraftObject.FieldCount - 1 do
        Result.Add(DraftObject.Fields[Index].Name, DraftObject.Fields[Index].Formula.StoredText);

    if DraftObject is TEdgeObject then
      Result.Add('role', EdgeRoleNames[TEdgeObject(DraftObject).Role]);
    if DraftObject.Marker <> pmPlain then
      Result.Add('marker', PointMarkerNames[DraftObject.Marker]);
  except
    FreeAndNil(Result);
    raise;
  end;
end;

function SaveMaterials(Pattern: TPattern): TJSONArray;
var
  Index: integer;
  Item: TJSONObject;
begin
  Result := TJSONArray.Create;
  try
    for Index := 0 to Pattern.MaterialCount - 1 do
    begin
      Item := TJSONObject.Create;
      Result.Add(Item);
      Item.Add('id', JSONId(Pattern.Materials[Index].Key));
      Item.Add('name', Pattern.Materials[Index].Name);
      Item.Add('color', Pattern.Materials[Index].Color);
      Item.Add('fill', MaterialFillNames[Ord(Pattern.Materials[Index].Fill)]);
      if Pattern.Materials[Index].HasAllowance then
        Item.Add('allowance', JSONFloat(Pattern.Materials[Index].Allowance));
    end;
  except
    FreeAndNil(Result);
    raise;
  end;
end;

function SaveView(Pattern: TPattern): TJSONObject;
var
  Centre, Roles: TJSONArray;
  RoleName: string;
begin
  Result := TJSONObject.Create;
  try
    if Pattern.View.HasView then
    begin
      Result.Add('zoom', JSONFloat(Pattern.View.Zoom));
      Centre := TJSONArray.Create;
      Result.Add('centre', Centre);
      Centre.Add(JSONFloat(Pattern.View.CentreX));
      Centre.Add(JSONFloat(Pattern.View.CentreY));
    end;
    // Left out when every role shows
    if Pattern.View.HiddenRoles <> [] then
    begin
      Roles := TJSONArray.Create;
      Result.Add('hiddenRoles', Roles);
      for RoleName in RolesToNames(Pattern.View.HiddenRoles) do
        Roles.Add(RoleName);
    end;
    // Left out when they show
    if Pattern.View.HideAnnotations then
      Result.Add('hideAnnotations', True);
  except
    FreeAndNil(Result);
    raise;
  end;
end;

// The view is only a convenience, so anything odd in it is passed over
procedure ReadPatternViewData(Pattern: TPattern; Data: TJSONData);
var
  Root: TJSONObject;
  List: TJSONData;
  Zoom: double;
  Index: integer;
  Role: TEdgeRole;
  Hide: boolean;
begin
  Pattern.View.Reset;
  if not Assigned(Data) or (Data.JSONType <> jtObject) then
    Exit;
  Root := TJSONObject(Data);
  List := Root.Find('centre');
  if GetJSONNumber(Root, 'zoom', Zoom) and (Zoom > 0) and Assigned(List) and (List.JSONType = jtArray) and (List.Count = 2) and
    (List.Items[0].JSONType = jtNumber) and (List.Items[1].JSONType = jtNumber) then
  begin
    Pattern.View.Zoom := Zoom;
    Pattern.View.CentreX := List.Items[0].AsFloat;
    Pattern.View.CentreY := List.Items[1].AsFloat;
    Pattern.View.HasView := True;
  end;
  // Unknown roles are passed over, and Outline is always shown
  List := Root.Find('hiddenRoles');
  if Assigned(List) and (List.JSONType = jtArray) then
    for Index := 0 to List.Count - 1 do
      if List.Items[Index].JSONType = jtString then
        for Role := Low(TEdgeRole) to High(TEdgeRole) do
          if (EdgeRoleNames[Role] = List.Items[Index].AsString) and (Role in HideableRoles) then
            Pattern.View.HiddenRoles := Pattern.View.HiddenRoles + [Role];
  if GetJSONBoolean(Root, 'hideAnnotations', Hide) then
    Pattern.View.HideAnnotations := Hide;
end;

function PatternViewToText(Pattern: TPattern): string;
var
  Root: TJSONObject;
begin
  Root := SaveView(Pattern);
  try
    Result := JSONToText(Root);
  finally
    FreeAndNil(Root);
  end;
end;

procedure RestorePatternView(Pattern: TPattern; const Text: string);
var
  Root: TJSONObject;
  Err: string;
begin
  if not ParseJSONObject(Text, Root, Err) then
    Exit;
  try
    ReadPatternViewData(Pattern, Root);
  finally
    FreeAndNil(Root);
  end;
end;

function SavePatternToText(Pattern: TPattern; WithNextId: boolean): string;
var
  Root: TJSONObject;
  List: TJSONArray;
  Index: integer;
begin
  Root := TJSONObject.Create;
  try
    Root.Add('format', PatternFormat);
    Root.Add('version', PatternVersion);
    Root.Add('units', MeasureUnitNames[Pattern.Units]);
    Root.Add('notes', Pattern.Notes);
    Root.Add('measurementFile', Pattern.MeasurementFile);
    if Pattern.Identity <> '' then
      Root.Add('identity', Pattern.Identity);
    if WithNextId then
      Root.Add('nextId', Pattern.NextId);
    List := TJSONArray.Create;
    Root.Add('variables', List);
    for Index := 0 to Pattern.VariableCount - 1 do
      List.Add(SaveVariable(Pattern.Variables[Index]));
    List := TJSONArray.Create;
    Root.Add('objects', List);
    for Index := 0 to Pattern.ObjectCount - 1 do
      List.Add(SaveObject(Pattern.Objects[Index]));
    // The untouched Main writes nothing, so simple files stay simple
    if Pattern.Materials[0].Key <> '' then
      Root.Add('materials', SaveMaterials(Pattern));
    if WithNextId and (Pattern.View.HasView or (Pattern.View.HiddenRoles <> []) or Pattern.View.HideAnnotations) then
      Root.Add('view', SaveView(Pattern));
    Result := JSONToText(Root);
  finally
    FreeAndNil(Root);
  end;
end;

{ Loading }

constructor TPatternLoader.Create(APattern: TPattern; AIdMap: TPatternIdMap);
begin
  FPattern := APattern;
  FIdMap := AIdMap;
end;

function TPatternLoader.MapKey(Id: integer): string;
begin
  Result := IntToStr(Id);
  if Assigned(FIdMap) and FIdMap.ContainsKey(Result) then
    Result := FIdMap[Result];
end;

function TPatternLoader.MapFormula(const Text: string): string;
begin
  if Assigned(FIdMap) then
    Result := MapStoredFormula(Text, FIdMap)
  else
    Result := Text;
end;

// Stored form writes an object or variable only as {id}, so braces mark every ID
function MapStoredFormula(const Text: string; IdMap: TPatternIdMap): string;
var
  Position, Close: integer;
  Id: string;
begin
  Result := '';
  Position := 1;
  while Position <= Length(Text) do
  begin
    Close := Pos('}', Text, Position);
    if (Text[Position] = '{') and (Close > Position + 1) then
    begin
      Id := Copy(Text, Position + 1, Close - Position - 1);
      if IdMap.ContainsKey(Id) then
        Id := IdMap[Id];
      Result := Result + '{' + Id + '}';
      Position := Close + 1;
    end
    else
    begin
      Result := Result + Text[Position];
      Inc(Position);
    end;
  end;
end;

function TPatternLoader.Fail(const Msg: string): boolean;
begin
  FError := Msg;
  Result := False;
end;

function TPatternLoader.Missing(const AName: string): boolean;
begin
  Result := Fail(Format(rsPatternObjectMissing, [FId, AName]));
end;

function TPatternLoader.Problem(const Msg: string): boolean;
begin
  Result := Fail(Format(rsPatternObjectProblem, [FId, Msg]));
end;

// Derived edge names are only set once everything is loaded, so until then
// an edge may have no name; use its ID instead
function NodeLabel(Node: TEvalNode): string;
begin
  Result := Node.DisplayName;
  if Result = '' then
    Result := Node.Key;
end;

// A point or edge ID, which must come earlier in the file
function TPatternLoader.ReadInput(Item: TJSONObject; const AName: string; WantEdge: boolean;
  out Key: string): boolean;
var
  Node: TEvalNode;
  Id: integer;
begin
  Key := '';
  if not GetJSONInteger(Item, AName, Id) or (Id < 1) then
    Exit(Missing(AName));
  Key := MapKey(Id);
  Node := FPattern.FindNode(Key);
  if not Assigned(Node) then
    Exit(Fail(Format(rsPatternObjectNotBefore, [FId, Key])));
  if WantEdge and not (Node is TEdgeObject) then
    Exit(Problem(Format(rsDraftNotAnEdge, [NodeLabel(Node)])));
  if not WantEdge and not (Node is TPointObject) then
    Exit(Problem(Format(rsDraftNotAPoint, [NodeLabel(Node)])));
  Result := True;
end;

// An offset edge's "edges", each an edge and whether the run follows it
// backwards; or, as written before runs, one "edge" followed forwards
function TPatternLoader.ReadRun(Item: TJSONObject; out Run: TRunEdgeArray): boolean;
var
  Data: TJSONData;
  Entry: TJSONObject;
  Index: integer;
  Key: string;
  Reversed: boolean;
begin
  Run := nil;
  Data := Item.Find('edges');
  if not Assigned(Data) then
  begin
    if not ReadInput(Item, 'edge', True, Key) then
      Exit(False);
    SetLength(Run, 1);
    Run[0].EdgeKey := Key;
    Run[0].Reversed := False;
    Exit(True);
  end;
  if (Data.JSONType <> jtArray) or (Data.Count = 0) then
    Exit(Missing('edges'));
  for Index := 0 to Data.Count - 1 do
  begin
    if Data.Items[Index].JSONType <> jtObject then
      Exit(Missing('edges'));
    Entry := TJSONObject(Data.Items[Index]);
    if not ReadInput(Entry, 'edge', True, Key) or not ReadBoolean(Entry, 'reversed', Reversed) then
      Exit(False);
    SetLength(Run, Length(Run) + 1);
    Run[High(Run)].EdgeKey := Key;
    Run[High(Run)].Reversed := Reversed;
  end;
  Result := True;
end;

function TPatternLoader.RunStartKey(const Run: TRunEdgeArray): string;
var
  Edge: TEdgeObject;
begin
  Edge := TEdgeObject(FPattern.FindNode(Run[0].EdgeKey));
  if Run[0].Reversed then
    Result := Edge.EndKey
  else
    Result := Edge.StartKey;
end;

function TPatternLoader.RunEndKey(const Run: TRunEdgeArray): string;
var
  Edge: TEdgeObject;
begin
  Edge := TEdgeObject(FPattern.FindNode(Run[High(Run)].EdgeKey));
  if Run[High(Run)].Reversed then
    Result := Edge.StartKey
  else
    Result := Edge.EndKey;
end;

// A point or repeat ID, which must come earlier in the file
function TPatternLoader.ReadMarkedPoint(Item: TJSONObject; out Key: string): boolean;
var
  Node: TEvalNode;
  Id: integer;
begin
  Key := '';
  if not GetJSONInteger(Item, 'point', Id) or (Id < 1) then
    Exit(Missing('point'));
  Key := MapKey(Id);
  Node := FPattern.FindNode(Key);
  if not Assigned(Node) then
    Exit(Fail(Format(rsPatternObjectNotBefore, [FId, Key])));
  if not ((Node is TPointObject) or (Node is TRepeatObject)) then
    Exit(Problem(Format(rsDraftNotAPoint, [NodeLabel(Node)])));
  Result := True;
end;

// Optional; False when absent
function TPatternLoader.ReadBoolean(Item: TJSONObject; const AName: string; out Value: boolean): boolean;
begin
  Value := False;
  if not Assigned(Item.Find(AName)) then
    Exit(True);
  if not GetJSONBoolean(Item, AName, Value) then
    Exit(Missing(AName));
  Result := True;
end;

// Optional; the first choice when absent
function TPatternLoader.ReadChoice(Item: TJSONObject; const AName: string; const Choices: array of string;
  out Choice: integer): boolean;
var
  Text: string;
  Index: integer;
begin
  Choice := 0;
  if not Assigned(Item.Find(AName)) then
    Exit(True);
  if GetJSONString(Item, AName, Text) then
    for Index := 0 to High(Choices) do
      if Text = Choices[Index] then
      begin
        Choice := Index;
        Exit(True);
      end;
  Result := Missing(AName);
end;

// Optional; 1 when absent
function TPatternLoader.ReadPick(Item: TJSONObject; out Pick: integer): boolean;
begin
  Pick := 1;
  if not Assigned(Item.Find('pick')) then
    Exit(True);
  if not GetJSONInteger(Item, 'pick', Pick) then
    Exit(Missing('pick'));
  if Pick < 1 then
    Exit(Problem(rsPatternBadPick));
  Result := True;
end;

// A formula that does not parse is kept as text and shows as an error
function TPatternLoader.ReadFormula(Item: TJSONObject; const AName: string; Node: TEvalNode;
  const AField: string): boolean;
var
  Text: string;
begin
  if not GetJSONString(Item, AName, Text) then
    Exit(Missing(AName));
  Node.Field(AField).ParseStored(MapFormula(Text));
  Result := True;
end;

// A positive integer not used by anything loaded so far
function TPatternLoader.ReadFreeId(Item: TJSONObject; out Id: string): boolean;
var
  Value: integer;
begin
  Id := '';
  if not GetJSONInteger(Item, 'id', Value) or (Value < 1) then
    Exit(False);
  Id := MapKey(Value);
  Result := not Assigned(FPattern.FindNode(Id)) and not Assigned(FPattern.FindMaterial(Id));
end;

function TPatternLoader.LoadVariables(Data: TJSONData): boolean;
var
  Index: integer;
  Item: TJSONObject;
  Id, VariableName, Text, Description, Msg: string;
  Variable: TVariable;
begin
  if not Assigned(Data) then
    Exit(True);
  if Data.JSONType <> jtArray then
    Exit(Fail(Format(rsPatternFileList, ['variables'])));
  for Index := 0 to Data.Count - 1 do
  begin
    if Data.Items[Index].JSONType <> jtObject then
      Exit(Fail(Format(rsPatternFileList, ['variables'])));
    Item := TJSONObject(Data.Items[Index]);
    if not ReadFreeId(Item, Id) then
      Exit(Fail(Format(rsPatternFileBadId, [Index + 1, 'variables'])));
    if not GetJSONString(Item, 'name', VariableName) then
      Exit(Fail(Format(rsPatternVariableMissing, [Id, 'name'])));
    if not FPattern.CheckVariableName(VariableName, nil, Msg) then
      Exit(Fail(Format(rsPatternVariableBadName, [Id, Msg])));
    if not GetJSONString(Item, 'formula', Text) then
      Exit(Fail(Format(rsPatternVariableMissing, [Id, 'formula'])));
    GetJSONString(Item, 'description', Description);
    Variable := TVariable.Create(Id);
    Variable.Name := VariableName;
    Variable.Description := Description;
    Variable.Formula.ParseStored(MapFormula(Text));
    FPattern.InsertVariable(Variable);
  end;
  Result := True;
end;

function TPatternLoader.CreateCurvePath(Item: TJSONObject): TDraftObject;
var
  Nodes: TJSONData;
  NodeItems: array of TJSONObject;
  NodeKeys: TStringArray;
  Index: integer;
  NodeName: string;
begin
  Result := nil;
  Nodes := Item.Find('nodes');
  if not Assigned(Nodes) or (Nodes.JSONType <> jtArray) then
  begin
    Missing('nodes');
    Exit;
  end;
  if Nodes.Count < 2 then
  begin
    Problem(rsPatternPathTooShort);
    Exit;
  end;
  NodeItems := nil;
  NodeKeys := nil;
  SetLength(NodeItems, Nodes.Count);
  SetLength(NodeKeys, Nodes.Count);
  for Index := 0 to Nodes.Count - 1 do
  begin
    if Nodes.Items[Index].JSONType <> jtObject then
    begin
      Missing('nodes');
      Exit;
    end;
    NodeItems[Index] := TJSONObject(Nodes.Items[Index]);
    if not ReadInput(NodeItems[Index], 'point', False, NodeKeys[Index]) then
      Exit;
    if (Index > 0) and (NodeKeys[Index] = NodeKeys[Index - 1]) then
    begin
      Problem(rsPatternPathRepeats);
      Exit;
    end;
  end;
  Result := TCurvePathObject.Create(FId, NodeKeys);
  for Index := 0 to High(NodeItems) do
  begin
    NodeName := 'node' + IntToStr(Index + 1);
    if not ReadFormula(NodeItems[Index], 'angle', Result, NodeName + '.angle') or
      ((Index > 0) and not ReadFormula(NodeItems[Index], 'lengthIn', Result, NodeName + '.lengthIn')) or
      ((Index < High(NodeItems)) and not ReadFormula(NodeItems[Index], 'lengthOut', Result, NodeName + '.lengthOut')) then
    begin
      FreeAndNil(Result);
      Exit;
    end;
  end;
end;

// Optional. An "angle", or a "start" and "end" point.
function TPatternLoader.ReadGrainline(Item: TJSONObject; Piece: TPieceObject): boolean;
var
  Data: TJSONData;
  Grain: TJSONObject;
  First, Second: string;
begin
  Data := Item.Find('grainline');
  if not Assigned(Data) then
    Exit(True);
  if Data.JSONType <> jtObject then
    Exit(Missing('grainline'));
  Grain := TJSONObject(Data);
  if Assigned(Grain.Find('angle')) then
  begin
    Piece.SetGrainKind(gkAngle);
    Exit(ReadFormula(Grain, 'angle', Piece, GrainAngleField));
  end;
  if not ReadInput(Grain, 'start', False, First) or not ReadInput(Grain, 'end', False, Second) then
    Exit(False);
  if First = Second then
    Exit(Problem(rsPatternGrainSamePoint));
  Piece.SetGrainKind(gkPoints, First, Second);
  Result := True;
end;

// Optional. Each has a "point", or an "edge" of the piece and a "position".
function TPatternLoader.ReadMarkings(Item: TJSONObject; Piece: TPieceObject): boolean;
var
  Data: TJSONData;
  Marking: TJSONObject;
  Index, Choice, Added: integer;
  Key: string;
  Kind: TMarkingKind;
  Target: TEvalNode;
begin
  Data := Item.Find('markings');
  if not Assigned(Data) then
    Exit(True);
  if Data.JSONType <> jtArray then
    Exit(Missing('markings'));
  for Index := 0 to Data.Count - 1 do
  begin
    if Data.Items[Index].JSONType <> jtObject then
      Exit(Missing('markings'));
    Marking := TJSONObject(Data.Items[Index]);
    if not Assigned(Marking.Find('kind')) then
      Exit(Missing('kind'));
    if not ReadChoice(Marking, 'kind', ReadMarkingKindNames, Choice) then
      Exit(False);
    if Choice = OldHoleKind then
      Kind := mkPoint
    else if Choice > Ord(High(TMarkingKind)) then
      Kind := mkLine
    else
      Kind := TMarkingKind(Choice);
    if Kind = mkPoint then
    begin
      if not ReadMarkedPoint(Marking, Key) then
        Exit(False);
      Target := FPattern.FindNode(Key);
      // An older file's hole gives its point the marker, with the first
      // diameter it finds; the size is a formula of the point now
      if (Choice = OldHoleKind) and (TDraftObject(Target).Marker = pmPlain) then
      begin
        TDraftObject(Target).SetMarker(pmHole);
        if not ReadFormula(Marking, 'diameter', Target, MarkerSizeField) then
          Exit(False);
      end;
      if Piece.PointMarkingOf(Key) < 0 then
        Piece.AddMarking(mkPoint, Key, '');
      Continue;
    end;
    if not ReadInput(Marking, 'edge', True, Key) then
      Exit(False);
    // A construction line marked by an older file takes the marking's role
    if (Choice > Ord(High(TMarkingKind))) and (FPattern.FindNode(Key) is TEdgeObject) and
      (TEdgeObject(FPattern.FindNode(Key)).Role = erConstruction) then
      TEdgeObject(FPattern.FindNode(Key)).Role := OldMarkingRoles[Choice];
    Added := Piece.AddMarking(Kind, '', Key);
    if (Kind = mkStitchHoles) and (not ReadFormula(Marking, MarkingSpacingField, Piece, Piece.MarkingField(Added, MarkingSpacingField)) or
      not ReadFormula(Marking, MarkingSizeField, Piece, Piece.MarkingField(Added, MarkingSizeField))) then
      Exit(False);
  end;
  Result := True;
end;

function TPatternLoader.ReadNotches(Item: TJSONObject; Piece: TPieceObject): boolean;
var
  Data: TJSONData;
  Notch: TJSONObject;
  Index, Added: integer;
  Key: string;
begin
  Data := Item.Find('notches');
  if not Assigned(Data) then
    Exit(True);
  if Data.JSONType <> jtArray then
    Exit(Missing('notches'));
  for Index := 0 to Data.Count - 1 do
  begin
    if Data.Items[Index].JSONType <> jtObject then
      Exit(Missing('notches'));
    Notch := TJSONObject(Data.Items[Index]);
    if Assigned(Notch.Find('point')) then
    begin
      if not ReadInput(Notch, 'point', False, Key) then
        Exit(False);
      Piece.AddNotch(Key, '');
      Continue;
    end;
    if not ReadInput(Notch, 'edge', True, Key) then
      Exit(False);
    if Piece.PathIndexOf(Key) < 0 then
      Exit(Problem(Format(rsPatternNotInPiece, [NodeLabel(FPattern.FindNode(Key)), FId])));
    Added := Piece.AddNotch('', Key);
    if not ReadFormula(Notch, 'position', Piece, Piece.NotchField(Added)) then
      Exit(False);
  end;
  Result := True;
end;

// Optional; cut once, not mirrored
function TPatternLoader.ReadCut(Item: TJSONObject; Piece: TPieceObject): boolean;
var
  Data: TJSONData;
  Cut: TJSONObject;
  Count: integer;
  Mirrored: boolean;
begin
  Data := Item.Find('cut');
  if not Assigned(Data) then
    Exit(True);
  if Data.JSONType <> jtObject then
    Exit(Missing('cut'));
  Cut := TJSONObject(Data);
  Count := 1;
  if Assigned(Cut.Find('count')) and not GetJSONInteger(Cut, 'count', Count) then
    Exit(Missing('count'));
  if Count < 1 then
    Exit(Problem(rsPatternBadCutCount));
  if not ReadBoolean(Cut, 'mirrored', Mirrored) then
    Exit(False);
  Piece.CutCount := Count;
  Piece.Mirrored := Mirrored;
  Result := True;
end;

// Optional
function TPatternLoader.ReadMaterial(Item: TJSONObject; Piece: TPieceObject): boolean;
var
  Id: integer;
begin
  if not Assigned(Item.Find('material')) then
    Exit(True);
  if not GetJSONInteger(Item, 'material', Id) or not Assigned(FPattern.FindMaterial(IntToStr(Id))) then
    Exit(Missing('material'));
  Piece.MaterialKey := IntToStr(Id);
  Result := True;
end;

function TPatternLoader.ReadFill(Item: TJSONObject; Piece: TPieceObject): boolean;
var
  Data: TJSONData;
  Fill: TJSONObject;
  Text: string;
  Choice: integer;
begin
  Data := Item.Find('fill');
  if not Assigned(Data) then
    Exit(True);
  if Data.JSONType <> jtObject then
    Exit(Missing('fill'));
  Fill := TJSONObject(Data);
  if Assigned(Fill.Find('color')) then
  begin
    if not GetJSONString(Fill, 'color', Text) or not IsMaterialColor(Text) then
      Exit(Missing('color'));
    Piece.FillColor := UpperCase(Text);
  end;
  if Assigned(Fill.Find('style')) then
  begin
    if not ReadChoice(Fill, 'style', PieceFillNames, Choice) then
      Exit(False);
    Piece.FillStyle := TPieceFillStyle(Choice);
  end;
  Result := True;
end;

function TPatternLoader.ReadFold(Item: TJSONObject; Piece: TPieceObject): boolean;
var
  Key: string;
begin
  if not Assigned(Item.Find('foldEdge')) then
    Exit(True);
  if not ReadInput(Item, 'foldEdge', True, Key) then
    Exit(False);
  if Piece.PathIndexOf(Key) < 0 then
    Exit(Problem(Format(rsPatternNotInPiece, [NodeLabel(FPattern.FindNode(Key)), FId])));
  if not IsStraightEdge(TEdgeObject(FPattern.FindNode(Key))) then
    Exit(Problem(Format(rsPatternFoldNotStraight, [NodeLabel(FPattern.FindNode(Key))])));
  Piece.FoldEdgeKey := Key;
  Result := True;
end;

function TPatternLoader.CreatePiece(Item: TJSONObject): TDraftObject;
var
  Entries: TJSONData;
  Entry: TJSONObject;
  Path: TPiecePath;
  Index, Other: integer;
  Piece: TPieceObject;
begin
  Result := nil;
  Entries := Item.Find('path');
  if not Assigned(Entries) or (Entries.JSONType <> jtArray) then
  begin
    Missing('path');
    Exit;
  end;
  if Entries.Count < 1 then
  begin
    Problem(rsPatternPieceTooShort);
    Exit;
  end;
  Path := nil;
  SetLength(Path, Entries.Count);
  for Index := 0 to Entries.Count - 1 do
  begin
    if Entries.Items[Index].JSONType <> jtObject then
    begin
      Missing('path');
      Exit;
    end;
    Entry := TJSONObject(Entries.Items[Index]);
    if not ReadInput(Entry, 'edge', True, Path[Index].EdgeKey) or not ReadBoolean(Entry, 'reversed', Path[Index].Reversed) then
      Exit;
    for Other := 0 to Index - 1 do
      if Path[Other].EdgeKey = Path[Index].EdgeKey then
      begin
        Problem(Format(rsPatternPieceRepeats, [NodeLabel(FPattern.FindNode(Path[Index].EdgeKey))]));
        Exit;
      end;
  end;
  Piece := TPieceObject.Create(FId, Path);
  Result := Piece;
  if not ReadFormula(Item, PieceAllowanceField, Piece, PieceAllowanceField) then
  begin
    FreeAndNil(Result);
    Exit;
  end;
  for Index := 0 to High(Path) do
  begin
    Entry := TJSONObject(Entries.Items[Index]);
    if not Assigned(Entry.Find(PieceAllowanceField)) then
      Continue;
    Piece.AddOverride(Index);
    if not ReadFormula(Entry, PieceAllowanceField, Piece, Piece.OverrideField(Index)) then
    begin
      FreeAndNil(Result);
      Exit;
    end;
  end;
  if not ReadGrainline(Item, Piece) or not ReadNotches(Item, Piece) or not ReadMarkings(Item, Piece) or not ReadCut(Item, Piece) or
    not ReadFold(Item, Piece) or not ReadMaterial(Item, Piece) or not ReadFill(Item, Piece) then
    FreeAndNil(Result);
end;

function TPatternLoader.ReadSeamSide(Item: TJSONObject; const AName: string; out Side: TSeamSide): boolean;
var
  Entries: TJSONData;
  Entry: TJSONObject;
  Index, PieceId, EdgeId: integer;
begin
  Side := nil;
  Entries := Item.Find(AName);
  if not Assigned(Entries) or (Entries.JSONType <> jtArray) then
    Exit(Missing(AName));
  SetLength(Side, Entries.Count);
  for Index := 0 to Entries.Count - 1 do
  begin
    if Entries.Items[Index].JSONType <> jtObject then
      Exit(Missing(AName));
    Entry := TJSONObject(Entries.Items[Index]);
    if not GetJSONInteger(Entry, 'piece', PieceId) or not GetJSONInteger(Entry, 'edge', EdgeId) then
      Exit(Missing(AName));
    Side[Index].PieceKey := MapKey(PieceId);
    Side[Index].EdgeKey := MapKey(EdgeId);
  end;
  if not FPattern.CheckSeamSide(Side) then
    Exit(Problem(FPattern.LastError));
  Result := True;
end;

function TPatternLoader.CreateSeam(Item: TJSONObject): TDraftObject;
var
  SideA, SideB: TSeamSide;
  Flipped: boolean;
begin
  Result := nil;
  if not ReadSeamSide(Item, 'sideA', SideA) or not ReadSeamSide(Item, 'sideB', SideB) or not ReadBoolean(Item, 'reversed', Flipped) then
    Exit;
  Result := TSeamObject.Create(FId, SideA, SideB);
  TSeamObject(Result).Reversed := Flipped;
end;

// The anchor names one point, edge or piece, which must come earlier in the
// file; a note without one is free
function TPatternLoader.CreateNote(Item: TJSONObject): TDraftObject;
var
  Data: TJSONData;
  Anchor: TJSONObject;
  Kind, Found: TNoteAnchor;
  Id, Count: integer;
  Key: string;
  Node: TEvalNode;
  Fits: boolean;
begin
  Result := nil;
  Found := naFree;
  Key := '';
  Anchor := nil;
  Data := Item.Find('anchor');
  if Assigned(Data) then
  begin
    if Data.JSONType <> jtObject then
    begin
      Missing('anchor');
      Exit;
    end;
    Anchor := TJSONObject(Data);
    Count := 0;
    for Kind := naPoint to naPiece do
      if Assigned(Anchor.Find(NoteAnchorNames[Kind])) then
      begin
        Inc(Count);
        Found := Kind;
      end;
    if (Count <> 1) or not GetJSONInteger(Anchor, NoteAnchorNames[Found], Id) or (Id < 1) then
    begin
      Missing('anchor');
      Exit;
    end;
    Key := MapKey(Id);
    Node := FPattern.FindNode(Key);
    if not Assigned(Node) then
    begin
      Fail(Format(rsPatternObjectNotBefore, [FId, Key]));
      Exit;
    end;
    case Found of
      naPoint: Fits := Node is TPointObject;
      naEdge: Fits := Node is TEdgeObject;
      else
        Fits := Node is TPieceObject;
    end;
    if not Fits then
    begin
      Problem(Format(rsPatternNoteAnchor, [NodeLabel(Node), NoteAnchorNames[Found]]));
      Exit;
    end;
  end;
  Result := TNoteObject.Create(FId, Found, Key);
  if (Found = naEdge) and not ReadFormula(Anchor, NotePositionField, Result, NotePositionField) then
    FreeAndNil(Result);
end;

// Its fields other than an edge's position, text, size, print, leader,
// alignment and box
function TPatternLoader.ReadNoteValues(Item: TJSONObject; Note: TNoteObject): boolean;
var
  FieldName, Text: string;
  Size: double;
  Print, Boxed: boolean;
  Choice: integer;
begin
  for FieldName in Note.PlaceFields do
    if not ReadFormula(Item, FieldName, Note, FieldName) then
      Exit(False);
  if not GetJSONString(Item, 'text', Text) then
    Exit(Missing('text'));
  Note.SetStoredText(Text);
  if Assigned(Item.Find('size')) then
  begin
    if not GetJSONNumber(Item, 'size', Size) or (Size <= 0) or (Size > MaxNoteSize) then
      Exit(Missing('size'));
    Note.Size := Size;
  end;
  if Assigned(Item.Find('print')) then
  begin
    if not GetJSONBoolean(Item, 'print', Print) then
      Exit(Missing('print'));
    Note.Print := Print;
  end;
  if not ReadChoice(Item, 'leader', NoteLeaderNames, Choice) then
    Exit(False);
  if (Note.Anchor = naFree) and (TNoteLeader(Choice) <> nlNone) then
    Exit(Problem(rsPatternCalloutFree));
  Note.Leader := TNoteLeader(Choice);
  if not ReadChoice(Item, 'align', TextAlignNames, Choice) or not ReadBoolean(Item, 'box', Boxed) then
    Exit(False);
  Note.Align := TTextAlign(Choice);
  Note.Boxed := Boxed;
  Result := True;
end;

function TPatternLoader.ReadSources(Item: TJSONObject; out Sources: TStringArray): boolean;
var
  List: TJSONData;
  Index: integer;
  Node: TEvalNode;
  Key: string;
begin
  Sources := nil;
  List := Item.Find('sources');
  if not Assigned(List) or (List.JSONType <> jtArray) or (List.Count = 0) then
    Exit(Missing('sources'));
  for Index := 0 to List.Count - 1 do
  begin
    if List.Items[Index].JSONType <> jtNumber then
      Exit(Missing('sources'));
    Key := MapKey(List.Items[Index].AsInteger);
    Node := FPattern.FindNode(Key);
    if not Assigned(Node) then
      Exit(Fail(Format(rsPatternObjectNotBefore, [FId, Key])));
    if not (Node is TPointObject) and not (Node is TEdgeObject) then
      Exit(Problem(Format(rsPatternTransformNotCopyable, [NodeLabel(Node)])));
    Insert(Key, Sources, Length(Sources));
  end;
  Result := True;
end;

function TPatternLoader.ReadTransformKey(Item: TJSONObject; out Key: string): boolean;
var
  Id: integer;
begin
  Key := '';
  if not GetJSONInteger(Item, 'transform', Id) then
    Exit(Missing('transform'));
  Key := MapKey(Id);
  if not (FPattern.FindNode(Key) is TTransformObject) then
    Exit(Fail(Format(rsPatternObjectNotBefore, [FId, Key])));
  Result := True;
end;

function TPatternLoader.CreateTransform(Item: TJSONObject; Kind: TTransformKind): TDraftObject;
var
  Sources: TStringArray;
  Suffix, First, Second: string;
  Transform: TTransformObject;
  Axis: TJSONObject;
  Mode: integer;
begin
  Result := nil;
  if not ReadSources(Item, Sources) then
    Exit;
  if not GetJSONString(Item, 'suffix', Suffix) then
  begin
    Missing('suffix');
    Exit;
  end;
  Transform := TTransformObject.Create(FId, Kind, Sources, Suffix);
  Result := Transform;
  First := '';
  case Kind of
    tkRotate:
      if ReadInput(Item, 'pivot', False, First) then
        Transform.UseRotate(First)
      else
        FreeAndNil(Result);
    tkMove:
    begin
      if Assigned(Item.Find('pivot')) and not ReadInput(Item, 'pivot', False, First) then
      begin
        FreeAndNil(Result);
        Exit;
      end;
      if ReadChoice(Item, 'mode', OffsetModeNames, Mode) then
        Transform.UseMove(TOffsetMode(Mode) = omPolar, First)
      else
        FreeAndNil(Result);
    end;
    tkMirror:
    begin
      if not Assigned(Item.Find('axis')) or (Item.Find('axis').JSONType <> jtObject) then
      begin
        Missing('axis');
        FreeAndNil(Result);
        Exit;
      end;
      Axis := TJSONObject(Item.Find('axis'));
      if Assigned(Axis.Find('edge')) then
      begin
        if ReadInput(Axis, 'edge', True, First) then
          Transform.UseAxisEdge(First)
        else
          FreeAndNil(Result);
      end
      else if not ReadInput(Axis, 'a', False, First) then
        FreeAndNil(Result)
      else if not Assigned(Axis.Find('b')) then
        Transform.UseAxisAngle(First)
      else if ReadInput(Axis, 'b', False, Second) then
        Transform.UseAxisPoints(First, Second)
      else
        FreeAndNil(Result);
    end;
  end;
end;

function TPatternLoader.CreatePointCopy(Item: TJSONObject): TDraftObject;
var
  Transform, Source: string;
begin
  Result := nil;
  if ReadTransformKey(Item, Transform) and ReadInput(Item, 'source', False, Source) then
    Result := TPointCopy.Create(FId, Transform, Source);
end;

function TPatternLoader.CreateEdgeCopy(Item: TJSONObject): TDraftObject;
var
  Transform, Source, First, Second: string;
  Edge: TEdgeObject;
begin
  Result := nil;
  if ReadTransformKey(Item, Transform) and ReadInput(Item, 'source', True, Source) and ReadInput(Item, 'start', False, First) and
    ReadInput(Item, 'end', False, Second) then
  begin
    Edge := TEdgeObject(FPattern.FindNode(Source));
    Result := TEdgeCopy.Create(FId, Transform, Source, First, Second, Edge.IsStraight, Edge.NamePrefix);
  end;
end;

// The object with its inputs and options; formulas come later. nil on failure.
function TPatternLoader.CreateObject(Item: TJSONObject; const TypeText: string): TDraftObject;
var
  First, Second, Third: string;
  Choice, EndChoice, Pick, Part: integer;
  FlagA, FlagB: boolean;
  Run: TRunEdgeArray;
begin
  Result := nil;
  if TypeText = TypeFreePoint then
    Result := TFreePoint.Create(FId)
  else if TypeText = TypeOffsetPoint then
  begin
    if ReadInput(Item, 'base', False, First) and ReadChoice(Item, 'mode', OffsetModeNames, Choice) then
      Result := TOffsetPoint.Create(FId, First, TOffsetMode(Choice));
  end
  else if TypeText = TypeAlongEdgePoint then
  begin
    if ReadInput(Item, 'edge', True, First) and ReadChoice(Item, 'from', EdgeEndNames, EndChoice) and
      ReadChoice(Item, 'mode', AlongModeNames, Choice) then
      Result := TAlongEdgePoint.Create(FId, First, EndChoice = 1, TAlongMode(Choice));
  end
  else if TypeText = TypeRepeat then
  begin
    if not ReadChoice(Item, 'ends', RepeatEndNames, Choice) then
      Exit;
    if Assigned(Item.Find('edge')) then
    begin
      if ReadInput(Item, 'edge', True, First) then
        Result := TRepeatObject.CreateOnEdge(FId, First, Choice = 0);
    end
    else if ReadInput(Item, 'a', False, First) and ReadInput(Item, 'b', False, Second) then
      Result := TRepeatObject.CreateBetween(FId, First, Second, Choice = 0);
  end
  else if TypeText = TypeBetweenPoint then
  begin
    if ReadInput(Item, 'a', False, First) and ReadInput(Item, 'b', False, Second) and ReadChoice(Item, 'mode', AlongModeNames, Choice) then
      Result := TBetweenPoint.Create(FId, First, Second, TAlongMode(Choice));
  end
  else if TypeText = TypeIntersectPoint then
  begin
    if ReadInput(Item, 'edgeA', True, First) and ReadInput(Item, 'edgeB', True, Second) and
      ReadBoolean(Item, 'extendA', FlagA) and ReadBoolean(Item, 'extendB', FlagB) and ReadPick(Item, Pick) then
      if First = Second then
        Problem(rsPatternSameEdge)
      else
        Result := TIntersectPoint.Create(FId, First, Second, FlagA, FlagB, Pick);
  end
  else if TypeText = TypeCircleEdgePoint then
  begin
    if ReadInput(Item, 'centre', False, First) and ReadInput(Item, 'edge', True, Second) and
      ReadBoolean(Item, 'extend', FlagA) and ReadPick(Item, Pick) then
      Result := TCircleEdgePoint.Create(FId, First, Second, FlagA, Pick);
  end
  else if TypeText = TypeProjectPoint then
  begin
    if ReadInput(Item, 'point', False, First) and ReadInput(Item, 'edge', True, Second) and
      ReadChoice(Item, 'direction', DirectionNames, Choice) and ReadBoolean(Item, 'extend', FlagA) then
      Result := TProjectPoint.Create(FId, First, Second, TProjectDirection(Choice), FlagA);
  end
  else if TypeText = TypeLine then
  begin
    if ReadInput(Item, 'start', False, First) and ReadInput(Item, 'end', False, Second) then
      Result := TLineObject.Create(FId, First, Second);
  end
  else if TypeText = TypeCurve then
  begin
    if ReadInput(Item, 'start', False, First) and ReadInput(Item, 'end', False, Second) then
      Result := TCurveObject.Create(FId, First, Second);
  end
  else if TypeText = TypeOffsetEdge then
  begin
    if ReadRun(Item, Run) and ReadChoice(Item, 'side', OffsetSideNames, Choice) then
      Result := TOffsetEdge.Create(FId, Run, RunStartKey(Run), RunEndKey(Run), TOffsetSide(Choice));
  end
  else if TypeText = TypeCornerArc then
  begin
    if ReadInput(Item, 'vertex', False, First) and ReadInput(Item, 'edgeA', True, Second) and ReadInput(Item, 'edgeB', True, Third) then
      Result := TCornerArc.Create(FId, First, Second, Third);
  end
  else if TypeText = TypeCornerPoint then
  begin
    if ReadInput(Item, 'arc', True, First) then
      if not GetJSONInteger(Item, 'end', Pick) or (Pick < 1) or (Pick > 2) then
        Missing('end')
      else
        Result := TCornerPoint.Create(FId, First, Pick);
  end
  else if TypeText = TypeCircle then
  begin
    if ReadInput(Item, 'centre', False, First) then
      Result := TCircleObject.Create(FId, First);
  end
  else if TypeText = TypeArc then
  begin
    if ReadInput(Item, 'centre', False, First) then
      Result := TArcObject.Create(FId, First);
  end
  else if TypeText = TypeCircleCirclePoint then
  begin
    if ReadInput(Item, 'centreA', False, First) and ReadInput(Item, 'centreB', False, Second) and ReadPick(Item, Pick) then
      if Pick > 2 then
        Problem(rsPatternBadPick)
      else
        Result := TCircleCirclePoint.Create(FId, First, Second, Pick);
  end
  else if TypeText = TypeCurvePath then
    Result := CreateCurvePath(Item)
  else if TypeText = TypePiece then
    Result := CreatePiece(Item)
  else if TypeText = TypeSeam then
    Result := CreateSeam(Item)
  else if TypeText = TypeNote then
    Result := CreateNote(Item)
  else if TypeText = TransformTypes[tkRotate] then
    Result := CreateTransform(Item, tkRotate)
  else if TypeText = TransformTypes[tkMirror] then
    Result := CreateTransform(Item, tkMirror)
  else if TypeText = TransformTypes[tkMove] then
    Result := CreateTransform(Item, tkMove)
  else if TypeText = TypePointCopy then
    Result := CreatePointCopy(Item)
  else if TypeText = TypeEdgeCopy then
    Result := CreateEdgeCopy(Item)
  else if TypeText = TypeSplitPart then
  begin
    if ReadInput(Item, 'edge', True, First) and ReadInput(Item, 'point', False, Second) then
      if not GetJSONInteger(Item, 'part', Part) or (Part < 1) or (Part > 2) then
        Missing('part')
      else
        Result := NewSplitPart(FId, TEdgeObject(FPattern.FindNode(First)), Second, Part);
  end
  else
    Fail(Format(rsPatternObjectUnknownType, [FId, TypeText]));
end;

// Each is an index with the ID it was given on first use
function TPatternLoader.ReadRepeatPoints(Item: TJSONObject; ARepeat: TRepeatObject): boolean;
var
  List: TJSONData;
  Entry: TJSONObject;
  Index, PointIndex: integer;
  Id: string;
begin
  List := Item.Find('points');
  if not Assigned(List) then
    Exit(True);
  if List.JSONType <> jtArray then
    Exit(Fail(Format(rsPatternFileList, ['points'])));
  for Index := 0 to List.Count - 1 do
  begin
    if List.Items[Index].JSONType <> jtObject then
      Exit(Fail(Format(rsPatternFileList, ['points'])));
    Entry := TJSONObject(List.Items[Index]);
    if not GetJSONInteger(Entry, 'index', PointIndex) or (PointIndex < 1) or ARepeat.HasUsedIndex(PointIndex) then
      Exit(Fail(Format(rsPatternFileBadRepeatPoint, [FId])));
    if not ReadFreeId(Entry, Id) then
      Exit(Fail(Format(rsPatternFileBadRepeatPoint, [FId])));
    FPattern.InsertRepeatPoint(ARepeat, PointIndex, Id);
  end;
  Result := True;
end;

// Read before the objects wherever they are in the file, as pieces refer to them
function TPatternLoader.LoadMaterials(Data: TJSONData): boolean;
var
  Index, Choice: integer;
  Item: TJSONObject;
  Id, AName, Color, Reason: string;
  Material: TPatternMaterial;
begin
  if not Assigned(Data) then
    Exit(True);
  if (Data.JSONType <> jtArray) or (Data.Count = 0) then
    Exit(Fail(Format(rsPatternFileList, ['materials'])));
  for Index := 0 to Data.Count - 1 do
  begin
    if Data.Items[Index].JSONType <> jtObject then
      Exit(Fail(Format(rsPatternFileList, ['materials'])));
    Item := TJSONObject(Data.Items[Index]);
    if not ReadFreeId(Item, Id) or not GetJSONString(Item, 'name', AName) then
      Exit(Fail(Format(rsPatternFileBadId, [Index + 1, 'materials'])));
    if not CheckName(AName, Reason) then
      Exit(Fail(Format(rsPatternMaterialProblem, [Id, Reason])));
    if (FPattern.MaterialCount > 0) and (FPattern.Materials[0].Key <> '') and Assigned(FPattern.FindMaterialNamed(AName)) then
      Exit(Fail(Format(rsPatternMaterialProblem, [Id, Format(rsPatternMaterialTaken, [AName])])));
    if not GetJSONString(Item, 'color', Color) or not IsMaterialColor(Color) then
      Exit(Fail(Format(rsPatternMaterialProblem, [Id, Format(rsPatternMaterialBadColor, [Color])])));
    FId := Id;
    Choice := 0;
    if Assigned(Item.Find('fill')) and not ReadChoice(Item, 'fill', MaterialFillNames, Choice) then
      Exit(False);
    Material := TPatternMaterial.Create;
    Material.Key := Id;
    Material.Name := AName;
    Material.Color := UpperCase(Color);
    Material.Fill := TMaterialFill(Choice);
    FPattern.InsertMaterial(Material);
    if Assigned(Item.Find('allowance')) then
    begin
      if not GetJSONNumber(Item, 'allowance', Material.Allowance) or (Material.Allowance < 0) then
        Exit(Missing('allowance'));
      Material.HasAllowance := True;
    end;
  end;
  Result := True;
end;

// Files from before drafts and layers were taken out list them, and objects
// name their layer. Everything goes on the one canvas; their IDs stay retired.
procedure TPatternLoader.RetireDraftIds(Data: TJSONData);

  procedure Retire(Item: TJSONData);
  var
    Value: integer;
  begin
    if (Item.JSONType = jtObject) and GetJSONInteger(TJSONObject(Item), 'id', Value) then
      FPattern.NextId := Math.Max(FPattern.NextId, Value + 1);
  end;

var
  Index, Inner: integer;
  Layers: TJSONData;
begin
  if not Assigned(Data) or (Data.JSONType <> jtArray) then
    Exit;
  for Index := 0 to Data.Count - 1 do
  begin
    Retire(Data.Items[Index]);
    if Data.Items[Index].JSONType <> jtObject then
      Continue;
    Layers := TJSONObject(Data.Items[Index]).Find('layers');
    if Assigned(Layers) and (Layers.JSONType = jtArray) then
      for Inner := 0 to Layers.Count - 1 do
        Retire(Layers.Items[Inner]);
  end;
end;

function TPatternLoader.LoadObject(Item: TJSONObject): boolean;
var
  DraftObject, Inserted: TDraftObject;
  TypeText, ObjectName, Msg: string;
  Index, Choice: integer;
  HasName: boolean;
begin
  if not GetJSONString(Item, 'type', TypeText) then
    Exit(Missing('type'));
  DraftObject := CreateObject(Item, TypeText);
  if not Assigned(DraftObject) then
    Exit(False);
  try
    // Points, pieces and seams need a name; an edge without one is named after its ends
    ObjectName := '';
    HasName := Assigned(Item.Find('name'));
    if HasName or (DraftObject is TPointObject) or (DraftObject is TPieceObject) or (DraftObject is TSeamObject) or
      (DraftObject is TNoteObject) or (DraftObject is TTransformObject) or (DraftObject is TRepeatObject) then
    begin
      if not GetJSONString(Item, 'name', ObjectName) then
        Exit(Missing('name'));
      if not FPattern.CheckObjectName(ObjectName, nil, Msg) then
        Exit(Problem(Msg));
    end;
    // The marker comes first, as it adds the size field read below
    if ((DraftObject is TPointObject) or (DraftObject is TRepeatObject)) and Assigned(Item.Find('marker')) then
    begin
      if not ReadChoice(Item, 'marker', PointMarkerNames, Choice) then
        Exit(False);
      DraftObject.SetMarker(TPointMarker(Choice));
    end;
    if DraftObject is TNoteObject then
    begin
      if not ReadNoteValues(Item, TNoteObject(DraftObject)) then
        Exit(False);
    end
    else if not (DraftObject is TCurvePathObject) and not (DraftObject is TPieceObject) then
      for Index := 0 to DraftObject.FieldCount - 1 do
        if not ReadFormula(Item, DraftObject.Fields[Index].Name, DraftObject, DraftObject.Fields[Index].Name) then
          Exit(False);
    if DraftObject is TEdgeObject then
    begin
      if not ReadChoice(Item, 'role', EdgeRoleNames, Choice) then
        Exit(False);
      TEdgeObject(DraftObject).Role := TEdgeRole(Choice);
      // The derived name is set once every object is loaded
      TEdgeObject(DraftObject).NameIsDerived := not HasName;
    end;
    DraftObject.Name := ObjectName;
    Inserted := DraftObject;
    FPattern.InsertObject(DraftObject);
    DraftObject := nil;
    Result := not (Inserted is TRepeatObject) or ReadRepeatPoints(Item, TRepeatObject(Inserted));
  finally
    FreeAndNil(DraftObject);
  end;
end;

function TPatternLoader.LoadObjects(Data: TJSONData): boolean;
var
  Index: integer;
  Item: TJSONObject;
begin
  if not Assigned(Data) then
    Exit(True);
  if Data.JSONType <> jtArray then
    Exit(Fail(Format(rsPatternFileList, ['objects'])));
  for Index := 0 to Data.Count - 1 do
  begin
    if Data.Items[Index].JSONType <> jtObject then
      Exit(Fail(Format(rsPatternFileList, ['objects'])));
    Item := TJSONObject(Data.Items[Index]);
    if not ReadFreeId(Item, FId) then
      Exit(Fail(Format(rsPatternFileBadId, [Index + 1, 'objects'])));
    if not LoadObject(Item) then
      Exit(False);
  end;
  Result := True;
end;

function TPatternLoader.Load(const Text: string): boolean;
var
  Root: TJSONObject;
  TextValue: string;
  Version, NextId: integer;
  Units: TMeasureUnit;
begin
  FPattern.Clear;
  if not ParseJSONObject(Text, Root, FError) then
    Exit(False);
  try
    if not GetJSONString(Root, 'format', TextValue) or (TextValue <> PatternFormat) or not GetJSONInteger(Root, 'version', Version) then
      Exit(Fail(rsPatternFileWrongFormat));
    if Version > PatternVersion then
      Exit(Fail(Format(rsPatternFileNewerVersion, [Version])));
    if GetJSONString(Root, 'units', TextValue) then
    begin
      if not MeasureUnitFromName(TextValue, Units) then
        Exit(Fail(Format(rsPatternFileUnits, [TextValue])));
      FPattern.Units := Units;
    end;
    RetireDraftIds(Root.Find('drafts'));
    if not LoadMaterials(Root.Find('materials')) or not LoadVariables(Root.Find('variables')) or not LoadObjects(Root.Find('objects')) then
      Exit(False);
    // Loading has put NextId above every ID; a saved counter may be higher,
    // because deleted IDs stay retired. Hand-written files may leave it out.
    if Assigned(Root.Find('nextId')) then
    begin
      if not GetJSONInteger(Root, 'nextId', NextId) or (NextId < FPattern.NextId) then
        Exit(Fail(rsPatternFileBadNextId));
      FPattern.NextId := NextId;
    end;
    // A member left out reads as empty
    GetJSONString(Root, 'notes', TextValue);
    FPattern.Notes := TextValue;
    GetJSONString(Root, 'measurementFile', TextValue);
    FPattern.MeasurementFile := TextValue;
    GetJSONString(Root, 'identity', TextValue);
    FPattern.Identity := TextValue;
    FPattern.UpdateDerivedNames;
    ReadPatternViewData(FPattern, Root.Find('view'));
    Result := True;
  finally
    FreeAndNil(Root);
  end;
end;

function TPatternLoader.AddItems(Variables, Objects: TJSONArray): boolean;
begin
  Result := LoadVariables(Variables) and LoadObjects(Objects);
  FPattern.UpdateDerivedNames;
end;

function PatternVariableToJSON(Variable: TVariable): TJSONObject;
begin
  Result := SaveVariable(Variable);
end;

function PatternObjectToJSON(DraftObject: TDraftObject): TJSONObject;
begin
  Result := SaveObject(DraftObject);
end;

function AddPatternItems(Pattern: TPattern; Variables, Objects: TJSONArray; IdMap: TPatternIdMap; out ErrorMessage: string): boolean;
var
  Loader: TPatternLoader;
begin
  Loader := TPatternLoader.Create(Pattern, IdMap);
  try
    Result := Loader.AddItems(Variables, Objects);
    ErrorMessage := Loader.Error;
  finally
    FreeAndNil(Loader);
  end;
end;

function LoadPatternFromText(Pattern: TPattern; const Text: string; out ErrorMessage: string): boolean;
var
  Loader: TPatternLoader;
begin
  Loader := TPatternLoader.Create(Pattern);
  try
    Result := Loader.Load(Text);
    ErrorMessage := Loader.Error;
    if not Result then
      Pattern.Clear;
  finally
    FreeAndNil(Loader);
  end;
end;

function SavePatternToFile(Pattern: TPattern; const FileName: string; out ErrorMessage: string): boolean;
begin
  Result := WriteTextFile(FileName, SavePatternToText(Pattern), ErrorMessage);
end;

function LoadPatternFromFile(Pattern: TPattern; const FileName: string; out ErrorMessage: string): boolean;
var
  Text: string;
begin
  Pattern.Clear;
  if not ReadTextFile(FileName, Text, ErrorMessage) then
    Exit(False);
  Result := LoadPatternFromText(Pattern, Text, ErrorMessage);
end;

function MeasurementFilePath(Pattern: TPattern; const PatternFileName: string): string;
var
  Folder: string;
begin
  if Pattern.MeasurementFile = '' then
    Exit('');
  Result := SetDirSeparators(Pattern.MeasurementFile);
  Folder := ExtractFileDir(PatternFileName);
  if (Result[1] <> PathDelim) and (ExtractFileDrive(Result) = '') and (Folder <> '') then
    Result := ConcatPaths([Folder, Result]);
end;

end.
