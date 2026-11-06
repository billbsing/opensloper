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

// Offset edges along a run of edges: mitred and trimmed corners, inside and
// outside a piece, and failing when the offset collapses.
unit Sloper.Tests.OffsetRun;

{$mode ObjFPC}{$H+}

interface

uses
  SysUtils, fpcunit, testregistry, Sloper.Tests.TestCase, Sloper.Core.Geometry, Sloper.Core.Pattern, Sloper.Core.Draft,
  Sloper.Core.Piece;

type
  TTestOffsetRun = class(TOSTestCase)
  private
    FPattern, FLoaded: TPattern;
    function Pt(const AName: string; X: double = 0; Y: double = 0): string;
    function Line(const A, B: string): string;
    function Run(const Keys: array of string; const Reversed: array of boolean): TRunEdgeArray;
    // A (0, 0) to B (100, 0) to C (100, 100): right, then down the screen
    function Corner(out First, Second: string): TRunEdgeArray;
    function Square: TPieceObject;
    function RightmostX(Edge: TEdgeObject): double;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestOuterCornerMitres;
    procedure TestInnerCornerTrims;
    procedure TestReversedEdgeFollowsRun;
    procedure TestGapIsInvalid;
    procedure TestSharpCornerBevels;
    procedure TestInnerCornerTooTightCollapses;
    procedure TestTightCurveCollapses;
    procedure TestCurveWithRoomStaysValid;
    procedure TestClosedRunJoinsAtItsStart;
    procedure TestFollowsMeasurements;
    procedure TestChainOrdersEdges;
    procedure TestChainRefusesBranch;
    procedure TestPieceRunInside;
    procedure TestPieceRunOutside;
    procedure TestPieceRunWrapsRound;
    procedure TestPieceRunNeedsOneStretch;
    procedure TestInsideStitchJoinsItsPiece;
    procedure TestRunRoundTrip;
    procedure TestSingleEdgeWrittenAsBefore;
  end;

implementation

uses
  Sloper.Core.EvalTypes, Sloper.Core.PatternFile, Sloper.Core.PieceDetect;

procedure TTestOffsetRun.SetUp;
begin
  inherited SetUp;
  FPattern := TPattern.Create;
end;

procedure TTestOffsetRun.TearDown;
begin
  FreeAndNil(FLoaded);
  FreeAndNil(FPattern);
  inherited TearDown;
end;

function TTestOffsetRun.Pt(const AName: string; X, Y: double): string;
begin
  Result := FPattern.AddFreePoint(AName, FloatToStr(X), FloatToStr(Y)).Key;
end;

function TTestOffsetRun.Line(const A, B: string): string;
begin
  Result := FPattern.AddLine(A, B, erOutline).Key;
end;

function TTestOffsetRun.Run(const Keys: array of string; const Reversed: array of boolean): TRunEdgeArray;
var
  Index: integer;
begin
  Result := nil;
  SetLength(Result, Length(Keys));
  for Index := 0 to High(Keys) do
  begin
    Result[Index].EdgeKey := Keys[Index];
    Result[Index].Reversed := Reversed[Index];
  end;
end;

function TTestOffsetRun.Corner(out First, Second: string): TRunEdgeArray;
var
  B: string;
begin
  B := Pt('B', 100, 0);
  First := Line(Pt('A'), B);
  Second := Line(B, Pt('C', 100, 100));
  Result := Run([First, Second], [False, False]);
end;

// 100 mm square from (0, 0), as a piece
function TTestOffsetRun.Square: TPieceObject;
var
  Edges: TRectangleEdges;
  Path: TPiecePath;
  Reason: string;
begin
  AssertTrue(FPattern.LastError, FPattern.AddRectangle(Pt('O'), '100', '100', erOutline, Edges));
  FPattern.Evaluate;
  AssertTrue(Reason, DetectPiecePath(FPattern, Vec2(50, 50), Path, Reason));
  Result := FPattern.AddPiece('Square', Path, '10');
  FPattern.Evaluate;
end;

function TTestOffsetRun.RightmostX(Edge: TEdgeObject): double;
var
  Point: TVec2;
begin
  Result := -1e9;
  for Point in Edge.Flatten(0.05) do
    if Point.X > Result then
      Result := Point.X;
end;

procedure TTestOffsetRun.TestOuterCornerMitres;
var
  First, Second: string;
  Edge: TOffsetEdge;
begin
  // Left of travelling right is up; left of travelling down is to the right
  Edge := FPattern.AddOffsetRun(Corner(First, Second), '10', osLeft);
  AssertNotNull(FPattern.LastError, Edge);
  FPattern.Evaluate;
  AssertTrue(Edge.Message, Edge.State = esValid);
  AssertPointsNear('start', Vec2(0, -10), Edge.PointAtLength(0));
  AssertPointsNear('mitre', Vec2(110, -10), Edge.PointAtLength(110));
  AssertPointsNear('end', Vec2(110, 100), Edge.PointAtLength(Edge.Length));
  AssertEquals(220, Edge.Length, 1e-6);
end;

procedure TTestOffsetRun.TestInnerCornerTrims;
var
  First, Second: string;
  Edge: TOffsetEdge;
begin
  Edge := FPattern.AddOffsetRun(Corner(First, Second), '10', osRight);
  FPattern.Evaluate;
  AssertTrue(Edge.Message, Edge.State = esValid);
  AssertPointsNear('start', Vec2(0, 10), Edge.PointAtLength(0));
  AssertPointsNear('trimmed corner', Vec2(90, 10), Edge.PointAtLength(90));
  AssertPointsNear('end', Vec2(90, 100), Edge.PointAtLength(Edge.Length));
  AssertEquals(180, Edge.Length, 1e-6);
end;

procedure TTestOffsetRun.TestReversedEdgeFollowsRun;
var
  B: string;
  Edge: TOffsetEdge;
begin
  B := Pt('B', 100, 0);
  // The second edge is drawn from C up to B
  Edge := FPattern.AddOffsetRun(Run([Line(Pt('A'), B), Line(Pt('C', 100, 100), B)], [False, True]), '10', osLeft);
  FPattern.Evaluate;
  AssertTrue(Edge.Message, Edge.State = esValid);
  AssertPointsNear('end', Vec2(110, 100), Edge.PointAtLength(Edge.Length));
  AssertEquals(220, Edge.Length, 1e-6);
end;

procedure TTestOffsetRun.TestGapIsInvalid;
var
  Edge: TOffsetEdge;
begin
  Edge := FPattern.AddOffsetRun(Run([Line(Pt('A'), Pt('B', 100, 0)), Line(Pt('C', 120, 0), Pt('D', 120, 100))], [False, False]), '10', osLeft);
  FPattern.Evaluate;
  AssertTrue(Edge.State = esInvalid);
  AssertEquals(Format(rsDraftRunGap, ['Line_A_B', 'Line_C_D']), Edge.Message);
end;

// Back almost the way it came: the mitre would reach far out, so it is cut off
procedure TTestOffsetRun.TestSharpCornerBevels;
var
  B: string;
  Edge: TOffsetEdge;
begin
  B := Pt('B', 100, 0);
  Edge := FPattern.AddOffsetRun(Run([Line(Pt('A'), B), Line(B, Pt('C', 0, -5))], [False, False]), '10', osRight);
  FPattern.Evaluate;
  AssertTrue(Edge.Message, Edge.State = esValid);
  // A mitre would reach about 400 mm out; the second edge's own offset starts
  // half a millimetre past the corner
  AssertTrue('cut off at the corner, not out past it', RightmostX(Edge) <= 101);
end;

// A 5 mm first edge cannot take a 10 mm offset on its inner side
procedure TTestOffsetRun.TestInnerCornerTooTightCollapses;
var
  B: string;
  Edge: TOffsetEdge;
begin
  B := Pt('B', 5, 0);
  Edge := FPattern.AddOffsetRun(Run([Line(Pt('A'), B), Line(B, Pt('C', 5, 100))], [False, False]), '10', osRight);
  FPattern.Evaluate;
  AssertTrue(Edge.State = esInvalid);
  AssertEquals(Format(rsDraftOffsetCollapses, ['Line_B_C']), Edge.Message);
end;

procedure TTestOffsetRun.TestTightCurveCollapses;
var
  Arc: TArcObject;
  Edge: TOffsetEdge;
begin
  Arc := FPattern.AddArc(Pt('O'), '5', '0', '180', erOutline);
  // Anticlockwise, the left side is towards the centre
  Edge := FPattern.AddOffsetEdge(Arc.Key, '10', osLeft);
  FPattern.Evaluate;
  AssertTrue(Edge.State = esInvalid);
  AssertEquals(Format(rsDraftOffsetCollapses, [Arc.DisplayName]), Edge.Message);
end;

procedure TTestOffsetRun.TestCurveWithRoomStaysValid;
var
  Arc: TArcObject;
  Edge: TOffsetEdge;
begin
  Arc := FPattern.AddArc(Pt('O'), '5', '0', '180', erOutline);
  Edge := FPattern.AddOffsetEdge(Arc.Key, '10', osRight);
  FPattern.Evaluate;
  AssertTrue('away from the centre', Edge.State = esValid);
  AssertEquals(15, Distance(Edge.PointAtLength(Edge.Length / 2), Vec2(0, 0)), 0.01);
end;

procedure TTestOffsetRun.TestClosedRunJoinsAtItsStart;
var
  Piece: TPieceObject;
  Keys: TStringArray;
  Index: integer;
  Edges: TRunEdgeArray;
  Side: TOffsetSide;
  Edge: TOffsetEdge;
begin
  Piece := Square;
  Keys := nil;
  for Index := 0 to High(Piece.Path) do
    Insert(Piece.Path[Index].EdgeKey, Keys, Length(Keys));
  AssertTrue(FPattern.LastError, FPattern.PieceRun(Piece, Keys, True, Edges, Side));
  Edge := FPattern.AddOffsetRun(Edges, '10', Side);
  FPattern.Evaluate;
  AssertTrue(Edge.Message, Edge.State = esValid);
  AssertEquals('an 80 mm square', 320, Edge.Length, 1e-6);
  AssertPointsNear('closed', Edge.PointAtLength(0), Edge.PointAtLength(Edge.Length));
end;

procedure TTestOffsetRun.TestFollowsMeasurements;
var
  First, Second: string;
  Edge: TOffsetEdge;
begin
  Edge := FPattern.AddOffsetRun(Corner(First, Second), '10', osLeft);
  FPattern.Evaluate;
  AssertTrue(FPattern.SetFormula(FPattern.FindObject('C'), 'y', '50'));
  FPattern.Evaluate;
  AssertEquals(170, Edge.Length, 1e-6);
end;

// Followed the way the first edge given is drawn, here C up to B
procedure TTestOffsetRun.TestChainOrdersEdges;
var
  AB, CB, CD: string;
  Edges: TRunEdgeArray;
begin
  AB := Line(Pt('A'), Pt('B', 100, 0));
  CB := Line(Pt('C', 100, 100), FPattern.FindObject('B').Key);
  CD := Line(FPattern.FindObject('C').Key, Pt('D', 0, 100));
  FPattern.Evaluate;
  AssertTrue(FPattern.LastError, FPattern.ChainRun([CB, CD, AB], Edges));
  AssertEquals(3, Length(Edges));
  AssertEquals('D to C', CD, Edges[0].EdgeKey);
  AssertTrue(Edges[0].Reversed);
  AssertEquals('C to B, as drawn', CB, Edges[1].EdgeKey);
  AssertFalse(Edges[1].Reversed);
  AssertEquals('B to A', AB, Edges[2].EdgeKey);
  AssertTrue(Edges[2].Reversed);
end;

procedure TTestOffsetRun.TestChainRefusesBranch;
var
  B: string;
  Edges: TRunEdgeArray;
begin
  B := Pt('B', 100, 0);
  Line(Pt('A'), B);
  Line(Pt('C', 200, 0), Pt('D', 300, 0));
  // And a branch off B
  Line(B, Pt('E', 100, 50));
  Line(B, Pt('F', 100, -50));
  FPattern.Evaluate;
  AssertFalse('a gap', FPattern.ChainRun([FPattern.FindObject('Line_A_B').Key, FPattern.FindObject('Line_C_D').Key], Edges));
  AssertEquals(rsPatternRunNotJoined, FPattern.LastError);
  AssertFalse('a branch', FPattern.ChainRun([FPattern.FindObject('Line_A_B').Key, FPattern.FindObject('Line_B_E').Key,
    FPattern.FindObject('Line_B_F').Key], Edges));
  AssertEquals(rsPatternRunNotJoined, FPattern.LastError);
end;

procedure TTestOffsetRun.TestPieceRunInside;
var
  Piece: TPieceObject;
  Edges: TRunEdgeArray;
  Side: TOffsetSide;
  Edge: TOffsetEdge;
begin
  Piece := Square;
  AssertTrue(FPattern.LastError, FPattern.PieceRun(Piece, [Piece.Path[0].EdgeKey], True, Edges, Side));
  Edge := FPattern.AddOffsetRun(Edges, '10', Side);
  FPattern.Evaluate;
  AssertTrue('inside the seam line', PointInPolygon(Edge.PointAtLength(Edge.Length / 2), Piece.Outline));
end;

procedure TTestOffsetRun.TestPieceRunOutside;
var
  Piece: TPieceObject;
  Edges: TRunEdgeArray;
  Side: TOffsetSide;
  Edge: TOffsetEdge;
begin
  Piece := Square;
  AssertTrue(FPattern.PieceRun(Piece, [Piece.Path[1].EdgeKey], False, Edges, Side));
  Edge := FPattern.AddOffsetRun(Edges, '10', Side);
  FPattern.Evaluate;
  AssertFalse('outside the seam line', PointInPolygon(Edge.PointAtLength(Edge.Length / 2), Piece.Outline));
end;

// The last edge of the path and the first are one stretch
procedure TTestOffsetRun.TestPieceRunWrapsRound;
var
  Piece: TPieceObject;
  Edges: TRunEdgeArray;
  Side: TOffsetSide;
begin
  Piece := Square;
  AssertTrue(FPattern.LastError, FPattern.PieceRun(Piece, [Piece.Path[0].EdgeKey, Piece.Path[3].EdgeKey], True, Edges, Side));
  AssertEquals(Piece.Path[3].EdgeKey, Edges[0].EdgeKey);
  AssertEquals(Piece.Path[0].EdgeKey, Edges[1].EdgeKey);
end;

procedure TTestOffsetRun.TestPieceRunNeedsOneStretch;
var
  Piece: TPieceObject;
  Edges: TRunEdgeArray;
  Side: TOffsetSide;
begin
  Piece := Square;
  AssertFalse(FPattern.PieceRun(Piece, [Piece.Path[0].EdgeKey, Piece.Path[2].EdgeKey], True, Edges, Side));
  AssertEquals(rsPatternRunNotJoined, FPattern.LastError);
  AssertFalse('not on the piece', FPattern.PieceRun(Piece, [Line(Pt('P', 500, 500), Pt('Q', 600, 500))], True, Edges, Side));
end;

// The offset reads only the edges, so a stitch line inside its own piece
// makes no circular reference
procedure TTestOffsetRun.TestInsideStitchJoinsItsPiece;
var
  Piece: TPieceObject;
  Edges: TRunEdgeArray;
  Side: TOffsetSide;
  Edge: TOffsetEdge;
begin
  Piece := Square;
  AssertTrue(FPattern.PieceRun(Piece, [Piece.Path[0].EdgeKey, Piece.Path[1].EdgeKey], True, Edges, Side));
  Edge := FPattern.AddOffsetRun(Edges, '6', Side, erStitch);
  FPattern.Evaluate;
  AssertTrue(Edge.Message, Edge.State = esValid);
  AssertTrue(Piece.Message, Piece.State = esValid);
  AssertEquals(0, Piece.LineMarkingOf(Edge.Key));
end;

procedure TTestOffsetRun.TestRunRoundTrip;
var
  Reason: string;
  Edge, Back: TOffsetEdge;
begin
  Edge := FPattern.AddOffsetRun(Run([Line(Pt('A'), Pt('B', 100, 0)), Line(Pt('C', 100, 100), FPattern.FindObject('B').Key)],
    [False, True]), '10', osLeft);
  FPattern.Evaluate;
  FLoaded := TPattern.Create;
  AssertTrue(Reason, LoadPatternFromText(FLoaded, SavePatternToText(FPattern), Reason));
  FLoaded.Evaluate;
  Back := TOffsetEdge(FLoaded.FindNode(Edge.Key));
  AssertEquals(2, Length(Back.Run));
  AssertTrue(Back.Run[1].Reversed);
  AssertEquals(Edge.Length, Back.Length, 1e-9);
  AssertEquals(SavePatternToText(FPattern), SavePatternToText(FLoaded));
  AssertTrue('the run is written out', Pos('"edges"', SavePatternToText(FPattern)) > 0);
end;

procedure TTestOffsetRun.TestSingleEdgeWrittenAsBefore;
begin
  FPattern.AddOffsetEdge(Line(Pt('A'), Pt('B', 100, 0)), '10', osLeft);
  AssertEquals(0, Pos('"edges"', SavePatternToText(FPattern)));
end;

initialization
  RegisterTest(TTestOffsetRun);
end.
