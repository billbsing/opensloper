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

// The catalogue of standard body measurements (data/measurement-catalogue.json):
// what each is, how to take it, where it goes on the body figure, and its names
// in other programs' files. No LCL dependency.
unit Sloper.Core.Catalogue;

{$mode ObjFPC}{$H+}

interface

uses
  SysUtils, Generics.Collections, fpjson, Sloper.Core.Geometry;

const
  CatalogueFormat = 'measurement-catalogue';
  CatalogueVersion = 1;
  // Name of the Seamly2D and Valentina format in "translations"
  FormatSeamly2D = 'seamly2d';
  CatalogueGroups: array[0..8] of string = ('heights', 'circumferences', 'widths', 'arm', 'leg', 'crotch', 'head', 'hand', 'foot');

type
  TCatalogueView = (cvFront, cvBack, cvSide);
  TFigurePath = TVec2Array;
  TFigurePaths = array of TFigurePath;

  TCatalogueTranslation = record
    FormatName: string;
    // The first is the one exported
    Names: TStringArray;
  end;

  TCatalogueEntry = class
  public
    Key, Name, Group, Description, HowTo: string;
    View: TCatalogueView;
    Overlay: TFigurePath;
    // Typical minimum and maximum in mm
    RangeMin, RangeMax: double;
    Translations: array of TCatalogueTranslation;
    // Outside it is only a warning, so that unusual bodies are not blocked
    function InRange(Value: double): boolean;
    // The name to export under, '' when the format has none
    function NameIn(const FormatName: string): string;
  end;

  TCatalogueEntryList = specialize TObjectList<TCatalogueEntry>;
  TCatalogueEntryArray = array of TCatalogueEntry;

  TCatalogue = class
  private
    FEntries: TCatalogueEntryList;
    FFigures: array[TCatalogueView] of TFigurePaths;
    // Every name of each format, whether it has an entry or not
    FKnownNames: array of TCatalogueTranslation;
    procedure LoadKnownNames(Obj: TJSONObject);
    function GetCount: integer;
    function GetEntry(Index: integer): TCatalogueEntry;
    function GetFigure(View: TCatalogueView): TFigurePaths;
    function LoadFigures(Obj: TJSONObject; out ErrorMessage: string): boolean;
    function LoadEntry(Item: TJSONObject; out ErrorMessage: string): boolean;
  public
    constructor Create;
    destructor Destroy; override;
    procedure Clear;
    function Find(const Key: string): TCatalogueEntry;
    // The entry a name in another format stands for, nil when there is none
    function FindTranslated(const FormatName, Name: string): TCatalogueEntry;
    // Whether the format has this name of its own, so that a key imported
    // under it can go back unchanged
    function IsKnownName(const FormatName, Name: string): boolean;
    // Entries in Group, or every group when it is empty, whose key, name or
    // description holds Search, without regard to case
    function Search(const Group, SearchText: string): TCatalogueEntryArray;
    // The entry among Keys with an overlay on View nearest Point, within
    // Tolerance in figure units; nil when there is none
    function OverlayAt(View: TCatalogueView; const Point: TVec2; Tolerance: double; const Keys: TStringArray): TCatalogueEntry;
    // On failure the catalogue is left empty and ErrorMessage says why
    function LoadFromText(const Text: string; out ErrorMessage: string): boolean;
    function LoadFromFile(const FileName: string; out ErrorMessage: string): boolean;
    property Count: integer read GetCount;
    property Entries[Index: integer]: TCatalogueEntry read GetEntry; default;
    property Figures[View: TCatalogueView]: TFigurePaths read GetFigure;
  end;

  // Where the three views go in a control, each scaled alike
  TFigureLayout = record
    Scale: double;
    Origins: array[TCatalogueView] of TVec2;
  end;

const
  // Figure coordinates run down from the top of the head; each view is this big
  FigureWidth = 500;
  FigureHeight = 1000;

function LayoutFigures(AWidth, AHeight: double): TFigureLayout;
function FigureToScreen(const Layout: TFigureLayout; View: TCatalogueView; const Point: TVec2): TVec2;
// The view a point on the screen falls in, with its place in figure coordinates
function ScreenToFigure(const Layout: TFigureLayout; const Point: TVec2; out View: TCatalogueView; out OnFigure: TVec2): boolean;
function DistanceToPath(const Point: TVec2; const Path: TFigurePath): double;

resourcestring
  rsCatalogueWrongFormat = 'This is not a measurement catalogue';
  rsCatalogueNewerVersion = 'This catalogue was made by a newer version of OpenSloper (file version %d)';
  rsCatalogueNoFigures = 'The catalogue has no figures';
  rsCatalogueBadFigure = 'The catalogue''s %s figure is not valid';
  rsCatalogueNoList = 'The catalogue has no list of measurements';
  rsCatalogueBadEntry = 'A catalogue entry is not valid';
  rsCatalogueBadKey = 'Catalogue key "%s": %s';
  rsCatalogueDuplicate = 'Catalogue key "%s" is listed twice';
  rsCatalogueBadGroup = 'Catalogue key "%s" has an unknown group "%s"';
  rsCatalogueBadView = 'Catalogue key "%s" has an unknown view "%s"';
  rsCatalogueBadOverlay = 'Catalogue key "%s" has no valid overlay';
  rsCatalogueBadRange = 'Catalogue key "%s" has no valid range';

implementation

uses
  Math, Sloper.Core.JSON, Sloper.Core.Names;

const
  ViewNames: array[TCatalogueView] of string = ('front', 'back', 'side');

function TCatalogueEntry.InRange(Value: double): boolean;
begin
  Result := (Value >= RangeMin) and (Value <= RangeMax);
end;

function TCatalogueEntry.NameIn(const FormatName: string): string;
var
  Translation: TCatalogueTranslation;
begin
  Result := '';
  for Translation in Translations do
    if Translation.FormatName = FormatName then
      Exit(Translation.Names[0]);
end;

constructor TCatalogue.Create;
begin
  FEntries := TCatalogueEntryList.Create;
end;

destructor TCatalogue.Destroy;
begin
  FreeAndNil(FEntries);
  inherited Destroy;
end;

procedure TCatalogue.Clear;
var
  View: TCatalogueView;
begin
  FEntries.Clear;
  FKnownNames := nil;
  for View := Low(TCatalogueView) to High(TCatalogueView) do
    FFigures[View] := nil;
end;

function TCatalogue.GetCount: integer;
begin
  Result := FEntries.Count;
end;

function TCatalogue.GetEntry(Index: integer): TCatalogueEntry;
begin
  Result := FEntries[Index];
end;

function TCatalogue.GetFigure(View: TCatalogueView): TFigurePaths;
begin
  Result := FFigures[View];
end;

function TCatalogue.Find(const Key: string): TCatalogueEntry;
begin
  for Result in FEntries do
    if SameName(Result.Key, Key) then
      Exit;
  Result := nil;
end;

function TCatalogue.FindTranslated(const FormatName, Name: string): TCatalogueEntry;
var
  Translation: TCatalogueTranslation;
  Known: string;
begin
  for Result in FEntries do
    for Translation in Result.Translations do
      if Translation.FormatName = FormatName then
        for Known in Translation.Names do
          if Known = Name then
            Exit;
  Result := nil;
end;

function TCatalogue.IsKnownName(const FormatName, Name: string): boolean;
var
  Known: TCatalogueTranslation;
  Candidate: string;
begin
  for Known in FKnownNames do
    if Known.FormatName = FormatName then
      for Candidate in Known.Names do
        if Candidate = Name then
          Exit(True);
  Result := False;
end;

function TCatalogue.Search(const Group, SearchText: string): TCatalogueEntryArray;
var
  Entry: TCatalogueEntry;
  Wanted: string;
begin
  Result := nil;
  Wanted := LowerCase(Trim(SearchText));
  for Entry in FEntries do
    if ((Group = '') or (Entry.Group = Group)) and ((Wanted = '') or (Pos(Wanted, LowerCase(Entry.Key + ' ' + Entry.Name + ' ' + Entry.Description)) > 0)) then
      Insert(Entry, Result, Length(Result));
end;

function DistanceToPath(const Point: TVec2; const Path: TFigurePath): double;
var
  Index: integer;
  Along, LengthSquared: double;
  Part: TVec2;
begin
  Result := Infinity;
  for Index := 0 to High(Path) - 1 do
  begin
    Part := Path[Index + 1] - Path[Index];
    LengthSquared := Dot(Part, Part);
    Along := 0;
    if LengthSquared > 0 then
      Along := EnsureRange(Dot(Point - Path[Index], Part) / LengthSquared, 0, 1);
    Result := Min(Result, Distance(Point, Path[Index] + Part * Along));
  end;
end;

function TCatalogue.OverlayAt(View: TCatalogueView; const Point: TVec2; Tolerance: double; const Keys: TStringArray): TCatalogueEntry;
var
  Key: string;
  Entry: TCatalogueEntry;
  Nearest, Gap: double;
begin
  Result := nil;
  Nearest := Tolerance;
  for Key in Keys do
  begin
    Entry := Find(Key);
    if (Entry = nil) or (Entry.View <> View) then
      Continue;
    Gap := DistanceToPath(Point, Entry.Overlay);
    if Gap <= Nearest then
    begin
      Nearest := Gap;
      Result := Entry;
    end;
  end;
end;

// [[x, y], ...], with at least MinPoints points
function ReadPath(Data: TJSONData; MinPoints: integer; out Path: TFigurePath): boolean;
var
  Index: integer;
  Pair: TJSONData;
begin
  Path := nil;
  Result := (Data <> nil) and (Data.JSONType = jtArray) and (Data.Count >= MinPoints);
  if not Result then
    Exit;
  SetLength(Path, Data.Count);
  for Index := 0 to Data.Count - 1 do
  begin
    Pair := Data.Items[Index];
    if (Pair.JSONType <> jtArray) or (Pair.Count <> 2) or (Pair.Items[0].JSONType <> jtNumber) or (Pair.Items[1].JSONType <> jtNumber) then
      Exit(False);
    Path[Index] := Vec2(Pair.Items[0].AsFloat, Pair.Items[1].AsFloat);
  end;
end;

function TCatalogue.LoadFigures(Obj: TJSONObject; out ErrorMessage: string): boolean;
var
  Views, Paths: TJSONData;
  View: TCatalogueView;
  Index: integer;
begin
  ErrorMessage := '';
  Views := Obj.Find('figures');
  if (Views = nil) or (Views.JSONType <> jtObject) then
  begin
    ErrorMessage := rsCatalogueNoFigures;
    Exit(False);
  end;
  for View := Low(TCatalogueView) to High(TCatalogueView) do
  begin
    Paths := TJSONObject(Views).Find(ViewNames[View]);
    if (Paths = nil) or (Paths.JSONType <> jtArray) or (Paths.Count = 0) then
    begin
      ErrorMessage := Format(rsCatalogueBadFigure, [ViewNames[View]]);
      Exit(False);
    end;
    SetLength(FFigures[View], Paths.Count);
    for Index := 0 to Paths.Count - 1 do
      if not ReadPath(Paths.Items[Index], 3, FFigures[View][Index]) then
      begin
        ErrorMessage := Format(rsCatalogueBadFigure, [ViewNames[View]]);
        Exit(False);
      end;
  end;
  Result := True;
end;

function TCatalogue.LoadEntry(Item: TJSONObject; out ErrorMessage: string): boolean;

  function Fail(const Msg: string): boolean;
  begin
    ErrorMessage := Msg;
    Result := False;
  end;

  function ReadView(const ViewName: string; out View: TCatalogueView): boolean;
  var
    Candidate: TCatalogueView;
  begin
    View := cvFront;
    for Candidate := Low(TCatalogueView) to High(TCatalogueView) do
      if ViewNames[Candidate] = ViewName then
      begin
        View := Candidate;
        Exit(True);
      end;
    Result := False;
  end;

  procedure ReadTranslations(Entry: TCatalogueEntry);
  var
    List: TJSONData;
    Index, NameIndex: integer;
  begin
    List := Item.Find('translations');
    if (List = nil) or (List.JSONType <> jtObject) then
      Exit;
    SetLength(Entry.Translations, List.Count);
    for Index := 0 to List.Count - 1 do
    begin
      Entry.Translations[Index].FormatName := TJSONObject(List).Names[Index];
      SetLength(Entry.Translations[Index].Names, List.Items[Index].Count);
      for NameIndex := 0 to List.Items[Index].Count - 1 do
        Entry.Translations[Index].Names[NameIndex] := List.Items[Index].Items[NameIndex].AsString;
    end;
  end;

var
  Entry: TCatalogueEntry;
  Key, GroupName, ViewName, KeyError: string;
  Range: TJSONData;
  Known: boolean;
  Candidate: string;
begin
  ErrorMessage := '';
  if not GetJSONString(Item, 'key', Key) or not GetJSONString(Item, 'group', GroupName) or not GetJSONString(Item, 'view', ViewName) then
    Exit(Fail(rsCatalogueBadEntry));
  if not CheckName(Key, KeyError) then
    Exit(Fail(Format(rsCatalogueBadKey, [Key, KeyError])));
  if Find(Key) <> nil then
    Exit(Fail(Format(rsCatalogueDuplicate, [Key])));
  Known := False;
  for Candidate in CatalogueGroups do
    Known := Known or (Candidate = GroupName);
  if not Known then
    Exit(Fail(Format(rsCatalogueBadGroup, [Key, GroupName])));
  // Added first, so that the list owns it however this ends
  Entry := TCatalogueEntry.Create;
  FEntries.Add(Entry);
  Entry.Key := Key;
  Entry.Group := GroupName;
  GetJSONString(Item, 'name', Entry.Name);
  GetJSONString(Item, 'description', Entry.Description);
  GetJSONString(Item, 'howTo', Entry.HowTo);
  if not ReadView(ViewName, Entry.View) then
    Exit(Fail(Format(rsCatalogueBadView, [Key, ViewName])));
  if not ReadPath(Item.Find('overlay'), 2, Entry.Overlay) then
    Exit(Fail(Format(rsCatalogueBadOverlay, [Key])));
  Range := Item.Find('range');
  if (Range = nil) or (Range.JSONType <> jtArray) or (Range.Count <> 2) or (Range.Items[0].JSONType <> jtNumber) or
    (Range.Items[1].JSONType <> jtNumber) or (Range.Items[0].AsFloat >= Range.Items[1].AsFloat) then
    Exit(Fail(Format(rsCatalogueBadRange, [Key])));
  Entry.RangeMin := Range.Items[0].AsFloat;
  Entry.RangeMax := Range.Items[1].AsFloat;
  ReadTranslations(Entry);
  Result := True;
end;

procedure TCatalogue.LoadKnownNames(Obj: TJSONObject);
var
  List: TJSONData;
  Index, NameIndex: integer;
begin
  List := Obj.Find('knownNames');
  if (List = nil) or (List.JSONType <> jtObject) then
    Exit;
  SetLength(FKnownNames, List.Count);
  for Index := 0 to List.Count - 1 do
  begin
    FKnownNames[Index].FormatName := TJSONObject(List).Names[Index];
    SetLength(FKnownNames[Index].Names, List.Items[Index].Count);
    for NameIndex := 0 to List.Items[Index].Count - 1 do
      FKnownNames[Index].Names[NameIndex] := List.Items[Index].Items[NameIndex].AsString;
  end;
end;

function TCatalogue.LoadFromText(const Text: string; out ErrorMessage: string): boolean;
var
  Obj: TJSONObject;
  List: TJSONData;
  TextValue: string;
  Version, Index: integer;

  function Fail(const Msg: string): boolean;
  begin
    ErrorMessage := Msg;
    Clear;
    Result := False;
  end;

begin
  Clear;
  if not ParseJSONObject(Text, Obj, ErrorMessage) then
    Exit(False);
  try
    if not GetJSONString(Obj, 'format', TextValue) or (TextValue <> CatalogueFormat) or not GetJSONInteger(Obj, 'version', Version) then
      Exit(Fail(rsCatalogueWrongFormat));
    if Version > CatalogueVersion then
      Exit(Fail(Format(rsCatalogueNewerVersion, [Version])));
    if not LoadFigures(Obj, TextValue) then
      Exit(Fail(TextValue));
    LoadKnownNames(Obj);
    List := Obj.Find('measurements');
    if (List = nil) or (List.JSONType <> jtArray) then
      Exit(Fail(rsCatalogueNoList));
    for Index := 0 to List.Count - 1 do
    begin
      if List.Items[Index].JSONType <> jtObject then
        Exit(Fail(rsCatalogueBadEntry));
      if not LoadEntry(TJSONObject(List.Items[Index]), TextValue) then
        Exit(Fail(TextValue));
    end;
    Result := True;
  finally
    FreeAndNil(Obj);
  end;
end;

function TCatalogue.LoadFromFile(const FileName: string; out ErrorMessage: string): boolean;
var
  Text: string;
begin
  Clear;
  if not ReadTextFile(FileName, Text, ErrorMessage) then
    Exit(False);
  Result := LoadFromText(Text, ErrorMessage);
end;

function LayoutFigures(AWidth, AHeight: double): TFigureLayout;
var
  View: TCatalogueView;
  Across, Margin: double;
begin
  Across := FigureWidth * (Ord(High(TCatalogueView)) + 1);
  Result.Scale := Max(Min(AWidth / Across, AHeight / FigureHeight), 1e-6);
  Margin := (AWidth - Across * Result.Scale) / 2;
  for View := Low(TCatalogueView) to High(TCatalogueView) do
    Result.Origins[View] := Vec2(Margin + Ord(View) * FigureWidth * Result.Scale, (AHeight - FigureHeight * Result.Scale) / 2);
end;

function FigureToScreen(const Layout: TFigureLayout; View: TCatalogueView; const Point: TVec2): TVec2;
begin
  Result := Vec2(Layout.Origins[View].X + Point.X * Layout.Scale, Layout.Origins[View].Y + Point.Y * Layout.Scale);
end;

function ScreenToFigure(const Layout: TFigureLayout; const Point: TVec2; out View: TCatalogueView; out OnFigure: TVec2): boolean;
var
  Candidate: TCatalogueView;
begin
  OnFigure := Vec2(0, 0);
  View := cvFront;
  for Candidate := Low(TCatalogueView) to High(TCatalogueView) do
  begin
    OnFigure := Vec2((Point.X - Layout.Origins[Candidate].X) / Layout.Scale, (Point.Y - Layout.Origins[Candidate].Y) / Layout.Scale);
    if (OnFigure.X >= 0) and (OnFigure.X < FigureWidth) and (OnFigure.Y >= 0) and (OnFigure.Y < FigureHeight) then
    begin
      View := Candidate;
      Exit(True);
    end;
  end;
  Result := False;
end;

end.
