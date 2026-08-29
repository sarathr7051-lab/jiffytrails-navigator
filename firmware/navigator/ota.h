/*
  ota.h - update over the air, so the case never has to come off.

  BUILD_PLAN.md Stage 10 is a hard gate and says why: "discovering OTA is
  broken after the case is glued is a bad afternoon." It has to work before
  anything is sealed, and it has to be proven TWICE - a single successful
  update does not exercise the partition rotation, and the second one, running
  from the partition the first wrote, is the case that fails.

  ---------------------------------------------------------------------------
  IT TARGETS THE PHONE'S HOTSPOT, NOT A HOME NETWORK.

  The rider moves between cities and expects to change routers; the one
  constant network is the S24+ that is already paired to this device over BLE.
  Targeting it means OTA works in Kochi, in Bengaluru, and at the roadside,
  and it removes the "which network am I on" question entirely.

  ★ WIFI IS ONLY UP WHEN THERE IS NO ROUTE. That is the whole design, and it
  follows from the hotspot decision rather than being a separate idea: the
  phone is always present, so a connect-at-boot-and-stay-joined scheme would
  leave WiFi running for every minute of every ride. The ESP32 has one 2.4 GHz
  radio shared between WiFi and BLE, and BLE is what the display depends on.

  So the rule is simple and needs no button, which matters once the case is
  sealed and there is no serial port to reach:

      no route, stationary at a desk  ->  WiFi joins, OTA available
      navigation starts               ->  WiFi off within a second, BLE alone

  You will never be updating while riding, and the device never has to be told
  which of those it is doing.
*/

#pragma once
#include <Arduino.h>

/** Shown on the boot screen and in the OTA hostname, so an update is provable. */
extern const char* FW_VERSION;

/** Prepare OTA. Does not join anything yet - otaTick decides that. */
void otaBegin();

/**
 * Call every loop.
 *
 * @param navActive true while a route is running. WiFi is brought up only when
 *                  this is false and torn down as soon as it goes true.
 */
void otaTick(bool navActive);

/** True while an update is actually transferring - the display shows progress. */
bool otaBusy();

/** True when joined and listening, for the idle screen to say so. */
bool otaReady();
