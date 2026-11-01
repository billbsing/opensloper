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
  Classes, SysUtils, Controls, StdCtrls, Graphics, LCLType, LMessages, BGRABitmap, BGRABitmapTypes, Sloper.Core.Geometry,
  Sloper.Core.Draft, Sloper.Core.Drag, Sloper.Core.Piece, Sloper.Core.Seam, Sloper.Core.Drafts, Sloper.Core.Pattern, Sloper.Core.Transform, Sloper.Core.Settings,
  Sloper.Document.PatternDocument, Sloper.UI.View, Sloper.UI.Snap;

type
  // cmRefused: a drag was refused; the reason stays up until the button is released
  TCanvasMode = (cmIdle, cmPressed, cmPanning, cmDragging, cmRefused);
  // ctSelect selects and drags; ctPoint, ctLine and ctCurve add objects where
  // the snap points; ctPiece makes a piece of the region clicked; ctNotch adds
  // or removes a notch on a piece's seam line; ctSeam picks the edges of the
  // two sides of a seam
  TCanvasTool = (ctSelect, ctPoint, ctLine, ctCurve, ctPiece, ctNotch, ctSeam);
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
    // The press landed on a curve's handle, or the handle is being dragged
    FPressHandle, FDraggingHandle: boolean;
    FHandle: TCurveHandle;
    // The field that identifies the handle under the cursor, and its curve
    FHoverHandleField, FHoverHandleEdge: string;
    FSpaceDown: boolean;
    FTool: TCanvasTool;
    // Where a click would go, while a drawing tool is in use
    FSnap: TSnap;
    FSnapShown: boolean;
    // The first click of a line or curve
    FStartSnap: TSnap;
    FHasStart: boolean;
    // The seam being picked, and whether clicks go to side B
    FSeamA, FSeamB: TSeamSide;
    FSeamOnB: boolean;
    FLabelMode: TLabelMode;
    FShowPieceFills: boolean;
    // The hold-for-all-labels key is down
    FLabelsHeld: boolean;
    FHorzBar, FVertBar: TScrollBar;
    // A thumb is being dragged, so its bar is left alone until it lets go
    FThumbHeld: boolean;
    // The draft FView belongs to
    FViewDraftKey: string;
    // A transform waiting for its pivot or axis to be clicked
    FPicking: boolean;
    FPickKind: TTransformKind;
    FPickSources: TStringArray;
    FPickFirst: string;
    FOnToolChange: TNotifyEvent;
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
    procedure StoreDraftView;
    function SelectionIsLocked: boolean;
    procedure DropHiddenSelection;
    procedure MoveSelectionBy(Delta: integer);
    procedure PickHere(X, Y: integer);
    procedure EndPicking;
    procedure MakeTransform(const Spec: TTransformSpec);
    procedure ToggleSelected(const Key: string);
    procedure DropMissingSelection;
    procedure StartDrag;
    procedure StartHandleDrag;
    procedure DragTo(X, Y: integer);
    function UpdateHoverHandle(X, Y: integer): boolean;
    procedure CancelDrag;
    procedure Nudge(DX, DY: double);
    procedure SetTool(Value: TCanvasTool);
    procedure UpdateSnap(X, Y: integer);
    procedure ClickTool;
    procedure AddPointHere;
    procedure AddEdgeHere;
    procedure AddPieceHere(X, Y: integer);
    procedure ToggleNotchHere(X, Y: integer);
    function RemoveNotchesAt(const At: TVec2; Radius: double): boolean;
    function AddNotchesAt(const At: TVec2; Radius: double): boolean;
    procedure ToggleSeamEdgeHere(X, Y: integer);
    procedure ShowSeamProgress;
    procedure ChangeSeamSide(ToSideB: boolean);
    procedure MakeSeam;
    function PickingSeam: boolean;
    procedure ClearSeamSides;
    procedure CMWantSpecialKey(var Message: TCMWantSpecialKey); message CM_WANTSPECIALKEY;
    function UsesSnap: boolean;
    procedure CancelStart;
    procedure SetLabelMode(Value: TLabelMode);
    procedure SetShowPieceFills(Value: boolean);
    procedure SetLabelsHeld(Value: boolean);
    function ShownLabelMode: TLabelMode;
    function ToolLabelKeys: TStringArray;
    procedure DrawGrid;
    procedure DrawPiece(Piece: TPieceObject);
    procedure DrawPieceFill(Piece: TPieceObject; const Points: TVec2Array; const Screen: array of TPointF);
    procedure DrawChevron(const Position: TVec2; Angle: double; const AColor: TBGRAPixel);
    procedure DrawChevrons(Piece: TPieceObject);
    procedure DrawSeamSide(const Side: TSeamSide; const AColor: TBGRAPixel);
    procedure DrawSeams;
    procedure DrawPieceMarks(Piece: TPieceObject);
    procedure DrawEdge(Edge: TEdgeObject);
    procedure DrawPoint(Point: TPointObject);
    procedure DrawPattern;
    procedure DrawHandles;
    procedure DrawLabels;
    procedure DrawSnap;
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
    // Switches to another draft, with its own zoom
    procedure ShowDraft(Draft: TPatternDraft);
    // The active draft as it was last seen, or fitted
    procedure RestoreDraftView;
    // Selects these objects, as a click on the canvas would
    procedure SelectObjects(const Keys: TStringArray);
    // Brings the selection into view at the current zoom
    procedure RevealSelection;
    procedure ZoomToSelection;
    // Copies the selection with a transform: Move at once, Rotate and Mirror
    // once a pivot or axis has been clicked
    procedure StartTransform(Kind: TTransformKind);
    // A circle or arc around the selected point, ready for its radius to be typed
    procedure AddRoundEdge(WholeCircle: boolean);
    // A rectangle from the selected point
    procedure AddRectangleHere;
    // A construction edge parallel to the selected edge
    procedure OffsetSelection(Side: TOffsetSide);
    // Rounds the corner between the two selected edges
    procedure RoundSelectedCorner;
    // Adds a marking to the selected piece from the point or edge selected with it
    procedure MarkSelection(Kind: TMarkingKind);
    // Removes the selected piece's markings on the point or edge selected with it
    procedure UnmarkSelection;
    // Moves the selected objects to a layer, as one undo step
    procedure MoveSelectionToLayer(Layer: TPatternLayer);
    // Deletes the selected objects, the dependents first; nothing when any is in use
    procedure DeleteSelection;
    // Splits the selected edge at the selected point; says why not otherwise
    procedure SplitSelection;
    property Document: TPatternDocument read FDocument write SetDocument;
    // Keys of the selected objects
    property Selection: TStringArray read FSelection;
    property OnCursorMove: TCursorMoveEvent read FOnCursorMove write FOnCursorMove;
    // A hint or the reason something could not be done
    property OnMessage: TCanvasMessageEvent read FOnMessage write FOnMessage;
    property OnSelectionChange: TNotifyEvent read FOnSelectionChange write FOnSelectionChange;
    property Tool: TCanvasTool read FTool write SetTool;
    property OnToolChange: TNotifyEvent read FOnToolChange write FOnToolChange;
    property LabelMode: TLabelMode read FLabelMode write SetLabelMode;
    property ShowPieceFills: boolean read FShowPieceFills write SetShowPieceFills;
    // Scroll bars to keep in step with the view
    property HorzBar: TScrollBar read FHorzBar write SetHorzBar;
    property VertBar: TScrollBar read FVertBar write SetVertBar;
  end;

resourcestring
  rsCanvasMovePoint = 'Move point';
  rsCanvasMoveHandle = 'Move curve handle';
  rsCanvasNudge = 'Nudge';
  rsCanvasMoveToLayer = 'Move to layer';
  rsCanvasTransform = 'Add %s';
  rsCanvasPickCentre = 'Select the point for its centre first';
  rsCanvasAddRound = 'Add circle or arc';
  rsCanvasPickCorner = 'Select the point for its corner first';
  rsCanvasAddRectangle = 'Add rectangle';
  rsCanvasPickEdgeToOffset = 'Select the edge to offset first';
  rsCanvasAddOffset = 'Add offset edge';
  rsCanvasPickCornerEdges = 'Select the two straight edges that meet at the corner';
  rsCanvasRoundCorner = 'Round corner';
  rsCanvasPickHole = 'Select the piece and the point for the hole';
  rsCanvasPickMarkingEdge = 'Select the piece and the edge for the marking';
  rsCanvasPickMarkingToRemove = 'Select the piece and the point or edge of the marking to remove';
  rsCanvasAddMarking = 'Add marking';
  rsCanvasRemoveMarking = 'Remove marking';
  rsCanvasPickPivot = 'Rotate: click the point to turn about; Escape cancels';
  rsCanvasPickAxis = 'Mirror: click a straight edge, or the first of two points; Escape cancels';
  rsCanvasPickSecond = 'Mirror: click the second point; Escape cancels';
  rsCanvasPickPoint = 'Click a point';
  rsCanvasPickEdge = 'Click a straight edge or a point';
  rsCanvasNothingSelected = 'Select the points and edges to copy first';
  rsCanvasLocked = 'The layer %s is locked';
  rsCanvasDelete = 'Delete';
  rsCanvasHover = '%s: %s';
  rsCanvasAddPoint = 'Add point';
  rsCanvasAddLine = 'Add line';
  rsCanvasAddCurve = 'Add curve';
  rsCanvasAddPiece = 'Add piece';
  rsCanvasAddNotch = 'Add notch';
  rsCanvasRemoveNotch = 'Remove notch';
  rsCanvasToolSelect = 'Select: click to select, drag a point to move it';
  rsCanvasToolPoint = 'Point: click to add a point where it snaps';
  rsCanvasToolLine = 'Line: click the start, then the end; Escape stops';
  rsCanvasToolCurve = 'Curve: click the start, then the end; Escape stops';
  rsCanvasToolPiece = 'Piece: click inside a closed outline';
  rsCanvasPieceExists = '%s already covers this region';
  rsCanvasToolNotch = 'Notch: click a piece''s edge to add a notch, or a notch to remove it';
  rsCanvasNoSeam = 'There is no piece''s edge here';
  rsCanvasToolSeam = 'Seam: click edges for side A, Tab moves to side B, Enter makes the seam';
  rsCanvasSeamProgress = 'Side %s: A %s mm, B %s mm, difference %s mm. Tab changes side, Enter makes the seam';
  rsCanvasSeamSides = 'Pick edges for both sides first';
  rsCanvasAddSeam = 'Add seam';
  rsCanvasSplit = 'Split edge';

implementation

uses
  Math, Forms, Sloper.Core.Bounds, Sloper.Core.EvalTypes, Sloper.Core.Evaluator, Sloper.Core.Fabrics, Sloper.Core.PieceDetect, Sloper.UI.Scene;

const
  // A new circle or arc, as a starting point for typing the real values
  NewRoundRadius = '50';
  NewArcSweep = '90';
  NewRectangleWidth = '200';
  NewRectangleHeight = '100';
  NewOffsetDistance = '10';
  NewCornerRadius = '10';
  NewHoleDiameter = '4';
  NewStitchSpacing = '4';
  NewStitchSize = '1';
  // How strongly a fabric's colour shows under the lines
  FabricTintAlpha = 60;
  FabricHatchAlpha = 130;
  FabricHatchPixels = 8;
  // Screen pixels
  PointRadius = 3.5;
  SmallPointRadius = 2.5;
  PointHitRadius = 7;
  HandleRadius = 4;
  EdgeHitRadius = 5;
  DragThreshold = 3;
  FitMargin = 40;
  FlattenPixels = 0.25;
  LabelFontHeight = 13;
  WheelPanPixels = 60;
  SnapRadius = 8;
  SnapMarkerSize = 6;
  ChevronSize = 7;
  ChevronSpread = 150;
  SeamLineWidth = 4;
  // A line or curve shorter than this (mm) is ignored
  MinEdgeLength = 0.05;
  // Curve handles start this fraction of the way along the chord
  HandleFraction = 1 / 3;
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

function ScreenPoint(const P: TVec2): TPointF;
begin
  Result := PointF(P.X, P.Y);
end;

{ TPatternCanvas }

constructor TPatternCanvas.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FView := DefaultView;
  FShowPieceFills := True;
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
  begin
    DropMissingSelection;
    // The first click may name objects that undo removed
    FHasStart := False;
    FSnapShown := False;
  end;
  if Changes * [dcView, dcObjectsReplaced] <> [] then
    DropHiddenSelection;
  // Switching tabs, or undo showing what it changed
  if FDocument.Pattern.ActiveDraft.Key <> FViewDraftKey then
    RestoreDraftView;
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
  Point: TPointObject;
  Edge: TEdgeObject;
  Piece: TPieceObject;
begin
  Result := '';
  if FDocument = nil then
    Exit;
  Point := PointAt(FDocument.Pattern, ModelAt(X, Y), FView.PixelsToMM(PointHitRadius));
  if Point <> nil then
    Exit(Point.Key);
  Edge := EdgeAt(FDocument.Pattern, ModelAt(X, Y), FView.PixelsToMM(EdgeHitRadius));
  if Edge <> nil then
    Exit(Edge.Key);
  Piece := PieceAt(FDocument.Pattern, ModelAt(X, Y));
  if Piece <> nil then
    Result := Piece.Key;
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

// Picking something makes its layer the active one, so that what is drawn
// next goes beside it
procedure TPatternCanvas.SetSelection(const Keys: TStringArray);
var
  Node: TEvalNode;
begin
  FSelection := Keys;
  if (Keys <> nil) and (FDocument <> nil) then
  begin
    Node := FDocument.Pattern.FindNode(Keys[High(Keys)]);
    if ((Node is TDraftObject) or (Node is TRepeatPoint)) and (FDocument.Pattern.LayerOf(Node) <> FDocument.Pattern.ActiveLayer) and
      FDocument.Pattern.InActiveDraft(Node) then
    begin
      FDocument.Pattern.SelectLayer(FDocument.Pattern.LayerOf(Node));
      FDocument.ViewChanged;
    end;
  end;
  Invalidate;
  if Assigned(FOnSelectionChange) then
    FOnSelectionChange(Self);
end;

// The list shows every draft, so a row can be on another one
procedure TPatternCanvas.SelectObjects(const Keys: TStringArray);
var
  Node: TEvalNode;
begin
  if (Keys <> nil) and (FDocument <> nil) then
  begin
    Node := FDocument.Pattern.FindNode(Keys[0]);
    if ((Node is TDraftObject) or (Node is TRepeatPoint)) and not FDocument.Pattern.InActiveDraft(Node) then
      ShowDraft(FDocument.Pattern.DraftOf(Node));
  end;
  SetSelection(Keys);
end;

procedure TPatternCanvas.ShowDraft(Draft: TPatternDraft);
begin
  if (FDocument = nil) or (FDocument.Pattern.ActiveDraft = Draft) then
    Exit;
  FDocument.Pattern.ActiveDraft := Draft;
  SelectNone;
  FHasStart := False;
  FSnapShown := False;
  FHoverKey := '';
  FDocument.ViewChanged;
end;

procedure TPatternCanvas.RestoreDraftView;
var
  Draft: TPatternDraft;
begin
  if FDocument = nil then
    Exit;
  Draft := FDocument.Pattern.ActiveDraft;
  FViewDraftKey := Draft.Key;
  if Draft.HasView then
  begin
    FView.Scale := Draft.Zoom;
    FView.CentreOn(Vec2(Draft.CentreX, Draft.CentreY), ClientWidth, ClientHeight);
    Invalidate;
  end
  else
    ZoomToFit;
end;

// Kept on the draft, which is saved with the file and survives undo
procedure TPatternCanvas.StoreDraftView;
var
  Draft: TPatternDraft;
  Centre: TVec2;
begin
  if FDocument = nil then
    Exit;
  Draft := FDocument.Pattern.ActiveDraft;
  if Draft.Key <> FViewDraftKey then
    Exit;
  Centre := FView.ToModel(Vec2(ClientWidth / 2, ClientHeight / 2));
  Draft.HasView := True;
  Draft.Zoom := FView.Scale;
  Draft.CentreX := Centre.X;
  Draft.CentreY := Centre.Y;
end;

// True, with a message, when any of the selection is on a locked layer
function TPatternCanvas.SelectionIsLocked: boolean;
var
  Key: string;
  Node: TEvalNode;
begin
  Result := False;
  for Key in FSelection do
  begin
    Node := FDocument.Pattern.FindNode(Key);
    if ((Node is TDraftObject) or (Node is TRepeatPoint)) and FDocument.Pattern.LayerOf(Node).Locked then
    begin
      ShowMessageText(Format(rsCanvasLocked, [FDocument.Pattern.LayerOf(Node).Name]));
      Exit(True);
    end;
  end;
end;

// What no longer shows cannot stay selected
procedure TPatternCanvas.DropHiddenSelection;
var
  Kept: TStringArray;
  Key: string;
  Node: TEvalNode;
begin
  Kept := nil;
  for Key in FSelection do
  begin
    Node := FDocument.Pattern.FindNode(Key);
    if not ((Node is TDraftObject) or (Node is TRepeatPoint)) or FDocument.Pattern.IsShown(Node) then
      Insert(Key, Kept, Length(Kept));
  end;
  if Length(Kept) <> Length(FSelection) then
    SetSelection(Kept);
  if (FHoverKey <> '') and (FDocument.Pattern.FindNode(FHoverKey) <> nil) and not FDocument.Pattern.IsShown(FDocument.Pattern.FindNode(FHoverKey)) then
    FHoverKey := '';
end;

procedure TPatternCanvas.RevealSelection;
var
  Bounds: TRect2;
begin
  if (FDocument <> nil) and ObjectsBounds(FDocument.Pattern, FSelection, Bounds) then
  begin
    FView.Reveal(Bounds, ClientWidth, ClientHeight, FitMargin);
    Invalidate;
  end;
end;

procedure TPatternCanvas.ZoomToSelection;
var
  Bounds: TRect2;
begin
  if (FDocument <> nil) and ObjectsBounds(FDocument.Pattern, FSelection, Bounds) then
  begin
    FView.Fit(Bounds, ClientWidth, ClientHeight, FitMargin);
    Invalidate;
  end;
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
  FSeamA := ExistingSeamEntries(FDocument.Pattern, FSeamA);
  FSeamB := ExistingSeamEntries(FDocument.Pattern, FSeamB);
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
    FMode := cmRefused;
    Exit;
  end;
  FDragOffset := Point.Position - ModelAt(FPressPos.X, FPressPos.Y);
  FDocument.BeginChange(rsCanvasMovePoint);
  FMode := cmDragging;
end;

procedure TPatternCanvas.StartHandleDrag;
var
  Reason: string;
begin
  if not CanDragHandle(TEdgeObject(FDocument.Pattern.FindNode(FHandle.EdgeKey)), FHandle, Reason) then
  begin
    ShowMessageText(Reason);
    FMode := cmRefused;
    Exit;
  end;
  FDragOffset := FHandle.Position - ModelAt(FPressPos.X, FPressPos.Y);
  FDocument.BeginChange(rsCanvasMoveHandle);
  FDraggingHandle := True;
  FMode := cmDragging;
end;

procedure TPatternCanvas.DragTo(X, Y: integer);
var
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
  if HandleAt(FDocument.Pattern, FSelection, ModelAt(X, Y), FView.PixelsToMM(PointHitRadius), Found) then
  begin
    FieldName := Found.LengthField;
    EdgeKey := Found.EdgeKey;
  end;
  Result := (FieldName <> FHoverHandleField) or (EdgeKey <> FHoverHandleEdge);
  FHoverHandleField := FieldName;
  FHoverHandleEdge := EdgeKey;
end;

procedure TPatternCanvas.Nudge(DX, DY: double);
var
  Selected, Reason, MergeKey: string;
  Node: TEvalNode;
  Moved: boolean;
begin
  if (FDocument = nil) or (FSelection = nil) or SelectionIsLocked then
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
  if (FDocument = nil) or (FSelection = nil) or SelectionIsLocked then
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

procedure TPatternCanvas.SplitSelection;
var
  EdgeKey, PointKey, Reason, FirstKey, SecondKey: string;
  First, Second: TSplitPart;
  Done: boolean;
begin
  if FDocument = nil then
    Exit;
  if not SplitFromSelection(FDocument.Pattern, FSelection, EdgeKey, PointKey, Reason) then
  begin
    ShowMessageText(Reason);
    Exit;
  end;
  FDocument.BeginChange(rsCanvasSplit);
  Done := FDocument.Pattern.SplitEdge(EdgeKey, FDocument.Pattern.UsePoint(PointKey), First, Second);
  if Done then
  begin
    FirstKey := First.Key;
    SecondKey := Second.Key;
  end;
  Reason := FDocument.Pattern.LastError;
  if FDocument.Commit(Done) then
    SetSelection([FirstKey, SecondKey])
  else
    ShowMessageText(Reason);
end;

procedure TPatternCanvas.MoveSelectionToLayer(Layer: TPatternLayer);
var
  Key, Reason, LayerKey: string;
  Node: TEvalNode;
  Done: boolean;
  Found: TPatternDraft;
begin
  if (FDocument = nil) or (FSelection = nil) or SelectionIsLocked then
    Exit;
  FDocument.BeginChange(rsCanvasMoveToLayer);
  // Going onto a first layer gives it a key, so that is read after
  Done := True;
  LayerKey := Layer.Key;
  for Key in FSelection do
  begin
    Node := FDocument.Pattern.FindNode(Key);
    if (Node is TDraftObject) or (Node is TRepeatPoint) then
      Done := FDocument.Pattern.MoveToLayer(Node, Layer) and Done;
  end;
  Reason := FDocument.Pattern.LastError;
  if FDocument.Commit(Done) then
  begin
    LayerKey := Layer.Key;
    FDocument.Pattern.SelectLayer(FDocument.Pattern.FindLayer(LayerKey, Found));
    FDocument.ViewChanged;
  end
  else
    ShowMessageText(Reason);
end;

// The layer above or below the active one, for what is selected
procedure TPatternCanvas.MoveSelectionBy(Delta: integer);
var
  Draft: TPatternDraft;
  Index: integer;
begin
  if FDocument = nil then
    Exit;
  Draft := FDocument.Pattern.ActiveDraft;
  Index := Draft.IndexOfLayer(Draft.ActiveLayer) + Delta;
  if (Index >= 0) and (Index < Draft.Layers.Count) then
    MoveSelectionToLayer(Draft.Layers[Index]);
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

procedure TPatternCanvas.AddRoundEdge(WholeCircle: boolean);
var
  Node: TEvalNode;
  Added: TEdgeObject;
  Key, Reason: string;
begin
  if FDocument = nil then
    Exit;
  Node := nil;
  if Length(FSelection) = 1 then
    Node := FDocument.Pattern.FindNode(FSelection[0]);
  if not (Node is TPointObject) then
  begin
    ShowMessageText(rsCanvasPickCentre);
    Exit;
  end;
  FDocument.BeginChange(rsCanvasAddRound);
  if WholeCircle then
    Added := FDocument.Pattern.AddCircle(FDocument.Pattern.UsePoint(Node.Key), NewRoundRadius, erOutline)
  else
    Added := FDocument.Pattern.AddArc(FDocument.Pattern.UsePoint(Node.Key), NewRoundRadius, '0', NewArcSweep, erOutline);
  Key := '';
  if Added <> nil then
    Key := Added.Key;
  Reason := FDocument.Pattern.LastError;
  if FDocument.Commit(Added <> nil) then
    SetSelection([Key])
  else
    ShowMessageText(Reason);
  Invalidate;
end;

procedure TPatternCanvas.AddRectangleHere;
var
  Node: TEvalNode;
  Edges: TRectangleEdges;
  Key, Reason: string;
  Done: boolean;
begin
  if FDocument = nil then
    Exit;
  Node := nil;
  if Length(FSelection) = 1 then
    Node := FDocument.Pattern.FindNode(FSelection[0]);
  if not (Node is TPointObject) then
  begin
    ShowMessageText(rsCanvasPickCorner);
    Exit;
  end;
  FDocument.BeginChange(rsCanvasAddRectangle);
  Done := FDocument.Pattern.AddRectangle(FDocument.Pattern.UsePoint(Node.Key), NewRectangleWidth, NewRectangleHeight, erOutline, Edges);
  Key := '';
  if Done then
    Key := Edges[0].EndKey;
  Reason := FDocument.Pattern.LastError;
  if FDocument.Commit(Done) then
    SetSelection([Key])
  else
    ShowMessageText(Reason);
  Invalidate;
end;

procedure TPatternCanvas.OffsetSelection(Side: TOffsetSide);
var
  Node: TEvalNode;
  Added: TOffsetEdge;
  Key, Reason: string;
begin
  if FDocument = nil then
    Exit;
  Node := nil;
  if Length(FSelection) = 1 then
    Node := FDocument.Pattern.FindNode(FSelection[0]);
  if not (Node is TEdgeObject) then
  begin
    ShowMessageText(rsCanvasPickEdgeToOffset);
    Exit;
  end;
  FDocument.BeginChange(rsCanvasAddOffset);
  Added := FDocument.Pattern.AddOffsetEdge(Node.Key, NewOffsetDistance, Side, erConstruction);
  Key := '';
  if Added <> nil then
    Key := Added.Key;
  Reason := FDocument.Pattern.LastError;
  if FDocument.Commit(Added <> nil) then
    SetSelection([Key])
  else
    ShowMessageText(Reason);
  Invalidate;
end;

procedure TPatternCanvas.RoundSelectedCorner;
var
  Added: TCornerArc;
  Key, Reason: string;
begin
  if FDocument = nil then
    Exit;
  if (Length(FSelection) <> 2) or not (FDocument.Pattern.FindNode(FSelection[0]) is TEdgeObject) or not
    (FDocument.Pattern.FindNode(FSelection[1]) is TEdgeObject) then
  begin
    ShowMessageText(rsCanvasPickCornerEdges);
    Exit;
  end;
  FDocument.BeginChange(rsCanvasRoundCorner);
  Added := FDocument.Pattern.AddRoundCorner(FSelection[0], FSelection[1], NewCornerRadius);
  Key := '';
  if Added <> nil then
    Key := Added.Key;
  Reason := FDocument.Pattern.LastError;
  if FDocument.Commit(Added <> nil) then
    SetSelection([Key])
  else
    ShowMessageText(Reason);
  Invalidate;
end;

procedure TPatternCanvas.MarkSelection(Kind: TMarkingKind);
var
  Key, Reason, Target: string;
  Node: TEvalNode;
  Piece: TPieceObject;
  Done: boolean;
begin
  if FDocument = nil then
    Exit;
  Piece := nil;
  Target := '';
  for Key in FSelection do
  begin
    Node := FDocument.Pattern.FindNode(Key);
    if Node is TPieceObject then
      Piece := TPieceObject(Node)
    else if ((Kind = mkHole) and (Node is TPointObject)) or ((Kind <> mkHole) and (Node is TEdgeObject)) then
      Target := Key;
  end;
  if (Piece = nil) or (Target = '') or (Length(FSelection) <> 2) then
  begin
    if Kind = mkHole then
      ShowMessageText(rsCanvasPickHole)
    else
      ShowMessageText(rsCanvasPickMarkingEdge);
    Exit;
  end;
  FDocument.BeginChange(rsCanvasAddMarking);
  case Kind of
    mkHole: Done := FDocument.Pattern.AddHoleMarking(Piece, FDocument.Pattern.UsePoint(Target), NewHoleDiameter);
    mkStitchHoles: Done := FDocument.Pattern.AddStitchMarking(Piece, Target, NewStitchSpacing, NewStitchSize);
    else
      Done := FDocument.Pattern.AddLineMarking(Piece, Kind, Target);
  end;
  Reason := FDocument.Pattern.LastError;
  if not FDocument.Commit(Done) then
    ShowMessageText(Reason);
  Invalidate;
end;

procedure TPatternCanvas.UnmarkSelection;
var
  Key, Target: string;
  Node: TEvalNode;
  Piece: TPieceObject;
  Index: integer;
  Done: boolean;
begin
  if FDocument = nil then
    Exit;
  Piece := nil;
  Target := '';
  for Key in FSelection do
  begin
    Node := FDocument.Pattern.FindNode(Key);
    if Node is TPieceObject then
      Piece := TPieceObject(Node)
    else
      Target := Key;
  end;
  if (Piece = nil) or (Target = '') then
  begin
    ShowMessageText(rsCanvasPickMarkingToRemove);
    Exit;
  end;
  FDocument.BeginChange(rsCanvasRemoveMarking);
  Done := False;
  for Index := High(Piece.Markings) downto 0 do
    if (Piece.Markings[Index].PointKey = Target) or (Piece.Markings[Index].EdgeKey = Target) then
      Done := FDocument.Pattern.RemoveMarking(Piece, Index) or Done;
  if not FDocument.Commit(Done) then
    ShowMessageText(rsCanvasPickMarkingToRemove);
  Invalidate;
end;

procedure TPatternCanvas.StartTransform(Kind: TTransformKind);
var
  Spec: TTransformSpec;
begin
  if FDocument = nil then
    Exit;
  if FSelection = nil then
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
var
  Transform: TTransformObject;
  Key, Reason: string;
begin
  EndPicking;
  FDocument.BeginChange(Format(rsCanvasTransform, [Spec.Name]));
  Transform := FDocument.Pattern.AddTransform(Spec);
  Key := '';
  if Transform <> nil then
    Key := Transform.Key;
  Reason := FDocument.Pattern.LastError;
  if FDocument.Commit(Transform <> nil) then
    SetSelection([Key])
  else
    ShowMessageText(Reason);
end;

procedure TPatternCanvas.PickHere(X, Y: integer);
var
  At: TVec2;
  Point: TPointObject;
  Edge: TEdgeObject;
  Spec: TTransformSpec;
begin
  At := ModelAt(X, Y);
  Point := PointAt(FDocument.Pattern, At, FView.PixelsToMM(PointHitRadius));
  Spec := Default(TTransformSpec);
  Spec.Kind := FPickKind;
  Spec.Sources := FPickSources;
  if FPickKind = tkRotate then
  begin
    if Point = nil then
    begin
      ShowMessageText(rsCanvasPickPoint);
      Exit;
    end;
    Spec.Pivot := Point.Key;
    Spec.Angle := '0';
    MakeTransform(Spec);
  end
  else if Point <> nil then
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
    Edge := EdgeAt(FDocument.Pattern, At, FView.PixelsToMM(EdgeHitRadius));
    if Edge = nil then
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
  ClearSeamSides;
  FHasStart := False;
  FSnapShown := False;
  if FMode = cmDragging then
    CancelDrag;
  FTool := Value;
  if FTool <> ctSelect then
    FHoverKey := '';
  if FTool = ctSelect then
    Cursor := crDefault
  else
    Cursor := crCross;
  case FTool of
    ctSelect: ShowMessageText(rsCanvasToolSelect);
    ctPoint: ShowMessageText(rsCanvasToolPoint);
    ctLine: ShowMessageText(rsCanvasToolLine);
    ctCurve: ShowMessageText(rsCanvasToolCurve);
    ctPiece: ShowMessageText(rsCanvasToolPiece);
    ctNotch: ShowMessageText(rsCanvasToolNotch);
    ctSeam: ShowMessageText(rsCanvasToolSeam);
  end;
  Invalidate;
  if Assigned(FOnToolChange) then
    FOnToolChange(Self);
end;

function TPatternCanvas.UsesSnap: boolean;
begin
  Result := FTool in [ctPoint, ctLine, ctCurve];
end;

procedure TPatternCanvas.UpdateSnap(X, Y: integer);
var
  AnchorKey: string;
begin
  AnchorKey := '';
  // A line lines up with its start first, once that start is a point
  if FHasStart and (FStartSnap.Kind = snPoint) then
    AnchorKey := FStartSnap.PointKey;
  FSnap := FindSnap(FDocument.Pattern, ModelAt(X, Y), FView.PixelsToMM(SnapRadius), AnchorKey);
  FSnapShown := True;
  ShowMessageText(SnapDescription(FDocument.Pattern, FSnap));
  Invalidate;
end;

procedure TPatternCanvas.CancelStart;
begin
  FHasStart := False;
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

// What a drawing tool is working with: the start of a line and the snap
function TPatternCanvas.ToolLabelKeys: TStringArray;
begin
  Result := nil;
  if FHasStart then
    Result := SnapObjectKeys(FStartSnap);
  if FSnapShown and (FTool <> ctSelect) then
    Result := Concat(Result, SnapObjectKeys(FSnap));
end;

procedure TPatternCanvas.AddPointHere;
var
  Key, Reason: string;
begin
  if FSnap.Kind = snPoint then
  begin
    SetSelection([FSnap.PointKey]);
    Exit;
  end;
  FDocument.BeginChange(rsCanvasAddPoint);
  Key := PointFromSnap(FDocument.Pattern, FSnap);
  Reason := FDocument.Pattern.LastError;
  if FDocument.Commit(Key <> '') then
    SetSelection([Key])
  else
    ShowMessageText(Reason);
end;

// The second click of a line or curve: both ends and the edge are one change
procedure TPatternCanvas.AddEdgeHere;
var
  StartKey, EndKey, Reason, Description: string;
  StartPos, EndPos: TVec2;
  Chord: double;
  Edge: TEdgeObject;
begin
  StartPos := FStartSnap.Position;
  EndPos := FSnap.Position;
  Chord := Distance(StartPos, EndPos);
  if Chord < MinEdgeLength then
    Exit;
  if FTool = ctLine then
    Description := rsCanvasAddLine
  else
    Description := rsCanvasAddCurve;
  FDocument.BeginChange(Description);
  Edge := nil;
  StartKey := PointFromSnap(FDocument.Pattern, FStartSnap);
  EndKey := '';
  if StartKey <> '' then
    EndKey := PointFromSnap(FDocument.Pattern, FSnap);
  if (EndKey <> '') and (EndKey <> StartKey) then
    if FTool = ctLine then
      Edge := FDocument.Pattern.AddLine(StartKey, EndKey, erOutline)
    else
      Edge := FDocument.Pattern.AddCurve(StartKey, EndKey, RoundedText(AngleBetween(StartPos, EndPos), DragAngleDecimals),
        RoundedText(Chord * HandleFraction, DragLengthDecimals), RoundedText(AngleBetween(EndPos, StartPos), DragAngleDecimals),
        RoundedText(Chord * HandleFraction, DragLengthDecimals), erOutline);
  Reason := FDocument.Pattern.LastError;
  if not FDocument.Commit(Edge <> nil) then
  begin
    ShowMessageText(Reason);
    FHasStart := False;
    Exit;
  end;
  SetSelection([Edge.Key]);
  // Carry on from the end, as a chain
  FStartSnap := Default(TSnap);
  FStartSnap.Kind := snPoint;
  FStartSnap.PointKey := EndKey;
  FStartSnap.Position := TPointObject(FDocument.Pattern.FindNode(EndKey)).Position;
  FHasStart := True;
end;

// One click makes one piece, with the default allowance to edit in the
// properties; a region that already has a piece selects that piece
procedure TPatternCanvas.AddPieceHere(X, Y: integer);
var
  Path: TPiecePath;
  Reason, Key: string;
  Existing, Piece: TPieceObject;
begin
  if not DetectPiecePath(FDocument.Pattern, ModelAt(X, Y), Path, Reason) then
  begin
    ShowMessageText(Reason);
    Exit;
  end;
  Existing := PieceOnPath(FDocument.Pattern, Path);
  if Existing <> nil then
  begin
    ShowMessageText(Format(rsCanvasPieceExists, [Existing.DisplayName]));
    SetSelection([Existing.Key]);
    Exit;
  end;
  FDocument.BeginChange(rsCanvasAddPiece);
  Piece := FDocument.Pattern.AddPiece('', Path, DefaultPieceAllowance);
  Key := '';
  if Piece <> nil then
    Key := Piece.Key;
  Reason := FDocument.Pattern.LastError;
  if FDocument.Commit(Piece <> nil) then
    SetSelection([Key])
  else
    ShowMessageText(Reason);
end;

// Every notch here goes, since a notch often sits on two pieces sewn together
function TPatternCanvas.RemoveNotchesAt(const At: TVec2; Radius: double): boolean;
var
  Index, Notch: integer;
  Piece: TPieceObject;
begin
  Result := False;
  for Index := 0 to FDocument.Pattern.ObjectCount - 1 do
    if (FDocument.Pattern.Objects[Index] is TPieceObject) and FDocument.Pattern.IsPickable(FDocument.Pattern.Objects[Index]) then
    begin
      Piece := TPieceObject(FDocument.Pattern.Objects[Index]);
      for Notch := High(Piece.NotchMarks) downto 0 do
        if Distance(Piece.NotchMarks[Notch].Seam, At) <= Radius then
          Result := FDocument.Pattern.RemoveNotch(Piece, Notch) or Result;
    end;
end;

// On every piece that uses the edge, so two sides of a seam get matching notches
function TPatternCanvas.AddNotchesAt(const At: TVec2; Radius: double): boolean;
var
  Index: integer;
  Piece: TPieceObject;
  Target: TNotchTarget;
begin
  Result := False;
  if not NotchTargetAt(FDocument.Pattern, At, Radius, Target) then
    Exit;
  for Index := FDocument.Pattern.ObjectCount - 1 downto 0 do
    if FDocument.Pattern.Objects[Index] is TPieceObject then
    begin
      Piece := TPieceObject(FDocument.Pattern.Objects[Index]);
      if Piece.PathIndexOf(Target.EdgeKey) < 0 then
        Continue;
      if Target.PointKey <> '' then
        Result := FDocument.Pattern.AddPointNotch(Piece, FDocument.Pattern.UsePoint(Target.PointKey)) or Result
      else
        Result := FDocument.Pattern.AddEdgeNotch(Piece, Target.EdgeKey, RoundedText(Target.Position, DragLengthDecimals)) or Result;
    end;
end;

// A click on a notch removes it; one on a piece's edge adds one
procedure TPatternCanvas.ToggleNotchHere(X, Y: integer);
var
  At: TVec2;
  Radius: double;
begin
  At := ModelAt(X, Y);
  Radius := FView.PixelsToMM(SnapRadius);
  FDocument.BeginChange(rsCanvasRemoveNotch);
  if FDocument.Commit(RemoveNotchesAt(At, Radius)) then
    Exit;
  FDocument.BeginChange(rsCanvasAddNotch);
  if not FDocument.Commit(AddNotchesAt(At, Radius)) then
    ShowMessageText(rsCanvasNoSeam);
end;

function TPatternCanvas.PickingSeam: boolean;
begin
  Result := (FSeamA <> nil) or (FSeamB <> nil) or FSeamOnB;
end;

procedure TPatternCanvas.ClearSeamSides;
begin
  FSeamA := nil;
  FSeamB := nil;
  FSeamOnB := False;
end;

procedure TPatternCanvas.ShowSeamProgress;
const
  SideNames: array[boolean] of string = ('A', 'B');
var
  LengthA, LengthB: double;
begin
  LengthA := SeamSideLength(FDocument.Pattern, FSeamA);
  LengthB := SeamSideLength(FDocument.Pattern, FSeamB);
  ShowMessageText(Format(rsCanvasSeamProgress, [SideNames[FSeamOnB], RoundedText(LengthA, 1), RoundedText(LengthB, 1), RoundedText(LengthB - LengthA, 1)]));
end;

procedure TPatternCanvas.ToggleSeamEdgeHere(X, Y: integer);
var
  Entry: TSeamEntry;
  Piece: TPieceObject;
begin
  if not SeamEntryAt(FDocument.Pattern, ModelAt(X, Y), FView.PixelsToMM(SnapRadius), Entry) then
  begin
    ShowMessageText(rsCanvasNoSeam);
    Exit;
  end;
  Piece := TPieceObject(FDocument.Pattern.FindNode(Entry.PieceKey));
  if Piece.FoldEdgeKey = Entry.EdgeKey then
  begin
    ShowMessageText(Format(rsSeamOnFold, [FDocument.Pattern.FindNode(Entry.EdgeKey).DisplayName, Piece.DisplayName]));
    Exit;
  end;
  if FSeamOnB then
    ToggleSeamEntry(FSeamB, Entry)
  else
    ToggleSeamEntry(FSeamA, Entry);
  ShowSeamProgress;
  Invalidate;
end;

procedure TPatternCanvas.ChangeSeamSide(ToSideB: boolean);
begin
  FSeamOnB := ToSideB;
  ShowSeamProgress;
end;

procedure TPatternCanvas.MakeSeam;
var
  Seam: TSeamObject;
  Key, Reason: string;
begin
  if (FSeamA = nil) or (FSeamB = nil) then
  begin
    ShowMessageText(rsCanvasSeamSides);
    Exit;
  end;
  FDocument.BeginChange(rsCanvasAddSeam);
  Seam := FDocument.Pattern.AddSeam('', FSeamA, FSeamB);
  Key := '';
  if Seam <> nil then
    Key := Seam.Key;
  Reason := FDocument.Pattern.LastError;
  if FDocument.Commit(Seam <> nil) then
  begin
    ClearSeamSides;
    SetSelection([Key]);
    ShowMessageText(rsCanvasToolSeam);
  end
  else
    ShowMessageText(Reason);
  Invalidate;
end;

// Tab would otherwise move the focus to the next control
procedure TPatternCanvas.CMWantSpecialKey(var Message: TCMWantSpecialKey);
begin
  if (Message.CharCode = VK_TAB) and (FTool = ctSeam) then
    Message.Result := 1
  else
    inherited;
end;

procedure TPatternCanvas.ClickTool;
begin
  case FTool of
    ctPoint:
      AddPointHere;
    ctLine, ctCurve:
      if not FHasStart then
      begin
        FStartSnap := FSnap;
        FHasStart := True;
      end
      else
        AddEdgeHere;
  end;
  Invalidate;
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
  if FDocument = nil then
    Exit;
  if FPicking then
  begin
    if Button = mbLeft then
      PickHere(X, Y);
    Exit;
  end;
  if FTool = ctPiece then
  begin
    if Button = mbLeft then
      AddPieceHere(X, Y);
    Exit;
  end;
  if FTool = ctNotch then
  begin
    if Button = mbLeft then
      ToggleNotchHere(X, Y);
    Exit;
  end;
  if FTool = ctSeam then
  begin
    if Button = mbLeft then
      ToggleSeamEdgeHere(X, Y);
    Exit;
  end;
  if FTool <> ctSelect then
  begin
    // Right click stops a line or curve
    if Button = mbRight then
      CancelStart
    else if Button = mbLeft then
    begin
      UpdateSnap(X, Y);
      ClickTool;
    end;
    Exit;
  end;
  if Button <> mbLeft then
    Exit;
  // A handle lies over whatever else is there
  FPressHandle := HandleAt(FDocument.Pattern, FSelection, ModelAt(X, Y), FView.PixelsToMM(PointHitRadius), FHandle);
  if FPressHandle then
    FPressKey := FHandle.EdgeKey
  else
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
      if Max(Abs(X - FPressPos.X), Abs(Y - FPressPos.Y)) >= DragThreshold then
        if FPressHandle then
        begin
          StartHandleDrag;
          if FMode = cmDragging then
            DragTo(X, Y);
        end
        else if (FPressKey <> '') and (FDocument.Pattern.FindNode(FPressKey) is TPointObject) then
        begin
          StartDrag;
          if FMode = cmDragging then
            DragTo(X, Y);
        end;
    cmDragging:
      DragTo(X, Y);
    cmIdle:
      if (FDocument <> nil) and UsesSnap then
        UpdateSnap(X, Y)
      else if (FDocument <> nil) and (FTool = ctSelect) then
      begin
        if UpdateHoverHandle(X, Y) then
          Invalidate;
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
      FDraggingHandle := False;
      if not IsSelected(FPressKey) then
        SetSelection([FPressKey]);
    end;
    cmPressed:
      // A click on a handle leaves the selection as it is
      if not FPressHandle then
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
      else if FPicking then
      begin
        EndPicking;
        ShowMessageText('');
      end
      else if FHasStart then
        CancelStart
      else if PickingSeam then
      begin
        ClearSeamSides;
        ShowMessageText(rsCanvasToolSeam);
        Invalidate;
      end
      else if FTool <> ctSelect then
        SetTool(ctSelect)
      else
        SelectNone;
    VK_DELETE, VK_BACK:
      DeleteSelection;
    VK_TAB:
    begin
      if FTool <> ctSeam then
        Exit;
      ChangeSeamSide(not (ssShift in Shift));
    end;
    VK_RETURN:
    begin
      if FTool <> ctSeam then
        Exit;
      MakeSeam;
    end;
    VK_S, VK_P, VK_L, VK_C, VK_K, VK_T, VK_E:
    begin
      if Shift <> [] then
        Exit;
      case Key of
        VK_S: SetTool(ctSelect);
        VK_P: SetTool(ctPoint);
        VK_L: SetTool(ctLine);
        VK_C: SetTool(ctCurve);
        VK_K: SetTool(ctPiece);
        VK_T: SetTool(ctNotch);
        VK_E: SetTool(ctSeam);
      end;
    end;
    VK_N:
    begin
      if Shift <> [] then
        Exit;
      SetLabelsHeld(True);
    end;
    VK_PRIOR, VK_NEXT:
    begin
      if not (ssShift in Shift) then
        Exit;
      if Key = VK_PRIOR then
        MoveSelectionBy(1)
      else
        MoveSelectionBy(-1);
    end;
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

procedure TPatternCanvas.MouseLeave;
begin
  inherited MouseLeave;
  if FSnapShown then
  begin
    FSnapShown := False;
    Invalidate;
  end;
end;

// The key-up goes elsewhere once focus has moved
procedure TPatternCanvas.DoExit;
begin
  inherited DoExit;
  SetLabelsHeld(False);
end;

procedure TPatternCanvas.KeyUp(var Key: word; Shift: TShiftState);
begin
  inherited KeyUp(Key, Shift);
  if Key = VK_SPACE then
    FSpaceDown := False
  else if Key = VK_N then
    SetLabelsHeld(False);
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

// Under every line, so seams and labels stay readable. Hatching keeps its
// spacing on screen at any zoom.
procedure TPatternCanvas.DrawPieceFill(Piece: TPieceObject; const Points: TVec2Array; const Screen: array of TPointF);
var
  Look: TPieceLook;
  Stroke: TLine2;
begin
  Look := FDocument.Pattern.PieceLook(Piece);
  if not FShowPieceFills or not Look.Filled then
    Exit;
  if Look.Fill = ffTint then
    FBitmap.FillPolyAntialias(Screen, BGRA(Look.Color.R, Look.Color.G, Look.Color.B, FabricTintAlpha))
  else
    for Stroke in HatchLines(Points, FabricHatchPixels, Look.HatchAngle) do
      FBitmap.DrawLineAntialias(Stroke.P1.X, Stroke.P1.Y, Stroke.P2.X, Stroke.P2.Y, BGRA(Look.Color.R, Look.Color.G, Look.Color.B, FabricHatchAlpha), 1);
end;

// The cutting line, filled with its fabric; the seam line is the edges drawn over it
procedure TPatternCanvas.DrawPiece(Piece: TPieceObject);
var
  Screen: array of TPointF;
  Points: TVec2Array;
  Index: integer;
  LineColor: TBGRAPixel;
  LineWidth: single;
begin
  if Piece.CutLine = nil then
    Exit;
  Screen := nil;
  Points := nil;
  SetLength(Screen, Length(Piece.CutLine));
  SetLength(Points, Length(Piece.CutLine));
  for Index := 0 to High(Screen) do
  begin
    Points[Index] := FView.ToScreen(Piece.CutLine[Index]);
    Screen[Index] := ScreenPoint(Points[Index]);
  end;
  DrawPieceFill(Piece, Points, Screen);
  if Piece.Key = FHoverKey then
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

procedure TPatternCanvas.DrawChevron(const Position: TVec2; Angle: double; const AColor: TBGRAPixel);
var
  Tip, WingA, WingB: TVec2;
  Size: double;
begin
  Size := FView.PixelsToMM(ChevronSize);
  Tip := FView.ToScreen(Position);
  WingA := FView.ToScreen(PolarPoint(Position, Size, Angle + ChevronSpread));
  WingB := FView.ToScreen(PolarPoint(Position, Size, Angle - ChevronSpread));
  FBitmap.DrawPolyLineAntialias([PointF(WingA.X, WingA.Y), PointF(Tip.X, Tip.Y), PointF(WingB.X, WingB.Y)], AColor, 2);
end;

// Shown over the edges while a piece is hovered or selected
procedure TPatternCanvas.DrawChevrons(Piece: TPieceObject);
var
  Item: TPieceChevron;
begin
  for Item in PieceChevrons(FDocument.Pattern, Piece) do
    DrawChevron(Item.Position, Item.Angle, SelectedInk);
end;

procedure TPatternCanvas.DrawSeamSide(const Side: TSeamSide; const AColor: TBGRAPixel);
var
  Entry: TSeamEntry;
  Model: TVec2Array;
  Screen: array of TPointF;
  Index: integer;
begin
  for Entry in Side do
  begin
    // A side can run onto another draft
    if not FDocument.Pattern.IsShown(FDocument.Pattern.FindNode(Entry.PieceKey)) then
      Continue;
    Model := EdgePolyline(TEdgeObject(FDocument.Pattern.FindNode(Entry.EdgeKey)), FView.PixelsToMM(FlattenPixels));
    Screen := nil;
    SetLength(Screen, Length(Model));
    for Index := 0 to High(Model) do
      Screen[Index] := ScreenPoint(FView.ToScreen(Model[Index]));
    FBitmap.DrawPolyLineAntialias(Screen, AColor, SeamLineWidth);
  end;
end;

// The selected seams, with the way they run, and the one being picked
procedure TPatternCanvas.DrawSeams;
var
  Key: string;
  Node: TEvalNode;
  Item: TPieceChevron;
begin
  for Key in FSelection do
  begin
    Node := FDocument.Pattern.FindNode(Key);
    if not (Node is TSeamObject) then
      Continue;
    DrawSeamSide(TSeamObject(Node).SideA, SeamInkA);
    DrawSeamSide(TSeamObject(Node).SideB, SeamInkB);
    for Item in SeamChevrons(FDocument.Pattern, TSeamObject(Node), False) do
      DrawChevron(Item.Position, Item.Angle, SeamInkA);
    for Item in SeamChevrons(FDocument.Pattern, TSeamObject(Node), True) do
      DrawChevron(Item.Position, Item.Angle, SeamInkB);
  end;
  DrawSeamSide(FSeamA, SeamInkA);
  DrawSeamSide(FSeamB, SeamInkB);
end;

// The grainline and notches, over the edges
procedure TPatternCanvas.DrawPieceMarks(Piece: TPieceObject);
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
    First := FView.ToScreen(Stroke.P1);
    Last := FView.ToScreen(Stroke.P2);
    FBitmap.DrawLineAntialias(First.X, First.Y, Last.X, Last.Y, LineColor, 1.5);
  end;
  for Mark in Piece.NotchMarks do
  begin
    First := FView.ToScreen(Mark.Cut);
    Last := FView.ToScreen(Mark.Tip);
    FBitmap.DrawLineAntialias(First.X, First.Y, Last.X, Last.Y, LineColor, 2);
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
  // Selecting a transform shows its copies
  if IsSelected(Edge.Key) or IsSelected(CopyTransformKey(Edge)) then
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
  if ShownLabelMode = lmNone then
    Radius := SmallPointRadius
  else
    Radius := PointRadius;
  if Point.Key = FHoverKey then
    FBitmap.FillEllipseAntialias(Screen.X, Screen.Y, Radius + 5, Radius + 5, HoverHalo);
  if IsSelected(Point.Key) or IsSelected(CopyTransformKey(Point)) then
  begin
    InkColor := SelectedInk;
    Radius := Radius + 1.5;
  end;
  FBitmap.FillEllipseAntialias(Screen.X, Screen.Y, Radius, Radius, InkColor);
end;

procedure TPatternCanvas.DrawPattern;
var
  Point: TPointObject;
  Shown: TDraftObjectArray;
  DraftObject: TDraftObject;
begin
  // Pieces under edges, edges under points, and each bottom layer first
  Shown := ShownObjects(FDocument.Pattern);
  for DraftObject in Shown do
    if (DraftObject is TPieceObject) and DraftObject.HasResult then
      DrawPiece(TPieceObject(DraftObject));
  for DraftObject in Shown do
    if (DraftObject is TEdgeObject) and DraftObject.HasResult then
      DrawEdge(TEdgeObject(DraftObject));
  for DraftObject in Shown do
  begin
    if not (DraftObject is TPieceObject) or not DraftObject.HasResult then
      Continue;
    DrawPieceMarks(TPieceObject(DraftObject));
    if IsSelected(DraftObject.Key) or (DraftObject.Key = FHoverKey) then
      DrawChevrons(TPieceObject(DraftObject));
  end;
  DrawSeams;
  for Point in ShownPoints(FDocument.Pattern) do
    if Point.HasResult then
      DrawPoint(Point);
end;

// Each selected curve's tangent lines. A handle set by a formula is hollow,
// since it cannot be dragged.
procedure TPatternCanvas.DrawHandles;
var
  Item: TCurveHandle;
  Anchor, Tip: TVec2;
  Radius: single;
  Reason: string;
begin
  if FTool <> ctSelect then
    Exit;
  for Item in SelectionHandles(FDocument.Pattern, FSelection) do
  begin
    Anchor := FView.ToScreen(Item.Anchor);
    Tip := FView.ToScreen(Item.Position);
    FBitmap.DrawLineAntialias(Anchor.X, Anchor.Y, Tip.X, Tip.Y, SelectedInk, 1);
    Radius := HandleRadius;
    if (Item.LengthField = FHoverHandleField) and (Item.EdgeKey = FHoverHandleEdge) then
      Radius := Radius + 1.5;
    if CanDragHandle(TEdgeObject(FDocument.Pattern.FindNode(Item.EdgeKey)), Item, Reason) then
      FBitmap.FillEllipseAntialias(Tip.X, Tip.Y, Radius, Radius, SelectedInk)
    else
      FBitmap.EllipseAntialias(Tip.X, Tip.Y, Radius, Radius, SelectedInk, 1.5, Paper);
  end;
end;

// Over the drawing, so that no edge or point crosses out a label
procedure TPatternCanvas.DrawLabels;
var
  Key: string;
  Node: TEvalNode;
  Model: TVec2Array;
  Screen: TVec2;
  InkColor: TBGRAPixel;
begin
  for Key in LabelKeys(FDocument.Pattern, ShownLabelMode, FSelection, FHoverKey, ToolLabelKeys) do
  begin
    Node := FDocument.Pattern.FindNode(Key);
    if Node is TPointObject then
    begin
      Screen := FView.ToScreen(TPointObject(Node).Position);
      Screen := Vec2(Screen.X + 6, Screen.Y - LabelFontHeight - 2);
    end
    else if Node is TPieceObject then
      Screen := FView.ToScreen(PieceMiddle(TPieceObject(Node)))
    else
    begin
      Model := EdgePolyline(TEdgeObject(Node), FView.PixelsToMM(FlattenPixels));
      if Model = nil then
        Continue;
      Screen := FView.ToScreen(PolylineMiddle(Model));
      Screen := Vec2(Screen.X + 4, Screen.Y + 2);
    end;
    if IsSelected(Key) then
      InkColor := SelectedInk
    else
      InkColor := Faded(StateInk(Node.State, Ink), Node.State);
    if Node is TPieceObject then
      FBitmap.TextOut(Screen.X, Screen.Y, FDocument.Pattern.PieceCaption(TPieceObject(Node)), InkColor)
    else
      FBitmap.TextOut(Screen.X, Screen.Y, Node.DisplayName, InkColor);
  end;
end;

// The snap marker, a guide to the point it lines up with, and the line being drawn
procedure TPatternCanvas.DrawSnap;
var
  Screen, Base, Start: TVec2;
  Node: TEvalNode;
  Size: single;
begin
  if not FSnapShown or (FTool = ctSelect) then
    Exit;
  Screen := FView.ToScreen(FSnap.Position);
  Size := SnapMarkerSize;
  if FHasStart then
  begin
    Start := FView.ToScreen(FStartSnap.Position);
    FBitmap.PenStyle := psDash;
    FBitmap.DrawLineAntialias(Start.X, Start.Y, Screen.X, Screen.Y, SelectedInk, 1.5);
    FBitmap.PenStyle := psSolid;
  end;
  if FSnap.Kind in [snHorizontal, snVertical] then
  begin
    Node := FDocument.Pattern.FindNode(FSnap.PointKey);
    if Node is TPointObject then
    begin
      Base := FView.ToScreen(TPointObject(Node).Position);
      FBitmap.PenStyle := psDot;
      FBitmap.DrawLineAntialias(Base.X, Base.Y, Screen.X, Screen.Y, SnapInk, 1);
      FBitmap.PenStyle := psSolid;
    end;
  end;
  case FSnap.Kind of
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

procedure TPatternCanvas.SetHorzBar(Value: TScrollBar);
begin
  FHorzBar := Value;
  FHorzBar.Kind := sbHorizontal;
  FHorzBar.OnScroll := @BarScroll;
  FHorzBar.SmallChange := WheelPanPixels;
  FHorzBar.TabStop := False;
end;

procedure TPatternCanvas.SetVertBar(Value: TScrollBar);
begin
  FVertBar := Value;
  FVertBar.Kind := sbVertical;
  FVertBar.OnScroll := @BarScroll;
  FVertBar.SmallChange := WheelPanPixels;
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
    SetFocus;
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
  if (FHorzBar = nil) or (FVertBar = nil) or FThumbHeld then
    Exit;
  if (FDocument <> nil) and PatternBounds(FDocument.Pattern, Bounds) then
  begin
    TopLeft := FView.ToScreen(Vec2(Bounds.MinX, Bounds.MaxY));
    BottomRight := FView.ToScreen(Vec2(Bounds.MaxX, Bounds.MinY));
    ShowOnBar(FHorzBar, ScrollAxisFor(TopLeft.X - FitMargin, BottomRight.X + FitMargin, ClientWidth));
    ShowOnBar(FVertBar, ScrollAxisFor(TopLeft.Y - FitMargin, BottomRight.Y + FitMargin, ClientHeight));
  end
  else
  begin
    ShowOnBar(FHorzBar, ScrollAxisFor(0, ClientWidth, ClientWidth));
    ShowOnBar(FVertBar, ScrollAxisFor(0, ClientHeight, ClientHeight));
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
  begin
    DrawPattern;
    DrawHandles;
    DrawLabels;
    DrawSnap;
  end;
  FBitmap.Draw(Canvas, 0, 0, True);
  UpdateScrollBars;
  StoreDraftView;
end;

end.
