#!/usr/bin/perl
# ascii_junction.pl - rasterise the demo junctions the way geom.cpp draws them.
#
#   perl tools/ascii_junction.pl [box_px]     # default 96, the approach box
#
# Parses the junc*() builders out of firmware/navigator/demo.cpp and reproduces
# geomDraw(): same rider anchor, same decimetre-to-pixel scale, same layer
# ordering, same halo-punches-a-gap trick. So what you see is the renderer's
# arithmetic rather than an artist's impression of it.
#
# Legend:  #  your path      :  other roads      @  the rider
#
# The halo is what makes a flyover read. A higher layer is drawn with a
# background-coloured stroke before its ink, so it erases the road beneath
# where they cross. If the cross road does NOT break under the flyover here,
# the layer ordering is wrong and it will be wrong on the panel too.

use strict;
use warnings;

my $S = @ARGV ? $ARGV[0] : 96;

my $SRC = 'firmware/navigator/demo.cpp';
open my $fh, '<', $SRC or die "$SRC: $!";
my $src = do { local $/; <$fh> };
close $fh;

my $DEPTH = 120;
if (open my $g, '<', 'firmware/navigator/geom.h') {
    local $/; my $t = <$g>; close $g;
    $DEPTH = $1 if $t =~ /GEOM_DEPTH_M\s*=\s*(\d+)/;
}

# ------------------------------------------------------------------ parse

my @junctions;
while ($src =~ /void\s+(junc\w+)\s*\(\s*\)\s*\{(.*?)\n\}/gs) {
    my ($name, $body) = ($1, $2);

    my @ways;
    my ($ccy, $rr) = (620, 250);
    $ccy = $1 if $body =~ /ccy\s*=\s*(\d+)/;
    $rr  = $1 if $body =~ /rr\s*=\s*(\d+)/;

    for my $line (split /\n/, $body) {
        if ($line =~ /geomWay\(\s*(-?\d+)\s*,\s*(\w+)\s*\)/) {
            # Copy the captures out FIRST. Testing $2 with another match resets
            # $1, so writing `layer => $1, taken => ($2 =~ /TAKEN/ ...)` silently
            # loses the layer on exactly the ways where the inner match succeeds
            # - which is to say, on every taken way and no other. It rendered as
            # the route line vanishing while the side roads stayed.
            my ($lay, $flg) = ($1, $2);
            push @ways, { layer => $lay, taken => ($flg =~ /TAKEN/ ? 1 : 0), pts => [] };
        }
        while ($line =~ /geomPt\(\s*(-?\d+)\s*,\s*(-?\d+)\s*\)/g) {
            push @{ $ways[-1]{pts} }, [$1, $2] if @ways;
        }
        # Anything not written as literal integers is invisible here. That is
        # deliberate and the junction builders are written to suit it: a
        # loop-generated ring once rendered as no ring at all, which looked
        # like a renderer bug and was really a parser blind spot. Data a tool
        # cannot read is data nobody checks before flashing.
        if ($line =~ /geomPt\s*\(\s*[^-\d\s)]/ && $line !~ /^\s*\/\//) {
            warn "  ! non-literal geomPt ignored: " . ($line =~ s/^\s+//r) . "\n";
        }
    }
    push @junctions, { name => $name, ways => \@ways } if @ways;
}
die "parsed no junctions from $SRC\n" unless @junctions;

# ------------------------------------------------------------------ raster

my @buf;
sub clear { @buf = map { [ ('.') x $S ] } 1 .. $S; }

my %RANK = ('.' => 0, ':' => 1, '#' => 2, '@' => 3, ' ' => 0);

sub put {
    my ($x, $y, $c) = @_;
    return if $x < 0 || $x >= $S || $y < 0 || $y >= $S;   # geom.cpp clips too
    # A halo genuinely erases: background wins over ink, which is the whole
    # mechanism by which a flyover breaks the road beneath it.
    if ($c eq ' ') { $buf[$y][$x] = '.'; return; }
    $buf[$y][$x] = $c if $RANK{$c} >= $RANK{ $buf[$y][$x] };
}

# A solid capsule: every pixel within w/2 of the segment. geom.cpp draws a quad
# plus an octagonal joint, which is the same shape to within half a pixel - and
# both are SOLID, which is the point. The version this replaced offset parallel
# lines and left gaps on diagonals, exactly as the firmware did.
sub stroke {
    my ($ax, $ay, $bx, $by, $w, $c) = @_;
    my ($dx, $dy) = ($bx - $ax, $by - $ay);
    my $l2 = $dx * $dx + $dy * $dy;
    my $r  = $w / 2;

    my ($lo_x, $hi_x) = (sort { $a <=> $b } $ax, $bx)[0, 1];
    my ($lo_y, $hi_y) = (sort { $a <=> $b } $ay, $by)[0, 1];

    for my $y (int($lo_y - $r) .. int($hi_y + $r)) {
        for my $x (int($lo_x - $r) .. int($hi_x + $r)) {
            my $t = $l2 ? (($x - $ax) * $dx + ($y - $ay) * $dy) / $l2 : 0;
            $t = 0 if $t < 0; $t = 1 if $t > 1;
            my $px = $ax + $dx * $t, my $py = $ay + $dy * $t;
            put($x, $y, $c) if ($x - $px) ** 2 + ($y - $py) ** 2 <= $r * $r;
        }
    }
}

sub disc {
    my ($cx, $cy, $r, $c) = @_;
    for my $dy (-$r .. $r) { for my $dx (-$r .. $r) {
        put($cx + $dx, $cy + $dy, $c) if $dx * $dx + $dy * $dy <= $r * $r;
    } }
}

for my $j (@junctions) {
    clear();

    my $cx = int($S / 2);
    my $cy = $S - int($S / 8);
    my $sx = sub { $cx + int($_[0] * $S / ($DEPTH * 10)) };
    my $sy = sub { $cy - int($_[0] * $S / ($DEPTH * 10)) };

    my $wThin  = $S >= 96 ? 6  : 5;    # keep in step with geom.cpp
    my $wThick = $S >= 96 ? 15 : 12;
    my $halo   = 10;   # keep in step with geom.cpp

    # Casing pass then fill pass, PER LAYER - matching geom.cpp. Per-segment
    # lets a halo notch the previous segment at every joint; per-way lets two
    # roads on the SAME layer halo each other. A halo may only break layers
    # below it, and drawing every halo on a layer before any ink is what makes
    # that true.
    for my $layer (-2 .. 2) {
      for my $pass (0, 1) {
        for my $w (@{ $j->{ways} }) {
            next unless defined $w->{layer};
            next unless $w->{layer} == $layer && @{ $w->{pts} } >= 2;
            my $wd = $w->{taken} ? $wThick : $wThin;
            my $pw = $pass ? $wd : $wd + $halo;
            my $pc = $pass ? ($w->{taken} ? '#' : ':') : ' ';
            my @p  = @{ $w->{pts} };
            for my $k (0 .. $#p - 1) {
                my ($ax, $ay) = ($sx->($p[$k][0]),   $sy->($p[$k][1]));
                my ($bx, $by) = ($sx->($p[$k+1][0]), $sy->($p[$k+1][1]));
                stroke($ax, $ay, $bx, $by, $pw, $pc);
            }
        }
      }
    }

    my $r = $S >= 96 ? 7 : 6;
    disc($cx, $cy, $r + 3, ' ');
    disc($cx, $cy, $r,     '@');

    printf "%s   (%d px box, %d m deep)\n", $j->{name}, $S, $DEPTH;
    for (my $row = 0; $row < $S; $row += 4) {
        my $line = '';
        for (my $col = 0; $col < $S; $col += 2) {
            my $best = '.';
            for my $dy (0 .. 3) { for my $dx (0 .. 1) {
                next if $row + $dy >= $S || $col + $dx >= $S;
                my $v = $buf[$row + $dy][$col + $dx];
                $best = $v if $RANK{$v} > $RANK{$best};
            } }
            $line .= $best;
        }
        print "  $line\n";
    }
    print "\n";
}
