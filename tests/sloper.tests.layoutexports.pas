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

// SVG and DXF export, the export gate and Pack Pieces.
unit Sloper.Tests.LayoutExports;

{$mode ObjFPC}{$H+}

interface

uses
  SysUtils, Classes, fpcunit, testregistry, Sloper.Tests.TestCase, Sloper.Core.Geometry, Sloper.Core.Pattern, Sloper.Core.Piece,
  Sloper.Output.Layout;

type
  TTestLayoutExports = class(TOSTestCase)
  private
    FFolder: string;
    FLayout: TLayout;
    // A pattern of rectangles Width by Height, 10 mm allowance, each cut Cut
    // times, saved as AFile and added to the layout as a source
    procedure AddPattern(const AFile: string; const Widths, Heights: array of double; Cut: integer = 1; Fold: boolean = False);
    // A 100 mm square, 10 mm allowance, with one marking of each kind: a 4 mm
    // hole at (30, 40), a placement line, a fold line and stitch holes
    procedure AddMarkedPattern(const AFile: string; Fold: boolean = False);
    // Puts the first piece of the first source on a new fabric, Lining
    procedure LineFirstPiece;
    procedure UseMaterial(Width: double; ALength: double = 0);
    procedure UseA4;
    function Count(const Needle, Text: string): integer;
    function PagesUsed: integer;
    procedure AssertNoOverlap;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestSVGIsTrueScale;
    procedure TestSVGGroupsEachCopy;
    procedure TestSVGFollowsPlacement;
    procedure TestSVGEscapesNames;
    procedure TestSVGRepeatsExactly;
    procedure TestDXFOneBlockPerPiece;
    procedure TestDXFLayers;
    procedure TestDXFUsesPieceCoordinates;
    procedure TestDXFIsR12;
    procedure TestDXFQuantityIsCutCount;
    procedure TestDXFNamesFabric;
    procedure TestDXFFoldIsMirrorLine;
    procedure TestDXFNotch;
    procedure TestDXFOnlyPlacedPieces;
    procedure TestDXFBlockNamesAreUnique;
    procedure TestDXFRepeatsExactly;
    procedure TestPlacedMarksKeepTheirType;
    procedure TestPlacedHoleIsWhole;
    procedure TestPlacedHoleFollowsFlip;
    procedure TestPlacedButtonIsAMark;
    procedure TestLeatherRolesPrint;
    procedure TestOutputProfileSaved;
    procedure TestUnknownOutputProfileBlocksExport;
    procedure TestLeatherCutsOnSeamLine;
    procedure TestCutterProfileKeepsCutAndHoles;
    procedure TestInstructionsProfile;
    procedure TestProfileStylesOnPaper;
    procedure TestMachineProfileAfterOutputProfile;
    procedure TestAAMAFollowsOutputProfile;
    procedure TestPaperMarksKeepEverything;
    procedure TestFoldStaysHalfOnPaper;
    procedure TestFoldOpensWithProfile;
    procedure TestFoldOpensOnMaterial;
    procedure TestOpenedSeamLineIsWhole;
    procedure TestOpenedHolesOnBothHalves;
    procedure TestHoleOnTheFoldRefused;
    procedure TestStitchHolesOnTheFoldOnce;
    procedure TestOpenedCaptionDropsFold;
    procedure TestOpenedFoldIsAMark;
    procedure TestAAMAKeepsTheHalf;
    procedure TestMaterialRoundTrip;
    procedure TestMaterialDefaultsNotSaved;
    procedure TestBadMaterialRefused;
    procedure TestMaterialPacksToWidth;
    procedure TestMaterialDoesNotTurn;
    procedure TestMaterialTurnsWhenAllowed;
    procedure TestMaterialLengthLimitsPacking;
    procedure TestMaterialWarnsPastWidth;
    procedure TestMaterialWarnsPastLength;
    procedure TestMaterialWarnsOfQuarterTurn;
    procedure TestMaterialUseOnARoll;
    procedure TestMaterialUseOnASheet;
    procedure TestMaterialExportsPDF;
    procedure TestFabricLimitsTray;
    procedure TestFabricLimitsPlaced;
    procedure TestFabricLimitsPacking;
    procedure TestFabricLimitsDXF;
    procedure TestFabricIgnoresCase;
    procedure TestFabricClearedBringsPiecesBack;
    procedure TestFabricUnknownWarns;
    procedure TestFabricWithNothingBlocks;
    procedure TestProfilesRoundTrip;
    procedure TestProfileBadValuesKeepStandard;
    procedure TestStandardProfileAlwaysThere;
    procedure TestLayoutSavesProfileName;
    procedure TestPlainSVGHasNoProfileMarks;
    procedure TestMachineSVGColours;
    procedure TestMachineSVGCutsLast;
    procedure TestMachineSVGHolesAreCircles;
    procedure TestMachineSVGLineTypeOff;
    procedure TestUnknownProfileRefusesOnlyMachineExports;
    procedure TestProfileWarnsOfQuarterTurn;
    procedure TestDXFWritesMarkings;
    procedure TestMachineDXFFollowsPlacement;
    procedure TestMachineDXFCutsLast;
    procedure TestMachineDXFLayersSharedOnce;
    procedure TestMachineDXFRepeatsExactly;
    procedure TestMachineDXFFormatName;
    procedure TestFormatFromName;
    procedure TestFormatFromExtension;
    procedure TestExportWritesFile;
    procedure TestExportRefusesBlockedLayout;
    procedure TestPackNeverOverlaps;
    procedure TestPackRepeatsExactly;
    procedure TestPackReducesPages;
    procedure TestPackDoesNotAddPages;
    procedure TestPackPlacesTheTray;
    procedure TestPackKeepsFlips;
    procedure TestPackTurnsByQuarters;
    procedure TestPackRollWidth;
    procedure TestPackLeavesOutTooWide;
    procedure TestPackRefusesProjector;
    procedure TestPackClearsExcludedPages;
    procedure TestPackNothing;
  end;

implementation

uses
  Math, Sloper.Core.MachineProfiles, Sloper.Core.OutputProfiles, Sloper.Core.Settings, Sloper.Core.Draft, Sloper.Core.EvalTypes, Sloper.Core.PatternFile,
  Sloper.Core.PieceDetect, Sloper.Output.LayoutSVG,
  Sloper.Output.LayoutDXF, Sloper.Output.LayoutExport, Sloper.Output.Packing, Sloper.Output.Tiling, Sloper.Output.DraftSVG, StrUtils;

procedure TTestLayoutExports.SetUp;
begin
  FFolder := IncludeTrailingPathDelimiter(GetTempDir) + 'sloper-exports-' + IntToStr(Random(MaxInt));
  ForceDirectories(FFolder);
  FLayout := TLayout.Create;
  FLayout.FileName := ConcatPaths([FFolder, 'test.slayout']);
  FLayout.Name := 'test';
  FLayout.PrintDate := '2026-11-01';
  UseA4;
end;

procedure TTestLayoutExports.TearDown;
var
  Found: TSearchRec;
begin
  FreeAndNil(FLayout);
  if FindFirst(ConcatPaths([FFolder, '*']), faAnyFile, Found) = 0 then
  begin
    repeat
      if (Found.Name <> '.') and (Found.Name <> '..') then
        DeleteFile(ConcatPaths([FFolder, Found.Name]));
    until FindNext(Found) <> 0;
    FindClose(Found);
  end;
  RemoveDir(FFolder);
end;

procedure TTestLayoutExports.UseA4;
begin
  FLayout.Output.Kind := okTiled;
  FLayout.Output.Paper := 'A4';
  FLayout.Output.Tiles.PaperWidth := 210;
  FLayout.Output.Tiles.PaperHeight := 297;
  FLayout.Output.Tiles.Margin := 5;
  FLayout.Output.Tiles.Overlap := 10;
end;

procedure TTestLayoutExports.AddPattern(const AFile: string; const Widths, Heights: array of double; Cut: integer; Fold: boolean);
var
  Pattern: TPattern;
  Index: integer;
  Left, Width, Height: double;
  A, B, C, D, Reason: string;
  Path: TPiecePath;
  Piece: TPieceObject;
  Fixed: TFormatSettings;
begin
  Fixed := DefaultFormatSettings;
  Fixed.DecimalSeparator := '.';
  Pattern := TPattern.Create;
  try
    Left := 0;
    for Index := 0 to High(Widths) do
    begin
      Width := Widths[Index];
      Height := Heights[Index];
      A := Pattern.AddFreePoint('', FloatToStr(Left, Fixed), '0').Key;
      B := Pattern.AddFreePoint('', FloatToStr(Left + Width, Fixed), '0').Key;
      C := Pattern.AddFreePoint('', FloatToStr(Left + Width, Fixed), FloatToStr(Height, Fixed)).Key;
      D := Pattern.AddFreePoint('', FloatToStr(Left, Fixed), FloatToStr(Height, Fixed)).Key;
      Pattern.AddLine(A, B, erOutline);
      Pattern.AddLine(B, C, erOutline);
      Pattern.AddLine(C, D, erOutline);
      Pattern.AddLine(D, A, erOutline);
      Pattern.Evaluate;
      AssertTrue(Reason, DetectPiecePath(Pattern, Vec2(Left + Width / 2, Height / 2), Path, Reason));
      Piece := Pattern.AddPiece('', Path, '10');
      AssertNotNull(Pattern.LastError, Piece);
      Pattern.SetCut(Piece, Cut, Cut > 1);
      if Fold then
        AssertTrue(Pattern.LastError, Pattern.SetFoldEdge(Piece, Piece.Path[0].EdgeKey));
      Left := Left + Width + 50;
    end;
    AssertTrue(Reason, SavePatternToFile(Pattern, ConcatPaths([FFolder, AFile]), Reason));
  finally
    FreeAndNil(Pattern);
  end;
  FLayout.AddSource(AFile, '', '');
  FLayout.LoadSources;
end;

procedure TTestLayoutExports.LineFirstPiece;
var
  Pattern: TPattern;
  Index: integer;
begin
  Pattern := FLayout.Sources[0].Pattern;
  Pattern.AddFabric('Lining');
  for Index := 0 to Pattern.ObjectCount - 1 do
    if Pattern.Objects[Index] is TPieceObject then
    begin
      Pattern.SetPieceFabric(TPieceObject(Pattern.Objects[Index]), Pattern.FindFabricNamed('Lining'));
      Exit;
    end;
end;

procedure TTestLayoutExports.UseMaterial(Width: double; ALength: double);
begin
  FLayout.Output.Kind := okMaterial;
  FLayout.Output.MaterialWidth := Width;
  FLayout.Output.MaterialLength := ALength;
end;

procedure TTestLayoutExports.AddMarkedPattern(const AFile: string; Fold: boolean);
var
  Pattern: TPattern;
  A, B, C, D, Reason: string;
  Path: TPiecePath;
  Piece: TPieceObject;

  function Pt(const X, Y: string): string;
  begin
    Result := Pattern.AddFreePoint('', X, Y).Key;
  end;

begin
  Pattern := TPattern.Create;
  try
    A := Pt('0', '0');
    B := Pt('100', '0');
    C := Pt('100', '-100');
    D := Pt('0', '-100');
    Pattern.AddLine(A, B, erOutline);
    Pattern.AddLine(B, C, erOutline);
    Pattern.AddLine(C, D, erOutline);
    Pattern.AddLine(D, A, erOutline);
    Pattern.Evaluate;
    AssertTrue(Reason, DetectPiecePath(Pattern, Vec2(50, -50), Path, Reason));
    Piece := Pattern.AddPiece('', Path, '10');
    AssertNotNull(Pattern.LastError, Piece);
    if Fold then
      AssertTrue(Pattern.LastError, Pattern.SetFoldEdge(Piece, Piece.Path[0].EdgeKey));
    AssertTrue(Pattern.LastError, Pattern.SetMarker(Pt('30', '-40'), pmHole, '4'));
    Pattern.AddLine(Pt('20', '-60'), Pt('80', '-60'), erPlacement);
    Pattern.AddLine(Pt('50', '0'), Pt('50', '-100'), erFold);
    Pattern.Evaluate;
    AssertTrue(Pattern.LastError, Pattern.AddStitchMarking(Piece, Pattern.AddLine(Pt('20', '-80'), Pt('60', '-80')).Key, '10', '1'));
    Pattern.Evaluate;
    AssertTrue(Reason, SavePatternToFile(Pattern, ConcatPaths([FFolder, AFile]), Reason));
  finally
    FreeAndNil(Pattern);
  end;
  FLayout.AddSource(AFile, '', '');
  FLayout.LoadSources;
end;

function TTestLayoutExports.Count(const Needle, Text: string): integer;
var
  At: integer;
begin
  Result := 0;
  At := Pos(Needle, Text);
  while At > 0 do
  begin
    Inc(Result);
    At := PosEx(Needle, Text, At + Length(Needle));
  end;
end;

function TTestLayoutExports.PagesUsed: integer;
var
  Page: TTilePage;
  Rows, Columns: integer;
begin
  Result := 0;
  for Page in FLayout.Pages(FLayout.PlacedPieces, Rows, Columns) do
    if not Page.Blank then
      Inc(Result);
end;

procedure TTestLayoutExports.AssertNoOverlap;
var
  Shapes: TPlacedPieceArray;
  Index, Other: integer;
begin
  Shapes := FLayout.PlacedPieces;
  for Index := 0 to High(Shapes) do
    for Other := 0 to Index - 1 do
      AssertFalse(Format('pieces %d and %d touch', [Other, Index]), (Shapes[Index].Bounds.MinX < Shapes[Other].Bounds.MaxX + PackGap - 0.001) and
        (Shapes[Index].Bounds.MaxX + PackGap - 0.001 > Shapes[Other].Bounds.MinX) and
        (Shapes[Index].Bounds.MinY < Shapes[Other].Bounds.MaxY + PackGap - 0.001) and
        (Shapes[Index].Bounds.MaxY + PackGap - 0.001 > Shapes[Other].Bounds.MinY));
end;

// 100 mm square + 2 * 10 mm allowance + 2 * 5 mm margin
procedure TTestLayoutExports.TestSVGIsTrueScale;
var
  Text: string;
begin
  AddPattern('a.sloper', [100], [100]);
  FLayout.PlaceNewPieces;
  Text := LayoutToSVG(FLayout);
  AssertTrue(Text, Pos('width="130mm" height="130mm" viewBox="-5 -5 130 130"', Text) > 0);
end;

procedure TTestLayoutExports.TestSVGGroupsEachCopy;
var
  Text: string;
begin
  AddPattern('a.sloper', [100], [100], 2);
  FLayout.PlaceNewPieces;
  Text := LayoutToSVG(FLayout);
  AssertEquals('copies', 2, Count('data-name=', Text));
  AssertEquals('cut', 2, Count('class="cut"', Text));
  AssertEquals('seam', 2, Count('class="seam"', Text));
  AssertEquals('marks', 2, Count('class="marks"', Text));
  AssertEquals('label', 2, Count('class="label"', Text));
end;

procedure TTestLayoutExports.TestSVGFollowsPlacement;
var
  Text: string;
begin
  AddPattern('a.sloper', [100], [100]);
  FLayout.PlaceNewPieces;
  FLayout.Placements[0].X := 40;
  FLayout.Placements[0].Y := 60;
  Text := LayoutToSVG(FLayout);
  AssertTrue(Text, Pos('width="170mm" height="190mm"', Text) > 0);
  AssertTrue('seam line 10 mm inside the cut line', Pos('50 70', Text) > 0);
end;

procedure TTestLayoutExports.TestSVGEscapesNames;
begin
  AssertEquals('&lt;a&amp;b&gt;', EscapeXML('<a&b>'));
end;

procedure TTestLayoutExports.TestSVGRepeatsExactly;
begin
  AddPattern('a.sloper', [100, 80], [100, 60]);
  FLayout.PlaceNewPieces;
  AssertEquals(LayoutToSVG(FLayout), LayoutToSVG(FLayout));
end;

procedure TTestLayoutExports.TestDXFOneBlockPerPiece;
var
  Text: string;
begin
  AddPattern('a.sloper', [100, 80], [100, 60], 2);
  FLayout.PlaceNewPieces;
  AssertEquals('copies placed', 4, Length(FLayout.Placements));
  Text := LayoutToDXF(FLayout);
  AssertEquals('blocks', 2, Count(#13#10'BLOCK'#13#10, Text));
  AssertEquals('inserts', 2, Count(#13#10'INSERT'#13#10, Text));
end;

procedure TTestLayoutExports.TestDXFLayers;
var
  Text: string;
begin
  AddPattern('a.sloper', [100], [100]);
  FLayout.PlaceNewPieces;
  Text := LayoutToDXF(FLayout);
  AssertEquals('cut and seam', 2, Count(#13#10'POLYLINE'#13#10, Text));
  AssertTrue('cut', Pos(#13#10'POLYLINE'#13#10'  8'#13#10'1'#13#10, Text) > 0);
  AssertTrue('seam', Pos(#13#10'POLYLINE'#13#10'  8'#13#10'14'#13#10, Text) > 0);
  AssertTrue('grain', Pos(#13#10'LINE'#13#10'  8'#13#10'7'#13#10, Text) > 0);
end;

// The piece's own coordinates, whatever the placement says
procedure TTestLayoutExports.TestDXFUsesPieceCoordinates;
var
  Before: string;
begin
  AddPattern('a.sloper', [100], [100]);
  FLayout.PlaceNewPieces;
  Before := LayoutToDXF(FLayout);
  FLayout.Placements[0].X := 300;
  FLayout.Placements[0].Y := 200;
  FLayout.Placements[0].Rotation := 90;
  FLayout.Placements[0].Flipped := True;
  AssertEquals(Before, LayoutToDXF(FLayout));
end;

procedure TTestLayoutExports.TestDXFIsR12;
var
  Text: string;
begin
  AddPattern('a.sloper', [100], [100]);
  FLayout.PlaceNewPieces;
  Text := LayoutToDXF(FLayout);
  AssertTrue('version', Pos('$ACADVER'#13#10'  1'#13#10'AC1009', Text) > 0);
  AssertEquals('ends', 'EOF', Trim(Copy(Text, Length(Text) - 4, 5)));
  AssertTrue('units', Pos(rsDXFUnits, Text) > 0);
  AssertTrue('date', Pos(Format(rsDXFCreationDate, ['2026-11-01']), Text) > 0);
end;

procedure TTestLayoutExports.TestDXFNamesFabric;
var
  Pattern: TPattern;
begin
  UseA4;
  AddPattern('fabric.sloper', [100], [100], 1, False);
  FLayout.PlaceNewPieces;
  AssertEquals('none while Main is implicit', 0, Pos('Material', LayoutToDXF(FLayout)));
  Pattern := FLayout.Sources[0].Pattern;
  AssertTrue(Pattern.RenameFabric(Pattern.Fabrics[0], 'Denim'));
  AssertTrue(Pos(Format(rsDXFMaterial, ['Denim']), LayoutToDXF(FLayout)) > 0);
end;

procedure TTestLayoutExports.TestDXFQuantityIsCutCount;
var
  Text: string;
begin
  AddPattern('a.sloper', [100], [100], 3);
  FLayout.PlaceNewPieces;
  System.Delete(FLayout.Placements, 2, 1);
  Text := LayoutToDXF(FLayout);
  AssertTrue(Text, Pos(Format(rsDXFQuantity, [3]), Text) > 0);
end;

procedure TTestLayoutExports.TestDXFFoldIsMirrorLine;
var
  Text: string;
begin
  AddPattern('a.sloper', [100], [100], 1, True);
  FLayout.PlaceNewPieces;
  Text := LayoutToDXF(FLayout);
  AssertTrue(Text, Pos(#13#10'LINE'#13#10'  8'#13#10'6'#13#10, Text) > 0);
end;

procedure TTestLayoutExports.TestDXFNotch;
var
  Pattern: TPattern;
  Piece: TPieceObject;
  Reason, Text, Path: string;
begin
  AddPattern('a.sloper', [100], [100]);
  Path := ConcatPaths([FFolder, 'a.sloper']);
  Pattern := FLayout.Sources[0].Pattern;
  Piece := TPieceObject(Pattern.FindObject('Piece'));
  AssertTrue(Pattern.LastError, Pattern.AddEdgeNotch(Piece, Piece.Path[0].EdgeKey, '30'));
  Pattern.Evaluate;
  AssertTrue(Reason, SavePatternToFile(Pattern, Path, Reason));
  FLayout.LoadSources;
  FLayout.PlaceNewPieces;
  Text := LayoutToDXF(FLayout);
  AssertTrue(Text, Pos(#13#10'POINT'#13#10'  8'#13#10'4'#13#10, Text) > 0);
  AssertTrue('angle', Pos(#13#10' 50'#13#10, Copy(Text, Pos(#13#10'POINT'#13#10, Text), MaxInt)) > 0);
end;

procedure TTestLayoutExports.TestDXFOnlyPlacedPieces;
var
  Text: string;
begin
  AddPattern('a.sloper', [100, 80], [100, 60]);
  FLayout.PlaceNewPieces;
  FLayout.RemovePlacement(1);
  Text := LayoutToDXF(FLayout);
  AssertEquals('blocks', 1, Count(#13#10'BLOCK'#13#10, Text));
end;

// Two sources both have a piece called Piece
procedure TTestLayoutExports.TestDXFBlockNamesAreUnique;
var
  Text: string;
begin
  AddPattern('a.sloper', [100], [100]);
  AddPattern('b.sloper', [80], [60]);
  FLayout.PlaceNewPieces;
  Text := LayoutToDXF(FLayout);
  AssertEquals('blocks', 2, Count(#13#10'BLOCK'#13#10, Text));
  AssertTrue('first', Pos(#13#10'Piece'#13#10, Text) > 0);
  AssertTrue('second', Pos(#13#10'Piece2'#13#10, Text) > 0);
end;

procedure TTestLayoutExports.TestDXFRepeatsExactly;
begin
  AddPattern('a.sloper', [100, 80], [100, 60]);
  FLayout.PlaceNewPieces;
  AssertEquals(LayoutToDXF(FLayout), LayoutToDXF(FLayout));
end;

procedure TTestLayoutExports.TestPlacedMarksKeepTheirType;
var
  Shape: TPlacedPiece;
begin
  AddMarkedPattern('a.sloper');
  FLayout.PlaceNewPieces;
  Shape := FLayout.PlacedPieces[0];
  AssertEquals('only the fold line scores', 1, Length(Shape.ScoreLines));
  AssertEquals('at x 50, across the cutting line''s 10 mm', 60, Shape.ScoreLines[0].P1.X, 1e-6);
  AssertEquals('the hole and five stitch holes', 6, Length(Shape.Holes));
  AssertEquals('stitch hole size', 1, Shape.Holes[1].Diameter, 1e-9);
end;

// (30, 40) in a piece 120 mm tall, with its top at y 110
procedure TTestLayoutExports.TestPlacedHoleIsWhole;
var
  Shape: TPlacedPiece;
begin
  AddMarkedPattern('a.sloper');
  FLayout.PlaceNewPieces;
  Shape := FLayout.PlacedPieces[0];
  AssertPointsNear('moved with the piece', Vec2(40, 70), Shape.Holes[0].Centre);
  AssertEquals('diameter', 4, Shape.Holes[0].Diameter, 1e-9);
end;

procedure TTestLayoutExports.TestPlacedHoleFollowsFlip;
begin
  AddMarkedPattern('a.sloper');
  FLayout.PlaceNewPieces;
  FLayout.Placements[0].Flipped := True;
  AssertPointsNear('mirrored across the piece', Vec2(80, 70), FLayout.PlacedPieces[0].Holes[0].Centre);
end;

// Beside the hole at (30, 40), so placed at (80, 70); drawn, never cut
procedure TTestLayoutExports.TestPlacedButtonIsAMark;
var
  Pattern: TPattern;
  Shape: TPlacedPiece;
  Stroke: TLine2;
  Near: integer;
begin
  AddMarkedPattern('a.sloper');
  Pattern := FLayout.Sources[0].Pattern;
  AssertTrue(Pattern.LastError, Pattern.SetMarker(Pattern.AddFreePoint('', '70', '-40').Key, pmButton, '10'));
  Pattern.Evaluate;
  FLayout.PlaceNewPieces;
  Shape := FLayout.PlacedPieces[0];
  AssertEquals('still the hole and five stitch holes', 6, Length(Shape.Holes));
  Near := 0;
  for Stroke in Shape.MarkLines do
    if Distance(Stroke.P1, Vec2(80, 70)) < 5.01 then
      Inc(Near);
  AssertEquals('a circle and a cross, as marks', 18, Near);
end;

// Skive and edge finish lines join the piece and print as marks, in their
// own groups
procedure TTestLayoutExports.TestLeatherRolesPrint;
var
  Pattern: TPattern;
  Text: string;
begin
  AddMarkedPattern('a.sloper');
  Pattern := FLayout.Sources[0].Pattern;
  Pattern.AddLine(Pattern.AddFreePoint('', '10', '-10').Key, Pattern.AddFreePoint('', '90', '-10').Key, erSkive);
  Pattern.AddLine(Pattern.AddFreePoint('', '10', '-90').Key, Pattern.AddFreePoint('', '90', '-90').Key, erEdgeFinish);
  Pattern.Evaluate;
  FLayout.PlaceNewPieces;
  Text := LayoutToSVG(FLayout);
  AssertTrue('skive', Pos('<g class="line-skive">', Text) > 0);
  AssertTrue('edge finish', Pos('<g class="line-edge-finish">', Text) > 0);
  AssertEquals('only the fold line scores', 1, Length(FLayout.PlacedPieces[0].ScoreLines));
end;

procedure TTestLayoutExports.TestOutputProfileSaved;
var
  Loaded: TLayout;
  Reason: string;
begin
  FLayout.Output.OutputProfile := 'Leather';
  AssertTrue('written', Pos('"outputProfile"', FLayout.SaveToText) > 0);
  Loaded := TLayout.Create;
  try
    AssertTrue(Reason, Loaded.LoadFromText(FLayout.SaveToText, Reason));
    AssertEquals('Leather', Loaded.Output.OutputProfile);
  finally
    FreeAndNil(Loaded);
  end;
  FLayout.Output.OutputProfile := '';
  AssertEquals('left out when none', 0, Pos('outputProfile', FLayout.SaveToText));
end;

procedure TTestLayoutExports.TestUnknownOutputProfileBlocksExport;
var
  Reason: string;
  Problem: TLayoutProblem;
  Found: boolean;
begin
  AddMarkedPattern('a.sloper');
  FLayout.PlaceNewPieces;
  FLayout.Output.OutputProfile := 'Not there';
  Found := False;
  for Problem in FLayout.Problems do
    Found := Found or (Problem.Blocking and (Problem.Text = Format(rsLayoutUnknownOutputProfile, ['Not there'])));
  AssertTrue('blocking', Found);
  AssertFalse(ExportLayout(FLayout, efSVG, ConcatPaths([FFolder, 'x.svg']), Reason));
end;

// The marked piece is 100 by 100 inside a 10 mm allowance
procedure TTestLayoutExports.TestLeatherCutsOnSeamLine;
var
  Shape: TPlacedPiece;
  Line: TPlacedLine;
begin
  AddMarkedPattern('a.sloper');
  FLayout.Output.OutputProfile := 'Leather';
  FLayout.PlaceNewPieces;
  Shape := FLayout.PlacedPieces[0];
  AssertEquals('cut on the seam line', 100 * 100, Abs(SignedArea(Shape.CutLine)), 1e-3);
  AssertEquals('no seam line drawn', 0, Length(Shape.SeamLine));
  AssertEquals('placed from its own top left', 0, Shape.Bounds.MinX, 1e-6);
  for Line in Shape.Lines do
    AssertFalse('no placement or fold lines', Line.Role in [erPlacement, erFold]);
  AssertEquals('the hole and five stitch holes', 6, Length(Shape.Holes));
  AssertTrue(Shape.ShowLabel);
end;

procedure TTestLayoutExports.TestCutterProfileKeepsCutAndHoles;
var
  Shape: TPlacedPiece;
begin
  AddMarkedPattern('a.sloper');
  FLayout.Output.OutputProfile := 'Plotter or laser cutter';
  FLayout.PlaceNewPieces;
  Shape := FLayout.PlacedPieces[0];
  AssertEquals('no marking lines', 0, Length(Shape.Lines));
  AssertEquals('no fold line to score', 0, Length(Shape.ScoreLines));
  AssertEquals(6, Length(Shape.Holes));
  AssertEquals('no seam line', 0, Length(Shape.SeamLine));
  AssertFalse('no label', Shape.ShowLabel);
  AssertEquals('only hole circles as marks', 6 * 16, Length(Shape.Marks));
end;

procedure TTestLayoutExports.TestInstructionsProfile;
var
  Shape: TPlacedPiece;
begin
  AddMarkedPattern('a.sloper');
  FLayout.Output.OutputProfile := 'Instructions sheet';
  FLayout.PlaceNewPieces;
  Shape := FLayout.PlacedPieces[0];
  AssertTrue('seam line', Length(Shape.SeamLine) > 0);
  AssertEquals('placement and fold lines', 2, Length(Shape.Lines));
  AssertEquals('no holes', 0, Length(Shape.Holes));
end;

procedure TTestLayoutExports.TestProfileStylesOnPaper;
var
  Profile: TOutputProfile;
  Text: string;
begin
  AddMarkedPattern('a.sloper');
  Profile := FullOutputProfile;
  Profile.Name := 'Blue folds';
  Profile.Styles[erFold].Custom := True;
  Profile.Styles[erFold].Color := '#0000FF';
  Profile.Styles[erFold].Dashes[0] := 3;
  Profile.Styles[erFold].Dashes[1] := 2;
  Profile.Styles[erFold].Width := 0.5;
  FLayout.OutputProfiles := [Profile];
  FLayout.Output.OutputProfile := 'Blue folds';
  FLayout.PlaceNewPieces;
  Text := LayoutToSVG(FLayout);
  AssertTrue(Text, Pos('<g class="line-fold"><path d="', Text) > 0);
  AssertTrue('its own look', Pos('stroke="#0000ff" stroke-width="0.5" stroke-dasharray="3 2"', Text) > 0);
  AssertTrue('others keep theirs', Pos('<g class="line-placement"><path d="', Text) > 0);
end;

// The profile leaves the fold line out, so the machine has nothing to score
procedure TTestLayoutExports.TestMachineProfileAfterOutputProfile;
var
  Text: string;
begin
  AddMarkedPattern('a.sloper');
  FLayout.Output.OutputProfile := 'Plotter or laser cutter';
  FLayout.Output.Profile := StandardProfileName;
  FLayout.PlaceNewPieces;
  Text := LayoutToSVG(FLayout);
  AssertEquals('no score lines', 0, Pos('class="score"', Text));
  AssertTrue('holes cut', Pos('<circle', Text) > 0);
end;

procedure TTestLayoutExports.TestAAMAFollowsOutputProfile;
var
  Text: string;
begin
  AddMarkedPattern('a.sloper');
  FLayout.Output.OutputProfile := 'Leather';
  FLayout.PlaceNewPieces;
  Text := LayoutToDXF(FLayout);
  AssertEquals('no seam line', 0, Count('POLYLINE'#13#10'  8'#13#10'14'#13#10, Text));
  AssertEquals('no placement or fold lines', 0, Count('LINE'#13#10'  8'#13#10'8'#13#10, Text));
  AssertEquals('every hole, as a point', 6, Count('POINT'#13#10'  8'#13#10'13'#13#10, Text));
end;

// Paper keeps drawing every mark, holes as strokes, in one list
procedure TTestLayoutExports.TestPaperMarksKeepEverything;
const
  StrokesPerHole = 16;
var
  Shape: TPlacedPiece;
  Line: TPlacedLine;
  LineStrokes: integer;
begin
  AddMarkedPattern('a.sloper');
  FLayout.PlaceNewPieces;
  Shape := FLayout.PlacedPieces[0];
  // Marking lines go whole, to be drawn in their role's style
  LineStrokes := 0;
  for Line in Shape.Lines do
    Inc(LineStrokes, Length(Line.Points) - 1);
  AssertEquals('both lines', 2, Length(Shape.Lines));
  AssertEquals(Length(Shape.MarkLines) + Length(Shape.ScoreLines) + Length(Shape.SlitLines) + StrokesPerHole * Length(Shape.Holes),
    Length(Shape.Marks) + LineStrokes);
end;

procedure TTestLayoutExports.TestFoldStaysHalfOnPaper;
var
  Shape: TPlacedPiece;
begin
  AddPattern('a.sloper', [100], [100], 1, True);
  FLayout.PlaceNewPieces;
  Shape := FLayout.PlacedPieces[0];
  AssertEquals('no allowance on the fold, at x 0', 110, Shape.Bounds.MaxX - Shape.Bounds.MinX, 1e-6);
end;

procedure TTestLayoutExports.TestFoldOpensWithProfile;
var
  Shape: TPlacedPiece;
begin
  AddPattern('a.sloper', [100], [100], 1, True);
  FLayout.Output.Profile := StandardProfileName;
  FLayout.PlaceNewPieces;
  Shape := FLayout.PlacedPieces[0];
  AssertEquals('both halves', 220, Shape.Bounds.MaxX - Shape.Bounds.MinX, 1e-3);
  AssertEquals('height', 120, Shape.Bounds.MaxY - Shape.Bounds.MinY, 1e-3);
  AssertEquals('from its placement', 0, Shape.Bounds.MinX, 1e-3);
  AssertEquals('one outline, area', 120 * 220, Abs(SignedArea(Shape.CutLine)), 1);
end;

procedure TTestLayoutExports.TestFoldOpensOnMaterial;
begin
  AddPattern('a.sloper', [100], [100], 1, True);
  UseMaterial(1500);
  FLayout.PlaceNewPieces;
  AssertEquals(220, FLayout.PlacedPieces[0].Bounds.MaxX, 1e-3);
end;

procedure TTestLayoutExports.TestOpenedSeamLineIsWhole;
begin
  AddPattern('a.sloper', [100], [100], 1, True);
  UseMaterial(1500);
  FLayout.PlaceNewPieces;
  AssertEquals(100 * 200, Abs(SignedArea(FLayout.PlacedPieces[0].SeamLine)), 1);
end;

procedure TTestLayoutExports.TestOpenedHolesOnBothHalves;
var
  Shape: TPlacedPiece;
begin
  AddMarkedPattern('a.sloper', True);
  UseMaterial(1500);
  FLayout.PlaceNewPieces;
  Shape := FLayout.PlacedPieces[0];
  AssertEquals(12, Length(Shape.Holes));
  AssertPointsNear('the hole', Vec2(140, 70), Shape.Holes[0].Centre);
  AssertPointsNear('its twin', Vec2(80, 70), Shape.Holes[1].Centre);
end;

// So opening a piece out never has to write such a hole once
procedure TTestLayoutExports.TestHoleOnTheFoldRefused;
var
  Pattern: TPattern;
  Piece: TPieceObject;
  Index: integer;
  Hole: string;
begin
  AddMarkedPattern('a.sloper', True);
  Pattern := FLayout.Sources[0].Pattern;
  Piece := nil;
  for Index := 0 to Pattern.ObjectCount - 1 do
    if Pattern.Objects[Index] is TPieceObject then
      Piece := TPieceObject(Pattern.Objects[Index]);
  Hole := Pattern.AddFreePoint('', '0', '-70').Key;
  AssertTrue(Pattern.LastError, Pattern.SetMarker(Hole, pmHole, '4'));
  if Piece.PointMarkingOf(Hole) < 0 then
    AssertTrue(Pattern.LastError, Pattern.AddPointMarking(Piece, Hole));
  Pattern.Evaluate;
  AssertTrue('invalid', Piece.State = esInvalid);
  AssertTrue(Piece.Message, Pos('fold', Piece.Message) > 0);
end;

// Five of them on the fold, and six on each half from the pattern
procedure TTestLayoutExports.TestStitchHolesOnTheFoldOnce;
var
  Pattern: TPattern;
  Piece: TPieceObject;
  Index: integer;
begin
  AddMarkedPattern('a.sloper', True);
  Pattern := FLayout.Sources[0].Pattern;
  Piece := nil;
  for Index := 0 to Pattern.ObjectCount - 1 do
    if Pattern.Objects[Index] is TPieceObject then
      Piece := TPieceObject(Pattern.Objects[Index]);
  AssertTrue(Pattern.LastError, Pattern.AddStitchMarking(Piece, Pattern.AddLine(Pattern.AddFreePoint('', '0', '-20').Key,
    Pattern.AddFreePoint('', '0', '-60').Key).Key, '10', '1'));
  Pattern.Evaluate;
  AssertTrue(Piece.Message, Piece.State = esValid);
  UseMaterial(1500);
  FLayout.PlaceNewPieces;
  AssertEquals(17, Length(FLayout.PlacedPieces[0].Holes));
end;

procedure TTestLayoutExports.TestOpenedCaptionDropsFold;
begin
  AddPattern('a.sloper', [100], [100], 1, True);
  FLayout.PlaceNewPieces;
  AssertTrue(FLayout.PlacedPieces[0].Caption, Pos('fold', LowerCase(FLayout.PlacedPieces[0].Caption)) > 0);
  UseMaterial(1500);
  AssertEquals(FLayout.PlacedPieces[0].Caption, 0, Pos('fold', LowerCase(FLayout.PlacedPieces[0].Caption)));
end;

procedure TTestLayoutExports.TestOpenedFoldIsAMark;
var
  Stroke: TLine2;
  Found: integer;
begin
  AddPattern('a.sloper', [100], [100], 1, True);
  UseMaterial(1500);
  FLayout.PlaceNewPieces;
  Found := 0;
  for Stroke in FLayout.PlacedPieces[0].MarkLines do
    if (Abs(Stroke.P1.X - 110) < 1e-3) and (Abs(Stroke.P2.X - 110) < 1e-3) then
      Inc(Found);
  AssertEquals('once, across the middle', 1, Found);
end;

procedure TTestLayoutExports.TestAAMAKeepsTheHalf;
var
  Plain, Opened: string;
begin
  AddPattern('a.sloper', [100], [100], 1, True);
  FLayout.PlaceNewPieces;
  Plain := LayoutToDXF(FLayout);
  UseMaterial(1500);
  Opened := LayoutToDXF(FLayout);
  AssertEquals(Plain, Opened);
end;

procedure TTestLayoutExports.TestMaterialRoundTrip;
var
  Text, Reason: string;
begin
  UseMaterial(1400, 3000);
  FLayout.Output.AllowTurns := True;
  FLayout.Output.Fabric := 'Lining';
  Text := FLayout.SaveToText;
  AssertTrue(Reason, FLayout.LoadFromText(Text, Reason));
  AssertTrue(FLayout.Output.Kind = okMaterial);
  AssertEquals(1400, FLayout.Output.MaterialWidth, 1e-9);
  AssertEquals(3000, FLayout.Output.MaterialLength, 1e-9);
  AssertTrue(FLayout.Output.AllowTurns);
  AssertEquals('Lining', FLayout.Output.Fabric);
end;

procedure TTestLayoutExports.TestMaterialDefaultsNotSaved;
var
  Text: string;
begin
  Text := FLayout.SaveToText;
  AssertEquals(0, Pos('material', Text));
  AssertEquals(0, Pos('allowTurns', Text));
  AssertEquals(0, Pos('"fabric"', Text));
end;

procedure TTestLayoutExports.TestBadMaterialRefused;
var
  Text, Reason: string;
begin
  UseMaterial(1400);
  Text := StringReplace(FLayout.SaveToText, '1400', '-1', []);
  AssertFalse(FLayout.LoadFromText(Text, Reason));
  AssertEquals(rsLayoutBadMaterial, Reason);
end;

procedure TTestLayoutExports.TestMaterialPacksToWidth;
var
  Shape: TPlacedPiece;
begin
  AddPattern('a.sloper', [100, 100, 100], [100, 100, 100]);
  UseMaterial(280);
  AssertTrue(PackLayout(FLayout).Done);
  for Shape in FLayout.PlacedPieces do
    AssertTrue('inside the width', Shape.Bounds.MaxX <= 280 + 0.001);
  AssertNoOverlap;
end;

// Turning would fit it; a woven fabric would then be cut across the grain
procedure TTestLayoutExports.TestMaterialDoesNotTurn;
var
  Outcome: TPackResult;
begin
  AddPattern('a.sloper', [300], [100]);
  UseMaterial(200);
  Outcome := PackLayout(FLayout);
  AssertEquals(1, Outcome.LeftOut);
  AssertEquals(0, FLayout.Placements[0].Rotation);
end;

procedure TTestLayoutExports.TestMaterialTurnsWhenAllowed;
var
  Outcome: TPackResult;
begin
  AddPattern('a.sloper', [300], [100]);
  UseMaterial(200);
  FLayout.Output.AllowTurns := True;
  Outcome := PackLayout(FLayout);
  AssertEquals(0, Outcome.LeftOut);
  AssertEquals(90, FLayout.Placements[0].Rotation);
end;

procedure TTestLayoutExports.TestMaterialLengthLimitsPacking;
var
  Outcome: TPackResult;
begin
  AddPattern('a.sloper', [100, 100], [100, 100]);
  UseMaterial(130, 130);
  Outcome := PackLayout(FLayout);
  AssertEquals('one fits a board this size', 1, Outcome.LeftOut);
end;

procedure TTestLayoutExports.TestMaterialWarnsPastWidth;
begin
  AddPattern('a.sloper', [300], [100]);
  UseMaterial(200);
  FLayout.PlaceNewPieces;
  AssertEquals(1, Length(FLayout.Problems));
  AssertFalse(FLayout.Problems[0].Blocking);
end;

procedure TTestLayoutExports.TestMaterialWarnsPastLength;
begin
  AddPattern('a.sloper', [100], [300]);
  UseMaterial(200, 200);
  FLayout.PlaceNewPieces;
  AssertEquals(1, Length(FLayout.Problems));
end;

procedure TTestLayoutExports.TestMaterialWarnsOfQuarterTurn;
begin
  AddPattern('a.sloper', [100], [100]);
  UseMaterial(1500);
  FLayout.PlaceNewPieces;
  FLayout.Placements[0].Rotation := 90;
  AssertEquals(1, Length(FLayout.Problems));
end;

procedure TTestLayoutExports.TestMaterialUseOnARoll;
begin
  AddPattern('a.sloper', [100], [100]);
  UseMaterial(1500);
  FLayout.PlaceNewPieces;
  AssertTrue(FLayout.MaterialUse, Pos('120 mm', FLayout.MaterialUse) > 0);
  UseA4;
  AssertEquals('paper has none', '', FLayout.MaterialUse);
end;

procedure TTestLayoutExports.TestMaterialUseOnASheet;
begin
  AddPattern('a.sloper', [100], [100]);
  UseMaterial(240, 240);
  FLayout.PlaceNewPieces;
  AssertTrue(FLayout.MaterialUse, Pos('25%', FLayout.MaterialUse) > 0);
end;

procedure TTestLayoutExports.TestMaterialExportsPDF;
var
  Reason: string;
begin
  AddPattern('a.sloper', [100], [100], 1, True);
  UseMaterial(1500);
  FLayout.PlaceNewPieces;
  AssertTrue(Reason, ExportLayout(FLayout, efPDF, ConcatPaths([FFolder, 'a.pdf']), Reason));
  AssertTrue(FileExists(ConcatPaths([FFolder, 'a.pdf'])));
end;

procedure TTestLayoutExports.TestFabricLimitsTray;
begin
  AddPattern('a.sloper', [100, 100], [100, 100]);
  LineFirstPiece;
  FLayout.Output.Fabric := 'Lining';
  AssertEquals(1, Length(FLayout.Unplaced));
end;

procedure TTestLayoutExports.TestFabricLimitsPlaced;
begin
  AddPattern('a.sloper', [100, 100], [100, 100]);
  LineFirstPiece;
  FLayout.PlaceNewPieces;
  FLayout.Output.Fabric := 'Lining';
  AssertEquals(1, Length(FLayout.PlacedPieces));
  AssertEquals('the other stays in the file', 2, Length(FLayout.Placements));
end;

procedure TTestLayoutExports.TestFabricLimitsPacking;
begin
  AddPattern('a.sloper', [100, 100], [100, 100]);
  LineFirstPiece;
  UseMaterial(200);
  FLayout.Output.Fabric := 'Lining';
  AssertTrue(PackLayout(FLayout).Done or (Length(FLayout.Placements) = 1));
  AssertEquals('only the one placed', 1, Length(FLayout.Placements));
end;

procedure TTestLayoutExports.TestFabricLimitsDXF;
var
  Text: string;
begin
  AddPattern('a.sloper', [100, 100], [100, 100]);
  LineFirstPiece;
  FLayout.PlaceNewPieces;
  FLayout.Output.Fabric := 'Lining';
  Text := LayoutToDXF(FLayout);
  AssertEquals(1, Count('INSERT', Text));
end;

procedure TTestLayoutExports.TestFabricIgnoresCase;
begin
  AddPattern('a.sloper', [100, 100], [100, 100]);
  LineFirstPiece;
  FLayout.PlaceNewPieces;
  FLayout.Output.Fabric := 'LINING';
  AssertEquals(1, Length(FLayout.PlacedPieces));
end;

procedure TTestLayoutExports.TestFabricClearedBringsPiecesBack;
begin
  AddPattern('a.sloper', [100, 100], [100, 100]);
  LineFirstPiece;
  FLayout.PlaceNewPieces;
  FLayout.Output.Fabric := 'Lining';
  FLayout.Output.Fabric := '';
  AssertEquals(2, Length(FLayout.PlacedPieces));
end;

procedure TTestLayoutExports.TestFabricUnknownWarns;
var
  Problem: TLayoutProblem;
  Found: boolean;
begin
  AddPattern('a.sloper', [100], [100]);
  FLayout.PlaceNewPieces;
  FLayout.Output.Fabric := 'Denim';
  Found := False;
  for Problem in FLayout.Problems do
    Found := Found or (Pos('Denim', Problem.Text) > 0);
  AssertTrue(Found);
end;

procedure TTestLayoutExports.TestFabricWithNothingBlocks;
begin
  AddPattern('a.sloper', [100], [100]);
  FLayout.PlaceNewPieces;
  FLayout.Output.Fabric := 'Denim';
  AssertTrue('a blank file is never written', FLayout.Refusal <> '');
end;

procedure TTestLayoutExports.TestProfilesRoundTrip;
var
  Settings: TAppSettings;
  Profile: TMachineProfile;
  Text, Reason: string;
begin
  Settings := TAppSettings.Create;
  try
    AssertEquals('none, no key', 0, Pos('machineProfiles', Settings.SaveToText));
    Profile := StandardProfile;
    Profile.Name := 'Epilog';
    Profile.Lines[ltCut].Width := 0.01;
    Profile.Lines[ltEngrave].Enabled := False;
    Profile.Lines[ltHole].Layer := 'Pierce';
    Insert(Profile, Settings.MachineProfiles, 0);
    Text := Settings.SaveToText;
    AssertTrue(Reason, Settings.LoadFromText(Text, Reason));
    AssertEquals(1, Length(Settings.MachineProfiles));
    Profile := Settings.MachineProfiles[0];
    AssertEquals('Epilog', Profile.Name);
    AssertEquals(0.01, Profile.Lines[ltCut].Width, 1e-9);
    AssertFalse(Profile.Lines[ltEngrave].Enabled);
    AssertEquals('Pierce', Profile.Lines[ltHole].Layer);
    AssertEquals('same text', Text, Settings.SaveToText);
  finally
    FreeAndNil(Settings);
  end;
end;

procedure TTestLayoutExports.TestProfileBadValuesKeepStandard;
var
  Settings: TAppSettings;
  Reason: string;
begin
  Settings := TAppSettings.Create;
  try
    AssertTrue(Reason, Settings.LoadFromText('{"format":"opensloper-settings","version":1,"machineProfiles":[' +
      '{"name":"X","lines":{"cut":{"color":"red\"/>","width":-1,"layer":" "}}},{"lines":{}}]}', Reason));
    AssertEquals('no name, skipped', 1, Length(Settings.MachineProfiles));
    AssertEquals(StandardProfile.Lines[ltCut].Color, Settings.MachineProfiles[0].Lines[ltCut].Color);
    AssertEquals(StandardProfile.Lines[ltCut].Width, Settings.MachineProfiles[0].Lines[ltCut].Width, 1e-9);
    AssertEquals(StandardProfile.Lines[ltCut].Layer, Settings.MachineProfiles[0].Lines[ltCut].Layer);
  finally
    FreeAndNil(Settings);
  end;
end;

procedure TTestLayoutExports.TestStandardProfileAlwaysThere;
var
  Found: TMachineProfile;
begin
  AssertTrue('ignoring case', FindMachineProfile(nil, 'standard', Found));
  AssertEquals('#ff0000', Found.Lines[ltCut].Color);
  AssertFalse(FindMachineProfile(nil, 'Epilog', Found));
end;

procedure TTestLayoutExports.TestLayoutSavesProfileName;
var
  Text, Reason: string;
begin
  AssertEquals('none, no key', 0, Pos('"profile"', FLayout.SaveToText));
  FLayout.Output.Profile := 'Epilog';
  Text := FLayout.SaveToText;
  AssertTrue(Reason, FLayout.LoadFromText(Text, Reason));
  AssertEquals('Epilog', FLayout.Output.Profile);
end;

procedure TTestLayoutExports.TestPlainSVGHasNoProfileMarks;
var
  Text: string;
begin
  AddMarkedPattern('a.sloper');
  FLayout.PlaceNewPieces;
  Text := LayoutToSVG(FLayout);
  AssertEquals('holes stay strokes', 0, Count('<circle', Text));
  AssertEquals('one colour', 0, Count('#ff0000', Text));
end;

procedure TTestLayoutExports.TestMachineSVGColours;
var
  Text: string;
begin
  AddMarkedPattern('a.sloper');
  FLayout.PlaceNewPieces;
  FLayout.Output.Profile := StandardProfileName;
  Text := LayoutToSVG(FLayout);
  AssertTrue(Text, Pos('class="cut" data-layer="Cut" stroke="#ff0000"', Text) > 0);
  AssertTrue(Text, Pos('class="score" data-layer="Score" stroke="#0000ff"', Text) > 0);
  AssertTrue(Text, Pos('class="mark" data-layer="Mark" stroke="#000000"', Text) > 0);
  AssertTrue(Text, Pos('fill="#00ff00"', Text) > 0);
end;

procedure TTestLayoutExports.TestMachineSVGCutsLast;
var
  Text: string;
begin
  AddMarkedPattern('a.sloper');
  FLayout.PlaceNewPieces;
  FLayout.Output.Profile := StandardProfileName;
  Text := LayoutToSVG(FLayout);
  AssertTrue('score, mark', Pos('class="score"', Text) < Pos('class="mark"', Text));
  AssertTrue('mark, engrave', Pos('class="mark"', Text) < Pos('class="engrave"', Text));
  AssertTrue('engrave, hole', Pos('class="engrave"', Text) < Pos('class="hole"', Text));
  AssertTrue('hole, cut', Pos('class="hole"', Text) < Pos('class="cut"', Text));
end;

procedure TTestLayoutExports.TestMachineSVGHolesAreCircles;
var
  Text: string;
begin
  AddMarkedPattern('a.sloper');
  FLayout.PlaceNewPieces;
  FLayout.Output.Profile := StandardProfileName;
  Text := LayoutToSVG(FLayout);
  AssertEquals(6, Count('<circle', Text));
  AssertTrue(Text, Pos('<circle cx="40" cy="70" r="2"/>', Text) > 0);
end;

procedure TTestLayoutExports.TestMachineSVGLineTypeOff;
var
  Profile: TMachineProfile;
  Text: string;
begin
  AddMarkedPattern('a.sloper');
  FLayout.PlaceNewPieces;
  Profile := StandardProfile;
  Profile.Name := 'Outlines';
  Profile.Lines[ltMark].Enabled := False;
  Profile.Lines[ltScore].Enabled := False;
  Profile.Lines[ltEngrave].Enabled := False;
  Profile.Lines[ltHole].Enabled := False;
  Insert(Profile, FLayout.MachineProfiles, 0);
  FLayout.Output.Profile := 'outlines';
  Text := LayoutToSVG(FLayout);
  AssertEquals('cut only', 1, Count('<g class=', Text));
  AssertEquals(1, Count('class="cut"', Text));
end;

procedure TTestLayoutExports.TestUnknownProfileRefusesOnlyMachineExports;
var
  Reason: string;
begin
  AddPattern('a.sloper', [100], [100]);
  FLayout.PlaceNewPieces;
  FLayout.Output.Profile := 'Epilog';
  AssertFalse('SVG', ExportLayout(FLayout, efSVG, ConcatPaths([FFolder, 'a.svg']), Reason));
  AssertTrue(Reason, Pos('Epilog', Reason) > 0);
  AssertFalse('nothing written', FileExists(ConcatPaths([FFolder, 'a.svg'])));
  AssertFalse('machine DXF', ExportLayout(FLayout, efMachineDXF, ConcatPaths([FFolder, 'a.dxf']), Reason));
  AssertTrue('PDF has no use for it', ExportLayout(FLayout, efPDF, ConcatPaths([FFolder, 'a.pdf']), Reason));
  AssertTrue('AAMA has no use for it', ExportLayout(FLayout, efDXF, ConcatPaths([FFolder, 'b.dxf']), Reason));
  AssertEquals('one warning', 1, Length(FLayout.Problems));
  AssertFalse(FLayout.Problems[0].Blocking);
end;

procedure TTestLayoutExports.TestProfileWarnsOfQuarterTurn;
begin
  AddPattern('a.sloper', [100], [100]);
  FLayout.PlaceNewPieces;
  FLayout.Placements[0].Rotation := 90;
  AssertEquals('paper does not mind', 0, Length(FLayout.Problems));
  FLayout.Output.Profile := StandardProfileName;
  AssertEquals(1, Length(FLayout.Problems));
  FLayout.Placements[0].Rotation := 180;
  AssertEquals('a half turn stays on the grain', 0, Length(FLayout.Problems));
end;

procedure TTestLayoutExports.TestDXFWritesMarkings;
var
  Text: string;
begin
  AddMarkedPattern('a.sloper');
  FLayout.PlaceNewPieces;
  Text := LayoutToDXF(FLayout);
  AssertEquals('placement and fold lines', 2, Count('LINE'#13#10'  8'#13#10'8'#13#10, Text));
  AssertEquals('every hole, as a point', 6, Count('POINT'#13#10'  8'#13#10'13'#13#10, Text));
end;

procedure TTestLayoutExports.TestMachineDXFFollowsPlacement;
var
  Text: string;
begin
  AddMarkedPattern('a.sloper');
  FLayout.PlaceNewPieces;
  Text := LayoutToMachineDXF(FLayout, StandardProfile);
  AssertEquals(6, Count('CIRCLE'#13#10, Text));
  AssertTrue(Text, Pos('CIRCLE'#13#10'  8'#13#10'Hole'#13#10' 10'#13#10'40'#13#10' 20'#13#10'50'#13#10, Text) > 0);
  AssertEquals('placed, so no blocks', 0, Count('BLOCK', Text));
end;

procedure TTestLayoutExports.TestMachineDXFCutsLast;
var
  Text: string;
begin
  AddMarkedPattern('a.sloper');
  FLayout.PlaceNewPieces;
  Text := LayoutToMachineDXF(FLayout, StandardProfile);
  AssertTrue('holes, cut', Pos('CIRCLE', Text) < Pos('POLYLINE'#13#10'  8'#13#10'Cut', Text));
end;

procedure TTestLayoutExports.TestMachineDXFLayersSharedOnce;
var
  Profile: TMachineProfile;
  Text: string;
begin
  AddPattern('a.sloper', [100], [100]);
  FLayout.PlaceNewPieces;
  Profile := StandardProfile;
  Profile.Lines[ltHole].Layer := 'Cut';
  Text := LayoutToMachineDXF(FLayout, Profile);
  AssertEquals(1, Count('LAYER'#13#10'  2'#13#10'Cut'#13#10, Text));
  AssertTrue('red', Pos('LAYER'#13#10'  2'#13#10'Cut'#13#10' 70'#13#10'0'#13#10' 62'#13#10'1'#13#10, Text) > 0);
end;

procedure TTestLayoutExports.TestMachineDXFRepeatsExactly;
begin
  AddMarkedPattern('a.sloper');
  FLayout.PlaceNewPieces;
  AssertEquals(LayoutToMachineDXF(FLayout, StandardProfile), LayoutToMachineDXF(FLayout, StandardProfile));
end;

procedure TTestLayoutExports.TestMachineDXFFormatName;
var
  Found: TExportFormat;
begin
  AssertTrue(ExportFormatFor('machine-dxf', 'a.dxf', Found));
  AssertTrue(Found = efMachineDXF);
  AssertTrue(ExportFormatFor('', 'a.dxf', Found));
  AssertTrue('the extension means AAMA', Found = efDXF);
  AssertFalse(ExportFormatFor('hpgl', '', Found));
end;

procedure TTestLayoutExports.TestFormatFromName;
var
  Found: TExportFormat;
begin
  AssertTrue(ExportFormatFor('dxf', 'a.pdf', Found));
  AssertTrue('name wins', Found = efDXF);
  AssertTrue(ExportFormatFor('SVG', '', Found));
  AssertTrue('any case', Found = efSVG);
  AssertFalse('unknown', ExportFormatFor('png', '', Found));
end;

procedure TTestLayoutExports.TestFormatFromExtension;
var
  Found: TExportFormat;
begin
  AssertTrue(ExportFormatFor('', 'a.DXF', Found));
  AssertTrue('extension', Found = efDXF);
  AssertTrue(ExportFormatFor('', '', Found));
  AssertTrue('default', Found = efPDF);
  AssertFalse('unknown', ExportFormatFor('', 'a.png', Found));
end;

procedure TTestLayoutExports.TestExportWritesFile;
var
  Target, Reason: string;
  AFormat: TExportFormat;
begin
  AddPattern('a.sloper', [100], [100]);
  FLayout.PlaceNewPieces;
  for AFormat := Low(TExportFormat) to High(TExportFormat) do
  begin
    Target := ConcatPaths([FFolder, 'out' + ExportExtensions[AFormat]]);
    AssertTrue(Reason, ExportLayout(FLayout, AFormat, Target, Reason));
    AssertTrue(Target, FileExists(Target));
  end;
end;

procedure TTestLayoutExports.TestExportRefusesBlockedLayout;
var
  Target, Reason: string;
  AFormat: TExportFormat;
begin
  AddPattern('a.sloper', [100], [100]);
  for AFormat := Low(TExportFormat) to High(TExportFormat) do
  begin
    Target := ConcatPaths([FFolder, 'blocked' + ExportExtensions[AFormat]]);
    AssertFalse('nothing placed', ExportLayout(FLayout, AFormat, Target, Reason));
    AssertTrue(Reason, Pos(rsLayoutRefused, Reason) = 1);
    AssertFalse(Target, FileExists(Target));
  end;
end;

procedure TTestLayoutExports.TestPackNeverOverlaps;
var
  Outcome: TPackResult;
begin
  AddPattern('a.sloper', [300, 120, 90, 90, 200, 60, 150], [500, 200, 400, 90, 100, 60, 300], 2);
  Outcome := PackLayout(FLayout);
  AssertTrue(Outcome.Reason, Outcome.Done);
  AssertEquals('all placed', 14, Outcome.Count);
  AssertNoOverlap;
end;

procedure TTestLayoutExports.TestPackRepeatsExactly;
var
  First: string;
begin
  AddPattern('a.sloper', [300, 120, 90, 90, 200], [500, 200, 400, 90, 100]);
  PackLayout(FLayout);
  First := FLayout.SaveToText;
  PackLayout(FLayout);
  FLayout.Placements := nil;
  PackLayout(FLayout);
  AssertEquals(First, FLayout.SaveToText);
end;

// Eight small squares in rows up to a metre wide fill many A4 pages sparsely
procedure TTestLayoutExports.TestPackReducesPages;
var
  Before: integer;
  Outcome: TPackResult;
begin
  AddPattern('a.sloper', [70, 70, 70, 70, 70, 70, 70, 70], [70, 70, 70, 70, 70, 70, 70, 70]);
  FLayout.PlaceNewPieces;
  Before := PagesUsed;
  Outcome := PackLayout(FLayout);
  AssertTrue(Outcome.Reason, Outcome.Done);
  AssertTrue(Format('%d pages from %d', [Outcome.Pages, Before]), Outcome.Pages < Before);
  AssertEquals('reports the pages', PagesUsed, Outcome.Pages);
end;

// A hand arrangement that beats bounding boxes is left alone
procedure TTestLayoutExports.TestPackDoesNotAddPages;
var
  Before: string;
  Outcome: TPackResult;
begin
  AddPattern('a.sloper', [100], [100]);
  FLayout.PlaceNewPieces;
  FLayout.Placements[0].X := 0;
  FLayout.Placements[0].Y := 0;
  Before := FLayout.SaveToText;
  Outcome := PackLayout(FLayout);
  AssertTrue(Outcome.Reason, Outcome.Done or (Outcome.Reason = rsPackNoBetter));
  AssertEquals(Before, FLayout.SaveToText);
  AssertEquals('pages', 1, PagesUsed);
end;

procedure TTestLayoutExports.TestPackPlacesTheTray;
begin
  AddPattern('a.sloper', [100, 80], [100, 60]);
  AssertEquals('none placed', 0, Length(FLayout.Placements));
  PackLayout(FLayout);
  AssertEquals('all placed', 2, Length(FLayout.Placements));
  AssertEquals('tray empty', 0, Length(FLayout.Unplaced));
end;

procedure TTestLayoutExports.TestPackKeepsFlips;
var
  Index: integer;
  Flips: array of boolean;
begin
  AddPattern('a.sloper', [100, 80], [100, 60], 2);
  FLayout.PlaceNewPieces;
  Flips := nil;
  SetLength(Flips, Length(FLayout.Placements));
  for Index := 0 to High(Flips) do
    Flips[Index] := FLayout.Placements[Index].Flipped;
  PackLayout(FLayout);
  for Index := 0 to High(Flips) do
    AssertEquals('flip', Flips[Index], FLayout.Placements[Index].Flipped);
end;

// Too wide for one page lying flat, so turning it saves a page
procedure TTestLayoutExports.TestPackTurnsByQuarters;
var
  Placement: TPlacement;
begin
  AddPattern('a.sloper', [230], [100]);
  FLayout.PlaceNewPieces;
  PackLayout(FLayout);
  AssertEquals('one page', 1, PagesUsed);
  for Placement in FLayout.Placements do
    AssertEquals('a quarter turn', 0, Placement.Rotation mod 90);
  AssertEquals('turned', 90, FLayout.Placements[0].Rotation);
end;

procedure TTestLayoutExports.TestPackRollWidth;
var
  Shape: TPlacedPiece;
begin
  AddPattern('a.sloper', [200, 200, 200, 200, 200, 200], [100, 100, 100, 100, 100, 100]);
  FLayout.Output.Kind := okLarge;
  FLayout.Output.RollWidth := 500;
  PackLayout(FLayout);
  AssertNoOverlap;
  for Shape in FLayout.PlacedPieces do
    AssertTrue('inside the roll', Shape.Bounds.MaxX <= 490 + 0.001);
end;

procedure TTestLayoutExports.TestPackLeavesOutTooWide;
var
  Outcome: TPackResult;
begin
  AddPattern('a.sloper', [600, 100], [600, 100]);
  FLayout.PlaceNewPieces;
  FLayout.Output.Kind := okLarge;
  FLayout.Output.RollWidth := 500;
  Outcome := PackLayout(FLayout);
  AssertEquals('left out', 1, Outcome.LeftOut);
  AssertEquals('the small one', 1, Outcome.Count);
end;

procedure TTestLayoutExports.TestPackRefusesProjector;
var
  Outcome: TPackResult;
begin
  AddPattern('a.sloper', [100], [100]);
  FLayout.Output.Kind := okProjector;
  Outcome := PackLayout(FLayout);
  AssertFalse('refused', Outcome.Done);
  AssertEquals(rsPackProjector, Outcome.Reason);
  AssertEquals('nothing placed', 0, Length(FLayout.Placements));
end;

procedure TTestLayoutExports.TestPackClearsExcludedPages;
begin
  AddPattern('a.sloper', [70, 70, 70, 70], [70, 70, 70, 70]);
  FLayout.PlaceNewPieces;
  FLayout.TogglePage('A2');
  AssertTrue(PackLayout(FLayout).Done);
  AssertEquals('cleared', 0, Length(FLayout.Output.ExcludedPages));
end;

procedure TTestLayoutExports.TestPackNothing;
var
  Outcome: TPackResult;
begin
  FLayout.AddSource('missing.sloper', '', '');
  FLayout.LoadSources;
  Outcome := PackLayout(FLayout);
  AssertFalse('nothing', Outcome.Done);
  AssertEquals(rsPackNothing, Outcome.Reason);
end;

initialization
  RegisterTest(TTestLayoutExports);

end.
