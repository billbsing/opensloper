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

  // Lengths a new object starts with
  TStartingLength = (slPieceAllowance, slSeamTolerance, slArcRadius, slOffsetDistance, slCornerRadius, slStitchSpacing,
    slStitchSize, slHoleSize, slButtonSize, slMatchSize);

const
  MEASURE_UNIT_NAMES: array[TMeasureUnit] of string = ('mm', 'cm', 'in');
  MILLIMETRES_PER_UNIT: array[TMeasureUnit] of double = (1, 10, 25.4);
  // Dragged lengths are rounded to 0.1 mm, 0.1 cm or 0.01 in
  DRAG_UNIT_DECIMALS: array[TMeasureUnit] of integer = (1, 1, 2);
  // Round values in each unit, as formula text, rather than converted mm:
  // an inch pattern starts with a 3/8 in allowance, not 0.3937 in
  STARTING_LENGTHS: array[TStartingLength, TMeasureUnit] of string = (
    ('10', '1', '0.375'),     // piece allowance
    ('1', '0.1', '0.04'),     // seam tolerance
    ('50', '5', '2'),         // arc radius
    ('10', '1', '0.5'),       // offset distance
    ('10', '1', '0.5'),       // corner radius
    ('4', '0.4', '0.125'),    // stitch spacing
    ('1', '0.1', '0.04'),     // stitch hole size
    ('4', '0.4', '0.125'),    // hole marker
    ('15', '1.5', '0.625'),   // button marker
    ('3', '0.3', '0.125'));   // match dot

// The unit with this name (mm, cm or in, any case)
function MeasureUnitFromName(const AName: string; out AUnit: TMeasureUnit): boolean;
// Millimetres as shown in AUnit, to READOUT_DECIMALS and without trailing
// zeros or "-0", and without the unit's name
function FormatLength(Millimetres: double; AUnit: TMeasureUnit): string;
// FormatLength followed by the unit's name: "1.25 in"
function LengthWithUnit(Millimetres: double; AUnit: TMeasureUnit): string;
// Millimetres as formula text in AUnit, rounded to Decimals, without "-0"
function LengthFormulaText(Millimetres: double; AUnit: TMeasureUnit; Decimals: integer): string;
// Rounded to DRAG_UNIT_DECIMALS: 0.1 mm, 0.1 cm or 0.01 in
function RoundLengthFormulaText(Millimetres: double; AUnit: TMeasureUnit): string;

implementation

uses
  SysUtils, Math, Sloper.Core.JSON;

const
  // Lengths are shown to 0.1 mm, 0.01 cm or 0.001 in
  READOUT_DECIMALS: array[TMeasureUnit] of integer = (1, 2, 3);

function MeasureUnitFromName(const AName: string; out AUnit: TMeasureUnit): boolean;
var
  Candidate: TMeasureUnit;
begin
  AUnit := muMillimetre;
  for Candidate := Low(TMeasureUnit) to High(TMeasureUnit) do
    if SameText(AName, MEASURE_UNIT_NAMES[Candidate]) then
    begin
      AUnit := Candidate;
      Exit(True);
    end;
  Result := False;
end;

function FormatLength(Millimetres: double; AUnit: TMeasureUnit): string;
var
  Settings: TFormatSettings;
  Scale, Rounded: double;
begin
  Scale := IntPower(10, READOUT_DECIMALS[AUnit]);
  Rounded := Round(Millimetres / MILLIMETRES_PER_UNIT[AUnit] * Scale) / Scale;
  // No "-0"
  if Rounded = 0 then
    Rounded := 0;
  Settings := DefaultFormatSettings;
  Settings.DecimalSeparator := '.';
  Result := FormatFloat('0.###', Rounded, Settings);
end;

function LengthWithUnit(Millimetres: double; AUnit: TMeasureUnit): string;
begin
  Result := FormatLength(Millimetres, AUnit) + ' ' + MEASURE_UNIT_NAMES[AUnit];
end;

// Dividing a whole number leaves no binary noise (135.20000000000002) for the
// shortest round-trip form to print, as RoundTo would
function LengthFormulaText(Millimetres: double; AUnit: TMeasureUnit; Decimals: integer): string;
var
  Scale, Rounded: double;
begin
  Scale := IntPower(10, Decimals);
  Rounded := Round(Millimetres / MILLIMETRES_PER_UNIT[AUnit] * Scale) / Scale;
  if Rounded = 0 then
    Rounded := 0;
  Result := FormatJSONFloat(Rounded);
end;

function RoundLengthFormulaText(Millimetres: double; AUnit: TMeasureUnit): string;
begin
  Result := LengthFormulaText(Millimetres, AUnit, DRAG_UNIT_DECIMALS[AUnit]);
end;

end.
