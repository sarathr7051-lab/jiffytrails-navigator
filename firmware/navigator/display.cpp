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
static const int16_t GLYPH_FAR_X =  8, GLYPH_FAR_Y = 88,  GLYPH_FAR_S = 84;
static const int16_t GLYPH_APP_X =  6, GLYPH_APP_Y = 86,  GLYPH_APP_S = 96;
static const int16_t GLYPH_BIG_X =  4, GLYPH_BIG_Y = 76,  GLYPH_BIG_S = 104;
static_assert(GLYPH_FAR_X + GLYPH_FAR_S <= 108, "far glyph runs under the sprite");
static_assert(GLYPH_BIG_X + GLYPH_BIG_S <= ARROW_ZONE, "glyph runs under the sprite");
static_assert(GLYPH_APP_X + GLYPH_APP_S <= ARROW_ZONE, "glyph runs under the sprite");

static const int16_t DIST_Y_FAR   = 60;   // far band lifts the number to make
static const int16_t DIST_Y_OTHER = 88;   // room for the footer line

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

void displayInvalidate() {
  chromeValid = false;
  lastDist    = -1;
  lastFooter  = 0xFFFFFFFFu;
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

  if (m > 1000) {
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
static void drawFitted(const char* text, int16_t x, int16_t y, int16_t maxW, uint8_t font) {
  char buf[ALERT_TEXT_MAX + 4];
  snprintf(buf, sizeof(buf), "%s", text);
  if (tft.textWidth(buf, font) <= maxW) {
    tft.drawString(buf, x, y, font);
    return;
  }
  size_t n = strlen(buf);
  while (n > 1) {
    buf[--n] = '\0';
    char probe[ALERT_TEXT_MAX + 4];
    snprintf(probe, sizeof(probe), "%s...", buf);
    if (tft.textWidth(probe, font) <= maxW) { tft.drawString(probe, x, y, font); return; }
  }
}

static void drawBand(const NavState& s, BandContent band) {
  if (band == BAND_BLANK) {
    tft.fillRect(0, BAND_Y, W, BAND_H, C_BG);
    return;
  }

  if (band == BAND_FOOTER) {
    tft.fillRect(0, BAND_Y, W, BAND_H, C_BG);
    tft.setTextColor(C_MUTED, C_BG);

    char buf[24];
    // NAV_DATA.md measured progressMax drifting 7486 -> 7780 -> 7659 within
    // 45 s, so a cached remaining distance is wrong within a minute.
    if (s.eta_min) {
      snprintf(buf, sizeof(buf), "%u min", (unsigned)s.eta_min);
      tft.setTextDatum(BL_DATUM);
      tft.drawString(buf, 8, 228, 2);
    }
    if (s.remaining_100m) {
      snprintf(buf, sizeof(buf), "%u.%u km left",
               (unsigned)(s.remaining_100m / 10), (unsigned)(s.remaining_100m % 10));
      tft.setTextDatum(BR_DATUM);
      tft.drawString(buf, 312, 228, 2);
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

  tft.fillRect(0, BAND_Y, W, BAND_H, C_INV_BG);
  tft.setTextColor(C_INV_FG, C_INV_BG);

  tft.setTextDatum(TL_DATUM);
  tft.drawString(tag, 8, BAND_Y + 5, 2);

  // Body gets font 4 — this is the one thing in the band worth reading, and
  // font 2 at 700 mm is below the legible floor on a moving bike.
  tft.setTextDatum(TL_DATUM);
  if (body[0]) drawFitted(body, 8, BAND_Y + 21, W - 16, 4);
  else         drawFitted(isCall ? "incoming" : "notification", 8, BAND_Y + 21, W - 16, 4);
}

// Never a maneuver here, whatever the last packet said — BLE_PROTOCOL.md.
//
// The clock is the point of this screen. A handlebar clock is genuinely useful
// stopped at a signal, and it is the one thing worth showing when there is no
// route. It comes from the phone: the device has no RTC and no network, so
// there is no other source, and without one this screen has nothing to say.
static void drawIdle(const NavState& s) {
  tft.fillScreen(C_BG);

  if (s.clockValid) {
    char buf[8];
    snprintf(buf, sizeof(buf), "%u:%02u", (unsigned)s.clockHour, (unsigned)s.clockMin);
    tft.setTextColor(C_FG, C_BG);
    tft.setTextDatum(MC_DATUM);
    tft.drawString(buf, W / 2, 104, 7);   // font 7, 48 px — digits and colon
  } else {
    // No clock yet. Say what is actually true rather than inventing a time.
    tft.setTextColor(C_FG, C_BG);
    tft.setTextDatum(MC_DATUM);
    tft.setTextSize(2);
    tft.drawString("READY", W / 2, 104, 4);
    tft.setTextSize(1);
  }

  tft.setTextColor(C_MUTED, C_BG);
  tft.setTextDatum(MC_DATUM);
  tft.drawString("no route", W / 2, 168, 2);

  // Battery below 20% only. A permanent percentage is a re-glance magnet —
  // something you check because it is there, not because you need it.
  if (s.phoneBatteryPct && s.phoneBatteryPct <= 20) {
    char buf[20];
    snprintf(buf, sizeof(buf), "phone %u%%", (unsigned)s.phoneBatteryPct);
    tft.setTextDatum(BR_DATUM);
    tft.drawString(buf, 312, 232, 2);
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
      // Inverted below 30 m. A change of state you cannot miss at a junction.
      tft.fillScreen(C_INV_BG);
      drawManeuver(tft, GLYPH_BIG_X, GLYPH_BIG_Y, GLYPH_BIG_S, s.maneuver,
                   C_INV_FG, C_INV_BG);
      if (s.gpsWeak()) drawGpsWeak(false, C_INV_FG, C_INV_BG);
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
    char line[INSTRUCTION_MAX + 4];
    fitText(s.instruction, line, sizeof(line), maxW, 4);
    tft.setTextDatum(TL_DATUM);
    tft.drawString(line, 8, textY, 4);
  }
  if (s.gpsWeak()) drawGpsWeak(true, C_MUTED, C_BG);

  if (far) drawManeuver(tft, GLYPH_FAR_X, GLYPH_FAR_Y, GLYPH_FAR_S, s.maneuver, C_FG, C_BG);
  else     drawManeuver(tft, GLYPH_APP_X, GLYPH_APP_Y, GLYPH_APP_S, s.maneuver, C_FG, C_BG);
}

// ------------------------------------------------------------------- api

void displayBegin() {
  tft.init();
  tft.setRotation(ROTATION);
  tft.fillScreen(C_BG);

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

  if (changed) {
    drawChrome(s, scr);
    lastScreen   = scr;
    lastManeuver = s.maneuver;
    lastGpsWeak  = s.gpsWeak();
    snprintf(lastInstruction, sizeof(lastInstruction), "%s", s.instruction);
    chromeValid  = true;
    lastDist     = -1;               // chrome repaint wiped the number
    lastFooter   = 0xFFFFFFFFu;
  }

  if (!navScreen) return;

  // The band is re-evaluated every frame because BAND_NOTIFY expires on a
  // timer, not on an event — nothing arrives to tell us it is over.
  const BandContent band = bandFor(s, scr, millis());
  uint32_t bandKey;
  switch (band) {
    case BAND_FOOTER: bandKey = ((uint32_t)s.eta_min << 16) | s.remaining_100m; break;
    case BAND_CALL:   bandKey = 0x0C000000u | s.callState; break;
    case BAND_NOTIFY: bandKey = s.notifyAtMs | 0x40000000u; break;
    default:          bandKey = 0; break;
  }
  bandKey ^= (uint32_t)band << 28;
  if (bandKey != lastFooter) { drawBand(s, band); lastFooter = bandKey; }

  // Rendered as given. The phone has already quantised to the NAV_DATA.md
  // bands, so the digits skip at speed; quantising again here would round a
  // rounded value and could disagree with the band screenFor() picked.
  if ((int32_t)s.dist_m == lastDist) return;
  lastDist = s.dist_m;

  if (scr == UI_NAV_NOW)      pushDistance(s.dist_m, SPR_X, DIST_Y_OTHER, C_INV_FG, C_INV_BG);
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

void displayTick() {
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
