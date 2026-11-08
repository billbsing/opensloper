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

// The measurements tab of the side panel: the current set, with keys the
// pattern needs and the set lacks shown as missing. It allows the small edits
// the design gives the drafting app, in the grid: a value or description, a
// value for a missing key, and a new key from Add. Everything else belongs to
// the measurements app. Edits belong to the file rather than the pattern, so
// they are not undo steps: they are held, marked in bold, until Save writes
// them all at once, or Revert drops them. They do not change the pattern
// until they are saved.

// The Test size slider tries the pattern a size up or down: every measurement
// is scaled by up to 20% either way, 1% a step. Nothing is saved; the values
// shown are the scaled ones. Editing waits until the slider is back at 0%,
// and the slider waits until there are no unsaved edits.
unit Sloper.UI.MeasurementsPanel;

{$mode ObjFPC}{$H+}

interface

uses
  Classes, SysUtils, System.UITypes, Controls, Graphics, StdCtrls, ExtCtrls, ComCtrls, Dialogs, LCLType, Sloper.UI.ListPanel,
  Sloper.UI.PanelEdits;

type
  TMeasurementsPanel = class(TListPanel)
  private
    FFileLabel: TLabel;
    FButtons: TPanel;
    FAddButton, FSaveButton, FRevertButton: TButton;
    FSizeBar: TPanel;
    FSizeBox: TComboBox;
    FTestLabel: TLabel;
    FTestSlider: TTrackBar;
    FTestReset: TButton;
    FTestGroup: TGroupBox;
    FPending: TPendingMeasurements;
    // The file the pending edits are for; another file drops them
    FPendingPath: string;
    // While the slider is being set from the document
    FShowingTest: boolean;
    FOnNewSet: TNotifyEvent;
    function AddButton(Host: TWinControl; const ACaption: string; OnPress: TNotifyEvent): TButton;
    function Testing: boolean;
    procedure UpdateFileLabel;
    procedure UpdateSizes;
    procedure UpdateButtons;
    procedure SizeChange(Sender: TObject);
    procedure BuildTestBar;
    procedure UpdateTest;
    procedure TestChange(Sender: TObject);
    procedure TestResetClick(Sender: TObject);
    procedure AddClick(Sender: TObject);
    procedure SaveClick(Sender: TObject);
    procedure RevertClick(Sender: TObject);
    function PendingRow(Index: integer): TListPanelRow;
  protected
    function BuildRows: TListPanelRowArray; override;
    function CellEditable(const Key: string; Column: integer): boolean; override;
    function CellEditText(const Key: string; Column: integer; const Shown: string): string; override;
    function CommitCell(const Key: string; Column: integer; const AText: string; out Reason: string): boolean; override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    // Writes the unsaved edits to the file; False when they could not be
    function Save: boolean;
    // Drops the unsaved edits
    procedure Revert;
    // Asks whether to save or discard unsaved edits before they would be
    // lost; False when the user cancelled, or saving failed
    function ConfirmPending(CanCancel: boolean = True): boolean;
    function HasPending: boolean;
    // The user wants a new, empty file; saving with no file asks for this first
    property OnNewSet: TNotifyEvent read FOnNewSet write FOnNewSet;
  end;

resourcestring
  rsMeasurementsNoSet = 'No measurement set';
  rsMeasurementsSize = 'Size';
  rsMeasurementsAdd = '&Add';
  rsMeasurementsSave = '&Save';
  rsMeasurementsRevert = '&Revert';
  rsMeasurementsSaveHint = 'Write the edits in bold to the measurement file';
  rsMeasurementsRevertHint = 'Drop the edits in bold';
  rsMeasurementsKey = 'Key';
  rsMeasurementsValue = 'Value (mm)';
  rsMeasurementsDescription = 'Description';
  rsMeasurementsMissing = 'Missing';
  rsMeasurementsEdited = '%s *';
  rsMeasurementsTest = 'Test size: %s';
  rsMeasurementsTestOff = '0%';
  rsMeasurementsTestOn = '%s%%, editing paused';
  rsMeasurementsTestPaused = 'Save or revert the edits to try other sizes';
  rsMeasurementsTestReset = 'R&eset';
  rsMeasurementsTestHint = 'Tries the pattern with every measurement larger or smaller, 1% a step. Nothing is saved.';
  rsMeasurementsTestTitle = 'Test Sizes';
  rsMeasurementsSetTitle = 'Measurement Set';
  rsMeasurementsPendingTitle = 'Unsaved Measurements';
  rsMeasurementsPendingAsk = 'Save the measurement edits to %s?';
  rsMeasurementsPendingNewSet = 'a new measurement set';
  rsMeasurementsPendingSave = 'Save';
  rsMeasurementsPendingDiscard = 'Discard';
  rsMeasurementsPendingCancel = 'Cancel';

implementation

uses
  Sloper.Core.EvalTypes, Sloper.Core.JSON, Sloper.Core.Measurements, Sloper.UI.ObjectList;

const
  // Test size steps, in percent either way
  MaxTestPercent = 20;
  TestTickPercent = 5;

constructor TMeasurementsPanel.Create(AOwner: TComponent);
var
  SetGroup: TGroupBox;
  SizeLabel: TLabel;
begin
  inherited Create(AOwner);
  FPending := TPendingMeasurements.Create;
  // Above the search box
  SetGroup := TGroupBox.Create(Self);
  SetGroup.Parent := FHeader;
  SetGroup.Align := alTop;
  SetGroup.Top := -1;
  SetGroup.BorderSpacing.Bottom := 6;
  SetGroup.AutoSize := True;
  SetGroup.Caption := rsMeasurementsSetTitle;
  SetGroup.ChildSizing.TopBottomSpacing := 8;

  FFileLabel := TLabel.Create(Self);
  FFileLabel.Parent := SetGroup;
  FFileLabel.Align := alTop;
  FFileLabel.Top := -1;
  FFileLabel.Caption := rsMeasurementsNoSet;
  FSizeBar := TPanel.Create(Self);
  FSizeBar.Visible := False;
  FSizeBar.Parent := SetGroup;
  FSizeBar.Align := alTop;
  FSizeBar.Top := 1000;
  FSizeBar.BorderSpacing.Top := 6;
  FSizeBar.BevelOuter := bvNone;
  FSizeBar.AutoSize := True;
  SizeLabel := TLabel.Create(Self);
  SizeLabel.Parent := FSizeBar;
  SizeLabel.Align := alLeft;
  SizeLabel.Layout := tlCenter;
  SizeLabel.BorderSpacing.Right := 6;
  SizeLabel.Caption := rsMeasurementsSize;
  FSizeBox := TComboBox.Create(Self);
  FSizeBox.Parent := FSizeBar;
  FSizeBox.Align := alClient;
  FSizeBox.Style := csDropDownList;
  FSizeBox.OnChange := @SizeChange;

  // The buttons are the bottom row, under the test sizes
  FButtons := TPanel.Create(Self);
  FButtons.Parent := Self;
  FButtons.Align := alBottom;
  FButtons.Top := 200000;
  FButtons.BevelOuter := bvNone;
  FButtons.AutoSize := True;
  FAddButton := AddButton(FButtons, rsMeasurementsAdd, @AddClick);
  FSaveButton := AddButton(FButtons, rsMeasurementsSave, @SaveClick);
  FSaveButton.Hint := rsMeasurementsSaveHint;
  FSaveButton.ShowHint := True;
  FRevertButton := AddButton(FButtons, rsMeasurementsRevert, @RevertClick);
  FRevertButton.Hint := rsMeasurementsRevertHint;
  FRevertButton.ShowHint := True;
  BuildTestBar;
  SetColumns([rsMeasurementsKey, rsMeasurementsValue, rsMeasurementsDescription], [120, 100, 240]);
  SetEditableColumns([True, True, True], [False, False, False]);
  UpdateButtons;
end;

destructor TMeasurementsPanel.Destroy;
begin
  inherited Destroy;
  FreeAndNil(FPending);
end;

function TMeasurementsPanel.AddButton(Host: TWinControl; const ACaption: string; OnPress: TNotifyEvent): TButton;
begin
  Result := TButton.Create(Self);
  Result.Parent := Host;
  Result.Caption := ACaption;
  Result.AutoSize := True;
  // Docked left to right in the order of their positions
  Result.Align := alLeft;
  Result.Left := Host.ControlCount * 100;
  Result.OnClick := OnPress;
end;

// Exactly 1 is the slider at its centre, so this is not a tolerance compare
function TMeasurementsPanel.Testing: boolean;
begin
  Result := Assigned(Document) and (Document.MeasurementScale <> 1);
end;

function TMeasurementsPanel.HasPending: boolean;
begin
  Result := Assigned(FPending) and (FPending.Count > 0);
end;

procedure TMeasurementsPanel.UpdateFileLabel;
begin
  if not Assigned(Document) or (Document.MeasurementPath = '') then
    FFileLabel.Caption := rsMeasurementsNoSet
  else
    FFileLabel.Caption := ExtractFileName(Document.MeasurementPath);
end;

// The list is put back only when it differs, so a change of size while the
// list is open is not lost
procedure TMeasurementsPanel.UpdateSizes;
var
  Sizes: TStringList;
  Index: integer;
begin
  FSizeBar.Visible := Assigned(Document) and Assigned(Document.Measurements) and (Document.Measurements.SizeCount > 0);
  if not FSizeBar.Visible then
    Exit;
  Sizes := TStringList.Create;
  try
    for Index := 0 to Document.Measurements.SizeCount - 1 do
      Sizes.Add(Document.Measurements.Sizes[Index]);
    if not FSizeBox.Items.Equals(Sizes) then
      FSizeBox.Items.Assign(Sizes);
  finally
    FreeAndNil(Sizes);
  end;
  FSizeBox.ItemIndex := Document.Measurements.SizeIndex;
end;

procedure TMeasurementsPanel.UpdateButtons;
begin
  FAddButton.Enabled := Assigned(Document) and not Testing;
  FSaveButton.Enabled := HasPending;
  FRevertButton.Enabled := HasPending;
end;

// Another size shows other values, so the edits are settled first
procedure TMeasurementsPanel.SizeChange(Sender: TObject);
begin
  if not Assigned(Document) or (FSizeBox.ItemIndex < 0) then
    Exit;
  if not ConfirmPending then
  begin
    UpdateSizes;
    Exit;
  end;
  Document.SelectMeasurementSize(FSizeBox.Items[FSizeBox.ItemIndex]);
end;

// Over the buttons: the label above the slider and its Reset button
procedure TMeasurementsPanel.BuildTestBar;
var
  Row: TPanel;
begin
  FTestGroup := TGroupBox.Create(Self);
  FTestGroup.Parent := Self;
  FTestGroup.Align := alBottom;
  FTestGroup.Top := 100000;
  FTestGroup.Caption := rsMeasurementsTestTitle;
  FTestGroup.BorderSpacing.Top := 6;
  FTestGroup.BorderSpacing.Bottom := 6;
  FTestGroup.AutoSize := True;
  FTestGroup.Hint := rsMeasurementsTestHint;
  FTestGroup.ShowHint := True;
  FTestGroup.ChildSizing.TopBottomSpacing := 8;

  Row := TPanel.Create(Self);
  Row.Parent := FTestGroup;
  Row.Align := alTop;
  Row.BevelOuter := bvNone;
  Row.AutoSize := True;
  FTestReset := AddButton(Row, rsMeasurementsTestReset, @TestResetClick);
  FTestReset.Align := alRight;
  FTestLabel := TLabel.Create(Self);
  FTestLabel.Parent := Row;
  FTestLabel.Align := alClient;
  FTestLabel.Layout := tlCenter;
  FTestSlider := TTrackBar.Create(Self);
  FTestSlider.Parent := FTestGroup;
  FTestSlider.Align := alTop;
  FTestSlider.Top := 10000;
  FTestSlider.Min := -MaxTestPercent;
  FTestSlider.Max := MaxTestPercent;
  FTestSlider.Frequency := TestTickPercent;
  FTestSlider.LineSize := 1;
  FTestSlider.PageSize := TestTickPercent;
  FTestSlider.Position := 0;
  FTestSlider.OnChange := @TestChange;
  UpdateTest;
end;

// From the document, which goes back to 0% when another pattern opens
procedure TMeasurementsPanel.UpdateTest;
var
  Percent: integer;
begin
  Percent := 0;
  if Assigned(Document) then
    Percent := Round((Document.MeasurementScale - 1) * 100);
  FShowingTest := True;
  try
    FTestSlider.Position := Percent;
  finally
    FShowingTest := False;
  end;
  // Format has no + flag, so larger sizes get their sign here
  if Percent > 0 then
    FTestLabel.Caption := Format(rsMeasurementsTest, [Format(rsMeasurementsTestOn, ['+' + IntToStr(Percent)])])
  else if Testing then
    FTestLabel.Caption := Format(rsMeasurementsTest, [Format(rsMeasurementsTestOn, [IntToStr(Percent)])])
  else if HasPending then
    FTestLabel.Caption := rsMeasurementsTestPaused
  else
    FTestLabel.Caption := Format(rsMeasurementsTest, [rsMeasurementsTestOff]);
  FTestReset.Enabled := Testing;
  FTestSlider.Enabled := not HasPending;
end;

procedure TMeasurementsPanel.TestChange(Sender: TObject);
begin
  if FShowingTest or not Assigned(Document) then
    Exit;
  FinishEditing;
  Document.SetMeasurementScale(1 + FTestSlider.Position / 100);
end;

procedure TMeasurementsPanel.TestResetClick(Sender: TObject);
begin
  FTestSlider.Position := 0;
end;

function TMeasurementsPanel.PendingRow(Index: integer): TListPanelRow;
var
  Item: TPendingMeasurement;
  ValueText: string;
begin
  Item := FPending[Index];
  ValueText := '';
  if Item.HasValue then
    ValueText := FormatJSONFloat(Item.Value);
  Result := Default(TListPanelRow);
  Result.Key := Item.Key;
  Result.State := esValid;
  Result.Marked := True;
  Result.Cells := [Format(rsMeasurementsEdited, [Item.Key]), ValueText, Item.Description];
end;

function TMeasurementsPanel.BuildRows: TListPanelRowArray;
var
  Rows: TMeasurementRowArray;
  Index, Count, PendingIndex: integer;
  Listed: array of boolean;
  LowerSearch: string;
begin
  Result := nil;
  if Document.MeasurementPath <> FPendingPath then
  begin
    FPending.Clear;
    FPendingPath := Document.MeasurementPath;
  end;
  UpdateFileLabel;
  UpdateSizes;
  UpdateTest;
  UpdateButtons;
  Rows := MeasurementRows(Document.Pattern, Document.Measurements, SearchText);
  Listed := nil;
  SetLength(Listed, FPending.Count);
  SetLength(Result, Length(Rows) + FPending.Count);
  for Index := 0 to High(Rows) do
  begin
    PendingIndex := FPending.IndexOf(Rows[Index].Key);
    if PendingIndex >= 0 then
    begin
      Listed[PendingIndex] := True;
      Result[Index] := PendingRow(PendingIndex);
      Continue;
    end;
    Result[Index].Key := Rows[Index].Key;
    Result[Index].Marked := False;
    if Rows[Index].Missing then
    begin
      Result[Index].State := esError;
      Result[Index].Cells := [Rows[Index].Key, rsMeasurementsMissing, ''];
    end
    else
    begin
      Result[Index].State := esValid;
      Result[Index].Cells := [Rows[Index].Key, Rows[Index].Value, Rows[Index].Description];
    end;
  end;
  // New keys from Add come last, when the search lets them through
  Count := Length(Rows);
  LowerSearch := LowerCase(Trim(SearchText));
  for Index := 0 to FPending.Count - 1 do
    if not Listed[Index] and FPending[Index].IsNew and ((LowerSearch = '') or (Pos(LowerSearch, LowerCase(FPending[Index].Key)) > 0)) then
    begin
      Result[Count] := PendingRow(Index);
      Inc(Count);
    end;
  SetLength(Result, Count);
end;

// Nothing is edited while trying sizes, since the values shown are scaled;
// a key is only edited on a row made by Add
function TMeasurementsPanel.CellEditable(const Key: string; Column: integer): boolean;
var
  Index: integer;
begin
  Result := Assigned(Document) and not Testing and inherited CellEditable(Key, Column);
  if Result and (Column = Ord(mcKey)) then
  begin
    Index := FPending.IndexOf(Key);
    Result := (Index >= 0) and FPending[Index].IsNew;
  end;
end;

function TMeasurementsPanel.CellEditText(const Key: string; Column: integer; const Shown: string): string;
var
  Index: integer;
begin
  Result := Shown;
  Index := FPending.IndexOf(Key);
  if (Column = Ord(mcKey)) and (Index >= 0) then
    Result := FPending[Index].Key
  else if (Column = Ord(mcValue)) and (Shown = rsMeasurementsMissing) then
    Result := '';
end;

function TMeasurementsPanel.CommitCell(const Key: string; Column: integer; const AText: string; out Reason: string): boolean;
var
  NewKey: string;
begin
  Reason := '';
  if not Assigned(Document) or (Column < Ord(Low(TMeasurementColumn))) or (Column > Ord(High(TMeasurementColumn))) then
    Exit(False);
  Result := FPending.CommitCell(Document.Measurements, Key, TMeasurementColumn(Column), AText, NewKey, Reason);
  if not Result then
    Exit;
  if NewKey <> Key then
    ShowSelection([NewKey]);
  QueueRefresh;
end;

procedure TMeasurementsPanel.AddClick(Sender: TObject);
var
  Key: string;
begin
  if not Assigned(Document) or Testing then
    Exit;
  FinishEditing;
  Key := FPending.AddNew(Document.Measurements);
  Refresh;
  FocusCell(Key, Ord(mcKey), True);
end;

function TMeasurementsPanel.Save: boolean;
var
  Edits: TMeasurementEditArray;
  Changes: TMeasurementChangeArray;
  Reason: string;
begin
  Result := True;
  if not Assigned(Document) then
    Exit;
  FinishEditing;
  if not HasPending then
    Exit;
  Result := False;
  if not FPending.Edits(Edits, Reason) then
  begin
    ShowMessageText(Reason);
    Exit;
  end;
  if (Document.MeasurementPath = '') and Assigned(FOnNewSet) then
    FOnNewSet(Self);
  if Document.MeasurementPath = '' then
    Exit;
  // A new file is read with no edits, so they are kept for it
  FPendingPath := Document.MeasurementPath;
  if not Document.ChangeMeasurements(Edits, Changes, Reason) then
  begin
    ShowMessageText(Reason);
    Exit;
  end;
  FPending.Clear;
  Refresh;
  ShowMessageText(MeasurementsSavedText(Changes, Document.MeasurementPath));
  Result := True;
end;

procedure TMeasurementsPanel.Revert;
begin
  FinishEditing;
  FPending.Clear;
  ClearRefusals;
  ShowMessageText('');
end;

procedure TMeasurementsPanel.SaveClick(Sender: TObject);
begin
  Save;
end;

procedure TMeasurementsPanel.RevertClick(Sender: TObject);
begin
  Revert;
end;

function TMeasurementsPanel.ConfirmPending(CanCancel: boolean): boolean;
var
  Target: string;
  Answer: TModalResult;
begin
  FinishEditing;
  if not HasPending then
    Exit(True);
  if Document.MeasurementPath = '' then
    Target := rsMeasurementsPendingNewSet
  else
    Target := ExtractFileName(Document.MeasurementPath);
  if CanCancel then
    Answer := QuestionDlg(rsMeasurementsPendingTitle, Format(rsMeasurementsPendingAsk, [Target]), mtConfirmation,
      [mrYes, rsMeasurementsPendingSave, mrNo, rsMeasurementsPendingDiscard, mrCancel, rsMeasurementsPendingCancel, 'IsCancel'], 0)
  else
    Answer := QuestionDlg(rsMeasurementsPendingTitle, Format(rsMeasurementsPendingAsk, [Target]), mtConfirmation,
      [mrYes, rsMeasurementsPendingSave, mrNo, rsMeasurementsPendingDiscard], 0);
  case Answer of
    mrYes:
      Result := Save;
    mrCancel:
      Result := False;
    else
    begin
      // Discarding, or closing the question when it cannot be cancelled
      Revert;
      Result := True;
    end;
  end;
end;

end.
