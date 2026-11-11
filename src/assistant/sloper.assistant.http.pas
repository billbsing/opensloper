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

// How the assistant reaches the Claude API: a POST of the request body with
// the response streamed into a sink. Raw HTTPS through FPC's HTTP client and
// OpenSSL, since Pascal has no Anthropic SDK; tests put a transport of their
// own in its place. No LCL dependency.
unit Sloper.Assistant.Http;

{$mode ObjFPC}{$H+}

interface

uses
  Classes, SysUtils;

type
  TAssistantTransport = class
  public
    // Posts Body, writing a 2xx response into Sink as it arrives; anything
    // else is read whole into ErrorText. RetryAfter is the server's wait in
    // seconds, or 0. Raises on a network failure, and EAbort from the sink.
    function Post(const Body: string; Sink: TStream; out ErrorText: string; out RetryAfter: integer): integer; virtual; abstract;
  end;

  THttpsTransport = class(TAssistantTransport)
  private
    FKey: string;
  public
    constructor Create(const AKey: string);
    function Post(const Body: string; Sink: TStream; out ErrorText: string; out RetryAfter: integer): integer; override;
  end;

// The Messages endpoint: ANTHROPIC_BASE_URL, as the SDKs take it for a proxy, or the API's own
function MessagesUrl: string;

const
  API_VERSION = '2026-10-21';
  // Refusal fallbacks, so a request a safety check declines is re-run on a
  // model chosen for the reason, in the same call
  API_BETAS = 'server-side-fallback-2026-07-01';

implementation

uses
  fphttpclient, opensslsockets;

const
  DEFAULT_BASE_URL = 'https://api.anthropic.com';
  BASE_URL_ENVIRONMENT = 'ANTHROPIC_BASE_URL';
  MESSAGES_PATH = '/v1/messages';
  // Pings come every few seconds while Claude thinks, so a minute of silence
  // means the connection is gone; ms
  READ_TIMEOUT_MS = 60000;
  HTTP_OK_LOW = 200;
  HTTP_OK_HIGH = 299;

type
  // Sends a success to the sink and anything else to a string
  TStatusSplitter = class(TStream)
  private
    FClient: TFPHTTPClient;
    FSink: TStream;
    FError: rawbytestring;
  public
    function Write(const Buffer; Count: longint): longint; override;
    function Read(var Buffer; Count: longint): longint; override;
    function Seek(const Offset: int64; Origin: TSeekOrigin): int64; override;
  end;

function TStatusSplitter.Write(const Buffer; Count: longint): longint;
var
  Text: rawbytestring;
begin
  if (FClient.ResponseStatusCode >= HTTP_OK_LOW) and (FClient.ResponseStatusCode <= HTTP_OK_HIGH) then
    Exit(FSink.Write(Buffer, Count));
  SetLength(Text, Count);
  if Count > 0 then
    Move(Buffer, Text[1], Count);
  FError := FError + Text;
  Result := Count;
end;

function TStatusSplitter.Read(var Buffer; Count: longint): longint;
begin
  Result := 0;
end;

function TStatusSplitter.Seek(const Offset: int64; Origin: TSeekOrigin): int64;
begin
  Result := 0;
end;

function MessagesUrl: string;
begin
  Result := GetEnvironmentVariable(BASE_URL_ENVIRONMENT);
  if Result = '' then
    Result := DEFAULT_BASE_URL;
  while Result.EndsWith('/') do
    SetLength(Result, Length(Result) - 1);
  Result := Result + MESSAGES_PATH;
end;

constructor THttpsTransport.Create(const AKey: string);
begin
  inherited Create;
  FKey := AKey;
end;

function THttpsTransport.Post(const Body: string; Sink: TStream; out ErrorText: string; out RetryAfter: integer): integer;
var
  Client: TFPHTTPClient;
  Splitter: TStatusSplitter;
  Request: TStringStream;
begin
  ErrorText := '';
  RetryAfter := 0;
  Client := TFPHTTPClient.Create(nil);
  Splitter := TStatusSplitter.Create;
  Request := TStringStream.Create(Body);
  try
    Splitter.FClient := Client;
    Splitter.FSink := Sink;
    Client.IOTimeout := READ_TIMEOUT_MS;
    Client.AddHeader('content-type', 'application/json');
    Client.AddHeader('x-api-key', FKey);
    Client.AddHeader('anthropic-version', API_VERSION);
    Client.AddHeader('anthropic-beta', API_BETAS);
    Client.RequestBody := Request;
    try
      Client.HTTPMethod('POST', MessagesUrl, Splitter, []);
    finally
      Client.RequestBody := nil;
    end;
    Result := Client.ResponseStatusCode;
    ErrorText := Splitter.FError;
    RetryAfter := StrToIntDef(Client.GetHeader(Client.ResponseHeaders, 'retry-after'), 0);
  finally
    FreeAndNil(Request);
    FreeAndNil(Splitter);
    FreeAndNil(Client);
  end;
end;

end.
