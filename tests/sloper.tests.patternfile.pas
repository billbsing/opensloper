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

// Saving and loading pattern files: the layout, a round trip through every
// object type, and the messages for files that cannot be loaded.
unit Sloper.Tests.PatternFile;

{$mode ObjFPC}{$H+}

interface

uses
  fpcunit, testregistry, Sloper.Tests.TestCase, Sloper.Core.Measurements, Sloper.Core.Draft, Sloper.Core.Pattern;

type
  TTestPatternFile = class(TOSTestCase)
  private
    FSet: TMeasurementSet;
    FPattern: TPattern;
    FLoaded: TPattern;
    function Check(Obj: TObject): TObject;
    function Key(const AName: string): string;
    procedure BuildEveryType;
    procedure LoadObjects(const ObjectsText: string);
    procedure AssertLoadFails(const ObjectsText, Msg: string);
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestLayout;
    procedure TestRoundTripEveryType;
    procedure TestDerivedNamesFollowEnds;
    procedure TestDerivedNameAvoidsLaterName;
    procedure TestUserEdgeNameKept;
    procedure TestOptionalFields;
    procedure TestLoadKeepsBadFormula;
    procedure TestNewIdsAfterLoad;
    procedure TestHeaderErrors;
    procedure TestObjectErrors;
    procedure TestFailedLoadEmptiesPattern;
    procedure TestSaveAndLoadFile;
    procedure TestMissingFile;
  end;

implementation

uses
  SysUtils, Sloper.Core.Geometry, Sloper.Core.EvalTypes, Sloper.Core.Names, Sloper.Core.Evaluator, Sloper.Core.PatternFile;

function PatternWithObjects(const ObjectsText: string): string;
begin
  Result := '{"format": "pattern", "version": 1, "objects": ' + ObjectsText + '}';
end;

procedure TTestPatternFile.SetUp;
begin
  FSet := TMeasurementSet.Create;
  FSet.Add('waist', 720);
  FPattern := TPattern.Create;
  FPattern.Measurements := FSet;
  FLoaded := TPattern.Create;
  FLoaded.Measurements := FSet;
end;

procedure TTestPatternFile.TearDown;
begin
  FreeAndNil(FLoaded);
  FreeAndNil(FPattern);
  FreeAndNil(FSet);
end;

function TTestPatternFile.Check(Obj: TObject): TObject;
begin
  if Obj = nil then
    Fail('Refused: ' + FPattern.LastError);
  Result := Obj;
end;

function TTestPatternFile.Key(const AName: string): string;
begin
  Result := FPattern.FindObject(AName).Key;
end;

// One object of every type, all valid. A (0, 0), B (190, 0), C (0, -200),
// E (190, -200); Base runs A to B along the x axis.
procedure TTestPatternFile.BuildEveryType;
var
  First, Second: TSplitPart;
  Base: string;
begin
  Check(FPattern.AddVariable('ease', '10'));
  Check(FPattern.AddFreePoint('A', '0', '0'));
  Check(FPattern.AddOffsetPoint('B', Key('A'), omPolar, '@waist/4 + #ease', '0'));
  Check(FPattern.AddOffsetPoint('C', Key('A'), omCartesian, '0', '-200'));
  Check(FPattern.AddOffsetPoint('E', Key('B'), omCartesian, '0', '-200'));
  Base := TEdgeObject(Check(FPattern.AddLine(Key('A'), Key('B'), erOutline, 'Base'))).Key;
  Check(FPattern.AddLine(Key('C'), Key('E'), erOutline, 'Hem'));
  Check(FPattern.AddAlongEdgePoint('D', Base, False, amLength, '50'));
  Check(FPattern.AddAlongEdgePoint('D2', Base, True, amRatio, '0.25'));
  Check(FPattern.AddOffsetPoint('G', Key('D'), omCartesian, '0', '-10'));
  Check(FPattern.AddLine(Key('D'), Key('G')));
  Check(FPattern.AddIntersectPoint('H', Key('Line_D_G'), Key('Hem'), True, False, 1));
  Check(FPattern.AddCircleEdgePoint('I', Key('A'), '100', Base, False, 1));
  Check(FPattern.AddProjectPoint('J', Key('H'), Base, pdPerpendicular, '', False));
  Check(FPattern.AddProjectPoint('K', Key('E'), Base, pdAngle, '90', True));
  Check(FPattern.AddCurve(Key('A'), Key('C'), '270', '50', '90', 'A.x + 50'));
  Check(FPattern.AddCurvePath([Key('C'), Key('H'), Key('E')], ['0', '0', '0'], ['', '20', '20'],
    ['20', '20', ''], erOutline));
  AssertTrue(FPattern.LastError, FPattern.SplitEdge(Base, Key('D'), First, Second));
  FPattern.Notes := 'Every type';
  FPattern.MeasurementFile := 'bill.slm';
end;

procedure TTestPatternFile.LoadObjects(const ObjectsText: string);
var
  Err: string;
begin
  if not LoadPatternFromText(FLoaded, PatternWithObjects(ObjectsText), Err) then
    Fail('Load failed: ' + Err);
end;

procedure TTestPatternFile.AssertLoadFails(const ObjectsText, Msg: string);
var
  Err: string;
begin
  AssertFalse(ObjectsText, LoadPatternFromText(FLoaded, PatternWithObjects(ObjectsText), Err));
  AssertEquals(ObjectsText, Msg, Err);
end;

procedure TTestPatternFile.TestLayout;
begin
  Check(FPattern.AddVariable('ease', '10'));
  Check(FPattern.AddFreePoint('A', '0', '0'));
  Check(FPattern.AddOffsetPoint('B', 'p1', omPolar, '@waist/4 + #ease', '0'));
  Check(FPattern.AddLine('p1', 'p2', erOutline));
  FPattern.Notes := 'Test';
  FPattern.MeasurementFile := 'bill.slm';
  AssertEquals(
    '{'#10 +
    '  "format": "pattern",'#10 +
    '  "version": 1,'#10 +
    '  "units": "mm",'#10 +
    '  "notes": "Test",'#10 +
    '  "measurementFile": "bill.slm",'#10 +
    '  "variables": ['#10 +
    '    {'#10 +
    '      "id": "v1",'#10 +
    '      "name": "ease",'#10 +
    '      "formula": "10",'#10 +
    '      "description": ""'#10 +
    '    }'#10 +
    '  ],'#10 +
    '  "objects": ['#10 +
    '    {'#10 +
    '      "id": "p1",'#10 +
    '      "type": "freePoint",'#10 +
    '      "name": "A",'#10 +
    '      "x": "0",'#10 +
    '      "y": "0"'#10 +
    '    },'#10 +
    '    {'#10 +
    '      "id": "p2",'#10 +
    '      "type": "offsetPoint",'#10 +
    '      "name": "B",'#10 +
    '      "base": "p1",'#10 +
    '      "mode": "polar",'#10 +
    '      "length": "@waist/4 + {v1}",'#10 +
    '      "angle": "0"'#10 +
    '    },'#10 +
    '    {'#10 +
    '      "id": "l1",'#10 +
    '      "type": "line",'#10 +
    '      "start": "p1",'#10 +
    '      "end": "p2",'#10 +
    '      "role": "outline"'#10 +
    '    }'#10 +
    '  ]'#10 +
    '}'#10, SavePatternToText(FPattern));
end;

procedure TTestPatternFile.TestRoundTripEveryType;
const
  FileTypes: array[0..9] of string = ('freePoint', 'offsetPoint', 'alongEdgePoint', 'intersectPoint',
    'circleEdgePoint', 'projectPoint', 'line', 'curve', 'curvePath', 'splitPart');
var
  Saved, Err, FileType: string;
  Index: integer;
  Original, Copy: TDraftObject;
begin
  BuildEveryType;
  Saved := SavePatternToText(FPattern);
  for FileType in FileTypes do
    AssertTrue('has ' + FileType, Pos('"type": "' + FileType + '"', Saved) > 0);
  AssertTrue(Err, LoadPatternFromText(FLoaded, Saved, Err));
  AssertEquals('saves the same', Saved, SavePatternToText(FLoaded));
  AssertEquals('notes', 'Every type', FLoaded.Notes);
  AssertEquals('measurement file', 'bill.slm', FLoaded.MeasurementFile);

  FPattern.Evaluate;
  FLoaded.Evaluate;
  AssertEquals('object count', FPattern.ObjectCount, FLoaded.ObjectCount);
  for Index := 0 to FPattern.ObjectCount - 1 do
  begin
    Original := FPattern.Objects[Index];
    Copy := FLoaded.Objects[Index];
    AssertTrue(Original.Name + ' valid: ' + Original.Message, Original.State = esValid);
    AssertTrue(Copy.Name + ' valid: ' + Copy.Message, Copy.State = esValid);
    AssertEquals('key', Original.Key, Copy.Key);
    AssertEquals('name', Original.Name, Copy.Name);
    AssertEquals('class', Original.ClassName, Copy.ClassName);
    if Original is TPointObject then
      AssertPointsNear(Original.Name, TPointObject(Original).Position, TPointObject(Copy).Position)
    else
    begin
      AssertNear(Original.Name + ' length', TEdgeObject(Original).Length, TEdgeObject(Copy).Length);
      AssertTrue(Original.Name + ' role', TEdgeObject(Original).Role = TEdgeObject(Copy).Role);
    end;
  end;
  AssertPointsNear('H', TPointObject(FLoaded.FindObject('H')).Position, Vec2(50, -200));
end;

procedure TTestPatternFile.TestDerivedNamesFollowEnds;
begin
  LoadObjects('[{"id": "p1", "type": "freePoint", "name": "A", "x": "0", "y": "0"},' +
    ' {"id": "p2", "type": "freePoint", "name": "B", "x": "10", "y": "0"},' +
    ' {"id": "l1", "type": "line", "start": "p1", "end": "p2"}]');
  AssertEquals('derived', 'Line_A_B', FLoaded.FindNode('l1').DisplayName);
  AssertTrue(FLoaded.Rename(FLoaded.FindObject('A'), 'Z'));
  AssertEquals('follows', 'Line_Z_B', FLoaded.FindNode('l1').DisplayName);
  AssertEquals('not saved', 0, Pos('Line_', SavePatternToText(FLoaded)));
end;

procedure TTestPatternFile.TestDerivedNameAvoidsLaterName;
begin
  LoadObjects('[{"id": "p1", "type": "freePoint", "name": "A", "x": "0", "y": "0"},' +
    ' {"id": "p2", "type": "freePoint", "name": "B", "x": "10", "y": "0"},' +
    ' {"id": "l1", "type": "line", "start": "p1", "end": "p2"},' +
    ' {"id": "l2", "type": "line", "name": "Line_A_B", "start": "p2", "end": "p1"}]');
  AssertEquals('user name kept', 'Line_A_B', FLoaded.FindNode('l2').DisplayName);
  AssertEquals('derived name moves aside', 'Line_A_B2', FLoaded.FindNode('l1').DisplayName);
end;

procedure TTestPatternFile.TestUserEdgeNameKept;
begin
  LoadObjects('[{"id": "p1", "type": "freePoint", "name": "A", "x": "0", "y": "0"},' +
    ' {"id": "p2", "type": "freePoint", "name": "B", "x": "10", "y": "0"},' +
    ' {"id": "l1", "type": "line", "name": "Waist", "start": "p1", "end": "p2"}]');
  AssertTrue(FLoaded.Rename(FLoaded.FindObject('A'), 'Z'));
  AssertEquals('Waist', FLoaded.FindNode('l1').DisplayName);
  AssertTrue('saved', Pos('"name": "Waist"', SavePatternToText(FLoaded)) > 0);
end;

procedure TTestPatternFile.TestOptionalFields;
var
  Offset: TOffsetPoint;
  Along: TAlongEdgePoint;
  Intersect: TIntersectPoint;
  Project: TProjectPoint;
begin
  LoadObjects('[{"id": "p1", "type": "freePoint", "name": "A", "x": "0", "y": "0"},' +
    ' {"id": "p2", "type": "offsetPoint", "name": "B", "base": "p1", "length": "100", "angle": "0"},' +
    ' {"id": "l1", "type": "line", "start": "p1", "end": "p2"},' +
    ' {"id": "p3", "type": "alongEdgePoint", "name": "C", "edge": "l1", "value": "30"},' +
    ' {"id": "p4", "type": "offsetPoint", "name": "D", "base": "p3", "mode": "cartesian", "dx": "0", "dy": "10"},' +
    ' {"id": "l2", "type": "line", "start": "p3", "end": "p4"},' +
    ' {"id": "p5", "type": "intersectPoint", "name": "E", "edgeA": "l1", "edgeB": "l2"},' +
    ' {"id": "p6", "type": "projectPoint", "name": "F", "point": "p4", "edge": "l1"}]');
  Offset := TOffsetPoint(FLoaded.FindObject('B'));
  AssertTrue('offset mode', Offset.Mode = omPolar);
  Along := TAlongEdgePoint(FLoaded.FindObject('C'));
  AssertFalse('from start', Along.FromEnd);
  AssertTrue('along mode', Along.Mode = amLength);
  Intersect := TIntersectPoint(FLoaded.FindObject('E'));
  AssertFalse('extendA', Intersect.ExtendA);
  AssertFalse('extendB', Intersect.ExtendB);
  AssertEquals('pick', 1, Intersect.Pick);
  Project := TProjectPoint(FLoaded.FindObject('F'));
  AssertTrue('direction', Project.Direction = pdPerpendicular);
  AssertFalse('extend', Project.Extend);
  AssertTrue('role', TEdgeObject(FLoaded.FindNode('l1')).Role = erConstruction);
  FLoaded.Evaluate;
  AssertPointsNear('E', Vec2(30, 0), TPointObject(FLoaded.FindObject('E')).Position);
  AssertPointsNear('F', Vec2(30, 0), TPointObject(FLoaded.FindObject('F')).Position);
end;

procedure TTestPatternFile.TestLoadKeepsBadFormula;
var
  Point: TDraftObject;
begin
  LoadObjects('[{"id": "p1", "type": "freePoint", "name": "A", "x": "1 +", "y": "0"}]');
  Point := FLoaded.FindObject('A');
  FLoaded.Evaluate;
  AssertTrue('error state', Point.State = esError);
  AssertTrue('text kept', Pos('"x": "1 +"', SavePatternToText(FLoaded)) > 0);
end;

procedure TTestPatternFile.TestNewIdsAfterLoad;
var
  Err: string;
begin
  AssertTrue(Err, LoadPatternFromText(FPattern, '{"format": "pattern", "version": 1,' +
    ' "variables": [{"id": "v4", "name": "ease", "formula": "1"}],' +
    ' "objects": [{"id": "p5", "type": "freePoint", "name": "A", "x": "0", "y": "0"},' +
    ' {"id": "p2", "type": "freePoint", "name": "B", "x": "10", "y": "0"},' +
    ' {"id": "l3", "type": "line", "start": "p5", "end": "p2"},' +
    ' {"id": "c2", "type": "curve", "start": "p5", "end": "p2",' +
    ' "angle1": "0", "length1": "1", "angle2": "180", "length2": "1"}]}', Err));
  Check(FPattern.AddVariable('more', '2'));
  AssertEquals('v5', FPattern.FindVariable('more').Key);
  Check(FPattern.AddFreePoint('C', '0', '5'));
  AssertEquals('p6', Key('C'));
  AssertEquals('l4', TEdgeObject(Check(FPattern.AddLine('p5', 'p6'))).Key);
  AssertEquals('c3', TEdgeObject(Check(FPattern.AddCurve('p5', 'p6', '0', '1', '0', '1'))).Key);
end;

procedure TTestPatternFile.TestHeaderErrors;
var
  Err: string;

  procedure CheckText(const Text, Msg: string);
  begin
    AssertFalse(Text, LoadPatternFromText(FLoaded, Text, Err));
    AssertEquals(Text, Msg, Err);
  end;

begin
  CheckText('{"format": "measurements", "version": 1}', rsPatternFileWrongFormat);
  CheckText('{"format": "pattern"}', rsPatternFileWrongFormat);
  CheckText('{"format": "pattern", "version": 2}', Format(rsPatternFileNewerVersion, [2]));
  CheckText('{"format": "pattern", "version": 1, "units": "cm"}', Format(rsPatternFileUnits, ['cm']));
  CheckText('{"format": "pattern", "version": 1, "objects": {}}', Format(rsPatternFileList, ['objects']));
  CheckText('{"format": "pattern", "version": 1, "objects": [1]}', Format(rsPatternFileList, ['objects']));
  CheckText('{"format": "pattern", "version": 1, "variables": [{"id": "x1", "name": "a", "formula": "1"}],' +
    ' "objects": [{"id": "x1", "type": "freePoint", "name": "A", "x": "0", "y": "0"}]}',
    Format(rsPatternFileBadId, [1, 'objects']));
end;

procedure TTestPatternFile.TestObjectErrors;
const
  PointA = '{"id": "p1", "type": "freePoint", "name": "A", "x": "0", "y": "0"}, ';
  PointB = '{"id": "p2", "type": "freePoint", "name": "B", "x": "10", "y": "0"}, ';
  LineAB = '{"id": "l1", "type": "line", "start": "p1", "end": "p2"}, ';
  LineBA = '{"id": "l2", "type": "line", "start": "p2", "end": "p1"}, ';
begin
  AssertLoadFails('[{"type": "freePoint", "name": "A", "x": "0", "y": "0"}]', Format(rsPatternFileBadId, [1, 'objects']));
  AssertLoadFails('[{"id": "1p", "type": "freePoint", "name": "A", "x": "0", "y": "0"}]',
    Format(rsPatternFileBadId, [1, 'objects']));
  AssertLoadFails('[' + PointA + '{"id": "p1", "type": "freePoint", "name": "B", "x": "0", "y": "0"}]',
    Format(rsPatternFileBadId, [2, 'objects']));
  AssertLoadFails('[{"id": "p1", "name": "A"}]', Format(rsPatternObjectMissing, ['p1', 'type']));
  AssertLoadFails('[{"id": "p1", "type": "spline"}]', Format(rsPatternObjectUnknownType, ['p1', 'spline']));
  AssertLoadFails('[{"id": "p1", "type": "freePoint", "x": "0", "y": "0"}]', Format(rsPatternObjectMissing, ['p1', 'name']));
  AssertLoadFails('[{"id": "p1", "type": "freePoint", "name": "a b", "x": "0", "y": "0"}]',
    Format(rsPatternObjectProblem, ['p1', Format(rsNameInvalid, ['a b'])]));
  AssertLoadFails('[' + PointA + '{"id": "p2", "type": "freePoint", "name": "a", "x": "0", "y": "0"}]',
    Format(rsPatternObjectProblem, ['p2', Format(rsNameTaken, ['a'])]));
  AssertLoadFails('[{"id": "p1", "type": "freePoint", "name": "A", "x": "0"}]', Format(rsPatternObjectMissing, ['p1', 'y']));
  AssertLoadFails('[{"id": "p1", "type": "freePoint", "name": "A", "x": 0, "y": "0"}]', Format(rsPatternObjectMissing, ['p1', 'x']));
  AssertLoadFails('[' + PointA + '{"id": "l1", "type": "line", "start": "p1", "end": "p2"}, ' + PointB +
    '{"id": "p9", "type": "freePoint", "name": "Z", "x": "0", "y": "0"}]',
    Format(rsPatternObjectNotBefore, ['l1', 'p2']));
  AssertLoadFails('[' + PointA + '{"id": "l1", "type": "line", "start": "p1"}]', Format(rsPatternObjectMissing, ['l1', 'end']));
  AssertLoadFails('[' + PointA + PointB + '{"id": "p3", "type": "alongEdgePoint", "name": "C", "edge": "p2", "value": "1"}]',
    Format(rsPatternObjectProblem, ['p3', Format(rsDraftNotAnEdge, ['B'])]));
  AssertLoadFails('[' + PointA + PointB + LineAB + '{"id": "l2", "type": "line", "start": "p1", "end": "l1"}]',
    Format(rsPatternObjectProblem, ['l2', Format(rsDraftNotAPoint, ['l1'])]));
  AssertLoadFails('[' + PointA + '{"id": "p2", "type": "offsetPoint", "name": "B", "base": "p1", "mode": "sideways",' +
    ' "length": "1", "angle": "0"}]', Format(rsPatternObjectMissing, ['p2', 'mode']));
  AssertLoadFails('[' + PointA + PointB + LineAB + '{"id": "l2", "type": "line", "start": "p1", "end": "p2", "role": "seam"}]',
    Format(rsPatternObjectMissing, ['l2', 'role']));
  AssertLoadFails('[' + PointA + PointB + LineAB + LineBA +
    '{"id": "p3", "type": "intersectPoint", "name": "C", "edgeA": "l1", "edgeB": "l2", "extendA": "yes"}]',
    Format(rsPatternObjectMissing, ['p3', 'extendA']));
  AssertLoadFails('[' + PointA + PointB + LineAB + LineBA +
    '{"id": "p3", "type": "intersectPoint", "name": "C", "edgeA": "l1", "edgeB": "l2", "pick": 0}]',
    Format(rsPatternObjectProblem, ['p3', rsPatternBadPick]));
  AssertLoadFails('[' + PointA + PointB + LineAB +
    '{"id": "p3", "type": "intersectPoint", "name": "C", "edgeA": "l1", "edgeB": "l1"}]',
    Format(rsPatternObjectProblem, ['p3', rsPatternSameEdge]));
  AssertLoadFails('[' + PointA + '{"id": "c1", "type": "curvePath", "nodes": [{"point": "p1", "angle": "0"}]}]',
    Format(rsPatternObjectProblem, ['c1', rsPatternPathTooShort]));
  AssertLoadFails('[' + PointA + PointB + '{"id": "c1", "type": "curvePath", "nodes": [{"point": "p1", "angle": "0",' +
    ' "lengthOut": "1"}, {"point": "p2", "angle": "0"}]}]', Format(rsPatternObjectMissing, ['c1', 'lengthIn']));
  AssertLoadFails('[' + PointA + PointB + LineAB + '{"id": "l2", "type": "splitPart", "edge": "l1", "point": "p2", "part": 3}]',
    Format(rsPatternObjectMissing, ['l2', 'part']));
end;

procedure TTestPatternFile.TestFailedLoadEmptiesPattern;
var
  Err: string;
begin
  BuildEveryType;
  AssertFalse(LoadPatternFromText(FPattern, PatternWithObjects(
    '[{"id": "p1", "type": "freePoint", "name": "A", "x": "0", "y": "0"}, {"id": "p2", "type": "spline"}]'), Err));
  AssertEquals('objects', 0, FPattern.ObjectCount);
  AssertEquals('variables', 0, FPattern.VariableCount);
  AssertEquals('notes', '', FPattern.Notes);
end;

procedure TTestPatternFile.TestSaveAndLoadFile;
var
  FileName, Err: string;
begin
  FileName := ConcatPaths([GetTempDir, 'opensloper-test.sloper']);
  try
    BuildEveryType;
    FPattern.Notes := 'Ärmel';
    AssertTrue(Err, SavePatternToFile(FPattern, FileName, Err));
    AssertTrue(Err, LoadPatternFromFile(FLoaded, FileName, Err));
    AssertEquals('UTF-8 notes', 'Ärmel', FLoaded.Notes);
    AssertEquals(SavePatternToText(FPattern), SavePatternToText(FLoaded));
  finally
    DeleteFile(FileName);
  end;
end;

procedure TTestPatternFile.TestMissingFile;
var
  Err: string;
begin
  AssertFalse(LoadPatternFromFile(FLoaded, ConcatPaths([GetTempDir, 'no-such-file.sloper']), Err));
  AssertTrue('message names the file', Pos('no-such-file.sloper', Err) > 0);
end;

initialization
  RegisterTest(TTestPatternFile);

end.
