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
// is one change; everything else goes through the main form.
unit Sloper.Publish.PreviewCanvas;

{$mode ObjFPC}{$H+}

interface

uses
  Classes, SysUtils, Controls, Graphics, LCLType, BGRABitmap, BGRABitmapTypes, Sloper.Core.Materials, Sloper.Core.Geometry, Sloper.Core.Note,
  Sloper.Core.TextFields, Sloper.Output.Layout,
  Sloper.Output.LayoutDocument, Sloper.Output.Preview, Sloper.Output.Tiling;

type
  TPreviewMode = (pmIdle, pmPressed, pmDragging, pmPanning);

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
    FOnSelectionChange: TNotifyEvent;
    procedure SetSelected(Value: integer);
    procedure SetSelectedNote(Value: integer);
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
    // Layout position under a point of this control
    function LayoutAt(X, Y: integer): TVec2;
    // Sends the selected copy back to the tray, or deletes the selected note
    procedure RemoveSelected;
    property Document: TLayoutDocument read FDocument write FDocument;
    property Selected: integer read FSelected write SetSelected;
    property SelectedNote: integer read FSelectedNote write SetSelectedNote;
    property OnSelectionChange: TNotifyEvent read FOnSelectionChange write FOnSelectionChange;
    property OnDragOver;
    property OnDragDrop;
  end;

resourcestring
  rsPreviewMove = 'Move piece';
  rsPreviewTogglePage = 'Leave page out';
  rsPreviewRemove = 'Unplace piece';
  rsPreviewMoveNote = 'Move note';
  rsPreviewDeleteNote = 'Delete note';

implementation

uses
  Math, LCLIntf, Sloper.Core.Draft;

const
  FIT_MARGIN = 24;
  DRAG_THRESHOLD = 3;
  CAPTION_HEIGHT = 13;
  LABEL_HEIGHT = 12;
  MIN_NOTE_HEIGHT = 6;

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

procedure TPreviewCanvas.MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: integer);
var
  Hit: integer;
  At: TVec2;
begin
  inherited MouseDown(Button, Shift, X, Y);
  SetFocus;
  // SetFocus does nothing while this is already the active control, even
  // when a menu closed with Escape has left Qt's menu bar holding the
  // keyboard (see TPatternCanvas.TakeFocus)
  if HandleAllocated and not Focused then
    LCLIntf.SetFocus(Handle);
  FPressPos := Point(X, Y);
  FLastPos := FPressPos;
  if (Button = mbMiddle) or ((Button = mbLeft) and FSpaceDown) then
  begin
    FMode := pmPanning;
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
  end;
  FLastPos := Point(X, Y);
end;

procedure TPreviewCanvas.MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: integer);
begin
  inherited MouseUp(Button, Shift, X, Y);
  if FMode = pmDragging then
    FDocument.EndChange;
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
  if FNeedsFit and (Length(FPages) > 0) then
  begin
    Whole := FPages[0].Area;
    for Page in FPages do
    begin
      Whole.MaxX := Max(Whole.MaxX, Page.Area.MaxX);
      Whole.MaxY := Max(Whole.MaxY, Page.Area.MaxY);
    end;
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
  FBitmap.Draw(Canvas, 0, 0, True);
end;

end.
