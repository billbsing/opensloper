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
  Sloper.Output.Layout;

// The PDF as bytes, whatever problems the layout has; callers check first
function LayoutToPDF(Layout: TLayout): rawbytestring;
// How long the large-format sheet comes out for pages from TLayout.Pages
// (one page, in that kind of output)
function LargeSheetLength(Layout: TLayout; const PageHeight: double): double;
// Refuses, listing the blocking problems in ErrorMessage, or writes the file
function ExportLayoutPDF(Layout: TLayout; const FileName: string; out ErrorMessage: string): boolean;

resourcestring
  rsPDFPrintFullSize = 'Print at 100% / actual size. Do not "fit to page".';
  rsPDFCheckSquare = 'This square must measure %s. If it does not, set the calibration factors.';
  rsPDFPages = '%d pages to print, %d blank, %d left out';
  rsPDFRefused = 'The layout cannot be exported:';

implementation

uses
  SysUtils, Math, Classes, Sloper.Core.Geometry, Sloper.Output.PDFWriter, Sloper.Output.Tiling;

const
  CoverMargin = 15;
  TestSquareSide = 100;
  LetterTestSquareSide = 101.6;
  MapCell = 12;
  CaptionSize = 9;
  PieceLabelSize = 11;
  TitleSize = 16;
  BodySize = 10;
  CutLineWidth = 0.35;
  SeamLineWidth = 0.18;
  MarkLineWidth = 0.25;
  SeamDash = 2;
  OverlapDash = 1.5;
  DiamondSize = 3;
  // Room for the title, reminder and test square above a large sheet
  LargeHeaderHeight = 140;

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
    function PagePoint(const Page: TTilePage; const P: TVec2): TVec2;
    function PagePoints(const Page: TTilePage; const Points: TVec2Array): TVec2Array;
    procedure DrawCover;
    procedure DrawMap(Top: double);
    function DrawCheckBlock(Left, Top: double): double;
    procedure DrawLarge;
    procedure DrawTile(const Page: TTilePage);
    procedure DrawShape(const Page: TTilePage; const Shape: TPlacedPiece);
    procedure DrawDiamond(const Page: TTilePage; const Centre: TVec2);
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
function TLayoutPrinter.PagePoint(const Page: TTilePage; const P: TVec2): TVec2;
begin
  Result.X := FOrigin.X + (P.X - Page.Area.MinX) * FLayout.Output.CalibrationX;
  Result.Y := FOrigin.Y + (P.Y - Page.Area.MinY) * FLayout.Output.CalibrationY;
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
    Cell.MinX := CoverMargin + FPages[Index].Column * MapCell;
    Cell.MinY := Top + FPages[Index].Row * MapCell;
    Cell.MaxX := Cell.MinX + MapCell;
    Cell.MaxY := Cell.MinY + MapCell;
    FWriter.Rectangle(Cell);
    if not FPages[Index].Blank then
      FWriter.Text(Cell.MinX + 2, Cell.MinY + 7, CaptionSize, FPages[Index].Caption);
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
  FWriter.Text(Left, Top + 6, TitleSize, FLayout.Name);
  FWriter.Text(Left, Top + 15, BodySize, rsPDFPrintFullSize);
  if FLayout.Output.Paper = 'Letter' then
  begin
    Side := LetterTestSquareSide;
    Width := '4 in';
  end
  else
  begin
    Side := TestSquareSide;
    Width := '10 cm';
  end;
  FWriter.Text(Left, Top + 22, BodySize, Format(rsPDFCheckSquare, [Width]));
  Square.MinX := Left;
  Square.MinY := Top + 27;
  Square.MaxX := Square.MinX + Side * FLayout.Output.CalibrationX;
  Square.MaxY := Square.MinY + Side * FLayout.Output.CalibrationY;
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
  FWriter.SetLineWidth(MarkLineWidth);
  Bottom := DrawCheckBlock(CoverMargin, CoverMargin);
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
  FWriter.Text(CoverMargin, Bottom + 10, BodySize, Format(rsPDFPages, [Printed, Blank, Excluded]));
  DrawMap(Bottom + 15);
end;

// One sheet: the check block across the top, then the layout, as long as it
// needs to be
procedure TLayoutPrinter.DrawLarge;
var
  Margin, Bottom: double;
  Page: TTilePage;
  Printable: TRect2;
  Shape: TPlacedPiece;
begin
  Margin := FLayout.Output.Tiles.Margin;
  Page := FPages[0];
  Bottom := Margin + LargeHeaderHeight;
  FWriter.BeginPage(FLayout.Output.RollWidth, LargeSheetLength(FLayout, Page.Area.MaxY - Page.Area.MinY));
  FWriter.SetLineWidth(MarkLineWidth);
  DrawCheckBlock(Margin, Margin);
  FOrigin := Vec2(Margin, Bottom);
  Printable.MinX := Margin;
  Printable.MinY := Bottom;
  Printable.MaxX := FLayout.Output.RollWidth - Margin;
  Printable.MaxY := LargeSheetLength(FLayout, Page.Area.MaxY - Page.Area.MinY) - Margin;
  FWriter.PushClip(Printable);
  for Shape in FShapes do
    DrawShape(Page, Shape);
  FWriter.PopClip;
end;

procedure TLayoutPrinter.DrawShape(const Page: TTilePage; const Shape: TPlacedPiece);
var
  Mark: TLine2;
  Spot: TVec2;
begin
  FWriter.SetDash(0);
  FWriter.SetLineWidth(CutLineWidth);
  FWriter.Polyline(PagePoints(Page, Shape.CutLine), True);
  FWriter.SetDash(SeamDash);
  FWriter.SetLineWidth(SeamLineWidth);
  FWriter.Polyline(PagePoints(Page, Shape.SeamLine), True);
  FWriter.SetDash(0);
  FWriter.SetLineWidth(MarkLineWidth);
  for Mark in Shape.Marks do
    FWriter.Line(PagePoint(Page, Mark.P1), PagePoint(Page, Mark.P2));
  Spot := PagePoint(Page, Shape.LabelAt);
  FWriter.Text(Spot.X, Spot.Y, PieceLabelSize, Shape.Caption);
end;

procedure TLayoutPrinter.DrawDiamond(const Page: TTilePage; const Centre: TVec2);
var
  Spot: TVec2;
  Points: TVec2Array;
begin
  Spot := PagePoint(Page, Centre);
  Points := nil;
  SetLength(Points, 4);
  Points[0] := Spot + Vec2(0, -DiamondSize);
  Points[1] := Spot + Vec2(DiamondSize, 0);
  Points[2] := Spot + Vec2(0, DiamondSize);
  Points[3] := Spot + Vec2(-DiamondSize, 0);
  FWriter.Polyline(Points, True);
end;

// In the middle of each overlap, so neighbouring pages print the same marks
// and line up on them
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
  FWriter.SetLineWidth(MarkLineWidth);
  if Page.Column > 0 then
    DrawDiamond(Page, Vec2(Page.Area.MinX + Overlap / 2, MiddleY));
  if Page.Column < FColumnCount - 1 then
    DrawDiamond(Page, Vec2(Page.Area.MaxX - Overlap / 2, MiddleY));
  if Page.Row > 0 then
    DrawDiamond(Page, Vec2(MiddleX, Page.Area.MinY + Overlap / 2));
  if Page.Row < FRowCount - 1 then
    DrawDiamond(Page, Vec2(MiddleX, Page.Area.MaxY - Overlap / 2));
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
  FWriter.SetDash(OverlapDash);
  FWriter.SetLineWidth(SeamLineWidth);
  FWriter.Rectangle(Printable);
  FWriter.SetDash(0);
  FWriter.Text(Tiles.Margin + 1, Tiles.Margin + 4, CaptionSize, Page.Caption);
  FWriter.PushClip(Printable);
  for Shape in FShapes do
    if PolygonTouches(Shape.CutLine, Page.Area) then
      DrawShape(Page, Shape);
  DrawMarks(Page);
  FWriter.PopClip;
end;

procedure TLayoutPrinter.Print;
var
  Index: integer;
begin
  FShapes := FLayout.PlacedPieces;
  FPages := FLayout.Pages(FShapes, FRowCount, FColumnCount);
  if FLayout.Output.Kind = okLarge then
  begin
    DrawLarge;
    Exit;
  end;
  FOrigin := Vec2(FLayout.Output.Tiles.Margin, FLayout.Output.Tiles.Margin);
  DrawCover;
  for Index := 0 to High(FPages) do
    if not FPages[Index].Blank and not FPages[Index].Excluded then
      DrawTile(FPages[Index]);
end;

function LargeSheetLength(Layout: TLayout; const PageHeight: double): double;
begin
  Result := 2 * Layout.Output.Tiles.Margin + LargeHeaderHeight + PageHeight * Layout.Output.CalibrationY;
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
var
  Problem: TLayoutProblem;
  Bytes: rawbytestring;
  Stream: TFileStream;
begin
  ErrorMessage := '';
  for Problem in Layout.Problems do
    if Problem.Blocking then
      ErrorMessage := ErrorMessage + LineEnding + '  ' + Problem.Text;
  if ErrorMessage <> '' then
  begin
    ErrorMessage := rsPDFRefused + ErrorMessage;
    Exit(False);
  end;
  Bytes := LayoutToPDF(Layout);
  try
    Stream := TFileStream.Create(FileName, fmCreate);
    try
      Stream.WriteBuffer(Bytes[1], Length(Bytes));
    finally
      FreeAndNil(Stream);
    end;
    Result := True;
  except
    on Failure: EStreamError do
    begin
      ErrorMessage := Failure.Message;
      Result := False;
    end;
  end;
end;

end.
