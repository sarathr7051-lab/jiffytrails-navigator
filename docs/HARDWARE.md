# Hardware

## Bill of materials

| Part | Detail | ₹ |
|---|---|---|
| ESP32 **LOLIN32** | USB-C, CH340 USB-serial | 449 |
| **SmartElex 2.8" TFT** | ILI9341, SPI, 240×320, **non-touch** | 815 |
| MB102 breadboard | 830 points | 65 |
| Jumper wires | M2M / M2F / F2F, 20 each | 139 |
| Soldering kit + multimeter | 60 W adjustable, pump, wick, flux, stand | 1,000 |

Later: polycarbonate window, clear RTV, M8 cable gland, M3/M4 fasteners,
anti-glare film, PETG filament — around ₹840.

**Deliberately excluded:** GPS module, magnetometer, vibration motors, internal
battery. Reasons in PROJECT_STATE.md.

## Pin mapping

**Status: VERIFIED WORKING 22 Aug 2026.** `TFT_graphicstest_one_lib` renders
correctly through all rotations on this wiring.

| Display | LOLIN32 |
|---|---|
| VCC | 3V |
| GND | G |
| CS | GPIO 15 |
| RESET | **GPIO 16** |
| DC | GPIO 2 |
| SDI (MOSI) | GPIO 23 |
| SCK | GPIO 18 |
| SDO (MISO) | GPIO 19 |
| LED | 3V |

### Gotchas

**RESET is GPIO 16, not 4.** GPIO 4 is not broken out on the LOLIN32. Most
ILI9341 tutorials say 4, and following them gives you a white screen.

**No series resistors.** The vendor manual specifies 10 K on every signal line
and 5 V on VCC — that is for a 5 V Arduino. The ESP32 is natively 3.3 V; wire
straight through.

**3.3 V is sufficient** despite the module carrying an AMS1117 regulator.
Verified.

**The `+` beside the white connector is the LiPo JST terminal**, not a 5 V
header pin. `VP` and `VN` are GPIO 36 and 39, analog inputs — not power.

**The USB chip is CH340, not CP2102**, despite what some listings say. Windows
has a built-in driver; no install needed.

If the module exposes touch pins, leave them unconnected except **T_CS → 3.3 V**
so the touch controller stays off the shared SPI bus.

**This panel needs `ILI9341_2_DRIVER`, not `ILI9341_DRIVER`.** Same chip ID,
different init sequence ([TFT_eSPI issue 1172][1172]). Under the stock
`ILI9341_DRIVER` this display gave flat white, then vertical stripes once the
pins were corrected — the controller was receiving SPI but never initialising.
The alternative sequence brought it up first try. A second panel from a
different batch may want the other one; try both before assuming a fault.

[1172]: https://github.com/Bodmer/TFT_eSPI/issues/1172

**Run the bus at 27 MHz on breadboard**, not the 40 MHz default. Dupont jumpers
and an MB102 do not hold 40 MHz cleanly. Worth raising again once the build is
soldered — but retest, do not assume.

## Toolchain

Arduino IDE 2.x **from arduino.cc** — not the Microsoft Store build, which is
1.6.11 from 2016 and sandboxed.

Boards Manager URL:
```
https://raw.githubusercontent.com/espressif/arduino-esp32/gh-pages/package_esp32_index.json
```

Board: **WEMOS LOLIN32**.

### Sketchbook location — read this before editing any config

**The sketchbook on this machine is `C:\dev\Arduino`.** The live TFT_eSPI
config is therefore:

```
C:\dev\Arduino\libraries\TFT_eSPI\User_Setup.h
```

That is authoritative, not a guess — it is `directories.user` in
`C:\Users\sarat\.arduinoIDE\arduino-cli.yaml`. **Check that file rather than
trusting an assumed Documents path.**

**The trap that cost a full session:** OneDrive's Documents folder here is
localized to Japanese and is literally named `ドキュメント`. A second, stale
TFT_eSPI lives at

```
C:\Users\sarat\OneDrive\ドキュメント\Arduino\libraries\TFT_eSPI\
```

`%USERPROFILE%\Documents` contains no Arduino folder at all, so anything
reasoning about "Documents\Arduino\libraries" lands on the OneDrive copy — which
is never compiled. Every edit went there and changed nothing, which made two
correct fixes look like failures. **That copy is dead. Do not edit it.** Delete
it if you want the trap gone for good.

`firmware/navigator/User_Setup.h` in this repo is a reference copy; keep it in
sync with the live file by hand.

**Always confirm an edit landed before drawing conclusions from it.** Run
Read_User_Setup and check a value you know you changed. Note that swapping
`ILI9341_DRIVER` for `ILI9341_2_DRIVER` does *not* change the printed driver ID
— both report `9341`. Verify against `Display SPI frequency` or a pin instead.

## Mount

Reuses a **BOBO BM4** phone mount: handlebar clamp → 17 mm ball → socket bracket.
The copper jaw plate (the part that broke) is discarded and replaced with a
printed adapter presenting a 3-lug Garmin-style quarter-turn.

Quarter-turn rather than a clamp screw because a tightened joint holds by
friction, and engine vibration walks friction joints loose. Three lugs behind
solid shoulders is a shear plane — nothing to unwind.

## Enclosure

Roughly 94 × 58 × 20 mm, landscape.

- **PETG or ASA, never PLA.** PLA softens near 55 °C; a case in Indian sun
  exceeds that and sags.
- **Form-in-place gasket** — a 2 × 1.5 mm groove filled with clear RTV and cured
  with the case closed over cling film. Perfect match for about ₹30.
- **Window** — 2 mm polycarbonate bonded to the *inside* of the bezel, so water
  pressure seats it rather than lifting it.
- **Cable gland on the bottom face**, with a drip loop below.
- **ePTFE pressure vent, Ø3 mm.** The part most DIY builds omit. A sealed box in
  the sun reaches 60 °C+; cold rain contracts the air and pulls water past the
  gasket. Membrane can be cut from an old rain jacket.
- Blind screw bosses so fasteners never breach the sealed volume.

Print settings: 0.2 mm layers, **4 perimeters** (the lugs carry all the load),
30–40 % infill, sealing face flat on the bed.

Drawings in `hardware/mount-design.html`.
