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

// The API answered by a design window in automation mode, for
// opensloper-cli serve --connect. It connects on the first call, to the
// newest window listening, reading the token from the window's endpoint file,
// and connects again after the window closes or drops it. No LCL dependency.
unit Sloper.API.Connection;

{$mode ObjFPC}{$H+}

interface

uses
  SysUtils, fpjson, Sloper.API.Server, Sloper.API.Endpoint;

type
  TApiConnection = class(TApiBackend)
  private
    FLines: TSocketLines;
    FNextId: integer;
    // Connected and admitted, or EApiError saying why not
    procedure EnsureConnected;
    function TryEndpoint(const Endpoint: TAutomationEndpoint): boolean;
    procedure Drop;
    // Sends Line and, when Answered, waits for the reply
    function Exchange(const Line: string; Answered: boolean): string;
  public
    destructor Destroy; override;
    function CallMethod(const Method: string; Params: TJSONObject): TJSONData; override;
    function HandleLine(const Line: string): string; override;
    function Connected: boolean;
  end;

resourcestring
  rsConnectNoWindow = 'No OpenSloper design window is accepting Claude. Open the pattern in the design window and ' +
    'choose Tools → Allow Claude to Connect, or start it with --automation.';
  rsConnectLost = 'The design window closed the connection';

implementation

uses
  Sloper.Core.JSON;

const
  // How long a window has to admit the client; ms
  AUTH_REPLY_MS = 5000;
  // No limit: the user may be answering the window's question
  REPLY_NO_LIMIT = -1;

destructor TApiConnection.Destroy;
begin
  Drop;
  inherited Destroy;
end;

function TApiConnection.Connected: boolean;
begin
  Result := Assigned(FLines);
end;

procedure TApiConnection.Drop;
begin
  FreeAndNil(FLines);
end;

function TApiConnection.TryEndpoint(const Endpoint: TAutomationEndpoint): boolean;
var
  Request: TJSONObject;
  Reply: TJSONObject;
  Line, Err: string;
begin
  Result := False;
  try
    FLines := TSocketLines.Create(ConnectAutomation(Endpoint));
  except
    // Nothing listens there: a window that closed without tidying up
    on Exception do
      Exit;
  end;
  Request := TJSONObject.Create(['jsonrpc', '2.0', 'id', 0, 'method', AUTOMATION_AUTH_METHOD, 'params',
    TJSONObject.Create([AUTOMATION_TOKEN_PARAM, Endpoint.Token])]);
  try
    try
      FLines.WriteLine(Request.AsJSON);
      if (FLines.ReadLine(AUTH_REPLY_MS, AUTOMATION_LINE_LIMIT, Line) = lrLine) and ParseJSONObject(Line, Reply, Err) then
      try
        Result := Assigned(Reply.Find('result'));
      finally
        FreeAndNil(Reply);
      end;
    except
      on Exception do
        Result := False;
    end;
  finally
    FreeAndNil(Request);
  end;
  if not Result then
    Drop;
end;

procedure TApiConnection.EnsureConnected;
var
  Endpoint: TAutomationEndpoint;
begin
  if Connected then
    Exit;
  for Endpoint in ReadAutomationEndpoints do
    if TryEndpoint(Endpoint) then
      Exit;
  raise EApiError.Create(RPC_REFUSED, rsConnectNoWindow);
end;

function TApiConnection.Exchange(const Line: string; Answered: boolean): string;
begin
  EnsureConnected;
  Result := '';
  try
    FLines.WriteLine(Line);
    if Answered and (FLines.ReadLine(REPLY_NO_LIMIT, AUTOMATION_LINE_LIMIT, Result) <> lrLine) then
    begin
      Drop;
      raise EApiError.Create(RPC_REFUSED, rsConnectLost);
    end;
  except
    on Failure: EApiError do
      raise;
    on Exception do
    begin
      Drop;
      raise EApiError.Create(RPC_REFUSED, rsConnectLost);
    end;
  end;
end;

function TApiConnection.CallMethod(const Method: string; Params: TJSONObject): TJSONData;
var
  Request, Reply, Error, Data: TJSONObject;
  Err: string;
begin
  Inc(FNextId);
  Request := TJSONObject.Create(['jsonrpc', '2.0', 'id', FNextId, 'method', Method, 'params', Params.Clone]);
  try
    if not ParseJSONObject(Exchange(Request.AsJSON, True), Reply, Err) then
      raise EApiError.Create(RPC_INTERNAL_ERROR, Err);
  finally
    FreeAndNil(Request);
  end;
  try
    if Assigned(Reply.Find('error')) and (Reply.Find('error').JSONType = jtObject) then
    begin
      Error := Reply.Objects['error'];
      Data := nil;
      if Assigned(Error.Find('data')) and (Error.Find('data').JSONType = jtObject) then
        Data := Error.Objects['data'];
      if Assigned(Data) then
        raise EApiError.Create(Error.Get('code', RPC_INTERNAL_ERROR), Error.Get('message', ''), Data.Get('field', ''),
          Data.Get('position', 0))
      else
        raise EApiError.Create(Error.Get('code', RPC_INTERNAL_ERROR), Error.Get('message', ''));
    end;
    if not Assigned(Reply.Find('result')) then
      raise EApiError.Create(RPC_INTERNAL_ERROR, rsConnectLost);
    Result := Reply.Extract('result');
  finally
    FreeAndNil(Reply);
  end;
end;

// Passed on as it is; only a request with an id gets a reply to wait for
function TApiConnection.HandleLine(const Line: string): string;
var
  Request: TJSONObject;
  Err: string;
  Id: TJSONData;
begin
  Id := nil;
  Request := nil;
  try
    // A line that does not parse is the window's to answer, with an error
    if ParseJSONObject(Line, Request, Err) and Assigned(Request.Find('id')) then
      Id := Request.Find('id').Clone
    else if not Assigned(Request) then
      Id := TJSONNull.Create;
    try
      Result := Exchange(Line, Assigned(Id));
    except
      on Failure: EApiError do
      begin
        Result := '';
        if Assigned(Id) then
          Result := RpcErrorResponse(Id, Failure.Code, Failure.Message);
      end;
    end;
  finally
    FreeAndNil(Id);
    FreeAndNil(Request);
  end;
end;

end.
