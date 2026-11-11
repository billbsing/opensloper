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

// The canvas view: how model millimetres map to screen pixels, both y down,
// with zoom and pan. Kept free of the LCL so it can be unit-tested.
unit Sloper.UI.View;

{$mode ObjFPC}{$H+}
{$modeswitch advancedrecords}

interface

uses
  Sloper.Core.Geometry;

const
  MIN_SCALE = 0.02;   // pixels per mm
  MAX_SCALE = 200;
  ZOOM_STEP = 1.25;

type
  TViewTransform = record
    // Pixels per millimetre
    Scale: double;
    // Screen position of the model origin
    OriginX, OriginY: double;
    function ToScreen(const ModelPoint: TVec2): TVec2;
    function ToModel(const ScreenPoint: TVec2): TVec2;
    // Screen pixels as millimetres at this zoom
    function PixelsToMM(Pixels: double): double;
    // Zooms by Factor keeping the model point under Anchor (screen) still
    procedure ZoomAt(Factor: double; const Anchor: TVec2);
    procedure Pan(DX, DY: double);
    // Puts the model point Centre in the middle of a Width x Height view
    procedure CentreOn(const Centre: TVec2; Width, Height: double);
    // Shows Bounds (model) centred in a Width x Height view, with Margin pixels around it
    procedure Fit(const Bounds: TRect2; Width, Height, Margin: double);
    // Centres Bounds (model) without zooming, unless all of it already shows,
    // Margin pixels clear of the edges of a Width x Height view
    procedure Reveal(const Bounds: TRect2; Width, Height, Margin: double);
  end;

  // One scroll bar, in pixels. Extent covers the content and the view, so the
  // bar still means something when the view is panned away from the content.
  TScrollAxis = record
    Extent, Position, Page: integer;
    // False when all of the extent is showing
    Active: boolean;
  end;

function DefaultView: TViewTransform;
// A scroll bar for content running from ContentLow to ContentHigh on screen
// (the view being 0 to ViewSize)
function ScrollAxisFor(ContentLow, ContentHigh, ViewSize: double): TScrollAxis;
// Pixels per mm for true size on a screen with this many pixels per inch
function TrueScale(PixelsPerInch: double): double;

implementation

uses
  Math;

function DefaultView: TViewTransform;
begin
  Result.Scale := 2;
  Result.OriginX := 40;
  Result.OriginY := 40;
end;

function ScrollAxisFor(ContentLow, ContentHigh, ViewSize: double): TScrollAxis;
var
  Low, High: double;
begin
  Low := Min(ContentLow, 0);
  High := Max(ContentHigh, ViewSize);
  Result.Extent := Round(High - Low);
  Result.Position := Round(-Low);
  Result.Page := Round(ViewSize);
  Result.Active := Result.Extent > Result.Page;
end;

function TrueScale(PixelsPerInch: double): double;
begin
  Result := PixelsPerInch / 25.4;
end;

function TViewTransform.ToScreen(const ModelPoint: TVec2): TVec2;
begin
  Result.X := OriginX + ModelPoint.X * Scale;
  Result.Y := OriginY + ModelPoint.Y * Scale;
end;

function TViewTransform.ToModel(const ScreenPoint: TVec2): TVec2;
begin
  Result.X := (ScreenPoint.X - OriginX) / Scale;
  Result.Y := (ScreenPoint.Y - OriginY) / Scale;
end;

function TViewTransform.PixelsToMM(Pixels: double): double;
begin
  Result := Pixels / Scale;
end;

procedure TViewTransform.ZoomAt(Factor: double; const Anchor: TVec2);
var
  Fixed: TVec2;
begin
  Fixed := ToModel(Anchor);
  Scale := EnsureRange(Scale * Factor, MIN_SCALE, MAX_SCALE);
  OriginX := Anchor.X - Fixed.X * Scale;
  OriginY := Anchor.Y - Fixed.Y * Scale;
end;

procedure TViewTransform.Pan(DX, DY: double);
begin
  OriginX := OriginX + DX;
  OriginY := OriginY + DY;
end;

procedure TViewTransform.CentreOn(const Centre: TVec2; Width, Height: double);
begin
  OriginX := Width / 2 - Centre.X * Scale;
  OriginY := Height / 2 - Centre.Y * Scale;
end;

procedure TViewTransform.Fit(const Bounds: TRect2; Width, Height, Margin: double);
var
  ModelWidth, ModelHeight: double;
  Centre: TVec2;
begin
  ModelWidth := Max(Bounds.MaxX - Bounds.MinX, 1);
  ModelHeight := Max(Bounds.MaxY - Bounds.MinY, 1);
  Scale := EnsureRange(Min((Width - 2 * Margin) / ModelWidth, (Height - 2 * Margin) / ModelHeight), MIN_SCALE, MAX_SCALE);
  Centre := Vec2((Bounds.MinX + Bounds.MaxX) / 2, (Bounds.MinY + Bounds.MaxY) / 2);
  OriginX := Width / 2 - Centre.X * Scale;
  OriginY := Height / 2 - Centre.Y * Scale;
end;

procedure TViewTransform.Reveal(const Bounds: TRect2; Width, Height, Margin: double);
var
  Corner, OtherCorner: TVec2;
begin
  Corner := ToScreen(Vec2(Bounds.MinX, Bounds.MinY));
  OtherCorner := ToScreen(Vec2(Bounds.MaxX, Bounds.MaxY));
  if (Corner.X >= Margin) and (Corner.Y >= Margin) and (OtherCorner.X <= Width - Margin) and (OtherCorner.Y <= Height - Margin) then
    Exit;
  Pan(Width / 2 - (Corner.X + OtherCorner.X) / 2, Height / 2 - (Corner.Y + OtherCorner.Y) / 2);
end;

end.
