/*
  geom.cpp - draws the junction.

  Two things here are worth knowing before changing anything.

  CLIPPING IS NOT OPTIONAL. The glyph box sits directly left of the distance
  sprite, and the sprite is opaque. A road segment that ran a few pixels past
  the box edge would be painted over on the next distance push, which looks
  like the map flickering rather than like a clipping bug. Every segment is
  clipped to the box with Cohen-Sutherland before it is drawn.

  STROKES ARE PERPENDICULAR. maneuvers.cpp offsets its strokes horizontally,
  which is fine there because no glyph stroke is near-horizontal. Roads run in
  every direction, and a horizontally-offset stroke collapses to one pixel when
  the road is horizontal - which is exactly when it is a cross street and most
  needs to be visible.
*/

#include <TFT_eSPI.h>
#include "geom.h"

namespace {

GeomPt  pts[GEOM_MAX_PTS];
GeomWay ways[GEOM_MAX_WAYS];
uint8_t nPts = 0, nWays = 0;

// Committed view. Building writes the arrays above and only publishes counts
// here, so a transfer that dies half way cannot put a fragment on screen.
uint8_t  vPts = 0, vWays = 0;
uint32_t vAtMs = 0;
bool     vValid = false;

// ---------------------------------------------------------------- clipping

const uint8_t L = 1, R = 2, B = 4, T = 8;

uint8_t outcode(int x, int y, int x0, int y0, int x1, int y1) {
  uint8_t c = 0;
  if (x < x0) c |= L; else if (x > x1) c |= R;
  if (y < y0) c |= T; else if (y > y1) c |= B;
  return c;
}

// Cohen-Sutherland. Returns false if the segment is entirely outside.
bool clipSeg(int& ax, int& ay, int& bx, int& by,
             int x0, int y0, int x1, int y1) {
  uint8_t ca = outcode(ax, ay, x0, y0, x1, y1);
  uint8_t cb = outcode(bx, by, x0, y0, x1, y1);

  for (uint8_t guard = 0; guard < 8; guard++) {
    if (!(ca | cb))  return true;    // both inside
    if (ca & cb)     return false;   // both beyond the same edge

    const uint8_t c = ca ? ca : cb;
    int nx = 0, ny = 0;

    if (c & B)      { nx = ax + (bx - ax) * (y1 - ay) / (by - ay); ny = y1; }
    else if (c & T) { nx = ax + (bx - ax) * (y0 - ay) / (by - ay); ny = y0; }
    else if (c & R) { ny = ay + (by - ay) * (x1 - ax) / (bx - ax); nx = x1; }
    else            { ny = ay + (by - ay) * (x0 - ax) / (bx - ax); nx = x0; }

    if (c == ca) { ax = nx; ay = ny; ca = outcode(ax, ay, x0, y0, x1, y1); }
    else         { bx = nx; by = ny; cb = outcode(bx, by, x0, y0, x1, y1); }
  }
  return false;
}

// A stroke of width w offset along the perpendicular, clipped to the box.
void road(TFT_eSPI& tft, int ax, int ay, int bx, int by, int w, uint16_t c,
          int x0, int y0, int x1, int y1) {
  const float dx = bx - ax, dy = by - ay;
  const float len = sqrtf(dx * dx + dy * dy);
  if (len < 0.5f) return;
  const float nx = -dy / len, ny = dx / len;

  for (int i = -w / 2; i <= w / 2; i++) {
    int px = ax + (int)(nx * i), py = ay + (int)(ny * i);
    int qx = bx + (int)(nx * i), qy = by + (int)(ny * i);
    if (clipSeg(px, py, qx, qy, x0, y0, x1, y1)) tft.drawLine(px, py, qx, qy, c);
  }
}

}  // namespace

// ------------------------------------------------------------------ build

void geomBegin() { nPts = 0; nWays = 0; }

bool geomWay(int8_t layer, uint8_t flags) {
  if (nWays >= GEOM_MAX_WAYS) return false;
  ways[nWays].first = nPts;
  ways[nWays].n     = 0;
  ways[nWays].layer = layer;
  ways[nWays].flags = flags;
  nWays++;
  return true;
}

bool geomPt(int16_t x_dm, int16_t y_dm) {
  if (nPts >= GEOM_MAX_PTS || nWays == 0) return false;
  pts[nPts].x_dm = x_dm;
  pts[nPts].y_dm = y_dm;
  nPts++;
  ways[nWays - 1].n++;
  return true;
}

void geomCommit(uint32_t nowMs) {
  vPts = nPts; vWays = nWays; vAtMs = nowMs; vValid = (nWays > 0);
}

void geomClear() { nPts = nWays = vPts = vWays = 0; vValid = false; }

bool geomValid(uint32_t nowMs) {
  return vValid && (nowMs - vAtMs) < GEOM_MAX_AGE_MS;
}

// ----------------------------------------------------------------- render

void geomDraw(TFT_eSPI& tft, int16_t x, int16_t y, int16_t s,
              uint16_t fg, uint16_t muted, uint16_t bg) {
  const int x0 = x, y0 = y, x1 = x + s - 1, y1 = y + s - 1;

  // The rider sits low and central: almost all of the box is the road ahead,
  // which is the only part that can still be acted on. A centred rider would
  // spend half the box on tarmac already behind the wheel.
  const int cx = x + s / 2;
  const int cy = y + s - s / 8;

  // Decimetres to pixels. GEOM_DEPTH_M of forward view fills the box height.
  auto sx = [&](int16_t dm) { return cx + (int)((long)dm * s / (GEOM_DEPTH_M * 10)); };
  auto sy = [&](int16_t dm) { return cy - (int)((long)dm * s / (GEOM_DEPTH_M * 10)); };

  const int wThin  = (s >= 96) ? 5  : 4;
  const int wThick = (s >= 96) ? 11 : 9;
  /*
    The gap a higher layer punches through a lower one, total across both
    sides. 4 gave 2 px of clearance, which is about 1.7 arc-minutes at the
    700 mm a handlebar sits from the eye - below the threshold where a gap
    reads as a gap rather than as a slightly ragged join. 10 gives 5 px, which
    is the difference between "the flyover crosses over" and "the roads touch".

    This is the single number that makes a flyover legible, so it is worth
    more than it looks.
  */
  const int halo   = 10;

  /*
    Lowest layer first, and each way laid down as a background halo before its
    ink. The halo of a higher road erases the ink of a lower one where they
    cross, so the road underneath visibly breaks and the flyover reads as
    passing over it. No depth cue, no shading, no third colour - just draw
    order, which is all this panel can afford.
  */
  for (int layer = -2; layer <= 2; layer++) {
    for (uint8_t i = 0; i < vWays; i++) {
      const GeomWay& wv = ways[i];
      if (wv.layer != layer || wv.n < 2) continue;

      const bool taken = (wv.flags & GEOM_TAKEN);
      const int  w     = taken ? wThick : wThin;
      const uint16_t c = taken ? fg : muted;

      for (uint8_t p = wv.first; p + 1 < wv.first + wv.n; p++) {
        const int ax = sx(pts[p].x_dm),     ay = sy(pts[p].y_dm);
        const int bx = sx(pts[p + 1].x_dm), by = sy(pts[p + 1].y_dm);
        road(tft, ax, ay, bx, by, w + halo, bg, x0, y0, x1, y1);
        road(tft, ax, ay, bx, by, w,        c,  x0, y0, x1, y1);
      }
    }
  }

  /*
    The rider. A filled disc with a background ring around it, so it separates
    from the road it is standing on whichever colour that road is - the same
    halo trick, applied to the one mark that must never be ambiguous.

    It does not rotate and it does not move. Everything else does. That is what
    makes the view readable without interpretation: the thing at the bottom is
    always you, pointing where you are pointing.
  */
  const int r = (s >= 96) ? 7 : 6;
  tft.fillCircle(cx, cy, r + 3, bg);
  tft.fillCircle(cx, cy, r,     fg);
}

uint32_t geomKey(uint32_t nowMs) { return geomValid(nowMs) ? (vAtMs | 1u) : 0u; }
