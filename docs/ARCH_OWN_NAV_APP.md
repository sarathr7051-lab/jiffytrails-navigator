# Building our own navigation app

Architecture feasibility study, 28 Aug 2026. **DRAFT — IN PROGRESS.**

Question asked: **should we stop scraping Google Maps and build our own
navigation app on open-source maps — a real moving map with buildings, proper
cartography, turn-by-turn and search — and feed the handlebar display from data
we own end to end?**

---

## 1. Recommendation

*(pending — written last)*

---

## 2. Map rendering stack

### 2.1 MapLibre Native Android in 2026 — mature, and this is not the hard part

**Verified** from the repository and the getting-started guide.

| Fact | Value |
|---|---|
| Artifact | `org.maplibre.gl:android-sdk` on Maven Central |
| Current version | **13.5.1**, released 2026-08-21 |
| Release cadence | 13.0.1 (Mar), 13.1.0 (Apr), 13.2.0 (May), 13.3.0 (Jun), 13.4.0 (Jul), 13.5.0/13.5.1 (Aug) — **monthly, this year** |
| `minSdk` / `compileSdk` | 23 / 34 |
| Offline API | `org.maplibre.android.offline.OfflineManager` (Kotlin), with `offline_manager.cpp` JNI behind it; instrumented tests `OfflineManagerTest.kt`, `OfflineDownloadTest.kt` exist |
| License | BSD-2-Clause, no telemetry, no API key |

Sources: [`platform/android/VERSION`][mlnver], [`MapLibreAndroid/build.gradle.kts`][mlngradle],
[getting-started guide][mlnstart], [release tags via GitHub API][mlnrel].

This is a healthy, actively released project on a monthly cadence, and it is a
drop-in Mapbox-GL-v9 descendant with a familiar API. **Rendering an OSM vector
map on the phone is a solved problem and should be costed at days, not weeks.**
The offline path is first-class: `OfflineManager` downloads a style plus a
bounded region into the local ambient cache, or you point the style's source at
a `file://` or `mbtiles://` URI and skip the network entirely.

One caution, **inferred**: MapLibre's Android offline region API descends from
Mapbox's, which historically had a 6,000-tile-per-region soft limit and stored
into a single SQLite cache. For a Karnataka-sized region you want to hand
MapLibre a pre-built local archive rather than ask `OfflineManager` to download
one tile at a time. I did not confirm the current limit constant.

### 2.2 Offline vector tiles for India — measured, not estimated

`ARCH_ANDROID_AUTO.md` listed real per-tile MVT sizes for Bengaluru as an open
unknown. **It is now measured.**

Method: OpenFreeMap serves a full OpenMapTiles-schema planet as public MVT at
`https://tiles.openfreemap.org/planet/20260823_080002_pt/{z}/{x}/{y}.pbf`
(TileJSON read directly, build dated 2026-08-23). I fetched real tiles and
recorded `%{size_download}` — gzipped bytes on the wire, which is what lands on
disk.

**Tile counts for the project bbox** (arithmetic):

| Zoom | x range | y range | Tiles |
|---|---|---|---:|
| 12 | 2928–2933 | 1896–1901 | 36 |
| 13 | 5857–5867 | 3792–3802 | 121 |
| 14 | 11714–11735 | 7585–7604 | 440 |

**Measured sizes:**

| Sample | n | Mean bytes | Range |
|---|---:|---:|---|
| z14, Bengaluru bbox (6×5 grid) | 30 | **57,452** | 3,101 – 437,685 |
| z13, Bengaluru bbox (5×4 grid) | 20 | **50,052** | 11,501 – 161,538 |
| z14, rural Karnataka (~14.5 N, 76.0 E) | 12 | **1,352** | 186 – 3,050 |

The 42× spread between dense-core and rural z14 tiles is the important number,
because it makes the Karnataka extrapolation cheap:

| Extract | Estimate |
|---|---|
| Bengaluru bbox, z0–14 | 440 × 57 kB + 121 × 50 kB + 36 × ~40 kB ≈ **~35 MB** |
| Karnataka, z0–14 | ~192,000 km² ÷ 5.67 km² per z14 tile ≈ 33,900 z14 tiles, overwhelmingly rural at 1.35 kB, plus a handful of cities ≈ **~120–160 MB** |
| India, z0–14 | scaling by area (~3.29 M km²) ≈ **~1.5–2.5 GB** *(inferred, wide error bars)* |

**All of Karnataka fits in under 200 MB.** That kills storage as an objection
outright. The prior document's "20–30 MB, estimated" for Bengaluru was low by
about 20%; the corrected figure is still trivially small.

**How to generate it.** Two paths, both fine:

- **Planetiler** ([repo][pt]) — Apache-2.0, produces MBTiles *or* PMTiles, MVT or
  MLT, default profile is the OpenMapTiles schema. Stated requirements: *"at
  least 0.5× as much free RAM as the input `.osm.pbf` file size"* and *"1 GB of
  free SSD disk space plus 5–10× the size of the `.osm.pbf`."* For
  `southern-zone-latest.osm.pbf` at **531 MB** (verified today from
  [Geofabrik][gfi]) that is ~266 MB RAM and ~5 GB disk. Its published benchmarks
  are planet-scale (92 GB input in 19 min on a 192-CPU machine); **a 531 MB
  regional extract on a normal desktop is minutes, not hours** — I did not run
  it, so call that **inferred**, but the scaling is not subtle.
- **Protomaps `pmtiles extract`** — the planet basemap is *"roughly 120
  gigabytes, including zoom levels from 0 to 15"* ([docs][pmdl]), and `extract`
  pulls an arbitrary bbox out of it with HTTP range reads, so you never download
  120 GB. Single file, no SQLite. The prior doc flagged Java PMTiles reader
  maturity as unknown — **that no longer matters if MapLibre is the renderer**,
  because MapLibre Native reads `pmtiles://` natively. It only mattered when the
  plan was to decode MVT by hand.

**Licensing.** OSM data is ODbL. OpenMapTiles: *"All code in this repository is
under the BSD license. Design and the cartography decisions encoded in the
schema and SQL are licensed under CC-BY"*, with a requirement to *"visibly
credit 'OpenMapTiles.org'"* ([README][omt]). Protomaps basemap is an *"Open
Database License Produced Work"*. For a personal, never-published app all three
are satisfied by one line of attribution text in an About screen. **No licensing
obstacle exists.**

### 2.3 Buildings — the Overpass count, run 28 Aug 2026

Same bbox every other measurement in this project uses,
`(12.80, 77.40, 13.20, 77.85)`. Overpass `out count;`, data timestamp
`2026-08-28T04:43:31Z`. **Verified — I ran these.**

| Query | Ways | Relations | Total | % of buildings |
|---|---:|---:|---:|---:|
| `building=*` | 809,552 | 955 | **810,507** | 100% |
| ...with `building:levels` | 13,468 | 199 | **13,667** | **1.69%** |
| ...with `height` | 1,419 | 45 | **1,464** | **0.18%** |
| ...with `name` | 9,721 | 0 | **9,721** | **1.20%** |

Read these two rows in opposite directions.

**Footprints: outstanding.** 810 k building outlines across a ~50 × 50 km box is
dense, city-wide coverage — this is the Microsoft/Facebook ML-footprint import
era and Bengaluru got it. A 2D building fill is fully supported by the data and
is the single biggest cartographic difference between a bare OSM map and one
that looks like Google's. Free, immediate, no design work.

**Heights: dead.** 1.69% for `building:levels` and 0.18% for `height` is the
`turn:lanes` story again — 0.52% is what killed lane guidance in `FEATURES.md`,
and 0.18% is *worse than that*. And unlike `bridge` (§ARCH_ANDROID_AUTO
addendum), where absence is meaningful because most roads genuinely are not
bridges, here absence is pure missing data: every one of those 810 k buildings
has a height in reality.

**So 3D extrusion is not worth anything in Bengaluru.** MapLibre's
`fill-extrusion` layer would render 1.7% of buildings as blocks and 98.3% as
flat nothing, or — the OpenMapTiles default — extrude everything to a fallback
height, which is a lie drawn at 60 fps. On a handlebar the question does not
even arise; the ESP32 gets line segments, not a GL scene. On the *phone* screen
it is a demo feature you would look at once. **Conclusion: 2D building fills
yes, `fill-extrusion` no.** That is a real finding and it removes a chunk of
work from every option below.

Named buildings at 1.20% is a separate and worse problem, and it belongs to
§4.2: it means POI search cannot lean on building names.

### 2.4 Cartography — what comes free, what needs design

Free, immediately, from any OpenMapTiles style (OSM Bright, Positron, Liberty,
Protomaps Light/Dark): road network by class with sane widths and casings, water
and landuse fills, **building fills** (§2.3 says the data is there), park and
green space, label placement with collision detection, text halos, zoom-dependent
feature filtering, and light/dark variants. This is a competent general-purpose
map and it is one style-JSON URL of work. Nobody should spend a week on it.

What does **not** come free, and this is where Google's readability actually
lives:

1. **A navigation style is not a browsing style.** Google's driving map dims
   everything that is not the route, thickens the route corridor, drops most
   POIs, and raises road-name label priority. Every off-the-shelf OMT style is
   tuned for browsing a map on a desk. Retuning one into a navigation style is
   real work — call it **15–30 h** of iterating on a style JSON against real
   rides, and it is the kind of work that is never finished.
2. **Prominence.** Google knows Old Airport Road matters more than the service
   road beside it because it has traffic and behavioural data. OSM has
   `highway=*` and nothing else. An OMT style renders every `secondary` alike.
   There is no open substitute for this and no amount of styling manufactures it.
3. **Label language.** OMT carries `name`, `name:en`, `name:kn`, `name:hi`.
   Bengaluru street signage is bilingual Kannada/English and OSM's `name` here is
   usually English. Workable, but you will hit roads named only in one script and
   have to decide a fallback chain. **Unknown** — I did not measure `name:kn`
   coverage.
4. **POI icon set.** OMT ships classes; sprites you supply. Positron and Liberty
   include usable sprite sheets, so this is closer to free than not.

**Honest split: roughly 80% of Google's map readability is free, the last 20% is
weeks and never finishes.** For a phone screen you would look at while stopped,
80% is plenty. And note carefully — *none of this reaches the handlebar display*,
which renders line segments the ESP32 draws itself (§7). **The entire cartography
question is about the phone screen, which is the screen this project explicitly
does not want the rider looking at.** That is a large clue about where §5 lands.

---

## 3. Routing and guidance

### 3.1 Which engines genuinely run offline on Android in 2026

This is the section that changed most against expectation. **Three of the four
candidates do not run offline on Android, and the one that does is the one the
prior document dismissed in two sentences.**

| Engine | Offline on Android in 2026? | Evidence |
|---|---|---|
| **BRouter** | **Yes, today, no work.** | MIT, pure Java, 703 stars, last push 2026-08-17. Ships an Android app + AIDL service. Data is 5°×5° `.rd5` segments. |
| **GraphHopper** | **No — and worse than "unsupported".** | `pom.xml` line 19: `<maven.compiler.target>25</maven.compiler.target>`, and `<release>25</release>` on the compiler plugin. |
| **Valhalla** | **Not practically.** | README: *"is also used on iOS and Android devices"*, but there is no Android artifact, no Gradle module, and no maintained binding. |
| **OSRM** | **No.** | Server-side C++ with a preprocessing pipeline sized for datacentres. No mobile story, none attempted. |

**GraphHopper is now hard-blocked, not merely unsupported.** The docs say
*"Offline routing is [no longer officially supported] but should still work as
Android supports most of Java"* ([docs/index.md][ghdocs]) and the last shipped
`graphhopper-android` APK was **1.0, May 2020** — current is **11.0, Oct 2025**.
But the compiler target is the decisive fact: **class files at Java 25 bytecode
cannot be processed by Android's D8/R8**, whose desugaring tops out well below
that. You would have to fork GraphHopper and recompile the whole core at a lower
`--release`, permanently, against a moving upstream. *(Verified: the `pom.xml`
values. Inferred: that D8 rejects them — I did not run a build.)* **Cross
GraphHopper off.**

**Valhalla on Android is a myth with a POC behind it.** Searching GitHub for
bindings returns Python (70★), Rust (20★), Go, and Raku — and for
Android/Kotlin only `Rallista/ValhallaAndroidPOC` (**2 stars, last pushed
Oct 2024**, self-described as *"a poc/playground app to figure out how to
properly produce a trimmed down offline route generator on android"*) and
`Scoova/scoova-routing-android` (**0 stars**). Nobody has shipped a maintained
Valhalla-for-Android library. You would be doing NDK bring-up of a large C++
codebase with a tile-building pipeline — genuinely weeks, and then you own it.

**BRouter is the answer, and the prior document was wrong about it.**
`ARCH_ANDROID_AUTO.md` §2.1 says BRouter *"produces no turn instructions at
all"* and is *"a bicycle route planner, not a guidance engine."* **That is out
of date.** `brouter-core/.../VoiceHint.java` defines a full maneuver enum:

```
C=1 continue      TL=2 turn left      TSLL=3 slight left   TSHL=4 sharp left
TR=5 turn right   TSLR=6 slight right TSHR=7 sharp right
KL=8 keep left    KR=9 keep right     TLU=10 U-turn        TRU=11 right U-turn
OFFR=12 off route RNDB=13 roundabout  RNLB=14 rndb left    TU=15 180° U-turn
BL=16 beeline     EL=17 exit left     ER=18 exit right     END=100
```

`turnInstructionMode` appears in 27 files including `FormatJson.java`,
`FormatGpx.java`, `VoiceHintList.java`, and every car profile
(`car-vario.brf`, `moped.brf`, `shortest.brf`). **Verified by reading the
source.** Eighteen maneuver types, including keep-left / keep-right / sharp /
exit — all four of which `NAV_DATA.md` lists as *"not yet captured"* from
Google's icon hashes. And `OFFR=12` is off-route detection built into the
router.

**Data size, measured today:**

| Archive | Coverage | Size |
|---|---|---|
| BRouter `E75_N10.rd5` | 75–80 E, 10–15 N — all of Bengaluru, most of Karnataka | **57.4 MB** |
| BRouter `E75_N5.rd5` | southern tip | 14.8 MB |
| OsmAnd `India_karnataka_asia_2.obf` | Karnataka: map + roads + POI + transport + **address** | **327.8 MB** unpacked (169.6 MB zipped), dated 01.08.2026 |
| OsmAnd `…road.obf` (roads only) | Karnataka | 199.1 MB unpacked |

Verified by `HEAD` against `brouter.de/brouter/segments4/` and by reading
`download.osmand.net/get_indexes?xml`.

**So the realistic offline-routing shortlist is two entries: BRouter, or fork
OsmAnd.** OsmAnd already ships a complete, working, offline turn-by-turn engine
for Karnataka with address search, in 328 MB, on Android, today — and
`ARCH_ANDROID_AUTO.md` §2.4 already costed widening its AIDL at 15–30 h. That is
not "build your own nav app"; that is "use the one that exists."

### 3.2 What each returns for turn-by-turn

| | Maneuver types | Street names | Per-step geometry | Lane guidance | Junction structure |
|---|---|---|---|---|---|
| **BRouter** (on-device) | 18-value enum | **No** | yes — full track, hints carry point index | no | no |
| **Valhalla** (server) | ~37 types, `sign` object, `roundabout_exit_count` | yes | `begin_shape_index` / `end_shape_index` into polyline6 | build-option only | **yes**, via `trace_attributes` node `intersecting_edge.begin_heading`, `node.fork` |
| **OSRM** (server) | type + modifier + exit | yes | per-step `geometry` | optional `lanes[]` | **best** — `intersections[]` with `bearings[]`, `entry[]`, `in`/`out` |
| **GraphHopper** (blocked on Android) | instruction sign enum | yes | per-instruction interval | no | no |
| **OsmAnd** (on-device) | internal `TurnType` | **yes** | yes, internal | yes (widget exists) | not exposed via AIDL |

Valhalla/OSRM detail is unchanged from `ARCH_ANDROID_AUTO.md` §2.1 and is
verified there; I did not re-verify.

**The BRouter gap that matters: no street names.** I read `FormatJson.java` —
every `name` field in the output is a track, POI, or waypoint name, never a road
name. BRouter's `.rd5` format stores routing costs, not `name` tags. So an
offline BRouter build gives you *"turn left in 200 m"* and never *"onto Old
Madras Road."* Given §4.3 measured 65.5% arterial name coverage in OSM, the data
exists — BRouter just discards it. Recovering it means joining BRouter's
geometry back against your own tile extract, which is exactly the §ARCH_ANDROID_AUTO
2.2 machinery. **Doable, but it is a real extra component, not a config flag.**

### 3.3 MapLibre Navigation Android — real, complete, and needs a server

**Verified from the repository, 28 Aug 2026.** MIT, no telemetry, 199 stars,
**v5.0.0 released 2026-08-26 — two days before this document**, after fourteen
prereleases spanning Apr 2025 → Aug 2026.

Modules on Maven Central under `org.maplibre.navigation`:

| Module | Contents |
|---|---|
| `navigation-core` | KMP. Route processing, `OffRouteDetector`, `ToleranceUtils`, `NavigationRouteProcessor`, `NavigationEventDispatcher`. Fully FLOSS on Android — Google Play Services location was moved *out* in pre13. |
| `navigation-ui-android` | `NavigationView`, `NavigationViewModel`, `InstructionView`, and `voice/` — `SpeechPlayer`, `AndroidSpeechPlayer` (platform TTS), `NavigationSpeechPlayer`, `SpeechAnnouncement`. |
| `navigation-location-gms-android` | optional FusedLocationProvider backend |

So the direct answers to the questions asked:

- **Working turn-by-turn UI?** Yes. `libandroid-navigation-ui` is a complete
  instruction banner + maneuver view + route line, inherited from Mapbox
  Navigation SDK v0.19. The README's *"we completely removed the UI part"* refers
  to the **core** module; the UI module exists alongside it.
- **Voice?** Yes, via `AndroidSpeechPlayer` on platform TTS. Not cloud voices —
  which is the right answer for a phone in a pocket under a helmet.
- **Off-route detection?** Yes. `OffRouteDetector` + `OffRouteListener` +
  `OffRouteCallback` in `navigation-core`, with unit tests.
- **Rerouting?** The plumbing is there (41 code hits for "reroute", including
  localised strings in ~10 languages), but rerouting means *calling the
  Directions API again*. Which is the catch.

**The catch, and it is the whole story.** MapLibre Navigation speaks the
**Mapbox Directions JSON response format**. It does not compute routes. Its own
sample app ships a preconfigured Valhalla example and a GraphHopper
`/navigate` example — both **hosted HTTP services**. GraphHopper's own docs point
at this SDK and at Ferrostar under the heading *"Online"*, and put offline in a
separate section that says offline is unsupported.

**Ferrostar** (`stadiamaps/ferrostar`, 412★, v0.54.0 Aug 2026) is the modern
alternative and has exactly the same shape. Its guide states plainly that it is
*not* *"a routing engine, basemap, or search solution"* and offers *"want to
bring your own offline routing? Can do"* — i.e. an interface, not an
implementation.

**So the 2026 open-source navigation stack has a hole exactly where this project
needs substance.** UI, voice, off-route, route-progress: solved, MIT, polished.
The routing engine underneath, running offline on the phone: nobody ships one
that these SDKs can talk to. You would write the adapter that turns BRouter's
`VoiceHint` list into Mapbox Directions JSON yourself — and BRouter has no street
names to put in it (§3.2).

### 3.4 Rerouting latency on-device

**Largely unknown, and I will not pretend otherwise.**

What is measurable:

- Google Maps' reroute recovery is **300–600 ms**, measured on real rides
  (`NAV_DATA.md`). That is the bar.
- BRouter's `.rd5` for the whole region is 57 MB and is memory-mapped; the
  engine is A\* over a routing-cost graph with no contraction hierarchies. For a
  short reroute (a few hundred metres to rejoin the corridor) this should be well
  under a second on an S24+. For a fresh 12 km cross-city route, BRouter's own
  reputation is "a few seconds", and it degrades with distance because it has no
  CH/MLD preprocessing. **Inferred from architecture, not measured.**
- OsmAnd reroutes offline on far weaker phones than an S24+ and is subjectively
  fast. **No number.**

The honest engineering position: **on-device rerouting is very likely fine for
this use case and I could not find a published benchmark for any of these
engines on modern Android hardware.** It is a one-evening experiment (install
BRouter, feed it two points, time it) and it should be done before committing.
It is *not* the risk that decides this study — §4 is.

---

## 4. What you lose by leaving Google

### 4.1 Live traffic

*(pending)*

### 4.2 Search and geocoding

*(pending)*

### 4.3 Road network quality in Bengaluru — measured 28 Aug 2026

**Verified — I ran these.** Same bbox, same Overpass snapshot
(`2026-08-28T04:43:31Z`). Berlin `(52.35, 13.10, 52.68, 13.77)` is included as a
calibration control: comparable bbox area (Berlin ≈ 1,666 km², Bengaluru
≈ 2,172 km²), and a city where OSM is uncontroversially good enough to navigate
by.

| Measure | Bengaluru | Berlin |
|---|---:|---:|
| Drivable ways incl. `service` | 210,170 | — |
| Drivable ways excl. `service` | 173,760 | — |
| Arterials (`motorway…tertiary`, incl. `_link`) | 17,144 | 39,034 |
| ...of those, `name` present | 11,237 (**65.5%**) | — |
| All drivable excl. service, `name` present | 25,269 (**14.5%**) | — |
| `oneway=yes\|-1` on any highway | 16,969 | — |
| `oneway` tag present, drivable excl. service | 15,402 (**8.9%**) | — |
| `type=restriction` relations | **333** | **1,795** |
| Restrictions per arterial way | **1.94%** | **4.60%** |
| Highways with `maxspeed` | **4,218** | **109,730** |

Four findings, in descending order of how much they should worry you.

**1. Turn restrictions are thin, and this is a routing-correctness problem.**
333 turn restrictions for a metro with 17,144 arterial ways. Berlin has 5.4× as
many over 2.3× the arterials. Bengaluru is a city of no-left-turn boards,
signal-controlled U-turn-only junctions and one-way loops that change by time of
day — the real count of legal turn restrictions here is in the thousands. An
offline router with 333 of them **will route you through turns you cannot
legally make**, and you will discover this at the junction, on a motorcycle,
with the display telling you to turn. Google models these; OSM here does not.
This is the single most concrete thing you lose. *(Verified count; the inference
that real restrictions vastly exceed 333 is judgement, not measurement.)*

**2. `maxspeed` is effectively absent — 2.0% of drivable ways.** Berlin is at
roughly 26× the absolute count. So a speed-limit display sourced from OSM, which
`NAV_DATA.md` suggested as the workaround for Maps never publishing it, does not
work in Bengaluru either. Cross it off both lists.

**3. Road naming is fine on arterials, poor everywhere else.** 65.5% of
arterials carry a `name`, which is enough for "turn right onto Old Madras Road"
to work most of the time on the roads you would actually be guided along. But
14.5% across the full drivable network means residential turn instructions will
frequently be "turn right" with no road name — precisely the case
`NAV_DATA.md` parser rule 4 already handles for Google's output, so the display
degrades gracefully rather than breaking. Annoying, not disqualifying.

**4. `oneway` at 8.9% of drivable ways is not the alarm it looks like.** Most
residential streets genuinely are two-way, and untagged means two-way by
default, which is usually right. 16,969 explicit one-way ways is a substantial
dataset. This one is closer to the `bridge` case than the `turn:lanes` case:
absence is mostly meaningful. **But** Bengaluru's one-way network is heavily
time-of-day dependent (peak-hour reversals on several corridors), and OSM's
`conditional` tagging for that is essentially nonexistent here — I did not
measure it, but 333 total turn restrictions makes it implausible that
`oneway:conditional` is populated.

**The honest summary of this section:** the *geometry* of Bengaluru's roads in
OSM is excellent — 210 k ways, 810 k buildings, dense arterial naming. The
*rules* are not. Geometry is what §ARCH_ANDROID_AUTO 2.2 needs and it is
comfortably there. Legal-turn correctness is what a router needs and it is
measurably absent. **That split is the whole answer to this study**, and it maps
directly onto options A/B/C in §5.

### 4.4 Live incidents and closures

*(pending)*

---

## 5. Three options compared

*(pending)*

---

## 6. Phased plan for C

*(pending)*

---

## 7. The moving map on the display

*(pending)*

---

## 8. What I could not confirm

*(pending)*

---

## Sources

*(pending)*
