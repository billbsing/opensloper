# Changelog

What changed in each version of OpenSloper. Changes are added under the
version being worked on, the `APP_VERSION` in
`src/core/sloper.core.version.pas`, and the release workflow puts that
version's section in the notes of its GitHub release. A version left without
notes here gets the list of its commits since the last release instead
(`opensloper-make.sh release`). Issue numbers (#3) link to GitHub.

The layout follows [Keep a Changelog](https://keepachangelog.com): Added,
Changed, Fixed and Removed under each version.

## 0.2.0

### Added

- The Garment tab in the side panel shows the pieces as sewn (#4): darts made
  seams are closed, pieces cut on the fold are opened, and each piece is shaded
  as if round a body, arranged as on the canvas. Hovering a piece shows it on
  the canvas and a click selects it there; a selected seam is marked on both
  its sides. It exports SVG and PNG, the Automation API's `render` draws it
  with `garment`, and Preferences set its light.
- Objects can be locked (#16) with Edit → Lock and Unlock, or Locked in the
  Properties tab. A locked object is drawn greyed and cannot be moved, edited
  or deleted, but it can still be selected and used, and its formulas still
  run. The lock is saved with the pattern and is one undo step; the
  Automation API has `set_locked`.
- Overlapping pieces can be hidden, isolated and stacked (#10), from the View
  menu. Hide Piece takes a piece off the canvas with what only it uses; Isolate
  Piece dims everything the piece does not use and puts it out of reach; Bring
  to Front and Send to Back change the drawing order. They are saved with the
  pattern, outside undo, and the Garment tab and Export Draft follow them;
  every piece still prints.
- Notes and sheet notes have a font, bold and italic (#7). The canvas draws
  the font, SVG names it, and PDF embeds it from its TrueType file, cut down to
  the letters used. A font that cannot be embedded prints in the default font,
  with a warning.

### Changed

- The development scripts are one, `opensloper-make.sh`, with the commands
  `test`, `build`, `check`, `format`, `docs`, `package` and `release` in place
  of `run-tests.sh`, `build.sh`, `check-standards.sh`, `format.sh`,
  `build-docs.sh`, `package.sh` and `release-notes.sh` (#22).

### Fixed

- Angles worked out from points (`AngleBetween`, `NormalizeAngle`) were only
  good to about seven figures, as Free Pascal's `FMod` took its
  single-precision form.
- PDF prints text outside Latin-1, such as Greek or Cyrillic, in sheet notes,
  piece labels and notes, in the bundled Noto Sans; it used to print `?`.

## 0.1.0

The first release, for trying out: features and file formats may still change.

### Added

- **opensloper-measurements**: one person's measurements or a size table, from
  a catalogue of measurements with body figures.
- **opensloper-design**: points, lines, curves, circles and rectangles placed by
  formulas, in mm, cm or inches; pieces with seam allowances, seams, notches,
  markings, grainlines and materials; transforms, notes and callouts; full undo.
- **opensloper-publish**: pieces laid out on tiled pages, a large sheet, a
  projector or a material width, printed at true size or exported as PDF, SVG
  or DXF.
- **opensloper-cli**: checks and exports patterns and layouts, and serves the
  Automation API, also as an MCP server, so scripts and Claude can draft.
- Ask Claude about the open pattern from the design window's side panel.
- A Zoom tool (Z) in the design window and Zoom Area in the publish window:
  drag a box to zoom to it (#3).
- Zoom In and Zoom Out in the publish window, and Ctrl++ for Zoom In in both;
  Ctrl+= still works (#3).
- Scroll bars on the publish preview (#6).
- Downloads for Linux (x86_64), macOS (Apple silicon) and Windows (x86_64).
