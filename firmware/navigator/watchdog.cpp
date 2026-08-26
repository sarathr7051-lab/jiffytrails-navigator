/*
  watchdog.cpp — freshness and link state.

  The rule that makes this work: count packet ARRIVALS, not value changes.
  NAV_DATA.md measured 64 seconds in slow traffic during which not one field
  changed, while Maps kept posting at ~1 Hz — the distance was simply
  quantised to 100 m steps and the road name was the same. A change-based
  watchdog has no threshold that survives that. An arrival-based one is happy
  at 10 s.
*/

#include "watchdog.h"
#include "ble.h"

void watchdogNotePacket(NavState& s) {
  s.lastPacketMs = millis();
  s.packetCount++;
  s.stale = false;
}

void watchdogTick(NavState& s) {
  const bool wasUp = s.linkUp;
  s.linkUp = bleConnected();

  // A fresh connection restarts the clock. Without this, a device that sat
  // disconnected for a minute would come back already "stale" and flash the
  // warning before the first packet had any chance to arrive.
  if (s.linkUp && !wasUp) {
    s.lastPacketMs = millis();
    s.stale = false;
  }

  // While the link is down, DISCONNECTED outranks STALE anyway (see
  // screenFor). Hold the timer so the two states can never both be showing.
  if (!s.linkUp) {
    s.lastPacketMs = millis();
    s.stale = false;
    return;
  }

  s.stale = (millis() - s.lastPacketMs) > STALE_MS;

  // Arrival latch. Maps drops its notification about 4.7 s after you arrive,
  // which clears nav_active — so without latching, the arrival screen would
  // flash past and settle on IDLE, and the one moment the device should
  // acknowledge would be the one it skipped.
  if (s.arrived()) {
    if (!s.showArrival && s.arrivedAtMs == 0) {
      s.arrivedAtMs = millis();
      s.showArrival = true;
    }
    if (s.showArrival && (millis() - s.arrivedAtMs) > ARRIVAL_DWELL_MS) {
      s.showArrival = false;
    }
  } else {
    // A new route clears the latch so the next arrival can fire.
    s.showArrival = false;
    s.arrivedAtMs = 0;
  }
}
