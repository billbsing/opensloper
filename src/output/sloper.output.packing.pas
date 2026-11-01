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

// Pack Pieces: arranges a layout's pieces by their bounding boxes, tallest
// first, each as near the top left as it fits. Only placements change, and the
// same input gives the same result. See the design document.
unit Sloper.Output.Packing;

{$mode ObjFPC}{$H+}

interface

uses
  Sloper.Output.Layout;

const
  PackGap = 10;
  // The window's drag grid, so packed pieces can be lined up by hand
  PackGrid = 0.5;

type
  TPackResult = record
    // Whether the pieces moved; otherwise Reason says why not
    Done: boolean;
    Reason: string;
    Count: integer;
    // Pieces too wide for the sheet either way round, left where they were
    LeftOut: integer;
    // Pages for tiled output
    Pages: integer;
  end;

// Places any new copies first. Failing pieces stay in the tray.
function PackLayout(Layout: TLayout): TPackResult;

resourcestring
  rsPackProjector = 'Pieces cannot be packed for a projector, as the layout has no fabric width';
  rsPackNoPrintArea = 'The margin and overlap leave nothing to print on';
  rsPackNothing = 'There is nothing to pack';
  rsPackNoBetter = 'Packing would not improve this arrangement, so nothing moved';

implementation

uses
  SysUtils, Math, Sloper.Core.Geometry, Sloper.Output.Tiling;

const
  // Column counts tried above the fewest that fit the widest piece
  ExtraColumns = 12;
  CloseEnough = 1e-6;

type
  TPackItem = record
    Placement: integer;
    Width, Height: double;
  end;

  TPackItemArray = array of TPackItem;

  TPackSpot = record
    Placement: integer;
    X, Y: double;
    Turned: boolean;
  end;

  TPackSpotArray = array of TPackSpot;

  TPackBox = record
    MinX, MinY, MaxX, MaxY: double;
  end;

  TPackBoxArray = array of TPackBox;
  TDoubleArray = array of double;

// Longest side first, then file order, so ties always fall the same way
function ComesFirst(const A, B: TPackItem): boolean;
begin
  if Max(A.Width, A.Height) <> Max(B.Width, B.Height) then
    Exit(Max(A.Width, A.Height) > Max(B.Width, B.Height));
  Result := A.Placement < B.Placement;
end;

function ItemsFrom(Layout: TLayout): TPackItemArray;
var
  Shape: TPlacedPiece;
  Item: TPackItem;
  Place: integer;
begin
  Result := nil;
  for Shape in Layout.PlacedPieces do
  begin
    Item.Placement := Shape.Placement;
    Item.Width := Shape.Bounds.MaxX - Shape.Bounds.MinX;
    Item.Height := Shape.Bounds.MaxY - Shape.Bounds.MinY;
    Place := Length(Result);
    while (Place > 0) and ComesFirst(Item, Result[Place - 1]) do
      Dec(Place);
    Insert(Item, Result, Place);
  end;
end;

function OnGrid(Value: double): double;
begin
  Result := Ceil(Value / PackGrid - CloseEnough) * PackGrid;
end;

function BoxIsFree(const Boxes: TPackBoxArray; X, Y, Width, Height: double): boolean;
var
  Box: TPackBox;
begin
  for Box in Boxes do
    if (X < Box.MaxX + PackGap - CloseEnough) and (X + Width + PackGap > Box.MinX + CloseEnough) and
      (Y < Box.MaxY + PackGap - CloseEnough) and (Y + Height + PackGap > Box.MinY + CloseEnough) then
      Exit(False);
  Result := True;
end;

// Where the item's corner could go: the origin, or just past a placed box
procedure Candidates(const Boxes: TPackBoxArray; out Xs, Ys: TDoubleArray);
var
  Box: TPackBox;
begin
  Xs := nil;
  Ys := nil;
  Insert(0.0, Xs, 0);
  Insert(0.0, Ys, 0);
  for Box in Boxes do
  begin
    Insert(OnGrid(Box.MaxX + PackGap), Xs, Length(Xs));
    Insert(OnGrid(Box.MaxY + PackGap), Ys, Length(Ys));
  end;
end;

// Keeps Best when this size has no better spot, judged by how far down the
// bottom edge comes, then how far left
procedure TrySize(const Boxes: TPackBoxArray; const Xs, Ys: TDoubleArray; Width, Height, Limit, Depth: double; Turned: boolean;
  var Found: boolean; var Best: TPackSpot; var BestBottom: double);
var
  X, Y, Bottom: double;
begin
  if Width > Limit then
    Exit;
  for Y in Ys do
  begin
    Bottom := Y + Height;
    if Bottom > Depth + CloseEnough then
      Continue;
    if Found and (Bottom > BestBottom + CloseEnough) then
      Continue;
    for X in Xs do
    begin
      if X + Width > Limit then
        Continue;
      if Found and (Bottom >= BestBottom - CloseEnough) and (X >= Best.X - CloseEnough) then
        Continue;
      if BoxIsFree(Boxes, X, Y, Width, Height) then
      begin
        Found := True;
        Best.X := X;
        Best.Y := Y;
        Best.Turned := Turned;
        BestBottom := Bottom;
      end;
    end;
  end;
end;

// Items that fit, in Spots; returns how many did not. Depth is how far down
// pieces can go, and Turns says whether a quarter turn may be tried.
function PackInto(const Items: TPackItemArray; Limit: double; out Spots: TPackSpotArray; Depth: double = Infinity; Turns: boolean = True): integer;
var
  Item: TPackItem;
  Boxes: TPackBoxArray;
  Box: TPackBox;
  Xs, Ys: TDoubleArray;
  Best: TPackSpot;
  BestBottom: double;
  Found: boolean;
begin
  Result := 0;
  Spots := nil;
  Boxes := nil;
  for Item in Items do
  begin
    Candidates(Boxes, Xs, Ys);
    Found := False;
    Best := Default(TPackSpot);
    Best.Placement := Item.Placement;
    BestBottom := 0;
    TrySize(Boxes, Xs, Ys, Item.Width, Item.Height, Limit, Depth, False, Found, Best, BestBottom);
    if Turns then
      TrySize(Boxes, Xs, Ys, Item.Height, Item.Width, Limit, Depth, True, Found, Best, BestBottom);
    if not Found then
    begin
      Inc(Result);
      Continue;
    end;
    Insert(Best, Spots, Length(Spots));
    Box.MinX := Best.X;
    Box.MinY := Best.Y;
    if Best.Turned then
    begin
      Box.MaxX := Best.X + Item.Height;
      Box.MaxY := Best.Y + Item.Width;
    end
    else
    begin
      Box.MaxX := Best.X + Item.Width;
      Box.MaxY := Best.Y + Item.Height;
    end;
    Insert(Box, Boxes, Length(Boxes));
  end;
end;

procedure ApplySpots(Layout: TLayout; const Spots: TPackSpotArray);
var
  Spot: TPackSpot;
begin
  for Spot in Spots do
  begin
    Layout.Placements[Spot.Placement].X := Spot.X;
    Layout.Placements[Spot.Placement].Y := Spot.Y;
    if Spot.Turned then
      Layout.Placements[Spot.Placement].Rotation := (Layout.Placements[Spot.Placement].Rotation + 90) mod 360;
  end;
end;

function PagesInUse(Layout: TLayout): integer;
var
  Page: TTilePage;
  Rows, Columns: integer;
begin
  Result := 0;
  for Page in Layout.Pages(Layout.PlacedPieces, Rows, Columns) do
    if not Page.Blank then
      Inc(Result);
end;

function SheetLength(Layout: TLayout): double;
var
  Shape: TPlacedPiece;
begin
  Result := 0;
  for Shape in Layout.PlacedPieces do
    Result := Max(Result, Shape.Bounds.MaxY);
end;

function LessThan(PagesA: integer; LengthA: double; PagesB: integer; LengthB: double): boolean;
begin
  if PagesA <> PagesB then
    Exit(PagesA < PagesB);
  Result := LengthA < LengthB - CloseEnough;
end;

function TiledWidth(Layout: TLayout; Columns: integer): double;
var
  Printable: double;
begin
  Printable := Layout.Output.Tiles.PaperWidth - 2 * Layout.Output.Tiles.Margin;
  Result := Columns * Printable - (Columns - 1) * Layout.Output.Tiles.Overlap;
end;

// Each column count is tried on the real pages; the fewest pages win
function BestTiledSpots(Layout: TLayout; const Items: TPackItemArray): TPackSpotArray;
var
  Before: TPlacementArray;
  Spots: TPackSpotArray;
  Item: TPackItem;
  Columns, First, Pages, BestPages: integer;
  Widest, Sheet, BestSheet: double;
begin
  Result := nil;
  Widest := 0;
  for Item in Items do
    Widest := Max(Widest, Min(Item.Width, Item.Height));
  First := 1;
  while TiledWidth(Layout, First) < Widest do
    Inc(First);
  Before := Copy(Layout.Placements);
  BestPages := MaxInt;
  BestSheet := Infinity;
  for Columns := First to First + ExtraColumns do
  begin
    PackInto(Items, TiledWidth(Layout, Columns), Spots);
    ApplySpots(Layout, Spots);
    Pages := PagesInUse(Layout);
    Sheet := SheetLength(Layout);
    Layout.Placements := Copy(Before);
    if LessThan(Pages, Sheet, BestPages, BestSheet) then
    begin
      BestPages := Pages;
      BestSheet := Sheet;
      Result := Spots;
    end;
  end;
end;

function SheetDepth(Layout: TLayout): double;
begin
  Result := Infinity;
  if (Layout.Output.Kind = okMaterial) and (Layout.Output.MaterialLength > 0) then
    Result := Layout.Output.MaterialLength;
end;

function FitsRoll(Layout: TLayout): boolean;
var
  Shape: TPlacedPiece;
begin
  for Shape in Layout.PlacedPieces do
    if (Shape.Bounds.MaxX > Layout.UsableWidth + CloseEnough) or (Shape.Bounds.MaxY > SheetDepth(Layout) + CloseEnough) then
      Exit(False);
  Result := True;
end;

function PackLayout(Layout: TLayout): TPackResult;
var
  Items: TPackItemArray;
  Spots: TPackSpotArray;
  Before: TPlacementArray;
  PagesBefore: integer;
  LengthBefore: double;
  CanKeep: boolean;
begin
  Result := Default(TPackResult);
  if Layout.Output.Kind = okProjector then
  begin
    Result.Reason := rsPackProjector;
    Exit;
  end;
  if (Layout.Output.Kind = okTiled) and not TilesAreUsable(Layout.Output.Tiles) then
  begin
    Result.Reason := rsPackNoPrintArea;
    Exit;
  end;
  Layout.PlaceNewPieces;
  Items := ItemsFrom(Layout);
  if Items = nil then
  begin
    Result.Reason := rsPackNothing;
    Exit;
  end;
  PagesBefore := PagesInUse(Layout);
  LengthBefore := SheetLength(Layout);
  // An arrangement that runs off the roll is never the better one
  CanKeep := (Layout.Output.Kind = okTiled) or FitsRoll(Layout);
  Before := Copy(Layout.Placements);
  if Layout.Output.Kind = okTiled then
    Spots := BestTiledSpots(Layout, Items)
  else
    Result.LeftOut := PackInto(Items, Layout.UsableWidth, Spots, SheetDepth(Layout), (Layout.Output.Kind <> okMaterial) or Layout.Output.AllowTurns);
  ApplySpots(Layout, Spots);
  Result.Pages := PagesInUse(Layout);
  if CanKeep and LessThan(PagesBefore, LengthBefore, Result.Pages, SheetLength(Layout)) then
  begin
    Layout.Placements := Before;
    Result.Pages := PagesBefore;
    Result.LeftOut := 0;
    Result.Reason := rsPackNoBetter;
    Exit;
  end;
  Layout.Output.ExcludedPages := nil;
  Result.Done := True;
  Result.Count := Length(Spots);
end;

end.
