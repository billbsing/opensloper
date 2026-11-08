# Getting started

OpenSloper has no installer yet, so for now you build it from source. It runs
on Linux and macOS.

## What you need

- **Lazarus 4.8 with Free Pascal 3.2.2**, from your distribution or
  [lazarus-ide.org](https://www.lazarus-ide.org). Other versions from Free
  Pascal 3.2.0 on should work.
- **Git**, to fetch the code and the libraries it uses.
- **On Linux**, the Qt Pascal bindings: `libQt6Pas` or `libQt5Pas`. Qt 6 is
  used when it is installed.

## Build

```
git clone --recursive https://github.com/billbsing/opensloper.git
cd opensloper
./build.sh
```

The apps are built into `release/`:

```
release/opensloper-design
release/opensloper-measurements
release/opensloper-publish
release/opensloper-cli
```

If you cloned without `--recursive`, fetch the libraries first with
`git submodule update --init --recursive`.

## First steps

1. Start **opensloper-measurements** and make a measurement file (`.slm`) with
   the measurements your pattern needs, or open one you have.
2. Start **opensloper-design**, make a new pattern (File → New) and choose its
   measurement file (File → Measurements → Open Set…). Draw points and lines; their places are formulas that can read
   the measurements.
3. Make pieces from the closed outlines, then open **opensloper-publish** from
   the design app (File → Publish…) to lay the pieces out and print them.

## Preferences

Edit → Preferences… sets the unit you work in (mm, cm or inches), the grid
spacing and the printer calibration. The three apps share them. A new pattern
takes the unit from Preferences; a pattern keeps the unit it was made in, and
Tools → Convert Pattern Units… changes it.

Settings are kept in `~/.config/opensloper/` on Linux.
