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

// The Garment view: joining along seams, which seams join, opening out across
// the centre line, and the notes it gives.
unit Sloper.Tests.Garment;

{$mode ObjFPC}{$H+}

interface

uses
  SysUtils, fpcunit, testregistry, Sloper.Tests.TestCase, Sloper.Core.Geometry, Sloper.Core.Pattern, Sloper.Core.Piece,
  Sloper.Core.Seam, Sloper.Core.Fabrics, Sloper.Core.Garment;

type
  TTestGarment = class(TOSTestCase)
  private
    FPattern: TPattern;
    // An outline rectangle from (Left, Bottom), as a piece
    function Panel(const AName: string; Left, Bottom, Width, Height: double; View: TPieceView): TPieceObject;
    function EdgeNear(Piece: TPieceObject; X, Y: double): string;
    function Side(Piece: TPieceObject; const EdgeKey: string): TSeamSide;
    function ShapesOf(const Drawing: TGarmentDrawing; const AName: string): integer;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestViewChoosesPieces;
    procedure TestShapeTakesItsFabricLook;
    procedure TestBothShowsInEach;
    procedure TestNoViewIsCounted;
    procedure TestFailingPieceIsLeftOut;
    procedure TestLargestPieceStaysPut;
    procedure TestJoinMovesPieceAgainstSeam;
    procedure TestJoinRotatesToMatchSeam;
    procedure TestJoinUsesDirection;
    procedure TestFlipsOffThePieceItJoins;
    procedure TestSharesLengthDifference;
    procedure TestChainOfJoins;
    procedure TestSeamToOtherViewDoesNotJoin;
    procedure TestSpanningSeamDoesNotJoinEitherView;
    procedure TestUnjoinedGoesBeside;
    procedure TestFoldOpensOut;
    procedure TestFoldEdgeIsNotDrawn;
    procedure TestMirrorsCutTwiceAcrossFold;
    procedure TestPieceCutOnceIsNotMirrored;
    procedure TestSelfSeamIsCentreLine;
    procedure TestNoCentreLineIsOneSided;
    procedure TestCentreLineStandsUpright;
    procedure TestNothingInView;
    procedure TestViewSurvivesSaving;
    procedure TestNotes;
    procedure TestSVG;
    procedure TestSheetIsTrueScaleSideBySide;
    procedure TestSheetPlacesBackAfterFront;
    procedure TestSheetLeavesOutEmptySide;
    procedure TestSheetEscapesTitles;
    procedure TestSheetWithNothingStillDraws;
  end;

implementation

uses
  Math, Sloper.Core.Draft, Sloper.Core.PieceDetect, Sloper.Core.PatternFile, Sloper.Output.GarmentSVG, Sloper.UI.GarmentNotes;

procedure TTestGarment.SetUp;
begin
  FPattern := TPattern.Create;
end;

procedure TTestGarment.TearDown;
begin
  FreeAndNil(FPattern);
end;

function TTestGarment.Panel(const AName: string; Left, Bottom, Width, Height: double; View: TPieceView): TPieceObject;
var
  A, B, C, D, Reason: string;
  Path: TPiecePath;
  Fixed: TFormatSettings;

  function Pt(X, Y: double): string;
  begin
    Result := FPattern.AddFreePoint('', FloatToStr(X, Fixed), FloatToStr(Y, Fixed)).Key;
  end;

begin
  Fixed := DefaultFormatSettings;
  Fixed.DecimalSeparator := '.';
  A := Pt(Left, Bottom);
  B := Pt(Left + Width, Bottom);
  C := Pt(Left + Width, Bottom + Height);
  D := Pt(Left, Bottom + Height);
  FPattern.AddLine(A, B, erOutline);
  FPattern.AddLine(B, C, erOutline);
  FPattern.AddLine(C, D, erOutline);
  FPattern.AddLine(D, A, erOutline);
  FPattern.Evaluate;
  AssertTrue(Reason, DetectPiecePath(FPattern, Vec2(Left + Width / 2, Bottom + Height / 2), Path, Reason));
  Result := FPattern.AddPiece(AName, Path, '10');
  AssertNotNull(FPattern.LastError, Result);
  Result.View := View;
  FPattern.Evaluate;
end;

function TTestGarment.EdgeNear(Piece: TPieceObject; X, Y: double): string;
var
  Entry: TPieceEdge;
  Position, Gap: double;
begin
  for Entry in Piece.Path do
  begin
    TEdgeObject(FPattern.FindNode(Entry.EdgeKey)).Locate(Vec2(X, Y), Position, Gap);
    if Gap < 1 then
      Exit(Entry.EdgeKey);
  end;
  Fail('no edge there');
  Result := '';
end;

function TTestGarment.Side(Piece: TPieceObject; const EdgeKey: string): TSeamSide;
begin
  Result := nil;
  SetLength(Result, 1);
  Result[0].PieceKey := Piece.Key;
  Result[0].EdgeKey := EdgeKey;
end;

function TTestGarment.ShapesOf(const Drawing: TGarmentDrawing; const AName: string): integer;
var
  Shape: TGarmentShape;
begin
  Result := 0;
  for Shape in Drawing.Shapes do
    if Shape.PieceName = AName then
      Inc(Result);
end;

function ExtentOf(const Shape: TGarmentShape): TRect2;
var
  P: TVec2;
begin
  Result.MinX := Infinity;
  Result.MinY := Infinity;
  Result.MaxX := -Infinity;
  Result.MaxY := -Infinity;
  for P in Shape.Outline do
  begin
    Result.MinX := Min(Result.MinX, P.X);
    Result.MinY := Min(Result.MinY, P.Y);
    Result.MaxX := Max(Result.MaxX, P.X);
    Result.MaxY := Max(Result.MaxY, P.Y);
  end;
end;

function ExtentNamed(const Drawing: TGarmentDrawing; const AName: string): TRect2;
var
  Shape: TGarmentShape;
begin
  Result := Default(TRect2);
  for Shape in Drawing.Shapes do
    if Shape.PieceName = AName then
      Exit(ExtentOf(Shape));
end;

procedure TTestGarment.TestShapeTakesItsFabricLook;
var
  Drawing: TGarmentDrawing;
begin
  Panel('Front', 0, 0, 100, 200, pvFront);
  AssertTrue(FPattern.SetFabricColor(FPattern.Fabrics[0], '#102030'));
  FPattern.SetFabricFill(FPattern.Fabrics[0], ffHatch);
  Drawing := BuildGarment(FPattern, gsFront);
  AssertTrue(Drawing.Shapes[0].Look.Filled);
  AssertEquals('#102030', FabricColorText(Drawing.Shapes[0].Look.Color));
  AssertTrue(Drawing.Shapes[0].Look.Fill = ffHatch);
end;

procedure TTestGarment.TestViewChoosesPieces;
var
  Drawing: TGarmentDrawing;
begin
  Panel('Front', 0, 0, 100, 200, pvFront);
  Panel('Back', 300, 0, 100, 200, pvBack);
  Drawing := BuildGarment(FPattern, gsFront);
  AssertEquals('front', 1, ShapesOf(Drawing, 'Front'));
  AssertEquals('not back', 0, ShapesOf(Drawing, 'Back'));
  AssertEquals('back', 1, ShapesOf(BuildGarment(FPattern, gsBack), 'Back'));
end;

procedure TTestGarment.TestBothShowsInEach;
begin
  Panel('Sleeve', 0, 0, 100, 200, pvBoth);
  AssertEquals('front', 1, ShapesOf(BuildGarment(FPattern, gsFront), 'Sleeve'));
  AssertEquals('back', 1, ShapesOf(BuildGarment(FPattern, gsBack), 'Sleeve'));
end;

procedure TTestGarment.TestNoViewIsCounted;
begin
  Panel('Facing', 0, 0, 100, 200, pvNone);
  Panel('Front', 300, 0, 100, 200, pvFront);
  AssertEquals('in neither', 1, PiecesWithoutView(FPattern));
  AssertEquals('left out', 0, ShapesOf(BuildGarment(FPattern, gsFront), 'Facing'));
end;

procedure TTestGarment.TestFailingPieceIsLeftOut;
var
  Front: TPieceObject;
begin
  Front := Panel('Front', 0, 0, 100, 200, pvFront);
  AssertTrue(FPattern.LastError, FPattern.SetFormula(Front, PieceAllowanceField, '-1'));
  FPattern.Evaluate;
  AssertEquals('left out', 0, Length(BuildGarment(FPattern, gsFront).Shapes));
end;

procedure TTestGarment.TestLargestPieceStaysPut;
var
  Small, Large: TPieceObject;
  Extent: TRect2;
begin
  Small := Panel('Small', 0, 0, 50, 50, pvFront);
  Large := Panel('Large', 300, 0, 100, 200, pvFront);
  AssertNotNull(FPattern.LastError, FPattern.AddSeam('', Side(Small, EdgeNear(Small, 25, 50)), Side(Large, EdgeNear(Large, 350, 0))));
  FPattern.Evaluate;
  Extent := ExtentNamed(BuildGarment(FPattern, gsFront), 'Large');
  AssertNear('stays', 300, Extent.MinX);
end;

// A yoke's bottom edge against a skirt's top, drafted well apart
procedure TTestGarment.TestJoinMovesPieceAgainstSeam;
var
  Skirt, Yoke: TPieceObject;
  Drawing: TGarmentDrawing;
  Extent: TRect2;
begin
  Skirt := Panel('Skirt', 0, 0, 100, 200, pvFront);
  Yoke := Panel('Yoke', 400, 500, 100, 50, pvFront);
  AssertNotNull(FPattern.LastError, FPattern.AddSeam('', Side(Skirt, EdgeNear(Skirt, 50, 200)), Side(Yoke, EdgeNear(Yoke, 450, 500))));
  FPattern.Evaluate;
  Drawing := BuildGarment(FPattern, gsFront);
  Extent := ExtentNamed(Drawing, 'Yoke');
  AssertNear('on the skirt', 200, Extent.MinY);
  AssertNear('height kept', 250, Extent.MaxY);
  AssertNear('lined up', 0, Extent.MinX);
  AssertEquals('joined', 0, Length(Drawing.Unjoined));
end;

// Its side edge against the skirt's top, so it has to turn a quarter
procedure TTestGarment.TestJoinRotatesToMatchSeam;
var
  Skirt, Band: TPieceObject;
  Extent: TRect2;
begin
  Skirt := Panel('Skirt', 0, 0, 100, 200, pvFront);
  Band := Panel('Band', 400, 0, 30, 100, pvFront);
  AssertNotNull(FPattern.LastError, FPattern.AddSeam('', Side(Skirt, EdgeNear(Skirt, 50, 200)), Side(Band, EdgeNear(Band, 400, 50))));
  FPattern.Evaluate;
  Extent := ExtentNamed(BuildGarment(FPattern, gsFront), 'Band');
  AssertNear('lying along it', 100, Extent.MaxX - Extent.MinX);
  AssertNear('its width above', 30, Extent.MaxY - Extent.MinY);
  AssertNear('on the skirt', 200, Extent.MinY);
end;

// Reversed joins the far ends instead, which turns the piece end for end
procedure TTestGarment.TestJoinUsesDirection;
var
  Skirt, Yoke: TPieceObject;
  Seam: TSeamObject;
  Plain, Flipped: TGarmentDrawing;
  Extent: TRect2;
begin
  Skirt := Panel('Skirt', 0, 0, 100, 200, pvFront);
  Yoke := Panel('Yoke', 400, 500, 100, 50, pvFront);
  Seam := FPattern.AddSeam('', Side(Skirt, EdgeNear(Skirt, 50, 200)), Side(Yoke, EdgeNear(Yoke, 450, 500)));
  FPattern.Evaluate;
  Plain := BuildGarment(FPattern, gsFront);
  Seam.Reversed := True;
  Flipped := BuildGarment(FPattern, gsFront);
  Extent := ExtentNamed(Flipped, 'Yoke');
  AssertNear('still above the skirt', 200, Extent.MinY);
  AssertTrue('drawn the other way', not PointsNear(Plain.Shapes[1].Lines[0][0], Flipped.Shapes[1].Lines[0][0]));
end;

// Same edge of two panels, running the same way: laid straight on, one would
// cover the other
procedure TTestGarment.TestFlipsOffThePieceItJoins;
var
  Left, Right: TPieceObject;
  Seam: TSeamObject;
  Extent: TRect2;
begin
  Left := Panel('Left', 0, 0, 100, 200, pvFront);
  Right := Panel('Right', 300, 0, 80, 200, pvFront);
  Seam := FPattern.AddSeam('', Side(Left, EdgeNear(Left, 100, 100)), Side(Right, EdgeNear(Right, 380, 100)));
  Seam.Reversed := True;
  FPattern.Evaluate;
  Extent := ExtentNamed(BuildGarment(FPattern, gsFront), 'Right');
  AssertNear('beyond the seam', 100, Extent.MinX);
  AssertNear('its own width', 180, Extent.MaxX);
end;

// A side 20 mm longer sticks out 10 mm at each end
procedure TTestGarment.TestSharesLengthDifference;
var
  Skirt, Band: TPieceObject;
  Extent: TRect2;
begin
  Skirt := Panel('Skirt', 0, 0, 100, 200, pvFront);
  Band := Panel('Band', 400, 500, 120, 30, pvFront);
  AssertNotNull(FPattern.LastError, FPattern.AddSeam('', Side(Skirt, EdgeNear(Skirt, 50, 200)), Side(Band, EdgeNear(Band, 450, 500))));
  FPattern.Evaluate;
  Extent := ExtentNamed(BuildGarment(FPattern, gsFront), 'Band');
  AssertNear('shared', -10, Extent.MinX);
  AssertNear('shared', 110, Extent.MaxX);
end;

procedure TTestGarment.TestChainOfJoins;
var
  Skirt, Yoke, Band: TPieceObject;
  Extent: TRect2;
begin
  Skirt := Panel('Skirt', 0, 0, 100, 200, pvFront);
  Yoke := Panel('Yoke', 400, 500, 100, 50, pvFront);
  Band := Panel('Band', 800, 900, 100, 20, pvFront);
  AssertNotNull(FPattern.LastError, FPattern.AddSeam('', Side(Skirt, EdgeNear(Skirt, 50, 200)), Side(Yoke, EdgeNear(Yoke, 450, 500))));
  AssertNotNull(FPattern.LastError, FPattern.AddSeam('', Side(Yoke, EdgeNear(Yoke, 450, 550)), Side(Band, EdgeNear(Band, 850, 900))));
  FPattern.Evaluate;
  Extent := ExtentNamed(BuildGarment(FPattern, gsFront), 'Band');
  AssertNear('on the yoke', 250, Extent.MinY);
end;

procedure TTestGarment.TestSeamToOtherViewDoesNotJoin;
var
  Front, Back: TPieceObject;
  Drawing: TGarmentDrawing;
begin
  Front := Panel('Front', 0, 0, 100, 200, pvFront);
  Back := Panel('Back', 300, 0, 100, 200, pvBack);
  AssertNotNull(FPattern.LastError, FPattern.AddSeam('', Side(Front, EdgeNear(Front, 100, 100)), Side(Back, EdgeNear(Back, 300, 100))));
  FPattern.Evaluate;
  Drawing := BuildGarment(FPattern, gsFront);
  AssertEquals('alone, and that is no fault', 0, Length(Drawing.Unjoined));
  AssertEquals('one shape', 1, Length(Drawing.Shapes));
end;

// One seam round a front and a back armhole cannot join a sleeve in either view
procedure TTestGarment.TestSpanningSeamDoesNotJoinEitherView;
var
  Front, Back, Sleeve: TPieceObject;
  Drawing: TGarmentDrawing;
begin
  Front := Panel('Front', 0, 0, 200, 300, pvFront);
  Back := Panel('Back', 400, 0, 200, 300, pvBack);
  Sleeve := Panel('Sleeve', 800, 0, 100, 100, pvBoth);
  AssertNotNull(FPattern.LastError, FPattern.AddSeam('', Concat(Side(Front, EdgeNear(Front, 200, 150)), Side(Back, EdgeNear(Back, 400, 150))),
    Side(Sleeve, EdgeNear(Sleeve, 850, 100))));
  FPattern.Evaluate;
  Drawing := BuildGarment(FPattern, gsFront);
  AssertEquals('says so', 1, Length(Drawing.Unjoined));
  AssertEquals('Sleeve', Drawing.Unjoined[0]);
end;

procedure TTestGarment.TestUnjoinedGoesBeside;
var
  Drawing: TGarmentDrawing;
begin
  Panel('Front', 0, 0, 100, 200, pvFront);
  Panel('Pocket', 0, 500, 50, 50, pvFront);
  Drawing := BuildGarment(FPattern, gsFront);
  AssertEquals('Pocket', Drawing.Unjoined[0]);
  AssertTrue('to the right', ExtentNamed(Drawing, 'Pocket').MinX > ExtentNamed(Drawing, 'Front').MaxX);
end;

procedure TTestGarment.TestFoldOpensOut;
var
  Front: TPieceObject;
  Drawing: TGarmentDrawing;
begin
  Front := Panel('Front', 0, 0, 100, 200, pvFront);
  AssertTrue(FPattern.LastError, FPattern.SetFoldEdge(Front, EdgeNear(Front, 100, 100)));
  FPattern.Evaluate;
  Drawing := BuildGarment(FPattern, gsFront);
  AssertEquals('both halves', 2, ShapesOf(Drawing, 'Front'));
  AssertNear('whole width', 200, Drawing.Bounds.MaxX - Drawing.Bounds.MinX);
  AssertNear('same height', 200, Drawing.Bounds.MaxY - Drawing.Bounds.MinY);
  AssertFalse('nothing on one side only', Drawing.OneSided);
end;

procedure TTestGarment.TestFoldEdgeIsNotDrawn;
var
  Front: TPieceObject;
begin
  Front := Panel('Front', 0, 0, 100, 200, pvFront);
  AssertTrue(FPattern.LastError, FPattern.SetFoldEdge(Front, EdgeNear(Front, 100, 100)));
  FPattern.Evaluate;
  AssertEquals('three of the four edges', 3, Length(BuildGarment(FPattern, gsFront).Shapes[0].Lines));
end;

// A front on the fold with a side panel cut twice: a left and a right
procedure TTestGarment.TestMirrorsCutTwiceAcrossFold;
var
  Front, Panel2: TPieceObject;
  Drawing: TGarmentDrawing;
begin
  Front := Panel('Front', 0, 0, 100, 200, pvFront);
  Panel2 := Panel('Side', 400, 0, 50, 200, pvFront);
  FPattern.SetCut(Panel2, 2, True);
  AssertTrue(FPattern.LastError, FPattern.SetFoldEdge(Front, EdgeNear(Front, 0, 100)));
  AssertNotNull(FPattern.LastError, FPattern.AddSeam('', Side(Front, EdgeNear(Front, 100, 100)), Side(Panel2, EdgeNear(Panel2, 400, 100))));
  FPattern.Evaluate;
  Drawing := BuildGarment(FPattern, gsFront);
  AssertEquals('left and right', 2, ShapesOf(Drawing, 'Side'));
  AssertNear('both panels and both halves', 300, Drawing.Bounds.MaxX - Drawing.Bounds.MinX);
end;

procedure TTestGarment.TestPieceCutOnceIsNotMirrored;
var
  Front, Placket: TPieceObject;
  Drawing: TGarmentDrawing;
begin
  Front := Panel('Front', 0, 0, 100, 200, pvFront);
  Placket := Panel('Placket', 400, 0, 20, 200, pvFront);
  AssertTrue(FPattern.LastError, FPattern.SetFoldEdge(Front, EdgeNear(Front, 0, 100)));
  AssertNotNull(FPattern.LastError, FPattern.AddSeam('', Side(Front, EdgeNear(Front, 100, 100)), Side(Placket, EdgeNear(Placket, 400, 100))));
  FPattern.Evaluate;
  Drawing := BuildGarment(FPattern, gsFront);
  AssertEquals('once', 1, ShapesOf(Drawing, 'Placket'));
end;

procedure TTestGarment.TestSelfSeamIsCentreLine;
var
  Back: TPieceObject;
  Drawing: TGarmentDrawing;
begin
  Back := Panel('Back', 0, 0, 100, 200, pvBack);
  FPattern.SetCut(Back, 2, True);
  AssertNotNull(FPattern.LastError, FPattern.AddSeam('', Side(Back, EdgeNear(Back, 0, 100)), Side(Back, EdgeNear(Back, 0, 100))));
  FPattern.Evaluate;
  Drawing := BuildGarment(FPattern, gsBack);
  AssertEquals('left and right', 2, ShapesOf(Drawing, 'Back'));
  AssertNear('whole width', 200, Drawing.Bounds.MaxX - Drawing.Bounds.MinX);
end;

procedure TTestGarment.TestNoCentreLineIsOneSided;
var
  Back: TPieceObject;
  Drawing: TGarmentDrawing;
begin
  Back := Panel('Back', 0, 0, 100, 200, pvBack);
  FPattern.SetCut(Back, 2, True);
  FPattern.Evaluate;
  Drawing := BuildGarment(FPattern, gsBack);
  AssertEquals('one side', 1, ShapesOf(Drawing, 'Back'));
  AssertTrue('says so', Drawing.OneSided);
end;

// A fold across the piece stands up after a quarter turn
procedure TTestGarment.TestCentreLineStandsUpright;
var
  Front: TPieceObject;
  Drawing: TGarmentDrawing;
begin
  Front := Panel('Front', 0, 0, 200, 100, pvFront);
  AssertTrue(FPattern.LastError, FPattern.SetFoldEdge(Front, EdgeNear(Front, 100, 0)));
  FPattern.Evaluate;
  Drawing := BuildGarment(FPattern, gsFront);
  AssertNear('wide across the line', 200, Drawing.Bounds.MaxX - Drawing.Bounds.MinX);
  AssertNear('tall along it', 200, Drawing.Bounds.MaxY - Drawing.Bounds.MinY);
end;

procedure TTestGarment.TestNothingInView;
var
  Drawing: TGarmentDrawing;
begin
  Drawing := BuildGarment(FPattern, gsFront);
  AssertEquals('empty', 0, Length(Drawing.Shapes));
  AssertEquals('no notes', 0, Length(Drawing.Unjoined));
end;

procedure TTestGarment.TestViewSurvivesSaving;
var
  Front: TPieceObject;
  Loaded: TPattern;
  Err, Text: string;
begin
  Front := Panel('Front', 0, 0, 100, 200, pvBoth);
  Text := SavePatternToText(FPattern);
  Loaded := TPattern.Create;
  try
    AssertTrue(Err, LoadPatternFromText(Loaded, Text, Err));
    AssertTrue('kept', TPieceObject(Loaded.FindObject('Front')).View = pvBoth);
    Front.View := pvNone;
    AssertEquals('none is left out of the file', 0, Pos('"view"', SavePatternToText(FPattern)));
  finally
    FreeAndNil(Loaded);
  end;
end;

procedure TTestGarment.TestNotes;
var
  Back: TPieceObject;
  Notes: TStringArray;
begin
  Back := Panel('Back', 0, 0, 100, 200, pvBack);
  FPattern.SetCut(Back, 2, True);
  Panel('Pocket', 400, 0, 50, 50, pvBack);
  FPattern.Evaluate;
  Notes := GarmentNotes(BuildGarment(FPattern, gsBack), 'Back');
  AssertEquals('both', 2, Length(Notes));
  AssertEquals(Format(rsGarmentUnjoined, ['Back', 'Pocket']), Notes[0]);
  AssertEquals(Format(rsGarmentOneSided, ['Back']), Notes[1]);
end;

procedure TTestGarment.TestSVG;
var
  Text: string;
begin
  AssertTrue('empty still draws', Pos('<svg', GarmentToSVG(BuildGarment(FPattern, gsFront))) > 0);
  Panel('Front', 0, 0, 100, 200, pvFront);
  Text := GarmentToSVG(BuildGarment(FPattern, gsFront));
  AssertTrue(Text, Pos('data-name="Front"', Text) > 0);
  AssertTrue(Text, Pos('width="120mm" height="220mm"', Text) > 0);
end;

procedure TTestGarment.TestSheetIsTrueScaleSideBySide;
var
  Text: string;
begin
  Panel('Front', 0, 0, 100, 200, pvFront);
  Panel('Back', 300, 0, 150, 300, pvBack);
  Text := GarmentSheetToSVG(BuildGarment(FPattern, gsFront), BuildGarment(FPattern, gsBack), 'Front', 'Back');
  // 10 margin, 100, 60 gap, 150, 10 margin across; 10, 24 title, 300, 10 down
  AssertTrue(Text, Pos('width="330mm" height="344mm" viewBox="0 0 330 344"', Text) > 0);
  AssertTrue(Text, Pos('data-side="front"', Text) > 0);
  AssertTrue(Text, Pos('data-side="back"', Text) > 0);
  AssertTrue(Text, Pos('>Front</text>', Text) > 0);
  AssertTrue(Text, Pos('>Back</text>', Text) > 0);
end;

procedure TTestGarment.TestSheetPlacesBackAfterFront;
var
  Text: string;
begin
  Panel('Front', 50, 20, 100, 200, pvFront);
  Panel('Back', 300, 0, 150, 300, pvBack);
  Text := GarmentSheetToSVG(BuildGarment(FPattern, gsFront), BuildGarment(FPattern, gsBack), 'Front', 'Back');
  // Each side's top left lands at its place on the sheet, whatever its model position
  AssertTrue(Text, Pos('data-side="front" transform="translate(-40 254)"', Text) > 0);
  AssertTrue(Text, Pos('data-side="back" transform="translate(-130 334)"', Text) > 0);
end;

procedure TTestGarment.TestSheetLeavesOutEmptySide;
var
  Text: string;
begin
  Panel('Front', 0, 0, 100, 200, pvFront);
  Text := GarmentSheetToSVG(BuildGarment(FPattern, gsFront), BuildGarment(FPattern, gsBack), 'Front', 'Back');
  AssertEquals('no back', 0, Pos('data-side="back"', Text));
  AssertTrue(Text, Pos('width="120mm" height="244mm"', Text) > 0);
end;

procedure TTestGarment.TestSheetEscapesTitles;
var
  Text: string;
begin
  Panel('Front', 0, 0, 100, 200, pvFront);
  Text := GarmentSheetToSVG(BuildGarment(FPattern, gsFront), BuildGarment(FPattern, gsBack), 'A & B', 'Back');
  AssertTrue(Text, Pos('>A &amp; B</text>', Text) > 0);
end;

procedure TTestGarment.TestSheetWithNothingStillDraws;
var
  Text: string;
begin
  Text := GarmentSheetToSVG(BuildGarment(FPattern, gsFront), BuildGarment(FPattern, gsBack), 'Front', 'Back');
  AssertTrue(Text, Pos('<svg', Text) > 0);
  AssertTrue(Text, Pos('</svg>', Text) > 0);
end;

initialization
  RegisterTest(TTestGarment);

end.
