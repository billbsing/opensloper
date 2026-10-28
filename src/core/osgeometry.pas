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

// Basic 2D geometry types and helpers. Units are millimetres; angles are
// degrees, 0 pointing right, positive anticlockwise. No LCL dependency.
unit osGeometry;

{$mode ObjFPC}{$H+}
{$modeswitch advancedrecords}

interface

const
  // Default tolerance for comparing coordinates, in mm
  DefaultTolerance = 0.001;

type
  TVec2 = record
    X, Y: Double;
    function Length: Double;
    class operator +(const A, B: TVec2): TVec2;
    class operator -(const A, B: TVec2): TVec2;
    class operator *(const A: TVec2; S: Double): TVec2;
  end;

function Vec2(AX, AY: Double): TVec2; inline;
function Distance(const A, B: TVec2): Double;
// Point at Len from Origin in direction AngleDeg
function PolarPoint(const Origin: TVec2; Len, AngleDeg: Double): TVec2;
// Angle of the direction from A to B, in degrees in [0, 360)
function AngleBetween(const A, B: TVec2): Double;
function PointsNear(const A, B: TVec2; Tolerance: Double = DefaultTolerance): Boolean;

implementation

uses
  Math;

function TVec2.Length: Double;
begin
  Result := Hypot(X, Y);
end;

class operator TVec2.+(const A, B: TVec2): TVec2;
begin
  Result.X := A.X + B.X;
  Result.Y := A.Y + B.Y;
end;

class operator TVec2.-(const A, B: TVec2): TVec2;
begin
  Result.X := A.X - B.X;
  Result.Y := A.Y - B.Y;
end;

class operator TVec2.*(const A: TVec2; S: Double): TVec2;
begin
  Result.X := A.X * S;
  Result.Y := A.Y * S;
end;

function Vec2(AX, AY: Double): TVec2;
begin
  Result.X := AX;
  Result.Y := AY;
end;

function Distance(const A, B: TVec2): Double;
begin
  Result := (B - A).Length;
end;

function PolarPoint(const Origin: TVec2; Len, AngleDeg: Double): TVec2;
var
  Rad: Double;
begin
  Rad := DegToRad(AngleDeg);
  Result := Vec2(Origin.X + Len * Cos(Rad), Origin.Y + Len * Sin(Rad));
end;

function AngleBetween(const A, B: TVec2): Double;
begin
  Result := RadToDeg(ArcTan2(B.Y - A.Y, B.X - A.X));
  if Result < 0 then
    Result := Result + 360;
end;

function PointsNear(const A, B: TVec2; Tolerance: Double): Boolean;
begin
  Result := Distance(A, B) <= Tolerance;
end;

end.
