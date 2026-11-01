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

// A layout's pieces as DXF-AAMA: ASCII DXF R12 with one block per piece, in the
// piece's own coordinates, for CAD and cutting systems, which arrange pieces
// themselves. Copies are not repeated; the block gives the quantity. Layer
// numbers follow Valentina's exporter; see the design document.
unit Sloper.Output.LayoutDXF;

{$mode ObjFPC}{$H+}

interface

uses
  Sloper.Output.Layout;

const
  LayerCut = '1';
  LayerNotch = '4';
  LayerFold = '6';
  LayerGrain = '7';
  LayerSeam = '14';
  // The default layer has to be in the table too
  DXFLayers: array[0..5] of string = ('0', LayerCut, LayerNotch, LayerFold, LayerGrain, LayerSeam);

// The DXF, whatever problems the layout has; callers check first
function LayoutToDXF(Layout: TLayout): string;

resourcestring
  // Not translated by the formats that read them, but kept with the other text
  rsDXFStyleName = 'Style Name: %s';
  rsDXFCreationDate = 'Creation Date: %s';
  rsDXFUnits = 'Units: METRIC';
  rsDXFPieceName = 'Piece Name: %s';
  rsDXFSize = 'Size: %s';
  rsDXFQuantity = 'Quantity: %d';
  rsDXFMaterial = 'Material: %s';

implementation

uses
  SysUtils, Classes, Math, Generics.Collections, Sloper.Core.Geometry, Sloper.Core.Drag, Sloper.Core.Piece, Sloper.Core.Fabrics, Sloper.Core.Pattern;

const
  NumberDecimals = 3;
  TextHeight = 2.5;
  TextSpacing = 1.5;
  ClosedPolyline = '1';
  ReferencedBlock = '64';

type
  TKeySet = specialize THashSet<string>;

  TDXFWriter = class
  private
    FLines: TStringList;
    procedure Pair(Code: integer; const Value: string);
    procedure Number(Code: integer; Value: double);
    procedure Place(const P: TVec2; Z: double = 0);
    procedure Tables;
  public
    constructor Create;
    destructor Destroy; override;
    procedure StartFile;
    procedure StartSection(const AName: string);
    procedure EndSection;
    procedure StartBlock(const AName: string);
    procedure EndBlock;
    procedure Insert(const AName: string);
    procedure ClosedPath(const Layer: string; const Points: TVec2Array);
    procedure Line(const Layer: string; const Stroke: TLine2);
    procedure Notch(const Mark: TNotchMark);
    procedure TextAt(const Layer: string; const At: TVec2; const AText: string);
    function Finish: string;
  end;

constructor TDXFWriter.Create;
begin
  inherited Create;
  FLines := TStringList.Create;
  FLines.LineBreak := #13#10;
end;

destructor TDXFWriter.Destroy;
begin
  FreeAndNil(FLines);
  inherited Destroy;
end;

procedure TDXFWriter.Pair(Code: integer; const Value: string);
begin
  FLines.Add(Format('%3d', [Code]));
  FLines.Add(Value);
end;

procedure TDXFWriter.Number(Code: integer; Value: double);
begin
  Pair(Code, RoundedText(Value, NumberDecimals));
end;

procedure TDXFWriter.Place(const P: TVec2; Z: double);
begin
  Number(10, P.X);
  Number(20, P.Y);
  Number(30, Z);
end;

procedure TDXFWriter.StartSection(const AName: string);
begin
  Pair(0, 'SECTION');
  Pair(2, AName);
end;

procedure TDXFWriter.EndSection;
begin
  Pair(0, 'ENDSEC');
end;

procedure TDXFWriter.Tables;
var
  Layer: string;
begin
  StartSection('TABLES');
  Pair(0, 'TABLE');
  Pair(2, 'LTYPE');
  Pair(70, '1');
  Pair(0, 'LTYPE');
  Pair(2, 'CONTINUOUS');
  Pair(70, '0');
  Pair(3, 'Solid line');
  Pair(72, '65');
  Pair(73, '0');
  Pair(40, '0');
  Pair(0, 'ENDTAB');
  Pair(0, 'TABLE');
  Pair(2, 'LAYER');
  Pair(70, IntToStr(Length(DXFLayers)));
  for Layer in DXFLayers do
  begin
    Pair(0, 'LAYER');
    Pair(2, Layer);
    Pair(70, '0');
    Pair(62, '7');
    Pair(6, 'CONTINUOUS');
  end;
  Pair(0, 'ENDTAB');
  Pair(0, 'TABLE');
  Pair(2, 'STYLE');
  Pair(70, '1');
  Pair(0, 'STYLE');
  Pair(2, 'STANDARD');
  Pair(70, '0');
  Pair(40, '0');
  Pair(41, '1');
  Pair(50, '0');
  Pair(71, '0');
  Number(42, TextHeight);
  Pair(3, 'txt');
  Pair(4, '');
  Pair(0, 'ENDTAB');
  EndSection;
end;

procedure TDXFWriter.StartFile;
begin
  StartSection('HEADER');
  Pair(9, '$ACADVER');
  Pair(1, 'AC1009');
  Pair(9, '$CLAYER');
  Pair(8, LayerCut);
  EndSection;
  Tables;
end;

procedure TDXFWriter.StartBlock(const AName: string);
begin
  Pair(0, 'BLOCK');
  Pair(8, LayerCut);
  Pair(2, AName);
  Pair(70, ReferencedBlock);
  Place(Vec2(0, 0));
  Pair(3, AName);
end;

procedure TDXFWriter.EndBlock;
begin
  Pair(0, 'ENDBLK');
  Pair(8, LayerCut);
end;

procedure TDXFWriter.Insert(const AName: string);
begin
  Pair(0, 'INSERT');
  Pair(8, LayerCut);
  Pair(2, AName);
  Place(Vec2(0, 0));
end;

procedure TDXFWriter.ClosedPath(const Layer: string; const Points: TVec2Array);
var
  P: TVec2;
begin
  Pair(0, 'POLYLINE');
  Pair(8, Layer);
  Pair(66, '1');
  Place(Vec2(0, 0));
  Pair(70, ClosedPolyline);
  for P in Points do
  begin
    Pair(0, 'VERTEX');
    Pair(8, Layer);
    Place(P);
  end;
  Pair(0, 'SEQEND');
  Pair(8, Layer);
end;

procedure TDXFWriter.Line(const Layer: string; const Stroke: TLine2);
begin
  Pair(0, 'LINE');
  Pair(8, Layer);
  Place(Stroke.P1);
  Number(11, Stroke.P2.X);
  Number(21, Stroke.P2.Y);
  Number(31, 0);
end;

// A point on the cutting line, with the notch's length as z and its direction
procedure TDXFWriter.Notch(const Mark: TNotchMark);
begin
  Pair(0, 'POINT');
  Pair(8, LayerNotch);
  Place(Mark.Cut, Distance(Mark.Cut, Mark.Tip));
  Number(50, Line2(Mark.Cut, Mark.Tip).Angle);
end;

procedure TDXFWriter.TextAt(const Layer: string; const At: TVec2; const AText: string);
begin
  Pair(0, 'TEXT');
  Pair(8, Layer);
  Place(At);
  Number(40, TextHeight);
  Pair(1, AText);
end;

function TDXFWriter.Finish: string;
begin
  Pair(0, 'EOF');
  Result := FLines.Text;
end;

// Block names keep to letters, digits and underscores, as old readers expect
function BlockNameFrom(const Text: string): string;
var
  Index: integer;
begin
  Result := Text;
  for Index := 1 to Length(Result) do
    if not (Result[Index] in ['A'..'Z', 'a'..'z', '0'..'9', '_', '-']) then
      Result[Index] := '_';
end;

function FreeBlockName(const Wanted: string; Names: TKeySet): string;
var
  Number: integer;
begin
  Result := Wanted;
  Number := 1;
  while Names.Contains(LowerCase(Result)) do
  begin
    Inc(Number);
    Result := Wanted + IntToStr(Number);
  end;
  Names.Add(LowerCase(Result));
end;

procedure WriteStyleText(Writer: TDXFWriter; Layout: TLayout);
var
  Values: TFieldValues;
  At: TVec2;

  procedure AddLine(const AText: string);
  begin
    Writer.TextAt(LayerCut, At, AText);
    At.Y := At.Y - TextHeight - TextSpacing;
  end;

begin
  Values := Layout.FieldValues('', '');
  At := Vec2(0, -TextHeight);
  AddLine(Format(rsDXFStyleName, [Values.PatternName]));
  AddLine(Format(rsDXFCreationDate, [Values.Date]));
  AddLine(rsDXFUnits);
end;

procedure WritePieceBlock(Writer: TDXFWriter; Pattern: TPattern; Piece: TPieceObject; const BlockName, SizeName: string);
var
  At: TVec2;
  Mark: TNotchMark;
  Fabric: TPatternFabric;

  procedure AddText(const AText: string);
  begin
    Writer.TextAt(LayerCut, At, AText);
    At.Y := At.Y - TextHeight - TextSpacing;
  end;

begin
  Writer.StartBlock(BlockName);
  Writer.ClosedPath(LayerCut, Piece.CutLine);
  Writer.ClosedPath(LayerSeam, Piece.Outline);
  if Piece.GrainKind <> gkNone then
    Writer.Line(LayerGrain, Piece.Grainline);
  if Piece.OnFold then
    Writer.Line(LayerFold, Piece.FoldLine);
  for Mark in Piece.NotchMarks do
    Writer.Notch(Mark);
  At := Piece.Middle;
  AddText(Format(rsDXFPieceName, [Piece.DisplayName]));
  if SizeName <> '' then
    AddText(Format(rsDXFSize, [SizeName]));
  AddText(Format(rsDXFQuantity, [Piece.CutCount]));
  Fabric := Pattern.FabricOf(Piece);
  if (Fabric <> nil) and (Fabric.Key <> '') then
    AddText(Format(rsDXFMaterial, [Fabric.Name]));
  Writer.EndBlock;
end;

function LayoutToDXF(Layout: TLayout): string;
var
  Writer: TDXFWriter;
  Seen, Names: TKeySet;
  Blocks: TStringArray;
  BlockName, SizeName, Key: string;
  Placement: TPlacement;
  Source: TLayoutSource;
  Piece: TPieceObject;
begin
  Blocks := nil;
  Names := nil;
  Seen := nil;
  Writer := TDXFWriter.Create;
  try
    Seen := TKeySet.Create;
    Names := TKeySet.Create;
    Writer.StartFile;
    Writer.StartSection('BLOCKS');
    for Placement in Layout.Placements do
    begin
      Key := IntToStr(Placement.SourceId) + ':' + Placement.PieceKey;
      if Seen.Contains(Key) or not Layout.FindPiece(Placement, Source, Piece) or not Piece.HasResult then
        Continue;
      Seen.Add(Key);
      SizeName := '';
      if Source.Measurements <> nil then
        SizeName := Source.Measurements.SizeName;
      BlockName := BlockNameFrom(Piece.DisplayName);
      if (Layout.Sources.Count > 1) and (SizeName <> '') then
        BlockName := BlockName + '_' + BlockNameFrom(SizeName);
      BlockName := FreeBlockName(BlockName, Names);
      WritePieceBlock(Writer, Source.Pattern, Piece, BlockName, SizeName);
      System.Insert(BlockName, Blocks, Length(Blocks));
    end;
    Writer.EndSection;
    Writer.StartSection('ENTITIES');
    WriteStyleText(Writer, Layout);
    for BlockName in Blocks do
      Writer.Insert(BlockName);
    Writer.EndSection;
    Result := Writer.Finish;
  finally
    FreeAndNil(Names);
    FreeAndNil(Seen);
    FreeAndNil(Writer);
  end;
end;

end.
