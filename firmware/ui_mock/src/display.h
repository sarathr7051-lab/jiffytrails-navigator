// ---------------------------------------------------------------------------
// GENERATED COPY - DO NOT EDIT.
//
// Source of truth: firmware/navigator/display.h
// Regenerate:      perl tools/sync_ui_mock.pl
//
// arduino-cli and the Arduino IDE both copy a sketch before compiling it, so
// this sketch cannot #include across to firmware/navigator/. This file is a
// verbatim copy. Edit the original; `perl tools/sync_ui_mock.pl --check` fails
// if the two have diverged.
// ---------------------------------------------------------------------------
/*
  display.h — renders NavState and nothing else.

  Drawing code is ported from firmware/ui_mock/ui_mock.ino, which was
  validated on hardware. Keep its geometry: the two-column split, the glyph
  bounding boxes, and the runtime-measured distance block all exist because
  hand-estimated pixel maths clipped twice.
*/
#pragma once
#include "nav_types.h"

void displayBegin();

// Idempotent. Redraws chrome only when the screen changes, and the distance
// field only when the quantised value changes.
void displayRender(const NavState& s);

// Forces a full redraw on the next render (after a mode change or wake).
void displayInvalidate();

// Day is black-on-white for glare; night inverts. Elements that are themselves
// inversions (the sub-30 m screen, the alert band) flip with it, so they stay
// inversions rather than becoming ordinary.
void displaySetNight(bool on);

// The boot sequence. displayBootBegin draws the mark and wordmark; the two
// stage calls advance a progress ring that reports REAL progress, not a timer;
// displayBootFinish closes it and reports the link state in the waypoint dot -
// filled amber for connected, hollow for searching. Pass whatever linkUp
// actually says: a splash that claims a connection it does not have is the
// same lie as a stale maneuver, just prettier.
void displayBootBegin();
void displayBootStage(uint8_t stage);   // 1 = panel up, 2 = radio up, 3 = linked
void displayBootFinish(bool linked);

// Call every loop. Periodically asks the panel whether it is still configured
// and re-initialises it if not — see the comment on displayTick() for why this
// device needs a display watchdog at all.
void displayTick();

/*
  The OTA screens. An update takes long enough that a blank panel would read as
  a crash, and the display is the only progress indicator this device has.

  displayOtaBegin takes the screen; displayOtaProgress redraws only the bar, so
  the percentage moving is itself proof the transfer is live rather than hung.
  After an update the device reboots, so nothing has to hand the screen back -
  except on error, where displayInvalidate() does it.
*/
void displayOtaBegin();
void displayOtaProgress(uint8_t pct);
