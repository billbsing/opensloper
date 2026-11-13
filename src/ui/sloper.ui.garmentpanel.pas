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

// The Garment tab: each piece as sewn, darts closed and folds opened, shaded,
// arranged as on the canvas. Read-only: hovering a piece names it and shows it
// on the canvas, and a click selects it there. The scene comes from
// Sloper.Core.Garment and is drawn by Sloper.Output.GarmentPNG, so the tab and
// its PNG export look the same. See Garment view in the design document.
unit Sloper.UI.GarmentPanel;

{$mode ObjFPC}{$H+}

interface

uses
  Classes, SysUtils, Controls, StdCtrls, ExtCtrls, Graphics, Dialogs, Menus, BGRABitmap, BGRABitmapTypes, Sloper.Core.Geometry,
  Sloper.Core.Garment, Sloper.Document.PatternDocument, Sloper.UI.View, Sloper.Output.GarmentPNG;

type
  TGarmentPieceEvent = procedure(Sender: TObject; const PieceKey: string) of object;
  TGarmentMessageEvent = procedure(Sender: TObject; const AText: string) of object;

  TGarmentPanel = class;

  // Where the pieces are drawn; the panel does the work
  TGarmentDrawing = class(TCustomControl)
  private
    FPanel: TGarmentPanel;
  protected
    procedure Paint; override;
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: integer); override;
    procedure MouseMove(Shift: TShiftState; X, Y: integer); override;
    procedure MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: integer); override;
    procedure MouseLeave; override;
    procedure DblClick; override;
    function DoMouseWheel(Shift: TShiftState; WheelDelta: integer; MousePos: TPoint): boolean; override;
    procedure Resize; override;
  end;

  TGarmentPanel = class(TPanel)
  private
    FDocument: TPatternDocument;
    FBuilder: TGarmentBuilder;
    FScene, FShown: TGarmentScene;
    // The pattern changed since the scene was built
    FDirty: boolean;
    // The last build took longer than a frame, so a drag waits for its release
    FSlow: boolean;
    FLight: TGarmentLight;
    FFrame: TGarmentFrame;
    // Fitted to the panel until the user zooms or pans
    FFitted: boolean;
    FCanvasView: TViewTransform;
    FCanvasWidth, FCanvasHeight: integer;
    FSelection: TStringArray;
    FHoverKey: string;
    FHoverAt: TPoint;
    FPressed, FPanning: boolean;
    FPressAt: TPoint;
    FBitmap: TBGRABitmap;
    // Material keys in the list's order after "All", and the one chosen
    // unless all are shown; the first material's key may be ''
    FMaterialKeys: TStringArray;
    FMaterialKey: string;
    FAllMaterials: boolean;
    FMaterialChosen: boolean;
    FRefreshing: boolean;
    FToolbar: TPanel;
    FMaterialBox: TComboBox;
    FFollowBox: TCheckBox;
    FExportButton: TButton;
    FExportMenu: TPopupMenu;
    FDrawing: TGarmentDrawing;
    FNotes: TLabel;
    FOnHoverPiece, FOnSelectPiece: TGarmentPieceEvent;
    FOnMessage: TGarmentMessageEvent;
    procedure SetDocument(ADocument: TPatternDocument);
    procedure SetLight(const ALight: TGarmentLight);
    procedure DocumentChanged(Document: TPatternDocument; Changes: TDocumentChanges);
    procedure Build;
    procedure RefreshMaterials;
    procedure ChooseShown;
    function ShownMaterialIndex: integer;
    procedure UpdateFrame;
    function Marks: TGarmentMarks;
    function ModelAt(X, Y: integer): TVec2;
    procedure SetHover(const Key: string);
    procedure PaintDrawing;
    procedure DrawingMouseDown(Button: TMouseButton; X, Y: integer);
    procedure DrawingMouseMove(X, Y: integer);
    procedure DrawingMouseUp(Button: TMouseButton; X, Y: integer);
    procedure DrawingMouseLeave;
    procedure DrawingDoubleClick;
    procedure DrawingWheel(WheelDelta: integer; const MousePos: TPoint);
    procedure MaterialChange(Sender: TObject);
    procedure FollowClick(Sender: TObject);
    procedure ExportButtonClick(Sender: TObject);
    procedure ExportSVGClick(Sender: TObject);
    procedure ExportPNGClick(Sender: TObject);
    function ChooseExportFile(const Extension, Filter: string; out FileName: string): boolean;
    procedure Say(const AText: string);
    procedure CreateControls;
  protected
    procedure SetParent(NewParent: TWinControl); override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    // The canvas's selection: selected pieces are outlined, and a selected
    // seam is marked on both its sides
    procedure ShowSelection(const Keys: TStringArray);
    // The canvas's zoom and pan, for Follow canvas
    procedure ShowCanvasView(const View: TViewTransform; AWidth, AHeight: integer);
    property Document: TPatternDocument read FDocument write SetDocument;
    // From Preferences
    property Light: TGarmentLight read FLight write SetLight;
    // The piece under the pointer, or '' when it leaves
    property OnHoverPiece: TGarmentPieceEvent read FOnHoverPiece write FOnHoverPiece;
    property OnSelectPiece: TGarmentPieceEvent read FOnSelectPiece write FOnSelectPiece;
    property OnMessage: TGarmentMessageEvent read FOnMessage write FOnMessage;
  end;

resourcestring
  rsGarmentAllMaterials = 'All materials';
  rsGarmentMaterialHint = 'Which material''s pieces to show';
  rsGarmentFollow = 'Follow canvas';
  rsGarmentFollowHint = 'Use the canvas''s zoom and pan';
  rsGarmentExport = 'Export…';
  rsGarmentExportHint = 'Save the Garment view as SVG or PNG';
  rsGarmentExportSVG = 'SVG…';
  rsGarmentExportPNG = 'PNG…';
  rsGarmentSVGFilter = 'SVG images (*.svg)|*.svg';
  rsGarmentPNGFilter = 'PNG images (*.png)|*.png';
  rsGarmentPNGTitle = 'Export PNG';
  rsGarmentPNGPrompt = 'Width in pixels (%d to %d)';
  rsGarmentExported = 'Saved the Garment view as %s';
  rsGarmentExportFailed = 'The Garment view could not be saved as %s: %s';
  rsGarmentUnnamed = 'garment';
  rsGarmentNoPieces = 'No pieces to show. Make pieces on the canvas to see them here as sewn.';
  rsGarmentNoPiecesOfMaterial = 'No pieces of this material.';

implementation

uses
  Math, Sloper.Core.JSON, Sloper.Core.Evaluator, Sloper.Core.Pattern, Sloper.Core.Piece, Sloper.Core.Seam, Sloper.Output.GarmentSVG;

const
  // At 96 pixels per inch
  FIT_MARGIN96 = 16;
  HINT_PADDING96 = 4;
  // A press that moves further than this pans rather than clicks
  DRAG_THRESHOLD = 4;
  ZOOM_STEP = 1.25;
  MIN_SCALE = 0.02;
  MAX_SCALE = 50;
  // A build longer than this, in milliseconds, waits for a drag to finish
  FRAME_MILLISECONDS = 16;

  { TGarmentDrawing }

procedure TGarmentDrawing.Paint;
begin
  FPanel.PaintDrawing;
end;

procedure TGarmentDrawing.MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: integer);
begin
  inherited MouseDown(Button, Shift, X, Y);
  FPanel.DrawingMouseDown(Button, X, Y);
end;

procedure TGarmentDrawing.MouseMove(Shift: TShiftState; X, Y: integer);
begin
  inherited MouseMove(Shift, X, Y);
  FPanel.DrawingMouseMove(X, Y);
end;

procedure TGarmentDrawing.MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: integer);
begin
  inherited MouseUp(Button, Shift, X, Y);
  FPanel.DrawingMouseUp(Button, X, Y);
end;

procedure TGarmentDrawing.MouseLeave;
begin
  inherited MouseLeave;
  FPanel.DrawingMouseLeave;
end;

procedure TGarmentDrawing.DblClick;
begin
  inherited DblClick;
  FPanel.DrawingDoubleClick;
end;

function TGarmentDrawing.DoMouseWheel(Shift: TShiftState; WheelDelta: integer; MousePos: TPoint): boolean;
begin
  FPanel.DrawingWheel(WheelDelta, MousePos);
  Result := True;
end;

procedure TGarmentDrawing.Resize;
begin
  inherited Resize;
  Invalidate;
end;

{ TGarmentPanel }

constructor TGarmentPanel.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  BevelOuter := bvNone;
  FBuilder := TGarmentBuilder.Create;
  FBitmap := TBGRABitmap.Create(1, 1);
  FLight := DefaultGarmentLight;
  FFitted := True;
  FDirty := True;
end;

destructor TGarmentPanel.Destroy;
begin
  Document := nil;
  FreeAndNil(FBitmap);
  FreeAndNil(FBuilder);
  inherited Destroy;
end;

// Once on a form, as sizes scale with the screen
procedure TGarmentPanel.SetParent(NewParent: TWinControl);
begin
  inherited SetParent(NewParent);
  if Assigned(NewParent) and not Assigned(FDrawing) then
    CreateControls;
end;

procedure TGarmentPanel.CreateControls;
var
  Item: TMenuItem;
begin
  FToolbar := TPanel.Create(Self);
  FToolbar.Parent := Self;
  FToolbar.Align := alTop;
  FToolbar.BevelOuter := bvNone;
  FToolbar.AutoSize := True;
  FToolbar.BorderSpacing.Around := Scale96ToForm(4);
  FExportButton := TButton.Create(Self);
  FExportButton.Parent := FToolbar;
  FExportButton.Align := alRight;
  FExportButton.AutoSize := True;
  FExportButton.Caption := rsGarmentExport;
  FExportButton.Hint := rsGarmentExportHint;
  FExportButton.ShowHint := True;
  FExportButton.OnClick := @ExportButtonClick;
  FFollowBox := TCheckBox.Create(Self);
  FFollowBox.Parent := FToolbar;
  FFollowBox.Align := alRight;
  FFollowBox.BorderSpacing.Left := Scale96ToForm(6);
  FFollowBox.BorderSpacing.Right := Scale96ToForm(6);
  FFollowBox.Caption := rsGarmentFollow;
  FFollowBox.Hint := rsGarmentFollowHint;
  FFollowBox.ShowHint := True;
  FFollowBox.OnClick := @FollowClick;
  FMaterialBox := TComboBox.Create(Self);
  FMaterialBox.Parent := FToolbar;
  FMaterialBox.Align := alClient;
  FMaterialBox.Style := csDropDownList;
  FMaterialBox.Hint := rsGarmentMaterialHint;
  FMaterialBox.ShowHint := True;
  FMaterialBox.OnChange := @MaterialChange;
  FExportMenu := TPopupMenu.Create(Self);
  Item := TMenuItem.Create(FExportMenu);
  Item.Caption := rsGarmentExportSVG;
  Item.OnClick := @ExportSVGClick;
  FExportMenu.Items.Add(Item);
  Item := TMenuItem.Create(FExportMenu);
  Item.Caption := rsGarmentExportPNG;
  Item.OnClick := @ExportPNGClick;
  FExportMenu.Items.Add(Item);
  FNotes := TLabel.Create(Self);
  FNotes.Parent := Self;
  FNotes.Align := alBottom;
  FNotes.WordWrap := True;
  FNotes.AutoSize := True;
  FNotes.BorderSpacing.Around := Scale96ToForm(6);
  FNotes.Visible := False;
  FDrawing := TGarmentDrawing.Create(Self);
  FDrawing.FPanel := Self;
  FDrawing.Parent := Self;
  FDrawing.Align := alClient;
  FDrawing.ControlStyle := FDrawing.ControlStyle + [csOpaque];
  RefreshMaterials;
end;

procedure TGarmentPanel.SetDocument(ADocument: TPatternDocument);
begin
  if ADocument = FDocument then
    Exit;
  if Assigned(FDocument) then
    FDocument.RemoveListener(@DocumentChanged);
  FDocument := ADocument;
  FBuilder.Clear;
  FScene := Default(TGarmentScene);
  FShown := Default(TGarmentScene);
  FMaterialChosen := False;
  if Assigned(FDocument) then
    FDocument.AddListener(@DocumentChanged);
  FDirty := True;
  RefreshMaterials;
  if Assigned(FDrawing) then
    FDrawing.Invalidate;
end;

procedure TGarmentPanel.SetLight(const ALight: TGarmentLight);
begin
  FLight := ALight;
  if Assigned(FDrawing) then
    FDrawing.Invalidate;
end;

// Nothing is built here: the drawing builds when it next paints, which it
// does only while the tab shows
procedure TGarmentPanel.DocumentChanged(Document: TPatternDocument; Changes: TDocumentChanges);
begin
  if dcObjectsReplaced in Changes then
  begin
    // Another pattern: start again on its first material, fitted
    FBuilder.Clear;
    FMaterialChosen := False;
    FFitted := True;
  end;
  // dcView too, for hidden, isolated and reordered pieces
  if Changes * [dcPattern, dcObjectsReplaced, dcMeasurements, dcHistory, dcView] = [] then
    Exit;
  FDirty := True;
  RefreshMaterials;
  if Assigned(FDrawing) then
    FDrawing.Invalidate;
end;

procedure TGarmentPanel.Build;
var
  Started: QWord;
begin
  FDirty := False;
  if not Assigned(FDocument) then
  begin
    FScene := Default(TGarmentScene);
    ChooseShown;
    Exit;
  end;
  Started := GetTickCount64;
  FScene := FBuilder.Build(FDocument.Pattern, True);
  FSlow := GetTickCount64 - Started > FRAME_MILLISECONDS;
  ChooseShown;
end;

function TGarmentPanel.ShownMaterialIndex: integer;
var
  Index: integer;
begin
  Result := -1;
  if not Assigned(FDocument) or FAllMaterials then
    Exit;
  for Index := 0 to FDocument.Pattern.MaterialCount - 1 do
    if FDocument.Pattern.Materials[Index].Key = FMaterialKey then
      Exit(Index);
end;

// The scene of the chosen material, and the notes under it
procedure TGarmentPanel.ChooseShown;
var
  NoteText: string;
begin
  FShown := GarmentOfMaterial(FScene, ShownMaterialIndex);
  if not Assigned(FNotes) then
    Exit;
  NoteText := string.Join(LineEnding, FShown.Notes);
  if Length(FScene.Pieces) = 0 then
    NoteText := Trim(rsGarmentNoPieces + LineEnding + NoteText)
  else if Length(FShown.Pieces) = 0 then
    NoteText := Trim(rsGarmentNoPiecesOfMaterial + LineEnding + NoteText);
  FNotes.Caption := NoteText;
  FNotes.Visible := NoteText <> '';
end;

// The list of materials, keeping the one chosen; it starts on the first, so
// lining and interfacing do not cover the main pieces
procedure TGarmentPanel.RefreshMaterials;
var
  Index, Chosen: integer;
  Pattern: TPattern;
begin
  if not Assigned(FMaterialBox) then
    Exit;
  FRefreshing := True;
  try
    FMaterialBox.Items.BeginUpdate;
    try
      FMaterialBox.Items.Clear;
      FMaterialBox.Items.Add(rsGarmentAllMaterials);
      FMaterialKeys := nil;
      if Assigned(FDocument) then
      begin
        Pattern := FDocument.Pattern;
        for Index := 0 to Pattern.MaterialCount - 1 do
        begin
          FMaterialBox.Items.Add(Pattern.Materials[Index].Name);
          Insert(Pattern.Materials[Index].Key, FMaterialKeys, Length(FMaterialKeys));
        end;
      end;
    finally
      FMaterialBox.Items.EndUpdate;
    end;
    if not FMaterialChosen and Assigned(FDocument) then
    begin
      FMaterialChosen := True;
      FAllMaterials := Length(FMaterialKeys) = 0;
      if not FAllMaterials then
        FMaterialKey := FMaterialKeys[0];
    end;
    Chosen := 0;
    if not FAllMaterials then
      for Index := 0 to High(FMaterialKeys) do
        if FMaterialKeys[Index] = FMaterialKey then
          Chosen := Index + 1;
    // The first material, '' until it has an ID, keeps its place when it gets one
    if not FAllMaterials and (Chosen = 0) and (FMaterialKey = '') and (Length(FMaterialKeys) > 0) then
    begin
      Chosen := 1;
      FMaterialKey := FMaterialKeys[0];
    end;
    // A chosen material deleted: show them all
    FAllMaterials := Chosen = 0;
    FMaterialBox.ItemIndex := Chosen;
  finally
    FRefreshing := False;
  end;
end;

procedure TGarmentPanel.MaterialChange(Sender: TObject);
begin
  if FRefreshing then
    Exit;
  FAllMaterials := FMaterialBox.ItemIndex <= 0;
  if not FAllMaterials then
    FMaterialKey := FMaterialKeys[FMaterialBox.ItemIndex - 1];
  ChooseShown;
  FFitted := True;
  FDrawing.Invalidate;
end;

procedure TGarmentPanel.FollowClick(Sender: TObject);
begin
  if not FFollowBox.Checked then
    FFitted := True;
  FDrawing.Invalidate;
end;

procedure TGarmentPanel.ShowSelection(const Keys: TStringArray);
begin
  FSelection := Copy(Keys);
  if Assigned(FDrawing) then
    FDrawing.Invalidate;
end;

procedure TGarmentPanel.ShowCanvasView(const View: TViewTransform; AWidth, AHeight: integer);
begin
  FCanvasView := View;
  FCanvasWidth := AWidth;
  FCanvasHeight := AHeight;
  if Assigned(FFollowBox) and FFollowBox.Checked then
    FDrawing.Invalidate;
end;

procedure TGarmentPanel.UpdateFrame;
var
  Centre: TVec2;
begin
  if FFollowBox.Checked and (FCanvasView.Scale > 0) then
  begin
    // The canvas's zoom, and the middle of what it shows in the middle here
    Centre := FCanvasView.ToModel(Vec2(FCanvasWidth / 2, FCanvasHeight / 2));
    FFrame.Scale := FCanvasView.Scale;
    FFrame.Left := Centre.X - FDrawing.ClientWidth / 2 / FFrame.Scale;
    FFrame.Top := Centre.Y - FDrawing.ClientHeight / 2 / FFrame.Scale;
  end
  else if FFitted then
  begin
    if Length(FShown.Pieces) > 0 then
      FFrame := FitGarmentFrame(FShown.Bounds, FDrawing.ClientWidth, FDrawing.ClientHeight, Scale96ToForm(FIT_MARGIN96))
    else
    begin
      FFrame.Scale := 1;
      FFrame.Left := 0;
      FFrame.Top := 0;
    end;
  end;
end;

// What the canvas has selected, as the drawing marks it
function TGarmentPanel.Marks: TGarmentMarks;
var
  Key: string;
  Node: TEvalNode;
  Seam: TSeamObject;
  Entry: TSeamEntry;
begin
  Result := Default(TGarmentMarks);
  Result.HoverPiece := FHoverKey;
  if not Assigned(FDocument) then
    Exit;
  for Key in FSelection do
  begin
    Node := FDocument.Pattern.FindNode(Key);
    if Node is TPieceObject then
      Insert(Key, Result.SelectedPieces, Length(Result.SelectedPieces))
    else if Node is TSeamObject then
    begin
      Seam := TSeamObject(Node);
      Insert(Seam.Key, Result.SeamKeys, Length(Result.SeamKeys));
      for Entry in Seam.SideA do
        Insert(Entry.PieceKey + ':' + Entry.EdgeKey, Result.SeamEdges, Length(Result.SeamEdges));
      for Entry in Seam.SideB do
        Insert(Entry.PieceKey + ':' + Entry.EdgeKey, Result.SeamEdges, Length(Result.SeamEdges));
    end;
  end;
end;

function TGarmentPanel.ModelAt(X, Y: integer): TVec2;
begin
  Result := Vec2(X / FFrame.Scale + FFrame.Left, Y / FFrame.Scale + FFrame.Top);
end;

procedure TGarmentPanel.PaintDrawing;
var
  Background: TBGRAPixel;
  Index: integer;
  PieceName: string;
  Box: TRect;
  Inset: integer;
begin
  // A drag is shown on its release when building is slower than a frame
  if FDirty and not (FSlow and Assigned(FDocument) and FDocument.ChangeOpen) then
    Build;
  UpdateFrame;
  if (FBitmap.Width <> FDrawing.ClientWidth) or (FBitmap.Height <> FDrawing.ClientHeight) then
    FBitmap.SetSize(Max(FDrawing.ClientWidth, 1), Max(FDrawing.ClientHeight, 1));
  Background := ColorToBGRA(ColorToRGB(clWindow));
  FBitmap.Fill(Background);
  DrawGarment(FBitmap, FShown, FFrame, FLight, Marks, Background);
  FBitmap.Draw(FDrawing.Canvas, 0, 0, True);
  // The piece's name beside the pointer
  if FHoverKey = '' then
    Exit;
  PieceName := '';
  for Index := 0 to High(FShown.Pieces) do
    if FShown.Pieces[Index].PieceKey = FHoverKey then
      PieceName := FShown.Pieces[Index].Name;
  if PieceName = '' then
    Exit;
  Inset := Scale96ToForm(HINT_PADDING96);
  FDrawing.Canvas.Font.Color := clInfoText;
  FDrawing.Canvas.Brush.Color := clInfoBk;
  FDrawing.Canvas.Pen.Color := clInfoText;
  Box.Left := FHoverAt.X + Scale96ToForm(14);
  Box.Top := FHoverAt.Y + Scale96ToForm(14);
  Box.Right := Box.Left + FDrawing.Canvas.TextWidth(PieceName) + 2 * Inset;
  Box.Bottom := Box.Top + FDrawing.Canvas.TextHeight(PieceName) + 2 * Inset;
  // Kept inside the panel
  if Box.Right > FDrawing.ClientWidth then
    Box.Offset(FHoverAt.X - Box.Right - Scale96ToForm(4), 0);
  if Box.Bottom > FDrawing.ClientHeight then
    Box.Offset(0, FHoverAt.Y - Box.Bottom - Scale96ToForm(4));
  FDrawing.Canvas.Rectangle(Box);
  FDrawing.Canvas.TextOut(Box.Left + Inset, Box.Top + Inset, PieceName);
end;

procedure TGarmentPanel.SetHover(const Key: string);
begin
  if Key = FHoverKey then
    Exit;
  FHoverKey := Key;
  if Assigned(FOnHoverPiece) then
    FOnHoverPiece(Self, Key);
end;

procedure TGarmentPanel.DrawingMouseDown(Button: TMouseButton; X, Y: integer);
begin
  if Button <> mbLeft then
    Exit;
  FPressed := True;
  FPanning := False;
  FPressAt := Point(X, Y);
end;

procedure TGarmentPanel.DrawingMouseMove(X, Y: integer);
var
  Index: integer;
begin
  if FPressed and not FFollowBox.Checked and (FPanning or (Abs(X - FPressAt.X) > DRAG_THRESHOLD) or
    (Abs(Y - FPressAt.Y) > DRAG_THRESHOLD)) then
  begin
    FPanning := True;
    FFitted := False;
    FFrame.Left := FFrame.Left - (X - FPressAt.X) / FFrame.Scale;
    FFrame.Top := FFrame.Top - (Y - FPressAt.Y) / FFrame.Scale;
    FPressAt := Point(X, Y);
  end;
  FHoverAt := Point(X, Y);
  Index := GarmentPieceAt(FShown, ModelAt(X, Y));
  if Index >= 0 then
    SetHover(FShown.Pieces[Index].PieceKey)
  else
    SetHover('');
  FDrawing.Invalidate;
end;

procedure TGarmentPanel.DrawingMouseUp(Button: TMouseButton; X, Y: integer);
var
  Index: integer;
begin
  if (Button <> mbLeft) or not FPressed then
    Exit;
  FPressed := False;
  if FPanning then
    Exit;
  Index := GarmentPieceAt(FShown, ModelAt(X, Y));
  if (Index >= 0) and Assigned(FOnSelectPiece) then
    FOnSelectPiece(Self, FShown.Pieces[Index].PieceKey);
end;

procedure TGarmentPanel.DrawingMouseLeave;
begin
  SetHover('');
  FDrawing.Invalidate;
end;

procedure TGarmentPanel.DrawingDoubleClick;
begin
  FFitted := True;
  FDrawing.Invalidate;
end;

procedure TGarmentPanel.DrawingWheel(WheelDelta: integer; const MousePos: TPoint);
var
  Anchor: TVec2;
  Factor, NewScale: double;
begin
  if FFollowBox.Checked or (WheelDelta = 0) then
    Exit;
  Anchor := ModelAt(MousePos.X, MousePos.Y);
  if WheelDelta > 0 then
    Factor := ZOOM_STEP
  else
    Factor := 1 / ZOOM_STEP;
  NewScale := EnsureRange(FFrame.Scale * Factor, MIN_SCALE, MAX_SCALE);
  // The point under the pointer stays under it
  FFrame.Left := Anchor.X - MousePos.X / NewScale;
  FFrame.Top := Anchor.Y - MousePos.Y / NewScale;
  FFrame.Scale := NewScale;
  FFitted := False;
  FDrawing.Invalidate;
end;

procedure TGarmentPanel.ExportButtonClick(Sender: TObject);
var
  At: TPoint;
begin
  At := FExportButton.ClientToScreen(Point(0, FExportButton.Height));
  FExportMenu.PopUp(At.X, At.Y);
end;

function TGarmentPanel.ChooseExportFile(const Extension, Filter: string; out FileName: string): boolean;
var
  Dialog: TSaveDialog;
  PatternName: string;
begin
  FileName := '';
  PatternName := rsGarmentUnnamed;
  if Assigned(FDocument) and (FDocument.FileName <> '') then
    PatternName := ChangeFileExt(ExtractFileName(FDocument.FileName), '') + '-' + rsGarmentUnnamed;
  Dialog := TSaveDialog.Create(Self);
  try
    Dialog.Filter := Filter;
    Dialog.DefaultExt := Extension;
    Dialog.Options := Dialog.Options + [ofOverwritePrompt];
    Dialog.FileName := PatternName + '.' + Extension;
    if Assigned(FDocument) and (FDocument.FileName <> '') then
      Dialog.InitialDir := ExtractFileDir(FDocument.FileName);
    Result := Dialog.Execute;
    if Result then
      FileName := Dialog.FileName;
  finally
    FreeAndNil(Dialog);
  end;
end;

procedure TGarmentPanel.ExportSVGClick(Sender: TObject);
var
  FileName, Reason: string;
begin
  if FDirty then
    Build;
  if not ChooseExportFile('svg', rsGarmentSVGFilter, FileName) then
    Exit;
  if WriteTextFile(FileName, GarmentToSVG(FShown, FLight), Reason) then
    Say(Format(rsGarmentExported, [ExtractFileName(FileName)]))
  else
    MessageDlg(Format(rsGarmentExportFailed, [FileName, Reason]), mtError, [mbOK], 0);
end;

procedure TGarmentPanel.ExportPNGClick(Sender: TObject);
var
  FileName, Reason, WidthText: string;
  Png: rawbytestring;
  PngWidth: integer;
  Output: TFileStream;
begin
  if FDirty then
    Build;
  WidthText := IntToStr(GARMENT_PNG_DEFAULT_WIDTH);
  if not InputQuery(rsGarmentPNGTitle, Format(rsGarmentPNGPrompt, [GARMENT_PNG_MIN_WIDTH, GARMENT_PNG_MAX_WIDTH]), WidthText) then
    Exit;
  PngWidth := StrToIntDef(Trim(WidthText), 0);
  if not GarmentToPNG(FShown, FLight, PngWidth, Png, Reason) then
  begin
    MessageDlg(Reason, mtError, [mbOK], 0);
    Exit;
  end;
  if not ChooseExportFile('png', rsGarmentPNGFilter, FileName) then
    Exit;
  try
    Output := TFileStream.Create(FileName, fmCreate);
    try
      if Length(Png) > 0 then
        Output.WriteBuffer(Png[1], Length(Png));
    finally
      FreeAndNil(Output);
    end;
    Say(Format(rsGarmentExported, [ExtractFileName(FileName)]));
  except
    on Failure: Exception do
      MessageDlg(Format(rsGarmentExportFailed, [FileName, Failure.Message]), mtError, [mbOK], 0);
  end;
end;

procedure TGarmentPanel.Say(const AText: string);
begin
  if Assigned(FOnMessage) then
    FOnMessage(Self, AText);
end;

end.
