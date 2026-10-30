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

unit Sloper.Tests.API;

{$mode ObjFPC}{$H+}

interface

uses
  SysUtils, fpcunit, testregistry, fpjson, Sloper.Tests.TestCase, Sloper.API.Server;

type
  TTestAPI = class(TOSTestCase)
  private
    FServer: TApiServer;
    FFolder, FPatternPath, FSetPath: string;
    FReply: TJSONObject;
    procedure WriteFiles;
    procedure OpenTestPattern;
    procedure Keep(const Reply: string);
    // Sends a request with id 1 and keeps the parsed reply for the test
    procedure Call(const Method: string; const Params: string = '{}');
    function Answer: TJSONObject;
    function ErrorCode: integer;
    function ErrorText: string;
    function ObjectNamed(const AName: string): TJSONObject;
    function FormulaOf(Item: TJSONObject; const FieldName: string): string;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestOpen;
    procedure TestOpenMissingFile;
    procedure TestListObjects;
    procedure TestGetObject;
    procedure TestSetFormula;
    procedure TestSetFormulaRefusedSaysWhere;
    procedure TestSetFormulaOnVariable;
    procedure TestCycleRefused;
    procedure TestRenameKeepsReferences;
    procedure TestRenameRefused;
    procedure TestDeleteRefusedWhileUsed;
    procedure TestDelete;
    procedure TestUndoRedo;
    procedure TestNothingToUndo;
    procedure TestCheckReportsProblems;
    procedure TestEvaluate;
    procedure TestGetMeasurements;
    procedure TestSetMeasurement;
    procedure TestSetMeasurementKeepsDescription;
    procedure TestSave;
    procedure TestSaveNeedsAPath;
    procedure TestBadJSON;
    procedure TestNotARequest;
    procedure TestUnknownMethod;
    procedure TestMissingParam;
    procedure TestParamsMustBeAnObject;
    procedure TestNotificationGetsNoReply;
    procedure TestIdIsEchoed;
    procedure TestReplyIsOneLine;
    procedure TestUnknownTarget;
  end;

implementation

uses
  Sloper.Core.JSON, Sloper.Core.Measurements, Sloper.Core.Pattern, Sloper.Core.PatternFile, Sloper.Core.Draft;

function PathParams(const Path: string): string;
var
  Params: TJSONObject;
begin
  Params := TJSONObject.Create(['path', Path]);
  try
    Result := Params.AsJSON;
  finally
    FreeAndNil(Params);
  end;
end;

procedure TTestAPI.SetUp;
begin
  FServer := TApiServer.Create;
  FReply := nil;
  FFolder := ConcatPaths([GetTempDir, 'opensloper-api-test']);
  ForceDirectories(FFolder);
  FPatternPath := ConcatPaths([FFolder, 'test.sloper']);
  FSetPath := ConcatPaths([FFolder, 'test.slm']);
  WriteFiles;
end;

procedure TTestAPI.TearDown;
begin
  FreeAndNil(FReply);
  FreeAndNil(FServer);
  DeleteFile(FPatternPath);
  DeleteFile(FSetPath);
  DeleteFile(FPatternPath + '2');
  RemoveDir(FFolder);
end;

// A at the origin, B a quarter of the waist plus #ease to the right, and a line
procedure TTestAPI.WriteFiles;
var
  Pattern: TPattern;
  MeasurementSet: TMeasurementSet;
  Err: string;
begin
  MeasurementSet := TMeasurementSet.Create;
  Pattern := TPattern.Create;
  try
    MeasurementSet.Add('waist', 800, 'Round the waist');
    if not MeasurementSet.SaveToFile(FSetPath, Err) then
      Fail(Err);
    Pattern.Measurements := MeasurementSet;
    Pattern.MeasurementFile := ExtractFileName(FSetPath);
    Pattern.AddVariable('ease', '10');
    Pattern.AddFreePoint('A', '0', '0');
    Pattern.AddOffsetPoint('B', Pattern.FindObject('A').Key, omPolar, '@waist / 4 + #ease', '0');
    Pattern.AddLine(Pattern.FindObject('A').Key, Pattern.FindObject('B').Key, erOutline, 'Hem');
    if not SavePatternToFile(Pattern, FPatternPath, Err) then
      Fail(Err);
  finally
    FreeAndNil(Pattern);
    FreeAndNil(MeasurementSet);
  end;
end;

procedure TTestAPI.Keep(const Reply: string);
var
  Err: string;
begin
  FreeAndNil(FReply);
  if not ParseJSONObject(Reply, FReply, Err) then
    Fail(Err + ': ' + Reply);
end;

procedure TTestAPI.Call(const Method, Params: string);
begin
  Keep(FServer.HandleLine('{"jsonrpc": "2.0", "id": 1, "method": "' + Method + '", "params": ' + Params + '}'));
end;

procedure TTestAPI.OpenTestPattern;
begin
  Call('open', PathParams(FPatternPath));
end;

function TTestAPI.Answer: TJSONObject;
begin
  if FReply.Find('result') = nil then
    Fail('Expected a result: ' + FReply.AsJSON);
  Result := TJSONObject(FReply.Find('result'));
end;

function TTestAPI.ErrorCode: integer;
begin
  if FReply.Find('error') = nil then
    Fail('Expected an error: ' + FReply.AsJSON);
  Result := TJSONObject(FReply.Find('error')).Get('code', 0);
end;

function TTestAPI.ErrorText: string;
begin
  Result := TJSONObject(FReply.Find('error')).Get('message', '');
end;

function TTestAPI.ObjectNamed(const AName: string): TJSONObject;
var
  List: TJSONArray;
  Index: integer;
begin
  Call('list_objects');
  List := TJSONArray(Answer.Find('objects'));
  for Index := 0 to List.Count - 1 do
    if TJSONObject(List[Index]).Get('name', '') = AName then
      Exit(TJSONObject(List[Index]));
  Result := nil;
end;

function TTestAPI.FormulaOf(Item: TJSONObject; const FieldName: string): string;
begin
  Result := TJSONObject(Item.Find('formulas')).Get(FieldName, '');
end;

procedure TTestAPI.TestOpen;
begin
  OpenTestPattern;
  AssertEquals('objects', 3, Answer.Get('objects', 0));
  AssertEquals('variables', 1, Answer.Get('variables', 0));
  AssertEquals('measurements found beside it', FSetPath, Answer.Get('measurements', ''));
  AssertFalse('not modified', Answer.Get('modified', True));
end;

procedure TTestAPI.TestOpenMissingFile;
begin
  Call('open', '{"path": "/no/such/file.sloper"}');
  AssertEquals(RpcRefused, ErrorCode);
  AssertTrue('names the file', Pos('file.sloper', ErrorText) > 0);
end;

procedure TTestAPI.TestListObjects;
var
  Point: TJSONObject;
begin
  OpenTestPattern;
  Point := ObjectNamed('B');
  AssertNotNull(Point);
  AssertEquals('type', 'offsetPoint', Point.Get('type', ''));
  AssertEquals('state', 'valid', Point.Get('state', ''));
  AssertNear('x', 210, Point.Get('x', 0.0));
  AssertEquals('formula with names', '@waist / 4 + #ease', FormulaOf(Point, 'length'));
  AssertEquals('variables too', 'ease', TJSONObject(TJSONArray(Answer.Find('variables'))[0]).Get('name', ''));
  AssertNear('line length', 210, ObjectNamed('Hem').Get('length', 0.0));
end;

procedure TTestAPI.TestGetObject;
begin
  OpenTestPattern;
  Call('get_object', '{"name": "B"}');
  AssertEquals('by name', 'B', Answer.Get('name', ''));
  Call('get_object', Format('{"id": %d}', [Answer.Get('id', 0)]));
  AssertEquals('by id', 'B', Answer.Get('name', ''));
  Call('get_object', '{"name": "ease"}');
  AssertEquals('a variable', 'variable', Answer.Get('type', ''));
end;

procedure TTestAPI.TestSetFormula;
begin
  OpenTestPattern;
  Call('set_formula', '{"name": "B", "field": "length", "formula": "@waist / 2"}');
  AssertNear('re-evaluated', 400, Answer.Get('x', 0.0));
  AssertEquals('stored', '@waist / 2', FormulaOf(Answer, 'length'));
  AssertTrue('the pattern changed', FServer.Document.Modified);
end;

procedure TTestAPI.TestSetFormulaRefusedSaysWhere;
var
  Data: TJSONObject;
begin
  OpenTestPattern;
  Call('set_formula', '{"name": "B", "field": "length", "formula": "1 + @chest"}');
  AssertEquals(RpcRefused, ErrorCode);
  Data := TJSONObject(TJSONObject(FReply.Find('error')).Find('data'));
  AssertNotNull('where', Data);
  AssertEquals('field', 'length', Data.Get('field', ''));
  AssertEquals('position', 5, Data.Get('position', 0));
  Call('get_object', '{"name": "B"}');
  AssertEquals('unchanged', '@waist / 4 + #ease', FormulaOf(Answer, 'length'));
  AssertFalse('left no change open', FServer.Document.ChangeOpen);
end;

procedure TTestAPI.TestSetFormulaOnVariable;
begin
  OpenTestPattern;
  Call('set_formula', '{"name": "ease", "field": "formula", "formula": "30"}');
  AssertNear('value', 30, Answer.Get('value', 0.0));
  AssertNear('what reads it follows', 230, ObjectNamed('B').Get('x', 0.0));
end;

procedure TTestAPI.TestCycleRefused;
begin
  OpenTestPattern;
  Call('set_formula', '{"name": "A", "field": "x", "formula": "B.x"}');
  AssertEquals(RpcRefused, ErrorCode);
end;

procedure TTestAPI.TestRenameKeepsReferences;
begin
  OpenTestPattern;
  Call('rename', '{"name": "ease", "newName": "waist_ease"}');
  AssertEquals('waist_ease', Answer.Get('name', ''));
  AssertEquals('formulas follow', '@waist / 4 + #waist_ease', FormulaOf(ObjectNamed('B'), 'length'));
end;

procedure TTestAPI.TestRenameRefused;
begin
  OpenTestPattern;
  Call('rename', '{"name": "A", "newName": "B"}');
  AssertEquals(RpcRefused, ErrorCode);
end;

procedure TTestAPI.TestDeleteRefusedWhileUsed;
begin
  OpenTestPattern;
  Call('delete', '{"name": "A"}');
  AssertEquals(RpcRefused, ErrorCode);
  AssertTrue('says what uses it', Pos('B', ErrorText) > 0);
  AssertNotNull(ObjectNamed('A'));
end;

procedure TTestAPI.TestDelete;
begin
  OpenTestPattern;
  Call('delete', '{"name": "Hem"}');
  AssertEquals(2, Answer.Get('objects', 0));
end;

procedure TTestAPI.TestUndoRedo;
begin
  OpenTestPattern;
  Call('set_formula', '{"name": "A", "field": "x", "formula": "5"}');
  Call('undo');
  AssertNear('undone', 0, ObjectNamed('A').Get('x', 99.0));
  Call('redo');
  AssertNear('redone', 5, ObjectNamed('A').Get('x', 99.0));
end;

procedure TTestAPI.TestNothingToUndo;
begin
  Call('undo');
  AssertEquals(RpcRefused, ErrorCode);
  AssertEquals(rsApiNothingToUndo, ErrorText);
  Call('redo');
  AssertEquals(rsApiNothingToRedo, ErrorText);
end;

procedure TTestAPI.TestCheckReportsProblems;
begin
  OpenTestPattern;
  Call('check');
  AssertEquals('clean', 0, TJSONArray(Answer.Find('problems')).Count);
  AssertNotNull('the full report', Answer.Find('report'));
  Call('set_formula', '{"name": "ease", "field": "formula", "formula": "1 / 0"}');
  Call('check');
  AssertEquals('one problem', 1, TJSONArray(Answer.Find('problems')).Count);
  AssertTrue('what it blocks is counted', Answer.Get('blocked', 0) > 0);
end;

procedure TTestAPI.TestEvaluate;
begin
  OpenTestPattern;
  Call('evaluate');
  AssertEquals(0, TJSONArray(Answer.Find('problems')).Count);
  AssertNull('no report', Answer.Find('report'));
end;

procedure TTestAPI.TestGetMeasurements;
begin
  OpenTestPattern;
  Call('get_measurements');
  AssertEquals('path', FSetPath, Answer.Get('path', ''));
  AssertEquals('waist', TJSONObject(TJSONArray(Answer.Find('measurements'))[0]).Get('key', ''));
end;

procedure TTestAPI.TestSetMeasurement;
begin
  OpenTestPattern;
  Call('set_measurement', '{"key": "waist", "value": 1000}');
  AssertNear('old', 800, Answer.Get('oldValue', 0.0));
  AssertFalse('not added', Answer.Get('added', True));
  AssertNear('pattern follows', 260, ObjectNamed('B').Get('x', 0.0));
  AssertFalse('the pattern itself did not change', FServer.Document.Modified);
  Call('set_measurement', '{"key": "chest", "value": 900}');
  AssertTrue('added', Answer.Get('added', False));
  Call('set_measurement', '{"key": "2 bad", "value": 1}');
  AssertEquals(RpcRefused, ErrorCode);
end;

procedure TTestAPI.TestSetMeasurementKeepsDescription;
begin
  OpenTestPattern;
  Call('set_measurement', '{"key": "waist", "value": 1000}');
  Call('get_measurements');
  AssertEquals('Round the waist', TJSONObject(TJSONArray(Answer.Find('measurements'))[0]).Get('description', ''));
end;

procedure TTestAPI.TestSave;
var
  Copy: TPattern;
  Err: string;
begin
  OpenTestPattern;
  Call('set_formula', '{"name": "A", "field": "x", "formula": "5"}');
  Call('save', PathParams(FPatternPath + '2'));
  AssertFalse('saved', Answer.Get('modified', True));
  Copy := TPattern.Create;
  try
    AssertTrue(Err, LoadPatternFromFile(Copy, FPatternPath + '2', Err));
    AssertEquals('5', Copy.FormulaText(Copy.FindObject('A'), 'x'));
  finally
    FreeAndNil(Copy);
  end;
end;

procedure TTestAPI.TestSaveNeedsAPath;
begin
  Call('save');
  AssertEquals(RpcRefused, ErrorCode);
  AssertEquals(rsApiNoFileName, ErrorText);
end;

procedure TTestAPI.TestBadJSON;
begin
  Keep(FServer.HandleLine('{nope'));
  AssertEquals(RpcParseError, ErrorCode);
  AssertTrue('id is null', FReply.Find('id').JSONType = jtNull);
end;

procedure TTestAPI.TestNotARequest;
begin
  Keep(FServer.HandleLine('{"id": 7}'));
  AssertEquals(RpcInvalidRequest, ErrorCode);
  AssertEquals('id kept', 7, FReply.Get('id', 0));
end;

procedure TTestAPI.TestUnknownMethod;
begin
  Call('fly');
  AssertEquals(RpcMethodNotFound, ErrorCode);
end;

procedure TTestAPI.TestMissingParam;
begin
  Call('open');
  AssertEquals(RpcInvalidParams, ErrorCode);
end;

procedure TTestAPI.TestParamsMustBeAnObject;
begin
  Call('open', '[1]');
  AssertEquals(RpcInvalidParams, ErrorCode);
end;

procedure TTestAPI.TestNotificationGetsNoReply;
begin
  AssertEquals('', FServer.HandleLine('{"jsonrpc": "2.0", "method": "evaluate"}'));
end;

procedure TTestAPI.TestIdIsEchoed;
begin
  Keep(FServer.HandleLine('{"jsonrpc": "2.0", "id": "abc", "method": "evaluate"}'));
  AssertEquals('abc', FReply.Get('id', ''));
  AssertEquals('2.0', FReply.Get('jsonrpc', ''));
end;

procedure TTestAPI.TestReplyIsOneLine;
begin
  OpenTestPattern;
  AssertEquals(0, Pos(#10, FServer.HandleLine('{"jsonrpc": "2.0", "id": 1, "method": "check"}')));
end;

procedure TTestAPI.TestUnknownTarget;
begin
  Call('get_object', '{"id": 999}');
  AssertEquals(RpcRefused, ErrorCode);
  Call('get_object', '{"name": "Nothing"}');
  AssertEquals(RpcRefused, ErrorCode);
  Call('get_object');
  AssertEquals(RpcInvalidParams, ErrorCode);
end;

initialization
  RegisterTest(TTestAPI);

end.
