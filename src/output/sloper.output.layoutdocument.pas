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
  Classes, SysUtils, Sloper.Output.Layout;

const
  // Changes with the same merge key this close together become one step
  LayoutMergeSeconds = 1.0;

type
  TLayoutDocument = class
  private
    FLayout: TLayout;
    FUndo, FRedo: array of string;
    FDescriptions, FRedoDescriptions: array of string;
    FSavedText: string;
    FChangeOpen: boolean;
    FBefore, FDescription: string;
    FLastKey: string;
    FLastTime: TDateTime;
    FOnChange: TNotifyEvent;
    function GetModified: boolean;
    function GetCanUndo: boolean;
    function GetCanRedo: boolean;
    function GetUndoDescription: string;
    procedure Restore(const Text: string);
    procedure Changed;
    procedure ClearHistory;
  public
    constructor Create;
    destructor Destroy; override;
    // Replaces the layout with one for this pattern, every piece placed
    procedure NewForPattern(const PatternFile: string);
    function Open(const FileName: string; out ErrorMessage: string): boolean;
    function Save(const FileName: string; out ErrorMessage: string): boolean;
    // Reads the pattern files again; not an undo step
    procedure Reload;
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

uses
  DateUtils;

constructor TLayoutDocument.Create;
begin
  FLayout := TLayout.Create;
  FSavedText := FLayout.SaveToText;
end;

destructor TLayoutDocument.Destroy;
begin
  FreeAndNil(FLayout);
  inherited Destroy;
end;

procedure TLayoutDocument.Changed;
begin
  if Assigned(FOnChange) then
    FOnChange(Self);
end;

procedure TLayoutDocument.ClearHistory;
begin
  FUndo := nil;
  FRedo := nil;
  FDescriptions := nil;
  FRedoDescriptions := nil;
  FLastKey := '';
end;

procedure TLayoutDocument.NewForPattern(const PatternFile: string);
begin
  FLayout.Clear;
  FLayout.FileName := ChangeFileExt(PatternFile, LayoutExtension);
  FLayout.Name := ChangeFileExt(ExtractFileName(PatternFile), '');
  FLayout.AddSource(ExtractFileName(PatternFile), '', '');
  FLayout.LoadSources;
  FLayout.PlaceNewPieces;
  ClearHistory;
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
  ClearHistory;
  FSavedText := FLayout.SaveToText;
  Changed;
end;

function TLayoutDocument.Save(const FileName: string; out ErrorMessage: string): boolean;
begin
  Result := FLayout.SaveToFile(FileName, ErrorMessage);
  if Result then
  begin
    FSavedText := FLayout.SaveToText;
    FLastKey := '';
    Changed;
  end;
end;

procedure TLayoutDocument.Reload;
begin
  FLayout.LoadSources;
  Changed;
end;

function TLayoutDocument.GetModified: boolean;
begin
  Result := FLayout.SaveToText <> FSavedText;
end;

function TLayoutDocument.GetCanUndo: boolean;
begin
  Result := Length(FUndo) > 0;
end;

function TLayoutDocument.GetCanRedo: boolean;
begin
  Result := Length(FRedo) > 0;
end;

function TLayoutDocument.GetUndoDescription: string;
begin
  Result := '';
  if CanUndo then
    Result := FDescriptions[High(FDescriptions)];
end;

procedure TLayoutDocument.BeginChange(const Description: string);
begin
  FBefore := FLayout.SaveToText;
  FDescription := Description;
  FChangeOpen := True;
end;

procedure TLayoutDocument.EndChange(const MergeKey: string);
var
  Merges: boolean;
begin
  if not FChangeOpen then
    Exit;
  FChangeOpen := False;
  if FLayout.SaveToText = FBefore then
    Exit;
  Merges := (MergeKey <> '') and (MergeKey = FLastKey) and CanUndo and (SecondSpan(Now, FLastTime) <= LayoutMergeSeconds);
  if not Merges then
  begin
    Insert(FBefore, FUndo, Length(FUndo));
    Insert(FDescription, FDescriptions, Length(FDescriptions));
  end;
  FRedo := nil;
  FRedoDescriptions := nil;
  FLastKey := MergeKey;
  FLastTime := Now;
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
  FLastKey := '';
  Changed;
end;

procedure TLayoutDocument.Undo;
var
  Last: integer;
  Text: string;
begin
  if not CanUndo then
    Exit;
  Last := High(FUndo);
  Text := FUndo[Last];
  Insert(FLayout.SaveToText, FRedo, Length(FRedo));
  Insert(FDescriptions[Last], FRedoDescriptions, Length(FRedoDescriptions));
  SetLength(FUndo, Last);
  SetLength(FDescriptions, Last);
  Restore(Text);
end;

procedure TLayoutDocument.Redo;
var
  Last: integer;
  Text: string;
begin
  if not CanRedo then
    Exit;
  Last := High(FRedo);
  Text := FRedo[Last];
  Insert(FLayout.SaveToText, FUndo, Length(FUndo));
  Insert(FRedoDescriptions[Last], FDescriptions, Length(FDescriptions));
  SetLength(FRedo, Last);
  SetLength(FRedoDescriptions, Last);
  Restore(Text);
end;

end.
