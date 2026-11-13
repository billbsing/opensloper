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

// The question the three apps ask before unsaved changes would be lost, on
// closing, opening or starting a new file, so it reads the same in each.
unit Sloper.UI.SavePrompt;

{$mode ObjFPC}{$H+}

interface

uses
  Classes, SysUtils, Forms, Dialogs;

resourcestring
  rsSaveChanges = 'Save the changes to %s?';
  rsUntitled = 'Untitled';

// Yes, No or Cancel: mrYes to save first, mrNo to discard, anything else to
// stay. DocName is the file shown; an empty name is shown as Untitled.
function AskSaveChanges(const DocName: string): TModalResult;

implementation

function AskSaveChanges(const DocName: string): TModalResult;
var
  Shown: string;
begin
  Shown := DocName;
  if Shown = '' then
    Shown := rsUntitled;
  Result := MessageDlg(Format(rsSaveChanges, [Shown]), mtConfirmation, [mbYes, mbNo, mbCancel], 0);
end;

end.
