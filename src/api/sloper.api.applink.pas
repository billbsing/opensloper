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

// The apps' link to each other. A window listens on an endpoint of its kind
// (Sloper.API.Endpoint), with the same private folder and token as the
// design window's automation socket, and the other apps send it a message:
// one JSON-RPC request, a method and its params, answered with whether the
// window did it. The design window's Publish… asks each publish window to
// come to the front if it shows the pattern's layout, and starts a new one
// only when none does. No LCL dependency.
unit Sloper.API.AppLink;

{$mode ObjFPC}{$H+}

interface

uses
  SysUtils, fpjson, Sloper.API.Listener;

const
  // A publish window showing the layout in params.layout comes to the front
  APP_LINK_SHOW = 'show';
  APP_LINK_LAYOUT_PARAM = 'layout';
  // The result: {"done": true} when the window did what was asked
  APP_LINK_DONE = 'done';

type
  // On the main thread in an app; True when this window did what was asked.
  // Params is never nil.
  TAppLinkEvent = function(const Method: string; Params: TJSONObject): boolean of object;

  // A window listening for the other apps
  TAppLink = class
  private
    FListener: TAutomationListener;
    FOnMessage: TAppLinkEvent;
    function HandleLine(const Line: string): string;
  public
    // Listening on an endpoint of Kind; nil with a message when it could not
    // start. Synchronized runs OnMessage on the main thread, as a window
    // needs; tests call it on the listener's thread.
    class function Start(const Kind: string; AOnMessage: TAppLinkEvent; Synchronized: boolean;
      out ErrorMessage: string): TAppLink;
    // Stops listening and removes the endpoint
    destructor Destroy; override;
    property Listener: TAutomationListener read FListener;
  end;

// Sends Method to each window of Kind listening, newest first, until one
// says it did it; False when none did, or none listens
function SendToApp(const Kind, Method: string; Params: TJSONObject): boolean;

resourcestring
  rsAppLinkNotRequest = 'The message must be a JSON-RPC 2.0 request with a method';

implementation

uses
  Sloper.Core.JSON, Sloper.API.Endpoint, Sloper.API.Rpc;

const
  // How long a window has to admit the sender, and to answer; ms. A window
  // answers between its own events, so a busy one may take a moment.
  REPLY_MS = 3000;
  REQUEST_ID = 1;

  {$IFDEF WINDOWS}
// Lets the window being asked come to the front, which Windows allows only a
// process the user is working in
function AllowSetForegroundWindow(ProcessId: longword): longbool; stdcall; external 'user32.dll';
  {$ENDIF}

class function TAppLink.Start(const Kind: string; AOnMessage: TAppLinkEvent; Synchronized: boolean;
  out ErrorMessage: string): TAppLink;
begin
  Result := TAppLink.Create;
  Result.FOnMessage := AOnMessage;
  Result.FListener := TAutomationListener.Start(@Result.HandleLine, nil, Synchronized, ErrorMessage, Kind);
  if not Assigned(Result.FListener) then
    FreeAndNil(Result);
end;

destructor TAppLink.Destroy;
begin
  FreeAndNil(FListener);
  inherited Destroy;
end;

function TAppLink.HandleLine(const Line: string): string;
var
  Request, Params: TJSONObject;
  Err, Method: string;
  Id: TJSONData;
  Done: boolean;
begin
  Result := '';
  if not ParseJSONObject(Line, Request, Err) then
    Exit(RpcErrorResponse(nil, RPC_PARSE_ERROR, Err));
  try
    Id := Request.Find('id');
    if not GetJSONString(Request, 'method', Method) then
      Exit(RpcErrorResponse(Id, RPC_INVALID_REQUEST, rsAppLinkNotRequest));
    Params := nil;
    if Assigned(Request.Find('params')) and (Request.Find('params').JSONType = jtObject) then
      Params := Request.Objects['params']
    else
    begin
      Params := TJSONObject.Create;
      Request.Add('params', Params);
    end;
    Done := Assigned(FOnMessage) and FOnMessage(Method, Params);
    if Assigned(Id) then
      Result := RpcResultResponse(Id, TJSONObject.Create([APP_LINK_DONE, Done]));
  finally
    FreeAndNil(Request);
  end;
end;

// Whether the window at Endpoint did what Request asks
function AskEndpoint(const Endpoint: TAutomationEndpoint; const Request: string): boolean;
var
  Lines: TSocketLines;
  Line, Err: string;
  Reply: TJSONObject;
  Answer: TJSONData;
begin
  Result := False;
  try
    Lines := TSocketLines.Create(ConnectAutomation(Endpoint));
  except
    // Nothing listens there: a window that closed without tidying up. A
    // window writes its file only once it listens, so it is not one starting.
    on Exception do
    begin
      RemoveAutomationEndpoint(Endpoint);
      Exit;
    end;
  end;
  try
    try
      if not AuthenticateAt(Lines, Endpoint, REPLY_MS) then
        Exit;
      {$IFDEF WINDOWS}
      AllowSetForegroundWindow(Endpoint.Pid);
      {$ENDIF}
      Lines.WriteLine(Request);
      if (Lines.ReadLine(REPLY_MS, AUTOMATION_AUTH_LINE_LIMIT, Line) = lrLine) and ParseJSONObject(Line, Reply, Err) then
      try
        Answer := Reply.Find('result');
        Result := (Answer is TJSONObject) and TJSONObject(Answer).Get(APP_LINK_DONE, False);
      finally
        FreeAndNil(Reply);
      end;
    except
      // The window went away mid-reply
      on Exception do
        Result := False;
    end;
  finally
    FreeAndNil(Lines);
  end;
end;

function SendToApp(const Kind, Method: string; Params: TJSONObject): boolean;
var
  Request: TJSONObject;
  Endpoint: TAutomationEndpoint;
begin
  Result := False;
  Request := TJSONObject.Create(['jsonrpc', '2.0', 'id', REQUEST_ID, 'method', Method, 'params', Params.Clone]);
  try
    for Endpoint in ReadAutomationEndpoints(Kind) do
      if AskEndpoint(Endpoint, Request.AsJSON) then
        Exit(True);
  finally
    FreeAndNil(Request);
  end;
end;

end.
