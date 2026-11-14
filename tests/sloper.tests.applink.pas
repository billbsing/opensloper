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

// The apps' link to each other without the windows: a link listening on an
// endpoint of its own kind, and the message the design window's Publish…
// sends it. The link runs its handler on its own thread here; the test thread
// waits for the reply meanwhile.
unit Sloper.Tests.AppLink;

{$mode ObjFPC}{$H+}

interface

uses
  SysUtils, fpcunit, testregistry, fpjson, Sloper.Tests.TestCase, Sloper.API.AppLink;

type
  TTestAppLink = class(TOSTestCase)
  private
    FFolder: string;
    FLink: TAppLink;
    FReceived: string;
    function Message(const Method: string; Params: TJSONObject): boolean;
    procedure Listen;
    function Show(const LayoutFile: string): boolean;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestNoneListening;
    procedure TestShownOnlyByItsWindow;
    procedure TestKindsKeptApart;
    procedure TestEndpointRemovedOnStop;
    procedure TestStaleEndpointSkipped;
  end;

implementation

uses
  Sloper.Core.JSON, Sloper.API.Endpoint, Sloper.API.Listener;

const
  OPEN_LAYOUT = 'skirt.slayout';
  STALE_PID = 999999;

procedure TTestAppLink.SetUp;
begin
  FFolder := ConcatPaths([GetTempDir, 'opensloper-applink-test']);
  UseAutomationFolder(FFolder);
  FLink := nil;
  FReceived := '';
end;

procedure TTestAppLink.TearDown;
begin
  FreeAndNil(FLink);
  UseAutomationFolder('');
  RemoveDir(FFolder);
end;

// As a publish window with OPEN_LAYOUT open answers
function TTestAppLink.Message(const Method: string; Params: TJSONObject): boolean;
var
  LayoutFile: string;
begin
  FReceived := Method + ' ' + Params.AsJSON;
  Result := (Method = APP_LINK_SHOW) and GetJSONString(Params, APP_LINK_LAYOUT_PARAM, LayoutFile) and
    (LayoutFile = OPEN_LAYOUT);
end;

procedure TTestAppLink.Listen;
var
  Err: string;
begin
  FLink := TAppLink.Start(PUBLISH_KIND, @Message, False, Err);
  AssertTrue(Err, Assigned(FLink));
end;

function TTestAppLink.Show(const LayoutFile: string): boolean;
var
  Params: TJSONObject;
begin
  Params := TJSONObject.Create([APP_LINK_LAYOUT_PARAM, LayoutFile]);
  try
    Result := SendToApp(PUBLISH_KIND, APP_LINK_SHOW, Params);
  finally
    FreeAndNil(Params);
  end;
end;

// Publish… then starts a new window
procedure TTestAppLink.TestNoneListening;
begin
  AssertFalse(Show(OPEN_LAYOUT));
end;

procedure TTestAppLink.TestShownOnlyByItsWindow;
begin
  Listen;
  AssertTrue('its layout', Show(OPEN_LAYOUT));
  AssertEquals('show { "layout" : "' + OPEN_LAYOUT + '" }', FReceived);
  AssertFalse('another layout', Show('dress.slayout'));
end;

// A client looking for automation never finds a publish window, nor the other way round
procedure TTestAppLink.TestKindsKeptApart;
var
  Automation: TAutomationListener;
  Err: string;
begin
  Listen;
  Automation := TAutomationListener.Start(nil, nil, False, Err);
  try
    AssertTrue(Err, Assigned(Automation));
    AssertEquals('automation', 1, Length(ReadAutomationEndpoints));
    AssertEquals('automation file', Automation.Endpoint.InfoPath, ReadAutomationEndpoints[0].InfoPath);
    AssertEquals('publish', 1, Length(ReadAutomationEndpoints(PUBLISH_KIND)));
    AssertEquals('publish file', FLink.Listener.Endpoint.InfoPath, ReadAutomationEndpoints(PUBLISH_KIND)[0].InfoPath);
  finally
    FreeAndNil(Automation);
  end;
end;

procedure TTestAppLink.TestEndpointRemovedOnStop;
var
  Endpoint: TAutomationEndpoint;
begin
  Listen;
  Endpoint := FLink.Listener.Endpoint;
  FreeAndNil(FLink);
  AssertFalse('endpoint file', FileExists(Endpoint.InfoPath));
  AssertEquals(0, Length(ReadAutomationEndpoints(PUBLISH_KIND)));
  AssertFalse(Show(OPEN_LAYOUT));
end;

// A file left by a window that crashed, with nothing listening
procedure TTestAppLink.TestStaleEndpointSkipped;
var
  Folder, Err: string;
  Stale: TAutomationEndpoint;
begin
  AssertTrue(Err, PrepareAutomationFolder(Folder, Err));
  Stale := AutomationEndpointFor(Folder, STALE_PID, PUBLISH_KIND);
  Stale.Token := 'stale';
  AssertTrue(Err, WriteAutomationEndpoint(Stale, Err));
  try
    Listen;
    AssertTrue('the live window', Show(OPEN_LAYOUT));
    FreeAndNil(FLink);
    AssertFalse('only the stale file', Show(OPEN_LAYOUT));
    AssertFalse('the stale file removed', FileExists(Stale.InfoPath));
  finally
    DeleteFile(Stale.InfoPath);
  end;
end;

initialization
  RegisterTest(TTestAppLink);
end.
