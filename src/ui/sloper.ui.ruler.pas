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

// The rulers along the top and left of the drafting canvas, as in Inkscape,
// and the corner between them, which names the unit. Each ruler starts where
// the canvas does, so its pixels line up with the canvas's; the cursor shows
// as a line across it. Ticks come from Sloper.UI.RulerTicks.
unit Sloper.UI.Ruler;

{$mode ObjFPC}{$H+}

interface

uses
  Classes, Controls, BGRABitmap, BGRABitmapTypes, Sloper.Core.Geometry, Sloper.Core.Measurements, Sloper.Core.Units, Sloper.UI.View;

type
  TCanvasRuler = class(TCustomControl)
  private
    FBitmap: TBGRABitmap;
    FVertical: boolean;
    FView: TViewTransform;
    FMeasureUnit: TMeasureUnit;
    FPointer: TVec2;
    FPointerShown: boolean;
    procedure SetMeasureUnit(AUnit: TMeasureUnit);
    procedure DrawTicks;
    procedure DrawCursor;
    procedure DrawLabel(const ALabel: string; Position: integer);
  protected
    procedure Paint; override;
  public
    constructor Create(AOwner: TComponent; AVertical: boolean); reintroduce;
    destructor Destroy; override;
    // The canvas's view, which moves the ticks
    procedure SetView(const AView: TViewTransform);
    // The pointer on the canvas, in model millimetres
    procedure ShowCursor(const ModelPos: TVec2);
    procedure HideCursor;
    property MeasureUnit: TMeasureUnit read FMeasureUnit write SetMeasureUnit;
  end;

  // The square where the rulers meet, naming their unit
  TRulerCorner = class(TCustomControl)
  private
    FMeasureUnit: TMeasureUnit;
    procedure SetMeasureUnit(AUnit: TMeasureUnit);
  protected
    procedure Paint; override;
  public
    constructor Create(AOwner: TComponent); override;
    property MeasureUnit: TMeasureUnit read FMeasureUnit write SetMeasureUnit;
  end;

// How thick a ruler is, for this form's scale; the form sizes the rulers and
// corner, since they cannot scale before they have a parent
function RulerThickness(Control: TControl): integer;

implementation

uses
  SysUtils, Math, Graphics, Sloper.UI.RulerTicks;

const
  THICKNESS_AT96 = 22;
  FONT_HEIGHT_AT96 = 11;
  // Tick lengths as shares of the ruler's thickness
  LABELLED_SHARE = 0.9;
  MIDDLE_SHARE = 0.45;
  MINOR_SHARE = 0.25;
  LABEL_GAP = 2;

function Background: TBGRAPixel;
begin
  Result := BGRA(240, 239, 236);
end;

function TickColor: TBGRAPixel;
begin
  Result := BGRA(110, 108, 104);
end;

function TextColor: TBGRAPixel;
begin
  Result := BGRA(48, 48, 52);
end;

function CursorColor: TBGRAPixel;
begin
  Result := BGRA(214, 54, 40);
end;

function UnitColor: TBGRAPixel;
begin
  Result := BGRA(20, 104, 200);
end;

function RulerThickness(Control: TControl): integer;
begin
  Result := Control.Scale96ToForm(THICKNESS_AT96);
end;

constructor TCanvasRuler.Create(AOwner: TComponent; AVertical: boolean);
begin
  inherited Create(AOwner);
  FVertical := AVertical;
  FBitmap := TBGRABitmap.Create(1, 1);
  FView := DefaultView;
  FMeasureUnit := muMillimetre;
end;

destructor TCanvasRuler.Destroy;
begin
  FreeAndNil(FBitmap);
  inherited Destroy;
end;

procedure TCanvasRuler.SetView(const AView: TViewTransform);
begin
  // Any change at all moves the ticks, so this is not a tolerance compare
  if (AView.Scale = FView.Scale) and (AView.OriginX = FView.OriginX) and (AView.OriginY = FView.OriginY) then
    Exit;
  FView := AView;
  Invalidate;
end;

procedure TCanvasRuler.SetMeasureUnit(AUnit: TMeasureUnit);
begin
  if AUnit = FMeasureUnit then
    Exit;
  FMeasureUnit := AUnit;
  Invalidate;
end;

procedure TCanvasRuler.ShowCursor(const ModelPos: TVec2);
begin
  FPointer := ModelPos;
  FPointerShown := True;
  Invalidate;
end;

procedure TCanvasRuler.HideCursor;
begin
  if not FPointerShown then
    Exit;
  FPointerShown := False;
  Invalidate;
end;

// A number just past its tick: to the right on the top ruler; on the left
// ruler turned to read upwards, below the tick, as values grow downwards
procedure TCanvasRuler.DrawLabel(const ALabel: string; Position: integer);
var
  Size: TSize;
  Flat, Turned: TBGRABitmap;
  Gap: integer;
begin
  Size := FBitmap.TextSize(ALabel);
  Gap := Scale96ToForm(LABEL_GAP);
  if not FVertical then
  begin
    FBitmap.TextOut(Position + Gap, 0, ALabel, TextColor);
    Exit;
  end;
  Flat := TBGRABitmap.Create(Size.cx, Size.cy, BGRAPixelTransparent);
  try
    Flat.FontHeight := FBitmap.FontHeight;
    Flat.FontQuality := FBitmap.FontQuality;
    Flat.TextOut(0, 0, ALabel, TextColor);
    Turned := Flat.RotateCCW;
    try
      FBitmap.PutImage(0, Position + Gap, Turned, dmDrawWithTransparency);
    finally
      FreeAndNil(Turned);
    end;
  finally
    FreeAndNil(Flat);
  end;
end;

procedure TCanvasRuler.DrawTicks;
var
  Ticks: TRulerTickArray;
  Tick: TRulerTick;
  Thickness, Along, TickLength: integer;
  Labelled: double;
begin
  if FVertical then
  begin
    Thickness := ClientWidth;
    Ticks := RulerTicks(FView, True, ClientHeight, FMeasureUnit);
  end
  else
  begin
    Thickness := ClientHeight;
    Ticks := RulerTicks(FView, False, ClientWidth, FMeasureUnit);
  end;
  Labelled := RulerSpacing(FView.Scale * MILLIMETRES_PER_UNIT[FMeasureUnit], FMeasureUnit).Labelled;
  for Tick in Ticks do
  begin
    Along := Round(Tick.Position);
    case Tick.Kind of
      rtLabelled: TickLength := Round(Thickness * LABELLED_SHARE);
      rtMiddle: TickLength := Round(Thickness * MIDDLE_SHARE);
      else
        TickLength := Max(Round(Thickness * MINOR_SHARE), 2);
    end;
    // Ticks grow from the edge next to the canvas
    if FVertical then
      FBitmap.DrawHorizLine(Thickness - TickLength, Along, Thickness - 1, TickColor)
    else
      FBitmap.DrawVertLine(Along, Thickness - TickLength, Thickness - 1, TickColor);
    if Tick.Kind = rtLabelled then
      DrawLabel(RulerLabel(Tick.Value, Labelled), Along);
  end;
end;

procedure TCanvasRuler.DrawCursor;
var
  Screen: TVec2;
begin
  Screen := FView.ToScreen(FPointer);
  if FVertical then
    FBitmap.DrawHorizLine(0, Round(Screen.Y), ClientWidth - 1, CursorColor)
  else
    FBitmap.DrawVertLine(Round(Screen.X), 0, ClientHeight - 1, CursorColor);
end;

procedure TCanvasRuler.Paint;
begin
  if (FBitmap.Width <> ClientWidth) or (FBitmap.Height <> ClientHeight) then
    FBitmap.SetSize(Max(ClientWidth, 1), Max(ClientHeight, 1));
  FBitmap.Fill(Background);
  FBitmap.FontHeight := Scale96ToForm(FONT_HEIGHT_AT96);
  FBitmap.FontQuality := fqFineAntialiasing;
  DrawTicks;
  if FPointerShown then
    DrawCursor;
  // The edge next to the canvas
  if FVertical then
    FBitmap.DrawVertLine(ClientWidth - 1, 0, ClientHeight - 1, TickColor)
  else
    FBitmap.DrawHorizLine(0, ClientHeight - 1, ClientWidth - 1, TickColor);
  FBitmap.Draw(Canvas, 0, 0, True);
end;

constructor TRulerCorner.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FMeasureUnit := muMillimetre;
end;

procedure TRulerCorner.SetMeasureUnit(AUnit: TMeasureUnit);
begin
  if AUnit = FMeasureUnit then
    Exit;
  FMeasureUnit := AUnit;
  Invalidate;
end;

procedure TRulerCorner.Paint;
var
  Bitmap: TBGRABitmap;
  Abbreviation: string;
  Size: TSize;
begin
  Bitmap := TBGRABitmap.Create(Max(ClientWidth, 1), Max(ClientHeight, 1), Background);
  try
    Bitmap.FontHeight := Scale96ToForm(FONT_HEIGHT_AT96);
    Bitmap.FontStyle := [fsBold];
    Bitmap.FontQuality := fqFineAntialiasing;
    Abbreviation := MEASURE_UNIT_NAMES[FMeasureUnit];
    Size := Bitmap.TextSize(Abbreviation);
    Bitmap.TextOut((ClientWidth - Size.cx) div 2, (ClientHeight - Size.cy) div 2, Abbreviation, UnitColor);
    Bitmap.DrawVertLine(ClientWidth - 1, 0, ClientHeight - 1, TickColor);
    Bitmap.DrawHorizLine(0, ClientHeight - 1, ClientWidth - 1, TickColor);
    Bitmap.Draw(Canvas, 0, 0, True);
  finally
    FreeAndNil(Bitmap);
  end;
end;

end.
