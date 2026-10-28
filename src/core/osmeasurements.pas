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
unit osMeasurements;

{$mode ObjFPC}{$H+}

interface

uses
  Classes, SysUtils, fpjson;

const
  MeasurementFormat = 'measurements';
  MeasurementVersion = 1;

type
  EMeasurementError = class(Exception);

  TMeasurement = class
  private
    FKey: string;
  public
    Value: Double;       // mm
    Description: string;
    property Key: string read FKey;
  end;

  TMeasurementSet = class
  private
    FItems: TList;
    function GetCount: Integer;
    function GetItem(Index: Integer): TMeasurement;
    function ToJSON: TJSONObject;
  public
    Name: string;
    Notes: string;
    constructor Create;
    destructor Destroy; override;
    procedure Clear;
    // Keys are compared without regard to case
    function IndexOf(const Key: string): Integer;
    function Find(const Key: string): TMeasurement;
    function TryGetValue(const Key: string; out Value: Double): Boolean;
    // Checks that Key is valid and not used by another measurement than Exclude
    function CheckKey(const Key: string; Exclude: TMeasurement; out ErrorMessage: string): Boolean;
    // Add and Rename raise EMeasurementError for a key that fails CheckKey
    function Add(const Key: string; Value: Double; const Description: string = ''): TMeasurement;
    procedure Rename(Measurement: TMeasurement; const NewKey: string);
    procedure Delete(Measurement: TMeasurement);
    function SaveToText: string;
    // On failure the set is left empty and ErrorMessage says why
    function LoadFromText(const Text: string; out ErrorMessage: string): Boolean;
    function SaveToFile(const FileName: string; out ErrorMessage: string): Boolean;
    function LoadFromFile(const FileName: string; out ErrorMessage: string): Boolean;
    property Count: Integer read GetCount;
    property Items[Index: Integer]: TMeasurement read GetItem; default;
  end;

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
  osNames, osJSON;

constructor TMeasurementSet.Create;
begin
  FItems := TList.Create;
end;

destructor TMeasurementSet.Destroy;
begin
  Clear;
  FItems.Free;
  inherited Destroy;
end;

procedure TMeasurementSet.Clear;
var
  Index: Integer;
begin
  for Index := 0 to FItems.Count - 1 do
    TMeasurement(FItems[Index]).Free;
  FItems.Clear;
  Name := '';
  Notes := '';
end;

function TMeasurementSet.GetCount: Integer;
begin
  Result := FItems.Count;
end;

function TMeasurementSet.GetItem(Index: Integer): TMeasurement;
begin
  Result := TMeasurement(FItems[Index]);
end;

function TMeasurementSet.IndexOf(const Key: string): Integer;
begin
  for Result := 0 to FItems.Count - 1 do
    if SameName(Items[Result].Key, Key) then
      Exit;
  Result := -1;
end;

function TMeasurementSet.Find(const Key: string): TMeasurement;
var
  Index: Integer;
begin
  Index := IndexOf(Key);
  if Index < 0 then
    Result := nil
  else
    Result := Items[Index];
end;

function TMeasurementSet.TryGetValue(const Key: string; out Value: Double): Boolean;
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
  out ErrorMessage: string): Boolean;
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

function TMeasurementSet.Add(const Key: string; Value: Double;
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
end;

procedure TMeasurementSet.Rename(Measurement: TMeasurement; const NewKey: string);
var
  Msg: string;
begin
  if not CheckKey(NewKey, Measurement, Msg) then
    raise EMeasurementError.Create(Msg);
  Measurement.FKey := NewKey;
end;

procedure TMeasurementSet.Delete(Measurement: TMeasurement);
begin
  if FItems.Remove(Measurement) >= 0 then
    Measurement.Free;
end;

function TMeasurementSet.ToJSON: TJSONObject;
var
  List: TJSONArray;
  Item: TJSONObject;
  Index: Integer;
begin
  Result := TJSONObject.Create;
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
    Item.Add('key', Items[Index].Key);
    Item.Add('value', JSONFloat(Items[Index].Value));
    Item.Add('description', Items[Index].Description);
    List.Add(Item);
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
    Obj.Free;
  end;
end;

function TMeasurementSet.LoadFromText(const Text: string; out ErrorMessage: string): Boolean;
var
  Obj, Item: TJSONObject;
  List: TJSONData;
  TextValue, Key, Desc: string;
  Version, Index: Integer;
  Value: Double;
  KeyError: string;

  function Fail(const Msg: string): Boolean;
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
    Obj.Free;
  end;
end;

function TMeasurementSet.SaveToFile(const FileName: string; out ErrorMessage: string): Boolean;
begin
  Result := WriteTextFile(FileName, SaveToText, ErrorMessage);
end;

function TMeasurementSet.LoadFromFile(const FileName: string; out ErrorMessage: string): Boolean;
var
  Text: string;
begin
  Clear;
  if not ReadTextFile(FileName, Text, ErrorMessage) then
    Exit(False);
  Result := LoadFromText(Text, ErrorMessage);
end;

end.
