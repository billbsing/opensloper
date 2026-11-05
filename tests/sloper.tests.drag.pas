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

// Dragging points: which can move, and the plain numbers a drag writes.
unit Sloper.Tests.Drag;

{$mode ObjFPC}{$H+}

interface

uses
  fpcunit, testregistry, Sloper.Tests.TestCase, Sloper.Core.Measurements, Sloper.Core.Draft, Sloper.Core.Pattern;

type
  TTestDrag = class(TOSTestCase)
  private
    FSet: TMeasurementSet;
    FPattern: TPattern;
    function Check(Obj: TObject): TObject;
    function Pt(const AName, X, Y: string): TPointObject;
    procedure Drag(Point: TPointObject; X, Y: double);
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestFreePoint;
    procedure TestDragKeepsUnitSuffix;
    procedure TestHandleWithUnitAtAnchor;
    procedure TestOffsetPolar;
    procedure TestOffsetCartesian;
    procedure TestAlongEdge;
    procedure TestNegativeLiteralCanDrag;
    procedure TestFormulaIsLocked;
    procedure TestPlacedPointCannotDrag;
    procedure TestCurveHandles;
    procedure TestDragStartHandle;
    procedure TestDragEndHandle;
    procedure TestHandleAtAnchorKeepsAngle;
    procedure TestFormulaHandleIsLocked;
    procedure TestPathHandles;
    procedure TestDragPathHandleRotatesBothSides;
    procedure TestOnlyCurvesHaveHandles;
    procedure TestSplitPartHasNoHandles;
  end;

implementation

uses
  SysUtils, Sloper.Core.Geometry, Sloper.Core.Drag;

procedure TTestDrag.SetUp;
begin
  FSet := TMeasurementSet.Create;
  FSet.Add('waist', 720);
  FPattern := TPattern.Create;
  FPattern.Measurements := FSet;
end;

procedure TTestDrag.TearDown;
begin
  FreeAndNil(FPattern);
  FreeAndNil(FSet);
end;

function TTestDrag.Check(Obj: TObject): TObject;
begin
  if not Assigned(Obj) then
    Fail('Refused: ' + FPattern.LastError);
  Result := Obj;
end;

function TTestDrag.Pt(const AName, X, Y: string): TPointObject;
begin
  Result := TPointObject(Check(FPattern.AddFreePoint(AName, X, Y)));
end;

procedure TTestDrag.Drag(Point: TPointObject; X, Y: double);
var
  Err: string;
begin
  if not DragPoint(FPattern, Point, Vec2(X, Y), Err) then
    Fail('Drag refused: ' + Err);
  FPattern.Evaluate;
end;

procedure TTestDrag.TestFreePoint;
var
  A: TPointObject;
begin
  A := Pt('A', '0', '0');
  FPattern.Evaluate;
  Drag(A, 12.345, -6.78);
  AssertEquals('rounded to 0.1 mm', '12.3', FPattern.FormulaText(A, 'x'));
  AssertEquals('-6.8', FPattern.FormulaText(A, 'y'));
  AssertPointsNear('moved', Vec2(12.3, -6.8), A.Position);
end;

procedure TTestDrag.TestOffsetPolar;
var
  B: TPointObject;
begin
  Pt('A', '10', '-10');
  B := TPointObject(Check(FPattern.AddOffsetPoint('B', '1', omPolar, '5', '0')));
  FPattern.Evaluate;
  Drag(B, 40, -50);
  AssertEquals('length', '50', FPattern.FormulaText(B, 'length'));
  AssertEquals('angle', '53.1', FPattern.FormulaText(B, 'angle'));
end;

procedure TTestDrag.TestOffsetCartesian;
var
  B: TPointObject;
begin
  Pt('A', '10', '10');
  B := TPointObject(Check(FPattern.AddOffsetPoint('B', '1', omCartesian, '5', '0')));
  FPattern.Evaluate;
  Drag(B, 40, -5);
  AssertEquals('dx', '30', FPattern.FormulaText(B, 'dx'));
  AssertEquals('dy', '-15', FPattern.FormulaText(B, 'dy'));
end;

// A point along an edge slides along it, measured from its own end
procedure TTestDrag.TestAlongEdge;
var
  Edge: TLineObject;
  FromStart, FromEnd, Ratio: TPointObject;
begin
  Pt('A', '0', '0');
  Pt('B', '200', '0');
  Edge := TLineObject(Check(FPattern.AddLine('1', '2')));
  FromStart := TPointObject(Check(FPattern.AddAlongEdgePoint('C', Edge.Key, False, amLength, '10')));
  FromEnd := TPointObject(Check(FPattern.AddAlongEdgePoint('D', Edge.Key, True, amLength, '10')));
  Ratio := TPointObject(Check(FPattern.AddAlongEdgePoint('E', Edge.Key, False, amRatio, '0.1')));
  FPattern.Evaluate;
  Drag(FromStart, 50, 30);
  AssertEquals('from start', '50', FPattern.FormulaText(FromStart, 'value'));
  AssertPointsNear('stays on the edge', Vec2(50, 0), FromStart.Position);
  Drag(FromEnd, 50, -30);
  AssertEquals('from end', '150', FPattern.FormulaText(FromEnd, 'value'));
  Drag(Ratio, 50, 0);
  AssertEquals('ratio', '0.25', FPattern.FormulaText(Ratio, 'value'));
end;

procedure TTestDrag.TestNegativeLiteralCanDrag;
var
  A: TPointObject;
  Err: string;
begin
  A := Pt('A', '-5', '-0.5');
  AssertTrue(Err, CanDrag(A, Err));
end;

procedure TTestDrag.TestFormulaIsLocked;
var
  B: TPointObject;
  Err: string;
begin
  Pt('A', '0', '0');
  B := TPointObject(Check(FPattern.AddOffsetPoint('B', '1', omPolar, '@waist / 4', '0')));
  FPattern.Evaluate;
  AssertFalse(CanDrag(B, Err));
  AssertEquals(Format(rsDragFormula, ['B']), Err);
  AssertFalse('drag refused', DragPoint(FPattern, B, Vec2(1, 1), Err));
  AssertEquals('formula kept', '@waist / 4', FPattern.FormulaText(B, 'length'));
end;

procedure TTestDrag.TestPlacedPointCannotDrag;
var
  Crossing: TPointObject;
  Err: string;
begin
  Pt('A', '0', '0');
  Pt('B', '10', '10');
  Pt('C', '0', '10');
  Pt('D', '10', '0');
  Check(FPattern.AddLine('1', '2'));
  Check(FPattern.AddLine('3', '4'));
  Crossing := TPointObject(Check(FPattern.AddIntersectPoint('X', '5', '6', False, False, 1)));
  AssertFalse(CanDrag(Crossing, Err));
  AssertEquals(Format(rsDragPlaced, ['X']), Err);
end;

procedure TTestDrag.TestCurveHandles;
var
  Curve: TCurveObject;
  Handles: TCurveHandleArray;
begin
  Pt('A', '0', '0');
  Pt('B', '100', '0');
  Curve := TCurveObject(Check(FPattern.AddCurve('1', '2', '90', '30', '90', '40')));
  FPattern.Evaluate;
  Handles := CurveHandles(Curve);
  AssertEquals(2, Length(Handles));
  AssertPointsNear('start anchor', Vec2(0, 0), Handles[0].Anchor);
  AssertPointsNear('start handle', Vec2(0, -30), Handles[0].Position);
  AssertPointsNear('end anchor', Vec2(100, 0), Handles[1].Anchor);
  AssertPointsNear('end handle', Vec2(100, -40), Handles[1].Position);
end;

procedure TTestDrag.TestDragStartHandle;
var
  Curve: TCurveObject;
  Err: string;
begin
  Pt('A', '0', '0');
  Pt('B', '100', '0');
  Curve := TCurveObject(Check(FPattern.AddCurve('1', '2', '90', '30', '90', '40')));
  FPattern.Evaluate;
  AssertTrue(Err, DragHandle(FPattern, Curve, CurveHandles(Curve)[0], Vec2(30, -40), Err));
  FPattern.Evaluate;
  AssertEquals('length', '50', FPattern.FormulaText(Curve, 'length1'));
  AssertEquals('angle', '53.1', FPattern.FormulaText(Curve, 'angle1'));
  AssertEquals('other handle untouched', '40', FPattern.FormulaText(Curve, 'length2'));
end;

procedure TTestDrag.TestDragEndHandle;
var
  Curve: TCurveObject;
  Err: string;
begin
  Pt('A', '0', '0');
  Pt('B', '100', '0');
  Curve := TCurveObject(Check(FPattern.AddCurve('1', '2', '90', '30', '90', '40')));
  FPattern.Evaluate;
  AssertTrue(Err, DragHandle(FPattern, Curve, CurveHandles(Curve)[1], Vec2(100, 25), Err));
  FPattern.Evaluate;
  AssertEquals('below the end, angles stay positive', '270', FPattern.FormulaText(Curve, 'angle2'));
  AssertPointsNear('handle follows', Vec2(100, 25), CurveHandles(Curve)[1].Position);
end;

procedure TTestDrag.TestHandleAtAnchorKeepsAngle;
var
  Curve: TCurveObject;
  Err: string;
begin
  Pt('A', '0', '0');
  Pt('B', '100', '0');
  Curve := TCurveObject(Check(FPattern.AddCurve('1', '2', '90', '30', '90', '40')));
  FPattern.Evaluate;
  AssertTrue(Err, DragHandle(FPattern, Curve, CurveHandles(Curve)[0], Vec2(0.01, 0), Err));
  AssertEquals('length', '0', FPattern.FormulaText(Curve, 'length1'));
  AssertEquals('angle kept', '90', FPattern.FormulaText(Curve, 'angle1'));
end;

procedure TTestDrag.TestFormulaHandleIsLocked;
var
  Curve: TCurveObject;
  Handles: TCurveHandleArray;
  Err: string;
begin
  Pt('A', '0', '0');
  Pt('B', '100', '0');
  Curve := TCurveObject(Check(FPattern.AddCurve('1', '2', '90', '@waist / 6', '90', '40')));
  FPattern.Evaluate;
  Handles := CurveHandles(Curve);
  AssertFalse('a formula locks it', CanDragHandle(Curve, Handles[0], Err));
  AssertEquals(Format(rsDragHandleFormula, [Curve.DisplayName]), Err);
  AssertFalse('drag refused', DragHandle(FPattern, Curve, Handles[0], Vec2(5, 5), Err));
  AssertEquals('formula kept', '@waist / 6', FPattern.FormulaText(Curve, 'length1'));
  AssertTrue('the other handle is free', CanDragHandle(Curve, Handles[1], Err));
end;

procedure TTestDrag.TestPathHandles;
var
  Path: TCurvePathObject;
  Handles: TCurveHandleArray;
begin
  Pt('A', '0', '0');
  Pt('B', '100', '-100');
  Pt('C', '200', '0');
  Path := TCurvePathObject(Check(FPattern.AddCurvePath(['1', '2', '3'], ['90', '0', '270'], ['', '50', '20'], ['30', '40', ''])));
  FPattern.Evaluate;
  Handles := CurveHandles(Path);
  AssertEquals('none beyond the ends', 4, Length(Handles));
  AssertPointsNear('out of A', Vec2(0, -30), Handles[0].Position);
  AssertPointsNear('into B, back along the tangent', Vec2(50, -100), Handles[1].Position);
  AssertPointsNear('out of B', Vec2(140, -100), Handles[2].Position);
  AssertPointsNear('into C', Vec2(200, -20), Handles[3].Position);
  AssertEquals('node2.lengthIn', Handles[1].LengthField);
end;

procedure TTestDrag.TestDragPathHandleRotatesBothSides;
var
  Path: TCurvePathObject;
  Err: string;
  Handles: TCurveHandleArray;
begin
  Pt('A', '0', '0');
  Pt('B', '100', '-100');
  Pt('C', '200', '0');
  Path := TCurvePathObject(Check(FPattern.AddCurvePath(['1', '2', '3'], ['90', '0', '270'], ['', '50', '20'], ['30', '40', ''])));
  FPattern.Evaluate;
  // The handle into B, dragged to directly above B
  AssertTrue(Err, DragHandle(FPattern, Path, CurveHandles(Path)[1], Vec2(100, -160), Err));
  FPattern.Evaluate;
  AssertEquals('the shared tangent turns', '270', FPattern.FormulaText(Path, 'node2.angle'));
  AssertEquals('this length', '60', FPattern.FormulaText(Path, 'node2.lengthIn'));
  AssertEquals('the other length stays', '40', FPattern.FormulaText(Path, 'node2.lengthOut'));
  Handles := CurveHandles(Path);
  AssertPointsNear('dragged', Vec2(100, -160), Handles[1].Position);
  AssertPointsNear('the other side stays opposite', Vec2(100, -60), Handles[2].Position);
end;

procedure TTestDrag.TestOnlyCurvesHaveHandles;
var
  Line: TLineObject;
begin
  Pt('A', '0', '0');
  Pt('B', '100', '0');
  Line := TLineObject(Check(FPattern.AddLine('1', '2')));
  FPattern.Evaluate;
  AssertEquals(0, Length(CurveHandles(Line)));
end;

procedure TTestDrag.TestSplitPartHasNoHandles;
var
  Curve: TCurveObject;
  Middle: TPointObject;
  First, Second: TSplitPart;
begin
  Pt('A', '0', '0');
  Pt('B', '100', '0');
  Curve := TCurveObject(Check(FPattern.AddCurve('1', '2', '90', '30', '90', '40')));
  Middle := TPointObject(Check(FPattern.AddAlongEdgePoint('M', Curve.Key, False, amRatio, '0.5')));
  AssertTrue(FPattern.LastError, FPattern.SplitEdge(Curve.Key, Middle.Key, First, Second));
  FPattern.Evaluate;
  AssertEquals(0, Length(CurveHandles(First)));
end;

procedure TTestDrag.TestDragKeepsUnitSuffix;
var
  A, B: TPointObject;
begin
  A := Pt('A', '1in', '2cm');
  FPattern.Evaluate;
  AssertPointsNear('read in mm', Vec2(25.4, 20), A.Position);
  Drag(A, 50.9, 33.33);
  AssertEquals('inches, to 0.01 in', '2in', FPattern.FormulaText(A, 'x'));
  AssertEquals('centimetres, to 0.1 cm', '3.3cm', FPattern.FormulaText(A, 'y'));
  B := TPointObject(Check(FPattern.AddOffsetPoint('B', '1', omPolar, '1in', '0')));
  FPattern.Evaluate;
  Drag(B, 50.8 + 50.8, 33);
  AssertEquals('polar length', '2in', FPattern.FormulaText(B, 'length'));
end;

procedure TTestDrag.TestHandleWithUnitAtAnchor;
var
  Curve: TCurveObject;
  Err: string;
begin
  Pt('A', '0', '0');
  Pt('B', '100', '0');
  Curve := TCurveObject(Check(FPattern.AddCurve('1', '2', '90', '1in', '90', '40')));
  FPattern.Evaluate;
  AssertTrue(Err, DragHandle(FPattern, Curve, CurveHandles(Curve)[0], Vec2(0.01, 0), Err));
  AssertEquals('length', '0in', FPattern.FormulaText(Curve, 'length1'));
  AssertEquals('angle kept', '90', FPattern.FormulaText(Curve, 'angle1'));
end;

initialization
  RegisterTest(TTestDrag);

end.
