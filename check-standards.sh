#!/usr/bin/env bash
# Check the Pascal sources for the coding standards that the formatter cannot
# enforce (see documents/coding-standards.md and CLAUDE.md). CI runs it on
# every pull request; run it before committing, with ./format.sh --check.
#
#   ./check-standards.sh           check every source file
#   ./check-standards.sh FILE...   check only the given files
#
# Errors fail the check (exit 1). Warnings are reported but do not fail it:
# they are heuristics a reviewer should look at. Under GitHub Actions both are
# also written as annotations, so they show on the pull request's diff.
set -euo pipefail

if [ $# -gt 0 ]; then
  FILES=("$@")
else
  cd "$(dirname "$0")"
  mapfile -t FILES < <(git ls-files --cached --others --exclude-standard '*.pas' '*.lpr' '*.pp' |
    grep -v '^src/packages/' | grep -v '^src/core/clipper2/osclipper2.pas$')
fi

exec perl -x "$0" "${FILES[@]}"

#!perl
use strict;
use warnings;

my $github = ($ENV{GITHUB_ACTIONS} // '') eq 'true';
my ($errors, $warnings) = (0, 0);

# Units that pull in the LCL (or a GUI library); not allowed below src/ui
my %lcl = map { lc($_) => 1 } qw(
  Forms Graphics Controls Dialogs StdCtrls ExtCtrls ComCtrls Menus ActnList
  ButtonPanel CheckLst Grids Spin Buttons Clipbrd ImgList ExtDlgs Interfaces
  LCLProc LCLType LCLIntf LMessages LResources BGRABitmap BGRABitmapTypes BGRASVG);

# Sloper areas each folder may use; folders not listed may use any area
my %allowed = (
  'src/core'     => [qw(Core)],
  'src/document' => [qw(Core Document)],
  'src/api'      => [qw(Core Document Output API)],
  'src/output'   => [qw(Core Output)],
  'src/cli'      => [qw(Core Document Output API CLI Docs)],
  'src/docs'     => [qw(Core API CLI Docs)],
);
my %no_lcl = map { $_ => 1 } qw(src/core src/document src/api src/output src/cli src/docs);

# Units where single-letter names match the maths (coding-standards.md)
my %math = map { $_ => 1 } qw(
  src/core/sloper.core.geometry.pas src/core/sloper.core.bezier.pas src/core/sloper.core.numeric.pas);

sub report {
  my ($kind, $file, $line, $msg) = @_;
  if ($kind eq 'error') { $errors++ } else { $warnings++ }
  print "$file:$line: $kind: $msg\n";
  print "::${kind} file=${file},line=${line}::${msg}\n" if $github;
}

sub line_of { my ($text, $pos) = @_; return 1 + (substr($text, 0, $pos) =~ tr/\n//) }

# Blank out comments (and strings, when asked), keeping offsets and newlines,
# so later patterns only see code and still report the right line
sub blank {
  my ($tok, $strings) = @_;
  return $tok if $tok =~ /^'/ && !$strings;
  return "'" . (' ' x (length($tok) - 2)) . "'" if $tok =~ /^'/;
  $tok =~ s/[^\n]/ /g;
  return $tok;
}

sub strip {
  my ($text, $strings) = @_;
  $text =~ s!(\{[^}]*\}|\(\*.*?\*\)|//[^\n]*|'(?:[^'\n]|'')*')!blank($1, $strings)!gse;
  return $text;
}

for my $file (@ARGV) {
  open(my $fh, '<', $file) or do { report('error', $file, 1, "cannot read: $!"); next };
  local $/;
  my $raw = <$fh>;
  close $fh;
  my $nocomments = strip($raw, 0);
  my $code = strip($raw, 1);
  (my $dir = $file) =~ s{/[^/]*$}{};
  my $is_test = $file =~ m{^tests/};

  # GPL header, then the compiler mode
  my $head = join("\n", grep { defined } (split /\n/, $raw)[0 .. 24]);
  report('error', $file, 1, 'missing the GPLv3 header from documents/gpl-header.txt')
    unless $head =~ /GNU General Public License/ && $head =~ /either version 3/;
  report('error', $file, 1, 'missing {$mode ObjFPC}{$H+}')
    if $file =~ /\.pas$/ && $raw !~ /\{\$mode\s+objfpc\}\s*\{\$H\+\}/i;

  # Unit name matches the file name and folder
  if ($file =~ /\.pas$/ && $code =~ /^\s*unit\s+([\w.]+)\s*;/mi) {
    my $unit = $1;
    (my $base = $file) =~ s{.*/}{};
    report('error', $file, line_of($code, $-[0]), "unit $unit should be in a file named " . lc($unit) . '.pas')
      unless lc($unit) . '.pas' eq $base;
    my ($area) = $dir =~ m{^(?:src/)?([^/]+)$};
    report('error', $file, line_of($code, $-[0]), "unit $unit should be named Sloper.<Area>.<Name> for folder $dir")
      unless defined $area && $unit =~ /^Sloper\.\Q$area\E\./i;
  }

  # Uses clauses: layering and Sloper.Core.CodePage first in programs
  my $first_uses = 1;
  while ($code =~ /\buses\b(.*?);/gsi) {
    my ($list, $at) = ($1, $-[0]);
    my @units = map { s/\s+in\s+.*//sr =~ s/^\s+|\s+$//gr } split /,/, $list;
    if ($file =~ /\.lpr$/ && $first_uses) {
      my ($first) = grep { !/^(cthreads|cmem)$/i } @units;
      report('error', $file, line_of($code, $at), 'Sloper.Core.CodePage must be the first unit in a program\'s uses clause')
        unless defined $first && lc($first) eq 'sloper.core.codepage';
    }
    $first_uses = 0;
    for my $unit (@units) {
      report('error', $file, line_of($code, $at), "$dir must not use the LCL unit $unit")
        if $no_lcl{$dir} && $lcl{lc $unit};
      if ($allowed{$dir} && $unit =~ /^Sloper\.(\w+)\./i) {
        my $area = $1;
        report('error', $file, line_of($code, $at), "$dir must not use $unit (allowed: Sloper." .
          join(', Sloper.', @{ $allowed{$dir} }) . ')')
          unless grep { lc($_) eq lc($area) } @{ $allowed{$dir} };
      }
    }
  }

  # FreeAndNil, not .Free or .Destroy on a reference; an indexed or typecast
  # item (Controls[0].Free, TObject(List[Index]).Free) is the documented exception
  while ($code =~ /(?<![\w.)\]])([A-Za-z_]\w*(?:\.[A-Za-z_]\w*)*)\.(Free|Destroy)\s*;/g) {
    next if substr($code, 0, $-[0]) =~ /\bdestructor\s+$/i;
    report('error', $file, line_of($code, $-[0]), "use FreeAndNil($1), not $1.$2");
  }

  # Assigned(), not comparisons with nil (default values such as "X: T = nil" are fine)
  while ($code =~ /(<>|(?<![:<>])=)\s*nil\b/gi) {
    my $pos = $-[0];
    my $before = substr($code, 0, $pos);
    next if $1 eq '=' && $before =~ /:\s*[\w.]+\s*$/;
    report('error', $file, line_of($code, $pos), 'test references with Assigned(), not a comparison with nil');
  }

  # Shortcuts use ssModifier
  while ($code =~ /\bssCtrl\b/g) {
    report('error', $file, line_of($code, $-[0]), 'use ssModifier for shortcuts, not ssCtrl');
  }

  next if $is_test;

  # User-visible text belongs in resourcestring sections
  while ($nocomments =~ /\b(?:ShowMessage|MessageDlg|QuestionDlg|MessageBox)\s*\(\s*'|\b(?:Caption|Hint)\s*:=\s*'[^']*[A-Za-z]{2}/g) {
    report('error', $file, line_of($nocomments, $-[0]), 'user-visible text should be a resourcestring');
  }

  # Descriptive names: single-letter variables, fields and parameters
  next if $math{$file};
  # The whole name list is matched, so a short name after a long one
  # (Centre, Direction, P: TVec2) is found too
  while ($code =~ /(?:^[ \t]*|[(;][ \t]*(?:const |var |out )?)((?:[A-Za-z_]\w*[ \t]*,[ \t]*)*[A-Za-z_]\w*)[ \t]*:(?!=)/mg) {
    my ($names, $pos) = ($1, $-[1]);
    # Coordinates read well as X, Y, Z
    my @short = grep { /^[A-Za-z]$/ && !/^[XYZ]$/i } split /[ \t]*,[ \t]*/, $names;
    next unless @short;
    report('warning', $file, line_of($code, $pos), 'single-letter name (' . join(', ', @short) . '); use a descriptive name');
  }
}

my $checked = scalar @ARGV;
print "Checked $checked files: $errors errors, $warnings warnings.\n";
exit($errors ? 1 : 0);
