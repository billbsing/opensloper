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

// The design window's automation socket: a thread that accepts one client at
// a time, admits it only with the endpoint's token, and hands each request
// line to the window. In the window the handlers run on the main thread, so
// requests reach the document between the user's own edits. No LCL dependency.
unit Sloper.API.Listener;

{$mode ObjFPC}{$H+}

interface

uses
  Classes, SysUtils, ssockets, Sloper.API.Endpoint;

type
  // The reply to one request line; '' for a notification
  TAutomationRequestEvent = function(const Line: string): string of object;
  TAutomationClientEvent = procedure(Connected: boolean) of object;

  TAutomationListener = class(TThread)
  private
    FServer: TSocketServer;
    FEndpoint: TAutomationEndpoint;
    FOnRequest: TAutomationRequestEvent;
    FOnClient: TAutomationClientEvent;
    FSynchronized: boolean;
    FDropClient: boolean;
    // Passed to the main thread
    FLine, FReply: string;
    FConnected: boolean;
    constructor Create(AServer: TSocketServer; const AEndpoint: TAutomationEndpoint; AOnRequest: TAutomationRequestEvent;
      AOnClient: TAutomationClientEvent; ASynchronized: boolean);
    procedure ServerIdle(Sender: TObject);
    procedure ServerConnect(Sender: TObject; Data: TSocketStream);
    function Authenticate(Lines: TSocketLines): boolean;
    procedure Serve(Lines: TSocketLines);
    procedure CallRequest;
    procedure CallClient;
    function Request(const Line: string): string;
    procedure ClientChanged(Connected: boolean);
  protected
    procedure Execute; override;
  public
    // Listening, its endpoint file written; nil with a message when it could
    // not start. Synchronized runs the handlers on the main thread, as the
    // window needs; tests call them on the listener's thread.
    class function Start(AOnRequest: TAutomationRequestEvent; AOnClient: TAutomationClientEvent; ASynchronized: boolean;
      out ErrorMessage: string): TAutomationListener;
    // Stops listening and removes the endpoint
    destructor Destroy; override;
    // Closes the connection to the client after the reply being sent, if any
    procedure Disconnect;
    property Endpoint: TAutomationEndpoint read FEndpoint;
  end;

resourcestring
  rsAutomationNotAllowed = 'Not allowed: the token does not match';
  rsAutomationCannotListen = 'Automation could not start: %s';
  rsAutomationPathTooLong = 'Automation could not start: the socket path %s is too long; the system allows %d characters';

implementation

uses
  fpjson, Sockets, {$IFDEF UNIX} BaseUnix, {$ENDIF} Sloper.Core.JSON, Sloper.API.Server;

const
  // How often the thread looks up from waiting, to stop or drop a client; ms
  POLL_MS = 200;
  // How long a client has to send its token; ms
  AUTH_WAIT_MS = 5000;
  {$IFDEF UNIX}
  SOCKET_FILE_MODE = &600;
  // The longest socket path every Unix takes (macOS 104, Linux 108, with the
  // closing zero); ssockets crashes rather than report a longer one
  SOCKET_PATH_LIMIT = 103;
  {$ENDIF}

class function TAutomationListener.Start(AOnRequest: TAutomationRequestEvent; AOnClient: TAutomationClientEvent;
  ASynchronized: boolean; out ErrorMessage: string): TAutomationListener;
var
  Folder: string;
  Place: TAutomationEndpoint;
  Server: TSocketServer;
  {$IFDEF WINDOWS}
  Address: TInetSockAddr;
  AddressLength: TSockLen;
  {$ENDIF}
begin
  Result := nil;
  if not PrepareAutomationFolder(Folder, ErrorMessage) then
    Exit;
  Place := AutomationEndpointFor(Folder, GetProcessID);
  if not NewAutomationToken(Place.Token, ErrorMessage) then
    Exit;
  Server := nil;
  try
    {$IFDEF UNIX}
    if Length(Place.SocketPath) > SOCKET_PATH_LIMIT then
    begin
      ErrorMessage := Format(rsAutomationPathTooLong, [Place.SocketPath, SOCKET_PATH_LIMIT]);
      Exit;
    end;
    // Left by an earlier run with this process number
    DeleteFile(Place.SocketPath);
    Server := TUnixServer.Create(Place.SocketPath);
    Server.Listen;
    fpChmod(Place.SocketPath, SOCKET_FILE_MODE);
    {$ELSE}
    Server := TInetServer.Create(AUTOMATION_HOST, 0);
    Server.Listen;
    AddressLength := SizeOf(Address);
    fpGetSockName(Server.Socket, @Address, @AddressLength);
    Place.Port := NToHs(Address.sin_port);
    {$ENDIF}
    if not WriteAutomationEndpoint(Place, ErrorMessage) then
    begin
      FreeAndNil(Server);
      DeleteFile(Place.InfoPath);
      Exit;
    end;
  except
    on Failure: Exception do
    begin
      ErrorMessage := Format(rsAutomationCannotListen, [Failure.Message]);
      FreeAndNil(Server);
      Exit;
    end;
  end;
  Result := TAutomationListener.Create(Server, Place, AOnRequest, AOnClient, ASynchronized);
end;

constructor TAutomationListener.Create(AServer: TSocketServer; const AEndpoint: TAutomationEndpoint;
  AOnRequest: TAutomationRequestEvent; AOnClient: TAutomationClientEvent; ASynchronized: boolean);
begin
  FServer := AServer;
  FEndpoint := AEndpoint;
  FOnRequest := AOnRequest;
  FOnClient := AOnClient;
  FSynchronized := ASynchronized;
  FServer.AcceptIdleTimeOut := POLL_MS;
  FServer.OnIdle := @ServerIdle;
  FServer.OnConnect := @ServerConnect;
  inherited Create(False);
end;

destructor TAutomationListener.Destroy;
begin
  Terminate;
  // In the window, WaitFor keeps answering Synchronize, so a request in
  // progress finishes first
  WaitFor;
  FreeAndNil(FServer);
  DeleteFile(FEndpoint.InfoPath);
  {$IFDEF UNIX}
  DeleteFile(FEndpoint.SocketPath);
  {$ENDIF}
  inherited Destroy;
end;

procedure TAutomationListener.Execute;
begin
  try
    FServer.StartAccepting;
  except
    // The socket failed; the window still shows automation on until turned off
    on Exception do ;
  end;
end;

procedure TAutomationListener.ServerIdle(Sender: TObject);
begin
  if Terminated then
    FServer.StopAccepting;
end;

procedure TAutomationListener.Disconnect;
begin
  FDropClient := True;
end;

procedure TAutomationListener.ServerConnect(Sender: TObject; Data: TSocketStream);
var
  Lines: TSocketLines;
begin
  Lines := TSocketLines.Create(Data);
  try
    FDropClient := False;
    try
      if Authenticate(Lines) then
      begin
        ClientChanged(True);
        try
          Serve(Lines);
        finally
          ClientChanged(False);
        end;
      end;
    except
      // The client went away mid-reply
      on Exception do ;
    end;
  finally
    FreeAndNil(Lines);
  end;
  if Terminated then
    FServer.StopAccepting;
end;

// The first line must be authenticate with the token
function TAutomationListener.Authenticate(Lines: TSocketLines): boolean;
var
  Line, Err, Method, Token: string;
  Waited: integer;
  Message, Params: TJSONObject;
  Id: TJSONData;
begin
  Result := False;
  Waited := 0;
  repeat
    case Lines.ReadLine(POLL_MS, AUTOMATION_AUTH_LINE_LIMIT, Line) of
      lrLine: Break;
      lrWaiting: Inc(Waited, POLL_MS);
      else
        Exit;
    end;
  until Terminated or (Waited >= AUTH_WAIT_MS);
  if Line = '' then
    Exit;
  if not ParseJSONObject(Line, Message, Err) then
    Exit;
  try
    Id := Message.Find('id');
    Params := nil;
    if Assigned(Message.Find('params')) and (Message.Find('params').JSONType = jtObject) then
      Params := Message.Objects['params'];
    Result := GetJSONString(Message, 'method', Method) and (Method = AUTOMATION_AUTH_METHOD) and Assigned(Params) and
      GetJSONString(Params, AUTOMATION_TOKEN_PARAM, Token) and SameToken(Token, FEndpoint.Token) and Assigned(Id);
    if Result then
      Lines.WriteLine(RpcResultResponse(Id, TJSONObject.Create(['authenticated', True])))
    else
      Lines.WriteLine(RpcErrorResponse(Id, RPC_REFUSED, rsAutomationNotAllowed));
  finally
    FreeAndNil(Message);
  end;
end;

procedure TAutomationListener.Serve(Lines: TSocketLines);
var
  Line, Reply: string;
begin
  while not Terminated and not FDropClient do
    case Lines.ReadLine(POLL_MS, AUTOMATION_LINE_LIMIT, Line) of
      lrLine:
        if Trim(Line) <> '' then
        begin
          Reply := Request(Line);
          if Reply <> '' then
            Lines.WriteLine(Reply);
        end;
      lrWaiting: ;
      else
        Exit;
    end;
end;

procedure TAutomationListener.CallRequest;
begin
  FReply := FOnRequest(FLine);
end;

procedure TAutomationListener.CallClient;
begin
  if Assigned(FOnClient) then
    FOnClient(FConnected);
end;

function TAutomationListener.Request(const Line: string): string;
begin
  FLine := Line;
  FReply := '';
  if FSynchronized then
    Synchronize(@CallRequest)
  else
    CallRequest;
  Result := FReply;
end;

procedure TAutomationListener.ClientChanged(Connected: boolean);
begin
  FConnected := Connected;
  if FSynchronized then
    Synchronize(@CallClient)
  else
    CallClient;
end;

end.
