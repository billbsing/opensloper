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

// Platform folders for config, data, state, cache and user documents.
// All other code gets its folders from TAppPaths. No LCL dependency.
unit Sloper.Core.AppPaths;

{$mode ObjFPC}{$H+}

interface

type
  TAppPaths = class
  public
    class function ConfigDir: string;
    class function DataDir: string;
    class function StateDir: string;
    class function CacheDir: string;
    class function DefaultDocumentsDir: string;
    class function SettingsFile: string;
    // True when portable.ini sits beside the executable
    class function IsPortable: boolean;
    // The publish app beside this program, or in publish/ below it as in a
    // source tree. Empty when it is in neither place.
    class function PublishProgram: string;
    class function PublishProgramIn(const Folder: string): string;
    // opensloper-measurements, found the same way; '' when it is not there
    class function MeasurementsProgram: string;
    class function MeasurementsProgramIn(const Folder: string): string;
    // Creates Dir if missing and returns it; folders are made on first use
    class function ForceDir(const Dir: string): string;
    // XDG rule: EnvValue when it is an absolute path, else Home + Fallback
    class function ResolveXdgDir(const EnvValue, Home, Fallback: string): string;
  end;

implementation

uses
  SysUtils, Sloper.Core.Version;

const
  PortableFileName = 'portable.ini';
  SettingsFileName = 'settings.json';
  PublishFolder = 'publish';
  MeasurementsFolder = 'measurements';
  {$IFDEF WINDOWS}
  PublishFileName = 'opensloper-publish.exe';
  MeasurementsFileName = 'opensloper-measurements.exe';
  {$ELSE}
  PublishFileName = 'opensloper-publish';
  MeasurementsFileName = 'opensloper-measurements';
  {$ENDIF}

function HomeDir: string;
begin
  Result := ExcludeTrailingPathDelimiter(GetUserDir);
end;

function ExeDir: string;
begin
  Result := ExcludeTrailingPathDelimiter(ExtractFilePath(ParamStr(0)));
end;

function PortableDir(const Sub: string): string;
begin
  Result := ConcatPaths([ExeDir, Sub]);
end;

{$IFDEF WINDOWS}
function WinDir(const EnvName: string; const Extra: array of string): string;
begin
  Result := ConcatPaths([GetEnvironmentVariable(EnvName), AppName]);
  if Length(Extra) > 0 then
    Result := ConcatPaths([Result, ConcatPaths(Extra)]);
end;
{$ENDIF}

{$IFDEF DARWIN}
function MacDir(const Sub: string): string;
begin
  Result := ConcatPaths([HomeDir, 'Library', Sub, AppName]);
end;
{$ENDIF}

{$IF DEFINED(UNIX) AND NOT DEFINED(DARWIN)}
function XdgDir(const EnvName, Fallback: string): string;
begin
  Result := ConcatPaths([TAppPaths.ResolveXdgDir(GetEnvironmentVariable(EnvName),
    HomeDir, Fallback), AppNameLower]);
end;
{$ENDIF}

class function TAppPaths.ConfigDir: string;
begin
  if IsPortable then
    Exit(PortableDir('config'));
  {$IF DEFINED(WINDOWS)}
  Result := WinDir('APPDATA', []);
  {$ELSEIF DEFINED(DARWIN)}
  Result := MacDir('Application Support');
  {$ELSE}
  Result := XdgDir('XDG_CONFIG_HOME', '.config');
  {$ENDIF}
end;

class function TAppPaths.DataDir: string;
begin
  if IsPortable then
    Exit(PortableDir('data'));
  {$IF DEFINED(WINDOWS)}
  Result := WinDir('APPDATA', []);
  {$ELSEIF DEFINED(DARWIN)}
  Result := MacDir('Application Support');
  {$ELSE}
  Result := XdgDir('XDG_DATA_HOME', ConcatPaths(['.local', 'share']));
  {$ENDIF}
end;

class function TAppPaths.StateDir: string;
begin
  if IsPortable then
    Exit(PortableDir('state'));
  {$IF DEFINED(WINDOWS)}
  Result := WinDir('LOCALAPPDATA', []);
  {$ELSEIF DEFINED(DARWIN)}
  Result := MacDir('Application Support');
  {$ELSE}
  Result := XdgDir('XDG_STATE_HOME', ConcatPaths(['.local', 'state']));
  {$ENDIF}
end;

class function TAppPaths.CacheDir: string;
begin
  if IsPortable then
    Exit(PortableDir('cache'));
  {$IF DEFINED(WINDOWS)}
  Result := WinDir('LOCALAPPDATA', ['Cache']);
  {$ELSEIF DEFINED(DARWIN)}
  Result := MacDir('Caches');
  {$ELSE}
  Result := XdgDir('XDG_CACHE_HOME', '.cache');
  {$ENDIF}
end;

class function TAppPaths.DefaultDocumentsDir: string;
begin
  if IsPortable then
    Exit(PortableDir('documents'));
  Result := ConcatPaths([HomeDir, 'Documents', AppName]);
end;

class function TAppPaths.SettingsFile: string;
begin
  Result := ConcatPaths([ConfigDir, SettingsFileName]);
end;

// Beside this program when installed, in its own folder in the source tree
function CompanionIn(const Folder, SubFolder, FileName: string): string;
begin
  Result := ConcatPaths([Folder, FileName]);
  if FileExists(Result) then
    Exit;
  Result := ConcatPaths([Folder, SubFolder, FileName]);
  if not FileExists(Result) then
    Result := '';
end;

class function TAppPaths.PublishProgram: string;
begin
  Result := PublishProgramIn(ExeDir);
end;

class function TAppPaths.PublishProgramIn(const Folder: string): string;
begin
  Result := CompanionIn(Folder, PublishFolder, PublishFileName);
end;

class function TAppPaths.MeasurementsProgram: string;
begin
  Result := MeasurementsProgramIn(ExeDir);
end;

class function TAppPaths.MeasurementsProgramIn(const Folder: string): string;
begin
  Result := CompanionIn(Folder, MeasurementsFolder, MeasurementsFileName);
end;

class function TAppPaths.IsPortable: boolean;
begin
  Result := FileExists(ConcatPaths([ExeDir, PortableFileName]));
end;

class function TAppPaths.ForceDir(const Dir: string): string;
begin
  if not DirectoryExists(Dir) then
    ForceDirectories(Dir);
  Result := Dir;
end;

class function TAppPaths.ResolveXdgDir(const EnvValue, Home, Fallback: string): string;
begin
  // The XDG spec says relative values are invalid and must be ignored
  if (EnvValue <> '') and (EnvValue[1] = PathDelim) then
    Result := ExcludeTrailingPathDelimiter(EnvValue)
  else
    Result := ConcatPaths([Home, Fallback]);
end;

end.
