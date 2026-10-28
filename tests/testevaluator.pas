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

// The evaluator on its own, with minimal nodes: each sums its inputs and
// can be told to fail.
unit TestEvaluator;

{$mode ObjFPC}{$H+}

interface

uses
  Classes, SysUtils, fpcunit, testregistry, osTestCase, osEvalTypes, osEvaluator;

type
  TSumNode = class(TEvalNode)
  public
    Inputs: TStringArray;
    Value: Double;
    Own: Double;
    FailWith: TEvalState;
    Computed: Integer;
    function InputKeys: TStringArray; override;
    function DisplayName: string; override;
    function Compute(Context: TEvalContext): TEvalState; override;
  end;

  TSumContext = class(TEvalContext)
  public
    Nodes: TList;
    constructor Create;
    destructor Destroy; override;
    function FindNode(const Key: string): TEvalNode; override;
    function MeasurementValue(const Key: string; out V: Double): Boolean; override;
    function VariableValue(const Id: string; out V: Double): Boolean; override;
    function PropertyValue(const ObjectId, Prop: string; out V: Double): Boolean; override;
  end;

  TTestEvaluator = class(TOSTestCase)
  private
    FContext: TSumContext;
    FEvaluator: TEvaluator;
    function Node(const Key: string; Own: Double; const Inputs: array of string): TSumNode;
    function N(const Key: string): TSumNode;
    procedure RunGraph;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestInputsComeFirst;
    procedure TestValuesFlowDownstream;
    procedure TestEachNodeComputedOnce;
    procedure TestDependents;
    procedure TestFailureBlocksDependents;
    procedure TestInvalidBlocksDependents;
    procedure TestMissingInputIsAnError;
    procedure TestCycleIsAnError;
    procedure TestReaches;
    procedure TestRerunClearsOldStates;
  end;

implementation

{ TSumNode }

function TSumNode.InputKeys: TStringArray;
begin
  Result := Inputs;
end;

function TSumNode.DisplayName: string;
begin
  Result := 'Node ' + Key;
end;

function TSumNode.Compute(Context: TEvalContext): TEvalState;
var
  K: string;
begin
  Inc(Computed);
  if FailWith <> esValid then
    Exit(Fail(FailWith, 'told to fail'));
  Value := Own;
  for K in Inputs do
    Value := Value + TSumNode(Context.FindNode(K)).Value;
  Result := esValid;
end;

{ TSumContext }

constructor TSumContext.Create;
begin
  Nodes := TList.Create;
end;

destructor TSumContext.Destroy;
var
  I: Integer;
begin
  for I := 0 to Nodes.Count - 1 do
    TObject(Nodes[I]).Free;
  Nodes.Free;
  inherited Destroy;
end;

function TSumContext.FindNode(const Key: string): TEvalNode;
var
  I: Integer;
begin
  for I := 0 to Nodes.Count - 1 do
    if TEvalNode(Nodes[I]).Key = Key then
      Exit(TEvalNode(Nodes[I]));
  Result := nil;
end;

function TSumContext.MeasurementValue(const Key: string; out V: Double): Boolean;
begin
  V := 0;
  Result := False;
end;

function TSumContext.VariableValue(const Id: string; out V: Double): Boolean;
begin
  V := 0;
  Result := False;
end;

function TSumContext.PropertyValue(const ObjectId, Prop: string; out V: Double): Boolean;
begin
  V := 0;
  Result := False;
end;

{ TTestEvaluator }

procedure TTestEvaluator.SetUp;
begin
  FContext := TSumContext.Create;
  FEvaluator := TEvaluator.Create;
end;

procedure TTestEvaluator.TearDown;
begin
  FEvaluator.Free;
  FContext.Free;
end;

function TTestEvaluator.Node(const Key: string; Own: Double;
  const Inputs: array of string): TSumNode;
var
  I: Integer;
begin
  Result := TSumNode.Create(Key);
  Result.Own := Own;
  SetLength(Result.Inputs, Length(Inputs));
  for I := 0 to High(Inputs) do
    Result.Inputs[I] := Inputs[I];
  FContext.Nodes.Add(Result);
end;

function TTestEvaluator.N(const Key: string): TSumNode;
begin
  Result := TSumNode(FContext.FindNode(Key));
end;

procedure TTestEvaluator.RunGraph;
var
  Nodes: TEvalNodeArray;
  I: Integer;
begin
  Nodes := nil;
  SetLength(Nodes, FContext.Nodes.Count);
  for I := 0 to High(Nodes) do
    Nodes[I] := TEvalNode(FContext.Nodes[I]);
  FEvaluator.Rebuild(Nodes, FContext);
  FEvaluator.Run(FContext);
end;

function IndexIn(const Nodes: TEvalNodeArray; Node: TEvalNode): Integer;
begin
  for Result := 0 to High(Nodes) do
    if Nodes[Result] = Node then
      Exit;
  Result := -1;
end;

procedure TTestEvaluator.TestInputsComeFirst;
var
  X, D: TEvalNode;
  Order: TEvalNodeArray;
begin
  // Listed in reverse dependency order
  Node('d', 1, ['c', 'b']);
  Node('c', 1, ['b']);
  Node('b', 1, ['a']);
  Node('a', 1, []);
  RunGraph;
  Order := FEvaluator.Order;
  AssertEquals('all sorted', 4, Length(Order));
  for X in Order do
    for D in X.Deps do
      AssertTrue(D.Key + ' before ' + X.Key, IndexIn(Order, D) < IndexIn(Order, X));
end;

procedure TTestEvaluator.TestValuesFlowDownstream;
begin
  Node('d', 1, ['c', 'b']);
  Node('c', 10, ['b']);
  Node('b', 100, ['a']);
  Node('a', 1000, []);
  RunGraph;
  AssertNear('b', 1100, N('b').Value);
  AssertNear('c', 1110, N('c').Value);
  AssertNear('d', 2211, N('d').Value);
  AssertTrue(N('d').State = esValid);
end;

procedure TTestEvaluator.TestEachNodeComputedOnce;
begin
  Node('a', 1, []);
  Node('b', 1, ['a']);
  Node('c', 1, ['a', 'b']);
  RunGraph;
  AssertEquals(1, N('a').Computed);
  AssertEquals(1, N('c').Computed);
end;

procedure TTestEvaluator.TestDependents;
begin
  Node('a', 1, []);
  Node('b', 1, ['a']);
  Node('c', 1, ['a']);
  RunGraph;
  AssertEquals('deps of b', 1, Length(N('b').Deps));
  AssertEquals('dependents of a', 2, Length(N('a').Dependents));
end;

procedure TTestEvaluator.TestFailureBlocksDependents;
begin
  Node('a', 1, []).FailWith := esError;
  Node('b', 1, ['a']);
  Node('c', 1, ['b']);
  Node('z', 1, []);
  RunGraph;
  AssertTrue('a', N('a').State = esError);
  AssertEquals('told to fail', N('a').Message);
  AssertTrue('b', N('b').State = esBlocked);
  AssertEquals(Format(rsEvalBlocked, ['Node a']), N('b').Message);
  AssertTrue('c', N('c').State = esBlocked);
  AssertEquals('names its own input', Format(rsEvalBlocked, ['Node b']), N('c').Message);
  AssertEquals('blocked nodes are not computed', 0, N('c').Computed);
  AssertTrue('unrelated', N('z').State = esValid);
end;

procedure TTestEvaluator.TestInvalidBlocksDependents;
begin
  Node('a', 1, []).FailWith := esInvalid;
  Node('b', 1, ['a']);
  RunGraph;
  AssertTrue(N('a').State = esInvalid);
  AssertTrue(N('b').State = esBlocked);
end;

procedure TTestEvaluator.TestMissingInputIsAnError;
begin
  Node('b', 1, ['gone']);
  Node('c', 1, ['b']);
  RunGraph;
  AssertTrue('b', N('b').State = esError);
  AssertEquals(Format(rsEvalMissing, ['gone']), N('b').Message);
  AssertTrue('c', N('c').State = esBlocked);
end;

procedure TTestEvaluator.TestCycleIsAnError;
begin
  Node('a', 1, ['b']);
  Node('b', 1, ['a']);
  Node('c', 1, ['a']);
  Node('d', 1, []);
  RunGraph;
  AssertTrue('a', N('a').State = esError);
  AssertEquals(rsEvalCycle, N('a').Message);
  AssertTrue('b', N('b').State = esError);
  AssertTrue('c reads the cycle', N('c').State = esBlocked);
  AssertEquals(Format(rsEvalBlocked, ['Node a']), N('c').Message);
  AssertTrue('d', N('d').State = esValid);
  AssertEquals('cycle left out of the order', 1, Length(FEvaluator.Order));
end;

procedure TTestEvaluator.TestReaches;
begin
  Node('a', 1, []);
  Node('b', 1, ['a']);
  Node('c', 1, ['b']);
  AssertTrue('c reads a', TEvaluator.Reaches(N('c'), N('a'), FContext));
  AssertFalse('a does not read c', TEvaluator.Reaches(N('a'), N('c'), FContext));
  AssertFalse('a does not read itself', TEvaluator.Reaches(N('a'), N('a'), FContext));
end;

procedure TTestEvaluator.TestRerunClearsOldStates;
begin
  Node('a', 1, []).FailWith := esError;
  Node('b', 1, ['a']);
  RunGraph;
  N('a').FailWith := esValid;
  RunGraph;
  AssertTrue(N('b').State = esValid);
  AssertEquals('message cleared', '', N('b').Message);
  AssertNear('b', 2, N('b').Value);
end;

initialization
  RegisterTest(TTestEvaluator);

end.
