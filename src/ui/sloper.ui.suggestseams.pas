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

// The Suggest Seams dialog: a list of likely pairs for the user to tick.
unit Sloper.UI.SuggestSeams;

{$mode ObjFPC}{$H+}

interface

uses
  Classes, Forms, Controls, CheckLst, ButtonPanel, Sloper.Core.Pattern, Sloper.Core.SeamSuggest;

// The pairs ticked; nil when none were, or the dialog was cancelled
function ChooseSeams(AOwner: TComponent; Pattern: TPattern; const Suggestions: TSeamSuggestionArray): TSeamSuggestionArray;

resourcestring
  rsSuggestSeamsTitle = 'Suggest Seams';

implementation

uses
  SysUtils, Sloper.UI.ObjectList, Sloper.UI.Spacing;

const
  DialogWidth = 560;
  DialogHeight = 400;

function ChooseSeams(AOwner: TComponent; Pattern: TPattern; const Suggestions: TSeamSuggestionArray): TSeamSuggestionArray;
var
  Dialog: TForm;
  List: TCheckListBox;
  Buttons: TButtonPanel;
  Index: integer;
begin
  Result := nil;
  Dialog := TForm.CreateNew(AOwner);
  try
    Dialog.Caption := rsSuggestSeamsTitle;
    Dialog.Position := poOwnerFormCenter;
    Dialog.BorderStyle := bsSizeable;
    Dialog.Width := DialogWidth;
    Dialog.Height := DialogHeight;
    Buttons := TButtonPanel.Create(Dialog);
    Buttons.Parent := Dialog;
    Buttons.ShowButtons := [pbOK, pbCancel];
    SpaceButtons(Buttons);
    List := TCheckListBox.Create(Dialog);
    List.Parent := Dialog;
    List.Align := alClient;
    List.BorderSpacing.Around := ControlGap;
    for Index := 0 to High(Suggestions) do
      List.Items.Add(SuggestionCaption(Pattern, Suggestions[Index]));
    if Dialog.ShowModal <> mrOk then
      Exit;
    for Index := 0 to High(Suggestions) do
      if List.Checked[Index] then
        Insert(Suggestions[Index], Result, Length(Result));
  finally
    FreeAndNil(Dialog);
  end;
end;

end.
