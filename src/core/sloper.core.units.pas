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

// Units of length: mm, cm and inches. A pattern's formulas are worked out in
// its unit, measurements are shown in the preferred one, and geometry, files
// and exports stay in mm. No LCL dependency.
unit Sloper.Core.Units;

{$mode ObjFPC}{$H+}

interface

type
  TMeasureUnit = (muMillimetre, muCentimetre, muInch);

const
  MeasureUnitNames: array[TMeasureUnit] of string = ('mm', 'cm', 'in');
  MillimetresPerUnit: array[TMeasureUnit] of double = (1, 10, 25.4);
  // Dragged lengths are rounded to 0.1 mm, 0.1 cm or 0.01 in
  DragUnitDecimals: array[TMeasureUnit] of integer = (1, 1, 2);

// The unit with this name (mm, cm or in, any case)
function MeasureUnitFromName(const AName: string; out AUnit: TMeasureUnit): boolean;

implementation

uses
  SysUtils;

function MeasureUnitFromName(const AName: string; out AUnit: TMeasureUnit): boolean;
var
  Candidate: TMeasureUnit;
begin
  AUnit := muMillimetre;
  for Candidate := Low(TMeasureUnit) to High(TMeasureUnit) do
    if SameText(AName, MeasureUnitNames[Candidate]) then
    begin
      AUnit := Candidate;
      Exit(True);
    end;
  Result := False;
end;

end.
