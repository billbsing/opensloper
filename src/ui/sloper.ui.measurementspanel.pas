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
// the design gives the drafting app: changing a value or description and adding
// a key. Everything else belongs to the measurements app. These edits go
// straight to the file, so they are not undo steps.

// The Test size slider tries the pattern a size up or down: every measurement
// is scaled by up to 20% either way, 1% a step. Nothing is saved; the values
// shown are the scaled ones, and editing waits until the slider is back at 0%.
unit Sloper.UI.MeasurementsPanel;

{$mode ObjFPC}{$H+}

interface

uses
  Classes, SysUtils, Controls, Graphics, StdCtrls, ExtCtrls, ComCtrls, LCLType, Sloper.UI.ListPanel;

type
  TMeasurementsPanel = class(TListPanel)
  private
    FFileLabel: TLabel;
    FEditors: TGroupBox;
    FKeyEdit, FValueEdit, FDescriptionEdit: TEdit;
    FSaveButton: TButton;
    FSizeBar: TPanel;
    FSizeBox: TComboBox;
    FTestLabel: TLabel;
    FTestSlider: TTrackBar;
    FTestReset: TButton;
    FTestGroup: TGroupBox;
    // While the slider is being set from the document
    FShowingTest: boolean;
    FOnOpenSet: TNotifyEvent;
    FOnNewSet: TNotifyEvent;
    FOnEditSet: TNotifyEvent;
    function AddEditor(const ACaption: string): TEdit;
    function AddButton(Host: TWinControl; const ACaption: string; OnPress: TNotifyEvent): TButton;
    procedure UpdateFileLabel;
    procedure UpdateSizes;
    procedure SizeChange(Sender: TObject);
    procedure BuildTestBar;
    procedure UpdateTest;
    procedure TestChange(Sender: TObject);
    procedure TestResetClick(Sender: TObject);
    procedure EditClick(Sender: TObject);
    procedure ShowEditors;
    procedure Save;
    procedure OpenClick(Sender: TObject);
    procedure NewClick(Sender: TObject);
    procedure AddClick(Sender: TObject);
    procedure SaveClick(Sender: TObject);
    procedure EditorKeyDown(Sender: TObject; var Key: word; Shift: TShiftState);
  protected
    function BuildRows: TListPanelRowArray; override;
    procedure SelectionChosen; override;
  public
    constructor Create(AOwner: TComponent); override;
    // The user wants to open another set
    property OnOpenSet: TNotifyEvent read FOnOpenSet write FOnOpenSet;
    // The user wants a new, empty file; saving with no file asks for this first
    property OnNewSet: TNotifyEvent read FOnNewSet write FOnNewSet;
    // The user wants the set in the measurements app
    property OnEditSet: TNotifyEvent read FOnEditSet write FOnEditSet;
  end;

resourcestring
  rsMeasurementsNoSet = 'No measurement set';
  rsMeasurementsOpen = '&Open...';
  rsMeasurementsNew = '&New...';
  rsMeasurementsEdit = '&Edit...';
  rsMeasurementsSize = 'Size';
  rsMeasurementsAdd = '&Add';
  rsMeasurementsSave = '&Save';
  rsMeasurementsKey = 'Key';
  rsMeasurementsValue = 'Value (mm)';
  rsMeasurementsDescription = 'Description';
  rsMeasurementsMissing = 'Missing';
  rsMeasurementsBadValue = 'The value must be a number, such as 820 or 41.5';
  rsMeasurementsTest = 'Test size: %s';
  rsMeasurementsTestOff = '0%';
  rsMeasurementsTestOn = '%s%%, editing paused';
  rsMeasurementsTestReset = '&Reset';
  rsMeasurementsTestHint = 'Tries the pattern with every measurement larger or smaller, 1% a step. Nothing is saved.';
  rsMeasurementsTestTitle = 'Test Sizes';
  rsMeasurementsSetTitle = 'Measurement Set';
  rsMeasurementsEditorsTitle = 'Measurement';

implementation

uses
  Sloper.Core.EvalTypes, Sloper.Core.JSON, Sloper.Core.Measurements, Sloper.UI.ObjectList;

const
  MaxValue = 1e12;
  // Test size steps, in percent either way
  MaxTestPercent = 20;
  TestTickPercent = 5;

function ParseValue(const Text: string; out Value: double): boolean;
var
  Settings: TFormatSettings;
begin
  Settings := DefaultFormatSettings;
  Settings.DecimalSeparator := '.';
  Result := TryStrToFloat(Trim(Text), Value, Settings) and (Abs(Value) < MaxValue);
end;

constructor TMeasurementsPanel.Create(AOwner: TComponent);
var
  FileBar, Buttons: TPanel;
  SetGroup: TGroupBox;
  SizeLabel: TLabel;
begin
  inherited Create(AOwner);
  MultiSelect := False;
  // Above the search box
  SetGroup := TGroupBox.Create(Self);
  SetGroup.Parent := FHeader;
  SetGroup.Align := alTop;
  SetGroup.Top := -1;
  SetGroup.BorderSpacing.Bottom := 6;
  SetGroup.AutoSize := True;
  SetGroup.Caption := rsMeasurementsSetTitle;
  SetGroup.ChildSizing.TopBottomSpacing := 8;

  FileBar := TPanel.Create(Self);
  FileBar.Parent := SetGroup;
  FileBar.Align := alTop;
  FileBar.Top := -1;
  FileBar.BevelOuter := bvNone;
  FileBar.AutoSize := True;
  AddButton(FileBar, rsMeasurementsNew, @NewClick);
  AddButton(FileBar, rsMeasurementsOpen, @OpenClick);
  AddButton(FileBar, rsMeasurementsEdit, @EditClick);
  FFileLabel := TLabel.Create(Self);
  FFileLabel.Parent := FileBar;
  FFileLabel.Align := alClient;
  FFileLabel.Layout := tlCenter;
  FFileLabel.Caption := rsMeasurementsNoSet;
  FSizeBar := TPanel.Create(Self);
  FSizeBar.Visible := False;
  FSizeBar.Parent := SetGroup;
  FSizeBar.Align := alTop;
  FSizeBar.Top := 1000;
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

  FEditors := TGroupBox.Create(Self);
  FEditors.Parent := Self;
  FEditors.Align := alBottom;
  FEditors.BorderSpacing.Top := 6;
  FEditors.AutoSize := True;
  FEditors.Caption := rsMeasurementsEditorsTitle;
  FEditors.ChildSizing.TopBottomSpacing := 8;

  FKeyEdit := AddEditor(rsMeasurementsKey);
  FValueEdit := AddEditor(rsMeasurementsValue);
  FDescriptionEdit := AddEditor(rsMeasurementsDescription);
  Buttons := TPanel.Create(Self);
  Buttons.Parent := FEditors;
  Buttons.Align := alTop;
  Buttons.Top := 10000;
  Buttons.BevelOuter := bvNone;
  Buttons.AutoSize := True;
  Buttons.BorderSpacing.Top := 8;
  AddButton(Buttons, rsMeasurementsAdd, @AddClick);
  FSaveButton := AddButton(Buttons, rsMeasurementsSave, @SaveClick);
  // After the editors, which it disables while testing
  BuildTestBar;
  SetColumns([rsMeasurementsKey, rsMeasurementsValue, rsMeasurementsDescription], [120, 100, 240]);
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
  Result.BorderSpacing.Right := 8;
end;

// A caption above a field, one under another
function TMeasurementsPanel.AddEditor(const ACaption: string): TEdit;
var
  Title: TLabel;
begin
  Title := TLabel.Create(Self);
  Title.Parent := FEditors;
  Title.Align := alTop;
  Title.Top := FEditors.ControlCount * 100;
  Title.Caption := ACaption;
  Result := TEdit.Create(Self);
  Result.Parent := FEditors;
  Result.Align := alTop;
  Result.Top := FEditors.ControlCount * 100;
  Result.OnKeyDown := @EditorKeyDown;
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

procedure TMeasurementsPanel.SizeChange(Sender: TObject);
begin
  if Assigned(Document) and (FSizeBox.ItemIndex >= 0) then
    Document.SelectMeasurementSize(FSizeBox.Items[FSizeBox.ItemIndex]);
end;

// At the bottom, under the editors: the label above the slider and its Reset
// button
procedure TMeasurementsPanel.BuildTestBar;
var
  Row: TPanel;
begin
  FTestGroup := TGroupBox.Create(Self);
  FTestGroup.Parent := Self;
  FTestGroup.Align := alBottom;
  // Below the editors, which are docked at the bottom too
  FTestGroup.Top := 100000;
  FTestGroup.Caption := rsMeasurementsTestTitle;
  FTestGroup.BorderSpacing.Top := 6;
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
  Testing: boolean;
begin
  Percent := 0;
  if Assigned(Document) then
    Percent := Round((Document.MeasurementScale - 1) * 100);
  Testing := Percent <> 0;
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
  else
    FTestLabel.Caption := Format(rsMeasurementsTest, [rsMeasurementsTestOff]);
  FTestReset.Enabled := Testing;
  FEditors.Enabled := not Testing;
end;

procedure TMeasurementsPanel.TestChange(Sender: TObject);
begin
  if FShowingTest or not Assigned(Document) then
    Exit;
  Document.SetMeasurementScale(1 + FTestSlider.Position / 100);
end;

procedure TMeasurementsPanel.TestResetClick(Sender: TObject);
begin
  FTestSlider.Position := 0;
end;

procedure TMeasurementsPanel.EditClick(Sender: TObject);
begin
  if Assigned(FOnEditSet) then
    FOnEditSet(Self);
end;

function TMeasurementsPanel.BuildRows: TListPanelRowArray;
var
  Rows: TMeasurementRowArray;
  Index: integer;
begin
  Result := nil;
  UpdateFileLabel;
  UpdateSizes;
  UpdateTest;
  Rows := MeasurementRows(Document.Pattern, Document.Measurements, SearchText);
  SetLength(Result, Length(Rows));
  for Index := 0 to High(Rows) do
  begin
    Result[Index].Key := Rows[Index].Key;
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
end;

// Keys are not renamed here, so the key field is only for a new one
procedure TMeasurementsPanel.ShowEditors;
var
  Measurement: TMeasurement;
begin
  FKeyEdit.Text := '';
  FValueEdit.Text := '';
  FDescriptionEdit.Text := '';
  FKeyEdit.ReadOnly := Length(Selection) > 0;
  if Length(Selection) = 0 then
    Exit;
  FKeyEdit.Text := Selection[0];
  Measurement := nil;
  if Assigned(Document.Measurements) then
    Measurement := Document.Measurements.Find(Selection[0]);
  if Assigned(Measurement) then
  begin
    if Measurement.HasValue then
      FValueEdit.Text := FormatJSONFloat(Measurement.Value);
    FDescriptionEdit.Text := Measurement.Description;
  end;
end;

procedure TMeasurementsPanel.SelectionChosen;
begin
  ShowEditors;
  inherited SelectionChosen;
end;

procedure TMeasurementsPanel.Save;
var
  Value: double;
  Key, Err: string;
  Change: TMeasurementChange;
begin
  if not Assigned(Document) then
    Exit;
  Key := Trim(FKeyEdit.Text);
  if not ParseValue(FValueEdit.Text, Value) then
  begin
    ShowMessageText(rsMeasurementsBadValue);
    FValueEdit.SetFocus;
    Exit;
  end;
  if (Document.MeasurementPath = '') and Assigned(FOnNewSet) then
    FOnNewSet(Self);
  if Document.MeasurementPath = '' then
    Exit;
  if not Document.ChangeMeasurement(Key, Value, FDescriptionEdit.Text, Change, Err) then
  begin
    ShowMessageText(Err);
    Exit;
  end;
  ShowMessageText(MeasurementChangeText(Change, Document.MeasurementPath));
  ChooseKeys([Change.Key]);
end;

procedure TMeasurementsPanel.OpenClick(Sender: TObject);
begin
  if Assigned(FOnOpenSet) then
    FOnOpenSet(Self);
end;

procedure TMeasurementsPanel.NewClick(Sender: TObject);
begin
  if Assigned(FOnNewSet) then
    FOnNewSet(Self);
end;

procedure TMeasurementsPanel.AddClick(Sender: TObject);
begin
  ChooseKeys(nil);
  FKeyEdit.SetFocus;
end;

procedure TMeasurementsPanel.SaveClick(Sender: TObject);
begin
  Save;
end;

procedure TMeasurementsPanel.EditorKeyDown(Sender: TObject; var Key: word; Shift: TShiftState);
begin
  case Key of
    VK_RETURN:
    begin
      Save;
      Key := 0;
    end;
    VK_ESCAPE:
    begin
      ShowEditors;
      Key := 0;
    end;
  end;
end;

end.
