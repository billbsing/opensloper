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

// The drafts of a pattern and the layers of each draft. Names, order and
// membership are part of the pattern; Hidden, Locked, the active layer and the
// zoom are view state, saved but outside undo. A pattern starts with one draft
// and one layer that have no IDs and are not written to the file, until the
// user changes them. No LCL dependency.
unit Sloper.Core.Drafts;

{$mode ObjFPC}{$H+}

interface

uses
  SysUtils, Generics.Collections;

const
  DefaultDraftName = 'Draft';
  DefaultLayerName = 'Draft';

type
  TPatternLayer = class
  public
    Key, Name: string;
    Hidden, Locked: boolean;
  end;

  TPatternLayerList = specialize TObjectList<TPatternLayer>;
  TPatternLayerArray = array of TPatternLayer;

  // Layers run from the bottom, drawn first, to the top
  TPatternDraft = class
  private
    FLayers: TPatternLayerList;
  public
    Key, Name: string;
    ActiveLayer: TPatternLayer;
    // Set once the canvas has shown this draft
    HasView: boolean;
    Zoom, CentreX, CentreY: double;
    constructor Create(const AKey, AName: string);
    destructor Destroy; override;
    function AddLayer(const AKey, AName: string): TPatternLayer;
    function FindLayer(const AKey: string): TPatternLayer;
    function IndexOfLayer(Layer: TPatternLayer): integer;
    property Layers: TPatternLayerList read FLayers;
  end;

  TPatternDraftList = specialize TObjectList<TPatternDraft>;

implementation

constructor TPatternDraft.Create(const AKey, AName: string);
begin
  inherited Create;
  Key := AKey;
  Name := AName;
  FLayers := TPatternLayerList.Create;
end;

destructor TPatternDraft.Destroy;
begin
  FreeAndNil(FLayers);
  inherited Destroy;
end;

function TPatternDraft.AddLayer(const AKey, AName: string): TPatternLayer;
begin
  Result := TPatternLayer.Create;
  Result.Key := AKey;
  Result.Name := AName;
  FLayers.Add(Result);
  if ActiveLayer = nil then
    ActiveLayer := Result;
end;

function TPatternDraft.FindLayer(const AKey: string): TPatternLayer;
begin
  for Result in FLayers do
    if Result.Key = AKey then
      Exit;
  Result := nil;
end;

function TPatternDraft.IndexOfLayer(Layer: TPatternLayer): integer;
begin
  Result := FLayers.IndexOf(Layer);
end;

end.
