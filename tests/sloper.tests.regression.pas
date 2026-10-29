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

// Regression patterns. Each tests/patterns/<pattern>.<set>.expected.json is
// the report of <pattern>.sloper evaluated with <set>.slm, as written by
// "opensloper-cli check --json"; every pattern is evaluated again and
// compared with it. See tests/patterns/README.md.
unit Sloper.Tests.Regression;

{$mode ObjFPC}{$H+}

interface

uses
  fpcunit, testregistry, fpjson, Sloper.Tests.TestCase;

type
  TTestRegression = class(TOSTestCase)
  private
    function PatternsDir: string;
    procedure CheckCase(const ExpectedFile: string);
    procedure CompareItems(const Context: string; Expected, Actual: TJSONData);
  published
    procedure TestPatterns;
  end;

implementation

uses
  Classes, SysUtils, Sloper.Core.JSON, Sloper.Core.Measurements, Sloper.Core.Pattern, Sloper.Core.PatternFile,
  Sloper.Core.PatternCheck;

const
  ExpectedSuffix = '.expected.json';
  // Reports are rounded to 1e-6 mm, so allow a little more than that
  ReportTolerance = 1e-5;

function TTestRegression.PatternsDir: string;
begin
  Result := ConcatPaths([ExtractFileDir(ExpandFileName(ParamStr(0))), 'patterns']);
end;

// Same items in the same order, with the same members; numbers within the tolerance
procedure TTestRegression.CompareItems(const Context: string; Expected, Actual: TJSONData);
var
  Index, MemberIndex: integer;
  ExpectedItem, ActualItem: TJSONObject;
  MemberName, ItemContext: string;
  ActualValue: TJSONData;
begin
  AssertTrue(Context + ' is a list', (Expected <> nil) and (Expected.JSONType = jtArray) and
    (Actual <> nil) and (Actual.JSONType = jtArray));
  AssertEquals(Context + ' count', Expected.Count, Actual.Count);
  for Index := 0 to Expected.Count - 1 do
  begin
    ExpectedItem := Expected.Items[Index] as TJSONObject;
    ActualItem := Actual.Items[Index] as TJSONObject;
    ItemContext := Context + ' ' + ExpectedItem.Get('id', '?') + ' (' + ExpectedItem.Get('name', '') + ')';
    AssertEquals(ItemContext + ' member count', ExpectedItem.Count, ActualItem.Count);
    for MemberIndex := 0 to ExpectedItem.Count - 1 do
    begin
      MemberName := ExpectedItem.Names[MemberIndex];
      ActualValue := ActualItem.Find(MemberName);
      AssertNotNull(ItemContext + ' has ' + MemberName, ActualValue);
      if ExpectedItem.Items[MemberIndex].JSONType = jtNumber then
        AssertNear(ItemContext + ' ' + MemberName, ExpectedItem.Items[MemberIndex].AsFloat, ActualValue.AsFloat,
          ReportTolerance)
      else
        AssertEquals(ItemContext + ' ' + MemberName, ExpectedItem.Items[MemberIndex].AsJSON, ActualValue.AsJSON);
    end;
  end;
end;

procedure TTestRegression.CheckCase(const ExpectedFile: string);
var
  CaseName, PatternName, SetName, Text, Err: string;
  Dot: integer;
  Pattern: TPattern;
  Measurements: TMeasurementSet;
  Expected, Actual: TJSONObject;
begin
  CaseName := ExtractFileName(ExpectedFile);
  CaseName := Copy(CaseName, 1, Length(CaseName) - Length(ExpectedSuffix));
  Dot := Pos('.', CaseName);
  AssertTrue(CaseName + ': name is <pattern>.<set>', Dot > 1);
  PatternName := Copy(CaseName, 1, Dot - 1) + '.sloper';
  SetName := Copy(CaseName, Dot + 1, MaxInt) + '.slm';

  Expected := nil;
  Actual := nil;
  Measurements := TMeasurementSet.Create;
  Pattern := TPattern.Create;
  try
    if not LoadPatternFromFile(Pattern, ConcatPaths([PatternsDir, PatternName]), Err) then
      Fail(CaseName + ': ' + Err);
    if not Measurements.LoadFromFile(ConcatPaths([PatternsDir, SetName]), Err) then
      Fail(CaseName + ': ' + Err);
    Pattern.Measurements := Measurements;
    Pattern.Evaluate;
    Actual := PatternReport(Pattern, PatternName, SetName);
    if not ReadTextFile(ExpectedFile, Text, Err) or not ParseJSONObject(Text, Expected, Err) then
      Fail(CaseName + ': ' + Err);
    AssertEquals(CaseName + ' pattern', Expected.Get('pattern', ''), PatternName);
    AssertEquals(CaseName + ' measurements', Expected.Get('measurements', ''), SetName);
    CompareItems(CaseName + ' variable', Expected.Find('variables'), Actual.Find('variables'));
    CompareItems(CaseName + ' object', Expected.Find('objects'), Actual.Find('objects'));
  finally
    FreeAndNil(Expected);
    FreeAndNil(Actual);
    FreeAndNil(Pattern);
    FreeAndNil(Measurements);
  end;
end;

procedure TTestRegression.TestPatterns;
var
  Search: TSearchRec;
  Files: TStringList;
  FileName: string;
begin
  Files := TStringList.Create;
  try
    if FindFirst(ConcatPaths([PatternsDir, '*' + ExpectedSuffix]), faAnyFile, Search) = 0 then
    try
      repeat
        Files.Add(ConcatPaths([PatternsDir, Search.Name]));
      until FindNext(Search) <> 0;
    finally
      FindClose(Search);
    end;
    Files.Sort;
    AssertTrue('regression cases found in ' + PatternsDir, Files.Count > 0);
    for FileName in Files do
      CheckCase(FileName);
  finally
    FreeAndNil(Files);
  end;
end;

initialization
  RegisterTest(TTestRegression);

end.
