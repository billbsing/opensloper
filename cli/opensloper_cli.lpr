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
  Sloper.Core.PatternCheck;

const
  ExitProblems = 1;
  ExitFailure = 2;

resourcestring
  rsDescription = 'Export and check OpenSloper patterns.';
  rsOptHelp = 'Show this help';
  rsOptVersion = 'Show the version';
  rsOptMeasurements = 'Measurement file (.slm); default: the one the pattern names';
  rsOptJSON = 'check: print every computed value as JSON';
  rsArgCommand = 'Command to run';
  rsArgPattern = 'Pattern file (.sloper)';
  rsCmdCheck = 'Evaluate a pattern and report problems';
  rsCmdExport = 'Export a pattern for one or more measurement files';
  rsNotImplemented = 'The %s command is not implemented yet.';
  rsNeedPattern = 'The %s command needs a pattern file.';
  rsLoadFailed = '%s: %s';
  rsFileNotFound = 'File not found: %s';
  rsCheckWith = '%s with %s';
  rsCheckNoSet = '%s with no measurement set';
  rsCheckClean = '%s: no problems (%d objects)';
  rsCheckProblems = '%s: problems found: %d';
  rsCheckBlocked = 'Blocked by these problems: %d more';

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
  function RunCheck(const PatternFile, MeasurementOption: string; AsJSON: boolean): integer;
  var
    Pattern: TPattern;
    Measurements: TMeasurementSet;
    MeasurementPath, Err, Title, Problem: string;
    Problems: TStringArray;
    BlockedCount: integer;
    Report: TJSONObject;
  begin
    Measurements := TMeasurementSet.Create;
    Pattern := TPattern.Create;
    try
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
    Parser.AddOption('json', '', '--json', rsOptJSON, '', avSwitch);
    Command := Parser.AddArgument('command', rsArgCommand, 'command', asRequired, avChoice);
    Command.AddChoice('check', rsCmdCheck);
    Command.AddChoice('export', rsCmdExport);
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
    if CommandName = 'check' then
    begin
      if PatternFile = '' then
      begin
        WriteLn(StdErr, Format(rsNeedPattern, [CommandName]));
        ExitCode := ExitFailure;
        Exit;
      end;
      ExitCode := RunCheck(PatternFile, Parser.GetOptionValueAsString('measurements'), Parser.IsOption('json'));
    end
    else
    begin
      WriteLn(StdErr, Format(rsNotImplemented, [CommandName]));
      ExitCode := ExitFailure;
    end;
  finally
    FreeAndNil(Parser);
  end;
end.
