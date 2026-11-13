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

// Basic 2D geometry: vectors, lines, intersections, transforms and polygons.
// Units are millimetres, x right and y down, as on screen and in Seamly2D.
// Angles are degrees, 0 pointing right and positive anticlockwise as seen on
// screen, so 90 points up (towards smaller y). Everything that turns, or tells
// left from right or clockwise from anticlockwise, means it as seen on screen.
// No LCL dependency.
unit Sloper.Core.Geometry;

{$mode ObjFPC}{$H+}
{$modeswitch advancedrecords}

interface

const
  // Default tolerance for comparing coordinates, in mm
  DEFAULT_TOLERANCE = 0.001;
  // Below this a length or determinant is treated as zero
  EPSILON = 1e-12;

type
  TVec2 = record
    X, Y: double;
    function Length: double;
    class operator +(const A, B: TVec2): TVec2;
    class operator -(const A, B: TVec2): TVec2;
    class operator -(const A: TVec2): TVec2;
    class operator *(const A: TVec2; S: double): TVec2;
  end;

  TVec2Array = array of TVec2;

  // A move, turn or mirror: X' = XX x + XY y + TX, Y' = YX x + YY y + TY
  TAffine2 = record
    XX, XY, YX, YY, TX, TY: double;
    function Apply(const P: TVec2): TVec2;
  end;

  TRect2 = record
    MinX, MinY, MaxX, MaxY: double;
  end;

  // A crossing found by an intersection function. T1 is the parameter on the
  // first line or curve argument, T2 on the second (0 when it is a circle).
  TIntersection = record
    Point: TVec2;
    T1, T2: double;
  end;

  TIntersectionArray = array of TIntersection;

  // Line from P1 (T = 0) to P2 (T = 1)
  TLine2 = record
    P1, P2: TVec2;
    function Length: double;
    function Angle: double;
    function PointAt(T: double): TVec2;
    function PointAtLength(D: double): TVec2;
    // Parameter of the foot of the perpendicular from P on the infinite line
    function ParamOf(const P: TVec2): double;
    function ClosestPoint(const P: TVec2; Extend: boolean): TVec2;
  end;

  TLine2Array = array of TLine2;

function AffineIdentity: TAffine2;
function AffineShift(const Offset: TVec2): TAffine2;
// About the origin, anticlockwise on screen
function AffineTurn(AngleDeg: double): TAffine2;
function AffineTurnAbout(const Pivot: TVec2; AngleDeg: double): TAffine2;
// Across the line through A and B
function AffineReflect(const A, B: TVec2): TAffine2;
// Before first, then After
function AffineThen(const After, Before: TAffine2): TAffine2;
function Vec2(AX, AY: double): TVec2; inline;
function Line2(const A, B: TVec2): TLine2; inline;
function Dot(const A, B: TVec2): double; inline;
// The plain cross product, A.X * B.Y - A.Y * B.X. With y down it is positive
// when B turns clockwise from A on screen; use LeftOf and SignedArea for sides.
function Cross(const A, B: TVec2): double; inline;
// V turned a quarter anticlockwise on screen: the left of a path running along V
function LeftOf(const V: TVec2): TVec2; inline;
function Lerp(const A, B: TVec2; T: double): TVec2;
function Distance(const A, B: TVec2): double;
function PointsNear(const A, B: TVec2; Tolerance: double = DEFAULT_TOLERANCE): boolean;

// Angle in degrees normalised to [0, 360)
function NormalizeAngle(AngleDeg: double): double;
// Point at Len from Origin in direction AngleDeg
function PolarPoint(const Origin: TVec2; Len, AngleDeg: double): TVec2;
// Angle of the direction from A to B, in degrees in [0, 360)
function AngleBetween(const A, B: TVec2): double;

function RotatePoint(const P, Pivot: TVec2; AngleDeg: double): TVec2;
// Mirror P across the infinite line through A and B
function MirrorPoint(const P, A, B: TVec2): TVec2;

// Intersection of two lines. Without Extend a line is limited to its ends
// (within DEFAULT_TOLERANCE). False when parallel or not crossing.
function IntersectLines(const A, B: TLine2; ExtendA, ExtendB: boolean; out Hit: TIntersection): boolean;
// Crossings of a line and a circle, sorted by T1 (the line parameter)
function IntersectLineCircle(const L: TLine2; Extend: boolean; const Centre: TVec2; Radius: double): TIntersectionArray;

// Where two circles cross: First is to the left going from centre A to centre
// B, and Second to the right. Count is 0 when they miss or share a centre, 1
// when they touch.
function IntersectCircles(const A: TVec2; RadiusA: double; const B: TVec2; RadiusB: double; out First, Second: TVec2): integer;
// Positive when the points run anticlockwise on screen
function SignedArea(const Pts: TVec2Array): double;
function IsClockwise(const Pts: TVec2Array): boolean;
// Non-zero winding rule; points exactly on the boundary may go either way
function PointInPolygon(const P: TVec2; const Pts: TVec2Array): boolean;
function PolylineLength(const Pts: TVec2Array): double;

procedure SortIntersections(var Hits: TIntersectionArray);
procedure AddIntersection(var Hits: TIntersectionArray; const P: TVec2; T1, T2: double);

implementation

uses
  Math;

const
  // A line or curve this close to a circle (in mm) touches it once
  TANGENT_TOLERANCE = 1e-9;
  // Angles this close below 360 degrees are taken as 0
  ANGLE_SNAP = 1e-9;

  { TVec2 }
  TOUCH_TOLERANCE = 1e-9;

function TVec2.Length: double;
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

class operator TVec2.-(const A: TVec2): TVec2;
begin
  Result.X := -A.X;
  Result.Y := -A.Y;
end;

class operator TVec2.*(const A: TVec2; S: double): TVec2;
begin
  Result.X := A.X * S;
  Result.Y := A.Y * S;
end;

{ TLine2 }

function TLine2.Length: double;
begin
  Result := Distance(P1, P2);
end;

function TLine2.Angle: double;
begin
  Result := AngleBetween(P1, P2);
end;

function TLine2.PointAt(T: double): TVec2;
begin
  Result := Lerp(P1, P2, T);
end;

function TLine2.PointAtLength(D: double): TVec2;
begin
  Result := PolarPoint(P1, D, Angle);
end;

function TLine2.ParamOf(const P: TVec2): double;
var
  D: TVec2;
  LenSq: double;
begin
  D := P2 - P1;
  LenSq := Dot(D, D);
  if LenSq < EPSILON then
    Exit(0);
  Result := Dot(P - P1, D) / LenSq;
end;

function TLine2.ClosestPoint(const P: TVec2; Extend: boolean): TVec2;
var
  T: double;
begin
  T := ParamOf(P);
  if not Extend then
    T := EnsureRange(T, 0, 1);
  Result := PointAt(T);
end;

{ Functions }

function TAffine2.Apply(const P: TVec2): TVec2;
begin
  Result.X := XX * P.X + XY * P.Y + TX;
  Result.Y := YX * P.X + YY * P.Y + TY;
end;

function AffineIdentity: TAffine2;
begin
  Result := Default(TAffine2);
  Result.XX := 1;
  Result.YY := 1;
end;

function AffineShift(const Offset: TVec2): TAffine2;
begin
  Result := AffineIdentity;
  Result.TX := Offset.X;
  Result.TY := Offset.Y;
end;

function AffineTurn(AngleDeg: double): TAffine2;
begin
  Result := AffineIdentity;
  // Anticlockwise on screen is clockwise in the y-down axes
  Result.XX := Cos(DegToRad(AngleDeg));
  Result.XY := Sin(DegToRad(AngleDeg));
  Result.YX := -Sin(DegToRad(AngleDeg));
  Result.YY := Cos(DegToRad(AngleDeg));
end;

function AffineTurnAbout(const Pivot: TVec2; AngleDeg: double): TAffine2;
begin
  Result := AffineThen(AffineShift(Pivot), AffineThen(AffineTurn(AngleDeg), AffineShift(-Pivot)));
end;

function AffineReflect(const A, B: TVec2): TAffine2;
var
  Along: TVec2;
  Span: double;
begin
  Result := AffineIdentity;
  Span := Distance(A, B);
  if Span = 0 then
    Exit;
  Along := (B - A) * (1 / Span);
  Result.XX := Along.X * Along.X - Along.Y * Along.Y;
  Result.XY := 2 * Along.X * Along.Y;
  Result.YX := Result.XY;
  Result.YY := -Result.XX;
  Result.TX := A.X - (Result.XX * A.X + Result.XY * A.Y);
  Result.TY := A.Y - (Result.YX * A.X + Result.YY * A.Y);
end;

function AffineThen(const After, Before: TAffine2): TAffine2;
begin
  Result.XX := After.XX * Before.XX + After.XY * Before.YX;
  Result.XY := After.XX * Before.XY + After.XY * Before.YY;
  Result.YX := After.YX * Before.XX + After.YY * Before.YX;
  Result.YY := After.YX * Before.XY + After.YY * Before.YY;
  Result.TX := After.XX * Before.TX + After.XY * Before.TY + After.TX;
  Result.TY := After.YX * Before.TX + After.YY * Before.TY + After.TY;
end;

function Vec2(AX, AY: double): TVec2;
begin
  Result.X := AX;
  Result.Y := AY;
end;

function Line2(const A, B: TVec2): TLine2;
begin
  Result.P1 := A;
  Result.P2 := B;
end;

function Dot(const A, B: TVec2): double;
begin
  Result := A.X * B.X + A.Y * B.Y;
end;

function Cross(const A, B: TVec2): double;
begin
  Result := A.X * B.Y - A.Y * B.X;
end;

function LeftOf(const V: TVec2): TVec2;
begin
  Result := Vec2(V.Y, -V.X);
end;

function Lerp(const A, B: TVec2; T: double): TVec2;
begin
  Result := Vec2(A.X + (B.X - A.X) * T, A.Y + (B.Y - A.Y) * T);
end;

function Distance(const A, B: TVec2): double;
begin
  Result := (B - A).Length;
end;

function PointsNear(const A, B: TVec2; Tolerance: double): boolean;
begin
  Result := Distance(A, B) <= Tolerance;
end;

function NormalizeAngle(AngleDeg: double): double;
begin
  // A double 360: with a whole number Math's FMod takes its single overload
  Result := FMod(AngleDeg, double(360));
  if Result < 0 then
    Result := Result + 360;
  // A rounding error just below 0 (or 360) would otherwise read 359.999...
  if Result >= 360 - ANGLE_SNAP then
    Result := 0;
end;

function PolarPoint(const Origin: TVec2; Len, AngleDeg: double): TVec2;
var
  Rad: double;
begin
  Rad := DegToRad(AngleDeg);
  // y down: a positive angle goes up the screen
  Result := Vec2(Origin.X + Len * Cos(Rad), Origin.Y - Len * Sin(Rad));
end;

function AngleBetween(const A, B: TVec2): double;
begin
  Result := NormalizeAngle(RadToDeg(ArcTan2(A.Y - B.Y, B.X - A.X)));
end;

function RotatePoint(const P, Pivot: TVec2; AngleDeg: double): TVec2;
var
  S, C: double;
  D: TVec2;
begin
  SinCos(DegToRad(AngleDeg), S, C);
  D := P - Pivot;
  Result := Vec2(Pivot.X + D.X * C + D.Y * S, Pivot.Y - D.X * S + D.Y * C);
end;

function MirrorPoint(const P, A, B: TVec2): TVec2;
var
  Foot: TVec2;
begin
  Foot := Line2(A, B).ClosestPoint(P, True);
  Result := Foot * 2 - P;
end;

// Parameter tolerance equivalent to DEFAULT_TOLERANCE along a line
function ParamTolerance(const L: TLine2): double;
var
  Len: double;
begin
  Len := L.Length;
  if Len < EPSILON then
    Result := 0
  else
    Result := DEFAULT_TOLERANCE / Len;
end;

function InRange01(T, Tol: double): boolean;
begin
  Result := (T >= -Tol) and (T <= 1 + Tol);
end;

function IntersectLines(const A, B: TLine2; ExtendA, ExtendB: boolean; out Hit: TIntersection): boolean;
var
  DA, DB, Diff: TVec2;
  Denom: double;
begin
  Hit := Default(TIntersection);
  DA := A.P2 - A.P1;
  DB := B.P2 - B.P1;
  Denom := Cross(DA, DB);
  // Relative test so the result does not depend on the line lengths
  if Abs(Denom) <= EPSILON * Max(1, DA.Length * DB.Length) then
    Exit(False);
  Diff := B.P1 - A.P1;
  Hit.T1 := Cross(Diff, DB) / Denom;
  Hit.T2 := Cross(Diff, DA) / Denom;
  if not ExtendA and not InRange01(Hit.T1, ParamTolerance(A)) then
    Exit(False);
  if not ExtendB and not InRange01(Hit.T2, ParamTolerance(B)) then
    Exit(False);
  Hit.Point := A.PointAt(Hit.T1);
  Result := True;
end;

function IntersectLineCircle(const L: TLine2; Extend: boolean; const Centre: TVec2; Radius: double): TIntersectionArray;
var
  D, F: TVec2;
  A, B, C, Disc, Root, Tol: double;

  procedure Add(T: double);
  begin
    if Extend or InRange01(T, Tol) then
      AddIntersection(Result, L.PointAt(T), T, 0);
  end;

begin
  Result := nil;
  D := L.P2 - L.P1;
  F := L.P1 - Centre;
  A := Dot(D, D);
  if A < EPSILON then
    Exit;
  B := 2 * Dot(F, D);
  C := Dot(F, F) - Radius * Radius;
  Disc := B * B - 4 * A * C;
  Tol := ParamTolerance(L);
  // Disc = 4A(r² - d²) ≈ 8Ar(r - d), where d is the centre's distance from
  // the line; treat |r - d| below TANGENT_TOLERANCE as touching at one point
  if Abs(Disc) <= 8 * A * Radius * TANGENT_TOLERANCE then
    Add(-B / (2 * A))
  else if Disc > 0 then
  begin
    Root := Sqrt(Disc);
    Add((-B - Root) / (2 * A));
    Add((-B + Root) / (2 * A));
  end;
end;

function IntersectCircles(const A: TVec2; RadiusA: double; const B: TVec2; RadiusB: double; out First, Second: TVec2): integer;
var
  Gap, Along, HeightSquared, Height: double;
  Unit2, Foot, Across: TVec2;
begin
  First := Vec2(0, 0);
  Second := First;
  Gap := Distance(A, B);
  if Gap < TOUCH_TOLERANCE then
    Exit(0);
  Along := (Gap * Gap + RadiusA * RadiusA - RadiusB * RadiusB) / (2 * Gap);
  HeightSquared := RadiusA * RadiusA - Along * Along;
  if HeightSquared < -TOUCH_TOLERANCE * Max(RadiusA * RadiusA, 1) then
    Exit(0);
  Unit2 := (B - A) * (1 / Gap);
  Foot := A + Unit2 * Along;
  if HeightSquared <= TOUCH_TOLERANCE * Max(RadiusA * RadiusA, 1) then
  begin
    First := Foot;
    Second := Foot;
    Exit(1);
  end;
  Height := Sqrt(HeightSquared);
  Across := LeftOf(Unit2) * Height;
  First := Foot + Across;
  Second := Foot - Across;
  Result := 2;
end;

function SignedArea(const Pts: TVec2Array): double;
var
  I, J: integer;
begin
  Result := 0;
  if Length(Pts) < 3 then
    Exit;
  J := High(Pts);
  for I := 0 to High(Pts) do
  begin
    Result := Result + Cross(Pts[J], Pts[I]);
    J := I;
  end;
  // The shoelace sum is positive for clockwise on screen, since y is down
  Result := -Result / 2;
end;

function IsClockwise(const Pts: TVec2Array): boolean;
begin
  Result := SignedArea(Pts) < 0;
end;

function PointInPolygon(const P: TVec2; const Pts: TVec2Array): boolean;
var
  I, J, Winding: integer;
  A, B: TVec2;
begin
  Winding := 0;
  if Length(Pts) < 3 then
    Exit(False);
  J := High(Pts);
  for I := 0 to High(Pts) do
  begin
    A := Pts[J];
    B := Pts[I];
    if A.Y <= P.Y then
    begin
      if (B.Y > P.Y) and (Cross(B - A, P - A) > 0) then
        Inc(Winding);
    end
    else if (B.Y <= P.Y) and (Cross(B - A, P - A) < 0) then
      Dec(Winding);
    J := I;
  end;
  Result := Winding <> 0;
end;

function PolylineLength(const Pts: TVec2Array): double;
var
  I: integer;
begin
  Result := 0;
  for I := 1 to High(Pts) do
    Result := Result + Distance(Pts[I - 1], Pts[I]);
end;

procedure SortIntersections(var Hits: TIntersectionArray);
var
  I, J: integer;
  Tmp: TIntersection;
begin
  // Insertion sort: the lists are a handful of items
  for I := 1 to High(Hits) do
  begin
    Tmp := Hits[I];
    J := I - 1;
    while (J >= 0) and (Hits[J].T1 > Tmp.T1) do
    begin
      Hits[J + 1] := Hits[J];
      Dec(J);
    end;
    Hits[J + 1] := Tmp;
  end;
end;

procedure AddIntersection(var Hits: TIntersectionArray; const P: TVec2; T1, T2: double);
var
  N: integer;
begin
  N := Length(Hits);
  SetLength(Hits, N + 1);
  Hits[N].Point := P;
  Hits[N].T1 := T1;
  Hits[N].T2 := T2;
end;

end.
