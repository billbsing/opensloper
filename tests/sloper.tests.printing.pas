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

// Printing from the publish app: reading lpstat, the media and the lp
// command line, and the gate that refuses a layout Export PDF would refuse.
// Nothing here sends a job to a printer.
unit Sloper.Tests.Printing;

{$mode ObjFPC}{$H+}

interface

uses
  fpcunit, testregistry, Sloper.Tests.TestCase;

type
  TTestPrinting = class(TOSTestCase)
  published
    procedure TestPrinterList;
    procedure TestPrinterListEmpty;
    procedure TestDefaultPrinter;
    procedure TestNoDefaultPrinter;
    procedure TestNamedMedia;
    procedure TestCustomMedia;
    procedure TestTiledCustomPaperMedia;
    procedure TestArgumentsTurnScalingOff;
    procedure TestArgumentsDefaultPrinter;
    procedure TestArgumentsCoverOnly;
    procedure TestArgumentsTilesOnly;
    procedure TestOneSheetIsOnePage;
    procedure TestRefusedLayoutDoesNotPrint;
  end;

implementation

uses
  SysUtils, Sloper.Output.Layout, Sloper.Output.Printing;

function Joined(const Parts: TStringArray): string;
begin
  Result := string.Join(' ', Parts);
end;

function Request(const Printer: string; Copies: integer; Pages: TPrintPages): TPrintRequest;
begin
  Result := Default(TPrintRequest);
  Result.Printer := Printer;
  Result.Copies := Copies;
  Result.Pages := Pages;
end;

procedure TTestPrinting.TestPrinterList;
var
  Printers: TStringArray;
begin
  Printers := ParsePrinterList('HP_LaserJet accepting requests since Thu 12 Nov 2026 10:00:00 AM' + LineEnding +
    '  extra detail' + LineEnding + LineEnding + 'Plotter accepting requests since Fri 13 Nov 2026 09:00:00 AM' + LineEnding);
  AssertEquals(2, Length(Printers));
  AssertEquals('HP_LaserJet', Printers[0]);
  AssertEquals('Plotter', Printers[1]);
end;

procedure TTestPrinting.TestPrinterListEmpty;
begin
  AssertEquals(0, Length(ParsePrinterList('')));
end;

procedure TTestPrinting.TestDefaultPrinter;
begin
  AssertEquals('Plotter', ParseDefaultPrinter('system default destination: plotter', ['HP_LaserJet', 'Plotter']));
end;

procedure TTestPrinting.TestNoDefaultPrinter;
begin
  AssertEquals('', ParseDefaultPrinter('no system default destination', ['HP_LaserJet']));
  // A name not in the list is not offered
  AssertEquals('', ParseDefaultPrinter('system default destination: Gone', ['HP_LaserJet']));
end;

procedure TTestPrinting.TestNamedMedia;
begin
  AssertEquals('A4', MediaName('A4', 210, 297));
  AssertEquals('Letter', MediaName('Letter', 215.9, 279.4));
end;

procedure TTestPrinting.TestCustomMedia;
begin
  AssertEquals('Custom.914x1234.5mm', MediaName('', 914, 1234.5));
  AssertEquals('Custom.300x400mm', MediaName(CUSTOM_PAPER, 300, 400));
end;

procedure TTestPrinting.TestTiledCustomPaperMedia;
var
  Layout: TLayout;
begin
  Layout := TLayout.Create;
  try
    Layout.Output.Kind := okTiled;
    Layout.Output.Paper := CUSTOM_PAPER;
    Layout.Output.Tiles.PaperWidth := 250;
    Layout.Output.Tiles.PaperHeight := 350;
    AssertEquals('Custom.250x350mm', PrintMedia(Layout));
  finally
    FreeAndNil(Layout);
  end;
end;

procedure TTestPrinting.TestArgumentsTurnScalingOff;
var
  Job: TPrintRequest;
begin
  Job := Request('HP', 2, ppAll);
  Job.Title := 'Skirt';
  AssertEquals('-d HP -n 2 -t Skirt -o print-scaling=none -o fit-to-page=false -o media=A4 file.pdf',
    Joined(PrintArguments(Job, 'A4', 'file.pdf', 5)));
end;

procedure TTestPrinting.TestArgumentsDefaultPrinter;
var
  Arguments: string;
begin
  Arguments := Joined(PrintArguments(Request('', 0, ppAll), 'A4', 'file.pdf', 5));
  AssertEquals('-n 1 -o print-scaling=none -o fit-to-page=false -o media=A4 file.pdf', Arguments);
end;

procedure TTestPrinting.TestArgumentsCoverOnly;
begin
  AssertTrue(Joined(PrintArguments(Request('HP', 1, ppCover), 'A4', 'file.pdf', 5)).EndsWith('-o page-ranges=1 file.pdf'));
end;

procedure TTestPrinting.TestArgumentsTilesOnly;
begin
  AssertTrue(Joined(PrintArguments(Request('HP', 1, ppTiles), 'A4', 'file.pdf', 5)).EndsWith('-o page-ranges=2-5 file.pdf'));
end;

procedure TTestPrinting.TestOneSheetIsOnePage;
var
  Layout: TLayout;
begin
  Layout := TLayout.Create;
  try
    Layout.Output.Kind := okLarge;
    AssertEquals(1, PrintedPageCount(Layout));
  finally
    FreeAndNil(Layout);
  end;
end;

procedure TTestPrinting.TestRefusedLayoutDoesNotPrint;
var
  Layout: TLayout;
  Reply: string;
begin
  Layout := TLayout.Create;
  try
    AssertFalse(PrintLayout(Layout, Request('', 1, ppAll), Reply));
    AssertEquals(Layout.Refusal, Reply);
    AssertTrue(Reply <> '');
  finally
    FreeAndNil(Layout);
  end;
end;

initialization
  RegisterTest(TTestPrinting);
end.
