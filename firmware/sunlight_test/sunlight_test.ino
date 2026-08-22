/*
  sunlight_test.ino — Stage 4 Test B, the daylight readability gate.

  This is the test that can invalidate the whole display choice, so it is
  worth doing properly. The library graphics test is not a fair proxy: it
  draws thin coloured lines on black, which is close to the worst case and
  nothing like the real UI.

  Cycles the six screens that matter, six seconds each, and prints the
  current screen over serial so photographs can be matched up afterwards.

    0  FAR        > 500 m   instruction + distance + ETA + traffic bar
    1  MID    500-100 m     large distance, arrow
    2  NEAR     < 100 m     full-screen arrow + distance
    3  IMMINENT  < 30 m     inverted, per the UI spec
    4  MAXLEGIBLE          digits only, black on white  <- best case
    5  MAXLEGIBLE-INV      digits only, white on black  <- polarity compare

  Screens 4 and 5 are the actual gate. If those two are not readable at
  arm's length in direct noon sun, no amount of layout work rescues this
  and the display class has to change.

  Hardware and TFT_eSPI config: see docs/HARDWARE.md. Do not assume the
  User_Setup.h you can see is the one being compiled.
*/

#include <TFT_eSPI.h>

TFT_eSPI tft = TFT_eSPI();

// Landscape. 1 and 3 differ only in which way up; try both on the bike.
static const uint8_t ROTATION = 1;

static const uint16_t W = 320;
static const uint16_t H = 240;

static const uint32_t DWELL_MS = 6000;
static const uint8_t  N_SCREENS = 6;

// Traffic bar colours straight from NAV_DATA.md's progressSegments table.
static const uint16_t TRAFFIC_GREY  = 0x73AE;  // 0xFF727272 travelled
static const uint16_t TRAFFIC_BLUE  = 0x05BF;  // 0xFF00B0FF normal
static const uint16_t TRAFFIC_AMBER = 0xFD00;  // 0xFFFFA000 slow
static const uint16_t TRAFFIC_RED   = 0xF9A6;  // 0xFFF44336 heavy

static uint8_t  screen  = 0;
static uint32_t lastSwitch = 0;

// ---------------------------------------------------------------- arrow

// dir: 0 straight, 1 right, 2 left.
// Drawn as a stem plus a solid head. Vector, not a bitmap — scalable and
// costs no flash, which is the plan for the real firmware too.
static void drawArrow(int cx, int cy, int s, uint8_t dir, uint16_t fg) {
  const int t = s / 3;          // stem thickness
  const int h = s * 2 / 3;      // head half-height

  if (dir == 0) {                                   // straight up
    tft.fillRect(cx - t / 2, cy, t, s, fg);
    tft.fillTriangle(cx - h, cy, cx + h, cy, cx, cy - s, fg);
    return;
  }

  const int sgn = (dir == 1) ? 1 : -1;              // right : left
  tft.fillRect(cx - t / 2, cy, t, s, fg);           // vertical stem
  tft.fillRect(cx - t / 2, cy - t / 2, sgn * s + t / 2, t, fg);  // elbow
  const int hx = cx + sgn * s;
  tft.fillTriangle(hx, cy - t / 2 - h, hx, cy - t / 2 + h,
                   hx + sgn * h, cy - t / 2, fg);
}

// ------------------------------------------------------------- screens

static void screenFar() {
  tft.fillScreen(TFT_WHITE);
  tft.setTextColor(TFT_BLACK, TFT_WHITE);

  // Instruction. NAV_DATA.md measured strings up to 59 chars; the maneuver
  // prefix is dropped because the arrow already says it, keeping the road
  // name, which is the part that carries information.
  tft.setTextDatum(TL_DATUM);
  tft.drawString("Horamavu Agara", 8, 6, 4);
  tft.drawString("Main Rd", 8, 34, 4);

  tft.setTextDatum(TR_DATUM);
  tft.drawString("1.2", 250, 70, 6);
  tft.drawString("km", 305, 96, 4);

  drawArrow(285, 30, 22, 1, TFT_BLACK);

  tft.setTextDatum(TL_DATUM);
  tft.drawString("Arrive 12:08", 8, 150, 4);
  tft.setTextDatum(TR_DATUM);
  tft.drawString("3.2 km left", 312, 150, 4);

  // Traffic profile ahead — the free win from progressSegments.
  const int by = 200, bh = 22;
  tft.fillRect(0,   by, 90,  bh, TRAFFIC_GREY);
  tft.fillRect(90,  by, 120, bh, TRAFFIC_BLUE);
  tft.fillRect(210, by, 60,  bh, TRAFFIC_AMBER);
  tft.fillRect(270, by, 50,  bh, TRAFFIC_RED);
}

static void screenMid() {
  tft.fillScreen(TFT_WHITE);
  tft.setTextColor(TFT_BLACK, TFT_WHITE);

  tft.setTextDatum(TL_DATUM);
  tft.drawString("Horamavu Agara Rd", 8, 6, 4);

  tft.setTextDatum(TR_DATUM);
  tft.drawString("350", 250, 60, 8);
  tft.drawString("m", 312, 140, 4);

  drawArrow(60, 190, 34, 1, TFT_BLACK);
}

static void screenNear() {
  tft.fillScreen(TFT_WHITE);
  tft.setTextColor(TFT_BLACK, TFT_WHITE);

  drawArrow(70, 165, 62, 1, TFT_BLACK);

  tft.setTextDatum(MR_DATUM);
  tft.drawString("80", 300, 120, 8);
}

static void screenImminent() {
  // Inverted below 30 m — a deliberate, hard-to-miss change of state.
  tft.fillScreen(TFT_BLACK);
  tft.setTextColor(TFT_WHITE, TFT_BLACK);

  drawArrow(70, 165, 62, 1, TFT_WHITE);

  tft.setTextDatum(MR_DATUM);
  tft.drawString("20", 300, 120, 8);
}

static void screenMaxLegible(bool inverted) {
  const uint16_t bg = inverted ? TFT_BLACK : TFT_WHITE;
  const uint16_t fg = inverted ? TFT_WHITE : TFT_BLACK;

  tft.fillScreen(bg);
  tft.setTextColor(fg, bg);
  tft.setTextDatum(MC_DATUM);
  tft.drawString("200", W / 2, H / 2, 8);   // font 8 — largest available
}

// --------------------------------------------------------------- frame

static void draw(uint8_t n) {
  switch (n) {
    case 0: screenFar();               Serial.println(F("0 FAR         >500 m, black on white")); break;
    case 1: screenMid();               Serial.println(F("1 MID         500-100 m, black on white")); break;
    case 2: screenNear();              Serial.println(F("2 NEAR        <100 m, black on white")); break;
    case 3: screenImminent();          Serial.println(F("3 IMMINENT    <30 m, INVERTED")); break;
    case 4: screenMaxLegible(false);   Serial.println(F("4 MAXLEGIBLE  digits only, black on white  <-- THE GATE")); break;
    case 5: screenMaxLegible(true);    Serial.println(F("5 MAXLEGIBLE  digits only, white on black  <-- THE GATE")); break;
  }
}

void setup() {
  Serial.begin(115200);
  delay(200);

  tft.init();
  tft.setRotation(ROTATION);
  tft.fillScreen(TFT_WHITE);

  Serial.println(F("\nsunlight_test - Stage 4 Test B"));
  Serial.println(F("Six screens, six seconds each. Photograph 4 and 5 outdoors."));
  Serial.println(F("If 4 and 5 fail at arm's length in noon sun, the gate has failed.\n"));

  draw(screen);
  lastSwitch = millis();
}

void loop() {
  if (millis() - lastSwitch >= DWELL_MS) {
    screen = (screen + 1) % N_SCREENS;
    draw(screen);
    lastSwitch = millis();
  }
}
