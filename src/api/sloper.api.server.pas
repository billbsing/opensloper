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
  SysUtils, fpjson, Sloper.Core.Evaluator, Sloper.Document.PatternDocument;

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
    procedure Refused;
    function DoOpen(Params: TJSONObject): TJSONData;
    function DoSave(Params: TJSONObject): TJSONData;
    function DoGetMeasurements: TJSONData;
    function DoSetMeasurement(Params: TJSONObject): TJSONData;
    function DoListObjects: TJSONData;
    function DoGetObject(Params: TJSONObject): TJSONData;
    function DoSetFormula(Params: TJSONObject): TJSONData;
    function DoRename(Params: TJSONObject): TJSONData;
    function DoDelete(Params: TJSONObject): TJSONData;
    function DoEvaluate(WithReport: boolean): TJSONData;
    function DoUndo: TJSONData;
    function DoRedo: TJSONData;
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

implementation

uses
  Sloper.Core.EvalTypes, Sloper.Core.JSON, Sloper.Core.Measurements, Sloper.Core.PatternCheck, Sloper.Core.PatternFile, Sloper.Core.Pattern,
  Sloper.Core.Variables, Sloper.Core.Draft;

const
  VariableType = 'variable';

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

// Name, type, state and what it computes to, then its formulas with names
function NodeToJSON(Document: TPatternDocument; Node: TEvalNode): TJSONObject;
var
  Formulas: TJSONObject;
  Index: integer;
  FieldName: string;
begin
  Result := TJSONObject.Create;
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
      Result.Add('length', ReportFloat(TEdgeObject(Node).Length));
  Formulas := TJSONObject.Create;
  Result.Add('formulas', Formulas);
  for Index := 0 to Node.FieldCount - 1 do
  begin
    FieldName := Node.Fields[Index].Name;
    Formulas.Add(FieldName, Document.Pattern.FormulaText(Node, FieldName));
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

// The reason the pattern gave for the last refused call
procedure TApiServer.Refused;
var
  Pattern: TPattern;
begin
  Pattern := FDocument.Pattern;
  raise EApiError.Create(RpcRefused, Pattern.LastError, Pattern.LastErrorField, Pattern.LastErrorPos);
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
  Result.Add('path', FDocument.FileName);
  Result.Add('measurements', FDocument.MeasurementPath);
  Result.Add('objects', FDocument.Pattern.ObjectCount);
  Result.Add('variables', FDocument.Pattern.VariableCount);
  Result.Add('modified', FDocument.Modified);
  if FDocument.MeasurementError <> '' then
    Result.Add('measurementError', FDocument.MeasurementError);
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
  Result := DocumentInfo;
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
  Result := Info;
  Info.Add('path', FDocument.MeasurementPath);
  List := TJSONArray.Create;
  Info.Add('measurements', List);
  if FDocument.Measurements = nil then
    Exit;
  for Index := 0 to FDocument.Measurements.Count - 1 do
  begin
    Item := TJSONObject.Create;
    Item.Add('key', FDocument.Measurements[Index].Key);
    Item.Add('value', JSONFloat(FDocument.Measurements[Index].Value));
    Item.Add('description', FDocument.Measurements[Index].Description);
    List.Add(Item);
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
  Result := Info;
  Info.Add('key', Change.Key);
  Info.Add('value', JSONFloat(Change.Value));
  Info.Add('added', Change.Added);
  if not Change.Added then
    Info.Add('oldValue', JSONFloat(Change.OldValue));
end;

function TApiServer.DoListObjects: TJSONData;
var
  Info: TJSONObject;
  List: TJSONArray;
  Index: integer;
begin
  Info := TJSONObject.Create;
  Result := Info;
  List := TJSONArray.Create;
  Info.Add('variables', List);
  for Index := 0 to FDocument.Pattern.VariableCount - 1 do
    List.Add(NodeToJSON(FDocument, FDocument.Pattern.Variables[Index]));
  List := TJSONArray.Create;
  Info.Add('objects', List);
  for Index := 0 to FDocument.Pattern.ObjectCount - 1 do
    List.Add(NodeToJSON(FDocument, FDocument.Pattern.Objects[Index]));
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
  begin
    FDocument.CancelChange;
    Refused;
  end;
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
  begin
    FDocument.CancelChange;
    Refused;
  end;
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
  begin
    FDocument.CancelChange;
    Refused;
  end;
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
  Problems := PatternProblems(FDocument.Pattern, BlockedCount);
  List := TJSONArray.Create;
  Result.Add('problems', List);
  for Problem in Problems do
    List.Add(Problem);
  Result.Add('blocked', BlockedCount);
  if WithReport then
    Result.Add('report', PatternReport(FDocument.Pattern, ExtractFileName(FDocument.FileName), ExtractFileName(FDocument.MeasurementPath)));
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

function TApiServer.CallMethod(const Method: string; Params: TJSONObject): TJSONData;
begin
  case Method of
    'open': Result := DoOpen(Params);
    'save': Result := DoSave(Params);
    'get_measurements': Result := DoGetMeasurements;
    'set_measurement': Result := DoSetMeasurement(Params);
    'list_objects': Result := DoListObjects;
    'get_object': Result := DoGetObject(Params);
    'set_formula': Result := DoSetFormula(Params);
    'rename': Result := DoRename(Params);
    'delete': Result := DoDelete(Params);
    'evaluate': Result := DoEvaluate(False);
    'check': Result := DoEvaluate(True);
    'undo': Result := DoUndo;
    'redo': Result := DoRedo;
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
  Params: TJSONObject;
  Response: TJSONObject;
begin
  if not ParseJSONObject(Line, Request, Err) then
    Exit(ErrorResponse(nil, RpcParseError, Err, '', 0));
  try
    Id := Request.Find('id');
    if not GetJSONString(Request, 'method', Method) then
      Exit(ErrorResponse(Id, RpcInvalidRequest, rsApiNotRequest, '', 0));
    ParamsData := Request.Find('params');
    if (ParamsData <> nil) and (ParamsData.JSONType <> jtObject) then
      Exit(ErrorResponse(Id, RpcInvalidParams, Format(rsApiMissingParam, ['params']), '', 0));
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
    FreeAndNil(Request);
  end;
end;

end.
