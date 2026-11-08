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

// Reference pages of the user documentation, written as Markdown from the
// tables the code itself uses, so they cannot drift from it: the formula
// functions and units, every kind of object and its members, the command
// line, and the Automation API. opensloper-cli doc TOPIC writes
// one; build-docs.sh writes them all into docs/reference/. No LCL dependency.
unit Sloper.Docs.Reference;

{$mode ObjFPC}{$H+}

interface

const
  // Each is written to docs/reference/TOPIC.md
  DocTopics: array[0..3] of string = ('functions', 'operations', 'cli', 'api');

// The page for Topic; False when there is no such topic
function ReferencePage(const Topic: string; out Markdown: string): boolean;

resourcestring
  rsDocGenerated = 'This page is generated from the program by `opensloper-cli doc %s`; do not edit it by hand.';
  rsDocFunctionsTitle = 'Formula functions and units';
  rsDocFunctionsIntro = 'Formulas can use these functions. Angles are in degrees, 0° pointing right and 90° up. ' +
    'Function names are written in lower case and are the same in every language.';
  rsDocFunction = 'Function';
  rsDocArguments = 'Values';
  rsDocWhatItGives = 'What it gives';
  rsDocOrMore = '%d or more';
  rsDocOperatorsTitle = 'Operators';
  rsDocOperatorsIntro = 'In order of precedence, highest first. `^` groups from the right and binds tighter than a leading ' +
    'minus, so `-2^2` is -4.';
  rsDocOperator = 'Operator';
  rsDocMeaning = 'Meaning';
  rsDocOpGroup = 'Grouping';
  rsDocOpPower = 'Power';
  rsDocOpNegate = 'Minus a value';
  rsDocOpMultiply = 'Multiply and divide';
  rsDocOpAdd = 'Add and subtract';
  rsDocUnitsTitle = 'Units';
  rsDocUnitsIntro = 'A plain number is in the pattern''s unit. A number may carry a unit written straight after it, in any ' +
    'case, and is then converted to the pattern''s unit: `400mm`, `1.5cm`, `2in`. A number written with a unit keeps ' +
    'its meaning in every pattern, and Convert Pattern Units leaves it alone.';
  rsDocUnit = 'Unit';
  rsDocMillimetres = 'In millimetres';
  rsDocCliTitle = 'Command line';
  rsDocCliIntro = '`opensloper-cli` exports and checks patterns without a window, for scripts and builds.';
  rsDocCommands = 'Commands';
  rsDocOptions = 'Options';
  rsDocOption = 'Option';
  rsDocValue = 'Value';
  rsDocDescription = 'Description';
  rsDocArgumentsTitle = 'Arguments';
  rsDocArgumentsIntro = 'After the command, in this order; each command takes the ones it needs.';
  rsDocArgument = 'Argument';
  rsDocExitCodes = 'Exit codes';
  rsDocCode = 'Code';
  rsDocOperationsTitle = 'Operations and objects';
  rsDocOperationsIntro = 'Every kind of object a pattern holds, with its members as they are written in a pattern file ' +
    'and given to the Automation API (`add_point`, `add_edge` and the other methods take the same names). Formulas are ' +
    'text, in the pattern''s unit; a plain number may be given in their place. Objects refer to one another by ID.';
  rsDocCommonTitle = 'Members every object has';
  rsDocCommonEdges = 'Edges also have:';
  rsDocCommonPoints = 'Points and repeats also have:';
  rsDocGroupPoints = 'Points';
  rsDocGroupEdges = 'Edges';
  rsDocGroupTransforms = 'Transforms';
  rsDocGroupPieces = 'Pieces and seams';
  rsDocGroupAnnotations = 'Notes';
  rsDocMember = 'Member';
  rsDocReads = 'Formulas can read: %s.';
  rsDocKindLength = 'length formula';
  rsDocKindAngle = 'angle formula';
  rsDocKindNumber = 'number formula';
  rsDocKindLengthOrRatio = 'length or ratio formula';
  rsDocKindPoint = 'point ID';
  rsDocKindEdge = 'edge ID';
  rsDocKindPiece = 'piece ID';
  rsDocKindObject = 'object ID';
  rsDocKindMaterial = 'material ID';
  rsDocKindChoice = 'one of: %s';
  rsDocKindFlag = 'true or false';
  rsDocKindWhole = 'whole number';
  rsDocKindText = 'text';
  rsDocKindSize = 'number';
  rsDocKindList = 'list';
  rsDocKindGroup = 'group';
  rsDocApiTitle = 'Automation API';
  rsDocApiIntro = '`opensloper-cli serve` lets a script or an assistant such as Claude drive a pattern. It reads ' +
    'JSON-RPC 2.0 requests on standard input, one a line, and answers each on a line of standard output. Every change ' +
    'goes through the pattern''s undo history, as an edit in the window does.';
  rsDocApiExample = 'For example:';
  rsDocApiErrorsTitle = 'Errors';
  rsDocApiErrorsIntro = 'A refused call answers with a JSON-RPC error. Its `data` names the `field` at fault and the ' +
    '`position` of the problem in a formula, when there is one. Check the code, not the message, which may be translated.';
  rsDocApiErrorParse = 'The line is not JSON';
  rsDocApiErrorRequest = 'Not a JSON-RPC 2.0 request';
  rsDocApiErrorMethod = 'There is no such method';
  rsDocApiErrorParams = 'A parameter is missing or the wrong type';
  rsDocApiErrorInternal = 'Something went wrong inside';
  rsDocApiErrorRefused = 'The call was understood and refused, such as a formula with an unknown name';
  rsDocApiGroupFiles = 'Files and history';
  rsDocApiGroupMeasurements = 'Measurements';
  rsDocApiGroupObjects = 'Objects and variables';
  rsDocApiGroupDrafting = 'Drafting';
  rsDocApiGroupPieces = 'Pieces';
  rsDocApiGroupMaterials = 'Materials';
  rsDocApiGroupSeams = 'Seams';
  rsDocApiGroupNotes = 'Notes';
  rsDocApiGroupChecking = 'Checking and output';
  rsDocParameter = 'Parameter';
  rsDocRequired = 'Required';
  rsDocYes = 'yes';
  rsDocNoParameters = 'No parameters.';
  rsDocReturns = 'Returns: %s.';
  rsDocTargetName = '`id` or `name`';
  rsDocTheMembers = 'the type''s members';
  rsDocApiKindTarget = 'number or text';
  rsDocApiKindFormula = 'formula';
  rsDocApiKindReference = 'ID or name';
  rsDocApiKindReferences = 'list of IDs or names';
  rsDocApiKindMaterial = 'material ID or name';
  rsDocApiKindNames = 'list of: %s';
  rsDocApiKindMembers = 'see the type';

implementation

uses
  SysUtils, Sloper.Core.Formula, Sloper.Core.FormulaLexer, Sloper.Core.Units, Sloper.Core.OperationInfo, Sloper.API.Server,
  Sloper.API.Methods, Sloper.CLI.Arguments;

// Characters that would end a table cell or start markup
function Cell(const Text: string): string;
begin
  Result := StringReplace(Text, '|', '\|', [rfReplaceAll]);
  Result := StringReplace(Result, LineEnding, '<br>', [rfReplaceAll]);
end;

function Row(const Cells: array of string): string;
var
  Index: integer;
begin
  Result := '|';
  for Index := 0 to High(Cells) do
    Result := Result + ' ' + Cells[Index] + ' |';
  Result := Result + LineEnding;
end;

function HeaderRow(const Cells: array of string): string;
var
  Index: integer;
begin
  Result := Row(Cells) + '|';
  for Index := 0 to High(Cells) do
    Result := Result + ' --- |';
  Result := Result + LineEnding;
end;

function Heading(Level: integer; const Text: string): string;
begin
  Result := StringOfChar('#', Level) + ' ' + Text + LineEnding + LineEnding;
end;

function Paragraph(const Text: string): string;
begin
  Result := Text + LineEnding + LineEnding;
end;

function Code(const Text: string): string;
begin
  Result := '`' + Text + '`';
end;

function Generated(const Topic: string): string;
begin
  Result := Paragraph('!!! note' + LineEnding + LineEnding + '    ' + Format(rsDocGenerated, [Topic]));
end;

function FunctionsPage: string;
var
  Info: TFormulaFunctionInfo;
  Values: string;
  Suffix: TNumberSuffix;
begin
  Result := Heading(1, rsDocFunctionsTitle) + Generated('functions') + Paragraph(rsDocFunctionsIntro);
  Result := Result + HeaderRow([rsDocFunction, rsDocArguments, rsDocWhatItGives]);
  for Info in FormulaFunctions do
  begin
    if Info.MaxArgs < 0 then
      Values := Format(rsDocOrMore, [Info.MinArgs])
    else
      Values := IntToStr(Info.MinArgs);
    Result := Result + Row([Code(Info.Name + '(' + Info.Arguments + ')'), Values, Cell(Info.Description)]);
  end;
  Result := Result + LineEnding + Heading(2, rsDocOperatorsTitle) + Paragraph(rsDocOperatorsIntro);
  Result := Result + HeaderRow([rsDocOperator, rsDocMeaning]);
  Result := Result + Row([Code('( )'), rsDocOpGroup]) + Row([Code('^'), rsDocOpPower]) + Row([Code('-'), rsDocOpNegate]) +
    Row([Code('*') + ' ' + Code('/'), rsDocOpMultiply]) + Row([Code('+') + ' ' + Code('-'), rsDocOpAdd]);
  Result := Result + LineEnding + Heading(2, rsDocUnitsTitle) + Paragraph(rsDocUnitsIntro);
  Result := Result + HeaderRow([rsDocUnit, rsDocMillimetres]);
  for Suffix := Succ(nsNone) to High(TNumberSuffix) do
    Result := Result + Row([Code(NumberSuffixNames[Suffix]), FormatFloat('0.##', NumberSuffixMillimetres[Suffix])]);
end;

function CodedList(const Choices: string): string;
var
  Words: TStringArray;
  Index: integer;
begin
  Words := Choices.Split([', ']);
  for Index := 0 to High(Words) do
    Words[Index] := Code(Words[Index]);
  Result := string.Join(', ', Words);
end;

function KindText(const Member: TOperationMember): string;
const
  Kinds: array[TMemberKind] of string = (rsDocKindLength, rsDocKindAngle, rsDocKindNumber, rsDocKindLengthOrRatio,
    rsDocKindPoint, rsDocKindEdge, rsDocKindPiece, rsDocKindObject, rsDocKindMaterial, rsDocKindChoice, rsDocKindFlag,
    rsDocKindWhole, rsDocKindText, rsDocKindSize, rsDocKindList, rsDocKindGroup);
begin
  if Member.Kind <> mkChoice then
    Exit(Kinds[Member.Kind]);
  Result := Format(rsDocKindChoice, [CodedList(Member.Choices)]);
end;

function MemberTable(const Members: TOperationMemberArray): string;
var
  Member: TOperationMember;
begin
  Result := HeaderRow([rsDocMember, rsDocValue, rsDocDescription]);
  for Member in Members do
    Result := Result + Row([Code(Member.Name), KindText(Member), Cell(Member.Description)]);
  Result := Result + LineEnding;
end;

function OperationsPage: string;
const
  GroupTitles: array[TOperationGroup] of string = (rsDocGroupPoints, rsDocGroupEdges, rsDocGroupTransforms, rsDocGroupPieces,
    rsDocGroupAnnotations);
var
  Group: TOperationGroup;
  Info: TOperationInfo;
  Common: TOperationMemberArray;
  Names: TStringArray;
  Index: integer;
begin
  Result := Heading(1, rsDocOperationsTitle) + Generated('operations') + Paragraph(rsDocOperationsIntro);
  Common := CommonMembers(ogTransform);
  Result := Result + Heading(2, rsDocCommonTitle) + MemberTable(Common);
  Result := Result + Paragraph(rsDocCommonEdges) + MemberTable(Copy(CommonMembers(ogEdge), Length(Common), MaxInt));
  Result := Result + Paragraph(rsDocCommonPoints) + MemberTable(Copy(CommonMembers(ogPoint), Length(Common), MaxInt));
  for Group := Low(TOperationGroup) to High(TOperationGroup) do
  begin
    Result := Result + Heading(2, GroupTitles[Group]);
    for Info in OperationInfos do
      if Info.Group = Group then
      begin
        Result := Result + Heading(3, Info.Title + ' (' + Code(Info.TypeName) + ')') + Paragraph(Info.Summary);
        if Info.Properties <> '' then
        begin
          // A condition in brackets stays outside the code: .angle (when straight)
          Names := Info.Properties.Split([', ']);
          for Index := 0 to High(Names) do
            if Pos(' (', Names[Index]) > 0 then
              Names[Index] := Code('.' + Copy(Names[Index], 1, Pos(' (', Names[Index]) - 1)) +
                Copy(Names[Index], Pos(' (', Names[Index]), MaxInt)
            else
              Names[Index] := Code('.' + Names[Index]);
          Result := Result + Paragraph(Format(rsDocReads, [string.Join(', ', Names)]));
        end;
        Result := Result + MemberTable(Info.Members);
      end;
  end;
end;

function ApiKindText(const Param: TApiParam): string;
begin
  case Param.Kind of
    apTarget: Result := rsDocApiKindTarget;
    apText: Result := rsDocKindText;
    apNumber: Result := rsDocKindSize;
    apWhole: Result := rsDocKindWhole;
    apFlag: Result := rsDocKindFlag;
    apFormula: Result := rsDocApiKindFormula;
    apReference: Result := rsDocApiKindReference;
    apReferences: Result := rsDocApiKindReferences;
    apMaterial: Result := rsDocApiKindMaterial;
    apChoice: Result := Format(rsDocKindChoice, [CodedList(Param.Choices)]);
    apNames: Result := Format(rsDocApiKindNames, [CodedList(Param.Choices)]);
    apList: Result := rsDocKindList;
    apGroup: Result := rsDocKindGroup;
    else
      Result := rsDocApiKindMembers;
  end;
end;

function ApiParamName(const Param: TApiParam): string;
begin
  if Param.Kind = apMembers then
    Result := rsDocTheMembers
  else if (Param.Kind = apTarget) and (Pos('[].', Param.Name) > 0) then
    Result := Code(Copy(Param.Name, 1, Pos('[].', Param.Name) + 2) + 'id') + ' or ' +
      Code(Copy(Param.Name, 1, Pos('[].', Param.Name) + 2) + 'name')
  else if Param.Kind = apTarget then
    Result := rsDocTargetName
  else
    Result := Code(Param.Name);
end;

function ApiPage: string;
const
  GroupTitles: array[TApiMethodGroup] of string = (rsDocApiGroupFiles, rsDocApiGroupMeasurements, rsDocApiGroupObjects,
    rsDocApiGroupDrafting, rsDocApiGroupPieces, rsDocApiGroupMaterials, rsDocApiGroupSeams, rsDocApiGroupNotes,
    rsDocApiGroupChecking);
var
  Group: TApiMethodGroup;
  Method: TApiMethod;
  Param: TApiParam;
  Required: string;
begin
  Result := Heading(1, rsDocApiTitle) + Generated('api') + Paragraph(rsDocApiIntro) + Paragraph(rsDocApiExample);
  Result := Result + Paragraph('```' + LineEnding + '--> {"jsonrpc": "2.0", "id": 1, "method": "set_formula", ' +
    '"params": {"name": "B", "field": "length", "formula": "@waist / 4 + #ease"}}' + LineEnding +
    '<-- {"jsonrpc": "2.0", "id": 1, "result": {"id": 3, "name": "B", "type": "offsetPoint", ...}}' + LineEnding + '```');
  Result := Result + Heading(2, rsDocApiErrorsTitle) + Paragraph(rsDocApiErrorsIntro) + HeaderRow([rsDocCode, rsDocMeaning]);
  Result := Result + Row([IntToStr(RpcParseError), rsDocApiErrorParse]) + Row([IntToStr(RpcInvalidRequest), rsDocApiErrorRequest]) +
    Row([IntToStr(RpcMethodNotFound), rsDocApiErrorMethod]) + Row([IntToStr(RpcInvalidParams), rsDocApiErrorParams]) +
    Row([IntToStr(RpcInternalError), rsDocApiErrorInternal]) + Row([IntToStr(RpcRefused), rsDocApiErrorRefused]) + LineEnding;
  for Group := Low(TApiMethodGroup) to High(TApiMethodGroup) do
  begin
    Result := Result + Heading(2, GroupTitles[Group]);
    for Method in ApiMethods do
      if Method.Group = Group then
      begin
        Result := Result + Heading(3, Code(Method.Name)) + Paragraph(Method.Summary);
        if Length(Method.Params) = 0 then
          Result := Result + Paragraph(rsDocNoParameters)
        else
        begin
          Result := Result + HeaderRow([rsDocParameter, rsDocValue, rsDocRequired, rsDocDescription]);
          for Param in Method.Params do
          begin
            Required := '';
            if Param.Required then
              Required := rsDocYes;
            Result := Result + Row([ApiParamName(Param), ApiKindText(Param), Required, Cell(Param.Description)]);
          end;
          Result := Result + LineEnding;
        end;
        Result := Result + Paragraph(Format(rsDocReturns, [Method.Returns]));
      end;
  end;
end;

function CliPage: string;
var
  Command: TCliCommand;
  Option: TCliOption;
  Argument: TCliArgument;
  Names: string;
  Status: integer;
begin
  Result := Heading(1, rsDocCliTitle) + Generated('cli') + Paragraph(rsDocCliIntro);
  Result := Result + Paragraph('```' + LineEnding + CliTitle + ' [options] <command> [arguments]' + LineEnding + '```');
  Result := Result + Heading(2, rsDocCommands);
  for Command in CliCommands do
  begin
    Result := Result + Heading(3, Command.Name) + Paragraph(Command.Description);
    // Each way of calling it on a line of its own
    Result := Result + Paragraph('```' + LineEnding + CliTitle + ' ' + StringReplace(Command.Usage, LineEnding,
      LineEnding + CliTitle + ' ', [rfReplaceAll]) + LineEnding + '```');
  end;
  Result := Result + Heading(2, rsDocOptions) + HeaderRow([rsDocOption, rsDocValue, rsDocDescription]);
  for Option in CliOptions do
  begin
    Names := Code(Option.Long);
    if Option.Short <> '' then
      Names := Code(Option.Short) + ', ' + Names;
    Result := Result + Row([Names, Option.Parameter, Cell(Option.Description)]);
  end;
  Result := Result + LineEnding + Heading(2, rsDocArgumentsTitle) + Paragraph(rsDocArgumentsIntro) +
    HeaderRow([rsDocArgument, rsDocDescription]);
  for Argument in CliArguments do
    Result := Result + Row([Code(Argument.Name), Cell(Argument.Description)]);
  Result := Result + LineEnding + Heading(2, rsDocExitCodes) + HeaderRow([rsDocCode, rsDocMeaning]);
  for Status := Low(CliExitCodes) to High(CliExitCodes) do
    Result := Result + Row([IntToStr(Status), CliExitCodes[Status]]);
end;

function ReferencePage(const Topic: string; out Markdown: string): boolean;
begin
  Result := True;
  if Topic = 'functions' then
    Markdown := FunctionsPage
  else if Topic = 'operations' then
    Markdown := OperationsPage
  else if Topic = 'cli' then
    Markdown := CliPage
  else if Topic = 'api' then
    Markdown := ApiPage
  else
  begin
    Markdown := '';
    Result := False;
  end;
  // Pages are written with LF line ends on every system
  Markdown := StringReplace(Markdown, LineEnding, #10, [rfReplaceAll]);
end;

end.
