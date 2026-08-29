// ---------------------------------------------------------------------------
// GENERATED COPY - DO NOT EDIT.
//
// Source of truth: firmware/navigator/ota.cpp
// Regenerate:      perl tools/sync_ui_mock.pl
//
// arduino-cli and the Arduino IDE both copy a sketch before compiling it, so
// this sketch cannot #include across to firmware/navigator/. This file is a
// verbatim copy. Edit the original; `perl tools/sync_ui_mock.pl --check` fails
// if the two have diverged.
// ---------------------------------------------------------------------------
/*
  ota.cpp - ArduinoOTA against the phone's hotspot, up only when parked.

  The whole module is designed to fail silently and change nothing. Every path
  out of every function leaves the device able to navigate, because navigation
  is the job and this is a convenience.
*/

#include "ota.h"
#include "display.h"

#if __has_include("wifi_secrets.h")
  #include "wifi_secrets.h"
#else
  // No secrets file: compile, do nothing. See wifi_secrets_example.h.
  #define WIFI_SSID ""
  #define WIFI_PASS ""
#endif

#include <WiFi.h>
#include <ArduinoOTA.h>

// Bumped by hand on every flash meant to be verifiable. The boot screen shows
// it, so "did the update land" is answered by looking at the device rather
// than by trusting the uploader.
const char* FW_VERSION = "0.9.0";

namespace {

/*
  Long enough for a hotspot to answer, short enough that nothing waits on it.
  The hotspot may simply be off - that is the normal case, not an error.
*/
const uint32_t JOIN_TIMEOUT_MS = 8000;

/*
  Do not hammer a hotspot that is not there. A failed attempt costs radio time
  BLE would rather have, and the device may sit parked for hours.
*/
const uint32_t RETRY_MS = 30000;

/*
  Wait before joining, after a route ends. Arriving somewhere is followed by a
  30 s arrival screen and often by riding off again, and bringing the radio up
  for that is churn for nothing.
*/
const uint32_t SETTLE_MS = 20000;

enum State : uint8_t { OFF, WAITING, JOINING, READY };

State    state      = OFF;
uint32_t stateAtMs  = 0;
uint32_t lastTryMs  = 0;
bool     busy       = false;
bool     configured = false;

void radioOff(const char* why) {
  if (state != OFF) {
    WiFi.disconnect(true, true);
    WiFi.mode(WIFI_OFF);
    Serial.printf("ota: radio off (%s)\n", why);
  }
  state = OFF;
  stateAtMs = millis();
}

void wireCallbacks() {
  ArduinoOTA.setHostname("jiffytrails");

  /*
    The display is the only progress indicator this device has, and an update
    takes long enough that a blank screen would read as a crash. A moving
    percentage is also the only proof the transfer is live rather than hung.
  */
  ArduinoOTA.onStart([]() { busy = true; displayOtaBegin(); });
  ArduinoOTA.onProgress([](unsigned int done, unsigned int total) {
    displayOtaProgress(total ? (uint8_t)((done * 100UL) / total) : 0);
  });
  ArduinoOTA.onEnd([]() { displayOtaProgress(100); });
  ArduinoOTA.onError([](ota_error_t) {
    busy = false;
    displayInvalidate();          // hand the screen back to the renderer
  });
}

}  // namespace

void otaBegin() {
  configured = (WIFI_SSID[0] != '\0');
  if (!configured) {
    Serial.println(F("ota: no credentials, disabled (see wifi_secrets_example.h)"));
    return;
  }
  wireCallbacks();
  state = WAITING;
  stateAtMs = millis();
  Serial.printf("ota: armed, fw %s - joins \"%s\" when there is no route\n",
                FW_VERSION, WIFI_SSID);
}

void otaTick(bool navActive) {
  if (!configured) return;
  const uint32_t now = millis();

  /*
    Navigation always wins. Not a preference - one radio, and a rider who
    misses a turn because the ESP32 was talking to a hotspot has been failed by
    a convenience feature.
  */
  if (navActive) {
    /*
      ★ ABORT AN UPDATE IN PROGRESS, do not just cut the radio underneath it.

      This used to only call radioOff(). If a route started mid-transfer, the
      radio went away, ArduinoOTA.handle() was never called again, so onError
      never fired and `busy` was never cleared - and navigator.ino returns from
      loop() on every iteration while otaBusy(). The panel froze on "UPDATING,
      do not disconnect" until a power cycle. Not a bricking risk, since the
      boot partition is not switched until Update.end(), but a dead display.
    */
    if (busy) {
      Update.abort();
      busy = false;
      displayInvalidate();
      Serial.println(F("ota: update aborted - route started"));
    }
    if (state != OFF) radioOff("route started");
    return;
  }

  switch (state) {
    case OFF:
      state = WAITING;
      stateAtMs = now;
      break;

    case WAITING:
      if (now - stateAtMs < SETTLE_MS) break;
      if (now - lastTryMs < RETRY_MS && lastTryMs != 0) break;
      lastTryMs = now;
      WiFi.mode(WIFI_STA);
      WiFi.setSleep(true);                    // share the antenna politely
      WiFi.begin(WIFI_SSID, WIFI_PASS);
      state = JOINING;
      stateAtMs = now;
      break;

    case JOINING:
      if (WiFi.status() == WL_CONNECTED) {
        ArduinoOTA.begin();
        state = READY;
        Serial.printf("ota: ready on %s as jiffytrails, fw %s\n",
                      WiFi.localIP().toString().c_str(), FW_VERSION);
      } else if (now - stateAtMs > JOIN_TIMEOUT_MS) {
        // Hotspot off, or out of range. Entirely normal.
        radioOff("no hotspot");
        state = WAITING;
        stateAtMs = now;
      }
      break;

    case READY:
      if (WiFi.status() != WL_CONNECTED) {
        radioOff("hotspot went away");
        state = WAITING;
        stateAtMs = now;
        break;
      }
      ArduinoOTA.handle();
      break;
  }
}

bool otaBusy()  { return busy; }
bool otaReady() { return state == READY; }
