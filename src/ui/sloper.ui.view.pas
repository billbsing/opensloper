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

// The canvas view: how model millimetres (y up) map to screen pixels (y
// down), with zoom and pan. Kept free of the LCL so it can be unit-tested.
unit Sloper.UI.View;

{$mode ObjFPC}{$H+}
{$modeswitch advancedrecords}

interface

uses
  Sloper.Core.Geometry;

const
  MinScale = 0.02;   // pixels per mm
  MaxScale = 200;
  ZoomStep = 1.25;

type
  TViewTransform = record
    // Pixels per millimetre
    Scale: double;
    // Screen position of the model origin
    OriginX, OriginY: double;
    function ToScreen(const P: TVec2): TVec2;
    function ToModel(const S: TVec2): TVec2;
    // Screen pixels as millimetres at this zoom
    function PixelsToMM(Pixels: double): double;
    // Zooms by Factor keeping the model point under Anchor (screen) still
    procedure ZoomAt(Factor: double; const Anchor: TVec2);
    procedure Pan(DX, DY: double);
    // Shows Bounds (model) centred in a Width x Height view, with Margin pixels around it
    procedure Fit(const Bounds: TRect2; Width, Height, Margin: double);
  end;

function DefaultView: TViewTransform;
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

function TrueScale(PixelsPerInch: double): double;
begin
  Result := PixelsPerInch / 25.4;
end;

function TViewTransform.ToScreen(const P: TVec2): TVec2;
begin
  Result.X := OriginX + P.X * Scale;
  Result.Y := OriginY - P.Y * Scale;
end;

function TViewTransform.ToModel(const S: TVec2): TVec2;
begin
  Result.X := (S.X - OriginX) / Scale;
  Result.Y := (OriginY - S.Y) / Scale;
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
  Scale := EnsureRange(Scale * Factor, MinScale, MaxScale);
  OriginX := Anchor.X - Fixed.X * Scale;
  OriginY := Anchor.Y + Fixed.Y * Scale;
end;

procedure TViewTransform.Pan(DX, DY: double);
begin
  OriginX := OriginX + DX;
  OriginY := OriginY + DY;
end;

procedure TViewTransform.Fit(const Bounds: TRect2; Width, Height, Margin: double);
var
  ModelWidth, ModelHeight: double;
  Centre: TVec2;
begin
  ModelWidth := Max(Bounds.MaxX - Bounds.MinX, 1);
  ModelHeight := Max(Bounds.MaxY - Bounds.MinY, 1);
  Scale := EnsureRange(Min((Width - 2 * Margin) / ModelWidth, (Height - 2 * Margin) / ModelHeight), MinScale, MaxScale);
  Centre := Vec2((Bounds.MinX + Bounds.MaxX) / 2, (Bounds.MinY + Bounds.MaxY) / 2);
  OriginX := Width / 2 - Centre.X * Scale;
  OriginY := Height / 2 + Centre.Y * Scale;
end;

end.
