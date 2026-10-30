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
  Classes, SysUtils, Forms, Controls, Menus, Dialogs, ComCtrls, ExtCtrls, LCLType, Sloper.Core.Geometry,
  Sloper.Core.Settings, Sloper.Document.PatternDocument, Sloper.UI.Canvas, Sloper.UI.Properties;

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
    FLabelItems: array[TLabelMode] of TMenuItem;
    FCanvas: TPatternCanvas;
    FProperties: TPropertiesPanel;
    FSplitter: TSplitter;
    FToolBar: TToolBar;
    FToolButtons: array[TCanvasTool] of TToolButton;
    FToolItems: array[TCanvasTool] of TMenuItem;
    FShown: boolean;
    procedure LoadSettings;
    procedure SaveSettings;
    procedure SetLabelMode(Mode: TLabelMode);
    procedure CreateLabelMenu;
    procedure LabelModeClick(Sender: TObject);
    procedure CreateTools;
    procedure ToolClick(Sender: TObject);
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
  Math, Sloper.Core.Version, Sloper.Core.AppPaths, Sloper.Core.PatternCheck;

  {$R *.lfm}

const
  PanelCursor = 0;
  PanelProblems = 1;
  PanelMeasurements = 2;
  PanelMessage = 3;

resourcestring
  rsMenuFile = '&File';
  rsMenuFileNew = '&New';
  rsMenuFileOpen = '&Open...';
  rsMenuFileSave = '&Save';
  rsMenuFileSaveAs = 'Save &As...';
  rsMenuFileMeasurements = '&Measurements...';
  rsMenuFileQuit = '&Quit';
  rsMenuEdit = '&Edit';
  rsMenuEditUndo = '&Undo';
  rsMenuEditUndoWhat = '&Undo %s';
  rsMenuEditRedo = '&Redo';
  rsMenuEditRedoWhat = '&Redo %s';
  rsMenuEditDelete = '&Delete';
  rsMenuView = '&View';
  rsMenuViewZoomIn = 'Zoom &In';
  rsMenuViewZoomOut = 'Zoom &Out';
  rsMenuViewFit = '&Fit Pattern';
  rsMenuViewTrueSize = '&True Size';
  rsMenuViewLabels = '&Labels';
  rsLabelsContextual = '&Contextual';
  rsLabelsAll = '&All (hold N)';
  rsLabelsNone = '&None';
  rsMenuTools = '&Tools';
  rsToolSelect = 'Select';
  rsToolPoint = 'Point';
  rsToolLine = 'Line';
  rsToolCurve = 'Curve';
  rsToolKey = '%s (%s)';
  rsMenuHelp = '&Help';
  rsMenuHelpAbout = '&About OpenSloper';
  rsAboutText = '%s %s'#10#10 + 'Parametric sewing pattern drafting.'#10#10 + 'This program is free software: you can redistribute it and/or modify ' +
    'it under the terms of the GNU General Public License as published by ' + 'the Free Software Foundation, either version 3 of the License, or ' +
    '(at your option) any later version.'#10#10 + 'This program comes with ABSOLUTELY NO WARRANTY.';
  rsUntitled = 'Untitled';
  rsTitle = '%s%s - %s';
  rsPatternFilter = 'OpenSloper patterns (*.sloper)|*.sloper|All files|%s';
  rsMeasurementFilter = 'Measurement sets (*.slm)|*.slm|All files|%s';
  rsSaveChanges = 'Save the changes to %s?';
  rsOpenFailed = 'Could not open %s:'#10'%s';
  rsSaveFailed = 'Could not save %s:'#10'%s';
  rsMeasurementsFailed = 'Could not use %s:'#10'%s';
  rsMeasurementsMissing = 'The pattern opened, but its measurements could not be loaded:'#10'%s';
  rsCursorAt = 'x %.1f   y %.1f mm';
  rsNoProblems = 'No problems';
  rsProblems = 'Problems: %d';
  rsNoMeasurements = 'No measurement set';

  { TMainForm }

procedure TMainForm.FormCreate(Sender: TObject);
begin
  MenuFile.Caption := rsMenuFile;
  MenuFileNew.Caption := rsMenuFileNew;
  MenuFileNew.ShortCut := ShortCut(VK_N, [ssModifier]);
  MenuFileOpen.Caption := rsMenuFileOpen;
  MenuFileOpen.ShortCut := ShortCut(VK_O, [ssModifier]);
  MenuFileSave.Caption := rsMenuFileSave;
  MenuFileSave.ShortCut := ShortCut(VK_S, [ssModifier]);
  MenuFileSaveAs.Caption := rsMenuFileSaveAs;
  MenuFileSaveAs.ShortCut := ShortCut(VK_S, [ssModifier, ssShift]);
  MenuFileMeasurements.Caption := rsMenuFileMeasurements;
  MenuFileMeasurements.ShortCut := ShortCut(VK_M, [ssModifier]);
  MenuFileQuit.Caption := rsMenuFileQuit;
  MenuFileQuit.ShortCut := ShortCut(VK_Q, [ssModifier]);
  MenuEdit.Caption := rsMenuEdit;
  MenuEditUndo.ShortCut := ShortCut(VK_Z, [ssModifier]);
  MenuEditRedo.ShortCut := ShortCut(VK_Z, [ssModifier, ssShift]);
  // The canvas handles the Delete key, so typing in a field can still delete text
  MenuEditDelete.Caption := rsMenuEditDelete;
  MenuView.Caption := rsMenuView;
  MenuViewZoomIn.Caption := rsMenuViewZoomIn;
  MenuViewZoomIn.ShortCut := ShortCut(VK_OEM_PLUS, [ssModifier]);
  MenuViewZoomOut.Caption := rsMenuViewZoomOut;
  MenuViewZoomOut.ShortCut := ShortCut(VK_OEM_MINUS, [ssModifier]);
  MenuViewFit.Caption := rsMenuViewFit;
  MenuViewFit.ShortCut := ShortCut(VK_0, [ssModifier]);
  MenuViewTrueSize.Caption := rsMenuViewTrueSize;
  MenuViewTrueSize.ShortCut := ShortCut(VK_1, [ssModifier]);
  MenuHelp.Caption := rsMenuHelp;
  MenuHelpAbout.Caption := rsMenuHelpAbout;

  OpenDialog.Filter := Format(rsPatternFilter, [AllFilesMask]);
  SaveDialog.Filter := OpenDialog.Filter;
  SaveDialog.DefaultExt := 'sloper';
  MeasurementsDialog.Filter := Format(rsMeasurementFilter, [AllFilesMask]);
  OpenDialog.InitialDir := TAppPaths.DefaultDocumentsDir;
  SaveDialog.InitialDir := OpenDialog.InitialDir;
  MeasurementsDialog.InitialDir := OpenDialog.InitialDir;

  FDocument := TPatternDocument.Create;
  CreateTools;
  FProperties := TPropertiesPanel.Create(Self);
  FProperties.Parent := Self;
  FProperties.Align := alRight;
  FProperties.Width := Scale96ToForm(280);
  FProperties.Document := FDocument;
  LoadSettings;
  FSplitter := TSplitter.Create(Self);
  FSplitter.Parent := Self;
  FSplitter.Align := alRight;
  FSplitter.Left := FProperties.Left - FSplitter.Width;
  FCanvas := TPatternCanvas.Create(Self);
  FCanvas.Parent := Self;
  FCanvas.Align := alClient;
  FCanvas.Document := FDocument;
  FCanvas.OnCursorMove := @CanvasCursorMove;
  FCanvas.OnMessage := @CanvasMessage;
  FCanvas.OnToolChange := @CanvasToolChange;
  FCanvas.OnSelectionChange := @CanvasSelectionChange;
  CreateLabelMenu;
  SetLabelMode(FSettings.LabelMode);
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
end;

procedure TMainForm.SaveSettings;
var
  Err: string;
begin
  FSettings.NameColumnShare := FProperties.NameShare;
  FSettings.LabelMode := FCanvas.LabelMode;
  TAppPaths.ForceDir(TAppPaths.ConfigDir);
  FSettings.SaveToFile(TAppPaths.SettingsFile, Err);
end;

procedure TMainForm.SetLabelMode(Mode: TLabelMode);
begin
  FCanvas.LabelMode := Mode;
  FLabelItems[Mode].Checked := True;
end;

// The label modes in the View menu; each item's Tag is its TLabelMode
procedure TMainForm.CreateLabelMenu;
var
  MenuLabels: TMenuItem;
  Mode: TLabelMode;
  Captions: array[TLabelMode] of string;
begin
  Captions[lmContextual] := rsLabelsContextual;
  Captions[lmAll] := rsLabelsAll;
  Captions[lmNone] := rsLabelsNone;
  MenuLabels := TMenuItem.Create(MainMenu);
  MenuLabels.Caption := rsMenuViewLabels;
  MenuView.Add(NewLine);
  MenuView.Add(MenuLabels);
  for Mode := Low(TLabelMode) to High(TLabelMode) do
  begin
    FLabelItems[Mode] := TMenuItem.Create(MenuLabels);
    FLabelItems[Mode].Caption := Captions[Mode];
    FLabelItems[Mode].RadioItem := True;
    FLabelItems[Mode].GroupIndex := 2;
    FLabelItems[Mode].Tag := Ord(Mode);
    FLabelItems[Mode].OnClick := @LabelModeClick;
    MenuLabels.Add(FLabelItems[Mode]);
  end;
end;

procedure TMainForm.LabelModeClick(Sender: TObject);
begin
  SetLabelMode(TLabelMode(TComponent(Sender).Tag));
end;

// The toolbar and Tools menu; each item's Tag is its TCanvasTool
procedure TMainForm.CreateTools;
const
  Keys: array[TCanvasTool] of string = ('S', 'P', 'L', 'C');
var
  MenuTools: TMenuItem;
  Tool: TCanvasTool;
  Captions: array[TCanvasTool] of string;
begin
  Captions[ctSelect] := rsToolSelect;
  Captions[ctPoint] := rsToolPoint;
  Captions[ctLine] := rsToolLine;
  Captions[ctCurve] := rsToolCurve;
  FToolBar := TToolBar.Create(Self);
  FToolBar.Parent := Self;
  FToolBar.Align := alTop;
  FToolBar.ShowCaptions := True;
  FToolBar.List := True;
  FToolBar.AutoSize := True;
  MenuTools := TMenuItem.Create(MainMenu);
  MenuTools.Caption := rsMenuTools;
  MainMenu.Items.Insert(MainMenu.Items.IndexOf(MenuHelp), MenuTools);
  for Tool := Low(TCanvasTool) to High(TCanvasTool) do
  begin
    FToolButtons[Tool] := TToolButton.Create(FToolBar);
    FToolButtons[Tool].Parent := FToolBar;
    FToolButtons[Tool].Caption := Captions[Tool];
    FToolButtons[Tool].Hint := Format(rsToolKey, [Captions[Tool], Keys[Tool]]);
    FToolButtons[Tool].ShowHint := True;
    FToolButtons[Tool].Style := tbsCheck;
    FToolButtons[Tool].Grouped := True;
    FToolButtons[Tool].Tag := Ord(Tool);
    FToolButtons[Tool].OnClick := @ToolClick;
  end;
  for Tool := Low(TCanvasTool) to High(TCanvasTool) do
  begin
    FToolItems[Tool] := TMenuItem.Create(MenuTools);
    FToolItems[Tool].Caption := Format(rsToolKey, [Captions[Tool], Keys[Tool]]);
    FToolItems[Tool].RadioItem := True;
    FToolItems[Tool].GroupIndex := 1;
    FToolItems[Tool].Tag := Ord(Tool);
    FToolItems[Tool].OnClick := @ToolClick;
    MenuTools.Add(FToolItems[Tool]);
  end;
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
  begin
    FToolButtons[Tool].Down := Tool = FCanvas.Tool;
    FToolItems[Tool].Checked := Tool = FCanvas.Tool;
  end;
end;

procedure TMainForm.CanvasSelectionChange(Sender: TObject);
begin
  FProperties.ShowSelection(FCanvas.Selection);
end;

procedure TMainForm.FormDestroy(Sender: TObject);
begin
  SaveSettings;
  FreeAndNil(FSettings);
  // The canvas and panel listen to the document, so they let go first
  FCanvas.Document := nil;
  FProperties.Document := nil;
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
  if dcFile in Changes then
    UpdateTitle;
  UpdateMenus;
  UpdateStatus;
end;

procedure TMainForm.CanvasCursorMove(Sender: TObject; const ModelPos: TVec2);
begin
  StatusBar.Panels[PanelCursor].Text := Format(rsCursorAt, [ModelPos.X, ModelPos.Y]);
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

procedure TMainForm.UpdateMenus;
begin
  MenuEditUndo.Enabled := FDocument.CanUndo;
  if FDocument.CanUndo then
    MenuEditUndo.Caption := Format(rsMenuEditUndoWhat, [FDocument.UndoDescription])
  else
    MenuEditUndo.Caption := rsMenuEditUndo;
  MenuEditRedo.Enabled := FDocument.CanRedo;
  if FDocument.CanRedo then
    MenuEditRedo.Caption := Format(rsMenuEditRedoWhat, [FDocument.RedoDescription])
  else
    MenuEditRedo.Caption := rsMenuEditRedo;
end;

procedure TMainForm.UpdateStatus;
var
  Problems: TStringArray;
  BlockedCount: integer;
begin
  Problems := PatternProblems(FDocument.Pattern, BlockedCount);
  if Length(Problems) = 0 then
    StatusBar.Panels[PanelProblems].Text := rsNoProblems
  else
    StatusBar.Panels[PanelProblems].Text := Format(rsProblems, [Length(Problems)]);
  if FDocument.Measurements = nil then
    StatusBar.Panels[PanelMeasurements].Text := rsNoMeasurements
  else if FDocument.Measurements.Name <> '' then
    StatusBar.Panels[PanelMeasurements].Text := FDocument.Measurements.Name
  else
    StatusBar.Panels[PanelMeasurements].Text := ExtractFileName(FDocument.MeasurementPath);
end;

function TMainForm.ConfirmDiscard: boolean;
begin
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
  FCanvas.SelectNone;
  FCanvas.ZoomToFit;
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
  if not Result then
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
  if not Result then
    MessageDlg(Format(rsSaveFailed, [SaveDialog.FileName, Err]), mtError, [mbOK], 0);
end;

procedure TMainForm.MenuFileNewClick(Sender: TObject);
begin
  if not ConfirmDiscard then
    Exit;
  FDocument.NewPattern;
  FCanvas.SelectNone;
  FCanvas.ZoomToFit;
end;

procedure TMainForm.MenuFileOpenClick(Sender: TObject);
begin
  if ConfirmDiscard and OpenDialog.Execute then
    OpenFile(OpenDialog.FileName);
end;

procedure TMainForm.MenuFileSaveClick(Sender: TObject);
begin
  Save;
end;

procedure TMainForm.MenuFileSaveAsClick(Sender: TObject);
begin
  SaveAs;
end;

procedure TMainForm.MenuFileMeasurementsClick(Sender: TObject);
var
  Err: string;
begin
  if not MeasurementsDialog.Execute then
    Exit;
  if not FDocument.UseMeasurements(MeasurementsDialog.FileName, Err) then
    MessageDlg(Format(rsMeasurementsFailed, [MeasurementsDialog.FileName, Err]), mtError, [mbOK], 0);
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
  MessageDlg(Format(rsAboutText, [AppName, AppVersion]), mtInformation, [mbOK], 0);
end;

end.
