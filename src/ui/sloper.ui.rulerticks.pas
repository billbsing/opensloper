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

// Where the canvas rulers put their ticks and numbers, in mm, cm or inches.
// Ticks are as close as stays readable at the zoom; inches divide in halves
// down to sixteenths, the metric units in 1, 2 and 5. Kept free of the LCL
// so it can be unit-tested.
unit Sloper.UI.RulerTicks;

{$mode ObjFPC}{$H+}

interface

uses
  Sloper.Core.Measurements, Sloper.UI.View;

const
  // Closest ticks and numbers may come, in pixels
  MinTickSpacing = 6;
  MinLabelSpacing = 50;

type
  TRulerTickKind = (rtMinor, rtMiddle, rtLabelled);

  TRulerTick = record
    // In the ruler's unit
    Value: double;
    // Pixels along the ruler, as on the canvas
    Position: double;
    Kind: TRulerTickKind;
  end;
  TRulerTickArray = array of TRulerTick;

  // In the ruler's unit; Labelled is a whole number of Minor steps
  TRulerSpacing = record
    Minor, Labelled: double;
  end;

function RulerSpacing(PixelsPerUnit: double; AUnit: TMeasureUnit): TRulerSpacing;
// The ticks on a ruler Length pixels long. A vertical ruler counts down the
// screen, as model y does.
function RulerTicks(const View: TViewTransform; Vertical: boolean; Length: double; AUnit: TMeasureUnit): TRulerTickArray;
// A labelled tick's number, with as many decimals as the spacing needs
function RulerLabel(Value, Labelled: double): string;

implementation

uses
  SysUtils, Math;

const
  // Steps beyond the last are its multiples by ten
  // 1, 2 and 5 times a power of ten, from a hundredth up
  MetricSteps: array[0..2] of double = (1, 2, 5);
  MetricFirstPower = -2;
  InchSteps: array[0..7] of double = (1 / 16, 1 / 8, 1 / 4, 1 / 2, 1, 2, 5, 10);
  Tolerance = 1e-9;

// The Index-th step of the unit's series, which runs on by tens
function StepAt(AUnit: TMeasureUnit; Index: integer): double;
var
  Count: integer;
begin
  if AUnit = muInch then
  begin
    if Index <= High(InchSteps) then
      Exit(InchSteps[Index]);
    Count := Index - High(InchSteps) + 2;
    Result := InchSteps[High(InchSteps) - 2 + Count mod 3] * IntPower(10, Count div 3);
  end
  else
    Result := MetricSteps[Index mod Length(MetricSteps)] * IntPower(10, Index div Length(MetricSteps) + MetricFirstPower);
end;

function IsWholeMultiple(Value, Step: double): boolean;
begin
  Result := Abs(Value / Step - Round(Value / Step)) < Tolerance;
end;

function RulerSpacing(PixelsPerUnit: double; AUnit: TMeasureUnit): TRulerSpacing;
const
  // Far beyond the smallest zoom, so the loops always end
  MaxSteps = 60;
var
  Index: integer;
begin
  Index := 0;
  while (Index < MaxSteps) and (StepAt(AUnit, Index) * PixelsPerUnit < MinTickSpacing) do
    Inc(Index);
  Result.Minor := StepAt(AUnit, Index);
  while (Index < MaxSteps) and ((StepAt(AUnit, Index) * PixelsPerUnit < MinLabelSpacing) or not IsWholeMultiple(StepAt(AUnit, Index), Result.Minor)) do
    Inc(Index);
  Result.Labelled := StepAt(AUnit, Index);
end;

function RulerTicks(const View: TViewTransform; Vertical: boolean; Length: double; AUnit: TMeasureUnit): TRulerTickArray;
var
  PixelsPerUnit, Origin, Low, High: double;
  Spacing: TRulerSpacing;
  PerLabel, First, Last, Index, Count: int64;
  Tick: TRulerTick;
begin
  Result := nil;
  PixelsPerUnit := View.Scale * MillimetresPerUnit[AUnit];
  if (PixelsPerUnit <= 0) or (Length <= 0) then
    Exit;
  Spacing := RulerSpacing(PixelsPerUnit, AUnit);
  PerLabel := Round(Spacing.Labelled / Spacing.Minor);
  if Vertical then
    Origin := View.OriginY
  else
    Origin := View.OriginX;
  // The values at the two ends of the ruler
  Low := -Origin / PixelsPerUnit;
  High := (Length - Origin) / PixelsPerUnit;
  // Counted in whole steps, so long rulers gather no rounding
  First := Ceil64(Low / Spacing.Minor - Tolerance);
  Last := Floor64(High / Spacing.Minor + Tolerance);
  SetLength(Result, Max(Last - First + 1, 0));
  Count := 0;
  for Index := First to Last do
  begin
    Tick.Value := Index * Spacing.Minor;
    Tick.Position := Origin + Tick.Value * PixelsPerUnit;
    if Index mod PerLabel = 0 then
      Tick.Kind := rtLabelled
    else if (PerLabel mod 2 = 0) and (Index mod (PerLabel div 2) = 0) then
      Tick.Kind := rtMiddle
    else
      Tick.Kind := rtMinor;
    Result[Count] := Tick;
    Inc(Count);
  end;
end;

function RulerLabel(Value, Labelled: double): string;
var
  Decimals: integer;
  Rounded: double;
begin
  Decimals := 0;
  while (Decimals < 4) and not IsWholeMultiple(Labelled * IntPower(10, Decimals), 1) do
    Inc(Decimals);
  Rounded := RoundTo(Value, -Decimals);
  // No "-0" at the origin
  if Abs(Rounded) < Tolerance then
    Rounded := 0;
  Result := FloatToStrF(Rounded, ffFixed, 15, Decimals);
end;

end.
