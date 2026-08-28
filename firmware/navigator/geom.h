/*
  geom.h - junction geometry: the roads around you, drawn.

  An arrow says "bear right". It cannot say "take the flyover, not the service
  road under it", and in Bengaluru those leave the junction on nearly the same
  bearing - NAV_DATA.md records that Maps publishes no flyover distinction at
  all. This module draws the actual shape instead.

  WHAT ARRIVES. The phone holds an offline OSM extract, queries it against its
  own GPS, and sends line segments already rotated into the rider's frame:
  x to the right, y forward, decimetres. Rotating on the phone rather than here
  is deliberate - the phone knows the heading, and a heading the device guessed
  would be a confidently wrong drawing, which is the failure this project
  refuses to ship.

  See docs/ARCH_ANDROID_AUTO.md 2.2 for the transport: ~726 B per 240 m window,
  ~39 B/s once the device caches tiles.

  HOW THE FLYOVER READS. Ways are drawn in layer order, lowest first, each one
  as a background-coloured halo with the ink stroke on top. A higher layer
  therefore punches a gap in everything beneath it automatically - which is the
  same convention the FLYOVER glyph already uses, and the same one every map
  renderer uses, so nothing new has to be learned to read it.
*/

#pragma once
#include <Arduino.h>

class TFT_eSPI;

// Sized from the measured budget in ARCH_ANDROID_AUTO.md: a Bengaluru arterial
// junction in a 240 m window is 10-40 ways and 60-150 vertices after
// simplification. 150*4 + 40*4 = 760 bytes, which is nothing.
static const uint8_t GEOM_MAX_PTS  = 150;
static const uint8_t GEOM_MAX_WAYS = 40;

// How far ahead the box covers. 120 m is about eight seconds at 50 km/h, which
// is the horizon a junction decision actually lives in; more depth shrinks the
// junction to a smudge and less arrives too late to act on.
static const uint8_t GEOM_DEPTH_M = 120;

// Geometry is as perishable as a maneuver. If the phone stops sending, the
// roads on screen are where you WERE, and a stale map is worse than none.
static const uint32_t GEOM_MAX_AGE_MS = 6000;

enum : uint8_t {
  GEOM_TAKEN = 0x01,   // the branch the route takes - drawn thick
};

struct GeomPt  { int16_t x_dm, y_dm; };
struct GeomWay { uint8_t first, n; int8_t layer; uint8_t flags; };

// Build a view. Call geomBegin, then geomWay/geomPt per way, then geomCommit.
// Nothing is drawn from a half-built view: geomCommit is what makes it valid,
// so a truncated transfer leaves the previous view up rather than a fragment.
void geomBegin();
bool geomWay(int8_t layer, uint8_t flags);   // false if full
bool geomPt(int16_t x_dm, int16_t y_dm);     // false if full
void geomCommit(uint32_t nowMs);
void geomClear();

// True if a view is present and fresh.
bool geomValid(uint32_t nowMs);

// Identity of the current view, for redraw tests: the commit time, or 0 when
// there is nothing valid. The display repaints when this changes, so a new
// window and an expiring one both trigger exactly one repaint.
uint32_t geomKey(uint32_t nowMs);

// Draw into the s-by-s box at (x, y). The rider sits at the bottom centre and
// does not move; the road moves under them, which is the only arrangement that
// needs no interpretation at a glance.
void geomDraw(TFT_eSPI& tft, int16_t x, int16_t y, int16_t s,
              uint16_t fg, uint16_t muted, uint16_t bg);
