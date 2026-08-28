/*
  glyph_data.h - maneuver artwork as data.

  Every glyph is a list of primitive ops in percent-of-box coordinates, so a
  glyph drawn into an s-by-s box at (x, y) can never escape it. The tables live
  here rather than in a switch statement for three reasons:

    1. **They can be rendered off the bike.** tools/ascii_glyphs.pl parses THIS
       FILE and emits a contact sheet. Every layout bug this project has
       shipped was arithmetic, and none was found by review.
    2. **Left is mirrored, not duplicated**, so a left/right pair cannot drift
       apart - on a motorcycle the worst bug this display can have.
    3. Adding a maneuver is a table edit rather than a code edit.

  COORDINATES. 0-100 in both axes, x right, y down, relative to the box.
  Mirroring maps x -> 100 - x, and for rectangles x -> 100 - x - w, because
  fillRect always grows in +x.

  ANGLES. OP_ARC sweeps a parameter t from a0 to a1 degrees and plots
  (cx - r*cos t, cy - r*sin t). The tangent at t=0 points straight up, at 135
  down-right at 45 degrees, at 180 straight down - so a single sweep IS a turn.

  ---------------------------------------------------------------------------
  THE SYSTEM. Derived in docs/SPEC_MANEUVER_ICONS.md against Material Symbols,
  Mapbox and OsmAnd, and against ISO 15008's legibility minima. Read that
  document before changing any number here; each one has arithmetic behind it.

    W   16   shaft width - your path
    Wt  10   thin width - a road that is not your path
    Hw  52   head width          Hw/W = 3.25, apex 74.8 deg
    Hl  34   head length
    V    6   head/shaft overlap - the shaft ends INSIDE the head, so no box
             size can open a hairline between them
    M    4   margin
    D   23   OP_LINE operand for a full-weight 45 deg stroke   (see below)
    Dt  14   ...and for a thin one

    turn angles         45 / 90 / 135 / 180
    entry centreline    Xe = 50 / 40 / 34 / 24 / 22 by angle
    optical centre      ink centroid (50,50), +-8 in x, +-6 in y

  W = 16 is not a preference. Three routes converge on it: the contrast
  sensitivity band at HARDWARE.md's measured 1.17:1 sunlight ACR wants ~13.7%;
  ISO 15008's 1:6 stroke-to-height ratio wants 14.7%; and 16% is 11.7 arc-min
  at the 84 px box, which sits on ISO 15008's 12 arc-min floor. Anything
  thinner is below it.

  ---------------------------------------------------------------------------
  ★ OP_LINE's operand is NOT a stroke width.

  maneuvers.cpp offsets the copies along x, so for a stroke at angle t to the
  horizontal the perpendicular width is e * |sin t|. At 45 degrees that is
  0.707 e.

  Every diagonal in the previous table was written e=15 to match the 15-wide
  rectangles beside it, and every one of them actually drew 10.6 - a 30% thin
  stroke sitting next to a full one, in five glyphs at once. That was the
  largest single cause of the inconsistent stroke weights visible on the panel,
  and it was invisible in review because the number in the table said 15.

  ascii_glyphs.pl reproduces the same arithmetic, so it does not catch this
  either. It is faithful, not wrong.

  Hence D = 23: 23 / sqrt(2) = 16.26 = W. Thin diagonals use Dt = 14 -> 9.9.

  A 45 deg stroke of perpendicular width 16 has an x-extent of 22.6, so butting
  it on a leg's centreline would hang 3.3 units past the leg on both sides.
  Every diagonal therefore starts at Xe+3 (Xe+1 for a thin branch), which puts
  its edge flush with the leg's to within half a unit.
*/

#pragma once
#include <stdint.h>

enum : uint8_t {
  OP_END = 0,
  OP_RECT,      // a=x  b=y  c=w  d=h
  OP_TRI,       // a,b  c,d  e,f  - three vertices
  OP_LINE,      // a,b -> c,d, operand e - see the note above, NOT a width
  OP_CIRC,      // a=cx b=cy c=r          filled
  OP_RING,      // a=cx b=cy c=r  d=thickness
  OP_ARC,       // a=cx b=cy c=r  d=dot radius  e=from deg  f=to deg
  OP_RECT_BG,   // as OP_RECT but in the background colour - punches a gap
};

struct GlyphOp { uint8_t op; int16_t a, b, c, d, e, f; };

// ---------------------------------------------------------------- straight

// Shaft foot on the bottom margin, tip on the top. Centroid (50.0, 47.3).
static const GlyphOp G_CONTINUE[] = {
  { OP_RECT, 42, 32, 16, 64,  0,  0 },
  { OP_TRI,  50,  4, 24, 38, 76, 38 },
  { OP_END,   0,  0,  0,  0,  0,  0 },
};

// ------------------------------------------------------------------- turns

/*
  90 degrees. Pivot at (Xe, Xe) = (34,34), which makes the entry leg and the
  exit arm the same length. Bounding-box centre x = 61 against Material's
  turn_right at 58.3: the glyph leans right, which is the instruction.
*/
static const GlyphOp G_TURN[] = {
  { OP_RECT, 26, 34, 16, 62,  0,  0 },   // entry leg, foot on the margin
  { OP_RECT, 26, 26, 42, 16,  0,  0 },   // exit arm, pivot to inside the head
  { OP_TRI,  96, 34, 62,  8, 62, 60 },   // head, tip on the right margin
  { OP_END,   0,  0,  0,  0,  0,  0 },
};

/*
  45 degrees - OsmAnd's literal, Material's exact dx=dy, Mapbox's 40.9.
  The exit axis is x + y = 98; the head tip and both diagonal endpoints satisfy
  it, which is the arithmetic check on this glyph.
*/
static const GlyphOp G_SLIGHT[] = {
  { OP_RECT, 32, 55, 16, 41,  0,  0 },
  { OP_LINE, 43, 55, 70, 28, 23,  0 },   // e=D, not W - see the header
  { OP_TRI,  88, 10, 46, 16, 82, 52 },
  { OP_END,   0,  0,  0,  0,  0,  0 },
};

/*
  135 degrees, drawn as a genuine reversal: up, round a hairpin, back down.

  The arc is not decoration. A square knee rendered as a solid triangular wedge
  20 units tall - the inner corner filled in completely and the hairpin stopped
  reading as a hairpin. r=18 with a dot radius of 8 leaves an inner radius of
  10, i.e. 8.4 px of open background at the 84 px box.

  Material Symbols' turn_sharp_right is deliberately NOT the model: its arrow
  ends pointing north, which is a lane shift rather than a 135 degree turn.
  Mapbox and OsmAnd both draw a real reversal. Exit axis is x - y = 27.
*/
static const GlyphOp G_SHARP[] = {
  { OP_RECT, 16, 40, 16, 56,  0,  0 },
  { OP_ARC,  42, 40, 18,  8,  0, 135 },
  { OP_LINE, 55, 28, 72, 45, 23,  0 },
  { OP_TRI,  92, 65, 50, 59, 86, 23 },
  { OP_END,   0,  0,  0,  0,  0,  0 },
};

/*
  180 degrees. The arc's endpoints at t=0 and t=180 ARE the two leg centrelines,
  so the joints are exact by construction rather than by matching two sets of
  hand-derived numbers.
*/
static const GlyphOp G_UTURN[] = {
  { OP_RECT, 14, 36, 16, 60,  0,  0 },   // entry leg, foot on the margin
  { OP_ARC,  46, 36, 24,  8,  0, 180 },  // the turn itself
  { OP_RECT, 62, 36, 16, 28,  0,  0 },   // exit leg, stops inside the head
  { OP_TRI,  70, 92, 44, 58, 96, 58 },   // head, pointing down
  { OP_END,   0,  0,  0,  0,  0,  0 },
};

// -------------------------------------------------------- splits and ramps

/*
  Both branches leave the split at 45 degrees in opposite directions, so the
  fork is symmetric in angle and asymmetric only in WEIGHT - which is exactly
  the information. The branch not taken is thin and headless.

  FORK and KEEP share this artwork deliberately: they are the same picture in
  every icon set worth copying, and inventing a difference the rider would have
  to learn is worse than admitting there isn't one.
*/
static const GlyphOp G_FORK[] = {
  { OP_RECT, 34, 62, 16, 34,  0,  0 },   // shared stem
  { OP_LINE, 43, 62, 14, 33, 14,  0 },   // not taken - thin, headless
  { OP_LINE, 45, 62, 72, 35, 23,  0 },   // taken
  { OP_TRI,  92, 15, 50, 21, 86, 57 },   // same head as SLIGHT, on purpose
  { OP_END,   0,  0,  0,  0,  0,  0 },
};

/*
  The road being left runs margin to margin at Wt and carries no head - it is
  scenery, not instruction. The ramp peels off it and carries the arrow.

  The split is at y=73, so 23 units of road continue below it. That is the whole
  message of the glyph - the road goes on without you - and it is why the ramp
  does not start at the top.
*/
static const GlyphOp G_EXIT[] = {
  { OP_RECT, 30,  4, 10, 92,  0,  0 },
  { OP_LINE, 41, 73, 70, 44, 23,  0 },
  { OP_TRI,  90, 24, 48, 30, 84, 66 },
  { OP_END,   0,  0,  0,  0,  0,  0 },
};

/*
  Your road runs straight through with the standard head; a lane joins from the
  lower left at Wt, because you do not ride it.

  The shaft centreline is 58, not 50. The joining lane is ~620 units of ink
  entirely on the left, and centring the shaft would put the centroid at x=36.

  Material draws merge symmetrically, as a Y with two equal legs. That is right
  for a road atlas and wrong here: this display tells ONE rider what to do, and
  "the road you are on continues, something joins it" is a different instruction
  from "two roads become one". The asymmetry is the message.
*/
static const GlyphOp G_MERGE[] = {
  { OP_RECT, 50, 32, 16, 64,  0,  0 },
  { OP_TRI,  58,  4, 32, 38, 84, 38 },
  { OP_LINE, 12, 96, 56, 52, 14,  0 },
  { OP_END,   0,  0,  0,  0,  0,  0 },
};

// ------------------------------------------------------------- roundabouts

/*
  Ring thickness is 12, not W, and the reason is the hole. OP_RING draws radii
  [r-t, r], so at r=26 a 16-thick ring leaves an inner radius of 10 - a 17 px
  white disc at the 84 px box, shrinking further as the stroke bleeds. At t=12
  the inner radius is 14, a 23.5 px disc. The enclosed white is what makes a
  ring read as a roundabout rather than as a blob: this is the one glyph where
  the SHAPE, not the stroke, is the feature.

  Ring diameter is 52 - the same as Hw. An earlier draft used a 48 ring beside a
  52 head and the arrow visibly dominated the roundabout.

  Two tables, identical but for the exit stub, so the ring does not jump between
  frames when an exit number appears or disappears.
*/

// Drawn when the exit NUMBER is known; maneuvers.cpp puts the digit where the
// stub would have been, because "take the 3rd exit" with an arrow pointing
// right is a confidently wrong instruction.
static const GlyphOp G_ROUNDABOUT[] = {
  { OP_RING, 32, 40, 26, 12,  0,  0 },
  { OP_RECT, 24, 56, 16, 40,  0,  0 },   // entry, from the bottom margin
  { OP_END,   0,  0,  0,  0,  0,  0 },
};

static const GlyphOp G_ROUNDABOUT_EXIT[] = {
  { OP_RING, 32, 40, 26, 12,  0,  0 },
  { OP_RECT, 24, 56, 16, 40,  0,  0 },
  { OP_RECT, 52, 32, 16, 16,  0,  0 },   // stub, ring edge into the head
  { OP_TRI,  96, 40, 62, 14, 62, 66 },
  { OP_END,   0,  0,  0,  0,  0,  0 },
};

// ------------------------------------------------------------------- depth

/*
  The same drawing with the gap moved; whichever road is broken is the one
  passing underneath. Our road is G_CONTINUE unchanged, which is the point - a
  flyover is a continue-straight with depth attached, and the rider should read
  the arrow first and the depth second.

  The crossing bar is W, not Wt, and this is the set's one deliberate exception
  to "a road that is not your path is thin". In G_UNDERPASS the break in OUR
  road is exactly the bar's thickness, and that break is the entire message. At
  16 the gap is 11.7 arc-min at the 84 px box, on ISO 15008's floor; at Wt it
  would be 7.3 and the underpass would silently become a continue-straight in
  sunlight. The crossing road is a landmark here, not an alternative route.
*/
static const GlyphOp G_FLYOVER[] = {
  { OP_RECT,     4, 48, 92, 16,  0,  0 },
  { OP_RECT_BG, 34, 46, 32, 20,  0,  0 },  // 2 units of overshoot each end, so
  { OP_RECT,    42, 32, 16, 64,  0,  0 },  // no box size leaves a hairline
  { OP_TRI,     50,  4, 24, 38, 76, 38 },
  { OP_END,      0,  0,  0,  0,  0,  0 },
};

static const GlyphOp G_UNDERPASS[] = {
  // Both segments run right up to the bar. The road must vanish AT it, not a
  // few percent before, or the gap reads as two unrelated stubs.
  { OP_RECT, 42, 32, 16, 16,  0,  0 },
  { OP_RECT, 42, 64, 16, 32,  0,  0 },
  { OP_TRI,  50,  4, 24, 38, 76, 38 },
  { OP_RECT,  4, 48, 92, 16,  0,  0 },   // crossing road, continuous
  { OP_END,   0,  0,  0,  0,  0,  0 },
};

// ------------------------------------------------------------------ others

/*
  Not an arrow, and that is the point: "drive straight ahead" is not what a
  ferry leg asks of the rider.

  A sailboat rather than a ro-ro silhouette on purpose. A modern ferry outline
  is a box with a superstructure, and at 84 px through a visor a box with a
  superstructure is a truck. Nothing else in this set is a triangle over a
  trapezoid, so this glyph is unconfusable.

  The hull is one convex quad split on its diagonal, which tiles exactly with no
  seam and no double-fill.
*/
static const GlyphOp G_FERRY[] = {
  { OP_TRI,  10, 44, 90, 44, 76, 66 },   // hull, upper half
  { OP_TRI,  10, 44, 76, 66, 24, 66 },   // hull, lower half
  { OP_RECT, 45, 10, 10, 34,  0,  0 },   // mast
  { OP_TRI,  55, 12, 84, 29, 55, 44 },   // sail
  { OP_RECT,  8, 76, 84, 10,  0,  0 },   // water, 10 below the keel
  { OP_END,   0,  0,  0,  0,  0,  0 },
};

/*
  The pennant is deliberately NOT the standard head. A pennant is longer than it
  is deep (1.09 here); a maneuver head is deeper than it is long (0.65). Making
  them the same shape would have the destination flag read as a right-turn arrow
  at a glance, which is the worst confusion available in this set.
*/
static const GlyphOp G_DESTINATION[] = {
  { OP_RECT, 30, 12, 10, 84,  0,  0 },   // pole, at Wt - it is not a road
  { OP_TRI,  88, 38, 40, 16, 40, 60 },
  { OP_END,   0,  0,  0,  0,  0,  0 },
};

// ------------------------------------------------------------------ table
//
// `mirror` reflects the glyph about the box centre. Every left-hand maneuver is
// its right-hand twin mirrored - never its own artwork - so the pair cannot
// drift apart in a later edit.

struct GlyphEntry { uint8_t code; const GlyphOp* ops; bool mirror; };

static const GlyphEntry GLYPHS[] = {
  { MV_CONTINUE,     G_CONTINUE,    false },
  { MV_TURN_RIGHT,   G_TURN,        false },
  { MV_TURN_LEFT,    G_TURN,        true  },
  { MV_SHARP_RIGHT,  G_SHARP,       false },
  { MV_SHARP_LEFT,   G_SHARP,       true  },
  { MV_SLIGHT_RIGHT, G_SLIGHT,      false },
  { MV_SLIGHT_LEFT,  G_SLIGHT,      true  },
  { MV_KEEP_RIGHT,   G_FORK,        false },
  { MV_KEEP_LEFT,    G_FORK,        true  },
  { MV_FORK_RIGHT,   G_FORK,        false },
  { MV_FORK_LEFT,    G_FORK,        true  },
  { MV_EXIT_RIGHT,   G_EXIT,        false },
  { MV_EXIT_LEFT,    G_EXIT,        true  },
  { MV_UTURN_RIGHT,  G_UTURN,       false },
  { MV_UTURN_LEFT,   G_UTURN,       true  },
  { MV_MERGE,        G_MERGE,       false },
  { MV_ROUNDABOUT,   G_ROUNDABOUT_EXIT, false },
  { MV_FLYOVER,      G_FLYOVER,     false },
  { MV_UNDERPASS,    G_UNDERPASS,   false },
  { MV_FERRY,        G_FERRY,       false },
  { MV_DESTINATION,  G_DESTINATION, false },
};

static const uint8_t GLYPH_COUNT = sizeof(GLYPHS) / sizeof(GLYPHS[0]);
