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
  Sloper.Core.Measurements, Sloper.Core.Variables, Sloper.Core.Draft, Sloper.Core.Piece, Sloper.Core.Seam;

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
    // The next ID to hand out, shared by variables and objects; only ever goes up
    FNextId: integer;
    FEvaluator: TEvaluator;
    FResolver: TNameResolver;          // objects, variables, measurements
    FVariableResolver: TNameResolver;  // variables and measurements only
    FContext: TEvalContext;
    FLastError: string;
    FParsingNewObject: boolean;
    FLastErrorField: string;
    FLastErrorPos: integer;
    FNameExclude: TDraftObject;
    procedure KeepIdsAbove(const Key: string);
    procedure AddVariableNode(Variable: TVariable);
    procedure AddObjectNode(DraftObject: TDraftObject);
    procedure KeepInputsBefore(Piece: TPieceObject);
    function CheckSeamEntry(const Entry: TSeamEntry): boolean;
    // Files list each object after its inputs. A changed point may now read
    // objects further down, so they move up; the rest stay in their order.
    procedure OrderObjectsByInputs;
    function GetVariableCount: integer;
    function GetVariable(Index: integer): TVariable;
    function GetObjectCount: integer;
    function GetObject(Index: integer): TDraftObject;
    function SetError(const Msg: string; const AField: string = ''; Pos: integer = 0): boolean;
    function FindRepeatItem(const Key: string): TEvalNode;
    function ObjectNameTaken(const AName: string): boolean;
    function VariableNameTaken(const AName: string): boolean;
    function ResolverFor(Node: TEvalNode): TNameResolver;
    function ParseFields(Node: TEvalNode; const Names, Texts: array of string): boolean;
    function CheckPoint(const Id: string): boolean;
    function CheckEdgeTarget(const Id: string): boolean;
    function AddPointObject(APoint: TDraftObject; const AName: string;
      const Names, Texts: array of string): boolean;
    function CheckNotInCircle(Target: TEvalNode; const Key: string): boolean;
    // Takes NewFormula once it is parsed, refusing anything that would make
    // Node read itself; frees it either way
    function InstallFormula(Node: TEvalNode; const AField: string; NewFormula: TFormula): boolean;
    function ReplacePoint(Point, NewPoint: TPointObject; const Names, Texts: array of string): boolean;
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
    // A free name for a new variable: variable, variable2 and so on
    function NewVariableName: string;
    function AddFreePoint(const AName, XText, YText: string): TFreePoint;
    // LengthOrDx and AngleOrDy are length and angle (omPolar) or dx and dy (omCartesian)
    function AddOffsetPoint(const AName, BaseId: string; Mode: TOffsetMode; const LengthOrDx, AngleOrDy: string): TOffsetPoint;
    function AddAlongEdgePoint(const AName, EdgeId: string; FromEnd: boolean;
      Mode: TAlongMode; const Value: string): TAlongEdgePoint;
    // Where two edges cross; Pick numbers the crossings from 1 along EdgeA
    function AddBetweenPoint(const AName, FirstId, LastId: string; Mode: TAlongMode; const Value: string): TBetweenPoint;
    // Count points between two points, or along an edge by arc length
    function AddRepeatBetween(const AName, FirstId, LastId, CountText: string; IncludeEnds: boolean): TRepeatObject;
    function AddRepeatOnEdge(const AName, EdgeId, CountText: string; IncludeEnds: boolean): TRepeatObject;
    // A key an operation can store: a virtual repeat point takes an ID now,
    // which is what first use means. Call it inside a change.
    function UsePoint(const Key: string): string;
    // Every point there is, a repeat's included, in order
    function AllPoints: TPointObjectArray;
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
    // A piece around the closed Path, with Allowance as the seam allowance of
    // every edge. An empty name takes the next free one: Piece, Piece2 and so on.
    function AddPiece(const AName: string; const Path: TPiecePath; const Allowance: string): TPieceObject;
    // Gives one edge of the path its own allowance; empty text goes back to
    // the piece's own
    function SetEdgeAllowance(Piece: TPieceObject; PathIndex: integer; const Text: string): boolean;

    // A grainline at an angle formula, through the piece's middle
    function SetGrainAngle(Piece: TPieceObject; const Text: string): boolean;
    function SetGrainPoints(Piece: TPieceObject; const StartId, EndId: string): boolean;
    procedure ClearGrain(Piece: TPieceObject);
    // A notch where the piece passes a point
    function AddPointNotch(Piece: TPieceObject; const PointId: string): boolean;
    // A notch Position mm along an edge of the piece, from the edge's start
    function AddEdgeNotch(Piece: TPieceObject; const EdgeId, Position: string): boolean;
    function RemoveNotch(Piece: TPieceObject; Index: integer): boolean;
    function SetCut(Piece: TPieceObject; Count: integer; Mirrored: boolean): boolean;
    // Cuts the piece on the fold along a straight edge of it; an empty EdgeId
    // clears the fold
    function SetFoldEdge(Piece: TPieceObject; const EdgeId: string): boolean;
    // A seam between two sides. An empty name takes the next free one: Seam,
    // Seam2 and so on. Nil with LastError set when refused.
    function AddSeam(const AName: string; const SideA, SideB: TSeamSide; const Ease: string = DefaultSeamEase;
      const Tolerance: string = DefaultSeamTolerance): TSeamObject;
    // Whether Side has edges, each once and each on the piece beside it. For
    // loaders too: a fold set after the seam is made only makes it invalid.
    function CheckSeamSide(const Side: TSeamSide): boolean;

    // Editing returns False when refused, with the reason in LastError
    function SetFormula(Node: TEvalNode; const AField, Text: string): boolean;
    // The same, for text in stored form ({12}.x), which does not go by names
    function SetStoredFormula(Node: TEvalNode; const AField, Text: string): boolean;
    // Change a point's operation. It keeps its ID, name and users, so what
    // reads it carries on; Point is freed. Formulas are in stored form. Nil
    // with LastError set on failure, when Point is left as it was.
    function ConvertToFree(Point: TPointObject; const XText, YText: string): TFreePoint;
    function ConvertToBetween(Point: TPointObject; const FirstId, LastId: string; Mode: TAlongMode; const Value: string): TBetweenPoint;
    function ConvertToAlongEdge(Point: TPointObject; const EdgeId: string; FromEnd: boolean; Mode: TAlongMode; const Value: string): TAlongEdgePoint;
    // Whether From reads Target, directly or through others
    function Reaches(From, Target: TEvalNode): boolean;
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
    // IDs, names and inputs. NextId is kept above the inserted IDs.
    procedure InsertVariable(Variable: TVariable);
    procedure InsertObject(DraftObject: TDraftObject);
    procedure InsertRepeatPoint(ARepeat: TRepeatObject; Index: integer; const Id: string);
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
    // The next ID to hand out. Loaders and undo may raise it; IDs are never reused.
    property NextId: integer read FNextId write FNextId;
    property LastError: string read FLastError;
    property LastErrorField: string read FLastErrorField;
    property LastErrorPos: integer read FLastErrorPos;
  end;

resourcestring
  rsPatternUnknownObject = 'There is no object %s';
  rsPatternUsesItself = '%s cannot use itself';
  rsPatternRepeatSamePoint = 'A repeat needs two different points';
  rsPatternRepeatItem = '%s is part of a repeat, so it cannot be changed on its own';
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
  rsPatternPieceTooShort = 'A piece needs at least two edges';
  rsPatternPieceRepeats = 'A piece cannot use %s twice';
  rsPatternNotInPiece = '%s is not part of %s';
  rsPatternSeamEmptySide = 'Each side of a seam needs at least one edge';
  rsPatternSeamRepeats = 'A side of a seam cannot use %s of %s twice';
  rsPatternGrainSamePoint = 'The grainline needs two different points';
  rsPatternNoNotch = 'There is no notch %d';
  rsPatternBadCutCount = 'A piece must be cut at least once';
  rsPatternFoldNotStraight = 'A fold has to be straight, and %s is not';

implementation

uses
  Sloper.Core.Names;

const
  // Not translated: a name has to keep to the name rules
  NewVariableBaseName = 'variable';
  NewPieceBaseName = 'Piece';
  NewSeamBaseName = 'Seam';

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
    function MeasurementProblem(const Key: string): string; override;
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
  // Formulas are only parsed to be kept, so this is a repeat point's first use
  if Result then
    Id := FPattern.UsePoint(DraftObject.Key);
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

function TPatternContext.MeasurementProblem(const Key: string): string;
begin
  if FPattern.Measurements = nil then
    Result := ''
  else
    Result := FPattern.Measurements.ValueProblem(Key);
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
  FNextId := 1;
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
  if FNodes.TryGetValue(MapKey, Result) then
    Exit;
  Result := FindRepeatItem(Key);
end;

// A repeat point's key before it has an ID: the repeat's ID and its index, 12[3].
// It still finds the point once it has one, so a selection stays good.
function TPattern.FindRepeatItem(const Key: string): TEvalNode;
var
  Bracket: integer;
  Owner: TEvalNode;
begin
  Result := nil;
  Bracket := Pos('[', Key);
  if (Bracket < 2) or (Key[Length(Key)] <> ']') then
    Exit;
  if FNodes.TryGetValue(Copy(Key, 1, Bracket - 1), Owner) and (Owner is TRepeatObject) then
    Result := TRepeatObject(Owner).Item(StrToIntDef(Copy(Key, Bracket + 1, Length(Key) - Bracket - 1), 0));
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
  Index, Bracket: integer;
begin
  for Index := 0 to FObjects.Count - 1 do
    if SameName(Objects[Index].Name, AName) then
      Exit(Objects[Index]);
  Result := nil;
  // Btn[3]: past the current count there is no such point
  Bracket := Pos('[', AName);
  if (Bracket < 2) or (AName[Length(AName)] <> ']') then
    Exit;
  for Index := 0 to FObjects.Count - 1 do
    if (Objects[Index] is TRepeatObject) and SameName(Objects[Index].Name, Copy(AName, 1, Bracket - 1)) then
      Exit(TRepeatObject(Objects[Index]).Item(StrToIntDef(Copy(AName, Bracket + 1, Length(AName) - Bracket - 1), 0)));
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
  FParsingNewObject := True;
  try
    for Index := 0 to High(Names) do
    begin
      FieldFormula := Node.Field(Names[Index]);
      if not FieldFormula.Parse(Texts[Index], ResolverFor(Node)) then
        Exit(SetError(FieldFormula.ErrorMessage, Names[Index], FieldFormula.ErrorPos));
    end;
    Result := True;
  finally
    FParsingNewObject := False;
  end;
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
  // Its key is not an ID, so nothing may store it; UsePoint gives it one
  if (Node is TRepeatPoint) and TRepeatPoint(Node).IsVirtual then
    Exit(SetError(Format(rsPatternUnknownObject, [Id])));
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

function TPattern.VariableNameTaken(const AName: string): boolean;
begin
  Result := FindVariable(AName) <> nil;
end;

function TPattern.NewVariableName: string;
begin
  Result := NextFreeName(NewVariableBaseName, @VariableNameTaken);
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
  Result := TVariable.Create(IntToStr(FNextId));
  if not ParseFields(Result, ['formula'], [FormulaText]) then
  begin
    FreeAndNil(Result);
    Exit;
  end;
  // A new node cannot close a cycle: nothing refers to it yet
  Inc(FNextId);
  Result.Name := AName;
  Result.Description := Description;
  AddVariableNode(Result);
end;

function TPattern.AddPointObject(APoint: TDraftObject; const AName: string;
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
  Inc(FNextId);
  APoint.Name := PointName;
  AddObjectNode(APoint);
  Result := True;
end;

function TPattern.AddFreePoint(const AName, XText, YText: string): TFreePoint;
begin
  Result := TFreePoint.Create(IntToStr(FNextId));
  if not AddPointObject(Result, AName, ['x', 'y'], [XText, YText]) then
    Result := nil;
end;

function TPattern.AddOffsetPoint(const AName, BaseId: string; Mode: TOffsetMode;
  const LengthOrDx, AngleOrDy: string): TOffsetPoint;
begin
  Result := nil;
  if not CheckPoint(BaseId) then
    Exit;
  Result := TOffsetPoint.Create(IntToStr(FNextId), BaseId, Mode);
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
  Result := TAlongEdgePoint.Create(IntToStr(FNextId), EdgeId, FromEnd, Mode);
  if not AddPointObject(Result, AName, ['value'], [Value]) then
    Result := nil;
end;

function TPattern.AddBetweenPoint(const AName, FirstId, LastId: string; Mode: TAlongMode; const Value: string): TBetweenPoint;
begin
  Result := nil;
  if not CheckPoint(FirstId) or not CheckPoint(LastId) then
    Exit;
  Result := TBetweenPoint.Create(IntToStr(FNextId), FirstId, LastId, Mode);
  if not AddPointObject(Result, AName, ['value'], [Value]) then
    Result := nil;
end;

function TPattern.AddRepeatBetween(const AName, FirstId, LastId, CountText: string; IncludeEnds: boolean): TRepeatObject;
begin
  Result := nil;
  if not CheckPoint(FirstId) or not CheckPoint(LastId) then
    Exit;
  if FirstId = LastId then
  begin
    SetError(rsPatternRepeatSamePoint);
    Exit;
  end;
  Result := TRepeatObject.CreateBetween(IntToStr(FNextId), FirstId, LastId, IncludeEnds);
  if not AddPointObject(Result, AName, ['count'], [CountText]) then
    Result := nil;
end;

function TPattern.AddRepeatOnEdge(const AName, EdgeId, CountText: string; IncludeEnds: boolean): TRepeatObject;
begin
  Result := nil;
  if not CheckEdgeTarget(EdgeId) then
    Exit;
  Result := TRepeatObject.CreateOnEdge(IntToStr(FNextId), EdgeId, IncludeEnds);
  if not AddPointObject(Result, AName, ['count'], [CountText]) then
    Result := nil;
end;

function TPattern.UsePoint(const Key: string): string;
var
  Node: TEvalNode;
  Used: TRepeatPoint;
begin
  Result := Key;
  Node := FindNode(Key);
  if not (Node is TRepeatPoint) then
    Exit;
  Result := Node.Key;
  if not TRepeatPoint(Node).IsVirtual then
    Exit;
  // An object being added has its formulas parsed once it holds the next ID
  if FParsingNewObject then
    Inc(FNextId);
  Used := TRepeatPoint(Node).Source.UseItem(TRepeatPoint(Node).Index, IntToStr(FNextId));
  Inc(FNextId);
  FNodes.Add(Used.Key, Used);
  Result := Used.Key;
end;

function TPattern.AllPoints: TPointObjectArray;
var
  Index, Number: integer;
  Item: TRepeatPoint;
begin
  Result := nil;
  for Index := 0 to FObjects.Count - 1 do
    if Objects[Index] is TPointObject then
      Insert(TPointObject(Objects[Index]), Result, Length(Result))
    else if Objects[Index] is TRepeatObject then
      for Number := 1 to TRepeatObject(Objects[Index]).Count do
      begin
        Item := TRepeatObject(Objects[Index]).Item(Number);
        if Item <> nil then
          Insert(TPointObject(Item), Result, Length(Result));
      end;
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
  Result := TIntersectPoint.Create(IntToStr(FNextId), EdgeAId, EdgeBId,
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
  Result := TCircleEdgePoint.Create(IntToStr(FNextId), CentreId, EdgeId, Extend, Pick);
  if not AddPointObject(Result, AName, ['radius'], [Radius]) then
    Result := nil;
end;

function TPattern.AddProjectPoint(const AName, SourceId, EdgeId: string;
  Direction: TProjectDirection; const Angle: string; Extend: boolean): TProjectPoint;
begin
  Result := nil;
  if not CheckPoint(SourceId) or not CheckEdgeTarget(EdgeId) then
    Exit;
  Result := TProjectPoint.Create(IntToStr(FNextId), SourceId, EdgeId, Direction, Extend);
  if Direction = pdAngle then
  begin
    if not AddPointObject(Result, AName, ['angle'], [Angle]) then
      Result := nil;
  end
  else if not AddPointObject(Result, AName, [], []) then
    Result := nil;
end;

function TPattern.DerivedEdgeName(AEdge: TEdgeObject): string;

  // A repeat's point has brackets, which a name cannot: Btn[2] gives Btn_2
  function EndName(Node: TEvalNode): string;
  begin
    Result := StringReplace(StringReplace(Node.DisplayName, '[', '_', []), ']', '', []);
  end;

begin
  FNameExclude := AEdge;
  Result := NextFreeName(AEdge.NamePrefix + '_' + EndName(FindNode(AEdge.StartKey)) + '_' + EndName(FindNode(AEdge.EndKey)), @ObjectNameTaken);
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
  Inc(FNextId);
  AddObjectNode(AEdge);
  Result := True;
end;

function TPattern.AddLine(const StartId, EndId: string; Role: TEdgeRole;
  const AName: string): TLineObject;
begin
  Result := TLineObject.Create(IntToStr(FNextId), StartId, EndId);
  if not AddEdgeObject(Result, AName, Role, [], []) then
    Result := nil;
end;

function TPattern.AddCurve(const StartId, EndId, Angle1, Length1, Angle2, Length2: string;
  Role: TEdgeRole; const AName: string): TCurveObject;
begin
  Result := TCurveObject.Create(IntToStr(FNextId), StartId, EndId);
  if not AddEdgeObject(Result, AName, Role, ['angle1', 'length1', 'angle2', 'length2'],
    [Angle1, Length1, Angle2, Length2]) then
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
  Result := TCurvePathObject.Create(IntToStr(FNextId), NodeIds);
  if not AddEdgeObject(Result, AName, Role, Names, Texts) then
    Result := nil;
end;

function TPattern.SplitEdge(const EdgeId, PointId: string; out First, Second: TSplitPart): boolean;
var
  Source: TEdgeObject;

  function NewPart(APart: integer): TSplitPart;
  begin
    Result := NewSplitPart(IntToStr(FNextId), Source, PointId, APart);
    Inc(FNextId);
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
  First := NewPart(1);
  Second := NewPart(2);
  Result := True;
end;

function TPattern.AddPiece(const AName: string; const Path: TPiecePath; const Allowance: string): TPieceObject;
var
  Index, Other: integer;
  Msg, PieceName: string;
begin
  Result := nil;
  if Length(Path) < 2 then
  begin
    SetError(rsPatternPieceTooShort);
    Exit;
  end;
  for Index := 0 to High(Path) do
  begin
    if not CheckEdgeTarget(Path[Index].EdgeKey) then
      Exit;
    for Other := 0 to Index - 1 do
      if Path[Other].EdgeKey = Path[Index].EdgeKey then
      begin
        SetError(Format(rsPatternPieceRepeats, [FindNode(Path[Index].EdgeKey).DisplayName]));
        Exit;
      end;
  end;
  PieceName := AName;
  if PieceName = '' then
  begin
    FNameExclude := nil;
    PieceName := NextFreeName(NewPieceBaseName, @ObjectNameTaken);
  end
  else if not CheckObjectName(PieceName, nil, Msg) then
  begin
    SetError(Msg);
    Exit;
  end;
  Result := TPieceObject.Create(IntToStr(FNextId), Path);
  if not ParseFields(Result, [PieceAllowanceField], [Allowance]) then
  begin
    FreeAndNil(Result);
    Exit;
  end;
  Inc(FNextId);
  Result.Name := PieceName;
  AddObjectNode(Result);
  SetGrainAngle(Result, DefaultGrainAngle);
end;

procedure TPattern.OrderObjectsByInputs;
var
  Ordered: array of TDraftObject;
  Seen: TEvalNodeMap;
  Index: integer;

  procedure Visit(DraftObject: TDraftObject);
  var
    Key: string;
    Input: TEvalNode;
  begin
    if Seen.ContainsKey(DraftObject.Key) then
      Exit;
    Seen.Add(DraftObject.Key, DraftObject);
    for Key in DraftObject.InputKeys do
    begin
      Input := FindNode(Key);
      // A repeat's points are saved with it
      if Input is TRepeatPoint then
        Visit(TRepeatPoint(Input).Source)
      else if Input is TDraftObject then
        Visit(TDraftObject(Input));
    end;
    Insert(DraftObject, Ordered, Length(Ordered));
  end;

begin
  Ordered := nil;
  Seen := TEvalNodeMap.Create;
  try
    for Index := 0 to FObjects.Count - 1 do
      Visit(Objects[Index]);
  finally
    FreeAndNil(Seen);
  end;
  // Only the order changes, so the list must not free what it lets go of
  FObjects.OwnsObjects := False;
  try
    FObjects.Clear;
    for Index := 0 to High(Ordered) do
      FObjects.Add(Ordered[Index]);
  finally
    FObjects.OwnsObjects := True;
  end;
end;

// A file lists an object's inputs before it. Only seams use a piece, so a piece
// that takes on a newer point can simply move to the end, with its seams after it.
procedure TPattern.KeepInputsBefore(Piece: TPieceObject);
var
  Index: integer;
begin
  FObjects.Move(FObjects.IndexOf(Piece), FObjects.Count - 1);
  for Index := FObjects.Count - 2 downto 0 do
    if (Objects[Index] is TSeamObject) and TSeamObject(Objects[Index]).UsesPiece(Piece.Key) then
      FObjects.Move(Index, FObjects.Count - 1);
end;

function TPattern.SetGrainAngle(Piece: TPieceObject; const Text: string): boolean;
var
  OldKind: TGrainKind;
  OldStart, OldEnd: string;
begin
  OldKind := Piece.GrainKind;
  if OldKind = gkAngle then
    Exit(SetFormula(Piece, GrainAngleField, Text));
  OldStart := Piece.GrainStartKey;
  OldEnd := Piece.GrainEndKey;
  Piece.SetGrainKind(gkAngle);
  Result := SetFormula(Piece, GrainAngleField, Text);
  if not Result then
    Piece.SetGrainKind(OldKind, OldStart, OldEnd);
end;

function TPattern.SetGrainPoints(Piece: TPieceObject; const StartId, EndId: string): boolean;
begin
  if not CheckPoint(StartId) or not CheckPoint(EndId) then
    Exit(False);
  if StartId = EndId then
    Exit(SetError(rsPatternGrainSamePoint));
  Piece.SetGrainKind(gkPoints, StartId, EndId);
  KeepInputsBefore(Piece);
  Result := True;
end;

procedure TPattern.ClearGrain(Piece: TPieceObject);
begin
  Piece.SetGrainKind(gkNone);
end;

function TPattern.AddPointNotch(Piece: TPieceObject; const PointId: string): boolean;
begin
  if not CheckPoint(PointId) then
    Exit(False);
  Piece.AddNotch(PointId, '');
  KeepInputsBefore(Piece);
  Result := True;
end;

function TPattern.AddEdgeNotch(Piece: TPieceObject; const EdgeId, Position: string): boolean;
var
  Index: integer;
begin
  if not CheckEdgeTarget(EdgeId) then
    Exit(False);
  if Piece.PathIndexOf(EdgeId) < 0 then
    Exit(SetError(Format(rsPatternNotInPiece, [FindNode(EdgeId).DisplayName, Piece.DisplayName])));
  Index := Piece.AddNotch('', EdgeId);
  Result := SetFormula(Piece, Piece.NotchField(Index), Position);
  if not Result then
    Piece.RemoveNotch(Index);
end;

function TPattern.RemoveNotch(Piece: TPieceObject; Index: integer): boolean;
begin
  if (Index < 0) or (Index > High(Piece.Notches)) then
    Exit(SetError(Format(rsPatternNoNotch, [Index + 1])));
  Piece.RemoveNotch(Index);
  Result := True;
end;

function TPattern.SetEdgeAllowance(Piece: TPieceObject; PathIndex: integer; const Text: string): boolean;
var
  Added: boolean;
begin
  if Text = '' then
  begin
    Piece.RemoveOverride(PathIndex);
    Exit(True);
  end;
  Added := not Piece.HasOverride(PathIndex);
  if Added then
    Piece.AddOverride(PathIndex);
  Result := SetFormula(Piece, Piece.OverrideField(PathIndex), Text);
  if Added and not Result then
    Piece.RemoveOverride(PathIndex);
end;

function TPattern.SetCut(Piece: TPieceObject; Count: integer; Mirrored: boolean): boolean;
begin
  if Count < 1 then
    Exit(SetError(rsPatternBadCutCount));
  Piece.CutCount := Count;
  Piece.Mirrored := Mirrored;
  Result := True;
end;

function TPattern.SetFoldEdge(Piece: TPieceObject; const EdgeId: string): boolean;
begin
  if EdgeId <> '' then
  begin
    if not CheckEdgeTarget(EdgeId) then
      Exit(False);
    if Piece.PathIndexOf(EdgeId) < 0 then
      Exit(SetError(Format(rsPatternNotInPiece, [FindNode(EdgeId).DisplayName, Piece.DisplayName])));
    if not IsStraightEdge(TEdgeObject(FindNode(EdgeId))) then
      Exit(SetError(Format(rsPatternFoldNotStraight, [FindNode(EdgeId).DisplayName])));
  end;
  Piece.FoldEdgeKey := EdgeId;
  Result := True;
end;

function TPattern.CheckSeamEntry(const Entry: TSeamEntry): boolean;
var
  Node: TEvalNode;
begin
  Node := FindNode(Entry.PieceKey);
  if Node = nil then
    Exit(SetError(Format(rsPatternUnknownObject, [Entry.PieceKey])));
  if not (Node is TPieceObject) then
    Exit(SetError(Format(rsSeamNotAPiece, [Node.DisplayName])));
  if not CheckEdgeTarget(Entry.EdgeKey) then
    Exit(False);
  if TPieceObject(Node).PathIndexOf(Entry.EdgeKey) < 0 then
    Exit(SetError(Format(rsPatternNotInPiece, [FindNode(Entry.EdgeKey).DisplayName, Node.DisplayName])));
  Result := True;
end;

function TPattern.CheckSeamSide(const Side: TSeamSide): boolean;
var
  Index, Other: integer;
begin
  if Side = nil then
    Exit(SetError(rsPatternSeamEmptySide));
  for Index := 0 to High(Side) do
  begin
    if not CheckSeamEntry(Side[Index]) then
      Exit(False);
    for Other := 0 to Index - 1 do
      if (Side[Other].PieceKey = Side[Index].PieceKey) and (Side[Other].EdgeKey = Side[Index].EdgeKey) then
        Exit(SetError(Format(rsPatternSeamRepeats, [FindNode(Side[Index].EdgeKey).DisplayName, FindNode(Side[Index].PieceKey).DisplayName])));
  end;
  Result := True;
end;

function TPattern.AddSeam(const AName: string; const SideA, SideB: TSeamSide; const Ease, Tolerance: string): TSeamObject;
var
  Msg, SeamName: string;
  Entry: TSeamEntry;
  Piece: TPieceObject;
begin
  Result := nil;
  if not CheckSeamSide(SideA) or not CheckSeamSide(SideB) then
    Exit;
  for Entry in Concat(SideA, SideB) do
  begin
    Piece := TPieceObject(FindNode(Entry.PieceKey));
    if Piece.FoldEdgeKey = Entry.EdgeKey then
    begin
      SetError(Format(rsSeamOnFold, [FindNode(Entry.EdgeKey).DisplayName, Piece.DisplayName]));
      Exit;
    end;
  end;
  SeamName := AName;
  if SeamName = '' then
  begin
    FNameExclude := nil;
    SeamName := NextFreeName(NewSeamBaseName, @ObjectNameTaken);
  end
  else if not CheckObjectName(SeamName, nil, Msg) then
  begin
    SetError(Msg);
    Exit;
  end;
  Result := TSeamObject.Create(IntToStr(FNextId), SideA, SideB);
  if not ParseFields(Result, [SeamEaseField, SeamToleranceField], [Ease, Tolerance]) then
  begin
    FreeAndNil(Result);
    Exit;
  end;
  Inc(FNextId);
  Result.Name := SeamName;
  AddObjectNode(Result);
end;

function TPattern.SetFormula(Node: TEvalNode; const AField, Text: string): boolean;
var
  NewFormula: TFormula;
begin
  if Node.Field(AField) = nil then
    Exit(SetError(Format(rsPatternNoField, [Node.DisplayName, AField]), AField));
  NewFormula := TFormula.Create;
  if NewFormula.Parse(Text, ResolverFor(Node)) then
    Exit(InstallFormula(Node, AField, NewFormula));
  Result := SetError(NewFormula.ErrorMessage, AField, NewFormula.ErrorPos);
  FreeAndNil(NewFormula);
end;

function TPattern.SetStoredFormula(Node: TEvalNode; const AField, Text: string): boolean;
var
  NewFormula: TFormula;
begin
  if Node.Field(AField) = nil then
    Exit(SetError(Format(rsPatternNoField, [Node.DisplayName, AField]), AField));
  NewFormula := TFormula.Create;
  if NewFormula.ParseStored(Text) then
    Exit(InstallFormula(Node, AField, NewFormula));
  Result := SetError(NewFormula.ErrorMessage, AField, NewFormula.ErrorPos);
  FreeAndNil(NewFormula);
end;

function TPattern.InstallFormula(Node: TEvalNode; const AField: string; NewFormula: TFormula): boolean;
var
  Ref: TFormulaReference;
  Dep: TEvalNode;
begin
  try
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

function TPattern.Reaches(From, Target: TEvalNode): boolean;
begin
  Result := TEvaluator.Reaches(From, Target, FContext);
end;

// Refuses Key when it would make Target read itself
function TPattern.CheckNotInCircle(Target: TEvalNode; const Key: string): boolean;
var
  Dep: TEvalNode;
begin
  Result := True;
  Dep := FindNode(Key);
  if Dep = Target then
    Exit(SetError(Format(rsPatternUsesItself, [Target.DisplayName])));
  if (Dep <> nil) and TEvaluator.Reaches(Dep, Target, FContext) then
    Exit(SetError(Format(rsPatternCycle, [Target.DisplayName, Dep.DisplayName, Dep.DisplayName, Target.DisplayName])));
end;

function TPattern.ReplacePoint(Point, NewPoint: TPointObject; const Names, Texts: array of string): boolean;
var
  Key: string;
  FieldIndex: integer;
  Ref: TFormulaReference;
  Slot: integer;
begin
  Result := False;
  try
    if Point is TRepeatPoint then
    begin
      SetError(Format(rsPatternRepeatItem, [Point.DisplayName]));
      Exit;
    end;
    for FieldIndex := 0 to High(Names) do
      if not NewPoint.Field(Names[FieldIndex]).ParseStored(Texts[FieldIndex]) then
      begin
        SetError(NewPoint.Field(Names[FieldIndex]).ErrorMessage, Names[FieldIndex], NewPoint.Field(Names[FieldIndex]).ErrorPos);
        Exit;
      end;
    for Key in NewPoint.InputKeys do
      if not CheckNotInCircle(Point, Key) then
        Exit;
    for FieldIndex := 0 to NewPoint.FieldCount - 1 do
      for Ref in NewPoint.Fields[FieldIndex].Formula.References do
        if not CheckNotInCircle(Point, ReferenceKey(Ref)) then
          Exit;
    // The evaluator may hold the node; forget the old graph
    FEvaluator.Rebuild(nil, FContext);
    NewPoint.Name := Point.Name;
    Slot := FObjects.IndexOf(Point);
    FNodes.AddOrSetValue(Point.Key, NewPoint);
    // The list owns its objects, so this frees the old one
    FObjects[Slot] := NewPoint;
    NewPoint := nil;
    OrderObjectsByInputs;
    Result := True;
  finally
    FreeAndNil(NewPoint);
  end;
end;

function TPattern.ConvertToFree(Point: TPointObject; const XText, YText: string): TFreePoint;
begin
  Result := TFreePoint.Create(Point.Key);
  if not ReplacePoint(Point, Result, ['x', 'y'], [XText, YText]) then
    Result := nil;
end;

function TPattern.ConvertToBetween(Point: TPointObject; const FirstId, LastId: string; Mode: TAlongMode; const Value: string): TBetweenPoint;
begin
  Result := nil;
  if not CheckPoint(FirstId) or not CheckPoint(LastId) then
    Exit;
  Result := TBetweenPoint.Create(Point.Key, FirstId, LastId, Mode);
  if not ReplacePoint(Point, Result, ['value'], [Value]) then
    Result := nil;
end;

function TPattern.ConvertToAlongEdge(Point: TPointObject; const EdgeId: string; FromEnd: boolean; Mode: TAlongMode; const Value: string): TAlongEdgePoint;
begin
  Result := nil;
  if not CheckEdgeTarget(EdgeId) then
    Exit;
  Result := TAlongEdgePoint.Create(Point.Key, EdgeId, FromEnd, Mode);
  if not ReplacePoint(Point, Result, ['value'], [Value]) then
    Result := nil;
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
    if Node is TRepeatPoint then
      Exit(SetError(Format(rsPatternRepeatItem, [Node.DisplayName])));
    TDraftObject(Node).Name := NewName;
    if Node is TRepeatObject then
      TRepeatObject(Node).UpdateItemNames;
    if Node is TEdgeObject then
      TEdgeObject(Node).NameIsDerived := False;
    UpdateDerivedNames;
  end
  else
    Exit(SetError(Format(rsPatternCannotRename, [Node.DisplayName])));
  Result := True;
end;

// A repeat's own points do not count, but whatever uses them does
function TPattern.UsersOf(Node: TEvalNode): TEvalNodeArray;
var
  Nodes: TEvalNodeArray;
  Candidate: TEvalNode;
  DepKey: string;
  Item: TRepeatPoint;
begin
  Result := nil;
  Nodes := AllNodes;
  for Candidate in Nodes do
    for DepKey in Candidate.DependencyKeys do
      if (DepKey = Node.Key) and not ((Candidate is TRepeatPoint) and (TRepeatPoint(Candidate).Source = Node)) then
      begin
        SetLength(Result, Length(Result) + 1);
        Result[High(Result)] := Candidate;
        Break;
      end;
  if Node is TRepeatObject then
    for Item in TRepeatObject(Node).UsedItems do
      Result := Concat(Result, UsersOf(Item));
end;

function TPattern.Delete(Node: TEvalNode): boolean;
var
  Item: TRepeatPoint;
  Users: TEvalNodeArray;
  Names: string;
  User: TEvalNode;
begin
  if not ((Node is TVariable) or (Node is TDraftObject)) then
    Exit(SetError(Format(rsPatternCannotDelete, [Node.DisplayName])));
  // The first point stands for the repeat; the others go only with it
  if Node is TRepeatPoint then
  begin
    if TRepeatPoint(Node).Index <> 1 then
      Exit(SetError(Format(rsPatternRepeatItem, [Node.DisplayName])));
    Node := TRepeatPoint(Node).Source;
  end;
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
  if Node is TRepeatObject then
    for Item in TRepeatObject(Node).UsedItems do
      FNodes.Remove(Item.Key);
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
  Item: TRepeatPoint;
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
  // Used repeat points are in the graph, though only their repeat is listed
  for DraftObject in FObjects do
    if DraftObject is TRepeatObject then
      for Item in TRepeatObject(DraftObject).UsedItems do
        Insert(TEvalNode(Item), Result, Length(Result));
end;

procedure TPattern.Evaluate;
begin
  // Measurement nodes are recreated, so drop the old graph first
  FEvaluator.Rebuild(nil, FContext);
  RebuildMeasurementNodes;
  FEvaluator.Rebuild(AllNodes, FContext);
  FEvaluator.Run(FContext);
end;

// Moves the counter past Key (12 -> next ID 13)
procedure TPattern.KeepIdsAbove(const Key: string);
var
  IdNumber, Code: integer;
begin
  Val(Key, IdNumber, Code);
  if (Code = 0) and (IdNumber >= FNextId) then
    FNextId := IdNumber + 1;
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

procedure TPattern.InsertRepeatPoint(ARepeat: TRepeatObject; Index: integer; const Id: string);
begin
  FNodes.Add(Id, ARepeat.UseItem(Index, Id));
  KeepIdsAbove(Id);
end;

end.
