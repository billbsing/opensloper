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

// Base test case with tolerance helpers. Never compare floats exactly.
unit osTestCase;

{$mode ObjFPC}{$H+}

interface

uses
  fpcunit, osGeometry;

type
  TOSTestCase = class(TTestCase)
  protected
    procedure AssertNear(const Msg: string; Expected, Actual: double;
      Tolerance: double = DefaultTolerance);
    procedure AssertPointsNear(const Msg: string; const Expected, Actual: TVec2;
      Tolerance: double = DefaultTolerance);
  end;

implementation

uses
  SysUtils;

procedure TOSTestCase.AssertNear(const Msg: string; Expected, Actual: double;
  Tolerance: double);
begin
  AssertEquals(Msg, Expected, Actual, Tolerance);
end;

procedure TOSTestCase.AssertPointsNear(const Msg: string; const Expected,
  Actual: TVec2; Tolerance: double);
begin
  if not PointsNear(Expected, Actual, Tolerance) then
    Fail(Format('%s: expected (%.4f, %.4f) but was (%.4f, %.4f)',
      [Msg, Expected.X, Expected.Y, Actual.X, Actual.Y]));
end;

end.
