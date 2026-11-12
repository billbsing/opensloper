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

// Cuts a TrueType font down to the glyphs a PDF uses. Every glyph keeps its
// number, with the unused ones left empty, so the PDF can name glyphs by their
// numbers in the full font while it is being written and embed the subset at
// the end. Only the tables a PDF reader needs are kept. The same font and
// glyphs always give the same bytes.
unit Sloper.Output.FontSubset;

{$mode ObjFPC}{$H+}

interface

// The font in FontData with only Glyphs (and .notdef, and the parts of
// composite glyphs) drawn; False when it is not a TrueType font with glyf
// outlines this can read
function SubsetTrueType(const FontData: rawbytestring; const Glyphs: array of word; out Subset: rawbytestring): boolean;
// Whether the font has TrueType (glyf) outlines; False for an OpenType font
// with PostScript (CFF) outlines, or one that cannot be read
function HasTrueTypeOutlines(const FontData: rawbytestring): boolean;

implementation

uses
  SysUtils;

type
  TFontTable = record
    Tag: string;
    Data: rawbytestring;
  end;

  TFontTableArray = array of TFontTable;

const
  TAG_LENGTH = 4;
  OFFSET_TABLE_SIZE = 12;
  TABLE_RECORD_SIZE = 16;
  // Places within the tables, in bytes
  HEAD_CHECKSUM_ADJUSTMENT = 8;
  HEAD_INDEX_TO_LOC_FORMAT = 50;
  HEAD_MIN_SIZE = 54;
  MAXP_NUM_GLYPHS = 4;
  GLYPH_HEADER_SIZE = 10;
  // Composite glyph flags (the glyf table in the OpenType specification)
  ARG_1_AND_2_ARE_WORDS = $0001;
  WE_HAVE_A_SCALE = $0008;
  MORE_COMPONENTS = $0020;
  WE_HAVE_AN_X_AND_Y_SCALE = $0040;
  WE_HAVE_A_TWO_BY_TWO = $0080;
  CHECKSUM_MAGIC = $B1B0AFBA;
  TRUETYPE_VERSION = $00010000;
  // The tables a PDF reader uses from an embedded TrueType font
  KEPT_TABLES: array[0..8] of string = ('cvt ', 'fpgm', 'glyf', 'head', 'hhea', 'hmtx', 'loca', 'maxp', 'prep');
  REQUIRED_TABLES: array[0..5] of string = ('glyf', 'head', 'hhea', 'hmtx', 'loca', 'maxp');

// Big-endian reads and writes; Offset counts from 0
function ReadU16(const Data: rawbytestring; Offset: integer): word;
begin
  Result := (Ord(Data[Offset + 1]) shl 8) or Ord(Data[Offset + 2]);
end;

function ReadU32(const Data: rawbytestring; Offset: integer): cardinal;
begin
  Result := (cardinal(ReadU16(Data, Offset)) shl 16) or ReadU16(Data, Offset + 2);
end;

function U16Bytes(Value: word): rawbytestring;
begin
  Result := chr(Value shr 8) + chr(Value and $FF);
end;

function U32Bytes(Value: cardinal): rawbytestring;
begin
  Result := U16Bytes(Value shr 16) + U16Bytes(Value and $FFFF);
end;

procedure WriteU16(var Data: rawbytestring; Offset: integer; Value: word);
begin
  Data[Offset + 1] := chr(Value shr 8);
  Data[Offset + 2] := chr(Value and $FF);
end;

procedure WriteU32(var Data: rawbytestring; Offset: integer; Value: cardinal);
begin
  WriteU16(Data, Offset, Value shr 16);
  WriteU16(Data, Offset + 2, Value and $FFFF);
end;

function Padded(const Data: rawbytestring): rawbytestring;
begin
  Result := Data;
  while Length(Result) mod 4 <> 0 do
    Result := Result + #0;
end;

// The sum of the data as big-endian 32-bit words, padded with zeros
function TableChecksum(const Data: rawbytestring): cardinal;
var
  Whole: rawbytestring;
  Offset: integer;
begin
  Whole := Padded(Data);
  Result := 0;
  Offset := 0;
  while Offset < Length(Whole) do
  begin
    {$PUSH}{$Q-}{$R-}
    Result := Result + ReadU32(Whole, Offset);
    {$POP}
    Inc(Offset, 4);
  end;
end;

// The font's tables by tag; False when the directory runs past the data
function ReadTables(const FontData: rawbytestring; out Tables: TFontTableArray): boolean;
var
  Count, Index, Place: integer;
  Offset, Size: cardinal;
begin
  Tables := nil;
  if Length(FontData) < OFFSET_TABLE_SIZE then
    Exit(False);
  Count := ReadU16(FontData, 4);
  if Length(FontData) < OFFSET_TABLE_SIZE + Count * TABLE_RECORD_SIZE then
    Exit(False);
  SetLength(Tables, Count);
  for Index := 0 to Count - 1 do
  begin
    Place := OFFSET_TABLE_SIZE + Index * TABLE_RECORD_SIZE;
    Offset := ReadU32(FontData, Place + 8);
    Size := ReadU32(FontData, Place + 12);
    if int64(Offset) + Size > Length(FontData) then
      Exit(False);
    Tables[Index].Tag := Copy(FontData, Place + 1, TAG_LENGTH);
    Tables[Index].Data := Copy(FontData, Offset + 1, Size);
  end;
  Result := True;
end;

function FindTable(const Tables: TFontTableArray; const Tag: string; out Data: rawbytestring): boolean;
var
  Table: TFontTable;
begin
  Data := '';
  for Table in Tables do
    if Table.Tag = Tag then
    begin
      Data := Table.Data;
      Exit(True);
    end;
  Result := False;
end;

function HasTrueTypeOutlines(const FontData: rawbytestring): boolean;
var
  Tables: TFontTableArray;
  Data: rawbytestring;
  Tag: string;
begin
  if not ReadTables(FontData, Tables) then
    Exit(False);
  for Tag in REQUIRED_TABLES do
    if not FindTable(Tables, Tag, Data) then
      Exit(False);
  Result := True;
end;

// Where each glyph's data starts in glyf, and where the last ends
function GlyphOffsets(const Loca: rawbytestring; GlyphCount: integer; LongOffsets: boolean; out Offsets: array of cardinal): boolean;
var
  Index: integer;
begin
  if LongOffsets then
    Result := Length(Loca) >= (GlyphCount + 1) * 4
  else
    Result := Length(Loca) >= (GlyphCount + 1) * 2;
  if not Result then
    Exit;
  for Index := 0 to GlyphCount do
    if LongOffsets then
      Offsets[Index] := ReadU32(Loca, Index * 4)
    else
      Offsets[Index] := cardinal(ReadU16(Loca, Index * 2)) * 2;
end;

// Marks the glyphs a composite glyph is made of, and theirs in turn
procedure MarkComponents(const Glyf: rawbytestring; const Offsets: array of cardinal; Glyph: integer; var Kept: array of boolean);
var
  Place, Stop, Flags, Part: integer;
begin
  Place := Offsets[Glyph];
  Stop := Offsets[Glyph + 1];
  if (Stop - Place < GLYPH_HEADER_SIZE) or (Stop > Length(Glyf)) or (smallint(ReadU16(Glyf, Place)) >= 0) then
    Exit;
  Inc(Place, GLYPH_HEADER_SIZE);
  repeat
    if Place + 4 > Stop then
      Exit;
    Flags := ReadU16(Glyf, Place);
    Part := ReadU16(Glyf, Place + 2);
    Inc(Place, 4);
    if (Part <= High(Kept)) and not Kept[Part] then
    begin
      Kept[Part] := True;
      MarkComponents(Glyf, Offsets, Part, Kept);
    end;
    if Flags and ARG_1_AND_2_ARE_WORDS <> 0 then
      Inc(Place, 4)
    else
      Inc(Place, 2);
    if Flags and WE_HAVE_A_SCALE <> 0 then
      Inc(Place, 2)
    else if Flags and WE_HAVE_AN_X_AND_Y_SCALE <> 0 then
      Inc(Place, 4)
    else if Flags and WE_HAVE_A_TWO_BY_TWO <> 0 then
      Inc(Place, 8);
  until Flags and MORE_COMPONENTS = 0;
end;

// The tables in tag order, each padded to four bytes, with head's checksum
// adjustment set over the whole file
function Assembled(var Tables: TFontTableArray): rawbytestring;
var
  Index, Count, Power, Selector, HeadIndex: integer;
  Offset: cardinal;
  Swap: TFontTable;
  Sorted: boolean;
begin
  repeat
    Sorted := True;
    for Index := 0 to High(Tables) - 1 do
      if Tables[Index].Tag > Tables[Index + 1].Tag then
      begin
        Swap := Tables[Index];
        Tables[Index] := Tables[Index + 1];
        Tables[Index + 1] := Swap;
        Sorted := False;
      end;
  until Sorted;
  Count := Length(Tables);
  Power := 1;
  Selector := 0;
  while Power * 2 <= Count do
  begin
    Power := Power * 2;
    Inc(Selector);
  end;
  Result := U32Bytes(TRUETYPE_VERSION) + U16Bytes(Count) + U16Bytes(Power * TABLE_RECORD_SIZE) + U16Bytes(Selector) +
    U16Bytes(Count * TABLE_RECORD_SIZE - Power * TABLE_RECORD_SIZE);
  Offset := OFFSET_TABLE_SIZE + Count * TABLE_RECORD_SIZE;
  HeadIndex := -1;
  for Index := 0 to High(Tables) do
  begin
    if Tables[Index].Tag = 'head' then
    begin
      HeadIndex := Index;
      WriteU32(Tables[Index].Data, HEAD_CHECKSUM_ADJUSTMENT, 0);
    end;
    Result := Result + Tables[Index].Tag + U32Bytes(TableChecksum(Tables[Index].Data)) + U32Bytes(Offset) +
      U32Bytes(Length(Tables[Index].Data));
    Inc(Offset, Length(Padded(Tables[Index].Data)));
  end;
  for Index := 0 to High(Tables) do
    Result := Result + Padded(Tables[Index].Data);
  if HeadIndex >= 0 then
  begin
    {$PUSH}{$Q-}{$R-}
    Offset := CHECKSUM_MAGIC - TableChecksum(Result);
    {$POP}
    // head's data begins where its record says
    WriteU32(Result, ReadU32(Result, OFFSET_TABLE_SIZE + HeadIndex * TABLE_RECORD_SIZE + 8) + HEAD_CHECKSUM_ADJUSTMENT, Offset);
  end;
end;

function SubsetTrueType(const FontData: rawbytestring; const Glyphs: array of word; out Subset: rawbytestring): boolean;
var
  Tables, Output: TFontTableArray;
  Head, Maxp, Loca, Glyf, Data, NewGlyf, NewLoca: rawbytestring;
  GlyphCount, Index: integer;
  Offsets: array of cardinal;
  Kept: array of boolean;
  Tag: string;
  Glyph: word;
begin
  Subset := '';
  if not HasTrueTypeOutlines(FontData) or not ReadTables(FontData, Tables) then
    Exit(False);
  FindTable(Tables, 'head', Head);
  FindTable(Tables, 'maxp', Maxp);
  FindTable(Tables, 'loca', Loca);
  FindTable(Tables, 'glyf', Glyf);
  if (Length(Head) < HEAD_MIN_SIZE) or (Length(Maxp) < MAXP_NUM_GLYPHS + 2) then
    Exit(False);
  GlyphCount := ReadU16(Maxp, MAXP_NUM_GLYPHS);
  Offsets := nil;
  SetLength(Offsets, GlyphCount + 1);
  if (GlyphCount = 0) or not GlyphOffsets(Loca, GlyphCount, ReadU16(Head, HEAD_INDEX_TO_LOC_FORMAT) <> 0, Offsets) then
    Exit(False);
  for Index := 0 to GlyphCount - 1 do
    if (Offsets[Index] > Offsets[Index + 1]) or (Offsets[Index + 1] > cardinal(Length(Glyf))) then
      Exit(False);
  Kept := nil;
  SetLength(Kept, GlyphCount);
  Kept[0] := True;
  for Glyph in Glyphs do
    if Glyph < GlyphCount then
      Kept[Glyph] := True;
  for Index := 0 to GlyphCount - 1 do
    if Kept[Index] then
      MarkComponents(Glyf, Offsets, Index, Kept);
  // A font can have tens of thousands of glyphs, so loca is filled in place
  NewGlyf := '';
  NewLoca := '';
  SetLength(NewLoca, (GlyphCount + 1) * 4);
  for Index := 0 to GlyphCount - 1 do
  begin
    WriteU32(NewLoca, Index * 4, Length(NewGlyf));
    if Kept[Index] then
      NewGlyf := NewGlyf + Padded(Copy(Glyf, Offsets[Index] + 1, Offsets[Index + 1] - Offsets[Index]));
  end;
  WriteU32(NewLoca, GlyphCount * 4, Length(NewGlyf));
  // Long offsets, whatever the font had
  WriteU16(Head, HEAD_INDEX_TO_LOC_FORMAT, 1);
  Output := nil;
  for Tag in KEPT_TABLES do
  begin
    if Tag = 'glyf' then
      Data := NewGlyf
    else if Tag = 'loca' then
      Data := NewLoca
    else if Tag = 'head' then
      Data := Head
    else if not FindTable(Tables, Tag, Data) then
      Continue;
    SetLength(Output, Length(Output) + 1);
    Output[High(Output)].Tag := Tag;
    Output[High(Output)].Data := Data;
  end;
  Subset := Assembled(Output);
  Result := True;
end;

end.
