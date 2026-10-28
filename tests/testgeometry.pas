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

unit TestGeometry;

{$mode ObjFPC}{$H+}

interface

uses
  fpcunit, testregistry, osTestCase, osGeometry;

type
  TTestGeometry = class(TOSTestCase)
  published
    procedure TestVectorArithmetic;
    procedure TestDistance;
    procedure TestPolarPointAnglesAreAnticlockwise;
    procedure TestAngleBetweenIsInRange;
    procedure TestPointsNearUsesTolerance;
  end;

implementation

procedure TTestGeometry.TestVectorArithmetic;
begin
  AssertPointsNear('add', Vec2(4, 6), Vec2(1, 2) + Vec2(3, 4));
  AssertPointsNear('subtract', Vec2(-2, -2), Vec2(1, 2) - Vec2(3, 4));
  AssertPointsNear('scale', Vec2(2.5, 5), Vec2(1, 2) * 2.5);
end;

procedure TTestGeometry.TestDistance;
begin
  AssertNear('3-4-5', 5, Distance(Vec2(1, 1), Vec2(4, 5)));
  AssertNear('same point', 0, Distance(Vec2(7, 7), Vec2(7, 7)));
end;

procedure TTestGeometry.TestPolarPointAnglesAreAnticlockwise;
begin
  AssertPointsNear('0 deg points right', Vec2(110, 0), PolarPoint(Vec2(10, 0), 100, 0));
  AssertPointsNear('90 deg points up', Vec2(0, 50), PolarPoint(Vec2(0, 0), 50, 90));
  AssertPointsNear('180 deg points left', Vec2(-50, 0), PolarPoint(Vec2(0, 0), 50, 180));
end;

procedure TTestGeometry.TestAngleBetweenIsInRange;
begin
  AssertNear('right', 0, AngleBetween(Vec2(0, 0), Vec2(10, 0)));
  AssertNear('up', 90, AngleBetween(Vec2(0, 0), Vec2(0, 10)));
  AssertNear('down', 270, AngleBetween(Vec2(0, 0), Vec2(0, -10)));
end;

procedure TTestGeometry.TestPointsNearUsesTolerance;
begin
  AssertTrue('within', PointsNear(Vec2(0, 0), Vec2(0.0005, 0)));
  AssertFalse('outside', PointsNear(Vec2(0, 0), Vec2(0.002, 0)));
end;

initialization
  RegisterTest(TTestGeometry);

end.
