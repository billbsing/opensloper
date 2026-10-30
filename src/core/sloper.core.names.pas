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
  FormulaFunctionNames: array[0..10] of string = ('sin', 'cos', 'tan', 'asin',
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
// Next automatic point name: A to Z, then A1 to Z1, A2 and so on
function NextAutoName(IsTaken: TNameTakenFunc): string;
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
  for FunctionName in FormulaFunctionNames do
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

function NextAutoName(IsTaken: TNameTakenFunc): string;
var
  Suffix: integer;
  Letter: char;
begin
  Suffix := 0;
  repeat
    for Letter := 'A' to 'Z' do
    begin
      if Suffix = 0 then
        Result := Letter
      else
        Result := Letter + IntToStr(Suffix);
      if not IsTaken(Result) then
        Exit;
    end;
    Inc(Suffix);
  until False;
end;

end.
