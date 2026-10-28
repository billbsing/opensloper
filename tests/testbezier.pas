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

// Expected values were computed independently (closed-form parabola arc
// length and bisection on the curve equations), not with this code.
unit TestBezier;

{$mode ObjFPC}{$H+}

interface

uses
  fpcunit, testregistry, osTestCase, osGeometry, osBezier;

type
  TTestBezier = class(TOSTestCase)
  published
    procedure TestFromHandles;
    procedure TestEndpointsAndMidpoint;
    procedure TestHandleAnglesReadBack;
    procedure TestZeroHandleAngleFallsBack;
    procedure TestStraightCurveLength;
    procedure TestParabolaLength;
    procedure TestParamAtLength;
    procedure TestPointAtLengthClamps;
    procedure TestSplit;
    procedure TestBounds;
    procedure TestFlattenStaysOnCurve;
    procedure TestClosestParam;
    procedure TestTransformsKeepLength;
    procedure TestMirrorReversesOrientation;
    procedure TestIntersectLine;
    procedure TestIntersectLineSCurve;
    procedure TestIntersectLineNeedsExtend;
    procedure TestIntersectLineAlongCurve;
    procedure TestIntersectCurves;
    procedure TestIntersectCurvesNoCrossing;
    procedure TestIntersectCircle;
    procedure TestIntersectCircleOneCrossing;
  end;

implementation

const
  // Closed-form arc length of the parabola below
  ParabolaLength = 147.89428575445976;

// x = 100t, y = 200t(1 - t): a parabola from (0, 0) over (50, 50) to (100, 0),
// written as a cubic (the quadratic with control point (50, 100), elevated)
function Parabola: TCubicBezier;
begin
  Result := CubicBezier(Vec2(0, 0), Vec2(100 / 3, 200 / 3), Vec2(200 / 3, 200 / 3), Vec2(100, 0));
end;

// x = 100t, y = 75 - 200t(1 - t): the parabola flipped and raised, from
// (0, 75) down to (50, 25) and back up to (100, 75)
function ParabolaFlipped: TCubicBezier;
begin
  Result := CubicBezier(Vec2(0, 75), Vec2(100 / 3, 25 / 3), Vec2(200 / 3, 25 / 3), Vec2(100, 75));
end;

procedure TTestBezier.TestFromHandles;
var
  C: TCubicBezier;
begin
  C := BezierFromHandles(Vec2(0, 0), 90, 40, Vec2(100, 0), 90, 30);
  AssertPointsNear('start', Vec2(0, 0), C.P0);
  AssertPointsNear('first handle', Vec2(0, 40), C.P1);
  AssertPointsNear('second handle', Vec2(100, 30), C.P2);
  AssertPointsNear('end', Vec2(100, 0), C.P3);
end;

procedure TTestBezier.TestEndpointsAndMidpoint;
var
  C: TCubicBezier;
begin
  C := Parabola;
  AssertPointsNear('t=0', Vec2(0, 0), C.PointAt(0));
  AssertPointsNear('t=1', Vec2(100, 0), C.PointAt(1));
  AssertPointsNear('apex', Vec2(50, 50), C.PointAt(0.5));
  AssertPointsNear('t=0.25', Vec2(25, 37.5), C.PointAt(0.25));
end;

procedure TTestBezier.TestHandleAnglesReadBack;
var
  C: TCubicBezier;
begin
  C := BezierFromHandles(Vec2(0, 0), 60, 40, Vec2(100, 0), 135, 30);
  AssertNear('angle1', 60, C.StartAngle);
  AssertNear('angle2', 135, C.EndAngle);
end;

procedure TTestBezier.TestZeroHandleAngleFallsBack;
var
  C: TCubicBezier;
begin
  C := BezierFromHandles(Vec2(0, 0), 60, 0, Vec2(100, 0), 90, 50);
  AssertNear('towards the other handle', AngleBetween(Vec2(0, 0), Vec2(100, 50)), C.StartAngle);
end;

procedure TTestBezier.TestStraightCurveLength;
var
  C: TCubicBezier;
begin
  C := CubicBezier(Vec2(0, 0), Vec2(10, 10), Vec2(20, 20), Vec2(30, 30));
  AssertNear('chord', Sqrt(1800), C.Length, 1e-6);
  AssertPointsNear('evenly spaced', Vec2(10, 10), C.PointAtLength(Sqrt(200)));
end;

procedure TTestBezier.TestParabolaLength;
begin
  AssertNear('length', ParabolaLength, Parabola.Length, 1e-6);
  AssertNear('half', ParabolaLength / 2, Parabola.LengthBetween(0, 0.5), 1e-6);
end;

procedure TTestBezier.TestParamAtLength;
var
  C: TCubicBezier;
begin
  C := Parabola;
  AssertNear('half way is the apex', 0.5, C.ParamAtLength(ParabolaLength / 2), 1e-9);
  AssertNear('quarter', 0.19463065852097, C.ParamAtLength(ParabolaLength / 4), 1e-9);
  AssertPointsNear('quarter point', Vec2(19.463065852097, 31.34991305693271),
    C.PointAtLength(ParabolaLength / 4));
end;

procedure TTestBezier.TestPointAtLengthClamps;
var
  C: TCubicBezier;
begin
  C := Parabola;
  AssertPointsNear('negative', C.P0, C.PointAtLength(-5));
  AssertPointsNear('past the end', C.P3, C.PointAtLength(ParabolaLength + 5));
end;

procedure TTestBezier.TestSplit;
var
  C, A, B: TCubicBezier;
begin
  C := Parabola;
  C.Split(0.25, A, B);
  AssertPointsNear('first starts at start', C.P0, A.P0);
  AssertPointsNear('join', C.PointAt(0.25), A.P3);
  AssertPointsNear('second starts at join', A.P3, B.P0);
  AssertPointsNear('second ends at end', C.P3, B.P3);
  AssertPointsNear('first half midpoint', C.PointAt(0.125), A.PointAt(0.5));
  AssertNear('lengths add up', C.Length, A.Length + B.Length, 1e-6);
end;

procedure TTestBezier.TestBounds;
var
  R: TRect2;
begin
  R := Parabola.Bounds;
  AssertNear('min x', 0, R.MinX);
  AssertNear('min y', 0, R.MinY);
  AssertNear('max x', 100, R.MaxX);
  AssertNear('max y (apex, not the control points)', 50, R.MaxY);
end;

procedure TTestBezier.TestFlattenStaysOnCurve;
var
  C: TCubicBezier;
  S: TCurveSampleArray;
  I: Integer;
  Mid: TVec2;
  Chord: TLine2;
begin
  C := Parabola;
  S := C.Flatten(0.01);
  AssertTrue('several points', Length(S) > 4);
  AssertNear('first t', 0, S[0].T);
  AssertNear('last t', 1, S[High(S)].T);
  for I := 0 to High(S) do
    AssertPointsNear('on curve', C.PointAt(S[I].T), S[I].Point, 1e-9);
  // The curve between two samples stays within the tolerance of their chord
  for I := 1 to High(S) do
  begin
    Mid := C.PointAt((S[I - 1].T + S[I].T) / 2);
    Chord := Line2(S[I - 1].Point, S[I].Point);
    AssertTrue('curve near chord', Distance(Chord.ClosestPoint(Mid, False), Mid) <= 0.01);
  end;
end;

procedure TTestBezier.TestClosestParam;
var
  C: TCubicBezier;
begin
  C := Parabola;
  AssertNear('above the apex', 0.5, C.ClosestParam(Vec2(50, 80)), 1e-9);
  AssertNear('off to the side', 0.6286253182799568, C.ClosestParam(Vec2(80, 80)), 1e-7);
  AssertNear('beyond the end', 1, C.ClosestParam(Vec2(150, -20)), 1e-9);
end;

procedure TTestBezier.TestTransformsKeepLength;
var
  C, R: TCubicBezier;
begin
  C := Parabola;
  R := C.Rotated(Vec2(10, 10), 37);
  AssertNear('rotated length', ParabolaLength, R.Length, 1e-6);
  AssertPointsNear('rotated start', RotatePoint(C.P0, Vec2(10, 10), 37), R.P0);
  AssertNear('rotated angle1', NormalizeAngle(C.StartAngle + 37), R.StartAngle);
  AssertNear('moved length', ParabolaLength, C.Translated(Vec2(5, -7)).Length, 1e-6);
  AssertPointsNear('moved apex', Vec2(55, 43), C.Translated(Vec2(5, -7)).PointAt(0.5));
end;

procedure TTestBezier.TestMirrorReversesOrientation;
var
  C, M: TCubicBezier;
begin
  C := Parabola;
  // Mirror in the x axis: the parabola now dips below
  M := C.Mirrored(Vec2(0, 0), Vec2(1, 0));
  AssertPointsNear('apex', Vec2(50, -50), M.PointAt(0.5));
  AssertNear('length', ParabolaLength, M.Length, 1e-6);
  AssertPointsNear('reversed start', C.P3, C.Reversed.P0);
end;

procedure TTestBezier.TestIntersectLine;
var
  Hits: TIntersectionArray;
begin
  Hits := IntersectBezierLine(Parabola, Line2(Vec2(-10, 50 - 50 * Sqrt(0.5)),
    Vec2(110, 50 - 50 * Sqrt(0.5))), False);
  AssertEquals('below the apex', 2, Length(Hits));
  Hits := IntersectBezierLine(Parabola, Line2(Vec2(-10, 50), Vec2(110, 50)), False);
  AssertEquals('tangent at apex', 1, Length(Hits));
  AssertPointsNear('apex', Vec2(50, 50), Hits[0].Point);
  Hits := IntersectBezierLine(Parabola, Line2(Vec2(-10, 25), Vec2(110, 25)), False);
  AssertEquals('y=25 count', 2, Length(Hits));
  AssertNear('first t', 0.1464466094067262, Hits[0].T1, 1e-9);
  AssertPointsNear('first', Vec2(14.64466094067262, 25), Hits[0].Point);
  AssertPointsNear('second', Vec2(85.35533905932738, 25), Hits[1].Point);
  AssertNear('line parameter', (14.64466094067262 + 10) / 120, Hits[0].T2, 1e-9);
end;

procedure TTestBezier.TestIntersectLineSCurve;
var
  C: TCubicBezier;
  Hits: TIntersectionArray;
begin
  // x = 100t, y = 300t(1-t)(1-2t): crosses y = 0 at both ends and the middle
  C := CubicBezier(Vec2(0, 0), Vec2(100 / 3, 100), Vec2(200 / 3, -100), Vec2(100, 0));
  Hits := IntersectBezierLine(C, Line2(Vec2(-10, 0), Vec2(110, 0)), False);
  AssertEquals('count', 3, Length(Hits));
  AssertPointsNear('start', Vec2(0, 0), Hits[0].Point);
  AssertPointsNear('middle', Vec2(50, 0), Hits[1].Point);
  AssertPointsNear('end', Vec2(100, 0), Hits[2].Point);
  AssertNear('middle t', 0.5, Hits[1].T1, 1e-9);
end;

procedure TTestBezier.TestIntersectLineNeedsExtend;
var
  L: TLine2;
begin
  L := Line2(Vec2(-30, 25), Vec2(0, 25));
  AssertEquals('segment', 0, Length(IntersectBezierLine(Parabola, L, False)));
  AssertEquals('extended', 2, Length(IntersectBezierLine(Parabola, L, True)));
end;

procedure TTestBezier.TestIntersectLineAlongCurve;
var
  C: TCubicBezier;
begin
  C := CubicBezier(Vec2(0, 0), Vec2(10, 0), Vec2(20, 0), Vec2(30, 0));
  AssertEquals(0, Length(IntersectBezierLine(C, Line2(Vec2(-10, 0), Vec2(50, 0)), True)));
end;

procedure TTestBezier.TestIntersectCurves;
var
  Hits: TIntersectionArray;
begin
  // Both have x = 100t, so they cross where 200t(1-t) = 37.5: t = 0.25, 0.75
  Hits := IntersectBeziers(Parabola, ParabolaFlipped);
  AssertEquals('count', 2, Length(Hits));
  AssertPointsNear('first', Vec2(25, 37.5), Hits[0].Point);
  AssertPointsNear('second', Vec2(75, 37.5), Hits[1].Point);
  AssertNear('first T1', 0.25, Hits[0].T1, 1e-9);
  AssertNear('first T2', 0.25, Hits[0].T2, 1e-9);
  AssertNear('second T2', 0.75, Hits[1].T2, 1e-9);
end;

procedure TTestBezier.TestIntersectCurvesNoCrossing;
begin
  AssertEquals(0, Length(IntersectBeziers(Parabola, Parabola.Translated(Vec2(0, 60)))));
end;

procedure TTestBezier.TestIntersectCircle;
var
  Hits: TIntersectionArray;
begin
  Hits := IntersectBezierCircle(Parabola, Vec2(50, 100), 70);
  AssertEquals('count', 2, Length(Hits));
  AssertNear('first t', 0.2299781088888848, Hits[0].T1, 1e-9);
  AssertPointsNear('first', Vec2(22.99781088888848, 35.41763566415541), Hits[0].Point);
  AssertPointsNear('second', Vec2(77.00218911111152, 35.41763566415541), Hits[1].Point);
end;

procedure TTestBezier.TestIntersectCircleOneCrossing;
var
  Hits: TIntersectionArray;
begin
  Hits := IntersectBezierCircle(Parabola, Vec2(0, 0), 60);
  AssertEquals('count', 1, Length(Hits));
  AssertPointsNear('crossing', Vec2(37.47115810813606, 46.8605624169735), Hits[0].Point);
end;

initialization
  RegisterTest(TTestBezier);

end.
