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

// The draft drawn as a PNG image, with the bundled fonts.
unit Sloper.Tests.DraftPNG;

{$mode ObjFPC}{$H+}

interface

uses
  SysUtils, fpcunit, testregistry, Sloper.Tests.TestCase, Sloper.Core.Pattern;

type
  TTestDraftPNG = class(TOSTestCase)
  private
    FPattern: TPattern;
    function Render(Width: integer; Labels: boolean): rawbytestring;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestBundledFontsLoad;
    procedure TestImageSize;
    procedure TestLabelsAreDrawn;
    procedure TestWidthLimits;
  end;

implementation

uses
  Sloper.Core.Draft, Sloper.Output.DraftSVG, Sloper.Output.DraftPNG;

const
  // Bytes 17 to 24 of a PNG file: the width and height, big-endian
  PNG_WIDTH_OFFSET = 17;
  PNG_HEIGHT_OFFSET = 21;

function PngSize(const Png: rawbytestring; Offset: integer): longword;
begin
  Result := BEtoN(PLongWord(@Png[Offset])^);
end;

procedure TTestDraftPNG.SetUp;
begin
  FPattern := TPattern.Create;
  // 200 wide and 100 high, so the image is half as high as it is wide
  FPattern.AddFreePoint('A', '0', '0');
  FPattern.AddFreePoint('B', '200', '100');
  FPattern.AddLine('1', '2', erOutline);
  FPattern.Evaluate;
end;

procedure TTestDraftPNG.TearDown;
begin
  FreeAndNil(FPattern);
end;

function TTestDraftPNG.Render(Width: integer; Labels: boolean): rawbytestring;
var
  Options: TDraftSVGOptions;
  Err: string;
begin
  Options := DefaultDraftSVGOptions;
  Options.Labels := Labels;
  AssertTrue(Err, DraftToPNG(FPattern, Options, Width, Result, Err));
end;

procedure TTestDraftPNG.TestBundledFontsLoad;
begin
  AssertEquals('Noto Sans, DejaVu Sans', DrawingFontFamilies);
end;

procedure TTestDraftPNG.TestImageSize;
var
  Png: rawbytestring;
begin
  Png := Render(400, False);
  AssertEquals('a PNG file', #137'PNG', Copy(Png, 1, 4));
  AssertEquals('width', 400, PngSize(Png, PNG_WIDTH_OFFSET));
  // The margin is a share of the longer side, so not exactly half
  AssertTrue('height follows the drawing', Abs(integer(PngSize(Png, PNG_HEIGHT_OFFSET)) - 220) < 30);
end;

// Text needs the fonts; without them BGRABitmap raises
procedure TTestDraftPNG.TestLabelsAreDrawn;
begin
  AssertFalse('names change the image', Render(400, False) = Render(400, True));
end;

procedure TTestDraftPNG.TestWidthLimits;
var
  Png: rawbytestring;
  Err: string;
begin
  AssertFalse(DraftToPNG(FPattern, DefaultDraftSVGOptions, PNG_MIN_WIDTH - 1, Png, Err));
  AssertTrue('says why', Err <> '');
  AssertFalse(DraftToPNG(FPattern, DefaultDraftSVGOptions, PNG_MAX_WIDTH + 1, Png, Err));
  AssertTrue(Err, DraftToPNG(FPattern, DefaultDraftSVGOptions, PNG_MIN_WIDTH, Png, Err));
end;

initialization
  RegisterTest(TTestDraftPNG);
end.
