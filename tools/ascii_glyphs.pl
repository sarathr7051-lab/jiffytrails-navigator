#!/usr/bin/perl
# ascii_glyphs.pl - rasterise firmware/navigator/glyph_data.h to text.
#
#   perl tools/ascii_glyphs.pl            # every glyph
#   perl tools/ascii_glyphs.pl EXIT FORK  # only those whose name matches
#
# Same table as the firmware, same percent-to-pixel arithmetic. Where
# render_glyphs.pl emits SVG and lets a browser do the filling, this fills the
# shapes itself - so it is a second opinion on the geometry as well as a way to
# look at an arrow without a display attached.
#
# It also reports any ink outside the 0-100 box, which is the failure the
# box-relative coordinate system exists to prevent and the one thing a human
# eye is bad at spotting.

use strict;
use warnings;

my @want = @ARGV;

my $HDR = 'firmware/navigator/glyph_data.h';
open my $fh, '<', $HDR or die "$HDR: $!";
my $src = do { local $/; <$fh> };
close $fh;

my %glyph;
while ($src =~ /static\s+const\s+GlyphOp\s+(G_\w+)\s*\[\]\s*=\s*\{(.*?)\n\};/gs) {
    my ($name, $body) = ($1, $2);
    my @ops;
    while ($body =~ /\{\s*(OP_\w+)\s*,\s*(-?\d+)\s*,\s*(-?\d+)\s*,\s*(-?\d+)\s*,\s*(-?\d+)\s*,\s*(-?\d+)\s*,\s*(-?\d+)\s*\}/g) {
        next if $1 eq 'OP_END';
        push @ops, { op => $1, a => $2, b => $3, c => $4, d => $5, e => $6, f => $7 };
    }
    $glyph{$name} = \@ops;
}

my @entries;
if ($src =~ /static\s+const\s+GlyphEntry\s+GLYPHS\s*\[\]\s*=\s*\{(.*?)\n\};/s) {
    my $body = $1;
    while ($body =~ /\{\s*(MV_\w+)\s*,\s*(G_\w+)\s*,\s*(true|false)\s*\}/g) {
        push @entries, { code => $1, glyph => $2, mirror => ($3 eq 'true') };
    }
}
die "parsed no glyphs\n" unless @entries;

# ------------------------------------------------------------------ raster

my $S = 96;                 # render size; 2x4 pixel blocks -> 48x24 characters
my (@buf, $spill);

sub clear { @buf = map { [ (0) x $S ] } 1 .. $S; $spill = 0; }

sub put {
    my ($x, $y, $v) = @_;
    if ($x < 0 || $x >= $S || $y < 0 || $y >= $S) { $spill++ if $v; return; }
    $buf[$y][$x] = $v;
}

sub P { my $pct = shift; return int($pct * $S / 100); }

sub fill_rect {
    my ($x, $y, $w, $h, $v) = @_;
    for my $j ($y .. $y + $h - 1) { for my $i ($x .. $x + $w - 1) { put($i, $j, $v); } }
}

sub edge { my ($ax,$ay,$bx,$by,$cx,$cy) = @_; return ($bx-$ax)*($cy-$ay) - ($by-$ay)*($cx-$ax); }

sub fill_tri {
    my ($x1,$y1,$x2,$y2,$x3,$y3) = @_;
    my ($lo_x,$hi_x) = (sort { $a <=> $b } $x1,$x2,$x3)[0,2];
    my ($lo_y,$hi_y) = (sort { $a <=> $b } $y1,$y2,$y3)[0,2];
    for my $y ($lo_y .. $hi_y) {
        for my $x ($lo_x .. $hi_x) {
            my $d1 = edge($x1,$y1,$x2,$y2,$x,$y);
            my $d2 = edge($x2,$y2,$x3,$y3,$x,$y);
            my $d3 = edge($x3,$y3,$x1,$y1,$x,$y);
            my $neg = ($d1 < 0) || ($d2 < 0) || ($d3 < 0);
            my $pos = ($d1 > 0) || ($d2 > 0) || ($d3 > 0);
            put($x, $y, 1) unless ($neg && $pos);
        }
    }
}

sub line {
    my ($x0,$y0,$x1,$y1) = @_;
    my $n = (abs($x1-$x0) > abs($y1-$y0)) ? abs($x1-$x0) : abs($y1-$y0);
    $n ||= 1;
    for my $i (0 .. $n) {
        put(int($x0 + ($x1-$x0) * $i / $n + 0.5), int($y0 + ($y1-$y0) * $i / $n + 0.5), 1);
    }
}

sub disc {
    my ($cx,$cy,$r) = @_;
    for my $dy (-$r .. $r) { for my $dx (-$r .. $r) {
        put($cx+$dx, $cy+$dy, 1) if $dx*$dx + $dy*$dy <= $r*$r;
    } }
}

sub annulus {
    my ($cx,$cy,$r,$t) = @_;
    my $inner = $r - $t;
    for my $dy (-$r .. $r) { for my $dx (-$r .. $r) {
        my $d2 = $dx*$dx + $dy*$dy;
        put($cx+$dx, $cy+$dy, 1) if $d2 <= $r*$r && $d2 > $inner*$inner;
    } }
}

sub draw {
    my ($ops, $mir) = @_;
    my $px  = sub { my $p = shift; return P($mir ? 100 - $p : $p); };
    my $py  = sub { my $p = shift; return P($p); };
    my $pxf = sub { my $p = shift; return int(($mir ? 100 - $p : $p) * $S / 100); };
    my $pyf = sub { my $p = shift; return int($p * $S / 100); };

    for my $o (@$ops) {
        my $t = $o->{op};
        if ($t eq 'OP_RECT' or $t eq 'OP_RECT_BG') {
            fill_rect($px->($mir ? $o->{a} + $o->{c} : $o->{a}), $py->($o->{b}),
                      P($o->{c}), P($o->{d}), ($t eq 'OP_RECT_BG') ? 0 : 1);
        }
        elsif ($t eq 'OP_TRI') {
            fill_tri($px->($o->{a}), $py->($o->{b}),
                     $px->($o->{c}), $py->($o->{d}),
                     $px->($o->{e}), $py->($o->{f}));
        }
        elsif ($t eq 'OP_LINE') {
            my $w = P($o->{e});
            my ($x0,$y0) = ($px->($o->{a}), $py->($o->{b}));
            my ($x1,$y1) = ($px->($o->{c}), $py->($o->{d}));
            line($x0+$_, $y0, $x1+$_, $y1) for (-int($w/2) .. int($w/2));
        }
        elsif ($t eq 'OP_CIRC') { disc($px->($o->{a}), $py->($o->{b}), P($o->{c})); }
        elsif ($t eq 'OP_RING') { annulus($px->($o->{a}), $py->($o->{b}), P($o->{c}), P($o->{d})); }
        elsif ($t eq 'OP_ARC')  {
            my $rp = $o->{c}; my $dot = P($o->{d});
            for my $i (0 .. 24) {
                my $rad = ($o->{e} + ($o->{f} - $o->{e}) * $i / 24) * 3.14159265 / 180.0;
                disc($pxf->($o->{a} - $rp * cos($rad)), $pyf->($o->{b} - $rp * sin($rad)), $dot);
            }
        }
    }
}

# 2 px wide x 4 px tall per character, so the aspect looks roughly square.
sub emit {
    my @rows;
    for (my $r = 0; $r < $S; $r += 4) {
        my $line = '';
        for (my $c = 0; $c < $S; $c += 2) {
            my $on = 0;
            for my $dy (0 .. 3) { for my $dx (0 .. 1) {
                $on ||= $buf[$r+$dy][$c+$dx] if $r+$dy < $S && $c+$dx < $S;
            } }
            $line .= $on ? '#' : '.';
        }
        push @rows, $line;
    }
    return @rows;
}

# ------------------------------------------------------------------ main

my $bad = 0;
for my $e (@entries) {
    my $short = $e->{code}; $short =~ s/^MV_//;
    if (@want) { next unless grep { index($short, uc $_) >= 0 } @want; }
    my $ops = $glyph{$e->{glyph}} or next;

    clear();
    draw($ops, $e->{mirror});
    my @rows = emit();

    printf "%s   [%s%s]\n", $short, $e->{glyph}, ($e->{mirror} ? ', mirrored' : '');
    print "  $_\n" for @rows;
    if ($spill) { printf "  !! %d pixels outside the box\n", $spill; $bad++; }
    print "\n";
}

if ($bad) { printf "FAIL: %d glyph(s) draw outside the box\n", $bad; exit 1; }
print "all glyphs stay inside the box\n";
