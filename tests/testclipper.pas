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

// Checks that the Clipper2 submodule builds and offsets as expected for
// seam allowance.
unit TestClipper;

{$mode ObjFPC}{$H+}

interface

uses
  fpcunit, testregistry, osTestCase;

type
  TTestClipper = class(TOSTestCase)
  published
    procedure TestMitredSquareOffset;
  end;

implementation

uses
  Clipper, Clipper.Core;

procedure TTestClipper.TestMitredSquareOffset;
var
  Square, Offset: TPathsD;
begin
  SetLength(Square, 1);
  Square[0] := MakePathD([0, 0, 100, 0, 100, 100, 0, 100]);
  Offset := InflatePaths(Square, 10, jtMiter, etPolygon);
  AssertEquals('path count', 1, Length(Offset));
  AssertNear('area of 120 mm square', 120 * 120, Abs(Area(Offset)), 0.1);
end;

initialization
  RegisterTest(TTestClipper);

end.
