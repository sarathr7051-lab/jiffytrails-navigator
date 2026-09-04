# Hardware

## Bill of materials

| Part | Detail | ₹ |
|---|---|---|
| ESP32 **LOLIN32** | USB-C, CH340 USB-serial | 449 |
| **SmartElex 2.8" TFT** | ILI9341, SPI, 240×320, **non-touch** | 815 |
| MB102 breadboard | 830 points | 65 |
| Jumper wires | M2M / M2F / F2F, 20 each | 139 |
| Soldering kit + multimeter | 60 W adjustable, pump, wick, flux, stand | 1,000 |

### Still to buy — ★ REWRITTEN 1 Sep 2026, THE OLD LIST BOUGHT THE WRONG PARTS

The line here used to read "polycarbonate window, clear RTV, M8 cable gland,
M3/M4 fasteners, anti-glare film, PETG filament". **Three of those parts are not
in the design and three that are were missing.** Against `hardware/case.scad`:

| Part | Detail | Why |
|---|---|---|
| **ASA filament, light coloured** | **not PETG, never PLA** | PETG's HDT is 65–80 °C against a sealed interior estimated at 53–70 °C in Bengaluru sun. See the Enclosure section. |
| **Closed-cell EPDM foam tape, 3 mm** | 4 mm wide, closes to 2 mm = 33% compression | The seal. `foam_w = 4.0`, `foam_d = 2.0`. ★ **Closed-cell, NOT open-cell polyurethane** — most cheap foam tape is open cell and wicks like a sponge. Test it: hold a piece under water and squeeze. Open cell streams bubbles and stays wet. |
| **M3 self-tapping screws** | **8 × M3 × 14** (cap → lid → body), **2 × M3 × 5** (hood) | ★ **REWRITTEN 3 Sep 2026 for the bayonet mount** — the line above used to say 8 × 12, 4 × 8 and 2 × 6, and all three were for the dovetail. The eight now run through **three** parts as one fastener set: 2.4 mm of mount cap under its counterbore, 5.0 mm of lid, then a 2.5 mm pilot 9.0 mm blind into the body. ×14 gives 6.6 mm of thread and never bottoms; ×12 gives 4.6 and ×16 is 0.4 mm from the floor. ★ **PAN head** (DIN 7981, 5.6 × 2.4), not socket cap: the cap's counterbore is 2.6 mm deep and a DIN 912 cap head is 3.0 mm tall, so it stands proud into the collar. ★ **The hood's two are ×5, NOT ×6** — `hood_pilot_len` is 4.0 mm blind over a 2.0 mm floor and a ×6 bottoms out before the hood is tight. ★ **There is no mount plate any more**; its 4 × M3 × 8 are deleted. Measured off the printed geometry, not the drawing: cap, lid and body carry the same eight positions, verified by solid intersection. |
| **M3 brass heat-set insert** | 1, for the mount adapter | The BM4's screw runs socket → plate into a brass insert, so our part carries the female thread. `MOUNT_INTERFACE.md` §3. ★ **Not for the case** — `case.scad` rejects inserts there: they need a 4.0 mm bore and 1.6 mm of wall either side, costing 2.4 mm of envelope in both directions, and eight iron-driven insertions into a part that cannot be reprinted. |
| **ePTFE membrane, Ø6 vent** | can be cut from an old rain jacket | Free |
| **Potting compound** | clear RTV or epoxy, for the cable entry | ★ **No cable gland.** See below. |
| **USB-C cable, ≤ Ø4.5 mm** | thin, right-angle at the bike end; the far plug is cut off and soldered inside | ★ `cable_bore_d = 4.5` and the case is printed. A braided cable is 5–6 mm and will not go through. Measure with a paper strip: circumference ÷ 3.1416. |
| **Power protection** | SMBJ6.0A TVS, 220 µF hybrid/polymer 16 V, 100 nF ceramics, ferrite bead, 1 A polyfuse | `FEATURES.md` "Decision: cable power, no battery". ★ 6.0A not 5.0A. ★ Polymer, not 85 °C electrolytic. |
| **USB power meter** | inline, cheap | Answers whether the Speed 400's socket is ignition-switched or always live, and its real current. Nobody has measured either. |
| Anti-glare film | cut from a phone screen protector | Sunlight section |

**Deleted, and do not buy:**

- **M8 cable gland** — ★ the entry is **potted**. An M8 gland's Ø14 locknut needs
  16 mm of clear flat wall on the inside, in a position this case does not have.
- **Polycarbonate window** — ★ **there is no separate window.** The front is
  closed and the panel is bonded behind it; `bezel()` does the precise work. A
  window with an air gap in front of the panel is also the wrong answer
  optically — see the Enclosure section.
- **M4 fasteners** — nothing in `case.scad` or `mount_v4.scad` uses M4. The only
  bolt in the whole mount is the BM4's own ISO 10642 M3 × 10 countersunk, which
  you already have. (`mount.scad`, which carried an M4 rule, is the abandoned
  dovetail design and is not what is printing.)

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
| LED | **GPIO 17** |

### Gotchas

**★ LED goes to GPIO 17, NOT to 3V3.** This table said `3V` until 29 Aug 2026
and it was wrong - `backlight.cpp` has owned GPIO 17 through the LEDC PWM
peripheral since the day/night dimming went in. Wiring LED to 3V3 leaves the
backlight stuck at full brightness with no dimming. Wiring it to BOTH - which
is what someone following the old table *and* the firmware would do - shorts
3V3 to ground through GPIO 17 every time the firmware dims, and that damages
the pin. One wire, to GPIO 17.


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

### ★ Backlight control — GPIO 17, PWM, and NO EXTERNAL TRANSISTOR

★ This section used to open "`LED` is tied straight to `3V`, the backlight is
therefore always on at full brightness". **Both halves are stale.**
`backlight.cpp` has driven GPIO 17 through the LEDC PWM peripheral (20 kHz,
10-bit) since day/night dimming went in, and the pin table above is the wiring.

★ It also said `User_Setup.h` "reserves `TFT_BL 17` and `TFT_BACKLIGHT_ON HIGH`,
commented out, for when this changes". **Those two defines must STAY commented
out, and not by oversight.** Defining `TFT_BL` makes TFT_eSPI drive the same pin
during init, and two owners on one GPIO fight: the library's plain
`digitalWrite` tears down the LEDC channel `backlight.cpp` attached. The
backlight is not TFT_eSPI's job in this build.

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
**27 MHz is TFT_eSPI's documented ceiling for *reading back* from the display**,
not for writing. For write-only rendering the library's own guidance is that
"40MHz seems to be OK with ILI9341 displays", with 80 MHz the point where the
controller starts failing. So 40 MHz should be reachable once the wiring is
soldered — **48% more bandwidth**, which matters directly for moving graphics.

★ **CORRECTED — THE FIRMWARE DOES READ THE PANEL, AND READS HAVE THEIR OWN
CLOCK.** The reasoning above used to close with "since this project never calls
`readPixel`". That is no longer true. `display.cpp` runs a boot probe
(`panelReadable`) and re-reads `MADCTL` twice every two seconds; **that watchdog
is the one mechanism that can recover the mirrored-screen fault**, and it
disarms itself if the reads come back as garbage.

Reads and writes are separately clocked, which is what makes raising the write
clock safe:

```
User_Setup.h    SPI_FREQUENCY       27000000   writes  <- raise this to 40 MHz
                SPI_READ_FREQUENCY   6000000   reads   <- LEAVE THIS ALONE
```

**6 MHz, not 20.** MISO is wired, yet at 20 MHz the boot probe kept returning
garbage and disarming the watchdog — so the recovery mechanism was switched off
by a number, not by a missing wire. Reads happen twice every two seconds and
their speed is worth nothing.

**Check the boot line before and after any SPI change.** If it says "watchdog
armed", the watchdog is real and a corrupted MADCTL heals itself within six
seconds instead of persisting until a power cycle. If it says "DISABLED", the
read clock is too fast or MISO is not connected.

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

Reuses a **BOBO BM4** phone mount: handlebar clamp → **Ø17 mm ball** (VERIFIED)
→ collet + collar → socket → phone plate.

★ **THE JAW BROKE. THE PLATE DID NOT.** This section used to say "the copper jaw
plate (the part that broke) is discarded". Only the **jaw** — the sprung grip
that holds a phone — failed, and the jaw is not used here. **The plate is
undamaged and is kept**: it is the measurement reference for the interface, and
the fallback if a printed part disappoints.

★ **THE MOUNT IS NOT METAL.** The socket and the plate are both polymer. **The
only metal in the whole mount is one ISO 10642 M3 × 10 countersunk screw.**

The printed adapter takes the plate's place in the stack, which means it has to
reproduce the plate's own interface to the socket:

- a **square cavity** — ★ CORRECTED 2 Sep 2026: the socket's square
  **protrudes** 2.0 mm and the plate's is the recess, not the other way round.
  Ours is 14.5 mm across flats, 2.42 mm corner radius, **2.20 mm deep** — deeper
  than the boss is tall, so our flat face seats on the socket's flat face and the
  square only keys rotation. It also puts the seating face flat on the print bed
  as the first layer, which is why it needs no support;
- an **M3 brass heat-set insert** on the centre line. The screw runs socket →
  plate, so **our part carries the female thread.** This withdraws the earlier
  project rule "no thread in printed plastic" — a brass insert is what BOBO
  themselves did, for the same reason;
- **no 90° countersink** — the screw head lands on the socket, not on us.

Full measurements and the reasoning: **`docs/MOUNT_INTERFACE.md`**, which
supersedes `COMPONENT_DIMENSIONS.md` §3 and the narrative in
`hardware/mount.scad`.

★ **The dovetail is gone too. The joint is a quarter-turn bayonet** —
`hardware/mount_v4.scad`, superseding `mount.scad`, `mount_v2.scad`,
`mount_v3.scad` and `dovetail.scad`, which remain only as history. Three lugs
on a central boss drop through three slots in the adapter's collar, a **55°**
twist takes them under a flat shoulder, a printed spring blade drops a tooth
into a notch, and hard stops arrest it 3° past the lock. One lug is 48° wide
against 44° slots so it goes on exactly one way. Release is a firm twist,
around 0.4 N·m — the retaining flanks are ramped at 60° because the release
tab sits under the cap where no finger can reach it. Verified in two geometry
kernels (CGAL and OCCT): 0.000 mm³ interference locked, 244 mm³ against a 3 mm
lift, and the spring at 1.26 % root strain over its real 18.5 mm free length.
The full record is in the git history of 3 Sep 2026 and the review pages it
links.

The rider's case pockets when parked and the adapter stays on the bike; the
same eight screws that seal the lid also fix the cap, so mount load never
passes through the foam seal.

## Enclosure

★ **REWRITTEN 1 Sep 2026. EVERYTHING THIS SECTION USED TO SAY DESCRIBED THE
ABANDONED FRONT-OPENING CASE** — "94 × 58 × 20 mm", an RTV gasket groove, a
Ø3 vent, a bonded polycarbonate window, 4 perimeters, a cable gland, and a print
orientation that is **the opposite of the one now required**. `hardware/case.scad`
is the authority.

**The case opens at the BACK.** The previous version was a tub facing the rider
with the lid carrying the window and the hood, and the sealing line ran right
around the display glass — the most crowded, least forgiving line on the part.
Turning it round dissolved five separate failures rather than solving them: the
screw bosses that stood inside the display's footprint, a gasket groove with no
inner wall, an unsealed window, a lid that could not clamp a gasket across an
82 mm span on four corner screws, and **the USB hole in a sealed wall**.

    THE FRONT IS CLOSED FOR GOOD, with the panel bonded behind it.
    THE BACK IS THE LID — a plain plate. No window, no hood, nothing to align.

**USB is reached by taking the back off.** There is no port opening.

### Size and print settings

**64.4 × 96.4 × 39.34 mm.** (`body_w` × `body_l` × overall.)

- **ASA, light coloured. Not PETG and never PLA.** PLA softens near 55 °C, and
  **PETG's HDT is only 65–80 °C, its Tg 75–85 °C** — inside the estimated sealed
  interior of 53–70 °C in Bengaluru sun. ASA gives ~105 °C service, better UV
  stability, and does not yellow. An 18 °C interior difference has been measured
  between otherwise identical dark-grey and light-grey enclosures.
- **0.2 mm layers, 5 perimeters** — four is the usual watertight threshold and a
  sealed case earns the fifth. ★ This said **4** and cited "the lugs carry all
  the load"; there are no lugs.
- **30–40% infill.**
- **ENCLOSURE OR DRAFT SHIELD MANDATORY.** ASA delaminating mid-print on a
  100 mm part in a draught is the likeliest way to lose the one print available.

### ★ ORIENTATION — THE OLD LINE HERE WAS BACKWARDS AND WOULD HAVE COST THE PRINT

The deleted instruction read **"body mount-face down; lid sealing-face down,
hood up"**. There is no mount face on the body any more and no hood on the lid.

| Part | Orientation |
|---|---|
| **body** | **FRONT FACE DOWN.** Puts the sealing rim on top, where it prints accurately with no elephant's foot, and the flange flares outward going up at 45° so it is self-supporting. **5 mm brim** — the first layer is a picture frame and adhesion is not optional. |
| **lid** | **OUTER FACE DOWN.** ★ The warning that stood here about a 4 mm picture frame and a 56 × 88 bridge described the mount plate's keying recess, deleted with the dovetail. Measured on the current part: 6085.8 mm² of solid first layer, no bridge, nothing over 45°. The easiest print of the set. |
| bezel | flat, trivial |
| hood | **MOUTH DOWN.** Two first-layer islands — the vent window cuts the skirt ring through its full height and they only join at z 15. Brim both. Its window ceiling is the only real bridge in the set, 27 mm. |
| mount adapter | **SEATING FACE DOWN.** The square cavity is the first layer, 1248 mm² flat on the bed, no support and no witness marks on the one datum that must be true. |
| mount cap | **OUTER FACE DOWN**, support in the pocket only. |

### Sealing, venting and cable entry

- **★ CLOSED-CELL EPDM FOAM TAPE, NOT AN RTV GROOVE AND NOT AN O-CORD.** 3 mm
  tape closing to 2 mm is 33% compression with a ±0.5 mm usable band. An O-cord
  at 25% squeeze has a ±0.15 mm band — and an ASA part this size **bows
  0.3–0.8 mm as it cools**, so the gasket would be defeated by warp alone before
  it ever met water. Foam also drops the closing force to ~5 N per screw, which
  is what makes self-tapping screws viable. **Buy closed-cell: most cheap foam
  tape is open-cell and wicks like a sponge.**
- **★ ePTFE pressure vent, Ø6 MINIMUM — not Ø3.** The part most DIY builds omit.
  A sealed box in the sun reaches 60 °C+; cold rain contracts the air and pulls
  water past the seal. Ø3 does not equalise fast enough on a 60-second quench.
  Membrane can be cut from an old rain jacket, bonded to a Ø12 recessed land.
- **★ POTTED CABLE ENTRY, NOT A GLAND.** An M8 gland's Ø14 locknut needs 16 mm
  of clear flat wall inside, in a position this case does not have — which is
  why the old design's gland never worked out. Drip loop below, as before.
- **Blind screw bosses**, bottoming in solid ASA, so no fastener ever breaches
  the sealed volume. That is what makes it safe to run the eight lid screws
  straight through the foam band.
- **★ NO SEPARATE WINDOW.** The front is closed and the panel is bonded behind
  it; `bezel()` cuts the aperture. This is also the optically correct answer: a
  window with an air gap in front of the panel adds two more air/plastic
  interfaces at ~4% reflection each, and air-gap stacks lose **8–20%** of light
  against **under 5%** for optically bonded ones. On a 250-nit panel already
  losing to glare, that gap was unaffordable.

### The display is the real thermal limit, not the case and not the battery

2.8" ILI9341 modules are rated **operating −20 to +70 °C**, and solar radiation
raises display surface temperature **40–50 °C above ambient**. A documented case
had a 50 °C-rated panel reach **90 °C in sun and black out completely**, with
repeated exposure leaving permanent "solar clearing" spots. **A quick-release
mount so the unit comes off when parked is a legitimate engineering answer** —
it is effectively what Beeline ships, and the quarter-turn bayonet provides it —
one twist and the case is in a pocket.

### Hood and mounting angle

- **Sunshade hood, 30 mm deep, matte black, 5 ribs inside.** Not cosmetic. Per
  the sunlight arithmetic above this is the largest single readability gain
  available, worth more than any backlight change. Bolt-on, two **M3 × 5** into
  blind pilots in pads on the body's sides — ★ ×5, not ×6: the pilot is 4.0 mm
  over a 2.0 mm floor and a ×6 bottoms out before the hood is tight.
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
      The bayonet sets only which way is up — never the angle.
    - **`hood_rake = 12` is provisional.** Once the rider settles on an angle it
      wants setting to match, or the hood shades the wrong part of the sky.

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
