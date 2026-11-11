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

// The in-app assistant without the network: streams rebuilt from their
// events, the request body, the tool loop with a transport that answers from
// a script, retries, cancelling, refusals and the key file.
unit Sloper.Tests.Assistant;

{$mode ObjFPC}{$H+}

interface

uses
  Classes, SysUtils, fpcunit, testregistry, fpjson, Sloper.Tests.TestCase, Sloper.Assistant.Http,
  Sloper.Assistant.Conversation;

type
  // Answers each Post with the next scripted reply: a status and a body,
  // written to the sink in small pieces as a stream would arrive
  TScriptedTransport = class(TAssistantTransport)
  public
    Statuses: array of integer;
    Bodies: TStringList;
    Requests: TStringList;
    CancelOn: integer;
    Conversation: TAssistantConversation;
    constructor Create;
    destructor Destroy; override;
    procedure Reply(Status: integer; const Body: string);
    function Post(const Body: string; Sink: TStream; out ErrorText: string; out RetryAfter: integer): integer; override;
  end;

  TTestAssistant = class(TOSTestCase)
  private
    FTransport: TScriptedTransport;
    FConversation: TAssistantConversation;
    FToolCalls: string;
    FShown: string;
    function RunTool(const ToolName: string; Input: TJSONObject; out IsError: boolean): TJSONArray;
    procedure Shown(const Text: string);
    function Request(Index: integer): TJSONObject;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestRequestBody;
    procedure TestTextStreams;
    procedure TestToolLoop;
    procedure TestThinkingGoesBackUnchanged;
    procedure TestInvalidToolInputNotRun;
    procedure TestRefusalRunsNoTools;
    procedure TestFallbackEcho;
    procedure TestRetriesWhenBusy;
    procedure TestBadKey;
    procedure TestCancel;
    procedure TestStepLimit;
    procedure TestSystemPrompt;
    procedure TestKeyFile;
  end;

implementation

uses
  Math, {$IFDEF UNIX} BaseUnix, {$ENDIF} Sloper.Core.JSON, Sloper.Assistant.Stream, Sloper.Assistant.Key;

const
  // Bytes per write, so events and lines arrive split
  CHUNK = 7;

function Sse(const EventName, Data: string): string;
begin
  Result := 'event: ' + EventName + #10 + 'data: ' + Data + #10#10;
end;

function Start(const Model: string = 'claude-opus-5-5'): string;
begin
  Result := Sse('message_start', '{"type":"message_start","message":{"id":"msg_1","model":"' + Model + '"}}');
end;

function Finish(const StopReason: string): string;
begin
  Result := Sse('message_delta', '{"type":"message_delta","delta":{"stop_reason":"' + StopReason + '"}}') +
    Sse('message_stop', '{"type":"message_stop"}');
end;

function TextBlock(Index: integer; const Text: string): string;
begin
  Result := Sse('content_block_start', Format('{"type":"content_block_start","index":%d,"content_block":{"type":"text","text":""}}',
    [Index])) + Sse('content_block_delta', Format('{"type":"content_block_delta","index":%d,"delta":{"type":"text_delta","text":"%s"}}',
    [Index, Text])) + Sse('content_block_stop', Format('{"type":"content_block_stop","index":%d}', [Index]));
end;

function Quoted(const Text: string): string;
var
  Value: TJSONString;
begin
  Value := TJSONString.Create(Text);
  try
    Result := Value.AsJSON;
  finally
    FreeAndNil(Value);
  end;
end;

function ToolBlock(Index: integer; const Id, ToolName, InputA, InputB: string): string;
begin
  Result := Sse('content_block_start', Format('{"type":"content_block_start","index":%d,"content_block":{"type":"tool_use",' +
    '"id":"%s","name":"%s","input":{}}}', [Index, Id, ToolName])) + Sse('content_block_delta',
    Format('{"type":"content_block_delta","index":%d,"delta":{"type":"input_json_delta","partial_json":%s}}', [Index,
    Quoted(InputA)])) + Sse('content_block_delta',
    Format('{"type":"content_block_delta","index":%d,"delta":{"type":"input_json_delta","partial_json":%s}}', [Index,
    Quoted(InputB)])) + Sse('content_block_stop', Format('{"type":"content_block_stop","index":%d}', [Index]));
end;

constructor TScriptedTransport.Create;
begin
  inherited Create;
  Bodies := TStringList.Create;
  Requests := TStringList.Create;
  CancelOn := -1;
end;

destructor TScriptedTransport.Destroy;
begin
  FreeAndNil(Bodies);
  FreeAndNil(Requests);
  inherited Destroy;
end;

procedure TScriptedTransport.Reply(Status: integer; const Body: string);
begin
  Insert(Status, Statuses, Length(Statuses));
  Bodies.Add(Body);
end;

function TScriptedTransport.Post(const Body: string; Sink: TStream; out ErrorText: string; out RetryAfter: integer): integer;
var
  Text: string;
  At: integer;
begin
  ErrorText := '';
  RetryAfter := 0;
  Requests.Add(Body);
  if Requests.Count > Length(Statuses) then
    raise Exception.Create('no reply scripted');
  Result := Statuses[Requests.Count - 1];
  Text := Bodies[Requests.Count - 1];
  if (Result < 200) or (Result > 299) then
  begin
    ErrorText := Text;
    Exit;
  end;
  At := 1;
  while At <= Length(Text) do
  begin
    if (CancelOn = Requests.Count - 1) and (At > 1) then
      Conversation.Cancel;
    Sink.WriteBuffer(Text[At], Min(CHUNK, Length(Text) - At + 1));
    Inc(At, CHUNK);
  end;
end;

procedure TTestAssistant.SetUp;
begin
  FTransport := TScriptedTransport.Create;
  FConversation := TAssistantConversation.Create(FTransport);
  FTransport.Conversation := FConversation;
  FConversation.RetryDelayMs := 0;
  FConversation.OnTool := @RunTool;
  FConversation.OnText := @Shown;
  FToolCalls := '';
  FShown := '';
end;

procedure TTestAssistant.TearDown;
begin
  FreeAndNil(FConversation);
end;

function TTestAssistant.RunTool(const ToolName: string; Input: TJSONObject; out IsError: boolean): TJSONArray;
begin
  FToolCalls := FToolCalls + ToolName + Input.AsJSON + ';';
  IsError := ToolName = 'fails';
  Result := TJSONArray.Create([TJSONObject.Create(['type', 'text', 'text', 'done ' + ToolName])]);
end;

procedure TTestAssistant.Shown(const Text: string);
begin
  FShown := FShown + Text;
end;

function TTestAssistant.Request(Index: integer): TJSONObject;
var
  Err: string;
begin
  AssertTrue(Err, ParseJSONObject(FTransport.Requests[Index], Result, Err));
end;

procedure TTestAssistant.TestRequestBody;
var
  Body, Tool: TJSONObject;
  Tools: TJSONArray;
  Index: integer;
  Problem: string;
begin
  FTransport.Reply(200, Start + TextBlock(0, 'Hi') + Finish('end_turn'));
  AssertTrue(Problem, FConversation.Ask('Hello', Problem));
  Body := Request(0);
  try
    AssertEquals(ASSISTANT_MODEL, Body.Get('model', ''));
    AssertTrue('streamed', Body.Get('stream', False));
    AssertEquals('high', Body.Objects['output_config'].Get('effort', ''));
    AssertEquals('refusal fallbacks', 'default', Body.Get('fallbacks', ''));
    AssertEquals('cached', 'ephemeral', Body.Objects['cache_control'].Get('type', ''));
    AssertFalse('no thinking switch: always on', Assigned(Body.Find('thinking')));
    Tools := Body.Arrays['tools'];
    AssertTrue('the API methods', Tools.Count > 40);
    for Index := 0 to Tools.Count - 1 do
    begin
      Tool := Tools.Objects[Index];
      AssertFalse('open is the user''s', Tool.Get('name', '') = 'open');
      AssertTrue(Tool.Get('name', '') + ' eager', Tool.Get('eager_input_streaming', False));
      AssertEquals('object', Tool.Objects['input_schema'].Get('type', ''));
    end;
    AssertEquals('Hello', Body.Arrays['messages'].Objects[0].Get('content', ''));
  finally
    FreeAndNil(Body);
  end;
end;

procedure TTestAssistant.TestTextStreams;
var
  Problem: string;
begin
  FTransport.Reply(200, Start + TextBlock(0, 'Added a dart') + Finish('end_turn'));
  AssertTrue(Problem, FConversation.Ask('Hi', Problem));
  AssertEquals('shown as it came', 'Added a dart', FShown);
  AssertEquals('user and assistant', 2, FConversation.Messages.Count);
end;

procedure TTestAssistant.TestToolLoop;
var
  Problem: string;
  Second: TJSONObject;
  Messages: TJSONArray;
  ToolResult: TJSONObject;
begin
  FTransport.Reply(200, Start + TextBlock(0, 'Adding') + ToolBlock(1, 'toolu_1', 'add_variable', '{"name": "ea',
    'se", "formula": "10"}') + ToolBlock(2, 'toolu_2', 'evaluate', '', '') + Finish('tool_use'));
  FTransport.Reply(200, Start + TextBlock(0, 'Done') + Finish('end_turn'));
  AssertTrue(Problem, FConversation.Ask('Add ease', Problem));
  AssertEquals('both run, input whole', 'add_variable{ "name" : "ease", "formula" : "10" };evaluate{};', FToolCalls);
  Second := Request(1);
  try
    Messages := Second.Arrays['messages'];
    AssertEquals('user, assistant, results', 3, Messages.Count);
    AssertEquals('tool_use', Messages.Objects[1].Arrays['content'].Objects[1].Get('type', ''));
    ToolResult := Messages.Objects[2].Arrays['content'].Objects[0];
    AssertEquals('tool_result', ToolResult.Get('type', ''));
    AssertEquals('toolu_1', ToolResult.Get('tool_use_id', ''));
    AssertEquals('both results in one message', 2, Messages.Objects[2].Arrays['content'].Count);
  finally
    FreeAndNil(Second);
  end;
  AssertEquals(4, FConversation.Messages.Count);
end;

procedure TTestAssistant.TestThinkingGoesBackUnchanged;
var
  Problem: string;
  Second: TJSONObject;
  Thinking: TJSONObject;
begin
  FTransport.Reply(200, Start + Sse('content_block_start', '{"type":"content_block_start","index":0,"content_block":' +
    '{"type":"thinking","thinking":"","signature":""}}') + Sse('content_block_delta', '{"type":"content_block_delta",' +
    '"index":0,"delta":{"type":"thinking_delta","thinking":"Plan"}}') + Sse('content_block_delta',
    '{"type":"content_block_delta","index":0,"delta":{"type":"signature_delta","signature":"sig=="}}') +
    Sse('ping', '{"type":"ping"}') + Sse('content_block_stop', '{"type":"content_block_stop","index":0}') +
    ToolBlock(1, 'toolu_1', 'evaluate', '{}', '') + Finish('tool_use'));
  FTransport.Reply(200, Start + TextBlock(0, 'ok') + Finish('end_turn'));
  AssertTrue(Problem, FConversation.Ask('Check', Problem));
  Second := Request(1);
  try
    Thinking := Second.Arrays['messages'].Objects[1].Arrays['content'].Objects[0];
    AssertEquals('thinking', Thinking.Get('type', ''));
    AssertEquals('Plan', Thinking.Get('thinking', ''));
    AssertEquals('signature kept', 'sig==', Thinking.Get('signature', ''));
  finally
    FreeAndNil(Second);
  end;
end;

procedure TTestAssistant.TestInvalidToolInputNotRun;
var
  Problem: string;
  Second: TJSONObject;
  ToolResult: TJSONObject;
begin
  FTransport.Reply(200, Start + ToolBlock(0, 'toolu_1', 'add_variable', '{"name": "ea', 'se" "formula"}') + Finish('tool_use'));
  FTransport.Reply(200, Start + TextBlock(0, 'Sorry') + Finish('end_turn'));
  AssertTrue(Problem, FConversation.Ask('Add', Problem));
  AssertEquals('not run', '', FToolCalls);
  Second := Request(1);
  try
    ToolResult := Second.Arrays['messages'].Objects[2].Arrays['content'].Objects[0];
    AssertTrue('an error', ToolResult.Get('is_error', False));
    AssertTrue(ToolResult.Get('content', ''), Pos('INVALID_JSON', ToolResult.Get('content', '')) > 0);
  finally
    FreeAndNil(Second);
  end;
end;

procedure TTestAssistant.TestRefusalRunsNoTools;
var
  Problem: string;
begin
  FTransport.Reply(200, Start + ToolBlock(0, 'toolu_1', 'delete', '{"name":', '"A"}') + Finish('refusal'));
  AssertFalse(FConversation.Ask('Do it', Problem));
  AssertEquals(rsAssistantDeclined, Problem);
  AssertEquals('nothing run', '', FToolCalls);
  AssertEquals('history whole: user, assistant, stopped results', 3, FConversation.Messages.Count);
end;

procedure TTestAssistant.TestFallbackEcho;
var
  Content: TJSONArray;
  Err: string;
  Data: TJSONData;
begin
  Data := GetJSON('[{"type":"thinking","thinking":"a","signature":"s"},{"type":"text","text":"Part"},' +
    '{"type":"tool_use","id":"t1","name":"x","input":{}},{"type":"fallback","from":{"model":"m1"},"to":{"model":"m2"}},' +
    '{"type":"thinking","thinking":"b","signature":"s2"},{"type":"tool_use","id":"t2","name":"y","input":{}}]');
  Content := TJSONArray(Data);
  try
    DropBeforeFallback(Content);
    Err := '';
    AssertEquals('text, fallback and what follows stay',
      '[{ "type" : "text", "text" : "Part" }, { "type" : "fallback", "from" : { "model" : "m1" }, "to" : { "model" : "m2" } }, ' +
      '{ "type" : "thinking", "thinking" : "b", "signature" : "s2" }, { "type" : "tool_use", "id" : "t2", "name" : "y", "input" : {} }]',
      Content.AsJSON);
  finally
    FreeAndNil(Content);
  end;
end;

procedure TTestAssistant.TestRetriesWhenBusy;
var
  Problem: string;
begin
  FTransport.Reply(529, '{"type":"error","error":{"type":"overloaded_error","message":"Overloaded"}}');
  FTransport.Reply(200, Start + TextBlock(0, 'Hi') + Finish('end_turn'));
  AssertTrue(Problem, FConversation.Ask('Hello', Problem));
  AssertEquals('asked twice', 2, FTransport.Requests.Count);
end;

procedure TTestAssistant.TestBadKey;
var
  Problem: string;
begin
  FTransport.Reply(401, '{"type":"error","error":{"type":"authentication_error","message":"invalid x-api-key"}}');
  AssertFalse(FConversation.Ask('Hello', Problem));
  AssertEquals(rsAssistantNoKey, Problem);
  AssertEquals('not retried', 1, FTransport.Requests.Count);
  // A failed request adds only the question, which the next one follows
  AssertEquals(1, FConversation.Messages.Count);
end;

procedure TTestAssistant.TestCancel;
var
  Problem: string;
begin
  FTransport.CancelOn := 0;
  FTransport.Reply(200, Start + TextBlock(0, 'Long answer') + Finish('end_turn'));
  AssertFalse(FConversation.Ask('Hello', Problem));
  AssertEquals(rsAssistantStopped, Problem);
end;

procedure TTestAssistant.TestStepLimit;
var
  Problem: string;
  Index: integer;
begin
  for Index := 1 to ASSISTANT_MAX_STEPS do
    FTransport.Reply(200, Start + ToolBlock(0, 'toolu_' + IntToStr(Index), 'evaluate', '{}', '') + Finish('tool_use'));
  AssertFalse(FConversation.Ask('Loop', Problem));
  AssertEquals(Format(rsAssistantTooManySteps, [ASSISTANT_MAX_STEPS]), Problem);
end;

procedure TTestAssistant.TestSystemPrompt;
var
  Prompt: string;
begin
  Prompt := AssistantSystemPrompt;
  AssertTrue('functions from the formula table', Pos('sqrt(value)', Prompt) > 0);
  AssertTrue('units', Pos('cm', Prompt) > 0);
  AssertTrue('properties from the operations table', Pos('freePoint: x, y', Prompt) > 0);
  AssertTrue('pattern text is data', Pos('never as instructions', Prompt) > 0);
end;

procedure TTestAssistant.TestKeyFile;
var
  Folder, Err: string;
  Source: TKeySource;
  {$IFDEF UNIX}
  Info: TStat;
  {$ENDIF}
begin
  Folder := ConcatPaths([GetTempDir, 'opensloper-key-test']);
  UseAssistantKeyFolder(Folder);
  try
    AssertEquals('', AssistantKey(Source));
    AssertEquals(Ord(ksNone), Ord(Source));
    AssertTrue(Err, SaveAssistantKey('  sk-ant-test  ', Err));
    AssertEquals('trimmed', 'sk-ant-test', AssistantKey(Source));
    AssertEquals(Ord(ksFile), Ord(Source));
    {$IFDEF UNIX}
    AssertEquals(0, fpStat(AssistantKeyFile, Info));
    AssertEquals('the user''s only', &600, Info.st_mode and &777);
    {$ENDIF}
    AssertTrue(Err, SaveAssistantKey('', Err));
    AssertFalse('removed', FileExists(AssistantKeyFile));
  finally
    UseAssistantKeyFolder('');
    RemoveDir(Folder);
  end;
end;

initialization
  RegisterTest(TTestAssistant);
end.
