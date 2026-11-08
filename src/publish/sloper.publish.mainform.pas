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
  Classes, SysUtils, Forms, Controls, StdCtrls, ExtCtrls, ComCtrls, Menus, Spin, Dialogs, ActnList, Sloper.Core.TextFields, Sloper.Core.Note,
  Sloper.Output.Layout, Sloper.Output.LayoutDocument,
  Sloper.Publish.PreviewCanvas, Sloper.UI.Commands, Sloper.Core.Shortcuts, Sloper.UI.RecentMenu;

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
    FFieldBoxes: array[0..5] of TCheckBox;
    FCornerBox: TComboBox;
    FNoteMemo: TMemo;
    FNoteSizeEdit: TFloatSpinEdit;
    FNoteAlignBox: TComboBox;
    FNoteBoxCheck: TCheckBox;
    FDeleteNoteButton: TButton;
    FStatus: TStatusBar;
    FPatternsSide: TWinControl;
    FOutputScroll: TScrollBox;
    FKindBox, FPaperBox, FMarksBox, FFillBox, FProfileBox, FOutputProfileBox, FMaterialBox, FSizeBox: TComboBox;
    FAllowTurnsBox: TCheckBox;
    FSourceBox: TListBox;
    FSourceSetLabel: TLabel;
    FRemoveSourceButton, FChooseSetButton, FPatternSetButton: TButton;
    FPaperWidthEdit, FPaperHeightEdit, FRollEdit, FMaterialWidthEdit, FMaterialLengthEdit, FMarginEdit,
    FOverlapEdit: TFloatSpinEdit;
    FTray, FProblems: TListBox;
    // What each tray line stands for
    FTrayCopies: TUnplacedCopyArray;
    FTurnButton, FFlipButton, FRemoveButton, FPackButton: TButton;
    FCommands: TCommandSet;
    FUndoAction, FRedoAction: TAction;
    FRecent: TRecentMenu;
    FWatch: TTimer;
    FRefreshing: boolean;
    // Rows stack in the order their Top says, so each takes the next one
    FNextRowTop: integer;
    // Where FRowParent goes back to when the open group ends
    FGroupOuter: TWinControl;
    function ScrollingRows(Side: TWinControl): TScrollBox;
    procedure PlaceRow(Row: TControl);
    procedure BeginGroup(const ACaption: string);
    procedure EndGroup;
    procedure BuildMenu;
    procedure BuildPiecesTab;
    procedure BuildPatternsTab;
    function CurrentSource: TLayoutSource;
    procedure RefreshPatternsTab;
    procedure RefreshProfiles;
    procedure RefreshMaterials;
    procedure AddSourceClick(Sender: TObject);
    procedure RemoveSourceClick(Sender: TObject);
    procedure ChooseSetClick(Sender: TObject);
    procedure PatternSetClick(Sender: TObject);
    procedure SourceSelected(Sender: TObject);
    procedure SizeChange(Sender: TObject);
    procedure ChangeSource(const Description, AMeasurementFile, ASize: string);
    procedure BuildSide;
    function AddSpin(const ACaption: string; AMax, AIncrement: double; Decimals: integer): TFloatSpinEdit;
    function AddLabel(const ACaption: string): TLabel;
    function AddButton(const ACaption: string; AHandler: TNotifyEvent): TButton;
    procedure DocumentChanged(Sender: TObject);
    procedure SelectionChanged(Sender: TObject);
    procedure RefreshControls;
    procedure PreferencesClick(Sender: TObject);
    procedure AboutClick(Sender: TObject);
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
    procedure PaperEditExit(Sender: TObject);
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
    procedure PackClick(Sender: TObject);
    procedure FlipClick(Sender: TObject);
    procedure CloseAsked(Sender: TObject; var CanClose: boolean);
    function ConfirmDiscard: boolean;
    procedure OpenPath(const Path: string);
    procedure RecentOpen(Sender: TObject; const FileName: string);
    procedure SaveLayout(const FileName: string);
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
  rsMenuExportSVG = 'Export S&VG...';
  rsMenuExportDXF = 'Export &DXF...';
  rsMenuExportMachineDXF = 'Export &Machine DXF...';
  rsMenuQuit = '&Quit';
  rsMenuEdit = '&Edit';
  rsMenuUndo = '&Undo';
  rsMenuUndoNamed = '&Undo %s';
  rsMenuRedo = '&Redo';
  rsMenuPreferences = 'Pre&ferences...';
  rsMenuHelp = '&Help';
  rsMenuAbout = '&About %s';
  rsAboutSummary = 'Pattern layouts and printing.';
  rsMenuView = '&View';
  rsMenuFit = '&Fit Pages';
  rsMenuReload = '&Reload Patterns';
  rsOutput = 'Output';
  rsOutputTiled = 'Tiled pages';
  rsOutputLarge = 'Large format';
  rsOutputProjector = 'Projector';
  rsOutputMaterial = 'Material sheet';
  rsMaterialWidth = 'Material width (mm)';
  rsMaterialLength = 'Material length (mm), 0 for a roll';
  rsAllowTurns = 'Allow quarter turns (no grain)';
  rsMaterialLimit = 'Material';
  rsMaterialAll = 'All materials';
  rsRollWidth = 'Roll width (mm)';
  rsPaper = 'Paper';
  rsMargin = 'Margin (mm)';
  rsOverlap = 'Overlap (mm)';
  rsTray = 'Unplaced: drag onto the pages';
  rsTrayGroup = 'Tray';
  rsSelectedPiece = 'Selected Piece';
  rsArrange = 'Arrange';
  rsContent = 'Content';
  rsExportGroup = 'Export';
  rsProblemsGroup = 'Problems';
  rsSheetNotes = 'Sheet Notes';
  rsTrayEmpty = 'Every piece is placed';
  rsTrayNoPieces = 'No pieces to place';
  rsRemove = 'Back to tray';
  rsTabPieces = 'Pieces';
  rsTabOutput = 'Output';
  rsTabPatterns = 'Patterns';
  rsPatternsLabel = 'Patterns in This Layout';
  rsAddPattern = 'Add pattern...';
  rsRemovePattern = 'Remove pattern';
  rsSourceSet = 'Measurements';
  rsChooseSet = 'Choose measurements...';
  rsPatternSet = 'Use the pattern''s own';
  rsSourceSize = 'Size';
  rsNoSet = 'None';
  rsAddPatternChange = 'Add pattern';
  rsRemovePatternChange = 'Remove pattern';
  rsSetChange = 'Change measurements';
  rsSizeChange = 'Change size';
  rsSourceAdded = '%d new copies in the tray';
  rsFilterMeasurements = 'Measurements (*.slm)|*.slm';
  rsMarks = 'Alignment marks';
  rsMarksDiamond = 'Diamonds';
  rsMarksNone = 'None';
  rsMarksHalfCircle = 'Half circles';
  rsFill = 'Piece fill';
  rsFillNone = 'None';
  rsFillTint = 'Light tint';
  rsFillHatch = 'Hatching';
  rsPaperCustom = 'Custom';
  rsPaperWidth = 'Paper width (mm)';
  rsPaperHeight = 'Paper height (mm)';
  rsTabNotes = 'Notes';
  rsTitleBlock = 'Title Block';
  rsShowTitleBlock = 'Show the title block';
  rsEveryPage = 'On every page';
  rsCorner = 'Corner';
  rsCornerBottomRight = 'Bottom right';
  rsCornerBottomLeft = 'Bottom left';
  rsCornerTopRight = 'Top right';
  rsFieldPattern = 'Pattern';
  rsFieldMeasurements = 'Measurements';
  rsFieldLayout = 'Layout name';
  rsFieldCutList = 'Cut list';
  rsFieldMaterials = 'Materials';
  rsFieldDate = 'Date';
  rsSheetNote = 'Sheet note';
  rsNoteSize = 'Text size (pt)';
  rsNoteAlign = 'Lines';
  rsNoteAlignLeft = 'Left';
  rsNoteAlignCentre = 'Centred';
  rsNoteAlignRight = 'Right';
  rsNoteBox = 'On a white box';
  rsAddNote = 'Add note';
  rsDeleteNote = 'Delete note';
  rsNoteHelp = 'Fields: {pattern.name} {measurements.name} {date} {page} {pages} {cutlist} {materials}';
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
  rsExportSVG = 'Export SVG...';
  rsExportDXF = 'Export DXF...';
  rsExportMachineDXF = 'Export Machine DXF...';
  rsProfile = 'Machine profile';
  rsProfileNone = 'None';
  rsOutputProfile = 'Output profile';
  rsOutputProfileAll = 'Everything';
  rsPackPieces = 'Pack pieces';
  rsPackChange = 'Pack pieces';
  rsPackedPages = 'Packed %d copies on %d pages';
  rsPacked = 'Packed %d copies';
  rsPackLeftOut = '%s; %d too wide for the roll stayed where they were';
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
  rsFilterPattern = 'Patterns (*.sloper)|*.sloper';
  rsFilterPDF = 'PDF (*.pdf)|*.pdf';
  rsFilterSVG = 'SVG (*.svg)|*.svg';
  rsFilterDXF = 'DXF-AAMA (*.dxf)|*.dxf';
  rsFilterMachineDXF = 'Machine DXF (*.dxf)|*.dxf';

implementation

uses
  LCLType, Math, Sloper.Core.Geometry, Sloper.Core.MachineProfiles, Sloper.Core.OutputProfiles, Sloper.Core.RecentFiles, Sloper.Core.Settings, Sloper.UI.IconSet,
  Sloper.UI.About, Sloper.UI.Preferences, Sloper.Output.LayoutExport,
  Sloper.Output.LayoutPDF, Sloper.Output.Packing, Sloper.Output.Preview, Sloper.Output.Tiling;

const
  SideWidth = 340;
  NewNoteSize = 12;
  NewNoteGap = 10;
  MaxNoteSize = 200;
  NoteMemoHeight = 110;
  // In the order of FFieldBoxes
  TitleFields: array[0..5] of string = (FieldPatternName, FieldMeasurementsName, FieldLayoutName, FieldDate, FieldCutList, FieldMaterials);
  SideGap = 6;
  SideRowStep = 100;
  ProblemsHeight = 110;
  WatchMilliseconds = 1000;
  SpinDecimals = 1;
  MaxMillimetres = 100;
  MaxRollWidth = 2000;
  PatternExtension = '.sloper';
  // The last is the size typed in
  PaperNames: array[0..3] of string = ('A4', 'A3', 'Letter', CustomPaper);
  PatternListHeight = 120;
  MaxPaperSide = 2000;

constructor TPublishForm.Create(AOwner: TComponent);
var
  ProblemsGroup: TGroupBox;
begin
  inherited CreateNew(AOwner);
  Caption := rsPublishTitle;
  Width := 1100;
  Height := 750;
  Position := poScreenCenter;
  OnCloseQuery := @CloseAsked;
  FDocument := TLayoutDocument.Create;
  FDocument.Layout.MachineProfiles := UserMachineProfiles;
  FDocument.Layout.OutputProfiles := UserOutputProfiles;
  FDocument.Layout.Calibration := UserCalibration;
  FDocument.OnChange := @DocumentChanged;
  BuildMenu;
  FStatus := TStatusBar.Create(Self);
  FStatus.Parent := Self;
  FColumn := TPanel.Create(Self);
  FColumn.Parent := Self;
  FColumn.Align := alRight;
  FColumn.Width := SideWidth;
  FColumn.BevelOuter := bvNone;
  ProblemsGroup := TGroupBox.Create(Self);
  ProblemsGroup.Parent := FColumn;
  ProblemsGroup.Align := alBottom;
  ProblemsGroup.AutoSize := True;
  ProblemsGroup.BorderSpacing.Around := SideGap;
  ProblemsGroup.Caption := rsProblemsGroup;
  FProblems := TListBox.Create(Self);
  FProblems.Parent := ProblemsGroup;
  FProblems.Align := alTop;
  FProblems.Height := ProblemsHeight;
  FProblems.ShowHint := True;
  FProblems.BorderSpacing.Around := SideGap;
  FTabs := TPageControl.Create(Self);
  FTabs.Parent := FColumn;
  FTabs.Align := alClient;
  FPiecesSide := FTabs.AddTabSheet;
  TTabSheet(FPiecesSide).Caption := rsTabPieces;
  FPatternsSide := FTabs.AddTabSheet;
  TTabSheet(FPatternsSide).Caption := rsTabPatterns;
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
  FRowParent := FPatternsSide;
  BuildPatternsTab;
  FOutputScroll := ScrollingRows(FSide);
  FRowParent := FOutputScroll;
  BuildSide;
  FRowParent := ScrollingRows(FNotesSide);
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

var
  Group, OpenItem: TMenuItem;
  OpenAction, SaveAction, FitAction, ReloadAction: TAction;
  ExportActions: array[TExportFormat] of TAction;
  ExportFormat: TExportFormat;
begin
  Bar := TMainMenu.Create(Self);
  Menu := Bar;
  FCommands := TCommandSet.Create(Self, Bar);
  OpenAction := FCommands.NewAction(rsMenuOpen, aiOpen, @OpenClick, CommandShortCut(kcOpen));
  SaveAction := FCommands.NewAction(rsMenuSave, aiSave, @SaveClick, CommandShortCut(kcSave));
  ExportActions[efPDF] := FCommands.NewAction(rsMenuExport, aiExportPDF, @ExportClick, CommandShortCut(kcExportPDF), Ord(efPDF));
  ExportActions[efSVG] := FCommands.NewAction(rsMenuExportSVG, aiExportSVG, @ExportClick, 0, Ord(efSVG));
  ExportActions[efDXF] := FCommands.NewAction(rsMenuExportDXF, aiExportDXF, @ExportClick, 0, Ord(efDXF));
  ExportActions[efMachineDXF] := FCommands.NewAction(rsMenuExportMachineDXF, aiExportMachineDXF, @ExportClick, 0, Ord(efMachineDXF));
  FUndoAction := FCommands.NewAction(rsMenuUndo, aiUndo, @UndoClick, CommandShortCut(kcUndo));
  FRedoAction := FCommands.NewAction(rsMenuRedo, aiRedo, @RedoClick, CommandShortCut(kcRedo));
  FitAction := FCommands.NewAction(rsMenuFit, aiFit, @FitClick, CommandShortCut(kcFit));
  ReloadAction := FCommands.NewAction(rsMenuReload, aiReload, @ReloadClick, CommandShortCut(kcReload));

  Group := AddMenu(rsMenuFile);
  OpenItem := FCommands.AddMenuItem(Group, OpenAction);
  FRecent := TRecentMenu.Create(Self, Group, OpenItem, rlLayouts, @RecentOpen);
  FCommands.AddMenuItem(Group, SaveAction);
  FCommands.AddMenuItem(Group, FCommands.NewAction(rsMenuSaveAs, aiSaveAs, @SaveAsClick, CommandShortCut(kcSaveAs)));
  Group.AddSeparator;
  for ExportFormat := Low(TExportFormat) to High(TExportFormat) do
    FCommands.AddMenuItem(Group, ExportActions[ExportFormat]);
  Group.AddSeparator;
  FCommands.AddMenuItem(Group, FCommands.NewAction(rsMenuQuit, aiQuit, @QuitClick, CommandShortCut(kcQuit)));
  Group := AddMenu(rsMenuEdit);
  FCommands.AddMenuItem(Group, FUndoAction);
  FCommands.AddMenuItem(Group, FRedoAction);
  Group.AddSeparator;
  FCommands.AddMenuItem(Group, FCommands.NewAction(rsMenuPreferences, aiPreferences, @PreferencesClick, CommandShortCut(kcPreferences)));
  Group := AddMenu(rsMenuView);
  FCommands.AddMenuItem(Group, FitAction);
  FCommands.AddMenuItem(Group, ReloadAction);
  Group := AddMenu(rsMenuHelp);
  FCommands.AddMenuItem(Group, FCommands.NewAction(Format(rsMenuAbout, [rsPublishTitle]), aiAbout, @AboutClick));

  FCommands.AddButton(OpenAction);
  FCommands.AddButton(SaveAction);
  FCommands.AddDivider;
  FCommands.AddButton(FUndoAction);
  FCommands.AddButton(FRedoAction);
  FCommands.AddDivider;
  FCommands.AddButton(FitAction);
  FCommands.AddButton(ReloadAction);
  FCommands.AddDivider;
  for ExportFormat := Low(TExportFormat) to High(TExportFormat) do
    FCommands.AddButton(ExportActions[ExportFormat]);
end;

// For a tab with more rows than a small window has room for
function TPublishForm.ScrollingRows(Side: TWinControl): TScrollBox;
begin
  Result := TScrollBox.Create(Self);
  Result.Parent := Side;
  Result.Align := alClient;
  Result.BorderStyle := bsNone;
  Result.HorzScrollBar.Visible := False;
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

// The rows placed after this go in a captioned box, until the next group or
// EndGroup
procedure TPublishForm.BeginGroup(const ACaption: string);
var
  Group: TGroupBox;
begin
  EndGroup;
  Group := TGroupBox.Create(Self);
  Group.Caption := ACaption;
  Group.AutoSize := True;
  PlaceRow(Group);
  Group.BorderSpacing.Top := SideGap;
  Group.ChildSizing.TopBottomSpacing := SideGap div 2;
  FGroupOuter := FRowParent;
  FRowParent := Group;
end;

procedure TPublishForm.EndGroup;
begin
  if Assigned(FGroupOuter) then
    FRowParent := FGroupOuter;
  FGroupOuter := nil;
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
  FieldCaptions: array[0..5] of string = (rsFieldPattern, rsFieldMeasurements, rsFieldLayout, rsFieldDate, rsFieldCutList, rsFieldMaterials);
var
  Index: integer;
begin
  BeginGroup(rsTitleBlock);
  FTitleBox := AddCheck(rsShowTitleBlock);
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
  BeginGroup(rsSheetNotes);
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
  AddLabel(rsNoteAlign);
  FNoteAlignBox := TComboBox.Create(Self);
  PlaceRow(FNoteAlignBox);
  FNoteAlignBox.Style := csDropDownList;
  // In the order of TTextAlign
  FNoteAlignBox.Items.Add(rsNoteAlignLeft);
  FNoteAlignBox.Items.Add(rsNoteAlignCentre);
  FNoteAlignBox.Items.Add(rsNoteAlignRight);
  FNoteAlignBox.OnChange := @NoteChange;
  FNoteBoxCheck := AddCheck(rsNoteBox);
  FNoteBoxCheck.OnChange := @NoteChange;
  FDeleteNoteButton := AddButton(rsDeleteNote, @DeleteNoteClick);
  EndGroup;
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
  FNoteAlignBox.Enabled := NoteChosen;
  FNoteBoxCheck.Enabled := NoteChosen;
  FDeleteNoteButton.Enabled := NoteChosen;
  if NoteChosen then
  begin
    if FNoteMemo.Text <> Layout.Notes[FPreview.SelectedNote].Text then
      FNoteMemo.Text := Layout.Notes[FPreview.SelectedNote].Text;
    FNoteSizeEdit.Value := Layout.Notes[FPreview.SelectedNote].Size;
    FNoteAlignBox.ItemIndex := Ord(Layout.Notes[FPreview.SelectedNote].Align);
    FNoteBoxCheck.Checked := Layout.Notes[FPreview.SelectedNote].Boxed;
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
  if FNoteAlignBox.ItemIndex >= 0 then
    FDocument.Layout.Notes[Index].Align := TTextAlign(FNoteAlignBox.ItemIndex);
  FDocument.Layout.Notes[Index].Boxed := FNoteBoxCheck.Checked;
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
  Index: integer;

  function AddChoice(const ACaption: string): TComboBox;
  begin
    AddLabel(ACaption);
    Result := TComboBox.Create(Self);
    PlaceRow(Result);
    Result.Style := csDropDownList;
    Result.OnChange := @SettingChange;
  end;

begin
  BeginGroup(rsOutput);
  FKindBox := TComboBox.Create(Self);
  PlaceRow(FKindBox);
  FKindBox.Style := csDropDownList;
  // In the order of TOutputKind
  FKindBox.Items.Add(rsOutputTiled);
  FKindBox.Items.Add(rsOutputLarge);
  FKindBox.Items.Add(rsOutputProjector);
  FKindBox.Items.Add(rsOutputMaterial);
  FKindBox.OnChange := @SettingChange;
  FRollEdit := AddSpin(rsRollWidth, MaxRollWidth, 1, 0);
  FMaterialWidthEdit := AddSpin(rsMaterialWidth, MaxRollWidth, 1, 0);
  FMaterialLengthEdit := AddSpin(rsMaterialLength, MaxRollWidth, 1, 0);
  FAllowTurnsBox := TCheckBox.Create(Self);
  FAllowTurnsBox.Caption := rsAllowTurns;
  PlaceRow(FAllowTurnsBox);
  FAllowTurnsBox.OnClick := @SettingChange;
  BeginGroup(rsPaper);
  FPaperBox := TComboBox.Create(Self);
  PlaceRow(FPaperBox);
  FPaperBox.Style := csDropDownList;
  for Index := 0 to High(PaperNames) - 1 do
    FPaperBox.Items.Add(PaperNames[Index]);
  FPaperBox.Items.Add(rsPaperCustom);
  FPaperBox.OnChange := @SettingChange;
  FPaperWidthEdit := AddSpin(rsPaperWidth, MaxPaperSide, 1, SpinDecimals);
  FPaperHeightEdit := AddSpin(rsPaperHeight, MaxPaperSide, 1, SpinDecimals);
  FPaperWidthEdit.OnExit := @PaperEditExit;
  FPaperHeightEdit.OnExit := @PaperEditExit;
  FMarginEdit := AddSpin(rsMargin, MaxMillimetres, 1, SpinDecimals);
  FOverlapEdit := AddSpin(rsOverlap, MaxMillimetres, 1, SpinDecimals);
  FMarksBox := AddChoice(rsMarks);
  // In the order of TLayoutMarks
  FMarksBox.Items.Add(rsMarksDiamond);
  FMarksBox.Items.Add(rsMarksNone);
  FMarksBox.Items.Add(rsMarksHalfCircle);
  BeginGroup(rsContent);
  FFillBox := AddChoice(rsFill);
  // In the order of TLayoutFill
  FFillBox.Items.Add(rsFillNone);
  FFillBox.Items.Add(rsFillTint);
  FFillBox.Items.Add(rsFillHatch);
  FOutputProfileBox := AddChoice(rsOutputProfile);
  FProfileBox := AddChoice(rsProfile);
  FMaterialBox := AddChoice(rsMaterialLimit);
  BeginGroup(rsExportGroup);
  AddButton(rsExportPDF, @ExportClick).Tag := Ord(efPDF);
  AddButton(rsExportSVG, @ExportClick).Tag := Ord(efSVG);
  AddButton(rsExportDXF, @ExportClick).Tag := Ord(efDXF);
  AddButton(rsExportMachineDXF, @ExportClick).Tag := Ord(efMachineDXF);
  EndGroup;
end;

procedure TPublishForm.BuildPatternsTab;
begin
  BeginGroup(rsPatternsLabel);
  FSourceBox := TListBox.Create(Self);
  PlaceRow(FSourceBox);
  FSourceBox.Height := PatternListHeight;
  FSourceBox.OnClick := @SourceSelected;
  AddButton(rsAddPattern, @AddSourceClick);
  FRemoveSourceButton := AddButton(rsRemovePattern, @RemoveSourceClick);
  BeginGroup(rsSourceSet);
  FSourceSetLabel := AddLabel('');
  FChooseSetButton := AddButton(rsChooseSet, @ChooseSetClick);
  FPatternSetButton := AddButton(rsPatternSet, @PatternSetClick);
  AddLabel(rsSourceSize);
  FSizeBox := TComboBox.Create(Self);
  PlaceRow(FSizeBox);
  FSizeBox.Style := csDropDownList;
  FSizeBox.OnChange := @SizeChange;
  EndGroup;
end;

function TPublishForm.CurrentSource: TLayoutSource;
begin
  Result := nil;
  if (FSourceBox.ItemIndex >= 0) and (FSourceBox.ItemIndex < FDocument.Layout.Sources.Count) then
    Result := FDocument.Layout.Sources[FSourceBox.ItemIndex];
end;

// A name this user does not have stays listed, so opening a layout from
// another computer does not change it
procedure TPublishForm.RefreshProfiles;
var
  Profile: TMachineProfile;
  Output: TOutputProfile;
  Layout: TLayout;
begin
  Layout := FDocument.Layout;
  FProfileBox.Items.Clear;
  FProfileBox.Items.Add(rsProfileNone);
  FProfileBox.Items.Add(StandardProfileName);
  for Profile in Layout.MachineProfiles do
    if FProfileBox.Items.IndexOf(Profile.Name) < 0 then
      FProfileBox.Items.Add(Profile.Name);
  if (Layout.Output.Profile <> '') and (FProfileBox.Items.IndexOf(Layout.Output.Profile) < 0) then
    FProfileBox.Items.Add(Layout.Output.Profile);
  FProfileBox.ItemIndex := 0;
  if Layout.Output.Profile <> '' then
    FProfileBox.ItemIndex := FProfileBox.Items.IndexOf(Layout.Output.Profile);
  FOutputProfileBox.Items.Clear;
  FOutputProfileBox.Items.Add(rsOutputProfileAll);
  for Output in AllOutputProfiles(Layout.OutputProfiles) do
    FOutputProfileBox.Items.Add(Output.Name);
  if (Layout.Output.OutputProfile <> '') and (FOutputProfileBox.Items.IndexOf(Layout.Output.OutputProfile) < 0) then
    FOutputProfileBox.Items.Add(Layout.Output.OutputProfile);
  FOutputProfileBox.ItemIndex := 0;
  if Layout.Output.OutputProfile <> '' then
    FOutputProfileBox.ItemIndex := FOutputProfileBox.Items.IndexOf(Layout.Output.OutputProfile);
end;

// Every material in the layout's patterns, each name once; a name no pattern has
// stays listed, so the choice is not lost when a pattern changes
procedure TPublishForm.RefreshMaterials;
var
  Source: TLayoutSource;
  Index: integer;
  Layout: TLayout;
begin
  Layout := FDocument.Layout;
  FMaterialBox.Items.Clear;
  FMaterialBox.Items.Add(rsMaterialAll);
  for Source in Layout.Sources do
    if Assigned(Source.Pattern) then
      for Index := 0 to Source.Pattern.MaterialCount - 1 do
        if FMaterialBox.Items.IndexOf(Source.Pattern.Materials[Index].Name) < 0 then
          FMaterialBox.Items.Add(Source.Pattern.Materials[Index].Name);
  if (Layout.Output.Material <> '') and (FMaterialBox.Items.IndexOf(Layout.Output.Material) < 0) then
    FMaterialBox.Items.Add(Layout.Output.Material);
  FMaterialBox.ItemIndex := 0;
  if Layout.Output.Material <> '' then
    FMaterialBox.ItemIndex := FMaterialBox.Items.IndexOf(Layout.Output.Material);
end;

procedure TPublishForm.RefreshPatternsTab;
var
  Keep, Index: integer;
  Source: TLayoutSource;
  Entry: string;
begin
  Keep := Max(FSourceBox.ItemIndex, 0);
  FSourceBox.Items.BeginUpdate;
  try
    FSourceBox.Items.Clear;
    for Source in FDocument.Layout.Sources do
    begin
      Entry := ExtractFileName(Source.PatternFile);
      if Assigned(Source.Measurements) and (Source.Measurements.SizeName <> '') then
        Entry := Format(rsLayoutSetAndSize, [Entry, Source.Measurements.SizeName]);
      FSourceBox.Items.Add(Entry);
    end;
  finally
    FSourceBox.Items.EndUpdate;
  end;
  FSourceBox.ItemIndex := Min(Keep, FSourceBox.Items.Count - 1);
  Source := CurrentSource;
  FRemoveSourceButton.Enabled := Assigned(Source);
  FChooseSetButton.Enabled := Assigned(Source);
  FPatternSetButton.Enabled := Assigned(Source) and (Source.MeasurementFile <> '');
  FSourceSetLabel.Caption := rsNoSet;
  if Assigned(Source) and (Source.MeasurementPath <> '') then
    FSourceSetLabel.Caption := ExtractFileName(Source.MeasurementPath);
  FSizeBox.Items.Clear;
  if Assigned(Source) and Assigned(Source.Measurements) then
  begin
    for Index := 0 to Source.Measurements.SizeCount - 1 do
      FSizeBox.Items.Add(Source.Measurements.Sizes[Index]);
    FSizeBox.ItemIndex := FSizeBox.Items.IndexOf(Source.Measurements.SizeName);
  end;
  FSizeBox.Enabled := FSizeBox.Items.Count > 0;
end;

procedure TPublishForm.SourceSelected(Sender: TObject);
begin
  FRefreshing := True;
  try
    RefreshPatternsTab;
  finally
    FRefreshing := False;
  end;
end;

procedure TPublishForm.AddSourceClick(Sender: TObject);
var
  Dialog: TOpenDialog;
  Before: integer;
begin
  Dialog := TOpenDialog.Create(Self);
  try
    Dialog.Filter := rsFilterPattern;
    Dialog.Options := Dialog.Options + [ofFileMustExist];
    if not Dialog.Execute then
      Exit;
    Before := Length(FDocument.Layout.Unplaced);
    FDocument.BeginChange(rsAddPatternChange);
    FDocument.Layout.AddSource(FDocument.Layout.StoredPath(Dialog.FileName), '', '');
    FDocument.Layout.LoadSources;
    FDocument.EndChange;
    FSourceBox.ItemIndex := FSourceBox.Items.Count - 1;
    SourceSelected(Self);
    ShowStatus(Format(rsSourceAdded, [Length(FDocument.Layout.Unplaced) - Before]));
  finally
    FreeAndNil(Dialog);
  end;
end;

procedure TPublishForm.RemoveSourceClick(Sender: TObject);
begin
  if not Assigned(CurrentSource) then
    Exit;
  FPreview.Selected := -1;
  FDocument.BeginChange(rsRemovePatternChange);
  FDocument.Layout.RemoveSource(CurrentSource);
  FDocument.EndChange;
end;

procedure TPublishForm.ChangeSource(const Description, AMeasurementFile, ASize: string);
var
  Source: TLayoutSource;
begin
  Source := CurrentSource;
  if not Assigned(Source) then
    Exit;
  FDocument.BeginChange(Description);
  Source.MeasurementFile := AMeasurementFile;
  Source.Size := ASize;
  FDocument.Layout.LoadSources;
  FDocument.EndChange;
end;

// A size belongs to its file, so a new file starts on its first
procedure TPublishForm.ChooseSetClick(Sender: TObject);
var
  Dialog: TOpenDialog;
begin
  Dialog := TOpenDialog.Create(Self);
  try
    Dialog.Filter := rsFilterMeasurements;
    Dialog.Options := Dialog.Options + [ofFileMustExist];
    if Dialog.Execute then
      ChangeSource(rsSetChange, FDocument.Layout.StoredPath(Dialog.FileName), '');
  finally
    FreeAndNil(Dialog);
  end;
end;

procedure TPublishForm.PatternSetClick(Sender: TObject);
begin
  ChangeSource(rsSetChange, '', '');
end;

procedure TPublishForm.SizeChange(Sender: TObject);
begin
  if FRefreshing or not Assigned(CurrentSource) or (FSizeBox.ItemIndex < 0) then
    Exit;
  ChangeSource(rsSizeChange, CurrentSource.MeasurementFile, FSizeBox.Text);
end;

procedure TPublishForm.BuildPiecesTab;
var
  TrayGroup: TGroupBox;
begin
  BeginGroup(rsSelectedPiece);
  FTurnButton := AddButton(rsTurn, @TurnClick);
  FFlipButton := AddButton(rsFlip, @FlipClick);
  FRemoveButton := AddButton(rsRemove, @RemoveClick);
  BeginGroup(rsArrange);
  AddButton(rsPlaceNew, @PlaceClick);
  FPackButton := AddButton(rsPackPieces, @PackClick);
  EndGroup;
  // The rest of the tab, under the other groups
  TrayGroup := TGroupBox.Create(Self);
  TrayGroup.Parent := FPiecesSide;
  TrayGroup.Align := alClient;
  TrayGroup.BorderSpacing.Around := SideGap;
  TrayGroup.Caption := rsTrayGroup;
  FRowParent := TrayGroup;
  AddLabel(rsTray);
  FTray := TListBox.Create(Self);
  FTray.Parent := TrayGroup;
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
    if (Lines.Count = 0) and (Length(FDocument.Layout.Placements) = 0) then
      Lines.Add(rsTrayNoPieces)
    else if Lines.Count = 0 then
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
  // The column is narrow, so long problems only fit in full here
  FProblems.Hint := Trim(FProblems.Items.Text);
end;

procedure TPublishForm.RefreshControls;
const
  ModifiedMark: array[boolean] of string = ('', '*');
var
  Layout: TLayout;
  Pages: TTilePageArray;
  Page: TTilePage;
  Rows, Columns, Blank, LeftOut, Index: integer;
begin
  FRefreshing := True;
  try
    Layout := FDocument.Layout;
    FKindBox.ItemIndex := Ord(Layout.Output.Kind);
    FRollEdit.Value := Layout.Output.RollWidth;
    FRollEdit.Enabled := Layout.Output.Kind = okLarge;
    FPaperBox.Enabled := Layout.Output.Kind = okTiled;
    FOverlapEdit.Enabled := Layout.Output.Kind = okTiled;
    FPaperBox.ItemIndex := FPaperBox.Items.Count - 1;
    for Index := 0 to High(PaperNames) do
      if PaperNames[Index] = Layout.Output.Paper then
        FPaperBox.ItemIndex := Index;
    FPaperWidthEdit.Value := Layout.Output.Tiles.PaperWidth;
    FPaperHeightEdit.Value := Layout.Output.Tiles.PaperHeight;
    FPaperWidthEdit.Enabled := (Layout.Output.Kind = okTiled) and (FPaperBox.ItemIndex = High(PaperNames));
    FPaperHeightEdit.Enabled := FPaperWidthEdit.Enabled;
    FMarksBox.ItemIndex := Ord(Layout.Output.Marks);
    FMarksBox.Enabled := Layout.Output.Kind = okTiled;
    FFillBox.ItemIndex := Ord(Layout.Output.Fill);
    FFillBox.Enabled := Layout.Output.Kind <> okProjector;
    RefreshProfiles;
    RefreshMaterials;
    FMaterialWidthEdit.Value := Layout.Output.MaterialWidth;
    FMaterialWidthEdit.Enabled := Layout.Output.Kind = okMaterial;
    FMaterialLengthEdit.Value := Layout.Output.MaterialLength;
    FMaterialLengthEdit.Enabled := Layout.Output.Kind = okMaterial;
    FAllowTurnsBox.Checked := Layout.Output.AllowTurns;
    FAllowTurnsBox.Enabled := Layout.Output.Kind = okMaterial;
    RefreshPatternsTab;
    FMarginEdit.Value := Layout.Output.Tiles.Margin;
    FOverlapEdit.Value := Layout.Output.Tiles.Overlap;
    RefreshNotesTab;
  finally
    FRefreshing := False;
  end;
  FTurnButton.Enabled := FPreview.Selected >= 0;
  FFlipButton.Enabled := FPreview.Selected >= 0;
  FRemoveButton.Enabled := FPreview.Selected >= 0;
  FPackButton.Enabled := FDocument.Layout.Output.Kind <> okProjector;
  FUndoAction.Enabled := FDocument.CanUndo;
  if FDocument.CanUndo then
    FUndoAction.Caption := Format(rsMenuUndoNamed, [FDocument.UndoDescription])
  else
    FUndoAction.Caption := rsMenuUndo;
  SetActionHint(FUndoAction);
  FRedoAction.Enabled := FDocument.CanRedo;
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
    if Layout.Output.Kind = okMaterial then
      ShowStatus(Layout.MaterialUse);
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
  Output.Paper := PaperNames[FPaperBox.ItemIndex];
  if FPaperBox.ItemIndex = High(PaperNames) then
  begin
    Output.Tiles.PaperWidth := FPaperWidthEdit.Value;
    Output.Tiles.PaperHeight := FPaperHeightEdit.Value;
  end
  else
    PaperSize(Output.Paper, Output.Tiles.PaperWidth, Output.Tiles.PaperHeight);
  Output.Marks := TLayoutMarks(FMarksBox.ItemIndex);
  Output.Fill := TLayoutFill(FFillBox.ItemIndex);
  Output.MaterialWidth := FMaterialWidthEdit.Value;
  Output.MaterialLength := FMaterialLengthEdit.Value;
  Output.AllowTurns := FAllowTurnsBox.Checked;
  if FMaterialBox.ItemIndex > 0 then
    Output.Material := FMaterialBox.Items[FMaterialBox.ItemIndex]
  else
    Output.Material := '';
  if FProfileBox.ItemIndex > 0 then
    Output.Profile := FProfileBox.Items[FProfileBox.ItemIndex]
  else
    Output.Profile := '';
  if FOutputProfileBox.ItemIndex > 0 then
    Output.OutputProfile := FOutputProfileBox.Items[FOutputProfileBox.ItemIndex]
  else
    Output.OutputProfile := '';
  Output.Tiles.Margin := FMarginEdit.Value;
  Output.Tiles.Overlap := FOverlapEdit.Value;
  // Page names mean other sheets once the grid moves
  if (Output.Paper <> Before.Paper) or (Output.Tiles.PaperWidth <> Before.Tiles.PaperWidth) or
    (Output.Tiles.PaperHeight <> Before.Tiles.PaperHeight) or (Output.Tiles.Margin <> Before.Tiles.Margin) or (Output.Tiles.Overlap <> Before.Tiles.Overlap) or
    (Output.Kind <> Before.Kind) then
    Output.ExcludedPages := nil;
  if not TilesAreUsable(Output.Tiles) or (Output.RollWidth <= 2 * Output.Tiles.Margin) or (Output.MaterialWidth <= 0) then
  begin
    ShowStatus(rsLayoutNoPrintArea);
    // "400" passes through "4" on the way, so a typed size is left to finish
    if not FPaperWidthEdit.Focused and not FPaperHeightEdit.Focused then
      RefreshControls;
    Exit;
  end;
  FDocument.BeginChange(rsChangeSettings);
  FDocument.Layout.Output := Output;
  FDocument.EndChange('paper');
  FPreview.ZoomToFit;
end;

// Left at a size that cannot print, it goes back to the last good one
procedure TPublishForm.PaperEditExit(Sender: TObject);
begin
  RefreshControls;
end;

procedure TPublishForm.OpenPath(const Path: string);
var
  Reason: string;
begin
  // A pattern starts a new layout, which is remembered once it is saved
  if ExtractFileExt(Path) = PatternExtension then
    FDocument.NewForPattern(Path)
  else if FDocument.Open(Path, Reason) then
    FRecent.Remember(Path)
  else
  begin
    ShowStatus(Reason);
    Exit;
  end;
  FPreview.Selected := -1;
  FPreview.ZoomToFit;
end;

procedure TPublishForm.RecentOpen(Sender: TObject; const FileName: string);
begin
  if ConfirmDiscard then
    OpenPath(FileName);
end;

procedure TPublishForm.SaveLayout(const FileName: string);
var
  Reason: string;
begin
  if FDocument.Save(FileName, Reason) then
    FRecent.Remember(FileName)
  else
    ShowStatus(Reason);
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
begin
  if FDocument.Layout.FileName = '' then
    SaveAsClick(Sender)
  else
    SaveLayout(FDocument.Layout.FileName);
end;

procedure TPublishForm.SaveAsClick(Sender: TObject);
var
  Dialog: TSaveDialog;
begin
  Dialog := TSaveDialog.Create(Self);
  try
    Dialog.Filter := rsFilterLayout;
    Dialog.DefaultExt := LayoutExtension;
    Dialog.FileName := FDocument.Layout.FileName;
    if Dialog.Execute then
      SaveLayout(Dialog.FileName);
  finally
    FreeAndNil(Dialog);
  end;
end;

procedure TPublishForm.ExportClick(Sender: TObject);
var
  Dialog: TSaveDialog;
  Reason: string;
  Chosen: TExportFormat;
  Filters: array[TExportFormat] of string;
begin
  Chosen := TExportFormat(TComponent(Sender).Tag);
  Filters[efPDF] := rsFilterPDF;
  Filters[efSVG] := rsFilterSVG;
  Filters[efDXF] := rsFilterDXF;
  Filters[efMachineDXF] := rsFilterMachineDXF;
  Dialog := TSaveDialog.Create(Self);
  try
    Dialog.Filter := Filters[Chosen];
    Dialog.DefaultExt := ExportExtensions[Chosen];
    Dialog.FileName := ChangeFileExt(FDocument.Layout.FileName, ExportExtensions[Chosen]);
    if not Dialog.Execute then
      Exit;
    if ExportLayout(FDocument.Layout, Chosen, Dialog.FileName, Reason) then
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

procedure TPublishForm.PackClick(Sender: TObject);
var
  Outcome: TPackResult;
  Summary: string;
begin
  FDocument.BeginChange(rsPackChange);
  Outcome := PackLayout(FDocument.Layout);
  FDocument.EndChange;
  if Outcome.Done then
    FPreview.ZoomToFit;
  if not Outcome.Done then
    Summary := Outcome.Reason
  else if FDocument.Layout.Output.Kind = okTiled then
    Summary := Format(rsPackedPages, [Outcome.Count, Outcome.Pages])
  else
    Summary := Format(rsPacked, [Outcome.Count]);
  if Outcome.LeftOut > 0 then
    Summary := Format(rsPackLeftOut, [Summary, Outcome.LeftOut]);
  ShowStatus(Summary);
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

procedure TPublishForm.AboutClick(Sender: TObject);
begin
  ShowAboutDialog(Self, rsPublishTitle, rsAboutSummary);
end;

procedure TPublishForm.PreferencesClick(Sender: TObject);
var
  Preferences: TPreferences;
begin
  if not EditPreferences(Self, ptPublish, Preferences) then
    Exit;
  // Only printing reads it, so nothing on screen changes
  FDocument.Layout.Calibration := Preferences.Calibration;
end;

end.
