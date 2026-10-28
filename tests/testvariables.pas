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
  fpcunit, testregistry, osTestCase, osEvalTypes, osMeasurements, osVariables;

type
  TTestVariables = class(TOSTestCase)
  private
    FSet: TMeasurementSet;
    FVars: TVariableList;
    function AddVar(const Name, Formula: string): TVariable;
    procedure AssertValid(const Msg: string; V: TVariable; Expected: Double);
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
  SysUtils, fpjson, osNames, osFormula, osJSON;

procedure TTestVariables.SetUp;
begin
  FSet := TMeasurementSet.Create;
  FSet.Add('waist', 720);
  FSet.Add('hip', 960);
  FVars := TVariableList.Create;
  FVars.Measurements := FSet;
end;

procedure TTestVariables.TearDown;
begin
  FVars.Free;
  FSet.Free;
end;

function TTestVariables.AddVar(const Name, Formula: string): TVariable;
begin
  Result := FVars.Add(Name, Formula);
  if Result = nil then
    Fail(Format('Adding #%s = %s failed: %s', [Name, Formula, FVars.LastError]));
end;

procedure TTestVariables.AssertValid(const Msg: string; V: TVariable; Expected: Double);
begin
  AssertTrue(Msg + ' state: ' + V.Message, V.State = esValid);
  AssertNear(Msg, Expected, V.Value);
end;

procedure TTestVariables.TestAddAssignsIds;
begin
  AssertEquals('v1', AddVar('ease_waist', '20').Id);
  AssertEquals('v2', AddVar('ease_hip', '30').Id);
  AssertEquals(2, FVars.Count);
end;

procedure TTestVariables.TestEvaluateChain;
var
  A, B: TVariable;
begin
  A := AddVar('ease', '20');
  B := AddVar('front_waist', '@waist / 4 + #ease');
  FVars.Evaluate;
  AssertValid('ease', A, 20);
  AssertValid('front_waist', B, 200);
end;

procedure TTestVariables.TestOrderDoesNotMatter;
var
  A, B, C: TVariable;
begin
  // A is first in the list but ends up reading C, added last
  A := AddVar('a', '1');
  B := AddVar('b', '#a * 10');
  C := AddVar('c', '5');
  AssertTrue(FVars.LastError, FVars.SetFormula(A, '#c + 1'));
  FVars.Evaluate;
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
  AssertEquals('display', '@waist/4 + #ease', FVars.FormulaText(B));
end;

procedure TTestVariables.TestNameChecks;
var
  Msg: string;
begin
  AddVar('ease', '20');
  AssertFalse('duplicate', FVars.CheckName('Ease', nil, Msg));
  AssertEquals(Format(rsNameTaken, ['Ease']), Msg);
  AssertFalse('invalid', FVars.CheckName('2nd', nil, Msg));
  AssertFalse('reserved', FVars.CheckName('max', nil, Msg));
  AssertNull('add refused', FVars.Add('ease', '1'));
  AssertEquals(Format(rsNameTaken, ['ease']), FVars.LastError);
  // Measurements and variables are separate namespaces
  AssertNotNull('same name as a measurement', FVars.Add('waist', '1'));
end;

procedure TTestVariables.TestBadFormulaRefused;
begin
  AssertNull(FVars.Add('ease', '20 +'));
  AssertEquals(rsFormulaEndsTooSoon, FVars.LastError);
  AssertEquals('position', 5, FVars.LastErrorPos);
  AssertEquals('nothing added', 0, FVars.Count);
end;

procedure TTestVariables.TestUnknownMeasurementRefused;
begin
  AssertNull(FVars.Add('ease', '@chest / 10'));
  AssertEquals(Format(rsFormulaUnknownMeasurement, ['chest']), FVars.LastError);
end;

procedure TTestVariables.TestSelfReferenceRefused;
var
  A: TVariable;
begin
  A := AddVar('a', '1');
  AssertFalse(FVars.SetFormula(A, '#a + 1'));
  AssertEquals(Format(rsVariableUsesItself, ['a']), FVars.LastError);
end;

procedure TTestVariables.TestCycleRefused;
var
  A, B, C: TVariable;
begin
  A := AddVar('a', '1');
  B := AddVar('b', '#a + 1');
  C := AddVar('c', '#b + 1');
  AssertFalse(FVars.SetFormula(A, '#c * 2'));
  AssertEquals(Format(rsVariableCycle, ['a', 'c', 'c', 'a']), FVars.LastError);
  AssertTrue('unrelated edit still fine', FVars.SetFormula(B, '7'));
  AssertTrue('and now a may read c', FVars.SetFormula(A, '#c * 2'));
end;

procedure TTestVariables.TestRefusedEditKeepsOldFormula;
var
  A: TVariable;
begin
  A := AddVar('a', '@hip / 2');
  AssertFalse(FVars.SetFormula(A, '@hip /'));
  AssertEquals('@hip / 2', FVars.FormulaText(A));
  FVars.Evaluate;
  AssertValid('a', A, 480);
end;

procedure TTestVariables.TestRenameKeepsFormulas;
var
  A, B: TVariable;
begin
  A := AddVar('ease', '20');
  B := AddVar('front', '#ease * 2');
  AssertTrue(FVars.Rename(A, 'ease_waist'));
  AssertEquals('#ease_waist * 2', FVars.FormulaText(B));
  AssertFalse('onto another name', FVars.Rename(A, 'FRONT'));
  AssertTrue('change of case only', FVars.Rename(A, 'Ease_Waist'));
  FVars.Evaluate;
  AssertValid('front', B, 40);
end;

procedure TTestVariables.TestDeleteInUseRefused;
var
  A, B: TVariable;
begin
  A := AddVar('ease', '20');
  B := AddVar('front', '#ease * 2');
  AddVar('back', '#ease * 3');
  AssertFalse(FVars.Delete(A));
  AssertEquals(Format(rsVariableInUse, ['ease', '#front, #back']), FVars.LastError);
  AssertTrue('unused one can go', FVars.Delete(B));
  AssertEquals(2, FVars.Count);
end;

procedure TTestVariables.TestIdsNotReused;
begin
  AddVar('a', '1');
  FVars.Delete(AddVar('b', '2'));
  AssertEquals('v3', AddVar('c', '3').Id);
end;

procedure TTestVariables.TestErrorAndBlockedStates;
var
  A, B, C: TVariable;
begin
  A := AddVar('a', '1 / (@hip - 960)');
  B := AddVar('b', '#a + 1');
  C := AddVar('c', '@waist');
  FVars.Evaluate;
  AssertTrue('a error', A.State = esError);
  AssertEquals(rsFormulaDivideByZero, A.Message);
  AssertTrue('b blocked', B.State = esBlocked);
  AssertEquals(Format(rsVariableBlocked, ['a']), B.Message);
  AssertValid('unaffected', C, 720);
end;

procedure TTestVariables.TestFixingRestoresStates;
var
  A, B: TVariable;
begin
  A := AddVar('a', '1 / (@hip - 960)');
  B := AddVar('b', '#a + 1');
  FVars.Evaluate;
  FSet.Find('hip').Value := 961;
  FVars.Evaluate;
  AssertValid('a', A, 1);
  AssertValid('b', B, 2);
  AssertEquals('message cleared', '', B.Message);
end;

procedure TTestVariables.TestKeepsLastGoodValue;
var
  A: TVariable;
begin
  A := AddVar('a', 'sqrt(@hip - 951)');
  FVars.Evaluate;
  AssertValid('a', A, 3);
  FSet.Find('hip').Value := 900;
  FVars.Evaluate;
  AssertTrue('error', A.State = esError);
  AssertNear('last good value kept', 3, A.Value);
end;

procedure TTestVariables.TestOtherMeasurementSet;
var
  A: TVariable;
  Other: TMeasurementSet;
begin
  A := AddVar('a', '@hip / 4');
  Other := TMeasurementSet.Create;
  try
    Other.Add('hip', 1000);
    FVars.Measurements := Other;
    FVars.Evaluate;
    AssertValid('other person', A, 250);
    Other.Delete(Other.Find('hip'));
    FVars.Evaluate;
    AssertTrue('missing measurement', A.State = esError);
    AssertEquals(Format(rsFormulaNoValue, ['@hip']), A.Message);
  finally
    FVars.Measurements := FSet;
    Other.Free;
  end;
end;

procedure TTestVariables.TestNoMeasurementSet;
var
  A: TVariable;
begin
  A := AddVar('a', '@hip / 4');
  FVars.Measurements := nil;
  FVars.Evaluate;
  AssertTrue(A.State = esError);
  AssertNull('cannot type measurements', FVars.Add('b', '@hip'));
end;

procedure TTestVariables.TestSaveAndLoad;
var
  Arr: TJSONArray;
  Text, Err: string;
  Loaded: TVariableList;
begin
  AddVar('ease', '20').Description := 'Waist ease';
  AddVar('front', '@waist/4 + #ease');
  Arr := FVars.SaveToJSON;
  try
    Text := JSONToText(Arr);
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
      ']'#10, Text);
    Loaded := TVariableList.Create;
    try
      Loaded.Measurements := FSet;
      AssertTrue(Err, Loaded.LoadFromJSON(Arr, Err));
      Loaded.Evaluate;
      AssertValid('front', Loaded.FindByName('front'), 200);
      AssertEquals('display', '@waist/4 + #ease', Loaded.FormulaText(Loaded.FindByName('front')));
    finally
      Loaded.Free;
    end;
  finally
    Arr.Free;
  end;
end;

function ParseArray(const Text: string): TJSONData;
begin
  Result := GetJSON(Text);
end;

procedure TTestVariables.TestLoadKeepsBadFormula;
var
  Data: TJSONData;
  Err: string;
  V: TVariable;
  Saved: TJSONArray;
begin
  Data := ParseArray('[{"id": "v1", "name": "a", "formula": "1 +"}]');
  try
    AssertTrue(Err, FVars.LoadFromJSON(Data, Err));
  finally
    Data.Free;
  end;
  V := FVars.FindByName('a');
  FVars.Evaluate;
  AssertTrue('error state', V.State = esError);
  Saved := FVars.SaveToJSON;
  try
    AssertEquals('text kept', '1 +', TJSONObject(Saved.Items[0]).Strings['formula']);
  finally
    Saved.Free;
  end;
end;

procedure TTestVariables.TestLoadedCycleIsAnError;
var
  Data: TJSONData;
  Err: string;
begin
  Data := ParseArray('[{"id": "v1", "name": "a", "formula": "{v2} + 1"},' +
    ' {"id": "v2", "name": "b", "formula": "{v1} * 2"},' +
    ' {"id": "v3", "name": "c", "formula": "3"},' +
    ' {"id": "v4", "name": "d", "formula": "{v1}"}]');
  try
    AssertTrue(Err, FVars.LoadFromJSON(Data, Err));
  finally
    Data.Free;
  end;
  FVars.Evaluate;
  AssertTrue('a', FVars.FindByName('a').State = esError);
  AssertEquals(rsVariableInCycle, FVars.FindByName('a').Message);
  AssertTrue('b', FVars.FindByName('b').State = esError);
  AssertValid('c', FVars.FindByName('c'), 3);
  AssertTrue('d reads the cycle', FVars.FindByName('d').State in [esError, esBlocked]);
end;

procedure TTestVariables.TestLoadErrors;
var
  Data: TJSONData;
  Err: string;

  procedure Check(const Text, Msg: string);
  begin
    Data := ParseArray(Text);
    try
      AssertFalse(Text, FVars.LoadFromJSON(Data, Err));
      AssertEquals(Text, Msg, Err);
      AssertEquals('emptied', 0, FVars.Count);
    finally
      Data.Free;
    end;
  end;

begin
  Check('{"id": "v1"}', rsVariableList);
  Check('[{"name": "a", "formula": "1"}]', rsVariableBadId);
  Check('[{"id": "v1", "name": "a", "formula": "1"}, {"id": "v1", "name": "b", "formula": "1"}]',
    rsVariableBadId);
  Check('[{"id": "v1", "name": "a b", "formula": "1"}]',
    Format(rsVariableBadName, [Format(rsNameInvalid, ['a b'])]));
  Check('[{"id": "v1", "name": "a", "formula": "1"}, {"id": "v2", "name": "A", "formula": "1"}]',
    Format(rsVariableBadName, [Format(rsNameTaken, ['A'])]));
  Check('[{"id": "v1", "name": "a"}]', Format(rsVariableNoFormula, ['a']));
end;

procedure TTestVariables.TestNewIdsAfterLoad;
var
  Data: TJSONData;
  Err: string;
begin
  Data := ParseArray('[{"id": "v7", "name": "a", "formula": "1"}, {"id": "v3", "name": "b", "formula": "2"}]');
  try
    AssertTrue(Err, FVars.LoadFromJSON(Data, Err));
  finally
    Data.Free;
  end;
  AssertEquals('v8', AddVar('c', '3').Id);
end;

initialization
  RegisterTest(TTestVariables);

end.
