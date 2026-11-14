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

// Tokenizer for formulas. It reads either the display form the user types
// (Line_A_B.length + #ease + @waist) or the stored ID form
// ({12}.length + {3} + @waist). It only checks spelling; names are resolved
// by TFormula. A number may carry a unit straight after it (400mm, 1.5cm,
// 2in); the suffix is optional and stays part of the number's text, so both
// forms keep it. No LCL dependency.
unit Sloper.Core.FormulaLexer;

{$mode ObjFPC}{$H+}

interface

type
  TFormulaTextForm = (ffDisplay, ffStored);

  // The unit written after a number, if any
  TNumberSuffix = (nsNone, nsMillimetre, nsCentimetre, nsInch);

  TFormulaTokenKind = (
    ftNumber,       // 12, 0.5, .5, 1e3, 400mm, 1.5cm, 2in
    ftOperator,     // + - * / ^ ( ) ,
    ftName,         // plain identifier: a function, or a mistake
    ftMeasurement,  // @waist
    ftVariable,     // #ease (display form)
    ftObjectRef,    // Line_A_B.length (display form)
    ftIdRef         // {3} or {12}.length (stored form)
    );

  TFormulaToken = record
    Kind: TFormulaTokenKind;
    Pos, Len: integer;   // 1-based byte position in the text
    Op: char;            // ftOperator
    Value: double;       // ftNumber, as written, before any suffix converts it
    Suffix: TNumberSuffix; // ftNumber
    Name: string;        // identifier, measurement key, variable/object name or ID
    Prop: string;        // property after the dot, if any
  end;

  TFormulaTokenArray = array of TFormulaToken;

const
  NUMBER_SUFFIX_NAMES: array[TNumberSuffix] of string = ('', 'mm', 'cm', 'in');
  // Millimetres in one of each suffix's unit; a plain number is left as it is
  NUMBER_SUFFIX_MILLIMETRES: array[TNumberSuffix] of double = (1, 1, 10, 25.4);

// Splits Text into tokens. On failure ErrorMessage and ErrorPos (1-based)
// describe the first problem.
function TokenizeFormula(const Text: string; Form: TFormulaTextForm;
  out Tokens: TFormulaTokenArray; out ErrorMessage: string; out ErrorPos: integer): boolean;

resourcestring
  rsFormulaUnexpectedChar = 'Unexpected character "%s"';
  rsFormulaExpectedDigit = 'Expected a digit';
  rsFormulaNumberRange = 'This number is too large';
  rsFormulaExpectedProperty = 'Expected a property name after "."';
  rsFormulaExpectedMeasurement = 'Expected a measurement name after "@"';
  rsFormulaExpectedVariable = 'Expected a variable name after "#"';
  rsFormulaBadId = 'Expected an ID such as {12}';
  rsFormulaUnknownSuffix = 'Unknown unit "%s" after a number; use mm, cm or in';

implementation

uses
  SysUtils, Sloper.Core.Names, Sloper.Core.JSON;

function IsNameStart(Character: char): boolean; inline;
begin
  Result := Character in ['A'..'Z', 'a'..'z', '_'];
end;

function IsNameChar(Character: char): boolean; inline;
begin
  Result := Character in ['A'..'Z', 'a'..'z', '_', '0'..'9'];
end;

function IsDigit(Character: char): boolean; inline;
begin
  Result := Character in ['0'..'9'];
end;

// The whole UTF-8 character starting at Text[Position], for error messages
function CharAt(const Text: string; Position: integer): string;
var
  ByteCount: integer;
  LeadByte: byte;
begin
  LeadByte := Ord(Text[Position]);
  if LeadByte < $80 then
    ByteCount := 1
  else if LeadByte and $E0 = $C0 then
    ByteCount := 2
  else if LeadByte and $F0 = $E0 then
    ByteCount := 3
  else if LeadByte and $F8 = $F0 then
    ByteCount := 4
  else
    ByteCount := 1;
  Result := Copy(Text, Position, ByteCount);
end;

function TokenizeFormula(const Text: string; Form: TFormulaTextForm;
  out Tokens: TFormulaTokenArray; out ErrorMessage: string; out ErrorPos: integer): boolean;
var
  Position, Len, Count: integer;

  procedure Fail(const Msg: string; At: integer);
  begin
    ErrorMessage := Msg;
    ErrorPos := At;
  end;

  function Add(Kind: TFormulaTokenKind; Start: integer): integer;
  begin
    if Count = Length(Tokens) then
      SetLength(Tokens, Count * 2 + 8);
    Tokens[Count] := Default(TFormulaToken);
    Tokens[Count].Kind := Kind;
    Tokens[Count].Pos := Start;
    Tokens[Count].Len := Position - Start;
    Result := Count;
    Inc(Count);
  end;

  function ReadName: string;
  var
    Start: integer;
  begin
    Start := Position;
    while (Position <= Len) and IsNameChar(Text[Position]) do
      Inc(Position);
    Result := Copy(Text, Start, Position - Start);
  end;

  // Reads "[3]" if present, the index of one of a repeat's points
  function ReadRepeatIndex: string;
  var
    Start, Scan: integer;
  begin
    Result := '';
    Start := Position;
    if (Position > Len) or (Text[Position] <> '[') then
      Exit;
    Scan := Position + 1;
    while (Scan <= Len) and (Text[Scan] in ['0'..'9']) do
      Inc(Scan);
    if (Scan > Start + 1) and (Scan <= Len) and (Text[Scan] = ']') then
    begin
      Position := Scan + 1;
      Result := Copy(Text, Start, Position - Start);
    end;
  end;

  // Reads ".prop" if present. False on a dot without a name.
  function ReadProperty(out Prop: string): boolean;
  begin
    Prop := '';
    Result := True;
    if (Position <= Len) and (Text[Position] = '.') then
    begin
      Inc(Position);
      if (Position > Len) or not IsNameStart(Text[Position]) then
      begin
        Fail(rsFormulaExpectedProperty, Position);
        Exit(False);
      end;
      Prop := ReadName;
    end;
  end;

  // A unit straight after a number. Names cannot start with a digit, so any
  // letters there can only be a unit.
  function ReadSuffix(out Suffix: TNumberSuffix): boolean;
  var
    Start: integer;
    Written: string;
    Candidate: TNumberSuffix;
  begin
    Suffix := nsNone;
    Result := True;
    if (Position > Len) or not IsNameStart(Text[Position]) then
      Exit;
    Start := Position;
    Written := ReadName;
    for Candidate := Succ(nsNone) to High(TNumberSuffix) do
      if SameText(Written, NUMBER_SUFFIX_NAMES[Candidate]) then
      begin
        Suffix := Candidate;
        Exit;
      end;
    Fail(Format(rsFormulaUnknownSuffix, [Written]), Start);
    Result := False;
  end;

  function ReadNumber(Start: integer): boolean;
  var
    TokenIndex: integer;
    Value: double;
    Suffix: TNumberSuffix;
  begin
    Result := False;
    while (Position <= Len) and IsDigit(Text[Position]) do
      Inc(Position);
    if (Position <= Len) and (Text[Position] = '.') then
    begin
      Inc(Position);
      if (Position > Len) or not IsDigit(Text[Position]) then
      begin
        Fail(rsFormulaExpectedDigit, Position);
        Exit;
      end;
      while (Position <= Len) and IsDigit(Text[Position]) do
        Inc(Position);
    end;
    if (Position <= Len) and (Text[Position] in ['e', 'E']) then
    begin
      Inc(Position);
      if (Position <= Len) and (Text[Position] in ['+', '-']) then
        Inc(Position);
      if (Position > Len) or not IsDigit(Text[Position]) then
      begin
        Fail(rsFormulaExpectedDigit, Position);
        Exit;
      end;
      while (Position <= Len) and IsDigit(Text[Position]) do
        Inc(Position);
    end;
    // Its form is checked above, so only its size can fail: past a double's
    // range, read with no floating point exception, which would fail later work
    if not TextToFiniteFloat(Copy(Text, Start, Position - Start), Value) then
    begin
      Fail(rsFormulaNumberRange, Start);
      Exit;
    end;
    if not ReadSuffix(Suffix) then
      Exit;
    // Add may grow Tokens, so take the index before indexing
    TokenIndex := Add(ftNumber, Start);
    Tokens[TokenIndex].Value := Value;
    Tokens[TokenIndex].Suffix := Suffix;
    Result := True;
  end;

var
  Start, TokenIndex: integer;
  Character: char;
  Name, Prop: string;
begin
  Tokens := nil;
  ErrorMessage := '';
  ErrorPos := 0;
  Count := 0;
  Len := Length(Text);
  Position := 1;
  Result := False;
  while Position <= Len do
  begin
    Character := Text[Position];
    Start := Position;
    if Character in [' ', #9, #10, #13] then
      Inc(Position)
    else if IsDigit(Character) or ((Character = '.') and (Position < Len) and IsDigit(Text[Position + 1])) then
    begin
      if not ReadNumber(Start) then
        Exit;
    end
    else if Character in ['+', '-', '*', '/', '^', '(', ')', ','] then
    begin
      Inc(Position);
      TokenIndex := Add(ftOperator, Start);
      Tokens[TokenIndex].Op := Character;
    end
    else if Character = '@' then
    begin
      Inc(Position);
      if (Position > Len) or not IsNameStart(Text[Position]) then
      begin
        Fail(rsFormulaExpectedMeasurement, Position);
        Exit;
      end;
      Name := ReadName;
      TokenIndex := Add(ftMeasurement, Start);
      Tokens[TokenIndex].Name := Name;
    end
    else if (Character = '#') and (Form = ffDisplay) then
    begin
      Inc(Position);
      if (Position > Len) or not IsNameStart(Text[Position]) then
      begin
        Fail(rsFormulaExpectedVariable, Position);
        Exit;
      end;
      Name := ReadName;
      TokenIndex := Add(ftVariable, Start);
      Tokens[TokenIndex].Name := Name;
    end
    else if (Character = '{') and (Form = ffStored) then
    begin
      // IDs are positive integers, kept in their plain decimal form
      Inc(Position);
      Name := ReadName;
      if not IsIdText(Name) or (Position > Len) or (Text[Position] <> '}') then
      begin
        Fail(rsFormulaBadId, Start);
        Exit;
      end;
      Inc(Position);
      if not ReadProperty(Prop) then
        Exit;
      TokenIndex := Add(ftIdRef, Start);
      Tokens[TokenIndex].Name := Name;
      Tokens[TokenIndex].Prop := Prop;
    end
    else if IsNameStart(Character) then
    begin
      Name := ReadName;
      Name := Name + ReadRepeatIndex;
      if not ReadProperty(Prop) then
        Exit;
      if Prop = '' then
        TokenIndex := Add(ftName, Start)
      else
        TokenIndex := Add(ftObjectRef, Start);
      Tokens[TokenIndex].Name := Name;
      Tokens[TokenIndex].Prop := Prop;
    end
    else
    begin
      Fail(Format(rsFormulaUnexpectedChar, [CharAt(Text, Position)]), Position);
      Exit;
    end;
  end;
  SetLength(Tokens, Count);
  Result := True;
end;

end.
