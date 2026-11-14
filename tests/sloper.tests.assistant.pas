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
    // A question whose first request fails leaves no trace
    procedure TestFailedQuestionTakenBack;
    // Stopped after tools ran: the next question joins its last user turn,
    // saying it was stopped, so Claude does not carry it on
    procedure TestStoppedQuestionNotCarriedOn;
    procedure TestStepLimit;
    procedure TestSystemPrompt;
    procedure TestKeyFile;
  end;

  // The HTTPS transport against a TLS server of its own on 127.0.0.1
  TTestHttpsTransport = class(TOSTestCase)
  private
    // Posts to a server with Certificate's pair from tests/tls, trusting
    // TrustedFile's ('' for the system's); True when it was answered
    function Answered(const Certificate, TrustedFile: string; out Requests: integer): boolean;
  published
    // Refused before the key is sent: no trusted authority signed it
    procedure TestUntrustedCertificateRefused;
    procedure TestTrustedCertificateAccepted;
    // Trusted, but for otherhost.test, not localhost
    procedure TestCertificateForAnotherHostRefused;
  end;

implementation

uses
  Math, {$IFDEF UNIX} BaseUnix, {$ENDIF} ssockets, sslsockets, opensslsockets, Sloper.Core.JSON, Sloper.Assistant.Stream,
  Sloper.Assistant.Key;

type
  // Accepts on 127.0.0.1 with a self-signed certificate and answers each
  // request 200, until stopped
  TTlsTestServer = class(TThread)
  private
    FServer: TInetServer;
    FPort: word;
    FCertificate: string;
    FRequests: integer;
    procedure CreateHandler(Sender: TObject; out AHandler: TSocketHandler);
    procedure Connected(Sender: TObject; Data: TSocketStream);
    procedure Idle(Sender: TObject);
  protected
    procedure Execute; override;
  public
    // Certificate: the path of a .pem with its .key beside it
    constructor Create(const Certificate: string);
    destructor Destroy; override;
    property Port: word read FPort;
    property Requests: integer read FRequests;
  end;

const
  TLS_TEST_FIRST_PORT = 47100;
  TLS_TEST_PORT_TRIES = 50;
  TLS_TEST_IDLE_MS = 50;
  TLS_TEST_READ_MS = 2000;

// The pair of a test certificate in tests/tls
function TlsTestFile(const AName: string): string;
begin
  Result := ConcatPaths([ExtractFileDir(ExpandFileName(ParamStr(0))), 'tls', AName]);
end;

constructor TTlsTestServer.Create(const Certificate: string);
var
  Try_: integer;
begin
  inherited Create(True);
  FCertificate := Certificate;
  for Try_ := 0 to TLS_TEST_PORT_TRIES - 1 do
  try
    // Bound and listening before the client connects; StartAccepting
    // would bind only in the thread
    FServer := TInetServer.Create('127.0.0.1', TLS_TEST_FIRST_PORT + Try_);
    FServer.ReuseAddress := True;
    FServer.Listen;
    FPort := TLS_TEST_FIRST_PORT + Try_;
    Break;
  except
    on ESocketError do
      FreeAndNil(FServer);
  end;
  if not Assigned(FServer) then
    raise Exception.Create('No free port for the TLS test server');
  FServer.OnCreateClientSocketHandler := @CreateHandler;
  FServer.OnConnect := @Connected;
  FServer.OnIdle := @Idle;
  FServer.AcceptIdleTimeOut := TLS_TEST_IDLE_MS;
  Start;
end;

destructor TTlsTestServer.Destroy;
begin
  Terminate;
  WaitFor;
  FreeAndNil(FServer);
  inherited Destroy;
end;

procedure TTlsTestServer.CreateHandler(Sender: TObject; out AHandler: TSocketHandler);
var
  Handler: TOpenSSLSocketHandler;
begin
  Handler := TOpenSSLSocketHandler.Create;
  Handler.CertificateData.Certificate.FileName := FCertificate;
  Handler.CertificateData.PrivateKey.FileName := ChangeFileExt(FCertificate, '.key');
  AHandler := Handler;
end;

procedure TTlsTestServer.Connected(Sender: TObject; Data: TSocketStream);
const
  ANSWER = 'HTTP/1.1 200 OK'#13#10'Content-Length: 2'#13#10'Connection: close'#13#10#13#10'{}';
var
  Buffer: array[0..4095] of byte;
  Received: string;
  Count: integer;
begin
  try
    Inc(FRequests);
    Data.IOTimeout := TLS_TEST_READ_MS;
    Received := '';
    // The request ends with its body, '{}'
    repeat
      Count := Data.Read(Buffer, SizeOf(Buffer));
      if Count > 0 then
        Received := Received + Copy(PChar(@Buffer[0]), 1, Count);
    until (Count <= 0) or (Pos(#13#10#13#10, Received) > 0) and Received.EndsWith('}');
    Data.WriteBuffer(ANSWER[1], Length(ANSWER));
  finally
    FreeAndNil(Data);
  end;
end;

procedure TTlsTestServer.Idle(Sender: TObject);
begin
  if Terminated then
    FServer.StopAccepting;
end;

procedure TTlsTestServer.Execute;
begin
  try
    FServer.StartAccepting;
  except
    // A failed handshake is the client refusing, which is what is tested
  end;
end;

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
  AssertEquals('the question is taken back', 0, FConversation.Messages.Count);
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

procedure TTestAssistant.TestFailedQuestionTakenBack;
var
  Problem: string;
  Second: TJSONObject;
  Messages: TJSONArray;
begin
  FTransport.CancelOn := 0;
  FTransport.Reply(200, Start + TextBlock(0, 'Deleting') + Finish('end_turn'));
  FTransport.Reply(200, Start + TextBlock(0, 'A is at 0, 0') + Finish('end_turn'));
  AssertFalse(FConversation.Ask('Delete the construction points', Problem));
  AssertTrue(Problem, FConversation.Ask('Where is A?', Problem));
  Second := Request(1);
  try
    Messages := Second.Arrays['messages'];
    AssertEquals('only the new question', 1, Messages.Count);
    AssertEquals('Where is A?', Messages.Objects[0].Get('content', ''));
  finally
    FreeAndNil(Second);
  end;
end;

procedure TTestAssistant.TestStoppedQuestionNotCarriedOn;
var
  Problem: string;
  Third: TJSONObject;
  Messages, Content: TJSONArray;
  Index: integer;
begin
  FTransport.CancelOn := 1;
  FTransport.Reply(200, Start + ToolBlock(0, 'toolu_1', 'evaluate', '{}', '') + Finish('tool_use'));
  FTransport.Reply(200, Start + TextBlock(0, 'Deleting the rest') + Finish('end_turn'));
  FTransport.Reply(200, Start + TextBlock(0, 'A is at 0, 0') + Finish('end_turn'));
  AssertFalse(FConversation.Ask('Delete the construction points', Problem));
  AssertEquals(rsAssistantStopped, Problem);
  AssertTrue(Problem, FConversation.Ask('Where is A?', Problem));
  Third := Request(2);
  try
    Messages := Third.Arrays['messages'];
    AssertEquals('question, tool use, results with the new question', 3, Messages.Count);
    for Index := 1 to Messages.Count - 1 do
      AssertTrue('roles alternate', Messages.Objects[Index].Get('role', '') <> Messages.Objects[Index - 1].Get('role', ''));
    Content := Messages.Objects[2].Arrays['content'];
    AssertEquals('result, note, question', 3, Content.Count);
    AssertEquals('tool_result', Content.Objects[0].Get('type', ''));
    AssertEquals(rsAssistantPreviousStopped, Content.Objects[1].Get('text', ''));
    AssertEquals('Where is A?', Content.Objects[2].Get('text', ''));
  finally
    FreeAndNil(Third);
  end;
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

{ TTestHttpsTransport }

function TTestHttpsTransport.Answered(const Certificate, TrustedFile: string; out Requests: integer): boolean;
var
  Server: TTlsTestServer;
  Transport: THttpsTransport;
  Sink: TStringStream;
  ErrorText: string;
  RetryAfter: integer;
begin
  Server := TTlsTestServer.Create(TlsTestFile(Certificate));
  Sink := TStringStream.Create('');
  Transport := THttpsTransport.Create('test-key', Format('https://localhost:%d/v1/messages', [Server.Port]));
  try
    Transport.TrustedFile := TrustedFile;
    try
      Result := Transport.Post('{}', Sink, ErrorText, RetryAfter) = 200;
      AssertEquals('the answer', '{}', Sink.DataString);
    except
      on ESocketError do
        Result := False;
    end;
  finally
    FreeAndNil(Transport);
    FreeAndNil(Sink);
    Requests := Server.Requests;
    FreeAndNil(Server);
  end;
end;

procedure TTestHttpsTransport.TestUntrustedCertificateRefused;
var
  Requests: integer;
begin
  AssertFalse('refused', Answered('localhost.pem', '', Requests));
  AssertEquals('no request was read', 0, Requests);
end;

procedure TTestHttpsTransport.TestTrustedCertificateAccepted;
var
  Requests: integer;
begin
  AssertTrue('answered', Answered('localhost.pem', TlsTestFile('localhost.pem'), Requests));
  AssertEquals(1, Requests);
end;

procedure TTestHttpsTransport.TestCertificateForAnotherHostRefused;
var
  Requests: integer;
begin
  AssertFalse('refused', Answered('otherhost.pem', TlsTestFile('otherhost.pem'), Requests));
  AssertEquals('no request was read', 0, Requests);
end;

initialization
  RegisterTest(TTestAssistant);
  RegisterTest(TTestHttpsTransport);
end.
