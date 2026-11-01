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

// Machine profiles: how a laser, plotter or cutting machine wants each line
// type drawn. They describe a machine, so they live in the app settings, and a
// layout holds only a name. See Accessories in the design document. No LCL.
unit Sloper.Core.MachineProfiles;

{$mode ObjFPC}{$H+}

interface

uses
  fpjson;

type
  TLineType = (ltCut, ltScore, ltMark, ltEngrave, ltHole);

  TLineStyle = record
    Enabled: boolean;
    // #rrggbb
    Color, Layer: string;
    Width: double;
  end;

  TMachineProfile = record
    Name: string;
    Lines: array[TLineType] of TLineStyle;
  end;

  TMachineProfileArray = array of TMachineProfile;

const
  StandardProfileName = 'Standard';
  LineTypeNames: array[TLineType] of string = ('cut', 'score', 'mark', 'engrave', 'hole');
  // Outlines last, as a piece cut free can shift before its holes are cut
  MachineOrder: array[0..4] of TLineType = (ltScore, ltMark, ltEngrave, ltHole, ltCut);

function StandardProfile: TMachineProfile;
// Ignoring case. A profile in the list goes before the built-in one.
function FindMachineProfile(const Profiles: TMachineProfileArray; const AName: string; out Found: TMachineProfile): boolean;
function IsHexColor(const Text: string): boolean;
function MachineProfilesToJSON(const Profiles: TMachineProfileArray): TJSONArray;
// A profile with no name is skipped, and a bad value keeps Standard's
function MachineProfilesFromJSON(Data: TJSONData): TMachineProfileArray;

implementation

uses
  SysUtils, Sloper.Core.JSON;

const
  DefaultWidth = 0.1;

function StandardProfile: TMachineProfile;

  procedure SetLine(Kind: TLineType; const AColor, ALayer: string);
  begin
    Result.Lines[Kind].Enabled := True;
    Result.Lines[Kind].Color := AColor;
    Result.Lines[Kind].Layer := ALayer;
    Result.Lines[Kind].Width := DefaultWidth;
  end;

begin
  Result := Default(TMachineProfile);
  Result.Name := StandardProfileName;
  SetLine(ltCut, '#ff0000', 'Cut');
  SetLine(ltScore, '#0000ff', 'Score');
  SetLine(ltMark, '#000000', 'Mark');
  SetLine(ltEngrave, '#00ff00', 'Engrave');
  SetLine(ltHole, '#ff0000', 'Hole');
end;

function FindMachineProfile(const Profiles: TMachineProfileArray; const AName: string; out Found: TMachineProfile): boolean;
var
  Profile: TMachineProfile;
begin
  for Profile in Profiles do
    if SameText(Profile.Name, AName) then
    begin
      Found := Profile;
      Exit(True);
    end;
  Found := StandardProfile;
  Result := SameText(AName, StandardProfileName);
end;

function IsHexColor(const Text: string): boolean;
var
  Index: integer;
begin
  Result := (Length(Text) = 7) and (Text[1] = '#');
  if Result then
    for Index := 2 to 7 do
      if not (Text[Index] in ['0'..'9', 'a'..'f', 'A'..'F']) then
        Exit(False);
end;

function MachineProfilesToJSON(const Profiles: TMachineProfileArray): TJSONArray;
var
  Profile: TMachineProfile;
  Item, Lines, Line: TJSONObject;
  Kind: TLineType;
begin
  Result := TJSONArray.Create;
  try
    for Profile in Profiles do
    begin
      Item := TJSONObject.Create;
      Result.Add(Item);
      Item.Add('name', Profile.Name);
      Lines := TJSONObject.Create;
      Item.Add('lines', Lines);
      for Kind := Low(TLineType) to High(TLineType) do
      begin
        Line := TJSONObject.Create;
        Lines.Add(LineTypeNames[Kind], Line);
        Line.Add('on', Profile.Lines[Kind].Enabled);
        Line.Add('color', Profile.Lines[Kind].Color);
        Line.Add('layer', Profile.Lines[Kind].Layer);
        Line.Add('width', JSONFloat(Profile.Lines[Kind].Width));
      end;
    end;
  except
    FreeAndNil(Result);
    raise;
  end;
end;

procedure ReadLine(Item: TJSONObject; var Style: TLineStyle);
var
  Text: string;
  Width: double;
  Shown: boolean;
begin
  if GetJSONBoolean(Item, 'on', Shown) then
    Style.Enabled := Shown;
  if GetJSONString(Item, 'color', Text) and IsHexColor(Text) then
    Style.Color := Text;
  if GetJSONString(Item, 'layer', Text) and (Trim(Text) <> '') then
    Style.Layer := Text;
  if GetJSONNumber(Item, 'width', Width) and (Width > 0) then
    Style.Width := Width;
end;

function MachineProfilesFromJSON(Data: TJSONData): TMachineProfileArray;
var
  Index: integer;
  Item: TJSONObject;
  Lines, Line: TJSONData;
  Profile: TMachineProfile;
  Kind: TLineType;
  AName: string;
begin
  Result := nil;
  if (Data = nil) or (Data.JSONType <> jtArray) then
    Exit;
  for Index := 0 to Data.Count - 1 do
  begin
    if Data.Items[Index].JSONType <> jtObject then
      Continue;
    Item := TJSONObject(Data.Items[Index]);
    if not GetJSONString(Item, 'name', AName) or (Trim(AName) = '') then
      Continue;
    Profile := StandardProfile;
    Profile.Name := AName;
    Lines := Item.Find('lines');
    if (Lines <> nil) and (Lines.JSONType = jtObject) then
      for Kind := Low(TLineType) to High(TLineType) do
      begin
        Line := TJSONObject(Lines).Find(LineTypeNames[Kind]);
        if (Line <> nil) and (Line.JSONType = jtObject) then
          ReadLine(TJSONObject(Line), Profile.Lines[Kind]);
      end;
    Insert(Profile, Result, Length(Result));
  end;
end;

end.
