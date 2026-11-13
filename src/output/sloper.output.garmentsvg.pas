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

// The Garment view as SVG, at true scale in millimetres, for the Garment tab's
// export and the Automation API's render. Shading is drawn as one gradient per
// band of rows (or columns), clipped to the piece: close to the screen, not
// exact. See Garment view in the design document.
unit Sloper.Output.GarmentSVG;

{$mode ObjFPC}{$H+}

interface

uses
  Sloper.Core.Garment;

function GarmentToSVG(const Scene: TGarmentScene; const Light: TGarmentLight): string;

implementation

uses
  SysUtils, Math, Sloper.Core.Geometry, Sloper.Core.Numeric, Sloper.Core.Draft, Sloper.Core.Materials, Sloper.Output.DraftSVG;

const
  // In millimetres
  MARGIN = 15;
  EMPTY_SIZE = 100;
  LINE_WIDTH = 0.6;
  STITCH_WIDTH = 0.4;
  STITCH_INSET = 2.5;
  STITCH_DASH = '2 1.5';
  HATCH_SPACING = 6;
  // How deep a seam's shadow or highlight reaches into the piece
  EDGE_GLOW_WIDTH = 5;
  EDGE_SHADOW_OPACITY = 0.35;
  EDGE_HIGHLIGHT_OPACITY = 0.3;
  SHADOW_OFFSET_X = 2;
  SHADOW_OFFSET_Y = 3;
  SHADOW_BLUR = 2.5;
  SHADOW_OPACITY = 0.3;
  // About this deep each, between 8 and MAX_BANDS of them
  BAND_DEPTH = 4;
  MIN_BANDS = 8;
  MAX_BANDS = 150;
  // Gradient stops across a band
  STOPS = 10;
  INK_COLOR = '#202020';
  BACKGROUND_COLOR = '#ffffff';

function Num(Value: double): string;
begin
  Result := SVGNumber(Value);
end;

function PathData(const Points: TVec2Array; Closed: boolean): string;
var
  Index: integer;
begin
  Result := '';
  for Index := 0 to High(Points) do
  begin
    if Index = 0 then
      Result := 'M '
    else
      Result := Result + ' L ';
    Result := Result + Num(Points[Index].X) + ' ' + Num(Points[Index].Y);
  end;
  if Closed and (Result <> '') then
    Result := Result + ' Z';
end;

function ColorText(const Color: TMaterialColor): string;
begin
  Result := LowerCase(MaterialColorText(Color));
end;

// The bands' gradients, under Defs, and the bands themselves, as the result
function ShadingBands(const Piece: TGarmentPiece; Number: integer; const Light: TGarmentLight; var Defs: string): string;
var
  Base: TMaterialColor;
  Low, High, Band, Start, Depth, SpanLow, SpanHigh: double;
  Lows, Highs: TDoubleArray;
  Count, BandIndex, Stop: integer;
  Id: string;
begin
  Result := '';
  Base := GarmentBaseColor(Piece.Look);
  if Piece.ShadeColumns then
  begin
    Low := Piece.Bounds.MinX;
    High := Piece.Bounds.MaxX;
  end
  else
  begin
    Low := Piece.Bounds.MinY;
    High := Piece.Bounds.MaxY;
  end;
  Count := EnsureRange(Ceil((High - Low) / BAND_DEPTH), MIN_BANDS, MAX_BANDS);
  Depth := (High - Low) / Count;
  GarmentSpans(Piece, Low + Depth / 2, Depth, Count, Lows, Highs);
  for BandIndex := 0 to Count - 1 do
  begin
    Start := Low + BandIndex * Depth;
    SpanLow := Lows[BandIndex];
    SpanHigh := Highs[BandIndex];
    if SpanHigh <= SpanLow then
      Continue;
    Id := Format('shade%d-%d', [Number, BandIndex]);
    if Piece.ShadeColumns then
      Defs := Defs + Format('<linearGradient id="%s" gradientUnits="userSpaceOnUse" x1="0" y1="%s" x2="0" y2="%s">',
        [Id, Num(SpanLow), Num(SpanHigh)])
    else
      Defs := Defs + Format('<linearGradient id="%s" gradientUnits="userSpaceOnUse" x1="%s" y1="0" x2="%s" y2="0">',
        [Id, Num(SpanLow), Num(SpanHigh)]);
    for Stop := 0 to STOPS do
    begin
      Band := Stop / STOPS;
      Defs := Defs + Format('<stop offset="%s" stop-color="%s"/>', [Num(Band), ColorText(ShadedColor(Base,
        GarmentShade(Band, Piece.ShadeColumns, Light)))]);
    end;
    Defs := Defs + '</linearGradient>' + #10;
    // A hair over the band, so neighbours leave no seam between them
    if Piece.ShadeColumns then
      Result := Result + Format('<rect x="%s" y="%s" width="%s" height="%s" fill="url(#%s)"/>',
        [Num(Start), Num(Piece.Bounds.MinY), Num(Depth + 0.05), Num(Piece.Bounds.MaxY - Piece.Bounds.MinY), Id]) + #10
    else
      Result := Result + Format('<rect x="%s" y="%s" width="%s" height="%s" fill="url(#%s)"/>',
        [Num(Piece.Bounds.MinX), Num(Start), Num(Piece.Bounds.MaxX - Piece.Bounds.MinX), Num(Depth + 0.05), Id]) + #10;
  end;
end;

function MarkerElement(const Marker: TGarmentMarker): string;
var
  Radius: double;
begin
  Radius := Max(Marker.Size, 1) / 2;
  case Marker.Marker of
    pmButton:
      Result := Format('<circle cx="%s" cy="%s" r="%s" fill="#f4f4f0" stroke="%s" stroke-width="%s"/>',
        [Num(Marker.Centre.X), Num(Marker.Centre.Y), Num(Radius), INK_COLOR, Num(STITCH_WIDTH)]) +
        Format('<circle cx="%s" cy="%s" r="%s" fill="%s"/>', [Num(Marker.Centre.X - Radius / 4), Num(Marker.Centre.Y),
        Num(Radius / 8), INK_COLOR]) + Format('<circle cx="%s" cy="%s" r="%s" fill="%s"/>', [Num(Marker.Centre.X + Radius / 4),
        Num(Marker.Centre.Y), Num(Radius / 8), INK_COLOR]);
    else
      Result := Format('<circle cx="%s" cy="%s" r="%s" fill="%s"/>', [Num(Marker.Centre.X), Num(Marker.Centre.Y), Num(Radius), INK_COLOR]);
  end;
  Result := Result + #10;
end;

function PieceElement(const Piece: TGarmentPiece; Number: integer; const Light: TGarmentLight; var Defs: string): string;
var
  Outline, Hatch: string;
  Line: TGarmentLine;
  Stroke: TLine2;
  Marker: TGarmentMarker;
  Facing: double;
  ClipId: string;
begin
  Outline := PathData(Piece.Outline, True);
  ClipId := Format('piece%d', [Number]);
  Defs := Defs + Format('<clipPath id="%s"><path d="%s"/></clipPath>', [ClipId, Outline]) + #10;
  Result := Format('<g data-piece="%s" data-id="%s">', [EscapeXML(Piece.Name), Piece.PieceKey]) + #10;
  Result := Result + Format('<path d="%s" fill="#000000" opacity="%s" filter="url(#shadow)" transform="translate(%s %s)"/>',
    [Outline, Num(SHADOW_OPACITY), Num(SHADOW_OFFSET_X), Num(SHADOW_OFFSET_Y)]) + #10;
  Result := Result + Format('<path d="%s" fill="%s"/>', [Outline, ColorText(GarmentBaseColor(Piece.Look))]) + #10;
  Result := Result + Format('<g clip-path="url(#%s)">', [ClipId]) + #10;
  if Light.Enabled then
    Result := Result + ShadingBands(Piece, Number, Light, Defs);
  if Piece.Look.Filled and (Piece.Look.Fill = ffHatch) then
  begin
    Hatch := '';
    for Stroke in HatchLines(Piece.Outline, HATCH_SPACING, Piece.Look.HatchAngle) do
      Hatch := Hatch + Format('M %s %s L %s %s ', [Num(Stroke.P1.X), Num(Stroke.P1.Y), Num(Stroke.P2.X), Num(Stroke.P2.Y)]);
    if Hatch <> '' then
      Result := Result + Format('<path d="%s" fill="none" stroke="%s" stroke-width="%s"/>', [Trim(Hatch), ColorText(Piece.Look.Color),
        Num(STITCH_WIDTH)]) + #10;
  end;
  // A shadow inside each seam on the side away from the light, a highlight
  // on the side towards it, so seams look slightly raised
  if Light.Enabled then
    for Line in Piece.Edges do
    begin
      if not Line.Sewn then
        Continue;
      Facing := GarmentLineFacing(Piece.Outline, Line.Points, Light) * Light.Strength;
      if Facing < 0 then
        Result := Result + Format('<path d="%s" fill="none" stroke="#000000" stroke-opacity="%s" stroke-width="%s" filter="url(#glow)"/>',
          [PathData(Line.Points, False), Num(-Facing * EDGE_SHADOW_OPACITY), Num(EDGE_GLOW_WIDTH)]) + #10
      else if Facing > 0 then
        Result := Result + Format('<path d="%s" fill="none" stroke="#ffffff" stroke-opacity="%s" stroke-width="%s" filter="url(#glow)"/>',
          [PathData(Line.Points, False), Num(Facing * EDGE_HIGHLIGHT_OPACITY), Num(EDGE_GLOW_WIDTH)]) + #10;
    end;
  Result := Result + '</g>' + #10;
  for Line in Piece.Edges do
  begin
    Result := Result + Format('<path d="%s" fill="none" stroke="%s" stroke-width="%s" stroke-linejoin="round"/>',
      [PathData(Line.Points, False), INK_COLOR, Num(LINE_WIDTH)]) + #10;
    if Line.Sewn then
      Result := Result + Format('<path data-edge="%s" d="%s" fill="none" stroke="%s" stroke-width="%s" stroke-dasharray="%s"/>',
        [Line.EdgeKey, PathData(GarmentInset(Piece.Outline, Line.Points, STITCH_INSET), False), INK_COLOR, Num(STITCH_WIDTH),
        STITCH_DASH]) + #10;
  end;
  for Line in Piece.Stitches do
    Result := Result + Format('<path d="%s" fill="none" stroke="%s" stroke-width="%s" stroke-dasharray="%s"/>',
      [PathData(Line.Points, False), INK_COLOR, Num(STITCH_WIDTH), STITCH_DASH]) + #10;
  for Marker in Piece.Markers do
    Result := Result + MarkerElement(Marker);
  Result := Result + '</g>' + #10;
end;

function GarmentToSVG(const Scene: TGarmentScene; const Light: TGarmentLight): string;
var
  Left, Top, Width, Height: double;
  Defs, Body: string;
  Index: integer;
begin
  if Length(Scene.Pieces) = 0 then
  begin
    Left := 0;
    Top := 0;
    Width := EMPTY_SIZE;
    Height := EMPTY_SIZE;
  end
  else
  begin
    Left := Scene.Bounds.MinX - MARGIN;
    Top := Scene.Bounds.MinY - MARGIN;
    Width := Scene.Bounds.MaxX - Scene.Bounds.MinX + 2 * MARGIN;
    Height := Scene.Bounds.MaxY - Scene.Bounds.MinY + 2 * MARGIN;
  end;
  Defs := Format('<filter id="shadow" x="-10%%" y="-10%%" width="120%%" height="120%%"><feGaussianBlur stdDeviation="%s"/></filter>',
    [Num(SHADOW_BLUR)]) + #10 + Format('<filter id="glow"><feGaussianBlur stdDeviation="%s"/></filter>', [Num(EDGE_GLOW_WIDTH / 4)]) + #10;
  Body := '';
  for Index := 0 to High(Scene.Pieces) do
    Body := Body + PieceElement(Scene.Pieces[Index], Index, Light, Defs);
  Result := Format('<svg xmlns="http://www.w3.org/2000/svg" width="%smm" height="%smm" viewBox="%s %s %s %s">',
    [Num(Width), Num(Height), Num(Left), Num(Top), Num(Width), Num(Height)]) + #10 + '<defs>' + #10 + Defs + '</defs>' + #10 +
    Format('<rect x="%s" y="%s" width="%s" height="%s" fill="%s"/>', [Num(Left), Num(Top), Num(Width), Num(Height), BACKGROUND_COLOR]) +
    #10 + Body + '</svg>' + #10;
end;

end.
