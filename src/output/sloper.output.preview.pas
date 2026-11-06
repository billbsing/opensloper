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
  Sloper.Core.Geometry, Sloper.Core.TextFields, Sloper.Output.Layout, Sloper.Output.Tiling;

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
    function ToScreen(const LayoutPoint: TVec2): TVec2;
    function ToLayout(const ScreenPoint: TVec2): TVec2;
    // Zooms by Factor keeping the layout point under Anchor (screen) still
    procedure ZoomAt(Factor: double; const Anchor: TVec2);
    procedure Pan(DX, DY: double);
    // Shows Area centred in a Width x Height view, with Margin pixels around it
    procedure Fit(const Area: TRect2; Width, Height, Margin: double);
  end;

function DefaultPreviewView: TPreviewView;
// The index in Shapes of the smallest piece containing At, or -1
function ShapeAt(const Shapes: TPlacedPieceArray; const At: TVec2): integer;
// The index of the note covering At, the last drawn first, or -1
function NoteAt(const Notes: TSheetNoteArray; const Values: TFieldValues; const At: TVec2): integer;
// The caption of the page At falls on, nearest its middle where two overlap;
// '' when there is none
function PageCaptionAt(const Pages: TTilePageArray; const At: TVec2): string;
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

function TPreviewView.ToScreen(const LayoutPoint: TVec2): TVec2;
begin
  Result := Vec2(LayoutPoint.X * Scale + OriginX, LayoutPoint.Y * Scale + OriginY);
end;

function TPreviewView.ToLayout(const ScreenPoint: TVec2): TVec2;
begin
  Result := Vec2((ScreenPoint.X - OriginX) / Scale, (ScreenPoint.Y - OriginY) / Scale);
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

function NoteAt(const Notes: TSheetNoteArray; const Values: TFieldValues; const At: TVec2): integer;
var
  Spread: TRect2;
begin
  for Result := High(Notes) downto 0 do
  begin
    Spread := NoteBounds(Notes[Result], Values);
    if (At.X >= Spread.MinX) and (At.X <= Spread.MaxX) and (At.Y >= Spread.MinY) and (At.Y <= Spread.MaxY) then
      Exit;
  end;
  Result := -1;
end;

function PageCaptionAt(const Pages: TTilePageArray; const At: TVec2): string;
var
  Page: TTilePage;
  Middle: TVec2;
  Best: double;
begin
  Result := '';
  Best := Infinity;
  for Page in Pages do
    if (At.X >= Page.Area.MinX) and (At.X <= Page.Area.MaxX) and (At.Y >= Page.Area.MinY) and (At.Y <= Page.Area.MaxY) then
    begin
      Middle := Vec2((Page.Area.MinX + Page.Area.MaxX) / 2, (Page.Area.MinY + Page.Area.MaxY) / 2);
      if Distance(Middle, At) < Best then
      begin
        Best := Distance(Middle, At);
        Result := Page.Caption;
      end;
    end;
end;

function RoundToStep(Value: double): double;
begin
  Result := Round(Value / PlacementStep) * PlacementStep;
end;

end.
