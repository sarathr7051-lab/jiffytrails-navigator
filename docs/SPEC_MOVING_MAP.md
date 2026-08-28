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
| 2 | Tile format on the phone | **MBTiles.** There is no maintained Java/Kotlin PMTiles reader in 2026 — the one that existed is archived — and PMTiles' only real advantage is build-time. | §2.1 |
| 3 | Extract | `planetiler` over the Geofabrik `southern-zone` PBF, `--bounds` to the Bengaluru metro box, z12–z14, **roads-only custom profile**. | §2.2 |
| 4 | MVT decoder | `no.ecc.vectortile:vector-tile-java` + JTS. | §2.3 |
| 5 | Simplification | RDP at **3 m**, after clipping, in the rider-local metric frame. | §2.4 |
| 6 | Classes kept | motorway, trunk, primary, secondary, tertiary and their `_link`s; plus whatever way the rider is snapped to. | §2.5 |
| 7 | Position | `FusedLocationProviderClient`, `PRIORITY_HIGH_ACCURACY`, 1000 ms. | §3.1 |
| 8 | Heading | `Location.getBearing()` — course over ground. Frozen below 2.8 m/s. **Never** the compass. | §3.2 |
| 9 | Wire | `0x09 GEOM` fragmented into ≤182-byte notifications behind a 4-byte fragment header; `0x0A POSE` at 4 Hz; `0x0B TILE`; `0x0C TILEACK` device→phone. | §4 |
| 10 | Motion | **Both, layered.** Windows step at 0.33–1 Hz; the ESP32 dead-reckons between them but repaints only when accumulated motion exceeds **4 px** or heading exceeds **3°**. | §5 |
| 11 | Device cache | 3x3 grid of 256 m cells, **5,868 B**, evicted **geometrically** by distance from the anchor, reconciled by a `u32 tileKey` the device reports in full every time it changes. 3x3 is provably sufficient with 22.8 m to spare. | §6 |
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

### 2.1 Tile format — **MBTiles**, and the research reversed the earlier lean

`ARCH_ANDROID_AUTO.md` §2.2 recommended MBTiles but flagged PMTiles Java support
as **unknown**. `ARCH_OWN_NAV_APP.md` §2.2 then argued the unknown *"no longer
matters if MapLibre is the renderer"*. **It matters here**, because in this
design nothing renders the tile — the app decodes MVT by hand and emits line
segments. So the unknown had to be settled. It now is:

| Reader | Finding |
|---|---|
| `protomaps/PMTiles` official implementations | **JS, C++, Python, Go, OpenLayers. No Java, no Kotlin.** [verified — repo tree, 28 Aug 2026] |
| `tileverse-io/tileverse-pmtiles` | Java 17+, v1.0.0 released 3 Oct 2025, **repository `archived: true`**, 2 stars. [verified — GitHub API] |
| `tmizu23/PMTiles-Java-ObjectiveC` | Author's own description: *"conversion may not be complete, and caution is advised"*. Last push Mar 2023. [verified] |

There is no maintained Java PMTiles reader in 2026. The remaining option is
writing one — PMTiles v3 is genuinely small (a 127-byte fixed header, varint
directories, Hilbert-ordered tile IDs; [spec](https://github.com/protomaps/PMTiles/blob/main/spec/v3/spec.md))
and ~250 Kotlin lines would
do it.

**Do not.** Compare the two at the only moment that matters, the runtime lookup:

| | MBTiles | PMTiles |
|---|---|---|
| Lookup | one `SELECT` on a `(zoom_level, tile_column, tile_row)` index | header read → root directory decode → possibly a leaf directory decode → range read |
| Code to write | **zero** — `android.database.sqlite` is in the platform | ~250 lines, hand-verified against a spec, or an archived third-party jar |
| Gotcha | rows are **TMS**, so `tile_row = 2^z − 1 − y_xyz` | Hilbert curve ordering, clustered/deduplicated tile data |
| Real advantage | none at runtime | one file; `pmtiles extract` cuts a bbox out of a *remote* archive without downloading it |

The runtime lookup, in full — this is the whole of the "hard part":

```kotlin
// MBTiles 1.3: CREATE TABLE tiles (zoom_level integer, tile_column integer,
//                                  tile_row integer, tile_data blob);
// "in the TMS tiling scheme, the Y axis is reversed from the XYZ coordinate
//  system commonly used in the URLs"  -- spec, verbatim   [verified]
val tmsRow = (1 shl z) - 1 - y
db.rawQuery(
  "SELECT tile_data FROM tiles WHERE zoom_level=? AND tile_column=? AND tile_row=?",
  arrayOf(z.toString(), x.toString(), tmsRow.toString())
).use { c -> if (c.moveToFirst()) gunzip(c.getBlob(0)) else null }
```

The spec's own worked example — *"`tile_row` 1256, since 1256 is 2^11 − 1 − 791"*
**[verified, MBTiles 1.3 spec]** — is the test case for this line, and it should be
a unit test, because the y-flip is the single most common way to build a map that
is correct everywhere except mirrored about the equator.

PMTiles' genuine advantage is **build-time distribution over HTTP range reads**,
and this archive is generated once on a desktop and copied to the phone. It buys
nothing and costs a hand-written binary parser sitting between the rider and the
road ahead. **MBTiles.**

*(This is not a cost argument — cost is explicitly not a constraint on this
project. It is a correctness argument: the failure mode of a hand-written
directory decoder is a silently wrong tile, and a silently wrong tile is a
confidently wrong drawing, which §0 of every document in this repo refuses.)*

### 2.2 Producing the extract

**Tool: `planetiler`** (Apache-2.0). Flags **[verified — `PlanetilerConfig.java`
and `PLANET.md`, `main` branch]**: `--osm-path`, `--output`, `--bounds`,
`--minzoom`, `--maxzoom`, `--polygon`, `--force`, `--download`.

Geofabrik publishes no Karnataka extract; the containing region is
`asia/india/southern-zone` at **531 MB** `.osm.pbf` **[verified,
`ARCH_OWN_NAV_APP.md` §2.2]**.

```sh
# once, on the desktop
wget https://download.geofabrik.de/asia/india/southern-zone-latest.osm.pbf

java -Xmx4g -jar planetiler.jar \
  --osm-path=southern-zone-latest.osm.pbf \
  --output=blr-roads.mbtiles \
  --bounds=77.40,12.80,77.85,13.20 \
  --minzoom=14 --maxzoom=14 \
  --force
```

**z14 only.** This archive exists to answer one question — *which roads are within
233 m of this point* — and only z14 is ever read (§2.3). If Phase 1 of
`ARCH_OWN_NAV_APP.md` §6 later wants a map view on the phone screen, that is a
**second, separate, full-schema archive**, generated by the same tool with
`--minzoom=8 --maxzoom=14` and the default OpenMapTiles profile. Do not conflate
them: this one is tuned for a 240 m query at 4 Hz, that one for a pinch-zoom.

`--bounds` takes `minlon,minlat,maxlon,maxlat`. The bbox is the one every
measurement in this repo already uses.

**Tile counts, verified arithmetic** (`ARCH_OWN_NAV_APP.md` §2.2, independently
recomputed here and agreeing to the tile):

| Zoom | x range | y range | Tiles |
|---|---|---|---:|
| 12 | 2928–2933 | 1896–1901 | 36 |
| 13 | 5857–5867 | 3792–3802 | 121 |
| 14 | 11714–11735 | 7585–7604 | **440** |

At the measured mean of 57,452 B per Bengaluru z14 tile that is **~35 MB** for a
full OpenMapTiles-schema archive **[computed from verified measurements]**.

**Then cut it down, because 90% of those bytes are never read.** A full OMT tile
carries `water`, `landuse`, `building`, `poi`, `place`, `boundary`,
`transportation_name` and more. This design reads exactly one layer with six
fields. Write a **planetiler custom profile** (the YAML `planetiler-custommap`
form is sufficient) emitting a single `roads` layer:

```yaml
layers:
  - id: roads
    features:
      - source: osm
        geometry: line
        min_zoom: 14
        include_when:
          highway: [motorway, motorway_link, trunk, trunk_link,
                    primary, primary_link, secondary, secondary_link,
                    tertiary, tertiary_link]
        attributes:
          - key: class
          - key: layer          # THE FLYOVER BIT
          - key: brunnel        # bridge / tunnel / ford
          - key: oneway
          - key: ramp
          - key: name
```

Expected result **~8–14 MB for the 440 tiles [inferred — the transportation
layer is roughly a third of an OMT tile and this keeps only five of its
thirteen classes; not measured, and measuring it is one `planetiler` run]**.

Scaling to all of Karnataka: `ARCH_OWN_NAV_APP.md` §2.2 estimated 120–160 MB for
the *full* schema; a roads-only cut lands near **40–60 MB [inferred]**. Ship the
Bengaluru box; keep Karnataka as a menu option.

**Attribution.** ODbL for OSM, CC-BY for the OpenMapTiles schema decisions. One
About-screen line satisfies both. Already established, `ARCH_OWN_NAV_APP.md` §2.2.

### 2.3 Decoding MVT on Android

**Library: `no.ecc.vectortile:java-vector-tile:1.4.1`** (Apache-2.0, 209 stars,
last pushed 15 Jan 2025 — **alive** [verified, GitHub API]). It is *not* on Maven
Central; add the vendor repo **[verified — project README]**:

```gradle
repositories { maven { url = uri("https://maven.ecc.no/releases") } }
dependencies { implementation("no.ecc.vectortile:java-vector-tile:1.4.1") }
```

Use `VectorTileDecoder`. It returns JTS `LineString`s in tile-local integer
coordinates plus the attribute map.

**Fallback, named:** `com.wdtinc:mapbox-vector-tile:3.1.0` — on Maven Central,
but last published 12 Apr 2019 **[verified — Maven Central metadata]**. Take it
only if the ECC repo becomes unreachable.

**It drags in JTS (LocationTech, ~1.5 MB).** That is acceptable on an S24+ and
R8 strips most of it, but note what is *not* used: no JTS geometry ops in the
hot path. Clipping and simplification (§2.4) run in a rider-local metric frame
on `FloatArray`s, because JTS's `Coordinate` objects would allocate ~600 objects
per window at 1 Hz and that is a GC pause on a foreground service.

**Geometry maths, all [verified] from `ARCH_ANDROID_AUTO.md` §2.2 and
recomputed:**

```
z14 tile span at 13 N = 40,075,016 * cos(13 deg) / 2^14 = 2,382.4 m
MVT extent 4096       -> 0.5816 m per tile unit
240 m window          -> 412.7 tile units
```

The source quantisation is **4x finer than the display's 1.25 m/px** (§1.2), so
nothing is lost by working in integers throughout.

**Decode cost and cadence.** A z14 tile is 2.38 km across. At 50 km/h the rider
crosses one every **171 s** [computed]. Even at the full-schema 57 kB and a
10–30 ms decode **[inferred, `ARCH_ANDROID_AUTO.md` §2.2]**, that is ~0.02% duty.
Keep a 9-entry LRU of *decoded* tiles (current + 8 neighbours) so a boundary
crossing never blocks the 1 Hz window build.

### 2.4 The window query

Runs once per position fix. Input: `(lat, lon, bearing)`. Output: the argument
list for `geomBegin`/`geomWay`/`geomPt`.

**1. Rider-local frame.** Equirectangular about the fix — exact enough at
±200 m, and it is two multiplications:

```
mPerDegLat = 110574.0                       // WGS84 at 13 N, [verified: standard]
mPerDegLon = 111320.0 * cos(lat)  = 108,463 m at 13.0 N   [computed]

east  = (lon - lon0) * mPerDegLon
north = (lat - lat0) * mPerDegLat

x =  east * cos(brg) - north * sin(brg)     // right of the rider, metres
y =  east * sin(brg) + north * cos(brg)     // ahead of the rider, metres
```

(`brg` is the compass bearing in radians; this is a rotation by −brg written out.)

**2. Clip to the window, not to the box.** The transmitted window is larger than
what §1.2 displays, and deliberately so — the surplus is what the ESP32
dead-reckons into (§5).

```
window:    x in [-120, +120]   y in [-40, +200]     = 240 m x 240 m
displayed: x in [ -60,  +60]   y in [-15, +105]     (96 px box, 1.25 m/px)
forward margin = 200 - 105 = 95 m
             -> 95 / 13.9 m/s = 6.8 s of dead reckoning before the top of the
                box runs out of geometry at 50 km/h            [computed]
```

Clip with Liang–Barsky per segment. A way clipped into two pieces becomes two
ways on the wire; `GeomWay` has no notion of a hole and must not be given one.

**3. Simplify — RDP, two tolerances.** `ARCH_ANDROID_AUTO.md` §2.2 said 3 m flat.
Refine it, because 3 m is 2.4 px at the display scale and that is visible on a
96 px box:

| Ways | Tolerance | Rationale |
|---|---|---|
| The way the rider is snapped to, and any way within 40 m of the rider | **1.5 m** (1.2 px) | Sub-pixel. This is the shape being decided on. |
| Everything else in the window | **4.0 m** (3.2 px) | Context, not decision. Halves the vertex count. |

Applied **after** clipping and **in the rider frame**, so the tolerance is in
real metres rather than in tile units that shrink with latitude.

Expected outcome 60–150 vertices across 10–40 ways, which is exactly what
`GEOM_MAX_PTS = 150` / `GEOM_MAX_WAYS = 40` were sized for **[verified,
`geom.h`]**. If the budget is still exceeded (a six-way flyover interchange
will do it), **drop by class ascending, never by truncating a way** — a way cut
short is a road that stops in mid-air, which is a lie. §4.1 specifies the
`TRUNCATED` flag that tells the device this happened.

**4. Layer.** Pass OSM `layer` through, clamped to `[-2, +2]` — the range
`geomDraw` iterates **[verified, `geom.cpp`]**. Where `layer` is absent but
`brunnel=bridge`, synthesise `layer = +1`; `brunnel=tunnel` → `layer = -1`. This
matters: it is the whole flyover disambiguation, and OSM taggers frequently set
`bridge=yes` without an explicit `layer`.

### 2.5 Which `class` values survive

OpenMapTiles `transportation` layer, all values **[verified —
`layers/transportation/transportation.yaml`, `master`, fetched 28 Aug 2026]**.

| `class` | Verdict at 1.25 m/px in a 96 px box |
|---|---|
| `motorway` | **keep** — thick |
| `trunk` | **keep** — thick |
| `primary` | **keep** — thick |
| `secondary` | **keep** — thin |
| `tertiary` | **keep** — thin |
| `minor` (unclassified, residential, living_street, road) | **drop.** Bengaluru residential density would fill the box with a grey mesh and bury the junction. The one exception is §2.4's snap rule: if the rider is *on* a minor road, that single way is kept. |
| `path`, `track`, `raceway`, `busway`, `bus_guideway` | **drop** — not rideable decisions |
| `service` | **drop** — but see the note below, this one is contentious |
| `ferry` | **drop** |
| `*_construction` (9 values) | **drop.** A road that does not exist yet drawn as a road is the worst possible error class. |
| `rail` and rail subclasses | **drop** — a level crossing is not a turn |

**The `service` argument, and why it loses.** `ARCH_ANDROID_AUTO.md` §2.2 frames
the flyover problem as *"take the flyover, not the service road under it"* — so
dropping `class=service` looks like dropping the exact thing the feature exists
to disambiguate. It is not. In OSM a Bengaluru flyover's parallel ground-level
carriageway is almost always tagged `highway=primary`/`secondary` with
`layer=0`, not `highway=service`; `class=service` is driveways, parking aisles
and alleys (the `service` field enumerates exactly that **[verified, schema]**).
The flyover case is a `layer` distinction between two *arterial* ways, and both
are kept. **[inferred — this should be spot-checked with one Overpass query
against three named Bengaluru flyovers before the filter ships. §10.]**

`ramp=1` is kept as a *flag*, not a class: a slip road is drawn thin regardless
of its parent class, because at 120 m a ramp reads as a branch, not a highway.

---

## 3. Position and heading

### 3.1 Source and rate

**`FusedLocationProviderClient`, not `LocationManager.GPS_PROVIDER`.** Fused is
correct here for a reason specific to this use, not out of habit: it delivers
GNSS + WiFi + cell + the phone's own step/motion sensors, and the failure this
design most needs to survive is a **flyover underpass or an underground stretch
of the ORR**, where raw GPS drops and fused coasts on sensors for several
seconds. Coasting is exactly what §5 wants.

```kotlin
val req = LocationRequest.Builder(Priority.PRIORITY_HIGH_ACCURACY, 1000L)
    .setMinUpdateIntervalMillis(500L)     // accept faster fixes if offered
    .setMaxUpdateDelayMillis(0L)          // no batching — latency is the point
    .setWaitForAccurateLocation(false)    // a coarse fix now beats a good one late
    .setGranularity(Granularity.GRANULARITY_FINE)
    .build()

fused.requestLocationUpdates(req, callback, Looper.getMainLooper())
```

**1 Hz, not faster.** The window is 240 m and the display steps (§5); a 4 Hz
location stream would produce four windows the rider cannot tell apart and cost
GNSS power for nothing. The 4 Hz stream that *does* exist is `0x0A POSE` (§4.3),
and it is generated by *extrapolating* the 1 Hz fix, not by asking for more fixes.

**Manifest and permissions** (Android 16 on the S24+):

```xml
<uses-permission android:name="android.permission.ACCESS_FINE_LOCATION"/>
<uses-permission android:name="android.permission.FOREGROUND_SERVICE_LOCATION"/>
<service android:name=".NavService"
         android:foregroundServiceType="location|connectedDevice"/>
```

No `ACCESS_BACKGROUND_LOCATION` — the service is foreground for the whole ride
because it already is, for BLE. `ARCH_ANDROID_AUTO.md` §2.2 already records this
as the cost of the whole approach: *"Today's notification listener needs no
location permission at all."*

### 3.2 Heading — course over ground, and nothing else

**Settled, not re-argued.** `ARCH_OWN_NAV_APP.md` §7.2 disqualified the compass:
a handlebar-mounted phone *"measures **steering input** on top of chassis
motion"*, and its magnetometer sits next to the ignition coil. A heading-up map
slaved to it **would rotate when the rider countersteers**. `TYPE_ROTATION_VECTOR`
is not read by this feature, at all, for any purpose.

`Location.getBearing()` is derived from the velocity vector, so it is the
vehicle's heading and immune to both handlebar angle and magnetic distortion.

**The gate. All three conditions, every fix:**

```kotlin
val usable = loc.hasBearing()
          && loc.hasSpeed() && loc.speed >= 2.8f            // 10.1 km/h
          && (Build.VERSION.SDK_INT < 26 ||
              loc.bearingAccuracyDegrees in 0f..25f)        // API 26+
```

Gate on **accuracy and speed together**, not speed alone: at a signal on an
uphill start the speed can cross 2.8 m/s while `bearingAccuracyDegrees` is still
60°, and that produces exactly one frame of a map rotated 60° wrong — which is
the single most dangerous artefact this whole design can emit.

| Condition | Behaviour |
|---|---|
| `usable` | Adopt the smoothed COG (§3.3). Send windows normally. |
| `!usable`, moving < 20 s | **Freeze heading at the last good value.** Keep sending windows — the position is still advancing, so the picture is still true; only the rotation is held. |
| `!usable`, stopped > 20 s | **Stop sending windows.** `GEOM_MAX_AGE_MS = 6000` then blanks the box and the arrow returns. §8. |

Freezing rather than falling back is the whole rule. `NAV_DATA.md` records the
stationary symptom already: *"while stationary at a traffic signal the distance
drifted 30 → 40 → 50 m from GPS jitter alone"* — a bearing computed from that
same jitter spins freely, and a spinning map is worse than a frozen one and far
worse than none.

### 3.3 Smoothing

**Heading. Smooth the unit vector, never the angle.** Averaging degrees across
the 359°/0° wrap produces a 180° flip, and it will happen on the first
north-bound ride.

```kotlin
// u = (cos b, sin b) from the new bearing; v = the filter state
val alpha = 1.0 - exp(-dtSec / TAU)        // TAU = 0.6 s
vx = (1 - alpha) * vx + alpha * cos(b)
vy = (1 - alpha) * vy + alpha * sin(b)
heading = atan2(vy, vx)
```

τ = 0.6 s gives α ≈ **0.81** at a 1 Hz fix rate [computed] — light smoothing that
removes single-sample noise without adding a visible lag. A τ large enough to
feel smooth would put the map behind the bike at a junction, which is the one
place it must not be.

**Then rate-limit, on physics.** A motorcycle's yaw rate is bounded by its
lateral grip: `ω_max = a_lat / v`, with `a_lat ≈ 8 m/s²` for a road tyre in the
dry.

| Speed | `ω_max` |
|---|---|
| 50 km/h (13.9 m/s) | 0.58 rad/s = **33 °/s** |
| 30 km/h (8.3 m/s) | 0.96 rad/s = **55 °/s** |
| 15 km/h (4.2 m/s) | 1.92 rad/s = **110 °/s**, clamp at 90 |

[computed] Clamp the per-fix heading change to `min(90, 458/v_kmh) °/s × Δt`.
A jump larger than that is not a turn, it is a bad fix, and it must not reach
the display.

**Position: do not smooth. Snap.** A low-pass on lat/lon adds lag exactly where
lag is a lie about where the bike is. Instead, lateral map-matching against the
geometry the app already has decoded:

> Take the kept ways within **15 m** of the fix. If **exactly one** has a
> tangent within **30°** of the smoothed heading, move the window origin to the
> perpendicular foot of the fix on that way. Otherwise use the raw fix unchanged.

This removes the "rider dot floating in a field beside the road" artefact, which
is 100% of the perceived inaccuracy at this scale, and it refuses to guess when
two parallel candidates exist — which is precisely the flyover-over-service-road
case, where guessing wrong would be catastrophic. **[inferred design.]** It is a
strict subset of the full map-matching in Phase 3 of `ARCH_OWN_NAV_APP.md` §6,
and it is worth having before that phase lands.

### 3.4 API summary

| Need | API | Note |
|---|---|---|
| Fixes | `com.google.android.gms.location.FusedLocationProviderClient` | Play Services |
| Request | `LocationRequest.Builder(Priority.PRIORITY_HIGH_ACCURACY, 1000)` | `Priority`, not the deprecated int constants |
| Heading | `Location.getBearing()` / `hasBearing()` | degrees, 0 = true north, clockwise |
| Heading quality | `Location.getBearingAccuracyDegrees()` | **API 26+** — guard it |
| Speed | `Location.getSpeed()` / `hasSpeed()` / `getSpeedAccuracyMetersPerSecond()` | m/s; accuracy is API 26+ |
| Fix age | `Location.getElapsedRealtimeNanos()` | Use this, **not** `getTime()` — monotonic, immune to clock changes and to a stale system time after a phone reboot |
| Test injection | `FusedLocationProviderClient.setMockMode(true)` + `setMockLocation()` | §9.3 |
| Compass | — | **deliberately absent** |

---

## 4. The wire format

### 4.0 One refinement first: separate the points from the pose

`geom.h` today stores **rider-frame** points and re-rotates nothing:

> *"sends line segments already rotated into the rider's frame … Rotating on the
> phone rather than here is deliberate — the phone knows the heading, and a
> heading the device guessed would be a confidently wrong drawing."*

**Keep the principle, change the storage.** The principle is *the device never
derives a heading from anything it senses* — and it stays absolutely true,
because the ESP32 senses nothing: no IMU, no magnetometer, no GNSS. What
changes is that the point store becomes **grid-frame** (north-up) and the pose
becomes a separate, phone-supplied value:

```c
void geomPose(int16_t rider_x_dm, int16_t rider_y_dm,
              uint16_t heading_cdeg, uint16_t speed_cm_s, int16_t yaw_cds);
```

`geomDraw` then applies one rotation to the stored points. This is not a
philosophical retreat, it is what makes §5 and §6 possible at all: **the same
cached geometry has to be drawable at many different headings**, and it cannot
be if the heading is baked into the stored coordinates. A cache of pre-rotated
points is a cache that must be discarded every time the bike turns.

Cost of the change on the device: one `sincosf` per frame plus 4 multiplies and
2 adds per point — 150 points is **~600 multiply-adds, well under 0.5 ms**
**[computed; consistent with `ARCH_OWN_NAV_APP.md` §7.3]**.

**The grid.** A rigid 256 m metric lattice, defined identically on both sides:

```
LAT_REF   = 13.00 deg            // fixed for the whole extract, NOT the fix
M_PER_DEG_LAT = 110574.0
M_PER_DEG_LON = 111320.0 * cos(LAT_REF) = 108,463.0

east_m  = lon * M_PER_DEG_LON
north_m = lat * M_PER_DEG_LAT
gx = floor(east_m  / 256)        // 32,793 .. 32,983 over the project bbox
gy = floor(north_m / 256)        //  5,528 ..  5,701
tileKey = (uint32)gy << 16 | (uint32)gx
```

**Why a fixed reference latitude and not the fix's own.** `cos(lat)` varies by
0.16% across the bbox's 0.4° of latitude, which is **0.4 m over a 256 m cell**
[computed] — six times finer than the 1.25 m/px display and, crucially,
*constant*, so a cell computed at the north edge of the box and one computed at
the south edge are the same cell. A per-fix `cos(lat)` would make the lattice
breathe and cached tiles would stop lining up.

`tileKey` values collide only 16,777 km apart. Fine.

All coordinates on the wire are **decimetres, `int16`, ±3,276.7 m** — the range
`geom.h` already documents, and ample for a 3x3 grid of 256 m cells.

### 4.1 Fragmentation — one sub-layer, shared by `0x09` and `0x0B`

The outer framing is unchanged from `BLE_PROTOCOL.md`: `[type:u8][len:u8][payload…]`,
little-endian, `len` excludes the header.

```
ATT MTU 185  ->  182-byte ATT payload            [given]
minus 2 bytes of type/len framing                = 180
minus 3 bytes of fragment header                 = 177 bytes of chunk
```

**Fragment header, 3 bytes, on every fragment of `0x09` and `0x0B`:**

| Field | Type | Meaning |
|---|---|---|
| `seq` | `u8` | Transfer sequence. Same on every fragment of one transfer. Increments per transfer, wraps at 256. |
| `frag` | `u8` | 0-based fragment index. |
| `total` | `u8` | Total fragments in this transfer, 1..8. |

`total` is redundant in fragments 1..n−1 and it is repeated anyway: it makes every
fragment self-describing, so a receiver that joins mid-transfer knows immediately
that it has joined mid-transfer.

**Reassembly buffer on the ESP32:**

```c
static const uint16_t ASM_MAX = 768;     // 735 B worst-case window + slack
static uint8_t  asmBuf[ASM_MAX];
static uint16_t asmLen;
static uint8_t  asmSeq, asmNext, asmTotal;
static uint32_t asmStartMs;
```

768 bytes of `.bss`. Against 100–180 kB free heap this is not a budget item.

**Reassemble first, parse once.** Do **not** stream fragments into
`geomWay`/`geomPt` as they arrive. A way's vertex list straddles fragment
boundaries, so streaming needs a carry buffer and a resumable parser, and a
resumable parser that gets confused writes a half-way into the live array. Copy
into `asmBuf`, verify, then run one clean parse. It costs 768 bytes and removes
an entire class of bug.

**Acceptance rules, in order.** Any failure abandons the assembly (`asmLen = 0`)
and commits nothing — the previous view stays up, which is `geom.h`'s stated
design and is already correct.

1. `frag == 0` → start fresh: `asmSeq = seq`, `asmTotal = total`, `asmNext = 1`,
   `asmLen = chunkLen`, `asmStartMs = millis()`. A `frag == 0` **always** wins,
   even mid-assembly: the phone has restarted a transfer.
2. `frag > 0` and (`seq != asmSeq` or `frag != asmNext` or `total != asmTotal`)
   → **abandon**. Out of order, wrong transfer, or a fragment for a transfer
   whose start was missed.
3. `asmLen + chunkLen > ASM_MAX` → **abandon**. Refuses to overflow.
4. `millis() - asmStartMs > ASM_TIMEOUT_MS` (400 ms) → **abandon**, then apply
   rule 1 if this is `frag == 0`.
5. `frag == total - 1` → the transfer is **complete**: verify the CRC, then parse.

**Completion is CRC-checked.** The last two bytes of the reassembled payload are
**CRC-16/CCITT-FALSE** (poly `0x1021`, init `0xFFFF`, no reflection, no final
XOR) over everything before them.

> *Is this redundant?* Partly, and it is kept anyway. The BLE link layer already
> CRCs every PDU and retransmits, so within a live connection bytes do not
> silently corrupt or reorder — **fragment loss over BLE is not a random
> per-packet event, it is a connection event.** What the CRC actually catches is
> everything *above* the link layer: a NimBLE callback that runs out of buffer, a
> ring-buffer wrap in `ble.cpp`, a phone-side off-by-one in the chunker, a stale
> fragment from a previous connection. Two bytes and ~20 µs of table-free
> computation to guarantee the device never draws a corrupt road. **[verified
> reasoning: BLE 5.0 Core, Vol 6 Part B — LL uses a 24-bit CRC with
> acknowledgement and retransmission; ordered reliable delivery is a link-layer
> guarantee.]**

**Worst case: 5 fragments** for a 735-byte window [computed, §4.2]. Assembly
latency at Android's `CONNECTION_PRIORITY_HIGH` (11.25–15 ms interval) with
several ATT packets per connection event is **~30–60 ms [inferred]**; the 400 ms
timeout is 7x that.

### 4.2 `0x09 GEOM` — a window of roads

Payload after reassembly (fragment headers stripped, CRC stripped):

```
offset size  field              notes
  0     1    ver = 0x01         bump on any layout change
  1     1    flags              bit0 TRUNCATED   ways were dropped for budget
                                bit1 SNAPPED     origin is map-matched (§3.3)
                                bit2 FROZEN_HDG  heading is held, not measured
                                bit3 NIGHT       phone says use the night palette
                                bits 4-7 reserved, must be 0
  2     4    anchorKey  u32     the 256 m cell the rider is in (§4.0)
  6     2    rider_x_dm i16     rider offset east  of the cell's SW corner, 0..2559
  8     2    rider_y_dm i16     rider offset north of the cell's SW corner, 0..2559
 10     2    heading_cdeg u16   0..35999, clockwise from grid north
 12     2    speed_cm_s u16     0..65535 cm/s
 14     1    wayCount   u8      1..40
 15   ...    way records
 (end)  2    crc16              CRC-16/CCITT-FALSE over bytes 0..end-3
```

**Way record**, repeated `wayCount` times:

```
offset size  field
  0     1    cls_flags  u8
                bits 0-2  class  1 motorway, 2 trunk, 3 primary,
                                 4 secondary, 5 tertiary, 6 other-kept, 0 unknown
                bit 3     RAMP     (OMT ramp=1 — draw thin whatever the class)
                bit 4     TAKEN    -> geom.h GEOM_TAKEN 0x01
                bit 5     ONEWAY   (reserved for a future arrowhead; ignored today)
                bit 6     TUNNEL   (brunnel=tunnel)
                bit 7     reserved
  1     1    layer      i8    -2..+2, clamped by the phone (§2.4)
  2     1    n          u8    vertex count, 2..64
  3   4*n    vertices         i16 x_dm, i16 y_dm — ANCHOR-CELL-RELATIVE
```

**Size, computed:**

```
window header                    15 B
40 way records x 3 B headers    120 B
150 vertices x 4 B              600 B
crc16                             2 B
                               ------
                                737 B

fragments = ceil(737 / 177) = 5
wire bytes = 737 + 5*(2 + 3)  = 762 B per window
```

Which reproduces `ARCH_ANDROID_AUTO.md` §2.2's *"~726 B … five notifications at
MTU 185"* to within the header refinements added here. **[computed]**

**Parse order matters.** Parse the whole payload into locals first, validating
`wayCount ≤ GEOM_MAX_WAYS`, every `n ≥ 2`, and `Σn ≤ GEOM_MAX_PTS`, **before**
calling `geomBegin()`. `geomBegin()` clobbers the build arrays, so a payload that
fails validation halfway through would destroy a good view in order to fail. Only
call `geomBegin` once the payload is known to fit.

```c
geomBegin();
geomPose(rider_x_dm, rider_y_dm, heading_cdeg, speed_cm_s, 0);
for (each way)  { geomWay(layer, flags); for (each vtx) geomPt(x, y); }
geomCommit(millis());
```

### 4.3 `0x0A POSE` — motion, 4 Hz

Never fragmented. 13-byte payload, 15 bytes on the wire.

```
offset size  field
  0     4    anchorKey    u32   the cell the rider is in NOW
  4     2    rider_x_dm   i16
  6     2    rider_y_dm   i16
  8     2    heading_cdeg u16
 10     2    speed_cm_s   u16
 12     1    dt_cs        u8    centiseconds since the previous POSE, 0..255
```

`yaw rate` is **not** sent. It is recoverable on the device as
`(heading − heading_prev) / dt`, and sending a redundant derivative invites the
two to disagree. §5.2 uses the recovered value.

**Cost: 15 B × 4 Hz = 60 B/s.** [computed]

`anchorKey` is carried in full rather than as a delta so that a POSE is always
self-contained: a POSE that arrives after a missed window still places the rider
correctly, and one that arrives with an `anchorKey` the device has no geometry
for is *known* to be unusable rather than silently drawn against the wrong cell.

**Why 4 Hz and not 1 Hz.** At 50 km/h a 250 ms gap is 3.5 m = **2.8 px** at the
display scale [computed] — below the 4 px repaint threshold of §5.1, so POSE
alone produces motion that is already at the granularity the panel can show.
Dead reckoning (§5.2) exists to cover POSE *dropouts*, not to interpolate
between them.

### 4.4 `0x0B TILE` — cached geometry, and `0x0C TILEACK` — the device's answer

**`0x0B TILE`**, fragmented exactly like `0x09` (§4.1). Payload:

```
offset size  field
  0     1    ver = 0x01
  1     2    epoch      u16   identifies the tile extract this came from (§6.5)
  3     4    tileKey    u32
  7     1    wayCount   u8    0..32   (0 is legal and means "this cell is empty")
  8   ...    way records — identical encoding to §4.2, but coordinates are
             TILE-LOCAL decimetres from the cell's SW corner, range -128..+2688
             (12.8 m of overhang each side so a way crossing the boundary keeps
              its join and does not end in a visible stub at the seam)
 (end) 2    crc16
```

A typical cell is far smaller than a window: one 256 m cell over a Bengaluru
arterial holds **3–8 ways, 12–40 vertices**, so **~180–350 B, one or two
fragments [inferred, scaled from the measured 240 m window budget]**.

**An empty cell must be transmitted.** `wayCount = 0` is a positive statement
that there is nothing there. Without it the device cannot distinguish "no roads
in that cell" from "that cell has not arrived", and the second must never be
drawn as the first.

**`0x0C TILEACK`**, device → phone on the notify characteristic
`6e400003-…`. Never fragmented.

```
offset size  field
  0     1    ver = 0x01
  1     2    epoch u16  the extract epoch the device's cache belongs to,
                        or 0x0000 if the cache is empty
  3     1    count u8   0..9
  4   4*count tileKey u32, in eviction order — index 0 evicts next
```

Max 42 bytes on the wire. Sent on exactly three occasions:

1. **On connect / on MTU negotiation complete** — this is the reconnect story
   (§6.5) in one packet.
2. **After every `geomCommit` of a `0x0B TILE`** — a positive acknowledgement
   that the tile landed and passed CRC.
3. **After every eviction.**

The device reports its **whole resident set every time**, not a delta. Nine
`u32`s is 36 bytes; a delta protocol would save thirty bytes and introduce a
divergence bug that would take a season of riding to find.

### 4.5 What loss actually looks like, and what happens

| Event | What the device sees | What it does | What the rider sees |
|---|---|---|---|
| Connection drops mid-window | fragments stop | assembly times out at 400 ms, `asmLen = 0` | previous view, then the `PHONE DISCONNECTED` banner |
| Phone process restarts | a `frag == 0` with an unrelated `seq` | rule 1: start fresh | one window's worth of nothing, then normal |
| Phone chunker bug, wrong `total` | `total != asmTotal` on frag ≥ 1 | rule 2: abandon | previous view holds, then `GEOM_MAX_AGE_MS` blanks at 6 s |
| Corruption above the link layer | CRC fails | abandon, and `Serial.println` a counter | as above |
| A `0x0B TILE` never arrives | that cell is simply absent from the cache | **draw the cells it has, and nothing where it does not** | a corner of the box is empty — honest, and visibly different from a road |
| POSE stops, geometry does not | `nowMs − lastPoseMs` grows | dead-reckon up to `DR_MAX_MS` (§5.3), then freeze and mark | §8 |
| `anchorKey` in a POSE has no geometry | cell lookup misses | **do not draw the map.** Fall back to the maneuver arrow immediately | the arrow, which is never wrong |

**There is no retransmission request, and that is deliberate.** The device never
asks for a missing fragment. Geometry is perishable — `GEOM_MAX_AGE_MS` is 6 s
and a window is 240 m — so by the time a retransmit round trip completed, the
window it repaired would describe road the bike has already ridden through. The
correct repair for a lost window is **the next window**, which is already on its
way. `TILEACK` is the one exception, and only because a cached tile is *not*
perishable: it describes a place, not a moment.

---

## 5. Motion on the device

### 5.1 The two options — and the answer is both, in different jobs

| | (a) Re-send a window per update and step | (b) Send windows rarely, dead-reckon on the device |
|---|---|---|
| Bytes | 762 B per step. At 3 Hz that is **2.3 kB/s** — over the realistic budget | 762 B per 3 s + 60 B/s POSE = **314 B/s** |
| Motion granularity | limited by how often you can afford a window | limited only by the redraw threshold |
| Failure when the link stalls | picture freezes at the last window | picture keeps moving on stale assumptions — **the dangerous one** |
| Truth | every pixel came from the phone | position is extrapolated |

**Neither, alone.** (a) cannot afford fine motion; (b) is exactly the "stale map
is worse than no map" failure the project refuses. The resolution is to split
the two things being sent, which §4 already did:

- **Geometry** (`0x09 GEOM` / `0x0B TILE`) is expensive and changes slowly.
  Send it **rarely**: 0.33 Hz cruising, 1 Hz inside 150 m of a maneuver.
- **Pose** (`0x0A POSE`) is 15 bytes and changes constantly. Send it at **4 Hz**,
  60 B/s.
- **Dead reckoning** covers only the gap *between poses* and, briefly, a
  *dropout* of them. It is a 2.5-second bridge, not a navigation system.

This keeps every pixel's *position* traceable to a phone-supplied fix at most
250 ms old in normal operation, which is what makes it not-a-lie.

**Steady-state budget, computed:**

| Stream | Rate | Bytes/s |
|---|---|---|
| `0x09 GEOM`, cruising | 1 per 3 s | 254 |
| `0x0A POSE` | 4 Hz | 60 |
| `0x0C TILEACK` | on change | ~5 |
| **Total, no tile cache** | | **~319 B/s** |
| **Total, with the §6 cache warm** | | **~90 B/s** |
| Worst moment (inside 150 m, 1 Hz windows) | | **~830 B/s** |

Against the conservative 2 kB/s floor from `ARCH_ANDROID_AUTO.md` §1.2 the link
is at **16% steady, 42% at the worst moment.** [computed]

**Ask for the connection interval.** On the phone,
`BluetoothGatt.requestConnectionPriority(BluetoothGatt.CONNECTION_PRIORITY_HIGH)`
takes Android to an 11.25–15 ms connection interval. On the ESP32, NimBLE's
`ble_gap_update_params` should request the same. Without it Android settles at
~30–50 ms and the 5-fragment window takes several hundred milliseconds.

### 5.2 The dead-reckoning arithmetic

State, set by every `0x0A POSE`:

```c
struct Pose {
  int32_t  x_dm, y_dm;      // widened to i32: cell-relative, may exceed a cell
  float    h;               // radians, clockwise from grid north
  float    v;               // m/s
  float    w;               // yaw rate, rad/s, RECOVERED, not received
  uint32_t atMs;
};
```

Yaw rate is recovered from consecutive poses, wrapped correctly:

```c
float dh = wrapPi(h_new - h_prev);        // to (-pi, +pi]
w = dh / dtSec;
```

Extrapolation at time `t`, `dt = (t - atMs)/1000`. Heading is measured
**clockwise from grid north**, so the unit heading vector is `(sin h, cos h)` —
not `(cos h, sin h)`. Getting this backwards mirrors the map, which looks
plausible and is catastrophic.

```c
const float dh_dr = clampAbs(w * dt, DR_MAX_TURN);      // 15 deg = 0.262 rad
const float h_t   = h + dh_dr;

if (fabsf(w) < 1e-3f) {                 // straight: |w| < 0.057 deg/s
    x_t = x + v*dt*sinf(h);
    y_t = y + v*dt*cosf(h);
} else {                                // constant-turn-rate arc, R = v/w
    const float R = v / w;
    x_t = x + R * (cosf(h) - cosf(h_t));
    y_t = y + R * (sinf(h_t) - sinf(h));
}
```

That is the exact integral of `(ẋ, ẏ) = v·(sin h, cos h)` under `ḣ = ω`, so a
turn dead-reckons along the correct arc rather than along a chord.

**How much does the arc form actually buy? Less than it first looks, and it is
still worth taking.** Worked at 50 km/h through the hardest plausible turn
(ω = 0.575 rad/s = 33 °/s, R = v/ω = 24.2 m), with `DR_MAX_TURN` capping the
extrapolation at 15° = 0.262 rad, which is reached after **456 ms** of travel
= 6.33 m:

| Form | Endpoint (m) | Error vs the arc |
|---|---|---|
| Exact arc | (0.824, 6.257) | — |
| Chord along the **mid** heading `h0 + ωΔt/2` | (0.828, 6.280) | **0.023 m** — 0.02 px |
| Straight along the **entry** heading `h0` | (0.000, 6.330) | **0.83 m** — 0.66 px |
| Straight along `h0`, **if the 15° clamp were removed** and 2.5 s ran | — | **23.6 m** — 19 px |

[computed] So inside the clamp the naive straight-line form is already
sub-pixel, and the mid-heading chord is indistinguishable from exact. The arc
form is taken anyway for two reasons: two extra `cosf` calls per *frame* (not per
point) is not a cost worth reasoning about, and it makes the DR correct
**independently of `DR_MAX_TURN`** — so raising or removing that clamp later can
never silently introduce a 19 px error. Correctness that does not depend on a
tuning constant is worth 2 µs.

Cost: **1 `sincosf` + 4 `cosf`/`sinf` per frame, then 4 multiply-adds per stored
point.** For 150 points that is ~600 multiply-adds on a 240 MHz FPU-equipped
core: **well under 0.5 ms.** [computed, agreeing with `ARCH_OWN_NAV_APP.md` §7.3]

**Three hard clamps. Dead reckoning stops when any one trips:**

```c
static const uint32_t DR_MAX_MS   = 2500;    // 2.5 s
static const float    DR_MAX_DIST = 40.0f;   // metres travelled since the pose
static const float    DR_MAX_TURN = 0.262f;  // 15 degrees of accumulated turn
```

### 5.3 The drift budget, term by term

| Source | Magnitude | Over 250 ms (normal) | Over 2,500 ms (dropout) |
|---|---|---|---|
| Speed error — fused `getSpeedAccuracyMetersPerSecond()` is typically ~0.5 m/s | 0.5 m/s | 0.13 m = **0.1 px** | 1.25 m = **1.0 px** |
| Yaw-rate error — heading noise ~2° after §3.3 smoothing, differenced over 250 ms | ~11 °/s | 2.8° of heading | clamped at **15°** |
| Heading error → lateral error at the top of the box (105 m ahead) | | 105·sin(2.8°) = 5.1 m = **4.1 px** | 105·sin(15°) = 27 m = **22 px** |
| Arc-vs-straight-line, if the naive form were used (§5.2) | | < 0.01 m | 0.83 m = **0.7 px**, clamp-limited |

**The dominant term is heading, and it is dominant by an order of magnitude.**
That is why `DR_MAX_TURN` exists and why it is 15°: at 15° a road 105 m ahead is
drawn 22 px off, which is a quarter of the box width — the topology still reads
(three branches are still three branches, in the right order) but the geometry is
no longer trustworthy. Past that it stops being a map.

**In normal 4 Hz operation the total drift is ~4 px at the top of the box and
~0.1 px at the rider.** [computed] That is the honest number, and it is why the
motion is acceptable: the part of the picture the rider is standing on is exact,
and the error grows with distance ahead, which is also where the picture matters
least.

**Practical consequence, stated plainly:** dead reckoning here does **not** let
the phone send less often than 4 Hz. It lets the picture survive a tunnel, a
backgrounded app, or a 2-second BLE stall without freezing or lying. That is its
entire job.

### 5.4 Re-anchoring

**A new `0x0A POSE` replaces the DR state outright.** There is no blending and no
complementary filter: blending means deliberately drawing a position you already
know to be wrong. Compute the snap magnitude, use it, and log it:

```c
snap_px = hypot(x_dr - x_pose, y_dr - y_pose) * PX_PER_DM;
```

In normal operation `snap_px` is **0.1–0.5 px** — invisible. It only becomes
visible after a POSE dropout, which is exactly when the rider *should* see the
map correct itself. Keep a running max in the diagnostic counters; it is the
single best measure of whether the DR model matches the bike.

**A new `0x09 GEOM` replaces geometry and anchor atomically.** `geomCommit`
swaps `vPts/vWays/vAnchorKey` together. Points and anchor must never be updated
separately — a window's coordinates are meaningless against a different anchor.

**A POSE whose `anchorKey` differs from the committed geometry's is still
usable**, and this is the case that lets a window last for several cells:

```c
const int32_t dgx = (int32_t)(poseKey & 0xFFFF) - (int32_t)(anchorKey & 0xFFFF);
const int32_t dgy = (int32_t)(poseKey >> 16)    - (int32_t)(anchorKey >> 16);
if (labs(dgx) > 2 || labs(dgy) > 2) { mapUnusable(); return; }   // too far
rider_x_in_anchor_dm = pose_x_dm + dgx * 2560;
rider_y_in_anchor_dm = pose_y_dm + dgy * 2560;
```

Beyond ±2 cells (512 m) the rider has left the window entirely; **fall back to
the maneuver arrow**, do not draw an edge of a map 500 m behind.

### 5.5 Redraw cost, in milliseconds

The measured constant is **~1,700 px/ms** over SPI at 27 MHz (`HARDWARE.md`:
153,600 px in 45.5 ms = 1,688 px/ms — the figure checks out to 0.7%
**[verified, recomputed]**).

| Box | Pixels | SPI push | Sprite render | Transform | **Frame** | Ceiling |
|---|---:|---:|---:|---:|---:|---:|
| 84x84 (far) | 7,056 | **4.2 ms** | ~2–4 ms | <0.5 ms | **~7–9 ms** | ~120 FPS |
| **96x96 (approach) — the design point** | **9,216** | **5.5 ms** | ~3–5 ms | <0.5 ms | **~9–11 ms** | **~100 FPS** |
| 100x100 (widened far, §1.3) | 10,000 | 5.9 ms | ~3–5 ms | <0.5 ms | ~9–12 ms | ~90 FPS |
| 200x180 (variant B) | 36,000 | **21.2 ms** | ~10–18 ms | <0.5 ms | **~31–40 ms** | ~28 FPS |
| Full screen, for reference | 76,800 | 45.2 ms | — | — | — | 22 FPS |

Push times are **[computed]** from 1,700 px/ms. Sprite render times are
**[inferred]**, scaled by area and vertex count from `FEATURES.md`'s measured
*"~16–20 FPS with heading-up rotation included"* for ~200 points over the full
screen; the 96 box is 12% of that area with 75% of the points.

**Frame rate is not the constraint and never was.** The constraint is attention.

### 5.6 The repaint policy — where "step, don't animate" becomes a number

`ARCH_OWN_NAV_APP.md` §7.4 is right that continuous motion in the lower
peripheral field is an attentional cost paid for the whole ride. This spec builds
the moving map the rider asked for, and pays that finding its due by making the
motion **coarse on purpose**, with the threshold as the tunable:

```c
static const float REPAINT_PX   = 4.0f;    // accumulated translation
static const float REPAINT_DEG  = 3.0f;    // accumulated rotation
static const uint32_t REPAINT_MIN_MS = 90; // hard rate cap, ~11 FPS
```

Repaint when translation since the last paint exceeds 4 px **or** heading
exceeds 3°, and never more often than every 90 ms.

**What those numbers produce, computed:**

| Situation | Repaint rate | Step size |
|---|---|---|
| 50 km/h, straight | 4 px = 5 m ÷ 13.9 m/s → **2.8 Hz** | 4 px |
| 50 km/h, hard corner at 33 °/s | 3° ÷ 33 °/s = 91 ms → **11 Hz** (rate-capped) | 3° |
| 15 km/h in traffic | 5 m ÷ 4.2 m/s → **0.8 Hz** | 4 px |
| Stopped | **0 Hz** — nothing changes, nothing repaints | — |

Worst case is 11 Hz × 10 ms = **11% of one core** and 101,000 px/s of SPI, which
is **6% of the 27 MHz bus.** [computed] There is no thermal or power argument
against this; `FEATURES.md`'s 70 °C panel failure is a backlight-and-sun problem,
not a redraw problem.

**Two attention-preserving rules on top, both free:**

1. **Motion is spent where the decision is.** On the far screen (> 500 m) raise
   `REPAINT_PX` to 12 and cap at 0.5 Hz — the map there is orientation, not a
   decision, and it does not need to move. Inside 500 m use the numbers above.
   Below 100 m the map is not drawn at all (§1.4).
2. **Always render into a sprite and push once.** A 96x96 16 bpp sprite is
   **18,432 bytes** [computed]; the existing distance sprite is 33,280 B
   (`SPR_W 208 × SPR_H 80 × 2` **[verified]**), so the pair is 51.7 kB against
   100–180 kB free heap. Drawing the halo/ink passes directly to the panel — as
   `geomDraw` does today — makes every road visibly flash to background before
   it is re-inked, and at 2.8 Hz that flash is the motion the rider notices.
   Allocate it with the same `sprite_ok` fallback pattern `display.cpp` already
   uses, and fall back to direct drawing at 0.33 Hz stepping if it fails.

**The escape hatch is one constant.** Setting `REPAINT_PX = 9999` reduces this
system exactly to the shipped behaviour — one repaint per window, `geomKey()`
driving it — with no code removed. If a season of riding says the motion is a
distraction, the fix is a number, not a rewrite.

---

## 6. Tile caching on the ESP32

### 6.1 Why 3x3 of 256 m, proved rather than assumed

`ARCH_ANDROID_AUTO.md` §2.2 proposed 3x3 at 256 m without showing that it is
enough. It is, and the margin is 23 m.

The transmitted window is 240 m x 240 m: `x ∈ [-120, +120]`, `y ∈ [-40, +200]`
(§2.4). Its furthest corner from the rider is

```
r_max = sqrt(120^2 + 200^2) = 233.2 m
```

The window rotates with the rider, so the geometry the device can need is a
**disc of radius 233.2 m about the rider**, at any heading. The rider is
somewhere in the anchor cell; worst case is a corner of it, needing 233.2 m of
coverage beyond that corner in both axes. One neighbouring cell supplies 256 m.

```
256 m >= 233.2 m     ->  3x3 is exactly sufficient, with 22.8 m to spare
```

[computed] A 2x2 or an off-centre 3x3 would not be. A 5x5 would buy nothing for
rendering — only dropout tolerance, and dropout tolerance is already capped at
2.5 s by `DR_MAX_MS` (§5.2). **Stay at 3x3.** It is one constant if a repeated
commute ever justifies more.

### 6.2 Memory

```c
static const uint8_t  TILE_SLOTS     = 9;
static const uint8_t  TILE_MAX_WAYS  = 32;
static const uint8_t  TILE_MAX_PTS   = 128;

struct TileWay { uint8_t first, n; int8_t layer; uint8_t flags; };   // 4 B
struct TileSlot {
  uint32_t key;                       // 0 = empty
  uint32_t filledMs;
  uint8_t  nWays, nPts;
  TileWay  ways[TILE_MAX_WAYS];       //  128 B
  GeomPt   pts [TILE_MAX_PTS];        //  512 B
};                                    //  652 B
```

| Item | Bytes |
|---|---:|
| 9 x `TileSlot` | **5,868** |
| `asmBuf` reassembly (§4.1) | 768 |
| 96x96 16 bpp render sprite (§5.6) | 18,432 |
| **New RAM total** | **25,068** |
| Existing distance sprite (`208x80x2`) **[verified]** | 33,280 |
| **Both sprites + cache** | **58,348** |

Against **100–180 kB free heap** **[verified, `FEATURES.md`]** this fits with
room, and the sprite is by far the largest line — allocate it with the same
`createSprite() != nullptr` check `display.cpp` already does, and degrade to
direct drawing rather than failing.

5,868 B is close to `ARCH_ANDROID_AUTO.md` §2.2's independent *"9 × ~700 B =
6.3 kB"* estimate, which is a good sign that both derivations are sane.

**Overflow is a drop, never a truncation.** A cell denser than 32 ways / 128
points (an interchange will do it) is trimmed **on the phone**, dropping whole
ways by ascending class, and the `TRUNCATED` flag is set. Cutting a way short on
the device would draw a road that stops in mid-air.

### 6.3 Eviction — geometric, not LRU

The resident set is **defined by the anchor**, not by usage:

> A slot is resident if and only if its cell is within Chebyshev distance 1 of
> the anchor cell.

When `0x0A POSE` reports a new `anchorKey`, recompute; any slot now at distance
> 1 is freed immediately. Moving one cell east frees exactly 3 slots and opens
3 for the 3 new cells. **[computed]**

This is better than LRU for one specific reason: **it is deterministic and the
phone can predict it exactly.** LRU depends on draw-order accidents on the
device, so the phone's model of the cache would slowly diverge from the truth,
and the divergence would be invisible until a tile was silently missing. Here
the phone knows the resident set from the anchor alone, and `0x0C TILEACK`
exists only to catch tiles that failed to *arrive* — a much narrower job, and one
it can actually do.

**Refill traffic, computed.** At 50 km/h a 256 m cell is crossed every
**18.4 s**. Three new cells at ~250 B each = 750 B per 18.4 s = **41 B/s**,
which reproduces `ARCH_ANDROID_AUTO.md` §2.2's *"~39 B/s"* independently.

**Prefetch, so a crossing is never visible.** When the rider is within 100 m of
a cell boundary *and* the heading points across it, send the three cells on the
far side. 100 m is **7.2 s** at 50 km/h against the ~1 s the three tiles need on
the wire. A diagonal approach may need five cells; send five.

### 6.4 How the phone knows what the device holds

Three mechanisms, in order of authority:

1. **`0x0C TILEACK` is ground truth.** The device sends its whole resident set
   plus its `epoch` on connect, after every successful tile commit, and after
   every eviction. 42 bytes maximum. The phone's model is *replaced* by it, never
   merged with it.
2. **The phone's own prediction** from the anchor (§6.3) is used only to decide
   what to *prefetch*, never to decide what to skip.
3. **The rule that closes the gap:** the phone sends a cell whenever the cell is
   in the required set **and** the last `TILEACK` did not list it. Re-sending a
   cell the device already has is idempotent and costs 250 bytes. **When the two
   models disagree, send.** The failure of sending twice is 250 wasted bytes; the
   failure of not sending is a hole in the map.

**Deliberately absent: any device-initiated request.** The device never asks for
a tile. It has no idea which cells exist, which are empty, or where the rider is
going — the phone knows all three. A request protocol would add a round trip and
a state machine to buy nothing.

### 6.5 Reconnect, reboot, and a regenerated extract

**The cache is RAM and it does not survive a reboot. That is correct.** Storing
it in NVS would save re-sending 9 cells — about **2.3 kB, roughly one second of
BLE** — in exchange for flash wear on every ride and a persistence bug class that
outlives a power cycle. Not worth it. The 4 MB flash is 51% used and this is not
where the remaining half should go.

**The sequence on every connect:**

```
central connects
  -> MTU negotiated to 185
  -> device sends 0x0C TILEACK { epoch, count, keys[] }
     - after a reboot:        epoch = 0, count = 0
     - after a brief dropout: the full set it still holds, unchanged
  -> phone diffs against what it needs for the current anchor
  -> phone sends 0x0A POSE immediately (15 B — the rider is placed at once)
  -> phone sends 0x09 GEOM once (762 B — a guaranteed-correct first frame,
     independent of the cache)
  -> phone backfills missing 0x0B TILEs
```

**`0x09 GEOM` is the bootstrap, and this is why it stays in the protocol.** It
is self-contained: one packet family, no cache state, a complete picture. The
device is showing roads within ~200 ms of reconnecting, before a single tile has
been transferred. The cache then makes the *next* several minutes nearly free.

**`epoch` handles a regenerated extract.** It is a `u16` the phone derives from
the archive (the low 16 bits of the MBTiles file's mtime is sufficient) and
stamps into every `0x0B TILE`. Rules on the device:

- A `0x0B TILE` whose `epoch` differs from the cache's → **flush all 9 slots**,
  adopt the new epoch, accept the tile.
- `epoch` is reported in every `TILEACK` so the phone can see the flush happen.

Without this, regenerating the extract after an OSM update — a new flyover
opens, which in Bengaluru is a real and frequent event — would leave the device
drawing last month's junction from a cache the phone believed was current. That
is the exact "confidently wrong drawing" failure, arriving through the back door
of a cache, and two bytes closes it.

---

## 7. Rendering quality on this panel

### 7.1 The hatching is already fixed — and a worse bug is sitting behind it

The brief describes `geom.cpp` as drawing parallel offset lines that hatch on
diagonals. **That was true and is no longer.** The file on disk now reads
**[verified, `geom.cpp`, read 28 Aug 2026]**:

> *"each copy is a 1 px Bresenham line, and shifting it by (0.7, 0.7) rounds to
> whole pixels, so adjacent copies land on the same pixels or leave a gap …
> A segment is now one quad and a joint is one octagon, both clipped to the box
> with Sutherland–Hodgman and filled as a triangle fan."*

Correct diagnosis, correct fix, and the clip became exact rather than per-line.
Nothing in §7 asks for that to change.

**But the loop nesting is wrong, and it produces a false flyover.** The current
structure is:

```c
for (layer)                       // -2 .. +2
  for (way)
    for (pass)                    // 0 = halo (bg, w+10), 1 = ink (fg, w)
```

The halo/ink pass is **inside** the way loop. So within a single layer, way B's
halo is drawn *after* way A's ink, and **erases it where they cross**. Two
`primary` roads meeting at grade — `layer = 0` on both — therefore render with
one of them broken, which on this panel is the established, deliberate,
unmistakable signal for *"this road passes over that one."*

The device would be drawing a flyover that does not exist, at an at-grade
junction, in the exact feature whose entire purpose is flyover disambiguation.

**Fix — hoist `pass` above `way`:**

```c
for (layer)
  for (pass)                      // all halos for this layer, then all inks
    for (way)
```

Then same-layer roads **merge** at a crossing (correct: an at-grade junction is a
continuous surface) and only a *higher* layer's halo breaks a lower layer's ink
(correct: that is the flyover). One line moved. This should be fixed before any
of the rest of this document is built, because every §7.2 improvement below
would only make a wrong picture sharper.

*(Noted, not applied — this spec does not edit firmware.)*

### 7.2 Anti-aliasing — available, and it costs a sprite

TFT_eSPI 2.5.43 is installed **[verified, `library.properties`]** and exposes:

| Function | Signature |
|---|---|
| `drawWideLine` | `(float ax, ay, bx, by, float wd, uint32_t fg, uint32_t bg)` — *"draw an anti-aliased line with rounded ends, width wd"* **[verified, source comment]** |
| `drawWedgeLine` | same, with different end widths |
| `drawSpot` | AA filled circle (implemented as a zero-length wedge) |
| `fillSmoothCircle`, `drawSmoothCircle`, `drawSmoothArc` | AA circles and arcs |
| `alphaBlend(alpha, fg, bg[, dither])` | the primitive underneath |

**Two facts decide how to use them.**

1. **They blend against a *supplied* `bg_color`, or read the pixel back if
   `bg_color == 0x00FFFFFF`** **[verified, `TFT_eSPI.cpp`: `if (bg_color ==
   0x00FFFFFF) { bg = readPixel(xp, yp); swin = true; }`]**.
2. **`readPixel` is off the table on the panel.** `HARDWARE.md`: *"27 MHz is
   TFT_eSPI's documented ceiling for reading pixels back … Since this project
   never calls `readPixel`, 40 MHz should be reachable"* **[verified]**. Reading
   back from the ILI9341 would both be slow and forfeit the future 48% bandwidth
   gain from soldering and running at 40 MHz.

**Therefore: anti-alias inside the sprite, never on the panel.** `drawPixel`,
`readPixel`, `setWindow` and `pushColor` are all `virtual` in `TFT_eSPI.h`
**[verified, line 438 ff: *"These are virtual so the TFT_eSprite class can
override them"*]**, and `drawWedgeLine` reaches the panel only through them — so
`drawWideLine` on a `TFT_eSprite` works, and its `readPixel` is a RAM read.
§5.6 already requires a sprite for flicker; AA is the second reason for it.

**The sprite must be 16 bpp.** At 4 or 8 bpp `readPixel` returns a
palette-mapped value and a blend produces a colour that is not in the palette.
18,432 B for 96x96x2 (§6.2). Do not economise here.

**The pass rule, and why it is elegant rather than a compromise:**

| Pass | Method | Reason |
|---|---|---|
| **Halo** (`bg`, width `w + 10`) | keep the current **hard-edged filled quads**, no AA | The halo is an *erase*. An anti-aliased erase leaves a 50%-blended fringe that the ink pass only partly covers, putting a grey rim around every road — worse than aliasing, and invisible in testing but obvious in sunlight where everything is already grey. |
| **Ink** (`fg`/`muted`, width `w`) | `drawWideLine(ax, ay, bx, by, w, ink, bg)` | Its rounded ends make the octagonal joints unnecessary. And the `bg_color` argument is *exactly right*: the halo pass has just guaranteed the pixels under the ink's AA fringe are flat `bg`. The two passes fit together. |

**One residual artefact, stated:** where two ways *of the same layer* cross, the
second ink's AA fringe blends against `bg` while the true underlying pixel is
ink, leaving a ~1 px light seam. With §7.1's fix (all halos, then all inks, per
layer) this is the only place it can occur. At the 1.17:1 sunlight ACR
`HARDWARE.md` computes, it is invisible; at night it is a hairline. **Accept it.**

**Cost.** `drawWedgeLine` is per-pixel with a `fastBlend` — call it 3–5x a
`fillTriangle` span for the same area, but only the ink pass uses it and the ink
is the narrower stroke. Estimated **+1.5–3 ms** on the 96 box **[inferred]**,
against the ~9–11 ms frame of §5.5. Still under 15 ms.

**The rider marker** becomes `drawSpot` / `fillSmoothCircle`, or — per §1.5 — an
AA chevron built from three `drawWideLine` calls, which is both smoother and
simpler than the triangles.

### 7.3 Stroke widths, and what 700 mm actually means

**The panel, computed.** A 2.8" 4:3 module has a 43.2 x 57.6 mm active area, so
the pixel pitch is `57.6 / 320 =` **0.180 mm**.

```
angular size of 1 px at 700 mm = 0.180 / 700 = 2.571e-4 rad
                               = 0.01473 deg = 0.884 arc-minutes
```

[computed] This **independently confirms** `geom.cpp`'s own note — *"2 px … is
about 1.7 arc-minutes at the 700 mm a handlebar sits from the eye"* — which
implies 0.88 arcmin/px. The two derivations agree to 1%. **[verified]**

**What is legible.** 20/20 acuity resolves ~1 arcmin of *high-contrast* detail
under laboratory conditions. This panel offers none of those conditions: an ACR
of **1.17:1 in direct sun** (`HARDWARE.md`, computed), engine vibration, a
tinted visor, and a glance of well under a second taken with peripheral vision
doing most of the work. Derate by 4–5x. A stroke needs **≥ 4 arcmin ≈ 5 px** to
survive as a line rather than as a smudge.

**The hierarchy. Five widths, all ≥ 5 px:**

| Role | Width | Arcmin | Colour |
|---|---:|---:|---|
| The taken branch (`TAKEN`) | **11 px** | 9.7 | `fg` |
| motorway / trunk / primary | **7 px** | 6.2 | `fg` |
| secondary / tertiary | **5 px** | 4.4 | `muted` |
| ramp (`RAMP`, any class) | **5 px** | 4.4 | `muted` |
| *floor — never go below* | **5 px** | 4.4 | — |
| halo, added to whichever width | **+10 px** → 5 px gap each side | 4.4 | `bg` |

Current code has only two widths, `wThin = 5` / `wThick = 11` **[verified]**, and
they bracket this table exactly — the middle tier at 7 px is the addition.
`geomWay` needs the class, so widen its signature to take the `cls_flags` byte
from §4.2 rather than just `GEOM_TAKEN`.

`geom.cpp`'s own note on the halo stands and is confirmed by the arithmetic:
*"4 gave 2 px of clearance … below the threshold where a gap reads as a gap …
10 gives 5 px, which is the difference between 'the flyover crosses over' and
'the roads touch'."* 5 px = 4.4 arcmin — the same floor as a stroke, which is
the right answer for the same reason.

**Width is load-bearing; colour is not.** `HARDWARE.md` rule 4: *"Everything
converges to grey in glare, so contrast has to come from area and shape, not
colour. Never encode anything load-bearing in colour alone."* **[verified]** In
direct sun `C_MUTED` (0x8410) and `C_FG` (black) will not be distinguishable.
The hierarchy must therefore read from **width alone**, and the table above does:
11 / 7 / 5 are separable at 4.4 arcmin of quantisation even when every one of
them is the same shade of grey. Colour is a bonus that works at night and in
shade.

### 7.4 Palettes

The existing swap is used unchanged **[verified, `display.cpp`]**:

```
day    C_BG = TFT_WHITE   C_FG = TFT_BLACK   C_MUTED = 0x8410
night  C_BG = TFT_BLACK   C_FG = TFT_WHITE   C_MUTED = 0x8410
```

`geomDraw` already takes `(fg, muted, bg)` as arguments rather than reading
globals **[verified]**, so it needs no change at all — the caller passes whichever
triple is current, and the sprite's `fillSprite(bg)` and every `drawWideLine`'s
`bg_color` argument follow from the same three values. Getting this for free is
a consequence of the existing signature being right.

**Three palette-specific notes:**

1. **Night: do not use pure white ink.** White-on-black at width 11 halates on a
   TN panel and blooms under a wet visor. Use `0xE71C` (~90% white) for `fg` at
   night and keep `bg` at true black. **Geometry stays identical between
   palettes** — only the ink value changes — so nothing else in the layout has
   to know which palette is active. **[inferred]**
2. **`C_MUTED` is identical in both palettes** and that is a real problem at
   night: `0x8410` mid-grey against black is a 4.5:1 ratio, against white it is
   1.5:1. It reads well at night, poorly by day — and by day is exactly when the
   ACR is 1.17:1 and it needs to read best. **The width hierarchy is what
   rescues this**, which is the second reason §7.3 refuses to encode anything in
   colour.
3. **The amber accent (`C_ACCENT` 0xFC40) does not appear in the map. Ever.**
   `display.cpp` is explicit: *"One accent, one meaning: amber is 'live /
   attention' and appears nowhere else."* **[verified]** A road is not an alert.
4. **Under 30 m the screen inverts** (`UI_NAV_NOW`, `C_INV_*`), and the map is
   not drawn on that screen at all (§1.4), so the two never interact.

---

## 8. Failure modes

**The rule, from `geom.h` and unchanged:** *"Geometry is as perishable as a
maneuver. If the phone stops sending, the roads on screen are where you WERE, and
a stale map is worse than none."* **[verified]**

The map therefore has exactly **three** display states, and the transitions
between them are all time-driven. There is no fourth state and no "degraded map".

| State | Condition | What is on screen |
|---|---|---|
| **LIVE** | pose < 2.5 s old **and** geometry < 6 s old | the map, moving |
| **HELD** | pose 2.5–6 s old, geometry < 6 s old | the map, **frozen**, with a held marker |
| **GONE** | geometry ≥ 6 s old, or anything below says so | **the maneuver arrow.** Not a blank box — the arrow, which is what the box showed for the whole project before this feature existed |

`GEOM_MAX_AGE_MS = 6000` already implements the LIVE→GONE edge and `geomKey()`
already forces exactly one repaint at it **[verified, `geom.h`]**. The HELD state
is new and needs `POSE_MAX_AGE_MS = 2500` alongside it.

**The HELD marker.** A 2 px hollow ring around the rider dot instead of the solid
disc — a shape change, not a colour change, per `HARDWARE.md` rule 4. It says
"this picture is no longer being updated" without a word of text and without
costing a foveation.

### The full table

| Failure | Detected by | Behaviour | On screen |
|---|---|---|---|
| **Stale geometry** — phone stops sending windows | `geomValid()` false at 6 s | `geomDraw` not called | maneuver arrow returns. Already shipped. |
| **Stale pose** — POSE stops, geometry still fresh | `now − lastPoseMs > 2500` | stop dead reckoning, hold the last pose | map frozen + HELD ring |
| **Lost fragment / connection drop mid-window** | §4.1 rules 2–4, 400 ms timeout | commit nothing | previous view holds, then the 6 s edge |
| **CRC failure** | §4.1 rule 5 | commit nothing, bump `geomCrcFails` | as above |
| **GPS drift while stopped** | `speed < 2.8 m/s` on the phone | phone freezes heading; after 20 s stops sending windows | map freezes, then GONE at +6 s → arrow. Never a spinning map. |
| **GPS bearing accuracy poor while moving** | `bearingAccuracyDegrees > 25` | phone sets `FROZEN_HDG`, holds the last heading, keeps sending | map translates but does not rotate. Honest: position is known, heading is not. |
| **Tunnel / underpass** | fused coasts, then fixes stop | phone keeps sending POSE from the fused coast while it lasts; then POSE stops | LIVE → HELD at 2.5 s → GONE at 6 s. A 60 m underpass at 50 km/h is 4.3 s, so a typical Bengaluru underpass ends in HELD and never reaches GONE. **[computed]** |
| **Phone backgrounded / Samsung kills the service** | BLE writes stop entirely | watchdog | `PHONE DISCONNECTED` banner (already implemented) |
| **BLE disconnect** | NimBLE callback | `geomClear()` on disconnect | banner. Do **not** leave a map up behind a disconnect banner. |
| **ESP32 reboot** | — | cache empty, `TILEACK` reports `epoch=0, count=0` | boot screen, then arrow, then map within ~1 s of the first GEOM |
| **A cell never arrives** | absent from the resident set | draw the cells present; draw **nothing** in the missing one | a visibly empty corner. Distinguishable from "no roads there"? **No — and that is the one honest weakness of this design. [§10]** |
| **Anchor > 2 cells from the geometry** | §5.4 | `mapUnusable()` | arrow, immediately |
| **Window truncated for budget** | `TRUNCATED` flag | draw what arrived | the map, with minor roads missing. Acceptable: no drawn road is false, some true roads are absent. |
| **Sprite allocation fails at boot** | `createSprite() == nullptr` | direct-to-panel drawing, `REPAINT_PX = 9999` | the shipped step-per-window behaviour, no AA. Degraded, not broken. |

**The asymmetry that governs all of it.** Every failure above resolves toward
**the maneuver arrow**, never toward a partial map. The arrow is derived from a
live notification and cannot be stale without the watchdog knowing. A map with
one road missing looks exactly like a map with no road there, and there is no
way for the rider to tell — so the map is all-or-nothing and the arrow is the
floor.

---

## 9. Verification

### 9.1 Host-side — the part that must not need hardware

**Structural prerequisite: split `geom.cpp`.** The parse, the grid arithmetic and
the dead reckoner have no business depending on `TFT_eSPI.h`, and while they do,
none of them can be tested with `g++`. Move them to **`firmware/navigator/geomwire.cpp`**
(pure C++, no Arduino, no TFT) leaving `geom.cpp` as the renderer. This is the
single highest-value change in this document for testability.

Then `tools/geomtest` — a host binary linking `geomwire.cpp` — gives:

| Test | Assertion |
|---|---|
| Round trip | phone-side encoder output → parser → identical way/point set |
| CRC | flip one bit anywhere in a 737 B window → parse refused, no commit |
| Fragment out of order | send frags 0,2,1 → abandoned, previous view intact |
| Fragment `seq` change mid-transfer | abandoned |
| `total` mismatch | abandoned |
| Oversize | `wayCount = 41`, `Σn = 151`, `n = 1`, `n = 0` → all refused **before** `geomBegin` |
| `ASM_MAX` overflow | 9 fragments claiming `total = 9` → refused at rule 3, no memory touched past 768 |
| Grid | `tileKey` round trip for the four bbox corners; `cos(LAT_REF)` fixed, not per-fix |
| Anchor rebase | POSE in each of the 8 neighbour cells lands within ±2560 dm of the anchor |
| Dead reckoning | a synthetic 33 °/s constant-radius turn: arc form matches a closed-form circle to < 1 mm. With `DR_MAX_TURN` **disabled**, the naive straight-line form must diverge by 23.6 m over 2.5 s — that is the assertion that proves the arc form is doing real work (§5.2) |
| DR clamps | each of `DR_MAX_MS`, `DR_MAX_DIST`, `DR_MAX_TURN` trips independently |
| Heading wrap | 359° → 1° smoothing produces +2°, never −358° |

**`tools/geomfuzz.pl`** — new. Emits malformed byte streams into `geomtest` on
stdin: random truncation, random bit flips, adversarial lengths, `len` disagreeing
with the ATT write length (the exact hazard `BLE_PROTOCOL.md` warns about:
*"a wrong length must drop a packet, never corrupt state"*). Pass condition:
**no crash, no commit, no read outside `asmBuf`.** Run it under ASan.

**`tools/ascii_junction.pl` — three additions.** It already *"reproduces
geomDraw(): same rider anchor, same decimetre-to-pixel scale, same layer
ordering, same halo-punches-a-gap trick"* **[verified, tool header]**, which makes
it the right place for all three:

1. **`--pose x,y,heading`** — render the same `junc*()` from `demo.cpp` at an
   arbitrary pose. This is the acceptance test for the §4.0 refactor: the
   junction seen head-on and the same junction seen at 30° must be the same
   roads. Without it the grid-frame change is untested.
2. **`--frames N --speed V`** — a flipbook of N poses along a dead-reckoned
   path, printed side by side. Reading down the page shows whether motion is
   monotonic or whether roads jitter by a pixel between frames from rounding.
   The jitter is what a rider would see as shimmer, and ASCII shows it plainly.
3. **`--layers`** — render an at-grade crossing of two `layer = 0` primaries.
   **This is the regression test for §7.1.** Today it prints one road broken;
   after the loop is hoisted it must print them merged. The tool's own header
   already states the principle: *"If the cross road does NOT break under the
   flyover here, the layer ordering is wrong and it will be wrong on the panel
   too."* The converse needs testing too.

### 9.2 On the device, without a bike

**`demo.cpp` — add `M_MOVE`.** The existing `M_JUNC` mode holds each junction
static for `JUNC_MS = 3000` **[verified]**. `M_MOVE` takes the same `junc*()`
geometry and drives `geomPose()` at 4 Hz along a scripted path — approach at
50 km/h, decelerate, a 33 °/s turn, a stop, a restart. No phone, no BLE, no GPS.

This is the only way to answer the question §5.6 cannot answer arithmetically:
**does 4 px at 2.8 Hz read as motion or as stuttering, at 700 mm, in sunlight?**
Ride the panel taped to the bars with the engine running and `M_MOVE` looping.
`demo.cpp`'s own header states the doctrine: *"what you judge on the panel is the
real renderer, at mount distance, in real light."* **[verified]**

Add a `M_MOVE` sub-step that **stops sending poses mid-motion**, to see the
LIVE → HELD → GONE cascade of §8 with your own eyes at mount distance.

**Instrument the frame.** Wrap the sprite render and the push in `micros()` and
print `render_us / push_us / total_us` once a second. §5.5's push times are
computed and its render times are **inferred**; both need to become measured.
Specifically confirm or refute:

- 9,216 px pushes in **5.5 ms** (predicts 1,700 px/ms holds for a windowed push,
  not just `fillScreen`)
- sprite render **3–5 ms**, and **+1.5–3 ms** when the ink pass switches to
  `drawWideLine`
- peak heap after allocating both sprites stays above 40 kB

### 9.3 On the phone

**Extend `tools/navsim.py`.** It already *"connects to the navigator, writes
packets exactly as docs/BLE_PROTOCOL.md specifies, and prints every packet as hex
next to its decoded meaning"* **[verified]**, and it already has a `--garbage`
mode for malformed input. Add:

| Mode | What it does |
|---|---|
| `--map <gpx>` | Replay a GPX trace: derive COG, run the §3.3 filter, emit `0x09`/`0x0A`/`0x0B` at the real cadences. The complete phone side, minus the tiles. |
| `--map --tiles <mbtiles>` | The same, actually reading the MBTiles archive — proves the extract, the TMS y-flip, the class filter and the RDP tolerances in one command, on a desktop. |
| `--map --drop 5%` | Randomly drop whole fragments. Proves §4.5 without unplugging anything. |
| `--map --stall 3s` | Stop POSE mid-ride. Proves LIVE → HELD → GONE. |
| `--map --epoch-bump` | Change `epoch` mid-session. Proves the §6.5 cache flush. |
| `--tileack` | Print every `0x0C` the device notifies, so the cache can be watched filling and evicting from the desktop. |

**On the phone itself**, `FusedLocationProviderClient.setMockMode(true)` +
`setMockLocation()` replays the same GPX through the real app, exercising the
real MVT decode and the real BLE stack while the bike is in the garage.

**The one measurement to take first, before any of this.** `ARCH_OWN_NAV_APP.md`
§7.2 flags it and it remains the largest unmeasured risk in the whole design:

> *"I did not test COG stability on the S24+ at Bengaluru crawl speeds, and that
> is worth one ride with a logger."*

One ride, logging `getBearing()`, `getBearingAccuracyDegrees()`, `getSpeed()` and
`getSpeedAccuracyMetersPerSecond()` at 1 Hz, through signals and stop-start
traffic. It sets the 2.8 m/s threshold, the 25° accuracy gate and the 0.6 s time
constant — three numbers currently chosen by reasoning. **Do this before writing
the window builder**, because if COG is unusable below 20 km/h rather than
10 km/h, the map is a highway instrument and not a city one, and that changes
what gets built.

### 9.4 What cannot be simulated

Three things, all of which need the bike, the sun and the visor:

1. **Whether 4 px at 2.8 Hz is motion or shimmer** (§5.6, §9.2).
2. **Whether a 5 px `muted` road is visible at 1.17:1 ACR** (§7.3). The
   arithmetic says 4.4 arcmin; the arithmetic said 5:1 contrast was needed and
   the panel delivers 1.17:1, so the arithmetic is not the last word here.
3. **Whether the map is read or studied.** This is the whole §7.4-of-
   `ARCH_OWN_NAV_APP` argument, and it is behavioural. The honest test is to ride
   a familiar route with the map on and count how often you look at it versus how
   often you looked at the arrow. If the count goes up, the map is costing
   attention rather than saving it, and `REPAINT_PX = 9999` is the answer.

---

## 10. Open questions

Ordered by how much they could change the design.

1. **COG stability at Bengaluru crawl speeds. [unknown]** §9.3. The largest
   risk. One instrumented ride.
2. **Does `layer` / `bridge` coverage hold for Bengaluru flyovers? [unknown]**
   `ARCH_ANDROID_AUTO.md` §2.2 wrote the Overpass query and did not run it, and
   it is right that this is the coverage question that killed lane guidance
   (0.52% `turn:lanes`). Two minutes of Overpass. **The entire flyover feature is
   downstream of the answer.**
3. **Does dropping `class=service` lose the flyover's ground-level
   carriageway? [inferred, §2.5]** Spot-check three named Bengaluru flyovers in
   Overpass and read the actual tags on the road beneath.
4. **A missing cell and an empty cell look identical on screen. [known gap,
   §8]** The protocol distinguishes them (`wayCount = 0` is explicit) but the
   *rendering* does not. Options: a faint dotted border on cells not yet held, or
   refusing to draw the map at all until all 9 are resident. The second is
   simpler and more honest and probably right; it costs the first second after a
   reconnect, which §6.5's `0x09 GEOM` bootstrap already covers. **Decide before
   the cache ships, not after.**
5. **Roads-only tile size. [inferred, §2.2]** ~8–14 MB predicted for the 440-tile
   bbox. One `planetiler` run settles it.
6. **Sprite render time and the `drawWideLine` delta. [inferred, §5.5, §7.2]**
   `micros()` and a serial print.
7. **Is 40 MHz reachable once soldered?** `HARDWARE.md` says it should be, and it
   is **48% more bandwidth** — which would take the 96 box push from 5.5 ms to
   3.7 ms and Variant B (§1.3) from 21.2 ms to 14.3 ms. Variant B is not
   reconsidered on frame-rate grounds — §1.3 rejected it on attention, not
   milliseconds — but the headroom is worth having. Retest after soldering, do
   not assume.
8. **Should `0x09 GEOM` survive once the tile cache works?** This spec keeps it
   as the reconnect bootstrap (§6.5) and it earns that. Revisit after a season:
   if `0x0B TILE` + `0x0A POSE` proves reliable, GEOM is ~200 lines of device
   code doing a job three packets could do.

---

## Sources

Project documents, all in this repository and treated as authoritative:

- `docs/ARCH_OWN_NAV_APP.md` §2.2 (measured tile sizes, extract generation), §7
  (the moving map: heading source, dead reckoning, step-don't-animate)
- `docs/ARCH_ANDROID_AUTO.md` §2.2 (the vector-window transport, byte budget,
  tile caching, `0x09 GEOM` sketch), §1.2 (link budget)
- `docs/FEATURES.md` (raster rejected, vector recommended; the glance budget;
  measured 16–20 FPS with rotation; free heap 100–180 kB)
- `docs/HARDWARE.md` (27 MHz / 45.5 ms full-frame; ACR 1.17:1 in sun; polarised
  sunglasses; the colour-is-not-load-bearing rule)
- `docs/BLE_PROTOCOL.md` (framing, MTU 185, the `len`-is-advisory rule)
- `docs/NAV_DATA.md` (flyovers undistinguished by Maps; stationary GPS drift)
- `firmware/navigator/geom.h`, `geom.cpp` (the shipped renderer — read 28 Aug
  2026, after the filled-quad rewrite)
- `firmware/navigator/display.cpp`, `nav_types.h` (layout constants, palettes,
  screen thresholds)
- `tools/ascii_junction.pl`, `tools/navsim.py`, `firmware/navigator/demo.cpp`

External, all fetched or read 28 Aug 2026:

- PMTiles v3 specification —
  https://github.com/protomaps/PMTiles/blob/main/spec/v3/spec.md
- PMTiles repository (language implementations; no Java/Kotlin) —
  https://github.com/protomaps/PMTiles
- `tileverse-io/tileverse-pmtiles` (Java, v1.0.0, **archived**) —
  https://github.com/tileverse-io/tileverse-pmtiles
- MBTiles 1.3 specification (TMS row ordering) —
  https://github.com/mapbox/mbtiles-spec/blob/master/1.3/spec.md
- Mapbox Vector Tile specification 2.1 —
  https://github.com/mapbox/vector-tile-spec/tree/master/2.1
- `ElectronicChartCentre/java-vector-tile` (Apache-2.0, 209 stars, last push
  2025-01-15; Maven repo `https://maven.ecc.no/releases`) —
  https://github.com/ElectronicChartCentre/java-vector-tile
- `com.wdtinc:mapbox-vector-tile:3.1.0` (Maven Central, last published
  2019-04-12) —
  https://repo1.maven.org/maven2/com/wdtinc/mapbox-vector-tile/
- Planetiler (flags verified in `PlanetilerConfig.java` and `PLANET.md`) —
  https://github.com/onthegomap/planetiler
- OpenMapTiles `transportation` layer schema (all `class`, `brunnel`, `layer`,
  `ramp`, `service` values) —
  https://github.com/openmaptiles/openmaptiles/blob/master/layers/transportation/transportation.yaml
- Geofabrik India / southern-zone extracts —
  https://download.geofabrik.de/asia/india.html
- TFT_eSPI 2.5.43, installed locally — `TFT_eSPI.h` (virtual `drawPixel` /
  `readPixel` / `setWindow` / `pushColor`; `drawWideLine`, `drawWedgeLine`,
  `drawSpot`, `fillSmoothCircle`, `alphaBlend`), `TFT_eSPI.cpp`
  (`drawWedgeLine` blends against `bg_color`, or `readPixel` when
  `bg_color == 0x00FFFFFF`) — https://github.com/Bodmer/TFT_eSPI
- Android location APIs: `FusedLocationProviderClient`, `LocationRequest.Builder`,
  `Priority`, `Location.getBearingAccuracyDegrees()` (API 26+),
  `BluetoothGatt.requestConnectionPriority` —
  https://developer.android.com/reference/android/location/Location
