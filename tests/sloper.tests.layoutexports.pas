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
    procedure TestDXFFoldIsMirrorLine;
    procedure TestDXFNotch;
    procedure TestDXFOnlyPlacedPieces;
    procedure TestDXFBlockNamesAreUnique;
    procedure TestDXFRepeatsExactly;
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
  Math, Sloper.Core.Draft, Sloper.Core.EvalTypes, Sloper.Core.PatternFile, Sloper.Core.PieceDetect, Sloper.Output.LayoutSVG,
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
