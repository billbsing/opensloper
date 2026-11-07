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

// The app's own settings, kept in settings.json in the config folder: things
// that belong to the user rather than to a pattern, such as panel layout, and
// the preferences the three apps share (units, grid, printer calibration).
// A missing file is a first run, so the defaults stand. No LCL dependency.
unit Sloper.Core.Settings;

{$mode ObjFPC}{$H+}

interface

uses
  Sloper.Core.Measurements, Sloper.Core.Units, Sloper.Core.MachineProfiles, Sloper.Core.OutputProfiles, Sloper.Core.Draft;

type
  // Which labels the canvas shows: those that help the current step, all, or none
  TLabelMode = (lmContextual, lmAll, lmNone);

  // Factors scaling everything printed at true size, across and down the
  // page, for a printer that is consistently a little off
  TCalibration = record
    X, Y: double;
  end;

  // A saved set of roles to hide in the drafting app, such as "Seams only"
  TRolePreset = record
    Name: string;
    Hidden: TEdgeRoles;
  end;

  TRolePresetArray = array of TRolePreset;

  // In each unit's own numbers, so 0.125 in stays an eighth of an inch
  TGridSteps = array[TMeasureUnit] of double;

  // What the user sets in Preferences
  TPreferences = record
    // For new patterns, the measurements app and the drafting app's rulers,
    // grid and status bar
    MeasureUnit: TMeasureUnit;
    // The drafting canvas grid's spacing for each unit
    GridSteps: TGridSteps;
    Calibration: TCalibration;
  end;

const
  DefaultNameColumnShare = 0.45;
  DefaultLabelMode = lmContextual;
  DefaultGridSteps: TGridSteps = (5, 0.5, 0.125);
  // The largest grid spacing, in mm, so a mistyped one can't hide the grid
  MaxGridStep = 1000;
  // Calibration factors further off than this are typing mistakes
  MinCalibration = 0.5;
  MaxCalibration = 2;
  // The sides of the PDF's test square: 4 in on Letter, 10 cm elsewhere
  MetricTestSquareSide = 100;
  InchTestSquareSide = 101.6;

type
  TAppSettings = class
  public
    Preferences: TPreferences;
    // The part of the properties panel's row width given to field names, above 0 and below 1
    NameColumnShare: double;
    LabelMode: TLabelMode;
    ShowSidePanel: boolean;
    // Rulers along the top and left of the drafting canvas
    ShowRulers: boolean;
    // Whether the drafting canvas fills pieces with their fabric
    ShowPieceFills: boolean;
    // Besides the built-in Standard
    MachineProfiles: TMachineProfileArray;
    // Besides the built-in ones
    OutputProfiles: TOutputProfileArray;
    RolePresets: TRolePresetArray;
    constructor Create;
    procedure Reset;
    function SaveToText: string;
    // On failure the defaults stand and ErrorMessage says why
    function LoadFromText(const Text: string; out ErrorMessage: string): boolean;
    function SaveToFile(const FileName: string; out ErrorMessage: string): boolean;
    function LoadFromFile(const FileName: string; out ErrorMessage: string): boolean;
  end;

function DefaultPreferences: TPreferences;
function NoCalibration: TCalibration;
function CalibrationIsUsable(const Calibration: TCalibration): boolean;
function GridStepIsUsable(Step: double; AUnit: TMeasureUnit): boolean;
// The factor that makes a test square print at Expected, given that with
// Current it printed at Measured; the square is drawn with the factor, so the
// correction builds on it
function CorrectedCalibration(Current, Expected, Measured: double): double;

// The profiles saved for this user, for the programs that export; none when
// the settings cannot be read, and a layout naming one then says it is missing
function UserMachineProfiles: TMachineProfileArray;
// The same for output profiles
function UserOutputProfiles: TOutputProfileArray;
// Takes out a preset by name, ignoring case, and adds this one
procedure PutRolePreset(var Presets: TRolePresetArray; const Preset: TRolePreset);
procedure RemoveRolePreset(var Presets: TRolePresetArray; const AName: string);
// This user's printer calibration, for the programs that print; none when the
// settings cannot be read
function UserCalibration: TCalibration;
// This user's preferences; the defaults when the settings cannot be read
function UserPreferences: TPreferences;
// Reads the settings file again, gives it these preferences and writes it
// back, so what other apps running alongside have saved stays. Fails without
// writing when the file cannot be read, rather than lose what is in it.
function SaveUserPreferences(const Preferences: TPreferences; out ErrorMessage: string): boolean;
function SavePreferencesToFile(const FileName: string; const Preferences: TPreferences; out ErrorMessage: string): boolean;
// The same for role presets
function SaveUserRolePresets(const Presets: TRolePresetArray; out ErrorMessage: string): boolean;
function SaveRolePresetsToFile(const FileName: string; const Presets: TRolePresetArray; out ErrorMessage: string): boolean;

resourcestring
  rsSettingsWrongFormat = 'This is not an OpenSloper settings file';
  rsSettingsNewerVersion = 'This file was made by a newer version of OpenSloper (file version %d)';

implementation

uses
  SysUtils, fpjson, Sloper.Core.JSON, Sloper.Core.AppPaths;

const
  SettingsFormat = 'opensloper-settings';
  SettingsVersion = 1;
  LabelModeNames: array[TLabelMode] of string = ('contextual', 'all', 'none');

function DefaultPreferences: TPreferences;
begin
  Result.MeasureUnit := muMillimetre;
  Result.GridSteps := DefaultGridSteps;
  Result.Calibration := NoCalibration;
end;

function NoCalibration: TCalibration;
begin
  Result.X := 1;
  Result.Y := 1;
end;

function CalibrationIsUsable(const Calibration: TCalibration): boolean;
begin
  Result := (Calibration.X >= MinCalibration) and (Calibration.X <= MaxCalibration) and (Calibration.Y >= MinCalibration) and
    (Calibration.Y <= MaxCalibration);
end;

function GridStepIsUsable(Step: double; AUnit: TMeasureUnit): boolean;
begin
  Result := (Step > 0) and (Step * MillimetresPerUnit[AUnit] <= MaxGridStep);
end;

function CorrectedCalibration(Current, Expected, Measured: double): double;
begin
  if (Measured <= 0) or (Expected <= 0) then
    Exit(Current);
  Result := Current * Expected / Measured;
end;

constructor TAppSettings.Create;
begin
  inherited Create;
  Reset;
end;

procedure TAppSettings.Reset;
begin
  NameColumnShare := DefaultNameColumnShare;
  LabelMode := DefaultLabelMode;
  ShowSidePanel := True;
  ShowRulers := True;
  ShowPieceFills := True;
  Preferences := DefaultPreferences;
  MachineProfiles := nil;
  OutputProfiles := nil;
  RolePresets := nil;
end;

function RolePresetsToJSON(const Presets: TRolePresetArray): TJSONArray;
var
  Preset: TRolePreset;
  Item: TJSONObject;
  Hidden: TJSONArray;
  RoleName: string;
begin
  Result := TJSONArray.Create;
  try
    for Preset in Presets do
    begin
      Item := TJSONObject.Create;
      Result.Add(Item);
      Item.Add('name', Preset.Name);
      Hidden := TJSONArray.Create;
      Item.Add('hidden', Hidden);
      for RoleName in RolesToNames(Preset.Hidden) do
        Hidden.Add(RoleName);
    end;
  except
    FreeAndNil(Result);
    raise;
  end;
end;

// A preset with no name is skipped, and unknown roles and Outline are passed over
function RolePresetsFromJSON(Data: TJSONData): TRolePresetArray;
var
  Index, Item: integer;
  Obj: TJSONObject;
  Preset: TRolePreset;
  Hidden: TJSONData;
  Roles: TEdgeRoles;
begin
  Result := nil;
  if not Assigned(Data) or (Data.JSONType <> jtArray) then
    Exit;
  for Index := 0 to Data.Count - 1 do
  begin
    if Data.Items[Index].JSONType <> jtObject then
      Continue;
    Obj := TJSONObject(Data.Items[Index]);
    Preset := Default(TRolePreset);
    if not GetJSONString(Obj, 'name', Preset.Name) or (Trim(Preset.Name) = '') then
      Continue;
    Hidden := Obj.Find('hidden');
    if Assigned(Hidden) and (Hidden.JSONType = jtArray) then
      for Item := 0 to Hidden.Count - 1 do
        if (Hidden.Items[Item].JSONType = jtString) and NamesToRoles([Hidden.Items[Item].AsString], Roles) then
          Preset.Hidden := Preset.Hidden + Roles * HideableRoles;
    Insert(Preset, Result, Length(Result));
  end;
end;

procedure RemoveRolePreset(var Presets: TRolePresetArray; const AName: string);
var
  Index: integer;
begin
  for Index := High(Presets) downto 0 do
    if SameText(Presets[Index].Name, AName) then
      Delete(Presets, Index, 1);
end;

procedure PutRolePreset(var Presets: TRolePresetArray; const Preset: TRolePreset);
begin
  RemoveRolePreset(Presets, Preset.Name);
  Insert(Preset, Presets, Length(Presets));
end;

function GridStepsToJSON(const Steps: TGridSteps): TJSONObject;
var
  AUnit: TMeasureUnit;
begin
  Result := TJSONObject.Create;
  for AUnit := Low(TMeasureUnit) to High(TMeasureUnit) do
    Result.Add(MeasureUnitNames[AUnit], JSONFloat(Steps[AUnit]));
end;

// A missing or unusable step keeps its default
procedure ReadGridSteps(Obj: TJSONObject; var Steps: TGridSteps);
var
  Item: TJSONData;
  AUnit: TMeasureUnit;
  Step: double;
begin
  Item := Obj.Find('gridSteps');
  if not Assigned(Item) or (Item.JSONType <> jtObject) then
    Exit;
  for AUnit := Low(TMeasureUnit) to High(TMeasureUnit) do
    if GetJSONNumber(TJSONObject(Item), MeasureUnitNames[AUnit], Step) and GridStepIsUsable(Step, AUnit) then
      Steps[AUnit] := Step;
end;

// Both factors or neither, so a half-read pair can't skew one direction
procedure ReadCalibration(Obj: TJSONObject; var Calibration: TCalibration);
var
  Loaded: TCalibration;
begin
  if GetJSONNumber(Obj, 'calibrationX', Loaded.X) and GetJSONNumber(Obj, 'calibrationY', Loaded.Y) and CalibrationIsUsable(Loaded) then
    Calibration := Loaded;
end;

function TAppSettings.SaveToText: string;
var
  Obj: TJSONObject;
begin
  Obj := TJSONObject.Create;
  try
    Obj.Add('format', SettingsFormat);
    Obj.Add('version', SettingsVersion);
    Obj.Add('nameColumnShare', JSONFloat(NameColumnShare));
    Obj.Add('labelMode', LabelModeNames[LabelMode]);
    Obj.Add('showSidePanel', ShowSidePanel);
    Obj.Add('showRulers', ShowRulers);
    Obj.Add('showPieceFills', ShowPieceFills);
    Obj.Add('measureUnit', MeasureUnitNames[Preferences.MeasureUnit]);
    Obj.Add('gridSteps', GridStepsToJSON(Preferences.GridSteps));
    Obj.Add('calibrationX', JSONFloat(Preferences.Calibration.X));
    Obj.Add('calibrationY', JSONFloat(Preferences.Calibration.Y));
    if Length(MachineProfiles) > 0 then
      Obj.Add('machineProfiles', MachineProfilesToJSON(MachineProfiles));
    if Length(OutputProfiles) > 0 then
      Obj.Add('outputProfiles', OutputProfilesToJSON(OutputProfiles));
    if Length(RolePresets) > 0 then
      Obj.Add('rolePresets', RolePresetsToJSON(RolePresets));
    Result := JSONToText(Obj);
  finally
    FreeAndNil(Obj);
  end;
end;

function TAppSettings.LoadFromText(const Text: string; out ErrorMessage: string): boolean;
var
  Obj: TJSONObject;
  TextValue: string;
  Version: integer;
  Share: double;
  Mode: TLabelMode;
  AUnit: TMeasureUnit;
  Shown: boolean;
begin
  Reset;
  if not ParseJSONObject(Text, Obj, ErrorMessage) then
    Exit(False);
  try
    if not GetJSONString(Obj, 'format', TextValue) or (TextValue <> SettingsFormat) or not GetJSONInteger(Obj, 'version', Version) then
    begin
      ErrorMessage := rsSettingsWrongFormat;
      Exit(False);
    end;
    if Version > SettingsVersion then
    begin
      ErrorMessage := Format(rsSettingsNewerVersion, [Version]);
      Exit(False);
    end;
    if GetJSONNumber(Obj, 'nameColumnShare', Share) and (Share > 0) and (Share < 1) then
      NameColumnShare := Share;
    if GetJSONString(Obj, 'labelMode', TextValue) then
      for Mode := Low(TLabelMode) to High(TLabelMode) do
        if TextValue = LabelModeNames[Mode] then
          LabelMode := Mode;
    if GetJSONBoolean(Obj, 'showSidePanel', Shown) then
      ShowSidePanel := Shown;
    if GetJSONBoolean(Obj, 'showRulers', Shown) then
      ShowRulers := Shown;
    if GetJSONBoolean(Obj, 'showPieceFills', Shown) then
      ShowPieceFills := Shown;
    if GetJSONString(Obj, 'measureUnit', TextValue) then
      for AUnit := Low(TMeasureUnit) to High(TMeasureUnit) do
        if TextValue = MeasureUnitNames[AUnit] then
          Preferences.MeasureUnit := AUnit;
    ReadGridSteps(Obj, Preferences.GridSteps);
    ReadCalibration(Obj, Preferences.Calibration);
    MachineProfiles := MachineProfilesFromJSON(Obj.Find('machineProfiles'));
    OutputProfiles := OutputProfilesFromJSON(Obj.Find('outputProfiles'));
    RolePresets := RolePresetsFromJSON(Obj.Find('rolePresets'));
    Result := True;
  finally
    FreeAndNil(Obj);
  end;
end;

function TAppSettings.SaveToFile(const FileName: string; out ErrorMessage: string): boolean;
begin
  Result := WriteTextFile(FileName, SaveToText, ErrorMessage);
end;

function TAppSettings.LoadFromFile(const FileName: string; out ErrorMessage: string): boolean;
var
  Text: string;
begin
  Reset;
  ErrorMessage := '';
  if not FileExists(FileName) then
    Exit(True);
  if not ReadTextFile(FileName, Text, ErrorMessage) then
    Exit(False);
  Result := LoadFromText(Text, ErrorMessage);
end;

function UserMachineProfiles: TMachineProfileArray;
var
  Settings: TAppSettings;
  Reason: string;
begin
  Settings := TAppSettings.Create;
  try
    Settings.LoadFromFile(TAppPaths.SettingsFile, Reason);
    Result := Settings.MachineProfiles;
  finally
    FreeAndNil(Settings);
  end;
end;

function UserOutputProfiles: TOutputProfileArray;
var
  Settings: TAppSettings;
  Reason: string;
begin
  Settings := TAppSettings.Create;
  try
    Settings.LoadFromFile(TAppPaths.SettingsFile, Reason);
    Result := Settings.OutputProfiles;
  finally
    FreeAndNil(Settings);
  end;
end;

function UserPreferences: TPreferences;
var
  Settings: TAppSettings;
  Reason: string;
begin
  Settings := TAppSettings.Create;
  try
    Settings.LoadFromFile(TAppPaths.SettingsFile, Reason);
    Result := Settings.Preferences;
  finally
    FreeAndNil(Settings);
  end;
end;

function UserCalibration: TCalibration;
begin
  Result := UserPreferences.Calibration;
end;

function SaveUserPreferences(const Preferences: TPreferences; out ErrorMessage: string): boolean;
begin
  TAppPaths.ForceDir(TAppPaths.ConfigDir);
  Result := SavePreferencesToFile(TAppPaths.SettingsFile, Preferences, ErrorMessage);
end;

function SavePreferencesToFile(const FileName: string; const Preferences: TPreferences; out ErrorMessage: string): boolean;
var
  Settings: TAppSettings;
begin
  Settings := TAppSettings.Create;
  try
    if not Settings.LoadFromFile(FileName, ErrorMessage) then
      Exit(False);
    Settings.Preferences := Preferences;
    Result := Settings.SaveToFile(FileName, ErrorMessage);
  finally
    FreeAndNil(Settings);
  end;
end;

function SaveUserRolePresets(const Presets: TRolePresetArray; out ErrorMessage: string): boolean;
begin
  TAppPaths.ForceDir(TAppPaths.ConfigDir);
  Result := SaveRolePresetsToFile(TAppPaths.SettingsFile, Presets, ErrorMessage);
end;

function SaveRolePresetsToFile(const FileName: string; const Presets: TRolePresetArray; out ErrorMessage: string): boolean;
var
  Settings: TAppSettings;
begin
  Settings := TAppSettings.Create;
  try
    if not Settings.LoadFromFile(FileName, ErrorMessage) then
      Exit(False);
    Settings.RolePresets := Presets;
    Result := Settings.SaveToFile(FileName, ErrorMessage);
  finally
    FreeAndNil(Settings);
  end;
end;

end.
