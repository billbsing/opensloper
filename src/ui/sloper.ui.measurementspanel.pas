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
unit Sloper.UI.MeasurementsPanel;

{$mode ObjFPC}{$H+}

interface

uses
  Classes, SysUtils, Controls, Graphics, StdCtrls, ExtCtrls, LCLType, Sloper.UI.ListPanel;

type
  TMeasurementsPanel = class(TListPanel)
  private
    FFileLabel: TLabel;
    FEditors: TPanel;
    FKeyEdit, FValueEdit, FDescriptionEdit: TEdit;
    FSaveButton: TButton;
    FOnOpenSet: TNotifyEvent;
    FOnNewSet: TNotifyEvent;
    function AddEditor(const ACaption: string): TEdit;
    function AddButton(Host: TWinControl; const ACaption: string; OnPress: TNotifyEvent): TButton;
    procedure UpdateFileLabel;
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
  end;

resourcestring
  rsMeasurementsNoSet = 'No measurement set';
  rsMeasurementsOpen = '&Open...';
  rsMeasurementsNew = '&New...';
  rsMeasurementsAdd = '&Add';
  rsMeasurementsSave = '&Save';
  rsMeasurementsKey = 'Key';
  rsMeasurementsValue = 'Value (mm)';
  rsMeasurementsDescription = 'Description';
  rsMeasurementsMissing = 'Missing';
  rsMeasurementsBadValue = 'The value must be a number, such as 820 or 41.5';

implementation

uses
  Sloper.Core.EvalTypes, Sloper.Core.JSON, Sloper.Core.Measurements, Sloper.UI.ObjectList;

const
  MaxValue = 1e12;

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
begin
  inherited Create(AOwner);
  MultiSelect := False;
  FileBar := TPanel.Create(Self);
  FileBar.Parent := FHeader;
  FileBar.Align := alTop;
  FileBar.Top := -1;
  FileBar.BevelOuter := bvNone;
  FileBar.AutoSize := True;
  AddButton(FileBar, rsMeasurementsNew, @NewClick);
  AddButton(FileBar, rsMeasurementsOpen, @OpenClick);
  FFileLabel := TLabel.Create(Self);
  FFileLabel.Parent := FileBar;
  FFileLabel.Align := alClient;
  FFileLabel.Layout := tlCenter;
  FFileLabel.Caption := rsMeasurementsNoSet;

  FEditors := TPanel.Create(Self);
  FEditors.Parent := Self;
  FEditors.Align := alBottom;
  FEditors.BevelOuter := bvNone;
  FEditors.AutoSize := True;
  FKeyEdit := AddEditor(rsMeasurementsKey);
  FValueEdit := AddEditor(rsMeasurementsValue);
  FDescriptionEdit := AddEditor(rsMeasurementsDescription);
  Buttons := TPanel.Create(Self);
  Buttons.Parent := FEditors;
  Buttons.Align := alTop;
  Buttons.Top := 10000;
  Buttons.BevelOuter := bvNone;
  Buttons.AutoSize := True;
  AddButton(Buttons, rsMeasurementsAdd, @AddClick);
  FSaveButton := AddButton(Buttons, rsMeasurementsSave, @SaveClick);
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
  if (Document = nil) or (Document.MeasurementPath = '') then
    FFileLabel.Caption := rsMeasurementsNoSet
  else
    FFileLabel.Caption := ExtractFileName(Document.MeasurementPath);
end;

function TMeasurementsPanel.BuildRows: TListPanelRowArray;
var
  Rows: TMeasurementRowArray;
  Index: integer;
begin
  Result := nil;
  UpdateFileLabel;
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
  FKeyEdit.ReadOnly := Selection <> nil;
  if Selection = nil then
    Exit;
  FKeyEdit.Text := Selection[0];
  Measurement := nil;
  if Document.Measurements <> nil then
    Measurement := Document.Measurements.Find(Selection[0]);
  if Measurement <> nil then
  begin
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
  if Document = nil then
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
