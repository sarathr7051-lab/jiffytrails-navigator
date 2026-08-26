/*
  maneuvers.cpp - vector maneuver glyphs.

  Ported verbatim from firmware/ui_mock/ui_mock.ino, which was validated on the
  panel. The percentages below are the numbers that were judged at mount
  distance; they are not re-derived here. Only two things changed in the port:

    1. `tft` arrives as a parameter instead of being a global (display.cpp owns
       the TFT_eSPI instance now).
    2. The code range widened from ui_mock's nine maneuvers to every code in
       nav_types.h, plus the 0x20-0x2F roundabout-exit block.

  Vector paths, not bitmaps - scalable and a fraction of the flash.

  Every glyph is expressed as percentages of an s-by-s box whose top-left is
  (x, y), so no glyph can escape its box no matter which maneuver it is. The
  version before ui_mock took a centre point and grew the turn head to one
  side, which made the real extent depend on which way the arrow pointed - a
  right turn overran to the right, a left turn overran to the left, and the
  layout could not reserve space for both. Layout reserves one box and the
  glyph is guaranteed to fit inside it.

  ---------------------------------------------------------------------------
  APPROXIMATED CODES - what is drawn when nav_types.h has a code ui_mock never
  drew. BLE_PROTOCOL.md: "Never guess - a confidently wrong arrow is worse than
  no arrow." So the rule applied here is that an approximation may understate
  the maneuver but must never point the rider the wrong way; anything that
  cannot clear that bar renders "?" instead.

    SHARP_LEFT/RIGHT   -> the TURN_LEFT/RIGHT glyph. Same side, understated
                          angle. Sending a rider left when the turn is left is
                          right; only the severity is lost.
    KEEP_LEFT/RIGHT    -> the SLIGHT_LEFT/RIGHT glyph. A keep-left is a gentle
                          bear, which is exactly what that glyph reads as.
    FORK_LEFT/RIGHT    -> the SLIGHT_LEFT/RIGHT glyph. Same reasoning; the
                          missing information is that the road splits, not
                          which branch to take.
    EXIT_LEFT/RIGHT    -> the SLIGHT_LEFT/RIGHT glyph. Understates "this is a
                          ramp", keeps the side correct.
    UTURN_LEFT         -> the ui_mock U-turn mirrored about the box centre.
                          ui_mock had one U-turn (0x0A) with the head coming
                          down on the right, i.e. a U-turn to the right, which
                          is the common one here in left-hand traffic. It is
                          kept as UTURN_RIGHT (0x0B) and mirrored for 0x0A.
    FLYOVER/UNDERPASS  -> "?". NAV_DATA.md: Maps produces no flyover-specific
                          icon at all, so these codes can only ever come from a
                          source whose semantics nobody here has seen. A
                          CONTINUE arrow would be a confident claim that the
                          road goes straight through, which is precisely the
                          failure the protocol doc forbids.
    FERRY              -> "?". No boat glyph, and "drive straight ahead" is not
                          what a ferry leg asks of the rider.
    0x20-0x2F          -> the roundabout ring and entry, with the exit NUMBER
                          instead of an exit arrow. The generic ROUNDABOUT
                          glyph has its exit stub pointing right, which for
                          "take the 3rd exit" would be a confidently wrong
                          arrow. The exit angle is not derivable from the code
                          - real roundabouts are not evenly spaced - so the
                          number is the only honest thing to draw.

  One prototype bug found in the port and fixed: ui_mock drew the "?" in font 6.
  Font 6 (Font64rle) carries only "1234567890:-.apm" - '?' has a width table
  entry of 12 and a blank glyph, so MV_UNKNOWN drew nothing at all on hardware.
  It is font 4 here, doubled with setTextSize(2) in the larger boxes, because
  font 4 (Font32rle) is the largest full-ASCII font in the library.
*/

#include <TFT_eSPI.h>
#include "maneuvers.h"
#include "nav_types.h"

// The one glyph that needed mirroring rather than its own percentages: the
// arc is symmetric about the box centre, so only the two legs and the head
// swap sides. Percentages are ui_mock's, reflected as p -> 100 - p.
static void drawUturn(TFT_eSPI& tft, int x, int y, int s, bool toRight, uint16_t fg) {
  auto P = [&](int pct) { return (int)((long)pct * s / 100); };
  auto X = [&](int pct) { return x + P(toRight ? pct : 100 - pct); };
  auto Y = [&](int pct) { return y + P(pct); };

  // Arc drawn as overlapping dots rather than stacked circle outlines with the
  // lower half erased - erasing clipped the legs.
  const int cx = X(50), cy = Y(42), r = P(22), t = P(7);
  for (int i = 0; i <= 24; i++) {
    const float a = 3.14159265f * i / 24.0f;
    tft.fillCircle(cx - (int)(r * cosf(a)), cy - (int)(r * sinf(a)), t, fg);
  }

  // fillRect always grows +x, so a mirrored rect starts at its far corner.
  const int legW = P(14);
  const int inX  = toRight ? X(21) : X(21) - legW;   // entry leg, full height
  const int outX = toRight ? X(65) : X(65) - legW;   // exit leg, stops at head
  tft.fillRect(inX,  Y(42), legW, P(54), fg);
  tft.fillRect(outX, Y(42), legW, P(22), fg);
  tft.fillTriangle(X(58), Y(60), X(86), Y(60), X(72), Y(92), fg);
}

// Ring plus entry stub, shared by ROUNDABOUT and the 0x20-0x2F exit block.
// exitN <= 0 draws ui_mock's exit arrow; otherwise the exit number is drawn
// where that arrow would have been - see the approximation note above.
static void drawRoundabout(TFT_eSPI& tft, int x, int y, int s, int exitN,
                           uint16_t fg, uint16_t bg) {
  auto P = [&](int pct) { return (int)((long)pct * s / 100); };
  auto X = [&](int pct) { return x + P(pct); };
  auto Y = [&](int pct) { return y + P(pct); };

  const int cx = X(45), cy = Y(44), r = P(24);
  for (int k = 0; k < P(10); k++) tft.drawCircle(cx, cy, r - k, fg);
  tft.fillRect(X(40), Y(66), P(10), P(30), fg);            // entry, below

  if (exitN <= 0) {
    tft.fillRect(X(67), Y(39), P(18), P(10), fg);           // exit, right
    tft.fillTriangle(X(82), Y(32), X(82), Y(56), X(97), Y(44), fg);
    return;
  }

  // Font 4 digits are 14 px wide and 26 tall, and that is absolute, not scaled
  // with the box. In the 64 px box of the far band a font-4 digit would touch
  // the ring, so the small font is used there instead.
  char n[4];
  snprintf(n, sizeof(n), "%d", exitN);
  tft.setTextColor(fg, bg);
  tft.setTextDatum(MC_DATUM);
  tft.drawString(n, X(82), Y(44), (s >= 88) ? 4 : 2);
}

void drawManeuver(TFT_eSPI& tft, int x, int y, int s,
                  uint8_t maneuver, uint16_t fg, uint16_t bg) {
  auto P = [&](int pct) { return (int)((long)pct * s / 100); };
  auto X = [&](int pct) { return x + P(pct); };
  auto Y = [&](int pct) { return y + P(pct); };

  // A stroke of thickness P(w) from one point to another, for the diagonals.
  auto thickLine = [&](int x0, int y0, int x1, int y1, int w) {
    for (int i = -w / 2; i <= w / 2; i++) tft.drawLine(x0 + i, y0, x1 + i, y1, fg);
  };

  // The exit block is a range, not a value, so it cannot be a switch label.
  if (maneuver >= MV_ROUNDABOUT_EXIT_BASE && maneuver <= MV_ROUNDABOUT_EXIT_BASE + 0x0F) {
    drawRoundabout(tft, x, y, s, maneuver - MV_ROUNDABOUT_EXIT_BASE, fg, bg);
    return;
  }

  switch (maneuver) {
    case MV_CONTINUE:
      tft.fillRect(X(42), Y(35), P(16), P(60), fg);
      tft.fillTriangle(X(24), Y(40), X(76), Y(40), X(50), Y(6), fg);
      break;

    case MV_TURN_RIGHT:
    case MV_SHARP_RIGHT:            // approximated - see header note
      tft.fillRect(X(24), Y(46), P(15), P(50), fg);            // stem
      tft.fillRect(X(24), Y(46), P(44), P(15), fg);            // elbow
      tft.fillTriangle(X(62), Y(28), X(62), Y(79), X(96), Y(53), fg);
      break;

    case MV_TURN_LEFT:
    case MV_SHARP_LEFT:             // approximated
      tft.fillRect(X(61), Y(46), P(15), P(50), fg);
      tft.fillRect(X(32), Y(46), P(44), P(15), fg);
      tft.fillTriangle(X(38), Y(28), X(38), Y(79), X(4), Y(53), fg);
      break;

    case MV_SLIGHT_RIGHT:
    case MV_KEEP_RIGHT:             // approximated
    case MV_FORK_RIGHT:             // approximated
    case MV_EXIT_RIGHT:             // approximated
      tft.fillRect(X(42), Y(58), P(15), P(38), fg);
      thickLine(X(50), Y(62), X(74), Y(34), P(15));
      tft.fillTriangle(X(88), Y(14), X(58), Y(24), X(78), Y(48), fg);
      break;

    case MV_SLIGHT_LEFT:
    case MV_KEEP_LEFT:              // approximated
    case MV_FORK_LEFT:              // approximated
    case MV_EXIT_LEFT:              // approximated
      tft.fillRect(X(43), Y(58), P(15), P(38), fg);
      thickLine(X(50), Y(62), X(26), Y(34), P(15));
      tft.fillTriangle(X(12), Y(14), X(42), Y(24), X(22), Y(48), fg);
      break;

    case MV_UTURN_RIGHT: drawUturn(tft, x, y, s, true,  fg); break;
    case MV_UTURN_LEFT:  drawUturn(tft, x, y, s, false, fg); break;

    case MV_MERGE:
      tft.fillRect(X(42), Y(30), P(15), P(66), fg);
      tft.fillTriangle(X(25), Y(34), X(75), Y(34), X(50), Y(4), fg);
      thickLine(X(16), Y(94), X(44), Y(64), P(11));
      break;

    case MV_ROUNDABOUT:
      drawRoundabout(tft, x, y, s, 0, fg, bg);
      break;

    case MV_DESTINATION:
      tft.fillRect(X(28), Y(10), P(8), P(84), fg);              // pole
      tft.fillTriangle(X(36), Y(12), X(82), Y(30), X(36), Y(48), fg);
      break;

    // MV_UNKNOWN, MV_FLYOVER, MV_UNDERPASS, MV_FERRY and anything the phone
    // invents. Never guess an arrow, say so instead.
    default:
      tft.setTextColor(fg, bg);
      tft.setTextDatum(MC_DATUM);
      tft.setTextSize((s >= 88) ? 2 : 1);
      tft.drawString("?", X(50), Y(50), 4);
      tft.setTextSize(1);
      break;
  }
}
