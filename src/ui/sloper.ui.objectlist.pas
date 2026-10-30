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

// What the objects and variables panels list: a row of text for each, narrowed
// by a filter and a search, and how clicks change the selection. Also the captions
// the panels share for object types and formula fields. Kept free of the LCL
// so it can be unit-tested.
unit Sloper.UI.ObjectList;

{$mode ObjFPC}{$H+}

interface

uses
  SysUtils, Sloper.Core.EvalTypes, Sloper.Core.Evaluator, Sloper.Core.Measurements, Sloper.Core.Variables, Sloper.Core.Draft,
  Sloper.Core.Pattern;

type
  // ofProblems: anything not valid
  TObjectFilter = (ofAll, ofPoints, ofEdges, ofProblems);

  TObjectRow = record
    Key: string;
    Name: string;
    Operation: string;
    Value: string;
    Formulas: string;
    State: TEvalState;
    StateText: string;
  end;
  TObjectRowArray = array of TObjectRow;

  TVariableRow = record
    Key: string;
    Name: string;
    Formula: string;
    Value: string;
    Description: string;
    State: TEvalState;
    StateText: string;
  end;
  TVariableRowArray = array of TVariableRow;

  TMeasurementRow = record
    Key: string;
    Value: string;
    Description: string;
    // The pattern uses this key, but the set does not have it
    Missing: boolean;
  end;
  TMeasurementRowArray = array of TMeasurementRow;

// Caption for a formula field, such as "Start angle" for angle1
function FieldCaption(const FieldName: string): string;
// What kind of object this is, such as "Offset point"
function TypeCaption(Node: TEvalNode): string;
function StateCaption(State: TEvalState): string;
// What the object computes to: a position or a length. Empty before it is computed.
function ResultText(DraftObject: TDraftObject): string;
function ObjectRow(Pattern: TPattern; DraftObject: TDraftObject): TObjectRow;
// The objects passing Filter whose name, operation or formulas contain Search,
// ignoring case, in pattern order
function ObjectRows(Pattern: TPattern; Filter: TObjectFilter; const Search: string): TObjectRowArray;
function VariableRow(Pattern: TPattern; Variable: TVariable): TVariableRow;
// The variables whose name, formula or description contain Search, ignoring case
function VariableRows(Pattern: TPattern; const Search: string): TVariableRowArray;
// The set's measurements whose key or description contain Search, ignoring
// case, then any the pattern uses that the set lacks. Set may be nil.
function MeasurementRows(Pattern: TPattern; MeasurementSet: TMeasurementSet; const Search: string): TMeasurementRowArray;
// What a small edit did, for the status bar
function MeasurementChangeText(const Change: TMeasurementChange; const FileName: string): string;
// The selection after clicking Clicked. Toggle adds or removes it; Extend
// selects from Anchor to it in Visible, the keys in list order, or just it
// when Anchor is not listed.
function SelectionAfterClick(const Visible, Selected: TStringArray; const Anchor, Clicked: string;
  Toggle, Extend: boolean): TStringArray;

resourcestring
  rsObjectPosition = '%s, %s mm';
  rsObjectLength = '%s mm';
  rsObjectFormula = '%s = %s';
  rsObjectFormulaGap = '; ';
  rsMeasurementChanged = '@%s %s → %s mm saved to %s';
  rsMeasurementAdded = '@%s %s mm added to %s';
  rsStateValid = 'Valid';
  rsStateError = 'Error';
  rsStateInvalid = 'Invalid';
  rsStateBlocked = 'Blocked';
  rsFieldX = 'X';
  rsFieldY = 'Y';
  rsFieldLength = 'Length';
  rsFieldAngle = 'Angle';
  rsFieldDX = 'Across';
  rsFieldDY = 'Up';
  rsFieldValue = 'Distance or ratio';
  rsFieldRadius = 'Radius';
  rsFieldAngle1 = 'Start angle';
  rsFieldLength1 = 'Start handle';
  rsFieldAngle2 = 'End angle';
  rsFieldLength2 = 'End handle';
  rsFieldFormula = 'Formula';
  rsFieldNodeAngle = 'Point %s angle';
  rsFieldNodeIn = 'Point %s handle in';
  rsFieldNodeOut = 'Point %s handle out';
  rsTypeFree = 'Free point';
  rsTypeOffset = 'Offset point';
  rsTypeAlong = 'Point along an edge';
  rsTypeIntersect = 'Crossing of two edges';
  rsTypeCircle = 'Compass step onto an edge';
  rsTypeProject = 'Point projected onto an edge';
  rsTypeLine = 'Line';
  rsTypeCurve = 'Curve';
  rsTypePath = 'Curve path';
  rsTypePart = 'Part of a split edge';
  rsTypeVariable = 'Variable';

implementation

uses
  Sloper.Core.Drag, Sloper.Core.JSON;

const
  VariableDecimals = 4;

function FieldCaption(const FieldName: string): string;
var
  Dot: integer;
  NodeNumber, Part: string;
begin
  Dot := Pos('.', FieldName);
  if (Dot > 0) and (Copy(FieldName, 1, 4) = 'node') then
  begin
    NodeNumber := Copy(FieldName, 5, Dot - 5);
    Part := Copy(FieldName, Dot + 1, MaxInt);
    if Part = 'angle' then
      Exit(Format(rsFieldNodeAngle, [NodeNumber]));
    if Part = 'lengthIn' then
      Exit(Format(rsFieldNodeIn, [NodeNumber]));
    Exit(Format(rsFieldNodeOut, [NodeNumber]));
  end;
  case FieldName of
    'x': Result := rsFieldX;
    'y': Result := rsFieldY;
    'length': Result := rsFieldLength;
    'angle': Result := rsFieldAngle;
    'dx': Result := rsFieldDX;
    'dy': Result := rsFieldDY;
    'value': Result := rsFieldValue;
    'radius': Result := rsFieldRadius;
    'angle1': Result := rsFieldAngle1;
    'length1': Result := rsFieldLength1;
    'angle2': Result := rsFieldAngle2;
    'length2': Result := rsFieldLength2;
    'formula': Result := rsFieldFormula;
    else
      Result := FieldName;
  end;
end;

function TypeCaption(Node: TEvalNode): string;
begin
  if Node is TFreePoint then
    Result := rsTypeFree
  else if Node is TOffsetPoint then
    Result := rsTypeOffset
  else if Node is TAlongEdgePoint then
    Result := rsTypeAlong
  else if Node is TIntersectPoint then
    Result := rsTypeIntersect
  else if Node is TCircleEdgePoint then
    Result := rsTypeCircle
  else if Node is TProjectPoint then
    Result := rsTypeProject
  else if Node is TLineObject then
    Result := rsTypeLine
  else if Node is TCurveObject then
    Result := rsTypeCurve
  else if Node is TCurvePathObject then
    Result := rsTypePath
  else if Node is TSplitPart then
    Result := rsTypePart
  else if Node is TVariable then
    Result := rsTypeVariable
  else
    Result := '';
end;

function StateCaption(State: TEvalState): string;
begin
  case State of
    esValid: Result := rsStateValid;
    esError: Result := rsStateError;
    esInvalid: Result := rsStateInvalid;
    else
      Result := rsStateBlocked;
  end;
end;

function ResultText(DraftObject: TDraftObject): string;
begin
  Result := '';
  if not DraftObject.HasResult then
    Exit;
  if DraftObject is TPointObject then
    Result := Format(rsObjectPosition, [RoundedText(TPointObject(DraftObject).Position.X, 1),
      RoundedText(TPointObject(DraftObject).Position.Y, 1)])
  else if DraftObject is TEdgeObject then
    Result := Format(rsObjectLength, [RoundedText(TEdgeObject(DraftObject).Length, 1)]);
end;

function FormulasText(Pattern: TPattern; DraftObject: TDraftObject): string;
var
  Index: integer;
  FieldName, Item: string;
begin
  Result := '';
  for Index := 0 to DraftObject.FieldCount - 1 do
  begin
    FieldName := DraftObject.Fields[Index].Name;
    Item := Format(rsObjectFormula, [FieldCaption(FieldName), Pattern.FormulaText(DraftObject, FieldName)]);
    if Result = '' then
      Result := Item
    else
      Result := Result + rsObjectFormulaGap + Item;
  end;
end;

function ObjectRow(Pattern: TPattern; DraftObject: TDraftObject): TObjectRow;
begin
  Result.Key := DraftObject.Key;
  Result.Name := DraftObject.DisplayName;
  Result.Operation := TypeCaption(DraftObject);
  Result.Value := ResultText(DraftObject);
  Result.Formulas := FormulasText(Pattern, DraftObject);
  Result.State := DraftObject.State;
  Result.StateText := StateCaption(DraftObject.State);
end;

function PassesFilter(DraftObject: TDraftObject; Filter: TObjectFilter): boolean;
begin
  case Filter of
    ofPoints: Result := DraftObject is TPointObject;
    ofEdges: Result := DraftObject is TEdgeObject;
    ofProblems: Result := DraftObject.State <> esValid;
    else
      Result := True;
  end;
end;

function Matches(const Row: TObjectRow; const LowerSearch: string): boolean;
begin
  Result := (LowerSearch = '') or (Pos(LowerSearch, LowerCase(Row.Name)) > 0) or (Pos(LowerSearch, LowerCase(Row.Operation)) > 0) or
    (Pos(LowerSearch, LowerCase(Row.Formulas)) > 0);
end;

function ObjectRows(Pattern: TPattern; Filter: TObjectFilter; const Search: string): TObjectRowArray;
var
  Index, Count: integer;
  LowerSearch: string;
  Row: TObjectRow;
begin
  Result := nil;
  SetLength(Result, Pattern.ObjectCount);
  LowerSearch := LowerCase(Trim(Search));
  Count := 0;
  for Index := 0 to Pattern.ObjectCount - 1 do
    if PassesFilter(Pattern.Objects[Index], Filter) then
    begin
      Row := ObjectRow(Pattern, Pattern.Objects[Index]);
      if Matches(Row, LowerSearch) then
      begin
        Result[Count] := Row;
        Inc(Count);
      end;
    end;
  SetLength(Result, Count);
end;

function VariableRow(Pattern: TPattern; Variable: TVariable): TVariableRow;
begin
  Result.Key := Variable.Key;
  Result.Name := Variable.Name;
  Result.Formula := Pattern.FormulaText(Variable, 'formula');
  Result.Value := '';
  if Variable.State = esValid then
    Result.Value := RoundedText(Variable.Value, VariableDecimals);
  Result.Description := Variable.Description;
  Result.State := Variable.State;
  Result.StateText := StateCaption(Variable.State);
end;

function VariableRows(Pattern: TPattern; const Search: string): TVariableRowArray;
var
  Index, Count: integer;
  LowerSearch: string;
  Row: TVariableRow;
begin
  Result := nil;
  SetLength(Result, Pattern.VariableCount);
  LowerSearch := LowerCase(Trim(Search));
  Count := 0;
  for Index := 0 to Pattern.VariableCount - 1 do
  begin
    Row := VariableRow(Pattern, Pattern.Variables[Index]);
    if (LowerSearch = '') or (Pos(LowerSearch, LowerCase(Row.Name)) > 0) or (Pos(LowerSearch, LowerCase(Row.Formula)) > 0) or
      (Pos(LowerSearch, LowerCase(Row.Description)) > 0) then
    begin
      Result[Count] := Row;
      Inc(Count);
    end;
  end;
  SetLength(Result, Count);
end;

function MeasurementRows(Pattern: TPattern; MeasurementSet: TMeasurementSet; const Search: string): TMeasurementRowArray;
var
  LowerSearch: string;
  Index, Count: integer;
  Node: TEvalNode;
  Key: string;

  procedure Add(const AKey, Value, Description: string; Missing: boolean);
  begin
    if (LowerSearch <> '') and (Pos(LowerSearch, LowerCase(AKey)) = 0) and (Pos(LowerSearch, LowerCase(Description)) = 0) then
      Exit;
    SetLength(Result, Count + 1);
    Result[Count].Key := AKey;
    Result[Count].Value := Value;
    Result[Count].Description := Description;
    Result[Count].Missing := Missing;
    Inc(Count);
  end;

begin
  Result := nil;
  Count := 0;
  LowerSearch := LowerCase(Trim(Search));
  if MeasurementSet <> nil then
    for Index := 0 to MeasurementSet.Count - 1 do
      Add(MeasurementSet[Index].Key, FormatJSONFloat(MeasurementSet[Index].Value), MeasurementSet[Index].Description, False);
  for Node in Pattern.AllNodes do
    if Node is TMeasurementNode then
    begin
      Key := Copy(Node.Key, 2, MaxInt);
      if (MeasurementSet = nil) or (MeasurementSet.Find(Key) = nil) then
        Add(Key, '', '', True);
    end;
end;

function MeasurementChangeText(const Change: TMeasurementChange; const FileName: string): string;
begin
  if Change.Added then
    Result := Format(rsMeasurementAdded, [Change.Key, FormatJSONFloat(Change.Value), ExtractFileName(FileName)])
  else
    Result := Format(rsMeasurementChanged, [Change.Key, FormatJSONFloat(Change.OldValue), FormatJSONFloat(Change.Value),
      ExtractFileName(FileName)]);
end;

function KeyIndex(const Keys: TStringArray; const Key: string): integer;
begin
  for Result := 0 to High(Keys) do
    if Keys[Result] = Key then
      Exit;
  Result := -1;
end;

function SelectionAfterClick(const Visible, Selected: TStringArray; const Anchor, Clicked: string;
  Toggle, Extend: boolean): TStringArray;
var
  AnchorIndex, ClickedIndex, Found: integer;
begin
  AnchorIndex := KeyIndex(Visible, Anchor);
  ClickedIndex := KeyIndex(Visible, Clicked);
  if Extend and (AnchorIndex >= 0) and (ClickedIndex >= 0) then
  begin
    if AnchorIndex < ClickedIndex then
      Exit(Copy(Visible, AnchorIndex, ClickedIndex - AnchorIndex + 1));
    Exit(Copy(Visible, ClickedIndex, AnchorIndex - ClickedIndex + 1));
  end;
  if not Toggle then
    Exit([Clicked]);
  Result := Copy(Selected);
  Found := KeyIndex(Result, Clicked);
  if Found >= 0 then
    Delete(Result, Found, 1)
  else
    Insert(Clicked, Result, Length(Result));
end;

end.
