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
    procedure AddSquare;
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
    procedure TestRender;
    procedure TestRenderLabelsAndRegion;
    procedure TestRenderFollowsEdits;
    procedure TestRenderRefusals;
    procedure TestRenderWithoutParams;
    procedure TestBuildFromNothing;
    procedure TestEveryPointType;
    procedure TestCurves;
    procedure TestSplitEdge;
    procedure TestCreatePiece;
    procedure TestCreatePieceRefusals;
    procedure TestEdgeAllowance;
    procedure TestGrainlineAndNotches;
    procedure TestCutAndFold;
    procedure TestAddVariable;
    procedure TestAddIsOneUndoStep;
    procedure TestAddRefusals;
    procedure TestRefusedAddLeavesNoChangeOpen;
    procedure TestInputsByIdOrName;
    procedure TestAddedPatternSavesAndReopens;
    procedure TestFailureBuildingAReplyLeaksNothing;
  end;

implementation

uses
  Sloper.Core.JSON, Sloper.Core.Measurements, Sloper.Core.Pattern, Sloper.Core.PatternFile, Sloper.Core.Variables, Sloper.Core.Draft, Sloper.Core.PieceDetect;

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

procedure TTestAPI.TestRender;
var
  Svg: string;
begin
  OpenTestPattern;
  Call('render');
  AssertEquals('svg', Answer.Get('format', ''));
  Svg := Answer.Get('svg', '');
  AssertTrue('an svg', Pos('<svg', Svg) = 1);
  AssertTrue('has the point', Pos('data-name="B"', Svg) > 0);
  AssertTrue('no labels by default', Pos('<text', Svg) = 0);
end;

procedure TTestAPI.TestRenderLabelsAndRegion;
var
  Svg: string;
begin
  OpenTestPattern;
  Call('render', '{"labels": true, "region": {"minX": 0, "minY": -10, "maxX": 50, "maxY": 10}}');
  Svg := Answer.Get('svg', '');
  AssertTrue('labels', Pos('>B</text>', Svg) > 0);
  AssertTrue('region', Pos('viewBox="0 -10 50 20"', Svg) > 0);
end;

procedure TTestAPI.TestRenderFollowsEdits;
begin
  OpenTestPattern;
  Call('set_formula', '{"name": "B", "field": "length", "formula": "300"}');
  Call('render');
  AssertTrue('drawn where it now is', Pos('cx="300"', Answer.Get('svg', '')) > 0);
end;

procedure TTestAPI.TestRenderRefusals;
begin
  Call('render', '{"format": "png"}');
  AssertEquals(RpcRefused, ErrorCode);
  Call('render', '{"region": {"minX": 5, "minY": 0, "maxX": 1, "maxY": 1}}');
  AssertEquals(RpcInvalidParams, ErrorCode);
  Call('render', '{"region": 3}');
  AssertEquals(RpcInvalidParams, ErrorCode);
end;

procedure TTestAPI.TestRenderWithoutParams;
begin
  Keep(FServer.HandleLine('{"jsonrpc": "2.0", "id": 1, "method": "render"}'));
  AssertTrue(Pos('<svg', Answer.Get('svg', '')) = 1);
end;

procedure TTestAPI.TestBuildFromNothing;
begin
  Call('add_point', '{"type": "freePoint", "name": "A", "x": 0, "y": 0}');
  AssertEquals('A', Answer.Get('name', ''));
  Call('add_point', '{"type": "offsetPoint", "name": "B", "base": "A", "length": 100, "angle": 0}');
  AssertNear('placed', 100, Answer.Get('x', 0.0));
  Call('add_edge', '{"type": "line", "start": "A", "end": "B", "role": "outline"}');
  AssertEquals('derived name', 'Line_A_B', Answer.Get('name', ''));
  AssertNear('length', 100, Answer.Get('length', 0.0));
  Call('render');
  AssertTrue('drawn', Pos('Line_A_B', Answer.Get('svg', '')) > 0);
end;

procedure TTestAPI.TestEveryPointType;
begin
  Call('add_point', '{"type": "freePoint", "name": "A", "x": "0", "y": "0"}');
  Call('add_point', '{"type": "offsetPoint", "name": "B", "base": "A", "mode": "cartesian", "dx": 100, "dy": 0}');
  Call('add_point', '{"type": "offsetPoint", "name": "C", "base": "A", "dx": 1, "length": 50, "angle": 90}');
  Call('add_point', '{"type": "freePoint", "name": "D", "x": 50, "y": -20}');
  Call('add_edge', '{"type": "line", "name": "Base", "start": "A", "end": "B"}');
  Call('add_edge', '{"type": "line", "name": "Up", "start": "D", "end": "C"}');
  Call('add_point', '{"type": "alongEdgePoint", "name": "E", "edge": "Base", "from": "end", "mode": "ratio", "value": 0.25}');
  AssertNear('along', 75, Answer.Get('x', 0.0));
  Call('add_point', '{"type": "intersectPoint", "name": "F", "edgeA": "Base", "edgeB": "Up"}');
  AssertEquals('crosses', 'valid', Answer.Get('state', ''));
  Call('add_point', '{"type": "circleEdgePoint", "name": "G", "centre": "A", "radius": 30, "edge": "Base"}');
  AssertNear('compass', 30, Answer.Get('x', 0.0));
  Call('add_point', '{"type": "projectPoint", "name": "H", "point": "D", "edge": "Base"}');
  AssertNear('square onto it', 50, Answer.Get('x', 0.0));
  Call('add_point', '{"type": "projectPoint", "name": "J", "point": "D", "edge": "Base", "direction": "angle", "angle": 45}');
  AssertNear('at an angle', 70, Answer.Get('x', 0.0));
end;

procedure TTestAPI.TestCurves;
begin
  Call('add_point', '{"type": "freePoint", "name": "A", "x": 0, "y": 0}');
  Call('add_point', '{"type": "freePoint", "name": "B", "x": 100, "y": 100}');
  Call('add_point', '{"type": "freePoint", "name": "C", "x": 200, "y": 0}');
  Call('add_edge', '{"type": "curve", "name": "Arch", "start": "A", "end": "C", "angle1": 90, "length1": 50, "angle2": 90, "length2": 50, "role": "outline"}');
  AssertEquals('curve', Answer.Get('type', ''));
  AssertEquals('valid', Answer.Get('state', ''));
  Call('add_edge', '{"type": "curvePath", "start": "A", "nodes": [' +
    '{"point": "A", "angle": 90, "lengthOut": 30},' +
    '{"point": "B", "angle": 0, "lengthIn": 50, "lengthOut": 40},' +
    '{"point": "C", "angle": 270, "lengthIn": 20}]}');
  AssertEquals('curvePath', Answer.Get('type', ''));
  AssertEquals('Path_A_C', Answer.Get('name', ''));
  AssertEquals('valid', Answer.Get('state', ''));
end;

procedure TTestAPI.AddSquare;
begin
  Call('add_point', '{"type": "freePoint", "name": "A", "x": 0, "y": 0}');
  Call('add_point', '{"type": "freePoint", "name": "B", "x": 100, "y": 0}');
  Call('add_point', '{"type": "freePoint", "name": "C", "x": 100, "y": 100}');
  Call('add_point', '{"type": "freePoint", "name": "D", "x": 0, "y": 100}');
  Call('add_edge', '{"type": "line", "start": "A", "end": "B", "role": "outline"}');
  Call('add_edge', '{"type": "line", "start": "B", "end": "C", "role": "outline"}');
  Call('add_edge', '{"type": "line", "start": "C", "end": "D", "role": "outline"}');
  Call('add_edge', '{"type": "line", "start": "D", "end": "A", "role": "outline"}');
end;

procedure TTestAPI.TestCreatePiece;
begin
  AddSquare;
  Call('create_piece', '{"x": 50, "y": 50, "name": "Front", "allowance": 15}');
  AssertEquals('Front', Answer.Get('name', ''));
  AssertEquals('piece', Answer.Get('type', ''));
  AssertEquals('valid', Answer.Get('state', ''));
  AssertNear('area', 10000, Answer.Get('area', 0.0));
  AssertNear('perimeter', 400, Answer.Get('perimeter', 0.0));
  AssertEquals('path', 4, Answer.Arrays['path'].Count);
  AssertEquals('15', FormulaOf(Answer, 'allowance'));
  Call('undo', '{}');
  Call('list_objects', '{}');
  AssertNull('one undo step', ObjectNamed('Front'));
end;

procedure TTestAPI.TestCreatePieceRefusals;
begin
  AddSquare;
  Call('create_piece', '{"x": 500, "y": 50}');
  AssertEquals('refused', RpcRefused, ErrorCode);
  AssertEquals(rsDetectNoRegion, ErrorText);
  Call('create_piece', '{"x": 50, "y": 50, "name": "Front"}');
  Call('create_piece', '{"x": 50, "y": 50}');
  AssertEquals('one piece per region', RpcRefused, ErrorCode);
  Call('undo');
  Call('create_piece', '{"y": 50}');
  AssertEquals('no x', RpcInvalidParams, ErrorCode);
  Call('create_piece', '{"x": 50, "y": 50, "allowance": "1 +"}');
  AssertEquals('bad formula', RpcRefused, ErrorCode);
end;

procedure TTestAPI.TestEdgeAllowance;
begin
  AddSquare;
  Call('create_piece', '{"x": 50, "y": 50, "name": "Front"}');
  AssertEquals('10', FormulaOf(Answer, 'allowance'));
  Call('set_edge_allowance', '{"name": "Front", "edge": "Line_A_B", "allowance": 30}');
  AssertEquals('state', 'valid', Answer.Get('state', ''));
  AssertEquals('allowance, grainline, edge', 3, Answer.Objects['formulas'].Count);
  Call('set_edge_allowance', '{"name": "Front", "edge": "Line_A_B"}');
  AssertEquals('allowance and grainline', 2, Answer.Objects['formulas'].Count);
  Call('set_edge_allowance', '{"name": "A", "edge": "Line_A_B"}');
  AssertEquals('not a piece', RpcRefused, ErrorCode);
end;

procedure TTestAPI.TestGrainlineAndNotches;
begin
  AddSquare;
  Call('create_piece', '{"x": 50, "y": 50, "name": "Front"}');
  AssertEquals('90', FormulaOf(Answer, 'grainline.angle'));
  Call('set_grainline', '{"name": "Front", "angle": 45}');
  AssertEquals('45', FormulaOf(Answer, 'grainline.angle'));
  Call('set_grainline', '{"name": "Front", "start": "A", "end": "C"}');
  AssertEquals('between points', 'valid', Answer.Get('state', ''));
  AssertEquals('field gone', 1, Answer.Objects['formulas'].Count);
  Call('set_grainline', '{"name": "Front"}');
  AssertEquals('nothing given', RpcInvalidParams, ErrorCode);
  Call('set_grainline', '{"name": "Front", "none": true}');
  AssertEquals('cleared', 'valid', Answer.Get('state', ''));

  Call('add_notch', '{"name": "Front", "edge": "Line_A_B", "position": 30}');
  AssertEquals('notches', 1, Answer.Get('notches', 0));
  AssertEquals('30', FormulaOf(Answer, 'notch1.position'));
  Call('add_notch', '{"name": "Front", "point": "A"}');
  AssertEquals('notches', 2, Answer.Get('notches', 0));
  Call('add_notch', '{"name": "Front"}');
  AssertEquals('nothing given', RpcInvalidParams, ErrorCode);
  Call('remove_notch', '{"name": "Front", "notch": 1}');
  AssertEquals('notches', 1, Answer.Get('notches', 0));
  Call('remove_notch', '{"name": "Front", "notch": 9}');
  AssertEquals('no such notch', RpcRefused, ErrorCode);
  Call('undo');
  Call('get_object', '{"name": "Front"}');
  AssertEquals('undone', 2, Answer.Get('notches', 0));
end;

procedure TTestAPI.TestCutAndFold;
begin
  AddSquare;
  Call('create_piece', '{"x": 50, "y": 50, "name": "Front"}');
  AssertEquals('default', 1, Answer.Get('cutCount', 0));
  Call('set_cut', '{"name": "Front", "count": 2, "mirrored": true}');
  AssertEquals(2, Answer.Get('cutCount', 0));
  AssertTrue(Answer.Get('mirrored', False));
  Call('set_cut', '{"name": "Front", "count": 3}');
  AssertTrue('keeps mirrored', Answer.Get('mirrored', False));
  Call('set_cut', '{"name": "Front", "count": 0}');
  AssertEquals('refused', RpcRefused, ErrorCode);
  Call('set_fold', '{"name": "Front", "edge": "Line_D_A"}');
  AssertTrue(Answer.Get('onFold', False));
  Call('set_fold', '{"name": "Front"}');
  AssertEquals('nothing given', RpcInvalidParams, ErrorCode);
  Call('set_fold', '{"name": "Front", "none": true}');
  AssertFalse(Answer.Get('onFold', True));
end;

procedure TTestAPI.TestSplitEdge;
var
  Parts: TJSONArray;
begin
  Call('add_point', '{"type": "freePoint", "name": "A", "x": 0, "y": 0}');
  Call('add_point', '{"type": "freePoint", "name": "B", "x": 100, "y": 0}');
  Call('add_edge', '{"type": "line", "start": "A", "end": "B"}');
  Call('add_point', '{"type": "alongEdgePoint", "name": "M", "edge": "Line_A_B", "value": 30}');
  Call('split_edge', '{"edge": "Line_A_B", "point": "M"}');
  Parts := TJSONArray(FReply.Find('result'));
  AssertEquals(2, Parts.Count);
  AssertNear('first', 30, TJSONObject(Parts[0]).Get('length', 0.0));
  AssertNear('second', 70, TJSONObject(Parts[1]).Get('length', 0.0));
end;

procedure TTestAPI.TestAddVariable;
begin
  Call('add_variable', '{"name": "ease", "formula": "5 * 2", "description": "Some ease"}');
  AssertNear('value', 10, Answer.Get('value', 0.0));
  Call('add_point', '{"type": "freePoint", "name": "A", "x": "#ease", "y": 0}');
  AssertNear('used', 10, Answer.Get('x', 0.0));
end;

procedure TTestAPI.TestAddIsOneUndoStep;
begin
  Call('add_point', '{"type": "freePoint", "name": "A", "x": 0, "y": 0}');
  Call('add_point', '{"type": "freePoint", "name": "B", "x": 1, "y": 0}');
  Call('undo');
  AssertNull('B went', ObjectNamed('B'));
  AssertNotNull('A stayed', ObjectNamed('A'));
  Call('redo');
  AssertNotNull('B back', ObjectNamed('B'));
end;

procedure TTestAPI.TestAddRefusals;
var
  Data: TJSONObject;
begin
  Call('add_point', '{"type": "wobble"}');
  AssertEquals('unknown type', RpcInvalidParams, ErrorCode);
  AssertTrue('lists the choices', Pos('freePoint', ErrorText) > 0);
  Call('add_point', '{"type": "freePoint", "x": 0}');
  AssertEquals('missing field', RpcInvalidParams, ErrorCode);
  Call('add_point', '{"type": "offsetPoint", "base": "Nothing", "length": 1, "angle": 0}');
  AssertEquals('unknown input', RpcRefused, ErrorCode);
  Call('add_point', '{"type": "offsetPoint", "base": 99, "length": 1, "angle": 0}');
  AssertEquals('unknown ID', RpcRefused, ErrorCode);
  Call('add_point', '{"type": "freePoint", "name": "A", "x": 0, "y": 0}');
  Call('add_point', '{"type": "freePoint", "name": "a", "x": 0, "y": 0}');
  AssertEquals('name taken', RpcRefused, ErrorCode);
  Call('add_point', '{"type": "freePoint", "x": "1 +", "y": 0}');
  AssertEquals('bad formula', RpcRefused, ErrorCode);
  Data := TJSONObject(TJSONObject(FReply.Find('error')).Find('data'));
  AssertEquals('says which field', 'x', Data.Get('field', ''));
  Call('add_point', '{"type": "offsetPoint", "base": "A", "mode": "sideways", "length": 1, "angle": 0}');
  AssertEquals('bad choice', RpcInvalidParams, ErrorCode);
  Call('add_edge', '{"type": "line", "start": "A", "end": "A"}');
  AssertEquals('an edge to itself is a state, not a refusal', 'invalid', Answer.Get('state', ''));
  Call('delete', '{"name": "Line_A_A"}');
  Call('add_edge', '{"type": "curvePath"}');
  AssertEquals('no nodes', RpcInvalidParams, ErrorCode);
  Call('add_variable', '{"name": "2 bad", "formula": "1"}');
  AssertEquals('bad name', RpcRefused, ErrorCode);
end;

procedure TTestAPI.TestRefusedAddLeavesNoChangeOpen;
begin
  Call('add_point', '{"type": "freePoint", "x": "1 +", "y": 0}');
  AssertFalse(FServer.Document.ChangeOpen);
  Call('add_point', '{"type": "freePoint", "name": "A", "x": 0, "y": 0}');
  AssertEquals('the next call still works', 'A', Answer.Get('name', ''));
  Call('undo');
  Call('undo');
  AssertEquals('a refused add is not a step', RpcRefused, ErrorCode);
end;

procedure TTestAPI.TestInputsByIdOrName;
var
  Id: integer;
begin
  Call('add_point', '{"type": "freePoint", "name": "A", "x": 5, "y": 0}');
  Id := Answer.Get('id', 0);
  Call('add_point', Format('{"type": "offsetPoint", "name": "B", "base": %d, "length": 10, "angle": 0}', [Id]));
  AssertNear('by ID', 15, Answer.Get('x', 0.0));
  Call('add_point', '{"type": "offsetPoint", "name": "C", "base": "a", "length": 20, "angle": 0}');
  AssertNear('by name, ignoring case', 25, Answer.Get('x', 0.0));
end;

procedure TTestAPI.TestAddedPatternSavesAndReopens;
begin
  Call('add_point', '{"type": "freePoint", "name": "A", "x": 5, "y": 0}');
  Call('add_point', '{"type": "offsetPoint", "name": "B", "base": "A", "length": 10, "angle": 0}');
  Call('save', PathParams(FPatternPath + '2'));
  Call('open', PathParams(FPatternPath + '2'));
  AssertEquals(2, Answer.Get('objects', 0));
  AssertNear('evaluates after reopening', 15, ObjectNamed('B').Get('x', 0.0));
end;

// A key that is not a number makes the ID conversion raise partway through
// building each reply. heaptrc fails the run if anything built so far leaks.
procedure TTestAPI.TestFailureBuildingAReplyLeaksNothing;
begin
  OpenTestPattern;
  FServer.Document.Pattern.InsertVariable(TVariable.Create('bad'));
  Call('list_objects');
  AssertEquals('list', RpcInternalError, ErrorCode);
  Call('get_object', '{"name": "ease"}');
  AssertEquals('other objects still work', 'ease', Answer.Get('name', ''));
  Call('check');
  AssertEquals('check', RpcInternalError, ErrorCode);
  Call('save');
  AssertEquals('save', RpcInternalError, ErrorCode);
  AssertFalse('no change left open', FServer.Document.ChangeOpen);
end;

initialization
  RegisterTest(TTestAPI);

end.
