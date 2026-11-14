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

// opensloper-cli's commands, run in the test program through RunCli with
// their output caught, on copies of the example patterns in a folder of
// their own: exit codes, what they print and the files they write
unit Sloper.Tests.CLI;

{$mode ObjFPC}{$H+}

interface

uses
  SysUtils, fpcunit, testregistry, Sloper.Tests.TestCase;

type
  TTestCLI = class(TOSTestCase)
  private
    FFolder: string;
    // What the last command wrote to its output and its errors
    FOut, FErr: string;
    function Run(const Args: array of string): integer;
    // A copy of docs/examples/Example in the test folder; its path there
    function CopyExample(const Example: string): string;
    function InFolder(const FileName: string): string;
    function OutLines: TStringArray;
    // The tote bag, with Main and Lining given a width in cm
    function SizedToteBag(MainWidth, LiningWidth: double): string;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestVersion;
    procedure TestUnknownOptionIsUsageError;
    procedure TestCommandNeedsPattern;
    procedure TestMissingFile;
    procedure TestCheckClean;
    procedure TestCheckProblems;
    procedure TestCheckJSON;
    procedure TestCheckUnknownSize;
    procedure TestLayoutThenExport;
    procedure TestExportNeedsLayout;
    procedure TestExportBadFormat;
    procedure TestPack;
    procedure TestExportDraft;
    procedure TestExportDraftUpToUnknown;
    procedure TestExportDraftBadWidth;
    procedure TestMaterialsOfPattern;
    procedure TestMaterialsOfLayout;
    procedure TestMaterialsJSON;
    procedure TestMeasurementsList;
    procedure TestMeasurementsSet;
    procedure TestMeasurementsSetBadNumber;
    procedure TestMeasurementsMissing;
    procedure TestMeasurementsUsage;
    procedure TestDocTopics;
    procedure TestDocUnknownTopic;
    procedure TestDocToFile;
  end;

implementation

uses
  Classes, StreamIO, fpjson, jsonparser, Sloper.Core.Version, Sloper.Core.Pattern, Sloper.Core.PatternFile, Sloper.Core.Units,
  Sloper.Core.PatternCheck, Sloper.Core.Measurements, Sloper.CLI.Arguments, Sloper.CLI.Commands, Sloper.Output.Layout, Sloper.Output.LayoutExport;

function ExamplesFolder: string;
begin
  Result := ConcatPaths([ExtractFileDir(ExtractFileDir(ExpandFileName(ParamStr(0)))), 'docs', 'examples']);
end;

function ReadWholeFile(const FileName: string): rawbytestring;
var
  Stream: TFileStream;
begin
  Result := '';
  Stream := TFileStream.Create(FileName, fmOpenRead or fmShareDenyNone);
  try
    SetLength(Result, Stream.Size);
    if Stream.Size > 0 then
      Stream.ReadBuffer(Result[1], Stream.Size);
  finally
    FreeAndNil(Stream);
  end;
end;

procedure CopyWholeFile(const Source, Target: string);
var
  Stream: TFileStream;
  Content: rawbytestring;
begin
  Content := ReadWholeFile(Source);
  Stream := TFileStream.Create(Target, fmCreate);
  try
    if Content <> '' then
      Stream.WriteBuffer(Content[1], Length(Content));
  finally
    FreeAndNil(Stream);
  end;
end;

procedure TTestCLI.SetUp;
begin
  inherited SetUp;
  FFolder := IncludeTrailingPathDelimiter(GetTempDir) + 'sloper-cli-' + IntToStr(Random(MaxInt));
  ForceDirectories(FFolder);
end;

procedure TTestCLI.TearDown;
var
  Found: TSearchRec;
begin
  if FindFirst(ConcatPaths([FFolder, '*']), faAnyFile, Found) = 0 then
    repeat
      DeleteFile(ConcatPaths([FFolder, Found.Name]));
    until FindNext(Found) <> 0;
  FindClose(Found);
  RemoveDir(FFolder);
  inherited TearDown;
end;

function TTestCLI.Run(const Args: array of string): integer;
var
  OutStream, ErrStream: TStringStream;
  OutText, ErrText: Text;
begin
  OutStream := TStringStream.Create('');
  ErrStream := TStringStream.Create('');
  try
    AssignStream(OutText, OutStream);
    Rewrite(OutText);
    AssignStream(ErrText, ErrStream);
    Rewrite(ErrText);
    try
      Result := RunCli(Args, OutText, ErrText);
    finally
      CloseFile(OutText);
      CloseFile(ErrText);
    end;
    FOut := OutStream.DataString;
    FErr := ErrStream.DataString;
  finally
    FreeAndNil(OutStream);
    FreeAndNil(ErrStream);
  end;
end;

function TTestCLI.InFolder(const FileName: string): string;
begin
  Result := ConcatPaths([FFolder, FileName]);
end;

function TTestCLI.CopyExample(const Example: string): string;
begin
  Result := InFolder(ExtractFileName(Example));
  CopyWholeFile(ConcatPaths([ExamplesFolder, Example]), Result);
end;

function TTestCLI.OutLines: TStringArray;
begin
  Result := FOut.Trim.Split([LineEnding]);
end;

function TTestCLI.SizedToteBag(MainWidth, LiningWidth: double): string;
var
  Pattern: TPattern;
  Reason: string;
begin
  Result := CopyExample(ConcatPaths(['tote-bag', 'tote-bag.sloper']));
  Pattern := TPattern.Create;
  try
    AssertTrue(Reason, LoadPatternFromFile(Pattern, Result, Reason));
    AssertTrue(Pattern.LastError, Pattern.SetMaterialSize(Pattern.FindMaterialNamed('Main'), MainWidth, 0));
    AssertTrue(Pattern.LastError, Pattern.SetMaterialSize(Pattern.FindMaterialNamed('Lining'), LiningWidth, 0));
    AssertTrue(Reason, SavePatternToFile(Pattern, Result, Reason));
  finally
    FreeAndNil(Pattern);
  end;
end;

procedure TTestCLI.TestVersion;
begin
  AssertEquals(0, Run(['--version']));
  AssertEquals(APP_NAME + ' ' + APP_VERSION, FOut.Trim);
end;

procedure TTestCLI.TestUnknownOptionIsUsageError;
begin
  AssertEquals(EXIT_FAILURE, Run(['check', 'a.sloper', '--nonsense']));
  AssertEquals('nothing on the output', '', FOut);
  AssertTrue('says why', FErr <> '');
end;

procedure TTestCLI.TestCommandNeedsPattern;
begin
  AssertEquals(EXIT_FAILURE, Run(['check']));
  AssertEquals(Format(rsNeedPattern, ['check']), FErr.Trim);
end;

procedure TTestCLI.TestMissingFile;
begin
  AssertEquals(EXIT_FAILURE, Run(['check', InFolder('none.sloper')]));
  AssertEquals(Format(rsFileNotFound, [InFolder('none.sloper')]), FErr.Trim);
end;

procedure TTestCLI.TestCheckClean;
var
  Pattern: string;
begin
  Pattern := CopyExample(ConcatPaths(['skirt-block', 'skirt-block.sloper']));
  CopyExample(ConcatPaths(['skirt-block', 'skirt.slm']));
  AssertEquals(FErr, 0, Run(['check', Pattern]));
  AssertTrue(FOut, FOut.StartsWith(Format(rsCheckWith, ['skirt-block.sloper', 'skirt.slm']) + ': '));
end;

// Main 40 cm wide is narrower than the body; the strap's grainline runs
// along it, so it lies 12 cm across and fits
procedure TTestCLI.TestCheckProblems;
begin
  AssertEquals(EXIT_PROBLEMS, Run(['check', SizedToteBag(40, 140)]));
  AssertEquals(Format(rsCheckProblems, [Format(rsCheckNoSet, ['tote-bag.sloper']), 1]), OutLines[0]);
  AssertTrue(FOut, Pos(Format(rsCheckWiderThanRoll, ['Body', '42 cm', 'Main', '40 cm']), FOut) > 0);
end;

procedure TTestCLI.TestCheckJSON;
var
  Report: TJSONData;
begin
  AssertEquals(0, Run(['check', SizedToteBag(150, 140), '--json']));
  Report := GetJSON(FOut);
  try
    AssertTrue(Report.JSONType = jtObject);
    AssertEquals('tote-bag.sloper', TJSONObject(Report).Get('pattern', ''));
  finally
    FreeAndNil(Report);
  end;
end;

procedure TTestCLI.TestCheckUnknownSize;
var
  Pattern: string;
begin
  Pattern := CopyExample(ConcatPaths(['skirt-block', 'skirt-block.sloper']));
  CopyExample(ConcatPaths(['skirt-block', 'skirt.slm']));
  AssertEquals(EXIT_FAILURE, Run(['check', Pattern, '-s', 'XXL']));
  AssertEquals(Format(rsMeasurementUnknownSize, ['XXL']), FErr.Trim);
end;

procedure TTestCLI.TestLayoutThenExport;
var
  Pattern, Layout, Pdf: string;
begin
  Pattern := SizedToteBag(150, 140);
  Layout := InFolder('tote-bag.slayout');
  AssertEquals(FErr, 0, Run(['layout', Pattern]));
  AssertEquals(Format(rsWroteFile, [Layout]), OutLines[0]);
  AssertTrue('beside the pattern', FileExists(Layout));
  Pdf := InFolder('tote.pdf');
  AssertEquals(FErr, 0, Run(['export', Layout, '-o', Pdf]));
  AssertEquals(Format(rsWroteFile, [Pdf]), OutLines[0]);
  AssertEquals('a PDF', '%PDF', Copy(ReadWholeFile(Pdf), 1, 4));
end;

procedure TTestCLI.TestExportNeedsLayout;
begin
  AssertEquals(EXIT_FAILURE, Run(['export', SizedToteBag(150, 140)]));
  AssertEquals(Format(rsExportNeedsLayout, [LAYOUT_EXTENSION]), FErr.Trim);
end;

procedure TTestCLI.TestExportBadFormat;
begin
  AssertEquals(0, Run(['layout', SizedToteBag(150, 140)]));
  AssertEquals(EXIT_FAILURE, Run(['export', InFolder('tote-bag.slayout'), '--format=gif']));
  AssertEquals(rsExportBadFormat, FErr.Trim);
end;

procedure TTestCLI.TestPack;
var
  Layout: string;
begin
  AssertEquals(0, Run(['layout', SizedToteBag(150, 140)]));
  Layout := InFolder('tote-bag.slayout');
  AssertEquals(FErr, 0, Run(['pack', Layout]));
  AssertTrue(FOut, FOut.StartsWith('Packed '));
  AssertTrue(FOut, FOut.Trim.EndsWith(Layout));
end;

procedure TTestCLI.TestExportDraft;
var
  Svg: string;
begin
  Svg := InFolder('draft.svg');
  AssertEquals(FErr, 0, Run(['export-draft', SizedToteBag(150, 140), '-o', Svg, '--labels']));
  AssertEquals(Format(rsWroteFile, [Svg]), OutLines[0]);
  AssertTrue('an SVG', Pos('<svg', ReadWholeFile(Svg)) > 0);
end;

procedure TTestCLI.TestExportDraftUpToUnknown;
begin
  AssertEquals(EXIT_FAILURE, Run(['export-draft', SizedToteBag(150, 140), '--upto=Nothing']));
  AssertEquals(Format(rsUpToUnknown, ['Nothing']), FErr.Trim);
end;

procedure TTestCLI.TestExportDraftBadWidth;
begin
  AssertEquals(EXIT_FAILURE, Run(['export-draft', SizedToteBag(150, 140), '--format=png', '--width=wide']));
  AssertEquals(rsDraftWidth, FErr.Trim);
end;

// In the pattern's material order, each with its size, what it needs and how
// many pieces; the pocket's fold runs across its grain
procedure TTestCLI.TestMaterialsOfPattern;
var
  Lines: TStringArray;
begin
  AssertEquals(FErr, 0, Run(['materials', SizedToteBag(150, 140)]));
  Lines := OutLines;
  AssertEquals(3, Length(Lines));
  AssertTrue(Lines[0], Lines[0].StartsWith('Main, 150 cm roll: '));
  AssertTrue(Lines[0], Lines[0].EndsWith(' (5 pieces)'));
  AssertTrue(Lines[1], Lines[1].StartsWith('  Main: the fold of Pocket'));
  AssertTrue(Lines[2], Lines[2].StartsWith('Lining, 140 cm roll: '));
  AssertTrue(Lines[2], Lines[2].EndsWith(' (2 pieces)'));
end;

procedure TTestCLI.TestMaterialsOfLayout;
var
  FromPattern: string;
begin
  AssertEquals(0, Run(['materials', SizedToteBag(150, 140)]));
  FromPattern := FOut;
  AssertEquals(0, Run(['layout', InFolder('tote-bag.sloper')]));
  AssertEquals(FErr, 0, Run(['materials', InFolder('tote-bag.slayout')]));
  AssertEquals('the same as for its pattern', FromPattern, FOut);
end;

procedure TTestCLI.TestMaterialsJSON;
var
  Report: TJSONData;
  Main: TJSONObject;
begin
  AssertEquals(FErr, 0, Run(['materials', SizedToteBag(150, 140), '--json']));
  Report := GetJSON(FOut);
  try
    Main := TJSONObject(Report).Arrays['materials'].Objects[0];
    AssertEquals('Main', Main.Get('name', ''));
    AssertEquals('roll', Main.Get('kind', ''));
    AssertEquals('in mm', 1500, Main.Get('width', 0.0), 1e-9);
    AssertEquals(5, Main.Get('pieces', 0));
    AssertTrue('a length', Main.Get('needed', 0.0) > 0);
    AssertEquals(1, Main.Arrays['notes'].Count);
  finally
    FreeAndNil(Report);
  end;
end;

procedure TTestCLI.TestMeasurementsList;
begin
  AssertEquals(FErr, 0, Run(['measurements', 'list', CopyExample(ConcatPaths(['measurements', 'person.slm']))]));
  AssertTrue(FOut, Pos('waist_circumference', FOut) > 0);
  AssertEquals(0, Run(['measurements', 'list', InFolder('person.slm'), '--json']));
  AssertTrue('the file itself', FOut.TrimLeft.StartsWith('{'));
end;

procedure TTestCLI.TestMeasurementsSet;
var
  FileName: string;
  Measurements: TMeasurementSet;
  Reason: string;
begin
  Reason := '';
  FileName := CopyExample(ConcatPaths(['measurements', 'person.slm']));
  AssertEquals(FErr, 0, Run(['measurements', 'set', FileName, 'waist_circumference', '700']));
  AssertEquals(Format(rsMeasurementChanged, ['waist_circumference', '712', '700', 'person.slm']), FOut.Trim);
  AssertEquals(0, Run(['measurements', 'set', FileName, 'wrist', '160', '-d', 'Around the wrist']));
  AssertEquals(Format(rsMeasurementAdded, ['wrist', '160', 'person.slm']), FOut.Trim);
  Measurements := TMeasurementSet.Create;
  try
    AssertTrue(Reason, Measurements.LoadFromFile(FileName, Reason));
    AssertEquals('written to the file', 700, Measurements.Find('waist_circumference').Value, 1e-9);
  finally
    FreeAndNil(Measurements);
  end;
end;

procedure TTestCLI.TestMeasurementsSetBadNumber;
begin
  AssertEquals(EXIT_FAILURE, Run(['measurements', 'set', CopyExample(ConcatPaths(['measurements', 'person.slm'])), 'waist', 'lots']));
  AssertEquals(rsMeasurementBadNumber, FErr.Trim);
end;

// The skirt's own set has all it needs; one person's set for the bodice lacks
// the skirt's four
procedure TTestCLI.TestMeasurementsMissing;
var
  Pattern: string;
begin
  Pattern := CopyExample(ConcatPaths(['skirt-block', 'skirt-block.sloper']));
  AssertEquals(FErr, 0, Run(['measurements', 'missing', CopyExample(ConcatPaths(['skirt-block', 'skirt.slm'])), Pattern]));
  AssertEquals(Format(rsNothingMissing, ['skirt.slm', 'skirt-block.sloper']), FOut.Trim);
  AssertEquals(EXIT_PROBLEMS, Run(['measurements', 'missing', CopyExample(ConcatPaths(['measurements', 'person.slm'])), Pattern]));
  AssertEquals(Format(rsMissingCount, ['person.slm', 4, 'skirt-block.sloper']), OutLines[0]);
  AssertEquals(Format(rsMissingKey, ['hip']), OutLines[1]);
end;

procedure TTestCLI.TestMeasurementsUsage;
begin
  AssertEquals(EXIT_FAILURE, Run(['measurements', 'remove', 'a.slm']));
  AssertEquals(rsMeasurementsUsage, FErr.Trim);
end;

procedure TTestCLI.TestDocTopics;
begin
  AssertEquals(0, Run(['doc']));
  AssertTrue(FOut, Pos('cli', FOut) > 0);
end;

procedure TTestCLI.TestDocUnknownTopic;
begin
  AssertEquals(EXIT_FAILURE, Run(['doc', 'nothing']));
  AssertTrue(FErr, FErr.StartsWith(Format(rsUnknownTopic, ['nothing', ''])));
end;

procedure TTestCLI.TestDocToFile;
var
  Page: string;
begin
  Page := InFolder('cli.md');
  AssertEquals(FErr, 0, Run(['doc', 'cli', '-o', Page]));
  AssertTrue('names the materials command', Pos('materials LAYOUT|PATTERN', ReadWholeFile(Page)) > 0);
end;

initialization
  RegisterTest(TTestCLI);
end.
