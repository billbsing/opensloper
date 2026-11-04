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

// Seamly2D and Valentina measurement files. Individual files (.smis, .vit) hold
// one person's values. Multi-size files (.smms, .vst) hold a base value with an
// increase for each 2 cm of size and 6 cm of height, whereas a size table has
// one value per size in one dimension: importing gives the sizes around the
// base at its height, and exporting fits a straight line through the table.
// Names go through the catalogue's translations, and every change made on the
// way is reported, so nothing is altered silently. No LCL dependency.
unit Sloper.Core.SeamlyFormat;

{$mode ObjFPC}{$H+}

interface

uses
  SysUtils, Sloper.Core.Catalogue, Sloper.Core.Measurements;

const
  // How many sizes either side of a multi-size file's base become columns
  ImportSizeSpan = 3;

type
  TImportReport = record
    // Lines of the form "waist_circ -> waist_circumference"
    Translated: TStringArray;
    // Names with no translation, kept as custom keys
    Kept: TStringArray;
    // Names that broke our rules, or were taken, and had to change
    Corrected: TStringArray;
    // Anything else that was left out or could not be read
    Notes: TStringArray;
  end;

// Fills Measurements from a file's text; its root element says which kind it
// is. On failure Measurements is left empty and ErrorMessage says why.
function ImportSeamly(const Text: string; Catalogue: TCatalogue; Measurements: TMeasurementSet; out Report: TImportReport; out ErrorMessage: string): boolean;
function ImportSeamlyFile(const FileName: string; Catalogue: TCatalogue; Measurements: TMeasurementSet; out Report: TImportReport;
  out ErrorMessage: string): boolean;
// True for a file name Export can write, MultiSize saying which kind it is
function SeamlyFileKind(const FileName: string; out MultiSize: boolean): boolean;
// Writes the kind the extension asks for. An individual file takes the set's
// selected size. Notes lists what could not be carried over exactly.
function ExportSeamlyFile(const FileName: string; Catalogue: TCatalogue; Measurements: TMeasurementSet; out Notes: TStringArray;
  out ErrorMessage: string): boolean;

resourcestring
  rsSeamlyNotMeasurements = 'This is not a Seamly2D or Valentina measurement file';
  rsSeamlyBadFile = 'The file could not be read: %s';
  rsSeamlyTooOld = 'This file''s format, version %s, is older than version %s, the oldest that can be read. Open it in Seamly2D and save it again first';
  rsSeamlyBadUnit = 'The file''s unit "%s" is not known';
  rsSeamlyInches = 'Multi-size files in inches cannot be read, as Seamly2D does not support them';
  rsSeamlyBadBase = 'The file has no valid base size and height';
  rsSeamlyNewer = 'The file''s format, version %s, is newer than this program knows; check the values';
  rsSeamlyFormula = '%s is the formula "%s", which cannot be worked out, so it was left at 0';
  rsSeamlyCalculated = '%s was the formula "%s"; it holds the value that gives, and will not follow changes to the others';
  rsSeamlyBadNumber = '%s has no valid value, so it was left at 0';
  rsSeamlyHeights = 'All values are for height %s cm, the file''s base; its other heights were left out';
  rsSeamlySizesTaken = 'Sizes %s to %s were taken, either side of the base size %s';
  rsSeamlyWrongKind = 'A multi-size file needs a size table. Use an individual file (.smis) for a single set';
  rsSeamlyBadSizes = 'Size "%s" cannot go in a multi-size file: sizes must be even whole numbers from 22 to 72';
  rsSeamlyBadExtension = 'Use .smis, .vit, .smms or .vst';
  rsSeamlyCustom = '%s has no Seamly2D name, so it was written as the custom measurement @%s';
  rsSeamlyNameTaken = '%s would share a name with another measurement, so it was written as the custom measurement @%s';
  rsSeamlySkipped = '%s has no value for size %s, so it was left out';
  rsSeamlyOneSize = 'The individual file holds size %s, the one selected';
  rsSeamlyNoHeights = 'A size table has no heights, so every height increase is 0 from height 176 cm';
  rsSeamlyNotStraight = '%s does not follow a straight line through the sizes, so at size %s it will be %s mm, not %s';

implementation

uses
  Classes, Math, Generics.Collections, DOM, XMLRead, Sloper.Core.JSON, Sloper.Core.Names;

type
  TValueMap = specialize TDictionary<string, double>;

  // A value in the file that is not a plain number
  TPendingFormula = record
    Measurement: TMeasurement;
    Name, Text: string;
  end;

const
  MillimetresPerInch = 25.4;
  SizeStep = 2;
  MinSize = 22;
  MaxSize = 72;
  // Written when a set has no height to go by
  DefaultHeight = 176;
  // How far a value may stray from the line before it is reported
  LineTolerance = 0.5;
  CustomMark = '@';
  VersionIndividual = '0.3.4';
  VersionIndividualOld = '0.3.3';
  VersionMultiSize = '0.4.5';
  VersionMultiSizeOld = '0.4.4';
  OldestIndividual = '0.3.0';
  OldestMultiSize = '0.4.0';

procedure AddLine(var Lines: TStringArray; const Line: string);
begin
  Insert(Line, Lines, Length(Lines));
end;

// Compares dotted versions part by part
function CompareVersions(const First, Second: string): integer;
var
  FirstParts, SecondParts: TStringArray;
  Index, Count: integer;
begin
  FirstParts := First.Split('.');
  SecondParts := Second.Split('.');
  Count := Max(Length(FirstParts), Length(SecondParts));
  Result := 0;
  for Index := 0 to Count - 1 do
  begin
    if Index >= Length(FirstParts) then
      Exit(-1);
    if Index >= Length(SecondParts) then
      Exit(1);
    Result := CompareValue(StrToIntDef(FirstParts[Index], 0), StrToIntDef(SecondParts[Index], 0));
    if Result <> 0 then
      Exit;
  end;
end;

function ParseNumber(const Text: string; out Value: double): boolean;
var
  Settings: TFormatSettings;
begin
  Settings := DefaultFormatSettings;
  Settings.DecimalSeparator := '.';
  Result := TryStrToFloat(Trim(Text), Value, Settings);
end;

function FormatNumber(Value: double): string;
begin
  Result := FormatJSONFloat(RoundTo(Value, -6));
end;

function ChildText(Parent: TDOMNode; const TagName: string): string;
var
  Child: TDOMNode;
begin
  Result := '';
  Child := Parent.FindNode(unicodestring(TagName));
  if Assigned(Child) then
    Result := UTF8Encode(Child.TextContent);
end;

function ChildAttribute(Parent: TDOMNode; const TagName, Attribute: string): string;
var
  Child: TDOMNode;
begin
  Result := '';
  Child := Parent.FindNode(unicodestring(TagName));
  if Child is TDOMElement then
    Result := UTF8Encode(TDOMElement(Child).GetAttribute(unicodestring(Attribute)));
end;

function AttributeOf(Element: TDOMElement; const Attribute: string): string;
begin
  Result := UTF8Encode(Element.GetAttribute(unicodestring(Attribute)));
end;

// Letters, digits and underscores, not starting with a digit
function CleanKey(const Name: string): string;
var
  Index: integer;
begin
  Result := Name;
  for Index := 1 to Length(Result) do
    if not (Result[Index] in ['A'..'Z', 'a'..'z', '0'..'9', '_']) then
      Result[Index] := '_';
  if (Result = '') or (Result[1] in ['0'..'9']) then
    Result := 'm' + Result;
end;

function FreeKey(Measurements: TMeasurementSet; const Key: string): string;
var
  Number: integer;
begin
  Result := Key;
  Number := 1;
  while Assigned(Measurements.Find(Result)) do
  begin
    Inc(Number);
    Result := Key + IntToStr(Number);
  end;
end;

// Adds one measurement under the key its name comes to, reporting the change
function AddImported(Item: TDOMElement; Catalogue: TCatalogue; Measurements: TMeasurementSet; var Report: TImportReport): TMeasurement;
var
  Name, Custom, Wanted, Key, Description: string;
  Entry: TCatalogueEntry;
  Reason: string;
begin
  Name := AttributeOf(Item, 'name');
  Description := AttributeOf(Item, 'description');
  if Description = '' then
    Description := AttributeOf(Item, 'full_name');
  Entry := Catalogue.FindTranslated(FormatSeamly2D, Name);
  if Assigned(Entry) then
  begin
    Wanted := Entry.Key;
    if Description = '' then
      Description := Entry.Description;
  end
  else
  begin
    Custom := Name;
    if Copy(Custom, 1, Length(CustomMark)) = CustomMark then
      Delete(Custom, 1, Length(CustomMark));
    Wanted := CleanKey(Custom);
    if not CheckName(Wanted, Reason) then
      Wanted := 'm_' + Wanted;
  end;
  Key := FreeKey(Measurements, Wanted);
  if Assigned(Entry) and (Key = Wanted) then
    AddLine(Report.Translated, Name + ' -> ' + Key)
  else if not Assigned(Entry) and (Key = Name) then
    AddLine(Report.Kept, Name)
  else if not Assigned(Entry) and (Key = Custom) then
    AddLine(Report.Kept, Name + ' -> ' + Key)
  else
    AddLine(Report.Corrected, Name + ' -> ' + Key);
  Result := Measurements.Add(Key, 0, Description);
end;

// A value in the file's unit, as mm
function ToMillimetres(Value: double; const AUnit: string): double;
begin
  if AUnit = 'cm' then
    Result := Value * 10
  else if AUnit = 'inch' then
    Result := Value * MillimetresPerInch
  else
    Result := Value;
end;

// Arithmetic on numbers and the file's other values. False for anything else,
// such as a function, or a name with no value yet.
function CalculateFormula(const Text: string; Values: TValueMap; out Value: double): boolean;
const
  Operators = ['+', '-', '*', '/', '(', ')'];
var
  Position: integer;

  procedure SkipSpaces;
  begin
    while (Position <= Length(Text)) and (Text[Position] in [' ', #9]) do
      Inc(Position);
  end;

  function Accept(Character: char): boolean;
  begin
    SkipSpaces;
    Result := (Position <= Length(Text)) and (Text[Position] = Character);
    if Result then
      Inc(Position);
  end;

  function ParseSum(out Sum: double): boolean; forward;

  function ParseAtom(out Atom: double): boolean;
  var
    Start: integer;
    word: string;
  begin
    SkipSpaces;
    Start := Position;
    while (Position <= Length(Text)) and not (Text[Position] in Operators + [' ', #9]) do
    begin
      // The sign of an exponent belongs to the number
      if (Text[Position] in ['e', 'E']) and (Position > Start) and (Text[Start] in ['0'..'9', '.']) and (Position < Length(Text)) and
        (Text[Position + 1] in ['+', '-']) then
        Inc(Position);
      Inc(Position);
    end;
    word := Copy(Text, Start, Position - Start);
    Result := (word <> '') and (ParseNumber(word, Atom) or Values.TryGetValue(word, Atom));
  end;

  function ParseFactor(out Factor: double): boolean;
  begin
    if Accept('-') then
    begin
      Result := ParseFactor(Factor);
      Factor := -Factor;
    end
    else if Accept('+') then
      Result := ParseFactor(Factor)
    else if Accept('(') then
      Result := ParseSum(Factor) and Accept(')')
    else
      Result := ParseAtom(Factor);
  end;

  function ParseProduct(out Product: double): boolean;
  var
    Next: double;
  begin
    Result := ParseFactor(Product);
    while Result do
      if Accept('*') then
      begin
        Result := ParseFactor(Next);
        Product := Product * Next;
      end
      else if Accept('/') then
      begin
        Result := ParseFactor(Next) and (Next <> 0);
        if Result then
          Product := Product / Next;
      end
      else
        Break;
  end;

  function ParseSum(out Sum: double): boolean;
  var
    Next: double;
  begin
    Result := ParseProduct(Sum);
    while Result do
      if Accept('+') then
      begin
        Result := ParseProduct(Next);
        Sum := Sum + Next;
      end
      else if Accept('-') then
      begin
        Result := ParseProduct(Next);
        Sum := Sum - Next;
      end
      else
        Break;
  end;

begin
  Position := 1;
  Result := ParseSum(Value);
  SkipSpaces;
  Result := Result and (Position > Length(Text));
end;

// Formulas may use each other in any order, so this goes round until a pass
// works out no more. What is left is reported.
procedure ResolveFormulas(const Pending: array of TPendingFormula; Values: TValueMap; const AUnit: string; var Report: TImportReport);
var
  Done: array of boolean;
  Index: integer;
  Value: double;
  Progress: boolean;
begin
  Done := nil;
  SetLength(Done, Length(Pending));
  repeat
    Progress := False;
    for Index := 0 to High(Pending) do
      if not Done[Index] and CalculateFormula(Pending[Index].Text, Values, Value) then
      begin
        Pending[Index].Measurement.Value := ToMillimetres(Value, AUnit);
        Values.AddOrSetValue(Pending[Index].Name, Value);
        Done[Index] := True;
        Progress := True;
        AddLine(Report.Notes, Format(rsSeamlyCalculated, [Pending[Index].Measurement.Key, Pending[Index].Text]));
      end;
  until not Progress;
  for Index := 0 to High(Pending) do
    if not Done[Index] then
      AddLine(Report.Notes, Format(rsSeamlyFormula, [Pending[Index].Measurement.Key, Pending[Index].Text]));
end;

function ReadIndividual(Root: TDOMNode; Catalogue: TCatalogue; Measurements: TMeasurementSet; const AUnit: string; var Report: TImportReport): boolean;
var
  Item: TDOMNode;
  Measurement: TMeasurement;
  Text, Family, Given, Name: string;
  Value: double;
  Values: TValueMap;
  Pending: array of TPendingFormula;
begin
  Family := '';
  Given := '';
  Item := Root.FindNode('personal');
  if Assigned(Item) then
  begin
    Family := ChildText(Item, 'family-name');
    Given := ChildText(Item, 'given-name');
  end;
  Measurements.Name := Trim(Given + ' ' + Family);
  Item := Root.FindNode('body-measurements');
  Result := Assigned(Item);
  if not Result then
    Exit;
  Item := Item.FirstChild;
  Pending := nil;
  Values := TValueMap.Create;
  try
    while Assigned(Item) do
    begin
      if (Item is TDOMElement) and (Item.NodeName = 'm') then
      begin
        Measurement := AddImported(TDOMElement(Item), Catalogue, Measurements, Report);
        Name := AttributeOf(TDOMElement(Item), 'name');
        Text := AttributeOf(TDOMElement(Item), 'value');
        if ParseNumber(Text, Value) then
        begin
          Measurement.Value := ToMillimetres(Value, AUnit);
          Values.AddOrSetValue(Name, Value);
        end
        else if Trim(Text) = '' then
          AddLine(Report.Notes, Format(rsSeamlyBadNumber, [Measurement.Key]))
        else
        begin
          SetLength(Pending, Length(Pending) + 1);
          Pending[High(Pending)].Measurement := Measurement;
          Pending[High(Pending)].Name := Name;
          Pending[High(Pending)].Text := Text;
        end;
      end;
      Item := Item.NextSibling;
    end;
    ResolveFormulas(Pending, Values, AUnit, Report);
  finally
    FreeAndNil(Values);
  end;
end;

function ReadMultiSize(Root: TDOMNode; Catalogue: TCatalogue; Measurements: TMeasurementSet; const AUnit: string;
  var Report: TImportReport; out ErrorMessage: string): boolean;
var
  Item: TDOMNode;
  Measurement: TMeasurement;
  BaseSize, BaseHeight, UnitsPerCentimetre, Base, Increase, Steps: double;
  First, Last, Size, Index: integer;
begin
  ErrorMessage := '';
  Result := False;
  if AUnit = 'inch' then
  begin
    ErrorMessage := rsSeamlyInches;
    Exit;
  end;
  UnitsPerCentimetre := IfThen(AUnit = 'mm', 10, 1);
  if not ParseNumber(ChildAttribute(Root, 'size', 'base'), BaseSize) or not ParseNumber(ChildAttribute(Root, 'height', 'base'), BaseHeight) then
  begin
    ErrorMessage := rsSeamlyBadBase;
    Exit;
  end;
  BaseSize := BaseSize / UnitsPerCentimetre;
  BaseHeight := BaseHeight / UnitsPerCentimetre;
  Measurements.Notes := ChildText(Root, 'notes');
  First := Max(Round(BaseSize) - ImportSizeSpan * SizeStep, MinSize);
  Last := Min(Round(BaseSize) + ImportSizeSpan * SizeStep, MaxSize);
  Size := First;
  while Size <= Last do
  begin
    Measurements.AddSize(IntToStr(Size));
    Inc(Size, SizeStep);
  end;
  Item := Root.FindNode('body-measurements');
  if not Assigned(Item) then
  begin
    ErrorMessage := rsSeamlyNotMeasurements;
    Exit;
  end;
  Item := Item.FirstChild;
  while Assigned(Item) do
  begin
    if (Item is TDOMElement) and (Item.NodeName = 'm') then
    begin
      Measurement := AddImported(TDOMElement(Item), Catalogue, Measurements, Report);
      if not ParseNumber(AttributeOf(TDOMElement(Item), 'base'), Base) then
      begin
        Base := 0;
        AddLine(Report.Notes, Format(rsSeamlyBadNumber, [Measurement.Key]));
      end;
      if not ParseNumber(AttributeOf(TDOMElement(Item), 'size_increase'), Increase) then
        Increase := 0;
      for Index := 0 to Measurements.SizeCount - 1 do
      begin
        Steps := (StrToInt(Measurements.Sizes[Index]) - BaseSize) / SizeStep;
        Measurement.SetValueFor(Index, ToMillimetres(Base + Steps * Increase, AUnit));
      end;
    end;
    Item := Item.NextSibling;
  end;
  AddLine(Report.Notes, Format(rsSeamlyHeights, [FormatNumber(BaseHeight)]));
  AddLine(Report.Notes, Format(rsSeamlySizesTaken, [IntToStr(First), IntToStr(Last), FormatNumber(BaseSize)]));
  Result := True;
end;

function ReadRoot(Root: TDOMNode; Catalogue: TCatalogue; Measurements: TMeasurementSet; var Report: TImportReport; out ErrorMessage: string): boolean;
var
  RootName, Version, AUnit, Newest, Oldest: string;
  MultiSize: boolean;
begin
  Result := False;
  ErrorMessage := '';
  RootName := UTF8Encode(Root.NodeName);
  MultiSize := (RootName = 'smms') or (RootName = 'vst');
  if not MultiSize and (RootName <> 'smis') and (RootName <> 'vit') then
  begin
    ErrorMessage := rsSeamlyNotMeasurements;
    Exit;
  end;
  Version := ChildText(Root, 'version');
  Oldest := OldestIndividual;
  Newest := VersionIndividual;
  if MultiSize then
  begin
    Oldest := OldestMultiSize;
    Newest := VersionMultiSize;
  end;
  if CompareVersions(Version, Oldest) < 0 then
  begin
    ErrorMessage := Format(rsSeamlyTooOld, [Version, Oldest]);
    Exit;
  end;
  if CompareVersions(Version, Newest) > 0 then
    AddLine(Report.Notes, Format(rsSeamlyNewer, [Version]));
  AUnit := ChildText(Root, 'unit');
  if (AUnit <> 'mm') and (AUnit <> 'cm') and (AUnit <> 'inch') then
  begin
    ErrorMessage := Format(rsSeamlyBadUnit, [AUnit]);
    Exit;
  end;
  Measurements.Notes := ChildText(Root, 'notes');
  if MultiSize then
    Result := ReadMultiSize(Root, Catalogue, Measurements, AUnit, Report, ErrorMessage)
  else
  begin
    Result := ReadIndividual(Root, Catalogue, Measurements, AUnit, Report);
    if not Result then
      ErrorMessage := rsSeamlyNotMeasurements;
  end;
end;

function ImportSeamly(const Text: string; Catalogue: TCatalogue; Measurements: TMeasurementSet; out Report: TImportReport; out ErrorMessage: string): boolean;
var
  Stream: TStringStream;
  Document: TXMLDocument;
begin
  Result := False;
  Report := Default(TImportReport);
  ErrorMessage := '';
  Measurements.Clear;
  Document := nil;
  Stream := TStringStream.Create(Text);
  try
    try
      ReadXMLFile(Document, Stream);
      Result := ReadRoot(Document.DocumentElement, Catalogue, Measurements, Report, ErrorMessage);
    except
      on Failure: EXMLReadError do
        ErrorMessage := Format(rsSeamlyBadFile, [Failure.Message]);
      on Failure: EDOMError do
        ErrorMessage := Format(rsSeamlyBadFile, [Failure.Message]);
    end;
    if not Result then
      Measurements.Clear;
  finally
    FreeAndNil(Document);
    FreeAndNil(Stream);
  end;
end;

function ImportSeamlyFile(const FileName: string; Catalogue: TCatalogue; Measurements: TMeasurementSet; out Report: TImportReport;
  out ErrorMessage: string): boolean;
var
  Text: string;
begin
  Report := Default(TImportReport);
  Measurements.Clear;
  if not ReadTextFile(FileName, Text, ErrorMessage) then
    Exit(False);
  Result := ImportSeamly(Text, Catalogue, Measurements, Report, ErrorMessage);
  if Result and (Measurements.Name = '') then
    Measurements.Name := ChangeFileExt(ExtractFileName(FileName), '');
end;

function SeamlyFileKind(const FileName: string; out MultiSize: boolean): boolean;
var
  Extension: string;
begin
  Extension := LowerCase(ExtractFileExt(FileName));
  MultiSize := (Extension = '.smms') or (Extension = '.vst');
  Result := MultiSize or (Extension = '.smis') or (Extension = '.vit');
end;

function EscapeXML(const Text: string): string;
begin
  Result := StringReplace(Text, '&', '&amp;', [rfReplaceAll]);
  Result := StringReplace(Result, '<', '&lt;', [rfReplaceAll]);
  Result := StringReplace(Result, '>', '&gt;', [rfReplaceAll]);
  Result := StringReplace(Result, '"', '&quot;', [rfReplaceAll]);
end;

// The name a key goes out under: its translation, a name Seamly2D knows that
// came in unchanged, or a custom name. No two may be the same.
function ExportName(Measurement: TMeasurement; Catalogue: TCatalogue; var Used, Notes: TStringArray): string;
var
  Entry: TCatalogueEntry;
  Taken: string;
  Custom: boolean;
begin
  Entry := Catalogue.Find(Measurement.Key);
  Result := '';
  if Assigned(Entry) then
    Result := Entry.NameIn(FormatSeamly2D)
  else if Catalogue.IsKnownName(FormatSeamly2D, Measurement.Key) then
    Result := Measurement.Key;
  Custom := Result = '';
  if Custom then
  begin
    Result := CustomMark + Measurement.Key;
    AddLine(Notes, Format(rsSeamlyCustom, [Measurement.Key, Measurement.Key]));
  end;
  for Taken in Used do
    if Taken = Result then
    begin
      Result := CustomMark + Measurement.Key;
      AddLine(Notes, Format(rsSeamlyNameTaken, [Measurement.Key, Measurement.Key]));
      Break;
    end;
  AddLine(Used, Result);
end;

function ElementLine(const Name, Value: string; Measurement: TMeasurement; Catalogue: TCatalogue): string;
var
  Entry: TCatalogueEntry;
  FullName: string;
begin
  FullName := '';
  Entry := Catalogue.Find(Measurement.Key);
  if Assigned(Entry) then
    FullName := Entry.Name;
  Result := '        <m name="' + EscapeXML(Name) + '" ' + Value + ' full_name="' + EscapeXML(FullName) + '" description="' +
    EscapeXML(Measurement.Description) + '"/>';
end;

function IndividualText(Measurements: TMeasurementSet; Catalogue: TCatalogue; const RootName, Version: string; var Notes: TStringArray): string;
var
  Lines: TStringList;
  Used: TStringArray;
  Index: integer;
  Name: string;
begin
  Used := nil;
  if Measurements.SizeCount > 0 then
    AddLine(Notes, Format(rsSeamlyOneSize, [Measurements.SizeName]));
  Lines := TStringList.Create;
  try
    Lines.Add('<?xml version="1.0" encoding="UTF-8"?>');
    Lines.Add('<' + RootName + '>');
    Lines.Add('    <version>' + Version + '</version>');
    Lines.Add('    <read-only>false</read-only>');
    Lines.Add('    <notes>' + EscapeXML(Measurements.Notes) + '</notes>');
    Lines.Add('    <unit>mm</unit>');
    Lines.Add('    <pm_system>998</pm_system>');
    Lines.Add('    <personal>');
    Lines.Add('        <family-name>' + EscapeXML(Measurements.Name) + '</family-name>');
    Lines.Add('        <given-name/>');
    Lines.Add('        <birth-date>1800-01-01</birth-date>');
    Lines.Add('        <gender>unknown</gender>');
    Lines.Add('        <email/>');
    Lines.Add('    </personal>');
    Lines.Add('    <body-measurements>');
    for Index := 0 to Measurements.Count - 1 do
      if not Measurements[Index].HasValue then
        AddLine(Notes, Format(rsSeamlySkipped, [Measurements[Index].Key, Measurements.SizeName]))
      else
      begin
        Name := ExportName(Measurements[Index], Catalogue, Used, Notes);
        Lines.Add(ElementLine(Name, 'value="' + FormatNumber(Measurements[Index].Value) + '"', Measurements[Index], Catalogue));
      end;
    Lines.Add('    </body-measurements>');
    Lines.Add('</' + RootName + '>');
    Lines.LineBreak := #10;
    Result := Lines.Text;
  finally
    FreeAndNil(Lines);
  end;
end;

// The increase for one step of size, from the first and last sizes with a value
procedure FitLine(Measurement: TMeasurement; const SizeNumbers: array of integer; BaseSize: integer; out Base, Increase: double);
var
  Index, First, Last: integer;
begin
  First := -1;
  Last := -1;
  for Index := 0 to High(SizeNumbers) do
    if Measurement.HasValueFor(Index) then
    begin
      if First < 0 then
        First := Index;
      Last := Index;
    end;
  Base := 0;
  Increase := 0;
  if First < 0 then
    Exit;
  if Last > First then
    Increase := (Measurement.ValueFor(Last) - Measurement.ValueFor(First)) / ((SizeNumbers[Last] - SizeNumbers[First]) / SizeStep);
  Base := Measurement.ValueFor(First) + (BaseSize - SizeNumbers[First]) / SizeStep * Increase;
end;

function ReadSizeNumbers(Measurements: TMeasurementSet; out SizeNumbers: specialize TArray<integer>; out ErrorMessage: string): boolean;
var
  Index: integer;
begin
  ErrorMessage := '';
  SizeNumbers := nil;
  SetLength(SizeNumbers, Measurements.SizeCount);
  for Index := 0 to High(SizeNumbers) do
    if not TryStrToInt(Measurements.Sizes[Index], SizeNumbers[Index]) or (SizeNumbers[Index] < MinSize) or (SizeNumbers[Index] > MaxSize) or
      Odd(SizeNumbers[Index]) then
    begin
      ErrorMessage := Format(rsSeamlyBadSizes, [Measurements.Sizes[Index]]);
      Exit(False);
    end;
  Result := True;
end;

function MultiSizeText(Measurements: TMeasurementSet; Catalogue: TCatalogue; const RootName, Version: string; out Text: string;
  var Notes: TStringArray; out ErrorMessage: string): boolean;
var
  Lines: TStringList;
  Used: TStringArray;
  SizeNumbers: specialize TArray<integer>;
  Index, SizeIndex, BaseSize: integer;
  Base, Increase, OnLine: double;
  Name: string;
begin
  Text := '';
  if Measurements.SizeCount = 0 then
  begin
    ErrorMessage := rsSeamlyWrongKind;
    Exit(False);
  end;
  Result := ReadSizeNumbers(Measurements, SizeNumbers, ErrorMessage);
  if not Result then
    Exit;
  Used := nil;
  BaseSize := SizeNumbers[Length(SizeNumbers) div 2];
  AddLine(Notes, rsSeamlyNoHeights);
  Lines := TStringList.Create;
  try
    Lines.Add('<?xml version="1.0" encoding="UTF-8"?>');
    Lines.Add('<' + RootName + '>');
    Lines.Add('    <version>' + Version + '</version>');
    Lines.Add('    <read-only>false</read-only>');
    Lines.Add('    <notes>' + EscapeXML(Measurements.Notes) + '</notes>');
    Lines.Add('    <unit>mm</unit>');
    Lines.Add('    <pm_system>998</pm_system>');
    Lines.Add('    <size base="' + IntToStr(BaseSize * 10) + '"/>');
    Lines.Add('    <height base="' + IntToStr(DefaultHeight * 10) + '"/>');
    Lines.Add('    <body-measurements>');
    for Index := 0 to Measurements.Count - 1 do
    begin
      FitLine(Measurements[Index], SizeNumbers, BaseSize, Base, Increase);
      for SizeIndex := 0 to High(SizeNumbers) do
        if Measurements[Index].HasValueFor(SizeIndex) then
        begin
          OnLine := Base + (SizeNumbers[SizeIndex] - BaseSize) / SizeStep * Increase;
          if Abs(OnLine - Measurements[Index].ValueFor(SizeIndex)) > LineTolerance then
            AddLine(Notes, Format(rsSeamlyNotStraight, [Measurements[Index].Key, Measurements.Sizes[SizeIndex], FormatNumber(RoundTo(OnLine, -1)),
              FormatNumber(Measurements[Index].ValueFor(SizeIndex))]));
        end
        else
          AddLine(Notes, Format(rsSeamlySkipped, [Measurements[Index].Key, Measurements.Sizes[SizeIndex]]));
      Name := ExportName(Measurements[Index], Catalogue, Used, Notes);
      Lines.Add(ElementLine(Name, 'base="' + FormatNumber(Base) + '" size_increase="' + FormatNumber(Increase) + '" height_increase="0"',
        Measurements[Index], Catalogue));
    end;
    Lines.Add('    </body-measurements>');
    Lines.Add('</' + RootName + '>');
    Lines.LineBreak := #10;
    Text := Lines.Text;
  finally
    FreeAndNil(Lines);
  end;
end;

function ExportSeamlyFile(const FileName: string; Catalogue: TCatalogue; Measurements: TMeasurementSet; out Notes: TStringArray;
  out ErrorMessage: string): boolean;
var
  MultiSize, Old: boolean;
  Text, Extension: string;
begin
  Notes := nil;
  ErrorMessage := '';
  if not SeamlyFileKind(FileName, MultiSize) then
  begin
    ErrorMessage := rsSeamlyBadExtension;
    Exit(False);
  end;
  Extension := LowerCase(ExtractFileExt(FileName));
  Old := (Extension = '.vit') or (Extension = '.vst');
  Result := True;
  if MultiSize and Old then
    Result := MultiSizeText(Measurements, Catalogue, 'vst', VersionMultiSizeOld, Text, Notes, ErrorMessage)
  else if MultiSize then
    Result := MultiSizeText(Measurements, Catalogue, 'smms', VersionMultiSize, Text, Notes, ErrorMessage)
  else if Old then
    Text := IndividualText(Measurements, Catalogue, 'vit', VersionIndividualOld, Notes)
  else
    Text := IndividualText(Measurements, Catalogue, 'smis', VersionIndividual, Notes);
  if Result then
    Result := WriteTextFileAtomic(FileName, Text, ErrorMessage);
end;

end.
