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

// The command icons: every one has its file, and each takes the text colour.
unit Sloper.Tests.IconSet;

{$mode ObjFPC}{$H+}

interface

uses
  fpcunit, testregistry, Sloper.Tests.TestCase, Sloper.Core.AppPaths, Sloper.UI.IconSet;

type
  TTestIconSet = class(TOSTestCase)
  published
    procedure TestIconDirIsFound;
    procedure TestIconDirMissing;
    procedure TestIconDirFromAppFolder;
    procedure TestEveryIconHasItsFile;
    procedure TestEveryIconTakesTheTextColour;
    procedure TestTintReplacesEveryCurrentColor;
  end;

implementation

uses
  SysUtils, Sloper.Core.JSON;

procedure TTestIconSet.TestIconDirIsFound;
begin
  AssertTrue('found from the tests folder', DirectoryExists(TAppPaths.IconDir));
end;

procedure TTestIconSet.TestIconDirMissing;
begin
  AssertEquals('', TAppPaths.IconDirIn(ConcatPaths([GetTempDir, 'no-such-opensloper-folder', 'bin'])));
end;

// The GUI apps are built in src/<app>, two folders below data/
procedure TTestIconSet.TestIconDirFromAppFolder;
var
  AppDir: string;
begin
  AppDir := ConcatPaths([ExtractFilePath(ParamStr(0)), '..', 'src', 'design']);
  AssertEquals(TAppPaths.IconDir, TAppPaths.IconDirIn(AppDir));
  AssertEquals(TAppPaths.CatalogueFile, TAppPaths.CatalogueFileIn(AppDir));
end;

procedure TTestIconSet.TestEveryIconHasItsFile;
var
  Icon: TAppIcon;
begin
  for Icon := Low(TAppIcon) to High(TAppIcon) do
    AssertTrue(APP_ICON_NAMES[Icon], FileExists(IconFileName(TAppPaths.IconDir, Icon)));
end;

procedure TTestIconSet.TestEveryIconTakesTheTextColour;
var
  Icon: TAppIcon;
  Text, Err: string;
begin
  for Icon := Low(TAppIcon) to High(TAppIcon) do
  begin
    AssertTrue(Err, ReadTextFile(IconFileName(TAppPaths.IconDir, Icon), Text, Err));
    AssertTrue(APP_ICON_NAMES[Icon], Pos('currentColor', Text) > 0);
  end;
end;

procedure TTestIconSet.TestTintReplacesEveryCurrentColor;
var
  Text: string;
begin
  Text := TintedSVG('<svg stroke="currentColor"><path fill="currentColor"/></svg>', '#112233');
  AssertEquals('<svg stroke="#112233"><path fill="#112233"/></svg>', Text);
end;

initialization
  RegisterTest(TTestIconSet);

end.
