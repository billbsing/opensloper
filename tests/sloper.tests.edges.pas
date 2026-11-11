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

// Curve paths and split edges. The test path runs A (0, 0) -> B (100, 100)
// -> C (200, 0) with tangents 90, 0 and 270 degrees and 50 mm handles, so it
// is symmetric about x = 100. Each segment is 154.88679880318648 mm long
// (numerical integration), and y = 50 is crossed at x = 15.99776046414837
// and its mirror, 184.00223953585163.
unit Sloper.Tests.Edges;

{$mode ObjFPC}{$H+}

interface

uses
  fpcunit, testregistry, Sloper.Tests.TestCase, Sloper.Core.Geometry, Sloper.Core.EvalTypes, Sloper.Core.Measurements,
  Sloper.Core.Draft, Sloper.Core.Pattern;

type
  TTestEdges = class(TOSTestCase)
  private
    FSet: TMeasurementSet;
    FPattern: TPattern;
    function Pt(const AName: string; X, Y: double): TPointObject;
    function Key(const AName: string): string;
    function Check(Obj: TObject): TObject;
    function TestPath: TCurvePathObject;
    function BaseLine: TLineObject;
    procedure AssertAt(const Msg: string; P: TPointObject; X, Y: double);
    procedure AssertValidEdge(const Msg: string; E: TEdgeObject);
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestPathNameAndFields;
    procedure TestPathLengthAndMiddle;
    procedure TestPathJoinsSmoothly;
    procedure TestPathEndAngles;
    procedure TestPathCrossings;
    procedure TestPathExtends;
    procedure TestPathFormulas;
    procedure TestPathNegativeHandleIsInvalid;
    procedure TestPathChecks;
    procedure TestPathNamesFollowEnds;
    procedure TestSplitLine;
    procedure TestSplitFollowsPoint;
    procedure TestSplitPointOffEdge;
    procedure TestSplitAtEnd;
    procedure TestSplitCurve;
    procedure TestSplitPathAtNode;
    procedure TestSplitPartAgain;
    procedure TestSplitPartsCross;
    procedure TestSplitChecks;
    procedure TestLinesHaveEndAngles;
  end;

implementation

uses
  SysUtils, Sloper.Core.Formula, Sloper.Core.Evaluator;

const
  SEGMENT_LENGTH = 154.88679880318648;
  CROSSING_X = 15.99776046414837;

procedure TTestEdges.SetUp;
begin
  FSet := TMeasurementSet.Create;
  FSet.Add('neck', 400);
  FPattern := TPattern.Create;
  FPattern.Measurements := FSet;
end;

procedure TTestEdges.TearDown;
begin
  FreeAndNil(FPattern);
  FreeAndNil(FSet);
end;

function TTestEdges.Check(Obj: TObject): TObject;
begin
  if not Assigned(Obj) then
    Fail('Refused: ' + FPattern.LastError);
  Result := Obj;
end;

function TTestEdges.Pt(const AName: string; X, Y: double): TPointObject;
begin
  Result := TPointObject(Check(FPattern.AddFreePoint(AName, FloatToStr(X), FloatToStr(Y))));
end;

function TTestEdges.Key(const AName: string): string;
begin
  Result := FPattern.FindObject(AName).Key;
end;

function TTestEdges.TestPath: TCurvePathObject;
begin
  Pt('A', 0, 0);
  Pt('B', 100, -100);
  Pt('C', 200, 0);
  Result := TCurvePathObject(Check(FPattern.AddCurvePath([Key('A'), Key('B'), Key('C')],
    ['90', '0', '270'], ['', '50', '50'], ['50', '50', ''])));
end;

// Line_A_B from (0, 0) to (100, 0)
function TTestEdges.BaseLine: TLineObject;
begin
  Pt('A', 0, 0);
  Pt('B', 100, 0);
  Result := TLineObject(Check(FPattern.AddLine(Key('A'), Key('B'))));
end;

procedure TTestEdges.AssertAt(const Msg: string; P: TPointObject; X, Y: double);
begin
  AssertTrue(Msg + ' state: ' + P.Message, P.State = esValid);
  AssertPointsNear(Msg, Vec2(X, Y), P.Position);
end;

procedure TTestEdges.AssertValidEdge(const Msg: string; E: TEdgeObject);
begin
  AssertTrue(Msg + ' state: ' + E.Message, E.State = esValid);
end;

procedure TTestEdges.TestPathNameAndFields;
var
  Path: TCurvePathObject;
begin
  Path := TestPath;
  AssertEquals('Path_A_C', Path.Name);
  AssertEquals('4', Path.Key);
  AssertNotNull('first node has lengthOut', Path.Field('node1.lengthOut'));
  AssertNull('first node has no lengthIn', Path.Field('node1.lengthIn'));
  AssertNotNull('middle node has both', Path.Field('node2.lengthIn'));
  AssertNull('last node has no lengthOut', Path.Field('node3.lengthOut'));
  // node1: angle, lengthOut; node2: lengthIn, angle, lengthOut; node3: lengthIn, angle
  AssertEquals('seven fields', 7, Path.FieldCount);
end;

procedure TTestEdges.TestPathLengthAndMiddle;
var
  Path: TCurvePathObject;
  Middle: TPointObject;
begin
  Path := TestPath;
  Middle := TPointObject(Check(FPattern.AddAlongEdgePoint('M', Path.Key, False, amRatio, '0.5')));
  FPattern.Evaluate;
  AssertValidEdge('path', Path);
  AssertEquals('two segments', 2, Length(Path.Segments));
  AssertNear('length', 2 * SEGMENT_LENGTH, Path.Length, 1e-6);
  AssertNear('length property', 2 * SEGMENT_LENGTH, Path.PropertyValue('length'), 1e-6);
  AssertAt('half way is node B', Middle, 100, -100);
end;

procedure TTestEdges.TestPathJoinsSmoothly;
var
  Path: TCurvePathObject;
  First, Second: TEdgeSegment;
begin
  Path := TestPath;
  FPattern.Evaluate;
  First := Path.Segments[0];
  Second := Path.Segments[1];
  AssertPointsNear('handle into B', Vec2(50, -100), First.Curve.P2);
  AssertPointsNear('handle out of B', Vec2(150, -100), Second.Curve.P1);
  // Both handles at B lie on its tangent, on opposite sides
  AssertNear('tangent continues', NormalizeAngle(First.Curve.EndAngle + 180), Second.Curve.StartAngle);
end;

procedure TTestEdges.TestPathEndAngles;
var
  Path: TCurvePathObject;
begin
  Path := TestPath;
  FPattern.Evaluate;
  AssertNear('angle1 is the start handle', 90, Path.PropertyValue('angle1'));
  // The end handle points back up from C, against the 270 degree tangent
  AssertNear('angle2 is the end handle', 90, Path.PropertyValue('angle2'));
end;

procedure TTestEdges.TestPathCrossings;
var
  Path: TCurvePathObject;
  Across: TLineObject;
  First, Second: TPointObject;
begin
  Path := TestPath;
  Pt('L', -50, -50);
  Pt('R', 250, -50);
  Across := TLineObject(Check(FPattern.AddLine(Key('L'), Key('R'))));
  First := TPointObject(Check(FPattern.AddIntersectPoint('X1', Path.Key, Across.Key, False, False, 1)));
  Second := TPointObject(Check(FPattern.AddIntersectPoint('X2', Path.Key, Across.Key, False, False, 2)));
  FPattern.Evaluate;
  AssertAt('on the first segment', First, CROSSING_X, -50);
  AssertAt('on the second segment', Second, 200 - CROSSING_X, -50);
end;

procedure TTestEdges.TestPathExtends;
var
  Path: TCurvePathObject;
  Below: TLineObject;
  BeforeStart, AfterEnd: TPointObject;
begin
  Path := TestPath;
  Pt('L', -50, 20);
  Pt('R', 250, 20);
  Below := TLineObject(Check(FPattern.AddLine(Key('L'), Key('R'))));
  BeforeStart := TPointObject(Check(FPattern.AddIntersectPoint('X1', Path.Key, Below.Key, True, False, 1)));
  AfterEnd := TPointObject(Check(FPattern.AddIntersectPoint('X2', Path.Key, Below.Key, True, False, 2)));
  FPattern.Evaluate;
  // The path leaves A going up and reaches C going down, so its
  // extensions run straight down from both ends
  AssertAt('before the start', BeforeStart, 0, 20);
  AssertAt('after the end', AfterEnd, 200, 20);
end;

procedure TTestEdges.TestPathFormulas;
var
  Path: TCurvePathObject;
begin
  Path := TestPath;
  AssertTrue(FPattern.LastError, FPattern.SetFormula(Path, 'node1.lengthOut', '@neck / 8'));
  AssertEquals('@neck / 8', FPattern.FormulaText(Path, 'node1.lengthOut'));
  AssertTrue(FPattern.SetFormula(Path, 'node2.angle', '1 / (@neck - 400)'));
  FPattern.Evaluate;
  AssertTrue(Path.State = esError);
  AssertEquals('node2.angle: ' + rsFormulaDivideByZero, Path.Message);
end;

procedure TTestEdges.TestPathNegativeHandleIsInvalid;
var
  Path: TCurvePathObject;
begin
  Path := TestPath;
  FPattern.SetFormula(Path, 'node3.lengthIn', '-1');
  FPattern.Evaluate;
  AssertTrue(Path.State = esInvalid);
  AssertEquals(rsDraftNegativeHandle, Path.Message);
end;

procedure TTestEdges.TestPathChecks;
var
  Line: TLineObject;
begin
  Line := BaseLine;
  AssertNull('one node', FPattern.AddCurvePath([Key('A')], ['0'], [''], ['']));
  AssertEquals(rsPatternPathTooShort, FPattern.LastError);
  AssertNull('repeated node', FPattern.AddCurvePath([Key('A'), Key('A'), Key('B')], ['0', '0', '0'],
    ['', '1', '1'], ['1', '1', '']));
  AssertEquals(rsPatternPathRepeats, FPattern.LastError);
  AssertNull('missing angles', FPattern.AddCurvePath([Key('A'), Key('B')], ['0'], ['', '1'], ['1', '']));
  AssertEquals(rsPatternPathArrays, FPattern.LastError);
  AssertNull('a line as a node', FPattern.AddCurvePath([Key('A'), Line.Key], ['0', '0'], ['', '1'], ['1', '']));
  AssertNull('bad formula', FPattern.AddCurvePath([Key('A'), Key('B')], ['0', '0'], ['', '1 +'], ['1', '']));
  AssertEquals('node2.lengthIn', FPattern.LastErrorField);
end;

procedure TTestEdges.TestPathNamesFollowEnds;
var
  Path: TCurvePathObject;
begin
  Path := TestPath;
  AssertTrue(FPattern.Rename(FPattern.FindObject('B'), 'Middle'));
  AssertEquals('inner node does not name the path', 'Path_A_C', Path.Name);
  AssertTrue(FPattern.Rename(FPattern.FindObject('A'), 'Neck'));
  AssertEquals('Path_Neck_C', Path.Name);
  AssertFalse('nodes in use', FPattern.Delete(FPattern.FindObject('Middle')));
end;

procedure TTestEdges.TestSplitLine;
var
  Line: TLineObject;
  P: TPointObject;
  First, Second: TSplitPart;
begin
  Line := BaseLine;
  P := TPointObject(Check(FPattern.AddAlongEdgePoint('P', Line.Key, False, amLength, '30')));
  AssertTrue(FPattern.LastError, FPattern.SplitEdge(Line.Key, P.Key, First, Second));
  AssertEquals('Line_A_P', First.Name);
  AssertEquals('Line_P_B', Second.Name);
  AssertEquals('next free ID', '5', First.Key);
  FPattern.Evaluate;
  AssertValidEdge('first', First);
  AssertNear('first length', 30, First.Length);
  AssertNear('second length', 70, Second.Length);
  AssertNear('straight parts have angle', 0, Second.PropertyValue('angle'));
  AssertTrue('source stays', Line.State = esValid);
end;

procedure TTestEdges.TestSplitFollowsPoint;
var
  Line: TLineObject;
  P: TPointObject;
  First, Second: TSplitPart;
begin
  Line := BaseLine;
  P := TPointObject(Check(FPattern.AddAlongEdgePoint('P', Line.Key, False, amLength, '30')));
  FPattern.SplitEdge(Line.Key, P.Key, First, Second);
  FPattern.SetFormula(P, 'value', '60');
  FPattern.SetFormula(FPattern.FindObject('B'), 'x', '200');
  FPattern.Evaluate;
  AssertNear('first', 60, First.Length);
  AssertNear('second follows the longer line', 140, Second.Length);
end;

procedure TTestEdges.TestSplitPointOffEdge;
var
  Line: TLineObject;
  P: TPointObject;
  First, Second: TSplitPart;
begin
  Line := BaseLine;
  P := Pt('P', 50, 10);
  AssertTrue(FPattern.SplitEdge(Line.Key, P.Key, First, Second));
  FPattern.Evaluate;
  AssertTrue(First.State = esInvalid);
  AssertEquals(Format(rsDraftNotOnEdge, ['P', 'Line_A_B']), First.Message);
  AssertTrue(Second.State = esInvalid);
end;

procedure TTestEdges.TestSplitAtEnd;
var
  Line: TLineObject;
  P: TPointObject;
  First, Second: TSplitPart;
begin
  Line := BaseLine;
  P := TPointObject(Check(FPattern.AddAlongEdgePoint('P', Line.Key, False, amLength, '0')));
  FPattern.SplitEdge(Line.Key, P.Key, First, Second);
  FPattern.Evaluate;
  AssertTrue(First.State = esInvalid);
  AssertEquals(Format(rsDraftSplitAtEnd, ['P', 'Line_A_B']), First.Message);
end;

procedure TTestEdges.TestSplitCurve;
var
  Curve: TCurveObject;
  M: TPointObject;
  First, Second: TSplitPart;
begin
  // Arch from (0, 0) to (100, 0), handles straight up, top at (50, -75)
  Pt('A', 0, 0);
  Pt('B', 100, 0);
  Curve := TCurveObject(Check(FPattern.AddCurve(Key('A'), Key('B'), '90', '100', '90', '100')));
  M := TPointObject(Check(FPattern.AddAlongEdgePoint('M', Curve.Key, False, amRatio, '0.5')));
  AssertTrue(FPattern.SplitEdge(Curve.Key, M.Key, First, Second));
  AssertEquals('Curve_A_M', First.Name);
  AssertEquals('next free ID', '5', First.Key);
  FPattern.Evaluate;
  AssertValidEdge('first', First);
  AssertNear('halves', Curve.Length / 2, First.Length, 1e-6);
  AssertNear('halves', Curve.Length / 2, Second.Length, 1e-6);
  AssertPointsNear('first ends at the top', Vec2(50, -75), First.PointAtLength(First.Length));
  // At the top the curve runs level, to the right
  AssertNear('first end handle points back left', 180, First.PropertyValue('angle2'));
  AssertNear('second start handle points right', 0, Second.PropertyValue('angle1'));
  AssertNull('curved parts have no angle', FPattern.AddFreePoint('', 'Curve_A_M.angle', '0'));
  AssertEquals(Format(rsFormulaUnknownProperty, ['Curve_A_M', 'angle']), FPattern.LastError);
end;

procedure TTestEdges.TestSplitPathAtNode;
var
  Path: TCurvePathObject;
  First, Second: TSplitPart;
begin
  Path := TestPath;
  AssertTrue(FPattern.SplitEdge(Path.Key, Key('B'), First, Second));
  AssertEquals('Path_A_B', First.Name);
  FPattern.Evaluate;
  AssertValidEdge('first', First);
  AssertEquals('first is one segment', 1, Length(First.Segments));
  AssertNear('first', SEGMENT_LENGTH, First.Length, 1e-6);
  AssertNear('second', SEGMENT_LENGTH, Second.Length, 1e-6);
end;

procedure TTestEdges.TestSplitPartAgain;
var
  Line: TLineObject;
  P, Q: TPointObject;
  First, Second, Third, Fourth: TSplitPart;
begin
  Line := BaseLine;
  P := TPointObject(Check(FPattern.AddAlongEdgePoint('P', Line.Key, False, amLength, '30')));
  FPattern.SplitEdge(Line.Key, P.Key, First, Second);
  Q := TPointObject(Check(FPattern.AddAlongEdgePoint('Q', Second.Key, False, amLength, '20')));
  AssertTrue(FPattern.SplitEdge(Second.Key, Q.Key, Third, Fourth));
  AssertEquals('Line_P_Q', Third.Name);
  FPattern.Evaluate;
  AssertNear('third', 20, Third.Length);
  AssertNear('fourth', 50, Fourth.Length);
  AssertNear('still straight', 0, Fourth.PropertyValue('angle'));
end;

procedure TTestEdges.TestSplitPartsCross;
var
  Line: TLineObject;
  P: TPointObject;
  First, Second: TSplitPart;
  Down: TLineObject;
  OnFirst, OnSecond: TPointObject;
begin
  Line := BaseLine;
  P := TPointObject(Check(FPattern.AddAlongEdgePoint('P', Line.Key, False, amLength, '30')));
  FPattern.SplitEdge(Line.Key, P.Key, First, Second);
  Pt('U', 60, 50);
  Pt('D', 60, -50);
  Down := TLineObject(Check(FPattern.AddLine(Key('U'), Key('D'))));
  OnFirst := TPointObject(Check(FPattern.AddIntersectPoint('X1', First.Key, Down.Key, False, False, 1)));
  OnSecond := TPointObject(Check(FPattern.AddIntersectPoint('X2', Second.Key, Down.Key, False, False, 1)));
  FPattern.Evaluate;
  AssertTrue('x = 60 is not on the first part', OnFirst.State = esInvalid);
  AssertAt('on the second part', OnSecond, 60, 0);
end;

procedure TTestEdges.TestSplitChecks;
var
  Line: TLineObject;
  First, Second: TSplitPart;
begin
  Line := BaseLine;
  AssertFalse('point as edge', FPattern.SplitEdge(Key('A'), Key('B'), First, Second));
  AssertFalse('line as point', FPattern.SplitEdge(Line.Key, Line.Key, First, Second));
  AssertEquals(Format(rsDraftNotAPoint, ['Line_A_B']), FPattern.LastError);
  AssertNull(First);
end;

procedure TTestEdges.TestLinesHaveEndAngles;
var
  Line: TLineObject;
begin
  Line := BaseLine;
  FPattern.Evaluate;
  AssertNear('angle1', 0, Line.PropertyValue('angle1'));
  AssertNear('angle2 points back', 180, Line.PropertyValue('angle2'));
end;

initialization
  RegisterTest(TTestEdges);

end.
