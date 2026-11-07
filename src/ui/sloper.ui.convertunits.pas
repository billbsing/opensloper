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

// The Convert Pattern Units dialog: the unit to convert to, and a row for
// each number the formulas leave open, to mark as a length or a number.
// Each mark is worked through again, so numbers that follow from it fill in.
unit Sloper.UI.ConvertUnits;

{$mode ObjFPC}{$H+}

interface

uses
  Classes, Sloper.Core.Units, Sloper.Core.Pattern, Sloper.Core.UnitConvert;

// The unit chosen and every number with its role; False when cancelled
function ChooseUnitConversion(AOwner: TComponent; Pattern: TPattern; out ToUnits: TMeasureUnit; out Numbers: TUnitNumberArray): boolean;

resourcestring
  rsConvertTitle = 'Convert Pattern Units';
  rsConvertFrom = 'The pattern is in %s. Convert it to:';
  rsConvertIntro = 'Only lengths are rewritten; counts, ratios, angles and numbers written with a unit stay as they are.';
  rsConvertNothingOpen = 'Every number''s role is settled by where it is used.';
  rsConvertOpen = 'These numbers could be a length or a plain number. Choose for each:';
  rsConvertSkipped = 'Formulas with errors are left as they are: %d.';
  rsConvertRow = '%s, %s: %s';
  rsConvertChoose = 'Choose...';
  rsConvertLength = 'Length';
  rsConvertNumber = 'Number';
  rsConvertButton = 'Convert';
  rsConvertMillimetres = 'Millimetres (mm)';
  rsConvertCentimetres = 'Centimetres (cm)';
  rsConvertInches = 'Inches (in)';

implementation

uses
  SysUtils, Forms, Controls, StdCtrls, ExtCtrls, Graphics, ButtonPanel, Sloper.Core.Evaluator, Sloper.UI.ObjectList;

const
  DialogWidth = 640;
  DialogHeight = 480;
  DialogBorder = 8;
  ChoiceWidth = 120;
  // Marks the number in its formula
  NumberOpen = '«';
  NumberClose = '»';
  UnitCaptions: array[TMeasureUnit] of string = (rsConvertMillimetres, rsConvertCentimetres, rsConvertInches);

type
  TConvertDialog = class(TForm)
  private
    FPattern: TPattern;
    FUnitBox: TComboBox;
    FUnits: array of TMeasureUnit;
    FRows: TScrollBox;
    FButtons: TButtonPanel;
    // The numbers left open at first, each with its row's choice
    FOpen: TUnitNumberArray;
    FChoices: array of TComboBox;
    // Choices made by hand, which are marks; the others show what follows
    FByHand: array of boolean;
    FUpdating: boolean;
    FNumbers: TUnitNumberArray;
    procedure AddRow(const Number: TUnitNumber; Index: integer);
    procedure ChoiceChange(Sender: TObject);
    procedure Reanalyse;
  public
    constructor Create(AOwner: TComponent; APattern: TPattern); reintroduce;
    function ToUnits: TMeasureUnit;
    property Numbers: TUnitNumberArray read FNumbers;
  end;

var
  // Top-aligned controls are ordered by Top: each new one is given a larger
  // one than any before, so they go in the order made
  StackTop: integer = 100000;

procedure StackBelow(Control: TControl);
begin
  Inc(StackTop, 1000);
  Control.Top := StackTop;
  Control.Align := alTop;
end;

function AddLabel(AParent: TWinControl; const ACaption: string): TLabel;
begin
  Result := TLabel.Create(AParent);
  Result.Parent := AParent;
  StackBelow(Result);
  Result.WordWrap := True;
  Result.BorderSpacing.Around := DialogBorder;
  Result.Caption := ACaption;
end;

// The formula as shown, with the number marked
function RowCaption(Pattern: TPattern; const Number: TUnitNumber): string;
var
  Node: TEvalNode;
  Formula: string;
  At, Len: integer;
begin
  Node := Pattern.FindNode(Number.NodeKey);
  Formula := Node.Field(Number.FieldName).DisplayText(Pattern.Resolver);
  if Node.Field(Number.FieldName).DisplayTokenSpan(Pattern.Resolver, Number.Token, At, Len) then
  begin
    Insert(NumberClose, Formula, At + Len);
    Insert(NumberOpen, Formula, At);
  end;
  Result := Format(rsConvertRow, [Node.DisplayName, FieldCaption(Number.FieldName), Formula]);
end;

constructor TConvertDialog.Create(AOwner: TComponent; APattern: TPattern);
var
  Analysis: TUnitAnalysis;
  AUnit: TMeasureUnit;
  Index: integer;
begin
  inherited CreateNew(AOwner);
  FPattern := APattern;
  Caption := rsConvertTitle;
  Position := poOwnerFormCenter;
  BorderStyle := bsSizeable;
  Width := DialogWidth;
  Height := DialogHeight;
  FButtons := TButtonPanel.Create(Self);
  FButtons.Parent := Self;
  FButtons.ShowButtons := [pbOK, pbCancel];
  FButtons.OKButton.Caption := rsConvertButton;
  AddLabel(Self, Format(rsConvertFrom, [MeasureUnitNames[APattern.Units]]));
  FUnitBox := TComboBox.Create(Self);
  FUnitBox.Parent := Self;
  StackBelow(FUnitBox);
  FUnitBox.Style := csDropDownList;
  FUnitBox.BorderSpacing.Left := DialogBorder;
  FUnitBox.BorderSpacing.Right := DialogBorder;
  FUnits := nil;
  for AUnit := Low(TMeasureUnit) to High(TMeasureUnit) do
    if AUnit <> APattern.Units then
    begin
      FUnitBox.Items.Add(UnitCaptions[AUnit]);
      Insert(AUnit, FUnits, Length(FUnits));
    end;
  FUnitBox.ItemIndex := 0;
  AddLabel(Self, rsConvertIntro);
  Analysis := AnalyseUnits(APattern, nil);
  FNumbers := Analysis.Numbers;
  FOpen := nil;
  for Index := 0 to High(FNumbers) do
    if not FNumbers[Index].Decided then
      Insert(FNumbers[Index], FOpen, Length(FOpen));
  if Length(Analysis.Skipped) > 0 then
    AddLabel(Self, Format(rsConvertSkipped, [Length(Analysis.Skipped)]));
  if Length(FOpen) = 0 then
    AddLabel(Self, rsConvertNothingOpen)
  else
    AddLabel(Self, rsConvertOpen);
  FRows := TScrollBox.Create(Self);
  FRows.Parent := Self;
  FRows.Align := alClient;
  FRows.BorderSpacing.Around := DialogBorder;
  FRows.HorzScrollBar.Visible := False;
  FRows.Visible := Length(FOpen) > 0;
  FChoices := nil;
  SetLength(FChoices, Length(FOpen));
  FByHand := nil;
  SetLength(FByHand, Length(FOpen));
  for Index := 0 to High(FOpen) do
    AddRow(FOpen[Index], Index);
  Reanalyse;
end;

procedure TConvertDialog.AddRow(const Number: TUnitNumber; Index: integer);
var
  Row: TPanel;
  Description: TLabel;
begin
  Row := TPanel.Create(Self);
  Row.Parent := FRows;
  StackBelow(Row);
  Row.AutoSize := True;
  Row.BevelOuter := bvNone;
  FChoices[Index] := TComboBox.Create(Self);
  FChoices[Index].Parent := Row;
  FChoices[Index].Align := alRight;
  FChoices[Index].Width := ChoiceWidth;
  FChoices[Index].Style := csDropDownList;
  FChoices[Index].Items.Add(rsConvertChoose);
  FChoices[Index].Items.Add(rsConvertLength);
  FChoices[Index].Items.Add(rsConvertNumber);
  FChoices[Index].ItemIndex := 0;
  FChoices[Index].Tag := Index;
  FChoices[Index].OnChange := @ChoiceChange;
  Description := TLabel.Create(Self);
  Description.Parent := Row;
  Description.Align := alClient;
  Description.Layout := tlCenter;
  Description.BorderSpacing.Around := DialogBorder div 2;
  Description.Caption := RowCaption(FPattern, Number);
end;

procedure TConvertDialog.ChoiceChange(Sender: TObject);
begin
  if FUpdating then
    Exit;
  // Choose... again hands the row back to what follows from the others
  FByHand[TComboBox(Sender).Tag] := TComboBox(Sender).ItemIndex > 0;
  Reanalyse;
end;

// Works the roles out again from the marks, shows what follows from them in
// the rows not marked by hand, and lets Convert go once nothing is open
procedure TConvertDialog.Reanalyse;
var
  Marks: TUnitMarkArray;
  Index, Found: integer;
begin
  Marks := nil;
  for Index := 0 to High(FOpen) do
    if FByHand[Index] and (FChoices[Index].ItemIndex > 0) then
      Insert(MarkFor(FOpen[Index], FChoices[Index].ItemIndex = 1), Marks, Length(Marks));
  FNumbers := AnalyseUnits(FPattern, Marks).Numbers;
  FUpdating := True;
  for Index := 0 to High(FOpen) do
  begin
    if FByHand[Index] then
      Continue;
    for Found := 0 to High(FNumbers) do
      if (FNumbers[Found].NodeKey = FOpen[Index].NodeKey) and (FNumbers[Found].FieldName = FOpen[Index].FieldName) and
        (FNumbers[Found].Token = FOpen[Index].Token) then
      begin
        if not FNumbers[Found].Decided then
          FChoices[Index].ItemIndex := 0
        else if FNumbers[Found].Power = 1 then
          FChoices[Index].ItemIndex := 1
        else
          FChoices[Index].ItemIndex := 2;
      end;
  end;
  FUpdating := False;
  FButtons.OKButton.Enabled := UndecidedCount(FNumbers) = 0;
end;

function TConvertDialog.ToUnits: TMeasureUnit;
begin
  Result := FUnits[FUnitBox.ItemIndex];
end;

function ChooseUnitConversion(AOwner: TComponent; Pattern: TPattern; out ToUnits: TMeasureUnit; out Numbers: TUnitNumberArray): boolean;
var
  Dialog: TConvertDialog;
begin
  Dialog := TConvertDialog.Create(AOwner, Pattern);
  try
    Result := Dialog.ShowModal = mrOk;
    ToUnits := Dialog.ToUnits;
    Numbers := Dialog.Numbers;
  finally
    FreeAndNil(Dialog);
  end;
end;

end.
