/*
  ui_mock.ino - the nav interface, driven by a scripted ride.

  No BLE, no phone. A canned ride plays through the display exactly as the
  real thing will: distances count down at 1 Hz with the quantisation Google
  Maps actually uses, maneuvers change, and every failure state fires on
  schedule.

  The point is to finalise the interface before writing any BLE code. What
  gets judged here is glanceability at mount distance, not correctness of
  data - the data is fake on purpose.

  Serial commands (115200), for reviewing a state without waiting:
    0-3  jump to a distance band      4  idle screen
    r    rerouting    s  stale    d  disconnected
    n    next leg     p  pause / resume

  Data behaviour taken from docs/NAV_DATA.md:
    - distance quantisation bands (100 m / 50 m / 10 m)
    - values are rounded to the band, so digits visibly skip at speed
    - progressMax drifts, so remaining distance is recomputed, never cached
    - traffic bar uses the real progressSegments colorInt values

  Display rules from docs/BLE_PROTOCOL.md. One deliberate deviation, at STALE
  - see the comment there.
*/

#include <TFT_eSPI.h>

TFT_eSPI    tft  = TFT_eSPI();
TFT_eSprite dist = TFT_eSprite(&tft);   // distance field only - a full-screen
                                        // sprite will not fit in plain ESP32 RAM

static const uint8_t ROTATION = 1;      // landscape
static const int16_t W = 320;
static const int16_t H = 240;

// ---------------------------------------------------------------- palette

static const uint16_t C_BG    = TFT_WHITE;
static const uint16_t C_FG    = TFT_BLACK;
static const uint16_t C_MUTED = 0x8410;   // mid grey, de-emphasised text

// progressSegments colorInt values from NAV_DATA.md, converted to RGB565
static const uint16_t C_TRAF_GREY  = 0x73AE;
static const uint16_t C_TRAF_BLUE  = 0x05BF;
static const uint16_t C_TRAF_AMBER = 0xFD00;
static const uint16_t C_TRAF_RED   = 0xF9A6;

// ------------------------------------------------------------- maneuvers

enum : uint8_t {
  MV_UNKNOWN = 0x00, MV_CONTINUE = 0x01, MV_LEFT = 0x02, MV_RIGHT = 0x03,
  MV_SLIGHT_LEFT = 0x04, MV_SLIGHT_RIGHT = 0x05, MV_UTURN = 0x0A,
  MV_MERGE = 0x0C, MV_ROUNDABOUT = 0x11, MV_DESTINATION = 0x14
};

// ----------------------------------------------------------------- state

enum UiState : uint8_t {
  ST_NAV, ST_IDLE, ST_REROUTING, ST_STALE, ST_DISCONNECTED
};

struct Leg { uint8_t mv; const char* road; int32_t start_m; };

// A plausible Bengaluru route. Legs kept short so a full review runs in a few
// minutes rather than a real journey.
static const Leg RIDE[] = {
  { MV_CONTINUE,     "Old Madras Rd",        700 },
  { MV_RIGHT,        "TC Palya Main Rd",     620 },
  { MV_SLIGHT_RIGHT, "Horamavu Agara Rd",    480 },
  { MV_ROUNDABOUT,   "Hennur Main Rd",       550 },
  { MV_LEFT,         "Kammanahalli Main Rd", 430 },
  { MV_MERGE,        "Outer Ring Rd",        600 },
  { MV_UTURN,        "Banaswadi Rd",         380 },
  { MV_DESTINATION,  "Arriving",             260 },
};
static const uint8_t N_LEGS = sizeof(RIDE) / sizeof(RIDE[0]);

static uint8_t  leg       = 0;
static int32_t  dist_m    = 700;
static int32_t  route_m   = 8400;      // progressMax, drifts like the real thing
static int32_t  travelled = 1200;      // start mid-route so the traffic bar
                                       // shows a travelled segment immediately
static UiState  state     = ST_NAV;
static bool     paused    = false;
static uint32_t lastTick  = 0;
static uint32_t stateUntil = 0;        // when a transient state ends
static uint8_t  lastDrawn = 255;       // what the last full redraw was
static int32_t  lastDist  = -1;

// 15 m/s is about 54 km/h - a fair Bengaluru mix of arterial and crawling.
static const int32_t SPEED_MPS = 15;

// Screen is two columns: maneuver on the left, distance on the right.
//
// Sizing these by eye failed twice, so the real numbers, from the library's
// own width tables:
//
//   font 8  digits 55 px wide, 75 tall  ->  "700" is 165 px
//   font 6  digits 27 px wide, 48 tall  ->  "1.2" is  69 px
//   font 4  'm' 22 px, "km" 34 px, 26 tall
//
// 165 + 34 + padding is most of the screen, which leaves the arrow about
// 104 px. The sprite is opaque, so anything drawn to its left must stay
// inside ARROW_ZONE or it gets painted over on the next tick.
static const int16_t SPR_X = 112;   // sprite left edge
static const int16_t SPR_W = 208;   // 112 + 208 = 320, flush to the edge
static const int16_t SPR_H = 80;    // font 8 is 75 px tall
static const int16_t ARROW_ZONE = SPR_X - 4;

// --------------------------------------------------------------- helpers

// NAV_DATA.md: Maps rounds to the band rather than stepping through it, so at
// speed the digits visibly skip. Reproduced here because it changes how the
// display feels, and a smooth countdown would flatter the design unfairly.
static int32_t quantise(int32_t m) {
  if (m > 1000) return (m / 100) * 100;
  if (m >= 300) return (m /  50) *  50;
  return (m / 10) * 10;
}

// Bands drive the whole layout. 255 means "not a nav screen".
static uint8_t bandOf(int32_t m) {
  if (state != ST_NAV) return 255;
  if (m <  30)  return 3;
  if (m < 100)  return 2;
  if (m <= 500) return 1;
  return 0;
}

// ------------------------------------------------------------- maneuvers

// Vector paths, not bitmaps - scalable and a fraction of the flash.
//
// Every glyph is expressed as percentages of an s-by-s box whose top-left is
// (x, y), so no glyph can escape its box no matter which maneuver it is.
// The previous version took a centre point and grew the turn head to one
// side, which made the real extent depend on which way the arrow pointed -
// a right turn overran to the right, a left turn overran to the left, and
// the layout could not reserve space for both. Layout now reserves one box
// and the glyph is guaranteed to fit inside it.
static void drawManeuver(int x, int y, int s, uint8_t mv, uint16_t fg, uint16_t bg) {
  auto P = [&](int pct) { return (int)((long)pct * s / 100); };
  auto X = [&](int pct) { return x + P(pct); };
  auto Y = [&](int pct) { return y + P(pct); };

  // A stroke of thickness P(w) from one point to another, for the diagonals.
  auto thickLine = [&](int x0, int y0, int x1, int y1, int w) {
    for (int i = -w / 2; i <= w / 2; i++) tft.drawLine(x0 + i, y0, x1 + i, y1, fg);
  };

  switch (mv) {
    case MV_CONTINUE:
      tft.fillRect(X(42), Y(35), P(16), P(60), fg);
      tft.fillTriangle(X(24), Y(40), X(76), Y(40), X(50), Y(6), fg);
      break;

    case MV_RIGHT:
      tft.fillRect(X(24), Y(46), P(15), P(50), fg);            // stem
      tft.fillRect(X(24), Y(46), P(44), P(15), fg);            // elbow
      tft.fillTriangle(X(62), Y(28), X(62), Y(79), X(96), Y(53), fg);
      break;

    case MV_LEFT:
      tft.fillRect(X(61), Y(46), P(15), P(50), fg);
      tft.fillRect(X(32), Y(46), P(44), P(15), fg);
      tft.fillTriangle(X(38), Y(28), X(38), Y(79), X(4), Y(53), fg);
      break;

    case MV_SLIGHT_RIGHT:
      tft.fillRect(X(42), Y(58), P(15), P(38), fg);
      thickLine(X(50), Y(62), X(74), Y(34), P(15));
      tft.fillTriangle(X(88), Y(14), X(58), Y(24), X(78), Y(48), fg);
      break;

    case MV_SLIGHT_LEFT:
      tft.fillRect(X(43), Y(58), P(15), P(38), fg);
      thickLine(X(50), Y(62), X(26), Y(34), P(15));
      tft.fillTriangle(X(12), Y(14), X(42), Y(24), X(22), Y(48), fg);
      break;

    case MV_UTURN: {
      // Arc drawn as overlapping dots rather than stacked circle outlines
      // with the lower half erased - erasing clipped the legs.
      const int cx = X(50), cy = Y(42), r = P(22), t = P(7);
      for (int i = 0; i <= 24; i++) {
        const float a = 3.14159265f * i / 24.0f;
        tft.fillCircle(cx - (int)(r * cosf(a)), cy - (int)(r * sinf(a)), t, fg);
      }
      tft.fillRect(X(21), Y(42), P(14), P(54), fg);             // left leg, down
      tft.fillRect(X(65), Y(42), P(14), P(22), fg);             // right leg, short
      tft.fillTriangle(X(58), Y(60), X(86), Y(60), X(72), Y(92), fg);
      break;
    }

    case MV_MERGE:
      tft.fillRect(X(42), Y(30), P(15), P(66), fg);
      tft.fillTriangle(X(25), Y(34), X(75), Y(34), X(50), Y(4), fg);
      thickLine(X(16), Y(94), X(44), Y(64), P(11));
      break;

    case MV_ROUNDABOUT: {
      const int cx = X(45), cy = Y(44), r = P(24);
      for (int k = 0; k < P(10); k++) tft.drawCircle(cx, cy, r - k, fg);
      tft.fillRect(X(40), Y(66), P(10), P(30), fg);             // entry, below
      tft.fillRect(X(67), Y(39), P(18), P(10), fg);             // exit, right
      tft.fillTriangle(X(82), Y(32), X(82), Y(56), X(97), Y(44), fg);
      break;
    }

    case MV_DESTINATION:
      tft.fillRect(X(28), Y(10), P(8), P(84), fg);              // pole
      tft.fillTriangle(X(36), Y(12), X(82), Y(30), X(36), Y(48), fg);
      break;

    default:  // MV_UNKNOWN - never guess an arrow, say so instead
      tft.setTextDatum(MC_DATUM);
      tft.setTextColor(fg, bg);
      tft.drawString("?", X(50), Y(50), 6);
      break;
  }
}

// --------------------------------------------------------------- drawing

static void drawTrafficBar(int y) {
  // Segment [0] is always the travelled portion, per NAV_DATA.md.
  const int done = (route_m > 0) ? (int)((int64_t)W * travelled / route_m) : 0;
  const int rest = W - done;
  tft.fillRect(0, y, done, 16, C_TRAF_GREY);
  tft.fillRect(done,                    y, rest * 55 / 100, 16, C_TRAF_BLUE);
  tft.fillRect(done + rest * 55 / 100,  y, rest * 25 / 100, 16, C_TRAF_AMBER);
  tft.fillRect(done + rest * 80 / 100,  y, rest - rest * 80 / 100, 16, C_TRAF_RED);
}

// Only the distance field is a sprite. Redrawing a font-8 number straight to
// the panel every second flickers badly; the rest of the screen is static
// within a band, so it costs nothing to leave alone.
static void pushDistance(int32_t m, int x, int y, uint16_t fg, uint16_t bg) {
  dist.fillSprite(bg);
  dist.setTextColor(fg, bg);

  char num[10];
  const char* unit;
  uint8_t numFont;

  if (m > 1000) {
    snprintf(num, sizeof(num), "%ld.%ld", (long)(m / 1000), (long)((m % 1000) / 100));
    unit = "km"; numFont = 6;
  } else {
    snprintf(num, sizeof(num), "%ld", (long)m);
    unit = "m";  numFont = 8;
  }

  // Right-align the whole block against the sprite's right edge and let it
  // grow leftwards, measuring rather than assuming. Hard-coding an origin is
  // what clipped the leading digit: "700" at font 8 is 165 px, and anything
  // narrower than that silently loses characters off the left.
  const int16_t pad   = 8;
  const int16_t unitW = dist.textWidth(unit, 4);

  dist.setTextDatum(MR_DATUM);
  dist.drawString(unit, SPR_W - pad, SPR_H / 2 + 16, 4);
  dist.drawString(num,  SPR_W - pad - unitW - 6, SPR_H / 2, numFont);

  dist.pushSprite(x, y);
}

static void drawBanner(const char* line1, const char* line2, uint16_t bg, uint16_t fg) {
  tft.fillScreen(bg);
  tft.setTextColor(fg, bg);
  tft.setTextDatum(MC_DATUM);
  tft.drawString(line1, W / 2, line2 ? H / 2 - 26 : H / 2, 4);
  if (line2) tft.drawString(line2, W / 2, H / 2 + 22, 4);
}

static void drawChrome(uint8_t band) {
  if (band == 3) {
    // Inverted below 30 m. A change of state you cannot miss at a junction.
    tft.fillScreen(TFT_BLACK);
    drawManeuver(4, 76, 104, RIDE[leg].mv, TFT_WHITE, TFT_BLACK);
    return;
  }

  tft.fillScreen(C_BG);
  tft.setTextColor(C_FG, C_BG);

  if (band == 0) {
    tft.setTextDatum(TL_DATUM);
    tft.drawString(RIDE[leg].road, 8, 6, 4);
    drawManeuver(12, 96, 64, RIDE[leg].mv, C_FG, C_BG);

    tft.setTextColor(C_MUTED, C_BG);
    tft.setTextDatum(BL_DATUM);
    tft.drawString("Arrive 12:08", 8, 200, 2);
    tft.setTextDatum(BR_DATUM);
    char buf[24];
    const int32_t rem = route_m - travelled;
    snprintf(buf, sizeof(buf), "%ld.%ld km left", (long)(rem / 1000), (long)((rem % 1000) / 100));
    tft.drawString(buf, 312, 200, 2);
    drawTrafficBar(206);
  } else if (band == 1) {
    tft.setTextDatum(TL_DATUM);
    tft.drawString(RIDE[leg].road, 8, 4, 4);
    drawManeuver(8, 92, 92, RIDE[leg].mv, C_FG, C_BG);
  } else if (band == 2) {
    drawManeuver(4, 76, 104, RIDE[leg].mv, C_FG, C_BG);
  }
}

static void drawIdle() {
  tft.fillScreen(C_BG);
  tft.setTextColor(C_FG, C_BG);
  tft.setTextDatum(MC_DATUM);
  tft.drawString("12:08", W / 2, 82, 7);
  tft.setTextColor(C_MUTED, C_BG);
  tft.drawString("18.4 km   42 min   avg 26 km/h", W / 2, 170, 2);
}

static void render() {
  switch (state) {
    case ST_IDLE:
      if (lastDrawn != 250) { drawIdle(); lastDrawn = 250; }
      return;
    case ST_REROUTING:
      // Arrow suppressed. Showing the old maneuver here would be a lie.
      if (lastDrawn != 251) { drawBanner("REROUTING", nullptr, C_BG, C_FG); lastDrawn = 251; }
      return;
    case ST_STALE:
      // The spec says dim the screen. The backlight is hardwired to 3V with no
      // PWM control, so dimming is not available - see HARDWARE.md. Greyed
      // text is the honest substitute until LED moves to a driven pin.
      if (lastDrawn != 252) { drawBanner("STALE", "no data 10 s", C_BG, C_MUTED); lastDrawn = 252; }
      return;
    case ST_DISCONNECTED:
      if (lastDrawn != 253) { drawBanner("PHONE", "DISCONNECTED", C_BG, C_FG); lastDrawn = 253; }
      return;
    default:
      break;
  }

  const uint8_t band = bandOf(dist_m);
  if (band != lastDrawn) { drawChrome(band); lastDrawn = band; lastDist = -1; }

  const int32_t q = quantise(dist_m);
  if (q == lastDist) return;
  lastDist = q;

  if (band == 3)      pushDistance(q, SPR_X, 88, TFT_WHITE, TFT_BLACK);
  else if (band == 0) pushDistance(q, SPR_X, 60, C_FG, C_BG);
  else                pushDistance(q, SPR_X, 88, C_FG, C_BG);
}

// ---------------------------------------------------------------- script

static void nextLeg() {
  leg = (leg + 1) % N_LEGS;
  dist_m = RIDE[leg].start_m;
  lastDrawn = 255;

  // progressMax drifts constantly, and not only on reroutes - NAV_DATA.md
  // measured 7486 -> 7780 -> 7659 within 45 s. Never cache remaining distance.
  route_m += (leg % 2) ? 180 : -140;

  // Fire a failure state between legs so the review covers them. These are
  // the screens that matter more than the happy path.
  if (leg == 2) { state = ST_REROUTING;    stateUntil = millis() + 5000; }
  if (leg == 4) { state = ST_STALE;        stateUntil = millis() + 5000; }
  if (leg == 6) { state = ST_DISCONNECTED; stateUntil = millis() + 5000; }
  if (leg == 0) { state = ST_IDLE;         stateUntil = millis() + 6000; travelled = 0; }
}

static void handleSerial() {
  if (!Serial.available()) return;
  const char c = Serial.read();
  lastDrawn = 255;
  switch (c) {
    case '0': state = ST_NAV; dist_m = 700; break;
    case '1': state = ST_NAV; dist_m = 350; break;
    case '2': state = ST_NAV; dist_m =  80; break;
    case '3': state = ST_NAV; dist_m =  20; break;
    case '4': state = ST_IDLE; break;
    case 'r': state = ST_REROUTING;    stateUntil = millis() + 8000; break;
    case 's': state = ST_STALE;        stateUntil = millis() + 8000; break;
    case 'd': state = ST_DISCONNECTED; stateUntil = millis() + 8000; break;
    case 'n': nextLeg(); break;
    case 'p': paused = !paused; Serial.println(paused ? F("paused") : F("running")); break;
    default: break;
  }
}

void setup() {
  Serial.begin(115200);
  delay(200);

  tft.init();
  tft.setRotation(ROTATION);
  tft.fillScreen(C_BG);

  dist.setColorDepth(16);
  if (!dist.createSprite(SPR_W, SPR_H)) {
    Serial.println(F("sprite alloc FAILED - reduce size"));
  }

  Serial.println(F("\nui_mock - scripted ride, no BLE"));
  Serial.println(F("keys: 0-3 band  4 idle  r reroute  s stale  d disconnect  n next  p pause\n"));

  lastTick = millis();
}

void loop() {
  handleSerial();

  const uint32_t now = millis();

  if (stateUntil && now > stateUntil) { state = ST_NAV; stateUntil = 0; lastDrawn = 255; }

  // 1 Hz, matching the real packet rate.
  if (!paused && state == ST_NAV && now - lastTick >= 1000) {
    lastTick = now;
    dist_m    -= SPEED_MPS;
    travelled += SPEED_MPS;
    if (travelled > route_m) travelled = route_m;
    if (dist_m <= 0) nextLeg();
  }

  render();
}
