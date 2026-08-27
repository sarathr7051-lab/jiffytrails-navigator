#!/usr/bin/perl
# render_glyphs.pl - draw firmware/navigator/glyph_data.h as an HTML contact sheet.
#
# This parses the SAME table the firmware compiles, so what you look at is the
# firmware's arithmetic and not a second implementation of it. It reproduces the
# interpreter in maneuvers.cpp op for op, including integer truncation in the
# percent-to-pixel step and the horizontal-offset stroke, because those are
# exactly where the geometry bugs on this project have lived.
#
#   perl tools/render_glyphs.pl > build/glyphs.html
#
# It renders every maneuver at the two box sizes the layout actually uses:
# 104 px (UI_NAV_COMMITTED / UI_NAV_NOW) and 84 px (UI_NAV_FAR).

use strict;
use warnings;

my $HDR = 'firmware/navigator/glyph_data.h';
open my $fh, '<', $HDR or die "$HDR: $!";
my $src = do { local $/; <$fh> };
close $fh;

# ---------------------------------------------------------------- parse

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
die "parsed no glyphs - has the table format changed?\n" unless @entries;

# ---------------------------------------------------------------- interpret
# Mirrors maneuvers.cpp exactly. int() truncates toward zero like C integer
# division on the non-negative values these tables contain.

sub P  { my ($s,$pct) = @_; return int($pct * $s / 100); }

sub mk {
    my ($s, $mir) = @_;
    return {
        s   => $s,
        mir => $mir,
        px  => sub { my $p = shift; return P($s, $mir ? 100 - $p : $p); },
        py  => sub { my $p = shift; return P($s, $p); },
        pxf => sub { my $p = shift; return int(($mir ? 100 - $p : $p) * $s / 100); },
        pyf => sub { my $p = shift; return int($p * $s / 100); },
    };
}

sub render {
    my ($ops, $s, $mir) = @_;
    my $b = mk($s, $mir);
    my ($px, $py, $pxf, $pyf) = ($b->{px}, $b->{py}, $b->{pxf}, $b->{pyf});
    my @out;

    for my $o (@$ops) {
        my $t = $o->{op};

        if ($t eq 'OP_RECT' or $t eq 'OP_RECT_BG') {
            my $fill = $t eq 'OP_RECT_BG' ? 'var(--bg)' : 'var(--fg)';
            # rectX: a mirrored rect starts at what was its right edge.
            my $x = $px->($mir ? $o->{a} + $o->{c} : $o->{a});
            push @out, sprintf(
                '<rect x="%d" y="%d" width="%d" height="%d" fill="%s"/>',
                $x, $py->($o->{b}), P($s,$o->{c}), P($s,$o->{d}), $fill);
        }
        elsif ($t eq 'OP_TRI') {
            push @out, sprintf(
                '<polygon points="%d,%d %d,%d %d,%d" fill="var(--fg)"/>',
                $px->($o->{a}), $py->($o->{b}),
                $px->($o->{c}), $py->($o->{d}),
                $px->($o->{e}), $py->($o->{f}));
        }
        elsif ($t eq 'OP_LINE') {
            # The firmware builds this stroke from parallel copies offset in x.
            # Reproduced literally: a single SVG stroke would be thinner on the
            # diagonal than what the panel actually draws.
            my $w = P($s, $o->{e});
            my ($x0,$y0) = ($px->($o->{a}), $py->($o->{b}));
            my ($x1,$y1) = ($px->($o->{c}), $py->($o->{d}));
            for my $i (-int($w/2) .. int($w/2)) {
                push @out, sprintf(
                    '<line x1="%d" y1="%d" x2="%d" y2="%d" stroke="var(--fg)" stroke-width="1"/>',
                    $x0+$i, $y0, $x1+$i, $y1);
            }
        }
        elsif ($t eq 'OP_CIRC') {
            push @out, sprintf('<circle cx="%d" cy="%d" r="%d" fill="var(--fg)"/>',
                $px->($o->{a}), $py->($o->{b}), P($s,$o->{c}));
        }
        elsif ($t eq 'OP_RING') {
            my ($cx,$cy,$r) = ($px->($o->{a}), $py->($o->{b}), P($s,$o->{c}));
            for my $k (0 .. P($s,$o->{d}) - 1) {
                push @out, sprintf(
                    '<circle cx="%d" cy="%d" r="%d" fill="none" stroke="var(--fg)" stroke-width="1"/>',
                    $cx, $cy, $r - $k);
            }
        }
        elsif ($t eq 'OP_ARC') {
            my $rp  = $o->{c};
            my $dot = P($s, $o->{d});
            my $STEPS = 24;
            for my $i (0 .. $STEPS) {
                my $deg = $o->{e} + ($o->{f} - $o->{e}) * $i / $STEPS;
                my $rad = $deg * 3.14159265 / 180.0;
                push @out, sprintf('<circle cx="%d" cy="%d" r="%d" fill="var(--fg)"/>',
                    $pxf->($o->{a} - $rp * cos($rad)),
                    $pyf->($o->{b} - $rp * sin($rad)), $dot);
            }
        }
    }
    return join "\n      ", @out;
}

# ---------------------------------------------------------------- emit

my @SIZES = (104, 84);

print <<'HEAD';
<title>JiffyTrails Glyphs</title>
<style>
  :root{ --fg:#000; --bg:#fff; --ink:#E4E8EB; --dim:#98A2AA; --rule:#2C3237; --panel:#191D21; }
  body{margin:0;background:#101316;color:var(--ink);
       font:14px/1.5 "IBM Plex Sans",system-ui,sans-serif}
  .wrap{max-width:1200px;margin:0 auto;padding:2rem 1.25rem 4rem}
  h1{font-size:1.5rem;margin:0 0 .3rem}
  p.sub{color:var(--dim);margin:0 0 2rem;font-size:.9rem}
  h2{font-size:.75rem;letter-spacing:.12em;text-transform:uppercase;color:#FF8A00;
     margin:2rem 0 .8rem;border-bottom:1px solid var(--rule);padding-bottom:.4rem}
  .grid{display:grid;grid-template-columns:repeat(auto-fill,minmax(150px,1fr));gap:.9rem}
  .cell{background:var(--panel);border:1px solid var(--rule);border-radius:3px;overflow:hidden}
  .art{background:#fff;display:flex;align-items:center;justify-content:center;padding:10px;gap:12px}
  .art svg{display:block;outline:1px dashed #CBD2D8}
  .lbl{font:11px/1.4 ui-monospace,Menlo,monospace;padding:.45rem .55rem;color:var(--dim);
       border-top:1px solid var(--rule);word-break:break-all}
  .lbl b{color:var(--ink);font-weight:600}
</style>
<div class="wrap">
<h1>Maneuver glyph contact sheet</h1>
<p class="sub">Parsed from <code>firmware/navigator/glyph_data.h</code> and drawn with the same
arithmetic <code>maneuvers.cpp</code> uses, integer truncation included.
Left column 104&nbsp;px (committed / turn-now), right column 84&nbsp;px (far band).
The dashed outline is the glyph box &mdash; nothing may cross it.</p>
<div class="grid">
HEAD

for my $e (@entries) {
    my $ops = $glyph{$e->{glyph}} or next;
    my $art = '';
    for my $s (@SIZES) {
        $art .= sprintf('<svg width="%d" height="%d" viewBox="0 0 %d %d">%s</svg>',
            $s, $s, $s, $s, "\n      " . render($ops, $s, $e->{mirror}) . "\n    ");
    }
    my $code = $e->{code}; $code =~ s/^MV_//;
    printf "  <div class=\"cell\"><div class=\"art\">%s</div><div class=\"lbl\"><b>%s</b><br>%s%s</div></div>\n",
        $art, $code, $e->{glyph}, ($e->{mirror} ? ' &middot; mirrored' : '');
}

print "</div>\n";

# A dedicated row for the roundabout-with-exit case, which maneuvers.cpp draws
# as ring + entry + a digit rather than from a single table.
print <<'MID';
<h2>Roundabout with a known exit</h2>
<p class="sub" style="margin-bottom:1rem">Ring and entry come from <code>G_ROUNDABOUT</code>;
the digit replaces the exit arrow because the exit ANGLE is not derivable from the code.
The digit is drawn by <code>maneuvers.cpp</code>, not the table, so it is sketched here only
for position &mdash; font metrics do not scale with the box.</p>
<div class="grid">
MID

for my $n (1, 2, 3, 5) {
    my $ops = $glyph{'G_ROUNDABOUT'};
    my $art = '';
    for my $s (@SIZES) {
        my $b = mk($s, 0);
        my $dx = $b->{px}->(82); my $dy = $b->{py}->(44);
        my $fs = $s >= 88 ? 26 : 16;
        $art .= sprintf('<svg width="%d" height="%d" viewBox="0 0 %d %d">%s'
            . '<text x="%d" y="%d" text-anchor="middle" dominant-baseline="central"'
            . ' font-family="system-ui" font-size="%d" fill="var(--fg)">%d</text></svg>',
            $s, $s, $s, $s, "\n      " . render($ops, $s, 0) . "\n    ", $dx, $dy, $fs, $n);
    }
    printf "  <div class=\"cell\"><div class=\"art\">%s</div><div class=\"lbl\"><b>ROUNDABOUT_EXIT_%d</b><br>G_ROUNDABOUT + digit</div></div>\n", $art, $n;
}

print "</div>\n</div>\n";
