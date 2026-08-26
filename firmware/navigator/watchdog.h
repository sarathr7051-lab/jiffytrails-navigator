/*
  watchdog.h — freshness and link state.

  Counts packet ARRIVALS, not value changes. NAV_DATA.md measured 64 seconds
  with no field changing while Maps kept posting at ~1 Hz; a change-based
  watchdog has no threshold that works.
*/
#pragma once
#include "nav_types.h"

// Call every loop. Updates s.stale and s.linkUp from arrival timing.
void watchdogTick(NavState& s);

// Call from the BLE layer on every accepted packet, whatever its type.
void watchdogNotePacket(NavState& s);
