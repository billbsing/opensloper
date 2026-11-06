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
// curves, points, and optionally their names. Coordinates are millimetres
// as in the model, since both have y down. Reads computed geometry only.
unit Sloper.Output.DraftSVG;

{$mode ObjFPC}{$H+}

interface

uses
  SysUtils, Sloper.Core.Evaluator, Sloper.Core.Geometry, Sloper.Core.Draft, Sloper.Core.Pattern;

type
  TDraftSVGOptions = record
    // Names every point, edge and piece, as the canvas's All labels
    Labels: boolean;
    // Names only these objects, as the canvas was showing them; Labels is
    // then ignored
    LabelChosen: boolean;
    LabelKeys: TStringArray;
    // Pieces are left unfilled, as with View -> Piece Fills off
    NoFills: boolean;
    // Show only this part of the draft, in model millimetres
    HasRegion: boolean;
    Region: TRect2;
    // Lines of these roles are left out, as the canvas hides them
    HiddenRoles: TEdgeRoles;
    // Notes are left out, as View -> Annotations off hides them
    HideAnnotations: boolean;
    // For {pattern.name} in notes; empty leaves it as typed
    PatternFileName: string;
  end;

function DefaultDraftSVGOptions: TDraftSVGOptions;
function DraftToSVG(Pattern: TPattern; const Options: TDraftSVGOptions): string;
// A number as written in SVG
function SVGNumber(Value: double): string;
function EscapeXML(const Text: string): string;

implementation

uses
  Math, Sloper.Core.Bezier, Sloper.Core.Bounds, Sloper.Core.Drag, Sloper.Core.EvalTypes, Sloper.Core.Fabrics, Sloper.Core.Piece,
  Sloper.Core.Note, Sloper.Core.TextFields;

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

type
  TDraftView = record
    Left, Top, Width, Height, Extent: double;
  end;

function DefaultDraftSVGOptions: TDraftSVGOptions;
begin
  Result := Default(TDraftSVGOptions);
end;

function SVGNumber(Value: double): string;
begin
  Result := RoundedText(Value, CoordinateDecimals);
end;

function Num(Value: double): string;
begin
  Result := SVGNumber(Value);
end;

// Model and SVG both have y down
function Coord(const P: TVec2): string;
begin
  Result := Num(P.X) + ' ' + Num(P.Y);
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

// The part of the drawing shown, in millimetres. Extent is the
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
  else
    Found := PatternBounds(Pattern, Bounds, not Options.HideAnnotations);
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
  Result.Top := Bounds.MinY - Margin;
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
  Stroke, Length: double;
begin
  Dash := '';
  case Edge.Role of
    erOutline:
    begin
      Color := InkColor;
      Stroke := Extent * LineShare;
    end;
    erConstruction:
    begin
      Color := ConstructionColor;
      Stroke := Extent * ConstructionShare;
      Dash := Format(' stroke-dasharray="%s %s"', [Num(Stroke * 4), Num(Stroke * 3)]);
    end;
    else
    begin
      // A marking line in its role's colour, dashed as on paper but scaled
      // with the drawing, like the other lines
      Color := RoleColors[Edge.Role];
      Stroke := Extent * LineShare * 0.75;
      for Length in RoleDashes[Edge.Role] do
        if Length > 0 then
          Dash := Dash + ' ' + Num(Length * Stroke * 2);
      if Dash <> '' then
        Dash := Format(' stroke-dasharray="%s"', [Trim(Dash)]);
    end;
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
    [Num(Middle.X), Num(Middle.Y), Num(Extent * FontShare), StateColor(Piece.State, InkColor), EscapeXML(Pattern.PieceCaption(Piece))]) + #10;
end;

function LabelElement(const At: TVec2; Extent: double; const Color, Text: string): string;
var
  Offset: double;
begin
  Offset := Extent * PointShare * 1.5;
  Result := Format('<text x="%s" y="%s" font-family="sans-serif" font-size="%s" fill="%s">%s</text>',
    [Num(At.X + Offset), Num(At.Y - Offset), Num(Extent * FontShare), Color, EscapeXML(Text)]) + #10;
end;

// Halfway along the edge, where the canvas puts its name
function EdgeLabelElement(Edge: TEdgeObject; Extent: double): string;
begin
  Result := LabelElement(Edge.PointAtLength(Edge.Length / 2), Extent, StateColor(Edge.State, InkColor), Edge.DisplayName);
end;

function PointElement(Point: TPointObject; Extent: double; Labels: boolean): string;
var
  Radius: double;
  Color: string;
begin
  Radius := Extent * PointShare;
  Color := StateColor(Point.State, InkColor);
  Result := Format('<circle data-id="%s" data-name="%s" cx="%s" cy="%s" r="%s" fill="%s"/>',
    [Point.Key, EscapeXML(Point.DisplayName), Num(Point.Position.X), Num(Point.Position.Y), Num(Radius), Color]) + #10;
  if Labels then
    Result := Result + LabelElement(Point.Position, Extent, Color, Point.DisplayName);
end;

// A point's or repeat's marker, whether or not it is on a piece yet
function MarkerElement(DraftObject: TDraftObject; Extent: double): string;
var
  Centre: TVec2;
  Stroke: TLine2;
  PathText: string;
begin
  PathText := '';
  if DraftObject.MarkerSize > 0 then
    for Centre in MarkerPositions(DraftObject) do
      for Stroke in MarkerStrokes(DraftObject.Marker, Centre, DraftObject.MarkerSize) do
        PathText := PathText + 'M ' + Coord(Stroke.P1) + ' L ' + Coord(Stroke.P2) + ' ';
  Result := '';
  if PathText <> '' then
    Result := Format('<path data-id="%s" data-marker="%s" d="%s" fill="none" stroke="%s" stroke-width="%s"/>',
      [DraftObject.Key, PointMarkerNames[DraftObject.Marker], Trim(PathText), StateColor(DraftObject.State, InkColor),
      Num(Extent * LineShare)]) + #10;
end;

// At its true printed size, a text element per line, over everything else
function NoteElement(Note: TNoteObject; const Values: TFieldValues): string;
var
  Lines: TStringArray;
  Index: integer;
begin
  Result := '';
  Lines := TextLines(ExpandFields(Note.Text, Values));
  for Index := 0 to High(Lines) do
    Result := Result + Format('<text data-id="%s" x="%s" y="%s" font-family="Helvetica, Arial, sans-serif" font-size="%s" fill="%s">%s</text>',
      [Note.Key, Num(Note.Position.X), Num(Note.Position.Y + (Index + 1) * LineHeight(Note.Size)), Num(Note.Size * PointsToMM),
      StateColor(Note.State, InkColor), EscapeXML(Lines[Index])]) + #10;
end;

function AllObjects(Pattern: TPattern): TDraftObjectArray;
var
  Index: integer;
begin
  Result := nil;
  SetLength(Result, Pattern.ObjectCount);
  for Index := 0 to Pattern.ObjectCount - 1 do
    Result[Index] := Pattern.Objects[Index];
end;

function DraftToSVG(Pattern: TPattern; const Options: TDraftSVGOptions): string;
var
  View: TDraftView;
  Index: integer;
  DraftObject: TDraftObject;
  Point: TPointObject;

  function Labelled(DraftObject: TDraftObject): boolean;
  var
    Key: string;
  begin
    if not Options.LabelChosen then
      Exit(Options.Labels);
    for Key in Options.LabelKeys do
      if Key = DraftObject.Key then
        Exit(True);
    Result := False;
  end;

begin
  View := DraftView(Pattern, Options);
  Result := SVGStart(View);
  // Pieces under edges, edges under points
  for Index := 0 to Pattern.ObjectCount - 1 do
  begin
    DraftObject := Pattern.Objects[Index];
    if (DraftObject is TPieceObject) and DraftObject.HasResult then
      Result := Result + PieceElement(Pattern, TPieceObject(DraftObject), View.Extent, Options.NoFills);
  end;
  for DraftObject in EdgesInDrawOrder(AllObjects(Pattern)) do
  begin
    if DraftObject.HasResult and (Length(TEdgeObject(DraftObject).Segments) > 0) and not (TEdgeObject(DraftObject).Role in Options.HiddenRoles) then
    begin
      Result := Result + EdgeElement(TEdgeObject(DraftObject), View.Extent);
      if Labelled(DraftObject) then
        Result := Result + EdgeLabelElement(TEdgeObject(DraftObject), View.Extent);
    end;
  end;
  for Index := 0 to Pattern.ObjectCount - 1 do
  begin
    DraftObject := Pattern.Objects[Index];
    if (DraftObject is TPieceObject) and DraftObject.HasResult then
    begin
      Result := Result + PieceMarksElement(TPieceObject(DraftObject), View.Extent);
      if Labelled(DraftObject) then
        Result := Result + PieceLabelElement(Pattern, TPieceObject(DraftObject), View.Extent);
    end;
  end;
  for Index := 0 to Pattern.ObjectCount - 1 do
  begin
    DraftObject := Pattern.Objects[Index];
    if (DraftObject.Marker <> pmPlain) and DraftObject.HasResult then
      Result := Result + MarkerElement(DraftObject, View.Extent);
  end;
  for Point in Pattern.AllPoints do
    if Point.HasResult then
      Result := Result + PointElement(Point, View.Extent, Labelled(Point));
  // Screen-only notes never leave the app
  if not Options.HideAnnotations then
    for Index := 0 to Pattern.ObjectCount - 1 do
    begin
      DraftObject := Pattern.Objects[Index];
      if (DraftObject is TNoteObject) and DraftObject.HasResult and TNoteObject(DraftObject).Print then
        Result := Result + NoteElement(TNoteObject(DraftObject), PatternFieldValues(Pattern, Options.PatternFileName));
    end;
  Result := Result + '</svg>' + #10;
end;

end.
