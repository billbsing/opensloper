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

unit TestNumeric;

{$mode ObjFPC}{$H+}
{$modeswitch nestedprocvars}

interface

uses
  fpcunit, testregistry, osTestCase, osNumeric;

type
  TTestNumeric = class(TOSTestCase)
  private
    procedure AssertRoots(const Msg: string; const Expected: array of double;
      const Actual: TDoubleArray);
  published
    procedure TestQuadraticTwoRoots;
    procedure TestQuadraticDoubleRoot;
    procedure TestQuadraticNoRoots;
    procedure TestQuadraticFallsBackToLinear;
    procedure TestQuadraticAvoidsCancellation;
    procedure TestCubicThreeRoots;
    procedure TestCubicOneRoot;
    procedure TestCubicRepeatedRoots;
    procedure TestCubicFallsBackToQuadratic;
    procedure TestIntegratePolynomial;
    procedure TestIntegrateSine;
  end;

implementation

uses
  SysUtils;

procedure TTestNumeric.AssertRoots(const Msg: string; const Expected: array of double;
  const Actual: TDoubleArray);
var
  I: integer;
begin
  AssertEquals(Msg + ' count', Length(Expected), Length(Actual));
  for I := 0 to High(Expected) do
    AssertNear(Format('%s root %d', [Msg, I]), Expected[I], Actual[I], 1e-9);
end;

procedure TTestNumeric.TestQuadraticTwoRoots;
begin
  AssertRoots('(x-1)(x-3)', [1, 3], SolveQuadratic(1, -4, 3));
  AssertRoots('2(x+2)(x-0.5)', [-2, 0.5], SolveQuadratic(2, 3, -2));
end;

procedure TTestNumeric.TestQuadraticDoubleRoot;
begin
  AssertRoots('(x-2)²', [2], SolveQuadratic(1, -4, 4));
end;

procedure TTestNumeric.TestQuadraticNoRoots;
begin
  AssertRoots('x²+1', [], SolveQuadratic(1, 0, 1));
  AssertRoots('all zero', [], SolveQuadratic(0, 0, 0));
end;

procedure TTestNumeric.TestQuadraticFallsBackToLinear;
begin
  AssertRoots('2x-6', [3], SolveQuadratic(0, 2, -6));
end;

procedure TTestNumeric.TestQuadraticAvoidsCancellation;
begin
  // Roots 1e-6 and 1e6: the naive formula loses the small one
  AssertRoots('wide roots', [1e-6, 1e6], SolveQuadratic(1, -(1e6 + 1e-6), 1));
end;

procedure TTestNumeric.TestCubicThreeRoots;
begin
  AssertRoots('(x-1)(x-2)(x-3)', [1, 2, 3], SolveCubic(1, -6, 11, -6));
  AssertRoots('scaled', [-1, 0, 1], SolveCubic(-4, 0, 4, 0));
end;

procedure TTestNumeric.TestCubicOneRoot;
begin
  // (x-2)(x²+1)
  AssertRoots('one real', [2], SolveCubic(1, -2, 1, -2));
end;

procedure TTestNumeric.TestCubicRepeatedRoots;
begin
  AssertRoots('(x-1)³', [1], SolveCubic(1, -3, 3, -1));
  // (x-1)²(x-4)
  AssertRoots('double and single', [1, 4], SolveCubic(1, -6, 9, -4));
end;

procedure TTestNumeric.TestCubicFallsBackToQuadratic;
begin
  AssertRoots('x²-1', [-1, 1], SolveCubic(0, 1, 0, -1));
end;

procedure TTestNumeric.TestIntegratePolynomial;

  function F(X: double): double;
  begin
    Result := 3 * X * X + 1;
  end;

begin
  AssertNear('x³ + x over [0, 2]', 10, Integrate(@F, 0, 2), 1e-9);
  AssertNear('empty range', 0, Integrate(@F, 1, 1), 1e-12);
end;

procedure TTestNumeric.TestIntegrateSine;

  function F(X: double): double;
  begin
    Result := Sin(X);
  end;

begin
  AssertNear('sin over [0, pi]', 2, Integrate(@F, 0, Pi), 1e-9);
end;

initialization
  RegisterTest(TTestNumeric);

end.
