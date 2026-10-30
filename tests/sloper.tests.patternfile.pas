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
    procedure TestNextIdKept;
    procedure TestHeaderErrors;
    procedure TestObjectErrors;
    procedure TestFailedLoadEmptiesPattern;
    procedure TestSaveAndLoadFile;
    procedure TestMissingFile;
    procedure TestMeasurementFilePath;
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
  Check(FPattern.AddOffsetPoint('B', '2', omPolar, '@waist/4 + #ease', '0'));
  Check(FPattern.AddLine('2', '3', erOutline));
  FPattern.Notes := 'Test';
  FPattern.MeasurementFile := 'bill.slm';
  AssertEquals(
    '{'#10 +
    '  "format": "pattern",'#10 +
    '  "version": 1,'#10 +
    '  "units": "mm",'#10 +
    '  "notes": "Test",'#10 +
    '  "measurementFile": "bill.slm",'#10 +
    '  "nextId": 5,'#10 +
    '  "variables": ['#10 +
    '    {'#10 +
    '      "id": 1,'#10 +
    '      "name": "ease",'#10 +
    '      "formula": "10",'#10 +
    '      "description": ""'#10 +
    '    }'#10 +
    '  ],'#10 +
    '  "objects": ['#10 +
    '    {'#10 +
    '      "id": 2,'#10 +
    '      "type": "freePoint",'#10 +
    '      "name": "A",'#10 +
    '      "x": "0",'#10 +
    '      "y": "0"'#10 +
    '    },'#10 +
    '    {'#10 +
    '      "id": 3,'#10 +
    '      "type": "offsetPoint",'#10 +
    '      "name": "B",'#10 +
    '      "base": 2,'#10 +
    '      "mode": "polar",'#10 +
    '      "length": "@waist/4 + {1}",'#10 +
    '      "angle": "0"'#10 +
    '    },'#10 +
    '    {'#10 +
    '      "id": 4,'#10 +
    '      "type": "line",'#10 +
    '      "start": 2,'#10 +
    '      "end": 3,'#10 +
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
  LoadObjects('[{"id": 1, "type": "freePoint", "name": "A", "x": "0", "y": "0"},' +
    ' {"id": 2, "type": "freePoint", "name": "B", "x": "10", "y": "0"},' +
    ' {"id": 3, "type": "line", "start": 1, "end": 2}]');
  AssertEquals('derived', 'Line_A_B', FLoaded.FindNode('3').DisplayName);
  AssertTrue(FLoaded.Rename(FLoaded.FindObject('A'), 'Z'));
  AssertEquals('follows', 'Line_Z_B', FLoaded.FindNode('3').DisplayName);
  AssertEquals('not saved', 0, Pos('Line_', SavePatternToText(FLoaded)));
end;

procedure TTestPatternFile.TestDerivedNameAvoidsLaterName;
begin
  LoadObjects('[{"id": 1, "type": "freePoint", "name": "A", "x": "0", "y": "0"},' +
    ' {"id": 2, "type": "freePoint", "name": "B", "x": "10", "y": "0"},' +
    ' {"id": 3, "type": "line", "start": 1, "end": 2},' +
    ' {"id": 4, "type": "line", "name": "Line_A_B", "start": 2, "end": 1}]');
  AssertEquals('user name kept', 'Line_A_B', FLoaded.FindNode('4').DisplayName);
  AssertEquals('derived name moves aside', 'Line_A_B2', FLoaded.FindNode('3').DisplayName);
end;

procedure TTestPatternFile.TestUserEdgeNameKept;
begin
  LoadObjects('[{"id": 1, "type": "freePoint", "name": "A", "x": "0", "y": "0"},' +
    ' {"id": 2, "type": "freePoint", "name": "B", "x": "10", "y": "0"},' +
    ' {"id": 3, "type": "line", "name": "Waist", "start": 1, "end": 2}]');
  AssertTrue(FLoaded.Rename(FLoaded.FindObject('A'), 'Z'));
  AssertEquals('Waist', FLoaded.FindNode('3').DisplayName);
  AssertTrue('saved', Pos('"name": "Waist"', SavePatternToText(FLoaded)) > 0);
end;

procedure TTestPatternFile.TestOptionalFields;
var
  Offset: TOffsetPoint;
  Along: TAlongEdgePoint;
  Intersect: TIntersectPoint;
  Project: TProjectPoint;
begin
  LoadObjects('[{"id": 1, "type": "freePoint", "name": "A", "x": "0", "y": "0"},' +
    ' {"id": 2, "type": "offsetPoint", "name": "B", "base": 1, "length": "100", "angle": "0"},' +
    ' {"id": 3, "type": "line", "start": 1, "end": 2},' +
    ' {"id": 4, "type": "alongEdgePoint", "name": "C", "edge": 3, "value": "30"},' +
    ' {"id": 5, "type": "offsetPoint", "name": "D", "base": 4, "mode": "cartesian", "dx": "0", "dy": "10"},' +
    ' {"id": 6, "type": "line", "start": 4, "end": 5},' +
    ' {"id": 7, "type": "intersectPoint", "name": "E", "edgeA": 3, "edgeB": 6},' +
    ' {"id": 8, "type": "projectPoint", "name": "F", "point": 5, "edge": 3}]');
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
  AssertTrue('role', TEdgeObject(FLoaded.FindNode('3')).Role = erConstruction);
  FLoaded.Evaluate;
  AssertPointsNear('E', Vec2(30, 0), TPointObject(FLoaded.FindObject('E')).Position);
  AssertPointsNear('F', Vec2(30, 0), TPointObject(FLoaded.FindObject('F')).Position);
end;

procedure TTestPatternFile.TestLoadKeepsBadFormula;
var
  Point: TDraftObject;
begin
  LoadObjects('[{"id": 1, "type": "freePoint", "name": "A", "x": "1 +", "y": "0"}]');
  Point := FLoaded.FindObject('A');
  FLoaded.Evaluate;
  AssertTrue('error state', Point.State = esError);
  AssertTrue('text kept', Pos('"x": "1 +"', SavePatternToText(FLoaded)) > 0);
end;

procedure TTestPatternFile.TestNewIdsAfterLoad;
var
  Err: string;
begin
  // No nextId: new IDs continue above the highest, whatever the order
  AssertTrue(Err, LoadPatternFromText(FPattern, '{"format": "pattern", "version": 1,' +
    ' "variables": [{"id": 4, "name": "ease", "formula": "1"}],' +
    ' "objects": [{"id": 9, "type": "freePoint", "name": "A", "x": "0", "y": "0"},' +
    ' {"id": 2, "type": "freePoint", "name": "B", "x": "10", "y": "0"},' +
    ' {"id": 3, "type": "line", "start": 9, "end": 2},' +
    ' {"id": 5, "type": "curve", "start": 9, "end": 2,' +
    ' "angle1": "0", "length1": "1", "angle2": "180", "length2": "1"}]}', Err));
  AssertEquals(10, FPattern.NextId);
  Check(FPattern.AddVariable('more', '2'));
  AssertEquals('10', FPattern.FindVariable('more').Key);
  Check(FPattern.AddFreePoint('C', '0', '5'));
  AssertEquals('11', Key('C'));
  AssertEquals('12', TEdgeObject(Check(FPattern.AddLine('9', '11'))).Key);
end;

// A saved counter above every ID keeps deleted IDs retired
procedure TTestPatternFile.TestNextIdKept;
var
  Saved, Err: string;
begin
  Check(FPattern.AddFreePoint('A', '0', '0'));
  Check(FPattern.AddFreePoint('B', '1', '0'));
  AssertTrue(FPattern.Delete(FPattern.FindObject('B')));
  Saved := SavePatternToText(FPattern);
  AssertTrue('saved', Pos('"nextId": 3,', Saved) > 0);
  AssertTrue(Err, LoadPatternFromText(FLoaded, Saved, Err));
  AssertEquals(3, FLoaded.NextId);
  AssertEquals('3', FLoaded.AddFreePoint('C', '0', '1').Key);
  AssertFalse('below an ID', LoadPatternFromText(FLoaded, '{"format": "pattern", "version": 1, "nextId": 1,' +
    ' "objects": [{"id": 1, "type": "freePoint", "name": "A", "x": "0", "y": "0"}]}', Err));
  AssertEquals(rsPatternFileBadNextId, Err);
  AssertFalse('not a number', LoadPatternFromText(FLoaded, '{"format": "pattern", "version": 1, "nextId": "7"}', Err));
  AssertEquals(rsPatternFileBadNextId, Err);
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
  CheckText('{"format": "pattern", "version": 1, "variables": [{"id": 1, "name": "a", "formula": "1"}],' +
    ' "objects": [{"id": 1, "type": "freePoint", "name": "A", "x": "0", "y": "0"}]}',
    Format(rsPatternFileBadId, [1, 'objects']));
end;

procedure TTestPatternFile.TestObjectErrors;
const
  PointA = '{"id": 1, "type": "freePoint", "name": "A", "x": "0", "y": "0"}, ';
  PointB = '{"id": 2, "type": "freePoint", "name": "B", "x": "10", "y": "0"}, ';
  LineAB = '{"id": 3, "type": "line", "start": 1, "end": 2}, ';
  LineBA = '{"id": 4, "type": "line", "start": 2, "end": 1}, ';
begin
  AssertLoadFails('[{"type": "freePoint", "name": "A", "x": "0", "y": "0"}]', Format(rsPatternFileBadId, [1, 'objects']));
  AssertLoadFails('[{"id": "1", "type": "freePoint", "name": "A", "x": "0", "y": "0"}]',
    Format(rsPatternFileBadId, [1, 'objects']));
  AssertLoadFails('[{"id": 0, "type": "freePoint", "name": "A", "x": "0", "y": "0"}]',
    Format(rsPatternFileBadId, [1, 'objects']));
  AssertLoadFails('[' + PointA + '{"id": 2, "type": "offsetPoint", "name": "B", "base": "1", "length": "1", "angle": "0"}]',
    Format(rsPatternObjectMissing, ['2', 'base']));
  AssertLoadFails('[' + PointA + '{"id": 1, "type": "freePoint", "name": "B", "x": "0", "y": "0"}]',
    Format(rsPatternFileBadId, [2, 'objects']));
  AssertLoadFails('[{"id": 1, "name": "A"}]', Format(rsPatternObjectMissing, ['1', 'type']));
  AssertLoadFails('[{"id": 1, "type": "spline"}]', Format(rsPatternObjectUnknownType, ['1', 'spline']));
  AssertLoadFails('[{"id": 1, "type": "freePoint", "x": "0", "y": "0"}]', Format(rsPatternObjectMissing, ['1', 'name']));
  AssertLoadFails('[{"id": 1, "type": "freePoint", "name": "a b", "x": "0", "y": "0"}]',
    Format(rsPatternObjectProblem, ['1', Format(rsNameInvalid, ['a b'])]));
  AssertLoadFails('[' + PointA + '{"id": 2, "type": "freePoint", "name": "a", "x": "0", "y": "0"}]',
    Format(rsPatternObjectProblem, ['2', Format(rsNameTaken, ['a'])]));
  AssertLoadFails('[{"id": 1, "type": "freePoint", "name": "A", "x": "0"}]', Format(rsPatternObjectMissing, ['1', 'y']));
  AssertLoadFails('[{"id": 1, "type": "freePoint", "name": "A", "x": 0, "y": "0"}]', Format(rsPatternObjectMissing, ['1', 'x']));
  AssertLoadFails('[' + PointA + '{"id": 3, "type": "line", "start": 1, "end": 2}, ' + PointB +
    '{"id": 5, "type": "freePoint", "name": "Z", "x": "0", "y": "0"}]',
    Format(rsPatternObjectNotBefore, ['3', '2']));
  AssertLoadFails('[' + PointA + '{"id": 3, "type": "line", "start": 1}]', Format(rsPatternObjectMissing, ['3', 'end']));
  AssertLoadFails('[' + PointA + PointB + '{"id": 6, "type": "alongEdgePoint", "name": "C", "edge": 2, "value": "1"}]',
    Format(rsPatternObjectProblem, ['6', Format(rsDraftNotAnEdge, ['B'])]));
  AssertLoadFails('[' + PointA + PointB + LineAB + '{"id": 4, "type": "line", "start": 1, "end": 3}]',
    Format(rsPatternObjectProblem, ['4', Format(rsDraftNotAPoint, ['3'])]));
  AssertLoadFails('[' + PointA + '{"id": 2, "type": "offsetPoint", "name": "B", "base": 1, "mode": "sideways",' +
    ' "length": "1", "angle": "0"}]', Format(rsPatternObjectMissing, ['2', 'mode']));
  AssertLoadFails('[' + PointA + PointB + LineAB + '{"id": 4, "type": "line", "start": 1, "end": 2, "role": "seam"}]',
    Format(rsPatternObjectMissing, ['4', 'role']));
  AssertLoadFails('[' + PointA + PointB + LineAB + LineBA +
    '{"id": 6, "type": "intersectPoint", "name": "C", "edgeA": 3, "edgeB": 4, "extendA": "yes"}]',
    Format(rsPatternObjectMissing, ['6', 'extendA']));
  AssertLoadFails('[' + PointA + PointB + LineAB + LineBA +
    '{"id": 6, "type": "intersectPoint", "name": "C", "edgeA": 3, "edgeB": 4, "pick": 0}]',
    Format(rsPatternObjectProblem, ['6', rsPatternBadPick]));
  AssertLoadFails('[' + PointA + PointB + LineAB +
    '{"id": 6, "type": "intersectPoint", "name": "C", "edgeA": 3, "edgeB": 3}]',
    Format(rsPatternObjectProblem, ['6', rsPatternSameEdge]));
  AssertLoadFails('[' + PointA + '{"id": 7, "type": "curvePath", "nodes": [{"point": 1, "angle": "0"}]}]',
    Format(rsPatternObjectProblem, ['7', rsPatternPathTooShort]));
  AssertLoadFails('[' + PointA + PointB + '{"id": 7, "type": "curvePath", "nodes": [{"point": 1, "angle": "0",' +
    ' "lengthOut": "1"}, {"point": 2, "angle": "0"}]}]', Format(rsPatternObjectMissing, ['7', 'lengthIn']));
  AssertLoadFails('[' + PointA + PointB + LineAB + '{"id": 4, "type": "splitPart", "edge": 3, "point": 2, "part": 3}]',
    Format(rsPatternObjectMissing, ['4', 'part']));
end;

procedure TTestPatternFile.TestFailedLoadEmptiesPattern;
var
  Err: string;
begin
  BuildEveryType;
  AssertFalse(LoadPatternFromText(FPattern, PatternWithObjects(
    '[{"id": 1, "type": "freePoint", "name": "A", "x": "0", "y": "0"}, {"id": 2, "type": "spline"}]'), Err));
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

procedure TTestPatternFile.TestMeasurementFilePath;
begin
  AssertEquals('none', '', MeasurementFilePath(FPattern, ConcatPaths(['dir', 'skirt.sloper'])));
  FPattern.MeasurementFile := 'bill.slm';
  AssertEquals('beside the pattern', ConcatPaths(['dir', 'bill.slm']),
    MeasurementFilePath(FPattern, ConcatPaths(['dir', 'skirt.sloper'])));
  AssertEquals('pattern in the current folder', 'bill.slm', MeasurementFilePath(FPattern, 'skirt.sloper'));
  FPattern.MeasurementFile := 'sets/bill.slm';
  AssertEquals('stored with /', ConcatPaths(['dir', 'sets', 'bill.slm']),
    MeasurementFilePath(FPattern, ConcatPaths(['dir', 'skirt.sloper'])));
  {$IFDEF UNIX}
  FPattern.MeasurementFile := '/home/bill/bill.slm';
  AssertEquals('absolute', '/home/bill/bill.slm', MeasurementFilePath(FPattern, ConcatPaths(['dir', 'skirt.sloper'])));
  {$ENDIF}
end;

initialization
  RegisterTest(TTestPatternFile);

end.
