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

// The draft as an SVG, to look at or to check: edges as true lines and Bézier
// curves, points, and optionally their names. Coordinates are millimetres with
// y flipped, since SVG's y points down. Reads computed geometry only.
unit Sloper.Output.DraftSVG;

{$mode ObjFPC}{$H+}

interface

uses
  Sloper.Core.Geometry, Sloper.Core.Pattern;

type
  TDraftSVGOptions = record
    Labels: boolean;
    // Show only this part of the draft, in model millimetres
    HasRegion: boolean;
    Region: TRect2;
  end;

function DefaultDraftSVGOptions: TDraftSVGOptions;
function DraftToSVG(Pattern: TPattern; const Options: TDraftSVGOptions): string;

implementation

uses
  SysUtils, Math, Sloper.Core.Bezier, Sloper.Core.Bounds, Sloper.Core.Drag, Sloper.Core.EvalTypes, Sloper.Core.Draft;

const
  CoordinateDecimals = 3;
  // Of the longer side, so a drawing reads the same at any size
  LineShare = 0.0015;
  ConstructionShare = 0.0008;
  PointShare = 0.003;
  FontShare = 0.014;
  MarginShare = 0.05;
  MinimumExtent = 10;
  EmptyExtent = 100;
  InkColor = '#202020';
  ConstructionColor = '#808080';
  ErrorColor = '#c02020';
  BlockedColor = '#e08000';

function DefaultDraftSVGOptions: TDraftSVGOptions;
begin
  Result := Default(TDraftSVGOptions);
end;

function Num(Value: double): string;
begin
  Result := RoundedText(Value, CoordinateDecimals);
end;

// Model y points up, SVG y points down
function Coord(const P: TVec2): string;
begin
  Result := Num(P.X) + ' ' + Num(-P.Y);
end;

function EscapeXML(const Text: string): string;
begin
  Result := StringReplace(Text, '&', '&amp;', [rfReplaceAll]);
  Result := StringReplace(Result, '<', '&lt;', [rfReplaceAll]);
  Result := StringReplace(Result, '>', '&gt;', [rfReplaceAll]);
  Result := StringReplace(Result, '"', '&quot;', [rfReplaceAll]);
end;

function StateColor(State: TEvalState; const Normal: string): string;
begin
  case State of
    esError, esInvalid: Result := ErrorColor;
    esBlocked: Result := BlockedColor;
    else
      Result := Normal;
  end;
end;

function EdgePath(Edge: TEdgeObject): string;
var
  Segment: TEdgeSegment;
  First: boolean;
begin
  Result := '';
  First := True;
  for Segment in Edge.Segments do
    if Segment.Kind = skLine then
    begin
      if First then
        Result := 'M ' + Coord(Segment.Line.P1);
      Result := Result + ' L ' + Coord(Segment.Line.P2);
      First := False;
    end
    else
    begin
      if First then
        Result := 'M ' + Coord(Segment.Curve.P0);
      Result := Result + ' C ' + Coord(Segment.Curve.P1) + ' ' + Coord(Segment.Curve.P2) + ' ' + Coord(Segment.Curve.P3);
      First := False;
    end;
end;

function DraftToSVG(Pattern: TPattern; const Options: TDraftSVGOptions): string;
var
  Bounds: TRect2;
  Extent, Margin, Left, Top, Width, Height, Stroke: double;
  Index: integer;
  DraftObject: TDraftObject;
  Edge: TEdgeObject;
  Point: TPointObject;
  Color, Dash: string;
begin
  if Options.HasRegion then
    Bounds := Options.Region
  else if not PatternBounds(Pattern, Bounds) then
  begin
    Bounds := Default(TRect2);
    Bounds.MaxX := EmptyExtent;
    Bounds.MaxY := EmptyExtent;
  end;
  Extent := Max(Max(Bounds.MaxX - Bounds.MinX, Bounds.MaxY - Bounds.MinY), MinimumExtent);
  Margin := 0;
  if not Options.HasRegion then
    Margin := Extent * MarginShare;
  Left := Bounds.MinX - Margin;
  Top := -Bounds.MaxY - Margin;
  Width := Bounds.MaxX - Bounds.MinX + 2 * Margin;
  Height := Bounds.MaxY - Bounds.MinY + 2 * Margin;

  Result := Format('<svg xmlns="http://www.w3.org/2000/svg" width="%smm" height="%smm" viewBox="%s %s %s %s">',
    [Num(Width), Num(Height), Num(Left), Num(Top), Num(Width), Num(Height)]) + #10;
  Result := Result + Format('<rect x="%s" y="%s" width="%s" height="%s" fill="#ffffff"/>', [Num(Left), Num(Top), Num(Width), Num(Height)]) + #10;

  // Edges under points
  for Index := 0 to Pattern.ObjectCount - 1 do
  begin
    DraftObject := Pattern.Objects[Index];
    if not (DraftObject is TEdgeObject) or not DraftObject.HasResult then
      Continue;
    Edge := TEdgeObject(DraftObject);
    if Edge.Segments = nil then
      Continue;
    Dash := '';
    if Edge.Role = erOutline then
    begin
      Color := InkColor;
      Stroke := Extent * LineShare;
    end
    else
    begin
      Color := ConstructionColor;
      Stroke := Extent * ConstructionShare;
      Dash := Format(' stroke-dasharray="%s %s"', [Num(Stroke * 4), Num(Stroke * 3)]);
    end;
    Result := Result + Format('<path data-id="%s" data-name="%s" d="%s" fill="none" stroke="%s" stroke-width="%s"%s/>',
      [Edge.Key, EscapeXML(Edge.DisplayName), EdgePath(Edge), StateColor(Edge.State, Color), Num(Stroke), Dash]) + #10;
  end;

  for Index := 0 to Pattern.ObjectCount - 1 do
  begin
    DraftObject := Pattern.Objects[Index];
    if not (DraftObject is TPointObject) or not DraftObject.HasResult then
      Continue;
    Point := TPointObject(DraftObject);
    Result := Result + Format('<circle data-id="%s" data-name="%s" cx="%s" cy="%s" r="%s" fill="%s"/>',
      [Point.Key, EscapeXML(Point.DisplayName), Num(Point.Position.X), Num(-Point.Position.Y), Num(Extent * PointShare),
      StateColor(Point.State, InkColor)]) + #10;
    if Options.Labels then
      Result := Result + Format('<text x="%s" y="%s" font-family="sans-serif" font-size="%s" fill="%s">%s</text>',
        [Num(Point.Position.X + Extent * PointShare * 1.5), Num(-Point.Position.Y - Extent * PointShare * 1.5), Num(Extent * FontShare),
        StateColor(Point.State, InkColor), EscapeXML(Point.DisplayName)]) + #10;
  end;
  Result := Result + '</svg>' + #10;
end;

end.
