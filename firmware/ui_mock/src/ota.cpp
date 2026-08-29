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
  ota.cpp - ArduinoOTA, bounded and optional.

  The whole point is that this module can fail completely and change nothing.
  Every path out of otaBegin() leaves the device able to navigate.
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

// Bumped by hand on every flash that is meant to be verifiable. The boot screen
// shows it, so "did the update land" is answered by looking at the device
// rather than by trusting the uploader.
const char* FW_VERSION = "0.9.0";

namespace {

/*
  Long enough for a router to answer, short enough that a rider who started the
  bike outside WiFi range does not notice. The display is already up and the
  boot animation is running while this waits.
*/
const uint32_t JOIN_TIMEOUT_MS = 6000;

bool running = false;
bool busy    = false;

}  // namespace

bool otaBegin() {
  if (WIFI_SSID[0] == '\0') {
    Serial.println(F("ota: no credentials, skipping (see wifi_secrets_example.h)"));
    return false;
  }

  WiFi.mode(WIFI_STA);
  WiFi.setSleep(true);          // share the radio politely with BLE
  WiFi.begin(WIFI_SSID, WIFI_PASS);

  const uint32_t until = millis() + JOIN_TIMEOUT_MS;
  while (millis() < until && WiFi.status() != WL_CONNECTED) delay(100);

  if (WiFi.status() != WL_CONNECTED) {
    // Not at home. Switch the radio off rather than leave it retrying: BLE is
    // what the display depends on, and they share one antenna.
    WiFi.disconnect(true, true);
    WiFi.mode(WIFI_OFF);
    Serial.println(F("ota: no WiFi, radio off - normal on the road"));
    return false;
  }

  ArduinoOTA.setHostname("jiffytrails");

  /*
    The display is the only progress indicator this device has, and an update
    takes long enough that a blank screen would look like a crash. It also
    proves the transfer is live rather than hung.
  */
  ArduinoOTA.onStart([]() {
    busy = true;
    displayOtaBegin();
  });
  ArduinoOTA.onProgress([](unsigned int done, unsigned int total) {
    displayOtaProgress(total ? (uint8_t)((done * 100UL) / total) : 0);
  });
  ArduinoOTA.onEnd([]() {
    displayOtaProgress(100);
  });
  ArduinoOTA.onError([](ota_error_t) {
    busy = false;
    displayInvalidate();        // hand the screen back to the renderer
  });

  ArduinoOTA.begin();
  Serial.printf("ota: ready on %s as jiffytrails, fw %s\n",
                WiFi.localIP().toString().c_str(), FW_VERSION);
  running = true;
  return true;
}

void otaTick() {
  if (running) ArduinoOTA.handle();
}

bool otaBusy() { return busy; }
