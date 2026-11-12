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

// The box a note's font is chosen in, in the design and publish apps: the
// default font first, then the system's fonts, and a name can be typed.
unit Sloper.UI.FontBox;

{$mode ObjFPC}{$H+}

interface

uses
  Classes, StdCtrls;

// An editable box listing the fonts; Changed runs when one is picked from
// the list or a typed name is finished
function NewFontBox(Owner: TComponent; Changed: TNotifyEvent): TComboBox;
// The font the box names; empty for the default
function FontBoxName(Box: TComboBox): string;
procedure ShowFontName(Box: TComboBox; const AName: string);

resourcestring
  rsFontBoxDefault = 'Default (sans-serif)';
  rsFontBoxHint = 'The font it prints in. One not installed, or with PostScript outlines, prints in the default font.';

implementation

uses
  SysUtils, Forms;

const
  // Fonts shown at once when the list opens
  FONT_LIST_ROWS = 20;

var
  FontNames: TStringList;

// Read once: Screen.Fonts asks the system each time. Names starting with @
// are the vertical forms of East Asian fonts.
function SortedFontNames: TStringList;
var
  Name: string;
begin
  if not Assigned(FontNames) then
  begin
    FontNames := TStringList.Create;
    FontNames.Sorted := True;
    FontNames.Duplicates := dupIgnore;
    FontNames.CaseSensitive := False;
    for Name in Screen.Fonts do
      if (Name <> '') and not Name.StartsWith('@') then
        FontNames.Add(Name);
  end;
  Result := FontNames;
end;

function NewFontBox(Owner: TComponent; Changed: TNotifyEvent): TComboBox;
begin
  Result := TComboBox.Create(Owner);
  Result.Style := csDropDown;
  Result.Items.Add(rsFontBoxDefault);
  Result.Items.AddStrings(SortedFontNames);
  Result.DropDownCount := FONT_LIST_ROWS;
  Result.Hint := rsFontBoxHint;
  Result.ShowHint := True;
  Result.OnSelect := Changed;
  Result.OnEditingDone := Changed;
end;

function FontBoxName(Box: TComboBox): string;
begin
  Result := Trim(Box.Text);
  if SameText(Result, rsFontBoxDefault) then
    Result := '';
end;

procedure ShowFontName(Box: TComboBox; const AName: string);
begin
  if AName = '' then
    Box.Text := rsFontBoxDefault
  else
    Box.Text := AName;
end;

finalization
  FreeAndNil(FontNames);

end.
