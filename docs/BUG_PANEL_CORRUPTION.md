# BUG: Panel corruption on the ARRIVED screen

**Observed:** one night ride, 2026-08-29. Photographed. Not reproduced.
**Status:** analysis complete, no source edited. Diagnostic document.

> **Epistemic warning, up front.** This is **one** observation of a physical
> fault, with no serial log, no scope trace and no reset-reason record. A single
> event constrains almost nothing quantitatively. Everything below is ranked by
> mechanism plausibility, not by evidence weight, and §7 separates what is
> **verified** from what is **inferred** from what is **unknown**. The most
> valuable output of this document is not the ranking — it is §8.0, the list of
> observations that would actually discriminate between the top hypotheses, and
> the zero-cost forensics sketch that can settle §2 in twenty minutes on the bench.

---

## 1. The observation

From the photograph, on the handlebar, at the end of a night ride:

| # | Symptom | |
|---|---|---|
| A | The word **ARRIVED** is drawn **mirrored horizontally**, and appears **vertically flipped** as well | reversed lettering |
| B | The **left ~40%** of the panel is a block of **diagonal hatching / noise**, visually distinct from the rest | |
| C | The **right portion is white**, with the mirrored text on it | |
| D | The state **persisted** long enough to be photographed | |

### 1.1 What each symptom is evidence *of*, before any hypothesis

- **(A) is evidence of a register, not of noise.** Stable, legible, geometrically
  coherent mirrored text is a *correctly executed write through a wrong address
  mapping*. Random bit errors do not produce readable mirrored glyphs. This
  points at MADCTL (0x36) and essentially nothing else. See §2.
- **(B) is evidence of stored pixels, not live interference.** It was stable
  enough to photograph, so it is content sitting in GRAM, not a display artefact.
  Something *wrote* that, or something *failed to overwrite* what was already
  there. See §4.
- **(C) tells us the `fillScreen` ran and mostly worked.** C_BG on the day
  palette is `TFT_WHITE` (`display.cpp:60`, `display.cpp:1241`). See §1.2 —
  this also tells us something about night mode.
- **(D) is, on this firmware, expected and not diagnostic of anything.** See §6.
  The ARRIVED screen paints once and then *never repaints*. Persistence is a
  property of the renderer, not of the fault.

### 1.2 A side finding: night mode was almost certainly OFF

`C_BG` is `TFT_WHITE` only in the day palette. In night mode
(`display.cpp:1234`) `C_BG = TFT_BLACK` and `C_FG = 0xDEFB`.

`nightMode` has exactly one writer — `displaySetNight(state.night)` from
`navigator.ino:94` — and `state.night` has exactly one writer, `handleConfig`
in `ble.cpp:269-272`, fed by an *optional tail byte* on the BLE CONFIG packet.
`NavState::night` defaults to `false` (`nav_types.h:115`).

So a **white** background on a **night** ride means one of:

1. **The phone never sent `night=1`** — the CONFIG packet was absent, or was the
   older short form without the night tail. Most likely; the Android side is
   still unbuilt (`navigator.ino:8` — "No Android app yet").
2. Night was set, and the panel additionally had **display inversion** turned on
   (INVON, 0x21) — which would flip black→white and the ~88% white text→dark.

Option 2 would be a *second* spontaneous register change, which raises the
prior on "a stray command byte was latched" considerably (§3.1). **This is
worth resolving and is free to resolve:** check whether the phone/navsim was
sending a CONFIG with night set on that ride. If night *was* configured, the
whole diagnosis changes and INVON joins MADCTL as a corrupted register.

**Action:** confirm from the ride's phone-side config whether `night=1` was sent.

---

## 2. Which register produces mirrored text: MADCTL (0x36)

### 2.1 What the firmware sets, and when

`display.cpp:41` — `static const uint8_t ROTATION = 1;` (landscape).

TFT_eSPI 2.5.43, `TFT_Drivers/ILI9341_Rotation.h`, case 1, non-M5STACK branch:

```c
writecommand(TFT_MADCTL);
writedata(TFT_MAD_MV | TFT_MAD_COLOR_ORDER);
```

With `TFT_MAD_MV = 0x20` and `TFT_MAD_COLOR_ORDER = TFT_MAD_BGR = 0x08`
(`TFT_Drivers/ILI9341_Defines.h:56-72`):

> **The expected runtime MADCTL value on this build is `0x28`.**

It is written in exactly two places, both of which call `setRotation(ROTATION)`:

- `displayBegin()` — `display.cpp:1069-1070`, once at boot.
- `displayTick()` recovery path — `display.cpp:1272-1273`, **unreachable**,
  because `panelReadable` is false on this wiring (`display.cpp:1252`).

**So MADCTL is written once per boot and never again.** For it to hold a wrong
value at ARRIVED time, the panel must have received a `0x36` command + parameter
it was never *deliberately* sent, **or** the boot-time write itself was
corrupted (which requires a reboot — see §3.3).

### 2.2 The bit definitions (datasheet, verbatim)

ILI9341 datasheet v1.11, **§8.2.29 Memory Access Control (36h)**, page 127
([ILI Technology / Adafruit mirror](https://cdn-shop.adafruit.com/datasheets/ILI9341.pdf),
also [Newhaven mirror](https://newhavendisplay.com/content/app_notes/ILI9341.pdf)):

| Bit | Mask | Name | Datasheet description |
|---|---|---|---|
| D7 | 0x80 | MY | Row Address Order |
| D6 | 0x40 | MX | Column Address Order |
| D5 | 0x20 | MV | Row / Column Exchange |
| D4 | 0x10 | ML | Vertical Refresh Order |
| D3 | 0x08 | BGR | RGB-BGR Order |
| D2 | 0x04 | MH | Horizontal Refresh Order |

Quoted exactly from the page:

> "This command defines read/write scanning direction of frame memory."
> "This command makes no change on the other driver status."
> MY / MX / MV: **"These 3 bits control MCU to memory write/read direction."**
> ML: "LCD vertical refresh direction control."
> MH: "LCD horizontal refreshing direction control."
> "Note: When BGR bit is changed, the new setting is active immediately without
> update the content in Frame Memory again."

**Reset default: `00h`** (the parameter row's HEX column on p.127).

### 2.3 ★ The single most important consequence, and it is easy to get wrong

**MY / MX / MV are *write-side* controls. They remap where incoming pixels
land. They do NOT move pixels already sitting in GRAM.**

The datasheet states this by contrast: it goes out of its way to say that the
**BGR** change *is* "active immediately without update the content in Frame
Memory again" — a note that is only worth writing because the neighbouring bits
are **not**. MY/MX/MV are described as controlling "MCU to memory write/read
direction", i.e. the address counter, and the panel's GRAM→pixel scan mapping
is fixed (ML/MH only alter refresh *order*, not placement).

This has three consequences that drive the whole rest of the analysis:

1. **A MADCTL change is not retroactive.** Whatever was on screen before the
   change stays exactly where it was. Only content drawn *afterwards* is
   mirrored. So the mirrored ARRIVED text was drawn **after** the corruption,
   and the white field it sits on was probably drawn **before** it.
2. **Re-asserting MADCTL does not fix a corrupted frame.** It fixes the *next*
   frame. This is the key limitation of the "just call `setRotation()`
   periodically" mitigation — see §5.1. It must be paired with a forced repaint.
3. **MADCTL also changes the panel's addressable extent** (§2.5), which is the
   bridge to symptom (B).

### 2.4 Which value produces "mirrored horizontally AND flipped vertically"

From `0x28` (MV | BGR), the candidates, using TFT_eSPI's own rotation table as
the reference for what each looks like:

| MADCTL | Bits vs 0x28 | TFT_eSPI rotation | Visual effect vs correct render | Geometry |
|---|---|---|---|---|
| `0x28` | — | 1 | **correct** | 320 × 240 landscape |
| `0x68` | +MX | 5 | mirrored horizontally only | 320 × 240 landscape |
| `0xA8` | +MY | 7 | flipped vertically only | 320 × 240 landscape |
| **`0xE8`** | **+MX +MY** | **3** | **180° rotation = H-mirror *and* V-flip** | **320 × 240 landscape** |
| `0x08` | −MV | — | transposed (90°), no mirror | **240 × 320 portrait** |
| `0xC8` | −MV +MX +MY | — | transposed **and** point-reflected | **240 × 320 portrait** |
| `0x00` | HW-reset default | — | transposed, RGB order (colours swapped) | **240 × 320 portrait** |

> **Symptom (A) — horizontally mirrored *and* vertically flipped, with the panel
> still filling as a 320-wide landscape screen — is `MADCTL = 0xE8`.**
> That is `TFT_MAD_MY | TFT_MAD_MX | TFT_MAD_MV | TFT_MAD_BGR`, i.e. exactly
> TFT_eSPI's **rotation 3**: the 180° partner of the rotation the firmware asks
> for. Two bits, D7 and D6, both flipped 0→1. Both are the **top two bits of the
> byte**, i.e. the **first two bits clocked out** on an MSB-first SPI write.

That last detail matters and is developed in §3.2.

**Caveat, and it is a real one.** A 180° rotation and a *transpose-plus-mirror*
(`0xC8`) both photograph as "reversed lettering that also looks upside down."
They are distinguishable — under `0xE8` the word still runs left-to-right along
the panel's long axis; under `0xC8` it runs along the short axis and the panel
geometry breaks. **Re-examining the photograph for which axis the word runs
along is the single cheapest discriminating observation available** (§8.0).

### 2.5 The bridge to symptom (B): MV changes the panel's addressable width

Datasheet **§8.2.20 CASET (2Ah)**, p.110, Note 1, verbatim:

> "When SC [15:0] or EC [15:0] is greater than 00EFh (When MADCTL's B5 = 0) or
> 013Fh (When MADCTL's B5 = 1), data of out of range will be ignored"

and the CASET default table, same page:

> "If MADCTL's B5 = 0: EC [15:0]=00EFh — If MADCTL's B5 = 1: EC [15:0]=013Fh"

**B5 is MV.** So:

- MV = 1 → columns 0…**319** valid. Landscape. TFT_eSPI's `CASET(0,319)` is legal.
- MV = 0 → columns 0…**239** valid. Portrait. TFT_eSPI still sends `CASET(0,319)`
  because `_width` is a host-side variable — and **the out-of-range data is
  ignored by the controller.**

So **any corruption that clears MV silently truncates every window the library
sets**, and the pushed pixel count no longer matches the window. That is a
direct, datasheet-supported mechanism for "part of the screen did not get
painted." Hold that thought for §4.

---

## 3. What makes MADCTL change spontaneously — ranked

MADCTL is not written at runtime (§2.1). So one of the following happened.

### 3.1 ★ H1 — A stray byte was latched as a command mid-transaction (D/C or CS integrity)

**Mechanism.** In 4-line SPI the panel decides "command vs data" solely from the
D/CX pin level at each byte boundary. `drawArrived()` pushes ~186 kB with **CS
held low the entire time** (TFT_eSPI brackets an operation with
`begin_tft_write`/`end_tft_write`; `CS_L`/`CS_H` in
`Processors/TFT_eSPI_ESP32.h:204-239`). If D/CX (GPIO 2) dips low for one byte
period, the panel latches whatever byte is on the bus **as a command**, and
subsequent bytes as its parameters. If that byte happens to be `0x36`, the very
next byte becomes the new MADCTL.

**Is `0x36` reachable in the pixel stream?** In a solid `fillScreen(WHITE)` the
stream is all `0xFF` — `0x36` never appears, and `0xFF` is not a defined ILI9341
command. But `drawArrived()` also draws a 72 px maneuver glyph and smooth-font
text (`SMOOTH_FONT` is enabled, `User_Setup.h:40`), whose anti-aliased blend
colours span the full byte range. `0x36` is reachable there. Likewise `0x21`
(INVON) — relevant if §1.2 option 2 holds.

**Corroborating datasheet fact** (§8.2.22 RAMWR, p.114, verbatim):

> "Sending any other command can stop frame Write."

So a single spurious command byte does **two** things at once: it changes a
register **and** aborts the in-progress pixel write, leaving a region unpainted.
**One glitch, both symptoms.** This is why H1 ranks first — it is the only
single-event hypothesis that reaches for both (A) and (B) without extra
assumptions.

**Physical plausibility.** D/CX is GPIO 2 on this build (`User_Setup.h:23`).
GPIO 2 is an ESP32 **strapping pin** and on most LOLIN32-class boards carries an
onboard LED and/or a pull-down — extra capacitance and a bias toward the
*dangerous* level (low = command mode). On an MB102 with ~150–200 mm dupont
wires, adjacent conductors couple ~1–2 pF/cm. A 3.3 V edge with ESP32's ~1–2 ns
slew into ~2 pF of mutual capacitance against D/CX's ~50 pF load injects on the
order of 100–150 mV per aggressor edge — normally well inside the noise margin,
but the margin is already eroded by a rail measured at **3.18 V** (HARDWARE.md
line 47) and by running the bus at 2.7× the datasheet clock (§3.6).

**Rank: 1 of 5.** Best explanatory coverage. Unverified.

### 3.2 H2 — SPI bit errors from breadboard SI at 27 MHz

**The numbers.**

| Quantity | Value |
|---|---|
| SPI clock | 27 MHz (`User_Setup.h:44`) |
| Bit period | **37.04 ns** |
| Nominal SCK high / low | 18.5 ns each |
| **Datasheet min `twc` (serial clock cycle, write)** | **100 ns → 10 MHz max** |
| Datasheet min `twrh` / `twrl` (SCK H/L pulse width) | 40 ns each |
| Datasheet max `tr` / `tf` | 15 ns |
| Data setup `tds` / hold `tdh` | 10 ns |
| D/CX setup `tas` / hold `tah` | 10 ns |
| CS setup `tcss` | 40 ns |

Source: datasheet **§18.3.4 Display Serial Interface Timing Characteristics
(4-line SPI system)**, p.243. *(The PDF's table columns extract with mangled
alignment; the `twc = 100 ns` figure matches the widely cited ILI9341 10 MHz
write-clock spec and I am confident in it. Treat the sub-figures as indicative.)*

> **★ This build runs the panel at 2.7× its specified maximum write clock, and
> its SCK pulse widths are 46% of the specified minimum.** A 40 MHz build would
> be 4×. This is completely normal practice with ILI9341 — the part is far more
> capable than its spec — but it means **there is no guard band at all**. Every
> other marginality (a 4% low rail, breadboard inductance, a hot enclosure,
> vibration on a dupont contact) eats directly into a margin the datasheet does
> not promise exists.

Also note: at 27 MHz the bit cell is 37 ns against a **15 ns** specified
rise/fall time — **edges occupy up to 40% of the bit cell**. At 20 MHz that
falls to 30%, at 10 MHz to 15%. This is the honest reason to reduce the clock
(§5.2), and it scales linearly with period, not dramatically.

**The rate argument — why this fits "worked for months, failed once".**
A full-screen fill is 320 × 240 × 16 = **1,228,800 bits**. `drawArrived()`
in total is roughly:

| Operation | Pixels | Bytes | Time @27 MHz |
|---|---|---|---|
| `fillScreen(C_BG)` | 76,800 | 153,600 | **45.5 ms** |
| `drawManeuver` 72×72 box | ≤5,184 | ≤10,368 | ≤3.1 ms |
| "ARRIVED", font 4, size 2 | ~11,000 | ~22,000 | ~6.5 ms |
| **total** | **~93,000** | **~186,000** | **~55 ms**, ~1.49 Mbit |

If the bit error rate were 1 × 10⁻⁶, you would get **1.2 errors per fill** —
constant, obvious, unmissable corruption. One event in months of use implies a
BER somewhere around **10⁻⁹ to 10⁻¹⁰**. That is the signature of a link that is
*fine* until a second stressor arrives, and it is exactly why this will not
reproduce on a bench at room temperature.

**Weakness of H2 alone.** Random bit errors in a `fillScreen(0xFFFF)` stream are
*invisible* — every bit is already 1, and a dropped or inserted clock in an
all-ones stream produces all ones. Bit errors do not by themselves rewrite
MADCTL; they need H1's D/CX mechanism to become a *command*. **H2 is best
understood as the enabling condition for H1, not as a competing explanation.**

**Rank: 2 of 5 — as an enabler.** Partly verified (the clock overspec is a hard
fact; the error rate is inferred).

### 3.3 H3 — Brown-out reboot of the ESP32, with a corrupted MADCTL on re-init

**Mechanism.** The 3.3 V rail dips (BLE TX burst, backlight, vibration on a
power jumper, a marginal USB/12 V source). The ESP32 brown-out detector fires
and resets. `setup()` re-runs, `displayBegin()` calls `tft.init()` +
`setRotation(1)`. If **that** MADCTL parameter byte is corrupted — and it is
being written moments after a supply event, the worst possible moment for signal
integrity — the panel is 180° for the rest of the session.

**Supporting detail.** Remember the wrong value is `0xE8` and the correct one is
`0x28`: the two changed bits are D7 and D6, **the first two bits clocked out of
an MSB-first byte**. A byte whose *leading* bits read high is precisely the
signature of a line still ringing/settling from the transition that preceded it
— CS falling, or D/CX going high after the command byte. This is a suspiciously
good fit and is worth taking seriously.

**Testable for free.** `esp_reset_reason()` at boot, printed to serial, plus a
boot counter in RTC-retained memory. See §8.1. **Nothing currently records
this**, so a mid-ride reboot is presently invisible after the fact.

**Weakness.** A reboot would drop to `UI_DISCONNECTED`, require BLE
re-connection, and require the phone to re-send an ARRIVED packet. Possible, but
it is a chain. And it still does not explain (B): after a reboot,
`displayBegin()` does a full `fillScreen`, and with MV still set in `0xE8` that
fill covers the whole panel.

**Rank: 3 of 5.** Unverified, but the *cheapest to rule in or out*.

### 3.4 H4 — Missing decoupling / supply dip without a reboot

HARDWARE.md records **3.18 V at the `3V` pin with the backlight lit** (line 47,
22 Aug 2026) — a 4% droop, described there as "the LDO working rather than
coasting." There is no mention anywhere in the repo of a decoupling capacitor
at the panel.

The dynamic picture is worse than the static one. The ESP32's BT/BLE transmitter
draws burst currents in the ~100–130 mA region on advertising and connection
events, with edges in the microsecond range. An MB102 breadboard rail presents
roughly 10–20 nH per inch of loop inductance with no bulk capacitance near the
load. dI/dt of 100 mA in 1 µs across ~100 nH is only ~10 mV, but the real
transients are far faster than 1 µs and the MB102's own power module is
notoriously soft. A supply that is already 4% low and dipping further at radio
cadence narrows every logic threshold on both ends of the bus simultaneously.

This is **a cause of H1 and H2**, not an independent path to a wrong MADCTL.
But it is the cheapest thing on the entire list to fix (§5.3), so it earns its
rank on remediation value rather than on explanatory power.

**Rank: 4 of 5 as a direct cause; ★ rank 1 as a thing to fix.**

### 3.5 H5 — Floating or glitched RESET — ✗ **effectively ruled out**

Datasheet **§15.4 Reset Timing**, p.230, verbatim:

| RESX Pulse | Action |
|---|---|
| Shorter than 5 µs | **Reset Rejected** |
| Longer than 10 µs | Reset |
| Between 5 and 10 µs | Reset starts |

> "Note 3: During the Resetting period, **the display will be blanked** ... And
> then return to Default condition for Hardware Reset."

Two independent reasons this is not what happened:

1. **A reset blanks the display.** The photographed screen showed content. That
   is the signature of the *previously observed* failure documented at
   `display.cpp:800-805` ("renders correctly, then goes blank white") — a
   **different** fault. This one is not that one.
2. **A reset sets MADCTL to `00h`**, which clears MV → portrait geometry and
   RGB colour order. Symptom (A) requires MV *set*.

Also: the panel would need SLPOUT + DISPON re-issued to show anything, and
nothing in the firmware does that outside `tft.init()`. And RESX has ≤5 µs spike
rejection, so casual noise cannot trigger it.

**Rank: 5 of 5 for this event.** Still worth fixing on general principles (§5.6)
— GPIO 16 is driven by `tft.init()` and is *not* floating during operation, but
it is undefined while the ESP32 boots or browns out.

### 3.6 Summary ranking

| # | Hypothesis | Explains (A) mirror | Explains (B) band | Explains (C) white | Cheap to test? |
|---|---|---|---|---|---|
| **H1** | Stray byte latched as a command (D/CX or CS) | ✔ | ✔ (RAMWR abort) | ✔ | scope, or §8.0 photo re-read |
| **H2** | SPI bit errors at 2.7× spec clock | enabler only | ✗ alone | ✔ | lower the clock and wait |
| **H3** | Brown-out reboot + corrupted re-init MADCTL | ✔ | ✗ | ✔ | ★ **free** — log reset reason |
| **H4** | Supply dip / no decoupling | enabler only | ✗ alone | ✔ | ★ **₹5** — fit the caps |
| **H5** | RESET glitch | ✗ (gives `00h`) | ✗ | ✗ (blanks) | ruled out |

**No single hypothesis explains all three symptoms without assistance.** H1 comes
closest and is the only one that reaches (B) natively. §4 examines whether (B)
is really a separate event.

---

## 4. Why the left ~40% is hatching — and what a one-byte shift really does

### 4.1 Establish the raster geometry first

This is the part that does the real work, so it is worth being exact.

`RAMWR` (datasheet §8.2.22, p.114, verbatim):

> "When this command is accepted, the column register and the page register are
> reset to the Start Column/Start Page positions. **The Start Column/Start Page
> positions are different in accordance with MADCTL setting.** Then D [17:0] is
> stored in frame memory and the column register and the page register
> incremented."

The **column register increments first**. With `MADCTL = 0x28` (MV set), the
column range is 0…319 (§2.5), which maps to the panel's **long axis** — the
**horizontal** axis as this device is mounted (landscape).

> **Therefore, in normal operation, `fillScreen` raster-scans in horizontal
> lines: 320 px per line, 240 lines.**

| | |
|---|---|
| One pixel | 16 bits ÷ 27 MHz = **592.6 ns** |
| One 320 px line | 5,120 bits = **189.6 µs** |
| Full 240-line frame | **45.5 ms** (matches HARDWARE.md line 106) |

### 4.2 ★ The geometric constraint that does most of the diagnosis

From §4.1, with MV set, **every** anomaly bounded in *time* during a fill —
a noise burst, a truncated write, an aborted RAMWR — produces a band of whole
**lines**, i.e. a **horizontal** band across the full width.

**Only MV = 0 makes the fast axis vertical**, because then the column register
spans the panel's 240-axis, which is vertical in this mounting. And MV = 0 is
also the case where TFT_eSPI's `CASET(0,319)` goes out of range and, per the
datasheet Note 1 quoted in §2.5, the out-of-range data **"will be ignored"**.

So the two symptoms make opposite demands:

| Symptom | Requires |
|---|---|
| (A) mirrored, **not transposed**, text on a 320-wide layout | **MV = 1** |
| (B) a **full-height vertical** band down one side | **MV = 0** |

> **These cannot both be true of a single MADCTL value.** One of three things
> must therefore hold:
>
> 1. **The band is actually horizontal (top or bottom), not vertical**, and the
>    "left 40%" reading is an artefact of judging orientation from a screen
>    whose content is already mirrored. **This is the most likely resolution and
>    the cheapest to check — just look at the photograph again.**
> 2. **MADCTL changed more than once** during the frame (fill under one value,
>    text under another). Possible under H1, since a stray command byte can
>    arrive at any point in the 55 ms.
> 3. **The word is transposed rather than mirrored**, i.e. MADCTL was `0xC8` or
>    `0x08` throughout, the layout ran down the panel's short axis, and "mirrored
>    horizontally and flipped vertically" is a reasonable but imprecise
>    description of a 90°-rotated, point-reflected render.

**§8.0 turns this into a ten-minute bench test that settles it outright.**

### 4.3 What a one-byte shift in a 16 bpp stream actually does

The question was asked specifically, and the answer rules a hypothesis *out*,
which is more useful than it sounds.

**RGB565 byte layout** (datasheet §8.2.22 parameter table, 16 bpp row):

```
high byte:  R4 R3 R2 R1 R0 G5 G4 G3
low  byte:  G2 G1 G0 B4 B3 B2 B1 B0
```

Insert or drop **one byte** at position *k*, and every pixel after *k* is
assembled as `(low byte of intended pixel N, high byte of intended pixel N+1)`.
The reconstructed pixel takes its red and upper-green from pixel N's **blue**
field, and its blue from pixel N+1's **red** field.

**Consequences, in order of usefulness:**

1. **A one-byte shift is completely invisible in a uniform fill.** In
   `fillScreen(TFT_WHITE)` every byte is `0xFF`; shifted or not, every
   reconstructed pixel is still `0xFFFF`. Same for `TFT_BLACK` and `0x0000`.
   **This kills "a dropped byte during `fillScreen` produced the hatching."**
   It cannot have.
2. **It does not accumulate across operations.** `TFT_eSPI::setWindow`
   (`TFT_eSPI.cpp:3360-3364`) forces `addr_row = addr_col = 0xFFFF`, so CASET,
   PASET and RAMWR are re-issued before **every** drawing call. RAMWR then
   resets the column and page registers (quote in §4.1). A shift is therefore
   confined to the single operation in which it occurred and self-heals at the
   next one — which is genuinely good news about this codebase.
3. **On real content it produces strong false colour, not grey noise.** At a
   black↔white boundary the shifted stream yields pixels like `0x00FF` (pure
   blue) and `0xFF00` (red + green, i.e. yellow). **This is a checkable
   prediction against the photograph:** on a UI that is deliberately monochrome
   (`C_BG`/`C_FG`/`C_MUTED` are white/black/grey throughout), *any* saturated
   blue, yellow or cyan in the corrupted region is a signature of a byte/bit
   shift. Grey and black-and-white hatching is not, and points elsewhere.
4. **A fixed shift gives vertical stripes; only an accumulating one gives
   diagonals.** A line is 320 px = 640 bytes — even — so a constant one-byte
   shift has identical phase on every line, producing **vertical** artefacts.
   Diagonals require the shift to *grow* line by line. There is a plausible
   source for exactly that: `pushBlock` for ESP32
   (`Processors/TFT_eSPI_ESP32.c:255-289`) sets `*_spi_mosi_dlen = 511`, i.e.
   **512-bit (64-byte, 32-pixel) bursts**, and 320 ÷ 32 = **10 bursts per line**,
   2,400 per full frame. Between bursts the CPU spins on
   `while (*_spi_cmd & SPI_USR);` — **SCK idles while CS is still asserted low**.
   Each of those 2,400 windows is an opportunity for a noise pulse on SCK to be
   counted as a real clock edge and insert a bit. One inserted bit per burst
   would advance the phase by 10 bits per line = 0.625 px per line — a hatch
   sloping about 1 px across per 1.6 px down. That is a diagonal.

### 4.4 Where that leaves symptom (B)

Run the elimination:

- **Not a desynchronised `fillScreen`** — §4.3 item 1: mathematically invisible.
- **Not desynchronised glyph/text** — the hatched region is ~40% of 76,800 px
  ≈ **30,700 px**. The entire glyph plus text content of `drawArrived()` is only
  ~16,000 px, and it is drawn on the *right* half (`drawManeuver` at
  `GLYPH_FAR_X + 8`, text at x = 108, `display.cpp:635-648`). There is not enough
  drawn content in that frame to fill the hatched area.
- **Therefore the hatched region is area the fill did not cover**, showing what
  was already in GRAM.

What could already be in GRAM?

- **The previous screen** — a NAV screen with a 75 px numeral, an arrow glyph and
  a footer. Read out under a different address mapping than it was written with,
  that becomes regular oblique combing. Plausible as "diagonal hatching".
- **Random data**, if the panel had momentarily lost *power*. Datasheet
  §8.2.22, RAMWR default table, p.114, verbatim:

  > Power On Sequence — **"Contents of memory is set randomly"**
  > SW Reset — "Contents of memory is not cleared"
  > HW Reset — "Contents of memory is not cleared"

  **Random RGB565 aliased against the panel's RGB sub-pixel stripe photographs
  precisely as fine diagonal hatching.** This is the single best match for the
  described appearance — and note it requires a genuine **power** interruption to
  the panel, since neither a hardware nor a software reset clears GRAM.

> **★ Finding.** If the hatching is fine-grained *random* noise rather than a
> recognisable smear of the previous nav screen, then **the panel lost power
> momentarily** — which is a supply fault (H3/H4), not an SPI fault, and moves
> decoupling and the power path to the top of the fix list. If instead the
> hatching resolves into distorted remnants of the previous screen, the panel
> kept power and the fill was truncated — which is H1.
>
> **These two look different at arm's length and identical in a phone photo
> taken at night. Zoom into the photograph.** This is the highest-information,
> zero-cost observation available.

### 4.5 Answering the question as posed

> *Does that suggest a partial-window write (CASET/PASET corruption) rather than
> MADCTL alone?*

**Yes — MADCTL alone is definitively insufficient.** With MV set, any MADCTL
value still addresses the full 320 × 240 and `fillScreen` still covers the whole
panel; there would be no unpainted band at all. A second effect is required, and
the two candidate mechanisms are:

- **RAMWR abort** — datasheet: "Sending any other command can stop frame Write."
  A single stray command byte (H1) both rewrites a register and truncates the
  fill. **One event, both symptoms.**
- **CASET clipping** — if MV was cleared, `CASET(0,319)` exceeds `00EFh` and
  "data of out of range will be ignored", clipping the window to 240 columns.
  The library then pushes 76,800 px into a 240 × 240 = 57,600 px window; the
  surplus 19,200 px wrap to the window start, and **pages 240…319 — exactly
  25% of the panel's long axis — are never written**. A 25% strip eyeballed
  from a photograph is not far from the reported "~40%".

> *Could a single dropped or inserted byte during a `fillScreen` desynchronise
> the pixel stream and produce exactly this?*

**No.** §4.3 item 1 — a uniform stream is shift-invariant. A byte slip during
`fillScreen` is, uniquely, the one place in this firmware where it has **zero**
visible effect. It would matter during the glyph and text pushes, where it would
produce saturated false colour (§4.3 item 3) — worth looking for in the photo,
but it cannot account for a 30,000-pixel block.

---

## 5. Mitigations that work without MISO, ranked by effectiveness × cheapness

### 5.0 The framing that changes the priorities

There are two separable problems:

- **P1 — the corruption happens** (rare, physical, hard to fix, hard to verify).
- **P2 — the corruption is permanent once it happens** (certain, in software,
  trivial to fix, verifiable in five minutes).

**P2 is the one that turned a sub-second glitch into a photograph.** Fixing P2
does not require knowing the cause at all, cannot make anything worse, and caps
the damage from *every* hypothesis in §3 simultaneously. It should be done first
even though it is not a "real" fix.

### 5.1 ★ #1 — Periodic MADCTL re-assert **paired with a forced repaint**

**The question as asked:** *a `setRotation()` call sends only a command + one
byte; it writes no pixels, so it should be visually free. Would this actually
recover the observed corruption?*

**Cost — confirmed free.** `setRotation(1)` on this driver emits exactly
`writecommand(0x36)` + `writedata(0x28)` (`ILI9341_Rotation.h`, case 1): **two
bytes, 16 bits, 593 ns at 27 MHz**, plus a few hundred ns of TFT_eSPI
transaction overhead. Against a 45.5 ms frame that is a **0.0013%** cost. The
datasheet is explicit that it is side-effect-free: *"This command makes no
change on the other driver status."* It is as close to literally free as a
mitigation gets.

**But on its own it would NOT have recovered the photographed screen.** §2.3:
MY/MX/MV are write-side only, so re-asserting MADCTL corrects the *next* write
and leaves the existing frame exactly as it is. And on ARRIVED, **there is no
next write** — `displayRender` returns at `display.cpp:1168` and nothing
repaints for the full 30 s `ARRIVAL_DWELL_MS`. The rider would have stared at
the identical corrupt frame with a perfectly correct MADCTL behind it.

> **Verdict: necessary but not sufficient. `setRotation()` + `displayInvalidate()`
> is the actual mitigation.** The invalidate is what makes it work; the
> `setRotation` is what stops the repaint from being drawn wrong too.

**How often is sensible.** Two complementary cadences:

| Where | Cadence | Cost | Rationale |
|---|---|---|---|
| **Before every full-screen chrome repaint** | event-driven | 593 ns | Guarantees every full repaint starts from known register state. Unconditionally free. Do this. |
| **Periodic re-assert + invalidate on static screens** | every **5 s** | 45.5 ms fill + ~10 ms content ≈ **1.1% duty** | Converts *permanent* corruption into *≤5 s* corruption on ARRIVED / IDLE / banner screens. |

**Do not** make the periodic path unconditional on nav screens — they already
self-heal (§6.2) and a forced full repaint there is a visible flash.

**The one real cost to weigh:** a periodic full repaint of ARRIVED does a
`fillScreen` that briefly erases the glyph and text, so it *is* a ~10 ms visible
flicker every 5 s. Two ways out, both cheap:

- Repaint **without** the fill — redraw the glyph box and re-`drawString` over
  itself. `setTextColor(C_FG, C_BG)` is already set (`display.cpp:637`), so text
  paints its own opaque background and overdrawing identical content is
  invisible. ~16,000 px ≈ **10 ms**, no flash.
- Or accept the flash but stretch the period to 10–15 s. On a screen that is up
  for 30 s that still guarantees at least two chances to self-correct.

**Recommendation: re-assert MADCTL before every chrome repaint (free,
unconditional), and add a fill-free 5 s refresh for `UI_ARRIVED` and `UI_IDLE`.**

**Worth extending slightly.** Re-asserting the full non-destructive register set
costs barely more than MADCTL alone and covers more failure modes:

| Command | Bytes | Guards against |
|---|---|---|
| `0x36` MADCTL = `0x28` | 2 | the observed mirroring |
| `0x3A` COLMOD = `0x55` | 2 | 16 bpp lost → every pixel misparsed |
| `0x20` INVOFF (or `0x21`) | 1 | spurious inversion (§1.2 option 2) |
| `0x11` SLPOUT / `0x29` DISPON | 2 | the *previously observed* blank-white fault (`display.cpp:800-805`) |

**Under 10 bytes, ~3 µs, no pixels.** Note SLPOUT carries a datasheet timing
obligation (§15.4 note 7: 120 ms before a further SLPOUT), so if included it must
be rate-limited — which the 5 s cadence already does.

### 5.2 #2 — Lower the SPI frequency

**What it costs, exactly.** 320 × 240 × 16 bit = 1,228,800 bits per frame:

| SPI clock | Full frame | vs 27 MHz | Distance sprite (208×80, 16,640 px) | Bit cell | Edge (15 ns spec) as % of cell |
|---|---|---|---|---|---|
| 40 MHz | 30.7 ms | −33% | 6.7 ms | 25.0 ns | 60% |
| **27 MHz (current)** | **45.5 ms** | — | **9.9 ms** | **37.0 ns** | **41%** |
| 20 MHz | 61.4 ms | **+35%** | 13.3 ms | 50.0 ns | 30% |
| 13.5 MHz | 91.0 ms | +100% | 19.7 ms | 74.1 ns | 20% |
| 10 MHz (**datasheet max**) | 122.9 ms | +170% | 26.6 ms | 100.0 ns | 15% |

**What that actually costs this project today.** Full repaints happen on screen
*changes*, which are rare. The recurring cost is the distance sprite, pushed at
most once per distance change — call it 1 Hz. Going 27 → 20 MHz moves that from
**9.9 ms to 13.3 ms**, i.e. from 1.0% to 1.3% of a second. **Invisible.** Screen
transitions go from 45 ms to 61 ms, which is at the edge of perceptible and only
happens on a screen change.

The real cost is **future**: `SPEC_MOVING_MAP.md` implies animated content, and
HARDWARE.md line 100 already argues for going *up* to 40 MHz once soldered.

> **Recommendation: drop to 20 MHz now, as insurance, while the build is on a
> breadboard.** It is a one-line change in the live `User_Setup.h` (note the
> sketchbook trap: `C:\dev\Arduino\libraries\TFT_eSPI\User_Setup.h`, HARDWARE.md
> line 150). Revisit after soldering, and re-test rather than assume — exactly as
> HARDWARE.md line 93 already says.

**Honest caveat: this is unfalsifiable in practice.** At an inferred BER of
~10⁻⁹ (§3.2), you would need months of riding to tell 20 MHz from 27 MHz. Lower
it because the margin argument is sound, not because you will be able to prove it
worked.

### 5.3 ★ #3 — Decoupling capacitors (the best rupees-per-risk on the list)

Nothing in the repo mentions a decoupling cap. HARDWARE.md line 47 records
**3.18 V at the `3V` pin with the backlight lit** — a 4% droop before any
dynamic load.

| Part | Where | Cost | Why |
|---|---|---|---|
| **100 nF ceramic (X7R)** | directly across the display module's VCC↔GND pins, leads as short as physically possible | ~₹2 | Supplies the high-frequency transient current the controller's I/O draws on every SCK edge. The MB102 rail cannot; it is metres of inductance away electrically. |
| **10 µF electrolytic or tantalum** | on the breadboard rail next to the display header | ~₹3 | Bulk reservoir for the ~60–100 mA backlight and BLE TX bursts. |
| **100 nF + 10 µF** | at the ESP32's 3V3 pin | ~₹5 | Same argument, driver end. |

**The dynamic case.** ESP32 BLE advertising and connection events draw burst
currents in the ~100–130 mA region. An MB102 rail presents roughly 10–20 nH per
inch of loop inductance with no bulk capacitance near the load, and the MB102's
own power module is not a precision part. Every millivolt of rail sag narrows
V<sub>IH</sub>/V<sub>IL</sub> at **both ends of the bus at once** — on a link
already running at 2.7× the specified clock with no guard band.

> **~₹10 and fifteen minutes. Do this before anything else physical.** It
> attacks H3 and H4 directly and improves the margin that H1 and H2 depend on.

### 5.4 #4 — Re-wire MISO — but the watchdog as written would not have caught this

**The wiring.** One jumper: LOLIN32 **GPIO 19** → display **SDO**. It is already
declared (`User_Setup.h:19`) and already in the HARDWARE.md pin table (line 33);
it was deliberately removed (`display.cpp:829`). The probe at
`display.cpp:1076-1079` auto-detects and arms, so **this really is a pure wiring
fix with zero firmware change required to re-enable the watchdog.**

> **★ But the existing watchdog is blind to this specific fault.** It reads
> **RDDPM (0x0A)** and checks `DISON | SLPOUT` (`display.cpp:817-819, 1258-1260`).
> **MADCTL corruption does not change RDDPM.** A panel that is on, awake, and
> rendering everything 180° passes the check perfectly. Re-wiring MISO on its
> own would have changed nothing about the photographed screen.

**The fix that makes MISO worth the wire:** also read **RDMADCTL (`0x0B`)** —
already defined as `ILI9341_RDMADCTL` in `TFT_Drivers/ILI9341_Defines.h:87` —
and compare it against the expected `0x28`. On mismatch: re-assert MADCTL and
`displayInvalidate()`. That is a genuine detector for the observed fault, and it
also gives you a **counter** — the thing this investigation is most missing.

**Caveats, and they matter:**

- ILI9341 register reads over SPI need the dummy-clock handling in
  `readcommand8`, and are notoriously unreliable on cheap modules — which is
  exactly why the auto-detect exists. The probe may still disarm.
- Reads are the reason `SPI_READ_FREQUENCY` is 20 MHz (`User_Setup.h:45`) and
  why HARDWARE.md line 97 calls 27 MHz "TFT_eSPI's documented ceiling for
  *reading* pixels". Reads are the *least* tolerant traffic on the bus.
- Every 2 s poll is one more bus transaction with CS toggling — a small increase
  in exposure, though negligible against 45 ms frames.
- Do not re-arm the old three-strike `tft.init()` recovery without also fixing
  the false-positive story documented at `display.cpp:832-835`. A MADCTL
  mismatch should trigger a **MADCTL re-write + invalidate**, not a full
  `tft.init()`; full re-init is a visible flash and is reserved for the
  blank-panel fault.

### 5.5 #5 — Series resistors on SCK and MOSI

**22–33 Ω in series, at the ESP32 end, as close to the pin as possible.**
Cost ~₹5.

**Why it works, numerically.** The ESP32 drives ~1–2 ns edges. Signal content
therefore extends to roughly 0.35/1.5 ns ≈ **230 MHz**. A quarter wavelength at
230 MHz in wire is on the order of **250 mm** — and the dupont jumpers on this
build are 150–200 mm. **The wires are electrically long for the edge rate even
though they are trivially short for the 27 MHz fundamental.** That is the
mechanism behind ringing, overshoot and crosstalk into D/CX — i.e. behind H1.

33 Ω into the panel input's ~50–100 pF gives an RC of **1.7–3.3 ns**, which
slows the edge enough to kill overshoot while consuming under 10% of the 37 ns
bit cell. This is the standard source-termination fix and it is nearly free.

> **★ Correct a possible misreading of HARDWARE.md while doing this.**
> HARDWARE.md line 40 says *"No series resistors"* — but read line 41: that note
> is rejecting the **vendor's 10 kΩ level-shifting advice for a 5 V Arduino**,
> which is a completely different thing. **10 kΩ for level shifting: still wrong.
> 33 Ω for source termination: right, and orthogonal.** As written, that line
> could steer a future session away from the correct fix. Worth amending.

### 5.6 #6 — Pull-ups on CS and RESET

| Signal | Pin | Fix | Cost | Why |
|---|---|---|---|---|
| **CS** | GPIO 15 | 10 kΩ to 3V3 | ~₹1 | GPIO 15 is an ESP32 strapping pin with an internal pull-**up** at reset, so it is biased correctly at boot — but during a **brown-out** the pin tri-states. **A floating-low CS while the ESP32 reboots and the bus carries garbage is one of the cleanest ways a panel ends up with a wrong MADCTL.** Directly guards H3. |
| **RESET** | GPIO 16 | 10 kΩ to 3V3 | ~₹1 | Driven by `tft.init()`, so not floating in normal operation — but undefined while the ESP32 boots or browns out. §3.5 rules a reset *out* for this event (a reset blanks the display), so this is hygiene, not a fix. Confirm it is actually wired first — HARDWARE.md line 29 flags GPIO 16 as the classic trap. |
| **D/CX** | GPIO 2 | leave alone; **route away from SCK** | free | GPIO 2 is a strapping pin that must be low at boot, so do not pull it up. The useful action is physical: keep the D/CX jumper non-adjacent to SCK on the breadboard, and ideally put a ground wire between them. This is the direct countermeasure to H1. |

### 5.7 #7 — Shorter leads / leave the breadboard

The real fix, already planned as Stage 11 (HARDWARE.md line 70). Every item
above is a way to survive until then. Halving the lead length roughly halves the
inductance and the crosstalk coupling, and it removes the MB102's spring
contacts — which are a genuine intermittent-connection risk on a vibrating
motorcycle in a way that has nothing to do with SPI at all.

### 5.8 Ranked summary

| Rank | Mitigation | Effectiveness | Cost | Prevents or contains? |
|---|---|---|---|---|
| **1** | Re-assert MADCTL **+ `displayInvalidate()`** on a 5 s cadence for static screens | ★★★★★ caps every hypothesis | ~10 lines, 1.1% duty | **contains** |
| **2** | 100 nF + 10 µF decoupling at the panel and the ESP32 | ★★★★ attacks H3/H4, helps H1/H2 | ~₹10, 15 min | **prevents** |
| **3** | Log `esp_reset_reason()` + boot counter + uptime | ★★★★ as *diagnosis* | free | neither — it tells you which fix worked |
| **4** | MISO wire **+ watch RDMADCTL 0x0B, not just RDDPM 0x0A** | ★★★★ true detection | 1 wire, ~15 lines | **contains + measures** |
| **5** | SPI 27 → 20 MHz | ★★★ margin, unprovable | 1 line, +35% frame time | **prevents** |
| **6** | 33 Ω series on SCK/MOSI; 10 kΩ pull-up on CS; route D/CX away from SCK | ★★★ attacks H1 | ~₹10, a rewire session | **prevents** |
| **7** | Solder to perfboard, short leads | ★★★★★ | Stage 11 | **prevents** |

---

## 6. Is the ARRIVED screen special? Yes — but not electrically

### 6.1 ★ It is the only screen that paints once and then never repaints

`display.cpp:1162-1169`:

```cpp
  if (fullScreenAlert) {
    if (changed && idleKey) drawBand(s, band, scr);
    lastIdleKey = idleKey;
    return;
  }
```

`fullScreenAlert` is true for `UI_IDLE` and `UI_ARRIVED` (`display.cpp:1126`).
`drawChrome` runs only when `changed` (`display.cpp:1137`), and `changed`
requires `!chromeValid || scr != lastScreen` — plus, for ARRIVED, only an alert
identity change (`display.cpp:1135`). Nothing else can set it.

`UI_IDLE` at least has an escape hatch: `display.cpp:1106-1110` adds a clock and
battery change key, precisely because — as the comment says — *"nothing else
would ever repaint it."* **`UI_ARRIVED` has no such key.** There is no clock, no
distance, no battery, no geometry. It draws once and sits there for the full
`ARRIVAL_DWELL_MS = 30000` (`nav_types.h:72`).

> **This, not any electrical property, is why the fault was seen here.** On a
> NAV screen, `pushDistance` repaints a 208 × 80 sprite on every distance change
> (`display.cpp:1190-1197`), and `drawNavGlyph` repaints on geometry updates
> (`display.cpp:1157-1160`). Corruption there is **overwritten within about a
> second** and reads as a flicker, not a fault.

**The uncomfortable corollary: this may not be the first occurrence.** It may
simply be the first one that lasted long enough to be noticed, let alone
photographed. Every prior occurrence on a nav screen would have been a
sub-second flicker on a bumpy road at night — indistinguishable from nothing.
**The event rate is therefore not known to be "once", and any estimate of MTBF
from this single sighting is worthless.**

### 6.2 Is `drawArrived` electrically harder than other screens?

Somewhat, but not decisively:

| Screen | `fillScreen`? | Approx. pixels in one paint | Approx. CS-low SPI time |
|---|---|---|---|
| `drawArrived` | yes | ~93,000 | **~55 ms** |
| `drawIdle` | yes | ~80,000 | ~48 ms |
| `drawBanner` (DISCONNECTED / STALE / REROUTING) | yes | ~80,000 | ~48 ms |
| NAV chrome repaint | yes | ~90,000 | ~54 ms |
| NAV distance sprite (the common case) | no | 16,640 | ~9.9 ms |

`drawArrived` is at the top, but only marginally — it is not an outlier. What it
does have is the **largest single uninterrupted burst** (`fillScreen` alone:
153,600 bytes, 2,400 consecutive 512-bit FIFO bursts, CS held low for 45.5 ms
with 2,400 SCK-idle windows in between, §4.3 item 4). But `drawIdle` and every
banner do essentially the same thing.

### 6.3 Circumstantial factors that *are* specific to arrival

These are speculative but cheap to check and worth listing:

1. **Longest uptime.** ARRIVED is by definition reached at the end of the ride —
   maximum accumulated thermal soak on the LDO and the ESP32, maximum time for
   a vibrating dupont contact to work loose. HARDWARE.md's whole enclosure
   section is about a thermal environment that is already known to be hostile.
2. **★ The power source at the moment of arrival.** Arriving means *stopping*.
   If the device is on the bike's 12 V accessory rail, engine-off or idle drops
   the supply. If it is on a USB power bank, many power banks **cut output or
   renegotiate** when load drops — and load *does* drop at arrival, because
   navigation traffic stops. **A supply transient correlated with the act of
   arriving is a real and under-considered possibility**, and it would make the
   ARRIVED screen genuinely special rather than coincidentally so.
   **What was it powered from on this ride? This is worth answering.**
3. **BLE traffic pattern changes at arrival.** Maps drops the ongoing
   notification within a few seconds of arrival (`display.cpp:630-631`), so
   packets stop, `nudgeIfQuiet()` starts polling every 2 s
   (`navigator.ino:38-52`), and the connection may go idle or drop — all of which
   change the radio's current draw profile at exactly the moment `drawArrived`
   is pushing its 45 ms fill.

> **Answer to the question as posed:** the ARRIVED screen is **not obviously more
> likely to be corrupted** than IDLE or any banner — its paint is only ~15%
> larger than theirs. It **is** overwhelmingly more likely to be *seen*
> corrupted, because it is the only screen with no repaint path at all. Item 2
> above is the one candidate for genuine electrical specialness, and it is
> answerable for free.

---

## 7. Verified / inferred / unknown

### 7.1 Verified — checked against the datasheet, the library source, or this repo

| Fact | Source |
|---|---|
| Runtime MADCTL on this build is `0x28` (MV \| BGR) | `ILI9341_Rotation.h` case 1; `ILI9341_Defines.h:56-72`; `display.cpp:41` |
| MADCTL is written **once per boot** and never again at runtime | `display.cpp:1069-1070`; recovery path at 1272-1273 is unreachable via 1252 |
| MY/MX/MV control **MCU-to-memory write/read direction** — not the stored image | datasheet §8.2.29 p.127, verbatim |
| MADCTL "makes no change on the other driver status" — safe to re-assert | datasheet §8.2.29 p.127, verbatim |
| MADCTL reset default is `00h` | datasheet §8.2.29 p.127 |
| `0xE8` = MY\|MX\|MV\|BGR = TFT_eSPI **rotation 3** = 180° of rotation 1 | `ILI9341_Rotation.h` case 3 |
| CASET clips at `00EFh` when MV=0 and `013Fh` when MV=1; **"data of out of range will be ignored"** | datasheet §8.2.20 p.110, Note 1, verbatim |
| RAMWR resets the column/page registers, and **"Sending any other command can stop frame Write"** | datasheet §8.2.22 p.114, verbatim |
| GRAM is **random on power-on** but **not cleared** by SW or HW reset | datasheet §8.2.22 p.114 default table, verbatim |
| A hardware reset **blanks the display** and sets MADCTL to `00h` | datasheet §15.4 p.230 Note 3 |
| RESX rejects pulses **< 5 µs**; resets on **> 10 µs** | datasheet §15.4 p.230 Note 2 |
| **Datasheet max SPI write clock is 10 MHz** (`twc` min 100 ns); this build runs **27 MHz = 2.7× spec** | datasheet §18.3.4 p.243; `User_Setup.h:44` |
| The panel watchdog is **disabled at runtime** on this build | `display.cpp:847`, `1252`; the boot probe at 1076-1079 |
| The watchdog checks **RDDPM `0x0A`** only — which **cannot detect MADCTL corruption** | `display.cpp:817-819`, `1258-1260` |
| **`UI_ARRIVED` has no repaint path**; it draws once and returns for 30 s | `display.cpp:1126`, `1137`, `1162-1169`; `nav_types.h:72` |
| TFT_eSPI re-sends CASET/PASET/RAMWR before **every** drawing op, so shifts do not accumulate across ops | `TFT_eSPI.cpp:3360-3364` |
| `pushBlock` on ESP32 uses **512-bit (32-pixel) FIFO bursts**, CS held low, SCK idle between them | `Processors/TFT_eSPI_ESP32.c:255-289`; `TFT_eSPI_ESP32.h:204-239` |
| Full frame at 27 MHz = **45.5 ms**; the panel rail measured **3.18 V** | arithmetic; HARDWARE.md lines 47, 106 |
| Night mode defaults **off** and is only set by an optional BLE CONFIG tail byte | `nav_types.h:115`; `ble.cpp:259-272`; `navigator.ino:94` |
| The panel has **previously** lost its configuration mid-run, recovering only on a power cycle | `display.cpp:797-809`; HARDWARE.md |

### 7.2 Inferred — reasoned, consistent with the evidence, not demonstrated

- **The observed mirroring is `MADCTL = 0xE8`.** Strong inference from symptom
  (A) plus the rotation table. **Not confirmed** — `0xC8` and `0x08` are not
  excluded by a verbal description of the photo (§4.2).
- **The hatched band is GRAM the fill did not cover**, not corrupted fill data.
  Follows from the shift-invariance of a uniform stream (§4.3) and from the
  hatched area being roughly twice the total drawn content of the frame.
- **At least two distinct corruptions occurred**, or the band's orientation has
  been misread. Follows from the MV=1 / MV=0 contradiction in §4.2.
- **The bit error rate is around 10⁻⁹–10⁻¹⁰**, from one event against ~1.5 Mbit
  per full paint. Order-of-magnitude only; the true event count is unknown
  (§6.1), so this could be off by orders of magnitude in the *pessimistic*
  direction.
- **A stray command byte (H1) is the most economical single cause**, because the
  datasheet's "any other command can stop frame Write" makes one glitch produce
  both a register change and a truncated fill.
- **Marginal supply is the enabling condition** for whichever SPI mechanism
  applies: 3.18 V measured, no decoupling anywhere in the design, BLE bursts.

### 7.3 Unknown — and this is the honest majority of it

- **What the photograph actually shows.** Band orientation (H/V/oblique), which
  bezel edge it touches, its stripe period, whether the region contains
  saturated colour, whether the letters are 180°-rotated or mirror-imaged, and
  whether the destination-name line rendered at all. **Every one of these is
  recoverable from the existing image at zero cost and each one discriminates.**
- **Whether the ESP32 rebooted.** Nothing logs it. This is the single largest
  hole and the cheapest to close.
- **Whether the panel lost power.** Distinguishable from the GRAM appearance
  (§4.4) and from a reboot log.
- **What the device was powered from** on that ride (§6.3 item 2).
- **Whether `night=1` had been configured** (§1.2).
- **The true event rate.** §6.1 — prior occurrences on nav screens would have
  been invisible.
- **Ambient conditions**: temperature, vibration level, whether the unit was
  jostled or the breadboard bumped at the moment of arrival.
- **Whether this reproduces at all.** It has not been reproduced.

> **What one observation buys you: almost nothing.** It establishes that the
> failure mode exists and is not the previously-documented blank-white fault. It
> does not establish frequency, trigger, or mechanism. **Do not spend money or a
> rewire session on the strength of this document alone — spend twenty minutes
> on §8.0 first, because two of the four items there are free and one of them
> can be done without leaving the desk.**

---

## 8. Ordered action list

### 8.0 ★ First: four observations, before changing anything

These cost nothing and they collapse most of the hypothesis space.

1. **Re-examine the photograph. Zoom in.** Answer:
   - Does the band touch the **left/right** bezel edge (vertical, full height) or
     the **top/bottom** (horizontal, full width)? → §4.2. Vertical ⇒ MV was 0
     during the fill; horizontal ⇒ a truncated write with MV=1.
   - Are the stripes **fine random noise** (⇒ the panel lost **power**, GRAM
     re-randomised, §4.4) or **recognisable smeared remnants of the nav screen**
     (⇒ the panel kept power, the fill was truncated)?
   - Is there any **saturated blue / yellow / cyan** anywhere? The UI is
     monochrome by design, so false colour ⇒ a byte/bit shift in a content push
     (§4.3 item 3).
   - Is the word **180°-rotated** (running along the long axis) or
     **90°-rotated** (running along the short axis)? → decides `0xE8` vs `0xC8`.
2. **★ Write the MADCTL forensics sketch** — the decisive test, and it is the
   best twenty minutes available. A standalone sketch that renders the ARRIVED
   layout, then writes each candidate MADCTL raw (`0x28, 0x68, 0xA8, 0xE8,
   0x08, 0xC8, 0x00`) and repaints, photographing each. **Compare against the
   ride photo and read the answer off directly.** This converts §2.4 from
   inference to fact. Costs nothing, risks nothing, and every later decision
   depends on it. *(Remember HARDWARE.md line 133: upload through the Arduino
   IDE, and do not open the COM port from a script.)*
3. **Recall what the device was powered from** on that ride, and whether the
   supply could have changed at the moment of arrival (§6.3 item 2).
4. **Check whether `night=1` was ever sent** by the phone/navsim on that ride
   (§1.2). If it was, INVON joins the suspect list and the diagnosis shifts.

### 8.1 Firmware — cheap, now, in this order

| # | Change | Where | Why |
|---|---|---|---|
| 1 | **Log `esp_reset_reason()` and a boot counter** (RTC-retained), plus uptime at every screen transition | `navigator.ino` `setup()` | Closes the largest evidence gap in §7.3. Free. **Do this first** — it decides between H3 and everything else on the next occurrence. |
| 2 | **Re-assert MADCTL immediately before every full chrome repaint** | `drawChrome()` entry, `display.cpp:680` | 593 ns, unconditional, guarantees each repaint starts from known state. |
| 3 | **Add a static-screen refresh**: if `scr` is `UI_ARRIVED` or `UI_IDLE` and nothing has repainted for 5 s, re-assert MADCTL and force a repaint | `displayRender`, near `display.cpp:1165` | ★ The one change that would have prevented the photographed outcome regardless of cause. Prefer the fill-free variant (§5.1) to avoid a 5 s flicker. |
| 4 | **Extend the re-assert to COLMOD `0x3A`=`0x55` and INVOFF `0x20`** | alongside #2 | Under 10 bytes total; covers two more silent-corruption modes. |
| 5 | **SPI 27 → 20 MHz** | live `User_Setup.h` (**`C:\dev\Arduino\libraries\TFT_eSPI\User_Setup.h`** — HARDWARE.md line 150) and the repo reference copy | +35% frame time, currently imperceptible. Revert after soldering, with a retest. |
| 6 | **Instrument, do not just fix**: count and log every time #3 fires and (once MISO exists) every RDMADCTL mismatch | `display.cpp` | Turns "seen once" into a measured rate. Without this, no later fix can be shown to have worked. |

**Verification for #3 without waiting for a real fault:** add a debug serial
command that deliberately writes `MADCTL = 0xE8` at runtime, and confirm the
screen self-corrects within 5 s. `demo.cpp` already has a serial command
surface to hang this off.

### 8.2 Wiring — before the case is built

In order. Items 1–2 are worth doing on the breadboard today; 3–5 belong to the
Stage 11 soldering session.

| # | Change | Cost | Rationale |
|---|---|---|---|
| 1 | **100 nF X7R across the display module's VCC/GND, shortest possible leads; 10 µF bulk on the rail beside it; 100 nF + 10 µF at the ESP32 3V3** | ~₹10 | §5.3. Highest value per rupee on the list. Do it now, on the breadboard. |
| 2 | **Re-route the D/CX jumper away from SCK**; if possible run a ground jumper between them | free | §5.6. Direct countermeasure to H1, the top-ranked hypothesis. |
| 3 | **MISO: GPIO 19 → SDO** — and change the watchdog to check **RDMADCTL `0x0B` against `0x28`**, not just RDDPM `0x0A` | 1 wire | §5.4. The wire alone re-arms a watchdog that **cannot see this fault**; the register change is what makes it worth doing. |
| 4 | **33 Ω series on SCK and MOSI**, at the ESP32 end | ~₹5 | §5.5. Source termination for ~230 MHz edge content on 150–200 mm wires. |
| 5 | **10 kΩ pull-up on CS (GPIO 15) to 3V3**; confirm RESET (GPIO 16) is genuinely wired and add 10 kΩ to 3V3 | ~₹2 | §5.6. Guards the brown-out window when the ESP32 tri-states its pins. |
| 6 | **Solder to perfboard, shortest practical leads** | Stage 11 | §5.7. The actual fix. Everything above is scaffolding until then. |

### 8.3 Documentation follow-ups

- **HARDWARE.md line 40, "No series resistors."** Amend to make clear it rejects
  the vendor's **10 kΩ level-shifting** advice for 5 V Arduinos, and does **not**
  rule out **33 Ω source-termination** resistors, which are appropriate here.
  As written it could steer a future session away from the right fix (§5.5).
- **HARDWARE.md line 93**, on raising the clock to 40 MHz after soldering: add
  the datasheet figure — **`twc` min 100 ns = 10 MHz specified maximum**. Both 27
  and 40 MHz are overclocks; 40 MHz would be 4× spec. That does not mean don't
  do it, but it should be a decision made with the number in view.
- **`display.cpp:811`** says *"MISO is wired to GPIO 19"* while
  `display.cpp:829` says it *"is not wired — it was removed deliberately."*
  The first comment is stale and contradicts the second. Fix it — a future
  session reading only the first will draw the wrong conclusion.
- **Record this bug's outcome here** when the next occurrence (or non-occurrence
  over N rides) is observed. This file's value is as a running record, not a
  one-shot analysis.

---

## 9. References

**ILI9341 datasheet** (ILI Technology, v1.11) — sections cited:

- §8.2.20 **CASET (2Ah)**, p.110 — out-of-range column clipping, MV-dependent limits
- §8.2.22 **RAMWR (2Ch)**, p.114 — address counter reset, "any other command can stop frame Write", GRAM default contents
- §8.2.29 **MADCTL (36h)**, p.127 — MY/MX/MV/ML/BGR/MH definitions, reset default
- §15.4 **Reset Timing**, p.230 — tRW 10 µs, spike rejection, display blanks during reset
- §18.3.4 **Display Serial Interface Timing (4-line SPI)**, p.243 — twc min 100 ns

Mirrors: <https://cdn-shop.adafruit.com/datasheets/ILI9341.pdf> ·
<https://newhavendisplay.com/content/app_notes/ILI9341.pdf>

**TFT_eSPI** v2.5.43 (Bodmer) — <https://github.com/Bodmer/TFT_eSPI>

- `TFT_Drivers/ILI9341_Rotation.h` — the MADCTL value per rotation
- `TFT_Drivers/ILI9341_Defines.h` — `TFT_MAD_*` masks, `ILI9341_RDMADCTL 0x0B`
- `TFT_eSPI.cpp:3360` `setWindow` — per-operation CASET/PASET/RAMWR re-issue
- `Processors/TFT_eSPI_ESP32.c:255` `pushBlock` — 512-bit FIFO bursts
- `Processors/TFT_eSPI_ESP32.h:204` — `CS_L`/`CS_H` macros
- Issue 1172, the `ILI9341_2_DRIVER` alternative init this panel needs —
  <https://github.com/Bodmer/TFT_eSPI/issues/1172>
- Library guidance on clock rates —
  <https://doc-tft-espi.readthedocs.io/hardware/ili9341/>

**This repo:**

- `docs/HARDWARE.md` — pin map, 3.18 V measurement, 27 MHz rationale, frame timings, sketchbook trap
- `firmware/navigator/display.cpp` — `drawArrived` 632, `drawChrome` 680, panel watchdog 795-847, `displayBegin` 1068, `displayRender` 1088, `displaySetNight` 1200, `displayTick` 1250
- `firmware/navigator/User_Setup.h` — pins, `SPI_FREQUENCY 27000000`
- `firmware/navigator/nav_types.h:72` — `ARRIVAL_DWELL_MS`
- `firmware/navigator/navigator.ino:86` — the main loop
