// ---------------------------------------------------------------------------
// GENERATED COPY - DO NOT EDIT.
//
// Source of truth: firmware/navigator/backlight.cpp
// Regenerate:      perl tools/sync_ui_mock.pl
//
// arduino-cli and the Arduino IDE both copy a sketch before compiling it, so
// this sketch cannot #include across to firmware/navigator/. This file is a
// verbatim copy. Edit the original; `perl tools/sync_ui_mock.pl --check` fails
// if the two have diverged.
// ---------------------------------------------------------------------------
#include "backlight.h"
#include <Arduino.h>
#include <math.h>

/*
  ★ WHY THE LDR IS COMPILED OUT BY DEFAULT

  The rider asked the right question: is the sensor worth it, given the panel
  is not very bright to begin with? Working through it says no - not for this
  build - and the numbers are already in docs/HARDWARE.md.

  IN DAYLIGHT, DIMMING IS NEVER WANTED. The measured contrast in sun is
  1.17:1 against the 5:1 that readable text needs (HARDWARE.md:194-203). The
  panel is already losing to glare by a factor of four. There is no ambient
  level between dawn and dusk where the right answer is anything but maximum.
  An auto-dimmer spends its whole day arriving at the same conclusion.

  AT NIGHT, THE PROBLEM IS REAL, BUT NIGHT MODE ALREADY SOLVES MOST OF IT.
  displaySetNight() inverts to white-on-black, so the great majority of pixels
  go dark and emitted light falls with them. What is left is a backlight still
  running at full duty behind them, and that is worth pulling down - which is
  what this file now does.

  AND THE SENSOR IS NOT FREE. It needs a hole in the top face of a waterproof
  case, on the surface rain actually lands on, potted with epoxy. That is a
  deliberate leak path through the one part of the enclosure whose entire job
  is not leaking, bought for a refinement on a problem the night flag already
  covers.

  So v1 drives brightness from s.night, which the phone derives from
  SolarClock's real sunrise and sunset (LinkService.kt:448) - a source no
  tunnel, streetlight or jacket sleeve can fool.

  The LDR path below is complete and tested-by-construction. Set
  BACKLIGHT_USE_LDR to 1 and fit the parts if night mode alone proves not to be
  enough on a real ride. Nothing else has to change.
*/
#define BACKLIGHT_USE_LDR 0

// ---------------------------------------------------------------- hardware

/*
  Straight to the module LED pin. NO external transistor.

  The module already carries one: the LED header pin feeds a 1k base resistor
  into an S8050 NPN switching the backlight cathodes to ground (LCDWIKI MSP2807
  schematic). It is a logic input, not a supply rail, and it costs this pin
  (3.3 - 0.7) / 1000 = 2.6 mA against a 40 mA maximum.

  Confirm before soldering, because this family of boards is not consistent:
  put 1k in series with the LED pin. Stays bright = transistor present, wire it
  straight. Goes dark = the pin really is the LED supply and it needs a 2N7000
  low-side switch after all. See docs/HARDWARE.md.
*/
static const uint8_t PIN_BL  = 17;
#if BACKLIGHT_USE_LDR
static const uint8_t PIN_LDR = 36;   // ★ ADC1 only - see backlight.h
#endif

/*
  20 kHz, comfortably above hearing. Backlight PWM is commonly run at 1-5 kHz
  and on this project that would be a mistake twice over: some panel boards
  sing audibly at those rates, and a low carrier beats against a phone camera's
  rolling shutter, so every photograph of the display comes out banded. This
  display is debugged largely from photographs of it, so a carrier that ruins
  photographs would cost real time.

  10-bit at 20 kHz is well inside the LEDC's range - the ceiling is
  log2(80 MHz / 20 kHz) = 12 bits.
*/
static const uint32_t PWM_HZ   = 20000;
static const uint8_t  PWM_BITS = 10;
static const uint16_t PWM_MAX  = (1 << PWM_BITS) - 1;
static const uint8_t  PWM_CH   = 0;      // only used by the core 2.x API

// ---------------------------------------------------------------- response

static const uint8_t DAY_PCT   = 100;
/*
  35% rather than something lower. The temptation is to go dimmer, but the
  screen still has to be read at a glance at speed, and night riding in India
  includes plenty of unlit road where oncoming headlights keep the eye far from
  fully dark-adapted. Dark enough not to dazzle, bright enough to still be a
  glance rather than a stare.
*/
static const uint8_t NIGHT_PCT = 35;
static const uint8_t MIN_PCT   = 20;    // never off - see below

/*
  A one-second fade rather than a step. The day/night transition fires once,
  from a clock, often while moving - and a panel that changes brightness
  instantly in peripheral vision reads as a fault or a flicker, which is
  exactly the reflex this project has spent three bugs trying to eliminate.
*/
static const uint32_t FADE_MS  = 1000;
static const uint32_t TICK_MS  = 20;

/*
  Perceived brightness is not proportional to duty.

  ★ NOTE THE DIRECTION - the comment here used to have it backwards, and
  somebody would eventually have "fixed" it the wrong way. A forward gamma of
  2.2 COMPRESSES the low end rather than spreading it: 0.35^2.2 = 0.099, so 35
  would map to under a tenth of full scale. It is the MIN_PCT floor underneath
  that rescues the result to 28% duty, which is what makes night mode read as a
  bit over a third rather than nearly off. The number was right; the stated
  reason was inverted.

  Measured curve, pct -> % of full duty:
      0 -> 20.0   10 -> 20.5   20 -> 22.3   35 -> 28.0
     50 -> 37.4   75 -> 62.5  100 -> 100.0
*/
static const float GAMMA = 2.2f;

// ---------------------------------------------------------------- state

static float    curPct     = (float)DAY_PCT;
static uint8_t  targetPct  = DAY_PCT;
static uint8_t  override_  = 0;              // 0 = automatic
static uint32_t lastTick   = 0;

// ---------------------------------------------------------------- pwm

/*
  The LEDC API was renamed between ESP32 Arduino core 2.x and 3.x. Both are in
  circulation, so the version is tested rather than assumed - the 2.x calls do
  not exist in 3.x and the build fails outright rather than misbehaving.
*/
static bool pwmOk = false;

static void pwmBegin() {
#if defined(ESP_ARDUINO_VERSION_MAJOR) && ESP_ARDUINO_VERSION_MAJOR >= 3
  pwmOk = ledcAttach(PIN_BL, PWM_HZ, PWM_BITS);
#else
  pwmOk = (ledcSetup(PWM_CH, PWM_HZ, PWM_BITS) != 0);
  if (pwmOk) ledcAttachPin(PIN_BL, PWM_CH);
#endif
  /*
    ★ FAIL BRIGHT. Both LEDC calls return a status and both used to be
    discarded. If the timer cannot be allocated, GPIO 17 is left a floating
    input, the module's S8050 base sees nothing, and the panel is simply dark -
    silently, with no log line, in a module whose stated doctrine everywhere
    else is that the one input never to trust with darkening the display is one
    that has failed.
  */
  if (!pwmOk) {
    Serial.println(F("backlight: ledcAttach FAILED - pinning full bright"));
    pinMode(PIN_BL, OUTPUT);
    digitalWrite(PIN_BL, HIGH);
  }
}

static void pwmWrite(uint16_t duty) {
  if (!pwmOk) return;            // already pinned HIGH by pwmBegin
#if defined(ESP_ARDUINO_VERSION_MAJOR) && ESP_ARDUINO_VERSION_MAJOR >= 3
  ledcWrite(PIN_BL, duty);
#else
  ledcWrite(PWM_CH, duty);
#endif
}

/*
  Never off. A rider glancing down at 80 km/h and finding a black rectangle is
  a safety problem rather than a UI one, so the floor sits where the panel is
  still legible in a dark garage - not where it stops drawing current.
*/
static void applyPercent(float pct) {
  if (pct > 100.0f) pct = 100.0f;
  if (pct < 0.0f)   pct = 0.0f;

  const float shaped = powf(pct / 100.0f, GAMMA);
  const float lo     = (float)MIN_PCT / 100.0f;
  pwmWrite((uint16_t)((lo + (1.0f - lo) * shaped) * (float)PWM_MAX + 0.5f));
}

// ---------------------------------------------------------------- ldr

#if BACKLIGHT_USE_LDR
/*
  Divider is 3V3 - LDR - node - 10k - GND, so brighter light means a lower LDR
  resistance and a HIGHER reading. GL5528 against a 10k bottom leg:

      full sun    ~200R  -> ~3240 mV        dusk      ~15k  -> ~1320 mV
      overcast    ~1k5   -> ~2870 mV        night    ~100k  ->  ~300 mV
      indoors     ~2k    -> ~2750 mV        sensor dark ~1M ->   ~33 mV
*/
static const uint16_t DARK_MV   = 300;
static const uint16_t BRIGHT_MV = 2800;
static const uint16_t FAULT_MV  = 25;

/*
  ★ ASYMMETRIC SMOOTHING. One time constant cannot serve both directions. Come
  out of an underpass into afternoon sun with a slow filter and the panel stays
  dim for seconds - precisely when a maneuver is most likely due. Use a fast
  one instead and every tree, hoarding and overtaking truck strobes the
  backlight for the whole ride.

  Rise fast, fall slow. Brightening is urgent because the alternative is an
  unreadable screen; dimming never is.
*/
static const float EMA_RISE = 0.45f;   // ~3 samples, about a third of a second
static const float EMA_FALL = 0.02f;   // ~50 samples, about five seconds

static float    emaMv   = (float)BRIGHT_MV;
static uint16_t lastMv  = BRIGHT_MV;
static bool     faulted = false;

static uint8_t ldrPercent() {
  const uint16_t mv = analogReadMilliVolts(PIN_LDR);
  lastMv = mv;

  /*
    Below what the sensor can produce in total darkness, so the lead has come
    off and the 10k has pulled the node to ground. FAIL BRIGHT.

    This matters because the failure is silent and inverted: a broken sensor
    wire looks exactly like midnight, and the naive response to midnight is to
    dim the screen to its floor. The one input that must never be trusted to
    darken the display is the one that is disconnected.
  */
  faulted = (mv < FAULT_MV);
  if (faulted) { emaMv = (float)BRIGHT_MV; return 100; }

  const float target = (float)mv;
  emaMv += ((target > emaMv) ? EMA_RISE : EMA_FALL) * (target - emaMv);

  float span = (emaMv - (float)DARK_MV) / (float)(BRIGHT_MV - DARK_MV);
  if (span < 0.0f) span = 0.0f;
  if (span > 1.0f) span = 1.0f;
  return (uint8_t)(span * 100.0f + 0.5f);
}
#endif  // BACKLIGHT_USE_LDR

// ---------------------------------------------------------------- api

void backlightBegin() {
  pwmBegin();
#if BACKLIGHT_USE_LDR
  analogSetPinAttenuation(PIN_LDR, ADC_11db);   // full 0-3.3 V span
#endif
  /*
    Full brightness before anything else decides otherwise. The alternative -
    starting low and ramping up - leaves the boot screen dim in daylight, and
    the boot screen is the one thing a rider looks at to confirm the device
    woke up at all.
  */
  curPct = targetPct = DAY_PCT;
  applyPercent(curPct);
}

void backlightSetNight(bool on) {
  targetPct = on ? NIGHT_PCT : DAY_PCT;
}

void backlightSetOverride(uint8_t pct) {
  override_ = (pct > 100) ? 100 : pct;
}

uint8_t backlightPercent() { return (uint8_t)(curPct + 0.5f); }

#if BACKLIGHT_USE_LDR
uint16_t backlightAmbientMv()     { return lastMv; }
bool     backlightSensorFaulted() { return faulted; }
#else
uint16_t backlightAmbientMv()     { return 0; }
bool     backlightSensorFaulted() { return false; }
#endif

void backlightTick() {
  const uint32_t now = millis();
  if (now - lastTick < TICK_MS) return;
  lastTick = now;

  uint8_t want = targetPct;
#if BACKLIGHT_USE_LDR
  // The sensor scales within the band the night flag chose rather than
  // replacing it, so a fooled sensor can only ever be somewhat wrong.
  want = (uint8_t)((uint16_t)targetPct * ldrPercent() / 100);
  if (want < MIN_PCT) want = MIN_PCT;
#endif
  if (override_ > 0) want = override_;

  if ((uint8_t)(curPct + 0.5f) == want) return;

  const float step = 100.0f * (float)TICK_MS / (float)FADE_MS;
  if (curPct < want) { curPct += step; if (curPct > want) curPct = want; }
  else               { curPct -= step; if (curPct < want) curPct = want; }
  applyPercent(curPct);
}
