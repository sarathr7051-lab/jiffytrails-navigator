/*
  glyph_data.h - maneuver artwork as data.

  Every glyph is a list of primitive ops in percent-of-box coordinates, so a
  glyph drawn into an s-by-s box at (x, y) can never escape it. This replaces
  the switch statement that lived in maneuvers.cpp, for three reasons:

    1. **It can be rendered off the bike.** tools/render_glyphs.pl parses THIS
       FILE and emits an SVG contact sheet. That is the whole point: the last
       three layout bugs on this project were found by looking at hardware, and
       every one of them was arithmetic that a picture would have caught in
       seconds. A table both the firmware and a renderer read is one source of
       truth; a renderer that re-implements the geometry is just a second place
       to be wrong.

    2. **Left is mirrored, not duplicated.** Every left-hand glyph in the old
       switch was already an exact mirror of its right-hand twin - verified
       percentage by percentage during the port. Saying so once removes the
       possibility of a left/right pair drifting apart, which on a motorcycle
       is the single worst bug this display can have.

    3. Adding a maneuver is a table edit rather than a code edit.

  COORDINATES. 0-100 in both axes, x right, y down, relative to the box.
  Mirroring maps x -> 100 - x, and for rectangles x -> 100 - x - w, because
  fillRect always grows in +x.

  ANGLES. OP_ARC sweeps a parameter t from a0 to a1 degrees and plots
  (cx - r*cos t, cy - r*sin t), so 0-180 is the top half, left to right. That
  is the arithmetic the U-turn was drawn with on hardware; it is kept exactly.

  The ops are deliberately few. Anything needing text - the roundabout exit
  number, the "?" of MV_UNKNOWN - stays in maneuvers.cpp, because font metrics
  are not geometry and do not scale with the box.
*/

#pragma once
#include <stdint.h>

enum : uint8_t {
  OP_END = 0,
  OP_RECT,      // a=x  b=y  c=w  d=h
  OP_TRI,       // a,b  c,d  e,f  - three vertices
  OP_LINE,      // a,b -> c,d, stroke width e (vertical-offset stroke)
  OP_CIRC,      // a=cx b=cy c=r          filled
  OP_RING,      // a=cx b=cy c=r  d=thickness
  OP_ARC,       // a=cx b=cy c=r  d=dot radius  e=from deg  f=to deg
  OP_RECT_BG,   // as OP_RECT but in the background colour - punches a gap
};

struct GlyphOp { uint8_t op; int16_t a, b, c, d, e, f; };

/*
  A note on the arrowheads. Every head is a triangle whose tip is the first
  vertex and whose base is the other two, and every stroke that feeds a head
  ends *inside* it rather than at its base. Overlap is deliberate: a stroke
  that stops exactly on the base leaves a hairline of background between them
  at some box sizes, because the two shapes round their edges independently.
*/

// ---------------------------------------------------------------- unchanged
// These six are ui_mock's, validated on the panel, transcribed digit for
// digit. Do not "tidy" the numbers - they were judged at mount distance.

static const GlyphOp G_CONTINUE[] = {
  { OP_RECT, 42, 35, 16, 60,  0,  0 },
  { OP_TRI,  24, 40, 76, 40, 50,  6 },
  { OP_END,   0,  0,  0,  0,  0,  0 },
};

static const GlyphOp G_TURN[] = {
  { OP_RECT, 24, 46, 15, 50,  0,  0 },   // stem, up from the bottom edge
  { OP_RECT, 24, 46, 44, 15,  0,  0 },   // elbow, out to the right
  { OP_TRI,  96, 53, 62, 28, 62, 79 },   // head, pointing right
  { OP_END,   0,  0,  0,  0,  0,  0 },
};

static const GlyphOp G_SLIGHT[] = {
  { OP_RECT, 42, 58, 15, 38,  0,  0 },
  { OP_LINE, 50, 62, 74, 34, 15,  0 },
  { OP_TRI,  88, 14, 58, 24, 78, 48 },
  { OP_END,   0,  0,  0,  0,  0,  0 },
};

static const GlyphOp G_UTURN[] = {
  { OP_ARC,  50, 42, 22,  7,  0, 180 },  // the turn itself
  { OP_RECT, 21, 42, 14, 54,  0,  0 },   // entry leg, to the bottom edge
  { OP_RECT, 65, 42, 14, 22,  0,  0 },   // exit leg, stops at the head
  { OP_TRI,  72, 92, 58, 60, 86, 60 },   // head, pointing down
  { OP_END,   0,  0,  0,  0,  0,  0 },
};

static const GlyphOp G_MERGE[] = {
  { OP_RECT, 42, 30, 15, 66,  0,  0 },
  { OP_TRI,  50,  4, 25, 34, 75, 34 },
  { OP_LINE, 16, 94, 44, 64, 11,  0 },   // the lane joining from the left
  { OP_END,   0,  0,  0,  0,  0,  0 },
};

static const GlyphOp G_DESTINATION[] = {
  { OP_RECT, 28, 10,  8, 84,  0,  0 },   // pole
  { OP_TRI,  82, 30, 36, 12, 36, 48 },   // pennant
  { OP_END,   0,  0,  0,  0,  0,  0 },
};

static const GlyphOp G_ROUNDABOUT[] = {
  { OP_RING, 45, 44, 24, 10,  0,  0 },
  { OP_RECT, 40, 66, 10, 30,  0,  0 },   // entry, from the bottom edge
  { OP_END,   0,  0,  0,  0,  0,  0 },
};

// Ring plus entry plus the generic exit stub. Only used when no exit number is
// known; with a number, G_ROUNDABOUT is drawn and the digit replaces the stub,
// because "take the 3rd exit" with an arrow pointing right is a confident lie.
static const GlyphOp G_ROUNDABOUT_EXIT[] = {
  { OP_RING, 45, 44, 24, 10,  0,  0 },
  { OP_RECT, 40, 66, 10, 30,  0,  0 },
  { OP_RECT, 67, 39, 18, 10,  0,  0 },
  { OP_TRI,  97, 44, 82, 32, 82, 56 },
  { OP_END,   0,  0,  0,  0,  0,  0 },
};

// ------------------------------------------------------------------ new
// Six maneuvers used to share the SLIGHT and TURN glyphs. The approximations
// were honest - they never pointed the wrong way - but they threw away the one
// thing the rider actually needed at a Bengaluru flyover: whether the road
// splits, and whether you are leaving it. These are drawn properly now.

/*
  FORK / KEEP. Both branches are drawn, so the glyph says "the road divides"
  rather than "bear right". The branch not taken is a thinner stroke with no
  head - weight, not colour, carries the meaning, because at 1.2:1 contrast in
  sunlight a grey stroke is not reliably distinguishable from a black one.

  FORK and KEEP deliberately share this artwork. They are the same picture in
  every icon set worth copying, and inventing a difference the rider would have
  to learn is worse than admitting there isn't one.
*/
static const GlyphOp G_FORK[] = {
  { OP_RECT, 43, 74, 15, 22,  0,  0 },   // shared stem
  { OP_LINE, 48, 78, 27, 42,  9,  0 },   // branch not taken - thin, headless
  { OP_LINE, 51, 78, 74, 34, 15,  0 },   // branch taken
  { OP_TRI,  88, 14, 58, 24, 78, 48 },   // same head as SLIGHT, on purpose
  { OP_END,   0,  0,  0,  0,  0,  0 },
};

/*
  EXIT / RAMP - "get off the highway".

  The main road runs the full height of the box and keeps no arrowhead: it is
  scenery, not instruction. The ramp peels off it and carries the head. This is
  the one glyph the rider asked for by name, and it is the one case where the
  old approximation genuinely misled - a slight-right arrow says "the road
  bends"; this says "leave it".
*/
static const GlyphOp G_EXIT[] = {
  { OP_RECT, 31,  4, 12, 92,  0,  0 },   // the road you are leaving
  { OP_LINE, 43, 70, 70, 38, 15,  0 },   // the ramp
  { OP_TRI,  86, 16, 56, 26, 78, 50 },
  { OP_END,   0,  0,  0,  0,  0,  0 },
};

/*
  SHARP. More than ninety degrees: up, then back down to the side. The old
  approximation drew the ordinary TURN glyph, which understated the angle - safe,
  but at a Bengaluru junction the difference between a right turn and a hairpin
  is the difference between one road and another.
*/
static const GlyphOp G_SHARP[] = {
  { OP_RECT, 24, 44, 15, 52,  0,  0 },   // stem, up from the bottom edge
  { OP_LINE, 31, 50, 62, 70, 15,  0 },   // and back down to the right
  { OP_TRI,  86, 92, 80, 54, 48, 86 },   // head, pointing down-right at 45
  { OP_END,   0,  0,  0,  0,  0,  0 },
};

/*
  FLYOVER and UNDERPASS are the same drawing with the gap moved. Whichever road
  is broken is the one passing underneath - the universal convention, and the
  only way to show depth on a panel with two colours and no shading.

  NAV_DATA.md records that Maps emits no flyover-specific icon, so these codes
  can only arrive from a source with clearer semantics than Maps. They are drawn
  rather than "?" now because the protocol defines them; if nothing ever sends
  them, nothing is lost.
*/
static const GlyphOp G_FLYOVER[] = {
  { OP_RECT,     4, 54, 92, 14,  0,  0 },  // the crossing road
  { OP_RECT_BG, 34, 48, 32, 26,  0,  0 },  // ...broken where we pass over it
  { OP_RECT,    43,  8, 14, 88,  0,  0 },  // our road, continuous
  { OP_TRI,     50,  2, 28, 26, 72, 26 },
  { OP_END,      0,  0,  0,  0,  0,  0 },
};

static const GlyphOp G_UNDERPASS[] = {
  // Both segments run right up to the crossing bar rather than stopping short:
  // the road must vanish AT the bar, not a few percent before it, or the gap
  // reads as two unrelated stubs instead of one road passing beneath.
  { OP_RECT, 43, 68, 14, 28,  0,  0 },   // our road, below the crossing
  { OP_RECT, 43, 20, 14, 34,  0,  0 },   // ...and above it. Broken between
  { OP_TRI,  50,  2, 28, 26, 72, 26 },
  { OP_RECT,  4, 54, 92, 14,  0,  0 },   // the crossing road, continuous
  { OP_END,   0,  0,  0,  0,  0,  0 },
};

/*
  FERRY. Not an arrow at all, and that is the point - "drive straight ahead" is
  not what a ferry leg asks of the rider. A boat says stop, queue, and wait.
*/
static const GlyphOp G_FERRY[] = {
  { OP_TRI,  14, 58, 86, 58, 76, 80 },   // hull, upper half
  { OP_TRI,  14, 58, 76, 80, 24, 80 },   // hull, lower half
  { OP_RECT, 47, 22,  6, 36,  0,  0 },   // mast
  { OP_TRI,  53, 24, 80, 38, 53, 52 },   // sail
  { OP_RECT,  6, 88, 88,  8,  0,  0 },   // water
  { OP_END,   0,  0,  0,  0,  0,  0 },
};

// ------------------------------------------------------------------ table
//
// `mirror` reflects the glyph about the box centre. Every left-hand maneuver
// is its right-hand twin mirrored - never its own artwork - so the pair cannot
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
