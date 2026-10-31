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

// The measurements app's document: undo, watching and merging the file.
unit Sloper.Tests.MeasurementDocument;

{$mode ObjFPC}{$H+}

interface

uses
  fpcunit, testregistry, Sloper.Tests.TestCase, Sloper.Core.Measurements, Sloper.Document.MeasurementDocument;

type
  TTestMeasurementDocument = class(TOSTestCase)
  private
    FDocument: TMeasurementDocument;
    FFileName: string;
    FChanges: integer;
    procedure DocumentChanged(Sender: TObject);
    // A file with waist 820 and hip 900, opened
    procedure OpenSample;
    // Another app changes one key in the file
    procedure ChangeOnDisk(const Key: string; Value: double);
    // Runs the two checks a changed file takes
    function CheckTwice: TMeasurementFileCheck;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestStartsEmpty;
    procedure TestEditsAreUndone;
    procedure TestRedo;
    procedure TestModified;
    procedure TestSaveClearsModified;
    procedure TestSaveIsNotAnUndoBarrier;
    procedure TestAddNumbersKeys;
    procedure TestAddToTableHasNoValues;
    procedure TestAddKnown;
    procedure TestRenameRefused;
    procedure TestRenameUndone;
    procedure TestMoveMeasurement;
    procedure TestClearValueNeedsATable;
    procedure TestSizesUndone;
    procedure TestDeleteLastSizeRefused;
    procedure TestSizeRefused;
    procedure TestOpenFailureKeepsDocument;
    procedure TestSameFileWaitsForAStableFile;
    procedure TestUnchangedFileIsSame;
    procedure TestReloadsWhenNothingUnsaved;
    procedure TestReloadClearsUndo;
    procedure TestMergesOtherKeys;
    procedure TestMergeKeepsAddedKey;
    procedure TestMergeTakesTheirNewKey;
    procedure TestMergeTakesDeletion;
    procedure TestSameChangeBothSides;
    procedure TestConflictKeepMine;
    procedure TestConflictTakeTheirs;
    procedure TestConflictTheyDeleted;
    procedure TestSaveRefusedWhileFileIsNewer;
    procedure TestSaveAfterMerge;
    procedure TestBrokenFileIgnored;
    procedure TestNewFileHasNothingToWatch;
  end;

implementation

uses
  SysUtils, Sloper.Core.JSON, Sloper.Core.Names;

procedure TTestMeasurementDocument.SetUp;
begin
  FDocument := TMeasurementDocument.Create;
  FDocument.OnChange := @DocumentChanged;
  FChanges := 0;
  FFileName := GetTempFileName(GetTempDir, 'osd');
end;

procedure TTestMeasurementDocument.TearDown;
begin
  FreeAndNil(FDocument);
  DeleteFile(FFileName);
end;

procedure TTestMeasurementDocument.DocumentChanged(Sender: TObject);
begin
  Inc(FChanges);
end;

procedure TTestMeasurementDocument.OpenSample;
var
  Sample: TMeasurementSet;
  Err: string;
begin
  Sample := TMeasurementSet.Create;
  try
    Sample.Add('waist', 820);
    Sample.Add('hip', 900);
    AssertTrue(Err, Sample.SaveToFile(FFileName, Err));
  finally
    FreeAndNil(Sample);
  end;
  AssertTrue(Err, FDocument.Open(FFileName, Err));
end;

procedure TTestMeasurementDocument.ChangeOnDisk(const Key: string; Value: double);
var
  Change: TMeasurementChange;
  Err: string;
begin
  AssertTrue(Err, ChangeMeasurementInFile(FFileName, Key, Value, '', Change, Err));
end;

function TTestMeasurementDocument.CheckTwice: TMeasurementFileCheck;
begin
  AssertTrue('the first check waits', FDocument.CheckFile = fcSame);
  Result := FDocument.CheckFile;
end;

procedure TTestMeasurementDocument.TestStartsEmpty;
begin
  AssertEquals(0, FDocument.Measurements.Count);
  AssertFalse(FDocument.Modified);
  AssertFalse(FDocument.CanUndo);
  AssertEquals('', FDocument.FileName);
end;

procedure TTestMeasurementDocument.TestEditsAreUndone;
begin
  OpenSample;
  FDocument.SetValue(0, 0, 830);
  FDocument.SetDescription(0, 'Waist');
  AssertEquals(rsChangeDescription, FDocument.UndoDescription);
  FDocument.Undo;
  AssertEquals('', FDocument.Measurements[0].Description);
  AssertNear('value kept', 830, FDocument.Measurements[0].Value);
  FDocument.Undo;
  AssertNear('value back', 820, FDocument.Measurements[0].Value);
  AssertFalse(FDocument.CanUndo);
end;

procedure TTestMeasurementDocument.TestRedo;
begin
  OpenSample;
  FDocument.SetValue(0, 0, 830);
  FDocument.Undo;
  AssertTrue(FDocument.CanRedo);
  FDocument.Redo;
  AssertNear('value', 830, FDocument.Measurements[0].Value);
  AssertFalse(FDocument.CanRedo);
end;

procedure TTestMeasurementDocument.TestModified;
begin
  OpenSample;
  AssertFalse(FDocument.Modified);
  FDocument.SetValue(0, 0, 830);
  AssertTrue(FDocument.Modified);
  FDocument.Undo;
  AssertFalse('back as saved', FDocument.Modified);
end;

procedure TTestMeasurementDocument.TestSaveClearsModified;
var
  Err: string;
  OnDisk: TMeasurementSet;
begin
  OpenSample;
  FDocument.SetValue(0, 0, 830);
  AssertTrue(Err, FDocument.Save(FFileName, Err));
  AssertFalse(FDocument.Modified);
  OnDisk := TMeasurementSet.Create;
  try
    AssertTrue(Err, OnDisk.LoadFromFile(FFileName, Err));
    AssertNear('written', 830, OnDisk.Find('waist').Value);
  finally
    FreeAndNil(OnDisk);
  end;
  AssertTrue('not seen as a change elsewhere', FDocument.CheckFile = fcSame);
  AssertTrue('nor on the next check', FDocument.CheckFile = fcSame);
end;

procedure TTestMeasurementDocument.TestSaveIsNotAnUndoBarrier;
var
  Err: string;
begin
  OpenSample;
  FDocument.SetValue(0, 0, 830);
  AssertTrue(Err, FDocument.Save(FFileName, Err));
  FDocument.Undo;
  AssertNear('value', 820, FDocument.Measurements[0].Value);
  AssertTrue(FDocument.Modified);
end;

procedure TTestMeasurementDocument.TestAddNumbersKeys;
begin
  AssertEquals('measurement', FDocument.AddMeasurement.Key);
  AssertEquals('measurement2', FDocument.AddMeasurement.Key);
  AssertEquals('measurement3', FDocument.AddMeasurement.Key);
  FDocument.Undo;
  AssertEquals(2, FDocument.Measurements.Count);
end;

procedure TTestMeasurementDocument.TestAddToTableHasNoValues;
var
  Err: string;
  Added: TMeasurement;
begin
  AssertTrue(Err, FDocument.AddSize('36', Err));
  AssertTrue(Err, FDocument.AddSize('38', Err));
  Added := FDocument.AddMeasurement;
  AssertFalse(Added.HasValueFor(0));
  AssertFalse(Added.HasValueFor(1));
end;

procedure TTestMeasurementDocument.TestAddKnown;
var
  Err: string;
begin
  OpenSample;
  AssertTrue(Err, FDocument.AddKnown('neck_circumference', 'Round the neck', Err));
  AssertEquals('Round the neck', FDocument.Measurements.Find('neck_circumference').Description);
  FDocument.Undo;
  AssertNull(FDocument.Measurements.Find('neck_circumference'));
  AssertFalse('already there', FDocument.AddKnown('waist', '', Err));
  AssertEquals(Format(rsNameTaken, ['waist']), Err);
  AssertEquals('nothing added', 2, FDocument.Measurements.Count);
end;

procedure TTestMeasurementDocument.TestRenameRefused;
var
  Err: string;
begin
  OpenSample;
  AssertFalse(FDocument.RenameKey(0, 'hip', Err));
  AssertEquals(Format(rsNameTaken, ['hip']), Err);
  AssertFalse(FDocument.RenameKey(0, '2nd', Err));
  AssertTrue(Err <> '');
  AssertEquals('waist', FDocument.Measurements[0].Key);
  AssertFalse('nothing to undo', FDocument.CanUndo);
end;

procedure TTestMeasurementDocument.TestRenameUndone;
var
  Err: string;
begin
  OpenSample;
  AssertTrue(Err, FDocument.RenameKey(0, 'waist_circumference', Err));
  AssertEquals('waist_circumference', FDocument.Measurements[0].Key);
  FDocument.Undo;
  AssertEquals('waist', FDocument.Measurements[0].Key);
end;

procedure TTestMeasurementDocument.TestMoveMeasurement;
begin
  OpenSample;
  FDocument.MoveMeasurement(1, 0);
  AssertEquals('hip', FDocument.Measurements[0].Key);
  FDocument.Undo;
  AssertEquals('waist', FDocument.Measurements[0].Key);
end;

procedure TTestMeasurementDocument.TestClearValueNeedsATable;
var
  Err: string;
begin
  OpenSample;
  AssertFalse(FDocument.ClearValue(0, 0, Err));
  AssertEquals(rsNeedsAValue, Err);
  AssertTrue(Err, FDocument.AddSize('M', Err));
  AssertTrue(Err, FDocument.ClearValue(0, 0, Err));
  AssertFalse(FDocument.Measurements[0].HasValue);
end;

procedure TTestMeasurementDocument.TestSizesUndone;
var
  Err: string;
begin
  OpenSample;
  AssertTrue(Err, FDocument.AddSize('M', Err));
  AssertTrue(Err, FDocument.AddSize('L', Err));
  FDocument.SetValue(0, 1, 860);
  FDocument.MoveSize(1, 0);
  AssertEquals('L', FDocument.Measurements.Sizes[0]);
  FDocument.Undo;
  AssertEquals('M', FDocument.Measurements.Sizes[0]);
  AssertTrue(Err, FDocument.DeleteSize(1, Err));
  FDocument.Undo;
  AssertNear('values come back', 860, FDocument.Measurements[0].ValueFor(1));
  AssertTrue(Err, FDocument.RenameSize(1, 'XL', Err));
  FDocument.Undo;
  AssertEquals('L', FDocument.Measurements.Sizes[1]);
end;

procedure TTestMeasurementDocument.TestDeleteLastSizeRefused;
var
  Err: string;
begin
  AssertTrue(Err, FDocument.AddSize('M', Err));
  AssertFalse(FDocument.DeleteSize(0, Err));
  AssertEquals(rsMeasurementLastSize, Err);
  AssertEquals(1, FDocument.Measurements.SizeCount);
end;

procedure TTestMeasurementDocument.TestSizeRefused;
var
  Err: string;
begin
  AssertTrue(Err, FDocument.AddSize('M', Err));
  AssertFalse(FDocument.AddSize('m', Err));
  AssertFalse(FDocument.AddSize(' ', Err));
  AssertTrue(Err, FDocument.AddSize('L', Err));
  AssertFalse(FDocument.RenameSize(1, 'M', Err));
  AssertEquals(2, FDocument.Measurements.SizeCount);
end;

procedure TTestMeasurementDocument.TestOpenFailureKeepsDocument;
var
  Err: string;
begin
  OpenSample;
  FDocument.SetValue(0, 0, 830);
  AssertTrue(Err, WriteTextFile(FFileName, 'not json', Err));
  AssertFalse(FDocument.Open(FFileName, Err));
  AssertNear('what was open stays', 830, FDocument.Measurements[0].Value);
end;

procedure TTestMeasurementDocument.TestSameFileWaitsForAStableFile;
begin
  OpenSample;
  ChangeOnDisk('waist', 830);
  AssertTrue(FDocument.CheckFile = fcSame);
  ChangeOnDisk('waist', 840);
  AssertTrue('still changing', FDocument.CheckFile = fcSame);
  AssertTrue(FDocument.CheckFile = fcReloaded);
  AssertNear('the last value', 840, FDocument.Measurements[0].Value);
end;

procedure TTestMeasurementDocument.TestUnchangedFileIsSame;
begin
  OpenSample;
  AssertTrue(FDocument.CheckFile = fcSame);
  AssertTrue(FDocument.CheckFile = fcSame);
end;

procedure TTestMeasurementDocument.TestReloadsWhenNothingUnsaved;
begin
  OpenSample;
  ChangeOnDisk('waist', 830);
  FChanges := 0;
  AssertTrue(CheckTwice = fcReloaded);
  AssertNear('value', 830, FDocument.Measurements[0].Value);
  AssertFalse(FDocument.Modified);
  AssertEquals('told', 1, FChanges);
end;

procedure TTestMeasurementDocument.TestReloadClearsUndo;
var
  Err: string;
begin
  OpenSample;
  FDocument.SetValue(0, 0, 825);
  AssertTrue(Err, FDocument.Save(FFileName, Err));
  ChangeOnDisk('waist', 830);
  AssertTrue(CheckTwice = fcReloaded);
  AssertFalse('an old step would undo the other app', FDocument.CanUndo);
end;

procedure TTestMeasurementDocument.TestMergesOtherKeys;
begin
  OpenSample;
  FDocument.SetValue(0, 0, 830);
  ChangeOnDisk('hip', 910);
  AssertTrue(CheckTwice = fcMerged);
  AssertNear('my edit', 830, FDocument.Measurements.Find('waist').Value);
  AssertNear('their edit', 910, FDocument.Measurements.Find('hip').Value);
  AssertTrue('mine is still unsaved', FDocument.Modified);
end;

procedure TTestMeasurementDocument.TestMergeKeepsAddedKey;
var
  Err: string;
begin
  OpenSample;
  AssertTrue(Err, FDocument.RenameKey(FDocument.Measurements.IndexOf(FDocument.AddMeasurement.Key), 'chest', Err));
  ChangeOnDisk('hip', 910);
  AssertTrue(CheckTwice = fcMerged);
  AssertNotNull(FDocument.Measurements.Find('chest'));
end;

procedure TTestMeasurementDocument.TestMergeTakesTheirNewKey;
begin
  OpenSample;
  FDocument.SetValue(0, 0, 830);
  ChangeOnDisk('chest', 880);
  AssertTrue(CheckTwice = fcMerged);
  AssertNear('value', 880, FDocument.Measurements.Find('chest').Value);
end;

procedure TTestMeasurementDocument.TestMergeTakesDeletion;
var
  Sample: TMeasurementSet;
  Err: string;
begin
  OpenSample;
  FDocument.SetValue(0, 0, 830);
  Sample := TMeasurementSet.Create;
  try
    AssertTrue(Err, Sample.LoadFromFile(FFileName, Err));
    Sample.Delete(Sample.Find('hip'));
    AssertTrue(Err, Sample.SaveToFile(FFileName, Err));
  finally
    FreeAndNil(Sample);
  end;
  AssertTrue(CheckTwice = fcMerged);
  AssertNull('deleted there, not touched here', FDocument.Measurements.Find('hip'));
end;

procedure TTestMeasurementDocument.TestSameChangeBothSides;
begin
  OpenSample;
  FDocument.SetValue(0, 0, 830);
  FDocument.SetValue(1, 0, 910);
  ChangeOnDisk('waist', 830);
  AssertTrue(CheckTwice = fcMerged);
  AssertEquals(0, Length(FDocument.Conflicts));
end;

procedure TTestMeasurementDocument.TestConflictKeepMine;
begin
  OpenSample;
  FDocument.SetValue(0, 0, 830);
  ChangeOnDisk('waist', 840);
  AssertTrue(CheckTwice = fcConflict);
  AssertEquals(1, Length(FDocument.Conflicts));
  AssertEquals('waist', FDocument.Conflicts[0]);
  AssertNear('nothing changes until it is answered', 830, FDocument.Measurements[0].Value);
  FDocument.ResolveConflicts(nil);
  AssertNear('mine', 830, FDocument.Measurements[0].Value);
  AssertEquals(0, Length(FDocument.Conflicts));
  AssertTrue('so it can be saved', FDocument.Modified);
  AssertTrue('and the file is taken in', FDocument.CheckFile = fcSame);
end;

procedure TTestMeasurementDocument.TestConflictTakeTheirs;
var
  Keep: TStringArray;
begin
  OpenSample;
  FDocument.SetValue(0, 0, 830);
  FDocument.SetValue(1, 0, 910);
  ChangeOnDisk('waist', 840);
  AssertTrue(CheckTwice = fcConflict);
  Keep := nil;
  Insert('waist', Keep, 0);
  FDocument.ResolveConflicts(Keep);
  AssertNear('theirs', 840, FDocument.Measurements.Find('waist').Value);
  AssertNear('my other edit stays', 910, FDocument.Measurements.Find('hip').Value);
end;

procedure TTestMeasurementDocument.TestConflictTheyDeleted;
var
  Sample: TMeasurementSet;
  Err: string;
  Keep: TStringArray;
begin
  OpenSample;
  FDocument.SetValue(1, 0, 910);
  Sample := TMeasurementSet.Create;
  try
    AssertTrue(Err, Sample.LoadFromFile(FFileName, Err));
    Sample.Delete(Sample.Find('hip'));
    AssertTrue(Err, Sample.SaveToFile(FFileName, Err));
  finally
    FreeAndNil(Sample);
  end;
  AssertTrue(CheckTwice = fcConflict);
  Keep := nil;
  Insert('hip', Keep, 0);
  FDocument.ResolveConflicts(Keep);
  AssertNull('their deletion taken', FDocument.Measurements.Find('hip'));
end;

procedure TTestMeasurementDocument.TestSaveRefusedWhileFileIsNewer;
var
  Err: string;
  OnDisk: TMeasurementSet;
begin
  OpenSample;
  FDocument.SetValue(0, 0, 830);
  ChangeOnDisk('hip', 910);
  AssertFalse('it would lose their change', FDocument.Save(FFileName, Err));
  AssertEquals(rsFileChangedOnDisk, Err);
  OnDisk := TMeasurementSet.Create;
  try
    AssertTrue(Err, OnDisk.LoadFromFile(FFileName, Err));
    AssertNear('untouched', 820, OnDisk.Find('waist').Value);
    AssertNear('untouched', 910, OnDisk.Find('hip').Value);
  finally
    FreeAndNil(OnDisk);
  end;
end;

procedure TTestMeasurementDocument.TestSaveAfterMerge;
var
  Err: string;
  OnDisk: TMeasurementSet;
begin
  OpenSample;
  FDocument.SetValue(0, 0, 830);
  ChangeOnDisk('hip', 910);
  AssertTrue(CheckTwice = fcMerged);
  AssertTrue(Err, FDocument.Save(FFileName, Err));
  OnDisk := TMeasurementSet.Create;
  try
    AssertTrue(Err, OnDisk.LoadFromFile(FFileName, Err));
    AssertNear('both', 830, OnDisk.Find('waist').Value);
    AssertNear('both', 910, OnDisk.Find('hip').Value);
  finally
    FreeAndNil(OnDisk);
  end;
end;

procedure TTestMeasurementDocument.TestBrokenFileIgnored;
var
  Err: string;
begin
  OpenSample;
  AssertTrue(Err, WriteTextFile(FFileName, '{"format"', Err));
  AssertTrue(CheckTwice = fcSame);
  AssertTrue('and again', FDocument.CheckFile = fcSame);
  AssertEquals(2, FDocument.Measurements.Count);
end;

procedure TTestMeasurementDocument.TestNewFileHasNothingToWatch;
begin
  AssertTrue(FDocument.CheckFile = fcSame);
end;

initialization
  RegisterTest(TTestMeasurementDocument);

end.
