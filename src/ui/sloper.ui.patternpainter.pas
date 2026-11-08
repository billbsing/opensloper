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

// Draws the drafting canvas into a bitmap: the grid, the pattern with its
// notes and labels, and the overlays the canvas asks for (curve handles, the
// snap, the selection box). It draws what it is given and decides nothing
// about tools or input; the canvas says what to show.
unit Sloper.UI.PatternPainter;

{$mode ObjFPC}{$H+}

interface

uses
  Classes, SysUtils, Graphics, BGRABitmap, BGRABitmapTypes, Sloper.Core.Geometry, Sloper.Core.Draft, Sloper.Core.Piece, Sloper.Core.Seam,
  Sloper.Core.Pattern, Sloper.Core.Units, Sloper.Core.TextFields, Sloper.UI.View, Sloper.UI.Snap, Sloper.UI.Scene;

type
  // What a drawing tool's second click would make, drawn from its first
  TSnapPreview = (spNone, spLine, spCircle, spRectangle);

  // What the canvas shows besides the pattern itself
  TPaintState = record
    View: TViewTransform;
    Selection: TStringArray;
    HoverKey: string;
    ShowPieceFills: boolean;
    // Points drawn smaller, when no labels are shown
    SmallPoints: boolean;
    // The two sides of the seam being picked
    SeamA, SeamB: TSeamSide;
    // A callout whose tip is being dragged, and where to; empty when none
    DraggedTipKey: string;
    DraggedTip: TVec2;
    // A selected callout shows a handle on its tip, for dragging it
    TipHandles: boolean;
  end;

  TPatternPainter = class
  private
    FBitmap: TBGRABitmap;
    FPattern: TPattern;
    FState: TPaintState;
    FEdgeSlots: TEdgeSlotArray;
    function IsSelected(const Key: string): boolean;
    procedure DrawPieceFill(Piece: TPieceObject; const Points: TVec2Array; const Screen: array of TPointF);
    procedure DrawPiece(Piece: TPieceObject);
    procedure DrawChevron(const Position: TVec2; Angle: double; const AColor: TBGRAPixel);
    procedure DrawChevrons(Piece: TPieceObject);
    procedure DrawSeamSide(const Side: TSeamSide; const AColor: TBGRAPixel);
    procedure DrawSeams;
    procedure DrawPieceMarks(Piece: TPieceObject);
    function EdgeShift(const Key: string): TVec2;
    procedure DrawEdge(Edge: TEdgeObject);
    procedure DrawPoint(Point: TPointObject);
    procedure DrawMarker(DraftObject: TDraftObject);
  public
    constructor Create;
    destructor Destroy; override;
    // Starts a frame of Width by Height pixels on blank paper. Pattern may be
    // nil, for the grid alone; the Draw calls below except DrawGrid and
    // DrawBox need one.
    procedure BeginFrame(Pattern: TPattern; Width, Height: integer; const State: TPaintState);
    procedure EndFrame(Target: TCanvas);
    // Step in GridUnit, as in Preferences
    procedure DrawGrid(Step: double; GridUnit: TMeasureUnit);
    // Pieces under edges, edges under points, with seams and markers
    procedure DrawPattern;
    procedure DrawNotes(const Values: TFieldValues);
    // Over the rest, so no edge or point crosses out a label
    procedure DrawLabels(const Keys: TStringArray);
    // Each selected curve's handles; the one at HoverField of curve HoverEdge is larger
    procedure DrawHandles(const HoverField, HoverEdge: string);
    // The snap marker, a guide to the point it lines up with, and what the
    // second click would make from StartAt
    procedure DrawSnap(const Snap: TSnap; Preview: TSnapPreview; const StartAt: TVec2);
    // The selection box between two screen corners
    procedure DrawBox(const Corner, OtherCorner: TPoint);
  end;

implementation

uses
  Math, Sloper.Core.EvalTypes, Sloper.Core.Evaluator, Sloper.Core.Drag, Sloper.Core.Note, Sloper.Core.Transform,
  Sloper.Core.Materials, Sloper.UI.RulerTicks;

const
  // How strongly a material's colour shows under the lines
  MaterialTintAlpha = 60;
  MaterialHatchAlpha = 130;
  MaterialHatchPixels = 8;
  // Screen pixels
  MarkingLineWidth = 1.5;
  PointRadius = 3.5;
  SmallPointRadius = 2.5;
  HandleRadius = 4;
  // How far apart lines in the same place are drawn, in pixels
  CoincidentGap = 3;
  FlattenPixels = 0.25;
  LabelFontHeight = 13;
  SnapMarkerSize = 6;
  ChevronSize = 7;
  ChevronSpread = 150;
  SeamLineWidth = 4;
  // Text smaller than this many pixels is drawn as a faint bar
  MinNotePixels = 3;

function Paper: TBGRAPixel;
begin
  Result := BGRA(252, 251, 248);
end;

function GridMinor: TBGRAPixel;
begin
  Result := BGRA(236, 234, 228);
end;

function GridMajor: TBGRAPixel;
begin
  Result := BGRA(218, 215, 207);
end;

function Ink: TBGRAPixel;
begin
  Result := BGRA(34, 36, 40);
end;

function ConstructionInk: TBGRAPixel;
begin
  Result := BGRA(128, 134, 145);
end;

function SelectedInk: TBGRAPixel;
begin
  Result := BGRA(37, 116, 214);
end;

function SeamInkA: TBGRAPixel;
begin
  Result := BGRA(214, 96, 37);
end;

function SeamInkB: TBGRAPixel;
begin
  Result := BGRA(20, 140, 120);
end;

function SnapInk: TBGRAPixel;
begin
  Result := BGRA(196, 48, 140);
end;

function BoxFill: TBGRAPixel;
begin
  Result := BGRA(37, 116, 214, 20);
end;

function PieceHoverTint: TBGRAPixel;
begin
  Result := BGRA(37, 116, 214, 30);
end;

function HoverHalo: TBGRAPixel;
begin
  Result := BGRA(37, 116, 214, 60);
end;

function StateInk(State: TEvalState; const Normal: TBGRAPixel): TBGRAPixel;
begin
  case State of
    esError, esInvalid: Result := BGRA(209, 52, 56);
    esBlocked: Result := BGRA(226, 140, 40);
    else
      Result := Normal;
  end;
end;

// Failing objects are drawn faded at their last good result
function Faded(const Color: TBGRAPixel; State: TEvalState): TBGRAPixel;
begin
  Result := Color;
  if State <> esValid then
    Result.alpha := 150;
end;

function ScreenPoint(const Point: TVec2): TPointF;
begin
  Result := PointF(Point.X, Point.Y);
end;

{ TPatternPainter }

constructor TPatternPainter.Create;
begin
  inherited Create;
  FBitmap := TBGRABitmap.Create(1, 1);
end;

destructor TPatternPainter.Destroy;
begin
  FreeAndNil(FBitmap);
  inherited Destroy;
end;

procedure TPatternPainter.BeginFrame(Pattern: TPattern; Width, Height: integer; const State: TPaintState);
begin
  FPattern := Pattern;
  FState := State;
  // The bitmap is never empty, so a collapsed canvas keeps a 1 by 1 one
  Width := Max(Width, 1);
  Height := Max(Height, 1);
  if (FBitmap.Width <> Width) or (FBitmap.Height <> Height) then
    FBitmap.SetSize(Width, Height);
  FBitmap.Fill(Paper);
  FBitmap.FontHeight := LabelFontHeight;
  FBitmap.FontQuality := fqFineAntialiasing;
end;

procedure TPatternPainter.EndFrame(Target: TCanvas);
begin
  FBitmap.Draw(Target, 0, 0, True);
end;

function TPatternPainter.IsSelected(const Key: string): boolean;
var
  Selected: string;
begin
  for Selected in FState.Selection do
    if Selected = Key then
      Exit(True);
  Result := False;
end;

// Counted in whole steps from the origin, so major lines stay put and long
// grids gather no rounding
procedure TPatternPainter.DrawGrid(Step: double; GridUnit: TMeasureUnit);
var
  Spacing: TRulerSpacing;
  StepMm, Screen: double;
  PerMajor, First, Last, Index: int64;
  TopLeft, BottomRight: TVec2;
  LineColor: TBGRAPixel;
begin
  Spacing := GridSpacing(FState.View.Scale * MillimetresPerUnit[GridUnit], Step, GridUnit);
  StepMm := Spacing.Minor * MillimetresPerUnit[GridUnit];
  PerMajor := Max(1, Round(Spacing.Labelled / Spacing.Minor));
  TopLeft := FState.View.ToModel(Vec2(0, 0));
  BottomRight := FState.View.ToModel(Vec2(FBitmap.Width, FBitmap.Height));

  First := Floor64(TopLeft.X / StepMm);
  Last := Ceil64(BottomRight.X / StepMm);
  for Index := First to Last do
  begin
    if Index mod PerMajor = 0 then
      LineColor := GridMajor
    else
      LineColor := GridMinor;
    Screen := FState.View.ToScreen(Vec2(Index * StepMm, 0)).X;
    FBitmap.DrawVertLine(Round(Screen), 0, FBitmap.Height, LineColor);
  end;
  First := Floor64(TopLeft.Y / StepMm);
  Last := Ceil64(BottomRight.Y / StepMm);
  for Index := First to Last do
  begin
    if Index mod PerMajor = 0 then
      LineColor := GridMajor
    else
      LineColor := GridMinor;
    Screen := FState.View.ToScreen(Vec2(0, Index * StepMm)).Y;
    FBitmap.DrawHorizLine(0, Round(Screen), FBitmap.Width, LineColor);
  end;
end;

// Under every line, so seams and labels stay readable. Hatching keeps its
// spacing on screen at any zoom.
procedure TPatternPainter.DrawPieceFill(Piece: TPieceObject; const Points: TVec2Array; const Screen: array of TPointF);
var
  Look: TPieceLook;
  Stroke: TLine2;
begin
  Look := FPattern.PieceLook(Piece);
  if not FState.ShowPieceFills or not Look.Filled then
    Exit;
  if Look.Fill = ffTint then
    FBitmap.FillPolyAntialias(Screen, BGRA(Look.Color.Red, Look.Color.Green, Look.Color.Blue, MaterialTintAlpha))
  else
    for Stroke in HatchLines(Points, MaterialHatchPixels, Look.HatchAngle) do
      FBitmap.DrawLineAntialias(Stroke.P1.X, Stroke.P1.Y, Stroke.P2.X, Stroke.P2.Y, BGRA(Look.Color.Red, Look.Color.Green,
        Look.Color.Blue, MaterialHatchAlpha), 1);
end;

// The cutting line, filled with its material; the seam line is the edges drawn over it
procedure TPatternPainter.DrawPiece(Piece: TPieceObject);
var
  Screen: array of TPointF;
  Points: TVec2Array;
  Index: integer;
  LineColor: TBGRAPixel;
  LineWidth: single;
begin
  if Length(Piece.CutLine) = 0 then
    Exit;
  Screen := nil;
  Points := nil;
  SetLength(Screen, Length(Piece.CutLine));
  SetLength(Points, Length(Piece.CutLine));
  for Index := 0 to High(Screen) do
  begin
    Points[Index] := FState.View.ToScreen(Piece.CutLine[Index]);
    Screen[Index] := ScreenPoint(Points[Index]);
  end;
  DrawPieceFill(Piece, Points, Screen);
  if Piece.Key = FState.HoverKey then
    FBitmap.FillPolyAntialias(Screen, PieceHoverTint);
  LineColor := Faded(StateInk(Piece.State, ConstructionInk), Piece.State);
  LineWidth := 1;
  if IsSelected(Piece.Key) then
  begin
    LineColor := SelectedInk;
    LineWidth := 2;
  end;
  FBitmap.DrawPolygonAntialias(Screen, LineColor, LineWidth);
end;

procedure TPatternPainter.DrawChevron(const Position: TVec2; Angle: double; const AColor: TBGRAPixel);
var
  Tip, WingA, WingB: TVec2;
  Size: double;
begin
  Size := FState.View.PixelsToMM(ChevronSize);
  Tip := FState.View.ToScreen(Position);
  WingA := FState.View.ToScreen(PolarPoint(Position, Size, Angle + ChevronSpread));
  WingB := FState.View.ToScreen(PolarPoint(Position, Size, Angle - ChevronSpread));
  FBitmap.DrawPolyLineAntialias([PointF(WingA.X, WingA.Y), PointF(Tip.X, Tip.Y), PointF(WingB.X, WingB.Y)], AColor, 2);
end;

// Shown over the edges while a piece is hovered or selected
procedure TPatternPainter.DrawChevrons(Piece: TPieceObject);
var
  Item: TPieceChevron;
begin
  for Item in PieceChevrons(FPattern, Piece) do
    DrawChevron(Item.Position, Item.Angle, SelectedInk);
end;

procedure TPatternPainter.DrawSeamSide(const Side: TSeamSide; const AColor: TBGRAPixel);
var
  Entry: TSeamEntry;
  Model: TVec2Array;
  Screen: array of TPointF;
  Index: integer;
begin
  for Entry in Side do
  begin
    Model := EdgePolyline(TEdgeObject(FPattern.FindNode(Entry.EdgeKey)), FState.View.PixelsToMM(FlattenPixels));
    Screen := nil;
    SetLength(Screen, Length(Model));
    for Index := 0 to High(Model) do
      Screen[Index] := ScreenPoint(FState.View.ToScreen(Model[Index]));
    FBitmap.DrawPolyLineAntialias(Screen, AColor, SeamLineWidth);
  end;
end;

// The selected seams, with the way they run, and the one being picked
procedure TPatternPainter.DrawSeams;
var
  Key: string;
  Node: TEvalNode;
  Item: TPieceChevron;
begin
  for Key in FState.Selection do
  begin
    Node := FPattern.FindNode(Key);
    if not (Node is TSeamObject) then
      Continue;
    DrawSeamSide(TSeamObject(Node).SideA, SeamInkA);
    DrawSeamSide(TSeamObject(Node).SideB, SeamInkB);
    for Item in SeamChevrons(FPattern, TSeamObject(Node), False) do
      DrawChevron(Item.Position, Item.Angle, SeamInkA);
    for Item in SeamChevrons(FPattern, TSeamObject(Node), True) do
      DrawChevron(Item.Position, Item.Angle, SeamInkB);
  end;
  DrawSeamSide(FState.SeamA, SeamInkA);
  DrawSeamSide(FState.SeamB, SeamInkB);
end;

// The grainline and notches, over the edges
procedure TPatternPainter.DrawPieceMarks(Piece: TPieceObject);
var
  Stroke: TLine2;
  Mark: TNotchMark;
  LineColor: TBGRAPixel;
  First, Last: TVec2;
begin
  LineColor := Faded(StateInk(Piece.State, ConstructionInk), Piece.State);
  if IsSelected(Piece.Key) then
    LineColor := SelectedInk;
  for Stroke in Concat(Piece.GrainArrow, Piece.FoldArrow, Piece.MarkingStrokes) do
  begin
    First := FState.View.ToScreen(Stroke.P1);
    Last := FState.View.ToScreen(Stroke.P2);
    FBitmap.DrawLineAntialias(First.X, First.Y, Last.X, Last.Y, LineColor, 1.5);
  end;
  for Mark in Piece.NotchMarks do
  begin
    First := FState.View.ToScreen(Mark.Cut);
    Last := FState.View.ToScreen(Mark.Tip);
    FBitmap.DrawLineAntialias(First.X, First.Y, Last.X, Last.Y, LineColor, 2);
  end;
end;

function ScreenDashes(const Dashes: TDashPattern; LineWidth: single): TBGRAPenStyle; forward;

// Screen pixels to move an edge aside by, so lines in the same place show
// that there is more than one; geometry and output never move
function TPatternPainter.EdgeShift(const Key: string): TVec2;
var
  Slot: TEdgeSlot;
begin
  Result := Vec2(0, 0);
  for Slot in FEdgeSlots do
    if Slot.Key = Key then
      Exit(Slot.Normal * (Slot.Slot * CoincidentGap));
end;

procedure TPatternPainter.DrawEdge(Edge: TEdgeObject);
var
  Shift: TVec2;
  Model: TVec2Array;
  Screen: array of TPointF;
  Index: integer;
  LineColor: TBGRAPixel;
  LineWidth: single;
begin
  Model := EdgePolyline(Edge, FState.View.PixelsToMM(FlattenPixels));
  if Length(Model) < 2 then
    Exit;
  Shift := EdgeShift(Edge.Key);
  Screen := nil;
  SetLength(Screen, Length(Model));
  for Index := 0 to High(Model) do
    Screen[Index] := ScreenPoint(FState.View.ToScreen(Model[Index]) + Shift);

  case Edge.Role of
    erOutline:
    begin
      LineColor := Ink;
      LineWidth := 2;
    end;
    erConstruction:
    begin
      LineColor := ConstructionInk;
      LineWidth := 1;
    end;
    else
    begin
      LineColor := StrToBGRA(RoleColors[Edge.Role]);
      LineWidth := MarkingLineWidth;
    end;
  end;
  LineColor := Faded(StateInk(Edge.State, LineColor), Edge.State);
  if Edge.Key = FState.HoverKey then
    FBitmap.DrawPolyLineAntialias(Screen, HoverHalo, LineWidth + 6);
  // Selecting a transform shows its copies
  if IsSelected(Edge.Key) or IsSelected(CopyTransformKey(Edge)) then
  begin
    LineColor := SelectedInk;
    LineWidth := LineWidth + 1;
  end;
  if Edge.Role = erConstruction then
    FBitmap.PenStyle := psDash
  else if RoleDashes[Edge.Role][0] > 0 then
    FBitmap.CustomPenStyle := ScreenDashes(RoleDashes[Edge.Role], LineWidth);
  FBitmap.DrawPolyLineAntialias(Screen, LineColor, LineWidth);
  FBitmap.PenStyle := psSolid;
end;

// The paper dashes at a fixed size on screen, whatever the zoom, in the pen
// widths BGRABitmap counts in
function ScreenDashes(const Dashes: TDashPattern; LineWidth: single): TBGRAPenStyle;
const
  PixelsPerMillimetre = 2.5;
var
  Index, Count: integer;
begin
  Result := nil;
  Count := 0;
  for Index := 0 to High(Dashes) do
    if Dashes[Index] > 0 then
      Inc(Count);
  SetLength(Result, Count);
  for Index := 0 to Count - 1 do
    Result[Index] := Dashes[Index] * PixelsPerMillimetre / LineWidth;
end;

procedure TPatternPainter.DrawPoint(Point: TPointObject);
var
  Screen: TVec2;
  InkColor: TBGRAPixel;
  Radius: single;
begin
  Screen := FState.View.ToScreen(Point.Position);
  InkColor := Faded(StateInk(Point.State, Ink), Point.State);
  if FState.SmallPoints then
    Radius := SmallPointRadius
  else
    Radius := PointRadius;
  if Point.Key = FState.HoverKey then
    FBitmap.FillEllipseAntialias(Screen.X, Screen.Y, Radius + 5, Radius + 5, HoverHalo);
  if IsSelected(Point.Key) or IsSelected(CopyTransformKey(Point)) then
  begin
    InkColor := SelectedInk;
    Radius := Radius + 1.5;
  end;
  FBitmap.FillEllipseAntialias(Screen.X, Screen.Y, Radius, Radius, InkColor);
end;

procedure TPatternPainter.DrawPattern;
var
  Point: TPointObject;
  Shown: TDraftObjectArray;
  DraftObject: TDraftObject;
  Key: string;
  Node: TEvalNode;
begin
  // Pieces under edges, edges under points
  Shown := ShownObjects(FPattern);
  FEdgeSlots := CoincidentEdges(FPattern);
  for DraftObject in Shown do
    if (DraftObject is TPieceObject) and DraftObject.HasResult then
      DrawPiece(TPieceObject(DraftObject));
  for DraftObject in EdgesInDrawOrder(Shown) do
    if DraftObject.HasResult then
      DrawEdge(TEdgeObject(DraftObject));
  // A hidden line shows while it is selected, as from the Objects panel
  for Key in FState.Selection do
  begin
    Node := FPattern.FindNode(Key);
    if (Node is TEdgeObject) and FPattern.IsHidden(TEdgeObject(Node)) and Node.HasResult then
      DrawEdge(TEdgeObject(Node));
  end;
  for DraftObject in Shown do
  begin
    if not (DraftObject is TPieceObject) or not DraftObject.HasResult then
      Continue;
    DrawPieceMarks(TPieceObject(DraftObject));
    if IsSelected(DraftObject.Key) or (DraftObject.Key = FState.HoverKey) then
      DrawChevrons(TPieceObject(DraftObject));
  end;
  DrawSeams;
  // A marker shows at its point whether or not it is on a piece yet
  for DraftObject in Shown do
    if (DraftObject.Marker <> pmPlain) and DraftObject.HasResult then
      DrawMarker(DraftObject);
  for Point in ShownPoints(FPattern) do
    if Point.HasResult then
      DrawPoint(Point);
end;

// Over the pattern, at their true size for the zoom. A selected note shows a
// faint line to what it hangs from, and a hovered one a halo.
procedure TPatternPainter.DrawNotes(const Values: TFieldValues);
var
  Index, LineIndex: integer;
  Note: TNoteObject;
  Lines: TStringArray;
  Box, Frame: TRect2;
  TopLeft, BottomRight, Anchor, Spot, Tip, Start, First, Last: TVec2;
  InkColor: TBGRAPixel;
  EmPixels, LinePixels, BoxPixels: double;
  Stroke: TLine2;
  Selected: boolean;
begin
  if FPattern.View.HideAnnotations then
    Exit;
  for Index := 0 to FPattern.ObjectCount - 1 do
  begin
    if not (FPattern.Objects[Index] is TNoteObject) or not FPattern.Objects[Index].HasResult then
      Continue;
    Note := TNoteObject(FPattern.Objects[Index]);
    Selected := IsSelected(Note.Key);
    Box := NoteBox(Note, Values);
    Frame := NoteFrame(Note, Values);
    TopLeft := FState.View.ToScreen(Vec2(Box.MinX, Box.MinY));
    BottomRight := FState.View.ToScreen(Vec2(Box.MaxX, Box.MaxY));
    if Selected then
      InkColor := SelectedInk
    else
      InkColor := Faded(StateInk(Note.State, Ink), Note.State);
    // A screen-only note is drawn lighter, as it never prints
    if not Note.Print then
      InkColor.alpha := InkColor.alpha div 2;
    // A callout's leader, to where its tip is being dragged while it is
    Tip := Note.AnchorPosition;
    if (FState.DraggedTipKey <> '') and (Note.Key = FState.DraggedTipKey) then
      Tip := FState.DraggedTip;
    if (Note.Leader <> nlNone) and LeaderStart(Frame, Tip, Start) then
    begin
      for Stroke in LeaderStrokes(Start, Tip, Note.Leader) do
      begin
        First := FState.View.ToScreen(Stroke.P1);
        Last := FState.View.ToScreen(Stroke.P2);
        FBitmap.DrawLineAntialias(First.X, First.Y, Last.X, Last.Y, InkColor, 1);
      end;
      if Note.Leader = nlDot then
      begin
        Spot := FState.View.ToScreen(Tip);
        FBitmap.FillEllipseAntialias(Spot.X, Spot.Y, Max(1.5, LeaderDotRadius * FState.View.Scale), Max(1.5, LeaderDotRadius * FState.View.Scale), InkColor);
      end;
    end
    else if Selected and (Note.Anchor <> naFree) then
    begin
      // A plain note shows faintly what it hangs from
      Anchor := FState.View.ToScreen(Note.AnchorPosition);
      FBitmap.PenStyle := psDot;
      FBitmap.DrawLineAntialias(Anchor.X, Anchor.Y, TopLeft.X, TopLeft.Y, HoverHalo, 1);
      FBitmap.PenStyle := psSolid;
    end;
    // A selected callout's tip can be dragged to something else
    if Selected and (Note.Leader <> nlNone) and FState.TipHandles then
    begin
      Spot := FState.View.ToScreen(Tip);
      FBitmap.EllipseAntialias(Spot.X, Spot.Y, HandleRadius, HandleRadius, SelectedInk, 1.5, Paper);
    end;
    if Note.Boxed then
    begin
      First := FState.View.ToScreen(Vec2(Frame.MinX, Frame.MinY));
      Last := FState.View.ToScreen(Vec2(Frame.MaxX, Frame.MaxY));
      FBitmap.FillRectAntialias(First.X, First.Y, Last.X, Last.Y, BGRA(255, 255, 255));
    end;
    if (Note.Key = FState.HoverKey) or Selected then
      FBitmap.FillRectAntialias(TopLeft.X - 2, TopLeft.Y - 1, BottomRight.X + 2, BottomRight.Y + 1, PieceHoverTint);
    EmPixels := Note.Size * PointsToMM * FState.View.Scale;
    LinePixels := LineHeight(Note.Size) * FState.View.Scale;
    if EmPixels < MinNotePixels then
    begin
      FBitmap.FillRectAntialias(TopLeft.X, TopLeft.Y, BottomRight.X, BottomRight.Y, BGRA(InkColor.red, InkColor.green, InkColor.blue, 40));
      Continue;
    end;
    FBitmap.FontHeight := Round(EmPixels);
    BoxPixels := BottomRight.X - TopLeft.X;
    Lines := TextLines(ExpandFields(Note.ShownText, Values));
    for LineIndex := 0 to High(Lines) do
    begin
      Spot := Vec2(AlignedLeft(TopLeft.X, BoxPixels, FBitmap.TextSize(Lines[LineIndex]).cx, Note.Align), TopLeft.Y + LineIndex * LinePixels);
      FBitmap.TextOut(Spot.X, Spot.Y, Lines[LineIndex], InkColor);
    end;
  end;
  FBitmap.FontHeight := LabelFontHeight;
end;

procedure TPatternPainter.DrawMarker(DraftObject: TDraftObject);
var
  Centre: TVec2;
  Stroke: TLine2;
  First, Last: TVec2;
  LineColor: TBGRAPixel;
begin
  if DraftObject.MarkerSize <= 0 then
    Exit;
  LineColor := Faded(StateInk(DraftObject.State, Ink), DraftObject.State);
  if IsSelected(DraftObject.Key) then
    LineColor := SelectedInk;
  for Centre in MarkerPositions(DraftObject) do
    for Stroke in MarkerStrokes(DraftObject.Marker, Centre, DraftObject.MarkerSize) do
    begin
      First := FState.View.ToScreen(Stroke.P1);
      Last := FState.View.ToScreen(Stroke.P2);
      FBitmap.DrawLineAntialias(First.X, First.Y, Last.X, Last.Y, LineColor, 1);
    end;
end;

// Each selected curve's tangent lines. A handle set by a formula is hollow,
// since it cannot be dragged.
procedure TPatternPainter.DrawHandles(const HoverField, HoverEdge: string);
var
  Item: TCurveHandle;
  Anchor, Tip: TVec2;
  Radius: single;
  Reason: string;
begin
  for Item in SelectionHandles(FPattern, FState.Selection) do
  begin
    Anchor := FState.View.ToScreen(Item.Anchor);
    Tip := FState.View.ToScreen(Item.Position);
    FBitmap.DrawLineAntialias(Anchor.X, Anchor.Y, Tip.X, Tip.Y, SelectedInk, 1);
    Radius := HandleRadius;
    if (Item.LengthField = HoverField) and (Item.EdgeKey = HoverEdge) then
      Radius := Radius + 1.5;
    if CanDragHandle(TEdgeObject(FPattern.FindNode(Item.EdgeKey)), Item, Reason) then
      FBitmap.FillEllipseAntialias(Tip.X, Tip.Y, Radius, Radius, SelectedInk)
    else
      FBitmap.EllipseAntialias(Tip.X, Tip.Y, Radius, Radius, SelectedInk, 1.5, Paper);
  end;
end;

// Over the drawing, so that no edge or point crosses out a label
procedure TPatternPainter.DrawLabels(const Keys: TStringArray);
var
  Key: string;
  Node: TEvalNode;
  Model: TVec2Array;
  Screen: TVec2;
  InkColor: TBGRAPixel;
begin
  for Key in Keys do
  begin
    Node := FPattern.FindNode(Key);
    if Node is TPointObject then
    begin
      Screen := FState.View.ToScreen(TPointObject(Node).Position);
      Screen := Vec2(Screen.X + 6, Screen.Y - LabelFontHeight - 2);
    end
    else if Node is TPieceObject then
      Screen := FState.View.ToScreen(PieceMiddle(TPieceObject(Node)))
    else if Node is TEdgeObject then
    begin
      Model := EdgePolyline(TEdgeObject(Node), FState.View.PixelsToMM(FlattenPixels));
      if Length(Model) = 0 then
        Continue;
      Screen := FState.View.ToScreen(PolylineMiddle(Model));
      Screen := Vec2(Screen.X + 4, Screen.Y + 2);
    end
    else
      Continue;
    if IsSelected(Key) then
      InkColor := SelectedInk
    else
      InkColor := Faded(StateInk(Node.State, Ink), Node.State);
    if Node is TPieceObject then
      FBitmap.TextOut(Screen.X, Screen.Y, FPattern.PieceCaption(TPieceObject(Node)), InkColor)
    else
      FBitmap.TextOut(Screen.X, Screen.Y, Node.DisplayName, InkColor);
  end;
end;

procedure TPatternPainter.DrawSnap(const Snap: TSnap; Preview: TSnapPreview; const StartAt: TVec2);
var
  Screen, Base, Start: TVec2;
  Node: TEvalNode;
  Size: single;
begin
  Screen := FState.View.ToScreen(Snap.Position);
  Size := SnapMarkerSize;
  if Preview <> spNone then
  begin
    Start := FState.View.ToScreen(StartAt);
    FBitmap.PenStyle := psDash;
    case Preview of
      spCircle:
        FBitmap.EllipseAntialias(Start.X, Start.Y, Distance(Start, Screen), Distance(Start, Screen), SelectedInk, 1.5);
      spRectangle:
        FBitmap.RectangleAntialias(Min(Start.X, Screen.X), Min(Start.Y, Screen.Y), Max(Start.X, Screen.X), Max(Start.Y, Screen.Y),
          SelectedInk, 1.5);
      else
        FBitmap.DrawLineAntialias(Start.X, Start.Y, Screen.X, Screen.Y, SelectedInk, 1.5);
    end;
    FBitmap.PenStyle := psSolid;
  end;
  if Snap.Kind in [snHorizontal, snVertical] then
  begin
    Node := FPattern.FindNode(Snap.PointKey);
    if Node is TPointObject then
    begin
      Base := FState.View.ToScreen(TPointObject(Node).Position);
      FBitmap.PenStyle := psDot;
      FBitmap.DrawLineAntialias(Base.X, Base.Y, Screen.X, Screen.Y, SnapInk, 1);
      FBitmap.PenStyle := psSolid;
    end;
  end;
  case Snap.Kind of
    snPoint:
      FBitmap.EllipseAntialias(Screen.X, Screen.Y, Size, Size, SnapInk, 2);
    snCrossing:
    begin
      FBitmap.DrawLineAntialias(Screen.X - Size, Screen.Y - Size, Screen.X + Size, Screen.Y + Size, SnapInk, 2);
      FBitmap.DrawLineAntialias(Screen.X - Size, Screen.Y + Size, Screen.X + Size, Screen.Y - Size, SnapInk, 2);
    end;
    snEdge:
      FBitmap.DrawPolygonAntialias([PointF(Screen.X, Screen.Y - Size), PointF(Screen.X + Size, Screen.Y),
        PointF(Screen.X, Screen.Y + Size), PointF(Screen.X - Size, Screen.Y)], SnapInk, 2);
    snHorizontal, snVertical:
      FBitmap.RectangleAntialias(Screen.X - Size + 1, Screen.Y - Size + 1, Screen.X + Size - 1, Screen.Y + Size - 1, SnapInk, 2);
    else
    begin
      FBitmap.DrawLineAntialias(Screen.X - Size, Screen.Y, Screen.X + Size, Screen.Y, SnapInk, 1.5);
      FBitmap.DrawLineAntialias(Screen.X, Screen.Y - Size, Screen.X, Screen.Y + Size, SnapInk, 1.5);
    end;
  end;
end;

procedure TPatternPainter.DrawBox(const Corner, OtherCorner: TPoint);
var
  X1, Y1, X2, Y2: single;
begin
  X1 := Min(Corner.X, OtherCorner.X) + 0.5;
  X2 := Max(Corner.X, OtherCorner.X) + 0.5;
  Y1 := Min(Corner.Y, OtherCorner.Y) + 0.5;
  Y2 := Max(Corner.Y, OtherCorner.Y) + 0.5;
  FBitmap.FillRectAntialias(X1, Y1, X2, Y2, BoxFill);
  FBitmap.PenStyle := psDot;
  FBitmap.RectangleAntialias(X1, Y1, X2, Y2, SelectedInk, 1);
  FBitmap.PenStyle := psSolid;
end;

end.
