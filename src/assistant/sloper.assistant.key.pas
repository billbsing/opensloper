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

// The user's Anthropic API key for the assistant: ANTHROPIC_API_KEY when it is
// set, else a file of its own in the config folder that only the user can
// read. It is kept out of settings.json, which is plain and shared by the
// three apps. No LCL dependency.
unit Sloper.Assistant.Key;

{$mode ObjFPC}{$H+}

interface

type
  TKeySource = (ksNone, ksEnvironment, ksFile);

// The key to use, and where it came from
function AssistantKey(out Source: TKeySource): string;
// Writes the key file, readable by the user only; '' removes it
function SaveAssistantKey(const Key: string; out ErrorMessage: string): boolean;
// The key file's path
function AssistantKeyFile: string;
// For tests: keys are read and written in Folder; '' goes back to the config folder
procedure UseAssistantKeyFolder(const Folder: string);

implementation

uses
  SysUtils, {$IFDEF UNIX} BaseUnix, {$ENDIF} Sloper.Core.AppPaths, Sloper.Core.JSON;

const
  KEY_ENVIRONMENT = 'ANTHROPIC_API_KEY';
  KEY_FILE_NAME = 'anthropic-key';
  {$IFDEF UNIX}
  PRIVATE_FILE_MODE = &600;
  {$ENDIF}

resourcestring
  rsKeyCannotRemove = 'The key file %s could not be removed: %s';
  rsKeyCannotProtect = 'The key file %s could not be made private, so the key was not saved: %s';

var
  FolderOverride: string;

function AssistantKeyFile: string;
var
  Folder: string;
begin
  Folder := FolderOverride;
  if Folder = '' then
    Folder := TAppPaths.ConfigDir;
  Result := ConcatPaths([Folder, KEY_FILE_NAME]);
end;

procedure UseAssistantKeyFolder(const Folder: string);
begin
  FolderOverride := Folder;
end;

function AssistantKey(out Source: TKeySource): string;
var
  Err: string;
begin
  Source := ksNone;
  // Tests read only their own folder
  if FolderOverride = '' then
    Result := Trim(GetEnvironmentVariable(KEY_ENVIRONMENT))
  else
    Result := '';
  if Result <> '' then
  begin
    Source := ksEnvironment;
    Exit;
  end;
  if FileExists(AssistantKeyFile) and ReadTextFile(AssistantKeyFile, Result, Err) then
    Result := Trim(Result)
  else
    Result := '';
  if Result <> '' then
    Source := ksFile;
end;

function SaveAssistantKey(const Key: string; out ErrorMessage: string): boolean;
var
  Path: string;
begin
  ErrorMessage := '';
  Path := AssistantKeyFile;
  if Trim(Key) = '' then
  begin
    Result := not FileExists(Path) or DeleteFile(Path);
    if not Result then
      ErrorMessage := Format(rsKeyCannotRemove, [Path, SysErrorMessage(GetLastOSError)]);
    Exit;
  end;
  ForceDirectories(ExtractFileDir(Path));
  // Made empty and closed to others before the key goes in
  if not WriteTextFile(Path, '', ErrorMessage) then
    Exit(False);
  {$IFDEF UNIX}
  if fpChmod(Path, PRIVATE_FILE_MODE) <> 0 then
  begin
    ErrorMessage := Format(rsKeyCannotProtect, [Path, SysErrorMessage(fpGetErrno)]);
    Exit(False);
  end;
  {$ENDIF}
  Result := WriteTextFile(Path, Trim(Key), ErrorMessage);
end;

end.
