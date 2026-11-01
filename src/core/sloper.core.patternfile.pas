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
  SysUtils, Sloper.Core.EvalTypes, Sloper.Core.Draft, Sloper.Core.Drafts, Sloper.Core.Pattern;

const
  PatternFormat = 'pattern';
  PatternVersion = 1;

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
// The ID of the first object that differs between two sets of object texts
// from ObjectTexts, or ''
function ObjectTexts(Pattern: TPattern): TStringArray;
function FirstChangedObject(const Before, After: TStringArray): string;
// The object's "type" in a pattern file, such as offsetPoint
function PatternObjectTypeName(DraftObject: TDraftObject): string;
function LoadPatternFromFile(Pattern: TPattern; const FileName: string; out ErrorMessage: string): boolean;
// The pattern's measurement file as a path: relative to the folder of
// PatternFileName unless absolute. Stored with "/" on every platform. Empty
// when the pattern names none.
function MeasurementFilePath(Pattern: TPattern; const PatternFileName: string): string;

resourcestring
  rsPatternFileWrongFormat = 'This is not a pattern file';
  rsPatternFileNewerVersion = 'This file was made by a newer version of OpenSloper (file version %d)';
  rsPatternFileUnits = 'Units "%s" are not supported; use mm';
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

implementation

uses
  Math, fpjson, Sloper.Core.JSON, Sloper.Core.Evaluator, Sloper.Core.Variables, Sloper.Core.Piece, Sloper.Core.Seam, Sloper.Core.Transform;

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
  TypeCurvePath = 'curvePath';
  TypeSplitPart = 'splitPart';
  TypePiece = 'piece';
  TypeSeam = 'seam';
  TypePointCopy = 'pointCopy';
  TypeEdgeCopy = 'edgeCopy';
  TransformTypes: array[TTransformKind] of string = ('rotate', 'mirror', 'move');

  RoleNames: array[TEdgeRole] of string = ('construction', 'outline');
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
    function Fail(const Msg: string): boolean;
    function Missing(const AName: string): boolean;
    function Problem(const Msg: string): boolean;
    function ReadInput(Item: TJSONObject; const AName: string; WantEdge: boolean; out Key: string): boolean;
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
    function ReadSources(Item: TJSONObject; out Sources: TStringArray): boolean;
    function ReadTransformKey(Item: TJSONObject; out Key: string): boolean;
    function CreateTransform(Item: TJSONObject; Kind: TTransformKind): TDraftObject;
    function CreatePointCopy(Item: TJSONObject): TDraftObject;
    function CreateEdgeCopy(Item: TJSONObject): TDraftObject;
    function ReadGrainline(Item: TJSONObject; Piece: TPieceObject): boolean;
    function ReadNotches(Item: TJSONObject; Piece: TPieceObject): boolean;
    function ReadCut(Item: TJSONObject; Piece: TPieceObject): boolean;
    function ReadFold(Item: TJSONObject; Piece: TPieceObject): boolean;
    function ReadView(Item: TJSONObject; Piece: TPieceObject): boolean;
    function LoadDrafts(Data: TJSONData): boolean;
    function ReadLayer(Item: TJSONObject; DraftObject: TDraftObject): boolean;
    function LoadObject(Item: TJSONObject): boolean;
  public
    constructor Create(APattern: TPattern);
    function Load(const Text: string): boolean;
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
  else if DraftObject is TCurvePathObject then
    Result := TypeCurvePath
  else if DraftObject is TSplitPart then
    Result := TypeSplitPart
  else if DraftObject is TPieceObject then
    Result := TypePiece
  else if DraftObject is TSeamObject then
    Result := TypeSeam
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
  if ARepeat.UsedItems = nil then
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
    if DraftObject.LayerKey <> '' then
      Result.Add('layer', JSONId(DraftObject.LayerKey));

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
      if TPieceObject(DraftObject).Notches <> nil then
        Result.Add('notches', SaveNotches(TPieceObject(DraftObject)));
      Result.Add('cut', SaveCut(TPieceObject(DraftObject)));
      if TPieceObject(DraftObject).OnFold then
        Result.Add('foldEdge', JSONId(TPieceObject(DraftObject).FoldEdgeKey));
      if TPieceObject(DraftObject).View <> pvNone then
        Result.Add('view', PieceViewNames[Ord(TPieceObject(DraftObject).View)]);
    end
    else
      for Index := 0 to DraftObject.FieldCount - 1 do
        Result.Add(DraftObject.Fields[Index].Name, DraftObject.Fields[Index].Formula.StoredText);

    if DraftObject is TEdgeObject then
      Result.Add('role', RoleNames[TEdgeObject(DraftObject).Role]);
  except
    FreeAndNil(Result);
    raise;
  end;
end;

function SaveDrafts(Pattern: TPattern): TJSONArray;
var
  Index: integer;
  Draft: TPatternDraft;
  Layer: TPatternLayer;
  Item, Entry: TJSONObject;
  Layers: TJSONArray;
begin
  Result := TJSONArray.Create;
  try
    for Index := 0 to Pattern.DraftCount - 1 do
    begin
      Draft := Pattern.Drafts[Index];
      Item := TJSONObject.Create;
      Result.Add(Item);
      Item.Add('id', JSONId(Draft.Key));
      Item.Add('name', Draft.Name);
      Layers := TJSONArray.Create;
      Item.Add('layers', Layers);
      for Layer in Draft.Layers do
      begin
        Entry := TJSONObject.Create;
        Layers.Add(Entry);
        Entry.Add('id', JSONId(Layer.Key));
        Entry.Add('name', Layer.Name);
      end;
    end;
  except
    FreeAndNil(Result);
    raise;
  end;
end;

// The implicit first draft and layer have no key; 0 stands for them
function ViewId(const Key: string): integer;
begin
  Result := StrToIntDef(Key, 0);
end;

function SaveView(Pattern: TPattern): TJSONObject;
var
  Index: integer;
  Draft: TPatternDraft;
  Layer: TPatternLayer;
  Drafts, Item: TJSONObject;
  Hidden, Locked, Centre: TJSONArray;
begin
  Result := TJSONObject.Create;
  try
    Result.Add('draft', ViewId(Pattern.ActiveDraft.Key));
    if Pattern.SoloLayer <> nil then
      Result.Add('solo', ViewId(Pattern.SoloLayer.Key));
    Drafts := TJSONObject.Create;
    Result.Add('drafts', Drafts);
    for Index := 0 to Pattern.DraftCount - 1 do
    begin
      Draft := Pattern.Drafts[Index];
      Item := TJSONObject.Create;
      Drafts.Add(IntToStr(ViewId(Draft.Key)), Item);
      Item.Add('activeLayer', ViewId(Draft.ActiveLayer.Key));
      if Draft.HasView then
      begin
        Item.Add('zoom', JSONFloat(Draft.Zoom));
        Centre := TJSONArray.Create;
        Item.Add('centre', Centre);
        Centre.Add(JSONFloat(Draft.CentreX));
        Centre.Add(JSONFloat(Draft.CentreY));
      end;
      Hidden := TJSONArray.Create;
      Item.Add('hidden', Hidden);
      Locked := TJSONArray.Create;
      Item.Add('locked', Locked);
      for Layer in Draft.Layers do
      begin
        if Layer.Hidden then
          Hidden.Add(ViewId(Layer.Key));
        if Layer.Locked then
          Locked.Add(ViewId(Layer.Key));
      end;
    end;
  except
    FreeAndNil(Result);
    raise;
  end;
end;

function KeyOfViewId(Id: integer): string;
begin
  Result := '';
  if Id > 0 then
    Result := IntToStr(Id);
end;

// Whatever no longer exists is passed over: the view is only a convenience
procedure ReadPatternViewData(Pattern: TPattern; Data: TJSONData);
var
  Root, Drafts, Item: TJSONObject;
  Value, Index: integer;
  Draft: TPatternDraft;
  Layer: TPatternLayer;
  List: TJSONData;

  procedure MarkLayers(const AName: string; Hide: boolean);
  var
    Position: integer;
    Marked: TPatternLayer;
  begin
    List := Item.Find(AName);
    if (List = nil) or (List.JSONType <> jtArray) then
      Exit;
    for Position := 0 to List.Count - 1 do
      if List.Items[Position].JSONType = jtNumber then
      begin
        Marked := Draft.FindLayer(KeyOfViewId(List.Items[Position].AsInteger));
        if (Marked <> nil) and Hide then
          Marked.Hidden := True
        else if Marked <> nil then
          Marked.Locked := True;
      end;
  end;

begin
  if (Data = nil) or (Data.JSONType <> jtObject) then
    Exit;
  Root := TJSONObject(Data);
  if GetJSONInteger(Root, 'draft', Value) and (Pattern.FindDraft(KeyOfViewId(Value)) <> nil) then
    Pattern.ActiveDraft := Pattern.FindDraft(KeyOfViewId(Value));
  if GetJSONInteger(Root, 'solo', Value) then
    Pattern.SoloLayer := Pattern.FindLayer(KeyOfViewId(Value), Draft);
  if (Root.Find('drafts') = nil) or (Root.Find('drafts').JSONType <> jtObject) then
    Exit;
  Drafts := TJSONObject(Root.Find('drafts'));
  for Index := 0 to Pattern.DraftCount - 1 do
  begin
    Draft := Pattern.Drafts[Index];
    Data := Drafts.Find(IntToStr(ViewId(Draft.Key)));
    if (Data = nil) or (Data.JSONType <> jtObject) then
      Continue;
    Item := TJSONObject(Data);
    if GetJSONInteger(Item, 'activeLayer', Value) then
    begin
      Layer := Draft.FindLayer(KeyOfViewId(Value));
      if Layer <> nil then
        Draft.ActiveLayer := Layer;
    end;
    List := Item.Find('centre');
    if GetJSONNumber(Item, 'zoom', Draft.Zoom) and (List <> nil) and (List.JSONType = jtArray) and (List.Count = 2) then
    begin
      Draft.CentreX := List.Items[0].AsFloat;
      Draft.CentreY := List.Items[1].AsFloat;
      Draft.HasView := True;
    end;
    MarkLayers('hidden', True);
    MarkLayers('locked', False);
  end;
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

function ObjectTexts(Pattern: TPattern): TStringArray;
var
  Index: integer;
  Item: TJSONObject;
begin
  Result := nil;
  SetLength(Result, Pattern.ObjectCount);
  for Index := 0 to Pattern.ObjectCount - 1 do
  begin
    Item := SaveObject(Pattern.Objects[Index]);
    try
      Result[Index] := Pattern.Objects[Index].Key + #9 + Item.AsJSON;
    finally
      FreeAndNil(Item);
    end;
  end;
end;

function FirstChangedObject(const Before, After: TStringArray): string;

  function KeyOf(const Text: string): string;
  begin
    Result := Copy(Text, 1, Pos(#9, Text) - 1);
  end;

  function IsIn(const Text: string; const List: TStringArray): boolean;
  var
    Item: string;
  begin
    Result := False;
    for Item in List do
      if Item = Text then
        Exit(True);
  end;

var
  Text: string;
begin
  Result := '';
  for Text in After do
    if not IsIn(Text, Before) then
      Exit(KeyOf(Text));
  for Text in Before do
    if not IsIn(Text, After) then
      Exit(KeyOf(Text));
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
    Root.Add('units', 'mm');
    Root.Add('notes', Pattern.Notes);
    Root.Add('measurementFile', Pattern.MeasurementFile);
    if WithNextId then
      Root.Add('nextId', Pattern.NextId);
    // One unchanged draft and layer write nothing, so simple files stay simple
    if Pattern.Drafts[0].Key <> '' then
      Root.Add('drafts', SaveDrafts(Pattern));
    List := TJSONArray.Create;
    Root.Add('variables', List);
    for Index := 0 to Pattern.VariableCount - 1 do
      List.Add(SaveVariable(Pattern.Variables[Index]));
    List := TJSONArray.Create;
    Root.Add('objects', List);
    for Index := 0 to Pattern.ObjectCount - 1 do
      List.Add(SaveObject(Pattern.Objects[Index]));
    if WithNextId and (Pattern.Drafts[0].Key <> '') then
      Root.Add('view', SaveView(Pattern));
    Result := JSONToText(Root);
  finally
    FreeAndNil(Root);
  end;
end;

{ Loading }

constructor TPatternLoader.Create(APattern: TPattern);
begin
  FPattern := APattern;
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
  Key := IntToStr(Id);
  Node := FPattern.FindNode(Key);
  if Node = nil then
    Exit(Fail(Format(rsPatternObjectNotBefore, [FId, Key])));
  if WantEdge and not (Node is TEdgeObject) then
    Exit(Problem(Format(rsDraftNotAnEdge, [NodeLabel(Node)])));
  if not WantEdge and not (Node is TPointObject) then
    Exit(Problem(Format(rsDraftNotAPoint, [NodeLabel(Node)])));
  Result := True;
end;

// Optional; False when absent
function TPatternLoader.ReadBoolean(Item: TJSONObject; const AName: string; out Value: boolean): boolean;
begin
  Value := False;
  if Item.Find(AName) = nil then
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
  if Item.Find(AName) = nil then
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
  if Item.Find('pick') = nil then
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
  Node.Field(AField).ParseStored(Text);
  Result := True;
end;

// A positive integer not used by anything loaded so far
function IdIsFree(Pattern: TPattern; Item: TJSONObject; out Id: string): boolean;
var
  Value: integer;
  Found: TPatternDraft;
begin
  Id := '';
  if not GetJSONInteger(Item, 'id', Value) or (Value < 1) then
    Exit(False);
  Id := IntToStr(Value);
  Result := (Pattern.FindNode(Id) = nil) and (Pattern.FindDraft(Id) = nil) and (Pattern.FindLayer(Id, Found) = nil);
end;

function TPatternLoader.LoadVariables(Data: TJSONData): boolean;
var
  Index: integer;
  Item: TJSONObject;
  Id, VariableName, Text, Description, Msg: string;
  Variable: TVariable;
begin
  if Data = nil then
    Exit(True);
  if Data.JSONType <> jtArray then
    Exit(Fail(Format(rsPatternFileList, ['variables'])));
  for Index := 0 to Data.Count - 1 do
  begin
    if Data.Items[Index].JSONType <> jtObject then
      Exit(Fail(Format(rsPatternFileList, ['variables'])));
    Item := TJSONObject(Data.Items[Index]);
    if not IdIsFree(FPattern, Item, Id) then
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
    Variable.Formula.ParseStored(Text);
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
  if (Nodes = nil) or (Nodes.JSONType <> jtArray) then
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
  if Data = nil then
    Exit(True);
  if Data.JSONType <> jtObject then
    Exit(Missing('grainline'));
  Grain := TJSONObject(Data);
  if Grain.Find('angle') <> nil then
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
function TPatternLoader.ReadNotches(Item: TJSONObject; Piece: TPieceObject): boolean;
var
  Data: TJSONData;
  Notch: TJSONObject;
  Index, Added: integer;
  Key: string;
begin
  Data := Item.Find('notches');
  if Data = nil then
    Exit(True);
  if Data.JSONType <> jtArray then
    Exit(Missing('notches'));
  for Index := 0 to Data.Count - 1 do
  begin
    if Data.Items[Index].JSONType <> jtObject then
      Exit(Missing('notches'));
    Notch := TJSONObject(Data.Items[Index]);
    if Notch.Find('point') <> nil then
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
  if Data = nil then
    Exit(True);
  if Data.JSONType <> jtObject then
    Exit(Missing('cut'));
  Cut := TJSONObject(Data);
  Count := 1;
  if (Cut.Find('count') <> nil) and not GetJSONInteger(Cut, 'count', Count) then
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
// Optional: none when absent
function TPatternLoader.ReadView(Item: TJSONObject; Piece: TPieceObject): boolean;
var
  Choice: integer;
begin
  if Item.Find('view') = nil then
    Exit(True);
  Result := ReadChoice(Item, 'view', PieceViewNames, Choice);
  if Result then
    Piece.View := TPieceView(Choice);
end;

function TPatternLoader.ReadFold(Item: TJSONObject; Piece: TPieceObject): boolean;
var
  Key: string;
begin
  if Item.Find('foldEdge') = nil then
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
  if (Entries = nil) or (Entries.JSONType <> jtArray) then
  begin
    Missing('path');
    Exit;
  end;
  if Entries.Count < 2 then
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
    if Entry.Find(PieceAllowanceField) = nil then
      Continue;
    Piece.AddOverride(Index);
    if not ReadFormula(Entry, PieceAllowanceField, Piece, Piece.OverrideField(Index)) then
    begin
      FreeAndNil(Result);
      Exit;
    end;
  end;
  if not ReadGrainline(Item, Piece) or not ReadNotches(Item, Piece) or not ReadCut(Item, Piece) or not ReadFold(Item, Piece) or not ReadView(Item, Piece) then
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
  if (Entries = nil) or (Entries.JSONType <> jtArray) then
    Exit(Missing(AName));
  SetLength(Side, Entries.Count);
  for Index := 0 to Entries.Count - 1 do
  begin
    if Entries.Items[Index].JSONType <> jtObject then
      Exit(Missing(AName));
    Entry := TJSONObject(Entries.Items[Index]);
    if not GetJSONInteger(Entry, 'piece', PieceId) or not GetJSONInteger(Entry, 'edge', EdgeId) then
      Exit(Missing(AName));
    Side[Index].PieceKey := IntToStr(PieceId);
    Side[Index].EdgeKey := IntToStr(EdgeId);
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

function TPatternLoader.ReadSources(Item: TJSONObject; out Sources: TStringArray): boolean;
var
  List: TJSONData;
  Index: integer;
  Node: TEvalNode;
  Key: string;
begin
  Sources := nil;
  List := Item.Find('sources');
  if (List = nil) or (List.JSONType <> jtArray) or (List.Count = 0) then
    Exit(Missing('sources'));
  for Index := 0 to List.Count - 1 do
  begin
    if List.Items[Index].JSONType <> jtNumber then
      Exit(Missing('sources'));
    Key := IntToStr(List.Items[Index].AsInteger);
    Node := FPattern.FindNode(Key);
    if Node = nil then
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
  Key := IntToStr(Id);
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
      if (Item.Find('pivot') <> nil) and not ReadInput(Item, 'pivot', False, First) then
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
      if (Item.Find('axis') = nil) or (Item.Find('axis').JSONType <> jtObject) then
      begin
        Missing('axis');
        FreeAndNil(Result);
        Exit;
      end;
      Axis := TJSONObject(Item.Find('axis'));
      if Axis.Find('edge') <> nil then
      begin
        if ReadInput(Axis, 'edge', True, First) then
          Transform.UseAxisEdge(First)
        else
          FreeAndNil(Result);
      end
      else if not ReadInput(Axis, 'a', False, First) then
        FreeAndNil(Result)
      else if Axis.Find('b') = nil then
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
  First, Second: string;
  Choice, EndChoice, Pick, Part: integer;
  FlagA, FlagB: boolean;
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
    if Item.Find('edge') <> nil then
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
  else if TypeText = TypeCurvePath then
    Result := CreateCurvePath(Item)
  else if TypeText = TypePiece then
    Result := CreatePiece(Item)
  else if TypeText = TypeSeam then
    Result := CreateSeam(Item)
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
  if List = nil then
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
    if not IdIsFree(FPattern, Entry, Id) then
      Exit(Fail(Format(rsPatternFileBadRepeatPoint, [FId])));
    FPattern.InsertRepeatPoint(ARepeat, PointIndex, Id);
  end;
  Result := True;
end;

function TPatternLoader.LoadDrafts(Data: TJSONData): boolean;
var
  Index, Inner: integer;
  Item, Entry: TJSONObject;
  Layers: TJSONData;
  Id, LayerId, AName: string;
  Draft: TPatternDraft;
  Found: TPatternDraft;
begin
  if Data = nil then
    Exit(True);
  if (Data.JSONType <> jtArray) or (Data.Count = 0) then
    Exit(Fail(Format(rsPatternFileList, ['drafts'])));
  for Index := 0 to Data.Count - 1 do
  begin
    if Data.Items[Index].JSONType <> jtObject then
      Exit(Fail(Format(rsPatternFileList, ['drafts'])));
    Item := TJSONObject(Data.Items[Index]);
    if not IdIsFree(FPattern, Item, Id) or not GetJSONString(Item, 'name', AName) then
      Exit(Fail(Format(rsPatternFileBadId, [Index + 1, 'drafts'])));
    Layers := Item.Find('layers');
    if (Layers = nil) or (Layers.JSONType <> jtArray) or (Layers.Count = 0) then
      Exit(Fail(Format(rsPatternFileList, ['layers'])));
    Draft := TPatternDraft.Create(Id, AName);
    FPattern.InsertDraft(Draft);
    for Inner := 0 to Layers.Count - 1 do
    begin
      if Layers.Items[Inner].JSONType <> jtObject then
        Exit(Fail(Format(rsPatternFileList, ['layers'])));
      Entry := TJSONObject(Layers.Items[Inner]);
      if not IdIsFree(FPattern, Entry, LayerId) or not GetJSONString(Entry, 'name', AName) then
        Exit(Fail(Format(rsPatternFileBadId, [Inner + 1, 'layers'])));
      Draft.AddLayer(LayerId, AName);
      FPattern.NextId := Math.Max(FPattern.NextId, StrToInt(LayerId) + 1);
    end;
    if FPattern.FindLayer(Id, Found) <> nil then
      Exit(Fail(Format(rsPatternFileBadId, [Index + 1, 'drafts'])));
  end;
  Result := True;
end;

// Optional: an object with no layer goes on the first draft's first layer
function TPatternLoader.ReadLayer(Item: TJSONObject; DraftObject: TDraftObject): boolean;
var
  Id: integer;
  Found: TPatternDraft;
begin
  Result := True;
  DraftObject.LayerKey := FPattern.Drafts[0].Layers[0].Key;
  if Item.Find('layer') = nil then
    Exit;
  if not GetJSONInteger(Item, 'layer', Id) or (FPattern.FindLayer(IntToStr(Id), Found) = nil) then
    Exit(Missing('layer'));
  DraftObject.LayerKey := IntToStr(Id);
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
  if DraftObject = nil then
    Exit(False);
  try
    // Points, pieces and seams need a name; an edge without one is named after its ends
    ObjectName := '';
    HasName := Item.Find('name') <> nil;
    if HasName or (DraftObject is TPointObject) or (DraftObject is TPieceObject) or (DraftObject is TSeamObject) or
      (DraftObject is TTransformObject) or (DraftObject is TRepeatObject) then
    begin
      if not GetJSONString(Item, 'name', ObjectName) then
        Exit(Missing('name'));
      if not FPattern.CheckObjectName(ObjectName, nil, Msg) then
        Exit(Problem(Msg));
    end;
    if not (DraftObject is TCurvePathObject) and not (DraftObject is TPieceObject) then
      for Index := 0 to DraftObject.FieldCount - 1 do
        if not ReadFormula(Item, DraftObject.Fields[Index].Name, DraftObject, DraftObject.Fields[Index].Name) then
          Exit(False);
    if DraftObject is TEdgeObject then
    begin
      if not ReadChoice(Item, 'role', RoleNames, Choice) then
        Exit(False);
      TEdgeObject(DraftObject).Role := TEdgeRole(Choice);
      // The derived name is set once every object is loaded
      TEdgeObject(DraftObject).NameIsDerived := not HasName;
    end;
    DraftObject.Name := ObjectName;
    if not ReadLayer(Item, DraftObject) then
      Exit(False);
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
  if Data = nil then
    Exit(True);
  if Data.JSONType <> jtArray then
    Exit(Fail(Format(rsPatternFileList, ['objects'])));
  for Index := 0 to Data.Count - 1 do
  begin
    if Data.Items[Index].JSONType <> jtObject then
      Exit(Fail(Format(rsPatternFileList, ['objects'])));
    Item := TJSONObject(Data.Items[Index]);
    if not IdIsFree(FPattern, Item, FId) then
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
begin
  FPattern.Clear;
  if not ParseJSONObject(Text, Root, FError) then
    Exit(False);
  try
    if not GetJSONString(Root, 'format', TextValue) or (TextValue <> PatternFormat) or not GetJSONInteger(Root, 'version', Version) then
      Exit(Fail(rsPatternFileWrongFormat));
    if Version > PatternVersion then
      Exit(Fail(Format(rsPatternFileNewerVersion, [Version])));
    if GetJSONString(Root, 'units', TextValue) and (TextValue <> 'mm') then
      Exit(Fail(Format(rsPatternFileUnits, [TextValue])));
    if not LoadDrafts(Root.Find('drafts')) or not LoadVariables(Root.Find('variables')) or not LoadObjects(Root.Find('objects')) then
      Exit(False);
    // Loading has put NextId above every ID; a saved counter may be higher,
    // because deleted IDs stay retired. Hand-written files may leave it out.
    if Root.Find('nextId') <> nil then
    begin
      if not GetJSONInteger(Root, 'nextId', NextId) or (NextId < FPattern.NextId) then
        Exit(Fail(rsPatternFileBadNextId));
      FPattern.NextId := NextId;
    end;
    GetJSONString(Root, 'notes', FPattern.Notes);
    GetJSONString(Root, 'measurementFile', FPattern.MeasurementFile);
    FPattern.UpdateDerivedNames;
    ReadPatternViewData(FPattern, Root.Find('view'));
    Result := True;
  finally
    FreeAndNil(Root);
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
