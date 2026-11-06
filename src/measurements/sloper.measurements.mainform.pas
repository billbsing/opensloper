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

// The measurements app's one window: a table of keys, values and descriptions,
// with a column per size, beside the body figure and the catalogue. Every edit
// goes through TMeasurementDocument. Built in code, so it has no form file.
unit Sloper.Measurements.MainForm;

{$mode ObjFPC}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, StdCtrls, ExtCtrls, ComCtrls, Menus, Dialogs, Grids, ActnList, Sloper.Core.Catalogue, Sloper.Core.Measurements,
  Sloper.Document.MeasurementDocument, Sloper.Measurements.BodyFigure, Sloper.UI.Commands, Sloper.UI.RecentMenu;

type
  TMeasurementsForm = class(TForm)
  private
    FDocument: TMeasurementDocument;
    FCatalogue: TCatalogue;
    FFigure: TBodyFigure;
    FGroupBox: TComboBox;
    FSearchEdit: TEdit;
    FEntryList: TListBox;
    FEntryInfo: TMemo;
    // What each line of the list stands for
    FListed: TCatalogueEntryArray;
    FAddKnownButton: TButton;
    // The key the mouse is over in the table, ''  when none
    FGridHover: string;
    FGrid: TStringGrid;
    FTableColumn: TPanel;
    FMissingPanel: TGroupBox;
    FMissingLabel: TLabel;
    FMissingList: TListBox;
    FMissingButton: TButton;
    // What each line of the list stands for
    FMissing: TMissingMeasurementArray;
    FNameEdit, FNotesEdit: TEdit;
    FUnitBox: TComboBox;
    FStatus: TStatusBar;
    FCommands: TCommandSet;
    FUndoAction, FRedoAction: TAction;
    FRecent: TRecentMenu;
    FBar: TPanel;
    FWatch: TTimer;
    FUnit: TMeasureUnit;
    FRefreshing, FAnswering: boolean;
    procedure BuildMenu;
    procedure BuildHeader;
    procedure BuildBar;
    procedure BuildGrid;
    procedure BuildSide;
    procedure BuildMissing;
    procedure RefreshMissing;
    procedure MissingFix(Sender: TObject);
    procedure MissingSelect(Sender: TObject);
    procedure OpenArguments;
    procedure UsePatternPath(const Path: string);
    procedure CheckPatternClick(Sender: TObject);
    procedure StopPatternClick(Sender: TObject);
    procedure LoadCatalogue;
    procedure RefreshEntries;
    procedure RefreshFigure;
    function SelectedKey: string;
    procedure ShowEntry(const Key: string);
    function WarnRange(Index: integer; Value: double): boolean;
    procedure GridSelection(Sender: TObject; aCol, aRow: integer);
    procedure GridMouseMove(Sender: TObject; Shift: TShiftState; X, Y: integer);
    procedure GridMouseLeave(Sender: TObject);
    procedure GridPrepareCanvas(Sender: TObject; aCol, aRow: integer; aState: TGridDrawState);
    procedure FigurePick(Sender: TObject; const Key: string);
    procedure FigureHover(Sender: TObject; const Key: string);
    procedure FilterChange(Sender: TObject);
    procedure EntryClick(Sender: TObject);
    procedure AddKnownClick(Sender: TObject);
    function AddButton(const ACaption: string; AHandler: TNotifyEvent): TButton;
    procedure DocumentChanged(Sender: TObject);
    procedure RefreshLater(Data: PtrInt);
    procedure RefreshAll;
    procedure PreferencesClick(Sender: TObject);
    procedure AboutClick(Sender: TObject);
    procedure RefreshGrid;
    function CellText(Row, Column: integer): string;
    function ValueColumns: integer;
    function DescriptionColumn: integer;
    // The measurement on a grid row, -1 for the heading or an empty table
    function RowIndex(Row: integer): integer;
    function ColumnSize(Column: integer): integer;
    function CurrentSize: integer;
    procedure SelectCell(Index, Column: integer);
    procedure GridValidate(Sender: TObject; ACol, ARow: integer; const OldValue: string; var NewValue: string);
    procedure GridEditText(Sender: TObject; ACol, ARow: integer; const Value: string);
    function CommitCell(Column, Index: integer; const NewText: string): boolean;
    procedure HeaderDone(Sender: TObject);
    procedure UnitChange(Sender: TObject);
    procedure WatchTick(Sender: TObject);
    procedure AnswerConflicts;
    procedure NewClick(Sender: TObject);
    procedure OpenClick(Sender: TObject);
    procedure SaveClick(Sender: TObject);
    procedure SaveAsClick(Sender: TObject);
    procedure ImportClick(Sender: TObject);
    procedure ExportClick(Sender: TObject);
    procedure ImportPath(const Path: string);
    procedure ShowReport(const ATitle: string; const Lines: TStrings);
    procedure QuitClick(Sender: TObject);
    procedure UndoClick(Sender: TObject);
    procedure RedoClick(Sender: TObject);
    procedure AddClick(Sender: TObject);
    procedure DeleteClick(Sender: TObject);
    procedure UpClick(Sender: TObject);
    procedure DownClick(Sender: TObject);
    procedure AddSizeClick(Sender: TObject);
    procedure RenameSizeClick(Sender: TObject);
    procedure DeleteSizeClick(Sender: TObject);
    procedure SizeLeftClick(Sender: TObject);
    procedure SizeRightClick(Sender: TObject);
    procedure CloseAsked(Sender: TObject; var CanClose: boolean);
    function ConfirmDiscard: boolean;
    function SaveTo(const FileName: string): boolean;
    procedure OpenPath(const Path: string);
    procedure RecentOpen(Sender: TObject; const FileName: string);
    procedure ShowStatus(const AText: string);
    procedure ShowRefusal(const Reason: string);
    procedure LoadUnit;
    procedure SaveUnit;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
  end;

resourcestring
  rsMeasurementsTitle = 'OpenSloper Measurements';
  rsMeasurementsTitleFile = '%s%s - OpenSloper Measurements';
  rsUntitled = 'Untitled';
  rsMenuFile = '&File';
  rsMenuNew = '&New';
  rsMenuOpen = '&Open...';
  rsMenuSave = '&Save';
  rsMenuSaveAs = 'Save &As...';
  rsMenuImport = '&Import...';
  rsMenuExport = '&Export...';
  rsMenuCheck = '&Check Against Pattern...';
  rsMenuStopCheck = 'Stop Chec&king';
  rsMenuQuit = '&Quit';
  rsMenuEdit = '&Edit';
  rsMenuUndo = '&Undo';
  rsMenuUndoNamed = '&Undo %s';
  rsMenuRedo = '&Redo';
  rsMenuPreferences = 'Pre&ferences...';
  rsMenuHelp = '&Help';
  rsMenuAbout = '&About %s';
  rsAboutSummary = 'Measurement sets and size tables.';
  rsName = 'Name';
  rsNotes = 'Notes';
  rsShowIn = 'Show in';
  rsAdd = 'Add';
  rsDelete = 'Delete';
  rsUp = 'Up';
  rsDown = 'Down';
  rsAddSize = 'Add size...';
  rsRenameSize = 'Rename size...';
  rsDeleteSize = 'Delete size';
  rsSizeLeft = 'Size left';
  rsSizeRight = 'Size right';
  rsCatalogueTitle = 'Add From the Catalogue';
  rsAddKnown = 'Add to the file';
  rsAllGroups = 'All groups';
  rsGroupHeights = 'Heights and lengths';
  rsGroupCircumferences = 'Circumferences';
  rsGroupWidths = 'Widths';
  rsGroupArm = 'Arm';
  rsGroupLeg = 'Leg';
  rsGroupCrotch = 'Crotch';
  rsGroupHead = 'Head';
  rsGroupHand = 'Hand';
  rsGroupFoot = 'Foot';
  rsSearchHint = 'Search';
  rsTypicalRange = 'Typically %s to %s %s';
  rsOutsideRange = '@%s is outside the usual %s to %s %s; it is kept, in case that is right';
  rsNoCatalogue = 'The measurement catalogue could not be read: %s';
  rsCatalogueMissing = 'The measurement catalogue was not found';
  rsColumnKey = 'Key';
  rsColumnValue = 'Value';
  rsColumnDescription = 'Description';
  rsSizePrompt = 'Size name';
  rsAddSizeTitle = 'Add a size';
  rsRenameSizeTitle = 'Rename size %s';
  rsDeleteSizeQuestion = 'Delete size %s and its values?';
  rsDeleteQuestion = 'Delete @%s? Patterns using it will show it as missing.';
  rsDiscardQuestion = 'Discard the changes to this file?';
  rsChooseASize = 'Click a value in the size''s column first';
  rsChooseAMeasurement = 'Click a measurement first';
  rsRenamed = 'Renamed to @%s. Patterns using @%s will show it as missing';
  rsBadValue = 'A value must be a number, such as 82.5';
  rsFileReloaded = 'The file changed on disk, so it was read again';
  rsFileMerged = 'The file changed on disk; those changes were merged with yours';
  rsConflictQuestion = '@%s was changed here and in the file. Keep your version? No takes the one in the file.';
  rsConflictsAnswered = 'The file changed on disk; your answers were merged with it';
  rsSaved = 'Wrote %s';
  rsOpenFailed = 'Could not open %s: %s';
  rsSaveFailed = 'Could not save %s: %s';
  rsFilter = 'Measurements (*.slm)|*.slm';
  rsFilterImport = 'Seamly2D and Valentina (*.smis;*.smms;*.vit;*.vst)|*.smis;*.smms;*.vit;*.vst';
  rsFilterExportTable = 'Seamly2D multi-size (*.smms)|*.smms|Valentina multi-size (*.vst)|*.vst|Seamly2D individual, this size (*.smis)|*.smis|Valentina individual, this size (*.vit)|*.vit';
  rsFilterExportSet = 'Seamly2D individual (*.smis)|*.smis|Valentina individual (*.vit)|*.vit';
  rsImportTitle = 'Imported %s';
  rsImportCounts = '%d measurements read: %d translated, %d kept, %d corrected.';
  rsImportTranslated = 'Renamed to our keys:';
  rsImportKept = 'Kept as custom keys:';
  rsImportCorrected = 'Had to change:';
  rsImportNotes = 'Notes:';
  rsImportFailed = 'Could not import %s: %s';
  rsExportTitle = 'Exported %s';
  rsExportFailed = 'Could not export %s: %s';
  rsClose = 'Close';
  rsMissingNone = '%s has everything it needs here';
  rsMissingSome = '%s needs these, which this file cannot give it:';
  rsMissingKey = '@%s';
  rsMissingSizes = '@%s: no value for size %s';
  rsMissingFix = 'Add or go to it';
  rsMissingTitle = 'Pattern Check';
  rsPatternFailed = 'Could not read %s: %s';
  rsPatternReread = '%s was saved, so it was checked again';
  rsFilterPattern = 'Patterns (*.sloper)|*.sloper';

implementation

uses
  Graphics, LCLType, Math, Sloper.Core.AppPaths, Sloper.Core.RecentFiles, Sloper.Core.SeamlyFormat, Sloper.Core.Settings,
  Sloper.UI.About, Sloper.UI.IconSet, Sloper.UI.Preferences;

const
  HeaderHeight = 30;
  SideWidth = 430;
  CatalogueHeight = 410;
  EntryInfoHeight = 120;
  MissingHeight = 150;
  PatternExtension = '.sloper';
  ReportWidth = 640;
  ReportHeight = 480;
  GroupNames: array[0..High(CatalogueGroups)] of string = (rsGroupHeights, rsGroupCircumferences, rsGroupWidths, rsGroupArm, rsGroupLeg,
    rsGroupCrotch, rsGroupHead, rsGroupHand, rsGroupFoot);
  SideGap = 6;
  LabelWidth = 50;
  KeyColumnWidth = 190;
  ValueColumnWidth = 80;
  DescriptionColumnWidth = 320;
  WatchMilliseconds = 1000;
  OutOfRangeColour = $B8E6FF;
  MeasurementExtension = 'slm';
  // The key is the first column and the values follow
  KeyColumn = 0;
  FirstValueColumn = 1;

constructor TMeasurementsForm.Create(AOwner: TComponent);
begin
  inherited CreateNew(AOwner);
  Caption := rsMeasurementsTitle;
  Width := 1280;
  Height := 800;
  Position := poScreenCenter;
  OnCloseQuery := @CloseAsked;
  LoadUnit;
  FCatalogue := TCatalogue.Create;
  FDocument := TMeasurementDocument.Create;
  FDocument.OnChange := @DocumentChanged;
  BuildMenu;
  FStatus := TStatusBar.Create(Self);
  FStatus.Parent := Self;
  FStatus.SimplePanel := True;
  BuildSide;
  BuildHeader;
  BuildBar;
  // Under the table only, so that the list leaves the figure its height
  FTableColumn := TPanel.Create(Self);
  FTableColumn.Parent := Self;
  FTableColumn.Align := alClient;
  FTableColumn.BevelOuter := bvNone;
  BuildMissing;
  BuildGrid;
  LoadCatalogue;
  RefreshAll;
  FWatch := TTimer.Create(Self);
  FWatch.Interval := WatchMilliseconds;
  FWatch.OnTimer := @WatchTick;
  OpenArguments;
end;

destructor TMeasurementsForm.Destroy;
begin
  Application.RemoveAsyncCalls(Self);
  FreeAndNil(FDocument);
  FreeAndNil(FCatalogue);
  inherited Destroy;
end;

procedure TMeasurementsForm.BuildMenu;
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
  NewAction, OpenAction, SaveAction, ImportAction, ExportAction, CheckAction: TAction;
begin
  Bar := TMainMenu.Create(Self);
  Menu := Bar;
  FCommands := TCommandSet.Create(Self, Bar);
  NewAction := FCommands.NewAction(rsMenuNew, aiNew, @NewClick, ShortCut(VK_N, [ssModifier]));
  OpenAction := FCommands.NewAction(rsMenuOpen, aiOpen, @OpenClick, ShortCut(VK_O, [ssModifier]));
  SaveAction := FCommands.NewAction(rsMenuSave, aiSave, @SaveClick, ShortCut(VK_S, [ssModifier]));
  ImportAction := FCommands.NewAction(rsMenuImport, aiImport, @ImportClick, ShortCut(VK_I, [ssModifier]));
  ExportAction := FCommands.NewAction(rsMenuExport, aiExport, @ExportClick, ShortCut(VK_E, [ssModifier]));
  CheckAction := FCommands.NewAction(rsMenuCheck, aiCheckPattern, @CheckPatternClick);
  FUndoAction := FCommands.NewAction(rsMenuUndo, aiUndo, @UndoClick, ShortCut(VK_Z, [ssModifier]));
  FRedoAction := FCommands.NewAction(rsMenuRedo, aiRedo, @RedoClick, ShortCut(VK_Z, [ssModifier, ssShift]));

  Group := AddMenu(rsMenuFile);
  FCommands.AddMenuItem(Group, NewAction);
  OpenItem := FCommands.AddMenuItem(Group, OpenAction);
  FRecent := TRecentMenu.Create(Self, Group, OpenItem, rlMeasurements, @RecentOpen);
  FCommands.AddMenuItem(Group, SaveAction);
  FCommands.AddMenuItem(Group, FCommands.NewAction(rsMenuSaveAs, aiSaveAs, @SaveAsClick, ShortCut(VK_S, [ssModifier, ssShift])));
  Group.AddSeparator;
  FCommands.AddMenuItem(Group, ImportAction);
  FCommands.AddMenuItem(Group, ExportAction);
  Group.AddSeparator;
  FCommands.AddMenuItem(Group, CheckAction);
  FCommands.AddMenuItem(Group, FCommands.NewAction(rsMenuStopCheck, aiStopCheck, @StopPatternClick));
  Group.AddSeparator;
  FCommands.AddMenuItem(Group, FCommands.NewAction(rsMenuQuit, aiQuit, @QuitClick, ShortCut(VK_Q, [ssModifier])));
  Group := AddMenu(rsMenuEdit);
  FCommands.AddMenuItem(Group, FUndoAction);
  FCommands.AddMenuItem(Group, FRedoAction);
  Group.AddSeparator;
  FCommands.AddMenuItem(Group, FCommands.NewAction(rsMenuPreferences, aiPreferences, @PreferencesClick, ShortCut(VK_OEM_COMMA, [ssModifier])));
  Group := AddMenu(rsMenuHelp);
  FCommands.AddMenuItem(Group, FCommands.NewAction(Format(rsMenuAbout, [rsMeasurementsTitle]), aiAbout, @AboutClick));

  FCommands.AddButton(NewAction);
  FCommands.AddButton(OpenAction);
  FCommands.AddButton(SaveAction);
  FCommands.AddDivider;
  FCommands.AddButton(FUndoAction);
  FCommands.AddButton(FRedoAction);
  FCommands.AddDivider;
  FCommands.AddButton(ImportAction);
  FCommands.AddButton(ExportAction);
  FCommands.AddDivider;
  FCommands.AddButton(CheckAction);
end;

procedure TMeasurementsForm.BuildHeader;
var
  Row: TPanel;

  function AddField(const ACaption: string; AWidth: integer): TEdit;
  var
    Title: TLabel;
  begin
    Title := TLabel.Create(Self);
    Title.Parent := Row;
    Title.Caption := ACaption;
    Title.Align := alLeft;
    Title.Left := Row.ControlCount * 1000;
    Title.Layout := tlCenter;
    Title.AutoSize := False;
    Title.Width := LabelWidth;
    Title.BorderSpacing.Left := SideGap;
    Result := TEdit.Create(Self);
    Result.Parent := Row;
    Result.Align := alLeft;
    Result.Left := Row.ControlCount * 1000;
    Result.Width := AWidth;
    Result.BorderSpacing.Around := 2;
    Result.OnEditingDone := @HeaderDone;
  end;

begin
  Row := TPanel.Create(Self);
  Row.Parent := Self;
  // Under the toolbar: top-aligned controls stack in the order of their Top
  Row.Top := FCommands.Bar.BoundsRect.Bottom;
  Row.Align := alTop;
  Row.Height := HeaderHeight + SideGap;
  Row.BevelOuter := bvNone;
  FNameEdit := AddField(rsName, 240);
  FNotesEdit := AddField(rsNotes, 420);
end;

function TMeasurementsForm.AddButton(const ACaption: string; AHandler: TNotifyEvent): TButton;
begin
  Result := TButton.Create(Self);
  Result.Parent := FBar;
  Result.Align := alLeft;
  Result.Left := FBar.ControlCount * 1000;
  Result.AutoSize := True;
  Result.BorderSpacing.Around := 2;
  Result.Caption := ACaption;
  Result.OnClick := AHandler;
end;

procedure TMeasurementsForm.BuildBar;
var
  Title: TLabel;
  AUnit: TMeasureUnit;
begin
  FBar := TPanel.Create(Self);
  FBar.Parent := Self;
  FBar.Align := alTop;
  FBar.Top := FNameEdit.Parent.BoundsRect.Bottom;
  FBar.Height := HeaderHeight + SideGap;
  FBar.BevelOuter := bvNone;
  AddButton(rsAdd, @AddClick);
  AddButton(rsDelete, @DeleteClick);
  AddButton(rsUp, @UpClick);
  AddButton(rsDown, @DownClick).BorderSpacing.Right := SideGap * 3;
  AddButton(rsAddSize, @AddSizeClick);
  AddButton(rsRenameSize, @RenameSizeClick);
  AddButton(rsDeleteSize, @DeleteSizeClick);
  AddButton(rsSizeLeft, @SizeLeftClick);
  AddButton(rsSizeRight, @SizeRightClick);
  FUnitBox := TComboBox.Create(Self);
  FUnitBox.Parent := FBar;
  FUnitBox.Align := alRight;
  FUnitBox.Style := csDropDownList;
  FUnitBox.Width := 70;
  FUnitBox.BorderSpacing.Around := 2;
  for AUnit := Low(TMeasureUnit) to High(TMeasureUnit) do
    FUnitBox.Items.Add(MeasureUnitNames[AUnit]);
  FUnitBox.ItemIndex := Ord(FUnit);
  FUnitBox.OnChange := @UnitChange;
  Title := TLabel.Create(Self);
  Title.Parent := FBar;
  Title.Caption := rsShowIn;
  Title.Align := alRight;
  Title.Layout := tlCenter;
  Title.BorderSpacing.Right := SideGap;
end;

procedure TMeasurementsForm.BuildGrid;
begin
  FGrid := TStringGrid.Create(Self);
  FGrid.Parent := FTableColumn;
  FGrid.Align := alClient;
  FGrid.FixedCols := 0;
  FGrid.FixedRows := 1;
  FGrid.RowCount := 1;
  FGrid.Options := FGrid.Options + [goEditing, goColSizing, goTabs, goAlwaysShowEditor] - [goRangeSelect];
  FGrid.OnValidateEntry := @GridValidate;
  FGrid.OnSetEditText := @GridEditText;
  FGrid.OnSelection := @GridSelection;
  FGrid.OnMouseMove := @GridMouseMove;
  FGrid.OnMouseLeave := @GridMouseLeave;
  FGrid.OnPrepareCanvas := @GridPrepareCanvas;
end;

procedure TMeasurementsForm.BuildSide;
var
  Side, Buttons: TPanel;
  Browser: TGroupBox;
  Group: string;
begin
  Side := TPanel.Create(Self);
  Side.Parent := Self;
  Side.Align := alRight;
  Side.Width := SideWidth;
  Side.BevelOuter := bvNone;
  Browser := TGroupBox.Create(Self);
  Browser.Parent := Side;
  Browser.Align := alBottom;
  Browser.Height := CatalogueHeight;
  Browser.BorderSpacing.Around := SideGap;
  Browser.Caption := rsCatalogueTitle;
  FGroupBox := TComboBox.Create(Self);
  FGroupBox.Parent := Browser;
  FGroupBox.Align := alTop;
  FGroupBox.Top := 100;
  FGroupBox.Style := csDropDownList;
  FGroupBox.BorderSpacing.Left := SideGap;
  FGroupBox.BorderSpacing.Right := SideGap;
  FGroupBox.Items.Add(rsAllGroups);
  for Group in GroupNames do
    FGroupBox.Items.Add(Group);
  FGroupBox.ItemIndex := 0;
  FGroupBox.OnChange := @FilterChange;
  FSearchEdit := TEdit.Create(Self);
  FSearchEdit.Parent := Browser;
  FSearchEdit.Align := alTop;
  FSearchEdit.Top := 200;
  FSearchEdit.TextHint := rsSearchHint;
  FSearchEdit.BorderSpacing.Around := SideGap;
  FSearchEdit.OnChange := @FilterChange;
  Buttons := TPanel.Create(Self);
  Buttons.Parent := Browser;
  Buttons.Align := alBottom;
  Buttons.AutoSize := True;
  Buttons.BevelOuter := bvNone;
  FAddKnownButton := TButton.Create(Self);
  FAddKnownButton.Parent := Buttons;
  FAddKnownButton.Align := alLeft;
  FAddKnownButton.AutoSize := True;
  FAddKnownButton.BorderSpacing.Around := SideGap;
  FAddKnownButton.Caption := rsAddKnown;
  FAddKnownButton.OnClick := @AddKnownClick;
  FEntryInfo := TMemo.Create(Self);
  FEntryInfo.Parent := Browser;
  FEntryInfo.Align := alBottom;
  FEntryInfo.Height := EntryInfoHeight;
  FEntryInfo.ReadOnly := True;
  FEntryInfo.WordWrap := True;
  FEntryInfo.ScrollBars := ssAutoVertical;
  FEntryInfo.BorderSpacing.Left := SideGap;
  FEntryInfo.BorderSpacing.Right := SideGap;
  FEntryList := TListBox.Create(Self);
  FEntryList.Parent := Browser;
  FEntryList.Align := alClient;
  FEntryList.BorderSpacing.Left := SideGap;
  FEntryList.BorderSpacing.Right := SideGap;
  FEntryList.BorderSpacing.Bottom := SideGap;
  FEntryList.OnClick := @EntryClick;
  FEntryList.OnDblClick := @AddKnownClick;
  FFigure := TBodyFigure.Create(Self);
  FFigure.Parent := Side;
  FFigure.Align := alClient;
  FFigure.BorderSpacing.Around := SideGap;
  FFigure.OnPick := @FigurePick;
  FFigure.OnHover := @FigureHover;
end;

procedure TMeasurementsForm.BuildMissing;
var
  Buttons: TPanel;
begin
  FMissingPanel := TGroupBox.Create(Self);
  FMissingPanel.Parent := FTableColumn;
  FMissingPanel.Align := alBottom;
  FMissingPanel.Height := MissingHeight;
  FMissingPanel.BorderSpacing.Top := SideGap;
  FMissingPanel.Caption := rsMissingTitle;
  FMissingPanel.Visible := False;
  Buttons := TPanel.Create(Self);
  Buttons.Parent := FMissingPanel;
  Buttons.Align := alRight;
  Buttons.AutoSize := True;
  Buttons.BevelOuter := bvNone;
  FMissingButton := TButton.Create(Self);
  FMissingButton.Parent := Buttons;
  FMissingButton.Align := alTop;
  FMissingButton.AutoSize := True;
  FMissingButton.BorderSpacing.Around := SideGap;
  FMissingButton.Caption := rsMissingFix;
  FMissingButton.OnClick := @MissingFix;
  FMissingLabel := TLabel.Create(Self);
  FMissingLabel.Parent := FMissingPanel;
  FMissingLabel.Align := alTop;
  FMissingLabel.BorderSpacing.Around := SideGap;
  FMissingList := TListBox.Create(Self);
  FMissingList.Parent := FMissingPanel;
  FMissingList.Align := alClient;
  FMissingList.BorderSpacing.Left := SideGap;
  FMissingList.BorderSpacing.Bottom := SideGap;
  FMissingList.OnClick := @MissingSelect;
  FMissingList.OnDblClick := @MissingFix;
end;

// The list shows only while checking against a pattern
procedure TMeasurementsForm.RefreshMissing;
var
  Item: TMissingMeasurement;
  Lines: TStringList;
begin
  FMissingPanel.Visible := FDocument.PatternFile <> '';
  if not FMissingPanel.Visible then
    Exit;
  FMissing := FDocument.Missing;
  if Length(FMissing) = 0 then
    FMissingLabel.Caption := Format(rsMissingNone, [ExtractFileName(FDocument.PatternFile)])
  else
    FMissingLabel.Caption := Format(rsMissingSome, [ExtractFileName(FDocument.PatternFile)]);
  Lines := TStringList.Create;
  try
    for Item in FMissing do
      if Length(Item.Sizes) = 0 then
        Lines.Add(Format(rsMissingKey, [Item.Key]))
      else
        Lines.Add(Format(rsMissingSizes, [Item.Key, string.Join(', ', Item.Sizes)]));
    if not FMissingList.Items.Equals(Lines) then
      FMissingList.Items.Assign(Lines);
  finally
    FreeAndNil(Lines);
  end;
  FMissingButton.Enabled := FMissingList.ItemIndex >= 0;
end;

procedure TMeasurementsForm.MissingSelect(Sender: TObject);
begin
  FMissingButton.Enabled := FMissingList.ItemIndex >= 0;
  if FMissingList.ItemIndex >= 0 then
    ShowEntry(FMissing[FMissingList.ItemIndex].Key);
end;

// A key the file lacks is added; one short of a value is gone to, at that size
procedure TMeasurementsForm.MissingFix(Sender: TObject);
var
  Item: TMissingMeasurement;
  Entry: TCatalogueEntry;
  Description, Reason: string;
begin
  if FMissingList.ItemIndex < 0 then
    Exit;
  Item := FMissing[FMissingList.ItemIndex];
  if Length(Item.Sizes) > 0 then
    SelectCell(FDocument.Measurements.IndexOf(Item.Key), FirstValueColumn + FDocument.Measurements.IndexOfSize(Item.Sizes[0]))
  else
  begin
    Description := '';
    Entry := FCatalogue.Find(Item.Key);
    if Assigned(Entry) then
      Description := Entry.Description;
    if not FDocument.AddKnown(Item.Key, Description, Reason) then
    begin
      ShowRefusal(Reason);
      Exit;
    end;
    SelectCell(FDocument.Measurements.IndexOf(Item.Key), FirstValueColumn);
  end;
  ShowEntry(Item.Key);
  FGrid.SetFocus;
end;

// What each file is decides what is done with it, so the order does not matter
procedure TMeasurementsForm.OpenArguments;
var
  Index: integer;
  Path: string;
  IsMultiSize: boolean;
begin
  for Index := 1 to ParamCount do
  begin
    Path := ParamStr(Index);
    if not FileExists(Path) then
      Continue;
    if LowerCase(ExtractFileExt(Path)) = PatternExtension then
      UsePatternPath(Path)
    else if SeamlyFileKind(Path, IsMultiSize) then
      ImportPath(Path)
    else
      OpenPath(Path);
  end;
end;

procedure TMeasurementsForm.UsePatternPath(const Path: string);
var
  Reason: string;
begin
  if not FDocument.UsePattern(Path, Reason) then
    MessageDlg(Format(rsPatternFailed, [Path, Reason]), mtError, [mbOK], 0);
end;

procedure TMeasurementsForm.CheckPatternClick(Sender: TObject);
var
  Dialog: TOpenDialog;
begin
  Dialog := TOpenDialog.Create(Self);
  try
    Dialog.Filter := rsFilterPattern;
    if Dialog.Execute then
      UsePatternPath(Dialog.FileName);
  finally
    FreeAndNil(Dialog);
  end;
end;

procedure TMeasurementsForm.StopPatternClick(Sender: TObject);
begin
  UsePatternPath('');
end;

// Nothing depends on the catalogue, so without it the table still works
procedure TMeasurementsForm.LoadCatalogue;
var
  Path, Reason: string;
begin
  Path := TAppPaths.CatalogueFile;
  if Path = '' then
    ShowStatus(rsCatalogueMissing)
  else if FCatalogue.LoadFromFile(Path, Reason) then
    FFigure.Catalogue := FCatalogue
  else
    ShowStatus(Format(rsNoCatalogue, [Reason]));
end;

// Only what the file does not have yet, since a file keeps what a person needs
procedure TMeasurementsForm.RefreshEntries;
var
  Entry: TCatalogueEntry;
  Group: string;
  Lines: TStringList;
begin
  Group := '';
  if FGroupBox.ItemIndex > 0 then
    Group := CatalogueGroups[FGroupBox.ItemIndex - 1];
  FListed := nil;
  Lines := TStringList.Create;
  try
    for Entry in FCatalogue.Search(Group, FSearchEdit.Text) do
      if not Assigned(FDocument.Measurements.Find(Entry.Key)) then
      begin
        Insert(Entry, FListed, Length(FListed));
        Lines.Add(Entry.Name);
      end;
    if not FEntryList.Items.Equals(Lines) then
      FEntryList.Items.Assign(Lines);
  finally
    FreeAndNil(Lines);
  end;
  FAddKnownButton.Enabled := FEntryList.ItemIndex >= 0;
end;

procedure TMeasurementsForm.RefreshFigure;
var
  Keys: TStringArray;
  Index: integer;
begin
  Keys := nil;
  SetLength(Keys, FDocument.Measurements.Count);
  for Index := 0 to High(Keys) do
    Keys[Index] := FDocument.Measurements[Index].Key;
  FFigure.Keys := Keys;
end;

function TMeasurementsForm.SelectedKey: string;
var
  Index: integer;
begin
  Result := '';
  Index := RowIndex(FGrid.Row);
  if Index >= 0 then
    Result := FDocument.Measurements[Index].Key;
end;

procedure TMeasurementsForm.ShowEntry(const Key: string);
var
  Entry: TCatalogueEntry;
begin
  FFigure.Highlight := Key;
  Entry := FCatalogue.Find(Key);
  FEntryInfo.Lines.BeginUpdate;
  try
    FEntryInfo.Clear;
    if not Assigned(Entry) then
      Exit;
    FEntryInfo.Lines.Add(Entry.Name);
    FEntryInfo.Lines.Add(Entry.Description);
    FEntryInfo.Lines.Add(Entry.HowTo);
    FEntryInfo.Lines.Add(Format(rsTypicalRange, [FormatMeasure(Entry.RangeMin, FUnit), FormatMeasure(Entry.RangeMax, FUnit), MeasureUnitNames[FUnit]]));
  finally
    FEntryInfo.Lines.EndUpdate;
  end;
  FEntryInfo.SelStart := 0;
end;

function TMeasurementsForm.WarnRange(Index: integer; Value: double): boolean;
var
  Entry: TCatalogueEntry;
begin
  Entry := FCatalogue.Find(FDocument.Measurements[Index].Key);
  Result := Assigned(Entry) and not Entry.InRange(Value);
  if Result then
    ShowStatus(Format(rsOutsideRange, [Entry.Key, FormatMeasure(Entry.RangeMin, FUnit), FormatMeasure(Entry.RangeMax, FUnit), MeasureUnitNames[FUnit]]));
end;

procedure TMeasurementsForm.GridSelection(Sender: TObject; aCol, aRow: integer);
begin
  if not FRefreshing then
    ShowEntry(SelectedKey);
end;

procedure TMeasurementsForm.GridMouseMove(Sender: TObject; Shift: TShiftState; X, Y: integer);
var
  Column, Row, Index: integer;
  Key: string;
begin
  Key := '';
  FGrid.MouseToCell(X, Y, Column, Row);
  Index := RowIndex(Row);
  if Index >= 0 then
    Key := FDocument.Measurements[Index].Key;
  if Key = FGridHover then
    Exit;
  FGridHover := Key;
  if Key = '' then
    FFigure.Highlight := SelectedKey
  else
    FFigure.Highlight := Key;
end;

procedure TMeasurementsForm.GridMouseLeave(Sender: TObject);
begin
  FGridHover := '';
  FFigure.Highlight := SelectedKey;
end;

// A typical range only warns, so the value stays and its cell is tinted
procedure TMeasurementsForm.GridPrepareCanvas(Sender: TObject; aCol, aRow: integer; aState: TGridDrawState);
var
  Index, Size: integer;
  Measurement: TMeasurement;
  Entry: TCatalogueEntry;
begin
  Index := RowIndex(aRow);
  Size := ColumnSize(aCol);
  if (Index < 0) or (Size < 0) or (gdSelected in aState) then
    Exit;
  Measurement := FDocument.Measurements[Index];
  Entry := FCatalogue.Find(Measurement.Key);
  if Assigned(Entry) and Measurement.HasValueFor(Size) and not Entry.InRange(Measurement.ValueFor(Size)) then
    FGrid.Canvas.Brush.Color := OutOfRangeColour;
end;

procedure TMeasurementsForm.FigurePick(Sender: TObject; const Key: string);
begin
  SelectCell(FDocument.Measurements.IndexOf(Key), FirstValueColumn);
  ShowEntry(Key);
  FGrid.SetFocus;
end;

procedure TMeasurementsForm.FigureHover(Sender: TObject; const Key: string);
begin
  if Key = '' then
    ShowEntry(SelectedKey)
  else
    ShowEntry(Key);
end;

procedure TMeasurementsForm.FilterChange(Sender: TObject);
begin
  RefreshEntries;
end;

procedure TMeasurementsForm.EntryClick(Sender: TObject);
begin
  FAddKnownButton.Enabled := FEntryList.ItemIndex >= 0;
  if FEntryList.ItemIndex >= 0 then
    ShowEntry(FListed[FEntryList.ItemIndex].Key);
end;

procedure TMeasurementsForm.AddKnownClick(Sender: TObject);
var
  Entry: TCatalogueEntry;
  Reason: string;
begin
  if FEntryList.ItemIndex < 0 then
    Exit;
  Entry := FListed[FEntryList.ItemIndex];
  if FDocument.AddKnown(Entry.Key, Entry.Description, Reason) then
  begin
    // Or the next line slides under the mouse, ready to be added by mistake
    FEntryList.ItemIndex := -1;
    SelectCell(FDocument.Measurements.IndexOf(Entry.Key), FirstValueColumn);
    ShowEntry(Entry.Key);
    FGrid.SetFocus;
  end
  else
    ShowRefusal(Reason);
end;

function TMeasurementsForm.ValueColumns: integer;
begin
  Result := Max(FDocument.Measurements.SizeCount, 1);
end;

function TMeasurementsForm.DescriptionColumn: integer;
begin
  Result := FirstValueColumn + ValueColumns;
end;

function TMeasurementsForm.RowIndex(Row: integer): integer;
begin
  Result := Row - FGrid.FixedRows;
  if (Result < 0) or (Result >= FDocument.Measurements.Count) then
    Result := -1;
end;

function TMeasurementsForm.ColumnSize(Column: integer): integer;
begin
  Result := Column - FirstValueColumn;
  if (Result < 0) or (Result >= ValueColumns) then
    Result := -1;
end;

function TMeasurementsForm.CurrentSize: integer;
begin
  Result := -1;
  if FDocument.Measurements.SizeCount > 0 then
    Result := ColumnSize(FGrid.Col);
end;

function TMeasurementsForm.CellText(Row, Column: integer): string;
var
  Measurement: TMeasurement;
  Size: integer;
begin
  Measurement := FDocument.Measurements[Row];
  Size := ColumnSize(Column);
  if Column = KeyColumn then
    Result := Measurement.Key
  else if Column = DescriptionColumn then
    Result := Measurement.Description
  else if Measurement.HasValueFor(Size) then
    Result := FormatMeasure(Measurement.ValueFor(Size), FUnit)
  else
    Result := '';
end;

procedure TMeasurementsForm.RefreshGrid;
var
  Row, Column, Size: integer;
  Table: TMeasurementSet;
begin
  Table := FDocument.Measurements;
  FRefreshing := True;
  try
    FGrid.EditorMode := False;
    FGrid.ColCount := DescriptionColumn + 1;
    FGrid.RowCount := FGrid.FixedRows + Max(Table.Count, 0);
    FGrid.ColWidths[KeyColumn] := KeyColumnWidth;
    FGrid.Cells[KeyColumn, 0] := rsColumnKey;
    for Size := 0 to ValueColumns - 1 do
    begin
      FGrid.ColWidths[FirstValueColumn + Size] := ValueColumnWidth;
      if Table.SizeCount > 0 then
        FGrid.Cells[FirstValueColumn + Size, 0] := Table.Sizes[Size]
      else
        FGrid.Cells[FirstValueColumn + Size, 0] := rsColumnValue;
    end;
    FGrid.ColWidths[DescriptionColumn] := DescriptionColumnWidth;
    FGrid.Cells[DescriptionColumn, 0] := rsColumnDescription;
    for Row := 0 to Table.Count - 1 do
      for Column := 0 to DescriptionColumn do
        FGrid.Cells[Column, FGrid.FixedRows + Row] := CellText(Row, Column);
  finally
    FRefreshing := False;
  end;
end;

procedure TMeasurementsForm.RefreshAll;
const
  ModifiedMark: array[boolean] of string = ('', '*');
var
  FileTitle: string;
begin
  RefreshGrid;
  RefreshEntries;
  RefreshFigure;
  RefreshMissing;
  ShowEntry(SelectedKey);
  FRefreshing := True;
  try
    if not FNameEdit.Focused then
      FNameEdit.Text := FDocument.Measurements.Name;
    if not FNotesEdit.Focused then
      FNotesEdit.Text := FDocument.Measurements.Notes;
  finally
    FRefreshing := False;
  end;
  FUndoAction.Enabled := FDocument.CanUndo;
  if FDocument.CanUndo then
    FUndoAction.Caption := Format(rsMenuUndoNamed, [FDocument.UndoDescription])
  else
    FUndoAction.Caption := rsMenuUndo;
  SetActionHint(FUndoAction);
  FRedoAction.Enabled := FDocument.CanRedo;
  FileTitle := ExtractFileName(FDocument.FileName);
  if FileTitle = '' then
    FileTitle := rsUntitled;
  Caption := Format(rsMeasurementsTitleFile, [FileTitle, ModifiedMark[FDocument.Modified]]);
end;

// A change made while the grid is finishing an edit is drawn once it has
procedure TMeasurementsForm.DocumentChanged(Sender: TObject);
begin
  Application.QueueAsyncCall(@RefreshLater, 0);
end;

procedure TMeasurementsForm.RefreshLater(Data: PtrInt);
begin
  RefreshAll;
end;

procedure TMeasurementsForm.SelectCell(Index, Column: integer);
begin
  if Index < 0 then
    Exit;
  RefreshAll;
  FGrid.Row := FGrid.FixedRows + Index;
  FGrid.Col := Min(Column, DescriptionColumn);
end;

function TMeasurementsForm.CommitCell(Column, Index: integer; const NewText: string): boolean;
var
  OldKey, Reason: string;
  Value: double;
  Size: integer;
begin
  Reason := '';
  Result := True;
  if Column = KeyColumn then
  begin
    OldKey := FDocument.Measurements[Index].Key;
    Result := FDocument.RenameKey(Index, Trim(NewText), Reason);
    if Result then
      ShowStatus(Format(rsRenamed, [Trim(NewText), OldKey]));
  end
  else if Column = DescriptionColumn then
    FDocument.SetDescription(Index, NewText)
  else
  begin
    Size := ColumnSize(Column);
    if Trim(NewText) = '' then
      Result := FDocument.ClearValue(Index, Size, Reason)
    else
    begin
      Result := ParseMeasure(NewText, FUnit, Value);
      if Result then
      begin
        FDocument.SetValue(Index, Size, Value);
        WarnRange(Index, Value);
      end
      else
        Reason := rsBadValue;
    end;
  end;
  if not Result then
    ShowRefusal(Reason);
end;

// An unchanged cell is left alone, so moving through a table in inches does
// not round its values
procedure TMeasurementsForm.GridValidate(Sender: TObject; ACol, ARow: integer; const OldValue: string; var NewValue: string);
var
  Index: integer;
begin
  Index := RowIndex(ARow);
  if FRefreshing or (Index < 0) or (NewValue = OldValue) then
    Exit;
  if not CommitCell(ACol, Index, NewValue) then
    NewValue := OldValue;
end;

// Keys are checked as they are typed; the edit itself is made on leaving the cell
procedure TMeasurementsForm.GridEditText(Sender: TObject; ACol, ARow: integer; const Value: string);
var
  Index: integer;
  Reason: string;
begin
  Index := RowIndex(ARow);
  if FRefreshing or (Index < 0) or (ACol <> KeyColumn) then
    Exit;
  if FDocument.Measurements.CheckKey(Trim(Value), FDocument.Measurements[Index], Reason) then
    ShowStatus('')
  else
    ShowStatus(Reason);
end;

procedure TMeasurementsForm.HeaderDone(Sender: TObject);
begin
  if FRefreshing then
    Exit;
  if FNameEdit.Text <> FDocument.Measurements.Name then
    FDocument.SetName(FNameEdit.Text);
  if FNotesEdit.Text <> FDocument.Measurements.Notes then
    FDocument.SetNotes(FNotesEdit.Text);
end;

procedure TMeasurementsForm.UnitChange(Sender: TObject);
begin
  FUnit := TMeasureUnit(FUnitBox.ItemIndex);
  SaveUnit;
  RefreshAll;
end;

procedure TMeasurementsForm.LoadUnit;
begin
  FUnit := UserPreferences.MeasureUnit;
end;

// The unit is the user's preference, which the other apps share
procedure TMeasurementsForm.SaveUnit;
var
  Preferences: TPreferences;
  Reason: string;
begin
  Preferences := UserPreferences;
  Preferences.MeasureUnit := FUnit;
  SaveUserPreferences(Preferences, Reason);
end;

procedure TMeasurementsForm.WatchTick(Sender: TObject);
begin
  // Taking in a change now would lose what is being typed
  if FAnswering or Assigned(FGrid.Editor) and (FGrid.Cells[FGrid.Col, FGrid.Row] <> FGrid.Editor.Caption) then
    Exit;
  if FDocument.CheckPattern then
    ShowStatus(Format(rsPatternReread, [ExtractFileName(FDocument.PatternFile)]));
  case FDocument.CheckFile of
    fcReloaded: ShowStatus(rsFileReloaded);
    fcMerged: ShowStatus(rsFileMerged);
    fcConflict: AnswerConflicts;
    else;
  end;
end;

procedure TMeasurementsForm.AnswerConflicts;
var
  Conflict: string;
  TakeTheirs: TStringArray;
begin
  FAnswering := True;
  try
    TakeTheirs := nil;
    for Conflict in FDocument.Conflicts do
      if MessageDlg(Format(rsConflictQuestion, [Conflict]), mtConfirmation, [mbYes, mbNo], 0) = mrNo then
        Insert(Conflict, TakeTheirs, Length(TakeTheirs));
    FDocument.ResolveConflicts(TakeTheirs);
    ShowStatus(rsConflictsAnswered);
  finally
    FAnswering := False;
  end;
end;

procedure TMeasurementsForm.ShowStatus(const AText: string);
begin
  FStatus.SimpleText := AText;
end;

procedure TMeasurementsForm.ShowRefusal(const Reason: string);
begin
  ShowStatus(Reason);
  Beep;
end;

function TMeasurementsForm.ConfirmDiscard: boolean;
begin
  Result := not FDocument.Modified or (MessageDlg(rsDiscardQuestion, mtConfirmation, [mbYes, mbNo], 0) = mrYes);
end;

procedure TMeasurementsForm.CloseAsked(Sender: TObject; var CanClose: boolean);
begin
  FGrid.EditingDone;
  CanClose := ConfirmDiscard;
end;

procedure TMeasurementsForm.NewClick(Sender: TObject);
begin
  if ConfirmDiscard then
    FDocument.New;
end;

procedure TMeasurementsForm.OpenPath(const Path: string);
var
  Reason: string;
begin
  if FDocument.Open(Path, Reason) then
    FRecent.Remember(Path)
  else
    MessageDlg(Format(rsOpenFailed, [Path, Reason]), mtError, [mbOK], 0);
end;

procedure TMeasurementsForm.RecentOpen(Sender: TObject; const FileName: string);
begin
  FGrid.EditingDone;
  if ConfirmDiscard then
    OpenPath(FileName);
end;

procedure TMeasurementsForm.OpenClick(Sender: TObject);
var
  Dialog: TOpenDialog;
begin
  if not ConfirmDiscard then
    Exit;
  Dialog := TOpenDialog.Create(Self);
  try
    Dialog.Filter := rsFilter;
    if Dialog.Execute then
      OpenPath(Dialog.FileName);
  finally
    FreeAndNil(Dialog);
  end;
end;

function TMeasurementsForm.SaveTo(const FileName: string): boolean;
var
  Reason: string;
begin
  Result := FDocument.Save(FileName, Reason);
  if Result then
  begin
    ShowStatus(Format(rsSaved, [FileName]));
    FRecent.Remember(FileName);
  end
  else
    MessageDlg(Format(rsSaveFailed, [FileName, Reason]), mtError, [mbOK], 0);
end;

procedure TMeasurementsForm.SaveClick(Sender: TObject);
begin
  FGrid.EditingDone;
  HeaderDone(Sender);
  if FDocument.FileName = '' then
    SaveAsClick(Sender)
  else
    SaveTo(FDocument.FileName);
end;

procedure TMeasurementsForm.SaveAsClick(Sender: TObject);
var
  Dialog: TSaveDialog;
begin
  FGrid.EditingDone;
  HeaderDone(Sender);
  Dialog := TSaveDialog.Create(Self);
  try
    Dialog.Filter := rsFilter;
    Dialog.DefaultExt := MeasurementExtension;
    Dialog.FileName := FDocument.FileName;
    Dialog.Options := Dialog.Options + [ofOverwritePrompt];
    if Dialog.Execute then
      SaveTo(Dialog.FileName);
  finally
    FreeAndNil(Dialog);
  end;
end;

// So nothing is altered silently, whatever changed on the way is shown
procedure TMeasurementsForm.ShowReport(const ATitle: string; const Lines: TStrings);
var
  Window: TForm;
  Body: TMemo;
  Button: TButton;
begin
  Window := TForm.CreateNew(Self);
  try
    Window.Caption := ATitle;
    Window.Width := ReportWidth;
    Window.Height := ReportHeight;
    Window.Position := poOwnerFormCenter;
    Button := TButton.Create(Window);
    Button.Parent := Window;
    Button.Align := alBottom;
    Button.BorderSpacing.Around := SideGap;
    Button.Caption := rsClose;
    Button.ModalResult := mrClose;
    Body := TMemo.Create(Window);
    Body.Parent := Window;
    Body.Align := alClient;
    Body.ReadOnly := True;
    Body.ScrollBars := ssAutoBoth;
    Body.BorderSpacing.Around := SideGap;
    Body.Lines.Assign(Lines);
    Window.ShowModal;
  finally
    FreeAndNil(Window);
  end;
end;

procedure TMeasurementsForm.ImportPath(const Path: string);
var
  Imported: TMeasurementSet;
  Report: TImportReport;
  Reason: string;
  Lines: TStringList;

  procedure AddSection(const Heading: string; const Section: TStringArray);
  var
    Line: string;
  begin
    if Length(Section) = 0 then
      Exit;
    Lines.Add('');
    Lines.Add(Heading);
    for Line in Section do
      Lines.Add('  ' + Line);
  end;

begin
  Lines := nil;
  Imported := TMeasurementSet.Create;
  try
    if not ImportSeamlyFile(Path, FCatalogue, Imported, Report, Reason) then
    begin
      MessageDlg(Format(rsImportFailed, [Path, Reason]), mtError, [mbOK], 0);
      Exit;
    end;
    FDocument.TakeImported(Imported);
    Lines := TStringList.Create;
    Lines.Add(Format(rsImportCounts, [Imported.Count, Length(Report.Translated), Length(Report.Kept), Length(Report.Corrected)]));
    AddSection(rsImportNotes, Report.Notes);
    AddSection(rsImportCorrected, Report.Corrected);
    AddSection(rsImportKept, Report.Kept);
    AddSection(rsImportTranslated, Report.Translated);
    ShowReport(Format(rsImportTitle, [ExtractFileName(Path)]), Lines);
  finally
    FreeAndNil(Lines);
    FreeAndNil(Imported);
  end;
end;

procedure TMeasurementsForm.ImportClick(Sender: TObject);
var
  Dialog: TOpenDialog;
begin
  if not ConfirmDiscard then
    Exit;
  Dialog := TOpenDialog.Create(Self);
  try
    Dialog.Filter := rsFilterImport;
    if Dialog.Execute then
      ImportPath(Dialog.FileName);
  finally
    FreeAndNil(Dialog);
  end;
end;

// An individual file holds one size: the column the cursor is in
procedure TMeasurementsForm.ExportClick(Sender: TObject);
var
  Dialog: TSaveDialog;
  Notes: TStringArray;
  Reason: string;
  Lines: TStringList;
begin
  FGrid.EditingDone;
  HeaderDone(Sender);
  if CurrentSize >= 0 then
    FDocument.Measurements.SelectSize(FDocument.Measurements.Sizes[CurrentSize]);
  Lines := nil;
  Dialog := TSaveDialog.Create(Self);
  try
    if FDocument.Measurements.SizeCount > 0 then
      Dialog.Filter := rsFilterExportTable
    else
      Dialog.Filter := rsFilterExportSet;
    Dialog.Options := Dialog.Options + [ofOverwritePrompt];
    Dialog.DefaultExt := 'smis';
    if FDocument.Measurements.SizeCount > 0 then
      Dialog.DefaultExt := 'smms';
    if not Dialog.Execute then
      Exit;
    if not ExportSeamlyFile(Dialog.FileName, FCatalogue, FDocument.Measurements, Notes, Reason) then
    begin
      MessageDlg(Format(rsExportFailed, [Dialog.FileName, Reason]), mtError, [mbOK], 0);
      Exit;
    end;
    ShowStatus(Format(rsSaved, [Dialog.FileName]));
    if Length(Notes) > 0 then
    begin
      Lines := TStringList.Create;
      Lines.AddStrings(Notes);
      ShowReport(Format(rsExportTitle, [ExtractFileName(Dialog.FileName)]), Lines);
    end;
  finally
    FreeAndNil(Lines);
    FreeAndNil(Dialog);
  end;
end;

procedure TMeasurementsForm.QuitClick(Sender: TObject);
begin
  Close;
end;

procedure TMeasurementsForm.UndoClick(Sender: TObject);
begin
  FDocument.Undo;
end;

procedure TMeasurementsForm.RedoClick(Sender: TObject);
begin
  FDocument.Redo;
end;

procedure TMeasurementsForm.AddClick(Sender: TObject);
begin
  FDocument.AddMeasurement;
  SelectCell(FDocument.Measurements.Count - 1, KeyColumn);
  FGrid.SetFocus;
end;

procedure TMeasurementsForm.DeleteClick(Sender: TObject);
var
  Index: integer;
begin
  Index := RowIndex(FGrid.Row);
  if Index < 0 then
    ShowRefusal(rsChooseAMeasurement)
  else if MessageDlg(Format(rsDeleteQuestion, [FDocument.Measurements[Index].Key]), mtConfirmation, [mbYes, mbNo], 0) = mrYes then
    FDocument.DeleteMeasurement(Index);
end;

procedure TMeasurementsForm.UpClick(Sender: TObject);
var
  Index: integer;
begin
  Index := RowIndex(FGrid.Row);
  if Index > 0 then
  begin
    FDocument.MoveMeasurement(Index, Index - 1);
    SelectCell(Index - 1, FGrid.Col);
  end;
end;

procedure TMeasurementsForm.DownClick(Sender: TObject);
var
  Index: integer;
begin
  Index := RowIndex(FGrid.Row);
  if (Index >= 0) and (Index < FDocument.Measurements.Count - 1) then
  begin
    FDocument.MoveMeasurement(Index, Index + 1);
    SelectCell(Index + 1, FGrid.Col);
  end;
end;

procedure TMeasurementsForm.AddSizeClick(Sender: TObject);
var
  Size, Reason: string;
begin
  Size := '';
  if InputQuery(rsAddSizeTitle, rsSizePrompt, Size) and not FDocument.AddSize(Size, Reason) then
    ShowRefusal(Reason);
end;

procedure TMeasurementsForm.RenameSizeClick(Sender: TObject);
var
  Index: integer;
  Size, Reason: string;
begin
  Index := CurrentSize;
  if Index < 0 then
  begin
    ShowRefusal(rsChooseASize);
    Exit;
  end;
  Size := FDocument.Measurements.Sizes[Index];
  if InputQuery(Format(rsRenameSizeTitle, [Size]), rsSizePrompt, Size) and not FDocument.RenameSize(Index, Size, Reason) then
    ShowRefusal(Reason);
end;

procedure TMeasurementsForm.DeleteSizeClick(Sender: TObject);
var
  Index: integer;
  Reason: string;
begin
  Index := CurrentSize;
  if Index < 0 then
    ShowRefusal(rsChooseASize)
  else if (MessageDlg(Format(rsDeleteSizeQuestion, [FDocument.Measurements.Sizes[Index]]), mtConfirmation, [mbYes, mbNo], 0) = mrYes) and
    not FDocument.DeleteSize(Index, Reason) then
    ShowRefusal(Reason);
end;

procedure TMeasurementsForm.SizeLeftClick(Sender: TObject);
var
  Index: integer;
begin
  Index := CurrentSize;
  if Index > 0 then
  begin
    FDocument.MoveSize(Index, Index - 1);
    SelectCell(RowIndex(FGrid.Row), FGrid.Col - 1);
  end;
end;

procedure TMeasurementsForm.SizeRightClick(Sender: TObject);
var
  Index: integer;
begin
  Index := CurrentSize;
  if (Index >= 0) and (Index < FDocument.Measurements.SizeCount - 1) then
  begin
    FDocument.MoveSize(Index, Index + 1);
    SelectCell(RowIndex(FGrid.Row), FGrid.Col + 1);
  end;
end;

procedure TMeasurementsForm.AboutClick(Sender: TObject);
begin
  ShowAboutDialog(Self, rsMeasurementsTitle, rsAboutSummary);
end;

procedure TMeasurementsForm.PreferencesClick(Sender: TObject);
var
  Preferences: TPreferences;
begin
  if not EditPreferences(Self, ptGeneral, Preferences) then
    Exit;
  FUnit := Preferences.MeasureUnit;
  FUnitBox.ItemIndex := Ord(FUnit);
  RefreshAll;
end;

end.
