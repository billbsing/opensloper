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

// Pattern units: formulas worked out in the pattern's unit, geometry in mm.
unit Sloper.Tests.PatternUnits;

{$mode ObjFPC}{$H+}

interface

uses
  fpcunit, testregistry, Sloper.Tests.TestCase, Sloper.Core.Measurements, Sloper.Core.Draft, Sloper.Core.Pattern;

type
  TTestPatternUnits = class(TOSTestCase)
  private
    FSet: TMeasurementSet;
    FPattern: TPattern;
    function Check(Obj: TObject): TObject;
    function Pt(const AName, X, Y: string): TPointObject;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestNewPatternIsMillimetres;
    procedure TestPlainNumbersInPatternUnit;
    procedure TestSuffixConvertsToPatternUnit;
    procedure TestMeasurementsArriveInPatternUnit;
    procedure TestVariablesStayInPatternUnit;
    procedure TestLengthPropertiesArriveInPatternUnit;
    procedure TestAnglesAreNotConverted;
    procedure TestAlongEdgeLengthAndRatio;
    procedure TestBetweenPointsLength;
    procedure TestClearSetsMillimetres;
    procedure TestSavedAndLoaded;
    procedure TestUnknownUnitRefused;
    procedure TestDragInPatternUnit;
    procedure TestDragKeepsSuffixInOtherUnit;
  end;

implementation

uses
  SysUtils, Sloper.Core.Units, Sloper.Core.Geometry, Sloper.Core.Variables, Sloper.Core.Drag, Sloper.Core.PatternFile;

procedure TTestPatternUnits.SetUp;
begin
  FSet := TMeasurementSet.Create;
  FSet.Add('waist', 720);
  FPattern := TPattern.Create;
  FPattern.Measurements := FSet;
end;

procedure TTestPatternUnits.TearDown;
begin
  FreeAndNil(FPattern);
  FreeAndNil(FSet);
end;

function TTestPatternUnits.Check(Obj: TObject): TObject;
begin
  if not Assigned(Obj) then
    Fail('Refused: ' + FPattern.LastError);
  Result := Obj;
end;

function TTestPatternUnits.Pt(const AName, X, Y: string): TPointObject;
begin
  Result := TPointObject(Check(FPattern.AddFreePoint(AName, X, Y)));
end;

procedure TTestPatternUnits.TestNewPatternIsMillimetres;
var
  A: TPointObject;
begin
  AssertTrue(FPattern.Units = muMillimetre);
  A := Pt('A', '10', '2cm');
  FPattern.Evaluate;
  AssertPointsNear('mm', Vec2(10, 20), A.Position);
end;

procedure TTestPatternUnits.TestPlainNumbersInPatternUnit;
var
  A, B: TPointObject;
begin
  FPattern.Units := muCentimetre;
  A := Pt('A', '10', '-2.5');
  B := TPointObject(Check(FPattern.AddOffsetPoint('B', A.Key, omCartesian, '1', '2')));
  FPattern.Evaluate;
  AssertPointsNear('cm becomes mm', Vec2(100, -25), A.Position);
  AssertPointsNear('offset in cm', Vec2(110, -5), B.Position);
  FPattern.Units := muInch;
  FPattern.Evaluate;
  AssertPointsNear('inches', Vec2(254, -63.5), A.Position);
end;

procedure TTestPatternUnits.TestSuffixConvertsToPatternUnit;
var
  A: TPointObject;
  V: TVariable;
begin
  FPattern.Units := muInch;
  A := Pt('A', '400mm', '2.54cm');
  V := TVariable(Check(FPattern.AddVariable('v', '2.54cm + 1')));
  FPattern.Evaluate;
  AssertPointsNear('suffixed numbers keep their size', Vec2(400, 25.4), A.Position);
  AssertNear('variable in inches', 2, V.Value);
end;

procedure TTestPatternUnits.TestMeasurementsArriveInPatternUnit;
var
  A: TPointObject;
  V: TVariable;
begin
  FPattern.Units := muInch;
  V := TVariable(Check(FPattern.AddVariable('quarter', '@waist / 4')));
  A := Pt('A', '@waist / 4 + 1', '0');
  FPattern.Evaluate;
  AssertNear('waist in inches', 720 / 25.4 / 4, V.Value);
  AssertPointsNear('plus an inch', Vec2(180 + 25.4, 0), A.Position);
  FPattern.MeasurementScale := 1.1;
  FPattern.Evaluate;
  AssertNear('trial scale still applies', 1.1 * 720 / 25.4 / 4, V.Value);
end;

procedure TTestPatternUnits.TestVariablesStayInPatternUnit;
var
  A: TPointObject;
begin
  FPattern.Units := muCentimetre;
  Check(FPattern.AddVariable('ease', '1.5'));
  A := Pt('A', '#ease * 2', '0');
  FPattern.Evaluate;
  AssertPointsNear('3 cm', Vec2(30, 0), A.Position);
end;

procedure TTestPatternUnits.TestLengthPropertiesArriveInPatternUnit;
var
  A, B, C, D: TPointObject;
begin
  FPattern.Units := muCentimetre;
  A := Pt('A', '0', '0');
  B := Pt('B', '3', '4');
  Check(FPattern.AddLine(A.Key, B.Key));
  // 5 cm long; 5 * 2 is 10 cm, where 50 * 2 would be 100 cm
  C := Pt('C', 'Line_A_B.length * 2', '0');
  D := Pt('D', 'B.x + 1', 'B.y');
  FPattern.Evaluate;
  AssertPointsNear('length in cm', Vec2(100, 0), C.Position);
  AssertPointsNear('position in cm', Vec2(40, 40), D.Position);
end;

procedure TTestPatternUnits.TestAnglesAreNotConverted;
var
  A, B, C: TPointObject;
  Edge: TLineObject;
begin
  FPattern.Units := muInch;
  A := Pt('A', '0', '0');
  B := Pt('B', '0', '-2');
  Edge := TLineObject(Check(FPattern.AddLine(A.Key, B.Key)));
  // Up the edge (90°), turned a right angle, one inch: to the left
  C := TPointObject(Check(FPattern.AddOffsetPoint('C', A.Key, omPolar, '1', 'Line_A_B.angle + 90')));
  FPattern.Evaluate;
  AssertPointsNear('one inch left', Vec2(-25.4, 0), C.Position);
end;

procedure TTestPatternUnits.TestAlongEdgeLengthAndRatio;
var
  A, B, ByLength, ByRatio: TPointObject;
  Edge: TLineObject;
begin
  FPattern.Units := muCentimetre;
  A := Pt('A', '0', '0');
  B := Pt('B', '10', '0');
  Edge := TLineObject(Check(FPattern.AddLine(A.Key, B.Key)));
  ByLength := TPointObject(Check(FPattern.AddAlongEdgePoint('C', Edge.Key, False, amLength, '2')));
  ByRatio := TPointObject(Check(FPattern.AddAlongEdgePoint('D', Edge.Key, False, amRatio, '0.25')));
  FPattern.Evaluate;
  AssertPointsNear('2 cm along', Vec2(20, 0), ByLength.Position);
  AssertPointsNear('a ratio is not a length', Vec2(25, 0), ByRatio.Position);
end;

procedure TTestPatternUnits.TestBetweenPointsLength;
var
  A, B, C: TPointObject;
begin
  FPattern.Units := muInch;
  A := Pt('A', '0', '0');
  B := Pt('B', '4', '0');
  C := TPointObject(Check(FPattern.AddBetweenPoint('C', A.Key, B.Key, amLength, '1')));
  FPattern.Evaluate;
  AssertPointsNear('an inch along', Vec2(25.4, 0), C.Position);
end;

procedure TTestPatternUnits.TestClearSetsMillimetres;
begin
  FPattern.Units := muInch;
  FPattern.Clear;
  AssertTrue(FPattern.Units = muMillimetre);
end;

procedure TTestPatternUnits.TestSavedAndLoaded;
var
  Loaded: TPattern;
  Text, Err: string;
begin
  FPattern.Units := muCentimetre;
  Pt('A', '10', '0');
  Text := SavePatternToText(FPattern);
  AssertTrue('saved', Pos('"units": "cm"', Text) > 0);
  Loaded := TPattern.Create;
  try
    AssertTrue(Err, LoadPatternFromText(Loaded, Text, Err));
    AssertTrue('cm', Loaded.Units = muCentimetre);
    Loaded.Evaluate;
    AssertPointsNear('same place', Vec2(100, 0), TPointObject(Loaded.FindObject('A')).Position);
    AssertTrue(Err, LoadPatternFromText(Loaded, '{"format": "pattern", "version": 1, "units": "IN"}', Err));
    AssertTrue('any case', Loaded.Units = muInch);
    AssertTrue(Err, LoadPatternFromText(Loaded, '{"format": "pattern", "version": 1}', Err));
    AssertTrue('mm when left out', Loaded.Units = muMillimetre);
  finally
    FreeAndNil(Loaded);
  end;
end;

procedure TTestPatternUnits.TestUnknownUnitRefused;
var
  Err: string;
begin
  AssertFalse(LoadPatternFromText(FPattern, '{"format": "pattern", "version": 1, "units": "ft"}', Err));
  AssertEquals(Format(rsPatternFileUnits, ['ft']), Err);
end;

procedure TTestPatternUnits.TestDragInPatternUnit;
var
  A: TPointObject;
  Err: string;
begin
  FPattern.Units := muInch;
  A := Pt('A', '0', '0');
  FPattern.Evaluate;
  AssertTrue(Err, DragPoint(FPattern, A, Vec2(50.9, 12.7), Err));
  FPattern.Evaluate;
  AssertEquals('to 0.01 in', '2', FPattern.FormulaText(A, 'x'));
  AssertEquals('half an inch', '0.5', FPattern.FormulaText(A, 'y'));
  FPattern.Units := muCentimetre;
  FPattern.Evaluate;
  AssertTrue(Err, DragPoint(FPattern, A, Vec2(33.33, 0), Err));
  AssertEquals('to 0.1 cm', '3.3', FPattern.FormulaText(A, 'x'));
end;

procedure TTestPatternUnits.TestDragKeepsSuffixInOtherUnit;
var
  A: TPointObject;
  Err: string;
begin
  FPattern.Units := muInch;
  A := Pt('A', '10mm', '0');
  FPattern.Evaluate;
  AssertTrue(Err, DragPoint(FPattern, A, Vec2(12.34, 0), Err));
  AssertEquals('stays in mm', '12.3mm', FPattern.FormulaText(A, 'x'));
end;

initialization
  RegisterTest(TTestPatternUnits);
end.
