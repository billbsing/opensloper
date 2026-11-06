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

// The About dialog the three apps share: the app's own logo, read from the
// icon built into the program, beside its name, version and licence.
unit Sloper.UI.About;

{$mode ObjFPC}{$H+}

interface

uses
  Classes;

// ATitle names the app, such as OpenSloper Publish; ASummary says in a line
// what it does
procedure ShowAboutDialog(AOwner: TComponent; const ATitle, ASummary: string);

resourcestring
  rsAboutTitle = 'About %s';
  rsAboutVersion = 'Version %s';
  rsAboutOK = 'OK';
  rsAboutLicence = 'This program is free software: you can redistribute it and/or modify ' +
    'it under the terms of the GNU General Public License as published by ' + 'the Free Software Foundation, either version 3 of the License, or ' +
    '(at your option) any later version.'#10#10 + 'This program comes with ABSOLUTELY NO WARRANTY.'#10#10 +
    'Icons from Tabler Icons (tabler.io), MIT licence.';

implementation

uses
  SysUtils, Types, Forms, Controls, Graphics, StdCtrls, ExtCtrls, Sloper.Core.Version;

const
  // At 96 dpi; scaled to the screen
  LogoSize = 128;
  TextWidth = 360;
  DialogBorder = 12;
  // Points
  TitleFontSize = 16;

function NewLabel(Dialog: TForm; const ACaption: string): TLabel;
begin
  Result := TLabel.Create(Dialog);
  Result.Parent := Dialog;
  Result.Caption := ACaption;
  Result.WordWrap := True;
  Result.AutoSize := True;
  Result.Constraints.MinWidth := Dialog.Scale96ToScreen(TextWidth);
  Result.Constraints.MaxWidth := Dialog.Scale96ToScreen(TextWidth);
end;

// Under AControl, or at the top beside the logo when AControl is nil
procedure PlaceBelow(ALabel: TLabel; Logo, AControl: TControl; Gap: integer);
begin
  ALabel.AnchorSide[akLeft].Control := Logo;
  ALabel.AnchorSide[akLeft].Side := asrRight;
  ALabel.BorderSpacing.Left := DialogBorder;
  ALabel.BorderSpacing.Right := DialogBorder;
  ALabel.Anchors := [akLeft, akTop];
  if Assigned(AControl) then
  begin
    ALabel.AnchorSide[akTop].Control := AControl;
    ALabel.AnchorSide[akTop].Side := asrBottom;
    ALabel.BorderSpacing.Top := Gap;
  end
  else
    ALabel.BorderSpacing.Top := DialogBorder;
end;

function NewLogo(Dialog: TForm): TImage;
var
  Size: integer;
begin
  Size := Dialog.Scale96ToScreen(LogoSize);
  Result := TImage.Create(Dialog);
  Result.Parent := Dialog;
  Result.SetBounds(0, 0, Size, Size);
  Result.Anchors := [akLeft, akTop];
  Result.BorderSpacing.Around := DialogBorder;
  Result.Stretch := True;
  Result.Proportional := True;
  Result.Center := True;
  // The icon holds several sizes; take the one nearest the logo's
  Result.Picture.Icon.Assign(Application.Icon);
  if Result.Picture.Icon.Count > 0 then
    Result.Picture.Icon.Current := Result.Picture.Icon.GetBestIndexForSize(Types.Size(Size, Size));
end;

procedure ShowAboutDialog(AOwner: TComponent; const ATitle, ASummary: string);
var
  Dialog: TForm;
  Logo: TImage;
  TitleLabel, VersionLabel, SummaryLabel, LicenceLabel: TLabel;
  OKButton: TButton;
begin
  Dialog := TForm.CreateNew(AOwner);
  try
    Dialog.Caption := Format(rsAboutTitle, [ATitle]);
    Dialog.Position := poOwnerFormCenter;
    Dialog.BorderStyle := bsDialog;
    Dialog.AutoSize := True;
    Logo := NewLogo(Dialog);
    TitleLabel := NewLabel(Dialog, ATitle);
    TitleLabel.Font.Style := [fsBold];
    TitleLabel.Font.Size := TitleFontSize;
    PlaceBelow(TitleLabel, Logo, nil, 0);
    VersionLabel := NewLabel(Dialog, Format(rsAboutVersion, [AppVersion]));
    PlaceBelow(VersionLabel, Logo, TitleLabel, 0);
    SummaryLabel := NewLabel(Dialog, ASummary);
    PlaceBelow(SummaryLabel, Logo, VersionLabel, DialogBorder);
    LicenceLabel := NewLabel(Dialog, rsAboutLicence);
    PlaceBelow(LicenceLabel, Logo, SummaryLabel, DialogBorder);
    OKButton := TButton.Create(Dialog);
    OKButton.Parent := Dialog;
    OKButton.Caption := rsAboutOK;
    OKButton.ModalResult := mrOk;
    OKButton.Default := True;
    OKButton.Cancel := True;
    OKButton.AutoSize := True;
    OKButton.Anchors := [akTop, akRight];
    OKButton.AnchorSide[akTop].Control := LicenceLabel;
    OKButton.AnchorSide[akTop].Side := asrBottom;
    OKButton.AnchorSide[akRight].Control := LicenceLabel;
    OKButton.AnchorSide[akRight].Side := asrRight;
    OKButton.BorderSpacing.Top := DialogBorder;
    OKButton.BorderSpacing.Bottom := DialogBorder;
    Dialog.ActiveControl := OKButton;
    Dialog.ShowModal;
  finally
    FreeAndNil(Dialog);
  end;
end;

end.
