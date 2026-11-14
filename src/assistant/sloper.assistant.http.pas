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
  Classes, SysUtils, SyncObjs, ssockets;

type
  TAssistantTransport = class
  public
    // Posts Body, writing a 2xx response into Sink as it arrives; anything
    // else is read whole into ErrorText. RetryAfter is the server's wait in
    // seconds, or 0. Raises on a network failure, and EAbort from the sink.
    function Post(const Body: string; Sink: TStream; out ErrorText: string; out RetryAfter: integer): integer; virtual; abstract;
    // From another thread: ends a Post in progress, which then raises
    procedure Abort; virtual;
  end;

  THttpsTransport = class(TAssistantTransport)
  private
    FKey: string;
    FUrl: string;
    FTrustedFile: string;
    // The connection Post is using, for Abort; FLock guards it, as Abort
    // comes from another thread
    FLock: TCriticalSection;
    FActive: TSocketHandler;
    // Abort came during this Post
    FAborted: boolean;
    function Aborted: boolean;
    procedure GetSocketHandler(Sender: TObject; const UseSSL: boolean; out AHandler: TSocketHandler);
    // Called as the connection's handler is freed, before its socket closes
    procedure Forget(Handler: TSocketHandler);
  public
    // Posts to Url, or to MessagesUrl when it is ''
    constructor Create(const AKey: string; const AUrl: string = '');
    destructor Destroy; override;
    function Post(const Body: string; Sink: TStream; out ErrorText: string; out RetryAfter: integer): integer; override;
    // Shuts the connection's socket down, so a read waiting on a server that
    // has gone quiet ends now rather than at the read timeout
    procedure Abort; override;
    // A PEM file of the certificates to trust in place of the system's, for tests
    property TrustedFile: string read FTrustedFile write FTrustedFile;
    // Read at each Post; not while one runs
    property Key: string read FKey write FKey;
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
  dynlibs, ctypes, Sockets, SysConst, fphttpclient, openssl, opensslsockets;

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
  // OpenSSL with the server's certificate checked, which FPC 3.2's handler
  // leaves off: the chain against trusted roots and the name against the
  // host, both in the handshake, so the key is never sent to a server that
  // merely claims to be the API
  TVerifyingSSLHandler = class(TOpenSSLSocketHandler)
  private
    FTrustedFile: string;
    FOwner: THttpsTransport;
  protected
    function InitContext(NeedCertificate: boolean): boolean; override;
  public
    constructor Create; override;
    destructor Destroy; override;
  end;

  // A plain connection, to an ANTHROPIC_BASE_URL without TLS, that Abort can end
  TPlainHandler = class(TSocketHandler)
  private
    FOwner: THttpsTransport;
  public
    destructor Destroy; override;
  end;

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

type
  TSslGetSslCtx = function(Ssl: PSSL): PSSL_CTX; cdecl;
  TSslCtxSetDefaultVerifyPaths = function(Ctx: PSSL_CTX): cint; cdecl;
  TSslSet1Host = function(Ssl: PSSL; HostName: pansichar): cint; cdecl;

constructor TVerifyingSSLHandler.Create;
begin
  inherited Create;
  VerifyPeerCert := True;
end;

destructor TVerifyingSSLHandler.Destroy;
begin
  if Assigned(FOwner) then
    FOwner.Forget(Self);
  inherited Destroy;
end;

destructor TPlainHandler.Destroy;
begin
  if Assigned(FOwner) then
    FOwner.Forget(Self);
  inherited Destroy;
end;

// After the context is made and before the handshake. OpenSSL 1.1 or later,
// for SSL_set1_host; without it, or without trusted roots, no connection.
function TVerifyingSSLHandler.InitContext(NeedCertificate: boolean): boolean;
var
  GetSslCtx: TSslGetSslCtx;
  SetDefaultVerifyPaths: TSslCtxSetDefaultVerifyPaths;
  Set1Host: TSslSet1Host;
  Ctx: PSSL_CTX;
begin
  Result := inherited InitContext(NeedCertificate);
  if not Result then
    Exit;
  Result := False;
  if not (Socket is TInetSocket) then
    Exit;
  Pointer(GetSslCtx) := GetProcedureAddress(SSLLibHandle, 'SSL_get_SSL_CTX');
  Pointer(SetDefaultVerifyPaths) := GetProcedureAddress(SSLLibHandle, 'SSL_CTX_set_default_verify_paths');
  Pointer(Set1Host) := GetProcedureAddress(SSLLibHandle, 'SSL_set1_host');
  if not Assigned(GetSslCtx) or not Assigned(SetDefaultVerifyPaths) or not Assigned(Set1Host) then
    Exit;
  Ctx := GetSslCtx(SSL.FSSL);
  if FTrustedFile <> '' then
    Result := SslCtxLoadVerifyLocations(Ctx, FTrustedFile, '') = 1
  else
    // The system's roots, or those SSL_CERT_FILE and SSL_CERT_DIR name
    Result := SetDefaultVerifyPaths(Ctx) = 1;
  Result := Result and (Set1Host(SSL.FSSL, pansichar(ansistring(TInetSocket(Socket).Host))) = 1);
end;

procedure TAssistantTransport.Abort;
begin
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

procedure THttpsTransport.GetSocketHandler(Sender: TObject; const UseSSL: boolean; out AHandler: TSocketHandler);
var
  Secure: TVerifyingSSLHandler;
  Plain: TPlainHandler;
begin
  if UseSSL then
  begin
    Secure := TVerifyingSSLHandler.Create;
    Secure.FTrustedFile := FTrustedFile;
    Secure.FOwner := Self;
    AHandler := Secure;
  end
  else
  begin
    Plain := TPlainHandler.Create;
    Plain.FOwner := Self;
    AHandler := Plain;
  end;
  FLock.Enter;
  try
    FActive := AHandler;
  finally
    FLock.Leave;
  end;
end;

procedure THttpsTransport.Forget(Handler: TSocketHandler);
begin
  FLock.Enter;
  try
    if FActive = Handler then
      FActive := nil;
  finally
    FLock.Leave;
  end;
end;

// The socket is still open: a handler is freed before its socket is closed,
// and Forget waits for the lock. Only reading is shut down, which wakes the
// read; writing stays open, since OpenSSL's closing write to a socket shut
// both ways would raise SIGPIPE and end the program
procedure THttpsTransport.Abort;
const
  SHUT_READING = 0;
begin
  FLock.Enter;
  try
    FAborted := True;
    if Assigned(FActive) and Assigned(FActive.Socket) then
      fpShutdown(FActive.Socket.Handle, SHUT_READING);
  finally
    FLock.Leave;
  end;
end;

constructor THttpsTransport.Create(const AKey: string; const AUrl: string);
begin
  inherited Create;
  FLock := TCriticalSection.Create;
  FKey := AKey;
  FUrl := AUrl;
  if FUrl = '' then
    FUrl := MessagesUrl;
end;

function THttpsTransport.Aborted: boolean;
begin
  FLock.Enter;
  try
    Result := FAborted;
  finally
    FLock.Leave;
  end;
end;

destructor THttpsTransport.Destroy;
begin
  FreeAndNil(FLock);
  inherited Destroy;
end;

function THttpsTransport.Post(const Body: string; Sink: TStream; out ErrorText: string; out RetryAfter: integer): integer;
var
  Client: TFPHTTPClient;
  Splitter: TStatusSplitter;
  Request: TStringStream;
begin
  ErrorText := '';
  RetryAfter := 0;
  FLock.Enter;
  try
    FAborted := False;
  finally
    FLock.Leave;
  end;
  Client := TFPHTTPClient.Create(nil);
  Splitter := TStatusSplitter.Create;
  Request := TStringStream.Create(Body);
  try
    Splitter.FClient := Client;
    Splitter.FSink := Sink;
    Client.OnGetSocketHandler := @GetSocketHandler;
    Client.IOTimeout := READ_TIMEOUT_MS;
    Client.AddHeader('content-type', 'application/json');
    Client.AddHeader('x-api-key', FKey);
    Client.AddHeader('anthropic-version', API_VERSION);
    Client.AddHeader('anthropic-beta', API_BETAS);
    Client.RequestBody := Request;
    try
      try
        Client.HTTPMethod('POST', FUrl, Splitter, []);
      except
        if Aborted then
          raise EAbort.Create(SAbortError);
        raise;
      end;
    finally
      Client.RequestBody := nil;
    end;
    // A read ended by Abort looks to the client like the end of the response
    if Aborted then
      raise EAbort.Create(SAbortError);
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
