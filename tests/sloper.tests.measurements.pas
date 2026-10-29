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
  fpcunit, testregistry, Sloper.Tests.TestCase, Sloper.Core.Measurements;

type
  TTestMeasurements = class(TOSTestCase)
  private
    FSet: TMeasurementSet;
    procedure AssertLoadFails(const Text, Msg: string);
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestAddAndFind;
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
  end;

implementation

uses
  SysUtils, Sloper.Core.Names;

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

initialization
  RegisterTest(TTestMeasurements);

end.
