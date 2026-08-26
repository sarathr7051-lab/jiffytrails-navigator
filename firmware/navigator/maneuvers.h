/*
  maneuvers.h — vector maneuver glyphs.

  Every glyph is drawn as percentages of an s-by-s box with its top-left at
  (x, y), so no glyph can escape its box regardless of which maneuver it is.
  An earlier centre-point version overran differently for left and right
  turns, so the layout could not reserve space for both.
*/
#pragma once
#include <Arduino.h>

class TFT_eSPI;

void drawManeuver(TFT_eSPI& tft, int x, int y, int s,
                  uint8_t maneuver, uint16_t fg, uint16_t bg);
