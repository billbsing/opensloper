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
    procedure TestOffsetPolar;
    procedure TestOffsetCartesian;
    procedure TestAlongEdge;
    procedure TestNegativeLiteralCanDrag;
    procedure TestFormulaIsLocked;
    procedure TestPlacedPointCannotDrag;
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
  if Obj = nil then
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
  Pt('A', '10', '10');
  B := TPointObject(Check(FPattern.AddOffsetPoint('B', '1', omPolar, '5', '0')));
  FPattern.Evaluate;
  Drag(B, 40, 50);
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

initialization
  RegisterTest(TTestDrag);

end.
