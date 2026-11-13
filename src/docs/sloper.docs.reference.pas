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
// one; opensloper-make.sh docs writes them all into docs/reference/. No LCL dependency.
unit Sloper.Docs.Reference;

{$mode ObjFPC}{$H+}

interface

const
  // A page is written to docs/reference/TOPIC.md, and a schema, whose topic is
  // its file name, to docs/reference/schemas/TOPIC; opensloper.py, the Python
  // client of the Automation API, to docs/reference/opensloper.py
  DOC_TOPICS: array[0..9] of string = ('functions', 'operations', 'files', 'shortcuts', 'cli', 'api', 'pattern.schema.json',
    'measurements.schema.json', 'layout.schema.json', 'opensloper.py');

// The page or schema for Topic; False when there is no such topic
function ReferencePage(const Topic: string; out Markdown: string): boolean;
// Where Topic is written, relative to docs/reference, with / between folders
function DocTopicPath(const Topic: string): string;

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
  rsDocKindListOf = 'list, each %s';
  rsDocKindSizeOrNull = 'number or null';
  rsDocKindFormula = 'formula';
  rsDocKindPatternObject = 'object';
  rsDocFilesTitle = 'File formats';
  rsDocFilesIntro = 'The apps keep their files as JSON text, so other programs, scripts and assistants such as Claude ' +
    'can read and write them. Each kind of file is described here, and by a JSON Schema that a validator can check a ' +
    'file against.';
  rsDocFilesRulesTitle = 'Rules for every file';
  rsDocFilesRules =
    '- The file is UTF-8 JSON with one object at the top. Its `format` says what kind of file it is and its `version` ' +
    'which version of that format; a program refuses a file newer than it knows.' + LineEnding +
    '- Lengths in measurement and layout files are millimetres. A pattern''s formulas are in the pattern''s own ' +
    '`units`; a number may also carry its unit, as `2in`.' + LineEnding +
    '- Objects have IDs, whole numbers above 0 that never change and are never reused. Other objects and formulas refer ' +
    'to them by ID: a member such as `base` holds the number, and formula text writes it in braces, `{12}`. Names are ' +
    'for people: letters, digits and underscore, not starting with a digit.' + LineEnding +
    '- File names inside a file are relative to that file''s folder unless absolute, and written with `/`.' + LineEnding +
    '- The apps write every member in a fixed order, two spaces to a level, with numbers in the shortest form that ' +
    'reads back exactly and `.` as the decimal point, so files compare well in version control.' + LineEnding +
    '- Members marked required must be there for the file to load. Others may be left out of a file written by hand, ' +
    'and take their defaults. A file that does not load says why, and nothing of it is used.' + LineEnding +
    '- The schemas list exactly the members the apps write. The apps also read a few members older files have, which ' +
    'the schemas leave out.';
  rsDocFilesVersion = 'Version %d. JSON Schema: [%s](schemas/%s).';
  rsDocFilesObjects = 'Each entry in `objects` is an object whose members depend on its `type`; they are listed on ' +
    '[Operations and objects](operations.md).';
  rsDocExample = 'Example';
  rsDocShortcutsTitle = 'Keyboard shortcuts';
  rsDocShortcutsIntro = 'On macOS, Cmd takes the place of Ctrl. Keys on the canvas work while the canvas has the focus: ' +
    'click it first if you were typing in a panel.';
  rsDocKeys = 'Keys';
  rsDocWhatItDoes = 'What it does';
  rsDocAppDesign = 'Design app';
  rsDocAppMeasurements = 'Measurements app';
  rsDocAppPublish = 'Publish app';
  rsDocShortcutFile = 'File';
  rsDocShortcutEdit = 'Edit';
  rsDocShortcutView = 'View';
  rsDocShortcutTools = 'Tools';
  rsDocShortcutCanvas = 'On the canvas';
  rsDocShortcutPanels = 'In the tables';
  rsDocShortcutMouse = 'Mouse';
  rsDocKeysAnd = '%s and %s';
  rsDocKeyArrows = 'the arrow keys';
  rsDocKeyWheel = 'the wheel';
  rsDocKeyDrag = 'drag';
  rsDocKeyClick = 'click';
  rsDocKeyMiddleDrag = 'drag with the middle button';
  rsDocKeyRightClick = 'right-click';
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
  SysUtils, StrUtils, Sloper.Core.Formula, Sloper.Core.FormulaLexer, Sloper.Core.Units, Sloper.Core.OperationInfo, Sloper.Core.FileInfo,
  Sloper.Core.PatternFile, Sloper.Core.Shortcuts, Sloper.API.Server, Sloper.API.Methods, Sloper.CLI.Arguments, Sloper.Docs.Schema,
  Sloper.Docs.Python;

const
  MEMBER_KIND_TEXTS: array[TMemberKind] of string = (rsDocKindLength, rsDocKindAngle, rsDocKindNumber, rsDocKindLengthOrRatio,
    rsDocKindPoint, rsDocKindEdge, rsDocKindPiece, rsDocKindObject, rsDocKindMaterial, rsDocKindChoice, rsDocKindFlag,
    rsDocKindWhole, rsDocKindText, rsDocKindSize, rsDocKindSizeOrNull, rsDocKindFormula, rsDocKindPatternObject,
    rsDocKindList, rsDocKindGroup);
  KEY_WORDS: array[0..5] of string = ('Arrows', 'Wheel', 'Drag', 'Click', 'Middle-drag', 'Right-click');
  KEY_WORD_TEXTS: array[0..5] of string = (rsDocKeyArrows, rsDocKeyWheel, rsDocKeyDrag, rsDocKeyClick, rsDocKeyMiddleDrag,
    rsDocKeyRightClick);
  ARROW_KEYS: array[0..3] of string = ('Left', 'Right', 'Up', 'Down');
  SHORTCUT_APP_TITLES: array[TShortcutApp] of string = (rsDocAppDesign, rsDocAppMeasurements, rsDocAppPublish);
  SHORTCUT_GROUP_TITLES: array[TShortcutGroup] of string = (rsDocShortcutFile, rsDocShortcutEdit, rsDocShortcutView, rsDocShortcutTools,
    rsDocShortcutCanvas, rsDocShortcutPanels, rsDocShortcutMouse);
  OPERATION_GROUP_TITLES: array[TOperationGroup] of string = (rsDocGroupPoints, rsDocGroupEdges, rsDocGroupTransforms, rsDocGroupPieces,
    rsDocGroupAnnotations);
  API_GROUP_TITLES: array[TApiMethodGroup] of string = (rsDocApiGroupFiles, rsDocApiGroupMeasurements, rsDocApiGroupObjects,
    rsDocApiGroupDrafting, rsDocApiGroupPieces, rsDocApiGroupMaterials, rsDocApiGroupSeams, rsDocApiGroupNotes,
    rsDocApiGroupChecking);

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
    Result := Result + Row([Code(NUMBER_SUFFIX_NAMES[Suffix]), FormatFloat('0.##', NUMBER_SUFFIX_MILLIMETRES[Suffix])]);
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
begin
  if Member.Kind = mkChoice then
    Result := Format(rsDocKindChoice, [CodedList(Member.Choices)])
  else
    Result := MEMBER_KIND_TEXTS[Member.Kind];
  if Member.Name.EndsWith('[]') then
    Result := Format(rsDocKindListOf, [Result]);
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

// With a column for the members a file needs
function FileMemberTable(const Members: TOperationMemberArray): string;
var
  Member: TOperationMember;
  Required: string;
begin
  Result := HeaderRow([rsDocMember, rsDocValue, rsDocRequired, rsDocDescription]);
  for Member in Members do
  begin
    Required := '';
    if Member.Required then
      Required := rsDocYes;
    Result := Result + Row([Code(Member.Name), KindText(Member), Required, Cell(Member.Description)]);
  end;
  Result := Result + LineEnding;
end;

// Keys as the site draws them, ++ctrl+shift+s++, with mouse actions in words:
// Mod+Wheel is ++ctrl++ and the wheel
function KeysMarkdown(const Keys: string): string;
var
  Part, Pressed, Action, Name: string;
  Index: integer;
begin
  Pressed := '';
  Action := '';
  for Part in Keys.Split(['+']) do
  begin
    Index := IndexStr(Part, KEY_WORDS);
    if Index >= 0 then
    begin
      Action := KEY_WORD_TEXTS[Index];
      Continue;
    end;
    if Part = 'Mod' then
      Name := 'ctrl'
    else if IndexStr(Part, ARROW_KEYS) >= 0 then
      Name := 'arrow-' + LowerCase(Part)
    else
      Name := LowerCase(Part);
    if Pressed <> '' then
      Pressed := Pressed + '+';
    Pressed := Pressed + Name;
  end;
  if Pressed <> '' then
    Pressed := '++' + Pressed + '++';
  if (Pressed <> '') and (Action <> '') then
    Result := Format(rsDocKeysAnd, [Pressed, Action])
  else
    Result := Pressed + Action;
  if Result <> '' then
    Result[1] := UpCase(Result[1]);
end;

function ShortcutsPage: string;
var
  App: TShortcutApp;
  Group: TShortcutGroup;
  Command: TKeyCommand;
  Info: TShortcutInfo;
  Table: string;
begin
  Result := Heading(1, rsDocShortcutsTitle) + Generated('shortcuts') + Paragraph(rsDocShortcutsIntro);
  for App := Low(TShortcutApp) to High(TShortcutApp) do
  begin
    Result := Result + Heading(2, SHORTCUT_APP_TITLES[App]);
    for Group := Low(TShortcutGroup) to High(TShortcutGroup) do
    begin
      Table := '';
      for Command := Low(TKeyCommand) to High(TKeyCommand) do
      begin
        Info := ShortcutInfo(Command);
        if (Info.Group = Group) and (App in Info.Apps) then
          Table := Table + Row([KeysMarkdown(Info.Keys), Cell(Info.Description)]);
      end;
      if Table <> '' then
        Result := Result + Heading(3, SHORTCUT_GROUP_TITLES[Group]) + HeaderRow([rsDocKeys, rsDocWhatItDoes]) + Table + LineEnding;
    end;
  end;
end;

function FilesPage: string;
var
  Info: TFileFormatInfo;
  SchemaName: string;
begin
  Result := Heading(1, rsDocFilesTitle) + Generated('files') + Paragraph(rsDocFilesIntro);
  Result := Result + Heading(2, rsDocFilesRulesTitle) + Paragraph(rsDocFilesRules);
  for Info in FileFormatInfos do
  begin
    SchemaName := Info.FormatName + SCHEMA_SUFFIX;
    Result := Result + Heading(2, Info.Title + ' (' + Code(Info.Extension) + ')') + Paragraph(Info.Summary);
    Result := Result + Paragraph(Format(rsDocFilesVersion, [Info.Version, SchemaName, SchemaName]));
    Result := Result + FileMemberTable(Info.Members);
    if Info.FormatName = PATTERN_FORMAT then
      Result := Result + Paragraph(rsDocFilesObjects);
    Result := Result + Heading(3, rsDocExample) + Paragraph('```json' + LineEnding + Info.Example + LineEnding + '```');
  end;
end;

function OperationsPage: string;
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
    Result := Result + Heading(2, OPERATION_GROUP_TITLES[Group]);
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
  Result := Result + Row([IntToStr(RPC_PARSE_ERROR), rsDocApiErrorParse]) + Row([IntToStr(RPC_INVALID_REQUEST), rsDocApiErrorRequest]) +
    Row([IntToStr(RPC_METHOD_NOT_FOUND), rsDocApiErrorMethod]) + Row([IntToStr(RPC_INVALID_PARAMS), rsDocApiErrorParams]) +
    Row([IntToStr(RPC_INTERNAL_ERROR), rsDocApiErrorInternal]) + Row([IntToStr(RPC_REFUSED), rsDocApiErrorRefused]) + LineEnding;
  for Group := Low(TApiMethodGroup) to High(TApiMethodGroup) do
  begin
    Result := Result + Heading(2, API_GROUP_TITLES[Group]);
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
  Result := Result + Paragraph('```' + LineEnding + CLI_TITLE + ' [options] <command> [arguments]' + LineEnding + '```');
  Result := Result + Heading(2, rsDocCommands);
  for Command in CLI_COMMANDS do
  begin
    Result := Result + Heading(3, Command.Name) + Paragraph(Command.Description);
    // Each way of calling it on a line of its own
    Result := Result + Paragraph('```' + LineEnding + CLI_TITLE + ' ' + StringReplace(Command.Usage, LineEnding,
      LineEnding + CLI_TITLE + ' ', [rfReplaceAll]) + LineEnding + '```');
  end;
  Result := Result + Heading(2, rsDocOptions) + HeaderRow([rsDocOption, rsDocValue, rsDocDescription]);
  for Option in CLI_OPTIONS do
  begin
    Names := Code(Option.Long);
    if Option.Short <> '' then
      Names := Code(Option.Short) + ', ' + Names;
    Result := Result + Row([Names, Option.Parameter, Cell(Option.Description)]);
  end;
  Result := Result + LineEnding + Heading(2, rsDocArgumentsTitle) + Paragraph(rsDocArgumentsIntro) +
    HeaderRow([rsDocArgument, rsDocDescription]);
  for Argument in CLI_ARGUMENTS do
    Result := Result + Row([Code(Argument.Name), Cell(Argument.Description)]);
  Result := Result + LineEnding + Heading(2, rsDocExitCodes) + HeaderRow([rsDocCode, rsDocMeaning]);
  for Status := Low(CLI_EXIT_CODES) to High(CLI_EXIT_CODES) do
    Result := Result + Row([IntToStr(Status), CLI_EXIT_CODES[Status]]);
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
  else if Topic = 'files' then
    Markdown := FilesPage
  else if Topic = 'shortcuts' then
    Markdown := ShortcutsPage
  else if Topic = PYTHON_CLIENT_TOPIC then
    Markdown := PythonClient
  else if Topic.EndsWith(SCHEMA_SUFFIX) then
    Result := FileSchema(Copy(Topic, 1, Length(Topic) - Length(SCHEMA_SUFFIX)), Markdown)
  else
  begin
    Markdown := '';
    Result := False;
  end;
  // Pages are written with LF line ends on every system
  Markdown := StringReplace(Markdown, LineEnding, #10, [rfReplaceAll]);
end;

function DocTopicPath(const Topic: string): string;
begin
  if Topic.EndsWith(SCHEMA_SUFFIX) then
    Result := 'schemas/' + Topic
  else if Topic = PYTHON_CLIENT_TOPIC then
    Result := Topic
  else
    Result := Topic + '.md';
end;

end.
