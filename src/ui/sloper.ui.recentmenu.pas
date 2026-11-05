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

// File → Open Recent, shared by the three apps: fills a submenu from one of
// the lists in Sloper.Core.RecentFiles and hands a chosen file to the app.
unit Sloper.UI.RecentMenu;

{$mode ObjFPC}{$H+}

interface

uses
  Classes, SysUtils, Menus, Sloper.Core.RecentFiles;

type
  TRecentOpenEvent = procedure(Sender: TObject; const FileName: string) of object;

  TRecentMenu = class(TComponent)
  private
    FItem: TMenuItem;
    FList: TRecentList;
    FOnOpen: TRecentOpenEvent;
    FFiles: TStringArray;
    procedure FileClick(Sender: TObject);
    procedure ClearClick(Sender: TObject);
    function CaptionFor(Index: integer): string;
    // The clicked item may be the one Refresh would free, so wait until its click is over
    procedure QueueRefresh;
    procedure QueuedRefresh(Data: PtrInt);
  public
    // Adds Open Recent to Parent just after After (at the end when nil)
    constructor Create(AOwner: TComponent; Parent, After: TMenuItem; AList: TRecentList; AOnOpen: TRecentOpenEvent); reintroduce;
    destructor Destroy; override;
    // Re-reads the list, which another window of the same app may have changed
    procedure Refresh;
    // After a file is opened or saved
    procedure Remember(const FileName: string);
    property Item: TMenuItem read FItem;
  end;

resourcestring
  rsRecentMenu = 'Open &Recent';
  rsRecentClear = '&Clear Recent';
  rsRecentMissing = '%s'#10'can no longer be found, so it has been taken off the list.';
  rsRecentEntry = '&%d  %s';
  rsRecentEntryTenth = '1&0  %s';
  rsRecentEntryLater = '%d  %s';
  rsRecentInFolder = '%s  (%s)';

implementation

uses
  Dialogs, Forms, Sloper.Core.AppPaths;

constructor TRecentMenu.Create(AOwner: TComponent; Parent, After: TMenuItem; AList: TRecentList; AOnOpen: TRecentOpenEvent);
var
  Position: integer;
begin
  inherited Create(AOwner);
  FList := AList;
  FOnOpen := AOnOpen;
  FItem := TMenuItem.Create(Parent);
  FItem.Caption := rsRecentMenu;
  if Assigned(After) then
    Position := Parent.IndexOf(After) + 1
  else
    Position := Parent.Count;
  Parent.Insert(Position, FItem);
  Refresh;
end;

destructor TRecentMenu.Destroy;
begin
  Application.RemoveAsyncCalls(Self);
  inherited Destroy;
end;

procedure TRecentMenu.QueueRefresh;
begin
  Application.RemoveAsyncCalls(Self);
  Application.QueueAsyncCall(@QueuedRefresh, 0);
end;

procedure TRecentMenu.QueuedRefresh(Data: PtrInt);
begin
  Refresh;
end;

// The file name alone, unless another entry has the same one
function TRecentMenu.CaptionFor(Index: integer): string;
var
  Other: integer;
  ShownName: string;
begin
  ShownName := ExtractFileName(FFiles[Index]);
  for Other := 0 to High(FFiles) do
    if (Other <> Index) and SameFileName(ExtractFileName(FFiles[Other]), ShownName) then
    begin
      ShownName := Format(rsRecentInFolder, [ShownName, ExtractFileDir(FFiles[Index])]);
      Break;
    end;
  // Ampersands in a name would otherwise become accelerators
  ShownName := StringReplace(ShownName, '&', '&&', [rfReplaceAll]);
  if Index < 9 then
    Result := Format(rsRecentEntry, [Index + 1, ShownName])
  else if Index = 9 then
    Result := Format(rsRecentEntryTenth, [ShownName])
  else
    Result := Format(rsRecentEntryLater, [Index + 1, ShownName]);
end;

procedure TRecentMenu.Refresh;
var
  Index: integer;
  Entry: TMenuItem;
begin
  FItem.Clear;
  FFiles := ReadRecentFiles(TAppPaths.RecentFilesFile, FList);
  for Index := 0 to High(FFiles) do
  begin
    Entry := TMenuItem.Create(FItem);
    Entry.Caption := CaptionFor(Index);
    Entry.Hint := FFiles[Index];
    Entry.Tag := Index;
    Entry.OnClick := @FileClick;
    FItem.Add(Entry);
  end;
  if Length(FFiles) > 0 then
  begin
    FItem.AddSeparator;
    Entry := TMenuItem.Create(FItem);
    Entry.Caption := rsRecentClear;
    Entry.OnClick := @ClearClick;
    FItem.Add(Entry);
  end;
  FItem.Enabled := Length(FFiles) > 0;
end;

procedure TRecentMenu.Remember(const FileName: string);
begin
  RememberRecentFile(TAppPaths.RecentFilesFile, FList, FileName);
  QueueRefresh;
end;

procedure TRecentMenu.FileClick(Sender: TObject);
var
  FileName: string;
begin
  FileName := FFiles[TMenuItem(Sender).Tag];
  if not FileExists(FileName) then
  begin
    MessageDlg(Format(rsRecentMissing, [FileName]), mtWarning, [mbOK], 0);
    ForgetRecentFile(TAppPaths.RecentFilesFile, FList, FileName);
    QueueRefresh;
    Exit;
  end;
  if Assigned(FOnOpen) then
    FOnOpen(Self, FileName);
end;

procedure TRecentMenu.ClearClick(Sender: TObject);
begin
  ClearRecentFiles(TAppPaths.RecentFilesFile, FList);
  QueueRefresh;
end;

end.
