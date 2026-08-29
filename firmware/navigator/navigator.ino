/*
  navigator.ino — JiffyTrails handlebar navigator.

  Handlebar display for a Triumph Speed 400. The phone does the routing and
  parses Google Maps' ongoing notification; this device shows the maneuver so
  the phone can stay in a pocket.

  Stage 5: BLE link and protocol. No Android app yet — drive it with
  tools/navsim.py or nRF Connect. See docs/STAGE5_TEST_PLAN.md.

  Structure and responsibilities:
    nav_types.h    the contract. NavState is the only shared truth
    ble.cpp        NimBLE peripheral, framing, defensive parse
    watchdog.cpp   freshness, counted by arrivals not changes
    display.cpp    renders NavState, decides nothing
    maneuvers.cpp  vector glyphs

  Hardware and the TFT_eSPI config trap are documented in docs/HARDWARE.md.
  Read the sketchbook section there before editing any User_Setup.h.
*/

#include "nav_types.h"
#include "ble.h"
#include "display.h"
#include "watchdog.h"
#include "demo.h"
#include "backlight.h"
// WiFi and ArduinoOTA are included HERE, not only in ota.cpp, because the
// Arduino builder resolves library dependencies from the sketch file. An
// include that appears solely in a .cpp is not discovered, and the build fails
// with "ArduinoOTA.h: No such file or directory" while the library sits in the
// core the whole time.
#include <WiFi.h>
#include <ArduinoOTA.h>
#include "ota.h"

static const char* DEVICE_NAME = "JiffyTrails";

// The one instance. Everything else takes it by reference.
static NavState state;

// If the phone goes quiet, prompt rather than sit waiting. Maps can legitimately
// leave a notification unchanged for a long stretch, so the phone may have
// nothing new to volunteer — but it should still be asked before the watchdog
// declares the data stale. Idea taken from alexanderlavrushko's BLE HUD, which
// sends an empty indication for exactly this reason (see docs/PRIOR_ART.md).
static const uint32_t NUDGE_AFTER_MS = 4000;
static const uint32_t NUDGE_EVERY_MS = 2000;
static uint32_t lastNudgeMs = 0;

static void nudgeIfQuiet() {
  if (!state.linkUp || state.packetCount == 0) return;

  const uint32_t now = millis();
  if (now - state.lastPacketMs < NUDGE_AFTER_MS) return;
  if (now - lastNudgeMs < NUDGE_EVERY_MS) return;

  const uint8_t poll = 0x00;   // zero-length prod, no packet type claimed
  bleNotify(&poll, 1);
  lastNudgeMs = now;
}

void setup() {
  Serial.begin(115200);
  delay(200);
  Serial.println(F("\nJiffyTrails navigator — stage 5, BLE link"));

  // Why we last started. A corrupted panel on the road could be a brown-out
  // reboot rather than a bus glitch, and those want completely different fixes
  // - a capacitor versus a shorter lead. One line closes the biggest gap in
  // the evidence for docs/BUG_PANEL_CORRUPTION.md.
  Serial.printf("boot: reset reason %d\n", (int)esp_reset_reason());

  displayBegin();
  backlightBegin();   // panel is alive, so it is safe to light it

  displayBootBegin();
  displayBootStage(1);            // panel is up - the ring can honestly say so

  bleBegin(&state, DEVICE_NAME);
  Serial.printf("advertising as \"%s\"\n", DEVICE_NAME);
  displayBootStage(2);            // radio is up

  // Armed, not joined. otaTick brings the radio up only when there is no
  // route - see ota.h for why the phone hotspot rather than a home network.
  otaBegin();

  /*
    Now wait for a phone, but not forever. The ring stalling at two thirds is
    the honest report of "advertising, nobody has answered" - but a rider who
    left their phone at home must not be left looking at a splash, so this
    gives up after BOOT_LINK_WAIT_MS and hands over to the normal screen, which
    says PHONE DISCONNECTED and means it.

    bleTick() and watchdogTick() run here so linkUp is real rather than assumed.
  */
  const uint32_t waitUntil = millis() + 2500;
  while (millis() < waitUntil && !state.linkUp) {
    bleTick();
    watchdogTick(state);
    delay(20);
  }
  displayBootFinish(state.linkUp);
}

void loop() {
  bleTick();              // re-advertises after a disconnect

  // A demo owns NavState while it runs. The watchdog must not also run: it
  // would see no packets arriving and paint STALE over the demo.
  // Gated on a LIVE route, not merely on a NAV_ACTIVE flag. If the link drops
  // mid-route without a final nav_active=0, the flag sticks - and OTA would be
  // locked out exactly when the device is parked, which is the only time it is
  // allowed up and the only way back in once the case is sealed.
  otaTick(state.linkUp && !state.stale && state.navActive());
  if (otaBusy()) return;          // the update owns the screen

  backlightTick();        // ambient light -> backlight PWM
  demoSerial(state);
  if (demoActive()) demoTick(state);
  else              watchdogTick(state);   // link state and freshness
  displaySetNight(state.night);
  backlightSetNight(state.night);
  displayTick();          // re-inits the panel if it has lost its config
  nudgeIfQuiet();
  displayRender(state);   // renders whatever state now says, and nothing else
}
