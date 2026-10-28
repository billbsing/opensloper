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

unit TestPattern;

{$mode ObjFPC}{$H+}

interface

uses
  fpcunit, testregistry, osTestCase, osGeometry, osEvalTypes, osMeasurements,
  osDraft, osPattern;

type
  TTestPattern = class(TOSTestCase)
  private
    FSet: TMeasurementSet;
    FPattern: TPattern;
    // A at (0, 0) and B at (100, 0), joined by Line_A_B
    procedure Basic(out A, B: TPointObject; out L: TLineObject);
    procedure AssertAt(const Msg: string; P: TPointObject; X, Y: double);
    function Check(Obj: TObject): TObject;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestFreePointAndAutoNames;
    procedure TestOffsetPolar;
    procedure TestOffsetCartesianWithMeasurements;
    procedure TestLineNameAndProperties;
    procedure TestFormulaReadsLineLength;
    procedure TestSecondLineGetsNumber;
    procedure TestRenamePointUpdatesDerivedNames;
    procedure TestCustomLineNameIsKept;
    procedure TestAlongLine;
    procedure TestAlongLinePastEndIsInvalid;
    procedure TestAlongCurve;
    procedure TestCurveHandlesAndProperties;
    procedure TestNegativeHandleIsInvalid;
    procedure TestCoincidentEndsAreInvalid;
    procedure TestForwardReference;
    procedure TestCycleThroughObjectsRefused;
    procedure TestSelfReferenceRefused;
    procedure TestFieldErrorRefusesAdd;
    procedure TestFieldNameInEvaluationError;
    procedure TestTypeChecks;
    procedure TestUnknownField;
    procedure TestUnknownProperty;
    procedure TestMissingMeasurementBlocks;
    procedure TestKeepsLastGoodPosition;
    procedure TestDeleteInUseRefused;
    procedure TestEvaluationOrder;
  end;

implementation

uses
  SysUtils, osNames, osFormula, osEvaluator;

procedure TTestPattern.SetUp;
begin
  FSet := TMeasurementSet.Create;
  FSet.Add('waist', 720);
  FSet.Add('hip', 960);
  FPattern := TPattern.Create;
  FPattern.Measurements := FSet;
end;

procedure TTestPattern.TearDown;
begin
  FPattern.Free;
  FSet.Free;
end;

function TTestPattern.Check(Obj: TObject): TObject;
begin
  if Obj = nil then
    Fail('Refused: ' + FPattern.LastError);
  Result := Obj;
end;

procedure TTestPattern.Basic(out A, B: TPointObject; out L: TLineObject);
begin
  A := TPointObject(Check(FPattern.AddFreePoint('', '0', '0')));
  B := TPointObject(Check(FPattern.AddOffsetPoint('', A.Key, omPolar, '100', '0')));
  L := TLineObject(Check(FPattern.AddLine(A.Key, B.Key)));
end;

procedure TTestPattern.AssertAt(const Msg: string; P: TPointObject; X, Y: double);
begin
  AssertTrue(Msg + ' state: ' + P.Message, P.State = esValid);
  AssertPointsNear(Msg, Vec2(X, Y), P.Position);
end;

procedure TTestPattern.TestFreePointAndAutoNames;
var
  A, B: TFreePoint;
begin
  A := FPattern.AddFreePoint('', '10', '-5');
  B := FPattern.AddFreePoint('', '0', '0');
  AssertEquals('A', A.Name);
  AssertEquals('B', B.Name);
  AssertEquals('p1', A.Key);
  AssertEquals('p2', B.Key);
  AssertEquals('C', FPattern.AddFreePoint('', '0', '0').Name);
  FPattern.Evaluate;
  AssertAt('A', A, 10, -5);
end;

procedure TTestPattern.TestOffsetPolar;
var
  A, B: TPointObject;
  C: TOffsetPoint;
  L: TLineObject;
begin
  Basic(A, B, L);
  C := TOffsetPoint(Check(FPattern.AddOffsetPoint('C', B.Key, omPolar, '50', '90')));
  FPattern.Evaluate;
  AssertAt('B', B, 100, 0);
  AssertAt('C straight up from B', C, 100, 50);
end;

procedure TTestPattern.TestOffsetCartesianWithMeasurements;
var
  A, B: TPointObject;
  L: TLineObject;
  C: TOffsetPoint;
begin
  Basic(A, B, L);
  Check(FPattern.AddVariable('ease', '20'));
  C := TOffsetPoint(Check(FPattern.AddOffsetPoint('C', B.Key, omCartesian, '0', '@waist/4 + #ease')));
  FPattern.Evaluate;
  AssertAt('C', C, 100, 200);
end;

procedure TTestPattern.TestLineNameAndProperties;
var
  A, B: TPointObject;
  L: TLineObject;
begin
  Basic(A, B, L);
  AssertEquals('Line_A_B', L.Name);
  AssertEquals('l1', L.Key);
  FPattern.Evaluate;
  AssertTrue(L.State = esValid);
  AssertNear('length', 100, L.PropertyValue('length'));
  AssertNear('angle', 0, L.PropertyValue('angle'));
end;

procedure TTestPattern.TestFormulaReadsLineLength;
var
  A, B: TPointObject;
  L: TLineObject;
  D: TOffsetPoint;
begin
  Basic(A, B, L);
  D := TOffsetPoint(Check(FPattern.AddOffsetPoint('D', A.Key, omPolar,
    'Line_A_B.length / 2', 'Line_A_B.angle + 90')));
  AssertEquals('stored', '{l1}.length / 2', D.Field('length').StoredText);
  FPattern.Evaluate;
  AssertAt('D', D, 0, 50);
end;

procedure TTestPattern.TestSecondLineGetsNumber;
var
  A, B: TPointObject;
  L: TLineObject;
begin
  Basic(A, B, L);
  AssertEquals('Line_A_B2', FPattern.AddLine(A.Key, B.Key).Name);
  AssertEquals('reverse direction', 'Line_B_A', FPattern.AddLine(B.Key, A.Key).Name);
end;

procedure TTestPattern.TestRenamePointUpdatesDerivedNames;
var
  A, B: TPointObject;
  L: TLineObject;
  D: TOffsetPoint;
begin
  Basic(A, B, L);
  D := TOffsetPoint(Check(FPattern.AddOffsetPoint('D', A.Key, omPolar, 'Line_A_B.length / 2', '90')));
  AssertTrue(FPattern.Rename(A, 'Front'));
  AssertEquals('line follows', 'Line_Front_B', L.Name);
  AssertEquals('formula follows', 'Line_Front_B.length / 2', FPattern.FormulaText(D, 'length'));
  AssertFalse('name taken', FPattern.Rename(B, 'front'));
end;

procedure TTestPattern.TestCustomLineNameIsKept;
var
  A, B: TPointObject;
  L: TLineObject;
begin
  Basic(A, B, L);
  AssertTrue(FPattern.Rename(L, 'Waistline'));
  AssertTrue(FPattern.Rename(A, 'Front'));
  AssertEquals('Waistline', L.Name);
  AssertEquals('named at creation', 'Hem',
    FPattern.AddLine(A.Key, B.Key, erOutline, 'Hem').Name);
end;

procedure TTestPattern.TestAlongLine;
var
  A, B: TPointObject;
  L: TLineObject;
begin
  Basic(A, B, L);
  FPattern.AddAlongEdgePoint('P', L.Key, False, amLength, '30');
  FPattern.AddAlongEdgePoint('Q', L.Key, True, amLength, '30');
  FPattern.AddAlongEdgePoint('R', L.Key, False, amRatio, '0.25');
  FPattern.AddAlongEdgePoint('S', L.Key, True, amRatio, '0.25');
  FPattern.Evaluate;
  AssertAt('from start', TPointObject(FPattern.FindObject('P')), 30, 0);
  AssertAt('from end', TPointObject(FPattern.FindObject('Q')), 70, 0);
  AssertAt('ratio', TPointObject(FPattern.FindObject('R')), 25, 0);
  AssertAt('ratio from end', TPointObject(FPattern.FindObject('S')), 75, 0);
end;

procedure TTestPattern.TestAlongLinePastEndIsInvalid;
var
  A, B: TPointObject;
  L: TLineObject;
  P, Q: TPointObject;
begin
  Basic(A, B, L);
  P := TPointObject(Check(FPattern.AddAlongEdgePoint('P', L.Key, False, amLength, '150')));
  Q := TPointObject(Check(FPattern.AddOffsetPoint('Q', P.Key, omPolar, '10', '90')));
  FPattern.Evaluate;
  AssertTrue('invalid', P.State = esInvalid);
  AssertEquals(Format(rsDraftPastEnd, ['150', 'Line_A_B', '100']), P.Message);
  AssertTrue('dependent blocked', Q.State = esBlocked);
  AssertEquals(Format(rsEvalBlocked, ['P']), Q.Message);
  AssertTrue(FPattern.SetFormula(P, 'value', '90'));
  FPattern.Evaluate;
  AssertAt('fixed', Q, 90, 10);
end;

procedure TTestPattern.TestAlongCurve;
var
  A, B: TPointObject;
  L: TLineObject;
  C: TCurveObject;
  M: TPointObject;
begin
  Basic(A, B, L);
  // Symmetric curve: handles straight up, 100 long; its middle is (50, 75)
  C := TCurveObject(Check(FPattern.AddCurve(A.Key, B.Key, '90', '100', '90', '100')));
  AssertEquals('Curve_A_B', C.Name);
  M := TPointObject(Check(FPattern.AddAlongEdgePoint('M', C.Key, False, amRatio, '0.5')));
  FPattern.Evaluate;
  AssertAt('middle', M, 50, 75);
end;

procedure TTestPattern.TestCurveHandlesAndProperties;
var
  A, B: TPointObject;
  L: TLineObject;
  C: TCurveObject;
begin
  Basic(A, B, L);
  C := TCurveObject(Check(FPattern.AddCurve(A.Key, B.Key, '60', '@waist / 18', '120', '40')));
  FPattern.Evaluate;
  AssertTrue(C.State = esValid);
  AssertPointsNear('first handle', PolarPoint(Vec2(0, 0), 40, 60), C.Curve.P1);
  AssertNear('angle1', 60, C.PropertyValue('angle1'));
  AssertNear('angle2', 120, C.PropertyValue('angle2'));
  AssertTrue('longer than the chord', C.PropertyValue('length') > 100);
end;

procedure TTestPattern.TestNegativeHandleIsInvalid;
var
  A, B: TPointObject;
  L: TLineObject;
  C: TCurveObject;
begin
  Basic(A, B, L);
  C := TCurveObject(Check(FPattern.AddCurve(A.Key, B.Key, '90', '-5', '90', '10')));
  FPattern.Evaluate;
  AssertTrue(C.State = esInvalid);
  AssertEquals(rsDraftNegativeHandle, C.Message);
end;

procedure TTestPattern.TestCoincidentEndsAreInvalid;
var
  A, B, E: TPointObject;
  L, L2: TLineObject;
  P: TPointObject;
begin
  Basic(A, B, L);
  E := TPointObject(Check(FPattern.AddOffsetPoint('E', A.Key, omPolar, '0', '0')));
  L2 := TLineObject(Check(FPattern.AddLine(A.Key, E.Key)));
  P := TPointObject(Check(FPattern.AddOffsetPoint('P', A.Key, omPolar, 'Line_A_E.length', '0')));
  FPattern.Evaluate;
  AssertTrue('line invalid', L2.State = esInvalid);
  AssertEquals(rsDraftSamePlace, L2.Message);
  AssertTrue('formula reader blocked', P.State = esBlocked);
end;

procedure TTestPattern.TestForwardReference;
var
  A, B: TFreePoint;
begin
  A := FPattern.AddFreePoint('', '10', '0');
  B := FPattern.AddFreePoint('', '3', '4');
  // A, earlier in the list, now reads B
  AssertTrue(FPattern.LastError, FPattern.SetFormula(A, 'x', 'B.x + 5'));
  FPattern.Evaluate;
  AssertAt('A', A, 8, 0);
end;

procedure TTestPattern.TestCycleThroughObjectsRefused;
var
  A, B: TPointObject;
  L: TLineObject;
  C: TPointObject;
begin
  Basic(A, B, L);
  C := TPointObject(Check(FPattern.AddOffsetPoint('C', B.Key, omPolar, '10', '90')));
  AssertFalse(FPattern.SetFormula(A, 'x', 'C.x'));
  AssertEquals(Format(rsPatternCycle, ['A', 'C', 'C', 'A']), FPattern.LastError);
  AssertFalse('through a line', FPattern.SetFormula(B, 'length', 'Line_A_B.length'));
  AssertEquals(Format(rsPatternCycle, ['B', 'Line_A_B', 'Line_A_B', 'B']), FPattern.LastError);
  AssertTrue('unrelated is fine', FPattern.SetFormula(C, 'length', 'Line_A_B.length'));
end;

procedure TTestPattern.TestSelfReferenceRefused;
var
  A: TFreePoint;
begin
  A := FPattern.AddFreePoint('', '0', '0');
  AssertFalse(FPattern.SetFormula(A, 'x', 'A.y'));
  AssertEquals(Format(rsPatternUsesItself, ['A']), FPattern.LastError);
  AssertEquals('field', 'x', FPattern.LastErrorField);
end;

procedure TTestPattern.TestFieldErrorRefusesAdd;
begin
  AssertNull(FPattern.AddFreePoint('', '0', '1 +'));
  AssertEquals('field', 'y', FPattern.LastErrorField);
  AssertEquals(rsFormulaEndsTooSoon, FPattern.LastError);
  AssertEquals('nothing added', 0, FPattern.ObjectCount);
  AssertEquals('ID not used up', 'p1', FPattern.AddFreePoint('', '0', '0').Key);
end;

procedure TTestPattern.TestFieldNameInEvaluationError;
var
  A: TFreePoint;
begin
  A := FPattern.AddFreePoint('', '1 / (@hip - 960)', '0');
  FPattern.Evaluate;
  AssertTrue(A.State = esError);
  AssertEquals('x: ' + rsFormulaDivideByZero, A.Message);
end;

procedure TTestPattern.TestTypeChecks;
var
  A, B: TPointObject;
  L: TLineObject;
begin
  Basic(A, B, L);
  AssertNull('line as base', FPattern.AddOffsetPoint('X', L.Key, omPolar, '1', '0'));
  AssertEquals(Format(rsDraftNotAPoint, ['Line_A_B']), FPattern.LastError);
  AssertNull('unknown base', FPattern.AddOffsetPoint('X', 'p99', omPolar, '1', '0'));
  AssertEquals(Format(rsPatternUnknownObject, ['p99']), FPattern.LastError);
  AssertNull('point as edge', FPattern.AddAlongEdgePoint('X', A.Key, False, amLength, '1'));
  AssertEquals(Format(rsDraftNotAnEdge, ['A']), FPattern.LastError);
  AssertNull('line to a line', FPattern.AddLine(A.Key, L.Key));
end;

procedure TTestPattern.TestUnknownField;
var
  A: TFreePoint;
begin
  A := FPattern.AddFreePoint('', '0', '0');
  AssertFalse(FPattern.SetFormula(A, 'length', '1'));
  AssertEquals(Format(rsPatternNoField, ['A', 'length']), FPattern.LastError);
end;

procedure TTestPattern.TestUnknownProperty;
begin
  FPattern.AddFreePoint('', '0', '0');
  AssertNull(FPattern.AddFreePoint('', 'A.length', '0'));
  AssertEquals(Format(rsFormulaUnknownProperty, ['A', 'length']), FPattern.LastError);
end;

procedure TTestPattern.TestMissingMeasurementBlocks;
var
  A: TFreePoint;
begin
  A := FPattern.AddFreePoint('', '@hip / 4', '0');
  FSet.Delete(FSet.Find('hip'));
  FPattern.Evaluate;
  AssertTrue(A.State = esBlocked);
  AssertEquals(Format(rsEvalBlocked, ['@hip']), A.Message);
end;

procedure TTestPattern.TestKeepsLastGoodPosition;
var
  A: TFreePoint;
begin
  A := FPattern.AddFreePoint('', 'sqrt(@hip - 951)', '7');
  FPattern.Evaluate;
  AssertAt('A', A, 3, 7);
  FSet.Find('hip').Value := 900;
  FPattern.Evaluate;
  AssertTrue(A.State = esError);
  AssertPointsNear('last good position', Vec2(3, 7), A.Position);
end;

procedure TTestPattern.TestDeleteInUseRefused;
var
  A, B: TPointObject;
  L: TLineObject;
begin
  Basic(A, B, L);
  AssertFalse(FPattern.Delete(B));
  AssertEquals(Format(rsPatternInUse, ['B', 'Line_A_B']), FPattern.LastError);
  AssertTrue('line first', FPattern.Delete(L));
  AssertTrue('then the point', FPattern.Delete(B));
  AssertEquals(1, FPattern.ObjectCount);
  FPattern.Evaluate;
  AssertAt('A still fine', A, 0, 0);
end;

procedure TTestPattern.TestEvaluationOrder;
var
  A, B: TPointObject;
  L: TLineObject;
  Order: TEvalNodeArray;
  I, J, K: integer;
  Found: boolean;
begin
  Basic(A, B, L);
  FPattern.AddVariable('ease', '@waist / 100');
  FPattern.AddAlongEdgePoint('', L.Key, False, amLength, '#ease');
  FPattern.SetFormula(A, 'x', '0 * Line_A_B2.length');
  FPattern.Evaluate;
  Order := FPattern.Evaluator.Order;
  for I := 0 to High(Order) do
    for J := 0 to High(Order[I].Deps) do
    begin
      Found := False;
      for K := 0 to I - 1 do
        if Order[K] = Order[I].Deps[J] then
          Found := True;
      AssertTrue(Order[I].Deps[J].DisplayName + ' before ' + Order[I].DisplayName, Found);
    end;
end;

initialization
  RegisterTest(TTestPattern);

end.
