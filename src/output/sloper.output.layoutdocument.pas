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

// The layout being edited in the publish app, with undo. A change records the
// layout's saved text before it, as TPatternDocument does, and undo loads it
// back, so the sources are read again and placements are held by index only
// between changes.
unit Sloper.Output.LayoutDocument;

{$mode ObjFPC}{$H+}

interface

uses
  Classes, SysUtils, Sloper.Core.TextHistory, Sloper.Output.Layout;

type
  TLayoutDocument = class
  private
    FLayout: TLayout;
    FHistory: TTextHistory;
    FSavedText: string;
    FChangeOpen: boolean;
    FBefore, FDescription: string;
    // The files' stamps last time CheckSources saw them differ
    FPendingStamps: string;
    FOnChange: TNotifyEvent;
    function GetModified: boolean;
    function GetCanUndo: boolean;
    function GetCanRedo: boolean;
    function GetUndoDescription: string;
    procedure Restore(const Text: string);
    procedure Changed;
  public
    constructor Create;
    destructor Destroy; override;
    // Replaces the layout with one for this pattern, every piece placed
    procedure NewForPattern(const PatternFile: string);
    function Open(const FileName: string; out ErrorMessage: string): boolean;
    function Save(const FileName: string; out ErrorMessage: string): boolean;
    // Reads the pattern files again; not an undo step
    procedure Reload;
    // Call regularly: reads the sources again once a saved file has stopped
    // changing, and returns the names of the patterns read, '' when none
    function CheckSources: string;
    procedure BeginChange(const Description: string);
    // A step that matches the last one's non-empty key, within a second, joins it
    procedure EndChange(const MergeKey: string = '');
    procedure CancelChange;
    // Redraws without recording anything, during a drag
    procedure LiveUpdate;
    procedure Undo;
    procedure Redo;
    property Layout: TLayout read FLayout;
    property Modified: boolean read GetModified;
    property CanUndo: boolean read GetCanUndo;
    property CanRedo: boolean read GetCanRedo;
    property UndoDescription: string read GetUndoDescription;
    property OnChange: TNotifyEvent read FOnChange write FOnChange;
  end;

implementation

constructor TLayoutDocument.Create;
begin
  FLayout := TLayout.Create;
  FHistory := TTextHistory.Create;
  FSavedText := FLayout.SaveToText;
end;

destructor TLayoutDocument.Destroy;
begin
  FreeAndNil(FHistory);
  FreeAndNil(FLayout);
  inherited Destroy;
end;

procedure TLayoutDocument.Changed;
begin
  if Assigned(FOnChange) then
    FOnChange(Self);
end;

procedure TLayoutDocument.NewForPattern(const PatternFile: string);
begin
  FLayout.Clear;
  FLayout.FileName := ChangeFileExt(PatternFile, LAYOUT_EXTENSION);
  FLayout.Name := ChangeFileExt(ExtractFileName(PatternFile), '');
  FLayout.AddSource(ExtractFileName(PatternFile), '', '');
  FLayout.LoadSources;
  FLayout.PlaceNewPieces;
  FLayout.UseDefaultTitle;
  FHistory.Clear;
  // Not saved yet, so closing it asks
  FSavedText := '';
  Changed;
end;

function TLayoutDocument.Open(const FileName: string; out ErrorMessage: string): boolean;
begin
  Result := FLayout.LoadFromFile(FileName, ErrorMessage);
  if not Result then
    Exit;
  FLayout.LoadSources;
  FHistory.Clear;
  FSavedText := FLayout.SaveToText;
  Changed;
end;

function TLayoutDocument.Save(const FileName: string; out ErrorMessage: string): boolean;
begin
  Result := FLayout.SaveToFile(FileName, ErrorMessage);
  if Result then
  begin
    FSavedText := FLayout.SaveToText;
    FHistory.EndMerging;
    Changed;
  end;
end;

procedure TLayoutDocument.Reload;
begin
  FLayout.LoadSources;
  Changed;
end;

// A file seen changing may still be being written, so it has to read the same
// on two checks running before it is loaded
function TLayoutDocument.CheckSources: string;
var
  Source: TLayoutSource;
  Stamps: string;
begin
  Result := '';
  Stamps := '';
  for Source in FLayout.Sources do
  begin
    Stamps := Stamps + Source.CurrentStamp + ';';
    if Source.CurrentStamp <> Source.LoadedStamp then
    begin
      if Result <> '' then
        Result := Result + ', ';
      Result := Result + ExtractFileName(Source.PatternPath);
    end;
  end;
  if Result = '' then
  begin
    FPendingStamps := '';
    Exit;
  end;
  if Stamps <> FPendingStamps then
  begin
    FPendingStamps := Stamps;
    Exit('');
  end;
  FPendingStamps := '';
  Reload;
end;

function TLayoutDocument.GetModified: boolean;
begin
  Result := FLayout.SaveToText <> FSavedText;
end;

function TLayoutDocument.GetCanUndo: boolean;
begin
  Result := FHistory.CanUndo;
end;

function TLayoutDocument.GetCanRedo: boolean;
begin
  Result := FHistory.CanRedo;
end;

function TLayoutDocument.GetUndoDescription: string;
begin
  Result := FHistory.UndoDescription;
end;

procedure TLayoutDocument.BeginChange(const Description: string);
begin
  FBefore := FLayout.SaveToText;
  FDescription := Description;
  FChangeOpen := True;
end;

procedure TLayoutDocument.EndChange(const MergeKey: string);
begin
  if not FChangeOpen then
    Exit;
  FChangeOpen := False;
  if FLayout.SaveToText = FBefore then
    Exit;
  FHistory.Add(FBefore, FDescription, MergeKey);
  Changed;
end;

procedure TLayoutDocument.CancelChange;
begin
  if not FChangeOpen then
    Exit;
  FChangeOpen := False;
  Restore(FBefore);
end;

procedure TLayoutDocument.LiveUpdate;
begin
  Changed;
end;

// Keeps the file name, which the text does not hold
procedure TLayoutDocument.Restore(const Text: string);
var
  Reason: string;
begin
  if FLayout.LoadFromText(Text, Reason) then
    FLayout.LoadSources;
  Changed;
end;

procedure TLayoutDocument.Undo;
begin
  if CanUndo then
    Restore(FHistory.Undo(FLayout.SaveToText));
end;

procedure TLayoutDocument.Redo;
begin
  if CanRedo then
    Restore(FHistory.Redo(FLayout.SaveToText));
end;

end.
