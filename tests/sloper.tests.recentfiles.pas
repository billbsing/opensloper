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

unit Sloper.Tests.RecentFiles;

{$mode ObjFPC}{$H+}

interface

uses
  SysUtils, fpcunit, testregistry, Sloper.Tests.TestCase, Sloper.Core.RecentFiles;

type
  TTestRecentFiles = class(TOSTestCase)
  private
    FRecent: TRecentFiles;
    FFolder: string;
    function StoreFile: string;
    function Path(const Name: string): string;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestEmptyAtFirst;
    procedure TestAddPutsNewestFirst;
    procedure TestAddAgainMovesToFront;
    procedure TestListIsCapped;
    procedure TestRelativeNameIsExpanded;
    procedure TestRemove;
    procedure TestListsAreSeparate;
    procedure TestTextRoundTrip;
    procedure TestBrokenTextIsEmpty;
    procedure TestWrongFormatIsRefused;
    procedure TestNewerVersionIsFlagged;
    procedure TestMissingFileIsEmpty;
    procedure TestRememberCreatesFolderAndFile;
    procedure TestRememberKeepsOtherApps;
    procedure TestForgetAndClear;
    procedure TestRememberLeavesNewerVersionAlone;
    procedure TestRememberReplacesBrokenFile;
  end;

implementation

uses
  Sloper.Core.JSON;

procedure TTestRecentFiles.SetUp;
begin
  FRecent := TRecentFiles.Create;
  FFolder := ConcatPaths([GetTempDir, 'opensloper-recent-test-' + IntToStr(GetProcessID)]);
end;

procedure TTestRecentFiles.TearDown;
begin
  FreeAndNil(FRecent);
  DeleteFile(StoreFile);
  RemoveDir(FFolder);
end;

function TTestRecentFiles.StoreFile: string;
begin
  Result := ConcatPaths([FFolder, 'recent-files.json']);
end;

function TTestRecentFiles.Path(const Name: string): string;
begin
  Result := ConcatPaths([GetTempDir, Name]);
end;

procedure TTestRecentFiles.TestEmptyAtFirst;
begin
  AssertEquals(0, Length(FRecent.Files[rlPatterns]));
  AssertEquals(0, Length(FRecent.Files[rlMeasurements]));
  AssertEquals(0, Length(FRecent.Files[rlLayouts]));
end;

procedure TTestRecentFiles.TestAddPutsNewestFirst;
begin
  FRecent.Add(rlPatterns, Path('a.sloper'));
  FRecent.Add(rlPatterns, Path('b.sloper'));
  AssertEquals(2, Length(FRecent.Files[rlPatterns]));
  AssertEquals(Path('b.sloper'), FRecent.Files[rlPatterns][0]);
  AssertEquals(Path('a.sloper'), FRecent.Files[rlPatterns][1]);
end;

procedure TTestRecentFiles.TestAddAgainMovesToFront;
begin
  FRecent.Add(rlPatterns, Path('a.sloper'));
  FRecent.Add(rlPatterns, Path('b.sloper'));
  FRecent.Add(rlPatterns, Path('a.sloper'));
  AssertEquals('no repeat', 2, Length(FRecent.Files[rlPatterns]));
  AssertEquals(Path('a.sloper'), FRecent.Files[rlPatterns][0]);
end;

procedure TTestRecentFiles.TestListIsCapped;
var
  Index: integer;
begin
  for Index := 1 to MaxRecentFiles + 3 do
    FRecent.Add(rlLayouts, Path(Format('%d.layout', [Index])));
  AssertEquals(MaxRecentFiles, Length(FRecent.Files[rlLayouts]));
  AssertEquals('newest kept', Path(Format('%d.layout', [MaxRecentFiles + 3])), FRecent.Files[rlLayouts][0]);
end;

procedure TTestRecentFiles.TestRelativeNameIsExpanded;
begin
  FRecent.Add(rlPatterns, 'shirt.sloper');
  AssertEquals(ExpandFileName('shirt.sloper'), FRecent.Files[rlPatterns][0]);
end;

procedure TTestRecentFiles.TestRemove;
begin
  FRecent.Add(rlPatterns, Path('a.sloper'));
  FRecent.Add(rlPatterns, Path('b.sloper'));
  FRecent.Remove(rlPatterns, Path('a.sloper'));
  AssertEquals(1, Length(FRecent.Files[rlPatterns]));
  AssertEquals(Path('b.sloper'), FRecent.Files[rlPatterns][0]);
end;

procedure TTestRecentFiles.TestListsAreSeparate;
begin
  FRecent.Add(rlPatterns, Path('a.sloper'));
  FRecent.Add(rlMeasurements, Path('me.osm'));
  AssertEquals(1, Length(FRecent.Files[rlPatterns]));
  AssertEquals(1, Length(FRecent.Files[rlMeasurements]));
  AssertEquals(0, Length(FRecent.Files[rlLayouts]));
end;

procedure TTestRecentFiles.TestTextRoundTrip;
var
  Other: TRecentFiles;
  Err: string;
begin
  FRecent.Add(rlPatterns, Path('a.sloper'));
  FRecent.Add(rlPatterns, Path('b.sloper'));
  FRecent.Add(rlLayouts, Path('c.layout'));
  Other := TRecentFiles.Create;
  try
    AssertTrue(Err, Other.LoadFromText(FRecent.SaveToText, Err));
    AssertEquals(2, Length(Other.Files[rlPatterns]));
    AssertEquals('order kept', Path('b.sloper'), Other.Files[rlPatterns][0]);
    AssertEquals(Path('a.sloper'), Other.Files[rlPatterns][1]);
    AssertEquals(Path('c.layout'), Other.Files[rlLayouts][0]);
    AssertEquals(0, Length(Other.Files[rlMeasurements]));
  finally
    FreeAndNil(Other);
  end;
end;

procedure TTestRecentFiles.TestBrokenTextIsEmpty;
var
  Err: string;
begin
  FRecent.Add(rlPatterns, Path('a.sloper'));
  AssertFalse(FRecent.LoadFromText('{ not json', Err));
  AssertTrue('reports why', Err <> '');
  AssertEquals(0, Length(FRecent.Files[rlPatterns]));
end;

procedure TTestRecentFiles.TestWrongFormatIsRefused;
var
  Err: string;
begin
  AssertFalse(FRecent.LoadFromText('{"format": "opensloper-settings", "version": 1, "design": ["/a.sloper"]}', Err));
  AssertEquals(0, Length(FRecent.Files[rlPatterns]));
  AssertFalse('not newer', FRecent.NewerVersion);
end;

procedure TTestRecentFiles.TestNewerVersionIsFlagged;
var
  Err: string;
begin
  AssertFalse(FRecent.LoadFromText('{"format": "opensloper-recent-files", "version": 999, "design": ["/a.sloper"]}', Err));
  AssertTrue(FRecent.NewerVersion);
  AssertEquals(0, Length(FRecent.Files[rlPatterns]));
end;

procedure TTestRecentFiles.TestMissingFileIsEmpty;
var
  Err: string;
begin
  AssertTrue('a first run is not an error', FRecent.LoadFromFile(StoreFile, Err));
  AssertEquals(0, Length(FRecent.Files[rlPatterns]));
end;

procedure TTestRecentFiles.TestRememberCreatesFolderAndFile;
var
  Files: TStringArray;
begin
  RememberRecentFile(StoreFile, rlPatterns, Path('a.sloper'));
  AssertTrue('file written', FileExists(StoreFile));
  Files := ReadRecentFiles(StoreFile, rlPatterns);
  AssertEquals(1, Length(Files));
  AssertEquals(Path('a.sloper'), Files[0]);
end;

procedure TTestRecentFiles.TestRememberKeepsOtherApps;
begin
  RememberRecentFile(StoreFile, rlPatterns, Path('a.sloper'));
  RememberRecentFile(StoreFile, rlMeasurements, Path('me.osm'));
  RememberRecentFile(StoreFile, rlLayouts, Path('c.layout'));
  AssertEquals(Path('a.sloper'), ReadRecentFiles(StoreFile, rlPatterns)[0]);
  AssertEquals(Path('me.osm'), ReadRecentFiles(StoreFile, rlMeasurements)[0]);
  AssertEquals(Path('c.layout'), ReadRecentFiles(StoreFile, rlLayouts)[0]);
end;

procedure TTestRecentFiles.TestForgetAndClear;
begin
  RememberRecentFile(StoreFile, rlPatterns, Path('a.sloper'));
  RememberRecentFile(StoreFile, rlPatterns, Path('b.sloper'));
  RememberRecentFile(StoreFile, rlLayouts, Path('c.layout'));
  ForgetRecentFile(StoreFile, rlPatterns, Path('b.sloper'));
  AssertEquals(1, Length(ReadRecentFiles(StoreFile, rlPatterns)));
  ClearRecentFiles(StoreFile, rlPatterns);
  AssertEquals(0, Length(ReadRecentFiles(StoreFile, rlPatterns)));
  AssertEquals('other list kept', 1, Length(ReadRecentFiles(StoreFile, rlLayouts)));
end;

procedure TTestRecentFiles.TestRememberLeavesNewerVersionAlone;
var
  Newer, Text, Err: string;
begin
  Newer := '{"format": "opensloper-recent-files", "version": 999}';
  ForceDirectories(FFolder);
  AssertTrue(Err, WriteTextFile(StoreFile, Newer, Err));
  RememberRecentFile(StoreFile, rlPatterns, Path('a.sloper'));
  AssertTrue(Err, ReadTextFile(StoreFile, Text, Err));
  AssertEquals(Newer, Text);
end;

procedure TTestRecentFiles.TestRememberReplacesBrokenFile;
var
  Err: string;
begin
  ForceDirectories(FFolder);
  AssertTrue(Err, WriteTextFile(StoreFile, '{ not json', Err));
  RememberRecentFile(StoreFile, rlPatterns, Path('a.sloper'));
  AssertEquals(1, Length(ReadRecentFiles(StoreFile, rlPatterns)));
end;

initialization
  RegisterTest(TTestRecentFiles);

end.
