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

// The publish preview without its drawing: how layout millimetres map to
// screen pixels, and what is under the cursor. Both y axes point down. Kept
// free of the LCL so it can be unit-tested.
unit Sloper.Output.Preview;

{$mode ObjFPC}{$H+}
{$modeswitch advancedrecords}

interface

uses
  Sloper.Core.Geometry, Sloper.Output.Layout;

const
  PreviewZoomStep = 1.25;
  // Placements land on this grid, in mm
  PlacementStep = 0.5;

type
  TPreviewView = record
    // Pixels per millimetre
    Scale: double;
    // Screen position of the layout's top left
    OriginX, OriginY: double;
    function ToScreen(const P: TVec2): TVec2;
    function ToLayout(const S: TVec2): TVec2;
    // Zooms by Factor keeping the layout point under Anchor (screen) still
    procedure ZoomAt(Factor: double; const Anchor: TVec2);
    procedure Pan(DX, DY: double);
    // Shows Area centred in a Width x Height view, with Margin pixels around it
    procedure Fit(const Area: TRect2; Width, Height, Margin: double);
  end;

function DefaultPreviewView: TPreviewView;
// The index in Shapes of the smallest piece containing At, or -1
function ShapeAt(const Shapes: TPlacedPieceArray; const At: TVec2): integer;
function RoundToStep(Value: double): double;

implementation

uses
  Math;

const
  MinPreviewScale = 0.02;
  MaxPreviewScale = 20;

function DefaultPreviewView: TPreviewView;
begin
  Result.Scale := 1;
  Result.OriginX := 0;
  Result.OriginY := 0;
end;

function TPreviewView.ToScreen(const P: TVec2): TVec2;
begin
  Result := Vec2(P.X * Scale + OriginX, P.Y * Scale + OriginY);
end;

function TPreviewView.ToLayout(const S: TVec2): TVec2;
begin
  Result := Vec2((S.X - OriginX) / Scale, (S.Y - OriginY) / Scale);
end;

procedure TPreviewView.ZoomAt(Factor: double; const Anchor: TVec2);
var
  Held: TVec2;
begin
  Held := ToLayout(Anchor);
  Scale := EnsureRange(Scale * Factor, MinPreviewScale, MaxPreviewScale);
  OriginX := Anchor.X - Held.X * Scale;
  OriginY := Anchor.Y - Held.Y * Scale;
end;

procedure TPreviewView.Pan(DX, DY: double);
begin
  OriginX := OriginX + DX;
  OriginY := OriginY + DY;
end;

procedure TPreviewView.Fit(const Area: TRect2; Width, Height, Margin: double);
var
  AreaWidth, AreaHeight: double;
begin
  AreaWidth := Max(Area.MaxX - Area.MinX, 1);
  AreaHeight := Max(Area.MaxY - Area.MinY, 1);
  Scale := EnsureRange(Min((Width - 2 * Margin) / AreaWidth, (Height - 2 * Margin) / AreaHeight), MinPreviewScale, MaxPreviewScale);
  OriginX := (Width - AreaWidth * Scale) / 2 - Area.MinX * Scale;
  OriginY := (Height - AreaHeight * Scale) / 2 - Area.MinY * Scale;
end;

function ShapeAt(const Shapes: TPlacedPieceArray; const At: TVec2): integer;
var
  Index: integer;
  Size, Best: double;
begin
  Result := -1;
  Best := Infinity;
  for Index := 0 to High(Shapes) do
  begin
    Size := Abs(SignedArea(Shapes[Index].CutLine));
    if (Size < Best) and PointInPolygon(At, Shapes[Index].CutLine) then
    begin
      Best := Size;
      Result := Index;
    end;
  end;
end;

function RoundToStep(Value: double): double;
begin
  Result := Round(Value / PlacementStep) * PlacementStep;
end;

end.
