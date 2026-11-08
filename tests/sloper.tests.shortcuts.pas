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

// The shortcuts table: every key an app sets from it is one key press, and no
// app gives one key press to two commands.
unit Sloper.Tests.Shortcuts;

{$mode ObjFPC}{$H+}

interface

uses
  fpcunit, testregistry, Sloper.Tests.TestCase;

type
  TTestShortcuts = class(TOSTestCase)
  published
    procedure TestCommandsAreOneKeyPress;
    procedure TestNoKeyTwiceInAnApp;
    procedure TestParse;
  end;

implementation

uses
  SysUtils, Sloper.Core.Shortcuts;

// Keys in one form however they were written: Shift+Mod+S is Mod+Shift+S
function KeyPress(const Keys: string): string;
var
  Key: string;
  Modifiers: TShortcutModifiers;
begin
  if not ParseShortcut(Keys, Key, Modifiers) then
    Exit('');
  Result := '';
  if smMod in Modifiers then
    Result := Result + 'Mod+';
  if smShift in Modifiers then
    Result := Result + 'Shift+';
  if smAlt in Modifiers then
    Result := Result + 'Alt+';
  Result := Result + Key;
end;

procedure TTestShortcuts.TestCommandsAreOneKeyPress;
var
  Command: TKeyCommand;
  Info: TShortcutInfo;
begin
  for Command := Low(TKeyCommand) to High(TKeyCommand) do
  begin
    Info := ShortcutInfo(Command);
    AssertTrue(Info.Description, Info.Apps <> []);
    if Info.Kind = skCommand then
      AssertTrue(Info.Keys + ' is not one key press', KeyPress(Info.Keys) <> '');
  end;
end;

procedure TTestShortcuts.TestNoKeyTwiceInAnApp;
var
  App: TShortcutApp;
  Command, Other: TKeyCommand;
  Info, OtherInfo: TShortcutInfo;
begin
  for App := Low(TShortcutApp) to High(TShortcutApp) do
    for Command := Low(TKeyCommand) to High(TKeyCommand) do
    begin
      Info := ShortcutInfo(Command);
      if (Info.Kind <> skCommand) or not (App in Info.Apps) then
        Continue;
      for Other := Succ(Command) to High(TKeyCommand) do
      begin
        OtherInfo := ShortcutInfo(Other);
        if (OtherInfo.Kind = skCommand) and (App in OtherInfo.Apps) then
          AssertFalse(Format('%s is both "%s" and "%s"', [Info.Keys, Info.Description, OtherInfo.Description]),
            KeyPress(Info.Keys) = KeyPress(OtherInfo.Keys));
      end;
    end;
end;

procedure TTestShortcuts.TestParse;
var
  Key: string;
  Modifiers: TShortcutModifiers;
begin
  AssertTrue(ParseShortcut('Mod+Shift+S', Key, Modifiers));
  AssertEquals('S', Key);
  AssertTrue(Modifiers = [smMod, smShift]);
  AssertTrue(ParseShortcut('Escape', Key, Modifiers));
  AssertEquals('Escape', Key);
  AssertTrue(Modifiers = []);
  AssertEquals('Mod+Shift+Z', KeyPress('Shift+Mod+Z'));
  AssertFalse('two keys', ParseShortcut('S+P', Key, Modifiers));
  AssertFalse('no key', ParseShortcut('Mod+Shift', Key, Modifiers));
  AssertFalse('not a key', ParseShortcut('Arrows', Key, Modifiers));
  AssertFalse('a mouse action', ParseShortcut('Alt+Click', Key, Modifiers));
  AssertFalse('lower case', ParseShortcut('Mod+s', Key, Modifiers));
end;

initialization
  RegisterTest(TTestShortcuts);
end.
