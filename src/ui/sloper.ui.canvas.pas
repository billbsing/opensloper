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
  Classes, SysUtils, Controls, StdCtrls, Menus, Graphics, LCLType, LMessages, BGRABitmap, BGRABitmapTypes, Sloper.Core.Geometry,
  Sloper.Core.Draft, Sloper.Core.Drag, Sloper.Core.Piece, Sloper.Core.Seam, Sloper.Core.Pattern, Sloper.Core.Transform, Sloper.Core.Settings,
  Sloper.Core.Measurements, Sloper.Core.Units, Sloper.Core.Note, Sloper.Core.TextFields, Sloper.Document.PatternDocument, Sloper.UI.View, Sloper.UI.Snap,
  Sloper.UI.Scene;

type
  // cmRefused: a drag was refused; the reason stays up until the button is released
  // cmBoxing: dragging a selection box from empty canvas or a piece
  TCanvasMode = (cmIdle, cmPressed, cmPanning, cmDragging, cmRefused, cmBoxing);
  // ctSelect selects and drags; ctPoint, ctLine and ctCurve add objects where
  // the snap points; ctPiece makes a piece of the region clicked; ctNotch adds
  // or removes a notch on a piece's seam line; ctSeam picks the edges of the
  // two sides of a seam; ctText places a note, hung from what it snaps to;
  // ctCallout takes what its tip points at, then where its text goes
  TCanvasTool = (ctSelect, ctPoint, ctLine, ctCurve, ctCircle, ctRectangle, ctPiece, ctNotch, ctSeam, ctText, ctCallout);
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
    // Where the last plain click selected something, for clicking again to
    // pick the next of the lines there
    FLastClickPos: TPoint;
    FHasLastClick: boolean;
    // Edges drawn in the same place as others, worked out for each paint
    FEdgeSlots: TEdgeSlotArray;
    FPickMenu: TPopupMenu;
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
    // Where the cursor was when the snap was found, for the Text tool
    FSnapClick: TVec2;
    // Where the Callout tool's first click was
    FStartClick: TVec2;
    // A press on a selected callout's tip, and the tip being dragged
    FPressTip, FTipDragging: boolean;
    // The first click of a line or curve
    FStartSnap: TSnap;
    FHasStart: boolean;
    // The seam being picked, and whether clicks go to side B
    FSeamA, FSeamB: TSeamSide;
    FSeamOnB: boolean;
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
    function NoteValues: TFieldValues;
    function NotesHere(X, Y: integer): TStringArray;
    procedure AddNoteHere;
    procedure StartCallout;
    procedure AddCalloutHere;
    procedure FinishTipDrag;
    procedure DrawNotes;
    function MarkerKey(const Key: string): string;
    procedure MarkHoles;
    procedure FinishOffset(Added: TOffsetEdge);
    function EdgeShift(const Key: string): TVec2;
    function ClickKey(X, Y: integer; Shift: TShiftState): string;
    procedure ShowPickMenu(X, Y: integer);
    procedure PickMenuClick(Sender: TObject);
    procedure SetDocument(ADocument: TPatternDocument);
    procedure DocumentChanged(Document: TPatternDocument; Changes: TDocumentChanges);
    procedure ShowMessageText(const AText: string);
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
    procedure AddShapeHere;
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
    procedure DrawMarker(DraftObject: TDraftObject);
    procedure DrawPattern;
    procedure DrawHandles;
    procedure DrawLabels;
    procedure DrawSnap;
    procedure DrawBox;
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
    // A circle or arc around the selected point, ready for its radius to be typed
    // An arc about the selected point
    procedure AddArcHere;
    // A rectangle from the selected point
    // A construction edge parallel to the selected edge, or to the run the
    // selected edges make
    procedure OffsetSelection(Side: TOffsetSide);
    // An edge inside or outside the selected piece, along its selected edges
    procedure OffsetSelectionInPiece(Inside: boolean);
    // Changes the selected edges to lines or curves in place, as one undo step
    procedure ConvertSelection(ToCurve: boolean);
    // Merges the selected points into one, as one undo step, and selects it
    procedure MergeSelection;
    // Breaks the selected point into one for each edge meeting there, as one
    // undo step, and selects them
    procedure BreakSelection;
    // Rounds the corner between the two selected edges
    procedure RoundSelectedCorner;
    // mkPoint makes the selected points and repeats holes, which join the
    // pieces they lie in; the others add a marking to the selected piece
    // from the edge (or, for mkLine, the marked point) selected with it
    procedure MarkSelection(Kind: TMarkingKind);
    // Removes the selected piece's markings on the point or edge selected with it
    procedure UnmarkSelection;
    // Deletes the selected objects, the dependents first; nothing when any is in use
    procedure DeleteSelection;
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
    // The grid's spacing in AUnit, from the preferences
    procedure SetGrid(Step: double; AUnit: TMeasureUnit);
    // Scroll bars to keep in step with the view
    property HorzBar: TScrollBar read FHorzBar write SetHorzBar;
    property VertBar: TScrollBar read FVertBar write SetVertBar;
  end;

resourcestring
  rsCanvasMovePoint = 'Move point';
  rsCanvasMoveNote = 'Move note';
  rsCanvasAddNote = 'Add note';
  rsCanvasNewNoteText = 'Text';
  rsCanvasToolText = 'Text: click to place a note; it hangs from the point, edge or piece it snaps to';
  rsCanvasToolCallout = 'Callout: click what it points at, then where its text goes; Escape stops';
  rsCanvasCalloutBox = 'Click where the callout''s text goes';
  rsCanvasAddCallout = 'Add callout';
  rsCanvasMoveTip = 'Move callout tip';
  rsCanvasMoveHandle = 'Move curve handle';
  rsCanvasNudge = 'Nudge';
  rsCanvasTransform = 'Add %s';
  rsCanvasPickCentre = 'Select the point for its centre first';
  rsCanvasAddRound = 'Add circle or arc';
  rsCanvasAddRectangle = 'Add rectangle';
  rsCanvasPickEdgeToOffset = 'Select the edges to offset first';
  rsCanvasPickPieceEdges = 'Select the piece and the edges of it to offset';
  rsCanvasAddOffset = 'Add offset edge';
  rsCanvasPickEdgesToConvert = 'Select the edges to change first';
  rsCanvasConvertToLine = 'Change to line';
  rsCanvasConvertToCurve = 'Change to curve';
  rsCanvasMergePoints = 'Merge points';
  rsCanvasMerged = 'Merged %d points into %s';
  rsCanvasPickPointToBreak = 'Select the point to break first';
  rsCanvasBreakPoint = 'Break point';
  rsCanvasBroken = 'Broke %s into %d points';
  rsCanvasPickCornerEdges = 'Select the two straight edges that meet at the corner';
  rsCanvasRoundCorner = 'Round corner';
  rsCanvasPickHole = 'Select the points to mark as holes';
  rsCanvasPickMarkingEdge = 'Select the piece and the edge for the marking';
  rsCanvasPickLine = 'Select the piece and the marking line or marked point to attach to it';
  rsCanvasPickMarkingToRemove = 'Select the piece and the point or edge of the marking to remove';
  rsCanvasAddMarking = 'Add marking';
  rsCanvasRemoveMarking = 'Remove marking';
  rsCanvasPickPivot = 'Rotate Copy: click the point to turn about; Escape cancels';
  rsCanvasPickAxis = 'Mirror Copy: click a straight edge, or the first of two points; Escape cancels';
  rsCanvasPickSecond = 'Mirror Copy: click the second point; Escape cancels';
  rsCanvasPickPoint = 'Click a point';
  rsCanvasPickEdge = 'Click a straight edge or a point';
  rsCanvasNothingSelected = 'Select the points and edges to copy first';
  rsCanvasDelete = 'Delete';
  rsCanvasHover = '%s: %s';
  rsCanvasCycle = '%s (%d of %d here; click again for the next)';
  rsCanvasPickItem = '%s (%s)';
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
  rsCanvasToolCircle = 'Circle: click the centre, then a point on the rim; Escape stops';
  rsCanvasToolRectangle = 'Rectangle: click one corner, then the opposite one; Escape stops';
  rsCanvasCircleRim = 'Click a point on the rim';
  rsCanvasRadius = 'Radius %s';
  rsCanvasRectangleSize = '%s by %s';
  rsCanvasRectangleCorner = 'Click the opposite corner';
  rsCanvasToolSeam = 'Seam: click edges for side A, Tab moves to side B, Enter makes the seam';
  rsCanvasSeamProgress = 'Side %s: A %s, B %s, difference %s. Tab changes side, Enter makes the seam';
  rsCanvasSeamSides = 'Pick edges for both sides first';
  rsCanvasAddSeam = 'Add seam';
  rsCanvasSplit = 'Split edge';

implementation

uses
  Math, Forms, StrUtils, Sloper.Core.Bounds, Sloper.Core.EvalTypes, Sloper.Core.Evaluator, Sloper.Core.Fabrics, Sloper.Core.PieceDetect,
  Sloper.UI.RulerTicks, Sloper.UI.ObjectList;

const
  // A new arc's sweep, as a starting point for typing the real values; its
  // radius and other starting lengths are per unit (StartingLengths)
  NewArcSweep = '90';
  // How strongly a fabric's colour shows under the lines
  FabricTintAlpha = 60;
  FabricHatchAlpha = 130;
  FabricHatchPixels = 8;
  // Screen pixels
  MarkingLineWidth = 1.5;
  PointRadius = 3.5;
  SmallPointRadius = 2.5;
  PointHitRadius = 7;
  HandleRadius = 4;
  EdgeHitRadius = 5;
  DragThreshold = 3;
  // How far apart lines in the same place are drawn, in pixels
  CoincidentGap = 3;
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
  // A click this many pixels around a note's text picks it
  NoteHitPixels = 2;
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

{ TPatternCanvas }

constructor TPatternCanvas.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FView := DefaultView;
  FShowPieceFills := True;
  FDrawRole := erOutline;
  FGridUnit := muMillimetre;
  FGridStep := DefaultGridSteps[muMillimetre];
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
    // The first click may name objects that undo removed
    FHasStart := False;
    FSnapShown := False;
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
  Point := PointAt(FDocument.Pattern, ModelAt(X, Y), FView.PixelsToMM(PointHitRadius));
  if Assigned(Point) then
    Exit(Point.Key);
  Edge := EdgeAt(FDocument.Pattern, ModelAt(X, Y), FView.PixelsToMM(EdgeHitRadius));
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
  Result := NotesAt(FDocument.Pattern, ModelAt(X, Y), NoteValues, FView.PixelsToMM(NoteHitPixels));
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
    FView.Reveal(Bounds, ClientWidth, ClientHeight, FitMargin);
    Invalidate;
  end;
end;

procedure TPatternCanvas.ZoomToSelection;
var
  Bounds: TRect2;
begin
  if Assigned(FDocument) and ObjectsBounds(FDocument.Pattern, FSelection, Bounds) then
  begin
    FView.Fit(Bounds, ClientWidth, ClientHeight, FitMargin);
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
  if Assigned(FDocument) and PatternBounds(FDocument.Pattern, Bounds, not FDocument.Pattern.View.HideAnnotations) then
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
      FMode := cmRefused;
      Exit;
    end;
    FDragOffset := TNoteObject(Node).Position - ModelAt(FPressPos.X, FPressPos.Y);
    FDocument.BeginChange(rsCanvasMoveNote);
    FMode := cmDragging;
    Exit;
  end;
  Point := TPointObject(Node);
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
    FSnapShown := False;
    Invalidate;
  end
  else if FMode = cmDragging then
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
  Moved, Done: boolean;
begin
  if not Assigned(FDocument) or (Length(FSelection) = 0) then
    Exit;
  FDocument.BeginChange(rsCanvasNudge);
  Moved := False;
  MergeKey := 'nudge';
  for Selected in FSelection do
  begin
    Node := FDocument.Pattern.FindNode(Selected);
    if not (Node is TPointObject) and not (Node is TNoteObject) then
      Continue;
    MergeKey := MergeKey + ':' + Selected;
    if Node is TNoteObject then
      Done := DragNote(FDocument.Pattern, TNoteObject(Node), TNoteObject(Node).Position + Vec2(DX, DY), Reason)
    else
      Done := DragPoint(FDocument.Pattern, TPointObject(Node), TPointObject(Node).Position + Vec2(DX, DY), Reason);
    if not Done then
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
  if not Assigned(FDocument) or (Length(FSelection) = 0) then
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
  if not Assigned(FDocument) then
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

{ Transforms }

procedure TPatternCanvas.EndPicking;
begin
  FPicking := False;
  FPickFirst := '';
  FPickSources := nil;
  if FTool = ctSelect then
    Cursor := crDefault;
end;

// An arc about the selected point; circles have their own tool
procedure TPatternCanvas.AddArcHere;
var
  Node: TEvalNode;
  Added: TEdgeObject;
  Key, Reason: string;
begin
  if not Assigned(FDocument) then
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
  Added := FDocument.Pattern.AddArc(FDocument.Pattern.UsePoint(Node.Key), StartingLengths[slArcRadius, FDocument.Pattern.Units], '0', NewArcSweep, FDrawRole);
  Key := '';
  if Assigned(Added) then
    Key := Added.Key;
  Reason := FDocument.Pattern.LastError;
  if FDocument.Commit(Assigned(Added)) then
    SetSelection([Key])
  else
    ShowMessageText(Reason);
  Invalidate;
end;

// The second click of a circle or rectangle: its first point, made if need
// be, and the shape are one change. The tool stays on for the next.
procedure TPatternCanvas.AddShapeHere;
var
  Circle: TCircleObject;
  Edges: TRectangleEdges;
  Key, Reason: string;
  Done: boolean;
begin
  FHasStart := False;
  Key := '';
  if FTool = ctCircle then
  begin
    FDocument.BeginChange(rsCanvasAddRound);
    Circle := CircleFromSnap(FDocument.Pattern, FStartSnap, FSnap.Position, FDrawRole);
    Done := Assigned(Circle);
    if Done then
      Key := Circle.Key;
  end
  else
  begin
    FDocument.BeginChange(rsCanvasAddRectangle);
    Done := RectangleFromSnap(FDocument.Pattern, FStartSnap, FSnap.Position, FDrawRole, Edges);
  end;
  Reason := FDocument.Pattern.LastError;
  if FDocument.Commit(Done) then
  begin
    if Key <> '' then
      SetSelection([Key])
    else
      SetSelection([Edges[0].Key, Edges[1].Key, Edges[2].Key, Edges[3].Key]);
  end
  else
    ShowMessageText(Reason);
  Invalidate;
end;

// One edge, or a run of them in any order, which follows the first selected
procedure TPatternCanvas.OffsetSelection(Side: TOffsetSide);
var
  Edges: TStringArray;
  Run: TRunEdgeArray;
  Added: TOffsetEdge;
begin
  if not Assigned(FDocument) then
    Exit;
  Edges := EdgeKeys(FDocument.Pattern, FSelection);
  if (Length(Edges) = 0) or (Length(Edges) <> Length(FSelection)) then
  begin
    ShowMessageText(rsCanvasPickEdgeToOffset);
    Exit;
  end;
  FDocument.BeginChange(rsCanvasAddOffset);
  Added := nil;
  if Length(Edges) = 1 then
    Added := FDocument.Pattern.AddOffsetEdge(Edges[0], StartingLengths[slOffsetDistance, FDocument.Pattern.Units], Side, erConstruction)
  else if FDocument.Pattern.ChainRun(Edges, Run) then
    Added := FDocument.Pattern.AddOffsetRun(Run, StartingLengths[slOffsetDistance, FDocument.Pattern.Units], Side, erConstruction);
  FinishOffset(Added);
end;

// Edges of a piece, selected with it, offset inside it (as a stitch line)
// or outside it (as a construction line)
procedure TPatternCanvas.OffsetSelectionInPiece(Inside: boolean);
var
  Key: string;
  Node: TEvalNode;
  Piece: TPieceObject;
  Edges: TStringArray;
  Run: TRunEdgeArray;
  Side: TOffsetSide;
  Role: TEdgeRole;
  Added: TOffsetEdge;
begin
  if not Assigned(FDocument) then
    Exit;
  Piece := nil;
  for Key in FSelection do
  begin
    Node := FDocument.Pattern.FindNode(Key);
    if Node is TPieceObject then
      Piece := TPieceObject(Node);
  end;
  Edges := EdgeKeys(FDocument.Pattern, FSelection);
  if not Assigned(Piece) or (Length(Edges) = 0) or (Length(Edges) + 1 <> Length(FSelection)) then
  begin
    ShowMessageText(rsCanvasPickPieceEdges);
    Exit;
  end;
  Role := erConstruction;
  if Inside then
    Role := erStitch;
  FDocument.BeginChange(rsCanvasAddOffset);
  Added := nil;
  if FDocument.Pattern.PieceRun(Piece, Edges, Inside, Run, Side) then
    Added := FDocument.Pattern.AddOffsetRun(Run, StartingLengths[slOffsetDistance, FDocument.Pattern.Units], Side, Role);
  FinishOffset(Added);
end;

procedure TPatternCanvas.FinishOffset(Added: TOffsetEdge);
var
  Key, Reason: string;
begin
  Key := '';
  if Assigned(Added) then
    Key := Added.Key;
  Reason := FDocument.Pattern.LastError;
  if FDocument.Commit(Assigned(Added)) then
    SetSelection([Key])
  else
    ShowMessageText(Reason);
  Invalidate;
end;

procedure TPatternCanvas.ConvertSelection(ToCurve: boolean);
var
  Key, Reason: string;
  Node: TEvalNode;
  Edges: TStringArray;
  Done: boolean;
begin
  if not Assigned(FDocument) then
    Exit;
  Edges := nil;
  for Key in FSelection do
    if FDocument.Pattern.FindNode(Key) is TEdgeObject then
      Insert(Key, Edges, Length(Edges));
  if Length(Edges) = 0 then
  begin
    ShowMessageText(rsCanvasPickEdgesToConvert);
    Exit;
  end;
  if ToCurve then
    FDocument.BeginChange(rsCanvasConvertToCurve)
  else
    FDocument.BeginChange(rsCanvasConvertToLine);
  Done := True;
  // Each edge keeps its ID, so it is found again after the one before it changed
  for Key in Edges do
  begin
    Node := FDocument.Pattern.FindNode(Key);
    if ToCurve then
      Done := Assigned(FDocument.Pattern.ConvertToCurve(TEdgeObject(Node)))
    else
      Done := Assigned(FDocument.Pattern.ConvertToLine(TEdgeObject(Node)));
    if not Done then
      Break;
  end;
  Reason := FDocument.Pattern.LastError;
  if not FDocument.Commit(Done) then
    ShowMessageText(Reason);
  Invalidate;
end;

procedure TPatternCanvas.MergeSelection;
var
  Kept: TPointObject;
  Key, Reason, KeptName: string;
  Points: TStringArray;
begin
  if not Assigned(FDocument) then
    Exit;
  Points := nil;
  for Key in FSelection do
    if FDocument.Pattern.FindNode(Key) is TPointObject then
      Insert(Key, Points, Length(Points));
  FDocument.BeginChange(rsCanvasMergePoints);
  Kept := FDocument.Pattern.MergePoints(Points);
  Key := '';
  KeptName := '';
  if Assigned(Kept) then
  begin
    Key := Kept.Key;
    KeptName := Kept.Name;
  end;
  Reason := FDocument.Pattern.LastError;
  if FDocument.Commit(Assigned(Kept)) then
  begin
    SetSelection([Key]);
    ShowMessageText(Format(rsCanvasMerged, [Length(Points), KeptName]));
  end
  else
    ShowMessageText(Reason);
  Invalidate;
end;

procedure TPatternCanvas.BreakSelection;
var
  Node: TEvalNode;
  Broken: TPointObjectArray;
  Keys: TStringArray;
  Item: TPointObject;
  Reason, OldName: string;
begin
  if not Assigned(FDocument) then
    Exit;
  Node := nil;
  if Length(FSelection) = 1 then
    Node := FDocument.Pattern.FindNode(FSelection[0]);
  if not (Node is TPointObject) then
  begin
    ShowMessageText(rsCanvasPickPointToBreak);
    Exit;
  end;
  OldName := Node.DisplayName;
  FDocument.BeginChange(rsCanvasBreakPoint);
  Broken := FDocument.Pattern.BreakPoint(TPointObject(Node));
  Keys := nil;
  for Item in Broken do
    Insert(Item.Key, Keys, Length(Keys));
  Reason := FDocument.Pattern.LastError;
  if FDocument.Commit(Length(Broken) > 0) then
  begin
    SetSelection(Keys);
    ShowMessageText(Format(rsCanvasBroken, [OldName, Length(Keys)]));
  end
  else
    ShowMessageText(Reason);
  Invalidate;
end;

procedure TPatternCanvas.RoundSelectedCorner;
var
  Added: TCornerArc;
  Key, Reason: string;
begin
  if not Assigned(FDocument) then
    Exit;
  if (Length(FSelection) <> 2) or not (FDocument.Pattern.FindNode(FSelection[0]) is TEdgeObject) or not
    (FDocument.Pattern.FindNode(FSelection[1]) is TEdgeObject) then
  begin
    ShowMessageText(rsCanvasPickCornerEdges);
    Exit;
  end;
  FDocument.BeginChange(rsCanvasRoundCorner);
  Added := FDocument.Pattern.AddRoundCorner(FSelection[0], FSelection[1], StartingLengths[slCornerRadius, FDocument.Pattern.Units]);
  Key := '';
  if Assigned(Added) then
    Key := Added.Key;
  Reason := FDocument.Pattern.LastError;
  if FDocument.Commit(Assigned(Added)) then
    SetSelection([Key])
  else
    ShowMessageText(Reason);
  Invalidate;
end;

// A repeat's point stands for its repeat, which holds the marker
function TPatternCanvas.MarkerKey(const Key: string): string;
var
  Node: TEvalNode;
begin
  Result := Key;
  Node := FDocument.Pattern.FindNode(Key);
  if Node is TRepeatPoint then
    Result := TRepeatPoint(Node).Source.Key;
end;

// Every selected point or repeat becomes a hole, joining the pieces it lies in
procedure TPatternCanvas.MarkHoles;
var
  Key, Target, Reason: string;
  Node: TEvalNode;
  Targets: TStringArray;
  Done: boolean;
begin
  Targets := nil;
  for Key in FSelection do
  begin
    Node := FDocument.Pattern.FindNode(Key);
    Target := MarkerKey(Key);
    if ((Node is TPointObject) or (Node is TRepeatObject)) and (TDraftObject(FDocument.Pattern.FindNode(Target)).Marker <> pmHole) and
      (IndexStr(Target, Targets) < 0) then
      Insert(Target, Targets, Length(Targets));
  end;
  if Length(Targets) = 0 then
  begin
    ShowMessageText(rsCanvasPickHole);
    Exit;
  end;
  FDocument.BeginChange(rsCanvasAddMarking);
  Done := True;
  for Target in Targets do
    Done := Done and FDocument.Pattern.SetMarker(Target, pmHole);
  Reason := FDocument.Pattern.LastError;
  if not FDocument.Commit(Done) then
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
  if not Assigned(FDocument) then
    Exit;
  if Kind = mkPoint then
  begin
    MarkHoles;
    Exit;
  end;
  Piece := nil;
  Target := '';
  for Key in FSelection do
  begin
    Node := FDocument.Pattern.FindNode(Key);
    if Node is TPieceObject then
      Piece := TPieceObject(Node)
    else if (Node is TEdgeObject) or ((Kind = mkLine) and ((Node is TPointObject) or (Node is TRepeatObject))) then
      Target := MarkerKey(Key);
  end;
  if not Assigned(Piece) or (Target = '') or (Length(FSelection) <> 2) then
  begin
    if Kind = mkLine then
      ShowMessageText(rsCanvasPickLine)
    else
      ShowMessageText(rsCanvasPickMarkingEdge);
    Exit;
  end;
  FDocument.BeginChange(rsCanvasAddMarking);
  if Kind = mkStitchHoles then
    Done := FDocument.Pattern.AddStitchMarking(Piece, Target, StartingLengths[slStitchSpacing, FDocument.Pattern.Units],
      StartingLengths[slStitchSize, FDocument.Pattern.Units])
  else if FDocument.Pattern.FindNode(Target) is TEdgeObject then
    Done := FDocument.Pattern.AddLineMarking(Piece, Target)
  else
    Done := FDocument.Pattern.AddPointMarking(Piece, Target);
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
  if not Assigned(FDocument) then
    Exit;
  Piece := nil;
  Target := '';
  for Key in FSelection do
  begin
    Node := FDocument.Pattern.FindNode(Key);
    if Node is TPieceObject then
      Piece := TPieceObject(Node)
    else
      Target := MarkerKey(Key);
  end;
  if not Assigned(Piece) or (Target = '') then
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
var
  Transform: TTransformObject;
  Key, Reason: string;
begin
  EndPicking;
  FDocument.BeginChange(Format(rsCanvasTransform, [Spec.Name]));
  Transform := FDocument.Pattern.AddTransform(Spec);
  Key := '';
  if Assigned(Transform) then
    Key := Transform.Key;
  Reason := FDocument.Pattern.LastError;
  if FDocument.Commit(Assigned(Transform)) then
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
    Edge := EdgeAt(FDocument.Pattern, At, FView.PixelsToMM(EdgeHitRadius));
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
    ctCircle: ShowMessageText(rsCanvasToolCircle);
    ctRectangle: ShowMessageText(rsCanvasToolRectangle);
    ctText: ShowMessageText(rsCanvasToolText);
    ctCallout: ShowMessageText(rsCanvasToolCallout);
  end;
  Invalidate;
  if Assigned(FOnToolChange) then
    FOnToolChange(Self);
end;

function TPatternCanvas.UsesSnap: boolean;
begin
  Result := FTool in [ctPoint, ctLine, ctCurve, ctCircle, ctRectangle, ctText, ctCallout];
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
  FSnapClick := ModelAt(X, Y);
  FSnapShown := True;
  // The second click of a circle or rectangle makes no point, only its size
  if FHasStart and (FTool = ctCircle) then
    ShowMessageText(Format(rsCanvasRadius, [LengthWithUnit(Distance(FStartSnap.Position, FSnap.Position), FDocument.Pattern.Units)]))
  else if FHasStart and (FTool = ctRectangle) then
    ShowMessageText(Format(rsCanvasRectangleSize, [LengthWithUnit(Abs(FSnap.Position.X - FStartSnap.Position.X), FDocument.Pattern.Units),
      LengthWithUnit(Abs(FSnap.Position.Y - FStartSnap.Position.Y), FDocument.Pattern.Units)]))
  else if FTool = ctText then
    ShowMessageText(NoteSnapDescription(FDocument.Pattern, FSnap, FSnapClick))
  else if (FTool = ctCallout) and FHasStart then
    ShowMessageText(rsCanvasCalloutBox)
  else if (FTool = ctCallout) or FTipDragging then
    ShowMessageText(CalloutSnapDescription(FDocument.Pattern, FSnap, FSnapClick))
  else
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
    Result := LabelKeys(FDocument.Pattern, ShownLabelMode, FSelection, FHoverKey, ToolLabelKeys);
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

// The note is selected, ready for its text to be typed in the properties
procedure TPatternCanvas.AddNoteHere;
var
  Note: TNoteObject;
  Key, Reason: string;
begin
  FDocument.BeginChange(rsCanvasAddNote);
  Note := NoteFromSnap(FDocument.Pattern, FSnap, FSnapClick, rsCanvasNewNoteText);
  Reason := FDocument.Pattern.LastError;
  Key := '';
  if Assigned(Note) then
    Key := Note.Key;
  if not FDocument.Commit(Assigned(Note)) then
  begin
    ShowMessageText(Reason);
    Exit;
  end;
  SetSelection([Key]);
  if Assigned(FOnNoteAdded) then
    FOnNoteAdded(Self);
end;

// The first click says what the tip points at, which cannot be nothing
procedure TPatternCanvas.StartCallout;
var
  Anchor: TNoteAnchor;
  AnchorKey: string;
  Ratio: double;
begin
  NoteAnchorFromSnap(FDocument.Pattern, FSnap, FSnapClick, Anchor, AnchorKey, Ratio);
  if Anchor = naFree then
  begin
    ShowMessageText(rsPatternCalloutFree);
    Exit;
  end;
  FStartSnap := FSnap;
  FStartClick := FSnapClick;
  FHasStart := True;
  ShowMessageText(rsCanvasCalloutBox);
end;

// The second click: the text goes where it was, and the tip where the first snapped
procedure TPatternCanvas.AddCalloutHere;
var
  Note: TNoteObject;
  Key, Reason: string;
begin
  FHasStart := False;
  FDocument.BeginChange(rsCanvasAddCallout);
  Note := CalloutFromSnap(FDocument.Pattern, FStartSnap, FStartClick, FSnapClick, rsCanvasNewNoteText, nlArrow);
  Reason := FDocument.Pattern.LastError;
  Key := '';
  if Assigned(Note) then
    Key := Note.Key;
  if not FDocument.Commit(Assigned(Note)) then
  begin
    ShowMessageText(Reason);
    Exit;
  end;
  ShowMessageText(rsCanvasToolCallout);
  SetSelection([Key]);
  if Assigned(FOnNoteAdded) then
    FOnNoteAdded(Self);
end;

// The dropped tip hangs the callout from what it snaps to; its text stays put
procedure TPatternCanvas.FinishTipDrag;
var
  Node: TEvalNode;
  Reason: string;
  Done: boolean;
begin
  FTipDragging := False;
  FSnapShown := False;
  Node := FDocument.Pattern.FindNode(FPressKey);
  if not (Node is TNoteObject) then
    Exit;
  FDocument.BeginChange(rsCanvasMoveTip);
  Done := ReanchorFromSnap(FDocument.Pattern, TNoteObject(Node), FSnap, FSnapClick);
  Reason := FDocument.Pattern.LastError;
  FDocument.Commit(Done);
  if not Done then
    ShowMessageText(Reason);
  Invalidate;
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
      Edge := FDocument.Pattern.AddLine(StartKey, EndKey, FDrawRole)
    else
      Edge := FDocument.Pattern.AddCurve(StartKey, EndKey, RoundedText(AngleBetween(StartPos, EndPos), DragAngleDecimals),
        RoundLengthFormulaText(Chord * HandleFraction, FDocument.Pattern.Units), RoundedText(AngleBetween(EndPos, StartPos), DragAngleDecimals),
        RoundLengthFormulaText(Chord * HandleFraction, FDocument.Pattern.Units), FDrawRole);
  Reason := FDocument.Pattern.LastError;
  if not FDocument.Commit(Assigned(Edge)) then
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
  if Assigned(Existing) then
  begin
    ShowMessageText(Format(rsCanvasPieceExists, [Existing.DisplayName]));
    SetSelection([Existing.Key]);
    Exit;
  end;
  FDocument.BeginChange(rsCanvasAddPiece);
  Piece := FDocument.Pattern.AddPiece('', Path, DefaultPieceAllowance);
  Key := '';
  if Assigned(Piece) then
    Key := Piece.Key;
  Reason := FDocument.Pattern.LastError;
  if FDocument.Commit(Assigned(Piece)) then
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
    if (FDocument.Pattern.Objects[Index] is TPieceObject) then
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
        Result := FDocument.Pattern.AddEdgeNotch(Piece, Target.EdgeKey, RoundLengthFormulaText(Target.Position, FDocument.Pattern.Units)) or Result;
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
  Result := (Length(FSeamA) > 0) or (Length(FSeamB) > 0) or FSeamOnB;
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
  AUnit: TMeasureUnit;
begin
  LengthA := SeamSideLength(FDocument.Pattern, FSeamA);
  LengthB := SeamSideLength(FDocument.Pattern, FSeamB);
  AUnit := FDocument.Pattern.Units;
  ShowMessageText(Format(rsCanvasSeamProgress, [SideNames[FSeamOnB], LengthWithUnit(LengthA, AUnit), LengthWithUnit(LengthB, AUnit),
    LengthWithUnit(LengthB - LengthA, AUnit)]));
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
  if (Length(FSeamA) = 0) or (Length(FSeamB) = 0) then
  begin
    ShowMessageText(rsCanvasSeamSides);
    Exit;
  end;
  FDocument.BeginChange(rsCanvasAddSeam);
  Seam := FDocument.Pattern.AddSeam('', FSeamA, FSeamB);
  Key := '';
  if Assigned(Seam) then
    Key := Seam.Key;
  Reason := FDocument.Pattern.LastError;
  if FDocument.Commit(Assigned(Seam)) then
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
    ctText:
      AddNoteHere;
    ctCallout:
      if FHasStart then
        AddCalloutHere
      else
        StartCallout;
    ctLine, ctCurve:
      if not FHasStart then
      begin
        FStartSnap := FSnap;
        FHasStart := True;
      end
      else
        AddEdgeHere;
    ctCircle, ctRectangle:
      if not FHasStart then
      begin
        FStartSnap := FSnap;
        FHasStart := True;
        if FTool = ctCircle then
          ShowMessageText(rsCanvasCircleRim)
        else
          ShowMessageText(rsCanvasRectangleCorner);
      end
      else
        AddShapeHere;
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
  if not Assigned(FDocument) then
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
  if Button = mbRight then
  begin
    ShowPickMenu(X, Y);
    Exit;
  end;
  if Button <> mbLeft then
    Exit;
  // A callout's tip or a curve's handle lies over whatever else is there
  FPressKey := CalloutTipAt(FDocument.Pattern, FSelection, ModelAt(X, Y), FView.PixelsToMM(PointHitRadius));
  FPressTip := FPressKey <> '';
  FPressHandle := not FPressTip and HandleAt(FDocument.Pattern, FSelection, ModelAt(X, Y), FView.PixelsToMM(PointHitRadius), FHandle);
  if FPressHandle then
    FPressKey := FHandle.EdgeKey
  else if not FPressTip then
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
        if FPressTip then
        begin
          FTipDragging := True;
          FMode := cmDragging;
          UpdateSnap(X, Y);
        end
        else if FPressHandle then
        begin
          StartHandleDrag;
          if FMode = cmDragging then
            DragTo(X, Y);
        end
        else if (FPressKey <> '') and ((FDocument.Pattern.FindNode(FPressKey) is TPointObject) or (FDocument.Pattern.FindNode(FPressKey) is TNoteObject)) then
        begin
          StartDrag;
          if FMode = cmDragging then
            DragTo(X, Y);
        end
        else
        begin
          FMode := cmBoxing;
          Invalidate;
        end;
    cmDragging:
      if FTipDragging then
        UpdateSnap(X, Y)
      else
        DragTo(X, Y);
    cmBoxing:
      Invalidate;
    cmIdle:
      if Assigned(FDocument) and UsesSnap then
        UpdateSnap(X, Y)
      else if Assigned(FDocument) and (FTool = ctSelect) then
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
  case FMode of
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
      SelectBox(X, Y, ssShift in Shift);
      Invalidate;
    end;
    cmPressed:
      // A click on a handle or a callout's tip leaves the selection as it is
      if not FPressHandle and not FPressTip then
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
  FMode := cmIdle;
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
  Here := Concat(NotesHere(X, Y), ObjectsAt(FDocument.Pattern, ModelAt(X, Y), FView.PixelsToMM(PointHitRadius), FView.PixelsToMM(EdgeHitRadius)));
  Again := FHasLastClick and (Max(Abs(X - FLastClickPos.X), Abs(Y - FLastClickPos.Y)) < DragThreshold) and (Length(FSelection) = 1);
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
  Here := Concat(NotesHere(X, Y), ObjectsAt(FDocument.Pattern, ModelAt(X, Y), FView.PixelsToMM(PointHitRadius), FView.PixelsToMM(EdgeHitRadius)));
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
      else if FMode = cmBoxing then
      begin
        FMode := cmIdle;
        Invalidate;
      end
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
    VK_S, VK_P, VK_L, VK_C, VK_O, VK_R, VK_K, VK_T, VK_E, VK_X, VK_A:
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
        VK_O: SetTool(ctCircle);
        VK_R: SetTool(ctRectangle);
        VK_X: SetTool(ctText);
        VK_A: SetTool(ctCallout);
      end;
    end;
    VK_N:
    begin
      if Shift <> [] then
        Exit;
      SetLabelsHeld(True);
    end;
    VK_LEFT:
      Nudge(-Step, 0);
    VK_RIGHT:
      Nudge(Step, 0);
    VK_UP:
      Nudge(0, -Step);
    VK_DOWN:
      Nudge(0, Step);
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

// Counted in whole steps from the origin, so major lines stay put and long
// grids gather no rounding
procedure TPatternCanvas.DrawGrid;
var
  Spacing: TRulerSpacing;
  StepMm, Screen: double;
  PerMajor, First, Last, Index: int64;
  TopLeft, BottomRight: TVec2;
  LineColor: TBGRAPixel;
begin
  Spacing := GridSpacing(FView.Scale * MillimetresPerUnit[FGridUnit], FGridStep, FGridUnit);
  StepMm := Spacing.Minor * MillimetresPerUnit[FGridUnit];
  PerMajor := Max(1, Round(Spacing.Labelled / Spacing.Minor));
  TopLeft := ModelAt(0, 0);
  BottomRight := ModelAt(ClientWidth, ClientHeight);

  First := Floor64(TopLeft.X / StepMm);
  Last := Ceil64(BottomRight.X / StepMm);
  for Index := First to Last do
  begin
    if Index mod PerMajor = 0 then
      LineColor := GridMajor
    else
      LineColor := GridMinor;
    Screen := FView.ToScreen(Vec2(Index * StepMm, 0)).X;
    FBitmap.DrawVertLine(Round(Screen), 0, ClientHeight, LineColor);
  end;
  First := Floor64(TopLeft.Y / StepMm);
  Last := Ceil64(BottomRight.Y / StepMm);
  for Index := First to Last do
  begin
    if Index mod PerMajor = 0 then
      LineColor := GridMajor
    else
      LineColor := GridMinor;
    Screen := FView.ToScreen(Vec2(0, Index * StepMm)).Y;
    FBitmap.DrawHorizLine(0, Round(Screen), ClientWidth, LineColor);
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
    FBitmap.FillPolyAntialias(Screen, BGRA(Look.Color.Red, Look.Color.Green, Look.Color.Blue, FabricTintAlpha))
  else
    for Stroke in HatchLines(Points, FabricHatchPixels, Look.HatchAngle) do
      FBitmap.DrawLineAntialias(Stroke.P1.X, Stroke.P1.Y, Stroke.P2.X, Stroke.P2.Y, BGRA(Look.Color.Red, Look.Color.Green, Look.Color.Blue, FabricHatchAlpha), 1);
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
  if Length(Piece.CutLine) = 0 then
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

function ScreenDashes(const Dashes: TDashPattern; LineWidth: single): TBGRAPenStyle; forward;

// Screen pixels to move an edge aside by, so lines in the same place show
// that there is more than one; geometry and output never move
function TPatternCanvas.EdgeShift(const Key: string): TVec2;
var
  Slot: TEdgeSlot;
begin
  Result := Vec2(0, 0);
  for Slot in FEdgeSlots do
    if Slot.Key = Key then
      Exit(Slot.Normal * (Slot.Slot * CoincidentGap));
end;

procedure TPatternCanvas.DrawEdge(Edge: TEdgeObject);
var
  Shift: TVec2;
  Model: TVec2Array;
  Screen: array of TPointF;
  Index: integer;
  LineColor: TBGRAPixel;
  LineWidth: single;
begin
  Model := EdgePolyline(Edge, FView.PixelsToMM(FlattenPixels));
  if Length(Model) < 2 then
    Exit;
  Shift := EdgeShift(Edge.Key);
  Screen := nil;
  SetLength(Screen, Length(Model));
  for Index := 0 to High(Model) do
    Screen[Index] := ScreenPoint(FView.ToScreen(Model[Index]) + Shift);

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
  if Edge.Key = FHoverKey then
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
  Key: string;
  Node: TEvalNode;
begin
  // Pieces under edges, edges under points
  Shown := ShownObjects(FDocument.Pattern);
  FEdgeSlots := CoincidentEdges(FDocument.Pattern);
  for DraftObject in Shown do
    if (DraftObject is TPieceObject) and DraftObject.HasResult then
      DrawPiece(TPieceObject(DraftObject));
  for DraftObject in EdgesInDrawOrder(Shown) do
    if DraftObject.HasResult then
      DrawEdge(TEdgeObject(DraftObject));
  // A hidden line shows while it is selected, as from the Objects panel
  for Key in FSelection do
  begin
    Node := FDocument.Pattern.FindNode(Key);
    if (Node is TEdgeObject) and FDocument.Pattern.IsHidden(TEdgeObject(Node)) and Node.HasResult then
      DrawEdge(TEdgeObject(Node));
  end;
  for DraftObject in Shown do
  begin
    if not (DraftObject is TPieceObject) or not DraftObject.HasResult then
      Continue;
    DrawPieceMarks(TPieceObject(DraftObject));
    if IsSelected(DraftObject.Key) or (DraftObject.Key = FHoverKey) then
      DrawChevrons(TPieceObject(DraftObject));
  end;
  DrawSeams;
  // A marker shows at its point whether or not it is on a piece yet
  for DraftObject in Shown do
    if (DraftObject.Marker <> pmPlain) and DraftObject.HasResult then
      DrawMarker(DraftObject);
  for Point in ShownPoints(FDocument.Pattern) do
    if Point.HasResult then
      DrawPoint(Point);
end;

// Over the pattern, at their true size for the zoom. A selected note shows a
// faint line to what it hangs from, and a hovered one a halo.
procedure TPatternCanvas.DrawNotes;
var
  Index, LineIndex: integer;
  Note: TNoteObject;
  Values: TFieldValues;
  Lines: TStringArray;
  Box, Frame: TRect2;
  TopLeft, BottomRight, Anchor, Spot, Tip, Start, First, Last: TVec2;
  InkColor: TBGRAPixel;
  EmPixels, LinePixels, BoxPixels: double;
  Stroke: TLine2;
  Selected: boolean;
begin
  if FDocument.Pattern.View.HideAnnotations then
    Exit;
  Values := NoteValues;
  for Index := 0 to FDocument.Pattern.ObjectCount - 1 do
  begin
    if not (FDocument.Pattern.Objects[Index] is TNoteObject) or not FDocument.Pattern.Objects[Index].HasResult then
      Continue;
    Note := TNoteObject(FDocument.Pattern.Objects[Index]);
    Selected := IsSelected(Note.Key);
    Box := NoteBox(Note, Values);
    Frame := NoteFrame(Note, Values);
    TopLeft := FView.ToScreen(Vec2(Box.MinX, Box.MinY));
    BottomRight := FView.ToScreen(Vec2(Box.MaxX, Box.MaxY));
    if Selected then
      InkColor := SelectedInk
    else
      InkColor := Faded(StateInk(Note.State, Ink), Note.State);
    // A screen-only note is drawn lighter, as it never prints
    if not Note.Print then
      InkColor.alpha := InkColor.alpha div 2;
    // A callout's leader, to where its tip is being dragged while it is
    Tip := Note.AnchorPosition;
    if FTipDragging and (Note.Key = FPressKey) then
      Tip := FSnap.Position;
    if (Note.Leader <> nlNone) and LeaderStart(Frame, Tip, Start) then
    begin
      for Stroke in LeaderStrokes(Start, Tip, Note.Leader) do
      begin
        First := FView.ToScreen(Stroke.P1);
        Last := FView.ToScreen(Stroke.P2);
        FBitmap.DrawLineAntialias(First.X, First.Y, Last.X, Last.Y, InkColor, 1);
      end;
      if Note.Leader = nlDot then
      begin
        Spot := FView.ToScreen(Tip);
        FBitmap.FillEllipseAntialias(Spot.X, Spot.Y, Max(1.5, LeaderDotRadius * FView.Scale), Max(1.5, LeaderDotRadius * FView.Scale), InkColor);
      end;
    end
    else if Selected and (Note.Anchor <> naFree) then
    begin
      // A plain note shows faintly what it hangs from
      Anchor := FView.ToScreen(Note.AnchorPosition);
      FBitmap.PenStyle := psDot;
      FBitmap.DrawLineAntialias(Anchor.X, Anchor.Y, TopLeft.X, TopLeft.Y, HoverHalo, 1);
      FBitmap.PenStyle := psSolid;
    end;
    // A selected callout's tip can be dragged to something else
    if Selected and (Note.Leader <> nlNone) and (FTool = ctSelect) then
    begin
      Spot := FView.ToScreen(Tip);
      FBitmap.EllipseAntialias(Spot.X, Spot.Y, HandleRadius, HandleRadius, SelectedInk, 1.5, Paper);
    end;
    if Note.Boxed then
    begin
      First := FView.ToScreen(Vec2(Frame.MinX, Frame.MinY));
      Last := FView.ToScreen(Vec2(Frame.MaxX, Frame.MaxY));
      FBitmap.FillRectAntialias(First.X, First.Y, Last.X, Last.Y, BGRA(255, 255, 255));
    end;
    if (Note.Key = FHoverKey) or Selected then
      FBitmap.FillRectAntialias(TopLeft.X - 2, TopLeft.Y - 1, BottomRight.X + 2, BottomRight.Y + 1, PieceHoverTint);
    EmPixels := Note.Size * PointsToMM * FView.Scale;
    LinePixels := LineHeight(Note.Size) * FView.Scale;
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

procedure TPatternCanvas.DrawMarker(DraftObject: TDraftObject);
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
      First := FView.ToScreen(Stroke.P1);
      Last := FView.ToScreen(Stroke.P2);
      FBitmap.DrawLineAntialias(First.X, First.Y, Last.X, Last.Y, LineColor, 1);
    end;
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
  for Key in ShownLabelKeys do
  begin
    Node := FDocument.Pattern.FindNode(Key);
    if Node is TPointObject then
    begin
      Screen := FView.ToScreen(TPointObject(Node).Position);
      Screen := Vec2(Screen.X + 6, Screen.Y - LabelFontHeight - 2);
    end
    else if Node is TPieceObject then
      Screen := FView.ToScreen(PieceMiddle(TPieceObject(Node)))
    else if Node is TEdgeObject then
    begin
      Model := EdgePolyline(TEdgeObject(Node), FView.PixelsToMM(FlattenPixels));
      if Length(Model) = 0 then
        Continue;
      Screen := FView.ToScreen(PolylineMiddle(Model));
      Screen := Vec2(Screen.X + 4, Screen.Y + 2);
    end
    else
      Continue;
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
  if not FSnapShown or ((FTool = ctSelect) and not FTipDragging) then
    Exit;
  Screen := FView.ToScreen(FSnap.Position);
  Size := SnapMarkerSize;
  // What the second click would make
  if FHasStart then
  begin
    Start := FView.ToScreen(FStartSnap.Position);
    FBitmap.PenStyle := psDash;
    case FTool of
      ctCircle:
        FBitmap.EllipseAntialias(Start.X, Start.Y, Distance(Start, Screen), Distance(Start, Screen), SelectedInk, 1.5);
      ctRectangle:
        FBitmap.RectangleAntialias(Min(Start.X, Screen.X), Min(Start.Y, Screen.Y), Max(Start.X, Screen.X), Max(Start.Y, Screen.Y),
          SelectedInk, 1.5);
      else
        FBitmap.DrawLineAntialias(Start.X, Start.Y, Screen.X, Screen.Y, SelectedInk, 1.5);
    end;
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
  if not Assigned(FHorzBar) or not Assigned(FVertBar) or FThumbHeld then
    Exit;
  if Assigned(FDocument) and PatternBounds(FDocument.Pattern, Bounds, not FDocument.Pattern.View.HideAnnotations) then
  begin
    TopLeft := FView.ToScreen(Vec2(Bounds.MinX, Bounds.MinY));
    BottomRight := FView.ToScreen(Vec2(Bounds.MaxX, Bounds.MaxY));
    ShowOnBar(FHorzBar, ScrollAxisFor(TopLeft.X - FitMargin, BottomRight.X + FitMargin, ClientWidth));
    ShowOnBar(FVertBar, ScrollAxisFor(TopLeft.Y - FitMargin, BottomRight.Y + FitMargin, ClientHeight));
  end
  else
  begin
    ShowOnBar(FHorzBar, ScrollAxisFor(0, ClientWidth, ClientWidth));
    ShowOnBar(FVertBar, ScrollAxisFor(0, ClientHeight, ClientHeight));
  end;
end;

// The selection box, dotted over a faint tint
procedure TPatternCanvas.DrawBox;
var
  X1, Y1, X2, Y2: single;
begin
  if FMode <> cmBoxing then
    Exit;
  X1 := Min(FPressPos.X, FLastPos.X) + 0.5;
  X2 := Max(FPressPos.X, FLastPos.X) + 0.5;
  Y1 := Min(FPressPos.Y, FLastPos.Y) + 0.5;
  Y2 := Max(FPressPos.Y, FLastPos.Y) + 0.5;
  FBitmap.FillRectAntialias(X1, Y1, X2, Y2, BoxFill);
  FBitmap.PenStyle := psDot;
  FBitmap.RectangleAntialias(X1, Y1, X2, Y2, SelectedInk, 1);
  FBitmap.PenStyle := psSolid;
end;

procedure TPatternCanvas.Paint;
begin
  if (FBitmap.Width <> ClientWidth) or (FBitmap.Height <> ClientHeight) then
    FBitmap.SetSize(Max(ClientWidth, 1), Max(ClientHeight, 1));
  FBitmap.Fill(Paper);
  FBitmap.FontHeight := LabelFontHeight;
  FBitmap.FontQuality := fqFineAntialiasing;
  DrawGrid;
  if Assigned(FDocument) then
  begin
    DrawPattern;
    DrawNotes;
    DrawHandles;
    DrawLabels;
    DrawSnap;
    DrawBox;
  end;
  FBitmap.Draw(Canvas, 0, 0, True);
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
