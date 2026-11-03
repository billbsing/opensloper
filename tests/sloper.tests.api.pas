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
    // Replaces the set with a size table where waist has no value for M
    procedure WriteTable;
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
    procedure TestCircleArcAndCircleCircle;
    procedure TestRectangleCornerAndOffset;
    procedure TestMarkings;
    procedure TestFabricMethods;
    procedure TestFabricRefusals;
    procedure TestPieceFabricAndFill;
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
    procedure TestSizesInGetMeasurements;
    procedure TestOpenWithASize;
    procedure TestSetMeasurementInASize;
    procedure TestUnknownSizeRefused;
    procedure TestMissingMeasurements;
    procedure TestAddBetweenPoint;
    procedure TestArrangeAligns;
    procedure TestArrangeLeavesFormulasUnlessTold;
    procedure TestArrangeRefused;
    procedure TestAddRepeat;
    procedure TestRepeatPointAsAnInput;
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
    procedure TestSeams;
    procedure TestTransforms;
    procedure TestNoDraftsOrLayers;
    procedure TestExport;
    procedure TestSplitEdge;
    procedure TestCreatePiece;
    procedure TestCreatePieceRefusals;
    procedure TestEdgeAllowance;
    procedure TestGrainlineAndNotches;
    procedure TestCutAndFold;
    procedure TestConvertEdge;
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
  Sloper.Output.Layout,
  Sloper.Core.Arrange, Sloper.Core.JSON, Sloper.Core.Measurements, Sloper.Core.Pattern, Sloper.Core.PatternFile, Sloper.Core.Variables,
  Sloper.Core.Draft, Sloper.Core.PieceDetect;

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

function AsJSONString(const Text: string): string;
var
  Value: TJSONString;
begin
  Value := TJSONString.Create(Text);
  try
    Result := Value.AsJSON;
  finally
    FreeAndNil(Value);
  end;
end;

procedure WriteLayoutFor(const PatternFile, LayoutFile: string);
var
  Layout: TLayout;
  Reason: string;
begin
  Layout := TLayout.Create;
  try
    Layout.FileName := LayoutFile;
    Layout.AddSource(ExtractFileName(PatternFile), '', '');
    Layout.LoadSources;
    Layout.PlaceNewPieces;
    if not Layout.SaveToFile(LayoutFile, Reason) then
      raise Exception.Create(Reason);
  finally
    FreeAndNil(Layout);
  end;
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

procedure TTestAPI.TestMarkings;
begin
  AddSquare;
  Call('create_piece', '{"x": 50, "y": 50, "name": "Flap"}');
  Call('add_point', '{"type": "freePoint", "name": "H", "x": 50, "y": 50}');
  Call('add_marking', '{"name": "Flap", "kind": "hole", "point": "H", "diameter": 4}');
  AssertEquals(1, Answer.Get('markings', 0));
  Call('add_point', '{"type": "freePoint", "name": "P", "x": 10, "y": 80}');
  Call('add_point', '{"type": "freePoint", "name": "Q", "x": 90, "y": 80}');
  Call('add_edge', '{"type": "line", "start": "P", "end": "Q", "name": "Stitch"}');
  Call('add_marking', '{"name": "Flap", "kind": "stitch", "edge": "Stitch", "spacing": 4, "size": 1}');
  AssertEquals(21, Answer.Get('holes', 0));
  Call('remove_marking', '{"name": "Flap", "marking": 1}');
  AssertEquals(1, Answer.Get('markings', 0));
  Call('remove_marking', '{"name": "Flap", "marking": 9}');
  AssertEquals(Format(rsPatternNoMarking, [9]), ErrorText);
end;

procedure TTestAPI.TestRectangleCornerAndOffset;
var
  Edges: TJSONArray;
begin
  Call('add_point', '{"type": "freePoint", "name": "O", "x": 0, "y": 0}');
  Call('add_rectangle', '{"corner": "O", "width": 200, "height": 100, "role": "outline"}');
  Edges := TJSONArray(FReply.Find('result'));
  AssertEquals(4, Edges.Count);
  Call('round_corner', Format('{"edgeA": "%s", "edgeB": "%s", "radius": 20}', [Edges.Objects[0].Get('name', ''), Edges.Objects[1].Get('name', '')]));
  AssertEquals('valid', Answer.Get('state', ''));
  Call('add_edge', '{"type": "offsetEdge", "edge": "Line_B_O", "distance": 5, "side": "right", "role": "construction"}');
  AssertEquals('Offset_B_O', Answer.Get('name', ''));
  Call('create_piece', '{"x": 100, "y": 50, "name": "Flap"}');
  AssertEquals('valid', Answer.Get('state', ''));
  Call('add_fabric', '{"name": "Leather"}');
  Call('set_fabric', '{"fabric": "Leather", "allowance": 0}');
  AssertEquals(0, TJSONArray(Answer.Find('fabrics')).Objects[1].Get('allowance', -1.0), 1e-9);
end;

procedure TTestAPI.TestCircleArcAndCircleCircle;
begin
  Call('add_point', '{"type": "freePoint", "name": "O", "x": 0, "y": 0}');
  Call('add_point', '{"type": "freePoint", "name": "P", "x": 60, "y": 0}');
  Call('add_edge', '{"type": "circle", "centre": "O", "radius": 50, "role": "outline"}');
  AssertEquals('Circle_O', Answer.Get('name', ''));
  Call('add_edge', '{"type": "arc", "centre": "O", "radius": 30, "angle1": 0, "angle2": 90, "name": "Flap"}');
  AssertEquals('Flap', Answer.Get('name', ''));
  Call('add_point', '{"type": "circleCirclePoint", "name": "C", "centreA": "O", "radiusA": 50, "centreB": "P", "radiusB": 50, "pick": 1}');
  Call('get_object', '{"name": "C"}');
  AssertEquals(30, Answer.Get('x', 0.0), 1e-6);
  AssertEquals(40, Answer.Get('y', 0.0), 1e-6);
  Call('create_piece', '{"x": -40, "y": 0, "name": "Base"}');
  AssertEquals('valid', Answer.Get('state', ''));
end;

procedure TTestAPI.TestFabricMethods;
var
  List: TJSONArray;
begin
  OpenTestPattern;
  Call('list_fabrics');
  List := TJSONArray(Answer.Find('fabrics'));
  AssertEquals(1, List.Count);
  AssertEquals('Main', List.Objects[0].Get('name', ''));
  AssertEquals('no ID yet', 0, List.Objects[0].Get('id', -1));
  Call('add_fabric', '{"name": "Lining", "color": "#C9A227", "fill": "hatch"}');
  List := TJSONArray(Answer.Find('fabrics'));
  AssertEquals(2, List.Count);
  AssertEquals('hatch', List.Objects[1].Get('fill', ''));
  Call('rename_fabric', '{"fabric": "Lining", "name": "Silk"}');
  Call('set_fabric', '{"fabric": "Silk", "color": "#112233", "fill": "tint"}');
  List := TJSONArray(Answer.Find('fabrics'));
  AssertEquals('Silk', List.Objects[1].Get('name', ''));
  AssertEquals('#112233', List.Objects[1].Get('color', ''));
  AssertEquals('tint', List.Objects[1].Get('fill', ''));
  Call('delete_fabric', '{"fabric": "Silk"}');
  AssertEquals(1, TJSONArray(Answer.Find('fabrics')).Count);
  Call('undo');
  Call('list_fabrics');
  AssertEquals('undo brings it back', 2, TJSONArray(Answer.Find('fabrics')).Count);
end;

procedure TTestAPI.TestFabricRefusals;
begin
  OpenTestPattern;
  Call('delete_fabric', '{"fabric": "Main"}');
  AssertEquals(rsPatternLastFabric, ErrorText);
  Call('add_fabric', '{"name": "Main"}');
  AssertEquals(Format(rsPatternFabricTaken, ['Main']), ErrorText);
  Call('add_fabric', '{"color": "blue"}');
  AssertEquals(Format(rsPatternFabricBadColor, ['blue']), ErrorText);
  Call('rename_fabric', '{"fabric": "Nothing", "name": "X"}');
  AssertEquals(Format(rsApiNoFabric, ['Nothing']), ErrorText);
end;

procedure TTestAPI.TestPieceFabricAndFill;
begin
  AddSquare;
  Call('create_piece', '{"x": 50, "y": 50, "name": "Front"}');
  AssertEquals('Main', Answer.Get('fabric', ''));
  Call('add_fabric', '{"name": "Lining"}');
  Call('set_piece_fabric', '{"name": "Front", "fabric": "Lining"}');
  AssertEquals('Lining', Answer.Get('fabric', ''));
  Call('set_piece_fill', '{"name": "Front", "color": "#123456", "style": "hatch"}');
  AssertEquals('#123456', Answer.Get('fillColor', ''));
  AssertEquals('hatch', Answer.Get('fillStyle', ''));
  Call('list_fabrics');
  AssertTrue(Pos('Lining: Front', Answer.Get('cutList', '')) > 0);
  Call('delete_fabric', '{"fabric": "Lining"}');
  AssertEquals(Format(rsPatternFabricInUse, ['Lining', 'Front']), ErrorText);
  Call('set_piece_fabric', '{"name": "Front", "none": true}');
  AssertEquals('none', '', Answer.Get('fabric', ''));
  Call('set_piece_fabric', '{"name": "Front"}');
  AssertEquals(rsApiFabricOrNone, ErrorText);
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

procedure TTestAPI.WriteTable;
var
  Table: TMeasurementSet;
  Err: string;
begin
  Table := TMeasurementSet.Create;
  try
    AssertTrue(Err, Table.LoadFromText('{"format": "measurements", "version": 1, "sizes": ["S", "M"], ' +
      '"measurements": [{"key": "waist", "values": [700, null]}]}', Err));
    AssertTrue(Err, Table.SaveToFile(FSetPath, Err));
  finally
    FreeAndNil(Table);
  end;
end;

procedure TTestAPI.TestSizesInGetMeasurements;
begin
  WriteTable;
  OpenTestPattern;
  Call('get_measurements');
  AssertEquals('the first until another is chosen', 'S', Answer.Get('size', ''));
  AssertEquals(2, TJSONArray(Answer.Find('sizes')).Count);
end;

procedure TTestAPI.TestOpenWithASize;
begin
  WriteTable;
  Call('open', Format('{"path": "%s", "size": "M"}', [FPatternPath]));
  Call('get_measurements');
  AssertEquals('M', Answer.Get('size', ''));
  AssertTrue('no value there', TJSONObject(TJSONArray(Answer.Find('measurements'))[0]).Find('value').IsNull);
end;

procedure TTestAPI.TestSetMeasurementInASize;
begin
  WriteTable;
  OpenTestPattern;
  Call('set_measurement', '{"key": "waist", "value": 800, "size": "M"}');
  Call('get_measurements');
  AssertEquals('M', Answer.Get('size', ''));
  AssertNear('that size', 800, TJSONObject(TJSONArray(Answer.Find('measurements'))[0]).Get('value', 0.0));
end;

procedure TTestAPI.TestUnknownSizeRefused;
begin
  WriteTable;
  OpenTestPattern;
  Call('set_measurement', '{"key": "waist", "value": 800, "size": "XL"}');
  AssertEquals(RpcRefused, ErrorCode);
  AssertEquals(Format(rsMeasurementUnknownSize, ['XL']), ErrorText);
end;

procedure TTestAPI.TestAddBetweenPoint;
begin
  OpenTestPattern;
  Call('add_point', '{"type": "freePoint", "name": "P", "x": "0", "y": "0"}');
  Call('add_point', '{"type": "freePoint", "name": "Q", "x": "100", "y": "0"}');
  Call('add_point', '{"type": "betweenPoint", "name": "R", "a": "P", "b": "Q", "mode": "ratio", "value": "0.25"}');
  AssertNear('x', 25, ObjectNamed('R').Get('x', 0.0));
end;

procedure TTestAPI.TestArrangeAligns;
begin
  OpenTestPattern;
  Call('add_point', '{"type": "freePoint", "name": "P", "x": "70", "y": "0"}');
  Call('add_point', '{"type": "freePoint", "name": "Q", "x": "10", "y": "5"}');
  Call('arrange', '{"action": "alignVertical", "points": ["P", "Q"], "reference": "P"}');
  AssertEquals('Q', TJSONArray(Answer.Find('changed')).Strings[0]);
  AssertNear('x', 70, ObjectNamed('Q').Get('x', 0.0));
  AssertTrue(FServer.Document.CanUndo);
end;

procedure TTestAPI.TestArrangeLeavesFormulasUnlessTold;
begin
  OpenTestPattern;
  Call('add_point', '{"type": "freePoint", "name": "P", "x": "70", "y": "0"}');
  Call('add_point', '{"type": "freePoint", "name": "Q", "x": "10 + 5", "y": "5"}');
  Call('arrange', '{"action": "alignVertical", "points": ["P", "Q"], "reference": "P"}');
  AssertEquals('Q', TJSONArray(Answer.Find('asked')).Strings[0]);
  AssertNear('left', 15, ObjectNamed('Q').Get('x', 0.0));
  Call('arrange', '{"action": "alignVertical", "points": ["P", "Q"], "reference": "P", "replace": ["Q"]}');
  AssertNear('replaced', 70, ObjectNamed('Q').Get('x', 0.0));
end;

procedure TTestAPI.TestAddRepeat;
begin
  OpenTestPattern;
  Call('add_point', '{"type": "freePoint", "name": "P", "x": "0", "y": "0"}');
  Call('add_point', '{"type": "freePoint", "name": "Q", "x": "300", "y": "0"}');
  Call('add_repeat', '{"name": "Btn", "a": "P", "b": "Q", "count": "4", "ends": "include"}');
  AssertEquals('Btn', Answer.Get('name', ''));
  Call('get_object', '{"name": "Btn[3]"}');
  AssertNear('x', 200, Answer.Get('x', 0.0));
  AssertTrue(FServer.Document.CanUndo);
end;

procedure TTestAPI.TestRepeatPointAsAnInput;
begin
  OpenTestPattern;
  Call('add_point', '{"type": "freePoint", "name": "P", "x": "0", "y": "0"}');
  Call('add_point', '{"type": "freePoint", "name": "Q", "x": "300", "y": "0"}');
  Call('add_repeat', '{"name": "Btn", "a": "P", "b": "Q", "count": "4", "ends": "include"}');
  Call('add_point', '{"type": "betweenPoint", "name": "R", "a": "Btn[2]", "b": "Q", "mode": "ratio", "value": "0.5"}');
  AssertNear('x', 200, ObjectNamed('R').Get('x', 0.0));
end;

procedure TTestAPI.TestArrangeRefused;
begin
  OpenTestPattern;
  Call('arrange', '{"action": "distribute", "points": ["A"]}');
  AssertEquals(RpcRefused, ErrorCode);
  AssertEquals(rsArrangeTooFewToDistribute, ErrorText);
end;

procedure TTestAPI.TestMissingMeasurements;
var
  Item: TJSONObject;
begin
  OpenTestPattern;
  Call('missing_measurements');
  AssertEquals('all there', 0, TJSONArray(Answer.Find('missing')).Count);
  WriteTable;
  Call('open', Format('{"path": "%s", "size": "M"}', [FPatternPath]));
  Call('missing_measurements');
  AssertEquals(1, TJSONArray(Answer.Find('missing')).Count);
  Item := TJSONObject(TJSONArray(Answer.Find('missing'))[0]);
  AssertEquals('waist', Item.Get('key', ''));
  AssertEquals('M', TJSONArray(Item.Find('sizes')).Strings[0]);
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

// The piece keeps its edge, now a curve, and undo brings the line back
procedure TTestAPI.TestConvertEdge;
begin
  AddSquare;
  Call('create_piece', '{"x": 50, "y": 50, "name": "Front"}');
  Call('convert_edge', '{"name": "Line_C_D", "to": "curve"}');
  AssertEquals('curve', Answer.Get('type', ''));
  AssertEquals('named for its type', 'Curve_C_D', Answer.Get('name', ''));
  Call('get_object', '{"name": "Front"}');
  AssertEquals('the piece is fine', 'valid', Answer.Get('state', ''));
  Call('convert_edge', '{"name": "Curve_C_D", "to": "curve"}');
  AssertEquals('already one', RpcRefused, ErrorCode);
  Call('convert_edge', '{"name": "Curve_C_D", "to": "spiral"}');
  AssertEquals('no such type', RpcInvalidParams, ErrorCode);
  Call('convert_edge', '{"name": "Front", "to": "line"}');
  AssertEquals('not an edge', RpcRefused, ErrorCode);
  Call('undo');
  Call('get_object', '{"name": "Line_C_D"}');
  AssertEquals('back to a line', 'line', Answer.Get('type', ''));
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

procedure TTestAPI.TestTransforms;
begin
  Call('add_point', '{"type": "freePoint", "name": "A", "x": 10, "y": 0}');
  Call('add_point', '{"type": "freePoint", "name": "P", "x": 0, "y": 0}');
  Call('add_point', '{"type": "freePoint", "name": "Q", "x": 0, "y": 50}');
  Call('add_transform', '{"type": "rotate", "sources": ["A"], "pivot": "P", "angle": 90}');
  AssertEquals('rotate', 'rotate', Answer.Get('type', ''));
  AssertEquals('angle', '90', FormulaOf(Answer, 'angle'));
  Call('get_object', '{"name": "A_r1"}');
  AssertEquals('copy', 'pointCopy', Answer.Get('type', ''));
  AssertEquals('x', 0, Answer.Get('x', 99.0), 0.001);
  AssertEquals('y', 10, Answer.Get('y', 99.0), 0.001);
  Call('add_transform', '{"type": "mirror", "sources": ["A"], "axis": {"a": "P", "b": "Q"}}');
  AssertEquals('mirror', 'mirror', Answer.Get('type', ''));
  Call('get_object', '{"name": "A_m1"}');
  AssertEquals('across', -10, Answer.Get('x', 99.0), 0.001);
  Call('add_transform', '{"type": "move", "sources": ["A"], "dx": 5, "dy": 6}');
  Call('get_object', '{"name": "A_t1"}');
  AssertEquals('moved', 15, Answer.Get('x', 99.0), 0.001);
  Call('add_transform', '{"type": "mirror", "sources": ["A"]}');
  AssertEquals('no axis', RpcInvalidParams, ErrorCode);
  Call('add_transform', '{"type": "turn", "sources": ["A"]}');
  AssertEquals('no such type', RpcInvalidParams, ErrorCode);
  Call('add_transform', '{"type": "move", "sources": []}');
  AssertEquals('nothing to copy', RpcRefused, ErrorCode);
  Call('delete', '{"name": "A_r1"}');
  AssertEquals('copy alone', RpcRefused, ErrorCode);
  Call('delete', '{"name": "Rotate"}');
  Call('get_object', '{"name": "A_r1"}');
  AssertEquals('gone with it', RpcRefused, ErrorCode);
  Call('undo');
  Call('get_object', '{"name": "A_r1"}');
  AssertEquals('back', 'pointCopy', Answer.Get('type', ''));
end;

// A pattern is one canvas: the draft and layer methods have gone
procedure TTestAPI.TestNoDraftsOrLayers;
begin
  Call('list_drafts');
  AssertEquals('no drafts', RpcMethodNotFound, ErrorCode);
  Call('add_layer', '{"name": "Dart"}');
  AssertEquals('no layers', RpcMethodNotFound, ErrorCode);
end;

procedure TTestAPI.TestExport;
var
  Pattern, Layout, Target: string;
begin
  AddSquare;
  Call('create_piece', '{"name": "Front", "x": 50, "y": 50}');
  Pattern := GetTempFileName(GetTempDir, 'sloper') + '.sloper';
  Layout := ChangeFileExt(Pattern, '.slayout');
  Target := ChangeFileExt(Pattern, '.dxf');
  try
    Call('save', Format('{"path": %s}', [AsJSONString(Pattern)]));
    Answer;
    AssertEquals('layout refused', True, FileExists(Pattern));
    Call('export', Format('{"layout": %s, "path": %s}', [AsJSONString(Layout), AsJSONString(Target)]));
    AssertEquals('no layout yet', RpcRefused, ErrorCode);
    Call('export', Format('{"layout": %s, "path": "a.png"}', [AsJSONString(Layout)]));
    AssertEquals('unknown format', RpcInvalidParams, ErrorCode);
    WriteLayoutFor(Pattern, Layout);
    Call('export', Format('{"layout": %s, "path": %s}', [AsJSONString(Layout), AsJSONString(Target)]));
    AssertEquals('path', Target, Answer.Get('path', ''));
    AssertTrue('written', FileExists(Target));
  finally
    DeleteFile(Pattern);
    DeleteFile(Layout);
    DeleteFile(Target);
  end;
end;

procedure TTestAPI.TestSeams;
begin
  AddSquare;
  Call('create_piece', '{"name": "Front", "x": 50, "y": 50}');
  Call('add_seam', '{"sideA": [{"piece": "Front", "edge": "Line_A_B"}], "sideB": [{"piece": "Front", "edge": "Line_C_D"}], "name": "Hem", "ease": 5}');
  AssertEquals('type', 'seam', Answer.Get('type', ''));
  AssertEquals('lengths', Answer.Get('lengthA', 0.0), Answer.Get('lengthB', -1.0), 0.001);
  AssertTrue('5 mm of ease is out of tolerance', Answer.Get('outOfTolerance', False));
  AssertEquals('ease formula', '5', FormulaOf(Answer, 'ease'));
  Call('flip_seam', '{"name": "Hem"}');
  AssertTrue('flipped', Answer.Get('reversed', False));
  Call('undo');
  Call('get_object', '{"name": "Hem"}');
  AssertFalse('undone', Answer.Get('reversed', True));
  Call('flip_seam', '{"name": "Front"}');
  AssertEquals('not a seam', RpcRefused, ErrorCode);
  Call('add_seam', '{"sideA": [{"piece": "Front", "edge": "Line_A_B"}], "sideB": []}');
  AssertEquals('empty side', RpcRefused, ErrorCode);
  Call('add_seam', '{"sideA": [{"piece": "Front", "edge": "Line_A_B"}]}');
  AssertEquals('no side', RpcInvalidParams, ErrorCode);
  Call('delete', '{"name": "Front"}');
  AssertEquals('piece in use', RpcRefused, ErrorCode);
  Call('suggest_seams');
  AssertEquals('one piece has no pairs', 0, Answer.Arrays['suggestions'].Count);
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
