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

/*
  Roads are filled polygons, not stacks of offset lines.

  The first version drew a stroke as parallel drawLine copies offset along the
  perpendicular. That is fine for a vertical or horizontal road and visibly
  WRONG for a diagonal one: each copy is a 1 px Bresenham line, and shifting it
  by (0.7, 0.7) rounds to whole pixels, so adjacent copies land on the same
  pixels or leave a gap between them. On the panel a diagonal road rendered as
  diagonal hatching - it looked like a dashed line, not a road.

  A segment is now one quad and a joint is one octagon, both clipped to the box
  with Sutherland-Hodgman and filled as a triangle fan. Solid at every angle,
  and the clip is exact rather than per-line.
*/

struct Pf { float x, y; };

// side: 0 keep x>=v, 1 keep x<=v, 2 keep y>=v, 3 keep y<=v
inline bool inSide(const Pf& p, int side, float v) {
  switch (side) {
    case 0:  return p.x >= v;
    case 1:  return p.x <= v;
    case 2:  return p.y >= v;
    default: return p.y <= v;
  }
}

inline Pf cross(const Pf& a, const Pf& b, int side, float v) {
  const float t = (side < 2) ? (v - a.x) / (b.x - a.x)
                             : (v - a.y) / (b.y - a.y);
  return Pf{ a.x + (b.x - a.x) * t, a.y + (b.y - a.y) * t };
}

int clipTo(const Pf* in, int n, Pf* out, int side, float v) {
  int m = 0;
  for (int i = 0; i < n; i++) {
    const Pf& a = in[i];
    const Pf& b = in[(i + 1) % n];
    const bool ia = inSide(a, side, v), ib = inSide(b, side, v);
    if (ia)        out[m++] = a;
    if (ia != ib)  out[m++] = cross(a, b, side, v);
    if (m >= 14) break;                    // cannot happen; refuses to overflow
  }
  return m;
}

void fillClipped(TFT_eSPI& g, const Pf* poly, int n,
                 int x0, int y0, int x1, int y1, uint16_t c) {
  Pf a[16], b[16];
  int m = n;
  for (int i = 0; i < n && i < 16; i++) a[i] = poly[i];

  m = clipTo(a, m, b, 0, (float)x0);       if (m < 3) return;
  m = clipTo(b, m, a, 1, (float)x1);       if (m < 3) return;
  m = clipTo(a, m, b, 2, (float)y0);       if (m < 3) return;
  m = clipTo(b, m, a, 3, (float)y1);       if (m < 3) return;

  for (int i = 1; i + 1 < m; i++) {
    g.fillTriangle((int)(a[0].x + 0.5f),     (int)(a[0].y + 0.5f),
                   (int)(a[i].x + 0.5f),     (int)(a[i].y + 0.5f),
                   (int)(a[i + 1].x + 0.5f), (int)(a[i + 1].y + 0.5f), c);
  }
}

// One segment, as a quad of width w.
void road(TFT_eSPI& tft, int ax, int ay, int bx, int by, int w, uint16_t c,
          int x0, int y0, int x1, int y1) {
  const float dx = bx - ax, dy = by - ay;
  const float len = sqrtf(dx * dx + dy * dy);
  if (len < 0.5f) return;
  const float h = w * 0.5f;
  const float nx = -dy / len * h, ny = dx / len * h;

  const Pf quad[4] = { { ax + nx, ay + ny }, { bx + nx, by + ny },
                       { bx - nx, by - ny }, { ax - nx, ay - ny } };
  fillClipped(tft, quad, 4, x0, y0, x1, y1, c);
}

// A round join, as an octagon. Without one, two segments meeting at an angle
// leave a notch on the outside of the corner - most visible on a roundabout,
// which is nothing but corners.
void joint(TFT_eSPI& tft, int x, int y, int w, uint16_t c,
           int x0, int y0, int x1, int y1) {
  const float r = w * 0.5f;
  Pf o[8];
  for (int i = 0; i < 8; i++) {
    const float a = 3.14159265f * (2 * i + 1) / 8.0f;   // rotated: flat top
    o[i] = Pf{ x + r * cosf(a), y + r * sinf(a) };
  }
  fillClipped(tft, o, 8, x0, y0, x1, y1, c);
}

}  // namespace

// ------------------------------------------------------------------ build

void geomBegin() {
  nPts = 0; nWays = 0;
  // Unpublish immediately. geomDraw indexes the LIVE arrays with the COMMITTED
  // counts, so a render landing mid-build would draw old counts over
  // half-overwritten coordinates. Nothing calls this across loop iterations
  // today - the demo builds atomically - but a BLE-fed window will arrive from
  // a NimBLE callback while displayRender runs on the main loop, and then it
  // would. The header promises a half transfer cannot reach the screen; this
  // is what makes that true.
  vValid = false;
}

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

  /*
    Weights, raised after seeing the first render on the panel.

    5 px and 11 px were chosen on the laptop and looked thin and washed out on
    a TN panel at 700 mm, where the black level greys out at the handlebar
    viewing angle. Contrast against a poor ground beats stroke economy, and the
    same lesson already forced the night text up from 70% to 88%.

    The ratio matters more than either number: the route has to be obviously
    heavier than the roads around it, or the drawing becomes a puzzle.
  */
  const int wThin  = (s >= 96) ? 6  : 5;
  const int wThick = (s >= 96) ? 15 : 12;
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
  /*
    Casing pass then fill pass, PER LAYER - the order every map renderer uses,
    and it has to be this way round for two separate reasons.

    Per SEGMENT was wrong: the next segment's halo bit a notch out of the
    previous segment's ink at every joint, and a roundabout ring came out as a
    dotted circle.

    Per WAY was still wrong, and more subtly: two roads at the SAME layer
    haloed each other, so a side road punched gaps in the cross street it
    merely touched. A halo must only break layers BELOW it. Drawing every halo
    on a layer before any ink on that layer is what makes that true.
  */
  /*
    A casing is only meaningful when something is BELOW it. Ways on the lowest
    layer present get their ink and no halo.

    Without this, a window where every road is at grade - which is most windows
    in a real OSM extract - pays for a casing pass that can only do harm: it
    breaks roads that MEET rather than cross, at every junction, for no depth
    information at all. The halo exists to say "this passes over that", and
    where there is no "that" it says nothing and costs ink.
  */
  int minLayer = 2;
  for (uint8_t i = 0; i < vWays; i++) {
    if (ways[i].n >= 2 && ways[i].layer < minLayer) minLayer = ways[i].layer;
  }

  for (int layer = -2; layer <= 2; layer++) {
    for (uint8_t pass = 0; pass < 2; pass++) {
      if (pass == 0 && layer == minLayer) continue;   // nothing beneath to break
      for (uint8_t i = 0; i < vWays; i++) {
        const GeomWay& wv = ways[i];
        if (wv.layer != layer || wv.n < 2) continue;

        const bool taken = (wv.flags & GEOM_TAKEN);
        const int  w     = taken ? wThick : wThin;
        const int  pw    = pass ? w : w + halo;
        const uint16_t pc = pass ? (taken ? fg : muted) : bg;

        for (uint8_t p = wv.first; p + 1 < wv.first + wv.n; p++) {
          const int ax = sx(pts[p].x_dm),     ay = sy(pts[p].y_dm);
          const int bx = sx(pts[p + 1].x_dm), by = sy(pts[p + 1].y_dm);
          road(tft, ax, ay, bx, by, pw, pc, x0, y0, x1, y1);
          // Joints on interior vertices only. The ends of a way are clipped
          // edges or dead ends; neither needs a cap.
          if (p + 2 < wv.first + wv.n) joint(tft, bx, by, pw, pc, x0, y0, x1, y1);
        }
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
