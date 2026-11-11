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

// The design window's automation mode without the window: the listener on a
// document, the token, the endpoint files, and the connection serve --connect
// uses, with the window's hooks (undo labels, writes, open, ui_state, a
// change in progress). The listener runs its handler on its own thread here;
// the test thread waits on the connection meanwhile, so only one touches the
// document at a time.
unit Sloper.Tests.Automation;

{$mode ObjFPC}{$H+}

interface

uses
  SysUtils, fpcunit, testregistry, fpjson, Sloper.Tests.TestCase, Sloper.Document.PatternDocument, Sloper.API.Server,
  Sloper.API.Listener, Sloper.API.Connection;

type
  TTestAutomation = class(TOSTestCase)
  private
    FFolder: string;
    FDocument: TPatternDocument;
    FApi: TApiServer;
    FListener: TAutomationListener;
    FConnection: TApiConnection;
    FClientEvents: string;
    FWriteAllowed: boolean;
    function Request(const Line: string): string;
    procedure ClientChanged(Connected: boolean);
    function ConfirmWrite(const Path: string): boolean;
    function WindowState: TJSONObject;
    procedure Listen;
    // The method's result as JSON, or its error code as "error <code>"
    function Call(const Method: string; const Params: string = '{}'): string;
    // Waits for the listener's thread to report the client
    procedure WaitForEvents(const Expected: string);
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestTokens;
    procedure TestEndpointIsPrivate;
    procedure TestCallsReachTheDocument;
    procedure TestChangesAreLabelled;
    procedure TestWrongTokenRefused;
    procedure TestNoWindow;
    procedure TestReconnectsAfterDrop;
    procedure TestNotificationPassesThrough;
    procedure TestMcpThroughConnection;
    procedure TestBusyWhileUserEdits;
    procedure TestWritesAsked;
    procedure TestOpenRefusedInWindow;
    procedure TestWindowState;
    procedure TestEndpointRemovedOnStop;
    procedure TestLongSocketPathRefused;
  end;

implementation

uses
  Classes, ssockets, {$IFDEF UNIX} BaseUnix, {$ENDIF} Sloper.Core.JSON, Sloper.Core.Version, Sloper.API.Endpoint, Sloper.API.MCP;

const
  CLAUDE_PREFIX = 'Claude: ';
  EVENT_WAIT_MS = 3000;
  EVENT_STEP_MS = 10;

procedure TTestAutomation.SetUp;
begin
  FFolder := ConcatPaths([GetTempDir, 'opensloper-automation-test']);
  UseAutomationFolder(FFolder);
  FDocument := TPatternDocument.Create;
  FApi := TApiServer.CreateFor(FDocument);
  FApi.ChangePrefix := CLAUDE_PREFIX;
  FApi.OpensFiles := False;
  FApi.OnConfirmWrite := @ConfirmWrite;
  FWriteAllowed := True;
  FClientEvents := '';
  FListener := nil;
  FConnection := TApiConnection.Create;
end;

procedure TTestAutomation.TearDown;
begin
  FreeAndNil(FConnection);
  FreeAndNil(FListener);
  FreeAndNil(FApi);
  FreeAndNil(FDocument);
  UseAutomationFolder('');
  RemoveDir(FFolder);
end;

function TTestAutomation.Request(const Line: string): string;
begin
  Result := FApi.HandleLine(Line);
end;

procedure TTestAutomation.ClientChanged(Connected: boolean);
begin
  if Connected then
    FClientEvents := FClientEvents + '+'
  else
    FClientEvents := FClientEvents + '-';
end;

function TTestAutomation.ConfirmWrite(const Path: string): boolean;
begin
  Result := FWriteAllowed;
end;

function TTestAutomation.WindowState: TJSONObject;
begin
  Result := TJSONObject.Create(['selection', TJSONArray.Create]);
end;

procedure TTestAutomation.Listen;
var
  Err: string;
begin
  FListener := TAutomationListener.Start(@Request, @ClientChanged, False, Err);
  AssertTrue(Err, Assigned(FListener));
end;

function TTestAutomation.Call(const Method, Params: string): string;
var
  Data: TJSONData;
  Err: string;
  ParamObject: TJSONObject;
begin
  AssertTrue(Err, ParseJSONObject(Params, ParamObject, Err));
  try
    try
      Data := FConnection.CallMethod(Method, ParamObject);
      try
        Result := Data.AsJSON;
      finally
        FreeAndNil(Data);
      end;
    except
      on Failure: EApiError do
        Result := 'error ' + IntToStr(Failure.Code) + ': ' + Failure.Message;
    end;
  finally
    FreeAndNil(ParamObject);
  end;
end;

procedure TTestAutomation.WaitForEvents(const Expected: string);
var
  Waited: integer;
begin
  Waited := 0;
  while (FClientEvents <> Expected) and (Waited < EVENT_WAIT_MS) do
  begin
    Sleep(EVENT_STEP_MS);
    Inc(Waited, EVENT_STEP_MS);
  end;
  AssertEquals('client events', Expected, FClientEvents);
end;

procedure TTestAutomation.TestTokens;
var
  First, Second, Err: string;
  Index: integer;
begin
  AssertTrue(Err, NewAutomationToken(First, Err));
  AssertTrue(Err, NewAutomationToken(Second, Err));
  AssertEquals('32 bytes as hex', 64, Length(First));
  for Index := 1 to Length(First) do
    AssertTrue('hex', First[Index] in ['0' .. '9', 'a' .. 'f']);
  AssertFalse('new each time', First = Second);
  AssertTrue(SameToken(First, First));
  AssertFalse(SameToken(First, Second));
  AssertFalse('length differs', SameToken(First, Copy(First, 1, 63)));
  AssertFalse('empty never matches', SameToken('', ''));
end;

procedure TTestAutomation.TestEndpointIsPrivate;
var
  Endpoints: TAutomationEndpointArray;
  {$IFDEF UNIX}
  Info: TStat;
  {$ENDIF}
begin
  Listen;
  Endpoints := ReadAutomationEndpoints;
  AssertEquals('one window', 1, Length(Endpoints));
  AssertEquals('this process', integer(GetProcessID), Endpoints[0].Pid);
  AssertEquals('its token', FListener.Endpoint.Token, Endpoints[0].Token);
  {$IFDEF UNIX}
  AssertEquals(0, fpStat(FFolder, Info));
  AssertEquals('folder closed to others', 0, Info.st_mode and &077);
  AssertEquals(0, fpStat(Endpoints[0].InfoPath, Info));
  AssertEquals('token file the user''s only', &600, Info.st_mode and &777);
  AssertEquals(0, fpStat(Endpoints[0].SocketPath, Info));
  AssertEquals('socket the user''s only', 0, Info.st_mode and &077);
  {$ENDIF}
end;

procedure TTestAutomation.TestCallsReachTheDocument;
begin
  Listen;
  AssertTrue(Call('add_variable', '{"name": "ease", "formula": "12"}'), Pos('"ease"', Call('get_object', '{"name": "ease"}')) > 0);
  AssertTrue('an undo step in the window''s document', FDocument.CanUndo);
  FDocument.Undo;
  AssertTrue('gone with it', Call('get_object', '{"name": "ease"}').StartsWith('error'));
  WaitForEvents('+');
end;

procedure TTestAutomation.TestChangesAreLabelled;
begin
  Listen;
  Call('add_variable', '{"name": "ease", "formula": "12"}');
  AssertTrue(FDocument.UndoDescription, FDocument.UndoDescription.StartsWith(CLAUDE_PREFIX));
end;

procedure TTestAutomation.TestWrongTokenRefused;
var
  Endpoint: TAutomationEndpoint;
  Lines: TSocketLines;
  Line: string;
begin
  Listen;
  Endpoint := FListener.Endpoint;
  Lines := TSocketLines.Create(ConnectAutomation(Endpoint));
  try
    Lines.WriteLine('{"jsonrpc": "2.0", "id": 1, "method": "authenticate", "params": {"token": "' + StringOfChar('0', 64) + '"}}');
    AssertEquals(Ord(lrLine), Ord(Lines.ReadLine(EVENT_WAIT_MS, AUTOMATION_LINE_LIMIT, Line)));
    AssertTrue('refused: ' + Line, Pos(IntToStr(RPC_REFUSED), Line) > 0);
    // And the window closes the connection
    AssertEquals('closed', Ord(lrClosed), Ord(Lines.ReadLine(EVENT_WAIT_MS, AUTOMATION_LINE_LIMIT, Line)));
  finally
    FreeAndNil(Lines);
  end;
  AssertEquals('never admitted', '', FClientEvents);
  // A request that is not authenticate first is refused too
  Lines := TSocketLines.Create(ConnectAutomation(Endpoint));
  try
    Lines.WriteLine('{"jsonrpc": "2.0", "id": 1, "method": "list_objects"}');
    AssertEquals(Ord(lrLine), Ord(Lines.ReadLine(EVENT_WAIT_MS, AUTOMATION_LINE_LIMIT, Line)));
    AssertTrue('refused: ' + Line, Pos(IntToStr(RPC_REFUSED), Line) > 0);
  finally
    FreeAndNil(Lines);
  end;
end;

procedure TTestAutomation.TestNoWindow;
begin
  AssertTrue(Call('list_objects').StartsWith('error ' + IntToStr(RPC_REFUSED)));
  AssertFalse(FConnection.Connected);
end;

procedure TTestAutomation.TestReconnectsAfterDrop;
begin
  Listen;
  AssertFalse(Call('list_objects').StartsWith('error'));
  WaitForEvents('+');
  FListener.Disconnect;
  WaitForEvents('+-');
  AssertTrue('the call that finds it gone fails', Call('list_objects').StartsWith('error'));
  AssertFalse('and the next connects again', Call('list_objects').StartsWith('error'));
  WaitForEvents('+-+');
end;

procedure TTestAutomation.TestNotificationPassesThrough;
begin
  Listen;
  AssertEquals('no reply waited for', '', FConnection.HandleLine('{"jsonrpc": "2.0", "method": "evaluate"}'));
  AssertTrue(Pos('"result"', FConnection.HandleLine('{"jsonrpc": "2.0", "id": 4, "method": "evaluate"}')) > 0);
end;

procedure TTestAutomation.TestMcpThroughConnection;
var
  Mcp: TMcpServer;
  Reply: string;
begin
  Listen;
  Mcp := TMcpServer.CreateFor(FConnection);
  FConnection := nil;
  try
    Reply := Mcp.HandleLine('{"jsonrpc": "2.0", "id": 1, "method": "tools/call", "params": {"name": "add_variable", ' +
      '"arguments": {"name": "ease", "formula": "5"}}}');
    AssertTrue(Reply, Pos('"isError"', Reply) = 0);
    AssertTrue(FDocument.UndoDescription.StartsWith(CLAUDE_PREFIX));
    // The handshake is answered here, without the window
    AssertTrue(Pos(APP_NAME_LOWER, Mcp.HandleLine('{"jsonrpc": "2.0", "id": 2, "method": "initialize", "params": {}}')) > 0);
  finally
    FreeAndNil(Mcp);
  end;
end;

procedure TTestAutomation.TestBusyWhileUserEdits;
begin
  Listen;
  Call('add_variable', '{"name": "ease", "formula": "12"}');
  FDocument.BeginChange('Drag');
  try
    AssertTrue('edits wait', Call('set_formula', '{"name": "ease", "field": "formula", "formula": "3"}').StartsWith(
      'error ' + IntToStr(RPC_REFUSED)));
    AssertTrue('so does saving', Call('save', '{"path": "x.sloper"}').StartsWith('error ' + IntToStr(RPC_REFUSED)));
    AssertFalse('reading does not', Call('get_object', '{"name": "ease"}').StartsWith('error'));
    AssertTrue('the user''s change is still open', FDocument.ChangeOpen);
  finally
    FDocument.CancelChange;
  end;
end;

procedure TTestAutomation.TestWritesAsked;
var
  Path: string;
begin
  Listen;
  Path := ConcatPaths([FFolder, 'claude.sloper']);
  FWriteAllowed := False;
  AssertTrue('declined', Call('save', '{"path": "' + StringReplace(Path, '\', '\\', [rfReplaceAll]) + '"}').StartsWith('error'));
  AssertFalse(FileExists(Path));
  FWriteAllowed := True;
  AssertFalse('allowed', Call('save', '{"path": "' + StringReplace(Path, '\', '\\', [rfReplaceAll]) + '"}').StartsWith('error'));
  AssertTrue(FileExists(Path));
  DeleteFile(Path);
end;

procedure TTestAutomation.TestOpenRefusedInWindow;
begin
  Listen;
  AssertTrue(Call('open', '{"path": "anything.sloper"}').StartsWith('error ' + IntToStr(RPC_REFUSED)));
end;

procedure TTestAutomation.TestWindowState;
begin
  Listen;
  AssertTrue('without the window', Call('ui_state').StartsWith('error ' + IntToStr(RPC_REFUSED)));
  FApi.OnWindowState := @WindowState;
  AssertEquals('{ "selection" : [] }', Call('ui_state'));
end;

procedure TTestAutomation.TestEndpointRemovedOnStop;
var
  Endpoint: TAutomationEndpoint;
begin
  Listen;
  Call('list_objects');
  Endpoint := FListener.Endpoint;
  FreeAndNil(FListener);
  AssertFalse('endpoint file', FileExists(Endpoint.InfoPath));
  {$IFDEF UNIX}
  AssertFalse('socket', FileExists(Endpoint.SocketPath));
  {$ENDIF}
  AssertEquals(0, Length(ReadAutomationEndpoints));
  AssertTrue('the connection finds it gone', Call('list_objects').StartsWith('error'));
end;

// A run folder too deep for a socket is reported, not a crash
procedure TTestAutomation.TestLongSocketPathRefused;
var
  Deep, Err: string;
begin
  {$IFDEF UNIX}
  Deep := ConcatPaths([FFolder, StringOfChar('d', 120)]);
  UseAutomationFolder(Deep);
  try
    FListener := TAutomationListener.Start(@Request, @ClientChanged, False, Err);
    AssertFalse('not started', Assigned(FListener));
    AssertTrue(Err, Pos('too long', Err) > 0);
  finally
    UseAutomationFolder(FFolder);
    RemoveDir(Deep);
  end;
  {$ENDIF}
end;

initialization
  RegisterTest(TTestAutomation);
end.
