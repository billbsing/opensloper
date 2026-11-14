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

// The Automation API as a Model Context Protocol server. MCP is JSON-RPC 2.0
// one message a line, so this answers its handshake and lists the methods
// table as tools, each called through the API server; any other method goes
// to the API server as it is, so one connection serves both scripts and MCP
// clients such as Claude Code and Claude Desktop. No LCL dependency.
unit Sloper.API.MCP;

{$mode ObjFPC}{$H+}

interface

uses
  SysUtils, fpjson, Sloper.API.Server, Sloper.API.Rpc;

type
  TMcpServer = class
  private
    FBackend: TApiBackend;
    FApi: TApiServer;
    function Initialize(Params: TJSONObject): TJSONObject;
    function CallTool(Params: TJSONObject): TJSONObject;
    // The reply to an MCP method, or nil when Method is not one
    function CallMcp(const Method: string; Params: TJSONObject; out Handled: boolean): TJSONData;
  public
    // On a document of its own
    constructor Create;
    // Calling Backend, such as a connection to the design window; it is freed
    // with the server
    constructor CreateFor(ABackend: TApiBackend);
    destructor Destroy; override;
    // The response to one line, on one line; '' for a notification
    function HandleLine(const Line: string): string;
    // The local server, or nil when calling another backend
    property Api: TApiServer read FApi;
  end;

// Every API method as an MCP tool, with a JSON Schema of its parameters
function McpTools: TJSONArray;

type
  // What a tool's reply is sent as: render's PNG as an image; its SVG, or
  // any other reply as JSON, as text
  TToolOutputKind = (tokImage, tokText);

// How a method's Output goes back to a model, here and in the assistant:
// Text is the PNG's base64 for an image
procedure ReadToolOutput(Output: TJSONData; out Kind: TToolOutputKind; out Text: string);
// A failed call as the API's error (code, message, and field and position
// when known), so the model reads why; any other exception is an internal error
function FailureText(Failure: Exception): string;

const
  TOOL_IMAGE_MIME_TYPE = 'image/png';

resourcestring
  rsMcpInstructions = 'OpenSloper drafts sewing patterns from formulas. Open a pattern with open, or build one from the ' +
    'empty pattern the server starts with, then save it. Objects are given by id or by name. Formulas are in the ' +
    'pattern''s unit; positions and lengths in answers are always mm. Every change is one undo step. Use render to look ' +
    'at the draft and evaluate to list its problems.';
  rsMcpReturns = 'Returns: %s.';
  rsMcpTargetBy = '%s: give "id" or "name".';
  rsMcpMembers = 'Members of each type: %s';
  rsMcpListOf = 'a list, each with %s';
  rsMcpNoTool = 'There is no tool "%s"';

implementation

uses
  StrUtils, Sloper.Core.JSON, Sloper.Core.OperationInfo, Sloper.Core.Version, Sloper.API.Methods;

const
  // Newest first; a client asking for another is answered with the newest
  MCP_PROTOCOL_VERSIONS: array[0..3] of string = ('2025-11-25', '2025-06-18', '2025-03-26', '2024-11-05');
  MCP_NOTIFICATION_PREFIX = 'notifications/';
  TYPE_PARAM = 'type';
  // The render reply members sent as content of their own, not inside JSON
  SVG_MEMBER = 'svg';
  PNG_MEMBER = 'png';

// Markdown links become their text: an MCP client has no reference pages
function PlainText(const Text: string): string;
var
  Start, Middle, Finish: integer;
begin
  Result := Text;
  Start := Pos('[', Result);
  while Start > 0 do
  begin
    Middle := PosEx('](', Result, Start);
    Finish := PosEx(')', Result, Middle);
    if (Middle = 0) or (Finish = 0) then
      Break;
    Result := Copy(Result, 1, Start - 1) + Copy(Result, Start + 1, Middle - Start - 1) + Copy(Result, Finish + 1, MaxInt);
    Start := PosEx('[', Result, Start);
  end;
end;

function ChoiceArray(const Choices: string): TJSONArray;
var
  Choice: string;
begin
  Result := TJSONArray.Create;
  for Choice in SplitString(Choices, ',') do
    if Trim(Choice) <> '' then
      Result.Add(Trim(Choice));
end;

function IdOrName: TJSONArray;
begin
  Result := TJSONArray.Create(['integer', 'string']);
end;

// A member directly under Prefix: under 'axis.', axis.edge but not axis.x.y
function IsChildOf(const Param: TApiParam; const Prefix: string): boolean;
var
  Rest: string;
begin
  if (Param.Kind = apMembers) or not Param.Name.StartsWith(Prefix) then
    Exit(False);
  Rest := Copy(Param.Name, Length(Prefix) + 1, MaxInt);
  Result := (Rest <> '') and (Pos('.', Rest) = 0) and (Pos('[', Rest) = 0);
end;

procedure AddObjectSchema(Into: TJSONObject; const Method: TApiMethod; const Prefix: string); forward;

function ParamSchema(const Method: TApiMethod; const Param: TApiParam): TJSONObject;
begin
  Result := TJSONObject.Create(['description', PlainText(Param.Description)]);
  case Param.Kind of
    apText: Result.Add('type', 'string');
    apNumber: Result.Add('type', 'number');
    apWhole: Result.Add('type', 'integer');
    apFlag: Result.Add('type', 'boolean');
    apFormula: Result.Add('type', TJSONArray.Create(['string', 'number']));
    apTarget, apReference, apMaterial: Result.Add('type', IdOrName);
    apReferences: Result.Add('items', TJSONObject.Create(['type', IdOrName]));
    apChoice: Result.Add('enum', ChoiceArray(Param.Choices));
    apNames: Result.Add('items', TJSONObject.Create(['enum', ChoiceArray(Param.Choices)]));
    apList: Result.Add('items', TJSONObject.Create);
    apGroup: AddObjectSchema(Result, Method, Param.Name + '.');
  end;
  case Param.Kind of
    apChoice: Result.Add('type', 'string');
    apReferences, apNames, apList: Result.Add('type', 'array');
  end;
  if Param.Kind = apList then
    AddObjectSchema(Result.Objects['items'], Method, Param.Name + '[].');
end;

// The parameters directly under Prefix; a target is "id" or "name", so both
// are listed and neither is required
procedure AddObjectSchema(Into: TJSONObject; const Method: TApiMethod; const Prefix: string);
var
  Properties: TJSONObject;
  Required: TJSONArray;
  Param: TApiParam;
  LocalName, Described: string;
begin
  Into.Add('type', 'object');
  Properties := TJSONObject.Create;
  Into.Add('properties', Properties);
  Required := TJSONArray.Create;
  for Param in Method.Params do
    if IsChildOf(Param, Prefix) then
    begin
      LocalName := Copy(Param.Name, Length(Prefix) + 1, MaxInt);
      if Param.Kind = apTarget then
      begin
        Described := Format(rsMcpTargetBy, [PlainText(Param.Description)]);
        Properties.Add('id', TJSONObject.Create(['type', 'integer', 'description', Described]));
        if Properties.IndexOfName('name') < 0 then
          Properties.Add('name', TJSONObject.Create(['type', 'string', 'description', Described]));
        Continue;
      end;
      if Properties.IndexOfName(LocalName) >= 0 then
        Properties.Delete(LocalName);
      Properties.Add(LocalName, ParamSchema(Method, Param));
      if Param.Required then
        Required.Add(LocalName);
    end;
  if Required.Count > 0 then
    Into.Add('required', Required)
  else
    FreeAndNil(Required);
end;

// One type's members as add_point and add_edge take them: x, y; or
// nodes (a list, each with point, angle)
function TypeMembersText(const Info: TOperationInfo): string;
var
  Member, Child: TOperationMember;
  Children, Part: string;
begin
  Result := '';
  for Member in Info.Members do
  begin
    if Pos('.', Member.Name) > 0 then
      Continue;
    Part := Member.Name;
    if Member.Kind = mkChoice then
      Part := Part + ' (' + StringReplace(Member.Choices, ', ', ' | ', [rfReplaceAll]) + ')'
    else if Member.Kind in [mkList, mkGroup] then
    begin
      Children := '';
      for Child in Info.Members do
        if Child.Name.StartsWith(Member.Name + '[].') or Child.Name.StartsWith(Member.Name + '.') then
          Children := Children + IfThen(Children <> '', ', ') + Copy(Child.Name, Pos('.', Child.Name) + 1, MaxInt);
      Part := Part + ' (' + Format(rsMcpListOf, [Children]) + ')';
    end;
    Result := Result + IfThen(Result <> '', ', ') + Part;
  end;
end;

// The members of each type the method's "type" parameter takes
function MembersText(const Method: TApiMethod): string;
var
  Param: TApiParam;
  Info: TOperationInfo;
  Choice, Types: string;
begin
  Types := '';
  for Param in Method.Params do
    if Param.Name = TYPE_PARAM then
      for Choice in SplitString(Param.Choices, ',') do
        if FindOperationInfo(Trim(Choice), Info) then
          Types := Types + IfThen(Types <> '', '; ') + Trim(Choice) + ': ' + TypeMembersText(Info);
  Result := Format(rsMcpMembers, [Types]);
end;

function ToolDescription(const Method: TApiMethod): string;
var
  Param: TApiParam;
begin
  Result := PlainText(Method.Summary);
  for Param in Method.Params do
    if Param.Kind = apMembers then
      Result := Result + ' ' + PlainText(Param.Description) + '. ' + MembersText(Method) + '.';
  Result := Result + ' ' + Format(rsMcpReturns, [PlainText(Method.Returns)]);
end;

function McpTools: TJSONArray;
var
  Method: TApiMethod;
  Tool, Schema: TJSONObject;
begin
  Result := TJSONArray.Create;
  for Method in ApiMethods do
  begin
    Tool := TJSONObject.Create(['name', Method.Name, 'description', ToolDescription(Method)]);
    Result.Add(Tool);
    Schema := TJSONObject.Create;
    Tool.Add('inputSchema', Schema);
    AddObjectSchema(Schema, Method, '');
    Tool.Add('annotations', TJSONObject.Create(['readOnlyHint', Method.ReadOnly]));
  end;
end;

// What an MCP client shows the model: a PNG as an image, so the model sees
// the draft; the SVG as it is; anything else as JSON
procedure ReadToolOutput(Output: TJSONData; out Kind: TToolOutputKind; out Text: string);
var
  Member: TJSONData;
begin
  Kind := tokText;
  Text := Output.AsJSON;
  if Output.JSONType <> jtObject then
    Exit;
  Member := TJSONObject(Output).Find(PNG_MEMBER);
  if Assigned(Member) and (Member.JSONType = jtString) then
  begin
    Kind := tokImage;
    Text := Member.AsString;
    Exit;
  end;
  Member := TJSONObject(Output).Find(SVG_MEMBER);
  if Assigned(Member) and (Member.JSONType = jtString) then
    Text := Member.AsString;
end;

function ToolResult(Output: TJSONData): TJSONObject;
var
  Kind: TToolOutputKind;
  Text: string;
  Item: TJSONObject;
begin
  ReadToolOutput(Output, Kind, Text);
  if Kind = tokImage then
    Item := TJSONObject.Create(['type', 'image', 'data', Text, 'mimeType', TOOL_IMAGE_MIME_TYPE])
  else
    Item := TJSONObject.Create(['type', 'text', 'text', Text]);
  Result := TJSONObject.Create(['content', TJSONArray.Create([Item])]);
end;

function ErrorResult(const Text: string): TJSONObject;
begin
  Result := TJSONObject.Create(['content', TJSONArray.Create([TJSONObject.Create(['type', 'text', 'text', Text])]), 'isError', True]);
end;

// A refusal as the API gives it, so the model reads the code, field and position
function RefusalText(Code: integer; const AMessage, FieldName: string; APosition: integer): string;
var
  Error: TJSONObject;
begin
  Error := TJSONObject.Create(['code', Code, 'message', AMessage]);
  try
    if (FieldName <> '') or (APosition > 0) then
      Error.Add('data', TJSONObject.Create(['field', FieldName, 'position', APosition]));
    Result := Error.AsJSON;
  finally
    FreeAndNil(Error);
  end;
end;

function FailureText(Failure: Exception): string;
begin
  if Failure is EApiError then
    Result := RefusalText(EApiError(Failure).Code, Failure.Message, EApiError(Failure).FieldName, EApiError(Failure).Position)
  else
    Result := RefusalText(RPC_INTERNAL_ERROR, Failure.Message, '', 0);
end;

constructor TMcpServer.Create;
begin
  inherited Create;
  FApi := TApiServer.Create;
  FBackend := FApi;
end;

constructor TMcpServer.CreateFor(ABackend: TApiBackend);
begin
  inherited Create;
  FBackend := ABackend;
  FApi := nil;
end;

destructor TMcpServer.Destroy;
begin
  FreeAndNil(FBackend);
  FApi := nil;
  inherited Destroy;
end;

function TMcpServer.Initialize(Params: TJSONObject): TJSONObject;
var
  Asked, Version, Candidate: string;
begin
  Version := MCP_PROTOCOL_VERSIONS[0];
  if GetJSONString(Params, 'protocolVersion', Asked) then
    for Candidate in MCP_PROTOCOL_VERSIONS do
      if Candidate = Asked then
        Version := Asked;
  Result := TJSONObject.Create(['protocolVersion', Version, 'capabilities',
    TJSONObject.Create(['tools', TJSONObject.Create(['listChanged', False])]), 'serverInfo',
    TJSONObject.Create(['name', APP_NAME_LOWER, 'title', APP_NAME, 'version', APP_VERSION]), 'instructions', rsMcpInstructions]);
end;

// A refused call is the tool's answer, not a protocol error, so the model sees
// why and can try again
function TMcpServer.CallTool(Params: TJSONObject): TJSONObject;
var
  ToolName: string;
  Method: TApiMethod;
  Arguments: TJSONData;
  OwnArguments: TJSONObject;
  Output: TJSONData;
begin
  if not GetJSONString(Params, 'name', ToolName) then
    raise EApiError.Create(RPC_INVALID_PARAMS, Format(rsApiMissingParam, ['name']));
  if not FindApiMethod(ToolName, Method) then
    raise EApiError.Create(RPC_INVALID_PARAMS, Format(rsMcpNoTool, [ToolName]));
  Arguments := Params.Find('arguments');
  if Assigned(Arguments) and (Arguments.JSONType <> jtObject) then
    raise EApiError.Create(RPC_INVALID_PARAMS, Format(rsApiMissingParam, ['arguments']));
  OwnArguments := nil;
  if not Assigned(Arguments) then
  begin
    OwnArguments := TJSONObject.Create;
    Arguments := OwnArguments;
  end;
  Output := nil;
  try
    try
      Output := FBackend.CallMethod(ToolName, TJSONObject(Arguments));
      Result := ToolResult(Output);
    except
      on Failure: Exception do
        Result := ErrorResult(FailureText(Failure));
    end;
  finally
    FreeAndNil(Output);
    FreeAndNil(OwnArguments);
  end;
end;

function TMcpServer.CallMcp(const Method: string; Params: TJSONObject; out Handled: boolean): TJSONData;
begin
  Handled := True;
  Result := nil;
  case Method of
    'initialize': Result := Initialize(Params);
    'ping': Result := TJSONObject.Create;
    'tools/list': Result := TJSONObject.Create(['tools', McpTools]);
    'tools/call': Result := CallTool(Params);
    else
      Handled := Method.StartsWith(MCP_NOTIFICATION_PREFIX);
  end;
end;

function TMcpServer.HandleLine(const Line: string): string;
var
  Request, Params, OwnParams: TJSONObject;
  Err, Method: string;
  Id, Output: TJSONData;
  Handled: boolean;
begin
  // Anything that is not a request for an MCP method, malformed lines
  // included, is the API server's to answer
  if not ParseJSONObject(Line, Request, Err) then
    Exit(FBackend.HandleLine(Line));
  OwnParams := nil;
  Output := nil;
  try
    if not GetJSONString(Request, 'method', Method) then
      Exit(FBackend.HandleLine(Line));
    Id := Request.Find('id');
    if Assigned(Request.Find('params')) and (Request.Find('params').JSONType = jtObject) then
      Params := Request.Objects['params']
    else
    begin
      OwnParams := TJSONObject.Create;
      Params := OwnParams;
    end;
    try
      Output := CallMcp(Method, Params, Handled);
      if not Handled then
        Exit(FBackend.HandleLine(Line));
      Result := '';
      if Assigned(Id) and Assigned(Output) then
      begin
        Result := RpcResultResponse(Id, Output);
        Output := nil;
      end;
    except
      on Failure: EApiError do
        Result := RpcErrorResponse(Id, Failure.Code, Failure.Message, Failure.FieldName, Failure.Position);
      on Failure: Exception do
        Result := RpcErrorResponse(Id, RPC_INTERNAL_ERROR, Failure.Message);
    end;
    if not Assigned(Id) then
      Result := '';
  finally
    FreeAndNil(Output);
    FreeAndNil(OwnParams);
    FreeAndNil(Request);
  end;
end;

end.
