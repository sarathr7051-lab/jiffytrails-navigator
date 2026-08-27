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

## Related sketches

`../sunlight_test/sunlight_test.ino` — Stage 4 Test B. Cycles the six real UI
states so daylight readability can be judged against the actual design rather
than the library graphics test, which draws thin coloured lines on black and is
close to a worst case.

`../ui_mock/ui_mock.ino` — the nav interface driven by a scripted ride, no BLE.
Distances count down at 1 Hz with the real Google Maps quantisation, maneuvers
change, and every failure state fires on a timer. Serial keys jump straight to
any state. This is where the interface gets finalised before BLE work starts;
its drawing code becomes `display.cpp`.

---

## Stage 5 — known limitations and landmines

Written down 26 Aug 2026 while the BLE link was built. None of this is blocking;
all of it will cost an evening if rediscovered.

**Packet parsing runs on a different task from rendering.** NimBLE delivers
writes on its host task; `displayRender()` reads `NavState` on the loop task.
There is no lock, so a render can in principle catch a half-updated
`instruction[]`. At 1 Hz the window is tiny and the next frame corrects it, so
the visible worst case is one frame of garbled road name. **If it ever matters,
the fix is to stage the raw frame bytes in `onWrite` and parse them in
`bleTick()`**, moving all mutation onto the loop task. Left as-is for now
because untested restructuring is a worse risk than a one-frame cosmetic fault.

**xtensa gcc 14 (esp32 core 3.3.11) ICEs on a specific construct.** A
namespace-scope function-pointer type that names a class from an *anonymous*
namespace crashes the compiler with a segfault — it appeared as a failure on
`struct PacketHandler` with no useful diagnostic. `PacketReader` is therefore at
file scope rather than in an anonymous namespace. Do not "tidy" it back.

**`NavState.linkUp` has exactly one writer: `watchdogTick()`.** It derives the
value from `bleConnected()` once per loop because it needs the
disconnected→connected *edge* to restart the freshness clock. `ble.cpp`
deliberately does not set it — an earlier version did, which consumed the edge
and silently made the reconnect branch dead code.

### Regressions against `ui_mock`, both from missing protocol rows

- **No traffic bar.** Needs `0x07 TRAFFIC` specified and a `NavState` field.
- **Idle screen shows "READY", not a clock and trip stats.** Needs a time source
  and `0x05 TRIP`. A fabricated clock on a handlebar is worse than none.

### Maneuver glyphs that are approximations

SHARP_LEFT/RIGHT draw as ordinary turns; KEEP, FORK and EXIT all draw as slight
turns — correct side, less specific meaning. FLYOVER, UNDERPASS and FERRY render
`?` on purpose: Maps emits no icon for them (NAV_DATA.md), so they can only
arrive from an unvalidated source, and a CONTINUE arrow would be a confident
claim that the road runs straight through. Roundabout exits `0x20`–`0x2F` draw
the ring plus the exit **number**, because exit angles are not evenly spaced and
a generic exit stub would point the wrong way.


## Two sketches

**`firmware/navigator/`** is the real thing: the phone drives it over BLE.

**`firmware/ui_mock/`** is the same display with no phone and no radio. It boots
straight into a scripted ride from Panampilly Nagar to Fort Kochi Beach and
loops it — distances count down at a real speed, the screen crosses every band,
every maneuver glyph appears, and the route ends on the arrival screen before
starting again. Useful for judging the interface at mount distance without
pairing anything, and it is half the flash because there is no BLE stack.

Both accept the same serial keys at 115200:

| key | |
|---|---|
| `r` | the scripted ride |
| `g` | glyph parade — every maneuver, named as it draws |
| `a` | alerts — call and message, riding and parked |
| `b` | replay the boot sequence |
| `x` | stop (in `navigator`, hands the display back to the phone) |

### Keeping them in sync

`firmware/ui_mock/src/` holds **generated copies** of the shared sources. Do not
edit them. After changing anything in `firmware/navigator/`:

```
perl tools/sync_ui_mock.pl
```

and `perl tools/sync_ui_mock.pl --check` fails if they have diverged.

Copies rather than includes because arduino-cli *and* the IDE both copy a sketch
into a build directory before compiling, so a relative `#include` pointing
outside the sketch resolves against the copy and finds nothing.

This matters more than it looks. The previous `ui_mock` was a hand-maintained
second implementation of every screen, and it drifted until it had nine
maneuvers, an enum where left was `MV_LEFT`, and a traffic bar the firmware had
removed — a mock showing a UI the device no longer had. The copies are
mechanical and the check makes drift an error instead of something you discover
on the panel.
