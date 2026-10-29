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

// The drafting canvas: draws the pattern with BGRABitmap, pans and zooms,
// selects points and edges, and drags points. Objects are held by ID, since
// undo and redo replace the pattern's objects. Every edit goes through the
// document as a change; a drag is one change.
unit Sloper.UI.Canvas;

{$mode ObjFPC}{$H+}

interface

uses
  Classes, SysUtils, Controls, Graphics, LCLType, BGRABitmap, BGRABitmapTypes, Sloper.Core.Geometry,
  Sloper.Core.Draft, Sloper.Document.PatternDocument, Sloper.UI.View;

type
  TCanvasMode = (cmIdle, cmPressed, cmPanning, cmDragging);
  TCursorMoveEvent = procedure(Sender: TObject; const ModelPos: TVec2) of object;
  TCanvasMessageEvent = procedure(Sender: TObject; const Text: string) of object;

  TPatternCanvas = class(TCustomControl)
  private
    FDocument: TPatternDocument;
    FView: TViewTransform;
    FBitmap: TBGRABitmap;
    FSelection: TStringArray;
    FHoverKey: string;
    FMode: TCanvasMode;
    FPressPos, FLastPos: TPoint;
    FPressKey: string;
    FDragOffset: TVec2;
    FSpaceDown: boolean;
    FOnCursorMove: TCursorMoveEvent;
    FOnMessage: TCanvasMessageEvent;
    FOnSelectionChange: TNotifyEvent;
    procedure SetDocument(ADocument: TPatternDocument);
    procedure DocumentChanged(Document: TPatternDocument; Changes: TDocumentChanges);
    procedure ShowMessageText(const AText: string);
    function ModelAt(X, Y: integer): TVec2;
    function ObjectKeyAt(X, Y: integer): string;
    function IsSelected(const Key: string): boolean;
    procedure SetSelection(const Keys: TStringArray);
    procedure ToggleSelected(const Key: string);
    procedure DropMissingSelection;
    procedure StartDrag;
    procedure DragTo(X, Y: integer);
    procedure CancelDrag;
    procedure Nudge(DX, DY: double);
    procedure DrawGrid;
    procedure DrawEdge(Edge: TEdgeObject);
    procedure DrawPoint(Point: TPointObject);
    procedure DrawPattern;
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
    procedure ZoomIn;
    procedure ZoomOut;
    // Shows the whole pattern
    procedure ZoomToFit;
    // 1 mm on screen is 1 mm
    procedure ZoomTrueSize;
    procedure SelectNone;
    // Deletes the selected objects, the dependents first; nothing when any is in use
    procedure DeleteSelection;
    property Document: TPatternDocument read FDocument write SetDocument;
    // Keys of the selected objects
    property Selection: TStringArray read FSelection;
    property OnCursorMove: TCursorMoveEvent read FOnCursorMove write FOnCursorMove;
    // A hint or the reason something could not be done
    property OnMessage: TCanvasMessageEvent read FOnMessage write FOnMessage;
    property OnSelectionChange: TNotifyEvent read FOnSelectionChange write FOnSelectionChange;
  end;

resourcestring
  rsCanvasMovePoint = 'Move point';
  rsCanvasNudge = 'Nudge';
  rsCanvasDelete = 'Delete';
  rsCanvasHover = '%s: %s';

implementation

uses
  Math, Sloper.Core.EvalTypes, Sloper.Core.Evaluator, Sloper.Core.Drag, Sloper.UI.Scene;

const
  // Screen pixels
  PointRadius = 3.5;
  PointHitRadius = 7;
  EdgeHitRadius = 5;
  DragThreshold = 3;
  FitMargin = 40;
  FlattenPixels = 0.25;
  LabelFontHeight = 13;
  WheelPanPixels = 60;
  // Arrow-key nudges in mm
  NudgeStep = 1;
  NudgeStepLarge = 10;

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

function ScreenPoint(const P: TVec2): TPointF;
begin
  Result := PointF(P.X, P.Y);
end;

{ TPatternCanvas }

constructor TPatternCanvas.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FView := DefaultView;
  FBitmap := TBGRABitmap.Create(1, 1);
  TabStop := True;
  DoubleBuffered := False;
  ControlStyle := ControlStyle + [csOpaque];
end;

destructor TPatternCanvas.Destroy;
begin
  SetDocument(nil);
  FreeAndNil(FBitmap);
  inherited Destroy;
end;

procedure TPatternCanvas.SetDocument(ADocument: TPatternDocument);
begin
  if FDocument = ADocument then
    Exit;
  if FDocument <> nil then
    FDocument.RemoveListener(@DocumentChanged);
  FDocument := ADocument;
  FSelection := nil;
  FHoverKey := '';
  if FDocument <> nil then
    FDocument.AddListener(@DocumentChanged);
  Invalidate;
end;

procedure TPatternCanvas.DocumentChanged(Document: TPatternDocument; Changes: TDocumentChanges);
begin
  if dcObjectsReplaced in Changes then
    DropMissingSelection;
  Invalidate;
end;

procedure TPatternCanvas.ShowMessageText(const AText: string);
begin
  if Assigned(FOnMessage) then
    FOnMessage(Self, AText);
end;

function TPatternCanvas.ModelAt(X, Y: integer): TVec2;
begin
  Result := FView.ToModel(Vec2(X, Y));
end;

// Points take precedence over edges, so a point on an edge can be picked
function TPatternCanvas.ObjectKeyAt(X, Y: integer): string;
var
  Point: TPointObject;
  Edge: TEdgeObject;
begin
  Result := '';
  if FDocument = nil then
    Exit;
  Point := PointAt(FDocument.Pattern, ModelAt(X, Y), FView.PixelsToMM(PointHitRadius));
  if Point <> nil then
    Exit(Point.Key);
  Edge := EdgeAt(FDocument.Pattern, ModelAt(X, Y), FView.PixelsToMM(EdgeHitRadius));
  if Edge <> nil then
    Result := Edge.Key;
end;

function TPatternCanvas.IsSelected(const Key: string): boolean;
var
  Selected: string;
begin
  for Selected in FSelection do
    if Selected = Key then
      Exit(True);
  Result := False;
end;

procedure TPatternCanvas.SetSelection(const Keys: TStringArray);
begin
  FSelection := Keys;
  Invalidate;
  if Assigned(FOnSelectionChange) then
    FOnSelectionChange(Self);
end;

procedure TPatternCanvas.ToggleSelected(const Key: string);
var
  Kept: TStringArray;
  Selected: string;
begin
  if not IsSelected(Key) then
  begin
    Kept := Copy(FSelection, 0, Length(FSelection));
    Insert(Key, Kept, Length(Kept));
  end
  else
  begin
    Kept := nil;
    for Selected in FSelection do
      if Selected <> Key then
        Insert(Selected, Kept, Length(Kept));
  end;
  SetSelection(Kept);
end;

procedure TPatternCanvas.SelectNone;
begin
  if FSelection <> nil then
    SetSelection(nil);
end;

// After undo or redo some selected objects may be gone
procedure TPatternCanvas.DropMissingSelection;
var
  Kept: TStringArray;
  Selected: string;
begin
  Kept := nil;
  for Selected in FSelection do
    if FDocument.Pattern.FindNode(Selected) <> nil then
      Insert(Selected, Kept, Length(Kept));
  if Length(Kept) <> Length(FSelection) then
    SetSelection(Kept);
  if (FHoverKey <> '') and (FDocument.Pattern.FindNode(FHoverKey) = nil) then
    FHoverKey := '';
end;

procedure TPatternCanvas.ZoomIn;
begin
  FView.ZoomAt(ZoomStep, Vec2(ClientWidth / 2, ClientHeight / 2));
  Invalidate;
end;

procedure TPatternCanvas.ZoomOut;
begin
  FView.ZoomAt(1 / ZoomStep, Vec2(ClientWidth / 2, ClientHeight / 2));
  Invalidate;
end;

procedure TPatternCanvas.ZoomToFit;
var
  Bounds: TRect2;
begin
  if (FDocument <> nil) and PatternBounds(FDocument.Pattern, Bounds) then
    FView.Fit(Bounds, ClientWidth, ClientHeight, FitMargin)
  else
    FView := DefaultView;
  Invalidate;
end;

procedure TPatternCanvas.ZoomTrueSize;
begin
  FView.ZoomAt(TrueScale(Font.PixelsPerInch) / FView.Scale, Vec2(ClientWidth / 2, ClientHeight / 2));
  Invalidate;
end;

{ Dragging }

procedure TPatternCanvas.StartDrag;
var
  Point: TPointObject;
  Reason: string;
begin
  Point := TPointObject(FDocument.Pattern.FindNode(FPressKey));
  if not CanDrag(Point, Reason) then
  begin
    ShowMessageText(Reason);
    FMode := cmIdle;
    Exit;
  end;
  FDragOffset := Point.Position - ModelAt(FPressPos.X, FPressPos.Y);
  FDocument.BeginChange(rsCanvasMovePoint);
  FMode := cmDragging;
end;

procedure TPatternCanvas.DragTo(X, Y: integer);
var
  Point: TPointObject;
  Reason: string;
begin
  Point := TPointObject(FDocument.Pattern.FindNode(FPressKey));
  if DragPoint(FDocument.Pattern, Point, ModelAt(X, Y) + FDragOffset, Reason) then
    FDocument.LiveUpdate
  else
    ShowMessageText(Reason);
end;

procedure TPatternCanvas.CancelDrag;
begin
  if FMode = cmDragging then
    FDocument.CancelChange;
  FMode := cmIdle;
end;

procedure TPatternCanvas.Nudge(DX, DY: double);
var
  Selected, Reason, MergeKey: string;
  Node: TEvalNode;
  Moved: boolean;
begin
  if (FDocument = nil) or (FSelection = nil) then
    Exit;
  FDocument.BeginChange(rsCanvasNudge);
  Moved := False;
  MergeKey := 'nudge';
  for Selected in FSelection do
  begin
    Node := FDocument.Pattern.FindNode(Selected);
    if not (Node is TPointObject) then
      Continue;
    MergeKey := MergeKey + ':' + Selected;
    if not DragPoint(FDocument.Pattern, TPointObject(Node), TPointObject(Node).Position + Vec2(DX, DY), Reason) then
    begin
      ShowMessageText(Reason);
      FDocument.CancelChange;
      Exit;
    end;
    Moved := True;
  end;
  FDocument.Commit(Moved, MergeKey);
end;

procedure TPatternCanvas.DeleteSelection;
var
  Index: integer;
  Node: TEvalNode;
begin
  if (FDocument = nil) or (FSelection = nil) then
    Exit;
  FDocument.BeginChange(rsCanvasDelete);
  // Later objects can use earlier ones, so delete from the end of the pattern
  for Index := FDocument.Pattern.ObjectCount - 1 downto 0 do
  begin
    Node := FDocument.Pattern.Objects[Index];
    if IsSelected(Node.Key) and not FDocument.Pattern.Delete(Node) then
    begin
      ShowMessageText(FDocument.Pattern.LastError);
      FDocument.CancelChange;
      Exit;
    end;
  end;
  FDocument.EndChange;
  SetSelection(nil);
end;

{ Mouse and keys }

procedure TPatternCanvas.MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: integer);
begin
  inherited MouseDown(Button, Shift, X, Y);
  SetFocus;
  FPressPos := Point(X, Y);
  FLastPos := FPressPos;
  if (Button = mbMiddle) or ((Button = mbLeft) and FSpaceDown) then
  begin
    FMode := cmPanning;
    Exit;
  end;
  if (Button <> mbLeft) or (FDocument = nil) then
    Exit;
  FPressKey := ObjectKeyAt(X, Y);
  FMode := cmPressed;
end;

procedure TPatternCanvas.MouseMove(Shift: TShiftState; X, Y: integer);
var
  Key: string;
  Node: TEvalNode;
begin
  inherited MouseMove(Shift, X, Y);
  if Assigned(FOnCursorMove) then
    FOnCursorMove(Self, ModelAt(X, Y));
  case FMode of
    cmPanning:
    begin
      FView.Pan(X - FLastPos.X, Y - FLastPos.Y);
      Invalidate;
    end;
    cmPressed:
      if (FPressKey <> '') and (FDocument.Pattern.FindNode(FPressKey) is TPointObject) and
        (Max(Abs(X - FPressPos.X), Abs(Y - FPressPos.Y)) >= DragThreshold) then
      begin
        StartDrag;
        if FMode = cmDragging then
          DragTo(X, Y);
      end;
    cmDragging:
      DragTo(X, Y);
    cmIdle:
      if FDocument <> nil then
      begin
        Key := ObjectKeyAt(X, Y);
        if Key <> FHoverKey then
        begin
          FHoverKey := Key;
          Invalidate;
          Node := FDocument.Pattern.FindNode(Key);
          if (Node <> nil) and (Node.State <> esValid) then
            ShowMessageText(Format(rsCanvasHover, [Node.DisplayName, Node.Message]))
          else
            ShowMessageText('');
        end;
      end;
  end;
  FLastPos := Point(X, Y);
end;

procedure TPatternCanvas.MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: integer);
begin
  inherited MouseUp(Button, Shift, X, Y);
  case FMode of
    cmDragging:
    begin
      FDocument.EndChange;
      if not IsSelected(FPressKey) then
        SetSelection([FPressKey]);
    end;
    cmPressed:
      if FPressKey = '' then
      begin
        if not (ssShift in Shift) then
          SelectNone;
      end
      else if ssShift in Shift then
        ToggleSelected(FPressKey)
      else
        SetSelection([FPressKey]);
  end;
  FMode := cmIdle;
end;

function TPatternCanvas.DoMouseWheel(Shift: TShiftState; WheelDelta: integer; MousePos: TPoint): boolean;
var
  Steps: double;
begin
  Result := True;
  Steps := WheelDelta / 120;
  if ssModifier in Shift then
    FView.ZoomAt(Power(ZoomStep, Steps), Vec2(MousePos.X, MousePos.Y))
  else if ssShift in Shift then
    FView.Pan(Steps * WheelPanPixels, 0)
  else
    FView.Pan(0, Steps * WheelPanPixels);
  Invalidate;
end;

procedure TPatternCanvas.KeyDown(var Key: word; Shift: TShiftState);
var
  Step: double;
begin
  inherited KeyDown(Key, Shift);
  if ssShift in Shift then
    Step := NudgeStepLarge
  else
    Step := NudgeStep;
  case Key of
    VK_SPACE:
      FSpaceDown := True;
    VK_ESCAPE:
      if FMode = cmDragging then
        CancelDrag
      else
        SelectNone;
    VK_LEFT:
      Nudge(-Step, 0);
    VK_RIGHT:
      Nudge(Step, 0);
    VK_UP:
      Nudge(0, Step);
    VK_DOWN:
      Nudge(0, -Step);
    else
      Exit;
  end;
  Key := 0;
end;

procedure TPatternCanvas.KeyUp(var Key: word; Shift: TShiftState);
begin
  inherited KeyUp(Key, Shift);
  if Key = VK_SPACE then
    FSpaceDown := False;
end;

{ Drawing }

procedure TPatternCanvas.DrawGrid;
const
  Steps: array[0..9] of double = (1, 2, 5, 10, 20, 50, 100, 200, 500, 1000);
  MinSpacing = 10;
var
  Step, Major, Coord: double;
  Index: integer;
  TopLeft, BottomRight, Screen: TVec2;
  LineColor: TBGRAPixel;
begin
  Step := Steps[High(Steps)];
  for Index := 0 to High(Steps) do
    if Steps[Index] * FView.Scale >= MinSpacing then
    begin
      Step := Steps[Index];
      Break;
    end;
  Major := Step * 10;
  TopLeft := ModelAt(0, 0);
  BottomRight := ModelAt(ClientWidth, ClientHeight);

  Coord := Floor(TopLeft.X / Step) * Step;
  while Coord <= BottomRight.X do
  begin
    Screen := FView.ToScreen(Vec2(Coord, 0));
    if Abs(Coord / Major - Round(Coord / Major)) < 1e-9 then
      LineColor := GridMajor
    else
      LineColor := GridMinor;
    FBitmap.DrawVertLine(Round(Screen.X), 0, ClientHeight, LineColor);
    Coord := Coord + Step;
  end;
  Coord := Floor(BottomRight.Y / Step) * Step;
  while Coord <= TopLeft.Y do
  begin
    Screen := FView.ToScreen(Vec2(0, Coord));
    if Abs(Coord / Major - Round(Coord / Major)) < 1e-9 then
      LineColor := GridMajor
    else
      LineColor := GridMinor;
    FBitmap.DrawHorizLine(0, Round(Screen.Y), ClientWidth, LineColor);
    Coord := Coord + Step;
  end;
end;

procedure TPatternCanvas.DrawEdge(Edge: TEdgeObject);
var
  Model: TVec2Array;
  Screen: array of TPointF;
  Index: integer;
  LineColor: TBGRAPixel;
  LineWidth: single;
begin
  Model := EdgePolyline(Edge, FView.PixelsToMM(FlattenPixels));
  if Length(Model) < 2 then
    Exit;
  Screen := nil;
  SetLength(Screen, Length(Model));
  for Index := 0 to High(Model) do
    Screen[Index] := ScreenPoint(FView.ToScreen(Model[Index]));

  if Edge.Role = erOutline then
  begin
    LineColor := Ink;
    LineWidth := 2;
  end
  else
  begin
    LineColor := ConstructionInk;
    LineWidth := 1;
  end;
  LineColor := Faded(StateInk(Edge.State, LineColor), Edge.State);
  if Edge.Key = FHoverKey then
    FBitmap.DrawPolyLineAntialias(Screen, HoverHalo, LineWidth + 6);
  if IsSelected(Edge.Key) then
  begin
    LineColor := SelectedInk;
    LineWidth := LineWidth + 1;
  end;
  if Edge.Role = erConstruction then
    FBitmap.PenStyle := psDash;
  FBitmap.DrawPolyLineAntialias(Screen, LineColor, LineWidth);
  FBitmap.PenStyle := psSolid;
end;

procedure TPatternCanvas.DrawPoint(Point: TPointObject);
var
  Screen: TVec2;
  InkColor: TBGRAPixel;
  Radius: single;
begin
  Screen := FView.ToScreen(Point.Position);
  InkColor := Faded(StateInk(Point.State, Ink), Point.State);
  Radius := PointRadius;
  if Point.Key = FHoverKey then
    FBitmap.FillEllipseAntialias(Screen.X, Screen.Y, Radius + 5, Radius + 5, HoverHalo);
  if IsSelected(Point.Key) then
  begin
    InkColor := SelectedInk;
    Radius := Radius + 1.5;
  end;
  FBitmap.FillEllipseAntialias(Screen.X, Screen.Y, Radius, Radius, InkColor);
  FBitmap.TextOut(Screen.X + 6, Screen.Y - LabelFontHeight - 2, Point.Name, InkColor);
end;

procedure TPatternCanvas.DrawPattern;
var
  Index: integer;
  DraftObject: TDraftObject;
begin
  // Edges under points
  for Index := 0 to FDocument.Pattern.ObjectCount - 1 do
  begin
    DraftObject := FDocument.Pattern.Objects[Index];
    if (DraftObject is TEdgeObject) and DraftObject.HasResult then
      DrawEdge(TEdgeObject(DraftObject));
  end;
  for Index := 0 to FDocument.Pattern.ObjectCount - 1 do
  begin
    DraftObject := FDocument.Pattern.Objects[Index];
    if (DraftObject is TPointObject) and DraftObject.HasResult then
      DrawPoint(TPointObject(DraftObject));
  end;
end;

procedure TPatternCanvas.Paint;
begin
  if (FBitmap.Width <> ClientWidth) or (FBitmap.Height <> ClientHeight) then
    FBitmap.SetSize(Max(ClientWidth, 1), Max(ClientHeight, 1));
  FBitmap.Fill(Paper);
  FBitmap.FontHeight := LabelFontHeight;
  FBitmap.FontQuality := fqFineAntialiasing;
  DrawGrid;
  if FDocument <> nil then
    DrawPattern;
  FBitmap.Draw(Canvas, 0, 0, True);
end;

end.
