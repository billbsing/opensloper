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

// A layout as one true-scale SVG, in millimetres from its top left, with each
// piece copy where it was placed: for plotters, laser cutters and Inkscape.
// Paper things (pages, marks, calibration, title block, sheet notes) stay out.
unit Sloper.Output.LayoutSVG;

{$mode ObjFPC}{$H+}

interface

uses
  Sloper.Output.Layout;

// The SVG, whatever problems the layout has; callers check first
function LayoutToSVG(Layout: TLayout): string;

implementation

uses
  SysUtils, Math, Sloper.Core.Geometry, Sloper.Core.MachineProfiles, Sloper.Output.DraftSVG;

const
  // Around the pieces, so that a line on the edge is drawn whole
  SheetMargin = 5;
  LabelSize = 4;
  CutWidth = 0.35;
  SeamWidth = 0.18;
  MarkWidth = 0.25;
  SeamDash = 2;
  InkColor = '#000000';

function PointText(const P: TVec2): string;
begin
  Result := SVGNumber(P.X) + ' ' + SVGNumber(P.Y);
end;

function ClosedPath(const Points: TVec2Array): string;
var
  Index: integer;
begin
  Result := '';
  for Index := 0 to High(Points) do
    if Index = 0 then
      Result := 'M ' + PointText(Points[Index])
    else
      Result := Result + ' L ' + PointText(Points[Index]);
  Result := Result + ' Z';
end;

function StrokesPath(const Strokes: TLine2Array): string;
var
  Stroke: TLine2;
begin
  Result := '';
  for Stroke in Strokes do
    Result := Result + 'M ' + PointText(Stroke.P1) + ' L ' + PointText(Stroke.P2) + ' ';
  Result := Trim(Result);
end;

function PieceGroup(const Shape: TPlacedPiece; Number: integer): string;
var
  Marks: string;
begin
  Marks := StrokesPath(Shape.Marks);
  Result := Format('<g id="piece%d" data-name="%s" fill="none" stroke="%s">', [Number, EscapeXML(Shape.Caption), InkColor]) + #10 +
    Format('<g class="cut"><path d="%s" stroke-width="%s"/></g>', [ClosedPath(Shape.CutLine), SVGNumber(CutWidth)]) + #10 +
    Format('<g class="seam"><path d="%s" stroke-width="%s" stroke-dasharray="%s %s"/></g>',
    [ClosedPath(Shape.SeamLine), SVGNumber(SeamWidth), SVGNumber(SeamDash), SVGNumber(SeamDash)]) + #10;
  if Marks <> '' then
    Result := Result + Format('<g class="marks"><path d="%s" stroke-width="%s"/></g>', [Marks, SVGNumber(MarkWidth)]) + #10;
  Result := Result + Format('<g class="label"><text x="%s" y="%s" font-family="sans-serif" font-size="%s" fill="%s" stroke="none">%s</text></g>',
    [SVGNumber(Shape.LabelAt.X), SVGNumber(Shape.LabelAt.Y), SVGNumber(LabelSize), InkColor, EscapeXML(Shape.Caption)]) + #10 + '</g>' + #10;
end;

// What one line type draws of a piece, without its style
function LineBody(const Shape: TPlacedPiece; Kind: TLineType; const Style: TLineStyle): string;
var
  Hole: TPlacedHole;
begin
  Result := '';
  case Kind of
    ltCut: Result := Format('<path d="%s"/>', [ClosedPath(Shape.CutLine)]);
    ltScore:
      if Shape.ScoreLines <> nil then
        Result := Format('<path d="%s"/>', [StrokesPath(Shape.ScoreLines)]);
    ltMark:
    begin
      Result := Format('<path d="%s"/>', [ClosedPath(Shape.SeamLine)]);
      if Shape.MarkLines <> nil then
        Result := Result + Format('<path d="%s"/>', [StrokesPath(Shape.MarkLines)]);
    end;
    ltEngrave: Result := Format('<text x="%s" y="%s" font-family="sans-serif" font-size="%s" fill="%s" stroke="none">%s</text>',
        [SVGNumber(Shape.LabelAt.X), SVGNumber(Shape.LabelAt.Y), SVGNumber(LabelSize), Style.Color, EscapeXML(Shape.Caption)]);
    ltHole:
      for Hole in Shape.Holes do
        Result := Result + Format('<circle cx="%s" cy="%s" r="%s"/>', [SVGNumber(Hole.Centre.X), SVGNumber(Hole.Centre.Y), SVGNumber(Hole.Diameter / 2)]);
  end;
end;

function MachinePieceGroup(const Shape: TPlacedPiece; Number: integer; const Profile: TMachineProfile): string;
var
  Kind: TLineType;
  Style: TLineStyle;
  Body: string;
begin
  Result := Format('<g id="piece%d" data-name="%s" fill="none">', [Number, EscapeXML(Shape.Caption)]) + #10;
  for Kind in MachineOrder do
  begin
    Style := Profile.Lines[Kind];
    Body := LineBody(Shape, Kind, Style);
    if Style.Enabled and (Body <> '') then
      Result := Result + Format('<g class="%s" data-layer="%s" stroke="%s" stroke-width="%s">%s</g>',
        [LineTypeNames[Kind], EscapeXML(Style.Layer), Style.Color, SVGNumber(Style.Width), Body]) + #10;
  end;
  Result := Result + '</g>' + #10;
end;

function LayoutToSVG(Layout: TLayout): string;
var
  Shapes: TPlacedPieceArray;
  Profile: TMachineProfile;
  ForMachine: boolean;
  Index: integer;
  Width, Height: double;
begin
  Shapes := Layout.PlacedPieces;
  ForMachine := (Layout.Output.Profile <> '') and Layout.ChosenProfile(Profile);
  Width := 0;
  Height := 0;
  for Index := 0 to High(Shapes) do
  begin
    Width := Max(Width, Shapes[Index].Bounds.MaxX);
    Height := Max(Height, Shapes[Index].Bounds.MaxY);
  end;
  Width := Width + 2 * SheetMargin;
  Height := Height + 2 * SheetMargin;
  Result := '<?xml version="1.0" encoding="UTF-8"?>' + #10 +
    Format('<svg xmlns="http://www.w3.org/2000/svg" width="%smm" height="%smm" viewBox="%s %s %s %s">',
    [SVGNumber(Width), SVGNumber(Height), SVGNumber(-SheetMargin), SVGNumber(-SheetMargin), SVGNumber(Width), SVGNumber(Height)]) + #10;
  for Index := 0 to High(Shapes) do
    if ForMachine then
      Result := Result + MachinePieceGroup(Shapes[Index], Index + 1, Profile)
    else
      Result := Result + PieceGroup(Shapes[Index], Index + 1);
  Result := Result + '</svg>' + #10;
end;

end.
