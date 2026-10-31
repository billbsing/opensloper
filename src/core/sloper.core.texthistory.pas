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

// An undo history of saved text, for documents that restore themselves from
// their own file text. No LCL dependency.
unit Sloper.Core.TextHistory;

{$mode ObjFPC}{$H+}

interface

const
  // Steps with the same merge key this close together become one
  HistoryMergeSeconds = 1.0;

type
  TTextHistory = class
  private
    FUndo, FRedo, FDescriptions, FRedoDescriptions: array of string;
    FLastKey: string;
    FLastTime: TDateTime;
    function GetCanUndo: boolean;
    function GetCanRedo: boolean;
    function GetUndoDescription: string;
  public
    procedure Clear;
    // Stops the next step joining the last
    procedure EndMerging;
    // Before is the text ahead of a change. A step that matches the last one's
    // non-empty key, within HistoryMergeSeconds, joins it.
    procedure Add(const Before, Description, MergeKey: string);
    // Current is the text now. Returns the text to go back or forward to.
    function Undo(const Current: string): string;
    function Redo(const Current: string): string;
    property CanUndo: boolean read GetCanUndo;
    property CanRedo: boolean read GetCanRedo;
    property UndoDescription: string read GetUndoDescription;
  end;

implementation

uses
  SysUtils, DateUtils;

procedure TTextHistory.Clear;
begin
  FUndo := nil;
  FRedo := nil;
  FDescriptions := nil;
  FRedoDescriptions := nil;
  FLastKey := '';
end;

procedure TTextHistory.EndMerging;
begin
  FLastKey := '';
end;

function TTextHistory.GetCanUndo: boolean;
begin
  Result := Length(FUndo) > 0;
end;

function TTextHistory.GetCanRedo: boolean;
begin
  Result := Length(FRedo) > 0;
end;

function TTextHistory.GetUndoDescription: string;
begin
  Result := '';
  if CanUndo then
    Result := FDescriptions[High(FDescriptions)];
end;

procedure TTextHistory.Add(const Before, Description, MergeKey: string);
var
  Merges: boolean;
begin
  Merges := (MergeKey <> '') and (MergeKey = FLastKey) and CanUndo and (SecondSpan(Now, FLastTime) <= HistoryMergeSeconds);
  if not Merges then
  begin
    Insert(Before, FUndo, Length(FUndo));
    Insert(Description, FDescriptions, Length(FDescriptions));
  end;
  FRedo := nil;
  FRedoDescriptions := nil;
  FLastKey := MergeKey;
  FLastTime := Now;
end;

function TTextHistory.Undo(const Current: string): string;
var
  Last: integer;
begin
  Last := High(FUndo);
  Result := FUndo[Last];
  Insert(Current, FRedo, Length(FRedo));
  Insert(FDescriptions[Last], FRedoDescriptions, Length(FRedoDescriptions));
  SetLength(FUndo, Last);
  SetLength(FDescriptions, Last);
  FLastKey := '';
end;

function TTextHistory.Redo(const Current: string): string;
var
  Last: integer;
begin
  Last := High(FRedo);
  Result := FRedo[Last];
  Insert(Current, FUndo, Length(FUndo));
  Insert(FRedoDescriptions[Last], FDescriptions, Length(FDescriptions));
  SetLength(FRedo, Last);
  SetLength(FRedoDescriptions, Last);
  FLastKey := '';
end;

end.
