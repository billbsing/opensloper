# Changelog

What changed in each version of OpenSloper. Each change adds its line under
the version being worked on, the `APP_VERSION` in
`src/core/sloper.core.version.pas`; the release workflow puts that version's
section in the notes of its GitHub release and will not publish a version
whose section is missing or empty. Issue numbers (#3) link to GitHub.

The layout follows [Keep a Changelog](https://keepachangelog.com): Added,
Changed, Fixed and Removed under each version.

## 0.2.0

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
