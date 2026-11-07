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

unit Sloper.Tests.Measurements;

{$mode ObjFPC}{$H+}

interface

uses
  fpcunit, testregistry, Sloper.Tests.TestCase, Sloper.Core.Measurements, Sloper.Core.Units;

type
  TTestMeasurements = class(TOSTestCase)
  private
    FSet: TMeasurementSet;
    procedure AssertLoadFails(const Text, Msg: string);
    procedure LoadTable;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestAddAndFind;
    procedure TestChangeInFile;
    procedure TestChangeKeepsChangesMadeElsewhere;
    procedure TestChangeAddsNewKey;
    procedure TestChangeRefusesBadKey;
    procedure TestChangeMissingFile;
    procedure TestChangeLeavesNoTempFile;
    procedure TestCreateFile;
    procedure TestKeysIgnoreCase;
    procedure TestCheckKey;
    procedure TestAddRejectsBadKey;
    procedure TestRename;
    procedure TestDelete;
    procedure TestSaveText;
    procedure TestRoundTrip;
    procedure TestFileRoundTrip;
    procedure TestLoadErrors;
    procedure TestFailedLoadLeavesSetEmpty;
    procedure TestMissingFile;
    procedure TestSizeTable;
    procedure TestSizeTableRoundTrip;
    procedure TestPersonalSetHasNoSizes;
    procedure TestBadSizeTables;
    procedure TestNoValueForSize;
    procedure TestNoValueBlocksFormulas;
    procedure TestFirstSizeKeepsValues;
    procedure TestAddSizeStartsEmpty;
    procedure TestAddToATable;
    procedure TestSizeNames;
    procedure TestRenameSize;
    procedure TestDeleteSize;
    procedure TestDeleteLastSizeRefused;
    procedure TestMoveSize;
    procedure TestMoveMeasurement;
    procedure TestChangeOneSize;
    procedure TestChangeNeedsASize;
    procedure TestChangeAddsToOneSize;
    procedure TestChangeKeepsDescription;
    procedure TestChangeFillsAnEmptySize;
    procedure TestMissingKeys;
    procedure TestMissingValuesBySize;
    procedure TestNothingMissing;
    procedure TestListPersonal;
    procedure TestListTable;
    procedure TestListOneSize;
    procedure TestFormatMeasure;
    procedure TestParseMeasure;
    procedure TestMergeSizes;
    procedure TestMergeKeepsSizeValues;
  end;

implementation

uses
  SysUtils, Sloper.Core.Names, Sloper.Core.EvalTypes, Sloper.Core.Pattern, Sloper.Core.Draft;

const
  SampleText =
    '{'#10 +
    '  "format": "measurements",'#10 +
    '  "version": 1,'#10 +
    '  "units": "mm",'#10 +
    '  "name": "Bill",'#10 +
    '  "notes": "Measured over a T-shirt",'#10 +
    '  "measurements": ['#10 +
    '    {'#10 +
    '      "key": "waist",'#10 +
    '      "value": 820,'#10 +
    '      "description": "Waist circumference"'#10 +
    '    },'#10 +
    '    {'#10 +
    '      "key": "back_length",'#10 +
    '      "value": 432.5,'#10 +
    '      "description": ""'#10 +
    '    }'#10 +
    '  ]'#10 +
    '}'#10;

const
  TableText =
    '{'#10 +
    '  "format": "measurements",'#10 +
    '  "version": 1,'#10 +
    '  "units": "mm",'#10 +
    '  "name": "Block",'#10 +
    '  "notes": "",'#10 +
    '  "sizes": ['#10 +
    '    "36",'#10 +
    '    "38",'#10 +
    '    "40"'#10 +
    '  ],'#10 +
    '  "measurements": ['#10 +
    '    {'#10 +
    '      "key": "waist",'#10 +
    '      "values": ['#10 +
    '        700,'#10 +
    '        740.5,'#10 +
    '        780'#10 +
    '      ],'#10 +
    '      "description": "Waist"'#10 +
    '    },'#10 +
    '    {'#10 +
    '      "key": "hip",'#10 +
    '      "values": ['#10 +
    '        900,'#10 +
    '        null,'#10 +
    '        980'#10 +
    '      ],'#10 +
    '      "description": ""'#10 +
    '    }'#10 +
    '  ]'#10 +
    '}'#10;

procedure TTestMeasurements.SetUp;
begin
  FSet := TMeasurementSet.Create;
end;

procedure TTestMeasurements.TearDown;
begin
  FreeAndNil(FSet);
end;

procedure TTestMeasurements.AssertLoadFails(const Text, Msg: string);
var
  Err: string;
begin
  AssertFalse(Msg + ' loads', FSet.LoadFromText(Text, Err));
  AssertEquals(Msg, Msg, Err);
end;

procedure TTestMeasurements.LoadTable;
var
  Err: string;
begin
  AssertTrue(Err, FSet.LoadFromText(TableText, Err));
end;

procedure TTestMeasurements.TestSizeTable;
begin
  LoadTable;
  AssertEquals(3, FSet.SizeCount);
  AssertEquals('the first until another is selected', '36', FSet.SizeName);
  AssertNear('value', 700, FSet.Find('waist').Value);
  AssertTrue(FSet.SelectSize('38'));
  AssertEquals(1, FSet.SizeIndex);
  AssertNear('value', 740.5, FSet.Find('waist').Value);
  AssertFalse('unknown', FSet.SelectSize('42'));
  AssertEquals('stays where it was', '38', FSet.SizeName);
end;

procedure TTestMeasurements.TestSizeTableRoundTrip;
begin
  LoadTable;
  AssertEquals(TableText, FSet.SaveToText);
end;

procedure TTestMeasurements.TestPersonalSetHasNoSizes;
var
  Err: string;
begin
  AssertTrue(Err, FSet.LoadFromText(SampleText, Err));
  AssertEquals(0, FSet.SizeCount);
  AssertEquals('', FSet.SizeName);
  AssertTrue(FSet.Find('waist').HasValue);
  AssertEquals(SampleText, FSet.SaveToText);
end;

procedure TTestMeasurements.TestBadSizeTables;
const
  Head = '{"format": "measurements", "version": 1, ';
begin
  AssertLoadFails(Head + '"sizes": 3, "measurements": []}', rsMeasurementBadSizes);
  AssertLoadFails(Head + '"sizes": [36], "measurements": []}', rsMeasurementBadSizes);
  AssertLoadFails(Head + '"sizes": [" "], "measurements": []}', rsMeasurementSizeEmpty);
  AssertLoadFails(Head + '"sizes": ["S", "s"], "measurements": []}', Format(rsMeasurementSizeTaken, ['s']));
  AssertLoadFails(Head + '"sizes": ["36", "38"], "measurements": [{"key": "a", "values": [1]}]}',
    Format(rsMeasurementBadValues, ['a', 2]));
  AssertLoadFails(Head + '"sizes": ["36"], "measurements": [{"key": "a", "value": 1}]}',
    Format(rsMeasurementBadValues, ['a', 1]));
  AssertLoadFails(Head + '"sizes": ["36"], "measurements": [{"key": "a", "values": ["1"]}]}',
    Format(rsMeasurementBadValue, ['a']));
end;

procedure TTestMeasurements.TestNoValueForSize;
var
  Value: double;
begin
  LoadTable;
  FSet.SelectSize('38');
  AssertFalse(FSet.Find('hip').HasValue);
  AssertFalse(FSet.TryGetValue('hip', Value));
  AssertEquals(Format(rsMeasurementNoSizeValue, ['hip', '38']), FSet.ValueProblem('hip'));
  AssertEquals(Format(rsMeasurementNotInSet, ['chest']), FSet.ValueProblem('chest'));
  AssertEquals('', FSet.ValueProblem('waist'));
  FSet.SelectSize('40');
  AssertNear('value', 980, FSet.Find('hip').Value);
end;

procedure TTestMeasurements.TestNoValueBlocksFormulas;
var
  Pattern: TPattern;
  Point: TDraftObject;
begin
  LoadTable;
  FSet.SelectSize('38');
  Pattern := TPattern.Create;
  try
    Pattern.Measurements := FSet;
    Point := Pattern.AddFreePoint('A', '@hip', '0');
    Pattern.Evaluate;
    AssertEquals('one error, on the measurement', Format(rsMeasurementNoSizeValue, ['hip', '38']), Pattern.FindNode('@hip').Message);
    AssertTrue('what reads it is blocked', Point.State = esBlocked);
    FSet.SelectSize('36');
    Pattern.Evaluate;
    AssertTrue('valid at a size with a value', Point.State = esValid);
    Pattern.Measurements := nil;
  finally
    FreeAndNil(Pattern);
  end;
end;

procedure TTestMeasurements.TestFirstSizeKeepsValues;
begin
  FSet.Add('waist', 820);
  FSet.AddSize('M');
  AssertEquals('M', FSet.SizeName);
  AssertNear('value', 820, FSet.Find('waist').Value);
end;

procedure TTestMeasurements.TestAddSizeStartsEmpty;
begin
  LoadTable;
  FSet.AddSize('42');
  AssertEquals(4, FSet.SizeCount);
  AssertFalse(FSet.Find('waist').HasValueFor(3));
  AssertEquals('the selection stays', '36', FSet.SizeName);
  AssertNear('value', 780, FSet.Find('waist').ValueFor(2));
end;

procedure TTestMeasurements.TestAddToATable;
var
  Measurement: TMeasurement;
begin
  LoadTable;
  FSet.SelectSize('38');
  Measurement := FSet.Add('chest', 880);
  AssertTrue('the selected size', Measurement.HasValueFor(1));
  AssertFalse(Measurement.HasValueFor(0));
  AssertFalse(Measurement.HasValueFor(2));
end;

procedure TTestMeasurements.TestSizeNames;
var
  Err: string;
begin
  LoadTable;
  AssertFalse(FSet.CheckSize('', -1, Err));
  AssertEquals(rsMeasurementSizeEmpty, Err);
  AssertFalse(FSet.CheckSize('38', -1, Err));
  AssertEquals(Format(rsMeasurementSizeTaken, ['38']), Err);
  AssertTrue('itself', FSet.CheckSize('38', 1, Err));
  AssertTrue(FSet.CheckSize('42', -1, Err));
end;

procedure TTestMeasurements.TestRenameSize;
begin
  LoadTable;
  FSet.RenameSize(0, 'S');
  AssertEquals('S', FSet.SizeName);
  AssertNear('value', 700, FSet.Find('waist').Value);
  try
    FSet.RenameSize(0, '38');
    Fail('a taken name is refused');
  except
    on EMeasurementError do ;
  end;
end;

procedure TTestMeasurements.TestDeleteSize;
begin
  LoadTable;
  FSet.SelectSize('40');
  FSet.DeleteSize(0);
  AssertEquals(2, FSet.SizeCount);
  AssertEquals('the selection follows its size', '40', FSet.SizeName);
  AssertNear('value', 780, FSet.Find('waist').Value);
  FSet.DeleteSize(1);
  AssertEquals('the selected one goes', '38', FSet.SizeName);
  AssertNear('value', 740.5, FSet.Find('waist').Value);
end;

procedure TTestMeasurements.TestDeleteLastSizeRefused;
begin
  FSet.AddSize('M');
  try
    FSet.DeleteSize(0);
    Fail('a table keeps one size');
  except
    on Failure: EMeasurementError do
      AssertEquals(rsMeasurementLastSize, Failure.Message);
  end;
end;

procedure TTestMeasurements.TestMoveSize;
begin
  LoadTable;
  FSet.SelectSize('36');
  FSet.MoveSize(0, 2);
  AssertEquals('38', FSet.Sizes[0]);
  AssertEquals('36', FSet.Sizes[2]);
  AssertEquals('the selection follows its size', '36', FSet.SizeName);
  AssertNear('value', 700, FSet.Find('waist').Value);
  AssertFalse('values move with their size', FSet.Find('hip').HasValueFor(0));
  AssertNear('value', 980, FSet.Find('hip').ValueFor(1));
end;

procedure TTestMeasurements.TestMoveMeasurement;
begin
  LoadTable;
  FSet.Move(FSet.Find('hip'), 0);
  AssertEquals('hip', FSet[0].Key);
  AssertEquals('waist', FSet[1].Key);
  AssertEquals('found by key as before', 1, FSet.IndexOf('waist'));
end;

procedure TTestMeasurements.TestChangeOneSize;
var
  FileName, Err: string;
  Change: TMeasurementChange;
begin
  FileName := GetTempFileName(GetTempDir, 'osm');
  try
    LoadTable;
    AssertTrue(Err, FSet.SaveToFile(FileName, Err));
    AssertTrue(Err, ChangeMeasurementInFile(FileName, 'waist', 750, '', Change, Err, '38'));
    AssertNear('old', 740.5, Change.OldValue);
    AssertTrue(Err, FSet.LoadFromFile(FileName, Err));
    AssertNear('changed', 750, FSet.Find('waist').ValueFor(1));
    AssertNear('the others stay', 700, FSet.Find('waist').ValueFor(0));
    AssertNear('the others stay', 780, FSet.Find('waist').ValueFor(2));
  finally
    DeleteFile(FileName);
  end;
end;

procedure TTestMeasurements.TestChangeNeedsASize;
var
  FileName, Err: string;
  Change: TMeasurementChange;
begin
  FileName := GetTempFileName(GetTempDir, 'osm');
  try
    LoadTable;
    AssertTrue(Err, FSet.SaveToFile(FileName, Err));
    AssertFalse(ChangeMeasurementInFile(FileName, 'waist', 750, '', Change, Err));
    AssertEquals(rsMeasurementNeedsSize, Err);
    AssertFalse(ChangeMeasurementInFile(FileName, 'waist', 750, '', Change, Err, '42'));
    AssertEquals(Format(rsMeasurementUnknownSize, ['42']), Err);
    FSet.Clear;
    FSet.Add('waist', 820);
    AssertTrue(Err, FSet.SaveToFile(FileName, Err));
    AssertFalse('a personal set has no sizes', ChangeMeasurementInFile(FileName, 'waist', 750, '', Change, Err, '38'));
  finally
    DeleteFile(FileName);
  end;
end;

procedure TTestMeasurements.TestChangeAddsToOneSize;
var
  FileName, Err: string;
  Change: TMeasurementChange;
begin
  FileName := GetTempFileName(GetTempDir, 'osm');
  try
    LoadTable;
    AssertTrue(Err, FSet.SaveToFile(FileName, Err));
    AssertTrue(Err, ChangeMeasurementInFile(FileName, 'chest', 880, '', Change, Err, '40'));
    AssertTrue(Change.Added);
    AssertTrue(Err, FSet.LoadFromFile(FileName, Err));
    AssertNear('value', 880, FSet.Find('chest').ValueFor(2));
    AssertFalse(FSet.Find('chest').HasValueFor(0));
  finally
    DeleteFile(FileName);
  end;
end;

procedure TTestMeasurements.TestChangeKeepsDescription;
var
  FileName, Err: string;
  Change: TMeasurementChange;
begin
  FileName := GetTempFileName(GetTempDir, 'osm');
  try
    FSet.Add('waist', 820, 'Old');
    AssertTrue(Err, FSet.SaveToFile(FileName, Err));
    AssertTrue(Err, ChangeMeasurementInFile(FileName, 'waist', 830, 'Ignored', Change, Err, '', True));
    AssertTrue(Err, ChangeMeasurementInFile(FileName, 'chest', 900, 'New key', Change, Err, '', True));
    AssertTrue(Err, FSet.LoadFromFile(FileName, Err));
    AssertEquals('kept', 'Old', FSet.Find('waist').Description);
    AssertNear('changed', 830, FSet.Find('waist').Value);
    AssertEquals('a new key has only this one', 'New key', FSet.Find('chest').Description);
  finally
    DeleteFile(FileName);
  end;
end;

procedure TTestMeasurements.TestChangeFillsAnEmptySize;
var
  FileName, Err: string;
  Change: TMeasurementChange;
begin
  FileName := GetTempFileName(GetTempDir, 'osm');
  try
    LoadTable;
    AssertTrue(Err, FSet.SaveToFile(FileName, Err));
    AssertTrue(Err, ChangeMeasurementInFile(FileName, 'hip', 940, '', Change, Err, '38'));
    AssertFalse('the key was there', Change.Added);
    AssertFalse('but that size had nothing to replace', Change.HadValue);
    AssertTrue(Err, ChangeMeasurementInFile(FileName, 'hip', 950, '', Change, Err, '38'));
    AssertTrue(Change.HadValue);
    AssertNear('old', 940, Change.OldValue);
  finally
    DeleteFile(FileName);
  end;
end;

procedure TTestMeasurements.TestMissingKeys;
var
  Keys: TStringArray;
  Found: TMissingMeasurementArray;
begin
  FSet.Add('waist', 820);
  Keys := nil;
  Insert('WAIST', Keys, 0);
  Insert('chest', Keys, 1);
  Found := MissingMeasurements(Keys, FSet);
  AssertEquals(1, Length(Found));
  AssertEquals('chest', Found[0].Key);
  AssertEquals('not in the set at all', 0, Length(Found[0].Sizes));
end;

procedure TTestMeasurements.TestMissingValuesBySize;
var
  Keys: TStringArray;
  Found: TMissingMeasurementArray;
begin
  LoadTable;
  Keys := nil;
  Insert('HIP', Keys, 0);
  Insert('waist', Keys, 1);
  Found := MissingMeasurements(Keys, FSet);
  AssertEquals('waist has all its values', 1, Length(Found));
  AssertEquals('the stored spelling', 'hip', Found[0].Key);
  AssertEquals(1, Length(Found[0].Sizes));
  AssertEquals('38', Found[0].Sizes[0]);
end;

procedure TTestMeasurements.TestNothingMissing;
begin
  AssertEquals(0, Length(MissingMeasurements(nil, FSet)));
end;

procedure TTestMeasurements.TestListPersonal;
begin
  FSet.Add('waist', 820.5, 'Round it');
  AssertEquals('key'#9'value'#9'description'#10'waist'#9'820.5'#9'Round it'#10, MeasurementListText(FSet, ''));
end;

procedure TTestMeasurements.TestListTable;
begin
  LoadTable;
  AssertEquals('key'#9'36'#9'38'#9'40'#9'description'#10'waist'#9'700'#9'740.5'#9'780'#9'Waist'#10'hip'#9'900'#9#9'980'#9#10, MeasurementListText(FSet, ''));
end;

procedure TTestMeasurements.TestListOneSize;
begin
  LoadTable;
  AssertEquals('key'#9'value'#9'description'#10'waist'#9'740.5'#9'Waist'#10'hip'#9#9#10, MeasurementListText(FSet, '38'));
end;

procedure TTestMeasurements.TestFormatMeasure;
begin
  AssertEquals('820.5', FormatMeasure(820.5, muMillimetre));
  AssertEquals('82.05', FormatMeasure(820.5, muCentimetre));
  AssertEquals('32.2835', FormatMeasure(820, muInch));
  AssertEquals('whole numbers stay whole', '10', FormatMeasure(254, muInch));
end;

procedure TTestMeasurements.TestParseMeasure;
var
  Value: double;
begin
  AssertTrue(ParseMeasure('820', muMillimetre, Value));
  AssertNear('mm', 820, Value);
  AssertTrue(ParseMeasure(' 82.5 ', muCentimetre, Value));
  AssertNear('cm', 825, Value);
  AssertTrue(ParseMeasure('10', muInch, Value));
  AssertNear('in', 254, Value);
  AssertTrue('a decimal comma', ParseMeasure('82,5', muCentimetre, Value));
  AssertNear('comma', 825, Value);
  AssertFalse(ParseMeasure('', muMillimetre, Value));
  AssertFalse(ParseMeasure('wide', muMillimetre, Value));
  AssertFalse('too big', ParseMeasure('1e13', muMillimetre, Value));
end;

procedure TTestMeasurements.TestMergeSizes;
var
  Base, Mine, Theirs, Merged: TMeasurementSet;
  Conflicts: TStringArray;
begin
  Base := TMeasurementSet.Create;
  Mine := TMeasurementSet.Create;
  Theirs := TMeasurementSet.Create;
  Merged := TMeasurementSet.Create;
  try
    Base.AddSize('36');
    Base.AddSize('38');
    Mine.AddSize('36');
    Mine.AddSize('38');
    Mine.AddSize('40');
    Theirs.AddSize('38');
    Theirs.AddSize('42');
    MergeMeasurementSets(Base, Mine, Theirs, nil, Merged, Conflicts);
    AssertEquals('they deleted 36, each added one', 3, Merged.SizeCount);
    AssertEquals('38', Merged.Sizes[0]);
    AssertEquals('42', Merged.Sizes[1]);
    AssertEquals('40', Merged.Sizes[2]);
  finally
    FreeAndNil(Merged);
    FreeAndNil(Theirs);
    FreeAndNil(Mine);
    FreeAndNil(Base);
  end;
end;

procedure TTestMeasurements.TestMergeKeepsSizeValues;
var
  Base, Mine, Theirs, Merged: TMeasurementSet;
  Conflicts: TStringArray;
  Err: string;
begin
  Base := TMeasurementSet.Create;
  Mine := TMeasurementSet.Create;
  Theirs := TMeasurementSet.Create;
  Merged := TMeasurementSet.Create;
  try
    AssertTrue(Err, Base.LoadFromText(TableText, Err));
    AssertTrue(Err, Mine.LoadFromText(TableText, Err));
    AssertTrue(Err, Theirs.LoadFromText(TableText, Err));
    Mine.Find('waist').SetValueFor(1, 745);
    Theirs.Find('hip').SetValueFor(1, 940);
    MergeMeasurementSets(Base, Mine, Theirs, nil, Merged, Conflicts);
    AssertEquals(0, Length(Conflicts));
    AssertNear('mine', 745, Merged.Find('waist').ValueFor(1));
    AssertNear('the rest of it', 780, Merged.Find('waist').ValueFor(2));
    AssertNear('theirs', 940, Merged.Find('hip').ValueFor(1));
  finally
    FreeAndNil(Merged);
    FreeAndNil(Theirs);
    FreeAndNil(Mine);
    FreeAndNil(Base);
  end;
end;

procedure TTestMeasurements.TestAddAndFind;
var
  V: double;
begin
  FSet.Add('waist', 820, 'Waist circumference');
  FSet.Add('hip', 1010);
  AssertEquals('count', 2, FSet.Count);
  AssertEquals('order kept', 'hip', FSet[1].Key);
  AssertTrue(FSet.TryGetValue('hip', V));
  AssertNear('value', 1010, V);
  AssertFalse('missing', FSet.TryGetValue('chest', V));
  AssertNull(FSet.Find('chest'));
end;

procedure TTestMeasurements.TestKeysIgnoreCase;
begin
  FSet.Add('Waist', 820);
  AssertNotNull(FSet.Find('WAIST'));
  AssertEquals('spelling kept', 'Waist', FSet.Find('waist').Key);
end;

procedure TTestMeasurements.TestCheckKey;
var
  Msg: string;
  M: TMeasurement;
begin
  M := FSet.Add('waist', 820);
  AssertFalse('duplicate', FSet.CheckKey('WAIST', nil, Msg));
  AssertTrue('same item may keep its key', FSet.CheckKey('Waist', M, Msg));
  AssertFalse('invalid', FSet.CheckKey('back-length', nil, Msg));
  AssertFalse('reserved', FSet.CheckKey('sqrt', nil, Msg));
  AssertTrue('new', FSet.CheckKey('hip', nil, Msg));
end;

procedure TTestMeasurements.TestAddRejectsBadKey;
begin
  FSet.Add('waist', 820);
  try
    FSet.Add('waist', 1);
    Fail('duplicate accepted');
  except
    on EMeasurementError do ;
  end;
  AssertEquals(1, FSet.Count);
end;

procedure TTestMeasurements.TestRename;
var
  M: TMeasurement;
begin
  M := FSet.Add('waist', 820);
  FSet.Add('hip', 1010);
  FSet.Rename(M, 'waist_natural');
  AssertNotNull(FSet.Find('waist_natural'));
  AssertSame('any case', M, FSet.Find('WAIST_Natural'));
  AssertNull(FSet.Find('waist'));
  try
    FSet.Rename(M, 'hip');
    Fail('rename onto another key accepted');
  except
    on EMeasurementError do ;
  end;
end;

procedure TTestMeasurements.TestDelete;
begin
  FSet.Add('waist', 820);
  FSet.Delete(FSet.Find('waist'));
  AssertEquals(0, FSet.Count);
  AssertNull('not found', FSet.Find('waist'));
  AssertNotNull('key free again', FSet.Add('waist', 800));
end;

procedure TTestMeasurements.TestSaveText;
begin
  FSet.Name := 'Bill';
  FSet.Notes := 'Measured over a T-shirt';
  FSet.Add('waist', 820, 'Waist circumference');
  FSet.Add('back_length', 432.5);
  AssertEquals(SampleText, FSet.SaveToText);
end;

procedure TTestMeasurements.TestRoundTrip;
var
  Err: string;
begin
  AssertTrue(FSet.LoadFromText(SampleText, Err));
  AssertEquals('name', 'Bill', FSet.Name);
  AssertEquals('count', 2, FSet.Count);
  AssertNear('value', 432.5, FSet.Find('back_length').Value);
  AssertEquals('identical after save', SampleText, FSet.SaveToText);
end;

procedure TTestMeasurements.TestFileRoundTrip;
var
  FileName, Err: string;
  Other: TMeasurementSet;
begin
  FileName := GetTempFileName(GetTempDir, 'osm');
  try
    FSet.Name := 'Ärmel test';
    FSet.Add('waist', 820);
    AssertTrue(Err, FSet.SaveToFile(FileName, Err));
    Other := TMeasurementSet.Create;
    try
      AssertTrue(Err, Other.LoadFromFile(FileName, Err));
      AssertEquals('UTF-8 name', 'Ärmel test', Other.Name);
      AssertNear('value', 820, Other.Find('waist').Value);
    finally
      FreeAndNil(Other);
    end;
  finally
    DeleteFile(FileName);
  end;
end;

procedure TTestMeasurements.TestLoadErrors;
begin
  AssertLoadFails('{"format": "pattern", "version": 1, "measurements": []}', rsMeasurementWrongFormat);
  AssertLoadFails('{"format": "measurements", "version": 2, "measurements": []}',
    Format(rsMeasurementNewerVersion, [2]));
  AssertLoadFails('{"format": "measurements", "version": 1, "units": "cm", "measurements": []}',
    Format(rsMeasurementUnits, ['cm']));
  AssertLoadFails('{"format": "measurements", "version": 1}', rsMeasurementList);
  AssertLoadFails('{"format": "measurements", "version": 1, "measurements": [{"value": 1}]}',
    Format(rsMeasurementMissing, ['key']));
  AssertLoadFails('{"format": "measurements", "version": 1, "measurements": [{"key": "hip", "value": "big"}]}',
    Format(rsMeasurementBadValue, ['hip']));
  AssertLoadFails('{"format": "measurements", "version": 1, "measurements": ' +
    '[{"key": "hip", "value": 1}, {"key": "HIP", "value": 2}]}',
    Format(rsMeasurementBadKey, [Format(rsNameTaken, ['HIP'])]));
end;

procedure TTestMeasurements.TestFailedLoadLeavesSetEmpty;
var
  Err: string;
begin
  FSet.Add('waist', 820);
  AssertFalse(FSet.LoadFromText('not json', Err));
  AssertEquals(0, FSet.Count);
end;

procedure TTestMeasurements.TestMissingFile;
var
  Err: string;
begin
  AssertFalse(FSet.LoadFromFile(ConcatPaths([GetTempDir, 'no-such-file.slm']), Err));
  AssertTrue('message names the file', Pos('no-such-file.slm', Err) > 0);
end;

procedure TTestMeasurements.TestChangeInFile;
var
  FileName, Err: string;
  Change: TMeasurementChange;
begin
  FileName := GetTempFileName(GetTempDir, 'osm');
  try
    FSet.Add('waist', 820, 'Old');
    AssertTrue(Err, FSet.SaveToFile(FileName, Err));
    AssertTrue(Err, ChangeMeasurementInFile(FileName, 'WAIST', 830, 'New', Change, Err));
    AssertEquals('stored spelling', 'waist', Change.Key);
    AssertNear('old', 820, Change.OldValue);
    AssertNear('new', 830, Change.Value);
    AssertFalse('not added', Change.Added);
    AssertTrue(Err, FSet.LoadFromFile(FileName, Err));
    AssertNear('written', 830, FSet.Find('waist').Value);
    AssertEquals('description', 'New', FSet.Find('waist').Description);
  finally
    DeleteFile(FileName);
  end;
end;

// The set in memory is out of date: another app changed hip since it was loaded
procedure TTestMeasurements.TestChangeKeepsChangesMadeElsewhere;
var
  FileName, Err: string;
  Change: TMeasurementChange;
  Elsewhere: TMeasurementSet;
begin
  FileName := GetTempFileName(GetTempDir, 'osm');
  try
    FSet.Add('waist', 820);
    FSet.Add('hip', 900);
    AssertTrue(Err, FSet.SaveToFile(FileName, Err));
    Elsewhere := TMeasurementSet.Create;
    try
      AssertTrue(Err, Elsewhere.LoadFromFile(FileName, Err));
      Elsewhere.Find('hip').Value := 910;
      Elsewhere.Add('neck', 400);
      AssertTrue(Err, Elsewhere.SaveToFile(FileName, Err));
    finally
      FreeAndNil(Elsewhere);
    end;
    AssertTrue(Err, ChangeMeasurementInFile(FileName, 'waist', 830, '', Change, Err));
    AssertTrue(Err, FSet.LoadFromFile(FileName, Err));
    AssertNear('this edit', 830, FSet.Find('waist').Value);
    AssertNear('their edit kept', 910, FSet.Find('hip').Value);
    AssertNotNull('their new key kept', FSet.Find('neck'));
  finally
    DeleteFile(FileName);
  end;
end;

procedure TTestMeasurements.TestChangeAddsNewKey;
var
  FileName, Err: string;
  Change: TMeasurementChange;
begin
  FileName := GetTempFileName(GetTempDir, 'osm');
  try
    AssertTrue(Err, FSet.SaveToFile(FileName, Err));
    AssertTrue(Err, ChangeMeasurementInFile(FileName, 'chest', 900, 'Round the chest', Change, Err));
    AssertTrue('added', Change.Added);
    AssertTrue(Err, FSet.LoadFromFile(FileName, Err));
    AssertEquals('Round the chest', FSet.Find('chest').Description);
  finally
    DeleteFile(FileName);
  end;
end;

procedure TTestMeasurements.TestChangeRefusesBadKey;
var
  FileName, Err, Before, After: string;
  Change: TMeasurementChange;
begin
  FileName := GetTempFileName(GetTempDir, 'osm');
  try
    FSet.Add('waist', 820);
    AssertTrue(Err, FSet.SaveToFile(FileName, Err));
    Before := FSet.SaveToText;
    AssertFalse(ChangeMeasurementInFile(FileName, '2nd key', 1, '', Change, Err));
    AssertTrue('says why', Err <> '');
    AssertTrue(Err, FSet.LoadFromFile(FileName, Err));
    After := FSet.SaveToText;
    AssertEquals('file unchanged', Before, After);
  finally
    DeleteFile(FileName);
  end;
end;

procedure TTestMeasurements.TestChangeMissingFile;
var
  FileName, Err: string;
  Change: TMeasurementChange;
begin
  FileName := ConcatPaths([GetTempDir, 'opensloper-no-such-file.slm']);
  AssertFalse(ChangeMeasurementInFile(FileName, 'waist', 1, '', Change, Err));
  AssertTrue('says why', Err <> '');
  AssertFalse('not created', FileExists(FileName));
end;

procedure TTestMeasurements.TestChangeLeavesNoTempFile;
var
  FileName, Err: string;
  Change: TMeasurementChange;
begin
  FileName := GetTempFileName(GetTempDir, 'osm');
  try
    AssertTrue(Err, FSet.SaveToFile(FileName, Err));
    AssertTrue(Err, ChangeMeasurementInFile(FileName, 'waist', 1, '', Change, Err));
    AssertFalse(FileExists(FileName + '.tmp'));
  finally
    DeleteFile(FileName);
  end;
end;

procedure TTestMeasurements.TestCreateFile;
var
  FileName, Err: string;
begin
  FileName := ConcatPaths([GetTempDir, 'opensloper-new-set.slm']);
  try
    AssertTrue(Err, CreateMeasurementFile(FileName, Err));
    AssertTrue(Err, FSet.LoadFromFile(FileName, Err));
    AssertEquals('empty', 0, FSet.Count);
  finally
    DeleteFile(FileName);
  end;
end;

initialization
  RegisterTest(TTestMeasurements);

end.
