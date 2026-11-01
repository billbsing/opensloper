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

// The Automation API: JSON-RPC 2.0, one message to a line, over an open
// document. Every edit goes through the document's change commands, so name
// rules, formula checks and undo apply as they do for a user, and the API
// cannot make a state the UI could not. Refusals come back as errors carrying
// the message, field and position. Independent of any transport, so it can be
// tested directly; opensloper-cli serve connects it to stdin and stdout. No LCL
// dependency.
unit Sloper.API.Server;

{$mode ObjFPC}{$H+}

interface

uses
  SysUtils, fpjson, Sloper.Core.Evaluator, Sloper.Core.Piece, Sloper.Core.Seam, Sloper.Document.PatternDocument;

const
  // JSON-RPC 2.0's own codes
  RpcParseError = -32700;
  RpcInvalidRequest = -32600;
  RpcMethodNotFound = -32601;
  RpcInvalidParams = -32602;
  RpcInternalError = -32603;
  // The call was understood and refused
  RpcRefused = -32000;

type
  EApiError = class(Exception)
  public
    Code: integer;
    FieldName: string;
    Position: integer;
    constructor Create(ACode: integer; const AMessage: string; const AFieldName: string = ''; APosition: integer = 0);
  end;

  TApiServer = class
  private
    FDocument: TPatternDocument;
    function CallMethod(const Method: string; Params: TJSONObject): TJSONData;
    function FindTarget(Params: TJSONObject): TEvalNode;
    function DocumentInfo: TJSONObject;
    function ProblemsResult(WithReport: boolean): TJSONObject;
    // Cancels the open change and raises the pattern's reason for refusing it
    procedure RefuseChange;
    function Reference(Params: TJSONObject; const AName: string): string;
    function AddedNode(Node: TEvalNode): TJSONData;
    function DoOpen(Params: TJSONObject): TJSONData;
    function DoSave(Params: TJSONObject): TJSONData;
    function DoGetMeasurements: TJSONData;
    function DoMissingMeasurements: TJSONData;
    function DoAddRepeat(Params: TJSONObject): TJSONData;
    function DoArrange(Params: TJSONObject): TJSONData;
    function ReferenceList(Params: TJSONObject; const AName: string): TStringArray;
    // Selects it, refusing one the set does not have; empty leaves it alone
    procedure UseSize(const Size: string);
    function DoSetMeasurement(Params: TJSONObject): TJSONData;
    function DoListObjects: TJSONData;
    function DoGetObject(Params: TJSONObject): TJSONData;
    function DoSetFormula(Params: TJSONObject): TJSONData;
    function DoRename(Params: TJSONObject): TJSONData;
    function DoDelete(Params: TJSONObject): TJSONData;
    function DoEvaluate(WithReport: boolean): TJSONData;
    function DoUndo: TJSONData;
    function DoRedo: TJSONData;
    function DoRender(Params: TJSONObject): TJSONData;
    function DoAddVariable(Params: TJSONObject): TJSONData;
    function DoAddPoint(Params: TJSONObject): TJSONData;
    function DoAddEdge(Params: TJSONObject): TJSONData;
    function DoSplitEdge(Params: TJSONObject): TJSONData;
    function DoCreatePiece(Params: TJSONObject): TJSONData;
    function DoSetEdgeAllowance(Params: TJSONObject): TJSONData;
    function TargetPiece(Params: TJSONObject): TPieceObject;
    function DoSetGrainline(Params: TJSONObject): TJSONData;
    function DoAddNotch(Params: TJSONObject): TJSONData;
    function DoRemoveNotch(Params: TJSONObject): TJSONData;
    function DoSetCut(Params: TJSONObject): TJSONData;
    function DoSetFold(Params: TJSONObject): TJSONData;
    function SeamSideParam(Params: TJSONObject; const AName: string): TSeamSide;
    function DoAddSeam(Params: TJSONObject): TJSONData;
    function DoFlipSeam(Params: TJSONObject): TJSONData;
    function DoSuggestSeams: TJSONData;
  public
    constructor Create;
    destructor Destroy; override;
    // The response to one line, on one line; '' for a notification, which has
    // no id and gets no reply
    function HandleLine(const Line: string): string;
    property Document: TPatternDocument read FDocument;
  end;

resourcestring
  rsApiNotRequest = 'The request must be a JSON-RPC 2.0 object with a method';
  rsApiNoMethod = 'There is no method "%s"';
  rsApiMissingParam = 'Parameter "%s" is missing or the wrong type';
  rsApiNoTarget = 'Give the object as "id" or "name"';
  rsApiUnknownId = 'There is no object or variable with ID %d';
  rsApiUnknownName = 'There is no object or variable named "%s"';
  rsApiNoFileName = 'The pattern has no file name yet; give a "path"';
  rsApiNothingToUndo = 'There is nothing to undo';
  rsApiNothingToRedo = 'There is nothing to redo';
  rsApiSetFormula = 'Change %s';
  rsApiRename = 'Rename';
  rsApiDelete = 'Delete';
  rsApiAdd = 'Add %s';
  rsApiSplit = 'Split edge';
  rsApiUnknownType = 'There is no type "%s"; use one of: %s';
  rsApiBadChoice = 'Parameter "%s" must be one of: %s';
  rsApiBadNodes = 'A curve path needs a "nodes" list, each with a point and angle';
  rsApiRenderFormat = 'Format "%s" is not available; use svg';
  rsApiPieceExists = '%s already covers this region';
  rsApiNotAPiece = '%s is not a piece';
  rsApiNotInPiece = '%s is not part of %s';
  rsApiNotASeam = '%s is not a seam';
  rsApiBadSeamSide = 'Parameter "%s" must be a list of objects with a "piece" and an "edge"';
  rsApiFlipSeam = 'Flip seam';
  rsApiEdgeAllowance = 'Change seam allowance';
  rsApiGrainline = 'Change grainline';
  rsApiAddNotch = 'Add notch';
  rsApiRemoveNotch = 'Remove notch';
  rsApiArrange = 'Arrange points';
  rsApiAddRepeat = 'Add repeat';
  rsApiCut = 'Change cut';
  rsApiFold = 'Change fold';
  rsApiBadFold = 'Give an "edge", or "none": true';
  rsApiBadGrainline = 'Give an "angle", a "start" and "end" point, or "none": true';
  rsApiBadNotch = 'Give a "point", or an "edge" and a "position"';
  rsApiBadRegion = 'A region needs minX, minY, maxX and maxY, with each max above its min';

implementation

uses
  Sloper.Core.Arrange, Sloper.Core.EvalTypes, Sloper.Core.JSON, Sloper.Core.Measurements, Sloper.Core.PatternCheck, Sloper.Core.PatternFile, Sloper.Core.Pattern,
  Sloper.Core.Variables, Sloper.Core.Draft, Sloper.Core.Geometry, Sloper.Core.PieceDetect, Sloper.Core.SeamSuggest, Sloper.Output.DraftSVG;

const
  VariableType = 'variable';
  PieceType = 'piece';
  SeamType = 'seam';
  RenderFormatSVG = 'svg';

constructor EApiError.Create(ACode: integer; const AMessage: string; const AFieldName: string; APosition: integer);
begin
  inherited Create(AMessage);
  Code := ACode;
  FieldName := AFieldName;
  Position := APosition;
end;

function RequireString(Params: TJSONObject; const AName: string): string;
begin
  if (Params = nil) or not GetJSONString(Params, AName, Result) then
    raise EApiError.Create(RpcInvalidParams, Format(rsApiMissingParam, [AName]));
end;

function OptionalString(Params: TJSONObject; const AName: string): string;
begin
  Result := '';
  if (Params <> nil) and (Params.Find(AName) <> nil) then
    Result := RequireString(Params, AName);
end;

// A formula, as text or a plain number
function FormulaParam(Params: TJSONObject; const AName: string): string;
var
  Value: double;
begin
  if GetJSONNumber(Params, AName, Value) then
    Exit(FormatJSONFloat(Value));
  Result := RequireString(Params, AName);
end;

function OptionalFormula(Params: TJSONObject; const AName: string): string;
begin
  Result := '';
  if Params.Find(AName) <> nil then
    Result := FormulaParam(Params, AName);
end;

function BooleanParam(Params: TJSONObject; const AName: string): boolean;
begin
  Result := False;
  if (Params.Find(AName) <> nil) and not GetJSONBoolean(Params, AName, Result) then
    raise EApiError.Create(RpcInvalidParams, Format(rsApiMissingParam, [AName]));
end;

// Which of Choices, the first when absent
function ChoiceParam(Params: TJSONObject; const AName: string; const Choices: array of string): integer;
var
  Text: string;
begin
  Result := 0;
  if Params.Find(AName) = nil then
    Exit;
  Text := RequireString(Params, AName);
  for Result := 0 to High(Choices) do
    if Choices[Result] = Text then
      Exit;
  raise EApiError.Create(RpcInvalidParams, Format(rsApiBadChoice, [AName, string.Join(', ', Choices)]));
end;

function PickParam(Params: TJSONObject): integer;
begin
  Result := 1;
  if (Params.Find('pick') <> nil) and not GetJSONInteger(Params, 'pick', Result) then
    raise EApiError.Create(RpcInvalidParams, Format(rsApiMissingParam, ['pick']));
end;

function RoleParam(Params: TJSONObject): TEdgeRole;
begin
  Result := TEdgeRole(ChoiceParam(Params, 'role', ['construction', 'outline']));
end;

// Name, type, state and what it computes to, then its formulas with names
function SeamEntryToJSON(Pattern: TPattern; const Entry: TSeamEntry): TJSONObject;
begin
  Result := TJSONObject.Create;
  try
    Result.Add('piece', Pattern.FindNode(Entry.PieceKey).DisplayName);
    Result.Add('edge', Pattern.FindNode(Entry.EdgeKey).DisplayName);
  except
    FreeAndNil(Result);
    raise;
  end;
end;

function SeamSideToJSON(Pattern: TPattern; const Side: TSeamSide): TJSONArray;
var
  Entry: TSeamEntry;
begin
  Result := TJSONArray.Create;
  try
    for Entry in Side do
      Result.Add(SeamEntryToJSON(Pattern, Entry));
  except
    FreeAndNil(Result);
    raise;
  end;
end;

function PiecePathToJSON(Piece: TPieceObject): TJSONArray;
var
  Entry: TPieceEdge;
  Item: TJSONObject;
begin
  Result := TJSONArray.Create;
  try
    for Entry in Piece.Path do
    begin
      Item := TJSONObject.Create;
      Result.Add(Item);
      Item.Add('edge', StrToInt(Entry.EdgeKey));
      Item.Add('reversed', Entry.Reversed);
    end;
  except
    FreeAndNil(Result);
    raise;
  end;
end;

function NodeToJSON(Document: TPatternDocument; Node: TEvalNode): TJSONObject;
var
  Formulas: TJSONObject;
  Index: integer;
  FieldName: string;
begin
  Result := TJSONObject.Create;
  try
    // A repeat's point has no ID until something uses it
    if (Node is TRepeatPoint) and TRepeatPoint(Node).IsVirtual then
      Result.Add('id', TJSONNull.Create)
    else
      Result.Add('id', StrToInt(Node.Key));
    if Node is TVariable then
    begin
      Result.Add('name', TVariable(Node).Name);
      Result.Add('type', VariableType);
    end
    else
    begin
      Result.Add('name', Node.DisplayName);
      Result.Add('type', PatternObjectTypeName(TDraftObject(Node)));
    end;
    Result.Add('state', StateName(Node.State));
    if Node.State <> esValid then
      Result.Add('message', Node.Message);
    if Node.State = esValid then
      if Node is TVariable then
        Result.Add('value', ReportFloat(TVariable(Node).Value))
      else if Node is TPointObject then
      begin
        Result.Add('x', ReportFloat(TPointObject(Node).Position.X));
        Result.Add('y', ReportFloat(TPointObject(Node).Position.Y));
      end
      else if Node is TEdgeObject then
        Result.Add('length', ReportFloat(TEdgeObject(Node).Length))
      else if Node is TPieceObject then
      begin
        Result.Add('area', ReportFloat(TPieceObject(Node).Area));
        Result.Add('perimeter', ReportFloat(TPieceObject(Node).Perimeter));
        Result.Add('path', PiecePathToJSON(TPieceObject(Node)));
        Result.Add('notches', Length(TPieceObject(Node).Notches));
        Result.Add('cutCount', TPieceObject(Node).CutCount);
        Result.Add('mirrored', TPieceObject(Node).Mirrored);
        Result.Add('onFold', TPieceObject(Node).OnFold);
      end
      else if Node is TSeamObject then
      begin
        Result.Add('sideA', SeamSideToJSON(Document.Pattern, TSeamObject(Node).SideA));
        Result.Add('sideB', SeamSideToJSON(Document.Pattern, TSeamObject(Node).SideB));
        Result.Add('reversed', TSeamObject(Node).Reversed);
        Result.Add('lengthA', ReportFloat(TSeamObject(Node).LengthA));
        Result.Add('lengthB', ReportFloat(TSeamObject(Node).LengthB));
        Result.Add('difference', ReportFloat(TSeamObject(Node).Difference));
        Result.Add('outOfTolerance', TSeamObject(Node).OutOfTolerance);
      end;
    Formulas := TJSONObject.Create;
    Result.Add('formulas', Formulas);
    for Index := 0 to Node.FieldCount - 1 do
    begin
      FieldName := Node.Fields[Index].Name;
      Formulas.Add(FieldName, Document.Pattern.FormulaText(Node, FieldName));
    end;
  except
    FreeAndNil(Result);
    raise;
  end;
end;

constructor TApiServer.Create;
begin
  inherited Create;
  FDocument := TPatternDocument.Create;
end;

destructor TApiServer.Destroy;
begin
  FreeAndNil(FDocument);
  inherited Destroy;
end;

// The reason is read first, since cancelling can reload the pattern
procedure TApiServer.RefuseChange;
var
  Reason, FieldName: string;
  Position: integer;
begin
  Reason := FDocument.Pattern.LastError;
  FieldName := FDocument.Pattern.LastErrorField;
  Position := FDocument.Pattern.LastErrorPos;
  FDocument.CancelChange;
  raise EApiError.Create(RpcRefused, Reason, FieldName, Position);
end;

// The ID of an input given as a number, or as an object's name
function TApiServer.Reference(Params: TJSONObject; const AName: string): string;
var
  Id: integer;
  TargetName: string;
  Target: TDraftObject;
begin
  if GetJSONInteger(Params, AName, Id) then
    Exit(IntToStr(Id));
  if not GetJSONString(Params, AName, TargetName) then
    raise EApiError.Create(RpcInvalidParams, Format(rsApiMissingParam, [AName]));
  Target := FDocument.Pattern.FindObject(TargetName);
  if Target = nil then
    raise EApiError.Create(RpcRefused, Format(rsApiUnknownName, [TargetName]));
  Result := FDocument.Pattern.UsePoint(Target.Key);
end;

// Ends the change that added Node, nil when it was refused
function TApiServer.AddedNode(Node: TEvalNode): TJSONData;
var
  Key: string;
begin
  if Node = nil then
    RefuseChange;
  Key := Node.Key;
  FDocument.EndChange;
  Result := NodeToJSON(FDocument, FDocument.Pattern.FindNode(Key));
end;

// The object or variable a call means, by "id" or by "name"
function TApiServer.FindTarget(Params: TJSONObject): TEvalNode;
var
  Id: integer;
  TargetName: string;
begin
  Result := nil;
  if (Params <> nil) and GetJSONInteger(Params, 'id', Id) then
  begin
    Result := FDocument.Pattern.FindNode(IntToStr(Id));
    if not ((Result is TDraftObject) or (Result is TVariable)) then
      raise EApiError.Create(RpcRefused, Format(rsApiUnknownId, [Id]));
    Exit;
  end;
  if (Params = nil) or not GetJSONString(Params, 'name', TargetName) then
    raise EApiError.Create(RpcInvalidParams, rsApiNoTarget);
  Result := FDocument.Pattern.FindObject(TargetName);
  if Result = nil then
    Result := FDocument.Pattern.FindVariable(TargetName);
  if Result = nil then
    raise EApiError.Create(RpcRefused, Format(rsApiUnknownName, [TargetName]));
end;

function TApiServer.DocumentInfo: TJSONObject;
begin
  Result := TJSONObject.Create;
  try
    Result.Add('path', FDocument.FileName);
    Result.Add('measurements', FDocument.MeasurementPath);
    Result.Add('objects', FDocument.Pattern.ObjectCount);
    Result.Add('variables', FDocument.Pattern.VariableCount);
    Result.Add('modified', FDocument.Modified);
    if FDocument.MeasurementError <> '' then
      Result.Add('measurementError', FDocument.MeasurementError);
  except
    FreeAndNil(Result);
    raise;
  end;
end;

function TApiServer.DoOpen(Params: TJSONObject): TJSONData;
var
  Err, Measurements: string;
begin
  Measurements := OptionalString(Params, 'measurements');
  if not FDocument.LoadFromFile(RequireString(Params, 'path'), Err) then
    raise EApiError.Create(RpcRefused, Err);
  if (Measurements <> '') and not FDocument.UseMeasurements(Measurements, Err) then
    raise EApiError.Create(RpcRefused, Err);
  UseSize(OptionalString(Params, 'size'));
  Result := DocumentInfo;
end;

procedure TApiServer.UseSize(const Size: string);
begin
  if (Size <> '') and not FDocument.SelectMeasurementSize(Size) then
    raise EApiError.Create(RpcRefused, Format(rsMeasurementUnknownSize, [Size]));
end;

function TApiServer.DoMissingMeasurements: TJSONData;
var
  Info: TJSONObject;
  List, Sizes: TJSONArray;
  Item: TJSONObject;
  Empty: TMeasurementSet;
  Found: TMissingMeasurement;
  Size: string;
  Lacking: TMissingMeasurementArray;
begin
  Empty := nil;
  Info := TJSONObject.Create;
  try
    List := TJSONArray.Create;
    Info.Add('missing', List);
    if FDocument.Measurements <> nil then
      Lacking := MissingMeasurements(PatternMeasurementKeys(FDocument.Pattern), FDocument.Measurements)
    else
    begin
      Empty := TMeasurementSet.Create;
      Lacking := MissingMeasurements(PatternMeasurementKeys(FDocument.Pattern), Empty);
    end;
    for Found in Lacking do
    begin
      Item := TJSONObject.Create;
      List.Add(Item);
      Item.Add('key', Found.Key);
      Sizes := TJSONArray.Create;
      Item.Add('sizes', Sizes);
      for Size in Found.Sizes do
        Sizes.Add(Size);
    end;
    Result := Info;
  except
    FreeAndNil(Info);
    FreeAndNil(Empty);
    raise;
  end;
  FreeAndNil(Empty);
end;

function TApiServer.DoAddRepeat(Params: TJSONObject): TJSONData;
var
  CountText, First, Second, RepeatName: string;
  IncludeEnds: boolean;
  Added: TRepeatObject;
begin
  CountText := FormulaParam(Params, 'count');
  RepeatName := OptionalString(Params, 'name');
  IncludeEnds := ChoiceParam(Params, 'ends', ['include', 'exclude']) = 0;
  if Params.Find('edge') <> nil then
  begin
    First := Reference(Params, 'edge');
    FDocument.BeginChange(rsApiAddRepeat);
    Added := FDocument.Pattern.AddRepeatOnEdge(RepeatName, First, CountText, IncludeEnds);
  end
  else
  begin
    First := Reference(Params, 'a');
    Second := Reference(Params, 'b');
    FDocument.BeginChange(rsApiAddRepeat);
    Added := FDocument.Pattern.AddRepeatBetween(RepeatName, First, Second, CountText, IncludeEnds);
  end;
  Result := AddedNode(Added);
end;

// Each item is an ID or a name
function TApiServer.ReferenceList(Params: TJSONObject; const AName: string): TStringArray;
var
  List: TJSONData;
  Index: integer;
  Holder: TJSONObject;
begin
  Result := nil;
  List := Params.Find(AName);
  if (List = nil) or (List.JSONType <> jtArray) then
    Exit;
  Holder := TJSONObject.Create;
  try
    for Index := 0 to List.Count - 1 do
    begin
      Holder.Clear;
      Holder.Add(AName, List.Items[Index].Clone);
      Insert(Reference(Holder, AName), Result, Length(Result));
    end;
  finally
    FreeAndNil(Holder);
  end;
end;

function TApiServer.DoArrange(Params: TJSONObject): TJSONData;
var
  Request: TArrangeRequest;
  Replace: TStringArray;
  Items: TArrangeItemArray;
  Item: TArrangeItem;
  Err, Key: string;
  Info: TJSONObject;
  Changed, Asked, Kept: TJSONArray;
  Wanted: boolean;
begin
  Request := Default(TArrangeRequest);
  Request.Action := TArrangeAction(ChoiceParam(Params, 'action', ['alignVertical', 'alignHorizontal', 'distribute', 'distributeHorizontal',
    'distributeVertical', 'distributeAlongEdge']));
  Request.Points := ReferenceList(Params, 'points');
  if Params.Find('reference') <> nil then
    Request.Reference := Reference(Params, 'reference');
  if Params.Find('edge') <> nil then
    Request.Edge := Reference(Params, 'edge');
  Replace := ReferenceList(Params, 'replace');
  if not PlanArrange(FDocument.Pattern, Request, Items, Err) then
    raise EApiError.Create(RpcRefused, Err);
  Info := TJSONObject.Create;
  try
    Changed := TJSONArray.Create;
    Info.Add('changed', Changed);
    Asked := TJSONArray.Create;
    Info.Add('asked', Asked);
    Kept := TJSONArray.Create;
    Info.Add('kept', Kept);
    for Item in Items do
    begin
      Wanted := Item.Choice = acChange;
      if Item.Choice = acAsk then
        for Key in Replace do
          Wanted := Wanted or (Key = Item.Key);
      if Wanted then
        Changed.Add(Item.Name)
      else if Item.Choice = acAsk then
        Asked.Add(Item.Name)
      else
        Kept.Add(Item.Name);
    end;
    FDocument.BeginChange(rsApiArrange);
    if not ApplyArrange(FDocument.Pattern, Request, Replace, Err) then
    begin
      FDocument.CancelChange;
      raise EApiError.Create(RpcRefused, Err);
    end;
    FDocument.Commit(True);
    Result := Info;
  except
    FreeAndNil(Info);
    raise;
  end;
end;

function TApiServer.DoSave(Params: TJSONObject): TJSONData;
var
  Err, Path: string;
begin
  Path := OptionalString(Params, 'path');
  if Path = '' then
    Path := FDocument.FileName;
  if Path = '' then
    raise EApiError.Create(RpcRefused, rsApiNoFileName);
  if not FDocument.SaveToFile(Path, Err) then
    raise EApiError.Create(RpcRefused, Err);
  Result := DocumentInfo;
end;

function TApiServer.DoGetMeasurements: TJSONData;
var
  Info: TJSONObject;
  List: TJSONArray;
  Item: TJSONObject;
  Index: integer;
begin
  Info := TJSONObject.Create;
  try
    Info.Add('path', FDocument.MeasurementPath);
    if (FDocument.Measurements <> nil) and (FDocument.Measurements.SizeCount > 0) then
    begin
      Info.Add('size', FDocument.Measurements.SizeName);
      List := TJSONArray.Create;
      Info.Add('sizes', List);
      for Index := 0 to FDocument.Measurements.SizeCount - 1 do
        List.Add(FDocument.Measurements.Sizes[Index]);
    end;
    List := TJSONArray.Create;
    Info.Add('measurements', List);
    if FDocument.Measurements <> nil then
      for Index := 0 to FDocument.Measurements.Count - 1 do
      begin
        Item := TJSONObject.Create;
        List.Add(Item);
        Item.Add('key', FDocument.Measurements[Index].Key);
        if FDocument.Measurements[Index].HasValue then
          Item.Add('value', JSONFloat(FDocument.Measurements[Index].Value))
        else
          Item.Add('value', TJSONNull.Create);
        Item.Add('description', FDocument.Measurements[Index].Description);
      end;
    Result := Info;
  except
    FreeAndNil(Info);
    raise;
  end;
end;

// Keeps the description when none is given
function TApiServer.DoSetMeasurement(Params: TJSONObject): TJSONData;
var
  Key, Description, Err: string;
  Value: double;
  Existing: TMeasurement;
  Change: TMeasurementChange;
  Info: TJSONObject;
begin
  Key := RequireString(Params, 'key');
  if not GetJSONNumber(Params, 'value', Value) then
    raise EApiError.Create(RpcInvalidParams, Format(rsApiMissingParam, ['value']));
  UseSize(OptionalString(Params, 'size'));
  Description := '';
  Existing := nil;
  if FDocument.Measurements <> nil then
    Existing := FDocument.Measurements.Find(Key);
  if Existing <> nil then
    Description := Existing.Description;
  if Params.Find('description') <> nil then
    Description := RequireString(Params, 'description');
  if not FDocument.ChangeMeasurement(Key, Value, Description, Change, Err) then
    raise EApiError.Create(RpcRefused, Err);
  Info := TJSONObject.Create;
  try
    Info.Add('key', Change.Key);
    Info.Add('value', JSONFloat(Change.Value));
    Info.Add('added', Change.Added);
    if Change.HadValue then
      Info.Add('oldValue', JSONFloat(Change.OldValue));
    Result := Info;
  except
    FreeAndNil(Info);
    raise;
  end;
end;

function TApiServer.DoListObjects: TJSONData;
var
  Info: TJSONObject;
  List: TJSONArray;
  Index: integer;
begin
  Info := TJSONObject.Create;
  try
    List := TJSONArray.Create;
    Info.Add('variables', List);
    for Index := 0 to FDocument.Pattern.VariableCount - 1 do
      List.Add(NodeToJSON(FDocument, FDocument.Pattern.Variables[Index]));
    List := TJSONArray.Create;
    Info.Add('objects', List);
    for Index := 0 to FDocument.Pattern.ObjectCount - 1 do
      List.Add(NodeToJSON(FDocument, FDocument.Pattern.Objects[Index]));
    Result := Info;
  except
    FreeAndNil(Info);
    raise;
  end;
end;

function TApiServer.DoGetObject(Params: TJSONObject): TJSONData;
begin
  Result := NodeToJSON(FDocument, FindTarget(Params));
end;

function TApiServer.DoSetFormula(Params: TJSONObject): TJSONData;
var
  Node: TEvalNode;
  FieldName, Text: string;
  Done: boolean;
begin
  Node := FindTarget(Params);
  FieldName := RequireString(Params, 'field');
  Text := RequireString(Params, 'formula');
  FDocument.BeginChange(Format(rsApiSetFormula, [FieldName]));
  Done := FDocument.Pattern.SetFormula(Node, FieldName, Text);
  if not Done then
    RefuseChange;
  FDocument.EndChange;
  Result := NodeToJSON(FDocument, FindTarget(Params));
end;

function TApiServer.DoRename(Params: TJSONObject): TJSONData;
var
  Node: TEvalNode;
  NewName: string;
begin
  Node := FindTarget(Params);
  NewName := RequireString(Params, 'newName');
  FDocument.BeginChange(rsApiRename);
  if not FDocument.Pattern.Rename(Node, NewName) then
    RefuseChange;
  FDocument.EndChange;
  Result := NodeToJSON(FDocument, FDocument.Pattern.FindNode(Node.Key));
end;

function TApiServer.DoDelete(Params: TJSONObject): TJSONData;
var
  Node: TEvalNode;
begin
  Node := FindTarget(Params);
  FDocument.BeginChange(rsApiDelete);
  if not FDocument.Pattern.Delete(Node) then
    RefuseChange;
  FDocument.EndChange;
  Result := DocumentInfo;
end;

function TApiServer.ProblemsResult(WithReport: boolean): TJSONObject;
var
  Problems: TStringArray;
  Problem: string;
  List: TJSONArray;
  BlockedCount: integer;
begin
  Result := TJSONObject.Create;
  try
    Problems := PatternProblems(FDocument.Pattern, BlockedCount);
    List := TJSONArray.Create;
    Result.Add('problems', List);
    for Problem in Problems do
      List.Add(Problem);
    Result.Add('blocked', BlockedCount);
    if WithReport then
      Result.Add('report', PatternReport(FDocument.Pattern, ExtractFileName(FDocument.FileName), ExtractFileName(FDocument.MeasurementPath)));
  except
    FreeAndNil(Result);
    raise;
  end;
end;

function TApiServer.DoEvaluate(WithReport: boolean): TJSONData;
begin
  FDocument.LiveUpdate;
  Result := ProblemsResult(WithReport);
end;

function TApiServer.DoUndo: TJSONData;
begin
  if not FDocument.Undo then
    raise EApiError.Create(RpcRefused, rsApiNothingToUndo);
  Result := DocumentInfo;
end;

function TApiServer.DoRedo: TJSONData;
begin
  if not FDocument.Redo then
    raise EApiError.Create(RpcRefused, rsApiNothingToRedo);
  Result := DocumentInfo;
end;

// The SVG comes back in the reply: file access is for open, save and export
function TApiServer.DoRender(Params: TJSONObject): TJSONData;
var
  Options: TDraftSVGOptions;
  Region: TJSONData;
  RegionItem: TJSONObject;
  RenderFormat: string;
  Info: TJSONObject;
begin
  RenderFormat := OptionalString(Params, 'format');
  if (RenderFormat <> '') and (RenderFormat <> RenderFormatSVG) then
    raise EApiError.Create(RpcRefused, Format(rsApiRenderFormat, [RenderFormat]));
  Options := DefaultDraftSVGOptions;
  if Params <> nil then
  begin
    GetJSONBoolean(Params, 'labels', Options.Labels);
    Region := Params.Find('region');
    if Region <> nil then
    begin
      if Region.JSONType <> jtObject then
        raise EApiError.Create(RpcInvalidParams, rsApiBadRegion);
      RegionItem := TJSONObject(Region);
      if not GetJSONNumber(RegionItem, 'minX', Options.Region.MinX) or not GetJSONNumber(RegionItem, 'minY', Options.Region.MinY) or
        not GetJSONNumber(RegionItem, 'maxX', Options.Region.MaxX) or not GetJSONNumber(RegionItem, 'maxY', Options.Region.MaxY) or
        (Options.Region.MaxX <= Options.Region.MinX) or (Options.Region.MaxY <= Options.Region.MinY) then
        raise EApiError.Create(RpcInvalidParams, rsApiBadRegion);
      Options.HasRegion := True;
    end;
  end;
  Info := TJSONObject.Create;
  try
    Info.Add('format', RenderFormatSVG);
    Info.Add('svg', DraftToSVG(FDocument.Pattern, Options));
    Result := Info;
  except
    FreeAndNil(Info);
    raise;
  end;
end;

function TApiServer.DoAddVariable(Params: TJSONObject): TJSONData;
var
  VariableName, Formula, Description: string;
begin
  VariableName := RequireString(Params, 'name');
  Formula := FormulaParam(Params, 'formula');
  Description := OptionalString(Params, 'description');
  FDocument.BeginChange(Format(rsApiAdd, [VariableType]));
  Result := AddedNode(FDocument.Pattern.AddVariable(VariableName, Formula, Description));
end;

// Fields as in a pattern file. Inputs are read before the change opens, since
// a bad one raises.
function TApiServer.DoAddPoint(Params: TJSONObject): TJSONData;
var
  Pattern: TPattern;
  TypeName, PointName, First, Second, FormulaA, FormulaB: string;
  Mode, Direction: integer;
  FlagA, FlagB, FromEnd: boolean;
  Pick: integer;
  Added: TEvalNode;
begin
  Pattern := FDocument.Pattern;
  TypeName := RequireString(Params, 'type');
  PointName := OptionalString(Params, 'name');
  case TypeName of
    'freePoint':
    begin
      FormulaA := FormulaParam(Params, 'x');
      FormulaB := FormulaParam(Params, 'y');
      FDocument.BeginChange(Format(rsApiAdd, [TypeName]));
      Added := Pattern.AddFreePoint(PointName, FormulaA, FormulaB);
    end;
    'offsetPoint':
    begin
      First := Reference(Params, 'base');
      Mode := ChoiceParam(Params, 'mode', ['polar', 'cartesian']);
      if TOffsetMode(Mode) = omPolar then
      begin
        FormulaA := FormulaParam(Params, 'length');
        FormulaB := FormulaParam(Params, 'angle');
      end
      else
      begin
        FormulaA := FormulaParam(Params, 'dx');
        FormulaB := FormulaParam(Params, 'dy');
      end;
      FDocument.BeginChange(Format(rsApiAdd, [TypeName]));
      Added := Pattern.AddOffsetPoint(PointName, First, TOffsetMode(Mode), FormulaA, FormulaB);
    end;
    'alongEdgePoint':
    begin
      First := Reference(Params, 'edge');
      FromEnd := ChoiceParam(Params, 'from', ['start', 'end']) = 1;
      Mode := ChoiceParam(Params, 'mode', ['length', 'ratio']);
      FormulaA := FormulaParam(Params, 'value');
      FDocument.BeginChange(Format(rsApiAdd, [TypeName]));
      Added := Pattern.AddAlongEdgePoint(PointName, First, FromEnd, TAlongMode(Mode), FormulaA);
    end;
    'betweenPoint':
    begin
      First := Reference(Params, 'a');
      Second := Reference(Params, 'b');
      Mode := ChoiceParam(Params, 'mode', ['length', 'ratio']);
      FormulaA := FormulaParam(Params, 'value');
      FDocument.BeginChange(Format(rsApiAdd, [TypeName]));
      Added := Pattern.AddBetweenPoint(PointName, First, Second, TAlongMode(Mode), FormulaA);
    end;
    'intersectPoint':
    begin
      First := Reference(Params, 'edgeA');
      Second := Reference(Params, 'edgeB');
      FlagA := BooleanParam(Params, 'extendA');
      FlagB := BooleanParam(Params, 'extendB');
      Pick := PickParam(Params);
      FDocument.BeginChange(Format(rsApiAdd, [TypeName]));
      Added := Pattern.AddIntersectPoint(PointName, First, Second, FlagA, FlagB, Pick);
    end;
    'circleEdgePoint':
    begin
      First := Reference(Params, 'centre');
      FormulaA := FormulaParam(Params, 'radius');
      Second := Reference(Params, 'edge');
      FlagA := BooleanParam(Params, 'extend');
      Pick := PickParam(Params);
      FDocument.BeginChange(Format(rsApiAdd, [TypeName]));
      Added := Pattern.AddCircleEdgePoint(PointName, First, FormulaA, Second, FlagA, Pick);
    end;
    'projectPoint':
    begin
      First := Reference(Params, 'point');
      Second := Reference(Params, 'edge');
      Direction := ChoiceParam(Params, 'direction', ['perpendicular', 'angle']);
      FormulaA := '';
      if TProjectDirection(Direction) = pdAngle then
        FormulaA := FormulaParam(Params, 'angle');
      FlagA := BooleanParam(Params, 'extend');
      FDocument.BeginChange(Format(rsApiAdd, [TypeName]));
      Added := Pattern.AddProjectPoint(PointName, First, Second, TProjectDirection(Direction), FormulaA, FlagA);
    end;
    else
      raise EApiError.Create(RpcInvalidParams, Format(rsApiUnknownType,
        [TypeName, 'freePoint, offsetPoint, alongEdgePoint, intersectPoint, circleEdgePoint, projectPoint']));
  end;
  Result := AddedNode(Added);
end;

function TApiServer.DoAddEdge(Params: TJSONObject): TJSONData;
var
  Pattern: TPattern;
  TypeName, EdgeName, First, Second: string;
  Angle1, Length1, Angle2, Length2: string;
  Role: TEdgeRole;
  Nodes: TJSONData;
  Item: TJSONObject;
  NodeKeys, Angles, LengthsIn, LengthsOut: TStringArray;
  Index: integer;
  Added: TEvalNode;
begin
  Pattern := FDocument.Pattern;
  TypeName := RequireString(Params, 'type');
  EdgeName := OptionalString(Params, 'name');
  Role := RoleParam(Params);
  case TypeName of
    'line':
    begin
      First := Reference(Params, 'start');
      Second := Reference(Params, 'end');
      FDocument.BeginChange(Format(rsApiAdd, [TypeName]));
      Added := Pattern.AddLine(First, Second, Role, EdgeName);
    end;
    'curve':
    begin
      First := Reference(Params, 'start');
      Second := Reference(Params, 'end');
      Angle1 := FormulaParam(Params, 'angle1');
      Length1 := FormulaParam(Params, 'length1');
      Angle2 := FormulaParam(Params, 'angle2');
      Length2 := FormulaParam(Params, 'length2');
      FDocument.BeginChange(Format(rsApiAdd, [TypeName]));
      Added := Pattern.AddCurve(First, Second, Angle1, Length1, Angle2, Length2, Role, EdgeName);
    end;
    'curvePath':
    begin
      Nodes := Params.Find('nodes');
      if (Nodes = nil) or (Nodes.JSONType <> jtArray) then
        raise EApiError.Create(RpcInvalidParams, rsApiBadNodes);
      NodeKeys := nil;
      Angles := nil;
      LengthsIn := nil;
      LengthsOut := nil;
      SetLength(NodeKeys, Nodes.Count);
      SetLength(Angles, Nodes.Count);
      SetLength(LengthsIn, Nodes.Count);
      SetLength(LengthsOut, Nodes.Count);
      for Index := 0 to Nodes.Count - 1 do
      begin
        if Nodes.Items[Index].JSONType <> jtObject then
          raise EApiError.Create(RpcInvalidParams, rsApiBadNodes);
        Item := TJSONObject(Nodes.Items[Index]);
        NodeKeys[Index] := Reference(Item, 'point');
        Angles[Index] := FormulaParam(Item, 'angle');
        LengthsIn[Index] := OptionalFormula(Item, 'lengthIn');
        LengthsOut[Index] := OptionalFormula(Item, 'lengthOut');
      end;
      FDocument.BeginChange(Format(rsApiAdd, [TypeName]));
      Added := Pattern.AddCurvePath(NodeKeys, Angles, LengthsIn, LengthsOut, Role, EdgeName);
    end;
    else
      raise EApiError.Create(RpcInvalidParams, Format(rsApiUnknownType, [TypeName, 'line, curve, curvePath']));
  end;
  Result := AddedNode(Added);
end;

function TApiServer.DoSplitEdge(Params: TJSONObject): TJSONData;
var
  Edge, Point, FirstKey, SecondKey: string;
  First, Second: TSplitPart;
  Parts: TJSONArray;
begin
  Edge := Reference(Params, 'edge');
  Point := Reference(Params, 'point');
  FDocument.BeginChange(rsApiSplit);
  if not FDocument.Pattern.SplitEdge(Edge, Point, First, Second) then
    RefuseChange;
  FirstKey := First.Key;
  SecondKey := Second.Key;
  FDocument.EndChange;
  Parts := TJSONArray.Create;
  try
    Parts.Add(NodeToJSON(FDocument, FDocument.Pattern.FindNode(FirstKey)));
    Parts.Add(NodeToJSON(FDocument, FDocument.Pattern.FindNode(SecondKey)));
    Result := Parts;
  except
    FreeAndNil(Parts);
    raise;
  end;
end;

function TApiServer.DoCreatePiece(Params: TJSONObject): TJSONData;
var
  At: TVec2;
  Path: TPiecePath;
  PieceName, Allowance, Reason: string;
  Existing: TPieceObject;
begin
  if not GetJSONNumber(Params, 'x', At.X) then
    raise EApiError.Create(RpcInvalidParams, Format(rsApiMissingParam, ['x']));
  if not GetJSONNumber(Params, 'y', At.Y) then
    raise EApiError.Create(RpcInvalidParams, Format(rsApiMissingParam, ['y']));
  PieceName := OptionalString(Params, 'name');
  Allowance := OptionalFormula(Params, PieceAllowanceField);
  if Allowance = '' then
    Allowance := DefaultPieceAllowance;
  if not DetectPiecePath(FDocument.Pattern, At, Path, Reason) then
    raise EApiError.Create(RpcRefused, Reason);
  Existing := PieceOnPath(FDocument.Pattern, Path);
  if Existing <> nil then
    raise EApiError.Create(RpcRefused, Format(rsApiPieceExists, [Existing.DisplayName]));
  FDocument.BeginChange(Format(rsApiAdd, [PieceType]));
  Result := AddedNode(FDocument.Pattern.AddPiece(PieceName, Path, Allowance));
end;

function TApiServer.TargetPiece(Params: TJSONObject): TPieceObject;
var
  Target: TEvalNode;
begin
  Target := FindTarget(Params);
  if not (Target is TPieceObject) then
    raise EApiError.Create(RpcRefused, Format(rsApiNotAPiece, [Target.DisplayName]));
  Result := TPieceObject(Target);
end;

function TApiServer.DoSetGrainline(Params: TJSONObject): TJSONData;
var
  Piece: TPieceObject;
  First, Second, Angle: string;
  Done: boolean;
begin
  Piece := TargetPiece(Params);
  if BooleanParam(Params, 'none') then
  begin
    FDocument.BeginChange(rsApiGrainline);
    FDocument.Pattern.ClearGrain(Piece);
    Exit(AddedNode(Piece));
  end;
  Angle := OptionalFormula(Params, 'angle');
  if (Angle = '') and (Params.Find('start') = nil) then
    raise EApiError.Create(RpcInvalidParams, rsApiBadGrainline);
  if Angle <> '' then
  begin
    FDocument.BeginChange(rsApiGrainline);
    Done := FDocument.Pattern.SetGrainAngle(Piece, Angle);
  end
  else
  begin
    First := Reference(Params, 'start');
    Second := Reference(Params, 'end');
    FDocument.BeginChange(rsApiGrainline);
    Done := FDocument.Pattern.SetGrainPoints(Piece, First, Second);
  end;
  if not Done then
    RefuseChange;
  Result := AddedNode(Piece);
end;

function TApiServer.DoAddNotch(Params: TJSONObject): TJSONData;
var
  Piece: TPieceObject;
  Key, Position: string;
  Done: boolean;
begin
  Piece := TargetPiece(Params);
  if Params.Find('point') <> nil then
  begin
    Key := Reference(Params, 'point');
    FDocument.BeginChange(rsApiAddNotch);
    Done := FDocument.Pattern.AddPointNotch(Piece, Key);
  end
  else
  begin
    if (Params.Find('edge') = nil) or (Params.Find('position') = nil) then
      raise EApiError.Create(RpcInvalidParams, rsApiBadNotch);
    Key := Reference(Params, 'edge');
    Position := FormulaParam(Params, 'position');
    FDocument.BeginChange(rsApiAddNotch);
    Done := FDocument.Pattern.AddEdgeNotch(Piece, Key, Position);
  end;
  if not Done then
    RefuseChange;
  Result := AddedNode(Piece);
end;

// Notches count from 1, as in the field names
function TApiServer.DoRemoveNotch(Params: TJSONObject): TJSONData;
var
  Piece: TPieceObject;
  Index: integer;
begin
  Piece := TargetPiece(Params);
  if not GetJSONInteger(Params, 'notch', Index) then
    raise EApiError.Create(RpcInvalidParams, Format(rsApiMissingParam, ['notch']));
  FDocument.BeginChange(rsApiRemoveNotch);
  if not FDocument.Pattern.RemoveNotch(Piece, Index - 1) then
    RefuseChange;
  Result := AddedNode(Piece);
end;

// Either can be left out, keeping what the piece has
function TApiServer.DoSetCut(Params: TJSONObject): TJSONData;
var
  Piece: TPieceObject;
  Count: integer;
  Mirrored: boolean;
begin
  Piece := TargetPiece(Params);
  Count := Piece.CutCount;
  Mirrored := Piece.Mirrored;
  if (Params.Find('count') <> nil) and not GetJSONInteger(Params, 'count', Count) then
    raise EApiError.Create(RpcInvalidParams, Format(rsApiMissingParam, ['count']));
  if Params.Find('mirrored') <> nil then
    Mirrored := BooleanParam(Params, 'mirrored');
  FDocument.BeginChange(rsApiCut);
  if not FDocument.Pattern.SetCut(Piece, Count, Mirrored) then
    RefuseChange;
  Result := AddedNode(Piece);
end;

function TApiServer.DoSetFold(Params: TJSONObject): TJSONData;
var
  Piece: TPieceObject;
  Edge: string;
begin
  Piece := TargetPiece(Params);
  Edge := '';
  if not BooleanParam(Params, 'none') then
  begin
    if Params.Find('edge') = nil then
      raise EApiError.Create(RpcInvalidParams, rsApiBadFold);
    Edge := Reference(Params, 'edge');
  end;
  FDocument.BeginChange(rsApiFold);
  if not FDocument.Pattern.SetFoldEdge(Piece, Edge) then
    RefuseChange;
  Result := AddedNode(Piece);
end;

function TApiServer.SeamSideParam(Params: TJSONObject; const AName: string): TSeamSide;
var
  List: TJSONData;
  Index: integer;
begin
  Result := nil;
  List := Params.Find(AName);
  if (List = nil) or (List.JSONType <> jtArray) then
    raise EApiError.Create(RpcInvalidParams, Format(rsApiBadSeamSide, [AName]));
  SetLength(Result, List.Count);
  for Index := 0 to List.Count - 1 do
  begin
    if List.Items[Index].JSONType <> jtObject then
      raise EApiError.Create(RpcInvalidParams, Format(rsApiBadSeamSide, [AName]));
    Result[Index].PieceKey := Reference(TJSONObject(List.Items[Index]), 'piece');
    Result[Index].EdgeKey := Reference(TJSONObject(List.Items[Index]), 'edge');
  end;
end;

function TApiServer.DoAddSeam(Params: TJSONObject): TJSONData;
var
  SideA, SideB: TSeamSide;
  Ease, Tolerance: string;
begin
  SideA := SeamSideParam(Params, 'sideA');
  SideB := SeamSideParam(Params, 'sideB');
  Ease := OptionalFormula(Params, SeamEaseField);
  if Ease = '' then
    Ease := DefaultSeamEase;
  Tolerance := OptionalFormula(Params, SeamToleranceField);
  if Tolerance = '' then
    Tolerance := DefaultSeamTolerance;
  FDocument.BeginChange(Format(rsApiAdd, [SeamType]));
  Result := AddedNode(FDocument.Pattern.AddSeam(OptionalString(Params, 'name'), SideA, SideB, Ease, Tolerance));
end;

function TApiServer.DoFlipSeam(Params: TJSONObject): TJSONData;
var
  Target: TEvalNode;
begin
  Target := FindTarget(Params);
  if not (Target is TSeamObject) then
    raise EApiError.Create(RpcRefused, Format(rsApiNotASeam, [Target.DisplayName]));
  FDocument.BeginChange(rsApiFlipSeam);
  TSeamObject(Target).Reversed := not TSeamObject(Target).Reversed;
  Result := AddedNode(Target);
end;

// Names, so that a suggestion can go straight back to add_seam
function TApiServer.DoSuggestSeams: TJSONData;
var
  Reply, Item: TJSONObject;
  List, Side: TJSONArray;
  Suggestion: TSeamSuggestion;
begin
  FDocument.LiveUpdate;
  Reply := TJSONObject.Create;
  try
    List := TJSONArray.Create;
    Reply.Add('suggestions', List);
    for Suggestion in SuggestSeams(FDocument.Pattern) do
    begin
      Item := TJSONObject.Create;
      List.Add(Item);
      Side := TJSONArray.Create;
      Item.Add('sideA', Side);
      Side.Add(SeamEntryToJSON(FDocument.Pattern, Suggestion.First));
      Side := TJSONArray.Create;
      Item.Add('sideB', Side);
      Side.Add(SeamEntryToJSON(FDocument.Pattern, Suggestion.Second));
      Item.Add('shared', Suggestion.Shared);
      Item.Add('difference', ReportFloat(Suggestion.Difference));
    end;
  except
    FreeAndNil(Reply);
    raise;
  end;
  Result := Reply;
end;

// An empty or missing allowance puts the edge back on the piece's own
function TApiServer.DoSetEdgeAllowance(Params: TJSONObject): TJSONData;
var
  Target: TEvalNode;
  Edge, Allowance: string;
  PathIndex: integer;
begin
  Target := TargetPiece(Params);
  Edge := Reference(Params, 'edge');
  PathIndex := TPieceObject(Target).PathIndexOf(Edge);
  if PathIndex < 0 then
    raise EApiError.Create(RpcRefused, Format(rsApiNotInPiece, [FDocument.Pattern.FindNode(Edge).DisplayName, Target.DisplayName]));
  Allowance := OptionalFormula(Params, PieceAllowanceField);
  FDocument.BeginChange(rsApiEdgeAllowance);
  if not FDocument.Pattern.SetEdgeAllowance(TPieceObject(Target), PathIndex, Allowance) then
    RefuseChange;
  Result := AddedNode(Target);
end;

function TApiServer.CallMethod(const Method: string; Params: TJSONObject): TJSONData;
begin
  case Method of
    'open': Result := DoOpen(Params);
    'save': Result := DoSave(Params);
    'get_measurements': Result := DoGetMeasurements;
    'arrange': Result := DoArrange(Params);
    'add_repeat': Result := DoAddRepeat(Params);
    'set_measurement': Result := DoSetMeasurement(Params);
    'missing_measurements': Result := DoMissingMeasurements;
    'list_objects': Result := DoListObjects;
    'get_object': Result := DoGetObject(Params);
    'set_formula': Result := DoSetFormula(Params);
    'rename': Result := DoRename(Params);
    'delete': Result := DoDelete(Params);
    'evaluate': Result := DoEvaluate(False);
    'check': Result := DoEvaluate(True);
    'undo': Result := DoUndo;
    'redo': Result := DoRedo;
    'render': Result := DoRender(Params);
    'add_variable': Result := DoAddVariable(Params);
    'add_point': Result := DoAddPoint(Params);
    'add_edge': Result := DoAddEdge(Params);
    'split_edge': Result := DoSplitEdge(Params);
    'create_piece': Result := DoCreatePiece(Params);
    'set_edge_allowance': Result := DoSetEdgeAllowance(Params);
    'set_grainline': Result := DoSetGrainline(Params);
    'add_notch': Result := DoAddNotch(Params);
    'remove_notch': Result := DoRemoveNotch(Params);
    'set_cut': Result := DoSetCut(Params);
    'set_fold': Result := DoSetFold(Params);
    'add_seam': Result := DoAddSeam(Params);
    'flip_seam': Result := DoFlipSeam(Params);
    'suggest_seams': Result := DoSuggestSeams;
    else
      raise EApiError.Create(RpcMethodNotFound, Format(rsApiNoMethod, [Method]));
  end;
end;

function ErrorResponse(Id: TJSONData; Code: integer; const AMessage, FieldName: string; Position: integer): string;
var
  Response, Error, Data: TJSONObject;
begin
  Response := TJSONObject.Create;
  try
    Response.Add('jsonrpc', '2.0');
    if Id <> nil then
      Response.Add('id', Id.Clone)
    else
      Response.Add('id', TJSONNull.Create);
    Error := TJSONObject.Create;
    Response.Add('error', Error);
    Error.Add('code', Code);
    Error.Add('message', AMessage);
    if (FieldName <> '') or (Position > 0) then
    begin
      Data := TJSONObject.Create;
      Error.Add('data', Data);
      Data.Add('field', FieldName);
      Data.Add('position', Position);
    end;
    Result := Response.AsJSON;
  finally
    FreeAndNil(Response);
  end;
end;

function TApiServer.HandleLine(const Line: string): string;
var
  Request: TJSONObject;
  Err, Method: string;
  Id, ParamsData, Output: TJSONData;
  Params, OwnParams: TJSONObject;
  Response: TJSONObject;
begin
  OwnParams := nil;
  if not ParseJSONObject(Line, Request, Err) then
    Exit(ErrorResponse(nil, RpcParseError, Err, '', 0));
  try
    Id := Request.Find('id');
    if not GetJSONString(Request, 'method', Method) then
      Exit(ErrorResponse(Id, RpcInvalidRequest, rsApiNotRequest, '', 0));
    ParamsData := Request.Find('params');
    if (ParamsData <> nil) and (ParamsData.JSONType <> jtObject) then
      Exit(ErrorResponse(Id, RpcInvalidParams, Format(rsApiMissingParam, ['params']), '', 0));
    // Methods read members straight from it, so a request without any gets an empty one
    OwnParams := nil;
    if ParamsData = nil then
    begin
      OwnParams := TJSONObject.Create;
      ParamsData := OwnParams;
    end;
    Params := TJSONObject(ParamsData);
    Output := nil;
    try
      try
        Output := CallMethod(Method, Params);
        if Id = nil then
          Exit('');
        Response := TJSONObject.Create;
        try
          Response.Add('jsonrpc', '2.0');
          Response.Add('id', Id.Clone);
          Response.Add('result', Output);
          Output := nil;
          Result := Response.AsJSON;
        finally
          FreeAndNil(Response);
        end;
      except
        on Failure: EApiError do
          Result := ErrorResponse(Id, Failure.Code, Failure.Message, Failure.FieldName, Failure.Position);
        on Failure: Exception do
          Result := ErrorResponse(Id, RpcInternalError, Failure.Message, '', 0);
      end;
    finally
      FreeAndNil(Output);
    end;
  finally
    FreeAndNil(OwnParams);
    FreeAndNil(Request);
  end;
end;

end.
