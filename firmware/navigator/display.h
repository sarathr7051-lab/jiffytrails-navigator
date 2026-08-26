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
