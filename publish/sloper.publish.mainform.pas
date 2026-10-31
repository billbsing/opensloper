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
    FSide: TPanel;
    FStatus: TStatusBar;
    FPaperBox: TComboBox;
    FMarginEdit, FOverlapEdit, FCalibrationXEdit, FCalibrationYEdit: TFloatSpinEdit;
    FProblems: TListBox;
    FTurnButton, FFlipButton: TButton;
    FUndoItem, FRedoItem: TMenuItem;
    FRefreshing: boolean;
    // Rows stack in the order their Top says, so each takes the next one
    FNextRowTop: integer;
    procedure PlaceRow(Row: TControl);
    procedure BuildMenu;
    procedure BuildSide;
    function AddSpin(const ACaption: string; AMax, AIncrement: double; Decimals: integer): TFloatSpinEdit;
    procedure AddLabel(const ACaption: string);
    function AddButton(const ACaption: string; AHandler: TNotifyEvent): TButton;
    procedure DocumentChanged(Sender: TObject);
    procedure SelectionChanged(Sender: TObject);
    procedure RefreshControls;
    procedure RefreshProblems;
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
  rsPaper = 'Paper';
  rsMargin = 'Margin (mm)';
  rsOverlap = 'Overlap (mm)';
  rsCalibrationX = 'Calibration across';
  rsCalibrationY = 'Calibration down';
  rsProblems = 'Problems';
  rsNoProblems = 'No problems';
  rsPlaceNew = 'Place new pieces';
  rsTurn = 'Turn 180°';
  rsFlip = 'Flip';
  rsExportPDF = 'Export PDF...';
  rsChangeSettings = 'Change paper';
  rsPlaceChange = 'Place new pieces';
  rsTurnChange = 'Turn piece';
  rsFlipChange = 'Flip piece';
  rsDiscardQuestion = 'Discard the changes to this layout?';
  rsPages = '%d pages, %d blank';
  rsExported = 'Wrote %s';
  rsFilterOpen = 'Layouts and patterns (*.slayout;*.sloper)|*.slayout;*.sloper';
  rsFilterLayout = 'Layouts (*.slayout)|*.slayout';
  rsFilterPDF = 'PDF (*.pdf)|*.pdf';

implementation

uses
  LCLType, Sloper.Output.LayoutPDF, Sloper.Output.Tiling;

const
  SideWidth = 260;
  SideGap = 6;
  SideRowStep = 100;
  SpinDecimals = 1;
  CalibrationDecimals = 3;
  MaxMillimetres = 100;
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
  FSide := TPanel.Create(Self);
  FSide.Parent := Self;
  FSide.Align := alRight;
  FSide.Width := SideWidth;
  FSide.BevelOuter := bvNone;
  FSide.BorderSpacing.Around := SideGap;
  FPreview := TPreviewCanvas.Create(Self);
  FPreview.Parent := Self;
  FPreview.Align := alClient;
  FPreview.Document := FDocument;
  FPreview.OnSelectionChange := @SelectionChanged;
  BuildSide;
  RefreshControls;
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
  Row.Parent := FSide;
end;

procedure TPublishForm.AddLabel(const ACaption: string);
var
  Heading: TLabel;
begin
  Heading := TLabel.Create(Self);
  Heading.Caption := ACaption;
  Heading.BorderSpacing.Top := SideGap;
  PlaceRow(Heading);
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
  FTurnButton := AddButton(rsTurn, @TurnClick);
  FFlipButton := AddButton(rsFlip, @FlipClick);
  AddButton(rsPlaceNew, @PlaceClick);
  AddButton(rsExportPDF, @ExportClick);
  AddLabel(rsProblems);
  FProblems := TListBox.Create(Self);
  FProblems.Parent := FSide;
  FProblems.Align := alClient;
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

procedure TPublishForm.RefreshProblems;
var
  Problem: TLayoutProblem;
begin
  FProblems.Items.BeginUpdate;
  try
    FProblems.Items.Clear;
    for Problem in FDocument.Layout.Problems do
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
  Rows, Columns, Blank: integer;
begin
  FRefreshing := True;
  try
    Layout := FDocument.Layout;
    FPaperBox.ItemIndex := FPaperBox.Items.IndexOf(Layout.Output.Paper);
    FMarginEdit.Value := Layout.Output.Tiles.Margin;
    FOverlapEdit.Value := Layout.Output.Tiles.Overlap;
    FCalibrationXEdit.Value := Layout.Output.CalibrationX;
    FCalibrationYEdit.Value := Layout.Output.CalibrationY;
  finally
    FRefreshing := False;
  end;
  FTurnButton.Enabled := FPreview.Selected >= 0;
  FFlipButton.Enabled := FPreview.Selected >= 0;
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
  Pages := Layout.Pages(Layout.PlacedPieces, Rows, Columns);
  Blank := 0;
  for Page in Pages do
    if Page.Blank then
      Inc(Blank);
  ShowStatus(Format(rsPages, [Length(Pages), Blank]));
end;

// A run of spin clicks is one undo step. A paper that leaves no room to
// print is put back.
procedure TPublishForm.SettingChange(Sender: TObject);
var
  Output: TLayoutOutput;
begin
  if FRefreshing or (FPaperBox.ItemIndex < 0) then
    Exit;
  Output := FDocument.Layout.Output;
  Output.Paper := FPaperBox.Text;
  PaperSize(Output.Paper, Output.Tiles.PaperWidth, Output.Tiles.PaperHeight);
  Output.Tiles.Margin := FMarginEdit.Value;
  Output.Tiles.Overlap := FOverlapEdit.Value;
  Output.CalibrationX := FCalibrationXEdit.Value;
  Output.CalibrationY := FCalibrationYEdit.Value;
  if not TilesAreUsable(Output.Tiles) or (Output.CalibrationX <= 0) or (Output.CalibrationY <= 0) then
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
  FDocument.Layout.Placements[Index].Rotation := (FDocument.Layout.Placements[Index].Rotation + 180) mod 360;
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
