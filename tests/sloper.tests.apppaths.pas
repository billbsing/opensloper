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

unit Sloper.Tests.AppPaths;

{$mode ObjFPC}{$H+}

interface

uses
  fpcunit, testregistry, Sloper.Tests.TestCase, Sloper.Core.AppPaths;

type
  TTestAppPaths = class(TOSTestCase)
  published
    procedure TestXdgAbsoluteValueIsUsed;
    procedure TestXdgEmptyValueFallsBack;
    procedure TestXdgRelativeValueIsIgnored;
    procedure TestFoldersEndWithAppName;
    procedure TestSettingsFileIsInConfigDir;
    procedure TestRecentFilesFileIsInStateDir;
  end;

implementation

uses
  SysUtils, StrUtils;

procedure TTestAppPaths.TestXdgAbsoluteValueIsUsed;
var
  Dir: string;
begin
  Dir := PathDelim + ConcatPaths(['tmp', 'cfg']);
  AssertEquals(Dir, TAppPaths.ResolveXdgDir(Dir + PathDelim, PathDelim + 'home', '.config'));
end;

procedure TTestAppPaths.TestXdgEmptyValueFallsBack;
begin
  AssertEquals(ConcatPaths([PathDelim + 'home', '.config']),
    TAppPaths.ResolveXdgDir('', PathDelim + 'home', '.config'));
end;

procedure TTestAppPaths.TestXdgRelativeValueIsIgnored;
begin
  AssertEquals(ConcatPaths([PathDelim + 'home', '.cache']),
    TAppPaths.ResolveXdgDir('relative' + PathDelim + 'dir', PathDelim + 'home', '.cache'));
end;

procedure TTestAppPaths.TestFoldersEndWithAppName;
begin
  if TAppPaths.IsPortable then
    Exit;
  AssertTrue('config', AnsiEndsText('opensloper', TAppPaths.ConfigDir));
  AssertTrue('data', AnsiEndsText('opensloper', TAppPaths.DataDir));
  AssertTrue('documents', AnsiEndsText('opensloper', TAppPaths.DefaultDocumentsDir));
end;

procedure TTestAppPaths.TestSettingsFileIsInConfigDir;
begin
  AssertEquals(ConcatPaths([TAppPaths.ConfigDir, 'settings.json']), TAppPaths.SettingsFile);
end;

procedure TTestAppPaths.TestRecentFilesFileIsInStateDir;
begin
  AssertEquals(ConcatPaths([TAppPaths.StateDir, 'recent-files.json']), TAppPaths.RecentFilesFile);
end;

initialization
  RegisterTest(TTestAppPaths);

end.
