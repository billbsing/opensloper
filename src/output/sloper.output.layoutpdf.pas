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

// A layout as a tiled PDF: a cover page with the test square, the page map
// and a print-at-full-size reminder, then one page per tile that has any of a
// piece on it. Pieces cut on a fold print as the half drawn, with the fold's
// bracket, as on a paper pattern.
unit Sloper.Output.LayoutPDF;

{$mode ObjFPC}{$H+}

interface

uses
  Sloper.Core.TextFields, Sloper.Output.Layout;

// The PDF as bytes, whatever problems the layout has; callers check first
function LayoutToPDF(Layout: TLayout): rawbytestring;
// The size of the one sheet of large-format or projector output, for the
// page from TLayout.Pages
function OneSheetWidth(Layout: TLayout; const PageWidth: double): double;
function LargeSheetLength(Layout: TLayout; const PageHeight: double): double;
// Refuses, listing the blocking problems in ErrorMessage, or writes the file
function ExportLayoutPDF(Layout: TLayout; const FileName: string; out ErrorMessage: string): boolean;

resourcestring
  rsPDFPrintFullSize = 'Print at 100% / actual size. Do not "fit to page".';
  rsPDFCheckSquare = 'This square must measure %s. If it does not, set the printer calibration in Preferences.';
  rsPDFPages = '%d pages to print, %d blank, %d left out';
  rsPDFProjectorFit = 'Set the projector so that this square measures %s on the material.';
  rsPDFProjectorZoom = 'Show at 100%, then adjust the projector, not the viewer.';

implementation

uses
  SysUtils, Math, Classes, Sloper.Core.Geometry, Sloper.Core.Materials, Sloper.Core.Settings, Sloper.Core.Draft, Sloper.Core.Note,
  Sloper.Output.PDFWriter, Sloper.Output.Tiling, Sloper.Output.TitleBlock;

const
  TEST_SQUARE_SIDE = METRIC_TEST_SQUARE_SIDE;
  LETTER_TEST_SQUARE_SIDE = INCH_TEST_SQUARE_SIDE;
  MAP_CELL = 12;
  CAPTION_SIZE = 9;
  PIECE_LABEL_SIZE = 11;
  TITLE_SIZE = 16;
  BODY_SIZE = 10;
  CUT_LINE_WIDTH = 0.35;
  SEAM_LINE_WIDTH = 0.18;
  MARK_LINE_WIDTH = 0.25;
  SEAM_DASH = 2;
  OVERLAP_DASH = 1.5;
  DIAMOND_SIZE = 3;
  // Light enough that lines and text stay clear on it
  HATCH_SPACING = 6;
  HATCH_GRAY = 0.6;
  HALF_CIRCLE_STEPS = 16;
  PROJECTOR_CUT_WIDTH = 1.5;
  PROJECTOR_SEAM_WIDTH = 0.7;
  PROJECTOR_MARK_WIDTH = 1;
  PROJECTOR_LABEL_SIZE = 28;
  // Room for the header, when there is little or nothing below it
  MIN_PROJECTOR_WIDTH = 130;

type
  TLayoutPrinter = class
  private
    FLayout: TLayout;
    FWriter: TPDFWriter;
    FShapes: TPlacedPieceArray;
    FPages: TTilePageArray;
    FRowCount, FColumnCount: integer;
    // Where the top left of the page's area lands on the paper
    FOrigin: TVec2;
    FCutWidth, FSeamWidth, FMarkWidth, FLabelSize: double;
    // Pages in the file, and the page being drawn, for {page} and {pages}
    FPageCount, FPageNumber: integer;
    function PagePoint(const Page: TTilePage; const Point: TVec2): TVec2;
    function PagePoints(const Page: TTilePage; const Points: TVec2Array): TVec2Array;
    procedure DrawCover;
    procedure DrawMap(Top: double);
    function DrawCheckBlock(Left, Top: double): double;
    procedure DrawOneSheet;
    procedure DrawTile(const Page: TTilePage);
    procedure DrawFill(const Page: TTilePage; const Shape: TPlacedPiece);
    procedure DrawShape(const Page: TTilePage; const Shape: TPlacedPiece);
    procedure DrawDiamond(const Page: TTilePage; const Centre: TVec2);
    procedure DrawHalfCircle(const Page: TTilePage; const Centre: TVec2; Inward: double);
    procedure DrawMark(const Page: TTilePage; const Centre: TVec2; Inward: double);
    function PageValues: TFieldValues;
    procedure DrawTitle(Left, Top: double; Boxed: boolean);
    procedure DrawTitleInCorner(PageWidth, PageHeight, Inset: double);
    procedure DrawNotes(const Page: TTilePage);
    procedure DrawMarks(const Page: TTilePage);
  public
    constructor Create(ALayout: TLayout; AWriter: TPDFWriter);
    procedure Print;
  end;

constructor TLayoutPrinter.Create(ALayout: TLayout; AWriter: TPDFWriter);
begin
  FLayout := ALayout;
  FWriter := AWriter;
end;

// Layout space to the page. Calibration corrects a printer that is
// consistently a little off, so it scales everything drawn at true size.
function TLayoutPrinter.PagePoint(const Page: TTilePage; const Point: TVec2): TVec2;
begin
  Result.X := FOrigin.X + (Point.X - Page.Area.MinX) * FLayout.Calibration.X;
  Result.Y := FOrigin.Y + (Point.Y - Page.Area.MinY) * FLayout.Calibration.Y;
end;

function TLayoutPrinter.PagePoints(const Page: TTilePage; const Points: TVec2Array): TVec2Array;
var
  Index: integer;
begin
  Result := nil;
  SetLength(Result, Length(Points));
  for Index := 0 to High(Points) do
    Result[Index] := PagePoint(Page, Points[Index]);
end;

procedure TLayoutPrinter.DrawMap(Top: double);
var
  Index: integer;
  Cell: TRect2;
begin
  for Index := 0 to High(FPages) do
  begin
    Cell.MinX := COVER_MARGIN + FPages[Index].Column * MAP_CELL;
    Cell.MinY := Top + FPages[Index].Row * MAP_CELL;
    Cell.MaxX := Cell.MinX + MAP_CELL;
    Cell.MaxY := Cell.MinY + MAP_CELL;
    FWriter.Rectangle(Cell);
    if not FPages[Index].Blank then
      FWriter.Text(Cell.MinX + 2, Cell.MinY + 7, CAPTION_SIZE, FPages[Index].Caption);
    if FPages[Index].Excluded then
      FWriter.Line(Vec2(Cell.MinX, Cell.MinY), Vec2(Cell.MaxX, Cell.MaxY));
  end;
end;

// The title, the reminder and the test square, from (Left, Top). Returns
// where the block ends.
function TLayoutPrinter.DrawCheckBlock(Left, Top: double): double;
var
  Side: double;
  Square: TRect2;
  Width: string;
begin
  FWriter.Text(Left, Top + 6, TITLE_SIZE, FLayout.Name);
  if FLayout.Output.Kind = okProjector then
    FWriter.Text(Left, Top + 15, BODY_SIZE, rsPDFProjectorZoom)
  else
    FWriter.Text(Left, Top + 15, BODY_SIZE, rsPDFPrintFullSize);
  if FLayout.Output.Paper = 'Letter' then
  begin
    Side := LETTER_TEST_SQUARE_SIDE;
    Width := '4 in';
  end
  else
  begin
    Side := TEST_SQUARE_SIDE;
    Width := '10 cm';
  end;
  if FLayout.Output.Kind = okProjector then
    FWriter.Text(Left, Top + 22, BODY_SIZE, Format(rsPDFProjectorFit, [Width]))
  else
    FWriter.Text(Left, Top + 22, BODY_SIZE, Format(rsPDFCheckSquare, [Width]));
  Square.MinX := Left;
  Square.MinY := Top + CHECK_SQUARE_TOP;
  Square.MaxX := Square.MinX + Side * FLayout.Calibration.X;
  Square.MaxY := Square.MinY + Side * FLayout.Calibration.Y;
  FWriter.Rectangle(Square);
  Result := Square.MaxY;
end;

procedure TLayoutPrinter.DrawCover;
var
  Bottom: double;
  Printed, Blank, Excluded: integer;
  Page: TTilePage;
begin
  FWriter.BeginPage(FLayout.Output.Tiles.PaperWidth, FLayout.Output.Tiles.PaperHeight);
  FWriter.SetLineWidth(MARK_LINE_WIDTH);
  Bottom := DrawCheckBlock(COVER_MARGIN, COVER_MARGIN);
  Printed := 0;
  Blank := 0;
  Excluded := 0;
  for Page in FPages do
    if Page.Blank then
      Inc(Blank)
    else if Page.Excluded then
      Inc(Excluded)
    else
      Inc(Printed);
  FWriter.Text(COVER_MARGIN, Bottom + 10, BODY_SIZE, Format(rsPDFPages, [Printed, Blank, Excluded]));
  DrawMap(Bottom + 15);
  DrawTitleInCorner(FLayout.Output.Tiles.PaperWidth, FLayout.Output.Tiles.PaperHeight, COVER_MARGIN);
end;

// One sheet: the check block across the top, then the layout, as long as it
// needs to be. For a projector it is light on dark, and the lines are thick
// enough to see on material.
procedure TLayoutPrinter.DrawOneSheet;
var
  Margin, Bottom, SheetWidth, SheetLength: double;
  Page: TTilePage;
  Printable, Whole: TRect2;
  Shape: TPlacedPiece;
begin
  Margin := FLayout.Output.Tiles.Margin;
  Page := FPages[0];
  Bottom := Margin + LARGE_HEADER_HEIGHT;
  SheetWidth := OneSheetWidth(FLayout, Page.Area.MaxX - Page.Area.MinX);
  SheetLength := LargeSheetLength(FLayout, Page.Area.MaxY - Page.Area.MinY);
  FWriter.BeginPage(SheetWidth, SheetLength);
  if FLayout.Output.Kind = okProjector then
  begin
    Whole := Default(TRect2);
    Whole.MaxX := SheetWidth;
    Whole.MaxY := SheetLength;
    FWriter.SetGray(0);
    FWriter.FillRectangle(Whole);
    FWriter.SetGray(1);
  end;
  FWriter.SetLineWidth(FMarkWidth);
  DrawCheckBlock(Margin, Margin);
  // Beside the test square, clear of the pieces
  DrawTitle(Margin + LETTER_TEST_SQUARE_SIDE * FLayout.Calibration.X + TITLE_GAP, Margin + CHECK_SQUARE_TOP, False);
  FOrigin := Vec2(Margin, Bottom);
  Printable.MinX := Margin;
  Printable.MinY := Bottom;
  Printable.MaxX := SheetWidth - Margin;
  Printable.MaxY := SheetLength - Margin;
  FWriter.PushClip(Printable);
  for Shape in FShapes do
    DrawShape(Page, Shape);
  DrawNotes(Page);
  FWriter.PopClip;
end;

function TLayoutPrinter.PageValues: TFieldValues;
begin
  Result := FLayout.FieldValues(IntToStr(FPageNumber), IntToStr(FPageCount));
end;

// Boxed clears what is under it, for a corner of a tile
procedure TLayoutPrinter.DrawTitle(Left, Top: double; Boxed: boolean);
var
  Lines: TStringArray;
  BoxWidth, BoxHeight, Baseline: double;
  Index: integer;
  Box: TRect2;
begin
  if not TitleBlockSize(FLayout, PageValues, BoxWidth, BoxHeight) then
    Exit;
  Lines := FLayout.TitleLines(PageValues);
  Box.MinX := Left;
  Box.MinY := Top;
  Box.MaxX := Left + BoxWidth;
  Box.MaxY := Top + BoxHeight;
  if Boxed then
  begin
    FWriter.SetGray(1);
    FWriter.FillRectangle(Box);
    FWriter.SetGray(0);
  end;
  FWriter.SetDash(0);
  FWriter.SetLineWidth(MARK_LINE_WIDTH);
  FWriter.Rectangle(Box);
  Baseline := Top + TITLE_PADDING;
  for Index := 0 to High(Lines) do
  begin
    Baseline := Baseline + LineHeight(TITLE_TEXT_SIZE);
    FWriter.Text(Left + TITLE_PADDING, Baseline, TITLE_TEXT_SIZE, Lines[Index]);
  end;
end;

procedure TLayoutPrinter.DrawTitleInCorner(PageWidth, PageHeight, Inset: double);
var
  BoxWidth, BoxHeight: double;
  Spot: TVec2;
begin
  if not TitleBlockSize(FLayout, PageValues, BoxWidth, BoxHeight) then
    Exit;
  Spot := TitleCornerSpot(FLayout.Title.Corner, PageWidth, PageHeight, Inset, BoxWidth, BoxHeight);
  DrawTitle(Spot.X, Spot.Y, True);
end;

// A white box goes under the text in the paper's colour, which on a
// projector is black; a callout's leader is drawn as the marks are
procedure TLayoutPrinter.DrawNotes(const Page: TTilePage);
var
  Note: TSheetNote;
  Spot, Start: TVec2;
  Lines: TStringArray;
  Index: integer;
  Spread, Frame, Area: TRect2;
  Stroke: TLine2;
  Ink: double;
begin
  Ink := 0;
  if FLayout.Output.Kind = okProjector then
    Ink := 1;
  for Note in PrintedNotes(FLayout, FShapes) do
  begin
    Spread := NoteFrameBounds(Note, PageValues);
    Frame := Spread;
    if Note.Leader <> nlNone then
    begin
      Spread.MinX := Min(Spread.MinX, Note.Tip.X);
      Spread.MinY := Min(Spread.MinY, Note.Tip.Y);
      Spread.MaxX := Max(Spread.MaxX, Note.Tip.X);
      Spread.MaxY := Max(Spread.MaxY, Note.Tip.Y);
    end;
    if (Spread.MaxX < Page.Area.MinX) or (Spread.MinX > Page.Area.MaxX) or (Spread.MaxY < Page.Area.MinY) or (Spread.MinY > Page.Area.MaxY) then
      Continue;
    FWriter.SetGray(Ink);
    if (Note.Leader <> nlNone) and LeaderStart(Frame, Note.Tip, Start) then
    begin
      FWriter.SetLineWidth(FMarkWidth);
      for Stroke in LeaderStrokes(Start, Note.Tip, Note.Leader) do
        FWriter.Line(PagePoint(Page, Stroke.P1), PagePoint(Page, Stroke.P2));
      if Note.Leader = nlDot then
        FWriter.FillPolygon(PagePoints(Page, LeaderDot(Note.Tip)));
    end;
    if Note.Boxed then
    begin
      Spot := PagePoint(Page, Vec2(Frame.MinX, Frame.MinY));
      Area.MinX := Spot.X;
      Area.MinY := Spot.Y;
      Spot := PagePoint(Page, Vec2(Frame.MaxX, Frame.MaxY));
      Area.MaxX := Spot.X;
      Area.MaxY := Spot.Y;
      FWriter.SetGray(1 - Ink);
      FWriter.FillRectangle(Area);
      FWriter.SetGray(Ink);
    end;
    Lines := TextLines(ExpandFields(Note.Text, PageValues));
    for Index := 0 to High(Lines) do
    begin
      Spot := PagePoint(Page, Vec2(NoteLineLeft(Note, PageValues, Lines[Index]), Note.Y + (Index + 1) * LineHeight(Note.Size)));
      FWriter.Text(Spot.X, Spot.Y, Note.Size, Lines[Index], Note.Style);
    end;
  end;
end;

// Under the lines. A piece with no material stays unfilled, and on a projector
// nothing is filled, as its output is dark.
procedure TLayoutPrinter.DrawFill(const Page: TTilePage; const Shape: TPlacedPiece);
var
  Tint: TMaterialColor;
  Stroke: TLine2;
begin
  if (FLayout.Output.Kind = okProjector) or not Shape.Look.Filled then
    Exit;
  case FLayout.Output.Fill of
    lfTint:
    begin
      Tint := MaterialTint(Shape.Look.Color);
      FWriter.SetColor(Tint.Red / 255, Tint.Green / 255, Tint.Blue / 255);
      FWriter.FillPolygon(PagePoints(Page, Shape.CutLine));
      FWriter.SetGray(0);
    end;
    lfHatch:
    begin
      FWriter.SetDash(0);
      FWriter.SetLineWidth(FMarkWidth);
      FWriter.SetGray(HATCH_GRAY);
      for Stroke in HatchLines(Shape.CutLine, HATCH_SPACING, Shape.Look.HatchAngle) do
        FWriter.Line(PagePoint(Page, Stroke.P1), PagePoint(Page, Stroke.P2));
      FWriter.SetGray(0);
    end;
  end;
end;

// One of the red, green and blue parts of #rrggbb, from 0 to 1
function HexPart(const Color: string; Part: integer): double;
begin
  Result := StrToIntDef('$' + Copy(Color, 2 + 2 * Part, 2), 0) / 255;
end;

procedure TLayoutPrinter.DrawShape(const Page: TTilePage; const Shape: TPlacedPiece);
var
  Line: TPlacedLine;
  Mark: TLine2;
  Spot: TVec2;
begin
  DrawFill(Page, Shape);
  FWriter.SetDash(0);
  FWriter.SetLineWidth(FCutWidth);
  FWriter.Polyline(PagePoints(Page, Shape.CutLine), True);
  if Length(Shape.SeamLine) > 0 then
  begin
    FWriter.SetDash(SEAM_DASH);
    FWriter.SetLineWidth(FSeamWidth);
    FWriter.Polyline(PagePoints(Page, Shape.SeamLine), True);
  end;
  FWriter.SetDash(0);
  FWriter.SetLineWidth(FMarkWidth);
  for Mark in Shape.Marks do
    FWriter.Line(PagePoint(Page, Mark.P1), PagePoint(Page, Mark.P2));
  for Line in Shape.Lines do
  begin
    // An output profile's own look, or the built-in one
    if Line.Style.Custom then
    begin
      FWriter.SetDashPattern(Line.Style.Dashes);
      FWriter.SetLineWidth(Line.Style.Width);
      FWriter.SetColor(HexPart(Line.Style.Color, 0), HexPart(Line.Style.Color, 1), HexPart(Line.Style.Color, 2));
    end
    else
    begin
      FWriter.SetDashPattern(ROLE_DASHES[Line.Role]);
      if Line.Role = erCut then
        FWriter.SetLineWidth(FCutWidth)
      else
        FWriter.SetLineWidth(FMarkWidth);
    end;
    FWriter.Polyline(PagePoints(Page, Line.Points), False);
    if Line.Style.Custom then
      FWriter.SetGray(0);
  end;
  FWriter.SetDash(0);
  if Shape.ShowLabel then
  begin
    Spot := PagePoint(Page, Shape.LabelAt);
    FWriter.Text(Spot.X, Spot.Y, FLabelSize, Shape.Caption);
  end;
end;

procedure TLayoutPrinter.DrawDiamond(const Page: TTilePage; const Centre: TVec2);
var
  Spot: TVec2;
  Points: TVec2Array;
begin
  Spot := PagePoint(Page, Centre);
  Points := nil;
  SetLength(Points, 4);
  Points[0] := Spot + Vec2(0, -DIAMOND_SIZE);
  Points[1] := Spot + Vec2(DIAMOND_SIZE, 0);
  Points[2] := Spot + Vec2(0, DIAMOND_SIZE);
  Points[3] := Spot + Vec2(-DIAMOND_SIZE, 0);
  FWriter.Polyline(Points, True);
end;

// Each page prints the half on its own side of the overlap's middle, so that
// with one sheet over the other the two halves make a circle
procedure TLayoutPrinter.DrawHalfCircle(const Page: TTilePage; const Centre: TVec2; Inward: double);
var
  Spot: TVec2;
  Points: TVec2Array;
  Index: integer;
begin
  Spot := PagePoint(Page, Centre);
  Points := nil;
  SetLength(Points, HALF_CIRCLE_STEPS + 1);
  for Index := 0 to HALF_CIRCLE_STEPS do
    Points[Index] := PolarPoint(Spot, DIAMOND_SIZE, Inward - 90 + 180 * Index / HALF_CIRCLE_STEPS);
  FWriter.Polyline(Points, True);
end;

procedure TLayoutPrinter.DrawMark(const Page: TTilePage; const Centre: TVec2; Inward: double);
begin
  if FLayout.Output.Marks = lkHalfCircle then
    DrawHalfCircle(Page, Centre, Inward)
  else
    DrawDiamond(Page, Centre);
end;

// In the middle of each overlap, so neighbouring pages print the same marks
// and line up on them. Inward is the way into the page, as an angle seen on
// the page: 270 points down from the top edge.
procedure TLayoutPrinter.DrawMarks(const Page: TTilePage);
var
  Overlap, MiddleX, MiddleY: double;
begin
  if FLayout.Output.Marks = lkNone then
    Exit;
  Overlap := FLayout.Output.Tiles.Overlap;
  MiddleX := (Page.Area.MinX + Page.Area.MaxX) / 2;
  MiddleY := (Page.Area.MinY + Page.Area.MaxY) / 2;
  FWriter.SetDash(0);
  FWriter.SetLineWidth(MARK_LINE_WIDTH);
  if Page.Column > 0 then
    DrawMark(Page, Vec2(Page.Area.MinX + Overlap / 2, MiddleY), 0);
  if Page.Column < FColumnCount - 1 then
    DrawMark(Page, Vec2(Page.Area.MaxX - Overlap / 2, MiddleY), 180);
  if Page.Row > 0 then
    DrawMark(Page, Vec2(MiddleX, Page.Area.MinY + Overlap / 2), 270);
  if Page.Row < FRowCount - 1 then
    DrawMark(Page, Vec2(MiddleX, Page.Area.MaxY - Overlap / 2), 90);
end;

procedure TLayoutPrinter.DrawTile(const Page: TTilePage);
var
  Tiles: TTileSettings;
  Printable: TRect2;
  Shape: TPlacedPiece;
begin
  Tiles := FLayout.Output.Tiles;
  FWriter.BeginPage(Tiles.PaperWidth, Tiles.PaperHeight);
  Printable.MinX := Tiles.Margin;
  Printable.MinY := Tiles.Margin;
  Printable.MaxX := Tiles.PaperWidth - Tiles.Margin;
  Printable.MaxY := Tiles.PaperHeight - Tiles.Margin;
  FWriter.SetDash(OVERLAP_DASH);
  FWriter.SetLineWidth(SEAM_LINE_WIDTH);
  FWriter.Rectangle(Printable);
  FWriter.SetDash(0);
  FWriter.Text(Tiles.Margin + 1, Tiles.Margin + 4, CAPTION_SIZE, Page.Caption);
  FWriter.PushClip(Printable);
  for Shape in FShapes do
    if PolygonTouches(Shape.CutLine, Page.Area) then
      DrawShape(Page, Shape);
  DrawMarks(Page);
  DrawNotes(Page);
  FWriter.PopClip;
  if FLayout.Title.EveryPage then
    DrawTitleInCorner(Tiles.PaperWidth, Tiles.PaperHeight, Tiles.Margin + TITLE_PADDING);
end;

procedure TLayoutPrinter.Print;
var
  Index: integer;
begin
  FShapes := FLayout.PlacedPieces;
  FPages := FLayout.Pages(FShapes, FRowCount, FColumnCount);
  FPageCount := 1;
  FPageNumber := 1;
  FCutWidth := CUT_LINE_WIDTH;
  FSeamWidth := SEAM_LINE_WIDTH;
  FMarkWidth := MARK_LINE_WIDTH;
  FLabelSize := PIECE_LABEL_SIZE;
  if FLayout.Output.Kind = okProjector then
  begin
    FCutWidth := PROJECTOR_CUT_WIDTH;
    FSeamWidth := PROJECTOR_SEAM_WIDTH;
    FMarkWidth := PROJECTOR_MARK_WIDTH;
    FLabelSize := PROJECTOR_LABEL_SIZE;
  end;
  if FLayout.Output.Kind <> okTiled then
  begin
    DrawOneSheet;
    Exit;
  end;
  FOrigin := Vec2(FLayout.Output.Tiles.Margin, FLayout.Output.Tiles.Margin);
  for Index := 0 to High(FPages) do
    if not FPages[Index].Blank and not FPages[Index].Excluded then
      Inc(FPageCount);
  DrawCover;
  for Index := 0 to High(FPages) do
    if not FPages[Index].Blank and not FPages[Index].Excluded then
    begin
      Inc(FPageNumber);
      DrawTile(FPages[Index]);
    end;
end;

function OneSheetWidth(Layout: TLayout; const PageWidth: double): double;
begin
  if Layout.Output.Kind = okLarge then
    Result := Layout.Output.RollWidth
  else if Layout.Output.Kind = okMaterial then
    Result := Layout.Output.MaterialWidth + 2 * Layout.Output.Tiles.Margin
  else
    Result := Max(MIN_PROJECTOR_WIDTH, 2 * Layout.Output.Tiles.Margin + PageWidth * Layout.Calibration.X);
end;

function LargeSheetLength(Layout: TLayout; const PageHeight: double): double;
begin
  Result := 2 * Layout.Output.Tiles.Margin + LARGE_HEADER_HEIGHT + PageHeight * Layout.Calibration.Y;
end;

function LayoutToPDF(Layout: TLayout): rawbytestring;
var
  Writer: TPDFWriter;
  Printer: TLayoutPrinter;
begin
  Writer := nil;
  Printer := nil;
  try
    Writer := TPDFWriter.Create;
    Printer := TLayoutPrinter.Create(Layout, Writer);
    Printer.Print;
    Result := Writer.Finish;
  finally
    FreeAndNil(Printer);
    FreeAndNil(Writer);
  end;
end;

function ExportLayoutPDF(Layout: TLayout; const FileName: string; out ErrorMessage: string): boolean;
begin
  ErrorMessage := Layout.Refusal;
  Result := (ErrorMessage = '') and WriteBytesToFile(FileName, LayoutToPDF(Layout), ErrorMessage);
end;

end.
