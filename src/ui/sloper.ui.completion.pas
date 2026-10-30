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

// Autocomplete for formula fields: what to offer at the caret, in the display
// form the user types. Kept free of the LCL so it can be unit-tested.
unit Sloper.UI.Completion;

{$mode ObjFPC}{$H+}

interface

uses
  Sloper.Core.Evaluator, Sloper.Core.Pattern;

type
  TCompletionItem = record
    // What the list shows and what the match is against
    Name: string;
    // Replaces the word at the caret
    Insert: string;
    // A value or kind, shown beside the name
    Detail: string;
  end;
  TCompletionItemArray = array of TCompletionItem;

  TCompletion = record
    // The text offsets, from 0, of the word being replaced
    From, Upto: integer;
    Items: TCompletionItemArray;
  end;

// What to offer at Caret, an offset from 0, in a formula for Node. A bare word
// offers objects, variables, measurements and functions; @, # and a dot after
// an object narrow that. An empty bare word offers nothing unless Explicit, the
// user having asked. Text the user has already finished offers nothing.
function FormulaCompletion(Pattern: TPattern; Node: TEvalNode; const Text: string; Caret: integer; Explicit: boolean): TCompletion;
// Text with the item in place of the word, and where the caret goes
function ApplyCompletion(const Text: string; const Completion: TCompletion; Index: integer; out Caret: integer): string;

resourcestring
  rsCompletionFunction = 'Function';
  rsCompletionMeasurement = '%s mm';

implementation

uses
  SysUtils, Sloper.Core.EvalTypes, Sloper.Core.Measurements, Sloper.Core.Names, Sloper.Core.Variables, Sloper.Core.Draft,
  Sloper.Core.Drag, Sloper.UI.ObjectList;

const
  PropertyNames: array[0..5] of string = ('x', 'y', 'length', 'angle', 'angle1', 'angle2');
  ValueDecimals = 2;

function IsWordChar(Character: char): boolean;
begin
  Result := Character in ['A'..'Z', 'a'..'z', '0'..'9', '_'];
end;

// Earlier is better: 0 starts with the word, 1 contains it, -1 does not match
function MatchRank(const Name, LowerWord: string): integer;
var
  Found: integer;
begin
  if LowerWord = '' then
    Exit(0);
  Found := Pos(LowerWord, LowerCase(Name));
  if Found = 1 then
    Result := 0
  else if Found > 1 then
    Result := 1
  else
    Result := -1;
end;

// Adds Item in order of rank, then name, so a short name comes before longer ones
procedure AddItem(var Items: TCompletionItemArray; var Ranks: array of integer; const Item: TCompletionItem; const LowerWord: string);
var
  Rank, Place, Index: integer;
begin
  Rank := MatchRank(Item.Name, LowerWord);
  if Rank < 0 then
    Exit;
  Place := Length(Items);
  while (Place > 0) and ((Ranks[Place - 1] > Rank) or ((Ranks[Place - 1] = Rank) and
      (CompareText(Items[Place - 1].Name, Item.Name) > 0))) do
    Dec(Place);
  SetLength(Items, Length(Items) + 1);
  for Index := High(Items) downto Place + 1 do
  begin
    Items[Index] := Items[Index - 1];
    Ranks[Index] := Ranks[Index - 1];
  end;
  Items[Place] := Item;
  Ranks[Place] := Rank;
end;

function MakeItem(const Name, Insert, Detail: string): TCompletionItem;
begin
  Result.Name := Name;
  Result.Insert := Insert;
  Result.Detail := Detail;
end;

function VariableDetail(Variable: TVariable): string;
begin
  if Variable.State = esValid then
    Result := RoundedText(Variable.Value, ValueDecimals)
  else
    Result := '';
end;

function FormulaCompletion(Pattern: TPattern; Node: TEvalNode; const Text: string; Caret: integer; Explicit: boolean): TCompletion;
var
  WordStart, Index, Capacity: integer;
  word, LowerWord, OwnerName: string;
  Before: char;
  Ranks: array of integer;
  Owner: TDraftObject;
  Variable: TVariable;
  DraftObject: TDraftObject;
  FunctionName, PropertyName, Detail: string;
  AllowObjects: boolean;

  procedure Add(const Name, Insert, ItemDetail: string);
  begin
    AddItem(Result.Items, Ranks, MakeItem(Name, Insert, ItemDetail), LowerWord);
  end;

  procedure AddMeasurements(const Prefix: string);
  var
    MeasurementIndex: integer;
  begin
    if Pattern.Measurements = nil then
      Exit;
    for MeasurementIndex := 0 to Pattern.Measurements.Count - 1 do
      Add(Pattern.Measurements[MeasurementIndex].Key, Prefix + Pattern.Measurements[MeasurementIndex].Key,
        Format(rsCompletionMeasurement, [RoundedText(Pattern.Measurements[MeasurementIndex].Value, ValueDecimals)]));
  end;

  procedure AddVariables(const Prefix: string);
  var
    VariableIndex: integer;
  begin
    for VariableIndex := 0 to Pattern.VariableCount - 1 do
    begin
      Variable := Pattern.Variables[VariableIndex];
      if Variable <> Node then
        Add(Variable.Name, Prefix + Variable.Name, VariableDetail(Variable));
    end;
  end;

begin
  Result := Default(TCompletion);
  if (Caret < 0) or (Caret > Length(Text)) then
    Exit;
  WordStart := Caret;
  while (WordStart > 0) and IsWordChar(Text[WordStart]) do
    Dec(WordStart);
  word := Copy(Text, WordStart + 1, Caret - WordStart);
  LowerWord := LowerCase(word);
  Result.From := WordStart;
  Result.Upto := Caret;
  // The rest of a word the caret is inside goes too
  while (Result.Upto < Length(Text)) and IsWordChar(Text[Result.Upto + 1]) do
    Inc(Result.Upto);
  Before := #0;
  if WordStart > 0 then
    Before := Text[WordStart];
  // A number such as 12 or 1.5 is not a name
  if (word <> '') and (word[1] in ['0'..'9']) and (Before <> '.') then
    Exit;

  AllowObjects := not (Node is TVariable);
  Capacity := Pattern.ObjectCount + Pattern.VariableCount + Length(FormulaFunctionNames) + Length(PropertyNames) + 1;
  if Pattern.Measurements <> nil then
    Capacity := Capacity + Pattern.Measurements.Count;
  Ranks := nil;
  SetLength(Ranks, Capacity);

  case Before of
    '@':
      AddMeasurements('');
    '#':
      AddVariables('');
    '.':
    begin
      Index := WordStart - 1;
      while (Index > 0) and IsWordChar(Text[Index]) do
        Dec(Index);
      OwnerName := Copy(Text, Index + 1, WordStart - 1 - Index);
      Owner := nil;
      if AllowObjects and (OwnerName <> '') and not (OwnerName[1] in ['0'..'9']) then
        Owner := Pattern.FindObject(OwnerName);
      if (Owner <> nil) and (Owner <> Node) then
        for PropertyName in PropertyNames do
          if Owner.HasProperty(PropertyName) then
          begin
            Detail := '';
            if Owner.HasResult and (Owner.State = esValid) then
              Detail := RoundedText(Owner.PropertyValue(PropertyName), ValueDecimals);
            Add(PropertyName, PropertyName, Detail);
          end;
    end;
    else
      if (word <> '') or Explicit then
      begin
        if AllowObjects then
          for Index := 0 to Pattern.ObjectCount - 1 do
          begin
            DraftObject := Pattern.Objects[Index];
            if DraftObject <> Node then
              Add(DraftObject.DisplayName, DraftObject.DisplayName + '.', TypeCaption(DraftObject));
          end;
        AddVariables('#');
        AddMeasurements('@');
        for FunctionName in FormulaFunctionNames do
          Add(FunctionName, FunctionName + '(', rsCompletionFunction);
      end;
  end;

  // Nothing to add to a word that is already complete
  if (Length(Result.Items) = 1) and (Result.Upto = Caret) and SameText(Result.Items[0].Insert, word) then
    Result.Items := nil;
end;

function ApplyCompletion(const Text: string; const Completion: TCompletion; Index: integer; out Caret: integer): string;
var
  Insert: string;
begin
  Insert := Completion.Items[Index].Insert;
  Result := Copy(Text, 1, Completion.From) + Insert + Copy(Text, Completion.Upto + 1, MaxInt);
  Caret := Completion.From + Length(Insert);
end;

end.
