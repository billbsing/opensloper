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
  SysUtils, Math, Sloper.Core.Geometry, Sloper.Core.Draft, Sloper.Core.MachineProfiles, Sloper.Core.TextFields, Sloper.Core.Note, Sloper.Output.DraftSVG;

const
  // Around the pieces, so that a line on the edge is drawn whole
  SHEET_MARGIN = 5;
  LABEL_SIZE = 4;
  CUT_WIDTH = 0.35;
  SEAM_WIDTH = 0.18;
  MARK_WIDTH = 0.25;
  SEAM_DASH = 2;
  INK_COLOR = '#000000';

function PointText(const Point: TVec2): string;
begin
  Result := SVGNumber(Point.X) + ' ' + SVGNumber(Point.Y);
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

function OpenPath(const Points: TVec2Array): string;
var
  Index: integer;
begin
  Result := '';
  for Index := 0 to High(Points) do
    if Index = 0 then
      Result := 'M ' + PointText(Points[Index])
    else
      Result := Result + ' L ' + PointText(Points[Index]);
end;

function DashText(const Dashes: TDashPattern): string;
var
  Length: double;
begin
  Result := '';
  for Length in Dashes do
    if Length > 0 then
      Result := Result + ' ' + SVGNumber(Length);
  if Result <> '' then
    Result := Format(' stroke-dasharray="%s"', [Trim(Result)]);
end;

function DashArray(Role: TEdgeRole): string;
begin
  Result := DashText(ROLE_DASHES[Role]);
end;

// One group per role, as the roles print differently
function LinesGroup(const Shape: TPlacedPiece): string;
var
  Line: TPlacedLine;
  Width: double;
begin
  Result := '';
  for Line in Shape.Lines do
  begin
    Width := MARK_WIDTH;
    if Line.Role = erCut then
      Width := CUT_WIDTH;
    // An output profile's own look, or the built-in one
    if Line.Style.Custom then
      Result := Result + Format('<g class="line-%s"><path d="%s" stroke="%s" stroke-width="%s"%s/></g>',
        [ROLE_CLASS_NAMES[Line.Role], OpenPath(Line.Points), LowerCase(Line.Style.Color), SVGNumber(Line.Style.Width),
        DashText(Line.Style.Dashes)]) + #10
    else
      Result := Result + Format('<g class="line-%s"><path d="%s" stroke-width="%s"%s/></g>',
        [ROLE_CLASS_NAMES[Line.Role], OpenPath(Line.Points), SVGNumber(Width), DashArray(Line.Role)]) + #10;
  end;
end;

// The pattern's notes printed with the piece: a callout's leader, a white box
// when it has one, and a text element per line
function NotesGroup(const Shape: TPlacedPiece; const Values: TFieldValues): string;
var
  Note: TSheetNote;
  Lines: TStringArray;
  Index: integer;
  Frame: TRect2;
  Start: TVec2;
begin
  Result := '';
  for Note in Shape.Notes do
  begin
    Frame := NoteFrameBounds(Note, Values);
    if (Note.Leader <> nlNone) and LeaderStart(Frame, Note.Tip, Start) then
    begin
      Result := Result + Format('<path d="%s" fill="none" stroke="%s" stroke-width="%s"/>',
        [StrokesPath(LeaderStrokes(Start, Note.Tip, Note.Leader)), INK_COLOR, SVGNumber(MARK_WIDTH)]);
      if Note.Leader = nlDot then
        Result := Result + Format('<circle cx="%s" cy="%s" r="%s" fill="%s" stroke="none"/>',
          [SVGNumber(Note.Tip.X), SVGNumber(Note.Tip.Y), SVGNumber(LEADER_DOT_RADIUS), INK_COLOR]);
    end;
    if Note.Boxed then
      Result := Result + Format('<rect x="%s" y="%s" width="%s" height="%s" fill="#ffffff" stroke="none"/>',
        [SVGNumber(Frame.MinX), SVGNumber(Frame.MinY), SVGNumber(Frame.MaxX - Frame.MinX), SVGNumber(Frame.MaxY - Frame.MinY)]);
    Lines := TextLines(ExpandFields(Note.Text, Values));
    for Index := 0 to High(Lines) do
      Result := Result + Format('<text x="%s" y="%s" %s font-size="%s" fill="%s" stroke="none">%s</text>',
        [SVGNumber(NoteLineLeft(Note, Values, Lines[Index])), SVGNumber(Note.Y + (Index + 1) * LineHeight(Note.Size)),
        NoteFontAttributes(Note.Style), SVGNumber(Note.Size * POINTS_TO_MM), INK_COLOR, EscapeXML(Lines[Index])]);
  end;
  if Result <> '' then
    Result := '<g class="notes">' + Result + '</g>' + #10;
end;

function PieceGroup(const Shape: TPlacedPiece; Number: integer; const Values: TFieldValues): string;
var
  Marks: string;
begin
  Marks := StrokesPath(Shape.Marks);
  Result := Format('<g id="piece%d" data-name="%s" fill="none" stroke="%s">', [Number, EscapeXML(Shape.Caption), INK_COLOR]) + #10 +
    Format('<g class="cut"><path d="%s" stroke-width="%s"/></g>', [ClosedPath(Shape.CutLine), SVGNumber(CUT_WIDTH)]) + #10;
  if Length(Shape.SeamLine) > 0 then
    Result := Result + Format('<g class="seam"><path d="%s" stroke-width="%s" stroke-dasharray="%s %s"/></g>',
      [ClosedPath(Shape.SeamLine), SVGNumber(SEAM_WIDTH), SVGNumber(SEAM_DASH), SVGNumber(SEAM_DASH)]) + #10;
  if Marks <> '' then
    Result := Result + Format('<g class="marks"><path d="%s" stroke-width="%s"/></g>', [Marks, SVGNumber(MARK_WIDTH)]) + #10;
  Result := Result + LinesGroup(Shape);
  if Shape.ShowLabel then
    Result := Result + Format('<g class="label"><text x="%s" y="%s" font-family="sans-serif" font-size="%s" fill="%s" stroke="none">%s</text></g>',
      [SVGNumber(Shape.LabelAt.X), SVGNumber(Shape.LabelAt.Y), SVGNumber(LABEL_SIZE), INK_COLOR, EscapeXML(Shape.Caption)]) + #10;
  Result := Result + NotesGroup(Shape, Values);
  Result := Result + '</g>' + #10;
end;

// What one line type draws of a piece, without its style
function LineBody(const Shape: TPlacedPiece; Kind: TLineType; const Style: TLineStyle): string;
var
  Hole: TPlacedHole;
begin
  Result := '';
  case Kind of
    ltCut:
    begin
      Result := Format('<path d="%s"/>', [ClosedPath(Shape.CutLine)]);
      if Length(Shape.SlitLines) > 0 then
        Result := Result + Format('<path d="%s"/>', [StrokesPath(Shape.SlitLines)]);
    end;
    ltScore:
      if Length(Shape.ScoreLines) > 0 then
        Result := Format('<path d="%s"/>', [StrokesPath(Shape.ScoreLines)]);
    ltMark:
    begin
      if Length(Shape.SeamLine) > 0 then
        Result := Format('<path d="%s"/>', [ClosedPath(Shape.SeamLine)]);
      if Length(Shape.MarkLines) > 0 then
        Result := Result + Format('<path d="%s"/>', [StrokesPath(Shape.MarkLines)]);
    end;
    ltEngrave:
      if Shape.ShowLabel then
        Result := Format('<text x="%s" y="%s" font-family="sans-serif" font-size="%s" fill="%s" stroke="none">%s</text>',
          [SVGNumber(Shape.LabelAt.X), SVGNumber(Shape.LabelAt.Y), SVGNumber(LABEL_SIZE), Style.Color, EscapeXML(Shape.Caption)]);
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
  for Kind in MACHINE_ORDER do
  begin
    Style := Profile.Lines[Kind];
    Body := LineBody(Shape, Kind, Style);
    if Style.Enabled and (Body <> '') then
      Result := Result + Format('<g class="%s" data-layer="%s" stroke="%s" stroke-width="%s">%s</g>',
        [LINE_TYPE_NAMES[Kind], EscapeXML(Style.Layer), Style.Color, SVGNumber(Style.Width), Body]) + #10;
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
  Width := Width + 2 * SHEET_MARGIN;
  Height := Height + 2 * SHEET_MARGIN;
  Result := '<?xml version="1.0" encoding="UTF-8"?>' + #10 +
    Format('<svg xmlns="http://www.w3.org/2000/svg" width="%smm" height="%smm" viewBox="%s %s %s %s">',
    [SVGNumber(Width), SVGNumber(Height), SVGNumber(-SHEET_MARGIN), SVGNumber(-SHEET_MARGIN), SVGNumber(Width), SVGNumber(Height)]) + #10;
  for Index := 0 to High(Shapes) do
    if ForMachine then
      Result := Result + MachinePieceGroup(Shapes[Index], Index + 1, Profile)
    else
      Result := Result + PieceGroup(Shapes[Index], Index + 1, Layout.FieldValues('', ''));
  Result := Result + '</svg>' + #10;
end;

end.
