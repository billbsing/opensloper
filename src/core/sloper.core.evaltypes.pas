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

// Evaluation states shared by everything the evaluator computes.
// No LCL dependency.
unit Sloper.Core.EvalTypes;

{$mode ObjFPC}{$H+}

interface

type
  // esValid: computed fine. esDirty: waiting to be computed. esError: a
  // formula problem. esInvalid: geometry impossible. esBlocked: depends on
  // something that failed. Failing objects keep their last good value.
  TEvalState = (esValid, esDirty, esError, esInvalid, esBlocked);

implementation

end.
