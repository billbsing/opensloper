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

// Where a design window in automation mode listens, and how a client finds it
// and proves it may connect. The apps' link to each other (Sloper.API.AppLink)
// listens the same way, under another kind of endpoint. Each window writes an
// endpoint file in a private run folder: its socket (a Unix domain socket on Linux and macOS, a loopback
// port on Windows) and a token of 32 random bytes, new at each start. Only
// the user can read the folder, so only the user's own programs can present
// the token; the user never sees or types it. Messages are JSON-RPC, one a
// line. No LCL dependency.
unit Sloper.API.Endpoint;

{$mode ObjFPC}{$H+}

interface

uses
  SysUtils, ssockets;

const
  // The first request a client sends: {"method": "authenticate", "params": {"token": ...}}
  AUTOMATION_AUTH_METHOD = 'authenticate';
  AUTOMATION_TOKEN_PARAM = 'token';
  // Longest line before a client has authenticated, and after; in bytes
  AUTOMATION_AUTH_LINE_LIMIT = 4096;
  AUTOMATION_LINE_LIMIT = 256 * 1024 * 1024;
  // Windows listens here, never on every interface
  AUTOMATION_HOST = '127.0.0.1';
  // The kinds of endpoint, which start their files' names: a design window
  // in automation mode, and a publish window listening for the other apps
  AUTOMATION_KIND = 'automation';
  PUBLISH_KIND = 'publish';

type
  TAutomationEndpoint = record
    Pid: integer;
    // Linux and macOS: the socket file
    SocketPath: string;
    // Windows: the loopback port
    Port: integer;
    Token: string;
    // The endpoint file
    InfoPath: string;
  end;
  TAutomationEndpointArray = array of TAutomationEndpoint;

  TLineResult = (lrLine, lrWaiting, lrClosed, lrTooLong);

  // JSON-RPC messages over a socket, one a line
  TSocketLines = class
  private
    FStream: TSocketStream;
    FBuffer: rawbytestring;
  public
    // Takes over Stream
    constructor Create(AStream: TSocketStream);
    destructor Destroy; override;
    // The next line without its line end. TimeoutMs < 0 waits as long as it
    // takes; lrWaiting when none came in time.
    function ReadLine(TimeoutMs, MaxLength: integer; out Line: string): TLineResult;
    // Raises ESocketError or EStreamError when the other end has gone
    procedure WriteLine(const Line: string);
    property Stream: TSocketStream read FStream;
  end;

// Endpoints go in Folder instead of the run folder, so tests do not meet a
// window the user has open; '' goes back to the run folder
procedure UseAutomationFolder(const Folder: string);
// The private run folder, made if missing: on Linux and macOS it must belong
// to the user and be closed to everyone else
function PrepareAutomationFolder(out Folder, ErrorMessage: string): boolean;
// 32 bytes from the operating system's random source, as hex
function NewAutomationToken(out Token, ErrorMessage: string): boolean;
// Compares in a time that does not depend on where they differ
function SameToken(const Given, Expected: string): boolean;
// The paths this process uses in Folder for an endpoint of Kind
function AutomationEndpointFor(const Folder: string; APid: integer; const Kind: string = AUTOMATION_KIND): TAutomationEndpoint;
// Readable by the user only
function WriteAutomationEndpoint(const Endpoint: TAutomationEndpoint; out ErrorMessage: string): boolean;
// The windows listening now with an endpoint of Kind, as their files say, newest first
function ReadAutomationEndpoints(const Kind: string = AUTOMATION_KIND): TAutomationEndpointArray;
// Removes the files of a window that closed without tidying up, once nothing
// answers there
procedure RemoveAutomationEndpoint(const Endpoint: TAutomationEndpoint);
// Raises ESocketError when nothing listens there
function ConnectAutomation(const Endpoint: TAutomationEndpoint): TSocketStream;
// Sends the endpoint's token as the first request; True when the window admits
// the client within TimeoutMs. Raises ESocketError or EStreamError when the
// window has gone.
function AuthenticateAt(Lines: TSocketLines; const Endpoint: TAutomationEndpoint; TimeoutMs: integer): boolean;

resourcestring
  rsAutomationFolder = 'The folder %s cannot be made private to you, so automation stays off';
  rsAutomationRandom = 'The system''s random source could not be read, so automation stays off';

implementation

uses
  Classes, fpjson, Sockets, {$IFDEF UNIX} BaseUnix, {$ENDIF} {$IFDEF WINDOWS} WinSock2, {$ENDIF}
  Sloper.Core.AppPaths, Sloper.Core.JSON;

const
  ENDPOINT_FORMAT = 'opensloperAutomation';
  ENDPOINT_VERSION = 1;
  KIND_SEPARATOR = '-';
  ENDPOINT_EXTENSION = '.json';
  SOCKET_EXTENSION = '.sock';
  TOKEN_BYTES = 32;
  READ_CHUNK = 65536;
  MS_PER_SECOND = 1000;
  US_PER_MS = 1000;
  LINE_END = #10;
  {$IFDEF UNIX}
  PRIVATE_FOLDER_MODE = &700;
  PRIVATE_FILE_MODE = &600;
  OTHERS_MODE_MASK = &077;
  RANDOM_DEVICE = '/dev/urandom';
  {$ENDIF}
  {$IFDEF LINUX}
  // So writing to a client that has gone raises instead of killing the app
  SEND_NO_SIGNAL = $4000;
  {$ENDIF}

var
  FolderOverride: string;

function AutomationFolder: string;
begin
  Result := FolderOverride;
  if Result = '' then
    Result := TAppPaths.RuntimeDir;
end;

procedure UseAutomationFolder(const Folder: string);
begin
  FolderOverride := Folder;
end;

{$IFDEF WINDOWS}
function RtlGenRandom(RandomBuffer: Pointer; RandomBufferLength: longword): boolean; stdcall;
  external 'advapi32.dll' name 'SystemFunction036';
{$ENDIF}

// Whether the socket has something to read within TimeoutMs (< 0: no limit)
function WaitReadable(Handle: longint; TimeoutMs: integer): boolean;
var
  FDS: TFDSet;
  TimeV: TTimeVal;
  TimePointer: ^TTimeVal;
begin
  TimePointer := nil;
  if TimeoutMs >= 0 then
  begin
    TimeV.tv_sec := TimeoutMs div MS_PER_SECOND;
    TimeV.tv_usec := (TimeoutMs mod MS_PER_SECOND) * US_PER_MS;
    TimePointer := @TimeV;
  end;
  FDS := Default(TFDSet);
  {$IFDEF UNIX}
  fpFD_ZERO(FDS);
  fpFD_SET(Handle, FDS);
  Result := fpSelect(Handle + 1, @FDS, nil, nil, TimePointer) > 0;
  {$ELSE}
  FD_ZERO(FDS);
  FD_SET(Handle, FDS);
  Result := select(Handle + 1, @FDS, nil, nil, TimePointer) > 0;
  {$ENDIF}
end;

constructor TSocketLines.Create(AStream: TSocketStream);
  {$IFDEF DARWIN}
var
  NoSignal: longint;
  {$ENDIF}
begin
  inherited Create;
  FStream := AStream;
  {$IFDEF LINUX}
  FStream.WriteFlags := SEND_NO_SIGNAL;
  {$ENDIF}
  {$IFDEF DARWIN}
  NoSignal := 1;
  fpSetSockOpt(FStream.Handle, SOL_SOCKET, SO_NOSIGPIPE, @NoSignal, SizeOf(NoSignal));
  {$ENDIF}
  FBuffer := '';
end;

destructor TSocketLines.Destroy;
begin
  FreeAndNil(FStream);
  inherited Destroy;
end;

function TSocketLines.ReadLine(TimeoutMs, MaxLength: integer; out Line: string): TLineResult;
var
  Chunk: array[0..READ_CHUNK - 1] of byte;
  Count, EndAt: integer;
begin
  Line := '';
  repeat
    EndAt := Pos(LINE_END, FBuffer);
    if EndAt > 0 then
    begin
      Line := Copy(FBuffer, 1, EndAt - 1);
      Delete(FBuffer, 1, EndAt);
      if (Line <> '') and (Line[Length(Line)] = #13) then
        SetLength(Line, Length(Line) - 1);
      Exit(lrLine);
    end;
    if Length(FBuffer) > MaxLength then
      Exit(lrTooLong);
    if not WaitReadable(FStream.Handle, TimeoutMs) then
      Exit(lrWaiting);
    Count := FStream.Read(Chunk, SizeOf(Chunk));
    if Count <= 0 then
      Exit(lrClosed);
    SetLength(FBuffer, Length(FBuffer) + Count);
    Move(Chunk, FBuffer[Length(FBuffer) - Count + 1], Count);
  until False;
end;

procedure TSocketLines.WriteLine(const Line: string);
var
  Text: rawbytestring;
begin
  Text := Line + LINE_END;
  FStream.WriteBuffer(Text[1], Length(Text));
end;

function PrepareAutomationFolder(out Folder, ErrorMessage: string): boolean;
  {$IFDEF UNIX}
var
  Info: TStat;
  {$ENDIF}
begin
  ErrorMessage := '';
  Folder := AutomationFolder;
  Result := ForceDirectories(Folder);
  {$IFDEF UNIX}
  Result := Result and (fpChmod(Folder, PRIVATE_FOLDER_MODE) = 0) and (fpStat(Folder, Info) = 0) and
    (Info.st_uid = fpGetUid) and (Info.st_mode and OTHERS_MODE_MASK = 0);
  {$ENDIF}
  if not Result then
    ErrorMessage := Format(rsAutomationFolder, [Folder]);
end;

function NewAutomationToken(out Token, ErrorMessage: string): boolean;
var
  Bytes: array[0..TOKEN_BYTES - 1] of byte;
  Index: integer;
  {$IFDEF UNIX}
  Source: TFileStream;
  {$ENDIF}
begin
  Token := '';
  ErrorMessage := '';
  FillChar(Bytes, SizeOf(Bytes), 0);
  Result := False;
  try
    {$IFDEF UNIX}
    Source := TFileStream.Create(RANDOM_DEVICE, fmOpenRead or fmShareDenyNone);
    try
      Source.ReadBuffer(Bytes, SizeOf(Bytes));
      Result := True;
    finally
      FreeAndNil(Source);
    end;
    {$ENDIF}
    {$IFDEF WINDOWS}
    Result := RtlGenRandom(@Bytes, SizeOf(Bytes));
    {$ENDIF}
  except
    on Exception do
      Result := False;
  end;
  if not Result then
  begin
    ErrorMessage := rsAutomationRandom;
    Exit;
  end;
  for Index := 0 to High(Bytes) do
    Token := Token + IntToHex(Bytes[Index], 2);
  Token := LowerCase(Token);
end;

function SameToken(const Given, Expected: string): boolean;
var
  Index: integer;
  Difference: byte;
begin
  if (Length(Given) <> Length(Expected)) or (Expected = '') then
    Exit(False);
  Difference := 0;
  for Index := 1 to Length(Expected) do
    Difference := Difference or (Ord(Given[Index]) xor Ord(Expected[Index]));
  Result := Difference = 0;
end;

function AutomationEndpointFor(const Folder: string; APid: integer; const Kind: string): TAutomationEndpoint;
begin
  Result := Default(TAutomationEndpoint);
  Result.Pid := APid;
  Result.InfoPath := ConcatPaths([Folder, Kind + KIND_SEPARATOR + IntToStr(APid) + ENDPOINT_EXTENSION]);
  {$IFDEF UNIX}
  Result.SocketPath := ConcatPaths([Folder, Kind + KIND_SEPARATOR + IntToStr(APid) + SOCKET_EXTENSION]);
  {$ENDIF}
end;

function WriteAutomationEndpoint(const Endpoint: TAutomationEndpoint; out ErrorMessage: string): boolean;
var
  Info: TJSONObject;
begin
  Info := TJSONObject.Create(['format', ENDPOINT_FORMAT, 'version', ENDPOINT_VERSION, 'pid', Endpoint.Pid, 'socket',
    Endpoint.SocketPath, 'port', Endpoint.Port, AUTOMATION_TOKEN_PARAM, Endpoint.Token]);
  try
    // Made empty and closed to others before the token goes in
    Result := WriteTextFile(Endpoint.InfoPath, '', ErrorMessage);
    {$IFDEF UNIX}
    Result := Result and (fpChmod(Endpoint.InfoPath, PRIVATE_FILE_MODE) = 0);
    {$ENDIF}
    Result := Result and WriteTextFile(Endpoint.InfoPath, JSONToText(Info), ErrorMessage);
  finally
    FreeAndNil(Info);
  end;
end;

function ReadEndpoint(const Path: string; out Endpoint: TAutomationEndpoint): boolean;
var
  Text, Err, FormatName: string;
  Info: TJSONObject;
begin
  Endpoint := Default(TAutomationEndpoint);
  Endpoint.InfoPath := Path;
  if not ReadTextFile(Path, Text, Err) or not ParseJSONObject(Text, Info, Err) then
    Exit(False);
  try
    Result := GetJSONString(Info, 'format', FormatName) and (FormatName = ENDPOINT_FORMAT) and
      GetJSONString(Info, AUTOMATION_TOKEN_PARAM, Endpoint.Token) and GetJSONInteger(Info, 'pid', Endpoint.Pid);
    GetJSONString(Info, 'socket', Endpoint.SocketPath);
    GetJSONInteger(Info, 'port', Endpoint.Port);
  finally
    FreeAndNil(Info);
  end;
end;

function ReadAutomationEndpoints(const Kind: string): TAutomationEndpointArray;
var
  Found: TSearchRec;
  Folder: string;
  Endpoint: TAutomationEndpoint;
  Ages: array of longint;
  Place: integer;
begin
  Result := nil;
  Ages := nil;
  Folder := AutomationFolder;
  if FindFirst(ConcatPaths([Folder, Kind + KIND_SEPARATOR + '*' + ENDPOINT_EXTENSION]), faAnyFile, Found) = 0 then
  try
    repeat
      if not ReadEndpoint(ConcatPaths([Folder, Found.Name]), Endpoint) then
        Continue;
      // Newest first
      Place := 0;
      while (Place < Length(Ages)) and (Ages[Place] >= Found.Time) do
        Inc(Place);
      Insert(Endpoint, Result, Place);
      Insert(Found.Time, Ages, Place);
    until FindNext(Found) <> 0;
  finally
    FindClose(Found);
  end;
end;

procedure RemoveAutomationEndpoint(const Endpoint: TAutomationEndpoint);
begin
  DeleteFile(Endpoint.InfoPath);
  {$IFDEF UNIX}
  DeleteFile(Endpoint.SocketPath);
  {$ENDIF}
end;

function ConnectAutomation(const Endpoint: TAutomationEndpoint): TSocketStream;
begin
  {$IFDEF UNIX}
  Result := TUnixSocket.Create(Endpoint.SocketPath);
  {$ELSE}
  Result := TInetSocket.Create(AUTOMATION_HOST, Endpoint.Port);
  {$ENDIF}
end;

function AuthenticateAt(Lines: TSocketLines; const Endpoint: TAutomationEndpoint; TimeoutMs: integer): boolean;
var
  Request, Reply: TJSONObject;
  Line, Err: string;
begin
  Result := False;
  Request := TJSONObject.Create(['jsonrpc', '2.0', 'id', 0, 'method', AUTOMATION_AUTH_METHOD, 'params',
    TJSONObject.Create([AUTOMATION_TOKEN_PARAM, Endpoint.Token])]);
  try
    Lines.WriteLine(Request.AsJSON);
  finally
    FreeAndNil(Request);
  end;
  if (Lines.ReadLine(TimeoutMs, AUTOMATION_LINE_LIMIT, Line) = lrLine) and ParseJSONObject(Line, Reply, Err) then
  try
    Result := Assigned(Reply.Find('result'));
  finally
    FreeAndNil(Reply);
  end;
end;

end.
