# SPEC: the moving map

**Status:** implementation specification, first draft 28 Aug 2026.
**Scope:** how to put a rider arrow and the roads around it on the 320x240
handlebar panel, from open-source map data, updating as he rides.

**Prerequisites, not repeated here.** `ARCH_OWN_NAV_APP.md` §7 settled *whether*
(yes) and *how it should feel* (step, don't animate). `ARCH_ANDROID_AUTO.md`
§2.2 settled *where the geometry comes from* (offline vector tiles on the phone,
clipped to a window, sent as line segments in the rider frame).
`firmware/navigator/geom.h` / `geom.cpp` already implement the device-side
renderer. This document is the byte-level, pixel-level, millisecond-level
build sheet that sits under all three.

**Convention.** Every claim is marked **[verified]** (read the source or the
code), **[computed]** (arithmetic from a verified figure), **[inferred]**
(reasoned, not measured) or **[unknown]** (must be settled before that line of
code is written).

---

## 0. The decisions, in one table

| # | Question | Decision | Where |
|---|---|---|---|
| 1 | Where does the map live on screen? | **Stay in the glyph box.** 96x96 at (6,80) on the approach screen. No full-screen map. | §1 |
| 2 | Tile format on the phone | **PMTiles v3**, one file, with a ~250-line Kotlin reader. MBTiles is the named fallback. | §2.1 |
| 3 | Extract | `planetiler` over the Geofabrik `southern-zone` PBF, bbox-clipped to Bengaluru metro, z8–z14. | §2.2 |
| 4 | MVT decoder | `no.ecc.vectortile:vector-tile-java` + JTS. | §2.3 |
| 5 | Simplification | RDP at **3 m**, after clipping, in the rider-local metric frame. | §2.4 |
| 6 | Classes kept | motorway, trunk, primary, secondary, tertiary and their `_link`s; plus whatever way the rider is snapped to. | §2.5 |
| 7 | Position | `FusedLocationProviderClient`, `PRIORITY_HIGH_ACCURACY`, 1000 ms. | §3.1 |
| 8 | Heading | `Location.getBearing()` — course over ground. Frozen below 2.8 m/s. **Never** the compass. | §3.2 |
| 9 | Wire | `0x09 GEOM` fragmented into ≤182-byte notifications behind a 4-byte fragment header; `0x0A POSE` at 4 Hz; `0x0B TILE`; `0x0C TILEACK` device→phone. | §4 |
| 10 | Motion | **Both, layered.** Windows step at 0.33–1 Hz; the ESP32 dead-reckons between them but repaints only when accumulated motion exceeds **4 px** or heading exceeds **3°**. | §5 |
| 11 | Device cache | 3x3 grid of 256 m tiles, ~7.6 kB, evicted by grid distance, reconciled by a 16-bit `tileId` the phone tracks and the device confirms. | §6 |
| 12 | Strokes | The hatching is **already fixed on disk** (filled quads + octagon joins). Add `drawWideLine` AA for the ink pass only, into a 16 bpp sprite. | §7 |
| 13 | Stale rule | 6 s hard blank (`GEOM_MAX_AGE_MS`, already shipped); 2.5 s soft — stop dead-reckoning and mark it. | §8 |

---

## 1. The picture

### 1.1 What is already on the panel

All figures **[verified]** from `firmware/navigator/display.cpp`.

```
ROTATION 1 (landscape)   W = 320   H = 240
distance sprite   SPR_X 112, SPR_W 208, SPR_H 80   (opaque, flush to x=320)
ARROW_ZONE        108                              (nothing may cross this)
glyph box  far    (  8,  68)  84x84     screen > 500 m
glyph box  appr   (  6,  80)  96x96     500-100 m
glyph box  big    (  4,  76) 104x104    < 100 m
alert band        y 190, h 50
instruction text  y 4-6, font 4, up to two lines on the far screen
```

Screen selection is `screenFor()` in `nav_types.h`: `> 500 m` far,
`500–100 m` approach, `< 100 m` committed, `< 30 m` now (inverted). **[verified]**

The map already draws into the glyph box: `drawNavGlyph()` calls
`geomDraw(tft, gx, gy, gs, …)` when `geomValid()`, else the maneuver arrow.
**[verified]**

### 1.2 Variant A — map in the glyph box (96x96). **Recommended.**

Scale, with `GEOM_DEPTH_M = 120` filling the box height **[computed from
`geom.cpp`]**:

```
96 px  /  120 m  =  0.80 px/m   ->  1.25 m/px
rider at (cx, cy) = (gx + 48, gy + 96 - 12) = (54, 164)
forward visible   = 84 px / 0.80 = 105 m ahead
behind visible    = 12 px / 0.80 =  15 m
lateral visible   = ±48 px       = ±60 m
```

So the box is a **120 m x 120 m patch of city**, which at Bengaluru arterial
spacing holds one junction and the approach to it, and nothing else. That is
the correct amount: it is the decision the rider is about to make.

At 50 km/h (13.9 m/s) the world moves **11.1 px/s** through this box
**[computed]**. A 3 s window cadence therefore steps it 33 px; a 1 s cadence
steps it 11 px. §5 spends the dead-reckoner on closing that gap.

### 1.3 Variant B — map takes most of the screen

The honest version of B is not "full screen". The distance sprite is opaque and
flush to the right edge, and distance is the single most-read number on the
panel, so B means **the left two-thirds**: a box of roughly 200x180 at (4, 40),
with distance shrunk from font 8 to font 6 and moved into the top-right corner.

```
200 px / 240 m depth = 0.83 px/m   (same scale, 2x the depth)
push cost 200x180 = 36,000 px @ 1,700 px/ms = 21.2 ms   [computed]
```

**Rejected.** Four reasons, in descending order of force.

1. **It doubles the depth, and depth is what makes a junction unreadable.**
   `geom.h` states the reasoning already: *"more depth shrinks the junction to a
   smudge"*. A 240 m box at 50 km/h covers 17 s of riding, which is two
   junctions and the gap between them. The rider does not have a question about
   the second junction.
2. **It costs a foveation, and the whole design is built to avoid that.**
   `FEATURES.md`: *"Full-block luminance inversion … detected peripherally
   **without costing a glance**. Small text is the opposite: it needs foveation,
   which is the resource the whole design is trying to protect."* **[verified]**
   A 96 px map that answers "which of these three exits" is a shape. A 200 px
   map with four junctions in it is a document.
3. **It demotes distance.** Dropping font 8 (75 px tall) to font 6 to make room
   trades the number that is *always* useful for a picture that is useful for
   about eight seconds per junction. Wrong trade.
4. **It costs nothing to defer.** `geomDraw` already takes `(x, y, s)`.
   Variant B is one call-site change and a layout constant. If a season of
   riding says the small box is too small, B is an afternoon — so there is no
   reason to buy it now on speculation.

**One concession to B, and only one.** On the **far** screen (> 500 m), where
there is no junction to draw and the box is showing the surrounding street grid
as orientation rather than as a decision, widen it to the full arrow zone:
`(4, 56) 100x100`, `GEOM_DEPTH_M` raised to 200 for that screen only. That is
where a wider view is actually informative and where nothing is being decided.
**[inferred — worth trying, not load-bearing]**

### 1.4 What stays around the map

Unchanged from the current nav screen. The map replaces the arrow glyph and
**nothing else**:

| Element | Position | Fate |
|---|---|---|
| Instruction / road name | y 4–6, font 4, ≤2 lines | **stays** — the map cannot say "onto Old Airport Road" |
| Distance to maneuver | sprite (112, 88) 208x80, font 8 | **stays, untouched** |
| ETA / remaining | alert band, y 190 | **stays** (footer, far screen only) |
| GPS-weak marker | top-right, 44 px reserved | **stays** |
| Maneuver arrow | glyph box | **replaced by the map when `geomValid()`, else drawn** |

**Below 100 m the map is not drawn at all.** `drawNavGlyph` is not called on the
committed or now screens, and that stays true: *"a drawing has to be read, an
arrow is recognised, and there is time to read a junction at 300 m and none at
60"* **[verified, `display.cpp`]**. The moving map is an *approach* instrument.

### 1.5 The rider marker

`geomDraw` puts it at `(x + s/2, y + s - s/8)` — for the 96 box, 12 px up from
the bottom edge, centred **[verified]**. It is a filled disc of r=7 with a 3 px
background ring, and it does not move or rotate.

**Change one thing: make it a chevron, not a disc.** A disc is rotationally
symmetric and therefore says "you are here" but not "you point this way". On a
heading-up map with a fixed marker the direction is implied by the frame, so
the disc is not *wrong* — but a chevron costs three `fillTriangle` calls and
removes the one moment of interpretation left in the picture. Geometry, for the
96 box:

```
apex        (cx,      cy - 9)
left wing   (cx - 8,  cy + 7)
notch       (cx,      cy + 2)
right wing  (cx + 8,  cy + 7)
```

drawn as two triangles in `fg` over a 2 px `bg` outline drawn the same way at
+2 px scale — the same halo trick the disc already uses, so it separates from
whatever road it stands on. **[inferred]**

---

## 2. Phone side — getting the roads

### 2.1 Tile format: PMTiles vs MBTiles
### 2.2 Producing the Karnataka extract
### 2.3 Decoding MVT on Android
### 2.4 The window query: clip, filter, simplify
### 2.5 Which `class` values survive at this scale

---

## 3. Position and heading

### 3.1 Location source and rate
### 3.2 Heading: course-over-ground, and the low-speed rule
### 3.3 Smoothing
### 3.4 The Android APIs, named

---

## 4. The wire format

### 4.1 `0x09 GEOM` — the window
### 4.2 Fragmentation and reassembly
### 4.3 `0x0A POSE` — the between-windows pose
### 4.4 `0x0B TILEACK` — device to phone
### 4.5 Loss, sequence numbers, and what completion means

---

## 5. Motion on the device

### 5.1 The two options, and the choice
### 5.2 Dead-reckoning arithmetic
### 5.3 Drift budget
### 5.4 Re-anchoring on a new window
### 5.5 Redraw cost in milliseconds

---

## 6. Tile caching on the ESP32

### 6.1 The grid and the residency set
### 6.2 Memory budget
### 6.3 Eviction
### 6.4 How the phone knows what the device holds
### 6.5 Reconnect

---

## 7. Rendering quality on this panel

### 7.1 The hatching bug in the current stroke
### 7.2 Anti-aliasing in TFT_eSPI
### 7.3 Minimum stroke widths at 700 mm
### 7.4 Day and night palettes

---

## 8. Failure modes

---

## 9. Verification

### 9.1 Host-side
### 9.2 On-device
### 9.3 On-phone
### 9.4 The one ride that cannot be simulated

---

## 10. Open questions

---

## Sources
