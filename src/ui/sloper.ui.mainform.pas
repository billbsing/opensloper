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

// Main application window: the canvas, menus and status bar around one
// pattern document.
unit Sloper.UI.MainForm;

{$mode ObjFPC}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, Menus, Dialogs, ComCtrls, ExtCtrls, StdCtrls, LCLType, ActnList, Sloper.Core.Geometry, Sloper.Core.Draft,
  Sloper.Core.Settings, Sloper.Document.PatternDocument, Sloper.UI.Canvas, Sloper.UI.Properties,
  Sloper.UI.ListPanel, Sloper.UI.ObjectsPanel, Sloper.UI.VariablesPanel,
  Sloper.UI.MeasurementsPanel, Sloper.UI.AlignPanel, Sloper.UI.SuggestSeams, Sloper.UI.ConvertUnits, Sloper.UI.RecentMenu, Sloper.UI.Ruler,
  Sloper.UI.MaterialPanel, Sloper.UI.MaterialDialog, Sloper.UI.RolesPanel, Sloper.UI.IconSet, Sloper.UI.Commands, Sloper.UI.Preferences,
  Sloper.Core.Transform, Sloper.Core.Fragment;

type

  { TMainForm }

  TMainForm = class(TForm)
    MainMenu: TMainMenu;
    MenuFile: TMenuItem;
    MenuFileNew: TMenuItem;
    MenuFileOpen: TMenuItem;
    MenuFileSave: TMenuItem;
    MenuFileSaveAs: TMenuItem;
    MenuFileSep1: TMenuItem;
    MenuFileMeasurements: TMenuItem;
    MenuFilePublish: TMenuItem;
    MenuFileExportDraft: TMenuItem;
    MenuFileSep2: TMenuItem;
    MenuFileQuit: TMenuItem;
    MenuEdit: TMenuItem;
    MenuEditUndo: TMenuItem;
    MenuEditRedo: TMenuItem;
    MenuEditSep1: TMenuItem;
    MenuEditDelete: TMenuItem;
    MenuView: TMenuItem;
    MenuViewZoomIn: TMenuItem;
    MenuViewZoomOut: TMenuItem;
    MenuViewFit: TMenuItem;
    MenuViewTrueSize: TMenuItem;
    MenuHelp: TMenuItem;
    MenuHelpAbout: TMenuItem;
    StatusBar: TStatusBar;
    OpenDialog: TOpenDialog;
    SaveDialog: TSaveDialog;
    MeasurementsDialog: TOpenDialog;
    procedure FormCloseQuery(Sender: TObject; var CanClose: boolean);
    procedure FormCreate(Sender: TObject);
    procedure FormDestroy(Sender: TObject);
    procedure FormShow(Sender: TObject);
    procedure MenuFileNewClick(Sender: TObject);
    procedure MenuFileOpenClick(Sender: TObject);
    procedure MenuFileSaveClick(Sender: TObject);
    procedure MenuFileSaveAsClick(Sender: TObject);
    procedure MenuFileMeasurementsClick(Sender: TObject);
    procedure MenuFilePublishClick(Sender: TObject);
    procedure MenuFileExportDraftClick(Sender: TObject);
    procedure MenuFileQuitClick(Sender: TObject);
    procedure MenuEditUndoClick(Sender: TObject);
    procedure MenuEditRedoClick(Sender: TObject);
    procedure MenuEditDeleteClick(Sender: TObject);
    procedure MenuViewZoomInClick(Sender: TObject);
    procedure MenuViewZoomOutClick(Sender: TObject);
    procedure MenuViewFitClick(Sender: TObject);
    procedure MenuViewTrueSizeClick(Sender: TObject);
    procedure MenuHelpAboutClick(Sender: TObject);
  private
    FDocument: TPatternDocument;
    FSettings: TAppSettings;
    // The clipboard format of copied objects, registered on first use
    FFragmentFormat: TClipboardFormat;
    // Shared with the other apps, and changed through Edit → Preferences
    FPreferences: TPreferences;
    FRecent: TRecentMenu;
    FActions: TActionList;
    // The same icons at toolbar and menu sizes, in TAppIcon order, and greyed
    // for disabled buttons: a grey copy of a black icon is still black
    FToolIcons, FDisabledIcons, FMenuIcons: TImageList;
    FCommandBar, FToolBar: TToolBar;
    FUndoAction, FRedoAction, FPieceFillsAction, FSideAction, FRulersAction, FAnnotationsAction: TAction;
    FRulerTop: TPanel;
    FRulerCorner: TRulerCorner;
    FHorzRuler, FVertRuler: TCanvasRuler;
    FToolActions: array[TCanvasTool] of TAction;
    FLabelActions: array[TLabelMode] of TAction;
    FRoleActions: array[TEdgeRole] of TAction;
    FRoleBox: TComboBox;
    FSidePanel: TPageControl;
    FSideSplitter: TSplitter;
    FCanvasPanel: TPanel;
    FMaterials: TMaterialsPanel;
    FRoles: TRolesPanel;
    FCanvasHorzBar, FCanvasVertBar: TScrollBar;
    FObjects: TObjectsPanel;
    FVariables: TVariablesPanel;
    FMeasurements: TMeasurementsPanel;
    FAlign: TAlignPanel;
    FNewSetDialog: TSaveDialog;
    FMeasurementWatch: TTimer;
    FOpenSetAction: TAction;
    // The Materials dialog's list width, kept in the settings
    FMaterialSplit: integer;
    FCanvas: TPatternCanvas;
    FProperties: TPropertiesPanel;
    FShown: boolean;
    procedure LoadSettings;
    procedure SaveSettings;
    procedure ApplyPreferences;
    procedure PreferencesClick(Sender: TObject);
    procedure EditCutClick(Sender: TObject);
    procedure EditCopyClick(Sender: TObject);
    procedure PutOnClipboard(const Copied: TFragmentCopy);
    procedure EditPasteClick(Sender: TObject);
    function FragmentFormat: TClipboardFormat;
    function AddEditItem(AAction: TAction): TMenuItem;
    procedure SetLabelMode(Mode: TLabelMode);
    function NewAction(const ACaption: string; AIcon: TAppIcon; AHandler: TNotifyEvent; AShortCut: TShortCut = 0;
      ATag: PtrInt = 0): TAction;
    procedure SetActionHint(AAction: TAction);
    function AddMenuItem(AParent: TMenuItem; AAction: TAction): TMenuItem;
    procedure AddButton(Bar: TToolBar; AAction: TBasicAction; Grouped: boolean = False);
    procedure AddDivider(Bar: TToolBar);
    procedure CreateToolBars;
    procedure ToolBarResize(Sender: TObject);
    procedure CreateCommands;
    procedure CreateViewCommands;
    procedure LabelModeClick(Sender: TObject);
    procedure DrawRoleClick(Sender: TObject);
    procedure DrawRoleBoxChange(Sender: TObject);
    procedure SetDrawRole(Role: TEdgeRole);
    procedure CreateDrawRoleBox;
    procedure PieceFillsClick(Sender: TObject);
    procedure AnnotationsClick(Sender: TObject);
    procedure CanvasNoteAdded(Sender: TObject);
    procedure CreateSidePanel;
    procedure SetSideShown(Shown: boolean);
    procedure SideItemClick(Sender: TObject);
    procedure ListPanelMessage(Sender: TObject; const AText: string);
    procedure ObjectsSelect(Sender: TObject);
    procedure AlignSelect(Sender: TObject; const Key: string);
    procedure ObjectsZoom(Sender: TObject);
    procedure ObjectsDelete(Sender: TObject);
    procedure MeasurementsNewSet(Sender: TObject);
    procedure MeasurementsNewSetClick(Sender: TObject);
    procedure MaterialsEditClick(Sender: TObject);
    procedure MeasurementsEditSet(Sender: TObject);
    procedure MeasurementWatchTick(Sender: TObject);
    procedure CreateToolCommands;
    procedure ToolClick(Sender: TObject);
    procedure SplitClick(Sender: TObject);
    procedure MergeClick(Sender: TObject);
    procedure BreakClick(Sender: TObject);
    procedure TransformClick(Sender: TObject);
    procedure ArcClick(Sender: TObject);
    procedure OffsetClick(Sender: TObject);
    procedure OffsetPieceClick(Sender: TObject);
    procedure RoundCornerClick(Sender: TObject);
    procedure ConvertClick(Sender: TObject);
    procedure MarkingClick(Sender: TObject);
    procedure RemoveMarkingClick(Sender: TObject);
    procedure SuggestSeamsClick(Sender: TObject);
    procedure ConvertUnitsClick(Sender: TObject);
    procedure CanvasToolChange(Sender: TObject);
    procedure CanvasSelectionChange(Sender: TObject);
    procedure DocumentChanged(Document: TPatternDocument; Changes: TDocumentChanges);
    procedure CanvasCursorMove(Sender: TObject; const ModelPos: TVec2);
    procedure CanvasMessage(Sender: TObject; const AText: string);
    procedure StatusBarResize(Sender: TObject);
    function DisplayName: string;
    // True when there are no unsaved changes, or the user saved or discarded them
    function ConfirmDiscard: boolean;
    procedure OpenFile(const FileName: string);
    procedure CreateRulers;
    procedure SetRulersShown(Shown: boolean);
    procedure RulersClick(Sender: TObject);
    procedure CanvasViewChange(Sender: TObject);
    procedure CanvasCursorLeave(Sender: TObject);
    procedure RecentOpen(Sender: TObject; const FileName: string);
    function Save: boolean;
    function SaveAs: boolean;
    procedure UpdateTitle;
    procedure UpdateMenus;
    procedure UpdateStatus;
  end;

var
  MainForm: TMainForm;

implementation

uses
  Math, process, Graphics, Clipbrd, Sloper.UI.Icons, Sloper.Core.JSON, Sloper.Core.Piece, Sloper.Output.DraftSVG,
  Sloper.Core.Seam, Sloper.Core.SeamSuggest, Sloper.Core.Version, Sloper.UI.About,
  Sloper.Core.AppPaths, Sloper.Core.Measurements, Sloper.Core.Units, Sloper.Core.UnitConvert,
  Sloper.Core.PatternCheck, Sloper.Core.RecentFiles, Sloper.Output.Layout;

  {$R *.lfm}

const
  PanelCursor = 0;
  PanelProblems = 1;
  PanelMeasurements = 2;
  PanelMessage = 3;
  ProblemsPanelWidth96 = 150;
  MeasurementWatchMilliseconds = 1000;

resourcestring
  rsMenuFile = '&File';
  rsMenuFileNew = '&New';
  rsMenuFileOpen = '&Open...';
  rsMenuFileSave = '&Save';
  rsMenuFileSaveAs = 'Save &As...';
  rsMenuFileMeasurements = '&Measurements';
  rsMenuMeasurementsNew = '&New Set...';
  rsMenuMeasurementsOpen = '&Open Set...';
  rsMenuMeasurementsEdit = '&Edit in Measurements App...';
  rsMenuFilePublish = '&Publish...';
  rsMenuFileExportDraft = 'E&xport Draft SVG...';
  rsExportDraftFilter = 'SVG (*.svg)|*.svg';
  rsExportDraftUnnamed = 'draft';
  rsExportDraftDone = 'Wrote %s';
  rsExportDraftFailed = 'Could not write %s: %s';
  rsPublishSaveFirst = 'The publish app reads the saved file. Save your changes first?';
  rsPublishMissing = 'The publish app (opensloper-publish) was not found beside this program.';
  rsMeasurementsAppMissing = 'The measurements app (opensloper-measurements) was not found beside this program.';
  rsMeasurementsAppFailed = 'The measurements app could not be started: %s';
  rsMeasurementsReloaded = '%s changed, so it was read again';
  rsPublishFailed = 'The publish app could not be started: %s';
  rsMenuFileQuit = '&Quit';
  rsMenuEdit = '&Edit';
  rsMenuEditUndo = '&Undo';
  rsMenuEditUndoWhat = '&Undo %s';
  rsMenuEditRedo = '&Redo';
  rsMenuEditRedoWhat = '&Redo %s';
  rsMenuEditCut = 'Cu&t';
  rsMenuEditCopy = '&Copy';
  rsMenuEditPaste = '&Paste';
  rsMenuEditDelete = '&Delete';
  rsMenuEditPreferences = 'Pre&ferences...';
  rsMenuEditMaterials = '&Materials...';
  rsMenuView = '&View';
  rsMenuViewZoomIn = 'Zoom &In';
  rsMenuViewZoomOut = 'Zoom &Out';
  rsMenuViewFit = '&Fit Pattern';
  rsMenuViewTrueSize = '&True Size';
  rsTabMaterials = 'Materials';
  rsTabLines = 'Lines';
  rsMenuViewSidePanel = '&Side Panel';
  rsMenuViewRulers = '&Rulers';
  rsTabProperties = 'Properties';
  rsTabObjects = 'Objects';
  rsTabVariables = 'Variables';
  rsTabMeasurements = 'Measurements';
  rsTabAlign = 'Align';
  rsMenuViewLabels = '&Labels';
  rsMenuViewPieceFills = 'Piece &Fills';
  rsMenuViewAnnotations = '&Annotations';
  rsLabelsContextual = '&Contextual';
  rsLabelsAll = '&All (hold N)';
  rsLabelsNone = '&None';
  rsMenuTools = '&Tools';
  rsToolSelect = 'Select';
  rsToolPoint = 'Point';
  rsToolLine = 'Line';
  rsToolCurve = 'Curve';
  rsToolPiece = 'Piece';
  rsToolNotch = 'Notch';
  rsToolSeam = 'Seam';
  rsToolText = 'Text';
  rsToolCallout = 'Callout';
  rsMenuToolsSplit = 'Sp&lit Edge';
  rsToolCircle = 'Circle';
  rsMenuToolsArc = 'A&rc';
  rsMenuToolsEdge = '&Edge';
  rsMenuToolsOffset = 'O&ffset';
  rsMenuToolsPoints = '&Points';
  rsMenuToolsMarkings = '&Markings';
  rsMenuToolsTransform = '&Transform';
  rsMenuOffsetLeft = 'Edge &Left';
  rsMenuOffsetRight = 'Edge &Right';
  rsMenuOffsetInside = '&Inside Piece';
  rsMenuOffsetOutside = '&Outside Piece';
  rsToolRectangle = 'Rectangle';
  rsMenuToolsOffsetLeft = 'O&ffset Edge Left';
  rsMenuToolsOffsetRight = 'Offset Edge Ri&ght';
  rsMenuToolsOffsetInside = 'Offset Inside Piece';
  rsMenuToolsOffsetOutside = 'Offset Outside Piece';
  rsMenuToolsRoundCorner = 'Ro&und Corner';
  rsMenuToolsToLine = 'Change to Li&ne';
  rsMenuToolsToCurve = 'Change to Curv&e';
  rsMenuToolsMerge = 'Merge &Points';
  rsMenuToolsBreak = '&Break Point';
  rsMenuToolsHole = 'Mark &Hole';
  rsMenuToolsAttachLine = 'Attach Marking to &Piece';
  rsMenuToolsDrawAs = 'Draw &As';
  rsDrawRoleHint = 'The role of the lines and shapes drawn next';
  rsMenuToolsStitch = 'Mark &Stitch Holes';
  rsMenuToolsRemoveMarking = '&Remove Marking';
  rsMenuToolsRotate = '&Rotate Copy...';
  rsMenuToolsMirror = 'M&irror Copy...';
  rsMenuToolsMove = 'Mo&ve Copy...';
  rsMenuToolsSuggest = 'Suggest &Seams...';
  rsMenuToolsConvertUnits = 'Convert Pattern &Units...';
  rsConvertUnitsChange = 'Convert pattern units';
  rsNoSuggestions = 'No more seams to suggest';
  rsAddSuggestedSeams = 'Add seams';
  rsHintKey = '%s (%s)';
  rsMenuHelp = '&Help';
  rsMenuHelpAbout = '&About OpenSloper';
  rsAboutSummary = 'Parametric sewing pattern drafting.';
  rsUntitled = 'Untitled';
  rsTitle = '%s%s - %s';
  rsPatternFilter = 'OpenSloper patterns (*.sloper)|*.sloper|All files|%s';
  rsMeasurementFilter = 'Measurement sets (*.slm)|*.slm|All files|%s';
  rsSaveChanges = 'Save the changes to %s?';
  rsOpenFailed = 'Could not open %s:'#10'%s';
  rsSaveFailed = 'Could not save %s:'#10'%s';
  rsMeasurementsFailed = 'Could not use %s:'#10'%s';
  rsMeasurementsMissing = 'The pattern opened, but its measurements could not be loaded:'#10'%s';
  rsCursorAt = 'x %s   y %s %s';
  rsNoProblems = 'No problems';
  rsProblems = 'Problems: %d';
  rsRolesHidden = '%s; %d kinds of line hidden';
  rsRoleHidden = '%s; 1 kind of line hidden';
  rsNoMeasurements = 'No measurement set';

  { TMainForm }

procedure TMainForm.FormCreate(Sender: TObject);
begin
  MenuFile.Caption := rsMenuFile;
  MenuEdit.Caption := rsMenuEdit;
  MenuView.Caption := rsMenuView;
  MenuHelp.Caption := rsMenuHelp;

  OpenDialog.Filter := Format(rsPatternFilter, [AllFilesMask]);
  SaveDialog.Filter := OpenDialog.Filter;
  SaveDialog.DefaultExt := 'sloper';
  MeasurementsDialog.Filter := Format(rsMeasurementFilter, [AllFilesMask]);
  OpenDialog.InitialDir := TAppPaths.DefaultDocumentsDir;
  SaveDialog.InitialDir := OpenDialog.InitialDir;
  MeasurementsDialog.InitialDir := OpenDialog.InitialDir;

  FDocument := TPatternDocument.Create;
  CreateToolBars;
  CreateCommands;
  FRecent := TRecentMenu.Create(Self, MenuFile, MenuFileOpen, rlPatterns, @RecentOpen);
  CreateSidePanel;
  CreateViewCommands;
  CreateToolCommands;
  CreateDrawRoleBox;
  LoadSettings;
  FCanvasPanel := TPanel.Create(Self);
  FCanvasPanel.Parent := Self;
  FCanvasPanel.Align := alClient;
  FCanvasPanel.BevelOuter := bvNone;
  FCanvasHorzBar := TScrollBar.Create(Self);
  FCanvasHorzBar.Parent := FCanvasPanel;
  FCanvasHorzBar.Align := alBottom;
  FCanvasVertBar := TScrollBar.Create(Self);
  FCanvasVertBar.Parent := FCanvasPanel;
  FCanvasVertBar.Align := alRight;
  CreateRulers;
  FCanvas := TPatternCanvas.Create(Self);
  FCanvas.Parent := FCanvasPanel;
  FCanvas.Align := alClient;
  FCanvas.HorzBar := FCanvasHorzBar;
  FCanvas.VertBar := FCanvasVertBar;
  FCanvas.Document := FDocument;
  FCanvas.OnCursorMove := @CanvasCursorMove;
  FCanvas.OnCursorLeave := @CanvasCursorLeave;
  FCanvas.OnViewChange := @CanvasViewChange;
  FCanvas.OnMessage := @CanvasMessage;
  FCanvas.OnToolChange := @CanvasToolChange;
  FCanvas.OnSelectionChange := @CanvasSelectionChange;
  FCanvas.OnNoteAdded := @CanvasNoteAdded;
  SetLabelMode(FSettings.LabelMode);
  SetDrawRole(erOutline);
  FPieceFillsAction.Checked := FSettings.ShowPieceFills;
  FCanvas.ShowPieceFills := FSettings.ShowPieceFills;
  SetSideShown(FSettings.ShowSidePanel);
  SetRulersShown(FSettings.ShowRulers);
  FDocument.NewPattern(FPreferences.MeasureUnit);
  ApplyPreferences;
  CanvasToolChange(nil);
  FDocument.AddListener(@DocumentChanged);
  StatusBar.OnResize := @StatusBarResize;
  UpdateTitle;
  UpdateMenus;
  UpdateStatus;
end;

// Settings only arrange the window, so a problem with the file isn't worth
// stopping the user for: the defaults stand and the file is rewritten on exit
procedure TMainForm.LoadSettings;
var
  Err: string;
begin
  FSettings := TAppSettings.Create;
  FSettings.LoadFromFile(TAppPaths.SettingsFile, Err);
  FProperties.NameShare := FSettings.NameColumnShare;
  FMaterialSplit := FSettings.MaterialDialogSplit;
  FPreferences := FSettings.Preferences;
  FRoles.SetPresets(FSettings.RolePresets);
end;

// Read again first, so that what the other apps saved in the same file while
// this one was open stays: only this window's own arrangement is written
procedure TMainForm.SaveSettings;
var
  Err: string;
begin
  FSettings.LoadFromFile(TAppPaths.SettingsFile, Err);
  FSettings.NameColumnShare := FProperties.NameShare;
  FSettings.LabelMode := FCanvas.LabelMode;
  FSettings.ShowPieceFills := FCanvas.ShowPieceFills;
  FSettings.ShowSidePanel := FSidePanel.Visible;
  FSettings.ShowRulers := FRulersAction.Checked;
  FSettings.MaterialDialogSplit := FMaterialSplit;
  TAppPaths.ForceDir(TAppPaths.ConfigDir);
  FSettings.SaveToFile(TAppPaths.SettingsFile, Err);
end;

// Rulers, grid and cursor position are in the pattern's unit, with the grid
// spacing the preferences give that unit
procedure TMainForm.ApplyPreferences;
var
  AUnit: TMeasureUnit;
begin
  AUnit := FDocument.Pattern.Units;
  FHorzRuler.MeasureUnit := AUnit;
  FVertRuler.MeasureUnit := AUnit;
  FRulerCorner.MeasureUnit := AUnit;
  FCanvas.SetGrid(FPreferences.GridSteps[AUnit], AUnit);
end;

procedure TMainForm.PreferencesClick(Sender: TObject);
var
  Preferences: TPreferences;
begin
  if not EditPreferences(Self, ptDesign, Preferences) then
    Exit;
  FPreferences := Preferences;
  ApplyPreferences;
end;

procedure TMainForm.SetLabelMode(Mode: TLabelMode);
begin
  FCanvas.LabelMode := Mode;
  FLabelActions[Mode].Checked := True;
end;

// The tabs down the left; the list panels share one place
procedure TMainForm.CreateSidePanel;

  function AddTab(const ACaption: string; Panel: TListPanel): TListPanel;
  var
    Sheet: TTabSheet;
  begin
    Sheet := FSidePanel.AddTabSheet;
    Sheet.Caption := ACaption;
    Panel.Parent := Sheet;
    Panel.Align := alClient;
    Panel.Document := FDocument;
    Panel.OnMessage := @ListPanelMessage;
    Result := Panel;
  end;

var
  PropertySheet, AlignSheet, MaterialsSheet, RolesSheet: TTabSheet;
begin
  FSidePanel := TPageControl.Create(Self);
  FSidePanel.Parent := Self;
  FSidePanel.Align := alRight;
  FSidePanel.Width := Scale96ToForm(490);
  FSidePanel.TabPosition := tpLeft;
  PropertySheet := FSidePanel.AddTabSheet;
  PropertySheet.Caption := rsTabProperties;
  FProperties := TPropertiesPanel.Create(Self);
  FProperties.Parent := PropertySheet;
  FProperties.Align := alClient;
  FProperties.Document := FDocument;
  FProperties.OnMessage := @ListPanelMessage;
  FObjects := TObjectsPanel(AddTab(rsTabObjects, TObjectsPanel.Create(Self)));
  FObjects.OnSelect := @ObjectsSelect;
  FObjects.OnZoom := @ObjectsZoom;
  FObjects.OnDelete := @ObjectsDelete;
  FVariables := TVariablesPanel(AddTab(rsTabVariables, TVariablesPanel.Create(Self)));
  FMeasurements := TMeasurementsPanel(AddTab(rsTabMeasurements, TMeasurementsPanel.Create(Self)));
  FMeasurements.OnNewSet := @MeasurementsNewSet;
  FMeasurementWatch := TTimer.Create(Self);
  FMeasurementWatch.Interval := MeasurementWatchMilliseconds;
  FMeasurementWatch.OnTimer := @MeasurementWatchTick;
  AlignSheet := FSidePanel.AddTabSheet;
  AlignSheet.Caption := rsTabAlign;
  FAlign := TAlignPanel.Create(Self);
  FAlign.Parent := AlignSheet;
  FAlign.Align := alClient;
  FAlign.Document := FDocument;
  FAlign.OnMessage := @ListPanelMessage;
  FAlign.OnSelect := @AlignSelect;
  // Hidden until the panel is fixed; the arrange code stays for the Automation API
  AlignSheet.TabVisible := False;
  RolesSheet := FSidePanel.AddTabSheet;
  RolesSheet.Caption := rsTabLines;
  FRoles := TRolesPanel.Create(Self);
  FRoles.Parent := RolesSheet;
  FRoles.Align := alClient;
  FRoles.Document := FDocument;
  FRoles.OnMessage := @ListPanelMessage;
  MaterialsSheet := FSidePanel.AddTabSheet;
  MaterialsSheet.Caption := rsTabMaterials;
  FMaterials := TMaterialsPanel.Create(Self);
  FMaterials.Parent := MaterialsSheet;
  FMaterials.Align := alClient;
  FMaterials.Document := FDocument;
  FMaterials.OnMessage := @ListPanelMessage;
  FMaterials.OnEdit := @MaterialsEditClick;
  FSideSplitter := TSplitter.Create(Self);
  FSideSplitter.Parent := Self;
  FSideSplitter.Align := alRight;
  FSideSplitter.Left := FSidePanel.Left - FSideSplitter.Width;
end;

procedure TMainForm.SetSideShown(Shown: boolean);
begin
  FSidePanel.Visible := Shown;
  // Both dock on the right, so the splitter goes just before the panel, between
  // it and the canvas, or it docks on the far side of it
  FSideSplitter.Left := FSidePanel.Left - FSideSplitter.Width;
  FSideSplitter.Visible := Shown;
  FSideAction.Checked := Shown;
end;

procedure TMainForm.SideItemClick(Sender: TObject);
begin
  SetSideShown(not FSidePanel.Visible);
end;

procedure TMainForm.ListPanelMessage(Sender: TObject; const AText: string);
begin
  StatusBar.Panels[PanelMessage].Text := AText;
end;

procedure TMainForm.AlignSelect(Sender: TObject; const Key: string);
begin
  FCanvas.SelectObjects([Key]);
end;

procedure TMainForm.ObjectsSelect(Sender: TObject);
begin
  FCanvas.SelectObjects(FObjects.Selection);
  FCanvas.RevealSelection;
end;

procedure TMainForm.ObjectsZoom(Sender: TObject);
begin
  FCanvas.ZoomToSelection;
end;

procedure TMainForm.ObjectsDelete(Sender: TObject);
begin
  FCanvas.DeleteSelection;
end;

procedure TMainForm.MeasurementsEditSet(Sender: TObject);
var
  ProgramFile: string;
  Process: TProcess;
begin
  ProgramFile := TAppPaths.MeasurementsProgram;
  if ProgramFile = '' then
  begin
    MessageDlg(rsMeasurementsAppMissing, mtError, [mbOK], 0);
    Exit;
  end;
  Process := TProcess.Create(nil);
  try
    Process.Executable := ProgramFile;
    if FDocument.MeasurementPath <> '' then
      Process.Parameters.Add(FDocument.MeasurementPath);
    // So it can list what this pattern needs; it reads the saved file
    if FDocument.FileName <> '' then
      Process.Parameters.Add(FDocument.FileName);
    try
      Process.Execute;
    except
      on Failure: EProcess do
        MessageDlg(Format(rsMeasurementsAppFailed, [Failure.Message]), mtError, [mbOK], 0);
    end;
  finally
    FreeAndNil(Process);
  end;
end;

// Unsaved edits in the Measurements tab are settled before the file they are
// for is read again
procedure TMainForm.MeasurementWatchTick(Sender: TObject);
begin
  if FMeasurements.HasPending and FDocument.MeasurementFileChanged then
  begin
    FMeasurementWatch.Enabled := False;
    try
      FMeasurements.ConfirmPending(False);
    finally
      FMeasurementWatch.Enabled := True;
    end;
  end;
  if FDocument.CheckMeasurementFile then
    StatusBar.Panels[PanelMessage].Text := Format(rsMeasurementsReloaded, [ExtractFileName(FDocument.MeasurementPath)]);
end;

procedure TMainForm.MeasurementsNewSet(Sender: TObject);
var
  Err: string;
begin
  if not Assigned(FNewSetDialog) then
  begin
    FNewSetDialog := TSaveDialog.Create(Self);
    FNewSetDialog.Filter := MeasurementsDialog.Filter;
    FNewSetDialog.DefaultExt := 'slm';
    FNewSetDialog.InitialDir := MeasurementsDialog.InitialDir;
    FNewSetDialog.Options := FNewSetDialog.Options + [ofOverwritePrompt];
  end;
  if not FNewSetDialog.Execute then
    Exit;
  if not CreateMeasurementFile(FNewSetDialog.FileName, Err) or not FDocument.UseMeasurements(FNewSetDialog.FileName, Err) then
    MessageDlg(Format(rsMeasurementsFailed, [FNewSetDialog.FileName, Err]), mtError, [mbOK], 0);
end;

// An action for a command, shared by its menu item and toolbar button
function TMainForm.NewAction(const ACaption: string; AIcon: TAppIcon; AHandler: TNotifyEvent; AShortCut: TShortCut;
  ATag: PtrInt): TAction;
begin
  Result := TAction.Create(FActions);
  Result.ActionList := FActions;
  Result.Caption := ACaption;
  Result.ImageIndex := Ord(AIcon);
  Result.ShortCut := AShortCut;
  Result.Tag := ATag;
  Result.OnExecute := AHandler;
  SetActionHint(Result);
end;

// The tooltip: the caption without its accelerator or dots. The LCL adds
// the shortcut itself.
procedure TMainForm.SetActionHint(AAction: TAction);
begin
  AAction.Hint := StringReplace(StripHotkey(AAction.Caption), '...', '', []);
end;

function TMainForm.AddMenuItem(AParent: TMenuItem; AAction: TAction): TMenuItem;
begin
  Result := TMenuItem.Create(AParent);
  Result.Action := AAction;
  AParent.Add(Result);
end;

procedure TMainForm.AddButton(Bar: TToolBar; AAction: TBasicAction; Grouped: boolean);
var
  Button: TToolButton;
begin
  Button := TToolButton.Create(Bar);
  Button.Parent := Bar;
  Button.Action := AAction;
  if Grouped then
  begin
    Button.Style := tbsCheck;
    Button.Grouped := True;
  end;
end;

procedure TMainForm.AddDivider(Bar: TToolBar);
begin
  AddToolDivider(Bar);
end;

// Commands along the top, drafting tools down the left. Without the icon
// folder the buttons show their captions instead.
procedure TMainForm.CreateToolBars;

  function NewBar(AAlign: TAlign): TToolBar;
  begin
    Result := TToolBar.Create(Self);
    Result.Parent := Self;
    Result.Align := AAlign;
    Result.Images := FToolIcons;
    Result.DisabledImages := FDisabledIcons;
    Result.ShowCaptions := not IconsFound;
    Result.ShowHint := True;
    Result.AutoSize := True;
    Result.Wrapable := True;
    if IconsFound then
    begin
      Result.ButtonWidth := FToolIcons.Width + Scale96ToForm(8);
      Result.ButtonHeight := FToolIcons.Height + Scale96ToForm(8);
    end;
  end;

begin
  FToolIcons := CreateIconList(Self, Scale96ToForm(24), clWindowText);
  FDisabledIcons := CreateIconList(Self, Scale96ToForm(24), clGrayText);
  FMenuIcons := CreateIconList(Self, Scale96ToForm(16), clMenuText);
  FActions := TActionList.Create(Self);
  FActions.Images := FMenuIcons;
  MainMenu.Images := FMenuIcons;
  ShowMenuDividers;
  FCommandBar := NewBar(alTop);
  FToolBar := NewBar(alLeft);
  // Sized by hand, so a short window wraps the tools into another column
  FToolBar.AutoSize := False;
  FToolBar.Width := FToolBar.ButtonWidth + Scale96ToForm(6);
  FToolBar.OnResize := @ToolBarResize;
end;

// As wide as the columns the buttons wrapped into
procedure TMainForm.ToolBarResize(Sender: TObject);
var
  Index, Right: integer;
begin
  Right := 0;
  for Index := 0 to FToolBar.ButtonCount - 1 do
    Right := Max(Right, FToolBar.Buttons[Index].Left + FToolBar.Buttons[Index].Width);
  Right := Right + FToolBar.Width - FToolBar.ClientWidth + Scale96ToForm(2);
  if (Right > Scale96ToForm(8)) and (Right <> FToolBar.Width) then
    FToolBar.Width := Right;
end;

// The File, Edit and View commands from the form, and the top toolbar
procedure TMainForm.CreateCommands;
begin
  MenuFileNew.Action := NewAction(rsMenuFileNew, aiNew, @MenuFileNewClick, ShortCut(VK_N, [ssModifier]));
  MenuFileOpen.Action := NewAction(rsMenuFileOpen, aiOpen, @MenuFileOpenClick, ShortCut(VK_O, [ssModifier]));
  MenuFileSave.Action := NewAction(rsMenuFileSave, aiSave, @MenuFileSaveClick, ShortCut(VK_S, [ssModifier]));
  MenuFileSaveAs.Action := NewAction(rsMenuFileSaveAs, aiSaveAs, @MenuFileSaveAsClick, ShortCut(VK_S, [ssModifier, ssShift]));
  // Open Set is also the toolbar's measurements button
  MenuFileMeasurements.Caption := rsMenuFileMeasurements;
  MenuFileMeasurements.ImageIndex := Ord(aiMeasurements);
  AddMenuItem(MenuFileMeasurements, NewAction(rsMenuMeasurementsNew, aiNew, @MeasurementsNewSetClick));
  FOpenSetAction := NewAction(rsMenuMeasurementsOpen, aiMeasurements, @MenuFileMeasurementsClick, ShortCut(VK_M, [ssModifier]));
  AddMenuItem(MenuFileMeasurements, FOpenSetAction);
  AddMenuItem(MenuFileMeasurements, NewAction(rsMenuMeasurementsEdit, aiOpen, @MeasurementsEditSet));
  MenuFilePublish.Action := NewAction(rsMenuFilePublish, aiPublish, @MenuFilePublishClick, ShortCut(VK_P, [ssModifier]));
  MenuFileExportDraft.Action := NewAction(rsMenuFileExportDraft, aiExportDraft, @MenuFileExportDraftClick);
  MenuFileQuit.Action := NewAction(rsMenuFileQuit, aiQuit, @MenuFileQuitClick, ShortCut(VK_Q, [ssModifier]));
  FUndoAction := NewAction(rsMenuEditUndo, aiUndo, @MenuEditUndoClick, ShortCut(VK_Z, [ssModifier]));
  MenuEditUndo.Action := FUndoAction;
  FRedoAction := NewAction(rsMenuEditRedo, aiRedo, @MenuEditRedoClick, ShortCut(VK_Z, [ssModifier, ssShift]));
  MenuEditRedo.Action := FRedoAction;
  // In a text field Cut, Copy and Paste work on its text
  AddEditItem(NewAction(rsMenuEditCut, aiCut, @EditCutClick, ShortCut(VK_X, [ssModifier])));
  AddEditItem(NewAction(rsMenuEditCopy, aiCopy, @EditCopyClick, ShortCut(VK_C, [ssModifier])));
  AddEditItem(NewAction(rsMenuEditPaste, aiPaste, @EditPasteClick, ShortCut(VK_V, [ssModifier])));
  // The canvas handles the Delete key, so typing in a field can still delete text
  MenuEditDelete.Action := NewAction(rsMenuEditDelete, aiDelete, @MenuEditDeleteClick);
  MenuEdit.AddSeparator;
  AddMenuItem(MenuEdit, NewAction(rsMenuEditMaterials, aiPieceFills, @MaterialsEditClick));
  AddMenuItem(MenuEdit, NewAction(rsMenuEditPreferences, aiPreferences, @PreferencesClick, ShortCut(VK_OEM_COMMA, [ssModifier])));
  MenuViewZoomIn.Action := NewAction(rsMenuViewZoomIn, aiZoomIn, @MenuViewZoomInClick, ShortCut(VK_OEM_PLUS, [ssModifier]));
  MenuViewZoomOut.Action := NewAction(rsMenuViewZoomOut, aiZoomOut, @MenuViewZoomOutClick, ShortCut(VK_OEM_MINUS, [ssModifier]));
  MenuViewFit.Action := NewAction(rsMenuViewFit, aiFit, @MenuViewFitClick, ShortCut(VK_0, [ssModifier]));
  MenuViewTrueSize.Action := NewAction(rsMenuViewTrueSize, aiTrueSize, @MenuViewTrueSizeClick, ShortCut(VK_1, [ssModifier]));
  MenuHelpAbout.Action := NewAction(rsMenuHelpAbout, aiAbout, @MenuHelpAboutClick);
  AddButton(FCommandBar, MenuFileNew.Action);
  AddButton(FCommandBar, MenuFileOpen.Action);
  AddButton(FCommandBar, MenuFileSave.Action);
  AddDivider(FCommandBar);
  AddButton(FCommandBar, FUndoAction);
  AddButton(FCommandBar, FRedoAction);
  AddButton(FCommandBar, MenuEditDelete.Action);
  AddDivider(FCommandBar);
  AddButton(FCommandBar, MenuViewZoomIn.Action);
  AddButton(FCommandBar, MenuViewZoomOut.Action);
  AddButton(FCommandBar, MenuViewFit.Action);
  AddButton(FCommandBar, MenuViewTrueSize.Action);
  AddDivider(FCommandBar);
  AddButton(FCommandBar, FOpenSetAction);
  AddButton(FCommandBar, MenuFilePublish.Action);
  AddButton(FCommandBar, MenuFileExportDraft.Action);
end;

// The side panel, label and fill toggles at the end of the View menu; each
// label action's Tag is its TLabelMode
procedure TMainForm.CreateViewCommands;
var
  MenuLabels, Item: TMenuItem;
  Mode: TLabelMode;
  Captions: array[TLabelMode] of string;
begin
  Captions[lmContextual] := rsLabelsContextual;
  Captions[lmAll] := rsLabelsAll;
  Captions[lmNone] := rsLabelsNone;
  FSideAction := NewAction(rsMenuViewSidePanel, aiSidePanel, @SideItemClick);
  MenuView.Add(NewLine);
  AddMenuItem(MenuView, FSideAction);
  FRulersAction := NewAction(rsMenuViewRulers, aiRulers, @RulersClick, ShortCut(VK_R, [ssModifier]));
  AddMenuItem(MenuView, FRulersAction);
  MenuLabels := TMenuItem.Create(MainMenu);
  MenuLabels.Caption := rsMenuViewLabels;
  MenuLabels.ImageIndex := Ord(aiLabels);
  MenuView.Add(NewLine);
  MenuView.Add(MenuLabels);
  for Mode := Low(TLabelMode) to High(TLabelMode) do
  begin
    FLabelActions[Mode] := NewAction(Captions[Mode], aiLabels, @LabelModeClick, 0, Ord(Mode));
    FLabelActions[Mode].ImageIndex := -1;
    FLabelActions[Mode].GroupIndex := 2;
    Item := AddMenuItem(MenuLabels, FLabelActions[Mode]);
    Item.RadioItem := True;
  end;
  FPieceFillsAction := NewAction(rsMenuViewPieceFills, aiPieceFills, @PieceFillsClick);
  AddMenuItem(MenuView, FPieceFillsAction);
  FAnnotationsAction := NewAction(rsMenuViewAnnotations, aiAnnotations, @AnnotationsClick);
  AddMenuItem(MenuView, FAnnotationsAction);
end;

// Kept in the pattern's view, outside undo, like the hidden roles
procedure TMainForm.AnnotationsClick(Sender: TObject);
begin
  FDocument.Pattern.View.HideAnnotations := not FDocument.Pattern.View.HideAnnotations;
  FDocument.ViewChanged;
  FCanvas.Invalidate;
end;

// Its text is typed in the properties, which share the side panel with the lists
procedure TMainForm.CanvasNoteAdded(Sender: TObject);
begin
  if not FSidePanel.Visible then
    Exit;
  FSidePanel.ActivePage := FProperties.Parent as TTabSheet;
  FProperties.FocusNoteText;
end;

procedure TMainForm.PieceFillsClick(Sender: TObject);
begin
  FPieceFillsAction.Checked := not FPieceFillsAction.Checked;
  FCanvas.ShowPieceFills := FPieceFillsAction.Checked;
end;

procedure TMainForm.LabelModeClick(Sender: TObject);
begin
  SetLabelMode(TLabelMode(TComponent(Sender).Tag));
end;

// Each role action's Tag is its TEdgeRole
procedure TMainForm.DrawRoleClick(Sender: TObject);
begin
  SetDrawRole(TEdgeRole(TComponent(Sender).Tag));
end;

procedure TMainForm.DrawRoleBoxChange(Sender: TObject);
begin
  if FRoleBox.ItemIndex >= 0 then
    SetDrawRole(TEdgeRole(FRoleBox.ItemIndex));
  FCanvas.SetFocus;
end;

procedure TMainForm.SetDrawRole(Role: TEdgeRole);
begin
  FCanvas.DrawRole := Role;
  FRoleActions[Role].Checked := True;
  FRoleBox.ItemIndex := Ord(Role);
end;

// On the command bar, so the role new lines take is always in sight
procedure TMainForm.CreateDrawRoleBox;
var
  Role: TEdgeRole;
begin
  AddDivider(FCommandBar);
  FRoleBox := TComboBox.Create(Self);
  FRoleBox.Style := csDropDownList;
  for Role := Low(TEdgeRole) to High(TEdgeRole) do
    FRoleBox.Items.Add(StripHotkey(FRoleActions[Role].Caption));
  FRoleBox.Width := Scale96ToForm(120);
  FRoleBox.Hint := rsDrawRoleHint;
  FRoleBox.ShowHint := True;
  FRoleBox.OnChange := @DrawRoleBoxChange;
  FRoleBox.Parent := FCommandBar;
end;

// The Tools menu and the toolbar down the left, in the same order. Each
// action's Tag is its TCanvasTool, TMarkingKind, TTransformKind or
// TOffsetSide, or Ord(True) for inside a piece.
procedure TMainForm.CreateToolCommands;
const
  Keys: array[TCanvasTool] of string = ('S', 'P', 'L', 'C', 'O', 'R', 'K', 'T', 'E', 'X', 'A');
  ToolIcons: array[TCanvasTool] of TAppIcon = (aiSelect, aiPoint, aiLine, aiCurve, aiCircle, aiRectangle, aiPiece, aiNotch, aiSeam, aiText,
    aiCallout);
  MarkingIcons: array[TMarkingKind] of TAppIcon = (aiHole, aiPlacement, aiStitchHoles);
  TransformIcons: array[TTransformKind] of TAppIcon = (aiRotate, aiMirror, aiMove);
var
  MenuTools, Item: TMenuItem;
  Tool: TCanvasTool;
  Captions: array[TCanvasTool] of string;
  TransformCaptions: array[TTransformKind] of string;
  MarkingCaptions: array[TMarkingKind] of string;
  Marking: TMarkingKind;
  Kind: TTransformKind;
  SubMenu: TMenuItem;
  OffsetAction, ConvertAction: TAction;
  Role: TEdgeRole;

  procedure AddCommand(AParent: TMenuItem; AAction: TAction);
  begin
    AddMenuItem(AParent, AAction);
    AddButton(FToolBar, AAction);
  end;

  procedure AddBreak;
  begin
    MenuTools.Add(NewLine);
    AddDivider(FToolBar);
  end;

  function AddSubmenu(const ACaption: string): TMenuItem;
  begin
    Result := TMenuItem.Create(MenuTools);
    Result.Caption := ACaption;
    MenuTools.Add(Result);
  end;

  // A shorter caption in its submenu; the action keeps the full one for its
  // toolbar hint. LCL leaves a caption alone once it differs from the action's.
  procedure AddShortItem(AParent: TMenuItem; AAction: TAction; const ACaption: string);
  begin
    AddMenuItem(AParent, AAction).Caption := ACaption;
  end;

begin
  MarkingCaptions[mkPoint] := rsMenuToolsHole;
  MarkingCaptions[mkLine] := rsMenuToolsAttachLine;
  MarkingCaptions[mkStitchHoles] := rsMenuToolsStitch;
  TransformCaptions[tkRotate] := rsMenuToolsRotate;
  TransformCaptions[tkMirror] := rsMenuToolsMirror;
  TransformCaptions[tkMove] := rsMenuToolsMove;
  Captions[ctSelect] := rsToolSelect;
  Captions[ctPoint] := rsToolPoint;
  Captions[ctLine] := rsToolLine;
  Captions[ctCurve] := rsToolCurve;
  Captions[ctPiece] := rsToolPiece;
  Captions[ctNotch] := rsToolNotch;
  Captions[ctSeam] := rsToolSeam;
  Captions[ctCircle] := rsToolCircle;
  Captions[ctRectangle] := rsToolRectangle;
  Captions[ctText] := rsToolText;
  Captions[ctCallout] := rsToolCallout;
  MenuTools := TMenuItem.Create(MainMenu);
  MenuTools.Caption := rsMenuTools;
  MainMenu.Items.Insert(MainMenu.Items.IndexOf(MenuHelp), MenuTools);
  // The canvas reads the tool keys itself, so they are in the caption only
  for Tool := Low(TCanvasTool) to High(TCanvasTool) do
  begin
    FToolActions[Tool] := NewAction(Format(rsHintKey, [Captions[Tool], Keys[Tool]]), ToolIcons[Tool], @ToolClick, 0, Ord(Tool));
    FToolActions[Tool].GroupIndex := 1;
    Item := AddMenuItem(MenuTools, FToolActions[Tool]);
    Item.RadioItem := True;
    AddButton(FToolBar, FToolActions[Tool], True);
  end;
  AddBreak;
  AddCommand(MenuTools, NewAction(rsMenuToolsArc, aiArc, @ArcClick));
  SubMenu := AddSubmenu(rsMenuToolsEdge);
  AddCommand(SubMenu, NewAction(rsMenuToolsSplit, aiSplit, @SplitClick));
  AddCommand(SubMenu, NewAction(rsMenuToolsRoundCorner, aiRoundCorner, @RoundCornerClick));
  // Menu only: on the toolbar they would look like the Line and Curve tools
  SubMenu.Add(NewLine);
  AddMenuItem(SubMenu, NewAction(rsMenuToolsToLine, aiToLine, @ConvertClick, 0, Ord(False)));
  AddMenuItem(SubMenu, NewAction(rsMenuToolsToCurve, aiToCurve, @ConvertClick, 0, Ord(True)));
  SubMenu := AddSubmenu(rsMenuToolsOffset);
  OffsetAction := NewAction(rsMenuToolsOffsetLeft, aiOffsetLeft, @OffsetClick, 0, Ord(osLeft));
  AddShortItem(SubMenu, OffsetAction, rsMenuOffsetLeft);
  AddButton(FToolBar, OffsetAction);
  OffsetAction := NewAction(rsMenuToolsOffsetRight, aiOffsetRight, @OffsetClick, 0, Ord(osRight));
  AddShortItem(SubMenu, OffsetAction, rsMenuOffsetRight);
  AddButton(FToolBar, OffsetAction);
  // Menu only, as their icons would look like the two above
  AddShortItem(SubMenu, NewAction(rsMenuToolsOffsetInside, aiOffsetRight, @OffsetPieceClick, 0, Ord(True)), rsMenuOffsetInside);
  AddShortItem(SubMenu, NewAction(rsMenuToolsOffsetOutside, aiOffsetLeft, @OffsetPieceClick, 0, Ord(False)), rsMenuOffsetOutside);
  AddDivider(FToolBar);
  SubMenu := AddSubmenu(rsMenuToolsPoints);
  AddCommand(SubMenu, NewAction(rsMenuToolsMerge, aiMergePoints, @MergeClick));
  AddCommand(SubMenu, NewAction(rsMenuToolsBreak, aiBreakPoint, @BreakClick));
  AddBreak;
  SubMenu := AddSubmenu(rsMenuToolsMarkings);
  for Marking := Low(TMarkingKind) to High(TMarkingKind) do
    AddCommand(SubMenu, NewAction(MarkingCaptions[Marking], MarkingIcons[Marking], @MarkingClick, 0, Ord(Marking)));
  SubMenu.Add(NewLine);
  AddCommand(SubMenu, NewAction(rsMenuToolsRemoveMarking, aiRemoveMarking, @RemoveMarkingClick));
  SubMenu := AddSubmenu(rsMenuToolsDrawAs);
  for Role := Low(TEdgeRole) to High(TEdgeRole) do
  begin
    FRoleActions[Role] := NewAction(RoleCaption(Role), aiLine, @DrawRoleClick, 0, Ord(Role));
    FRoleActions[Role].ImageIndex := -1;
    FRoleActions[Role].GroupIndex := 3;
    Item := AddMenuItem(SubMenu, FRoleActions[Role]);
    Item.RadioItem := True;
  end;
  AddBreak;
  SubMenu := AddSubmenu(rsMenuToolsTransform);
  for Kind := Low(TTransformKind) to High(TTransformKind) do
    AddCommand(SubMenu, NewAction(TransformCaptions[Kind], TransformIcons[Kind], @TransformClick, 0, Ord(Kind)));
  AddCommand(MenuTools, NewAction(rsMenuToolsSuggest, aiSuggestSeams, @SuggestSeamsClick));
  // Menu only: a rare command, with no icon of its own
  MenuTools.Add(NewLine);
  ConvertAction := NewAction(rsMenuToolsConvertUnits, aiSuggestSeams, @ConvertUnitsClick);
  ConvertAction.ImageIndex := -1;
  AddMenuItem(MenuTools, ConvertAction);
end;

procedure TMainForm.MarkingClick(Sender: TObject);
begin
  FCanvas.MarkSelection(TMarkingKind(TComponent(Sender).Tag));
  FCanvas.SetFocus;
end;

procedure TMainForm.RemoveMarkingClick(Sender: TObject);
begin
  FCanvas.UnmarkSelection;
  FCanvas.SetFocus;
end;


procedure TMainForm.OffsetClick(Sender: TObject);
begin
  FCanvas.OffsetSelection(TOffsetSide(TComponent(Sender).Tag));
  FCanvas.SetFocus;
end;

procedure TMainForm.OffsetPieceClick(Sender: TObject);
begin
  FCanvas.OffsetSelectionInPiece(TComponent(Sender).Tag = Ord(True));
  FCanvas.SetFocus;
end;

procedure TMainForm.ConvertClick(Sender: TObject);
begin
  FCanvas.ConvertSelection(TComponent(Sender).Tag = Ord(True));
  FCanvas.SetFocus;
end;

procedure TMainForm.MergeClick(Sender: TObject);
begin
  FCanvas.MergeSelection;
  FCanvas.SetFocus;
end;

procedure TMainForm.BreakClick(Sender: TObject);
begin
  FCanvas.BreakSelection;
  FCanvas.SetFocus;
end;

procedure TMainForm.RoundCornerClick(Sender: TObject);
begin
  FCanvas.RoundSelectedCorner;
  FCanvas.SetFocus;
end;

procedure TMainForm.ArcClick(Sender: TObject);
begin
  FCanvas.AddArcHere;
  FCanvas.SetFocus;
end;

procedure TMainForm.TransformClick(Sender: TObject);
begin
  FCanvas.StartTransform(TTransformKind(TComponent(Sender).Tag));
  FCanvas.SetFocus;
end;

procedure TMainForm.SplitClick(Sender: TObject);
begin
  FCanvas.SplitSelection;
end;

// All the seams ticked are one undo step
procedure TMainForm.SuggestSeamsClick(Sender: TObject);
var
  Suggestions, Chosen: TSeamSuggestionArray;
  Item: TSeamSuggestion;
  Done: boolean;
  SideA, SideB: TSeamSide;
begin
  Suggestions := SuggestSeams(FDocument.Pattern);
  if Length(Suggestions) = 0 then
  begin
    CanvasMessage(Self, rsNoSuggestions);
    Exit;
  end;
  Chosen := ChooseSeams(Self, FDocument.Pattern, Suggestions);
  if Length(Chosen) = 0 then
    Exit;
  FDocument.BeginChange(rsAddSuggestedSeams);
  Done := True;
  for Item in Chosen do
  begin
    SideA := [Item.First];
    SideB := [Item.Second];
    Done := Done and Assigned(FDocument.Pattern.AddSeam('', SideA, SideB));
  end;
  FDocument.Commit(Done);
end;

procedure TMainForm.ConvertUnitsClick(Sender: TObject);
var
  ToUnits: TMeasureUnit;
  Numbers: TUnitNumberArray;
  Err: string;
begin
  if not ChooseUnitConversion(Self, FDocument.Pattern, ToUnits, Numbers) then
    Exit;
  FDocument.BeginChange(rsConvertUnitsChange);
  if not ConvertPatternUnits(FDocument.Pattern, ToUnits, Numbers, Err) then
  begin
    FDocument.CancelChange;
    MessageDlg(Err, mtError, [mbOK], 0);
    Exit;
  end;
  FDocument.EndChange;
end;

procedure TMainForm.ToolClick(Sender: TObject);
begin
  FCanvas.Tool := TCanvasTool(TComponent(Sender).Tag);
  FCanvas.SetFocus;
end;

procedure TMainForm.CanvasToolChange(Sender: TObject);
var
  Tool: TCanvasTool;
begin
  for Tool := Low(TCanvasTool) to High(TCanvasTool) do
    FToolActions[Tool].Checked := Tool = FCanvas.Tool;
end;

procedure TMainForm.CanvasSelectionChange(Sender: TObject);
begin
  FObjects.ShowSelection(FCanvas.Selection);
  FAlign.Selection := FCanvas.Selection;
  FProperties.ShowSelection(FCanvas.Selection);
end;

procedure TMainForm.FormDestroy(Sender: TObject);
begin
  SaveSettings;
  FreeAndNil(FSettings);
  // The canvas and panels listen to the document, so they let go first
  FCanvas.Document := nil;
  FMaterials.Document := nil;
  FProperties.Document := nil;
  FObjects.Document := nil;
  FVariables.Document := nil;
  FMeasurements.Document := nil;
  FDocument.RemoveListener(@DocumentChanged);
  FreeAndNil(FDocument);
end;

procedure TMainForm.FormShow(Sender: TObject);
begin
  if FShown then
    Exit;
  FShown := True;
  if (ParamCount >= 1) and FileExists(ParamStr(1)) then
    OpenFile(ParamStr(1));
  FCanvas.SetFocus;
end;

procedure TMainForm.FormCloseQuery(Sender: TObject; var CanClose: boolean);
begin
  CanClose := ConfirmDiscard;
end;

procedure TMainForm.DocumentChanged(Document: TPatternDocument; Changes: TDocumentChanges);
begin
  // A new or opened pattern, a conversion, or undoing one, may change the unit
  if FDocument.Pattern.Units <> FHorzRuler.MeasureUnit then
    ApplyPreferences;
  if dcFile in Changes then
    UpdateTitle;
  UpdateMenus;
  UpdateStatus;
end;

// To a tenth of a millimetre, or as near as the unit shows it
function CursorNumber(Millimetres: double; AUnit: TMeasureUnit): string;
const
  Decimals: array[TMeasureUnit] of integer = (1, 2, 3);
begin
  Result := FloatToStrF(Millimetres / MillimetresPerUnit[AUnit], ffFixed, 15, Decimals[AUnit]);
end;

procedure TMainForm.CanvasCursorMove(Sender: TObject; const ModelPos: TVec2);
begin
  StatusBar.Panels[PanelCursor].Text := Format(rsCursorAt, [CursorNumber(ModelPos.X, FDocument.Pattern.Units),
    CursorNumber(ModelPos.Y, FDocument.Pattern.Units), MeasureUnitNames[FDocument.Pattern.Units]]);
  FHorzRuler.ShowCursor(ModelPos);
  FVertRuler.ShowCursor(ModelPos);
end;

procedure TMainForm.CanvasCursorLeave(Sender: TObject);
begin
  FHorzRuler.HideCursor;
  FVertRuler.HideCursor;
end;

procedure TMainForm.CanvasViewChange(Sender: TObject);
begin
  FHorzRuler.SetView(FCanvas.View);
  FVertRuler.SetView(FCanvas.View);
end;

// Along the top and left of the canvas, which they must line up with: the
// top strip spans the panel, so the corner is exactly as wide as the left
// ruler and the top ruler starts where the canvas does. They count in the
// pattern's unit (see ApplyPreferences).
procedure TMainForm.CreateRulers;
begin
  FRulerTop := TPanel.Create(Self);
  FRulerTop.Parent := FCanvasPanel;
  FRulerTop.Align := alTop;
  FRulerTop.BevelOuter := bvNone;
  FRulerTop.Height := RulerThickness(Self);
  FRulerCorner := TRulerCorner.Create(Self);
  FRulerCorner.Parent := FRulerTop;
  FRulerCorner.Align := alLeft;
  FRulerCorner.Width := RulerThickness(Self);
  FHorzRuler := TCanvasRuler.Create(Self, False);
  FHorzRuler.Parent := FRulerTop;
  FHorzRuler.Align := alClient;
  FVertRuler := TCanvasRuler.Create(Self, True);
  FVertRuler.Parent := FCanvasPanel;
  FVertRuler.Align := alLeft;
  FVertRuler.Width := RulerThickness(Self);
end;

procedure TMainForm.SetRulersShown(Shown: boolean);
begin
  FRulerTop.Visible := Shown;
  FVertRuler.Visible := Shown;
  FRulersAction.Checked := Shown;
end;

procedure TMainForm.RulersClick(Sender: TObject);
begin
  SetRulersShown(not FRulersAction.Checked);
end;

procedure TMainForm.CanvasMessage(Sender: TObject; const AText: string);
begin
  StatusBar.Panels[PanelMessage].Text := AText;
end;

// The message panel takes the room the others leave
procedure TMainForm.StatusBarResize(Sender: TObject);
var
  Index, Used: integer;
begin
  Used := 0;
  for Index := 0 to PanelMessage - 1 do
    Inc(Used, StatusBar.Panels[Index].Width);
  StatusBar.Panels[PanelMessage].Width := Max(50, StatusBar.ClientWidth - Used);
end;

function TMainForm.DisplayName: string;
begin
  if FDocument.FileName = '' then
    Result := rsUntitled
  else
    Result := ExtractFileName(FDocument.FileName);
end;

procedure TMainForm.UpdateTitle;
var
  Mark: string;
begin
  if FDocument.Modified then
    Mark := '*'
  else
    Mark := '';
  Caption := Format(rsTitle, [DisplayName, Mark, AppName]);
end;

// Undo and Redo name the step, in the menu and the tooltip
procedure TMainForm.UpdateMenus;
begin
  FUndoAction.Enabled := FDocument.CanUndo;
  if FDocument.CanUndo then
    FUndoAction.Caption := Format(rsMenuEditUndoWhat, [FDocument.UndoDescription])
  else
    FUndoAction.Caption := rsMenuEditUndo;
  SetActionHint(FUndoAction);
  FRedoAction.Enabled := FDocument.CanRedo;
  if FDocument.CanRedo then
    FRedoAction.Caption := Format(rsMenuEditRedoWhat, [FDocument.RedoDescription])
  else
    FRedoAction.Caption := rsMenuEditRedo;
  SetActionHint(FRedoAction);
  FAnnotationsAction.Checked := not FDocument.Pattern.View.HideAnnotations;
end;

procedure TMainForm.UpdateStatus;
var
  Problems: TStringArray;
  BlockedCount, Hidden: integer;
  ProblemText: string;
  Role: TEdgeRole;
begin
  Problems := PatternProblems(FDocument.Pattern, BlockedCount);
  if Length(Problems) = 0 then
    ProblemText := rsNoProblems
  else
    ProblemText := Format(rsProblems, [Length(Problems)]);
  // So that nothing seems to vanish without a reason
  Hidden := 0;
  for Role := Low(TEdgeRole) to High(TEdgeRole) do
    if Role in FDocument.Pattern.View.HiddenRoles then
      Inc(Hidden);
  if Hidden = 1 then
    ProblemText := Format(rsRoleHidden, [ProblemText])
  else if Hidden > 1 then
    ProblemText := Format(rsRolesHidden, [ProblemText, Hidden]);
  StatusBar.Panels[PanelProblems].Text := ProblemText;
  StatusBar.Panels[PanelProblems].Width := Max(Scale96ToForm(ProblemsPanelWidth96), StatusBar.Canvas.TextWidth(ProblemText) + Scale96ToForm(16));
  StatusBarResize(StatusBar);
  if not Assigned(FDocument.Measurements) then
    StatusBar.Panels[PanelMeasurements].Text := rsNoMeasurements
  else if FDocument.Measurements.Name <> '' then
    StatusBar.Panels[PanelMeasurements].Text := FDocument.Measurements.Name
  else
    StatusBar.Panels[PanelMeasurements].Text := ExtractFileName(FDocument.MeasurementPath);
end;

function TMainForm.ConfirmDiscard: boolean;
begin
  if not FMeasurements.ConfirmPending then
    Exit(False);
  if not FDocument.Modified then
    Exit(True);
  case MessageDlg(Format(rsSaveChanges, [DisplayName]), mtConfirmation, [mbYes, mbNo, mbCancel], 0) of
    mrYes: Result := Save;
    mrNo: Result := True;
    else
      Result := False;
  end;
end;

procedure TMainForm.OpenFile(const FileName: string);
var
  Err: string;
begin
  if not FDocument.LoadFromFile(FileName, Err) then
  begin
    MessageDlg(Format(rsOpenFailed, [FileName, Err]), mtError, [mbOK], 0);
    Exit;
  end;
  FRecent.Remember(FileName);
  FCanvas.SelectNone;
  FCanvas.RestoreView;
  if FDocument.MeasurementError <> '' then
    MessageDlg(Format(rsMeasurementsMissing, [FDocument.MeasurementError]), mtWarning, [mbOK], 0);
end;

function TMainForm.Save: boolean;
var
  Err: string;
begin
  if FDocument.FileName = '' then
    Exit(SaveAs);
  Result := FDocument.SaveToFile(FDocument.FileName, Err);
  if Result then
    FRecent.Remember(FDocument.FileName)
  else
    MessageDlg(Format(rsSaveFailed, [FDocument.FileName, Err]), mtError, [mbOK], 0);
end;

function TMainForm.SaveAs: boolean;
var
  Err: string;
begin
  SaveDialog.FileName := ExtractFileName(FDocument.FileName);
  if not SaveDialog.Execute then
    Exit(False);
  Result := FDocument.SaveToFile(SaveDialog.FileName, Err);
  if Result then
    FRecent.Remember(SaveDialog.FileName)
  else
    MessageDlg(Format(rsSaveFailed, [SaveDialog.FileName, Err]), mtError, [mbOK], 0);
end;

procedure TMainForm.MenuFileNewClick(Sender: TObject);
begin
  if not ConfirmDiscard then
    Exit;
  FDocument.NewPattern(FPreferences.MeasureUnit);
  FCanvas.SelectNone;
  FCanvas.RestoreView;
end;

procedure TMainForm.MenuFileOpenClick(Sender: TObject);
begin
  if ConfirmDiscard and OpenDialog.Execute then
    OpenFile(OpenDialog.FileName);
end;

procedure TMainForm.RecentOpen(Sender: TObject; const FileName: string);
begin
  if ConfirmDiscard then
    OpenFile(FileName);
end;

procedure TMainForm.MenuFileSaveClick(Sender: TObject);
begin
  Save;
end;

procedure TMainForm.MenuFileSaveAsClick(Sender: TObject);
begin
  SaveAs;
end;

procedure TMainForm.MaterialsEditClick(Sender: TObject);
var
  Dialog: TMaterialsDialog;
begin
  Dialog := TMaterialsDialog.CreateFor(Self, FDocument, FMaterials.MaterialIndex);
  try
    Dialog.Split := FMaterialSplit;
    Dialog.ShowModal;
    FMaterialSplit := Dialog.Split;
  finally
    FreeAndNil(Dialog);
  end;
end;

procedure TMainForm.MeasurementsNewSetClick(Sender: TObject);
begin
  if FMeasurements.ConfirmPending then
    MeasurementsNewSet(Sender);
end;

procedure TMainForm.MenuFileMeasurementsClick(Sender: TObject);
var
  Err: string;
begin
  if not FMeasurements.ConfirmPending or not MeasurementsDialog.Execute then
    Exit;
  if not FDocument.UseMeasurements(MeasurementsDialog.FileName, Err) then
    MessageDlg(Format(rsMeasurementsFailed, [MeasurementsDialog.FileName, Err]), mtError, [mbOK], 0);
end;

// The publish app reads saved files, so an unsaved pattern has to be saved,
// and a modified one is offered the choice
// The pattern as it stands on screen, saved or not, with its fills and labels
procedure TMainForm.MenuFileExportDraftClick(Sender: TObject);
var
  Dialog: TSaveDialog;
  Options: TDraftSVGOptions;
  PatternName, Reason: string;
begin
  PatternName := rsExportDraftUnnamed;
  if FDocument.FileName <> '' then
    PatternName := ChangeFileExt(ExtractFileName(FDocument.FileName), '');
  Dialog := TSaveDialog.Create(Self);
  try
    Dialog.Filter := rsExportDraftFilter;
    Dialog.DefaultExt := 'svg';
    Dialog.Options := Dialog.Options + [ofOverwritePrompt];
    Dialog.FileName := PatternName + '.svg';
    if FDocument.FileName <> '' then
      Dialog.InitialDir := ExtractFileDir(FDocument.FileName);
    if not Dialog.Execute then
      Exit;
    Options := DefaultDraftSVGOptions;
    Options.NoFills := not FCanvas.ShowPieceFills;
    Options.HiddenRoles := FDocument.Pattern.View.HiddenRoles;
    Options.HideAnnotations := FDocument.Pattern.View.HideAnnotations;
    Options.PatternFileName := FDocument.FileName;
    // The names the canvas is showing: all, none, or for Contextual the
    // selection and what it uses and is used by
    Options.LabelChosen := True;
    Options.LabelKeys := FCanvas.ShownLabelKeys;
    if WriteTextFile(Dialog.FileName, DraftToSVG(FDocument.Pattern, Options), Reason) then
      StatusBar.Panels[PanelMessage].Text := Format(rsExportDraftDone, [ExtractFileName(Dialog.FileName)])
    else
      MessageDlg(Format(rsExportDraftFailed, [Dialog.FileName, Reason]), mtError, [mbOK], 0);
  finally
    FreeAndNil(Dialog);
  end;
end;

procedure TMainForm.MenuFilePublishClick(Sender: TObject);
var
  ProgramFile: string;
  Process: TProcess;
begin
  ProgramFile := TAppPaths.PublishProgram;
  if ProgramFile = '' then
  begin
    MessageDlg(rsPublishMissing, mtError, [mbOK], 0);
    Exit;
  end;
  if FDocument.FileName = '' then
  begin
    if not Save then
      Exit;
  end
  else if FDocument.Modified then
    case MessageDlg(rsPublishSaveFirst, mtConfirmation, [mbYes, mbNo, mbCancel], 0) of
      mrYes:
        if not Save then
          Exit;
      mrCancel:
        Exit;
    end;
  Process := TProcess.Create(nil);
  try
    Process.Executable := ProgramFile;
    Process.Parameters.Add(PublishTargetFor(FDocument.FileName));
    try
      Process.Execute;
    except
      on Failure: EProcess do
        MessageDlg(Format(rsPublishFailed, [Failure.Message]), mtError, [mbOK], 0);
    end;
  finally
    FreeAndNil(Process);
  end;
end;

procedure TMainForm.MenuFileQuitClick(Sender: TObject);
begin
  Close;
end;

procedure TMainForm.MenuEditUndoClick(Sender: TObject);
begin
  FDocument.Undo;
end;

procedure TMainForm.MenuEditRedoClick(Sender: TObject);
begin
  FDocument.Redo;
end;

procedure TMainForm.MenuEditDeleteClick(Sender: TObject);
begin
  FCanvas.DeleteSelection;
end;

// Before Delete
function TMainForm.AddEditItem(AAction: TAction): TMenuItem;
begin
  Result := TMenuItem.Create(MenuEdit);
  Result.Action := AAction;
  MenuEdit.Insert(MenuEditDelete.MenuIndex, Result);
end;

function TMainForm.FragmentFormat: TClipboardFormat;
begin
  if FFragmentFormat = 0 then
    FFragmentFormat := RegisterClipboardFormat(FragmentMimeType);
  Result := FFragmentFormat;
end;

// The objects go on the clipboard twice: as a fragment, and as their names
// for a formula field or another app
procedure TMainForm.EditCopyClick(Sender: TObject);
begin
  if ActiveControl is TCustomEdit then
    TCustomEdit(ActiveControl).CopyToClipboard
  else
    PutOnClipboard(FCanvas.CopySelection);
end;

procedure TMainForm.EditCutClick(Sender: TObject);
begin
  if ActiveControl is TCustomEdit then
    TCustomEdit(ActiveControl).CutToClipboard
  else
    PutOnClipboard(FCanvas.CutSelection);
end;

procedure TMainForm.PutOnClipboard(const Copied: TFragmentCopy);
var
  Stream: TStringStream;
begin
  if Copied.Text = '' then
    Exit;
  Stream := TStringStream.Create(Copied.Text);
  try
    Clipboard.Open;
    try
      Clipboard.AsText := Copied.Names;
      Clipboard.AddFormat(FragmentFormat, Stream);
    finally
      Clipboard.Close;
    end;
  finally
    FreeAndNil(Stream);
  end;
end;

procedure TMainForm.EditPasteClick(Sender: TObject);
var
  Stream: TStringStream;
  Pasted: string;
begin
  if ActiveControl is TCustomEdit then
  begin
    TCustomEdit(ActiveControl).PasteFromClipboard;
    Exit;
  end;
  Pasted := '';
  if Clipboard.HasFormat(FragmentFormat) then
  begin
    Stream := TStringStream.Create('');
    try
      if Clipboard.GetFormat(FragmentFormat, Stream) then
        Pasted := TrimRight(Stream.DataString);
    finally
      FreeAndNil(Stream);
    end;
  end;
  // A fragment copied as plain text, such as one from the Automation API
  if Pasted = '' then
    Pasted := Clipboard.AsText;
  FCanvas.PasteFragmentText(Pasted);
end;

procedure TMainForm.MenuViewZoomInClick(Sender: TObject);
begin
  FCanvas.ZoomIn;
end;

procedure TMainForm.MenuViewZoomOutClick(Sender: TObject);
begin
  FCanvas.ZoomOut;
end;

procedure TMainForm.MenuViewFitClick(Sender: TObject);
begin
  FCanvas.ZoomToFit;
end;

procedure TMainForm.MenuViewTrueSizeClick(Sender: TObject);
begin
  FCanvas.ZoomTrueSize;
end;

procedure TMainForm.MenuHelpAboutClick(Sender: TObject);
begin
  ShowAboutDialog(Self, AppName, rsAboutSummary);
end;

end.
