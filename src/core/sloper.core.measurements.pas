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

// Measurement sets: a person's body measurements, or a table of them by size,
// kept in their own file (.slm) so one set can drive many patterns. Patterns
// refer to measurements by key (@waist). Values are in millimetres. No LCL
// dependency.
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

  TMeasurementSet = class;

  TMeasurementCell = record
    Value: double;       // mm
    Present: boolean;
  end;

  TMeasurement = class
  private
    FKey: string;
    FOwner: TMeasurementSet;
    // One per size; a personal set has just the one, always present
    FCells: array of TMeasurementCell;
    function GetValue: double;
    procedure SetValue(AValue: double);
  public
    Description: string;
    // For the set's selected size; a size with no value reads as 0
    function HasValue: boolean;
    function HasValueFor(SizeIndex: integer): boolean;
    function ValueFor(SizeIndex: integer): double;
    procedure SetValueFor(SizeIndex: integer; AValue: double);
    procedure ClearValueFor(SizeIndex: integer);
    property Key: string read FKey;
    property Value: double read GetValue write SetValue;
  end;

  TMeasurementList = specialize TObjectList<TMeasurement>;
  TMeasurementMap = specialize TDictionary<string, TMeasurement>;

  TMeasurementSet = class
  private
    FItems: TMeasurementList;
    // Measurements by key in lower case, for Find
    FByKey: TMeasurementMap;
    FSizes: TStringArray;
    FSizeIndex: integer;
    function GetCount: integer;
    function GetItem(Index: integer): TMeasurement;
    function GetSize(Index: integer): string;
    function GetSizeCount: integer;
    function GetSizeName: string;
    function LoadSizes(Obj: TJSONObject; out ErrorMessage: string): boolean;
    function LoadValues(Item: TJSONObject; Measurement: TMeasurement; out ErrorMessage: string): boolean;
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
    procedure Move(Measurement: TMeasurement; NewIndex: integer);
    // Sizes are compared without regard to case. Values follow the selected
    // size, the first until another is selected.
    function IndexOfSize(const Size: string): integer;
    function SelectSize(const Size: string): boolean;
    function CheckSize(const Size: string; Exclude: integer; out ErrorMessage: string): boolean;
    // The first size of a personal set takes over its values; a later size
    // starts with none. These raise EMeasurementError for a size that fails
    // CheckSize, and DeleteSize for the last size, since every table has one.
    procedure AddSize(const Size: string);
    procedure RenameSize(Index: integer; const NewSize: string);
    procedure DeleteSize(Index: integer);
    procedure MoveSize(Index, NewIndex: integer);
    // Why Key has no value: not in the set, or not for the selected size
    function ValueProblem(const Key: string): string;
    function SaveToText: string;
    // On failure the set is left empty and ErrorMessage says why
    function LoadFromText(const Text: string; out ErrorMessage: string): boolean;
    function SaveToFile(const FileName: string; out ErrorMessage: string): boolean;
    function LoadFromFile(const FileName: string; out ErrorMessage: string): boolean;
    property Count: integer read GetCount;
    property Items[Index: integer]: TMeasurement read GetItem; default;
    property SizeCount: integer read GetSizeCount;
    property Sizes[Index: integer]: string read GetSize;
    property SizeIndex: integer read FSizeIndex;
    // Empty for a personal set
    property SizeName: string read GetSizeName;
  end;

  // How values are shown and typed; files always store mm
  TMeasureUnit = (muMillimetre, muCentimetre, muInch);

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
// other key is kept. A size table needs Size, and a personal set refuses one.
// On failure the file is left as it was.
function ChangeMeasurementInFile(const FileName, Key: string; Value: double; const Description: string;
  out Change: TMeasurementChange; out ErrorMessage: string; const Size: string = ''): boolean;
// A value in mm, as shown in this unit
function FormatMeasure(Millimetres: double; AUnit: TMeasureUnit): string;
// Text in this unit, in mm. A comma is taken as the decimal point.
function ParseMeasure(const Text: string; AUnit: TMeasureUnit; out Millimetres: double): boolean;
// A three-way merge by key of two sets that both started from Base. A key
// changed on one side takes that side; one changed on both is a conflict, which
// keeps Mine and is listed, unless it is in TakeTheirs. Merged is filled in.
procedure MergeMeasurementSets(Base, Mine, Theirs: TMeasurementSet; const TakeTheirs: TStringArray; Merged: TMeasurementSet;
  out Conflicts: TStringArray);
// A new, empty measurement file
function CreateMeasurementFile(const FileName: string; out ErrorMessage: string): boolean;

const
  MeasureUnitNames: array[TMeasureUnit] of string = ('mm', 'cm', 'in');

resourcestring
  rsMeasurementWrongFormat = 'This is not a measurements file';
  rsMeasurementNewerVersion = 'This file was made by a newer version of OpenSloper (file version %d)';
  rsMeasurementUnits = 'Units "%s" are not supported; use mm';
  rsMeasurementMissing = 'A measurement has no "%s"';
  rsMeasurementBadValue = 'Measurement "%s" has no valid value';
  rsMeasurementBadKey = 'Measurement key: %s';
  rsMeasurementList = 'The file has no list of measurements';
  rsMeasurementNotInSet = '@%s is not in the measurement set';
  rsMeasurementNoSizeValue = '@%s has no value for size %s';
  rsMeasurementBadValues = 'Measurement "%s" needs one value for each of the %d sizes';
  rsMeasurementBadSizes = '"sizes" must be a list of size names';
  rsMeasurementSizeEmpty = 'A size needs a name';
  rsMeasurementSizeTaken = 'Size "%s" is already in the table';
  rsMeasurementLastSize = 'A size table needs at least one size';
  rsMeasurementNeedsSize = 'This is a size table, so a size is needed';
  rsMeasurementUnknownSize = 'Size "%s" is not in the measurement set';

implementation

uses
  Classes, Math, Sloper.Core.Names, Sloper.Core.JSON;

const
  MillimetresPerUnit: array[TMeasureUnit] of double = (1, 10, 25.4);
  // Enough places to tell 0.1 mm apart in each unit
  MeasureFormats: array[TMeasureUnit] of string = ('0.######', '0.####', '0.####');
  MaxMeasure = 1e12;

function TMeasurement.GetValue: double;
begin
  Result := ValueFor(FOwner.SizeIndex);
end;

procedure TMeasurement.SetValue(AValue: double);
begin
  SetValueFor(FOwner.SizeIndex, AValue);
end;

function TMeasurement.HasValue: boolean;
begin
  Result := HasValueFor(FOwner.SizeIndex);
end;

function TMeasurement.HasValueFor(SizeIndex: integer): boolean;
begin
  Result := FCells[SizeIndex].Present;
end;

function TMeasurement.ValueFor(SizeIndex: integer): double;
begin
  if FCells[SizeIndex].Present then
    Result := FCells[SizeIndex].Value
  else
    Result := 0;
end;

procedure TMeasurement.SetValueFor(SizeIndex: integer; AValue: double);
begin
  FCells[SizeIndex].Value := AValue;
  FCells[SizeIndex].Present := True;
end;

procedure TMeasurement.ClearValueFor(SizeIndex: integer);
begin
  FCells[SizeIndex].Present := False;
end;

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
  FSizes := nil;
  FSizeIndex := 0;
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

function TMeasurementSet.GetSize(Index: integer): string;
begin
  Result := FSizes[Index];
end;

function TMeasurementSet.GetSizeCount: integer;
begin
  Result := Length(FSizes);
end;

function TMeasurementSet.GetSizeName: string;
begin
  if FSizes = nil then
    Result := ''
  else
    Result := FSizes[FSizeIndex];
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
  Value := 0;
  Result := (Measurement <> nil) and Measurement.HasValue;
  if Result then
    Value := Measurement.Value;
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
  Result.FOwner := Self;
  SetLength(Result.FCells, Max(SizeCount, 1));
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

procedure TMeasurementSet.Move(Measurement: TMeasurement; NewIndex: integer);
begin
  FItems.Move(FItems.IndexOf(Measurement), NewIndex);
end;

function TMeasurementSet.IndexOfSize(const Size: string): integer;
begin
  for Result := 0 to High(FSizes) do
    if SameText(FSizes[Result], Size) then
      Exit;
  Result := -1;
end;

function TMeasurementSet.SelectSize(const Size: string): boolean;
var
  Index: integer;
begin
  Index := IndexOfSize(Size);
  Result := Index >= 0;
  if Result then
    FSizeIndex := Index;
end;

function TMeasurementSet.CheckSize(const Size: string; Exclude: integer; out ErrorMessage: string): boolean;
var
  Existing: integer;
begin
  ErrorMessage := '';
  if Trim(Size) = '' then
  begin
    ErrorMessage := rsMeasurementSizeEmpty;
    Exit(False);
  end;
  Existing := IndexOfSize(Size);
  if (Existing >= 0) and (Existing <> Exclude) then
  begin
    ErrorMessage := Format(rsMeasurementSizeTaken, [Size]);
    Exit(False);
  end;
  Result := True;
end;

procedure TMeasurementSet.AddSize(const Size: string);
var
  Msg: string;
  Index: integer;
begin
  if not CheckSize(Size, -1, Msg) then
    raise EMeasurementError.Create(Msg);
  if FSizes <> nil then
    for Index := 0 to Count - 1 do
      SetLength(Items[Index].FCells, Length(Items[Index].FCells) + 1);
  SetLength(FSizes, Length(FSizes) + 1);
  FSizes[High(FSizes)] := Size;
end;

procedure TMeasurementSet.RenameSize(Index: integer; const NewSize: string);
var
  Msg: string;
begin
  if not CheckSize(NewSize, Index, Msg) then
    raise EMeasurementError.Create(Msg);
  FSizes[Index] := NewSize;
end;

procedure TMeasurementSet.DeleteSize(Index: integer);
var
  ItemIndex: integer;
begin
  if SizeCount = 1 then
    raise EMeasurementError.Create(rsMeasurementLastSize);
  for ItemIndex := 0 to Count - 1 do
    System.Delete(Items[ItemIndex].FCells, Index, 1);
  System.Delete(FSizes, Index, 1);
  if FSizeIndex > Index then
    Dec(FSizeIndex)
  else
    FSizeIndex := Min(FSizeIndex, High(FSizes));
end;

procedure TMeasurementSet.MoveSize(Index, NewIndex: integer);
var
  ItemIndex: integer;
  Selected, Moved: string;
  Cell: TMeasurementCell;
begin
  Selected := SizeName;
  Moved := FSizes[Index];
  System.Delete(FSizes, Index, 1);
  System.Insert(Moved, FSizes, NewIndex);
  for ItemIndex := 0 to Count - 1 do
  begin
    Cell := Items[ItemIndex].FCells[Index];
    System.Delete(Items[ItemIndex].FCells, Index, 1);
    System.Insert(Cell, Items[ItemIndex].FCells, NewIndex);
  end;
  SelectSize(Selected);
end;

function TMeasurementSet.ValueProblem(const Key: string): string;
var
  Measurement: TMeasurement;
begin
  Measurement := Find(Key);
  if Measurement = nil then
    Result := Format(rsMeasurementNotInSet, [Key])
  else if Measurement.HasValue then
    Result := ''
  else
    Result := Format(rsMeasurementNoSizeValue, [Measurement.Key, SizeName]);
end;

function TMeasurementSet.ToJSON: TJSONObject;
var
  List, Values: TJSONArray;
  Item: TJSONObject;
  Index, SizeNumber: integer;
begin
  Result := TJSONObject.Create;
  try
    Result.Add('format', MeasurementFormat);
    Result.Add('version', MeasurementVersion);
    Result.Add('units', 'mm');
    Result.Add('name', Name);
    Result.Add('notes', Notes);
    if FSizes <> nil then
    begin
      List := TJSONArray.Create;
      Result.Add('sizes', List);
      for SizeNumber := 0 to High(FSizes) do
        List.Add(FSizes[SizeNumber]);
    end;
    List := TJSONArray.Create;
    Result.Add('measurements', List);
    for Index := 0 to Count - 1 do
    begin
      Item := TJSONObject.Create;
      List.Add(Item);
      Item.Add('key', Items[Index].Key);
      if FSizes = nil then
        Item.Add('value', JSONFloat(Items[Index].Value))
      else
      begin
        Values := TJSONArray.Create;
        Item.Add('values', Values);
        for SizeNumber := 0 to High(FSizes) do
          if Items[Index].HasValueFor(SizeNumber) then
            Values.Add(JSONFloat(Items[Index].ValueFor(SizeNumber)))
          else
            Values.Add(TJSONNull.Create);
      end;
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

function TMeasurementSet.LoadSizes(Obj: TJSONObject; out ErrorMessage: string): boolean;
var
  List: TJSONData;
  Index: integer;
begin
  ErrorMessage := '';
  List := Obj.Find('sizes');
  if List = nil then
    Exit(True);
  if List.JSONType <> jtArray then
  begin
    ErrorMessage := rsMeasurementBadSizes;
    Exit(False);
  end;
  for Index := 0 to List.Count - 1 do
  begin
    if List.Items[Index].JSONType <> jtString then
    begin
      ErrorMessage := rsMeasurementBadSizes;
      Exit(False);
    end;
    if not CheckSize(List.Items[Index].AsString, -1, ErrorMessage) then
      Exit(False);
    AddSize(List.Items[Index].AsString);
  end;
  Result := True;
end;

function TMeasurementSet.LoadValues(Item: TJSONObject; Measurement: TMeasurement; out ErrorMessage: string): boolean;
var
  List: TJSONData;
  Value: double;
  Index: integer;
begin
  ErrorMessage := '';
  if FSizes = nil then
  begin
    Result := GetJSONNumber(Item, 'value', Value);
    if Result then
      Measurement.Value := Value
    else
      ErrorMessage := Format(rsMeasurementBadValue, [Measurement.Key]);
    Exit;
  end;
  List := Item.Find('values');
  if (List = nil) or (List.JSONType <> jtArray) or (List.Count <> SizeCount) then
  begin
    ErrorMessage := Format(rsMeasurementBadValues, [Measurement.Key, SizeCount]);
    Exit(False);
  end;
  for Index := 0 to SizeCount - 1 do
    case List.Items[Index].JSONType of
      jtNumber: Measurement.SetValueFor(Index, List.Items[Index].AsFloat);
      jtNull: Measurement.ClearValueFor(Index);
      else
      begin
        ErrorMessage := Format(rsMeasurementBadValue, [Measurement.Key]);
        Exit(False);
      end;
    end;
  Result := True;
end;

function TMeasurementSet.LoadFromText(const Text: string; out ErrorMessage: string): boolean;
var
  Obj, Item: TJSONObject;
  List: TJSONData;
  TextValue, Key, Desc: string;
  Version, Index: integer;
  KeyError, ValueError: string;

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
    if not LoadSizes(Obj, ValueError) then
      Exit(Fail(ValueError));
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
      Desc := '';
      GetJSONString(Item, 'description', Desc);
      if not LoadValues(Item, Add(Key, 0, Desc), ValueError) then
        Exit(Fail(ValueError));
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
  out Change: TMeasurementChange; out ErrorMessage: string; const Size: string): boolean;
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
    if (MeasurementSet.SizeCount > 0) and (Size = '') then
    begin
      ErrorMessage := rsMeasurementNeedsSize;
      Exit;
    end;
    if (Size <> '') and not MeasurementSet.SelectSize(Size) then
    begin
      ErrorMessage := Format(rsMeasurementUnknownSize, [Size]);
      Exit;
    end;
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

function FormatMeasure(Millimetres: double; AUnit: TMeasureUnit): string;
var
  Settings: TFormatSettings;
begin
  Settings := DefaultFormatSettings;
  Settings.DecimalSeparator := '.';
  Result := FormatFloat(MeasureFormats[AUnit], Millimetres / MillimetresPerUnit[AUnit], Settings);
end;

function ParseMeasure(const Text: string; AUnit: TMeasureUnit; out Millimetres: double): boolean;
var
  Settings: TFormatSettings;
  Value: double;
begin
  Millimetres := 0;
  Settings := DefaultFormatSettings;
  Settings.DecimalSeparator := '.';
  Result := TryStrToFloat(StringReplace(Trim(Text), ',', '.', []), Value, Settings) and (Abs(Value) < MaxMeasure);
  if Result then
    Millimetres := Value * MillimetresPerUnit[AUnit];
end;

// All a side says about a key, to see whether it changed; '' when it has none
function KeyFingerprint(MeasurementSet: TMeasurementSet; const Key: string): string;
var
  Measurement: TMeasurement;
  Lines: TStringList;
  Index: integer;
begin
  Result := '';
  Measurement := MeasurementSet.Find(Key);
  if Measurement = nil then
    Exit;
  Lines := TStringList.Create;
  try
    for Index := 0 to High(Measurement.FCells) do
      if Measurement.HasValueFor(Index) then
        if MeasurementSet.SizeCount = 0 then
          Lines.Add('=' + FormatJSONFloat(Measurement.ValueFor(Index)))
        else
          Lines.Add(LowerCase(MeasurementSet.Sizes[Index]) + '=' + FormatJSONFloat(Measurement.ValueFor(Index)));
    Lines.Sort;
    Result := Measurement.Key + #10 + Measurement.Description + #10 + Lines.Text;
  finally
    FreeAndNil(Lines);
  end;
end;

// Adds the key to Merged, its values going by size name
procedure CopyMeasurement(Source: TMeasurementSet; const Key: string; Merged: TMeasurementSet);
var
  From, Into: TMeasurement;
  Index, Target: integer;
begin
  From := Source.Find(Key);
  Into := Merged.Add(From.Key, 0, From.Description);
  for Index := 0 to Merged.SizeCount - 1 do
    Into.ClearValueFor(Index);
  for Index := 0 to High(From.FCells) do
    if From.HasValueFor(Index) then
    begin
      Target := 0;
      if Source.SizeCount > 0 then
        Target := Merged.IndexOfSize(Source.Sizes[Index]);
      if Target >= 0 then
        Into.SetValueFor(Target, From.ValueFor(Index));
    end;
end;

procedure MergeSizes(Base, Mine, Theirs, Merged: TMeasurementSet);
var
  Index: integer;
begin
  // Sizes they kept, unless deleted here
  for Index := 0 to Theirs.SizeCount - 1 do
    if (Mine.IndexOfSize(Theirs.Sizes[Index]) >= 0) or (Base.IndexOfSize(Theirs.Sizes[Index]) < 0) then
      Merged.AddSize(Theirs.Sizes[Index]);
  for Index := 0 to Mine.SizeCount - 1 do
    if (Base.IndexOfSize(Mine.Sizes[Index]) < 0) and (Merged.IndexOfSize(Mine.Sizes[Index]) < 0) then
      Merged.AddSize(Mine.Sizes[Index]);
end;

procedure MergeMeasurementSets(Base, Mine, Theirs: TMeasurementSet; const TakeTheirs: TStringArray; Merged: TMeasurementSet;
  out Conflicts: TStringArray);

  function Listed(const Key: string): boolean;
  var
    Taken: string;
  begin
    for Taken in TakeTheirs do
      if SameName(Taken, Key) then
        Exit(True);
    Result := False;
  end;

  procedure MergeKey(const Key: string);
  var
    OnBase, OnMine, OnTheirs: string;
    FromTheirs: boolean;
  begin
    OnBase := KeyFingerprint(Base, Key);
    OnMine := KeyFingerprint(Mine, Key);
    OnTheirs := KeyFingerprint(Theirs, Key);
    FromTheirs := OnMine = OnBase;
    if (OnMine <> OnBase) and (OnTheirs <> OnBase) and (OnMine <> OnTheirs) then
    begin
      FromTheirs := Listed(Key);
      if not FromTheirs then
      begin
        SetLength(Conflicts, Length(Conflicts) + 1);
        Conflicts[High(Conflicts)] := Key;
      end;
    end;
    if FromTheirs and (Theirs.Find(Key) <> nil) then
      CopyMeasurement(Theirs, Key, Merged)
    else if not FromTheirs and (Mine.Find(Key) <> nil) then
      CopyMeasurement(Mine, Key, Merged);
  end;

var
  Index: integer;
begin
  Conflicts := nil;
  Merged.Clear;
  MergeSizes(Base, Mine, Theirs, Merged);
  if Mine.Name = Base.Name then
    Merged.Name := Theirs.Name
  else
    Merged.Name := Mine.Name;
  if Mine.Notes = Base.Notes then
    Merged.Notes := Theirs.Notes
  else
    Merged.Notes := Mine.Notes;
  for Index := 0 to Theirs.Count - 1 do
    MergeKey(Theirs[Index].Key);
  // Keys they do not have: added here, or deleted there
  for Index := 0 to Mine.Count - 1 do
    if Theirs.Find(Mine[Index].Key) = nil then
      MergeKey(Mine[Index].Key);
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
