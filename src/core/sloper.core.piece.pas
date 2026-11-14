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

// Pieces: a closed path of edge references with a seam allowance. Only the
// references and formulas are stored, so a piece follows every change to its
// edges; its outline and cutting line are computed. No LCL dependency.
unit Sloper.Core.Piece;

{$mode ObjFPC}{$H+}

interface

uses
  SysUtils, Sloper.Core.EvalTypes, Sloper.Core.Evaluator, Sloper.Core.Geometry, Sloper.Core.Draft, Sloper.Core.SeamAllowance,
  Sloper.Core.Materials;

const
  // The formula field of the seam allowance, and its member in pattern files
  PIECE_ALLOWANCE_FIELD = 'allowance';
  // Asks AddPiece for the starting allowance: the first material's, or the
  // pattern unit's (StartingLengths)
  DEFAULT_PIECE_ALLOWANCE = '';
  GRAIN_ANGLE_FIELD = 'grainline.angle';
  // As written in pattern files and the Automation API
  DEFAULT_GRAIN_ANGLE = '90';
  // A point this close (in mm) to a piece's seam line can carry a notch
  NOTCH_POINT_TOLERANCE = 0.05;
  // The second part of a marking's fields, after "markingN."
  MARKING_SPACING_FIELD = 'spacing';
  MARKING_SIZE_FIELD = 'size';
  // As written in pattern files and the Automation API
  MARKING_KIND_NAMES: array[0..2] of string = ('point', 'line', 'stitch');
  // Ends of neighbouring edges this close (in mm) count as joined, so formula
  // rounding cannot open a piece
  PIECE_JOIN_TOLERANCE = 0.01;

type

  TPieceEdge = record
    EdgeKey: string;
    // True when the path runs along the edge from its end to its start
    Reversed: boolean;
  end;

  TPiecePath = array of TPieceEdge;

  // gkAngle lays the grainline through the piece's middle at a formula angle;
  // gkPoints runs it between two points
  TGrainKind = (gkNone, gkAngle, gkPoints);

  // A piece as it lies on material, its grainline along the length (see
  // TPieceObject.GrainShape)
  TGrainShape = record
    // The cutting line as drafted: for a piece on a fold, the half laid
    // against the material's fold
    Half: TVec2Array;
    // Half and, on a fold, its mirror image: the whole piece's points, for
    // its extent
    Whole: TVec2Array;
    // On a fold that runs along the grain, so it can go on the material's fold
    FoldAlongGrain: boolean;
  end;

  // On a point, or at the formula "notchN.position": mm from the edge's start
  TPieceNotch = record
    PointKey, EdgeKey: string;
  end;

  TPieceNotchArray = array of TPieceNotch;

  // A notch as cut: from the cutting line in towards the seam line
  TNotchMark = record
    Seam, Cut, Tip: TVec2;
  end;

  TNotchMarkArray = array of TNotchMark;

  // mkPoint is a point or repeat with a marker, which has the marker's size.
  // The others are along an edge: mkLine is a marking line, drawn in its
  // edge's role, and mkStitchHoles has a spacing and a hole size.
  TMarkingKind = (mkPoint, mkLine, mkStitchHoles);

  TPieceMarking = record
    Kind: TMarkingKind;
    PointKey, EdgeKey: string;
  end;

  TPieceMarkingArray = array of TPieceMarking;

  // A marking worked out: Line for a line, Holes for holes of diameter
  // HoleSize, and Centres for buttons and match dots of that size
  TMarkingMark = record
    Kind: TMarkingKind;
    // How an mkLine is drawn: its edge's marking role
    Role: TEdgeRole;
    // An mkPoint's marker
    Marker: TPointMarker;
    Line: TVec2Array;
    Holes: TVec2Array;
    Centres: TVec2Array;
    HoleSize: double;
  end;

  TMarkingMarkArray = array of TMarkingMark;

  // The default seam allowance is the field "allowance"; an edge with its own
  // has a field such as "edge2.allowance", which exists only while it does
  TPieceObject = class(TDraftObject)
  private
    FPath: TPiecePath;
    FOutline: TVec2Array;
    FCutLine: TVec2Array;
    FGrainKind: TGrainKind;
    FGrainStartKey, FGrainEndKey: string;
    FGrainline: TLine2;
    FNotches: TPieceNotchArray;
    FNotchMarks: TNotchMarkArray;
    FMarkings: TPieceMarkingArray;
    FMarkingMarks: TMarkingMarkArray;
    FCutCount: integer;
    FMirrored: boolean;
    FFoldEdgeKey: string;
    FFoldLine: TLine2;
    FFoldInwards: double;
    FMaterialKey: string;
    FFillColor: string;
    FFillStyle: TPieceFillStyle;
    function BuildOutline(Context: TEvalContext; DefaultWidth: double; out Outline: TVec2Array; out Widths, EdgeWidths: TDoubleArray): TEvalState;
    function ComputeGrainline(Context: TEvalContext; const Points: TVec2Array; out Line: TLine2): TEvalState;
    function ComputeNotch(Context: TEvalContext; Index: integer; const EdgeWidths: TDoubleArray; Anticlockwise: boolean;
      out Mark: TNotchMark): TEvalState;
    procedure ComputeFold(Context: TEvalContext; Anticlockwise: boolean; out Line: TLine2; out Inwards: double);
    function ComputeMarking(Context: TEvalContext; Index: integer; const Cut: TVec2Array; const Fold: TLine2; out Mark: TMarkingMark): TEvalState;
    function OutwardAngle(Edge: TEdgeObject; PathIndex: integer; Position: double; Anticlockwise: boolean): double;
    function LocateNotch(Context: TEvalContext; Index: integer; out PathIndex: integer; out Position: double): TEvalState;
  public
    constructor Create(const AKey: string; const APath: TPiecePath);
    function InputKeys: TStringArray; override;
    procedure RedirectPoint(const OldKey, NewKey: string); override;
    function TypeName: string; override;
    function HasProperty(const Prop: string): boolean; override;
    function PropertyValue(const Prop: string): double; override;
    function Compute(Context: TEvalContext): TEvalState; override;
    function FieldUnitKind(const AName: string): TFieldUnitKind; override;
    // Index in the path of the edge with this key, or -1
    function PathIndexOf(const EdgeKey: string): integer;
    function OverrideField(PathIndex: integer): string;
    function HasOverride(PathIndex: integer): boolean;
    // The path index of an override field (edge2.allowance is 1), or -1
    function OverridePathIndex(const FieldName: string): integer;
    procedure AddOverride(PathIndex: integer);
    procedure RemoveOverride(PathIndex: integer);
    // The edge at PathIndex becomes two, in the order the path runs: an
    // override it had goes to both, and later overrides move up one
    procedure SplitPathEdge(PathIndex: integer; const FirstKey, SecondKey: string);
    // The edge at PathIndex and the next one round the path become one: an
    // override either had goes to it, and later overrides move down one
    procedure JoinPathEdges(PathIndex: integer; const EdgeKey: string; Reversed: boolean);
    procedure SetNotchEdge(Index: integer; const AEdgeKey: string);
    // Clears the old grainline's field, if any. gkAngle adds its field;
    // gkPoints takes the two point keys.
    procedure SetGrainKind(AKind: TGrainKind; const AStartKey: string = ''; const AEndKey: string = '');
    // A new notch's index. An edge notch has the field NotchField(Index).
    function AddNotch(const APointKey, AEdgeKey: string): integer;
    procedure RemoveNotch(Index: integer);
    function NotchField(Index: integer): string;
    // A new marking's index; its fields follow from its kind
    function AddMarking(AKind: TMarkingKind; const APointKey, AEdgeKey: string): integer;
    procedure RemoveMarking(Index: integer);
    function MarkingField(Index: integer; const Part: string): string;
    // The mkLine marking along this edge, or -1
    function LineMarkingOf(const AEdgeKey: string): integer;
    // The mkPoint marking of this point or repeat, or -1
    function PointMarkingOf(const AKey: string): integer;
    // True when the piece reads the object only as marking lines or a
    // marked point, so deleting it or changing its role or marker can simply
    // take them off
    function UsesOnlyAsMarking(const AKey: string): boolean;
    // Its holes, buttons and match dots as short strokes, for drawing;
    // marking lines are drawn as their edges, in their role's style
    function MarkingStrokes: TLine2Array;
    function Area: double;
    function Perimeter: double;
    // The middle of the outline's extent
    function Middle: TVec2;
    // The grainline's shaft and the strokes of an arrowhead at each end
    function GrainArrow: TLine2Array;
    // The fold line's bracket: a line in from the fold with an arrow down to
    // it at each end. Empty when the piece is not cut on a fold.
    function FoldArrow: TLine2Array;
    // The name with how to cut it: "Front, cut 2 mirrored"
    // Whole leaves out "on fold", for a piece opened out to cut flat
    function CutCaption(Whole: boolean = False): string;
    property Path: TPiecePath read FPath;
    // Last good seam line, closed without repeating its first point
    property Outline: TVec2Array read FOutline;
    // Last good cutting line, clockwise, closed without repeating its first point
    property CutLine: TVec2Array read FCutLine;
    property GrainKind: TGrainKind read FGrainKind;
    property GrainStartKey: string read FGrainStartKey;
    property GrainEndKey: string read FGrainEndKey;
    // Last good grainline
    property Grainline: TLine2 read FGrainline;
    property Notches: TPieceNotchArray read FNotches;
    // Last good marks, one per notch
    property NotchMarks: TNotchMarkArray read FNotchMarks;
    property Markings: TPieceMarkingArray read FMarkings;
    // Last good marks, one per marking
    property MarkingMarks: TMarkingMarkArray read FMarkingMarks;
    // How many to cut, at least 1
    property CutCount: integer read FCutCount write FCutCount;
    // Copies after the first are cut mirrored, as a left and a right
    property Mirrored: boolean read FMirrored write FMirrored;
    // The edge the piece is cut on the fold along, or '' when none. It has no
    // seam allowance, whatever its allowance says.
    property FoldEdgeKey: string read FFoldEdgeKey write FFoldEdgeKey;
    // Last good line of the fold, along its edge
    property FoldLine: TLine2 read FFoldLine;
    function OnFold: boolean;
    // The cutting line turned so the grainline points up, as the piece lies
    // on material with its grain along the length; as drawn with no grainline
    function GrainShape: TGrainShape;
    // How far the whole piece, turned by its grain, reaches across (X) and
    // along (Y) the material: opened out when it is on a fold, which needs
    // the same width as cutting it on material folded double
    function GrainExtent: TVec2;
    // The material it is cut from. While the pattern's first material has no ID,
    // '' is that material; once it has, '' is no material.
    property MaterialKey: string read FMaterialKey write FMaterialKey;
    // Its own colour, or '' for the material's
    property FillColor: string read FFillColor write FFillColor;
    property FillStyle: TPieceFillStyle read FFillStyle write FFillStyle;
  end;

  TPieceObjectArray = array of TPieceObject;

resourcestring
  rsPieceGap = 'There is a gap between %s and %s';
  rsPieceNoArea = 'The outline encloses no area';
  rsPieceNegativeAllowance = 'A seam allowance cannot be negative';
  rsPieceNoCutLine = 'No cutting line could be worked out';
  rsPieceGrainSamePlace = 'The grainline starts and ends at the same place';
  rsPieceHoleOutside = 'The marker at %s is outside the piece';
  rsPieceHoleOnFold = 'The hole at %s is on the fold';
  rsPieceHoleSize = 'A hole needs a size above 0';
  rsPieceStitchSpacing = 'Stitch holes need a spacing above 0';
  rsPieceNotchOffPiece = 'The notch at %s is not on the seam line';
  rsPieceNotchPastEnd = 'The notch at %s mm is off %s (%s mm long)';
  rsPieceCaption = '%s, cut %d';
  rsPieceCaptionMirrored = '%s, cut %d mirrored';
  rsPieceCaptionFold = '%s, cut %d on fold';

implementation

uses
  Math, Sloper.Core.Bezier;

const
  // Share of the piece's span along its grain that the arrow covers
  GRAIN_SHARE = 0.6;
  GRAIN_HEAD_LENGTH = 10;
  GRAIN_HEAD_SPREAD = 155;
  // How far, in degrees, a fold may run from the grain and still go on the
  // material's fold
  FOLD_GRAIN_TOLERANCE = 1;
  NOTCH_LENGTH = 6;
  FOLD_DEPTH = 20;
  FOLD_INSET = 0.15;
  FOLD_HEAD_LENGTH = 8;
  FOLD_HEAD_WIDTH = 25;

constructor TPieceObject.Create(const AKey: string; const APath: TPiecePath);
begin
  inherited Create(AKey);
  FPath := Copy(APath);
  AddField(PIECE_ALLOWANCE_FIELD);
  FCutCount := 1;
end;

function TPieceObject.InputKeys: TStringArray;
var
  Index: integer;
begin
  Result := nil;
  SetLength(Result, Length(FPath));
  for Index := 0 to High(FPath) do
    Result[Index] := FPath[Index].EdgeKey;
  if FGrainKind = gkPoints then
  begin
    System.Insert(FGrainStartKey, Result, Length(Result));
    System.Insert(FGrainEndKey, Result, Length(Result));
  end;
  for Index := 0 to High(FNotches) do
    if FNotches[Index].PointKey <> '' then
      System.Insert(FNotches[Index].PointKey, Result, Length(Result));
  for Index := 0 to High(FMarkings) do
    if FMarkings[Index].PointKey <> '' then
      System.Insert(FMarkings[Index].PointKey, Result, Length(Result))
    else
      System.Insert(FMarkings[Index].EdgeKey, Result, Length(Result));
end;

procedure TPieceObject.RedirectPoint(const OldKey, NewKey: string);
var
  Index: integer;
begin
  RedirectKey(FGrainStartKey, OldKey, NewKey);
  RedirectKey(FGrainEndKey, OldKey, NewKey);
  for Index := 0 to High(FNotches) do
    RedirectKey(FNotches[Index].PointKey, OldKey, NewKey);
  for Index := 0 to High(FMarkings) do
    RedirectKey(FMarkings[Index].PointKey, OldKey, NewKey);
end;

function TPieceObject.TypeName: string;
begin
  Result := 'piece';
end;

function TPieceObject.HasProperty(const Prop: string): boolean;
begin
  Result := Prop = 'holes';
end;

// Only stitch holes count, as they are what thread goes through
function TPieceObject.PropertyValue(const Prop: string): double;
var
  Mark: TMarkingMark;
begin
  Result := 0;
  if Prop = 'holes' then
    for Mark in FMarkingMarks do
      if Mark.Kind = mkStitchHoles then
        Result := Result + Length(Mark.Holes);
end;

function TPieceObject.PathIndexOf(const EdgeKey: string): integer;
begin
  for Result := 0 to High(FPath) do
    if FPath[Result].EdgeKey = EdgeKey then
      Exit;
  Result := -1;
end;

function TPieceObject.OverrideField(PathIndex: integer): string;
begin
  Result := 'edge' + IntToStr(PathIndex + 1) + '.' + PIECE_ALLOWANCE_FIELD;
end;

function TPieceObject.HasOverride(PathIndex: integer): boolean;
begin
  Result := Assigned(Field(OverrideField(PathIndex)));
end;

procedure TPieceObject.AddOverride(PathIndex: integer);
begin
  if not HasOverride(PathIndex) then
    AddField(OverrideField(PathIndex));
end;

procedure TPieceObject.RemoveOverride(PathIndex: integer);
begin
  RemoveField(OverrideField(PathIndex));
end;

procedure TPieceObject.SetGrainKind(AKind: TGrainKind; const AStartKey, AEndKey: string);
begin
  if FGrainKind = gkAngle then
    RemoveField(GRAIN_ANGLE_FIELD);
  FGrainKind := AKind;
  FGrainStartKey := AStartKey;
  FGrainEndKey := AEndKey;
  if AKind = gkAngle then
    AddField(GRAIN_ANGLE_FIELD);
end;

function TPieceObject.NotchField(Index: integer): string;
begin
  Result := 'notch' + IntToStr(Index + 1) + '.position';
end;

function TPieceObject.MarkingField(Index: integer; const Part: string): string;
begin
  Result := 'marking' + IntToStr(Index + 1) + '.' + Part;
end;

function TPieceObject.LineMarkingOf(const AEdgeKey: string): integer;
var
  Index: integer;
begin
  for Index := 0 to High(FMarkings) do
    if (FMarkings[Index].Kind = mkLine) and (FMarkings[Index].EdgeKey = AEdgeKey) then
      Exit(Index);
  Result := -1;
end;

function TPieceObject.PointMarkingOf(const AKey: string): integer;
var
  Index: integer;
begin
  for Index := 0 to High(FMarkings) do
    if (FMarkings[Index].Kind = mkPoint) and (FMarkings[Index].PointKey = AKey) then
      Exit(Index);
  Result := -1;
end;

function TPieceObject.UsesOnlyAsMarking(const AKey: string): boolean;
var
  InputKey: string;
  Reads, AsMarking, Index: integer;
begin
  Reads := 0;
  for InputKey in InputKeys do
    if InputKey = AKey then
      Inc(Reads);
  AsMarking := 0;
  for Index := 0 to High(FMarkings) do
    if ((FMarkings[Index].Kind = mkLine) and (FMarkings[Index].EdgeKey = AKey)) or
      ((FMarkings[Index].Kind = mkPoint) and (FMarkings[Index].PointKey = AKey)) then
      Inc(AsMarking);
  Result := (AsMarking > 0) and (Reads = AsMarking);
end;

function TPieceObject.AddMarking(AKind: TMarkingKind; const APointKey, AEdgeKey: string): integer;
begin
  Result := Length(FMarkings);
  SetLength(FMarkings, Result + 1);
  FMarkings[Result].Kind := AKind;
  FMarkings[Result].PointKey := APointKey;
  FMarkings[Result].EdgeKey := AEdgeKey;
  if AKind = mkStitchHoles then
  begin
    AddField(MarkingField(Result, MARKING_SPACING_FIELD));
    AddField(MarkingField(Result, MARKING_SIZE_FIELD));
  end;
end;

procedure TPieceObject.RemoveMarking(Index: integer);
var
  Later: integer;

  procedure MoveDown(At: integer);
  begin
    if FMarkings[At].Kind = mkStitchHoles then
    begin
      RenameField(MarkingField(At, MARKING_SPACING_FIELD), MarkingField(At - 1, MARKING_SPACING_FIELD));
      RenameField(MarkingField(At, MARKING_SIZE_FIELD), MarkingField(At - 1, MARKING_SIZE_FIELD));
    end;
  end;

begin
  if FMarkings[Index].Kind = mkStitchHoles then
  begin
    RemoveField(MarkingField(Index, MARKING_SPACING_FIELD));
    RemoveField(MarkingField(Index, MARKING_SIZE_FIELD));
  end;
  for Later := Index + 1 to High(FMarkings) do
    MoveDown(Later);
  System.Delete(FMarkings, Index, 1);
  if Index <= High(FMarkingMarks) then
    System.Delete(FMarkingMarks, Index, 1);
end;

function TPieceObject.ComputeMarking(Context: TEvalContext; Index: integer; const Cut: TVec2Array; const Fold: TLine2; out Mark: TMarkingMark): TEvalState;
var
  Marking: TPieceMarking;
  Node: TEvalNode;
  Edge: TEdgeObject;
  Spacing, Size: double;
  Count, Hole: integer;
  Position: TVec2;
  Positions: TVec2Array;
begin
  Mark := Default(TMarkingMark);
  Marking := FMarkings[Index];
  Mark.Kind := Marking.Kind;
  if Marking.Kind = mkPoint then
  begin
    Node := Context.FindNode(Marking.PointKey);
    if not ((Node is TPointObject) or (Node is TRepeatObject)) then
      Exit(Fail(esError, Format(rsDraftNotAPoint, [Marking.PointKey])));
    // A point that lost its marker prints nothing until it is taken off
    Mark.Marker := TDraftObject(Node).Marker;
    if Mark.Marker = pmPlain then
      Exit(esValid);
    Positions := MarkerPositions(TDraftObject(Node));
    for Position in Positions do
    begin
      // Checked first: a point on the outline can pass the test below or not,
      // and a hole here would have no other half when the piece opens out
      if (Mark.Marker = pmHole) and OnFold and (Distance(Position, MirrorPoint(Position, Fold.P1, Fold.P2)) < DEFAULT_TOLERANCE) then
        Exit(Fail(esInvalid, Format(rsPieceHoleOnFold, [Node.DisplayName])));
      if not PointInPolygon(Position, Cut) then
        Exit(Fail(esInvalid, Format(rsPieceHoleOutside, [Node.DisplayName])));
    end;
    if Mark.Marker = pmHole then
      Mark.Holes := Positions
    else
      Mark.Centres := Positions;
    Mark.HoleSize := TDraftObject(Node).MarkerSize;
    Exit(esValid);
  end;
  Node := Context.FindNode(Marking.EdgeKey);
  if not (Node is TEdgeObject) then
    Exit(Fail(esError, Format(rsDraftNotAnEdge, [Marking.EdgeKey])));
  Edge := TEdgeObject(Node);
  if Marking.Kind = mkLine then
  begin
    Mark.Line := Edge.Flatten(COARSE_FLATNESS);
    // An edge that lost its marking role keeps the plainest look
    Mark.Role := erPlacement;
    if Edge.Role in MARKING_ROLES then
      Mark.Role := Edge.Role;
    Exit(esValid);
  end;
  if not EvalLength(Context, MarkingField(Index, MARKING_SPACING_FIELD), Spacing) or not EvalLength(Context, MarkingField(Index, MARKING_SIZE_FIELD), Size) then
    Exit(esError);
  if Spacing <= 0 then
    Exit(Fail(esInvalid, rsPieceStitchSpacing));
  if Size <= 0 then
    Exit(Fail(esInvalid, rsPieceHoleSize));
  // Evenly between the ends, with the spacing adjusted to fit
  Count := Max(1, Round(Edge.Length / Spacing));
  SetLength(Mark.Holes, Count + 1);
  for Hole := 0 to Count do
    Mark.Holes[Hole] := Edge.PointAtLength(Edge.Length * Hole / Count);
  Mark.HoleSize := Size;
  Result := esValid;
end;

function TPieceObject.MarkingStrokes: TLine2Array;
var
  Mark: TMarkingMark;
  Centre: TVec2;
begin
  Result := nil;
  for Mark in FMarkingMarks do
  begin
    for Centre in Mark.Holes do
      Result := Concat(Result, MarkerStrokes(pmHole, Centre, Mark.HoleSize));
    for Centre in Mark.Centres do
      Result := Concat(Result, MarkerStrokes(Mark.Marker, Centre, Mark.HoleSize));
  end;
end;

function TPieceObject.AddNotch(const APointKey, AEdgeKey: string): integer;
begin
  Result := Length(FNotches);
  SetLength(FNotches, Result + 1);
  FNotches[Result].PointKey := APointKey;
  FNotches[Result].EdgeKey := AEdgeKey;
  if AEdgeKey <> '' then
    AddField(NotchField(Result));
end;

procedure TPieceObject.RemoveNotch(Index: integer);
var
  Later: integer;
begin
  if FNotches[Index].EdgeKey <> '' then
    RemoveField(NotchField(Index));
  // Fields are named by place in the list, so later ones move down
  for Later := Index + 1 to High(FNotches) do
    if FNotches[Later].EdgeKey <> '' then
      RenameField(NotchField(Later), NotchField(Later - 1));
  System.Delete(FNotches, Index, 1);
  if Index <= High(FNotchMarks) then
    System.Delete(FNotchMarks, Index, 1);
end;

function ReversedPoints(const Points: TVec2Array): TVec2Array;
var
  Index: integer;
begin
  Result := nil;
  SetLength(Result, Length(Points));
  for Index := 0 to High(Points) do
    Result[Index] := Points[High(Points) - Index];
end;

function TPieceObject.BuildOutline(Context: TEvalContext; DefaultWidth: double; out Outline: TVec2Array;
  out Widths, EdgeWidths: TDoubleArray): TEvalState;
var
  Index, Added, PointIndex: integer;
  Node: TEvalNode;
  First, Previous: TEdgeObject;
  Points: TVec2Array;
  LastEnd: TVec2;
  Width: double;
begin
  Outline := nil;
  Widths := nil;
  EdgeWidths := nil;
  SetLength(EdgeWidths, Length(FPath));
  First := nil;
  Previous := nil;
  LastEnd := Vec2(0, 0);
  for Index := 0 to High(FPath) do
  begin
    Node := Context.FindNode(FPath[Index].EdgeKey);
    if not (Node is TEdgeObject) then
      Exit(Fail(esError, Format(rsDraftNotAnEdge, [FPath[Index].EdgeKey])));
    Width := DefaultWidth;
    if HasOverride(Index) and not EvalLength(Context, OverrideField(Index), Width) then
      Exit(esError);
    if Width < 0 then
      Exit(Fail(esInvalid, rsPieceNegativeAllowance));
    if FPath[Index].EdgeKey = FFoldEdgeKey then
      Width := 0;
    EdgeWidths[Index] := Width;
    Points := TEdgeObject(Node).Flatten(COARSE_FLATNESS);
    if FPath[Index].Reversed then
      Points := ReversedPoints(Points);
    if Assigned(Previous) and not PointsNear(LastEnd, Points[0], PIECE_JOIN_TOLERANCE) then
      Exit(Fail(esInvalid, Format(rsPieceGap, [Previous.DisplayName, Node.DisplayName])));
    // Each point of the edge but its last starts a segment of this width
    Added := Length(Outline);
    SetLength(Outline, Added + High(Points));
    SetLength(Widths, Added + High(Points));
    for PointIndex := 0 to High(Points) - 1 do
    begin
      Outline[Added + PointIndex] := Points[PointIndex];
      Widths[Added + PointIndex] := Width;
    end;
    LastEnd := Points[High(Points)];
    Previous := TEdgeObject(Node);
    if not Assigned(First) then
      First := Previous;
  end;
  if not PointsNear(LastEnd, Outline[0], PIECE_JOIN_TOLERANCE) then
    Exit(Fail(esInvalid, Format(rsPieceGap, [Previous.DisplayName, First.DisplayName])));
  Result := esValid;
end;

function ExtentMiddle(const Points: TVec2Array): TVec2;
var
  Point: TVec2;
  MinX, MinY, MaxX, MaxY: double;
begin
  MinX := Infinity;
  MinY := Infinity;
  MaxX := -Infinity;
  MaxY := -Infinity;
  for Point in Points do
  begin
    MinX := Min(MinX, Point.X);
    MinY := Min(MinY, Point.Y);
    MaxX := Max(MaxX, Point.X);
    MaxY := Max(MaxY, Point.Y);
  end;
  Result := Vec2((MinX + MaxX) / 2, (MinY + MaxY) / 2);
end;

function TPieceObject.ComputeGrainline(Context: TEvalContext; const Points: TVec2Array; out Line: TLine2): TEvalState;
var
  Angle, Along, Lowest, Highest: double;
  Centre, Direction, Point: TVec2;
  StartNode, EndNode: TEvalNode;
begin
  Line := FGrainline;
  case FGrainKind of
    gkAngle:
    begin
      if not EvalField(Context, GRAIN_ANGLE_FIELD, Angle) then
        Exit(esError);
      Centre := ExtentMiddle(Points);
      Direction := PolarPoint(Vec2(0, 0), 1, Angle);
      Lowest := Infinity;
      Highest := -Infinity;
      for Point in Points do
      begin
        Along := Dot(Point - Centre, Direction);
        Lowest := Min(Lowest, Along);
        Highest := Max(Highest, Along);
      end;
      Centre := Centre + Direction * ((Lowest + Highest) / 2);
      Along := (Highest - Lowest) * GRAIN_SHARE / 2;
      Line := Line2(Centre - Direction * Along, Centre + Direction * Along);
    end;
    gkPoints:
    begin
      StartNode := Context.FindNode(FGrainStartKey);
      EndNode := Context.FindNode(FGrainEndKey);
      if not (StartNode is TPointObject) then
        Exit(Fail(esError, Format(rsDraftNotAPoint, [FGrainStartKey])));
      if not (EndNode is TPointObject) then
        Exit(Fail(esError, Format(rsDraftNotAPoint, [FGrainEndKey])));
      Line := Line2(TPointObject(StartNode).Position, TPointObject(EndNode).Position);
      if PointsNear(Line.P1, Line.P2) then
        Exit(Fail(esInvalid, rsPieceGrainSamePlace));
    end;
  end;
  Result := esValid;
end;

// Where a notch falls: which edge of the path, and how far along it
function TPieceObject.LocateNotch(Context: TEvalContext; Index: integer; out PathIndex: integer; out Position: double): TEvalState;
var
  Notch: TPieceNotch;
  Node: TEvalNode;
  Edge: TEdgeObject;
  Entry: integer;
  Spot: TVec2;
  Along, Gap, Best: double;
begin
  Notch := FNotches[Index];
  PathIndex := -1;
  Position := 0;
  if Notch.EdgeKey <> '' then
  begin
    PathIndex := PathIndexOf(Notch.EdgeKey);
    if PathIndex < 0 then
      Exit(Fail(esError, Format(rsDraftNotAnEdge, [Notch.EdgeKey])));
    Edge := TEdgeObject(Context.FindNode(Notch.EdgeKey));
    if not EvalLength(Context, NotchField(Index), Position) then
      Exit(esError);
    if (Position < -DEFAULT_TOLERANCE) or (Position > Edge.Length + DEFAULT_TOLERANCE) then
      Exit(Fail(esInvalid, Format(rsPieceNotchPastEnd, [FormatFloat('0.#', Position), Edge.DisplayName, FormatFloat('0.#', Edge.Length)])));
    Exit(esValid);
  end;
  Node := Context.FindNode(Notch.PointKey);
  if not (Node is TPointObject) then
    Exit(Fail(esError, Format(rsDraftNotAPoint, [Notch.PointKey])));
  Spot := TPointObject(Node).Position;
  Best := NOTCH_POINT_TOLERANCE;
  for Entry := 0 to High(FPath) do
  begin
    TEdgeObject(Context.FindNode(FPath[Entry].EdgeKey)).Locate(Spot, Along, Gap);
    if Gap <= Best then
    begin
      Best := Gap;
      PathIndex := Entry;
      Position := Along;
    end;
  end;
  if PathIndex < 0 then
    Exit(Fail(esInvalid, Format(rsPieceNotchOffPiece, [Node.DisplayName])));
  Result := esValid;
end;

// Outside is left of the way a clockwise path runs
function TPieceObject.OutwardAngle(Edge: TEdgeObject; PathIndex: integer; Position: double; Anticlockwise: boolean): double;
begin
  Result := Edge.DirectionAt(Position);
  if FPath[PathIndex].Reversed then
    Result := Result + 180;
  if Anticlockwise then
    Result := Result - 90
  else
    Result := Result + 90;
end;

procedure TPieceObject.ComputeFold(Context: TEvalContext; Anticlockwise: boolean; out Line: TLine2; out Inwards: double);
var
  Edge: TEdgeObject;
begin
  Line := FFoldLine;
  Inwards := FFoldInwards;
  if FFoldEdgeKey = '' then
    Exit;
  Edge := TEdgeObject(Context.FindNode(FFoldEdgeKey));
  Line := Line2(Edge.PointAtLength(0), Edge.PointAtLength(Edge.Length));
  Inwards := OutwardAngle(Edge, PathIndexOf(FFoldEdgeKey), Edge.Length / 2, Anticlockwise) + 180;
end;

function TPieceObject.ComputeNotch(Context: TEvalContext; Index: integer; const EdgeWidths: TDoubleArray;
  Anticlockwise: boolean; out Mark: TNotchMark): TEvalState;
var
  PathIndex: integer;
  Position, Outwards: double;
  Edge: TEdgeObject;
begin
  Mark := Default(TNotchMark);
  Result := LocateNotch(Context, Index, PathIndex, Position);
  if Result <> esValid then
    Exit;
  Edge := TEdgeObject(Context.FindNode(FPath[PathIndex].EdgeKey));
  Outwards := OutwardAngle(Edge, PathIndex, Position, Anticlockwise);
  Mark.Seam := Edge.PointAtLength(Position);
  Mark.Cut := PolarPoint(Mark.Seam, EdgeWidths[PathIndex], Outwards);
  Mark.Tip := PolarPoint(Mark.Cut, NOTCH_LENGTH, Outwards + 180);
end;

function TPieceObject.Compute(Context: TEvalContext): TEvalState;
var
  Width: double;
  Points, Cut: TVec2Array;
  Widths, EdgeWidths: TDoubleArray;
  Line: TLine2;
  Marks: TNotchMarkArray;
  NewMarkings: TMarkingMarkArray;
  Index: integer;
  NewFold: TLine2;
  FoldInwards: double;
begin
  if not EvalLength(Context, PIECE_ALLOWANCE_FIELD, Width) then
    Exit(esError);
  if Width < 0 then
    Exit(Fail(esInvalid, rsPieceNegativeAllowance));
  Result := BuildOutline(Context, Width, Points, Widths, EdgeWidths);
  if Result <> esValid then
    Exit;
  if Abs(SignedArea(Points)) < PIECE_JOIN_TOLERANCE then
    Exit(Fail(esInvalid, rsPieceNoArea));
  if not OffsetOutline(Points, Widths, Cut) then
    Exit(Fail(esInvalid, rsPieceNoCutLine));
  Result := ComputeGrainline(Context, Points, Line);
  if Result <> esValid then
    Exit;
  Marks := nil;
  SetLength(Marks, Length(FNotches));
  for Index := 0 to High(FNotches) do
  begin
    Result := ComputeNotch(Context, Index, EdgeWidths, SignedArea(Points) > 0, Marks[Index]);
    if Result <> esValid then
      Exit;
  end;
  ComputeFold(Context, SignedArea(Points) > 0, NewFold, FoldInwards);
  NewMarkings := nil;
  SetLength(NewMarkings, Length(FMarkings));
  for Index := 0 to High(FMarkings) do
  begin
    Result := ComputeMarking(Context, Index, Cut, NewFold, NewMarkings[Index]);
    if Result <> esValid then
      Exit;
  end;
  FMarkingMarks := NewMarkings;
  FOutline := Points;
  FCutLine := Cut;
  FGrainline := Line;
  FNotchMarks := Marks;
  FFoldLine := NewFold;
  FFoldInwards := FoldInwards;
end;

function TPieceObject.Area: double;
begin
  Result := Abs(SignedArea(FOutline));
end;

function TPieceObject.Perimeter: double;
begin
  Result := 0;
  if Length(FOutline) > 0 then
    Result := PolylineLength(FOutline) + Distance(FOutline[High(FOutline)], FOutline[0]);
end;

function TPieceObject.Middle: TVec2;
begin
  Result := ExtentMiddle(FOutline);
end;

function TPieceObject.OnFold: boolean;
begin
  Result := FFoldEdgeKey <> '';
end;

function TPieceObject.GrainShape: TGrainShape;
var
  Turn: double;
  Index: integer;
  Fold: TLine2;
begin
  Result := Default(TGrainShape);
  Turn := 0;
  if FGrainKind <> gkNone then
    Turn := 90 - FGrainline.Angle;
  SetLength(Result.Half, Length(FCutLine));
  for Index := 0 to High(FCutLine) do
    Result.Half[Index] := RotatePoint(FCutLine[Index], Vec2(0, 0), Turn);
  Result.Whole := Copy(Result.Half);
  if not OnFold then
    Exit;
  Fold := Line2(RotatePoint(FFoldLine.P1, Vec2(0, 0), Turn), RotatePoint(FFoldLine.P2, Vec2(0, 0), Turn));
  Result.FoldAlongGrain := Abs(Fold.P1.X - Fold.P2.X) <= Fold.Length * Sin(DegToRad(FOLD_GRAIN_TOLERANCE));
  SetLength(Result.Whole, 2 * Length(Result.Half));
  for Index := 0 to High(Result.Half) do
    Result.Whole[Length(Result.Half) + Index] := MirrorPoint(Result.Half[Index], Fold.P1, Fold.P2);
end;

function TPieceObject.GrainExtent: TVec2;
var
  Shape: TGrainShape;
begin
  Shape := GrainShape;
  Result := PointsExtent(Shape.Whole);
end;

function TPieceObject.CutCaption(Whole: boolean): string;
begin
  if OnFold and not Whole then
    Result := Format(rsPieceCaptionFold, [DisplayName, FCutCount])
  else if FMirrored and (FCutCount > 1) then
    Result := Format(rsPieceCaptionMirrored, [DisplayName, FCutCount])
  else
    Result := Format(rsPieceCaption, [DisplayName, FCutCount]);
end;

function TPieceObject.FoldArrow: TLine2Array;
var
  Near1, Near2, Far1, Far2: TVec2;

  procedure AddStroke(const From, Target: TVec2);
  begin
    SetLength(Result, Length(Result) + 1);
    Result[High(Result)] := Line2(From, Target);
  end;

  procedure AddHead(const Tip: TVec2);
  begin
    AddStroke(Tip, PolarPoint(Tip, FOLD_HEAD_LENGTH, FFoldInwards + FOLD_HEAD_WIDTH));
    AddStroke(Tip, PolarPoint(Tip, FOLD_HEAD_LENGTH, FFoldInwards - FOLD_HEAD_WIDTH));
  end;

begin
  Result := nil;
  if not OnFold then
    Exit;
  Near1 := FFoldLine.PointAt(FOLD_INSET);
  Near2 := FFoldLine.PointAt(1 - FOLD_INSET);
  Far1 := PolarPoint(Near1, FOLD_DEPTH, FFoldInwards);
  Far2 := PolarPoint(Near2, FOLD_DEPTH, FFoldInwards);
  AddStroke(Far1, Far2);
  AddStroke(Far1, Near1);
  AddStroke(Far2, Near2);
  AddHead(Near1);
  AddHead(Near2);
end;

function TPieceObject.GrainArrow: TLine2Array;
var
  Angle: double;

  procedure AddStroke(const From, Target: TVec2);
  begin
    SetLength(Result, Length(Result) + 1);
    Result[High(Result)] := Line2(From, Target);
  end;

begin
  Result := nil;
  if FGrainKind = gkNone then
    Exit;
  Angle := FGrainline.Angle;
  AddStroke(FGrainline.P1, FGrainline.P2);
  AddStroke(FGrainline.P2, PolarPoint(FGrainline.P2, GRAIN_HEAD_LENGTH, Angle + GRAIN_HEAD_SPREAD));
  AddStroke(FGrainline.P2, PolarPoint(FGrainline.P2, GRAIN_HEAD_LENGTH, Angle - GRAIN_HEAD_SPREAD));
  AddStroke(FGrainline.P1, PolarPoint(FGrainline.P1, GRAIN_HEAD_LENGTH, Angle + GRAIN_HEAD_SPREAD + 180));
  AddStroke(FGrainline.P1, PolarPoint(FGrainline.P1, GRAIN_HEAD_LENGTH, Angle - GRAIN_HEAD_SPREAD + 180));
end;

// The allowance and its overrides (edge1.allowance), marking spacings and
// sizes, and notch positions along an edge are lengths; the grainline's is an angle
function TPieceObject.FieldUnitKind(const AName: string): TFieldUnitKind;
begin
  if AName = GRAIN_ANGLE_FIELD then
    Result := fkAngle
  else if (AName = PIECE_ALLOWANCE_FIELD) or AName.EndsWith('.' + PIECE_ALLOWANCE_FIELD) or AName.EndsWith('.' + MARKING_SPACING_FIELD) or
    AName.EndsWith('.' + MARKING_SIZE_FIELD) or AName.EndsWith('.position') then
    Result := fkLength
  else
    Result := inherited FieldUnitKind(AName);
end;

procedure TPieceObject.SplitPathEdge(PathIndex: integer; const FirstKey, SecondKey: string);
var
  Index: integer;
  Entry: TPieceEdge;
  OverrideText: string;
begin
  Entry := FPath[PathIndex];
  Insert(Entry, FPath, PathIndex + 1);
  FPath[PathIndex].EdgeKey := FirstKey;
  FPath[PathIndex + 1].EdgeKey := SecondKey;
  // From the end, so no field is renamed onto one still to move
  for Index := High(FPath) - 1 downto PathIndex + 1 do
    if HasOverride(Index) then
      RenameField(OverrideField(Index), OverrideField(Index + 1));
  if HasOverride(PathIndex) then
  begin
    OverrideText := Field(OverrideField(PathIndex)).StoredText;
    AddOverride(PathIndex + 1);
    Field(OverrideField(PathIndex + 1)).ParseStored(OverrideText);
  end;
end;

procedure TPieceObject.JoinPathEdges(PathIndex: integer; const EdgeKey: string; Reversed: boolean);
var
  Index, Next, Joined: integer;
  OverrideText: string;
begin
  Next := (PathIndex + 1) mod Length(FPath);
  OverrideText := '';
  if HasOverride(PathIndex) then
    OverrideText := Field(OverrideField(PathIndex)).StoredText
  else if HasOverride(Next) then
    OverrideText := Field(OverrideField(Next)).StoredText;
  if HasOverride(PathIndex) then
    RemoveOverride(PathIndex);
  if HasOverride(Next) then
    RemoveOverride(Next);
  FPath[PathIndex].EdgeKey := EdgeKey;
  FPath[PathIndex].Reversed := Reversed;
  Delete(FPath, Next, 1);
  // Later overrides move down one, from the start so none is renamed onto one still to move
  for Index := Next to High(FPath) do
    if HasOverride(Index + 1) then
      RenameField(OverrideField(Index + 1), OverrideField(Index));
  if Next > PathIndex then
    Joined := PathIndex
  else
    Joined := PathIndex - 1;
  if OverrideText <> '' then
  begin
    AddOverride(Joined);
    Field(OverrideField(Joined)).ParseStored(OverrideText);
  end;
end;

procedure TPieceObject.SetNotchEdge(Index: integer; const AEdgeKey: string);
begin
  FNotches[Index].EdgeKey := AEdgeKey;
end;

function TPieceObject.OverridePathIndex(const FieldName: string): integer;
begin
  for Result := 0 to High(FPath) do
    if SameText(FieldName, OverrideField(Result)) then
      Exit;
  Result := -1;
end;

end.
