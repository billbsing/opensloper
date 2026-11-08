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

// The edits the side panel's editable lists make. Variables change through
// the document, so each is one undo step. Measurements belong to their file,
// so the Measurements tab holds its edits as pending changes until Save
// writes them all at once. Kept free of the LCL so the tests can make them.
unit Sloper.UI.PanelEdits;

{$mode ObjFPC}{$H+}

interface

uses
  SysUtils, StrUtils, Sloper.Core.Measurements, Sloper.Document.PatternDocument;

type
  // The Variables tab's columns, in order
  TVariableColumn = (vcName, vcFormula, vcValue, vcDescription);
  // The Measurements tab's columns, in order
  TMeasurementColumn = (mcKey, mcValue, mcDescription);
  // The fields of the Materials dialog
  TMaterialField = (mfName, mfColor, mfFill, mfAllowance);

  // A measurement edited in the panel and not yet saved
  TPendingMeasurement = record
    Key: string;
    Value: double;
    // False until a value is given to a key the set does not have
    HasValue: boolean;
    Description: string;
    // Made by Add, so its key can still be changed
    IsNew: boolean;
  end;

  // The Measurements tab's unsaved edits, by key, in the order first made
  TPendingMeasurements = class
  private
    FItems: array of TPendingMeasurement;
    function GetItem(Index: integer): TPendingMeasurement;
    function Start(MeasurementSet: TMeasurementSet; const Key: string): integer;
  public
    function Count: integer;
    // The edit for Key, ignoring case, or -1
    function IndexOf(const Key: string): integer;
    procedure Clear;
    // A new key, the first of measurement, measurement2 and so on that neither
    // the set nor another edit has
    function AddNew(MeasurementSet: TMeasurementSet): string;
    // Commits a cell of Key's row. The first edit of a row starts from what
    // the set has. NewKey is the row's key afterwards, which changes only when
    // a new row's key is edited. False refuses Text with the reason.
    function CommitCell(MeasurementSet: TMeasurementSet; const Key: string; Column: TMeasurementColumn; const Text: string;
      out NewKey, Reason: string): boolean;
    // Every edit, ready for TPatternDocument.ChangeMeasurements; False when
    // one has no value yet
    function Edits(out AEdits: TMeasurementEditArray; out Reason: string): boolean;
    property Items[Index: integer]: TPendingMeasurement read GetItem; default;
  end;

// A value as typed in the panel: a plain number with a point for decimals
function ParseMeasurementValue(const Text: string; out Value: double): boolean;
// What Save did, for the status bar
function MeasurementsSavedText(const Changes: TMeasurementChangeArray; const FileName: string): string;

// Sets a field of the pattern's material at Index as one undo step: a name,
// a #RRGGBB colour, a fill as in pattern files (tint or hatch), or an
// allowance in the pattern's unit, empty for none. Text the field already
// holds makes no step. False refuses it, with Reason saying why.
function CommitMaterialField(Document: TPatternDocument; Index: integer; Field: TMaterialField; const Text: string;
  out Reason: string): boolean;
// The field as CommitMaterialField takes it
function MaterialFieldText(Document: TPatternDocument; Index: integer; Field: TMaterialField): string;
// Adds a material as one undo step; its index, or -1
function AddMaterialStep(Document: TPatternDocument): integer;
// Deletes the material at Index as one undo step; False refuses, with Reason
function DeleteMaterialStep(Document: TPatternDocument; Index: integer; out Reason: string): boolean;

// Commits Text to the variable's cell as one undo step. False refuses it, with
// Reason saying why and ErrorPos (1-based, 0 for none) where in a formula.
function CommitVariableCell(Document: TPatternDocument; const Key: string; Column: TVariableColumn; const Text: string;
  out Reason: string; out ErrorPos: integer): boolean;

resourcestring
  rsPanelRenameVariable = 'Rename variable';
  rsPanelVariableFormula = 'Edit variable formula';
  rsPanelVariableDescription = 'Change variable description';
  rsPanelNotVariable = 'This variable no longer exists';
  rsPanelBadValue = 'The value must be a number, such as 820 or 41.5';
  rsPanelNoValue = '@%s has no value yet';
  rsPanelKeyFixed = 'Only a new measurement''s key can be changed here';
  rsPanelNewKey = 'measurement';
  // Count, file name
  rsPanelMeasurementsSaved = '%d measurements saved to %s';
  rsPanelNoMaterial = 'This material no longer exists';
  rsPanelBadAllowance = 'The allowance must be a number, such as 10 or 3.5, or empty for none';
  rsPanelBadColor = 'The colour must be written #RRGGBB';
  rsPanelBadFill = 'The fill must be tint or hatch';
  rsPanelAddMaterial = 'Add material';
  rsPanelDeleteMaterial = 'Delete material';
  rsPanelRenameMaterial = 'Rename material';
  rsPanelRecolorMaterial = 'Change material colour';
  rsPanelMaterialFill = 'Change material fill';
  rsPanelMaterialAllowance = 'Change material allowance';

implementation

uses
  Sloper.Core.Evaluator, Sloper.Core.Variables, Sloper.Core.Names, Sloper.Core.Materials, Sloper.Core.JSON, Sloper.UI.ObjectList;

const
  MaxMeasurementValue = 1e12;

function CommitVariableCell(Document: TPatternDocument; const Key: string; Column: TVariableColumn; const Text: string;
  out Reason: string; out ErrorPos: integer): boolean;
var
  Node: TEvalNode;
begin
  Reason := '';
  ErrorPos := 0;
  Result := False;
  Node := Document.Pattern.FindNode(Key);
  if not (Node is TVariable) then
  begin
    Reason := rsPanelNotVariable;
    Exit;
  end;
  case Column of
    vcName:
    begin
      Document.BeginChange(rsPanelRenameVariable);
      Result := Document.Pattern.Rename(Node, Trim(Text));
    end;
    vcFormula:
    begin
      Document.BeginChange(rsPanelVariableFormula);
      Result := Document.Pattern.SetFormula(Node, 'formula', Text);
    end;
    vcDescription:
    begin
      Document.BeginChange(rsPanelVariableDescription);
      TVariable(Node).Description := Text;
      Result := True;
    end;
    else
      Exit;
  end;
  if not Result then
  begin
    Reason := Document.Pattern.LastError;
    ErrorPos := Document.Pattern.LastErrorPos;
  end;
  Document.Commit(Result);
end;

function MaterialFieldText(Document: TPatternDocument; Index: integer; Field: TMaterialField): string;
var
  Material: TPatternMaterial;
begin
  Result := '';
  if (Index < 0) or (Index >= Document.Pattern.MaterialCount) then
    Exit;
  Material := Document.Pattern.Materials[Index];
  case Field of
    mfName:
      Result := Material.Name;
    mfColor:
      Result := Material.Color;
    mfFill:
      Result := MaterialFillNames[Ord(Material.Fill)];
    mfAllowance:
      if Material.HasAllowance then
        Result := FormatJSONFloat(Material.Allowance);
  end;
end;

function CommitMaterialField(Document: TPatternDocument; Index: integer; Field: TMaterialField; const Text: string;
  out Reason: string): boolean;
const
  Descriptions: array[TMaterialField] of string = (rsPanelRenameMaterial, rsPanelRecolorMaterial, rsPanelMaterialFill,
    rsPanelMaterialAllowance);
var
  Material: TPatternMaterial;
  Entry: string;
  Value: double;
  Fill: TMaterialFill;
  FillIndex: integer;
begin
  Reason := '';
  if (Index < 0) or (Index >= Document.Pattern.MaterialCount) then
  begin
    Reason := rsPanelNoMaterial;
    Exit(False);
  end;
  Entry := Trim(Text);
  if Entry = MaterialFieldText(Document, Index, Field) then
    Exit(True);
  Value := 0;
  Fill := ffTint;
  // Checked before the change, so a refusal leaves no trace
  case Field of
    mfColor:
      if not IsMaterialColor(Entry) then
        Reason := rsPanelBadColor;
    mfFill:
    begin
      FillIndex := IndexText(Entry, MaterialFillNames);
      if FillIndex < 0 then
        Reason := rsPanelBadFill
      else
        Fill := TMaterialFill(FillIndex);
    end;
    mfAllowance:
      if (Entry <> '') and not ParseMeasurementValue(Entry, Value) then
        Reason := rsPanelBadAllowance;
  end;
  if Reason <> '' then
    Exit(False);
  Document.BeginChange(Descriptions[Field]);
  Material := Document.Pattern.Materials[Index];
  case Field of
    mfName:
      Result := Document.Pattern.RenameMaterial(Material, Entry);
    mfColor:
      Result := Document.Pattern.SetMaterialColor(Material, Entry);
    mfFill:
    begin
      Document.Pattern.SetMaterialFill(Material, Fill);
      Result := True;
    end;
    mfAllowance:
      Result := Document.Pattern.SetMaterialAllowance(Material, Entry <> '', Value);
    else
      Result := False;
  end;
  if not Result then
    Reason := Document.Pattern.LastError;
  Document.Commit(Result);
end;

function AddMaterialStep(Document: TPatternDocument): integer;
var
  Added: boolean;
begin
  Document.BeginChange(rsPanelAddMaterial);
  Added := Assigned(Document.Pattern.AddMaterial);
  Document.Commit(Added);
  Result := -1;
  if Added then
    Result := Document.Pattern.MaterialCount - 1;
end;

function DeleteMaterialStep(Document: TPatternDocument; Index: integer; out Reason: string): boolean;
begin
  Reason := '';
  if (Index < 0) or (Index >= Document.Pattern.MaterialCount) then
  begin
    Reason := rsPanelNoMaterial;
    Exit(False);
  end;
  Document.BeginChange(rsPanelDeleteMaterial);
  Result := Document.Pattern.DeleteMaterial(Document.Pattern.Materials[Index]);
  if not Result then
    Reason := Document.Pattern.LastError;
  Document.Commit(Result);
end;

function ParseMeasurementValue(const Text: string; out Value: double): boolean;
var
  Settings: TFormatSettings;
begin
  Settings := DefaultFormatSettings;
  Settings.DecimalSeparator := '.';
  Settings.ThousandSeparator := #0;
  Result := TryStrToFloat(Trim(Text), Value, Settings) and (Abs(Value) < MaxMeasurementValue);
end;

function MeasurementsSavedText(const Changes: TMeasurementChangeArray; const FileName: string): string;
begin
  if Length(Changes) = 1 then
    Result := MeasurementChangeText(Changes[0], FileName)
  else
    Result := Format(rsPanelMeasurementsSaved, [Length(Changes), ExtractFileName(FileName)]);
end;

function TPendingMeasurements.GetItem(Index: integer): TPendingMeasurement;
begin
  Result := FItems[Index];
end;

function TPendingMeasurements.Count: integer;
begin
  Result := Length(FItems);
end;

function TPendingMeasurements.IndexOf(const Key: string): integer;
var
  Index: integer;
begin
  for Index := 0 to High(FItems) do
    if SameName(FItems[Index].Key, Key) then
      Exit(Index);
  Result := -1;
end;

procedure TPendingMeasurements.Clear;
begin
  FItems := nil;
end;

// The edit for Key, made from the set's measurement when there is none yet
function TPendingMeasurements.Start(MeasurementSet: TMeasurementSet; const Key: string): integer;
var
  Measurement: TMeasurement;
begin
  Result := IndexOf(Key);
  if Result >= 0 then
    Exit;
  Result := Length(FItems);
  SetLength(FItems, Result + 1);
  FItems[Result] := Default(TPendingMeasurement);
  FItems[Result].Key := Key;
  Measurement := nil;
  if Assigned(MeasurementSet) then
    Measurement := MeasurementSet.Find(Key);
  if Assigned(Measurement) then
  begin
    FItems[Result].Key := Measurement.Key;
    FItems[Result].HasValue := Measurement.HasValue;
    if Measurement.HasValue then
      FItems[Result].Value := Measurement.Value;
    FItems[Result].Description := Measurement.Description;
  end;
end;

function TPendingMeasurements.AddNew(MeasurementSet: TMeasurementSet): string;
var
  Number, Index: integer;

  function Taken(const Key: string): boolean;
  begin
    Result := (IndexOf(Key) >= 0) or (Assigned(MeasurementSet) and Assigned(MeasurementSet.Find(Key)));
  end;

begin
  Result := rsPanelNewKey;
  Number := 1;
  while Taken(Result) do
  begin
    Inc(Number);
    Result := rsPanelNewKey + IntToStr(Number);
  end;
  Index := Start(MeasurementSet, Result);
  FItems[Index].IsNew := True;
end;

function TPendingMeasurements.CommitCell(MeasurementSet: TMeasurementSet; const Key: string; Column: TMeasurementColumn;
  const Text: string; out NewKey, Reason: string): boolean;
var
  Index, Other: integer;
  Value: double;
  NewName: string;
begin
  Result := False;
  NewKey := Key;
  Reason := '';
  case Column of
    mcKey:
    begin
      Index := IndexOf(Key);
      if (Index < 0) or not FItems[Index].IsNew then
      begin
        Reason := rsPanelKeyFixed;
        Exit;
      end;
      NewName := Trim(Text);
      if not CheckName(NewName, Reason) then
        Exit;
      Other := IndexOf(NewName);
      if ((Other >= 0) and (Other <> Index)) or (Assigned(MeasurementSet) and Assigned(MeasurementSet.Find(NewName))) then
      begin
        Reason := Format(rsNameTaken, [NewName]);
        Exit;
      end;
      FItems[Index].Key := NewName;
      NewKey := NewName;
    end;
    mcValue:
    begin
      if not ParseMeasurementValue(Text, Value) then
      begin
        Reason := rsPanelBadValue;
        Exit;
      end;
      Index := Start(MeasurementSet, Key);
      FItems[Index].Value := Value;
      FItems[Index].HasValue := True;
    end;
    mcDescription:
    begin
      Index := Start(MeasurementSet, Key);
      FItems[Index].Description := Text;
    end;
  end;
  Result := True;
end;

function TPendingMeasurements.Edits(out AEdits: TMeasurementEditArray; out Reason: string): boolean;
var
  Index: integer;
begin
  AEdits := nil;
  Reason := '';
  SetLength(AEdits, Length(FItems));
  for Index := 0 to High(FItems) do
  begin
    if not FItems[Index].HasValue then
    begin
      AEdits := nil;
      Reason := Format(rsPanelNoValue, [FItems[Index].Key]);
      Exit(False);
    end;
    AEdits[Index].Key := FItems[Index].Key;
    AEdits[Index].Value := FItems[Index].Value;
    AEdits[Index].Description := FItems[Index].Description;
  end;
  Result := True;
end;

end.
