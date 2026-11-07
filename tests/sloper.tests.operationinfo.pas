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

// The table of operations the reference documentation is written from, held
// to the code: a pattern with every kind of object, saved, has only members
// the table lists, and each formula has the kind its node says.
unit Sloper.Tests.OperationInfo;

{$mode ObjFPC}{$H+}

interface

uses
  fpcunit, testregistry, Sloper.Tests.TestCase, Sloper.Core.Draft, Sloper.Core.Pattern;

type
  TTestOperationInfo = class(TOSTestCase)
  private
    FPattern: TPattern;
    function Check(Obj: TObject): TObject;
    function Pt(const AName, X, Y: string): string;
    function Line(const StartKey, EndKey: string; Role: TEdgeRole = erConstruction): string;
    procedure BuildEveryKind;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestEverySavedMemberListed;
    procedure TestEveryTypeAppears;
    procedure TestFormulaKindsMatch;
    procedure TestTypesAreUnique;
  end;

implementation

uses
  SysUtils, fpjson, Sloper.Core.JSON, Sloper.Core.Geometry, Sloper.Core.Evaluator, Sloper.Core.Piece, Sloper.Core.PieceDetect,
  Sloper.Core.Seam, Sloper.Core.Note, Sloper.Core.Fabrics, Sloper.Core.Transform, Sloper.Core.PatternFile,
  Sloper.Core.OperationInfo;

procedure TTestOperationInfo.SetUp;
begin
  FPattern := TPattern.Create;
  BuildEveryKind;
end;

procedure TTestOperationInfo.TearDown;
begin
  FreeAndNil(FPattern);
end;

function TTestOperationInfo.Check(Obj: TObject): TObject;
begin
  if not Assigned(Obj) then
    Fail('Refused: ' + FPattern.LastError);
  Result := Obj;
end;

function TTestOperationInfo.Pt(const AName, X, Y: string): string;
begin
  Result := TPointObject(Check(FPattern.AddFreePoint(AName, X, Y))).Key;
end;

function TTestOperationInfo.Line(const StartKey, EndKey: string; Role: TEdgeRole): string;
begin
  Result := TEdgeObject(Check(FPattern.AddLine(StartKey, EndKey, Role))).Key;
end;

procedure TTestOperationInfo.BuildEveryKind;
var
  A, B, C, D, E, M, N, S1, S2, Mark, Cross: string;
  AB, BC, CD, DA, Diagonal, Other, Inner, Placement, Curve: string;
  First, Second: TSplitPart;
  EdgeRun: TRunEdgeArray;
  Spec: TTransformSpec;
  Path: TPiecePath;
  Piece: TPieceObject;
  Side: TSeamSide;
  Repeated: TRepeatObject;
  Reason: string;
begin
  A := Pt('A', '0', '0');
  B := Pt('B', '200', '0');
  C := Pt('C', '200', '300');
  D := Pt('D', '0', '300');
  AB := Line(A, B, erOutline);
  BC := Line(B, C, erOutline);
  CD := Line(C, D, erOutline);
  DA := Line(D, A, erOutline);
  Check(FPattern.AddOffsetPoint('P', A, omPolar, '20', '-45'));
  Check(FPattern.AddOffsetPoint('Q', A, omCartesian, '20', '30'));
  E := TPointObject(Check(FPattern.AddAlongEdgePoint('E', AB, False, amLength, '50'))).Key;
  Check(FPattern.AddAlongEdgePoint('F', CD, True, amRatio, '0.5'));
  Check(FPattern.AddBetweenPoint('G', A, C, amRatio, '0.5'));
  Diagonal := Line(A, C);
  Other := Line(B, D);
  Cross := TPointObject(Check(FPattern.AddIntersectPoint('H', Diagonal, Other, False, False, 1))).Key;
  Check(FPattern.AddCircleEdgePoint('I', A, '250', BC, True, 1));
  Check(FPattern.AddCircleCirclePoint('J', A, '150', B, '150', 2));
  Check(FPattern.AddProjectPoint('K', E, CD, pdPerpendicular, '', True));
  Check(FPattern.AddProjectPoint('L', E, CD, pdAngle, '-80', True));
  Repeated := TRepeatObject(Check(FPattern.AddRepeatOnEdge('R', DA, '3', False)));
  FPattern.UsePoint(Repeated.Key + '[2]');
  Check(FPattern.AddRepeatBetween('T', A, B, '2', True));
  Curve := TEdgeObject(Check(FPattern.AddCurve(A, C, '-30', '60', '120', '50'))).Key;
  M := Pt('M', '50', '100');
  Check(FPattern.AddCurvePath([A, M, C], ['-45', '0', '45'], ['', '20', '30'], ['20', '30', '']));
  Check(FPattern.AddCircle(C, '10'));
  Check(FPattern.AddArc(A, '20', '0', '90'));
  Check(FPattern.AddOffsetEdge(Curve, '10', osLeft, erConstruction));
  // An offset run needs its edges worked out
  FPattern.Evaluate;
  AssertTrue(FPattern.LastError, FPattern.ChainRun([AB, BC], EdgeRun));
  Check(FPattern.AddOffsetRun(EdgeRun, '5', osRight, erConstruction));
  AssertTrue(FPattern.LastError, FPattern.SplitEdge(Diagonal, Cross, First, Second));
  N := Pt('N', '400', '0');
  Check(FPattern.AddRoundCorner(Line(Pt('O', '400', '100'), N), Line(N, Pt('U', '500', '0')), '10'));
  // Transforms, with an edge among the sources so there are edge copies
  Spec := Default(TTransformSpec);
  Spec.Sources := [E];
  Spec.Kind := tkRotate;
  Spec.Pivot := A;
  Spec.Angle := '30';
  Check(FPattern.AddTransform(Spec));
  Spec.Kind := tkMirror;
  Spec.Pivot := '';
  Spec.Angle := '';
  Spec.AxisEdge := DA;
  Check(FPattern.AddTransform(Spec));
  Spec.AxisEdge := '';
  Spec.AxisA := A;
  Spec.Angle := '90';
  Check(FPattern.AddTransform(Spec));
  Spec := Default(TTransformSpec);
  Spec.Kind := tkMove;
  Spec.Sources := [AB];
  Spec.Polar := True;
  Spec.Length := '300';
  Spec.Angle := '0';
  Spec.Pivot := A;
  Spec.Rotate := '10';
  Check(FPattern.AddTransform(Spec));
  Spec.Polar := False;
  Spec.DX := '0';
  Spec.DY := '400';
  Spec.Pivot := '';
  Spec.Rotate := '';
  Check(FPattern.AddTransform(Spec));
  // A piece with everything a piece can have
  S1 := Pt('S1', '20', '200');
  S2 := Pt('S2', '180', '200');
  Inner := Line(S1, S2, erStitch);
  Placement := Line(Pt('V1', '20', '250'), Pt('V2', '180', '250'), erPlacement);
  Mark := Pt('W', '100', '150');
  AssertTrue(FPattern.LastError, FPattern.SetMarker(Mark, pmButton));
  FPattern.Evaluate;
  AssertTrue(Reason, DetectPiecePath(FPattern, Vec2(150, 60), Path, Reason));
  Piece := TPieceObject(Check(FPattern.AddPiece('Front', Path, '10')));
  AssertTrue(FPattern.LastError, FPattern.SetEdgeAllowance(Piece, 0, '15'));
  AssertTrue(FPattern.LastError, FPattern.SetGrainPoints(Piece, S1, Mark));
  AssertTrue(FPattern.LastError, FPattern.AddPointNotch(Piece, E));
  AssertTrue(FPattern.LastError, FPattern.AddEdgeNotch(Piece, BC, '100'));
  AssertTrue(FPattern.LastError, FPattern.AddPointMarking(Piece, Mark));
  AssertTrue(FPattern.LastError, FPattern.AddStitchMarking(Piece, Inner, '4', '1'));
  AssertTrue(FPattern.LastError, FPattern.AddLineMarking(Piece, Placement));
  AssertTrue(FPattern.LastError, FPattern.SetCut(Piece, 2, True));
  AssertTrue(FPattern.LastError, FPattern.SetFoldEdge(Piece, DA));
  FPattern.SetPieceFabric(Piece, TPatternFabric(Check(FPattern.AddFabric('Lining'))));
  AssertTrue(FPattern.LastError, FPattern.SetPieceFill(Piece, '#ff0000', pfHatch));
  Side := [Default(TSeamEntry)];
  Side[0].PieceKey := Piece.Key;
  Side[0].EdgeKey := AB;
  Check(FPattern.AddSeam('', Side, Side, '0', '1'));
  // Notes: free, and hung from a point (as a callout), an edge and a piece
  Check(FPattern.AddNote('', 'Free {=B.x / 4}', naFree, '', '', '10', '20'));
  Check(FPattern.AddNote('', 'Callout', naPoint, A, '', '10', '20', 12, True, nlArrow));
  FPattern.SetNoteAlign(TNoteObject(FPattern.Objects[FPattern.ObjectCount - 1]), taCentre);
  FPattern.SetNoteBoxed(TNoteObject(FPattern.Objects[FPattern.ObjectCount - 1]), True);
  Check(FPattern.AddNote('', 'On an edge', naEdge, AB, '0.5', '0', '10'));
  Check(FPattern.AddNote('', 'On the piece', naPiece, Piece.Key, '', '0', '0'));
  FPattern.Evaluate;
end;

// Every member of Item, nested ones as list[].member and group.member, is listed
procedure CheckMembers(const Info: TOperationInfo; Item: TJSONObject; const Prefix: string; Found: TStringArray);
var
  Index, Element: integer;
  FullName: string;
  Member: TOperationMember;
  Value: TJSONData;
begin
  for Index := 0 to Item.Count - 1 do
  begin
    FullName := Prefix + Item.Names[Index];
    if not FindMember(Info, FullName, Member) then
      raise EAssertionFailedError.CreateFmt('%s: "%s" is not in the operations table', [Info.TypeName, FullName]);
    Value := Item.Items[Index];
    if Value.JSONType = jtObject then
      CheckMembers(Info, TJSONObject(Value), FullName + '.', Found)
    else if Value.JSONType = jtArray then
      for Element := 0 to Value.Count - 1 do
        if Value.Items[Element].JSONType = jtObject then
          CheckMembers(Info, TJSONObject(Value.Items[Element]), FullName + '[].', Found);
  end;
end;

function SavedObjects(Pattern: TPattern; out Root: TJSONObject): TJSONArray;
var
  Err: string;
begin
  if not ParseJSONObject(SavePatternToText(Pattern), Root, Err) then
    raise EAssertionFailedError.Create(Err);
  Result := TJSONArray(Root.Find('objects'));
end;

procedure TTestOperationInfo.TestEverySavedMemberListed;
var
  Root: TJSONObject;
  Objects: TJSONArray;
  Index: integer;
  Item: TJSONObject;
  Info: TOperationInfo;
begin
  Objects := SavedObjects(FPattern, Root);
  try
    for Index := 0 to Objects.Count - 1 do
    begin
      Item := TJSONObject(Objects[Index]);
      AssertTrue('type ' + Item.Get('type', ''), FindOperationInfo(Item.Get('type', ''), Info));
      CheckMembers(Info, Item, '', nil);
    end;
  finally
    FreeAndNil(Root);
  end;
end;

procedure TTestOperationInfo.TestEveryTypeAppears;
var
  Root: TJSONObject;
  Objects: TJSONArray;
  Info: TOperationInfo;
  Index: integer;
  Seen: boolean;
begin
  Objects := SavedObjects(FPattern, Root);
  try
    for Info in OperationInfos do
    begin
      Seen := False;
      for Index := 0 to Objects.Count - 1 do
        Seen := Seen or (TJSONObject(Objects[Index]).Get('type', '') = Info.TypeName);
      AssertTrue(Info.TypeName + ' is listed but the pattern has none', Seen);
    end;
  finally
    FreeAndNil(Root);
  end;
end;

// A formula field's name as the table lists it: node2.angle is nodes[].angle
function MemberNameOfField(const FieldName: string): string;
const
  Lists: array[0..3, 0..1] of string = (('node', 'nodes[]'), ('edge', 'path[]'), ('notch', 'notches[]'), ('marking', 'markings[]'));
var
  Dot, Index: integer;
  Head: string;
begin
  Result := FieldName;
  Dot := Pos('.', FieldName);
  if Dot = 0 then
    Exit;
  Head := Copy(FieldName, 1, Dot - 1);
  for Index := 0 to High(Lists) do
    if (Copy(Head, 1, Length(Lists[Index, 0])) = Lists[Index, 0]) and (Length(Head) > Length(Lists[Index, 0])) and
      (Head[Length(Lists[Index, 0]) + 1] in ['0'..'9']) then
      Exit(Lists[Index, 1] + Copy(FieldName, Dot, MaxInt));
end;

procedure TTestOperationInfo.TestFormulaKindsMatch;
var
  Index, FieldIndex: integer;
  Node: TDraftObject;
  Info: TOperationInfo;
  Member: TOperationMember;
  FieldName, MemberName: string;
  Kind: TFieldUnitKind;
begin
  for Index := 0 to FPattern.ObjectCount - 1 do
  begin
    Node := FPattern.Objects[Index];
    AssertTrue(PatternObjectTypeName(Node), FindOperationInfo(PatternObjectTypeName(Node), Info));
    for FieldIndex := 0 to Node.FieldCount - 1 do
    begin
      FieldName := Node.Fields[FieldIndex].Name;
      MemberName := MemberNameOfField(FieldName);
      // A note's draft values are written in its text, and its place on an edge in its anchor
      if (Node is TNoteObject) and (FieldName.StartsWith(NoteValueField) or (FieldName = NotePositionField)) then
      begin
        if FieldName = NotePositionField then
          MemberName := 'anchor.position'
        else
          Continue;
      end;
      AssertTrue(Info.TypeName + ': field ' + FieldName + ' as ' + MemberName, FindMember(Info, MemberName, Member));
      Kind := Node.FieldUnitKind(FieldName);
      case Member.Kind of
        mkLength: AssertTrue(Info.TypeName + '.' + MemberName + ' is a length', Kind = fkLength);
        mkAngle: AssertTrue(Info.TypeName + '.' + MemberName + ' is an angle', Kind = fkAngle);
        mkNumber: AssertTrue(Info.TypeName + '.' + MemberName + ' is a number', Kind = fkNumber);
        mkLengthOrRatio: AssertTrue(Info.TypeName + '.' + MemberName + ' is a length or ratio', Kind in [fkLength, fkNumber]);
        else
          Fail(Info.TypeName + '.' + MemberName + ' is a formula but not listed as one');
      end;
    end;
  end;
end;

procedure TTestOperationInfo.TestTypesAreUnique;
var
  Infos: TOperationInfoArray;
  Index, Other: integer;
begin
  Infos := OperationInfos;
  for Index := 0 to High(Infos) do
    for Other := 0 to Index - 1 do
      AssertFalse(Infos[Index].TypeName + ' twice', Infos[Index].TypeName = Infos[Other].TypeName);
end;

initialization
  RegisterTest(TTestOperationInfo);
end.
