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

// The file format table holds to the code: a file with every member, read and
// written again, writes only listed members and every one of them, and each
// example on the File formats page is a file as the program writes it.
unit Sloper.Tests.FileInfo;

{$mode ObjFPC}{$H+}

interface

uses
  fpcunit, testregistry, Sloper.Tests.TestCase;

type
  TTestFileInfo = class(TOSTestCase)
  published
    procedure TestEverySavedMemberListed;
    procedure TestEveryListedMemberWritten;
    procedure TestExamplesReadBack;
    procedure TestLayoutMatchesItsUnit;
    procedure TestSchemasForEveryFormat;
  end;

implementation

uses
  SysUtils, Classes, fpjson, Sloper.Core.JSON, Sloper.Core.Pattern, Sloper.Core.PatternFile, Sloper.Core.Measurements,
  Sloper.Core.OperationInfo, Sloper.Core.FileInfo, Sloper.Output.Layout, Sloper.Docs.Schema;

const
  // Every member outside the objects, with values that make the writer write it
  FULL_PATTERN =
    '{"format": "pattern", "version": 1, "units": "cm", "notes": "Notes", "measurementFile": "bill.slm",' +
    ' "identity": "3021d120-7482-45c9-8c9a-1b9c1b60be87", "nextId": 16,' +
    ' "variables": [{"id": 1, "name": "ease", "formula": "2", "description": "Ease"}],' +
    ' "objects": [{"id": 2, "type": "freePoint", "name": "A", "x": "0", "y": "0"},' +
    ' {"id": 10, "type": "freePoint", "name": "B", "x": "10", "y": "0"}, {"id": 11, "type": "freePoint", "name": "C", "x": "0", "y": "10"},' +
    ' {"id": 12, "type": "line", "start": 2, "end": 10, "role": "outline"}, {"id": 13, "type": "line", "start": 10, "end": 11, "role": "outline"},' +
    ' {"id": 14, "type": "line", "start": 11, "end": 2, "role": "outline"},' +
    ' {"id": 15, "type": "piece", "name": "P", "path": [{"edge": 12, "reversed": false}, {"edge": 13, "reversed": false},' +
    ' {"edge": 14, "reversed": false}], "allowance": "1", "grainline": {"angle": "90"}, "cut": {"count": 1, "mirrored": false}}],' +
    ' "materials": [{"id": 3, "name": "Main", "color": "#5B8DB8", "fill": "hatch", "allowance": 1.5, "width": 1400, "length": 900, "allowTurns": true}],' +
    ' "view": {"zoom": 1.5, "centre": [120, -200], "hiddenRoles": ["construction"], "hideAnnotations": true,' +
    ' "hiddenPieces": [15], "isolate": 15, "pieceOrder": [15]}}';
  FULL_MEASUREMENTS =
    '{"format": "measurements", "version": 1, "units": "mm", "name": "Bill", "notes": "Notes",' +
    ' "measurements": [{"key": "waist", "value": 820, "description": "Waist"}]}';
  FULL_SIZE_TABLE =
    '{"format": "measurements", "version": 1, "units": "mm", "name": "Sizes", "notes": "", "sizes": ["36", "38"],' +
    ' "measurements": [{"key": "waist", "values": [700, null], "description": "Waist"}]}';
  FULL_LAYOUT =
    '{"format": "layout", "version": 1, "units": "mm", "name": "Skirt", "nextId": 2,' +
    ' "sources": [{"id": 1, "pattern": "skirt.sloper", "measurementFile": "sizes.slm", "size": "38"}],' +
    ' "output": {"kind": "material", "rollWidth": 900, "paper": "Mine", "paperWidth": 200, "paperHeight": 300,' +
    ' "margin": 5, "overlap": 8, "marks": "halfCircle", "fill": "tint", "profile": "Laser", "outputProfile": "Leather",' +
    ' "materialWidth": 600, "materialLength": 400, "allowTurns": true, "material": "Main", "excludedPages": ["A1"]},' +
    ' "placements": [{"source": 1, "piece": 42, "copy": 2, "x": 20, "y": 30, "rotation": 90, "flipped": true}],' +
    ' "sheetNotes": [{"text": "Cut 2", "x": 10, "y": 10, "size": 14, "align": "centre", "box": true, "font": "DejaVu Sans",' +
    ' "bold": true, "italic": true}],' +
    ' "titleBlock": {"corner": "topRight", "fields": ["pattern.name", "date"], "everyPage": true}}';

// The file as the program writes it after reading Text
function ReadBack(const FormatName, Text: string): string;
var
  Pattern: TPattern;
  MeasurementSet: TMeasurementSet;
  Layout: TLayout;
  Err: string;
begin
  Result := '';
  Err := '';
  if FormatName = PATTERN_FORMAT then
  begin
    Pattern := TPattern.Create;
    try
      if LoadPatternFromText(Pattern, Text, Err) then
        Result := SavePatternToText(Pattern);
    finally
      FreeAndNil(Pattern);
    end;
  end
  else if FormatName = MEASUREMENT_FORMAT then
  begin
    MeasurementSet := TMeasurementSet.Create;
    try
      if MeasurementSet.LoadFromText(Text, Err) then
        Result := MeasurementSet.SaveToText;
    finally
      FreeAndNil(MeasurementSet);
    end;
  end
  else
  begin
    Layout := TLayout.Create;
    try
      if Layout.LoadFromText(Text, Err) then
        Result := Layout.SaveToText;
    finally
      FreeAndNil(Layout);
    end;
  end;
  if Result = '' then
    raise EAssertionFailedError.CreateFmt('%s does not load: %s', [FormatName, Err]);
end;

// The names of every member Item has, nested ones as list[].member and
// group.member; a pattern's objects are left to the operations table's test
procedure CollectMembers(Item: TJSONObject; const Prefix: string; Names: TStrings);
var
  Index, Element: integer;
  FullName: string;
  Value: TJSONData;
begin
  for Index := 0 to Item.Count - 1 do
  begin
    FullName := Prefix + Item.Names[Index];
    Value := Item.Items[Index];
    if (FullName = 'objects') and (Prefix = '') then
    begin
      Names.Add('objects');
      Continue;
    end;
    Names.Add(FullName);
    if Value.JSONType = jtObject then
      CollectMembers(TJSONObject(Value), FullName + '.', Names)
    else if Value.JSONType = jtArray then
      for Element := 0 to Value.Count - 1 do
        if Value.Items[Element].JSONType = jtObject then
          CollectMembers(TJSONObject(Value.Items[Element]), FullName + '[].', Names);
  end;
end;

// Every member written when the files with every member are read back
function WrittenMembers(const FormatName: string): TStringList;
var
  Texts: array of string;
  Text, Err: string;
  Root: TJSONObject;
begin
  if FormatName = PATTERN_FORMAT then
    Texts := [FULL_PATTERN]
  else if FormatName = MEASUREMENT_FORMAT then
    Texts := [FULL_MEASUREMENTS, FULL_SIZE_TABLE]
  else
    Texts := [FULL_LAYOUT];
  Result := TStringList.Create;
  Result.Sorted := True;
  Result.Duplicates := dupIgnore;
  for Text in Texts do
  begin
    if not ParseJSONObject(ReadBack(FormatName, Text), Root, Err) then
      raise EAssertionFailedError.Create(Err);
    try
      CollectMembers(Root, '', Result);
    finally
      FreeAndNil(Root);
    end;
  end;
end;

procedure TTestFileInfo.TestEverySavedMemberListed;
var
  Info: TFileFormatInfo;
  Written: TStringList;
  Name: string;
  Member: TOperationMember;
begin
  for Info in FileFormatInfos do
  begin
    Written := WrittenMembers(Info.FormatName);
    try
      for Name in Written do
        AssertTrue(Format('%s: "%s" is written but not in the file table', [Info.FormatName, Name]),
          FindFileMember(Info, Name, Member));
    finally
      FreeAndNil(Written);
    end;
  end;
end;

procedure TTestFileInfo.TestEveryListedMemberWritten;
var
  Info: TFileFormatInfo;
  Written: TStringList;
  Member: TOperationMember;
  Name: string;
begin
  for Info in FileFormatInfos do
  begin
    Written := WrittenMembers(Info.FormatName);
    try
      for Member in Info.Members do
      begin
        Name := Member.Name;
        if Name.EndsWith('[]') then
          SetLength(Name, Length(Name) - 2);
        AssertTrue(Format('%s: "%s" is listed but never written', [Info.FormatName, Member.Name]), Written.IndexOf(Name) >= 0);
      end;
    finally
      FreeAndNil(Written);
    end;
  end;
end;

procedure TTestFileInfo.TestExamplesReadBack;
var
  Info: TFileFormatInfo;
begin
  for Info in FileFormatInfos do
    AssertEquals(Info.FormatName + ' example', Info.Example + LineEnding, ReadBack(Info.FormatName, Info.Example));
end;

procedure TTestFileInfo.TestLayoutMatchesItsUnit;
var
  Info: TFileFormatInfo;
begin
  AssertTrue(FindFileFormatInfo(LAYOUT_FORMAT, Info));
  AssertEquals(LAYOUT_VERSION, Info.Version);
  AssertEquals(LAYOUT_EXTENSION, Info.Extension);
end;

procedure TTestFileInfo.TestSchemasForEveryFormat;
var
  Info: TFileFormatInfo;
  Text: string;
begin
  for Info in FileFormatInfos do
  begin
    AssertTrue(Info.FormatName, FileSchema(Info.FormatName, Text));
    AssertTrue(Info.FormatName, Pos('"const": "' + Info.FormatName + '"', Text) > 0);
  end;
  AssertFalse(FileSchema('nothing', Text));
end;

initialization
  RegisterTest(TTestFileInfo);
end.
