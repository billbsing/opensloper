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

unit Sloper.Tests.Geometry;

{$mode ObjFPC}{$H+}

interface

uses
  fpcunit, testregistry, Sloper.Tests.TestCase, Sloper.Core.Geometry;

type
  TTestGeometry = class(TOSTestCase)
  published
    procedure TestVectorArithmetic;
    procedure TestDotAndCross;
    procedure TestDistance;
    procedure TestPolarPointAnglesAreAnticlockwise;
    procedure TestAngleBetweenIsInRange;
    procedure TestNormalizeAngle;
    procedure TestPointsNearUsesTolerance;
    procedure TestRotatePoint;
    procedure TestMirrorPoint;
    procedure TestLineLengthAndAngle;
    procedure TestLinePointAtLength;
    procedure TestLineClosestPoint;
    procedure TestIntersectCrossingLines;
    procedure TestIntersectParallelLinesFails;
    procedure TestIntersectNeedsExtend;
    procedure TestIntersectAtSharedEnd;
    procedure TestLineCircleTwoCrossings;
    procedure TestLineCircleTangent;
    procedure TestLineCircleMiss;
    procedure TestLineCircleSegmentLimits;
    procedure TestSignedAreaAndOrientation;
    procedure TestPointInPolygon;
    procedure TestPolylineLength;
  end;

implementation

// Anticlockwise on screen: right, then up, which is towards smaller y
function Square: TVec2Array;
begin
  Result := nil;
  SetLength(Result, 4);
  Result[0] := Vec2(0, 0);
  Result[1] := Vec2(100, 0);
  Result[2] := Vec2(100, -100);
  Result[3] := Vec2(0, -100);
end;

procedure TTestGeometry.TestVectorArithmetic;
begin
  AssertPointsNear('add', Vec2(4, 6), Vec2(1, 2) + Vec2(3, 4));
  AssertPointsNear('subtract', Vec2(-2, -2), Vec2(1, 2) - Vec2(3, 4));
  AssertPointsNear('negate', Vec2(-1, 2), -Vec2(1, -2));
  AssertPointsNear('scale', Vec2(2.5, 5), Vec2(1, 2) * 2.5);
  AssertPointsNear('lerp', Vec2(2.5, 5), Lerp(Vec2(0, 0), Vec2(10, 20), 0.25));
end;

procedure TTestGeometry.TestDotAndCross;
begin
  AssertNear('dot', 11, Dot(Vec2(1, 2), Vec2(3, 4)));
  AssertNear('cross', -2, Cross(Vec2(1, 2), Vec2(3, 4)));
  AssertNear('cross anticlockwise is positive', 1, Cross(Vec2(1, 0), Vec2(0, 1)));
end;

procedure TTestGeometry.TestDistance;
begin
  AssertNear('3-4-5', 5, Distance(Vec2(1, 1), Vec2(4, 5)));
  AssertNear('same point', 0, Distance(Vec2(7, 7), Vec2(7, 7)));
end;

procedure TTestGeometry.TestPolarPointAnglesAreAnticlockwise;
begin
  AssertPointsNear('0 deg points right', Vec2(110, 0), PolarPoint(Vec2(10, 0), 100, 0));
  AssertPointsNear('90 deg points up', Vec2(0, -50), PolarPoint(Vec2(0, 0), 50, 90));
  AssertPointsNear('180 deg points left', Vec2(-50, 0), PolarPoint(Vec2(0, 0), 50, 180));
end;

procedure TTestGeometry.TestAngleBetweenIsInRange;
begin
  AssertNear('right', 0, AngleBetween(Vec2(0, 0), Vec2(10, 0)));
  AssertNear('up', 90, AngleBetween(Vec2(0, 0), Vec2(0, -10)));
  AssertNear('down', 270, AngleBetween(Vec2(0, 0), Vec2(0, 10)));
end;

procedure TTestGeometry.TestNormalizeAngle;
begin
  AssertNear('negative', 270, NormalizeAngle(-90));
  AssertNear('over 360', 45, NormalizeAngle(405));
  AssertNear('360 is 0', 0, NormalizeAngle(360));
  AssertNear('large negative', 10, NormalizeAngle(-710));
  // A rounding error just below 0 must not come back as 359.999...
  AssertNear('tiny negative', 0, NormalizeAngle(-1e-12));
  AssertNear('just under 360', 0, NormalizeAngle(360 - 1e-12));
end;

procedure TTestGeometry.TestPointsNearUsesTolerance;
begin
  AssertTrue('within', PointsNear(Vec2(0, 0), Vec2(0.0005, 0)));
  AssertFalse('outside', PointsNear(Vec2(0, 0), Vec2(0.002, 0)));
end;

procedure TTestGeometry.TestRotatePoint;
begin
  AssertPointsNear('90 about origin turns up', Vec2(0, -10), RotatePoint(Vec2(10, 0), Vec2(0, 0), 90));
  AssertPointsNear('180 about pivot', Vec2(0, 10), RotatePoint(Vec2(20, 10), Vec2(10, 10), 180));
  AssertPointsNear('-90 is clockwise, so down', Vec2(0, 10), RotatePoint(Vec2(10, 0), Vec2(0, 0), -90));
end;

procedure TTestGeometry.TestMirrorPoint;
begin
  AssertPointsNear('vertical axis', Vec2(-3, 5), MirrorPoint(Vec2(3, 5), Vec2(0, 0), Vec2(0, 1)));
  AssertPointsNear('45 deg axis swaps x and y', Vec2(5, 3),
    MirrorPoint(Vec2(3, 5), Vec2(0, 0), Vec2(10, 10)));
  AssertPointsNear('point on axis stays', Vec2(4, 4),
    MirrorPoint(Vec2(4, 4), Vec2(0, 0), Vec2(1, 1)));
end;

procedure TTestGeometry.TestLineLengthAndAngle;
var
  L: TLine2;
begin
  L := Line2(Vec2(10, -10), Vec2(10, 20));
  AssertNear('length', 30, L.Length);
  AssertNear('straight down', 270, L.Angle);
end;

procedure TTestGeometry.TestLinePointAtLength;
var
  L: TLine2;
begin
  L := Line2(Vec2(0, 0), Vec2(30, 40));
  AssertPointsNear('10 mm along', Vec2(6, 8), L.PointAtLength(10));
  AssertPointsNear('past the end', Vec2(60, 80), L.PointAtLength(100));
  AssertPointsNear('midpoint', Vec2(15, 20), L.PointAt(0.5));
end;

procedure TTestGeometry.TestLineClosestPoint;
var
  L: TLine2;
begin
  L := Line2(Vec2(0, 0), Vec2(100, 0));
  AssertNear('param', 0.3, L.ParamOf(Vec2(30, 25)));
  AssertPointsNear('foot', Vec2(30, 0), L.ClosestPoint(Vec2(30, 25), False));
  AssertPointsNear('clamped', Vec2(100, 0), L.ClosestPoint(Vec2(150, 25), False));
  AssertPointsNear('extended', Vec2(150, 0), L.ClosestPoint(Vec2(150, 25), True));
end;

procedure TTestGeometry.TestIntersectCrossingLines;
var
  Hit: TIntersection;
begin
  AssertTrue(IntersectLines(Line2(Vec2(0, 0), Vec2(100, 100)),
    Line2(Vec2(0, 100), Vec2(100, 0)), False, False, Hit));
  AssertPointsNear('point', Vec2(50, 50), Hit.Point);
  AssertNear('T1', 0.5, Hit.T1);
  AssertNear('T2', 0.5, Hit.T2);
end;

procedure TTestGeometry.TestIntersectParallelLinesFails;
var
  Hit: TIntersection;
begin
  AssertFalse('parallel', IntersectLines(Line2(Vec2(0, 0), Vec2(100, 0)),
    Line2(Vec2(0, 10), Vec2(100, 10)), True, True, Hit));
  AssertFalse('collinear', IntersectLines(Line2(Vec2(0, 0), Vec2(100, 0)),
    Line2(Vec2(50, 0), Vec2(150, 0)), True, True, Hit));
end;

procedure TTestGeometry.TestIntersectNeedsExtend;
var
  A, B: TLine2;
  Hit: TIntersection;
begin
  A := Line2(Vec2(0, 0), Vec2(10, 0));
  B := Line2(Vec2(50, 10), Vec2(50, 20));
  AssertFalse('segments', IntersectLines(A, B, False, False, Hit));
  AssertFalse('only A extended', IntersectLines(A, B, True, False, Hit));
  AssertTrue('both extended', IntersectLines(A, B, True, True, Hit));
  AssertPointsNear('point', Vec2(50, 0), Hit.Point);
  AssertNear('T1 beyond end', 5, Hit.T1);
  AssertNear('T2 before start', -1, Hit.T2);
end;

procedure TTestGeometry.TestIntersectAtSharedEnd;
var
  Hit: TIntersection;
begin
  AssertTrue(IntersectLines(Line2(Vec2(0, 0), Vec2(100, 0)),
    Line2(Vec2(100, 0), Vec2(100, 100)), False, False, Hit));
  AssertPointsNear('corner', Vec2(100, 0), Hit.Point);
end;

procedure TTestGeometry.TestLineCircleTwoCrossings;
var
  Hits: TIntersectionArray;
begin
  Hits := IntersectLineCircle(Line2(Vec2(-200, 0), Vec2(200, 0)), False, Vec2(0, 0), 100);
  AssertEquals('count', 2, Length(Hits));
  AssertPointsNear('first', Vec2(-100, 0), Hits[0].Point);
  AssertPointsNear('second', Vec2(100, 0), Hits[1].Point);
  AssertNear('T1 of first', 0.25, Hits[0].T1);
end;

procedure TTestGeometry.TestLineCircleTangent;
var
  Hits: TIntersectionArray;
begin
  Hits := IntersectLineCircle(Line2(Vec2(-200, 50), Vec2(200, 50)), False, Vec2(0, 0), 50);
  AssertEquals('count', 1, Length(Hits));
  AssertPointsNear('touch', Vec2(0, 50), Hits[0].Point);
end;

procedure TTestGeometry.TestLineCircleMiss;
begin
  AssertEquals(0, Length(IntersectLineCircle(Line2(Vec2(-200, 60), Vec2(200, 60)),
    True, Vec2(0, 0), 50)));
end;

procedure TTestGeometry.TestLineCircleSegmentLimits;
var
  L: TLine2;
  Hits: TIntersectionArray;
begin
  // Compass step: shoulder length 120 from the neck point onto a slope line
  L := Line2(Vec2(0, 0), Vec2(50, 0));
  Hits := IntersectLineCircle(L, False, Vec2(0, 0), 120);
  AssertEquals('segment too short', 0, Length(Hits));
  Hits := IntersectLineCircle(L, True, Vec2(0, 0), 120);
  AssertEquals('extended', 2, Length(Hits));
  AssertPointsNear('forward crossing', Vec2(120, 0), Hits[1].Point);
end;

procedure TTestGeometry.TestSignedAreaAndOrientation;
var
  Pts, Rev: TVec2Array;
  I: integer;
begin
  Pts := Square;
  AssertNear('anticlockwise area', 10000, SignedArea(Pts));
  AssertFalse('anticlockwise', IsClockwise(Pts));
  Rev := nil;
  SetLength(Rev, Length(Pts));
  for I := 0 to High(Pts) do
    Rev[I] := Pts[High(Pts) - I];
  AssertNear('clockwise area', -10000, SignedArea(Rev));
  AssertTrue('clockwise', IsClockwise(Rev));
end;

procedure TTestGeometry.TestPointInPolygon;
var
  L: TVec2Array;
begin
  AssertTrue('inside', PointInPolygon(Vec2(50, -50), Square));
  AssertFalse('outside', PointInPolygon(Vec2(150, -50), Square));
  // L shape: the notch at the top right is outside
  L := nil;
  SetLength(L, 6);
  L[0] := Vec2(0, 0);
  L[1] := Vec2(100, 0);
  L[2] := Vec2(100, 50);
  L[3] := Vec2(50, 50);
  L[4] := Vec2(50, 100);
  L[5] := Vec2(0, 100);
  AssertTrue('in the L', PointInPolygon(Vec2(25, 75), L));
  AssertFalse('in the notch', PointInPolygon(Vec2(75, 75), L));
end;

procedure TTestGeometry.TestPolylineLength;
begin
  AssertNear('open square', 300, PolylineLength(Square));
end;

initialization
  RegisterTest(TTestGeometry);

end.
