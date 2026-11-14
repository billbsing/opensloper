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

// Where the information block (the title block in the files) goes: its size,
// its place in a page corner, and where the publish preview shows it. The PDF
// and the preview both use it, so the preview shows the block where it
// prints. Kept free of the LCL so it can be unit-tested.
unit Sloper.Output.TitleBlock;

{$mode ObjFPC}{$H+}

interface

uses
  Sloper.Core.Geometry, Sloper.Core.TextFields, Sloper.Output.Layout, Sloper.Output.Tiling;

const
  // In points
  TITLE_TEXT_SIZE = 9;
  // Around the lines, in mm
  TITLE_PADDING = 2;
  // Between the test square and the block on one sheet, in mm
  TITLE_GAP = 10;
  // The cover's edges, in mm
  COVER_MARGIN = 15;
  // The test square's top, below the layout's name, in mm
  CHECK_SQUARE_TOP = 27;
  // Room for the title, reminder and test square above a large sheet, in mm
  LARGE_HEADER_HEIGHT = 140;
  // Between the cover and the first column of tiles in the preview, in mm
  PREVIEW_COVER_GAP = 20;

type
  TRect2Array = array of TRect2;

// The block's width and height in mm; False when it is off or has no lines
function TitleBlockSize(Layout: TLayout; const Values: TFieldValues; out Width, Height: double): boolean;
// The block's top left in a page's corner, Inset from its edges
function TitleCornerSpot(Corner: TTitleCorner; PageWidth, PageHeight, Inset, Width, Height: double): TVec2;
// Tiled output: the cover's printable area in layout space, left of the
// first column, the size of a tile's
function PreviewCover(Layout: TLayout; const Pages: TTilePageArray): TRect2;
// Where the block prints, in layout space: on the cover and every printed
// tile when tiled, above the sheet beside the test square otherwise. Empty
// when it is off.
function PreviewTitleBoxes(Layout: TLayout; const Pages: TTilePageArray; const Values: TFieldValues): TRect2Array;

implementation

uses
  SysUtils, Math, Sloper.Core.Settings;

function TitleBlockSize(Layout: TLayout; const Values: TFieldValues; out Width, Height: double): boolean;
var
  Lines: TStringArray;
  Line: string;
begin
  Width := 0;
  Height := 0;
  if not Layout.Title.Enabled then
    Exit(False);
  Lines := Layout.TitleLines(Values);
  if Length(Lines) = 0 then
    Exit(False);
  for Line in Lines do
    Width := Max(Width, TextWidth(Line, TITLE_TEXT_SIZE));
  Width := Width + 2 * TITLE_PADDING;
  Height := Length(Lines) * LineHeight(TITLE_TEXT_SIZE) + 2 * TITLE_PADDING;
  Result := True;
end;

function TitleCornerSpot(Corner: TTitleCorner; PageWidth, PageHeight, Inset, Width, Height: double): TVec2;
begin
  case Corner of
    tcBottomLeft: Result := Vec2(Inset, PageHeight - Inset - Height);
    tcTopRight: Result := Vec2(PageWidth - Inset - Width, Inset);
    else
      Result := Vec2(PageWidth - Inset - Width, PageHeight - Inset - Height);
  end;
end;

function PreviewCover(Layout: TLayout; const Pages: TTilePageArray): TRect2;
var
  Tiles: TTileSettings;
  Page: TTilePage;
  Left, Top: double;
begin
  Tiles := Layout.Output.Tiles;
  Left := 0;
  Top := 0;
  if Length(Pages) > 0 then
  begin
    Left := Pages[0].Area.MinX;
    Top := Pages[0].Area.MinY;
  end;
  for Page in Pages do
  begin
    Left := Min(Left, Page.Area.MinX);
    Top := Min(Top, Page.Area.MinY);
  end;
  Result.MaxX := Left - PREVIEW_COVER_GAP;
  Result.MinX := Result.MaxX - (Tiles.PaperWidth - 2 * Tiles.Margin);
  Result.MinY := Top;
  Result.MaxY := Top + Tiles.PaperHeight - 2 * Tiles.Margin;
end;

function PreviewTitleBoxes(Layout: TLayout; const Pages: TTilePageArray; const Values: TFieldValues): TRect2Array;
var
  Tiles: TTileSettings;
  Width, Height: double;
  Page: TTilePage;

// Spot is on the paper, whose printable area is Area
  procedure AddBox(const Area: TRect2; const Spot: TVec2);
  var
    Box: TRect2;
  begin
    Box.MinX := Area.MinX + Spot.X - Tiles.Margin;
    Box.MinY := Area.MinY + Spot.Y - Tiles.Margin;
    Box.MaxX := Box.MinX + Width;
    Box.MaxY := Box.MinY + Height;
    Insert(Box, Result, Length(Result));
  end;

begin
  Result := nil;
  if not TitleBlockSize(Layout, Values, Width, Height) then
    Exit;
  Tiles := Layout.Output.Tiles;
  if Layout.Output.Kind <> okTiled then
  begin
    if Length(Pages) = 0 then
      Exit;
    // The header is above the sheet's area; the test square is on the paper
    // at its calibrated size
    AddBox(Pages[0].Area, Vec2(Tiles.Margin + INCH_TEST_SQUARE_SIDE * Layout.Calibration.X + TITLE_GAP,
      Tiles.Margin + CHECK_SQUARE_TOP - LARGE_HEADER_HEIGHT));
    Exit;
  end;
  AddBox(PreviewCover(Layout, Pages), TitleCornerSpot(Layout.Title.Corner, Tiles.PaperWidth, Tiles.PaperHeight, COVER_MARGIN, Width, Height));
  if not Layout.Title.EveryPage then
    Exit;
  for Page in Pages do
    if not Page.Blank and not Page.Excluded then
      AddBox(Page.Area, TitleCornerSpot(Layout.Title.Corner, Tiles.PaperWidth, Tiles.PaperHeight, Tiles.Margin + TITLE_PADDING, Width, Height));
end;

end.
