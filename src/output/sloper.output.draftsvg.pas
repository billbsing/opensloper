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
  Sloper.Core.Evaluator, Sloper.Core.Geometry, Sloper.Core.Pattern;

type
  TDraftSVGOptions = record
    Labels: boolean;
    // As the canvas shows it: hidden layers and everything outside a solo layer
    // are left out. Hiding never changes output otherwise, but this is a
    // picture of the working view.
    ShownOnly: boolean;
    // Pieces are left unfilled, as with View -> Piece Fills off
    NoFills: boolean;
    // Show only this part of the draft, in model millimetres
    HasRegion: boolean;
    Region: TRect2;
  end;

function DefaultDraftSVGOptions: TDraftSVGOptions;
function DraftToSVG(Pattern: TPattern; const Options: TDraftSVGOptions): string;
// A file name for one draft: the pattern's alone when it has only that draft
function DraftSVGFileName(const PatternName, DraftName: string; DraftCount: integer): string;
// A number as written in SVG
function SVGNumber(Value: double): string;
function EscapeXML(const Text: string): string;

implementation

uses
  SysUtils, Math, Sloper.Core.Bezier, Sloper.Core.Bounds, Sloper.Core.Drag, Sloper.Core.EvalTypes, Sloper.Core.Draft, Sloper.Core.Fabrics, Sloper.Core.Piece;

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
  // Share of the view's size between hatching lines
  HatchShare = 0.012;
  SVGFileExtension = '.svg';

type
  TDraftView = record
    Left, Top, Width, Height, Extent: double;
  end;

function DefaultDraftSVGOptions: TDraftSVGOptions;
begin
  Result := Default(TDraftSVGOptions);
end;

function DraftSVGFileName(const PatternName, DraftName: string; DraftCount: integer): string;
const
  SlashChars = ['/', '\'];
var
  Index: integer;
  Safe: string;
begin
  Result := PatternName + SVGFileExtension;
  if DraftCount < 2 then
    Exit;
  // A draft's name may hold anything, and must not start another folder
  Safe := DraftName;
  for Index := 1 to Length(Safe) do
    if Safe[Index] in SlashChars then
      Safe[Index] := '_';
  Result := PatternName + '-' + Safe + SVGFileExtension;
end;

function SVGNumber(Value: double): string;
begin
  Result := RoundedText(Value, CoordinateDecimals);
end;

function Num(Value: double): string;
begin
  Result := SVGNumber(Value);
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

function IsDrawn(Pattern: TPattern; Node: TEvalNode; const Options: TDraftSVGOptions): boolean;
begin
  if Options.ShownOnly then
    Result := Pattern.IsShown(Node)
  else
    Result := Pattern.InActiveDraft(Node);
end;

function ShownBounds(Pattern: TPattern; out Bounds: TRect2): boolean;
var
  Index: integer;
  Empty: boolean;
begin
  Bounds := Default(TRect2);
  Empty := True;
  for Index := 0 to Pattern.ObjectCount - 1 do
    if Pattern.IsShown(Pattern.Objects[Index]) then
      IncludeObject(Bounds, Empty, Pattern.Objects[Index]);
  Result := not Empty;
end;

// The part of the drawing shown, in SVG's y-down millimetres. Extent is the
// longer side, which line widths and text sizes are shares of.
function DraftView(Pattern: TPattern; const Options: TDraftSVGOptions): TDraftView;
var
  Bounds: TRect2;
  Margin: double;
  Found: boolean;
begin
  Found := True;
  if Options.HasRegion then
    Bounds := Options.Region
  else if Options.ShownOnly then
    Found := ShownBounds(Pattern, Bounds)
  else
    Found := PatternBounds(Pattern, Bounds);
  if not Found then
  begin
    Bounds := Default(TRect2);
    Bounds.MaxX := EmptyExtent;
    Bounds.MaxY := EmptyExtent;
  end;
  Result.Extent := Max(Max(Bounds.MaxX - Bounds.MinX, Bounds.MaxY - Bounds.MinY), MinimumExtent);
  Margin := 0;
  if not Options.HasRegion then
    Margin := Result.Extent * MarginShare;
  Result.Left := Bounds.MinX - Margin;
  Result.Top := -Bounds.MaxY - Margin;
  Result.Width := Bounds.MaxX - Bounds.MinX + 2 * Margin;
  Result.Height := Bounds.MaxY - Bounds.MinY + 2 * Margin;
end;

function SVGStart(const View: TDraftView): string;
begin
  Result := Format('<svg xmlns="http://www.w3.org/2000/svg" width="%smm" height="%smm" viewBox="%s %s %s %s">',
    [Num(View.Width), Num(View.Height), Num(View.Left), Num(View.Top), Num(View.Width), Num(View.Height)]) + #10 +
    Format('<rect x="%s" y="%s" width="%s" height="%s" fill="#ffffff"/>', [Num(View.Left), Num(View.Top), Num(View.Width), Num(View.Height)]) + #10;
end;

function EdgeElement(Edge: TEdgeObject; Extent: double): string;
var
  Color, Dash: string;
  Stroke: double;
begin
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
  Result := Format('<path data-id="%s" data-name="%s" d="%s" fill="none" stroke="%s" stroke-width="%s"%s/>',
    [Edge.Key, EscapeXML(Edge.DisplayName), EdgePath(Edge), StateColor(Edge.State, Color), Num(Stroke), Dash]) + #10;
end;

// The cutting line, filled, so the edges drawn over it show the seam line
function PieceElement(Pattern: TPattern; Piece: TPieceObject; Extent: double; NoFills: boolean): string;
var
  Index: integer;
  PathText, FillText, HatchText: string;
  Look: TPieceLook;
  Stroke: TLine2;
begin
  Look := Pattern.PieceLook(Piece);
  if NoFills then
    Look.Filled := False;
  FillText := 'none';
  if Look.Filled and (Look.Fill = ffTint) then
    FillText := LowerCase(FabricColorText(FabricTint(Look.Color)));
  PathText := '';
  for Index := 0 to High(Piece.CutLine) do
    if Index = 0 then
      PathText := 'M ' + Coord(Piece.CutLine[Index])
    else
      PathText := PathText + ' L ' + Coord(Piece.CutLine[Index]);
  Result := Format('<path data-id="%s" data-name="%s" d="%s Z" fill="%s" stroke="%s" stroke-width="%s"/>',
    [Piece.Key, EscapeXML(Piece.DisplayName), PathText, FillText, StateColor(Piece.State, InkColor), Num(Extent * LineShare)]) + #10;
  if not Look.Filled or (Look.Fill <> ffHatch) then
    Exit;
  HatchText := '';
  for Stroke in HatchLines(Piece.CutLine, Extent * HatchShare, Look.HatchAngle) do
    HatchText := HatchText + 'M ' + Coord(Stroke.P1) + ' L ' + Coord(Stroke.P2) + ' ';
  if HatchText <> '' then
    Result := Result + Format('<path data-id="%s" data-hatch="%s" d="%s" fill="none" stroke="%s" stroke-width="%s"/>',
      [Piece.Key, EscapeXML(Piece.DisplayName), Trim(HatchText), LowerCase(FabricColorText(Look.Color)), Num(Extent * LineShare)]) + #10;
end;

// The grainline and notches, over the edges
function PieceMarksElement(Piece: TPieceObject; Extent: double): string;
var
  Stroke: TLine2;
  Mark: TNotchMark;
  PathText: string;
begin
  PathText := '';
  for Stroke in Concat(Piece.GrainArrow, Piece.FoldArrow, Piece.MarkingStrokes) do
    PathText := PathText + 'M ' + Coord(Stroke.P1) + ' L ' + Coord(Stroke.P2) + ' ';
  for Mark in Piece.NotchMarks do
    PathText := PathText + 'M ' + Coord(Mark.Cut) + ' L ' + Coord(Mark.Tip) + ' ';
  Result := '';
  if PathText <> '' then
    Result := Format('<path data-id="%s" data-marks="%s" d="%s" fill="none" stroke="%s" stroke-width="%s"/>',
      [Piece.Key, EscapeXML(Piece.DisplayName), Trim(PathText), StateColor(Piece.State, InkColor), Num(Extent * LineShare)]) + #10;
end;

function PieceLabelElement(Pattern: TPattern; Piece: TPieceObject; Extent: double): string;
var
  Middle: TVec2;
begin
  Middle := Piece.Middle;
  Result := Format('<text x="%s" y="%s" font-family="sans-serif" font-size="%s" fill="%s">%s</text>',
    [Num(Middle.X), Num(-Middle.Y), Num(Extent * FontShare), StateColor(Piece.State, InkColor), EscapeXML(Pattern.PieceCaption(Piece))]) + #10;
end;

function PointElement(Point: TPointObject; Extent: double; Labels: boolean): string;
var
  Radius: double;
  Color: string;
begin
  Radius := Extent * PointShare;
  Color := StateColor(Point.State, InkColor);
  Result := Format('<circle data-id="%s" data-name="%s" cx="%s" cy="%s" r="%s" fill="%s"/>',
    [Point.Key, EscapeXML(Point.DisplayName), Num(Point.Position.X), Num(-Point.Position.Y), Num(Radius), Color]) + #10;
  if Labels then
    Result := Result + Format('<text x="%s" y="%s" font-family="sans-serif" font-size="%s" fill="%s">%s</text>',
      [Num(Point.Position.X + Radius * 1.5), Num(-Point.Position.Y - Radius * 1.5), Num(Extent * FontShare), Color,
      EscapeXML(Point.DisplayName)]) + #10;
end;

function DraftToSVG(Pattern: TPattern; const Options: TDraftSVGOptions): string;
var
  View: TDraftView;
  Index: integer;
  DraftObject: TDraftObject;
  Point: TPointObject;
begin
  View := DraftView(Pattern, Options);
  Result := SVGStart(View);
  // Pieces under edges, edges under points
  for Index := 0 to Pattern.ObjectCount - 1 do
  begin
    DraftObject := Pattern.Objects[Index];
    if (DraftObject is TPieceObject) and DraftObject.HasResult and IsDrawn(Pattern, DraftObject, Options) then
      Result := Result + PieceElement(Pattern, TPieceObject(DraftObject), View.Extent, Options.NoFills);
  end;
  for Index := 0 to Pattern.ObjectCount - 1 do
  begin
    DraftObject := Pattern.Objects[Index];
    if (DraftObject is TEdgeObject) and DraftObject.HasResult and (TEdgeObject(DraftObject).Segments <> nil) and IsDrawn(Pattern, DraftObject, Options) then
      Result := Result + EdgeElement(TEdgeObject(DraftObject), View.Extent);
  end;
  for Index := 0 to Pattern.ObjectCount - 1 do
  begin
    DraftObject := Pattern.Objects[Index];
    if (DraftObject is TPieceObject) and DraftObject.HasResult and IsDrawn(Pattern, DraftObject, Options) then
    begin
      Result := Result + PieceMarksElement(TPieceObject(DraftObject), View.Extent);
      if Options.Labels then
        Result := Result + PieceLabelElement(Pattern, TPieceObject(DraftObject), View.Extent);
    end;
  end;
  for Point in Pattern.AllPoints do
    if Point.HasResult and IsDrawn(Pattern, Point, Options) then
      Result := Result + PointElement(Point, View.Extent, Options.Labels);
  Result := Result + '</svg>' + #10;
end;

end.
