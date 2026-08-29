// ---------------------------------------------------------------------------
// GENERATED COPY - DO NOT EDIT.
//
// Source of truth: firmware/navigator/ota.h
// Regenerate:      perl tools/sync_ui_mock.pl
//
// arduino-cli and the Arduino IDE both copy a sketch before compiling it, so
// this sketch cannot #include across to firmware/navigator/. This file is a
// verbatim copy. Edit the original; `perl tools/sync_ui_mock.pl --check` fails
// if the two have diverged.
// ---------------------------------------------------------------------------
/*
  ota.h - update over the air, so the case never has to come off.

  BUILD_PLAN.md Stage 10 is a hard gate and says why: "discovering OTA is
  broken after the case is glued is a bad afternoon." This has to work before
  anything is sealed, and it has to be proven TWICE, because a single
  successful update does not exercise the partition rotation - the second one
  runs from the partition the first one wrote, and that is the case that fails.

  HOW IT BEHAVES. At boot it tries the configured network for a bounded window.
  If it joins, OTA stays available and the boot screen says so. If it does not,
  the radio is switched off completely and the device carries on - which is
  every ride, because the bike is not at home.

  WHY WIFI IS NOT LEFT SCANNING. The ESP32 has one 2.4 GHz radio shared between
  WiFi and BLE, and BLE is the thing the display actually depends on. A failed
  join costs a few seconds at boot; a permanent retry loop would cost airtime
  on every ride for a feature that can only work in one location.

  CREDENTIALS live in wifi_secrets.h, which is not tracked. Copy
  wifi_secrets_example.h over it and fill it in. With no file, or with an empty
  SSID, OTA is compiled in but never starts and nothing else changes.
*/

#pragma once
#include <Arduino.h>

/** Shown on the boot screen and in the OTA hostname, so an update is provable. */
extern const char* FW_VERSION;

/**
 * Try to join WiFi and start the OTA listener. Returns true if the radio is up
 * and updates are possible; false means it gave up and switched WiFi off.
 *
 * Bounded and non-fatal by construction: nothing else in the firmware waits on
 * it and nothing else fails if it fails.
 */
bool otaBegin();

/** Call from loop(). A no-op when otaBegin() returned false. */
void otaTick();

/** True while an update is actually transferring - the display shows progress. */
bool otaBusy();
