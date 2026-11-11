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

// The Automation API as an MCP server: the handshake, the tool list made from
// the methods table, and tool calls, with plain API requests still answered.
unit Sloper.Tests.MCP;

{$mode ObjFPC}{$H+}

interface

uses
  fpcunit, testregistry, fpjson, Sloper.Tests.TestCase, Sloper.API.MCP;

type
  TTestMCP = class(TOSTestCase)
  private
    FServer: TMcpServer;
    FReply: TJSONObject;
    procedure Send(const Method: string; const Params: string = '{}');
    function Answer: TJSONObject;
    function ErrorCode: integer;
    function FindTool(const ToolName: string): TJSONObject;
    // Calls a tool and gives the text it answered with
    function CallTool(const ToolName, Arguments: string; out IsError: boolean): string;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestInitializeAgreesOnVersion;
    procedure TestNotificationsGetNoReply;
    procedure TestPing;
    procedure TestEveryMethodIsATool;
    procedure TestToolSchemas;
    procedure TestTypeMembersDescribed;
    procedure TestReadOnlyHint;
    procedure TestToolCall;
    procedure TestRefusalIsToolError;
    procedure TestUnknownTool;
    procedure TestRenderGivesSvgText;
    procedure TestApiRequestsStillAnswered;
  end;

implementation

uses
  SysUtils, Sloper.Core.JSON, Sloper.Core.Version, Sloper.API.Server, Sloper.API.Methods;

procedure TTestMCP.SetUp;
begin
  FServer := TMcpServer.Create;
  FReply := nil;
end;

procedure TTestMCP.TearDown;
begin
  FreeAndNil(FReply);
  FreeAndNil(FServer);
end;

procedure TTestMCP.Send(const Method, Params: string);
var
  Err, Reply: string;
begin
  FreeAndNil(FReply);
  Reply := FServer.HandleLine('{"jsonrpc": "2.0", "id": 7, "method": "' + Method + '", "params": ' + Params + '}');
  if not ParseJSONObject(Reply, FReply, Err) then
    Fail(Err + ': ' + Reply);
  AssertEquals('id echoed', 7, FReply.Get('id', 0));
end;

function TTestMCP.Answer: TJSONObject;
begin
  if not Assigned(FReply.Find('result')) then
    Fail('Expected a result: ' + FReply.AsJSON);
  Result := FReply.Objects['result'];
end;

function TTestMCP.ErrorCode: integer;
begin
  if not Assigned(FReply.Find('error')) then
    Fail('Expected an error: ' + FReply.AsJSON);
  Result := FReply.Objects['error'].Get('code', 0);
end;

function TTestMCP.FindTool(const ToolName: string): TJSONObject;
var
  Tools: TJSONArray;
  Index: integer;
begin
  Send('tools/list');
  Tools := Answer.Arrays['tools'];
  for Index := 0 to Tools.Count - 1 do
    if Tools.Objects[Index].Get('name', '') = ToolName then
      Exit(Tools.Objects[Index]);
  Fail('No tool ' + ToolName);
  Result := nil;
end;

function TTestMCP.CallTool(const ToolName, Arguments: string; out IsError: boolean): string;
var
  Content: TJSONArray;
begin
  Send('tools/call', '{"name": "' + ToolName + '", "arguments": ' + Arguments + '}');
  IsError := Answer.Get('isError', False);
  Content := Answer.Arrays['content'];
  AssertEquals('one content item', 1, Content.Count);
  AssertEquals('text', 'text', Content.Objects[0].Get('type', ''));
  Result := Content.Objects[0].Get('text', '');
end;

procedure TTestMCP.TestInitializeAgreesOnVersion;
begin
  Send('initialize', '{"protocolVersion": "2025-06-18", "capabilities": {}, "clientInfo": {"name": "test", "version": "1"}}');
  AssertEquals('the client''s, which it knows', '2025-06-18', Answer.Get('protocolVersion', ''));
  AssertEquals(APP_NAME_LOWER, Answer.Objects['serverInfo'].Get('name', ''));
  AssertEquals(APP_VERSION, Answer.Objects['serverInfo'].Get('version', ''));
  AssertTrue('offers tools', Assigned(Answer.Objects['capabilities'].Find('tools')));
  AssertTrue('instructions', Answer.Get('instructions', '') <> '');
  Send('initialize', '{"protocolVersion": "1999-01-01"}');
  AssertEquals('its newest for one it does not know', '2025-11-25', Answer.Get('protocolVersion', ''));
end;

procedure TTestMCP.TestNotificationsGetNoReply;
begin
  AssertEquals('', FServer.HandleLine('{"jsonrpc": "2.0", "method": "notifications/initialized"}'));
  AssertEquals('', FServer.HandleLine('{"jsonrpc": "2.0", "method": "notifications/cancelled", "params": {"requestId": 3}}'));
end;

procedure TTestMCP.TestPing;
begin
  Send('ping');
  AssertEquals(0, Answer.Count);
end;

procedure TTestMCP.TestEveryMethodIsATool;
var
  Method: TApiMethod;
  Tools: TJSONArray;
  Index: integer;
begin
  Send('tools/list');
  Tools := Answer.Arrays['tools'];
  AssertEquals(Length(ApiMethods), Tools.Count);
  Index := 0;
  for Method in ApiMethods do
  begin
    AssertEquals('in the table''s order', Method.Name, Tools.Objects[Index].Get('name', ''));
    AssertTrue(Method.Name + ' has a description', Tools.Objects[Index].Get('description', '') <> '');
    Inc(Index);
  end;
end;

procedure TTestMCP.TestToolSchemas;
var
  Schema, Properties, Axis, Marks: TJSONObject;
begin
  Schema := FindTool('open').Objects['inputSchema'];
  AssertEquals('object', Schema.Get('type', ''));
  AssertEquals('path required', '["path"]', Schema.Arrays['required'].AsJSON);
  AssertEquals('string', Schema.Objects['properties'].Objects['path'].Get('type', ''));
  // A target is "id" or "name", so neither is required
  Schema := FindTool('rename').Objects['inputSchema'];
  Properties := Schema.Objects['properties'];
  AssertEquals('integer', Properties.Objects['id'].Get('type', ''));
  AssertEquals('string', Properties.Objects['name'].Get('type', ''));
  AssertEquals('["newName"]', Schema.Arrays['required'].AsJSON);
  // Choices, groups and lists
  Properties := FindTool('add_transform').Objects['inputSchema'].Objects['properties'];
  AssertEquals('["rotate", "mirror", "move"]', Properties.Objects['type'].Arrays['enum'].AsJSON);
  Axis := Properties.Objects['axis'];
  AssertEquals('object', Axis.Get('type', ''));
  AssertTrue('axis.edge', Assigned(Axis.Objects['properties'].Find('edge')));
  Marks := FindTool('convert_units').Objects['inputSchema'].Objects['properties'].Objects['marks'];
  AssertEquals('array', Marks.Get('type', ''));
  AssertTrue('marks[].token', Assigned(Marks.Objects['items'].Objects['properties'].Find('token')));
  AssertTrue('marks[] by id', Assigned(Marks.Objects['items'].Objects['properties'].Find('id')));
  AssertEquals('formula as text or number', '["string", "number"]',
    FindTool('add_variable').Objects['inputSchema'].Objects['properties'].Objects['formula'].Arrays['type'].AsJSON);
end;

procedure TTestMCP.TestTypeMembersDescribed;
var
  Text: string;
begin
  Text := FindTool('add_point').Get('description', '');
  AssertTrue('offsetPoint members: ' + Text, Pos('offsetPoint: base, mode (polar | cartesian)', Text) > 0);
  AssertEquals('no Markdown links', 0, Pos('](', Text));
  Text := FindTool('add_edge').Get('description', '');
  AssertTrue('curve path nodes: ' + Text, Pos('nodes (a list, each with point, angle, lengthIn, lengthOut)', Text) > 0);
end;

procedure TTestMCP.TestReadOnlyHint;
begin
  AssertTrue('list_objects', FindTool('list_objects').Objects['annotations'].Get('readOnlyHint', False));
  AssertFalse('set_formula', FindTool('set_formula').Objects['annotations'].Get('readOnlyHint', True));
  AssertFalse('save', FindTool('save').Objects['annotations'].Get('readOnlyHint', True));
end;

procedure TTestMCP.TestToolCall;
var
  IsError: boolean;
  Text, Err: string;
  Item: TJSONObject;
begin
  CallTool('add_variable', '{"name": "ease", "formula": 12}', IsError);
  AssertFalse(IsError);
  Text := CallTool('get_object', '{"name": "ease"}', IsError);
  AssertFalse(IsError);
  AssertTrue(Err, ParseJSONObject(Text, Item, Err));
  try
    AssertEquals('ease', Item.Get('name', ''));
  finally
    FreeAndNil(Item);
  end;
  AssertTrue('an undo step', FServer.Api.Document.CanUndo);
  FServer.Api.Document.Undo;
  AssertFalse('only one', FServer.Api.Document.CanUndo);
end;

procedure TTestMCP.TestRefusalIsToolError;
var
  IsError: boolean;
  Text, Err: string;
  Error: TJSONObject;
begin
  Text := CallTool('add_variable', '{"name": "bad", "formula": "1 +"}', IsError);
  AssertTrue('isError', IsError);
  AssertTrue(Err, ParseJSONObject(Text, Error, Err));
  try
    AssertEquals(RPC_REFUSED, Error.Get('code', 0));
    AssertTrue('message', Error.Get('message', '') <> '');
    AssertEquals('formula', Error.Objects['data'].Get('field', ''));
  finally
    FreeAndNil(Error);
  end;
end;

procedure TTestMCP.TestUnknownTool;
begin
  Send('tools/call', '{"name": "format_disk", "arguments": {}}');
  AssertEquals(RPC_INVALID_PARAMS, ErrorCode);
  Send('tools/call', '{"name": "evaluate", "arguments": 3}');
  AssertEquals(RPC_INVALID_PARAMS, ErrorCode);
end;

procedure TTestMCP.TestRenderGivesSvgText;
var
  IsError: boolean;
  Text: string;
begin
  CallTool('add_point', '{"type": "freePoint", "name": "A", "x": "10", "y": "20"}', IsError);
  AssertFalse(IsError);
  Text := CallTool('render', '{}', IsError);
  AssertFalse(IsError);
  AssertTrue('the SVG itself, not JSON: ' + Copy(Text, 1, 80), (Pos('<svg', Text) > 0) and (Pos('<svg', Text) < 100));
end;

procedure TTestMCP.TestApiRequestsStillAnswered;
begin
  Send('add_variable', '{"name": "ease", "formula": "5"}');
  AssertEquals('ease', Answer.Get('name', ''));
  Send('no_such_method');
  AssertEquals(RPC_METHOD_NOT_FOUND, ErrorCode);
  FreeAndNil(FReply);
  AssertTrue('parse errors too', Pos(IntToStr(RPC_PARSE_ERROR), FServer.HandleLine('{nope')) > 0);
end;

initialization
  RegisterTest(TTestMCP);
end.
