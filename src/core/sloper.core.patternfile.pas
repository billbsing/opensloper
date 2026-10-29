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
  Sloper.Core.Pattern;

const
  PatternFormat = 'pattern';
  PatternVersion = 1;

function SavePatternToText(Pattern: TPattern): string;
// Replaces the pattern's contents. On failure the pattern is left empty and
// ErrorMessage says why. A formula that does not parse is kept as text and
// shows as an error when evaluated. Call Evaluate afterwards.
function LoadPatternFromText(Pattern: TPattern; const Text: string; out ErrorMessage: string): boolean;
function SavePatternToFile(Pattern: TPattern; const FileName: string; out ErrorMessage: string): boolean;
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
  rsPatternVariableMissing = 'Variable %s has no valid "%s"';
  rsPatternVariableBadName = 'Variable %s: %s';
  rsPatternObjectMissing = 'Object %s has no valid "%s"';
  rsPatternObjectUnknownType = 'Object %s has an unknown type "%s"';
  rsPatternObjectNotBefore = 'Object %s uses %s, which is not defined before it';
  rsPatternObjectProblem = 'Object %s: %s';

implementation

uses
  SysUtils, fpjson, Sloper.Core.JSON, Sloper.Core.Names, Sloper.Core.Evaluator, Sloper.Core.Variables,
  Sloper.Core.Draft;

const
  TypeFreePoint = 'freePoint';
  TypeOffsetPoint = 'offsetPoint';
  TypeAlongEdgePoint = 'alongEdgePoint';
  TypeIntersectPoint = 'intersectPoint';
  TypeCircleEdgePoint = 'circleEdgePoint';
  TypeProjectPoint = 'projectPoint';
  TypeLine = 'line';
  TypeCurve = 'curve';
  TypeCurvePath = 'curvePath';
  TypeSplitPart = 'splitPart';

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
    function CreateCurvePath(Item: TJSONObject): TDraftObject;
    function LoadObject(Item: TJSONObject): boolean;
  public
    constructor Create(APattern: TPattern);
    function Load(const Text: string): boolean;
    property Error: string read FError;
  end;

function ObjectTypeName(DraftObject: TDraftObject): string;
begin
  if DraftObject is TFreePoint then
    Result := TypeFreePoint
  else if DraftObject is TOffsetPoint then
    Result := TypeOffsetPoint
  else if DraftObject is TAlongEdgePoint then
    Result := TypeAlongEdgePoint
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
  else
    raise Exception.CreateFmt('No file type for %s', [DraftObject.ClassName]);
end;

{ Saving }

function SaveVariable(Variable: TVariable): TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.Add('id', Variable.Key);
  Result.Add('name', Variable.Name);
  Result.Add('formula', Variable.Formula.StoredText);
  Result.Add('description', Variable.Description);
end;

function SaveCurvePathNodes(Path: TCurvePathObject): TJSONArray;
var
  Index: integer;
  NodeItem: TJSONObject;
  NodeName: string;
begin
  Result := TJSONArray.Create;
  for Index := 0 to High(Path.NodeKeys) do
  begin
    NodeName := 'node' + IntToStr(Index + 1);
    NodeItem := TJSONObject.Create;
    NodeItem.Add('point', Path.NodeKeys[Index]);
    NodeItem.Add('angle', Path.Field(NodeName + '.angle').StoredText);
    if Index > 0 then
      NodeItem.Add('lengthIn', Path.Field(NodeName + '.lengthIn').StoredText);
    if Index < High(Path.NodeKeys) then
      NodeItem.Add('lengthOut', Path.Field(NodeName + '.lengthOut').StoredText);
    Result.Add(NodeItem);
  end;
end;

// id, type and name; then inputs and options; then formulas under their
// field names; then the role of an edge
function SaveObject(DraftObject: TDraftObject): TJSONObject;
var
  Index: integer;
  Offset: TOffsetPoint;
  Along: TAlongEdgePoint;
  Intersect: TIntersectPoint;
  Circle: TCircleEdgePoint;
  Project: TProjectPoint;
  Part: TSplitPart;
begin
  Result := TJSONObject.Create;
  Result.Add('id', DraftObject.Key);
  Result.Add('type', ObjectTypeName(DraftObject));
  // A derived name (Line_A_B) is recomputed on loading
  if not ((DraftObject is TEdgeObject) and TEdgeObject(DraftObject).NameIsDerived) then
    Result.Add('name', DraftObject.Name);

  if DraftObject is TOffsetPoint then
  begin
    Offset := TOffsetPoint(DraftObject);
    Result.Add('base', Offset.Base);
    Result.Add('mode', OffsetModeNames[Offset.Mode]);
  end
  else if DraftObject is TAlongEdgePoint then
  begin
    Along := TAlongEdgePoint(DraftObject);
    Result.Add('edge', Along.Edge);
    Result.Add('from', EdgeEndNames[Along.FromEnd]);
    Result.Add('mode', AlongModeNames[Along.Mode]);
  end
  else if DraftObject is TIntersectPoint then
  begin
    Intersect := TIntersectPoint(DraftObject);
    Result.Add('edgeA', Intersect.EdgeA);
    Result.Add('edgeB', Intersect.EdgeB);
    Result.Add('extendA', Intersect.ExtendA);
    Result.Add('extendB', Intersect.ExtendB);
    Result.Add('pick', Intersect.Pick);
  end
  else if DraftObject is TCircleEdgePoint then
  begin
    Circle := TCircleEdgePoint(DraftObject);
    Result.Add('centre', Circle.Centre);
    Result.Add('edge', Circle.Edge);
    Result.Add('extend', Circle.Extend);
    Result.Add('pick', Circle.Pick);
  end
  else if DraftObject is TProjectPoint then
  begin
    Project := TProjectPoint(DraftObject);
    Result.Add('point', Project.Source);
    Result.Add('edge', Project.Edge);
    Result.Add('direction', DirectionNames[Project.Direction]);
    Result.Add('extend', Project.Extend);
  end
  else if DraftObject is TSplitPart then
  begin
    Part := TSplitPart(DraftObject);
    Result.Add('edge', Part.Source);
    Result.Add('point', Part.Point);
    Result.Add('part', Part.Part);
  end
  else if (DraftObject is TLineObject) or (DraftObject is TCurveObject) then
  begin
    Result.Add('start', TEdgeObject(DraftObject).StartKey);
    Result.Add('end', TEdgeObject(DraftObject).EndKey);
  end;

  if DraftObject is TCurvePathObject then
    Result.Add('nodes', SaveCurvePathNodes(TCurvePathObject(DraftObject)))
  else
    for Index := 0 to DraftObject.FieldCount - 1 do
      Result.Add(DraftObject.Fields[Index].Name, DraftObject.Fields[Index].Formula.StoredText);

  if DraftObject is TEdgeObject then
    Result.Add('role', RoleNames[TEdgeObject(DraftObject).Role]);
end;

function SavePatternToText(Pattern: TPattern): string;
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
    List := TJSONArray.Create;
    Root.Add('variables', List);
    for Index := 0 to Pattern.VariableCount - 1 do
      List.Add(SaveVariable(Pattern.Variables[Index]));
    List := TJSONArray.Create;
    Root.Add('objects', List);
    for Index := 0 to Pattern.ObjectCount - 1 do
      List.Add(SaveObject(Pattern.Objects[Index]));
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
begin
  if not GetJSONString(Item, AName, Key) then
    Exit(Missing(AName));
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

function IdIsFree(Pattern: TPattern; Item: TJSONObject; out Id: string): boolean;
begin
  Result := GetJSONString(Item, 'id', Id) and IsValidName(Id) and (Pattern.FindNode(Id) = nil);
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

function TPatternLoader.LoadObject(Item: TJSONObject): boolean;
var
  DraftObject: TDraftObject;
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
    // Points need a name; an edge without one is named after its ends
    ObjectName := '';
    HasName := Item.Find('name') <> nil;
    if HasName or (DraftObject is TPointObject) then
    begin
      if not GetJSONString(Item, 'name', ObjectName) then
        Exit(Missing('name'));
      if not FPattern.CheckObjectName(ObjectName, nil, Msg) then
        Exit(Problem(Msg));
    end;
    if not (DraftObject is TCurvePathObject) then
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
    FPattern.InsertObject(DraftObject);
    DraftObject := nil;
    Result := True;
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
  Version: integer;
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
    if not LoadVariables(Root.Find('variables')) or not LoadObjects(Root.Find('objects')) then
      Exit(False);
    GetJSONString(Root, 'notes', FPattern.Notes);
    GetJSONString(Root, 'measurementFile', FPattern.MeasurementFile);
    FPattern.UpdateDerivedNames;
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
