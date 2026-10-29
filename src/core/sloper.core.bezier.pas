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

// Cubic Bézier curves: evaluation, length, splitting, bounds, closest point,
// transforms and intersections. Units are mm, angles degrees. No LCL dependency.
unit Sloper.Core.Bezier;

{$mode ObjFPC}{$H+}
{$modeswitch advancedrecords}
{$modeswitch nestedprocvars}

interface

uses
  Sloper.Core.Geometry;

const
  // Flattening tolerance used to find intersections before refining, in mm
  CoarseFlatness = 0.05;

type
  TCurveSample = record
    T: double;
    Point: TVec2;
  end;

  TCurveSampleArray = array of TCurveSample;

  // Start P0, control points P1 and P2, end P3; parameter T runs 0 to 1
  TCubicBezier = record
    P0, P1, P2, P3: TVec2;
    function PointAt(T: double): TVec2;
    function DerivativeAt(T: double): TVec2;
    function SecondDerivativeAt(T: double): TVec2;
    function Length: double;
    function LengthBetween(T0, T1: double): double;
    // Parameter at arc length S from the start, clamped to the curve
    function ParamAtLength(S: double): double;
    function PointAtLength(S: double): TVec2;
    // Direction of the start handle (angle1) and end handle (angle2)
    function StartAngle: double;
    function EndAngle: double;
    procedure Split(T: double; out First, Second: TCubicBezier);
    function Bounds: TRect2;
    // Polyline whose points lie on the curve, within Tolerance of it
    function Flatten(Tolerance: double): TCurveSampleArray;
    // Parameter of the nearest point on the curve to P
    function ClosestParam(const P: TVec2): double;
    function Reversed: TCubicBezier;
    function Translated(const D: TVec2): TCubicBezier;
    function Rotated(const Pivot: TVec2; AngleDeg: double): TCubicBezier;
    function Mirrored(const A, B: TVec2): TCubicBezier;
  end;

function CubicBezier(const P0, P1, P2, P3: TVec2): TCubicBezier;
// Curve from Start to Finish whose handles leave Start at Angle1 with length
// Length1 and leave Finish at Angle2 with length Length2
function BezierFromHandles(const Start: TVec2; Angle1, Length1: double; const Finish: TVec2; Angle2, Length2: double): TCubicBezier;

// Crossings of a curve with a line, sorted by curve parameter (T1); T2 is the
// line parameter. Empty when the curve lies along the line.
function IntersectBezierLine(const C: TCubicBezier; const L: TLine2; ExtendLine: boolean): TIntersectionArray;
// Crossings of two curves, sorted by the first curve's parameter
function IntersectBeziers(const A, B: TCubicBezier): TIntersectionArray;
// Crossings of a curve with a circle, sorted by curve parameter
function IntersectBezierCircle(const C: TCubicBezier; const Centre: TVec2; Radius: double): TIntersectionArray;

implementation

uses
  Math, Sloper.Core.Numeric;

const
  LengthTolerance = 1e-9;
  MaxFlattenDepth = 18;
  NewtonIterations = 30;
  // Parameter tolerance when merging duplicate crossings
  MergeParamTolerance = 1e-7;

  { TCubicBezier }

function TCubicBezier.PointAt(T: double): TVec2;
var
  U, B0, B1, B2, B3: double;
begin
  U := 1 - T;
  B0 := U * U * U;
  B1 := 3 * U * U * T;
  B2 := 3 * U * T * T;
  B3 := T * T * T;
  Result := Vec2(B0 * P0.X + B1 * P1.X + B2 * P2.X + B3 * P3.X, B0 * P0.Y + B1 * P1.Y + B2 * P2.Y + B3 * P3.Y);
end;

function TCubicBezier.DerivativeAt(T: double): TVec2;
var
  U: double;
begin
  U := 1 - T;
  Result := (P1 - P0) * (3 * U * U) + (P2 - P1) * (6 * U * T) + (P3 - P2) * (3 * T * T);
end;

function TCubicBezier.SecondDerivativeAt(T: double): TVec2;
begin
  Result := (P2 - P1 * 2 + P0) * (6 * (1 - T)) + (P3 - P2 * 2 + P1) * (6 * T);
end;

function TCubicBezier.Length: double;
begin
  Result := LengthBetween(0, 1);
end;

function TCubicBezier.LengthBetween(T0, T1: double): double;

  function Speed(T: double): double;
  begin
    Result := DerivativeAt(T).Length;
  end;

begin
  Result := Integrate(@Speed, T0, T1, LengthTolerance);
end;

function TCubicBezier.ParamAtLength(S: double): double;
var
  Total, Lo, Hi, T, F, D, Next: double;
  I: integer;
begin
  Total := Length;
  if (S <= 0) or (Total < Epsilon) then
    Exit(0);
  if S >= Total then
    Exit(1);
  Lo := 0;
  Hi := 1;
  T := S / Total;
  for I := 1 to NewtonIterations do
  begin
    F := LengthBetween(0, T) - S;
    if Abs(F) <= LengthTolerance * 10 then
      Break;
    if F > 0 then
      Hi := T
    else
      Lo := T;
    // Newton step on arc length, falling back to bisection
    D := DerivativeAt(T).Length;
    if D > Epsilon then
      Next := T - F / D
    else
      Next := (Lo + Hi) / 2;
    if (Next <= Lo) or (Next >= Hi) then
      Next := (Lo + Hi) / 2;
    T := Next;
  end;
  Result := T;
end;

function TCubicBezier.PointAtLength(S: double): TVec2;
begin
  Result := PointAt(ParamAtLength(S));
end;

function TCubicBezier.StartAngle: double;
begin
  // A zero-length handle has no direction; use the next control point
  if not PointsNear(P1, P0, Epsilon) then
    Result := AngleBetween(P0, P1)
  else if not PointsNear(P2, P0, Epsilon) then
    Result := AngleBetween(P0, P2)
  else
    Result := AngleBetween(P0, P3);
end;

function TCubicBezier.EndAngle: double;
begin
  if not PointsNear(P2, P3, Epsilon) then
    Result := AngleBetween(P3, P2)
  else if not PointsNear(P1, P3, Epsilon) then
    Result := AngleBetween(P3, P1)
  else
    Result := AngleBetween(P3, P0);
end;

procedure TCubicBezier.Split(T: double; out First, Second: TCubicBezier);
var
  A, B, C, AB, BC, Mid: TVec2;
begin
  // de Casteljau
  A := Lerp(P0, P1, T);
  B := Lerp(P1, P2, T);
  C := Lerp(P2, P3, T);
  AB := Lerp(A, B, T);
  BC := Lerp(B, C, T);
  Mid := Lerp(AB, BC, T);
  First := CubicBezier(P0, A, AB, Mid);
  Second := CubicBezier(Mid, BC, C, P3);
end;

function TCubicBezier.Bounds: TRect2;

  procedure Include(const P: TVec2);
  begin
    Result.MinX := Min(Result.MinX, P.X);
    Result.MinY := Min(Result.MinY, P.Y);
    Result.MaxX := Max(Result.MaxX, P.X);
    Result.MaxY := Max(Result.MaxY, P.Y);
  end;

  // Extremes along one axis are where the derivative is zero
  procedure IncludeExtremes(C0, C1, C2, C3: double);
  var
    E, F, G: double;
    Roots: TDoubleArray;
    T: double;
  begin
    E := C1 - C0;
    F := C2 - C1;
    G := C3 - C2;
    Roots := SolveQuadratic(E - 2 * F + G, 2 * (F - E), E);
    for T in Roots do
      if (T > 0) and (T < 1) then
        Include(PointAt(T));
  end;

begin
  Result.MinX := Min(P0.X, P3.X);
  Result.MinY := Min(P0.Y, P3.Y);
  Result.MaxX := Max(P0.X, P3.X);
  Result.MaxY := Max(P0.Y, P3.Y);
  IncludeExtremes(P0.X, P1.X, P2.X, P3.X);
  IncludeExtremes(P0.Y, P1.Y, P2.Y, P3.Y);
end;

function TCubicBezier.Flatten(Tolerance: double): TCurveSampleArray;
var
  Count: integer;

  procedure Add(T: double; const P: TVec2);
  begin
    if Count = System.Length(Result) then
      SetLength(Result, Count * 2 + 16);
    Result[Count].T := T;
    Result[Count].Point := P;
    Inc(Count);
  end;

  // Adds the end of the piece; its start is already in the list
  procedure Subdivide(const C: TCubicBezier; T0, T1: double; Depth: integer);
  var
    Chord: TLine2;
    Flat: boolean;
    First, Second: TCubicBezier;
  begin
    Chord := Line2(C.P0, C.P3);
    Flat := (Distance(Chord.ClosestPoint(C.P1, False), C.P1) <= Tolerance) and (Distance(Chord.ClosestPoint(C.P2, False), C.P2) <= Tolerance);
    if Flat or (Depth >= MaxFlattenDepth) then
      Add(T1, C.P3)
    else
    begin
      C.Split(0.5, First, Second);
      Subdivide(First, T0, (T0 + T1) / 2, Depth + 1);
      Subdivide(Second, (T0 + T1) / 2, T1, Depth + 1);
    end;
  end;

begin
  Result := nil;
  Count := 0;
  Add(0, P0);
  Subdivide(Self, 0, 1, 0);
  SetLength(Result, Count);
end;

function TCubicBezier.ClosestParam(const P: TVec2): double;
var
  Samples: TCurveSampleArray;
  I, J: integer;
  BestT, BestDist, T, Dist, F, DF: double;
  Seg: TLine2;
  Q, D1: TVec2;
begin
  Samples := Flatten(CoarseFlatness);
  BestT := 0;
  BestDist := Distance(P, P0);
  for I := 1 to High(Samples) do
  begin
    Seg := Line2(Samples[I - 1].Point, Samples[I].Point);
    T := EnsureRange(Seg.ParamOf(P), 0, 1);
    Dist := Distance(P, Seg.PointAt(T));
    if Dist < BestDist then
    begin
      BestDist := Dist;
      BestT := Samples[I - 1].T + (Samples[I].T - Samples[I - 1].T) * T;
    end;
  end;

  // Newton on (B(t) - P) . B'(t) = 0
  T := BestT;
  for J := 1 to NewtonIterations do
  begin
    Q := PointAt(T) - P;
    D1 := DerivativeAt(T);
    F := Dot(Q, D1);
    DF := Dot(D1, D1) + Dot(Q, SecondDerivativeAt(T));
    if Abs(DF) < Epsilon then
      Break;
    T := EnsureRange(T - F / DF, 0, 1);
    if Abs(F / DF) < 1e-12 then
      Break;
  end;
  if Distance(PointAt(T), P) <= Distance(PointAt(BestT), P) then
    Result := T
  else
    Result := BestT;
end;

function TCubicBezier.Reversed: TCubicBezier;
begin
  Result := CubicBezier(P3, P2, P1, P0);
end;

function TCubicBezier.Translated(const D: TVec2): TCubicBezier;
begin
  Result := CubicBezier(P0 + D, P1 + D, P2 + D, P3 + D);
end;

function TCubicBezier.Rotated(const Pivot: TVec2; AngleDeg: double): TCubicBezier;
begin
  Result := CubicBezier(RotatePoint(P0, Pivot, AngleDeg), RotatePoint(P1, Pivot, AngleDeg), RotatePoint(P2, Pivot, AngleDeg), RotatePoint(P3, Pivot, AngleDeg));
end;

function TCubicBezier.Mirrored(const A, B: TVec2): TCubicBezier;
begin
  Result := CubicBezier(MirrorPoint(P0, A, B), MirrorPoint(P1, A, B), MirrorPoint(P2, A, B), MirrorPoint(P3, A, B));
end;

{ Functions }

function CubicBezier(const P0, P1, P2, P3: TVec2): TCubicBezier;
begin
  Result.P0 := P0;
  Result.P1 := P1;
  Result.P2 := P2;
  Result.P3 := P3;
end;

function BezierFromHandles(const Start: TVec2; Angle1, Length1: double; const Finish: TVec2; Angle2, Length2: double): TCubicBezier;
begin
  Result := CubicBezier(Start, PolarPoint(Start, Length1, Angle1), PolarPoint(Finish, Length2, Angle2), Finish);
end;

// Sorts by T1 and drops crossings that are the same point found twice, for
// example where two flattened segments share an end
procedure MergeIntersections(var Hits: TIntersectionArray);
var
  I, N: integer;
  DT: double;
  Duplicate: boolean;
begin
  SortIntersections(Hits);
  N := 0;
  for I := 0 to High(Hits) do
  begin
    Duplicate := False;
    if N > 0 then
    begin
      // A curve can pass through the same point twice at different
      // parameters, so a near point alone is not a duplicate
      DT := Abs(Hits[I].T1 - Hits[N - 1].T1);
      Duplicate := (DT <= MergeParamTolerance) or ((DT <= 1e-4) and PointsNear(Hits[I].Point, Hits[N - 1].Point, DefaultTolerance / 10));
    end;
    if not Duplicate then
    begin
      Hits[N] := Hits[I];
      Inc(N);
    end;
  end;
  SetLength(Hits, N);
end;

function IntersectBezierLine(const C: TCubicBezier; const L: TLine2; ExtendLine: boolean): TIntersectionArray;
var
  Dir: TVec2;
  D0, D1, D2, D3, T, LineT, CurveTol, LineTol: double;
  Roots: TDoubleArray;
  P: TVec2;
begin
  Result := nil;
  Dir := L.P2 - L.P1;
  if Dir.Length < Epsilon then
    Exit;
  Dir := Dir * (1 / Dir.Length);
  // Signed distances of the control points from the line; the curve's own
  // distance is the Bézier with these values, a cubic in t
  D0 := Cross(Dir, C.P0 - L.P1);
  D1 := Cross(Dir, C.P1 - L.P1);
  D2 := Cross(Dir, C.P2 - L.P1);
  D3 := Cross(Dir, C.P3 - L.P1);
  if Max(Max(Abs(D0), Abs(D1)), Max(Abs(D2), Abs(D3))) < Epsilon then
    Exit; // the curve lies along the line
  Roots := SolveCubic(-D0 + 3 * D1 - 3 * D2 + D3, 3 * D0 - 6 * D1 + 3 * D2, -3 * D0 + 3 * D1, D0);

  CurveTol := DefaultTolerance / Max(C.Length, Epsilon);
  LineTol := DefaultTolerance / L.Length;
  for T in Roots do
  begin
    if (T < -CurveTol) or (T > 1 + CurveTol) then
      Continue;
    P := C.PointAt(EnsureRange(T, 0, 1));
    LineT := L.ParamOf(P);
    if ExtendLine or ((LineT >= -LineTol) and (LineT <= 1 + LineTol)) then
      AddIntersection(Result, P, EnsureRange(T, 0, 1), LineT);
  end;
  MergeIntersections(Result);
end;

// Newton on A(s) - B(t) = 0. False if it does not converge inside both curves.
function RefineCurveCrossing(const A, B: TCubicBezier; var S, T: double): boolean;
var
  I: integer;
  F, DA, DB, NegF, NegDB: TVec2;
  Det, DS, DT: double;
begin
  for I := 1 to NewtonIterations do
  begin
    F := A.PointAt(S) - B.PointAt(T);
    if F.Length < 1e-10 then
      Break;
    DA := A.DerivativeAt(S);
    DB := B.DerivativeAt(T);
    NegF := -F;
    NegDB := -DB;
    // Solve DA*dS - DB*dT = -F by Cramer's rule
    Det := Cross(DA, NegDB);
    if Abs(Det) < Epsilon then
      Exit(False);
    DS := Cross(NegF, NegDB) / Det;
    DT := Cross(DA, NegF) / Det;
    S := S + DS;
    T := T + DT;
    if (S < -0.5) or (S > 1.5) or (T < -0.5) or (T > 1.5) then
      Exit(False);
  end;
  Result := (S >= -MergeParamTolerance) and (S <= 1 + MergeParamTolerance) and (T >= -MergeParamTolerance) and
    (T <= 1 + MergeParamTolerance) and (Distance(A.PointAt(EnsureRange(S, 0, 1)), B.PointAt(EnsureRange(T, 0, 1))) <= DefaultTolerance / 10);
  S := EnsureRange(S, 0, 1);
  T := EnsureRange(T, 0, 1);
end;

function IntersectBeziers(const A, B: TCubicBezier): TIntersectionArray;
var
  SA, SB: TCurveSampleArray;
  I, J: integer;
  Hit: TIntersection;
  S, T: double;
begin
  Result := nil;
  // Find crossings of the two polylines, then refine each on the curves
  SA := A.Flatten(CoarseFlatness);
  SB := B.Flatten(CoarseFlatness);
  for I := 1 to High(SA) do
    for J := 1 to High(SB) do
      if IntersectLines(Line2(SA[I - 1].Point, SA[I].Point), Line2(SB[J - 1].Point, SB[J].Point), False, False, Hit) then
      begin
        S := SA[I - 1].T + (SA[I].T - SA[I - 1].T) * EnsureRange(Hit.T1, 0, 1);
        T := SB[J - 1].T + (SB[J].T - SB[J - 1].T) * EnsureRange(Hit.T2, 0, 1);
        if RefineCurveCrossing(A, B, S, T) then
          AddIntersection(Result, A.PointAt(S), S, T);
      end;
  MergeIntersections(Result);
end;

function IntersectBezierCircle(const C: TCubicBezier; const Centre: TVec2; Radius: double): TIntersectionArray;
var
  Samples: TCurveSampleArray;
  SegHits: TIntersectionArray;
  I, J, K: integer;
  T, G, DG: double;
  Q, D1: TVec2;
begin
  Result := nil;
  Samples := C.Flatten(CoarseFlatness);
  for I := 1 to High(Samples) do
  begin
    SegHits := IntersectLineCircle(Line2(Samples[I - 1].Point, Samples[I].Point), False, Centre, Radius);
    for J := 0 to High(SegHits) do
    begin
      T := Samples[I - 1].T + (Samples[I].T - Samples[I - 1].T) * EnsureRange(SegHits[J].T1, 0, 1);
      // Newton on |B(t) - centre|² - r² = 0
      for K := 1 to NewtonIterations do
      begin
        Q := C.PointAt(T) - Centre;
        D1 := C.DerivativeAt(T);
        G := Dot(Q, Q) - Radius * Radius;
        DG := 2 * Dot(Q, D1);
        if Abs(DG) < Epsilon then
          Break;
        T := EnsureRange(T - G / DG, 0, 1);
        if Abs(G / DG) < 1e-12 then
          Break;
      end;
      if Abs(Distance(C.PointAt(T), Centre) - Radius) <= DefaultTolerance / 10 then
        AddIntersection(Result, C.PointAt(T), T, 0);
    end;
  end;
  MergeIntersections(Result);
end;

end.
