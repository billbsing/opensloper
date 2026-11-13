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

// The drafting canvas: shows the pattern (drawn by Sloper.UI.PatternPainter), pans and zooms
// (with the zoom tool's box too), selects points and edges, and drags points; the other tools are objects in
// Sloper.UI.CanvasTools, which the canvas hands its clicks, moves and keys.
// Objects are held by ID, since undo and redo replace the pattern's objects.
// Every edit goes through the document as a change; a drag is one change.
unit Sloper.UI.Canvas;

{$mode ObjFPC}{$H+}

interface

uses
  Classes, SysUtils, Controls, StdCtrls, Menus, Graphics, LCLType, LMessages, Sloper.Core.Geometry,
  Sloper.Core.Draft, Sloper.Core.Drag, Sloper.Core.Piece, Sloper.Core.Pattern, Sloper.Core.Transform, Sloper.Core.Settings,
  Sloper.Core.Measurements, Sloper.Core.Units, Sloper.Core.Note, Sloper.Core.TextFields, Sloper.Core.Fragment,
  Sloper.Document.PatternDocument, Sloper.UI.View, Sloper.UI.Snap,
  Sloper.UI.Scene, Sloper.UI.CanvasInput, Sloper.UI.SelectionEdits, Sloper.UI.PatternPainter, Sloper.UI.CanvasTools;

type
  TCursorMoveEvent = procedure(Sender: TObject; const ModelPos: TVec2) of object;
  TCanvasMessageEvent = procedure(Sender: TObject; const Text: string) of object;

  TPatternCanvas = class(TCustomControl)
  private
    FDocument: TPatternDocument;
    FView: TViewTransform;
    FPainter: TPatternPainter;
    FSelection: TStringArray;
    FHoverKey: string;
    FOutsideHoverKey: string;
    FInput: TCanvasInput;
    FPressPos, FLastPos: TPoint;
    FPressKey: string;
    // Where the last plain click selected something, for clicking again to
    // pick the next of the lines there
    FLastClickPos: TPoint;
    FHasLastClick: boolean;
    // Edges drawn in the same place as others, worked out for each paint
    FPickMenu: TPopupMenu;
    FDragOffset: TVec2;
    // The press landed on a curve's handle, or the handle is being dragged
    FPressHandle, FDraggingHandle: boolean;
    FHandle: TCurveHandle;
    // The field that identifies the handle under the cursor, and its curve
    FHoverHandleField, FHoverHandleEdge: string;
    FTool: TCanvasTool;
    // One of each tool, and what they ask of the canvas
    FTools: TCanvasToolHandlers;
    FToolHost: TCanvasToolHost;
    // Each tool's key, worked out once
    FToolKeys: array[TCanvasTool] of TShortCut;
    // A press on a selected callout's tip, and the tip being dragged
    FPressTip, FTipDragging: boolean;
    // Where a dragged tip snaps, and where the cursor was when it did
    FTipSnap: TSnap;
    FTipSnapShown: boolean;
    FTipClick: TVec2;
    FLabelMode: TLabelMode;
    FDrawRole: TEdgeRole;
    FShowPieceFills: boolean;
    // The grid's spacing, in GridUnit
    FGridStep: double;
    FGridUnit: TMeasureUnit;
    // The hold-for-all-labels key is down
    FLabelsHeld: boolean;
    FHorzBar, FVertBar: TScrollBar;
    // A thumb is being dragged, so its bar is left alone until it lets go
    FThumbHeld: boolean;
    // A transform waiting for its pivot or axis to be clicked
    FPicking: boolean;
    FPickKind: TTransformKind;
    FPickSources: TStringArray;
    FPickFirst: string;
    FOnToolChange: TNotifyEvent;
    FOnCursorMove: TCursorMoveEvent;
    FOnCursorLeave: TNotifyEvent;
    FOnViewChange: TNotifyEvent;
    // The view last reported through OnViewChange
    FReportedView: TViewTransform;
    FOnMessage: TCanvasMessageEvent;
    FOnSelectionChange: TNotifyEvent;
    FOnNoteAdded: TNotifyEvent;
    procedure TakeFocus;
    function NoteValues: TFieldValues;
    function NotesHere(X, Y: integer): TStringArray;
    function ActiveTool: TCanvasToolHandler;
    procedure UpdateTipSnap(X, Y: integer);
    procedure FinishTipDrag;
    function ClickKey(X, Y: integer; Shift: TShiftState): string;
    procedure ShowPickMenu(X, Y: integer);
    procedure PickMenuClick(Sender: TObject);
    procedure SetDocument(ADocument: TPatternDocument);
    procedure DocumentChanged(Document: TPatternDocument; Changes: TDocumentChanges);
    procedure ShowMessageText(const AText: string);
    procedure ApplyEdit(const Edit: TSelectionEdit);
    function PaintState: TPaintState;
    function ModelAt(X, Y: integer): TVec2;
    function ObjectKeyAt(X, Y: integer): string;
    function IsSelected(const Key: string): boolean;
    procedure SetSelection(const Keys: TStringArray);
    procedure StoreView;
    procedure PickHere(X, Y: integer);
    procedure EndPicking;
    procedure MakeTransform(const Spec: TTransformSpec);
    procedure ToggleSelected(const Key: string);
    procedure SelectBox(X, Y: integer; Adding: boolean);
    procedure ZoomClick(X, Y: integer; ZoomingOut: boolean);
    procedure DropMissingSelection;
    procedure StartDrag;
    procedure StartHandleDrag;
    procedure DragTo(X, Y: integer);
    function UpdateHoverHandle(X, Y: integer): boolean;
    procedure CancelDrag;
    procedure Nudge(DX, DY: double);
    procedure SetTool(Value: TCanvasTool);
    procedure CMWantSpecialKey(var Message: TCMWantSpecialKey); message CM_WANTSPECIALKEY;
    procedure SetLabelMode(Value: TLabelMode);
    procedure SetShowPieceFills(Value: boolean);
    procedure SetOutsideHoverKey(const Value: string);
    procedure SetLabelsHeld(Value: boolean);
    function ShownLabelMode: TLabelMode;
    procedure SetHorzBar(Value: TScrollBar);
    procedure SetVertBar(Value: TScrollBar);
    procedure BarScroll(Sender: TObject; ScrollCode: TScrollCode; var ScrollPos: integer);
    procedure ShowOnBar(Bar: TScrollBar; const Axis: TScrollAxis);
    procedure UpdateScrollBars;
  protected
    procedure Paint; override;
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: integer); override;
    procedure MouseMove(Shift: TShiftState; X, Y: integer); override;
    procedure MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: integer); override;
    function DoMouseWheel(Shift: TShiftState; WheelDelta: integer; MousePos: TPoint): boolean; override;
    procedure KeyDown(var Key: word; Shift: TShiftState); override;
    procedure KeyUp(var Key: word; Shift: TShiftState); override;
    procedure MouseLeave; override;
    procedure DoExit; override;
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
    // The pattern as it was last seen, or fitted
    procedure RestoreView;
    // The objects the canvas is naming now, for an export that matches it
    function ShownLabelKeys: TStringArray;
    // Selects these objects, as a click on the canvas would
    procedure SelectObjects(const Keys: TStringArray);
    // Brings the selection into view at the current zoom
    procedure RevealSelection;
    procedure ZoomToSelection;
    // Copies the selection with a transform: Move at once, Rotate and Mirror
    // once a pivot or axis has been clicked
    procedure StartTransform(Kind: TTransformKind);
    // An arc about the selected point
    procedure AddArcHere;
    // A construction edge parallel to the selected edge, or to the run the
    // selected edges make
    procedure OffsetSelection(Side: TOffsetSide);
    // An edge inside or outside the selected piece, along its selected edges
    procedure OffsetSelectionInPiece(Inside: boolean);
    // Changes the selected edges to lines or curves in place, as one undo step
    procedure ConvertSelection(ToCurve: boolean);
    // Merges the selected points into one, as one undo step, and selects it
    procedure MergeSelection;
    procedure AddRepeatAtSelection;
    // Breaks the selected point into one for each edge meeting there, as one
    // undo step, and selects them
    procedure BreakSelection;
    // Rounds the corner between the two selected edges
    procedure RoundSelectedCorner;
    // Selects the sources of the selected transform copies, or of a selected
    // transform, and brings them into view
    procedure GoToSource;
    // Locks or unlocks the selected objects
    procedure LockSelection(Lock: boolean);
    // mkPoint makes the selected points and repeats holes, which join the
    // pieces they lie in; the others add a marking to the selected piece
    // from the edge (or, for mkLine, the marked point) selected with it
    procedure MarkSelection(Kind: TMarkingKind);
    // Removes the selected piece's markings on the point or edge selected with it
    procedure UnmarkSelection;
    // Deletes the selected objects, the dependents first; nothing when any is in use
    procedure DeleteSelection;
    // The selected objects as a fragment for the clipboard; empty, with the
    // reason shown, when none can be copied
    function CopySelection: TFragmentCopy;
    // Copies the selected objects and deletes them, as one undo step. Empty,
    // with the reason shown, when any cannot be copied or deleted, and then
    // nothing is deleted.
    function CutSelection: TFragmentCopy;
    // Adds copied objects as one undo step and selects them; says why not otherwise
    procedure PasteFragmentText(const FragmentText: string);
    // Splits the selected edge at the selected point; says why not otherwise
    procedure SplitSelection;
    property Document: TPatternDocument read FDocument write SetDocument;
    // Keys of the selected objects
    property Selection: TStringArray read FSelection;
    property OnCursorMove: TCursorMoveEvent read FOnCursorMove write FOnCursorMove;
    property OnCursorLeave: TNotifyEvent read FOnCursorLeave write FOnCursorLeave;
    // After a paint that zoomed or panned, for the rulers
    property OnViewChange: TNotifyEvent read FOnViewChange write FOnViewChange;
    property View: TViewTransform read FView;
    // A hint or the reason something could not be done
    property OnMessage: TCanvasMessageEvent read FOnMessage write FOnMessage;
    property OnSelectionChange: TNotifyEvent read FOnSelectionChange write FOnSelectionChange;
    // After the Text tool places a note, which is then selected, so its text
    // can be typed
    property OnNoteAdded: TNotifyEvent read FOnNoteAdded write FOnNoteAdded;
    property Tool: TCanvasTool read FTool write SetTool;
    property OnToolChange: TNotifyEvent read FOnToolChange write FOnToolChange;
    property LabelMode: TLabelMode read FLabelMode write SetLabelMode;
    // The role of the lines, curves, circles, arcs and rectangles drawn next
    property DrawRole: TEdgeRole read FDrawRole write FDrawRole;
    property ShowPieceFills: boolean read FShowPieceFills write SetShowPieceFills;
    // An object pointed at somewhere else, such as a piece in the Garment
    // tab, shown as if hovered here while the pointer is not on the canvas
    property OutsideHoverKey: string read FOutsideHoverKey write SetOutsideHoverKey;
    // The grid's spacing in AUnit, from the preferences
    procedure SetGrid(Step: double; AUnit: TMeasureUnit);
    // Scroll bars to keep in step with the view
    property HorzBar: TScrollBar read FHorzBar write SetHorzBar;
    property VertBar: TScrollBar read FVertBar write SetVertBar;
  end;

resourcestring
  rsCanvasMovePoint = 'Move point';
  rsCanvasMoveNote = 'Move note';
  rsCanvasMoveTip = 'Move callout tip';
  rsCanvasMoveHandle = 'Move curve handle';
  rsCanvasPickPivot = 'Rotate Copy: click the point to turn about; Escape cancels';
  rsCanvasPickAxis = 'Mirror Copy: click a straight edge, or the first of two points; Escape cancels';
  rsCanvasPickSecond = 'Mirror Copy: click the second point; Escape cancels';
  rsCanvasPickPoint = 'Click a point';
  rsCanvasPickEdge = 'Click a straight edge or a point';
  rsCanvasNothingSelected = 'Select the points and edges to copy first';
  rsCanvasHover = '%s: %s';
  rsCanvasCycle = '%s (%d of %d here; click again for the next)';
  rsCanvasPickItem = '%s (%s)';

implementation

uses
  Math, Forms, StrUtils, LCLIntf, Sloper.UI.Commands, Sloper.Core.Bounds, Sloper.Core.EvalTypes, Sloper.Core.Evaluator,
  Sloper.UI.ObjectList;

const
  // Screen pixels
  POINT_HIT_RADIUS = 7;
  EDGE_HIT_RADIUS = 5;
  DRAG_THRESHOLD = 3;
  FIT_MARGIN = 40;
  WHEEL_PAN_PIXELS = 60;
  // Arrow-key nudges in mm
  NUDGE_STEP = 1;
  NUDGE_STEP_LARGE = 10;
  // A click this many pixels around a note's text picks it
  NOTE_HIT_PIXELS = 2;

type
  // How the tools reach the canvas
  TCanvasHost = class(TCanvasToolHost)
  private
    FCanvas: TPatternCanvas;
  public
    constructor Create(ACanvas: TPatternCanvas);
    function Document: TPatternDocument; override;
    function View: TViewTransform; override;
    function DrawRole: TEdgeRole; override;
    procedure Select(const Keys: TStringArray); override;
    procedure ShowMessage(const AText: string); override;
    procedure Refresh; override;
    procedure NoteAdded; override;
  end;

constructor TCanvasHost.Create(ACanvas: TPatternCanvas);
begin
  inherited Create;
  FCanvas := ACanvas;
end;

function TCanvasHost.Document: TPatternDocument;
begin
  Result := FCanvas.FDocument;
end;

function TCanvasHost.View: TViewTransform;
begin
  Result := FCanvas.FView;
end;

function TCanvasHost.DrawRole: TEdgeRole;
begin
  Result := FCanvas.FDrawRole;
end;

procedure TCanvasHost.Select(const Keys: TStringArray);
begin
  FCanvas.SetSelection(Keys);
end;

procedure TCanvasHost.ShowMessage(const AText: string);
begin
  FCanvas.ShowMessageText(AText);
end;

procedure TCanvasHost.Refresh;
begin
  FCanvas.Invalidate;
end;

procedure TCanvasHost.NoteAdded;
begin
  if Assigned(FCanvas.FOnNoteAdded) then
    FCanvas.FOnNoteAdded(FCanvas);
end;

{ TPatternCanvas }

constructor TPatternCanvas.Create(AOwner: TComponent);
var
  KeyTool: TCanvasTool;
begin
  inherited Create(AOwner);
  FView := DefaultView;
  FShowPieceFills := True;
  FDrawRole := erOutline;
  FGridUnit := muMillimetre;
  FGridStep := DEFAULT_GRID_STEPS[muMillimetre];
  FPainter := TPatternPainter.Create;
  FToolHost := TCanvasHost.Create(Self);
  FTools := CreateCanvasTools(FToolHost);
  for KeyTool := Low(TCanvasTool) to High(TCanvasTool) do
    FToolKeys[KeyTool] := CommandShortCut(CanvasToolInfo(KeyTool).Command);
  TabStop := True;
  DoubleBuffered := False;
  ControlStyle := ControlStyle + [csOpaque];
end;

destructor TPatternCanvas.Destroy;
begin
  SetDocument(nil);
  FreeCanvasTools(FTools);
  FreeAndNil(FToolHost);
  FreeAndNil(FPainter);
  inherited Destroy;
end;

function TPatternCanvas.ActiveTool: TCanvasToolHandler;
begin
  Result := FTools[FTool];
end;

procedure TPatternCanvas.SetDocument(ADocument: TPatternDocument);
begin
  if FDocument = ADocument then
    Exit;
  if Assigned(FDocument) then
    FDocument.RemoveListener(@DocumentChanged);
  FDocument := ADocument;
  FSelection := nil;
  FHoverKey := '';
  if Assigned(FDocument) then
    FDocument.AddListener(@DocumentChanged);
  Invalidate;
end;

procedure TPatternCanvas.DocumentChanged(Document: TPatternDocument; Changes: TDocumentChanges);
begin
  if dcObjectsReplaced in Changes then
  begin
    DropMissingSelection;
    ActiveTool.ObjectsReplaced;
    FTipSnapShown := False;
  end;
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

// Points take precedence over edges, so a point on an edge can be picked, and
// edges over pieces, which fill the space around them
function TPatternCanvas.ObjectKeyAt(X, Y: integer): string;
var
  Notes: TStringArray;
  Point: TPointObject;
  Edge: TEdgeObject;
  Piece: TPieceObject;
begin
  Result := '';
  if not Assigned(FDocument) then
    Exit;
  // Notes are drawn over everything, so they are picked first
  Notes := NotesHere(X, Y);
  if Length(Notes) > 0 then
    Exit(Notes[0]);
  Point := PointAt(FDocument.Pattern, ModelAt(X, Y), FView.PixelsToMM(POINT_HIT_RADIUS));
  if Assigned(Point) then
    Exit(Point.Key);
  Edge := EdgeAt(FDocument.Pattern, ModelAt(X, Y), FView.PixelsToMM(EDGE_HIT_RADIUS));
  if Assigned(Edge) then
    Exit(Edge.Key);
  Piece := PieceAt(FDocument.Pattern, ModelAt(X, Y));
  if Assigned(Piece) then
    Result := Piece.Key;
end;

// The fields notes show on the canvas
function TPatternCanvas.NoteValues: TFieldValues;
begin
  Result := PatternFieldValues(FDocument.Pattern, FDocument.FileName);
end;

function TPatternCanvas.NotesHere(X, Y: integer): TStringArray;
begin
  Result := NotesAt(FDocument.Pattern, ModelAt(X, Y), NoteValues, FView.PixelsToMM(NOTE_HIT_PIXELS));
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

procedure TPatternCanvas.SelectObjects(const Keys: TStringArray);
begin
  SetSelection(Keys);
end;

procedure TPatternCanvas.RestoreView;
begin
  if not Assigned(FDocument) then
    Exit;
  if FDocument.Pattern.View.HasView then
  begin
    FView.Scale := FDocument.Pattern.View.Zoom;
    FView.CentreOn(Vec2(FDocument.Pattern.View.CentreX, FDocument.Pattern.View.CentreY), ClientWidth, ClientHeight);
    Invalidate;
  end
  else
    ZoomToFit;
end;

// Kept on the pattern, which saves it with the file and keeps it through undo
procedure TPatternCanvas.StoreView;
var
  Centre: TVec2;
begin
  if not Assigned(FDocument) then
    Exit;
  Centre := FView.ToModel(Vec2(ClientWidth / 2, ClientHeight / 2));
  FDocument.Pattern.View.HasView := True;
  FDocument.Pattern.View.Zoom := FView.Scale;
  FDocument.Pattern.View.CentreX := Centre.X;
  FDocument.Pattern.View.CentreY := Centre.Y;
end;

procedure TPatternCanvas.RevealSelection;
var
  Bounds: TRect2;
begin
  if Assigned(FDocument) and ObjectsBounds(FDocument.Pattern, FSelection, Bounds) then
  begin
    FView.Reveal(Bounds, ClientWidth, ClientHeight, FIT_MARGIN);
    Invalidate;
  end;
end;

procedure TPatternCanvas.ZoomToSelection;
var
  Bounds: TRect2;
begin
  if Assigned(FDocument) and ObjectsBounds(FDocument.Pattern, FSelection, Bounds) then
  begin
    FView.Fit(Bounds, ClientWidth, ClientHeight, FIT_MARGIN);
    Invalidate;
  end;
end;

// Everything wholly inside the box from the press to (X, Y); Adding keeps
// what was selected, as Shift does for a click
procedure TPatternCanvas.SelectBox(X, Y: integer; Adding: boolean);
var
  Corner1, Corner2: TVec2;
  Box: TRect2;
  Keys: TStringArray;
  Key: string;
begin
  Corner1 := ModelAt(FPressPos.X, FPressPos.Y);
  Corner2 := ModelAt(X, Y);
  Box.MinX := Min(Corner1.X, Corner2.X);
  Box.MaxX := Max(Corner1.X, Corner2.X);
  Box.MinY := Min(Corner1.Y, Corner2.Y);
  Box.MaxY := Max(Corner1.Y, Corner2.Y);
  Keys := nil;
  if Adding then
    Keys := Copy(FSelection, 0, Length(FSelection));
  for Key in ObjectsInBox(FDocument.Pattern, Box) do
    if not Adding or not IsSelected(Key) then
      Insert(Key, Keys, Length(Keys));
  SetSelection(Keys);
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
  if Length(FSelection) > 0 then
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
    if Assigned(FDocument.Pattern.FindNode(Selected)) then
      Insert(Selected, Kept, Length(Kept));
  if Length(Kept) <> Length(FSelection) then
    SetSelection(Kept);
  if (FHoverKey <> '') and not Assigned(FDocument.Pattern.FindNode(FHoverKey)) then
    FHoverKey := '';
end;

procedure TPatternCanvas.ZoomIn;
begin
  FView.ZoomAt(ZOOM_STEP, Vec2(ClientWidth / 2, ClientHeight / 2));
  Invalidate;
end;

procedure TPatternCanvas.ZoomOut;
begin
  FView.ZoomAt(1 / ZOOM_STEP, Vec2(ClientWidth / 2, ClientHeight / 2));
  Invalidate;
end;

// A step about the point clicked, as the wheel zooms
procedure TPatternCanvas.ZoomClick(X, Y: integer; ZoomingOut: boolean);
begin
  if ZoomingOut then
    FView.ZoomAt(1 / ZOOM_STEP, Vec2(X, Y))
  else
    FView.ZoomAt(ZOOM_STEP, Vec2(X, Y));
  Invalidate;
end;

procedure TPatternCanvas.ZoomToFit;
var
  Bounds: TRect2;
begin
  if Assigned(FDocument) and PatternBounds(FDocument.Pattern, Bounds, not FDocument.Pattern.View.HideAnnotations) then
    FView.Fit(Bounds, ClientWidth, ClientHeight, FIT_MARGIN)
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
  Node: TEvalNode;
  Point: TPointObject;
  Reason: string;
begin
  Node := FDocument.Pattern.FindNode(FPressKey);
  if Node is TNoteObject then
  begin
    if not CanDragNote(TNoteObject(Node), Reason) then
    begin
      ShowMessageText(Reason);
      FInput.Mode := cmRefused;
      Exit;
    end;
    FDragOffset := TNoteObject(Node).Position - ModelAt(FPressPos.X, FPressPos.Y);
    FDocument.BeginChange(rsCanvasMoveNote);
    FInput.Mode := cmDragging;
    Exit;
  end;
  Point := TPointObject(Node);
  if not CanDrag(FDocument.Pattern, Point, Reason) then
  begin
    ShowMessageText(Reason);
    FInput.Mode := cmRefused;
    Exit;
  end;
  FDragOffset := Point.Position - ModelAt(FPressPos.X, FPressPos.Y);
  FDocument.BeginChange(rsCanvasMovePoint);
  FInput.Mode := cmDragging;
end;

procedure TPatternCanvas.StartHandleDrag;
var
  Reason: string;
begin
  if not CanDragHandle(TEdgeObject(FDocument.Pattern.FindNode(FHandle.EdgeKey)), FHandle, Reason) then
  begin
    ShowMessageText(Reason);
    FInput.Mode := cmRefused;
    Exit;
  end;
  FDragOffset := FHandle.Position - ModelAt(FPressPos.X, FPressPos.Y);
  FDocument.BeginChange(rsCanvasMoveHandle);
  FDraggingHandle := True;
  FInput.Mode := cmDragging;
end;

procedure TPatternCanvas.DragTo(X, Y: integer);
var
  Node: TEvalNode;
  Point: TPointObject;
  Reason: string;
begin
  if FDraggingHandle then
  begin
    if DragHandle(FDocument.Pattern, TEdgeObject(FDocument.Pattern.FindNode(FHandle.EdgeKey)), FHandle, ModelAt(X, Y) + FDragOffset, Reason) then
      FDocument.LiveUpdate
    else
      ShowMessageText(Reason);
    Exit;
  end;
  Node := FDocument.Pattern.FindNode(FPressKey);
  if Node is TNoteObject then
  begin
    if DragNote(FDocument.Pattern, TNoteObject(Node), ModelAt(X, Y) + FDragOffset, Reason) then
      FDocument.LiveUpdate
    else
      ShowMessageText(Reason);
    Exit;
  end;
  Point := TPointObject(Node);
  if DragPoint(FDocument.Pattern, Point, ModelAt(X, Y) + FDragOffset, Reason) then
    FDocument.LiveUpdate
  else
    ShowMessageText(Reason);
end;

procedure TPatternCanvas.CancelDrag;
begin
  // A tip being dragged has changed nothing yet
  if FTipDragging then
  begin
    FTipDragging := False;
    FTipSnapShown := False;
    Invalidate;
  end
  else if FInput.Mode = cmDragging then
    FDocument.CancelChange;
  FInput.Mode := cmIdle;
  FDraggingHandle := False;
end;

// True when the cursor moved on or off a handle, or to another one
function TPatternCanvas.UpdateHoverHandle(X, Y: integer): boolean;
var
  Found: TCurveHandle;
  FieldName, EdgeKey: string;
begin
  FieldName := '';
  EdgeKey := '';
  if HandleAt(FDocument.Pattern, FSelection, ModelAt(X, Y), FView.PixelsToMM(POINT_HIT_RADIUS), Found) then
  begin
    FieldName := Found.LengthField;
    EdgeKey := Found.EdgeKey;
  end;
  Result := (FieldName <> FHoverHandleField) or (EdgeKey <> FHoverHandleEdge);
  FHoverHandleField := FieldName;
  FHoverHandleEdge := EdgeKey;
end;

procedure TPatternCanvas.ApplyEdit(const Edit: TSelectionEdit);
begin
  if Edit.Reselect then
    SetSelection(Edit.Selection);
  if Edit.Message <> '' then
    ShowMessageText(Edit.Message);
  Invalidate;
end;

procedure TPatternCanvas.Nudge(DX, DY: double);
begin
  if Assigned(FDocument) then
    ApplyEdit(NudgeSelection(FDocument, FSelection, Vec2(DX, DY)));
end;

procedure TPatternCanvas.DeleteSelection;
begin
  if Assigned(FDocument) then
    ApplyEdit(Sloper.UI.SelectionEdits.DeleteSelection(FDocument, FSelection, rsSelectionDelete));
end;

function TPatternCanvas.CopySelection: TFragmentCopy;
begin
  Result := Default(TFragmentCopy);
  if Assigned(FDocument) then
    ApplyEdit(Sloper.UI.SelectionEdits.CopySelection(FDocument, FSelection, Result));
end;

function TPatternCanvas.CutSelection: TFragmentCopy;
begin
  Result := Default(TFragmentCopy);
  if Assigned(FDocument) then
    ApplyEdit(Sloper.UI.SelectionEdits.CutSelection(FDocument, FSelection, Result));
end;

procedure TPatternCanvas.PasteFragmentText(const FragmentText: string);
begin
  if Assigned(FDocument) then
    ApplyEdit(Sloper.UI.SelectionEdits.PasteFragmentText(FDocument, FragmentText));
end;

procedure TPatternCanvas.SplitSelection;
begin
  if Assigned(FDocument) then
    ApplyEdit(Sloper.UI.SelectionEdits.SplitSelection(FDocument, FSelection));
end;

{ Transforms }

procedure TPatternCanvas.EndPicking;
begin
  FPicking := False;
  FPickFirst := '';
  FPickSources := nil;
  if FTool = ctSelect then
    Cursor := crDefault;
end;

procedure TPatternCanvas.AddArcHere;
begin
  if Assigned(FDocument) then
    ApplyEdit(AddArcAtSelection(FDocument, FSelection, FDrawRole));
end;

procedure TPatternCanvas.OffsetSelection(Side: TOffsetSide);
begin
  if Assigned(FDocument) then
    ApplyEdit(Sloper.UI.SelectionEdits.OffsetSelection(FDocument, FSelection, Side));
end;

procedure TPatternCanvas.OffsetSelectionInPiece(Inside: boolean);
begin
  if Assigned(FDocument) then
    ApplyEdit(Sloper.UI.SelectionEdits.OffsetSelectionInPiece(FDocument, FSelection, Inside));
end;

procedure TPatternCanvas.ConvertSelection(ToCurve: boolean);
begin
  if Assigned(FDocument) then
    ApplyEdit(Sloper.UI.SelectionEdits.ConvertSelection(FDocument, FSelection, ToCurve));
end;

procedure TPatternCanvas.MergeSelection;
begin
  if Assigned(FDocument) then
    ApplyEdit(Sloper.UI.SelectionEdits.MergeSelection(FDocument, FSelection));
end;

procedure TPatternCanvas.AddRepeatAtSelection;
begin
  if Assigned(FDocument) then
    ApplyEdit(Sloper.UI.SelectionEdits.AddRepeatAtSelection(FDocument, FSelection));
end;

procedure TPatternCanvas.BreakSelection;
begin
  if Assigned(FDocument) then
    ApplyEdit(Sloper.UI.SelectionEdits.BreakSelection(FDocument, FSelection));
end;

procedure TPatternCanvas.LockSelection(Lock: boolean);
begin
  if Assigned(FDocument) then
    ApplyEdit(Sloper.UI.SelectionEdits.LockSelection(FDocument, FSelection, Lock));
end;

procedure TPatternCanvas.GoToSource;
var
  Edit: TSelectionEdit;
begin
  if not Assigned(FDocument) then
    Exit;
  Edit := Sloper.UI.SelectionEdits.GoToSource(FDocument, FSelection);
  ApplyEdit(Edit);
  if Edit.Done then
    RevealSelection;
end;

procedure TPatternCanvas.RoundSelectedCorner;
begin
  if Assigned(FDocument) then
    ApplyEdit(Sloper.UI.SelectionEdits.RoundSelectedCorner(FDocument, FSelection));
end;

procedure TPatternCanvas.MarkSelection(Kind: TMarkingKind);
begin
  if Assigned(FDocument) then
    ApplyEdit(Sloper.UI.SelectionEdits.MarkSelection(FDocument, FSelection, Kind));
end;

procedure TPatternCanvas.UnmarkSelection;
begin
  if Assigned(FDocument) then
    ApplyEdit(Sloper.UI.SelectionEdits.UnmarkSelection(FDocument, FSelection));
end;

procedure TPatternCanvas.StartTransform(Kind: TTransformKind);
var
  Spec: TTransformSpec;
begin
  if not Assigned(FDocument) then
    Exit;
  if Length(FSelection) = 0 then
  begin
    ShowMessageText(rsCanvasNothingSelected);
    Exit;
  end;
  if Kind = tkMove then
  begin
    Spec := Default(TTransformSpec);
    Spec.Kind := tkMove;
    Spec.Sources := Copy(FSelection);
    Spec.DX := '0';
    Spec.DY := '0';
    MakeTransform(Spec);
    Exit;
  end;
  FPicking := True;
  FPickKind := Kind;
  FPickFirst := '';
  FPickSources := Copy(FSelection);
  Cursor := crCross;
  if Kind = tkRotate then
    ShowMessageText(rsCanvasPickPivot)
  else
    ShowMessageText(rsCanvasPickAxis);
end;

procedure TPatternCanvas.MakeTransform(const Spec: TTransformSpec);
begin
  EndPicking;
  ApplyEdit(AddTransform(FDocument, Spec));
end;

procedure TPatternCanvas.PickHere(X, Y: integer);
var
  At: TVec2;
  Point: TPointObject;
  Edge: TEdgeObject;
  Spec: TTransformSpec;
begin
  At := ModelAt(X, Y);
  Point := PointAt(FDocument.Pattern, At, FView.PixelsToMM(POINT_HIT_RADIUS));
  Spec := Default(TTransformSpec);
  Spec.Kind := FPickKind;
  Spec.Sources := FPickSources;
  if FPickKind = tkRotate then
  begin
    if not Assigned(Point) then
    begin
      ShowMessageText(rsCanvasPickPoint);
      Exit;
    end;
    Spec.Pivot := Point.Key;
    Spec.Angle := '0';
    MakeTransform(Spec);
  end
  else if Assigned(Point) then
  begin
    if FPickFirst = '' then
    begin
      FPickFirst := Point.Key;
      ShowMessageText(rsCanvasPickSecond);
      Exit;
    end;
    Spec.AxisA := FPickFirst;
    Spec.AxisB := Point.Key;
    MakeTransform(Spec);
  end
  else
  begin
    Edge := EdgeAt(FDocument.Pattern, At, FView.PixelsToMM(EDGE_HIT_RADIUS));
    if not Assigned(Edge) then
    begin
      ShowMessageText(rsCanvasPickEdge);
      Exit;
    end;
    Spec.AxisEdge := Edge.Key;
    MakeTransform(Spec);
  end;
end;

{ Drawing tools }

procedure TPatternCanvas.SetTool(Value: TCanvasTool);
begin
  EndPicking;
  ActiveTool.Reset;
  FTipSnapShown := False;
  if FInput.Mode = cmDragging then
    CancelDrag;
  FTool := Value;
  ActiveTool.Reset;
  if FTool <> ctSelect then
    FHoverKey := '';
  if FTool = ctSelect then
    Cursor := crDefault
  else
    Cursor := crCross;
  ShowMessageText(ActiveTool.Hint);
  Invalidate;
  if Assigned(FOnToolChange) then
    FOnToolChange(Self);
end;

// Where a dragged callout tip would hang from
procedure TPatternCanvas.UpdateTipSnap(X, Y: integer);
begin
  FTipSnap := FindSnap(FDocument.Pattern, ModelAt(X, Y), FView.PixelsToMM(SNAP_RADIUS));
  FTipClick := ModelAt(X, Y);
  FTipSnapShown := True;
  ShowMessageText(CalloutSnapDescription(FDocument.Pattern, FTipSnap, FTipClick));
  Invalidate;
end;

procedure TPatternCanvas.SetLabelMode(Value: TLabelMode);
begin
  FLabelMode := Value;
  Invalidate;
end;

procedure TPatternCanvas.SetShowPieceFills(Value: boolean);
begin
  FShowPieceFills := Value;
  Invalidate;
end;

procedure TPatternCanvas.SetGrid(Step: double; AUnit: TMeasureUnit);
begin
  if Step <= 0 then
    Exit;
  FGridStep := Step;
  FGridUnit := AUnit;
  Invalidate;
end;

procedure TPatternCanvas.SetLabelsHeld(Value: boolean);
begin
  if Value = FLabelsHeld then
    Exit;
  FLabelsHeld := Value;
  Invalidate;
end;

function TPatternCanvas.ShownLabelMode: TLabelMode;
begin
  if FLabelsHeld then
    Result := lmAll
  else
    Result := FLabelMode;
end;

function TPatternCanvas.ShownLabelKeys: TStringArray;
begin
  Result := nil;
  if Assigned(FDocument) then
    Result := LabelKeys(FDocument.Pattern, ShownLabelMode, FSelection, FHoverKey, ActiveTool.LabelKeys);
end;

// The dropped tip hangs the callout from what it snaps to; its text stays put
procedure TPatternCanvas.FinishTipDrag;
var
  Node: TEvalNode;
  Reason: string;
  Done: boolean;
begin
  FTipDragging := False;
  FTipSnapShown := False;
  Node := FDocument.Pattern.FindNode(FPressKey);
  if not (Node is TNoteObject) then
    Exit;
  FDocument.BeginChange(rsCanvasMoveTip);
  Done := ReanchorFromSnap(FDocument.Pattern, TNoteObject(Node), FTipSnap, FTipClick);
  Reason := FDocument.Pattern.LastError;
  FDocument.Commit(Done);
  if not Done then
    ShowMessageText(Reason);
  Invalidate;
end;

// Tab would otherwise move the focus to the next control
procedure TPatternCanvas.CMWantSpecialKey(var Message: TCMWantSpecialKey);
begin
  if (Message.CharCode = VK_TAB) and ActiveTool.HandlesKey(VK_TAB) then
    Message.Result := 1
  else
    inherited;
end;

{ Mouse and keys }

// SetFocus does nothing while the canvas is already the form's active
// control, even when the keyboard has gone elsewhere: on Qt a menu closed with
// Escape leaves the menu bar holding it, and no shortcut then works. So ask
// the widgetset directly when the canvas does not really have it.
procedure TPatternCanvas.TakeFocus;
begin
  SetFocus;
  if HandleAllocated and not Focused then
    LCLIntf.SetFocus(Handle);
end;

function CanvasButton(Button: TMouseButton): TCanvasButton;
begin
  case Button of
    mbLeft: Result := cbLeft;
    mbMiddle: Result := cbMiddle;
    mbRight: Result := cbRight;
    else
      Result := cbOther;
  end;
end;

procedure TPatternCanvas.MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: integer);
var
  Pressed: TCanvasButton;
begin
  inherited MouseDown(Button, Shift, X, Y);
  TakeFocus;
  Pressed := CanvasButton(Button);
  // The release of the button that began the gesture never came
  if FInput.Holds(Pressed) then
  begin
    CancelDrag;
    Invalidate;
  end;
  // One gesture at a time: a drag holds an open change until its release
  if FInput.Press(Pressed) = paIgnore then
    Exit;
  FPressPos := Point(X, Y);
  FLastPos := FPressPos;
  if FInput.Mode = cmPanning then
    Exit;
  if not Assigned(FDocument) then
    Exit;
  if FPicking then
  begin
    if Button = mbLeft then
      PickHere(X, Y);
    Exit;
  end;
  // The zoom tool's box is the select tool's, with nothing under it to drag
  if FTool = ctZoom then
  begin
    if Button = mbLeft then
    begin
      FPressKey := '';
      FPressTip := False;
      FPressHandle := False;
      FInput.Mode := cmPressed;
    end;
    Exit;
  end;
  if FTool <> ctSelect then
  begin
    ActiveTool.Press(Pressed, Shift, X, Y);
    Exit;
  end;
  if Button = mbRight then
  begin
    ShowPickMenu(X, Y);
    Exit;
  end;
  if Button <> mbLeft then
    Exit;
  // Double-clicking a copy, which its first click selected, goes to its
  // source; the press starts nothing, so its release does not cycle on
  if (ssDouble in Shift) and (Length(FSelection) = 1) and (CopyTransformKey(FDocument.Pattern.FindNode(FSelection[0])) <> '') then
  begin
    GoToSource;
    Exit;
  end;
  // A callout's tip or a curve's handle lies over whatever else is there
  FPressKey := CalloutTipAt(FDocument.Pattern, FSelection, ModelAt(X, Y), FView.PixelsToMM(POINT_HIT_RADIUS));
  FPressTip := FPressKey <> '';
  FPressHandle := not FPressTip and HandleAt(FDocument.Pattern, FSelection, ModelAt(X, Y), FView.PixelsToMM(POINT_HIT_RADIUS), FHandle);
  if FPressHandle then
    FPressKey := FHandle.EdgeKey
  else if not FPressTip then
    FPressKey := ObjectKeyAt(X, Y);
  FInput.Mode := cmPressed;
end;

procedure TPatternCanvas.MouseMove(Shift: TShiftState; X, Y: integer);
var
  Key: string;
  Node: TEvalNode;
begin
  inherited MouseMove(Shift, X, Y);
  if Assigned(FOnCursorMove) then
    FOnCursorMove(Self, ModelAt(X, Y));
  case FInput.Mode of
    cmPanning:
    begin
      FView.Pan(X - FLastPos.X, Y - FLastPos.Y);
      Invalidate;
    end;
    cmPressed:
      if Max(Abs(X - FPressPos.X), Abs(Y - FPressPos.Y)) >= DRAG_THRESHOLD then
        if FPressTip and FDocument.Pattern.IsLocked(FDocument.Pattern.FindNode(FPressKey)) then
        begin
          ShowMessageText(Format(rsPatternLocked, [FDocument.Pattern.FindNode(FPressKey).DisplayName]));
          FInput.Mode := cmRefused;
        end
        else if FPressTip then
        begin
          FTipDragging := True;
          FInput.Mode := cmDragging;
          UpdateTipSnap(X, Y);
        end
        else if FPressHandle then
        begin
          StartHandleDrag;
          if FInput.Mode = cmDragging then
            DragTo(X, Y);
        end
        else if (FPressKey <> '') and ((FDocument.Pattern.FindNode(FPressKey) is TPointObject) or (FDocument.Pattern.FindNode(FPressKey) is TNoteObject)) then
        begin
          StartDrag;
          if FInput.Mode = cmDragging then
            DragTo(X, Y);
        end
        else
        begin
          FInput.Mode := cmBoxing;
          Invalidate;
        end;
    cmDragging:
      if FTipDragging then
        UpdateTipSnap(X, Y)
      else
        DragTo(X, Y);
    cmBoxing:
      Invalidate;
    cmIdle:
      if Assigned(FDocument) and (FTool <> ctSelect) then
        ActiveTool.Move(X, Y)
      else if Assigned(FDocument) then
      begin
        if UpdateHoverHandle(X, Y) then
          Invalidate;
        Key := ObjectKeyAt(X, Y);
        if Key <> FHoverKey then
        begin
          FHoverKey := Key;
          Invalidate;
          Node := FDocument.Pattern.FindNode(Key);
          if Assigned(Node) and (Node.State <> esValid) then
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
  // Another button let go mid-gesture leaves it running
  if not FInput.Holds(CanvasButton(Button)) then
    Exit;
  case FInput.Mode of
    cmDragging:
      if FTipDragging then
        FinishTipDrag
      else
      begin
        FDocument.EndChange;
        FDraggingHandle := False;
        if not IsSelected(FPressKey) then
          SetSelection([FPressKey]);
      end;
    cmBoxing:
    begin
      if FTool = ctZoom then
        FView.ZoomToBox(Vec2(FPressPos.X, FPressPos.Y), Vec2(X, Y), ClientWidth, ClientHeight)
      else
        SelectBox(X, Y, ssShift in Shift);
      Invalidate;
    end;
    cmPressed:
      if FTool = ctZoom then
        ZoomClick(X, Y, ssShift in Shift)
      // A click on a handle or a callout's tip leaves the selection as it is
      else if not FPressHandle and not FPressTip then
        if FPressKey = '' then
        begin
          if not (ssShift in Shift) then
            SelectNone;
        end
        else if ssShift in Shift then
          ToggleSelected(FPressKey)
        else
          SetSelection([ClickKey(X, Y, Shift)]);
  end;
  FInput.Mode := cmIdle;
end;

// What a plain click selects. Clicking again where lines lie in the same
// place picks the next of them, and Alt-click the next of everything there;
// the status bar says which it is.
function TPatternCanvas.ClickKey(X, Y: integer; Shift: TShiftState): string;
var
  Here, Choices: TStringArray;
  Again: boolean;
  Index: integer;
begin
  Result := FPressKey;
  Here := Concat(NotesHere(X, Y), ObjectsAt(FDocument.Pattern, ModelAt(X, Y), FView.PixelsToMM(POINT_HIT_RADIUS), FView.PixelsToMM(EDGE_HIT_RADIUS)));
  Again := FHasLastClick and (Max(Abs(X - FLastClickPos.X), Abs(Y - FLastClickPos.Y)) < DRAG_THRESHOLD) and (Length(FSelection) = 1);
  FLastClickPos := Point(X, Y);
  FHasLastClick := True;
  if ssAlt in Shift then
    Choices := Here
  else
    Choices := EdgeKeys(FDocument.Pattern, Here);
  if Length(Choices) < 2 then
    Exit;
  if (ssAlt in Shift) or (Again and (IndexStr(FSelection[0], Choices) >= 0)) then
    if (Length(FSelection) = 1) and (IndexStr(FSelection[0], Choices) >= 0) then
      Result := NextKey(Choices, FSelection[0])
    else
      Result := Choices[0];
  Index := IndexStr(Result, Choices);
  if Index >= 0 then
    ShowMessageText(Format(rsCanvasCycle, [FDocument.Pattern.FindNode(Result).DisplayName, Index + 1, Length(Choices)]));
end;

// Everything under the pointer, to pick one where several lie together
procedure TPatternCanvas.ShowPickMenu(X, Y: integer);
var
  Here: TStringArray;
  Key: string;
  Item: TMenuItem;
  Node: TEvalNode;
  Screen: TPoint;
begin
  Here := Concat(NotesHere(X, Y), ObjectsAt(FDocument.Pattern, ModelAt(X, Y), FView.PixelsToMM(POINT_HIT_RADIUS), FView.PixelsToMM(EDGE_HIT_RADIUS)));
  if Length(Here) = 0 then
    Exit;
  if not Assigned(FPickMenu) then
    FPickMenu := TPopupMenu.Create(Self);
  FPickMenu.Items.Clear;
  for Key in Here do
  begin
    Node := FDocument.Pattern.FindNode(Key);
    Item := TMenuItem.Create(FPickMenu);
    Item.Caption := Format(rsCanvasPickItem, [Node.DisplayName, TypeCaption(Node)]);
    Item.Hint := Key;
    Item.Checked := IsSelected(Key);
    Item.OnClick := @PickMenuClick;
    FPickMenu.Items.Add(Item);
  end;
  Screen := ClientToScreen(Point(X, Y));
  FPickMenu.PopUp(Screen.X, Screen.Y);
end;

procedure TPatternCanvas.PickMenuClick(Sender: TObject);
begin
  SetSelection([TMenuItem(Sender).Hint]);
  Invalidate;
end;

function TPatternCanvas.DoMouseWheel(Shift: TShiftState; WheelDelta: integer; MousePos: TPoint): boolean;
var
  Steps: double;
begin
  Result := True;
  Steps := WheelDelta / 120;
  if ssModifier in Shift then
    FView.ZoomAt(Power(ZOOM_STEP, Steps), Vec2(MousePos.X, MousePos.Y))
  else if ssShift in Shift then
    FView.Pan(Steps * WHEEL_PAN_PIXELS, 0)
  else
    FView.Pan(0, Steps * WHEEL_PAN_PIXELS);
  Invalidate;
end;

procedure TPatternCanvas.KeyDown(var Key: word; Shift: TShiftState);
var
  Step: double;
  KeyTool: TCanvasTool;
begin
  inherited KeyDown(Key, Shift);
  // The tool keys come from the shortcuts table. None of the keys that change
  // the tool or the pattern act mid-gesture: a drag holds an open change.
  if FInput.TakesKeys then
    for KeyTool := Low(TCanvasTool) to High(TCanvasTool) do
      if (Key <> 0) and (FToolKeys[KeyTool] = ShortCut(Key, Shift)) then
      begin
        SetTool(KeyTool);
        Key := 0;
        Exit;
      end;
  if ssShift in Shift then
    Step := NUDGE_STEP_LARGE
  else
    Step := NUDGE_STEP;
  case Key of
    VK_SPACE:
      FInput.SpaceDown := True;
    VK_ESCAPE:
      if FInput.Mode = cmDragging then
        CancelDrag
      else if FInput.Mode = cmBoxing then
      begin
        FInput.Mode := cmIdle;
        Invalidate;
      end
      else if FPicking then
      begin
        EndPicking;
        ShowMessageText('');
      end
      // First what the tool is part way through, then the tool, then the selection
      else if not ActiveTool.Cancel then
      begin
        if FTool <> ctSelect then
          SetTool(ctSelect)
        // Last, with nothing selected, it leaves an isolated piece
        else if (Length(FSelection) = 0) and Assigned(FDocument) and Assigned(FDocument.Pattern.IsolatedPiece) then
        begin
          FDocument.Pattern.View.Isolated := '';
          FDocument.ViewChanged;
          Invalidate;
        end
        else
          SelectNone;
      end;
    VK_DELETE, VK_BACK:
    begin
      // Shift+Delete means Cut elsewhere; deleting would lose what was meant to be kept
      if not IsPlainKey(Shift) then
        Exit;
      if FInput.TakesKeys then
        DeleteSelection;
    end;
    VK_TAB, VK_RETURN:
    begin
      if not ActiveTool.HandlesKey(Key) then
        Exit;
      if FInput.TakesKeys then
        ActiveTool.KeyDown(Key, Shift);
    end;
    VK_N:
    begin
      if not IsPlainKey(Shift) then
        Exit;
      SetLabelsHeld(True);
    end;
    VK_LEFT, VK_RIGHT, VK_UP, VK_DOWN:
      if FInput.TakesKeys then
        case Key of
          VK_LEFT: Nudge(-Step, 0);
          VK_RIGHT: Nudge(Step, 0);
          VK_UP: Nudge(0, -Step);
          VK_DOWN: Nudge(0, Step);
        end;
    else
      Exit;
  end;
  Key := 0;
end;

procedure TPatternCanvas.MouseLeave;
begin
  inherited MouseLeave;
  if Assigned(FOnCursorLeave) then
    FOnCursorLeave(Self);
  // Both, so the snap goes whichever was shown
  if ActiveTool.Leave or FTipSnapShown then
  begin
    FTipSnapShown := False;
    Invalidate;
  end;
end;

// The key-up goes elsewhere once focus has moved
procedure TPatternCanvas.DoExit;
begin
  inherited DoExit;
  SetLabelsHeld(False);
  FInput.LoseFocus;
end;

procedure TPatternCanvas.KeyUp(var Key: word; Shift: TShiftState);
begin
  inherited KeyUp(Key, Shift);
  if Key = VK_SPACE then
    FInput.SpaceDown := False
  else if Key = VK_N then
    SetLabelsHeld(False);
end;

procedure TPatternCanvas.SetHorzBar(Value: TScrollBar);
begin
  FHorzBar := Value;
  FHorzBar.Kind := sbHorizontal;
  FHorzBar.OnScroll := @BarScroll;
  FHorzBar.SmallChange := WHEEL_PAN_PIXELS;
  FHorzBar.TabStop := False;
end;

procedure TPatternCanvas.SetVertBar(Value: TScrollBar);
begin
  FVertBar := Value;
  FVertBar.Kind := sbVertical;
  FVertBar.OnScroll := @BarScroll;
  FVertBar.SmallChange := WHEEL_PAN_PIXELS;
  FVertBar.TabStop := False;
end;

// The bars are moved by hand only, so the view follows them, and the keys go
// back to the canvas afterwards
procedure TPatternCanvas.BarScroll(Sender: TObject; ScrollCode: TScrollCode; var ScrollPos: integer);
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

procedure TPatternCanvas.ShowOnBar(Bar: TScrollBar; const Axis: TScrollAxis);
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

// The pattern and a margin round it, or just the view when it is empty
procedure TPatternCanvas.UpdateScrollBars;
var
  Bounds: TRect2;
  TopLeft, BottomRight: TVec2;
begin
  if not Assigned(FHorzBar) or not Assigned(FVertBar) or FThumbHeld then
    Exit;
  if Assigned(FDocument) and PatternBounds(FDocument.Pattern, Bounds, not FDocument.Pattern.View.HideAnnotations) then
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

procedure TPatternCanvas.SetOutsideHoverKey(const Value: string);
begin
  if Value = FOutsideHoverKey then
    Exit;
  FOutsideHoverKey := Value;
  Invalidate;
end;

{ Drawing }

// What the painter needs to know of the canvas
function TPatternCanvas.PaintState: TPaintState;
begin
  Result := Default(TPaintState);
  Result.View := FView;
  Result.Selection := FSelection;
  Result.HoverKey := FHoverKey;
  if Result.HoverKey = '' then
    Result.HoverKey := FOutsideHoverKey;
  Result.ShowPieceFills := FShowPieceFills;
  Result.SmallPoints := ShownLabelMode = lmNone;
  if FTipDragging then
  begin
    Result.DraggedTipKey := FPressKey;
    Result.DraggedTip := FTipSnap.Position;
  end;
  Result.TipHandles := FTool = ctSelect;
  ActiveTool.AddToPaintState(Result);
end;

procedure TPatternCanvas.Paint;
var
  Pattern: TPattern;
begin
  Pattern := nil;
  if Assigned(FDocument) then
    Pattern := FDocument.Pattern;
  FPainter.BeginFrame(Pattern, ClientWidth, ClientHeight, PaintState);
  FPainter.DrawGrid(FGridStep, FGridUnit);
  if Assigned(FDocument) then
  begin
    FPainter.DrawPattern;
    FPainter.DrawNotes(NoteValues);
    if FTool = ctSelect then
      FPainter.DrawHandles(FHoverHandleField, FHoverHandleEdge);
    FPainter.DrawLabels(ShownLabelKeys);
    ActiveTool.Paint(FPainter);
    if FTipDragging and FTipSnapShown then
      FPainter.DrawSnap(FTipSnap, spNone, FTipSnap.Position);
    if FInput.Mode = cmBoxing then
      FPainter.DrawBox(FPressPos, FLastPos);
  end;
  FPainter.EndFrame(Canvas);
  UpdateScrollBars;
  StoreView;
  // Any change at all moves the rulers, so this is not a tolerance compare
  if Assigned(FOnViewChange) and ((FView.Scale <> FReportedView.Scale) or (FView.OriginX <> FReportedView.OriginX) or
    (FView.OriginY <> FReportedView.OriginY)) then
  begin
    FReportedView := FView;
    FOnViewChange(Self);
  end;
end;

end.
