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

unit Sloper.Tests.Settings;

{$mode ObjFPC}{$H+}

interface

uses
  fpcunit, testregistry, Sloper.Tests.TestCase, Sloper.Core.Settings;

type
  TTestSettings = class(TOSTestCase)
  private
    FSettings: TAppSettings;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestDefaults;
    procedure TestTextRoundTrip;
    procedure TestFileRoundTrip;
    procedure TestMissingFileKeepsDefaults;
    procedure TestBrokenTextKeepsDefaults;
    procedure TestWrongFormatKeepsDefaults;
    procedure TestNewerVersionKeepsDefaults;
    procedure TestOutOfRangeShareIsIgnored;
    procedure TestMissingShareIsDefault;
    procedure TestLabelModeRoundTrip;
    procedure TestUnknownLabelModeIsIgnored;
  end;

implementation

uses
  SysUtils;

procedure TTestSettings.SetUp;
begin
  FSettings := TAppSettings.Create;
end;

procedure TTestSettings.TearDown;
begin
  FreeAndNil(FSettings);
end;

procedure TTestSettings.TestDefaults;
begin
  AssertNear('share', DefaultNameColumnShare, FSettings.NameColumnShare);
  AssertTrue('label mode', FSettings.LabelMode = lmContextual);
end;

procedure TTestSettings.TestLabelModeRoundTrip;
var
  Other: TAppSettings;
  Err: string;
  Mode: TLabelMode;
begin
  Other := TAppSettings.Create;
  try
    for Mode := Low(TLabelMode) to High(TLabelMode) do
    begin
      FSettings.LabelMode := Mode;
      AssertTrue(Err, Other.LoadFromText(FSettings.SaveToText, Err));
      AssertTrue('label mode', Other.LabelMode = Mode);
    end;
  finally
    FreeAndNil(Other);
  end;
end;

procedure TTestSettings.TestUnknownLabelModeIsIgnored;
var
  Err: string;
begin
  FSettings.LabelMode := lmNone;
  AssertTrue(Err, FSettings.LoadFromText('{"format": "opensloper-settings", "version": 1, "labelMode": "some"}', Err));
  AssertTrue(FSettings.LabelMode = DefaultLabelMode);
end;

procedure TTestSettings.TestTextRoundTrip;
var
  Other: TAppSettings;
  Err: string;
begin
  FSettings.NameColumnShare := 0.625;
  Other := TAppSettings.Create;
  try
    AssertTrue(Err, Other.LoadFromText(FSettings.SaveToText, Err));
    AssertNear('share', 0.625, Other.NameColumnShare);
  finally
    FreeAndNil(Other);
  end;
end;

procedure TTestSettings.TestFileRoundTrip;
var
  FileName, Err: string;
  Other: TAppSettings;
begin
  FileName := GetTempFileName(GetTempDir, 'oss');
  try
    FSettings.NameColumnShare := 0.3;
    AssertTrue(Err, FSettings.SaveToFile(FileName, Err));
    Other := TAppSettings.Create;
    try
      AssertTrue(Err, Other.LoadFromFile(FileName, Err));
      AssertNear('share', 0.3, Other.NameColumnShare);
    finally
      FreeAndNil(Other);
    end;
  finally
    DeleteFile(FileName);
  end;
end;

procedure TTestSettings.TestMissingFileKeepsDefaults;
var
  Err: string;
begin
  AssertTrue('a first run is not an error',
    FSettings.LoadFromFile(ConcatPaths([GetTempDir, 'opensloper-no-such-settings.json']), Err));
  AssertNear('share', DefaultNameColumnShare, FSettings.NameColumnShare);
end;

procedure TTestSettings.TestBrokenTextKeepsDefaults;
var
  Err: string;
begin
  AssertFalse(FSettings.LoadFromText('{ not json', Err));
  AssertTrue('reports why', Err <> '');
  AssertNear('share', DefaultNameColumnShare, FSettings.NameColumnShare);
end;

procedure TTestSettings.TestWrongFormatKeepsDefaults;
var
  Err: string;
begin
  AssertFalse(FSettings.LoadFromText('{"format": "other", "version": 1, "nameColumnShare": 0.3}', Err));
  AssertTrue('reports why', Err <> '');
  AssertNear('share', DefaultNameColumnShare, FSettings.NameColumnShare);
end;

procedure TTestSettings.TestNewerVersionKeepsDefaults;
var
  Err: string;
begin
  AssertFalse(FSettings.LoadFromText('{"format": "opensloper-settings", "version": 999, "nameColumnShare": 0.3}', Err));
  AssertNear('share', DefaultNameColumnShare, FSettings.NameColumnShare);
end;

procedure TTestSettings.TestOutOfRangeShareIsIgnored;
var
  Err: string;
begin
  AssertTrue(Err, FSettings.LoadFromText('{"format": "opensloper-settings", "version": 1, "nameColumnShare": 7}', Err));
  AssertNear('share', DefaultNameColumnShare, FSettings.NameColumnShare);
end;

procedure TTestSettings.TestMissingShareIsDefault;
var
  Err: string;
begin
  FSettings.NameColumnShare := 0.3;
  AssertTrue(Err, FSettings.LoadFromText('{"format": "opensloper-settings", "version": 1}', Err));
  AssertNear('share', DefaultNameColumnShare, FSettings.NameColumnShare);
end;

initialization
  RegisterTest(TTestSettings);

end.
