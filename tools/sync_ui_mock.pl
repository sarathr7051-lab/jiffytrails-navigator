#!/usr/bin/perl
# sync_ui_mock.pl - copy the navigator's shared sources into the ui_mock sketch.
#
#   perl tools/sync_ui_mock.pl            # copy
#   perl tools/sync_ui_mock.pl --check    # exit 1 if any copy is stale
#
# WHY A COPY AND NOT AN INCLUDE. The obvious answer - one shim file in
# ui_mock/src/ that #includes ../../navigator/display.cpp - does not work.
# arduino-cli copies the sketch folder into a build directory before compiling
# it, so a relative include pointing outside the sketch resolves against the
# copy and finds nothing. The Arduino IDE behaves the same way. There is no
# include path setting that survives both, short of installing the shared code
# as a library outside the repository.
#
# So: generated copies, and a --check mode that makes staleness an error rather
# than something you discover on the panel. The old ui_mock drifted for five
# days and ended up drawing arrows the firmware had stopped drawing; the point
# of this script is that the same drift now fails loudly instead.
#
# Run --check before committing any change to firmware/navigator/.

use strict;
use warnings;

my $CHECK = (@ARGV && $ARGV[0] eq '--check');

my $SRC = 'firmware/navigator';
my $DST = 'firmware/ui_mock/src';

# Everything the display needs, and nothing else. ble.*, watchdog.* and the
# navigator's own .ino are deliberately absent: ui_mock has no radio, and a
# watchdog with no packets to watch would paint STALE over the demo.
my @FILES = qw(
    nav_types.h
    glyph_data.h
    geom.h     geom.cpp
    ota.h      ota.cpp
    display.h  display.cpp
    maneuvers.h maneuvers.cpp
    demo.h     demo.cpp
);

my $BANNER = <<'END';
// ---------------------------------------------------------------------------
// GENERATED COPY - DO NOT EDIT.
//
// Source of truth: firmware/navigator/%s
// Regenerate:      perl tools/sync_ui_mock.pl
//
// arduino-cli and the Arduino IDE both copy a sketch before compiling it, so
// this sketch cannot #include across to firmware/navigator/. This file is a
// verbatim copy. Edit the original; `perl tools/sync_ui_mock.pl --check` fails
// if the two have diverged.
// ---------------------------------------------------------------------------
END

mkdir $DST unless -d $DST;

my $stale = 0;
for my $f (@FILES) {
    my $in = "$SRC/$f";
    open my $i, '<', $in or die "$in: $!\n";
    my $body = do { local $/; <$i> };
    close $i;

    my $want = sprintf($BANNER, $f) . $body;

    my $out = "$DST/$f";
    my $have = '';
    if (open my $o, '<', $out) { local $/; $have = <$o>; close $o; }

    if ($have eq $want) { next; }

    if ($CHECK) {
        printf "STALE  %s\n", $out;
        $stale++;
        next;
    }
    open my $o, '>', $out or die "$out: $!\n";
    print $o $want;
    close $o;
    printf "copied %s\n", $f;
}

if ($CHECK) {
    if ($stale) {
        printf "\n%d file(s) out of date - run: perl tools/sync_ui_mock.pl\n", $stale;
        exit 1;
    }
    print "ui_mock is in sync with firmware/navigator\n";
}
