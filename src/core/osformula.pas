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

// Formulas: parsing, references, evaluation and name/ID conversion.
//
// Users type names (Line_A_B.length + #ease_waist + @waist / 4). Parse
// resolves them and keeps the stored ID form ({l1}.length + {v1} + @waist / 4),
// which survives renames. DisplayText turns IDs back into current names.
// Measurements are referred to by their stable key in both forms.
//
// Syntax: numbers, + - * / ^ (right-associative, binds tighter than unary
// minus), brackets, and the functions sin cos tan asin acos atan2 sqrt abs
// min max round. Angles are in degrees. Failures are reported through
// ErrorMessage and ErrorPos, never as exceptions. No LCL dependency.
unit osFormula;

{$mode ObjFPC}{$H+}

interface

uses
  osFormulaLexer;

type
  TReferenceKind = (rkMeasurement, rkVariable, rkObject);

  // Something a formula reads. Id is the measurement key, variable ID or
  // object ID; Prop is the object property, in lower case.
  TFormulaReference = record
    Kind: TReferenceKind;
    Id: string;
    Prop: string;
  end;

  TFormulaReferenceArray = array of TFormulaReference;

  // Maps names to IDs and back, for the pattern being edited
  TNameResolver = class
  public
    function ResolveMeasurement(const Name: string; out Key: string): Boolean; virtual; abstract;
    function ResolveVariable(const Name: string; out Id: string): Boolean; virtual; abstract;
    function ResolveObject(const Name: string; out Id: string): Boolean; virtual; abstract;
    // Prop is valid for the object; CanonicalProp is its stored spelling
    function ResolveProperty(const ObjectId, Prop: string; out CanonicalProp: string): Boolean; virtual; abstract;
    function VariableName(const Id: string; out Name: string): Boolean; virtual; abstract;
    function ObjectName(const Id: string; out Name: string): Boolean; virtual; abstract;
  end;

  // Supplies values when a formula is evaluated
  TFormulaContext = class
  public
    function MeasurementValue(const Key: string; out Value: Double): Boolean; virtual; abstract;
    function VariableValue(const Id: string; out Value: Double): Boolean; virtual; abstract;
    function PropertyValue(const ObjectId, Prop: string; out Value: Double): Boolean; virtual; abstract;
  end;

  TFormulaNode = class;

  TFormula = class
  private
    FStoredText: string;
    FTokens: TFormulaTokenArray;   // positions refer to FStoredText
    FTokenRefs: array of Integer;  // reference index per token, or -1
    FReferences: TFormulaReferenceArray;
    FRoot: TFormulaNode;
    FValid: Boolean;
    FErrorMessage: string;
    FErrorPos: Integer;
    FErrorToken: Integer;
    procedure Clear;
    function DoParse(const Text: string; Form: TFormulaTextForm; Resolver: TNameResolver): Boolean;
    function BuildDisplay(Resolver: TNameResolver; out TokenPos: TFormulaTokenArray): string;
    procedure SetError(const Msg: string; Pos, Token: Integer);
  public
    destructor Destroy; override;
    // Parses what the user typed. On failure the formula is invalid, keeps
    // Text as typed and sets ErrorMessage and ErrorPos (in Text).
    function Parse(const Text: string; Resolver: TNameResolver): Boolean;
    // Parses the stored ID form, as read from a file
    function ParseStored(const Text: string): Boolean;
    function Evaluate(Context: TFormulaContext; out Value: Double): Boolean;
    function DisplayText(Resolver: TNameResolver): string;
    // ErrorPos converted to a position in DisplayText
    function DisplayErrorPos(Resolver: TNameResolver): Integer;
    // A plain number, optionally negative: can be changed by dragging
    function IsLiteral: Boolean;
    property StoredText: string read FStoredText;
    property References: TFormulaReferenceArray read FReferences;
    property Valid: Boolean read FValid;
    property ErrorMessage: string read FErrorMessage;
    // 1-based position of the problem, or 0 when it concerns the whole formula
    property ErrorPos: Integer read FErrorPos;
  end;

  TFormulaNode = class
  public
    Token: Integer;  // token index, for error positions
    function Eval(Formula: TFormula; Context: TFormulaContext): Double; virtual; abstract;
  end;

resourcestring
  rsFormulaEmpty = 'The formula is empty';
  rsFormulaUnknownName = 'Unknown name "%s"';
  rsFormulaUnknownMeasurement = 'Unknown measurement "@%s"';
  rsFormulaUnknownVariable = 'Unknown variable "#%s"';
  rsFormulaMissingHash = 'Unknown name "%s"; for the variable write "#%s"';
  rsFormulaNeedsProperty = '"%s" needs a property, such as "%s.x" or "%s.length"';
  rsFormulaUnknownProperty = '"%s" has no property "%s"';
  rsFormulaNamesNotIds = 'Expected an ID such as {p1}, not a name';
  rsFormulaExpectedBracket = 'Expected "(" after %s';
  rsFormulaExpectedValue = 'Expected a number, a name or "("';
  rsFormulaExpectedClose = 'Expected ")"';
  rsFormulaUnexpected = 'Unexpected "%s"';
  rsFormulaEndsTooSoon = 'The formula ends too soon';
  rsFormulaArgCount = '%s() takes %d value(s)';
  rsFormulaArgCountAtLeast = '%s() takes at least %d values';
  rsFormulaNoValue = 'No value for %s';
  rsFormulaDivideByZero = 'Division by zero';
  rsFormulaSqrtNegative = 'Square root of a negative number';
  rsFormulaOutOfDomain = '%s() needs a value from -1 to 1';
  rsFormulaNotANumber = 'The result is not a valid number';

implementation

uses
  SysUtils, Math, osNames;

type
  TFormulaFunction = (ffSin, ffCos, ffTan, ffAsin, ffAcos, ffAtan2, ffSqrt,
    ffAbs, ffMin, ffMax, ffRound);

const
  FunctionNames: array[TFormulaFunction] of string = ('sin', 'cos', 'tan',
    'asin', 'acos', 'atan2', 'sqrt', 'abs', 'min', 'max', 'round');
  // Minimum and maximum number of arguments; -1 means no maximum
  FunctionMinArgs: array[TFormulaFunction] of Integer = (1, 1, 1, 1, 1, 2, 1, 1, 2, 2, 1);
  FunctionMaxArgs: array[TFormulaFunction] of Integer = (1, 1, 1, 1, 1, 2, 1, 1, -1, -1, 1);

type
  // Raised inside evaluation and parsing only; TFormula turns it into an error state
  EFormulaError = class(Exception)
  public
    Token: Integer;
    constructor Create(const Msg: string; AToken: Integer);
  end;

  TNumberNode = class(TFormulaNode)
  public
    Value: Double;
    function Eval(Formula: TFormula; Context: TFormulaContext): Double; override;
  end;

  TReferenceNode = class(TFormulaNode)
  public
    Index: Integer;
    function Eval(Formula: TFormula; Context: TFormulaContext): Double; override;
  end;

  TNegateNode = class(TFormulaNode)
  public
    Operand: TFormulaNode;
    destructor Destroy; override;
    function Eval(Formula: TFormula; Context: TFormulaContext): Double; override;
  end;

  TBinaryNode = class(TFormulaNode)
  public
    Op: Char;
    Left, Right: TFormulaNode;
    destructor Destroy; override;
    function Eval(Formula: TFormula; Context: TFormulaContext): Double; override;
  end;

  TFunctionNode = class(TFormulaNode)
  public
    Func: TFormulaFunction;
    Args: array of TFormulaNode;
    destructor Destroy; override;
    function Eval(Formula: TFormula; Context: TFormulaContext): Double; override;
  end;

  // Recursive descent over the token list:
  //   expr    := term (('+' | '-') term)*
  //   term    := unary (('*' | '/') unary)*
  //   unary   := ('-' | '+') unary | power
  //   power   := primary ('^' unary)?
  //   primary := number | reference | function '(' expr (',' expr)* ')' | '(' expr ')'
  TFormulaParser = class
  private
    FText: string;
    FTokens: TFormulaTokenArray;
    FTokenRefs: array of Integer;
    FPos: Integer;
    function AtOp(AOp: Char): Boolean;
    function ParseExpr: TFormulaNode;
    function ParseTerm: TFormulaNode;
    function ParseUnary: TFormulaNode;
    function ParsePower: TFormulaNode;
    function ParsePrimary: TFormulaNode;
    function ParseFunction: TFormulaNode;
    procedure Error(const Msg: string);
  public
    function Parse(const Text: string; const Tokens: TFormulaTokenArray;
      const TokenRefs: array of Integer): TFormulaNode;
  end;

function FindFunction(const Name: string; out Func: TFormulaFunction): Boolean;
var
  Candidate: TFormulaFunction;
begin
  for Candidate := Low(Candidate) to High(Candidate) do
    if SameText(FunctionNames[Candidate], Name) then
    begin
      Func := Candidate;
      Exit(True);
    end;
  Result := False;
end;

function ReferenceStoredText(const Ref: TFormulaReference): string;
begin
  case Ref.Kind of
    rkMeasurement: Result := '@' + Ref.Id;
    rkVariable: Result := '{' + Ref.Id + '}';
    rkObject: Result := '{' + Ref.Id + '}.' + Ref.Prop;
  end;
end;

function SameReference(const First, Second: TFormulaReference): Boolean;
begin
  Result := (First.Kind = Second.Kind) and SameText(First.Id, Second.Id) and SameText(First.Prop, Second.Prop);
end;

{ EFormulaError }

constructor EFormulaError.Create(const Msg: string; AToken: Integer);
begin
  inherited Create(Msg);
  Token := AToken;
end;

{ Nodes }

function TNumberNode.Eval(Formula: TFormula; Context: TFormulaContext): Double;
begin
  Result := Value;
end;

function TReferenceNode.Eval(Formula: TFormula; Context: TFormulaContext): Double;
var
  Ref: TFormulaReference;
  Ok: Boolean;
begin
  Ok := False;
  Ref := Formula.FReferences[Index];
  case Ref.Kind of
    rkMeasurement: Ok := Context.MeasurementValue(Ref.Id, Result);
    rkVariable: Ok := Context.VariableValue(Ref.Id, Result);
    rkObject: Ok := Context.PropertyValue(Ref.Id, Ref.Prop, Result);
  end;
  if not Ok then
    raise EFormulaError.Create(Format(rsFormulaNoValue, [ReferenceStoredText(Ref)]), Token);
end;

destructor TNegateNode.Destroy;
begin
  Operand.Free;
  inherited Destroy;
end;

function TNegateNode.Eval(Formula: TFormula; Context: TFormulaContext): Double;
begin
  Result := -Operand.Eval(Formula, Context);
end;

destructor TBinaryNode.Destroy;
begin
  Left.Free;
  Right.Free;
  inherited Destroy;
end;

function TBinaryNode.Eval(Formula: TFormula; Context: TFormulaContext): Double;
var
  LeftValue, RightValue: Double;
begin
  LeftValue := Left.Eval(Formula, Context);
  RightValue := Right.Eval(Formula, Context);
  case Op of
    '+': Result := LeftValue + RightValue;
    '-': Result := LeftValue - RightValue;
    '*': Result := LeftValue * RightValue;
    '/':
      begin
        if RightValue = 0 then
          raise EFormulaError.Create(rsFormulaDivideByZero, Token);
        Result := LeftValue / RightValue;
      end;
    '^': Result := Power(LeftValue, RightValue);
  end;
end;

destructor TFunctionNode.Destroy;
var
  Arg: TFormulaNode;
begin
  for Arg in Args do
    Arg.Free;
  inherited Destroy;
end;

function TFunctionNode.Eval(Formula: TFormula; Context: TFormulaContext): Double;
var
  Values: array of Double;
  Index: Integer;
begin
  Values := nil;
  SetLength(Values, Length(Args));
  for Index := 0 to High(Args) do
    Values[Index] := Args[Index].Eval(Formula, Context);
  case Func of
    ffSin: Result := Sin(DegToRad(Values[0]));
    ffCos: Result := Cos(DegToRad(Values[0]));
    ffTan: Result := Tan(DegToRad(Values[0]));
    ffAsin, ffAcos:
      begin
        if (Values[0] < -1) or (Values[0] > 1) then
          raise EFormulaError.Create(Format(rsFormulaOutOfDomain, [FunctionNames[Func]]), Token);
        if Func = ffAsin then
          Result := RadToDeg(ArcSin(Values[0]))
        else
          Result := RadToDeg(ArcCos(Values[0]));
      end;
    ffAtan2: Result := RadToDeg(ArcTan2(Values[0], Values[1]));
    ffSqrt:
      begin
        if Values[0] < 0 then
          raise EFormulaError.Create(rsFormulaSqrtNegative, Token);
        Result := Sqrt(Values[0]);
      end;
    ffAbs: Result := Abs(Values[0]);
    ffMin:
      begin
        Result := Values[0];
        for Index := 1 to High(Values) do
          Result := Min(Result, Values[Index]);
      end;
    ffMax:
      begin
        Result := Values[0];
        for Index := 1 to High(Values) do
          Result := Max(Result, Values[Index]);
      end;
    // Half away from zero, as people expect; Pascal's Round rounds half to even
    ffRound: Result := Sign(Values[0]) * Floor(Abs(Values[0]) + 0.5);
  end;
end;

{ TFormulaParser }

procedure TFormulaParser.Error(const Msg: string);
begin
  raise EFormulaError.Create(Msg, FPos);
end;

function TFormulaParser.AtOp(AOp: Char): Boolean;
begin
  Result := (FPos <= High(FTokens)) and (FTokens[FPos].Kind = ftOperator)
    and (FTokens[FPos].Op = AOp);
end;

function TFormulaParser.Parse(const Text: string; const Tokens: TFormulaTokenArray;
  const TokenRefs: array of Integer): TFormulaNode;
var
  Index: Integer;
begin
  FText := Text;
  FTokens := Tokens;
  FTokenRefs := nil;
  SetLength(FTokenRefs, Length(TokenRefs));
  for Index := 0 to High(TokenRefs) do
    FTokenRefs[Index] := TokenRefs[Index];
  FPos := 0;
  Result := ParseExpr;
  if FPos <= High(FTokens) then
  begin
    Result.Free;
    Error(Format(rsFormulaUnexpected, [Copy(FText, FTokens[FPos].Pos, FTokens[FPos].Len)]));
  end;
end;

function TFormulaParser.ParseExpr: TFormulaNode;
var
  Node: TBinaryNode;
begin
  Result := ParseTerm;
  while AtOp('+') or AtOp('-') do
  begin
    Node := TBinaryNode.Create;
    Node.Token := FPos;
    Node.Op := FTokens[FPos].Op;
    Node.Left := Result;
    Result := Node;
    Inc(FPos);
    try
      Node.Right := ParseTerm;
    except
      Result.Free;
      raise;
    end;
  end;
end;

function TFormulaParser.ParseTerm: TFormulaNode;
var
  Node: TBinaryNode;
begin
  Result := ParseUnary;
  while AtOp('*') or AtOp('/') do
  begin
    Node := TBinaryNode.Create;
    Node.Token := FPos;
    Node.Op := FTokens[FPos].Op;
    Node.Left := Result;
    Result := Node;
    Inc(FPos);
    try
      Node.Right := ParseUnary;
    except
      Result.Free;
      raise;
    end;
  end;
end;

function TFormulaParser.ParseUnary: TFormulaNode;
var
  Node: TNegateNode;
begin
  // In ObjFPC mode a bare ParseUnary here is the result variable; the
  // brackets make it a recursive call
  if AtOp('+') then
  begin
    Inc(FPos);
    Exit(ParseUnary());
  end;
  if AtOp('-') then
  begin
    Node := TNegateNode.Create;
    Node.Token := FPos;
    Inc(FPos);
    try
      Node.Operand := ParseUnary();
    except
      Node.Free;
      raise;
    end;
    Exit(Node);
  end;
  Result := ParsePower;
end;

function TFormulaParser.ParsePower: TFormulaNode;
var
  Node: TBinaryNode;
begin
  Result := ParsePrimary;
  if AtOp('^') then
  begin
    Node := TBinaryNode.Create;
    Node.Token := FPos;
    Node.Op := '^';
    Node.Left := Result;
    Result := Node;
    Inc(FPos);
    // The exponent may carry its own sign: 2^-1
    try
      Node.Right := ParseUnary;
    except
      Result.Free;
      raise;
    end;
  end;
end;

function TFormulaParser.ParsePrimary: TFormulaNode;
var
  Tok: TFormulaToken;
begin
  if FPos > High(FTokens) then
    Error(rsFormulaEndsTooSoon);
  Tok := FTokens[FPos];
  case Tok.Kind of
    ftNumber:
      begin
        Result := TNumberNode.Create;
        Result.Token := FPos;
        TNumberNode(Result).Value := Tok.Value;
        Inc(FPos);
      end;
    ftMeasurement, ftVariable, ftObjectRef, ftIdRef:
      begin
        Result := TReferenceNode.Create;
        Result.Token := FPos;
        TReferenceNode(Result).Index := FTokenRefs[FPos];
        Inc(FPos);
      end;
    ftName:
      Result := ParseFunction;
    ftOperator:
      if Tok.Op = '(' then
      begin
        Inc(FPos);
        Result := ParseExpr;
        if not AtOp(')') then
        begin
          Result.Free;
          Error(rsFormulaExpectedClose);
        end;
        Inc(FPos);
      end
      else
        Error(rsFormulaExpectedValue);
  else
    Error(rsFormulaExpectedValue);
  end;
end;

function TFormulaParser.ParseFunction: TFormulaNode;
var
  Node: TFunctionNode;
  Func: TFormulaFunction;
  NameToken, ArgCount: Integer;
begin
  // Names were checked by TFormula, so this is a known function
  FindFunction(FTokens[FPos].Name, Func);
  NameToken := FPos;
  Node := TFunctionNode.Create;
  Node.Token := NameToken;
  Node.Func := Func;
  try
    Inc(FPos);
    if not AtOp('(') then
      Error(Format(rsFormulaExpectedBracket, [FunctionNames[Func]]));
    Inc(FPos);
    repeat
      ArgCount := Length(Node.Args);
      SetLength(Node.Args, ArgCount + 1);
      Node.Args[ArgCount] := nil;
      Node.Args[ArgCount] := ParseExpr;
      if not AtOp(',') then
        Break;
      Inc(FPos);
    until False;
    if not AtOp(')') then
      Error(rsFormulaExpectedClose);
    Inc(FPos);
    ArgCount := Length(Node.Args);
    if (ArgCount < FunctionMinArgs[Func])
      or ((FunctionMaxArgs[Func] >= 0) and (ArgCount > FunctionMaxArgs[Func])) then
    begin
      FPos := NameToken;
      if FunctionMaxArgs[Func] < 0 then
        Error(Format(rsFormulaArgCountAtLeast, [FunctionNames[Func], FunctionMinArgs[Func]]))
      else
        Error(Format(rsFormulaArgCount, [FunctionNames[Func], FunctionMinArgs[Func]]));
    end;
  except
    Node.Free;
    raise;
  end;
  Result := Node;
end;

{ TFormula }

destructor TFormula.Destroy;
begin
  Clear;
  inherited Destroy;
end;

procedure TFormula.Clear;
begin
  FreeAndNil(FRoot);
  FTokens := nil;
  FTokenRefs := nil;
  FReferences := nil;
  FValid := False;
  FErrorMessage := '';
  FErrorPos := 0;
  FErrorToken := -1;
end;

procedure TFormula.SetError(const Msg: string; Pos, Token: Integer);
begin
  FErrorMessage := Msg;
  FErrorPos := Pos;
  FErrorToken := Token;
end;

function TFormula.Parse(const Text: string; Resolver: TNameResolver): Boolean;
begin
  Result := DoParse(Text, ffDisplay, Resolver);
end;

function TFormula.ParseStored(const Text: string): Boolean;
begin
  Result := DoParse(Text, ffStored, nil);
end;

function TFormula.DoParse(const Text: string; Form: TFormulaTextForm;
  Resolver: TNameResolver): Boolean;
var
  Tokens: TFormulaTokenArray;
  Msg, Key, Id, Prop, Name, Stored: string;
  ErrPos, TokenIndex, StoredPos, Last: Integer;
  Ref: TFormulaReference;
  Func: TFormulaFunction;
  Parser: TFormulaParser;

  function Fail(const AMsg: string; APos: Integer): Boolean;
  begin
    SetError(AMsg, APos, -1);
    FStoredText := Text;
    Result := False;
  end;

  function AddReference(const NewRef: TFormulaReference): Integer;
  var
    ExistingIndex: Integer;
  begin
    for ExistingIndex := 0 to High(FReferences) do
      if SameReference(FReferences[ExistingIndex], NewRef) then
        Exit(ExistingIndex);
    Result := Length(FReferences);
    SetLength(FReferences, Result + 1);
    FReferences[Result] := NewRef;
  end;

begin
  Clear;
  if Trim(Text) = '' then
    Exit(Fail(rsFormulaEmpty, 1));
  if not TokenizeFormula(Text, Form, Tokens, Msg, ErrPos) then
    Exit(Fail(Msg, ErrPos));

  // Resolve names and collect references
  SetLength(FTokenRefs, Length(Tokens));
  for TokenIndex := 0 to High(Tokens) do
  begin
    FTokenRefs[TokenIndex] := -1;
    Ref := Default(TFormulaReference);
    case Tokens[TokenIndex].Kind of
      ftMeasurement:
        begin
          Ref.Kind := rkMeasurement;
          if Form = ffStored then
            Ref.Id := Tokens[TokenIndex].Name
          else if Resolver.ResolveMeasurement(Tokens[TokenIndex].Name, Key) then
            Ref.Id := Key
          else
            Exit(Fail(Format(rsFormulaUnknownMeasurement, [Tokens[TokenIndex].Name]), Tokens[TokenIndex].Pos));
          FTokenRefs[TokenIndex] := AddReference(Ref);
        end;
      ftVariable:
        begin
          if not Resolver.ResolveVariable(Tokens[TokenIndex].Name, Id) then
            Exit(Fail(Format(rsFormulaUnknownVariable, [Tokens[TokenIndex].Name]), Tokens[TokenIndex].Pos));
          Ref.Kind := rkVariable;
          Ref.Id := Id;
          FTokenRefs[TokenIndex] := AddReference(Ref);
        end;
      ftObjectRef:
        begin
          if Form = ffStored then
            Exit(Fail(rsFormulaNamesNotIds, Tokens[TokenIndex].Pos));
          if not Resolver.ResolveObject(Tokens[TokenIndex].Name, Id) then
            Exit(Fail(Format(rsFormulaUnknownName, [Tokens[TokenIndex].Name]), Tokens[TokenIndex].Pos));
          if not Resolver.ResolveProperty(Id, Tokens[TokenIndex].Prop, Prop) then
            Exit(Fail(Format(rsFormulaUnknownProperty, [Tokens[TokenIndex].Name, Tokens[TokenIndex].Prop]),
              Tokens[TokenIndex].Pos + Length(Tokens[TokenIndex].Name) + 1));
          Ref.Kind := rkObject;
          Ref.Id := Id;
          Ref.Prop := Prop;
          FTokenRefs[TokenIndex] := AddReference(Ref);
        end;
      ftIdRef:
        begin
          if Tokens[TokenIndex].Prop = '' then
            Ref.Kind := rkVariable
          else
            Ref.Kind := rkObject;
          Ref.Id := Tokens[TokenIndex].Name;
          Ref.Prop := LowerCase(Tokens[TokenIndex].Prop);
          FTokenRefs[TokenIndex] := AddReference(Ref);
        end;
      ftName:
        if not FindFunction(Tokens[TokenIndex].Name, Func) then
        begin
          Name := Tokens[TokenIndex].Name;
          if Form = ffStored then
            Exit(Fail(rsFormulaNamesNotIds, Tokens[TokenIndex].Pos));
          if Resolver.ResolveObject(Name, Id) then
            Exit(Fail(Format(rsFormulaNeedsProperty, [Name, Name, Name]), Tokens[TokenIndex].Pos));
          if Resolver.ResolveVariable(Name, Id) then
            Exit(Fail(Format(rsFormulaMissingHash, [Name, Name]), Tokens[TokenIndex].Pos));
          Exit(Fail(Format(rsFormulaUnknownName, [Name]), Tokens[TokenIndex].Pos));
        end;
    end;
  end;

  // Parse into an expression tree
  Parser := TFormulaParser.Create;
  try
    try
      FRoot := Parser.Parse(Text, Tokens, FTokenRefs);
    except
      on ParseError: EFormulaError do
      begin
        if ParseError.Token <= High(Tokens) then
          ErrPos := Tokens[ParseError.Token].Pos
        else
          ErrPos := Length(TrimRight(Text)) + 1; // ran out of tokens
        Msg := ParseError.Message;
        FReferences := nil;
        FTokenRefs := nil;
        Exit(Fail(Msg, ErrPos));
      end;
    end;
  finally
    Parser.Free;
  end;

  // Build the stored form, keeping the user's spacing and number spelling
  Stored := '';
  Last := 1;
  for TokenIndex := 0 to High(Tokens) do
  begin
    Stored := Stored + Copy(Text, Last, Tokens[TokenIndex].Pos - Last);
    StoredPos := Length(Stored) + 1;
    if FTokenRefs[TokenIndex] >= 0 then
      Stored := Stored + ReferenceStoredText(FReferences[FTokenRefs[TokenIndex]])
    else
      Stored := Stored + Copy(Text, Tokens[TokenIndex].Pos, Tokens[TokenIndex].Len);
    Last := Tokens[TokenIndex].Pos + Tokens[TokenIndex].Len;
    Tokens[TokenIndex].Len := Length(Stored) + 1 - StoredPos;
    Tokens[TokenIndex].Pos := StoredPos;
  end;
  Stored := Stored + Copy(Text, Last, MaxInt);

  FStoredText := Stored;
  FTokens := Tokens;
  FValid := True;
  Result := True;
end;

function TFormula.Evaluate(Context: TFormulaContext; out Value: Double): Boolean;
var
  SavedMask: TFPUExceptionMask;
begin
  Value := 0;
  if not FValid then
  begin
    if FErrorMessage = '' then
      SetError(rsFormulaEmpty, 1, -1);
    Exit(False);
  end;
  FErrorMessage := '';
  FErrorPos := 0;
  FErrorToken := -1;
  // With FPU exceptions masked, overflow and invalid operations give
  // infinity or NaN, caught below. Unmasked, x87 exceptions (used by Power)
  // can be raised later, outside this method.
  SavedMask := GetExceptionMask;
  SetExceptionMask(SavedMask + [exInvalidOp, exDenormalized, exZeroDivide,
    exOverflow, exUnderflow, exPrecision]);
  try
    try
      Value := FRoot.Eval(Self, Context);
      if IsNan(Value) or IsInfinite(Value) then
      begin
        Value := 0;
        SetError(rsFormulaNotANumber, 0, -1);
        Exit(False);
      end;
      Result := True;
    except
      on Failure: EFormulaError do
      begin
        Value := 0;
        SetError(Failure.Message, FTokens[Failure.Token].Pos, Failure.Token);
        Result := False;
      end;
      on Failure: EMathError do
      begin
        Value := 0;
        SetError(rsFormulaNotANumber, 0, -1);
        Result := False;
      end;
    end;
  finally
    ClearExceptions(False);
    SetExceptionMask(SavedMask);
  end;
end;

function TFormula.BuildDisplay(Resolver: TNameResolver;
  out TokenPos: TFormulaTokenArray): string;
var
  TokenIndex, Last: Integer;
  Ref: TFormulaReference;
  Name, Piece: string;
begin
  TokenPos := Copy(FTokens);
  if not FValid then
    Exit(FStoredText);
  Result := '';
  Last := 1;
  for TokenIndex := 0 to High(FTokens) do
  begin
    Result := Result + Copy(FStoredText, Last, FTokens[TokenIndex].Pos - Last);
    TokenPos[TokenIndex].Pos := Length(Result) + 1;
    if FTokenRefs[TokenIndex] >= 0 then
    begin
      Ref := FReferences[FTokenRefs[TokenIndex]];
      case Ref.Kind of
        rkMeasurement: Piece := '@' + Ref.Id;
        // An ID with no current name (deleted object) stays in ID form
        rkVariable:
          if Resolver.VariableName(Ref.Id, Name) then
            Piece := '#' + Name
          else
            Piece := ReferenceStoredText(Ref);
        rkObject:
          if Resolver.ObjectName(Ref.Id, Name) then
            Piece := Name + '.' + Ref.Prop
          else
            Piece := ReferenceStoredText(Ref);
      end;
    end
    else
      Piece := Copy(FStoredText, FTokens[TokenIndex].Pos, FTokens[TokenIndex].Len);
    Result := Result + Piece;
    TokenPos[TokenIndex].Len := Length(Piece);
    Last := FTokens[TokenIndex].Pos + FTokens[TokenIndex].Len;
  end;
  Result := Result + Copy(FStoredText, Last, MaxInt);
end;

function TFormula.DisplayText(Resolver: TNameResolver): string;
var
  TokenPos: TFormulaTokenArray;
begin
  Result := BuildDisplay(Resolver, TokenPos);
end;

function TFormula.DisplayErrorPos(Resolver: TNameResolver): Integer;
var
  TokenPos: TFormulaTokenArray;
begin
  if not FValid or (FErrorToken < 0) then
    Exit(FErrorPos);
  BuildDisplay(Resolver, TokenPos);
  Result := TokenPos[FErrorToken].Pos;
end;

function TFormula.IsLiteral: Boolean;
begin
  Result := FValid and ((FRoot is TNumberNode)
    or ((FRoot is TNegateNode) and (TNegateNode(FRoot).Operand is TNumberNode)));
end;

end.
