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

// Text placed on a pattern or layout: the {fields} it may hold, its lines, and
// roughly how much room it takes in Helvetica, the one font printed so far.
// No LCL dependency.
unit Sloper.Core.TextFields;

{$mode ObjFPC}{$H+}

interface

uses
  SysUtils, Sloper.Core.Geometry, Sloper.Core.Pattern, Sloper.Core.Note;

const
  // The fields a title block can show; also usable as {pattern.name} in text
  FIELD_PATTERN_NAME = 'pattern.name';
  FIELD_MEASUREMENTS_NAME = 'measurements.name';
  FIELD_LAYOUT_NAME = 'layout.name';
  FIELD_DATE = 'date';
  FIELD_CUT_LIST = 'cutlist';
  FIELD_MATERIALS = 'materials';
  POINTS_TO_MM = 25.4 / 72;

type
  // What fields stand for in text; an empty value leaves the field as typed
  TFieldValues = record
    PatternName, MeasurementsName, LayoutName, Date, Page, Pages, CutList, Materials: string;
  end;

// Text with its known {fields} filled in
function ExpandFields(const Text: string; const Values: TFieldValues): string;
// Text as lines, however it was broken
function TextLines(const Text: string): TStringArray;
// About how far a line of text runs, in mm, at Size points in Helvetica
function TextWidth(const Text: string; Size: double): double;
// The height of one line of text, in mm
function LineHeight(Size: double): double;
// Today's date as fields show it
function FieldDateText: string;
// The fields a pattern's notes can show: the pattern's name from its file
// (empty when it has none), its measurement set and size, today's date, its
// cut list and materials. Page and pages are left as typed.
function PatternFieldValues(Pattern: TPattern; const PatternFileName: string): TFieldValues;
// The rough area a note's text covers, in mm, from its top left down
function NoteBox(Note: TNoteObject; const Values: TFieldValues): TRect2;
// What a note draws round its text: the white box when it has one, or just
// the text; a callout's leader leaves from its edge
function NoteFrame(Note: TNoteObject; const Values: TFieldValues): TRect2;

implementation

const
  // Line spacing, and the average width of a Helvetica letter, as shares of its size
  LINE_SPACING = 1.25;
  LETTER_WIDTH = 0.52;
  // The title block fields only this unit fills in: the sheet's number and count
  FIELD_PAGE = 'page';
  FIELD_PAGES = 'pages';

function ExpandFields(const Text: string; const Values: TFieldValues): string;

  procedure Fill(const Field, Value: string);
  begin
    if Value <> '' then
      Result := StringReplace(Result, '{' + Field + '}', Value, [rfReplaceAll]);
  end;

begin
  Result := Text;
  Fill(FIELD_PATTERN_NAME, Values.PatternName);
  Fill(FIELD_MEASUREMENTS_NAME, Values.MeasurementsName);
  Fill(FIELD_LAYOUT_NAME, Values.LayoutName);
  Fill(FIELD_DATE, Values.Date);
  Fill(FIELD_PAGE, Values.Page);
  Fill(FIELD_PAGES, Values.Pages);
  Fill(FIELD_CUT_LIST, Values.CutList);
  Fill(FIELD_MATERIALS, Values.Materials);
end;

function TextLines(const Text: string): TStringArray;
var
  Unified: string;
  Start, Position: integer;
begin
  Result := nil;
  Unified := StringReplace(Text, #13#10, #10, [rfReplaceAll]);
  Unified := StringReplace(Unified, #13, #10, [rfReplaceAll]);
  Start := 1;
  for Position := 1 to Length(Unified) + 1 do
    if (Position > Length(Unified)) or (Unified[Position] = #10) then
    begin
      Insert(Copy(Unified, Start, Position - Start), Result, Length(Result));
      Start := Position + 1;
    end;
end;

function TextWidth(const Text: string; Size: double): double;
begin
  Result := Length(UTF8Decode(Text)) * Size * LETTER_WIDTH * POINTS_TO_MM;
end;

function LineHeight(Size: double): double;
begin
  Result := Size * LINE_SPACING * POINTS_TO_MM;
end;

function FieldDateText: string;
begin
  Result := FormatDateTime('yyyy-mm-dd', Date);
end;

function PatternFieldValues(Pattern: TPattern; const PatternFileName: string): TFieldValues;
begin
  Result := Default(TFieldValues);
  Result.PatternName := ChangeFileExt(ExtractFileName(PatternFileName), '');
  if Assigned(Pattern.Measurements) then
  begin
    Result.MeasurementsName := Pattern.Measurements.Name;
    if Pattern.Measurements.SizeName <> '' then
      Result.MeasurementsName := Trim(Result.MeasurementsName + ' ' + Pattern.Measurements.SizeName);
  end;
  Result.Date := FieldDateText;
  Result.CutList := Pattern.CutList;
  Result.Materials := Pattern.MaterialNames;
end;

function NoteBox(Note: TNoteObject; const Values: TFieldValues): TRect2;
var
  Lines: TStringArray;
  Line: string;
  Widest: double;
begin
  Lines := TextLines(ExpandFields(Note.ShownText, Values));
  Widest := 0;
  for Line in Lines do
    if TextWidth(Line, Note.Size) > Widest then
      Widest := TextWidth(Line, Note.Size);
  Result.MinX := Note.Position.X;
  Result.MinY := Note.Position.Y;
  Result.MaxX := Note.Position.X + Widest;
  Result.MaxY := Note.Position.Y + Length(Lines) * LineHeight(Note.Size);
end;

function NoteFrame(Note: TNoteObject; const Values: TFieldValues): TRect2;
begin
  Result := NoteBox(Note, Values);
  if Note.Boxed then
    Result := PaddedBox(Result);
end;

end.
