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
  Sloper.Core.Drafts,
  Sloper.Core.Pattern,
  Sloper.Core.PatternFile,
  Sloper.Core.PatternCheck,
  Sloper.Core.Settings,
  Sloper.Output.DraftSVG,
  Sloper.Output.Layout,
  Sloper.Output.LayoutExport,
  Sloper.Output.Packing,
  Sloper.API.Server;

const
  ExitProblems = 1;
  ExitFailure = 2;

resourcestring
  rsDescription = 'Export and check OpenSloper patterns.';
  rsOptHelp = 'Show this help';
  rsOptVersion = 'Show the version';
  rsOptMeasurements = 'Measurement file (.slm); default: the one the pattern names';
  rsOptSize = 'check, layout: the size to use from a size table, default the first; measurements: the size to list or set';
  rsOptDescription = 'measurements set: the description; default: keep the one it has';
  rsOptJSON = 'check: print every computed value as JSON; measurements list: print the file';
  rsOptOutput = 'layout, export, export-draft: the file to write';
  rsOptDraft = 'export-draft: the draft to export; default: the one the pattern was left on';
  rsOptLabels = 'export-draft: name the points and pieces';
  rsOptFormat = 'export: pdf, svg, dxf or machine-dxf; default: the extension of --output, or pdf';
  rsOptProfile = 'export: a machine profile from the settings, in place of the layout''s';
  rsArgCommand = 'Command to run';
  rsArgPattern = 'Pattern file (.sloper), layout file (.slayout) to export, or for measurements: list, set or missing';
  rsArgFile = 'measurements: the measurement file (.slm)';
  rsArgKey = 'measurements set: the key; measurements missing: the pattern file';
  rsArgValue = 'measurements set: the value in mm';
  rsCmdCheck = 'Evaluate a pattern and report problems';
  rsCmdExport = 'Export a layout file as PDF, SVG or DXF';
  rsCmdExportDraft = 'Export a pattern''s draft as SVG, as the drafting window shows it';
  rsNoDraft = 'There is no draft called %s';
  rsCmdPack = 'Pack a layout''s pieces and rewrite the layout file';
  rsPacked = 'Packed %d copies in %s';
  rsPackedPages = 'Packed %d copies on %d pages in %s';
  rsPackLeftOut = 'Warning: %d pieces are too wide for the roll, so they stayed where they were';
  rsCmdMeasurements = 'List a measurement file, set a value, or see what a pattern needs that it lacks';
  rsMeasurementsUsage = 'Use: measurements list FILE, measurements set FILE KEY VALUE or measurements missing FILE PATTERN';
  rsMeasurementBadNumber = 'The value must be a number of millimetres, such as 820 or 41.5';
  rsMeasurementAdded = '@%s added at %s mm in %s';
  rsMeasurementChanged = '@%s %s -> %s mm in %s';
  rsMeasurementFilled = '@%s set to %s mm in %s';
  rsNothingMissing = '%s has everything %s needs';
  rsMissingCount = '%s lacks %d of what %s needs:';
  rsMissingKey = '  @%s is not in the file';
  rsMissingSizes = '  @%s has no value for size %s';
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

  // Reads the measurement file given, or else the one the pattern names, into
  // Measurements for the pattern. With neither, MeasurementPath is ''.
  function UseMeasurements(Pattern: TPattern; Measurements: TMeasurementSet; const PatternFile, MeasurementOption, SizeOption: string;
    out MeasurementPath: string): boolean;
  var
    Err: string;
  begin
    Result := False;
    MeasurementPath := MeasurementOption;
    if MeasurementPath = '' then
      MeasurementPath := MeasurementFilePath(Pattern, PatternFile);
    if MeasurementPath = '' then
      Exit(True);
    if not CheckFileExists(MeasurementPath) then
      Exit;
    if not Measurements.LoadFromFile(MeasurementPath, Err) then
    begin
      WriteLn(StdErr, Format(rsLoadFailed, [MeasurementPath, Err]));
      Exit;
    end;
    if (SizeOption <> '') and not Measurements.SelectSize(SizeOption) then
    begin
      WriteLn(StdErr, Format(rsMeasurementUnknownSize, [SizeOption]));
      Exit;
    end;
    Pattern.Measurements := Measurements;
    Result := True;
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
      if not UseMeasurements(Pattern, Measurements, PatternFile, MeasurementOption, SizeOption, MeasurementPath) then
        Exit(ExitFailure);
      if MeasurementPath <> '' then
      begin
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
  // One draft as SVG. Layers hidden in the saved view stay hidden, so a file
  // comes out as it looks in the drafting window.
  function RunExportDraft(const PatternFile, MeasurementOption, SizeOption, DraftOption, OutputOption: string; WithLabels: boolean): integer;
  var
    Pattern: TPattern;
    Measurements: TMeasurementSet;
    Draft: TPatternDraft;
    Options: TDraftSVGOptions;
    MeasurementPath, Target, Err, Problem: string;
    BlockedCount: integer;
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
      if not UseMeasurements(Pattern, Measurements, PatternFile, MeasurementOption, SizeOption, MeasurementPath) then
        Exit(ExitFailure);
      if DraftOption <> '' then
      begin
        Draft := Pattern.FindDraftNamed(DraftOption);
        if Draft = nil then
        begin
          WriteLn(StdErr, Format(rsNoDraft, [DraftOption]));
          Exit(ExitFailure);
        end;
        Pattern.ActiveDraft := Draft;
      end;
      Pattern.Evaluate;
      Options := DefaultDraftSVGOptions;
      Options.ShownOnly := True;
      Options.Labels := WithLabels;
      Target := OutputOption;
      if Target = '' then
        // ExtractFilePath keeps its separator, and is empty for a file in this folder
        Target := ExtractFilePath(PatternFile) + DraftSVGFileName(ChangeFileExt(ExtractFileName(PatternFile), ''), Pattern.ActiveDraft.Name,
          Pattern.DraftCount);
      if not WriteTextFile(Target, DraftToSVG(Pattern, Options), Err) then
      begin
        WriteLn(StdErr, Err);
        Exit(ExitFailure);
      end;
      WriteLn(Format(rsWroteFile, [Target]));
      for Problem in PatternProblems(Pattern, BlockedCount) do
        WriteLn(StdErr, Format(rsWarning, [Problem]));
      Result := 0;
    finally
      // The pattern reads the measurement set, so it goes first
      FreeAndNil(Pattern);
      FreeAndNil(Measurements);
    end;
  end;

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

  function RunPack(const LayoutFile: string): integer;
  var
    Layout: TLayout;
    Outcome: TPackResult;
    Err: string;
  begin
    if ExtractFileExt(LayoutFile) <> LayoutExtension then
    begin
      WriteLn(StdErr, Format(rsExportNeedsLayout, [LayoutExtension]));
      Exit(ExitFailure);
    end;
    if not CheckFileExists(LayoutFile) then
      Exit(ExitFailure);
    Layout := TLayout.Create;
    try
      if not Layout.LoadFromFile(LayoutFile, Err) then
      begin
        WriteLn(StdErr, Format(rsLoadFailed, [LayoutFile, Err]));
        Exit(ExitFailure);
      end;
      Layout.LoadSources;
      Outcome := PackLayout(Layout);
      if not Outcome.Done then
      begin
        WriteLn(StdErr, Outcome.Reason);
        Exit(ExitProblems);
      end;
      if not Layout.SaveToFile(LayoutFile, Err) then
      begin
        WriteLn(StdErr, Err);
        Exit(ExitFailure);
      end;
      if Layout.Output.Kind = okTiled then
        WriteLn(Format(rsPackedPages, [Outcome.Count, Outcome.Pages, LayoutFile]))
      else
        WriteLn(Format(rsPacked, [Outcome.Count, LayoutFile]));
      if Outcome.LeftOut > 0 then
        WriteLn(StdErr, Format(rsPackLeftOut, [Outcome.LeftOut]));
      Result := 0;
    finally
      FreeAndNil(Layout);
    end;
  end;

  function RunExport(const LayoutFile, OutputOption, FormatOption, ProfileOption: string): integer;
  var
    Layout: TLayout;
    Target, Err: string;
    Problem: TLayoutProblem;
    Chosen: TExportFormat;
  begin
    if ExtractFileExt(LayoutFile) <> LayoutExtension then
    begin
      WriteLn(StdErr, Format(rsExportNeedsLayout, [LayoutExtension]));
      Exit(ExitFailure);
    end;
    if not CheckFileExists(LayoutFile) then
      Exit(ExitFailure);
    if not ExportFormatFor(FormatOption, OutputOption, Chosen) then
    begin
      WriteLn(StdErr, rsExportBadFormat);
      Exit(ExitFailure);
    end;
    Target := OutputOption;
    if Target = '' then
      Target := ChangeFileExt(LayoutFile, ExportExtensions[Chosen]);
    Layout := TLayout.Create;
    try
      if not Layout.LoadFromFile(LayoutFile, Err) then
      begin
        WriteLn(StdErr, Format(rsLoadFailed, [LayoutFile, Err]));
        Exit(ExitFailure);
      end;
      Layout.LoadSources;
      Layout.MachineProfiles := UserMachineProfiles;
      if ProfileOption <> '' then
        Layout.Output.Profile := ProfileOption;
      if not ExportLayout(Layout, Chosen, Target, Err) then
      begin
        WriteLn(StdErr, Err);
        Exit(ExitProblems);
      end;
      for Problem in Layout.Problems do
        WriteLn(StdErr, Format(rsWarning, [Problem.Text]));
      WriteLn(Format(rsWroteFile, [Target]));
      if Layout.MaterialUse <> '' then
        WriteLn(Layout.MaterialUse);
      Result := 0;
    finally
      FreeAndNil(Layout);
    end;
  end;

  function LoadMeasurements(const FileName: string; Measurements: TMeasurementSet): boolean;
  var
    Err: string;
  begin
    Result := CheckFileExists(FileName) and Measurements.LoadFromFile(FileName, Err);
    if not Result and FileExists(FileName) then
      WriteLn(StdErr, Format(rsLoadFailed, [FileName, Err]));
  end;

  function RunMeasurementList(const FileName, SizeOption: string; AsJSON: boolean): integer;
  var
    Measurements: TMeasurementSet;
  begin
    Measurements := TMeasurementSet.Create;
    try
      if not LoadMeasurements(FileName, Measurements) then
        Exit(ExitFailure);
      if (SizeOption <> '') and not Measurements.SelectSize(SizeOption) then
      begin
        WriteLn(StdErr, Format(rsMeasurementUnknownSize, [SizeOption]));
        Exit(ExitFailure);
      end;
      if AsJSON then
        Write(Measurements.SaveToText)
      else
        Write(MeasurementListText(Measurements, SizeOption));
      Result := 0;
    finally
      FreeAndNil(Measurements);
    end;
  end;

  function RunMeasurementSet(const FileName, Key, ValueText, SizeOption, Description: string; KeepDescription: boolean): integer;
  var
    Value: double;
    Err: string;
    Change: TMeasurementChange;
  begin
    if not ParseMeasure(ValueText, muMillimetre, Value) then
    begin
      WriteLn(StdErr, rsMeasurementBadNumber);
      Exit(ExitFailure);
    end;
    if not CheckFileExists(FileName) then
      Exit(ExitFailure);
    if not ChangeMeasurementInFile(FileName, Key, Value, Description, Change, Err, SizeOption, KeepDescription) then
    begin
      WriteLn(StdErr, Err);
      Exit(ExitFailure);
    end;
    if Change.Added then
      WriteLn(Format(rsMeasurementAdded, [Change.Key, FormatJSONFloat(Change.Value), ExtractFileName(FileName)]))
    else if not Change.HadValue then
      WriteLn(Format(rsMeasurementFilled, [Change.Key, FormatJSONFloat(Change.Value), ExtractFileName(FileName)]))
    else
      WriteLn(Format(rsMeasurementChanged, [Change.Key, FormatJSONFloat(Change.OldValue), FormatJSONFloat(Change.Value), ExtractFileName(FileName)]));
    Result := 0;
  end;

  function RunMeasurementMissing(const FileName, PatternFile: string): integer;
  var
    Measurements: TMeasurementSet;
    Keys: TStringArray;
    Err: string;
    Lacking: TMissingMeasurementArray;
    Item: TMissingMeasurement;
  begin
    Measurements := TMeasurementSet.Create;
    try
      if not LoadMeasurements(FileName, Measurements) or not CheckFileExists(PatternFile) then
        Exit(ExitFailure);
      if not ReadPatternMeasurementKeys(PatternFile, Keys, Err) then
      begin
        WriteLn(StdErr, Format(rsLoadFailed, [PatternFile, Err]));
        Exit(ExitFailure);
      end;
      Lacking := MissingMeasurements(Keys, Measurements);
      if Lacking = nil then
      begin
        WriteLn(Format(rsNothingMissing, [ExtractFileName(FileName), ExtractFileName(PatternFile)]));
        Exit(0);
      end;
      WriteLn(Format(rsMissingCount, [ExtractFileName(FileName), Length(Lacking), ExtractFileName(PatternFile)]));
      for Item in Lacking do
        if Item.Sizes = nil then
          WriteLn(Format(rsMissingKey, [Item.Key]))
        else
          WriteLn(Format(rsMissingSizes, [Item.Key, string.Join(', ', Item.Sizes)]));
      Result := ExitProblems;
    finally
      FreeAndNil(Measurements);
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
  CommandName, PatternFile, FileArgument, KeyArgument, ValueArgument: string;
begin
  Parser := TArgumentParser.Create;
  try
    Parser.Title := 'opensloper-cli';
    Parser.Description := rsDescription;
    Parser.AddOption('help', '-h', '--help', rsOptHelp, '', avSwitch);
    Parser.AddOption('version', '-V', '--version', rsOptVersion, '', avSwitch);
    Parser.AddOption('measurements', '-m', '--measurements', rsOptMeasurements, 'file');
    Parser.AddOption('size', '-s', '--size', rsOptSize, 'size');
    Parser.AddOption('description', '-d', '--description', rsOptDescription, 'text');
    Parser.AddOption('json', '', '--json', rsOptJSON, '', avSwitch);
    Parser.AddOption('output', '-o', '--output', rsOptOutput, 'file');
    Parser.AddOption('format', '', '--format', rsOptFormat, 'format');
    Parser.AddOption('profile', '', '--profile', rsOptProfile, 'name');
    Parser.AddOption('draft', '', '--draft', rsOptDraft, 'name');
    Parser.AddOption('labels', '', '--labels', rsOptLabels, '', avSwitch);
    Command := Parser.AddArgument('command', rsArgCommand, 'command', asRequired, avChoice);
    Command.AddChoice('check', rsCmdCheck);
    Command.AddChoice('export', rsCmdExport);
    Command.AddChoice('export-draft', rsCmdExportDraft);
    Command.AddChoice('layout', rsCmdLayout);
    Command.AddChoice('measurements', rsCmdMeasurements);
    Command.AddChoice('pack', rsCmdPack);
    Command.AddChoice('serve', rsCmdServe);
    Parser.AddArgument('pattern', rsArgPattern, 'pattern', asOptional);
    Parser.AddArgument('file', rsArgFile, 'file', asOptional);
    Parser.AddArgument('key', rsArgKey, 'key', asOptional);
    Parser.AddArgument('value', rsArgValue, 'value', asOptional);

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
    if CommandName = 'measurements' then
    begin
      // The word after "measurements" says which, so it comes in as the pattern
      FileArgument := Parser.GetArgumentValueAsString('file');
      KeyArgument := Parser.GetArgumentValueAsString('key');
      ValueArgument := Parser.GetArgumentValueAsString('value');
      if (PatternFile = 'list') and (FileArgument <> '') then
        ExitCode := RunMeasurementList(FileArgument, Parser.GetOptionValueAsString('size'), Parser.IsOption('json'))
      else if (PatternFile = 'set') and (FileArgument <> '') and (KeyArgument <> '') and (ValueArgument <> '') then
        ExitCode := RunMeasurementSet(FileArgument, KeyArgument, ValueArgument, Parser.GetOptionValueAsString('size'),
          Parser.GetOptionValueAsString('description'), not Parser.IsOption('description'))
      else if (PatternFile = 'missing') and (FileArgument <> '') and (KeyArgument <> '') then
        ExitCode := RunMeasurementMissing(FileArgument, KeyArgument)
      else
      begin
        WriteLn(StdErr, rsMeasurementsUsage);
        ExitCode := ExitFailure;
      end;
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
    else if CommandName = 'pack' then
      ExitCode := RunPack(PatternFile)
    else if CommandName = 'export-draft' then
      ExitCode := RunExportDraft(PatternFile, Parser.GetOptionValueAsString('measurements'), Parser.GetOptionValueAsString('size'),
        Parser.GetOptionValueAsString('draft'), Parser.GetOptionValueAsString('output'), Parser.IsOption('labels'))
    else
      ExitCode := RunExport(PatternFile, Parser.GetOptionValueAsString('output'), Parser.GetOptionValueAsString('format'),
        Parser.GetOptionValueAsString('profile'));
  finally
    FreeAndNil(Parser);
  end;
end.
