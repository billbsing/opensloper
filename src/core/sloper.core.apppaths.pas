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
    // Files that last only while an app runs, such as the automation socket:
    // $XDG_RUNTIME_DIR on Linux, the user's own temporary folder on macOS,
    // Local AppData on Windows. Never the portable folder, which may be on a
    // drive that cannot hold a socket. Not made private here.
    class function RuntimeDir: string;
    class function DefaultDocumentsDir: string;
    class function SettingsFile: string;
    // File → Open Recent's lists, which are state rather than settings
    class function RecentFilesFile: string;
    // True when portable.ini sits beside the executable
    class function IsPortable: boolean;
    // The publish app beside this program, or in the source tree in publish/
    // below it or beside its folder. Empty when it is in none of these.
    class function PublishProgram: string;
    class function PublishProgramIn(const Folder: string): string;
    // opensloper-measurements, found the same way; '' when it is not there
    class function MeasurementsProgram: string;
    class function MeasurementsProgramIn(const Folder: string): string;
    // The measurement catalogue, in data beside this program when installed
    // or one or two folders up in the source tree; '' when it is not there
    class function CatalogueFile: string;
    class function CatalogueFileIn(const Folder: string): string;
    // The toolbar and menu icons, found the same way; '' when they are not there
    class function IconDir: string;
    class function IconDirIn(const Folder: string): string;
    // The fonts bundled for drawing text into images, data/fonts
    class function FontDir: string;
    class function FontDirIn(const Folder: string): string;
    // Creates Dir if missing and returns it; folders are made on first use
    class function ForceDir(const Dir: string): string;
    // XDG rule: EnvValue when it is an absolute path, else Home + Fallback
    class function ResolveXdgDir(const EnvValue, Home, Fallback: string): string;
  end;

implementation

uses
  {$IFDEF UNIX}
  BaseUnix,
  {$ENDIF}
  SysUtils, Sloper.Core.Version;

const
  PORTABLE_FILE_NAME = 'portable.ini';
  SETTINGS_FILE_NAME = 'settings.json';
  RECENT_FILES_FILE_NAME = 'recent-files.json';
  PUBLISH_FOLDER = 'publish';
  MEASUREMENTS_FOLDER = 'measurements';
  DATA_FOLDER = 'data';
  CATALOGUE_FILE_NAME = 'measurement-catalogue.json';
  ICON_FOLDER = 'icons';
  FONT_FOLDER = 'fonts';
  {$IFDEF WINDOWS}
  PUBLISH_FILE_NAME = 'opensloper-publish.exe';
  MEASUREMENTS_FILE_NAME = 'opensloper-measurements.exe';
  {$ELSE}
  PUBLISH_FILE_NAME = 'opensloper-publish';
  MEASUREMENTS_FILE_NAME = 'opensloper-measurements';
  {$ENDIF}
  DATA_UP_LEVELS: array[0..2] of string = ('', '..', '..' + PathDelim + '..');

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
  Result := ConcatPaths([GetEnvironmentVariable(EnvName), APP_NAME]);
  if Length(Extra) > 0 then
    Result := ConcatPaths([Result, ConcatPaths(Extra)]);
end;
{$ENDIF}

{$IFDEF DARWIN}
function MacDir(const Sub: string): string;
begin
  Result := ConcatPaths([HomeDir, 'Library', Sub, APP_NAME]);
end;
{$ENDIF}

{$IF DEFINED(UNIX) AND NOT DEFINED(DARWIN)}
function XdgDir(const EnvName, Fallback: string): string;
begin
  Result := ConcatPaths([TAppPaths.ResolveXdgDir(GetEnvironmentVariable(EnvName),
    HomeDir, Fallback), APP_NAME_LOWER]);
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

class function TAppPaths.RuntimeDir: string;
begin
  {$IF DEFINED(WINDOWS)}
  Result := WinDir('LOCALAPPDATA', ['run']);
  {$ELSEIF DEFINED(DARWIN)}
  // TMPDIR is already the user's own
  Result := ConcatPaths([ExcludeTrailingPathDelimiter(GetTempDir), APP_NAME_LOWER]);
  {$ELSE}
  if (GetEnvironmentVariable('XDG_RUNTIME_DIR') <> '') and (GetEnvironmentVariable('XDG_RUNTIME_DIR')[1] = PathDelim) then
    Result := ConcatPaths([GetEnvironmentVariable('XDG_RUNTIME_DIR'), APP_NAME_LOWER])
  else
    Result := ConcatPaths([ExcludeTrailingPathDelimiter(GetTempDir), APP_NAME_LOWER + '-' + IntToStr(fpGetUid)]);
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
  Result := ConcatPaths([HomeDir, 'Documents', APP_NAME]);
end;

class function TAppPaths.SettingsFile: string;
begin
  Result := ConcatPaths([ConfigDir, SETTINGS_FILE_NAME]);
end;

class function TAppPaths.RecentFilesFile: string;
begin
  Result := ConcatPaths([StateDir, RECENT_FILES_FILE_NAME]);
end;

// Beside this program when installed; in the source tree in its own folder,
// below this program or beside its folder (src/design and src/publish)
function CompanionIn(const Folder, SubFolder, FileName: string): string;
begin
  Result := ConcatPaths([Folder, FileName]);
  if FileExists(Result) then
    Exit;
  Result := ConcatPaths([Folder, SubFolder, FileName]);
  if FileExists(Result) then
    Exit;
  Result := ExpandFileName(ConcatPaths([Folder, '..', SubFolder, FileName]));
  if not FileExists(Result) then
    Result := '';
end;

// Path in data beside Folder when installed, or in the data folder of the
// source tree: one folder up from tests and cli, two up from src/<app>
function DataPathIn(const Folder, Path: string; WantDir: boolean): string;
var
  Up: string;
begin
  for Up in DATA_UP_LEVELS do
  begin
    Result := ExpandFileName(ConcatPaths([Folder, Up, DATA_FOLDER, Path]));
    if (WantDir and DirectoryExists(Result)) or (not WantDir and FileExists(Result)) then
      Exit;
  end;
  Result := '';
end;

class function TAppPaths.PublishProgram: string;
begin
  Result := PublishProgramIn(ExeDir);
end;

class function TAppPaths.PublishProgramIn(const Folder: string): string;
begin
  Result := CompanionIn(Folder, PUBLISH_FOLDER, PUBLISH_FILE_NAME);
end;

class function TAppPaths.CatalogueFile: string;
begin
  Result := CatalogueFileIn(ExeDir);
end;

class function TAppPaths.CatalogueFileIn(const Folder: string): string;
begin
  Result := DataPathIn(Folder, CATALOGUE_FILE_NAME, False);
end;

class function TAppPaths.IconDir: string;
begin
  Result := IconDirIn(ExeDir);
end;

class function TAppPaths.IconDirIn(const Folder: string): string;
begin
  Result := DataPathIn(Folder, ICON_FOLDER, True);
end;

class function TAppPaths.FontDir: string;
begin
  Result := FontDirIn(ExeDir);
end;

class function TAppPaths.FontDirIn(const Folder: string): string;
begin
  Result := DataPathIn(Folder, FONT_FOLDER, True);
end;

class function TAppPaths.MeasurementsProgram: string;
begin
  Result := MeasurementsProgramIn(ExeDir);
end;

class function TAppPaths.MeasurementsProgramIn(const Folder: string): string;
begin
  Result := CompanionIn(Folder, MEASUREMENTS_FOLDER, MEASUREMENTS_FILE_NAME);
end;

class function TAppPaths.IsPortable: boolean;
begin
  Result := FileExists(ConcatPaths([ExeDir, PORTABLE_FILE_NAME]));
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
