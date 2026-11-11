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

// Page tiling: how a layout, in millimetres from its top left with y down, is
// cut into overlapping pages of paper. No drawing here.
unit Sloper.Output.Tiling;

{$mode ObjFPC}{$H+}

interface

uses
  Sloper.Core.Geometry;

type
  TTileSettings = record
    PaperWidth, PaperHeight, Margin, Overlap: double;
  end;

  // Area is the part of the layout this page prints
  TTilePage = record
    Row, Column: integer;
    Area: TRect2;
    Caption: string;
    // Nothing is on it, so it is left out of the print
    Blank: boolean;
    // The user left it out, as when reprinting one damaged sheet
    Excluded: boolean;
  end;

  TTilePageArray = array of TTilePage;

// False when the margins and overlap leave nothing to print on
function TilesAreUsable(const Settings: TTileSettings): boolean;
// Every page needed to cover the layout from (0, 0) to Extent, row by row
function TilePages(const Extent: TVec2; const Settings: TTileSettings; out RowCount, ColumnCount: integer): TTilePageArray;
// A1, A2 ... B1; rows past Z go on to AA
function TileCaption(Row, Column: integer): string;
// True when the closed polygon has any part inside Area
function PolygonTouches(const Points: TVec2Array; const Area: TRect2): boolean;

implementation

uses
  SysUtils, Math;

function TilesAreUsable(const Settings: TTileSettings): boolean;
begin
  Result := (Settings.PaperWidth - 2 * Settings.Margin - Settings.Overlap > 0) and
    (Settings.PaperHeight - 2 * Settings.Margin - Settings.Overlap > 0) and (Settings.Margin >= 0) and (Settings.Overlap >= 0);
end;

// Pages after the first each add their printable size less the overlap
function PagesFor(Extent, Printable, Overlap: double): integer;
begin
  Result := 1;
  if Extent > Printable then
    Result := 1 + Ceil((Extent - Printable - DEFAULT_TOLERANCE) / (Printable - Overlap));
end;

function TilePages(const Extent: TVec2; const Settings: TTileSettings; out RowCount, ColumnCount: integer): TTilePageArray;
var
  PrintWidth, PrintHeight: double;
  Row, Column, Index: integer;
begin
  PrintWidth := Settings.PaperWidth - 2 * Settings.Margin;
  PrintHeight := Settings.PaperHeight - 2 * Settings.Margin;
  ColumnCount := PagesFor(Extent.X, PrintWidth, Settings.Overlap);
  RowCount := PagesFor(Extent.Y, PrintHeight, Settings.Overlap);
  Result := nil;
  SetLength(Result, RowCount * ColumnCount);
  Index := 0;
  for Row := 0 to RowCount - 1 do
    for Column := 0 to ColumnCount - 1 do
    begin
      Result[Index].Row := Row;
      Result[Index].Column := Column;
      Result[Index].Area.MinX := Column * (PrintWidth - Settings.Overlap);
      Result[Index].Area.MinY := Row * (PrintHeight - Settings.Overlap);
      Result[Index].Area.MaxX := Result[Index].Area.MinX + PrintWidth;
      Result[Index].Area.MaxY := Result[Index].Area.MinY + PrintHeight;
      Result[Index].Caption := TileCaption(Row, Column);
      Inc(Index);
    end;
end;

function TileCaption(Row, Column: integer): string;
var
  Remaining: integer;
begin
  Result := '';
  Remaining := Row;
  repeat
    Result := Chr(Ord('A') + Remaining mod 26) + Result;
    Remaining := Remaining div 26 - 1;
  until Remaining < 0;
  Result := Result + IntToStr(Column + 1);
end;

function PointInRect(const Point: TVec2; const Area: TRect2): boolean;
begin
  Result := (Point.X >= Area.MinX) and (Point.X <= Area.MaxX) and (Point.Y >= Area.MinY) and (Point.Y <= Area.MaxY);
end;

function PolygonTouches(const Points: TVec2Array; const Area: TRect2): boolean;
var
  Index, Side: integer;
  Corners: array[0..3] of TVec2;
  Hit: TIntersection;
  Segment: TLine2;
begin
  for Index := 0 to High(Points) do
    if PointInRect(Points[Index], Area) then
      Exit(True);
  Corners[0] := Vec2(Area.MinX, Area.MinY);
  Corners[1] := Vec2(Area.MaxX, Area.MinY);
  Corners[2] := Vec2(Area.MaxX, Area.MaxY);
  Corners[3] := Vec2(Area.MinX, Area.MaxY);
  // The page may lie wholly inside the polygon
  if PointInPolygon(Corners[0], Points) then
    Exit(True);
  for Index := 0 to High(Points) do
  begin
    Segment := Line2(Points[Index], Points[(Index + 1) mod Length(Points)]);
    for Side := 0 to 3 do
      if IntersectLines(Segment, Line2(Corners[Side], Corners[(Side + 1) mod 4]), False, False, Hit) then
        Exit(True);
  end;
  Result := False;
end;

end.
