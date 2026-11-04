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

// Intersect edges, circle x edge and project onto edge. The curve used
// throughout runs from (0, 0) to (100, 0) with both handles straight up and
// 100 mm long: x = 300t^2 - 200t^3, y = 300t(1 - t). It passes (15.625, 56.25)
// at t = 0.25, (50, 75) at t = 0.5 and (84.375, 56.25) at t = 0.75.
unit Sloper.Tests.Operations;

{$mode ObjFPC}{$H+}

interface

uses
  fpcunit, testregistry, Sloper.Tests.TestCase, Sloper.Core.Geometry, Sloper.Core.EvalTypes, Sloper.Core.Measurements,
  Sloper.Core.Draft, Sloper.Core.Pattern;

type
  TTestOperations = class(TOSTestCase)
  private
    FSet: TMeasurementSet;
    FPattern: TPattern;
    function Pt(const AName: string; X, Y: double): TPointObject;
    function Line(const FromName, ToName: string): TEdgeObject;
    function Arch: TEdgeObject;
    function Check(Obj: TObject): TObject;
    procedure AssertAt(const Msg: string; P: TPointObject; X, Y: double);
    procedure AssertInvalid(const Msg: string; P: TPointObject; const Expected: string);
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestLinesCross;
    procedure TestParallelLinesDoNotCross;
    procedure TestExtendLines;
    procedure TestLineCrossesCurveTwice;
    procedure TestPickFollowsFirstEdge;
    procedure TestCurveExtendsAlongTangents;
    procedure TestCurvesCross;
    procedure TestCompassStepOnLine;
    procedure TestCircleOnExtendedLine;
    procedure TestCircleCrossesLineTwice;
    procedure TestCircleOnCurve;
    procedure TestNegativeRadiusIsInvalid;
    procedure TestProjectSquareOntoLine;
    procedure TestProjectAtAngle;
    procedure TestProjectOntoCurve;
    procedure TestProjectTakesNearest;
    procedure TestPatternChecks;
    procedure TestFollowsInputs;
  end;

implementation

uses
  SysUtils, Sloper.Core.Evaluator;

procedure TTestOperations.SetUp;
begin
  FSet := TMeasurementSet.Create;
  FSet.Add('waist', 720);
  FPattern := TPattern.Create;
  FPattern.Measurements := FSet;
end;

procedure TTestOperations.TearDown;
begin
  FreeAndNil(FPattern);
  FreeAndNil(FSet);
end;

function TTestOperations.Check(Obj: TObject): TObject;
begin
  if not Assigned(Obj) then
    Fail('Refused: ' + FPattern.LastError);
  Result := Obj;
end;

function TTestOperations.Pt(const AName: string; X, Y: double): TPointObject;
begin
  Result := TPointObject(Check(FPattern.AddFreePoint(AName, FloatToStr(X), FloatToStr(Y))));
end;

function TTestOperations.Line(const FromName, ToName: string): TEdgeObject;
begin
  Result := TEdgeObject(Check(FPattern.AddLine(FPattern.FindObject(FromName).Key,
    FPattern.FindObject(ToName).Key)));
end;

// The arch curve from A0 (0, 0) to A1 (100, 0)
function TTestOperations.Arch: TEdgeObject;
begin
  Pt('A0', 0, 0);
  Pt('A1', 100, 0);
  Result := TEdgeObject(Check(FPattern.AddCurve(FPattern.FindObject('A0').Key,
    FPattern.FindObject('A1').Key, '90', '100', '90', '100')));
end;

procedure TTestOperations.AssertAt(const Msg: string; P: TPointObject; X, Y: double);
begin
  AssertTrue(Msg + ' state: ' + P.Message, P.State = esValid);
  AssertPointsNear(Msg, Vec2(X, Y), P.Position);
end;

procedure TTestOperations.AssertInvalid(const Msg: string; P: TPointObject;
  const Expected: string);
begin
  AssertTrue(Msg + ' invalid', P.State = esInvalid);
  AssertEquals(Msg + ' message', Expected, P.Message);
end;

procedure TTestOperations.TestLinesCross;
var
  First, Second: TEdgeObject;
  X: TPointObject;
begin
  Pt('A', 0, 0);
  Pt('B', 100, 0);
  Pt('C', 0, 100);
  Pt('D', 100, 100);
  First := Line('A', 'D');
  Second := Line('C', 'B');
  X := TPointObject(Check(FPattern.AddIntersectPoint('X', First.Key, Second.Key, False, False, 1)));
  FPattern.Evaluate;
  AssertAt('X', X, 50, 50);
end;

procedure TTestOperations.TestParallelLinesDoNotCross;
var
  First, Second: TEdgeObject;
  X: TPointObject;
begin
  Pt('A', 0, 0);
  Pt('B', 100, 0);
  Pt('C', 0, 10);
  Pt('D', 100, 10);
  First := Line('A', 'B');
  Second := Line('C', 'D');
  X := TPointObject(Check(FPattern.AddIntersectPoint('X', First.Key, Second.Key, True, True, 1)));
  FPattern.Evaluate;
  AssertInvalid('parallel', X, Format(rsDraftNoCrossing, ['Line_A_B', 'Line_C_D']));
end;

procedure TTestOperations.TestExtendLines;
var
  First, Second: TEdgeObject;
  Neither, OnlyFirst, Both: TPointObject;
begin
  Pt('A', 0, 0);
  Pt('B', 10, 0);
  Pt('C', 50, 10);
  Pt('D', 50, 20);
  First := Line('A', 'B');
  Second := Line('C', 'D');
  Neither := TPointObject(Check(FPattern.AddIntersectPoint('N', First.Key, Second.Key, False, False, 1)));
  OnlyFirst := TPointObject(Check(FPattern.AddIntersectPoint('O', First.Key, Second.Key, True, False, 1)));
  Both := TPointObject(Check(FPattern.AddIntersectPoint('X', First.Key, Second.Key, True, True, 1)));
  FPattern.Evaluate;
  AssertTrue('segments', Neither.State = esInvalid);
  AssertTrue('one extended', OnlyFirst.State = esInvalid);
  AssertAt('both extended', Both, 50, 0);
end;

procedure TTestOperations.TestLineCrossesCurveTwice;
var
  Curve, Across: TEdgeObject;
  First, Second, Third: TPointObject;
begin
  Curve := Arch;
  Pt('L', -10, 56.25);
  Pt('R', 110, 56.25);
  Across := Line('L', 'R');
  First := TPointObject(Check(FPattern.AddIntersectPoint('X1', Across.Key, Curve.Key, False, False, 1)));
  Second := TPointObject(Check(FPattern.AddIntersectPoint('X2', Across.Key, Curve.Key, False, False, 2)));
  Third := TPointObject(Check(FPattern.AddIntersectPoint('X3', Across.Key, Curve.Key, False, False, 3)));
  FPattern.Evaluate;
  AssertAt('first', First, 15.625, 56.25);
  AssertAt('second', Second, 84.375, 56.25);
  AssertInvalid('third', Third, Format(rsDraftPickMissing, [2, 3]));
end;

procedure TTestOperations.TestPickFollowsFirstEdge;
var
  Curve, Backwards: TEdgeObject;
  AlongLine, AlongCurve: TPointObject;
begin
  Curve := Arch;
  Pt('L', -10, 56.25);
  Pt('R', 110, 56.25);
  Backwards := Line('R', 'L');
  AlongLine := TPointObject(Check(FPattern.AddIntersectPoint('X1', Backwards.Key, Curve.Key, False, False, 1)));
  AlongCurve := TPointObject(Check(FPattern.AddIntersectPoint('X2', Curve.Key, Backwards.Key, False, False, 1)));
  FPattern.Evaluate;
  AssertAt('first along a right-to-left line', AlongLine, 84.375, 56.25);
  AssertAt('first along the curve', AlongCurve, 15.625, 56.25);
end;

procedure TTestOperations.TestCurveExtendsAlongTangents;
var
  Curve, Below: TEdgeObject;
  Plain, StartRay, EndRay: TPointObject;
begin
  Curve := Arch;
  Pt('M', -50, -20);
  Pt('N', 150, -20);
  Below := Line('M', 'N');
  Plain := TPointObject(Check(FPattern.AddIntersectPoint('X0', Curve.Key, Below.Key, False, False, 1)));
  StartRay := TPointObject(Check(FPattern.AddIntersectPoint('X1', Curve.Key, Below.Key, True, False, 1)));
  EndRay := TPointObject(Check(FPattern.AddIntersectPoint('X2', Curve.Key, Below.Key, True, False, 2)));
  FPattern.Evaluate;
  AssertTrue('curve alone does not reach', Plain.State = esInvalid);
  // Both handles point up, so the curve continues straight down off each end
  AssertAt('before the start', StartRay, 0, -20);
  AssertAt('after the end', EndRay, 100, -20);
end;

procedure TTestOperations.TestCurvesCross;
var
  Curve, Flipped: TEdgeObject;
  First, Second: TPointObject;
begin
  Curve := Arch;
  // The arch flipped about y = 56.25: x(t) is the same, so they meet where
  // 300t(1 - t) = 56.25, at t = 0.25 and 0.75
  Pt('F0', 0, 112.5);
  Pt('F1', 100, 112.5);
  Flipped := TEdgeObject(Check(FPattern.AddCurve(FPattern.FindObject('F0').Key,
    FPattern.FindObject('F1').Key, '270', '100', '270', '100')));
  First := TPointObject(Check(FPattern.AddIntersectPoint('X1', Curve.Key, Flipped.Key, False, False, 1)));
  Second := TPointObject(Check(FPattern.AddIntersectPoint('X2', Curve.Key, Flipped.Key, False, False, 2)));
  FPattern.Evaluate;
  AssertAt('first', First, 15.625, 56.25);
  AssertAt('second', Second, 84.375, 56.25);
end;

procedure TTestOperations.TestCompassStepOnLine;
var
  Diagonal: TEdgeObject;
  Step: TPointObject;
begin
  Pt('A', 0, 0);
  Pt('D', 100, 100);
  Diagonal := Line('A', 'D');
  Step := TPointObject(Check(FPattern.AddCircleEdgePoint('S', FPattern.FindObject('A').Key,
    '@waist / 14.4', Diagonal.Key, False, 1)));
  FPattern.Evaluate;
  AssertAt('50 mm along the diagonal', Step, 35.35533905932737, 35.35533905932737);
end;

procedure TTestOperations.TestCircleOnExtendedLine;
var
  Diagonal: TEdgeObject;
  Short, Behind, Ahead: TPointObject;
  CentreKey: string;
begin
  Pt('A', 0, 0);
  Pt('D', 100, 100);
  Diagonal := Line('A', 'D');
  CentreKey := FPattern.FindObject('A').Key;
  Short := TPointObject(Check(FPattern.AddCircleEdgePoint('S', CentreKey, '200', Diagonal.Key, False, 1)));
  Behind := TPointObject(Check(FPattern.AddCircleEdgePoint('B', CentreKey, '200', Diagonal.Key, True, 1)));
  Ahead := TPointObject(Check(FPattern.AddCircleEdgePoint('F', CentreKey, '200', Diagonal.Key, True, 2)));
  FPattern.Evaluate;
  AssertInvalid('line too short', Short, Format(rsDraftCircleMisses, ['Line_A_D']));
  AssertAt('behind the start comes first', Behind, -141.4213562373095, -141.4213562373095);
  AssertAt('past the end', Ahead, 141.4213562373095, 141.4213562373095);
end;

procedure TTestOperations.TestCircleCrossesLineTwice;
var
  Base: TEdgeObject;
  First, Second: TPointObject;
begin
  Pt('A', 0, 0);
  Pt('B', 100, 0);
  Pt('M', 50, 0);
  Base := Line('A', 'B');
  First := TPointObject(Check(FPattern.AddCircleEdgePoint('C1', FPattern.FindObject('M').Key,
    '30', Base.Key, False, 1)));
  Second := TPointObject(Check(FPattern.AddCircleEdgePoint('C2', FPattern.FindObject('M').Key,
    '30', Base.Key, False, 2)));
  FPattern.Evaluate;
  AssertAt('first', First, 20, 0);
  AssertAt('second', Second, 80, 0);
end;

procedure TTestOperations.TestCircleOnCurve;
var
  Curve: TEdgeObject;
  First, Second: TPointObject;
begin
  Curve := Arch;
  Pt('M', 50, 0);
  First := TPointObject(Check(FPattern.AddCircleEdgePoint('C1', FPattern.FindObject('M').Key,
    'sqrt(34.375^2 + 56.25^2)', Curve.Key, False, 1)));
  Second := TPointObject(Check(FPattern.AddCircleEdgePoint('C2', FPattern.FindObject('M').Key,
    'sqrt(34.375^2 + 56.25^2)', Curve.Key, False, 2)));
  FPattern.Evaluate;
  AssertAt('first', First, 15.625, 56.25);
  AssertAt('second', Second, 84.375, 56.25);
end;

procedure TTestOperations.TestNegativeRadiusIsInvalid;
var
  Base: TEdgeObject;
  Step: TPointObject;
begin
  Pt('A', 0, 0);
  Pt('B', 100, 0);
  Base := Line('A', 'B');
  Step := TPointObject(Check(FPattern.AddCircleEdgePoint('S', FPattern.FindObject('A').Key,
    '-5', Base.Key, False, 1)));
  FPattern.Evaluate;
  AssertInvalid('negative', Step, rsDraftNegativeRadius);
end;

procedure TTestOperations.TestProjectSquareOntoLine;
var
  Base: TEdgeObject;
  Over, Beyond, BeyondExtended: TPointObject;
begin
  Pt('A', 0, 0);
  Pt('B', 100, 0);
  Pt('P', 30, 40);
  Pt('Q', 150, 40);
  Base := Line('A', 'B');
  Over := TPointObject(Check(FPattern.AddProjectPoint('F1', FPattern.FindObject('P').Key,
    Base.Key, pdPerpendicular, '', False)));
  Beyond := TPointObject(Check(FPattern.AddProjectPoint('F2', FPattern.FindObject('Q').Key,
    Base.Key, pdPerpendicular, '', False)));
  BeyondExtended := TPointObject(Check(FPattern.AddProjectPoint('F3', FPattern.FindObject('Q').Key,
    Base.Key, pdPerpendicular, '', True)));
  FPattern.Evaluate;
  AssertAt('foot', Over, 30, 0);
  AssertInvalid('beyond the end', Beyond, Format(rsDraftNoFoot, ['Q', 'Line_A_B']));
  AssertAt('on the extension', BeyondExtended, 150, 0);
end;

procedure TTestOperations.TestProjectAtAngle;
var
  Base: TEdgeObject;
  Down, Slanted, SlantedExtended: TPointObject;
  SourceKey: string;
begin
  Pt('A', 0, 0);
  Pt('B', 100, 0);
  Pt('P', 30, 40);
  Base := Line('A', 'B');
  SourceKey := FPattern.FindObject('P').Key;
  Down := TPointObject(Check(FPattern.AddProjectPoint('D', SourceKey, Base.Key, pdAngle, '270', False)));
  // At 225 degrees the line from P meets y = 0 at x = -10, before A
  Slanted := TPointObject(Check(FPattern.AddProjectPoint('S', SourceKey, Base.Key, pdAngle, '225', False)));
  SlantedExtended := TPointObject(Check(FPattern.AddProjectPoint('E', SourceKey, Base.Key, pdAngle, '225', True)));
  FPattern.Evaluate;
  AssertAt('straight down', Down, 30, 0);
  AssertInvalid('misses the line', Slanted, Format(rsDraftNoProjection, ['P', '225', 'Line_A_B']));
  AssertAt('meets the extension', SlantedExtended, -10, 0);
end;

procedure TTestOperations.TestProjectOntoCurve;
var
  Curve: TEdgeObject;
  Square, Down: TPointObject;
begin
  Curve := Arch;
  Pt('P', 50, 100);
  Pt('Q', 15.625, 100);
  Square := TPointObject(Check(FPattern.AddProjectPoint('F', FPattern.FindObject('P').Key,
    Curve.Key, pdPerpendicular, '', False)));
  Down := TPointObject(Check(FPattern.AddProjectPoint('D', FPattern.FindObject('Q').Key,
    Curve.Key, pdAngle, '270', False)));
  FPattern.Evaluate;
  AssertAt('foot at the top of the arch', Square, 50, 75);
  AssertAt('straight down', Down, 15.625, 56.25);
end;

procedure TTestOperations.TestProjectTakesNearest;
var
  Curve: TEdgeObject;
  Across: TPointObject;
begin
  Curve := Arch;
  // A horizontal line through P meets the arch on both sides
  Pt('P', 70, 56.25);
  Across := TPointObject(Check(FPattern.AddProjectPoint('X', FPattern.FindObject('P').Key,
    Curve.Key, pdAngle, '0', False)));
  FPattern.Evaluate;
  AssertAt('nearer crossing', Across, 84.375, 56.25);
end;

procedure TTestOperations.TestPatternChecks;
var
  Base: TEdgeObject;
  PointKey: string;
begin
  Pt('A', 0, 0);
  Pt('B', 100, 0);
  Base := Line('A', 'B');
  PointKey := FPattern.FindObject('A').Key;
  AssertNull('same edge', FPattern.AddIntersectPoint('X', Base.Key, Base.Key, False, False, 1));
  AssertEquals(rsPatternSameEdge, FPattern.LastError);
  AssertNull('pick 0', FPattern.AddCircleEdgePoint('X', PointKey, '5', Base.Key, False, 0));
  AssertEquals(rsPatternBadPick, FPattern.LastError);
  AssertNull('point as edge', FPattern.AddIntersectPoint('X', PointKey, Base.Key, False, False, 1));
  AssertEquals(Format(rsDraftNotAnEdge, ['A']), FPattern.LastError);
  AssertNull('edge as centre', FPattern.AddCircleEdgePoint('X', Base.Key, '5', Base.Key, False, 1));
  AssertNull('bad angle formula', FPattern.AddProjectPoint('X', PointKey, Base.Key, pdAngle, '90 +', False));
  AssertEquals('angle', FPattern.LastErrorField);
end;

procedure TTestOperations.TestFollowsInputs;
var
  First, Second: TEdgeObject;
  X, Above: TPointObject;
begin
  Pt('A', 0, 0);
  Pt('B', 100, 0);
  Pt('C', 0, 100);
  Pt('D', 100, 100);
  First := Line('A', 'D');
  Second := Line('C', 'B');
  X := TPointObject(Check(FPattern.AddIntersectPoint('X', First.Key, Second.Key, False, False, 1)));
  Above := TPointObject(Check(FPattern.AddOffsetPoint('Y', X.Key, omPolar, '10', '90')));
  FPattern.Evaluate;
  AssertAt('Y', Above, 50, 60);
  // Move C so the lines no longer cross within their ends
  AssertTrue(FPattern.SetFormula(FPattern.FindObject('C'), 'y', '-100'));
  FPattern.Evaluate;
  AssertTrue('X invalid', X.State = esInvalid);
  AssertTrue('Y blocked', Above.State = esBlocked);
  AssertEquals(Format(rsEvalBlocked, ['X']), Above.Message);
end;

initialization
  RegisterTest(TTestOperations);

end.
