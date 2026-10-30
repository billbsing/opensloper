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

unit Sloper.Tests.GridColumns;

{$mode ObjFPC}{$H+}

interface

uses
  fpcunit, testregistry, Sloper.Tests.TestCase, Sloper.UI.GridColumns;

type
  TTestGridColumns = class(TOSTestCase)
  private
    // Every code point is ten pixels wide
    function MeasureText(const Text: string): integer;
  published
    procedure TestShareSetsNameWidth;
    procedure TestNameColumnKeepsMinimum;
    procedure TestValueColumnKeepsMinimum;
    procedure TestNarrowPanelSplitsEvenly;
    procedure TestShareFollowsPosition;
    procedure TestShareClampsPosition;
    procedure TestShareWithNoSpaceIsDefault;
    procedure TestFitLeavesShortTextAlone;
    procedure TestFitCutsLongText;
    procedure TestFitNeverSplitsACharacter;
    procedure TestFitDropsSpaceBeforeEllipsis;
    procedure TestFitTooNarrowGivesEllipsis;
  end;

implementation

uses
  Sloper.Core.Settings;

function TTestGridColumns.MeasureText(const Text: string): integer;
var
  Index: integer;
begin
  Result := 0;
  for Index := 1 to Length(Text) do
    if (Ord(Text[Index]) and $C0) <> $80 then
      Inc(Result, 10);
end;

procedure TTestGridColumns.TestShareSetsNameWidth;
begin
  AssertEquals(100, NameColumnWidth(250, 40, 0.4));
end;

procedure TTestGridColumns.TestNameColumnKeepsMinimum;
begin
  AssertEquals(40, NameColumnWidth(250, 40, 0.01));
end;

procedure TTestGridColumns.TestValueColumnKeepsMinimum;
begin
  AssertEquals(210, NameColumnWidth(250, 40, 0.99));
end;

procedure TTestGridColumns.TestNarrowPanelSplitsEvenly;
begin
  AssertEquals(30, NameColumnWidth(60, 40, 0.9));
end;

procedure TTestGridColumns.TestShareFollowsPosition;
begin
  AssertNear('share', 0.5, NameShareAt(100, 200, 40));
end;

procedure TTestGridColumns.TestShareClampsPosition;
begin
  AssertNear('too far left', 0.2, NameShareAt(-30, 200, 40));
  AssertNear('too far right', 0.8, NameShareAt(500, 200, 40));
end;

procedure TTestGridColumns.TestShareWithNoSpaceIsDefault;
begin
  AssertNear('no space', DefaultNameColumnShare, NameShareAt(10, 0, 40));
  AssertNear('too narrow for both minimums', DefaultNameColumnShare, NameShareAt(10, 60, 40));
end;

procedure TTestGridColumns.TestFitLeavesShortTextAlone;
begin
  AssertEquals('Length', FitText('Length', 60, @MeasureText));
end;

procedure TTestGridColumns.TestFitCutsLongText;
begin
  AssertEquals('Star…', FitText('Start handle', 50, @MeasureText));
end;

procedure TTestGridColumns.TestFitNeverSplitsACharacter;
begin
  AssertEquals('Ärm…', FitText('Ärmelweite', 40, @MeasureText));
end;

procedure TTestGridColumns.TestFitDropsSpaceBeforeEllipsis;
begin
  AssertEquals('Point…', FitText('Point 12 handle', 70, @MeasureText));
end;

procedure TTestGridColumns.TestFitTooNarrowGivesEllipsis;
begin
  AssertEquals('…', FitText('Length', 5, @MeasureText));
end;

initialization
  RegisterTest(TTestGridColumns);

end.
