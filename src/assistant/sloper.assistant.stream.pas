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

// A streamed Messages API response, read as it arrives: server-sent events
// split into event and data, and the assistant message rebuilt from them
// block by block, exactly as the API sent it, since thinking blocks must go
// back unchanged on the next request. No LCL dependency.
unit Sloper.Assistant.Stream;

{$mode ObjFPC}{$H+}

interface

uses
  Classes, SysUtils, fpjson;

type
  TAssistantTextEvent = procedure(const Text: string) of object;

  // Builds the assistant message from the stream's events
  TMessageAssembler = class
  private
    FContent: TJSONArray;
    // Each tool_use block's input, as the deltas give it
    FPartialInputs: TStringList;
    FStopReason, FModel, FErrorText: string;
    FFinished: boolean;
    FInvalidInputs: TStringList;
    FOnText: TAssistantTextEvent;
    procedure StartBlock(Event: TJSONObject);
    procedure Delta(Event: TJSONObject);
    procedure StopBlock(Event: TJSONObject);
    function Block(Index: integer): TJSONObject;
  public
    constructor Create;
    destructor Destroy; override;
    // One event's data; unknown events are ignored
    procedure Event(const EventName, Data: string);
    // The content, which the caller takes over
    function TakeContent: TJSONArray;
    // The raw input of a tool_use whose input was not valid JSON, or ''
    function InvalidInput(const ToolUseId: string): string;
    property StopReason: string read FStopReason;
    // message_stop came: the message is whole. A stream that ends without it
    // was cut off, and its blocks may be part-written
    property Finished: boolean read FFinished;
    property Model: string read FModel;
    // An error event's message, or ''
    property ErrorText: string read FErrorText;
    // Text as it streams, for showing
    property OnText: TAssistantTextEvent read FOnText write FOnText;
  end;

  // A stream the HTTP client writes the response into: complete events go to
  // the assembler, and each write checks for a cancel, raising EAbort
  TEventSink = class(TStream)
  private
    FAssembler: TMessageAssembler;
    FBuffer: rawbytestring;
    FEventName, FData: string;
    FCancelled: PBoolean;
    procedure Line(const Text: string);
  public
    constructor Create(AAssembler: TMessageAssembler; ACancelled: PBoolean);
    function Write(const Buffer; Count: longint): longint; override;
    function Read(var Buffer; Count: longint): longint; override;
    function Seek(const Offset: int64; Origin: TSeekOrigin): int64; override;
  end;

// After a refusal part-way through, the API rules for sending it back: before
// the last fallback block, thinking, tool_use and unpaired server tool blocks
// are left out. Content without a fallback block is unchanged.
procedure DropBeforeFallback(Content: TJSONArray);

implementation

uses
  StrUtils, Sloper.Core.JSON;

const
  LINE_END = #10;
  FALLBACK_TYPE = 'fallback';

constructor TMessageAssembler.Create;
begin
  inherited Create;
  FContent := TJSONArray.Create;
  FPartialInputs := TStringList.Create;
  FInvalidInputs := TStringList.Create;
end;

destructor TMessageAssembler.Destroy;
begin
  FreeAndNil(FContent);
  FreeAndNil(FPartialInputs);
  FreeAndNil(FInvalidInputs);
  inherited Destroy;
end;

function TMessageAssembler.TakeContent: TJSONArray;
begin
  Result := FContent;
  FContent := TJSONArray.Create;
end;

function TMessageAssembler.InvalidInput(const ToolUseId: string): string;
begin
  Result := FInvalidInputs.Values[ToolUseId];
end;

function TMessageAssembler.Block(Index: integer): TJSONObject;
begin
  if (Index < 0) or (Index >= FContent.Count) or (FContent.Items[Index].JSONType <> jtObject) then
    Exit(nil);
  Result := FContent.Objects[Index];
end;

procedure TMessageAssembler.Event(const EventName, Data: string);
var
  Item: TJSONObject;
  Err, EventType: string;
  Part: TJSONData;
begin
  if not ParseJSONObject(Data, Item, Err) then
    Exit;
  try
    EventType := Item.Get('type', EventName);
    case EventType of
      'message_start':
      begin
        Part := Item.Find('message');
        if Assigned(Part) and (Part.JSONType = jtObject) then
          FModel := TJSONObject(Part).Get('model', '');
      end;
      'content_block_start': StartBlock(Item);
      'content_block_delta': Delta(Item);
      'content_block_stop': StopBlock(Item);
      'message_stop': FFinished := True;
      'message_delta':
      begin
        Part := Item.Find('delta');
        if Assigned(Part) and (Part.JSONType = jtObject) then
          FStopReason := TJSONObject(Part).Get('stop_reason', FStopReason);
      end;
      'error':
      begin
        Part := Item.Find('error');
        if Assigned(Part) and (Part.JSONType = jtObject) then
          FErrorText := TJSONObject(Part).Get('message', Data)
        else
          FErrorText := Data;
      end;
    end;
  finally
    FreeAndNil(Item);
  end;
end;

procedure TMessageAssembler.StartBlock(Event: TJSONObject);
var
  Index: integer;
  Started: TJSONData;
begin
  Index := Event.Get('index', FContent.Count);
  Started := Event.Find('content_block');
  if not Assigned(Started) or (Started.JSONType <> jtObject) then
    Exit;
  while FContent.Count < Index do
    FContent.Add(TJSONObject.Create);
  if Index < FContent.Count then
    FContent.Delete(Index);
  FContent.Insert(Index, Started.Clone);
  if TJSONObject(Started).Get('type', '') = 'text' then
    if Assigned(FOnText) and (TJSONObject(Started).Get('text', '') <> '') then
      FOnText(TJSONObject(Started).Get('text', ''));
end;

procedure TMessageAssembler.Delta(Event: TJSONObject);
var
  Target, Changed: TJSONObject;
  Change: TJSONData;
  Index: integer;

  procedure Append(const FieldName, Text: string);
  begin
    Target.Strings[FieldName] := Target.Get(FieldName, '') + Text;
  end;

begin
  Index := Event.Get('index', -1);
  Target := Block(Index);
  Change := Event.Find('delta');
  if not Assigned(Target) or not Assigned(Change) or (Change.JSONType <> jtObject) then
    Exit;
  Changed := TJSONObject(Change);
  case Changed.Get('type', '') of
    'text_delta':
    begin
      Append('text', Changed.Get('text', ''));
      if Assigned(FOnText) then
        FOnText(Changed.Get('text', ''));
    end;
    'thinking_delta': Append('thinking', Changed.Get('thinking', ''));
    'signature_delta': Append('signature', Changed.Get('signature', ''));
    'input_json_delta':
      FPartialInputs.Values[IntToStr(Index)] := FPartialInputs.Values[IntToStr(Index)] + Changed.Get('partial_json', '');
  end;
end;

// A tool's input is parsed strictly once it is whole; input that does not
// parse is kept, so the tool is not run and Claude is told
procedure TMessageAssembler.StopBlock(Event: TJSONObject);
var
  Target, Input: TJSONObject;
  Index: integer;
  Raw, Err: string;
begin
  Index := Event.Get('index', -1);
  Target := Block(Index);
  if not Assigned(Target) or (Target.Get('type', '') <> 'tool_use') then
    Exit;
  Raw := FPartialInputs.Values[IntToStr(Index)];
  if Trim(Raw) = '' then
    Exit;
  if ParseJSONObject(Raw, Input, Err) then
  begin
    if Target.IndexOfName('input') >= 0 then
      Target.Delete('input');
    Target.Add('input', Input);
  end
  else
    FInvalidInputs.Values[Target.Get('id', '')] := Raw;
end;

procedure DropBeforeFallback(Content: TJSONArray);
var
  Index, Boundary: integer;
  BlockType: string;
  Paired: TStringList;
begin
  Boundary := -1;
  for Index := 0 to Content.Count - 1 do
    if (Content.Items[Index].JSONType = jtObject) and (Content.Objects[Index].Get('type', '') = FALLBACK_TYPE) then
      Boundary := Index;
  if Boundary < 0 then
    Exit;
  // Server tool uses answered before the boundary stay
  Paired := TStringList.Create;
  try
    for Index := 0 to Boundary - 1 do
      if (Content.Items[Index].JSONType = jtObject) and AnsiEndsStr('_tool_result', Content.Objects[Index].Get('type', '')) then
        Paired.Add(Content.Objects[Index].Get('tool_use_id', ''));
    for Index := Boundary - 1 downto 0 do
    begin
      if Content.Items[Index].JSONType <> jtObject then
        Continue;
      BlockType := Content.Objects[Index].Get('type', '');
      if (BlockType = 'thinking') or (BlockType = 'redacted_thinking') or (BlockType = 'tool_use') or
        ((BlockType = 'server_tool_use') and (Paired.IndexOf(Content.Objects[Index].Get('id', '')) < 0)) then
        Content.Delete(Index);
    end;
  finally
    FreeAndNil(Paired);
  end;
end;

constructor TEventSink.Create(AAssembler: TMessageAssembler; ACancelled: PBoolean);
begin
  inherited Create;
  FAssembler := AAssembler;
  FCancelled := ACancelled;
end;

procedure TEventSink.Line(const Text: string);
begin
  if Text = '' then
  begin
    // A blank line ends the event
    if FData <> '' then
      FAssembler.Event(FEventName, FData);
    FEventName := '';
    FData := '';
  end
  else if Text.StartsWith('event:') then
    FEventName := Trim(Copy(Text, Length('event:') + 1, MaxInt))
  else if Text.StartsWith('data:') then
  begin
    if FData <> '' then
      FData := FData + LINE_END;
    FData := FData + TrimLeft(Copy(Text, Length('data:') + 1, MaxInt));
  end;
end;

function TEventSink.Write(const Buffer; Count: longint): longint;
var
  EndAt: integer;
  Text: string;
begin
  if Assigned(FCancelled) and FCancelled^ then
    raise EAbort.Create('');
  if Count > 0 then
  begin
    SetLength(Text, Count);
    Move(Buffer, Text[1], Count);
    FBuffer := FBuffer + Text;
  end;
  EndAt := Pos(LINE_END, FBuffer);
  while EndAt > 0 do
  begin
    Text := Copy(FBuffer, 1, EndAt - 1);
    Delete(FBuffer, 1, EndAt);
    if (Text <> '') and (Text[Length(Text)] = #13) then
      SetLength(Text, Length(Text) - 1);
    Line(Text);
    EndAt := Pos(LINE_END, FBuffer);
  end;
  Result := Count;
end;

function TEventSink.Read(var Buffer; Count: longint): longint;
begin
  Result := 0;
end;

function TEventSink.Seek(const Offset: int64; Origin: TSeekOrigin): int64;
begin
  Result := 0;
end;

end.
