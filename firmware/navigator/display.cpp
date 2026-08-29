/*
  display.cpp - renders NavState and nothing else.

  Ported from firmware/ui_mock/ui_mock.ino, which was reviewed on the panel at
  mount distance. The layout numbers here are that sketch's, not re-derived:
  the two-column split, the glyph boxes and the runtime-measured distance block
  all exist because hand-estimated pixel maths clipped the display twice.

  Differences from ui_mock, all forced by the contract in nav_types.h:

    - The screen comes from screenFor(). ui_mock derived bands inline; the
      precedence now lives in one place so no failure state can leave a stale
      maneuver on screen, and this file must not second-guess it.
    - The road name is NavState.instruction, a real string up to 59 chars,
      rather than a canned name chosen to fit.
    - Distance is rendered exactly as given. The phone quantises (NAV_DATA.md
      bands: 100 m / 50 m / 10 m); ui_mock had to fake that locally because it
      had no phone. Re-quantising here would round twice.
    - The traffic bar is gone. It needs progressSegments, and NavState carries
      no traffic field - PKT_TRAFFIC exists in the protocol but nothing lands
      in NavState yet. Inventing segment colours would be a drawn lie about
      the road ahead, so the far-band footer gets the space instead.
    - ui_mock's idle clock and trip stats came from data NavState does not
      carry (no time of day, PKT_TRIP is not in the struct). Idle says what it
      honestly knows.
*/

#include <TFT_eSPI.h>
#include "display.h"
#include "maneuvers.h"
#include "geom.h"

// display.cpp owns the panel. maneuvers.cpp gets it through the TFT_eSPI&
// parameter in its signature; nothing else touches it.
static TFT_eSPI    tft  = TFT_eSPI();
static TFT_eSprite dist = TFT_eSprite(&tft);   // distance field only - a
                                               // full-screen sprite will not
                                               // fit in plain ESP32 RAM
static bool sprite_ok = false;

static const uint8_t ROTATION = 1;      // landscape
static const int16_t W = 320;
static const int16_t H = 240;

// ---------------------------------------------------------------- palette

/*
  Palette, not constants — day and night swap these.

  Day is black on white: daylight readability is the project's gate, and
  positive polarity gives the most ink against glare. Night inverts, because a
  mostly-white panel at 700 mm destroys the dark adaptation you need to see an
  unlit Bengaluru road.

  C_INV_* are for elements that invert *relative to the current theme* — the
  sub-30 m screen and the alert band. They must not be hardcoded to black and
  white, or at night they would stop being an inversion and start being
  ordinary.
*/
static uint16_t C_BG     = TFT_WHITE;
static uint16_t C_FG     = TFT_BLACK;
static uint16_t C_MUTED  = 0x8410;    // mid grey, de-emphasised text
static uint16_t C_INV_BG = TFT_BLACK;
static uint16_t C_INV_FG = TFT_WHITE;
static bool     nightMode = false;

/*
  One accent, one meaning: amber is "live / attention" and appears nowhere else.
  It is deliberately NOT part of the day/night swap - amber is the one hue that
  survives a dimmed backlight and a tinted visor, which is why it is the only
  colour the night palette keeps.

  It is also never load-bearing on its own. Every state amber marks differs in
  SHAPE too (filled disc vs hollow ring), because a photochromic visor turns
  amber to grey and a rider who can only see shape must still be able to read
  the screen.
*/
static const uint16_t C_ACCENT = 0xFC40;   // #FF8A00

// ----------------------------------------------------------------- layout
//
// Screen is two columns: maneuver on the left, distance on the right.
//
// Sizing these by eye failed twice, so the real numbers, from the library's
// own width tables (Font32rle.c / Font64rle.c / Font72rle.c):
//
//   font 8  digits 55 px wide, 75 tall  ->  "700" is 165 px
//   font 6  digits 27 px wide, 48 tall  ->  "1.2" is  69 px
//   font 4  'm' 22 px, "km" 34 px, 26 tall
//
// 165 + 34 + padding is most of the screen, which leaves the arrow about
// 104 px. The sprite is opaque, so anything drawn to its left must stay inside
// ARROW_ZONE or it gets painted over on the next tick.
static const int16_t SPR_X = 112;   // sprite left edge
static const int16_t SPR_W = 208;   // 112 + 208 = 320, flush to the edge
static const int16_t SPR_H = 80;    // font 8 is 75 px tall
static const int16_t ARROW_ZONE = SPR_X - 4;

// Glyph boxes, per screen. The committed/now box is the widest one and is the
// binding constraint on ARROW_ZONE, so let the compiler hold us to it.
// Sized against the distance number, not in isolation. Font 8 is 75 px tall,
// and a glyph fills roughly 90% of its declared box — so a 64 px box drew an
// arrow about 57 px against a 75 px number, and the number visibly dominated.
// The arrow is the instruction; the number is the qualifier, and it should not
// be the larger of the two. Boxes now start at parity and grow past it as the
// turn approaches, which also makes the progression easier to feel.
// The arrow and the number are one row and must share a centre line. They did
// not: on the far screen the sprite centred at y=100 while the glyph box centred
// at y=130, so the number floated 30 px above the arrow and the row read as two
// unrelated objects. Each Y below is derived as (row centre - box/2), and the
// static_asserts hold that arithmetic true if anyone moves a row.
//
//   far        row centre 110   sprite 70..150   glyph 68..152
//   approach   row centre 128   sprite 88..168   glyph 80..176
//   committed  row centre 128   sprite 88..168   glyph 76..180
static const int16_t GLYPH_FAR_X =  8, GLYPH_FAR_Y = 68,  GLYPH_FAR_S = 84;
static const int16_t GLYPH_APP_X =  6, GLYPH_APP_Y = 80,  GLYPH_APP_S = 96;
static const int16_t GLYPH_BIG_X =  4, GLYPH_BIG_Y = 76,  GLYPH_BIG_S = 104;

// The turn-now frame. Must clear the glyph and the distance sprite, or the
// next distance push paints over the bottom bar and it flickers once per
// 10 m step - the same trap the geometry box fell into.
static const int16_t NOW_BAR_H = 14;
static_assert(NOW_BAR_H <= GLYPH_BIG_Y, "top bar overlaps the turn-now glyph");
static_assert(GLYPH_FAR_X + GLYPH_FAR_S <= 108, "far glyph runs under the sprite");
static_assert(GLYPH_BIG_X + GLYPH_BIG_S <= ARROW_ZONE, "glyph runs under the sprite");
static_assert(GLYPH_APP_X + GLYPH_APP_S <= ARROW_ZONE, "glyph runs under the sprite");

// Sprite origins. SPR_H is 80, so the row centre is DIST_Y + 40.
static const int16_t DIST_Y_FAR   = 70;   // centre 110, clears the taller footer
static const int16_t DIST_Y_OTHER = 88;   // centre 128

// The distance sprite must clear the turn-now bottom bar, or every 10 m step
// repaints over it and the frame flickers.
static_assert(DIST_Y_OTHER + SPR_H <= H - NOW_BAR_H, "sprite overlaps the turn-now bar");

// Arrow and number must sit on the same centre line, or the row reads as two
// unrelated objects. Checked here so a future nudge to either cannot drift.
static_assert(GLYPH_FAR_Y + GLYPH_FAR_S / 2 == DIST_Y_FAR   + SPR_H / 2, "far row misaligned");
static_assert(GLYPH_APP_Y + GLYPH_APP_S / 2 == DIST_Y_OTHER + SPR_H / 2, "approach row misaligned");
static_assert(GLYPH_BIG_Y + GLYPH_BIG_S / 2 == DIST_Y_OTHER + SPR_H / 2, "committed row misaligned");

/*
  Where an alert starts, per screen. These were literals inside drawBand and the
  asserts below tested the main row against BAND_Y (190) instead - which on the
  approach screen is 10 px of slack the assert claimed to be guarding and was
  not, because an alert there starts at 180. Nothing is broken today, but a
  guard that does not guard what its message says is worse than no guard: it
  invites the next edit to trust it.

  Bounded by what sits above them. Far: glyph ends 152, sprite ends 150.
  Approach: glyph ends 176. Committed and turn-now suppress alerts entirely, so
  they genuinely use BAND_Y.
*/
static const int16_t ALERT_TOP_FAR  = 156;
static const int16_t ALERT_TOP_APP  = 180;
static const int16_t ALERT_TOP_IDLE = 0;    // parked, the message IS the screen

// Nothing in the main row may run under the region an alert can occupy.
static_assert(GLYPH_FAR_Y + GLYPH_FAR_S <= ALERT_TOP_FAR, "far glyph runs into the alert");
static_assert(DIST_Y_FAR  + SPR_H       <= ALERT_TOP_FAR, "far sprite runs into the alert");
static_assert(GLYPH_APP_Y + GLYPH_APP_S <= ALERT_TOP_APP, "approach glyph runs into the alert");
static_assert(GLYPH_BIG_Y + GLYPH_BIG_S <= 190, "committed glyph runs into the band");

// ------------------------------------------------------------ redraw state
//
// Idempotency: chrome is redrawn only when something chrome depends on
// changes, the distance field only when the value changes. At 1 Hz with a
// font-8 number, redrawing either unnecessarily is visible as flicker.

static bool     chromeValid  = false;
static UiScreen lastScreen   = UI_DISCONNECTED;
static uint8_t  lastManeuver = 0xFF;
static bool     lastGpsWeak  = false;
static char     lastInstruction[INSTRUCTION_MAX] = {0};
static int32_t  lastDist     = -1;
static uint32_t lastFooter   = 0xFFFFFFFFu;
// Junction geometry arriving, changing or expiring is a chrome change: it
// occupies the arrow box, so the box has to be repainted when it appears and
// again when it goes and the arrow comes back.
static uint32_t lastGeomKey  = 0xFFFFFFFFu;
// The idle and arrived screens repaint wholesale, so they track their alert
// separately from lastFooter, which encodes a nav-screen band value.
static uint32_t lastIdleKey = 0;
static uint16_t lastClockKey = 0xFFFF;   // idle screen has no other change key
static uint8_t  lastBattery  = 0xFF;

void displayInvalidate() {
  chromeValid  = false;
  lastDist     = -1;
  lastFooter   = 0xFFFFFFFFu;
  lastClockKey = 0xFFFF;
  lastBattery  = 0xFF;
}

// --------------------------------------------------------------- helpers

// NAV_DATA.md rule 7: instructions reach 59 characters ("Slight right at
// Horamavu Agara Circle onto Horamavu Agara Rd") and roughly 16-20 fit at a
// glanceable size. Truncating from the end costs the road name, which is the
// useful part - the better fix is for the phone to drop the maneuver prefix,
// since the arrow already says "slight right". Until the parser does that,
// this at least never clips silently: it measures with textWidth and ends
// with an ellipsis so the rider can see something was cut.
static void fitText(const char* src, char* dst, size_t dstSize,
                    int16_t maxW, uint8_t font) {
  snprintf(dst, dstSize, "%s", src);
  if (tft.textWidth(dst, font) <= maxW) return;

  char probe[INSTRUCTION_MAX + 4];
  size_t n = strlen(dst);
  while (n > 0) {
    dst[--n] = '\0';
    snprintf(probe, sizeof(probe), "%s...", dst);
    if (tft.textWidth(probe, font) <= maxW) {
      snprintf(dst, dstSize, "%s", probe);
      return;
    }
  }
  dst[0] = '\0';
}

// TFT_eSprite derives from TFT_eSPI, so the same layout code serves the
// sprite and the direct-to-panel fallback; (ox, oy) is the block's origin.
//
// Right-align the whole block against the right edge and let it grow
// leftwards, measuring rather than assuming. Hard-coding an origin is what
// clipped the leading digit: "700" at font 8 is 165 px, and anything narrower
// than that silently loses characters off the left.
static void layoutDistance(TFT_eSPI& g, int32_t m, int16_t ox, int16_t oy,
                           uint16_t fg, uint16_t bg) {
  g.setTextColor(fg, bg);

  char num[12];
  const char* unit;
  uint8_t numFont;

  /*
    >= and not >, and the difference is a clipped digit.

    Font 8 digits are 55 px. The field is SPR_W 208 wide, and the unit takes
    pad 8 + "m" 22 + gap 6 = 36, leaving 172 for the number. Three digits is
    165 and fits; four is 220 and overruns by 48, so the leading digit is cut
    off on the left and 1000 m renders as "000 m".

    With >, exactly 1000 took the metres branch and did precisely that. It is
    reachable in normal use: above 500 m the phone quantises to 100 m steps, so
    the sequence really is 1200, 1100, 1000, 900 - and a long "continue"
    instruction sits in that range for minutes at a time.
  */
  if (m >= 1000) {
    snprintf(num, sizeof(num), "%ld.%ld", (long)(m / 1000), (long)((m % 1000) / 100));
    unit = "km"; numFont = 6;
  } else {
    snprintf(num, sizeof(num), "%ld", (long)m);
    unit = "m";  numFont = 8;
  }

  const int16_t pad   = 8;
  const int16_t unitW = g.textWidth(unit, 4);

  g.setTextDatum(MR_DATUM);
  g.drawString(unit, ox + SPR_W - pad,             oy + SPR_H / 2 + 16, 4);
  g.drawString(num,  ox + SPR_W - pad - unitW - 6, oy + SPR_H / 2,      numFont);
}

// Only the distance field is a sprite. Redrawing a font-8 number straight to
// the panel every second flickers badly; the rest of a screen is static, so it
// costs nothing to leave alone. If the 33 kB sprite could not be allocated we
// still have to show a distance, so fall back to the flickery path rather than
// showing nothing.
static void pushDistance(int32_t m, int16_t x, int16_t y, uint16_t fg, uint16_t bg) {
  if (sprite_ok) {
    dist.fillSprite(bg);
    layoutDistance(dist, m, 0, 0, fg, bg);
    dist.pushSprite(x, y);
  } else {
    tft.fillRect(x, y, SPR_W, SPR_H, bg);
    layoutDistance(tft, m, x, y, fg, bg);
  }
}

static void drawBanner(const char* line1, const char* line2, uint16_t bg, uint16_t fg) {
  tft.fillScreen(bg);
  tft.setTextColor(fg, bg);
  tft.setTextDatum(MC_DATUM);
  tft.drawString(line1, W / 2, line2 ? H / 2 - 26 : H / 2, 4);
  if (line2) tft.drawString(line2, W / 2, H / 2 + 22, 4);
}

// BLE_PROTOCOL.md wants a small corner warning for gps_weak. Font 2, top
// corner, and the instruction gives up the width for it rather than the two
// overlapping.
static const int16_t GPS_RESERVE_W = 44;

static void drawGpsWeak(bool topRight, uint16_t fg, uint16_t bg) {
  tft.setTextColor(fg, bg);
  tft.setTextDatum(topRight ? TR_DATUM : TL_DATUM);
  tft.drawString("GPS?", topRight ? W - 6 : 6, 4, 2);
}

// eta_min and remaining_100m both arrive on every packet and change slowly, so
// the footer is its own small redraw rather than a reason to repaint chrome.
// remaining_100m is recomputed by the phone every packet on purpose:
// NAV_DATA.md measured progressMax drifting 7486 -> 7780 -> 7659 within 45 s,
// so a cached remaining distance is wrong within a minute.
// The band along the bottom. See bandFor() in nav_types.h for why this exists
// and what outranks what. Geometry checked against the approach glyph, which
// is the tallest thing above it and ends at y=184.
static const int16_t BAND_Y = 190;
static const int16_t BAND_H = H - BAND_Y;   // 50 px

static const char* notifyTag(uint8_t kind) {
  switch (kind) {
    case NOTIFY_MESSAGE: return "MSG";
    case NOTIFY_EMAIL:   return "MAIL";
    case NOTIFY_ALERT:   return "ALERT";
    default:             return "PHONE";
  }
}

// Truncate to fit, ending in an ellipsis so a cut is visibly a cut rather
// than a shorter name. Measured, never estimated — hand-guessed widths clipped
// this display twice before.
/*
  Word-wrapped text, up to `maxLines`, ellipsised only if it still will not fit.

  Breaks on spaces so a road name survives intact. The last line takes the
  ellipsis, so what gets lost is the tail rather than the middle. Font 4 is
  26 px, so two lines cost 56 px including the gap.
*/
static void drawWrapped(const char* text, int16_t x, int16_t y,
                        int16_t maxW, uint8_t maxLines, uint16_t fg) {
  static const uint8_t FONT = 4;
  static const int16_t LINE_H = 28;

  tft.setTextColor(fg, C_BG);
  tft.setTextDatum(TL_DATUM);

  char rest[INSTRUCTION_MAX + 4];
  snprintf(rest, sizeof(rest), "%s", text);

  for (uint8_t line = 0; line < maxLines; line++) {
    if (rest[0] == '\0') return;

    if (tft.textWidth(rest, FONT) <= maxW) {      // the remainder fits
      tft.drawString(rest, x, y + line * LINE_H, FONT);
      return;
    }

    if (line + 1 == maxLines) {                   // last line: ellipsise
      char cut[INSTRUCTION_MAX + 4];
      fitText(rest, cut, sizeof(cut), maxW, FONT);
      tft.drawString(cut, x, y + line * LINE_H, FONT);
      return;
    }

    // Longest word-boundary prefix that fits.
    int brk = -1;
    for (int i = 0; rest[i] != '\0'; i++) {
      if (rest[i] != ' ') continue;
      char save = rest[i];
      rest[i] = '\0';
      const bool fits = tft.textWidth(rest, FONT) <= maxW;
      rest[i] = save;
      if (!fits) break;
      brk = i;
    }
    if (brk < 0) {                                // one unbreakable word
      char cut[INSTRUCTION_MAX + 4];
      fitText(rest, cut, sizeof(cut), maxW, FONT);
      tft.drawString(cut, x, y + line * LINE_H, FONT);
      return;
    }

    rest[brk] = '\0';
    tft.drawString(rest, x, y + line * LINE_H, FONT);
    memmove(rest, rest + brk + 1, strlen(rest + brk + 1) + 1);
  }
}

// `scr` decides what "blank" means. The sub-30 m screen is drawn inverted, so
// clearing the band to C_BG painted a white stripe across the bottom of a black
// screen - which read as a large empty alert rather than as nothing at all.
static void drawBand(const NavState& s, BandContent band, UiScreen scr) {
  const bool inverted = (scr == UI_NAV_NOW);
  const uint16_t groundBg = inverted ? C_INV_BG : C_BG;

  /*
    An alert grows upward into the footer, because for the two seconds it is up
    the message is what the rider wants and the arrival time is not. It never
    grows past the main row: the arrow and the distance are the instruction and
    nothing may cover them.

    The approach glyph is the tallest thing above the band and ends at 176, so
    that band starts at 180. The far row ends at 152 and can give 24 px more,
    which is the difference between one line of a WhatsApp message and two.
  */
  /*
    Derived from the SCREEN, not from the band.

    This used to depend on the band: an alert got a tall region and everything
    else got the 50 px strip from BAND_Y. That left a bug on the panel. A call
    band on the far screen painted 156..240; when it was replaced by the footer,
    the footer cleared only 190..240, and the top 34 px of the alert stayed on
    screen - a white strip with the caller's name in it, sitting under the road
    name for the rest of the ride.

    Whatever region an alert COULD occupy on this screen is the region every
    band has to clear. The values are bounded by what sits above them:

      far         glyph ends 152, sprite ends 150   -> 156
      approach    glyph ends 176                    -> 180
      committed   glyph ends 180, alerts suppressed -> BAND_Y
      idle        the message IS the screen         -> 0

    Idle used to be 64, which cut the clock in half. The font-8 digits run
    44..119, so the alert sliced straight through them and left the top 20 px
    of "18:42" stranded above the band as four meaningless arches. Seen on the
    panel; it looked like memory corruption rather than a layout error.

    Nudging the band down would only move the cut. With no route there is
    nothing on screen worth protecting, so a message parked gets the whole
    display - which is also the better answer, because reading a message is the
    only thing you are doing at that moment.
  */
  const int16_t alertTop =
      (scr == UI_IDLE || scr == UI_ARRIVED) ? ALERT_TOP_IDLE
    : (scr == UI_NAV_FAR)                   ? ALERT_TOP_FAR
    : (scr == UI_NAV_APPROACH)              ? ALERT_TOP_APP
    :                                         BAND_Y;
  const int16_t alertH = H - alertTop;

  if (band == BAND_BLANK) {
    tft.fillRect(0, alertTop, W, alertH, groundBg);
    return;
  }

  if (band == BAND_FOOTER) {
    tft.fillRect(0, alertTop, W, alertH, groundBg);

    /*
      Two cells: a large figure with a small unit beside it, baselines aligned.

      Font 2 is 16 px tall. At the ~700 mm a handlebar sits from the eye that is
      about 16 arc-minutes — ISO 15008's absolute floor for a *static* display,
      and this one vibrates in sunlight. The figures move to font 6 at 48 px and
      the units stay at font 4, which is the cycling-computer pattern: the
      number carries the value and the unit is a label you learn once and stop
      reading.

      Baselines are shared so the pair reads as one object rather than two.
    */
    const int16_t base = BAND_Y + BAND_H - 6;   // shared baseline
    const int16_t unitGap = 5;

    char num[12];
    char unit[8];

    if (s.eta_min) {
      snprintf(num, sizeof(num), "%u", (unsigned)s.eta_min);
      snprintf(unit, sizeof(unit), "min");
      tft.setTextColor(C_FG, groundBg);
      tft.setTextDatum(BL_DATUM);
      tft.drawString(num, 8, base, 6);
      tft.setTextColor(C_MUTED, groundBg);
      tft.drawString(unit, 8 + tft.textWidth(num, 6) + unitGap, base, 4);
    }

    // NAV_DATA.md measured progressMax drifting 7486 -> 7780 -> 7659 within
    // 45 s, so a cached remaining distance is wrong within a minute.
    if (s.remaining_100m) {
      snprintf(num, sizeof(num), "%u.%u",
               (unsigned)(s.remaining_100m / 10), (unsigned)(s.remaining_100m % 10));
      snprintf(unit, sizeof(unit), "km");

      const int16_t numW  = tft.textWidth(num, 6);
      const int16_t unitW = tft.textWidth(unit, 4);
      const int16_t x0    = 312 - unitW - unitGap - numW;

      tft.setTextColor(C_FG, groundBg);
      tft.setTextDatum(BL_DATUM);
      tft.drawString(num, x0, base, 6);
      tft.setTextColor(C_MUTED, groundBg);
      tft.drawString(unit, x0 + numW + unitGap, base, 4);
    }
    return;
  }

  // CALL and NOTIFY: the whole band inverts. A large low-spatial-frequency
  // luminance flip is the one encoding that survives vibration blur and glare
  // on this panel, and it registers peripherally without costing a glance.
  const bool isCall  = (band == BAND_CALL);
  const char* tag    = isCall ? "CALL" :
                       (s.notifySrc[0] ? s.notifySrc : notifyTag(s.notifyKind));
  const char* body   = isCall ? s.callName : s.notifyText;

  tft.fillRect(0, alertTop, W, alertH, C_INV_BG);
  tft.setTextColor(C_INV_FG, C_INV_BG);

  /*
    Parked, the message is the only thing on screen and gets a layout rather
    than a strip: sender at the top, a hairline under it, and the text on the
    same x=16 rail the idle screen uses, so the two screens agree.

    Riding, every pixel of height is a word, so the tag sits tight above the
    body and the rail moves in to 8. The strip is not a small version of the
    parked screen; it is a different job.
  */
  const bool    wholeScreen = (alertTop == 0);
  const int16_t railX = wholeScreen ? 16 : 8;
  const int16_t bodyY = wholeScreen ? 72 : alertTop + 22;

  tft.setTextDatum(TL_DATUM);
  tft.drawString(tag, railX, wholeScreen ? 24 : alertTop + 4, 2);
  if (wholeScreen) tft.fillRect(railX, 52, W - railX * 2, 1, C_MUTED);

  // Body gets font 4 — this is the one thing in the band worth reading, and
  // font 2 at 700 mm is below the legible floor on a moving bike. Two lines
  // when the band is tall enough, which is the difference between a message
  // being readable and merely being present.
  const char* shown = body[0] ? body : (isCall ? "incoming" : "notification");
  // With no route there is nothing to protect, so a message gets the screen
  // rather than a strip - which is the difference between glimpsing that a
  // message arrived and actually reading it.
  const uint8_t lines = wholeScreen ? 4 : (alertH >= 70) ? 2 : 1;

  // drawWrapped clears against C_BG, and inside the band the ground is
  // inverted. Swapped rather than parameterised because every other caller
  // draws on the normal ground and should not have to say so.
  const uint16_t saveBg = C_BG;
  C_BG = C_INV_BG;
  drawWrapped(shown, railX, bodyY, W - railX * 2, lines, C_INV_FG);
  C_BG = saveBg;
}

// Never a maneuver here, whatever the last packet said — BLE_PROTOCOL.md.
//
// The clock is the point of this screen. A handlebar clock is genuinely useful
// stopped at a signal, and it is the one thing worth showing when there is no
// route. It comes from the phone: the device has no RTC and no network, so
// there is no other source, and without one this screen has nothing to say.
/*
  The idle screen. The device at rest, and the only screen with no safety
  constraint on it - which makes it the one place a bit of character is free.

  Two rails only, x=16 and x=304, and everything sits on one of them. Mixing
  centred and rail-aligned elements is the loudest homemade tell there is, and
  the old version did exactly that: three centred lines stacked down the middle.

  The clock moved from font 7 to font 8. Font 7 is the seven-segment face, and
  nothing else turns a considered instrument into a 1994 clock radio as fast.
  Font 8 is also 75 px against font 7's 48, so it is both better looking and
  more readable at arm's length - the rare change with no trade.

  It is right-aligned to the rail rather than centred, for a reason beyond
  taste: a centred clock shifts sideways whenever the hour goes from one digit
  to two, and a number that moves when its value changes reads as unstable.
*/
static const int16_t IDLE_RAIL_L  = 16, IDLE_RAIL_R = 304;
static const int16_t IDLE_LABEL_Y = 16;    // font 2, 16 tall
static const int16_t IDLE_CLOCK_Y = 44;    // font 8, 75 tall
static const int16_t IDLE_TRAIL_Y = 148;   // the road, 3 px
static const int16_t IDLE_NOTE_Y  = 180;   // font 2
static const int16_t IDLE_DOT_X   = 152, IDLE_DOT_R = 6;

static_assert(IDLE_LABEL_Y + 16 <= IDLE_CLOCK_Y, "PARKED overlaps the clock");
static_assert(IDLE_CLOCK_Y + 75 <= IDLE_TRAIL_Y, "clock overlaps the trail");
static_assert(IDLE_TRAIL_Y + 3  <= IDLE_NOTE_Y,  "trail overlaps the note");
static_assert(IDLE_NOTE_Y  + 16 <= H,            "note falls off the screen");
static_assert(IDLE_DOT_X + IDLE_DOT_R < IDLE_RAIL_R, "rider dot escapes the rail");

static void drawTracked(const char* s, int16_t cx, int16_t y, uint8_t font,
                        int16_t extra, uint16_t fg);

static void drawIdle(const NavState& s) {
  tft.fillScreen(C_BG);

  // Tracked small caps against a large tight numeral - the instrument idiom,
  // and the only second "weight" a single-weight font library has.
  {
    const char* label = "PARKED";
    int16_t w = 0;
    for (const char* p = label; *p; ++p) w += tft.textWidth(String(*p), 2) + 3;
    drawTracked(label, IDLE_RAIL_L + (w - 3) / 2, IDLE_LABEL_Y, 2, 3, C_MUTED);
  }

  tft.setTextColor(C_FG, C_BG);
  tft.setTextDatum(TR_DATUM);
  if (s.clockValid) {
    char buf[8];
    snprintf(buf, sizeof(buf), "%u:%02u", (unsigned)s.clockHour, (unsigned)s.clockMin);
    tft.drawString(buf, IDLE_RAIL_R, IDLE_CLOCK_Y, 8);
  } else {
    // No clock yet. Say what is actually true rather than inventing a time.
    tft.setTextSize(2);
    tft.drawString("READY", IDLE_RAIL_R, IDLE_CLOCK_Y + 20, 4);
    tft.setTextSize(1);
  }

  /*
    The road, with the rider resting in a gap in it. This is the same drawing
    as the boot mark and the logo - a line with something on it - so the device
    reads as one idea rather than three screens that happen to share a font.

    It is not decoration standing in for content: the gap is where you are, and
    a parked bike is exactly a rider stopped on a road.
  */
  tft.fillRect(IDLE_RAIL_L, IDLE_TRAIL_Y, IDLE_DOT_X - 12 - IDLE_RAIL_L, 3, C_FG);
  tft.fillRect(IDLE_DOT_X + 12, IDLE_TRAIL_Y, IDLE_RAIL_R - (IDLE_DOT_X + 12), 3, C_FG);
  tft.fillCircle(IDLE_DOT_X, IDLE_TRAIL_Y + 1, IDLE_DOT_R, C_FG);

  tft.setTextColor(C_MUTED, C_BG);
  tft.setTextDatum(TL_DATUM);
  tft.drawString("no route", IDLE_RAIL_L, IDLE_NOTE_Y, 2);

  // Battery below 20% only. A permanent percentage is a re-glance magnet —
  // something you check because it is there, not because you need it.
  if (s.phoneBatteryPct && s.phoneBatteryPct <= 20) {
    char buf[20];
    snprintf(buf, sizeof(buf), "phone %u%%", (unsigned)s.phoneBatteryPct);
    tft.setTextDatum(TR_DATUM);
    tft.drawString(buf, IDLE_RAIL_R, IDLE_NOTE_Y, 2);
  }
}

// The arrival screen. This existed in the protocol as the NAV_ARRIVED flag and
// was rendered nowhere — arriving simply dropped to idle, so the one moment
// the device should acknowledge was the one it skipped. Latched by the
// watchdog for ARRIVAL_DWELL_MS, because Maps drops the notification within
// about five seconds of arrival.
static void drawArrived(const NavState& s) {
  tft.fillScreen(C_BG);

  drawManeuver(tft, GLYPH_FAR_X + 8, 68, 72, MV_DESTINATION, C_FG, C_BG);

  tft.setTextColor(C_FG, C_BG);
  tft.setTextDatum(TL_DATUM);
  tft.setTextSize(2);
  tft.drawString("ARRIVED", 108, 84, 4);
  tft.setTextSize(1);

  // The destination name, if the last packet carried one.
  if (s.instruction[0]) {
    char line[INSTRUCTION_MAX + 4];
    fitText(s.instruction, line, sizeof(line), W - 116, 4);
    tft.setTextColor(C_MUTED, C_BG);
    tft.drawString(line, 108, 140, 4);
  }
}

/*
  The glyph box: junction geometry if there is any, otherwise the arrow.

  Separate from drawChrome because geometry arrives at its own rate and must
  NOT drag a full-screen repaint along with it. Treating a new window as a
  chrome change repainted everything at the geometry's update rate, which on
  the panel is a solid flicker - the same mistake as the idle alert band, made
  twice in one week. Only this box is redrawn.

  Below 100 m the arrow always wins, and this function is not called there: a
  drawing has to be read, an arrow is recognised, and there is time to read a
  junction at 300 m and none at 60.

  With nothing received - every ride until the phone side of
  ARCH_ANDROID_AUTO.md 2.2 exists - this is exactly the old behaviour. The
  freshness test matters as much as the presence test: geometry that stopped
  arriving is a picture of a junction already ridden through.
*/
static void drawNavGlyph(const NavState& s, bool far) {
  const int16_t gx = far ? GLYPH_FAR_X : GLYPH_APP_X;
  const int16_t gy = far ? GLYPH_FAR_Y : GLYPH_APP_Y;
  const int16_t gs = far ? GLYPH_FAR_S : GLYPH_APP_S;

  tft.fillRect(gx, gy, gs, gs, C_BG);
  if (geomValid(millis())) geomDraw(tft, gx, gy, gs, C_FG, C_MUTED, C_BG);
  else                     drawManeuver(tft, gx, gy, gs, s.maneuver, C_FG, C_BG);
}

static void drawChrome(const NavState& s, UiScreen scr) {
  switch (scr) {
    case UI_DISCONNECTED:
      drawBanner("PHONE", "DISCONNECTED", C_BG, C_FG);
      return;

    case UI_STALE:
      // The spec says dim the screen. The backlight is hardwired to 3V with no
      // PWM control, so dimming is not available - see HARDWARE.md. Greyed
      // text is the honest substitute until LED moves to a driven pin.
      drawBanner("STALE", "no data 10 s", C_BG, C_MUTED);
      return;

    case UI_ARRIVED:
      drawArrived(s);
      return;

    case UI_IDLE:
      drawIdle(s);
      return;

    case UI_REROUTING:
      // Arrow suppressed. Showing the old maneuver here would be a lie.
      drawBanner("REROUTING", nullptr, C_BG, C_FG);
      return;

    case UI_NAV_NOW: {
      /*
        Under 30 m: framed, not inverted.

        This used to flip the whole screen to black. It was chosen because a
        large luminance change is the most blur- and glare-robust signal this
        panel has, and that reasoning is sound - but it was reported twice from
        the bike as looking like a fault, and reading as a fault is a real
        defect whatever the theory says. A rider who thinks the display has
        glitched at 20 m from a junction is worse off than one who was never
        signalled at all.

        It was also genuinely wrong at night. displaySetNight swaps C_INV_BG to
        ~88% white, so the "inversion" became a full 320x240 flood of near-white
        straight into a dark-adapted eye, at a junction, on an unlit road -
        exactly what night mode exists to prevent. The comment on C_INV_BG
        reasons about a 50 px alert band and this is the whole screen.

        Two 14 px bars instead. Peripheral vision is most sensitive to large
        low-frequency luminance edges, which is what a frame is, and it costs
        8,960 px against 76,800 - about 5 ms rather than 45. It also inverts
        safely at night, because a bar is small enough to be bright without
        flooding anything.
      */
      tft.fillScreen(C_BG);
      /*
        Amber at night, ink by day - and this is the third time this screen has
        had to be talked out of flooding a dark-adapted eye.

        Reported from a night ride: the bars come up white at 20 m and 10 m.
        They do, because C_FG at night is 0xDEFB, ~88% white. Two full-width
        bars are 8,960 px of near-white - far better than the 76,800 the
        inversion used to throw, and still the brightest thing on an otherwise
        dark screen, at a junction, on an unlit road.

        Amber is the right answer rather than merely a dimmer one. It is
        already this project's single accent for "live / attention", so it
        introduces no new vocabulary; long-wavelength light costs far less rod
        adaptation than white at the same apparent brightness; and it survives
        a dimmed backlight and a tinted visor, which is why the palette notes
        made it the one colour night mode keeps.

        By day it stays ink: at the measured 1.17:1 sunlight contrast ratio,
        amber on white is nearly invisible and black is the only thing that
        works. Colour is never load-bearing on its own here - the bars
        APPEARING is the signal, and their colour only tunes the cost.
      */
      const uint16_t barColour = nightMode ? C_ACCENT : C_FG;
      tft.fillRect(0, 0,             W, NOW_BAR_H, barColour);
      tft.fillRect(0, H - NOW_BAR_H, W, NOW_BAR_H, barColour);
      drawManeuver(tft, GLYPH_BIG_X, GLYPH_BIG_Y, GLYPH_BIG_S, s.maneuver,
                   C_FG, C_BG);
      if (s.gpsWeak()) drawGpsWeak(false, C_FG, C_BG);
      return;
    }

    default:
      break;
  }

  tft.fillScreen(C_BG);
  tft.setTextColor(C_FG, C_BG);

  if (scr == UI_NAV_COMMITTED) {
    // No room for a road name once the glyph is this size, and at under 100 m
    // the rider is looking at the junction, not reading.
    drawManeuver(tft, GLYPH_BIG_X, GLYPH_BIG_Y, GLYPH_BIG_S, s.maneuver, C_FG, C_BG);
    if (s.gpsWeak()) drawGpsWeak(false, C_MUTED, C_BG);
    return;
  }

  const bool far = (scr == UI_NAV_FAR);
  const int16_t textY = far ? 6 : 4;
  int16_t maxW = W - 16;                       // 8 px margin each side
  if (s.gpsWeak()) maxW -= GPS_RESERVE_W;

  if (s.instruction[0]) {
    // Two lines where the layout allows it. "BOT Bridge Jct onto Koc..." lost
    // the road name to the ellipsis, which is the half that matters - rule 7
    // says truncating from the end destroys exactly the useful part. Wrapping
    // on a word boundary keeps it, and the far screen has 60 px of headroom
    // above the main row that was doing nothing.
    drawWrapped(s.instruction, 8, textY, maxW, far ? 2 : 1, C_FG);
  }
  if (s.gpsWeak()) drawGpsWeak(true, C_MUTED, C_BG);

  drawNavGlyph(s, far);
}

// --------------------------------------------------------- panel watchdog

/*
  The panel can lose its configuration while the ESP32 carries on running.

  Observed twice on the bench: the display renders correctly, then goes blank
  white, and stays white through a reflash — but comes back after unplugging
  and replugging power. That is the signature of the ILI9341 reverting to its
  power-on state (display off, sleep in) while the MCU keeps writing pixels to
  a controller that has stopped listening. A brownout on the 3.3 V rail will do
  it; so will a glitch on the reset line.

  Requiring a power cycle to recover is tolerable on a desk and not tolerable
  on a motorcycle, where the supply is a 12 V accessory rail and the whole
  assembly is being shaken. So the device asks.

  MISO is wired to GPIO 19, so RDDPM (0x0A) can be read back. Bit 2 is DISON
  (display on) and bit 4 is SLPOUT (awake); both are set on a healthy panel and
  clear after an unwanted reset. Three consecutive bad reads are required before
  acting, because a single garbled read on a marginal bus should not trigger a
  visible re-init.
*/
static const uint32_t PANEL_CHECK_MS   = 2000;
static const uint8_t  PANEL_OK_MASK    = 0x14;   // DISON | SLPOUT
static const uint8_t  PANEL_FAIL_LIMIT = 3;

static uint32_t lastPanelCheckMs = 0;
static uint8_t  panelFailStreak  = 0;
static uint32_t panelRecoveries  = 0;

/*
  Whether the panel can be READ at all.

  The watchdog asks the panel over MISO whether it is still configured. On this
  build MISO is not wired - it was removed deliberately, and the panel works
  perfectly without it, because the display is write-only in normal use.

  A floating MISO reads back as garbage, which never matches DISON|SLPOUT, so
  the watchdog scored three failures at 2 s apiece and re-initialised a healthy
  panel every six seconds. That is a visible full-screen flash, on a device
  whose entire promise is that what it shows can be trusted.

  So the watchdog now proves it can see before it is allowed to act: it reads
  the register once at boot, immediately after init, when the panel is KNOWN to
  be on and awake. If that read does not come back correct, reads are
  impossible on this wiring and the watchdog disables itself for the session.

  The failure it was written for - the panel silently losing its configuration
  while the ESP32 keeps running - is real and was observed. Recovering from it
  needs MISO. Until that wire goes back, the honest position is no watchdog
  rather than one that fires at random, and the log says so out loud.
*/
static bool     panelReadable    = false;


/*
  What makes one notification DIFFERENT from another - the message, not when it
  arrived.

  The band was keyed on notifyAtMs, which is a wall clock reading. Any source
  that re-stamps it repaints the band for no new information: the alerts demo
  did it every loop and strobed the whole screen, and a phone that re-posts the
  same notification once a second would repaint at 1 Hz on a real ride. The
  identity of an alert is its content.

  FNV-1a over kind, source and text. The top bit is forced so the value is
  never zero, which the parked path uses to mean "no alert".
*/
static uint32_t notifyIdentity(const NavState& s) {
  uint32_t h = 2166136261u;
  h = (h ^ s.notifyKind) * 16777619u;
  for (const char* p = s.notifySrc;  *p; ++p) h = (h ^ (uint8_t)*p) * 16777619u;
  for (const char* p = s.notifyText; *p; ++p) h = (h ^ (uint8_t)*p) * 16777619u;
  return h | 0x40000000u;
}

// ------------------------------------------------------------------ boot
/*
  The startup sequence.

  Two rules shaped this, both from the same place: a splash that outlives its
  boot is a splash the rider learns to resent.

    1. The ring reports REAL stages - a third when the panel is up, two thirds
       when the radio is up, closed when the phone is actually connected. It
       genuinely stalls at two thirds while the phone connects, and that stall
       is information. A spinner says "I don't know"; this says "I know exactly
       where I am".

    2. It gives up. If nothing has connected by BOOT_LINK_WAIT_MS the ring
       closes anyway and the waypoint stays HOLLOW rather than filling amber -
       so the mark itself reports the link state, in shape as well as colour,
       and hands straight over to the normal disconnected screen.

  The artwork is the logo: a route line tracing a lowercase j, with the tittle
  as the destination. It is drawn from the same three-segment polyline at every
  size, so the boot mark and the wordmark are visibly one idea rather than two.

  Cost: the largest dirty region here is the 88 px ring bounding box, about
  7,700 px, which at ~1,700 px/ms is 4.5 ms. Everything else is far smaller.
  The whole sequence is under a second unless it is deliberately waiting.
*/

// The logo polyline, in the 64x64 box the mark is designed in.
struct Pt { int16_t x, y; };
static const Pt TRAIL[] = { {38, 26}, {38, 44}, {28, 54}, {14, 54} };
static const uint8_t TRAIL_N = sizeof(TRAIL) / sizeof(TRAIL[0]);
static const Pt TRAIL_DOT = {38, 11};

static const int16_t MARK_CX = 160, MARK_CY = 88;   // ring and mark centre
static const int16_t RING_R  = 44;
static const int16_t MARK_S  = 60;                  // logo box, inside the ring

static const int16_t WORD1_Y = 164;   // "JIFFY",  font 2, 16 px tall
static const int16_t WORD2_Y = 184;   // "TRAILS", font 4, 26 px tall
static const int16_t RULE_Y = 220, RULE_HALF = 56;

/*
  Hold the boot layout to its own arithmetic. Three of the four layout bugs this
  project has shipped were a row overlapping another row by a number nobody had
  written down, so every gap that matters is a compile error if it closes.
*/
static_assert(MARK_CY + RING_R < WORD1_Y,        "ring overlaps the wordmark");
static_assert(WORD1_Y + 16 <= WORD2_Y,           "JIFFY overlaps TRAILS");
static_assert(WORD2_Y + 26 <= RULE_Y,            "TRAILS overlaps the rule");
static_assert(RULE_Y + 2 <= 240,                 "rule falls off the screen");
static_assert(MARK_CX - RULE_HALF >= 0,          "rule falls off the left edge");
// The mark must sit inside the ring with clearance, or the logo touches its own
// progress indicator and the two read as one shape.
static_assert(MARK_S / 2 + 4 < RING_R,           "mark does not fit inside the ring");

static uint16_t bootSweep = 0;      // degrees of ring drawn so far

static inline int16_t markX(int c) { return MARK_CX - MARK_S / 2 + (int)((long)c * MARK_S / 64); }
static inline int16_t markY(int c) { return MARK_CY - MARK_S / 2 + (int)((long)c * MARK_S / 64); }

/*
  A stroke of width w offset along the PERPENDICULAR, not along x.

  maneuvers.cpp offsets its strokes horizontally, which is fine there because no
  glyph stroke is near-horizontal. The logo's final segment is exactly
  horizontal, and a horizontally-offset stroke would collapse every copy onto
  the same line and draw it 1 px thick.
*/
static void strokeThick(int x0, int y0, int x1, int y1, int w, uint16_t c) {
  const float dx = x1 - x0, dy = y1 - y0;
  const float len = sqrtf(dx * dx + dy * dy);
  if (len < 0.5f) return;
  const float nx = -dy / len, ny = dx / len;
  for (int i = -w / 2; i <= w / 2; i++) {
    tft.drawLine(x0 + (int)(nx * i), y0 + (int)(ny * i),
                 x1 + (int)(nx * i), y1 + (int)(ny * i), c);
  }
}

// Text drawn glyph by glyph with extra advance. Tracking is the only second
// "weight" this library has: one font, widely tracked, reads as a different
// weight beside the same font set tight.
static void drawTracked(const char* s, int16_t cx, int16_t y, uint8_t font,
                        int16_t extra, uint16_t fg) {
  int16_t total = 0;
  for (const char* p = s; *p; ++p) total += tft.textWidth(String(*p), font) + extra;
  total -= extra;

  tft.setTextColor(fg, C_BG);
  tft.setTextDatum(TL_DATUM);
  int16_t x = cx - total / 2;
  for (const char* p = s; *p; ++p) {
    char one[2] = { *p, 0 };
    tft.drawString(one, x, y, font);
    x += tft.textWidth(String(*p), font) + extra;
  }
}

// Ring arc from the top, clockwise. Overlapping dots rather than an arc call,
// for the same reason the U-turn uses them: it is the primitive that is
// definitely present, and the overlap hides the quantisation.
static void ringArc(int fromDeg, int toDeg, uint16_t c, int dotR) {
  for (int a = fromDeg; a <= toDeg; a += 2) {
    const float r = a * 3.14159265f / 180.0f;
    tft.fillCircle(MARK_CX + (int)(RING_R * sinf(r)),
                   MARK_CY - (int)(RING_R * cosf(r)), dotR, c);
  }
}

// The trail, drawn to a fraction of its own length. Round joints at every
// vertex reached, which is what keeps a two-segment corner from notching.
static void drawTrail(uint8_t pct, uint16_t c) {
  const int w = MARK_S * 7 / 64;             // 7% stroke, as designed
  float total = 0, seg[TRAIL_N];
  for (uint8_t i = 1; i < TRAIL_N; i++) {
    const float dx = TRAIL[i].x - TRAIL[i-1].x, dy = TRAIL[i].y - TRAIL[i-1].y;
    seg[i] = sqrtf(dx * dx + dy * dy);
    total += seg[i];
  }
  float want = total * pct / 100.0f;

  tft.fillCircle(markX(TRAIL[0].x), markY(TRAIL[0].y), w / 2, c);
  for (uint8_t i = 1; i < TRAIL_N && want > 0; i++) {
    const float f = (want >= seg[i]) ? 1.0f : (want / seg[i]);
    const int ex = TRAIL[i-1].x + (int)((TRAIL[i].x - TRAIL[i-1].x) * f);
    const int ey = TRAIL[i-1].y + (int)((TRAIL[i].y - TRAIL[i-1].y) * f);
    strokeThick(markX(TRAIL[i-1].x), markY(TRAIL[i-1].y), markX(ex), markY(ey), w, c);
    tft.fillCircle(markX(ex), markY(ey), w / 2, c);
    want -= seg[i];
  }
}

void displayBootBegin() {
  tft.fillScreen(C_BG);
  bootSweep = 0;

  // Ring track. Present from the first frame so the ring reads as filling a
  // known distance rather than growing to an unknown one.
  ringArc(0, 360, C_MUTED, 1);

  drawTracked("JIFFY",  MARK_CX, WORD1_Y, 2, 3, C_MUTED);
  drawTracked("TRAILS", MARK_CX, WORD2_Y, 4, 1, C_FG);

  // ~330 ms, eased out: fast away, settling into the corner.
  static const uint8_t EASE[] = { 0, 33, 57, 74, 85, 92, 97, 100 };
  for (uint8_t i = 0; i < sizeof(EASE); i++) {
    drawTrail(EASE[i], C_FG);
    delay(40);
  }
}

void displayBootStage(uint8_t stage) {
  const uint16_t target = (stage >= 3) ? 360 : stage * 120;
  while (bootSweep < target) {
    const uint16_t next = (bootSweep + 8 > target) ? target : bootSweep + 8;
    ringArc(bootSweep, next, C_FG, 2);
    bootSweep = next;
    delay(8);
  }
}

void displayBootFinish(bool linked) {
  displayBootStage(3);

  /*
    The waypoint arrives last, and it is the only element that reports the link.
    Filled amber means a phone is connected; a hollow ring means searching -
    the same two shapes the idle screen's status pip uses, so the vocabulary is
    learned once.

    The three radii are a one-pixel overshoot. It costs 6 ms and it is the
    single detail that makes the thing feel built rather than assembled.
  */
  const int16_t dx = markX(TRAIL_DOT.x), dy = markY(TRAIL_DOT.y);
  const int16_t r  = MARK_S * 6 / 64;
  if (linked) {
    const int16_t pop[] = { r / 2, r + 1, r };
    for (uint8_t i = 0; i < 3; i++) {
      tft.fillCircle(dx, dy, pop[i], (i == 2) ? C_ACCENT : C_FG);
      delay(45);
    }
  } else {
    tft.fillCircle(dx, dy, r, C_FG);
    tft.fillCircle(dx, dy, r - 2, C_BG);       // hollow: searching
  }

  // A rule growing out from the centre is the cheapest possible "ready".
  for (int16_t half = 4; half <= RULE_HALF; half += 8) {
    tft.fillRect(MARK_CX - half, RULE_Y, half * 2, 2, C_MUTED);
    delay(12);
  }
  delay(260);
  displayInvalidate();
}

// ------------------------------------------------------------------- api

void displayBegin() {
  tft.init();
  tft.setRotation(ROTATION);
  tft.fillScreen(C_BG);

  // Probe read capability while the answer is known. The panel has just been
  // initialised, so it IS on and awake; if the register does not say so, the
  // read path is broken rather than the panel.
  const uint8_t probe = tft.readcommand8(0x0A);
  panelReadable = ((probe & PANEL_OK_MASK) == PANEL_OK_MASK);
  Serial.printf("display: panel read probe 0x%02X - watchdog %s\n", probe,
                panelReadable ? "armed" : "DISABLED (MISO not wired)");

  dist.setColorDepth(16);
  sprite_ok = (dist.createSprite(SPR_W, SPR_H) != nullptr);
  if (!sprite_ok) Serial.println(F("display: sprite alloc FAILED - flickery fallback"));

  displayInvalidate();
}

void displayRender(const NavState& s) {
  const UiScreen scr = screenFor(s);
  const bool navScreen = (scr >= UI_NAV_FAR);

  // Only fields the current screen actually draws may force a redraw.
  // Including the maneuver unconditionally would repaint the REROUTING banner
  // every time a suppressed arrow changed underneath it.
  bool changed = !chromeValid || scr != lastScreen;
  if (navScreen && !changed) {
    changed = (s.maneuver != lastManeuver)
           || (s.gpsWeak() != lastGpsWeak)
           || (strncmp(s.instruction, lastInstruction, INSTRUCTION_MAX) != 0);
  }

  // The idle screen has no distance field, so nothing else would ever repaint
  // it — the clock drew once at boot and then sat there, which is worse than no
  // clock because a wrong time still looks like a right one. This is the whole
  // reason chrome-only screens need their own change key.
  if (scr == UI_IDLE && !changed) {
    const uint16_t clockKey =
        (uint16_t)(s.clockValid ? (s.clockHour * 60 + s.clockMin + 1) : 0);
    changed = (clockKey != lastClockKey) || (s.phoneBatteryPct != lastBattery);
  }

  const BandContent band = bandFor(s, scr, millis());

  /*
    Idle and arrived paint the WHOLE screen, so an alert arriving or expiring
    there is a chrome change rather than a band change - the alert covers the
    clock, and when it expires the clock has to come back.

    This is also the wiring that was missing. drawBand has had a branch for
    UI_IDLE and UI_ARRIVED since alerts were added, giving a message the top of
    the screen instead of a 50 px strip, and it was unreachable: the early
    return on !navScreen sat above the band block, so the band never ran on
    those two screens at all. The geometry was written and never called, which
    is why the full-screen idle notification was reported as missing. It was.
  */
  const bool fullScreenAlert = (scr == UI_IDLE || scr == UI_ARRIVED);

  // Keyed on the alert's identity, not just its kind. Testing the kind alone
  // would repaint an unchanged call band on every loop iteration - which at
  // this loop rate is a solid flicker - and would also miss a second caller
  // arriving while the first band is still up, since both are BAND_CALL.
  const uint32_t idleKey = (band == BAND_CALL)   ? (0x0C000000u | s.callState)
                         : (band == BAND_NOTIFY) ? notifyIdentity(s)
                         : 0;
  if (fullScreenAlert && idleKey != lastIdleKey) changed = true;

  if (changed) {
    drawChrome(s, scr);
    lastScreen   = scr;
    lastManeuver = s.maneuver;
    lastGpsWeak  = s.gpsWeak();
    lastGeomKey  = geomKey(millis());
    snprintf(lastInstruction, sizeof(lastInstruction), "%s", s.instruction);
    chromeValid  = true;
    lastDist     = -1;               // chrome repaint wiped the number
    lastClockKey = (uint16_t)(s.clockValid ? (s.clockHour * 60 + s.clockMin + 1) : 0);
    lastBattery  = s.phoneBatteryPct;
    lastFooter   = 0xFFFFFFFFu;
  }

  /*
    Geometry moves at its own rate and owns only the glyph box, so it gets a
    targeted redraw. Folding it into the chrome test instead repainted the
    whole screen every time a window arrived, which at the demo's rate was a
    solid flicker and at a real 1 Hz feed would be a flash every second.
  */
  if (scr == UI_NAV_FAR || scr == UI_NAV_APPROACH) {
    const uint32_t gk = geomKey(millis());
    if (gk != lastGeomKey) { drawNavGlyph(s, scr == UI_NAV_FAR); lastGeomKey = gk; }
  }

  // Idle and arrived: the chrome above has just repainted the screen, so an
  // alert only needs painting on top of it. Nothing else on these screens
  // changes per-frame, so there is no distance field to fall through to.
  if (fullScreenAlert) {
    if (changed && idleKey) drawBand(s, band, scr);
    lastIdleKey = idleKey;
    return;
  }

  if (!navScreen) return;

  // The band is re-evaluated every frame because BAND_NOTIFY expires on a
  // timer, not on an event — nothing arrives to tell us it is over.
  uint32_t bandKey;
  switch (band) {
    case BAND_FOOTER: bandKey = ((uint32_t)s.eta_min << 16) | s.remaining_100m; break;
    case BAND_CALL:   bandKey = 0x0C000000u | s.callState; break;
    case BAND_NOTIFY: bandKey = notifyIdentity(s); break;
    // scr is folded in below, so an alert that outlives a screen change is
    // redrawn against the new ground rather than left on the old one.
    default:          bandKey = 0; break;
  }
  bandKey ^= (uint32_t)band << 28;
  if (bandKey != lastFooter) { drawBand(s, band, scr); lastFooter = bandKey; }

  // Rendered as given. The phone has already quantised to the NAV_DATA.md
  // bands, so the digits skip at speed; quantising again here would round a
  // rounded value and could disagree with the band screenFor() picked.
  if ((int32_t)s.dist_m == lastDist) return;
  lastDist = s.dist_m;

  // Positive polarity now on every nav screen; the turn-now screen is framed
  // rather than inverted, so nothing here needs the inverted palette.
  if (scr == UI_NAV_NOW)      pushDistance(s.dist_m, SPR_X, DIST_Y_OTHER, C_FG, C_BG);
  else if (scr == UI_NAV_FAR) pushDistance(s.dist_m, SPR_X, DIST_Y_FAR,   C_FG, C_BG);
  else                        pushDistance(s.dist_m, SPR_X, DIST_Y_OTHER, C_FG, C_BG);
}

void displaySetNight(bool on) {
  if (on == nightMode) return;
  nightMode = on;

  if (on) {
    /*
      Night text is grey, not white — and this is the part that matters.

      Inverting already cuts total emitted light by roughly 6-8x, because a
      typical nav screen is only 10-15% ink: black-on-white drives ~85% of the
      panel to full transmission, white-on-black drives ~12%. But the glyphs
      themselves would still be at full backlight, and they are exactly what
      the eye fixates on.

      On a transmissive panel a grey pixel genuinely transmits less light than
      a white one, so dropping the text to ~70% is real dimming with no
      hardware at all. Rod dark adaptation takes 20-30 minutes to build and is
      lost almost instantly, so every full-white glance on an unlit road costs
      real seeing distance.

      This is a stopgap. The proper answer is PWM on the backlight, which needs
      a MOSFET (see HARDWARE.md) — and that work is needed on the Sharp Memory
      LCD path too, where a front light must be dimmable from day one.
    */
    /*
      Raised from ~70% to ~88% after bench testing at night. The theory said
      dimmer text saves dark adaptation; the panel disagreed. This is a cheap
      TN-type ILI9341 whose black level washes out when viewed off-axis from
      above — which is exactly the handlebar viewing angle — so the background
      is never truly black and a 70% grey did not stand far enough off it.
      Contrast against a grey ground beat absolute light output. The proper fix
      is still backlight PWM, which lowers both together and would let the text
      go back down.
    */
    C_BG = TFT_BLACK; C_FG = 0xDEFB;          // ~88% white
    // The alert band still has to be an unmissable luminance event, but a
    // full-white block at night is the flash this whole mode exists to avoid.
    // Grey block, black text: still a step change against a near-black ground.
    C_INV_BG = 0xDEFB; C_INV_FG = TFT_BLACK;
    C_MUTED  = 0x8410;                        // ~50%, clearly below the text
  } else {
    C_BG = TFT_WHITE; C_FG = TFT_BLACK;
    C_INV_BG = TFT_BLACK; C_INV_FG = TFT_WHITE;
    C_MUTED  = 0x8410;
  }

  displayInvalidate();
}


void displayTick() {
  // A watchdog that cannot observe cannot protect. See panelReadable.
  if (!panelReadable) return;

  const uint32_t now = millis();
  if (now - lastPanelCheckMs < PANEL_CHECK_MS) return;
  lastPanelCheckMs = now;

  const uint8_t pm = tft.readcommand8(0x0A);

  if ((pm & PANEL_OK_MASK) == PANEL_OK_MASK) {
    panelFailStreak = 0;
    return;
  }

  if (++panelFailStreak < PANEL_FAIL_LIMIT) return;
  panelFailStreak = 0;
  panelRecoveries++;

  Serial.printf("display: panel lost config (RDDPM 0x%02X), re-init #%lu\n",
                pm, (unsigned long)panelRecoveries);

  tft.init();
  tft.setRotation(ROTATION);
  displayInvalidate();
}
