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

// A garment view as SVG, in millimetres with y flipped, for the Automation API.
unit Sloper.Output.GarmentSVG;

{$mode ObjFPC}{$H+}

interface

uses
  Sloper.Core.Garment;

function GarmentToSVG(const Drawing: TGarmentDrawing): string;

implementation

uses
  SysUtils, Sloper.Core.Geometry, Sloper.Output.DraftSVG;

const
  SheetMargin = 10;
  EmptySize = 100;
  LineWidth = 0.6;
  InkColor = '#202020';
  TintColor = '#f3efe6';

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
begin
  Result := Format('<g data-name="%s"><path d="%s" fill="%s" stroke="none"/>', [EscapeXML(Shape.PieceName), PathText(Shape.Outline, True), TintColor]) + #10;
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

end.
