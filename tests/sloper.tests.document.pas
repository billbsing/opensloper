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

// The pattern document: changes and undo/redo, merging, the modified flag,
// notifications, and files with their measurement sets.
unit Sloper.Tests.Document;

{$mode ObjFPC}{$H+}

interface

uses
  fpcunit, testregistry, Sloper.Tests.TestCase, Sloper.Core.Measurements, Sloper.Document.PatternDocument;

type
  TTestDocument = class(TOSTestCase)
  private
    FDocument: TPatternDocument;
    FTime: TDateTime;
    FChanges: array of TDocumentChanges;
    FFolder: string;
    function Clock: TDateTime;
    procedure Listen(Document: TPatternDocument; Changes: TDocumentChanges);
    procedure Wait(Seconds: double);
    function Text: string;
    function PointX(const AName: string): double;
    procedure AddPoint(const AName, X: string);
    procedure Nudge(const AName: string; Dx: double);
    function WriteSet(const AName: string; Waist: double): string;
    function WriteTable: string;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestChangeIsOneStep;
    procedure TestUndoRedoRestoresExactly;
    procedure TestRedoKeepsIds;
    procedure TestUndoneIdNotReused;
    procedure TestRefusedEditAddsNothing;
    procedure TestCancelRestores;
    procedure TestDragIsOneStep;
    procedure TestNudgesMerge;
    procedure TestMergeNeedsSameKeyAndTime;
    procedure TestMergeBackToStartDropsStep;
    procedure TestNoMergeIntoSavedStep;
    procedure TestNewChangeClearsRedo;
    procedure TestUndoRefusedDuringChange;
    procedure TestChangesDoNotNest;
    procedure TestUndoLimit;
    procedure TestModifiedFlag;
    procedure TestSavedStateLostOnNewBranch;
    procedure TestNotifications;
    procedure TestRemoveListener;
    procedure TestSaveAndLoadWithMeasurements;
    procedure TestMeasurementsInOtherFolder;
    procedure TestMissingMeasurementFileStillOpens;
    procedure TestFailedLoadKeepsPattern;
    procedure TestMeasurementsSurviveUndo;
    procedure TestChangeMeasurementReevaluates;
    procedure TestSelectSizeReevaluates;
    procedure TestChangeMeasurementKeepsSize;
    procedure TestSeesMeasurementFileChange;
    procedure TestMeasurementWatchWaitsForAStableFile;
    procedure TestMeasurementWatchKeepsSize;
    procedure TestMeasurementWatchIgnoresBrokenFile;
    procedure TestMeasurementWatchIgnoresOwnChange;
    procedure TestChangeMeasurementIsNotAnUndoStep;
    procedure TestChangeMeasurementFixesMissingKey;
    procedure TestChangeMeasurementNeedsAFile;
    procedure TestNewPattern;
    procedure TestMeasurementScaleScalesValues;
    procedure TestMeasurementScaleIsNotAChange;
    procedure TestMeasurementScaleIsNotSaved;
    procedure TestMeasurementScaleSurvivesUndo;
    procedure TestMeasurementScaleNotifies;
    procedure TestMeasurementScaleRefusesNonPositive;
    procedure TestNewPatternResetsMeasurementScale;
    procedure TestOpeningResetsMeasurementScale;
  end;

implementation

uses
  Sloper.Core.JSON,
  SysUtils, Sloper.Core.EvalTypes, Sloper.Core.Draft, Sloper.Core.Pattern, Sloper.Core.PatternFile, Sloper.Core.Units;

procedure TTestDocument.SetUp;
begin
  FTime := EncodeDate(2026, 10, 29);
  FChanges := nil;
  FDocument := TPatternDocument.Create;
  FDocument.Clock := @Clock;
  FFolder := ConcatPaths([GetTempDir, 'opensloper-document-test']);
  ForceDirectories(ConcatPaths([FFolder, 'sets']));
end;

procedure TTestDocument.TearDown;
begin
  FreeAndNil(FDocument);
  DeleteFile(ConcatPaths([FFolder, 'sets', 'bill.slm']));
  DeleteFile(ConcatPaths([FFolder, 'sets', 'other.slm']));
  DeleteFile(ConcatPaths([FFolder, 'skirt.sloper']));
  DeleteFile(ConcatPaths([FFolder, 'sets', 'skirt.sloper']));
  RemoveDir(ConcatPaths([FFolder, 'sets']));
  RemoveDir(FFolder);
end;

function TTestDocument.Clock: TDateTime;
begin
  Result := FTime;
end;

procedure TTestDocument.Wait(Seconds: double);
begin
  FTime := FTime + Seconds / SecsPerDay;
end;

procedure TTestDocument.Listen(Document: TPatternDocument; Changes: TDocumentChanges);
begin
  SetLength(FChanges, Length(FChanges) + 1);
  FChanges[High(FChanges)] := Changes;
end;

// The definitions, without the ID counter, which undo leaves where it is
function TTestDocument.Text: string;
begin
  Result := SavePatternToText(FDocument.Pattern, False);
end;

function TTestDocument.PointX(const AName: string): double;
begin
  Result := TPointObject(FDocument.Pattern.FindObject(AName)).Position.X;
end;

procedure TTestDocument.AddPoint(const AName, X: string);
begin
  FDocument.BeginChange('Add point');
  if not FDocument.Commit(Assigned(FDocument.Pattern.AddFreePoint(AName, X, '0'))) then
    Fail('Refused: ' + FDocument.Pattern.LastError);
end;

// An arrow-key nudge: x becomes a new literal, merged per point
procedure TTestDocument.Nudge(const AName: string; Dx: double);
var
  Point: TDraftObject;
begin
  Point := FDocument.Pattern.FindObject(AName);
  FDocument.BeginChange('Move point');
  FDocument.Commit(FDocument.Pattern.SetFormula(Point, 'x', FloatToStr(PointX(AName) + Dx)), 'nudge:' + Point.Key);
end;

function TTestDocument.WriteSet(const AName: string; Waist: double): string;
var
  MeasurementSet: TMeasurementSet;
  Err: string;
begin
  Result := ConcatPaths([FFolder, 'sets', AName]);
  MeasurementSet := TMeasurementSet.Create;
  try
    MeasurementSet.Add('waist', Waist);
    if not MeasurementSet.SaveToFile(Result, Err) then
      Fail(Err);
  finally
    FreeAndNil(MeasurementSet);
  end;
end;

procedure TTestDocument.TestChangeIsOneStep;
begin
  AssertFalse('nothing to undo', FDocument.CanUndo);
  AddPoint('A', '10');
  AssertTrue('can undo', FDocument.CanUndo);
  AssertEquals('Add point', FDocument.UndoDescription);
  AssertTrue('undo', FDocument.Undo);
  AssertNull('point gone', FDocument.Pattern.FindObject('A'));
  AssertTrue('can redo', FDocument.CanRedo);
  AssertEquals('Add point', FDocument.RedoDescription);
  AssertTrue('redo', FDocument.Redo);
  AssertNotNull('point back', FDocument.Pattern.FindObject('A'));
  AssertNear('evaluated', 10, PointX('A'));
end;

procedure TTestDocument.TestUndoRedoRestoresExactly;
var
  Before, After: string;
begin
  AddPoint('A', '10');
  AddPoint('B', '20');
  Before := Text;
  FDocument.BeginChange('Edit');
  FDocument.Pattern.Rename(FDocument.Pattern.FindObject('A'), 'Start');
  FDocument.Pattern.AddLine(FDocument.Pattern.FindObject('Start').Key, FDocument.Pattern.FindObject('B').Key);
  FDocument.EndChange;
  After := Text;
  FDocument.Undo;
  AssertEquals('undo', Before, Text);
  FDocument.Redo;
  AssertEquals('redo', After, Text);
end;

procedure TTestDocument.TestRedoKeepsIds;
begin
  AddPoint('A', '10');
  AddPoint('B', '20');
  FDocument.Undo;
  FDocument.Redo;
  AssertEquals('2', FDocument.Pattern.FindObject('B').Key);
  AddPoint('C', '30');
  AssertEquals('3', FDocument.Pattern.FindObject('C').Key);
end;

// Undo restores the text but not the counter, so B's ID stays retired
procedure TTestDocument.TestUndoneIdNotReused;
begin
  AddPoint('A', '10');
  AddPoint('B', '20');
  FDocument.Undo;
  AddPoint('C', '30');
  AssertEquals('3', FDocument.Pattern.FindObject('C').Key);
end;

procedure TTestDocument.TestRefusedEditAddsNothing;
begin
  AddPoint('A', '10');
  FDocument.BeginChange('Add point');
  AssertFalse('refused', FDocument.Commit(Assigned(FDocument.Pattern.AddFreePoint('A', '1', '0'))));
  AssertFalse('change closed', FDocument.ChangeOpen);
  FDocument.Undo;
  AssertFalse('only one step', FDocument.CanUndo);
  // A change that ends with nothing different is no step either
  FDocument.BeginChange('Nothing');
  AssertFalse(FDocument.EndChange);
  AssertFalse(FDocument.CanUndo);
end;

procedure TTestDocument.TestCancelRestores;
var
  Before: string;
begin
  AddPoint('A', '10');
  Before := Text;
  FDocument.BeginChange('Add point');
  FDocument.Pattern.AddFreePoint('B', '1', '0');
  FDocument.Pattern.Rename(FDocument.Pattern.FindObject('A'), 'Z');
  FDocument.CancelChange;
  AssertEquals(Before, Text);
  FDocument.Undo;
  AssertFalse('cancel added no step', FDocument.CanUndo);
end;

// The model follows the mouse during the drag; mouse-up records one step
procedure TTestDocument.TestDragIsOneStep;
var
  Step: integer;
  Point: TDraftObject;
begin
  AddPoint('A', '10');
  FDocument.BeginChange('Move point');
  Point := FDocument.Pattern.FindObject('A');
  for Step := 1 to 5 do
  begin
    FDocument.Pattern.SetFormula(Point, 'x', IntToStr(10 + Step * 10));
    FDocument.LiveUpdate;
    AssertNear('live', 10 + Step * 10, PointX('A'));
  end;
  AssertTrue(FDocument.EndChange);
  AssertNear('dropped', 60, PointX('A'));
  FDocument.Undo;
  AssertNear('one step back', 10, PointX('A'));
  FDocument.Undo;
  AssertNull('then the add', FDocument.Pattern.FindObject('A'));
end;

procedure TTestDocument.TestNudgesMerge;
begin
  AddPoint('A', '10');
  Nudge('A', 1);
  Wait(0.5);
  Nudge('A', 1);
  Wait(0.5);
  Nudge('A', 1);
  AssertNear('three nudges', 13, PointX('A'));
  FDocument.Undo;
  AssertNear('three nudges, one step', 10, PointX('A'));
  // The window runs from the last nudge
  FDocument.Redo;
  Wait(2);
  Nudge('A', 1);
  FDocument.Undo;
  AssertNear('a pause starts a new step', 13, PointX('A'));
end;

procedure TTestDocument.TestMergeNeedsSameKeyAndTime;
begin
  AddPoint('A', '10');
  AddPoint('B', '20');
  Nudge('A', 1);
  Nudge('B', 1);
  FDocument.Undo;
  AssertNear('B undone', 20, PointX('B'));
  AssertNear('A not', 11, PointX('A'));
  Nudge('B', 1);
  Wait(1.5);
  Nudge('B', 1);
  FDocument.Undo;
  AssertNear('only the late nudge', 21, PointX('B'));
end;

procedure TTestDocument.TestMergeBackToStartDropsStep;
begin
  AddPoint('A', '10');
  Nudge('A', 1);
  Nudge('A', -1);
  AssertNear('back where it was', 10, PointX('A'));
  FDocument.Undo;
  AssertNull('the step went; this undid the add', FDocument.Pattern.FindObject('A'));
end;

procedure TTestDocument.TestNoMergeIntoSavedStep;
var
  Err: string;
begin
  AddPoint('A', '10');
  Nudge('A', 1);
  AssertTrue(Err, FDocument.SaveToFile(ConcatPaths([FFolder, 'skirt.sloper']), Err));
  Nudge('A', 1);
  AssertTrue('modified', FDocument.Modified);
  FDocument.Undo;
  AssertNear('back to the saved state', 11, PointX('A'));
  AssertFalse('which is not modified', FDocument.Modified);
end;

procedure TTestDocument.TestNewChangeClearsRedo;
begin
  AddPoint('A', '10');
  AddPoint('B', '20');
  FDocument.Undo;
  AddPoint('C', '30');
  AssertFalse(FDocument.CanRedo);
end;

procedure TTestDocument.TestUndoRefusedDuringChange;
begin
  AddPoint('A', '10');
  FDocument.BeginChange('Move point');
  AssertFalse('can undo', FDocument.CanUndo);
  AssertFalse('undo', FDocument.Undo);
  FDocument.CancelChange;
  AssertTrue(FDocument.Undo);
end;

procedure TTestDocument.TestChangesDoNotNest;
var
  Raised: boolean;
begin
  FDocument.BeginChange('First');
  Raised := False;
  try
    FDocument.BeginChange('Second');
  except
    on EDocumentError do
      Raised := True;
  end;
  AssertTrue('nested change refused', Raised);
  FDocument.CancelChange;
  Raised := False;
  try
    FDocument.EndChange;
  except
    on EDocumentError do
      Raised := True;
  end;
  AssertTrue('no change to end', Raised);
end;

procedure TTestDocument.TestUndoLimit;
var
  Index, Steps: integer;
begin
  FDocument.UndoLimit := 3;
  for Index := 1 to 5 do
    AddPoint('P' + IntToStr(Index), IntToStr(Index));
  Steps := 0;
  while FDocument.Undo do
    Inc(Steps);
  AssertEquals(3, Steps);
  AssertNotNull('older steps kept their effect', FDocument.Pattern.FindObject('P2'));
  AssertTrue('the saved state was dropped', FDocument.Modified);
end;

procedure TTestDocument.TestModifiedFlag;
var
  Err: string;
begin
  AssertFalse('new', FDocument.Modified);
  AddPoint('A', '10');
  AssertTrue('changed', FDocument.Modified);
  AssertTrue(Err, FDocument.SaveToFile(ConcatPaths([FFolder, 'skirt.sloper']), Err));
  AssertFalse('saved', FDocument.Modified);
  AddPoint('B', '20');
  AssertTrue('changed again', FDocument.Modified);
  FDocument.Undo;
  AssertFalse('back to the saved state', FDocument.Modified);
  FDocument.Undo;
  AssertTrue('before the saved state', FDocument.Modified);
  FDocument.Redo;
  AssertFalse('saved state again', FDocument.Modified);
end;

procedure TTestDocument.TestSavedStateLostOnNewBranch;
var
  Err: string;
begin
  AddPoint('A', '10');
  AddPoint('B', '20');
  AssertTrue(Err, FDocument.SaveToFile(ConcatPaths([FFolder, 'skirt.sloper']), Err));
  FDocument.Undo;
  AddPoint('C', '30');
  FDocument.Undo;
  AssertTrue('the saved state cannot come back', FDocument.Modified);
end;

procedure TTestDocument.TestNotifications;
var
  Err: string;
begin
  FDocument.AddListener(@Listen);
  AddPoint('A', '10');
  AssertEquals('one notification', 1, Length(FChanges));
  AssertTrue('commit', FChanges[0] = [dcPattern, dcHistory, dcFile]);
  AddPoint('B', '20');
  AssertTrue('already modified', FChanges[1] = [dcPattern, dcHistory]);
  FDocument.Undo;
  AssertTrue('undo replaces objects', FChanges[2] = [dcPattern, dcObjectsReplaced, dcHistory]);
  FDocument.BeginChange('Move point');
  FDocument.LiveUpdate;
  AssertTrue('live', FChanges[3] = [dcPattern]);
  FDocument.CancelChange;
  AssertEquals('nothing to cancel, no notification', 4, Length(FChanges));
  AssertTrue(Err, FDocument.SaveToFile(ConcatPaths([FFolder, 'skirt.sloper']), Err));
  AssertTrue('save', FChanges[4] = [dcFile]);
end;

procedure TTestDocument.TestRemoveListener;
begin
  FDocument.AddListener(@Listen);
  FDocument.RemoveListener(@Listen);
  AddPoint('A', '10');
  AssertEquals(0, Length(FChanges));
end;

procedure TTestDocument.TestSaveAndLoadWithMeasurements;
var
  Other: TPatternDocument;
  FileName, Err: string;
begin
  FileName := ConcatPaths([FFolder, 'skirt.sloper']);
  AssertTrue(Err, FDocument.UseMeasurements(WriteSet('bill.slm', 720), Err));
  FDocument.BeginChange('Add point');
  FDocument.Commit(Assigned(FDocument.Pattern.AddFreePoint('A', '@waist / 4', '0')));
  AssertNear('evaluated with the set', 180, PointX('A'));
  AssertTrue(Err, FDocument.SaveToFile(FileName, Err));
  AssertEquals('stored relative, with /', 'sets/bill.slm', FDocument.Pattern.MeasurementFile);

  Other := TPatternDocument.Create;
  try
    AssertTrue(Err, Other.LoadFromFile(FileName, Err));
    AssertEquals('file name', ExpandFileName(FileName), Other.FileName);
    AssertEquals('no error', '', Other.MeasurementError);
    AssertNotNull('set loaded', Other.Measurements);
    AssertEquals('set path', ConcatPaths([FFolder, 'sets', 'bill.slm']), Other.MeasurementPath);
    AssertNear('evaluated', 180, TPointObject(Other.Pattern.FindObject('A')).Position.X);
    AssertFalse('not modified', Other.Modified);
    AssertFalse('no history', Other.CanUndo);
  finally
    FreeAndNil(Other);
  end;
end;

procedure TTestDocument.TestMeasurementsInOtherFolder;
var
  Err: string;
begin
  AssertTrue(Err, FDocument.UseMeasurements(WriteSet('bill.slm', 720), Err));
  AssertEquals('absolute while unsaved', ConcatPaths([FFolder, 'sets', 'bill.slm']), FDocument.Pattern.MeasurementFile);
  AssertTrue(Err, FDocument.SaveToFile(ConcatPaths([FFolder, 'sets', 'skirt.sloper']), Err));
  AssertEquals('beside it', 'bill.slm', FDocument.Pattern.MeasurementFile);
  AssertTrue(Err, FDocument.SaveToFile(ConcatPaths([FFolder, 'skirt.sloper']), Err));
  AssertEquals('below it', 'sets/bill.slm', FDocument.Pattern.MeasurementFile);
end;

procedure TTestDocument.TestMissingMeasurementFileStillOpens;
var
  Other: TPatternDocument;
  FileName, SetName, Err: string;
begin
  FileName := ConcatPaths([FFolder, 'skirt.sloper']);
  SetName := WriteSet('bill.slm', 720);
  AssertTrue(Err, FDocument.UseMeasurements(SetName, Err));
  FDocument.BeginChange('Add point');
  FDocument.Commit(Assigned(FDocument.Pattern.AddFreePoint('A', '@waist / 4', '0')));
  AssertTrue(Err, FDocument.SaveToFile(FileName, Err));
  DeleteFile(SetName);

  Other := TPatternDocument.Create;
  try
    AssertTrue(Err, Other.LoadFromFile(FileName, Err));
    AssertTrue('error given', Pos('bill.slm', Other.MeasurementError) > 0);
    AssertNull('no set', Other.Measurements);
    AssertTrue('point blocked', Other.Pattern.FindObject('A').State = esBlocked);
    AssertEquals('still named', 'sets/bill.slm', Other.Pattern.MeasurementFile);
  finally
    FreeAndNil(Other);
  end;
end;

procedure TTestDocument.TestFailedLoadKeepsPattern;
var
  Err: string;
begin
  AddPoint('A', '10');
  AssertFalse(FDocument.LoadFromFile(ConcatPaths([FFolder, 'missing.sloper']), Err));
  AssertNotNull('pattern kept', FDocument.Pattern.FindObject('A'));
  AssertTrue('history kept', FDocument.CanUndo);
  AssertFalse('bad set refused', FDocument.UseMeasurements(ConcatPaths([FFolder, 'missing.slm']), Err));
  AssertNull('no set before, none now', FDocument.Measurements);
end;

// The measurement set is the document's choice; undo does not bring back an old one
function TTestDocument.WriteTable: string;
var
  Table: TMeasurementSet;
  Err: string;
begin
  Result := ConcatPaths([FFolder, 'sets', 'bill.slm']);
  ForceDirectories(ExtractFileDir(Result));
  Table := TMeasurementSet.Create;
  try
    AssertTrue(Err, Table.LoadFromText('{"format": "measurements", "version": 1, "sizes": ["36", "38"], ' +
      '"measurements": [{"key": "waist", "values": [400, 800]}]}', Err));
    AssertTrue(Err, Table.SaveToFile(Result, Err));
  finally
    FreeAndNil(Table);
  end;
end;

procedure TTestDocument.TestSelectSizeReevaluates;
var
  Err: string;
begin
  AssertTrue(Err, FDocument.UseMeasurements(WriteTable, Err));
  FDocument.BeginChange('Add point');
  FDocument.Commit(Assigned(FDocument.Pattern.AddFreePoint('A', '@waist / 4', '0')));
  AssertNear('first size', 100, PointX('A'));
  FChanges := nil;
  FDocument.AddListener(@Listen);
  AssertTrue(FDocument.SelectMeasurementSize('38'));
  AssertNear('second size', 200, PointX('A'));
  AssertEquals('one notification', 1, Length(FChanges));
  AssertFalse('unknown size', FDocument.SelectMeasurementSize('42'));
  AssertEquals('38', FDocument.Measurements.SizeName);
  AssertFalse('not a pattern edit', FDocument.CanUndo and (FDocument.UndoDescription <> 'Add point'));
end;

procedure TTestDocument.TestChangeMeasurementKeepsSize;
var
  Err: string;
  Change: TMeasurementChange;
begin
  AssertTrue(Err, FDocument.UseMeasurements(WriteTable, Err));
  AssertTrue(FDocument.SelectMeasurementSize('38'));
  AssertTrue(Err, FDocument.ChangeMeasurement('waist', 820, '', Change, Err));
  AssertEquals('38', FDocument.Measurements.SizeName);
  AssertNear('that size', 820, FDocument.Measurements.Find('waist').Value);
  AssertNear('not the other', 400, FDocument.Measurements.Find('waist').ValueFor(0));
end;

procedure TTestDocument.TestSeesMeasurementFileChange;
var
  Err: string;
begin
  AssertTrue(Err, FDocument.UseMeasurements(WriteSet('bill.slm', 720), Err));
  FDocument.BeginChange('Add point');
  FDocument.Commit(Assigned(FDocument.Pattern.AddFreePoint('A', '@waist / 4', '0')));
  AssertFalse('no change', FDocument.CheckMeasurementFile);
  WriteSet('bill.slm', 800);
  AssertFalse('the first sight waits', FDocument.CheckMeasurementFile);
  AssertTrue(FDocument.CheckMeasurementFile);
  AssertNear('pattern follows', 200, PointX('A'));
  AssertFalse('once only', FDocument.CheckMeasurementFile);
end;

procedure TTestDocument.TestMeasurementWatchWaitsForAStableFile;
var
  Err: string;
begin
  AssertTrue(Err, FDocument.UseMeasurements(WriteSet('bill.slm', 720), Err));
  WriteSet('bill.slm', 800);
  AssertFalse(FDocument.CheckMeasurementFile);
  WriteSet('bill.slm', 810);
  AssertFalse('still changing', FDocument.CheckMeasurementFile);
  AssertTrue(FDocument.CheckMeasurementFile);
  AssertNear('the last value', 810, FDocument.Measurements.Find('waist').Value);
end;

procedure TTestDocument.TestMeasurementWatchKeepsSize;
var
  Err: string;
  Path: string;
  Change: TMeasurementChange;
begin
  Path := WriteTable;
  AssertTrue(Err, FDocument.UseMeasurements(Path, Err));
  AssertTrue(FDocument.SelectMeasurementSize('38'));
  AssertTrue(Err, ChangeMeasurementInFile(Path, 'waist', 830, '', Change, Err, '38'));
  AssertFalse(FDocument.CheckMeasurementFile);
  AssertTrue(FDocument.CheckMeasurementFile);
  AssertEquals('38', FDocument.Measurements.SizeName);
  AssertNear('value', 830, FDocument.Measurements.Find('waist').Value);
end;

procedure TTestDocument.TestMeasurementWatchIgnoresBrokenFile;
var
  Err, Path: string;
begin
  Path := WriteSet('bill.slm', 720);
  AssertTrue(Err, FDocument.UseMeasurements(Path, Err));
  AssertTrue(Err, WriteTextFile(Path, 'half a fi', Err));
  AssertFalse(FDocument.CheckMeasurementFile);
  AssertFalse(FDocument.CheckMeasurementFile);
  AssertNear('stays', 720, FDocument.Measurements.Find('waist').Value);
end;

procedure TTestDocument.TestMeasurementWatchIgnoresOwnChange;
var
  Err: string;
  Change: TMeasurementChange;
begin
  AssertTrue(Err, FDocument.UseMeasurements(WriteSet('bill.slm', 720), Err));
  AssertTrue(Err, FDocument.ChangeMeasurement('waist', 800, '', Change, Err));
  AssertFalse(FDocument.CheckMeasurementFile);
  AssertFalse(FDocument.CheckMeasurementFile);
end;

procedure TTestDocument.TestChangeMeasurementReevaluates;
var
  Err: string;
  Change: TMeasurementChange;
begin
  AssertTrue(Err, FDocument.UseMeasurements(WriteSet('bill.slm', 720), Err));
  FDocument.BeginChange('Add point');
  FDocument.Commit(Assigned(FDocument.Pattern.AddFreePoint('A', '@waist / 4', '0')));
  FChanges := nil;
  FDocument.AddListener(@Listen);
  AssertTrue(Err, FDocument.ChangeMeasurement('waist', 800, 'Waist', Change, Err));
  AssertNear('old value', 720, Change.OldValue);
  AssertNear('pattern follows', 200, PointX('A'));
  AssertNotNull('set reloaded', FDocument.Measurements.Find('waist'));
  AssertNear('set value', 800, FDocument.Measurements.Find('waist').Value);
  AssertEquals('one notification', 1, Length(FChanges));
  AssertTrue('listeners told', dcMeasurements in FChanges[0]);
end;

procedure TTestDocument.TestChangeMeasurementIsNotAnUndoStep;
var
  Err: string;
  Change: TMeasurementChange;
begin
  AssertTrue(Err, FDocument.UseMeasurements(WriteSet('bill.slm', 720), Err));
  FDocument.BeginChange('Add point');
  FDocument.Commit(Assigned(FDocument.Pattern.AddFreePoint('A', '@waist / 4', '0')));
  AssertTrue(Err, FDocument.SaveToFile(ConcatPaths([FFolder, 'test.sloper']), Err));
  AssertFalse('saved', FDocument.Modified);
  AssertTrue(Err, FDocument.ChangeMeasurement('waist', 800, '', Change, Err));
  AssertFalse('the pattern did not change', FDocument.Modified);
  FDocument.Undo;
  AssertNull('undo goes past it', FDocument.Pattern.FindObject('A'));
  AssertNear('the file keeps the edit', 800, FDocument.Measurements.Find('waist').Value);
end;

procedure TTestDocument.TestChangeMeasurementFixesMissingKey;
var
  Err: string;
  Change: TMeasurementChange;
begin
  AssertTrue(Err, FDocument.UseMeasurements(WriteSet('bill.slm', 720), Err));
  FDocument.BeginChange('Add point');
  FDocument.Commit(Assigned(FDocument.Pattern.AddFreePoint('A', '@waist / 4', '0')));
  AssertTrue(Err, FDocument.UseMeasurements(WriteSet('other.slm', 800), Err));
  AssertTrue(Err, FDocument.ChangeMeasurement('chest', 960, '', Change, Err));
  AssertTrue('added', Change.Added);
  AssertNotNull(FDocument.Measurements.Find('chest'));
end;

procedure TTestDocument.TestChangeMeasurementNeedsAFile;
var
  Err: string;
  Change: TMeasurementChange;
begin
  AssertFalse(FDocument.ChangeMeasurement('waist', 800, '', Change, Err));
  AssertEquals(rsDocumentNoMeasurements, Err);
end;

procedure TTestDocument.TestMeasurementsSurviveUndo;
var
  Err: string;
begin
  AssertTrue(Err, FDocument.UseMeasurements(WriteSet('bill.slm', 720), Err));
  FDocument.BeginChange('Add point');
  FDocument.Commit(Assigned(FDocument.Pattern.AddFreePoint('A', '@waist / 4', '0')));
  AssertTrue(Err, FDocument.UseMeasurements(WriteSet('other.slm', 800), Err));
  AssertTrue('modified', FDocument.Modified);
  AssertNear('new set', 200, PointX('A'));
  AddPoint('B', '1');
  FDocument.Undo;
  AssertNear('set kept', 200, PointX('A'));
  AssertEquals(ConcatPaths([FFolder, 'sets', 'other.slm']), FDocument.Pattern.MeasurementFile);
  FDocument.Undo;
  AssertNull(FDocument.Pattern.FindObject('A'));
  AssertTrue('still modified: the set changed', FDocument.Modified);
end;

// A waist of 720 with A at waist / 4, so A is at 180 unscaled
procedure TTestDocument.TestMeasurementScaleScalesValues;
var
  Err: string;
begin
  AssertTrue(Err, FDocument.UseMeasurements(WriteSet('bill.slm', 720), Err));
  AddPoint('A', '@waist / 4');
  AssertNear('unscaled', 180, PointX('A'));
  AssertTrue(FDocument.SetMeasurementScale(1.1));
  AssertNear('scale', 1.1, FDocument.MeasurementScale);
  AssertNear('10% larger', 198, PointX('A'));
  AssertNear('the set is untouched', 720, FDocument.Measurements.Find('waist').Value);
  AssertTrue(FDocument.SetMeasurementScale(0.8));
  AssertNear('20% smaller', 144, PointX('A'));
  AssertTrue(FDocument.SetMeasurementScale(1));
  AssertNear('back', 180, PointX('A'));
end;

procedure TTestDocument.TestMeasurementScaleIsNotAChange;
var
  Err: string;
begin
  AssertTrue(Err, FDocument.UseMeasurements(WriteSet('bill.slm', 720), Err));
  AddPoint('A', '@waist / 4');
  AssertTrue(Err, FDocument.SaveToFile(ConcatPaths([FFolder, 'test.sloper']), Err));
  FDocument.SetMeasurementScale(1.2);
  AssertFalse('not modified', FDocument.Modified);
  AssertEquals('no undo step', 'Add point', FDocument.UndoDescription);
end;

procedure TTestDocument.TestMeasurementScaleIsNotSaved;
var
  Err, FileName: string;
begin
  AssertTrue(Err, FDocument.UseMeasurements(WriteSet('bill.slm', 720), Err));
  AddPoint('A', '@waist / 4');
  FDocument.SetMeasurementScale(1.2);
  FileName := ConcatPaths([FFolder, 'test.sloper']);
  AssertTrue(Err, FDocument.SaveToFile(FileName, Err));
  AssertTrue(Err, FDocument.LoadFromFile(FileName, Err));
  AssertNear('opens unscaled', 1, FDocument.MeasurementScale);
  AssertNear('unscaled', 180, PointX('A'));
end;

procedure TTestDocument.TestMeasurementScaleSurvivesUndo;
var
  Err: string;
begin
  AssertTrue(Err, FDocument.UseMeasurements(WriteSet('bill.slm', 720), Err));
  AddPoint('A', '@waist / 4');
  FDocument.SetMeasurementScale(1.1);
  AddPoint('B', '1');
  FDocument.Undo;
  AssertNear('scale kept', 1.1, FDocument.MeasurementScale);
  AssertNear('still scaled', 198, PointX('A'));
  FDocument.Redo;
  AssertNear('still scaled after redo', 198, PointX('A'));
end;

procedure TTestDocument.TestMeasurementScaleNotifies;
var
  Err: string;
begin
  AssertTrue(Err, FDocument.UseMeasurements(WriteSet('bill.slm', 720), Err));
  FChanges := nil;
  FDocument.AddListener(@Listen);
  FDocument.SetMeasurementScale(1.05);
  AssertEquals('one notification', 1, Length(FChanges));
  AssertTrue('measurements', dcMeasurements in FChanges[0]);
  AssertTrue('pattern', dcPattern in FChanges[0]);
  FDocument.SetMeasurementScale(1.05);
  AssertEquals('no change, no notification', 1, Length(FChanges));
end;

procedure TTestDocument.TestMeasurementScaleRefusesNonPositive;
begin
  AssertFalse(FDocument.SetMeasurementScale(0));
  AssertFalse(FDocument.SetMeasurementScale(-1));
  AssertNear('unchanged', 1, FDocument.MeasurementScale);
end;

procedure TTestDocument.TestNewPatternResetsMeasurementScale;
begin
  FDocument.SetMeasurementScale(1.2);
  FDocument.NewPattern;
  AssertNear('reset', 1, FDocument.MeasurementScale);
end;

procedure TTestDocument.TestOpeningResetsMeasurementScale;
var
  Err, FileName: string;
begin
  FileName := ConcatPaths([FFolder, 'test.sloper']);
  AssertTrue(Err, FDocument.SaveToFile(FileName, Err));
  FDocument.SetMeasurementScale(0.9);
  AssertTrue(Err, FDocument.LoadFromFile(FileName, Err));
  AssertNear('reset', 1, FDocument.MeasurementScale);
end;

procedure TTestDocument.TestNewPattern;
var
  Err: string;
begin
  AssertTrue(Err, FDocument.SaveToFile(ConcatPaths([FFolder, 'skirt.sloper']), Err));
  AddPoint('A', '10');
  FDocument.NewPattern;
  AssertEquals('objects', 0, FDocument.Pattern.ObjectCount);
  AssertEquals('file name', '', FDocument.FileName);
  AssertFalse('history', FDocument.CanUndo);
  AssertFalse('modified', FDocument.Modified);
  AssertTrue('mm unless asked', FDocument.Pattern.Units = muMillimetre);
  FDocument.NewPattern(muInch);
  AssertTrue('in the unit asked for', FDocument.Pattern.Units = muInch);
  AssertFalse('still not modified', FDocument.Modified);
end;

initialization
  RegisterTest(TTestDocument);

end.
