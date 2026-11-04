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
  Sloper.Core.Measurements, Sloper.Core.Variables, Sloper.Core.Draft, Sloper.Core.Fabrics, Sloper.Core.Piece, Sloper.Core.Seam,
  Sloper.Core.Transform;

type
  // What AddTransform needs. Sources are expanded: an edge brings its ends.
  // In order around: from the corner along the width, then up, back and down
  TRectangleEdges = array[0..3] of TLineObject;

  TTransformSpec = record
    Kind: TTransformKind;
    Name, Suffix: string;
    Sources: TStringArray;
    // Rotate: Pivot and Angle. Move with a turn: Pivot and Rotate.
    Pivot, Angle, Rotate: string;
    // Mirror: one of AxisEdge, AxisA and AxisB, or AxisA with Angle
    AxisEdge, AxisA, AxisB: string;
    // Move: Length and Angle when Polar, otherwise DX and DY
    Polar: boolean;
    Length, DX, DY: string;
  end;

  // Where the canvas was left, saved with the pattern but outside undo
  TPatternView = record
    // Set once the canvas has shown the pattern
    HasView: boolean;
    Zoom, CentreX, CentreY: double;
  end;

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
    FFabrics: TPatternFabricList;
    procedure ResetFabrics;
    // Gives the first fabric an ID and puts every piece on it, ready to be
    // written to the file
    procedure MakeFabricsExplicit;
    function FabricNameTaken(const AName: string; Exclude: TPatternFabric = nil): boolean;
    function CheckFabricName(const AName: string; Exclude: TPatternFabric): boolean;
    function FreeFabricColor: string;
    function GetFabricCount: integer;
    function GetFabric(Index: integer): TPatternFabric;
    function DeleteNode(Node: TEvalNode): boolean;
    function DeleteTransform(Transform: TTransformObject): boolean;
    function CopiesOf(Transform: TTransformObject): TDraftObjectArray;
    function ExpandedSources(const Sources: TStringArray; out Expanded: TStringArray): boolean;
    function FreeCopyName(const SourceName, Suffix: string): string;
    function NextSuffix(Kind: TTransformKind): string;
    function BuildTransform(const Spec: TTransformSpec; const Sources: TStringArray): TTransformObject;
    procedure MakeCopies(Transform: TTransformObject; const Sources: TStringArray);
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
    function CheckConvertible(Edge: TEdgeObject): boolean;
    function ChooseKeptPoint(const Points: TPointObjectArray; const AName: string): TPointObject;
    function CheckMergeAway(const Points: TPointObjectArray; Kept: TPointObject; out Doomed: TDraftObjectArray): boolean;
    function ConnectingEdges(Point: TPointObject): TDraftObjectArray;
    function NextBrokenName(const Base: string; var Number: integer; Own: TDraftObject): string;
    procedure RedirectUsers(Point: TPointObject; const KeptKey: string; const Doomed: TDraftObjectArray);
    function ReplaceEdge(Edge, NewEdge: TEdgeObject; const Names, Texts: array of string): boolean;
    function AddEdgeObject(AEdge: TEdgeObject; const AName: string; ARole: TEdgeRole;
      const Names, Texts: array of string): boolean;
    function DerivedEdgeName(AEdge: TEdgeObject): string;
    procedure RebuildMeasurementNodes;
  public
    Notes: string;
    // The measurement file last used with the pattern, as the user chose it;
    // the document resolves it. Not loaded here.
    MeasurementFile: string;
    View: TPatternView;
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
    // Pick 1 is to the left going from A to B, and 2 to the right
    function AddCircleCirclePoint(const AName, CentreAId, RadiusA, CentreBId, RadiusB: string; Pick: integer): TCircleCirclePoint;
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
    function AddCircle(const CentreId, Radius: string; Role: TEdgeRole = erConstruction; const AName: string = ''): TCircleObject;
    function AddArc(const CentreId, Radius, Angle1, Angle2: string; Role: TEdgeRole = erConstruction; const AName: string = ''): TArcObject;
    // Points and lines from CornerId, with Width and Height as formulas. The
    // height is held in one place, the point above the corner.
    function AddRectangle(const CornerId, Width, Height: string; Role: TEdgeRole; out Edges: TRectangleEdges): boolean;
    function AddOffsetEdge(const EdgeId, Distance: string; Side: TOffsetSide; Role: TEdgeRole = erOutline; const AName: string = ''): TOffsetEdge;
    // Rounds the corner where two straight edges meet. Each is split at the
    // arc's tangent point; the part beyond the corner stays, and the rest
    // becomes construction, as the sharp corner's guide.
    function AddRoundCorner(const EdgeAId, EdgeBId, Radius: string): TCornerArc;
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
    function AddHoleMarking(Piece: TPieceObject; const PointId, Diameter: string): boolean;
    // A placement or fold line along an edge
    function AddLineMarking(Piece: TPieceObject; Kind: TMarkingKind; const EdgeId: string): boolean;
    function AddStitchMarking(Piece: TPieceObject; const EdgeId, Spacing, Size: string): boolean;
    function RemoveMarking(Piece: TPieceObject; Index: integer): boolean;
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
    // An edge changed between line and curve in place: its ID, role and place
    // stay, so pieces, seams and formulas that use it go on using it, and a
    // name the user gave it is kept. An arc becomes a line between two new
    // points at its ends, offsets from its centre by its own formulas. A new
    // curve starts straight, its handles a third of the way along. Nil with
    // LastError set when refused.
    function ConvertToLine(Edge: TEdgeObject): TLineObject;
    function ConvertToCurve(Edge: TEdgeObject): TCurveObject;
    // Joins two or more points into one, as Inkscape joins nodes: one point's
    // definition is kept, and whatever used the others uses it instead, then
    // they are deleted, with any line or curve that ran between two of them.
    // It takes MergedName of their names. Kept is the named point unless it is
    // placed from one of the others; then the first that is not. A copy or a
    // repeat's point can only be kept. Nil with LastError set when refused.
    function MergePoints(const Keys: array of string): TPointObject;
    // The opposite of MergePoints: a point where several lines, curves or
    // curve paths meet becomes one point for each of them. The point itself,
    // renamed M1, stays with the first and with everything else that uses it;
    // each other edge gets a new point M2, M3 … placed from it by dx 0, dy 0,
    // so it follows the point until it is moved apart. The point first, nil
    // with LastError set when refused.
    function BreakPoint(Point: TPointObject): TPointObjectArray;
    // Whether From reads Target, directly or through others
    function Reaches(From, Target: TEvalNode): boolean;
    function Rename(Node: TEvalNode; const NewName: string): boolean;
    // Refused while other nodes use Node
    function Delete(Node: TEvalNode): boolean;
    // Nodes that read Node directly
    function UsersOf(Node: TEvalNode): TEvalNodeArray;
    // A formula as the user sees it, with current names
    function FormulaText(Node: TEvalNode; const AField: string): string;

    // A transform and a copy of each source, as one change. The copies start
    // where the formulas put them. Nil with LastError set when refused.
    function AddTransform(const Spec: TTransformSpec): TTransformObject;
    // Fabrics. Changing them returns False when refused, with the reason in
    // LastError. An empty name or colour takes the next free one.
    function AddFabric(const AName: string = ''; const AColor: string = ''; AFill: TFabricFill = ffTint): TPatternFabric;
    function RenameFabric(Fabric: TPatternFabric; const NewName: string): boolean;
    function SetFabricColor(Fabric: TPatternFabric; const AColor: string): boolean;
    // A fabric's allowance goes on a piece when it takes the fabric; it does not
    // follow later changes, so the piece can be set by hand
    function SetFabricAllowance(Fabric: TPatternFabric; HasAllowance: boolean; Allowance: double): boolean;
    procedure SetFabricFill(Fabric: TPatternFabric; AFill: TFabricFill);
    // Refused for the last fabric and for one that pieces use
    function DeleteFabric(Fabric: TPatternFabric): boolean;
    function FindFabric(const Key: string): TPatternFabric;
    function FindFabricNamed(const AName: string): TPatternFabric;
    // The piece's fabric, or nil when it has none
    function FabricOf(Piece: TPieceObject): TPatternFabric;
    // nil leaves the piece with no fabric
    procedure SetPieceFabric(Piece: TPieceObject; Fabric: TPatternFabric);
    // An empty colour and pfFabric go back to the fabric's
    function SetPieceFill(Piece: TPieceObject; const AColor: string; Style: TPieceFillStyle): boolean;
    function PieceLook(Piece: TPieceObject): TPieceLook;
    // CutCaption, with the fabric's name once the pattern has named its fabrics
    // Whole is for a piece opened out to cut flat
    function PieceCaption(Piece: TPieceObject; Whole: boolean = False): string;
    // "Main: Front ×1 on fold, Back ×2 · Lining: Front ×1 on fold"
    function CutList: string;
    function FabricNames: string;
    // For loaders: replaces the first fabric, unless a fabric was inserted already
    procedure InsertFabric(Fabric: TPatternFabric);
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
    property FabricCount: integer read GetFabricCount;
    property Fabrics[Index: integer]: TPatternFabric read GetFabric;
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
  rsPatternNotConvertible = '%s cannot be changed: only lines, curves and arcs can become a line or a curve';
  rsPatternAlreadyLine = '%s is already a line';
  rsPatternAlreadyCurve = '%s is already a curve';
  rsPatternCircleNoEnds = '%s is a whole circle, so it has no ends to join with a line';
  rsPatternOnlyLineToCurve = 'Only a line can become a curve, and %s is an arc';
  rsPatternAngleInUse = '%s reads %s.angle, which only a line has, so it cannot become a curve';
  rsPatternMergeTooFew = 'Select two or more points to merge';
  rsPatternMergeNotPoint = '%s is not a point, so it cannot be merged';
  rsPatternMergeTwoFixed = '%s and %s are copies or a repeat''s points, and only one point can be kept';
  rsPatternMergeKeptReads = '%s is placed from %s, so %s cannot be merged into it';
  rsPatternMergeCopied = '%s is copied by %s, so it cannot be merged away';
  rsPatternMergeEdgeInUse = '%s runs between points being merged and is used by %s';
  rsPatternBreakTooFew = '%s joins fewer than two lines or curves, so there is nothing to break';
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
  rsPatternPieceTooShort = 'A piece needs at least two edges, or one that closes on itself';
  rsPatternCornerNotStraight = 'Only corners between straight edges can be rounded, and %s is not straight';
  rsPatternCornerNotMeeting = '%s and %s do not meet at a point';
  rsPatternCornerInPiece = '%s is part of %s; delete the piece first, then make it again after rounding the corner';
  rsPatternPieceRepeats = 'A piece cannot use %s twice';
  rsPatternNotInPiece = '%s is not part of %s';
  rsPatternFabricTaken = 'There is already a fabric called %s';
  rsPatternFabricBadColor = '%s is not a colour; use the form #5B8DB8';
  rsPatternLastFabric = 'A pattern needs at least one fabric';
  rsPatternFabricInUse = '%s cannot be deleted: %s is cut from it';
  rsPatternPieceCaptionFabric = '%s, %s';
  rsPatternCutEntry = '%s ×%d';
  rsPatternCutEntryFold = '%s ×%d on fold';
  rsPatternCutEntryMirrored = '%s ×%d mirrored';
  rsPatternCutGroup = '%s: %s';
  rsPatternNoFabric = 'No fabric';
  rsPatternObjectsInUse = '%s cannot be deleted: %s uses %s';
  rsPatternCopyOfTransform = '%s is a copy made by %s, so it changes with it';
  rsPatternTransformNothing = 'Select the points and edges to copy';
  rsPatternTransformNotCopyable = '%s cannot be copied: only points and edges can';
  rsPatternSeamEmptySide = 'Each side of a seam needs at least one edge';
  rsPatternSeamRepeats = 'A side of a seam cannot use %s of %s twice';
  rsPatternGrainSamePoint = 'The grainline needs two different points';
  rsPatternNoNotch = 'There is no notch %d';
  rsPatternNoMarking = 'There is no marking %d';
  rsPatternBadCutCount = 'A piece must be cut at least once';
  rsPatternFoldNotStraight = 'A fold has to be straight, and %s is not';

implementation

uses
  Math, Sloper.Core.Names;

const
  // Not translated: a name has to keep to the name rules
  NewVariableBaseName = 'variable';
  NewPieceBaseName = 'Piece';
  NewSeamBaseName = 'Seam';
  TransformBaseNames: array[TTransformKind] of string = ('Rotate', 'Mirror', 'Move');
  TransformSuffixLetters: array[TTransformKind] of string = ('_r', '_m', '_t');

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
  if not Assigned(FPattern.Measurements) then
    Exit(False);
  Measurement := FPattern.Measurements.Find(AName);
  Result := Assigned(Measurement);
  if Result then
    Key := Measurement.Key;
end;

function TPatternResolver.ResolveVariable(const AName: string; out Id: string): boolean;
var
  Variable: TVariable;
begin
  Variable := FPattern.FindVariable(AName);
  Result := Assigned(Variable);
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
  Result := Assigned(DraftObject);
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
  Result := Assigned(FPattern.Measurements) and FPattern.Measurements.TryGetValue(Key, Value);
end;

function TPatternContext.MeasurementProblem(const Key: string): string;
begin
  if not Assigned(FPattern.Measurements) then
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
  FFabrics := TPatternFabricList.Create;
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
  FreeAndNil(FFabrics);
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
  View := Default(TPatternView);
  ResetFabrics;
end;

// As formula text, always with a decimal point
function AllowanceText(Fabric: TPatternFabric): string;
var
  Formats: TFormatSettings;
begin
  Formats := DefaultFormatSettings;
  Formats.DecimalSeparator := '.';
  Result := FloatToStr(Fabric.Allowance, Formats);
end;

procedure TPattern.ResetFabrics;
var
  Fabric: TPatternFabric;
begin
  FFabrics.Clear;
  Fabric := TPatternFabric.Create;
  FFabrics.Add(Fabric);
  Fabric.Name := DefaultFabricName;
  Fabric.Color := FabricPalette[0];
end;

procedure TPattern.MakeFabricsExplicit;
var
  Index: integer;
begin
  if FFabrics[0].Key <> '' then
    Exit;
  FFabrics[0].Key := IntToStr(FNextId);
  Inc(FNextId);
  for Index := 0 to FObjects.Count - 1 do
    if Objects[Index] is TPieceObject then
      TPieceObject(Objects[Index]).FabricKey := FFabrics[0].Key;
end;

function TPattern.GetFabricCount: integer;
begin
  Result := FFabrics.Count;
end;

function TPattern.GetFabric(Index: integer): TPatternFabric;
begin
  Result := FFabrics[Index];
end;

function TPattern.FabricNameTaken(const AName: string; Exclude: TPatternFabric): boolean;
var
  Fabric: TPatternFabric;
begin
  Result := False;
  for Fabric in FFabrics do
    if (Fabric <> Exclude) and SameName(Fabric.Name, AName) then
      Exit(True);
end;

function TPattern.CheckFabricName(const AName: string; Exclude: TPatternFabric): boolean;
var
  Reason: string;
begin
  if not CheckName(AName, Reason) then
    Exit(SetError(Reason));
  if FabricNameTaken(AName, Exclude) then
    Exit(SetError(Format(rsPatternFabricTaken, [AName])));
  Result := True;
end;

// The first colour of the palette no fabric has; they repeat once all are used
function TPattern.FreeFabricColor: string;
var
  Fabric: TPatternFabric;
  Taken: boolean;
begin
  for Result in FabricPalette do
  begin
    Taken := False;
    for Fabric in FFabrics do
      Taken := Taken or SameText(Fabric.Color, Result);
    if not Taken then
      Exit;
  end;
  Result := FabricPalette[FFabrics.Count mod Length(FabricPalette)];
end;

function TPattern.AddFabric(const AName, AColor: string; AFill: TFabricFill): TPatternFabric;
var
  FabricName, FabricColor: string;
  Number: integer;
begin
  Result := nil;
  FabricName := Trim(AName);
  if FabricName = '' then
  begin
    Number := 1;
    FabricName := NewFabricBaseName;
    while FabricNameTaken(FabricName) do
    begin
      Inc(Number);
      FabricName := NewFabricBaseName + IntToStr(Number);
    end;
  end
  else if not CheckFabricName(FabricName, nil) then
    Exit;
  FabricColor := AColor;
  if FabricColor = '' then
    FabricColor := FreeFabricColor
  else if not IsFabricColor(FabricColor) then
  begin
    SetError(Format(rsPatternFabricBadColor, [FabricColor]));
    Exit;
  end;
  MakeFabricsExplicit;
  Result := TPatternFabric.Create;
  FFabrics.Add(Result);
  Result.Key := IntToStr(FNextId);
  Inc(FNextId);
  Result.Name := FabricName;
  Result.Color := UpperCase(FabricColor);
  Result.Fill := AFill;
end;

function TPattern.RenameFabric(Fabric: TPatternFabric; const NewName: string): boolean;
begin
  if not CheckFabricName(Trim(NewName), Fabric) then
    Exit(False);
  MakeFabricsExplicit;
  Fabric.Name := Trim(NewName);
  Result := True;
end;

function TPattern.SetFabricAllowance(Fabric: TPatternFabric; HasAllowance: boolean; Allowance: double): boolean;
begin
  if HasAllowance and (Allowance < 0) then
    Exit(SetError(rsPieceNegativeAllowance));
  MakeFabricsExplicit;
  Fabric.HasAllowance := HasAllowance;
  Fabric.Allowance := Allowance;
  Result := True;
end;

function TPattern.SetFabricColor(Fabric: TPatternFabric; const AColor: string): boolean;
begin
  if not IsFabricColor(AColor) then
    Exit(SetError(Format(rsPatternFabricBadColor, [AColor])));
  MakeFabricsExplicit;
  Fabric.Color := UpperCase(AColor);
  Result := True;
end;

procedure TPattern.SetFabricFill(Fabric: TPatternFabric; AFill: TFabricFill);
begin
  MakeFabricsExplicit;
  Fabric.Fill := AFill;
end;

function TPattern.DeleteFabric(Fabric: TPatternFabric): boolean;
var
  Index: integer;
begin
  if FFabrics.Count = 1 then
    Exit(SetError(rsPatternLastFabric));
  for Index := 0 to FObjects.Count - 1 do
    if (Objects[Index] is TPieceObject) and (FabricOf(TPieceObject(Objects[Index])) = Fabric) then
      Exit(SetError(Format(rsPatternFabricInUse, [Fabric.Name, Objects[Index].DisplayName])));
  FFabrics.Remove(Fabric);
  Result := True;
end;

function TPattern.FindFabric(const Key: string): TPatternFabric;
begin
  for Result in FFabrics do
    if Result.Key = Key then
      Exit;
  Result := nil;
end;

function TPattern.FindFabricNamed(const AName: string): TPatternFabric;
begin
  for Result in FFabrics do
    if SameName(Result.Name, AName) then
      Exit;
  Result := nil;
end;

function TPattern.FabricOf(Piece: TPieceObject): TPatternFabric;
begin
  Result := FindFabric(Piece.FabricKey);
end;

procedure TPattern.SetPieceFabric(Piece: TPieceObject; Fabric: TPatternFabric);
begin
  // The first fabric has a key to tell it from none only once it is explicit
  if not Assigned(Fabric) then
    MakeFabricsExplicit;
  if Assigned(Fabric) then
    Piece.FabricKey := Fabric.Key
  else
    Piece.FabricKey := '';
  if Assigned(Fabric) and Fabric.HasAllowance then
    SetFormula(Piece, PieceAllowanceField, AllowanceText(Fabric));
end;

function TPattern.SetPieceFill(Piece: TPieceObject; const AColor: string; Style: TPieceFillStyle): boolean;
begin
  if (AColor <> '') and not IsFabricColor(AColor) then
    Exit(SetError(Format(rsPatternFabricBadColor, [AColor])));
  Piece.FillColor := UpperCase(AColor);
  Piece.FillStyle := Style;
  Result := True;
end;

function TPattern.PieceLook(Piece: TPieceObject): TPieceLook;
var
  Fabric: TPatternFabric;
begin
  Result := Default(TPieceLook);
  Fabric := FabricOf(Piece);
  if not Assigned(Fabric) then
    Exit;
  Result.Filled := True;
  Result.HatchAngle := FabricHatchAngle(FFabrics.IndexOf(Fabric));
  if Piece.FillColor <> '' then
    Result.Color := ParseFabricColor(Piece.FillColor)
  else
    Result.Color := ParseFabricColor(Fabric.Color);
  case Piece.FillStyle of
    pfFabric: Result.Fill := Fabric.Fill;
    pfTint: Result.Fill := ffTint;
    pfHatch: Result.Fill := ffHatch;
  end;
end;

function TPattern.PieceCaption(Piece: TPieceObject; Whole: boolean): string;
var
  Fabric: TPatternFabric;
begin
  Result := Piece.CutCaption(Whole);
  Fabric := FabricOf(Piece);
  if Assigned(Fabric) and (Fabric.Key <> '') then
    Result := Format(rsPatternPieceCaptionFabric, [Result, Fabric.Name]);
end;

function TPattern.CutList: string;
const
  EntryGap = ', ';
  GroupGap = ' · ';
var
  Index: integer;

  function Entry(Piece: TPieceObject): string;
  begin
    if Piece.OnFold then
      Result := Format(rsPatternCutEntryFold, [Piece.DisplayName, Piece.CutCount])
    else if Piece.Mirrored and (Piece.CutCount > 1) then
      Result := Format(rsPatternCutEntryMirrored, [Piece.DisplayName, Piece.CutCount])
    else
      Result := Format(rsPatternCutEntry, [Piece.DisplayName, Piece.CutCount]);
  end;

  procedure AddGroup(Fabric: TPatternFabric; const Caption: string);
  var
    Entries: string;
    Place: integer;
  begin
    Entries := '';
    for Place := 0 to FObjects.Count - 1 do
      if (Objects[Place] is TPieceObject) and (FabricOf(TPieceObject(Objects[Place])) = Fabric) then
      begin
        if Entries <> '' then
          Entries := Entries + EntryGap;
        Entries := Entries + Entry(TPieceObject(Objects[Place]));
      end;
    if Entries = '' then
      Exit;
    if Result <> '' then
      Result := Result + GroupGap;
    Result := Result + Format(rsPatternCutGroup, [Caption, Entries]);
  end;

begin
  Result := '';
  for Index := 0 to FFabrics.Count - 1 do
    AddGroup(FFabrics[Index], FFabrics[Index].Name);
  AddGroup(nil, rsPatternNoFabric);
end;

function TPattern.FabricNames: string;
var
  Fabric: TPatternFabric;
begin
  Result := '';
  for Fabric in FFabrics do
  begin
    if Result <> '' then
      Result := Result + ', ';
    Result := Result + Fabric.Name;
  end;
end;

procedure TPattern.InsertFabric(Fabric: TPatternFabric);
begin
  if FFabrics[0].Key = '' then
    FFabrics.Clear;
  FFabrics.Add(Fabric);
  KeepIdsAbove(Fabric.Key);
end;

// Every source once, points first, an edge bringing its ends. Virtual repeat
// points take an ID here, so this is inside the change.
function TPattern.ExpandedSources(const Sources: TStringArray; out Expanded: TStringArray): boolean;
var
  Points, Edges: TStringArray;
  Key, Used: string;
  Node: TEvalNode;

  procedure AddOnce(var List: TStringArray; const AKey: string);
  var
    Item: string;
  begin
    for Item in List do
      if Item = AKey then
        Exit;
    Insert(AKey, List, System.Length(List));
  end;

begin
  Points := nil;
  Edges := nil;
  Expanded := nil;
  if Length(Sources) = 0 then
    Exit(SetError(rsPatternTransformNothing));
  for Key in Sources do
  begin
    Node := FindNode(Key);
    if not Assigned(Node) then
      Exit(SetError(Format(rsPatternUnknownObject, [Key])));
    if Node is TPointObject then
    begin
      Used := UsePoint(Key);
      AddOnce(Points, Used);
    end
    else if Node is TEdgeObject then
    begin
      AddOnce(Edges, Key);
      AddOnce(Points, UsePoint(TEdgeObject(Node).StartKey));
      AddOnce(Points, UsePoint(TEdgeObject(Node).EndKey));
    end
    else
      Exit(SetError(Format(rsPatternTransformNotCopyable, [Node.DisplayName])));
  end;
  Expanded := Concat(Points, Edges);
  Result := True;
end;

// The lowest number no transform of this kind has used
function TPattern.NextSuffix(Kind: TTransformKind): string;
var
  Number, Index: integer;
  Taken: boolean;
begin
  Number := 0;
  repeat
    Inc(Number);
    Result := TransformSuffixLetters[Kind] + IntToStr(Number);
    Taken := False;
    for Index := 0 to FObjects.Count - 1 do
      if (Objects[Index] is TTransformObject) and SameName(TTransformObject(Objects[Index]).Suffix, Result) then
        Taken := True;
  until not Taken;
end;

// A name cannot hold a repeat point's brackets
function TPattern.FreeCopyName(const SourceName, Suffix: string): string;
begin
  FNameExclude := nil;
  Result := NextFreeName(StringReplace(StringReplace(SourceName, '[', '_', []), ']', '', []) + Suffix, @ObjectNameTaken);
end;

function TPattern.BuildTransform(const Spec: TTransformSpec; const Sources: TStringArray): TTransformObject;
var
  Suffix, TransformName, Msg: string;
  Names, Texts: TStringArray;

  procedure AddField(const AName, Text: string);
  begin
    Insert(AName, Names, System.Length(Names));
    Insert(Text, Texts, System.Length(Texts));
  end;

begin
  Result := nil;
  Suffix := Spec.Suffix;
  if Suffix = '' then
    Suffix := NextSuffix(Spec.Kind);
  TransformName := Spec.Name;
  if TransformName = '' then
  begin
    FNameExclude := nil;
    TransformName := NextFreeName(TransformBaseNames[Spec.Kind], @ObjectNameTaken);
  end
  else if not CheckObjectName(TransformName, nil, Msg) then
  begin
    SetError(Msg);
    Exit;
  end;
  Names := nil;
  Texts := nil;
  Result := TTransformObject.Create(IntToStr(FNextId), Spec.Kind, Sources, Suffix);
  case Spec.Kind of
    tkRotate:
    begin
      Result.UseRotate(Spec.Pivot);
      AddField(FieldAngle, Spec.Angle);
    end;
    tkMirror:
      if Spec.AxisEdge <> '' then
        Result.UseAxisEdge(Spec.AxisEdge)
      else if Spec.AxisB <> '' then
        Result.UseAxisPoints(Spec.AxisA, Spec.AxisB)
      else
      begin
        Result.UseAxisAngle(Spec.AxisA);
        AddField(FieldAngle, Spec.Angle);
      end;
    tkMove:
    begin
      Result.UseMove(Spec.Polar, Spec.Pivot);
      if Spec.Polar then
      begin
        AddField(FieldLength, Spec.Length);
        AddField(FieldAngle, Spec.Angle);
      end
      else
      begin
        AddField(FieldDX, Spec.DX);
        AddField(FieldDY, Spec.DY);
      end;
      if Spec.Pivot <> '' then
        AddField(FieldRotate, Spec.Rotate);
    end;
  end;
  if not ParseFields(Result, Names, Texts) then
  begin
    FreeAndNil(Result);
    Exit;
  end;
  Inc(FNextId);
  Result.Name := TransformName;
end;

procedure TPattern.MakeCopies(Transform: TTransformObject; const Sources: TStringArray);
var
  Key, CopyKey: string;
  Node: TEvalNode;
  Edge: TEdgeObject;
  Point: TPointCopy;
  Copied: TEdgeCopy;
  PointCopies: TEvalNodeMap;
begin
  PointCopies := TEvalNodeMap.Create;
  try
    for Key in Sources do
    begin
      Node := FindNode(Key);
      CopyKey := IntToStr(FNextId);
      Inc(FNextId);
      if Node is TPointObject then
      begin
        Point := TPointCopy.Create(CopyKey, Transform.Key, Key);
        Point.Name := FreeCopyName(Node.DisplayName, Transform.Suffix);
        AddObjectNode(Point);
        PointCopies.Add(Key, Point);
      end
      else
      begin
        Edge := TEdgeObject(Node);
        Copied := TEdgeCopy.Create(CopyKey, Transform.Key, Key, PointCopies[Edge.StartKey].Key, PointCopies[Edge.EndKey].Key, Edge.IsStraight, Edge.NamePrefix);
        Copied.Name := FreeCopyName(Edge.DisplayName, Transform.Suffix);
        Copied.NameIsDerived := False;
        Copied.Role := Edge.Role;
        AddObjectNode(Copied);
      end;
    end;
  finally
    FreeAndNil(PointCopies);
  end;
end;

function TPattern.AddTransform(const Spec: TTransformSpec): TTransformObject;
var
  Expanded: TStringArray;
  Axis: TEvalNode;
begin
  Result := nil;
  if not ExpandedSources(Spec.Sources, Expanded) then
    Exit;
  if Spec.Pivot <> '' then
    if not (FindNode(Spec.Pivot) is TPointObject) then
    begin
      SetError(Format(rsDraftNotAPoint, [Spec.Pivot]));
      Exit;
    end;
  if Spec.AxisEdge <> '' then
  begin
    Axis := FindNode(Spec.AxisEdge);
    if not (Axis is TEdgeObject) then
    begin
      SetError(Format(rsDraftNotAnEdge, [Spec.AxisEdge]));
      Exit;
    end;
    if not TEdgeObject(Axis).IsStraight then
    begin
      SetError(Format(rsTransformCurvedAxis, [Axis.DisplayName]));
      Exit;
    end;
  end;
  if (Spec.Kind = tkMirror) and (Spec.AxisEdge = '') and not (FindNode(Spec.AxisA) is TPointObject) then
  begin
    SetError(Format(rsDraftNotAPoint, [Spec.AxisA]));
    Exit;
  end;
  Result := BuildTransform(Spec, Expanded);
  if not Assigned(Result) then
    Exit;
  AddObjectNode(Result);
  MakeCopies(Result, Expanded);
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
  Result := Assigned(Existing) and (Existing <> FNameExclude);
end;

function TPattern.CheckObjectName(const AName: string; Exclude: TDraftObject;
  out ErrorMessage: string): boolean;
var
  Existing: TDraftObject;
begin
  if not CheckName(AName, ErrorMessage) then
    Exit(False);
  Existing := FindObject(AName);
  if Assigned(Existing) and (Existing <> Exclude) then
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
  if Assigned(Existing) and (Existing <> Exclude) then
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
  if not Assigned(Node) then
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
  if not Assigned(Node) then
    Exit(SetError(Format(rsPatternUnknownObject, [Id])));
  if not (Node is TEdgeObject) then
    Exit(SetError(Format(rsDraftNotAnEdge, [Node.DisplayName])));
  Result := True;
end;

function TPattern.VariableNameTaken(const AName: string): boolean;
begin
  Result := Assigned(FindVariable(AName));
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
        if Assigned(Item) then
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

function TPattern.AddCircleCirclePoint(const AName, CentreAId, RadiusA, CentreBId, RadiusB: string; Pick: integer): TCircleCirclePoint;
begin
  Result := nil;
  if not CheckPoint(CentreAId) or not CheckPoint(CentreBId) then
    Exit;
  if (Pick < 1) or (Pick > 2) then
  begin
    SetError(rsPatternBadPick);
    Exit;
  end;
  Result := TCircleCirclePoint.Create(IntToStr(FNextId), CentreAId, CentreBId, Pick);
  if not AddPointObject(Result, AName, ['radiusA', 'radiusB'], [RadiusA, RadiusB]) then
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
  if AEdge.StartKey = AEdge.EndKey then
    Result := AEdge.NamePrefix + '_' + EndName(FindNode(AEdge.StartKey))
  else
    Result := AEdge.NamePrefix + '_' + EndName(FindNode(AEdge.StartKey)) + '_' + EndName(FindNode(AEdge.EndKey));
  Result := NextFreeName(Result, @ObjectNameTaken);
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

function TPattern.AddCircle(const CentreId, Radius: string; Role: TEdgeRole; const AName: string): TCircleObject;
begin
  Result := TCircleObject.Create(IntToStr(FNextId), CentreId);
  if not AddEdgeObject(Result, AName, Role, ['radius'], [Radius]) then
    Result := nil;
end;

function TPattern.AddArc(const CentreId, Radius, Angle1, Angle2: string; Role: TEdgeRole; const AName: string): TArcObject;
begin
  Result := TArcObject.Create(IntToStr(FNextId), CentreId);
  if not AddEdgeObject(Result, AName, Role, ['radius', 'angle1', 'angle2'], [Radius, Angle1, Angle2]) then
    Result := nil;
end;

function TPattern.AddRectangle(const CornerId, Width, Height: string; Role: TEdgeRole; out Edges: TRectangleEdges): boolean;
var
  Corner: TEvalNode;
  Across, Above, Opposite: TOffsetPoint;
  CornerName: string;
begin
  Edges := Default(TRectangleEdges);
  Result := CheckPoint(CornerId);
  if not Result then
    Exit;
  Corner := FindNode(CornerId);
  CornerName := Corner.DisplayName;
  Across := AddOffsetPoint('', CornerId, omCartesian, Width, '0');
  if not Assigned(Across) then
    Exit(False);
  Above := AddOffsetPoint('', CornerId, omCartesian, '0', Height);
  if not Assigned(Above) then
    Exit(False);
  Opposite := AddOffsetPoint('', Across.Key, omCartesian, '0', Above.DisplayName + '.y - ' + CornerName + '.y');
  if not Assigned(Opposite) then
    Exit(False);
  Edges[0] := AddLine(CornerId, Across.Key, Role);
  Edges[1] := AddLine(Across.Key, Opposite.Key, Role);
  Edges[2] := AddLine(Opposite.Key, Above.Key, Role);
  Edges[3] := AddLine(Above.Key, CornerId, Role);
  Result := Assigned(Edges[0]) and Assigned(Edges[1]) and Assigned(Edges[2]) and Assigned(Edges[3]);
end;

function TPattern.AddOffsetEdge(const EdgeId, Distance: string; Side: TOffsetSide; Role: TEdgeRole; const AName: string): TOffsetEdge;
var
  Source: TEdgeObject;
begin
  Result := nil;
  if not CheckEdgeTarget(EdgeId) then
    Exit;
  Source := TEdgeObject(FindNode(EdgeId));
  Result := TOffsetEdge.Create(IntToStr(FNextId), EdgeId, Source.StartKey, Source.EndKey, Side);
  if not AddEdgeObject(Result, AName, Role, ['distance'], [Distance]) then
    Result := nil;
end;

function TPattern.AddRoundCorner(const EdgeAId, EdgeBId, Radius: string): TCornerArc;
var
  First, Second: TEdgeObject;
  Vertex: string;
  Starts, Ends: TSplitPart;
  TangentA, TangentB: TCornerPoint;

  function CheckEdge(Edge: TEdgeObject): boolean;
  var
    User: TEvalNode;
  begin
    if not Edge.IsStraight then
      Exit(SetError(Format(rsPatternCornerNotStraight, [Edge.DisplayName])));
    for User in UsersOf(Edge) do
      if User is TPieceObject then
        Exit(SetError(Format(rsPatternCornerInPiece, [Edge.DisplayName, User.DisplayName])));
    Result := True;
  end;

  // Splits the edge and returns the part away from the corner; the sharp end
  // and the whole edge become construction
  function Trim(Edge: TEdgeObject; const PointKey: string): TEdgeObject;
  var
    Near: TSplitPart;
  begin
    Result := nil;
    if not SplitEdge(Edge.Key, PointKey, Starts, Ends) then
      Exit;
    if Edge.StartKey = Vertex then
    begin
      Near := Starts;
      Result := Ends;
    end
    else
    begin
      Near := Ends;
      Result := Starts;
    end;
    Near.Role := erConstruction;
    Edge.Role := erConstruction;
  end;

begin
  Result := nil;
  if not CheckEdgeTarget(EdgeAId) or not CheckEdgeTarget(EdgeBId) then
    Exit;
  First := TEdgeObject(FindNode(EdgeAId));
  Second := TEdgeObject(FindNode(EdgeBId));
  if not CheckEdge(First) or not CheckEdge(Second) then
    Exit;
  if (First.StartKey = Second.StartKey) or (First.StartKey = Second.EndKey) then
    Vertex := First.StartKey
  else if (First.EndKey = Second.StartKey) or (First.EndKey = Second.EndKey) then
    Vertex := First.EndKey
  else
  begin
    SetError(Format(rsPatternCornerNotMeeting, [First.DisplayName, Second.DisplayName]));
    Exit;
  end;
  Result := TCornerArc.Create(IntToStr(FNextId), Vertex, EdgeAId, EdgeBId);
  if not AddEdgeObject(Result, '', First.Role, ['radius'], [Radius]) then
  begin
    Result := nil;
    Exit;
  end;
  TangentA := TCornerPoint.Create(IntToStr(FNextId), Result.Key, 1);
  if not AddPointObject(TangentA, '', [], []) then
    Exit(nil);
  TangentB := TCornerPoint.Create(IntToStr(FNextId), Result.Key, 2);
  if not AddPointObject(TangentB, '', [], []) then
    Exit(nil);
  Result.TrimmedA := Trim(First, TangentA.Key);
  Result.TrimmedB := Trim(Second, TangentB.Key);
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
  Msg, PieceName, PieceAllowance: string;
begin
  Result := nil;
  // One edge will do only when it closes on itself, like a circle
  if (Length(Path) = 0) or ((Length(Path) = 1) and not ((FindNode(Path[0].EdgeKey) is TEdgeObject) and TEdgeObject(FindNode(Path[0].EdgeKey)).IsClosed)) then
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
  // The first fabric's allowance stands in for the general default
  PieceAllowance := Allowance;
  if (Allowance = DefaultPieceAllowance) and FFabrics[0].HasAllowance then
    PieceAllowance := AllowanceText(FFabrics[0]);
  if not ParseFields(Result, [PieceAllowanceField], [PieceAllowance]) then
  begin
    FreeAndNil(Result);
    Exit;
  end;
  Inc(FNextId);
  Result.Name := PieceName;
  Result.FabricKey := FFabrics[0].Key;
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

function TPattern.AddHoleMarking(Piece: TPieceObject; const PointId, Diameter: string): boolean;
var
  Index: integer;
begin
  if not CheckPoint(PointId) then
    Exit(False);
  Index := Piece.AddMarking(mkHole, PointId, '');
  KeepInputsBefore(Piece);
  Result := SetFormula(Piece, Piece.MarkingField(Index, MarkingDiameterField), Diameter);
  if not Result then
    Piece.RemoveMarking(Index);
end;

function TPattern.AddLineMarking(Piece: TPieceObject; Kind: TMarkingKind; const EdgeId: string): boolean;
begin
  if not CheckEdgeTarget(EdgeId) then
    Exit(False);
  Piece.AddMarking(Kind, '', EdgeId);
  KeepInputsBefore(Piece);
  Result := True;
end;

function TPattern.AddStitchMarking(Piece: TPieceObject; const EdgeId, Spacing, Size: string): boolean;
var
  Index: integer;
begin
  if not CheckEdgeTarget(EdgeId) then
    Exit(False);
  Index := Piece.AddMarking(mkStitchHoles, '', EdgeId);
  KeepInputsBefore(Piece);
  Result := SetFormula(Piece, Piece.MarkingField(Index, MarkingSpacingField), Spacing) and SetFormula(Piece, Piece.MarkingField(Index, MarkingSizeField), Size);
  if not Result then
    Piece.RemoveMarking(Index);
end;

function TPattern.RemoveMarking(Piece: TPieceObject; Index: integer): boolean;
begin
  if (Index < 0) or (Index > High(Piece.Markings)) then
    Exit(SetError(Format(rsPatternNoMarking, [Index + 1])));
  Piece.RemoveMarking(Index);
  Result := True;
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
  if not Assigned(Node) then
    Exit(SetError(Format(rsPatternUnknownObject, [Entry.PieceKey])));
  if not (Node is TPieceObject) then
    Exit(SetError(Format(rsSeamNotAPiece, [Node.DisplayName])));
  if not Assigned(FindNode(Entry.EdgeKey)) then
    Exit(SetError(Format(rsPatternUnknownObject, [Entry.EdgeKey])));
  if not (FindNode(Entry.EdgeKey) is TEdgeObject) then
    Exit(SetError(Format(rsDraftNotAnEdge, [FindNode(Entry.EdgeKey).DisplayName])));
  if TPieceObject(Node).PathIndexOf(Entry.EdgeKey) < 0 then
    Exit(SetError(Format(rsPatternNotInPiece, [FindNode(Entry.EdgeKey).DisplayName, Node.DisplayName])));
  Result := True;
end;

function TPattern.CheckSeamSide(const Side: TSeamSide): boolean;
var
  Index, Other: integer;
begin
  if Length(Side) = 0 then
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
  if not Assigned(Node.Field(AField)) then
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
  if not Assigned(Node.Field(AField)) then
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
      if Assigned(Dep) and TEvaluator.Reaches(Dep, Node, FContext) then
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
  if Assigned(Dep) and TEvaluator.Reaches(Dep, Target, FContext) then
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
    if Point is TPointCopy then
    begin
      SetError(Format(rsPatternCopyOfTransform, [Point.DisplayName, FindNode(TPointCopy(Point).TransformKey).DisplayName]));
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

// Lines, curves and arcs the user drew; copies and parts follow other edges
function TPattern.CheckConvertible(Edge: TEdgeObject): boolean;
begin
  if Edge is TEdgeCopy then
    Exit(SetError(Format(rsPatternCopyOfTransform, [Edge.DisplayName, FindNode(TEdgeCopy(Edge).TransformKey).DisplayName])));
  if Edge.ClassType = TCircleObject then
    Exit(SetError(Format(rsPatternCircleNoEnds, [Edge.DisplayName])));
  if (Edge.ClassType <> TLineObject) and (Edge.ClassType <> TCurveObject) and (Edge.ClassType <> TArcObject) then
    Exit(SetError(Format(rsPatternNotConvertible, [Edge.DisplayName])));
  Result := True;
end;

// As ReplacePoint, for an edge: NewEdge takes Edge's ID, place, role and name,
// or a fresh derived name when Edge's was derived
function TPattern.ReplaceEdge(Edge, NewEdge: TEdgeObject; const Names, Texts: array of string): boolean;
var
  Key: string;
  FieldIndex, Slot: integer;
begin
  Result := False;
  try
    for FieldIndex := 0 to High(Names) do
      if not NewEdge.Field(Names[FieldIndex]).ParseStored(Texts[FieldIndex]) then
      begin
        SetError(NewEdge.Field(Names[FieldIndex]).ErrorMessage, Names[FieldIndex], NewEdge.Field(Names[FieldIndex]).ErrorPos);
        Exit;
      end;
    for Key in NewEdge.InputKeys do
      if not CheckNotInCircle(Edge, Key) then
        Exit;
    // The evaluator may hold the node; forget the old graph
    FEvaluator.Rebuild(nil, FContext);
    NewEdge.Role := Edge.Role;
    NewEdge.NameIsDerived := Edge.NameIsDerived;
    NewEdge.Name := Edge.Name;
    Slot := FObjects.IndexOf(Edge);
    FNodes.AddOrSetValue(Edge.Key, NewEdge);
    // The list owns its objects, so this frees the old one
    FObjects[Slot] := NewEdge;
    if NewEdge.NameIsDerived then
      NewEdge.Name := DerivedEdgeName(NewEdge);
    NewEdge := nil;
    OrderObjectsByInputs;
    Result := True;
  finally
    FreeAndNil(NewEdge);
  end;
end;

function TPattern.ConvertToLine(Edge: TEdgeObject): TLineObject;
var
  StartPoint, EndPoint: TOffsetPoint;
  Radius: string;
begin
  Result := nil;
  if not CheckConvertible(Edge) then
    Exit;
  if Edge is TLineObject then
  begin
    SetError(Format(rsPatternAlreadyLine, [Edge.DisplayName]));
    Exit;
  end;
  if Edge is TArcObject then
  begin
    Radius := FormulaText(Edge, 'radius');
    StartPoint := AddOffsetPoint('', TArcObject(Edge).Centre, omPolar, Radius, FormulaText(Edge, 'angle1'));
    if not Assigned(StartPoint) then
      Exit;
    EndPoint := AddOffsetPoint('', TArcObject(Edge).Centre, omPolar, Radius, FormulaText(Edge, 'angle2'));
    if not Assigned(EndPoint) then
      Exit;
    Result := TLineObject.Create(Edge.Key, StartPoint.Key, EndPoint.Key);
  end
  else
    Result := TLineObject.Create(Edge.Key, Edge.StartKey, Edge.EndKey);
  if not ReplaceEdge(Edge, Result, [], []) then
    Result := nil;
end;

function TPattern.ConvertToCurve(Edge: TEdgeObject): TCurveObject;
var
  User: TEvalNode;
  FieldIndex: integer;
  Ref: TFormulaReference;
  Direction, BackAngle, Handle: double;
  Formats: TFormatSettings;

  function Text(Value: double): string;
  begin
    Result := FloatToStr(RoundTo(Value, -1), Formats);
  end;

begin
  Result := nil;
  if not CheckConvertible(Edge) then
    Exit;
  if Edge is TCurveObject then
  begin
    SetError(Format(rsPatternAlreadyCurve, [Edge.DisplayName]));
    Exit;
  end;
  if Edge is TArcObject then
  begin
    SetError(Format(rsPatternOnlyLineToCurve, [Edge.DisplayName]));
    Exit;
  end;
  for User in UsersOf(Edge) do
    for FieldIndex := 0 to User.FieldCount - 1 do
      for Ref in User.Fields[FieldIndex].Formula.References do
        if (ReferenceKey(Ref) = Edge.Key) and SameText(Ref.Prop, 'angle') then
        begin
          SetError(Format(rsPatternAngleInUse, [User.DisplayName, Edge.DisplayName]));
          Exit;
        end;
  Formats := DefaultFormatSettings;
  Formats.DecimalSeparator := '.';
  // The handles are placed from where the line is now
  if not Edge.HasResult then
    Evaluate;
  Direction := 0;
  Handle := 0;
  if Edge.HasResult then
  begin
    Direction := Edge.StartDirection;
    Handle := Edge.Length / 3;
  end;
  // The end handle points back along the edge
  BackAngle := FMod(Direction + 180, 360);
  Result := TCurveObject.Create(Edge.Key, Edge.StartKey, Edge.EndKey);
  if not ReplaceEdge(Edge, Result, ['angle1', 'length1', 'angle2', 'length2'],
    [Text(Direction), Text(Handle), Text(BackAngle), Text(Handle)]) then
    Result := nil;
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

function IndexOfObject(const Objects: TDraftObjectArray; DraftObject: TEvalNode): integer;
var
  Index: integer;
begin
  for Index := 0 to High(Objects) do
    if Objects[Index] = DraftObject then
      Exit(Index);
  Result := -1;
end;

// A copy or a repeat's point follows something else, so it cannot be deleted
function IsFixedPoint(Point: TPointObject): boolean;
begin
  Result := (Point is TPointCopy) or (Point is TRepeatPoint);
end;

// The point named AName when it reads none of the others, or else the first
// that reads none of them; a fixed point has to be the one kept
function TPattern.ChooseKeptPoint(const Points: TPointObjectArray; const AName: string): TPointObject;
var
  Point, Other, Fixed: TPointObject;

  function ReadsAnother(Candidate: TPointObject): TPointObject;
  var
    Member: TPointObject;
  begin
    for Member in Points do
      if (Member <> Candidate) and Reaches(Candidate, Member) then
        Exit(Member);
    Result := nil;
  end;

begin
  Result := nil;
  Fixed := nil;
  for Point in Points do
    if IsFixedPoint(Point) then
    begin
      if Assigned(Fixed) then
      begin
        SetError(Format(rsPatternMergeTwoFixed, [Fixed.DisplayName, Point.DisplayName]));
        Exit;
      end;
      Fixed := Point;
    end;
  if Assigned(Fixed) then
  begin
    Other := ReadsAnother(Fixed);
    if Assigned(Other) then
      SetError(Format(rsPatternMergeKeptReads, [Fixed.DisplayName, Other.DisplayName, Other.DisplayName]))
    else
      Result := Fixed;
    Exit;
  end;
  for Point in Points do
    if SameName(Point.Name, AName) and not Assigned(ReadsAnother(Point)) then
      Exit(Point);
  for Point in Points do
    if not Assigned(ReadsAnother(Point)) then
      Exit(Point);
end;

// Doomed: the points to merge away, and lines and curves between two of the
// points, which nothing else may use
function TPattern.CheckMergeAway(const Points: TPointObjectArray; Kept: TPointObject; out Doomed: TDraftObjectArray): boolean;
var
  Point: TPointObject;
  User: TEvalNode;
  Index, NodeIndex: integer;
  Edge: TEdgeObject;
  Path: TCurvePathObject;

  function InGroup(const Key: string): boolean;
  var
    Member: TPointObject;
  begin
    for Member in Points do
      if Member.Key = Key then
        Exit(True);
    Result := False;
  end;

begin
  Result := False;
  Doomed := nil;
  for Point in Points do
    if Point <> Kept then
    begin
      for User in UsersOf(Point) do
        if User is TPointCopy then
          Exit(SetError(Format(rsPatternMergeCopied, [Point.DisplayName, FindNode(TPointCopy(User).TransformKey).DisplayName])));
      Insert(Point, Doomed, Length(Doomed));
    end;
  for Index := 0 to FObjects.Count - 1 do
  begin
    if Objects[Index] is TCurvePathObject then
    begin
      Path := TCurvePathObject(Objects[Index]);
      for NodeIndex := 1 to High(Path.NodeKeys) do
        if InGroup(Path.NodeKeys[NodeIndex - 1]) and InGroup(Path.NodeKeys[NodeIndex]) then
          Exit(SetError(rsPatternPathRepeats));
    end;
    if not ((Objects[Index].ClassType = TLineObject) or (Objects[Index].ClassType = TCurveObject)) then
      Continue;
    Edge := TEdgeObject(Objects[Index]);
    if InGroup(Edge.StartKey) and InGroup(Edge.EndKey) then
      Insert(Edge, Doomed, Length(Doomed));
  end;
  for Index := 0 to High(Doomed) do
    if Doomed[Index] is TEdgeObject then
      for User in UsersOf(Doomed[Index]) do
        if IndexOfObject(Doomed, User) < 0 then
          Exit(SetError(Format(rsPatternMergeEdgeInUse, [Doomed[Index].DisplayName, User.DisplayName])));
  Result := True;
end;

// Every object but the doomed reads KeptKey instead of Point, in its inputs
// and its formulas
procedure TPattern.RedirectUsers(Point: TPointObject; const KeptKey: string; const Doomed: TDraftObjectArray);
var
  Node: TEvalNode;
  Ref: TFormulaReference;
  Index: integer;
  Formula: TFormula;
begin
  for Node in AllNodes do
  begin
    if not (Node is TDraftObject) or (IndexOfObject(Doomed, Node) >= 0) then
      Continue;
    TDraftObject(Node).RedirectPoint(Point.Key, KeptKey);
    for Index := 0 to Node.FieldCount - 1 do
    begin
      Formula := Node.Fields[Index].Formula;
      for Ref in Formula.References do
        if Ref.Id = Point.Key then
        begin
          // In stored form braces hold only IDs
          Formula.ParseStored(StringReplace(Formula.StoredText, '{' + Point.Key + '}', '{' + KeptKey + '}', [rfReplaceAll]));
          Break;
        end;
    end;
  end;
end;

function TPattern.MergePoints(const Keys: array of string): TPointObject;
var
  Points: TPointObjectArray;
  Names: TStringArray;
  Doomed: TDraftObjectArray;
  Key, KeptKey, NewName: string;
  Node: TEvalNode;
  Item: TDraftObject;
  Deleted: boolean;
  Index: integer;

  function HasPoint(Candidate: TEvalNode): boolean;
  var
    Member: TPointObject;
  begin
    for Member in Points do
      if Member = Candidate then
        Exit(True);
    Result := False;
  end;

begin
  Result := nil;
  Points := nil;
  Names := nil;
  for Key in Keys do
  begin
    Node := FindNode(Key);
    if not Assigned(Node) then
    begin
      SetError(Format(rsPatternUnknownObject, [Key]));
      Exit;
    end;
    if not (Node is TPointObject) then
    begin
      SetError(Format(rsPatternMergeNotPoint, [Node.DisplayName]));
      Exit;
    end;
    if not HasPoint(Node) then
    begin
      Insert(TPointObject(Node), Points, Length(Points));
      Insert(TPointObject(Node).Name, Names, Length(Names));
    end;
  end;
  if Length(Points) < 2 then
  begin
    SetError(rsPatternMergeTooFew);
    Exit;
  end;
  NewName := MergedName(Names);
  Result := ChooseKeptPoint(Points, NewName);
  if not Assigned(Result) or not CheckMergeAway(Points, Result, Doomed) then
    Exit(nil);
  // A repeat's point that nothing uses yet needs an ID before anything can
  KeptKey := UsePoint(Result.Key);
  // The evaluator may hold the nodes; forget the old graph
  FEvaluator.Rebuild(nil, FContext);
  for Item in Doomed do
    if Item is TPointObject then
      RedirectUsers(TPointObject(Item), KeptKey, Doomed);
  // Doomed objects may read each other, so each goes once nothing does
  repeat
    Deleted := False;
    for Index := High(Doomed) downto 0 do
      if Length(UsersOf(Doomed[Index])) = 0 then
      begin
        DeleteNode(Doomed[Index]);
        System.Delete(Doomed, Index, 1);
        Deleted := True;
      end;
  until not Deleted;
  Result := TPointObject(FindNode(KeptKey));
  if not IsFixedPoint(Result) then
    Result.Name := NewName;
  UpdateDerivedNames;
  OrderObjectsByInputs;
end;

// Lines, curves and curve paths that pass through or end at Point, in list
// order; derived edges follow their sources and are left out
function TPattern.ConnectingEdges(Point: TPointObject): TDraftObjectArray;
var
  Index: integer;
  Candidate: TDraftObject;
  Key: string;
begin
  Result := nil;
  for Index := 0 to FObjects.Count - 1 do
  begin
    Candidate := Objects[Index];
    if (Candidate.ClassType <> TLineObject) and (Candidate.ClassType <> TCurveObject) and (Candidate.ClassType <> TCurvePathObject) then
      Continue;
    for Key in Candidate.InputKeys do
      if Key = Point.Key then
      begin
        Insert(Candidate, Result, Length(Result));
        Break;
      end;
  end;
end;

// Base followed by the next number from Number that no other object has
function TPattern.NextBrokenName(const Base: string; var Number: integer; Own: TDraftObject): string;
var
  Taken: TDraftObject;
begin
  repeat
    Result := Base + IntToStr(Number);
    Inc(Number);
    Taken := FindObject(Result);
  until not Assigned(Taken) or (Taken = Own);
end;

function TPattern.BreakPoint(Point: TPointObject): TPointObjectArray;
var
  Edges: TDraftObjectArray;
  Base: string;
  Number, Index: integer;
  Added: TOffsetPoint;
begin
  Result := nil;
  if Point is TRepeatPoint then
  begin
    SetError(Format(rsPatternRepeatItem, [Point.DisplayName]));
    Exit;
  end;
  if Point is TPointCopy then
  begin
    SetError(Format(rsPatternCopyOfTransform, [Point.DisplayName, FindNode(TPointCopy(Point).TransformKey).DisplayName]));
    Exit;
  end;
  Edges := ConnectingEdges(Point);
  if Length(Edges) < 2 then
  begin
    SetError(Format(rsPatternBreakTooFew, [Point.DisplayName]));
    Exit;
  end;
  // A copy's number is replaced, as when copying: M2 breaks into M3, M4
  Base := Point.Name;
  while (Length(Base) > 1) and (Base[Length(Base)] in ['0'..'9']) do
    System.Delete(Base, Length(Base), 1);
  Number := 1;
  Point.Name := NextBrokenName(Base, Number, Point);
  Insert(Point, Result, 0);
  for Index := 1 to High(Edges) do
  begin
    Added := AddOffsetPoint(NextBrokenName(Base, Number, nil), Point.Key, omCartesian, '0', '0');
    if not Assigned(Added) then
      Exit(nil);
    Edges[Index].RedirectPoint(Point.Key, Added.Key);
    Insert(TPointObject(Added), Result, Length(Result));
  end;
  // The evaluator may hold the old graph
  FEvaluator.Rebuild(nil, FContext);
  UpdateDerivedNames;
  OrderObjectsByInputs;
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

function TPattern.CopiesOf(Transform: TTransformObject): TDraftObjectArray;
var
  Index: integer;
begin
  Result := nil;
  for Index := 0 to FObjects.Count - 1 do
    if CopyTransformKey(Objects[Index]) = Transform.Key then
      Insert(Objects[Index], Result, System.Length(Result));
end;

// With its copies, unless something else uses one
function TPattern.DeleteTransform(Transform: TTransformObject): boolean;
var
  Copies: TDraftObjectArray;
  Item: TDraftObject;
  User: TEvalNode;
  Index: integer;

  function IsCopy(Node: TEvalNode): boolean;
  begin
    Result := CopyTransformKey(Node) = Transform.Key;
  end;

begin
  Copies := CopiesOf(Transform);
  for Item in Copies do
    for User in UsersOf(Item) do
      if not IsCopy(User) then
        Exit(SetError(Format(rsPatternInUse, [Item.DisplayName, User.DisplayName])));
  for User in UsersOf(Transform) do
    if not IsCopy(User) then
      Exit(SetError(Format(rsPatternInUse, [Transform.DisplayName, User.DisplayName])));
  // Edges first, since they read the points
  for Index := High(Copies) downto 0 do
    DeleteNode(Copies[Index]);
  Result := DeleteNode(Transform);
end;

function TPattern.Delete(Node: TEvalNode): boolean;
begin
  if CopyTransformKey(Node) <> '' then
    Exit(SetError(Format(rsPatternCopyOfTransform, [Node.DisplayName, FindNode(CopyTransformKey(Node)).DisplayName])));
  if Node is TTransformObject then
    Exit(DeleteTransform(TTransformObject(Node)));
  Result := DeleteNode(Node);
end;

function TPattern.DeleteNode(Node: TEvalNode): boolean;
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
