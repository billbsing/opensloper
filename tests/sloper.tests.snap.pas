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

// Snapping: what a click finds, in priority order, and the operation it records.
// The drawing: A (0, 0), B (100, 0), C (50, -50), D (50, 50); Line_A_B
// along the x axis and Line_C_D crossing it at (50, 0).
unit Sloper.Tests.Snap;

{$mode ObjFPC}{$H+}

interface

uses
  fpcunit, testregistry, Sloper.Tests.TestCase, Sloper.Core.Pattern, Sloper.UI.Snap;

type
  TTestSnap = class(TOSTestCase)
  private
    FPattern: TPattern;
    function Snap(X, Y: double; const AnchorKey: string = ''): TSnap;
    procedure AssertMakes(const Msg: string; const ASnap: TSnap; const TypeName: string; X, Y: double);
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestPointComesFirst;
    procedure TestCrossing;
    procedure TestOnEdge;
    procedure TestOnEdgeFromNearerEnd;
    procedure TestHorizontal;
    procedure TestVertical;
    procedure TestAnchorComesFirst;
    procedure TestFree;
    procedure TestSplitPartsDoNotCross;
    procedure TestDescriptions;
    procedure TestObjectKeys;
    procedure TestCircleOnExistingPoint;
    procedure TestCircleMakesItsCentre;
    procedure TestCircleTooSmall;
    procedure TestRectangleFromCorner;
    procedure TestRectangleEitherWay;
    procedure TestRectangleTooThin;
    procedure TestInPatternUnit;
  end;

implementation

uses
  SysUtils, Sloper.Core.Geometry, Sloper.Core.Draft, Sloper.Core.Units;

const
  RADIUS = 2;

procedure TTestSnap.SetUp;
begin
  FPattern := TPattern.Create;
  FPattern.AddFreePoint('A', '0', '0');
  FPattern.AddFreePoint('B', '100', '0');
  FPattern.AddFreePoint('C', '50', '50');
  FPattern.AddFreePoint('D', '50', '-50');
  FPattern.AddLine('1', '2');
  FPattern.AddLine('3', '4');
  FPattern.Evaluate;
end;

procedure TTestSnap.TearDown;
begin
  FreeAndNil(FPattern);
end;

function TTestSnap.Snap(X, Y: double; const AnchorKey: string): TSnap;
begin
  Result := FindSnap(FPattern, Vec2(X, Y), RADIUS, AnchorKey);
end;

// The snap adds a point of the expected operation, which evaluates to X, Y
procedure TTestSnap.AssertMakes(const Msg: string; const ASnap: TSnap; const TypeName: string; X, Y: double);
var
  Key: string;
  Added: TPointObject;
begin
  Key := PointFromSnap(FPattern, ASnap);
  if Key = '' then
    Fail(Msg + ': refused: ' + FPattern.LastError);
  FPattern.Evaluate;
  Added := TPointObject(FPattern.FindNode(Key));
  AssertEquals(Msg + ' operation', TypeName, Added.ClassName);
  AssertPointsNear(Msg + ' position', Vec2(X, Y), Added.Position);
end;

procedure TTestSnap.TestPointComesFirst;
var
  Result: TSnap;
begin
  Result := Snap(99, 1);
  AssertTrue('point', Result.Kind = snPoint);
  AssertEquals('2', Result.PointKey);
  AssertEquals('reused, not added', '2', PointFromSnap(FPattern, Result));
  AssertEquals('nothing added', 6, FPattern.ObjectCount);
end;

procedure TTestSnap.TestCrossing;
var
  Result: TSnap;
begin
  Result := Snap(50.6, 0.7);
  AssertTrue('crossing', Result.Kind = snCrossing);
  AssertEquals('first edge', '5', Result.EdgeKey);
  AssertEquals('second edge', '6', Result.OtherEdgeKey);
  AssertEquals('pick', 1, Result.Pick);
  AssertMakes('crossing', Result, 'TIntersectPoint', 50, 0);
end;

procedure TTestSnap.TestOnEdge;
var
  Result: TSnap;
begin
  Result := Snap(20.04, 1);
  AssertTrue('edge', Result.Kind = snEdge);
  AssertEquals('5', Result.EdgeKey);
  AssertFalse('from the start', Result.FromEnd);
  AssertNear('distance', 20.04, Result.Distance);
  AssertMakes('on edge, rounded to 0.1 mm', Result, 'TAlongEdgePoint', 20, 0);
end;

procedure TTestSnap.TestOnEdgeFromNearerEnd;
var
  Result: TSnap;
begin
  Result := Snap(70, -1.5);
  AssertTrue('edge', Result.Kind = snEdge);
  AssertTrue('from the end', Result.FromEnd);
  AssertNear('distance', 30, Result.Distance);
  AssertMakes('from the end', Result, 'TAlongEdgePoint', 70, 0);
end;

procedure TTestSnap.TestHorizontal;
var
  Result: TSnap;
begin
  Result := Snap(130, 0.8);
  AssertTrue('level', Result.Kind = snHorizontal);
  AssertEquals('the nearer of A and B', '2', Result.PointKey);
  AssertNear('distance', 30, Result.Distance);
  AssertNear('to the right', 0, Result.Angle);
  AssertMakes('right of B', Result, 'TOffsetPoint', 130, 0);
  Result := Snap(-40, -1);
  AssertNear('to the left', 180, Result.Angle);
  AssertMakes('left of A', Result, 'TOffsetPoint', -40, 0);
end;

procedure TTestSnap.TestVertical;
var
  Result: TSnap;
begin
  Result := Snap(50.5, -80);
  AssertTrue('square', Result.Kind = snVertical);
  AssertEquals('above D', '4', Result.PointKey);
  AssertNear('distance', 30, Result.Distance);
  AssertNear('up', 90, Result.Angle);
  AssertMakes('above D', Result, 'TOffsetPoint', 50, -80);
end;

procedure TTestSnap.TestAnchorComesFirst;
var
  Result: TSnap;
begin
  // Square to A (0.9 mm off) and level with C (0.4 mm off): C lines up
  // better, but a line from A lines up with A first
  Result := Snap(0.9, 49.6, '1');
  AssertTrue('square to the anchor', Result.Kind = snVertical);
  AssertEquals('1', Result.PointKey);
  Result := Snap(0.9, 49.6);
  AssertTrue('level with C without an anchor', Result.Kind = snHorizontal);
  AssertEquals('3', Result.PointKey);
end;

procedure TTestSnap.TestFree;
var
  Result: TSnap;
begin
  Result := Snap(200.04, 200);
  AssertTrue('free', Result.Kind = snFree);
  AssertMakes('free, rounded', Result, 'TFreePoint', 200, 200);
end;

procedure TTestSnap.TestSplitPartsDoNotCross;
var
  First, Second: TSplitPart;
  Result: TSnap;
begin
  FPattern.AddAlongEdgePoint('F', '5', False, amLength, '25');
  FPattern.Evaluate;
  AssertTrue(FPattern.SplitEdge('5', FPattern.FindObject('F').Key, First, Second));
  FPattern.Evaluate;
  Result := Snap(12, 0.5);
  AssertTrue('on an edge, not a crossing of an edge with its own part', Result.Kind = snEdge);
end;

procedure TTestSnap.TestDescriptions;
begin
  AssertEquals(Format(rsSnapPoint, ['B']), SnapDescription(FPattern, Snap(99, 1)));
  AssertEquals(Format(rsSnapCrossing, ['Line_A_B', 'Line_C_D']), SnapDescription(FPattern, Snap(50.6, 0.7)));
  AssertEquals(Format(rsSnapEdge, ['Line_A_B', '30 mm', 'B']), SnapDescription(FPattern, Snap(70, -1.5)));
  AssertEquals(Format(rsSnapRight, ['30 mm', 'B']), SnapDescription(FPattern, Snap(130, 0.8)));
  AssertEquals(Format(rsSnapUp, ['30 mm', 'D']), SnapDescription(FPattern, Snap(50.5, -80)));
  AssertEquals(Format(rsSnapFree, ['200', '200']), SnapDescription(FPattern, Snap(200, 200)));
end;

procedure TTestSnap.TestObjectKeys;
begin
  AssertEquals('a point', '2', string.Join(' ', SnapObjectKeys(Snap(99, 0))));
  AssertEquals('a crossing', '5 6', string.Join(' ', SnapObjectKeys(Snap(50, 0.5))));
  AssertEquals('an edge', '5', string.Join(' ', SnapObjectKeys(Snap(25, 0.5))));
  AssertEquals('lines up with a point', '4', string.Join(' ', SnapObjectKeys(Snap(50, -60))));
  AssertEquals('free', '', string.Join(' ', SnapObjectKeys(Snap(200, 200))));
end;

procedure TTestSnap.TestCircleOnExistingPoint;
var
  Circle: TCircleObject;
  Count: integer;
begin
  Count := FPattern.ObjectCount;
  Circle := CircleFromSnap(FPattern, Snap(0.5, 0.5), Vec2(30.04, 40), erOutline);
  AssertNotNull(FPattern.LastError, Circle);
  AssertEquals('on A', '1', Circle.Centre);
  AssertEquals('rounded to 0.1 mm', '50', FPattern.FormulaText(Circle, 'radius'));
  AssertEquals('only the circle', Count + 1, FPattern.ObjectCount);
end;

procedure TTestSnap.TestCircleMakesItsCentre;
var
  Circle: TCircleObject;
begin
  Circle := CircleFromSnap(FPattern, Snap(200, 200), Vec2(200, 225), erStitch);
  AssertNotNull(FPattern.LastError, Circle);
  FPattern.Evaluate;
  AssertPointsNear('a new free point', Vec2(200, 200), TPointObject(FPattern.FindNode(Circle.Centre)).Position);
  AssertEquals(25, Circle.PropertyValue('radius'), 1e-9);
  AssertTrue(Circle.Role = erStitch);
end;

procedure TTestSnap.TestCircleTooSmall;
var
  Count: integer;
begin
  Count := FPattern.ObjectCount;
  AssertNull(CircleFromSnap(FPattern, Snap(200, 200), Vec2(200.02, 200), erOutline));
  AssertEquals(rsSnapTooSmall, FPattern.LastError);
  AssertEquals('no centre left behind', Count, FPattern.ObjectCount);
end;

procedure TTestSnap.TestRectangleFromCorner;
var
  Edges: TRectangleEdges;
begin
  AssertTrue(FPattern.LastError, RectangleFromSnap(FPattern, Snap(200, 200), Vec2(320, 260.04), erOutline, Edges));
  FPattern.Evaluate;
  AssertPointsNear('across', Vec2(320, 200), Edges[0].PointAtLength(Edges[0].Length));
  AssertPointsNear('opposite', Vec2(320, 260), Edges[1].PointAtLength(Edges[1].Length));
end;

// Up and to the left of the corner works too
procedure TTestSnap.TestRectangleEitherWay;
var
  Edges: TRectangleEdges;
begin
  AssertTrue(FPattern.LastError, RectangleFromSnap(FPattern, Snap(200, 200), Vec2(150, 170), erOutline, Edges));
  FPattern.Evaluate;
  AssertPointsNear('opposite', Vec2(150, 170), Edges[1].PointAtLength(Edges[1].Length));
end;

procedure TTestSnap.TestRectangleTooThin;
var
  Edges: TRectangleEdges;
  Count: integer;
begin
  Count := FPattern.ObjectCount;
  AssertFalse(RectangleFromSnap(FPattern, Snap(200, 200), Vec2(300, 200.01), erOutline, Edges));
  AssertEquals(rsSnapTooSmall, FPattern.LastError);
  AssertEquals(Count, FPattern.ObjectCount);
end;

// In a cm pattern the read-outs and the formulas written are in cm
procedure TTestSnap.TestInPatternUnit;
var
  Key: string;
  Circle: TCircleObject;
begin
  FPattern.Units := muCentimetre;
  FPattern.Evaluate;
  // B is now at 1000 mm
  AssertEquals(Format(rsSnapEdge, ['Line_A_B', '30 cm', 'B']), SnapDescription(FPattern, Snap(700, -1.5)));
  Key := PointFromSnap(FPattern, Snap(700, -1.5));
  AssertEquals('length along, in cm', '30', FPattern.FormulaText(TDraftObject(FPattern.FindNode(Key)), 'value'));
  Circle := CircleFromSnap(FPattern, Snap(0.5, 0.5), Vec2(0, 123), erConstruction);
  AssertNotNull(FPattern.LastError, Circle);
  AssertEquals('radius to 0.1 cm', '12.3', FPattern.FormulaText(Circle, 'radius'));
  AssertNull('under 0.05 cm is nothing', CircleFromSnap(FPattern, Snap(0.5, 0.5), Vec2(0, 0.4), erConstruction));
end;

initialization
  RegisterTest(TTestSnap);

end.
