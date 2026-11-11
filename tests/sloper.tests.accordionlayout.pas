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

// Where the side panel's headers and its open section go
unit Sloper.Tests.AccordionLayout;

{$mode ObjFPC}{$H+}

interface

uses
  fpcunit, testregistry, Sloper.Tests.TestCase, Sloper.UI.AccordionLayout;

type
  TTestAccordionLayout = class(TOSTestCase)
  published
    procedure TestFirstOpen;
    procedure TestMiddleOpen;
    procedure TestLastOpen;
    procedure TestOneSection;
    procedure TestNoSections;
    procedure TestTooShort;
    procedure TestActiveKeptInRange;
  end;

implementation

const
  HEADER = 20;

procedure TTestAccordionLayout.TestFirstOpen;
var
  Places: TAccordionPlaces;
begin
  Places := PlaceSections(3, 0, HEADER, 200);
  AssertEquals('open header at the top', 0, Places.HeaderTops[0]);
  AssertEquals('section under it', 20, Places.ContentTop);
  AssertEquals('section down to the others', 140, Places.ContentHeight);
  AssertEquals('second at the bottom', 160, Places.HeaderTops[1]);
  AssertEquals('third under it', 180, Places.HeaderTops[2]);
end;

procedure TTestAccordionLayout.TestMiddleOpen;
var
  Places: TAccordionPlaces;
begin
  Places := PlaceSections(4, 1, HEADER, 200);
  AssertEquals(0, Places.HeaderTops[0]);
  AssertEquals('open header under the first', 20, Places.HeaderTops[1]);
  AssertEquals(40, Places.ContentTop);
  AssertEquals(120, Places.ContentHeight);
  AssertEquals(160, Places.HeaderTops[2]);
  AssertEquals(180, Places.HeaderTops[3]);
end;

procedure TTestAccordionLayout.TestLastOpen;
var
  Places: TAccordionPlaces;
begin
  Places := PlaceSections(3, 2, HEADER, 200);
  AssertEquals(0, Places.HeaderTops[0]);
  AssertEquals(20, Places.HeaderTops[1]);
  AssertEquals(40, Places.HeaderTops[2]);
  AssertEquals(60, Places.ContentTop);
  AssertEquals('down to the bottom', 140, Places.ContentHeight);
end;

procedure TTestAccordionLayout.TestOneSection;
var
  Places: TAccordionPlaces;
begin
  Places := PlaceSections(1, 0, HEADER, 100);
  AssertEquals(0, Places.HeaderTops[0]);
  AssertEquals(20, Places.ContentTop);
  AssertEquals(80, Places.ContentHeight);
end;

procedure TTestAccordionLayout.TestNoSections;
var
  Places: TAccordionPlaces;
begin
  Places := PlaceSections(0, 0, HEADER, 100);
  AssertEquals(0, Length(Places.HeaderTops));
  AssertEquals(0, Places.ContentHeight);
end;

// The open section gets nothing and the last headers run past the bottom
procedure TTestAccordionLayout.TestTooShort;
var
  Places: TAccordionPlaces;
begin
  Places := PlaceSections(4, 0, HEADER, 50);
  AssertEquals(20, Places.ContentTop);
  AssertEquals(0, Places.ContentHeight);
  AssertEquals('straight under the open header', 20, Places.HeaderTops[1]);
  AssertEquals(60, Places.HeaderTops[3]);
end;

procedure TTestAccordionLayout.TestActiveKeptInRange;
var
  Places: TAccordionPlaces;
begin
  Places := PlaceSections(2, 5, HEADER, 100);
  AssertEquals('the last is open', 40, Places.ContentTop);
  Places := PlaceSections(2, -1, HEADER, 100);
  AssertEquals('the first is open', 20, Places.ContentTop);
end;

initialization
  RegisterTest(TTestAccordionLayout);
end.
