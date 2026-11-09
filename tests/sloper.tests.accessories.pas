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

unit Sloper.Tests.Accessories;

{$mode ObjFPC}{$H+}

interface

uses
  SysUtils, fpcunit, testregistry, Sloper.Tests.TestCase, Sloper.Core.Geometry, Sloper.Core.Pattern, Sloper.Core.Draft,
  Sloper.Core.Materials, Sloper.Core.Piece, Sloper.Core.Seam;

type
  TTestAccessories = class(TOSTestCase)
  private
    FPattern, FLoaded: TPattern;
    function Pt(const AName: string; X: double = 0; Y: double = 0): string;
    function Line(const A, B: string): TLineObject;
    function Rectangle(const Width: string = '200'; const Height: string = '100'): TRectangleEdges;
    function Reloaded: TPattern;
    function PieceAt(X, Y: double; const AName: string = 'Panel'): TPieceObject;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestRectangleCorners;
    procedure TestRectangleIsAPiece;
    procedure TestRectangleFollowsFormulas;
    procedure TestRectangleHeightIsInOnePlace;
    procedure TestRectangleRoundTrip;
    procedure TestRectangleOnFirstPointIsOneChange;
    procedure TestOffsetLineLeft;
    procedure TestOffsetLineRight;
    procedure TestOffsetFollowsSource;
    procedure TestOffsetFollowsDistance;
    procedure TestOffsetNegativeIsInvalid;
    procedure TestOffsetOfArcChangesRadius;
    procedure TestOffsetOfCurveStaysAtDistance;
    procedure TestOffsetOfPathJoinsUp;
    procedure TestOffsetIsStraightOnlyFromAStraightEdge;
    procedure TestOffsetRoundTrip;
    procedure TestPointAlongOffset;
    procedure TestCornerTangentPoints;
    procedure TestCornerArcLength;
    procedure TestCornerFollowsRadius;
    procedure TestCornerFollowsMovedPoint;
    procedure TestCornerRadiusTooBigIsInvalid;
    procedure TestCornerRefusesCurve;
    procedure TestCornerRefusesEdgesNotMeeting;
    procedure TestCornerOnAPiece;
    procedure TestCornerOnAPieceEitherOrder;
    procedure TestAllFourCornersOfAPiece;
    procedure TestCornerOnAPieceMovesNotches;
    procedure TestCornerOnAPieceKeepsAllowance;
    procedure TestCornerOnAPieceFollowsSeam;
    procedure TestCornerRefusesFold;
    procedure TestCornerLeavesConstruction;
    procedure TestAllFourCornersMakeAPiece;
    procedure TestCornerRoundTrip;
    procedure TestMaterialAllowanceSetsPiece;
    procedure TestMaterialAllowanceForNewPiece;
    procedure TestMaterialWithoutAllowanceLeavesPiece;
    procedure TestExplicitAllowanceStands;
    procedure TestMaterialAllowanceRoundTrip;
    procedure TestMaterialAllowanceRefusesNegative;
    procedure TestLeatherHasNoAllowance;
    procedure TestHoleMarking;
    procedure TestHoleFollowsItsPoint;
    procedure TestHoleOutsidePieceIsInvalid;
    procedure TestHoleDiameterMustBePositive;
    procedure TestPlacementLineFollowsEdge;
    procedure TestFoldLineMarking;
    procedure TestStitchHolesSpaceEvenly;
    procedure TestStitchSpacingAdjustsToFit;
    procedure TestStitchHolesFollowSize;
    procedure TestStitchSpacingMustBePositive;
    procedure TestPieceReportsHoleCount;
    procedure TestMarkingUsesItsInput;
    procedure TestRemoveMarkingRenumbers;
    procedure TestRemoveMissingMarkingRefused;
    procedure TestMarkingsRoundTrip;
    procedure TestMarkingsDrawAsStrokes;
    procedure TestRoleLineJoinsItsPiece;
    procedure TestLineInOverlappingPiecesJoinsBoth;
    procedure TestLooseLineJoinsNewPiece;
    procedure TestAssignmentIsKept;
    procedure TestOtherRoleDetaches;
    procedure TestDeletingLineDetaches;
    procedure TestAttachNeedsMarkingRole;
    procedure TestAttachByHand;
    procedure TestOldPlacementBecomesRole;
    procedure TestRolesRoundTrip;
  end;

implementation

uses
  Math, Sloper.Core.EvalTypes, Sloper.Core.PatternFile, Sloper.Core.PieceDetect, Sloper.Core.Evaluator, Sloper.Core.PatternCheck;

procedure TTestAccessories.SetUp;
begin
  inherited SetUp;
  FPattern := TPattern.Create;
end;

procedure TTestAccessories.TearDown;
begin
  FreeAndNil(FLoaded);
  FreeAndNil(FPattern);
  inherited TearDown;
end;

function TTestAccessories.Pt(const AName: string; X, Y: double): string;
begin
  Result := FPattern.AddFreePoint(AName, FloatToStr(X), FloatToStr(Y)).Key;
end;

function TTestAccessories.Line(const A, B: string): TLineObject;
begin
  Result := FPattern.AddLine(A, B, erOutline);
  AssertNotNull(FPattern.LastError, Result);
end;

function TTestAccessories.Rectangle(const Width, Height: string): TRectangleEdges;
begin
  AssertTrue(FPattern.LastError, FPattern.AddRectangle(Pt('O'), Width, Height, erOutline, Result));
  FPattern.Evaluate;
end;

function TTestAccessories.Reloaded: TPattern;
var
  Reason: string;
begin
  FreeAndNil(FLoaded);
  FLoaded := TPattern.Create;
  AssertTrue(Reason, LoadPatternFromText(FLoaded, SavePatternToText(FPattern), Reason));
  FLoaded.Evaluate;
  Result := FLoaded;
end;

function TTestAccessories.PieceAt(X, Y: double; const AName: string): TPieceObject;
var
  Path: TPiecePath;
  Reason: string;
begin
  FPattern.Evaluate;
  AssertTrue(Reason, DetectPiecePath(FPattern, Vec2(X, Y), Path, Reason));
  Result := FPattern.AddPiece(AName, Path, DefaultPieceAllowance);
  AssertNotNull(FPattern.LastError, Result);
  FPattern.Evaluate;
end;

procedure TTestAccessories.TestRectangleCorners;
var
  Edges: TRectangleEdges;
begin
  Edges := Rectangle;
  AssertPointsNear('bottom', Vec2(200, 0), Edges[0].PointAtLength(Edges[0].Length));
  AssertPointsNear('right', Vec2(200, 100), Edges[1].PointAtLength(Edges[1].Length));
  AssertPointsNear('top', Vec2(0, 100), Edges[2].PointAtLength(Edges[2].Length));
  AssertPointsNear('left', Vec2(0, 0), Edges[3].PointAtLength(Edges[3].Length));
end;

procedure TTestAccessories.TestRectangleIsAPiece;
begin
  Rectangle;
  AssertEquals(20000, PieceAt(50, 50).Area, 1e-6);
end;

procedure TTestAccessories.TestRectangleFollowsFormulas;
var
  Edges: TRectangleEdges;
begin
  FPattern.AddVariable('width', '300');
  FPattern.AddVariable('height', '80');
  Edges := Rectangle('#width', '#height');
  AssertEquals(300, Edges[0].Length, 1e-9);
  AssertEquals(80, Edges[1].Length, 1e-9);
end;

procedure TTestAccessories.TestRectangleHeightIsInOnePlace;
var
  Edges: TRectangleEdges;
begin
  Edges := Rectangle;
  // The top left point holds the height, and the top right follows it
  AssertTrue(FPattern.LastError, FPattern.SetFormula(FPattern.FindNode(Edges[2].EndKey), 'dy', '150'));
  FPattern.Evaluate;
  AssertEquals(150, Edges[1].Length, 1e-9);
  AssertEquals(150, Edges[3].Length, 1e-9);
end;

procedure TTestAccessories.TestRectangleRoundTrip;
var
  Edges: TRectangleEdges;
begin
  Edges := Rectangle;
  Reloaded;
  AssertEquals(100, TEdgeObject(FLoaded.FindNode(Edges[1].Key)).Length, 1e-9);
end;

procedure TTestAccessories.TestRectangleOnFirstPointIsOneChange;
var
  Edges: TRectangleEdges;
begin
  Edges := Rectangle;
  AssertEquals('corner, three points and four lines', 8, FPattern.ObjectCount);
  AssertEquals('outline', Ord(erOutline), Ord(Edges[0].Role));
end;

procedure TTestAccessories.TestOffsetLineLeft;
var
  Edge: TOffsetEdge;
begin
  Edge := FPattern.AddOffsetEdge(Line(Pt('A'), Pt('B', 100)).Key, '10', osLeft);
  FPattern.Evaluate;
  AssertTrue(Edge.Message, Edge.State = esValid);
  AssertPointsNear('start', Vec2(0, -10), Edge.PointAtLength(0));
  AssertPointsNear('end', Vec2(100, -10), Edge.PointAtLength(Edge.Length));
end;

procedure TTestAccessories.TestOffsetLineRight;
var
  Edge: TOffsetEdge;
begin
  Edge := FPattern.AddOffsetEdge(Line(Pt('A'), Pt('B', 100)).Key, '10', osRight);
  FPattern.Evaluate;
  AssertPointsNear('start', Vec2(0, 10), Edge.PointAtLength(0));
end;

procedure TTestAccessories.TestOffsetFollowsSource;
var
  B: string;
  Edge: TOffsetEdge;
begin
  B := Pt('B', 100);
  Edge := FPattern.AddOffsetEdge(Line(Pt('A'), B).Key, '10', osLeft);
  FPattern.Evaluate;
  AssertTrue(FPattern.SetFormula(FPattern.FindNode(B), 'x', '250'));
  FPattern.Evaluate;
  AssertEquals(250, Edge.Length, 1e-9);
end;

procedure TTestAccessories.TestOffsetFollowsDistance;
var
  Edge: TOffsetEdge;
begin
  FPattern.AddVariable('stitch', '6');
  Edge := FPattern.AddOffsetEdge(Line(Pt('A'), Pt('B', 100)).Key, '#stitch * 2', osLeft);
  FPattern.Evaluate;
  // Left of a line running right is up, towards smaller y
  AssertEquals(-12, Edge.PointAtLength(0).Y, 1e-9);
end;

procedure TTestAccessories.TestOffsetNegativeIsInvalid;
var
  Edge: TOffsetEdge;
begin
  Edge := FPattern.AddOffsetEdge(Line(Pt('A'), Pt('B', 100)).Key, '-1', osLeft);
  FPattern.Evaluate;
  AssertTrue(Edge.State = esInvalid);
end;

procedure TTestAccessories.TestOffsetOfArcChangesRadius;
var
  Arc: TArcObject;
  Edge: TOffsetEdge;
  Index: integer;
begin
  Arc := FPattern.AddArc(Pt('O'), '50', '0', '180', erOutline);
  // Anticlockwise, the left side is towards the centre
  Edge := FPattern.AddOffsetEdge(Arc.Key, '10', osLeft);
  FPattern.Evaluate;
  for Index := 0 to 20 do
    AssertEquals(40, Distance(Edge.PointAtLength(Edge.Length * Index / 20), Vec2(0, 0)), 0.01);
  AssertEquals(Pi * 40, Edge.Length, 0.05);
end;

procedure TTestAccessories.TestOffsetOfCurveStaysAtDistance;
var
  Curve: TCurveObject;
  Edge: TOffsetEdge;
  Index: integer;
  At: TVec2;
  Position, Gap: double;
begin
  Curve := FPattern.AddCurve(Pt('A'), Pt('B', 300), '60', '120', '120', '120', erOutline);
  Edge := FPattern.AddOffsetEdge(Curve.Key, '15', osRight);
  FPattern.Evaluate;
  for Index := 0 to 40 do
  begin
    At := Edge.PointAtLength(Edge.Length * Index / 40);
    Curve.Locate(At, Position, Gap);
    AssertEquals(15, Gap, 0.05);
  end;
end;

procedure TTestAccessories.TestOffsetOfPathJoinsUp;
var
  Edge: TOffsetEdge;
  Path: TCurvePathObject;
  Points: TVec2Array;
  Index: integer;
begin
  Path := FPattern.AddCurvePath([Pt('A'), Pt('B', 100), Pt('C', 200)], ['0', '45', '0'], ['0', '30', '30'], ['30', '30', '0'], erOutline);
  AssertNotNull(FPattern.LastError, Path);
  Edge := FPattern.AddOffsetEdge(Path.Key, '10', osLeft);
  FPattern.Evaluate;
  Points := Edge.Flatten(0.1);
  for Index := 1 to High(Points) do
    AssertTrue('no jumps', Distance(Points[Index - 1], Points[Index]) < 40);
end;

procedure TTestAccessories.TestOffsetIsStraightOnlyFromAStraightEdge;
var
  Straight, Round: TOffsetEdge;
begin
  Straight := FPattern.AddOffsetEdge(Line(Pt('A'), Pt('B', 100)).Key, '10', osLeft);
  Round := FPattern.AddOffsetEdge(FPattern.AddArc(Pt('O'), '50', '0', '90').Key, '10', osLeft);
  FPattern.Evaluate;
  AssertTrue(Straight.IsStraight);
  AssertFalse(Round.IsStraight);
end;

procedure TTestAccessories.TestOffsetRoundTrip;
var
  Edge, Back: TOffsetEdge;
begin
  Edge := FPattern.AddOffsetEdge(Line(Pt('A'), Pt('B', 100)).Key, '10', osRight, erOutline);
  FPattern.Evaluate;
  Back := TOffsetEdge(Reloaded.FindNode(Edge.Key));
  AssertTrue(Back.Side = osRight);
  AssertTrue(Back.Role = erOutline);
  AssertPointsNear('same place', Vec2(0, 10), Back.PointAtLength(0));
  AssertEquals(SavePatternToText(FPattern), SavePatternToText(FLoaded));
end;

procedure TTestAccessories.TestPointAlongOffset;
var
  Edge: TOffsetEdge;
  Point: TAlongEdgePoint;
begin
  Edge := FPattern.AddOffsetEdge(Line(Pt('A'), Pt('B', 100)).Key, '10', osLeft);
  Point := FPattern.AddAlongEdgePoint('M', Edge.Key, False, amRatio, '0.5');
  FPattern.Evaluate;
  AssertPointsNear('middle', Vec2(50, -10), Point.Position);
end;

procedure TTestAccessories.TestCornerTangentPoints;
var
  V: string;
  Arc: TCornerArc;
begin
  V := Pt('V', 100);
  Arc := FPattern.AddRoundCorner(Line(Pt('A'), V).Key, Line(V, Pt('B', 100, 100)).Key, '20');
  AssertNotNull(FPattern.LastError, Arc);
  FPattern.Evaluate;
  AssertTrue(Arc.Message, Arc.State = esValid);
  AssertPointsNear('on the first edge', Vec2(80, 0), Arc.PointAtLength(0));
  AssertPointsNear('on the second', Vec2(100, 20), Arc.PointAtLength(Arc.Length));
end;

procedure TTestAccessories.TestCornerArcLength;
var
  V: string;
  Arc: TCornerArc;
begin
  V := Pt('V', 100);
  Arc := FPattern.AddRoundCorner(Line(Pt('A'), V).Key, Line(V, Pt('B', 100, 100)).Key, '20');
  FPattern.Evaluate;
  AssertEquals('a quarter circle', Pi * 10, Arc.PropertyValue('length'), 1e-9);
end;

procedure TTestAccessories.TestCornerFollowsRadius;
var
  V: string;
  Arc: TCornerArc;
begin
  V := Pt('V', 100);
  Arc := FPattern.AddRoundCorner(Line(Pt('A'), V).Key, Line(V, Pt('B', 100, 100)).Key, '20');
  FPattern.Evaluate;
  AssertTrue(FPattern.SetFormula(Arc, 'radius', '40'));
  FPattern.Evaluate;
  AssertPointsNear('moved along', Vec2(60, 0), Arc.PointAtLength(0));
end;

procedure TTestAccessories.TestCornerFollowsMovedPoint;
var
  V: string;
  Arc: TCornerArc;
begin
  V := Pt('V', 100);
  Arc := FPattern.AddRoundCorner(Line(Pt('A'), V).Key, Line(V, Pt('B', 100, 100)).Key, '20');
  FPattern.Evaluate;
  AssertTrue(FPattern.SetFormula(FPattern.FindNode(V), 'y', '0.5'));
  FPattern.Evaluate;
  AssertTrue(Arc.Message, Arc.State = esValid);
end;

procedure TTestAccessories.TestCornerRadiusTooBigIsInvalid;
var
  V: string;
  Arc: TCornerArc;
begin
  V := Pt('V', 100);
  Arc := FPattern.AddRoundCorner(Line(Pt('A'), V).Key, Line(V, Pt('B', 100, 100)).Key, '150');
  FPattern.Evaluate;
  AssertTrue(Arc.State = esInvalid);
end;

procedure TTestAccessories.TestCornerRefusesCurve;
var
  V: string;
  Curve: TCurveObject;
begin
  V := Pt('V', 100);
  Curve := FPattern.AddCurve(Pt('A'), V, '30', '30', '150', '30', erOutline);
  FPattern.Evaluate;
  AssertTrue(not Assigned(FPattern.AddRoundCorner(Curve.Key, Line(V, Pt('B', 100, 100)).Key, '20')));
  AssertEquals(Format(rsPatternCornerNotStraight, [Curve.Name]), FPattern.LastError);
end;

procedure TTestAccessories.TestCornerRefusesEdgesNotMeeting;
var
  First, Second: TLineObject;
begin
  First := Line(Pt('A'), Pt('B', 100));
  Second := Line(Pt('C', 200), Pt('D', 300));
  FPattern.Evaluate;
  AssertTrue(not Assigned(FPattern.AddRoundCorner(First.Key, Second.Key, '20')));
  AssertEquals(Format(rsPatternCornerNotMeeting, [First.Name, Second.Name]), FPattern.LastError);
end;

// The cut-away corner lost from a rectangle piece rounded with this radius
function CornerLoss(Radius: double): double;
begin
  Result := (1 - Pi / 4) * Sqr(Radius);
end;

// Rounding a corner of a piece rounds the piece: it takes the arc and what is
// left of the edges, as it takes the parts of a split edge
procedure TTestAccessories.TestCornerOnAPiece;
var
  Edges: TRectangleEdges;
  Piece: TPieceObject;
  Arc: TCornerArc;
begin
  Edges := Rectangle;
  Piece := PieceAt(50, 50);
  Arc := FPattern.AddRoundCorner(Edges[0].Key, Edges[1].Key, '20');
  AssertNotNull(FPattern.LastError, Arc);
  FPattern.Evaluate;
  AssertTrue(Piece.Message, Piece.State = esValid);
  AssertEquals('four lines and the arc', 5, Length(Piece.Path));
  AssertTrue('the arc is in the path', Piece.PathIndexOf(Arc.Key) >= 0);
  AssertTrue('so is what is left of the first edge', Piece.PathIndexOf(Arc.TrimmedA.Key) >= 0);
  AssertTrue('and of the second', Piece.PathIndexOf(Arc.TrimmedB.Key) >= 0);
  AssertEquals(20000 - CornerLoss(20), Piece.Area, 2);
end;

procedure TTestAccessories.TestCornerOnAPieceEitherOrder;
var
  Edges: TRectangleEdges;
  Piece: TPieceObject;
begin
  Edges := Rectangle;
  Piece := PieceAt(50, 50);
  AssertNotNull(FPattern.LastError, FPattern.AddRoundCorner(Edges[1].Key, Edges[0].Key, '20'));
  FPattern.Evaluate;
  AssertTrue(Piece.Message, Piece.State = esValid);
  AssertEquals(20000 - CornerLoss(20), Piece.Area, 2);
end;

// One of the corners joins the end of the path to its start
procedure TTestAccessories.TestAllFourCornersOfAPiece;
const
  Radius = 20;
var
  Edges: TRectangleEdges;
  Index: integer;
  Current: array[0..3] of TEdgeObject;
  Arc: TCornerArc;
  Piece: TPieceObject;
begin
  Edges := Rectangle;
  Piece := PieceAt(100, 50);
  for Index := 0 to 3 do
    Current[Index] := Edges[Index];
  for Index := 0 to 3 do
  begin
    Arc := FPattern.AddRoundCorner(Current[Index].Key, Current[(Index + 1) mod 4].Key, IntToStr(Radius));
    AssertNotNull(FPattern.LastError, Arc);
    Current[Index] := Arc.TrimmedA;
    Current[(Index + 1) mod 4] := Arc.TrimmedB;
  end;
  FPattern.Evaluate;
  AssertTrue(Piece.Message, Piece.State = esValid);
  AssertEquals('four lines and four arcs', 8, Length(Piece.Path));
  AssertEquals(20000 - 4 * CornerLoss(Radius), Piece.Area, 6);
  Reloaded;
  AssertTrue(TPieceObject(FLoaded.FindObject('Panel')).State = esValid);
end;

// A notch on the part cut away goes to the arc's end nearest it; one on the
// part kept stays where it is
procedure TTestAccessories.TestCornerOnAPieceMovesNotches;
var
  Edges: TRectangleEdges;
  Piece: TPieceObject;
  Arc: TCornerArc;
  Index: integer;
begin
  Edges := Rectangle;
  Piece := PieceAt(50, 50);
  AssertTrue(FPattern.LastError, FPattern.AddEdgeNotch(Piece, Edges[0].Key, '50'));
  AssertTrue(FPattern.LastError, FPattern.AddEdgeNotch(Piece, Edges[0].Key, '195'));
  AssertTrue(FPattern.LastError, FPattern.AddEdgeNotch(Piece, Edges[1].Key, '5'));
  Arc := FPattern.AddRoundCorner(Edges[0].Key, Edges[1].Key, '20');
  AssertNotNull(FPattern.LastError, Arc);
  FPattern.Evaluate;
  AssertTrue(Piece.Message, Piece.State = esValid);
  AssertEquals(3, Length(Piece.Notches));
  for Index := 0 to 2 do
    AssertTrue('no notch on a part cut away', (Piece.Notches[Index].EdgeKey = Arc.Key) or
      (Piece.Notches[Index].EdgeKey = Arc.TrimmedA.Key) or (Piece.Notches[Index].EdgeKey = Arc.TrimmedB.Key));
  AssertPointsNear('the notch on the part kept', Vec2(50, 0), Piece.NotchMarks[0].Seam);
  AssertPointsNear('at the start of the arc', Vec2(180, 0), Piece.NotchMarks[1].Seam);
  AssertPointsNear('at the end of the arc', Vec2(200, 20), Piece.NotchMarks[2].Seam);
end;

procedure TTestAccessories.TestCornerOnAPieceKeepsAllowance;
var
  Edges: TRectangleEdges;
  Piece: TPieceObject;
  Arc: TCornerArc;
begin
  Edges := Rectangle;
  Piece := PieceAt(50, 50);
  AssertTrue(FPattern.LastError, FPattern.SetEdgeAllowance(Piece, Piece.PathIndexOf(Edges[3].Key), '25'));
  Arc := FPattern.AddRoundCorner(Edges[0].Key, Edges[1].Key, '20');
  AssertNotNull(FPattern.LastError, Arc);
  FPattern.Evaluate;
  AssertTrue(Piece.Message, Piece.State = esValid);
  AssertTrue('the left edge keeps its own allowance', Piece.HasOverride(Piece.PathIndexOf(Edges[3].Key)));
  AssertEquals('25', Piece.Field(Piece.OverrideField(Piece.PathIndexOf(Edges[3].Key))).StoredText);
  AssertFalse('the arc has none of its own', Piece.HasOverride(Piece.PathIndexOf(Arc.Key)));
end;

// A seam that used the edges takes what is left of them and the arc
procedure TTestAccessories.TestCornerOnAPieceFollowsSeam;
var
  Edges: TRectangleEdges;
  Piece: TPieceObject;
  Seam: TSeamObject;
  Arc: TCornerArc;
  SideA, SideB: TSeamSide;
begin
  Edges := Rectangle;
  Piece := PieceAt(50, 50);
  SetLength(SideA, 2);
  SideA[0].PieceKey := Piece.Key;
  SideA[0].EdgeKey := Edges[0].Key;
  SideA[1].PieceKey := Piece.Key;
  SideA[1].EdgeKey := Edges[1].Key;
  SetLength(SideB, 1);
  SideB[0].PieceKey := Piece.Key;
  SideB[0].EdgeKey := Edges[2].Key;
  Seam := FPattern.AddSeam('Top', SideA, SideB);
  AssertNotNull(FPattern.LastError, Seam);
  Arc := FPattern.AddRoundCorner(Edges[0].Key, Edges[1].Key, '20');
  AssertNotNull(FPattern.LastError, Arc);
  FPattern.Evaluate;
  AssertTrue(Seam.Message, Seam.State = esValid);
  AssertEquals('the kept parts and the arc', 3, Length(Seam.SideA));
  AssertTrue(Seam.UsesEdge(Piece.Key, Arc.Key));
  AssertEquals(300 - 40 + Pi * 10, Seam.LengthA, 0.1);
end;

// A fold has to stay one straight edge
procedure TTestAccessories.TestCornerRefusesFold;
var
  Edges: TRectangleEdges;
  Piece: TPieceObject;
begin
  Edges := Rectangle;
  Piece := PieceAt(50, 50);
  AssertTrue(FPattern.LastError, FPattern.SetFoldEdge(Piece, Edges[1].Key));
  AssertTrue(not Assigned(FPattern.AddRoundCorner(Edges[0].Key, Edges[1].Key, '20')));
  AssertEquals(Format(rsPatternCornerOnFold, [Edges[1].Name, 'Panel']), FPattern.LastError);
end;

procedure TTestAccessories.TestCornerLeavesConstruction;
var
  V: string;
  First: TLineObject;
begin
  V := Pt('V', 100);
  First := Line(Pt('A'), V);
  FPattern.AddRoundCorner(First.Key, Line(V, Pt('B', 100, 100)).Key, '20');
  AssertTrue('the sharp corner stays as a guide', First.Role = erConstruction);
end;

procedure TTestAccessories.TestAllFourCornersMakeAPiece;
const
  Radius = 20;
var
  Edges: TRectangleEdges;
  Index: integer;
  Current: array[0..3] of TEdgeObject;
  Arc: TCornerArc;
  Piece: TPieceObject;
begin
  Edges := Rectangle;
  for Index := 0 to 3 do
    Current[Index] := Edges[Index];
  // Each corner trims two edges, and the next uses what is left of them
  for Index := 0 to 3 do
  begin
    Arc := FPattern.AddRoundCorner(Current[Index].Key, Current[(Index + 1) mod 4].Key, IntToStr(Radius));
    AssertNotNull(FPattern.LastError, Arc);
    Current[Index] := Arc.TrimmedA;
    Current[(Index + 1) mod 4] := Arc.TrimmedB;
  end;
  Piece := PieceAt(100, 50);
  AssertEquals('four lines and four arcs', 8, Length(Piece.Path));
  AssertEquals('within 0.03%, from the flattened outline', 20000 - (4 - Pi) * Sqr(Radius), Piece.Area, 6);
  AssertEquals(2 * (200 + 100) - 8 * Radius + 2 * Pi * Radius, Piece.Perimeter, 0.5);
  Reloaded;
  AssertTrue('survives saving', FLoaded.FindObject('Panel').State = esValid);
end;

procedure TTestAccessories.TestCornerRoundTrip;
var
  V: string;
  Arc, Back: TCornerArc;
begin
  V := Pt('V', 100);
  Arc := FPattern.AddRoundCorner(Line(Pt('A'), V).Key, Line(V, Pt('B', 100, 100)).Key, '20');
  FPattern.Evaluate;
  Back := TCornerArc(Reloaded.FindNode(Arc.Key));
  AssertPointsNear('same', Vec2(80, 0), Back.PointAtLength(0));
  AssertEquals(SavePatternToText(FPattern), SavePatternToText(FLoaded));
end;

procedure TTestAccessories.TestMaterialAllowanceSetsPiece;
var
  Leather: TPatternMaterial;
  Piece: TPieceObject;
begin
  Rectangle;
  Piece := PieceAt(50, 50);
  Leather := FPattern.AddMaterial('Leather');
  AssertTrue(FPattern.SetMaterialAllowance(Leather, True, 3));
  FPattern.SetPieceMaterial(Piece, Leather);
  FPattern.Evaluate;
  AssertEquals('3', FPattern.FormulaText(Piece, PieceAllowanceField));
end;

procedure TTestAccessories.TestMaterialAllowanceForNewPiece;
begin
  AssertTrue(FPattern.SetMaterialAllowance(FPattern.Materials[0], True, 4.5));
  Rectangle;
  AssertEquals('4.5', FPattern.FormulaText(PieceAt(50, 50), PieceAllowanceField));
end;

procedure TTestAccessories.TestMaterialWithoutAllowanceLeavesPiece;
var
  Piece: TPieceObject;
begin
  Rectangle;
  Piece := PieceAt(50, 50);
  AssertTrue(FPattern.SetFormula(Piece, PieceAllowanceField, '12'));
  FPattern.SetPieceMaterial(Piece, FPattern.AddMaterial('Lining'));
  AssertEquals('12', FPattern.FormulaText(Piece, PieceAllowanceField));
end;

procedure TTestAccessories.TestExplicitAllowanceStands;
var
  Path: TPiecePath;
  Reason: string;
begin
  AssertTrue(FPattern.SetMaterialAllowance(FPattern.Materials[0], True, 3));
  Rectangle;
  AssertTrue(Reason, DetectPiecePath(FPattern, Vec2(50, 50), Path, Reason));
  AssertEquals('25', FPattern.FormulaText(FPattern.AddPiece('Panel', Path, '25'), PieceAllowanceField));
end;

procedure TTestAccessories.TestMaterialAllowanceRoundTrip;
begin
  AssertTrue(FPattern.SetMaterialAllowance(FPattern.AddMaterial('Leather'), True, 0));
  Reloaded;
  AssertTrue(FLoaded.Materials[1].HasAllowance);
  AssertEquals(0, FLoaded.Materials[1].Allowance, 1e-9);
  AssertFalse('the other has none', FLoaded.Materials[0].HasAllowance);
end;

procedure TTestAccessories.TestMaterialAllowanceRefusesNegative;
begin
  AssertFalse(FPattern.SetMaterialAllowance(FPattern.Materials[0], True, -1));
end;

procedure TTestAccessories.TestLeatherHasNoAllowance;
var
  Leather: TPatternMaterial;
  Piece: TPieceObject;
begin
  Rectangle;
  Piece := PieceAt(50, 50);
  Leather := FPattern.AddMaterial('Leather');
  AssertTrue(FPattern.SetMaterialAllowance(Leather, True, 0));
  FPattern.SetPieceMaterial(Piece, Leather);
  FPattern.Evaluate;
  AssertEquals('cut on the line', Piece.Area, Abs(SignedArea(Piece.CutLine)), 1);
end;

procedure TTestAccessories.TestHoleMarking;
var
  Piece: TPieceObject;
begin
  Rectangle;
  Piece := PieceAt(50, 50);
  AssertTrue(FPattern.LastError, FPattern.SetMarker(Pt('H', 50, 50), pmHole, '4'));
  FPattern.Evaluate;
  AssertTrue(Piece.Message, Piece.State = esValid);
  AssertEquals('joined the piece it lies in', 1, Length(Piece.MarkingMarks));
  AssertPointsNear('at its point', Vec2(50, 50), Piece.MarkingMarks[0].Holes[0]);
  AssertEquals(4, Piece.MarkingMarks[0].HoleSize, 1e-9);
end;

procedure TTestAccessories.TestHoleFollowsItsPoint;
var
  Piece: TPieceObject;
  Hole: string;
begin
  Rectangle;
  Piece := PieceAt(50, 50);
  Hole := Pt('H', 50, 50);
  AssertTrue(FPattern.SetMarker(Hole, pmHole, '4'));
  FPattern.Evaluate;
  AssertTrue(FPattern.SetFormula(FPattern.FindNode(Hole), 'x', '120'));
  FPattern.Evaluate;
  AssertPointsNear('moved', Vec2(120, 50), Piece.MarkingMarks[0].Holes[0]);
end;

procedure TTestAccessories.TestHoleOutsidePieceIsInvalid;
var
  Piece: TPieceObject;
  Hole: string;
begin
  Rectangle;
  Piece := PieceAt(50, 50);
  Hole := Pt('H', 500, 500);
  AssertTrue(FPattern.SetMarker(Hole, pmHole, '4'));
  FPattern.Evaluate;
  AssertEquals('not inside, so not joined', 0, Length(Piece.Markings));
  AssertTrue('by hand', FPattern.AddPointMarking(Piece, Hole));
  FPattern.Evaluate;
  AssertTrue(Piece.State = esInvalid);
end;

procedure TTestAccessories.TestHoleDiameterMustBePositive;
var
  Hole: string;
begin
  Rectangle;
  PieceAt(50, 50);
  Hole := Pt('H', 50, 50);
  AssertTrue(FPattern.SetMarker(Hole, pmHole, '0'));
  FPattern.Evaluate;
  AssertTrue(FPattern.FindNode(Hole).State = esInvalid);
  AssertEquals(rsDraftMarkerSize, FPattern.FindNode(Hole).Message);
end;

procedure TTestAccessories.TestPlacementLineFollowsEdge;
var
  Piece: TPieceObject;
  First, Pocket: string;
begin
  Rectangle;
  Piece := PieceAt(50, 50);
  First := Pt('P', 20, 50);
  Pocket := FPattern.AddLine(First, Pt('Q', 180, 50), erPlacement).Key;
  FPattern.Evaluate;
  AssertEquals('joined the piece', 0, Piece.LineMarkingOf(Pocket));
  AssertTrue(Piece.Message, Piece.State = esValid);
  AssertPointsNear('start', Vec2(20, 50), Piece.MarkingMarks[0].Line[0]);
  AssertTrue(FPattern.SetFormula(FPattern.FindNode(First), 'y', '70'));
  FPattern.Evaluate;
  AssertPointsNear('moved', Vec2(20, 70), Piece.MarkingMarks[0].Line[0]);
end;

procedure TTestAccessories.TestFoldLineMarking;
var
  Piece: TPieceObject;
begin
  Rectangle;
  Piece := PieceAt(50, 50);
  FPattern.AddLine(Pt('P', 100, 0), Pt('Q', 100, 100), erFold);
  FPattern.Evaluate;
  AssertTrue(Piece.MarkingMarks[0].Kind = mkLine);
  AssertTrue('drawn as a fold', Piece.MarkingMarks[0].Role = erFold);
end;

procedure TTestAccessories.TestStitchHolesSpaceEvenly;
var
  Piece: TPieceObject;
  Edge: string;
  Holes: TVec2Array;
  Index: integer;
begin
  Rectangle;
  Piece := PieceAt(50, 50);
  Edge := FPattern.AddLine(Pt('P', 20, 50), Pt('Q', 120, 50)).Key;
  AssertTrue(FPattern.LastError, FPattern.AddStitchMarking(Piece, Edge, '4', '1'));
  FPattern.Evaluate;
  Holes := Piece.MarkingMarks[0].Holes;
  AssertEquals('both ends and all between', 26, Length(Holes));
  for Index := 1 to High(Holes) do
    AssertEquals(4, Distance(Holes[Index - 1], Holes[Index]), 1e-6);
  AssertEquals(1, Piece.MarkingMarks[0].HoleSize, 1e-9);
end;

procedure TTestAccessories.TestStitchSpacingAdjustsToFit;
var
  Piece: TPieceObject;
  Holes: TVec2Array;
begin
  Rectangle;
  Piece := PieceAt(50, 50);
  AssertTrue(FPattern.AddStitchMarking(Piece, FPattern.AddLine(Pt('P', 20, 50), Pt('Q', 121, 50)).Key, '4', '1'));
  FPattern.Evaluate;
  Holes := Piece.MarkingMarks[0].Holes;
  AssertEquals(26, Length(Holes));
  AssertPointsNear('runs to the end', Vec2(121, 50), Holes[High(Holes)]);
  AssertEquals(101 / 25, Distance(Holes[0], Holes[1]), 1e-6);
end;

procedure TTestAccessories.TestStitchHolesFollowSize;
var
  Piece: TPieceObject;
  End2: string;
begin
  Rectangle;
  Piece := PieceAt(50, 50);
  End2 := Pt('Q', 120, 50);
  AssertTrue(FPattern.AddStitchMarking(Piece, FPattern.AddLine(Pt('P', 20, 50), End2).Key, '4', '1'));
  FPattern.Evaluate;
  AssertTrue(FPattern.SetFormula(FPattern.FindNode(End2), 'x', '180'));
  FPattern.Evaluate;
  AssertEquals(41, Length(Piece.MarkingMarks[0].Holes));
end;

procedure TTestAccessories.TestStitchSpacingMustBePositive;
var
  Piece: TPieceObject;
begin
  Rectangle;
  Piece := PieceAt(50, 50);
  AssertTrue(FPattern.AddStitchMarking(Piece, FPattern.AddLine(Pt('P', 20, 50), Pt('Q', 120, 50)).Key, '0', '1'));
  FPattern.Evaluate;
  AssertTrue(Piece.State = esInvalid);
end;

procedure TTestAccessories.TestPieceReportsHoleCount;
var
  Piece: TPieceObject;
begin
  Rectangle;
  Piece := PieceAt(50, 50);
  AssertTrue(FPattern.AddStitchMarking(Piece, FPattern.AddLine(Pt('P', 20, 50), Pt('Q', 120, 50)).Key, '4', '1'));
  AssertTrue(FPattern.SetMarker(Pt('H', 50, 60), pmHole, '4'));
  FPattern.Evaluate;
  AssertEquals('stitch holes only: thread goes through those', 26, Piece.PropertyValue('holes'), 1e-9);
end;

// As for a marking line, the piece lets a point it only marks go with it
procedure TTestAccessories.TestMarkingUsesItsInput;
var
  Piece: TPieceObject;
  Hole: string;
begin
  Rectangle;
  Piece := PieceAt(50, 50);
  Hole := Pt('H', 50, 50);
  AssertTrue(FPattern.SetMarker(Hole, pmHole, '4'));
  FPattern.Evaluate;
  AssertEquals(1, Length(Piece.Markings));
  AssertTrue(FPattern.LastError, FPattern.Delete(FPattern.FindNode(Hole)));
  AssertEquals('taken off', 0, Length(Piece.Markings));
end;

procedure TTestAccessories.TestRemoveMarkingRenumbers;
var
  Piece: TPieceObject;
begin
  Rectangle;
  Piece := PieceAt(50, 50);
  AssertTrue(FPattern.AddStitchMarking(Piece, FPattern.AddLine(Pt('P', 20, 50), Pt('Q', 120, 50)).Key, '4', '1'));
  AssertTrue(FPattern.AddStitchMarking(Piece, FPattern.AddLine(Pt('R', 20, 60), Pt('S', 120, 60)).Key, '5', '2'));
  AssertTrue(FPattern.RemoveMarking(Piece, 0));
  FPattern.Evaluate;
  AssertTrue(Piece.Message, Piece.State = esValid);
  AssertEquals(1, Length(Piece.Markings));
  AssertEquals('5', FPattern.FormulaText(Piece, Piece.MarkingField(0, MarkingSpacingField)));
  AssertEquals(2, Piece.MarkingMarks[0].HoleSize, 1e-9);
end;

procedure TTestAccessories.TestRemoveMissingMarkingRefused;
var
  Piece: TPieceObject;
begin
  Rectangle;
  Piece := PieceAt(50, 50);
  AssertFalse(FPattern.RemoveMarking(Piece, 0));
end;

procedure TTestAccessories.TestMarkingsRoundTrip;
var
  Piece, Back: TPieceObject;
begin
  Rectangle;
  Piece := PieceAt(50, 50);
  AssertTrue(FPattern.SetMarker(Pt('H', 50, 50), pmHole, '4'));
  FPattern.AddLine(Pt('P', 20, 50), Pt('Q', 120, 50), erPlacement);
  FPattern.AddLine(Pt('R', 20, 60), Pt('S', 120, 60), erFold);
  FPattern.Evaluate;
  AssertTrue(FPattern.AddStitchMarking(Piece, FPattern.AddLine(Pt('T', 20, 70), Pt('U', 120, 70)).Key, '5', '1.5'));
  FPattern.Evaluate;
  Back := TPieceObject(Reloaded.FindNode(Piece.Key));
  AssertTrue(Back.Message, Back.State = esValid);
  AssertEquals(4, Length(Back.Markings));
  AssertTrue(Back.Markings[3].Kind = mkStitchHoles);
  AssertEquals(21, Length(Back.MarkingMarks[3].Holes));
  AssertEquals(SavePatternToText(FPattern), SavePatternToText(FLoaded));
end;

procedure TTestAccessories.TestMarkingsDrawAsStrokes;
var
  Piece: TPieceObject;
  Before: integer;
begin
  Rectangle;
  Piece := PieceAt(50, 50);
  Before := Length(Piece.MarkingStrokes);
  AssertTrue(FPattern.SetMarker(Pt('H', 50, 50), pmHole, '4'));
  FPattern.Evaluate;
  AssertEquals(0, Before);
  AssertTrue('a circle of strokes', Length(Piece.MarkingStrokes) > 8);
end;

procedure TTestAccessories.TestRoleLineJoinsItsPiece;
var
  Piece: TPieceObject;
  Stitch: TLineObject;
begin
  Rectangle;
  Piece := PieceAt(50, 50);
  Stitch := FPattern.AddLine(Pt('P', 20, 20), Pt('Q', 180, 20), erStitch);
  AssertEquals('waits for evaluation', -1, Piece.LineMarkingOf(Stitch.Key));
  FPattern.Evaluate;
  AssertEquals('joined', 0, Piece.LineMarkingOf(Stitch.Key));
  AssertTrue(Piece.Message, Piece.State = esValid);
  AssertTrue('drawn as stitching', Piece.MarkingMarks[0].Role = erStitch);
  AssertEquals('listed', 1, Length(FPattern.PiecesWithMarking(Stitch.Key)));
end;

procedure TTestAccessories.TestLineInOverlappingPiecesJoinsBoth;
var
  Inner, Outer: TPieceObject;
  Edges: TRectangleEdges;
  Path: TPiecePath;
  Index: integer;
  Fold: TLineObject;
begin
  Rectangle;
  Inner := PieceAt(50, 50, 'Inner');
  // A larger piece drawn round the first, as a back drafted under a front
  AssertTrue(FPattern.LastError, FPattern.AddRectangle(Pt('Corner2', -50, -50), '300', '200', erOutline, Edges));
  Path := nil;
  SetLength(Path, 4);
  for Index := 0 to 3 do
    Path[Index].EdgeKey := Edges[Index].Key;
  Outer := FPattern.AddPiece('Outer', Path, '10');
  AssertNotNull(FPattern.LastError, Outer);
  FPattern.Evaluate;
  AssertTrue(Outer.Message, Outer.State = esValid);
  Fold := FPattern.AddLine(Pt('P', 100, 10), Pt('Q', 100, 90), erFold);
  FPattern.Evaluate;
  AssertTrue('inner', Inner.LineMarkingOf(Fold.Key) >= 0);
  AssertTrue('outer', Outer.LineMarkingOf(Fold.Key) >= 0);
end;

procedure TTestAccessories.TestLooseLineJoinsNewPiece;
var
  Piece: TPieceObject;
  MarkLine: TLineObject;
  Blocked: integer;
  Problem: string;
  Found: boolean;
begin
  Rectangle;
  MarkLine := FPattern.AddLine(Pt('P', 20, 50), Pt('Q', 120, 50), erPlacement);
  FPattern.Evaluate;
  AssertEquals('no piece yet', 0, Length(FPattern.PiecesWithMarking(MarkLine.Key)));
  Found := False;
  for Problem in PatternProblems(FPattern, Blocked) do
    Found := Found or (Problem = Format(rsCheckLineLoose, [MarkLine.DisplayName]));
  AssertTrue('reported as loose', Found);
  Piece := PieceAt(50, 20);
  AssertEquals('joins the new piece', 0, Piece.LineMarkingOf(MarkLine.Key));
end;

// Stored, so a measurement change cannot move a line to another piece
procedure TTestAccessories.TestAssignmentIsKept;
var
  Piece: TPieceObject;
  First: string;
  MarkLine: TLineObject;
  Blocked: integer;
  Problems: TStringArray;
begin
  Rectangle;
  Piece := PieceAt(50, 50);
  First := Pt('P', 20, 50);
  MarkLine := FPattern.AddLine(First, Pt('Q', 120, 50), erPlacement);
  FPattern.Evaluate;
  AssertTrue(FPattern.SetFormula(FPattern.FindNode(First), 'y', '400'));
  AssertTrue(FPattern.SetFormula(FPattern.FindNode(MarkLine.EndKey), 'y', '400'));
  FPattern.Evaluate;
  AssertEquals('still marked', 0, Piece.LineMarkingOf(MarkLine.Key));
  Problems := PatternProblems(FPattern, Blocked);
  AssertEquals(1, Length(Problems));
  AssertEquals(Format(rsCheckLineOutside, [MarkLine.DisplayName, Piece.DisplayName]), Problems[0]);
end;

procedure TTestAccessories.TestOtherRoleDetaches;
var
  Piece: TPieceObject;
  MarkLine: TLineObject;
begin
  Rectangle;
  Piece := PieceAt(50, 50);
  MarkLine := FPattern.AddLine(Pt('P', 20, 50), Pt('Q', 120, 50), erPlacement);
  FPattern.Evaluate;
  AssertTrue(FPattern.SetEdgeRole(MarkLine, erCut));
  FPattern.Evaluate;
  AssertEquals('another marking role keeps it', 0, Piece.LineMarkingOf(MarkLine.Key));
  AssertTrue(Piece.MarkingMarks[0].Role = erCut);
  AssertTrue(FPattern.SetEdgeRole(MarkLine, erConstruction));
  FPattern.Evaluate;
  AssertEquals('construction takes it off', 0, Length(Piece.Markings));
  AssertTrue(FPattern.SetEdgeRole(MarkLine, erStitch));
  FPattern.Evaluate;
  AssertEquals('and back on', 0, Piece.LineMarkingOf(MarkLine.Key));
end;

procedure TTestAccessories.TestDeletingLineDetaches;
var
  Piece: TPieceObject;
  MarkLine: TLineObject;
  Edges: TRectangleEdges;
begin
  Edges := Rectangle;
  Piece := PieceAt(50, 50);
  MarkLine := FPattern.AddLine(Pt('P', 20, 50), Pt('Q', 120, 50), erStitch);
  FPattern.Evaluate;
  AssertTrue(FPattern.LastError, FPattern.Delete(MarkLine));
  FPattern.Evaluate;
  AssertEquals(0, Length(Piece.Markings));
  AssertTrue(Piece.Message, Piece.State = esValid);
  AssertFalse('an outline edge is still in use', FPattern.Delete(Edges[0]));
end;

procedure TTestAccessories.TestAttachNeedsMarkingRole;
var
  Piece: TPieceObject;
  MarkLine: TLineObject;
begin
  Rectangle;
  Piece := PieceAt(50, 50);
  MarkLine := FPattern.AddLine(Pt('P', 20, 50), Pt('Q', 120, 50));
  AssertFalse(FPattern.AddLineMarking(Piece, MarkLine.Key));
  AssertEquals(Format(rsPatternNotMarkingLine, [MarkLine.DisplayName]), FPattern.LastError);
end;

// Outside every piece, so only by hand
procedure TTestAccessories.TestAttachByHand;
var
  Piece: TPieceObject;
  MarkLine: TLineObject;
begin
  Rectangle;
  Piece := PieceAt(50, 50);
  MarkLine := FPattern.AddLine(Pt('P', 20, 300), Pt('Q', 120, 300), erPlacement);
  FPattern.Evaluate;
  AssertEquals(0, Length(Piece.Markings));
  AssertTrue(FPattern.LastError, FPattern.AddLineMarking(Piece, MarkLine.Key));
  AssertFalse('only once', FPattern.AddLineMarking(Piece, MarkLine.Key));
  FPattern.Evaluate;
  AssertTrue(Piece.Message, Piece.State = esValid);
end;

procedure TTestAccessories.TestOldPlacementBecomesRole;
var
  Piece: TPieceObject;
  MarkLine: TLineObject;
  Text, Reason: string;
  Back: TLineObject;
begin
  Rectangle;
  Piece := PieceAt(50, 50);
  MarkLine := FPattern.AddLine(Pt('P', 20, 50), Pt('Q', 120, 50), erPlacement);
  FPattern.Evaluate;
  // As an older file wrote it: a construction line marked on the piece
  Text := StringReplace(SavePatternToText(FPattern), '"role": "placement"', '"role": "construction"', []);
  Text := StringReplace(Text, '"kind": "line"', '"kind": "fold"', []);
  FreeAndNil(FLoaded);
  FLoaded := TPattern.Create;
  AssertTrue(Reason, LoadPatternFromText(FLoaded, Text, Reason));
  FLoaded.Evaluate;
  Back := TLineObject(FLoaded.FindNode(MarkLine.Key));
  AssertTrue('takes the marking''s role', Back.Role = erFold);
  AssertEquals(0, TPieceObject(FLoaded.FindNode(Piece.Key)).LineMarkingOf(MarkLine.Key));
  AssertTrue('saved the new way', Pos('"kind": "line"', SavePatternToText(FLoaded)) > 0);
end;

procedure TTestAccessories.TestRolesRoundTrip;
var
  Role: TEdgeRole;
  MarkLine: TLineObject;
  Keys: array[TEdgeRole] of string;
begin
  Rectangle;
  PieceAt(50, 50);
  for Role := Low(TEdgeRole) to High(TEdgeRole) do
  begin
    MarkLine := FPattern.AddLine(Pt('', 20, 10 + 10 * Ord(Role)), Pt('', 120, 10 + 10 * Ord(Role)), Role);
    Keys[Role] := MarkLine.Key;
  end;
  FPattern.Evaluate;
  Reloaded;
  for Role := Low(TEdgeRole) to High(TEdgeRole) do
    AssertTrue(TEdgeObject(FLoaded.FindNode(Keys[Role])).Role = Role);
  AssertEquals(SavePatternToText(FPattern), SavePatternToText(FLoaded));
end;

initialization
  RegisterTest(TTestAccessories);
end.
