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
  SysUtils, fpjson, Sloper.API.Rpc, Sloper.Core.Evaluator, Sloper.Core.Materials, Sloper.Core.Piece, Sloper.Core.Seam, Sloper.Document.PatternDocument;

type
  EApiError = class(Exception)
  public
    Code: integer;
    FieldName: string;
    Position: integer;
    constructor Create(ACode: integer; const AMessage: string; const AFieldName: string = ''; APosition: integer = 0);
  end;

  // What answers API calls: the server with its document, or a connection to
  // the design window's
  TApiBackend = class
  public
    // The method's result, or EApiError when it is refused
    function CallMethod(const Method: string; Params: TJSONObject): TJSONData; virtual; abstract;
    // The response to one line, on one line; '' for a notification, which has
    // no id and gets no reply
    function HandleLine(const Line: string): string; virtual; abstract;
  end;

  // Asked before a file is written; False refuses the call
  TApiConfirmWrite = function(const Path: string): boolean of object;
  // The design window's state for ui_state
  TApiWindowState = function: TJSONObject of object;

  TApiServer = class(TApiBackend)
  private
    FDocument: TPatternDocument;
    FOwnsDocument: boolean;
    FChangePrefix: string;
    FOpensFiles: boolean;
    FOnConfirmWrite: TApiConfirmWrite;
    FOnWindowState: TApiWindowState;
    // The call's change was opened by Reference, to give a repeat point its
    // ID; the method's own BeginChange takes it over
    FEarlyChange: boolean;
    // Opens a change on the document, refusing while the user has one open;
    // CheckLocks as in TPatternDocument.BeginChange
    procedure BeginChange(const Description: string; CheckLocks: boolean = True);
    // Ends the change, raising the reason when it was refused for changing a
    // locked object
    procedure EndChange;
    procedure ConfirmWrite(const Path: string);
    function DoWindowState: TJSONData;
    function FindTarget(Params: TJSONObject): TEvalNode;
    function DocumentInfo: TJSONObject;
    function ProblemsResult(WithReport: boolean): TJSONObject;
    // Cancels the open change and raises the pattern's reason for refusing it
    procedure RefuseChange;
    function Reference(Params: TJSONObject; const AName: string; Use: boolean = True): string;
    function AddedNode(Node: TEvalNode): TJSONData;
    function DoOpen(Params: TJSONObject): TJSONData;
    function DoSave(Params: TJSONObject): TJSONData;
    function DoGetMeasurements: TJSONData;
    function DoMissingMeasurements: TJSONData;
    function DoAddRepeat(Params: TJSONObject): TJSONData;
    function DoArrange(Params: TJSONObject): TJSONData;
    function ReferenceList(Params: TJSONObject; const AName: string; Use: boolean = True): TStringArray;
    // Selects it, refusing one the set does not have; empty leaves it alone
    procedure UseSize(const Size: string);
    function DoSetMeasurement(Params: TJSONObject): TJSONData;
    function DoListObjects: TJSONData;
    function DoGetObject(Params: TJSONObject): TJSONData;
    function DoSetFormula(Params: TJSONObject): TJSONData;
    function DoRename(Params: TJSONObject): TJSONData;
    function DoDelete(Params: TJSONObject): TJSONData;
    function DoSetLocked(Params: TJSONObject): TJSONData;
    function DoEvaluate(WithReport: boolean): TJSONData;
    function DoUndo: TJSONData;
    function DoRedo: TJSONData;
    function DoRender(Params: TJSONObject): TJSONData;
    function RenderGarment(Params: TJSONObject; const RenderFormat: string): TJSONData;
    function DoAddVariable(Params: TJSONObject): TJSONData;
    function DoAddPoint(Params: TJSONObject): TJSONData;
    function DoAddEdge(Params: TJSONObject): TJSONData;
    function DoSplitEdge(Params: TJSONObject): TJSONData;
    function DoAddRectangle(Params: TJSONObject): TJSONData;
    function DoRoundCorner(Params: TJSONObject): TJSONData;
    function DoCreatePiece(Params: TJSONObject): TJSONData;
    function DoSetEdgeAllowance(Params: TJSONObject): TJSONData;
    function TargetPiece(Params: TJSONObject): TPieceObject;
    function DoSetGrainline(Params: TJSONObject): TJSONData;
    function DoAddNotch(Params: TJSONObject): TJSONData;
    function DoRemoveNotch(Params: TJSONObject): TJSONData;
    function DoAddMarking(Params: TJSONObject): TJSONData;
    function DoRemoveMarking(Params: TJSONObject): TJSONData;
    function DoSetCut(Params: TJSONObject): TJSONData;
    function DoSetFold(Params: TJSONObject): TJSONData;
    function DoConvertEdge(Params: TJSONObject): TJSONData;
    function DoSetRole(Params: TJSONObject): TJSONData;
    function DoSetMarker(Params: TJSONObject): TJSONData;
    function DoMergePoints(Params: TJSONObject): TJSONData;
    function DoBreakPoint(Params: TJSONObject): TJSONData;
    function DoCopyObjects(Params: TJSONObject): TJSONData;
    function DoPasteObjects(Params: TJSONObject): TJSONData;
    function FindMaterialParam(Params: TJSONObject; const AName: string): TPatternMaterial;
    function MaterialsToJSON: TJSONData;
    function DoAddMaterial(Params: TJSONObject): TJSONData;
    function DoRenameMaterial(Params: TJSONObject): TJSONData;
    function DoSetMaterial(Params: TJSONObject): TJSONData;
    function DoDeleteMaterial(Params: TJSONObject): TJSONData;
    function DoSetPieceMaterial(Params: TJSONObject): TJSONData;
    function DoSetPieceFill(Params: TJSONObject): TJSONData;
    function DoAddTransform(Params: TJSONObject): TJSONData;
    function SeamSideParam(Params: TJSONObject; const AName: string): TSeamSide;
    function DoAddSeam(Params: TJSONObject): TJSONData;
    function DoFlipSeam(Params: TJSONObject): TJSONData;
    function DoSuggestSeams: TJSONData;
    function DoAddNote(Params: TJSONObject): TJSONData;
    function DoSetText(Params: TJSONObject): TJSONData;
    function DoExport(Params: TJSONObject): TJSONData;
    function DoConvertUnits(Params: TJSONObject): TJSONData;
    // Runs the method by name, for CallMethod
    function DispatchMethod(const Method: string; Params: TJSONObject): TJSONData;
  public
    // With a document of its own, empty until open
    constructor Create;
    // On the design window's document, which it does not free
    constructor CreateFor(ADocument: TPatternDocument);
    destructor Destroy; override;
    function CallMethod(const Method: string; Params: TJSONObject): TJSONData; override;
    function HandleLine(const Line: string): string; override;
    property Document: TPatternDocument read FDocument;
    // Put before each change's description in the undo history
    property ChangePrefix: string read FChangePrefix write FChangePrefix;
    // False in the design window, where the user opens patterns
    property OpensFiles: boolean read FOpensFiles write FOpensFiles;
    property OnConfirmWrite: TApiConfirmWrite read FOnConfirmWrite write FOnConfirmWrite;
    // Answers ui_state; without it ui_state is refused
    property OnWindowState: TApiWindowState read FOnWindowState write FOnWindowState;
  end;

// An object as a selection lists it: its id, name and type
function NodeReference(Node: TEvalNode): TJSONObject;

resourcestring
  rsApiNotRequest = 'The request must be a JSON-RPC 2.0 object with a method';
  rsApiNoMethod = 'There is no method "%s"';
  rsApiMissingParam = 'Parameter "%s" is missing or the wrong type';
  rsApiNoTarget = 'Give the object as "id" or "name"';
  rsApiUnknownId = 'There is no object or variable with ID %d';
  rsApiUnknownName = 'There is no object or variable named "%s"';
  rsApiNoFileName = 'The pattern has no file name yet; give a "path"';
  rsApiSaveExtension = '"%s" is not a .sloper file; patterns are saved only as .sloper files';
  rsApiNotAPattern = '"%s" is not a pattern file, so it is not replaced';
  rsApiExportExtension = 'A %s export is written to a %s file';
  rsApiNothingToUndo = 'There is nothing to undo';
  rsApiNothingToRedo = 'There is nothing to redo';
  rsApiSetFormula = 'Change %s';
  rsApiRename = 'Rename';
  rsApiDelete = 'Delete';
  rsApiLock = 'Lock';
  rsApiUnlock = 'Unlock';
  rsApiAdd = 'Add %s';
  rsApiSplit = 'Split edge';
  rsApiUnknownType = 'There is no type "%s"; use one of: %s';
  rsApiBadChoice = 'Parameter "%s" must be one of: %s';
  rsApiBadNodes = 'A curve path needs a "nodes" list, each with a point and angle';
  rsApiRenderFormat = 'Format "%s" is not available; use svg or png';
  rsApiPieceExists = '%s already covers this region';
  rsApiNotAPiece = '%s is not a piece';
  rsApiNotAnEdge = '%s is not an edge';
  rsApiConvertEdge = 'Change edge type';
  rsApiMergePoints = 'Merge points';
  rsApiBreakPoint = 'Break point';
  rsApiPaste = 'Paste';
  rsApiCannotCopy = 'Nothing to copy: %s cannot be copied; only points and edges can';
  rsApiNotAPoint = '%s is not a point';
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
  rsApiRole = 'Change role';
  rsApiMarker = 'Change marker';
  rsApiAddMarking = 'Add marking';
  rsApiRemoveMarking = 'Remove marking';
  rsApiMaterials = 'Change materials';
  rsApiPieceMaterial = 'Change material';
  rsApiPieceFill = 'Change fill';
  rsApiNoMaterial = 'There is no material "%s"';
  rsApiMaterialOrNone = 'Give a "material", or "none": true';
  rsApiTransform = 'Add transform';
  rsApiBadAxis = 'A mirror needs an "axis" with an "edge", or "a" and "b", or "a" and an "angle"';
  rsApiBadFold = 'Give an "edge", or "none": true';
  rsApiBadGrainline = 'Give an "angle", a "start" and "end" point, or "none": true';
  rsApiBadNotch = 'Give a "point", or an "edge" and a "position"';
  rsApiBadRegion = 'A region needs minX, minY, maxX and maxY, with each max above its min';
  rsApiBadAnchor = 'An "anchor" needs one of "point", "edge" (with a "position") or "piece"';
  rsApiNotANote = '%s is not a note';
  rsApiChangeNote = 'Change note';
  rsApiConvertUnits = 'Convert pattern units';
  rsApiBusy = 'The window is in the middle of a change; try again when the user has finished';
  rsApiOpenInWindow = 'Patterns are opened in the design window, not through the API; this works on the pattern open there';
  rsApiWriteDeclined = 'The user did not allow writing %s';
  rsApiNoWindow = 'ui_state needs the design window: start it with --automation and run opensloper-cli serve --connect';
  rsApiBadMarks = 'Parameter "marks" must be a list of objects with an "id" or "name", a "field", a "token" and a "role"';

implementation

uses
  Sloper.Core.Arrange, Sloper.Core.EvalTypes, Sloper.Core.JSON, Sloper.Core.Measurements, Sloper.Core.PatternCheck, Sloper.Core.PatternFile, Sloper.Core.Pattern,
  Sloper.Core.Variables, Sloper.Core.Draft, Sloper.Core.Geometry, Sloper.Core.PieceDetect, Sloper.Core.SeamSuggest, Sloper.Core.Transform,
  Sloper.Core.Settings, Sloper.Core.Note, Sloper.Core.Units, Sloper.Core.UnitConvert, Sloper.Core.Fragment, base64,
  Sloper.Output.DraftSVG, Sloper.Output.DraftPNG, Sloper.Output.Layout, Sloper.Core.Garment, Sloper.Output.GarmentSVG, Sloper.Output.GarmentPNG,
  Sloper.Output.LayoutExport, Sloper.Core.Version, Sloper.API.Methods;

const
  VARIABLE_TYPE = 'variable';
  PIECE_TYPE = 'piece';
  SEAM_TYPE = 'seam';
  NOTE_TYPE = 'note';
  RENDER_FORMAT_SVG = 'svg';
  RENDER_FORMAT_PNG = 'png';

constructor EApiError.Create(ACode: integer; const AMessage: string; const AFieldName: string; APosition: integer);
begin
  inherited Create(AMessage);
  Code := ACode;
  FieldName := AFieldName;
  Position := APosition;
end;

function RequireString(Params: TJSONObject; const AName: string): string;
begin
  if not Assigned(Params) or not GetJSONString(Params, AName, Result) then
    raise EApiError.Create(RPC_INVALID_PARAMS, Format(rsApiMissingParam, [AName]));
end;

function OptionalString(Params: TJSONObject; const AName: string): string;
begin
  Result := '';
  if Assigned(Params) and Assigned(Params.Find(AName)) then
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
  if Assigned(Params.Find(AName)) then
    Result := FormulaParam(Params, AName);
end;

// The words a method's choice parameter takes, as the methods table lists them
function TableChoices(const Method, AName: string): string;
var
  Info: TApiMethod;
  Param: TApiParam;
begin
  Result := '';
  if FindApiMethod(Method, Info) then
    for Param in Info.Params do
      if Param.Name = AName then
        Exit(Param.Choices);
end;

// True when the parameter is given, refusing one that is not a number
function OptionalNumber(Params: TJSONObject; const AName: string; var Value: double): boolean;
begin
  Result := Assigned(Params.Find(AName));
  if Result and not GetJSONNumber(Params, AName, Value) then
    raise EApiError.Create(RPC_INVALID_PARAMS, Format(rsApiMissingParam, [AName]));
end;

function BooleanParam(Params: TJSONObject; const AName: string): boolean;
begin
  Result := False;
  if Assigned(Params.Find(AName)) and not GetJSONBoolean(Params, AName, Result) then
    raise EApiError.Create(RPC_INVALID_PARAMS, Format(rsApiMissingParam, [AName]));
end;

// A note's font, bold and italic, each kept from Base when left out; an
// empty font is the default
function NoteStyleParam(Params: TJSONObject; const Base: TTextStyle): TTextStyle;
begin
  Result := Base;
  if Assigned(Params.Find('font')) then
    Result.Font := RequireString(Params, 'font');
  if Assigned(Params.Find('bold')) then
    Result.Bold := BooleanParam(Params, 'bold');
  if Assigned(Params.Find('italic')) then
    Result.Italic := BooleanParam(Params, 'italic');
end;

// A list of strings; anything else in it is refused
function StringListParam(Params: TJSONObject; const AName: string): TStringArray;
var
  List: TJSONData;
  Index: integer;
begin
  Result := nil;
  List := Params.Find(AName);
  if List.JSONType <> jtArray then
    raise EApiError.Create(RPC_INVALID_PARAMS, Format(rsApiMissingParam, [AName]));
  for Index := 0 to List.Count - 1 do
  begin
    if List.Items[Index].JSONType <> jtString then
      raise EApiError.Create(RPC_INVALID_PARAMS, Format(rsApiMissingParam, [AName]));
    Insert(List.Items[Index].AsString, Result, Length(Result));
  end;
end;

function JoinedRoleNames: string;
begin
  Result := string.Join(', ', EDGE_ROLE_NAMES);
end;

// Which of Choices, the first when absent
function ChoiceParam(Params: TJSONObject; const AName: string; const Choices: array of string): integer;
var
  Text: string;
begin
  Result := 0;
  if not Assigned(Params.Find(AName)) then
    Exit;
  Text := RequireString(Params, AName);
  for Result := 0 to High(Choices) do
    if Choices[Result] = Text then
      Exit;
  raise EApiError.Create(RPC_INVALID_PARAMS, Format(rsApiBadChoice, [AName, string.Join(', ', Choices)]));
end;

function PickParam(Params: TJSONObject): integer;
begin
  Result := 1;
  if Assigned(Params.Find('pick')) and not GetJSONInteger(Params, 'pick', Result) then
    raise EApiError.Create(RPC_INVALID_PARAMS, Format(rsApiMissingParam, ['pick']));
end;

function RoleParam(Params: TJSONObject): TEdgeRole;
begin
  Result := TEdgeRole(ChoiceParam(Params, 'role', EDGE_ROLE_NAMES));
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

function NodeReference(Node: TEvalNode): TJSONObject;
begin
  Result := TJSONObject.Create;
  if (Node is TRepeatPoint) and TRepeatPoint(Node).IsVirtual then
    Result.Add('id', TJSONNull.Create)
  else
    Result.Add('id', StrToInt(Node.Key));
  if Node is TVariable then
  begin
    Result.Add('name', TVariable(Node).Name);
    Result.Add('type', VARIABLE_TYPE);
  end
  else
  begin
    Result.Add('name', Node.DisplayName);
    Result.Add('type', PatternObjectTypeName(TDraftObject(Node)));
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
      Result.Add('type', VARIABLE_TYPE);
    end
    else
    begin
      Result.Add('name', Node.DisplayName);
      Result.Add('type', PatternObjectTypeName(TDraftObject(Node)));
      if Node is TEdgeObject then
        Result.Add('role', EDGE_ROLE_NAMES[TEdgeObject(Node).Role]);
      if TDraftObject(Node).Marker <> pmPlain then
        Result.Add('marker', POINT_MARKER_NAMES[TDraftObject(Node).Marker]);
      Result.Add('locked', Document.Pattern.IsLocked(Node));
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
        Result.Add('markings', Length(TPieceObject(Node).Markings));
        Result.Add('holes', Round(TPieceObject(Node).PropertyValue('holes')));
        Result.Add('cutCount', TPieceObject(Node).CutCount);
        Result.Add('mirrored', TPieceObject(Node).Mirrored);
        Result.Add('onFold', TPieceObject(Node).OnFold);
        if Assigned(Document.Pattern.MaterialOf(TPieceObject(Node))) then
          Result.Add('material', Document.Pattern.MaterialOf(TPieceObject(Node)).Name);
        Result.Add('fillColor', TPieceObject(Node).FillColor);
        Result.Add('fillStyle', PIECE_FILL_NAMES[Ord(TPieceObject(Node).FillStyle)]);
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
      end
      else if Node is TNoteObject then
      begin
        Result.Add('x', ReportFloat(TNoteObject(Node).Position.X));
        Result.Add('y', ReportFloat(TNoteObject(Node).Position.Y));
      end;
    if Node is TNoteObject then
    begin
      Result.Add('text', TNoteObject(Node).DisplayText(Document.Pattern.Resolver));
      Result.Add('shownText', TNoteObject(Node).ShownText);
      Result.Add('size', JSONFloat(TNoteObject(Node).Size));
      Result.Add('print', TNoteObject(Node).Print);
      Result.Add('leader', NOTE_LEADER_NAMES[TNoteObject(Node).Leader]);
      Result.Add('align', TEXT_ALIGN_NAMES[TNoteObject(Node).Align]);
      Result.Add('box', TNoteObject(Node).Boxed);
      Result.Add('font', TNoteObject(Node).Style.Font);
      Result.Add('bold', TNoteObject(Node).Style.Bold);
      Result.Add('italic', TNoteObject(Node).Style.Italic);
      Result.Add('anchor', NOTE_ANCHOR_NAMES[TNoteObject(Node).Anchor]);
      if TNoteObject(Node).Anchor <> naFree then
        Result.Add('anchorId', StrToInt(TNoteObject(Node).AnchorKey));
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
  FOwnsDocument := True;
  FOpensFiles := True;
end;

constructor TApiServer.CreateFor(ADocument: TPatternDocument);
begin
  inherited Create;
  FDocument := ADocument;
  FOwnsDocument := False;
  FOpensFiles := True;
end;

destructor TApiServer.Destroy;
begin
  if FOwnsDocument then
    FreeAndNil(FDocument);
  inherited Destroy;
end;

procedure TApiServer.BeginChange(const Description: string; CheckLocks: boolean);
begin
  // Opened checking locks, which only a change to the whole pattern skips
  if FEarlyChange then
  begin
    FEarlyChange := False;
    FDocument.RenameChange(FChangePrefix + Description);
    Exit;
  end;
  if FDocument.ChangeOpen then
    raise EApiError.Create(RPC_REFUSED, rsApiBusy);
  FDocument.BeginChange(FChangePrefix + Description, CheckLocks);
end;

procedure TApiServer.EndChange;
begin
  FDocument.EndChange;
  if FDocument.ChangeRefused then
    raise EApiError.Create(RPC_REFUSED, FDocument.Pattern.LastError);
end;

procedure TApiServer.ConfirmWrite(const Path: string);
begin
  if Assigned(FOnConfirmWrite) and not FOnConfirmWrite(ExpandFileName(Path)) then
    raise EApiError.Create(RPC_REFUSED, Format(rsApiWriteDeclined, [Path]));
end;

function TApiServer.DoWindowState: TJSONData;
begin
  if not Assigned(FOnWindowState) then
    raise EApiError.Create(RPC_REFUSED, rsApiNoWindow);
  Result := FOnWindowState();
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
  raise EApiError.Create(RPC_REFUSED, Reason, FieldName, Position);
end;

// The ID of an input given as a number, or as an object's name. A repeat
// point not used before takes an ID, which changes the pattern, so when Use
// is set and no change is open the call's change is opened here.
function TApiServer.Reference(Params: TJSONObject; const AName: string; Use: boolean): string;
var
  Id: integer;
  TargetName: string;
  Target: TDraftObject;
begin
  if GetJSONInteger(Params, AName, Id) then
  begin
    // Checked here, so a method can rely on the node being there; one of the
    // wrong kind is the pattern's to refuse, with a reason
    if not Assigned(FDocument.Pattern.FindNode(IntToStr(Id))) then
      raise EApiError.Create(RPC_REFUSED, Format(rsApiUnknownId, [Id]));
    if not (FDocument.Pattern.FindNode(IntToStr(Id)) is TDraftObject) then
      Exit(IntToStr(Id));
    Target := TDraftObject(FDocument.Pattern.FindNode(IntToStr(Id)));
  end
  else if GetJSONString(Params, AName, TargetName) then
    Target := FDocument.Pattern.FindObject(TargetName)
  else
    raise EApiError.Create(RPC_INVALID_PARAMS, Format(rsApiMissingParam, [AName]));
  if not Assigned(Target) then
    raise EApiError.Create(RPC_REFUSED, Format(rsApiUnknownName, [TargetName]));
  Result := Target.Key;
  if not Use or not (Target is TRepeatPoint) or not TRepeatPoint(Target).IsVirtual then
    Exit;
  if not FDocument.ChangeOpen then
  begin
    FDocument.BeginChange(FChangePrefix);
    FEarlyChange := True;
  end;
  Result := FDocument.Pattern.UsePoint(Target.Key);
end;

// Ends the change that added Node, nil when it was refused
function TApiServer.AddedNode(Node: TEvalNode): TJSONData;
var
  Key: string;
begin
  if not Assigned(Node) then
    RefuseChange;
  Key := Node.Key;
  EndChange;
  Result := NodeToJSON(FDocument, FDocument.Pattern.FindNode(Key));
end;

// The object or variable a call means, by "id" or by "name"
function TApiServer.FindTarget(Params: TJSONObject): TEvalNode;
var
  Id: integer;
  TargetName: string;
begin
  Result := nil;
  if Assigned(Params) and GetJSONInteger(Params, 'id', Id) then
  begin
    Result := FDocument.Pattern.FindNode(IntToStr(Id));
    if not ((Result is TDraftObject) or (Result is TVariable)) then
      raise EApiError.Create(RPC_REFUSED, Format(rsApiUnknownId, [Id]));
    Exit;
  end;
  if not Assigned(Params) or not GetJSONString(Params, 'name', TargetName) then
    raise EApiError.Create(RPC_INVALID_PARAMS, rsApiNoTarget);
  Result := FDocument.Pattern.FindObject(TargetName);
  if not Assigned(Result) then
    Result := FDocument.Pattern.FindVariable(TargetName);
  if not Assigned(Result) then
    raise EApiError.Create(RPC_REFUSED, Format(rsApiUnknownName, [TargetName]));
end;

function TApiServer.DocumentInfo: TJSONObject;
begin
  Result := TJSONObject.Create;
  try
    Result.Add('path', FDocument.FileName);
    Result.Add('measurements', FDocument.MeasurementPath);
    // Formulas and variable values are in this unit; reported positions and lengths are mm
    Result.Add('units', MEASURE_UNIT_NAMES[FDocument.Pattern.Units]);
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
  if not FOpensFiles then
    raise EApiError.Create(RPC_REFUSED, rsApiOpenInWindow);
  Measurements := OptionalString(Params, 'measurements');
  if not FDocument.LoadFromFile(RequireString(Params, 'path'), Err) then
    raise EApiError.Create(RPC_REFUSED, Err);
  if (Measurements <> '') and not FDocument.UseMeasurements(Measurements, Err) then
    raise EApiError.Create(RPC_REFUSED, Err);
  UseSize(OptionalString(Params, 'size'));
  Result := DocumentInfo;
end;

procedure TApiServer.UseSize(const Size: string);
begin
  if (Size <> '') and not FDocument.SelectMeasurementSize(Size) then
    raise EApiError.Create(RPC_REFUSED, Format(rsMeasurementUnknownSize, [Size]));
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
    if Assigned(FDocument.Measurements) then
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
  if Assigned(Params.Find('edge')) then
  begin
    First := Reference(Params, 'edge');
    BeginChange(rsApiAddRepeat);
    Added := FDocument.Pattern.AddRepeatOnEdge(RepeatName, First, CountText, IncludeEnds);
  end
  else
  begin
    First := Reference(Params, 'a');
    Second := Reference(Params, 'b');
    BeginChange(rsApiAddRepeat);
    Added := FDocument.Pattern.AddRepeatBetween(RepeatName, First, Second, CountText, IncludeEnds);
  end;
  Result := AddedNode(Added);
end;

// Each item is an ID or a name
function TApiServer.ReferenceList(Params: TJSONObject; const AName: string; Use: boolean): TStringArray;
var
  List: TJSONData;
  Index: integer;
  Holder: TJSONObject;
begin
  Result := nil;
  List := Params.Find(AName);
  if not Assigned(List) or (List.JSONType <> jtArray) then
    Exit;
  Holder := TJSONObject.Create;
  try
    for Index := 0 to List.Count - 1 do
    begin
      Holder.Clear;
      Holder.Add(AName, List.Items[Index].Clone);
      Insert(Reference(Holder, AName, Use), Result, Length(Result));
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
  if Assigned(Params.Find('reference')) then
    Request.Reference := Reference(Params, 'reference');
  if Assigned(Params.Find('edge')) then
    Request.Edge := Reference(Params, 'edge');
  Replace := ReferenceList(Params, 'replace');
  if not PlanArrange(FDocument.Pattern, Request, Items, Err) then
    raise EApiError.Create(RPC_REFUSED, Err);
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
    BeginChange(rsApiArrange);
    if not ApplyArrange(FDocument.Pattern, Request, Replace, Err) then
    begin
      FDocument.CancelChange;
      raise EApiError.Create(RPC_REFUSED, Err);
    end;
    EndChange;
    Result := Info;
  except
    FreeAndNil(Info);
    raise;
  end;
end;

// Whether the file holds a pattern, by its "format" member
function IsPatternFile(const Path: string): boolean;
var
  Text, Err, FormatName: string;
  Root: TJSONObject;
begin
  Result := False;
  if not ReadTextFile(Path, Text, Err) or not ParseJSONObject(Text, Root, Err) then
    Exit;
  try
    Result := GetJSONString(Root, 'format', FormatName) and (FormatName = PATTERN_FORMAT);
  finally
    FreeAndNil(Root);
  end;
end;

// A client may be steered by text in a shared pattern, so the API writes only
// .sloper files and replaces only a file that already holds a pattern
procedure CheckPatternTarget(const Path: string);
begin
  if not SameText(ExtractFileExt(Path), PATTERN_FILE_EXT) then
    raise EApiError.Create(RPC_REFUSED, Format(rsApiSaveExtension, [ExtractFileName(Path)]));
  if FileExists(Path) and not IsPatternFile(Path) then
    raise EApiError.Create(RPC_REFUSED, Format(rsApiNotAPattern, [ExtractFileName(Path)]));
end;

function TApiServer.DoSave(Params: TJSONObject): TJSONData;
var
  Err, Path: string;
begin
  Path := OptionalString(Params, 'path');
  if Path = '' then
    Path := FDocument.FileName;
  if Path = '' then
    raise EApiError.Create(RPC_REFUSED, rsApiNoFileName);
  CheckPatternTarget(Path);
  ConfirmWrite(Path);
  if not FDocument.SaveToFile(Path, Err) then
    raise EApiError.Create(RPC_REFUSED, Err);
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
    if Assigned(FDocument.Measurements) and (FDocument.Measurements.SizeCount > 0) then
    begin
      Info.Add('size', FDocument.Measurements.SizeName);
      List := TJSONArray.Create;
      Info.Add('sizes', List);
      for Index := 0 to FDocument.Measurements.SizeCount - 1 do
        List.Add(FDocument.Measurements.Sizes[Index]);
    end;
    List := TJSONArray.Create;
    Info.Add('measurements', List);
    if Assigned(FDocument.Measurements) then
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
    raise EApiError.Create(RPC_INVALID_PARAMS, Format(rsApiMissingParam, ['value']));
  UseSize(OptionalString(Params, 'size'));
  Description := '';
  Existing := nil;
  if Assigned(FDocument.Measurements) then
    Existing := FDocument.Measurements.Find(Key);
  if Assigned(Existing) then
    Description := Existing.Description;
  if Assigned(Params.Find('description')) then
    Description := RequireString(Params, 'description');
  if not FDocument.ChangeMeasurement(Key, Value, Description, Change, Err) then
    raise EApiError.Create(RPC_REFUSED, Err);
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
  BeginChange(Format(rsApiSetFormula, [FieldName]));
  Done := FDocument.Pattern.SetFormula(Node, FieldName, Text);
  if not Done then
    RefuseChange;
  EndChange;
  Result := NodeToJSON(FDocument, FindTarget(Params));
end;

// Converts the pattern to another unit, rewriting only lengths. Numbers whose
// role the formulas leave open are marked in "marks"; while any is still open
// nothing changes, and the reply lists them so the caller can mark them and
// call again. Their "token" is what a mark names; "position" is where the
// number starts in "formula", as shown.
function TApiServer.DoConvertUnits(Params: TJSONObject): TJSONData;
var
  ToUnits: TMeasureUnit;
  Marks: TUnitMarkArray;
  Mark: TUnitMark;
  MarkList, Undecided: TJSONArray;
  MarkItem, Item: TJSONObject;
  Analysis: TUnitAnalysis;
  Number: TUnitNumber;
  Node: TEvalNode;
  Index, At, Len: integer;
  Err: string;
  Reply: TJSONObject;
begin
  if not Assigned(Params.Find('units')) then
    raise EApiError.Create(RPC_INVALID_PARAMS, Format(rsApiMissingParam, ['units']));
  ToUnits := TMeasureUnit(ChoiceParam(Params, 'units', MEASURE_UNIT_NAMES));
  if ToUnits = FDocument.Pattern.Units then
    raise EApiError.Create(RPC_REFUSED, Format(rsConvertSameUnit, [MEASURE_UNIT_NAMES[ToUnits]]));
  Marks := nil;
  if Assigned(Params.Find('marks')) then
  begin
    if Params.Find('marks').JSONType <> jtArray then
      raise EApiError.Create(RPC_INVALID_PARAMS, rsApiBadMarks);
    MarkList := TJSONArray(Params.Find('marks'));
    for Index := 0 to MarkList.Count - 1 do
    begin
      if MarkList[Index].JSONType <> jtObject then
        raise EApiError.Create(RPC_INVALID_PARAMS, rsApiBadMarks);
      MarkItem := TJSONObject(MarkList[Index]);
      Mark := Default(TUnitMark);
      Mark.NodeKey := FindTarget(MarkItem).Key;
      if not GetJSONString(MarkItem, 'field', Mark.FieldName) or not GetJSONInteger(MarkItem, 'token', Mark.Token) or not
        Assigned(MarkItem.Find('role')) then
        raise EApiError.Create(RPC_INVALID_PARAMS, rsApiBadMarks);
      Mark.IsLength := ChoiceParam(MarkItem, 'role', ['length', 'number']) = 0;
      Insert(Mark, Marks, Length(Marks));
    end;
  end;
  Analysis := AnalyseUnits(FDocument.Pattern, Marks);
  Reply := TJSONObject.Create;
  try
    if UndecidedCount(Analysis.Numbers) > 0 then
    begin
      Reply.Add('converted', False);
      Undecided := TJSONArray.Create;
      Reply.Add('undecided', Undecided);
      for Number in Analysis.Numbers do
        if not Number.Decided then
        begin
          Node := FDocument.Pattern.FindNode(Number.NodeKey);
          Item := TJSONObject.Create;
          Undecided.Add(Item);
          Item.Add('id', StrToInt(Node.Key));
          Item.Add('name', Node.DisplayName);
          Item.Add('field', Number.FieldName);
          Item.Add('token', Number.Token);
          Item.Add('number', ReportFloat(Number.Value));
          Item.Add('formula', Node.Field(Number.FieldName).DisplayText(FDocument.Pattern.Resolver));
          if Node.Field(Number.FieldName).DisplayTokenSpan(FDocument.Pattern.Resolver, Number.Token, At, Len) then
            Item.Add('position', At);
        end;
      Exit(Reply);
    end;
    // Converting rewrites every formula, locked objects' too
    BeginChange(rsApiConvertUnits, False);
    if not ConvertPatternUnits(FDocument.Pattern, ToUnits, Analysis.Numbers, Err) then
    begin
      FDocument.CancelChange;
      raise EApiError.Create(RPC_REFUSED, Err);
    end;
    EndChange;
    Reply.Add('converted', True);
    Reply.Add('units', MEASURE_UNIT_NAMES[ToUnits]);
    Reply.Add('skipped', Length(Analysis.Skipped));
    Result := Reply;
  except
    FreeAndNil(Reply);
    raise;
  end;
end;

function TApiServer.DoRename(Params: TJSONObject): TJSONData;
var
  Node: TEvalNode;
  NewName: string;
begin
  Node := FindTarget(Params);
  NewName := RequireString(Params, 'newName');
  BeginChange(rsApiRename);
  if not FDocument.Pattern.Rename(Node, NewName) then
    RefuseChange;
  EndChange;
  Result := NodeToJSON(FDocument, FDocument.Pattern.FindNode(Node.Key));
end;

function TApiServer.DoDelete(Params: TJSONObject): TJSONData;
var
  Node: TEvalNode;
begin
  Node := FindTarget(Params);
  BeginChange(rsApiDelete);
  if not FDocument.Pattern.Delete(Node) then
    RefuseChange;
  EndChange;
  Result := DocumentInfo;
end;

function TApiServer.DoSetLocked(Params: TJSONObject): TJSONData;
var
  Node: TEvalNode;
  Locked: boolean;
begin
  Node := FindTarget(Params);
  if not Assigned(Params.Find('locked')) then
    raise EApiError.Create(RPC_INVALID_PARAMS, Format(rsApiMissingParam, ['locked']));
  Locked := BooleanParam(Params, 'locked');
  if Locked then
    BeginChange(rsApiLock)
  else
    BeginChange(rsApiUnlock);
  if not FDocument.Pattern.SetLocked(Node, Locked) then
    RefuseChange;
  EndChange;
  Result := NodeToJSON(FDocument, FDocument.Pattern.FindNode(Node.Key));
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
    raise EApiError.Create(RPC_REFUSED, rsApiNothingToUndo);
  Result := DocumentInfo;
end;

function TApiServer.DoRedo: TJSONData;
begin
  if not FDocument.Redo then
    raise EApiError.Create(RPC_REFUSED, rsApiNothingToRedo);
  Result := DocumentInfo;
end;

// The Garment view, lit as by default
function TApiServer.RenderGarment(Params: TJSONObject; const RenderFormat: string): TJSONData;
var
  Scene: TGarmentScene;
  MaterialName, Err: string;
  Material: TPatternMaterial;
  Index, Width: integer;
  Png: rawbytestring;
  Info: TJSONObject;
begin
  Scene := BuildGarment(FDocument.Pattern);
  MaterialName := OptionalString(Params, 'material');
  if MaterialName <> '' then
  begin
    Material := FDocument.Pattern.FindMaterialNamed(MaterialName);
    if not Assigned(Material) then
      raise EApiError.Create(RPC_REFUSED, Format(rsApiNoMaterial, [MaterialName]));
    for Index := 0 to FDocument.Pattern.MaterialCount - 1 do
      if FDocument.Pattern.Materials[Index] = Material then
        Scene := GarmentOfMaterial(Scene, Index);
  end;
  if RenderFormat = RENDER_FORMAT_SVG then
    Exit(TJSONObject.Create(['format', RENDER_FORMAT_SVG, 'svg', GarmentToSVG(Scene, DefaultGarmentLight)]));
  Width := PNG_DEFAULT_WIDTH;
  if Assigned(Params.Find('width')) and not GetJSONInteger(Params, 'width', Width) then
    raise EApiError.Create(RPC_INVALID_PARAMS, Format(rsApiMissingParam, ['width']));
  if not GarmentToPNG(Scene, DefaultGarmentLight, Width, Png, Err) then
    raise EApiError.Create(RPC_REFUSED, Err);
  Info := TJSONObject.Create(['format', RENDER_FORMAT_PNG, 'width', Width]);
  Info.Add('png', EncodeStringBase64(Png));
  Result := Info;
end;

// The SVG comes back in the reply: file access is for open, save and export
function TApiServer.DoRender(Params: TJSONObject): TJSONData;
var
  Options: TDraftSVGOptions;
  Region: TJSONData;
  RegionItem: TJSONObject;
  RenderFormat, Err: string;
  Png: rawbytestring;
  Width: integer;
  Info: TJSONObject;
begin
  RenderFormat := OptionalString(Params, 'format');
  if RenderFormat = '' then
    RenderFormat := RENDER_FORMAT_SVG;
  if (RenderFormat <> RENDER_FORMAT_SVG) and (RenderFormat <> RENDER_FORMAT_PNG) then
    raise EApiError.Create(RPC_REFUSED, Format(rsApiRenderFormat, [RenderFormat]));
  if Assigned(Params.Find('garment')) and BooleanParam(Params, 'garment') then
    Exit(RenderGarment(Params, RenderFormat));
  Options := DefaultDraftSVGOptions;
  GetJSONBoolean(Params, 'labels', Options.Labels);
  if Assigned(Params.Find('hiddenRoles')) and not NamesToRoles(StringListParam(Params, 'hiddenRoles'), Options.HiddenRoles) then
    raise EApiError.Create(RPC_INVALID_PARAMS, Format(rsApiBadChoice, ['hiddenRoles', JoinedRoleNames]));
  if Assigned(Params.Find('annotations')) then
    Options.HideAnnotations := not BooleanParam(Params, 'annotations');
  Region := Params.Find('region');
  if Assigned(Region) then
  begin
    if Region.JSONType <> jtObject then
      raise EApiError.Create(RPC_INVALID_PARAMS, rsApiBadRegion);
    RegionItem := TJSONObject(Region);
    if not GetJSONNumber(RegionItem, 'minX', Options.Region.MinX) or not GetJSONNumber(RegionItem, 'minY', Options.Region.MinY) or
      not GetJSONNumber(RegionItem, 'maxX', Options.Region.MaxX) or not GetJSONNumber(RegionItem, 'maxY', Options.Region.MaxY) or
      (Options.Region.MaxX <= Options.Region.MinX) or (Options.Region.MaxY <= Options.Region.MinY) then
      raise EApiError.Create(RPC_INVALID_PARAMS, rsApiBadRegion);
    Options.HasRegion := True;
  end;
  if RenderFormat = RENDER_FORMAT_SVG then
    Exit(TJSONObject.Create(['format', RENDER_FORMAT_SVG, 'svg', DraftToSVG(FDocument.Pattern, Options)]));
  Width := PNG_DEFAULT_WIDTH;
  if Assigned(Params.Find('width')) and not GetJSONInteger(Params, 'width', Width) then
    raise EApiError.Create(RPC_INVALID_PARAMS, Format(rsApiMissingParam, ['width']));
  if not DraftToPNG(FDocument.Pattern, Options, Width, Png, Err) then
    raise EApiError.Create(RPC_REFUSED, Err);
  Info := TJSONObject.Create(['format', RENDER_FORMAT_PNG, 'width', Width]);
  Info.Add('png', EncodeStringBase64(Png));
  Result := Info;
end;

function TApiServer.DoAddVariable(Params: TJSONObject): TJSONData;
var
  VariableName, Formula, Description: string;
begin
  VariableName := RequireString(Params, 'name');
  Formula := FormulaParam(Params, 'formula');
  Description := OptionalString(Params, 'description');
  BeginChange(Format(rsApiAdd, [VARIABLE_TYPE]));
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
      BeginChange(Format(rsApiAdd, [TypeName]));
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
      BeginChange(Format(rsApiAdd, [TypeName]));
      Added := Pattern.AddOffsetPoint(PointName, First, TOffsetMode(Mode), FormulaA, FormulaB);
    end;
    'alongEdgePoint':
    begin
      First := Reference(Params, 'edge');
      FromEnd := ChoiceParam(Params, 'from', ['start', 'end']) = 1;
      Mode := ChoiceParam(Params, 'mode', ['length', 'ratio']);
      FormulaA := FormulaParam(Params, 'value');
      BeginChange(Format(rsApiAdd, [TypeName]));
      Added := Pattern.AddAlongEdgePoint(PointName, First, FromEnd, TAlongMode(Mode), FormulaA);
    end;
    'betweenPoint':
    begin
      First := Reference(Params, 'a');
      Second := Reference(Params, 'b');
      Mode := ChoiceParam(Params, 'mode', ['length', 'ratio']);
      FormulaA := FormulaParam(Params, 'value');
      BeginChange(Format(rsApiAdd, [TypeName]));
      Added := Pattern.AddBetweenPoint(PointName, First, Second, TAlongMode(Mode), FormulaA);
    end;
    'intersectPoint':
    begin
      First := Reference(Params, 'edgeA');
      Second := Reference(Params, 'edgeB');
      FlagA := BooleanParam(Params, 'extendA');
      FlagB := BooleanParam(Params, 'extendB');
      Pick := PickParam(Params);
      BeginChange(Format(rsApiAdd, [TypeName]));
      Added := Pattern.AddIntersectPoint(PointName, First, Second, FlagA, FlagB, Pick);
    end;
    'circleCirclePoint':
    begin
      First := Reference(Params, 'centreA');
      FormulaA := FormulaParam(Params, 'radiusA');
      Second := Reference(Params, 'centreB');
      FormulaB := FormulaParam(Params, 'radiusB');
      Pick := PickParam(Params);
      BeginChange(Format(rsApiAdd, [TypeName]));
      Added := Pattern.AddCircleCirclePoint(PointName, First, FormulaA, Second, FormulaB, Pick);
    end;
    'circleEdgePoint':
    begin
      First := Reference(Params, 'centre');
      FormulaA := FormulaParam(Params, 'radius');
      Second := Reference(Params, 'edge');
      FlagA := BooleanParam(Params, 'extend');
      Pick := PickParam(Params);
      BeginChange(Format(rsApiAdd, [TypeName]));
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
      BeginChange(Format(rsApiAdd, [TypeName]));
      Added := Pattern.AddProjectPoint(PointName, First, Second, TProjectDirection(Direction), FormulaA, FlagA);
    end;
    else
      raise EApiError.Create(RPC_INVALID_PARAMS, Format(rsApiUnknownType, [TypeName, TableChoices('add_point', 'type')]));
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
  Piece: TPieceObject;
  Run: TRunEdgeArray;
  Side: TOffsetSide;
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
      BeginChange(Format(rsApiAdd, [TypeName]));
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
      BeginChange(Format(rsApiAdd, [TypeName]));
      Added := Pattern.AddCurve(First, Second, Angle1, Length1, Angle2, Length2, Role, EdgeName);
    end;
    // One edge, or a run of "edges" in any order; inside and outside need
    // the piece the run is part of
    'offsetEdge':
    begin
      Length1 := FormulaParam(Params, 'distance');
      Index := ChoiceParam(Params, 'side', ['left', 'right', 'inside', 'outside']);
      if Assigned(Params.Find('edges')) then
        NodeKeys := ReferenceList(Params, 'edges')
      else
        NodeKeys := [Reference(Params, 'edge')];
      Piece := nil;
      if Index >= 2 then
      begin
        Added := Pattern.FindNode(Reference(Params, 'piece'));
        if not (Added is TPieceObject) then
          raise EApiError.Create(RPC_REFUSED, Format(rsApiNotAPiece, [Added.DisplayName]));
        Piece := TPieceObject(Added);
      end;
      BeginChange(Format(rsApiAdd, [TypeName]));
      Added := nil;
      Side := TOffsetSide(Index mod 2);
      if Assigned(Piece) then
      begin
        if Pattern.PieceRun(Piece, NodeKeys, Index = 2, Run, Side) then
          Added := Pattern.AddOffsetRun(Run, Length1, Side, Role, EdgeName);
      end
      else if Length(NodeKeys) = 1 then
        Added := Pattern.AddOffsetEdge(NodeKeys[0], Length1, Side, Role, EdgeName)
      else if Pattern.ChainRun(NodeKeys, Run) then
        Added := Pattern.AddOffsetRun(Run, Length1, Side, Role, EdgeName);
    end;
    'circle':
    begin
      First := Reference(Params, 'centre');
      Length1 := FormulaParam(Params, 'radius');
      BeginChange(Format(rsApiAdd, [TypeName]));
      Added := Pattern.AddCircle(First, Length1, Role, EdgeName);
    end;
    'arc':
    begin
      First := Reference(Params, 'centre');
      Length1 := FormulaParam(Params, 'radius');
      Angle1 := FormulaParam(Params, 'angle1');
      Angle2 := FormulaParam(Params, 'angle2');
      BeginChange(Format(rsApiAdd, [TypeName]));
      Added := Pattern.AddArc(First, Length1, Angle1, Angle2, Role, EdgeName);
    end;
    'curvePath':
    begin
      Nodes := Params.Find('nodes');
      if not Assigned(Nodes) or (Nodes.JSONType <> jtArray) then
        raise EApiError.Create(RPC_INVALID_PARAMS, rsApiBadNodes);
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
          raise EApiError.Create(RPC_INVALID_PARAMS, rsApiBadNodes);
        Item := TJSONObject(Nodes.Items[Index]);
        NodeKeys[Index] := Reference(Item, 'point');
        Angles[Index] := FormulaParam(Item, 'angle');
        LengthsIn[Index] := OptionalFormula(Item, 'lengthIn');
        LengthsOut[Index] := OptionalFormula(Item, 'lengthOut');
      end;
      BeginChange(Format(rsApiAdd, [TypeName]));
      Added := Pattern.AddCurvePath(NodeKeys, Angles, LengthsIn, LengthsOut, Role, EdgeName);
    end;
    else
      raise EApiError.Create(RPC_INVALID_PARAMS, Format(rsApiUnknownType, [TypeName, TableChoices('add_edge', 'type')]));
  end;
  Result := AddedNode(Added);
end;

function TApiServer.DoAddRectangle(Params: TJSONObject): TJSONData;
var
  Corner, Width, Height: string;
  Edges: TRectangleEdges;
  Keys: array[0..3] of string;
  Index: integer;
  List: TJSONArray;
begin
  Corner := Reference(Params, 'corner');
  Width := FormulaParam(Params, 'width');
  Height := FormulaParam(Params, 'height');
  BeginChange(Format(rsApiAdd, ['rectangle']));
  if not FDocument.Pattern.AddRectangle(Corner, Width, Height, RoleParam(Params), Edges) then
    RefuseChange;
  for Index := 0 to 3 do
    Keys[Index] := Edges[Index].Key;
  EndChange;
  List := TJSONArray.Create;
  try
    for Index := 0 to 3 do
      List.Add(NodeToJSON(FDocument, FDocument.Pattern.FindNode(Keys[Index])));
    Result := List;
  except
    FreeAndNil(List);
    raise;
  end;
end;

function TApiServer.DoRoundCorner(Params: TJSONObject): TJSONData;
var
  EdgeA, EdgeB, Radius: string;
begin
  EdgeA := Reference(Params, 'edgeA');
  EdgeB := Reference(Params, 'edgeB');
  Radius := FormulaParam(Params, 'radius');
  BeginChange(Format(rsApiAdd, ['corner']));
  Result := AddedNode(FDocument.Pattern.AddRoundCorner(EdgeA, EdgeB, Radius));
end;

function TApiServer.DoSplitEdge(Params: TJSONObject): TJSONData;
var
  Edge, Point, FirstKey, SecondKey: string;
  First, Second: TSplitPart;
  Parts: TJSONArray;
begin
  Edge := Reference(Params, 'edge');
  Point := Reference(Params, 'point');
  BeginChange(rsApiSplit);
  if not FDocument.Pattern.SplitEdge(Edge, Point, First, Second) then
    RefuseChange;
  FirstKey := First.Key;
  SecondKey := Second.Key;
  EndChange;
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
    raise EApiError.Create(RPC_INVALID_PARAMS, Format(rsApiMissingParam, ['x']));
  if not GetJSONNumber(Params, 'y', At.Y) then
    raise EApiError.Create(RPC_INVALID_PARAMS, Format(rsApiMissingParam, ['y']));
  PieceName := OptionalString(Params, 'name');
  Allowance := OptionalFormula(Params, PIECE_ALLOWANCE_FIELD);
  if Allowance = '' then
    Allowance := DEFAULT_PIECE_ALLOWANCE;
  if not DetectPiecePath(FDocument.Pattern, At, Path, Reason) then
    raise EApiError.Create(RPC_REFUSED, Reason);
  Existing := PieceOnPath(FDocument.Pattern, Path);
  if Assigned(Existing) then
    raise EApiError.Create(RPC_REFUSED, Format(rsApiPieceExists, [Existing.DisplayName]));
  BeginChange(Format(rsApiAdd, [PIECE_TYPE]));
  Result := AddedNode(FDocument.Pattern.AddPiece(PieceName, Path, Allowance));
end;

function TApiServer.TargetPiece(Params: TJSONObject): TPieceObject;
var
  Target: TEvalNode;
begin
  Target := FindTarget(Params);
  if not (Target is TPieceObject) then
    raise EApiError.Create(RPC_REFUSED, Format(rsApiNotAPiece, [Target.DisplayName]));
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
    BeginChange(rsApiGrainline);
    FDocument.Pattern.ClearGrain(Piece);
    Exit(AddedNode(Piece));
  end;
  Angle := OptionalFormula(Params, 'angle');
  if (Angle = '') and not Assigned(Params.Find('start')) then
    raise EApiError.Create(RPC_INVALID_PARAMS, rsApiBadGrainline);
  if Angle <> '' then
  begin
    BeginChange(rsApiGrainline);
    Done := FDocument.Pattern.SetGrainAngle(Piece, Angle);
  end
  else
  begin
    First := Reference(Params, 'start');
    Second := Reference(Params, 'end');
    BeginChange(rsApiGrainline);
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
  if Assigned(Params.Find('point')) then
  begin
    Key := Reference(Params, 'point');
    BeginChange(rsApiAddNotch);
    Done := FDocument.Pattern.AddPointNotch(Piece, Key);
  end
  else
  begin
    if not Assigned(Params.Find('edge')) or not Assigned(Params.Find('position')) then
      raise EApiError.Create(RPC_INVALID_PARAMS, rsApiBadNotch);
    Key := Reference(Params, 'edge');
    Position := FormulaParam(Params, 'position');
    BeginChange(rsApiAddNotch);
    Done := FDocument.Pattern.AddEdgeNotch(Piece, Key, Position);
  end;
  if not Done then
    RefuseChange;
  Result := AddedNode(Piece);
end;

// Notches count from 1, as in the field names
function TApiServer.DoAddMarking(Params: TJSONObject): TJSONData;
var
  Piece: TPieceObject;
  Kind: TMarkingKind;
  Key, FirstFormula, SecondFormula: string;
  Done: boolean;
begin
  Piece := TargetPiece(Params);
  if not Assigned(Params.Find('kind')) then
    raise EApiError.Create(RPC_INVALID_PARAMS, Format(rsApiMissingParam, ['kind']));
  // "hole", as before point markers, gives the point a hole marker and
  // puts it on the piece
  if (Params.Find('kind').JSONType = jtString) and (Params.Get('kind', '') = 'hole') then
  begin
    Key := Reference(Params, 'point');
    FirstFormula := FormulaParam(Params, 'diameter');
    BeginChange(rsApiAddMarking);
    Done := FDocument.Pattern.SetMarker(Key, pmHole, FirstFormula) and
      ((Piece.PointMarkingOf(Key) >= 0) or FDocument.Pattern.AddPointMarking(Piece, Key));
    if not Done then
      RefuseChange;
    Exit(AddedNode(Piece));
  end;
  Kind := TMarkingKind(ChoiceParam(Params, 'kind', MARKING_KIND_NAMES));
  case Kind of
    mkPoint:
    begin
      Key := Reference(Params, 'point');
      BeginChange(rsApiAddMarking);
      Done := FDocument.Pattern.AddPointMarking(Piece, Key);
    end;
    mkStitchHoles:
    begin
      Key := Reference(Params, 'edge');
      FirstFormula := FormulaParam(Params, MARKING_SPACING_FIELD);
      SecondFormula := FormulaParam(Params, MARKING_SIZE_FIELD);
      BeginChange(rsApiAddMarking);
      Done := FDocument.Pattern.AddStitchMarking(Piece, Key, FirstFormula, SecondFormula);
    end;
    else
    begin
      Key := Reference(Params, 'edge');
      BeginChange(rsApiAddMarking);
      Done := FDocument.Pattern.AddLineMarking(Piece, Key);
    end;
  end;
  if not Done then
    RefuseChange;
  Result := AddedNode(Piece);
end;

function TApiServer.DoRemoveMarking(Params: TJSONObject): TJSONData;
var
  Piece: TPieceObject;
  Index: integer;
begin
  Piece := TargetPiece(Params);
  if not GetJSONInteger(Params, 'marking', Index) then
    raise EApiError.Create(RPC_INVALID_PARAMS, Format(rsApiMissingParam, ['marking']));
  BeginChange(rsApiRemoveMarking);
  if not FDocument.Pattern.RemoveMarking(Piece, Index - 1) then
    RefuseChange;
  Result := AddedNode(Piece);
end;

function TApiServer.DoRemoveNotch(Params: TJSONObject): TJSONData;
var
  Piece: TPieceObject;
  Index: integer;
begin
  Piece := TargetPiece(Params);
  if not GetJSONInteger(Params, 'notch', Index) then
    raise EApiError.Create(RPC_INVALID_PARAMS, Format(rsApiMissingParam, ['notch']));
  BeginChange(rsApiRemoveNotch);
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
  if Assigned(Params.Find('count')) and not GetJSONInteger(Params, 'count', Count) then
    raise EApiError.Create(RPC_INVALID_PARAMS, Format(rsApiMissingParam, ['count']));
  if Assigned(Params.Find('mirrored')) then
    Mirrored := BooleanParam(Params, 'mirrored');
  BeginChange(rsApiCut);
  if not FDocument.Pattern.SetCut(Piece, Count, Mirrored) then
    RefuseChange;
  Result := AddedNode(Piece);
end;

// By ID or name
// By ID or by name
function TApiServer.FindMaterialParam(Params: TJSONObject; const AName: string): TPatternMaterial;
var
  Id: integer;
  Text: string;
begin
  if GetJSONInteger(Params, AName, Id) then
  begin
    Text := IntToStr(Id);
    Result := FDocument.Pattern.FindMaterial(Text);
  end
  else
  begin
    Text := RequireString(Params, AName);
    Result := FDocument.Pattern.FindMaterialNamed(Text);
  end;
  if not Assigned(Result) then
    raise EApiError.Create(RPC_REFUSED, Format(rsApiNoMaterial, [Text]));
end;

function TApiServer.MaterialsToJSON: TJSONData;
var
  Reply, Item: TJSONObject;
  List: TJSONArray;
  Index: integer;
  Material: TPatternMaterial;
begin
  Reply := TJSONObject.Create;
  try
    List := TJSONArray.Create;
    Reply.Add('materials', List);
    for Index := 0 to FDocument.Pattern.MaterialCount - 1 do
    begin
      Material := FDocument.Pattern.Materials[Index];
      Item := TJSONObject.Create;
      List.Add(Item);
      Item.Add('id', StrToIntDef(Material.Key, 0));
      Item.Add('name', Material.Name);
      Item.Add('color', Material.Color);
      Item.Add('fill', MATERIAL_FILL_NAMES[Ord(Material.Fill)]);
      if Material.HasAllowance then
        Item.Add('allowance', ReportFloat(Material.Allowance));
      if Material.Width > 0 then
        Item.Add('width', ReportFloat(Material.Width));
      if Material.Length > 0 then
        Item.Add('length', ReportFloat(Material.Length));
      if Material.AllowTurns then
        Item.Add('allowTurns', True);
    end;
    Reply.Add('cutList', FDocument.Pattern.CutList);
  except
    FreeAndNil(Reply);
    raise;
  end;
  Result := Reply;
end;

function TApiServer.DoAddMaterial(Params: TJSONObject): TJSONData;
var
  Fill: TMaterialFill;
begin
  BeginChange(rsApiMaterials);
  Fill := ffTint;
  if Assigned(Params) then
    Fill := TMaterialFill(ChoiceParam(Params, 'fill', MATERIAL_FILL_NAMES));
  if not Assigned(FDocument.Pattern.AddMaterial(OptionalString(Params, 'name'), OptionalString(Params, 'color'), Fill)) then
    RefuseChange;
  EndChange;
  Result := MaterialsToJSON;
end;

function TApiServer.DoRenameMaterial(Params: TJSONObject): TJSONData;
var
  Material: TPatternMaterial;
begin
  Material := FindMaterialParam(Params, 'material');
  BeginChange(rsApiMaterials);
  if not FDocument.Pattern.RenameMaterial(Material, RequireString(Params, 'name')) then
    RefuseChange;
  EndChange;
  Result := MaterialsToJSON;
end;

function TApiServer.DoSetMaterial(Params: TJSONObject): TJSONData;
var
  Material: TPatternMaterial;
  Allowance, NewWidth, NewLength: double;
begin
  Material := FindMaterialParam(Params, 'material');
  BeginChange(rsApiMaterials);
  if Assigned(Params.Find('color')) and not FDocument.Pattern.SetMaterialColor(Material, RequireString(Params, 'color')) then
    RefuseChange;
  if Assigned(Params.Find('fill')) then
    FDocument.Pattern.SetMaterialFill(Material, TMaterialFill(ChoiceParam(Params, 'fill', MATERIAL_FILL_NAMES)));
  Allowance := 0;
  if OptionalNumber(Params, 'allowance', Allowance) and not FDocument.Pattern.SetMaterialAllowance(Material, True, Allowance) then
    RefuseChange;
  if Assigned(Params.Find('noAllowance')) and BooleanParam(Params, 'noAllowance') then
    FDocument.Pattern.SetMaterialAllowance(Material, False, 0);
  if Assigned(Params.Find('width')) or Assigned(Params.Find('length')) then
  begin
    NewWidth := Material.Width;
    NewLength := Material.Length;
    OptionalNumber(Params, 'width', NewWidth);
    // No width takes the length away too
    if not OptionalNumber(Params, 'length', NewLength) and (NewWidth = 0) then
      NewLength := 0;
    if not FDocument.Pattern.SetMaterialSize(Material, NewWidth, NewLength) then
      RefuseChange;
  end;
  if Assigned(Params.Find('allowTurns')) then
    FDocument.Pattern.SetMaterialAllowTurns(Material, BooleanParam(Params, 'allowTurns'));
  EndChange;
  Result := MaterialsToJSON;
end;

function TApiServer.DoDeleteMaterial(Params: TJSONObject): TJSONData;
var
  Material: TPatternMaterial;
begin
  Material := FindMaterialParam(Params, 'material');
  BeginChange(rsApiMaterials);
  if not FDocument.Pattern.DeleteMaterial(Material) then
    RefuseChange;
  EndChange;
  Result := MaterialsToJSON;
end;

function TApiServer.DoSetPieceMaterial(Params: TJSONObject): TJSONData;
var
  Piece: TPieceObject;
  Material: TPatternMaterial;
begin
  Piece := TargetPiece(Params);
  Material := nil;
  if Assigned(Params.Find('material')) then
    Material := FindMaterialParam(Params, 'material')
  else if not (Assigned(Params.Find('none')) and BooleanParam(Params, 'none')) then
    raise EApiError.Create(RPC_INVALID_PARAMS, rsApiMaterialOrNone);
  BeginChange(rsApiPieceMaterial);
  FDocument.Pattern.SetPieceMaterial(Piece, Material);
  Result := AddedNode(Piece);
end;

function TApiServer.DoSetPieceFill(Params: TJSONObject): TJSONData;
var
  Piece: TPieceObject;
  Color: string;
  Style: TPieceFillStyle;
begin
  Piece := TargetPiece(Params);
  Color := Piece.FillColor;
  Style := Piece.FillStyle;
  if Assigned(Params.Find('color')) then
    Color := RequireString(Params, 'color');
  if Assigned(Params.Find('style')) then
    Style := TPieceFillStyle(ChoiceParam(Params, 'style', PIECE_FILL_NAMES));
  BeginChange(rsApiPieceFill);
  if not FDocument.Pattern.SetPieceFill(Piece, Color, Style) then
    RefuseChange;
  Result := AddedNode(Piece);
end;

function TApiServer.DoAddTransform(Params: TJSONObject): TJSONData;
var
  Spec: TTransformSpec;
  Axis: TJSONData;

  function FormulaOr(const AName, Default_: string): string;
  begin
    Result := OptionalFormula(Params, AName);
    if Result = '' then
      Result := Default_;
  end;

begin
  Spec := Default(TTransformSpec);
  Spec.Kind := TTransformKind(ChoiceParam(Params, 'type', ['rotate', 'mirror', 'move']));
  if not Assigned(Params.Find('type')) then
    raise EApiError.Create(RPC_INVALID_PARAMS, Format(rsApiMissingParam, ['type']));
  Spec.Name := OptionalString(Params, 'name');
  Spec.Suffix := OptionalString(Params, 'suffix');
  if not Assigned(Params.Find('sources')) then
    raise EApiError.Create(RPC_INVALID_PARAMS, Format(rsApiMissingParam, ['sources']));
  Spec.Angle := FormulaOr('angle', '0');
  case Spec.Kind of
    tkRotate:
      Spec.Pivot := Reference(Params, 'pivot');
    tkMirror:
    begin
      Axis := Params.Find('axis');
      if not Assigned(Axis) or (Axis.JSONType <> jtObject) then
        raise EApiError.Create(RPC_INVALID_PARAMS, rsApiBadAxis);
      if Assigned(TJSONObject(Axis).Find('edge')) then
        Spec.AxisEdge := Reference(TJSONObject(Axis), 'edge')
      else
      begin
        Spec.AxisA := Reference(TJSONObject(Axis), 'a');
        if Assigned(TJSONObject(Axis).Find('b')) then
          Spec.AxisB := Reference(TJSONObject(Axis), 'b');
      end;
    end;
    tkMove:
    begin
      Spec.Polar := Assigned(Params.Find('length'));
      Spec.Length := FormulaOr('length', '0');
      Spec.DX := FormulaOr('dx', '0');
      Spec.DY := FormulaOr('dy', '0');
      if Assigned(Params.Find('pivot')) then
      begin
        Spec.Pivot := Reference(Params, 'pivot');
        Spec.Rotate := FormulaOr('rotate', '0');
      end;
    end;
  end;
  BeginChange(rsApiTransform);
  Spec.Sources := ReferenceList(Params, 'sources');
  Result := AddedNode(FDocument.Pattern.AddTransform(Spec));
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
    if not Assigned(Params.Find('edge')) then
      raise EApiError.Create(RPC_INVALID_PARAMS, rsApiBadFold);
    Edge := Reference(Params, 'edge');
  end;
  BeginChange(rsApiFold);
  if not FDocument.Pattern.SetFoldEdge(Piece, Edge) then
    RefuseChange;
  Result := AddedNode(Piece);
end;

// In place: the edge keeps its ID, so whatever used it still does
function TApiServer.DoConvertEdge(Params: TJSONObject): TJSONData;
var
  Target: TEvalNode;
  ToCurve: boolean;
  Converted: TEdgeObject;
begin
  Target := FindTarget(Params);
  if not (Target is TEdgeObject) then
    raise EApiError.Create(RPC_REFUSED, Format(rsApiNotAnEdge, [Target.DisplayName]));
  if not Assigned(Params) or not Assigned(Params.Find('to')) then
    raise EApiError.Create(RPC_INVALID_PARAMS, Format(rsApiMissingParam, ['to']));
  ToCurve := ChoiceParam(Params, 'to', ['line', 'curve']) = 1;
  BeginChange(rsApiConvertEdge);
  if ToCurve then
    Converted := FDocument.Pattern.ConvertToCurve(TEdgeObject(Target))
  else
    Converted := FDocument.Pattern.ConvertToLine(TEdgeObject(Target));
  if not Assigned(Converted) then
    RefuseChange;
  Result := AddedNode(Converted);
end;

// A marking role gives the edge to the pieces it lies in, as the reply's
// pieces list shows
function TApiServer.DoSetRole(Params: TJSONObject): TJSONData;
var
  Role: TEdgeRole;
  Target: TEvalNode;
  Piece: TPieceObject;
  Pieces: TJSONArray;
begin
  Target := FindTarget(Params);
  if not (Target is TEdgeObject) then
    raise EApiError.Create(RPC_REFUSED, Format(rsApiNotAnEdge, [Target.DisplayName]));
  if not Assigned(Params.Find('role')) then
    raise EApiError.Create(RPC_INVALID_PARAMS, Format(rsApiMissingParam, ['role']));
  // Read before the change opens, as a bad role raises
  Role := RoleParam(Params);
  BeginChange(rsApiRole);
  if not FDocument.Pattern.SetEdgeRole(TEdgeObject(Target), Role) then
    RefuseChange;
  Result := AddedNode(Target);
  Pieces := TJSONArray.Create;
  TJSONObject(Result).Add('pieces', Pieces);
  for Piece in FDocument.Pattern.PiecesWithMarking(Target.Key) do
    Pieces.Add(Piece.DisplayName);
end;

// Like set_role for a point or repeat: a marker puts it on the pieces it
// lies in once evaluated, listed in the reply
function TApiServer.DoSetMarker(Params: TJSONObject): TJSONData;
var
  Marker: TPointMarker;
  Target: TEvalNode;
  Size: string;
  Piece: TPieceObject;
  Pieces: TJSONArray;
begin
  Target := FindTarget(Params);
  if not Assigned(Params.Find('marker')) then
    raise EApiError.Create(RPC_INVALID_PARAMS, Format(rsApiMissingParam, ['marker']));
  Marker := TPointMarker(ChoiceParam(Params, 'marker', POINT_MARKER_NAMES));
  Size := '';
  if Assigned(Params.Find('size')) then
    Size := FormulaParam(Params, 'size');
  BeginChange(rsApiMarker);
  if not FDocument.Pattern.SetMarker(Target.Key, Marker, Size) then
    RefuseChange;
  Result := AddedNode(Target);
  Pieces := TJSONArray.Create;
  TJSONObject(Result).Add('pieces', Pieces);
  for Piece in FDocument.Pattern.PiecesWithMarking(Target.Key) do
    Pieces.Add(Piece.DisplayName);
end;

// The point kept, under the merged name
function TApiServer.DoMergePoints(Params: TJSONObject): TJSONData;
var
  Points: TStringArray;
begin
  if not Assigned(Params) or not Assigned(Params.Find('points')) then
    raise EApiError.Create(RPC_INVALID_PARAMS, Format(rsApiMissingParam, ['points']));
  Points := ReferenceList(Params, 'points');
  BeginChange(rsApiMergePoints);
  Result := AddedNode(FDocument.Pattern.MergePoints(Points));
end;

// The points it became, as points[], the point itself first
function TApiServer.DoBreakPoint(Params: TJSONObject): TJSONData;
var
  Target: TEvalNode;
  Broken: TPointObjectArray;
  Keys: TStringArray;
  Item: TPointObject;
  Key: string;
  List: TJSONArray;
begin
  Target := FindTarget(Params);
  if not (Target is TPointObject) then
    raise EApiError.Create(RPC_REFUSED, Format(rsApiNotAPoint, [Target.DisplayName]));
  BeginChange(rsApiBreakPoint);
  Broken := FDocument.Pattern.BreakPoint(TPointObject(Target));
  if Length(Broken) = 0 then
    RefuseChange;
  Keys := nil;
  for Item in Broken do
    Insert(Item.Key, Keys, Length(Keys));
  EndChange;
  Result := TJSONObject.Create;
  try
    List := TJSONArray.Create;
    TJSONObject(Result).Add('points', List);
    for Key in Keys do
      List.Add(NodeToJSON(FDocument, FDocument.Pattern.FindNode(Key)));
  except
    FreeAndNil(Result);
    raise;
  end;
end;

function TApiServer.DoCopyObjects(Params: TJSONObject): TJSONData;
var
  Copied: TFragmentCopy;
  List: TJSONArray;
  AName: string;
begin
  if not Assigned(Params) or not Assigned(Params.Find('objects')) then
    raise EApiError.Create(RPC_INVALID_PARAMS, Format(rsApiMissingParam, ['objects']));
  // Reading only: a repeat point is copied as it is, without taking an ID
  Copied := CopyFragment(FDocument.Pattern, ReferenceList(Params, 'objects', False));
  if Copied.Text = '' then
    raise EApiError.Create(RPC_REFUSED, Format(rsApiCannotCopy, [string.Join(', ', Copied.LeftOut)]));
  Result := TJSONObject.Create;
  try
    TJSONObject(Result).Add('fragment', Copied.Text);
    TJSONObject(Result).Add('names', Copied.Names);
    List := TJSONArray.Create;
    TJSONObject(Result).Add('leftOut', List);
    for AName in Copied.LeftOut do
      List.Add(AName);
  except
    FreeAndNil(Result);
    raise;
  end;
end;

function TApiServer.DoPasteObjects(Params: TJSONObject): TJSONData;
var
  Text, Reason, Key, Renamed: string;
  Pasted: TFragmentPaste;
  List: TJSONArray;
begin
  if not Assigned(Params) or not GetJSONString(Params, 'fragment', Text) then
    raise EApiError.Create(RPC_INVALID_PARAMS, Format(rsApiMissingParam, ['fragment']));
  BeginChange(rsApiPaste);
  if not PasteFragment(FDocument.Pattern, Text, Pasted, Reason) then
  begin
    FDocument.CancelChange;
    raise EApiError.Create(RPC_REFUSED, Reason);
  end;
  EndChange;
  Result := TJSONObject.Create;
  try
    List := TJSONArray.Create;
    TJSONObject(Result).Add('objects', List);
    for Key in Pasted.Keys do
      List.Add(NodeToJSON(FDocument, FDocument.Pattern.FindNode(Key)));
    List := TJSONArray.Create;
    TJSONObject(Result).Add('renamed', List);
    for Renamed in Pasted.Renamed do
      List.Add(Renamed);
  except
    FreeAndNil(Result);
    raise;
  end;
end;

function TApiServer.SeamSideParam(Params: TJSONObject; const AName: string): TSeamSide;
var
  List: TJSONData;
  Index: integer;
begin
  Result := nil;
  List := Params.Find(AName);
  if not Assigned(List) or (List.JSONType <> jtArray) then
    raise EApiError.Create(RPC_INVALID_PARAMS, Format(rsApiBadSeamSide, [AName]));
  SetLength(Result, List.Count);
  for Index := 0 to List.Count - 1 do
  begin
    if List.Items[Index].JSONType <> jtObject then
      raise EApiError.Create(RPC_INVALID_PARAMS, Format(rsApiBadSeamSide, [AName]));
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
  Ease := OptionalFormula(Params, SEAM_EASE_FIELD);
  if Ease = '' then
    Ease := DEFAULT_SEAM_EASE;
  Tolerance := OptionalFormula(Params, SEAM_TOLERANCE_FIELD);
  if Tolerance = '' then
    Tolerance := DEFAULT_SEAM_TOLERANCE;
  BeginChange(Format(rsApiAdd, [SEAM_TYPE]));
  Result := AddedNode(FDocument.Pattern.AddSeam(OptionalString(Params, 'name'), SideA, SideB, Ease, Tolerance));
end;

function TApiServer.DoFlipSeam(Params: TJSONObject): TJSONData;
var
  Target: TEvalNode;
begin
  Target := FindTarget(Params);
  if not (Target is TSeamObject) then
    raise EApiError.Create(RPC_REFUSED, Format(rsApiNotASeam, [Target.DisplayName]));
  BeginChange(rsApiFlipSeam);
  TSeamObject(Target).Reversed := not TSeamObject(Target).Reversed;
  Result := AddedNode(Target);
end;

// The anchor as {"point": ...}, {"edge": ..., "position": ...} or
// {"piece": ...}, by ID or name; none makes a free note at x, y
function TApiServer.DoAddNote(Params: TJSONObject): TJSONData;
var
  Text, AnchorKey, Position, First, Second: string;
  Anchor: TNoteAnchor;
  AnchorData: TJSONData;
  AnchorItem: TJSONObject;
  Kind: TNoteAnchor;
  Size: double;
  Print, Boxed: boolean;
  Leader: TNoteLeader;
  Align: TTextAlign;
  Note: TNoteObject;
  Style: TTextStyle;
begin
  Text := RequireString(Params, 'text');
  Anchor := naFree;
  AnchorKey := '';
  Position := '';
  AnchorData := Params.Find('anchor');
  if Assigned(AnchorData) then
  begin
    if AnchorData.JSONType <> jtObject then
      raise EApiError.Create(RPC_INVALID_PARAMS, rsApiBadAnchor);
    AnchorItem := TJSONObject(AnchorData);
    for Kind := naPoint to naPiece do
      if Assigned(AnchorItem.Find(NOTE_ANCHOR_NAMES[Kind])) then
      begin
        if Anchor <> naFree then
          raise EApiError.Create(RPC_INVALID_PARAMS, rsApiBadAnchor);
        Anchor := Kind;
      end;
    if Anchor = naFree then
      raise EApiError.Create(RPC_INVALID_PARAMS, rsApiBadAnchor);
    AnchorKey := Reference(AnchorItem, NOTE_ANCHOR_NAMES[Anchor]);
    if Anchor = naEdge then
    begin
      if not Assigned(AnchorItem.Find(NOTE_POSITION_FIELD)) then
        raise EApiError.Create(RPC_INVALID_PARAMS, rsApiBadAnchor);
      Position := FormulaParam(AnchorItem, NOTE_POSITION_FIELD);
    end;
  end;
  if Anchor = naFree then
  begin
    First := OptionalFormula(Params, NOTE_X_FIELD);
    Second := OptionalFormula(Params, NOTE_Y_FIELD);
  end
  else
  begin
    First := OptionalFormula(Params, NOTE_DX_FIELD);
    Second := OptionalFormula(Params, NOTE_DY_FIELD);
  end;
  if First = '' then
    First := '0';
  if Second = '' then
    Second := '0';
  Size := DEFAULT_NOTE_SIZE;
  if Assigned(Params.Find('size')) and not GetJSONNumber(Params, 'size', Size) then
    raise EApiError.Create(RPC_INVALID_PARAMS, Format(rsApiMissingParam, ['size']));
  Print := True;
  if Assigned(Params.Find('print')) then
    Print := BooleanParam(Params, 'print');
  Leader := TNoteLeader(ChoiceParam(Params, 'leader', NOTE_LEADER_NAMES));
  Align := TTextAlign(ChoiceParam(Params, 'align', TEXT_ALIGN_NAMES));
  Boxed := BooleanParam(Params, 'box');
  Style := NoteStyleParam(Params, Default(TTextStyle));
  BeginChange(Format(rsApiAdd, [NOTE_TYPE]));
  Note := FDocument.Pattern.AddNote(OptionalString(Params, 'name'), Text, Anchor, AnchorKey, Position, First, Second, Size, Print, Leader);
  if Assigned(Note) then
  begin
    FDocument.Pattern.SetNoteAlign(Note, Align);
    FDocument.Pattern.SetNoteBoxed(Note, Boxed);
    if not FDocument.Pattern.SetNoteStyle(Note, Style) then
      RefuseChange;
  end;
  Result := AddedNode(Note);
end;

// Any of the text, size, printing, leader, alignment, box and font
function TApiServer.DoSetText(Params: TJSONObject): TJSONData;
var
  Target: TEvalNode;
  Note: TNoteObject;
  Text: string;
  Size: double;
  Print, Boxed: boolean;
  Leader: TNoteLeader;
  Align: TTextAlign;
  Style: TTextStyle;
begin
  Target := FindTarget(Params);
  if not (Target is TNoteObject) then
    raise EApiError.Create(RPC_REFUSED, Format(rsApiNotANote, [Target.DisplayName]));
  Note := TNoteObject(Target);
  Text := Note.DisplayText(FDocument.Pattern.Resolver);
  if Assigned(Params.Find('text')) then
    Text := RequireString(Params, 'text');
  Size := Note.Size;
  if Assigned(Params.Find('size')) and not GetJSONNumber(Params, 'size', Size) then
    raise EApiError.Create(RPC_INVALID_PARAMS, Format(rsApiMissingParam, ['size']));
  Print := Note.Print;
  if Assigned(Params.Find('print')) then
    Print := BooleanParam(Params, 'print');
  Leader := Note.Leader;
  if Assigned(Params.Find('leader')) then
    Leader := TNoteLeader(ChoiceParam(Params, 'leader', NOTE_LEADER_NAMES));
  Align := Note.Align;
  if Assigned(Params.Find('align')) then
    Align := TTextAlign(ChoiceParam(Params, 'align', TEXT_ALIGN_NAMES));
  Boxed := Note.Boxed;
  if Assigned(Params.Find('box')) then
    Boxed := BooleanParam(Params, 'box');
  Style := NoteStyleParam(Params, Note.Style);
  BeginChange(rsApiChangeNote);
  FDocument.Pattern.SetNotePrint(Note, Print);
  FDocument.Pattern.SetNoteAlign(Note, Align);
  FDocument.Pattern.SetNoteBoxed(Note, Boxed);
  if not FDocument.Pattern.SetNoteText(Note, Text) or not FDocument.Pattern.SetNoteSize(Note, Size) or not
    FDocument.Pattern.SetNoteLeader(Note, Leader) or not FDocument.Pattern.SetNoteStyle(Note, Style) then
    RefuseChange;
  Result := AddedNode(Note);
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

// From the saved files, as the publish app works, not the pattern being edited
function TApiServer.DoExport(Params: TJSONObject): TJSONData;
var
  LayoutFile, Target, Err: string;
  Chosen: TExportFormat;
  Layout: TLayout;
  Reply: TJSONObject;
begin
  LayoutFile := RequireString(Params, 'layout');
  Target := RequireString(Params, 'path');
  if not ExportFormatFor(OptionalString(Params, 'format'), Target, Chosen) then
    raise EApiError.Create(RPC_INVALID_PARAMS, rsExportBadFormat);
  // So an export cannot be written over a file of another kind
  if not SameText(ExtractFileExt(Target), EXPORT_EXTENSIONS[Chosen]) then
    raise EApiError.Create(RPC_REFUSED, Format(rsApiExportExtension, [EXPORT_NAMES[Chosen], EXPORT_EXTENSIONS[Chosen]]));
  ConfirmWrite(Target);
  Layout := TLayout.Create;
  try
    if not Layout.LoadFromFile(LayoutFile, Err) then
      raise EApiError.Create(RPC_REFUSED, Err);
    Layout.LoadSources;
    Layout.MachineProfiles := UserMachineProfiles;
    Layout.OutputProfiles := UserOutputProfiles;
    Layout.Calibration := UserCalibration;
    if OptionalString(Params, 'profile') <> '' then
      Layout.Output.Profile := OptionalString(Params, 'profile');
    if not ExportLayout(Layout, Chosen, Target, Err) then
      raise EApiError.Create(RPC_REFUSED, Err);
  finally
    FreeAndNil(Layout);
  end;
  Reply := TJSONObject.Create;
  Reply.Add('path', Target);
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
    raise EApiError.Create(RPC_REFUSED, Format(rsApiNotInPiece, [FDocument.Pattern.FindNode(Edge).DisplayName, Target.DisplayName]));
  Allowance := OptionalFormula(Params, PIECE_ALLOWANCE_FIELD);
  BeginChange(rsApiEdgeAllowance);
  if not FDocument.Pattern.SetEdgeAllowance(TPieceObject(Target), PathIndex, Allowance) then
    RefuseChange;
  Result := AddedNode(Target);
end;

function TApiServer.CallMethod(const Method: string; Params: TJSONObject): TJSONData;
var
  Info: TApiMethod;
  WasOpen: boolean;
begin
  // In the design window the user may be dragging; only reading waits for nothing
  WasOpen := FDocument.ChangeOpen;
  if WasOpen and FindApiMethod(Method, Info) and not Info.ReadOnly then
    raise EApiError.Create(RPC_REFUSED, rsApiBusy);
  FEarlyChange := False;
  try
    try
      Result := DispatchMethod(Method, Params);
      // Opened by Reference for a method that then changed nothing
      if FEarlyChange then
        FDocument.CancelChange;
    except
      // A method that fails after BeginChange, say on a param it reads late,
      // must not leave its change open: every later edit would be refused
      if not WasOpen and FDocument.ChangeOpen then
        FDocument.CancelChange;
      raise;
    end;
  finally
    FEarlyChange := False;
  end;
end;

function TApiServer.DispatchMethod(const Method: string; Params: TJSONObject): TJSONData;
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
    'set_locked': Result := DoSetLocked(Params);
    'evaluate': Result := DoEvaluate(False);
    'check': Result := DoEvaluate(True);
    'undo': Result := DoUndo;
    'redo': Result := DoRedo;
    'render': Result := DoRender(Params);
    'add_variable': Result := DoAddVariable(Params);
    'add_point': Result := DoAddPoint(Params);
    'add_edge': Result := DoAddEdge(Params);
    'split_edge': Result := DoSplitEdge(Params);
    'add_rectangle': Result := DoAddRectangle(Params);
    'round_corner': Result := DoRoundCorner(Params);
    'create_piece': Result := DoCreatePiece(Params);
    'set_edge_allowance': Result := DoSetEdgeAllowance(Params);
    'set_grainline': Result := DoSetGrainline(Params);
    'add_notch': Result := DoAddNotch(Params);
    'remove_notch': Result := DoRemoveNotch(Params);
    'add_marking': Result := DoAddMarking(Params);
    'remove_marking': Result := DoRemoveMarking(Params);
    'set_cut': Result := DoSetCut(Params);
    'set_fold': Result := DoSetFold(Params);
    'convert_edge': Result := DoConvertEdge(Params);
    'set_role': Result := DoSetRole(Params);
    'set_marker': Result := DoSetMarker(Params);
    'merge_points': Result := DoMergePoints(Params);
    'break_point': Result := DoBreakPoint(Params);
    'copy_objects': Result := DoCopyObjects(Params);
    'paste_objects': Result := DoPasteObjects(Params);
    'list_materials': Result := MaterialsToJSON;
    'add_material': Result := DoAddMaterial(Params);
    'rename_material': Result := DoRenameMaterial(Params);
    'set_material': Result := DoSetMaterial(Params);
    'delete_material': Result := DoDeleteMaterial(Params);
    'set_piece_material': Result := DoSetPieceMaterial(Params);
    'set_piece_fill': Result := DoSetPieceFill(Params);
    'add_transform': Result := DoAddTransform(Params);
    'add_seam': Result := DoAddSeam(Params);
    'flip_seam': Result := DoFlipSeam(Params);
    'suggest_seams': Result := DoSuggestSeams;
    'add_note': Result := DoAddNote(Params);
    'set_text': Result := DoSetText(Params);
    'export': Result := DoExport(Params);
    'convert_units': Result := DoConvertUnits(Params);
    'ui_state': Result := DoWindowState;
    else
      raise EApiError.Create(RPC_METHOD_NOT_FOUND, Format(rsApiNoMethod, [Method]));
  end;
end;

// Reply, or '' when the request has no id
function ReplyIfAsked(Id: TJSONData; const Reply: string): string;
begin
  if Assigned(Id) then
    Result := Reply
  else
    Result := '';
end;

function TApiServer.HandleLine(const Line: string): string;
var
  Request: TJSONObject;
  Err, Method: string;
  Id, ParamsData, Output: TJSONData;
  Params, OwnParams: TJSONObject;
begin
  OwnParams := nil;
  if not ParseJSONObject(Line, Request, Err) then
    Exit(RpcErrorResponse(nil, RPC_PARSE_ERROR, Err));
  try
    Id := Request.Find('id');
    // A line without an id gets no reply, even malformed: serve --connect
    // reads none, and would take one as the answer to its next request
    if not GetJSONString(Request, 'method', Method) then
      Exit(ReplyIfAsked(Id, RpcErrorResponse(Id, RPC_INVALID_REQUEST, rsApiNotRequest)));
    ParamsData := Request.Find('params');
    if Assigned(ParamsData) and (ParamsData.JSONType <> jtObject) then
      Exit(ReplyIfAsked(Id, RpcErrorResponse(Id, RPC_INVALID_PARAMS, Format(rsApiMissingParam, ['params']))));
    // Methods read members straight from it, so a request without any gets an empty one
    if not Assigned(ParamsData) then
    begin
      OwnParams := TJSONObject.Create;
      ParamsData := OwnParams;
    end;
    Params := TJSONObject(ParamsData);
    Output := nil;
    try
      try
        Output := CallMethod(Method, Params);
        Result := '';
        if Assigned(Id) then
        begin
          Result := RpcResultResponse(Id, Output);
          Output := nil;
        end;
      except
        on Failure: EApiError do
          Result := RpcErrorResponse(Id, Failure.Code, Failure.Message, Failure.FieldName, Failure.Position);
        on Failure: Exception do
          Result := RpcErrorResponse(Id, RPC_INTERNAL_ERROR, Failure.Message);
      end;
      // A notification gets no reply, not even an error
      if not Assigned(Id) then
        Result := '';
    finally
      FreeAndNil(Output);
    end;
  finally
    FreeAndNil(OwnParams);
    FreeAndNil(Request);
  end;
end;

end.
