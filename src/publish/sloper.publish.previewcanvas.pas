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

// The publish preview: the pages with the pieces on them, drawn with
// BGRABitmap. Blank pages are greyed out. Pieces are dragged here, and a drag
// is one change; everything else goes through the main form. With Zoom Area
// on, a drag zooms to its box instead and a click zooms a step. Scroll bars
// beside it, when given, follow the view over the pages, as on the design
// canvas.
unit Sloper.Publish.PreviewCanvas;

{$mode ObjFPC}{$H+}

interface

uses
  Classes, SysUtils, Controls, StdCtrls, Graphics, LCLType, BGRABitmap, BGRABitmapTypes, Sloper.Core.Materials, Sloper.Core.Geometry, Sloper.Core.Note,
  Sloper.Core.TextFields, Sloper.Output.Layout,
  Sloper.Output.LayoutDocument, Sloper.Output.Preview, Sloper.Output.Tiling, Sloper.UI.View;

type
  // pmZoomPressed and pmZoomBoxing: Zoom Area's click, and its box being drawn
  TPreviewMode = (pmIdle, pmPressed, pmDragging, pmPanning, pmZoomPressed, pmZoomBoxing);

  TPreviewCanvas = class(TCustomControl)
  private
    FDocument: TLayoutDocument;
    FBitmap: TBGRABitmap;
    FView: TPreviewView;
    FShapes: TPlacedPieceArray;
    FPages: TTilePageArray;
    FRowCount, FColumnCount: integer;
    // The selected placement's index, or -1
    FSelected: integer;
    // The selected note's index, or -1
    FSelectedNote: integer;
    FMode: TPreviewMode;
    FPressPos, FLastPos: TPoint;
    FGrab: TVec2;
    FNeedsFit: boolean;
    FSpaceDown: boolean;
    FZoomArea: boolean;
    // The zoom tool's key, from the shortcuts table
    FZoomKey: TShortCut;
    FOnSelectionChange: TNotifyEvent;
    FOnZoomAreaChange: TNotifyEvent;
    FHorzBar, FVertBar: TScrollBar;
    // A thumb is being dragged, so its bar is left alone until it lets go
    FThumbHeld: boolean;
    procedure TakeFocus;
    procedure SetHorzBar(Value: TScrollBar);
    procedure SetVertBar(Value: TScrollBar);
    procedure BarScroll(Sender: TObject; ScrollCode: TScrollCode; var ScrollPos: integer);
    procedure ShowOnBar(Bar: TScrollBar; const Axis: TScrollAxis);
    procedure UpdateScrollBars;
    procedure SetSelected(Value: integer);
    procedure SetSelectedNote(Value: integer);
    procedure SetZoomArea(Value: boolean);
    procedure ZoomBy(Factor: double; X, Y: double);
    procedure DrawZoomBox;
    procedure DrawNotes;
    procedure DragTo(X, Y: integer);
    procedure TogglePageAt(const At: TVec2);
    procedure DrawPage(const Page: TTilePage);
    procedure DrawShape(const Shape: TPlacedPiece);
    function ScreenPoints(const Points: TVec2Array): specialize TArray<TPointF>;
  protected
    procedure Paint; override;
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: integer); override;
    procedure MouseMove(Shift: TShiftState; X, Y: integer); override;
    procedure MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: integer); override;
    function DoMouseWheel(Shift: TShiftState; WheelDelta: integer; MousePos: TPoint): boolean; override;
    procedure KeyDown(var Key: word; Shift: TShiftState); override;
    procedure KeyUp(var Key: word; Shift: TShiftState); override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    // Picks up the layout after any change
    procedure Refresh; reintroduce;
    procedure ZoomToFit;
    procedure ZoomIn;
    procedure ZoomOut;
    // Layout position under a point of this control
    function LayoutAt(X, Y: integer): TVec2;
    // Sends the selected copy back to the tray, or deletes the selected note
    procedure RemoveSelected;
    property Document: TLayoutDocument read FDocument write FDocument;
    property Selected: integer read FSelected write SetSelected;
    property SelectedNote: integer read FSelectedNote write SetSelectedNote;
    property OnSelectionChange: TNotifyEvent read FOnSelectionChange write FOnSelectionChange;
    // Pieces cannot be dragged while it is on
    property ZoomArea: boolean read FZoomArea write SetZoomArea;
    // Zoom Area turned on or off, here by its key or Escape too
    property OnZoomAreaChange: TNotifyEvent read FOnZoomAreaChange write FOnZoomAreaChange;
    // Scroll bars to keep in step with the view
    property HorzBar: TScrollBar read FHorzBar write SetHorzBar;
    property VertBar: TScrollBar read FVertBar write SetVertBar;
    property OnDragOver;
    property OnDragDrop;
  end;

resourcestring
  rsPreviewMove = 'Move piece';
  rsPreviewTogglePage = 'Leave page out';
  rsPreviewRemove = 'Unplace piece';
  rsPreviewMoveNote = 'Move note';
  rsPreviewDeleteNote = 'Delete note';
  rsPreviewZoomAreaHint = 'Zoom Area: drag a box to zoom to it, click to zoom in, Shift+click to zoom out';

implementation

uses
  Math, LCLIntf, Forms, Menus, Sloper.Core.Draft, Sloper.Core.Shortcuts, Sloper.UI.Commands;

const
  FIT_MARGIN = 24;
  DRAG_THRESHOLD = 3;
  CAPTION_HEIGHT = 13;
  LABEL_HEIGHT = 12;
  MIN_NOTE_HEIGHT = 6;
  // A click on a scroll bar's arrow moves the view this far
  SCROLL_STEP_PIXELS = 60;

function Desk: TBGRAPixel;
begin
  Result := BGRA(120, 122, 128);
end;

function PaperInk: TBGRAPixel;
begin
  Result := BGRA(255, 255, 255);
end;

function BlankPaperInk: TBGRAPixel;
begin
  Result := BGRA(205, 206, 210);
end;

function LeftOutInk: TBGRAPixel;
begin
  Result := BGRA(190, 60, 60);
end;

function EdgeInk: TBGRAPixel;
begin
  Result := BGRA(90, 92, 98);
end;

function PieceInk: TBGRAPixel;
begin
  Result := BGRA(34, 36, 40);
end;

function SelectedInk: TBGRAPixel;
begin
  Result := BGRA(37, 116, 214);
end;

function ZoomBoxFill: TBGRAPixel;
begin
  Result := BGRA(37, 116, 214, 40);
end;

function PieceTint(const Look: TPieceLook): TBGRAPixel;
begin
  Result := BGRA(Look.Color.Red, Look.Color.Green, Look.Color.Blue, 50);
end;

constructor TPreviewCanvas.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FBitmap := TBGRABitmap.Create(1, 1);
  FView := DefaultPreviewView;
  FSelected := -1;
  FSelectedNote := -1;
  FNeedsFit := True;
  FZoomKey := CommandShortCut(kcToolZoom);
  TabStop := True;
  ControlStyle := ControlStyle + [csOpaque];
end;

destructor TPreviewCanvas.Destroy;
begin
  FreeAndNil(FBitmap);
  inherited Destroy;
end;

procedure TPreviewCanvas.Refresh;
begin
  if not Assigned(FDocument) then
    Exit;
  FShapes := FDocument.Layout.PlacedPieces;
  FPages := FDocument.Layout.Pages(FShapes, FRowCount, FColumnCount);
  if FSelected > High(FDocument.Layout.Placements) then
    SetSelected(-1);
  if FSelectedNote > High(FDocument.Layout.Notes) then
    SetSelectedNote(-1);
  Invalidate;
end;

procedure TPreviewCanvas.ZoomToFit;
begin
  FNeedsFit := True;
  Invalidate;
end;

procedure TPreviewCanvas.ZoomBy(Factor: double; X, Y: double);
begin
  FView.ZoomAt(Factor, Vec2(X, Y));
  Invalidate;
end;

procedure TPreviewCanvas.ZoomIn;
begin
  ZoomBy(PREVIEW_ZOOM_STEP, ClientWidth / 2, ClientHeight / 2);
end;

procedure TPreviewCanvas.ZoomOut;
begin
  ZoomBy(1 / PREVIEW_ZOOM_STEP, ClientWidth / 2, ClientHeight / 2);
end;

procedure TPreviewCanvas.SetZoomArea(Value: boolean);
begin
  if Value = FZoomArea then
    Exit;
  FZoomArea := Value;
  if FMode in [pmZoomPressed, pmZoomBoxing] then
    FMode := pmIdle;
  if Value then
    Cursor := crCross
  else
    Cursor := crDefault;
  Invalidate;
  if Assigned(FOnZoomAreaChange) then
    FOnZoomAreaChange(Self);
end;

function TPreviewCanvas.LayoutAt(X, Y: integer): TVec2;
begin
  Result := FView.ToLayout(Vec2(X, Y));
end;

procedure TPreviewCanvas.RemoveSelected;
var
  Index: integer;
begin
  if FSelectedNote >= 0 then
  begin
    Index := FSelectedNote;
    SetSelectedNote(-1);
    FDocument.BeginChange(rsPreviewDeleteNote);
    FDocument.Layout.RemoveNote(Index);
    FDocument.EndChange;
    Exit;
  end;
  Index := FSelected;
  if Index < 0 then
    Exit;
  SetSelected(-1);
  FDocument.BeginChange(rsPreviewRemove);
  FDocument.Layout.RemovePlacement(Index);
  FDocument.EndChange;
end;

procedure TPreviewCanvas.SetSelectedNote(Value: integer);
begin
  if Value = FSelectedNote then
    Exit;
  FSelectedNote := Value;
  if Value >= 0 then
    FSelected := -1;
  Invalidate;
  if Assigned(FOnSelectionChange) then
    FOnSelectionChange(Self);
end;

procedure TPreviewCanvas.SetSelected(Value: integer);
begin
  if Value = FSelected then
    Exit;
  FSelected := Value;
  if Value >= 0 then
    FSelectedNote := -1;
  Invalidate;
  if Assigned(FOnSelectionChange) then
    FOnSelectionChange(Self);
end;

procedure TPreviewCanvas.DragTo(X, Y: integer);
var
  At: TVec2;
begin
  At := FView.ToLayout(Vec2(X, Y));
  if FSelectedNote >= 0 then
  begin
    FDocument.Layout.Notes[FSelectedNote].X := RoundToStep(At.X + FGrab.X);
    FDocument.Layout.Notes[FSelectedNote].Y := RoundToStep(At.Y + FGrab.Y);
  end
  else
  begin
    FDocument.Layout.Placements[FSelected].X := RoundToStep(At.X + FGrab.X);
    FDocument.Layout.Placements[FSelected].Y := RoundToStep(At.Y + FGrab.Y);
  end;
  FDocument.LiveUpdate;
end;

procedure TPreviewCanvas.TogglePageAt(const At: TVec2);
var
  PageName: string;
begin
  PageName := PageCaptionAt(FPages, At);
  if PageName = '' then
    Exit;
  FDocument.BeginChange(rsPreviewTogglePage);
  FDocument.Layout.TogglePage(PageName);
  FDocument.EndChange;
end;

// SetFocus does nothing while this is already the active control, even when a
// menu closed with Escape has left Qt's menu bar holding the keyboard (see
// TPatternCanvas.TakeFocus)
procedure TPreviewCanvas.TakeFocus;
begin
  SetFocus;
  if HandleAllocated and not Focused then
    LCLIntf.SetFocus(Handle);
end;

procedure TPreviewCanvas.SetHorzBar(Value: TScrollBar);
begin
  FHorzBar := Value;
  FHorzBar.Kind := sbHorizontal;
  FHorzBar.OnScroll := @BarScroll;
  FHorzBar.SmallChange := SCROLL_STEP_PIXELS;
  FHorzBar.TabStop := False;
end;

procedure TPreviewCanvas.SetVertBar(Value: TScrollBar);
begin
  FVertBar := Value;
  FVertBar.Kind := sbVertical;
  FVertBar.OnScroll := @BarScroll;
  FVertBar.SmallChange := SCROLL_STEP_PIXELS;
  FVertBar.TabStop := False;
end;

// The bars are moved by hand only, so the view follows them, and the keys go
// back to the preview afterwards
procedure TPreviewCanvas.BarScroll(Sender: TObject; ScrollCode: TScrollCode; var ScrollPos: integer);
var
  Moved: integer;
begin
  Moved := TScrollBar(Sender).Position - ScrollPos;
  if Sender = FHorzBar then
    FView.Pan(Moved, 0)
  else
    FView.Pan(0, Moved);
  FThumbHeld := ScrollCode = scTrack;
  TScrollBar(Sender).Position := ScrollPos;
  if ScrollCode = scEndScroll then
    TakeFocus;
  Invalidate;
end;

procedure TPreviewCanvas.ShowOnBar(Bar: TScrollBar; const Axis: TScrollAxis);
begin
  Bar.Enabled := Axis.Active;
  if not Axis.Active then
    Exit;
  Bar.Min := 0;
  Bar.Max := Axis.Extent - 1;
  Bar.PageSize := Axis.Page;
  Bar.LargeChange := Axis.Page;
  Bar.Position := Axis.Position;
end;

// The pages and the margin Fit Pages leaves round them, or just the view when
// there are none
procedure TPreviewCanvas.UpdateScrollBars;
var
  Bounds: TRect2;
  TopLeft, BottomRight: TVec2;
begin
  if not Assigned(FHorzBar) or not Assigned(FVertBar) or FThumbHeld then
    Exit;
  if PagesBounds(FPages, Bounds) then
  begin
    TopLeft := FView.ToScreen(Vec2(Bounds.MinX, Bounds.MinY));
    BottomRight := FView.ToScreen(Vec2(Bounds.MaxX, Bounds.MaxY));
    ShowOnBar(FHorzBar, ScrollAxisFor(TopLeft.X - FIT_MARGIN, BottomRight.X + FIT_MARGIN, ClientWidth));
    ShowOnBar(FVertBar, ScrollAxisFor(TopLeft.Y - FIT_MARGIN, BottomRight.Y + FIT_MARGIN, ClientHeight));
  end
  else
  begin
    ShowOnBar(FHorzBar, ScrollAxisFor(0, ClientWidth, ClientWidth));
    ShowOnBar(FVertBar, ScrollAxisFor(0, ClientHeight, ClientHeight));
  end;
end;

procedure TPreviewCanvas.MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: integer);
var
  Hit: integer;
  At: TVec2;
begin
  inherited MouseDown(Button, Shift, X, Y);
  TakeFocus;
  FPressPos := Point(X, Y);
  FLastPos := FPressPos;
  if (Button = mbMiddle) or ((Button = mbLeft) and FSpaceDown) then
  begin
    FMode := pmPanning;
    Exit;
  end;
  if FZoomArea and (Button = mbLeft) then
  begin
    FMode := pmZoomPressed;
    Exit;
  end;
  if not Assigned(FDocument) then
    Exit;
  At := FView.ToLayout(Vec2(X, Y));
  // A page is often all piece, so right click reaches it whatever is on it
  if Button = mbRight then
  begin
    TogglePageAt(At);
    Exit;
  end;
  if Button <> mbLeft then
    Exit;
  // Notes lie over pieces
  Hit := NoteAt(FDocument.Layout.Notes, FDocument.Layout.FieldValues('', ''), At);
  if Hit >= 0 then
  begin
    SetSelectedNote(Hit);
    FGrab := Vec2(FDocument.Layout.Notes[Hit].X - At.X, FDocument.Layout.Notes[Hit].Y - At.Y);
    FMode := pmPressed;
    Exit;
  end;
  SetSelectedNote(-1);
  Hit := ShapeAt(FShapes, At);
  if Hit < 0 then
  begin
    SetSelected(-1);
    Exit;
  end;
  SetSelected(FShapes[Hit].Placement);
  FGrab := Vec2(FDocument.Layout.Placements[FSelected].X - At.X, FDocument.Layout.Placements[FSelected].Y - At.Y);
  FMode := pmPressed;
end;

procedure TPreviewCanvas.MouseMove(Shift: TShiftState; X, Y: integer);
begin
  inherited MouseMove(Shift, X, Y);
  case FMode of
    pmPanning:
    begin
      FView.Pan(X - FLastPos.X, Y - FLastPos.Y);
      Invalidate;
    end;
    pmPressed:
      if Max(Abs(X - FPressPos.X), Abs(Y - FPressPos.Y)) >= DRAG_THRESHOLD then
      begin
        if FSelectedNote >= 0 then
          FDocument.BeginChange(rsPreviewMoveNote)
        else
          FDocument.BeginChange(rsPreviewMove);
        FMode := pmDragging;
        DragTo(X, Y);
      end;
    pmDragging:
      DragTo(X, Y);
    pmZoomPressed:
      if Max(Abs(X - FPressPos.X), Abs(Y - FPressPos.Y)) >= DRAG_THRESHOLD then
      begin
        FMode := pmZoomBoxing;
        Invalidate;
      end;
    pmZoomBoxing:
      Invalidate;
  end;
  FLastPos := Point(X, Y);
end;

procedure TPreviewCanvas.MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: integer);
begin
  inherited MouseUp(Button, Shift, X, Y);
  case FMode of
    pmDragging:
      FDocument.EndChange;
    pmZoomBoxing:
    begin
      FView.ZoomToBox(Vec2(FPressPos.X, FPressPos.Y), Vec2(X, Y), ClientWidth, ClientHeight);
      Invalidate;
    end;
    pmZoomPressed:
      if ssShift in Shift then
        ZoomBy(1 / PREVIEW_ZOOM_STEP, X, Y)
      else
        ZoomBy(PREVIEW_ZOOM_STEP, X, Y);
  end;
  FMode := pmIdle;
end;

function TPreviewCanvas.DoMouseWheel(Shift: TShiftState; WheelDelta: integer; MousePos: TPoint): boolean;
begin
  Result := True;
  FView.ZoomAt(Power(PREVIEW_ZOOM_STEP, WheelDelta / 120), Vec2(MousePos.X, MousePos.Y));
  Invalidate;
end;

procedure TPreviewCanvas.KeyDown(var Key: word; Shift: TShiftState);
begin
  inherited KeyDown(Key, Shift);
  if (Key <> 0) and (FMode = pmIdle) and (ShortCut(Key, Shift) = FZoomKey) then
  begin
    SetZoomArea(not FZoomArea);
    Key := 0;
    Exit;
  end;
  case Key of
    VK_SPACE:
      FSpaceDown := True;
    VK_DELETE, VK_BACK:
      RemoveSelected;
    VK_ESCAPE:
      if FMode = pmDragging then
      begin
        FMode := pmIdle;
        FDocument.CancelChange;
      end
      else if FMode = pmZoomBoxing then
      begin
        FMode := pmIdle;
        Invalidate;
      end
      else if FZoomArea then
        SetZoomArea(False)
      else
        SetSelected(-1);
    else
      Exit;
  end;
  Key := 0;
end;

procedure TPreviewCanvas.KeyUp(var Key: word; Shift: TShiftState);
begin
  inherited KeyUp(Key, Shift);
  if Key = VK_SPACE then
    FSpaceDown := False;
end;

function TPreviewCanvas.ScreenPoints(const Points: TVec2Array): specialize TArray<TPointF>;
var
  Index: integer;
  Screen: TVec2;
begin
  Result := nil;
  SetLength(Result, Length(Points));
  for Index := 0 to High(Points) do
  begin
    Screen := FView.ToScreen(Points[Index]);
    Result[Index] := PointF(Screen.X, Screen.Y);
  end;
end;

// The sheet of paper around the page's printable area
procedure TPreviewCanvas.DrawPage(const Page: TTilePage);
var
  TopLeft, BottomRight: TVec2;
  Fill: TBGRAPixel;
begin
  TopLeft := FView.ToScreen(Vec2(Page.Area.MinX, Page.Area.MinY));
  BottomRight := FView.ToScreen(Vec2(Page.Area.MaxX, Page.Area.MaxY));
  if Page.Blank or Page.Excluded then
    Fill := BlankPaperInk
  else
    Fill := PaperInk;
  FBitmap.FillRectAntialias(TopLeft.X, TopLeft.Y, BottomRight.X, BottomRight.Y, Fill);
  FBitmap.RectangleAntialias(TopLeft.X, TopLeft.Y, BottomRight.X, BottomRight.Y, EdgeInk, 1);
  if Page.Excluded then
  begin
    FBitmap.DrawLineAntialias(TopLeft.X, TopLeft.Y, BottomRight.X, BottomRight.Y, LeftOutInk, 1.5);
    FBitmap.DrawLineAntialias(BottomRight.X, TopLeft.Y, TopLeft.X, BottomRight.Y, LeftOutInk, 1.5);
  end;
  FBitmap.FontHeight := CAPTION_HEIGHT;
  FBitmap.TextOut(TopLeft.X + 4, TopLeft.Y + 2, Page.Caption, EdgeInk);
end;

procedure TPreviewCanvas.DrawShape(const Shape: TPlacedPiece);
var
  Line: TPlacedLine;
  Mark: TLine2;
  First, Last, Spot: TVec2;
  Ink: TBGRAPixel;
  LineWidth: single;
begin
  Ink := PieceInk;
  LineWidth := 1.5;
  if Shape.Placement = FSelected then
  begin
    Ink := SelectedInk;
    LineWidth := 2.5;
  end;
  if Shape.Look.Filled then
    FBitmap.FillPolyAntialias(ScreenPoints(Shape.CutLine), PieceTint(Shape.Look));
  FBitmap.DrawPolygonAntialias(ScreenPoints(Shape.CutLine), Ink, LineWidth);
  if Length(Shape.SeamLine) > 0 then
  begin
    FBitmap.PenStyle := psDash;
    FBitmap.DrawPolygonAntialias(ScreenPoints(Shape.SeamLine), Ink, 1);
    FBitmap.PenStyle := psSolid;
  end;
  for Mark in Shape.Marks do
  begin
    First := FView.ToScreen(Mark.P1);
    Last := FView.ToScreen(Mark.P2);
    FBitmap.DrawLineAntialias(First.X, First.Y, Last.X, Last.Y, Ink, 1);
  end;
  for Line in Shape.Lines do
  begin
    if ROLE_DASHES[Line.Role][0] > 0 then
      FBitmap.PenStyle := psDash;
    FBitmap.DrawPolyLineAntialias(ScreenPoints(Line.Points), Ink, 1);
    FBitmap.PenStyle := psSolid;
  end;
  if not Shape.ShowLabel then
    Exit;
  Spot := FView.ToScreen(Shape.LabelAt);
  FBitmap.FontHeight := LABEL_HEIGHT;
  FBitmap.TextOut(Spot.X, Spot.Y, Shape.Caption, Ink);
end;

procedure TPreviewCanvas.DrawZoomBox;
var
  X1, Y1, X2, Y2: single;
begin
  X1 := Min(FPressPos.X, FLastPos.X) + 0.5;
  X2 := Max(FPressPos.X, FLastPos.X) + 0.5;
  Y1 := Min(FPressPos.Y, FLastPos.Y) + 0.5;
  Y2 := Max(FPressPos.Y, FLastPos.Y) + 0.5;
  FBitmap.FillRectAntialias(X1, Y1, X2, Y2, ZoomBoxFill);
  FBitmap.PenStyle := psDot;
  FBitmap.RectangleAntialias(X1, Y1, X2, Y2, SelectedInk, 1);
  FBitmap.PenStyle := psSolid;
end;

// The layout's notes, which can be selected, and the pattern notes that print
// with the pieces, which move with them
procedure TPreviewCanvas.DrawNotes;
var
  Index: integer;
  Values: TFieldValues;
  Shape: TPlacedPiece;
  Note: TSheetNote;

  procedure DrawNote(const Item: TSheetNote; const Ink: TBGRAPixel);
  var
    Lines: TStringArray;
    LineIndex: integer;
    Spot, Start, First, Last: TVec2;
    Frame: TRect2;
    Stroke: TLine2;
  begin
    Frame := NoteFrameBounds(Item, Values);
    if (Item.Leader <> nlNone) and LeaderStart(Frame, Item.Tip, Start) then
    begin
      for Stroke in LeaderStrokes(Start, Item.Tip, Item.Leader) do
      begin
        First := FView.ToScreen(Stroke.P1);
        Last := FView.ToScreen(Stroke.P2);
        FBitmap.DrawLineAntialias(First.X, First.Y, Last.X, Last.Y, Ink, 1);
      end;
      if Item.Leader = nlDot then
      begin
        Spot := FView.ToScreen(Item.Tip);
        FBitmap.FillEllipseAntialias(Spot.X, Spot.Y, LEADER_DOT_RADIUS * FView.Scale + 0.5, LEADER_DOT_RADIUS * FView.Scale + 0.5, Ink);
      end;
    end;
    if Item.Boxed then
    begin
      First := FView.ToScreen(Vec2(Frame.MinX, Frame.MinY));
      Last := FView.ToScreen(Vec2(Frame.MaxX, Frame.MaxY));
      FBitmap.FillRectAntialias(First.X, First.Y, Last.X, Last.Y, PaperInk);
    end;
    Lines := TextLines(ExpandFields(Item.Text, Values));
    FBitmap.FontHeight := Max(MIN_NOTE_HEIGHT, Round(LineHeight(Item.Size) * FView.Scale));
    for LineIndex := 0 to High(Lines) do
    begin
      Spot := FView.ToScreen(Vec2(NoteLineLeft(Item, Values, Lines[LineIndex]), Item.Y));
      FBitmap.TextOut(Spot.X, Spot.Y + LineIndex * FBitmap.FontHeight, Lines[LineIndex], Ink);
    end;
  end;

begin
  Values := FDocument.Layout.FieldValues('', '');
  for Shape in FShapes do
    for Note in Shape.Notes do
      DrawNote(Note, PieceInk);
  for Index := 0 to High(FDocument.Layout.Notes) do
    if Index = FSelectedNote then
      DrawNote(FDocument.Layout.Notes[Index], SelectedInk)
    else
      DrawNote(FDocument.Layout.Notes[Index], PieceInk);
end;

procedure TPreviewCanvas.Paint;
var
  Page: TTilePage;
  Shape: TPlacedPiece;
  Whole: TRect2;
begin
  if (FBitmap.Width <> ClientWidth) or (FBitmap.Height <> ClientHeight) then
    FBitmap.SetSize(Max(ClientWidth, 1), Max(ClientHeight, 1));
  if FNeedsFit and PagesBounds(FPages, Whole) then
  begin
    FView.Fit(Whole, ClientWidth, ClientHeight, FIT_MARGIN);
    FNeedsFit := False;
  end;
  FBitmap.Fill(Desk);
  FBitmap.FontQuality := fqFineAntialiasing;
  // Used pages last, so their overlaps with blank ones stay white
  for Page in FPages do
    if Page.Blank then
      DrawPage(Page);
  for Page in FPages do
    if not Page.Blank and not Page.Excluded then
      DrawPage(Page);
  for Page in FPages do
    if Page.Excluded and not Page.Blank then
      DrawPage(Page);
  for Shape in FShapes do
    DrawShape(Shape);
  if Assigned(FDocument) then
    DrawNotes;
  if FMode = pmZoomBoxing then
    DrawZoomBox;
  FBitmap.Draw(Canvas, 0, 0, True);
  UpdateScrollBars;
end;

end.
