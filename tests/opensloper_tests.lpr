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

program opensloper_tests;

{$mode ObjFPC}{$H+}

uses
  Sloper.Core.CodePage,
  Classes,
  SysUtils,
  consoletestrunner,
  Sloper.Tests.Geometry,
  Sloper.Tests.Numeric,
  Sloper.Tests.Bezier,
  Sloper.Tests.Names,
  Sloper.Tests.Formula,
  Sloper.Tests.JSON,
  Sloper.Tests.Measurements,
  Sloper.Tests.Evaluator,
  Sloper.Tests.Variables,
  Sloper.Tests.Pattern,
  Sloper.Tests.Operations,
  Sloper.Tests.Edges,
  Sloper.Tests.PatternFile,
  Sloper.Tests.PatternCheck,
  Sloper.Tests.Regression,
  Sloper.Tests.Document,
  Sloper.Tests.Drag,
  Sloper.Tests.CanvasModel,
  Sloper.Tests.Snap,
  Sloper.Tests.GridColumns,
  Sloper.Tests.ObjectList,
  Sloper.Tests.Completion,
  Sloper.Tests.API,
  Sloper.Tests.DraftSVG,
  Sloper.Tests.Settings,
  Sloper.Tests.AppPaths,
  Sloper.Tests.Clipper,
  Sloper.Tests.Piece,
  Sloper.Tests.Seam,
  Sloper.Tests.Garment,
  Sloper.Tests.Layers,
  Sloper.Tests.Fabrics,
  Sloper.Tests.Circles,
  Sloper.Tests.Accessories,
  Sloper.Tests.Transform,
  Sloper.Tests.Layout,
  Sloper.Tests.LayoutExports,
  Sloper.Tests.MeasurementDocument,
  Sloper.Tests.Catalogue,
  Sloper.Tests.SeamlyFormat,
  Sloper.Tests.Arrange,
  Sloper.Tests.RepeatPoints;

var
  App: TTestRunner;

begin
  DefaultRunAllTests := True;
  DefaultFormat := fPlain;
  App := TTestRunner.Create(nil);
  try
    App.Initialize;
    App.Title := 'OpenSloper tests';
    App.Run;
  finally
    FreeAndNil(App);
  end;
end.
