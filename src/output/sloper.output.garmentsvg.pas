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

// A garment view as SVG, in millimetres with y flipped, for the Automation API,
// and both views on one sheet, for the Garment window's export.
unit Sloper.Output.GarmentSVG;

{$mode ObjFPC}{$H+}

interface

uses
  Sloper.Core.Garment;

function GarmentToSVG(const Drawing: TGarmentDrawing): string;
// Front and back side by side at true scale, each under its title. A view with
// nothing in it is left out.
function GarmentSheetToSVG(const Front, Back: TGarmentDrawing; const FrontTitle, BackTitle: string): string;

implementation

uses
  SysUtils, Sloper.Core.Geometry, Sloper.Core.Fabrics, Sloper.Output.DraftSVG;

const
  SheetMargin = 10;
  EmptySize = 100;
  LineWidth = 0.6;
  InkColor = '#202020';
  HatchSpacing = 8;
  SideGap = 60;
  TitleRoom = 24;
  TitleSize = 16;

function PointText(const P: TVec2): string;
begin
  Result := SVGNumber(P.X) + ' ' + SVGNumber(-P.Y);
end;

function PathText(const Points: TVec2Array; Closed: boolean): string;
var
  Index: integer;
begin
  Result := '';
  for Index := 0 to High(Points) do
    if Index = 0 then
      Result := 'M ' + PointText(Points[Index])
    else
      Result := Result + ' L ' + PointText(Points[Index]);
  if Closed then
    Result := Result + ' Z';
end;

function ShapeElement(const Shape: TGarmentShape): string;
var
  Line: TVec2Array;
  Stroke: TLine2;
  FillText: string;
begin
  FillText := 'none';
  if Shape.Look.Filled and (Shape.Look.Fill = ffTint) then
    FillText := LowerCase(FabricColorText(FabricTint(Shape.Look.Color)));
  Result := Format('<g data-name="%s"><path d="%s" fill="%s" stroke="none"/>', [EscapeXML(Shape.PieceName), PathText(Shape.Outline, True), FillText]) + #10;
  if Shape.Look.Filled and (Shape.Look.Fill = ffHatch) then
    for Stroke in HatchLines(Shape.Outline, HatchSpacing, Shape.Look.HatchAngle) do
      Result := Result + Format('<path d="M %s L %s" fill="none" stroke="%s" stroke-width="%s"/>',
        [PointText(Stroke.P1), PointText(Stroke.P2), LowerCase(FabricColorText(Shape.Look.Color)), SVGNumber(LineWidth / 2)]) + #10;
  for Line in Shape.Lines do
    Result := Result + Format('<path d="%s" fill="none" stroke="%s" stroke-width="%s"/>', [PathText(Line, False), InkColor, SVGNumber(LineWidth)]) + #10;
  Result := Result + '</g>' + #10;
end;

function GarmentToSVG(const Drawing: TGarmentDrawing): string;
var
  Shape: TGarmentShape;
  Left, Top, Width, Height: double;
begin
  Left := Drawing.Bounds.MinX - SheetMargin;
  Top := -Drawing.Bounds.MaxY - SheetMargin;
  Width := Drawing.Bounds.MaxX - Drawing.Bounds.MinX + 2 * SheetMargin;
  Height := Drawing.Bounds.MaxY - Drawing.Bounds.MinY + 2 * SheetMargin;
  if Drawing.Shapes = nil then
  begin
    Left := 0;
    Top := 0;
    Width := EmptySize;
    Height := EmptySize;
  end;
  Result := Format('<svg xmlns="http://www.w3.org/2000/svg" width="%smm" height="%smm" viewBox="%s %s %s %s">',
    [SVGNumber(Width), SVGNumber(Height), SVGNumber(Left), SVGNumber(Top), SVGNumber(Width), SVGNumber(Height)]) + #10;
  for Shape in Drawing.Shapes do
    Result := Result + ShapeElement(Shape);
  Result := Result + '</svg>' + #10;
end;

function GarmentSheetToSVG(const Front, Back: TGarmentDrawing; const FrontTitle, BackTitle: string): string;
var
  Body: string;
  Across, Tallest: double;

// Puts the view's top left at (Across, below the title), and moves Across on
  procedure AddSide(const Drawing: TGarmentDrawing; const SideName, Title: string);
  var
    Shape: TGarmentShape;
    OffsetX, OffsetY: double;
  begin
    if Drawing.Shapes = nil then
      Exit;
    if Body <> '' then
      Across := Across + SideGap;
    OffsetX := Across - Drawing.Bounds.MinX;
    OffsetY := SheetMargin + TitleRoom + Drawing.Bounds.MaxY;
    Body := Body + Format('<text x="%s" y="%s" font-family="sans-serif" font-size="%s" fill="%s">%s</text>',
      [SVGNumber(Across), SVGNumber(SheetMargin + TitleSize), SVGNumber(TitleSize), InkColor, EscapeXML(Title)]) + #10;
    Body := Body + Format('<g data-side="%s" transform="translate(%s %s)">', [SideName, SVGNumber(OffsetX), SVGNumber(OffsetY)]) + #10;
    for Shape in Drawing.Shapes do
      Body := Body + ShapeElement(Shape);
    Body := Body + '</g>' + #10;
    Across := Across + Drawing.Bounds.MaxX - Drawing.Bounds.MinX;
    if Drawing.Bounds.MaxY - Drawing.Bounds.MinY > Tallest then
      Tallest := Drawing.Bounds.MaxY - Drawing.Bounds.MinY;
  end;

var
  Width, Height: double;
begin
  Body := '';
  Across := SheetMargin;
  Tallest := 0;
  AddSide(Front, 'front', FrontTitle);
  AddSide(Back, 'back', BackTitle);
  Width := Across + SheetMargin;
  Height := 2 * SheetMargin + TitleRoom + Tallest;
  if Body = '' then
  begin
    Width := EmptySize;
    Height := EmptySize;
  end;
  Result := Format('<svg xmlns="http://www.w3.org/2000/svg" width="%smm" height="%smm" viewBox="0 0 %s %s">',
    [SVGNumber(Width), SVGNumber(Height), SVGNumber(Width), SVGNumber(Height)]) + #10 + Body + '</svg>' + #10;
end;

end.
