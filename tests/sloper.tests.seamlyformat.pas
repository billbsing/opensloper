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

// Seamly2D and Valentina measurement files, in and out.
unit Sloper.Tests.SeamlyFormat;

{$mode ObjFPC}{$H+}

interface

uses
  SysUtils, fpcunit, testregistry, Sloper.Tests.TestCase, Sloper.Core.Catalogue, Sloper.Core.Measurements, Sloper.Core.SeamlyFormat;

type
  TTestSeamlyFormat = class(TOSTestCase)
  private
    FCatalogue: TCatalogue;
    FSet: TMeasurementSet;
    FReport: TImportReport;
    FFolder: string;
    function Import(const Text: string): boolean;
    procedure AssertImportFails(const Text, Msg: string);
    function Export(const AName: string; out Notes: TStringArray): string;
    function HasLine(const Lines: TStringArray; const Line: string): boolean;
    function Individual(const AUnit, Items: string): string;
    function MultiSize(const AUnit: string; BaseSize, BaseHeight: integer; const Items: string): string;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestReadsAnIndividualFile;
    procedure TestReadsOlderRootNames;
    procedure TestUnits;
    procedure TestNameFromPerson;
    procedure TestTranslatesAndReports;
    procedure TestKeepsKnownNames;
    procedure TestDropsCustomMark;
    procedure TestCorrectsBadNames;
    procedure TestNumbersTakenKeys;
    procedure TestDescriptions;
    procedure TestFormulaIsReported;
    procedure TestFormulaIsCalculated;
    procedure TestFormulaInOrderOfNeed;
    procedure TestFormulaOperators;
    procedure TestFormulaInFileUnits;
    procedure TestFormulaLoopIsReported;
    procedure TestFormulaDivisionByZero;
    procedure TestMultiSizeValues;
    procedure TestMultiSizeInCentimetres;
    procedure TestMultiSizeStaysInRange;
    procedure TestMultiSizeReportsHeights;
    procedure TestRefusals;
    procedure TestBrokenFile;
    procedure TestFailureLeavesSetEmpty;
    procedure TestNewerIsNoted;
    procedure TestFileNameBecomesName;
    procedure TestKinds;
    procedure TestExportsIndividual;
    procedure TestExportRootsAndVersions;
    procedure TestExportTranslatesBack;
    procedure TestExportMarksCustom;
    procedure TestExportEscapes;
    procedure TestExportOneSizeOfATable;
    procedure TestExportNeverRepeatsAName;
    procedure TestIndividualRoundTrip;
    procedure TestMultiSizeRoundTrip;
    procedure TestMultiSizeNotesCurves;
    procedure TestMultiSizeNeedsATable;
    procedure TestMultiSizeNeedsNumberedSizes;
    procedure TestBadExtension;
  end;

implementation

uses
  Sloper.Core.AppPaths, Sloper.Core.JSON;

function TTestSeamlyFormat.Individual(const AUnit, Items: string): string;
begin
  Result := '<?xml version="1.0" encoding="UTF-8"?><smis><version>0.3.4</version><read-only>false</read-only><notes>Fitted</notes><unit>' + AUnit +
    '</unit><pm_system>998</pm_system><personal><family-name>Doe</family-name><given-name>Sam</given-name><birth-date>1800-01-01</birth-date>' +
    '<gender>unknown</gender><email/></personal><body-measurements>' + Items + '</body-measurements></smis>';
end;

function TTestSeamlyFormat.MultiSize(const AUnit: string; BaseSize, BaseHeight: integer; const Items: string): string;
begin
  Result := Format('<?xml version="1.0" encoding="UTF-8"?><smms><version>0.4.5</version><read-only>false</read-only><notes/><unit>%s</unit>' +
    '<pm_system>998</pm_system><size base="%d"/><height base="%d"/><body-measurements>%s</body-measurements></smms>', [AUnit, BaseSize, BaseHeight, Items]);
end;

procedure TTestSeamlyFormat.SetUp;
var
  Err: string;
begin
  FCatalogue := TCatalogue.Create;
  AssertTrue(Err, FCatalogue.LoadFromFile(TAppPaths.CatalogueFile, Err));
  FSet := TMeasurementSet.Create;
  FFolder := IncludeTrailingPathDelimiter(GetTempDir) + 'sloper-seamly-' + IntToStr(Random(MaxInt));
  ForceDirectories(FFolder);
end;

procedure TTestSeamlyFormat.TearDown;
var
  Found: TSearchRec;
begin
  if FindFirst(ConcatPaths([FFolder, '*']), faAnyFile, Found) = 0 then
    repeat
      DeleteFile(ConcatPaths([FFolder, Found.Name]));
    until FindNext(Found) <> 0;
  FindClose(Found);
  RemoveDir(FFolder);
  FreeAndNil(FSet);
  FreeAndNil(FCatalogue);
end;

function TTestSeamlyFormat.Import(const Text: string): boolean;
var
  Err: string;
begin
  Result := ImportSeamly(Text, FCatalogue, FSet, FReport, Err);
  AssertTrue(Err, Result);
end;

procedure TTestSeamlyFormat.AssertImportFails(const Text, Msg: string);
var
  Err: string;
begin
  AssertFalse(Msg + ' loads', ImportSeamly(Text, FCatalogue, FSet, FReport, Err));
  AssertEquals(Msg, Err);
end;

function TTestSeamlyFormat.Export(const AName: string; out Notes: TStringArray): string;
var
  Err, Path: string;
begin
  Path := ConcatPaths([FFolder, AName]);
  AssertTrue(Err, ExportSeamlyFile(Path, FCatalogue, FSet, Notes, Err));
  AssertTrue(Err, ReadTextFile(Path, Result, Err));
end;

function TTestSeamlyFormat.HasLine(const Lines: TStringArray; const Line: string): boolean;
var
  Candidate: string;
begin
  for Candidate in Lines do
    if Candidate = Line then
      Exit(True);
  Result := False;
end;

procedure TTestSeamlyFormat.TestReadsAnIndividualFile;
begin
  Import(Individual('mm', '<m name="waist_circ" value="820"/><m name="hip_circ" value="960.5"/>'));
  AssertEquals(2, FSet.Count);
  AssertNear('waist', 820, FSet.Find('waist_circumference').Value);
  AssertNear('hip', 960.5, FSet.Find('hip_circumference').Value);
  AssertEquals('Fitted', FSet.Notes);
  AssertEquals('a personal set', 0, FSet.SizeCount);
end;

procedure TTestSeamlyFormat.TestReadsOlderRootNames;
begin
  Import('<vit><version>0.3.3</version><unit>mm</unit><body-measurements><m name="waist_circ" value="1"/></body-measurements></vit>');
  AssertEquals(1, FSet.Count);
  Import('<vst><version>0.4.4</version><unit>mm</unit><size base="500"/><height base="1760"/><body-measurements>' +
    '<m name="waist_circ" base="800" size_increase="20" height_increase="0"/></body-measurements></vst>');
  AssertEquals(7, FSet.SizeCount);
end;

procedure TTestSeamlyFormat.TestUnits;
begin
  Import(Individual('cm', '<m name="waist_circ" value="82.5"/>'));
  AssertNear('cm', 825, FSet.Find('waist_circumference').Value);
  Import(Individual('inch', '<m name="waist_circ" value="10"/>'));
  AssertNear('inch', 254, FSet.Find('waist_circumference').Value);
end;

procedure TTestSeamlyFormat.TestNameFromPerson;
begin
  Import(Individual('mm', ''));
  AssertEquals('Sam Doe', FSet.Name);
end;

procedure TTestSeamlyFormat.TestTranslatesAndReports;
begin
  Import(Individual('mm', '<m name="waist_circ" value="820"/>'));
  AssertTrue(HasLine(FReport.Translated, 'waist_circ -> waist_circumference'));
  AssertEquals(0, Length(FReport.Kept));
  AssertEquals(0, Length(FReport.Corrected));
end;

procedure TTestSeamlyFormat.TestKeepsKnownNames;
begin
  Import(Individual('mm', '<m name="neck_arc_f" value="200"/>'));
  AssertNotNull('kept as it is', FSet.Find('neck_arc_f'));
  AssertTrue(HasLine(FReport.Kept, 'neck_arc_f'));
end;

procedure TTestSeamlyFormat.TestDropsCustomMark;
begin
  Import(Individual('mm', '<m name="@M_1" value="5"/>'));
  AssertNotNull(FSet.Find('M_1'));
  AssertTrue('still listed', HasLine(FReport.Kept, '@M_1 -> M_1'));
end;

procedure TTestSeamlyFormat.TestCorrectsBadNames;
begin
  Import(Individual('mm', '<m name="@ширина" value="5"/><m name="@2nd" value="6"/>'));
  AssertEquals(2, FSet.Count);
  AssertEquals(2, Length(FReport.Corrected));
  AssertNotNull('not starting with a digit', FSet.Find('m2nd'));
end;

procedure TTestSeamlyFormat.TestNumbersTakenKeys;
begin
  Import(Individual('mm', '<m name="@ease" value="1"/><m name="@EASE" value="2"/>'));
  AssertEquals('never dropped', 2, FSet.Count);
  AssertNear('the next free number', 2, FSet.Find('EASE2').Value);
  AssertTrue(HasLine(FReport.Corrected, '@EASE -> EASE2'));
end;

procedure TTestSeamlyFormat.TestDescriptions;
begin
  Import(Individual('mm', '<m name="@a" value="1" description="Told" full_name="Name"/><m name="@b" value="1" full_name="Name"/>' +
    '<m name="waist_circ" value="1"/><m name="hip_circ" value="1" description="Mine"/>'));
  AssertEquals('Told', FSet.Find('a').Description);
  AssertEquals('Name', FSet.Find('b').Description);
  AssertEquals('from the catalogue', FCatalogue.Find('waist_circumference').Description, FSet.Find('waist_circumference').Description);
  AssertEquals('Mine', FSet.Find('hip_circumference').Description);
end;

procedure TTestSeamlyFormat.TestFormulaIsReported;
begin
  Import(Individual('mm', '<m name="waist_circ" value="hip_circ/2"/>'));
  AssertNear('left at 0', 0, FSet.Find('waist_circumference').Value);
  AssertTrue(HasLine(FReport.Notes, Format(rsSeamlyFormula, ['waist_circumference', 'hip_circ/2'])));
end;

procedure TTestSeamlyFormat.TestFormulaIsCalculated;
begin
  Import(Individual('mm', '<m name="hip_circ" value="960"/><m name="waist_circ" value="hip_circ/2 - 10"/>'));
  AssertNear('calculated', 470, FSet.Find('waist_circumference').Value);
  AssertTrue(HasLine(FReport.Notes, Format(rsSeamlyCalculated, ['waist_circumference', 'hip_circ/2 - 10'])));
end;

// One may use a value that comes later in the file, itself a formula
procedure TTestSeamlyFormat.TestFormulaInOrderOfNeed;
begin
  Import(Individual('mm', '<m name="@a" value="@b + 1"/><m name="@b" value="@c * 2"/><m name="@c" value="10"/>'));
  AssertNear('chained', 21, FSet.Find('a').Value);
end;

procedure TTestSeamlyFormat.TestFormulaOperators;
begin
  Import(Individual('mm', '<m name="@a" value="(1 + 2) * 3"/><m name="@b" value="-2 + 10 / 4"/><m name="@c" value="2 - (3 - 1)"/><m name="@d" value="1.5e1"/>'));
  AssertNear('brackets', 9, FSet.Find('a').Value);
  AssertNear('order', 0.5, FSet.Find('b').Value);
  AssertNear('nested', 0, FSet.Find('c').Value);
  AssertNear('a plain number', 15, FSet.Find('d').Value);
end;

procedure TTestSeamlyFormat.TestFormulaInFileUnits;
begin
  Import(Individual('cm', '<m name="hip_circ" value="96"/><m name="waist_circ" value="hip_circ + 1"/>'));
  AssertNear('worked in cm, stored in mm', 970, FSet.Find('waist_circumference').Value);
end;

procedure TTestSeamlyFormat.TestFormulaLoopIsReported;
begin
  Import(Individual('mm', '<m name="@a" value="@b + 1"/><m name="@b" value="@a + 1"/>'));
  AssertTrue(HasLine(FReport.Notes, Format(rsSeamlyFormula, ['a', '@b + 1'])));
  AssertTrue(HasLine(FReport.Notes, Format(rsSeamlyFormula, ['b', '@a + 1'])));
end;

procedure TTestSeamlyFormat.TestFormulaDivisionByZero;
begin
  Import(Individual('mm', '<m name="@a" value="1 / 0"/>'));
  AssertTrue(HasLine(FReport.Notes, Format(rsSeamlyFormula, ['a', '1 / 0'])));
end;

procedure TTestSeamlyFormat.TestMultiSizeValues;
begin
  Import(MultiSize('mm', 500, 1760, '<m name="waist_circ" base="800" size_increase="20" height_increase="5"/>'));
  AssertEquals(7, FSet.SizeCount);
  AssertEquals('44', FSet.Sizes[0]);
  AssertEquals('50', FSet.Sizes[3]);
  AssertEquals('56', FSet.Sizes[6]);
  AssertNear('the base', 800, FSet.Find('waist_circumference').ValueFor(3));
  AssertNear('one step up', 820, FSet.Find('waist_circumference').ValueFor(4));
  AssertNear('three down', 740, FSet.Find('waist_circumference').ValueFor(0));
end;

procedure TTestSeamlyFormat.TestMultiSizeInCentimetres;
begin
  Import(MultiSize('cm', 50, 176, '<m name="waist_circ" base="80" size_increase="2" height_increase="0"/>'));
  AssertEquals('50', FSet.Sizes[3]);
  AssertNear('the base', 800, FSet.Find('waist_circumference').ValueFor(3));
  AssertNear('one step up', 820, FSet.Find('waist_circumference').ValueFor(4));
end;

procedure TTestSeamlyFormat.TestMultiSizeStaysInRange;
begin
  Import(MultiSize('cm', 24, 176, ''));
  AssertEquals('22', FSet.Sizes[0]);
  Import(MultiSize('cm', 70, 176, ''));
  AssertEquals('72', FSet.Sizes[FSet.SizeCount - 1]);
end;

procedure TTestSeamlyFormat.TestMultiSizeReportsHeights;
begin
  Import(MultiSize('mm', 500, 1760, ''));
  AssertTrue(HasLine(FReport.Notes, Format(rsSeamlyHeights, ['176'])));
  AssertTrue(HasLine(FReport.Notes, Format(rsSeamlySizesTaken, ['44', '56', '50'])));
end;

procedure TTestSeamlyFormat.TestRefusals;
begin
  AssertImportFails('<pattern/>', rsSeamlyNotMeasurements);
  AssertImportFails('<vit><version>0.2.0</version></vit>', Format(rsSeamlyTooOld, ['0.2.0', '0.3.0']));
  AssertImportFails('<vst><version>0.3.0</version></vst>', Format(rsSeamlyTooOld, ['0.3.0', '0.4.0']));
  AssertImportFails('<smis><version>0.3.4</version><unit>ell</unit></smis>', Format(rsSeamlyBadUnit, ['ell']));
  AssertImportFails(MultiSize('inch', 50, 176, ''), rsSeamlyInches);
  AssertImportFails('<smms><version>0.4.5</version><unit>mm</unit></smms>', rsSeamlyBadBase);
  AssertImportFails('<smis><version>0.3.4</version><unit>mm</unit></smis>', rsSeamlyNotMeasurements);
end;

procedure TTestSeamlyFormat.TestBrokenFile;
var
  Err: string;
begin
  AssertFalse(ImportSeamly('<smis><version>', FCatalogue, FSet, FReport, Err));
  AssertTrue(Err, Pos('could not be read', Err) > 0);
end;

procedure TTestSeamlyFormat.TestFailureLeavesSetEmpty;
var
  Err: string;
begin
  Import(Individual('mm', '<m name="waist_circ" value="1"/>'));
  AssertFalse(ImportSeamly('<pattern/>', FCatalogue, FSet, FReport, Err));
  AssertEquals(0, FSet.Count);
end;

procedure TTestSeamlyFormat.TestNewerIsNoted;
begin
  Import('<smis><version>9.0.0</version><unit>mm</unit><body-measurements/></smis>');
  AssertTrue(HasLine(FReport.Notes, Format(rsSeamlyNewer, ['9.0.0'])));
end;

procedure TTestSeamlyFormat.TestFileNameBecomesName;
var
  Err, Path: string;
begin
  Path := ConcatPaths([FFolder, 'gost.smms']);
  AssertTrue(Err, WriteTextFile(Path, MultiSize('mm', 500, 1760, ''), Err));
  AssertTrue(Err, ImportSeamlyFile(Path, FCatalogue, FSet, FReport, Err));
  AssertEquals('gost', FSet.Name);
end;

procedure TTestSeamlyFormat.TestKinds;
var
  Multi: boolean;
begin
  AssertTrue(SeamlyFileKind('a.smis', Multi));
  AssertFalse(Multi);
  AssertTrue(SeamlyFileKind('a.VIT', Multi));
  AssertFalse(Multi);
  AssertTrue(SeamlyFileKind('a.smms', Multi));
  AssertTrue(Multi);
  AssertTrue(SeamlyFileKind('a.vst', Multi));
  AssertTrue(Multi);
  AssertFalse(SeamlyFileKind('a.slm', Multi));
end;

procedure TTestSeamlyFormat.TestExportsIndividual;
var
  Notes: TStringArray;
  Text: string;
begin
  FSet.Name := 'Sam';
  FSet.Notes := 'Fitted';
  FSet.Add('waist_circumference', 820, 'Round it');
  Text := Export('a.smis', Notes);
  AssertTrue(Text, Pos('<smis>', Text) > 0);
  AssertTrue(Text, Pos('<unit>mm</unit>', Text) > 0);
  AssertTrue(Text, Pos('name="waist_circ" value="820"', Text) > 0);
  AssertTrue(Text, Pos('description="Round it"', Text) > 0);
  AssertTrue(Text, Pos('full_name="Waist circumference"', Text) > 0);
  AssertTrue(Text, Pos('<family-name>Sam</family-name>', Text) > 0);
end;

procedure TTestSeamlyFormat.TestExportRootsAndVersions;
var
  Notes: TStringArray;
begin
  AssertTrue(Pos('<version>0.3.4</version>', Export('a.smis', Notes)) > 0);
  AssertTrue(Pos('<vit>', Export('a.vit', Notes)) > 0);
  AssertTrue(Pos('<version>0.3.3</version>', Export('b.vit', Notes)) > 0);
  FSet.AddSize('50');
  AssertTrue(Pos('<smms>', Export('a.smms', Notes)) > 0);
  AssertTrue(Pos('<version>0.4.5</version>', Export('b.smms', Notes)) > 0);
  AssertTrue(Pos('<vst>', Export('a.vst', Notes)) > 0);
  AssertTrue(Pos('<version>0.4.4</version>', Export('b.vst', Notes)) > 0);
end;

procedure TTestSeamlyFormat.TestExportTranslatesBack;
var
  Notes: TStringArray;
begin
  FSet.Add('neck_arc_f', 200);
  AssertTrue('their own name goes back unchanged', Pos('name="neck_arc_f"', Export('a.smis', Notes)) > 0);
  AssertEquals('nothing to report', 0, Length(Notes));
end;

procedure TTestSeamlyFormat.TestExportMarksCustom;
var
  Notes: TStringArray;
begin
  FSet.Add('ease', 15);
  AssertTrue(Pos('name="@ease"', Export('a.smis', Notes)) > 0);
  AssertTrue(HasLine(Notes, Format(rsSeamlyCustom, ['ease', 'ease'])));
end;

procedure TTestSeamlyFormat.TestExportEscapes;
var
  Notes: TStringArray;
begin
  FSet.Name := 'A & B';
  FSet.Add('ease', 15, '"<fit>"');
  Import(Export('a.smis', Notes));
  AssertEquals('reads back', '"<fit>"', FSet.Find('ease').Description);
end;

procedure TTestSeamlyFormat.TestExportOneSizeOfATable;
var
  Notes: TStringArray;
  Text: string;
begin
  FSet.AddSize('S');
  FSet.AddSize('M');
  FSet.Add('waist_circumference', 700).SetValueFor(1, 760);
  FSet.Add('hip_circumference', 900).ClearValueFor(1);
  FSet.SelectSize('M');
  Text := Export('a.smis', Notes);
  AssertTrue(Text, Pos('value="760"', Text) > 0);
  AssertEquals('no value, no line', 0, Pos('hip_circ', Text));
  AssertTrue(HasLine(Notes, Format(rsSeamlyOneSize, ['M'])));
  AssertTrue(HasLine(Notes, Format(rsSeamlySkipped, ['hip_circumference', 'M'])));
end;

procedure TTestSeamlyFormat.TestExportNeverRepeatsAName;
var
  Notes: TStringArray;
  Text: string;
begin
  FSet.Add('waist_circumference', 800);
  FSet.Add('waist_circ', 810);
  Text := Export('a.smis', Notes);
  AssertTrue(Text, Pos('name="@waist_circ"', Text) > 0);
  AssertTrue(HasLine(Notes, Format(rsSeamlyNameTaken, ['waist_circ', 'waist_circ'])));
end;

procedure TTestSeamlyFormat.TestIndividualRoundTrip;
var
  Notes: TStringArray;
begin
  FSet.Name := 'Sam';
  FSet.Add('waist_circumference', 820.5, 'Waist');
  FSet.Add('neck_arc_f', 200);
  FSet.Add('ease', 15);
  Import(Export('a.smis', Notes));
  AssertEquals(3, FSet.Count);
  AssertEquals('Sam', FSet.Name);
  AssertNear('value', 820.5, FSet.Find('waist_circumference').Value);
  AssertNotNull(FSet.Find('neck_arc_f'));
  AssertNotNull(FSet.Find('ease'));
end;

procedure TTestSeamlyFormat.TestMultiSizeRoundTrip;
var
  Notes: TStringArray;
  Err: string;
begin
  AssertTrue(Err, FSet.LoadFromText('{"format": "measurements", "version": 1, "sizes": ["48", "50", "52"], ' +
    '"measurements": [{"key": "waist_circumference", "values": [780, 800, 820]}]}', Err));
  Import(Export('a.smms', Notes));
  AssertEquals('around the base', 7, FSet.SizeCount);
  AssertNear('base', 800, FSet.Find('waist_circumference').ValueFor(FSet.IndexOfSize('50')));
  AssertNear('one up', 820, FSet.Find('waist_circumference').ValueFor(FSet.IndexOfSize('52')));
  AssertNear('one down', 780, FSet.Find('waist_circumference').ValueFor(FSet.IndexOfSize('48')));
end;

procedure TTestSeamlyFormat.TestMultiSizeNotesCurves;
var
  Notes: TStringArray;
  Err: string;
begin
  AssertTrue(Err, FSet.LoadFromText('{"format": "measurements", "version": 1, "sizes": ["48", "50", "52"], ' +
    '"measurements": [{"key": "waist_circumference", "values": [780, 815, 820]}, {"key": "hip_circumference", "values": [900, null, 940]}]}', Err));
  Export('a.smms', Notes);
  AssertTrue(HasLine(Notes, Format(rsSeamlyNotStraight, ['waist_circumference', '50', '800', '815'])));
  AssertTrue(HasLine(Notes, Format(rsSeamlySkipped, ['hip_circumference', '50'])));
end;

procedure TTestSeamlyFormat.TestMultiSizeNeedsATable;
var
  Notes: TStringArray;
  Err: string;
begin
  AssertFalse(ExportSeamlyFile(ConcatPaths([FFolder, 'a.smms']), FCatalogue, FSet, Notes, Err));
  AssertEquals(rsSeamlyWrongKind, Err);
end;

procedure TTestSeamlyFormat.TestMultiSizeNeedsNumberedSizes;
var
  Notes: TStringArray;
  Err: string;
begin
  FSet.AddSize('M');
  AssertFalse(ExportSeamlyFile(ConcatPaths([FFolder, 'a.smms']), FCatalogue, FSet, Notes, Err));
  AssertEquals(Format(rsSeamlyBadSizes, ['M']), Err);
  FSet.Clear;
  FSet.AddSize('51');
  AssertFalse('odd', ExportSeamlyFile(ConcatPaths([FFolder, 'a.smms']), FCatalogue, FSet, Notes, Err));
  FSet.Clear;
  FSet.AddSize('80');
  AssertFalse('out of range', ExportSeamlyFile(ConcatPaths([FFolder, 'a.smms']), FCatalogue, FSet, Notes, Err));
  AssertFalse('nothing written', FileExists(ConcatPaths([FFolder, 'a.smms'])));
end;

procedure TTestSeamlyFormat.TestBadExtension;
var
  Notes: TStringArray;
  Err: string;
begin
  AssertFalse(ExportSeamlyFile(ConcatPaths([FFolder, 'a.txt']), FCatalogue, FSet, Notes, Err));
  AssertEquals(rsSeamlyBadExtension, Err);
end;

initialization
  RegisterTest(TTestSeamlyFormat);

end.
