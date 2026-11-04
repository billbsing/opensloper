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

type
  // The items so far, best first, with what each ranked
  TFoundItems = record
    Items: TCompletionItemArray;
    Ranks: array of integer;
    LowerWord: string;
  end;

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

// Adds an item in order of rank, then name, so a short name comes before longer ones
procedure AddItem(var Found: TFoundItems; const Name, Insert, Detail: string);
var
  Rank, Place, Index: integer;
begin
  Rank := MatchRank(Name, Found.LowerWord);
  if Rank < 0 then
    Exit;
  Place := Length(Found.Items);
  while (Place > 0) and ((Found.Ranks[Place - 1] > Rank) or ((Found.Ranks[Place - 1] = Rank) and
      (CompareText(Found.Items[Place - 1].Name, Name) > 0))) do
    Dec(Place);
  SetLength(Found.Items, Length(Found.Items) + 1);
  SetLength(Found.Ranks, Length(Found.Items));
  for Index := High(Found.Items) downto Place + 1 do
  begin
    Found.Items[Index] := Found.Items[Index - 1];
    Found.Ranks[Index] := Found.Ranks[Index - 1];
  end;
  Found.Items[Place].Name := Name;
  Found.Items[Place].Insert := Insert;
  Found.Items[Place].Detail := Detail;
  Found.Ranks[Place] := Rank;
end;

procedure AddMeasurements(var Found: TFoundItems; Pattern: TPattern; const Prefix: string);
var
  Index: integer;
  Measurement: TMeasurement;
begin
  if not Assigned(Pattern.Measurements) then
    Exit;
  for Index := 0 to Pattern.Measurements.Count - 1 do
  begin
    Measurement := Pattern.Measurements[Index];
    AddItem(Found, Measurement.Key, Prefix + Measurement.Key, Format(rsCompletionMeasurement, [RoundedText(Measurement.Value, ValueDecimals)]));
  end;
end;

// Node's own variable is left out: a formula cannot use itself
procedure AddVariables(var Found: TFoundItems; Pattern: TPattern; Node: TEvalNode; const Prefix: string);
var
  Index: integer;
  Variable: TVariable;
  Detail: string;
begin
  for Index := 0 to Pattern.VariableCount - 1 do
  begin
    Variable := Pattern.Variables[Index];
    if Variable = Node then
      Continue;
    Detail := '';
    if Variable.State = esValid then
      Detail := RoundedText(Variable.Value, ValueDecimals);
    AddItem(Found, Variable.Name, Prefix + Variable.Name, Detail);
  end;
end;

procedure AddProperties(var Found: TFoundItems; Owner: TDraftObject);
var
  PropertyName, Detail: string;
begin
  for PropertyName in PropertyNames do
    if Owner.HasProperty(PropertyName) then
    begin
      Detail := '';
      if Owner.HasResult and (Owner.State = esValid) then
        Detail := RoundedText(Owner.PropertyValue(PropertyName), ValueDecimals);
      AddItem(Found, PropertyName, PropertyName, Detail);
    end;
end;

// What a bare word can be. An object's dot goes in with it, and a function's bracket.
procedure AddBareWordItems(var Found: TFoundItems; Pattern: TPattern; Node: TEvalNode);
var
  Index: integer;
  DraftObject: TDraftObject;
  FunctionName: string;
begin
  if not (Node is TVariable) then
    for Index := 0 to Pattern.ObjectCount - 1 do
    begin
      DraftObject := Pattern.Objects[Index];
      if DraftObject <> Node then
        AddItem(Found, DraftObject.DisplayName, DraftObject.DisplayName + '.', TypeCaption(DraftObject));
    end;
  AddVariables(Found, Pattern, Node, '#');
  AddMeasurements(Found, Pattern, '@');
  for FunctionName in FormulaFunctionNames do
    AddItem(Found, FunctionName, FunctionName + '(', rsCompletionFunction);
end;

// The object named just before the dot at offset DotOffset, if a formula for
// Node may read its properties
function ObjectBeforeDot(Pattern: TPattern; Node: TEvalNode; const Text: string; DotOffset: integer): TDraftObject;
var
  Start: integer;
  OwnerName: string;
begin
  Result := nil;
  if Node is TVariable then
    Exit;
  Start := DotOffset;
  while (Start > 0) and IsWordChar(Text[Start]) do
    Dec(Start);
  OwnerName := Copy(Text, Start + 1, DotOffset - Start);
  if (OwnerName = '') or (OwnerName[1] in ['0'..'9']) then
    Exit;
  Result := Pattern.FindObject(OwnerName);
  if Result = Node then
    Result := nil;
end;

function FormulaCompletion(Pattern: TPattern; Node: TEvalNode; const Text: string; Caret: integer; Explicit: boolean): TCompletion;
var
  WordStart: integer;
  CaretWord: string;
  Before: char;
  Found: TFoundItems;
  Owner: TDraftObject;
begin
  Result := Default(TCompletion);
  if (Caret < 0) or (Caret > Length(Text)) then
    Exit;
  WordStart := Caret;
  while (WordStart > 0) and IsWordChar(Text[WordStart]) do
    Dec(WordStart);
  CaretWord := Copy(Text, WordStart + 1, Caret - WordStart);
  Result.From := WordStart;
  Result.Upto := Caret;
  // The rest of a word the caret is inside goes too
  while (Result.Upto < Length(Text)) and IsWordChar(Text[Result.Upto + 1]) do
    Inc(Result.Upto);
  Before := #0;
  if WordStart > 0 then
    Before := Text[WordStart];
  // A number such as 12 or 1.5 is not a name
  if (CaretWord <> '') and (CaretWord[1] in ['0'..'9']) and (Before <> '.') then
    Exit;

  Found := Default(TFoundItems);
  Found.LowerWord := LowerCase(CaretWord);
  case Before of
    '@':
      AddMeasurements(Found, Pattern, '');
    '#':
      AddVariables(Found, Pattern, Node, '');
    '.':
    begin
      Owner := ObjectBeforeDot(Pattern, Node, Text, WordStart - 1);
      if Assigned(Owner) then
        AddProperties(Found, Owner);
    end;
    else
      if (CaretWord <> '') or Explicit then
        AddBareWordItems(Found, Pattern, Node);
  end;

  // Nothing to add to a word that is already complete
  if (Length(Found.Items) = 1) and (Result.Upto = Caret) and SameText(Found.Items[0].Insert, CaretWord) then
    Exit;
  Result.Items := Found.Items;
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
