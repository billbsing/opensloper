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
  Sloper.Core.Measurements, Sloper.Core.Variables, Sloper.Core.Draft, Sloper.Core.Materials, Sloper.Core.Piece, Sloper.Core.Seam,
  Sloper.Core.Transform, Sloper.Core.Note, Sloper.Core.Geometry, Sloper.Core.Units, Sloper.Core.PatternMaterials;

type
  // In order around: from the corner along the width, then up, back and down
  TRectangleEdges = array[0..3] of TLineObject;

  // What AddTransform needs. Sources are expanded: an edge brings its ends.
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
  TPatternView = class
  private
    FHasView: boolean;
    FZoom, FCentreX, FCentreY: double;
    FHiddenRoles: TEdgeRoles;
    FHideAnnotations: boolean;
  public
    // Back to a pattern never shown, with every role and the notes showing
    procedure Reset;
    // Set once the canvas has shown the pattern
    property HasView: boolean read FHasView write FHasView;
    property Zoom: double read FZoom write FZoom;
    property CentreX: double read FCentreX write FCentreX;
    property CentreY: double read FCentreY write FCentreY;
    // Roles the drafting app does not show (see Visibility, styles and
    // output in the design); never Outline
    property HiddenRoles: TEdgeRoles read FHiddenRoles write FHiddenRoles;
    // Notes are not drawn on the canvas or in draft export
    property HideAnnotations: boolean read FHideAnnotations write FHideAnnotations;
  end;

  TMeasurementNodeList = specialize TObjectList<TMeasurementNode>;
  TVariableList = specialize TObjectList<TVariable>;
  TDraftObjectList = specialize TObjectList<TDraftObject>;
  TEvalNodeMap = specialize TDictionary<string, TEvalNode>;

  TPattern = class
  private
    FMeasurements: TMeasurementSet;
    FMeasurementScale: double;
    FUnits: TMeasureUnit;
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
    FLastErrorField: string;
    FLastErrorPos: integer;
    FMaterialSet: TPatternMaterials;
    FNotes, FMeasurementFile, FIdentity: string;
    FView: TPatternView;
    // Marking lines and marked points to give a piece after the next
    // evaluation, which works out where they lie; FAssignLoose adds every one
    // without a piece
    FPendingMarkings: TStringArray;
    FAssignLoose: boolean;
    procedure QueueMarking(DraftObject: TDraftObject);
    function AssignPendingMarkings: boolean;
    // Takes the object's marking lines or marked points off every piece
    procedure DetachMarking(const Key: string);
    // The next ID, counted past. A new object takes its ID before its
    // formulas are parsed, so a repeat's point they name takes a later one.
    function TakeId: string;
    // A refused new object's ID goes back, unless something took one since
    procedure GiveBackId(const Key: string);
    // Every piece, in pattern order
    function PieceList: TPieceObjectArray;
    function GetMaterialCount: integer;
    function GetMaterial(Index: integer): TPatternMaterial;
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
    function CheckNoteAnchor(Anchor: TNoteAnchor; const AnchorKey: string; out Key: string): boolean;
    function NoteAnchorPlace(Anchor: TNoteAnchor; const Key: string; Ratio: double): TVec2;
    procedure FollowSplit(Source: TEdgeObject; First, Second: TSplitPart);
    procedure FollowCorner(Arc: TCornerArc; NearA, NearB: TSplitPart);
    function GetVariableCount: integer;
    function GetVariable(Index: integer): TVariable;
    function GetObjectCount: integer;
    function GetObject(Index: integer): TDraftObject;
    function FindRepeatItem(const Key: string): TEvalNode;
    function ObjectNameTaken(const AName: string): boolean;
    function VariableNameTaken(const AName: string): boolean;
    function ResolverFor(Node: TEvalNode): TNameResolver;
    function ParseFields(Node: TEvalNode; const Names, Texts: array of string): boolean;
    // A point or repeat that can take a marker
    function CheckMarkerTarget(const Id: string): boolean;
    function AddPointObject(APoint: TDraftObject; const AName: string;
      const Names, Texts: array of string): boolean;
    function CheckNotInCircle(Target: TEvalNode; const Key: string): boolean;
    // Takes NewFormula once it is parsed, refusing anything that would make
    // Node read itself; frees it either way
    function InstallFormula(Node: TEvalNode; const AField: string; NewFormula: TFormula): boolean;
    function AddEdgeObject(AEdge: TEdgeObject; const AName: string; ARole: TEdgeRole;
      const Names, Texts: array of string): boolean;
    function DerivedEdgeName(AEdge: TEdgeObject): string;
    procedure RebuildMeasurementNodes;
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
    // A free name for a new variable: variable, variable2 and so on
    function NewVariableName: string;
    function AddFreePoint(const AName, XText, YText: string): TFreePoint;
    // LengthOrDx and AngleOrDy are length and angle (omPolar) or dx and dy (omCartesian)
    function AddOffsetPoint(const AName, BaseId: string; Mode: TOffsetMode; const LengthOrDx, AngleOrDy: string): TOffsetPoint;
    function AddAlongEdgePoint(const AName, EdgeId: string; FromEnd: boolean;
      Mode: TAlongMode; const Value: string): TAlongEdgePoint;
    function AddBetweenPoint(const AName, FirstId, LastId: string; Mode: TAlongMode; const Value: string): TBetweenPoint;
    // Count points between two points, or along an edge by arc length
    function AddRepeatBetween(const AName, FirstId, LastId, CountText: string; IncludeEnds: boolean): TRepeatObject;
    function AddRepeatOnEdge(const AName, EdgeId, CountText: string; IncludeEnds: boolean): TRepeatObject;
    // A key an operation can store: a virtual repeat point takes an ID now,
    // which is what first use means. Call it inside a change.
    function UsePoint(const Key: string): string;
    // Every point there is, a repeat's included, in order
    function AllPoints: TPointObjectArray;
    // Where two edges cross; Pick numbers the crossings from 1 along EdgeA
    function AddIntersectPoint(const AName, EdgeAId, EdgeBId: string;
      ExtendA, ExtendB: boolean; Pick: integer): TIntersectPoint;
    // Where a circle around CentreId crosses an edge (a compass step)
    function AddCircleEdgePoint(const AName, CentreId, Radius, EdgeId: string;
      Extend: boolean; Pick: integer): TCircleEdgePoint;
    // Where two circles cross. Pick 1 is to the left going from A to B, and 2
    // to the right.
    function AddCircleCirclePoint(const AName, CentreAId, RadiusA, CentreBId, RadiusB: string; Pick: integer): TCircleCirclePoint;
    // From SourceId onto an edge, square to it or at the Angle formula
    // (Angle is ignored for pdPerpendicular)
    function AddProjectPoint(const AName, SourceId, EdgeId: string;
      Direction: TProjectDirection; const Angle: string; Extend: boolean): TProjectPoint;
    function AddLine(const StartId, EndId: string; Role: TEdgeRole = erConstruction;
      const AName: string = ''): TLineObject;
    function AddCurve(const StartId, EndId, Angle1, Length1, Angle2, Length2: string;
      Role: TEdgeRole = erConstruction; const AName: string = ''): TCurveObject;
    function AddCircle(const CentreId, Radius: string; Role: TEdgeRole = erConstruction; const AName: string = ''): TCircleObject;
    function AddArc(const CentreId, Radius, Angle1, Angle2: string; Role: TEdgeRole = erConstruction; const AName: string = ''): TArcObject;
    // Points and lines from CornerId, with Width and Height as formulas: the
    // corner is the top left, with the width to the right and the height
    // down. The height is held in one place, the point below the corner.
    function AddRectangle(const CornerId, Width, Height: string; Role: TEdgeRole; out Edges: TRectangleEdges): boolean;
    function AddOffsetEdge(const EdgeId, Distance: string; Side: TOffsetSide; Role: TEdgeRole = erOutline; const AName: string = ''): TOffsetEdge;
    // A parallel copy of a connected run of edges (see TOffsetEdge)
    function AddOffsetRun(const Run: TRunEdgeArray; const Distance: string; Side: TOffsetSide; Role: TEdgeRole = erOutline;
      const AName: string = ''): TOffsetEdge;
    // The edges in order along one connected run, each turned to follow it,
    // from computed positions. False with the reason when they branch, leave
    // a gap or are not edges.
    function ChainRun(const EdgeIds: TStringArray; out Run: TRunEdgeArray): boolean;
    // The edges in the order the piece's path runs, as one connected stretch
    // of it, and the side that is inside or outside the piece. False with the
    // reason when an edge is not on the piece or the stretch has a gap.
    function PieceRun(Piece: TPieceObject; const EdgeIds: TStringArray; Inside: boolean; out Run: TRunEdgeArray;
      out Side: TOffsetSide): boolean;
    // Rounds the corner where two straight edges meet. Each is split at the
    // arc's tangent point; the part beyond the corner stays, and the rest
    // becomes construction, as the sharp corner's guide.
    function AddRoundCorner(const EdgeAId, EdgeBId, Radius: string): TCornerArc;
    // A smooth curve through NodeIds. Angles are the tangent at each node
    // (direction of travel); LengthsIn and LengthsOut the handle lengths before
    // and after it. All arrays have one entry per node; LengthsIn[0] and the
    // last LengthsOut are ignored.
    function AddCurvePath(const NodeIds, Angles, LengthsIn, LengthsOut: array of string;
      Role: TEdgeRole = erConstruction; const AName: string = ''): TCurvePathObject;
    // Splits an edge at a point on it into two new edges, which follow the
    // edge and the point. The edge itself stays, and the pieces and seams
    // that used it take the parts instead (see FollowSplit).
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
    // Gives a point or repeat a marker, with its size as a formula ('' for
    // the marker's default size). A marker gives it to every piece it lies
    // inside at the next evaluation, and plain takes it off them.
    function SetMarker(const Id: string; AMarker: TPointMarker; const Size: string = ''): boolean;
    // Attaches a marking line, or a point or repeat with a marker, to a
    // piece by hand, whatever it lies in
    function AddLineMarking(Piece: TPieceObject; const EdgeId: string): boolean;
    function AddPointMarking(Piece: TPieceObject; const Id: string): boolean;
    // Changes an edge's role. A marking role gives the edge to every piece it
    // lies inside at the next evaluation, and any other takes it off them.
    function SetEdgeRole(Edge: TEdgeObject; Role: TEdgeRole): boolean;
    // Most of the edge, sampled along it, or of a marked point's or repeat's
    // positions, lies inside the piece's cutting line
    function LiesInside(DraftObject: TDraftObject; Piece: TPieceObject): boolean;
    // The pieces that print this marking line or marked point
    function PiecesWithMarking(const Key: string): TPieceObjectArray;
    // A marking line or a point or repeat with a marker
    function IsMarking(DraftObject: TDraftObject): boolean;
    // An edge whose role the view hides, or a note while notes are hidden
    function IsHidden(DraftObject: TDraftObject): boolean;
    // Sets LastError, for a caller that refuses before changing anything;
    // always False
    function Refuse(const Msg: string): boolean;
    function AddStitchMarking(Piece: TPieceObject; const EdgeId, Spacing, Size: string): boolean;
    function RemoveMarking(Piece: TPieceObject; Index: integer): boolean;
    function SetCut(Piece: TPieceObject; Count: integer; Mirrored: boolean): boolean;
    // Cuts the piece on the fold along a straight edge of it; an empty EdgeId
    // clears the fold
    function SetFoldEdge(Piece: TPieceObject; const EdgeId: string): boolean;
    // A seam between two sides. An empty name takes the next free one: Seam,
    // Seam2 and so on. Nil with LastError set when refused.
    function AddSeam(const AName: string; const SideA, SideB: TSeamSide; const Ease: string = DEFAULT_SEAM_EASE;
      const Tolerance: string = DEFAULT_SEAM_TOLERANCE): TSeamObject;
    // Whether Side has edges, each once and each on the piece beside it. For
    // loaders too: a fold set after the seam is made only makes it invalid.
    function CheckSeamSide(const Side: TSeamSide): boolean;
    // A note anchored to AnchorKey, which must be of the anchor's kind, with
    // its offset dx and dy as formulas (x and y for a free note) and, on an
    // edge, Position as a ratio from its start. An empty name takes the next
    // free one: Note, Note2 and so on. Nil with LastError set when refused.
    // A leader other than nlNone makes it a callout, which a free note
    // cannot be.
    function AddNote(const AName, AText: string; Anchor: TNoteAnchor; const AnchorKey, Position, DxOrX, DyOrY: string;
      ASize: double = DEFAULT_NOTE_SIZE; APrint: boolean = True; ALeader: TNoteLeader = nlNone): TNoteObject;
    // Text as typed, draft values {=...} with names. Refused when one does
    // not parse, with the reason and its place in LastError.
    function SetNoteText(Note: TNoteObject; const AText: string): boolean;
    // Refused unless above 0 and at most MAX_NOTE_SIZE points
    function SetNoteSize(Note: TNoteObject; ASize: double): boolean;
    procedure SetNotePrint(Note: TNoteObject; APrint: boolean);
    // Refused for a free note, which has nothing to point at
    function SetNoteLeader(Note: TNoteObject; ALeader: TNoteLeader): boolean;
    procedure SetNoteAlign(Note: TNoteObject; AAlign: TTextAlign);
    procedure SetNoteBoxed(Note: TNoteObject; ABoxed: boolean);
    // Hangs the note from another anchor, Ratio along an edge, keeping its
    // text where it was last drawn, as when a callout's tip is dragged. A
    // callout cannot be made free.
    function SetNoteAnchor(Note: TNoteObject; Anchor: TNoteAnchor; const AnchorKey: string; Ratio: double = 0): boolean;
    // Unhooks an anchored note, leaving it where it was last drawn, so that
    // its anchor can be deleted
    function MakeNoteFree(Note: TNoteObject): boolean;
    // The pieces a note prints with: the piece it is anchored to, the pieces
    // whose outline, notches or markings use its point or edge, and those
    // whose cutting line its top left lies in. A callout goes with what it
    // points at, so for it the place is its tip.
    function NotePieces(Note: TNoteObject): TPieceObjectArray;
    // The notes that print with the piece, in pattern order
    function PieceNotes(Piece: TPieceObject): TNoteObjectArray;

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
    // Carries a curve or curve path on through PointId, in place, as a curve
    // path (see Sloper.Core.TypeChange.ExtendCurve)
    function ExtendCurve(Edge: TEdgeObject; const PointId: string): TCurvePathObject;
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
    // A formula as the user sees it, with current names; '' when the node
    // has no such field, as a marker's size once it is plain
    function FormulaText(Node: TEvalNode; const AField: string): string;

    // A transform and a copy of each source, as one change. The copies start
    // where the formulas put them. Nil with LastError set when refused.
    function AddTransform(const Spec: TTransformSpec): TTransformObject;
    // Materials. Changing them returns False when refused, with the reason in
    // LastError. An empty name or colour takes the next free one.
    function AddMaterial(const AName: string = ''; const AColor: string = ''; AFill: TMaterialFill = ffTint): TPatternMaterial;
    function RenameMaterial(Material: TPatternMaterial; const NewName: string): boolean;
    function SetMaterialColor(Material: TPatternMaterial; const AColor: string): boolean;
    // A material's allowance goes on a piece when it takes the material; it does not
    // follow later changes, so the piece can be set by hand
    function SetMaterialAllowance(Material: TPatternMaterial; HasAllowance: boolean; Allowance: double): boolean;
    procedure SetMaterialFill(Material: TPatternMaterial; AFill: TMaterialFill);
    // Refused for the last material and for one that pieces use
    function DeleteMaterial(Material: TPatternMaterial): boolean;
    function FindMaterial(const Key: string): TPatternMaterial;
    function FindMaterialNamed(const AName: string): TPatternMaterial;
    // The piece's material, or nil when it has none
    function MaterialOf(Piece: TPieceObject): TPatternMaterial;
    // nil leaves the piece with no material
    procedure SetPieceMaterial(Piece: TPieceObject; Material: TPatternMaterial);
    // An empty colour and pfMaterial go back to the material's
    function SetPieceFill(Piece: TPieceObject; const AColor: string; Style: TPieceFillStyle): boolean;
    function PieceLook(Piece: TPieceObject): TPieceLook;
    // CutCaption, with the material's name once the pattern has named its materials
    // Whole is for a piece opened out to cut flat
    function PieceCaption(Piece: TPieceObject; Whole: boolean = False): string;
    // "Main: Front ×1 on fold, Back ×2 · Lining: Front ×1 on fold"
    function CutList: string;
    function MaterialNames: string;
    // For loaders: replaces the first material, unless a material was inserted already
    procedure InsertMaterial(Material: TPatternMaterial);
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
    // The objects with these keys join the pieces they lie in at the next
    // evaluation, as new markings do; for objects added by a loader, such as
    // pasted ones
    procedure QueueMarkings(const Keys: array of string);

    // Not owned. Can be nil or swapped for another person's set.
    property Measurements: TMeasurementSet read FMeasurements write FMeasurements;
    // Every measurement value is multiplied by this as the pattern reads it,
    // to try the pattern a size up or down. 1 by default; like Measurements,
    // not part of the pattern, so it is never saved and Clear keeps it.
    property MeasurementScale: double read FMeasurementScale write FMeasurementScale;
    // The unit formulas are worked out in; geometry stays in mm. Saved with
    // the pattern; Clear sets mm. Evaluate again after changing it.
    property Units: TMeasureUnit read FUnits write FUnits;
    property Resolver: TNameResolver read FResolver;
    property Evaluator: TEvaluator read FEvaluator;
    property VariableCount: integer read GetVariableCount;
    property Variables[Index: integer]: TVariable read GetVariable;
    property ObjectCount: integer read GetObjectCount;
    property MaterialCount: integer read GetMaterialCount;
    property Materials[Index: integer]: TPatternMaterial read GetMaterial;
    property Objects[Index: integer]: TDraftObject read GetObject;
    // The next ID to hand out. Loaders and undo may raise it; IDs are never reused.
    property NextId: integer read FNextId write FNextId;
    property Notes: string read FNotes write FNotes;
    // The measurement file last used with the pattern, as the user chose it;
    // the document resolves it. Not loaded here.
    property MeasurementFile: string read FMeasurementFile write FMeasurementFile;
    // Tells this pattern from others when objects are pasted (see
    // Sloper.Core.Fragment); made by NewPatternIdentity and kept by Save As.
    // Empty, as after Clear, matches no pattern.
    property Identity: string read FIdentity write FIdentity;
    // Owned; Clear resets it
    property View: TPatternView read FView;
    property LastError: string read FLastError;
    property LastErrorField: string read FLastErrorField;
    property LastErrorPos: integer read FLastErrorPos;

    // The editing kernel, for the core units that edit the pattern through
    // it (Sloper.Core.TypeChange, Sloper.Core.PointMerge). The apps use the
    // methods above, which keep the pattern whole; these leave that to the
    // caller.
    // Sets LastError, LastErrorField and LastErrorPos; always False
    function SetError(const Msg: string; const AField: string = ''; Pos: integer = 0): boolean;
    // Drops the evaluator's graph, which may hold nodes about to be freed or
    // replaced; the next Evaluate builds it again
    procedure ForgetGraph;
    // Frees Node, which nothing may use, and takes it off every list
    function DeleteNode(Node: TEvalNode): boolean;
    // Files list each object after its inputs. A changed point may now read
    // objects further down, so they move up; the rest stay in their order.
    procedure OrderObjectsByInputs;
    // NewPoint takes Point's ID, place and name, with Names parsed from Texts
    // in stored form; Point is freed. Refused, with NewPoint freed and Point
    // left as it was, for a repeat's point or a copy, a formula that does not
    // parse, or an input that reads Point.
    function ReplacePoint(Point, NewPoint: TPointObject; const Names, Texts: array of string): boolean;
    // As ReplacePoint, for an edge: NewEdge also takes Edge's role, and a
    // fresh derived name when Edge's was derived
    function ReplaceEdge(Edge, NewEdge: TEdgeObject; const Names, Texts: array of string): boolean;
    // That Id is a point, or an edge, with the reason when not
    function CheckPoint(const Id: string): boolean;
    function CheckEdgeTarget(const Id: string): boolean;
  end;

// A new random identity for a pattern
function NewPatternIdentity: string;

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
  rsPatternPieceTooShort = 'A piece needs at least two edges, or one that closes on itself';
  rsPatternCornerNotStraight = 'Only corners between straight edges can be rounded, and %s is not straight';
  rsPatternCornerNotMeeting = '%s and %s do not meet at a point';
  rsPatternCornerOnFold = '%s is the fold of %s, and a fold has to stay one straight edge';
  rsPatternPieceRepeats = 'A piece cannot use %s twice';
  rsPatternNotInPiece = '%s is not part of %s';
  rsPatternObjectsInUse = '%s cannot be deleted: %s uses %s';
  rsPatternCopyOfTransform = '%s is a copy made by %s, so it changes with it';
  rsPatternTransformNothing = 'Select the points and edges to copy';
  rsPatternTransformNotCopyable = '%s cannot be copied: only points and edges can';
  rsPatternSeamEmptySide = 'Each side of a seam needs at least one edge';
  rsPatternSeamRepeats = 'A side of a seam cannot use %s of %s twice';
  rsPatternGrainSamePoint = 'The grainline needs two different points';
  rsPatternNoNotch = 'There is no notch %d';
  rsPatternNoMarking = 'There is no marking %d';
  rsPatternNotMarkingLine = '%s is not a marking line; give it a role such as Placement or Stitch first';
  rsPatternLineIsOutline = '%s is part of the outline of %s';
  rsPatternLineMarked = '%s is already marked on %s';
  rsPatternNoRun = 'Select the edges to offset';
  rsPatternRunNotJoined = 'The edges must join end to end in one run, without branches or gaps';
  rsPatternRunNotComputed = '%s has not been worked out, so it cannot be offset';
  rsPatternMarkerOnRepeat = '%s is one of the points of %s; give the repeat its marker';
  rsPatternNoMarker = '%s has no marker; give it one such as Hole or Button first';
  rsPatternBadCutCount = 'A piece must be cut at least once';
  rsPatternFoldNotStraight = 'A fold has to be straight, and %s is not';
  rsPatternNoteAnchor = 'A note cannot hang from %s: it must be a %s';
  rsPatternNoteAnchorPoint = 'point';
  rsPatternNoteAnchorEdge = 'line or curve';
  rsPatternNoteAnchorPiece = 'piece';
  rsPatternNoteSize = 'A note''s size must be above 0 and at most %d points';
  rsPatternNoteIsFree = '%s is not anchored to anything';
  rsPatternCalloutFree = 'A callout needs a point, an edge or a piece to point at';

implementation

uses
  Math, StrUtils, Sloper.Core.Names, Sloper.Core.TypeChange, Sloper.Core.PointMerge;

const
  CHAIN_TOLERANCE = 0.01;
  INSIDE_SAMPLES = 8;

function NewPatternIdentity: string;
var
  Guid: TGUID;
begin
  CreateGUID(Guid);
  Result := LowerCase(Copy(GUIDToString(Guid), 2, 36));
end;

procedure TPatternView.Reset;
begin
  FHasView := False;
  FZoom := 0;
  FCentreX := 0;
  FCentreY := 0;
  FHiddenRoles := [];
  FHideAnnotations := False;
end;

const
  // pmPlain has no size; the entry is never used
  MARKER_STARTING_LENGTHS: array[TPointMarker] of TStartingLength = (slHoleSize, slHoleSize, slButtonSize, slMatchSize);
  // Not translated: a name has to keep to the name rules
  NEW_VARIABLE_BASE_NAME = 'variable';
  NEW_PIECE_BASE_NAME = 'Piece';
  NEW_SEAM_BASE_NAME = 'Seam';
  NEW_NOTE_BASE_NAME = 'Note';
  NOTE_RATIO_DECIMALS = 4;
  TRANSFORM_BASE_NAMES: array[TTransformKind] of string = ('Rotate', 'Mirror', 'Move');
  TRANSFORM_SUFFIX_LETTERS: array[TTransformKind] of string = ('_r', '_m', '_t');

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
    function LengthScale: double; override;
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
  // Files keep mm; formulas read the pattern unit
  if Result then
    Value := Value * FPattern.MeasurementScale / LengthScale;
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
  if Result and IsLengthProperty(Prop) then
    Value := Value / LengthScale;
end;

function TPatternContext.LengthScale: double;
begin
  Result := MILLIMETRES_PER_UNIT[FPattern.Units];
end;

{ TPattern }

constructor TPattern.Create;
var
  Host: TMaterialsHost;
begin
  FMeasurementNodes := TMeasurementNodeList.Create;
  FVariables := TVariableList.Create;
  FObjects := TDraftObjectList.Create;
  FNodes := TEvalNodeMap.Create;
  FEvaluator := TEvaluator.Create;
  FResolver := TPatternResolver.Create(Self, True);
  FVariableResolver := TPatternResolver.Create(Self, False);
  FContext := TPatternContext.Create(Self);
  Host.NewId := @TakeId;
  Host.KeepIdAbove := @KeepIdsAbove;
  Host.Pieces := @PieceList;
  Host.Refuse := @Refuse;
  FMaterialSet := TPatternMaterials.Create(Host);
  FView := TPatternView.Create;
  FMeasurementScale := 1;
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
  FreeAndNil(FMaterialSet);
  FreeAndNil(FView);
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
  FUnits := muMillimetre;
  FPendingMarkings := nil;
  FAssignLoose := False;
  FNotes := '';
  FMeasurementFile := '';
  FIdentity := '';
  FView.Reset;
  FMaterialSet.Reset;
end;

function TPattern.TakeId: string;
begin
  Result := IntToStr(FNextId);
  Inc(FNextId);
end;

procedure TPattern.GiveBackId(const Key: string);
begin
  if StrToIntDef(Key, 0) = FNextId - 1 then
    Dec(FNextId);
end;

function TPattern.PieceList: TPieceObjectArray;
var
  DraftObject: TDraftObject;
begin
  Result := nil;
  for DraftObject in FObjects do
    if DraftObject is TPieceObject then
      Insert(TPieceObject(DraftObject), Result, Length(Result));
end;

// The materials are in Sloper.Core.PatternMaterials

function TPattern.GetMaterialCount: integer;
begin
  Result := FMaterialSet.Count;
end;

function TPattern.GetMaterial(Index: integer): TPatternMaterial;
begin
  Result := FMaterialSet[Index];
end;

function TPattern.AddMaterial(const AName, AColor: string; AFill: TMaterialFill): TPatternMaterial;
begin
  Result := FMaterialSet.Add(AName, AColor, AFill);
end;

function TPattern.RenameMaterial(Material: TPatternMaterial; const NewName: string): boolean;
begin
  Result := FMaterialSet.Rename(Material, NewName);
end;

function TPattern.SetMaterialAllowance(Material: TPatternMaterial; HasAllowance: boolean; Allowance: double): boolean;
begin
  Result := FMaterialSet.SetAllowance(Material, HasAllowance, Allowance);
end;

function TPattern.SetMaterialColor(Material: TPatternMaterial; const AColor: string): boolean;
begin
  Result := FMaterialSet.SetColor(Material, AColor);
end;

procedure TPattern.SetMaterialFill(Material: TPatternMaterial; AFill: TMaterialFill);
begin
  FMaterialSet.SetFill(Material, AFill);
end;

function TPattern.DeleteMaterial(Material: TPatternMaterial): boolean;
begin
  Result := FMaterialSet.Delete(Material);
end;

function TPattern.FindMaterial(const Key: string): TPatternMaterial;
begin
  Result := FMaterialSet.Find(Key);
end;

function TPattern.FindMaterialNamed(const AName: string): TPatternMaterial;
begin
  Result := FMaterialSet.FindNamed(AName);
end;

function TPattern.MaterialOf(Piece: TPieceObject): TPatternMaterial;
begin
  Result := FMaterialSet.MaterialOf(Piece);
end;

procedure TPattern.SetPieceMaterial(Piece: TPieceObject; Material: TPatternMaterial);
begin
  FMaterialSet.SetPieceMaterial(Piece, Material);
  if Assigned(Material) and Material.HasAllowance then
    SetFormula(Piece, PIECE_ALLOWANCE_FIELD, MaterialAllowanceText(Material));
end;

function TPattern.SetPieceFill(Piece: TPieceObject; const AColor: string; Style: TPieceFillStyle): boolean;
begin
  Result := FMaterialSet.SetPieceFill(Piece, AColor, Style);
end;

function TPattern.PieceLook(Piece: TPieceObject): TPieceLook;
begin
  Result := FMaterialSet.PieceLook(Piece);
end;

function TPattern.PieceCaption(Piece: TPieceObject; Whole: boolean): string;
begin
  Result := FMaterialSet.PieceCaption(Piece, Whole);
end;

function TPattern.CutList: string;
begin
  Result := FMaterialSet.CutList;
end;

function TPattern.MaterialNames: string;
begin
  Result := FMaterialSet.Names;
end;

procedure TPattern.InsertMaterial(Material: TPatternMaterial);
begin
  FMaterialSet.Insert(Material);
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
    Result := TRANSFORM_SUFFIX_LETTERS[Kind] + IntToStr(Number);
    Taken := False;
    for Index := 0 to FObjects.Count - 1 do
      if (Objects[Index] is TTransformObject) and SameName(TTransformObject(Objects[Index]).Suffix, Result) then
        Taken := True;
  until not Taken;
end;

// A name cannot hold a repeat point's brackets
function TPattern.FreeCopyName(const SourceName, Suffix: string): string;
begin
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
    TransformName := NextFreeName(TRANSFORM_BASE_NAMES[Spec.Kind], @ObjectNameTaken);
  end
  else if not CheckObjectName(TransformName, nil, Msg) then
  begin
    SetError(Msg);
    Exit;
  end;
  Names := nil;
  Texts := nil;
  Result := TTransformObject.Create(TakeId, Spec.Kind, Sources, Suffix);
  case Spec.Kind of
    tkRotate:
    begin
      Result.UseRotate(Spec.Pivot);
      AddField(FIELD_ANGLE, Spec.Angle);
    end;
    tkMirror:
      if Spec.AxisEdge <> '' then
        Result.UseAxisEdge(Spec.AxisEdge)
      else if Spec.AxisB <> '' then
        Result.UseAxisPoints(Spec.AxisA, Spec.AxisB)
      else
      begin
        Result.UseAxisAngle(Spec.AxisA);
        AddField(FIELD_ANGLE, Spec.Angle);
      end;
    tkMove:
    begin
      Result.UseMove(Spec.Polar, Spec.Pivot);
      if Spec.Polar then
      begin
        AddField(FIELD_LENGTH, Spec.Length);
        AddField(FIELD_ANGLE, Spec.Angle);
      end
      else
      begin
        AddField(FIELD_DX, Spec.DX);
        AddField(FIELD_DY, Spec.DY);
      end;
      if Spec.Pivot <> '' then
        AddField(FIELD_ROTATE, Spec.Rotate);
    end;
  end;
  if not ParseFields(Result, Names, Texts) then
  begin
    GiveBackId(Result.Key);
    FreeAndNil(Result);
    Exit;
  end;
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
      CopyKey := TakeId;
      if Node is TPointObject then
      begin
        Point := TPointCopy.Create(CopyKey, Transform.Key, Key);
        Point.Name := FreeCopyName(Node.DisplayName, Transform.Suffix);
        // A copy keeps its source's marker, as a copied edge keeps its role
        if TPointObject(Node).Marker <> pmPlain then
        begin
          Point.SetMarker(TPointObject(Node).Marker);
          Point.Field(MARKER_SIZE_FIELD).ParseStored(Node.Field(MARKER_SIZE_FIELD).StoredText);
        end;
        AddObjectNode(Point);
        PointCopies.Add(Key, Point);
        QueueMarking(Point);
      end
      else
      begin
        Edge := TEdgeObject(Node);
        Copied := TEdgeCopy.Create(CopyKey, Transform.Key, Key, PointCopies[Edge.StartKey].Key, PointCopies[Edge.EndKey].Key, Edge.IsStraight, Edge.NamePrefix);
        Copied.Name := FreeCopyName(Edge.DisplayName, Transform.Suffix);
        Copied.NameIsDerived := False;
        Copied.Role := Edge.Role;
        AddObjectNode(Copied);
        QueueMarking(Copied);
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
begin
  Result := Assigned(FindObject(AName));
end;

type
  // Whether a name is taken by an object other than Own, so that an edge's
  // derived name can stay its own
  TOtherObjectName = class
  private
    FPattern: TPattern;
    FOwn: TDraftObject;
  public
    constructor Create(APattern: TPattern; AOwn: TDraftObject);
    function Taken(const AName: string): boolean;
  end;

constructor TOtherObjectName.Create(APattern: TPattern; AOwn: TDraftObject);
begin
  inherited Create;
  FPattern := APattern;
  FOwn := AOwn;
end;

function TOtherObjectName.Taken(const AName: string): boolean;
var
  Existing: TDraftObject;
begin
  Existing := FPattern.FindObject(AName);
  Result := Assigned(Existing) and (Existing <> FOwn);
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
  Result := NextFreeName(NEW_VARIABLE_BASE_NAME, @VariableNameTaken);
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
  Result := TVariable.Create(TakeId);
  if not ParseFields(Result, ['formula'], [FormulaText]) then
  begin
    GiveBackId(Result.Key);
    FreeAndNil(Result);
    Exit;
  end;
  // A new node cannot close a cycle: nothing refers to it yet
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
    PointName := NextAutoName(@ObjectNameTaken);
  end
  else if not CheckObjectName(PointName, nil, Msg) then
  begin
    GiveBackId(APoint.Key);
    FreeAndNil(APoint);
    Exit(SetError(Msg));
  end;
  if not ParseFields(APoint, Names, Texts) then
  begin
    GiveBackId(APoint.Key);
    FreeAndNil(APoint);
    Exit(False);
  end;
  APoint.Name := PointName;
  AddObjectNode(APoint);
  Result := True;
end;

function TPattern.AddFreePoint(const AName, XText, YText: string): TFreePoint;
begin
  Result := TFreePoint.Create(TakeId);
  if not AddPointObject(Result, AName, ['x', 'y'], [XText, YText]) then
    Result := nil;
end;

function TPattern.AddOffsetPoint(const AName, BaseId: string; Mode: TOffsetMode;
  const LengthOrDx, AngleOrDy: string): TOffsetPoint;
begin
  Result := nil;
  if not CheckPoint(BaseId) then
    Exit;
  Result := TOffsetPoint.Create(TakeId, BaseId, Mode);
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
  Result := TAlongEdgePoint.Create(TakeId, EdgeId, FromEnd, Mode);
  if not AddPointObject(Result, AName, ['value'], [Value]) then
    Result := nil;
end;

function TPattern.AddBetweenPoint(const AName, FirstId, LastId: string; Mode: TAlongMode; const Value: string): TBetweenPoint;
begin
  Result := nil;
  if not CheckPoint(FirstId) or not CheckPoint(LastId) then
    Exit;
  Result := TBetweenPoint.Create(TakeId, FirstId, LastId, Mode);
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
  Result := TRepeatObject.CreateBetween(TakeId, FirstId, LastId, IncludeEnds);
  if not AddPointObject(Result, AName, ['count'], [CountText]) then
    Result := nil;
end;

function TPattern.AddRepeatOnEdge(const AName, EdgeId, CountText: string; IncludeEnds: boolean): TRepeatObject;
begin
  Result := nil;
  if not CheckEdgeTarget(EdgeId) then
    Exit;
  Result := TRepeatObject.CreateOnEdge(TakeId, EdgeId, IncludeEnds);
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
  Used := TRepeatPoint(Node).Source.UseItem(TRepeatPoint(Node).Index, TakeId);
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
  Result := TIntersectPoint.Create(TakeId, EdgeAId, EdgeBId,
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
  Result := TCircleCirclePoint.Create(TakeId, CentreAId, CentreBId, Pick);
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
  Result := TCircleEdgePoint.Create(TakeId, CentreId, EdgeId, Extend, Pick);
  if not AddPointObject(Result, AName, ['radius'], [Radius]) then
    Result := nil;
end;

function TPattern.AddProjectPoint(const AName, SourceId, EdgeId: string;
  Direction: TProjectDirection; const Angle: string; Extend: boolean): TProjectPoint;
begin
  Result := nil;
  if not CheckPoint(SourceId) or not CheckEdgeTarget(EdgeId) then
    Exit;
  Result := TProjectPoint.Create(TakeId, SourceId, EdgeId, Direction, Extend);
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
  Others: TOtherObjectName;

// A repeat's point has brackets, which a name cannot: Btn[2] gives Btn_2
  function EndName(Node: TEvalNode): string;
  begin
    Result := StringReplace(StringReplace(Node.DisplayName, '[', '_', []), ']', '', []);
  end;

begin
  if AEdge.StartKey = AEdge.EndKey then
    Result := AEdge.NamePrefix + '_' + EndName(FindNode(AEdge.StartKey))
  else
    Result := AEdge.NamePrefix + '_' + EndName(FindNode(AEdge.StartKey)) + '_' + EndName(FindNode(AEdge.EndKey));
  Others := TOtherObjectName.Create(Self, AEdge);
  try
    Result := NextFreeName(Result, @Others.Taken);
  finally
    FreeAndNil(Others);
  end;
end;

function TPattern.AddEdgeObject(AEdge: TEdgeObject; const AName: string; ARole: TEdgeRole;
  const Names, Texts: array of string): boolean;
var
  Msg: string;
begin
  if not CheckPoint(AEdge.StartKey) or not CheckPoint(AEdge.EndKey) then
  begin
    GiveBackId(AEdge.Key);
    FreeAndNil(AEdge);
    Exit(False);
  end;
  if AName <> '' then
  begin
    if not CheckObjectName(AName, nil, Msg) then
    begin
      GiveBackId(AEdge.Key);
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
    GiveBackId(AEdge.Key);
    FreeAndNil(AEdge);
    Exit(False);
  end;
  AEdge.Role := ARole;
  AddObjectNode(AEdge);
  QueueMarking(AEdge);
  Result := True;
end;

function TPattern.AddLine(const StartId, EndId: string; Role: TEdgeRole;
  const AName: string): TLineObject;
begin
  Result := TLineObject.Create(TakeId, StartId, EndId);
  if not AddEdgeObject(Result, AName, Role, [], []) then
    Result := nil;
end;

function TPattern.AddCurve(const StartId, EndId, Angle1, Length1, Angle2, Length2: string;
  Role: TEdgeRole; const AName: string): TCurveObject;
begin
  Result := TCurveObject.Create(TakeId, StartId, EndId);
  if not AddEdgeObject(Result, AName, Role, ['angle1', 'length1', 'angle2', 'length2'],
    [Angle1, Length1, Angle2, Length2]) then
    Result := nil;
end;

function TPattern.AddCircle(const CentreId, Radius: string; Role: TEdgeRole; const AName: string): TCircleObject;
begin
  Result := TCircleObject.Create(TakeId, CentreId);
  if not AddEdgeObject(Result, AName, Role, ['radius'], [Radius]) then
    Result := nil;
end;

function TPattern.AddArc(const CentreId, Radius, Angle1, Angle2: string; Role: TEdgeRole; const AName: string): TArcObject;
begin
  Result := TArcObject.Create(TakeId, CentreId);
  if not AddEdgeObject(Result, AName, Role, ['radius', 'angle1', 'angle2'], [Radius, Angle1, Angle2]) then
    Result := nil;
end;

function TPattern.AddRectangle(const CornerId, Width, Height: string; Role: TEdgeRole; out Edges: TRectangleEdges): boolean;
var
  Corner: TEvalNode;
  Across, Below, Opposite: TOffsetPoint;
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
  Below := AddOffsetPoint('', CornerId, omCartesian, '0', Height);
  if not Assigned(Below) then
    Exit(False);
  Opposite := AddOffsetPoint('', Across.Key, omCartesian, '0', Below.DisplayName + '.y - ' + CornerName + '.y');
  if not Assigned(Opposite) then
    Exit(False);
  Edges[0] := AddLine(CornerId, Across.Key, Role);
  Edges[1] := AddLine(Across.Key, Opposite.Key, Role);
  Edges[2] := AddLine(Opposite.Key, Below.Key, Role);
  Edges[3] := AddLine(Below.Key, CornerId, Role);
  Result := Assigned(Edges[0]) and Assigned(Edges[1]) and Assigned(Edges[2]) and Assigned(Edges[3]);
end;

function TPattern.AddOffsetEdge(const EdgeId, Distance: string; Side: TOffsetSide; Role: TEdgeRole; const AName: string): TOffsetEdge;
var
  Run: TRunEdgeArray;
begin
  Run := nil;
  SetLength(Run, 1);
  Run[0].EdgeKey := EdgeId;
  Run[0].Reversed := False;
  Result := AddOffsetRun(Run, Distance, Side, Role, AName);
end;

function TPattern.AddOffsetRun(const Run: TRunEdgeArray; const Distance: string; Side: TOffsetSide; Role: TEdgeRole;
  const AName: string): TOffsetEdge;
var
  Item: TRunEdge;
  First, Last: TEdgeObject;
  StartKey, EndKey: string;
begin
  Result := nil;
  if Length(Run) = 0 then
  begin
    SetError(rsPatternNoRun);
    Exit;
  end;
  for Item in Run do
    if not CheckEdgeTarget(Item.EdgeKey) then
      Exit;
  First := TEdgeObject(FindNode(Run[0].EdgeKey));
  Last := TEdgeObject(FindNode(Run[High(Run)].EdgeKey));
  StartKey := First.StartKey;
  if Run[0].Reversed then
    StartKey := First.EndKey;
  EndKey := Last.EndKey;
  if Run[High(Run)].Reversed then
    EndKey := Last.StartKey;
  Result := TOffsetEdge.Create(TakeId, Run, StartKey, EndKey, Side);
  if not AddEdgeObject(Result, AName, Role, ['distance'], [Distance]) then
    Result := nil;
end;

// Grown both ways from the first edge, which the run follows the way it is
// drawn, so that left and right are the sides of that edge
function TPattern.ChainRun(const EdgeIds: TStringArray; out Run: TRunEdgeArray): boolean;
var
  Edges: array of TEdgeObject;
  Used: array of boolean;
  Other: integer;
  Id: string;
  Edge: TEdgeObject;
  RunStart, RunEnd: TVec2;
  Grew: boolean;

  function EdgeStart(AEdge: TEdgeObject): TVec2;
  begin
    Result := AEdge.PointAtLength(0);
  end;

  function EdgeEnd(AEdge: TEdgeObject): TVec2;
  begin
    Result := AEdge.PointAtLength(AEdge.Length);
  end;

  procedure Append(AEdge: TEdgeObject; Reversed: boolean; AtFront: boolean);
  var
    Item: TRunEdge;
  begin
    Item.EdgeKey := AEdge.Key;
    Item.Reversed := Reversed;
    if AtFront then
      System.Insert(Item, Run, 0)
    else
      System.Insert(Item, Run, Length(Run));
  end;

begin
  Run := nil;
  Edges := nil;
  for Id in EdgeIds do
  begin
    if not CheckEdgeTarget(Id) then
      Exit(False);
    Edge := TEdgeObject(FindNode(Id));
    if not Edge.HasResult or (Length(Edge.Segments) = 0) then
      Exit(SetError(Format(rsPatternRunNotComputed, [Edge.DisplayName])));
    System.Insert(Edge, Edges, Length(Edges));
  end;
  if Length(Edges) = 0 then
    Exit(SetError(rsPatternNoRun));
  Used := nil;
  SetLength(Used, Length(Edges));
  Append(Edges[0], False, False);
  Used[0] := True;
  RunStart := EdgeStart(Edges[0]);
  RunEnd := EdgeEnd(Edges[0]);
  repeat
    Grew := False;
    for Other := 0 to High(Edges) do
    begin
      if Used[Other] then
        Continue;
      if PointsNear(EdgeStart(Edges[Other]), RunEnd, CHAIN_TOLERANCE) then
      begin
        Append(Edges[Other], False, False);
        RunEnd := EdgeEnd(Edges[Other]);
      end
      else if PointsNear(EdgeEnd(Edges[Other]), RunEnd, CHAIN_TOLERANCE) then
      begin
        Append(Edges[Other], True, False);
        RunEnd := EdgeStart(Edges[Other]);
      end
      else if PointsNear(EdgeEnd(Edges[Other]), RunStart, CHAIN_TOLERANCE) then
      begin
        Append(Edges[Other], False, True);
        RunStart := EdgeStart(Edges[Other]);
      end
      else if PointsNear(EdgeStart(Edges[Other]), RunStart, CHAIN_TOLERANCE) then
      begin
        Append(Edges[Other], True, True);
        RunStart := EdgeEnd(Edges[Other]);
      end
      else
        Continue;
      Used[Other] := True;
      Grew := True;
    end;
  until not Grew;
  if Length(Run) <> Length(Edges) then
    Exit(SetError(rsPatternRunNotJoined));
  Result := True;
end;

function TPattern.PieceRun(Piece: TPieceObject; const EdgeIds: TStringArray; Inside: boolean; out Run: TRunEdgeArray;
  out Side: TOffsetSide): boolean;
var
  Id: string;
  Count, Index, First, Step: integer;
  Chosen: array of boolean;
begin
  Run := nil;
  Side := osLeft;
  Count := Length(Piece.Path);
  if Length(EdgeIds) = 0 then
    Exit(SetError(rsPatternNoRun));
  if (Piece.State <> esValid) or (Length(Piece.Outline) < 3) then
    Exit(SetError(Format(rsPatternRunNotComputed, [Piece.DisplayName])));
  Chosen := nil;
  SetLength(Chosen, Count);
  for Id in EdgeIds do
  begin
    Index := Piece.PathIndexOf(Id);
    if Index < 0 then
      Exit(SetError(Format(rsPatternNotInPiece, [FindNode(Id).DisplayName, Piece.DisplayName])));
    Chosen[Index] := True;
  end;
  // The stretch starts after a path edge that is not chosen; the whole path
  // starts at its first edge
  First := 0;
  for Index := 0 to Count - 1 do
    if Chosen[Index] and not Chosen[(Index + Count - 1) mod Count] then
    begin
      First := Index;
      Break;
    end;
  for Step := 0 to Count - 1 do
  begin
    Index := (First + Step) mod Count;
    if not Chosen[Index] then
      Break;
    System.Insert(Default(TRunEdge), Run, Length(Run));
    Run[High(Run)].EdgeKey := Piece.Path[Index].EdgeKey;
    Run[High(Run)].Reversed := Piece.Path[Index].Reversed;
  end;
  if Length(Run) <> Length(EdgeIds) then
    Exit(SetError(rsPatternRunNotJoined));
  // Going clockwise round the piece as seen on screen, its inside is on the right
  if IsClockwise(Piece.Outline) = Inside then
    Side := osRight
  else
    Side := osLeft;
  Result := True;
end;

function TPattern.AddRoundCorner(const EdgeAId, EdgeBId, Radius: string): TCornerArc;
var
  First, Second: TEdgeObject;
  Vertex: string;
  Starts, Ends, NearA, NearB: TSplitPart;
  TangentA, TangentB: TCornerPoint;

// A fold has to stay one straight edge, so a piece folded on it is refused
  function CheckEdge(Edge: TEdgeObject): boolean;
  var
    User: TEvalNode;
  begin
    if not Edge.IsStraight then
      Exit(SetError(Format(rsPatternCornerNotStraight, [Edge.DisplayName])));
    for User in UsersOf(Edge) do
      if (User is TPieceObject) and (TPieceObject(User).FoldEdgeKey = Edge.Key) then
        Exit(SetError(Format(rsPatternCornerOnFold, [Edge.DisplayName, User.DisplayName])));
    Result := True;
  end;

  // Splits the edge and returns the part away from the corner, and in Near
  // the part at it; the sharp end and the whole edge become construction.
  // Pieces and seams on the edge take both parts, as for any split.
  function Trim(Edge: TEdgeObject; const PointKey: string; out Near: TSplitPart): TEdgeObject;
  begin
    Result := nil;
    Near := nil;
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
  Result := TCornerArc.Create(TakeId, Vertex, EdgeAId, EdgeBId);
  if not AddEdgeObject(Result, '', First.Role, ['radius'], [Radius]) then
  begin
    Result := nil;
    Exit;
  end;
  TangentA := TCornerPoint.Create(TakeId, Result.Key, 1);
  if not AddPointObject(TangentA, '', [], []) then
    Exit(nil);
  TangentB := TCornerPoint.Create(TakeId, Result.Key, 2);
  if not AddPointObject(TangentB, '', [], []) then
    Exit(nil);
  Result.TrimmedA := Trim(First, TangentA.Key, NearA);
  Result.TrimmedB := Trim(Second, TangentB.Key, NearB);
  if Assigned(NearA) and Assigned(NearB) then
    FollowCorner(Result, NearA, NearB);
end;

// Pieces that took both parts at the corner, one after the other round the
// path, take the arc in their place, so the piece is rounded too. The arc runs
// from the first edge to the second, and is reversed when the path runs the
// other way. Notches on the parts cut away go to the arc's end beside them,
// and seams take the arc where they had the parts.
procedure TPattern.FollowCorner(Arc: TCornerArc; NearA, NearB: TSplitPart);
var
  Index, IndexA, IndexB, Count, Notch, SeamIndex: integer;
  Piece: TPieceObject;
  Moved: boolean;
begin
  Moved := False;
  for Index := 0 to FObjects.Count - 1 do
  begin
    if not (FObjects[Index] is TPieceObject) then
      Continue;
    Piece := TPieceObject(FObjects[Index]);
    IndexA := Piece.PathIndexOf(NearA.Key);
    IndexB := Piece.PathIndexOf(NearB.Key);
    Count := Length(Piece.Path);
    if (IndexA < 0) or (IndexB < 0) then
      Continue;
    if (IndexA + 1) mod Count = IndexB then
      Piece.JoinPathEdges(IndexA, Arc.Key, False)
    else if (IndexB + 1) mod Count = IndexA then
      Piece.JoinPathEdges(IndexB, Arc.Key, True)
    else
      Continue;
    for Notch := 0 to High(Piece.Notches) do
      if Piece.Notches[Notch].EdgeKey = NearA.Key then
      begin
        Piece.SetNotchEdge(Notch, Arc.Key);
        SetStoredFormula(Piece, Piece.NotchField(Notch), '0');
      end
      else if Piece.Notches[Notch].EdgeKey = NearB.Key then
      begin
        Piece.SetNotchEdge(Notch, Arc.Key);
        SetStoredFormula(Piece, Piece.NotchField(Notch), '{' + Arc.Key + '}.length');
      end;
    for SeamIndex := 0 to FObjects.Count - 1 do
      if FObjects[SeamIndex] is TSeamObject then
        TSeamObject(FObjects[SeamIndex]).JoinEntries(Piece.Key, NearA.Key, NearB.Key, Arc.Key);
    Moved := True;
  end;
  // A piece now reads the arc, which may come after it
  if Moved then
    OrderObjectsByInputs;
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
  Result := TCurvePathObject.Create(TakeId, NodeIds);
  if not AddEdgeObject(Result, AName, Role, Names, Texts) then
    Result := nil;
end;

function TPattern.SplitEdge(const EdgeId, PointId: string; out First, Second: TSplitPart): boolean;
var
  Source: TEdgeObject;

  function NewPart(APart: integer): TSplitPart;
  begin
    Result := NewSplitPart(TakeId, Source, PointId, APart);
    // Each part is its own edge: it gets a derived name and joins the pattern
    Result.Name := DerivedEdgeName(Result);
    Result.Role := Source.Role;
    AddObjectNode(Result);
    QueueMarking(Result);
  end;

begin
  First := nil;
  Second := nil;
  if not CheckEdgeTarget(EdgeId) or not CheckPoint(PointId) then
    Exit(False);
  Source := TEdgeObject(FindNode(EdgeId));
  First := NewPart(1);
  Second := NewPart(2);
  FollowSplit(Source, First, Second);
  Result := True;
end;

// Pieces that use the split edge take its parts instead, in the order their
// paths run, so a seam or notch can use part of what was one edge. A notch
// past the split point moves to the second part, measured from its start; a
// seam on the edge takes both parts. A piece folded on the edge keeps it, as
// a fold is one edge. Nothing changes while the parts are not valid.
procedure TPattern.FollowSplit(Source: TEdgeObject; First, Second: TSplitPart);
var
  Index, PathIndex, Notch, SeamIndex: integer;
  Piece: TPieceObject;
  Order: array of string;
  Position: double;
  Moved: boolean;
begin
  Evaluate;
  if (First.State <> esValid) or (Second.State <> esValid) then
    Exit;
  Moved := False;
  for Index := 0 to FObjects.Count - 1 do
  begin
    if not (FObjects[Index] is TPieceObject) then
      Continue;
    Piece := TPieceObject(FObjects[Index]);
    PathIndex := Piece.PathIndexOf(Source.Key);
    if (PathIndex < 0) or (Piece.FoldEdgeKey = Source.Key) then
      Continue;
    for Notch := 0 to High(Piece.Notches) do
      if (Piece.Notches[Notch].EdgeKey = Source.Key) and Piece.Field(Piece.NotchField(Notch)).Evaluate(FContext, Position) and
        (Position * FContext.LengthScale > First.Length + DEFAULT_TOLERANCE) then
      begin
        Piece.SetNotchEdge(Notch, Second.Key);
        SetStoredFormula(Piece, Piece.NotchField(Notch), '(' + Piece.Field(Piece.NotchField(Notch)).StoredText + ') - {' +
          First.Key + '}.length');
      end
      else if Piece.Notches[Notch].EdgeKey = Source.Key then
        Piece.SetNotchEdge(Notch, First.Key);
    if Piece.Path[PathIndex].Reversed then
      Order := [Second.Key, First.Key]
    else
      Order := [First.Key, Second.Key];
    Piece.SplitPathEdge(PathIndex, Order[0], Order[1]);
    for SeamIndex := 0 to FObjects.Count - 1 do
      if FObjects[SeamIndex] is TSeamObject then
        TSeamObject(FObjects[SeamIndex]).SplitEntry(Piece.Key, Source.Key, Order);
    Moved := True;
  end;
  // A piece now reads the parts, which come after it
  if Moved then
    OrderObjectsByInputs;
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
    PieceName := NextFreeName(NEW_PIECE_BASE_NAME, @ObjectNameTaken);
  end
  else if not CheckObjectName(PieceName, nil, Msg) then
  begin
    SetError(Msg);
    Exit;
  end;
  Result := TPieceObject.Create(TakeId, Path);
  // The first material's allowance stands in for the general default
  PieceAllowance := Allowance;
  if (Allowance = DEFAULT_PIECE_ALLOWANCE) and FMaterialSet[0].HasAllowance then
    PieceAllowance := MaterialAllowanceText(FMaterialSet[0])
  else if Allowance = DEFAULT_PIECE_ALLOWANCE then
    PieceAllowance := STARTING_LENGTHS[slPieceAllowance, FUnits];
  if not ParseFields(Result, [PIECE_ALLOWANCE_FIELD], [PieceAllowance]) then
  begin
    GiveBackId(Result.Key);
    FreeAndNil(Result);
    Exit;
  end;
  Result.Name := PieceName;
  Result.MaterialKey := FMaterialSet[0].Key;
  AddObjectNode(Result);
  SetGrainAngle(Result, DEFAULT_GRAIN_ANGLE);
  // Lines drawn before the piece was made join it now
  FAssignLoose := True;
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

// A file lists an object's inputs before it. Only seams and notes use a piece,
// and nothing uses them, so a piece that takes on a newer point can simply
// move to the end, with what uses it after it.
procedure TPattern.KeepInputsBefore(Piece: TPieceObject);
var
  Index: integer;
  InputKey: string;
begin
  FObjects.Move(FObjects.IndexOf(Piece), FObjects.Count - 1);
  for Index := FObjects.Count - 2 downto 0 do
    for InputKey in Objects[Index].InputKeys do
      if InputKey = Piece.Key then
      begin
        FObjects.Move(Index, FObjects.Count - 1);
        Break;
      end;
end;

function TPattern.SetGrainAngle(Piece: TPieceObject; const Text: string): boolean;
var
  OldKind: TGrainKind;
  OldStart, OldEnd: string;
begin
  OldKind := Piece.GrainKind;
  if OldKind = gkAngle then
    Exit(SetFormula(Piece, GRAIN_ANGLE_FIELD, Text));
  OldStart := Piece.GrainStartKey;
  OldEnd := Piece.GrainEndKey;
  Piece.SetGrainKind(gkAngle);
  Result := SetFormula(Piece, GRAIN_ANGLE_FIELD, Text);
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

function TPattern.CheckMarkerTarget(const Id: string): boolean;
var
  Node: TEvalNode;
begin
  Node := FindNode(Id);
  if Node is TRepeatObject then
    Exit(True);
  if not CheckPoint(Id) then
    Exit(False);
  // A repeat's points share the repeat's marker
  if Node is TRepeatPoint then
    Exit(SetError(Format(rsPatternMarkerOnRepeat, [Node.DisplayName, TRepeatPoint(Node).Source.DisplayName])));
  Result := True;
end;

function TPattern.SetMarker(const Id: string; AMarker: TPointMarker; const Size: string): boolean;
var
  Target: TDraftObject;
  OldMarker: TPointMarker;
  OldSize: string;
begin
  if not CheckMarkerTarget(Id) then
    Exit(False);
  Target := TDraftObject(FindNode(Id));
  OldMarker := Target.Marker;
  OldSize := '';
  if OldMarker <> pmPlain then
    OldSize := Target.Field(MARKER_SIZE_FIELD).StoredText;
  Target.SetMarker(AMarker);
  if AMarker = pmPlain then
  begin
    DetachMarking(Id);
    Exit(True);
  end;
  if Size <> '' then
    Result := SetFormula(Target, MARKER_SIZE_FIELD, Size)
  else if OldMarker = pmPlain then
    Result := SetFormula(Target, MARKER_SIZE_FIELD, STARTING_LENGTHS[MARKER_STARTING_LENGTHS[AMarker], FUnits])
  else
    Result := True;
  if not Result then
  begin
    Target.SetMarker(OldMarker);
    if OldMarker <> pmPlain then
      SetStoredFormula(Target, MARKER_SIZE_FIELD, OldSize);
    Exit;
  end;
  if OldMarker = pmPlain then
    QueueMarking(Target);
end;

function TPattern.AddPointMarking(Piece: TPieceObject; const Id: string): boolean;
var
  Target: TDraftObject;
begin
  if not CheckMarkerTarget(Id) then
    Exit(False);
  Target := TDraftObject(FindNode(Id));
  if Target.Marker = pmPlain then
    Exit(SetError(Format(rsPatternNoMarker, [Target.DisplayName])));
  if Piece.PointMarkingOf(Id) >= 0 then
    Exit(SetError(Format(rsPatternLineMarked, [Target.DisplayName, Piece.DisplayName])));
  Piece.AddMarking(mkPoint, Id, '');
  KeepInputsBefore(Piece);
  Result := True;
end;

function TPattern.AddLineMarking(Piece: TPieceObject; const EdgeId: string): boolean;
var
  Edge: TEdgeObject;
begin
  if not CheckEdgeTarget(EdgeId) then
    Exit(False);
  Edge := TEdgeObject(FindNode(EdgeId));
  if not (Edge.Role in MARKING_ROLES) then
    Exit(SetError(Format(rsPatternNotMarkingLine, [Edge.DisplayName])));
  if Piece.PathIndexOf(EdgeId) >= 0 then
    Exit(SetError(Format(rsPatternLineIsOutline, [Edge.DisplayName, Piece.DisplayName])));
  if Piece.LineMarkingOf(EdgeId) >= 0 then
    Exit(SetError(Format(rsPatternLineMarked, [Edge.DisplayName, Piece.DisplayName])));
  Piece.AddMarking(mkLine, '', EdgeId);
  KeepInputsBefore(Piece);
  Result := True;
end;

function TPattern.SetEdgeRole(Edge: TEdgeObject; Role: TEdgeRole): boolean;
var
  WasMarking: boolean;
begin
  WasMarking := Edge.Role in MARKING_ROLES;
  Edge.Role := Role;
  if not (Role in MARKING_ROLES) then
    DetachMarking(Edge.Key)
  else if not WasMarking then
    QueueMarking(Edge);
  Result := True;
end;

function TPattern.Refuse(const Msg: string): boolean;
begin
  Result := SetError(Msg);
end;

function TPattern.IsHidden(DraftObject: TDraftObject): boolean;
begin
  Result := ((DraftObject is TEdgeObject) and (TEdgeObject(DraftObject).Role in View.HiddenRoles)) or
    ((DraftObject is TNoteObject) and View.HideAnnotations);
end;

function TPattern.IsMarking(DraftObject: TDraftObject): boolean;
begin
  if DraftObject is TEdgeObject then
    Result := TEdgeObject(DraftObject).Role in MARKING_ROLES
  else
    Result := ((DraftObject is TPointObject) or (DraftObject is TRepeatObject)) and (DraftObject.Marker <> pmPlain);
end;

procedure TPattern.QueueMarking(DraftObject: TDraftObject);
begin
  if IsMarking(DraftObject) then
    System.Insert(DraftObject.Key, FPendingMarkings, Length(FPendingMarkings));
end;

function TPattern.LiesInside(DraftObject: TDraftObject; Piece: TPieceObject): boolean;
var
  Index, Inside: integer;
  Edge: TEdgeObject;
  Positions: TVec2Array;
begin
  if not DraftObject.HasResult or (Piece.State <> esValid) or (Length(Piece.CutLine) < 3) then
    Exit(False);
  Positions := nil;
  if DraftObject is TEdgeObject then
  begin
    Edge := TEdgeObject(DraftObject);
    SetLength(Positions, INSIDE_SAMPLES + 1);
    for Index := 0 to INSIDE_SAMPLES do
      Positions[Index] := Edge.PointAtLength(Edge.Length * Index / INSIDE_SAMPLES);
  end
  else
    Positions := MarkerPositions(DraftObject);
  Inside := 0;
  for Index := 0 to High(Positions) do
    if PointInPolygon(Positions[Index], Piece.CutLine) then
      Inc(Inside);
  Result := 2 * Inside > Length(Positions);
end;

function TPattern.PiecesWithMarking(const Key: string): TPieceObjectArray;
var
  DraftObject: TDraftObject;
begin
  Result := nil;
  for DraftObject in FObjects do
    if (DraftObject is TPieceObject) and ((TPieceObject(DraftObject).LineMarkingOf(Key) >= 0) or
      (TPieceObject(DraftObject).PointMarkingOf(Key) >= 0)) then
      System.Insert(TPieceObject(DraftObject), Result, Length(Result));
end;

procedure TPattern.DetachMarking(const Key: string);
var
  DraftObject: TDraftObject;
  Piece: TPieceObject;
  Index: integer;
begin
  for DraftObject in FObjects do
    if DraftObject is TPieceObject then
    begin
      Piece := TPieceObject(DraftObject);
      Index := Piece.LineMarkingOf(Key);
      while Index >= 0 do
      begin
        Piece.RemoveMarking(Index);
        Index := Piece.LineMarkingOf(Key);
      end;
      Index := Piece.PointMarkingOf(Key);
      while Index >= 0 do
      begin
        Piece.RemoveMarking(Index);
        Index := Piece.PointMarkingOf(Key);
      end;
    end;
end;

// A marking inside several pieces goes to all of them; one inside none
// waits for a piece, as a new piece takes the loose markings inside it
function TPattern.AssignPendingMarkings: boolean;
var
  Keys: TStringArray;
  Key: string;
  DraftObject, Other: TDraftObject;
  Piece: TPieceObject;
  Changed: TPieceObjectArray;
begin
  Keys := FPendingMarkings;
  if FAssignLoose then
    for DraftObject in FObjects do
      if IsMarking(DraftObject) and (Length(PiecesWithMarking(DraftObject.Key)) = 0) then
        System.Insert(DraftObject.Key, Keys, Length(Keys));
  FPendingMarkings := nil;
  FAssignLoose := False;
  Changed := nil;
  for Key in Keys do
  begin
    if not (FindNode(Key) is TDraftObject) then
      Continue;
    DraftObject := TDraftObject(FindNode(Key));
    if not IsMarking(DraftObject) then
      Continue;
    for Other in FObjects do
      if Other is TPieceObject then
      begin
        Piece := TPieceObject(Other);
        if (Piece.PathIndexOf(Key) >= 0) or (Piece.LineMarkingOf(Key) >= 0) or (Piece.PointMarkingOf(Key) >= 0) or not LiesInside(DraftObject, Piece) then
          Continue;
        if DraftObject is TEdgeObject then
          Piece.AddMarking(mkLine, '', Key)
        else
          Piece.AddMarking(mkPoint, Key, '');
        System.Insert(Piece, Changed, Length(Changed));
      end;
  end;
  // Reordering the list for the file waits until it is not being walked
  for Piece in Changed do
    KeepInputsBefore(Piece);
  Result := Length(Changed) > 0;
end;

function TPattern.AddStitchMarking(Piece: TPieceObject; const EdgeId, Spacing, Size: string): boolean;
var
  Index: integer;
begin
  if not CheckEdgeTarget(EdgeId) then
    Exit(False);
  Index := Piece.AddMarking(mkStitchHoles, '', EdgeId);
  KeepInputsBefore(Piece);
  Result := SetFormula(Piece, Piece.MarkingField(Index, MARKING_SPACING_FIELD), Spacing) and SetFormula(Piece,
    Piece.MarkingField(Index, MARKING_SIZE_FIELD), Size);
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
  Msg, SeamName, SeamTolerance: string;
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
    SeamName := NextFreeName(NEW_SEAM_BASE_NAME, @ObjectNameTaken);
  end
  else if not CheckObjectName(SeamName, nil, Msg) then
  begin
    SetError(Msg);
    Exit;
  end;
  Result := TSeamObject.Create(TakeId, SideA, SideB);
  SeamTolerance := Tolerance;
  if SeamTolerance = DEFAULT_SEAM_TOLERANCE then
    SeamTolerance := STARTING_LENGTHS[slSeamTolerance, FUnits];
  if not ParseFields(Result, [SEAM_EASE_FIELD, SEAM_TOLERANCE_FIELD], [Ease, SeamTolerance]) then
  begin
    GiveBackId(Result.Key);
    FreeAndNil(Result);
    Exit;
  end;
  Result.Name := SeamName;
  AddObjectNode(Result);
end;

// The key to store: a repeat's point takes an ID on first use
function TPattern.CheckNoteAnchor(Anchor: TNoteAnchor; const AnchorKey: string; out Key: string): boolean;
var
  Node: TEvalNode;
  KindText: string;
  Fits: boolean;
begin
  Key := '';
  if Anchor = naFree then
    Exit(True);
  Node := FindNode(AnchorKey);
  if not Assigned(Node) then
    Exit(SetError(Format(rsPatternUnknownObject, [AnchorKey])));
  case Anchor of
    naPoint:
    begin
      Fits := Node is TPointObject;
      KindText := rsPatternNoteAnchorPoint;
    end;
    naEdge:
    begin
      Fits := Node is TEdgeObject;
      KindText := rsPatternNoteAnchorEdge;
    end;
    else
    begin
      Fits := Node is TPieceObject;
      KindText := rsPatternNoteAnchorPiece;
    end;
  end;
  if not Fits then
    Exit(SetError(Format(rsPatternNoteAnchor, [Node.DisplayName, KindText])));
  Key := AnchorKey;
  if Anchor = naPoint then
    Key := UsePoint(AnchorKey);
  Result := True;
end;

function TPattern.AddNote(const AName, AText: string; Anchor: TNoteAnchor; const AnchorKey, Position, DxOrX, DyOrY: string;
  ASize: double; APrint: boolean; ALeader: TNoteLeader): TNoteObject;
var
  Msg, NoteName, Key: string;
begin
  Result := nil;
  if (Anchor = naFree) and (ALeader <> nlNone) then
  begin
    SetError(rsPatternCalloutFree);
    Exit;
  end;
  if not CheckNoteAnchor(Anchor, AnchorKey, Key) then
    Exit;
  if (ASize <= 0) or (ASize > MAX_NOTE_SIZE) then
  begin
    SetError(Format(rsPatternNoteSize, [MAX_NOTE_SIZE]));
    Exit;
  end;
  NoteName := AName;
  if NoteName = '' then
  begin
    NoteName := NextFreeName(NEW_NOTE_BASE_NAME, @ObjectNameTaken);
  end
  else if not CheckObjectName(NoteName, nil, Msg) then
  begin
    SetError(Msg);
    Exit;
  end;
  Result := TNoteObject.Create(TakeId, Anchor, Key);
  if ((Anchor = naFree) and not ParseFields(Result, [NOTE_X_FIELD, NOTE_Y_FIELD], [DxOrX, DyOrY])) or
    ((Anchor = naEdge) and not ParseFields(Result, [NOTE_POSITION_FIELD], [Position])) or
    ((Anchor <> naFree) and not ParseFields(Result, [NOTE_DX_FIELD, NOTE_DY_FIELD], [DxOrX, DyOrY])) or not SetNoteText(Result, AText) then
  begin
    GiveBackId(Result.Key);
    FreeAndNil(Result);
    Exit;
  end;
  Result.Name := NoteName;
  Result.Size := ASize;
  Result.Print := APrint;
  Result.Leader := ALeader;
  AddObjectNode(Result);
end;

function TPattern.SetNoteText(Note: TNoteObject; const AText: string): boolean;
var
  Template: string;
  Expressions: TStringArray;
  Formulas: array of TFormula;
  ErrorPos, Index, Built: integer;
  Ref: TFormulaReference;
begin
  if not SplitDraftValues(AText, Template, Expressions, ErrorPos) then
    Exit(SetError(rsNoteUnclosed, NOTE_TEXT_FIELD, ErrorPos));
  Formulas := nil;
  SetLength(Formulas, Length(Expressions));
  Built := 0;
  try
    for Index := 0 to High(Expressions) do
    begin
      Formulas[Index] := TFormula.Create;
      Built := Index + 1;
      if not Formulas[Index].Parse(Expressions[Index], ResolverFor(Note)) then
        Exit(SetError(Formulas[Index].ErrorMessage, NOTE_TEXT_FIELD));
      // Nothing reads a note, so only reading itself could go round
      for Ref in Formulas[Index].References do
        if ReferenceKey(Ref) = Note.Key then
          Exit(SetError(Format(rsPatternUsesItself, [Note.DisplayName]), NOTE_TEXT_FIELD));
    end;
    Note.SetValues(Template, Formulas);
    Built := 0;
    Result := True;
  finally
    for Index := 0 to Built - 1 do
      FreeAndNil(Formulas[Index]);
  end;
end;

function TPattern.SetNoteSize(Note: TNoteObject; ASize: double): boolean;
begin
  if (ASize <= 0) or (ASize > MAX_NOTE_SIZE) then
    Exit(SetError(Format(rsPatternNoteSize, [MAX_NOTE_SIZE])));
  Note.Size := ASize;
  Result := True;
end;

procedure TPattern.SetNotePrint(Note: TNoteObject; APrint: boolean);
begin
  Note.Print := APrint;
end;

function TPattern.SetNoteLeader(Note: TNoteObject; ALeader: TNoteLeader): boolean;
begin
  if (Note.Anchor = naFree) and (ALeader <> nlNone) then
    Exit(SetError(rsPatternCalloutFree));
  Note.Leader := ALeader;
  Result := True;
end;

procedure TPattern.SetNoteAlign(Note: TNoteObject; AAlign: TTextAlign);
begin
  Note.Align := AAlign;
end;

procedure TPattern.SetNoteBoxed(Note: TNoteObject; ABoxed: boolean);
begin
  Note.Boxed := ABoxed;
end;

// Worked out from the anchor's last good place, as the note's own is
function TPattern.NoteAnchorPlace(Anchor: TNoteAnchor; const Key: string; Ratio: double): TVec2;
var
  Node: TEvalNode;
begin
  Node := FindNode(Key);
  case Anchor of
    naPoint: Result := TPointObject(Node).Position;
    naEdge: Result := TEdgeObject(Node).PointAtLength(Ratio * TEdgeObject(Node).Length);
    naPiece: Result := TPieceObject(Node).Middle;
    else
      Result := Vec2(0, 0);
  end;
end;

function TPattern.SetNoteAnchor(Note: TNoteObject; Anchor: TNoteAnchor; const AnchorKey: string; Ratio: double): boolean;
var
  Key, RatioText: string;
  Box, Base: TVec2;
begin
  if (Anchor = naFree) and (Note.Leader <> nlNone) then
    Exit(SetError(rsPatternCalloutFree));
  if (Anchor = naEdge) and ((Ratio < 0) or (Ratio > 1)) then
    Exit(SetError(Format(rsDraftRatioRange, [FormatFloat('0.###', Ratio)])));
  if not CheckNoteAnchor(Anchor, AnchorKey, Key) then
    Exit(False);
  Box := Note.Position;
  RatioText := RoundedNumberText(Ratio, NOTE_RATIO_DECIMALS);
  Base := Vec2(0, 0);
  if Anchor <> naFree then
    Base := NoteAnchorPlace(Anchor, Key, RoundTo(Ratio, -NOTE_RATIO_DECIMALS));
  Note.Reanchor(Anchor, Key);
  if (Anchor = naEdge) and not ParseFields(Note, [NOTE_POSITION_FIELD], [RatioText]) then
    Exit(False);
  Result := ParseFields(Note, Note.PlaceFields, [RoundLengthFormulaText(Box.X - Base.X, FUnits),
    RoundLengthFormulaText(Box.Y - Base.Y, FUnits)]);
end;

function TPattern.MakeNoteFree(Note: TNoteObject): boolean;
var
  At: TVec2;
begin
  if Note.Anchor = naFree then
    Exit(SetError(Format(rsPatternNoteIsFree, [Note.DisplayName])));
  At := Note.Position;
  Note.MakeFree;
  Result := ParseFields(Note, [NOTE_X_FIELD, NOTE_Y_FIELD], [RoundLengthFormulaText(At.X, FUnits),
    RoundLengthFormulaText(At.Y, FUnits)]);
end;

function TPattern.NotePieces(Note: TNoteObject): TPieceObjectArray;
var
  Index: integer;
  Piece: TPieceObject;
  Place: TVec2;

  function UsesAnchor: boolean;
  var
    Entry: TPieceEdge;
    Edge: TEvalNode;
    Notch: TPieceNotch;
    Marking: TPieceMarking;
  begin
    case Note.Anchor of
      naPiece: Exit(Note.AnchorKey = Piece.Key);
      naFree: Exit(False);
    end;
    for Entry in Piece.Path do
    begin
      if Entry.EdgeKey = Note.AnchorKey then
        Exit(True);
      Edge := FindNode(Entry.EdgeKey);
      if (Edge is TEdgeObject) and ((TEdgeObject(Edge).StartKey = Note.AnchorKey) or (TEdgeObject(Edge).EndKey = Note.AnchorKey)) then
        Exit(True);
    end;
    for Notch in Piece.Notches do
      if Notch.PointKey = Note.AnchorKey then
        Exit(True);
    for Marking in Piece.Markings do
      if (Marking.PointKey = Note.AnchorKey) or (Marking.EdgeKey = Note.AnchorKey) then
        Exit(True);
    Result := False;
  end;

begin
  Result := nil;
  Place := Note.Position;
  if Note.Leader <> nlNone then
    Place := Note.AnchorPosition;
  for Index := 0 to FObjects.Count - 1 do
    if Objects[Index] is TPieceObject then
    begin
      Piece := TPieceObject(Objects[Index]);
      if UsesAnchor or (Note.HasResult and Piece.HasResult and (Length(Piece.CutLine) > 2) and PointInPolygon(Place, Piece.CutLine)) then
        Insert(Piece, Result, System.Length(Result));
    end;
end;

function TPattern.PieceNotes(Piece: TPieceObject): TNoteObjectArray;
var
  Index: integer;
  Note: TNoteObject;
  Candidate: TPieceObject;
begin
  Result := nil;
  for Index := 0 to FObjects.Count - 1 do
    if (Objects[Index] is TNoteObject) and TNoteObject(Objects[Index]).Print then
    begin
      Note := TNoteObject(Objects[Index]);
      for Candidate in NotePieces(Note) do
        if Candidate = Piece then
        begin
          Insert(Note, Result, System.Length(Result));
          Break;
        end;
    end;
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

// Changing type is in Sloper.Core.TypeChange, merging and breaking points in
// Sloper.Core.PointMerge

function TPattern.ConvertToLine(Edge: TEdgeObject): TLineObject;
begin
  Result := Sloper.Core.TypeChange.ConvertToLine(Self, Edge);
end;

function TPattern.ConvertToCurve(Edge: TEdgeObject): TCurveObject;
begin
  Result := Sloper.Core.TypeChange.ConvertToCurve(Self, Edge);
end;

function TPattern.ExtendCurve(Edge: TEdgeObject; const PointId: string): TCurvePathObject;
begin
  Result := Sloper.Core.TypeChange.ExtendCurve(Self, Edge, PointId);
end;

function TPattern.ConvertToFree(Point: TPointObject; const XText, YText: string): TFreePoint;
begin
  Result := Sloper.Core.TypeChange.ConvertToFree(Self, Point, XText, YText);
end;

function TPattern.ConvertToBetween(Point: TPointObject; const FirstId, LastId: string; Mode: TAlongMode; const Value: string): TBetweenPoint;
begin
  Result := Sloper.Core.TypeChange.ConvertToBetween(Self, Point, FirstId, LastId, Mode, Value);
end;

function TPattern.ConvertToAlongEdge(Point: TPointObject; const EdgeId: string; FromEnd: boolean; Mode: TAlongMode; const Value: string): TAlongEdgePoint;
begin
  Result := Sloper.Core.TypeChange.ConvertToAlongEdge(Self, Point, EdgeId, FromEnd, Mode, Value);
end;

function TPattern.MergePoints(const Keys: array of string): TPointObject;
begin
  Result := Sloper.Core.PointMerge.MergePoints(Self, Keys);
end;

function TPattern.BreakPoint(Point: TPointObject): TPointObjectArray;
begin
  Result := Sloper.Core.PointMerge.BreakPoint(Self, Point);
end;

procedure TPattern.ForgetGraph;
begin
  FEvaluator.Rebuild(nil, FContext);
end;

procedure TPattern.QueueMarkings(const Keys: array of string);
var
  Key: string;
begin
  for Key in Keys do
    if FindNode(Key) is TDraftObject then
      QueueMarking(TDraftObject(FindNode(Key)));
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
  // A piece that only prints the line lets it go with it
  Names := '';
  for User in Users do
    if not ((User is TPieceObject) and TPieceObject(User).UsesOnlyAsMarking(Node.Key)) then
    begin
      if Names <> '' then
        Names := Names + ', ';
      Names := Names + User.DisplayName;
    end;
  if Names <> '' then
    Exit(SetError(Format(rsPatternInUse, [Node.DisplayName, Names])));
  DetachMarking(Node.Key);
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
var
  Formula: TFormula;
begin
  Formula := Node.Field(AField);
  if not Assigned(Formula) then
    Exit('');
  Result := Formula.DisplayText(ResolverFor(Node));
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
  // Where a new marking line lies is only known once it is computed
  if AssignPendingMarkings then
  begin
    FEvaluator.Rebuild(AllNodes, FContext);
    FEvaluator.Run(FContext);
  end;
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
