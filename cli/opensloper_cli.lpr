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

// opensloper-cli: export and check patterns from the command line.
// Exit codes: 0 success, 1 the pattern has problems, 2 a usage or file error.
program opensloper_cli;

{$mode ObjFPC}{$H+}

uses
  {$IFDEF UNIX}
  cthreads,
  {$ENDIF}
  Sloper.Core.CodePage,
  SysUtils,
  fpjson,
  ConsoleTools,
  Sloper.Core.Version,
  Sloper.Core.JSON,
  Sloper.Core.Measurements,
  Sloper.Core.Pattern,
  Sloper.Core.PatternFile,
  Sloper.Core.PatternCheck,
  Sloper.Output.Layout,
  Sloper.Output.LayoutPDF,
  Sloper.API.Server;

const
  ExitProblems = 1;
  ExitFailure = 2;

resourcestring
  rsDescription = 'Export and check OpenSloper patterns.';
  rsOptHelp = 'Show this help';
  rsOptVersion = 'Show the version';
  rsOptMeasurements = 'Measurement file (.slm); default: the one the pattern names';
  rsOptSize = 'check, layout: the size to use from a size table; default: the first';
  rsOptJSON = 'check: print every computed value as JSON';
  rsOptOutput = 'layout, export: the file to write';
  rsArgCommand = 'Command to run';
  rsArgPattern = 'Pattern file (.sloper), or layout file (.slayout) to export';
  rsCmdCheck = 'Evaluate a pattern and report problems';
  rsCmdExport = 'Export a layout file as a tiled PDF';
  rsCmdLayout = 'Start a layout file for a pattern, with every piece placed';
  rsCmdServe = 'Answer JSON-RPC 2.0 on stdin and stdout, one message per line';
  rsNeedPattern = 'The %s command needs a pattern file.';
  rsLoadFailed = '%s: %s';
  rsFileNotFound = 'File not found: %s';
  rsCheckWith = '%s with %s';
  rsCheckNoSet = '%s with no measurement set';
  rsCheckClean = '%s: no problems (%d objects)';
  rsCheckProblems = '%s: problems found: %d';
  rsCheckBlocked = 'Blocked by these problems: %d more';
  rsExportNeedsLayout = 'The export command needs a layout file (%s). Make one with the layout command.';
  rsWroteFile = 'Wrote %s';
  rsWarning = 'Warning: %s';

  // False, with a message, when FileName does not exist; the load messages
  // would otherwise name it several times
  function CheckFileExists(const FileName: string): boolean;
  begin
    Result := FileExists(FileName);
    if not Result then
      WriteLn(StdErr, Format(rsFileNotFound, [FileName]));
  end;

  // Loads and evaluates the pattern, then prints its problems, or its report
  // as JSON. Returns the exit code.
  function RunCheck(const PatternFile, MeasurementOption, SizeOption: string; AsJSON: boolean): integer;
  var
    Pattern: TPattern;
    Measurements: TMeasurementSet;
    MeasurementPath, Err, Title, Problem: string;
    Problems: TStringArray;
    BlockedCount: integer;
    Report: TJSONObject;
  begin
    Measurements := nil;
    Pattern := nil;
    try
      Measurements := TMeasurementSet.Create;
      Pattern := TPattern.Create;
      if not CheckFileExists(PatternFile) then
        Exit(ExitFailure);
      if not LoadPatternFromFile(Pattern, PatternFile, Err) then
      begin
        WriteLn(StdErr, Format(rsLoadFailed, [PatternFile, Err]));
        Exit(ExitFailure);
      end;
      MeasurementPath := MeasurementOption;
      if MeasurementPath = '' then
        MeasurementPath := MeasurementFilePath(Pattern, PatternFile);
      if MeasurementPath <> '' then
      begin
        if not CheckFileExists(MeasurementPath) then
          Exit(ExitFailure);
        if not Measurements.LoadFromFile(MeasurementPath, Err) then
        begin
          WriteLn(StdErr, Format(rsLoadFailed, [MeasurementPath, Err]));
          Exit(ExitFailure);
        end;
        if (SizeOption <> '') and not Measurements.SelectSize(SizeOption) then
        begin
          WriteLn(StdErr, Format(rsMeasurementUnknownSize, [SizeOption]));
          Exit(ExitFailure);
        end;
        Pattern.Measurements := Measurements;
        Title := Format(rsCheckWith, [ExtractFileName(PatternFile), ExtractFileName(MeasurementPath)]);
      end
      else
        Title := Format(rsCheckNoSet, [ExtractFileName(PatternFile)]);

      Pattern.Evaluate;
      Problems := PatternProblems(Pattern, BlockedCount);
      if AsJSON then
      begin
        Report := PatternReport(Pattern, ExtractFileName(PatternFile), ExtractFileName(MeasurementPath));
        try
          Write(JSONToText(Report));
        finally
          FreeAndNil(Report);
        end;
      end
      else if Length(Problems) = 0 then
        WriteLn(Format(rsCheckClean, [Title, Pattern.ObjectCount]))
      else
      begin
        WriteLn(Format(rsCheckProblems, [Title, Length(Problems)]));
        for Problem in Problems do
          WriteLn('  ', Problem);
        if BlockedCount > 0 then
          WriteLn('  ', Format(rsCheckBlocked, [BlockedCount]));
      end;
      if (Length(Problems) > 0) or (BlockedCount > 0) then
        Result := ExitProblems
      else
        Result := 0;
    finally
      // The pattern reads the measurement set, so it goes first
      FreeAndNil(Pattern);
      FreeAndNil(Measurements);
    end;
  end;

  // Starts a layout beside the pattern, with every piece placed in rows
  function RunLayout(const PatternFile, MeasurementOption, SizeOption, OutputOption: string): integer;
  var
    Layout: TLayout;
    Target, Err: string;
    Problem: TLayoutProblem;
  begin
    Target := OutputOption;
    if Target = '' then
      Target := ChangeFileExt(PatternFile, LayoutExtension);
    Layout := TLayout.Create;
    try
      Layout.FileName := Target;
      Layout.Name := ChangeFileExt(ExtractFileName(PatternFile), '');
      Layout.AddSource(ExtractRelativePath(ExpandFileName(ExtractFilePath(Target)), ExpandFileName(PatternFile)), MeasurementOption, SizeOption);
      Layout.LoadSources;
      Layout.PlaceNewPieces;
      Layout.UseDefaultTitle;
      if not Layout.SaveToFile(Target, Err) then
      begin
        WriteLn(StdErr, Err);
        Exit(ExitFailure);
      end;
      WriteLn(Format(rsWroteFile, [Target]));
      for Problem in Layout.Problems do
        WriteLn(StdErr, Format(rsWarning, [Problem.Text]));
      Result := 0;
    finally
      FreeAndNil(Layout);
    end;
  end;

  function RunExport(const LayoutFile, OutputOption: string): integer;
  var
    Layout: TLayout;
    Target, Err: string;
    Problem: TLayoutProblem;
  begin
    if ExtractFileExt(LayoutFile) <> LayoutExtension then
    begin
      WriteLn(StdErr, Format(rsExportNeedsLayout, [LayoutExtension]));
      Exit(ExitFailure);
    end;
    if not CheckFileExists(LayoutFile) then
      Exit(ExitFailure);
    Target := OutputOption;
    if Target = '' then
      Target := ChangeFileExt(LayoutFile, '.pdf');
    Layout := TLayout.Create;
    try
      if not Layout.LoadFromFile(LayoutFile, Err) then
      begin
        WriteLn(StdErr, Format(rsLoadFailed, [LayoutFile, Err]));
        Exit(ExitFailure);
      end;
      Layout.LoadSources;
      if not ExportLayoutPDF(Layout, Target, Err) then
      begin
        WriteLn(StdErr, Err);
        Exit(ExitProblems);
      end;
      for Problem in Layout.Problems do
        WriteLn(StdErr, Format(rsWarning, [Problem.Text]));
      WriteLn(Format(rsWroteFile, [Target]));
      Result := 0;
    finally
      FreeAndNil(Layout);
    end;
  end;

  // The Automation API: one request a line, until stdin closes
  procedure RunServe;
  var
    Server: TApiServer;
    Line, Reply: string;
  begin
    Server := TApiServer.Create;
    try
      while not EOF(Input) do
      begin
        ReadLn(Input, Line);
        if Trim(Line) = '' then
          Continue;
        Reply := Server.HandleLine(Line);
        if Reply <> '' then
        begin
          WriteLn(Output, Reply);
          Flush(Output);
        end;
      end;
    finally
      FreeAndNil(Server);
    end;
  end;

var
  Parser: TArgumentParser;
  Command: TArgument;
  CommandName, PatternFile: string;
begin
  Parser := TArgumentParser.Create;
  try
    Parser.Title := 'opensloper-cli';
    Parser.Description := rsDescription;
    Parser.AddOption('help', '-h', '--help', rsOptHelp, '', avSwitch);
    Parser.AddOption('version', '-V', '--version', rsOptVersion, '', avSwitch);
    Parser.AddOption('measurements', '-m', '--measurements', rsOptMeasurements, 'file');
    Parser.AddOption('size', '-s', '--size', rsOptSize, 'size');
    Parser.AddOption('json', '', '--json', rsOptJSON, '', avSwitch);
    Parser.AddOption('output', '-o', '--output', rsOptOutput, 'file');
    Command := Parser.AddArgument('command', rsArgCommand, 'command', asRequired, avChoice);
    Command.AddChoice('check', rsCmdCheck);
    Command.AddChoice('export', rsCmdExport);
    Command.AddChoice('layout', rsCmdLayout);
    Command.AddChoice('serve', rsCmdServe);
    Parser.AddArgument('pattern', rsArgPattern, 'pattern', asOptional);

    try
      Parser.Parse;
      if Parser.IsOption('help') then
      begin
        Parser.ShowHelp;
        Exit;
      end;
      if Parser.IsOption('version') then
      begin
        WriteLn(AppName, ' ', AppVersion);
        Exit;
      end;
      Parser.Validate;
    except
      on Failure: EArgumentParserException do
      begin
        WriteLn(StdErr, Failure.Message);
        ExitCode := ExitFailure;
        Exit;
      end;
    end;

    CommandName := Parser.GetArgumentValueAsString('command');
    PatternFile := Parser.GetArgumentValueAsString('pattern');
    if CommandName = 'serve' then
    begin
      RunServe;
      Exit;
    end;
    if PatternFile = '' then
    begin
      WriteLn(StdErr, Format(rsNeedPattern, [CommandName]));
      ExitCode := ExitFailure;
      Exit;
    end;
    if CommandName = 'check' then
      ExitCode := RunCheck(PatternFile, Parser.GetOptionValueAsString('measurements'), Parser.GetOptionValueAsString('size'),
        Parser.IsOption('json'))
    else if CommandName = 'layout' then
      ExitCode := RunLayout(PatternFile, Parser.GetOptionValueAsString('measurements'), Parser.GetOptionValueAsString('size'),
        Parser.GetOptionValueAsString('output'))
    else
      ExitCode := RunExport(PatternFile, Parser.GetOptionValueAsString('output'));
  finally
    FreeAndNil(Parser);
  end;
end.
