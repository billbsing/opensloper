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

unit Sloper.Tests.RulerTicks;

{$mode ObjFPC}{$H+}

interface

uses
  fpcunit, testregistry, Sloper.Tests.TestCase, Sloper.Core.Measurements, Sloper.Core.Units, Sloper.UI.View, Sloper.UI.RulerTicks;

type
  TTestRulerTicks = class(TOSTestCase)
  private
    function View(Scale, OriginX, OriginY: double): TViewTransform;
  published
    procedure TestMillimetreSpacingAtDefaultZoom;
    procedure TestInchSpacingAtDefaultZoom;
    procedure TestCentimetreSpacing;
    procedure TestSpacingIsReadableAtEveryZoom;
    procedure TestLabelledIsWholeNumberOfMinor;
    procedure TestHorizontalTicksMatchTheView;
    procedure TestVerticalTicksCountDownTheScreen;
    procedure TestTicksStayOnTheRuler;
    procedure TestTickKinds;
    procedure TestInchTicksAtSixteenths;
    procedure TestEmptyRuler;
    procedure TestLabels;
    procedure TestGridKeepsItsStep;
    procedure TestGridInchMajorIsAnInch;
    procedure TestGridZoomedOutDropsMinorLines;
    procedure TestGridIsReadableAtEveryZoom;
  end;

implementation

uses
  SysUtils, Sloper.Core.Geometry;

function TTestRulerTicks.View(Scale, OriginX, OriginY: double): TViewTransform;
begin
  Result.Scale := Scale;
  Result.OriginX := OriginX;
  Result.OriginY := OriginY;
end;

procedure TTestRulerTicks.TestMillimetreSpacingAtDefaultZoom;
var
  Spacing: TRulerSpacing;
begin
  // 2 px per mm: 5 mm is the first step 6 px apart, 50 mm the first 50 px apart
  Spacing := RulerSpacing(2, muMillimetre);
  AssertNear('minor', 5, Spacing.Minor);
  AssertNear('labelled', 50, Spacing.Labelled);
end;

procedure TTestRulerTicks.TestInchSpacingAtDefaultZoom;
var
  Spacing: TRulerSpacing;
begin
  // 50.8 px per inch
  Spacing := RulerSpacing(2 * 25.4, muInch);
  AssertNear('minor', 1 / 8, Spacing.Minor);
  AssertNear('labelled', 1, Spacing.Labelled);
end;

procedure TTestRulerTicks.TestCentimetreSpacing;
var
  Spacing: TRulerSpacing;
begin
  // 40 px per cm
  Spacing := RulerSpacing(40, muCentimetre);
  AssertNear('minor', 0.2, Spacing.Minor);
  AssertNear('labelled', 2, Spacing.Labelled);
end;

procedure TTestRulerTicks.TestSpacingIsReadableAtEveryZoom;
var
  Scale, PixelsPerUnit: double;
  AUnit: TMeasureUnit;
  Spacing: TRulerSpacing;
begin
  for AUnit := Low(TMeasureUnit) to High(TMeasureUnit) do
  begin
    Scale := MIN_SCALE;
    while Scale <= MAX_SCALE do
    begin
      PixelsPerUnit := Scale * MILLIMETRES_PER_UNIT[AUnit];
      Spacing := RulerSpacing(PixelsPerUnit, AUnit);
      AssertTrue(Format('%s minor at %g', [MEASURE_UNIT_NAMES[AUnit], Scale]), Spacing.Minor * PixelsPerUnit >= MIN_TICK_SPACING);
      AssertTrue(Format('%s labels at %g', [MEASURE_UNIT_NAMES[AUnit], Scale]), Spacing.Labelled * PixelsPerUnit >= MIN_LABEL_SPACING);
      Scale := Scale * 1.1;
    end;
  end;
end;

procedure TTestRulerTicks.TestLabelledIsWholeNumberOfMinor;
var
  Scale, Ratio: double;
  AUnit: TMeasureUnit;
  Spacing: TRulerSpacing;
begin
  for AUnit := Low(TMeasureUnit) to High(TMeasureUnit) do
  begin
    Scale := MIN_SCALE;
    while Scale <= MAX_SCALE do
    begin
      Spacing := RulerSpacing(Scale * MILLIMETRES_PER_UNIT[AUnit], AUnit);
      Ratio := Spacing.Labelled / Spacing.Minor;
      AssertNear(Format('%s at %g', [MEASURE_UNIT_NAMES[AUnit], Scale]), Round(Ratio), Ratio, 1e-6);
      Scale := Scale * 1.1;
    end;
  end;
end;

procedure TTestRulerTicks.TestHorizontalTicksMatchTheView;
var
  AView: TViewTransform;
  Ticks: TRulerTickArray;
  Tick: TRulerTick;
begin
  AView := View(2, 40, 300);
  Ticks := RulerTicks(AView, False, 800, muMillimetre);
  AssertTrue('some ticks', Length(Ticks) > 0);
  for Tick in Ticks do
    AssertNear(Format('at %g mm', [Tick.Value]), AView.ToScreen(Vec2(Tick.Value, 0)).X, Tick.Position);
  // The origin is 40 px in, so the ruler starts at -20 mm, on a tick
  AssertNear('first at the left edge', -20, Ticks[0].Value);
end;

procedure TTestRulerTicks.TestVerticalTicksCountDownTheScreen;
var
  AView: TViewTransform;
  Ticks: TRulerTickArray;
  Index: integer;
begin
  AView := View(2, 40, 300);
  Ticks := RulerTicks(AView, True, 600, muMillimetre);
  AssertTrue('some ticks', Length(Ticks) > 1);
  for Index := 0 to High(Ticks) do
    AssertNear(Format('at %g mm', [Ticks[Index].Value]), AView.ToScreen(Vec2(0, Ticks[Index].Value)).Y, Ticks[Index].Position);
  for Index := 1 to High(Ticks) do
    AssertTrue('larger values sit lower, as model y points down', Ticks[Index].Position > Ticks[Index - 1].Position);
end;

procedure TTestRulerTicks.TestTicksStayOnTheRuler;
var
  Ticks: TRulerTickArray;
  Tick: TRulerTick;
begin
  Ticks := RulerTicks(View(3.7, -123.4, 456.7), False, 500, muCentimetre);
  for Tick in Ticks do
    AssertTrue(Format('%g on the ruler', [Tick.Position]), (Tick.Position >= -1e-6) and (Tick.Position <= 500 + 1e-6));
  Ticks := RulerTicks(View(3.7, -123.4, 456.7), True, 500, muInch);
  for Tick in Ticks do
    AssertTrue(Format('%g on the ruler', [Tick.Position]), (Tick.Position >= -1e-6) and (Tick.Position <= 500 + 1e-6));
end;

procedure TTestRulerTicks.TestTickKinds;
var
  Tick: TRulerTick;
begin
  // 5 mm minor, 50 mm labelled, 25 mm middle
  for Tick in RulerTicks(View(2, 0, 0), False, 400, muMillimetre) do
    if Abs(Tick.Value - 50 * Round(Tick.Value / 50)) < 1e-6 then
      AssertTrue(Format('%g labelled', [Tick.Value]), Tick.Kind = rtLabelled)
    else if Abs(Tick.Value - 25 * Round(Tick.Value / 25)) < 1e-6 then
      AssertTrue(Format('%g middle', [Tick.Value]), Tick.Kind = rtMiddle)
    else
      AssertTrue(Format('%g minor', [Tick.Value]), Tick.Kind = rtMinor);
end;

procedure TTestRulerTicks.TestInchTicksAtSixteenths;
var
  Ticks: TRulerTickArray;
begin
  // 3.9 px per mm is 99 px per inch: room for sixteenths, numbers every inch
  Ticks := RulerTicks(View(3.9, 0, 0), False, 100, muInch);
  AssertNear('step', 1 / 16, Ticks[1].Value - Ticks[0].Value);
  AssertEquals('0 to 1 inch', 17, Length(Ticks));
  AssertTrue('inch labelled', Ticks[16].Kind = rtLabelled);
  AssertTrue('half inch middle', Ticks[8].Kind = rtMiddle);
  AssertTrue('quarter inch minor', Ticks[4].Kind = rtMinor);
end;

procedure TTestRulerTicks.TestEmptyRuler;
begin
  AssertEquals(0, Length(RulerTicks(View(2, 0, 0), False, 0, muMillimetre)));
end;

procedure TTestRulerTicks.TestLabels;
var
  Point: char;
begin
  Point := DefaultFormatSettings.DecimalSeparator;
  AssertEquals('0', RulerLabel(0, 50));
  AssertEquals('no minus zero', '0', RulerLabel(-1e-12, 50));
  AssertEquals('-150', RulerLabel(-150, 50));
  AssertEquals('0' + Point + '5', RulerLabel(0.5, 0.5));
  AssertEquals('1' + Point + '25', RulerLabel(1.25, 0.25));
  AssertEquals('whole step, no decimals', '3', RulerLabel(3, 1));
end;

procedure TTestRulerTicks.TestGridKeepsItsStep;
var
  Spacing: TRulerSpacing;
begin
  // 5 mm at 4 px per mm is 20 px apart: as set, majors every ten
  Spacing := GridSpacing(4, 5, muMillimetre);
  AssertNear('minor', 5, Spacing.Minor);
  AssertNear('major', 50, Spacing.Labelled);
end;

procedure TTestRulerTicks.TestGridInchMajorIsAnInch;
var
  Spacing: TRulerSpacing;
begin
  Spacing := GridSpacing(200, 1 / 8, muInch);
  AssertNear('minor', 1 / 8, Spacing.Minor);
  AssertNear('major', 1, Spacing.Labelled);
  AssertEquals('a step not dividing an inch', 10, GridMajorCount(0.3, muInch));
  AssertEquals('a whole inch', 10, GridMajorCount(1, muInch));
  AssertEquals('metric', 10, GridMajorCount(0.125, muCentimetre));
end;

procedure TTestRulerTicks.TestGridZoomedOutDropsMinorLines;
var
  Spacing: TRulerSpacing;
begin
  // 5 mm at 1 px per mm would be 5 px apart, so the 50 mm lines take over
  Spacing := GridSpacing(1, 5, muMillimetre);
  AssertNear('minor', 50, Spacing.Minor);
  AssertNear('major', 500, Spacing.Labelled);
  // An eighth of an inch at 20 px per inch doubles to a half, 10 px apart
  Spacing := GridSpacing(20, 1 / 8, muInch);
  AssertNear('inch minor', 1 / 2, Spacing.Minor);
  AssertNear('inch major', 1, Spacing.Labelled);
  // Further out, whole inches and then tens
  Spacing := GridSpacing(5, 1 / 8, muInch);
  AssertNear('inches', 10, Spacing.Minor);
  AssertNear('tens', 100, Spacing.Labelled);
end;

procedure TTestRulerTicks.TestGridIsReadableAtEveryZoom;
var
  Scale, PixelsPerUnit: double;
  AUnit: TMeasureUnit;
  Spacing: TRulerSpacing;
begin
  for AUnit := Low(TMeasureUnit) to High(TMeasureUnit) do
  begin
    Scale := MIN_SCALE;
    while Scale <= MAX_SCALE do
    begin
      PixelsPerUnit := Scale * MILLIMETRES_PER_UNIT[AUnit];
      Spacing := GridSpacing(PixelsPerUnit, 0.1, AUnit);
      AssertTrue(Format('%s at %g', [MEASURE_UNIT_NAMES[AUnit], Scale]), Spacing.Minor * PixelsPerUnit >= MIN_GRID_SPACING);
      AssertTrue('major is a multiple', Abs(Spacing.Labelled / Spacing.Minor - Round(Spacing.Labelled / Spacing.Minor)) < 1e-9);
      Scale := Scale * 1.1;
    end;
  end;
end;

initialization
  RegisterTest(TTestRulerTicks);

end.
