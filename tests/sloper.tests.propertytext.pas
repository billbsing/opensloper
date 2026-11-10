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

// The text the properties panel works out: the pieces a marking is on, what
// a note hangs from, an edge allowance's caption, and a note's typed text.
unit Sloper.Tests.PropertyText;

{$mode ObjFPC}{$H+}

interface

uses
  SysUtils, fpcunit, testregistry, Sloper.Tests.TestCase, Sloper.Core.Pattern, Sloper.Core.Draft, Sloper.Core.Piece;

type
  TTestPropertyText = class(TOSTestCase)
  private
    FPattern: TPattern;
    FEdges: TRectangleEdges;
    function Pt(const AName: string; X: double = 0; Y: double = 0): string;
    // A 200 by 100 piece from the origin, named Panel
    function Panel: TPieceObject;
    // The same outline again, as another piece over the first
    function PanelCopy(const AName: string): TPieceObject;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestPlainPointIsNotMarking;
    procedure TestMarkerOutsidePieces;
    procedure TestMarkerInOnePiece;
    procedure TestMarkerInTwoPieces;
    procedure TestMarkingLine;
    procedure TestNoteOnPoint;
    procedure TestNoteOnEdge;
    procedure TestNoteOnPiece;
    procedure TestFreeNote;
    procedure TestNoteAfterMadeFree;
    procedure TestPieceAllowanceIsNoEdgeCaption;
    procedure TestEdgeAllowanceCaption;
    procedure TestNoteTextLineFeeds;
    procedure TestNoteTextOtherBreaks;
    procedure TestNoteTextTrailingBreaks;
  end;

implementation

uses
  Sloper.Core.Note, Sloper.UI.PropertyText;

procedure TTestPropertyText.SetUp;
begin
  inherited SetUp;
  FPattern := TPattern.Create;
end;

procedure TTestPropertyText.TearDown;
begin
  FreeAndNil(FPattern);
  inherited TearDown;
end;

function TTestPropertyText.Pt(const AName: string; X, Y: double): string;
begin
  Result := FPattern.AddFreePoint(AName, FloatToStr(X), FloatToStr(Y)).Key;
end;

function TTestPropertyText.Panel: TPieceObject;
begin
  AssertTrue(FPattern.LastError, FPattern.AddRectangle(Pt('O'), '200', '100', erOutline, FEdges));
  Result := PanelCopy('Panel');
end;

function TTestPropertyText.PanelCopy(const AName: string): TPieceObject;
var
  Path: TPiecePath;
  Index: integer;
begin
  Path := nil;
  SetLength(Path, 4);
  for Index := 0 to 3 do
    Path[Index].EdgeKey := FEdges[Index].Key;
  Result := FPattern.AddPiece(AName, Path, '10');
  AssertNotNull(FPattern.LastError, Result);
  FPattern.Evaluate;
end;

procedure TTestPropertyText.TestPlainPointIsNotMarking;
begin
  Panel;
  AssertEquals('-', MarkedOnText(FPattern, TDraftObject(FPattern.FindNode(Pt('Plain', 50, 50)))));
end;

procedure TTestPropertyText.TestMarkerOutsidePieces;
var
  Key: string;
begin
  Panel;
  Key := Pt('Far', 500, 500);
  AssertTrue(FPattern.SetMarker(Key, pmHole));
  FPattern.Evaluate;
  AssertEquals('No piece', MarkedOnText(FPattern, TDraftObject(FPattern.FindNode(Key))));
end;

procedure TTestPropertyText.TestMarkerInOnePiece;
var
  Key: string;
begin
  Panel;
  Key := Pt('H', 100, 50);
  AssertTrue(FPattern.SetMarker(Key, pmHole));
  FPattern.Evaluate;
  AssertEquals('Panel', MarkedOnText(FPattern, TDraftObject(FPattern.FindNode(Key))));
end;

procedure TTestPropertyText.TestMarkerInTwoPieces;
var
  Key: string;
begin
  Panel;
  PanelCopy('Lining');
  Key := Pt('H', 100, 50);
  AssertTrue(FPattern.SetMarker(Key, pmMatch));
  FPattern.Evaluate;
  AssertEquals('Panel, Lining', MarkedOnText(FPattern, TDraftObject(FPattern.FindNode(Key))));
end;

procedure TTestPropertyText.TestMarkingLine;
var
  Line: TLineObject;
begin
  Panel;
  Line := FPattern.AddLine(Pt('P1', 50, 20), Pt('P2', 50, 80), erPlacement);
  AssertNotNull(FPattern.LastError, Line);
  FPattern.Evaluate;
  AssertEquals('Panel', MarkedOnText(FPattern, Line));
end;

procedure TTestPropertyText.TestNoteOnPoint;
var
  Note: TNoteObject;
begin
  Note := FPattern.AddNote('', 'Stay-stitch', naPoint, Pt('A', 10, 20), '', '5', '-3');
  AssertNotNull(FPattern.LastError, Note);
  AssertEquals('Point A', NoteAnchorText(FPattern, Note));
end;

procedure TTestPropertyText.TestNoteOnEdge;
var
  Edge: TLineObject;
  Note: TNoteObject;
begin
  Edge := FPattern.AddLine(Pt('A'), Pt('B', 100, 0));
  AssertTrue(FPattern.LastError, FPattern.Rename(Edge, 'Hem'));
  Note := FPattern.AddNote('', 'Ease', naEdge, Edge.Key, '0.25', '0', '10');
  AssertNotNull(FPattern.LastError, Note);
  AssertEquals('Hem', NoteAnchorText(FPattern, Note));
end;

procedure TTestPropertyText.TestNoteOnPiece;
var
  Note: TNoteObject;
begin
  Note := FPattern.AddNote('', 'Front', naPiece, Panel.Key, '', '-10', '0');
  AssertNotNull(FPattern.LastError, Note);
  AssertEquals('Piece Panel', NoteAnchorText(FPattern, Note));
end;

procedure TTestPropertyText.TestFreeNote;
var
  Note: TNoteObject;
begin
  Note := FPattern.AddNote('', 'Loose', naFree, '', '', '30', '40');
  AssertNotNull(FPattern.LastError, Note);
  AssertEquals('Nothing (free)', NoteAnchorText(FPattern, Note));
end;

procedure TTestPropertyText.TestNoteAfterMadeFree;
var
  Note: TNoteObject;
begin
  Note := FPattern.AddNote('', 'Stay-stitch', naPoint, Pt('A', 10, 20), '', '5', '-3');
  FPattern.Evaluate;
  AssertTrue(FPattern.LastError, FPattern.MakeNoteFree(Note));
  Note := TNoteObject(FPattern.FindNode(Note.Key));
  AssertEquals('Nothing (free)', NoteAnchorText(FPattern, Note));
end;

procedure TTestPropertyText.TestPieceAllowanceIsNoEdgeCaption;
begin
  AssertEquals('', EdgeAllowanceCaption(FPattern, Panel, PieceAllowanceField));
end;

procedure TTestPropertyText.TestEdgeAllowanceCaption;
var
  Piece: TPieceObject;
  EdgeName: string;
begin
  Piece := Panel;
  AssertTrue(FPattern.LastError, FPattern.SetEdgeAllowance(Piece, 1, '25'));
  Piece := TPieceObject(FPattern.FindNode(Piece.Key));
  EdgeName := FPattern.FindNode(Piece.Path[1].EdgeKey).DisplayName;
  AssertEquals('Allowance, ' + EdgeName, EdgeAllowanceCaption(FPattern, Piece, Piece.OverrideField(1)));
end;

procedure TTestPropertyText.TestNoteTextLineFeeds;
begin
  AssertEquals('Cut' + #10 + 'two', NoteTextFromField('Cut' + #10 + 'two'));
end;

procedure TTestPropertyText.TestNoteTextOtherBreaks;
begin
  AssertEquals('One' + #10 + 'two' + #10 + 'three', NoteTextFromField('One' + #13#10 + 'two' + #13 + 'three'));
end;

procedure TTestPropertyText.TestNoteTextTrailingBreaks;
begin
  AssertEquals('Hem', NoteTextFromField('Hem' + #13#10));
  AssertEquals('Hem', NoteTextFromField('Hem' + #10#10));
  AssertEquals('', NoteTextFromField(#13#10));
end;

initialization
  RegisterTest(TTestPropertyText);
end.
