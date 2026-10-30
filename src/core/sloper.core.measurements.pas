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

// Measurement sets: a person's body measurements, kept in their own file
// (.slm) so one set can drive many patterns. Patterns refer to measurements
// by key (@waist). Values are in millimetres. No LCL dependency.
unit Sloper.Core.Measurements;

{$mode ObjFPC}{$H+}

interface

uses
  SysUtils, Generics.Collections, fpjson;

const
  MeasurementFormat = 'measurements';
  MeasurementVersion = 1;

type
  EMeasurementError = class(Exception);

  TMeasurement = class
  private
    FKey: string;
  public
    Value: double;       // mm
    Description: string;
    property Key: string read FKey;
  end;

  TMeasurementList = specialize TObjectList<TMeasurement>;
  TMeasurementMap = specialize TDictionary<string, TMeasurement>;

  TMeasurementSet = class
  private
    FItems: TMeasurementList;
    // Measurements by key in lower case, for Find
    FByKey: TMeasurementMap;
    function GetCount: integer;
    function GetItem(Index: integer): TMeasurement;
    function ToJSON: TJSONObject;
  public
    Name: string;
    Notes: string;
    constructor Create;
    destructor Destroy; override;
    procedure Clear;
    // Keys are compared without regard to case
    function IndexOf(const Key: string): integer;
    function Find(const Key: string): TMeasurement;
    function TryGetValue(const Key: string; out Value: double): boolean;
    // Checks that Key is valid and not used by another measurement than Exclude
    function CheckKey(const Key: string; Exclude: TMeasurement; out ErrorMessage: string): boolean;
    // Add and Rename raise EMeasurementError for a key that fails CheckKey
    function Add(const Key: string; Value: double; const Description: string = ''): TMeasurement;
    procedure Rename(Measurement: TMeasurement; const NewKey: string);
    procedure Delete(Measurement: TMeasurement);
    function SaveToText: string;
    // On failure the set is left empty and ErrorMessage says why
    function LoadFromText(const Text: string; out ErrorMessage: string): boolean;
    function SaveToFile(const FileName: string; out ErrorMessage: string): boolean;
    function LoadFromFile(const FileName: string; out ErrorMessage: string): boolean;
    property Count: integer read GetCount;
    property Items[Index: integer]: TMeasurement read GetItem; default;
  end;

  // One small edit to a measurement file
  TMeasurementChange = record
    Key: string;
    Value: double;
    // The value before, unless the key is new
    OldValue: double;
    Added: boolean;
  end;

// Re-reads the file, gives Key this value and description, adding it when it
// is new, and writes the file atomically, so a change made elsewhere to any
// other key is kept. On failure the file is left as it was.
function ChangeMeasurementInFile(const FileName, Key: string; Value: double; const Description: string;
  out Change: TMeasurementChange; out ErrorMessage: string): boolean;
// A new, empty measurement file
function CreateMeasurementFile(const FileName: string; out ErrorMessage: string): boolean;

resourcestring
  rsMeasurementWrongFormat = 'This is not a measurements file';
  rsMeasurementNewerVersion = 'This file was made by a newer version of OpenSloper (file version %d)';
  rsMeasurementUnits = 'Units "%s" are not supported; use mm';
  rsMeasurementMissing = 'A measurement has no "%s"';
  rsMeasurementBadValue = 'Measurement "%s" has no valid value';
  rsMeasurementBadKey = 'Measurement key: %s';
  rsMeasurementList = 'The file has no list of measurements';

implementation

uses
  Sloper.Core.Names, Sloper.Core.JSON;

constructor TMeasurementSet.Create;
begin
  FItems := TMeasurementList.Create;
  FByKey := TMeasurementMap.Create;
end;

destructor TMeasurementSet.Destroy;
begin
  Clear;
  FreeAndNil(FByKey);
  FreeAndNil(FItems);
  inherited Destroy;
end;

procedure TMeasurementSet.Clear;
begin
  FByKey.Clear;
  FItems.Clear;
  Name := '';
  Notes := '';
end;

function TMeasurementSet.GetCount: integer;
begin
  Result := FItems.Count;
end;

function TMeasurementSet.GetItem(Index: integer): TMeasurement;
begin
  Result := FItems[Index];
end;

function TMeasurementSet.IndexOf(const Key: string): integer;
var
  Measurement: TMeasurement;
begin
  Measurement := Find(Key);
  if Measurement = nil then
    Result := -1
  else
    Result := FItems.IndexOf(Measurement);
end;

// Keys follow the name rules (ASCII letters, digits, underscore), so
// LowerCase gives the same result as SameName
function TMeasurementSet.Find(const Key: string): TMeasurement;
begin
  if not FByKey.TryGetValue(LowerCase(Key), Result) then
    Result := nil;
end;

function TMeasurementSet.TryGetValue(const Key: string; out Value: double): boolean;
var
  Measurement: TMeasurement;
begin
  Measurement := Find(Key);
  Result := Measurement <> nil;
  if Result then
    Value := Measurement.Value
  else
    Value := 0;
end;

function TMeasurementSet.CheckKey(const Key: string; Exclude: TMeasurement;
  out ErrorMessage: string): boolean;
var
  Existing: TMeasurement;
begin
  if not CheckName(Key, ErrorMessage) then
    Exit(False);
  Existing := Find(Key);
  if (Existing <> nil) and (Existing <> Exclude) then
  begin
    ErrorMessage := Format(rsNameTaken, [Key]);
    Exit(False);
  end;
  Result := True;
end;

function TMeasurementSet.Add(const Key: string; Value: double;
  const Description: string): TMeasurement;
var
  Msg: string;
begin
  if not CheckKey(Key, nil, Msg) then
    raise EMeasurementError.Create(Msg);
  Result := TMeasurement.Create;
  Result.FKey := Key;
  Result.Value := Value;
  Result.Description := Description;
  FItems.Add(Result);
  FByKey.Add(LowerCase(Key), Result);
end;

procedure TMeasurementSet.Rename(Measurement: TMeasurement; const NewKey: string);
var
  Msg: string;
begin
  if not CheckKey(NewKey, Measurement, Msg) then
    raise EMeasurementError.Create(Msg);
  FByKey.Remove(LowerCase(Measurement.FKey));
  Measurement.FKey := NewKey;
  FByKey.Add(LowerCase(NewKey), Measurement);
end;

procedure TMeasurementSet.Delete(Measurement: TMeasurement);
begin
  // The list owns its measurements, so removing frees it
  if FItems.IndexOf(Measurement) >= 0 then
  begin
    FByKey.Remove(LowerCase(Measurement.Key));
    FItems.Remove(Measurement);
  end;
end;

function TMeasurementSet.ToJSON: TJSONObject;
var
  List: TJSONArray;
  Item: TJSONObject;
  Index: integer;
begin
  Result := TJSONObject.Create;
  try
    Result.Add('format', MeasurementFormat);
    Result.Add('version', MeasurementVersion);
    Result.Add('units', 'mm');
    Result.Add('name', Name);
    Result.Add('notes', Notes);
    List := TJSONArray.Create;
    Result.Add('measurements', List);
    for Index := 0 to Count - 1 do
    begin
      Item := TJSONObject.Create;
      List.Add(Item);
      Item.Add('key', Items[Index].Key);
      Item.Add('value', JSONFloat(Items[Index].Value));
      Item.Add('description', Items[Index].Description);
    end;
  except
    FreeAndNil(Result);
    raise;
  end;
end;

function TMeasurementSet.SaveToText: string;
var
  Obj: TJSONObject;
begin
  Obj := ToJSON;
  try
    Result := JSONToText(Obj);
  finally
    FreeAndNil(Obj);
  end;
end;

function TMeasurementSet.LoadFromText(const Text: string; out ErrorMessage: string): boolean;
var
  Obj, Item: TJSONObject;
  List: TJSONData;
  TextValue, Key, Desc: string;
  Version, Index: integer;
  Value: double;
  KeyError: string;

  function Fail(const Msg: string): boolean;
  begin
    ErrorMessage := Msg;
    Clear;
    Result := False;
  end;

begin
  Clear;
  if not ParseJSONObject(Text, Obj, ErrorMessage) then
    Exit(False);
  try
    if not GetJSONString(Obj, 'format', TextValue) or (TextValue <> MeasurementFormat) then
      Exit(Fail(rsMeasurementWrongFormat));
    if not GetJSONInteger(Obj, 'version', Version) then
      Exit(Fail(rsMeasurementWrongFormat));
    if Version > MeasurementVersion then
      Exit(Fail(Format(rsMeasurementNewerVersion, [Version])));
    if GetJSONString(Obj, 'units', TextValue) and (TextValue <> 'mm') then
      Exit(Fail(Format(rsMeasurementUnits, [TextValue])));
    GetJSONString(Obj, 'name', Name);
    GetJSONString(Obj, 'notes', Notes);
    List := Obj.Find('measurements');
    if (List = nil) or (List.JSONType <> jtArray) then
      Exit(Fail(rsMeasurementList));
    for Index := 0 to List.Count - 1 do
    begin
      if List.Items[Index].JSONType <> jtObject then
        Exit(Fail(Format(rsMeasurementMissing, ['key'])));
      Item := TJSONObject(List.Items[Index]);
      if not GetJSONString(Item, 'key', Key) then
        Exit(Fail(Format(rsMeasurementMissing, ['key'])));
      if not CheckKey(Key, nil, KeyError) then
        Exit(Fail(Format(rsMeasurementBadKey, [KeyError])));
      if not GetJSONNumber(Item, 'value', Value) then
        Exit(Fail(Format(rsMeasurementBadValue, [Key])));
      GetJSONString(Item, 'description', Desc);
      Add(Key, Value, Desc);
    end;
    Result := True;
  finally
    FreeAndNil(Obj);
  end;
end;

function TMeasurementSet.SaveToFile(const FileName: string; out ErrorMessage: string): boolean;
begin
  Result := WriteTextFile(FileName, SaveToText, ErrorMessage);
end;

function TMeasurementSet.LoadFromFile(const FileName: string; out ErrorMessage: string): boolean;
var
  Text: string;
begin
  Clear;
  if not ReadTextFile(FileName, Text, ErrorMessage) then
    Exit(False);
  Result := LoadFromText(Text, ErrorMessage);
end;

function ChangeMeasurementInFile(const FileName, Key: string; Value: double; const Description: string;
  out Change: TMeasurementChange; out ErrorMessage: string): boolean;
var
  MeasurementSet: TMeasurementSet;
  Existing: TMeasurement;
begin
  Result := False;
  Change := Default(TMeasurementChange);
  MeasurementSet := TMeasurementSet.Create;
  try
    if not MeasurementSet.LoadFromFile(FileName, ErrorMessage) then
      Exit;
    Existing := MeasurementSet.Find(Key);
    if Existing = nil then
    begin
      if not MeasurementSet.CheckKey(Key, nil, ErrorMessage) then
        Exit;
      Change.Key := Key;
      Change.Added := True;
      MeasurementSet.Add(Key, Value, Description);
    end
    else
    begin
      Change.Key := Existing.Key;
      Change.OldValue := Existing.Value;
      Existing.Value := Value;
      Existing.Description := Description;
    end;
    Change.Value := Value;
    Result := WriteTextFileAtomic(FileName, MeasurementSet.SaveToText, ErrorMessage);
  finally
    FreeAndNil(MeasurementSet);
  end;
end;

function CreateMeasurementFile(const FileName: string; out ErrorMessage: string): boolean;
var
  MeasurementSet: TMeasurementSet;
begin
  MeasurementSet := TMeasurementSet.Create;
  try
    Result := WriteTextFileAtomic(FileName, MeasurementSet.SaveToText, ErrorMessage);
  finally
    FreeAndNil(MeasurementSet);
  end;
end;

end.
