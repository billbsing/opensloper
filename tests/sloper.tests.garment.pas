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

// The Garment view: closing darts, opening folds, placing pieces, shading,
// rebuilding only what changed, and the SVG export.
unit Sloper.Tests.Garment;

{$mode ObjFPC}{$H+}

interface

uses
  SysUtils, Math, fpcunit, testregistry, Sloper.Tests.TestCase, Sloper.Core.Geometry, Sloper.Core.Draft, Sloper.Core.Pattern,
  Sloper.Core.Piece, Sloper.Core.Seam, Sloper.Core.Warp, Sloper.Core.Garment, Sloper.Output.GarmentSVG;

type
  TTestWarp = class(TOSTestCase)
  published
    procedure TestLegsMeetOnBisector;
    procedure TestUnequalLegsMeetHalfway;
    procedure TestOppositeSideStays;
    procedure TestOpeningMustBeOutside;
    procedure TestTwoDartsBothClose;
  end;

  TTestGarment = class(TOSTestCase)
  private
    FPattern: TPattern;
    function Pt(X, Y: double): string;
    // A closed outline through the points, as a piece
    function Shape(const AName: string; const Xs, Ys: array of double): TPieceObject;
    function Side(Piece: TPieceObject; const EdgeKey: string): TSeamSide;
    // A 200 mm square with a dart in its top edge: legs from (90, 0) and
    // (110, 0) to the apex at (100, 60), and the dart seam
    function DartedSquare(out Seam: TSeamObject): TPieceObject;
    function FindPiece(const Scene: TGarmentScene; const AName: string): TGarmentPiece;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestPlainPieceKeepsItsPlace;
    procedure TestDartCloses;
    procedure TestDartKeepsFarSideInPlace;
    procedure TestWideDartLeftOpen;
    procedure TestFoldOpens;
    procedure TestGrainlineStandsUpright;
    procedure TestSeamEdgesAreSewn;
    procedure TestFailingPieceNoted;
    procedure TestRebuildsOnlyChangedPieces;
    procedure TestMaterialFilter;
    procedure TestStackingOrder;
    procedure TestLongNarrowShadedAcross;
    procedure TestShadeBrightestNearMiddle;
    procedure TestShadeOff;
    procedure TestSpan;
    procedure TestEdgeFacing;
    procedure TestPieceAt;
    procedure TestSVG;
  end;

implementation

{ TTestWarp }

procedure TTestWarp.TestLegsMeetOnBisector;
var
  Dart: TDartClosing;
  Warp: TPieceWarp;
  Square: TVec2Array;
begin
  Square := [Vec2(0, 0), Vec2(90, 0), Vec2(100, 60), Vec2(110, 0), Vec2(200, 0), Vec2(200, 200), Vec2(0, 200)];
  AssertTrue(MakeDartClosing(Vec2(100, 60), Vec2(90, 0), Vec2(110, 0), Square, Dart));
  AssertNear('opening', 2 * RadToDeg(ArcTan(double(10) / 60)), Dart.Opening, 1e-9);
  AssertNear('points up', 90, Dart.Bisector, 1e-9);
  Warp := TPieceWarp.Create;
  try
    Warp.AddDart(Dart);
    AssertPointsNear('legs meet', Warp.Close(Vec2(90, 0)), Warp.Close(Vec2(110, 0)), 1e-6);
    AssertPointsNear('on the bisector', ClosedDartEnd(Dart), Warp.Close(Vec2(90, 0)), 1e-6);
    AssertPointsNear('apex stays', Vec2(100, 60), Warp.Close(Vec2(100, 60)));
  finally
    FreeAndNil(Warp);
  end;
end;

procedure TTestWarp.TestUnequalLegsMeetHalfway;
var
  Dart: TDartClosing;
  Warp: TPieceWarp;
  Shape: TVec2Array;
begin
  Shape := [Vec2(0, 0), Vec2(90, 0), Vec2(100, 60), Vec2(110, -20), Vec2(200, -20), Vec2(200, 200), Vec2(0, 200)];
  AssertTrue(MakeDartClosing(Vec2(100, 60), Vec2(90, 0), Vec2(110, -20), Shape, Dart));
  Warp := TPieceWarp.Create;
  try
    Warp.AddDart(Dart);
    AssertPointsNear('legs meet', Warp.Close(Vec2(90, 0)), Warp.Close(Vec2(110, -20)), 1e-6);
    AssertNear('halfway', (Distance(Vec2(100, 60), Vec2(90, 0)) + Distance(Vec2(100, 60), Vec2(110, -20))) / 2,
      Distance(Vec2(100, 60), Warp.Close(Vec2(90, 0))), 1e-6);
  finally
    FreeAndNil(Warp);
  end;
end;

procedure TTestWarp.TestOppositeSideStays;
var
  Dart: TDartClosing;
  Warp: TPieceWarp;
  Square: TVec2Array;
  Opposite, Beside: TVec2;
begin
  Square := [Vec2(0, 0), Vec2(90, 0), Vec2(100, 60), Vec2(110, 0), Vec2(200, 0), Vec2(200, 200), Vec2(0, 200)];
  AssertTrue(MakeDartClosing(Vec2(100, 60), Vec2(90, 0), Vec2(110, 0), Square, Dart));
  Warp := TPieceWarp.Create;
  try
    Warp.AddDart(Dart);
    Opposite := Vec2(100, 200);
    AssertPointsNear('opposite', Opposite, Warp.Close(Opposite), 1e-9);
    // Beside the dart moves most
    Beside := Vec2(80, 0);
    AssertTrue('beside moves', Distance(Beside, Warp.Close(Beside)) > Distance(Vec2(0, 200), Warp.Close(Vec2(0, 200))));
  finally
    FreeAndNil(Warp);
  end;
end;

procedure TTestWarp.TestOpeningMustBeOutside;
var
  Dart: TDartClosing;
  Square: TVec2Array;
begin
  // A plain convex corner: between its edges is the piece
  Square := [Vec2(0, 0), Vec2(100, 0), Vec2(100, 100), Vec2(0, 100)];
  AssertFalse(MakeDartClosing(Vec2(0, 0), Vec2(100, 0), Vec2(0, 100), Square, Dart));
end;

procedure TTestWarp.TestTwoDartsBothClose;
var
  First, Second: TDartClosing;
  Warp: TPieceWarp;
  Shape: TVec2Array;
begin
  Shape := [Vec2(0, 0), Vec2(40, 0), Vec2(50, 50), Vec2(60, 0), Vec2(140, 0), Vec2(150, 50), Vec2(160, 0), Vec2(200, 0),
    Vec2(200, 200), Vec2(0, 200)];
  AssertTrue(MakeDartClosing(Vec2(50, 50), Vec2(40, 0), Vec2(60, 0), Shape, First));
  AssertTrue(MakeDartClosing(Vec2(150, 50), Vec2(140, 0), Vec2(160, 0), Shape, Second));
  Warp := TPieceWarp.Create;
  try
    Warp.AddDart(First);
    Warp.AddDart(Second);
    AssertPointsNear('first', Warp.Close(Vec2(40, 0)), Warp.Close(Vec2(60, 0)), 1e-6);
    AssertPointsNear('second', Warp.Close(Vec2(140, 0)), Warp.Close(Vec2(160, 0)), 1e-6);
  finally
    FreeAndNil(Warp);
  end;
end;

{ TTestGarment }

procedure TTestGarment.SetUp;
begin
  FPattern := TPattern.Create;
end;

procedure TTestGarment.TearDown;
begin
  FreeAndNil(FPattern);
end;

function TTestGarment.Pt(X, Y: double): string;
begin
  Result := FPattern.AddFreePoint('', FloatToStr(X), FloatToStr(Y)).Key;
end;

function TTestGarment.Shape(const AName: string; const Xs, Ys: array of double): TPieceObject;
var
  Keys: array of string;
  Index: integer;
  Path: TPiecePath;
begin
  Keys := nil;
  SetLength(Keys, Length(Xs));
  for Index := 0 to High(Xs) do
    Keys[Index] := Pt(Xs[Index], Ys[Index]);
  Path := nil;
  SetLength(Path, Length(Keys));
  for Index := 0 to High(Keys) do
  begin
    Path[Index].EdgeKey := FPattern.AddLine(Keys[Index], Keys[(Index + 1) mod Length(Keys)], erOutline).Key;
    Path[Index].Reversed := False;
  end;
  FPattern.Evaluate;
  Result := FPattern.AddPiece(AName, Path, '10');
  AssertNotNull(FPattern.LastError, Result);
  FPattern.Evaluate;
end;

function TTestGarment.Side(Piece: TPieceObject; const EdgeKey: string): TSeamSide;
begin
  Result := nil;
  SetLength(Result, 1);
  Result[0].PieceKey := Piece.Key;
  Result[0].EdgeKey := EdgeKey;
end;

function TTestGarment.DartedSquare(out Seam: TSeamObject): TPieceObject;
var
  LegA, LegB: string;
  Index: integer;
  Edge: TEdgeObject;
begin
  Result := Shape('Front', [0, 90, 100, 110, 200, 200, 0], [0, 0, 60, 0, 0, 200, 200]);
  LegA := '';
  LegB := '';
  for Index := 0 to High(Result.Path) do
  begin
    Edge := TEdgeObject(FPattern.FindNode(Result.Path[Index].EdgeKey));
    if PointsNear(Edge.PointAtLength(0), Vec2(90, 0)) or PointsNear(Edge.PointAtLength(Edge.Length), Vec2(90, 0)) then
      if PointsNear(Edge.PointAtLength(0), Vec2(100, 60)) or PointsNear(Edge.PointAtLength(Edge.Length), Vec2(100, 60)) then
        LegA := Edge.Key;
    if PointsNear(Edge.PointAtLength(0), Vec2(110, 0)) or PointsNear(Edge.PointAtLength(Edge.Length), Vec2(110, 0)) then
      if PointsNear(Edge.PointAtLength(0), Vec2(100, 60)) or PointsNear(Edge.PointAtLength(Edge.Length), Vec2(100, 60)) then
        LegB := Edge.Key;
  end;
  AssertTrue('legs', (LegA <> '') and (LegB <> ''));
  Seam := FPattern.AddSeam('Dart', Side(Result, LegA), Side(Result, LegB));
  AssertNotNull(FPattern.LastError, Seam);
  FPattern.Evaluate;
end;

function TTestGarment.FindPiece(const Scene: TGarmentScene; const AName: string): TGarmentPiece;
var
  Piece: TGarmentPiece;
begin
  for Piece in Scene.Pieces do
    if Piece.Name = AName then
      Exit(Piece);
  Fail('No piece ' + AName);
  Result := Default(TGarmentPiece);
end;

procedure TTestGarment.TestPlainPieceKeepsItsPlace;
var
  Scene: TGarmentScene;
  Piece: TGarmentPiece;
begin
  Shape('Back', [10, 110, 110, 10], [20, 20, 220, 220]);
  Scene := BuildGarment(FPattern);
  AssertEquals(1, Length(Scene.Pieces));
  Piece := Scene.Pieces[0];
  AssertEquals(4, Length(Piece.Outline));
  AssertEquals('edges', 4, Length(Piece.Edges));
  AssertNear('left', 10, Piece.Bounds.MinX);
  AssertNear('top', 20, Piece.Bounds.MinY);
  AssertNear('right', 110, Piece.Bounds.MaxX);
  AssertNear('bottom', 220, Piece.Bounds.MaxY);
  AssertEquals('no notes', 0, Length(Scene.Notes));
end;

procedure TTestGarment.TestDartCloses;
var
  Seam: TSeamObject;
  Scene: TGarmentScene;
  Piece: TGarmentPiece;
  Stitch: TGarmentLine;
  Point: TVec2;
begin
  DartedSquare(Seam);
  Scene := BuildGarment(FPattern);
  Piece := Scene.Pieces[0];
  // The legs are gone from the outline, and the dart is one stitch line
  AssertEquals('edges', 5, Length(Piece.Edges));
  AssertEquals('stitches', 1, Length(Piece.Stitches));
  Stitch := Piece.Stitches[0];
  AssertEquals('seam', Seam.Key, Stitch.SeamKey);
  AssertEquals(2, Length(Stitch.Points));
  AssertNear('stitch is the leg length', Distance(Vec2(100, 60), Vec2(90, 0)), Distance(Stitch.Points[0], Stitch.Points[1]), 1e-6);
  // The outline reaches the end of the closed dart
  for Point in Piece.Outline do
    AssertTrue('no apex in the outline', Distance(Point, Stitch.Points[0]) > 1);
  AssertEquals('no notes', 0, Length(Scene.Notes));
end;

procedure TTestGarment.TestDartKeepsFarSideInPlace;
var
  Seam: TSeamObject;
  Scene: TGarmentScene;
  Piece: TGarmentPiece;
  Point: TVec2;
  Kept: boolean;
begin
  DartedSquare(Seam);
  Scene := BuildGarment(FPattern);
  Piece := Scene.Pieces[0];
  // One of the bottom corners, furthest from the apex, stays exactly
  Kept := False;
  for Point in Piece.Outline do
    Kept := Kept or PointsNear(Point, Vec2(0, 200), 1e-6) or PointsNear(Point, Vec2(200, 200), 1e-6);
  AssertTrue('a far corner stays', Kept);
  // And the piece does not drift far
  AssertTrue('stays near', Abs(Piece.Bounds.MinX) < 20);
end;

procedure TTestGarment.TestWideDartLeftOpen;
var
  LegA, LegB: string;
  Piece: TPieceObject;
  Scene: TGarmentScene;
  Index: integer;
  Edge: TEdgeObject;
begin
  // Legs from (20, 0) and (180, 0) down to (100, 40): over 90° open
  Piece := Shape('Wide', [0, 20, 100, 180, 200, 200, 0], [0, 0, 40, 0, 0, 200, 200]);
  LegA := '';
  LegB := '';
  for Index := 0 to High(Piece.Path) do
  begin
    Edge := TEdgeObject(FPattern.FindNode(Piece.Path[Index].EdgeKey));
    if PointsNear(Edge.PointAtLength(Edge.Length), Vec2(100, 40)) or PointsNear(Edge.PointAtLength(0), Vec2(100, 40)) then
      if LegA = '' then
        LegA := Edge.Key
      else
        LegB := Edge.Key;
  end;
  AssertNotNull(FPattern.LastError, FPattern.AddSeam('Dart', Side(Piece, LegA), Side(Piece, LegB)));
  FPattern.Evaluate;
  Scene := BuildGarment(FPattern);
  AssertEquals('note', 1, Length(Scene.Notes));
  AssertTrue(Scene.Notes[0], Pos('wider', Scene.Notes[0]) > 0);
  AssertEquals('legs stay', 7, Length(Scene.Pieces[0].Edges));
  AssertEquals('no stitch', 0, Length(Scene.Pieces[0].Stitches));
end;

procedure TTestGarment.TestFoldOpens;
var
  Piece: TPieceObject;
  Scene: TGarmentScene;
  Index: integer;
  Edge: TEdgeObject;
  Finished: TGarmentPiece;
begin
  Piece := Shape('Front', [0, 100, 100, 0], [0, 0, 200, 200]);
  for Index := 0 to High(Piece.Path) do
  begin
    Edge := TEdgeObject(FPattern.FindNode(Piece.Path[Index].EdgeKey));
    if PointsNear(Edge.PointAtLength(0), Vec2(0, 200)) or PointsNear(Edge.PointAtLength(Edge.Length), Vec2(0, 200)) then
      if PointsNear(Edge.PointAtLength(0), Vec2(0, 0)) or PointsNear(Edge.PointAtLength(Edge.Length), Vec2(0, 0)) then
        AssertTrue(FPattern.LastError, FPattern.SetFoldEdge(Piece, Edge.Key));
  end;
  FPattern.Evaluate;
  Scene := BuildGarment(FPattern);
  Finished := Scene.Pieces[0];
  AssertNear('opened left', -100, Finished.Bounds.MinX, 1e-6);
  AssertNear('right stays', 100, Finished.Bounds.MaxX, 1e-6);
  AssertNear('area doubles', 2 * Piece.Area, Abs(SignedArea(Finished.Outline)), 1e-6);
  // Three edges on each half; the fold has none
  AssertEquals('edges', 6, Length(Finished.Edges));
end;

procedure TTestGarment.TestGrainlineStandsUpright;
var
  Piece: TPieceObject;
  Scene: TGarmentScene;
begin
  Piece := Shape('Band', [0, 200, 200, 0], [0, 0, 50, 50]);
  AssertTrue(FPattern.LastError, FPattern.SetGrainAngle(Piece, '0'));
  FPattern.Evaluate;
  Scene := BuildGarment(FPattern);
  AssertNear('now tall', 200, Scene.Pieces[0].Bounds.MaxY - Scene.Pieces[0].Bounds.MinY, 1e-6);
  AssertNear('and narrow', 50, Scene.Pieces[0].Bounds.MaxX - Scene.Pieces[0].Bounds.MinX, 1e-6);
  // About its middle
  AssertNear('centre', 100, (Scene.Pieces[0].Bounds.MaxX + Scene.Pieces[0].Bounds.MinX) / 2, 1e-6);
end;

procedure TTestGarment.TestSeamEdgesAreSewn;
var
  Front, Back: TPieceObject;
  Scene: TGarmentScene;
  Line: TGarmentLine;
  Sewn: integer;
begin
  Front := Shape('Front', [0, 100, 100, 0], [0, 0, 200, 200]);
  Back := Shape('Back', [300, 400, 400, 300], [0, 0, 200, 200]);
  AssertNotNull(FPattern.LastError, FPattern.AddSeam('Side', Side(Front, Front.Path[1].EdgeKey), Side(Back, Back.Path[3].EdgeKey)));
  FPattern.Evaluate;
  Scene := BuildGarment(FPattern);
  Sewn := 0;
  for Line in FindPiece(Scene, 'Front').Edges do
    if Line.Sewn then
    begin
      Inc(Sewn);
      AssertEquals(Front.Path[1].EdgeKey, Line.EdgeKey);
    end;
  AssertEquals('one sewn edge', 1, Sewn);
end;

procedure TTestGarment.TestFailingPieceNoted;
var
  Piece: TPieceObject;
  Scene: TGarmentScene;
begin
  Piece := Shape('Front', [0, 100, 100, 0], [0, 0, 200, 200]);
  AssertTrue(FPattern.SetFormula(Piece, PIECE_ALLOWANCE_FIELD, '-1'));
  FPattern.Evaluate;
  Scene := BuildGarment(FPattern);
  AssertEquals('left out', 0, Length(Scene.Pieces));
  AssertEquals('noted', 1, Length(Scene.Notes));
end;

procedure TTestGarment.TestRebuildsOnlyChangedPieces;
var
  Builder: TGarmentBuilder;
  Scene: TGarmentScene;
  Corner: TDraftObject;
begin
  Shape('Front', [0, 100, 100, 0], [0, 0, 200, 200]);
  Shape('Back', [300, 400, 400, 300], [0, 0, 200, 200]);
  Builder := TGarmentBuilder.Create;
  try
    Scene := Builder.Build(FPattern);
    AssertEquals('first build', 2, Builder.Rebuilt);
    Scene := Builder.Build(FPattern);
    AssertEquals('nothing changed', 0, Builder.Rebuilt);
    // Move one corner of the back
    Corner := FPattern.Objects[FPattern.ObjectCount - 1];
    Corner := TDraftObject(FPattern.FindNode(TEdgeObject(FPattern.FindNode(TPieceObject(Corner).Path[0].EdgeKey)).StartKey));
    AssertTrue(FPattern.LastError, FPattern.SetFormula(Corner, 'x', '310'));
    FPattern.Evaluate;
    Scene := Builder.Build(FPattern);
    AssertEquals('one changed', 1, Builder.Rebuilt);
    AssertEquals(2, Length(Scene.Pieces));
  finally
    FreeAndNil(Builder);
  end;
end;

procedure TTestGarment.TestMaterialFilter;
var
  Back: TPieceObject;
  Scene, Shown: TGarmentScene;
begin
  Shape('Front', [0, 100, 100, 0], [0, 0, 200, 200]);
  Back := Shape('Lining', [300, 400, 400, 300], [0, 0, 200, 200]);
  FPattern.SetPieceMaterial(Back, FPattern.AddMaterial('Lining', '#AA3333'));
  FPattern.Evaluate;
  Scene := BuildGarment(FPattern);
  AssertEquals('all', 2, Length(GarmentOfMaterial(Scene, -1).Pieces));
  Shown := GarmentOfMaterial(Scene, 0);
  AssertEquals('main', 1, Length(Shown.Pieces));
  AssertEquals('Front', Shown.Pieces[0].Name);
  AssertNear('bounds follow', 100, Shown.Bounds.MaxX);
  Shown := GarmentOfMaterial(Scene, 1);
  AssertEquals('lining', 1, Length(Shown.Pieces));
  AssertEquals('Lining', Shown.Pieces[0].Name);
end;

procedure TTestGarment.TestStackingOrder;
var
  Scene: TGarmentScene;
begin
  // Drawn over each other, in pattern order
  Shape('Back', [0, 100, 100, 0], [0, 0, 200, 200]);
  Shape('Front', [20, 120, 120, 20], [0, 0, 200, 200]);
  Scene := BuildGarment(FPattern);
  AssertEquals('Back', Scene.Pieces[0].Name);
  AssertEquals('Front', Scene.Pieces[1].Name);
  AssertEquals('top piece', 1, GarmentPieceAt(Scene, Vec2(50, 100)));
  AssertEquals('under', 0, GarmentPieceAt(Scene, Vec2(10, 100)));
end;

procedure TTestGarment.TestLongNarrowShadedAcross;
var
  Scene: TGarmentScene;
begin
  Shape('Waistband', [0, 300, 300, 0], [0, 0, 40, 40]);
  Shape('Front', [0, 100, 100, 0], [100, 100, 300, 300]);
  Scene := BuildGarment(FPattern);
  AssertTrue('band', FindPiece(Scene, 'Waistband').ShadeColumns);
  AssertFalse('front', FindPiece(Scene, 'Front').ShadeColumns);
end;

procedure TTestGarment.TestShadeBrightestNearMiddle;
var
  Light: TGarmentLight;
begin
  Light := DefaultGarmentLight;
  AssertTrue('middle over left side', GarmentShade(0.45, False, Light) > GarmentShade(0.02, False, Light));
  AssertTrue('middle over right side', GarmentShade(0.45, False, Light) > GarmentShade(0.98, False, Light));
  // Lit from the upper left
  AssertTrue('left over right', GarmentShade(0.25, False, Light) > GarmentShade(0.75, False, Light));
  AssertTrue('top over bottom', GarmentShade(0.25, True, Light) > GarmentShade(0.75, True, Light));
  // Stronger means more contrast
  Light.Strength := 1;
  AssertTrue('stronger', GarmentShade(0.98, False, Light) < GarmentShade(0.98, False, DefaultGarmentLight));
  Light.Strength := 0;
  AssertNear('flat', 1, GarmentShade(0.98, False, Light), 1e-12);
end;

procedure TTestGarment.TestShadeOff;
var
  Light: TGarmentLight;
begin
  Light := DefaultGarmentLight;
  Light.Enabled := False;
  AssertNear('off', 1, GarmentShade(0.1, False, Light), 1e-12);
end;

procedure TTestGarment.TestSpan;
var
  Low, High: double;
  Triangle: TVec2Array;
begin
  Triangle := [Vec2(0, 0), Vec2(100, 100), Vec2(0, 100)];
  AssertTrue(GarmentSpan(Triangle, False, 50, Low, High));
  AssertNear('row left', 0, Low);
  AssertNear('row right', 50, High);
  AssertTrue(GarmentSpan(Triangle, True, 20, Low, High));
  AssertNear('column top', 20, Low);
  AssertNear('column bottom', 100, High);
  AssertFalse('miss', GarmentSpan(Triangle, False, 150, Low, High));
end;

procedure TTestGarment.TestEdgeFacing;
var
  Square: TVec2Array;
  Light: TGarmentLight;
begin
  Square := [Vec2(0, 0), Vec2(100, 0), Vec2(100, 100), Vec2(0, 100)];
  Light := DefaultGarmentLight;
  // The top edge faces up, towards a light from the upper left; the bottom away
  AssertTrue('top', GarmentEdgeFacing(Square, Vec2(0, 0), Vec2(100, 0), Light) > 0);
  AssertTrue('bottom', GarmentEdgeFacing(Square, Vec2(100, 100), Vec2(0, 100), Light) < 0);
  AssertPointsNear('inward of top', Vec2(0, 1), GarmentInward(Square, Vec2(0, 0), Vec2(100, 0)));
end;

procedure TTestGarment.TestPieceAt;
var
  Scene: TGarmentScene;
begin
  Shape('Front', [0, 100, 100, 0], [0, 0, 200, 200]);
  Scene := BuildGarment(FPattern);
  AssertEquals(0, GarmentPieceAt(Scene, Vec2(50, 50)));
  AssertEquals(-1, GarmentPieceAt(Scene, Vec2(150, 50)));
end;

procedure TTestGarment.TestSVG;
var
  Seam: TSeamObject;
  Text: string;
begin
  DartedSquare(Seam);
  Text := GarmentToSVG(BuildGarment(FPattern), DefaultGarmentLight);
  AssertTrue('svg', Pos('<svg', Text) = 1);
  AssertTrue('piece', Pos('data-piece="Front"', Text) > 0);
  AssertTrue('gradient', Pos('<linearGradient', Text) > 0);
  AssertTrue('clipped', Pos('clip-path=', Text) > 0);
  AssertTrue('stitch', Pos('stroke-dasharray', Text) > 0);
  AssertTrue('closed', Pos('</svg>', Text) > 0);
  Text := GarmentToSVG(BuildGarment(FPattern), Default(TGarmentLight));
  AssertTrue('no shading when off', Pos('<linearGradient', Text) = 0);
end;

initialization
  RegisterTest(TTestWarp);
  RegisterTest(TTestGarment);
end.
