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
// ({l1}.length + {v1} + @waist). It only checks spelling; names are resolved
// by TFormula. No LCL dependency.
unit osFormulaLexer;

{$mode ObjFPC}{$H+}

interface

type
  TFormulaTextForm = (ffDisplay, ffStored);

  TFormulaTokenKind = (
    ftNumber,       // 12, 0.5, .5, 1e3
    ftOperator,     // + - * / ^ ( ) ,
    ftName,         // plain identifier: a function, or a mistake
    ftMeasurement,  // @waist
    ftVariable,     // #ease (display form)
    ftObjectRef,    // Line_A_B.length (display form)
    ftIdRef         // {v1} or {l1}.length (stored form)
  );

  TFormulaToken = record
    Kind: TFormulaTokenKind;
    Pos, Len: Integer;   // 1-based byte position in the text
    Op: Char;            // ftOperator
    Value: Double;       // ftNumber
    Name: string;        // identifier, measurement key, variable/object name or ID
    Prop: string;        // property after the dot, if any
  end;

  TFormulaTokenArray = array of TFormulaToken;

// Splits Text into tokens. On failure ErrorMessage and ErrorPos (1-based)
// describe the first problem.
function TokenizeFormula(const Text: string; Form: TFormulaTextForm;
  out Tokens: TFormulaTokenArray; out ErrorMessage: string; out ErrorPos: Integer): Boolean;

resourcestring
  rsFormulaUnexpectedChar = 'Unexpected character "%s"';
  rsFormulaExpectedDigit = 'Expected a digit';
  rsFormulaExpectedProperty = 'Expected a property name after "."';
  rsFormulaExpectedMeasurement = 'Expected a measurement name after "@"';
  rsFormulaExpectedVariable = 'Expected a variable name after "#"';
  rsFormulaBadId = 'Expected an ID such as {p1}';

implementation

uses
  SysUtils;

function IsNameStart(C: Char): Boolean; inline;
begin
  Result := C in ['A'..'Z', 'a'..'z', '_'];
end;

function IsNameChar(C: Char): Boolean; inline;
begin
  Result := C in ['A'..'Z', 'a'..'z', '_', '0'..'9'];
end;

function IsDigit(C: Char): Boolean; inline;
begin
  Result := C in ['0'..'9'];
end;

// The whole UTF-8 character starting at Text[P], for error messages
function CharAt(const Text: string; P: Integer): string;
var
  N: Integer;
  B: Byte;
begin
  B := Ord(Text[P]);
  if B < $80 then
    N := 1
  else if B and $E0 = $C0 then
    N := 2
  else if B and $F0 = $E0 then
    N := 3
  else if B and $F8 = $F0 then
    N := 4
  else
    N := 1;
  Result := Copy(Text, P, N);
end;

function TokenizeFormula(const Text: string; Form: TFormulaTextForm;
  out Tokens: TFormulaTokenArray; out ErrorMessage: string; out ErrorPos: Integer): Boolean;
var
  P, Len, Count: Integer;

  procedure Fail(const Msg: string; At: Integer);
  begin
    ErrorMessage := Msg;
    ErrorPos := At;
  end;

  function Add(Kind: TFormulaTokenKind; Start: Integer): Integer;
  begin
    if Count = Length(Tokens) then
      SetLength(Tokens, Count * 2 + 8);
    Tokens[Count] := Default(TFormulaToken);
    Tokens[Count].Kind := Kind;
    Tokens[Count].Pos := Start;
    Tokens[Count].Len := P - Start;
    Result := Count;
    Inc(Count);
  end;

  function ReadName: string;
  var
    Start: Integer;
  begin
    Start := P;
    while (P <= Len) and IsNameChar(Text[P]) do
      Inc(P);
    Result := Copy(Text, Start, P - Start);
  end;

  // Reads ".prop" if present. False on a dot without a name.
  function ReadProperty(out Prop: string): Boolean;
  begin
    Prop := '';
    Result := True;
    if (P <= Len) and (Text[P] = '.') then
    begin
      Inc(P);
      if (P > Len) or not IsNameStart(Text[P]) then
      begin
        Fail(rsFormulaExpectedProperty, P);
        Exit(False);
      end;
      Prop := ReadName;
    end;
  end;

  function ReadNumber(Start: Integer): Boolean;
  var
    Code, I: Integer;
    V: Double;
  begin
    Result := False;
    while (P <= Len) and IsDigit(Text[P]) do
      Inc(P);
    if (P <= Len) and (Text[P] = '.') then
    begin
      Inc(P);
      if (P > Len) or not IsDigit(Text[P]) then
      begin
        Fail(rsFormulaExpectedDigit, P);
        Exit;
      end;
      while (P <= Len) and IsDigit(Text[P]) do
        Inc(P);
    end;
    if (P <= Len) and (Text[P] in ['e', 'E']) then
    begin
      Inc(P);
      if (P <= Len) and (Text[P] in ['+', '-']) then
        Inc(P);
      if (P > Len) or not IsDigit(Text[P]) then
      begin
        Fail(rsFormulaExpectedDigit, P);
        Exit;
      end;
      while (P <= Len) and IsDigit(Text[P]) do
        Inc(P);
    end;
    // Val always uses '.' as the decimal separator, whatever the locale
    Val(Copy(Text, Start, P - Start), V, Code);
    if Code <> 0 then
    begin
      Fail(rsFormulaExpectedDigit, Start + Code - 1);
      Exit;
    end;
    // Add may grow Tokens, so take the index before indexing
    I := Add(ftNumber, Start);
    Tokens[I].Value := V;
    Result := True;
  end;

var
  Start, I: Integer;
  C: Char;
  Name, Prop: string;
begin
  Tokens := nil;
  ErrorMessage := '';
  ErrorPos := 0;
  Count := 0;
  Len := Length(Text);
  P := 1;
  Result := False;
  while P <= Len do
  begin
    C := Text[P];
    Start := P;
    if C in [' ', #9, #10, #13] then
      Inc(P)
    else if IsDigit(C) or ((C = '.') and (P < Len) and IsDigit(Text[P + 1])) then
    begin
      if not ReadNumber(Start) then
        Exit;
    end
    else if C in ['+', '-', '*', '/', '^', '(', ')', ','] then
    begin
      Inc(P);
      I := Add(ftOperator, Start);
      Tokens[I].Op := C;
    end
    else if C = '@' then
    begin
      Inc(P);
      if (P > Len) or not IsNameStart(Text[P]) then
      begin
        Fail(rsFormulaExpectedMeasurement, P);
        Exit;
      end;
      Name := ReadName;
      I := Add(ftMeasurement, Start);
      Tokens[I].Name := Name;
    end
    else if (C = '#') and (Form = ffDisplay) then
    begin
      Inc(P);
      if (P > Len) or not IsNameStart(Text[P]) then
      begin
        Fail(rsFormulaExpectedVariable, P);
        Exit;
      end;
      Name := ReadName;
      I := Add(ftVariable, Start);
      Tokens[I].Name := Name;
    end
    else if (C = '{') and (Form = ffStored) then
    begin
      Inc(P);
      Name := ReadName;
      if (Name = '') or (P > Len) or (Text[P] <> '}') then
      begin
        Fail(rsFormulaBadId, Start);
        Exit;
      end;
      Inc(P);
      if not ReadProperty(Prop) then
        Exit;
      I := Add(ftIdRef, Start);
      Tokens[I].Name := Name;
      Tokens[I].Prop := Prop;
    end
    else if IsNameStart(C) then
    begin
      Name := ReadName;
      if not ReadProperty(Prop) then
        Exit;
      if Prop = '' then
        I := Add(ftName, Start)
      else
        I := Add(ftObjectRef, Start);
      Tokens[I].Name := Name;
      Tokens[I].Prop := Prop;
    end
    else
    begin
      Fail(Format(rsFormulaUnexpectedChar, [CharAt(Text, P)]), P);
      Exit;
    end;
  end;
  SetLength(Tokens, Count);
  Result := True;
end;

end.
