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

// JSON-RPC 2.0's error codes and its responses, one a line: what the
// Automation API, the automation socket and the apps' link all answer with.
// No LCL dependency.
unit Sloper.API.Rpc;

{$mode ObjFPC}{$H+}

interface

uses
  SysUtils, fpjson;

const
  // JSON-RPC 2.0's own codes
  RPC_PARSE_ERROR = -32700;
  RPC_INVALID_REQUEST = -32600;
  RPC_METHOD_NOT_FOUND = -32601;
  RPC_INVALID_PARAMS = -32602;
  RPC_INTERNAL_ERROR = -32603;
  // The call was understood and refused
  RPC_REFUSED = -32000;

// A JSON-RPC response on one line: the result, which it takes over, or an
// error with the field and position it names
function RpcResultResponse(Id, Output: TJSONData): string;
function RpcErrorResponse(Id: TJSONData; Code: integer; const AMessage: string; const FieldName: string = '';
  APosition: integer = 0): string;

implementation

function RpcResultResponse(Id, Output: TJSONData): string;
var
  Response: TJSONObject;
begin
  Response := TJSONObject.Create;
  try
    Response.Add('jsonrpc', '2.0');
    Response.Add('id', Id.Clone);
    Response.Add('result', Output);
    Result := Response.AsJSON;
  finally
    FreeAndNil(Response);
  end;
end;

function RpcErrorResponse(Id: TJSONData; Code: integer; const AMessage: string; const FieldName: string;
  APosition: integer): string;
var
  Response, Error, Data: TJSONObject;
begin
  Response := TJSONObject.Create;
  try
    Response.Add('jsonrpc', '2.0');
    if Assigned(Id) then
      Response.Add('id', Id.Clone)
    else
      Response.Add('id', TJSONNull.Create);
    Error := TJSONObject.Create;
    Response.Add('error', Error);
    Error.Add('code', Code);
    Error.Add('message', AMessage);
    if (FieldName <> '') or (APosition > 0) then
    begin
      Data := TJSONObject.Create;
      Error.Add('data', Data);
      Data.Add('field', FieldName);
      Data.Add('position', APosition);
    end;
    Result := Response.AsJSON;
  finally
    FreeAndNil(Response);
  end;
end;

end.
