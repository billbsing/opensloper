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

// Name rules for draft objects, variables and measurements: valid names,
// reserved words, case-insensitive comparison and numbering of copies; and
// the form of IDs.
// No LCL dependency.
unit Sloper.Core.Names;

{$mode ObjFPC}{$H+}

interface

type
  TNameTakenFunc = function(const Name: string): boolean of object;

const
  // Formula functions; names may not use them
  FORMULA_FUNCTION_NAMES: array[0..10] of string = ('sin', 'cos', 'tan', 'asin',
    'acos', 'atan2', 'sqrt', 'abs', 'min', 'max', 'round');

// Letters, digits and underscore, not starting with a digit, not reserved
function IsValidName(const Name: string): boolean;
function IsReservedName(const Name: string): boolean;
function IsFunctionName(const Name: string): boolean;
// IsValidName with a message saying what is wrong
function CheckName(const Name: string; out ErrorMessage: string): boolean;
function SameName(const First, Second: string): boolean;
// Name for a copy when Name is taken: trailing digits are stripped and the
// next free number from 2 is appended (A -> A2, A2 -> A3, Hip2 -> Hip3).
// Returns Name itself when it is free.
function NextFreeName(const Name: string; IsTaken: TNameTakenFunc): string;
// Next automatic point name, counting like spreadsheet columns: A to Z, then
// AA to AZ, BA to ZZ, then AAA. Skips taken and reserved names. Never has
// digits, so a trailing number always means a copy.
function NextAutoName(IsTaken: TNameTakenFunc): string;
// A name the app could have made: an automatic name, perhaps with a copy
// number (M, AB, M2, M1). Any other name is taken to be the user's.
function IsMadeName(const Name: string): boolean;
// The name merged points keep: the first one the user gave, in order, or else
// the lowest made name, counting as NextAutoName does (M, MyNode, O gives
// MyNode; M, N, O gives M; Z before AA, M before M2)
function MergedName(const Names: array of string): string;
// An ID as text: a positive integer in plain decimal (12, not 012 or 0),
// small enough for an integer
function IsIdText(const Text: string): boolean;

resourcestring
  rsNameEmpty = 'The name is empty';
  rsNameInvalid = '"%s" is not a valid name: use letters, digits and underscore, not starting with a digit';
  rsNameReserved = '"%s" is a function name and cannot be used';
  rsNameTaken = '"%s" is already used';

implementation

uses
  SysUtils;

function IsNameStart(Character: char): boolean;
begin
  Result := Character in ['A'..'Z', 'a'..'z', '_'];
end;

function IsNameChar(Character: char): boolean;
begin
  Result := Character in ['A'..'Z', 'a'..'z', '_', '0'..'9'];
end;

function IsIdText(const Text: string): boolean;
var
  Index: integer;
begin
  if (Text = '') or (Length(Text) > 9) or (Text[1] = '0') then
    Exit(False);
  for Index := 1 to Length(Text) do
    if not (Text[Index] in ['0'..'9']) then
      Exit(False);
  Result := True;
end;

function IsFunctionName(const Name: string): boolean;
var
  FunctionName: string;
begin
  for FunctionName in FORMULA_FUNCTION_NAMES do
    if SameText(FunctionName, Name) then
      Exit(True);
  Result := False;
end;

function IsReservedName(const Name: string): boolean;
begin
  Result := IsFunctionName(Name);
end;

function IsValidName(const Name: string): boolean;
var
  Index: integer;
begin
  if (Name = '') or not IsNameStart(Name[1]) then
    Exit(False);
  for Index := 2 to Length(Name) do
    if not IsNameChar(Name[Index]) then
      Exit(False);
  Result := not IsReservedName(Name);
end;

function CheckName(const Name: string; out ErrorMessage: string): boolean;
begin
  ErrorMessage := '';
  if Name = '' then
    ErrorMessage := rsNameEmpty
  else if IsReservedName(Name) then
    ErrorMessage := Format(rsNameReserved, [Name])
  else if not IsValidName(Name) then
    ErrorMessage := Format(rsNameInvalid, [Name]);
  Result := ErrorMessage = '';
end;

function SameName(const First, Second: string): boolean;
begin
  Result := SameText(First, Second);
end;

function NextFreeName(const Name: string; IsTaken: TNameTakenFunc): string;
var
  Stem: string;
  Number: integer;
begin
  if not IsTaken(Name) then
    Exit(Name);
  Stem := Name;
  while (Length(Stem) > 1) and (Stem[Length(Stem)] in ['0'..'9']) do
    SetLength(Stem, Length(Stem) - 1);
  Number := 2;
  repeat
    Result := Stem + IntToStr(Number);
    Inc(Number);
  until not IsTaken(Result);
end;

// The Index'th spreadsheet column name, from 1: A, B … Z, AA, AB …
function ColumnName(Index: integer): string;
begin
  Result := '';
  while Index > 0 do
  begin
    Dec(Index);
    Result := Chr(Ord('A') + Index mod 26) + Result;
    Index := Index div 26;
  end;
end;

function NextAutoName(IsTaken: TNameTakenFunc): string;
var
  Index: integer;
begin
  Index := 1;
  repeat
    Result := ColumnName(Index);
    if not IsReservedName(Result) and not IsTaken(Result) then
      Exit;
    Inc(Index);
  until False;
end;

// Splits a made name into its letters and copy number, 0 for none
procedure SplitMadeName(const Name: string; out Letters: string; out Number: integer);
var
  Index: integer;
begin
  Index := Length(Name);
  while (Index > 0) and (Name[Index] in ['0'..'9']) do
    Dec(Index);
  Letters := Copy(Name, 1, Index);
  Number := StrToIntDef(Copy(Name, Index + 1, MaxInt), 0);
end;

function IsMadeName(const Name: string): boolean;
var
  Letters: string;
  Number, Index: integer;
begin
  SplitMadeName(Name, Letters, Number);
  // A copy number never starts with 0
  if (Letters = '') or ((Letters <> Name) and (Name[Length(Letters) + 1] = '0')) then
    Exit(False);
  for Index := 1 to Length(Letters) do
    if not (Letters[Index] in ['A'..'Z']) then
      Exit(False);
  Result := True;
end;

// Below zero when First comes before Second in the order names are made
function CompareMadeNames(const First, Second: string): integer;
var
  FirstLetters, SecondLetters: string;
  FirstNumber, SecondNumber: integer;
begin
  SplitMadeName(First, FirstLetters, FirstNumber);
  SplitMadeName(Second, SecondLetters, SecondNumber);
  Result := Length(FirstLetters) - Length(SecondLetters);
  if Result = 0 then
    Result := CompareStr(FirstLetters, SecondLetters);
  if Result = 0 then
    Result := FirstNumber - SecondNumber;
end;

function MergedName(const Names: array of string): string;
var
  Candidate: string;
begin
  Result := '';
  for Candidate in Names do
    if not IsMadeName(Candidate) then
      Exit(Candidate);
  for Candidate in Names do
    if (Result = '') or (CompareMadeNames(Candidate, Result) < 0) then
      Result := Candidate;
end;

end.
