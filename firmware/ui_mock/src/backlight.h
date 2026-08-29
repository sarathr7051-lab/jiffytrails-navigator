// ---------------------------------------------------------------------------
// GENERATED COPY - DO NOT EDIT.
//
// Source of truth: firmware/navigator/backlight.h
// Regenerate:      perl tools/sync_ui_mock.pl
//
// arduino-cli and the Arduino IDE both copy a sketch before compiling it, so
// this sketch cannot #include across to firmware/navigator/. This file is a
// verbatim copy. Edit the original; `perl tools/sync_ui_mock.pl --check` fails
// if the two have diverged.
// ---------------------------------------------------------------------------
/*
  backlight.h — ambient light sensing and backlight PWM.

  Drives the display module backlight by PWM on GPIO 17, so the panel is readable
  in direct sun without blinding the rider at night.

  No external transistor: the module has its own S8050 low-side switch and the
  LED header pin is a logic input into it. An optional LDR path is compiled out
  by default - the reasoning is in backlight.cpp.

  ---------------------------------------------------------------------------
  WHAT THIS DELIBERATELY DOES NOT DO

  It does not touch day/night colour polarity. That is s.night, and it comes
  from the phone, which computes it from SolarClock's sunrise/sunset times and
  sends it on transition (LinkService.kt:448). An LDR is the worse source for
  that decision and the failure is not symmetric:

      a tunnel at noon     -> LDR says night -> screen inverts mid-corner
      a streetlight at 9pm -> LDR says day   -> white screen in the face

  Brightness can be wrong for a second and it is a minor annoyance. Polarity
  flipping while you are reading a maneuver is not. Clock beats sensor here,
  and mixing two sources of truth for one flag is the exact bug pattern that
  already cost this project three flicker bugs.

  ---------------------------------------------------------------------------
  ★ PIN 36 IS NOT A PREFERENCE

  The LDR must sit on ADC1. ADC2 stops converting the moment the WiFi radio is
  active, and ota.cpp raises WiFi whenever no route is running - so on an ADC2
  pin the reading would die exactly during an over-the-air update, which is the
  worst possible time for the hardware to behave differently from how it was
  last tested.
*/
#pragma once
#include <stdint.h>

// Sets up the ADC and the LEDC timer, and takes the panel to full brightness
// before the first reading lands. Call once, from setup(), AFTER displayBegin()
// so the panel is already alive when the light comes up.
void backlightBegin();

// Call every loop; it rate-limits itself. Fades toward the target and drives
// the PWM. Cheap enough to sit in the hot loop.
void backlightTick();

/*
  The primary input. Day is full brightness - the panel loses to sun glare by a
  factor of four already, so there is no daylight level where dimming is right.
  Night pulls the backlight down behind the inverted colours.

  Driven from s.night, which the phone computes from real sunrise and sunset
  times. Fades over a second rather than stepping.
*/
void backlightSetNight(bool on);

/*
  The phone's CONFIG packet carries a brightness byte, which until now was read
  and discarded. It is now a manual override:

      0        follow the sensor (the default, and what the phone sends today)
      1..100   hold this percentage, ignore the sensor

  A manual value is not remembered across a reboot. That is on purpose - if a
  rider pins the panel to 5% and forgets, the fix should be a power cycle
  rather than a support conversation.
*/
void backlightSetOverride(uint8_t pct);

// For the boot screen and the serial demo: what the sensor last saw, in
// millivolts, and what duty we are actually driving as a percentage.
uint16_t backlightAmbientMv();
uint8_t  backlightPercent();

// True when the reading is below anything the sensor can physically produce,
// which means a broken lead rather than a dark night. See backlight.cpp - the
// response is to go FULL bright, never dim.
bool backlightSensorFaulted();
