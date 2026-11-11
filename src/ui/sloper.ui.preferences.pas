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

// The Preferences dialog, the same in all three apps: a General tab with the
// unit, a Design tab with the grid and a Publish tab with the printer
// calibration. What it saves goes straight to settings.json, read again first
// so the other apps' settings stay.
unit Sloper.UI.Preferences;

{$mode ObjFPC}{$H+}

interface

uses
  Classes, Sloper.Core.Settings;

type
  TPreferencesTab = (ptGeneral, ptDesign, ptPublish);

// Opens on FirstTab. True when the user saved changes, which Preferences
// then holds; a file that cannot be written is reported and gives False.
function EditPreferences(AOwner: TComponent; FirstTab: TPreferencesTab; out Preferences: TPreferences): boolean;

resourcestring
  rsPreferencesTitle = 'Preferences';
  rsPreferencesGeneral = 'General';
  rsPreferencesDesign = 'Design';
  rsPreferencesPublish = 'Publish';
  rsPreferencesUnitGroup = 'Units';
  rsPreferencesUnit = 'Unit';
  rsPreferencesUnitMillimetre = 'Millimetres (mm)';
  rsPreferencesUnitCentimetre = 'Centimetres (cm)';
  rsPreferencesUnitInch = 'Inches (in)';
  rsPreferencesUnitNote = 'Measurements, and the drafting app''s rulers, grid and cursor position, are shown in this unit. ' +
    'New patterns will start in it once patterns can have units other than millimetres.';
  rsPreferencesGrid = 'Grid Spacing';
  rsPreferencesGridNote = 'Each unit keeps its own spacing. Zoomed out too far to see the lines, the grid spaces them further apart, always on multiples of this spacing.';
  rsPreferencesCalibrationX = 'Calibration across';
  rsPreferencesCalibrationY = 'Calibration down';
  rsPreferencesCalibration = 'Printer Calibration';
  rsPreferencesCalibrationNote = 'Everything printed at true size is scaled by these factors, for a printer that is consistently a little off.';
  rsPreferencesTestPrint = 'Work Out From a Test Print';
  rsPreferencesTestPrintNote = 'Print a layout with the factors above, measure the test square on its first page, and type what you measured.';
  rsPreferencesTestSquare = 'Test square';
  rsPreferencesSquareMetric = '10 cm (A4, A3 and others)';
  rsPreferencesSquareInch = '4 in (Letter)';
  rsPreferencesMeasuredX = 'Measured across (%s)';
  rsPreferencesMeasuredY = 'Measured down (%s)';
  rsPreferencesWorkOut = 'Work Out Factors';
  rsPreferencesNotSaved = 'The preferences could not be saved: %s';
  rsPreferencesClaude = 'Claude assistant';
  rsPreferencesClaudeKey = 'Anthropic API key';
  rsPreferencesClaudeNote = 'The Claude tab in the side panel sends your questions and the pattern''s names, formulas ' +
    'and drawings to Anthropic, using this key and billed to its account. The key is kept in a file only you can read.';
  rsPreferencesClaudeFromEnvironment = 'Using the key in ANTHROPIC_API_KEY.';
  rsPreferencesKeyNotSaved = 'The API key could not be saved: %s';

implementation

uses
  SysUtils, Math, Forms, Controls, Graphics, StdCtrls, ExtCtrls, ComCtrls, Spin, ButtonPanel, Dialogs, Sloper.Core.Measurements,
  Sloper.Core.Units, Sloper.UI.Spacing, Sloper.Assistant.Key;

const
  DIALOG_WIDTH = 560;
  DIALOG_HEIGHT = 500;
  CALIBRATION_DECIMALS = 4;
  MEASURED_DECIMALS: array[TMeasureUnit] of integer = (1, 2, 3);
  GRID_DECIMALS: array[TMeasureUnit] of integer = (1, 2, 4);
  GRID_INCREMENTS: array[TMeasureUnit] of double = (1, 0.1, 0.0625);
  CALIBRATION_INCREMENT = 0.001;
  UNIT_CAPTIONS: array[TMeasureUnit] of string = (rsPreferencesUnitMillimetre, rsPreferencesUnitCentimetre, rsPreferencesUnitInch);

type
  // Holds the controls while the dialog is open
  TPreferencesDialog = class(TForm)
  private
    FPages: TPageControl;
    FUnitBox, FSquareBox: TComboBox;
    FGridEdits: array[TMeasureUnit] of TFloatSpinEdit;
    FCalibrationXEdit, FCalibrationYEdit, FMeasuredXEdit, FMeasuredYEdit: TFloatSpinEdit;
    FMeasuredXLabel, FMeasuredYLabel: TLabel;
    FKeyEdit: TEdit;
    FKeyShown: string;
    // The unit the measured sizes are typed in, which follows the Units box
    FMeasuredUnit: TMeasureUnit;
    function AddTab(const ACaption: string): TTabSheet;
    function AddGroup(Sheet: TTabSheet; const ACaption: string): TGroupBox;
    function AddRows(Host: TWinControl): TPanel;
    function AddNote(Host: TWinControl; const AText: string): TLabel;
    function AddRow(Rows: TPanel; const ACaption: string; Control: TControl): TLabel;
    function NewSpin(MinValue, MaxValue, Increment: double; Decimals: integer): TFloatSpinEdit;
    procedure BuildGeneralTab;
    procedure BuildDesignTab;
    procedure BuildClaudeGroup;
    procedure BuildPublishTab;
    function ExpectedSide: double;
    procedure ShowMeasuredUnit;
    procedure UnitChange(Sender: TObject);
    procedure SquareChange(Sender: TObject);
    procedure WorkOutClick(Sender: TObject);
  public
    constructor CreateDialog(AOwner: TComponent);
    procedure ShowPreferences(const Preferences: TPreferences);
    function ReadPreferences: TPreferences;
    // Writes the key file when the key was changed; False with a message
    function SaveKey(out ErrorMessage: string): boolean;
  end;

constructor TPreferencesDialog.CreateDialog(AOwner: TComponent);
var
  Buttons: TButtonPanel;
begin
  inherited CreateNew(AOwner);
  Caption := rsPreferencesTitle;
  Position := poOwnerFormCenter;
  BorderStyle := bsDialog;
  Width := Scale96ToForm(DIALOG_WIDTH);
  Height := Scale96ToForm(DIALOG_HEIGHT);
  Buttons := TButtonPanel.Create(Self);
  Buttons.Parent := Self;
  Buttons.ShowButtons := [pbOK, pbCancel];
  SpaceButtons(Buttons);
  FPages := TPageControl.Create(Self);
  FPages.Parent := Self;
  FPages.Align := alClient;
  FPages.BorderSpacing.Around := ControlGap;
  BuildGeneralTab;
  BuildDesignTab;
  BuildPublishTab;
end;

function TPreferencesDialog.AddTab(const ACaption: string): TTabSheet;
begin
  Result := FPages.AddTabSheet;
  Result.Caption := ACaption;
end;

// Below everything already in Host, since top-aligned controls are stacked
// in the order of their tops
procedure StackIn(Host: TWinControl; Control: TControl);
var
  Index, Bottom: integer;
begin
  Bottom := 0;
  for Index := 0 to Host.ControlCount - 1 do
    if Host.Controls[Index] <> Control then
      Bottom := Max(Bottom, Host.Controls[Index].Top + Host.Controls[Index].Height);
  Control.Top := Bottom + 1;
  Control.Align := alTop;
  Control.BorderSpacing.Around := ControlGap;
  Control.Parent := Host;
end;

// A captioned box around one section of a sheet
function TPreferencesDialog.AddGroup(Sheet: TTabSheet; const ACaption: string): TGroupBox;
begin
  Result := TGroupBox.Create(Self);
  Result.Caption := ACaption;
  Result.AutoSize := True;
  StackIn(Sheet, Result);
end;

// Controls in two columns, captions on the left
function TPreferencesDialog.AddRows(Host: TWinControl): TPanel;
begin
  Result := TPanel.Create(Self);
  Result.AutoSize := True;
  Result.BevelOuter := bvNone;
  Result.ChildSizing.Layout := cclLeftToRightThenTopToBottom;
  Result.ChildSizing.ControlsPerLine := 2;
  Result.ChildSizing.HorizontalSpacing := ControlGap;
  Result.ChildSizing.VerticalSpacing := ControlGap;
  Result.ChildSizing.EnlargeHorizontal := crsHomogenousChildResize;
  StackIn(Host, Result);
end;

// Wrapped text across the host
function TPreferencesDialog.AddNote(Host: TWinControl; const AText: string): TLabel;
begin
  Result := TLabel.Create(Self);
  Result.WordWrap := True;
  Result.AutoSize := True;
  Result.Caption := AText;
  StackIn(Host, Result);
end;

function TPreferencesDialog.AddRow(Rows: TPanel; const ACaption: string; Control: TControl): TLabel;
begin
  Result := TLabel.Create(Self);
  Result.Caption := ACaption;
  Result.Layout := tlCenter;
  Result.Parent := Rows;
  Control.Parent := Rows;
end;

function TPreferencesDialog.NewSpin(MinValue, MaxValue, Increment: double; Decimals: integer): TFloatSpinEdit;
begin
  Result := TFloatSpinEdit.Create(Self);
  Result.DecimalPlaces := Decimals;
  Result.MinValue := MinValue;
  Result.MaxValue := MaxValue;
  Result.Increment := Increment;
end;

procedure TPreferencesDialog.BuildGeneralTab;
var
  Group: TGroupBox;
begin
  Group := AddGroup(AddTab(rsPreferencesGeneral), rsPreferencesUnitGroup);
  FUnitBox := TComboBox.Create(Self);
  FUnitBox.Style := csDropDownList;
  // In the order of TMeasureUnit
  FUnitBox.Items.Add(rsPreferencesUnitMillimetre);
  FUnitBox.Items.Add(rsPreferencesUnitCentimetre);
  FUnitBox.Items.Add(rsPreferencesUnitInch);
  FUnitBox.OnChange := @UnitChange;
  AddRow(AddRows(Group), rsPreferencesUnit, FUnitBox);
  AddNote(Group, rsPreferencesUnitNote);
end;

procedure TPreferencesDialog.BuildDesignTab;
var
  Group: TGroupBox;
  Rows: TPanel;
  AUnit: TMeasureUnit;
begin
  Group := AddGroup(AddTab(rsPreferencesDesign), rsPreferencesGrid);
  Rows := AddRows(Group);
  for AUnit := Low(TMeasureUnit) to High(TMeasureUnit) do
  begin
    FGridEdits[AUnit] := NewSpin(IntPower(10, -GRID_DECIMALS[AUnit]), MAX_GRID_STEP / MILLIMETRES_PER_UNIT[AUnit], GRID_INCREMENTS[AUnit],
      GRID_DECIMALS[AUnit]);
    AddRow(Rows, UNIT_CAPTIONS[AUnit], FGridEdits[AUnit]);
  end;
  AddNote(Group, rsPreferencesGridNote);
  BuildClaudeGroup;
end;

// The key is shown masked; from the environment it cannot be changed here
procedure TPreferencesDialog.BuildClaudeGroup;
var
  Group: TGroupBox;
  Source: TKeySource;
begin
  Group := AddGroup(TTabSheet(FPages.Pages[FPages.PageCount - 1]), rsPreferencesClaude);
  FKeyEdit := TEdit.Create(Self);
  FKeyEdit.PasswordChar := '*';
  FKeyShown := AssistantKey(Source);
  FKeyEdit.Text := FKeyShown;
  FKeyEdit.Enabled := Source <> ksEnvironment;
  AddRow(AddRows(Group), rsPreferencesClaudeKey, FKeyEdit);
  if Source = ksEnvironment then
    AddNote(Group, rsPreferencesClaudeFromEnvironment);
  AddNote(Group, rsPreferencesClaudeNote);
end;

function TPreferencesDialog.SaveKey(out ErrorMessage: string): boolean;
begin
  ErrorMessage := '';
  Result := not FKeyEdit.Enabled or (FKeyEdit.Text = FKeyShown) or SaveAssistantKey(FKeyEdit.Text, ErrorMessage);
end;

procedure TPreferencesDialog.BuildPublishTab;
var
  Sheet: TTabSheet;
  Group: TGroupBox;
  Rows: TPanel;
  WorkOut: TButton;
begin
  Sheet := AddTab(rsPreferencesPublish);
  Group := AddGroup(Sheet, rsPreferencesCalibration);
  Rows := AddRows(Group);
  FCalibrationXEdit := NewSpin(MIN_CALIBRATION, MAX_CALIBRATION, CALIBRATION_INCREMENT, CALIBRATION_DECIMALS);
  AddRow(Rows, rsPreferencesCalibrationX, FCalibrationXEdit);
  FCalibrationYEdit := NewSpin(MIN_CALIBRATION, MAX_CALIBRATION, CALIBRATION_INCREMENT, CALIBRATION_DECIMALS);
  AddRow(Rows, rsPreferencesCalibrationY, FCalibrationYEdit);
  AddNote(Group, rsPreferencesCalibrationNote);
  Group := AddGroup(Sheet, rsPreferencesTestPrint);
  AddNote(Group, rsPreferencesTestPrintNote);
  Rows := AddRows(Group);
  FSquareBox := TComboBox.Create(Self);
  FSquareBox.Style := csDropDownList;
  FSquareBox.Items.Add(rsPreferencesSquareMetric);
  FSquareBox.Items.Add(rsPreferencesSquareInch);
  FSquareBox.ItemIndex := 0;
  FSquareBox.OnChange := @SquareChange;
  AddRow(Rows, rsPreferencesTestSquare, FSquareBox);
  FMeasuredXEdit := NewSpin(0, 1000, 0.1, 1);
  FMeasuredXLabel := AddRow(Rows, '', FMeasuredXEdit);
  FMeasuredYEdit := NewSpin(0, 1000, 0.1, 1);
  FMeasuredYLabel := AddRow(Rows, '', FMeasuredYEdit);
  WorkOut := TButton.Create(Self);
  WorkOut.Caption := rsPreferencesWorkOut;
  WorkOut.AutoSize := True;
  WorkOut.OnClick := @WorkOutClick;
  AddRow(Rows, '', WorkOut);
end;

procedure TPreferencesDialog.ShowPreferences(const Preferences: TPreferences);
var
  AUnit: TMeasureUnit;
begin
  FUnitBox.ItemIndex := Ord(Preferences.MeasureUnit);
  for AUnit := Low(TMeasureUnit) to High(TMeasureUnit) do
    FGridEdits[AUnit].Value := Preferences.GridSteps[AUnit];
  FCalibrationXEdit.Value := Preferences.Calibration.X;
  FCalibrationYEdit.Value := Preferences.Calibration.Y;
  FSquareBox.ItemIndex := 0;
  FMeasuredUnit := Preferences.MeasureUnit;
  ShowMeasuredUnit;
  FMeasuredXEdit.Value := ExpectedSide / MILLIMETRES_PER_UNIT[FMeasuredUnit];
  FMeasuredYEdit.Value := FMeasuredXEdit.Value;
end;

function TPreferencesDialog.ReadPreferences: TPreferences;
var
  AUnit: TMeasureUnit;
begin
  Result := DefaultPreferences;
  if FUnitBox.ItemIndex >= 0 then
    Result.MeasureUnit := TMeasureUnit(FUnitBox.ItemIndex);
  for AUnit := Low(TMeasureUnit) to High(TMeasureUnit) do
    if GridStepIsUsable(FGridEdits[AUnit].Value, AUnit) then
      Result.GridSteps[AUnit] := FGridEdits[AUnit].Value;
  Result.Calibration.X := FCalibrationXEdit.Value;
  Result.Calibration.Y := FCalibrationYEdit.Value;
  if not CalibrationIsUsable(Result.Calibration) then
    Result.Calibration := NoCalibration;
end;

// The side of the test square chosen, in mm
function TPreferencesDialog.ExpectedSide: double;
begin
  if FSquareBox.ItemIndex = 1 then
    Result := INCH_TEST_SQUARE_SIDE
  else
    Result := METRIC_TEST_SQUARE_SIDE;
end;

procedure TPreferencesDialog.ShowMeasuredUnit;
begin
  FMeasuredXLabel.Caption := Format(rsPreferencesMeasuredX, [MEASURE_UNIT_NAMES[FMeasuredUnit]]);
  FMeasuredYLabel.Caption := Format(rsPreferencesMeasuredY, [MEASURE_UNIT_NAMES[FMeasuredUnit]]);
  FMeasuredXEdit.DecimalPlaces := MEASURED_DECIMALS[FMeasuredUnit];
  FMeasuredYEdit.DecimalPlaces := MEASURED_DECIMALS[FMeasuredUnit];
  FMeasuredXEdit.Increment := IntPower(10, -MEASURED_DECIMALS[FMeasuredUnit]);
  FMeasuredYEdit.Increment := FMeasuredXEdit.Increment;
  FMeasuredXEdit.MaxValue := 2 * INCH_TEST_SQUARE_SIDE / MILLIMETRES_PER_UNIT[FMeasuredUnit];
  FMeasuredYEdit.MaxValue := FMeasuredXEdit.MaxValue;
end;

// The measured sizes keep their length in the new unit
procedure TPreferencesDialog.UnitChange(Sender: TObject);
var
  Across, Down: double;
begin
  if FUnitBox.ItemIndex < 0 then
    Exit;
  Across := FMeasuredXEdit.Value * MILLIMETRES_PER_UNIT[FMeasuredUnit];
  Down := FMeasuredYEdit.Value * MILLIMETRES_PER_UNIT[FMeasuredUnit];
  FMeasuredUnit := TMeasureUnit(FUnitBox.ItemIndex);
  ShowMeasuredUnit;
  FMeasuredXEdit.Value := Across / MILLIMETRES_PER_UNIT[FMeasuredUnit];
  FMeasuredYEdit.Value := Down / MILLIMETRES_PER_UNIT[FMeasuredUnit];
end;

// Starts the measured sizes at the square's own, so only what differs is typed
procedure TPreferencesDialog.SquareChange(Sender: TObject);
begin
  FMeasuredXEdit.Value := ExpectedSide / MILLIMETRES_PER_UNIT[FMeasuredUnit];
  FMeasuredYEdit.Value := FMeasuredXEdit.Value;
end;

procedure TPreferencesDialog.WorkOutClick(Sender: TObject);
var
  Scale: double;
begin
  Scale := MILLIMETRES_PER_UNIT[FMeasuredUnit];
  FCalibrationXEdit.Value := CorrectedCalibration(FCalibrationXEdit.Value, ExpectedSide, FMeasuredXEdit.Value * Scale);
  FCalibrationYEdit.Value := CorrectedCalibration(FCalibrationYEdit.Value, ExpectedSide, FMeasuredYEdit.Value * Scale);
  // The new factors would print the square true, so the next print starts afresh
  SquareChange(nil);
end;

function EditPreferences(AOwner: TComponent; FirstTab: TPreferencesTab; out Preferences: TPreferences): boolean;
var
  Dialog: TPreferencesDialog;
  Reason: string;
begin
  Preferences := UserPreferences;
  Dialog := TPreferencesDialog.CreateDialog(AOwner);
  try
    Dialog.ShowPreferences(Preferences);
    Dialog.FPages.PageIndex := Ord(FirstTab);
    if Dialog.ShowModal <> mrOk then
      Exit(False);
    Preferences := Dialog.ReadPreferences;
    if not Dialog.SaveKey(Reason) then
      MessageDlg(Format(rsPreferencesKeyNotSaved, [Reason]), mtError, [mbOK], 0);
  finally
    FreeAndNil(Dialog);
  end;
  Result := SaveUserPreferences(Preferences, Reason);
  if not Result then
    MessageDlg(Format(rsPreferencesNotSaved, [Reason]), mtError, [mbOK], 0);
end;

end.
