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

// Copy and paste: selected objects as a fragment, JSON in pattern file form,
// and pasting one into a pattern (see Copy and paste in the design document).
// A fragment holds the selection and every object and variable it depends
// on. Pasted into the pattern it came from, only the selection is added and
// its references outside the selection stay on the objects already there;
// pasted into another pattern, everything is added. Pasted objects take new
// IDs and free names. No LCL dependency.
unit Sloper.Core.Fragment;

{$mode ObjFPC}{$H+}

interface

uses
  SysUtils, Sloper.Core.Pattern;

const
  // The clipboard format the apps register for a fragment
  FRAGMENT_MIME_TYPE = 'application/x-opensloper-fragment';

type
  TFragmentCopy = record
    // The fragment; empty when nothing selected can be copied
    Text: string;
    // The copied objects' names, for the plain text clipboard
    Names: string;
    // The copied objects
    Keys: TStringArray;
    // Names of selected objects that cannot be copied, such as pieces
    LeftOut: TStringArray;
  end;

  TFragmentPaste = record
    // The pasted copies of the selected objects, in the order they were copied
    Keys: TStringArray;
    // Names that clashed, as "A → A2"
    Renamed: TStringArray;
  end;

// The objects with these keys as a fragment. Pattern must be evaluated, for
// copies of transform copies, which are copied as plain points and edges.
function CopyFragment(Pattern: TPattern; const Keys: array of string): TFragmentCopy;
// Whether Text looks like a fragment, without checking it all
function IsFragmentText(const Text: string): boolean;
// Adds the fragment to Pattern. On failure the pattern may hold part of it
// (a document change undoes that) and ErrorMessage says why. Call Evaluate
// afterwards.
function PasteFragment(Pattern: TPattern; const Text: string; out Pasted: TFragmentPaste; out ErrorMessage: string): boolean;

resourcestring
  rsFragmentNotFragment = 'There are no copied objects to paste';
  rsFragmentNewerVersion = 'The copied objects come from a newer version of OpenSloper';
  rsFragmentUnits = 'The copied objects are in %s and this pattern is in %s; convert one of them first';
  rsFragmentNeeds = 'The copied objects need %s, which cannot be pasted into another pattern';
  rsFragmentRenamed = '%s → %s';

implementation

uses
  Math, Generics.Collections, fpjson, Sloper.Core.JSON, Sloper.Core.Evaluator, Sloper.Core.Geometry, Sloper.Core.Bezier, Sloper.Core.Draft,
  Sloper.Core.Variables, Sloper.Core.Transform, Sloper.Core.Units, Sloper.Core.Names, Sloper.Core.PatternFile;

const
  FRAGMENT_FORMAT = 'opensloperFragment';
  FRAGMENT_VERSION = 1;
  // Decimals for a transform copy's position and handles
  COPY_DECIMALS = 4;

type
  TKeySet = specialize THashSet<string>;

  { Copying }

function IsCopyableEdgeCopy(Edge: TEdgeCopy): boolean;
begin
  Result := Edge.IsStraight or ((Length(Edge.Segments) = 1) and (Edge.Segments[0].Kind = skCurve));
end;

// Points, repeats and edges; a transform copy as the plain point or edge it gives
function CanCopy(Node: TEvalNode): boolean;
begin
  if Node is TEdgeCopy then
    Result := IsCopyableEdgeCopy(TEdgeCopy(Node))
  else
    Result := ((Node is TPointObject) and not (Node is TRepeatPoint)) or (Node is TRepeatObject) or (Node is TEdgeObject);
end;

function NumberText(Value: double): string;
begin
  Result := FormatJSONFloat(RoundTo(Value, -COPY_DECIMALS));
end;

// A transform copy as a plain object at its last good place, written as a
// pattern file writes the object
function PlainCopyJSON(Pattern: TPattern; Node: TDraftObject): TJSONObject;
var
  Plain: TDraftObject;
  Edge: TEdgeCopy;
  Curve: TCubicBezier;
begin
  if Node is TPointCopy then
  begin
    Plain := TFreePoint.Create(Node.Key);
    Plain.Field('x').ParseStored(LengthFormulaText(TPointObject(Node).Position.X, Pattern.Units, COPY_DECIMALS));
    Plain.Field('y').ParseStored(LengthFormulaText(TPointObject(Node).Position.Y, Pattern.Units, COPY_DECIMALS));
  end
  else
  begin
    Edge := TEdgeCopy(Node);
    if Edge.IsStraight then
      Plain := TLineObject.Create(Edge.Key, Edge.StartKey, Edge.EndKey)
    else
    begin
      Plain := TCurveObject.Create(Edge.Key, Edge.StartKey, Edge.EndKey);
      Curve := Edge.Segments[0].Curve;
      Plain.Field('angle1').ParseStored(NumberText(AngleBetween(Curve.P0, Curve.P1)));
      Plain.Field('length1').ParseStored(LengthFormulaText(Distance(Curve.P0, Curve.P1), Pattern.Units, COPY_DECIMALS));
      Plain.Field('angle2').ParseStored(NumberText(AngleBetween(Curve.P3, Curve.P2)));
      Plain.Field('length2').ParseStored(LengthFormulaText(Distance(Curve.P3, Curve.P2), Pattern.Units, COPY_DECIMALS));
    end;
    TEdgeObject(Plain).Role := Edge.Role;
    TEdgeObject(Plain).NameIsDerived := Edge.NameIsDerived;
  end;
  try
    Plain.Name := Node.Name;
    Result := PatternObjectToJSON(Plain);
  finally
    FreeAndNil(Plain);
  end;
end;

type
  // Works out what a copy holds: the selection and what it depends on
  TFragmentBuilder = class
  private
    FPattern: TPattern;
    FIncluded: TKeySet;
    FSelected: TStringArray;
    FNames: TStringArray;
    FLeftOut: TStringArray;
    // Objects the copy needs that cannot be copied
    FNeeds: TStringArray;
    procedure Include(Node: TEvalNode);
    function VariablesJSON: TJSONArray;
    function ObjectsJSON: TJSONArray;
  public
    constructor Create(APattern: TPattern);
    destructor Destroy; override;
    procedure Select(const Keys: array of string);
    function Build: TFragmentCopy;
  end;

constructor TFragmentBuilder.Create(APattern: TPattern);
begin
  FPattern := APattern;
  FIncluded := TKeySet.Create;
end;

destructor TFragmentBuilder.Destroy;
begin
  FreeAndNil(FIncluded);
  inherited Destroy;
end;

// Node and everything it reads. A transform copy is copied as a plain
// object: a point needs nothing, and an edge only its ends. A repeat's point
// needs its repeat.
procedure TFragmentBuilder.Include(Node: TEvalNode);
var
  Key: string;
  Dependency: TEvalNode;
begin
  if FIncluded.Contains(Node.Key) then
    Exit;
  FIncluded.Add(Node.Key);
  if Node is TPointCopy then
    Exit;
  if Node is TEdgeCopy then
  begin
    Include(FPattern.FindNode(TEdgeCopy(Node).StartKey));
    Include(FPattern.FindNode(TEdgeCopy(Node).EndKey));
    Exit;
  end;
  if Node is TRepeatPoint then
  begin
    Include(TRepeatPoint(Node).Source);
    Exit;
  end;
  for Key in Node.DependencyKeys do
  begin
    if (Key = '') or (Key[1] = '@') then
      Continue;
    Dependency := FPattern.FindNode(Key);
    if not Assigned(Dependency) then
      Continue;
    if (Dependency is TVariable) or (Dependency is TRepeatPoint) or CanCopy(Dependency) then
      Include(Dependency)
    else
      Insert(Dependency.DisplayName, FNeeds, Length(FNeeds));
  end;
end;

procedure TFragmentBuilder.Select(const Keys: array of string);
var
  Key: string;
  Node: TEvalNode;
begin
  for Key in Keys do
  begin
    Node := FPattern.FindNode(Key);
    if not Assigned(Node) then
      Continue;
    if not CanCopy(Node) then
    begin
      Insert(Node.DisplayName, FLeftOut, Length(FLeftOut));
      Continue;
    end;
    Insert(Node.Key, FSelected, Length(FSelected));
    Insert(Node.DisplayName, FNames, Length(FNames));
    Include(Node);
  end;
end;

// Each with its formula as the user reads it, so that another pattern can
// tell whether a variable of the same name is the same
function TFragmentBuilder.VariablesJSON: TJSONArray;
var
  Index: integer;
  Variable: TVariable;
  Item: TJSONObject;
begin
  Result := TJSONArray.Create;
  try
    for Index := 0 to FPattern.VariableCount - 1 do
    begin
      Variable := FPattern.Variables[Index];
      if not FIncluded.Contains(Variable.Key) then
        Continue;
      Item := PatternVariableToJSON(Variable);
      Result.Add(Item);
      Item.Add('display', Variable.Formula.DisplayText(FPattern.Resolver));
    end;
  except
    FreeAndNil(Result);
    raise;
  end;
end;

// In the pattern's order, which lists every object after what it reads
function TFragmentBuilder.ObjectsJSON: TJSONArray;
var
  Index: integer;
  DraftObject: TDraftObject;
  Item: TJSONObject;
begin
  Result := TJSONArray.Create;
  try
    for Index := 0 to FPattern.ObjectCount - 1 do
    begin
      DraftObject := FPattern.Objects[Index];
      if not FIncluded.Contains(DraftObject.Key) then
        Continue;
      if (DraftObject is TPointCopy) or (DraftObject is TEdgeCopy) then
        Result.Add(PlainCopyJSON(FPattern, DraftObject))
      else
      begin
        Item := PatternObjectToJSON(DraftObject);
        // A pasted copy starts unlocked
        Item.Delete('locked');
        Result.Add(Item);
      end;
    end;
  except
    FreeAndNil(Result);
    raise;
  end;
end;

function TFragmentBuilder.Build: TFragmentCopy;
var
  Root: TJSONObject;
  List: TJSONArray;
  Key, Name: string;
begin
  Result := Default(TFragmentCopy);
  Result.LeftOut := FLeftOut;
  Result.Keys := FSelected;
  if Length(FSelected) = 0 then
    Exit;
  Root := TJSONObject.Create;
  try
    Root.Add('format', FRAGMENT_FORMAT);
    Root.Add('version', FRAGMENT_VERSION);
    Root.Add('identity', FPattern.Identity);
    Root.Add('units', MEASURE_UNIT_NAMES[FPattern.Units]);
    List := TJSONArray.Create;
    Root.Add('selection', List);
    for Key in FSelected do
      List.Add(StrToInt(Key));
    Root.Add('variables', VariablesJSON);
    Root.Add('objects', ObjectsJSON);
    if Length(FNeeds) > 0 then
    begin
      List := TJSONArray.Create;
      Root.Add('needs', List);
      for Name in FNeeds do
        List.Add(Name);
    end;
    Result.Text := JSONToText(Root);
  finally
    FreeAndNil(Root);
  end;
  Result.Names := string.Join(' ', FNames);
end;

function CopyFragment(Pattern: TPattern; const Keys: array of string): TFragmentCopy;
var
  Builder: TFragmentBuilder;
begin
  Builder := TFragmentBuilder.Create(Pattern);
  try
    Builder.Select(Keys);
    Result := Builder.Build;
  finally
    FreeAndNil(Builder);
  end;
end;

function IsFragmentText(const Text: string): boolean;
var
  Root: TJSONObject;
  Reason, FormatName: string;
begin
  if (Text = '') or not ParseJSONObject(Text, Root, Reason) then
    Exit(False);
  try
    Result := GetJSONString(Root, 'format', FormatName) and (FormatName = FRAGMENT_FORMAT);
  finally
    FreeAndNil(Root);
  end;
end;

{ Pasting }

type
  // Decides each item's new ID and name, then adds the items
  TFragmentPaster = class
  private
    FPattern: TPattern;
    FRoot: TJSONObject;
    FSamePattern: boolean;
    FSelection: TKeySet;
    FMap: TPatternIdMap;
    FNextId: integer;
    // Names given in this paste, upper case
    FUsedObjectNames, FUsedVariableNames: TKeySet;
    FVariables, FObjects: TJSONArray;
    FRenamed: TStringArray;
    FError: string;
    function Fail(const Msg: string): boolean;
    function NewKey: string;
    function ObjectNameTaken(const AName: string): boolean;
    function VariableNameTaken(const AName: string): boolean;
    procedure GiveFreeName(Item: TJSONObject; IsTaken: TNameTakenFunc; Used: TKeySet);
    function ReadHeader: boolean;
    function ReadSelection: boolean;
    function ExistingVariable(Item: TJSONObject; const Id: string): string;
    function PlanVariables: boolean;
    function PlanObjects: boolean;
  public
    constructor Create(APattern: TPattern);
    destructor Destroy; override;
    function Paste(const Text: string; out Pasted: TFragmentPaste): boolean;
    property Error: string read FError;
  end;

constructor TFragmentPaster.Create(APattern: TPattern);
begin
  FPattern := APattern;
  FSelection := TKeySet.Create;
  FMap := TPatternIdMap.Create;
  FUsedObjectNames := TKeySet.Create;
  FUsedVariableNames := TKeySet.Create;
  FVariables := TJSONArray.Create;
  FObjects := TJSONArray.Create;
end;

destructor TFragmentPaster.Destroy;
begin
  FreeAndNil(FObjects);
  FreeAndNil(FVariables);
  FreeAndNil(FUsedVariableNames);
  FreeAndNil(FUsedObjectNames);
  FreeAndNil(FMap);
  FreeAndNil(FSelection);
  FreeAndNil(FRoot);
  inherited Destroy;
end;

function TFragmentPaster.Fail(const Msg: string): boolean;
begin
  FError := Msg;
  Result := False;
end;

function TFragmentPaster.NewKey: string;
begin
  Result := IntToStr(FNextId);
  Inc(FNextId);
end;

function TFragmentPaster.ObjectNameTaken(const AName: string): boolean;
var
  Reason: string;
begin
  Result := FUsedObjectNames.Contains(UpperCase(AName)) or not FPattern.CheckObjectName(AName, nil, Reason);
end;

function TFragmentPaster.VariableNameTaken(const AName: string): boolean;
var
  Reason: string;
begin
  Result := FUsedVariableNames.Contains(UpperCase(AName)) or not FPattern.CheckVariableName(AName, nil, Reason);
end;

// A name that clashes takes the next copy number (A → A2). An edge named
// after its ends has none here; it is named once added.
procedure TFragmentPaster.GiveFreeName(Item: TJSONObject; IsTaken: TNameTakenFunc; Used: TKeySet);
var
  OldName, NewName: string;
begin
  if not GetJSONString(Item, 'name', OldName) then
    Exit;
  NewName := NextFreeName(OldName, IsTaken);
  Used.Add(UpperCase(NewName));
  if NewName = OldName then
    Exit;
  Item.Strings['name'] := NewName;
  Insert(Format(rsFragmentRenamed, [OldName, NewName]), FRenamed, Length(FRenamed));
end;

function TFragmentPaster.ReadHeader: boolean;
var
  Text, Identity: string;
  Version: integer;
  Units: TMeasureUnit;
  Needs: TJSONData;
begin
  if not GetJSONString(FRoot, 'format', Text) or (Text <> FRAGMENT_FORMAT) or not GetJSONInteger(FRoot, 'version', Version) then
    Exit(Fail(rsFragmentNotFragment));
  if Version > FRAGMENT_VERSION then
    Exit(Fail(rsFragmentNewerVersion));
  if not GetJSONString(FRoot, 'units', Text) or not MeasureUnitFromName(Text, Units) then
    Exit(Fail(rsFragmentNotFragment));
  if Units <> FPattern.Units then
    Exit(Fail(Format(rsFragmentUnits, [MEASURE_UNIT_NAMES[Units], MEASURE_UNIT_NAMES[FPattern.Units]])));
  GetJSONString(FRoot, 'identity', Identity);
  FSamePattern := (Identity <> '') and (Identity = FPattern.Identity);
  Needs := FRoot.Find('needs');
  if not FSamePattern and Assigned(Needs) and (Needs.JSONType = jtArray) and (Needs.Count > 0) then
    Exit(Fail(Format(rsFragmentNeeds, [Needs.Items[0].AsString])));
  Result := True;
end;

function TFragmentPaster.ReadSelection: boolean;
var
  List: TJSONData;
  Index: integer;
begin
  List := FRoot.Find('selection');
  if not Assigned(List) or (List.JSONType <> jtArray) or (List.Count = 0) then
    Exit(Fail(rsFragmentNotFragment));
  for Index := 0 to List.Count - 1 do
  begin
    if List.Items[Index].JSONType <> jtNumber then
      Exit(Fail(rsFragmentNotFragment));
    FSelection.Add(IntToStr(List.Items[Index].AsInteger));
  end;
  Result := True;
end;

// The key of the variable already in the pattern that Item stands for, or ''
function TFragmentPaster.ExistingVariable(Item: TJSONObject; const Id: string): string;
var
  Existing: TVariable;
  AName, Display: string;
begin
  Result := '';
  if FSamePattern then
  begin
    if FPattern.FindNode(Id) is TVariable then
      Result := Id;
    Exit;
  end;
  // Another pattern's variable is the same when its name and formula are
  if not GetJSONString(Item, 'name', AName) or not GetJSONString(Item, 'display', Display) then
    Exit;
  Existing := FPattern.FindVariable(AName);
  if Assigned(Existing) and (Existing.Formula.DisplayText(FPattern.Resolver) = Display) then
    Result := Existing.Key;
end;

function TFragmentPaster.PlanVariables: boolean;
var
  List: TJSONData;
  Index, Value: integer;
  Item: TJSONObject;
  Id, Existing: string;
begin
  List := FRoot.Find('variables');
  if not Assigned(List) then
    Exit(True);
  if List.JSONType <> jtArray then
    Exit(Fail(rsFragmentNotFragment));
  for Index := 0 to List.Count - 1 do
  begin
    if (List.Items[Index].JSONType <> jtObject) or not GetJSONInteger(TJSONObject(List.Items[Index]), 'id', Value) then
      Exit(Fail(rsFragmentNotFragment));
    Item := TJSONObject(List.Items[Index]);
    Id := IntToStr(Value);
    Existing := ExistingVariable(Item, Id);
    if Existing <> '' then
      FMap.AddOrSetValue(Id, Existing)
    else
    begin
      FMap.AddOrSetValue(Id, NewKey);
      GiveFreeName(Item, @VariableNameTaken, FUsedVariableNames);
      FVariables.Add(Item.Clone);
    end;
  end;
  Result := True;
end;

// In the same pattern, what is outside the selection and still there is used
// as it is; everything else is added with new IDs, a repeat's points too
function TFragmentPaster.PlanObjects: boolean;
var
  List, Points: TJSONData;
  Index, Inner, Value: integer;
  Item: TJSONObject;
  Id: string;
begin
  List := FRoot.Find('objects');
  if not Assigned(List) or (List.JSONType <> jtArray) then
    Exit(Fail(rsFragmentNotFragment));
  for Index := 0 to List.Count - 1 do
  begin
    if (List.Items[Index].JSONType <> jtObject) or not GetJSONInteger(TJSONObject(List.Items[Index]), 'id', Value) then
      Exit(Fail(rsFragmentNotFragment));
    Item := TJSONObject(List.Items[Index]);
    Id := IntToStr(Value);
    if FSamePattern and not FSelection.Contains(Id) and Assigned(FPattern.FindNode(Id)) then
    begin
      FMap.AddOrSetValue(Id, Id);
      Continue;
    end;
    FMap.AddOrSetValue(Id, NewKey);
    Points := Item.Find('points');
    if Assigned(Points) and (Points.JSONType = jtArray) then
      for Inner := 0 to Points.Count - 1 do
        if (Points.Items[Inner].JSONType = jtObject) and GetJSONInteger(TJSONObject(Points.Items[Inner]), 'id', Value) then
          FMap.AddOrSetValue(IntToStr(Value), NewKey);
    GiveFreeName(Item, @ObjectNameTaken, FUsedObjectNames);
    FObjects.Add(Item.Clone);
  end;
  Result := True;
end;

function TFragmentPaster.Paste(const Text: string; out Pasted: TFragmentPaste): boolean;
var
  Key: string;
  Added: TStringArray;
  Index: integer;
  Item: TJSONData;
begin
  Pasted := Default(TFragmentPaste);
  if not ParseJSONObject(Text, FRoot, FError) then
    Exit(Fail(rsFragmentNotFragment));
  if not ReadHeader or not ReadSelection then
    Exit(False);
  FNextId := FPattern.NextId;
  if not PlanVariables or not PlanObjects then
    Exit(False);
  for Key in FSelection do
    if not FMap.ContainsKey(Key) then
      Exit(Fail(rsFragmentNotFragment));
  if not AddPatternItems(FPattern, FVariables, FObjects, FMap, FError) then
    Exit(False);
  Added := nil;
  for Index := 0 to FObjects.Count - 1 do
  begin
    Item := FObjects.Items[Index];
    Insert(FMap[IntToStr(TJSONObject(Item).Integers['id'])], Added, Length(Added));
  end;
  // A pasted stitch line inside a piece joins it, as a new one would
  FPattern.QueueMarkings(Added);
  for Index := 0 to TJSONArray(FRoot.Find('selection')).Count - 1 do
  begin
    Key := FMap[IntToStr(TJSONArray(FRoot.Find('selection')).Integers[Index])];
    Insert(Key, Pasted.Keys, Length(Pasted.Keys));
  end;
  Pasted.Renamed := FRenamed;
  Result := True;
end;

function PasteFragment(Pattern: TPattern; const Text: string; out Pasted: TFragmentPaste; out ErrorMessage: string): boolean;
var
  Paster: TFragmentPaster;
begin
  Paster := TFragmentPaster.Create(Pattern);
  try
    Result := Paster.Paste(Text, Pasted);
    ErrorMessage := Paster.Error;
  finally
    FreeAndNil(Paster);
  end;
end;

end.
