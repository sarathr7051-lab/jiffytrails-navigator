# Component dimensions

Research compiled 29 Aug 2026 so the enclosure can be designed without callipers.

**Status key** — every number below carries one:

- **VERIFIED** — read from a datasheet, a dimensioned drawing, or a manufacturer spec page. URL given.
- **INFERRED** — computed or derived from something verified (e.g. active area from the diagonal), or read off a photograph against a known reference. Stated as such.
- **UNKNOWN** — not found. A calliper-free method to obtain it is given instead.

> Silence is not agreement. If a dimension is not listed here, it was not found.
> Do not assume an omitted number is fine — a case is the one part of this
> project that cannot be fixed in software.

---

## ★★ STOP — THE BOARD IN HAND IS PROBABLY NOT THE MSP2806

Added 29 Aug 2026. **Nothing in section 1 may be used to commit a print until
the photographs in section 5 have been taken.**

Almost every display dimension in this document was read off the LCDWIKI
MSP2806 drawing. That was the right source to find, and the numbers in it are
sound. But the vendor's own photograph of the SmartElex board actually
purchased (PCB marking `4484516A_Y7475_241108`) shows **a different PCB**:

| | LCDWIKI MSP2806 | The board in the photograph |
|---|---|---|
| Panel FPC | bonded at the header end | **ZIF connector mid-board, tail folded through a slot cut in the PCB** |
| Card socket | mid-board, straddling 32–61 mm | **far end, near a corner** |
| SD header | centred on the far edge | **at a corner** |

The consequence that matters is §1.4. The active area's **4.90 mm offset toward
the far end is not a styling choice — on the MSP2806 it is forced**, because the
FPC is bonded along the header edge and the glass physically cannot sit there.
Put the FPC on a ZIF connector fed through a slot instead and that constraint
disappears: the panel is free to sit anywhere along the 86 mm axis.

The offset may still be 4.90 mm. There is no longer any evidence that it is.

**So §5.1's lit-white-screen photograph is no longer a confirmation step. It is
the only source.** The lid aperture is the least forgiving feature on the case —
it is cut to the active area with no tolerance, and getting it wrong crops live
picture on one side while showing bare PCB on the other. That is precisely the
failure the 4.90 mm figure was found to prevent, and it returns in full if the
number is carried over from the wrong board.

The listing also mixes at least two revisions across its three photos — one with
bare header holes, one with a 14-pin header fitted. It cannot be trusted for
population either. **Trust the board on the desk, not the drawing.**

---

## ★ MEASURED ON THE ACTUAL HARDWARE — 29 Aug 2026

Rider measurements with a steel rule. These **supersede every drawing figure
they contradict**, and the case is now built from them.

| What | Measured | Drawing said | Status |
|---|---|---|---|
| Display PCB length | **82.0 mm** | 86.00 | ★ **4 mm shorter.** Cross-checked independently: the white panel frame is 70 mm, centred, with 6 mm of board at each end — 70 + 6 + 6 = 82 |
| Display PCB width | **50.0 mm** | 50.00 | agrees |
| White panel frame | **70 × 50 mm, centred** | glass 69.20, *not* centred | ★ On this board the frame **is** centred along the length. On the MSP2806 it is not. |
| Frame proud of the PCB edge | **0.35 mm** per side | not documented | Module is 50.7 mm at its widest. Nothing in any datasheet mentions this lip, and a 50.6 mm locating pocket would have jammed on it. |
| Module thickness, glass face → PCB back | **5.0 mm** | 4.40 | Taking the measured, larger value |
| Header pin projection past the PCB back | **10.0 mm** | 8.38 | |
| SD socket above the PCB back face | **3.0 mm** | ≤2.20 (micro-SD board) | Full-size socket, so taller |
| **Folded ribbon loop above the PCB back** | **4.0 mm** | feature does not exist on the MSP2806 | ★ **The tallest thing on the back.** This is the obstruction the audit could not characterise. |
| ESP32 length | **50.0 mm** | 58 (vendor listing) | see below |
| ESP32 width | **25.0 mm** | 25 | agrees |
| JST connector height | **6.0 mm** | ~6 inferred | confirmed |

### The active-area offset — measured at last

Screen lit white, two independent readings:

```
D (header end) = 14 mm, C (far end) = 7 mm  ->  span 61.0, offset 3.5
D (header end) = 15 mm, C (far end) = 8 mm  ->  span 59.0, offset 3.5
```

Both spans exceed the 57.6 mm the panel can physically produce (320 px ×
0.18 mm), by 1.70 and 0.70 mm respectively — and **the excess is equal at both
ends in each case.** That is backlight glow spilling past the pixel edge, which
inflates the span and leaves the difference untouched. So the offset is taken
from the difference, which the glow cannot corrupt:

> **`disp_active_off = 3.5 mm` toward the far end.** Not 0, not the inherited
> 4.90. Two readings of different edges agreeing on 3.5 is the confirmation.

### The handlebar ball — 17 mm, VERIFIED from the manufacturer

**VERIFIED** 29 Aug 2026 from BOBO's own product listings, by two independent
routes:

1. BOBO's **[Metal Buckle Handlebar Attachment][bobobuckle]** (SKU BB-BM-502) is
   sold in a **17 mm** ball version whose stated compatibility list names the
   **BM4** explicitly, alongside the BM1/2/3/5/6/10/11/12/14/20/21/24 series.
2. BOBO's stem mounts split the same way — **SM1 carries a 25 mm ball, SM2
   a 17 mm ball**, and the BM4 pairs with the SM2.

So the ball on the bike is **Ø17.0 mm**, and this is now a sourced figure
rather than the "near-universal motorcycle standard" it was being taken on.

★ **One caveat that keeps it worth a glance.** BOBO sells the same buckle in
**15, 17 and 25 mm**. The 17 is what ships with a BM4, but if the handlebar
attachment was ever bought separately or swapped, it could be another size.
Thirty seconds of confirmation, no callipers:

```
paper strip round the ball's widest point, mark the overlap, flatten, measure:
    47.1 mm  ->  15 mm ball
    53.4 mm  ->  17 mm ball   <- expected
    78.5 mm  ->  25 mm ball
```

Circumference multiplies the error by pi, which is exactly why this beats
trying to measure a sphere's diameter with a rule. A 15 and a 17 are 6.3 mm
apart on the strip — unmissable.

[bobobuckle]: https://www.bobogears.com/product/bobo-metal-buckle-handlebar-attachment/

### ★ The ESP32 is probably a LOLIN32 **Lite**, not a LOLIN32

50 × 25 mm matches the published **LOLIN32 Lite** outline (~50.4 × 25.5) rather
than the full LOLIN32 (~58 × 26) the vendor listing describes. Both carry a JST
battery connector, so that is not a discriminator.

This does not affect the enclosure — the display is the larger part and
`mcu_l` is referenced by no geometry — but **it matters for the perfboard
layout and for the pin map**, because the Lite breaks out fewer pins in a
different order. The working pin map in `User_Setup.h` is bench-proven and
remains the authority; do not "correct" it against a LOLIN32 pinout diagram.

---

## 1. SmartElex 2.8" TFT (ILI9341, SPI, 240×320, non-touch)

### 1.1 Source and SKU

| Item | Value | Status |
|---|---|---|
| Robocraze SKU | **TIFDP0094** | VERIFIED — [robocraze.com product page][rc1] |
| Product name | SmartElex 2.8 Inch TFT LCD Display 240×320 | VERIFIED — [rc1] |
| Vendor manual | `2.8_inch_manual.pdf` | VERIFIED — [linked from rc1][rcpdf] |
| Touch | **NO** — the vendor manual states "Touch Support: NO" | VERIFIED — [rcpdf] |
| Underlying generic module | **LCDWIKI MSP2806** (the no-touch member of the MSP2806/MSP2807 pair) | INFERRED — see below |

**The SmartElex manual publishes no dimensions at all.** It is nine pages of
Adafruit_ILI9341 demo code plus a six-line feature list. Robocraze, the
authoritative source for their own house brand, does not state a single
millimetre anywhere on the product page or in the datasheet they link. That is
the central finding for this part: **the vendor cannot answer the question.**

So the dimensions below come from the generic module the SmartElex is a rebadge
of. The identification rests on three independent matches:

1. **The pin list is identical.** The SmartElex manual lists exactly nine module
   pins — VCC, GND, RESET, DC, CS, SDI(MOSI), SDO(MISO), SCK, LED. The LCDWIKI
   MSP2806/2807 manual lists the same nine as pins 1–9, with the five touch pins
   (T_CLK, T_CS, T_DIN, T_DO, T_IRQ) as pins 10–14 that "you can not connect"
   if the module has no touch function. ([MSP2807 manual][msp2807])
2. **The bad advice matches.** The SmartElex manual's wiring table specifies a
   10 K resistor on every signal line and VCC to 5 V — the exact LCDWIKI-family
   instruction that `HARDWARE.md` already identifies as 5 V-Arduino guidance and
   correctly discards for a 3.3 V ESP32.
3. **The touch/no-touch split matches the SKU pair.** LCDWIKI ships one PCB in
   two populations: MSP2807 with touch, **MSP2806 without**. A non-touch 2.8"
   ILI9341 SPI board with this pin list is the MSP2806 population.

Confidence: high that it is this module family. Not certain that Robocraze's
batch is dimensionally identical to LCDWIKI's — **see §1.4 and §6 for the check
to run before printing.**

[rc1]: https://robocraze.com/products/smartelex-2-8-inch-tft-lcd-display-240x320-color-lcd-screen-for-diy-electronics
[rcpdf]: https://cdn.shopify.com/s/files/1/0559/1970/6265/files/2.8_inch_manual.pdf
[msp2807]: https://www.dragonwake.com/download/LCD/2.8inch_spi/2.8inch_SPI_Module_MSP2807_User_Manual_EN.pdf
[lcdwiki2807]: https://www.lcdwiki.com/2.8inch_SPI_Module_ILI9341_SKU:MSP2807

### 1.2 PCB outline and thickness

| Dimension | Value | Status |
|---|---|---|
| PCB length (long edge) | **86.0 mm** | VERIFIED — "Module PCB Size 50.0x86.0 (mm)", [MSP2807 manual p.2][msp2807]; same figure on [LCD wiki][lcdwiki2807] |
| PCB width (short edge) | **50.0 mm** | VERIFIED — same source |
| PCB thickness | **1.6 mm** | INFERRED — not published. 1.6 mm is the default FR-4 thickness for this class of module and what `case.scad` already assumes. Treat as ±0.2 mm. |
| Module weight | ~25 g | VERIFIED — [MSP2807 manual p.3][msp2807] |

`case.scad` currently has `disp_pcb_w = 50.0`, `disp_pcb_l = 86.0`,
`disp_pcb_t = 1.6`. **All three are correct** — the outline pair is confirmed by
datasheet, the thickness is a reasonable standing assumption.

Note the enclosure sizing consequence: `HARDWARE.md` describes the case as
"roughly 94 × 58 × 20 mm". An 86 × 50 board plus 1.2 mm clearance plus 2.4 mm
walls gives 93.2 × 57.2 mm, so that estimate was already right and needs no
revision.

### 1.3 Active display area

| Dimension | Value | Status |
|---|---|---|
| Active area, short axis (240 px) | **43.2 mm** | VERIFIED — "Active Area 43.2x57.6 (mm)", [MSP2807 manual p.2][msp2807] |
| Active area, long axis (320 px) | **57.6 mm** | VERIFIED — same source |

**This is also derivable, and the derivation agrees, which is worth doing
because it is the check that catches a mislabelled panel.**

Pixel pitch on this panel is 0.18 mm exactly:

```
240 px × 0.18 mm = 43.2 mm
320 px × 0.18 mm = 57.6 mm
diagonal = sqrt(43.2² + 57.6²) = sqrt(1866.24 + 3317.76) = sqrt(5184) = 72.0 mm
72.0 mm / 25.4 = 2.835 inches
```

So the true diagonal is **2.835"**, not 2.800". "2.8 inch" is the marketing
round-down, and the panel is very slightly larger than the name implies.

If you had instead taken the name at face value and computed from a literal
2.800" diagonal at 3:4:

```
2.8 in = 71.12 mm ;  3-4-5 triangle → 0.6 × 71.12 = 42.67 mm, 0.8 × 71.12 = 56.90 mm
```

That gives **42.7 × 56.9 mm** — about **0.5 mm and 0.7 mm too small on the two
axes**. Cutting a bezel aperture to those numbers would crop the live edge of
the picture on all four sides. **Use 43.2 × 57.6, the datasheet pair, not the
figure derived from the nominal 2.8 inches.** This is exactly the trap the
"compute it from the diagonal" instinct walks into.

`case.scad` already has `disp_active_w = 43.2`, `disp_active_l = 57.6`.
**Both correct, now datasheet-backed rather than assumed.**

---

### 1.4 Active area position relative to the PCB — ★ THE ANSWER, AND IT IS NOT ZERO

**LCDWIKI publishes a dimensioned mechanical drawing for the exact non-touch
SKU.** It is not linked from any product listing, only from the downloads block
of the MSP2807 wiki page, filed under the *other* SKU's name:

> **[MSP2806_Size.pdf][size2806]** — "LCM OUTLINE, SKU MSP2806, V1.0, 2024-04-11"

[size2806]: https://www.lcdwiki.com/res/MSP2807/MSP2806_Size.pdf

Every number below is read from that drawing. **Status: VERIFIED.**

#### Across the 50 mm axis (short edge) — centred

```
3.40  +  43.20 (LCD AA)  +  3.40  =  50.00 (PCB)   ← exact
```

The glass ("50.00 ±0.2 LCD BL") is the **full width of the PCB**, flush with
both long edges, and the active area is **centred, 3.40 mm in from each side**.
Corroborated independently by the panel supplier's own datasheet
([QD-TFT2803 spec v1.1, Fig. 1][qd]), which carries the same 3.40 / 43.20 / 3.40
chain.

#### Along the 86 mm axis (long edge) — ★ NOT centred, off by 4.90 mm

The drawing nests four spans from one datum edge and carries two offset callouts
on the same dimension lines:

| Feature | Span | Offset from the datum edge |
|---|---|---|
| PCB | 86.00 | 0 (datum) |
| Mounting hole centres | 76.08 | 4.96 (inferred, symmetric — not labelled) |
| LCD glass / backlight | 69.20 ±0.2 | **6.40** |
| **Active area** | 57.60 | **9.30** |

The datum is the PCB edge **furthest from the pin header**. Measuring from it:

```
PCB edge (far end)  ──0.00
                       6.40   glass starts
                       9.30   ACTIVE AREA starts   ┐
                                                   │ 57.60
                      66.90   active area ends     ┘
                      75.60   glass ends
                      86.00   PCB edge (header end)
```

Which makes the four bezel offsets, PCB edge to active area:

| From which PCB edge | To the active area |
|---|---|
| Far end (away from header) | **9.30 mm** |
| Header end | **19.10 mm** |
| Each long side | **3.40 mm** |

**So the active area centre sits 4.90 mm off the PCB centre, displaced toward
the far end:**

```
active area centre from far edge = 9.30 + 57.60/2 = 38.10 mm
PCB centre                       = 86.00 / 2      = 43.00 mm
offset                           = 43.00 − 38.10  =  4.90 mm
```

> ### ★ `case.scad` has `disp_active_off = 0.0`. That is wrong by 4.90 mm.
>
> This is the most consequential number in this document. Printing the lid as
> currently parameterised puts the aperture 4.90 mm off along the long axis.
> The glass bezel is only **2.90 mm** wide at the far end (9.30 − 6.40), so a
> 4.90 mm error does not merely look off-centre — **it crops roughly 4.9 mm off
> one end of the live picture and exposes bare PCB at the other.**
> Set `disp_active_off = 4.90` (sign per §5).

#### Why the offset exists, and why it points that way

The panel is specified **12 o'clock viewing direction**, driver **ILI9341V**
([MSP2806 drawing, notes 2 and 3][size2806]). On a 12 o'clock TN panel the COG
driver and the FPC tail run along the **bottom** edge — the edge facing the pin
header, because the tail has to reach the board. The driver strip is what eats
the border:

```
glass border, far end     = 9.30 − 6.40   = 2.90 mm   (plain bezel)
glass border, header end  = 75.60 − 66.90 = 8.70 mm   (driver + FPC)
                                            ────────
                            total          = 11.60 mm = 69.20 − 57.60 ✓
```

That 2.90-against-8.70 asymmetry is the whole reason the aperture cannot be
centred. It also independently confirms which edge is the datum: **the wide
border must be at the header end**, because that is where the driver is.

#### The residual doubt, and the check that closes it

The chain above is verified for the **LCDWIKI MSP2806**. That the Robocraze
SmartElex is dimensionally identical is **inferred** (§1.1), not proven —
Robocraze publishes nothing. Before committing a lid print, run the
calliper-free check in **§6.1**, which resolves the offset to about ±0.5 mm from
a photograph. Or just print `lid()` on its own first and offer it up.

[qd]: https://www.lcdwiki.com/res/MSP2807/QD-TFT2803%20specification_v1.1.pdf

### 1.5 Assembled height (worst case)

From the Side view of the [MSP2806 drawing][size2806]. **VERIFIED:**

| Layer | Value |
|---|---|
| LCD glass, without back tape | 2.30 ±0.1 mm |
| LCD back tape | 0.50 mm |
| PCB | 1.60 mm |
| **Bare module, glass face to back copper** | **4.40 ±0.2 mm** ("Total Thickness excluding Header") |
| SMD components on the back | 2.20 mm max |
| Pin header, projection behind the PCB | 8.38 mm |
| Pin header, own height | 11.17 mm |
| **Module + soldered straight header, glass to pin tips** | **12.78 mm** ("Total height (include Header)") |

The arithmetic closes, which is a good sign the drawing is self-consistent:
`1.60 + 0.50 + 2.30 = 4.40` ✓ and `4.40 + 8.38 = 12.78` ✓.

> ### ★ The number that really sets case depth — and it breaks the 20 mm budget
>
> 12.78 mm is the module with a bare soldered header and **nothing plugged into
> it**. The moment a female Dupont jumper goes on, the housing swallows the
> 8.38 mm of pin and stands roughly **14–15 mm proud of the PCB back face**,
> before the wire even bends. Realistic worst case, glass face to the back of a
> seated Dupont shell:
>
> ```
> 4.40 (module)  +  ~15 (Dupont shell)  ≈  19–20 mm      display alone
> ```
>
> `HARDWARE.md` budgets the whole enclosure at **~20 mm deep**, and that depth
> has to hold the display *and* the LOLIN32 *and* the wiring *and* two 2.4 mm
> walls. **Dupont connectors on the display header do not fit. Not marginally —
> at all.**
>
> Three ways out, best first:
>
> 1. **Solder the nine wires straight to the module's pads, no header.** Module
>    stack becomes 4.40 mm plus the wire. Free, and it also deletes nine
>    vibration-loosening friction joints from a device bolted to a motorcycle —
>    the same argument `HARDWARE.md` already makes for a quarter-turn mount over
>    a clamp screw.
> 2. **Right-angle header**, so wires exit in the plane of the board. Adds about
>    2.5 mm of depth instead of ~15.
> 3. **Straight header with the pins cut short.** Keeps 12.78 mm. Worst of the
>    three and still gives no connector.
>
> This interacts with the Stage 11 perfboard work in §4 and with the backlight
> MOSFET that `HARDWARE.md` flags as "decide before soldering to perfboard".
> **Decide the display's wire exit at the same time as the MOSFET.**

### 1.6 Mounting holes

**VERIFIED** from the [MSP2806 drawing][size2806]:

| Property | Value |
|---|---|
| Count | 4, one near each corner |
| Hole diameter | **Ø3.20 mm** ("4-3.20") — clearance for M3 |
| Keep-out / pad diameter | **Ø4.70 mm** ("4-4.70") |
| Hole centre grid | **44.00 × 76.08 mm** |
| Inset from each long (50 mm) edge | **3.00 mm** — verified, `44.00 + 3.00 + 3.00 = 50.00` ✓ |
| Inset from the **far** (non-header) edge | **3.00 mm** — VERIFIED |
| Inset from the **header** edge | **6.92 mm** — VERIFIED; `3.00 + 76.08 + 6.92 = 86.00` ✓ |

★ **CORRECTED 29 Aug 2026.** This row previously read "4.96 mm from each short
edge — INFERRED as `(86.00 − 76.08) / 2`, assuming symmetry". The drawing does
label it, and **the holes are not symmetric**: they sit 1.96 mm toward the far
end. Confirmed twice over — the explicit `3.00` callout sits in the same nested
dimension chain as the `6.40` glass and `9.30` active-area offsets, and the
extracted hole-circle centres land in the same place.

Standoffs laid out on the old symmetric 4.96/4.96 pattern would miss by 1.96 mm
at **both** ends. Ø3.20 holes on M3 screws give about 0.1 mm of slop, so that
is not a tight fit — it is a scrapped print.

This is the same error, from the same cause, as the original `disp_active_off =
0.0`: assuming symmetry on a board that is asymmetric by design. The glass is
off-centre, the mounting holes are off-centre, and the reason is the same — the
driver chip eats one end.

Four Ø3.20 holes on a 44.00 × 76.08 grid are a proper mounting scheme for M3 —
better than trapping the board between bosses and hoping the lid holds it. The
case does not currently use them; it probably should.

### 1.7 Connectors

**VERIFIED** from the [MSP2806 drawing][size2806] and the [MSP2807 manual][msp2807]:

| Property | Value |
|---|---|
| Header | single row, **14 positions**, 2.54 mm pitch |
| Header pin span | **33.02 mm** (`13 × 2.54`) |
| Position across the width | **centred** — `8.49 + 33.02 + 8.49 = 50.00` ✓ |
| Which edge | the short edge at the **header end** — the same end as the 8.70 mm wide glass border |
| Offset from that PCB edge | **2.00 mm** |
| Projection behind the PCB | **8.38 mm** (pins); header body 11.17 mm |
| SD card slot | on the **back** face, near the header end |
| Back-side component height | 2.20 mm max |

Of the 14 positions, **this project uses 9**: VCC, GND, CS, RESET, DC/RS,
SDI(MOSI), SCK, SDO(MISO), LED. Positions 10–14 are the touch signals (T_CLK,
T_CS, T_DIN, T_DO, T_IRQ), unpopulated on a non-touch board.

Two things to confirm on the actual board, neither needing a calliper:

- **Count the header positions.** If yours has 9 rather than 14 it is a
  different population, and the 8.49 mm centring figure will not hold — the span
  would be `8 × 2.54 = 20.32 mm`. The PCB outline and glass position are
  unaffected either way.
- **`HARDWARE.md` says to tie T_CS to 3.3 V if touch pins are exposed.** On a
  true MSP2806 there is no touch controller to keep off the SPI bus, so the step
  is moot — but only if the pins really are absent. Look before wiring.

**Orientation, stated plainly because it is easy to get backwards: the pin
header and the wide 8.70 mm glass border are at the SAME end of the board.** The
narrow 2.90 mm border is at the far end. The aperture shifts toward the far end.

---

## 2. WEMOS LOLIN32 (ESP32, CH340, LiPo JST)

### 2.1 Identification — ★ this is not actually a WEMOS product

The board was bought from Robocraze at ₹449 as **SKU TIFCC0110**, listed as
"ESP32 CP2102 Wireless Development Board D1 LOLIN32" ([product page][rclolin];
the ₹449 sale price on the page matches the order exactly).

[rclolin]: https://robocraze.com/products/esp32-development-board-lolin

**Three independent signs say this is a third-party board that copies the
LOLIN32 name and Arduino board profile, not the WEMOS original:**

| | Genuine WEMOS LOLIN32 V1.0.0 | The board in hand |
|---|---|---|
| USB connector | Micro-USB ([espboards][espb]) | **USB-C** (`HARDWARE.md` BOM) |
| USB-serial chip | CP2104 ([espboards][espb]) | **CH340**, bench-verified — and the Robocraze listing title says CP2102, a *third* answer |
| GPIO 4 | broken out ([espboards pinout][espb]) | **not broken out** — bench-verified |
| GPIO 16 | not in the published pinout ([espboards][espb]) | **broken out and working as TFT RESET**, verified 22 Aug 2026 |

`HARDWARE.md` already records two of these as hard-won bench findings: "The USB
chip is CH340, not CP2102, despite what some listings say", and "RESET is GPIO
16, not 4. GPIO 4 is not broken out on the LOLIN32." **Those observations are
the authority for this board.** Every published WEMOS LOLIN32 datasheet is,
strictly, describing a different object.

What follows from that for enclosure design: **there is no manufacturer
datasheet for this board, and there cannot be one.** The outline below is from
the vendor's own listing, which is the best available source, and the rest is
inferred from parts whose dimensions *are* published. Treat §2 as materially
less certain than §1, where an exact SKU drawing exists.

[espb]: https://www.espboards.dev/esp32/lolin32/

### 2.2 PCB outline and thickness

| Dimension | Value | Status |
|---|---|---|
| PCB length | **58 mm** | VERIFIED against the vendor of the actual part — Robocraze spec table, "PCB Size 58×25mm" ([TIFCC0110][rclolin]) |
| PCB width | **25 mm**, likely 25.4 | VERIFIED as 25 by Robocraze; [espboards][espb] gives **25.4 mm** for the WEMOS board. The two disagree by 0.4 mm — see below |
| PCB thickness | **1.6 mm** | INFERRED — not published anywhere. Standard FR-4. |
| Weight | 8 g | VERIFIED — [Robocraze spec table][rclolin] |
| Digital I/O | 26 pins | VERIFIED — [Robocraze][rclolin] |

**On the 25 vs 25.4 disagreement:** take **25.4 mm**. 25.4 mm is exactly 1.000
inch and exactly 10 × 2.54 mm header pitch, which is how these boards are laid
out; "25" is a rounded retail figure. `case.scad` already has `mcu_w = 26.0`,
which is generous enough to swallow the difference either way.

**A third source disagrees more seriously and should be discarded.** A widely
mirrored "Wemos ESP32 Lolin32 Board BOOK" PDF gives "Dimensions 50x25mm" and "2
mounting holes, 3 mm diameter" ([megma.ma mirror][book]). That document is
describing the **LOLIN32 Lite**, not the LOLIN32 — its own text says the board
"does not use the WROOM32 module … has the ESP32 chip, the 4MByte flash memory,
and the antenna built directly on the board", and puts the LED on GPIO22. Both
are Lite characteristics. **Do not use its 50 mm figure or its mounting holes.**

[book]: https://megma.ma/wp-content/uploads/2021/08/Wemos-ESP32-Lolin32-Board-BOOK-ENGLISH.pdf

`case.scad` has `mcu_l = 58.0`, `mcu_w = 26.0`. **Both fine** — length now
vendor-confirmed, width carries about 0.6 mm of deliberate slack.

### 2.3 Assembled height (worst case)

Nothing publishes a stack height for this board, so it is built up from parts
that are individually documented.

| Layer | Value | Status |
|---|---|---|
| PCB | 1.6 mm | INFERRED (standard FR-4) |
| ESP32-WROOM-32 module, above the PCB | **3.10 ±0.15 mm** | **VERIFIED** — Espressif datasheet, module is 18.00 ±0.15 × 25.50 × 3.10 ±0.15 mm ([Espressif][wroom]) |
| USB-C receptacle, above the PCB | ~3.2 mm | INFERRED — typical 16-pin SMD USB-C receptacle |
| **JST LiPo connector, above the PCB** | **~6 mm** | INFERRED — typical JST-PH 2.0 vertical header. **Probably the tallest thing on the top face.** |
| Male header pins soldered through, below the PCB | ~2.54 mm of plastic, plus pin | INFERRED |
| Female Dupont socket on top of a header | ~8.5 mm body | INFERRED |

A useful sanity check that the outline is right: the WROOM-32 module is
**25.50 mm** on its long side and **18.00 mm** on its short side. It can only sit
on a 25.4 mm-wide board with its 18.00 mm dimension across the width. That fits,
with about 3.7 mm of board either side — consistent with 25.4 mm and *not*
consistent with a much narrower board.

**Recommended build — LOLIN32 soldered to perfboard on its own header pins, no socket:**

```
perfboard              1.60
header plastic         2.54
LOLIN32 PCB            1.60
tallest top-face part  6.00   (JST; 3.10 if the JST is removed or shorter)
                      ─────
                      11.74 mm, plus wire dressing
```

**`case.scad` has `mcu_stack = 14.0`. That is a sound number for this build** —
11.74 mm plus a little over 2 mm for wiring. Keep it.

> ### ★ But it fails immediately if you socket the board
>
> Put the LOLIN32 on **female** header strips so it can be unplugged, and the
> stack becomes roughly `1.6 + 8.5 + 1.6 + 6.0 ≈ 17.7 mm` before wiring. Add the
> display and two 2.4 mm walls and the case passes 25 mm, against a ~20 mm
> budget in `HARDWARE.md`.
>
> This is the same trap as §1.5, from the other side. **The 20 mm enclosure
> depth is only achievable if neither board uses pluggable connectors
> internally.** That is a real design constraint and it should be decided
> alongside the backlight MOSFET, before anything is soldered.

> ### ★ A second, smaller `case.scad` finding
>
> ```
> inner_h = disp_pcb_t + mcu_stack + 2.0;      // disp_pcb_t = 1.6
> ```
>
> `disp_pcb_t` is the display's **bare PCB** thickness, but the thing that
> occupies space in the cavity is the whole display module — glass, tape and PCB
> — which §1.5 verifies as **4.40 mm**. As written, `inner_h` under-counts the
> display by **2.80 mm**. Either set `disp_pcb_t = 4.4` (and rename it, since it
> is then a module thickness), or add the 2.8 mm explicitly. Left alone, the lid
> presses on the display.

[wroom]: https://www.espressif.com/sites/default/files/documentation/esp32-wroom-32_datasheet_en.pdf

### 2.4 Mounting holes

**UNKNOWN — and quite possibly none.**

No source consulted documents mounting holes on the LOLIN32 (as opposed to the
Lite). The only figure found, "2 holes, 3 mm diameter", comes from the
[board book][book] that §2.2 shows is describing the Lite, so it does not apply.

This is a case where **absence of evidence is close to evidence of absence**:
the LOLIN32 packs a 58 × 25.4 mm board with a 25.5 mm module, a USB-C jack, a
JST connector and two full-length header rows. There is very little board left
for mounting holes.

**Design around it.** Do not put screw bosses under the MCU expecting holes to
receive them. Retain the LOLIN32 either by soldering it to the perfboard (§4),
which is the plan anyway, or with a printed clip or a dab of RTV. The display,
by contrast, *does* have four documented Ø3.20 holes (§1.6) and should carry the
mechanical load.

To settle it in ten seconds without a calliper: **look at the board.** Corner
holes are visible or they are not.

### 2.5 Connectors — USB and JST

**Mostly UNKNOWN. This is the weakest area in the whole document, and it matters
because the USB-C port has to line up with a hole in a sealed wall.**

| Property | Value | Status |
|---|---|---|
| USB connector type | USB-C | VERIFIED — `HARDWARE.md` BOM, and the board is in hand |
| USB-C position | centred on one short (25.4 mm) end | INFERRED — universal on this board family |
| USB-C receptacle height above PCB | ~3.2 mm | INFERRED — typical |
| USB-C receptacle width | ~9.0 mm | INFERRED — typical |
| **USB-C overhang past the PCB edge** | **UNKNOWN**, typically 0–1.5 mm | UNKNOWN |
| JST LiPo connector | 2-pin, white, marked `+` | VERIFIED — `HARDWARE.md` |
| JST position and height | on the top face; ~6 mm tall | INFERRED |

Two notes that come straight out of `HARDWARE.md` and are worth repeating here
because they are mechanical, not electrical:

- **The `+` beside the white connector is the LiPo JST terminal, not a 5 V pin.**
  The project deliberately excludes an internal battery, so this connector is
  dead weight — but it is still physically present and, at ~6 mm, is probably
  the **tallest object on the board**. If depth gets tight, desoldering it is a
  legitimate 3 mm saving. Nothing in the design uses it.
- **The USB port is needed after the case is closed**, because `HARDWARE.md`
  requires uploads to go through the Arduino IDE over USB. So the wall opening
  is not optional, and it is a hole in a sealed, gasketed enclosure that also
  needs an ePTFE vent and a cable gland. Consider whether the USB opening should
  be a blanking plug or a serviceable panel rather than an open slot.

**How to place the USB cut-out without a calliper:** do not try to measure the
connector. Instead, **print the body with no USB opening at all, offer the board
up, and mark through** — or print a 1 mm-thick throwaway test coupon of just
that wall face with a generous 12 × 5 mm slot, check the plug seats, and
transfer the winning dimensions. A USB-C plug overmould is much larger than the
receptacle, so size the hole for the **plug**, not the socket.

---

## 3. BOBO BM4 mount

### 3.1 Ball diameter

**UNKNOWN from any published source. 17 mm is a well-founded guess, not a fact.**

BOBO publishes no engineering dimensions for the BM4 at all. Every retailer
listing checked repeats the same marketing block and nothing more. What *is*
confirmed across listings:

| Item | Value | Status |
|---|---|---|
| Handlebar sizes supported | **22, 25 and 32 mm** via metal buckle + plastic spacers | VERIFIED — [Moto Central listing][mc] ("We support 3 common sizes of handlebar diameter i.e. 22, 25, and 32 mm") |
| Hex key included | yes, for the buckle | VERIFIED — [mc] |
| Jaw grip range | 4.0–6.5" phones (some listings say 4.0–7.0") | VERIFIED — [mc], [store4riders][s4r] |
| **Ball diameter** | **not published by anyone** | **UNKNOWN** |

[mc]: https://motocentral.in/products/bobo-jaw-grip-aluminium-mobile-holder-motorcycle-mobile-mount-without-charger
[s4r]: https://www.store4riders.com/bobo-bm4-jaw-grip-motorcycle-mobile-mount.html

**Why 17 mm is nevertheless the right thing to design for.** 17 mm is a genuine
de-facto standard for this class of mount — action-camera rigs, motorcycle phone
holders and modular vehicle systems — and it is a *tight* standard, not a
nominal one: true 17 mm balls hold **±0.05 mm** ([17mm ball mount guide][ball]).
Arkon, iBOLT, Tackform, ProClip and BRCOVAN all build to it. A ₹1,200 Indian
jaw-grip mount using a non-standard ball would be unusual.

[ball]: https://electronics.alibaba.com/buyingguides/17mm-ball-mount-guide-how-to-choose-right

**Confirm it in two minutes without callipers — the paper-strip method.** This is
much better than trying to eyeball a curved surface against a ruler:

1. Cut a strip of paper about 8 mm wide. Wrap it once round the ball's equator,
   pulled snug, and mark where it overlaps with a sharp pencil.
2. Unwrap, lay it flat on a steel rule, read the distance between the marks.
   That is the **circumference**.
3. Divide by π (3.1416).

A 17 mm ball gives **53.4 mm** of circumference. A 16 mm ball gives 50.3, an
18 mm gives 56.5 — so a reading you can take to ±1 mm on a ruler resolves the
diameter to about **±0.3 mm**, which is better than most people manage with
cheap callipers anyway. If you read 53–54 mm, it is a 17 mm ball.

**A second free check you already own:** the kit ships **22 mm and 25 mm plastic
spacers and a 32 mm metal buckle**. Those are three known, moulded diameters
sitting in the box. Photograph the ball next to the 22 mm spacer, square on,
and compare — 17 against 22 is an obvious visual ratio (0.77). This doubles as
the scale reference for §6.

### 3.2 Socket / arm interface

**UNKNOWN. Nothing is published, and this one cannot be derived.**

The BM4's arm terminates in a socket that pinches the ball, tightened by the
included hex key. No source gives the socket bore, the jaw geometry, the arm
cross-section, or the thread size.

**The good news is that the design does not need those numbers.** The plan in
`HARDWARE.md` is to discard the broken copper jaw plate and print an adapter
that engages the **ball**, and a ball is the one feature here that *is* a
standard. So design the adapter against the ball, not against BOBO's arm:

- **Print a two-piece pinch socket** — a spherical cup of Ø17.0 mm split across
  its axis, pulled together by two M3 screws. It grips by elastic deformation,
  so a 0.2–0.3 mm error in the ball diameter is absorbed by the screws rather
  than becoming a rattle or a press-fit failure.
- **Make the cup a little deeper than a hemisphere** (about 60 % of the sphere,
  ~10 mm of a 17 mm ball) so it captures rather than merely rests.
- **Do not print a one-piece snap-over socket.** It will either be too loose on
  day one or crack at the split after a few thermal cycles in a black-plastic
  part sitting in Bengaluru sun — and `HARDWARE.md` already establishes the
  interior reaches 53–70 °C.
- Print it in **ASA** like the rest, and note the same argument `HARDWARE.md`
  makes about friction joints: a pinch socket *is* a friction joint, so use a
  nyloc nut or thread-locker on those M3s.

### 3.3 Garmin quarter-turn lug pattern — ★ the `case.scad` figures cannot be verified, and the model has a bug

**Checked against the best available sources. Two separate problems.**

#### Problem 1: Garmin publishes nothing, so "the standard" has no authority

> "Garmin doesn't publish the dimensions of the quarter-turn interface. The
> numbers circulating on forums and repositories are hobbyist measurements."
> — [Kapy CAD, *The Garmin quarter-turn mount*][kapy]

[kapy]: https://kapycad.com/en/learn/standards/garmin-quarter-turn

The only dimensional table that source offers is explicitly labelled
"indicative values from one unit, not official":

| Feature | Kapy CAD indicative range | `case.scad` value | Verdict |
|---|---|---|---|
| Tab thickness | **~1–1.5 mm** | `mount_lug_t = 2.4` | **outside the range, ~2× too thick** |
| Effective overlap | ~1.5–2 mm | — | not modelled |
| Overall diameter | **~20–24 mm** | `mount_lug_r = 11.5` → Ø23 | plausible, inside the range |
| | | `mount_plate_d = 26.0` | larger than any quoted figure |
| Turn angle | 90° | 90° | ✓ |
| Lug width | *not given by any source* | `mount_lug_w = 8.0` | **UNKNOWN — unverifiable** |

So of the four values `case.scad` flags as UNVERIFIED: **one (lug radius) is
plausible, one (plate Ø) is oversized, one (lug thickness 2.4) contradicts the
only published range, and one (lug width 8) cannot be checked at all.** The
`★ UNVERIFIED` comment in the file is entirely justified and must stay.

#### Problem 2: the real Garmin interface has TWO tabs at 180°, not three at 120°

Both sources consulted describe the same geometry, and it is not what
`case.scad` models:

> a bayonet with **two opposing tabs** on the device back positioned at 180°,
> the cradle having a matching recess — insert rotated ~90° from the in-use
> position, then turn a quarter turn. ([Kapy CAD][kapy])

`case.scad` builds `for (a = [0, 120, 240])` — **three lugs at 120°**.
`HARDWARE.md` likewise describes "a 3-lug Garmin-style quarter-turn" and argues
for it as "three lugs behind solid shoulders". That reasoning is sound
mechanically, but the part it produces is **not Garmin-compatible**. It will not
enter a genuine Garmin cradle, a Garmin-compatible aftermarket cradle, or any of
the printed Garmin mounts on Thingiverse/Printables.

**This is a decision, not necessarily a defect.** Two coherent options:

- **Keep 3 lugs at 120°** and accept that the interface is *JiffyTrails-only*.
  Then you must also print the mating cradle, and the word "Garmin" should come
  out of `HARDWARE.md` and `case.scad` before it misleads someone into buying a
  Garmin part. Mechanically this is the stronger joint and the reasoning in
  `HARDWARE.md` stands.
- **Go to 2 tabs at 180°** to gain the real ecosystem — cheap aftermarket
  Garmin-compatible bar cradles, out-front mounts and stem mounts, most under
  ₹500. Then the dimensions still have to be reverse-engineered from a physical
  sample, because Garmin publishes none.

Given the owner has no Garmin hardware to copy from, **option 1 (print both
halves, drop the Garmin name) is far lower risk** and keeps the vibration
argument intact.

#### Problem 3: as written, `mount_plate()` renders no lugs at all

Independent of which pattern is chosen, the current code does not produce the
part it describes:

```scad
cylinder(h = mount_boss_h, d = mount_plate_d);        // Ø26  → radius 13
...
polygon([[0,0], [mount_lug_r, -mount_lug_w/2],
                [mount_lug_r,  mount_lug_w/2]]);      // reaches radius 11.5
```

**The lugs extend to radius 11.5, inside the Ø26 (radius 13) cylinder they are
unioned with, so they are completely swallowed by it.** The subsequent
`difference()` then bores Ø18 straight through the full height. What actually
renders is a **plain tube, Ø26 outside, Ø18 inside, 6 mm tall — with no
quarter-turn feature anywhere on it.**

For the lugs to exist, `mount_lug_r` must be **greater than** `mount_plate_d / 2`
(i.e. > 13 with the current plate), or the plate diameter must shrink below
2 × 11.5 = 23 mm. Given Kapy CAD's ~20–24 mm overall range, the sane fix is to
**reduce `mount_plate_d` to about 18–20 mm and keep `mount_lug_r = 11.5`**, so
the lugs stand ~2 mm proud — which also lands the overall Ø23 comfortably inside
the indicative range.

The file's own advice — "Print `mount_test_plate()` on its own first … it is a
3 g, four-minute print" — is exactly right and would have caught this. **Do that
before anything else.**

---

## 4. Perfboard recommendation

### 4.1 The space it has to fit in

From §1.2 and `case.scad`'s own derived values:

```
cavity width   = disp_pcb_w + 2 × inner_clear = 50.0 + 2.4 = 52.4 mm
cavity length  = disp_pcb_l + 2 × inner_clear = 86.0 + 2.4 = 88.4 mm
```

Minus the four Ø7 mm screw bosses, which stand in the cavity corners.

**"Beside the display" is not available.** The display module is 50 × 86 mm and
the cavity is 52.4 × 88.4 mm — the display fills the footprint almost exactly.
The perfboard must go **behind** it, stacked, which is what makes the depth
arithmetic in §1.5 and §2.3 binding rather than academic.

### 4.2 Recommended size — 50 × 70 mm

**The standard "5 × 7 cm" board, 18 × 24 holes at 2.54 mm pitch.**

| Check | Result |
|---|---|
| Fits the 52.4 × 88.4 mm cavity | ✓ 2.4 mm spare across, 18.4 mm spare along |
| Clears the corner bosses | ✓ the 18.4 mm of spare length lets it sit clear of one pair |
| Holds the LOLIN32 (58 × 25.4 mm) | ✓ along the 70 mm axis: 58 mm used, 12 mm spare |
| Room left beside the LOLIN32 | ✓ **~20 mm × 70 mm** — 8 spare hole columns |
| Room for the cable gland and drip loop | ✓ the 18.4 mm end gap lines up with `gland_from_end = 22.0` |

That leftover 20 mm strip is not spare capacity, it is exactly where the parts
`HARDWARE.md` says are still to come must live: the **backlight low-side MOSFET**
(2N7002 or AO3400, or a BC337), its gate resistor, and the landing pads for the
nine display wires. Do not choose a smaller board.

**Buying it in India:** Robocraze stock 3×4 inch (₹24) and 6×4 inch (₹39)
boards ([Vero Boards collection][rcvero]). Either is larger than needed; score
along a hole line with a craft knife on both faces and snap it over a table
edge. Do not try to cut it with scissors — it shatters.

[rcvero]: https://robocraze.com/collections/vero-boards

### 4.3 Recommended type — plain perfboard, and specifically NOT stripboard

For a first-time solderer building *this* circuit, the ranking is:

**1st — breadboard-layout proto board ("Perma-Proto" style), if you can get one.**
The circuit is already working on an MB102 breadboard and the wiring is VERIFIED
in `HARDWARE.md`. A board with the *same* layout — power rails down the sides,
five-hole columns, centre gutter — lets you transfer the working circuit
**hole-for-hole with no re-thinking**. The centre gutter also isolates the
LOLIN32's two header rows for free. The single biggest source of error in a
first perfboard build is re-planning a layout that already worked; this
eliminates it. Harder to find in India and pricier, but worth hunting.

**2nd — plain perfboard (dot matrix, sold locally as "zero PCB" or confusingly
as "Veroboard").** Every pad is isolated, so every connection is a deliberate
act. More wires to solder — but this circuit has only about **15 nets**, so
"more wiring" costs an extra hour, not an extra weekend. Crucially there is **no
way to create an accidental short**, which matters enormously here: this is a
sealed, gasketed, RTV-filled enclosure on a motorcycle. A short you cannot see
is a short you cannot fix.

**3rd, and actively discouraged — stripboard / true Veroboard.** Two specific
reasons for this build:

- **You would have to cut tracks under the LOLIN32.** Its header rows are about
  22.86 mm apart (9 × 2.54), so every strip passing beneath the board shorts a
  left-row pin to its right-row opposite. That is **nine track cuts** that must
  each be complete, in a place you cannot inspect once the board is populated.
  A missed cut shorts something to the 3.3 V rail. `HARDWARE.md` already records
  that the 3.3 V rail is running at 3.18 V with the LDO working rather than
  coasting — it does not need an extra load fault.
- **The BOM iron is 60 W.** Stripboard copper lifts when overheated, and lifting
  a track under a soldered module is effectively unrepairable. Isolated pads on
  plain perfboard lift too, but a lifted single pad is a one-wire fix.

**A naming trap worth knowing:** in India "Vero Board" and "DOT PCB" are used
almost interchangeably by retailers, and what usually arrives is the
**dot-matrix isolated-pad** board, not true copper-strip stripboard. That is the
one you want here — but **look at the product photograph before ordering**,
because the name will not tell you.

### 4.4 How to lay it out, given the depth problem

§2.3 shows the depth budget only closes if the LOLIN32 is **not** socketed. So:

- **Solder the LOLIN32 down through male header pins**, plastic side against the
  perfboard, no female socket. Stack from the perfboard face ≈ **11.7 mm**.
- Accept that this makes the MCU non-removable. **Flash and fully test the
  firmware before soldering** — `HARDWARE.md` already requires uploads to go
  through the Arduino IDE over USB, and the USB port stays accessible through
  the case wall, so reflashing still works. It is only *replacement* you give up.
- **Solder the nine display wires directly to the display's pads** (§1.5), and
  land their other ends on the perfboard. Use stranded wire for anything that
  crosses between two boards that can move relative to each other; solid core
  work-hardens and snaps under vibration.
- **Fit the backlight MOSFET now, not later.** `HARDWARE.md` is explicit:
  "Decide this before soldering to perfboard in Stage 11 — retrofitting it into
  a sealed enclosure is the bad version of this job." The 20 mm strip in §4.2
  exists for it.

---

## 5. What could not be found, and how to get it without callipers

Listed worst-first. **Silence elsewhere in this document means a number is
sourced; a number appearing here means it is not.**

### 5.1 ★ Confirming the display's active-area offset — the white-screen photo

**What is unknown:** §1.4 gives the offset chain as VERIFIED for the LCDWIKI
MSP2806, but that the Robocraze SmartElex is the same board is INFERRED. The
4.90 mm offset is the number most likely to ruin a print.

**The method, and it is better than callipers, not a poor substitute for them:**

1. **Light the panel white.** `tft.fillScreen(TFT_WHITE)` — one line, and the
   sketch is already building. Now the active area is *self-illuminating*, and
   its boundary is unambiguous. This is the whole trick: with an unlit panel you
   are guessing where the glass ends and where the pixels begin, and those are
   6.40 mm and 9.30 mm from the edge respectively — the exact confusion that
   produces a 3 mm error.
2. Lay the module face-up on **graph paper**, on a flat surface, in even light.
3. Photograph it **from directly overhead** — phone flat against a clear box
   lid, or braced on a stack of books. Parallax is the dominant error here; get
   the camera square and centred, and stand back and zoom rather than moving in
   close.
4. **Scale from the PCB, not the header.** The PCB long edge is **86.00 mm** and
   the short edge **50.00 mm**, both datasheet-verified. Use the 50.00 mm width
   as the scale — it is a crisp, full-length edge. The 33.02 mm header span
   works too but its ends are pin centres, which are fuzzier to locate.
5. Measure, in the photo, from each PCB edge to the edge of the lit rectangle.

**Expected results if the board matches:** 9.30 mm at the far end, 19.10 mm at
the header end, 3.40 mm on each long side, lit rectangle 43.2 × 57.6 mm.

**Accuracy:** on a 3000 px-wide photo of an 86 mm board, one pixel is about
0.03 mm, so the limit is squareness and edge judgement, not resolution —
realistically **±0.5 mm**. That is comfortably good enough to confirm or reject
a 4.90 mm offset.

**With no image editor:** count graph-paper squares directly. 1 mm paper against
a 9.3 mm offset is perfectly readable by eye.

**Cross-check that costs nothing:** the two side margins must come out *equal*
(3.40 mm each) and the two end margins *unequal* (9.30 and 19.10). If your photo
shows equal end margins, the board is not an MSP2806 and none of §1.4 applies.

### 5.2 The LOLIN32 USB-C cut-out — do not measure it, transfer it

**What is unknown:** the USB-C receptacle's overhang past the PCB edge, and its
exact height and width above the board (§2.5).

**Method:** do not measure the connector. Print a **throwaway coupon** — a
1 mm-thick rectangle the size of that wall face with a generous 12 × 5 mm slot —
and check the actual plug seats through it. Adjust once, then transfer the
winning numbers into `case.scad`. Two ten-minute prints beat a calliper here,
because the thing that must fit is the **plug's overmould**, which is far bigger
than the receptacle and varies between cables.

### 5.3 The BM4 ball — the paper-strip method

Fully described in **§3.1**. Wrap, mark, unwrap, read, divide by π. A 17 mm ball
reads 53.4 mm of circumference; resolution about ±0.3 mm.

### 5.4 The Garmin lug geometry — unknowable from documentation

**What is unknown:** everything. Garmin publishes no dimensions at all (§3.3),
so there is no source to consult and no arithmetic to do.

**Method:** `mount_test_plate()` already in `case.scad` is the right instrument —
a 3 g, four-minute print. But **fix the geometry bug in §3.3 first**, because as
written it renders a plain tube with no lugs, so printing it currently tests
nothing. Then print, offer up, adjust one variable, reprint. Three iterations
will beat any measurement.

### 5.5 LOLIN32 mounting holes — look at the board

**What is unknown:** whether they exist (§2.4). No calliper needed; corner holes
are visible or they are not. Design assuming **none**.

### 5.6 PCB thicknesses — assume 1.6 mm

Neither board's PCB thickness is published. 1.6 mm is the FR-4 default and is
what `case.scad` already assumes. **Calliper-free check:** stack ten known
1.6 mm boards… which you do not have. Better: this tolerance does not matter.
`inner_clear = 1.2` absorbs ±0.3 mm without complaint. **Leave it alone.**

### 5.7 Summary of what is genuinely unresolved

| Unknown | Section | Does it block printing? |
|---|---|---|
| SmartElex == MSP2806 dimensionally | §1.1, §1.4 | **Yes for the lid** — run §5.1 |
| USB-C overhang and cut-out size | §2.5 | **Yes for the body wall** — run §5.2 |
| LOLIN32 mounting holes | §2.4 | No — design as if none |
| BM4 ball diameter | §3.1 | **Yes for the adapter** — run §5.3 |
| BM4 socket/arm geometry | §3.2 | No — design against the ball instead |
| Garmin lug dimensions | §3.3 | **Yes for the mount** — and no source exists |
| Both PCB thicknesses | §1.2, §2.2 | No — 1.6 mm, clearance absorbs it |
| JST connector height | §2.5 | No — but it may set `mcu_stack`; look at it |

---

## 6. Mapping onto `hardware/case.scad`

Every parameter the brief asked about, with the value this research supports.

| `case.scad` parameter | Current | **Recommended** | Status | Source |
|---|---|---|---|---|
| `disp_pcb_l` | 86.0 | **86.0** — no change | VERIFIED | [MSP2807 manual p.2][msp2807], [MSP2806 drawing][size2806] |
| `disp_pcb_w` | 50.0 | **50.0** — no change | VERIFIED | same |
| `disp_active_l` | 57.6 | **57.6** — no change | VERIFIED | [MSP2807 manual p.2][msp2807]; independently derived, §1.3 |
| `disp_active_w` | 43.2 | **43.2** — no change | VERIFIED | same |
| **`disp_active_off`** | **0.0** | **★ 4.90** | VERIFIED for MSP2806; confirm via §5.1 | [MSP2806 drawing][size2806], §1.4 |
| `mcu_l` | 58.0 | **58.0** — no change | VERIFIED (vendor of the actual SKU) | [Robocraze TIFCC0110][rclolin] |
| `mcu_w` | 26.0 | **26.0** — keep the slack | VERIFIED 25 / 25.4, sources differ | [Robocraze][rclolin] 25; [espboards][espb] 25.4 |
| `mcu_stack` | 14.0 | **14.0** — but only if the MCU is *not* socketed | INFERRED, built up in §2.3 | [Espressif WROOM-32][wroom] + typical parts |

### The one change that matters

```scad
disp_active_off = 4.90;   // was 0.0
```

**Sign convention.** In `case.scad` the display's long axis is `y`, and the
aperture is placed by `translate([0, disp_active_off, -1])`. The active area
must shift **away from the pin-header end**. The header end is where the wires
leave, so it is the end with the cable gland — and the gland is placed at
`-body_l/2 + gland_from_end`, i.e. the **−y** end. Therefore the far end is
**+y** and the offset is **positive: `+4.90`**.

If you orient the board the other way round when you build it, the sign flips.
**Check it before printing the lid** — this is a one-character error that scraps
a print.

### Three further changes this research turned up, outside the requested list

| Where | Issue | Fix |
|---|---|---|
| `inner_h` (§2.3) | Uses `disp_pcb_t = 1.6`, the bare PCB, but the display *module* is **4.40 mm** thick. Under-counts the cavity by **2.80 mm**; the lid presses on the glass. | Set `disp_pcb_t = 4.4` (and rename — it is a module thickness), or add 2.8 mm to `inner_h` |
| `mount_plate()` (§3.3) | Lugs reach r = 11.5, inside the Ø26 plate they union with, so **no lugs render at all** — the part is a plain tube | Reduce `mount_plate_d` to ~18–20, keep `mount_lug_r = 11.5` |
| `mount_lug_t` (§3.3) | 2.4 mm against the only published indicative range of **1–1.5 mm** | Unresolvable from documentation — print and fit |

### Confidence, honestly stated

- **Display (§1): high.** A dimensioned drawing exists for the exact non-touch
  SKU, and every figure cross-checks against a second source or against
  arithmetic. The one open question is whether Robocraze's rebadge is the same
  board, which §5.1 settles in an afternoon.
- **LOLIN32 (§2): moderate for the outline, low for everything else.** The board
  is not a WEMOS product and has no datasheet. 58 mm comes from the vendor of the
  actual SKU; the stack height is a build-up from published component sizes, not
  a measurement.
- **Mount (§3): low, and irreducibly so.** BOBO publishes nothing and Garmin
  publishes nothing. This section is the one that must be resolved by printing
  test parts rather than by reading.
