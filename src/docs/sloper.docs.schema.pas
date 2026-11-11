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

// JSON Schemas (draft 2020-12) of the user files, from the tables in
// Sloper.Core.FileInfo and, for a pattern's objects, Sloper.Core.OperationInfo.
// A schema describes the files the program writes: every member it lists and
// no others, with the members a file needs to load marked required.
unit Sloper.Docs.Schema;

{$mode ObjFPC}{$H+}

interface

const
  SCHEMA_SUFFIX = '.schema.json';

// The schema of the file whose "format" is FormatName, as text; False when
// there is no such format
function FileSchema(const FormatName: string; out Text: string): boolean;

resourcestring
  rsSchemaTitle = 'OpenSloper %s file (%s)';
  rsSchemaGenerated = 'Generated from the program by opensloper-cli doc %s; do not edit it by hand.';
  rsSchemaObject = 'An object of a pattern: a point, edge, transform, piece, seam or note';

implementation

uses
  SysUtils, fpjson, Sloper.Core.JSON, Sloper.Core.OperationInfo, Sloper.Core.FileInfo;

const
  SCHEMA_BASE_URL = 'https://billbsing.github.io/opensloper/reference/schemas/';
  OBJECT_DEF = 'object';

function IsListOfValues(const Member: TOperationMember): boolean;
begin
  Result := Member.Name.EndsWith('[]');
end;

// The member's own name inside its parent: grainline.start is start
function LocalName(const Member: TOperationMember; const Prefix: string): string;
begin
  Result := Copy(Member.Name, Length(Prefix) + 1, MaxInt);
  if Result.EndsWith('[]') then
    SetLength(Result, Length(Result) - 2);
end;

function IsChildOf(const Member: TOperationMember; const Prefix: string): boolean;
var
  Rest: string;
begin
  if not Member.Name.StartsWith(Prefix) then
    Exit(False);
  Rest := LocalName(Member, Prefix);
  Result := (Rest <> '') and (Pos('.', Rest) = 0) and (Pos('[', Rest) = 0);
end;

procedure AddValueSchema(Into: TJSONObject; const Member: TOperationMember);
var
  Choices: TStringArray;
  Choice: string;
  Values: TJSONArray;
begin
  case Member.Kind of
    mkLength, mkAngle, mkNumber, mkLengthOrRatio, mkFormula, mkText:
      Into.Add('type', 'string');
    mkPoint, mkEdge, mkPiece, mkObject, mkMaterial:
    begin
      Into.Add('type', 'integer');
      Into.Add('minimum', 1);
    end;
    mkWhole:
      Into.Add('type', 'integer');
    mkSize:
      Into.Add('type', 'number');
    mkSizeOrNull:
      Into.Add('type', TJSONArray.Create(['number', 'null']));
    mkFlag:
      Into.Add('type', 'boolean');
    mkChoice:
    begin
      Choices := Member.Choices.Split([', ']);
      if Length(Choices) = 1 then
        Into.Add('const', Choices[0])
      else
      begin
        Values := TJSONArray.Create;
        Into.Add('enum', Values);
        for Choice in Choices do
          Values.Add(Choice);
      end;
    end;
    mkPatternObject:
      Into.Add('$ref', '#/$defs/' + OBJECT_DEF);
  end;
end;

procedure AddObjectSchema(Into: TJSONObject; const Members: TOperationMemberArray; const Prefix: string); forward;

function MemberSchema(const Members: TOperationMemberArray; const Member: TOperationMember): TJSONObject;
var
  Items: TJSONObject;
begin
  Result := TJSONObject.Create(['description', Member.Description]);
  if IsListOfValues(Member) or (Member.Kind = mkList) then
  begin
    Result.Add('type', 'array');
    Items := TJSONObject.Create;
    Result.Add('items', Items);
    if IsListOfValues(Member) then
      AddValueSchema(Items, Member)
    else
      AddObjectSchema(Items, Members, Member.Name + '[].');
  end
  else if Member.Kind = mkGroup then
    AddObjectSchema(Result, Members, Member.Name + '.')
  else
    AddValueSchema(Result, Member);
end;

// The members directly under Prefix, as an object that takes no others
procedure AddObjectSchema(Into: TJSONObject; const Members: TOperationMemberArray; const Prefix: string);
var
  Properties: TJSONObject;
  Required: TJSONArray;
  Member: TOperationMember;
begin
  Into.Add('type', 'object');
  Properties := TJSONObject.Create;
  Into.Add('properties', Properties);
  Required := TJSONArray.Create;
  for Member in Members do
    if IsChildOf(Member, Prefix) then
    begin
      Properties.Add(LocalName(Member, Prefix), MemberSchema(Members, Member));
      if Member.Required then
        Required.Add(LocalName(Member, Prefix));
    end;
  if Required.Count > 0 then
    Into.Add('required', Required)
  else
    FreeAndNil(Required);
  Into.Add('additionalProperties', False);
end;

// An object takes the members of its type
function PatternObjectDefs: TJSONObject;
var
  Info: TOperationInfo;
  Root, Condition, Branch, Def: TJSONObject;
  Types, Branches: TJSONArray;
begin
  Result := TJSONObject.Create;
  Root := TJSONObject.Create(['description', rsSchemaObject, 'type', 'object']);
  Result.Add(OBJECT_DEF, Root);
  Root.Add('required', TJSONArray.Create(['id', 'type']));
  Types := TJSONArray.Create;
  Root.Add('properties', TJSONObject.Create(['type', TJSONObject.Create(['enum', Types])]));
  Branches := TJSONArray.Create;
  Root.Add('allOf', Branches);
  for Info in OperationInfos do
  begin
    Types.Add(Info.TypeName);
    Condition := TJSONObject.Create(['required', TJSONArray.Create(['type']), 'properties',
      TJSONObject.Create(['type', TJSONObject.Create(['const', Info.TypeName])])]);
    Branch := TJSONObject.Create(['if', Condition, 'then', TJSONObject.Create(['$ref', '#/$defs/' + Info.TypeName])]);
    Branches.Add(Branch);
    Def := TJSONObject.Create(['description', Info.Title]);
    Result.Add(Info.TypeName, Def);
    AddObjectSchema(Def, Concat(CommonMembers(Info.Group), Info.Members), '');
  end;
end;

function HasObjects(const Info: TFileFormatInfo): boolean;
var
  Member: TOperationMember;
begin
  Result := False;
  for Member in Info.Members do
    Result := Result or (Member.Kind = mkPatternObject);
end;

function FileSchema(const FormatName: string; out Text: string): boolean;
var
  Info: TFileFormatInfo;
  Schema: TJSONObject;
begin
  Text := '';
  if not FindFileFormatInfo(FormatName, Info) then
    Exit(False);
  Schema := TJSONObject.Create;
  try
    Schema.Add('$schema', 'https://json-schema.org/draft/2020-12/schema');
    Schema.Add('$id', SCHEMA_BASE_URL + FormatName + SCHEMA_SUFFIX);
    Schema.Add('$comment', Format(rsSchemaGenerated, [FormatName + SCHEMA_SUFFIX]));
    Schema.Add('title', Format(rsSchemaTitle, [LowerCase(Info.Title), Info.Extension]));
    Schema.Add('description', Info.Summary);
    AddObjectSchema(Schema, Info.Members, '');
    if HasObjects(Info) then
      Schema.Add('$defs', PatternObjectDefs);
    Text := JSONToText(Schema);
  finally
    FreeAndNil(Schema);
  end;
  Result := True;
end;

end.
