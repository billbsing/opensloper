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

// Main application window.
unit osMainForm;

{$mode ObjFPC}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, Menus, Dialogs, LCLType;

type

  { TMainForm }

  TMainForm = class(TForm)
    MainMenu: TMainMenu;
    MenuFile: TMenuItem;
    MenuFileQuit: TMenuItem;
    MenuHelp: TMenuItem;
    MenuHelpAbout: TMenuItem;
    procedure FormCreate(Sender: TObject);
    procedure MenuFileQuitClick(Sender: TObject);
    procedure MenuHelpAboutClick(Sender: TObject);
  end;

var
  MainForm: TMainForm;

implementation

uses
  osVersion;

{$R *.lfm}

resourcestring
  rsMenuFile = '&File';
  rsMenuFileQuit = '&Quit';
  rsMenuHelp = '&Help';
  rsMenuHelpAbout = '&About OpenSloper';
  rsAboutText = '%s %s'#10#10
    + 'Parametric sewing pattern drafting.'#10#10
    + 'This program is free software: you can redistribute it and/or modify '
    + 'it under the terms of the GNU General Public License as published by '
    + 'the Free Software Foundation, either version 3 of the License, or '
    + '(at your option) any later version.'#10#10
    + 'This program comes with ABSOLUTELY NO WARRANTY.';

{ TMainForm }

procedure TMainForm.FormCreate(Sender: TObject);
begin
  Caption := AppName;
  MenuFile.Caption := rsMenuFile;
  MenuFileQuit.Caption := rsMenuFileQuit;
  MenuFileQuit.ShortCut := ShortCut(VK_Q, [ssModifier]);
  MenuHelp.Caption := rsMenuHelp;
  MenuHelpAbout.Caption := rsMenuHelpAbout;
end;

procedure TMainForm.MenuFileQuitClick(Sender: TObject);
begin
  Close;
end;

procedure TMainForm.MenuHelpAboutClick(Sender: TObject);
begin
  MessageDlg(Format(rsAboutText, [AppName, AppVersion]), mtInformation, [mbOK], 0);
end;

end.
