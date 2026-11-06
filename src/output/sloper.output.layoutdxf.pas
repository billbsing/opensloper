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
  Sloper.Core.MachineProfiles, Sloper.Core.OutputProfiles, Sloper.Core.TextFields, Sloper.Output.Layout;

const
  LayerCut = '1';
  LayerNotch = '4';
  LayerFold = '6';
  LayerGrain = '7';
  LayerInternal = '8';
  LayerHole = '13';
  LayerSeam = '14';
  // The default layer has to be in the table too
  DXFLayers: array[0..7] of string = ('0', LayerCut, LayerNotch, LayerFold, LayerGrain, LayerInternal, LayerHole, LayerSeam);

// The DXF, whatever problems the layout has; callers check first
function LayoutToDXF(Layout: TLayout): string;
// Every copy where it was placed, by the profile's line types, for a machine.
// Layout space with y up, from the bottom of the lowest piece.
function LayoutToMachineDXF(Layout: TLayout; const Profile: TMachineProfile): string;

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
  SysUtils, Classes, Math, Generics.Collections, Sloper.Core.Geometry, Sloper.Core.Drag, Sloper.Core.Draft, Sloper.Core.Piece,
  Sloper.Core.Fabrics, Sloper.Core.Pattern;

const
  NumberDecimals = 3;
  TextHeight = 2.5;
  TextSpacing = 1.5;
  ClosedPolyline = '1';
  ReferencedBlock = '64';
  // AutoCAD's colour for lines that show against the background
  DXFInk = 7;

type
  TKeySet = specialize THashSet<string>;

  TDXFLayer = record
    Name: string;
    Color: integer;
  end;

  TDXFLayerArray = array of TDXFLayer;

  TDXFWriter = class
  private
    FLines: TStringList;
    procedure Pair(Code: integer; const Value: string);
    procedure Number(Code: integer; Value: double);
    procedure Place(const Point: TVec2; Z: double = 0);
    procedure Tables(const Layers: TDXFLayerArray);
  public
    constructor Create;
    destructor Destroy; override;
    procedure StartFile(const Layers: TDXFLayerArray; const Current: string);
    procedure StartSection(const AName: string);
    procedure EndSection;
    procedure StartBlock(const AName: string);
    procedure EndBlock;
    procedure Insert(const AName: string);
    procedure ClosedPath(const Layer: string; const Points: TVec2Array);
    procedure Line(const Layer: string; const Stroke: TLine2);
    // A point on the cutting line, with the notch's length as z and its angle
    procedure Notch(const Cut: TVec2; NotchLength, Angle: double);
    procedure PointAt(const Layer: string; const At: TVec2);
    procedure Circle(const Layer: string; const Centre: TVec2; Radius: double);
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

procedure TDXFWriter.Place(const Point: TVec2; Z: double);
begin
  Number(10, Point.X);
  Number(20, Point.Y);
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

procedure TDXFWriter.Tables(const Layers: TDXFLayerArray);
var
  Layer: TDXFLayer;
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
  Pair(70, IntToStr(Length(Layers)));
  for Layer in Layers do
  begin
    Pair(0, 'LAYER');
    Pair(2, Layer.Name);
    Pair(70, '0');
    Pair(62, IntToStr(Layer.Color));
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

procedure TDXFWriter.StartFile(const Layers: TDXFLayerArray; const Current: string);
begin
  StartSection('HEADER');
  Pair(9, '$ACADVER');
  Pair(1, 'AC1009');
  Pair(9, '$CLAYER');
  Pair(8, Current);
  EndSection;
  Tables(Layers);
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
  Point: TVec2;
begin
  Pair(0, 'POLYLINE');
  Pair(8, Layer);
  Pair(66, '1');
  Place(Vec2(0, 0));
  Pair(70, ClosedPolyline);
  for Point in Points do
  begin
    Pair(0, 'VERTEX');
    Pair(8, Layer);
    Place(Point);
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

procedure TDXFWriter.Notch(const Cut: TVec2; NotchLength, Angle: double);
begin
  Pair(0, 'POINT');
  Pair(8, LayerNotch);
  Place(Cut, NotchLength);
  Number(50, Angle);
end;

procedure TDXFWriter.PointAt(const Layer: string; const At: TVec2);
begin
  Pair(0, 'POINT');
  Pair(8, Layer);
  Place(At);
end;

procedure TDXFWriter.Circle(const Layer: string; const Centre: TVec2; Radius: double);
begin
  Pair(0, 'CIRCLE');
  Pair(8, Layer);
  Place(Centre);
  Number(40, Radius);
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

// What the output profile includes, as PlaceShape does; the piece's name,
// size, quantity and material always go in, as DXF-AAMA asks for them
procedure WritePieceBlock(Writer: TDXFWriter; Pattern: TPattern; Piece: TPieceObject; const BlockName, SizeName: string;
  const Profile: TOutputProfile);
var
  At: TVec2;
  Mark: TNotchMark;
  Marking: TMarkingMark;
  Hole: TVec2;
  Stroke: TLine2;
  Index: integer;
  Fabric: TPatternFabric;

  procedure AddText(const AText: string);
  begin
    Writer.TextAt(LayerCut, At, AText);
    At.Y := At.Y - TextHeight - TextSpacing;
  end;

  // The model is y down and DXF y up
  function Up(const Point: TVec2): TVec2;
  begin
    Result := Vec2(Point.X, -Point.Y);
  end;

  function UpAll(const Points: TVec2Array): TVec2Array;
  var
    Each: integer;
  begin
    Result := nil;
    SetLength(Result, Length(Points));
    for Each := 0 to High(Points) do
      Result[Each] := Up(Points[Each]);
  end;

  function UpLine(const Stroke: TLine2): TLine2;
  begin
    Result := Line2(Up(Stroke.P1), Up(Stroke.P2));
  end;

begin
  Writer.StartBlock(BlockName);
  if Profile.Allowance = apNone then
    Writer.ClosedPath(LayerCut, UpAll(Piece.Outline))
  else
  begin
    Writer.ClosedPath(LayerCut, UpAll(Piece.CutLine));
    if pkSeamLine in Profile.PieceMarks then
      Writer.ClosedPath(LayerSeam, UpAll(Piece.Outline));
  end;
  if (Piece.GrainKind <> gkNone) and (pkGrainline in Profile.PieceMarks) then
    Writer.Line(LayerGrain, UpLine(Piece.Grainline));
  if Piece.OnFold and (pkFoldBracket in Profile.PieceMarks) then
    Writer.Line(LayerFold, UpLine(Piece.FoldLine));
  // An angle as seen on screen is already DXF's anticlockwise angle; cut on
  // the seam line, a notch starts there
  if pkNotches in Profile.PieceMarks then
    for Mark in Piece.NotchMarks do
      if Profile.Allowance = apNone then
        Writer.Notch(Up(Mark.Seam), Distance(Mark.Cut, Mark.Tip), Line2(Mark.Cut, Mark.Tip).Angle)
      else
        Writer.Notch(Up(Mark.Cut), Distance(Mark.Cut, Mark.Tip), Line2(Mark.Cut, Mark.Tip).Angle);
  for Marking in Piece.MarkingMarks do
  begin
    case Marking.Kind of
      mkLine:
        if not (Marking.Role in Profile.Roles) then
          Continue;
      mkPoint:
        if not (pkHoles in Profile.PieceMarks) then
          Continue;
      else
        if not (pkStitchHoles in Profile.PieceMarks) then
          Continue;
    end;
    for Index := 1 to High(Marking.Line) do
      Writer.Line(LayerInternal, UpLine(Line2(Marking.Line[Index - 1], Marking.Line[Index])));
    for Hole in Marking.Holes do
      Writer.PointAt(LayerHole, Up(Hole));
    for Hole in Marking.Centres do
      for Stroke in MarkerStrokes(Marking.Marker, Hole, Marking.HoleSize) do
        Writer.Line(LayerInternal, UpLine(Stroke));
  end;
  At := Up(Piece.Middle);
  AddText(Format(rsDXFPieceName, [Piece.DisplayName]));
  if SizeName <> '' then
    AddText(Format(rsDXFSize, [SizeName]));
  AddText(Format(rsDXFQuantity, [Piece.CutCount]));
  Fabric := Pattern.FabricOf(Piece);
  if Assigned(Fabric) and (Fabric.Key <> '') then
    AddText(Format(rsDXFMaterial, [Fabric.Name]));
  Writer.EndBlock;
end;

function AAMALayers: TDXFLayerArray;
var
  Index: integer;
begin
  Result := nil;
  SetLength(Result, Length(DXFLayers));
  for Index := 0 to High(DXFLayers) do
  begin
    Result[Index].Name := DXFLayers[Index];
    Result[Index].Color := DXFInk;
  end;
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
    Writer.StartFile(AAMALayers, LayerCut);
    Writer.StartSection('BLOCKS');
    for Placement in Layout.Placements do
    begin
      Key := IntToStr(Placement.SourceId) + ':' + Placement.PieceKey;
      if Seen.Contains(Key) or not Layout.FindPiece(Placement, Source, Piece) or not Piece.HasResult or not Layout.InFabric(Source, Piece) then
        Continue;
      Seen.Add(Key);
      SizeName := '';
      if Assigned(Source.Measurements) then
        SizeName := Source.Measurements.SizeName;
      BlockName := BlockNameFrom(Piece.DisplayName);
      if (Layout.Sources.Count > 1) and (SizeName <> '') then
        BlockName := BlockName + '_' + BlockNameFrom(SizeName);
      BlockName := FreeBlockName(BlockName, Names);
      WritePieceBlock(Writer, Source.Pattern, Piece, BlockName, SizeName, Layout.ActiveOutputProfile);
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

// The nearest of the seven plain DXF colours; black and white are both ink
function NearestDXFColor(const Color: string): integer;
const
  Plain: array[0..7, 0..3] of integer = ((255, 0, 0, 1), (255, 255, 0, 2), (0, 255, 0, 3), (0, 255, 255, 4), (0, 0, 255, 5),
    (255, 0, 255, 6), (0, 0, 0, DXFInk), (255, 255, 255, DXFInk));
var
  Red, Green, Blue, Index, Gap, Best: integer;
begin
  Red := StrToInt('$' + Copy(Color, 2, 2));
  Green := StrToInt('$' + Copy(Color, 4, 2));
  Blue := StrToInt('$' + Copy(Color, 6, 2));
  Result := DXFInk;
  Best := MaxInt;
  for Index := Low(Plain) to High(Plain) do
  begin
    Gap := Sqr(Red - Plain[Index, 0]) + Sqr(Green - Plain[Index, 1]) + Sqr(Blue - Plain[Index, 2]);
    if Gap < Best then
    begin
      Best := Gap;
      Result := Plain[Index, 3];
    end;
  end;
end;

// Layers in use, once each: two line types may share one
function MachineLayers(const Profile: TMachineProfile): TDXFLayerArray;
var
  Kind: TLineType;
  Seen: TKeySet;
  Layer: TDXFLayer;
begin
  Result := nil;
  Seen := TKeySet.Create;
  try
    Layer.Name := '0';
    Layer.Color := DXFInk;
    Seen.Add(Layer.Name);
    Insert(Layer, Result, 0);
    for Kind := Low(TLineType) to High(TLineType) do
    begin
      Layer.Name := BlockNameFrom(Profile.Lines[Kind].Layer);
      Layer.Color := NearestDXFColor(Profile.Lines[Kind].Color);
      if Profile.Lines[Kind].Enabled and not Seen.Contains(LowerCase(Layer.Name)) then
      begin
        Seen.Add(LowerCase(Layer.Name));
        Insert(Layer, Result, Length(Result));
      end;
    end;
  finally
    FreeAndNil(Seen);
  end;
end;

procedure WriteMachinePiece(Writer: TDXFWriter; const Shape: TPlacedPiece; const Profile: TMachineProfile; Top: double);

  function Up(const Point: TVec2): TVec2;
  begin
    Result := Vec2(Point.X, Top - Point.Y);
  end;

  function UpAll(const Points: TVec2Array): TVec2Array;
  var
    Index: integer;
  begin
    Result := nil;
    SetLength(Result, Length(Points));
    for Index := 0 to High(Points) do
      Result[Index] := Up(Points[Index]);
  end;

  procedure Strokes(const Layer: string; const Lines: TLine2Array);
  var
    Stroke: TLine2;
  begin
    for Stroke in Lines do
      Writer.Line(Layer, Line2(Up(Stroke.P1), Up(Stroke.P2)));
  end;

var
  Kind: TLineType;
  Layer: string;
  Hole: TPlacedHole;
begin
  for Kind in MachineOrder do
  begin
    if not Profile.Lines[Kind].Enabled then
      Continue;
    Layer := BlockNameFrom(Profile.Lines[Kind].Layer);
    case Kind of
      ltCut:
      begin
        Writer.ClosedPath(Layer, UpAll(Shape.CutLine));
        Strokes(Layer, Shape.SlitLines);
      end;
      ltScore: Strokes(Layer, Shape.ScoreLines);
      ltMark:
      begin
        if Length(Shape.SeamLine) > 0 then
          Writer.ClosedPath(Layer, UpAll(Shape.SeamLine));
        Strokes(Layer, Shape.MarkLines);
      end;
      ltEngrave:
        if Shape.ShowLabel then
          Writer.TextAt(Layer, Up(Shape.LabelAt), Shape.Caption);
      ltHole:
        for Hole in Shape.Holes do
          Writer.Circle(Layer, Up(Hole.Centre), Hole.Diameter / 2);
    end;
  end;
end;

function LayoutToMachineDXF(Layout: TLayout; const Profile: TMachineProfile): string;
var
  Writer: TDXFWriter;
  Shapes: TPlacedPieceArray;
  Shape: TPlacedPiece;
  Top: double;
begin
  Shapes := Layout.PlacedPieces;
  Top := 0;
  for Shape in Shapes do
    Top := Max(Top, Shape.Bounds.MaxY);
  Writer := TDXFWriter.Create;
  try
    Writer.StartFile(MachineLayers(Profile), '0');
    Writer.StartSection('ENTITIES');
    for Shape in Shapes do
      WriteMachinePiece(Writer, Shape, Profile, Top);
    Writer.EndSection;
    Result := Writer.Finish;
  finally
    FreeAndNil(Writer);
  end;
end;

end.
