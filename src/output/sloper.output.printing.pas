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

// Printing a layout directly: the same PDF as Export PDF, handed to the
// system's print service with scaling off, so the print is the export. On
// Linux and macOS that is CUPS (lpstat lists the printers, lp prints); on
// Windows the PDF goes to the print command of
// the default PDF viewer, which prints on the default printer. The PDF is
// written to the user's own runtime folder first: lp copies it into the queue
// before it returns, and the viewer reads it later.
unit Sloper.Output.Printing;

{$mode ObjFPC}{$H+}

interface

uses
  SysUtils, Sloper.Output.Layout;

type
  // ppCover prints the cover alone, to measure the test square before
  // printing the rest; ppTiles the rest. Both are for tiled pages only.
  TPrintPages = (ppAll, ppCover, ppTiles);

  TPrintRequest = record
    // Empty for the system's default printer
    Printer: string;
    Copies: integer;
    Pages: TPrintPages;
    // The job's name in the print queue
    Title: string;
  end;

// Whether this system can print directly, and whether it lets the printer,
// the copies and the pages be chosen (CUPS can; Windows only prints the lot
// once on the default printer)
function CanPrint: boolean;
function CanChoosePrintOptions: boolean;
// The printers the system knows, and its default among them ('' for none)
procedure ListPrinters(out Printers: TStringArray; out DefaultPrinter: string);
// The pages the PDF has: the cover and each tile printed, or the one sheet
function PrintedPageCount(Layout: TLayout): integer;
// Refuses as Export PDF does, or sends the layout to the printer. Reply is
// what the print service said, or why nothing was printed.
function PrintLayout(Layout: TLayout; const Request: TPrintRequest; out Reply: string): boolean;

// The parts, for the tests
// lpstat -a: one printer per line, its name first
function ParsePrinterList(const Output: string): TStringArray;
// lpstat -d: "system default destination: NAME", when NAME is one of Printers
function ParseDefaultPrinter(const Output: string; const Printers: TStringArray): string;
// The CUPS media of a sheet: the paper's name when it has one CUPS knows,
// else Custom.WIDTHxHEIGHTmm
function MediaName(const Paper: string; AWidth, AHeight: double): string;
function PrintMedia(Layout: TLayout): string;
// lp's arguments, which print FileName, a PDF of PageCount pages
function PrintArguments(const Request: TPrintRequest; const Media, FileName: string; PageCount: integer): TStringArray;

resourcestring
  rsPrintNoSystem = 'No print service was found (CUPS lp). Export the PDF and print it at 100% (actual size) from a PDF viewer.';
  rsPrintFailed = 'The printer did not take the job: %s';
  rsPrintNoReply = 'the print service stopped without saying why';
  rsPrintWindowsFailed =
    'Windows could not print the PDF, as no PDF viewer that prints from the Explorer is set up. ' +
    'Export the PDF and print it at 100% (actual size) from a PDF viewer.';
  rsPrintWindowsSent = 'Sent to the default PDF viewer to print';

implementation

uses
  Classes, Math, Process,
  {$IFDEF WINDOWS}
  Windows, ShellApi,
  {$ENDIF}
  Sloper.Core.AppPaths, Sloper.Output.LayoutPDF, Sloper.Output.Tiling;

const
  LPSTAT_PROGRAM = 'lpstat';
  LP_PROGRAM = 'lp';
  // Where CUPS puts them (/usr/bin), for a desktop app started without a full PATH
  CUPS_PROGRAM_DIRS: array[0..1] of string = ('usr', 'bin');
  // CUPS names these papers as the layout does
  CUPS_PAPERS: array[0..2] of string = ('A4', 'A3', 'Letter');
  // Custom media sizes are given to a tenth of a millimetre
  MEDIA_DECIMALS = '0.#';
  READ_BUFFER_SIZE = 4096;
  // Between checks of a program that has not finished, in milliseconds
  WAIT_STEP = 10;
  COVER_PAGE = 1;
  PRINT_FILE_SUFFIX = '-print.pdf';
  PRINT_FILE_UNSAVED = 'layout';
{$IFDEF WINDOWS}
  // ShellExecute's results up to this are errors
  SHELL_EXECUTE_LAST_ERROR = 32;
{$ENDIF}

function ToolPath(const AName: string): string;
var
  Usual: string;
begin
  Result := ExeSearch(AName, SysUtils.GetEnvironmentVariable('PATH'));
  Usual := PathDelim + ConcatPaths([CUPS_PROGRAM_DIRS[0], CUPS_PROGRAM_DIRS[1], AName]);
  if (Result = '') and FileExists(Usual) then
    Result := Usual;
end;

// Runs a program with the C locale, so its replies can be read, collecting
// what it writes; False when it could not be started
function RunTool(const Executable: string; const Arguments: array of string; out Output: string; out ExitCode: integer): boolean;
var
  Tool: TProcess;
  Buffer: array[0..READ_BUFFER_SIZE - 1] of byte;
  Collected: TStringStream;
  Argument: string;
  Index, Count: integer;

  procedure Drain;
  begin
    while Tool.Output.NumBytesAvailable > 0 do
    begin
      Count := Tool.Output.Read(Buffer[0], Min(READ_BUFFER_SIZE, Tool.Output.NumBytesAvailable));
      if Count <= 0 then
        Break;
      Collected.WriteBuffer(Buffer[0], Count);
    end;
  end;

begin
  Output := '';
  ExitCode := -1;
  Collected := TStringStream.Create('');
  Tool := TProcess.Create(nil);
  try
    Tool.Executable := Executable;
    for Argument in Arguments do
      Tool.Parameters.Add(Argument);
    for Index := 1 to GetEnvironmentVariableCount do
      Tool.Environment.Add(GetEnvironmentString(Index));
    Tool.Environment.Add('LC_ALL=C');
    Tool.Options := [poUsePipes, poStderrToOutPut, poNoConsole];
    try
      Tool.Execute;
    except
      on Failure: EProcess do
      begin
        Output := Failure.Message;
        Exit(False);
      end;
    end;
    Tool.CloseInput;
    while Tool.Running do
    begin
      Drain;
      Sleep(WAIT_STEP);
    end;
    Drain;
    Output := Trim(Collected.DataString);
    ExitCode := Tool.ExitCode;
    Result := True;
  finally
    FreeAndNil(Tool);
    FreeAndNil(Collected);
  end;
end;

function CanPrint: boolean;
begin
  {$IFDEF WINDOWS}
  Result := True;
  {$ELSE}
  Result := ToolPath(LP_PROGRAM) <> '';
  {$ENDIF}
end;

function CanChoosePrintOptions: boolean;
begin
  {$IFDEF WINDOWS}
  Result := False;
  {$ELSE}
  Result := True;
  {$ENDIF}
end;

function ParsePrinterList(const Output: string): TStringArray;
var
  Lines: TStringList;
  Line, PrinterName: string;
begin
  Result := nil;
  Lines := TStringList.Create;
  try
    Lines.Text := Output;
    for Line in Lines do
    begin
      // Continuation lines are indented
      if (Line = '') or (Line[1] <= ' ') then
        Continue;
      PrinterName := Line;
      if Pos(' ', PrinterName) > 0 then
        PrinterName := Copy(PrinterName, 1, Pos(' ', PrinterName) - 1);
      Insert(PrinterName, Result, Length(Result));
    end;
  finally
    FreeAndNil(Lines);
  end;
end;

function ParseDefaultPrinter(const Output: string; const Printers: TStringArray): string;
var
  Named, PrinterName: string;
begin
  Result := '';
  if Pos(':', Output) = 0 then
    Exit;
  Named := Trim(Copy(Output, LastDelimiter(':', Output) + 1, Length(Output)));
  for PrinterName in Printers do
    if SameText(PrinterName, Named) then
      Exit(PrinterName);
end;

procedure ListPrinters(out Printers: TStringArray; out DefaultPrinter: string);
var
  Lpstat, Output: string;
  ExitCode: integer;
begin
  Printers := nil;
  DefaultPrinter := '';
  Lpstat := ToolPath(LPSTAT_PROGRAM);
  if Lpstat = '' then
    Exit;
  if RunTool(Lpstat, ['-a'], Output, ExitCode) and (ExitCode = 0) then
    Printers := ParsePrinterList(Output);
  if (Length(Printers) > 0) and RunTool(Lpstat, ['-d'], Output, ExitCode) and (ExitCode = 0) then
    DefaultPrinter := ParseDefaultPrinter(Output, Printers);
end;

function PrintedPageCount(Layout: TLayout): integer;
var
  Pages: TTilePageArray;
  Page: TTilePage;
  Rows, Columns: integer;
begin
  Result := 1;
  if Layout.Output.Kind <> okTiled then
    Exit;
  Pages := Layout.Pages(Layout.PlacedPieces, Rows, Columns);
  for Page in Pages do
    if not Page.Blank and not Page.Excluded then
      Inc(Result);
end;

function MediaName(const Paper: string; AWidth, AHeight: double): string;
var
  Known: string;
  Numbers: TFormatSettings;
begin
  for Known in CUPS_PAPERS do
    if Known = Paper then
      Exit(Paper);
  Numbers := DefaultFormatSettings;
  Numbers.DecimalSeparator := '.';
  Result := 'Custom.' + FormatFloat(MEDIA_DECIMALS, AWidth, Numbers) + 'x' + FormatFloat(MEDIA_DECIMALS, AHeight, Numbers) + 'mm';
end;

function PrintMedia(Layout: TLayout): string;
var
  Pages: TTilePageArray;
  Rows, Columns: integer;
begin
  if Layout.Output.Kind = okTiled then
    Exit(MediaName(Layout.Output.Paper, Layout.Output.Tiles.PaperWidth, Layout.Output.Tiles.PaperHeight));
  // The one sheet, sized as the PDF sizes it
  Pages := Layout.Pages(Layout.PlacedPieces, Rows, Columns);
  Result := MediaName('', OneSheetWidth(Layout, Pages[0].Area.MaxX - Pages[0].Area.MinX),
    LargeSheetLength(Layout, Pages[0].Area.MaxY - Pages[0].Area.MinY));
end;

function PrintArguments(const Request: TPrintRequest; const Media, FileName: string; PageCount: integer): TStringArray;

  procedure Add(const Values: array of string);
  var
    Value: string;
  begin
    for Value in Values do
      Insert(Value, Result, Length(Result));
  end;

begin
  Result := nil;
  if Request.Printer <> '' then
    Add(['-d', Request.Printer]);
  Add(['-n', IntToStr(Max(1, Request.Copies))]);
  if Request.Title <> '' then
    Add(['-t', Request.Title]);
  // print-scaling for CUPS 2 and IPP printers, fit-to-page for older CUPS
  Add(['-o', 'print-scaling=none', '-o', 'fit-to-page=false', '-o', 'media=' + Media]);
  case Request.Pages of
    ppCover: Add(['-o', 'page-ranges=' + IntToStr(COVER_PAGE)]);
    ppTiles: if PageCount > COVER_PAGE then
        Add(['-o', 'page-ranges=' + IntToStr(COVER_PAGE + 1) + '-' + IntToStr(PageCount)]);
  end;
  Add([FileName]);
end;

// The PDF in the user's own runtime folder, for the print service to read
function WritePrintFile(Layout: TLayout; out FileName, ErrorMessage: string): boolean;
var
  Stem: string;
begin
  Stem := ChangeFileExt(ExtractFileName(Layout.FileName), '');
  if Stem = '' then
    Stem := PRINT_FILE_UNSAVED;
  FileName := ConcatPaths([TAppPaths.ForceDir(TAppPaths.RuntimeDir), Stem + PRINT_FILE_SUFFIX]);
  Result := WriteBytesToFile(FileName, LayoutToPDF(Layout), ErrorMessage);
end;

{$IFDEF WINDOWS}
function PrintLayout(Layout: TLayout; const Request: TPrintRequest; out Reply: string): boolean;
var
  FileName: string;
begin
  Reply := Layout.Refusal;
  if Reply <> '' then
    Exit(False);
  if not WritePrintFile(Layout, FileName, Reply) then
    Exit(False);
  // The viewer reads the file after this returns, so it is left for the next print to replace
  Result := PtrUInt(ShellExecuteW(0, 'print', PWideChar(UnicodeString(FileName)), nil, nil, SW_HIDE)) > SHELL_EXECUTE_LAST_ERROR;
  if Result then
    Reply := rsPrintWindowsSent
  else
    Reply := rsPrintWindowsFailed;
end;

{$ELSE}

function PrintLayout(Layout: TLayout; const Request: TPrintRequest; out Reply: string): boolean;
var
  Lp, Output, FileName: string;
  ExitCode: integer;
begin
  Reply := Layout.Refusal;
  if Reply <> '' then
    Exit(False);
  Lp := ToolPath(LP_PROGRAM);
  if Lp = '' then
  begin
    Reply := rsPrintNoSystem;
    Exit(False);
  end;
  if not WritePrintFile(Layout, FileName, Reply) then
    Exit(False);
  try
    Result := RunTool(Lp, PrintArguments(Request, PrintMedia(Layout), FileName, PrintedPageCount(Layout)), Output, ExitCode) and (ExitCode = 0);
  finally
    DeleteFile(FileName);
  end;
  if Result then
    Reply := Output
  else
  begin
    if Output = '' then
      Output := rsPrintNoReply;
    Reply := Format(rsPrintFailed, [Output]);
  end;
end;

{$ENDIF}

end.
