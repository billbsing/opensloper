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

// Splitting an edge a piece already uses: the piece, its notches and
// allowances, and seams on the edge take the parts.
unit Sloper.Tests.SplitPieces;

{$mode ObjFPC}{$H+}

interface

uses
  fpcunit, testregistry, Sloper.Tests.TestCase, Sloper.Core.Draft, Sloper.Core.Piece, Sloper.Core.Pattern;

type
  TTestSplitPieces = class(TOSTestCase)
  private
    FPattern: TPattern;
    // Corners at (Left, 0) and (Left + Width, Height); Top runs left to right
    function Panel(const AName: string; Left, Width, Height: double; out Top, Right: string): TPieceObject;
    function MidPoint(const EdgeKey: string; Along: double): string;
    procedure Split(const EdgeKey, PointKey: string; out First, Second: TSplitPart);
    function PathText(Piece: TPieceObject): string;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestPieceTakesTheParts;
    procedure TestOverrideGoesToBothParts;
    procedure TestNotchesFollow;
    procedure TestSeamTakesBothParts;
    procedure TestReversedEdge;
    procedure TestFoldKeepsTheEdge;
    procedure TestPointOffTheEdge;
    procedure TestOverridePathIndex;
  end;

implementation

uses
  SysUtils, Sloper.Core.Geometry, Sloper.Core.EvalTypes, Sloper.Core.PieceDetect, Sloper.Core.Seam;

procedure TTestSplitPieces.SetUp;
begin
  FPattern := TPattern.Create;
end;

procedure TTestSplitPieces.TearDown;
begin
  FreeAndNil(FPattern);
end;

function TTestSplitPieces.Panel(const AName: string; Left, Width, Height: double; out Top, Right: string): TPieceObject;
var
  A, B, C, D, Reason: string;
  Path: TPiecePath;

  function Pt(X, Y: double): string;
  begin
    Result := FPattern.AddFreePoint('', FloatToStr(X), FloatToStr(Y)).Key;
  end;

begin
  A := Pt(Left, 0);
  B := Pt(Left + Width, 0);
  C := Pt(Left + Width, Height);
  D := Pt(Left, Height);
  Top := FPattern.AddLine(A, B, erOutline).Key;
  Right := FPattern.AddLine(B, C, erOutline).Key;
  FPattern.AddLine(C, D, erOutline);
  FPattern.AddLine(D, A, erOutline);
  FPattern.Evaluate;
  AssertTrue(Reason, DetectPiecePath(FPattern, Vec2(Left + Width / 2, Height / 2), Path, Reason));
  Result := FPattern.AddPiece(AName, Path, '10');
  AssertNotNull(FPattern.LastError, Result);
  FPattern.Evaluate;
end;

function TTestSplitPieces.MidPoint(const EdgeKey: string; Along: double): string;
begin
  Result := FPattern.AddAlongEdgePoint('', EdgeKey, False, amLength, FloatToStr(Along)).Key;
end;

procedure TTestSplitPieces.Split(const EdgeKey, PointKey: string; out First, Second: TSplitPart);
begin
  AssertTrue(FPattern.LastError, FPattern.SplitEdge(EdgeKey, PointKey, First, Second));
  FPattern.Evaluate;
end;

function TTestSplitPieces.PathText(Piece: TPieceObject): string;
var
  Entry: TPieceEdge;
begin
  Result := '';
  for Entry in Piece.Path do
  begin
    if Result <> '' then
      Result := Result + ' ';
    Result := Result + Entry.EdgeKey;
    if Entry.Reversed then
      Result := Result + 'r';
  end;
end;

procedure TTestSplitPieces.TestPieceTakesTheParts;
var
  Piece: TPieceObject;
  Top, Right: string;
  First, Second: TSplitPart;
  Perimeter: double;
  Index: integer;
begin
  Piece := Panel('Front', 0, 100, 200, Top, Right);
  Perimeter := Piece.Perimeter;
  Index := Piece.PathIndexOf(Top);
  Split(Top, MidPoint(Top, 40), First, Second);
  AssertEquals('one edge more', 5, Length(Piece.Path));
  AssertEquals('the whole edge is gone', -1, Piece.PathIndexOf(Top));
  AssertEquals('first part in its place', Index, Piece.PathIndexOf(First.Key));
  AssertEquals('then the second', Index + 1, Piece.PathIndexOf(Second.Key));
  AssertTrue(Piece.Message, Piece.State = esValid);
  AssertNear('same outline', Perimeter, Piece.Perimeter);
end;

procedure TTestSplitPieces.TestOverrideGoesToBothParts;
var
  Piece: TPieceObject;
  Top, Right: string;
  First, Second: TSplitPart;
  Index, Overrides: integer;
begin
  Piece := Panel('Front', 0, 100, 200, Top, Right);
  AssertTrue(FPattern.LastError, FPattern.SetEdgeAllowance(Piece, Piece.PathIndexOf(Top), '20'));
  AssertTrue(FPattern.LastError, FPattern.SetEdgeAllowance(Piece, Piece.PathIndexOf(Right), '5'));
  FPattern.Evaluate;
  Split(Top, MidPoint(Top, 40), First, Second);
  AssertEquals('first part', '20', FPattern.FormulaText(Piece, Piece.OverrideField(Piece.PathIndexOf(First.Key))));
  AssertEquals('second part', '20', FPattern.FormulaText(Piece, Piece.OverrideField(Piece.PathIndexOf(Second.Key))));
  AssertEquals('Right keeps its own', '5', FPattern.FormulaText(Piece, Piece.OverrideField(Piece.PathIndexOf(Right))));
  Overrides := 0;
  for Index := 0 to High(Piece.Path) do
    if Piece.HasOverride(Index) then
      Inc(Overrides);
  AssertEquals('no others', 3, Overrides);
  AssertTrue(Piece.Message, Piece.State = esValid);
end;

procedure TTestSplitPieces.TestNotchesFollow;
var
  Piece: TPieceObject;
  Top, Right: string;
  First, Second: TSplitPart;
  Before: array[0..1] of TNotchMark;
begin
  Piece := Panel('Front', 0, 100, 200, Top, Right);
  AssertTrue(FPattern.LastError, FPattern.AddEdgeNotch(Piece, Top, '30'));
  AssertTrue(FPattern.LastError, FPattern.AddEdgeNotch(Piece, Top, '20 * 4'));
  FPattern.Evaluate;
  Before[0] := Piece.NotchMarks[0];
  Before[1] := Piece.NotchMarks[1];
  Split(Top, MidPoint(Top, 50), First, Second);
  AssertEquals('before the split', First.Key, Piece.Notches[0].EdgeKey);
  AssertEquals('formula kept', '30', FPattern.FormulaText(Piece, Piece.NotchField(0)));
  AssertEquals('after it', Second.Key, Piece.Notches[1].EdgeKey);
  AssertEquals('from the second part''s start', '(20 * 4) - ' + First.DisplayName + '.length',
    FPattern.FormulaText(Piece, Piece.NotchField(1)));
  AssertTrue(Piece.Message, Piece.State = esValid);
  AssertPointsNear('first stays', Before[0].Seam, Piece.NotchMarks[0].Seam);
  AssertPointsNear('second stays', Before[1].Seam, Piece.NotchMarks[1].Seam);
end;

procedure TTestSplitPieces.TestSeamTakesBothParts;
var
  Front, Back: TPieceObject;
  TopF, RightF, TopB, RightB: string;
  SideA, SideB: TSeamSide;
  Seam: TSeamObject;
  First, Second: TSplitPart;
  LengthA, LengthB: double;
begin
  Front := Panel('Front', 0, 100, 200, TopF, RightF);
  Back := Panel('Back', 300, 120, 200, TopB, RightB);
  SideA := [Default(TSeamEntry)];
  SideA[0].PieceKey := Front.Key;
  SideA[0].EdgeKey := TopF;
  SideB := [Default(TSeamEntry)];
  SideB[0].PieceKey := Back.Key;
  SideB[0].EdgeKey := TopB;
  Seam := FPattern.AddSeam('', SideA, SideB);
  AssertNotNull(FPattern.LastError, Seam);
  FPattern.Evaluate;
  LengthA := Seam.LengthA;
  LengthB := Seam.LengthB;
  Split(TopB, MidPoint(TopB, 30), First, Second);
  AssertEquals('side B has both parts', 2, Length(Seam.SideB));
  // Side B runs against its path, so the second part comes first
  AssertEquals(Second.Key, Seam.SideB[0].EdgeKey);
  AssertEquals(First.Key, Seam.SideB[1].EdgeKey);
  AssertTrue(Seam.Message, Seam.State = esValid);
  AssertNear('side A', LengthA, Seam.LengthA);
  AssertNear('side B', LengthB, Seam.LengthB);
end;

// Two panels side by side share an edge, which one of them runs backwards
procedure TTestSplitPieces.TestReversedEdge;
var
  Left, Right: TPieceObject;
  Top, Shared, B, C, E, F, Reason: string;
  Path: TPiecePath;
  First, Second: TSplitPart;
  Piece: TPieceObject;
  Index: integer;
  Perimeters: array[0..1] of double;
  Reversed: array[0..1] of boolean;
begin
  Left := Panel('Left', 0, 100, 200, Top, Shared);
  B := TEdgeObject(FPattern.FindNode(Shared)).StartKey;
  C := TEdgeObject(FPattern.FindNode(Shared)).EndKey;
  E := FPattern.AddFreePoint('', '200', '0').Key;
  F := FPattern.AddFreePoint('', '200', '200').Key;
  FPattern.AddLine(B, E, erOutline);
  FPattern.AddLine(E, F, erOutline);
  FPattern.AddLine(F, C, erOutline);
  FPattern.Evaluate;
  AssertTrue(Reason, DetectPiecePath(FPattern, Vec2(150, 100), Path, Reason));
  Right := FPattern.AddPiece('Right', Path, '10');
  AssertNotNull(FPattern.LastError, Right);
  FPattern.Evaluate;
  for Index := 0 to 1 do
  begin
    Piece := Left;
    if Index = 1 then
      Piece := Right;
    Perimeters[Index] := Piece.Perimeter;
    Reversed[Index] := Piece.Path[Piece.PathIndexOf(Shared)].Reversed;
  end;
  AssertTrue('one runs it each way', Reversed[0] <> Reversed[1]);
  Split(Shared, MidPoint(Shared, 50), First, Second);
  for Index := 0 to 1 do
  begin
    Piece := Left;
    if Index = 1 then
      Piece := Right;
    AssertTrue(Piece.Name + ': ' + Piece.Message, Piece.State = esValid);
    AssertNear(Piece.Name + ' outline', Perimeters[Index], Piece.Perimeter);
    if Reversed[Index] then
      AssertEquals(Piece.Name + ': second part first', Piece.PathIndexOf(Second.Key) + 1, Piece.PathIndexOf(First.Key))
    else
      AssertEquals(Piece.Name + ': first part first', Piece.PathIndexOf(First.Key) + 1, Piece.PathIndexOf(Second.Key));
  end;
end;

procedure TTestSplitPieces.TestFoldKeepsTheEdge;
var
  Piece: TPieceObject;
  Top, Right: string;
  First, Second: TSplitPart;
begin
  Piece := Panel('Front', 0, 100, 200, Top, Right);
  AssertTrue(FPattern.LastError, FPattern.SetFoldEdge(Piece, Right));
  Split(Right, MidPoint(Right, 50), First, Second);
  AssertEquals('kept whole', 4, Length(Piece.Path));
  AssertTrue('still the fold', Piece.PathIndexOf(Right) >= 0);
end;

procedure TTestSplitPieces.TestPointOffTheEdge;
var
  Piece: TPieceObject;
  Top, Right, Path: string;
  First, Second: TSplitPart;
begin
  Piece := Panel('Front', 0, 100, 200, Top, Right);
  Path := PathText(Piece);
  Split(Top, FPattern.AddFreePoint('Off', '50', '30').Key, First, Second);
  AssertEquals('unchanged', Path, PathText(Piece));
end;

procedure TTestSplitPieces.TestOverridePathIndex;
var
  Piece: TPieceObject;
  Top, Right: string;
begin
  Piece := Panel('Front', 0, 100, 200, Top, Right);
  AssertEquals('edge2.allowance', 1, Piece.OverridePathIndex(Piece.OverrideField(1)));
  AssertEquals('the piece''s own', -1, Piece.OverridePathIndex(PIECE_ALLOWANCE_FIELD));
  AssertEquals('past the path', -1, Piece.OverridePathIndex('edge9.allowance'));
end;

initialization
  RegisterTest(TTestSplitPieces);
end.
