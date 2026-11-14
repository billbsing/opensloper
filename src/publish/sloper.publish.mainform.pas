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
  Classes, SysUtils, Forms, Controls, StdCtrls, ExtCtrls, ComCtrls, Menus, Spin, Dialogs, ActnList, fpjson, Sloper.Core.TextFields,
  Sloper.Core.Note, Sloper.API.AppLink, Sloper.Output.Layout, Sloper.Output.LayoutDocument, Sloper.Output.LayoutExport,
  Sloper.Publish.PreviewCanvas, Sloper.UI.Commands, Sloper.Core.Shortcuts, Sloper.UI.RecentMenu, Sloper.UI.Accordion, Sloper.UI.SavePrompt;

type
  TPublishForm = class(TForm)
  private
    FDocument: TLayoutDocument;
    FPreview: TPreviewCanvas;
    // The side tabs; the rows being built go into FRowParent
    FTabs: TAccordion;
    FPiecesSide, FSide, FNotesSide, FRowParent: TWinControl;
    FColumn: TPanel;
    FTitleBox, FEveryPageBox: TCheckBox;
    FFieldBoxes: array[0..5] of TCheckBox;
    FCornerBox: TComboBox;
    FNoteMemo: TMemo;
    FNoteSizeEdit: TFloatSpinEdit;
    FNoteAlignBox, FNoteFontBox: TComboBox;
    FNoteBoxCheck, FNoteBoldCheck, FNoteItalicCheck: TCheckBox;
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
    FTray: TListBox;
    // The problems, in plain words, that the status bar counts
    FProblemTexts: TStringArray;
    FProblemsMenu: TPopupMenu;
    // What each tray line stands for
    FTrayCopies: TUnplacedCopyArray;
    FTurnButton, FFlipButton, FRemoveButton, FPackButton: TButton;
    FCommands: TCommandSet;
    FUndoAction, FRedoAction: TAction;
    // Checked while the preview zooms to boxes
    FZoomAreaAction: TAction;
    FPrintAction: TAction;
    // Enabled only while there is something for them to work on
    FSaveAction, FSaveAsAction, FFitAction, FZoomInAction, FZoomOutAction, FReloadAction: TAction;
    FExportActions: array[TExportFormat] of TAction;
    FPrintButton: TButton;
    FRecent: TRecentMenu;
    FWatch: TTimer;
    // Where the design window's Publish… finds this window
    FAppLink: TAppLink;
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
    procedure RefreshCommands;
    procedure PreferencesClick(Sender: TObject);
    procedure AboutClick(Sender: TObject);
    procedure WatchTick(Sender: TObject);
    // Comes to the front when asked to show the layout open here
    function AppLinkMessage(const Method: string; Params: TJSONObject): boolean;
    procedure RefreshProblems;
    procedure StatusResize(Sender: TObject);
    procedure StatusMouseMove(Sender: TObject; Shift: TShiftState; X, Y: integer);
    procedure StatusMouseUp(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: integer);
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
    procedure PrintClick(Sender: TObject);
    procedure QuitClick(Sender: TObject);
    procedure UndoClick(Sender: TObject);
    procedure RedoClick(Sender: TObject);
    procedure FitClick(Sender: TObject);
    procedure ZoomInClick(Sender: TObject);
    procedure ZoomOutClick(Sender: TObject);
    procedure ZoomAreaClick(Sender: TObject);
    procedure PreviewZoomAreaChange(Sender: TObject);
    procedure PlaceClick(Sender: TObject);
    procedure ReloadClick(Sender: TObject);
    procedure TurnClick(Sender: TObject);
    procedure PackClick(Sender: TObject);
    procedure FlipClick(Sender: TObject);
    procedure CloseAsked(Sender: TObject; var CanClose: boolean);
    function ConfirmDiscard: boolean;
    procedure OpenPath(const Path: string);
    procedure RecentOpen(Sender: TObject; const FileName: string);
    function SaveLayout(const FileName: string): boolean;
    // False when the save failed or the user cancelled the file dialog
    function Save: boolean;
    function SaveAs: boolean;
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
  rsMenuPrint = '&Print...';
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
  rsMenuZoomIn = 'Zoom &In';
  rsMenuZoomOut = 'Zoom &Out';
  // With its key
  rsMenuZoomArea = '&Zoom Area (%s)';
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
  rsExportGroup = 'Print and Export';
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
  rsNoteFont = 'Font';
  rsNoteBold = 'Bold';
  rsNoteItalic = 'Italic';
  rsAddNote = 'Add note';
  rsDeleteNote = 'Delete note';
  rsNoteHelp = 'Fields: {pattern.name} {measurements.name} {date} {page} {pages} {cutlist} {materials}';
  rsNewNote = 'New note';
  rsChangeTitle = 'Change title block';
  rsChangeNote = 'Change note';
  rsAddNoteChange = 'Add note';
  rsCannotPlace = 'This piece has a problem in the pattern, so it cannot be placed yet';
  rsNoProblems = 'No problems';
  rsProblemCount = 'Problems: %d';
  // With how many of them stop printing and exporting
  rsProblemCountBlocking = 'Problems: %d, %d stop printing';
  rsProblemsHint = 'Click to list the problems';
  rsPlaceNew = 'Place new pieces';
  rsTurn = 'Turn 90°';
  rsFlip = 'Flip';
  rsPrint = 'Print...';
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
  rsPages = '%d pages, %d blank, %d left out. Right-click a page to leave it out.';
  rsLargeSheet = 'One sheet %s mm wide, %s mm long';
  rsReloaded = '%s changed on disk, so it was read again';
  rsExported = 'Wrote %s';
  // With what the print service said, such as its job number
  rsPrinted = 'Sent to the printer: %s';
  rsFilterOpen = 'Layouts and patterns (*.slayout;*.sloper)|*.slayout;*.sloper';
  rsFilterLayout = 'Layouts (*.slayout)|*.slayout';
  rsFilterPattern = 'Patterns (*.sloper)|*.sloper';
  rsFilterPDF = 'PDF (*.pdf)|*.pdf';
  rsFilterSVG = 'SVG (*.svg)|*.svg';
  rsFilterDXF = 'DXF-AAMA (*.dxf)|*.dxf';
  rsFilterMachineDXF = 'Machine DXF (*.dxf)|*.dxf';

implementation

uses
  LCLType, Math, Sloper.Core.Geometry, Sloper.Core.MachineProfiles, Sloper.Core.OutputProfiles, Sloper.Core.RecentFiles,
  Sloper.Core.Settings, Sloper.UI.IconSet, Sloper.UI.Spacing, Sloper.UI.FontBox,
  Sloper.UI.About, Sloper.UI.Preferences,
  Sloper.Output.LayoutPDF, Sloper.Output.Packing, Sloper.Output.Preview, Sloper.Output.Printing, Sloper.Output.Tiling,
  Sloper.Publish.PrintDialog, Sloper.Core.JSON, Sloper.API.Endpoint;

const
  SIDE_WIDTH = 340;
  NEW_NOTE_SIZE = 12;
  NEW_NOTE_GAP = 10;
  MAX_NOTE_SIZE = 200;
  NOTE_MEMO_HEIGHT = 110;
  // In the order of FFieldBoxes
  TITLE_FIELDS: array[0..5] of string = (FIELD_PATTERN_NAME, FIELD_MEASUREMENTS_NAME, FIELD_LAYOUT_NAME, FIELD_DATE, FIELD_CUT_LIST, FIELD_MATERIALS);
  SIDE_ROW_STEP = 100;
  // The status bar's panels: the problems count, then messages
  PANEL_PROBLEMS = 0;
  PANEL_MESSAGE = 1;
  PROBLEMS_PANEL_WIDTH96 = 150;
  PANEL_PADDING96 = 16;
  MIN_MESSAGE_WIDTH = 50;
  WATCH_MILLISECONDS = 1000;
  SPIN_DECIMALS = 1;
  MAX_MILLIMETRES = 100;
  MAX_ROLL_WIDTH = 2000;
  PATTERN_EXTENSION = '.sloper';
  // The last is the size typed in
  PAPER_NAMES: array[0..3] of string = ('A4', 'A3', 'Letter', CUSTOM_PAPER);
  PATTERN_LIST_HEIGHT = 120;
  MAX_PAPER_SIDE = 2000;
  NOTE_FIELD_CAPTIONS: array[0..5] of string = (rsFieldPattern, rsFieldMeasurements, rsFieldLayout, rsFieldDate, rsFieldCutList, rsFieldMaterials);
  MODIFIED_MARK: array[boolean] of string = ('', '*');

constructor TPublishForm.Create(AOwner: TComponent);
var
  PreviewPanel: TPanel;
  HorzBar, VertBar: TScrollBar;
  Reason: string;
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
  FStatus.SimplePanel := False;
  FStatus.Panels.Add;
  FStatus.Panels.Add;
  FStatus.ShowHint := True;
  FStatus.OnResize := @StatusResize;
  FStatus.OnMouseMove := @StatusMouseMove;
  FStatus.OnMouseUp := @StatusMouseUp;
  FProblemsMenu := TPopupMenu.Create(Self);
  FColumn := TPanel.Create(Self);
  FColumn.Parent := Self;
  FColumn.Align := alRight;
  FColumn.Width := SIDE_WIDTH;
  FColumn.BevelOuter := bvNone;
  // One tab open at a time, as in the design app's side panel
  FTabs := TAccordion.Create(Self);
  FTabs.Parent := FColumn;
  FTabs.Align := alClient;
  FPiecesSide := FTabs.AddSection('pieces', rsTabPieces);
  FPatternsSide := FTabs.AddSection('patterns', rsTabPatterns);
  FSide := FTabs.AddSection('output', rsTabOutput);
  FNotesSide := FTabs.AddSection('notes', rsTabNotes);
  // The preview and its scroll bars share a panel, so the bars stay beside it
  PreviewPanel := TPanel.Create(Self);
  PreviewPanel.Parent := Self;
  PreviewPanel.Align := alClient;
  PreviewPanel.BevelOuter := bvNone;
  HorzBar := TScrollBar.Create(Self);
  HorzBar.Parent := PreviewPanel;
  HorzBar.Align := alBottom;
  VertBar := TScrollBar.Create(Self);
  VertBar.Parent := PreviewPanel;
  VertBar.Align := alRight;
  FPreview := TPreviewCanvas.Create(Self);
  FPreview.Parent := PreviewPanel;
  FPreview.Align := alClient;
  FPreview.HorzBar := HorzBar;
  FPreview.VertBar := VertBar;
  FPreview.Document := FDocument;
  FPreview.OnSelectionChange := @SelectionChanged;
  FPreview.OnZoomAreaChange := @PreviewZoomAreaChange;
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
  FTabs.ActiveKey := UserPublishTab;
  RefreshControls;
  FWatch := TTimer.Create(Self);
  FWatch.Interval := WATCH_MILLISECONDS;
  FWatch.OnTimer := @WatchTick;
  if (ParamCount >= 1) and FileExists(ParamStr(1)) then
    OpenPath(ParamStr(1));
  // Without it, Publish… opens another window rather than this one
  FAppLink := TAppLink.Start(PUBLISH_KIND, @AppLinkMessage, True, Reason);
end;

destructor TPublishForm.Destroy;
begin
  FreeAndNil(FAppLink);
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
  OpenAction: TAction;
  ExportFormat: TExportFormat;
begin
  Bar := TMainMenu.Create(Self);
  Menu := Bar;
  FCommands := TCommandSet.Create(Self, Bar);
  OpenAction := FCommands.NewAction(rsMenuOpen, aiOpen, @OpenClick, CommandShortCut(kcOpen));
  FSaveAction := FCommands.NewAction(rsMenuSave, aiSave, @SaveClick, CommandShortCut(kcSave));
  FExportActions[efPDF] := FCommands.NewAction(rsMenuExport, aiExportPDF, @ExportClick, CommandShortCut(kcExportPDF), Ord(efPDF));
  FExportActions[efSVG] := FCommands.NewAction(rsMenuExportSVG, aiExportSVG, @ExportClick, 0, Ord(efSVG));
  FExportActions[efDXF] := FCommands.NewAction(rsMenuExportDXF, aiExportDXF, @ExportClick, 0, Ord(efDXF));
  FExportActions[efMachineDXF] := FCommands.NewAction(rsMenuExportMachineDXF, aiExportMachineDXF, @ExportClick, 0, Ord(efMachineDXF));
  FUndoAction := FCommands.NewAction(rsMenuUndo, aiUndo, @UndoClick, CommandShortCut(kcUndo));
  FRedoAction := FCommands.NewAction(rsMenuRedo, aiRedo, @RedoClick, CommandShortCut(kcRedo));
  FFitAction := FCommands.NewAction(rsMenuFit, aiFit, @FitClick, CommandShortCut(kcFit));
  FZoomInAction := FCommands.NewAction(rsMenuZoomIn, aiZoomIn, @ZoomInClick, CommandShortCut(kcZoomIn));
  FZoomOutAction := FCommands.NewAction(rsMenuZoomOut, aiZoomOut, @ZoomOutClick, CommandShortCut(kcZoomOut));
  // The preview reads the key itself, so typing Z in a field types it; the
  // key is in the caption only
  FZoomAreaAction := FCommands.NewAction(Format(rsMenuZoomArea, [ShortcutInfo(kcToolZoom).Keys]), aiZoomArea, @ZoomAreaClick);
  FReloadAction := FCommands.NewAction(rsMenuReload, aiReload, @ReloadClick, CommandShortCut(kcReload));
  FSaveAsAction := FCommands.NewAction(rsMenuSaveAs, aiSaveAs, @SaveAsClick, CommandShortCut(kcSaveAs));
  FPrintAction := FCommands.NewAction(rsMenuPrint, aiPrint, @PrintClick, CommandShortCut(kcPrint));

  Group := AddMenu(rsMenuFile);
  OpenItem := FCommands.AddMenuItem(Group, OpenAction);
  FRecent := TRecentMenu.Create(Self, Group, OpenItem, rlLayouts, @RecentOpen);
  FCommands.AddMenuItem(Group, FSaveAction);
  FCommands.AddMenuItem(Group, FSaveAsAction);
  Group.AddSeparator;
  FCommands.AddMenuItem(Group, FPrintAction);
  for ExportFormat := Low(TExportFormat) to High(TExportFormat) do
    FCommands.AddMenuItem(Group, FExportActions[ExportFormat]);
  Group.AddSeparator;
  FCommands.AddMenuItem(Group, FCommands.NewAction(rsMenuQuit, aiQuit, @QuitClick, CommandShortCut(kcQuit)));
  Group := AddMenu(rsMenuEdit);
  FCommands.AddMenuItem(Group, FUndoAction);
  FCommands.AddMenuItem(Group, FRedoAction);
  Group.AddSeparator;
  FCommands.AddMenuItem(Group, FCommands.NewAction(rsMenuPreferences, aiPreferences, @PreferencesClick, CommandShortCut(kcPreferences)));
  Group := AddMenu(rsMenuView);
  FCommands.AddMenuItem(Group, FZoomInAction);
  FCommands.AddMenuItem(Group, FZoomOutAction);
  FCommands.AddMenuItem(Group, FFitAction);
  FCommands.AddMenuItem(Group, FZoomAreaAction);
  Group.AddSeparator;
  FCommands.AddMenuItem(Group, FReloadAction);
  Group := AddMenu(rsMenuHelp);
  FCommands.AddMenuItem(Group, FCommands.NewAction(Format(rsMenuAbout, [rsPublishTitle]), aiAbout, @AboutClick));

  FCommands.AddButton(OpenAction);
  FCommands.AddButton(FSaveAction);
  FCommands.AddDivider;
  FCommands.AddButton(FUndoAction);
  FCommands.AddButton(FRedoAction);
  FCommands.AddDivider;
  FCommands.AddButton(FZoomInAction);
  FCommands.AddButton(FZoomOutAction);
  FCommands.AddButton(FFitAction);
  FCommands.AddButton(FZoomAreaAction, True);
  FCommands.AddButton(FReloadAction);
  FCommands.AddDivider;
  FCommands.AddButton(FPrintAction);
  for ExportFormat := Low(TExportFormat) to High(TExportFormat) do
    FCommands.AddButton(FExportActions[ExportFormat]);
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
  Inc(FNextRowTop, SIDE_ROW_STEP);
  Row.Top := FNextRowTop;
  Row.Align := alTop;
  Row.BorderSpacing.Left := ControlGap;
  Row.BorderSpacing.Right := ControlGap;
  Row.BorderSpacing.Top := ControlGap;
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
  SpaceChildren(Group);
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
var
  Index: integer;
begin
  BeginGroup(rsTitleBlock);
  FTitleBox := AddCheck(rsShowTitleBlock);
  for Index := 0 to High(FFieldBoxes) do
    FFieldBoxes[Index] := AddCheck(NOTE_FIELD_CAPTIONS[Index]);
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
  FNoteMemo.Height := NOTE_MEMO_HEIGHT;
  FNoteMemo.OnChange := @NoteChange;
  PlaceRow(FNoteMemo);
  AddLabel(rsNoteHelp).WordWrap := True;
  FNoteSizeEdit := AddSpin(rsNoteSize, MAX_NOTE_SIZE, 1, 0);
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
  AddLabel(rsNoteFont);
  FNoteFontBox := NewFontBox(Self, @NoteChange);
  PlaceRow(FNoteFontBox);
  FNoteBoldCheck := AddCheck(rsNoteBold);
  FNoteBoldCheck.OnChange := @NoteChange;
  FNoteItalicCheck := AddCheck(rsNoteItalic);
  FNoteItalicCheck.OnChange := @NoteChange;
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
      Shown := Shown or (Field = TITLE_FIELDS[Index]);
    FFieldBoxes[Index].Checked := Shown;
    FFieldBoxes[Index].Enabled := Layout.Title.Enabled;
  end;
  NoteChosen := FPreview.SelectedNote >= 0;
  FNoteMemo.Enabled := NoteChosen;
  FNoteSizeEdit.Enabled := NoteChosen;
  FNoteAlignBox.Enabled := NoteChosen;
  FNoteBoxCheck.Enabled := NoteChosen;
  FNoteFontBox.Enabled := NoteChosen;
  FNoteBoldCheck.Enabled := NoteChosen;
  FNoteItalicCheck.Enabled := NoteChosen;
  FDeleteNoteButton.Enabled := NoteChosen;
  if NoteChosen then
  begin
    if FNoteMemo.Text <> Layout.Notes[FPreview.SelectedNote].Text then
      FNoteMemo.Text := Layout.Notes[FPreview.SelectedNote].Text;
    FNoteSizeEdit.Value := Layout.Notes[FPreview.SelectedNote].Size;
    FNoteAlignBox.ItemIndex := Ord(Layout.Notes[FPreview.SelectedNote].Align);
    FNoteBoxCheck.Checked := Layout.Notes[FPreview.SelectedNote].Boxed;
    if not FNoteFontBox.Focused then
      ShowFontName(FNoteFontBox, Layout.Notes[FPreview.SelectedNote].Style.Font);
    FNoteBoldCheck.Checked := Layout.Notes[FPreview.SelectedNote].Style.Bold;
    FNoteItalicCheck.Checked := Layout.Notes[FPreview.SelectedNote].Style.Italic;
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
      Insert(TITLE_FIELDS[Index], Title.Fields, Length(Title.Fields));
  FDocument.BeginChange(rsChangeTitle);
  FDocument.Layout.Title := Title;
  FDocument.EndChange;
end;

// Typing merges into one undo step, as long as it keeps going. A font name
// that is refused keeps the note's font, with the reason in the status bar.
procedure TPublishForm.NoteChange(Sender: TObject);
var
  Index: integer;
  FontName, Reason: string;
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
  if CheckFontName(FontBoxName(FNoteFontBox), FontName, Reason) then
    FDocument.Layout.Notes[Index].Style.Font := FontName
  else
    ShowStatus(Reason);
  FDocument.Layout.Notes[Index].Style.Bold := FNoteBoldCheck.Checked;
  FDocument.Layout.Notes[Index].Style.Italic := FNoteItalicCheck.Checked;
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
    Lowest := Max(Lowest, Shape.Bounds.MaxY + NEW_NOTE_GAP);
  FDocument.BeginChange(rsAddNoteChange);
  Added := FDocument.Layout.AddNote(rsNewNote, 0, Lowest, NEW_NOTE_SIZE);
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
  Result.BorderSpacing.Top := ControlGap;
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
  Result.BorderSpacing.Top := ControlGap;
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
  FRollEdit := AddSpin(rsRollWidth, MAX_ROLL_WIDTH, 1, 0);
  FMaterialWidthEdit := AddSpin(rsMaterialWidth, MAX_ROLL_WIDTH, 1, 0);
  FMaterialLengthEdit := AddSpin(rsMaterialLength, MAX_ROLL_WIDTH, 1, 0);
  FAllowTurnsBox := TCheckBox.Create(Self);
  FAllowTurnsBox.Caption := rsAllowTurns;
  PlaceRow(FAllowTurnsBox);
  FAllowTurnsBox.OnClick := @SettingChange;
  BeginGroup(rsPaper);
  FPaperBox := TComboBox.Create(Self);
  PlaceRow(FPaperBox);
  FPaperBox.Style := csDropDownList;
  for Index := 0 to High(PAPER_NAMES) - 1 do
    FPaperBox.Items.Add(PAPER_NAMES[Index]);
  FPaperBox.Items.Add(rsPaperCustom);
  FPaperBox.OnChange := @SettingChange;
  FPaperWidthEdit := AddSpin(rsPaperWidth, MAX_PAPER_SIDE, 1, SPIN_DECIMALS);
  FPaperHeightEdit := AddSpin(rsPaperHeight, MAX_PAPER_SIDE, 1, SPIN_DECIMALS);
  FPaperWidthEdit.OnExit := @PaperEditExit;
  FPaperHeightEdit.OnExit := @PaperEditExit;
  FMarginEdit := AddSpin(rsMargin, MAX_MILLIMETRES, 1, SPIN_DECIMALS);
  FOverlapEdit := AddSpin(rsOverlap, MAX_MILLIMETRES, 1, SPIN_DECIMALS);
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
  FPrintButton := AddButton(rsPrint, @PrintClick);
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
  FSourceBox.Height := PATTERN_LIST_HEIGHT;
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
  FProfileBox.Items.Add(STANDARD_PROFILE_NAME);
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
  TrayGroup.BorderSpacing.Around := ControlGap;
  TrayGroup.Caption := rsTrayGroup;
  FRowParent := TrayGroup;
  AddLabel(rsTray);
  FTray := TListBox.Create(Self);
  FTray.Parent := TrayGroup;
  FTray.Align := alClient;
  FTray.BorderSpacing.Around := ControlGap;
  FTray.OnMouseDown := @TrayMouseDown;
  FTray.OnDblClick := @TrayDoubleClick;
end;

procedure TPublishForm.ShowStatus(const AText: string);
begin
  FStatus.Panels[PANEL_MESSAGE].Text := AText;
end;

// Messages take what the problems count leaves
procedure TPublishForm.StatusResize(Sender: TObject);
begin
  FStatus.Panels[PANEL_MESSAGE].Width := Max(MIN_MESSAGE_WIDTH, FStatus.ClientWidth - FStatus.Panels[PANEL_PROBLEMS].Width);
end;

// The problems in full over their count
procedure TPublishForm.StatusMouseMove(Sender: TObject; Shift: TShiftState; X, Y: integer);
var
  Wanted: string;
begin
  Wanted := '';
  if (FStatus.GetPanelIndexAt(X, Y) = PANEL_PROBLEMS) and (Length(FProblemTexts) > 0) then
    Wanted := string.Join(LineEnding, FProblemTexts) + LineEnding + LineEnding + rsProblemsHint;
  if FStatus.Hint <> Wanted then
  begin
    FStatus.Hint := Wanted;
    Application.CancelHint;
  end;
end;

procedure TPublishForm.StatusMouseUp(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: integer);
var
  Problem: string;
  Item: TMenuItem;
  At: TPoint;
begin
  if (FStatus.GetPanelIndexAt(X, Y) <> PANEL_PROBLEMS) or (Length(FProblemTexts) = 0) then
    Exit;
  FProblemsMenu.Items.Clear;
  for Problem in FProblemTexts do
  begin
    Item := TMenuItem.Create(FProblemsMenu);
    Item.Caption := Problem;
    FProblemsMenu.Items.Add(Item);
  end;
  At := FStatus.ClientToScreen(Point(X, Y));
  FProblemsMenu.PopUp(At.X, At.Y);
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
  Placed := FDocument.Layout.PlaceCopyAt(Item, FPreview.LayoutAt(X, Y), PLACEMENT_STEP);
  FDocument.EndChange;
  FPreview.Selected := Placed;
end;

procedure TPublishForm.RemoveClick(Sender: TObject);
begin
  FPreview.RemoveSelected;
end;

// Counted in the status bar, as in the design app; the tray shows the
// copies waiting to be placed
procedure TPublishForm.RefreshProblems;
var
  Problem: TLayoutProblem;
  Blocking: integer;
  Shown: string;
begin
  FProblemTexts := nil;
  Blocking := 0;
  for Problem in FDocument.Layout.Problems do
    if not Problem.Unplaced then
    begin
      Insert(Problem.Text, FProblemTexts, Length(FProblemTexts));
      if Problem.Blocking then
        Inc(Blocking);
    end;
  if Length(FProblemTexts) = 0 then
    Shown := rsNoProblems
  else if Blocking = 0 then
    Shown := Format(rsProblemCount, [Length(FProblemTexts)])
  else
    Shown := Format(rsProblemCountBlocking, [Length(FProblemTexts), Blocking]);
  FStatus.Panels[PANEL_PROBLEMS].Text := Shown;
  FStatus.Panels[PANEL_PROBLEMS].Width := Max(Scale96ToForm(PROBLEMS_PANEL_WIDTH96), FStatus.Canvas.TextWidth(Shown) +
    Scale96ToForm(PANEL_PADDING96));
  StatusResize(FStatus);
end;

// A new layout has no patterns and nothing placed, so there is nothing to
// save, view or send out until there is
procedure TPublishForm.RefreshCommands;
var
  HasPatterns, HasPlaced: boolean;
  ExportFormat: TExportFormat;
begin
  HasPatterns := FDocument.Layout.Sources.Count > 0;
  HasPlaced := Length(FDocument.Layout.Placements) > 0;
  FSaveAction.Enabled := FDocument.Modified;
  FSaveAsAction.Enabled := FDocument.Modified or (FDocument.Layout.FileName <> '');
  FReloadAction.Enabled := HasPatterns;
  FFitAction.Enabled := HasPatterns;
  FZoomInAction.Enabled := HasPatterns;
  FZoomOutAction.Enabled := HasPatterns;
  FZoomAreaAction.Enabled := HasPatterns;
  for ExportFormat := Low(TExportFormat) to High(TExportFormat) do
    FExportActions[ExportFormat].Enabled := HasPlaced;
  // A projector sheet is dark all over: it is shown, not printed
  FPrintAction.Enabled := HasPlaced and (FDocument.Layout.Output.Kind <> okProjector);
  FPrintButton.Enabled := FPrintAction.Enabled;
end;

procedure TPublishForm.RefreshControls;
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
    for Index := 0 to High(PAPER_NAMES) do
      if PAPER_NAMES[Index] = Layout.Output.Paper then
        FPaperBox.ItemIndex := Index;
    FPaperWidthEdit.Value := Layout.Output.Tiles.PaperWidth;
    FPaperHeightEdit.Value := Layout.Output.Tiles.PaperHeight;
    FPaperWidthEdit.Enabled := (Layout.Output.Kind = okTiled) and (FPaperBox.ItemIndex = High(PAPER_NAMES));
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
  RefreshCommands;
  FUndoAction.Enabled := FDocument.CanUndo;
  if FDocument.CanUndo then
    FUndoAction.Caption := Format(rsMenuUndoNamed, [FDocument.UndoDescription])
  else
    FUndoAction.Caption := rsMenuUndo;
  SetActionHint(FUndoAction);
  FRedoAction.Enabled := FDocument.CanRedo;
  if Layout.FileName <> '' then
    Caption := Format(rsPublishTitleFile, [ExtractFileName(Layout.FileName), MODIFIED_MARK[FDocument.Modified]])
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
  Output.Paper := PAPER_NAMES[FPaperBox.ItemIndex];
  if FPaperBox.ItemIndex = High(PAPER_NAMES) then
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
  if ExtractFileExt(Path) = PATTERN_EXTENSION then
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

function TPublishForm.AppLinkMessage(const Method: string; Params: TJSONObject): boolean;
var
  LayoutFile: string;
begin
  Result := (Method = APP_LINK_SHOW) and GetJSONString(Params, APP_LINK_LAYOUT_PARAM, LayoutFile) and
    (FDocument.Layout.FileName <> '') and SameFileName(ExpandFileName(FDocument.Layout.FileName), ExpandFileName(LayoutFile));
  if not Result then
    Exit;
  if WindowState = wsMinimized then
    WindowState := wsNormal;
  Application.Restore;
  ShowOnTop;
  Application.BringToFront;
end;

procedure TPublishForm.RecentOpen(Sender: TObject; const FileName: string);
begin
  if ConfirmDiscard then
    OpenPath(FileName);
end;

function TPublishForm.SaveLayout(const FileName: string): boolean;
var
  Reason: string;
begin
  Result := FDocument.Save(FileName, Reason);
  if Result then
    FRecent.Remember(FileName)
  else
    ShowStatus(Reason);
end;

function TPublishForm.Save: boolean;
begin
  if FDocument.Layout.FileName = '' then
    Result := SaveAs
  else
    Result := SaveLayout(FDocument.Layout.FileName);
end;

function TPublishForm.SaveAs: boolean;
var
  Dialog: TSaveDialog;
begin
  Dialog := TSaveDialog.Create(Self);
  try
    Dialog.Filter := rsFilterLayout;
    Dialog.DefaultExt := LAYOUT_EXTENSION;
    Dialog.FileName := FDocument.Layout.FileName;
    Result := Dialog.Execute and SaveLayout(Dialog.FileName);
  finally
    FreeAndNil(Dialog);
  end;
end;

function TPublishForm.ConfirmDiscard: boolean;
begin
  if not FDocument.Modified then
    Exit(True);
  case AskSaveChanges(ExtractFileName(FDocument.Layout.FileName)) of
    mrYes: Result := Save;
    mrNo: Result := True;
    else
      Result := False;
  end;
end;

// The open tab is kept for next time; a settings file that cannot be read is
// left as it is
procedure TPublishForm.CloseAsked(Sender: TObject; var CanClose: boolean);
var
  Err: string;
begin
  CanClose := ConfirmDiscard;
  if CanClose then
    SaveUserPublishTab(FTabs.ActiveKey, Err);
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
  Save;
end;

procedure TPublishForm.SaveAsClick(Sender: TObject);
begin
  SaveAs;
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
    Dialog.DefaultExt := EXPORT_EXTENSIONS[Chosen];
    Dialog.FileName := ChangeFileExt(FDocument.Layout.FileName, EXPORT_EXTENSIONS[Chosen]);
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

procedure TPublishForm.PrintClick(Sender: TObject);
var
  Request: TPrintRequest;
  Reply: string;
begin
  if not FPrintAction.Enabled then
    Exit;
  // Refused before the dialog, so its choices are not made for nothing
  Reply := FDocument.Layout.Refusal;
  if Reply = '' then
  begin
    if not CanPrint then
      Reply := rsPrintNoSystem
    else if not ChoosePrintOptions(Self, FDocument.Layout, Request) then
      Exit
    else
    begin
      Screen.BeginWaitCursor;
      try
        if PrintLayout(FDocument.Layout, Request, Reply) then
        begin
          ShowStatus(Format(rsPrinted, [Reply]));
          Exit;
        end;
      finally
        Screen.EndWaitCursor;
      end;
    end;
  end;
  MessageDlg(Reply, mtError, [mbOK], 0);
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

procedure TPublishForm.ZoomInClick(Sender: TObject);
begin
  FPreview.ZoomIn;
end;

procedure TPublishForm.ZoomOutClick(Sender: TObject);
begin
  FPreview.ZoomOut;
end;

procedure TPublishForm.ZoomAreaClick(Sender: TObject);
begin
  FPreview.ZoomArea := not FPreview.ZoomArea;
  FPreview.SetFocus;
end;

procedure TPublishForm.PreviewZoomAreaChange(Sender: TObject);
begin
  FZoomAreaAction.Checked := FPreview.ZoomArea;
  if FPreview.ZoomArea then
    ShowStatus(rsPreviewZoomAreaHint)
  else
    ShowStatus('');
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
