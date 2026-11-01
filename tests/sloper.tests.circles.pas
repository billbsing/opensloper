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

unit Sloper.Tests.Circles;

{$mode ObjFPC}{$H+}

interface

uses
  SysUtils, fpcunit, testregistry, Sloper.Tests.TestCase, Sloper.Core.Geometry, Sloper.Core.Pattern, Sloper.Core.Draft,
  Sloper.Core.Piece;

type
  TTestCircles = class(TOSTestCase)
  private
    FPattern, FLoaded: TPattern;
    function Pt(const AName: string; X: double = 0; Y: double = 0): string;
    function Circle(const CentreKey: string; const Radius: string = '50'): TCircleObject;
    function Reloaded: TPattern;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestCircleLengthIsExact;
    procedure TestCircleHasRadiusProperty;
    procedure TestCircleStaysOnItsRadius;
    procedure TestCircleIsClosed;
    procedure TestCircleFollowsItsCentre;
    procedure TestCircleRadiusFollowsVariable;
    procedure TestRadiusMustBePositive;
    procedure TestCircleName;
    procedure TestArcEnds;
    procedure TestArcLengthIsExact;
    procedure TestArcRunsClockwiseWhenAngleFalls;
    procedure TestArcIsNotClosed;
    procedure TestArcRefusesNoSweep;
    procedure TestArcRefusesFullTurn;
    procedure TestPointAlongArcGivesItsEnd;
    procedure TestLineJoinsArcEndAndFollowsIt;
    procedure TestRoundTrip;
    procedure TestCircleCopiedByTransform;
    procedure TestCircleCirclePick;
    procedure TestCircleCircleFollowsFormula;
    procedure TestCircleCircleApartIsInvalid;
    procedure TestCircleCircleTouching;
    procedure TestCircleCircleConcentricIsInvalid;
    procedure TestCircleCircleRoundTrip;
    procedure TestCircleIsAPiece;
    procedure TestCirclePieceHasItsArea;
    procedure TestPieceOnOneOpenEdgeRefused;
    procedure TestSmallerFaceWinsOverCircle;
    procedure TestCircleInsideRectangleWins;
    procedure TestOutsideCircleIsNoPiece;
    procedure TestCircleCrossedByLineGivesFace;
    procedure TestSeamUsesCircle;
    procedure TestPieceFromArcAndLine;
  end;

implementation

uses
  Math, Sloper.Core.EvalTypes, Sloper.Core.PatternFile, Sloper.Core.PieceDetect, Sloper.Core.Seam, Sloper.Core.Transform;

procedure TTestCircles.SetUp;
begin
  inherited SetUp;
  FPattern := TPattern.Create;
end;

procedure TTestCircles.TearDown;
begin
  FreeAndNil(FLoaded);
  FreeAndNil(FPattern);
  inherited TearDown;
end;

function TTestCircles.Pt(const AName: string; X, Y: double): string;
begin
  Result := FPattern.AddFreePoint(AName, FloatToStr(X), FloatToStr(Y)).Key;
end;

function TTestCircles.Circle(const CentreKey, Radius: string): TCircleObject;
begin
  Result := FPattern.AddCircle(CentreKey, Radius, erOutline);
  AssertNotNull(FPattern.LastError, Result);
  FPattern.Evaluate;
end;

function TTestCircles.Reloaded: TPattern;
var
  Reason: string;
begin
  FreeAndNil(FLoaded);
  FLoaded := TPattern.Create;
  AssertTrue(Reason, LoadPatternFromText(FLoaded, SavePatternToText(FPattern), Reason));
  FLoaded.Evaluate;
  Result := FLoaded;
end;

procedure TTestCircles.TestCircleLengthIsExact;
var
  Edge: TCircleObject;
begin
  Edge := Circle(Pt('O'));
  AssertEquals(2 * Pi * 50, Edge.PropertyValue('length'), 1e-9);
  AssertEquals('the segments agree', 2 * Pi * 50, Edge.Length, 1e-3);
end;

procedure TTestCircles.TestCircleHasRadiusProperty;
begin
  AssertEquals(50, Circle(Pt('O')).PropertyValue('radius'), 1e-9);
end;

procedure TTestCircles.TestCircleStaysOnItsRadius;
var
  Edge: TCircleObject;
  Index: integer;
begin
  Edge := Circle(Pt('O', 10, 20));
  for Index := 0 to 36 do
    AssertEquals(50, Distance(Edge.PointAtLength(Edge.Length * Index / 36), Vec2(10, 20)), 1e-3);
end;

procedure TTestCircles.TestCircleIsClosed;
begin
  AssertTrue(Circle(Pt('O')).IsClosed);
end;

procedure TTestCircles.TestCircleFollowsItsCentre;
var
  Centre: string;
  Edge: TCircleObject;
begin
  Centre := Pt('O');
  Edge := Circle(Centre);
  AssertTrue(FPattern.SetFormula(FPattern.FindNode(Centre), 'x', '100'));
  FPattern.Evaluate;
  AssertEquals(100, Distance(Edge.PointAtLength(0), Vec2(0, 0)) - 50, 1e-6);
end;

procedure TTestCircles.TestCircleRadiusFollowsVariable;
var
  Edge: TCircleObject;
begin
  FPattern.AddVariable('size', '30');
  Edge := Circle(Pt('O'), '#size * 2');
  AssertEquals(60, Edge.PropertyValue('radius'), 1e-9);
end;

procedure TTestCircles.TestRadiusMustBePositive;
var
  Edge: TCircleObject;
begin
  Edge := Circle(Pt('O'), '0');
  AssertTrue(Edge.State = esInvalid);
end;

procedure TTestCircles.TestCircleName;
begin
  AssertEquals('Circle_O', Circle(Pt('O')).Name);
  AssertEquals('a second gets the next number', 'Circle_O2', Circle(FPattern.FindObject('O').Key).Name);
end;

procedure TTestCircles.TestArcEnds;
var
  Edge: TArcObject;
begin
  Edge := FPattern.AddArc(Pt('O', 10, 0), '50', '0', '90', erOutline);
  FPattern.Evaluate;
  AssertPointsNear('position', Vec2(60, 0), Edge.PointAtLength(0));
  AssertPointsNear('position', Vec2(10, 50), Edge.PointAtLength(Edge.Length));
end;

procedure TTestCircles.TestArcLengthIsExact;
var
  Edge: TArcObject;
begin
  Edge := FPattern.AddArc(Pt('O'), '50', '30', '100', erOutline);
  FPattern.Evaluate;
  AssertEquals(50 * DegToRad(70), Edge.PropertyValue('length'), 1e-9);
end;

procedure TTestCircles.TestArcRunsClockwiseWhenAngleFalls;
var
  Edge: TArcObject;
begin
  Edge := FPattern.AddArc(Pt('O'), '50', '90', '0', erOutline);
  FPattern.Evaluate;
  AssertPointsNear('position', Vec2(0, 50), Edge.PointAtLength(0));
  AssertPointsNear('position', Vec2(50, 0), Edge.PointAtLength(Edge.Length));
  AssertPointsNear('position', Vec2(50 * Cos(DegToRad(45)), 50 * Sin(DegToRad(45))), Edge.PointAtLength(Edge.Length / 2));
end;

procedure TTestCircles.TestArcIsNotClosed;
var
  Edge: TArcObject;
begin
  Edge := FPattern.AddArc(Pt('O'), '50', '0', '270', erOutline);
  FPattern.Evaluate;
  AssertFalse(Edge.IsClosed);
end;

procedure TTestCircles.TestArcRefusesNoSweep;
var
  Edge: TArcObject;
begin
  Edge := FPattern.AddArc(Pt('O'), '50', '40', '40', erOutline);
  FPattern.Evaluate;
  AssertTrue(Edge.State = esInvalid);
end;

procedure TTestCircles.TestArcRefusesFullTurn;
var
  Edge: TArcObject;
begin
  Edge := FPattern.AddArc(Pt('O'), '50', '0', '360', erOutline);
  FPattern.Evaluate;
  AssertTrue('that is a circle', Edge.State = esInvalid);
end;

procedure TTestCircles.TestPointAlongArcGivesItsEnd;
var
  Edge: TArcObject;
  EndPoint: TAlongEdgePoint;
begin
  Edge := FPattern.AddArc(Pt('O'), '50', '0', '90', erOutline);
  EndPoint := FPattern.AddAlongEdgePoint('E', Edge.Key, True, amLength, '0');
  FPattern.Evaluate;
  AssertPointsNear('position', Vec2(0, 50), EndPoint.Position);
end;

procedure TTestCircles.TestLineJoinsArcEndAndFollowsIt;
var
  Edge: TArcObject;
  EndPoint: TAlongEdgePoint;
  Line: TLineObject;
begin
  Edge := FPattern.AddArc(Pt('O'), '50', '0', '90', erOutline);
  EndPoint := FPattern.AddAlongEdgePoint('E', Edge.Key, True, amLength, '0');
  Line := FPattern.AddLine(EndPoint.Key, Pt('F', 200, 50), erOutline);
  FPattern.Evaluate;
  AssertTrue(FPattern.SetFormula(Edge, 'radius', '80'));
  FPattern.Evaluate;
  AssertPointsNear('position', Vec2(0, 80), Line.PointAtLength(0));
end;

procedure TTestCircles.TestRoundTrip;
var
  Back: TArcObject;
begin
  Circle(Pt('O'), '40');
  FPattern.AddArc(FPattern.FindObject('O').Key, '30', '10', '100', erOutline, 'Flap');
  FPattern.Evaluate;
  Reloaded;
  AssertEquals(40, TCircleObject(FLoaded.FindObject('Circle_O')).PropertyValue('radius'), 1e-9);
  Back := TArcObject(FLoaded.FindObject('Flap'));
  AssertEquals(30 * DegToRad(90), Back.PropertyValue('length'), 1e-9);
  AssertTrue(Back.Role = erOutline);
  AssertEquals('saves the same', SavePatternToText(FPattern), SavePatternToText(FLoaded));
end;

procedure TTestCircles.TestCircleCopiedByTransform;
var
  Edge: TCircleObject;
  Spec: TTransformSpec;
  Moved: TTransformObject;
  Copy: TDraftObject;
begin
  Edge := Circle(Pt('O'));
  Spec := Default(TTransformSpec);
  Spec.Kind := tkMove;
  Spec.DX := '100';
  Spec.DY := '0';
  Spec.Sources := [Edge.Key];
  Moved := FPattern.AddTransform(Spec);
  AssertNotNull(FPattern.LastError, Moved);
  FPattern.Evaluate;
  Copy := FPattern.FindObject('Circle_O_t1');
  AssertNotNull(Copy);
  AssertPointsNear('position', Vec2(150, 0), TEdgeObject(Copy).PointAtLength(0));
  AssertTrue('a copy of a circle closes too', TEdgeObject(Copy).IsClosed);
end;

procedure TTestCircles.TestCircleCirclePick;
var
  A, B: string;
  Left, Right: TCircleCirclePoint;
begin
  A := Pt('A');
  B := Pt('B', 60);
  Left := FPattern.AddCircleCirclePoint('L', A, '50', B, '50', 1);
  Right := FPattern.AddCircleCirclePoint('R', A, '50', B, '50', 2);
  FPattern.Evaluate;
  AssertPointsNear('position', Vec2(30, 40), Left.Position);
  AssertPointsNear('position', Vec2(30, -40), Right.Position);
end;

procedure TTestCircles.TestCircleCircleFollowsFormula;
var
  Point: TCircleCirclePoint;
begin
  Point := FPattern.AddCircleCirclePoint('L', Pt('A'), '50', Pt('B', 60), '50', 1);
  FPattern.Evaluate;
  AssertTrue(FPattern.SetFormula(Point, 'radiusA', '58.309518948'));
  FPattern.Evaluate;
  AssertEquals(58.309518948, Distance(Point.Position, Vec2(0, 0)), 1e-6);
  AssertEquals(50, Distance(Point.Position, Vec2(60, 0)), 1e-6);
end;

procedure TTestCircles.TestCircleCircleApartIsInvalid;
var
  Point: TCircleCirclePoint;
begin
  Point := FPattern.AddCircleCirclePoint('L', Pt('A'), '10', Pt('B', 100), '10', 1);
  FPattern.Evaluate;
  AssertTrue(Point.State = esInvalid);
end;

procedure TTestCircles.TestCircleCircleTouching;
var
  First, Second: TCircleCirclePoint;
begin
  First := FPattern.AddCircleCirclePoint('L', Pt('A'), '50', Pt('B', 100), '50', 1);
  Second := FPattern.AddCircleCirclePoint('M', FPattern.FindObject('A').Key, '50', FPattern.FindObject('B').Key, '50', 2);
  FPattern.Evaluate;
  AssertPointsNear('position', Vec2(50, 0), First.Position);
  AssertTrue('only one crossing', Second.State = esInvalid);
end;

procedure TTestCircles.TestCircleCircleConcentricIsInvalid;
var
  Point: TCircleCirclePoint;
begin
  Point := FPattern.AddCircleCirclePoint('L', Pt('A'), '50', Pt('B'), '50', 1);
  FPattern.Evaluate;
  AssertTrue(Point.State = esInvalid);
end;

procedure TTestCircles.TestCircleCircleRoundTrip;
var
  Back: TCircleCirclePoint;
begin
  FPattern.AddCircleCirclePoint('L', Pt('A'), '50', Pt('B', 60), '50', 2);
  FPattern.Evaluate;
  Back := TCircleCirclePoint(Reloaded.FindObject('L'));
  AssertEquals(2, Back.Pick);
  AssertPointsNear('position', Vec2(30, -40), Back.Position);
end;

procedure TTestCircles.TestCircleIsAPiece;
var
  Edge: TCircleObject;
  Path: TPiecePath;
  Reason: string;
  Piece: TPieceObject;
begin
  Edge := Circle(Pt('O'));
  AssertTrue(Reason, DetectPiecePath(FPattern, Vec2(5, 5), Path, Reason));
  AssertEquals(1, Length(Path));
  AssertEquals(Edge.Key, Path[0].EdgeKey);
  Piece := FPattern.AddPiece('Base', Path, '10');
  AssertNotNull(FPattern.LastError, Piece);
  FPattern.Evaluate;
  AssertTrue(Piece.Message, Piece.State = esValid);
  Reloaded;
  AssertTrue('survives saving', FLoaded.FindObject('Base').State = esValid);
end;

procedure TTestCircles.TestCirclePieceHasItsArea;
var
  Path: TPiecePath;
  Reason: string;
  Piece: TPieceObject;
begin
  Circle(Pt('O'));
  AssertTrue(Reason, DetectPiecePath(FPattern, Vec2(5, 5), Path, Reason));
  Piece := FPattern.AddPiece('Base', Path, '10');
  FPattern.Evaluate;
  AssertEquals('within 0.1%, from the flattened outline', Pi * 2500, Piece.Area, Pi * 2.5);
  AssertEquals('seam allowance outward', Pi * 3600, Abs(SignedArea(Piece.CutLine)), Pi * 3.6);
end;

procedure TTestCircles.TestPieceOnOneOpenEdgeRefused;
var
  Line: TLineObject;
  Path: TPiecePath;
begin
  Line := FPattern.AddLine(Pt('A'), Pt('B', 100), erOutline);
  FPattern.Evaluate;
  Path := nil;
  SetLength(Path, 1);
  Path[0].EdgeKey := Line.Key;
  AssertTrue(FPattern.AddPiece('Bad', Path, '10') = nil);
  AssertEquals(rsPatternPieceTooShort, FPattern.LastError);
end;

// A square inside a circle: a click in the square means the square
procedure TTestCircles.TestSmallerFaceWinsOverCircle;
var
  Corners: array[0..3] of string;
  Index: integer;
  Path: TPiecePath;
  Reason: string;
begin
  Circle(Pt('O'), '100');
  Corners[0] := Pt('A', -20, -20);
  Corners[1] := Pt('B', 20, -20);
  Corners[2] := Pt('C', 20, 20);
  Corners[3] := Pt('D', -20, 20);
  for Index := 0 to 3 do
    FPattern.AddLine(Corners[Index], Corners[(Index + 1) mod 4], erOutline);
  FPattern.Evaluate;
  AssertTrue(Reason, DetectPiecePath(FPattern, Vec2(0, 0), Path, Reason));
  AssertEquals(4, Length(Path));
end;

procedure TTestCircles.TestCircleInsideRectangleWins;
var
  Corners: array[0..3] of string;
  Index: integer;
  Path: TPiecePath;
  Reason: string;
begin
  Circle(Pt('O'), '20');
  Corners[0] := Pt('A', -100, -100);
  Corners[1] := Pt('B', 100, -100);
  Corners[2] := Pt('C', 100, 100);
  Corners[3] := Pt('D', -100, 100);
  for Index := 0 to 3 do
    FPattern.AddLine(Corners[Index], Corners[(Index + 1) mod 4], erOutline);
  FPattern.Evaluate;
  AssertTrue(Reason, DetectPiecePath(FPattern, Vec2(0, 0), Path, Reason));
  AssertEquals('the circle', 1, Length(Path));
  AssertTrue(Reason, DetectPiecePath(FPattern, Vec2(60, 60), Path, Reason));
  AssertEquals('outside it, the rectangle', 4, Length(Path));
end;

procedure TTestCircles.TestOutsideCircleIsNoPiece;
var
  Path: TPiecePath;
  Reason: string;
begin
  Circle(Pt('O'));
  AssertFalse(DetectPiecePath(FPattern, Vec2(80, 0), Path, Reason));
end;

// The line cuts the circle at its two crossings, so the half has whole-edge
// trouble and is refused until the circle is split there
procedure TTestCircles.TestCircleCrossedByLineGivesFace;
var
  Path: TPiecePath;
  Reason: string;
begin
  Circle(Pt('O'));
  FPattern.AddLine(Pt('A', -100, 0.5), Pt('B', 100, 0.5), erOutline);
  FPattern.Evaluate;
  AssertFalse('needs splitting', DetectPiecePath(FPattern, Vec2(0, 20), Path, Reason));
  AssertTrue(Reason, Reason <> '');
end;

procedure TTestCircles.TestSeamUsesCircle;
var
  First, Second: TPieceObject;
  Path: TPiecePath;
  Reason: string;
  SideA, SideB: TSeamSide;
  Seam: TSeamObject;
begin
  Circle(Pt('O'), '50');
  AssertTrue(Reason, DetectPiecePath(FPattern, Vec2(0, 0), Path, Reason));
  First := FPattern.AddPiece('Base', Path, '10');
  Circle(Pt('P', 300), '50');
  AssertTrue(Reason, DetectPiecePath(FPattern, Vec2(300, 0), Path, Reason));
  Second := FPattern.AddPiece('Lid', Path, '10');
  SideA := nil;
  SideB := nil;
  SetLength(SideA, 1);
  SetLength(SideB, 1);
  SideA[0].PieceKey := First.Key;
  SideA[0].EdgeKey := First.Path[0].EdgeKey;
  SideB[0].PieceKey := Second.Key;
  SideB[0].EdgeKey := Second.Path[0].EdgeKey;
  Seam := FPattern.AddSeam('', SideA, SideB);
  AssertNotNull(FPattern.LastError, Seam);
  FPattern.Evaluate;
  AssertTrue(Seam.Message, Seam.State = esValid);
  AssertEquals(2 * Pi * 50, Seam.LengthA, 1e-3);
  AssertFalse(Seam.OutOfTolerance);
end;

procedure TTestCircles.TestPieceFromArcAndLine;
var
  Edge: TArcObject;
  First, Last: TAlongEdgePoint;
  Path: TPiecePath;
  Reason: string;
  Piece: TPieceObject;
begin
  Edge := FPattern.AddArc(Pt('O'), '50', '0', '180', erOutline);
  First := FPattern.AddAlongEdgePoint('F', Edge.Key, False, amLength, '0');
  Last := FPattern.AddAlongEdgePoint('L', Edge.Key, True, amLength, '0');
  FPattern.AddLine(Last.Key, First.Key, erOutline);
  FPattern.Evaluate;
  AssertTrue(Reason, DetectPiecePath(FPattern, Vec2(0, 10), Path, Reason));
  AssertEquals(2, Length(Path));
  Piece := FPattern.AddPiece('Half', Path, '5');
  FPattern.Evaluate;
  AssertTrue(Piece.Message, Piece.State = esValid);
  AssertEquals(Pi * 1250, Piece.Area, Pi * 2.5);
end;

initialization
  RegisterTest(TTestCircles);
end.
