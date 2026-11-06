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

// Output profiles: which marking roles and piece marks a kind of print
// includes, and whether it keeps the seam allowance. They describe a print,
// not a pattern, so they live in the app settings and a layout holds only a
// name. See Visibility, styles and output in the design document. No LCL.
unit Sloper.Core.OutputProfiles;

{$mode ObjFPC}{$H+}

interface

uses
  fpjson, Sloper.Core.Draft;

type
  // The marks a piece has besides its marking lines and cutting line
  TPieceMark = (pkSeamLine, pkNotches, pkGrainline, pkFoldBracket, pkLabels, pkHoles, pkStitchHoles);
  TPieceMarks = set of TPieceMark;

  // apNone cuts on the seam line
  TAllowanceChoice = (apKeep, apNone);

  // How a role prints on paper; Custom False keeps the built-in look
  TRoleStyle = record
    Custom: boolean;
    // #rrggbb
    Color: string;
    Dashes: TDashPattern;
    // In mm
    Width: double;
  end;

  TRoleStyles = array[TEdgeRole] of TRoleStyle;

  TOutputProfile = record
    Name: string;
    // Marking roles only; construction and outline lines never print
    Roles: TEdgeRoles;
    PieceMarks: TPieceMarks;
    Allowance: TAllowanceChoice;
    Styles: TRoleStyles;
  end;

  TOutputProfileArray = array of TOutputProfile;

const
  AllPieceMarks = [Low(TPieceMark)..High(TPieceMark)];
  // As written in settings files
  PieceMarkNames: array[TPieceMark] of string = ('seamLine', 'notches', 'grainline', 'foldBracket', 'labels', 'holes', 'stitchHoles');
  AllowanceChoiceNames: array[TAllowanceChoice] of string = ('keep', 'none');

// Everything, as a layout without a profile prints
function FullOutputProfile: TOutputProfile;
// Home printing, Plotter or laser cutter, Leather and Instructions sheet
function BuiltInOutputProfiles: TOutputProfileArray;
function IsBuiltInOutputProfile(const AName: string): boolean;
// The built-in profiles, then the user's, ignoring case. A user profile with
// a built-in name is never found, so a built-in one always prints the same.
function FindOutputProfile(const Profiles: TOutputProfileArray; const AName: string; out Found: TOutputProfile): boolean;
// Built-in profiles followed by the user's that do not clash with them
function AllOutputProfiles(const Profiles: TOutputProfileArray): TOutputProfileArray;
function OutputProfilesToJSON(const Profiles: TOutputProfileArray): TJSONArray;
// A profile with no name, or a built-in one's name, is skipped; unknown
// roles, marks and bad styles are passed over
function OutputProfilesFromJSON(Data: TJSONData): TOutputProfileArray;

implementation

uses
  SysUtils, Sloper.Core.JSON, Sloper.Core.MachineProfiles;

const
  // Layouts store these names, so they are not translated
  ProfileHome = 'Home printing';
  ProfileCutter = 'Plotter or laser cutter';
  ProfileLeather = 'Leather';
  ProfileInstructions = 'Instructions sheet';

function FullOutputProfile: TOutputProfile;
begin
  Result := Default(TOutputProfile);
  Result.Roles := MarkingRoles;
  Result.PieceMarks := AllPieceMarks;
  Result.Allowance := apKeep;
end;

function BuiltInOutputProfiles: TOutputProfileArray;

  function Profile(const AName: string; ARoles: TEdgeRoles; AMarks: TPieceMarks; AAllowance: TAllowanceChoice): TOutputProfile;
  begin
    Result := Default(TOutputProfile);
    Result.Name := AName;
    Result.Roles := ARoles;
    Result.PieceMarks := AMarks;
    Result.Allowance := AAllowance;
  end;

begin
  Result := [Profile(ProfileHome, MarkingRoles, AllPieceMarks, apKeep),
    Profile(ProfileCutter, [erCut], [pkHoles, pkStitchHoles], apKeep),
    Profile(ProfileLeather, [erStitch, erCut, erSkive, erEdgeFinish], [pkNotches, pkGrainline, pkLabels, pkHoles, pkStitchHoles], apNone),
    Profile(ProfileInstructions, [erPlacement, erStitch, erFold], [pkSeamLine, pkNotches, pkLabels], apKeep)];
end;

function IsBuiltInOutputProfile(const AName: string): boolean;
var
  Profile: TOutputProfile;
begin
  for Profile in BuiltInOutputProfiles do
    if SameText(Profile.Name, AName) then
      Exit(True);
  Result := False;
end;

function FindOutputProfile(const Profiles: TOutputProfileArray; const AName: string; out Found: TOutputProfile): boolean;
var
  Profile: TOutputProfile;
begin
  for Profile in AllOutputProfiles(Profiles) do
    if SameText(Profile.Name, AName) then
    begin
      Found := Profile;
      Exit(True);
    end;
  Found := FullOutputProfile;
  Result := False;
end;

function AllOutputProfiles(const Profiles: TOutputProfileArray): TOutputProfileArray;
var
  Profile: TOutputProfile;
begin
  Result := BuiltInOutputProfiles;
  for Profile in Profiles do
    if not IsBuiltInOutputProfile(Profile.Name) then
      Insert(Profile, Result, Length(Result));
end;

function OutputProfilesToJSON(const Profiles: TOutputProfileArray): TJSONArray;
var
  Profile: TOutputProfile;
  Item, Styles, Style: TJSONObject;
  List, Dashes: TJSONArray;
  Role: TEdgeRole;
  Mark: TPieceMark;
  Length: double;
begin
  Result := TJSONArray.Create;
  try
    for Profile in Profiles do
    begin
      Item := TJSONObject.Create;
      Result.Add(Item);
      Item.Add('name', Profile.Name);
      List := TJSONArray.Create;
      Item.Add('roles', List);
      for Role := Low(TEdgeRole) to High(TEdgeRole) do
        if Role in Profile.Roles then
          List.Add(EdgeRoleNames[Role]);
      List := TJSONArray.Create;
      Item.Add('pieceMarks', List);
      for Mark := Low(TPieceMark) to High(TPieceMark) do
        if Mark in Profile.PieceMarks then
          List.Add(PieceMarkNames[Mark]);
      Item.Add('allowance', AllowanceChoiceNames[Profile.Allowance]);
      Styles := nil;
      for Role := Low(TEdgeRole) to High(TEdgeRole) do
      begin
        if not Profile.Styles[Role].Custom then
          Continue;
        if not Assigned(Styles) then
        begin
          Styles := TJSONObject.Create;
          Item.Add('styles', Styles);
        end;
        Style := TJSONObject.Create;
        Styles.Add(EdgeRoleNames[Role], Style);
        Style.Add('color', Profile.Styles[Role].Color);
        Dashes := TJSONArray.Create;
        Style.Add('dash', Dashes);
        for Length in Profile.Styles[Role].Dashes do
          if Length > 0 then
            Dashes.Add(JSONFloat(Length));
        Style.Add('width', JSONFloat(Profile.Styles[Role].Width));
      end;
    end;
  except
    FreeAndNil(Result);
    raise;
  end;
end;

function ReadNames(Data: TJSONData): TStringArray;
var
  Index: integer;
begin
  Result := nil;
  if not Assigned(Data) or (Data.JSONType <> jtArray) then
    Exit;
  for Index := 0 to Data.Count - 1 do
    if Data.Items[Index].JSONType = jtString then
      Insert(Data.Items[Index].AsString, Result, System.Length(Result));
end;

// Colour, up to four dash lengths and a width above 0, or none of it
function ReadStyle(Data: TJSONData; out Style: TRoleStyle): boolean;
var
  Obj: TJSONObject;
  Dashes: TJSONData;
  Index: integer;
begin
  Style := Default(TRoleStyle);
  if not Assigned(Data) or (Data.JSONType <> jtObject) then
    Exit(False);
  Obj := TJSONObject(Data);
  if not GetJSONString(Obj, 'color', Style.Color) or not IsHexColor(Style.Color) then
    Exit(False);
  if not GetJSONNumber(Obj, 'width', Style.Width) or (Style.Width <= 0) then
    Exit(False);
  Dashes := Obj.Find('dash');
  if Assigned(Dashes) then
  begin
    if (Dashes.JSONType <> jtArray) or (Dashes.Count > System.Length(Style.Dashes)) then
      Exit(False);
    for Index := 0 to Dashes.Count - 1 do
    begin
      if Dashes.Items[Index].JSONType <> jtNumber then
        Exit(False);
      Style.Dashes[Index] := Dashes.Items[Index].AsFloat;
      if Style.Dashes[Index] <= 0 then
        Exit(False);
    end;
  end;
  Style.Custom := True;
  Result := True;
end;

function OutputProfilesFromJSON(Data: TJSONData): TOutputProfileArray;
var
  Index: integer;
  Item: TJSONObject;
  Profile: TOutputProfile;
  Found: TEdgeRoles;
  Text: string;
  Role: TEdgeRole;
  Mark: TPieceMark;
  Styles: TJSONData;
begin
  Result := nil;
  if not Assigned(Data) or (Data.JSONType <> jtArray) then
    Exit;
  for Index := 0 to Data.Count - 1 do
  begin
    if Data.Items[Index].JSONType <> jtObject then
      Continue;
    Item := TJSONObject(Data.Items[Index]);
    Profile := FullOutputProfile;
    if not GetJSONString(Item, 'name', Profile.Name) or (Trim(Profile.Name) = '') or IsBuiltInOutputProfile(Profile.Name) then
      Continue;
    if Assigned(Item.Find('roles')) then
    begin
      Profile.Roles := [];
      for Text in ReadNames(Item.Find('roles')) do
        if NamesToRoles([Text], Found) then
          Profile.Roles := Profile.Roles + Found * MarkingRoles;
    end;
    if Assigned(Item.Find('pieceMarks')) then
    begin
      Profile.PieceMarks := [];
      for Text in ReadNames(Item.Find('pieceMarks')) do
        for Mark := Low(TPieceMark) to High(TPieceMark) do
          if PieceMarkNames[Mark] = Text then
            Include(Profile.PieceMarks, Mark);
    end;
    if GetJSONString(Item, 'allowance', Text) and (Text = AllowanceChoiceNames[apNone]) then
      Profile.Allowance := apNone;
    Styles := Item.Find('styles');
    if Assigned(Styles) and (Styles.JSONType = jtObject) then
      for Role := Low(TEdgeRole) to High(TEdgeRole) do
        if (Role in MarkingRoles) and not ReadStyle(TJSONObject(Styles).Find(EdgeRoleNames[Role]), Profile.Styles[Role]) then
          Profile.Styles[Role] := Default(TRoleStyle);
    Insert(Profile, Result, System.Length(Result));
  end;
end;

end.
