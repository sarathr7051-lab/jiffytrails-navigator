# ESP32 firmware

**Status: display bring-up COMPLETE (22 Aug 2026).** Panel renders graphics and
text correctly through all rotations. Firmware itself not yet written.

## Setup

`User_Setup.h` here is a reference copy. The live file the compiler actually
reads is `<sketchbook>/libraries/TFT_eSPI/User_Setup.h`, and on this machine
the sketchbook is **`C:\dev\Arduino`** — see the sketchbook section in
`docs/HARDWARE.md` before editing anything, including the OneDrive decoy that
wasted a session.

Working configuration:

| Setting | Value |
|---|---|
| Driver | **`ILI9341_2_DRIVER`** (not `ILI9341_DRIVER`) |
| SPI_FREQUENCY | **27000000** on breadboard |
| CS / DC / RST | 15 / 2 / 16 |
| MOSI / SCLK / MISO | 23 / 18 / 19 |

Verify with **Examples → TFT_eSPI → Test and diagnostics → Read_User_Setup**
before anything else. It prints back what the compiler actually used, which
catches a mistyped pin or a wrong-file edit in seconds. Then
**Examples → TFT_eSPI → 320 x 240 → TFT_graphicstest_one_lib**.

Note Read_User_Setup prints inside `loop()`, so the output repeats forever —
that is normal, not a boot loop. One cycle ends at `[/code]`.

## White screen checklist

In order of likelihood, learned the hard way:

1. **You edited a `User_Setup.h` that isn't the one being compiled.** Check
   `directories.user` in `~/.arduinoIDE/arduino-cli.yaml`, then confirm with
   Read_User_Setup that a value you changed actually changed. Everything below
   is a waste of time until this is ruled out.
2. Wrong init sequence — try **`ILI9341_2_DRIVER`**. Flat white or vertical
   stripes with correct pins is the signature. Note the printed driver ID stays
   `9341` either way, so verify via the SPI frequency line instead.
3. RESET wired to GPIO 4 instead of **16**
4. SPI too fast for breadboard — drop to **27 MHz**
5. A jumper not fully seated — swap the suspect wire before touching config
6. Unsoldered or cold headers. SPI will not tolerate a marginal contact even
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
