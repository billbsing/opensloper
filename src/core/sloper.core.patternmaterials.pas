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
// A pattern's materials: the list, their names, colours, fills and
// allowances, which material each piece is cut from and how it looks, and
// the cut list. The pattern owns one and reaches it through its own methods;
// it hands out IDs, lists the pieces and records refusals (TMaterialsHost).
// No LCL dependency.
unit Sloper.Core.PatternMaterials;

{$mode ObjFPC}{$H+}

interface

uses
  SysUtils, Sloper.Core.Materials, Sloper.Core.Piece;

type
  // What the materials need from the pattern that owns them
  TMaterialsHost = record
    // The next ID, which it then counts past
    NewId: function: string of object;
    // A loaded ID, which later IDs must be above
    KeepIdAbove: procedure(const Key: string) of object;
    // The pattern's pieces, in pattern order
    Pieces: function: TPieceObjectArray of object;
    // Records why a change was refused; always False
    Refuse: function(const Msg: string): boolean of object;
  end;

  // Changes return False when refused, with the reason given to the host
  TPatternMaterials = class
  private
    FItems: TPatternMaterialList;
    FHost: TMaterialsHost;
    function GetCount: integer;
    function GetItem(Index: integer): TPatternMaterial;
    function NameTaken(const AName: string; Exclude: TPatternMaterial = nil): boolean;
    function CheckName(const AName: string; Exclude: TPatternMaterial): boolean;
    function FreeColor: string;
  public
    constructor Create(const AHost: TMaterialsHost);
    destructor Destroy; override;
    // Back to the one implicit material, Main
    procedure Reset;
    // Gives the first material an ID and puts every piece on it, ready to be
    // written to the file
    procedure MakeExplicit;
    // An empty name or colour takes the next free one
    function Add(const AName: string = ''; const AColor: string = ''; AFill: TMaterialFill = ffTint): TPatternMaterial;
    function Rename(Material: TPatternMaterial; const NewName: string): boolean;
    function SetColor(Material: TPatternMaterial; const AColor: string): boolean;
    // Goes on a piece when it takes the material; it does not follow later
    // changes, so the piece can be set by hand
    function SetAllowance(Material: TPatternMaterial; HasAllowance: boolean; Allowance: double): boolean;
    procedure SetFill(Material: TPatternMaterial; AFill: TMaterialFill);
    // Refused for the last material and for one that pieces use
    function Delete(Material: TPatternMaterial): boolean;
    function Find(const Key: string): TPatternMaterial;
    function FindNamed(const AName: string): TPatternMaterial;
    // The piece's material, or nil when it has none
    function MaterialOf(Piece: TPieceObject): TPatternMaterial;
    // Puts the piece on Material, or on none for nil; the allowance is the
    // pattern's to set, as it is a formula
    procedure SetPieceMaterial(Piece: TPieceObject; Material: TPatternMaterial);
    // An empty colour and pfMaterial go back to the material's
    function SetPieceFill(Piece: TPieceObject; const AColor: string; Style: TPieceFillStyle): boolean;
    function PieceLook(Piece: TPieceObject): TPieceLook;
    // CutCaption, with the material's name once the pattern has named its
    // materials; Whole is for a piece opened out to cut flat
    function PieceCaption(Piece: TPieceObject; Whole: boolean = False): string;
    // "Main: Front ×1 on fold, Back ×2 · Lining: Front ×1 on fold"
    function CutList: string;
    function Names: string;
    // For loaders: replaces the first material, unless a material was inserted already
    procedure Insert(Material: TPatternMaterial);
    property Count: integer read GetCount;
    property Items[Index: integer]: TPatternMaterial read GetItem; default;
  end;

// The material's allowance as formula text, always with a decimal point
function MaterialAllowanceText(Material: TPatternMaterial): string;

resourcestring
  rsPatternMaterialTaken = 'There is already a material called %s';
  rsPatternMaterialBadColor = '%s is not a colour; use the form #5B8DB8';
  rsPatternLastMaterial = 'A pattern needs at least one material';
  rsPatternMaterialInUse = '%s cannot be deleted: %s is cut from it';
  rsPatternPieceCaptionMaterial = '%s, %s';
  rsPatternCutEntry = '%s ×%d';
  rsPatternCutEntryFold = '%s ×%d on fold';
  rsPatternCutEntryMirrored = '%s ×%d mirrored';
  rsPatternCutGroup = '%s: %s';
  rsPatternNoMaterial = 'No material';

implementation

uses
  Sloper.Core.Names;

const
  CUT_LIST_ENTRY_GAP = ', ';
  // Typed, so the middle dot stays a UTF-8 string
  CUT_LIST_GROUP_GAP: string = ' · ';

function MaterialAllowanceText(Material: TPatternMaterial): string;
var
  Formats: TFormatSettings;
begin
  Formats := DefaultFormatSettings;
  Formats.DecimalSeparator := '.';
  Result := FloatToStr(Material.Allowance, Formats);
end;

constructor TPatternMaterials.Create(const AHost: TMaterialsHost);
begin
  inherited Create;
  FHost := AHost;
  FItems := TPatternMaterialList.Create;
  Reset;
end;

destructor TPatternMaterials.Destroy;
begin
  FreeAndNil(FItems);
  inherited Destroy;
end;

procedure TPatternMaterials.Reset;
var
  Material: TPatternMaterial;
begin
  FItems.Clear;
  Material := TPatternMaterial.Create;
  FItems.Add(Material);
  Material.Name := DEFAULT_MATERIAL_NAME;
  Material.Color := MATERIAL_PALETTE[0];
end;

procedure TPatternMaterials.MakeExplicit;
var
  Piece: TPieceObject;
begin
  if FItems[0].Key <> '' then
    Exit;
  FItems[0].Key := FHost.NewId();
  for Piece in FHost.Pieces() do
    Piece.MaterialKey := FItems[0].Key;
end;

function TPatternMaterials.GetCount: integer;
begin
  Result := FItems.Count;
end;

function TPatternMaterials.GetItem(Index: integer): TPatternMaterial;
begin
  Result := FItems[Index];
end;

function TPatternMaterials.NameTaken(const AName: string; Exclude: TPatternMaterial): boolean;
var
  Material: TPatternMaterial;
begin
  Result := False;
  for Material in FItems do
    if (Material <> Exclude) and SameName(Material.Name, AName) then
      Exit(True);
end;

function TPatternMaterials.CheckName(const AName: string; Exclude: TPatternMaterial): boolean;
var
  Reason: string;
begin
  if not Sloper.Core.Names.CheckName(AName, Reason) then
    Exit(FHost.Refuse(Reason));
  if NameTaken(AName, Exclude) then
    Exit(FHost.Refuse(Format(rsPatternMaterialTaken, [AName])));
  Result := True;
end;

// The first colour of the palette no material has; they repeat once all are used
function TPatternMaterials.FreeColor: string;
var
  Material: TPatternMaterial;
  Taken: boolean;
begin
  for Result in MATERIAL_PALETTE do
  begin
    Taken := False;
    for Material in FItems do
      Taken := Taken or SameText(Material.Color, Result);
    if not Taken then
      Exit;
  end;
  Result := MATERIAL_PALETTE[FItems.Count mod Length(MATERIAL_PALETTE)];
end;

function TPatternMaterials.Add(const AName, AColor: string; AFill: TMaterialFill): TPatternMaterial;
var
  MaterialName, MaterialColor: string;
  Number: integer;
begin
  Result := nil;
  MaterialName := Trim(AName);
  if MaterialName = '' then
  begin
    Number := 1;
    MaterialName := NEW_MATERIAL_BASE_NAME;
    while NameTaken(MaterialName) do
    begin
      Inc(Number);
      MaterialName := NEW_MATERIAL_BASE_NAME + IntToStr(Number);
    end;
  end
  else if not CheckName(MaterialName, nil) then
    Exit;
  MaterialColor := AColor;
  if MaterialColor = '' then
    MaterialColor := FreeColor
  else if not IsMaterialColor(MaterialColor) then
  begin
    FHost.Refuse(Format(rsPatternMaterialBadColor, [MaterialColor]));
    Exit;
  end;
  MakeExplicit;
  Result := TPatternMaterial.Create;
  FItems.Add(Result);
  Result.Key := FHost.NewId();
  Result.Name := MaterialName;
  Result.Color := UpperCase(MaterialColor);
  Result.Fill := AFill;
end;

function TPatternMaterials.Rename(Material: TPatternMaterial; const NewName: string): boolean;
begin
  if not CheckName(Trim(NewName), Material) then
    Exit(False);
  MakeExplicit;
  Material.Name := Trim(NewName);
  Result := True;
end;

function TPatternMaterials.SetAllowance(Material: TPatternMaterial; HasAllowance: boolean; Allowance: double): boolean;
begin
  if HasAllowance and (Allowance < 0) then
    Exit(FHost.Refuse(rsPieceNegativeAllowance));
  MakeExplicit;
  Material.HasAllowance := HasAllowance;
  Material.Allowance := Allowance;
  Result := True;
end;

function TPatternMaterials.SetColor(Material: TPatternMaterial; const AColor: string): boolean;
begin
  if not IsMaterialColor(AColor) then
    Exit(FHost.Refuse(Format(rsPatternMaterialBadColor, [AColor])));
  MakeExplicit;
  Material.Color := UpperCase(AColor);
  Result := True;
end;

procedure TPatternMaterials.SetFill(Material: TPatternMaterial; AFill: TMaterialFill);
begin
  MakeExplicit;
  Material.Fill := AFill;
end;

function TPatternMaterials.Delete(Material: TPatternMaterial): boolean;
var
  Piece: TPieceObject;
begin
  if FItems.Count = 1 then
    Exit(FHost.Refuse(rsPatternLastMaterial));
  for Piece in FHost.Pieces() do
    if MaterialOf(Piece) = Material then
      Exit(FHost.Refuse(Format(rsPatternMaterialInUse, [Material.Name, Piece.DisplayName])));
  FItems.Remove(Material);
  Result := True;
end;

function TPatternMaterials.Find(const Key: string): TPatternMaterial;
begin
  for Result in FItems do
    if Result.Key = Key then
      Exit;
  Result := nil;
end;

function TPatternMaterials.FindNamed(const AName: string): TPatternMaterial;
begin
  for Result in FItems do
    if SameName(Result.Name, AName) then
      Exit;
  Result := nil;
end;

function TPatternMaterials.MaterialOf(Piece: TPieceObject): TPatternMaterial;
begin
  Result := Find(Piece.MaterialKey);
end;

procedure TPatternMaterials.SetPieceMaterial(Piece: TPieceObject; Material: TPatternMaterial);
begin
  // The first material has a key to tell it from none only once it is explicit
  if not Assigned(Material) then
    MakeExplicit;
  if Assigned(Material) then
    Piece.MaterialKey := Material.Key
  else
    Piece.MaterialKey := '';
end;

function TPatternMaterials.SetPieceFill(Piece: TPieceObject; const AColor: string; Style: TPieceFillStyle): boolean;
begin
  if (AColor <> '') and not IsMaterialColor(AColor) then
    Exit(FHost.Refuse(Format(rsPatternMaterialBadColor, [AColor])));
  Piece.FillColor := UpperCase(AColor);
  Piece.FillStyle := Style;
  Result := True;
end;

function TPatternMaterials.PieceLook(Piece: TPieceObject): TPieceLook;
var
  Material: TPatternMaterial;
begin
  Result := Default(TPieceLook);
  Material := MaterialOf(Piece);
  if not Assigned(Material) then
    Exit;
  Result.Filled := True;
  Result.HatchAngle := MaterialHatchAngle(FItems.IndexOf(Material));
  if Piece.FillColor <> '' then
    Result.Color := ParseMaterialColor(Piece.FillColor)
  else
    Result.Color := ParseMaterialColor(Material.Color);
  case Piece.FillStyle of
    pfMaterial: Result.Fill := Material.Fill;
    pfTint: Result.Fill := ffTint;
    pfHatch: Result.Fill := ffHatch;
  end;
end;

function TPatternMaterials.PieceCaption(Piece: TPieceObject; Whole: boolean): string;
var
  Material: TPatternMaterial;
begin
  Result := Piece.CutCaption(Whole);
  Material := MaterialOf(Piece);
  if Assigned(Material) and (Material.Key <> '') then
    Result := Format(rsPatternPieceCaptionMaterial, [Result, Material.Name]);
end;

function TPatternMaterials.CutList: string;
var
  Pieces: TPieceObjectArray;
  Index: integer;

  function Entry(Piece: TPieceObject): string;
  begin
    if Piece.OnFold then
      Result := Format(rsPatternCutEntryFold, [Piece.DisplayName, Piece.CutCount])
    else if Piece.Mirrored and (Piece.CutCount > 1) then
      Result := Format(rsPatternCutEntryMirrored, [Piece.DisplayName, Piece.CutCount])
    else
      Result := Format(rsPatternCutEntry, [Piece.DisplayName, Piece.CutCount]);
  end;

  procedure AddGroup(Material: TPatternMaterial; const Caption: string);
  var
    Entries: string;
    Piece: TPieceObject;
  begin
    Entries := '';
    for Piece in Pieces do
      if MaterialOf(Piece) = Material then
      begin
        if Entries <> '' then
          Entries := Entries + CUT_LIST_ENTRY_GAP;
        Entries := Entries + Entry(Piece);
      end;
    if Entries = '' then
      Exit;
    if Result <> '' then
      Result := Result + CUT_LIST_GROUP_GAP;
    Result := Result + Format(rsPatternCutGroup, [Caption, Entries]);
  end;

begin
  Result := '';
  Pieces := FHost.Pieces();
  for Index := 0 to FItems.Count - 1 do
    AddGroup(FItems[Index], FItems[Index].Name);
  AddGroup(nil, rsPatternNoMaterial);
end;

function TPatternMaterials.Names: string;
var
  Material: TPatternMaterial;
begin
  Result := '';
  for Material in FItems do
  begin
    if Result <> '' then
      Result := Result + ', ';
    Result := Result + Material.Name;
  end;
end;

procedure TPatternMaterials.Insert(Material: TPatternMaterial);
begin
  if FItems[0].Key = '' then
    FItems.Clear;
  FItems.Add(Material);
  FHost.KeepIdAbove(Material.Key);
end;

end.
