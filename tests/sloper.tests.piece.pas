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

// Pieces: the cutting line, automatic detection, and pieces as pattern objects.
unit Sloper.Tests.Piece;

{$mode ObjFPC}{$H+}

interface

uses
  fpcunit, testregistry, Sloper.Tests.TestCase, Sloper.Core.Geometry, Sloper.Core.EvalTypes, Sloper.Core.Draft, Sloper.Core.Pattern,
  Sloper.Core.Piece, Sloper.Core.PieceDetect, Sloper.Core.SeamAllowance;

type
  TTestPiece = class(TOSTestCase)
  private
    FPattern: TPattern;
    function Pt(const AName: string; X, Y: double): string;
    function Line(const A, B: string): TLineObject;
    // Outline square of Size with its corner at the origin; returns the corner keys
    procedure Square(Size: double; out A, B, C, D: string);
    function Detect(X, Y: double): TPiecePath;
    function SquarePiece(const Allowance: string): TPieceObject;
    procedure AssertRefused(const Msg, Expected: string; X, Y: double);
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestOffsetSquare;
    procedure TestOffsetClockwiseKeepsWidths;
    procedure TestOffsetOneEdgeWider;
    procedure TestOffsetZeroEdgeForFold;
    procedure TestOffsetConcaveCorner;
    procedure TestOffsetCutsOffLongSpike;
    procedure TestDetectSquare;
    procedure TestDetectEdgesDrawnAnyWay;
    procedure TestDetectOutsideIsRefused;
    procedure TestDetectIgnoresConstruction;
    procedure TestDetectIgnoresDanglingEdge;
    procedure TestDetectPicksSmallestRegion;
    procedure TestDetectCrossingNeedsSplit;
    procedure TestDetectOverlappingPanels;
    procedure TestDetectUsesSplitParts;
    procedure TestDetectLineAndCurve;
    procedure TestPieceOnPath;
    procedure TestPieceCuttingLine;
    procedure TestPieceFollowsMeasurementChange;
    procedure TestPieceAllowanceFormula;
    procedure TestPieceEdgeAllowance;
    procedure TestPieceGapIsInvalid;
    procedure TestPieceNegativeAllowanceIsInvalid;
    procedure TestPieceChecks;
    procedure TestPieceKeepsItsEdges;
    procedure TestPieceDefaultNames;
    procedure TestPieceFileRoundTrip;
    procedure TestGrainlineDefault;
    procedure TestGrainlineAngleFormula;
    procedure TestGrainlineBetweenPoints;
    procedure TestGrainlineChecks;
    procedure TestNotchOnEdge;
    procedure TestNotchOnReversedEdgePointsInwards;
    procedure TestNotchOnPoint;
    procedure TestNotchOffPieceIsInvalid;
    procedure TestNotchPastEndIsInvalid;
    procedure TestNotchChecks;
    procedure TestRemoveNotchRenumbers;
    procedure TestNotchUsesEdgeAllowance;
    procedure TestPointKeepsItsNotch;
    procedure TestMarksRoundTripWithNewerPoint;
    procedure TestCutDefaults;
    procedure TestSetCut;
    procedure TestCutCaption;
    procedure TestFoldHasNoAllowance;
    procedure TestFoldOverridesEdgeAllowance;
    procedure TestFoldNotchAtFoldLine;
    procedure TestFoldArrowPointsAtFold;
    procedure TestFoldChecks;
    procedure TestCutAndFoldRoundTrip;
    procedure TestPieceCurvedEdgeStaysAtItsAllowance;
  end;

implementation

uses
  SysUtils, Sloper.Core.PatternFile;

const
  AreaTolerance = 0.5;

function Outline(const Coordinates: array of double): TVec2Array;
var
  Index: integer;
begin
  Result := nil;
  SetLength(Result, Length(Coordinates) div 2);
  for Index := 0 to High(Result) do
    Result[Index] := Vec2(Coordinates[Index * 2], Coordinates[Index * 2 + 1]);
end;

function Widths(const Values: array of double): TDoubleArray;
var
  Index: integer;
begin
  Result := nil;
  SetLength(Result, Length(Values));
  for Index := 0 to High(Values) do
    Result[Index] := Values[Index];
end;

function HasPoint(const Points: TVec2Array; X, Y: double): boolean;
var
  P: TVec2;
begin
  for P in Points do
    if PointsNear(P, Vec2(X, Y), 0.01) then
      Exit(True);
  Result := False;
end;

procedure TTestPiece.SetUp;
begin
  FPattern := TPattern.Create;
end;

procedure TTestPiece.TearDown;
begin
  FreeAndNil(FPattern);
end;

function TTestPiece.Pt(const AName: string; X, Y: double): string;
var
  Point: TFreePoint;
begin
  Point := FPattern.AddFreePoint(AName, FloatToStr(X), FloatToStr(Y));
  AssertNotNull(FPattern.LastError, Point);
  Result := Point.Key;
end;

function TTestPiece.Line(const A, B: string): TLineObject;
begin
  Result := FPattern.AddLine(A, B, erOutline);
  AssertNotNull(FPattern.LastError, Result);
end;

procedure TTestPiece.Square(Size: double; out A, B, C, D: string);
begin
  A := Pt('', 0, 0);
  B := Pt('', Size, 0);
  C := Pt('', Size, Size);
  D := Pt('', 0, Size);
  Line(A, B);
  Line(B, C);
  Line(C, D);
  Line(D, A);
end;

function TTestPiece.Detect(X, Y: double): TPiecePath;
var
  ErrorMessage: string;
begin
  FPattern.Evaluate;
  AssertTrue(ErrorMessage, DetectPiecePath(FPattern, Vec2(X, Y), Result, ErrorMessage));
end;

function TTestPiece.SquarePiece(const Allowance: string): TPieceObject;
var
  A, B, C, D: string;
begin
  Square(100, A, B, C, D);
  Result := FPattern.AddPiece('Front', Detect(50, 50), Allowance);
  AssertNotNull(FPattern.LastError, Result);
  FPattern.Evaluate;
  AssertTrue(Result.Message, Result.State = esValid);
end;

procedure TTestPiece.AssertRefused(const Msg, Expected: string; X, Y: double);
var
  Path: TPiecePath;
  ErrorMessage: string;
begin
  FPattern.Evaluate;
  AssertFalse(Msg, DetectPiecePath(FPattern, Vec2(X, Y), Path, ErrorMessage));
  AssertEquals(Msg, Expected, ErrorMessage);
end;

procedure TTestPiece.TestOffsetSquare;
var
  Cut: TVec2Array;
begin
  AssertTrue(OffsetOutline(Outline([0, 0, 100, 0, 100, 100, 0, 100]), Widths([10, 10, 10, 10]), Cut));
  AssertNear('area', 120 * 120, Abs(SignedArea(Cut)), AreaTolerance);
  AssertTrue('clockwise', IsClockwise(Cut));
  AssertTrue('mitred corner', HasPoint(Cut, 110, 110));
end;

procedure TTestPiece.TestOffsetClockwiseKeepsWidths;
var
  Cut: TVec2Array;
begin
  // Clockwise: (0,0) -> (0,100) is the left side, then the top, the right, the bottom
  AssertTrue(OffsetOutline(Outline([0, 0, 0, 100, 100, 100, 100, 0]), Widths([20, 0, 0, 0]), Cut));
  AssertTrue('left side wider', HasPoint(Cut, -20, 0));
  AssertTrue('left side wider', HasPoint(Cut, -20, 100));
  AssertTrue('right side untouched', HasPoint(Cut, 100, 100));
end;

procedure TTestPiece.TestOffsetOneEdgeWider;
var
  Cut: TVec2Array;
begin
  AssertTrue(OffsetOutline(Outline([0, 0, 100, 0, 100, 100, 0, 100]), Widths([30, 10, 10, 10]), Cut));
  // Hem of 30 along the bottom, 10 elsewhere
  AssertNear('area', 120 * 140, Abs(SignedArea(Cut)), AreaTolerance);
  AssertTrue('corner meets the wider edge', HasPoint(Cut, 110, -30));
  AssertTrue('corner meets the wider edge', HasPoint(Cut, -10, -30));
end;

procedure TTestPiece.TestOffsetZeroEdgeForFold;
var
  Cut: TVec2Array;
begin
  AssertTrue(OffsetOutline(Outline([0, 0, 100, 0, 100, 100, 0, 100]), Widths([10, 10, 10, 0]), Cut));
  AssertNear('area', 110 * 120, Abs(SignedArea(Cut)), AreaTolerance);
  AssertTrue('nothing beyond the fold', HasPoint(Cut, 0, -10));
end;

procedure TTestPiece.TestOffsetConcaveCorner;
var
  Cut: TVec2Array;
begin
  // An L: the inner corner is at (50, 50)
  AssertTrue(OffsetOutline(Outline([0, 0, 100, 0, 100, 50, 50, 50, 50, 100, 0, 100]), Widths([10, 10, 10, 10, 10, 10]), Cut));
  AssertTrue('inner corner moves out', HasPoint(Cut, 60, 60));
  AssertFalse('no vertex left behind', HasPoint(Cut, 50, 50));
  AssertEquals('clean corners', 6, Length(Cut));
end;

procedure TTestPiece.TestOffsetCutsOffLongSpike;
var
  Cut: TVec2Array;
  P: TVec2;
begin
  // A sliver 200 long and 10 wide: the mitre at its tip would run some 400 mm out
  AssertTrue(OffsetOutline(Outline([0, 0, 200, 5, 0, 10]), Widths([10, 10, 10]), Cut));
  for P in Cut do
    AssertTrue('stays near the tip', P.X < 200 + 4 * 10 + 1);
end;

procedure TTestPiece.TestDetectSquare;
var
  Path: TPiecePath;
  A, B, C, D: string;
begin
  Square(100, A, B, C, D);
  Path := Detect(50, 50);
  AssertEquals('edges', 4, Length(Path));
  // With y down the square is drawn clockwise on screen, so none is reversed
  AssertFalse(Path[0].Reversed or Path[1].Reversed or Path[2].Reversed or Path[3].Reversed);
end;

procedure TTestPiece.TestDetectEdgesDrawnAnyWay;
var
  A, B, C, D: string;
  Piece: TPieceObject;
begin
  A := Pt('', 0, 0);
  B := Pt('', 100, 0);
  C := Pt('', 100, 100);
  D := Pt('', 0, 100);
  Line(A, B);
  Line(C, B);
  Line(C, D);
  Line(A, D);
  Piece := FPattern.AddPiece('', Detect(50, 50), '10');
  FPattern.Evaluate;
  AssertTrue(Piece.Message, Piece.State = esValid);
  AssertTrue('clockwise', IsClockwise(Piece.Outline));
  AssertNear('area', 10000, Piece.Area);
end;

procedure TTestPiece.TestDetectOutsideIsRefused;
var
  A, B, C, D: string;
begin
  Square(100, A, B, C, D);
  AssertRefused('outside', rsDetectNoRegion, 150, 50);
end;

procedure TTestPiece.TestDetectIgnoresConstruction;
var
  A, B, C, D: string;
begin
  Square(100, A, B, C, D);
  // A construction diagonal does not divide the square
  FPattern.AddLine(A, C, erConstruction);
  AssertEquals('edges', 4, Length(Detect(25, 75)));
end;

procedure TTestPiece.TestDetectIgnoresDanglingEdge;
var
  A, B, C, D: string;
begin
  Square(100, A, B, C, D);
  Line(C, Pt('', 150, 150));
  AssertEquals('edges', 4, Length(Detect(50, 50)));
end;

procedure TTestPiece.TestDetectPicksSmallestRegion;
var
  A, B, C, D: string;
begin
  Square(100, A, B, C, D);
  // The diagonal divides the square; each side is a triangle
  Line(A, C);
  AssertEquals('edges', 3, Length(Detect(25, 75)));
  AssertEquals('edges', 3, Length(Detect(75, 25)));
end;

procedure TTestPiece.TestDetectCrossingNeedsSplit;
var
  A, B, C, D, Middle: string;
begin
  // Two panels stand on one long base and meet at its middle, like a hem
  // drawn once under a front and a back: the base needs a split there
  A := Pt('', 0, 0);
  B := Pt('', 200, 0);
  C := Pt('', 200, 100);
  D := Pt('', 0, 100);
  Middle := Pt('M', 100, 0);
  Line(A, B);
  Line(B, C);
  Line(C, Middle);
  Line(Middle, D);
  Line(D, A);
  AssertRefused('T junction', Format(rsDetectNeedsSplit, ['Line_A_B']), 10, 50);
end;

procedure TTestPiece.TestDetectOverlappingPanels;
var
  A, B, C, D, E, F, G, H, Message: string;
  Path: TPiecePath;
begin
  // Two rectangles sharing no edge, overlapping between x = 80 and x = 120
  A := Pt('', 0, 0);
  B := Pt('', 120, 0);
  C := Pt('', 120, 100);
  D := Pt('', 0, 100);
  Line(A, B);
  Line(B, C);
  Line(C, D);
  Line(D, A);
  E := Pt('', 80, 20);
  F := Pt('', 200, 20);
  Line(E, F);
  G := Pt('', 200, 80);
  H := Pt('', 80, 80);
  Line(F, G);
  Line(G, H);
  Line(H, E);
  FPattern.Evaluate;
  AssertTrue('left panel', DetectPiecePath(FPattern, Vec2(20, 50), Path, Message));
  AssertEquals('left panel', 4, Length(Path));
  AssertTrue('right panel', DetectPiecePath(FPattern, Vec2(180, 50), Path, Message));
  AssertEquals('right panel', 4, Length(Path));
end;

procedure TTestPiece.TestDetectUsesSplitParts;
var
  A, B, C, D, Middle: string;
  Bottom: TLineObject;
  First, Second: TSplitPart;
begin
  A := Pt('', 0, 0);
  B := Pt('', 100, 0);
  C := Pt('', 100, 100);
  D := Pt('', 0, 100);
  Bottom := Line(A, B);
  Line(B, C);
  Line(C, D);
  Line(D, A);
  Middle := FPattern.AddAlongEdgePoint('', Bottom.Key, False, amRatio, '0.5').Key;
  AssertTrue(FPattern.SplitEdge(Bottom.Key, Middle, First, Second));
  // The split edge itself is left out, so the parts make the path
  AssertEquals('edges', 5, Length(Detect(50, 50)));
end;

procedure TTestPiece.TestDetectLineAndCurve;
var
  A, B: string;
  Curve: TCurveObject;
  Path: TPiecePath;
begin
  A := Pt('', 0, 0);
  B := Pt('', 100, 0);
  Line(A, B);
  Curve := FPattern.AddCurve(A, B, '90', '50', '90', '50', erOutline);
  AssertNotNull(FPattern.LastError, Curve);
  // The curve bulges up, towards smaller y
  Path := Detect(50, -10);
  AssertEquals('edges', 2, Length(Path));
end;

procedure TTestPiece.TestPieceOnPath;
var
  Piece: TPieceObject;
  Path: TPiecePath;
begin
  Piece := SquarePiece('10');
  AssertTrue('found', PieceOnPath(FPattern, Detect(50, 50)) = Piece);
  // A triangle made of other edges
  Line(FPattern.FindObject('A').Key, FPattern.FindObject('C').Key);
  Path := Detect(25, 75);
  AssertNull('another path', PieceOnPath(FPattern, Path));
end;

procedure TTestPiece.TestPieceCuttingLine;
var
  Piece: TPieceObject;
begin
  Piece := SquarePiece('10');
  AssertNear('area', 10000, Piece.Area);
  AssertNear('perimeter', 400, Piece.Perimeter);
  AssertNear('cut area', 14400, Abs(SignedArea(Piece.CutLine)), AreaTolerance);
end;

procedure TTestPiece.TestPieceFollowsMeasurementChange;
var
  Piece: TPieceObject;
begin
  Piece := SquarePiece('10');
  AssertTrue(FPattern.LastError, FPattern.SetFormula(FPattern.FindObject('C'), 'x', '200'));
  AssertTrue(FPattern.LastError, FPattern.SetFormula(FPattern.FindObject('B'), 'x', '200'));
  FPattern.Evaluate;
  AssertTrue(Piece.Message, Piece.State = esValid);
  AssertNear('area', 20000, Piece.Area);
end;

procedure TTestPiece.TestPieceAllowanceFormula;
var
  Piece: TPieceObject;
begin
  FPattern.AddVariable('seam', '15');
  Piece := SquarePiece('#seam * 2');
  AssertNear('cut area', 160 * 160, Abs(SignedArea(Piece.CutLine)), AreaTolerance);
end;

procedure TTestPiece.TestPieceEdgeAllowance;
var
  Piece: TPieceObject;
begin
  Piece := SquarePiece('10');
  AssertTrue(FPattern.LastError, FPattern.SetEdgeAllowance(Piece, 0, '30'));
  FPattern.Evaluate;
  AssertNear('one edge wider', 120 * 140, Abs(SignedArea(Piece.CutLine)), AreaTolerance);
  AssertFalse('a bad formula is refused', FPattern.SetEdgeAllowance(Piece, 1, '1 +'));
  AssertFalse('and leaves no field', Piece.HasOverride(1));
  AssertTrue(FPattern.SetEdgeAllowance(Piece, 0, ''));
  AssertFalse(Piece.HasOverride(0));
  FPattern.Evaluate;
  AssertNear('back to the default', 14400, Abs(SignedArea(Piece.CutLine)), AreaTolerance);
end;

procedure TTestPiece.TestPieceGapIsInvalid;
var
  A, B, C, D, Near: string;
  Path: TPiecePath;
  Piece: TPieceObject;

  function Entry(Edge: TLineObject): TPieceEdge;
  begin
    Result.EdgeKey := Edge.Key;
    Result.Reversed := False;
  end;

begin
  A := Pt('A', 0, 0);
  B := Pt('B', 100, 0);
  C := Pt('C', 100, 100);
  D := Pt('D', 5, 5);
  Near := Pt('E', 0.005, 0);
  Path := nil;
  SetLength(Path, 3);
  Path[0] := Entry(Line(A, B));
  Path[1] := Entry(Line(B, C));
  Path[2] := Entry(Line(C, D));
  Piece := FPattern.AddPiece('Gap', Path, '10');
  AssertNotNull(FPattern.LastError, Piece);
  FPattern.Evaluate;
  AssertTrue('open at the join', Piece.State = esInvalid);
  AssertEquals(Format(rsPieceGap, ['Line_C_D', 'Line_A_B']), Piece.Message);

  Path[2] := Entry(Line(C, Near));
  Piece := FPattern.AddPiece('Closed', Path, '10');
  FPattern.Evaluate;
  AssertTrue('rounding does not open it: ' + Piece.Message, Piece.State = esValid);
end;

procedure TTestPiece.TestPieceNegativeAllowanceIsInvalid;
var
  Piece: TPieceObject;
begin
  Piece := SquarePiece('10');
  AssertTrue(FPattern.SetFormula(Piece, PieceAllowanceField, '-1'));
  FPattern.Evaluate;
  AssertTrue(Piece.State = esInvalid);
  AssertEquals(rsPieceNegativeAllowance, Piece.Message);
  AssertNear('keeps its last good line', 14400, Abs(SignedArea(Piece.CutLine)), AreaTolerance);
end;

procedure TTestPiece.TestPieceChecks;
var
  A, B, C, D: string;
  Path: TPiecePath;
begin
  Square(100, A, B, C, D);
  Path := Detect(50, 50);
  AssertNull('bad formula', FPattern.AddPiece('', Path, '1 +'));
  AssertEquals(PieceAllowanceField, FPattern.LastErrorField);
  AssertNull('bad name', FPattern.AddPiece('1x', Path, '10'));
  AssertNull('name taken', FPattern.AddPiece('A', Path, '10'));
  Path[1] := Path[0];
  AssertNull('edge twice', FPattern.AddPiece('', Path, '10'));
  SetLength(Path, 1);
  AssertNull('too short', FPattern.AddPiece('', Path, '10'));
  Path[0].EdgeKey := A;
  SetLength(Path, 2);
  Path[1].EdgeKey := B;
  AssertNull('not edges', FPattern.AddPiece('', Path, '10'));
end;

procedure TTestPiece.TestPieceKeepsItsEdges;
var
  Piece: TPieceObject;
begin
  Piece := SquarePiece('10');
  AssertFalse('in use', FPattern.Delete(FPattern.FindNode(Piece.Path[0].EdgeKey)));
  AssertTrue('the piece can go', FPattern.Delete(Piece));
end;

procedure TTestPiece.TestPieceDefaultNames;
var
  A, B, C, D: string;
  Path: TPiecePath;
begin
  Square(100, A, B, C, D);
  Path := Detect(50, 50);
  AssertEquals('Piece', FPattern.AddPiece('', Path, '10').Name);
  AssertEquals('Piece2', FPattern.AddPiece('', Path, '10').Name);
end;

procedure TTestPiece.TestPieceFileRoundTrip;
var
  Piece: TPieceObject;
  Text, ErrorMessage: string;
  Loaded: TPattern;
begin
  Piece := SquarePiece('10');
  AssertTrue(FPattern.SetEdgeAllowance(Piece, 2, '25'));
  Text := SavePatternToText(FPattern);
  Loaded := TPattern.Create;
  try
    AssertTrue(ErrorMessage, LoadPatternFromText(Loaded, Text, ErrorMessage));
    AssertEquals('same text', Text, SavePatternToText(Loaded));
    Loaded.Evaluate;
    Piece := TPieceObject(Loaded.FindObject('Front'));
    AssertTrue(Piece.Message, Piece.State = esValid);
    AssertTrue(Piece.HasOverride(2));
    AssertNear('cut area', 120 * 135, Abs(SignedArea(Piece.CutLine)), AreaTolerance);
  finally
    FreeAndNil(Loaded);
  end;
end;

procedure TTestPiece.TestPieceCurvedEdgeStaysAtItsAllowance;
var
  A, B: string;
  Piece: TPieceObject;
  Curve: TCurveObject;
  P: TVec2;
  Position, Gap: double;
begin
  A := Pt('', 0, 0);
  B := Pt('', 100, 0);
  Line(A, B);
  Curve := FPattern.AddCurve(A, B, '90', '50', '90', '50', erOutline);
  Piece := FPattern.AddPiece('', Detect(50, -10), '10');
  FPattern.Evaluate;
  AssertTrue(Piece.Message, Piece.State = esValid);
  // Every point of the cutting line above the base is 10 mm off the curve
  for P in Piece.CutLine do
    if (P.Y < -1) and (P.X > 0) and (P.X < 100) then
    begin
      Curve.Locate(P, Position, Gap);
      AssertNear('10 mm off the curve', 10, Gap, 0.1);
    end;
end;

procedure TTestPiece.TestGrainlineDefault;
var
  Piece: TPieceObject;
begin
  Piece := SquarePiece('10');
  AssertTrue(Piece.GrainKind = gkAngle);
  // Straight up through the middle, 60% of the height: from y 80 to y 20
  AssertPointsNear('start', Vec2(50, 80), Piece.Grainline.P1);
  AssertPointsNear('end', Vec2(50, 20), Piece.Grainline.P2);
  AssertEquals('shaft and two heads', 5, Length(Piece.GrainArrow));
end;

procedure TTestPiece.TestGrainlineAngleFormula;
var
  Piece: TPieceObject;
begin
  FPattern.AddVariable('bias', '45');
  Piece := SquarePiece('10');
  AssertTrue(FPattern.LastError, FPattern.SetGrainAngle(Piece, '#bias'));
  FPattern.Evaluate;
  AssertTrue(Piece.Message, Piece.State = esValid);
  AssertNear('angle', 45, Piece.Grainline.Angle);
  AssertFalse('bad formula', FPattern.SetGrainAngle(Piece, '1 +'));
end;

procedure TTestPiece.TestGrainlineBetweenPoints;
var
  Piece: TPieceObject;
begin
  Piece := SquarePiece('10');
  AssertTrue(FPattern.LastError, FPattern.SetGrainPoints(Piece, Pt('G1', 10, 10), Pt('G2', 90, 10)));
  FPattern.Evaluate;
  AssertTrue(Piece.Message, Piece.State = esValid);
  AssertPointsNear('start', Vec2(10, 10), Piece.Grainline.P1);
  AssertNull('the angle field went', Piece.Field(GrainAngleField));
  AssertFalse('a point in use', FPattern.Delete(FPattern.FindObject('G1')));
end;

procedure TTestPiece.TestGrainlineChecks;
var
  Piece: TPieceObject;
begin
  Piece := SquarePiece('10');
  AssertFalse('same point', FPattern.SetGrainPoints(Piece, Piece.Path[0].EdgeKey, Piece.Path[0].EdgeKey));
  AssertFalse('not a point', FPattern.SetGrainPoints(Piece, FPattern.FindObject('A').Key, Piece.Path[0].EdgeKey));
  FPattern.ClearGrain(Piece);
  FPattern.Evaluate;
  AssertTrue(Piece.State = esValid);
  AssertEquals('no arrow', 0, Length(Piece.GrainArrow));
end;

procedure TTestPiece.TestNotchOnEdge;
var
  Piece: TPieceObject;
  Mark: TNotchMark;
begin
  Piece := SquarePiece('10');
  // Line_A_B is the bottom, running from x = 0
  AssertTrue(FPattern.LastError, FPattern.AddEdgeNotch(Piece, FPattern.FindObject('Line_A_B').Key, '30'));
  FPattern.Evaluate;
  AssertTrue(Piece.Message, Piece.State = esValid);
  Mark := Piece.NotchMarks[0];
  AssertPointsNear('on the seam', Vec2(30, 0), Mark.Seam);
  AssertPointsNear('at the cutting line', Vec2(30, -10), Mark.Cut);
  AssertPointsNear('cut inwards', Vec2(30, -4), Mark.Tip);
end;

procedure TTestPiece.TestNotchOnReversedEdgePointsInwards;
var
  A, B, C, D: string;
  Piece: TPieceObject;
begin
  // Drawn so that the top edge runs with the clockwise path, unreversed
  A := Pt('', 0, 0);
  B := Pt('', 100, 0);
  C := Pt('', 100, 100);
  D := Pt('', 0, 100);
  Line(A, B);
  Line(B, C);
  Line(D, C);
  Line(D, A);
  Piece := FPattern.AddPiece('', Detect(50, 50), '10');
  AssertTrue(FPattern.AddEdgeNotch(Piece, FPattern.FindObject('Line_D_C').Key, '30'));
  AssertTrue(FPattern.AddEdgeNotch(Piece, FPattern.FindObject('Line_A_B').Key, '30'));
  FPattern.Evaluate;
  AssertPointsNear('top goes up', Vec2(30, 110), Piece.NotchMarks[0].Cut);
  AssertPointsNear('bottom goes down', Vec2(30, -10), Piece.NotchMarks[1].Cut);
end;

procedure TTestPiece.TestNotchOnPoint;
var
  Piece: TPieceObject;
  Spot: TAlongEdgePoint;
begin
  Piece := SquarePiece('10');
  Spot := FPattern.AddAlongEdgePoint('N', FPattern.FindObject('Line_B_C').Key, False, amLength, '40');
  AssertTrue(FPattern.LastError, FPattern.AddPointNotch(Piece, Spot.Key));
  FPattern.Evaluate;
  AssertTrue(Piece.Message, Piece.State = esValid);
  AssertPointsNear('on the right side', Vec2(100, 40), Piece.NotchMarks[0].Seam);
  AssertPointsNear('at the cutting line', Vec2(110, 40), Piece.NotchMarks[0].Cut);
end;

procedure TTestPiece.TestNotchOffPieceIsInvalid;
var
  Piece: TPieceObject;
begin
  Piece := SquarePiece('10');
  AssertTrue(FPattern.AddPointNotch(Piece, Pt('Off', 50, 50)));
  FPattern.Evaluate;
  AssertTrue(Piece.State = esInvalid);
  AssertEquals(Format(rsPieceNotchOffPiece, ['Off']), Piece.Message);
end;

procedure TTestPiece.TestNotchPastEndIsInvalid;
var
  Piece: TPieceObject;
begin
  Piece := SquarePiece('10');
  AssertTrue(FPattern.AddEdgeNotch(Piece, Piece.Path[0].EdgeKey, '150'));
  FPattern.Evaluate;
  AssertTrue(Piece.State = esInvalid);
end;

procedure TTestPiece.TestNotchChecks;
var
  Piece: TPieceObject;
begin
  Piece := SquarePiece('10');
  AssertFalse('bad formula', FPattern.AddEdgeNotch(Piece, Piece.Path[0].EdgeKey, '1 +'));
  AssertEquals('leaves nothing', 0, Length(Piece.Notches));
  Line(FPattern.FindObject('A').Key, FPattern.FindObject('C').Key);
  AssertFalse('not on the piece', FPattern.AddEdgeNotch(Piece, FPattern.FindObject('Line_A_C').Key, '10'));
  AssertFalse('no such notch', FPattern.RemoveNotch(Piece, 0));
end;

procedure TTestPiece.TestRemoveNotchRenumbers;
var
  Piece: TPieceObject;
begin
  Piece := SquarePiece('10');
  AssertTrue(FPattern.AddEdgeNotch(Piece, Piece.Path[0].EdgeKey, '10'));
  AssertTrue(FPattern.AddEdgeNotch(Piece, Piece.Path[0].EdgeKey, '20'));
  AssertTrue(FPattern.AddEdgeNotch(Piece, Piece.Path[1].EdgeKey, '30'));
  AssertTrue(FPattern.RemoveNotch(Piece, 0));
  AssertEquals('notches', 2, Length(Piece.Notches));
  AssertEquals('20', FPattern.FormulaText(Piece, Piece.NotchField(0)));
  AssertEquals('30', FPattern.FormulaText(Piece, Piece.NotchField(1)));
  AssertNull('nothing left at the end', Piece.Field(Piece.NotchField(2)));
end;

procedure TTestPiece.TestNotchUsesEdgeAllowance;
var
  Piece: TPieceObject;
  Bottom: string;
begin
  Piece := SquarePiece('10');
  Bottom := FPattern.FindObject('Line_A_B').Key;
  AssertTrue(FPattern.SetEdgeAllowance(Piece, Piece.PathIndexOf(Bottom), '30'));
  AssertTrue(FPattern.AddEdgeNotch(Piece, Bottom, '50'));
  FPattern.Evaluate;
  AssertPointsNear('at the wider cutting line', Vec2(50, -30), Piece.NotchMarks[0].Cut);
end;

procedure TTestPiece.TestPointKeepsItsNotch;
var
  Piece: TPieceObject;
  Spot: TAlongEdgePoint;
begin
  Piece := SquarePiece('10');
  Spot := FPattern.AddAlongEdgePoint('N', FPattern.FindObject('Line_B_C').Key, False, amLength, '40');
  AssertTrue(FPattern.AddPointNotch(Piece, Spot.Key));
  AssertFalse('in use', FPattern.Delete(Spot));
end;

procedure TTestPiece.TestMarksRoundTripWithNewerPoint;
var
  Piece: TPieceObject;
  Spot: TAlongEdgePoint;
  Text, ErrorMessage: string;
  Loaded: TPattern;
begin
  Piece := SquarePiece('10');
  // These points are newer than the piece, and a file lists inputs first
  Spot := FPattern.AddAlongEdgePoint('N', FPattern.FindObject('Line_B_C').Key, False, amLength, '40');
  AssertTrue(FPattern.AddPointNotch(Piece, Spot.Key));
  AssertTrue(FPattern.AddEdgeNotch(Piece, Piece.Path[0].EdgeKey, '25'));
  AssertTrue(FPattern.SetGrainPoints(Piece, Pt('G1', 10, 10), Pt('G2', 90, 10)));
  FPattern.Evaluate;
  Text := SavePatternToText(FPattern);
  Loaded := TPattern.Create;
  try
    AssertTrue(ErrorMessage, LoadPatternFromText(Loaded, Text, ErrorMessage));
    AssertEquals('same text', Text, SavePatternToText(Loaded));
    Loaded.Evaluate;
    Piece := TPieceObject(Loaded.FindObject('Front'));
    AssertTrue(Piece.Message, Piece.State = esValid);
    AssertEquals('notches', 2, Length(Piece.NotchMarks));
    AssertTrue('grainline', Piece.GrainKind = gkPoints);
  finally
    FreeAndNil(Loaded);
  end;
end;

procedure TTestPiece.TestCutDefaults;
var
  Piece: TPieceObject;
begin
  Piece := SquarePiece('10');
  AssertEquals(1, Piece.CutCount);
  AssertFalse(Piece.Mirrored);
  AssertFalse(Piece.OnFold);
  AssertEquals('no bracket', 0, Length(Piece.FoldArrow));
end;

procedure TTestPiece.TestSetCut;
var
  Piece: TPieceObject;
begin
  Piece := SquarePiece('10');
  AssertTrue(FPattern.SetCut(Piece, 2, True));
  AssertEquals(2, Piece.CutCount);
  AssertTrue(Piece.Mirrored);
  AssertFalse('none is refused', FPattern.SetCut(Piece, 0, False));
  AssertEquals('and leaves it', 2, Piece.CutCount);
end;

procedure TTestPiece.TestCutCaption;
var
  Piece: TPieceObject;
begin
  Piece := SquarePiece('10');
  AssertEquals('Front, cut 1', Piece.CutCaption);
  AssertTrue(FPattern.SetCut(Piece, 2, True));
  AssertEquals('Front, cut 2 mirrored', Piece.CutCaption);
  AssertTrue(FPattern.SetCut(Piece, 1, True));
  AssertEquals('one cannot be mirrored', 'Front, cut 1', Piece.CutCaption);
  AssertTrue(FPattern.SetFoldEdge(Piece, Piece.Path[0].EdgeKey));
  AssertEquals('Front, cut 1 on fold', Piece.CutCaption);
end;

procedure TTestPiece.TestFoldHasNoAllowance;
var
  Piece: TPieceObject;
begin
  Piece := SquarePiece('10');
  AssertTrue(FPattern.LastError, FPattern.SetFoldEdge(Piece, FPattern.FindObject('Line_D_A').Key));
  FPattern.Evaluate;
  AssertTrue(Piece.Message, Piece.State = esValid);
  AssertNear('nothing added at the fold', 110 * 120, Abs(SignedArea(Piece.CutLine)), AreaTolerance);
  AssertTrue('the cut runs along the fold', HasPoint(Piece.CutLine, 0, -10));
end;

procedure TTestPiece.TestFoldOverridesEdgeAllowance;
var
  Piece: TPieceObject;
  Fold: string;
begin
  Piece := SquarePiece('10');
  Fold := FPattern.FindObject('Line_D_A').Key;
  AssertTrue(FPattern.SetEdgeAllowance(Piece, Piece.PathIndexOf(Fold), '25'));
  AssertTrue(FPattern.SetFoldEdge(Piece, Fold));
  FPattern.Evaluate;
  AssertNear('still none', 110 * 120, Abs(SignedArea(Piece.CutLine)), AreaTolerance);
  AssertTrue('clearing it brings the allowance back', FPattern.SetFoldEdge(Piece, ''));
  FPattern.Evaluate;
  AssertNear('the override', 135 * 120, Abs(SignedArea(Piece.CutLine)), AreaTolerance);
end;

procedure TTestPiece.TestFoldNotchAtFoldLine;
var
  Piece: TPieceObject;
  Fold: string;
begin
  Piece := SquarePiece('10');
  Fold := FPattern.FindObject('Line_D_A').Key;
  AssertTrue(FPattern.SetFoldEdge(Piece, Fold));
  AssertTrue(FPattern.AddEdgeNotch(Piece, Fold, '50'));
  FPattern.Evaluate;
  AssertPointsNear('no allowance to cross', Vec2(0, 50), Piece.NotchMarks[0].Cut);
end;

procedure TTestPiece.TestFoldArrowPointsAtFold;
var
  Piece: TPieceObject;
  Strokes: TLine2Array;
begin
  Piece := SquarePiece('10');
  AssertTrue(FPattern.SetFoldEdge(Piece, FPattern.FindObject('Line_D_A').Key));
  FPattern.Evaluate;
  Strokes := Piece.FoldArrow;
  AssertEquals('bracket, stubs and heads', 7, Length(Strokes));
  // The fold is x = 0, so the bracket stands inside the piece
  AssertNear('bracket inside', 20, Strokes[0].P1.X);
  AssertNear('stub ends on the fold', 0, Strokes[1].P2.X);
  AssertTrue('head comes back inside', Strokes[3].P2.X > 0);
end;

procedure TTestPiece.TestFoldChecks;
var
  A, B: string;
  Piece: TPieceObject;
  Curve: TCurveObject;
begin
  A := Pt('', 0, 0);
  B := Pt('', 100, 0);
  Line(A, B);
  Curve := FPattern.AddCurve(A, B, '90', '50', '90', '50', erOutline);
  Piece := FPattern.AddPiece('', Detect(50, -10), '10');
  AssertFalse('curved', FPattern.SetFoldEdge(Piece, Curve.Key));
  AssertEquals(Format(rsPatternFoldNotStraight, [Curve.Name]), FPattern.LastError);
  Line(B, Pt('', 200, 0));
  AssertFalse('not in the piece', FPattern.SetFoldEdge(Piece, FPattern.Objects[FPattern.ObjectCount - 1].Key));
end;

procedure TTestPiece.TestCutAndFoldRoundTrip;
var
  Piece: TPieceObject;
  Text, ErrorMessage: string;
  Loaded: TPattern;
begin
  Piece := SquarePiece('10');
  AssertTrue(FPattern.SetCut(Piece, 4, True));
  AssertTrue(FPattern.SetFoldEdge(Piece, Piece.Path[1].EdgeKey));
  Text := SavePatternToText(FPattern);
  Loaded := TPattern.Create;
  try
    AssertTrue(ErrorMessage, LoadPatternFromText(Loaded, Text, ErrorMessage));
    AssertEquals('same text', Text, SavePatternToText(Loaded));
    Piece := TPieceObject(Loaded.FindObject('Front'));
    AssertEquals(4, Piece.CutCount);
    AssertTrue(Piece.Mirrored);
    AssertTrue(Piece.OnFold);
  finally
    FreeAndNil(Loaded);
  end;
end;

initialization
  RegisterTest(TTestPiece);

end.
