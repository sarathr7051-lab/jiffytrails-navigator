# ESP32 firmware

**Status: not yet written.** Display bring-up in progress.

## Setup

`User_Setup.h` goes into `<sketchbook>/libraries/TFT_eSPI/`, replacing the
file that ships with the library. **Restart the Arduino IDE afterwards** — the
config is cached and your edit won't take effect otherwise.

Verify with **Examples → TFT_eSPI → Test and Diagnostics → Read_User_Setup**
before anything else. It prints back the driver and pins the library actually
compiled with, which catches a mistyped pin or an unnoticed cache in seconds.

Then **Examples → TFT_eSPI → 320 x 240 → TFT_graphicstest_one_lib**.

## White screen checklist

In order of likelihood:

1. RESET wired to GPIO 4 instead of **16**
2. IDE not restarted after editing `User_Setup.h`
3. A jumper not fully seated — swap the suspect wire before touching config
4. Unsoldered headers. SPI at 40 MHz will not tolerate a marginal contact, even
   though DC power gets through fine

## Planned structure

```
navigator.ino     entry, setup, main loop
ble.cpp           NimBLE peripheral, packet parse, reconnect
display.cpp       screen states, distance bands, failure states
maneuvers.cpp     vector arrow drawing
watchdog.cpp      stale detection — counts arrivals, not changes
ota.cpp           WiFi OTA — must work before the case is sealed
```

Use TFT_eSPI **sprites for the distance field only**. A full-screen sprite
won't fit in plain ESP32 RAM.

Draw maneuver arrows as **vector paths**, not bitmaps — scalable, and a fraction
of the flash.
