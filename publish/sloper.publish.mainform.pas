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

// The publish app's one window: the preview, with the paper settings, the
// problems and the actions beside it. It only arranges and prints; every edit
// goes through TLayoutDocument. Built in code, so it has no form file.
unit Sloper.Publish.MainForm;

{$mode ObjFPC}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, StdCtrls, ExtCtrls, ComCtrls, Menus, Spin, Dialogs, Sloper.Output.Layout, Sloper.Output.LayoutDocument,
  Sloper.Publish.PreviewCanvas;

type
  TPublishForm = class(TForm)
  private
    FDocument: TLayoutDocument;
    FPreview: TPreviewCanvas;
    // The side tabs; the rows being built go into FRowParent
    FTabs: TPageControl;
    FPiecesSide, FSide, FNotesSide, FRowParent: TWinControl;
    FColumn: TPanel;
    FTitleBox, FEveryPageBox: TCheckBox;
    FFieldBoxes: array[0..3] of TCheckBox;
    FCornerBox: TComboBox;
    FNoteMemo: TMemo;
    FNoteSizeEdit: TFloatSpinEdit;
    FDeleteNoteButton: TButton;
    FStatus: TStatusBar;
    FKindBox, FPaperBox: TComboBox;
    FRollEdit, FMarginEdit, FOverlapEdit, FCalibrationXEdit, FCalibrationYEdit: TFloatSpinEdit;
    FTray, FProblems: TListBox;
    // What each tray line stands for
    FTrayCopies: TUnplacedCopyArray;
    FTurnButton, FFlipButton, FRemoveButton: TButton;
    FUndoItem, FRedoItem: TMenuItem;
    FWatch: TTimer;
    FRefreshing: boolean;
    // Rows stack in the order their Top says, so each takes the next one
    FNextRowTop: integer;
    procedure PlaceRow(Row: TControl);
    procedure BuildMenu;
    procedure BuildPiecesTab;
    procedure BuildSide;
    function AddSpin(const ACaption: string; AMax, AIncrement: double; Decimals: integer): TFloatSpinEdit;
    function AddLabel(const ACaption: string): TLabel;
    function AddButton(const ACaption: string; AHandler: TNotifyEvent): TButton;
    procedure DocumentChanged(Sender: TObject);
    procedure SelectionChanged(Sender: TObject);
    procedure RefreshControls;
    procedure WatchTick(Sender: TObject);
    procedure RefreshProblems;
    procedure RefreshTray;
    procedure RefreshNotesTab;
    procedure BuildNotesTab;
    function AddCheck(const ACaption: string): TCheckBox;
    procedure TitleChange(Sender: TObject);
    procedure NoteChange(Sender: TObject);
    procedure AddNoteClick(Sender: TObject);
    procedure DeleteNoteClick(Sender: TObject);
    procedure TrayMouseDown(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: integer);
    procedure TrayDoubleClick(Sender: TObject);
    procedure PreviewDragOver(Sender, Source: TObject; X, Y: integer; State: TDragState; var Accept: boolean);
    procedure PreviewDragDrop(Sender, Source: TObject; X, Y: integer);
    procedure RemoveClick(Sender: TObject);
    procedure SettingChange(Sender: TObject);
    procedure OpenClick(Sender: TObject);
    procedure SaveClick(Sender: TObject);
    procedure SaveAsClick(Sender: TObject);
    procedure ExportClick(Sender: TObject);
    procedure QuitClick(Sender: TObject);
    procedure UndoClick(Sender: TObject);
    procedure RedoClick(Sender: TObject);
    procedure FitClick(Sender: TObject);
    procedure PlaceClick(Sender: TObject);
    procedure ReloadClick(Sender: TObject);
    procedure TurnClick(Sender: TObject);
    procedure FlipClick(Sender: TObject);
    procedure CloseAsked(Sender: TObject; var CanClose: boolean);
    function ConfirmDiscard: boolean;
    procedure OpenPath(const Path: string);
    procedure ShowStatus(const AText: string);
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
  end;

resourcestring
  rsPublishTitle = 'OpenSloper Publish';
  rsPublishTitleFile = '%s%s - OpenSloper Publish';
  rsMenuFile = '&File';
  rsMenuOpen = '&Open...';
  rsMenuSave = '&Save';
  rsMenuSaveAs = 'Save &As...';
  rsMenuExport = '&Export PDF...';
  rsMenuQuit = '&Quit';
  rsMenuEdit = '&Edit';
  rsMenuUndo = '&Undo';
  rsMenuUndoNamed = '&Undo %s';
  rsMenuRedo = '&Redo';
  rsMenuView = '&View';
  rsMenuFit = '&Fit Pages';
  rsMenuReload = '&Reload Patterns';
  rsOutput = 'Output';
  rsOutputTiled = 'Tiled pages';
  rsOutputLarge = 'Large format';
  rsOutputProjector = 'Projector';
  rsRollWidth = 'Roll width (mm)';
  rsPaper = 'Paper';
  rsMargin = 'Margin (mm)';
  rsOverlap = 'Overlap (mm)';
  rsCalibrationX = 'Calibration across';
  rsCalibrationY = 'Calibration down';
  rsTray = 'Unplaced: drag onto the pages';
  rsTrayEmpty = 'Every piece is placed';
  rsRemove = 'Back to tray';
  rsTabPieces = 'Pieces';
  rsTabOutput = 'Output';
  rsTabNotes = 'Notes';
  rsTitleBlock = 'Title block';
  rsEveryPage = 'On every page';
  rsCorner = 'Corner';
  rsCornerBottomRight = 'Bottom right';
  rsCornerBottomLeft = 'Bottom left';
  rsCornerTopRight = 'Top right';
  rsFieldPattern = 'Pattern';
  rsFieldMeasurements = 'Measurements';
  rsFieldLayout = 'Layout name';
  rsFieldDate = 'Date';
  rsSheetNote = 'Sheet note';
  rsNoteSize = 'Text size (pt)';
  rsAddNote = 'Add note';
  rsDeleteNote = 'Delete note';
  rsNoteHelp = 'Fields: {pattern.name} {measurements.name} {date} {page} {pages}';
  rsNewNote = 'New note';
  rsChangeTitle = 'Change title block';
  rsChangeNote = 'Change note';
  rsAddNoteChange = 'Add note';
  rsCannotPlace = 'This piece has a problem in the pattern, so it cannot be placed yet';
  rsNoProblems = 'No problems';
  rsPlaceNew = 'Place new pieces';
  rsTurn = 'Turn 90°';
  rsFlip = 'Flip';
  rsExportPDF = 'Export PDF...';
  rsChangeSettings = 'Change paper';
  rsPlaceChange = 'Place new pieces';
  rsPlaceOne = 'Place piece';
  rsTurnChange = 'Turn piece';
  rsFlipChange = 'Flip piece';
  rsDiscardQuestion = 'Discard the changes to this layout?';
  rsPages = '%d pages, %d blank, %d left out. Right-click a page to leave it out.';
  rsLargeSheet = 'One sheet %s mm wide, %s mm long';
  rsReloaded = '%s changed on disk, so it was read again';
  rsExported = 'Wrote %s';
  rsFilterOpen = 'Layouts and patterns (*.slayout;*.sloper)|*.slayout;*.sloper';
  rsFilterLayout = 'Layouts (*.slayout)|*.slayout';
  rsFilterPDF = 'PDF (*.pdf)|*.pdf';

implementation

uses
  LCLType, Math, Sloper.Core.Geometry, Sloper.Output.LayoutPDF, Sloper.Output.Preview, Sloper.Output.Tiling;

const
  SideWidth = 280;
  NewNoteSize = 12;
  NewNoteGap = 10;
  MaxNoteSize = 200;
  NoteMemoHeight = 110;
  // In the order of FFieldBoxes
  TitleFields: array[0..3] of string = (FieldPatternName, FieldMeasurementsName, FieldLayoutName, FieldDate);
  SideGap = 6;
  SideRowStep = 100;
  ProblemsHeight = 110;
  WatchMilliseconds = 1000;
  SpinDecimals = 1;
  CalibrationDecimals = 3;
  MaxMillimetres = 100;
  MaxRollWidth = 2000;
  MaxCalibration = 2;
  PatternExtension = '.sloper';
  PaperNames: array[0..2] of string = ('A4', 'A3', 'Letter');

constructor TPublishForm.Create(AOwner: TComponent);
begin
  inherited CreateNew(AOwner);
  Caption := rsPublishTitle;
  Width := 1100;
  Height := 750;
  Position := poScreenCenter;
  OnCloseQuery := @CloseAsked;
  FDocument := TLayoutDocument.Create;
  FDocument.OnChange := @DocumentChanged;
  BuildMenu;
  FStatus := TStatusBar.Create(Self);
  FStatus.Parent := Self;
  FColumn := TPanel.Create(Self);
  FColumn.Parent := Self;
  FColumn.Align := alRight;
  FColumn.Width := SideWidth;
  FColumn.BevelOuter := bvNone;
  FProblems := TListBox.Create(Self);
  FProblems.Parent := FColumn;
  FProblems.Align := alBottom;
  FProblems.Height := ProblemsHeight;
  FProblems.BorderSpacing.Around := SideGap;
  FTabs := TPageControl.Create(Self);
  FTabs.Parent := FColumn;
  FTabs.Align := alClient;
  FPiecesSide := FTabs.AddTabSheet;
  TTabSheet(FPiecesSide).Caption := rsTabPieces;
  FSide := FTabs.AddTabSheet;
  TTabSheet(FSide).Caption := rsTabOutput;
  FNotesSide := FTabs.AddTabSheet;
  TTabSheet(FNotesSide).Caption := rsTabNotes;
  FPreview := TPreviewCanvas.Create(Self);
  FPreview.Parent := Self;
  FPreview.Align := alClient;
  FPreview.Document := FDocument;
  FPreview.OnSelectionChange := @SelectionChanged;
  FPreview.OnDragOver := @PreviewDragOver;
  FPreview.OnDragDrop := @PreviewDragDrop;
  FRowParent := FPiecesSide;
  BuildPiecesTab;
  FRowParent := FSide;
  BuildSide;
  FRowParent := FNotesSide;
  BuildNotesTab;
  RefreshControls;
  FWatch := TTimer.Create(Self);
  FWatch.Interval := WatchMilliseconds;
  FWatch.OnTimer := @WatchTick;
  if (ParamCount >= 1) and FileExists(ParamStr(1)) then
    OpenPath(ParamStr(1));
end;

destructor TPublishForm.Destroy;
begin
  FreeAndNil(FDocument);
  inherited Destroy;
end;

procedure TPublishForm.BuildMenu;
var
  Bar: TMainMenu;

  function AddMenu(const ACaption: string): TMenuItem;
  begin
    Result := TMenuItem.Create(Bar);
    Result.Caption := ACaption;
    Bar.Items.Add(Result);
  end;

  function AddItem(Parent: TMenuItem; const ACaption: string; AHandler: TNotifyEvent; AShortCut: TShortCut = 0): TMenuItem;
  begin
    Result := TMenuItem.Create(Parent);
    Result.Caption := ACaption;
    Result.OnClick := AHandler;
    Result.ShortCut := AShortCut;
    Parent.Add(Result);
  end;

var
  Group: TMenuItem;
begin
  Bar := TMainMenu.Create(Self);
  Menu := Bar;
  Group := AddMenu(rsMenuFile);
  AddItem(Group, rsMenuOpen, @OpenClick, ShortCut(VK_O, [ssModifier]));
  AddItem(Group, rsMenuSave, @SaveClick, ShortCut(VK_S, [ssModifier]));
  AddItem(Group, rsMenuSaveAs, @SaveAsClick, ShortCut(VK_S, [ssModifier, ssShift]));
  AddItem(Group, rsMenuExport, @ExportClick, ShortCut(VK_E, [ssModifier]));
  AddItem(Group, rsMenuQuit, @QuitClick, ShortCut(VK_Q, [ssModifier]));
  Group := AddMenu(rsMenuEdit);
  FUndoItem := AddItem(Group, rsMenuUndo, @UndoClick, ShortCut(VK_Z, [ssModifier]));
  FRedoItem := AddItem(Group, rsMenuRedo, @RedoClick, ShortCut(VK_Z, [ssModifier, ssShift]));
  Group := AddMenu(rsMenuView);
  AddItem(Group, rsMenuFit, @FitClick, ShortCut(VK_0, [ssModifier]));
  AddItem(Group, rsMenuReload, @ReloadClick, ShortCut(VK_R, [ssModifier]));
end;

procedure TPublishForm.PlaceRow(Row: TControl);
begin
  Inc(FNextRowTop, SideRowStep);
  Row.Top := FNextRowTop;
  Row.Align := alTop;
  Row.BorderSpacing.Left := SideGap;
  Row.BorderSpacing.Right := SideGap;
  Row.Parent := FRowParent;
end;

function TPublishForm.AddCheck(const ACaption: string): TCheckBox;
begin
  Result := TCheckBox.Create(Self);
  Result.Caption := ACaption;
  Result.OnChange := @TitleChange;
  PlaceRow(Result);
end;

procedure TPublishForm.BuildNotesTab;
const
  FieldCaptions: array[0..3] of string = (rsFieldPattern, rsFieldMeasurements, rsFieldLayout, rsFieldDate);
var
  Index: integer;
begin
  FTitleBox := AddCheck(rsTitleBlock);
  for Index := 0 to High(FFieldBoxes) do
    FFieldBoxes[Index] := AddCheck(FieldCaptions[Index]);
  FEveryPageBox := AddCheck(rsEveryPage);
  AddLabel(rsCorner);
  FCornerBox := TComboBox.Create(Self);
  PlaceRow(FCornerBox);
  FCornerBox.Style := csDropDownList;
  // In the order of TTitleCorner
  FCornerBox.Items.Add(rsCornerBottomRight);
  FCornerBox.Items.Add(rsCornerBottomLeft);
  FCornerBox.Items.Add(rsCornerTopRight);
  FCornerBox.OnChange := @TitleChange;
  AddButton(rsAddNote, @AddNoteClick);
  AddLabel(rsSheetNote);
  FNoteMemo := TMemo.Create(Self);
  FNoteMemo.Height := NoteMemoHeight;
  FNoteMemo.OnChange := @NoteChange;
  PlaceRow(FNoteMemo);
  AddLabel(rsNoteHelp).WordWrap := True;
  FNoteSizeEdit := AddSpin(rsNoteSize, MaxNoteSize, 1, 0);
  FNoteSizeEdit.MinValue := 1;
  FNoteSizeEdit.OnChange := @NoteChange;
  FDeleteNoteButton := AddButton(rsDeleteNote, @DeleteNoteClick);
end;

procedure TPublishForm.RefreshNotesTab;
var
  Layout: TLayout;
  Index: integer;
  Field: string;
  NoteChosen, Shown: boolean;
begin
  Layout := FDocument.Layout;
  FTitleBox.Checked := Layout.Title.Enabled;
  FEveryPageBox.Checked := Layout.Title.EveryPage;
  FEveryPageBox.Enabled := Layout.Output.Kind = okTiled;
  FCornerBox.ItemIndex := Ord(Layout.Title.Corner);
  FCornerBox.Enabled := Layout.Output.Kind = okTiled;
  for Index := 0 to High(FFieldBoxes) do
  begin
    Shown := False;
    for Field in Layout.Title.Fields do
      Shown := Shown or (Field = TitleFields[Index]);
    FFieldBoxes[Index].Checked := Shown;
    FFieldBoxes[Index].Enabled := Layout.Title.Enabled;
  end;
  NoteChosen := FPreview.SelectedNote >= 0;
  FNoteMemo.Enabled := NoteChosen;
  FNoteSizeEdit.Enabled := NoteChosen;
  FDeleteNoteButton.Enabled := NoteChosen;
  if NoteChosen then
  begin
    if FNoteMemo.Text <> Layout.Notes[FPreview.SelectedNote].Text then
      FNoteMemo.Text := Layout.Notes[FPreview.SelectedNote].Text;
    FNoteSizeEdit.Value := Layout.Notes[FPreview.SelectedNote].Size;
  end
  else
    FNoteMemo.Clear;
end;

procedure TPublishForm.TitleChange(Sender: TObject);
var
  Title: TTitleBlock;
  Index: integer;
begin
  if FRefreshing then
    Exit;
  Title := Default(TTitleBlock);
  Title.Enabled := FTitleBox.Checked;
  Title.EveryPage := FEveryPageBox.Checked;
  Title.Corner := TTitleCorner(FCornerBox.ItemIndex);
  for Index := 0 to High(FFieldBoxes) do
    if FFieldBoxes[Index].Checked then
      Insert(TitleFields[Index], Title.Fields, Length(Title.Fields));
  FDocument.BeginChange(rsChangeTitle);
  FDocument.Layout.Title := Title;
  FDocument.EndChange;
end;

// Typing merges into one undo step, as long as it keeps going
procedure TPublishForm.NoteChange(Sender: TObject);
var
  Index: integer;
begin
  Index := FPreview.SelectedNote;
  if FRefreshing or (Index < 0) then
    Exit;
  FDocument.BeginChange(rsChangeNote);
  FDocument.Layout.Notes[Index].Text := TrimRight(FNoteMemo.Text);
  FDocument.Layout.Notes[Index].Size := FNoteSizeEdit.Value;
  FDocument.EndChange('note:' + IntToStr(Index));
end;

procedure TPublishForm.AddNoteClick(Sender: TObject);
var
  Lowest: double;
  Added: integer;
  Shape: TPlacedPiece;
begin
  Lowest := 0;
  for Shape in FDocument.Layout.PlacedPieces do
    Lowest := Max(Lowest, Shape.Bounds.MaxY + NewNoteGap);
  FDocument.BeginChange(rsAddNoteChange);
  Added := FDocument.Layout.AddNote(rsNewNote, 0, Lowest, NewNoteSize);
  FDocument.EndChange;
  FPreview.SelectedNote := Added;
  FNoteMemo.SetFocus;
  FNoteMemo.SelectAll;
end;

procedure TPublishForm.DeleteNoteClick(Sender: TObject);
begin
  FPreview.RemoveSelected;
end;

function TPublishForm.AddLabel(const ACaption: string): TLabel;
begin
  Result := TLabel.Create(Self);
  Result.Caption := ACaption;
  Result.BorderSpacing.Top := SideGap;
  PlaceRow(Result);
end;

function TPublishForm.AddSpin(const ACaption: string; AMax, AIncrement: double; Decimals: integer): TFloatSpinEdit;
begin
  AddLabel(ACaption);
  Result := TFloatSpinEdit.Create(Self);
  PlaceRow(Result);
  Result.DecimalPlaces := Decimals;
  Result.MinValue := 0;
  Result.MaxValue := AMax;
  Result.Increment := AIncrement;
  Result.OnChange := @SettingChange;
end;

function TPublishForm.AddButton(const ACaption: string; AHandler: TNotifyEvent): TButton;
begin
  Result := TButton.Create(Self);
  Result.Caption := ACaption;
  Result.BorderSpacing.Top := SideGap;
  Result.OnClick := AHandler;
  PlaceRow(Result);
end;

procedure TPublishForm.BuildSide;
var
  PaperName: string;
begin
  AddLabel(rsOutput);
  FKindBox := TComboBox.Create(Self);
  PlaceRow(FKindBox);
  FKindBox.Style := csDropDownList;
  // In the order of TOutputKind
  FKindBox.Items.Add(rsOutputTiled);
  FKindBox.Items.Add(rsOutputLarge);
  FKindBox.Items.Add(rsOutputProjector);
  FKindBox.OnChange := @SettingChange;
  FRollEdit := AddSpin(rsRollWidth, MaxRollWidth, 1, 0);
  AddLabel(rsPaper);
  FPaperBox := TComboBox.Create(Self);
  PlaceRow(FPaperBox);
  FPaperBox.Style := csDropDownList;
  for PaperName in PaperNames do
    FPaperBox.Items.Add(PaperName);
  FPaperBox.OnChange := @SettingChange;
  FMarginEdit := AddSpin(rsMargin, MaxMillimetres, 1, SpinDecimals);
  FOverlapEdit := AddSpin(rsOverlap, MaxMillimetres, 1, SpinDecimals);
  FCalibrationXEdit := AddSpin(rsCalibrationX, MaxCalibration, 0.001, CalibrationDecimals);
  FCalibrationYEdit := AddSpin(rsCalibrationY, MaxCalibration, 0.001, CalibrationDecimals);
  AddButton(rsExportPDF, @ExportClick);
end;

procedure TPublishForm.BuildPiecesTab;
begin
  FTurnButton := AddButton(rsTurn, @TurnClick);
  FFlipButton := AddButton(rsFlip, @FlipClick);
  FRemoveButton := AddButton(rsRemove, @RemoveClick);
  AddButton(rsPlaceNew, @PlaceClick);
  AddLabel(rsTray);
  FTray := TListBox.Create(Self);
  FTray.Parent := FPiecesSide;
  FTray.Align := alClient;
  FTray.BorderSpacing.Around := SideGap;
  FTray.OnMouseDown := @TrayMouseDown;
  FTray.OnDblClick := @TrayDoubleClick;
end;

procedure TPublishForm.ShowStatus(const AText: string);
begin
  FStatus.SimpleText := AText;
end;

procedure TPublishForm.DocumentChanged(Sender: TObject);
begin
  FPreview.Refresh;
  RefreshControls;
end;

procedure TPublishForm.SelectionChanged(Sender: TObject);
begin
  RefreshControls;
end;

// Only saved files are seen; unsaved edits in the drafting app stay there
procedure TPublishForm.WatchTick(Sender: TObject);
var
  Names: string;
begin
  Names := FDocument.CheckSources;
  if Names <> '' then
    ShowStatus(Format(rsReloaded, [Names]));
end;

// Rebuilt only when it differs, so a drag from it survives other changes
procedure TPublishForm.RefreshTray;
var
  Lines: TStringList;
  Item: TUnplacedCopy;
begin
  FTrayCopies := FDocument.Layout.Unplaced;
  Lines := TStringList.Create;
  try
    for Item in FTrayCopies do
      Lines.Add(Item.Caption);
    if Lines.Count = 0 then
      Lines.Add(rsTrayEmpty);
    if not FTray.Items.Equals(Lines) then
      FTray.Items.Assign(Lines);
  finally
    FreeAndNil(Lines);
  end;
end;

procedure TPublishForm.TrayMouseDown(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: integer);
var
  Index: integer;
begin
  Index := FTray.ItemAtPos(Point(X, Y), True);
  if (Button = mbLeft) and (Index >= 0) and (Index <= High(FTrayCopies)) then
    FTray.BeginDrag(False);
end;

procedure TPublishForm.TrayDoubleClick(Sender: TObject);
var
  Index: integer;
  Copies: TUnplacedCopyArray;
begin
  Index := FTray.ItemIndex;
  if (Index < 0) or (Index > High(FTrayCopies)) then
    Exit;
  if not FTrayCopies[Index].CanPlace then
  begin
    ShowStatus(rsCannotPlace);
    Exit;
  end;
  Copies := Copy(FTrayCopies, Index, 1);
  FDocument.BeginChange(rsPlaceOne);
  FDocument.Layout.PlaceCopies(Copies);
  FDocument.EndChange;
end;

procedure TPublishForm.PreviewDragOver(Sender, Source: TObject; X, Y: integer; State: TDragState; var Accept: boolean);
begin
  Accept := (Source = FTray) and (FTray.ItemIndex >= 0) and (FTray.ItemIndex <= High(FTrayCopies));
end;

procedure TPublishForm.PreviewDragDrop(Sender, Source: TObject; X, Y: integer);
var
  Item: TUnplacedCopy;
  Placed: integer;
begin
  Item := FTrayCopies[FTray.ItemIndex];
  if not Item.CanPlace then
  begin
    ShowStatus(rsCannotPlace);
    Exit;
  end;
  FDocument.BeginChange(rsPlaceOne);
  Placed := FDocument.Layout.PlaceCopyAt(Item, FPreview.LayoutAt(X, Y), PlacementStep);
  FDocument.EndChange;
  FPreview.Selected := Placed;
end;

procedure TPublishForm.RemoveClick(Sender: TObject);
begin
  FPreview.RemoveSelected;
end;

procedure TPublishForm.RefreshProblems;
var
  Problem: TLayoutProblem;
begin
  FProblems.Items.BeginUpdate;
  try
    FProblems.Items.Clear;
    for Problem in FDocument.Layout.Problems do
      if not Problem.Unplaced then
        FProblems.Items.Add(Problem.Text);
    if FProblems.Items.Count = 0 then
      FProblems.Items.Add(rsNoProblems);
  finally
    FProblems.Items.EndUpdate;
  end;
end;

procedure TPublishForm.RefreshControls;
const
  ModifiedMark: array[boolean] of string = ('', '*');
var
  Layout: TLayout;
  Pages: TTilePageArray;
  Page: TTilePage;
  Rows, Columns, Blank, LeftOut: integer;
begin
  FRefreshing := True;
  try
    Layout := FDocument.Layout;
    FKindBox.ItemIndex := Ord(Layout.Output.Kind);
    FRollEdit.Value := Layout.Output.RollWidth;
    FRollEdit.Enabled := Layout.Output.Kind = okLarge;
    FPaperBox.Enabled := Layout.Output.Kind = okTiled;
    FOverlapEdit.Enabled := Layout.Output.Kind = okTiled;
    FPaperBox.ItemIndex := FPaperBox.Items.IndexOf(Layout.Output.Paper);
    FMarginEdit.Value := Layout.Output.Tiles.Margin;
    FOverlapEdit.Value := Layout.Output.Tiles.Overlap;
    FCalibrationXEdit.Value := Layout.Output.CalibrationX;
    FCalibrationYEdit.Value := Layout.Output.CalibrationY;
    RefreshNotesTab;
  finally
    FRefreshing := False;
  end;
  FTurnButton.Enabled := FPreview.Selected >= 0;
  FFlipButton.Enabled := FPreview.Selected >= 0;
  FRemoveButton.Enabled := FPreview.Selected >= 0;
  FUndoItem.Enabled := FDocument.CanUndo;
  if FDocument.CanUndo then
    FUndoItem.Caption := Format(rsMenuUndoNamed, [FDocument.UndoDescription])
  else
    FUndoItem.Caption := rsMenuUndo;
  FRedoItem.Enabled := FDocument.CanRedo;
  if Layout.FileName <> '' then
    Caption := Format(rsPublishTitleFile, [ExtractFileName(Layout.FileName), ModifiedMark[FDocument.Modified]])
  else
    Caption := rsPublishTitle;
  RefreshProblems;
  RefreshTray;
  Pages := Layout.Pages(Layout.PlacedPieces, Rows, Columns);
  if Layout.Output.Kind <> okTiled then
  begin
    ShowStatus(Format(rsLargeSheet, [FormatFloat('0', OneSheetWidth(Layout, Pages[0].Area.MaxX)),
      FormatFloat('0', LargeSheetLength(Layout, Pages[0].Area.MaxY))]));
    Exit;
  end;
  Blank := 0;
  LeftOut := 0;
  for Page in Pages do
    if Page.Blank then
      Inc(Blank)
    else if Page.Excluded then
      Inc(LeftOut);
  ShowStatus(Format(rsPages, [Length(Pages), Blank, LeftOut]));
end;

// A run of spin clicks is one undo step. A paper that leaves no room to
// print is put back.
procedure TPublishForm.SettingChange(Sender: TObject);
var
  Output, Before: TLayoutOutput;
begin
  if FRefreshing or (FPaperBox.ItemIndex < 0) then
    Exit;
  Output := FDocument.Layout.Output;
  Before := Output;
  Output.Kind := TOutputKind(FKindBox.ItemIndex);
  Output.RollWidth := FRollEdit.Value;
  Output.Paper := FPaperBox.Text;
  PaperSize(Output.Paper, Output.Tiles.PaperWidth, Output.Tiles.PaperHeight);
  Output.Tiles.Margin := FMarginEdit.Value;
  Output.Tiles.Overlap := FOverlapEdit.Value;
  Output.CalibrationX := FCalibrationXEdit.Value;
  Output.CalibrationY := FCalibrationYEdit.Value;
  // Page names mean other sheets once the grid moves
  if (Output.Paper <> Before.Paper) or (Output.Tiles.Margin <> Before.Tiles.Margin) or (Output.Tiles.Overlap <> Before.Tiles.Overlap) or
    (Output.Kind <> Before.Kind) then
    Output.ExcludedPages := nil;
  if not TilesAreUsable(Output.Tiles) or (Output.RollWidth <= 2 * Output.Tiles.Margin) or (Output.CalibrationX <= 0) or
    (Output.CalibrationY <= 0) then
  begin
    ShowStatus(rsLayoutNoPrintArea);
    RefreshControls;
    Exit;
  end;
  FDocument.BeginChange(rsChangeSettings);
  FDocument.Layout.Output := Output;
  FDocument.EndChange('paper');
  FPreview.ZoomToFit;
end;

procedure TPublishForm.OpenPath(const Path: string);
var
  Reason: string;
begin
  if ExtractFileExt(Path) = PatternExtension then
    FDocument.NewForPattern(Path)
  else if not FDocument.Open(Path, Reason) then
  begin
    ShowStatus(Reason);
    Exit;
  end;
  FPreview.Selected := -1;
  FPreview.ZoomToFit;
end;

function TPublishForm.ConfirmDiscard: boolean;
begin
  Result := not FDocument.Modified or (MessageDlg(rsDiscardQuestion, mtConfirmation, [mbYes, mbNo], 0) = mrYes);
end;

procedure TPublishForm.CloseAsked(Sender: TObject; var CanClose: boolean);
begin
  CanClose := ConfirmDiscard;
end;

procedure TPublishForm.OpenClick(Sender: TObject);
var
  Dialog: TOpenDialog;
begin
  if not ConfirmDiscard then
    Exit;
  Dialog := TOpenDialog.Create(Self);
  try
    Dialog.Filter := rsFilterOpen;
    if Dialog.Execute then
      OpenPath(Dialog.FileName);
  finally
    FreeAndNil(Dialog);
  end;
end;

procedure TPublishForm.SaveClick(Sender: TObject);
var
  Reason: string;
begin
  if FDocument.Layout.FileName = '' then
    SaveAsClick(Sender)
  else if not FDocument.Save(FDocument.Layout.FileName, Reason) then
    ShowStatus(Reason);
end;

procedure TPublishForm.SaveAsClick(Sender: TObject);
var
  Dialog: TSaveDialog;
  Reason: string;
begin
  Dialog := TSaveDialog.Create(Self);
  try
    Dialog.Filter := rsFilterLayout;
    Dialog.DefaultExt := LayoutExtension;
    Dialog.FileName := FDocument.Layout.FileName;
    if Dialog.Execute and not FDocument.Save(Dialog.FileName, Reason) then
      ShowStatus(Reason);
  finally
    FreeAndNil(Dialog);
  end;
end;

procedure TPublishForm.ExportClick(Sender: TObject);
var
  Dialog: TSaveDialog;
  Reason: string;
begin
  Dialog := TSaveDialog.Create(Self);
  try
    Dialog.Filter := rsFilterPDF;
    Dialog.DefaultExt := '.pdf';
    Dialog.FileName := ChangeFileExt(FDocument.Layout.FileName, '.pdf');
    if not Dialog.Execute then
      Exit;
    if ExportLayoutPDF(FDocument.Layout, Dialog.FileName, Reason) then
      ShowStatus(Format(rsExported, [Dialog.FileName]))
    else
      MessageDlg(Reason, mtError, [mbOK], 0);
  finally
    FreeAndNil(Dialog);
  end;
end;

procedure TPublishForm.QuitClick(Sender: TObject);
begin
  Close;
end;

procedure TPublishForm.UndoClick(Sender: TObject);
begin
  FDocument.Undo;
end;

procedure TPublishForm.RedoClick(Sender: TObject);
begin
  FDocument.Redo;
end;

procedure TPublishForm.FitClick(Sender: TObject);
begin
  FPreview.ZoomToFit;
end;

procedure TPublishForm.ReloadClick(Sender: TObject);
begin
  FDocument.Reload;
end;

procedure TPublishForm.PlaceClick(Sender: TObject);
begin
  FDocument.BeginChange(rsPlaceChange);
  FDocument.Layout.PlaceNewPieces;
  FDocument.EndChange;
end;

procedure TPublishForm.TurnClick(Sender: TObject);
var
  Index: integer;
begin
  Index := FPreview.Selected;
  if Index < 0 then
    Exit;
  FDocument.BeginChange(rsTurnChange);
  FDocument.Layout.Placements[Index].Rotation := (FDocument.Layout.Placements[Index].Rotation + 90) mod 360;
  FDocument.EndChange;
end;

procedure TPublishForm.FlipClick(Sender: TObject);
var
  Index: integer;
begin
  Index := FPreview.Selected;
  if Index < 0 then
    Exit;
  FDocument.BeginChange(rsFlipChange);
  FDocument.Layout.Placements[Index].Flipped := not FDocument.Layout.Placements[Index].Flipped;
  FDocument.EndChange;
end;

end.
