// ---------------------------------------------------------------------------
// GENERATED COPY - DO NOT EDIT.
//
// Source of truth: firmware/navigator/maneuvers.cpp
// Regenerate:      perl tools/sync_ui_mock.pl
//
// arduino-cli and the Arduino IDE both copy a sketch before compiling it, so
// this sketch cannot #include across to firmware/navigator/. This file is a
// verbatim copy. Edit the original; `perl tools/sync_ui_mock.pl --check` fails
// if the two have diverged.
// ---------------------------------------------------------------------------
/*
  maneuvers.cpp - draws the glyph tables in glyph_data.h.

  This file used to be a switch statement with the geometry inline. The
  geometry moved to glyph_data.h so that tools/render_glyphs.pl can parse the
  same numbers and produce an SVG contact sheet without an ESP32 in the loop.
  That matters more than it sounds: every layout bug this project has shipped
  was arithmetic, every one was found by squinting at the panel, and none was
  found by review. A picture on a laptop finds them in seconds.

  What is left here is the interpreter, the mirroring rule, and the two things
  that are not geometry - the roundabout's exit digit and MV_UNKNOWN's "?" -
  because font metrics do not scale with the box and never belonged in a table.

  MIRRORING. Left-hand glyphs are their right-hand twins reflected about the
  box centre; glyph_data.h explains why. Reflection is applied to percentages
  before they become pixels, so a mirrored arc and a mirrored rectangle agree
  with each other by construction rather than by two separate hand-derived sets
  of numbers - which is exactly how a left/right pair drifts apart.

  One inherited bug worth keeping a note of: ui_mock drew the "?" in font 6.
  Font 6 (Font64rle) carries only "1234567890:-.apm" - '?' has a width table
  entry but a blank glyph, so MV_UNKNOWN drew nothing at all on hardware. It is
  font 4 here, doubled in the larger boxes, because font 4 (Font32rle) is the
  largest full-ASCII font in the library.
*/

#include <TFT_eSPI.h>
#include "maneuvers.h"
#include "nav_types.h"
#include "glyph_data.h"

// How many dots make an arc. 24 was enough at the 104 px box and is still
// enough at 64: the dots are P(7) across and overlap heavily at both sizes.
static const int ARC_STEPS = 24;

namespace {

// Percent-of-box to pixels, with the mirror applied while the number is still
// a percentage. Every coordinate in a glyph goes through exactly one of these.
struct Box {
  int x, y, s;
  bool mirror;

  int p(int pct)  const { return (int)((long)pct * s / 100); }
  int px(int pct) const { return x + p(mirror ? 100 - pct : pct); }
  int py(int pct) const { return y + p(pct); }

  // Floats for the arc, which lands between percentages by nature.
  int pxf(float pct) const { return x + (int)((mirror ? 100.0f - pct : pct) * s / 100.0f); }
  int pyf(float pct) const { return y + (int)(pct * s / 100.0f); }

  // fillRect always grows in +x, so a mirrored rectangle starts at what was
  // its right edge. Getting this wrong shifts a mirrored glyph by its own
  // width, which reads as "the left arrow is off centre" rather than as a bug.
  int rectX(int pct, int w) const { return px(mirror ? pct + w : pct); }
};

void runOps(TFT_eSPI& tft, const Box& b, const GlyphOp* ops,
            uint16_t fg, uint16_t bg) {
  for (const GlyphOp* o = ops; o->op != OP_END; ++o) {
    switch (o->op) {
      case OP_RECT:
      case OP_RECT_BG:
        tft.fillRect(b.rectX(o->a, o->c), b.py(o->b), b.p(o->c), b.p(o->d),
                     (o->op == OP_RECT_BG) ? bg : fg);
        break;

      case OP_TRI:
        tft.fillTriangle(b.px(o->a), b.py(o->b),
                         b.px(o->c), b.py(o->d),
                         b.px(o->e), b.py(o->f), fg);
        break;

      case OP_LINE: {
        /*
          A stroke built from parallel copies offset in x.

          ★ The operand is NOT a perpendicular width. Offsetting along x gives
          w_perp = e * |sin t| for a stroke at angle t to the horizontal, so at
          45 degrees it draws 0.707 e. Every diagonal in the glyph set was once
          written e=15 to match the 15-wide rectangles beside it and drew 10.6.
          glyph_data.h now uses D=23 and Dt=14 for that reason; read the note
          there before writing a new OP_LINE.

          It is still correct enough for strokes that are never near-horizontal,
          and none in this set are - every one is exactly 45 degrees.
        */
        const int w = b.p(o->e);
        const int x0 = b.px(o->a), y0 = b.py(o->b);
        const int x1 = b.px(o->c), y1 = b.py(o->d);
        for (int i = -w / 2; i <= w / 2; i++) tft.drawLine(x0 + i, y0, x1 + i, y1, fg);
        break;
      }

      case OP_CIRC:
        tft.fillCircle(b.px(o->a), b.py(o->b), b.p(o->c), fg);
        break;

      case OP_RING: {
        const int cx = b.px(o->a), cy = b.py(o->b), r = b.p(o->c);
        for (int k = 0; k < b.p(o->d); k++) tft.drawCircle(cx, cy, r - k, fg);
        break;
      }

      case OP_ARC: {
        // Overlapping dots rather than stacked circle outlines with the lower
        // half erased - erasing clipped the legs that meet the arc.
        const float rp = (float)o->c;
        const int   dot = b.p(o->d);
        for (int i = 0; i <= ARC_STEPS; i++) {
          const float t = (o->e + (o->f - o->e) * (float)i / ARC_STEPS) * 3.14159265f / 180.0f;
          tft.fillCircle(b.pxf(o->a - rp * cosf(t)),
                         b.pyf(o->b - rp * sinf(t)), dot, fg);
        }
        break;
      }

      default: break;
    }
  }
}

const GlyphEntry* lookup(uint8_t maneuver) {
  for (uint8_t i = 0; i < GLYPH_COUNT; i++) {
    if (GLYPHS[i].code == maneuver) return &GLYPHS[i];
  }
  return nullptr;
}

}  // namespace

void drawManeuver(TFT_eSPI& tft, int x, int y, int s,
                  uint8_t maneuver, uint16_t fg, uint16_t bg) {
  Box b{x, y, s, false};

  /*
    Roundabouts with a known exit get the ring, the entry, and the NUMBER where
    the generic exit arrow would have been. The exit angle is not derivable from
    the code - real roundabouts are not evenly spaced - so an arrow pointing
    right for "take the 3rd exit" would be a confidently wrong instruction,
    which BLE_PROTOCOL.md forbids. The number is the only honest thing to draw.
  */
  if (maneuver > MV_ROUNDABOUT_EXIT_BASE &&
      maneuver <= MV_ROUNDABOUT_EXIT_BASE + 0x0F) {
    runOps(tft, b, G_ROUNDABOUT, fg, bg);
    char n[4];
    snprintf(n, sizeof(n), "%d", maneuver - MV_ROUNDABOUT_EXIT_BASE);
    tft.setTextColor(fg, bg);
    tft.setTextDatum(MC_DATUM);
    // Font 4 digits are 26 px tall and that is absolute, not scaled with the
    // box. In the 64 px far-band box a font-4 digit would touch the ring.
    // On the ring's exit axis and its centre line. Moved from (82,44) when the
    // ring was resized to match the head width - see SPEC_MANEUVER_ICONS.md.
    tft.drawString(n, b.px(78), b.py(40), (s >= 88) ? 4 : 2);
    return;
  }

  const GlyphEntry* g = lookup(maneuver);
  if (g) {
    b.mirror = g->mirror;
    runOps(tft, b, g->ops, fg, bg);
    return;
  }

  // MV_UNKNOWN, MV_ROUNDABOUT_EXIT_BASE itself, and anything the phone invents.
  // Never guess an arrow - say so instead.
  tft.setTextColor(fg, bg);
  tft.setTextDatum(MC_DATUM);
  tft.setTextSize((s >= 88) ? 2 : 1);
  tft.drawString("?", b.px(50), b.py(50), 4);
  tft.setTextSize(1);
}
