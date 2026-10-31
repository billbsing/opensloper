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

// Layout files, tiling and the tiled PDF.
unit Sloper.Tests.Layout;

{$mode ObjFPC}{$H+}

interface

uses
  SysUtils, fpcunit, testregistry, Sloper.Tests.TestCase, Sloper.Core.Geometry, Sloper.Core.Pattern, Sloper.Core.Piece,
  Sloper.Output.Layout, Sloper.Output.Tiling;

type
  TTestLayout = class(TOSTestCase)
  private
    FFolder, FPatternPath: string;
    FLayout: TLayout;
    // A 100 mm square piece "Front" (10 mm allowance) saved to a file
    procedure WritePattern(CutCount: integer = 1; Mirrored: boolean = False; const Allowance: string = '10');
    procedure Prepare;
    function ProblemText: string;
    function Tiles: TTileSettings;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestPageCountsOverlap;
    procedure TestPageAreas;
    procedure TestCaptions;
    procedure TestPolygonTouches;
    procedure TestPolygonCoveringPage;
    procedure TestUnusableTiles;
    procedure TestFileRoundTrip;
    procedure TestLoadRefusals;
    procedure TestPaperSizes;
    procedure TestCustomPaper;
    procedure TestMissingOutputMembersKeepDefaults;
    procedure TestPlaceNewPieces;
    procedure TestCopiesAndMirror;
    procedure TestPlacementStaysAtTopLeft;
    procedure TestRotationHalfTurn;
    procedure TestRotationQuarterTurn;
    procedure TestModelYPointsUp;
    procedure TestUnplacedIsAWarning;
    procedure TestMissingPatternBlocks;
    procedure TestDeletedPieceBlocks;
    procedure TestFailingPieceBlocks;
    procedure TestOverlapIsAWarning;
    procedure TestOffGrainIsAWarning;
    procedure TestSizeTableBlocks;
    procedure TestPDFStructure;
    procedure TestPDFRepeats;
    procedure TestPDFPageSize;
    procedure TestPDFSkipsBlankPages;
    procedure TestPDFEscapesText;
    procedure TestExportRefuses;
    procedure TestExportWrites;
    procedure TestCalibrationScales;
    procedure TestPagesMarkBlank;
    procedure TestViewRoundTrip;
    procedure TestViewZoomKeepsAnchor;
    procedure TestViewFit;
    procedure TestShapeAt;
    procedure TestRoundToStep;
    procedure TestDocumentUndoRedo;
    procedure TestDocumentMergesByKey;
    procedure TestDocumentCancel;
    procedure TestDocumentModified;
    procedure TestDocumentNewForPattern;
    procedure TestDocumentNoChangeNoStep;
    procedure TestPublishTarget;
    procedure TestExpandFields;
    procedure TestTextLines;
    procedure TestNoteBounds;
    procedure TestNotesRoundTrip;
    procedure TestBadNotesRefused;
    procedure TestNoteMakesAPageNeeded;
    procedure TestNotePrintedOnItsPage;
    procedure TestNoteOverPieceWarns;
    procedure TestNoteAt;
    procedure TestRemoveNote;
    procedure TestPageFieldsInNotes;
    procedure TestTitleRoundTrip;
    procedure TestTitleOffByDefault;
    procedure TestTitleOnCover;
    procedure TestTitleLines;
    procedure TestTitleEveryPage;
    procedure TestTitleOnOneSheet;
    procedure TestNewLayoutGetsATitle;
    procedure TestFieldValues;
    procedure TestProjectorIsOneDarkSheet;
    procedure TestProjectorSheetFitsThePieces;
    procedure TestProjectorThickerThanPaper;
    procedure TestProjectorRoundTrip;
    procedure TestProjectorWarnsAcrossTheGrain;
    procedure TestPaperHasNoBackground;
    procedure TestPDFGray;
    procedure TestUnplacedCopies;
    procedure TestPlaceOneCopy;
    procedure TestPlaceCopyAtCentres;
    procedure TestPlaceCopyAtStaysOnSheet;
    procedure TestPlaceCopyAtFlipsEvenCopies;
    procedure TestRemovePlacementReturnsToUnplaced;
    procedure TestFailingPieceWaitsUnplaced;
    procedure TestExtraCopyWarns;
    procedure TestTogglePage;
    procedure TestExcludedPagesSaved;
    procedure TestExcludedPageIsNotPrinted;
    procedure TestBlankStaysBlankWhenExcluded;
    procedure TestPageCaptionAt;
    procedure TestLargeIsOneSheet;
    procedure TestLargeSheetSize;
    procedure TestLargeRoundTrip;
    procedure TestLargeCheckBlock;
    procedure TestLargeWiderThanRollWarns;
    procedure TestLargeIgnoresExclusions;
    procedure TestLargeNarrowRollRefused;
    procedure TestPublishProgram;
    procedure TestWatchWaitsForAStableFile;
    procedure TestWatchIgnoresUnchangedFiles;
    procedure TestWatchSeesMeasurements;
    procedure TestWatchSeesDeletedPattern;
  end;

implementation

uses
  Classes, Math, Sloper.Core.AppPaths, Sloper.Core.JSON, Sloper.Core.Draft, Sloper.Core.Measurements, Sloper.Core.PatternFile, Sloper.Core.PieceDetect,
  Sloper.Output.LayoutDocument, Sloper.Output.LayoutPDF, Sloper.Output.PDFWriter, Sloper.Output.Preview;

function CountOf(const Part, Text: rawbytestring): integer;
var
  Position: integer;
begin
  Result := 0;
  Position := Pos(Part, Text);
  while Position > 0 do
  begin
    Inc(Result);
    Position := Pos(Part, Text, Position + Length(Part));
  end;
end;

procedure TTestLayout.SetUp;
begin
  FFolder := IncludeTrailingPathDelimiter(GetTempDir) + 'sloper-layout-' + IntToStr(Random(MaxInt));
  ForceDirectories(FFolder);
  FPatternPath := ConcatPaths([FFolder, 'front.sloper']);
  FLayout := TLayout.Create;
  FLayout.FileName := ConcatPaths([FFolder, 'front.slayout']);
end;

procedure TTestLayout.TearDown;
var
  Found: TSearchRec;
begin
  FreeAndNil(FLayout);
  if FindFirst(ConcatPaths([FFolder, '*']), faAnyFile, Found) = 0 then
    repeat
      DeleteFile(ConcatPaths([FFolder, Found.Name]));
    until FindNext(Found) <> 0;
  FindClose(Found);
  RemoveDir(FFolder);
end;

procedure TTestLayout.WritePattern(CutCount: integer; Mirrored: boolean; const Allowance: string);
var
  Pattern: TPattern;
  A, B, C, D, Reason: string;
  Path: TPiecePath;
  Piece: TPieceObject;
begin
  Pattern := TPattern.Create;
  try
    A := Pattern.AddFreePoint('A', '0', '0').Key;
    B := Pattern.AddFreePoint('B', '100', '0').Key;
    C := Pattern.AddFreePoint('C', '100', '100').Key;
    D := Pattern.AddFreePoint('D', '0', '100').Key;
    Pattern.AddLine(A, B, erOutline);
    Pattern.AddLine(B, C, erOutline);
    Pattern.AddLine(C, D, erOutline);
    Pattern.AddLine(D, A, erOutline);
    Pattern.Evaluate;
    AssertTrue(Reason, DetectPiecePath(Pattern, Vec2(50, 50), Path, Reason));
    Piece := Pattern.AddPiece('Front', Path, Allowance);
    Pattern.SetCut(Piece, CutCount, Mirrored);
    AssertTrue(Reason, SavePatternToFile(Pattern, FPatternPath, Reason));
  finally
    FreeAndNil(Pattern);
  end;
end;

procedure TTestLayout.Prepare;
begin
  FLayout.AddSource('front.sloper', '', '');
  FLayout.LoadSources;
end;

function TTestLayout.ProblemText: string;
var
  Problem: TLayoutProblem;
begin
  Result := '';
  for Problem in FLayout.Problems do
    Result := Result + Problem.Text + LineEnding;
end;

function TTestLayout.Tiles: TTileSettings;
begin
  Result := Default(TTileSettings);
  Result.PaperWidth := 210;
  Result.PaperHeight := 297;
  Result.Margin := 5;
  Result.Overlap := 10;
end;

procedure TTestLayout.TestPageCountsOverlap;
var
  Rows, Columns: integer;
begin
  // 200 × 287 printable, each extra page adds 190 × 277
  TilePages(Vec2(200, 287), Tiles, Rows, Columns);
  AssertEquals('one page exactly', 1, Rows * Columns);
  TilePages(Vec2(201, 287), Tiles, Rows, Columns);
  AssertEquals('just past', 2, Columns);
  TilePages(Vec2(390, 564), Tiles, Rows, Columns);
  AssertEquals('columns', 2, Columns);
  AssertEquals('rows', 2, Rows);
  TilePages(Vec2(391, 565), Tiles, Rows, Columns);
  AssertEquals('columns', 3, Columns);
  AssertEquals('rows', 3, Rows);
end;

procedure TTestLayout.TestPageAreas;
var
  Pages: TTilePageArray;
  Rows, Columns: integer;
begin
  Pages := TilePages(Vec2(300, 300), Tiles, Rows, Columns);
  AssertEquals('pages', 4, Length(Pages));
  AssertNear('second column starts inside the first', 190, Pages[1].Area.MinX);
  AssertNear('and shares the overlap', 200, Pages[0].Area.MaxX);
  AssertNear('second row', 277, Pages[2].Area.MinY);
  AssertEquals('B2', Pages[3].Caption);
end;

procedure TTestLayout.TestCaptions;
begin
  AssertEquals('A1', TileCaption(0, 0));
  AssertEquals('C12', TileCaption(2, 11));
  AssertEquals('Z1', TileCaption(25, 0));
  AssertEquals('AA1', TileCaption(26, 0));
  AssertEquals('AB1', TileCaption(27, 0));
end;

procedure TTestLayout.TestPolygonTouches;
var
  Square: TVec2Array;
  Area: TRect2;
begin
  Square := nil;
  SetLength(Square, 4);
  Square[0] := Vec2(0, 0);
  Square[1] := Vec2(100, 0);
  Square[2] := Vec2(100, 100);
  Square[3] := Vec2(0, 100);
  Area.MinX := 50;
  Area.MinY := 50;
  Area.MaxX := 200;
  Area.MaxY := 200;
  AssertTrue('corner inside', PolygonTouches(Square, Area));
  Area.MinX := 150;
  AssertFalse('clear of it', PolygonTouches(Square, Area));
  // A sliver passing right through, with no point in the page
  Area.MinX := 40;
  Area.MaxX := 60;
  Area.MinY := -10;
  Area.MaxY := 110;
  AssertTrue('crossed', PolygonTouches(Square, Area));
end;

procedure TTestLayout.TestPolygonCoveringPage;
var
  Square: TVec2Array;
  Area: TRect2;
begin
  Square := nil;
  SetLength(Square, 4);
  Square[0] := Vec2(0, 0);
  Square[1] := Vec2(1000, 0);
  Square[2] := Vec2(1000, 1000);
  Square[3] := Vec2(0, 1000);
  Area.MinX := 100;
  Area.MinY := 100;
  Area.MaxX := 300;
  Area.MaxY := 300;
  AssertTrue('the page is all piece', PolygonTouches(Square, Area));
end;

procedure TTestLayout.TestUnusableTiles;
var
  Settings: TTileSettings;
begin
  Settings := Tiles;
  AssertTrue(TilesAreUsable(Settings));
  Settings.Margin := 100;
  AssertFalse('no room', TilesAreUsable(Settings));
end;

procedure TTestLayout.TestFileRoundTrip;
var
  Text, ErrorMessage: string;
  Other: TLayout;
begin
  WritePattern(2, True);
  Prepare;
  FLayout.Name := 'Summer dress';
  FLayout.Output.Tiles.Overlap := 12;
  AssertEquals(2, FLayout.PlaceNewPieces);
  Text := FLayout.SaveToText;
  Other := TLayout.Create;
  try
    AssertTrue(ErrorMessage, Other.LoadFromText(Text, ErrorMessage));
    AssertEquals('same text', Text, Other.SaveToText);
    AssertEquals('Summer dress', Other.Name);
    AssertEquals(2, Length(Other.Placements));
    AssertTrue('second copy flipped', Other.Placements[1].Flipped);
    AssertNear('overlap', 12, Other.Output.Tiles.Overlap);
    // The next source keeps counting
    AssertEquals(2, Other.AddSource('other.sloper', '', '').Id);
  finally
    FreeAndNil(Other);
  end;
end;

procedure TTestLayout.TestLoadRefusals;
var
  ErrorMessage: string;

  procedure Refused(const Msg, Text, Expected: string);
  begin
    AssertFalse(Msg, FLayout.LoadFromText(Text, ErrorMessage));
    AssertEquals(Msg, Expected, ErrorMessage);
    AssertEquals(Msg + ': left empty', 0, FLayout.Sources.Count);
  end;

begin
  Refused('format', '{"format": "pattern", "version": 1}', rsLayoutWrongFormat);
  Refused('newer', '{"format": "layout", "version": 99}', Format(rsLayoutNewerVersion, [99]));
  Refused('sources', '{"format": "layout", "version": 1}', Format(rsLayoutList, ['sources']));
  Refused('repeated id', '{"format": "layout", "version": 1, "sources": [{"id": 1, "pattern": "a"}, {"id": 1, "pattern": "b"}]}',
    Format(rsLayoutBadSource, [2]));
  Refused('nextId', '{"format": "layout", "version": 1, "nextId": 1, "sources": [{"id": 3, "pattern": "a"}]}', rsLayoutBadNextId);
  Refused('placement', '{"format": "layout", "version": 1, "sources": [{"id": 1, "pattern": "a"}], "placements": [{"source": 2, "piece": 5, "x": 0, "y": 0}]}',
    Format(rsLayoutUnknownSource, [1, 2]));
  Refused('paper', '{"format": "layout", "version": 1, "sources": [], "output": {"paper": "B9"}}', Format(rsLayoutBadPaper, ['B9']));
  Refused('margin', '{"format": "layout", "version": 1, "sources": [], "output": {"margin": 200}}', rsLayoutNoPrintArea);
end;

procedure TTestLayout.TestPaperSizes;
var
  PaperWidth, PaperHeight: double;
begin
  AssertTrue(PaperSize('A4', PaperWidth, PaperHeight));
  AssertNear('A4', 297, PaperHeight);
  AssertTrue(PaperSize('Letter', PaperWidth, PaperHeight));
  AssertNear('Letter', 215.9, PaperWidth);
  AssertFalse(PaperSize('B9', PaperWidth, PaperHeight));
end;

procedure TTestLayout.TestCustomPaper;
var
  ErrorMessage, Text: string;
begin
  AssertTrue(ErrorMessage, FLayout.LoadFromText(
    '{"format": "layout", "version": 1, "sources": [], "output": {"paper": "custom", "paperWidth": 300, "paperHeight": 400}}', ErrorMessage));
  AssertNear('width', 300, FLayout.Output.Tiles.PaperWidth);
  Text := FLayout.SaveToText;
  AssertTrue(ErrorMessage, FLayout.LoadFromText(Text, ErrorMessage));
  AssertNear('height', 400, FLayout.Output.Tiles.PaperHeight);
end;

procedure TTestLayout.TestMissingOutputMembersKeepDefaults;
var
  ErrorMessage: string;
begin
  AssertTrue(ErrorMessage, FLayout.LoadFromText('{"format": "layout", "version": 1, "sources": [{"id": 1, "pattern": "a"}], "output": {},' +
    ' "placements": [{"source": 1, "piece": 5, "x": 0, "y": 0}]}', ErrorMessage));
  AssertEquals('A4', FLayout.Output.Paper);
  AssertNear('margin', 6, FLayout.Output.Tiles.Margin);
  AssertNear('overlap', 10, FLayout.Output.Tiles.Overlap);
  AssertNear('calibration', 1, FLayout.Output.CalibrationX);
  AssertEquals('first copy', 1, FLayout.Placements[0].Copy);
end;

procedure TTestLayout.TestPlaceNewPieces;
var
  Shapes: TPlacedPieceArray;
begin
  WritePattern;
  Prepare;
  AssertEquals(1, FLayout.PlaceNewPieces);
  AssertEquals('nothing left', 0, FLayout.PlaceNewPieces);
  Shapes := FLayout.PlacedPieces;
  AssertEquals(1, Length(Shapes));
  AssertNear('from the left', 0, Shapes[0].Bounds.MinX);
  AssertNear('cut width', 120, Shapes[0].Bounds.MaxX);
  AssertEquals('Front, cut 1', Shapes[0].Caption);
end;

procedure TTestLayout.TestCopiesAndMirror;
var
  Shapes: TPlacedPieceArray;
begin
  WritePattern(3, True);
  Prepare;
  AssertEquals(3, FLayout.PlaceNewPieces);
  AssertFalse('first as drawn', FLayout.Placements[0].Flipped);
  AssertTrue('second mirrored', FLayout.Placements[1].Flipped);
  AssertFalse('third as drawn', FLayout.Placements[2].Flipped);
  Shapes := FLayout.PlacedPieces;
  AssertTrue('side by side', Shapes[1].Bounds.MinX >= Shapes[0].Bounds.MaxX);
  AssertEquals('copies are numbered', 2, FLayout.Placements[1].Copy);
end;

procedure TTestLayout.TestPlacementStaysAtTopLeft;
var
  Shapes: TPlacedPieceArray;
begin
  WritePattern;
  Prepare;
  FLayout.PlaceNewPieces;
  FLayout.Placements[0].X := 40;
  FLayout.Placements[0].Y := 25;
  WritePattern(1, False, '30');
  FLayout.LoadSources;
  Shapes := FLayout.PlacedPieces;
  AssertNear('same left', 40, Shapes[0].Bounds.MinX);
  AssertNear('same top', 25, Shapes[0].Bounds.MinY);
  AssertNear('grown', 40 + 160, Shapes[0].Bounds.MaxX);
end;

procedure TTestLayout.TestRotationHalfTurn;
var
  Plain, Turned: TPlacedPieceArray;
begin
  WritePattern;
  Prepare;
  FLayout.PlaceNewPieces;
  Plain := FLayout.PlacedPieces;
  FLayout.Placements[0].Rotation := 180;
  Turned := FLayout.PlacedPieces;
  AssertNear('same corner', Plain[0].Bounds.MinX, Turned[0].Bounds.MinX);
  AssertNear('same size', Plain[0].Bounds.MaxY, Turned[0].Bounds.MaxY);
end;

procedure TTestLayout.TestRotationQuarterTurn;
var
  Shapes: TPlacedPieceArray;
  Grain: TLine2;
begin
  WritePattern;
  Prepare;
  FLayout.PlaceNewPieces;
  FLayout.Placements[0].Rotation := 90;
  Shapes := FLayout.PlacedPieces;
  AssertNear('corner stays', 0, Shapes[0].Bounds.MinX);
  AssertNear('square piece, same width', 120, Shapes[0].Bounds.MaxX);
  // The grainline ran up the page, and now runs across it
  Grain := Shapes[0].Marks[0];
  AssertNear('square to the sheet', Grain.P1.Y, Grain.P2.Y);
end;

// Model y points up and layout y down, so the piece's top comes first
procedure TTestLayout.TestModelYPointsUp;
var
  Shapes: TPlacedPieceArray;
  Grain: TLine2;
begin
  WritePattern;
  Prepare;
  FLayout.PlaceNewPieces;
  Shapes := FLayout.PlacedPieces;
  // The grainline runs up the piece from model y = 20 to 80
  Grain := Shapes[0].Marks[0];
  AssertNear('low end further down the page', 90, Grain.P1.Y);
  AssertNear('high end nearer the top', 30, Grain.P2.Y);
end;

procedure TTestLayout.TestUnplacedIsAWarning;
var
  Problems: TLayoutProblemArray;
begin
  WritePattern;
  Prepare;
  Problems := FLayout.Problems;
  AssertEquals(1, Length(Problems));
  AssertFalse(Problems[0].Blocking);
  AssertEquals(Format(rsLayoutUnplaced, ['front.sloper', 'Front', 1, 1]), Problems[0].Text);
end;

procedure TTestLayout.TestMissingPatternBlocks;
var
  Problems: TLayoutProblemArray;
begin
  Prepare;
  Problems := FLayout.Problems;
  AssertEquals(1, Length(Problems));
  AssertTrue(Problems[0].Blocking);
  AssertTrue(Problems[0].Text, Pos('File not found', Problems[0].Text) > 0);
end;

procedure TTestLayout.TestDeletedPieceBlocks;
var
  Problems: TLayoutProblemArray;
begin
  WritePattern;
  Prepare;
  FLayout.PlaceNewPieces;
  FLayout.Placements[0].PieceKey := '999';
  Problems := FLayout.Problems;
  AssertTrue(ProblemText, Length(Problems) >= 1);
  AssertTrue('never dropped silently', Problems[0].Blocking);
  AssertEquals(Format(rsLayoutPieceGone, ['front.sloper', '999']), Problems[0].Text);
end;

procedure TTestLayout.TestFailingPieceBlocks;
var
  Problems: TLayoutProblemArray;
begin
  WritePattern(1, False, '-1');
  Prepare;
  FLayout.PlaceNewPieces;
  AssertEquals('a failing piece is not placed', 0, Length(FLayout.Placements));
  Problems := nil;
  SetLength(FLayout.Placements, 1);
  FLayout.Placements[0] := Default(TPlacement);
  FLayout.Placements[0].SourceId := 1;
  FLayout.Placements[0].PieceKey := FLayout.Sources[0].Pattern.FindObject('Front').Key;
  Problems := FLayout.Problems;
  AssertTrue(ProblemText, Problems[0].Blocking);
end;

procedure TTestLayout.TestOverlapIsAWarning;
begin
  WritePattern(2);
  Prepare;
  FLayout.PlaceNewPieces;
  AssertEquals('apart', '', ProblemText);
  FLayout.Placements[1].X := FLayout.Placements[0].X + 50;
  AssertEquals(Format(rsLayoutOverlap, ['Front, cut 2', 'Front, cut 2']) + LineEnding, ProblemText);
  FLayout.Placements[1].X := -5;
  FLayout.Placements[1].Y := 500;
  AssertEquals(Format(rsLayoutOffSheet, ['Front, cut 2']) + LineEnding, ProblemText);
end;

procedure TTestLayout.TestOffGrainIsAWarning;
var
  Problems: TLayoutProblemArray;
begin
  WritePattern;
  Prepare;
  FLayout.PlaceNewPieces;
  FLayout.Placements[0].Rotation := 90;
  AssertEquals('quarter turns are fine', 0, Length(FLayout.Problems));
  FLayout.Placements[0].Rotation := 45;
  Problems := FLayout.Problems;
  AssertEquals(1, Length(Problems));
  AssertFalse(Problems[0].Blocking);
end;

procedure TTestLayout.TestSizeTableBlocks;
var
  Problems: TLayoutProblemArray;
begin
  WritePattern;
  FLayout.AddSource('front.sloper', '', '38');
  FLayout.LoadSources;
  Problems := FLayout.Problems;
  AssertTrue(Problems[0].Blocking);
  AssertTrue(Problems[0].Text, Pos('38', Problems[0].Text) > 0);
end;

procedure TTestLayout.TestPDFStructure;
var
  Bytes: rawbytestring;
  Offset: integer;
begin
  WritePattern;
  Prepare;
  FLayout.Name := 'Front';
  FLayout.PlaceNewPieces;
  Bytes := LayoutToPDF(FLayout);
  AssertEquals('%PDF-1.4', Copy(Bytes, 1, 8));
  AssertTrue('ends properly', Pos('%%EOF', Bytes) > Length(Bytes) - 10);
  AssertEquals('cover and one tile', 2, CountOf('/Type /Page ', Bytes));
  AssertTrue('reminder', Pos('100%', Bytes) > 0);
  AssertTrue('label', Pos('(Front, cut 1)', Bytes) > 0);
  // startxref points at the table
  Offset := StrToInt(Trim(Copy(Bytes, Pos('startxref', Bytes) + 9, Pos('%%EOF', Bytes) - Pos('startxref', Bytes) - 9)));
  AssertEquals('xref', 'xref', Copy(Bytes, Offset + 1, 4));
end;

procedure TTestLayout.TestPDFRepeats;
begin
  WritePattern;
  Prepare;
  FLayout.PlaceNewPieces;
  AssertTrue('same bytes each time', LayoutToPDF(FLayout) = LayoutToPDF(FLayout));
end;

procedure TTestLayout.TestPDFPageSize;
var
  Bytes: rawbytestring;
begin
  WritePattern;
  Prepare;
  FLayout.PlaceNewPieces;
  Bytes := LayoutToPDF(FLayout);
  // A4 in points
  AssertTrue(Bytes, Pos('/MediaBox [0 0 595.276 841.89]', Bytes) > 0);
end;

procedure TTestLayout.TestPDFSkipsBlankPages;
begin
  WritePattern(2);
  Prepare;
  FLayout.PlaceNewPieces;
  // Corners of a page grid: A1 and a page far along the diagonal
  FLayout.Placements[1].X := 400;
  FLayout.Placements[1].Y := 850;
  AssertEquals('cover and the two pieces, which touch few pages', 1 + 2, CountOf('/Type /Page ', LayoutToPDF(FLayout)));
end;

procedure TTestLayout.TestPDFEscapesText;
var
  Writer: TPDFWriter;
  Bytes: rawbytestring;
begin
  Writer := TPDFWriter.Create;
  try
    Writer.BeginPage(100, 100);
    Writer.Text(0, 0, 10, 'a(b)\c é 日');
    Bytes := Writer.Finish;
  finally
    FreeAndNil(Writer);
  end;
  AssertTrue(Bytes, Pos('(a\(b\)\\c ' + #$E9 + ' ?)', Bytes) > 0);
end;

procedure TTestLayout.TestExportRefuses;
var
  Target, ErrorMessage: string;
begin
  WritePattern;
  Prepare;
  FLayout.PlaceNewPieces;
  FLayout.Placements[0].PieceKey := '999';
  Target := ConcatPaths([FFolder, 'out.pdf']);
  AssertFalse(ExportLayoutPDF(FLayout, Target, ErrorMessage));
  AssertTrue(ErrorMessage, Pos('999', ErrorMessage) > 0);
  AssertFalse('nothing written', FileExists(Target));
end;

procedure TTestLayout.TestExportWrites;
var
  Target, ErrorMessage: string;
begin
  WritePattern;
  Prepare;
  FLayout.PlaceNewPieces;
  Target := ConcatPaths([FFolder, 'out.pdf']);
  AssertTrue(ErrorMessage, ExportLayoutPDF(FLayout, Target, ErrorMessage));
  AssertTrue(FileExists(Target));
end;

procedure TTestLayout.TestCalibrationScales;
var
  Plain, Scaled: rawbytestring;
begin
  WritePattern;
  Prepare;
  FLayout.PlaceNewPieces;
  Plain := LayoutToPDF(FLayout);
  FLayout.Output.CalibrationX := 1.01;
  Scaled := LayoutToPDF(FLayout);
  AssertTrue('the drawing changes', Plain <> Scaled);
end;

procedure TTestLayout.TestPagesMarkBlank;
var
  Pages: TTilePageArray;
  Rows, Columns: integer;
begin
  WritePattern(2);
  Prepare;
  FLayout.PlaceNewPieces;
  FLayout.Placements[1].X := 400;
  Pages := FLayout.Pages(FLayout.PlacedPieces, Rows, Columns);
  AssertEquals('three across', 3, Columns);
  AssertFalse('first in use', Pages[0].Blank);
  AssertTrue('second empty', Pages[1].Blank);
  AssertFalse('third in use', Pages[2].Blank);
end;

procedure TTestLayout.TestViewRoundTrip;
var
  View: TPreviewView;
begin
  View := DefaultPreviewView;
  View.Scale := 2.5;
  View.OriginX := 30;
  View.OriginY := -12;
  AssertPointsNear('there and back', Vec2(40, 70), View.ToLayout(View.ToScreen(Vec2(40, 70))));
  AssertNear('y stays down', 2.5 * 70 - 12, View.ToScreen(Vec2(40, 70)).Y);
end;

procedure TTestLayout.TestViewZoomKeepsAnchor;
var
  View: TPreviewView;
  Before: TVec2;
begin
  View := DefaultPreviewView;
  Before := View.ToLayout(Vec2(200, 100));
  View.ZoomAt(1.5, Vec2(200, 100));
  AssertPointsNear('stays under the cursor', Before, View.ToLayout(Vec2(200, 100)));
  AssertNear('zoomed', 1.5, View.Scale);
end;

procedure TTestLayout.TestViewFit;
var
  View: TPreviewView;
  Area: TRect2;
begin
  View := DefaultPreviewView;
  Area := Default(TRect2);
  Area.MaxX := 400;
  Area.MaxY := 200;
  View.Fit(Area, 1000, 1000, 100);
  AssertNear('limited by the width', 2, View.Scale);
  AssertPointsNear('centred', Vec2(500, 500), View.ToScreen(Vec2(200, 100)));
end;

procedure TTestLayout.TestShapeAt;
var
  Shapes: TPlacedPieceArray;
begin
  WritePattern(2);
  Prepare;
  FLayout.PlaceNewPieces;
  Shapes := FLayout.PlacedPieces;
  AssertEquals('first', 0, ShapeAt(Shapes, Vec2(50, 50)));
  AssertEquals('second', 1, ShapeAt(Shapes, Vec2(190, 50)));
  AssertEquals('between', -1, ShapeAt(Shapes, Vec2(125, 50)));
end;

procedure TTestLayout.TestRoundToStep;
begin
  AssertNear('down', 12.5, RoundToStep(12.6));
  AssertNear('up', 13, RoundToStep(12.8));
end;

procedure TTestLayout.TestDocumentUndoRedo;
var
  Document: TLayoutDocument;
  Reason: string;
begin
  WritePattern;
  Document := TLayoutDocument.Create;
  try
    FLayout.AddSource('front.sloper', '', '');
    AssertTrue(Reason, FLayout.SaveToFile(FLayout.FileName, Reason));
    AssertTrue(Reason, Document.Open(FLayout.FileName, Reason));
    Document.BeginChange('Place');
    Document.Layout.PlaceNewPieces;
    Document.EndChange;
    Document.BeginChange('Move');
    Document.Layout.Placements[0].X := 75;
    Document.EndChange;
    AssertEquals('Move', Document.UndoDescription);
    Document.Undo;
    AssertNear('moved back', 0, Document.Layout.Placements[0].X);
    AssertEquals('patterns read again', 1, Length(Document.Layout.PlacedPieces));
    AssertEquals('Place', Document.UndoDescription);
    Document.Redo;
    AssertNear('moved again', 75, Document.Layout.Placements[0].X);
    AssertEquals('file name kept', FLayout.FileName, Document.Layout.FileName);
    Document.Undo;
    Document.Undo;
    AssertEquals('nothing placed', 0, Length(Document.Layout.Placements));
    AssertFalse(Document.CanUndo);
  finally
    FreeAndNil(Document);
  end;
end;

procedure TTestLayout.TestDocumentMergesByKey;
var
  Document: TLayoutDocument;
begin
  Document := TLayoutDocument.Create;
  try
    Document.BeginChange('Paper');
    Document.Layout.Output.Tiles.Margin := 7;
    Document.EndChange('paper');
    Document.BeginChange('Paper');
    Document.Layout.Output.Tiles.Margin := 8;
    Document.EndChange('paper');
    Document.Undo;
    AssertFalse('one step', Document.CanUndo);
    AssertNear('back to the start', 6, Document.Layout.Output.Tiles.Margin);
  finally
    FreeAndNil(Document);
  end;
end;

procedure TTestLayout.TestDocumentCancel;
var
  Document: TLayoutDocument;
begin
  Document := TLayoutDocument.Create;
  try
    Document.BeginChange('Paper');
    Document.Layout.Output.Tiles.Margin := 9;
    Document.CancelChange;
    AssertNear('put back', 6, Document.Layout.Output.Tiles.Margin);
    AssertFalse('no step', Document.CanUndo);
  finally
    FreeAndNil(Document);
  end;
end;

procedure TTestLayout.TestDocumentModified;
var
  Document: TLayoutDocument;
  Reason, Path: string;
begin
  Path := ConcatPaths([FFolder, 'saved.slayout']);
  Document := TLayoutDocument.Create;
  try
    AssertFalse('new', Document.Modified);
    Document.BeginChange('Paper');
    Document.Layout.Output.Tiles.Margin := 9;
    Document.EndChange;
    AssertTrue('changed', Document.Modified);
    AssertTrue(Reason, Document.Save(Path, Reason));
    AssertFalse('saved', Document.Modified);
    Document.Undo;
    AssertTrue('undone past the save', Document.Modified);
    Document.Redo;
    AssertFalse('back at the save', Document.Modified);
  finally
    FreeAndNil(Document);
  end;
end;

procedure TTestLayout.TestDocumentNewForPattern;
var
  Document: TLayoutDocument;
begin
  WritePattern(2);
  Document := TLayoutDocument.Create;
  try
    Document.NewForPattern(FPatternPath);
    AssertEquals('named after it', 'front', Document.Layout.Name);
    AssertEquals('copies placed', 2, Length(Document.Layout.Placements));
    AssertEquals('beside it', ChangeFileExt(FPatternPath, LayoutExtension), Document.Layout.FileName);
    AssertTrue('not saved yet', Document.Modified);
  finally
    FreeAndNil(Document);
  end;
end;

procedure TTestLayout.TestDocumentNoChangeNoStep;
var
  Document: TLayoutDocument;
begin
  Document := TLayoutDocument.Create;
  try
    Document.BeginChange('Nothing');
    Document.EndChange;
    AssertFalse(Document.CanUndo);
  finally
    FreeAndNil(Document);
  end;
end;

procedure TTestLayout.TestPublishTarget;
var
  Reason: string;
begin
  WritePattern;
  AssertEquals('no layout yet', FPatternPath, PublishTargetFor(FPatternPath));
  FLayout.AddSource('front.sloper', '', '');
  AssertTrue(Reason, FLayout.SaveToFile(FLayout.FileName, Reason));
  AssertEquals('its layout', FLayout.FileName, PublishTargetFor(FPatternPath));
end;

procedure TTestLayout.TestPublishProgram;
var
  Name: string;
  Sub, Reason: string;
begin
  AssertEquals('not there', '', TAppPaths.PublishProgramIn(FFolder));
  Name := 'opensloper-publish' {$IFDEF WINDOWS} + '.exe' {$ENDIF};
  Sub := ConcatPaths([FFolder, 'publish']);
  ForceDirectories(Sub);
  try
    AssertTrue(Reason, WriteTextFile(ConcatPaths([Sub, Name]), '', Reason));
    AssertEquals('source tree', ConcatPaths([Sub, Name]), TAppPaths.PublishProgramIn(FFolder));
    AssertTrue(Reason, WriteTextFile(ConcatPaths([FFolder, Name]), '', Reason));
    AssertEquals('beside it first', ConcatPaths([FFolder, Name]), TAppPaths.PublishProgramIn(FFolder));
  finally
    DeleteFile(ConcatPaths([Sub, Name]));
    RemoveDir(Sub);
  end;
end;

procedure TTestLayout.TestWatchWaitsForAStableFile;
var
  Document: TLayoutDocument;
begin
  WritePattern;
  Document := TLayoutDocument.Create;
  try
    Document.NewForPattern(FPatternPath);
    AssertEquals('unchanged', '', Document.CheckSources);
    WritePattern(3);
    AssertEquals('first sight waits', '', Document.CheckSources);
    AssertEquals('still the old one', 1, Document.Layout.Sources[0].Pattern.ObjectCount div 9);
    AssertEquals('settled, so read', 'front.sloper', Document.CheckSources);
    AssertEquals('new copies are unplaced', 2, Length(Document.Layout.Unplaced));
    AssertEquals('quiet again', '', Document.CheckSources);
  finally
    FreeAndNil(Document);
  end;
end;

procedure TTestLayout.TestWatchIgnoresUnchangedFiles;
var
  Document: TLayoutDocument;
  Calls: integer;
begin
  WritePattern;
  Document := TLayoutDocument.Create;
  try
    Document.NewForPattern(FPatternPath);
    for Calls := 1 to 3 do
      AssertEquals('nothing to do', '', Document.CheckSources);
  finally
    FreeAndNil(Document);
  end;
end;

procedure TTestLayout.TestWatchSeesMeasurements;
var
  Document: TLayoutDocument;
  Measurements: TMeasurementSet;
  Reason, Path: string;
begin
  WritePattern;
  Path := ConcatPaths([FFolder, 'me.slm']);
  Measurements := TMeasurementSet.Create;
  try
    Measurements.Add('waist', 700);
    AssertTrue(Reason, Measurements.SaveToFile(Path, Reason));
    Document := TLayoutDocument.Create;
    try
      Document.Layout.FileName := FLayout.FileName;
      Document.Layout.AddSource('front.sloper', 'me.slm', '');
      Document.Reload;
      AssertEquals('settled', '', Document.CheckSources);
      Measurements.Add('hip', 950);
      AssertTrue(Reason, Measurements.SaveToFile(Path, Reason));
      Document.CheckSources;
      AssertEquals('read again', 'front.sloper', Document.CheckSources);
    finally
      FreeAndNil(Document);
    end;
  finally
    FreeAndNil(Measurements);
  end;
end;

procedure TTestLayout.TestWatchSeesDeletedPattern;
var
  Document: TLayoutDocument;
begin
  WritePattern;
  Document := TLayoutDocument.Create;
  try
    Document.NewForPattern(FPatternPath);
    DeleteFile(FPatternPath);
    Document.CheckSources;
    Document.CheckSources;
    AssertTrue('now a problem', Document.Layout.Problems[0].Blocking);
  finally
    FreeAndNil(Document);
  end;
end;

procedure TTestLayout.TestTogglePage;
var
  Pages: TTilePageArray;
  Rows, Columns: integer;
begin
  WritePattern;
  Prepare;
  FLayout.PlaceNewPieces;
  FLayout.TogglePage('A1');
  Pages := FLayout.Pages(FLayout.PlacedPieces, Rows, Columns);
  AssertTrue('left out', Pages[0].Excluded);
  FLayout.TogglePage('A1');
  Pages := FLayout.Pages(FLayout.PlacedPieces, Rows, Columns);
  AssertFalse('put back', Pages[0].Excluded);
  AssertEquals('none listed', 0, Length(FLayout.Output.ExcludedPages));
end;

procedure TTestLayout.TestExcludedPagesSaved;
var
  Text, ErrorMessage: string;
  Other: TLayout;
begin
  FLayout.TogglePage('B2');
  Text := FLayout.SaveToText;
  Other := TLayout.Create;
  try
    AssertTrue(ErrorMessage, Other.LoadFromText(Text, ErrorMessage));
    AssertEquals('B2', Other.Output.ExcludedPages[0]);
    AssertEquals('same text', Text, Other.SaveToText);
  finally
    FreeAndNil(Other);
  end;
end;

procedure TTestLayout.TestExcludedPageIsNotPrinted;
var
  Bytes: rawbytestring;
begin
  WritePattern(2);
  Prepare;
  FLayout.PlaceNewPieces;
  FLayout.Placements[1].X := 400;
  AssertEquals('cover and two tiles', 3, CountOf('/Type /Page ', LayoutToPDF(FLayout)));
  FLayout.TogglePage('A1');
  Bytes := LayoutToPDF(FLayout);
  AssertEquals('one fewer', 2, CountOf('/Type /Page ', Bytes));
  AssertTrue('counted on the cover', Pos(Format(rsPDFPages, [1, 1, 1]), Bytes) > 0);
end;

procedure TTestLayout.TestBlankStaysBlankWhenExcluded;
var
  Bytes: rawbytestring;
begin
  WritePattern(2);
  Prepare;
  FLayout.PlaceNewPieces;
  FLayout.Placements[1].X := 400;
  FLayout.TogglePage('A2');
  Bytes := LayoutToPDF(FLayout);
  AssertTrue(Pos(Format(rsPDFPages, [2, 1, 0]), Bytes) > 0);
end;

procedure TTestLayout.TestPageCaptionAt;
var
  Pages: TTilePageArray;
  Rows, Columns: integer;
begin
  Pages := TilePages(Vec2(300, 100), Tiles, Rows, Columns);
  AssertEquals('first', 'A1', PageCaptionAt(Pages, Vec2(20, 50)));
  AssertEquals('second', 'A2', PageCaptionAt(Pages, Vec2(300, 50)));
  AssertEquals('overlap goes by the nearer middle', 'A2', PageCaptionAt(Pages, Vec2(198, 150)));
  AssertEquals('off the pages', '', PageCaptionAt(Pages, Vec2(-5, 50)));
end;

procedure TTestLayout.TestLargeIsOneSheet;
var
  Pages: TTilePageArray;
  Rows, Columns: integer;
begin
  WritePattern(2);
  Prepare;
  FLayout.PlaceNewPieces;
  FLayout.Output.Kind := okLarge;
  Pages := FLayout.Pages(FLayout.PlacedPieces, Rows, Columns);
  AssertEquals('one page', 1, Length(Pages));
  AssertEquals(1, CountOf('/Type /Page ', LayoutToPDF(FLayout)));
end;

procedure TTestLayout.TestLargeSheetSize;
var
  Bytes: rawbytestring;
begin
  WritePattern;
  Prepare;
  FLayout.PlaceNewPieces;
  FLayout.Output.Kind := okLarge;
  FLayout.Output.RollWidth := 1000;
  Bytes := LayoutToPDF(FLayout);
  // 1000 mm wide; margin 6 + header 140 + piece 120 + margin 6 = 272 mm long
  AssertTrue(Bytes, Pos('/MediaBox [0 0 2834.646 771.024]', Bytes) > 0);
  AssertNear('the same length for the status bar', 272, LargeSheetLength(FLayout, 120));
end;

procedure TTestLayout.TestLargeRoundTrip;
var
  Text, ErrorMessage: string;
  Other: TLayout;
begin
  FLayout.Output.Kind := okLarge;
  FLayout.Output.RollWidth := 610;
  Text := FLayout.SaveToText;
  Other := TLayout.Create;
  try
    AssertTrue(ErrorMessage, Other.LoadFromText(Text, ErrorMessage));
    AssertTrue(Other.Output.Kind = okLarge);
    AssertNear('roll', 610, Other.Output.RollWidth);
    AssertEquals('same text', Text, Other.SaveToText);
  finally
    FreeAndNil(Other);
  end;
end;

procedure TTestLayout.TestLargeCheckBlock;
var
  Bytes: rawbytestring;
begin
  WritePattern;
  Prepare;
  FLayout.PlaceNewPieces;
  FLayout.Output.Kind := okLarge;
  Bytes := LayoutToPDF(FLayout);
  AssertTrue('reminder', Pos('100%', Bytes) > 0);
  AssertTrue('test square', Pos(' 283.465 283.465 re S', Bytes) > 0);
end;

procedure TTestLayout.TestLargeWiderThanRollWarns;
var
  Problems: TLayoutProblemArray;
begin
  WritePattern;
  Prepare;
  FLayout.PlaceNewPieces;
  FLayout.Output.Kind := okLarge;
  FLayout.Output.RollWidth := 120;
  Problems := FLayout.Problems;
  AssertEquals(ProblemText, 1, Length(Problems));
  AssertFalse(Problems[0].Blocking);
  AssertEquals(Format(rsLayoutWiderThanRoll, ['Front, cut 1', '120']), Problems[0].Text);
end;

procedure TTestLayout.TestLargeIgnoresExclusions;
begin
  WritePattern;
  Prepare;
  FLayout.PlaceNewPieces;
  FLayout.TogglePage('A1');
  FLayout.Output.Kind := okLarge;
  AssertEquals('still printed', 1, CountOf('/Type /Page ', LayoutToPDF(FLayout)));
end;

procedure TTestLayout.TestLargeNarrowRollRefused;
var
  ErrorMessage: string;
begin
  AssertFalse(FLayout.LoadFromText('{"format": "layout", "version": 1, "sources": [], "output": {"kind": "large", "rollWidth": 5}}', ErrorMessage));
  AssertEquals(rsLayoutBadRoll, ErrorMessage);
end;

procedure TTestLayout.TestUnplacedCopies;
var
  Copies: TUnplacedCopyArray;
begin
  WritePattern(2, True);
  Prepare;
  Copies := FLayout.Unplaced;
  AssertEquals(2, Length(Copies));
  AssertEquals(Format(rsLayoutTrayItem, ['Front', 2, 2]), Copies[1].Caption);
  AssertTrue(Copies[0].CanPlace);
  AssertTrue('a problem says so', FLayout.Problems[0].Unplaced);
  FLayout.PlaceNewPieces;
  AssertEquals('none left', 0, Length(FLayout.Unplaced));
end;

procedure TTestLayout.TestPlaceOneCopy;
begin
  WritePattern(2);
  Prepare;
  AssertEquals(1, FLayout.PlaceCopies(Copy(FLayout.Unplaced, 1, 1)));
  AssertEquals('the second copy', 2, FLayout.Placements[0].Copy);
  AssertEquals('the first still waits', 1, FLayout.Unplaced[0].Copy);
end;

procedure TTestLayout.TestPlaceCopyAtCentres;
var
  Index: integer;
  Shapes: TPlacedPieceArray;
begin
  WritePattern;
  Prepare;
  Index := FLayout.PlaceCopyAt(FLayout.Unplaced[0], Vec2(300.2, 400.2), 0.5);
  AssertEquals(0, Index);
  Shapes := FLayout.PlacedPieces;
  // 120 mm wide, centred, then on the 0.5 mm grid
  AssertNear('left', 240, Shapes[0].Bounds.MinX);
  AssertNear('top', 340, Shapes[0].Bounds.MinY);
end;

procedure TTestLayout.TestPlaceCopyAtStaysOnSheet;
begin
  WritePattern;
  Prepare;
  FLayout.PlaceCopyAt(FLayout.Unplaced[0], Vec2(10, 10), 0.5);
  AssertNear('left', 0, FLayout.Placements[0].X);
  AssertNear('top', 0, FLayout.Placements[0].Y);
end;

procedure TTestLayout.TestPlaceCopyAtFlipsEvenCopies;
begin
  WritePattern(2, True);
  Prepare;
  FLayout.PlaceCopyAt(FLayout.Unplaced[1], Vec2(100, 100), 0.5);
  AssertTrue(FLayout.Placements[0].Flipped);
end;

procedure TTestLayout.TestRemovePlacementReturnsToUnplaced;
begin
  WritePattern;
  Prepare;
  FLayout.PlaceNewPieces;
  FLayout.RemovePlacement(0);
  AssertEquals('none placed', 0, Length(FLayout.Placements));
  AssertEquals('waiting again', 1, Length(FLayout.Unplaced));
end;

procedure TTestLayout.TestFailingPieceWaitsUnplaced;
var
  Copies: TUnplacedCopyArray;
begin
  WritePattern(1, False, '-1');
  Prepare;
  Copies := FLayout.Unplaced;
  AssertEquals('still listed', 1, Length(Copies));
  AssertFalse(Copies[0].CanPlace);
  AssertEquals('refused', -1, FLayout.PlaceCopyAt(Copies[0], Vec2(0, 0), 0.5));
  AssertEquals('skipped', 0, FLayout.PlaceCopies(Copies));
end;

procedure TTestLayout.TestExtraCopyWarns;
begin
  WritePattern(2);
  Prepare;
  FLayout.PlaceNewPieces;
  WritePattern(1);
  FLayout.LoadSources;
  AssertTrue(ProblemText, Pos(Format(rsLayoutExtraCopy, ['front.sloper', 'Front', 1, 2]), ProblemText) > 0);
end;

procedure TTestLayout.TestProjectorIsOneDarkSheet;
var
  Bytes: rawbytestring;
begin
  WritePattern(2);
  Prepare;
  FLayout.PlaceNewPieces;
  FLayout.Output.Kind := okProjector;
  Bytes := LayoutToPDF(FLayout);
  AssertEquals('one sheet', 1, CountOf('/Type /Page ', Bytes));
  AssertTrue('black fill', Pos('0 G 0 g', Bytes) > 0);
  AssertTrue('then light lines', Pos('0 G 0 g', Bytes) < Pos('1 G 1 g', Bytes));
  AssertTrue('test square kept', Pos(' 283.465 283.465 re S', Bytes) > 0);
end;

procedure TTestLayout.TestProjectorSheetFitsThePieces;
var
  Bytes: rawbytestring;
begin
  WritePattern;
  Prepare;
  FLayout.PlaceNewPieces;
  FLayout.Output.Kind := okProjector;
  Bytes := LayoutToPDF(FLayout);
  // 6 + 120 + 6 = 132 mm wide, 6 + 140 + 120 + 6 = 272 mm long, not a roll or a paper size
  AssertTrue(Bytes, Pos('/MediaBox [0 0 374.173 771.024]', Bytes) > 0);
end;

procedure TTestLayout.TestProjectorThickerThanPaper;
var
  Bytes: rawbytestring;
begin
  WritePattern;
  Prepare;
  FLayout.PlaceNewPieces;
  FLayout.Output.Kind := okProjector;
  Bytes := LayoutToPDF(FLayout);
  // 1.5 mm in points
  AssertTrue(Bytes, Pos(#10 + '4.252 w', Bytes) > 0);
end;

procedure TTestLayout.TestProjectorRoundTrip;
var
  Text, ErrorMessage: string;
  Other: TLayout;
begin
  FLayout.Output.Kind := okProjector;
  Text := FLayout.SaveToText;
  Other := TLayout.Create;
  try
    AssertTrue(ErrorMessage, Other.LoadFromText(Text, ErrorMessage));
    AssertTrue(Other.Output.Kind = okProjector);
    AssertEquals('same text', Text, Other.SaveToText);
  finally
    FreeAndNil(Other);
  end;
end;

procedure TTestLayout.TestProjectorWarnsAcrossTheGrain;
var
  Problems: TLayoutProblemArray;
begin
  WritePattern;
  Prepare;
  FLayout.PlaceNewPieces;
  FLayout.Placements[0].Rotation := 90;
  AssertEquals('fine on paper', 0, Length(FLayout.Problems));
  FLayout.Output.Kind := okProjector;
  Problems := FLayout.Problems;
  AssertEquals(1, Length(Problems));
  AssertFalse(Problems[0].Blocking);
  AssertEquals(Format(rsLayoutProjectedAcross, ['front.sloper', 'Front']), Problems[0].Text);
  FLayout.Placements[0].Rotation := 180;
  AssertEquals('a half turn stays on the grain', 0, Length(FLayout.Problems));
end;

procedure TTestLayout.TestPaperHasNoBackground;
var
  Bytes: rawbytestring;
begin
  WritePattern;
  Prepare;
  FLayout.PlaceNewPieces;
  AssertEquals('tiled', 0, CountOf(' re f', LayoutToPDF(FLayout)));
  FLayout.Output.Kind := okLarge;
  Bytes := LayoutToPDF(FLayout);
  AssertEquals('large', 0, CountOf(' re f', Bytes));
end;

procedure TTestLayout.TestPDFGray;
var
  Writer: TPDFWriter;
  Bytes: rawbytestring;
  Area: TRect2;
begin
  Writer := TPDFWriter.Create;
  try
    Writer.BeginPage(100, 100);
    Writer.SetGray(0.5);
    Area := Default(TRect2);
    Area.MaxX := 10;
    Area.MaxY := 10;
    Writer.FillRectangle(Area);
    Bytes := Writer.Finish;
  finally
    FreeAndNil(Writer);
  end;
  AssertTrue(Bytes, Pos('0.5 G 0.5 g', Bytes) > 0);
  AssertTrue(Bytes, Pos(' re f', Bytes) > 0);
end;

procedure TTestLayout.TestExpandFields;
var
  Values: TFieldValues;
begin
  Values := Default(TFieldValues);
  Values.PatternName := 'Skirt';
  Values.Date := '2026-10-31';
  AssertEquals('Skirt, 2026-10-31', ExpandFields('{pattern.name}, {date}', Values));
  AssertEquals('empty stays as typed', '{page}', ExpandFields('{page}', Values));
  AssertEquals('unknown stays', '{other}', ExpandFields('{other}', Values));
end;

procedure TTestLayout.TestTextLines;
var
  Lines: TStringArray;
begin
  Lines := TextLines('one' + #13#10 + 'two' + #10 + 'three');
  AssertEquals(3, Length(Lines));
  AssertEquals('two', Lines[1]);
  AssertEquals('one line', 1, Length(TextLines('one')));
end;

procedure TTestLayout.TestNoteBounds;
var
  Note: TSheetNote;
  Spread: TRect2;
begin
  Note := Default(TSheetNote);
  Note.Text := 'ab' + #10 + 'abcd';
  Note.X := 10;
  Note.Y := 20;
  Note.Size := 72;
  Spread := NoteBounds(Note, Default(TFieldValues));
  AssertNear('left', 10, Spread.MinX);
  AssertNear('widest line', 10 + TextWidth('abcd', 72), Spread.MaxX);
  AssertNear('two lines', 20 + 2 * LineHeight(72), Spread.MaxY);
end;

procedure TTestLayout.TestNotesRoundTrip;
var
  Text, ErrorMessage: string;
  Other: TLayout;
begin
  FLayout.AddNote('Cut 2' + #10 + 'Press seams', 10, 20, 14);
  Text := FLayout.SaveToText;
  Other := TLayout.Create;
  try
    AssertTrue(ErrorMessage, Other.LoadFromText(Text, ErrorMessage));
    AssertEquals('Cut 2' + #10 + 'Press seams', Other.Notes[0].Text);
    AssertNear('size', 14, Other.Notes[0].Size);
    AssertEquals('same text', Text, Other.SaveToText);
  finally
    FreeAndNil(Other);
  end;
end;

procedure TTestLayout.TestBadNotesRefused;
var
  ErrorMessage: string;
begin
  AssertFalse(FLayout.LoadFromText('{"format": "layout", "version": 1, "sources": [], "sheetNotes": [{"x": 1}]}', ErrorMessage));
  AssertEquals(Format(rsLayoutList, ['sheetNotes']), ErrorMessage);
  AssertTrue(ErrorMessage, FLayout.LoadFromText('{"format": "layout", "version": 1, "sources": [], "sheetNotes": [{"text": "a", "x": 1, "y": 2}]}', ErrorMessage));
  AssertNear('default size', 12, FLayout.Notes[0].Size);
end;

procedure TTestLayout.TestNoteMakesAPageNeeded;
var
  Pages: TTilePageArray;
  Rows, Columns: integer;
begin
  WritePattern;
  Prepare;
  FLayout.PlaceNewPieces;
  FLayout.AddNote('Far away', 450, 20, 12);
  Pages := FLayout.Pages(FLayout.PlacedPieces, Rows, Columns);
  AssertTrue('the grid reaches it', Columns >= 3);
  AssertFalse('its page is printed', Pages[2].Blank);
  AssertTrue('the one between stays blank', Pages[1].Blank);
end;

procedure TTestLayout.TestNotePrintedOnItsPage;
var
  Bytes: rawbytestring;
begin
  WritePattern;
  Prepare;
  FLayout.PlaceNewPieces;
  FLayout.AddNote('Press seams', 130, 20, 12);
  Bytes := LayoutToPDF(FLayout);
  AssertEquals('once, on one page', 1, CountOf('(Press seams)', Bytes));
end;

procedure TTestLayout.TestNoteOverPieceWarns;
var
  Problems: TLayoutProblemArray;
begin
  WritePattern;
  Prepare;
  FLayout.PlaceNewPieces;
  FLayout.AddNote('Over it', 50, 50, 12);
  Problems := FLayout.Problems;
  AssertEquals(ProblemText, 1, Length(Problems));
  AssertFalse(Problems[0].Blocking);
  AssertEquals(Format(rsLayoutNoteOverlap, ['Over it', 'Front, cut 1']), Problems[0].Text);
end;

procedure TTestLayout.TestNoteAt;
var
  Values: TFieldValues;
begin
  Values := Default(TFieldValues);
  FLayout.AddNote('Long enough to hit', 10, 20, 12);
  FLayout.AddNote('Long enough to hit', 10, 20, 12);
  AssertEquals('the upper one', 1, NoteAt(FLayout.Notes, Values, Vec2(12, 22)));
  AssertEquals('clear of them', -1, NoteAt(FLayout.Notes, Values, Vec2(300, 22)));
end;

procedure TTestLayout.TestRemoveNote;
begin
  FLayout.AddNote('a', 0, 0, 12);
  FLayout.AddNote('b', 0, 0, 12);
  FLayout.RemoveNote(0);
  AssertEquals(1, Length(FLayout.Notes));
  AssertEquals('b', FLayout.Notes[0].Text);
end;

procedure TTestLayout.TestPageFieldsInNotes;
var
  Bytes: rawbytestring;
begin
  WritePattern;
  Prepare;
  FLayout.PlaceNewPieces;
  FLayout.AddNote('Page {page} of {pages}', 130, 20, 12);
  Bytes := LayoutToPDF(FLayout);
  AssertTrue('the cover counts', Pos('(Page 2 of 2)', Bytes) > 0);
end;

procedure TTestLayout.TestTitleRoundTrip;
var
  Text, ErrorMessage: string;
  Other: TLayout;
begin
  FLayout.UseDefaultTitle;
  FLayout.Title.Corner := tcTopRight;
  FLayout.Title.EveryPage := True;
  Text := FLayout.SaveToText;
  Other := TLayout.Create;
  try
    AssertTrue(ErrorMessage, Other.LoadFromText(Text, ErrorMessage));
    AssertTrue(Other.Title.Enabled);
    AssertTrue(Other.Title.Corner = tcTopRight);
    AssertTrue(Other.Title.EveryPage);
    AssertEquals(3, Length(Other.Title.Fields));
    AssertEquals('same text', Text, Other.SaveToText);
  finally
    FreeAndNil(Other);
  end;
end;

procedure TTestLayout.TestTitleOffByDefault;
begin
  WritePattern;
  Prepare;
  FLayout.PlaceNewPieces;
  AssertEquals('nothing printed', 0, Pos('Date:', LayoutToPDF(FLayout)));
  AssertEquals('nothing saved', 0, Pos('titleBlock', FLayout.SaveToText));
end;

procedure TTestLayout.TestTitleOnCover;
var
  Bytes: rawbytestring;
begin
  WritePattern;
  Prepare;
  FLayout.PlaceNewPieces;
  FLayout.UseDefaultTitle;
  FLayout.PrintDate := '2026-10-31';
  Bytes := LayoutToPDF(FLayout);
  AssertEquals('once', 1, CountOf('(Date: 2026-10-31)', Bytes));
  AssertTrue('the pattern', Pos('(Pattern: front)', Bytes) > 0);
end;

procedure TTestLayout.TestTitleLines;
var
  Values: TFieldValues;
  Lines: TStringArray;
begin
  FLayout.UseDefaultTitle;
  Insert('no.such.field', FLayout.Title.Fields, 0);
  Values := Default(TFieldValues);
  Values.PatternName := 'Skirt';
  Lines := FLayout.TitleLines(Values);
  AssertEquals('unknown left out', 3, Length(Lines));
  AssertEquals(Format(rsTitlePattern, ['Skirt']), Lines[0]);
end;

procedure TTestLayout.TestTitleEveryPage;
begin
  WritePattern;
  Prepare;
  FLayout.PlaceNewPieces;
  FLayout.UseDefaultTitle;
  FLayout.PrintDate := '2026-10-31';
  FLayout.Title.EveryPage := True;
  AssertEquals('cover and tile', 2, CountOf('(Date: 2026-10-31)', LayoutToPDF(FLayout)));
end;

procedure TTestLayout.TestTitleOnOneSheet;
begin
  WritePattern;
  Prepare;
  FLayout.PlaceNewPieces;
  FLayout.UseDefaultTitle;
  FLayout.PrintDate := '2026-10-31';
  FLayout.Output.Kind := okLarge;
  AssertEquals('once', 1, CountOf('(Date: 2026-10-31)', LayoutToPDF(FLayout)));
end;

procedure TTestLayout.TestNewLayoutGetsATitle;
var
  Document: TLayoutDocument;
begin
  WritePattern;
  Document := TLayoutDocument.Create;
  try
    Document.NewForPattern(FPatternPath);
    AssertTrue(Document.Layout.Title.Enabled);
  finally
    FreeAndNil(Document);
  end;
end;

procedure TTestLayout.TestFieldValues;
var
  Values: TFieldValues;
  Measurements: TMeasurementSet;
  Reason: string;
begin
  WritePattern;
  Measurements := TMeasurementSet.Create;
  try
    Measurements.Name := 'Bill';
    AssertTrue(Reason, Measurements.SaveToFile(ConcatPaths([FFolder, 'me.slm']), Reason));
  finally
    FreeAndNil(Measurements);
  end;
  FLayout.AddSource('front.sloper', 'me.slm', '');
  FLayout.LoadSources;
  FLayout.Name := 'Dress';
  FLayout.PrintDate := '2026-10-31';
  Values := FLayout.FieldValues('2', '5');
  AssertEquals('front', Values.PatternName);
  AssertEquals('the set''s name', 'Bill', Values.MeasurementsName);
  AssertEquals('Dress', Values.LayoutName);
  AssertEquals('2026-10-31', Values.Date);
  AssertEquals('2', Values.Page);
end;

initialization
  RegisterTest(TTestLayout);

end.
