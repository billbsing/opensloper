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

// The side panel's editable lists, without the GUI: variable cells committed
// through the document, the Measurements tab's pending edits, and writing
// several measurements at once.
unit Sloper.Tests.PanelEdits;

{$mode ObjFPC}{$H+}

interface

uses
  fpcunit, testregistry, Sloper.Tests.TestCase, Sloper.Core.Measurements, Sloper.Document.PatternDocument,
  Sloper.UI.PanelEdits;

type
  TTestPanelEdits = class(TOSTestCase)
  private
    FDocument: TPatternDocument;
    FPending: TPendingMeasurements;
    FFolder: string;
    function VariableKey(const AName: string): string;
    function WriteSet: string;
    function ReadSet(const FileName: string): TMeasurementSet;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestVariableFormulaIsOneStep;
    procedure TestVariableRename;
    procedure TestVariableDescription;
    procedure TestRefusedFormulaChangesNothing;
    procedure TestRefusedNameChangesNothing;
    procedure TestReadOnlyColumnRefused;
    procedure TestPendingStartsFromSet;
    procedure TestPendingRefusesBadValue;
    procedure TestPendingValueForMissingKey;
    procedure TestPendingNewKey;
    procedure TestPendingKeyOnlyForNewRows;
    procedure TestPendingNeedsValues;
    procedure TestChangeMeasurementsWritesOnce;
    procedure TestChangeMeasurementsAllOrNothing;
    procedure TestDocumentChangeMeasurements;
    procedure TestMeasurementFileChanged;
    procedure TestParseValue;
    procedure TestMaterialFieldsAreSteps;
    procedure TestMaterialSizeFields;
    procedure TestMaterialUnchangedMakesNoStep;
    procedure TestMaterialRefusals;
    procedure TestMaterialAddAndDelete;
  end;

implementation

uses
  SysUtils, Sloper.Core.Variables, Sloper.Core.Draft, Sloper.Core.JSON, Sloper.Core.PatternMaterials;

procedure TTestPanelEdits.SetUp;
begin
  FDocument := TPatternDocument.Create;
  FPending := TPendingMeasurements.Create;
  FFolder := ConcatPaths([GetTempDir, 'opensloper-paneledits-test']);
  ForceDirectories(FFolder);
  FDocument.BeginChange('Add variables');
  FDocument.Pattern.AddVariable('ease', '10');
  FDocument.Pattern.AddVariable('double_ease', '#ease * 2');
  FDocument.EndChange;
end;

procedure TTestPanelEdits.TearDown;
begin
  FreeAndNil(FPending);
  FreeAndNil(FDocument);
  DeleteFile(ConcatPaths([FFolder, 'set.slm']));
  RemoveDir(FFolder);
end;

function TTestPanelEdits.VariableKey(const AName: string): string;
var
  Index: integer;
begin
  for Index := 0 to FDocument.Pattern.VariableCount - 1 do
    if FDocument.Pattern.Variables[Index].Name = AName then
      Exit(FDocument.Pattern.Variables[Index].Key);
  Fail('no variable ' + AName);
  Result := '';
end;

function TTestPanelEdits.WriteSet: string;
var
  MeasurementSet: TMeasurementSet;
  Err: string;
begin
  Result := ConcatPaths([FFolder, 'set.slm']);
  MeasurementSet := TMeasurementSet.Create;
  try
    MeasurementSet.Add('waist', 720, 'Round the waist');
    MeasurementSet.Add('hip', 960);
    if not MeasurementSet.SaveToFile(Result, Err) then
      Fail(Err);
  finally
    FreeAndNil(MeasurementSet);
  end;
end;

function TTestPanelEdits.ReadSet(const FileName: string): TMeasurementSet;
var
  Err: string;
begin
  Result := TMeasurementSet.Create;
  if not Result.LoadFromFile(FileName, Err) then
  begin
    FreeAndNil(Result);
    Fail(Err);
  end;
end;

procedure TTestPanelEdits.TestVariableFormulaIsOneStep;
var
  Reason: string;
  ErrorPos: integer;
  Variable: TVariable;
begin
  AssertTrue(Reason, CommitVariableCell(FDocument, VariableKey('ease'), vcFormula, '15', Reason, ErrorPos));
  Variable := TVariable(FDocument.Pattern.FindNode(VariableKey('double_ease')));
  AssertNear('dependent follows', 30, Variable.Value);
  AssertEquals('Edit variable formula', FDocument.UndoDescription);
  AssertTrue('undo', FDocument.Undo);
  Variable := TVariable(FDocument.Pattern.FindNode(VariableKey('double_ease')));
  AssertNear('back after one undo', 20, Variable.Value);
end;

procedure TTestPanelEdits.TestVariableRename;
var
  Reason: string;
  ErrorPos: integer;
  Key: string;
begin
  Key := VariableKey('ease');
  AssertTrue(Reason, CommitVariableCell(FDocument, Key, vcName, ' allowance ', Reason, ErrorPos));
  AssertEquals('trimmed', 'allowance', TVariable(FDocument.Pattern.FindNode(Key)).Name);
  AssertEquals('formulas follow the name', '#allowance * 2', FDocument.Pattern.FormulaText(FDocument.Pattern.FindNode(VariableKey('double_ease')),
    'formula'));
end;

procedure TTestPanelEdits.TestVariableDescription;
var
  Reason: string;
  ErrorPos: integer;
  Key: string;
begin
  Key := VariableKey('ease');
  AssertTrue(Reason, CommitVariableCell(FDocument, Key, vcDescription, 'Ease at the waist', Reason, ErrorPos));
  AssertEquals('Ease at the waist', TVariable(FDocument.Pattern.FindNode(Key)).Description);
  AssertTrue('undo', FDocument.Undo);
  AssertEquals('undone', '', TVariable(FDocument.Pattern.FindNode(Key)).Description);
end;

procedure TTestPanelEdits.TestRefusedFormulaChangesNothing;
var
  Reason: string;
  ErrorPos: integer;
  Steps: string;
begin
  Steps := FDocument.UndoDescription;
  AssertFalse('refused', CommitVariableCell(FDocument, VariableKey('ease'), vcFormula, '1 +', Reason, ErrorPos));
  AssertTrue('says why', Reason <> '');
  AssertEquals('no undo step', Steps, FDocument.UndoDescription);
  AssertNear('value kept', 10, TVariable(FDocument.Pattern.FindNode(VariableKey('ease'))).Value);
end;

procedure TTestPanelEdits.TestRefusedNameChangesNothing;
var
  Reason: string;
  ErrorPos: integer;
begin
  AssertFalse('taken', CommitVariableCell(FDocument, VariableKey('ease'), vcName, 'DOUBLE_EASE', Reason, ErrorPos));
  AssertTrue('says why', Reason <> '');
  AssertFalse('bad name', CommitVariableCell(FDocument, VariableKey('ease'), vcName, '2nd', Reason, ErrorPos));
  AssertEquals('name kept', 'ease', TVariable(FDocument.Pattern.FindNode(VariableKey('ease'))).Name);
end;

procedure TTestPanelEdits.TestReadOnlyColumnRefused;
var
  Reason: string;
  ErrorPos: integer;
begin
  AssertFalse('value is computed', CommitVariableCell(FDocument, VariableKey('ease'), vcValue, '3', Reason, ErrorPos));
  AssertFalse('unknown key', CommitVariableCell(FDocument, '999', vcFormula, '3', Reason, ErrorPos));
end;

procedure TTestPanelEdits.TestPendingStartsFromSet;
var
  MeasurementSet: TMeasurementSet;
  NewKey, Reason: string;
begin
  MeasurementSet := ReadSet(WriteSet);
  try
    AssertTrue(Reason, FPending.CommitCell(MeasurementSet, 'WAIST', mcValue, '740.5', NewKey, Reason));
    AssertEquals('one edit', 1, FPending.Count);
    AssertEquals('key as the set has it', 'waist', FPending[0].Key);
    AssertNear('value', 740.5, FPending[0].Value);
    AssertEquals('description from the set', 'Round the waist', FPending[0].Description);
    AssertTrue(Reason, FPending.CommitCell(MeasurementSet, 'waist', mcDescription, 'Natural waist', NewKey, Reason));
    AssertEquals('same edit', 1, FPending.Count);
    AssertNear('value kept', 740.5, FPending[0].Value);
    AssertNear('set untouched', 720, MeasurementSet.Find('waist').Value);
  finally
    FreeAndNil(MeasurementSet);
  end;
end;

procedure TTestPanelEdits.TestPendingRefusesBadValue;
var
  MeasurementSet: TMeasurementSet;
  NewKey, Reason: string;
begin
  MeasurementSet := ReadSet(WriteSet);
  try
    AssertFalse('not a number', FPending.CommitCell(MeasurementSet, 'waist', mcValue, '72O', NewKey, Reason));
    AssertEquals(rsPanelBadValue, Reason);
    AssertEquals('nothing held', 0, FPending.Count);
  finally
    FreeAndNil(MeasurementSet);
  end;
end;

procedure TTestPanelEdits.TestPendingValueForMissingKey;
var
  MeasurementSet: TMeasurementSet;
  NewKey, Reason: string;
begin
  MeasurementSet := ReadSet(WriteSet);
  try
    AssertTrue(Reason, FPending.CommitCell(MeasurementSet, 'knee', mcValue, '560', NewKey, Reason));
    AssertEquals('knee', FPending[0].Key);
    AssertTrue('has a value', FPending[0].HasValue);
    AssertFalse('not from Add', FPending[0].IsNew);
  finally
    FreeAndNil(MeasurementSet);
  end;
end;

procedure TTestPanelEdits.TestPendingNewKey;
var
  MeasurementSet: TMeasurementSet;
  Key, Second, NewKey, Reason: string;
begin
  MeasurementSet := ReadSet(WriteSet);
  try
    Key := FPending.AddNew(MeasurementSet);
    AssertEquals('measurement', Key);
    Second := FPending.AddNew(MeasurementSet);
    AssertEquals('measurement2', Second);
    AssertFalse('taken in the set', FPending.CommitCell(MeasurementSet, Key, mcKey, 'Hip', NewKey, Reason));
    AssertFalse('taken by another edit', FPending.CommitCell(MeasurementSet, Key, mcKey, 'measurement2', NewKey, Reason));
    AssertFalse('not a name', FPending.CommitCell(MeasurementSet, Key, mcKey, 'two words', NewKey, Reason));
    AssertTrue(Reason, FPending.CommitCell(MeasurementSet, Key, mcKey, 'knee', NewKey, Reason));
    AssertEquals('new key', 'knee', NewKey);
    AssertEquals('found by it', 0, FPending.IndexOf('KNEE'));
    AssertTrue(Reason, FPending.CommitCell(MeasurementSet, 'knee', mcKey, 'knee', NewKey, Reason));
  finally
    FreeAndNil(MeasurementSet);
  end;
end;

procedure TTestPanelEdits.TestPendingKeyOnlyForNewRows;
var
  MeasurementSet: TMeasurementSet;
  NewKey, Reason: string;
begin
  MeasurementSet := ReadSet(WriteSet);
  try
    AssertFalse('not held', FPending.CommitCell(MeasurementSet, 'waist', mcKey, 'middle', NewKey, Reason));
    AssertTrue(Reason, FPending.CommitCell(MeasurementSet, 'waist', mcValue, '730', NewKey, Reason));
    AssertFalse('held, but in the set', FPending.CommitCell(MeasurementSet, 'waist', mcKey, 'middle', NewKey, Reason));
    AssertEquals(rsPanelKeyFixed, Reason);
  finally
    FreeAndNil(MeasurementSet);
  end;
end;

procedure TTestPanelEdits.TestPendingNeedsValues;
var
  MeasurementSet: TMeasurementSet;
  Key, NewKey, Reason: string;
  Edits: TMeasurementEditArray;
begin
  MeasurementSet := ReadSet(WriteSet);
  try
    AssertTrue(Reason, FPending.CommitCell(MeasurementSet, 'waist', mcValue, '730', NewKey, Reason));
    Key := FPending.AddNew(MeasurementSet);
    AssertFalse('new key has no value', FPending.Edits(Edits, Reason));
    AssertEquals(Format(rsPanelNoValue, [Key]), Reason);
    AssertTrue(Reason, FPending.CommitCell(MeasurementSet, Key, mcValue, '400', NewKey, Reason));
    AssertTrue(Reason, FPending.Edits(Edits, Reason));
    AssertEquals('two edits', 2, Length(Edits));
    AssertEquals('in order made', 'waist', Edits[0].Key);
    AssertNear('value', 400, Edits[1].Value);
  finally
    FreeAndNil(MeasurementSet);
  end;
end;

procedure TTestPanelEdits.TestChangeMeasurementsWritesOnce;
var
  FileName, Err: string;
  Edits: TMeasurementEditArray;
  Changes: TMeasurementChangeArray;
  MeasurementSet: TMeasurementSet;
begin
  FileName := WriteSet;
  Edits := nil;
  SetLength(Edits, 2);
  Edits[0].Key := 'waist';
  Edits[0].Value := 730;
  Edits[0].Description := 'Round the waist';
  Edits[1].Key := 'knee';
  Edits[1].Value := 560;
  AssertTrue(Err, ChangeMeasurementsInFile(FileName, Edits, Changes, Err));
  AssertEquals('a change for each', 2, Length(Changes));
  AssertNear('old value', 720, Changes[0].OldValue);
  AssertTrue('added', Changes[1].Added);
  MeasurementSet := ReadSet(FileName);
  try
    AssertNear('changed', 730, MeasurementSet.Find('waist').Value);
    AssertNear('added', 560, MeasurementSet.Find('knee').Value);
    AssertNear('kept', 960, MeasurementSet.Find('hip').Value);
  finally
    FreeAndNil(MeasurementSet);
  end;
end;

procedure TTestPanelEdits.TestChangeMeasurementsAllOrNothing;
var
  FileName, Before, After, Err: string;
  Edits: TMeasurementEditArray;
  Changes: TMeasurementChangeArray;
begin
  FileName := WriteSet;
  AssertTrue(Err, ReadTextFile(FileName, Before, Err));
  Edits := nil;
  SetLength(Edits, 2);
  Edits[0].Key := 'waist';
  Edits[0].Value := 730;
  Edits[1].Key := '2nd';
  Edits[1].Value := 1;
  AssertFalse('bad key', ChangeMeasurementsInFile(FileName, Edits, Changes, Err));
  AssertTrue('says why', Err <> '');
  AssertEquals('no changes', 0, Length(Changes));
  AssertTrue(Err, ReadTextFile(FileName, After, Err));
  AssertEquals('file untouched', Before, After);
end;

procedure TTestPanelEdits.TestDocumentChangeMeasurements;
var
  Err: string;
  Edits: TMeasurementEditArray;
  Changes: TMeasurementChangeArray;
begin
  AssertFalse('no set open', FDocument.ChangeMeasurements(nil, Changes, Err));
  AssertTrue(Err, FDocument.UseMeasurements(WriteSet, Err));
  FDocument.BeginChange('Add point');
  FDocument.Commit(Assigned(FDocument.Pattern.AddFreePoint('A', '@waist / 4', '@hip / 4')));
  Edits := nil;
  SetLength(Edits, 2);
  Edits[0].Key := 'waist';
  Edits[0].Value := 800;
  Edits[1].Key := 'hip';
  Edits[1].Value := 1000;
  AssertTrue(Err, FDocument.ChangeMeasurements(Edits, Changes, Err));
  AssertNear('set reloaded', 800, FDocument.Measurements.Find('waist').Value);
  AssertNear('pattern follows', 200, TPointObject(FDocument.Pattern.FindObject('A')).Position.X);
  AssertEquals('not an undo step', 'Add point', FDocument.UndoDescription);
end;

procedure TTestPanelEdits.TestMeasurementFileChanged;
var
  FileName, Err: string;
  Change: TMeasurementChange;
begin
  AssertFalse('no set', FDocument.MeasurementFileChanged);
  FileName := WriteSet;
  AssertTrue(Err, FDocument.UseMeasurements(FileName, Err));
  AssertFalse('as read', FDocument.MeasurementFileChanged);
  AssertTrue(Err, ChangeMeasurementInFile(FileName, 'hip', 970, '', Change, Err));
  AssertTrue('changed elsewhere', FDocument.MeasurementFileChanged);
  AssertTrue(Err, FDocument.ChangeMeasurement('waist', 700, '', Change, Err));
  AssertFalse('read again by its own write', FDocument.MeasurementFileChanged);
end;

procedure TTestPanelEdits.TestParseValue;
var
  Value: double;
begin
  AssertTrue(ParseMeasurementValue(' 41.5 ', Value));
  AssertNear('point decimals', 41.5, Value);
  AssertFalse('comma', ParseMeasurementValue('41,5', Value));
  AssertFalse('empty', ParseMeasurementValue('', Value));
  AssertFalse('too large', ParseMeasurementValue('1e13', Value));
end;

procedure TTestPanelEdits.TestMaterialFieldsAreSteps;
var
  Reason: string;
begin
  AssertTrue(Reason, CommitMaterialField(FDocument, 0, mfName, 'Shell', Reason));
  AssertEquals('Rename material', FDocument.UndoDescription);
  AssertTrue(Reason, CommitMaterialField(FDocument, 0, mfColor, '#112233', Reason));
  AssertTrue(Reason, CommitMaterialField(FDocument, 0, mfFill, 'hatch', Reason));
  AssertTrue(Reason, CommitMaterialField(FDocument, 0, mfAllowance, ' 6.5 ', Reason));
  AssertEquals('Shell', MaterialFieldText(FDocument, 0, mfName));
  AssertEquals('#112233', MaterialFieldText(FDocument, 0, mfColor));
  AssertEquals('hatch', MaterialFieldText(FDocument, 0, mfFill));
  AssertEquals('6.5', MaterialFieldText(FDocument, 0, mfAllowance));
  AssertTrue(Reason, CommitMaterialField(FDocument, 0, mfAllowance, '', Reason));
  AssertEquals('none', '', MaterialFieldText(FDocument, 0, mfAllowance));
  AssertTrue('undo', FDocument.Undo);
  AssertEquals('one step back', '6.5', MaterialFieldText(FDocument, 0, mfAllowance));
  AssertTrue('undo', FDocument.Undo);
  AssertEquals('another', '', MaterialFieldText(FDocument, 0, mfAllowance));
  AssertEquals('fill still set', 'hatch', MaterialFieldText(FDocument, 0, mfFill));
end;

procedure TTestPanelEdits.TestMaterialSizeFields;
var
  Reason: string;
begin
  AssertFalse('a length needs a width', CommitMaterialField(FDocument, 0, mfLength, '700', Reason));
  AssertEquals(rsMaterialLengthWithoutWidth, Reason);
  AssertFalse(CommitMaterialField(FDocument, 0, mfWidth, 'wide', Reason));
  AssertEquals(rsPanelBadSize, Reason);
  AssertTrue(Reason, CommitMaterialField(FDocument, 0, mfWidth, '1500', Reason));
  AssertEquals('Change material size', FDocument.UndoDescription);
  AssertTrue(Reason, CommitMaterialField(FDocument, 0, mfLength, '700', Reason));
  AssertEquals('1500', MaterialFieldText(FDocument, 0, mfWidth));
  AssertEquals('700', MaterialFieldText(FDocument, 0, mfLength));
  AssertTrue(Reason, CommitMaterialField(FDocument, 0, mfAllowTurns, 'true', Reason));
  AssertEquals('true', MaterialFieldText(FDocument, 0, mfAllowTurns));
  AssertTrue(Reason, CommitMaterialField(FDocument, 0, mfWidth, '', Reason));
  AssertEquals('no width', '', MaterialFieldText(FDocument, 0, mfWidth));
  AssertEquals('no width clears the length', '', MaterialFieldText(FDocument, 0, mfLength));
  AssertTrue('undo', FDocument.Undo);
  AssertEquals('one step back', '700', MaterialFieldText(FDocument, 0, mfLength));
end;

procedure TTestPanelEdits.TestMaterialUnchangedMakesNoStep;
var
  Reason, Steps: string;
begin
  Steps := FDocument.UndoDescription;
  AssertTrue(Reason, CommitMaterialField(FDocument, 0, mfName, MaterialFieldText(FDocument, 0, mfName), Reason));
  AssertTrue(Reason, CommitMaterialField(FDocument, 0, mfFill, 'tint', Reason));
  AssertEquals('no step', Steps, FDocument.UndoDescription);
end;

procedure TTestPanelEdits.TestMaterialRefusals;
var
  Reason, Steps: string;
begin
  Steps := FDocument.UndoDescription;
  AssertFalse('allowance', CommitMaterialField(FDocument, 0, mfAllowance, '6,5', Reason));
  AssertEquals(rsPanelBadAllowance, Reason);
  AssertFalse('colour', CommitMaterialField(FDocument, 0, mfColor, 'blue', Reason));
  AssertEquals(rsPanelBadColor, Reason);
  AssertFalse('fill', CommitMaterialField(FDocument, 0, mfFill, 'stripes', Reason));
  AssertFalse('name', CommitMaterialField(FDocument, 0, mfName, '2nd', Reason));
  AssertTrue('says why', Reason <> '');
  AssertFalse('no such material', CommitMaterialField(FDocument, 5, mfName, 'Other', Reason));
  AssertEquals(rsPanelNoMaterial, Reason);
  AssertEquals('no step', Steps, FDocument.UndoDescription);
end;

procedure TTestPanelEdits.TestMaterialAddAndDelete;
var
  Index: integer;
  Reason: string;
begin
  Index := AddMaterialStep(FDocument);
  AssertEquals('added last', FDocument.Pattern.MaterialCount - 1, Index);
  AssertEquals('Add material', FDocument.UndoDescription);
  AssertTrue(Reason, DeleteMaterialStep(FDocument, Index, Reason));
  AssertEquals('one left', 1, FDocument.Pattern.MaterialCount);
  AssertFalse('the last cannot go', DeleteMaterialStep(FDocument, 0, Reason));
  AssertTrue('says why', Reason <> '');
end;

initialization
  RegisterTest(TTestPanelEdits);
end.
