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

// Numerical helpers for geometry: polynomial roots and integration.
// No LCL dependency.
unit Sloper.Core.Numeric;

{$mode ObjFPC}{$H+}
{$modeswitch nestedprocvars}

interface

type
  TDoubleArray = array of double;
  TRealFunction = function(X: double): double is nested;

// Real roots of A x² + B x + C = 0, ascending; falls back to linear when A is 0
function SolveQuadratic(A, B, C: double): TDoubleArray;
// Real roots of A x³ + B x² + C x + D = 0, ascending, repeated roots once
function SolveCubic(A, B, C, D: double): TDoubleArray;
// Integral of F over [Lo, Hi] to within about Tolerance
function Integrate(F: TRealFunction; Lo, Hi: double; Tolerance: double = 1e-9): double;

implementation

uses
  Math;

const
  // Coefficients smaller than this, relative to the largest, count as zero
  RELATIVE_ZERO = 1e-12;
  // Five-point Gauss-Legendre nodes and weights on [-1, 1]
  GL_NODES: array[0..4] of double = (0, -0.5384693101056831, 0.5384693101056831, -0.9061798459386640, 0.9061798459386640);
  GL_WEIGHTS: array[0..4] of double = (0.5688888888888889, 0.4786286704993665,
    0.4786286704993665, 0.2369268850561891, 0.2369268850561891);
  MAX_INTEGRATE_DEPTH = 30;

procedure AddRoot(var Roots: TDoubleArray; X: double);
var
  N: integer;
begin
  N := Length(Roots);
  SetLength(Roots, N + 1);
  Roots[N] := X;
end;

procedure SortAndMerge(var Roots: TDoubleArray);
var
  I, J, N: integer;
  Tmp: double;
begin
  for I := 1 to High(Roots) do
  begin
    Tmp := Roots[I];
    J := I - 1;
    while (J >= 0) and (Roots[J] > Tmp) do
    begin
      Roots[J + 1] := Roots[J];
      Dec(J);
    end;
    Roots[J + 1] := Tmp;
  end;
  N := 0;
  for I := 0 to High(Roots) do
    if (N = 0) or not SameValue(Roots[I], Roots[N - 1], 1e-9 * Max(1, Abs(Roots[I]))) then
    begin
      Roots[N] := Roots[I];
      Inc(N);
    end;
  SetLength(Roots, N);
end;

function SolveQuadratic(A, B, C: double): TDoubleArray;
var
  Disc, Q, Scale: double;
begin
  Result := nil;
  Scale := Max(Abs(A), Max(Abs(B), Abs(C)));
  if Scale = 0 then
    Exit;
  if Abs(A) <= RELATIVE_ZERO * Scale then
  begin
    if Abs(B) > RELATIVE_ZERO * Scale then
      AddRoot(Result, -C / B);
    Exit;
  end;
  Disc := B * B - 4 * A * C;
  if Disc < -RELATIVE_ZERO * B * B then
    Exit;
  if Disc <= RELATIVE_ZERO * B * B then
    AddRoot(Result, -B / (2 * A))
  else
  begin
    // Numerically stable form avoids cancellation when B² ≫ 4AC
    Q := -0.5 * (B + Sign(B) * Sqrt(Disc));
    if B = 0 then
      Q := -0.5 * Sqrt(Disc);
    AddRoot(Result, Q / A);
    AddRoot(Result, C / Q);
  end;
  SortAndMerge(Result);
end;

function PolishCubicRoot(A, B, C, D, X: double): double;
var
  I: integer;
  F, DF: double;
begin
  Result := X;
  for I := 1 to 4 do
  begin
    F := ((A * Result + B) * Result + C) * Result + D;
    DF := (3 * A * Result + 2 * B) * Result + C;
    if DF = 0 then
      Break;
    Result := Result - F / DF;
  end;
  // Keep the unpolished value if polishing made it worse (near double roots)
  if Abs(((A * Result + B) * Result + C) * Result + D) > Abs(((A * X + B) * X + C) * X + D) then
    Result := X;
end;

function SolveCubic(A, B, C, D: double): TDoubleArray;
var
  Scale, P, Q, Disc, Shift, R, Phi, U: double;
  K: integer;
begin
  Result := nil;
  Scale := Max(Max(Abs(A), Abs(B)), Max(Abs(C), Abs(D)));
  if Scale = 0 then
    Exit;
  if Abs(A) <= RELATIVE_ZERO * Scale then
    Exit(SolveQuadratic(B, C, D));

  // Depressed cubic t³ + P t + Q = 0 with x = t - B / 3A
  Shift := B / (3 * A);
  P := (3 * A * C - B * B) / (3 * A * A);
  Q := (2 * B * B * B - 9 * A * B * C + 27 * A * A * D) / (27 * A * A * A);
  Disc := Q * Q / 4 + P * P * P / 27;

  if Abs(Disc) <= 1e-14 * Max(1, Max(Q * Q, Abs(P * P * P))) then
  begin
    // Repeated root
    if Abs(P) <= 1e-14 then
      AddRoot(Result, -Shift)
    else
    begin
      AddRoot(Result, 3 * Q / P - Shift);
      AddRoot(Result, -3 * Q / (2 * P) - Shift);
    end;
  end
  else if Disc > 0 then
  begin
    U := Sqrt(Disc);
    AddRoot(Result, Power(Abs(-Q / 2 + U), 1 / 3) * Sign(-Q / 2 + U) + Power(Abs(-Q / 2 - U), 1 / 3) * Sign(-Q / 2 - U) - Shift);
  end
  else
  begin
    // Three real roots: trigonometric method
    R := 2 * Sqrt(-P / 3);
    Phi := ArcCos(EnsureRange(3 * Q / (P * R), -1, 1));
    for K := 0 to 2 do
      AddRoot(Result, R * Cos((Phi - 2 * Pi * K) / 3) - Shift);
  end;

  for K := 0 to High(Result) do
    Result[K] := PolishCubicRoot(A, B, C, D, Result[K]);
  SortAndMerge(Result);
end;

function GaussLegendre(F: TRealFunction; Lo, Hi: double): double;
var
  I: integer;
  Mid, Half: double;
begin
  Mid := (Lo + Hi) / 2;
  Half := (Hi - Lo) / 2;
  Result := 0;
  for I := 0 to High(GL_NODES) do
    Result := Result + GL_WEIGHTS[I] * F(Mid + Half * GL_NODES[I]);
  Result := Result * Half;
end;

function IntegrateRange(F: TRealFunction; Lo, Hi, Whole, Tolerance: double; Depth: integer): double;
var
  Mid, Left, Right: double;
begin
  Mid := (Lo + Hi) / 2;
  Left := GaussLegendre(F, Lo, Mid);
  Right := GaussLegendre(F, Mid, Hi);
  if (Depth >= MAX_INTEGRATE_DEPTH) or (Abs(Left + Right - Whole) <= Tolerance) then
    Exit(Left + Right);
  Result := IntegrateRange(F, Lo, Mid, Left, Tolerance / 2, Depth + 1) + IntegrateRange(F, Mid, Hi, Right, Tolerance / 2, Depth + 1);
end;

function Integrate(F: TRealFunction; Lo, Hi: double; Tolerance: double): double;
begin
  if Lo = Hi then
    Exit(0);
  Result := IntegrateRange(F, Lo, Hi, GaussLegendre(F, Lo, Hi), Tolerance, 0);
end;

end.
