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

// JSON helpers for OpenSloper files: readable number formatting, a writer
// with a fixed layout (two-space indent, "key": value) so saved files diff
// cleanly, and parsing that reports errors instead of raising them.
// No LCL dependency.
unit osJSON;

{$mode ObjFPC}{$H+}

interface

uses
  fpjson;

type
  // A float that writes itself in the shortest form that reads back exactly
  TOSJSONFloat = class(TJSONFloatNumber)
  protected
    function GetAsString: TJSONStringType; override;
  end;

// Shortest text that reads back as exactly V, with '.' as decimal point
function FormatJSONFloat(V: Double): string;
function JSONFloat(V: Double): TJSONData;
// Two-space indent, "key": value, members in insertion order, LF line ends
function JSONToText(Data: TJSONData): string;
// Parses Text, which must hold a JSON object. The caller frees Obj.
function ParseJSONObject(const Text: string; out Obj: TJSONObject; out ErrorMessage: string): Boolean;
function ReadTextFile(const FileName: string; out Text: string; out ErrorMessage: string): Boolean;
function WriteTextFile(const FileName, Text: string; out ErrorMessage: string): Boolean;

// Typed member access. False when the member is missing or the wrong type.
function GetJSONString(Obj: TJSONObject; const Name: string; out Value: string): Boolean;
function GetJSONNumber(Obj: TJSONObject; const Name: string; out Value: Double): Boolean;
function GetJSONInteger(Obj: TJSONObject; const Name: string; out Value: Integer): Boolean;

resourcestring
  rsJSONNotObject = 'The file does not contain a JSON object';
  rsJSONSyntax = 'The file is not valid JSON: %s';
  rsFileRead = 'Could not read "%s": %s';
  rsFileWrite = 'Could not write "%s": %s';

implementation

uses
  Classes, SysUtils, jsonparser;

function JSONFormatSettings: TFormatSettings;
begin
  Result := DefaultFormatSettings;
  Result.DecimalSeparator := '.';
  Result.ThousandSeparator := #0;
end;

function FormatJSONFloat(V: Double): string;
var
  Settings: TFormatSettings;
  Precision: Integer;
  Back: Double;
begin
  if Frac(V) = 0 then
    if Abs(V) < 1e15 then
      Exit(IntToStr(Trunc(V)));
  Settings := JSONFormatSettings;
  for Precision := 15 to 17 do
  begin
    Result := FloatToStrF(V, ffGeneral, Precision, 0, Settings);
    // StrToFloat returns Extended; compare as Double or 0.1 never matches
    Back := StrToFloat(Result, Settings);
    if Back = V then
      Exit;
  end;
end;

function TOSJSONFloat.GetAsString: TJSONStringType;
begin
  Result := FormatJSONFloat(AsFloat);
end;

function JSONFloat(V: Double): TJSONData;
begin
  Result := TOSJSONFloat.Create(V);
end;

procedure WriteValue(Data: TJSONData; const Indent: string; Lines: TStrings; var Line: string);
var
  I: Integer;
  Inner: string;
  Obj: TJSONObject;
begin
  case Data.JSONType of
    jtObject:
      begin
        Obj := TJSONObject(Data);
        if Obj.Count = 0 then
        begin
          Line := Line + '{}';
          Exit;
        end;
        Lines.Add(Line + '{');
        Inner := Indent + '  ';
        for I := 0 to Obj.Count - 1 do
        begin
          Line := Inner + '"' + StringToJSONString(Obj.Names[I]) + '": ';
          WriteValue(Obj.Items[I], Inner, Lines, Line);
          if I < Obj.Count - 1 then
            Line := Line + ',';
          Lines.Add(Line);
        end;
        Line := Indent + '}';
      end;
    jtArray:
      begin
        if Data.Count = 0 then
        begin
          Line := Line + '[]';
          Exit;
        end;
        Lines.Add(Line + '[');
        Inner := Indent + '  ';
        for I := 0 to Data.Count - 1 do
        begin
          Line := Inner;
          WriteValue(Data.Items[I], Inner, Lines, Line);
          if I < Data.Count - 1 then
            Line := Line + ',';
          Lines.Add(Line);
        end;
        Line := Indent + ']';
      end;
    jtNumber:
      if Data is TJSONFloatNumber then
        Line := Line + FormatJSONFloat(Data.AsFloat)
      else
        Line := Line + Data.AsJSON;
  else
    // Strings, booleans and null
    Line := Line + Data.AsJSON;
  end;
end;

function JSONToText(Data: TJSONData): string;
var
  Lines: TStringList;
  Line: string;
  I: Integer;
begin
  Lines := TStringList.Create;
  try
    Line := '';
    WriteValue(Data, '', Lines, Line);
    Lines.Add(Line);
    Result := '';
    for I := 0 to Lines.Count - 1 do
      Result := Result + Lines[I] + #10;
  finally
    Lines.Free;
  end;
end;

function ParseJSONObject(const Text: string; out Obj: TJSONObject; out ErrorMessage: string): Boolean;
var
  Data: TJSONData;
begin
  Obj := nil;
  ErrorMessage := '';
  try
    Data := GetJSON(Text);
  except
    on E: Exception do
    begin
      ErrorMessage := Format(rsJSONSyntax, [E.Message]);
      Exit(False);
    end;
  end;
  if not (Data is TJSONObject) then
  begin
    Data.Free;
    ErrorMessage := rsJSONNotObject;
    Exit(False);
  end;
  Obj := TJSONObject(Data);
  Result := True;
end;

function ReadTextFile(const FileName: string; out Text: string; out ErrorMessage: string): Boolean;
var
  Stream: TFileStream;
begin
  Text := '';
  ErrorMessage := '';
  try
    Stream := TFileStream.Create(FileName, fmOpenRead or fmShareDenyWrite);
    try
      SetLength(Text, Stream.Size);
      if Length(Text) > 0 then
        Stream.ReadBuffer(Text[1], Length(Text));
    finally
      Stream.Free;
    end;
    Result := True;
  except
    on E: Exception do
    begin
      ErrorMessage := Format(rsFileRead, [FileName, E.Message]);
      Result := False;
    end;
  end;
end;

function WriteTextFile(const FileName, Text: string; out ErrorMessage: string): Boolean;
var
  Stream: TFileStream;
begin
  ErrorMessage := '';
  try
    Stream := TFileStream.Create(FileName, fmCreate);
    try
      if Length(Text) > 0 then
        Stream.WriteBuffer(Text[1], Length(Text));
    finally
      Stream.Free;
    end;
    Result := True;
  except
    on E: Exception do
    begin
      ErrorMessage := Format(rsFileWrite, [FileName, E.Message]);
      Result := False;
    end;
  end;
end;

function GetJSONString(Obj: TJSONObject; const Name: string; out Value: string): Boolean;
var
  Data: TJSONData;
begin
  Value := '';
  Data := Obj.Find(Name);
  Result := (Data <> nil) and (Data.JSONType = jtString);
  if Result then
    Value := Data.AsString;
end;

function GetJSONNumber(Obj: TJSONObject; const Name: string; out Value: Double): Boolean;
var
  Data: TJSONData;
begin
  Value := 0;
  Data := Obj.Find(Name);
  Result := (Data <> nil) and (Data.JSONType = jtNumber);
  if Result then
    Value := Data.AsFloat;
end;

function GetJSONInteger(Obj: TJSONObject; const Name: string; out Value: Integer): Boolean;
var
  Data: TJSONData;
begin
  Value := 0;
  Data := Obj.Find(Name);
  Result := (Data <> nil) and (Data.JSONType = jtNumber) and not (Data is TJSONFloatNumber);
  if Result then
    Value := Data.AsInteger;
end;

end.
