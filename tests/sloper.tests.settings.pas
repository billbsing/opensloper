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

unit Sloper.Tests.Settings;

{$mode ObjFPC}{$H+}

interface

uses
  fpcunit, testregistry, Sloper.Tests.TestCase, Sloper.Core.Settings;

type
  TTestSettings = class(TOSTestCase)
  private
    FSettings: TAppSettings;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestDefaults;
    procedure TestTextRoundTrip;
    procedure TestFileRoundTrip;
    procedure TestMissingFileKeepsDefaults;
    procedure TestBrokenTextKeepsDefaults;
    procedure TestWrongFormatKeepsDefaults;
    procedure TestNewerVersionKeepsDefaults;
    procedure TestOutOfRangeShareIsIgnored;
    procedure TestMissingShareIsDefault;
    procedure TestLabelModeRoundTrip;
    procedure TestSidePanelRoundTrip;
    procedure TestRulersRoundTrip;
    procedure TestUnknownLabelModeIsIgnored;
    procedure TestPreferenceDefaults;
    procedure TestPreferencesRoundTrip;
    procedure TestUnusablePreferencesAreIgnored;
    procedure TestSavingPreferencesKeepsTheRest;
    procedure TestSavingPreferencesLeavesUnreadableFile;
    procedure TestCorrectedCalibration;
    procedure TestRolePresetsRoundTrip;
    procedure TestRolePresetsPassOverOddEntries;
    procedure TestSavingPresetsKeepsTheRest;
    procedure TestPutRolePresetReplacesByName;
    procedure TestOutputProfilesRoundTrip;
    procedure TestBuiltInOutputProfiles;
    procedure TestBuiltInProfileCannotBeChanged;
    procedure TestOutputProfileBadStyleIgnored;
  end;

implementation

uses
  SysUtils, Sloper.Core.Measurements, Sloper.Core.Units, Sloper.Core.JSON, Sloper.Core.Draft, Sloper.Core.OutputProfiles;

procedure TTestSettings.SetUp;
begin
  FSettings := TAppSettings.Create;
end;

procedure TTestSettings.TearDown;
begin
  FreeAndNil(FSettings);
end;

procedure TTestSettings.TestDefaults;
begin
  AssertNear('share', DefaultNameColumnShare, FSettings.NameColumnShare);
  AssertTrue('label mode', FSettings.LabelMode = lmContextual);
  AssertTrue('side panel', FSettings.ShowSidePanel);
  AssertTrue('rulers', FSettings.ShowRulers);
end;

procedure TTestSettings.TestRulersRoundTrip;
var
  Other: TAppSettings;
  Err: string;
begin
  FSettings.ShowRulers := False;
  Other := TAppSettings.Create;
  try
    AssertTrue(Err, Other.LoadFromText(FSettings.SaveToText, Err));
    AssertFalse('hidden', Other.ShowRulers);
    AssertTrue('missing means shown', Other.LoadFromText('{"format": "opensloper-settings", "version": 1}', Err));
    AssertTrue(Other.ShowRulers);
  finally
    FreeAndNil(Other);
  end;
end;

procedure TTestSettings.TestSidePanelRoundTrip;
var
  Other: TAppSettings;
  Err: string;
begin
  FSettings.ShowSidePanel := False;
  Other := TAppSettings.Create;
  try
    AssertTrue(Err, Other.LoadFromText(FSettings.SaveToText, Err));
    AssertFalse('hidden', Other.ShowSidePanel);
  finally
    FreeAndNil(Other);
  end;
end;

procedure TTestSettings.TestLabelModeRoundTrip;
var
  Other: TAppSettings;
  Err: string;
  Mode: TLabelMode;
begin
  Other := TAppSettings.Create;
  try
    for Mode := Low(TLabelMode) to High(TLabelMode) do
    begin
      FSettings.LabelMode := Mode;
      AssertTrue(Err, Other.LoadFromText(FSettings.SaveToText, Err));
      AssertTrue('label mode', Other.LabelMode = Mode);
    end;
  finally
    FreeAndNil(Other);
  end;
end;

procedure TTestSettings.TestUnknownLabelModeIsIgnored;
var
  Err: string;
begin
  FSettings.LabelMode := lmNone;
  AssertTrue(Err, FSettings.LoadFromText('{"format": "opensloper-settings", "version": 1, "labelMode": "some"}', Err));
  AssertTrue(FSettings.LabelMode = DefaultLabelMode);
end;

procedure TTestSettings.TestTextRoundTrip;
var
  Other: TAppSettings;
  Err: string;
begin
  FSettings.NameColumnShare := 0.625;
  Other := TAppSettings.Create;
  try
    AssertTrue(Err, Other.LoadFromText(FSettings.SaveToText, Err));
    AssertNear('share', 0.625, Other.NameColumnShare);
  finally
    FreeAndNil(Other);
  end;
end;

procedure TTestSettings.TestFileRoundTrip;
var
  FileName, Err: string;
  Other: TAppSettings;
begin
  FileName := GetTempFileName(GetTempDir, 'oss');
  try
    FSettings.NameColumnShare := 0.3;
    AssertTrue(Err, FSettings.SaveToFile(FileName, Err));
    Other := TAppSettings.Create;
    try
      AssertTrue(Err, Other.LoadFromFile(FileName, Err));
      AssertNear('share', 0.3, Other.NameColumnShare);
    finally
      FreeAndNil(Other);
    end;
  finally
    DeleteFile(FileName);
  end;
end;

procedure TTestSettings.TestMissingFileKeepsDefaults;
var
  Err: string;
begin
  AssertTrue('a first run is not an error',
    FSettings.LoadFromFile(ConcatPaths([GetTempDir, 'opensloper-no-such-settings.json']), Err));
  AssertNear('share', DefaultNameColumnShare, FSettings.NameColumnShare);
end;

procedure TTestSettings.TestBrokenTextKeepsDefaults;
var
  Err: string;
begin
  AssertFalse(FSettings.LoadFromText('{ not json', Err));
  AssertTrue('reports why', Err <> '');
  AssertNear('share', DefaultNameColumnShare, FSettings.NameColumnShare);
end;

procedure TTestSettings.TestWrongFormatKeepsDefaults;
var
  Err: string;
begin
  AssertFalse(FSettings.LoadFromText('{"format": "other", "version": 1, "nameColumnShare": 0.3}', Err));
  AssertTrue('reports why', Err <> '');
  AssertNear('share', DefaultNameColumnShare, FSettings.NameColumnShare);
end;

procedure TTestSettings.TestNewerVersionKeepsDefaults;
var
  Err: string;
begin
  AssertFalse(FSettings.LoadFromText('{"format": "opensloper-settings", "version": 999, "nameColumnShare": 0.3}', Err));
  AssertNear('share', DefaultNameColumnShare, FSettings.NameColumnShare);
end;

procedure TTestSettings.TestOutOfRangeShareIsIgnored;
var
  Err: string;
begin
  AssertTrue(Err, FSettings.LoadFromText('{"format": "opensloper-settings", "version": 1, "nameColumnShare": 7}', Err));
  AssertNear('share', DefaultNameColumnShare, FSettings.NameColumnShare);
end;

procedure TTestSettings.TestMissingShareIsDefault;
var
  Err: string;
begin
  FSettings.NameColumnShare := 0.3;
  AssertTrue(Err, FSettings.LoadFromText('{"format": "opensloper-settings", "version": 1}', Err));
  AssertNear('share', DefaultNameColumnShare, FSettings.NameColumnShare);
end;

procedure TTestSettings.TestPreferenceDefaults;
var
  AUnit: TMeasureUnit;
begin
  AssertTrue('unit', FSettings.Preferences.MeasureUnit = muMillimetre);
  for AUnit := Low(TMeasureUnit) to High(TMeasureUnit) do
    AssertNear(MeasureUnitNames[AUnit], DefaultGridSteps[AUnit], FSettings.Preferences.GridSteps[AUnit]);
  AssertNear('across', 1, FSettings.Preferences.Calibration.X);
  AssertNear('down', 1, FSettings.Preferences.Calibration.Y);
end;

procedure TTestSettings.TestPreferencesRoundTrip;
var
  Other: TAppSettings;
  Err: string;
begin
  FSettings.Preferences.MeasureUnit := muInch;
  FSettings.Preferences.GridSteps[muMillimetre] := 2;
  FSettings.Preferences.GridSteps[muCentimetre] := 1;
  FSettings.Preferences.GridSteps[muInch] := 0.25;
  FSettings.Preferences.Calibration.X := 1.015;
  FSettings.Preferences.Calibration.Y := 0.99;
  Other := TAppSettings.Create;
  try
    AssertTrue(Err, Other.LoadFromText(FSettings.SaveToText, Err));
    AssertTrue('unit', Other.Preferences.MeasureUnit = muInch);
    AssertNear('mm grid', 2, Other.Preferences.GridSteps[muMillimetre]);
    AssertNear('cm grid', 1, Other.Preferences.GridSteps[muCentimetre]);
    AssertNear('inch grid', 0.25, Other.Preferences.GridSteps[muInch]);
    AssertNear('across', 1.015, Other.Preferences.Calibration.X);
    AssertNear('down', 0.99, Other.Preferences.Calibration.Y);
  finally
    FreeAndNil(Other);
  end;
end;

procedure TTestSettings.TestUnusablePreferencesAreIgnored;
var
  Err: string;
begin
  AssertTrue(Err, FSettings.LoadFromText('{"format": "opensloper-settings", "version": 1, "measureUnit": "furlong",' +
    ' "gridSteps": {"mm": -1, "cm": 500, "in": 0.5}, "calibrationX": 1.02}', Err));
  AssertTrue('unit', FSettings.Preferences.MeasureUnit = muMillimetre);
  AssertNear('negative', DefaultGridSteps[muMillimetre], FSettings.Preferences.GridSteps[muMillimetre]);
  AssertNear('too large', DefaultGridSteps[muCentimetre], FSettings.Preferences.GridSteps[muCentimetre]);
  AssertNear('usable', 0.5, FSettings.Preferences.GridSteps[muInch]);
  AssertNear('only one factor', 1, FSettings.Preferences.Calibration.X);
  AssertTrue(Err, FSettings.LoadFromText('{"format": "opensloper-settings", "version": 1, "calibrationX": 0, "calibrationY": 1}', Err));
  AssertNear('zero', 1, FSettings.Preferences.Calibration.X);
end;

procedure TTestSettings.TestSavingPreferencesKeepsTheRest;
var
  FileName, Err: string;
  Preferences: TPreferences;
begin
  FileName := GetTempFileName(GetTempDir, 'oss');
  try
    FSettings.NameColumnShare := 0.3;
    FSettings.ShowRulers := False;
    AssertTrue(Err, FSettings.SaveToFile(FileName, Err));
    Preferences := DefaultPreferences;
    Preferences.MeasureUnit := muCentimetre;
    Preferences.Calibration.X := 1.01;
    AssertTrue(Err, SavePreferencesToFile(FileName, Preferences, Err));
    AssertTrue(Err, FSettings.LoadFromFile(FileName, Err));
    AssertNear('share kept', 0.3, FSettings.NameColumnShare);
    AssertFalse('rulers kept', FSettings.ShowRulers);
    AssertTrue('unit', FSettings.Preferences.MeasureUnit = muCentimetre);
    AssertNear('across', 1.01, FSettings.Preferences.Calibration.X);
  finally
    DeleteFile(FileName);
  end;
end;

procedure TTestSettings.TestSavingPreferencesLeavesUnreadableFile;
const
  Newer = '{"format": "opensloper-settings", "version": 999}';
var
  FileName, Err, Text: string;
begin
  FileName := GetTempFileName(GetTempDir, 'oss');
  try
    AssertTrue(Err, WriteTextFile(FileName, Newer, Err));
    AssertFalse('refused', SavePreferencesToFile(FileName, DefaultPreferences, Err));
    AssertTrue('says why', Err <> '');
    AssertTrue(Err, ReadTextFile(FileName, Text, Err));
    AssertEquals('untouched', Newer, Text);
  finally
    DeleteFile(FileName);
  end;
end;

procedure TTestSettings.TestCorrectedCalibration;
begin
  // A 10 cm square printed 98.5 mm with no correction
  AssertNear('first time', 100 / 98.5, CorrectedCalibration(1, 100, 98.5));
  // Printed with 1.01 and still 1 % short: the new factor builds on the old
  AssertNear('again', 1.01 * 100 / 99, CorrectedCalibration(1.01, 100, 99));
  AssertNear('nothing measured', 1.02, CorrectedCalibration(1.02, 100, 0));
end;

procedure TTestSettings.TestRolePresetsRoundTrip;
var
  Preset: TRolePreset;
  Loaded: TAppSettings;
  Err: string;
begin
  Preset.Name := 'Seams only';
  Preset.Hidden := [erConstruction, erPlacement];
  PutRolePreset(FSettings.RolePresets, Preset);
  Loaded := TAppSettings.Create;
  try
    AssertTrue(Err, Loaded.LoadFromText(FSettings.SaveToText, Err));
    AssertEquals(1, Length(Loaded.RolePresets));
    AssertEquals('Seams only', Loaded.RolePresets[0].Name);
    AssertTrue(Loaded.RolePresets[0].Hidden = [erConstruction, erPlacement]);
  finally
    FreeAndNil(Loaded);
  end;
end;

procedure TTestSettings.TestRolePresetsPassOverOddEntries;
var
  Err: string;
begin
  AssertTrue(Err, FSettings.LoadFromText('{"format": "opensloper-settings", "version": 1, "rolePresets": [' +
    '{"name": "", "hidden": ["stitch"]}, 4, {"name": "Leather", "hidden": ["outline", "fold", "hem"]}]}', Err));
  AssertEquals(1, Length(FSettings.RolePresets));
  AssertTrue('outline never hidden', FSettings.RolePresets[0].Hidden = [erFold]);
end;

procedure TTestSettings.TestSavingPresetsKeepsTheRest;
var
  FileName, Err: string;
  Presets: TRolePresetArray;
begin
  FileName := GetTempFileName(GetTempDir, 'oss');
  try
    FSettings.ShowRulers := False;
    AssertTrue(Err, FSettings.SaveToFile(FileName, Err));
    Presets := nil;
    SetLength(Presets, 1);
    Presets[0].Name := 'Cut';
    Presets[0].Hidden := [erStitch];
    AssertTrue(Err, SaveRolePresetsToFile(FileName, Presets, Err));
    AssertTrue(Err, FSettings.LoadFromFile(FileName, Err));
    AssertFalse('rulers kept', FSettings.ShowRulers);
    AssertEquals(1, Length(FSettings.RolePresets));
  finally
    DeleteFile(FileName);
  end;
end;

procedure TTestSettings.TestPutRolePresetReplacesByName;
var
  Presets: TRolePresetArray;
  Preset: TRolePreset;
begin
  Presets := nil;
  Preset.Name := 'Mine';
  Preset.Hidden := [erStitch];
  PutRolePreset(Presets, Preset);
  Preset.Name := 'MINE';
  Preset.Hidden := [erFold];
  PutRolePreset(Presets, Preset);
  AssertEquals(1, Length(Presets));
  AssertTrue(Presets[0].Hidden = [erFold]);
  RemoveRolePreset(Presets, 'mine');
  AssertEquals(0, Length(Presets));
end;

procedure TTestSettings.TestOutputProfilesRoundTrip;
var
  Profile, Found: TOutputProfile;
  Loaded: TAppSettings;
  Err: string;
begin
  Profile := FullOutputProfile;
  Profile.Name := 'Topstitch sheet';
  Profile.Roles := [erStitch];
  Profile.PieceMarks := [pkNotches, pkLabels];
  Profile.Allowance := apNone;
  Profile.Styles[erStitch].Custom := True;
  Profile.Styles[erStitch].Color := '#336699';
  Profile.Styles[erStitch].Dashes[0] := 2;
  Profile.Styles[erStitch].Dashes[1] := 1;
  Profile.Styles[erStitch].Width := 0.5;
  FSettings.OutputProfiles := [Profile];
  Loaded := TAppSettings.Create;
  try
    AssertTrue(Err, Loaded.LoadFromText(FSettings.SaveToText, Err));
    AssertTrue(FindOutputProfile(Loaded.OutputProfiles, 'topstitch SHEET', Found));
    AssertTrue(Found.Roles = [erStitch]);
    AssertTrue(Found.PieceMarks = [pkNotches, pkLabels]);
    AssertTrue(Found.Allowance = apNone);
    AssertTrue(Found.Styles[erStitch].Custom);
    AssertEquals('#336699', Found.Styles[erStitch].Color);
    AssertEquals(1, Found.Styles[erStitch].Dashes[1], 1e-9);
    AssertFalse('others keep their look', Found.Styles[erFold].Custom);
  finally
    FreeAndNil(Loaded);
  end;
end;

procedure TTestSettings.TestBuiltInOutputProfiles;
var
  Found: TOutputProfile;
begin
  AssertEquals(4, Length(BuiltInOutputProfiles));
  AssertTrue(FindOutputProfile(nil, 'Leather', Found));
  AssertTrue(Found.Allowance = apNone);
  AssertTrue(Found.Roles = [erStitch, erCut, erSkive, erEdgeFinish]);
  AssertFalse('no seam line', pkSeamLine in Found.PieceMarks);
  AssertTrue(FindOutputProfile(nil, 'Plotter or laser cutter', Found));
  AssertTrue(Found.Roles = [erCut]);
  AssertFalse('unknown', FindOutputProfile(nil, 'Nothing like it', Found));
  AssertTrue('falls back to everything', Found.Roles = MarkingRoles);
end;

// A copy must take a new name; one under a built-in name is left out
procedure TTestSettings.TestBuiltInProfileCannotBeChanged;
var
  Found: TOutputProfile;
  Err: string;
begin
  AssertTrue(Err, FSettings.LoadFromText('{"format": "opensloper-settings", "version": 1, "outputProfiles": [' +
    '{"name": "leather", "roles": ["fold"], "allowance": "keep"}, {"name": "My leather", "roles": ["stitch"]}]}', Err));
  AssertEquals(1, Length(FSettings.OutputProfiles));
  AssertTrue(FindOutputProfile(FSettings.OutputProfiles, 'Leather', Found));
  AssertTrue('the built-in one', Found.Allowance = apNone);
  AssertEquals(5, Length(AllOutputProfiles(FSettings.OutputProfiles)));
end;

procedure TTestSettings.TestOutputProfileBadStyleIgnored;
var
  Err: string;
begin
  AssertTrue(Err, FSettings.LoadFromText('{"format": "opensloper-settings", "version": 1, "outputProfiles": [' +
    '{"name": "Odd", "styles": {"stitch": {"color": "blue", "width": 1}, "fold": {"color": "#000000", "width": 0.2, "dash": [3, -1]}}}]}', Err));
  AssertFalse(FSettings.OutputProfiles[0].Styles[erStitch].Custom);
  AssertFalse(FSettings.OutputProfiles[0].Styles[erFold].Custom);
  AssertTrue('everything when not listed', FSettings.OutputProfiles[0].Roles = MarkingRoles);
end;

initialization
  RegisterTest(TTestSettings);

end.
