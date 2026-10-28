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

// Pattern variables (increments): named values such as #ease_waist that hold
// design decisions. Each has a stable ID (v1, v2, ...) used in stored
// formulas, so renaming never breaks a formula. Variable formulas may use
// measurements and other variables. No LCL dependency.
unit osVariables;

{$mode ObjFPC}{$H+}

interface

uses
  Classes, SysUtils, fpjson, osEvalTypes, osFormula, osMeasurements;

type
  TVariable = class
  private
    FId: string;
    FName: string;
    FFormula: TFormula;
    FValue: Double;
    FState: TEvalState;
    FMessage: string;
  public
    Description: string;
    constructor Create;
    destructor Destroy; override;
    property Id: string read FId;
    property Name: string read FName;
    property Formula: TFormula read FFormula;
    // Last good value; kept while the variable is failing
    property Value: Double read FValue;
    property State: TEvalState read FState;
    property Message: string read FMessage;
  end;

  TVariableArray = array of TVariable;

  TVariableList = class
  private
    FItems: TList;
    FNextId: Integer;
    FMeasurements: TMeasurementSet;
    FResolver: TNameResolver;
    FContext: TFormulaContext;
    FLastError: string;
    FLastErrorPos: Integer;
    function GetCount: Integer;
    function GetItem(Index: Integer): TVariable;
    function VariableDeps(V: TVariable): TVariableArray;
    function DependsOn(V, Target: TVariable): Boolean;
    function SetError(const Msg: string; Pos: Integer = 0): Boolean;
    function CheckCycles(V: TVariable; Formula: TFormula): Boolean;
  public
    constructor Create;
    destructor Destroy; override;
    procedure Clear;
    function FindById(const Id: string): TVariable;
    // Names are compared without regard to case
    function FindByName(const Name: string): TVariable;
    function CheckName(const Name: string; Exclude: TVariable; out ErrorMessage: string): Boolean;
    // The editing functions return nil or False when the change is refused,
    // with the reason in LastError (and LastErrorPos for formula errors)
    function Add(const Name, FormulaText: string; const Description: string = ''): TVariable;
    function SetFormula(V: TVariable; const FormulaText: string): Boolean;
    function Rename(V: TVariable; const NewName: string): Boolean;
    // Refused while other variables use V
    function Delete(V: TVariable): Boolean;
    function UsersOf(V: TVariable): TVariableArray;
    // The formula as the user sees it, with current names
    function FormulaText(V: TVariable): string;
    // Computes every variable in dependency order
    procedure Evaluate;
    function SaveToJSON: TJSONArray;
    // Fails on a malformed list; a formula that does not parse is kept as
    // text and shows as an error when evaluated
    function LoadFromJSON(Data: TJSONData; out ErrorMessage: string): Boolean;
    property Count: Integer read GetCount;
    property Items[Index: Integer]: TVariable read GetItem; default;
    // Not owned. Can be nil or swapped for another person's set.
    property Measurements: TMeasurementSet read FMeasurements write FMeasurements;
    // Name lookup for formulas: measurements and variables
    property Resolver: TNameResolver read FResolver;
    property Context: TFormulaContext read FContext;
    property LastError: string read FLastError;
    property LastErrorPos: Integer read FLastErrorPos;
  end;

resourcestring
  rsVariableUsesItself = 'Circular reference: #%s cannot use itself';
  rsVariableCycle = 'Circular reference: #%s cannot use #%s, because #%s already uses #%s';
  rsVariableInUse = '#%s is used by %s';
  rsVariableBlocked = 'Uses #%s, which has a problem';
  rsVariableInCycle = 'Part of a circular reference';
  rsVariableList = 'The variable list is not valid';
  rsVariableBadId = 'A variable has a missing or repeated ID';
  rsVariableBadName = 'Variable name: %s';
  rsVariableNoFormula = 'Variable "%s" has no formula';

implementation

uses
  osNames, osJSON;

type
  TVariableResolver = class(TNameResolver)
  private
    FList: TVariableList;
  public
    constructor Create(AList: TVariableList);
    function ResolveMeasurement(const Name: string; out Key: string): Boolean; override;
    function ResolveVariable(const Name: string; out Id: string): Boolean; override;
    function ResolveObject(const Name: string; out Id: string): Boolean; override;
    function ResolveProperty(const ObjectId, Prop: string; out CanonicalProp: string): Boolean; override;
    function VariableName(const Id: string; out Name: string): Boolean; override;
    function ObjectName(const Id: string; out Name: string): Boolean; override;
  end;

  TVariableContext = class(TFormulaContext)
  private
    FList: TVariableList;
  public
    constructor Create(AList: TVariableList);
    function MeasurementValue(const Key: string; out Value: Double): Boolean; override;
    function VariableValue(const Id: string; out Value: Double): Boolean; override;
    function PropertyValue(const ObjectId, Prop: string; out Value: Double): Boolean; override;
  end;

{ TVariable }

constructor TVariable.Create;
begin
  FFormula := TFormula.Create;
  FState := esDirty;
end;

destructor TVariable.Destroy;
begin
  FFormula.Free;
  inherited Destroy;
end;

{ TVariableResolver }

constructor TVariableResolver.Create(AList: TVariableList);
begin
  FList := AList;
end;

function TVariableResolver.ResolveMeasurement(const Name: string; out Key: string): Boolean;
var
  M: TMeasurement;
begin
  Key := '';
  if FList.Measurements = nil then
    Exit(False);
  M := FList.Measurements.Find(Name);
  Result := M <> nil;
  if Result then
    Key := M.Key;
end;

function TVariableResolver.ResolveVariable(const Name: string; out Id: string): Boolean;
var
  V: TVariable;
begin
  V := FList.FindByName(Name);
  Result := V <> nil;
  if Result then
    Id := V.Id
  else
    Id := '';
end;

function TVariableResolver.ResolveObject(const Name: string; out Id: string): Boolean;
begin
  Id := '';
  Result := False;
end;

function TVariableResolver.ResolveProperty(const ObjectId, Prop: string;
  out CanonicalProp: string): Boolean;
begin
  CanonicalProp := '';
  Result := False;
end;

function TVariableResolver.VariableName(const Id: string; out Name: string): Boolean;
var
  V: TVariable;
begin
  V := FList.FindById(Id);
  Result := V <> nil;
  if Result then
    Name := V.Name
  else
    Name := '';
end;

function TVariableResolver.ObjectName(const Id: string; out Name: string): Boolean;
begin
  Name := '';
  Result := False;
end;

{ TVariableContext }

constructor TVariableContext.Create(AList: TVariableList);
begin
  FList := AList;
end;

function TVariableContext.MeasurementValue(const Key: string; out Value: Double): Boolean;
begin
  Value := 0;
  Result := (FList.Measurements <> nil) and FList.Measurements.TryGetValue(Key, Value);
end;

function TVariableContext.VariableValue(const Id: string; out Value: Double): Boolean;
var
  V: TVariable;
begin
  Value := 0;
  V := FList.FindById(Id);
  Result := (V <> nil) and (V.State = esValid);
  if Result then
    Value := V.Value;
end;

function TVariableContext.PropertyValue(const ObjectId, Prop: string; out Value: Double): Boolean;
begin
  Value := 0;
  Result := False;
end;

{ TVariableList }

constructor TVariableList.Create;
begin
  FItems := TList.Create;
  FNextId := 1;
  FResolver := TVariableResolver.Create(Self);
  FContext := TVariableContext.Create(Self);
end;

destructor TVariableList.Destroy;
begin
  Clear;
  FItems.Free;
  FResolver.Free;
  FContext.Free;
  inherited Destroy;
end;

procedure TVariableList.Clear;
var
  I: Integer;
begin
  for I := 0 to FItems.Count - 1 do
    TVariable(FItems[I]).Free;
  FItems.Clear;
  FNextId := 1;
end;

function TVariableList.GetCount: Integer;
begin
  Result := FItems.Count;
end;

function TVariableList.GetItem(Index: Integer): TVariable;
begin
  Result := TVariable(FItems[Index]);
end;

function TVariableList.SetError(const Msg: string; Pos: Integer): Boolean;
begin
  FLastError := Msg;
  FLastErrorPos := Pos;
  Result := False;
end;

function TVariableList.FindById(const Id: string): TVariable;
var
  I: Integer;
begin
  for I := 0 to Count - 1 do
    if Items[I].Id = Id then
      Exit(Items[I]);
  Result := nil;
end;

function TVariableList.FindByName(const Name: string): TVariable;
var
  I: Integer;
begin
  for I := 0 to Count - 1 do
    if SameName(Items[I].Name, Name) then
      Exit(Items[I]);
  Result := nil;
end;

function TVariableList.CheckName(const Name: string; Exclude: TVariable;
  out ErrorMessage: string): Boolean;
var
  V: TVariable;
begin
  if not osNames.CheckName(Name, ErrorMessage) then
    Exit(False);
  V := FindByName(Name);
  if (V <> nil) and (V <> Exclude) then
  begin
    ErrorMessage := Format(rsNameTaken, [Name]);
    Exit(False);
  end;
  Result := True;
end;

// Variables that V's formula reads directly
function TVariableList.VariableDeps(V: TVariable): TVariableArray;
var
  Ref: TFormulaReference;
  W: TVariable;
begin
  Result := nil;
  for Ref in V.Formula.References do
    if Ref.Kind = rkVariable then
    begin
      W := FindById(Ref.Id);
      if W <> nil then
      begin
        SetLength(Result, Length(Result) + 1);
        Result[High(Result)] := W;
      end;
    end;
end;

// True when V reads Target, directly or through other variables
function TVariableList.DependsOn(V, Target: TVariable): Boolean;
var
  Visited: TList;

  function Visit(X: TVariable): Boolean;
  var
    W: TVariable;
  begin
    if X = Target then
      Exit(True);
    if Visited.IndexOf(X) >= 0 then
      Exit(False);
    Visited.Add(X);
    for W in VariableDeps(X) do
      if Visit(W) then
        Exit(True);
    Result := False;
  end;

begin
  Visited := TList.Create;
  try
    Result := Visit(V);
  finally
    Visited.Free;
  end;
end;

// Refuses a formula for V that would make V depend on itself
function TVariableList.CheckCycles(V: TVariable; Formula: TFormula): Boolean;
var
  Ref: TFormulaReference;
  W: TVariable;
begin
  for Ref in Formula.References do
    if Ref.Kind = rkVariable then
    begin
      W := FindById(Ref.Id);
      if W = V then
        Exit(SetError(Format(rsVariableUsesItself, [V.Name])));
      if (W <> nil) and DependsOn(W, V) then
        Exit(SetError(Format(rsVariableCycle, [V.Name, W.Name, W.Name, V.Name])));
    end;
  Result := True;
end;

function TVariableList.Add(const Name, FormulaText: string;
  const Description: string): TVariable;
var
  Msg: string;
begin
  Result := nil;
  if not CheckName(Name, nil, Msg) then
  begin
    SetError(Msg);
    Exit;
  end;
  Result := TVariable.Create;
  if not Result.FFormula.Parse(FormulaText, FResolver) then
  begin
    SetError(Result.FFormula.ErrorMessage, Result.FFormula.ErrorPos);
    FreeAndNil(Result);
    Exit;
  end;
  // A new variable cannot be part of a cycle: nothing refers to it yet
  Result.FId := 'v' + IntToStr(FNextId);
  Inc(FNextId);
  Result.FName := Name;
  Result.Description := Description;
  FItems.Add(Result);
end;

function TVariableList.SetFormula(V: TVariable; const FormulaText: string): Boolean;
var
  F: TFormula;
begin
  F := TFormula.Create;
  try
    if not F.Parse(FormulaText, FResolver) then
      Exit(SetError(F.ErrorMessage, F.ErrorPos));
    if not CheckCycles(V, F) then
      Exit(False);
    // Swap in the new formula; clearing F stops the finally freeing it
    V.FFormula.Free;
    V.FFormula := F;
    F := nil;
    V.FState := esDirty;
    Result := True;
  finally
    F.Free;
  end;
end;

function TVariableList.Rename(V: TVariable; const NewName: string): Boolean;
var
  Msg: string;
begin
  if not CheckName(NewName, V, Msg) then
    Exit(SetError(Msg));
  V.FName := NewName;
  Result := True;
end;

function TVariableList.UsersOf(V: TVariable): TVariableArray;
var
  I: Integer;
  W: TVariable;
begin
  Result := nil;
  for I := 0 to Count - 1 do
    for W in VariableDeps(Items[I]) do
      if W = V then
      begin
        SetLength(Result, Length(Result) + 1);
        Result[High(Result)] := Items[I];
        Break;
      end;
end;

function TVariableList.Delete(V: TVariable): Boolean;
var
  Users: TVariableArray;
  Names: string;
  W: TVariable;
begin
  Users := UsersOf(V);
  if Length(Users) > 0 then
  begin
    Names := '';
    for W in Users do
    begin
      if Names <> '' then
        Names := Names + ', ';
      Names := Names + '#' + W.Name;
    end;
    Exit(SetError(Format(rsVariableInUse, [V.Name, Names])));
  end;
  FItems.Remove(V);
  V.Free;
  Result := True;
end;

function TVariableList.FormulaText(V: TVariable): string;
begin
  Result := V.Formula.DisplayText(FResolver);
end;

procedure TVariableList.Evaluate;
var
  Waiting: array of Integer;   // unevaluated dependencies per variable
  Queue: TList;
  I, Head: Integer;
  V, W, Failed: TVariable;
  Value: Double;
begin
  // Kahn's algorithm: evaluate a variable once everything it reads is done
  Waiting := nil;
  SetLength(Waiting, Count);
  Queue := TList.Create;
  try
    for I := 0 to Count - 1 do
    begin
      Items[I].FState := esDirty;
      Waiting[I] := Length(VariableDeps(Items[I]));
      if Waiting[I] = 0 then
        Queue.Add(Items[I]);
    end;
    Head := 0;
    while Head < Queue.Count do
    begin
      V := TVariable(Queue[Head]);
      Inc(Head);
      Failed := nil;
      for W in VariableDeps(V) do
        if W.State <> esValid then
        begin
          Failed := W;
          Break;
        end;
      if not V.Formula.Valid then
      begin
        V.FState := esError;
        V.FMessage := V.Formula.ErrorMessage;
      end
      else if Failed <> nil then
      begin
        V.FState := esBlocked;
        V.FMessage := Format(rsVariableBlocked, [Failed.Name]);
      end
      else if V.Formula.Evaluate(FContext, Value) then
      begin
        V.FState := esValid;
        V.FMessage := '';
        V.FValue := Value;
      end
      else
      begin
        V.FState := esError;
        V.FMessage := V.Formula.ErrorMessage;
      end;
      // Release the variables that read V
      for I := 0 to Count - 1 do
        for W in VariableDeps(Items[I]) do
          if W = V then
          begin
            Dec(Waiting[I]);
            if Waiting[I] = 0 then
              Queue.Add(Items[I]);
          end;
    end;
  finally
    Queue.Free;
  end;
  // Whatever was never reached is in a cycle (possible only in loaded files)
  for I := 0 to Count - 1 do
    if Items[I].State = esDirty then
    begin
      Items[I].FState := esError;
      Items[I].FMessage := rsVariableInCycle;
    end;
end;

function TVariableList.SaveToJSON: TJSONArray;
var
  I: Integer;
  Item: TJSONObject;
begin
  Result := TJSONArray.Create;
  for I := 0 to Count - 1 do
  begin
    Item := TJSONObject.Create;
    Item.Add('id', Items[I].Id);
    Item.Add('name', Items[I].Name);
    Item.Add('formula', Items[I].Formula.StoredText);
    Item.Add('description', Items[I].Description);
    Result.Add(Item);
  end;
end;

function TVariableList.LoadFromJSON(Data: TJSONData; out ErrorMessage: string): Boolean;
var
  I, N, Code: Integer;
  Item: TJSONObject;
  Id, Name, Text, Desc, Msg: string;
  V: TVariable;

  function Fail(const AMsg: string): Boolean;
  begin
    ErrorMessage := AMsg;
    Clear;
    Result := False;
  end;

begin
  Clear;
  ErrorMessage := '';
  if (Data = nil) or (Data.JSONType <> jtArray) then
    Exit(Fail(rsVariableList));
  for I := 0 to Data.Count - 1 do
  begin
    if Data.Items[I].JSONType <> jtObject then
      Exit(Fail(rsVariableList));
    Item := TJSONObject(Data.Items[I]);
    if not GetJSONString(Item, 'id', Id) or (Id = '') or (FindById(Id) <> nil) then
      Exit(Fail(rsVariableBadId));
    if not GetJSONString(Item, 'name', Name) then
      Name := '';
    if not CheckName(Name, nil, Msg) then
      Exit(Fail(Format(rsVariableBadName, [Msg])));
    if not GetJSONString(Item, 'formula', Text) then
      Exit(Fail(Format(rsVariableNoFormula, [Name])));
    GetJSONString(Item, 'description', Desc);
    V := TVariable.Create;
    V.FId := Id;
    V.FName := Name;
    V.Description := Desc;
    V.FFormula.ParseStored(Text);
    FItems.Add(V);
    // Keep new IDs above every loaded one
    if (Length(Id) > 1) and (Id[1] = 'v') then
    begin
      Val(Copy(Id, 2, MaxInt), N, Code);
      if (Code = 0) and (N >= FNextId) then
        FNextId := N + 1;
    end;
  end;
  Result := True;
end;

end.
