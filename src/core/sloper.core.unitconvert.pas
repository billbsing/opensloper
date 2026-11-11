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

// Converting a pattern to another unit (Tools > Convert Pattern Units). Only
// lengths are rewritten, so each plain number's role is worked out from where
// it sits. A role is a power of length: 0 for a count, ratio or angle, 1 for a
// length, 2 for an area. Each plain number and each variable is an unknown
// power; the formula tree gives linear equations between them (the operands
// of + - min max are equal, * adds powers and / subtracts them, sqrt halves,
// the arguments of sin cos tan are 0), and the field fixes the result: a
// length is 1, an angle or a count 0. Solving says which numbers are settled.
// A number left open, or caught in equations that disagree (a variable used
// both as a length and a count), is undecided, and the user marks it as a
// length or a number. Suffixed numbers (400mm) keep their unit and are never
// rewritten. No LCL dependency.
unit Sloper.Core.UnitConvert;

{$mode ObjFPC}{$H+}

interface

uses
  SysUtils, Generics.Collections, Sloper.Core.Units, Sloper.Core.Pattern;

type
  // A plain number in a formula, and its role
  TUnitNumber = record
    NodeKey, FieldName: string;
    // Its token in the field's formula
    Token: integer;
    // As written
    Value: double;
    // Settled by the formulas or by a mark
    Decided: boolean;
    Marked: boolean;
    // When decided, its power of length: 0 a plain number, 1 a length
    Power: double;
  end;
  TUnitNumberArray = array of TUnitNumber;

  // The user's word on an undecided number
  TUnitMark = record
    NodeKey, FieldName: string;
    Token: integer;
    IsLength: boolean;
  end;
  TUnitMarkArray = array of TUnitMark;

  TUnitAnalysis = record
    Numbers: TUnitNumberArray;
    // Fields whose formula has an error, as "node key, field": they are left as they are
    Skipped: TStringArray;
  end;

  TMember = specialize TList<integer>;
  TMembers = specialize TObjectDictionary<integer, TMember>;

  TPowersDict = specialize TDictionary<string, double>;

// Every plain number in the pattern's formulas, with its role where the
// formulas or Marks settle it
function AnalyseUnits(Pattern: TPattern; const Marks: TUnitMarkArray): TUnitAnalysis;
function UndecidedCount(const Numbers: TUnitNumberArray): integer;
function MarkFor(const Number: TUnitNumber; IsLength: boolean): TUnitMark;
// Value, a number of the given power in FromUnits, in ToUnits: lengths rounded
// to the new unit's drag precision, other powers to six places, and a small
// non-zero value kept to two significant figures rather than rounded to 0
function ConvertedNumber(Value, LengthPower: double; FromUnits, ToUnits: TMeasureUnit): double;
// Rewrites every number whose power is not 0, converts material allowances and
// sets the pattern's unit. Every number must be decided. Call inside a
// document change, and evaluate afterwards. On failure the pattern may be
// partly changed, so the change is to be cancelled.
function ConvertPatternUnits(Pattern: TPattern; ToUnits: TMeasureUnit; const Numbers: TUnitNumberArray; out ErrorMessage: string): boolean;

resourcestring
  rsConvertUndecided = '%d numbers still need to be marked as a length or a number';
  rsConvertSameUnit = 'The pattern is already in %s';

implementation

uses
  Math, Sloper.Core.Evaluator, Sloper.Core.Formula, Sloper.Core.FormulaLexer, Sloper.Core.Draft,
  Sloper.Core.Materials, Sloper.Core.Variables;

const
  TOLERANCE = 1e-9;

type
  TTerm = record
    Unknown: integer;
    Coef: double;
  end;

  // Constant + the sum of Coef * unknown; as a constraint, it equals 0
  TAffine = record
    Constant: double;
    Terms: array of TTerm;
  end;
  TAffineArray = array of TAffine;

  TUnknownMap = specialize TDictionary<string, integer>;

  TSolution = record
    Values: array of double;
    Determined: array of boolean;
  end;

function Constant(Value: double): TAffine;
begin
  Result := Default(TAffine);
  Result.Constant := Value;
end;

function Unknown(Index: integer): TAffine;
begin
  Result := Default(TAffine);
  SetLength(Result.Terms, 1);
  Result.Terms[0].Unknown := Index;
  Result.Terms[0].Coef := 1;
end;

function Scaled(const Expression: TAffine; Factor: double): TAffine;
var
  Index: integer;
begin
  Result := Default(TAffine);
  Result.Constant := Expression.Constant * Factor;
  SetLength(Result.Terms, Length(Expression.Terms));
  for Index := 0 to High(Expression.Terms) do
  begin
    Result.Terms[Index].Unknown := Expression.Terms[Index].Unknown;
    Result.Terms[Index].Coef := Expression.Terms[Index].Coef * Factor;
  end;
end;

function Sum(const First, Second: TAffine): TAffine;
var
  Index: integer;
begin
  Result := Default(TAffine);
  Result.Constant := First.Constant + Second.Constant;
  Result.Terms := Copy(First.Terms);
  for Index := 0 to High(Second.Terms) do
    Insert(Second.Terms[Index], Result.Terms, Length(Result.Terms));
end;

function Difference(const First, Second: TAffine): TAffine;
begin
  Result := Sum(First, Scaled(Second, -1));
end;

function NumberKey(const NodeKey, FieldName: string; Token: integer): string;
begin
  Result := NodeKey + #1 + FieldName + #1 + IntToStr(Token);
end;

{ Solving }

function FindRoot(var Parents: array of integer; Index: integer): integer;
begin
  Result := Index;
  while Parents[Result] <> Result do
    Result := Parents[Result];
  // Shorten the path for next time
  while Parents[Index] <> Result do
  begin
    Index := Parents[Index];
    Parents[Index] := Result;
  end;
end;

// Gauss-Jordan elimination on each group of unknowns linked by constraints.
// An unknown is determined when its group is consistent and its row has
// nothing left in the free columns. Unknowns in no constraint stay open.
function Solve(const Constraints: TAffineArray; UnknownCount: integer): TSolution;
var
  Parents, Column, Columns, PivotRow: array of integer;
  Groups, Members: TMembers;
  Group, Member: TMember;
  Matrix: array of array of double;
  Index, Term, Root, Row, Col, Rank, Best, Other, Width: integer;
  Pivot, Factor, Swap: double;
  Consistent, Clean: boolean;
  Pair: specialize TPair<integer, specialize TList<integer>>;
begin
  Result := Default(TSolution);
  SetLength(Result.Values, UnknownCount);
  SetLength(Result.Determined, UnknownCount);
  Parents := nil;
  SetLength(Parents, UnknownCount);
  for Index := 0 to UnknownCount - 1 do
    Parents[Index] := Index;
  for Index := 0 to High(Constraints) do
    for Term := 1 to High(Constraints[Index].Terms) do
      Parents[FindRoot(Parents, Constraints[Index].Terms[Term].Unknown)] := FindRoot(Parents, Constraints[Index].Terms[0].Unknown);
  Groups := TMembers.Create([doOwnsValues]);
  Members := TMembers.Create([doOwnsValues]);
  try
    for Index := 0 to UnknownCount - 1 do
    begin
      Root := FindRoot(Parents, Index);
      if not Members.TryGetValue(Root, Member) then
      begin
        Member := TMember.Create;
        Members.Add(Root, Member);
      end;
      Member.Add(Index);
    end;
    // The constraints of each group, by index
    for Index := 0 to High(Constraints) do
      if Length(Constraints[Index].Terms) > 0 then
      begin
        Root := FindRoot(Parents, Constraints[Index].Terms[0].Unknown);
        if not Groups.TryGetValue(Root, Group) then
        begin
          Group := TMember.Create;
          Groups.Add(Root, Group);
        end;
        Group.Add(Index);
      end;
    Column := nil;
    SetLength(Column, UnknownCount);
    for Pair in Groups do
    begin
      Group := Pair.Value;
      // Number the group's unknowns as columns
      Columns := nil;
      for Index in Members[Pair.Key] do
      begin
        Column[Index] := Length(Columns);
        Insert(Index, Columns, Length(Columns));
      end;
      Width := Length(Columns);
      // One row per constraint; the last column holds the constant
      Matrix := nil;
      SetLength(Matrix, Group.Count, Width + 1);
      for Row := 0 to Group.Count - 1 do
      begin
        for Term := 0 to High(Constraints[Group[Row]].Terms) do
        begin
          Col := Column[Constraints[Group[Row]].Terms[Term].Unknown];
          Matrix[Row][Col] := Matrix[Row][Col] + Constraints[Group[Row]].Terms[Term].Coef;
        end;
        Matrix[Row][Width] := Constraints[Group[Row]].Constant;
      end;
      PivotRow := nil;
      SetLength(PivotRow, Width);
      for Col := 0 to Width - 1 do
        PivotRow[Col] := -1;
      Rank := 0;
      for Col := 0 to Width - 1 do
      begin
        if Rank >= Group.Count then
          Break;
        Best := Rank;
        for Row := Rank + 1 to Group.Count - 1 do
          if Abs(Matrix[Row][Col]) > Abs(Matrix[Best][Col]) then
            Best := Row;
        if Abs(Matrix[Best][Col]) < TOLERANCE then
          Continue;
        for Other := 0 to Width do
        begin
          Swap := Matrix[Rank][Other];
          Matrix[Rank][Other] := Matrix[Best][Other];
          Matrix[Best][Other] := Swap;
        end;
        Pivot := Matrix[Rank][Col];
        for Other := 0 to Width do
          Matrix[Rank][Other] := Matrix[Rank][Other] / Pivot;
        for Row := 0 to Group.Count - 1 do
          if (Row <> Rank) and (Abs(Matrix[Row][Col]) >= TOLERANCE) then
          begin
            Factor := Matrix[Row][Col];
            for Other := 0 to Width do
              Matrix[Row][Other] := Matrix[Row][Other] - Factor * Matrix[Rank][Other];
          end;
        PivotRow[Col] := Rank;
        Inc(Rank);
      end;
      // A row of zeros with a constant left means the equations disagree
      Consistent := True;
      for Row := Rank to Group.Count - 1 do
        if Abs(Matrix[Row][Width]) >= TOLERANCE then
          Consistent := False;
      if not Consistent then
        Continue;
      for Col := 0 to Width - 1 do
      begin
        Row := PivotRow[Col];
        if Row < 0 then
          Continue;
        Clean := True;
        for Other := 0 to Width - 1 do
          if (Other <> Col) and (Abs(Matrix[Row][Other]) >= TOLERANCE) then
            Clean := False;
        if Clean then
        begin
          Result.Values[Columns[Col]] := -Matrix[Row][Width];
          Result.Determined[Columns[Col]] := True;
        end;
      end;
    end;
  finally
    FreeAndNil(Members);
    FreeAndNil(Groups);
  end;
end;

{ Building the equations }

type
  TBuilder = class
  private
    FPattern: TPattern;
    FConstraints: TAffineArray;
    FUnknownCount: integer;
    FVariables: TUnknownMap;
    // The number each unknown stands for, or -1 for a variable's, and back
    FNumberOf, FUnknownOf: array of integer;
    // Numbers that multiply or divide something read from the pattern, which
    // are taken as plain numbers when nothing else settles them
    FFactors: array of integer;
    function NewUnknown(NumberIndex: integer): integer;
    function VariableUnknown(const Key: string): integer;
    procedure AddConstraint(const Expression: TAffine);
    function HasReference(const Shape: TFormulaShape; Index: integer): boolean;
    function BareNumber(const Shape: TFormulaShape; Index: integer; out Value: double): boolean;
    function Build(Node: TEvalNode; const FieldName: string; Formula: TFormula; const Shape: TFormulaShape; Index: integer): TAffine;
    procedure AddField(Node: TEvalNode; const FieldName: string; Formula: TFormula);
  public
    Numbers: TUnitNumberArray;
    Skipped: TStringArray;
    constructor Create(APattern: TPattern);
    destructor Destroy; override;
    procedure AddPattern;
    function Analyse(const Marks: TUnitMarkArray): TUnitNumberArray;
  end;

constructor TBuilder.Create(APattern: TPattern);
begin
  FPattern := APattern;
  FVariables := TUnknownMap.Create;
end;

destructor TBuilder.Destroy;
begin
  FreeAndNil(FVariables);
  inherited Destroy;
end;

function TBuilder.NewUnknown(NumberIndex: integer): integer;
begin
  Result := FUnknownCount;
  Inc(FUnknownCount);
  Insert(NumberIndex, FNumberOf, Length(FNumberOf));
end;

function TBuilder.VariableUnknown(const Key: string): integer;
begin
  if not FVariables.TryGetValue(Key, Result) then
  begin
    Result := NewUnknown(-1);
    FVariables.Add(Key, Result);
  end;
end;

procedure TBuilder.AddConstraint(const Expression: TAffine);
begin
  Insert(Expression, FConstraints, Length(FConstraints));
end;

function TBuilder.HasReference(const Shape: TFormulaShape; Index: integer): boolean;
var
  Child: integer;
begin
  if Shape[Index].Kind = fsReference then
    Exit(True);
  for Child in Shape[Index].Children do
    if HasReference(Shape, Child) then
      Exit(True);
  Result := False;
end;

// A plain number, or its negative, as an exponent or a factor
function TBuilder.BareNumber(const Shape: TFormulaShape; Index: integer; out Value: double): boolean;
begin
  Value := 0;
  if (Shape[Index].Kind = fsNegate) and BareNumber(Shape, Shape[Index].Children[0], Value) then
  begin
    Value := -Value;
    Exit(True);
  end;
  Result := (Shape[Index].Kind = fsNumber) and (Shape[Index].Suffix = nsNone);
  if Result then
    Value := Shape[Index].Value;
end;

function TBuilder.Build(Node: TEvalNode; const FieldName: string; Formula: TFormula; const Shape: TFormulaShape; Index: integer): TAffine;
var
  Item: TFormulaShapeNode;
  Ref: TFormulaReference;
  Number: TUnitNumber;
  Parts: array of TAffine;
  Child, Side: integer;
  Exponent: double;
begin
  Item := Shape[Index];
  Parts := nil;
  for Child in Item.Children do
    Insert(Build(Node, FieldName, Formula, Shape, Child), Parts, Length(Parts));
  case Item.Kind of
    fsNumber:
      if Item.Suffix <> nsNone then
        Result := Constant(1)
      else
      begin
        Number := Default(TUnitNumber);
        Number.NodeKey := Node.Key;
        Number.FieldName := FieldName;
        Number.Token := Item.Token;
        Number.Value := Item.Value;
        Insert(Number, Numbers, Length(Numbers));
        Result := Unknown(NewUnknown(High(Numbers)));
        Insert(Result.Terms[0].Unknown, FUnknownOf, Length(FUnknownOf));
      end;
    fsReference:
    begin
      Ref := Formula.References[Item.Reference];
      case Ref.Kind of
        rkMeasurement: Result := Constant(1);
        rkVariable: Result := Unknown(VariableUnknown(Ref.Id));
        else
          if IsLengthProperty(Ref.Prop) then
            Result := Constant(1)
          else
            Result := Constant(0);
      end;
    end;
    fsNegate:
      Result := Parts[0];
    fsAdd, fsSubtract:
    begin
      AddConstraint(Difference(Parts[0], Parts[1]));
      Result := Parts[0];
    end;
    fsMultiply, fsDivide:
    begin
      for Side := 0 to 1 do
        if BareNumber(Shape, Item.Children[Side], Exponent) and HasReference(Shape, Item.Children[1 - Side]) then
          Insert(Parts[Side].Terms[0].Unknown, FFactors, Length(FFactors));
      if Item.Kind = fsMultiply then
        Result := Sum(Parts[0], Parts[1])
      else
        Result := Difference(Parts[0], Parts[1]);
    end;
    fsPower:
    begin
      // The exponent is a plain number; a written one scales the power
      AddConstraint(Parts[1]);
      if BareNumber(Shape, Item.Children[1], Exponent) then
        Result := Scaled(Parts[0], Exponent)
      else
      begin
        AddConstraint(Parts[0]);
        Result := Constant(0);
      end;
    end;
    else
      case Item.FunctionName of
        'sin', 'cos', 'tan', 'asin', 'acos':
        begin
          AddConstraint(Parts[0]);
          Result := Constant(0);
        end;
        'atan2':
        begin
          AddConstraint(Difference(Parts[0], Parts[1]));
          Result := Constant(0);
        end;
        'sqrt':
          Result := Scaled(Parts[0], 0.5);
        else
        begin
          // abs, round, min, max: the arguments and the result are alike
          for Side := 1 to High(Parts) do
            AddConstraint(Difference(Parts[0], Parts[Side]));
          Result := Parts[0];
        end;
      end;
  end;
end;

procedure TBuilder.AddField(Node: TEvalNode; const FieldName: string; Formula: TFormula);
var
  Shape: TFormulaShape;
  Root: TAffine;
begin
  Shape := Formula.Shape;
  if Length(Shape) = 0 then
  begin
    Insert(Node.Key + ', ' + FieldName, Skipped, Length(Skipped));
    Exit;
  end;
  Root := Build(Node, FieldName, Formula, Shape, 0);
  case Node.FieldUnitKind(FieldName) of
    fkLength: AddConstraint(Difference(Root, Constant(1)));
    fkAngle, fkNumber: AddConstraint(Root);
    else
      if Node is TVariable then
        AddConstraint(Difference(Root, Unknown(VariableUnknown(Node.Key))));
  end;
end;

procedure TBuilder.AddPattern;
var
  Index, FieldIndex: integer;
  Node: TEvalNode;
begin
  for Index := 0 to FPattern.VariableCount + FPattern.ObjectCount - 1 do
  begin
    if Index < FPattern.VariableCount then
      Node := FPattern.Variables[Index]
    else
      Node := FPattern.Objects[Index - FPattern.VariableCount];
    for FieldIndex := 0 to Node.FieldCount - 1 do
      AddField(Node, Node.Fields[FieldIndex].Name, Node.Fields[FieldIndex].Formula);
  end;
end;

function TBuilder.Analyse(const Marks: TUnitMarkArray): TUnitNumberArray;
var
  MarkPowers: TPowersDict;
  Constraints: TAffineArray;
  Solution: TSolution;
  Unknown_, Index, Factor: integer;
  MarkPower: double;

  function Fixed(UnknownIndex: integer; Value: double): TAffine;
  begin
    Result := Difference(Unknown(UnknownIndex), Constant(Value));
  end;

  // True when the unknown can take Value: the equations still agree, and no
  // plain number is left with a negative power, which nobody writes
  function Fits(UnknownIndex: integer; Value: double): boolean;
  var
    Trial: TAffineArray;
    Tried: TSolution;
    Other: integer;
  begin
    Trial := Copy(Constraints);
    Insert(Fixed(UnknownIndex, Value), Trial, Length(Trial));
    Tried := Solve(Trial, FUnknownCount);
    if not Tried.Determined[UnknownIndex] then
      Exit(False);
    for Other := 0 to FUnknownCount - 1 do
      if (FNumberOf[Other] >= 0) and Tried.Determined[Other] and (Tried.Values[Other] < -TOLERANCE) then
        Exit(False);
    Result := True;
  end;

  procedure Settle(UnknownIndex: integer; Value: double);
  begin
    Insert(Fixed(UnknownIndex, Value), Constraints, Length(Constraints));
    Solution := Solve(Constraints, FUnknownCount);
  end;

begin
  Result := Copy(Numbers);
  MarkPowers := TPowersDict.Create;
  try
    for Index := 0 to High(Marks) do
      MarkPowers.AddOrSetValue(NumberKey(Marks[Index].NodeKey, Marks[Index].FieldName, Marks[Index].Token),
        IfThen(Marks[Index].IsLength, 1, 0));
    Constraints := Copy(FConstraints);
    for Unknown_ := 0 to FUnknownCount - 1 do
      if (FNumberOf[Unknown_] >= 0) and MarkPowers.TryGetValue(NumberKey(Numbers[FNumberOf[Unknown_]].NodeKey,
        Numbers[FNumberOf[Unknown_]].FieldName, Numbers[FNumberOf[Unknown_]].Token), MarkPower) then
      begin
        Result[FNumberOf[Unknown_]].Marked := True;
        Insert(Fixed(Unknown_, MarkPower), Constraints, Length(Constraints));
      end;
    Solution := Solve(Constraints, FUnknownCount);
    // A number with only one role that leaves no power negative takes it:
    // in an angle, 2 * 10 is two plain numbers, while in a length 400 * 2
    // could be either way round
    for Index := 0 to High(Numbers) do
    begin
      Unknown_ := FUnknownOf[Index];
      if not Solution.Determined[Unknown_] and not Result[Index].Marked and (Fits(Unknown_, 0) <> Fits(Unknown_, 1)) then
        Settle(Unknown_, IfThen(Fits(Unknown_, 0), 0, 1));
    end;
    // A factor of something read from the pattern that is still open is
    // taken as a plain number, if that fits: @waist / 4 in a note's value
    for Factor in FFactors do
      if not Solution.Determined[Factor] and not Result[FNumberOf[Factor]].Marked and Fits(Factor, 0) then
        Settle(Factor, 0);
    for Index := 0 to High(Result) do
    begin
      Unknown_ := FUnknownOf[Index];
      if Result[Index].Marked then
      begin
        Result[Index].Decided := True;
        MarkPowers.TryGetValue(NumberKey(Result[Index].NodeKey, Result[Index].FieldName, Result[Index].Token), MarkPower);
        Result[Index].Power := MarkPower;
      end
      else if Solution.Determined[Unknown_] then
      begin
        Result[Index].Decided := True;
        // Powers are whole or halves; clear rounding noise
        Result[Index].Power := Round(Solution.Values[Unknown_] * 2) / 2;
      end;
    end;
  finally
    FreeAndNil(MarkPowers);
  end;
end;

{ Public }

function AnalyseUnits(Pattern: TPattern; const Marks: TUnitMarkArray): TUnitAnalysis;
var
  Builder: TBuilder;
begin
  Builder := TBuilder.Create(Pattern);
  try
    Builder.AddPattern;
    Result.Numbers := Builder.Analyse(Marks);
    Result.Skipped := Builder.Skipped;
  finally
    FreeAndNil(Builder);
  end;
end;

function UndecidedCount(const Numbers: TUnitNumberArray): integer;
var
  Number: TUnitNumber;
begin
  Result := 0;
  for Number in Numbers do
    if not Number.Decided then
      Inc(Result);
end;

function MarkFor(const Number: TUnitNumber; IsLength: boolean): TUnitMark;
begin
  Result.NodeKey := Number.NodeKey;
  Result.FieldName := Number.FieldName;
  Result.Token := Number.Token;
  Result.IsLength := IsLength;
end;

function RoundToPlaces(Value: double; Decimals: integer): double;
var
  Scale: double;
begin
  Scale := IntPower(10, Decimals);
  Result := Round(Value * Scale) / Scale;
end;

function ConvertedNumber(Value, LengthPower: double; FromUnits, ToUnits: TMeasureUnit): double;
var
  Decimals: integer;
begin
  Result := Value * Power(MILLIMETRES_PER_UNIT[FromUnits] / MILLIMETRES_PER_UNIT[ToUnits], LengthPower);
  if SameValue(LengthPower, 1) then
    Decimals := DRAG_UNIT_DECIMALS[ToUnits]
  else
    Decimals := 6;
  if (RoundToPlaces(Result, Decimals) = 0) and (Result <> 0) then
    // Two significant figures
    Decimals := 1 - Floor(Log10(Abs(Result)));
  Result := RoundToPlaces(Result, Decimals);
end;

// As formula text, without an exponent the lexer would have to read
function NumberText(Value: double): string;
var
  Settings: TFormatSettings;
begin
  Settings := DefaultFormatSettings;
  Settings.DecimalSeparator := '.';
  Result := FormatFloat('0.############', Value, Settings);
end;

function ConvertPatternUnits(Pattern: TPattern; ToUnits: TMeasureUnit; const Numbers: TUnitNumberArray; out ErrorMessage: string): boolean;
var
  FromUnits: TMeasureUnit;
  Index, Last, First, TokenPos, TokenLen: integer;
  Node: TEvalNode;
  Formula: TFormula;
  Text: string;
  Material: TPatternMaterial;
begin
  ErrorMessage := '';
  FromUnits := Pattern.Units;
  if FromUnits = ToUnits then
  begin
    ErrorMessage := Format(rsConvertSameUnit, [MEASURE_UNIT_NAMES[ToUnits]]);
    Exit(False);
  end;
  if UndecidedCount(Numbers) > 0 then
  begin
    ErrorMessage := Format(rsConvertUndecided, [UndecidedCount(Numbers)]);
    Exit(False);
  end;
  // A field's numbers are together and in token order: rewrite each field
  // from its last number back, so earlier positions still hold
  First := 0;
  while First <= High(Numbers) do
  begin
    Last := First;
    while (Last < High(Numbers)) and (Numbers[Last + 1].NodeKey = Numbers[First].NodeKey) and
      (Numbers[Last + 1].FieldName = Numbers[First].FieldName) do
      Inc(Last);
    Node := Pattern.FindNode(Numbers[First].NodeKey);
    Formula := Node.Field(Numbers[First].FieldName);
    Text := Formula.StoredText;
    // AnalyseUnits lists a field's numbers in token order
    for Index := Last downto First do
      if (Numbers[Index].Power <> 0) and Formula.StoredTokenSpan(Numbers[Index].Token, TokenPos, TokenLen) then
      begin
        Delete(Text, TokenPos, TokenLen);
        Insert(NumberText(ConvertedNumber(Numbers[Index].Value, Numbers[Index].Power, FromUnits, ToUnits)), Text, TokenPos);
      end;
    if (Text <> Formula.StoredText) and not Pattern.SetStoredFormula(Node, Numbers[First].FieldName, Text) then
    begin
      ErrorMessage := Pattern.LastError;
      Exit(False);
    end;
    First := Last + 1;
  end;
  for Index := 0 to Pattern.MaterialCount - 1 do
  begin
    Material := Pattern.Materials[Index];
    if Material.HasAllowance then
      Material.Allowance := ConvertedNumber(Material.Allowance, 1, FromUnits, ToUnits);
  end;
  Pattern.Units := ToUnits;
  Result := True;
end;

end.
