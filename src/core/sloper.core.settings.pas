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
// that belong to the user rather than to a pattern, such as panel layout.
// A missing file is a first run, so the defaults stand. No LCL dependency.
unit Sloper.Core.Settings;

{$mode ObjFPC}{$H+}

interface

uses
  Sloper.Core.Measurements;

type
  // Which labels the canvas shows: those that help the current step, all, or none
  TLabelMode = (lmContextual, lmAll, lmNone);

const
  DefaultNameColumnShare = 0.45;
  DefaultLabelMode = lmContextual;

type
  TAppSettings = class
  public
    // The part of the properties panel's row width given to field names, above 0 and below 1
    NameColumnShare: double;
    LabelMode: TLabelMode;
    ShowSidePanel: boolean;
    // Whether the drafting canvas fills pieces with their fabric
    ShowPieceFills: boolean;
    // How the measurements app shows values
    MeasureUnit: TMeasureUnit;
    constructor Create;
    procedure Reset;
    function SaveToText: string;
    // On failure the defaults stand and ErrorMessage says why
    function LoadFromText(const Text: string; out ErrorMessage: string): boolean;
    function SaveToFile(const FileName: string; out ErrorMessage: string): boolean;
    function LoadFromFile(const FileName: string; out ErrorMessage: string): boolean;
  end;

resourcestring
  rsSettingsWrongFormat = 'This is not an OpenSloper settings file';
  rsSettingsNewerVersion = 'This file was made by a newer version of OpenSloper (file version %d)';

implementation

uses
  SysUtils, fpjson, Sloper.Core.JSON;

const
  SettingsFormat = 'opensloper-settings';
  SettingsVersion = 1;
  LabelModeNames: array[TLabelMode] of string = ('contextual', 'all', 'none');

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
  ShowPieceFills := True;
  MeasureUnit := muMillimetre;
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
    Obj.Add('showPieceFills', ShowPieceFills);
    Obj.Add('measureUnit', MeasureUnitNames[MeasureUnit]);
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
    if GetJSONBoolean(Obj, 'showPieceFills', Shown) then
      ShowPieceFills := Shown;
    if GetJSONString(Obj, 'measureUnit', TextValue) then
      for AUnit := Low(TMeasureUnit) to High(TMeasureUnit) do
        if TextValue = MeasureUnitNames[AUnit] then
          MeasureUnit := AUnit;
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

end.
