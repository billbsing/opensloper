# Items to do

Review and testing before moving on to step 9, from `ffed2e4` on `development`. Run `./build.sh` first, which builds all three programs, including `publish/opensloper-publish`.

## To test

These could not be tested properly during development.

- [ ] **Export PDF in the window:** never clicked through a file dialog; all test exports went through the CLI.
- [ ] **A real print:** measure the 10 cm test square with a ruler, then tape two tiles together using the diamonds.
- [ ] **A real projector:** the line thicknesses are a best guess.
- [ ] **Publish… save prompt:** in the drafting app, try this with a modified pattern, and from a real save.
- [ ] **Publish window:** Flip, Reload Patterns, panning, the Delete key and the every-page title block.

## Known limits

- Pieces cannot use an edge that needs splitting. Detection names the edge, but the canvas has no split command, so the skirt's hem and side seam were split through the Automation API.
- An edge's own seam allowance, and a grainline between two points, can only be set through the Automation API.
- Each Publish… opens another window, rather than finding one already open.

## Found in review

