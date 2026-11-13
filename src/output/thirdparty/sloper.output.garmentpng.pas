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

// The Garment view drawn as pixels, shaded row by row as the core works it
// out: the Garment tab paints with it, and the PNG export and the Automation
// API's render use it, so an image is drawn as on screen. Uses BGRABitmap
// built without the LCL, so the CLI can draw it; it lives in thirdparty for
// that reason only. See Garment view in the design document.
unit Sloper.Output.GarmentPNG;

{$mode ObjFPC}{$H+}

interface

uses
  SysUtils, BGRABitmap, BGRABitmapTypes, Sloper.Core.Geometry, Sloper.Core.Garment;

type
  // Model to pixels: a point goes to ((X - Left) * Scale, (Y - Top) * Scale)
  TGarmentFrame = record
    Scale, Left, Top: double;
  end;

  // What the tab marks over the drawing; empty for an export
  TGarmentMarks = record
    // The piece under the pointer, by key
    HoverPiece: string;
    SelectedPieces: TStringArray;
    // The selected seams' edges as "piece:edge", and the seams' own keys,
    // which name the darts
    SeamEdges, SeamKeys: TStringArray;
  end;

const
  GARMENT_PNG_MIN_WIDTH = 16;
  GARMENT_PNG_MAX_WIDTH = 4096;
  GARMENT_PNG_DEFAULT_WIDTH = 1200;

// The frame that fits the scene's bounds in Width by Height pixels, Margin
// pixels in from each side, centred
function FitGarmentFrame(const Bounds: TRect2; Width, Height, Margin: integer): TGarmentFrame;
// Draws the scene over what Bitmap has; Background is what is behind it,
// which the shadows are made to show against
procedure DrawGarment(Bitmap: TBGRABitmap; const Scene: TGarmentScene; const Frame: TGarmentFrame; const Light: TGarmentLight;
  const Marks: TGarmentMarks; Background: TBGRAPixel);
// The scene on white, Width pixels across and as high as it needs, as PNG
// file bytes; False with a message when it cannot be drawn
function GarmentToPNG(const Scene: TGarmentScene; const Light: TGarmentLight; Width: integer; out Png: rawbytestring;
  out ErrorMessage: string): boolean;

resourcestring
  rsGarmentPngWidth = 'The width must be from %d to %d pixels';

implementation

uses
  Classes, Math, Sloper.Core.Numeric, Sloper.Core.Draft, Sloper.Core.Materials;

const
  // In pixels
  OUTLINE_WIDTH = 1.4;
  STITCH_WIDTH = 1;
  STITCH_INSET = 3;
  MARK_WIDTH = 3;
  SEAM_MARK_WIDTH = 4;
  SHADOW_OFFSET_X = 3;
  SHADOW_OFFSET_Y = 4;
  SHADOW_BLUR = 5;
  EDGE_GLOW_WIDTH = 7;
  EDGE_GLOW_BLUR = 3;
  HATCH_SPACING = 7;
  EXPORT_MARGIN = 24;
  // How strong, 0 to 255
  SHADOW_ALPHA_LIGHT = 80;
  SHADOW_ALPHA_DARK = 170;
  EDGE_SHADOW_ALPHA = 110;
  EDGE_HIGHLIGHT_ALPHA = 90;
  HOVER_TINT_ALPHA = 40;
  // The smallest marker drawn, across
  MIN_MARKER = 3;

function InkColor: TBGRAPixel;
begin
  Result := BGRA(32, 32, 32);
end;

function MarkColor: TBGRAPixel;
begin
  Result := BGRA(30, 120, 220);
end;

function SeamMarkColor: TBGRAPixel;
begin
  Result := BGRA(240, 120, 20);
end;

function FitGarmentFrame(const Bounds: TRect2; Width, Height, Margin: integer): TGarmentFrame;
var
  SpanX, SpanY: double;
begin
  SpanX := Max(Bounds.MaxX - Bounds.MinX, 1);
  SpanY := Max(Bounds.MaxY - Bounds.MinY, 1);
  Result.Scale := Min(Max(Width - 2 * Margin, 1) / SpanX, Max(Height - 2 * Margin, 1) / SpanY);
  Result.Left := (Bounds.MinX + Bounds.MaxX) / 2 - Width / 2 / Result.Scale;
  Result.Top := (Bounds.MinY + Bounds.MaxY) / 2 - Height / 2 / Result.Scale;
end;

function ToPixel(const Frame: TGarmentFrame; const Position: TVec2): TPointF;
begin
  Result := PointF((Position.X - Frame.Left) * Frame.Scale, (Position.Y - Frame.Top) * Frame.Scale);
end;

function ToPixels(const Frame: TGarmentFrame; const Points: TVec2Array; ShiftX: single = 0; ShiftY: single = 0): ArrayOfTPointF;
var
  Index: integer;
begin
  Result := nil;
  SetLength(Result, Length(Points));
  for Index := 0 to High(Points) do
  begin
    Result[Index] := ToPixel(Frame, Points[Index]);
    Result[Index].X := Result[Index].X + ShiftX;
    Result[Index].Y := Result[Index].Y + ShiftY;
  end;
end;

function Contains(const Keys: TStringArray; const Key: string): boolean;
var
  Each: string;
begin
  Result := False;
  for Each in Keys do
    if Each = Key then
      Exit(True);
end;

function IsDark(const Color: TBGRAPixel): boolean;
begin
  Result := (Color.red * 299 + Color.green * 587 + Color.blue * 114) div 1000 < 110;
end;

// Multiplies each pixel's colour by its shade: a half cylinder across the
// row (or column) the piece is at that height
procedure ShadeLayer(Layer: TBGRABitmap; const Piece: TGarmentPiece; const Frame: TGarmentFrame; OriginX, OriginY: integer;
  const Light: TGarmentLight);
var
  Row, Column: integer;
  Pixel: PBGRAPixel;
  Lows, Highs: TDoubleArray;
  Across: double;

  procedure Apply(var Target: TBGRAPixel; Factor: double);
  begin
    Target.red := Min(255, Round(Target.red * Factor));
    Target.green := Min(255, Round(Target.green * Factor));
    Target.blue := Min(255, Round(Target.blue * Factor));
  end;

begin
  if Piece.ShadeColumns then
    GarmentSpans(Piece, (OriginX + 0.5) / Frame.Scale + Frame.Left, 1 / Frame.Scale, Layer.Width, Lows, Highs)
  else
    GarmentSpans(Piece, (OriginY + 0.5) / Frame.Scale + Frame.Top, 1 / Frame.Scale, Layer.Height, Lows, Highs);
  for Row := 0 to Layer.Height - 1 do
  begin
    Pixel := Layer.ScanLine[Row];
    for Column := 0 to Layer.Width - 1 do
    begin
      if Pixel^.alpha > 0 then
        if Piece.ShadeColumns then
        begin
          if Highs[Column] > Lows[Column] then
          begin
            Across := ((OriginY + Row + 0.5) / Frame.Scale + Frame.Top - Lows[Column]) / (Highs[Column] - Lows[Column]);
            Apply(Pixel^, GarmentShade(Across, True, Light));
          end;
        end
        else if Highs[Row] > Lows[Row] then
        begin
          Across := ((OriginX + Column + 0.5) / Frame.Scale + Frame.Left - Lows[Row]) / (Highs[Row] - Lows[Row]);
          Apply(Pixel^, GarmentShade(Across, False, Light));
        end;
      Inc(Pixel);
    end;
  end;
  Layer.InvalidateBitmap;
end;

// A shadow inside each seam on the side away from the light, a highlight on
// the side towards it, drawn soft over the layer
procedure SeamGlow(Layer: TBGRABitmap; const Piece: TGarmentPiece; const Frame: TGarmentFrame; OriginX, OriginY: integer;
  const Light: TGarmentLight);
var
  Glow, Blurred: TBGRABitmap;
  Line: TGarmentLine;
  Index: integer;
  Facing: double;
  Ends: ArrayOfTPointF;
  Color: TBGRAPixel;
  Drawn: boolean;
begin
  Glow := TBGRABitmap.Create(Layer.Width, Layer.Height, BGRAPixelTransparent);
  try
    Drawn := False;
    for Line in Piece.Edges do
    begin
      if not Line.Sewn then
        Continue;
      for Index := 1 to High(Line.Points) do
      begin
        Facing := GarmentEdgeFacing(Piece.Outline, Line.Points[Index - 1], Line.Points[Index], Light) * Light.Strength;
        if Facing < 0 then
          Color := BGRA(0, 0, 0, Round(-Facing * EDGE_SHADOW_ALPHA))
        else
          Color := BGRA(255, 255, 255, Round(Facing * EDGE_HIGHLIGHT_ALPHA));
        if Color.alpha = 0 then
          Continue;
        Ends := ToPixels(Frame, [Line.Points[Index - 1], Line.Points[Index]], -OriginX, -OriginY);
        Glow.DrawLineAntialias(Ends[0].X, Ends[0].Y, Ends[1].X, Ends[1].Y, Color, EDGE_GLOW_WIDTH);
        Drawn := True;
      end;
    end;
    if not Drawn then
      Exit;
    Blurred := Glow.FilterBlurRadial(EDGE_GLOW_BLUR, rbFast) as TBGRABitmap;
    try
      Layer.PutImage(0, 0, Blurred, dmDrawWithTransparency);
    finally
      FreeAndNil(Blurred);
    end;
  finally
    FreeAndNil(Glow);
  end;
end;

procedure DrawPieceBody(Bitmap: TBGRABitmap; const Piece: TGarmentPiece; const Frame: TGarmentFrame; const Light: TGarmentLight;
  Background: TBGRAPixel; Hovered: boolean);
var
  Left, Top, Right, Bottom, Pad: integer;
  Layer, Mask, Shadow, Blurred: TBGRABitmap;
  Shape: ArrayOfTPointF;
  Base: TMaterialColor;
  Stroke: TLine2;
  Ends: ArrayOfTPointF;
  ShadowAlpha: byte;
begin
  Pad := SHADOW_BLUR * 2 + Max(SHADOW_OFFSET_X, SHADOW_OFFSET_Y);
  Left := Floor((Piece.Bounds.MinX - Frame.Left) * Frame.Scale) - Pad;
  Top := Floor((Piece.Bounds.MinY - Frame.Top) * Frame.Scale) - Pad;
  Right := Ceil((Piece.Bounds.MaxX - Frame.Left) * Frame.Scale) + Pad;
  Bottom := Ceil((Piece.Bounds.MaxY - Frame.Top) * Frame.Scale) + Pad;
  // Off the bitmap altogether
  if (Right < 0) or (Bottom < 0) or (Left > Bitmap.Width) or (Top > Bitmap.Height) then
    Exit;
  // Only what can show, so a piece zoomed far in costs no more than the panel
  Left := Max(Left, -Pad);
  Top := Max(Top, -Pad);
  Right := Min(Right, Bitmap.Width + Pad);
  Bottom := Min(Bottom, Bitmap.Height + Pad);
  if (Right <= Left) or (Bottom <= Top) then
    Exit;
  Shape := ToPixels(Frame, Piece.Outline, -Left, -Top);
  Layer := nil;
  Mask := nil;
  Shadow := nil;
  Blurred := nil;
  try
    Mask := TBGRABitmap.Create(Right - Left, Bottom - Top, BGRABlack);
    Mask.FillPolyAntialias(Shape, BGRAWhite);

    // The shadow, under the piece
    ShadowAlpha := SHADOW_ALPHA_LIGHT;
    if IsDark(Background) then
      ShadowAlpha := SHADOW_ALPHA_DARK;
    Shadow := TBGRABitmap.Create(Right - Left, Bottom - Top, BGRAPixelTransparent);
    Shadow.FillPolyAntialias(ToPixels(Frame, Piece.Outline, SHADOW_OFFSET_X - Left, SHADOW_OFFSET_Y - Top), BGRA(0, 0, 0, ShadowAlpha));
    Blurred := Shadow.FilterBlurRadial(SHADOW_BLUR, rbFast) as TBGRABitmap;
    Bitmap.PutImage(Left, Top, Blurred, dmDrawWithTransparency);

    Layer := TBGRABitmap.Create(Right - Left, Bottom - Top, BGRAPixelTransparent);
    Base := GarmentBaseColor(Piece.Look);
    Layer.FillPolyAntialias(Shape, BGRA(Base.Red, Base.Green, Base.Blue));
    if Light.Enabled then
      ShadeLayer(Layer, Piece, Frame, Left, Top, Light);
    if Piece.Look.Filled and (Piece.Look.Fill = ffHatch) then
      for Stroke in HatchLines(Piece.Outline, HATCH_SPACING / Frame.Scale, Piece.Look.HatchAngle) do
      begin
        Ends := ToPixels(Frame, [Stroke.P1, Stroke.P2], -Left, -Top);
        Layer.DrawLineAntialias(Ends[0].X, Ends[0].Y, Ends[1].X, Ends[1].Y, BGRA(Piece.Look.Color.Red, Piece.Look.Color.Green,
          Piece.Look.Color.Blue), 1);
      end;
    if Light.Enabled then
      SeamGlow(Layer, Piece, Frame, Left, Top, Light);
    if Hovered then
      Layer.FillPolyAntialias(Shape, BGRA(255, 255, 255, HOVER_TINT_ALPHA));
    Layer.ApplyMask(Mask);
    Bitmap.PutImage(Left, Top, Layer, dmDrawWithTransparency);
  finally
    FreeAndNil(Blurred);
    FreeAndNil(Shadow);
    FreeAndNil(Layer);
    FreeAndNil(Mask);
  end;
end;

procedure DrawDashed(Bitmap: TBGRABitmap; const Points: ArrayOfTPointF; const Color: TBGRAPixel; Width: single);
begin
  Bitmap.CustomPenStyle := BGRAPenStyle(3, 2.5);
  Bitmap.DrawPolyLineAntialias(Points, Color, Width);
  // An empty style is solid
  Bitmap.CustomPenStyle := nil;
end;

procedure DrawMarker(Bitmap: TBGRABitmap; const Marker: TGarmentMarker; const Frame: TGarmentFrame);
var
  Centre: TPointF;
  Radius: single;
begin
  Centre := ToPixel(Frame, Marker.Centre);
  Radius := Max(Marker.Size * Frame.Scale, MIN_MARKER) / 2;
  if Marker.Marker = pmButton then
  begin
    Bitmap.EllipseAntialias(Centre.X, Centre.Y, Radius, Radius, InkColor, 1, BGRA(244, 244, 240));
    Bitmap.FillEllipseAntialias(Centre.X - Radius / 3, Centre.Y, Max(Radius / 7, 0.6), Max(Radius / 7, 0.6), InkColor);
    Bitmap.FillEllipseAntialias(Centre.X + Radius / 3, Centre.Y, Max(Radius / 7, 0.6), Max(Radius / 7, 0.6), InkColor);
  end
  else
    Bitmap.FillEllipseAntialias(Centre.X, Centre.Y, Radius, Radius, InkColor);
end;

procedure DrawPieceLines(Bitmap: TBGRABitmap; const Piece: TGarmentPiece; const Frame: TGarmentFrame);
var
  Line: TGarmentLine;
  Marker: TGarmentMarker;
  Inset: double;
begin
  Inset := STITCH_INSET / Frame.Scale;
  for Line in Piece.Edges do
  begin
    Bitmap.DrawPolyLineAntialias(ToPixels(Frame, Line.Points), InkColor, OUTLINE_WIDTH);
    if Line.Sewn then
      DrawDashed(Bitmap, ToPixels(Frame, GarmentInset(Piece.Outline, Line.Points, Inset)), InkColor, STITCH_WIDTH);
  end;
  for Line in Piece.Stitches do
    DrawDashed(Bitmap, ToPixels(Frame, Line.Points), InkColor, STITCH_WIDTH);
  for Marker in Piece.Markers do
    DrawMarker(Bitmap, Marker, Frame);
end;

// Over every piece, so one lying over another cannot hide them
procedure DrawPieceMarks(Bitmap: TBGRABitmap; const Piece: TGarmentPiece; const Frame: TGarmentFrame; const Marks: TGarmentMarks);
var
  Line: TGarmentLine;
begin
  // A selected seam on both its sides, wherever they are
  for Line in Piece.Edges do
    if Contains(Marks.SeamEdges, Piece.PieceKey + ':' + Line.EdgeKey) then
      Bitmap.DrawPolyLineAntialias(ToPixels(Frame, Line.Points), SeamMarkColor, SEAM_MARK_WIDTH);
  for Line in Piece.Stitches do
    if (Line.SeamKey <> '') and Contains(Marks.SeamKeys, Line.SeamKey) then
      Bitmap.DrawPolyLineAntialias(ToPixels(Frame, Line.Points), SeamMarkColor, SEAM_MARK_WIDTH);
  if Contains(Marks.SelectedPieces, Piece.PieceKey) then
    Bitmap.DrawPolygonAntialias(ToPixels(Frame, Piece.Outline), MarkColor, MARK_WIDTH);
end;

procedure DrawGarment(Bitmap: TBGRABitmap; const Scene: TGarmentScene; const Frame: TGarmentFrame; const Light: TGarmentLight;
  const Marks: TGarmentMarks; Background: TBGRAPixel);
var
  Piece: TGarmentPiece;
begin
  // Each piece whole, body and lines, before the next goes over it
  for Piece in Scene.Pieces do
  begin
    DrawPieceBody(Bitmap, Piece, Frame, Light, Background, Piece.PieceKey = Marks.HoverPiece);
    DrawPieceLines(Bitmap, Piece, Frame);
  end;
  for Piece in Scene.Pieces do
    DrawPieceMarks(Bitmap, Piece, Frame, Marks);
end;

function GarmentToPNG(const Scene: TGarmentScene; const Light: TGarmentLight; Width: integer; out Png: rawbytestring;
  out ErrorMessage: string): boolean;
var
  Image: TBGRABitmap;
  Output: TMemoryStream;
  Height: integer;
  SpanX, SpanY: double;
  Frame: TGarmentFrame;
begin
  Png := '';
  ErrorMessage := '';
  if (Width < GARMENT_PNG_MIN_WIDTH) or (Width > GARMENT_PNG_MAX_WIDTH) then
  begin
    ErrorMessage := Format(rsGarmentPngWidth, [GARMENT_PNG_MIN_WIDTH, GARMENT_PNG_MAX_WIDTH]);
    Exit(False);
  end;
  SpanX := 1;
  SpanY := 1;
  if Length(Scene.Pieces) > 0 then
  begin
    SpanX := Max(Scene.Bounds.MaxX - Scene.Bounds.MinX, 1);
    SpanY := Max(Scene.Bounds.MaxY - Scene.Bounds.MinY, 1);
  end;
  Height := EnsureRange(Round((Width - 2 * EXPORT_MARGIN) * SpanY / SpanX) + 2 * EXPORT_MARGIN, 1, GARMENT_PNG_MAX_WIDTH * 4);
  Image := nil;
  Output := nil;
  try
    try
      Image := TBGRABitmap.Create(Width, Height, BGRAWhite);
      if Length(Scene.Pieces) > 0 then
      begin
        Frame := FitGarmentFrame(Scene.Bounds, Width, Height, EXPORT_MARGIN);
        DrawGarment(Image, Scene, Frame, Light, Default(TGarmentMarks), BGRAWhite);
      end;
      Output := TMemoryStream.Create;
      Image.SaveToStreamAsPng(Output);
      SetLength(Png, Output.Size);
      if Output.Size > 0 then
        Move(Output.Memory^, Png[1], Output.Size);
      Result := True;
    except
      on Failure: Exception do
      begin
        ErrorMessage := Failure.Message;
        Result := False;
      end;
    end;
  finally
    FreeAndNil(Output);
    FreeAndNil(Image);
  end;
end;

end.
