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
Verified on the bench: **3.18 V measured at the `3V` pin with the backlight
lit** (22 Aug 2026, DT-830D on DCV 20). A 4 % droop off nominal — fine, but
that is the LDO working rather than coasting. Re-measure if anything else is
ever added to the 3.3 V rail.

### ★ Backlight control is not wired for, and it needs to be

`LED` is tied straight to `3V`. The backlight is therefore always on at full
brightness, which blocks two things already in the plan:

- **"Dim screen on STALE"** (`BLE_PROTOCOL.md` display rules) — needs PWM.
- **Stage 9 auto-dim** via LDR or BH1750 — needs PWM.

`User_Setup.h` already reserves `TFT_BL 17` and `TFT_BACKLIGHT_ON HIGH`,
commented out, for when this changes.

**★ CORRECTED 29 Aug 2026 — no external switch is needed. The module already
has one.**

This section used to say the LED pin was the backlight supply, that it drew
60–100 mA, and that it therefore needed an added MOSFET or an NPN. The
[LCDWIKI MSP2807 schematic][msp2807sch] says otherwise, traced net by net:

```
3.3V ──> LEDA ─[4 white LEDs in parallel]─ LEDK ──[R5 10R]──┐
                                                  collector ┴
  header "LED" ──[R6 1k]── base ────────────────►  Q1  S8050 (NPN)
                                                    emitter ┬
                                                           GND
```

The LED pin is **a logic-level control input to an on-board low-side NPN**, not
a supply rail. That is why the wiki describes it as "high level lighting". The
current an ESP32 pin actually sources into it is base current:

```
(3.3 - 0.7) / 1000 = 2.6 mA
```

against a 40 mA absolute maximum. **Wire GPIO 17 straight to the LED pin and
PWM it.** No transistor, no gate resistor, no pulldown. `backlight.cpp` needs
no change — it was already only ever driving a pin.

The 60–100 mA figure was right about the *panel* (QD-TFT2803: Vf 3.2 V, If
60 mA nominal, 80 mA max) and wrong about this *module*, which runs those LEDs
off 3.3 V through a 10 Ω series resistor — so somewhere near 15–40 mA. Worth
knowing for the sunlight problem: **this backlight is already running well
under its rated current.**

★ **Confirm it in ten seconds before soldering, because this family of boards
is not consistent** — some genuinely do bring the LED supply straight out, and
Adafruit's own 2.8" breakout has a transistor while other sellers' do not. Put
a **1 kΩ resistor in series** between 3.3 V and the LED pin:

- backlight stays at **full brightness** → there is a transistor, drive it from
  the GPIO as above
- backlight goes **almost dark** → the pin is the LED supply after all, and the
  old advice applies: fit a 2N7000 low-side switch

[msp2807sch]: https://www.lcdwiki.com/res/MSP2807/MSP2807-2.8-SPI.pdf

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

Worth knowing why 27 is a sensible fallback rather than an arbitrary one:
**27 MHz is TFT_eSPI's documented ceiling for *reading pixels back* from the
display**, not for writing. For write-only rendering the library's own guidance
is that "40MHz seems to be OK with ILI9341 displays", with 80 MHz the point
where the controller starts failing. Since this project never calls
`readPixel`, 40 MHz should be reachable once the wiring is soldered — and that
is **48% more bandwidth**, which matters directly for any moving graphics.

For reference, a 320×240 RGB565 frame is 153,600 bytes = 1,228,800 bits:

| SPI clock | Wire time per full frame | Theoretical max FPS |
|---|---|---|
| 27 MHz | 45.5 ms | 22.0 |
| 40 MHz | 30.7 ms | 32.6 |

Measured TFT_eSPI `fillScreen` on ESP32 + ILI9341 at 40 MHz comes in at 31.2 ms
— about 98% of theoretical, which confirms the SPI wire is the wall and the
ESP32 can saturate it.

## Toolchain

Arduino IDE 2.x **from arduino.cc** — not the Microsoft Store build, which is
1.6.11 from 2016 and sandboxed.

Boards Manager URL:
```
https://raw.githubusercontent.com/espressif/arduino-esp32/gh-pages/package_esp32_index.json
```

Board: **WEMOS LOLIN32**.

### Upload from the Arduino IDE, not the command line

Sketches flashed with `arduino-cli` reported a clean write and verified hash,
the sketch ran and printed to serial — and the panel stayed white. The same
sketch uploaded through the IDE worked immediately, with nothing physical
changed in between. The board options are identical between the two
(`CPUFreq=240`, `FlashFreq=80`, same partition scheme), so the cause is not
board configuration and has not been pinned down.

Probable culprit: opening the serial port from a script toggles DTR/RTS, which
on this board drives the auto-reset circuit (EN and GPIO 0). That can leave the
ESP32 held in reset or sitting in download mode — the sketch is in flash and
appears fine, but nothing drives the display.

**Practical rule: upload through the IDE, and don't open COM11 from a script
while debugging the display.** An hour was lost to this, chasing a wiring fault
that did not exist.

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

## ★★ Sunlight readability — do the arithmetic before the test

Researched 22 Aug 2026, ahead of running Stage 4 Test B. **The numbers say a
bare ILI9341 fails in direct Bengaluru noon sun.** Worth knowing before the
test rather than being surprised by it.

### The governing equation

Glare is not subtractive, it is *additive light* laid over the whole panel:

```
L_reflected = E × R / π          E = ambient lux, R = front-surface reflectance
ACR = (L_white + L_reflected) / (L_black + L_reflected)
```

Readable text needs **ACR ≥ 5:1**. Maps and detail want 10:1.

### This panel, this city

Bengaluru clear-sky noon is **~100,000 lux**. A generic ILI9341 module has a
glossy overlay with an air gap, so R ≈ 4.5%.

```
L_reflected = 100000 × 0.045 / π ≈ 1430 nits of grey haze
ACR = (250 + 1430) / 1430 ≈ 1.17 : 1
```

Against a requirement of 5:1. **That is not marginal, it is a grey rectangle.**
Practitioner reports of ILI9341 outdoors agree — washed out, unreadable.

Note what the equation says about mitigation: **cutting ambient light beats
raising backlight.** A 5× reduction in E from a hood does more than a 4×
brighter backlight, and costs a 3D print. Even a 1000-nit panel behind the same
cheap air-gapped front only reaches 1.7:1 — commercial units optically bond and
AR-coat down to ~1% reflectance to get anywhere.

Measured brightness for these modules, where published at all: Winstar
500 cd/m², POLCD ~300, TST28011T 275. Most listings publish nothing.

### Mitigations, cheapest first

1. **Free — rotate the panel 90° and test with the sunglasses you ride in.**
   See the polariser note below. Do this before the enclosure is designed.
2. **₹150–400 — a deep matte-black hood**, 25–35 mm, ribbed or flocked inside.
   Biggest single win available. Attacks E directly.
3. **₹150–300 — matte anti-glare film** cut from a phone screen protector,
   applied *directly to the panel*. AG diffuses rather than eliminating, and
   softens the image — irrelevant when the content is a giant arrow.
4. **Free — the single-glyph layout.** Everything converges to grey in glare, so
   contrast has to come from area and shape, not colour. Never encode anything
   load-bearing in colour alone. This is already the design.
5. **Mount angle** — a screen tilted face-up mirrors the sky. Tilt it toward the
   rider, away from the zenith.

### ★ Polarised sunglasses will black this out, and the fix is free

Every LCD emits **linearly polarised** light. Polarised sunglasses are a linear
polariser. Cross the two at 90° and the screen goes **completely black** — and
it is head-angle dependent, so it comes and goes while riding.

Consumer panels put the polariser axis vertical or horizontal, so **rotating the
module 90° in the enclosure rotates its axis 90°** and can flip it from
invisible to fully visible through polarised lenses.

**This is the highest-value free experiment in the project. Test both
orientations with your own riding sunglasses before the housing is finalised.**

Two things not to do:
- **Do not add a linear polariser sheet** as a DIY anti-glare measure. It either
  halves the brightness or creates the exact blackout it is meant to prevent.
- **A circular polariser (quarter-wave retarder) is the proper fix** but absorbs
  a large fraction of emitted light. At 250 nits that is unaffordable. Only
  viable on a bright panel.

### Plan B, budgeted from the start rather than treated as failure

If hood + film + layout still is not enough at 13:00 on a clear day, the answer
is a part swap, not more mitigation:

| Option | Cost | Trade |
|---|---|---|
| **Sharp Memory LCD 2.7" 400×240** (Adafruit 4694) | ~$45 | **Reflective — gets brighter as the sun does.** ~20% reflectivity in 100k lux ≈ 6400 nits equivalent white. Near-zero power, LCD-speed refresh, 13.5 KB framebuffer fits ESP32 easily. Monochrome, and needs a front light at night. **This is what Garmin Edge and Wahoo use, and why they never publish a nits figure.** |
| 1000-nit sunlight-readable 2.8" IPS 240×320 (Orient Display / Newhaven / Chenghao) | ₹1,500–4,000 + import | Drop-in for the SPI code and keeps colour. Heavy backlight current. Still needs the hood — 1000 nits alone does not solve it. |

A turn arrow and a distance number do not need colour. The Memory LCD is
arguably the technically correct part for this job and always was.

### Calibration point in our favour

**Beeline Moto II publishes no nits figure at all and is widely reported as
readable in bright sun.** Reviewers credit the tiny 1.45" screen, extremely high
contrast, anti-glare coating and auto-backlight — not raw brightness. The design
lever matters as much as the panel.

## Mount

Reuses a **BOBO BM4** phone mount: handlebar clamp → 17 mm ball → socket bracket.
The copper jaw plate (the part that broke) is discarded and replaced with a
printed adapter presenting a 3-lug Garmin-style quarter-turn.

Quarter-turn rather than a clamp screw because a tightened joint holds by
friction, and engine vibration walks friction joints loose. Three lugs behind
solid shoulders is a shear plane — nothing to unwind.

## Enclosure

Roughly 94 × 58 × 20 mm, landscape.

- **ASA, not PETG.** Updated 26 Aug 2026 — PETG is no longer good enough here.
  PLA softens near 55 °C, but **PETG's HDT is only 65–80 °C and its Tg 75–85 °C**,
  which sits inside the estimated sealed-enclosure interior of 53–70 °C in
  Bengaluru sun. ASA gives ~105 °C service, better UV stability, and does not
  yellow. Print it light-coloured: an 18 °C interior difference has been measured
  between otherwise identical dark-grey and light-grey enclosures.

  **The display is the real thermal limit, not the case and not the battery.**
  2.8" ILI9341 modules are rated **operating −20 to +70 °C**, and solar radiation
  raises display surface temperature **40–50 °C above ambient**. A documented
  case had a 50 °C-rated panel reach **90 °C in sun and black out completely**,
  with repeated exposure leaving permanent "solar clearing" spots. A quick-release
  mount so the unit comes off when parked is a legitimate engineering answer —
  it is effectively what Beeline ships.
- **Form-in-place gasket** — a 2 × 1.5 mm groove filled with clear RTV and cured
  with the case closed over cling film. Perfect match for about ₹30.
- **Window** — 2 mm polycarbonate bonded to the *inside* of the bezel, so water
  pressure seats it rather than lifting it.

  **⚠ This conflicts with sunlight readability as currently drawn.** A window
  with an air gap in front of the panel adds two more air/plastic interfaces at
  ~4% reflection each. Published figures: air-gap stacks lose **8–20%** of light
  to reflections, optically bonded stacks **under 5%**. On a 250-nit panel
  already losing to glare, that gap is unaffordable.

  Either **omit the separate window** and seal against the panel's own glass, or
  **optically bond** the polycarbonate to the panel with clear optical silicone
  or UV adhesive so there is no air layer. Decide this before printing — see the
  sunlight section above.
- **Sunshade hood, 25–35 mm, matte black, ribbed inside.** Not cosmetic. Per the
  arithmetic above this is the largest single readability gain available, worth
  more than any backlight change.
- **MOUNTING ANGLE IS THE SECOND-LARGEST GAIN, AND IT IS FREE.** Rider test,
  29 Aug 2026, in real daylight: *"keep it straight up, I'm not able to see
  clearly, but if I adjust the angle I'm able to see it properly."*

  That is the reflection term of the ACR equation, not a preference. A screen
  lying face-up reflects a 100,000 lux sky straight back at the rider, which is
  exactly where the 1430 nits of grey haze above comes from. Tilt it toward the
  rider and it reflects the tank, the road and his own jacket instead — all of
  them orders of magnitude darker. The emitted 250 nits never changes; the
  denominator collapses.

  Two consequences for the build:
    - The ball joint is not a convenience. It is the adjustment that makes this
      panel usable in sun, and any mount that gives it up is the wrong mount.
      The quarter turn sets only which way is up — never the angle.
    - `hood_rake` assumes a near-vertical screen. Once the rider settles on an
      angle, it wants setting to match, or the hood shades the wrong part of
      the sky.
- **Cable gland on the bottom face**, with a drip loop below.
- **ePTFE pressure vent, Ø3 mm.** The part most DIY builds omit. A sealed box in
  the sun reaches 60 °C+; cold rain contracts the air and pulls water past the
  gasket. Membrane can be cut from an old rain jacket.
- Blind screw bosses so fasteners never breach the sealed volume.

Print settings: 0.2 mm layers, **4 perimeters** (the lugs carry all the load),
30–40 % infill.

**Orientation: body mount-face down; lid sealing-face down, hood up.** This
line previously said "sealing face flat on the bed", which is backwards for the
body and loses the print — that orientation gives a 282 mm picture-frame first
layer of only ~338 mm² on a part that shrinks 0.5 %, and asks the tub floor to
bridge 52 × 88 mm of open air. Mount-face down gives a full 57 × 93 mm first
layer and prints the sealing rim as the top face, where it comes out accurate
and free of elephant's foot.

Drawings in `hardware/mount-design.html`.

### ★ Partition scheme: Minimal SPIFFS, not Default

Adding WiFi and ArduinoOTA took the sketch from 51% to **97%** of the default
partition. OTA needs **two** app partitions — the incoming image is written to
the inactive one while the current one runs — so 97% does not mean "nearly
full", it means OTA would succeed once and then have nowhere to go.

In the Arduino IDE: **Tools → Partition Scheme → "Minimal SPIFFS (Large APPS
with OTA)"**. On the command line, `--fqbn esp32:esp32:lolin32:PartitionScheme=min_spiffs`.

That moves it to **65% of 1.97 MB**, which leaves room to keep building.

**The setting must match when you flash over USB.** Upload with the default
scheme and the image lands in a layout the OTA partitions do not agree with;
the device runs, and the first OTA attempt fails in a way that looks like a
network fault. Set it once in the IDE and it sticks per board.

This is exactly the kind of thing BUILD_PLAN Stage 10 exists to find before the
case is sealed. Discovered on the bench, it is a menu item; discovered after
gluing, it is a cracked enclosure.
