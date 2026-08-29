/*
  demo.h - drive the real display with fake data.

  This replaces firmware/ui_mock/, which was a second implementation of every
  screen: its own drawManeuver with nine maneuvers, its own enum where left was
  0x02 and called MV_LEFT, its own chrome, its own idle screen, and a traffic
  bar the real firmware had already removed. By the time the arrows, the boot
  sequence, the alert band and the idle screen had all changed, it was showing
  a UI the device no longer had - which is worse than no mock at all, because
  it is a mock you might believe.

  So the demo lives inside the real firmware and feeds synthetic values to the
  real renderer. It cannot drift, because there is nothing to drift from.

  Serial, 115200:
    f   FULL FLOW - every screen, in the order a ride happens
    n   toggle night mode (ui_mock has no phone to send it)
    j   junction geometry - flyover, fork, roundabout
    g   glyph parade - every maneuver in glyph_data.h, named as it draws
    r   scripted ride - the distance bands, then arrival
    a   alerts - call and message, on a route and while parked
    b   replay the boot sequence
    x   stop, hand the display back to the phone
*/
#pragma once
#include "nav_types.h"

// True while a demo owns NavState. The main loop must not run the watchdog
// then - it would notice no packets are arriving and declare the link stale
// over the top of whatever the demo is showing.
bool demoActive();

// Start a demo without a keypress, for a sketch that has no phone to wait for.
void demoForce(char what);

// Reads Serial. Returns true if this byte started or stopped a demo.
bool demoSerial();

// Writes the next frame of synthetic state. Call instead of watchdogTick().
void demoTick(NavState& s);
