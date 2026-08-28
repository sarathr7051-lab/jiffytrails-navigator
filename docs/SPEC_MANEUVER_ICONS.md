# Maneuver icon system

Status: SPEC, 28 Aug 2026. Replaces the hand-estimated coordinates currently in
`firmware/navigator/glyph_data.h`.

## Why this exists

The glyphs on the panel were judged by eye at mount distance and written as
percentages one at a time. Two of them — `G_CONTINUE` and `G_TURN` — happen to
be right. The rest are not wrong so much as *unrelated to each other*: **nine**
different stroke widths appear across fourteen glyphs (6, 8, 9, 10, 11, 12, 14,
15, 16), arrowhead base widths range from **24 to 52** units, `G_SLIGHT`'s head
is very nearly equilateral where `G_CONTINUE`'s is a 75° wedge, and every
diagonal stroke in the set is **29% thinner than the number in the table says**
because of an interpreter detail nobody accounted for (see "The OP_LINE trap"
below).

That reads exactly as reported: drawn by hand, not drawn to a system.

This document derives one construction grid from three published maneuver icon
sets and the panel arithmetic already in `HARDWARE.md`, then emits every glyph
from it. The point is not that the numbers are prettier. The point is that they
are **shared**, so a rider who has learned one arrow has learned all of them,
and so the next maneuver added is a lookup rather than a judgement call.

## Sources

Everything below marked **verified** was read as source: SVG path data, Android
vector `pathData`, or the drawing code itself. Nothing is measured off a
screenshot.

| Source | What was read | State |
|---|---|---|
| **Google Material Symbols** (`maps` set) | `straight`, `turn_right`, `turn_slight_right`, `turn_sharp_right`, `u_turn_right`, `fork_right`, `merge`, `ramp_right`, `roundabout_right` — outlined, 24 px, `viewBox="0 -960 960 960"` | verified |
| **Google Material Icons** (legacy `maps`) | same nine, 24×24 grid | verified |
| **Mapbox Navigation SDK for Android** | `tripdata/.../mapbox_ic_turn_{right,sharp_right,slight_right,straight,uturn}.xml`, 32×32 viewport, PaintCode-generated | verified |
| **OsmAnd** | `TurnPathHelper.java` — the arrow is *constructed in code* on a 72×72 grid, so the constants are literal | verified |
| **OsmAnd** | `RouteResultPreparation.java` — the angle thresholds that classify a turn | verified |
| `HARDWARE.md` | ACR arithmetic, 1.17:1 in Bengaluru noon sun | this repo |
| `FEATURES.md` | 1 px ≈ 0.87 arc-min at 700 mm; ISO 15008 feature-size table | this repo |

URLs:

- <https://raw.githubusercontent.com/google/material-design-icons/master/symbols/web/turn_right/materialsymbolsoutlined/turn_right_24px.svg> (and siblings)
- <https://raw.githubusercontent.com/google/material-design-icons/master/src/maps/turn_right/materialicons/24px.svg> (and siblings)
- <https://raw.githubusercontent.com/mapbox/mapbox-navigation-android/main/tripdata/src/main/res/drawable/mapbox_ic_turn_right.xml> (and siblings)
- <https://raw.githubusercontent.com/osmandapp/OsmAnd/master/OsmAnd/src/net/osmand/plus/views/TurnPathHelper.java>
- <https://raw.githubusercontent.com/osmandapp/OsmAnd/master/OsmAnd-java/src/main/java/net/osmand/router/RouteResultPreparation.java>

Three things were looked for and **not found**, recorded so they are not
re-searched:

- **Mapbox `maki`** carries no maneuver arrows at all. It is a POI set.
- **Mapbox Navigation for iOS** keeps its arrows in
  `Sources/MapboxNavigationUIKit/PaintCode/ManeuversStyleKit.swift` — file
  confirmed present, contents not read. The Android drawables are PaintCode
  output from what is very likely the same source document, so this is
  **inferred**, not verified, and nothing in this spec rests on it.
- **A citable numeric arrowhead ratio in MUTCD / Standard Highway Signs.** The
  arrow details exist as dimensioned drawings, not as a published ratio, and
  they are lane-control arrows on signs read at 60 km/h — a different problem
  from a 22 mm glyph at 700 mm. Not used.

## What the three reference systems actually do

Measured from the source above, normalised to percent of the icon box.

| | shaft width | head width | head : shaft | head length ÷ head width | apex angle |
|---|---|---|---|---|---|
| Material Symbols | 8.3% | 33.3% | **4.00** | 0.50 | 90° (open chevron) |
| OsmAnd, large arrow | 11.1% | 45.8% | **4.13** | 0.51 | ~89° |
| Mapbox Navigation | 12.5% | 55.4% | **4.43** | 0.69 | **72°** |
| Mapbox, slight-turn head | 12.5% | 49.1% | 3.93 | 0.65 | **75.2°** |
| **this spec** | **16%** | **52%** | **3.25** | **0.65** | **74.8°** |
| existing `G_CONTINUE` (panel-validated) | 16% | 52% | 3.25 | 0.65 | 74.8° |

Working, so the numbers can be checked:

- **Material Symbols** `straight` is `M440-120v-567l-64 63-56-56 160-160 160
  160-56 56-64-63v567h-80`. Shaft x 440→520 = **80** of 960. Chevron tip
  (480,-840), arms to (320,-680) and (640,-680): width **320**, length **160**.
  The chevron's own stroke measures 80 — the same as the shaft — confirming one
  stroke weight throughout.
- **OsmAnd** `TurnPathHelper.TurnVariables`, verbatim: `radInnerCircle = 10`,
  `radOuterCircle = radInnerCircle + 8` → shaft **8** of 72. `widthArrow = 22`
  multiplied by `scaleTriangle` = 1.5 for the large arrow → **33** of 72.
  `radArrowTriangle1 = radOuterCircle + 7` = 25, `radEndOfArrow = 44` → head
  length **~17** measured from the widest point.
- **Mapbox** `mapbox_ic_turn_straight`: shaft x −2→+2 = **4** of 32. Head tip
  (0,−15.02), barbs (±8.86,−2.82): width **17.72**, length **12.2**.
  17.72 / 4 = 4.43; apex = 2·atan(8.86/12.2) = **72°**.
- **Mapbox** `mapbox_ic_turn_slight_right` head: apex (9.88,−12.76), base
  (−2.97,−12.04)→(7.31,−0.15). Base **15.7**, apex-to-base-midpoint **10.19**,
  apex angle = 2·atan(7.85/10.19) = **75.2°**.

Two conclusions worth stating plainly:

1. **Head width is ~4× shaft width in every system that publishes one.** The
   2:1–2.5:1 figure from drafting practice (ISO 129 dimension arrows) is a
   different animal: those are read at arm's length on paper, where a fine point
   is an asset. At glance distance a 2:1 head does not register as a head.
2. **Apex angle is 72–90°.** Material's 90° works because the head is an *open
   chevron* whose two arms are strokes; a filled 90° triangle reads as a blunt
   wedge. Mapbox, which fills its heads, uses 72–75°. This spec fills its heads,
   so it takes Mapbox's number.

## ★ The system — every number, in one table

All values are percent of the glyph box, 0–100, x right, y down. Every glyph
below obeys these; where one cannot, the glyph's own section says so and why.

| Symbol | Name | Value | At 84 px | At 96 px | At 104 px |
|---|---|---|---|---|---|
| `W` | **shaft width** — your path | **16** | 13.4 px | 15.4 px | 16.6 px |
| `Wt` | **thin width** — a road that is not your path | **10** | 8.4 px | 9.6 px | 10.4 px |
| `Hw` | **head width** (base of the triangle) | **52** | 43.7 px | 49.9 px | 54.1 px |
| `Hl` | **head length** (base to tip) | **34** | 28.6 px | 32.6 px | 35.4 px |
| `V` | **head/shaft overlap**, measured along the axis | **6** | 5.0 px | 5.8 px | 6.2 px |
| `M` | **margin** — no ink outside `[M, 100−M]` | **4** | 3.4 px | 3.8 px | 4.2 px |
| `D` | **OP_LINE width for a 45° stroke** = `W·√2` | **23** | — | — | — |
| `Dt` | **OP_LINE width for a 45° thin stroke** = `Wt·√2` | **14** | — | — | — |
| — | turn angles: slight / normal / sharp / U | **45 / 90 / 135 / 180** | | | |
| `Xe` | entry centreline, by turn angle 0/45/90/135/180 | **50 / 40 / 34 / 24 / 22** | | | |
| — | optical centre — **ink centroid**, not bounding box | **(50, 50) ± 8 in x, ± 6 in y** | | | |

Derived ratios, for the record: `Hw / W` = **3.25**, `Hl / Hw` = **0.654**,
apex angle **74.8°**, `W / Wt` = **1.6**.

`Xe` is graduated: the sharper the turn, the further left the entry leg starts,
because the exit needs the room. The progression is copied from Material
Symbols, whose stems sit at 50% (straight), 41.7% (slight), 33.3% (right),
29.2% (sharp) and 29.2% (U-turn) of its 960 grid. Ours runs further left at the
sharp end — 24 and 22 rather than 29 — because our reversal arcs are larger:
Material's glyph sits inside a 20-of-24 live area, ours fills the box, and the
entry leg of a hairpin is `arc centre − arc radius` by construction, not a free
choice.

## Stroke weight: why 16 and not 8

This is the one constant that cannot be copied from anywhere, because no
reference system is drawn for a 1.17:1 panel.

**The contrast.** `HARDWARE.md` computes ACR ≈ (250 + 1430) / 1430 = **1.17:1**
in 100 klx Bengaluru noon sun on a 4.5%-reflectance ILI9341. As Michelson
contrast that is (1680 − 1430) / (1680 + 1430) = **8.0%**.

**The angular scale.** `FEATURES.md` establishes 1 px ≈ **0.87 arc-min** at
700 mm on this panel (0.1778 mm pitch ÷ 700 mm). So 1 px = 0.0145°.

**The frequency argument.** A stroke of width *s* pixels against background of
its own width is a square-wave grating of period 2*s* px, i.e.

```
f = 1 / (2 · s · 0.0145)  cycles/degree  =  34.5 / s
```

Human contrast sensitivity peaks near 3–5 c/deg photopic and falls off steeply
on both sides; at 8% Michelson (sensitivity 12.5) the usable band collapses
toward the peak and toward *lower* frequencies, because veiling glare raises the
adaptation luminance and adds spatial noise. Taking 3 c/deg as the target:

| f (c/deg) | s (px) | as % of an 84 px box |
|---|---|---|
| 5 | 6.9 | 8.2% |
| **3** | **11.5** | **13.7%** |
| 2 | 17.3 | 20.5% |

**The ISO cross-check.** ISO 15008 gives a stroke-width-to-character-height
ratio of 1:6 to 1:12. Applied to the glyph's ink height (≈88% of the box = 74 px
at 84): 1:6 → 12.3 px = **14.7%**; 1:12 → 6.2 px = 7.3%. Contrast is short of
the 5:1 ISO 15008 wants by a factor of four, so take the **heavy end**: ~15%.

**The arc-minute cross-check.** `FEATURES.md` already tabulates ISO 15008's
feature sizes: 20 arc-min recommended, 16 acceptable, 12 minimum → 23 / 18 /
14 px. At `W` = 16 the shaft is 13.4 px = **11.7 arc-min at the 84 px box** —
sitting on the ISO minimum. At `W` = 12 it would be 10.1 px = 8.8 arc-min,
below it. At Material's 8.3% it would be 7.0 px = 6.1 arc-min, half the minimum.

**Conclusion: `W` = 16.** Three independent routes — the CSF band, the ISO
stroke ratio, the ISO feature size — land between 13.7% and 16%, and the box is
smallest and the light worst at 84 px, so the number is taken at the top of that
range. It is also, not coincidentally, exactly what `G_CONTINUE` already uses;
that glyph was judged on hardware and it was judged right.

**`Wt` = 10** is the only other weight in the system. At 8.4 px / 7.3 arc-min it
is deliberately below the ISO minimum, and is therefore used **only** where the
element is context the rider does not have to resolve — the branch not taken,
the highway being left, the lane joining, the water under the ferry. Nothing
that carries an instruction is ever drawn at `Wt`. The 1.6:1 ratio against `W`
is a 5 px difference at the 84 px box, comfortably above the ~1.2:1 needed for
reliable size discrimination, and it is always reinforced by a second cue —
the heavy stroke is the one with the arrowhead.

Two weights, not three. `FEATURES.md` already records why: *"solid fill vs thin
outline is the strongest channel; size is a good second; never dashed-vs-solid
or dithered grey."*

## Arrowhead geometry

Every head in this set is the same triangle: **base `Hw` = 52, height `Hl` = 34,
apex 74.8°**, tip first, and the shaft always ends `V` = 6 *inside* it.

Why 52 and 34 specifically:

- **52 sits in the reference range measured in absolute terms** — OsmAnd 45.8%,
  Mapbox 49.1–55.4%, Material 33.3%. Material is the outlier because a Material
  icon occupies a 20-of-24 live area; scaled to a full box its head is ~40%.
- **The ratio `Hw/W` = 3.25 is below every reference's ~4:1 solely because our
  shaft is heavier.** The head is not smaller; the shaft is fatter, for the
  measured contrast reason above. Holding 4:1 would demand a 64-wide head, which
  at the 90° turn would leave 36 of vertical box for the entire entry leg.
- **34 gives a 74.8° apex, which is Mapbox's 72–75.2° to within half a degree.**
  A filled triangle needs to be sharper than Material's 90° chevron to read as
  an arrow rather than a wedge, and blunter than a drafting arrowhead, whose
  ~19° point is the first thing glare erases.

The canonical head for each direction used in this set, as `OP_TRI` operands.
`(cx, ty)` is the tip.

| Direction | `OP_TRI` |
|---|---|
| up | `cx, ty, cx−26, ty+34, cx+26, ty+34` |
| right | `tx, cy, tx−34, cy−26, tx−34, cy+26` |
| down | `cx, ty, cx−26, ty−34, cx+26, ty−34` |
| up-right 45° | `tx, ty, tx−42, ty+6, tx−6, ty+42` |
| down-right 45° | `tx, ty, tx−42, ty−6, tx−6, ty−42` |

The 45° forms come out of `B = T − 34·û`, `B ± 26·n̂` with û = (1,∓1)/√2 and
n̂ = (1,±1)/√2, then rounded: 34/√2 = 24.04 → 24 and 26/√2 = 18.38 → 18, giving
offsets 24+18 = 42 and 24−18 = 6. Every 45° head therefore has a 42×42 bounding
box, which is what makes the diagonal glyphs place cleanly on integers.

**The two panel-validated heads already in the firmware are this triangle.**
`G_CONTINUE`'s head is `24,40 76,40 50,6` — base 52, length 34, exactly. `G_TURN`'s
is `96,53 62,28 62,79` — base 51, length 34, off by one unit. That is the
strongest evidence available that these constants are right: they were arrived
at here from three published systems, and they reproduce what was independently
judged correct on the panel.

## Turn angles

**Verified from OsmAnd's `TurnPathHelper.calcTurnPath`**, which passes the
drawing angle to `TurnVariables` literally:

| Maneuver | Line | Angle drawn |
|---|---|---|
| `TR` / `TL` | `new TurnVariables(..., b == 1 ? 90 : -90, ...)` | **90°** |
| `TSLR` / `TSLL` | `float angle = shortArrow ? 65 : 45;` | **45°** |
| `TSHR` / `TSHL` | `new TurnVariables(..., b == 1 ? 135 : -135, ...)` | **135°** |
| `TU` / `TRU` | `new TurnVariables(..., 180, ...)` | **180°** |

So 45 / 90 / 135 / 180 is not a convention someone assumes — it is a literal in
the source of a shipping navigation app. Mapbox agrees geometrically:
`mapbox_ic_turn_slight_right`'s diagonal runs (−8.34,3) → (0.99,−5.09), i.e.
atan(8.09/9.33) = **40.9°**, and its slight head axis is 40.8° — 45° with a
rounded transition eating a few degrees. Material Symbols'
`turn_slight_right` diagonal is (440,−496) → (640,−296): Δx = Δy = 200, exactly
**45°**.

For completeness, the *classification* thresholds OsmAnd uses to pick which
glyph to draw (`RouteResultPreparation.getTurnByAngle`) are 5° / `TURN_DEGREE_MIN`
/ 120° / 150°. Those are the phone's problem, not this display's — the firmware
is told which maneuver it is — but they confirm that "sharp" means ≥120° of
actual deviation, which is why it must be drawn as a genuine reversal.

**Material Symbols' `turn_sharp_right` is wrong and must not be copied.** Its
path is stem-up, jog-right, head-up: `M240-120v-240q0-33 23.5-56.5T320-440h320
v-248l-64 64-56-56 160-160 160 160-56 56-64-64v248q0 33-23.5 56.5T640-360H320
v240h-80`. The arrow ends pointing north — the same heading it started with.
That is a lane shift, not a 135° turn. Mapbox and OsmAnd both draw the reversal.
This spec follows Mapbox and OsmAnd.

## Optical centre

**Rule: the ink centroid — not the bounding box — lands at (50, 50), within ±8
in x and ±6 in y.**

Centroid rather than bbox because that is what "optically centred" means for a
shape with a heavy end: a right-pointing triangle centred by its bounding box
looks like it has slid left, which is the whole reason the play-button glyph is
nudged right in every UI kit ever shipped. OsmAnd does the same thing
mechanically — its `TurnVariables` constructor starts at `cx = wa/2; cy = ha/2`
and then translates by the minimum amount that keeps `radEndOfArrow` inside the
box.

The x tolerance is looser than y on purpose. A right-turn glyph *should* feel
right-of-centre; the direction is the message. Material's own `turn_right`
bounding box spans 29.2%–87.5% (centre 58.3%) and its `turn_slight_right` spans
37.5%–75% (centre 56.25%) of a 960 grid. Every glyph's computed centroid is
given in its section below.

Two anchors are fixed for the whole family, and they matter more than the
centroid:

- **The entry leg's foot is at y = 96**, the bottom margin, in every glyph that
  has one. That stub is "you, now". It is in the same place, at the same width,
  in every arrow, which is what lets a rider read the difference between two
  glyphs rather than each glyph from scratch.
- **The head's tip touches the margin in the direction of travel.**

## ★ The OP_LINE trap — and the reason the diagonals look thin

`OP_LINE` is documented as "stroke width e", and it is not. From
`maneuvers.cpp`:

```cpp
const int w = b.p(o->e);
for (int i = -w / 2; i <= w / 2; i++) tft.drawLine(x0 + i, y0, x1 + i, y1, fg);
```

The copies are offset **along x**. For a stroke at angle θ to the horizontal the
*perpendicular* width is therefore

```
w_perp = e · |sin θ|
```

At 45° that is `e / √2` = **0.707 e**. Every diagonal in the current glyph set
is written with `e = 15` to match the 15-wide rectangles beside it, and every
one of them actually draws **10.6** — a 30% thin stroke sitting next to a full
one. `G_SLIGHT`, `G_FORK`, `G_EXIT`, `G_SHARP` and `G_MERGE` all have it. It is
the single largest contributor to "inconsistent stroke weights", and it is
invisible in review because the number in the table says 15.

`tools/ascii_glyphs.pl` reproduces the same arithmetic (`line($x0+$_, ...) for
(-int($w/2) .. int($w/2))`), so the renderer will not catch it either — it is
faithful, not wrong.

**The fix in this spec:** every 45° stroke is written with `e = D = 23`, because
23 / √2 = 16.26, which is `W`. Thin 45° strokes use `e = Dt = 14` → 9.9 ≈ `Wt`.
**Every diagonal in this document is at exactly 45°**, so the compensation is
exact rather than approximate. Any future glyph at a different angle must
compute `e = W / sin θ` or use the new op below.

## One new op — proposed, and deliberately not required

`OP_STROKE  a,b -> c,d, width e` — a true perpendicular-width stroke.

```
û  = ((c−a), (d−b)) / L          L = hypot(c−a, d−b)
n̂  = (−û.y, û.x)
P0 = (a,b) + (e/2)·n̂    P1 = (a,b) − (e/2)·n̂
P2 = (c,d) + (e/2)·n̂    P3 = (c,d) − (e/2)·n̂
fillTriangle(P0,P1,P2);  fillTriangle(P1,P2,P3);
```

Five operands, so it fits `GlyphOp` unchanged, and it costs two `fillTriangle`
calls instead of a `drawLine` loop — cheaper at every box size in this project.

**It is not needed to ship this spec.** Every diagonal here is 45°, where
`e = W·√2` is exact. The op is specified so that the day someone wants a 30°
merge taper or a five-way roundabout stub, the answer is one op rather than a
trigonometry comment in a table. Adding it also lets the `√2` disappear from the
tables, which is the kind of thing that stays correct.


## The glyphs

Every table below has been rendered through `tools/ascii_glyphs.pl` at the 96 px
box. All fourteen report **"all glyphs stay inside the box"**; no glyph spills a
single pixel. Left variants are the same tables with `mirror = true` and were
rendered mirrored as well — `G_TURN`, `G_SLIGHT`, `G_SHARP`, `G_UTURN`, `G_FORK`
and `G_EXIT` all reflect exactly, because every rectangle's `x + w` and every
triangle's vertices are integers and the interpreter's `rectX` correction
handles the `fillRect` direction.

Centroids quoted per glyph are ink area centroids computed by hand, including
subtraction of the overlaps.

### CONTINUE — `MV_CONTINUE`

Shaft on the box axis, `W` wide, from the bottom margin to `V` inside the head.
Head tip on the top margin. There is no turn, so `Xe` = 50 and the glyph is
symmetric about x = 50.

```c
static const GlyphOp G_CONTINUE[] = {
  { OP_RECT, 42, 32, 16, 64,  0,  0 },   // shaft, foot on the bottom margin
  { OP_TRI,  50,  4, 24, 38, 76, 38 },   // head, tip on the top margin
  { OP_END,   0,  0,  0,  0,  0,  0 },
};
```

Shaft x 42–58 (`W` = 16, centred). Shaft top y = 32 = head base 38 − `V` 6.
Head 52 × 34. Centroid **(50.0, 47.3)**.

This is the existing glyph with the shaft two units taller and the tip two units
higher; the head is byte-identical. It was already right, and the system was
derived partly to explain *why* it was right rather than to replace it.

### TURN — `MV_TURN_RIGHT`, `MV_TURN_LEFT` (mirrored)

Pivot at (`Xe`, `Xe`) = (34, 34), which makes the entry leg and the exit arm the
same length, 96 − 34 = 62. Square corner: at 90° a rectangle pair is exact, and
Material Symbols' own corner radius here is one stroke width, which at 84 px is
13 px of rounding the panel's own pixel grid supplies for free.

```c
static const GlyphOp G_TURN[] = {
  { OP_RECT, 26, 34, 16, 62,  0,  0 },   // entry leg, foot on the bottom margin
  { OP_RECT, 26, 26, 42, 16,  0,  0 },   // exit arm, pivot to inside the head
  { OP_TRI,  96, 34, 62,  8, 62, 60 },   // head, tip on the right margin
  { OP_END,   0,  0,  0,  0,  0,  0 },
};
```

Entry leg x 26–42, y 34–96. Exit arm x 26–68, y 26–42; it ends at 68, `V` = 6
past the head base at 62. Head 52 × 34 centred on y = 34.
Ink bbox x 26–96, y 8–96. Centroid **(50.5, 46.5)**.

Bounding-box centre is x = 61, against Material's `turn_right` at 58.3% — the
glyph leans right, which is the instruction.

### SLIGHT — `MV_SLIGHT_RIGHT`, `MV_SLIGHT_LEFT` (mirrored)

45°, verified as OsmAnd's literal (`float angle = shortArrow ? 65 : 45`),
Material's exact Δx = Δy, and Mapbox's 40.9° with a rounded transition.

```c
static const GlyphOp G_SLIGHT[] = {
  { OP_RECT, 32, 55, 16, 41,  0,  0 },   // entry leg
  { OP_LINE, 43, 55, 70, 28, 23,  0 },   // 45 deg diagonal - e=23, NOT 16
  { OP_TRI,  88, 10, 46, 16, 82, 52 },   // head, 45 deg
  { OP_END,   0,  0,  0,  0,  0,  0 },
};
```

`Xe` = 40, leg x 32–48. Exit axis is x + y = 98; the head tip (88,10) and the
diagonal's two endpoints all satisfy it, which is the arithmetic check on this
glyph. Head base midpoint (64,34); the diagonal ends at (70,28), `V` = 6 further
along the axis, i.e. inside the head.

**The `OP_LINE` butt is at x = 43, not 40.** A 45° stroke of perpendicular width
16 has an x-extent of 22.6, so butting it on the leg's centreline would hang
3.3 units past the leg on both sides. Starting it at `Xe` + 3 puts the stroke's
left edge at 31.5 against the leg's 32 — flush to within half a unit, which is
0.4 px at the 84 px box. Every diagonal in this set uses the same `Xe` + 3
offset (`Xe` + 1 for a thin branch, where the half-extent is 7).

Centroid **(57.2, 46.5)**. Bbox centre x = 60 against Material's
`turn_slight_right` at 56.25%; a slight right that does not lean right is not
telling the rider anything.

### SHARP — `MV_SHARP_RIGHT`, `MV_SHARP_LEFT` (mirrored)

135°, drawn as a genuine reversal: up, round a hairpin, back down at 45°.

```c
static const GlyphOp G_SHARP[] = {
  { OP_RECT, 16, 40, 16, 56,  0,  0 },   // entry leg
  { OP_ARC,  42, 40, 18,  8,  0, 135 },  // the reversal - 135 deg of arc
  { OP_LINE, 55, 28, 72, 45, 23,  0 },   // exit, down-right at 45
  { OP_TRI,  92, 65, 50, 59, 86, 23 },   // head, down-right at 45
  { OP_END,   0,  0,  0,  0,  0,  0 },
};
```

**Why an arc and not two rectangles.** `OP_ARC` plots
(cx − r·cos t, cy − r·sin t); the tangent at t = 0 is straight up and at t = 135°
is down-right at 45°, so a single `0 → 135` sweep *is* the turn. The first draft
of this glyph used a square knee and it rendered as a solid triangular wedge
20 units tall — the inner corner filled in completely and the hairpin stopped
reading as a hairpin. With r = 18 and a dot radius of 8, the inner radius is
10, i.e. 8.4 px of open background at the 84 px box, and the reversal reads.
OsmAnd draws the same reversal with a much smaller radius (`widthStepIn / 2`
= 5.6% of its box) because its arrow does not fill the box; Mapbox uses a large
rounded hook. 18 is between them and is set by the "inner corner must stay
open" constraint above.

Arc start dot centre (24,40), radius 8 → x 16–32, exactly the entry leg. Arc end
(54.7, 27.3); the exit `OP_LINE` butts at (55,28), inside it. Exit axis is
x − y = 27: (55,28), (72,45) and the tip (92,65) all satisfy it.

Head base midpoint (68,41), diagonal ends at (72,45) — `V` = 6 inside.
Ink bbox x 16–96, y 14–96. Centroid **(48.5, 49.4)**.

**Material Symbols' `turn_sharp_right` was rejected**, for the reason given
under "Turn angles": it ends pointing north. Mapbox's is the model — its head
tip sits at (91%, 73%) of its box and points down-right at 47°; ours is at
(92%, 65%) pointing down-right at 45°.

### U-TURN — `MV_UTURN_RIGHT`, `MV_UTURN_LEFT` (mirrored)

180°. A semicircular arc joins two parallel legs; the exit leg carries a
down-pointing head.

```c
static const GlyphOp G_UTURN[] = {
  { OP_RECT, 14, 36, 16, 60,  0,  0 },   // entry leg, foot on the bottom margin
  { OP_ARC,  46, 36, 24,  8,  0, 180 },  // the turn itself
  { OP_RECT, 62, 36, 16, 28,  0,  0 },   // exit leg, stops inside the head
  { OP_TRI,  70, 92, 44, 58, 96, 58 },   // head, pointing down
  { OP_END,   0,  0,  0,  0,  0,  0 },
};
```

Arc centre (46,36), r = 24, dot radius 8 → stroke width 16 = `W`. The arc's
endpoints at t = 0 and t = 180 are (22,36) and (70,36), which are the two leg
centrelines, so the joints are exact by construction rather than by matching two
sets of hand-derived numbers.

**Leg separation is 2r = 48.** Mapbox's `mapbox_ic_uturn` puts its legs 13 apart
on a 32 grid = **40.6%**, arc radius 6.5 = **20.3%**. An earlier draft here used
r = 20 to match that exactly and it failed a different constraint: the head is
52 wide and centred on the exit leg, so its left corner lands at
`2r + Xe − 26`, and at r = 20 that left only **6 units** of background between
the head and the entry leg — 5 px at the 84 px box, which closes up under blur.
At r = 24 the clearance is 14 units / 12 px. The head is wider relative to the
box here than Mapbox's is relative to theirs, so the U has to open wider.

Head tip (70,92), base y = 58, x 44–96. Exit leg y 36–64, ending 6 past the base.
Ink bbox x 14–96, y 4–96. Centroid **(48.1, 49.6)**.

### FORK / KEEP — `MV_FORK_*`, `MV_KEEP_*` (left variants mirrored)

Both branches drawn, so the glyph says "the road divides" rather than "bear
right". The branch not taken is `Wt` and headless. The existing rationale in
`glyph_data.h` stands and is unchanged: weight and the presence of a head carry
the meaning, because at 1.17:1 a grey stroke is not distinguishable from a black
one.

```c
static const GlyphOp G_FORK[] = {
  { OP_RECT, 34, 62, 16, 34,  0,  0 },   // shared stem
  { OP_LINE, 43, 62, 14, 33, 14,  0 },   // branch not taken - thin, headless
  { OP_LINE, 45, 62, 72, 35, 23,  0 },   // branch taken
  { OP_TRI,  92, 15, 50, 21, 86, 57 },   // head, 45 deg - same head as SLIGHT
  { OP_END,   0,  0,  0,  0,  0,  0 },
};
```

Stem centreline 42, x 34–50, y 62–96. Both branches leave the split at 45°, in
opposite directions, so the fork is symmetric in angle and asymmetric only in
weight — which is exactly the information.

Butt offsets again: the taken branch starts at 45 (= 42 + 3) so its left edge
lands on the stem's left edge; the thin branch starts at 43 (= 42 + 1, since
`Dt` = 14 gives a 7-unit half-extent) so its right edge lands on the stem's
right edge at 50.

Taken axis x + y = 107; head tip (92,15) and diagonal end (72,35) satisfy it.
Head base midpoint (68,39), diagonal ends 6 past it.
Not-taken axis y − x = 19, from (43,62) to (14,33).
Ink bbox x 7–92, y 15–96. Centroid **(55.6, 49.3)**.

`FORK` and `KEEP` still share this artwork deliberately. That decision is
unchanged and the reasoning in `glyph_data.h` is still the right reasoning.

### EXIT / RAMP — `MV_EXIT_RIGHT`, `MV_EXIT_LEFT` (mirrored)

The road being left runs the full height at `Wt` and carries no head — it is
scenery. The ramp peels off it at 45° and carries the head.

```c
static const GlyphOp G_EXIT[] = {
  { OP_RECT, 30,  4, 10, 92,  0,  0 },   // the road you are leaving - thin
  { OP_LINE, 41, 73, 70, 44, 23,  0 },   // the ramp - full weight
  { OP_TRI,  90, 24, 48, 30, 84, 66 },   // head, 45 deg
  { OP_END,   0,  0,  0,  0,  0,  0 },
};
```

Road x 30–40, y 4–96, margin to margin. Ramp butt at x = 41 = 30 + 11.3 rounded,
so the ramp's left edge lands on the road's left edge and the ramp appears to
grow out of the road rather than to cross it.

Ramp axis is x + y = 114, and butt (41,73), end (70,44) and tip (90,24) all sum
to it. Head base midpoint (66,48); the ramp ends at (70,44), `V` = 6 past it.

The split is at y = 73, so 23 units of road continue below it. That is the whole
message of the glyph — the road goes on without you — and it is why the ramp
does not start at the top.

Ink bbox x 30–90, y 4–96. Centroid **(55.3, 47.5)**.



### MERGE — `MV_MERGE`

Your road runs straight through with the standard head; a lane joins it from the
lower left at 45°, drawn at `Wt` because you do not ride it.

```c
static const GlyphOp G_MERGE[] = {
  { OP_RECT, 50, 32, 16, 64,  0,  0 },   // your road
  { OP_TRI,  58,  4, 32, 38, 84, 38 },   // head
  { OP_LINE, 12, 96, 56, 52, 14,  0 },   // the lane joining from the left
  { OP_END,   0,  0,  0,  0,  0,  0 },
};
```

Your road is at centreline 58, not 50. That is deliberate: the joining lane is
~620 units of ink entirely on the left, and centring the shaft would put the
glyph's centroid at x = 36. Offsetting the shaft by 8 brings it to **51.7**.

Lane axis x + y = 108, from the bottom margin (12,96) to (56,52), which is
6 units inside your road's left edge at 50. The two diverge below y ≈ 64, which
is the junction; that is a real divergence and not a rasterisation crack — the
lane is genuinely a separate road below the merge point.

Ink bbox x 5–84, y 4–96. Centroid **(51.7, 54.1)**.

Material Symbols draws `merge` symmetrically, as a Y with two equal legs. That
is correct for a road atlas and wrong here: this display is telling one rider
what to do, and "the road you are on continues, something joins it" is a
different instruction from "two roads become one". The asymmetry is the message.

### ROUNDABOUT — `MV_ROUNDABOUT`, and the exit-numbered variants

Two tables, identical but for the exit stub, so that the ring does not jump
between frames when an exit number appears or disappears.

```c
// Ring plus entry. Drawn when an exit NUMBER is known; the digit replaces the
// exit stub, because "take the 3rd exit" with an arrow pointing right is a lie.
static const GlyphOp G_ROUNDABOUT[] = {
  { OP_RING, 32, 40, 26, 12,  0,  0 },
  { OP_RECT, 24, 56, 16, 40,  0,  0 },   // entry, from the bottom margin
  { OP_END,   0,  0,  0,  0,  0,  0 },
};

// Ring plus entry plus the generic exit stub. Used when no number is known.
static const GlyphOp G_ROUNDABOUT_EXIT[] = {
  { OP_RING, 32, 40, 26, 12,  0,  0 },
  { OP_RECT, 24, 56, 16, 40,  0,  0 },
  { OP_RECT, 52, 32, 16, 16,  0,  0 },   // exit stub, ring edge into the head
  { OP_TRI,  96, 40, 62, 14, 62, 66 },
  { OP_END,   0,  0,  0,  0,  0,  0 },
};
```

**Ring thickness is 12, not `W` = 16, and the reason is the hole.** `OP_RING`
draws radii `[r − t, r]`, so at r = 26 a 16-thick ring leaves an inner radius of
10 — a 20% white disc, 17 px at the 84 px box, and shrinking further as the
stroke bleeds. At t = 12 the inner radius is 14, a 28% disc = 23.5 px. The
enclosed white is what makes a ring read as a roundabout rather than as a blob;
it is the one place in this set where the shape, not the stroke, is the feature,
and it gets the thickness that keeps the shape.

**Ring diameter is 52 — the same as `Hw`.** An earlier draft used r = 24 with the
centre at (36,40), giving a 48-diameter ring beside a 52-wide head, and the
arrow visibly dominated the roundabout. Material's `roundabout_right` keeps its
ring larger than its head. Matching ring diameter to head width is the smallest
correction that stops the arrow winning.

Ring centre (32,40), outer 26 → x 6–58, y 14–66. Entry leg x 24–40, y 56–96,
overlapping the ring's lower edge by 10. Exit stub x 52–68 spans from inside the
ring to `V` = 6 inside the head base at 62.

Centroids: `G_ROUNDABOUT_EXIT` **(45.0, 46.8)**. `G_ROUNDABOUT` on its own is
**(32.0, 50.0)** — 18 left, and deliberately so: the digit is drawn where the
exit stub would have been and restores the balance.

**One change is needed in `maneuvers.cpp`.** The digit is currently placed at
`b.px(82), b.py(44)`, which was on the old ring's exit axis. It should be

```cpp
tft.drawString(n, b.px(78), b.py(40), (s >= 88) ? 4 : 2);
```

x = 78 puts the digit on the new exit axis; y = 40 is the new ring centre. At the
84 px box that is pixel 65.5, and a font-4 digit is ~18 px wide, so it spans
57–74 of 84 — clear of the ring's right edge at 48.7 px and clear of the box.

### FLYOVER and UNDERPASS — `MV_FLYOVER`, `MV_UNDERPASS`

The same drawing with the gap moved. Whichever road is broken is the one passing
underneath.

```c
static const GlyphOp G_FLYOVER[] = {
  { OP_RECT,     4, 48, 92, 16,  0,  0 },  // the crossing road
  { OP_RECT_BG, 34, 46, 32, 20,  0,  0 },  // ...broken where we pass over it
  { OP_RECT,    42, 32, 16, 64,  0,  0 },  // our road, continuous
  { OP_TRI,     50,  4, 24, 38, 76, 38 },
  { OP_END,      0,  0,  0,  0,  0,  0 },
};

static const GlyphOp G_UNDERPASS[] = {
  // Both segments run right up to the crossing bar rather than stopping short:
  // the road must vanish AT the bar, not a few percent before it, or the gap
  // reads as two unrelated stubs instead of one road passing beneath.
  { OP_RECT, 42, 32, 16, 16,  0,  0 },   // our road, above the crossing
  { OP_RECT, 42, 64, 16, 32,  0,  0 },   // ...and below it. Broken between
  { OP_TRI,  50,  4, 24, 38, 76, 38 },
  { OP_RECT,  4, 48, 92, 16,  0,  0 },   // the crossing road, continuous
  { OP_END,   0,  0,  0,  0,  0,  0 },
};
```

Our road is `G_CONTINUE` unchanged, which is the point: a flyover is a
continue-straight with depth information attached, and the rider should read the
arrow first and the depth second.

**The crossing bar is `W` = 16, not `Wt`.** This is the one exception to
"a road that is not your path is thin", and it is a legibility calculation, not
a taste one. In `G_UNDERPASS` the break in *our* road is exactly the bar's
thickness — that break is the entire message. At 16 the gap is 13.4 px at the
84 px box = 11.7 arc-min, on ISO 15008's 12 arc-min minimum. At `Wt` = 10 it
would be 8.4 px = 7.3 arc-min, below it, and the underpass would silently become
a continue-straight in sunlight. The crossing road here is a landmark, not an
alternative route, so the thin-stroke rule does not apply to it.

`OP_RECT_BG` in `G_FLYOVER` punches x 34–66, y 46–66 — 8 units of clear
background on each side of our 16-wide road, 6.7 px at 84 px, and 2 units of
vertical overshoot past the bar at each end so the punch cannot leave a hairline
of bar behind at any box size.

Centroids: `G_FLYOVER` **(50.0, 49.3)**. `G_UNDERPASS` **(50.0, 50.8)**.

`NAV_DATA.md`'s note still holds: Maps emits no flyover-specific icon, so these
codes can only arrive from a source with clearer semantics. They are drawn
because the protocol defines them.

### FERRY — `MV_FERRY`

Not an arrow, and that is the point. "Drive straight ahead" is not what a ferry
leg asks of the rider.

```c
static const GlyphOp G_FERRY[] = {
  { OP_TRI,  10, 44, 90, 44, 76, 66 },   // hull, upper half
  { OP_TRI,  10, 44, 76, 66, 24, 66 },   // hull, lower half
  { OP_RECT, 45, 10, 10, 34,  0,  0 },   // mast
  { OP_TRI,  55, 12, 84, 29, 55, 44 },   // sail
  { OP_RECT,  8, 76, 84, 10,  0,  0 },   // water
  { OP_END,   0,  0,  0,  0,  0,  0 },
};
```

The hull is one convex quadrilateral (10,44) (90,44) (76,66) (24,66) split on the
diagonal (10,44)–(76,66); splitting a convex quad on a diagonal tiles it exactly,
with no seam and no double-fill.

Deck 80 wide, keel 52, depth 22. Mast and water are both `Wt` — neither is a
path, and the hull's solid mass is what carries the glyph. Water sits 10 units
below the keel: the earlier draft had a 20-unit gap and the boat looked airborne.

A sailboat rather than a ro-ro silhouette on purpose. A modern ferry outline is a
box with a superstructure, and at 84 px through a visor a box with a
superstructure is a truck. The mast-and-sail triangle is the most
distinguishable "boat" primitive available at this size, and this glyph is never
confusable with anything else in the set because nothing else in the set is a
triangle over a trapezoid.

Ink bbox x 8–90, y 10–86. Centroid **(52.2, 54.6)**. Bottom-heavy, and exempt
from the ±6 rule for the obvious reason: a boat on water is bottom-heavy.

### DESTINATION — `MV_DESTINATION`

```c
static const GlyphOp G_DESTINATION[] = {
  { OP_RECT, 30, 12, 10, 84,  0,  0 },   // pole
  { OP_TRI,  88, 38, 40, 16, 40, 60 },   // pennant
  { OP_END,   0,  0,  0,  0,  0,  0 },
};
```

Pole at `Wt`; it is a flagpole, not a road. Pennant base 44 on the pole's right
edge, length 48 — deliberately *not* the standard head. A pennant is longer than
it is deep (ratio 1.09 here) whereas the maneuver head is deeper than it is long
(0.65); making them the same shape would have the destination flag read as a
right-turn arrow at a glance, which is the single worst confusion available in
this set.

Pole x 30–40, y 12–96. Pennant tip (88,38), base x = 40 from y 16 to 60.
Ink bbox x 30–88, y 12–96. Centroid **(46.7, 45.1)**.



## Compliance table

Every stroke in the set, and whether it is a system constant or a documented
exception. There are exactly two exceptions and both have arithmetic behind them.

| Glyph | strokes used | head | centroid | notes |
|---|---|---|---|---|
| `G_CONTINUE` | 16 | 52 × 34 up | (50.0, 47.3) | |
| `G_TURN` | 16, 16 | 52 × 34 right | (50.5, 46.5) | |
| `G_SLIGHT` | 16, 23→16 | 52 × 34 at 45° | (57.2, 46.5) | |
| `G_SHARP` | 16, arc 2×8=16, 23→16 | 52 × 34 at 45° | (48.5, 49.4) | |
| `G_UTURN` | 16, arc 2×8=16, 16 | 52 × 34 down | (48.1, 49.6) | |
| `G_FORK` | 16, 23→16, 14→10 | 52 × 34 at 45° | (55.6, 49.3) | |
| `G_EXIT` | 10, 23→16 | 52 × 34 at 45° | (55.3, 47.5) | |
| `G_MERGE` | 16, 14→10 | 52 × 34 up | (51.7, 54.1) | shaft offset +8 to balance the lane |
| `G_ROUNDABOUT_EXIT` | ring 12, 16, 16 | 52 × 34 right | (45.0, 46.8) | **ring 12** — see below |
| `G_ROUNDABOUT` | ring 12, 16 | — | (32.0, 50.0) | digit supplies the right-hand mass |
| `G_FLYOVER` | 16, 16 | 52 × 34 up | (50.0, 49.3) | **bar 16** — see below |
| `G_UNDERPASS` | 16, 16 | 52 × 34 up | (50.0, 50.8) | **bar 16** — see below |
| `G_FERRY` | 10, 10 | — | (52.2, 54.6) | pictogram, exempt from the y tolerance |
| `G_DESTINATION` | 10 | pennant 44 × 48 | (46.7, 45.1) | pennant is deliberately not the head |

`23→16` and `14→10` mean an `OP_LINE` operand of 23 or 14, which draws a
perpendicular width of 16 or 10 at 45°. See "The OP_LINE trap".

**Exception 1 — the roundabout ring is 12, not 16.** At r = 26 a 16-thick ring
leaves a 20% white disc; the enclosed white is the feature, so the stroke yields.

**Exception 2 — the flyover/underpass crossing bar is 16, not 10.** The break in
our road equals the bar's thickness, and that break is the instruction. At 10 it
would be 7.3 arc-min at the 84 px box, below the ISO 15008 minimum.

## Verification performed

```
$ perl tools/ascii_glyphs.pl
... 20 glyph renders, including all six mirrored variants ...
all glyphs stay inside the box
```

What was checked, and how:

1. **Nothing leaves the box.** `ascii_glyphs.pl` counts ink outside 0–100 and
   exits non-zero if any exists. It reports zero for all fourteen tables and all
   six mirrored variants. Minimum ink coordinate across the set is 4
   (`G_UTURN` arc top, `G_EXIT` road top, `G_FLYOVER` bar); maximum is 96.
2. **Every arrowhead is attached to its shaft.** Each diagonal glyph has an
   axis equation (x + y = k or x − y = k) that the butt, the shaft end, the head
   base midpoint and the tip all satisfy; those are listed per glyph above.
   The orthogonal glyphs were checked by the shaft end exceeding the head base
   by exactly `V` = 6.
3. **Mirrors are exact.** Rendered mirrored and compared. Every rectangle here
   has integer `x` and `x + w`, so `rectX`'s `100 − x − w` is exact; every
   triangle vertex and arc centre reflects about 50 exactly. No mirrored glyph
   shifts by its own width, which is the failure mode `rectX` exists to prevent.
4. **The two panel-validated heads survive.** `G_CONTINUE`'s head is unchanged
   from the version judged correct on hardware; `G_TURN`'s moves by one unit in
   one vertex.

What was **not** checked, and must be before this is called done:

- **It has not been looked at on the panel.** Everything above is arithmetic and
  a 96 px ASCII raster. `maneuvers.cpp`'s own header says every layout bug this
  project has shipped was arithmetic found by squinting at hardware. Render the
  SVG contact sheet with `tools/render_glyphs.pl`, then put it on the display at
  84, 96 and 104 and look at it from 700 mm.
- **It has not been looked at in sunlight**, which is the whole reason `W` = 16
  rather than 8. The sunlight gate is unresolved for the project generally; this
  spec is drawn to survive it, not to prove it.

## What changes in the firmware

1. Replace the fourteen `GlyphOp` tables in `firmware/navigator/glyph_data.h`
   with the tables above. `GLYPHS[]` is unchanged — same codes, same `mirror`
   flags, same sharing of `G_FORK` between `FORK` and `KEEP`.
2. One line in `maneuvers.cpp`: the roundabout digit moves from
   `b.px(82), b.py(44)` to `b.px(78), b.py(40)`.
3. Nothing else. No new op is required, no interpreter change, no display
   change. `OP_STROKE` above is offered for later and is not part of this spec.

The header comment in `glyph_data.h` should gain one paragraph recording the
`OP_LINE` perpendicular-width rule, because it is the single trap most likely to
be re-introduced by the next person who adds a diagonal:

```
  DIAGONALS. OP_LINE offsets its copies along x, so a stroke at angle t to the
  horizontal has a PERPENDICULAR width of e*|sin t|, not e. Every diagonal in
  this file is at exactly 45 degrees and is therefore written with e = 23 for a
  16-wide stroke and e = 14 for a 10-wide one. Writing e = 16 draws an 11-wide
  stroke, which is what the previous set did, on every diagonal, silently.
```

