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

// The commands of opensloper-cli, run on arguments given as a list and
// writing to the text files given, so tests can run them without the
// program. serve keeps to standard input and output, and --help prints to
// standard output (ConsoleTools). Exit codes are as for the program.
unit Sloper.CLI.Commands;

{$mode ObjFPC}{$H+}

interface

// Runs one command line, Args without the program's name; returns the exit code
function RunCli(const Args: array of string; var AOut, AErr: Text): integer;

const
  DRAFT_FORMAT_SVG = 'svg';
  DRAFT_FORMAT_PNG = 'png';

resourcestring
  rsUnknownTopic = 'There is no documentation topic "%s"; use one of: %s';
  rsUpToUnknown = 'There is no object named "%s" in the pattern';
  rsUpToRefused = 'Could not leave out %s: %s';
  rsPacked = 'Packed %d copies in %s';
  rsPackedPages = 'Packed %d copies on %d pages in %s';
  rsPackLeftOut = 'Warning: %d pieces are too wide for the roll, so they stayed where they were';
  rsMeasurementsUsage = 'Use: measurements list FILE, measurements set FILE KEY VALUE or measurements missing FILE PATTERN';
  rsMeasurementBadNumber = 'The value must be a number of millimetres, such as 820 or 41.5';
  rsMeasurementAdded = '@%s added at %s mm in %s';
  rsMeasurementChanged = '@%s %s -> %s mm in %s';
  rsMeasurementFilled = '@%s set to %s mm in %s';
  rsNothingMissing = '%s has everything %s needs';
  rsMissingCount = '%s lacks %d of what %s needs:';
  rsMissingKey = '  @%s is not in the file';
  rsMissingSizes = '  @%s has no value for size %s';
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
  rsDraftFormat = 'export-draft writes svg or png, not "%s"';
  rsDraftWidth = 'The width must be a whole number of pixels, such as 1600';
  rsWarning = 'Warning: %s';
  // Material, size, what is needed, pieces
  rsMaterialsEntry = '%s%s: %s (%d pieces)';
  rsMaterialsNone = 'No pieces';

implementation

uses
  SysUtils, fpjson, ConsoleTools, Sloper.CLI.Arguments, Sloper.Docs.Reference, Sloper.Core.Version, Sloper.Core.JSON,
  Sloper.Core.Measurements, Sloper.Core.Units, Sloper.Core.Evaluator, Sloper.Core.Pattern, Sloper.Core.PatternFile,
  Sloper.Core.PatternCheck, Sloper.Core.Settings, Sloper.Output.DraftSVG, Sloper.Output.DraftPNG, Sloper.Output.Layout,
  Sloper.Output.LayoutExport, Sloper.Output.Packing, Sloper.Output.MaterialNeeded, Sloper.API.MCP, Sloper.API.Connection;

var
  // Where the command being run writes, set by RunCli
  CliOut, CliErr: ^Text;

// False, with a message, when FileName does not exist; the load messages
// would otherwise name it several times
function CheckFileExists(const FileName: string): boolean;
begin
  Result := FileExists(FileName);
  if not Result then
    WriteLn(CliErr^, Format(rsFileNotFound, [FileName]));
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
    WriteLn(CliErr^, Format(rsLoadFailed, [MeasurementPath, Err]));
    Exit;
  end;
  if (SizeOption <> '') and not Measurements.SelectSize(SizeOption) then
  begin
    WriteLn(CliErr^, Format(rsMeasurementUnknownSize, [SizeOption]));
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
      Exit(EXIT_FAILURE);
    if not LoadPatternFromFile(Pattern, PatternFile, Err) then
    begin
      WriteLn(CliErr^, Format(rsLoadFailed, [PatternFile, Err]));
      Exit(EXIT_FAILURE);
    end;
    if not UseMeasurements(Pattern, Measurements, PatternFile, MeasurementOption, SizeOption, MeasurementPath) then
      Exit(EXIT_FAILURE);
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
        Write(CliOut^, JSONToText(Report));
      finally
        FreeAndNil(Report);
      end;
    end
    else if Length(Problems) = 0 then
      WriteLn(CliOut^, Format(rsCheckClean, [Title, Pattern.ObjectCount]))
    else
    begin
      WriteLn(CliOut^, Format(rsCheckProblems, [Title, Length(Problems)]));
      for Problem in Problems do
        WriteLn(CliOut^, '  ', Problem);
      if BlockedCount > 0 then
        WriteLn(CliOut^, '  ', Format(rsCheckBlocked, [BlockedCount]));
    end;
    if (Length(Problems) > 0) or (BlockedCount > 0) then
      Result := EXIT_PROBLEMS
    else
      Result := 0;
  finally
    // The pattern reads the measurement set, so it goes first
    FreeAndNil(Pattern);
    FreeAndNil(Measurements);
  end;
end;

// Starts a layout beside the pattern, with every piece placed in rows
// The drafting canvas as SVG
// Deletes every object after the one named, newest first, so the pattern is
// as it was when that object was added: a file lists objects after what they use
function KeepUpTo(Pattern: TPattern; const ObjectName: string): boolean;
var
  Target: TEvalNode;
  Last: TEvalNode;
begin
  Target := Pattern.FindObject(ObjectName);
  if not Assigned(Target) then
  begin
    WriteLn(CliErr^, Format(rsUpToUnknown, [ObjectName]));
    Exit(False);
  end;
  while Pattern.Objects[Pattern.ObjectCount - 1] <> Target do
  begin
    Last := Pattern.Objects[Pattern.ObjectCount - 1];
    if not Pattern.Delete(Last) then
    begin
      WriteLn(CliErr^, Format(rsUpToRefused, [Last.DisplayName, Pattern.LastError]));
      Exit(False);
    end;
  end;
  Result := True;
end;

function RunExportDraft(const PatternFile, MeasurementOption, SizeOption, OutputOption, UpTo, FormatOption, WidthOption: string;
  WithLabels: boolean): integer;
var
  Pattern: TPattern;
  Measurements: TMeasurementSet;
  Options: TDraftSVGOptions;
  MeasurementPath, Target, Err, Problem, DraftFormat: string;
  Content: rawbytestring;
  BlockedCount, Width: integer;
begin
  Measurements := nil;
  Pattern := nil;
  // The format given, else the output file's extension, else svg
  DraftFormat := LowerCase(FormatOption);
  if (DraftFormat = '') and (OutputOption <> '') then
    DraftFormat := LowerCase(Copy(ExtractFileExt(OutputOption), 2, MaxInt));
  if (DraftFormat <> DRAFT_FORMAT_PNG) then
  begin
    if (FormatOption <> '') and (DraftFormat <> DRAFT_FORMAT_SVG) then
    begin
      WriteLn(CliErr^, Format(rsDraftFormat, [FormatOption]));
      Exit(EXIT_FAILURE);
    end;
    DraftFormat := DRAFT_FORMAT_SVG;
  end;
  Width := PNG_DEFAULT_WIDTH;
  if (WidthOption <> '') and not TryStrToInt(WidthOption, Width) then
  begin
    WriteLn(CliErr^, rsDraftWidth);
    Exit(EXIT_FAILURE);
  end;
  try
    Measurements := TMeasurementSet.Create;
    Pattern := TPattern.Create;
    if not CheckFileExists(PatternFile) then
      Exit(EXIT_FAILURE);
    if not LoadPatternFromFile(Pattern, PatternFile, Err) then
    begin
      WriteLn(CliErr^, Format(rsLoadFailed, [PatternFile, Err]));
      Exit(EXIT_FAILURE);
    end;
    if not UseMeasurements(Pattern, Measurements, PatternFile, MeasurementOption, SizeOption, MeasurementPath) then
      Exit(EXIT_FAILURE);
    if (UpTo <> '') and not KeepUpTo(Pattern, UpTo) then
      Exit(EXIT_FAILURE);
    Pattern.Evaluate;
    Options := DefaultDraftSVGOptions;
    Options.Labels := WithLabels;
    Options.PatternFileName := PatternFile;
    Target := OutputOption;
    if Target = '' then
      // ExtractFilePath keeps its separator, and is empty for a file in this folder
      Target := ChangeFileExt(PatternFile, '.' + DraftFormat);
    if DraftFormat = DRAFT_FORMAT_SVG then
      Content := DraftToSVG(Pattern, Options)
    else if not DraftToPNG(Pattern, Options, Width, Content, Err) then
    begin
      WriteLn(CliErr^, Err);
      Exit(EXIT_FAILURE);
    end;
    if not WriteTextFile(Target, Content, Err) then
    begin
      WriteLn(CliErr^, Err);
      Exit(EXIT_FAILURE);
    end;
    WriteLn(CliOut^, Format(rsWroteFile, [Target]));
    for Problem in PatternProblems(Pattern, BlockedCount) do
      WriteLn(CliErr^, Format(rsWarning, [Problem]));
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
    Target := ChangeFileExt(PatternFile, LAYOUT_EXTENSION);
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
      WriteLn(CliErr^, Err);
      Exit(EXIT_FAILURE);
    end;
    WriteLn(CliOut^, Format(rsWroteFile, [Target]));
    for Problem in Layout.Problems do
      WriteLn(CliErr^, Format(rsWarning, [Problem.Text]));
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
  if ExtractFileExt(LayoutFile) <> LAYOUT_EXTENSION then
  begin
    WriteLn(CliErr^, Format(rsExportNeedsLayout, [LAYOUT_EXTENSION]));
    Exit(EXIT_FAILURE);
  end;
  if not CheckFileExists(LayoutFile) then
    Exit(EXIT_FAILURE);
  Layout := TLayout.Create;
  try
    if not Layout.LoadFromFile(LayoutFile, Err) then
    begin
      WriteLn(CliErr^, Format(rsLoadFailed, [LayoutFile, Err]));
      Exit(EXIT_FAILURE);
    end;
    Layout.LoadSources;
    Outcome := PackLayout(Layout);
    if not Outcome.Done then
    begin
      WriteLn(CliErr^, Outcome.Reason);
      Exit(EXIT_PROBLEMS);
    end;
    if not Layout.SaveToFile(LayoutFile, Err) then
    begin
      WriteLn(CliErr^, Err);
      Exit(EXIT_FAILURE);
    end;
    if Layout.Output.Kind = okTiled then
      WriteLn(CliOut^, Format(rsPackedPages, [Outcome.Count, Outcome.Pages, LayoutFile]))
    else
      WriteLn(CliOut^, Format(rsPacked, [Outcome.Count, LayoutFile]));
    if Outcome.LeftOut > 0 then
      WriteLn(CliErr^, Format(rsPackLeftOut, [Outcome.LeftOut]));
    Result := 0;
  finally
    FreeAndNil(Layout);
  end;
end;

// A pattern is estimated alone, as a layout of it would be
function RunMaterials(const FileName: string; AsJSON: boolean): integer;
const
  KIND_NAMES: array[TMaterialNeedKind] of string = ('none', 'roll', 'sheet');
var
  Layout: TLayout;
  Needs: TMaterialNeedArray;
  Need: TMaterialNeed;
  Note, Size, Err: string;
  Report, Item: TJSONObject;
  List, Notes: TJSONArray;
begin
  if not CheckFileExists(FileName) then
    Exit(EXIT_FAILURE);
  Layout := TLayout.Create;
  try
    if ExtractFileExt(FileName) = LAYOUT_EXTENSION then
    begin
      if not Layout.LoadFromFile(FileName, Err) then
      begin
        WriteLn(CliErr^, Format(rsLoadFailed, [FileName, Err]));
        Exit(EXIT_FAILURE);
      end;
    end
    else
    begin
      Layout.FileName := ChangeFileExt(ExpandFileName(FileName), LAYOUT_EXTENSION);
      Layout.AddSource(ExtractFileName(FileName), '', '');
    end;
    Layout.LoadSources;
    Needs := LayoutMaterialNeeds(Layout);
    if AsJSON then
    begin
      Report := TJSONObject.Create;
      try
        List := TJSONArray.Create;
        Report.Add('materials', List);
        for Need in Needs do
        begin
          Item := TJSONObject.Create;
          List.Add(Item);
          Item.Add('name', Need.Name);
          Item.Add('kind', KIND_NAMES[Need.Kind]);
          Item.Add('width', JSONFloat(Need.Width));
          Item.Add('length', JSONFloat(Need.Length));
          Item.Add('allowTurns', Need.AllowTurns);
          Item.Add('pieces', Need.Copies);
          Item.Add('area', JSONFloat(Need.Area));
          Item.Add('needed', JSONFloat(Need.Needed));
          Item.Add('unfolded', JSONFloat(Need.Unfolded));
          Item.Add('sheets', Need.Sheets);
          Item.Add('narrowestRoll', JSONFloat(Need.NarrowestRoll));
          Notes := TJSONArray.Create;
          Item.Add('notes', Notes);
          for Note in Need.Notes do
            Notes.Add(Note);
        end;
        Write(CliOut^, JSONToText(Report));
      finally
        FreeAndNil(Report);
      end;
      Exit(0);
    end;
    if Length(Needs) = 0 then
      WriteLn(CliOut^, rsMaterialsNone);
    for Need in Needs do
    begin
      Size := MaterialNeedSize(Need);
      if Size <> '' then
        Size := ', ' + Size;
      WriteLn(CliOut^, Format(rsMaterialsEntry, [Need.Name, Size, MaterialNeedText(Need), Need.Copies]));
      for Note in Need.Notes do
        WriteLn(CliOut^, '  ', Note);
    end;
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
  if ExtractFileExt(LayoutFile) <> LAYOUT_EXTENSION then
  begin
    WriteLn(CliErr^, Format(rsExportNeedsLayout, [LAYOUT_EXTENSION]));
    Exit(EXIT_FAILURE);
  end;
  if not CheckFileExists(LayoutFile) then
    Exit(EXIT_FAILURE);
  if not ExportFormatFor(FormatOption, OutputOption, Chosen) then
  begin
    WriteLn(CliErr^, rsExportBadFormat);
    Exit(EXIT_FAILURE);
  end;
  Target := OutputOption;
  if Target = '' then
    Target := ChangeFileExt(LayoutFile, EXPORT_EXTENSIONS[Chosen]);
  Layout := TLayout.Create;
  try
    if not Layout.LoadFromFile(LayoutFile, Err) then
    begin
      WriteLn(CliErr^, Format(rsLoadFailed, [LayoutFile, Err]));
      Exit(EXIT_FAILURE);
    end;
    Layout.LoadSources;
    Layout.MachineProfiles := UserMachineProfiles;
    Layout.OutputProfiles := UserOutputProfiles;
    Layout.Calibration := UserCalibration;
    if ProfileOption <> '' then
      Layout.Output.Profile := ProfileOption;
    if not ExportLayout(Layout, Chosen, Target, Err) then
    begin
      WriteLn(CliErr^, Err);
      Exit(EXIT_PROBLEMS);
    end;
    for Problem in Layout.Problems do
      WriteLn(CliErr^, Format(rsWarning, [Problem.Text]));
    WriteLn(CliOut^, Format(rsWroteFile, [Target]));
    if Layout.MaterialUse <> '' then
      WriteLn(CliOut^, Layout.MaterialUse);
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
    WriteLn(CliErr^, Format(rsLoadFailed, [FileName, Err]));
end;

function RunMeasurementList(const FileName, SizeOption: string; AsJSON: boolean): integer;
var
  Measurements: TMeasurementSet;
begin
  Measurements := TMeasurementSet.Create;
  try
    if not LoadMeasurements(FileName, Measurements) then
      Exit(EXIT_FAILURE);
    if (SizeOption <> '') and not Measurements.SelectSize(SizeOption) then
    begin
      WriteLn(CliErr^, Format(rsMeasurementUnknownSize, [SizeOption]));
      Exit(EXIT_FAILURE);
    end;
    if AsJSON then
      Write(CliOut^, Measurements.SaveToText)
    else
      Write(CliOut^, MeasurementListText(Measurements, SizeOption));
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
    WriteLn(CliErr^, rsMeasurementBadNumber);
    Exit(EXIT_FAILURE);
  end;
  if not CheckFileExists(FileName) then
    Exit(EXIT_FAILURE);
  if not ChangeMeasurementInFile(FileName, Key, Value, Description, Change, Err, SizeOption, KeepDescription) then
  begin
    WriteLn(CliErr^, Err);
    Exit(EXIT_FAILURE);
  end;
  if Change.Added then
    WriteLn(CliOut^, Format(rsMeasurementAdded, [Change.Key, FormatJSONFloat(Change.Value), ExtractFileName(FileName)]))
  else if not Change.HadValue then
    WriteLn(CliOut^, Format(rsMeasurementFilled, [Change.Key, FormatJSONFloat(Change.Value), ExtractFileName(FileName)]))
  else
    WriteLn(CliOut^, Format(rsMeasurementChanged, [Change.Key, FormatJSONFloat(Change.OldValue), FormatJSONFloat(Change.Value), ExtractFileName(FileName)]));
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
      Exit(EXIT_FAILURE);
    if not ReadPatternMeasurementKeys(PatternFile, Keys, Err) then
    begin
      WriteLn(CliErr^, Format(rsLoadFailed, [PatternFile, Err]));
      Exit(EXIT_FAILURE);
    end;
    Lacking := MissingMeasurements(Keys, Measurements);
    if Length(Lacking) = 0 then
    begin
      WriteLn(CliOut^, Format(rsNothingMissing, [ExtractFileName(FileName), ExtractFileName(PatternFile)]));
      Exit(0);
    end;
    WriteLn(CliOut^, Format(rsMissingCount, [ExtractFileName(FileName), Length(Lacking), ExtractFileName(PatternFile)]));
    for Item in Lacking do
      if Length(Item.Sizes) = 0 then
        WriteLn(CliOut^, Format(rsMissingKey, [Item.Key]))
      else
        WriteLn(CliOut^, Format(rsMissingSizes, [Item.Key, string.Join(', ', Item.Sizes)]));
    Result := EXIT_PROBLEMS;
  finally
    FreeAndNil(Measurements);
  end;
end;

// The Automation API, also as an MCP server: one request a line, until stdin
// closes. With Connect, on the pattern open in the design window.
procedure RunServe(Connect: boolean);
var
  Server: TMcpServer;
  Line, Reply: string;
begin
  if Connect then
    Server := TMcpServer.CreateFor(TApiConnection.Create)
  else
    Server := TMcpServer.Create;
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

// A reference page, to the file given or to standard output
// With no topic, lists the topics, one a line, for opensloper-make.sh docs
function RunDoc(const Topic, OutputFile: string): integer;
var
  Markdown, Err, Name: string;
begin
  if Topic = '' then
  begin
    for Name in DOC_TOPICS do
      WriteLn(CliOut^, Name);
    Exit(EXIT_SUCCESS);
  end;
  if not ReferencePage(Topic, Markdown) then
  begin
    WriteLn(CliErr^, Format(rsUnknownTopic, [Topic, string.Join(', ', DOC_TOPICS)]));
    Exit(EXIT_FAILURE);
  end;
  if OutputFile = '' then
  begin
    Write(CliOut^, Markdown);
    Exit(EXIT_SUCCESS);
  end;
  if not WriteTextFile(OutputFile, Markdown, Err) then
  begin
    WriteLn(CliErr^, Err);
    Exit(EXIT_FAILURE);
  end;
  Result := EXIT_SUCCESS;
end;

function RunCli(const Args: array of string; var AOut, AErr: Text): integer;
var
  Parser: TArgumentParser;
  CommandName, PatternFile, FileArgument, KeyArgument, ValueArgument: string;
begin
  CliOut := @AOut;
  CliErr := @AErr;
  Result := EXIT_SUCCESS;
  Parser := BuildCliParser;
  try
    try
      Parser.Parse(Args);
      if Parser.IsOption('help') then
      begin
        Parser.ShowHelp;
        Exit;
      end;
      if Parser.IsOption('version') then
      begin
        WriteLn(CliOut^, APP_NAME, ' ', APP_VERSION);
        Exit;
      end;
      Parser.Validate;
    except
      on Failure: EArgumentParserException do
      begin
        WriteLn(CliErr^, Failure.Message);
        Result := EXIT_FAILURE;
        Exit;
      end;
    end;

    CommandName := Parser.GetArgumentValueAsString('command');
    PatternFile := Parser.GetArgumentValueAsString('pattern');
    if CommandName = 'serve' then
    begin
      RunServe(Parser.IsOption('connect'));
      Exit;
    end;
    if CommandName = 'measurements' then
    begin
      // The word after "measurements" says which, so it comes in as the pattern
      FileArgument := Parser.GetArgumentValueAsString('file');
      KeyArgument := Parser.GetArgumentValueAsString('key');
      ValueArgument := Parser.GetArgumentValueAsString('value');
      if (PatternFile = 'list') and (FileArgument <> '') then
        Result := RunMeasurementList(FileArgument, Parser.GetOptionValueAsString('size'), Parser.IsOption('json'))
      else if (PatternFile = 'set') and (FileArgument <> '') and (KeyArgument <> '') and (ValueArgument <> '') then
        Result := RunMeasurementSet(FileArgument, KeyArgument, ValueArgument, Parser.GetOptionValueAsString('size'),
          Parser.GetOptionValueAsString('description'), not Parser.IsOption('description'))
      else if (PatternFile = 'missing') and (FileArgument <> '') and (KeyArgument <> '') then
        Result := RunMeasurementMissing(FileArgument, KeyArgument)
      else
      begin
        WriteLn(CliErr^, rsMeasurementsUsage);
        Result := EXIT_FAILURE;
      end;
      Exit;
    end;
    if CommandName = 'doc' then
    begin
      Result := RunDoc(PatternFile, Parser.GetOptionValueAsString('output'));
      Exit;
    end;
    if PatternFile = '' then
    begin
      WriteLn(CliErr^, Format(rsNeedPattern, [CommandName]));
      Result := EXIT_FAILURE;
      Exit;
    end;
    if CommandName = 'check' then
      Result := RunCheck(PatternFile, Parser.GetOptionValueAsString('measurements'), Parser.GetOptionValueAsString('size'),
        Parser.IsOption('json'))
    else if CommandName = 'layout' then
      Result := RunLayout(PatternFile, Parser.GetOptionValueAsString('measurements'), Parser.GetOptionValueAsString('size'),
        Parser.GetOptionValueAsString('output'))
    else if CommandName = 'pack' then
      Result := RunPack(PatternFile)
    else if CommandName = 'materials' then
      Result := RunMaterials(PatternFile, Parser.IsOption('json'))
    else if CommandName = 'export-draft' then
      Result := RunExportDraft(PatternFile, Parser.GetOptionValueAsString('measurements'), Parser.GetOptionValueAsString('size'),
        Parser.GetOptionValueAsString('output'), Parser.GetOptionValueAsString('upto'), Parser.GetOptionValueAsString('format'),
        Parser.GetOptionValueAsString('width'), Parser.IsOption('labels'))
    else
      Result := RunExport(PatternFile, Parser.GetOptionValueAsString('output'), Parser.GetOptionValueAsString('format'),
        Parser.GetOptionValueAsString('profile'));
  finally
    FreeAndNil(Parser);
  end;
end;

end.
