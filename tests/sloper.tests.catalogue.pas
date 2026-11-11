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

// The measurement catalogue, and the file that ships with the app.
unit Sloper.Tests.Catalogue;

{$mode ObjFPC}{$H+}

interface

uses
  fpcunit, testregistry, Sloper.Tests.TestCase, Sloper.Core.Catalogue;

type
  TTestCatalogue = class(TOSTestCase)
  private
    FCatalogue: TCatalogue;
    procedure AssertLoadFails(const Entry, Msg: string);
    procedure LoadSample;
    procedure LoadShipped;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestLoads;
    procedure TestFind;
    procedure TestRange;
    procedure TestTranslations;
    procedure TestSearch;
    procedure TestOverlayAt;
    procedure TestOverlayAtOnlyListedKeys;
    procedure TestBadCatalogues;
    procedure TestBadEntries;
    procedure TestFailedLoadLeavesItEmpty;
    procedure TestMissingFile;
    procedure TestLayoutRoundTrip;
    procedure TestOutsideTheViews;
    procedure TestDistanceToPath;
    procedure TestFindsFile;
    procedure TestShippedLoads;
    procedure TestShippedKeysAreWholeWords;
    procedure TestShippedCoversEveryGroup;
    procedure TestShippedOnTheFigure;
    procedure TestShippedTranslatesOneToOne;
    procedure TestShippedReadsWell;
    procedure TestShippedKnowsSeamlyNames;
  end;

implementation

uses
  SysUtils, Math, Sloper.Core.AppPaths, Sloper.Core.Geometry;

const
  FIGURE = '[[0, 0], [100, 0], [100, 100]]';
  HEAD = '{"format": "measurement-catalogue", "version": 1, "figures": {"front": [' + FIGURE + '], "back": [' + FIGURE +
    '], "side": [' + FIGURE + ']}, "measurements": [';
  WAIST_ENTRY = '{"key": "waist_circumference", "translations": {"seamly2d": ["waist_circ", "waist"]}, "name": "Waist circumference", ' +
    '"group": "circumferences", "description": "Round the natural waist.", "howTo": "Measure it.", "view": "front", ' +
    '"overlay": [[100, 300], [300, 300]], "range": [550, 1500]}';
  ARM_ENTRY = '{"key": "arm_length", "name": "Arm length", "group": "arm", "description": "Shoulder tip to wrist.", "howTo": "", ' +
    '"view": "side", "overlay": [[100, 300], [100, 500]], "range": [480, 740]}';
  ENTRY_REST = '"name": "A", "description": "", "howTo": ""';
  ABBREVIATIONS: array[0..5] of string = ('circ', 'f', 'b', 'mid', 'bustpoint', 'arc_f');

procedure TTestCatalogue.SetUp;
begin
  FCatalogue := TCatalogue.Create;
end;

procedure TTestCatalogue.TearDown;
begin
  FreeAndNil(FCatalogue);
end;

procedure TTestCatalogue.LoadSample;
var
  Err: string;
begin
  AssertTrue(Err, FCatalogue.LoadFromText(HEAD + WAIST_ENTRY + ', ' + ARM_ENTRY + ']}', Err));
end;

procedure TTestCatalogue.LoadShipped;
var
  Err: string;
begin
  AssertTrue(Err, FCatalogue.LoadFromFile(TAppPaths.CatalogueFile, Err));
end;

procedure TTestCatalogue.AssertLoadFails(const Entry, Msg: string);
var
  Err: string;
begin
  AssertFalse(Msg + ' loads', FCatalogue.LoadFromText(HEAD + Entry + ']}', Err));
  AssertEquals(Msg, Err);
end;

procedure TTestCatalogue.TestLoads;
begin
  LoadSample;
  AssertEquals(2, FCatalogue.Count);
  AssertEquals('Waist circumference', FCatalogue[0].Name);
  AssertEquals('circumferences', FCatalogue[0].Group);
  AssertEquals('Measure it.', FCatalogue[0].HowTo);
  AssertTrue(FCatalogue[1].View = cvSide);
  AssertEquals(2, Length(FCatalogue[0].Overlay));
  AssertNear('overlay', 300, FCatalogue[0].Overlay[1].X);
  AssertEquals(3, Length(FCatalogue.Figures[cvBack][0]));
end;

procedure TTestCatalogue.TestFind;
begin
  LoadSample;
  AssertEquals('without regard to case', 'arm_length', FCatalogue.Find('ARM_length').Key);
  AssertNull(FCatalogue.Find('hip'));
end;

procedure TTestCatalogue.TestRange;
begin
  LoadSample;
  AssertTrue(FCatalogue[0].InRange(700));
  AssertTrue('the ends count', FCatalogue[0].InRange(550));
  AssertTrue('the ends count', FCatalogue[0].InRange(1500));
  AssertFalse(FCatalogue[0].InRange(549));
  AssertFalse(FCatalogue[0].InRange(1501));
end;

procedure TTestCatalogue.TestTranslations;
begin
  LoadSample;
  AssertEquals('the first is exported', 'waist_circ', FCatalogue[0].NameIn(FORMAT_SEAMLY2D));
  AssertEquals('no such format', '', FCatalogue[0].NameIn('other'));
  AssertEquals('no translation', '', FCatalogue[1].NameIn(FORMAT_SEAMLY2D));
  AssertEquals('waist_circumference', FCatalogue.FindTranslated(FORMAT_SEAMLY2D, 'waist_circ').Key);
  AssertEquals('any listed name', 'waist_circumference', FCatalogue.FindTranslated(FORMAT_SEAMLY2D, 'waist').Key);
  AssertNull('unknown name', FCatalogue.FindTranslated(FORMAT_SEAMLY2D, 'hip_circ'));
  AssertNull('unknown format', FCatalogue.FindTranslated('other', 'waist_circ'));
end;

procedure TTestCatalogue.TestSearch;
begin
  LoadSample;
  AssertEquals('everything', 2, Length(FCatalogue.Search('', '')));
  AssertEquals('by group', 'arm_length', FCatalogue.Search('arm', '')[0].Key);
  AssertEquals('by name, any case', 'waist_circumference', FCatalogue.Search('', 'WAIST')[0].Key);
  AssertEquals('by description', 'arm_length', FCatalogue.Search('', 'wrist')[0].Key);
  AssertEquals('both must match', 0, Length(FCatalogue.Search('arm', 'waist')));
end;

procedure TTestCatalogue.TestOverlayAt;
var
  Keys: TStringArray;
begin
  LoadSample;
  Keys := nil;
  Insert('waist_circumference', Keys, 0);
  Insert('arm_length', Keys, 0);
  AssertEquals('near it', 'waist_circumference', FCatalogue.OverlayAt(cvFront, Vec2(200, 304), 10, Keys).Key);
  AssertNull('too far', FCatalogue.OverlayAt(cvFront, Vec2(200, 320), 10, Keys));
  AssertNull('another view', FCatalogue.OverlayAt(cvBack, Vec2(200, 300), 10, Keys));
  AssertEquals('its own view', 'arm_length', FCatalogue.OverlayAt(cvSide, Vec2(100, 400), 10, Keys).Key);
end;

procedure TTestCatalogue.TestOverlayAtOnlyListedKeys;
var
  Keys: TStringArray;
begin
  LoadSample;
  Keys := nil;
  Insert('hip', Keys, 0);
  AssertNull('nothing listed is there', FCatalogue.OverlayAt(cvFront, Vec2(200, 300), 10, Keys));
end;

procedure TTestCatalogue.TestBadCatalogues;
var
  Err: string;
begin
  AssertFalse(FCatalogue.LoadFromText('{"format": "pattern", "version": 1}', Err));
  AssertEquals(rsCatalogueWrongFormat, Err);
  AssertFalse(FCatalogue.LoadFromText('{"format": "measurement-catalogue", "version": 99}', Err));
  AssertEquals(Format(rsCatalogueNewerVersion, [99]), Err);
  AssertFalse(FCatalogue.LoadFromText('{"format": "measurement-catalogue", "version": 1}', Err));
  AssertEquals(rsCatalogueNoFigures, Err);
  AssertFalse(FCatalogue.LoadFromText('{"format": "measurement-catalogue", "version": 1, "figures": {"front": []}}', Err));
  AssertEquals(Format(rsCatalogueBadFigure, ['front']), Err);
  AssertFalse(FCatalogue.LoadFromText('{"format": "measurement-catalogue", "version": 1, "figures": {"front": [' + FIGURE +
    '], "back": [[[0, 0]]], "side": [' + FIGURE + ']}}', Err));
  AssertEquals(Format(rsCatalogueBadFigure, ['back']), Err);
  AssertFalse(FCatalogue.LoadFromText(Copy(HEAD, 1, Pos(', "measurements"', HEAD) - 1) + '}', Err));
  AssertEquals(rsCatalogueNoList, Err);
end;

procedure TTestCatalogue.TestBadEntries;
begin
  AssertLoadFails('{"key": "a", "group": "arm"}', rsCatalogueBadEntry);
  AssertLoadFails('3', rsCatalogueBadEntry);
  AssertLoadFails(WAIST_ENTRY + ', ' + WAIST_ENTRY, Format(rsCatalogueDuplicate, ['waist_circumference']));
  AssertLoadFails('{"key": "a", ' + ENTRY_REST + ', "group": "toes", "view": "front", "overlay": [[0, 0], [1, 1]], "range": [1, 2]}',
    Format(rsCatalogueBadGroup, ['a', 'toes']));
  AssertLoadFails('{"key": "a", ' + ENTRY_REST + ', "group": "arm", "view": "top", "overlay": [[0, 0], [1, 1]], "range": [1, 2]}',
    Format(rsCatalogueBadView, ['a', 'top']));
  AssertLoadFails('{"key": "a", ' + ENTRY_REST + ', "group": "arm", "view": "front", "overlay": [[0, 0]], "range": [1, 2]}',
    Format(rsCatalogueBadOverlay, ['a']));
  AssertLoadFails('{"key": "a", ' + ENTRY_REST + ', "group": "arm", "view": "front", "overlay": [[0, 0], [1]], "range": [1, 2]}',
    Format(rsCatalogueBadOverlay, ['a']));
  AssertLoadFails('{"key": "a", ' + ENTRY_REST + ', "group": "arm", "view": "front", "overlay": [[0, 0], [1, 1]], "range": [2, 1]}',
    Format(rsCatalogueBadRange, ['a']));
  AssertLoadFails('{"key": "a", ' + ENTRY_REST + ', "group": "arm", "view": "front", "overlay": [[0, 0], [1, 1]]}',
    Format(rsCatalogueBadRange, ['a']));
end;

procedure TTestCatalogue.TestFailedLoadLeavesItEmpty;
var
  Err: string;
begin
  AssertFalse(FCatalogue.LoadFromText(HEAD + WAIST_ENTRY + ', {"key": "2"}]}', Err));
  AssertEquals(0, FCatalogue.Count);
  AssertEquals(0, Length(FCatalogue.Figures[cvFront]));
end;

procedure TTestCatalogue.TestMissingFile;
var
  Err: string;
begin
  AssertFalse(FCatalogue.LoadFromFile(ConcatPaths([GetTempDir, 'no-such-catalogue.json']), Err));
  AssertTrue(Err <> '');
end;

procedure TTestCatalogue.TestLayoutRoundTrip;
var
  Layout: TFigureLayout;
  View, Found: TCatalogueView;
  Back: TVec2;
begin
  Layout := LayoutFigures(600, 300);
  for View := Low(TCatalogueView) to High(TCatalogueView) do
  begin
    AssertTrue(ScreenToFigure(Layout, FigureToScreen(Layout, View, Vec2(120, 340)), Found, Back));
    AssertTrue('the same view', Found = View);
    AssertNear('x', 120, Back.X);
    AssertNear('y', 340, Back.Y);
  end;
end;

procedure TTestCatalogue.TestOutsideTheViews;
var
  Layout: TFigureLayout;
  Found: TCatalogueView;
  OnFigure: TVec2;
begin
  // Wider than it needs, so there is room left at the sides
  Layout := LayoutFigures(1000, 300);
  AssertNear('fits the height', 0.3, Layout.Scale);
  AssertFalse('left of the views', ScreenToFigure(Layout, Vec2(10, 150), Found, OnFigure));
  AssertFalse('below them', ScreenToFigure(Layout, Vec2(500, 301), Found, OnFigure));
end;

procedure TTestCatalogue.TestDistanceToPath;
var
  Path: TFigurePath;
begin
  Path := nil;
  SetLength(Path, 3);
  Path[0] := Vec2(0, 0);
  Path[1] := Vec2(10, 0);
  Path[2] := Vec2(10, 10);
  AssertNear('along a part', 3, DistanceToPath(Vec2(5, 3), Path));
  AssertNear('past the end', 5, DistanceToPath(Vec2(10, 15), Path));
  AssertNear('on it', 0, DistanceToPath(Vec2(10, 4), Path));
end;

procedure TTestCatalogue.TestFindsFile;
begin
  AssertTrue(TAppPaths.CatalogueFile, FileExists(TAppPaths.CatalogueFile));
end;

procedure TTestCatalogue.TestShippedLoads;
begin
  LoadShipped;
  AssertTrue('a useful number', FCatalogue.Count >= 70);
end;

// Keys use whole words, not the abbreviations of other programs
procedure TTestCatalogue.TestShippedKeysAreWholeWords;
var
  Index: integer;
  Abbreviation, Key: string;
begin
  LoadShipped;
  for Index := 0 to FCatalogue.Count - 1 do
  begin
    Key := '_' + FCatalogue[Index].Key + '_';
    for Abbreviation in ABBREVIATIONS do
      AssertEquals(Key, 0, Pos('_' + Abbreviation + '_', Key));
  end;
end;

procedure TTestCatalogue.TestShippedCoversEveryGroup;
var
  Group: string;
begin
  LoadShipped;
  for Group in CATALOGUE_GROUPS do
    AssertTrue(Group, Length(FCatalogue.Search(Group, '')) > 0);
end;

procedure TTestCatalogue.TestShippedOnTheFigure;
var
  Index: integer;
  Point: TVec2;
begin
  LoadShipped;
  for Index := 0 to FCatalogue.Count - 1 do
    for Point in FCatalogue[Index].Overlay do
    begin
      AssertTrue(FCatalogue[Index].Key, (Point.X >= 0) and (Point.X <= FIGURE_WIDTH));
      AssertTrue(FCatalogue[Index].Key, (Point.Y >= 0) and (Point.Y <= FIGURE_HEIGHT));
    end;
end;

// Import and export go through this, so no two entries can share a name
procedure TTestCatalogue.TestShippedTranslatesOneToOne;
var
  Index: integer;
  Name: string;
begin
  LoadShipped;
  for Index := 0 to FCatalogue.Count - 1 do
  begin
    Name := FCatalogue[Index].NameIn(FORMAT_SEAMLY2D);
    AssertTrue(FCatalogue[Index].Key + ' has a name', Name <> '');
    AssertEquals(FCatalogue[Index].Key, FCatalogue.FindTranslated(FORMAT_SEAMLY2D, Name).Key);
  end;
end;

procedure TTestCatalogue.TestShippedKnowsSeamlyNames;
var
  Index: integer;
begin
  LoadShipped;
  AssertTrue('one of ours', FCatalogue.IsKnownName(FORMAT_SEAMLY2D, 'waist_circ'));
  AssertTrue('one not in the catalogue', FCatalogue.IsKnownName(FORMAT_SEAMLY2D, 'neck_arc_f'));
  AssertFalse(FCatalogue.IsKnownName(FORMAT_SEAMLY2D, 'waist_circumference'));
  AssertFalse(FCatalogue.IsKnownName('other', 'waist_circ'));
  for Index := 0 to FCatalogue.Count - 1 do
    AssertTrue(FCatalogue[Index].Key, FCatalogue.IsKnownName(FORMAT_SEAMLY2D, FCatalogue[Index].NameIn(FORMAT_SEAMLY2D)));
end;

procedure TTestCatalogue.TestShippedReadsWell;
var
  Index: integer;
begin
  LoadShipped;
  for Index := 0 to FCatalogue.Count - 1 do
  begin
    AssertTrue(FCatalogue[Index].Key, FCatalogue[Index].Name <> '');
    AssertTrue(FCatalogue[Index].Key, FCatalogue[Index].Description <> '');
    AssertTrue(FCatalogue[Index].Key, FCatalogue[Index].HowTo <> '');
  end;
end;

initialization
  RegisterTest(TTestCatalogue);

end.
