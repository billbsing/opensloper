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

// The dependency graph and evaluator. Measurements, variables, points and
// edges are all nodes. A node's dependencies are its direct inputs plus
// everything its formulas reference; the evaluator sorts the nodes so inputs
// come first, then computes each one, recording failures as states.
// No LCL dependency.
unit Sloper.Core.Evaluator;

{$mode ObjFPC}{$H+}

interface

uses
  SysUtils, Sloper.Core.EvalTypes, Sloper.Core.Formula;

type
  TEvalNode = class;
  TEvalNodeArray = array of TEvalNode;

  // What nodes see while computing: formula values plus other nodes
  TEvalContext = class(TFormulaContext)
  public
    // Node by key: an object or variable ID, or '@key' for a measurement
    function FindNode(const Key: string): TEvalNode; virtual; abstract;
  end;

  TFormulaField = record
    Name: string;
    Formula: TFormula;
  end;

  TEvalNode = class
  private
    FKey: string;
    FState: TEvalState;
    FMessage: string;
    FDeps: TEvalNodeArray;
    FDependents: TEvalNodeArray;
    FMissingKey: string;
    FIndex: integer;  // position in the evaluator's node list
    FFields: array of TFormulaField;
    function GetFieldCount: integer;
    function GetField(Index: integer): TFormulaField;
  protected
    procedure AddField(const AName: string);
    // Evaluates a field; on failure sets Message and returns False
    function EvalField(Context: TEvalContext; const AName: string; out Value: double): boolean;
    // Sets Message and returns AState, for use as "Exit(Fail(esInvalid, ...))"
    function Fail(AState: TEvalState; const Msg: string): TEvalState;
  public
    constructor Create(const AKey: string);
    destructor Destroy; override;
    // Keys of nodes read directly, besides those in formulas
    function InputKeys: TStringArray; virtual;
    // Inputs plus every node the formulas reference, without repeats
    function DependencyKeys: TStringArray;
    function DisplayName: string; virtual; abstract;
    // Computes the result. Called only when every dependency is valid. On
    // failure returns esError or esInvalid with Message set, keeping the last
    // good result.
    function Compute(Context: TEvalContext): TEvalState; virtual; abstract;
    function Field(const AName: string): TFormula;
    // Swaps in a new formula for the field, freeing the old one
    procedure ReplaceField(const AName: string; Formula: TFormula);
    property Key: string read FKey;
    property State: TEvalState read FState;
    property Message: string read FMessage;
    property Deps: TEvalNodeArray read FDeps;
    property Dependents: TEvalNodeArray read FDependents;
    property FieldCount: integer read GetFieldCount;
    property Fields[Index: integer]: TFormulaField read GetField;
  end;

  TEvaluator = class
  private
    FNodes: TEvalNodeArray;
    FOrder: TEvalNodeArray;
  public
    // Resolves dependencies, fills in dependents and sorts the nodes
    procedure Rebuild(const Nodes: TEvalNodeArray; Context: TEvalContext);
    // Computes every node in order
    procedure Run(Context: TEvalContext);
    // True when From reads Target, directly or through other nodes. Follows
    // current definitions, so it can be used before Rebuild.
    class function Reaches(From, Target: TEvalNode; Context: TEvalContext): boolean;
    // Sorted nodes; nodes in a cycle are left out
    property Order: TEvalNodeArray read FOrder;
  end;

function ReferenceKey(const Ref: TFormulaReference): string;

resourcestring
  rsEvalBlocked = 'Blocked by %s';
  rsEvalMissing = 'Uses %s, which no longer exists';
  rsEvalCycle = 'Part of a circular reference';

implementation

uses
  Generics.Collections;

type
  TEvalNodeSet = specialize THashSet<TEvalNode>;

function ReferenceKey(const Ref: TFormulaReference): string;
begin
  if Ref.Kind = rkMeasurement then
    Result := '@' + Ref.Id
  else
    Result := Ref.Id;
end;

procedure AddUnique(var Keys: TStringArray; const Key: string);
var
  Existing: string;
begin
  for Existing in Keys do
    if Existing = Key then
      Exit;
  SetLength(Keys, Length(Keys) + 1);
  Keys[High(Keys)] := Key;
end;

procedure AddNode(var Nodes: TEvalNodeArray; Node: TEvalNode);
begin
  SetLength(Nodes, Length(Nodes) + 1);
  Nodes[High(Nodes)] := Node;
end;

{ TEvalNode }

constructor TEvalNode.Create(const AKey: string);
begin
  FKey := AKey;
  FState := esDirty;
end;

destructor TEvalNode.Destroy;
var
  Index: integer;
begin
  for Index := 0 to High(FFields) do
    FreeAndNil(FFields[Index].Formula);
  inherited Destroy;
end;

function TEvalNode.GetFieldCount: integer;
begin
  Result := Length(FFields);
end;

function TEvalNode.GetField(Index: integer): TFormulaField;
begin
  Result := FFields[Index];
end;

procedure TEvalNode.AddField(const AName: string);
var
  Count: integer;
begin
  Count := Length(FFields);
  SetLength(FFields, Count + 1);
  FFields[Count].Name := AName;
  FFields[Count].Formula := TFormula.Create;
end;

function TEvalNode.Field(const AName: string): TFormula;
var
  Entry: TFormulaField;
begin
  for Entry in FFields do
    if SameText(Entry.Name, AName) then
      Exit(Entry.Formula);
  Result := nil;
end;

procedure TEvalNode.ReplaceField(const AName: string; Formula: TFormula);
var
  Index: integer;
begin
  for Index := 0 to High(FFields) do
    if SameText(FFields[Index].Name, AName) then
    begin
      FreeAndNil(FFields[Index].Formula);
      FFields[Index].Formula := Formula;
      Exit;
    end;
  raise EArgumentException.CreateFmt('No formula field "%s"', [AName]);
end;

function TEvalNode.EvalField(Context: TEvalContext; const AName: string;
  out Value: double): boolean;
var
  FieldFormula: TFormula;
begin
  FieldFormula := Field(AName);
  Result := FieldFormula.Evaluate(Context, Value);
  if not Result then
    if Length(FFields) > 1 then
      FMessage := AName + ': ' + FieldFormula.ErrorMessage
    else
      FMessage := FieldFormula.ErrorMessage;
end;

function TEvalNode.Fail(AState: TEvalState; const Msg: string): TEvalState;
begin
  FMessage := Msg;
  Result := AState;
end;

function TEvalNode.InputKeys: TStringArray;
begin
  Result := nil;
end;

function TEvalNode.DependencyKeys: TStringArray;
var
  InputKey: string;
  Entry: TFormulaField;
  Ref: TFormulaReference;
begin
  Result := nil;
  for InputKey in InputKeys do
    AddUnique(Result, InputKey);
  for Entry in FFields do
    for Ref in Entry.Formula.References do
      AddUnique(Result, ReferenceKey(Ref));
end;

{ TEvaluator }

procedure TEvaluator.Rebuild(const Nodes: TEvalNodeArray; Context: TEvalContext);
var
  Node, Dep: TEvalNode;
  DepKey: string;
  Waiting: array of integer;
  Queue: TEvalNodeArray;
  Index, Head: integer;
begin
  FNodes := Copy(Nodes);
  for Index := 0 to High(FNodes) do
  begin
    FNodes[Index].FIndex := Index;
    FNodes[Index].FDeps := nil;
    FNodes[Index].FDependents := nil;
    FNodes[Index].FMissingKey := '';
  end;
  for Node in FNodes do
    for DepKey in Node.DependencyKeys do
    begin
      Dep := Context.FindNode(DepKey);
      if Dep = nil then
      begin
        if Node.FMissingKey = '' then
          Node.FMissingKey := DepKey;
      end
      else
      begin
        AddNode(Node.FDeps, Dep);
        AddNode(Dep.FDependents, Node);
      end;
    end;

  // Kahn's algorithm, in list order where there is a choice
  Waiting := nil;
  SetLength(Waiting, Length(FNodes));
  Queue := nil;
  for Index := 0 to High(FNodes) do
  begin
    FNodes[Index].FState := esDirty;
    Waiting[Index] := Length(FNodes[Index].FDeps);
    if Waiting[Index] = 0 then
      AddNode(Queue, FNodes[Index]);
  end;
  Head := 0;
  while Head < Length(Queue) do
  begin
    Node := Queue[Head];
    Inc(Head);
    for Dep in Node.FDependents do
    begin
      Dec(Waiting[Dep.FIndex]);
      if Waiting[Dep.FIndex] = 0 then
        AddNode(Queue, Dep);
    end;
  end;
  FOrder := Queue;
end;

procedure TEvaluator.Run(Context: TEvalContext);
var
  Node, Dep, BlockedBy: TEvalNode;
begin
  for Node in FNodes do
    Node.FState := esDirty;
  for Node in FOrder do
  begin
    if Node.FMissingKey <> '' then
    begin
      Node.FState := esError;
      Node.FMessage := Format(rsEvalMissing, [Node.FMissingKey]);
      Continue;
    end;
    BlockedBy := nil;
    for Dep in Node.FDeps do
      if Dep.FState <> esValid then
      begin
        BlockedBy := Dep;
        Break;
      end;
    if BlockedBy <> nil then
    begin
      Node.FState := esBlocked;
      Node.FMessage := Format(rsEvalBlocked, [BlockedBy.DisplayName]);
    end
    else
    begin
      Node.FMessage := '';
      Node.FState := Node.Compute(Context);
      if Node.FState = esValid then
        Node.FMessage := '';
    end;
  end;

  // Nodes never reached are in a cycle or read one (only from loaded files)
  for Node in FNodes do
    if Node.FState = esDirty then
    begin
      Node.FState := esError;
      Node.FMessage := rsEvalCycle;
    end;
  for Node in FNodes do
    if (Node.FState = esError) and (Node.FMessage = rsEvalCycle) and not Reaches(Node, Node, Context) then
    begin
      Node.FState := esBlocked;
      for Dep in Node.FDeps do
        if Dep.FState <> esValid then
        begin
          Node.FMessage := Format(rsEvalBlocked, [Dep.DisplayName]);
          Break;
        end;
    end;
end;

class function TEvaluator.Reaches(From, Target: TEvalNode; Context: TEvalContext): boolean;
var
  Visited: TEvalNodeSet;

  function Visit(Current: TEvalNode): boolean;
  var
    DepKey: string;
    Dep: TEvalNode;
  begin
    for DepKey in Current.DependencyKeys do
    begin
      Dep := Context.FindNode(DepKey);
      if Dep = nil then
        Continue;
      if Dep = Target then
        Exit(True);
      // Add is False when Dep was already visited
      if Visited.Add(Dep) and Visit(Dep) then
        Exit(True);
    end;
    Result := False;
  end;

begin
  Visited := TEvalNodeSet.Create;
  try
    Result := Visit(From);
  finally
    FreeAndNil(Visited);
  end;
end;

end.
