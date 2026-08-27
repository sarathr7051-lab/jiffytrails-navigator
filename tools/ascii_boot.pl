#!/usr/bin/perl
# ascii_boot.pl - rasterise the boot screen from display.cpp's own constants.
#
#   perl tools/ascii_boot.pl [sweep_degrees]     # default 360, the finished ring
#
# Parses MARK_CX/CY, RING_R, MARK_S, WORD1_Y, WORD2_Y, RULE_Y/HALF and the
# TRAIL polyline straight out of firmware/navigator/display.cpp, so the picture
# is the firmware's arithmetic rather than a second copy of it.
#
# Text extents come from TFT_eSPI's OWN width tables (Font16.c, Font32rle.c),
# because guessing text width is what clipped this display twice before. If the
# library is not where this expects it, the script says so rather than
# inventing numbers.
#
# Legend:  #  ink        o  accent (the waypoint)
#          :  ring track (grey)      =  text extent      -  the rule

use strict;
use warnings;

my $SWEEP = @ARGV ? $ARGV[0] : 360;

my $SRC = 'firmware/navigator/display.cpp';
open my $fh, '<', $SRC or die "$SRC: $!";
my $cpp = do { local $/; <$fh> };
close $fh;

sub konst {
    my $n = shift;
    $cpp =~ /\b\Q$n\E\s*=\s*(-?\d+)/ or die "could not find $n in $SRC\n";
    return $1;
}

my %K = map { $_ => konst($_) }
        qw(MARK_CX MARK_CY RING_R MARK_S WORD1_Y WORD2_Y RULE_Y RULE_HALF);

my @TRAIL;
if ($cpp =~ /static\s+const\s+Pt\s+TRAIL\[\]\s*=\s*\{(.*?)\};/s) {
    my $b = $1;
    while ($b =~ /\{\s*(-?\d+)\s*,\s*(-?\d+)\s*\}/g) { push @TRAIL, [$1, $2]; }
}
die "no TRAIL polyline found\n" unless @TRAIL >= 2;
my ($DOTX, $DOTY) = $cpp =~ /TRAIL_DOT\s*=\s*\{\s*(-?\d+)\s*,\s*(-?\d+)\s*\}/
    or die "no TRAIL_DOT found\n";

# ------------------------------------------------- TFT_eSPI width tables

my $FONTDIR = 'C:/dev/Arduino/libraries/TFT_eSPI/Fonts';

sub widths {
    my ($file, $tbl) = @_;
    my $p = "$FONTDIR/$file";
    open my $f, '<', $p or die "$p: $!\n(the real width tables are the point of "
                             . "this script - fix the path rather than guessing)\n";
    my $s = do { local $/; <$f> };
    close $f;
    # The declaration carries a trailing comment between "=" and "{".
    $s =~ m{\Q$tbl\E\s*\[\s*\d*\s*\]\s*=\s*(?://[^\n]*\n\s*)?\{(.*?)\}}s
        or die "no $tbl in $p\n";
    my $body = $1;
    $body =~ s{//[^\n]*}{}g;
    my @w = $body =~ /(\d+)/g;
    die "short table $tbl (" . scalar(@w) . ")\n" unless @w >= 96;
    return \@w;
}

my %W = ( 2 => widths('Font16.c', 'widtbl_f16'),
          4 => widths('Font32rle.c', 'widtbl_f32') );
my %HGT = ( 2 => 16, 4 => 26 );

sub text_w {
    my ($s, $font, $extra) = @_;
    my $t = 0;
    $t += $W{$font}[ord($_) - 32] + $extra for split //, $s;
    return $t - $extra;
}

# ------------------------------------------------------------- raster

my ($WD, $HT) = (320, 240);
my @buf = map { [ ('.') x $WD ] } 1 .. $HT;
my $spill = 0;

sub put {
    my ($x, $y, $c) = @_;
    $x = int($x); $y = int($y);
    if ($x < 0 || $x >= $WD || $y < 0 || $y >= $HT) { $spill++; return; }
    my %rank = ('.' => 0, ':' => 1, '-' => 2, '=' => 3, '#' => 4, 'o' => 5);
    $buf[$y][$x] = $c if $rank{$c} >= $rank{ $buf[$y][$x] };
}

sub disc { my ($cx,$cy,$r,$c) = @_;
    for my $dy (-$r..$r) { for my $dx (-$r..$r) {
        put($cx+$dx, $cy+$dy, $c) if $dx*$dx + $dy*$dy <= $r*$r; } } }

sub rect { my ($x,$y,$w,$h,$c) = @_;
    for my $j ($y .. $y+$h-1) { for my $i ($x .. $x+$w-1) { put($i,$j,$c); } } }

sub stroke {                       # perpendicular offset, like the firmware
    my ($x0,$y0,$x1,$y1,$w,$c) = @_;
    my ($dx,$dy) = ($x1-$x0, $y1-$y0);
    my $len = sqrt($dx*$dx + $dy*$dy) || 1;
    my ($nx,$ny) = (-$dy/$len, $dx/$len);
    for my $i (-int($w/2) .. int($w/2)) {
        my $n = int($len) || 1;
        for my $t (0 .. $n) {
            put($x0 + $dx*$t/$n + $nx*$i, $y0 + $dy*$t/$n + $ny*$i, $c);
        }
    }
}

sub mx { my $c = shift; return $K{MARK_CX} - $K{MARK_S}/2 + $c * $K{MARK_S} / 64; }
sub my_ { my $c = shift; return $K{MARK_CY} - $K{MARK_S}/2 + $c * $K{MARK_S} / 64; }

# ring track, then the swept portion
for (my $a = 0; $a < 360; $a += 1) {
    my $r = $a * 3.14159265 / 180;
    disc($K{MARK_CX} + $K{RING_R}*sin($r), $K{MARK_CY} - $K{RING_R}*cos($r), 1, ':');
}
for (my $a = 0; $a <= $SWEEP; $a += 2) {
    my $r = $a * 3.14159265 / 180;
    disc($K{MARK_CX} + $K{RING_R}*sin($r), $K{MARK_CY} - $K{RING_R}*cos($r), 2, '#');
}

# the trail
my $sw = int($K{MARK_S} * 7 / 64);
disc(mx($TRAIL[0][0]), my_($TRAIL[0][1]), int($sw/2), '#');
for my $i (1 .. $#TRAIL) {
    stroke(mx($TRAIL[$i-1][0]), my_($TRAIL[$i-1][1]),
           mx($TRAIL[$i][0]),   my_($TRAIL[$i][1]), $sw, '#');
    disc(mx($TRAIL[$i][0]), my_($TRAIL[$i][1]), int($sw/2), '#');
}
disc(mx($DOTX), my_($DOTY), int($K{MARK_S} * 6 / 64), 'o');

# wordmark extents, real widths
for my $t ( ['JIFFY', 2, 3, $K{WORD1_Y}], ['TRAILS', 4, 1, $K{WORD2_Y}] ) {
    my ($s, $f, $x, $y) = @$t;
    my $w = text_w($s, $f, $x);
    rect($K{MARK_CX} - int($w/2), $y, $w, $HGT{$f}, '=');
}

rect($K{MARK_CX} - $K{RULE_HALF}, $K{RULE_Y}, $K{RULE_HALF}*2, 2, '-');

# ------------------------------------------------------------- emit

print "boot screen, ring swept ${SWEEP} deg   (4x8 px per character)\n\n";
for (my $r = 0; $r < $HT; $r += 8) {
    my $line = '';
    for (my $c = 0; $c < $WD; $c += 4) {
        my $best = '.';
        my %rank = ('.' => 0, ':' => 1, '-' => 2, '=' => 3, '#' => 4, 'o' => 5);
        for my $dy (0 .. 7) { for my $dx (0 .. 3) {
            my $v = $buf[$r+$dy][$c+$dx];
            $best = $v if $rank{$v} > $rank{$best};
        } }
        $line .= $best;
    }
    printf "  %s\n", $line;
}

print "\n";
printf "  ring      y %d..%d\n", $K{MARK_CY}-$K{RING_R}, $K{MARK_CY}+$K{RING_R};
printf "  JIFFY     y %d..%d   w %d\n", $K{WORD1_Y}, $K{WORD1_Y}+$HGT{2}, text_w('JIFFY',2,3);
printf "  TRAILS    y %d..%d   w %d\n", $K{WORD2_Y}, $K{WORD2_Y}+$HGT{4}, text_w('TRAILS',4,1);
printf "  rule      y %d..%d   w %d\n", $K{RULE_Y}, $K{RULE_Y}+2, $K{RULE_HALF}*2;
print  "\n";
if ($spill) { printf "  !! %d pixels off-screen\n", $spill; exit 1; }
print "  everything on screen\n";
