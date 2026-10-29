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
unit Sloper.Core.Pattern;

{$mode ObjFPC}{$H+}

interface

uses
  Classes, SysUtils, Generics.Collections, Sloper.Core.EvalTypes, Sloper.Core.Evaluator, Sloper.Core.Formula,
  Sloper.Core.Measurements, Sloper.Core.Variables, Sloper.Core.Draft;

type
  TMeasurementNodeList = specialize TObjectList<TMeasurementNode>;
  TVariableList = specialize TObjectList<TVariable>;
  TDraftObjectList = specialize TObjectList<TDraftObject>;
  TEvalNodeMap = specialize TDictionary<string, TEvalNode>;

  TPattern = class
  private
    FMeasurements: TMeasurementSet;
    FMeasurementNodes: TMeasurementNodeList;
    FVariables: TVariableList;
    FObjects: TDraftObjectList;
    // Every node by key, for FindNode; measurement keys in lower case
    FNodes: TEvalNodeMap;
    FNextPoint, FNextLine, FNextCurve, FNextVariable: integer;
    FEvaluator: TEvaluator;
    FResolver: TNameResolver;          // objects, variables, measurements
    FVariableResolver: TNameResolver;  // variables and measurements only
    FContext: TEvalContext;
    FLastError: string;
    FLastErrorField: string;
    FLastErrorPos: integer;
    FNameExclude: TDraftObject;
    procedure KeepIdsAbove(const Key: string);
    procedure AddVariableNode(Variable: TVariable);
    procedure AddObjectNode(DraftObject: TDraftObject);
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
    procedure RebuildMeasurementNodes;
  public
    Notes: string;
    // The measurement file last used with the pattern, as the user chose it;
    // the document resolves it. Not loaded here.
    MeasurementFile: string;
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
    // Measurements the pattern uses (after Evaluate), then variables, then objects
    function AllNodes: TEvalNodeArray;

    // For loaders: add a variable or object that already has its stored ID
    // and formulas, taking ownership. Nothing is checked; the loader checks
    // IDs, names and inputs. New IDs are kept above the inserted ones.
    procedure InsertVariable(Variable: TVariable);
    procedure InsertObject(DraftObject: TDraftObject);
    // Recomputes the names of edges named after their ends; called after
    // loading, since a loaded edge's ends come first
    procedure UpdateDerivedNames;

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

implementation

uses
  Sloper.Core.Names;

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
  FMeasurementNodes := TMeasurementNodeList.Create;
  FVariables := TVariableList.Create;
  FObjects := TDraftObjectList.Create;
  FNodes := TEvalNodeMap.Create;
  FEvaluator := TEvaluator.Create;
  FResolver := TPatternResolver.Create(Self, True);
  FVariableResolver := TPatternResolver.Create(Self, False);
  FContext := TPatternContext.Create(Self);
  Clear;
end;

destructor TPattern.Destroy;
begin
  Clear;
  FreeAndNil(FMeasurementNodes);
  FreeAndNil(FVariables);
  FreeAndNil(FObjects);
  FreeAndNil(FNodes);
  FreeAndNil(FEvaluator);
  FreeAndNil(FResolver);
  FreeAndNil(FVariableResolver);
  FreeAndNil(FContext);
  inherited Destroy;
end;

procedure TPattern.Clear;
begin
  // The evaluator holds node references; drop them first
  FEvaluator.Rebuild(nil, FContext);
  FNodes.Clear;
  FMeasurementNodes.Clear;
  FVariables.Clear;
  FObjects.Clear;
  FNextPoint := 1;
  FNextLine := 1;
  FNextCurve := 1;
  FNextVariable := 1;
  Notes := '';
  MeasurementFile := '';
end;

function TPattern.GetVariableCount: integer;
begin
  Result := FVariables.Count;
end;

function TPattern.GetVariable(Index: integer): TVariable;
begin
  Result := FVariables[Index];
end;

function TPattern.GetObjectCount: integer;
begin
  Result := FObjects.Count;
end;

function TPattern.GetObject(Index: integer): TDraftObject;
begin
  Result := FObjects[Index];
end;

function TPattern.SetError(const Msg: string; const AField: string; Pos: integer): boolean;
begin
  FLastError := Msg;
  FLastErrorField := AField;
  FLastErrorPos := Pos;
  Result := False;
end;

// IDs are compared exactly; measurement keys (@waist) without regard to case
function TPattern.FindNode(const Key: string): TEvalNode;
var
  MapKey: string;
begin
  MapKey := Key;
  if (Key <> '') and (Key[1] = '@') then
    MapKey := LowerCase(Key);
  if not FNodes.TryGetValue(MapKey, Result) then
    Result := nil;
end;

procedure TPattern.AddVariableNode(Variable: TVariable);
begin
  FVariables.Add(Variable);
  FNodes.Add(Variable.Key, Variable);
end;

procedure TPattern.AddObjectNode(DraftObject: TDraftObject);
begin
  FObjects.Add(DraftObject);
  FNodes.Add(DraftObject.Key, DraftObject);
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
  AddVariableNode(Result);
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
    FreeAndNil(APoint);
    Exit(SetError(Msg));
  end;
  if not ParseFields(APoint, Names, Texts) then
  begin
    FreeAndNil(APoint);
    Exit(False);
  end;
  Inc(FNextPoint);
  APoint.Name := PointName;
  AddObjectNode(APoint);
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
    FreeAndNil(AEdge);
    Exit(False);
  end;
  if AName <> '' then
  begin
    if not CheckObjectName(AName, nil, Msg) then
    begin
      FreeAndNil(AEdge);
      Exit(SetError(Msg));
    end;
    AEdge.Name := AName;
    AEdge.NameIsDerived := False;
  end
  else
    AEdge.Name := DerivedEdgeName(AEdge);
  if not ParseFields(AEdge, Names, Texts) then
  begin
    FreeAndNil(AEdge);
    Exit(False);
  end;
  AEdge.Role := ARole;
  AddObjectNode(AEdge);
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
    Result := NewSplitPart(Key, Source, PointId, APart);
    // Each part is its own edge: it gets a derived name and joins the pattern
    Result.Name := DerivedEdgeName(Result);
    Result.Role := Source.Role;
    AddObjectNode(Result);
  end;

begin
  First := nil;
  Second := nil;
  if not CheckEdgeTarget(EdgeId) or not CheckPoint(PointId) then
    Exit(False);
  Source := TEdgeObject(FindNode(EdgeId));
  Straight := IsStraightEdge(Source);
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
    FreeAndNil(NewFormula);
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
  FNodes.Remove(Node.Key);
  // The lists own their nodes, so removing frees it
  if Node is TVariable then
    FVariables.Remove(TVariable(Node))
  else
    FObjects.Remove(TDraftObject(Node));
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
  MeasurementNode: TMeasurementNode;
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
    for MeasurementNode in FMeasurementNodes do
      FNodes.Remove(LowerCase(MeasurementNode.Key));
    FMeasurementNodes.Clear;
    for KeyIndex := 0 to Keys.Count - 1 do
    begin
      MeasurementNode := TMeasurementNode.Create(Keys[KeyIndex]);
      FMeasurementNodes.Add(MeasurementNode);
      FNodes.Add(LowerCase(MeasurementNode.Key), MeasurementNode);
    end;
  finally
    FreeAndNil(Keys);
  end;
end;

function TPattern.AllNodes: TEvalNodeArray;
var
  Count: integer;
  MeasurementNode: TMeasurementNode;
  Variable: TVariable;
  DraftObject: TDraftObject;
begin
  Result := nil;
  SetLength(Result, FMeasurementNodes.Count + FVariables.Count + FObjects.Count);
  Count := 0;
  for MeasurementNode in FMeasurementNodes do
  begin
    Result[Count] := MeasurementNode;
    Inc(Count);
  end;
  for Variable in FVariables do
  begin
    Result[Count] := Variable;
    Inc(Count);
  end;
  for DraftObject in FObjects do
  begin
    Result[Count] := DraftObject;
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

// Moves the counter for Key's letter past Key's number (p7 -> next point p8)
procedure TPattern.KeepIdsAbove(const Key: string);
var
  IdNumber, Code: integer;
begin
  if Length(Key) < 2 then
    Exit;
  Val(Copy(Key, 2, MaxInt), IdNumber, Code);
  if (Code <> 0) or (IdNumber < 1) then
    Exit;
  case Key[1] of
    'p':
      if IdNumber >= FNextPoint then
        FNextPoint := IdNumber + 1;
    'l':
      if IdNumber >= FNextLine then
        FNextLine := IdNumber + 1;
    'c':
      if IdNumber >= FNextCurve then
        FNextCurve := IdNumber + 1;
    'v':
      if IdNumber >= FNextVariable then
        FNextVariable := IdNumber + 1;
  end;
end;

procedure TPattern.InsertVariable(Variable: TVariable);
begin
  AddVariableNode(Variable);
  KeepIdsAbove(Variable.Key);
end;

procedure TPattern.InsertObject(DraftObject: TDraftObject);
begin
  AddObjectNode(DraftObject);
  KeepIdsAbove(DraftObject.Key);
end;

end.
