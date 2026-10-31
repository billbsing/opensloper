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

// The Align tab: lines up or spaces out the selected points. Unlike moving
// them, this rewrites their definitions through Sloper.Core.Arrange, so the
// arrangement holds when measurements change.
unit Sloper.UI.AlignPanel;

{$mode ObjFPC}{$H+}

interface

uses
  Classes, SysUtils, Controls, StdCtrls, ExtCtrls, Dialogs, Sloper.Core.Arrange, Sloper.Document.PatternDocument;

type
  TAlignMessageEvent = procedure(Sender: TObject; const AText: string) of object;
  TAlignSelectEvent = procedure(Sender: TObject; const Key: string) of object;

  TAlignPanel = class(TPanel)
  private
    FDocument: TPatternDocument;
    FSelection: TStringArray;
    FRelativeBox: TComboBox;
    FAnchorLabel: TLabel;
    FAnchor: string;
    FOnMessage: TAlignMessageEvent;
    FOnSelect: TAlignSelectEvent;
    FNextTop: integer;
    procedure RepeatClick(Sender: TObject);
    procedure AddButton(const ACaption: string; AAction: TArrangeAction);
    procedure AddHeading(const ACaption: string);
    procedure Place(Control: TControl);
    procedure ActionClick(Sender: TObject);
    procedure AnchorClick(Sender: TObject);
    function BuildRequest(AAction: TArrangeAction): TArrangeRequest;
    procedure Run(AAction: TArrangeAction);
    function AskToReplace(const Items: TArrangeItemArray): TStringArray;
    procedure ShowResult(const Items: TArrangeItemArray; const Replace: TStringArray);
    procedure Say(const AText: string);
    procedure UpdateAnchorLabel;
  public
    constructor Create(AOwner: TComponent); override;
    property Document: TPatternDocument read FDocument write FDocument;
    // The selected objects, in the order they were picked
    property Selection: TStringArray read FSelection write FSelection;
    property OnMessage: TAlignMessageEvent read FOnMessage write FOnMessage;
    // A new repeat is selected, so that its count can be set
    property OnSelect: TAlignSelectEvent read FOnSelect write FOnSelect;
  end;

resourcestring
  rsAlignHeading = 'Align';
  rsAlignRelative = 'Relative to';
  rsAlignFirst = 'First selected';
  rsAlignLast = 'Last selected';
  rsAlignAnchor = 'Anchor point';
  rsAlignSetAnchor = 'Use selected as anchor';
  rsAlignAnchorName = 'Anchor: %s';
  rsAlignNoAnchor = 'Anchor: none';
  rsAlignChooseAnchor = 'Select one point to use as the anchor';
  rsAlignVertically = 'Align vertically (same x)';
  rsAlignHorizontally = 'Align horizontally (same y)';
  rsDistributeHeading = 'Distribute';
  rsDistributeEvenly = 'Evenly';
  rsDistributeHorizontally = 'Horizontally';
  rsDistributeVertically = 'Vertically';
  rsDistributeAlongEdge = 'Along edge';
  rsRepeatHeading = 'Repeat';
  rsRepeatAdd = 'Add repeat';
  rsRepeatChange = 'Add repeat';
  rsRepeatNeeds = 'Select two points, or one line or curve, to repeat along';
  rsAlignChange = 'Align points';
  rsDistributeChange = 'Distribute points';
  rsAlignAsk = '%s: %s. Replace it?';
  rsAlignDone = '%d changed';
  rsAlignLeft = ', %d left as they were';
  rsAlignKept = '%s: %s';

implementation

uses
  Sloper.Core.Draft, Sloper.Core.Pattern;

const
  DefaultRepeatCount = '3';
  RowGap = 6;
  HeadingGap = 14;
  ActionTags: array[TArrangeAction] of integer = (0, 1, 2, 3, 4, 5);

constructor TAlignPanel.Create(AOwner: TComponent);
var
  Anchor, RepeatButton: TButton;
begin
  inherited Create(AOwner);
  BevelOuter := bvNone;
  FNextTop := 1;
  AddHeading(rsAlignRelative);
  FRelativeBox := TComboBox.Create(Self);
  FRelativeBox.Style := csDropDownList;
  FRelativeBox.Items.Add(rsAlignFirst);
  FRelativeBox.Items.Add(rsAlignLast);
  FRelativeBox.Items.Add(rsAlignAnchor);
  FRelativeBox.ItemIndex := 0;
  Place(FRelativeBox);
  Anchor := TButton.Create(Self);
  Anchor.Caption := rsAlignSetAnchor;
  Anchor.OnClick := @AnchorClick;
  Place(Anchor);
  FAnchorLabel := TLabel.Create(Self);
  Place(FAnchorLabel);
  UpdateAnchorLabel;
  AddHeading(rsAlignHeading);
  AddButton(rsAlignVertically, aaAlignVertical);
  AddButton(rsAlignHorizontally, aaAlignHorizontal);
  AddHeading(rsDistributeHeading);
  AddButton(rsDistributeEvenly, aaDistribute);
  AddButton(rsDistributeHorizontally, aaDistributeHorizontal);
  AddButton(rsDistributeVertically, aaDistributeVertical);
  AddButton(rsDistributeAlongEdge, aaDistributeAlongEdge);
  AddHeading(rsRepeatHeading);
  RepeatButton := TButton.Create(Self);
  RepeatButton.Caption := rsRepeatAdd;
  RepeatButton.OnClick := @RepeatClick;
  Place(RepeatButton);
end;

procedure TAlignPanel.Place(Control: TControl);
begin
  Control.Parent := Self;
  Control.Align := alTop;
  Control.Top := FNextTop;
  Inc(FNextTop, 1000);
  Control.BorderSpacing.Left := RowGap;
  Control.BorderSpacing.Right := RowGap;
  Control.BorderSpacing.Top := RowGap div 2;
end;

procedure TAlignPanel.AddHeading(const ACaption: string);
var
  Heading: TLabel;
begin
  Heading := TLabel.Create(Self);
  Heading.Caption := ACaption;
  Place(Heading);
  Heading.BorderSpacing.Top := HeadingGap;
end;

procedure TAlignPanel.AddButton(const ACaption: string; AAction: TArrangeAction);
var
  Button: TButton;
begin
  Button := TButton.Create(Self);
  Button.Caption := ACaption;
  Button.Tag := ActionTags[AAction];
  Button.OnClick := @ActionClick;
  Place(Button);
end;

procedure TAlignPanel.UpdateAnchorLabel;
var
  Node: TObject;
begin
  Node := nil;
  if (FDocument <> nil) and (FAnchor <> '') then
    Node := FDocument.Pattern.FindNode(FAnchor);
  if Node is TPointObject then
    FAnchorLabel.Caption := Format(rsAlignAnchorName, [TPointObject(Node).DisplayName])
  else
    FAnchorLabel.Caption := rsAlignNoAnchor;
end;

procedure TAlignPanel.AnchorClick(Sender: TObject);
begin
  if (Length(FSelection) <> 1) or not (FDocument.Pattern.FindNode(FSelection[0]) is TPointObject) then
  begin
    Say(rsAlignChooseAnchor);
    Exit;
  end;
  FAnchor := FSelection[0];
  FRelativeBox.ItemIndex := 2;
  UpdateAnchorLabel;
end;

function TAlignPanel.BuildRequest(AAction: TArrangeAction): TArrangeRequest;
var
  Key: string;
  Node: TObject;
begin
  Result := Default(TArrangeRequest);
  Result.Action := AAction;
  for Key in FSelection do
  begin
    Node := FDocument.Pattern.FindNode(Key);
    if Node is TPointObject then
      Insert(Key, Result.Points, Length(Result.Points))
    else if (Node is TEdgeObject) and (Result.Edge = '') then
      Result.Edge := Key;
  end;
  case FRelativeBox.ItemIndex of
    0: if Result.Points <> nil then
        Result.Reference := Result.Points[0];
    1: if Result.Points <> nil then
        Result.Reference := Result.Points[High(Result.Points)];
    else
      Result.Reference := FAnchor;
  end;
end;

// Nothing driven by a formula is overwritten without a yes
function TAlignPanel.AskToReplace(const Items: TArrangeItemArray): TStringArray;
var
  Item: TArrangeItem;
begin
  Result := nil;
  for Item in Items do
    if (Item.Choice = acAsk) and (MessageDlg(Format(rsAlignAsk, [Item.Name, Item.Reason]), mtConfirmation, [mbYes, mbNo], 0) = mrYes) then
      Insert(Item.Key, Result, Length(Result));
end;

procedure TAlignPanel.ShowResult(const Items: TArrangeItemArray; const Replace: TStringArray);
var
  Item: TArrangeItem;
  ChangedCount, LeftCount: integer;
  Note: string;
begin
  ChangedCount := Length(Replace);
  LeftCount := 0;
  Note := '';
  for Item in Items do
    if Item.Choice = acChange then
      Inc(ChangedCount)
    else if Item.Choice = acKeep then
    begin
      Inc(LeftCount);
      Note := Format(rsAlignKept, [Item.Name, Item.Reason]);
    end;
  if (ChangedCount = 0) and (Note <> '') then
    Say(Note)
  else if LeftCount > 0 then
    Say(Format(rsAlignDone, [ChangedCount]) + Format(rsAlignLeft, [LeftCount]))
  else
    Say(Format(rsAlignDone, [ChangedCount]));
end;

procedure TAlignPanel.Run(AAction: TArrangeAction);
const
  Descriptions: array[boolean] of string = (rsDistributeChange, rsAlignChange);
var
  Request: TArrangeRequest;
  Items: TArrangeItemArray;
  Replace: TStringArray;
  Err: string;
begin
  if (FDocument = nil) or FDocument.ChangeOpen then
    Exit;
  Request := BuildRequest(AAction);
  if not PlanArrange(FDocument.Pattern, Request, Items, Err) then
  begin
    Say(Err);
    Exit;
  end;
  Replace := AskToReplace(Items);
  FDocument.BeginChange(Descriptions[AAction in [aaAlignVertical, aaAlignHorizontal]]);
  if FDocument.Commit(ApplyArrange(FDocument.Pattern, Request, Replace, Err)) or (Err = '') then
    ShowResult(Items, Replace)
  else
    Say(Err);
end;

// Between two selected points, or along a selected edge
procedure TAlignPanel.RepeatClick(Sender: TObject);
var
  Request: TArrangeRequest;
  Added: TRepeatObject;
  Pattern: TPattern;
  Err: string;
begin
  if (FDocument = nil) or FDocument.ChangeOpen then
    Exit;
  Request := BuildRequest(aaDistribute);
  if not ((Length(Request.Points) = 2) and (Request.Edge = '') or (Request.Points = nil) and (Request.Edge <> '')) then
  begin
    Say(rsRepeatNeeds);
    Exit;
  end;
  Pattern := FDocument.Pattern;
  FDocument.BeginChange(rsRepeatChange);
  if Request.Edge <> '' then
    Added := Pattern.AddRepeatOnEdge('', Request.Edge, DefaultRepeatCount, True)
  else
    Added := Pattern.AddRepeatBetween('', Pattern.UsePoint(Request.Points[0]), Pattern.UsePoint(Request.Points[1]), DefaultRepeatCount, True);
  Err := Pattern.LastError;
  if not FDocument.Commit(Added <> nil) then
  begin
    Say(Err);
    Exit;
  end;
  Added := TRepeatObject(Pattern.FindObject(Added.Name));
  if Assigned(FOnSelect) and (Added.Item(1) <> nil) then
    FOnSelect(Self, Added.Item(1).Key);
end;

procedure TAlignPanel.ActionClick(Sender: TObject);
begin
  Run(TArrangeAction(TButton(Sender).Tag));
end;

procedure TAlignPanel.Say(const AText: string);
begin
  if Assigned(FOnMessage) then
    FOnMessage(Self, AText);
end;

end.
