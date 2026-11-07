# Command line

!!! note

    This page is generated from the program by `opensloper-cli doc cli`; do not edit it by hand.

`opensloper-cli` exports and checks patterns without a window, for scripts and builds.

```
opensloper-cli [options] <command> [arguments]
```

## Commands

### check

Evaluate a pattern and report problems

```
opensloper-cli check PATTERN [-m FILE] [-s SIZE] [--json]
```

### export

Export a layout file as PDF, SVG or DXF

```
opensloper-cli export LAYOUT [-o FILE] [--format FORMAT] [--profile NAME]
```

### export-draft

Export a pattern's draft as SVG, as the drafting window shows it

```
opensloper-cli export-draft PATTERN [-o FILE] [-m FILE] [-s SIZE] [--labels]
```

### layout

Start a layout file for a pattern, with every piece placed

```
opensloper-cli layout PATTERN [-o FILE] [-m FILE] [-s SIZE]
```

### measurements

List a measurement file, set a value, or see what a pattern needs that it lacks

```
opensloper-cli measurements list FILE [-s SIZE] [--json]
opensloper-cli measurements set FILE KEY VALUE [-s SIZE] [-d TEXT]
opensloper-cli measurements missing FILE PATTERN
```

### pack

Pack a layout's pieces and rewrite the layout file

```
opensloper-cli pack LAYOUT
```

### serve

Answer JSON-RPC 2.0 on stdin and stdout, one message per line

```
opensloper-cli serve
```

### doc

Write a page of the reference documentation as Markdown; with no topic, list the topics

```
opensloper-cli doc TOPIC [-o FILE]
opensloper-cli doc
```

## Options

| Option | Value | Description |
| --- | --- | --- |
| `-h`, `--help` |  | Show this help |
| `-V`, `--version` |  | Show the version |
| `-m`, `--measurements` | file | Measurement file (.slm); default: the one the pattern names |
| `-s`, `--size` | size | check, layout: the size to use from a size table, default the first; measurements: the size to list or set |
| `-d`, `--description` | text | measurements set: the description; default: keep the one it has |
| `--json` |  | check: print every computed value as JSON; measurements list: print the file |
| `-o`, `--output` | file | layout, export, export-draft, doc: the file to write |
| `--format` | format | export: pdf, svg, dxf or machine-dxf; default: the extension of --output, or pdf |
| `--profile` | name | export: a machine profile from the settings, in place of the layout's |
| `--labels` |  | export-draft: name the points and pieces |

## Arguments

After the command, in this order; each command takes the ones it needs.

| Argument | Description |
| --- | --- |
| `pattern` | Pattern file (.sloper), layout file (.slayout) to export, for measurements: list, set or missing, or for doc: the topic |
| `file` | measurements: the measurement file (.slm) |
| `key` | measurements set: the key; measurements missing: the pattern file |
| `value` | measurements set: the value in mm |

## Exit codes

| Code | Meaning |
| --- | --- |
| 0 | Success |
| 1 | check: the pattern has problems |
| 2 | A usage error, or a file that could not be read or written |
