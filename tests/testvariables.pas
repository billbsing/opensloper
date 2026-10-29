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

unit TestVariables;

{$mode ObjFPC}{$H+}

interface

uses
  fpcunit, testregistry, osTestCase, osEvalTypes, osMeasurements, osVariables, osPattern;

type
  TTestVariables = class(TOSTestCase)
  private
    FSet: TMeasurementSet;
    FPattern: TPattern;
    function AddVar(const AName, Formula: string): TVariable;
    procedure AssertValid(const Msg: string; V: TVariable; Expected: double);
    procedure LoadText(const Text: string);
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestAddAssignsIds;
    procedure TestEvaluateChain;
    procedure TestOrderDoesNotMatter;
    procedure TestStoredFormUsesIds;
    procedure TestNameChecks;
    procedure TestBadFormulaRefused;
    procedure TestUnknownMeasurementRefused;
    procedure TestVariablesCannotUseObjects;
    procedure TestSelfReferenceRefused;
    procedure TestCycleRefused;
    procedure TestRefusedEditKeepsOldFormula;
    procedure TestRenameKeepsFormulas;
    procedure TestDeleteInUseRefused;
    procedure TestIdsNotReused;
    procedure TestErrorAndBlockedStates;
    procedure TestFixingRestoresStates;
    procedure TestKeepsLastGoodValue;
    procedure TestOtherMeasurementSet;
    procedure TestNoMeasurementSet;
    procedure TestSaveAndLoad;
    procedure TestLoadKeepsBadFormula;
    procedure TestLoadedCycleIsAnError;
    procedure TestLoadErrors;
    procedure TestNewIdsAfterLoad;
  end;

implementation

uses
  SysUtils, fpjson, osNames, osFormula, osEvaluator, osJSON;

procedure TTestVariables.SetUp;
begin
  FSet := TMeasurementSet.Create;
  FSet.Add('waist', 720);
  FSet.Add('hip', 960);
  FPattern := TPattern.Create;
  FPattern.Measurements := FSet;
end;

procedure TTestVariables.TearDown;
begin
  FreeAndNil(FPattern);
  FreeAndNil(FSet);
end;

function TTestVariables.AddVar(const AName, Formula: string): TVariable;
begin
  Result := FPattern.AddVariable(AName, Formula);
  if Result = nil then
    Fail(Format('Adding #%s = %s failed: %s', [AName, Formula, FPattern.LastError]));
end;

procedure TTestVariables.AssertValid(const Msg: string; V: TVariable; Expected: double);
begin
  AssertTrue(Msg + ' state: ' + V.Message, V.State = esValid);
  AssertNear(Msg, Expected, V.Value);
end;

procedure TTestVariables.LoadText(const Text: string);
var
  Data: TJSONData;
  Err: string;
begin
  Data := GetJSON(Text);
  try
    if not FPattern.LoadVariables(Data, Err) then
      Fail('Load failed: ' + Err);
  finally
    FreeAndNil(Data);
  end;
end;

procedure TTestVariables.TestAddAssignsIds;
begin
  AssertEquals('v1', AddVar('ease_waist', '20').Key);
  AssertEquals('v2', AddVar('ease_hip', '30').Key);
  AssertEquals(2, FPattern.VariableCount);
end;

procedure TTestVariables.TestEvaluateChain;
var
  A, B: TVariable;
begin
  A := AddVar('ease', '20');
  B := AddVar('front_waist', '@waist / 4 + #ease');
  FPattern.Evaluate;
  AssertValid('ease', A, 20);
  AssertValid('front_waist', B, 200);
end;

procedure TTestVariables.TestOrderDoesNotMatter;
var
  A, B, C: TVariable;
begin
  // a is first in the list but ends up reading c, added last
  A := AddVar('a', '1');
  B := AddVar('b', '#a * 10');
  C := AddVar('c', '5');
  AssertTrue(FPattern.LastError, FPattern.SetFormula(A, 'formula', '#c + 1'));
  FPattern.Evaluate;
  AssertValid('c', C, 5);
  AssertValid('a', A, 6);
  AssertValid('b', B, 60);
end;

procedure TTestVariables.TestStoredFormUsesIds;
var
  B: TVariable;
begin
  AddVar('ease', '20');
  B := AddVar('front', '@waist/4 + #EASE');
  AssertEquals('stored', '@waist/4 + {v1}', B.Formula.StoredText);
  AssertEquals('display', '@waist/4 + #ease', FPattern.FormulaText(B, 'formula'));
end;

procedure TTestVariables.TestNameChecks;
var
  Msg: string;
begin
  AddVar('ease', '20');
  AssertFalse('duplicate', FPattern.CheckVariableName('Ease', nil, Msg));
  AssertEquals(Format(rsNameTaken, ['Ease']), Msg);
  AssertFalse('invalid', FPattern.CheckVariableName('2nd', nil, Msg));
  AssertFalse('reserved', FPattern.CheckVariableName('max', nil, Msg));
  AssertNull('add refused', FPattern.AddVariable('ease', '1'));
  AssertEquals(Format(rsNameTaken, ['ease']), FPattern.LastError);
  // Measurements, variables and objects are separate namespaces
  AssertNotNull('same name as a measurement', FPattern.AddVariable('waist', '1'));
  AssertNotNull('same name as a point', FPattern.AddFreePoint('ease', '0', '0'));
end;

procedure TTestVariables.TestBadFormulaRefused;
begin
  AssertNull(FPattern.AddVariable('ease', '20 +'));
  AssertEquals(rsFormulaEndsTooSoon, FPattern.LastError);
  AssertEquals('field', 'formula', FPattern.LastErrorField);
  AssertEquals('position', 5, FPattern.LastErrorPos);
  AssertEquals('nothing added', 0, FPattern.VariableCount);
  AssertEquals('ID not used up', 'v1', AddVar('ease', '20').Key);
end;

procedure TTestVariables.TestUnknownMeasurementRefused;
begin
  AssertNull(FPattern.AddVariable('ease', '@chest / 10'));
  AssertEquals(Format(rsFormulaUnknownMeasurement, ['chest']), FPattern.LastError);
end;

procedure TTestVariables.TestVariablesCannotUseObjects;
begin
  FPattern.AddFreePoint('A', '0', '0');
  AssertNull(FPattern.AddVariable('ease', 'A.x + 1'));
  AssertEquals(Format(rsFormulaUnknownName, ['A']), FPattern.LastError);
end;

procedure TTestVariables.TestSelfReferenceRefused;
var
  A: TVariable;
begin
  A := AddVar('a', '1');
  AssertFalse(FPattern.SetFormula(A, 'formula', '#a + 1'));
  AssertEquals(Format(rsPatternUsesItself, ['#a']), FPattern.LastError);
end;

procedure TTestVariables.TestCycleRefused;
var
  A, B: TVariable;
begin
  A := AddVar('a', '1');
  B := AddVar('b', '#a + 1');
  AddVar('c', '#b + 1');
  AssertFalse(FPattern.SetFormula(A, 'formula', '#c * 2'));
  AssertEquals(Format(rsPatternCycle, ['#a', '#c', '#c', '#a']), FPattern.LastError);
  AssertTrue('unrelated edit still fine', FPattern.SetFormula(B, 'formula', '7'));
  AssertTrue('and now a may read c', FPattern.SetFormula(A, 'formula', '#c * 2'));
end;

procedure TTestVariables.TestRefusedEditKeepsOldFormula;
var
  A: TVariable;
begin
  A := AddVar('a', '@hip / 2');
  AssertFalse(FPattern.SetFormula(A, 'formula', '@hip /'));
  AssertEquals('@hip / 2', FPattern.FormulaText(A, 'formula'));
  FPattern.Evaluate;
  AssertValid('a', A, 480);
end;

procedure TTestVariables.TestRenameKeepsFormulas;
var
  A, B: TVariable;
begin
  A := AddVar('ease', '20');
  B := AddVar('front', '#ease * 2');
  AssertTrue(FPattern.Rename(A, 'ease_waist'));
  AssertEquals('#ease_waist * 2', FPattern.FormulaText(B, 'formula'));
  AssertFalse('onto another name', FPattern.Rename(A, 'FRONT'));
  AssertTrue('change of case only', FPattern.Rename(A, 'Ease_Waist'));
  FPattern.Evaluate;
  AssertValid('front', B, 40);
end;

procedure TTestVariables.TestDeleteInUseRefused;
var
  A, B: TVariable;
begin
  A := AddVar('ease', '20');
  B := AddVar('front', '#ease * 2');
  AddVar('back', '#ease * 3');
  AssertFalse(FPattern.Delete(A));
  AssertEquals(Format(rsPatternInUse, ['#ease', '#front, #back']), FPattern.LastError);
  AssertTrue('unused one can go', FPattern.Delete(B));
  AssertEquals(2, FPattern.VariableCount);
end;

procedure TTestVariables.TestIdsNotReused;
begin
  AddVar('a', '1');
  FPattern.Delete(AddVar('b', '2'));
  AssertEquals('v3', AddVar('c', '3').Key);
end;

procedure TTestVariables.TestErrorAndBlockedStates;
var
  A, B, C: TVariable;
begin
  A := AddVar('a', '1 / (@hip - 960)');
  B := AddVar('b', '#a + 1');
  C := AddVar('c', '@waist');
  FPattern.Evaluate;
  AssertTrue('a error', A.State = esError);
  AssertEquals(rsFormulaDivideByZero, A.Message);
  AssertTrue('b blocked', B.State = esBlocked);
  AssertEquals(Format(rsEvalBlocked, ['#a']), B.Message);
  AssertValid('unaffected', C, 720);
end;

procedure TTestVariables.TestFixingRestoresStates;
var
  A, B: TVariable;
begin
  A := AddVar('a', '1 / (@hip - 960)');
  B := AddVar('b', '#a + 1');
  FPattern.Evaluate;
  FSet.Find('hip').Value := 961;
  FPattern.Evaluate;
  AssertValid('a', A, 1);
  AssertValid('b', B, 2);
  AssertEquals('message cleared', '', B.Message);
end;

procedure TTestVariables.TestKeepsLastGoodValue;
var
  A: TVariable;
begin
  A := AddVar('a', 'sqrt(@hip - 951)');
  FPattern.Evaluate;
  AssertValid('a', A, 3);
  FSet.Find('hip').Value := 900;
  FPattern.Evaluate;
  AssertTrue('error', A.State = esError);
  AssertNear('last good value kept', 3, A.Value);
end;

procedure TTestVariables.TestOtherMeasurementSet;
var
  A: TVariable;
  Other: TMeasurementSet;
  M: TEvalNode;
begin
  A := AddVar('a', '@hip / 4');
  Other := TMeasurementSet.Create;
  try
    Other.Add('hip', 1000);
    FPattern.Measurements := Other;
    FPattern.Evaluate;
    AssertValid('other person', A, 250);
    Other.Delete(Other.Find('hip'));
    FPattern.Evaluate;
    M := FPattern.FindNode('@hip');
    AssertTrue('measurement node fails', M.State = esError);
    AssertEquals(Format(rsMeasurementNotInSet, ['hip']), M.Message);
    AssertTrue('variable blocked', A.State = esBlocked);
    AssertEquals(Format(rsEvalBlocked, ['@hip']), A.Message);
  finally
    FPattern.Measurements := FSet;
    FreeAndNil(Other);
  end;
end;

procedure TTestVariables.TestNoMeasurementSet;
var
  A: TVariable;
begin
  A := AddVar('a', '@hip / 4');
  FPattern.Measurements := nil;
  FPattern.Evaluate;
  AssertTrue(A.State = esBlocked);
  AssertNull('cannot type measurements', FPattern.AddVariable('b', '@hip'));
end;

procedure TTestVariables.TestSaveAndLoad;
var
  Arr: TJSONArray;
  Loaded: TPattern;
  Err: string;
begin
  AddVar('ease', '20').Description := 'Waist ease';
  AddVar('front', '@waist/4 + #ease');
  Arr := FPattern.SaveVariables;
  try
    AssertEquals(
      '['#10 +
      '  {'#10 +
      '    "id": "v1",'#10 +
      '    "name": "ease",'#10 +
      '    "formula": "20",'#10 +
      '    "description": "Waist ease"'#10 +
      '  },'#10 +
      '  {'#10 +
      '    "id": "v2",'#10 +
      '    "name": "front",'#10 +
      '    "formula": "@waist/4 + {v1}",'#10 +
      '    "description": ""'#10 +
      '  }'#10 +
      ']'#10, JSONToText(Arr));
    Loaded := TPattern.Create;
    try
      Loaded.Measurements := FSet;
      AssertTrue(Err, Loaded.LoadVariables(Arr, Err));
      Loaded.Evaluate;
      AssertValid('front', Loaded.FindVariable('front'), 200);
      AssertEquals('display', '@waist/4 + #ease',
        Loaded.FormulaText(Loaded.FindVariable('front'), 'formula'));
    finally
      FreeAndNil(Loaded);
    end;
  finally
    FreeAndNil(Arr);
  end;
end;

procedure TTestVariables.TestLoadKeepsBadFormula;
var
  V: TVariable;
  Saved: TJSONArray;
begin
  LoadText('[{"id": "v1", "name": "a", "formula": "1 +"}]');
  V := FPattern.FindVariable('a');
  FPattern.Evaluate;
  AssertTrue('error state', V.State = esError);
  Saved := FPattern.SaveVariables;
  try
    AssertEquals('text kept', '1 +', TJSONObject(Saved.Items[0]).Strings['formula']);
  finally
    FreeAndNil(Saved);
  end;
end;

procedure TTestVariables.TestLoadedCycleIsAnError;
begin
  LoadText('[{"id": "v1", "name": "a", "formula": "{v2} + 1"},' +
    ' {"id": "v2", "name": "b", "formula": "{v1} * 2"},' +
    ' {"id": "v3", "name": "c", "formula": "3"},' +
    ' {"id": "v4", "name": "d", "formula": "{v1}"}]');
  FPattern.Evaluate;
  AssertTrue('a', FPattern.FindVariable('a').State = esError);
  AssertEquals(rsEvalCycle, FPattern.FindVariable('a').Message);
  AssertTrue('b', FPattern.FindVariable('b').State = esError);
  AssertValid('c', FPattern.FindVariable('c'), 3);
  AssertTrue('d reads the cycle', FPattern.FindVariable('d').State = esBlocked);
end;

procedure TTestVariables.TestLoadErrors;
var
  Data: TJSONData;
  Err: string;

  procedure Check(const Text, Msg: string);
  begin
    Data := GetJSON(Text);
    try
      AssertFalse(Text, FPattern.LoadVariables(Data, Err));
      AssertEquals(Text, Msg, Err);
      AssertEquals('emptied', 0, FPattern.VariableCount);
    finally
      FreeAndNil(Data);
    end;
  end;

begin
  Check('{"id": "v1"}', rsPatternVariableList);
  Check('[{"name": "a", "formula": "1"}]', rsPatternVariableBadId);
  Check('[{"id": "v1", "name": "a", "formula": "1"}, {"id": "v1", "name": "b", "formula": "1"}]',
    rsPatternVariableBadId);
  Check('[{"id": "v1", "name": "a b", "formula": "1"}]',
    Format(rsPatternVariableBadName, [Format(rsNameInvalid, ['a b'])]));
  Check('[{"id": "v1", "name": "a", "formula": "1"}, {"id": "v2", "name": "A", "formula": "1"}]',
    Format(rsPatternVariableBadName, [Format(rsNameTaken, ['A'])]));
  Check('[{"id": "v1", "name": "a"}]', Format(rsPatternVariableNoFormula, ['a']));
end;

procedure TTestVariables.TestNewIdsAfterLoad;
begin
  LoadText('[{"id": "v7", "name": "a", "formula": "1"}, {"id": "v3", "name": "b", "formula": "2"}]');
  AssertEquals('v8', AddVar('c', '3').Key);
end;

initialization
  RegisterTest(TTestVariables);

end.
