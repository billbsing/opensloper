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

// The table of Automation API methods the reference documentation is
// written from, held to the server: every method listed is answered, every
// method answered is listed, and every parameter is one the server reads.
unit Sloper.Tests.ApiMethods;

{$mode ObjFPC}{$H+}

interface

uses
  fpcunit, testregistry, Sloper.Tests.TestCase;

type
  TTestApiMethods = class(TOSTestCase)
  private
    FSource: string;
  protected
    procedure SetUp; override;
  published
    procedure TestEveryListedMethodAnswers;
    procedure TestEveryAnsweredMethodListed;
    procedure TestEveryParameterRead;
    procedure TestMethodsAreUnique;
  end;

implementation

uses
  SysUtils, Classes, fpjson, Sloper.Core.JSON, Sloper.Core.Piece, Sloper.Core.Seam, Sloper.Core.Note, Sloper.API.Server, Sloper.API.Rpc,
  Sloper.API.Methods;

const
  PARAMETER_CONSTANTS: array[0..9, 0..1] of string = ((PIECE_ALLOWANCE_FIELD, 'PIECE_ALLOWANCE_FIELD'),
    (MARKING_SPACING_FIELD, 'MARKING_SPACING_FIELD'), (MARKING_SIZE_FIELD, 'MARKING_SIZE_FIELD'), (SEAM_EASE_FIELD, 'SEAM_EASE_FIELD'),
    (SEAM_TOLERANCE_FIELD, 'SEAM_TOLERANCE_FIELD'), (NOTE_X_FIELD, 'NOTE_X_FIELD'), (NOTE_Y_FIELD, 'NOTE_Y_FIELD'),
    (NOTE_DX_FIELD, 'NOTE_DX_FIELD'), (NOTE_DY_FIELD, 'NOTE_DY_FIELD'), (NOTE_POSITION_FIELD, 'NOTE_POSITION_FIELD'));

procedure TTestApiMethods.SetUp;
var
  Err: string;
begin
  AssertTrue(Err, ReadTextFile(ConcatPaths([ExtractFileDir(ExtractFileDir(ExpandFileName(ParamStr(0)))), 'src', 'api',
    'sloper.api.server.pas']), FSource, Err));
end;

procedure TTestApiMethods.TestEveryListedMethodAnswers;
var
  Server: TApiServer;
  Method: TApiMethod;
  Reply: TJSONObject;
  Err: string;
begin
  Server := TApiServer.Create;
  try
    for Method in ApiMethods do
    begin
      AssertTrue(Err, ParseJSONObject(Server.HandleLine('{"jsonrpc": "2.0", "id": 1, "method": "' + Method.Name +
        '", "params": {}}'), Reply, Err));
      try
        AssertFalse(Method.Name + ' is listed but not answered',
          Assigned(Reply.Find('error')) and (TJSONObject(Reply.Find('error')).Get('code', 0) = RPC_METHOD_NOT_FOUND));
      finally
        FreeAndNil(Reply);
      end;
    end;
  finally
    FreeAndNil(Server);
  end;
end;

// The case labels of TApiServer.CallMethod: lines such as  'open': Result := DoOpen(Params);
procedure TTestApiMethods.TestEveryAnsweredMethodListed;
var
  Lines: TStringList;
  Line, AnsweredName: string;
  Inside: boolean;
  Method: TApiMethod;
  Count: integer;
begin
  Lines := TStringList.Create;
  try
    Lines.Text := FSource;
    Inside := False;
    Count := 0;
    for Line in Lines do
    begin
      if Line.StartsWith('function TApiServer.DispatchMethod') then
        Inside := True
      else if Inside and (Line = 'end;') then
        Break
      else if Inside and (Pos(''': Result :=', Line) > 0) then
      begin
        AnsweredName := Trim(Line);
        AnsweredName := Copy(AnsweredName, 2, Pos('''', Copy(AnsweredName, 2, MaxInt)) - 1);
        AssertTrue(AnsweredName + ' is answered but not listed', FindApiMethod(AnsweredName, Method));
        Inc(Count);
      end;
    end;
    AssertEquals('as many answered as listed', Length(ApiMethods), Count);
  finally
    FreeAndNil(Lines);
  end;
end;

// Each name appears quoted in the server, or is a field-name constant it uses
procedure TTestApiMethods.TestEveryParameterRead;
var
  Method: TApiMethod;
  Param: TApiParam;
  Last: string;
  Index: integer;
  Found: boolean;
begin
  for Method in ApiMethods do
    for Param in Method.Params do
    begin
      if Param.Kind in [apTarget, apMembers] then
        Continue;
      // The member's own name: axis.edge is edge, sideA[].piece is piece
      Last := Param.Name;
      while LastDelimiter('.', Last) > 0 do
        Last := Copy(Last, LastDelimiter('.', Last) + 1, MaxInt);
      Found := Pos('''' + Last + '''', FSource) > 0;
      for Index := 0 to High(PARAMETER_CONSTANTS) do
        Found := Found or ((PARAMETER_CONSTANTS[Index, 0] = Last) and (Pos(PARAMETER_CONSTANTS[Index, 1], FSource) > 0));
      // The anchor's kinds are read by their names in NOTE_ANCHOR_NAMES
      Found := Found or ((Method.Name = 'add_note') and Param.Name.StartsWith('anchor.') and (Pos('NOTE_ANCHOR_NAMES', FSource) > 0));
      AssertTrue(Method.Name + ': the server never reads "' + Param.Name + '"', Found);
    end;
end;

procedure TTestApiMethods.TestMethodsAreUnique;
var
  Methods: TApiMethodArray;
  Index, Other: integer;
begin
  Methods := ApiMethods;
  for Index := 0 to High(Methods) do
    for Other := 0 to Index - 1 do
      AssertFalse(Methods[Index].Name + ' twice', Methods[Index].Name = Methods[Other].Name);
end;

initialization
  RegisterTest(TTestApiMethods);
end.
