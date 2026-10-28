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

// A pattern: variables and draft objects in one dependency graph, with the
// measurement set they read. All edits go through TPattern, which checks
// names, parses formulas, refuses circular references and keeps derived
// names up to date. Evaluate computes everything in dependency order.
// No LCL dependency.
unit osPattern;

{$mode ObjFPC}{$H+}

interface

uses
  Classes, SysUtils, fpjson, osEvalTypes, osEvaluator, osFormula,
  osMeasurements, osVariables, osDraft;

type
  TPattern = class
  private
    FMeasurements: TMeasurementSet;
    FMeasurementNodes: TList;
    FVariables: TList;
    FObjects: TList;
    FNextPoint, FNextLine, FNextCurve, FNextVariable: integer;
    FEvaluator: TEvaluator;
    FResolver: TNameResolver;          // objects, variables, measurements
    FVariableResolver: TNameResolver;  // variables and measurements only
    FContext: TEvalContext;
    FLastError: string;
    FLastErrorField: string;
    FLastErrorPos: integer;
    FNameExclude: TDraftObject;
    function GetVariableCount: integer;
    function GetVariable(Index: integer): TVariable;
    function GetObjectCount: integer;
    function GetObject(Index: integer): TDraftObject;
    function SetError(const Msg: string; const AField: string = ''; Pos: integer = 0): boolean;
    function ObjectNameTaken(const AName: string): boolean;
    function ResolverFor(Node: TEvalNode): TNameResolver;
    function ParseFields(Node: TEvalNode; const Names, Texts: array of string): boolean;
    function CheckPoint(const Id: string): boolean;
    function CheckEdgeTarget(const Id: string): boolean;
    function AddPointObject(APoint: TPointObject; const AName: string;
      const Names, Texts: array of string): boolean;
    function AddEdgeObject(AEdge: TEdgeObject; const AName: string; ARole: TEdgeRole;
      const Names, Texts: array of string): boolean;
    function DerivedEdgeName(AEdge: TEdgeObject): string;
    procedure UpdateDerivedNames;
    procedure RebuildMeasurementNodes;
    function AllNodes: TEvalNodeArray;
  public
    constructor Create;
    destructor Destroy; override;
    procedure Clear;

    // Node by key: an object or variable ID, or '@key' for a measurement
    // the pattern uses (after Evaluate)
    function FindNode(const Key: string): TEvalNode;
    function FindObject(const AName: string): TDraftObject;
    function FindVariable(const AName: string): TVariable;
    function CheckObjectName(const AName: string; Exclude: TDraftObject; out ErrorMessage: string): boolean;
    function CheckVariableName(const AName: string; Exclude: TVariable; out ErrorMessage: string): boolean;

    // Adding returns nil when refused, with the reason in LastError,
    // LastErrorField and LastErrorPos. An empty point name takes the next
    // automatic name; an empty edge name is derived from its ends.
    function AddVariable(const AName, FormulaText: string; const Description: string = ''): TVariable;
    function AddFreePoint(const AName, XText, YText: string): TFreePoint;
    // LengthOrDx and AngleOrDy are length and angle (omPolar) or dx and dy (omCartesian)
    function AddOffsetPoint(const AName, BaseId: string; Mode: TOffsetMode; const LengthOrDx, AngleOrDy: string): TOffsetPoint;
    function AddAlongEdgePoint(const AName, EdgeId: string; FromEnd: boolean;
      Mode: TAlongMode; const Value: string): TAlongEdgePoint;
    // Where two edges cross; Pick numbers the crossings from 1 along EdgeA
    function AddIntersectPoint(const AName, EdgeAId, EdgeBId: string;
      ExtendA, ExtendB: boolean; Pick: integer): TIntersectPoint;
    // Where a circle around CentreId crosses an edge (a compass step)
    function AddCircleEdgePoint(const AName, CentreId, Radius, EdgeId: string;
      Extend: boolean; Pick: integer): TCircleEdgePoint;
    // From SourceId onto an edge, square to it or at the Angle formula
    // (Angle is ignored for pdPerpendicular)
    function AddProjectPoint(const AName, SourceId, EdgeId: string;
      Direction: TProjectDirection; const Angle: string; Extend: boolean): TProjectPoint;
    function AddLine(const StartId, EndId: string; Role: TEdgeRole = erConstruction;
      const AName: string = ''): TLineObject;
    function AddCurve(const StartId, EndId, Angle1, Length1, Angle2, Length2: string;
      Role: TEdgeRole = erConstruction; const AName: string = ''): TCurveObject;

    // A smooth curve through NodeIds. Angles are the tangent at each node
    // (direction of travel); LengthsIn and LengthsOut the handle lengths before
    // and after it. All arrays have one entry per node; LengthsIn[0] and the
    // last LengthsOut are ignored.
    function AddCurvePath(const NodeIds, Angles, LengthsIn, LengthsOut: array of string;
      Role: TEdgeRole = erConstruction; const AName: string = ''): TCurvePathObject;
    // Splits an edge at a point on it into two new edges, which follow the
    // edge and the point. The edge itself stays.
    function SplitEdge(const EdgeId, PointId: string; out First, Second: TSplitPart): boolean;

    // Editing returns False when refused, with the reason in LastError
    function SetFormula(Node: TEvalNode; const AField, Text: string): boolean;
    function Rename(Node: TEvalNode; const NewName: string): boolean;
    // Refused while other nodes use Node
    function Delete(Node: TEvalNode): boolean;
    // Nodes that read Node directly
    function UsersOf(Node: TEvalNode): TEvalNodeArray;
    // A formula as the user sees it, with current names
    function FormulaText(Node: TEvalNode; const AField: string): string;

    // Rebuilds the graph and computes everything
    procedure Evaluate;

    function SaveVariables: TJSONArray;
    // Replaces the variables. Fails on a malformed list; a formula that does
    // not parse is kept as text and shows as an error.
    function LoadVariables(Data: TJSONData; out ErrorMessage: string): boolean;

    // Not owned. Can be nil or swapped for another person's set.
    property Measurements: TMeasurementSet read FMeasurements write FMeasurements;
    property Resolver: TNameResolver read FResolver;
    property Evaluator: TEvaluator read FEvaluator;
    property VariableCount: integer read GetVariableCount;
    property Variables[Index: integer]: TVariable read GetVariable;
    property ObjectCount: integer read GetObjectCount;
    property Objects[Index: integer]: TDraftObject read GetObject;
    property LastError: string read FLastError;
    property LastErrorField: string read FLastErrorField;
    property LastErrorPos: integer read FLastErrorPos;
  end;

resourcestring
  rsPatternUnknownObject = 'There is no object %s';
  rsPatternUsesItself = '%s cannot use itself';
  rsPatternCycle = '%s cannot use %s, because %s already uses %s';
  rsPatternInUse = '%s is used by %s';
  rsPatternNoField = '%s has no formula "%s"';
  rsPatternCannotRename = '%s cannot be renamed';
  rsPatternCannotDelete = '%s cannot be deleted';
  rsPatternSameEdge = 'An edge cannot cross itself';
  rsPatternBadPick = 'The crossing number must be 1 or more';
  rsPatternPathTooShort = 'A curve path needs at least two points';
  rsPatternPathRepeats = 'A curve path cannot use the same point twice in a row';
  rsPatternPathArrays = 'A curve path needs an angle and handle lengths for every point';
  rsPatternVariableList = 'The variable list is not valid';
  rsPatternVariableBadId = 'A variable has a missing or repeated ID';
  rsPatternVariableBadName = 'Variable name: %s';
  rsPatternVariableNoFormula = 'Variable "%s" has no formula';

implementation

uses
  osNames, osJSON;

type
  TPatternResolver = class(TNameResolver)
  private
    FPattern: TPattern;
    FAllowObjects: boolean;
  public
    constructor Create(APattern: TPattern; AllowObjects: boolean);
    function ResolveMeasurement(const AName: string; out Key: string): boolean; override;
    function ResolveVariable(const AName: string; out Id: string): boolean; override;
    function ResolveObject(const AName: string; out Id: string): boolean; override;
    function ResolveProperty(const ObjectId, Prop: string; out CanonicalProp: string): boolean; override;
    function VariableName(const Id: string; out AName: string): boolean; override;
    function ObjectName(const Id: string; out AName: string): boolean; override;
  end;

  TPatternContext = class(TEvalContext)
  private
    FPattern: TPattern;
  public
    constructor Create(APattern: TPattern);
    function FindNode(const Key: string): TEvalNode; override;
    function MeasurementValue(const Key: string; out Value: double): boolean; override;
    function VariableValue(const Id: string; out Value: double): boolean; override;
    function PropertyValue(const ObjectId, Prop: string; out Value: double): boolean; override;
  end;

  { TPatternResolver }

constructor TPatternResolver.Create(APattern: TPattern; AllowObjects: boolean);
begin
  FPattern := APattern;
  FAllowObjects := AllowObjects;
end;

function TPatternResolver.ResolveMeasurement(const AName: string; out Key: string): boolean;
var
  Measurement: TMeasurement;
begin
  Key := '';
  if FPattern.Measurements = nil then
    Exit(False);
  Measurement := FPattern.Measurements.Find(AName);
  Result := Measurement <> nil;
  if Result then
    Key := Measurement.Key;
end;

function TPatternResolver.ResolveVariable(const AName: string; out Id: string): boolean;
var
  Variable: TVariable;
begin
  Variable := FPattern.FindVariable(AName);
  Result := Variable <> nil;
  if Result then
    Id := Variable.Key
  else
    Id := '';
end;

function TPatternResolver.ResolveObject(const AName: string; out Id: string): boolean;
var
  DraftObject: TDraftObject;
begin
  Id := '';
  if not FAllowObjects then
    Exit(False);
  DraftObject := FPattern.FindObject(AName);
  Result := DraftObject <> nil;
  if Result then
    Id := DraftObject.Key;
end;

function TPatternResolver.ResolveProperty(const ObjectId, Prop: string;
  out CanonicalProp: string): boolean;
var
  Node: TEvalNode;
begin
  CanonicalProp := LowerCase(Prop);
  Node := FPattern.FindNode(ObjectId);
  Result := (Node is TDraftObject) and TDraftObject(Node).HasProperty(CanonicalProp);
end;

function TPatternResolver.VariableName(const Id: string; out AName: string): boolean;
var
  Node: TEvalNode;
begin
  Node := FPattern.FindNode(Id);
  Result := Node is TVariable;
  if Result then
    AName := TVariable(Node).Name
  else
    AName := '';
end;

function TPatternResolver.ObjectName(const Id: string; out AName: string): boolean;
var
  Node: TEvalNode;
begin
  Node := FPattern.FindNode(Id);
  Result := Node is TDraftObject;
  if Result then
    AName := TDraftObject(Node).Name
  else
    AName := '';
end;

{ TPatternContext }

constructor TPatternContext.Create(APattern: TPattern);
begin
  FPattern := APattern;
end;

function TPatternContext.FindNode(const Key: string): TEvalNode;
begin
  Result := FPattern.FindNode(Key);
end;

function TPatternContext.MeasurementValue(const Key: string; out Value: double): boolean;
begin
  Value := 0;
  Result := (FPattern.Measurements <> nil) and FPattern.Measurements.TryGetValue(Key, Value);
end;

function TPatternContext.VariableValue(const Id: string; out Value: double): boolean;
var
  Node: TEvalNode;
begin
  Value := 0;
  Node := FPattern.FindNode(Id);
  Result := (Node is TVariable) and (Node.State = esValid);
  if Result then
    Value := TVariable(Node).Value;
end;

function TPatternContext.PropertyValue(const ObjectId, Prop: string; out Value: double): boolean;
var
  Node: TEvalNode;
begin
  Value := 0;
  Node := FPattern.FindNode(ObjectId);
  Result := (Node is TDraftObject) and (Node.State = esValid) and TDraftObject(Node).HasProperty(Prop);
  if Result then
    Value := TDraftObject(Node).PropertyValue(Prop);
end;

{ TPattern }

constructor TPattern.Create;
begin
  FMeasurementNodes := TList.Create;
  FVariables := TList.Create;
  FObjects := TList.Create;
  FEvaluator := TEvaluator.Create;
  FResolver := TPatternResolver.Create(Self, True);
  FVariableResolver := TPatternResolver.Create(Self, False);
  FContext := TPatternContext.Create(Self);
  Clear;
end;

destructor TPattern.Destroy;
begin
  Clear;
  FMeasurementNodes.Free;
  FVariables.Free;
  FObjects.Free;
  FEvaluator.Free;
  FResolver.Free;
  FVariableResolver.Free;
  FContext.Free;
  inherited Destroy;
end;

procedure FreeItems(List: TList);
var
  Index: integer;
begin
  for Index := 0 to List.Count - 1 do
    TObject(List[Index]).Free;
  List.Clear;
end;

procedure TPattern.Clear;
begin
  // The evaluator holds node references; drop them first
  FEvaluator.Rebuild(nil, FContext);
  FreeItems(FMeasurementNodes);
  FreeItems(FVariables);
  FreeItems(FObjects);
  FNextPoint := 1;
  FNextLine := 1;
  FNextCurve := 1;
  FNextVariable := 1;
end;

function TPattern.GetVariableCount: integer;
begin
  Result := FVariables.Count;
end;

function TPattern.GetVariable(Index: integer): TVariable;
begin
  Result := TVariable(FVariables[Index]);
end;

function TPattern.GetObjectCount: integer;
begin
  Result := FObjects.Count;
end;

function TPattern.GetObject(Index: integer): TDraftObject;
begin
  Result := TDraftObject(FObjects[Index]);
end;

function TPattern.SetError(const Msg: string; const AField: string; Pos: integer): boolean;
begin
  FLastError := Msg;
  FLastErrorField := AField;
  FLastErrorPos := Pos;
  Result := False;
end;

function TPattern.FindNode(const Key: string): TEvalNode;
var
  Index: integer;
begin
  if (Key <> '') and (Key[1] = '@') then
  begin
    for Index := 0 to FMeasurementNodes.Count - 1 do
      if SameText(TEvalNode(FMeasurementNodes[Index]).Key, Key) then
        Exit(TEvalNode(FMeasurementNodes[Index]));
    Exit(nil);
  end;
  for Index := 0 to FObjects.Count - 1 do
    if Objects[Index].Key = Key then
      Exit(Objects[Index]);
  for Index := 0 to FVariables.Count - 1 do
    if Variables[Index].Key = Key then
      Exit(Variables[Index]);
  Result := nil;
end;

function TPattern.FindObject(const AName: string): TDraftObject;
var
  Index: integer;
begin
  for Index := 0 to FObjects.Count - 1 do
    if SameName(Objects[Index].Name, AName) then
      Exit(Objects[Index]);
  Result := nil;
end;

function TPattern.FindVariable(const AName: string): TVariable;
var
  Index: integer;
begin
  for Index := 0 to FVariables.Count - 1 do
    if SameName(Variables[Index].Name, AName) then
      Exit(Variables[Index]);
  Result := nil;
end;

function TPattern.ObjectNameTaken(const AName: string): boolean;
var
  Existing: TDraftObject;
begin
  Existing := FindObject(AName);
  Result := (Existing <> nil) and (Existing <> FNameExclude);
end;

function TPattern.CheckObjectName(const AName: string; Exclude: TDraftObject;
  out ErrorMessage: string): boolean;
var
  Existing: TDraftObject;
begin
  if not CheckName(AName, ErrorMessage) then
    Exit(False);
  Existing := FindObject(AName);
  if (Existing <> nil) and (Existing <> Exclude) then
  begin
    ErrorMessage := Format(rsNameTaken, [AName]);
    Exit(False);
  end;
  Result := True;
end;

function TPattern.CheckVariableName(const AName: string; Exclude: TVariable;
  out ErrorMessage: string): boolean;
var
  Existing: TVariable;
begin
  if not CheckName(AName, ErrorMessage) then
    Exit(False);
  Existing := FindVariable(AName);
  if (Existing <> nil) and (Existing <> Exclude) then
  begin
    ErrorMessage := Format(rsNameTaken, [AName]);
    Exit(False);
  end;
  Result := True;
end;

function TPattern.ResolverFor(Node: TEvalNode): TNameResolver;
begin
  if Node is TVariable then
    Result := FVariableResolver
  else
    Result := FResolver;
end;

// Parses Texts into the node's fields of the same Names
function TPattern.ParseFields(Node: TEvalNode; const Names, Texts: array of string): boolean;
var
  Index: integer;
  FieldFormula: TFormula;
begin
  for Index := 0 to High(Names) do
  begin
    FieldFormula := Node.Field(Names[Index]);
    if not FieldFormula.Parse(Texts[Index], ResolverFor(Node)) then
      Exit(SetError(FieldFormula.ErrorMessage, Names[Index], FieldFormula.ErrorPos));
  end;
  Result := True;
end;

function TPattern.CheckPoint(const Id: string): boolean;
var
  Node: TEvalNode;
begin
  Node := FindNode(Id);
  if Node = nil then
    Exit(SetError(Format(rsPatternUnknownObject, [Id])));
  if not (Node is TPointObject) then
    Exit(SetError(Format(rsDraftNotAPoint, [Node.DisplayName])));
  Result := True;
end;

function TPattern.CheckEdgeTarget(const Id: string): boolean;
var
  Node: TEvalNode;
begin
  Node := FindNode(Id);
  if Node = nil then
    Exit(SetError(Format(rsPatternUnknownObject, [Id])));
  if not (Node is TEdgeObject) then
    Exit(SetError(Format(rsDraftNotAnEdge, [Node.DisplayName])));
  Result := True;
end;

function TPattern.AddVariable(const AName, FormulaText: string;
  const Description: string): TVariable;
var
  Msg: string;
begin
  Result := nil;
  if not CheckVariableName(AName, nil, Msg) then
  begin
    SetError(Msg);
    Exit;
  end;
  Result := TVariable.Create('v' + IntToStr(FNextVariable));
  if not ParseFields(Result, ['formula'], [FormulaText]) then
  begin
    FreeAndNil(Result);
    Exit;
  end;
  // A new node cannot close a cycle: nothing refers to it yet
  Inc(FNextVariable);
  Result.Name := AName;
  Result.Description := Description;
  FVariables.Add(Result);
end;

function TPattern.AddPointObject(APoint: TPointObject; const AName: string;
  const Names, Texts: array of string): boolean;
var
  Msg, PointName: string;
begin
  PointName := AName;
  if PointName = '' then
  begin
    FNameExclude := nil;
    PointName := NextAutoName(@ObjectNameTaken);
  end
  else if not CheckObjectName(PointName, nil, Msg) then
  begin
    APoint.Free;
    Exit(SetError(Msg));
  end;
  if not ParseFields(APoint, Names, Texts) then
  begin
    APoint.Free;
    Exit(False);
  end;
  Inc(FNextPoint);
  APoint.Name := PointName;
  FObjects.Add(APoint);
  Result := True;
end;

function TPattern.AddFreePoint(const AName, XText, YText: string): TFreePoint;
begin
  Result := TFreePoint.Create('p' + IntToStr(FNextPoint));
  if not AddPointObject(Result, AName, ['x', 'y'], [XText, YText]) then
    Result := nil;
end;

function TPattern.AddOffsetPoint(const AName, BaseId: string; Mode: TOffsetMode;
  const LengthOrDx, AngleOrDy: string): TOffsetPoint;
begin
  Result := nil;
  if not CheckPoint(BaseId) then
    Exit;
  Result := TOffsetPoint.Create('p' + IntToStr(FNextPoint), BaseId, Mode);
  if Mode = omPolar then
  begin
    if not AddPointObject(Result, AName, ['length', 'angle'], [LengthOrDx, AngleOrDy]) then
      Result := nil;
  end
  else if not AddPointObject(Result, AName, ['dx', 'dy'], [LengthOrDx, AngleOrDy]) then
    Result := nil;
end;

function TPattern.AddAlongEdgePoint(const AName, EdgeId: string; FromEnd: boolean;
  Mode: TAlongMode; const Value: string): TAlongEdgePoint;
begin
  Result := nil;
  if not CheckEdgeTarget(EdgeId) then
    Exit;
  Result := TAlongEdgePoint.Create('p' + IntToStr(FNextPoint), EdgeId, FromEnd, Mode);
  if not AddPointObject(Result, AName, ['value'], [Value]) then
    Result := nil;
end;

function TPattern.AddIntersectPoint(const AName, EdgeAId, EdgeBId: string;
  ExtendA, ExtendB: boolean; Pick: integer): TIntersectPoint;
begin
  Result := nil;
  if not CheckEdgeTarget(EdgeAId) or not CheckEdgeTarget(EdgeBId) then
    Exit;
  if EdgeAId = EdgeBId then
  begin
    SetError(rsPatternSameEdge);
    Exit;
  end;
  if Pick < 1 then
  begin
    SetError(rsPatternBadPick);
    Exit;
  end;
  Result := TIntersectPoint.Create('p' + IntToStr(FNextPoint), EdgeAId, EdgeBId,
    ExtendA, ExtendB, Pick);
  if not AddPointObject(Result, AName, [], []) then
    Result := nil;
end;

function TPattern.AddCircleEdgePoint(const AName, CentreId, Radius, EdgeId: string;
  Extend: boolean; Pick: integer): TCircleEdgePoint;
begin
  Result := nil;
  if not CheckPoint(CentreId) or not CheckEdgeTarget(EdgeId) then
    Exit;
  if Pick < 1 then
  begin
    SetError(rsPatternBadPick);
    Exit;
  end;
  Result := TCircleEdgePoint.Create('p' + IntToStr(FNextPoint), CentreId, EdgeId, Extend, Pick);
  if not AddPointObject(Result, AName, ['radius'], [Radius]) then
    Result := nil;
end;

function TPattern.AddProjectPoint(const AName, SourceId, EdgeId: string;
  Direction: TProjectDirection; const Angle: string; Extend: boolean): TProjectPoint;
begin
  Result := nil;
  if not CheckPoint(SourceId) or not CheckEdgeTarget(EdgeId) then
    Exit;
  Result := TProjectPoint.Create('p' + IntToStr(FNextPoint), SourceId, EdgeId, Direction, Extend);
  if Direction = pdAngle then
  begin
    if not AddPointObject(Result, AName, ['angle'], [Angle]) then
      Result := nil;
  end
  else if not AddPointObject(Result, AName, [], []) then
    Result := nil;
end;

function TPattern.DerivedEdgeName(AEdge: TEdgeObject): string;
var
  StartNode, EndNode: TEvalNode;
begin
  StartNode := FindNode(AEdge.StartKey);
  EndNode := FindNode(AEdge.EndKey);
  FNameExclude := AEdge;
  Result := NextFreeName(AEdge.NamePrefix + '_' + StartNode.DisplayName + '_' + EndNode.DisplayName, @ObjectNameTaken);
  FNameExclude := nil;
end;

function TPattern.AddEdgeObject(AEdge: TEdgeObject; const AName: string; ARole: TEdgeRole;
  const Names, Texts: array of string): boolean;
var
  Msg: string;
begin
  if not CheckPoint(AEdge.StartKey) or not CheckPoint(AEdge.EndKey) then
  begin
    AEdge.Free;
    Exit(False);
  end;
  if AName <> '' then
  begin
    if not CheckObjectName(AName, nil, Msg) then
    begin
      AEdge.Free;
      Exit(SetError(Msg));
    end;
    AEdge.Name := AName;
    AEdge.NameIsDerived := False;
  end
  else
    AEdge.Name := DerivedEdgeName(AEdge);
  if not ParseFields(AEdge, Names, Texts) then
  begin
    AEdge.Free;
    Exit(False);
  end;
  AEdge.Role := ARole;
  FObjects.Add(AEdge);
  Result := True;
end;

function TPattern.AddLine(const StartId, EndId: string; Role: TEdgeRole;
  const AName: string): TLineObject;
begin
  Result := TLineObject.Create('l' + IntToStr(FNextLine), StartId, EndId);
  if AddEdgeObject(Result, AName, Role, [], []) then
    Inc(FNextLine)
  else
    Result := nil;
end;

function TPattern.AddCurve(const StartId, EndId, Angle1, Length1, Angle2, Length2: string;
  Role: TEdgeRole; const AName: string): TCurveObject;
begin
  Result := TCurveObject.Create('c' + IntToStr(FNextCurve), StartId, EndId);
  if AddEdgeObject(Result, AName, Role, ['angle1', 'length1', 'angle2', 'length2'],
    [Angle1, Length1, Angle2, Length2]) then
    Inc(FNextCurve)
  else
    Result := nil;
end;

function TPattern.AddCurvePath(const NodeIds, Angles, LengthsIn, LengthsOut: array of string;
  Role: TEdgeRole; const AName: string): TCurvePathObject;
var
  Index, Count: integer;
  Names, Texts: array of string;
  NodeName: string;

  procedure AddText(const FieldName, Text: string);
  begin
    SetLength(Names, Length(Names) + 1);
    Names[High(Names)] := FieldName;
    SetLength(Texts, Length(Texts) + 1);
    Texts[High(Texts)] := Text;
  end;

begin
  Result := nil;
  Count := Length(NodeIds);
  if Count < 2 then
  begin
    SetError(rsPatternPathTooShort);
    Exit;
  end;
  if (Length(Angles) <> Count) or (Length(LengthsIn) <> Count) or (Length(LengthsOut) <> Count) then
  begin
    SetError(rsPatternPathArrays);
    Exit;
  end;
  for Index := 0 to Count - 1 do
  begin
    if not CheckPoint(NodeIds[Index]) then
      Exit;
    if (Index > 0) and (NodeIds[Index] = NodeIds[Index - 1]) then
    begin
      SetError(rsPatternPathRepeats);
      Exit;
    end;
  end;
  Names := nil;
  Texts := nil;
  for Index := 0 to Count - 1 do
  begin
    NodeName := 'node' + IntToStr(Index + 1);
    if Index > 0 then
      AddText(NodeName + '.lengthIn', LengthsIn[Index]);
    AddText(NodeName + '.angle', Angles[Index]);
    if Index < Count - 1 then
      AddText(NodeName + '.lengthOut', LengthsOut[Index]);
  end;
  Result := TCurvePathObject.Create('c' + IntToStr(FNextCurve), NodeIds);
  if AddEdgeObject(Result, AName, Role, Names, Texts) then
    Inc(FNextCurve)
  else
    Result := nil;
end;

function TPattern.SplitEdge(const EdgeId, PointId: string; out First, Second: TSplitPart): boolean;
var
  Source: TEdgeObject;
  Straight: boolean;
  Prefix: string;

  function NewPart(APart: integer): TSplitPart;
  var
    Key: string;
  begin
    if Straight then
    begin
      Key := 'l' + IntToStr(FNextLine);
      Inc(FNextLine);
    end
    else
    begin
      Key := 'c' + IntToStr(FNextCurve);
      Inc(FNextCurve);
    end;
    Result := TSplitPart.Create(Key, EdgeId, PointId, APart, Source.StartKey, Source.EndKey, Straight, Prefix);
    // Each part is its own edge: it gets a derived name and joins the pattern
    Result.Name := DerivedEdgeName(Result);
    Result.Role := Source.Role;
    FObjects.Add(Result);
  end;

begin
  First := nil;
  Second := nil;
  if not CheckEdgeTarget(EdgeId) or not CheckPoint(PointId) then
    Exit(False);
  Source := TEdgeObject(FindNode(EdgeId));
  Straight := (Source is TLineObject) or ((Source is TSplitPart) and TSplitPart(Source).Straight);
  Prefix := Source.NamePrefix;
  First := NewPart(1);
  Second := NewPart(2);
  Result := True;
end;

function TPattern.SetFormula(Node: TEvalNode; const AField, Text: string): boolean;
var
  NewFormula: TFormula;
  Ref: TFormulaReference;
  Dep: TEvalNode;
begin
  if Node.Field(AField) = nil then
    Exit(SetError(Format(rsPatternNoField, [Node.DisplayName, AField]), AField));
  NewFormula := TFormula.Create;
  try
    if not NewFormula.Parse(Text, ResolverFor(Node)) then
      Exit(SetError(NewFormula.ErrorMessage, AField, NewFormula.ErrorPos));
    // Refuse anything that would make Node read itself
    for Ref in NewFormula.References do
    begin
      Dep := FindNode(ReferenceKey(Ref));
      if Dep = Node then
        Exit(SetError(Format(rsPatternUsesItself, [Node.DisplayName]), AField));
      if (Dep <> nil) and TEvaluator.Reaches(Dep, Node, FContext) then
        Exit(SetError(Format(rsPatternCycle, [Node.DisplayName, Dep.DisplayName,
          Dep.DisplayName, Node.DisplayName]), AField));
    end;
    Node.ReplaceField(AField, NewFormula);
    NewFormula := nil;
    Result := True;
  finally
    NewFormula.Free;
  end;
end;

procedure TPattern.UpdateDerivedNames;
var
  Index: integer;
begin
  for Index := 0 to FObjects.Count - 1 do
    if (Objects[Index] is TEdgeObject) and TEdgeObject(Objects[Index]).NameIsDerived then
      Objects[Index].Name := DerivedEdgeName(TEdgeObject(Objects[Index]));
end;

function TPattern.Rename(Node: TEvalNode; const NewName: string): boolean;
var
  Msg: string;
begin
  if Node is TVariable then
  begin
    if not CheckVariableName(NewName, TVariable(Node), Msg) then
      Exit(SetError(Msg));
    TVariable(Node).Name := NewName;
  end
  else if Node is TDraftObject then
  begin
    if not CheckObjectName(NewName, TDraftObject(Node), Msg) then
      Exit(SetError(Msg));
    TDraftObject(Node).Name := NewName;
    if Node is TEdgeObject then
      TEdgeObject(Node).NameIsDerived := False;
    UpdateDerivedNames;
  end
  else
    Exit(SetError(Format(rsPatternCannotRename, [Node.DisplayName])));
  Result := True;
end;

function TPattern.UsersOf(Node: TEvalNode): TEvalNodeArray;
var
  Nodes: TEvalNodeArray;
  Candidate: TEvalNode;
  DepKey: string;
begin
  Result := nil;
  Nodes := AllNodes;
  for Candidate in Nodes do
    for DepKey in Candidate.DependencyKeys do
      if DepKey = Node.Key then
      begin
        SetLength(Result, Length(Result) + 1);
        Result[High(Result)] := Candidate;
        Break;
      end;
end;

function TPattern.Delete(Node: TEvalNode): boolean;
var
  Users: TEvalNodeArray;
  Names: string;
  User: TEvalNode;
begin
  if not ((Node is TVariable) or (Node is TDraftObject)) then
    Exit(SetError(Format(rsPatternCannotDelete, [Node.DisplayName])));
  Users := UsersOf(Node);
  if Length(Users) > 0 then
  begin
    Names := '';
    for User in Users do
    begin
      if Names <> '' then
        Names := Names + ', ';
      Names := Names + User.DisplayName;
    end;
    Exit(SetError(Format(rsPatternInUse, [Node.DisplayName, Names])));
  end;
  // The evaluator may hold the node; forget the old graph
  FEvaluator.Rebuild(nil, FContext);
  if Node is TVariable then
    FVariables.Remove(Node)
  else
    FObjects.Remove(Node);
  Node.Free;
  Result := True;
end;

function TPattern.FormulaText(Node: TEvalNode; const AField: string): string;
begin
  Result := Node.Field(AField).DisplayText(ResolverFor(Node));
end;

procedure TPattern.RebuildMeasurementNodes;
var
  Keys: TStringList;
  Node: TEvalNode;
  Ref: TFormulaReference;
  FieldIndex, KeyIndex: integer;
begin
  Keys := TStringList.Create;
  try
    Keys.CaseSensitive := False;
    Keys.Duplicates := dupIgnore;
    Keys.Sorted := True;
    for Node in AllNodes do
      for FieldIndex := 0 to Node.FieldCount - 1 do
        for Ref in Node.Fields[FieldIndex].Formula.References do
          if Ref.Kind = rkMeasurement then
            Keys.Add('@' + Ref.Id);
    FreeItems(FMeasurementNodes);
    for KeyIndex := 0 to Keys.Count - 1 do
      FMeasurementNodes.Add(TMeasurementNode.Create(Keys[KeyIndex]));
  finally
    Keys.Free;
  end;
end;

// Measurement nodes, then variables, then objects
function TPattern.AllNodes: TEvalNodeArray;
var
  Index, Count: integer;
begin
  Result := nil;
  SetLength(Result, FMeasurementNodes.Count + FVariables.Count + FObjects.Count);
  Count := 0;
  for Index := 0 to FMeasurementNodes.Count - 1 do
  begin
    Result[Count] := TEvalNode(FMeasurementNodes[Index]);
    Inc(Count);
  end;
  for Index := 0 to FVariables.Count - 1 do
  begin
    Result[Count] := Variables[Index];
    Inc(Count);
  end;
  for Index := 0 to FObjects.Count - 1 do
  begin
    Result[Count] := Objects[Index];
    Inc(Count);
  end;
end;

procedure TPattern.Evaluate;
begin
  // Measurement nodes are recreated, so drop the old graph first
  FEvaluator.Rebuild(nil, FContext);
  RebuildMeasurementNodes;
  FEvaluator.Rebuild(AllNodes, FContext);
  FEvaluator.Run(FContext);
end;

function TPattern.SaveVariables: TJSONArray;
var
  Index: integer;
  Item: TJSONObject;
begin
  Result := TJSONArray.Create;
  for Index := 0 to VariableCount - 1 do
  begin
    Item := TJSONObject.Create;
    Item.Add('id', Variables[Index].Key);
    Item.Add('name', Variables[Index].Name);
    Item.Add('formula', Variables[Index].Formula.StoredText);
    Item.Add('description', Variables[Index].Description);
    Result.Add(Item);
  end;
end;

function TPattern.LoadVariables(Data: TJSONData; out ErrorMessage: string): boolean;
var
  Index, IdNumber, Code: integer;
  Item: TJSONObject;
  Id, VName, Text, Desc, Msg: string;
  Variable: TVariable;

  function Fail(const AMsg: string): boolean;
  begin
    ErrorMessage := AMsg;
    FEvaluator.Rebuild(nil, FContext);
    FreeItems(FVariables);
    FNextVariable := 1;
    Result := False;
  end;

begin
  ErrorMessage := '';
  FEvaluator.Rebuild(nil, FContext);
  FreeItems(FVariables);
  FNextVariable := 1;
  if (Data = nil) or (Data.JSONType <> jtArray) then
    Exit(Fail(rsPatternVariableList));
  for Index := 0 to Data.Count - 1 do
  begin
    if Data.Items[Index].JSONType <> jtObject then
      Exit(Fail(rsPatternVariableList));
    Item := TJSONObject(Data.Items[Index]);
    if not GetJSONString(Item, 'id', Id) or (Id = '') or (FindNode(Id) <> nil) then
      Exit(Fail(rsPatternVariableBadId));
    if not GetJSONString(Item, 'name', VName) then
      VName := '';
    if not CheckVariableName(VName, nil, Msg) then
      Exit(Fail(Format(rsPatternVariableBadName, [Msg])));
    if not GetJSONString(Item, 'formula', Text) then
      Exit(Fail(Format(rsPatternVariableNoFormula, [VName])));
    GetJSONString(Item, 'description', Desc);
    Variable := TVariable.Create(Id);
    Variable.Name := VName;
    Variable.Description := Desc;
    Variable.Formula.ParseStored(Text);
    FVariables.Add(Variable);
    // Keep new IDs above every loaded one
    if (Length(Id) > 1) and (Id[1] = 'v') then
    begin
      Val(Copy(Id, 2, MaxInt), IdNumber, Code);
      if (Code = 0) and (IdNumber >= FNextVariable) then
        FNextVariable := IdNumber + 1;
    end;
  end;
  Result := True;
end;

end.
