# Building our own navigation app

Architecture feasibility study, 28 Aug 2026.

Question asked: **should we stop scraping Google Maps and build our own
navigation app on open-source maps — a real moving map with buildings, proper
cartography, turn-by-turn and search — and feed the handlebar display from data
we own end to end?**

Short answer: **no.** Build the road ahead from our own tiles (§5 option A/B,
80–130 h); keep Google's traffic. Every number below was measured on 28 Aug 2026
against the project's standard Bengaluru bbox unless marked *inferred* or
*unknown*.

---

## 1. Recommendation

**Don't.**

Not "not yet", and not "it's too much work" — the user has said multi-month is
acceptable and the estimate below is honestly reachable. **Don't, because the
thing you would be building is worse at the job in this specific city, and the
things it would add are things Bengaluru's OSM data cannot support.**

The measurements that produce that answer, all run today against the project's
standard bbox:

| What was hoped for | What the data says |
|---|---|
| Buildings and 3D cartography | **810,507 footprints** — excellent. But `building:levels` **1.69%**, `height` **0.18%**. 3D extrusion is dead. (§2.3) |
| Turn-by-turn from a real router | **333 turn restrictions** in the whole metro, against Berlin's 1,795 over 2.3× the arterials. An offline router will route you through turns you cannot make. (§4.3) |
| Speed limits from OSM | **`maxspeed` on 2.0%** of drivable ways. Berlin has 26× the absolute count. Dead. (§4.3) |
| Live traffic from somewhere open | **Nothing exists.** OpenTraffic is defunct; GraphHopper's curated open-traffic list contains zero India entries — its only "India" match is *Indiana*. (§4.1) |
| Search that handles Indian addresses | **Better than expected** — Nominatim and Photon both resolve *Silk Board Junction* and *Sony World Signal* exactly. But ~39 k POIs vs Google's hundreds of thousands, and `addr:housenumber` on **31,664** records for a metro of 13 million. (§4.2) |
| A mature offline routing engine for Android | **There isn't one worth the name.** GraphHopper's `pom.xml` targets Java 25 bytecode, which D8 cannot process; Valhalla-on-Android is a 2-star POC last touched in 2024; OSRM has no mobile story. Only BRouter runs today. (§3.1) |

And the structural argument, which matters more than any single number:

**You already have the one thing that cannot be replaced.**
`android.progressSegments` delivers a metre-indexed live traffic profile of the
road ahead, from the best traffic dataset in existence for this city, over a
channel that costs nothing. Google's Bengaluru advantage is not its map — OSM's
Bengaluru geometry is genuinely excellent — it is **13 million phones reporting
which roads are currently passable.** Metro barricading, monsoon flooding and
VIP closures are not in any open dataset and never will be. Building your own
app means giving that up, permanently, in the one city where it matters most.

**And the marquee features of an "own app" do not reach the display.** A moving
map with buildings and proper cartography is a *phone-screen* feature. The ESP32
has no PSRAM and no framebuffer; `FEATURES.md` rejected raster on three
independent grounds and the handlebar renders line segments it draws itself.
**You would spend 300–435 hours building a beautiful screen that this project
was specifically designed to stop you looking at.**

### What to do instead

1. **Phase 0 first, and it costs nothing.** Install OsmAnd (`India_karnataka_asia_2.obf`,
   328 MB) and BRouter (`E75_N10.rd5`, 57 MB) on the S24+ and ride your normal
   commutes for two weeks with offline routing alongside Google. Count the
   disagreements. **This is a free, code-free experiment that either kills option
   C from your own city's evidence or overturns this recommendation.** §4.3
   predicts it fails; you should find out rather than take my word.
2. **Build Phases 1–3 — option A, then option B.** Tile extract and phone map
   view (30–50 h), the vector window to the display (25–40 h), then map-matching
   to resolve which branch the route takes (25–40 h). **80–130 hours, 10–16
   weeks of evenings**, delivering true junction geometry with flyovers reading
   correctly, plus the `GEOM_TAKEN` flag `geom.h` was already written to expect —
   while Google keeps doing routing, traffic, closures and destination entry.
3. **Do not cross the Phase 4 line** (search and destination entry) unless
   Phase 0 came back positive.
4. **On the moving arrow: yes it can, no it shouldn't.** The ESP32 has the frame
   rate (~15–17 ms/frame, a 60 FPS ceiling, computed in §7.3). Step the picture
   on new data instead — 1 Hz inside 150 m of a maneuver, slower away from it.
   Smooth motion buys nothing and spends the exact resource (`FEATURES.md`:
   *"foveation, which is the resource the whole design is trying to protect"*)
   that the whole device exists to conserve.

### The honest counter-argument

There is one, and it deserves stating rather than burying. **Only option C can
deliver the next maneuver** — "left then right in 80 m" — which `NAV_DATA.md`
verified is unobtainable from Google by any means short of Android Auto. It is
also the only option immune to Maps breaking its notification format, which it
does roughly annually and which today takes the whole display down.

Those are real. They are worth **three items** against **four** — traffic,
closures, legal turns, and Google's India-specific two-wheeler routing — every
one of which changes where you actually ride. And the fragility half of the
argument is already largely answered by option A: once the geometry comes from
local tiles, a Maps break costs the maneuver arrow and the distance while **the
road ahead keeps drawing**.

**Build the road ahead. Keep Google's traffic.**

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

This section decides the answer, so it gets the most measurement and the least
charity.

### 4.1 Live traffic — no free or open source exists for Bengaluru

**The direct question: is there ANY free/open real-time traffic source for
Bengaluru? No.**

- **OpenTraffic** — the World Bank / Mapzen project that was going to be the open
  answer — is **marked defunct on the OSM wiki**. Repos survive, the data feed
  does not.
- **GraphHopper's `open-traffic-collection`** is the canonical curated list of
  open traffic data sources. I read the whole README (122 lines) and grepped it:
  **the only match for "India" is "Indiana."** Zero entries for India, zero for
  any Indian city. That is about as clean a negative as this kind of question
  admits.
- **OSM itself has no real-time layer.** By design.
- **Waze** has no public feed; its data-sharing programme is for government
  partners.

Commercial free tiers, which are not "open" but are free:

| Provider | Free tier | Bengaluru coverage |
|---|---|---|
| **TomTom** | Traffic Flow & Incidents **tiles: 200 K/month**; Traffic Incident Details **2.5 K/month**; Navigation/routing 20 K/month ([pricing][ttprice]) | **Yes** — TomTom publishes a Bengaluru city page in its Traffic Index ([link][ttbeng]), which it could not do without probe coverage |
| **HERE** | **Unknown.** Three fetch attempts to HERE's pricing pages returned `ECONNRESET` or 404. I could not confirm 2026 terms. | unknown |

**200 K traffic tiles/month is genuinely generous** — that is ~6,600/day, and a
single ride pulling a tile per minute for an hour uses 60. So a TomTom traffic
overlay on your own map is *technically* within the free tier for one rider.

**But read what you would actually be building.** You would leave Google in
order to depend on TomTom, under terms whose caching and storage restrictions I
did not verify, with a key that can be revoked, for a personal app — which is
strictly more vendor exposure than today, not less. And the fragility argument
that carried §ARCH_ANDROID_AUTO 2.2 runs *backwards* here: today's Google
dependency is a notification format, which breaks visibly and is fixed in an
evening; a TomTom dependency is an account and a quota.

**And here is the fact that should dominate this whole document.** The project
**already receives a live traffic profile of the road ahead, in metres, for
free**, in `android.progressSegments` — an ordered `{length, colorInt}` array
summing exactly to `progressMax`, with grey/blue/amber/red severity
(`NAV_DATA.md`). Google's Bengaluru traffic is the best in existence, it is
already arriving over a channel that costs nothing, and `NAV_DATA.md` records
that the project chose not to render it *on display-design grounds, not
availability grounds*.

**So "live traffic" is not a thing you would gain by building your own app. It
is a thing you already have and would give up.** In Bengaluru — where §4.3
counted 173,760 drivable ways and the entire riding experience is congestion
routing — this is the single largest loss on the list.

### 4.2 Search and geocoding — much better than expected, with one real catch

I tested this rather than assumed it. Nine live queries against
`nominatim.openstreetmap.org` (with a UA, `countrycodes=in`) and
`photon.komoot.io` (biased to 12.97 N, 77.59 E), 28 Aug 2026.

| Query | Nominatim | Photon |
|---|---|---|
| `100 Feet Road Indiranagar Bangalore` | ✅ 100 Feet Road, Indiranagar | ✅ |
| `Horamavu Agara Main Road Bangalore` | ✅ exact | ✅ |
| `3rd Cross Koramangala 5th Block Bengaluru` | ✅ 3rd Cross Rd, Koramangala 5th Block | ✅ (street) |
| `Phoenix Mall of Asia Bengaluru` | ✅ exact | ✅ + street |
| `Corner House Jayanagar Bangalore` | ✅ with house number, 26th Main Rd | ✅ |
| `Silk Board Junction Bangalore` | ✅ **exact, as a named junction** | ✅ |
| `Sony World Signal Koramangala` | ✅ **exact colloquial landmark** | ✅ |
| `Anand Sweets Indiranagar Bangalore` | ❌ no result | ✅ found |
| `742 12th Main HAL 2nd Stage Indiranagar` | ⚠ falls back to 12th Main Rd | ⚠ wrong POI |

**This is a genuine surprise and it must be reported as one.** Colloquial
Bengaluru landmarks that exist in nobody's postal address — *Silk Board
Junction*, *Sony World Signal* — resolve exactly. Locality + cross-road queries
resolve. A 2024-vintage mall resolves. The house-number case degrades to the
correct street, which for navigation is *fine*: you ride to 12th Main and look.

This is consistent with §4.3's 65.5% arterial name coverage. **Destination entry
on OSM data in Bengaluru is a solved problem, not a blocker.** I expected to
write the opposite.

The catches, in order:

1. **POI depth is ~40 k, against Google's hundreds of thousands.** Measured in
   the bbox: **27,589** `amenity` + **11,566** `shop` = **39,155** POIs, and
   **9,721** named buildings (1.20% of 810 k footprints). Google has every
   tailor, every dark kitchen, opening hours, and phone numbers. If your
   destination is a road, a landmark, or a known place, OSM works. If it is
   "that Andhra mess near Bellandur", it does not.
2. **`addr:housenumber` = 31,664 across a metro of ~13 million.** House-number
   geocoding does not exist here in any usable sense. This is not an OSM-India
   failing so much as a fact about Indian addressing.
3. **Nominatim's policy forbids the thing an app needs.** Verbatim from the
   [OSMF usage policy][nompol]: *"No heavy uses (an absolute maximum of 1 request
   per second)"*, and **"Auto-complete search"** is listed under unacceptable use
   — *"this is not yet supported by Nominatim and you must not implement such a
   service on the client side using the API."* Violators *"will get banned."*
   **So you cannot legitimately build a search box on the public Nominatim.**
4. **Photon is the practical answer, and it is a server.** Apache-2.0, 3,006★,
   last push 2026-08-18; the public `photon.komoot.io` is offered *"as long as
   the number of requests stay in a reasonable limit"* — fine for one rider,
   explicitly not guaranteed. Self-hosting India: GraphHopper publishes
   `photon-db-in-250720.tar.bz2` at **780 MB compressed**, but it is dated
   **2025-07-21 — thirteen months stale**. Planet self-host wants *"about 95 GB
   disk"* and *"at least 64 GB RAM"*. **Not a phone-side option.**
5. **Pelias** is a full Elasticsearch stack. Two sentences and no more: it is
   heavier than Photon for the same job and there is no reason to prefer it here.

**Which leaves the only coherent offline answer: OsmAnd's `.obf`.** The Karnataka
file is 327.8 MB and its own manifest says *"Map, Roads, POI, Transport,
**Address** data"* — a complete offline search index for the state, already
built, updated monthly (current file dated 01.08.2026). Building your own
offline geocoder from a tile extract, when this exists, would be inventing a
wheel someone ships for free.

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

Shorter than §4.1 because the answer is the same and harder.

**Nothing open exists.** TomTom's Traffic Incidents endpoint covers *"closed
roads, lane closures, construction zones, and accidents"* with per-minute
updates, on a 2.5 K/month free tier for the details API — that is ~83/day, which
is fine for polling every few minutes during a ride. HERE is unknown (§4.1).
Bengaluru Traffic Police runs its own systems; **I could not find any public API
or open feed, and I am recording that as unknown rather than as a negative** —
absence of a documented API is weak evidence.

But the practical loss is worse than the API question suggests, because
Bengaluru's real closures are not incidents in a database:

- **Metro construction.** Namma Metro Phase 2/3 barricading reroutes arterials
  for months at a time. OSM eventually catches up; it catches up in weeks, and
  Google catches up in days because millions of phones stop driving through.
- **Rain flooding.** Seasonal, hyperlocal, and only ever visible in probe data.
- **Event and VIP closures.** Hours of notice, no data anywhere except Google's
  own crowd behaviour.

This is the same asymmetry as §4.1 with a sharper edge: Google's advantage in
Bengaluru is not its map, it is **13 million phones telling it which roads are
currently passable**. There is no open substitute, no free substitute, and no
amount of engineering that manufactures one.

**And note the reinforcing detail from §4.3: 333 turn restrictions.** So an
own-app rider is exposed twice — routed through turns that are illegal, and
routed onto roads that are closed. Google is wrong about neither, usually.

---

## 5. Three options compared

### 5.1 The three, defined

- **A — Keep scraping, add the vector window.** Today's notification parser
  unchanged; the phone additionally holds an offline OSM tile extract, queries it
  against its own GPS at ~1 Hz, and ships ~726 B of rider-local line segments to
  the ESP32. `ARCH_ANDROID_AUTO.md` §2.2, the plan of record.
- **B — Hybrid.** Google keeps routing, traffic and destination entry; own tiles
  drive the map.
- **C — Full own app.** MapLibre map, offline tiles, own routing, own search, own
  guidance, own everything, feeding the display from data we control end to end.

### 5.2 Is B even coherent? Yes — but not the version you would first write

**The naive B is incoherent, exactly as suspected.** The notification carries no
route polyline; `NAV_DATA.md` verified that against a complete extras dump. So a
phone-screen moving map built on own tiles would show your position and the
roads around you and **could not draw where you are going**. That is a map
strictly worse than opening Google Maps, and it should not be built.

**But there is a second B, and it is the interesting one.** You do not need the
polyline if you can *infer the next edge*. Google tells you, at ~1 Hz: the
maneuver type (icon hash), the distance to it (10 m resolution inside 300 m),
and the road you are turning onto (`nowbarSecondaryInfo`, "towards Moulana Azad
Rd"). Your own tiles tell you every road around you and its name. **Map-match
the GPS trace to your local graph, look forward `distance` metres, and find the
branch whose name matches and whose turn angle matches the maneuver.** That
resolves *which specific branch of this junction the route takes* — without
routing, without a destination, without leaving Google.

Two reasons to take this seriously:

1. **The firmware already has the flag.** `firmware/navigator/geom.h`:
   `GEOM_TAKEN = 0x01, // the branch the route takes - drawn thick`. The renderer
   was built expecting someone to tell it which branch is the route. **Option A
   alone can only guess it from the maneuver direction; B can determine it.**
2. It degrades safely. If the match fails, you send the window with no
   `GEOM_TAKEN` bit and you are back to option A, which still draws the junction.

B is therefore not a third architecture. **B is A plus a map-matcher**, and it is
the natural second phase of A rather than a competing plan.

### 5.3 The comparison

Hours are marginal — work still to do from today, given that `geom.cpp` and the
BLE framing already exist.

| | **A** vector window | **B** A + map-matched branch | **C** full own app |
|---|---|---|---|
| Phone: tile store, MVT/PMTiles decode, clip, RDP, rider frame | 25–40 h | 25–40 h | 25–40 h (same code) |
| Phone: tile-cache protocol to ESP32 | 5–10 h | 5–10 h | 5–10 h |
| ESP32 render | **done** (`geom.cpp`) | done | done |
| Map-matching + maneuver→branch resolution | — | 25–40 h | included in guidance |
| MapLibre map view + offline style | — | — | 30–45 h |
| Navigation style tuning (§2.4) | — | — | 15–30 h |
| Search / destination entry | — | — | 40–60 h |
| Routing engine integration (BRouter or OsmAnd fork) | — | — | 30–60 h |
| Guidance layer: VoiceHint→state machine, street names by tile join | — | — | 40 h |
| Rerouting, off-route, route lifecycle | — | — | 25 h |
| Voice (platform TTS) | — | — | 5 h |
| Foreground service, battery, lifecycle hardening | 5 h | 5 h | 20 h |
| **Real-ride debugging** — the line everyone omits | 10 h | 15 h | **60–100 h** |
| **Total marginal** | **45–65 h** | **75–110 h** | **295–435 h** |

At a steady 8 h/week of evenings: **A ≈ 6–8 weeks. B ≈ 9–14 weeks. C ≈ 9–13
months.**

### 5.4 What the rider actually gets

| Capability | A | B | C |
|---|---|---|---|
| Maneuver arrow + distance + road name + ETA | ✅ Google | ✅ Google | ✅ own |
| **Live Bengaluru traffic** | ✅ Google, and `progressSegments` is a free metre-indexed profile | ✅ | ❌ **nothing open exists (§4.1)** |
| **Closures, metro barricading, flooding** | ✅ Google | ✅ | ❌ (§4.4) |
| **Correct turn restrictions** | ✅ Google | ✅ | ⚠ **333 in the whole metro (§4.3)** |
| **Two-wheeler routing** (Google's India-specific mode) | ✅ | ✅ | ❌ BRouter `moped.brf` is not this |
| Destination entry, voice, "navigate to…" | ✅ Google | ✅ | ⚠ works better than expected (§4.2), still ~40 k POIs vs Google's hundreds of thousands |
| **Junction geometry, flyover vs road beneath** | ✅ | ✅ | ✅ |
| **Which branch the route takes** (`GEOM_TAKEN`) | ⚠ guessed from maneuver | ✅ **determined** | ✅ |
| **Route line ahead on the display** | ❌ local roads only | ⚠ next edge only | ✅ full polyline |
| **Next maneuver** ("left then right in 80 m") | ❌ verified impossible | ❌ | ✅ **only C delivers this** |
| Lane guidance | ❌ | ❌ | ❌ — 0.52% `turn:lanes`, closed in FEATURES.md |
| Speed limit | ❌ | ❌ | ❌ — **2.0% `maxspeed` (§4.3)**, dead in OSM too |
| 3D buildings | ❌ | ❌ | ❌ — **0.18% `height` (§2.3)** |
| Survives a Maps notification-format break | partly — geometry survives | partly | ✅ fully |

### 5.5 Reading the table

**C's honest gain list is three items long:** the next maneuver, a real route
polyline on the display, and immunity to Maps format churn. Everything else in
the "own app" pitch — buildings, cartography, lane guidance, speed limits — is
either unsupported by Bengaluru's OSM data (measured, §2.3 and §4.3) or already
available from Google.

**C's loss list is four items long and every one of them is a thing that changes
where you ride:** traffic, closures, legal turns, and two-wheeler routing. In a
city whose defining navigational fact is congestion, trading Google's traffic for
a self-built router with 333 turn restrictions is not a lateral move.

**And the cartography question dissolves on inspection.** §2.4 concluded that
80% of Google's map readability is free from an OpenMapTiles style and the last
20% is weeks of work — but **none of it reaches the handlebar.** The ESP32 draws
line segments it renders itself; it has no PSRAM, no framebuffer, and
`FEATURES.md` already rejected raster on three independent grounds. A beautiful
moving map with buildings and proper cartography is a *phone-screen* feature, and
this project's entire premise is that the rider should not be looking at the
phone screen. **You would spend 300+ hours to build a screen you designed a
device to avoid looking at.**

---

## 6. Phased plan for C

Written as asked, and ordered on one principle: **every phase must be worth
having on its own, and quitting after any phase must waste nothing.** That
principle is what makes this plan safe to start even though §1 recommends not
finishing it — the first four phases are option A and option B, which are worth
building regardless, and the fork only happens at Phase 5.

### Phase 0 — the free experiment. 0 h of code, two weeks of riding.

**Do this before anything else, and it may end the project.**

Install **OsmAnd** and **BRouter** on the S24+. Download
`India_karnataka_asia_2.obf` (328 MB) and `E75_N10.rd5` (57 MB). Set OsmAnd to
motorcycle/moped profile. **Ride your normal commutes for two weeks with OsmAnd
routing and Google Maps open side by side, and keep a tally:**

- how often the offline route is materially worse (longer, through a jam Google
  avoided, through a turn you cannot legally make);
- how often it routes onto a road that is barricaded or flooded;
- how often destination entry fails to find the place you meant;
- how often the two agree, which is the number that would justify continuing.

**This costs nothing, needs no code, and is the highest-information hour in this
entire document.** §4.1, §4.3 and §4.4 predict this experiment fails. If it
fails, options C dies for £0 and you have your answer from your own city rather
than from a table of Overpass counts. If it *succeeds* — if offline Karnataka
routing turns out to be fine on the roads you actually ride — then every hours
estimate below becomes worth spending, and you will know that on evidence.

Nothing else in this plan should start until Phase 0 has run.

### Phase 1 — tile extract + phone-side map view. 30–50 h. *Useful alone.*

Build the Bengaluru/Karnataka extract with Planetiler or `pmtiles extract`
(§2.2), put it on the phone, and render it with MapLibre Native
`org.maplibre.gl:android-sdk:13.5.1` against a local `pmtiles://` source.

Independently useful because it is **the debugging instrument for everything
else**, and because it immediately settles the open question
`ARCH_ANDROID_AUTO.md`'s addendum left behind: *are the flyovers on your commute
actually tagged?* Ride NH 44 and NH 75 with the map open and look. Two evenings
of tile work buys the answer to the question the whole geometry feature rests on.

Abandonable: the extract and the pipeline are inputs to Phase 2 regardless.

### Phase 2 — the vector window to the display. 25–40 h. *This is option A.*

MVT/PMTiles decode, clip to the 240 m box, RDP at 3 m, rider-local frame, tile
cache protocol, `0x09 GEOM` packets. `geom.cpp` on the ESP32 already consumes
them. At the end of this phase **the handlebar display draws the shape of the
road ahead, with flyovers reading correctly, while Google keeps doing everything
else.** That is the thing originally asked for.

Stopping here is a good outcome, not a failure.

### Phase 3 — map-matching and the taken branch. 25–40 h. *This is option B.*

Match the GPS trace to the local graph; resolve Google's maneuver + distance +
`nowbarSecondaryInfo` road name onto a specific branch; set `GEOM_TAKEN`. The
display now shows not just the junction but which way through it.

Stopping here is a *very* good outcome. **Phases 1–3 are the recommendation of
§1.**

### Phase 4 — search and destination picking. 40–60 h. *Weakly useful alone.*

Offline search against the extract (or OsmAnd's `.obf` address index), plus a
map long-press pin. At the end you can pick a destination in your own app and it
does nothing with it. This is the first phase whose value is entirely deferred —
**which is exactly why it marks the fork.** Everything before it improves the
current architecture; everything from here replaces it.

### Phase 5 — routing. 30–60 h.

BRouter via its Android AIDL service (cheapest, 18 maneuver types, no street
names) or a fork of OsmAnd's engine (richer, GPLv3, fine for personal use).
Output: a route polyline on the phone map, and — via the machinery Phase 2
already built — **a real route line on the handlebar display**, which no earlier
phase can give.

### Phase 6 — guidance. 40 h. *The moment you could turn Google off.*

Convert the router's output into the `NavState` the display already consumes:
maneuver type, distance to it, road name (joined from your tiles, since BRouter
discards names — §3.2), ETA. **Run it in parallel with the notification scraper
for a month before switching**, logging disagreements. Both sources feeding one
display, with the scraper authoritative, is a safe and very informative state to
live in.

### Phase 7 — rerouting, off-route, voice, lifecycle. 55 h.

`OffRouteDetector` logic (borrow MapLibre Navigation's, MIT), reroute on
detection, platform TTS, foreground service hardening, battery-optimisation
whitelist. Measure reroute latency against `NAV_DATA.md`'s Google baseline of
**300–600 ms**.

### Phase 8 — real-ride hardening. 60–100 h. *Non-negotiable and always underestimated.*

Everything the previous phases got wrong, found at 50 km/h in traffic. Budget
this at roughly a quarter of the whole project or you are not costing it
honestly.

### Totals

| Phases | Delivers | Hours | Evenings at 8 h/wk |
|---|---|---:|---|
| 0 | the decision | 0 | 2 weeks of riding |
| 1–2 | **option A** | 55–90 | 7–11 weeks |
| 1–3 | **option B** | 80–130 | 10–16 weeks |
| 1–8 | **option C** | 295–435 | **9–13 months** |

### What to build first to learn the most

**Phase 0**, and it is not close. Every hour in Phases 1–8 is spent on the
assumption that offline OSM routing in Bengaluru is good enough to ride on, and
that assumption is testable this weekend with two free apps and no code. §4.3
measured 333 turn restrictions and 2% `maxspeed` coverage; Phase 0 turns those
numbers into an experience, which is the only form of evidence that has ever
changed a decision in this project.

Second: **Phase 1's map view**, because it is the instrument through which every
later phase is debugged, and because it independently answers the flyover-tagging
question that `ARCH_ANDROID_AUTO.md` had to leave open.

---

## 7. The moving map on the display

The question asked: **can the handlebar display show a moving arrow like Google
Maps?** Technically yes, comfortably. The rest of this section argues it
shouldn't — and separates the two clearly, because "we can't" and "we
shouldn't" are very different answers and only one of them is true.

### 7.1 Heading-up with a fixed rider marker — already built

`firmware/navigator/geom.h`, verbatim:

> *"Draw into the s-by-s box at (x, y). The rider sits at the bottom centre and
> does not move; the road moves under them, which is the only arrangement that
> needs no interpretation at a glance."*

And on where the rotation happens:

> *"…sends line segments already rotated into the rider's frame: x to the right,
> y forward, decimetres. Rotating on the phone rather than here is deliberate —
> the phone knows the heading, and a heading the device guessed would be a
> confidently wrong drawing, which is the failure this project refuses to ship."*

So the arrangement the question describes — fixed marker, world rotating and
translating beneath it, heading-up — **is the architecture already implemented.**
What is missing is only motion *between* windows.

### 7.2 Where heading comes from — GPS course-over-ground, not the compass

Two candidates, and one of them is disqualified by this project's own prior
finding.

**Phone fused orientation (rotation vector / `TYPE_ROTATION_VECTOR`).** Rejected.
`FEATURES.md` already established, when killing lane guidance, that *"handlebar
mounting makes it worse: the phone measures **steering input** on top of chassis
motion."* That applies with full force here. A handlebar-mounted phone turns
with the bars — through 30°+ at parking speeds and several degrees constantly at
road speed — so its yaw is not the vehicle's heading. On top of that the
magnetometer is sitting on a steel handlebar, near the ignition coil, the
alternator harness and (usually) a USB charger. **A heading-up map slaved to the
phone's compass would rotate when you countersteer.** Confidently wrong, which
is the failure mode `geom.h` names explicitly.

**GPS course-over-ground (`Location.getBearing()`).** This is the right source.
It is derived from the velocity vector, so it is the *vehicle's* heading and is
immune to both handlebar angle and magnetic distortion.

Its weakness is exactly the one the question anticipates: **it is unstable at low
speed**, because bearing is `atan2` of a velocity whose magnitude approaches the
noise floor. Stopped at a signal it is meaningless — `NAV_DATA.md` already
records the related symptom, *"while stationary at a traffic signal the distance
drifted 30 → 40 → 50 m from GPS jitter alone."* Same jitter, and a bearing
computed from it will spin.

**The rule that follows, and it is simple:**

| Speed | Heading source |
|---|---|
| **> ~10 km/h (2.8 m/s)** | GPS course-over-ground, lightly smoothed |
| **< ~10 km/h** | **freeze the last good heading. Do not rotate.** |
| Stopped > ~20 s | freeze, and let `GEOM_MAX_AGE_MS` blank the box if the phone stops sending |

Android exposes `Location.hasBearing()` and, on API 26+,
`getBearingAccuracyDegrees()` — gate on both rather than on speed alone.
*(Inferred design, not measured: I did not test COG stability on the S24+ at
Bengaluru crawl speeds, and that is worth one ride with a logger.)*

Note this is free of new risk: the phone is already the only thing that knows the
heading, and it already does the rotation.

### 7.3 Dead reckoning between windows — cheap, and the arithmetic

Geometry windows arrive every ~3 s in the §2.2 design (~39 B/s with tile
caching). Between them the drawing is frozen. To move it, the ESP32 needs speed
and heading change, which it does not have.

The fix is a small pose packet, sent at 4–5 Hz:

```
[type 0x0A POSE][len=5]
  u16 speed_cm_s        // 0..655 m/s, plenty
  i16 heading_cdeg_delta // change since last window, centidegrees
  u8  dt_ms_x10          // time since last pose
```

5 bytes plus 2 bytes of framing at 5 Hz = **35 B/s**, which roughly doubles the
geometry channel and remains under 2% of the conservative 2 kB/s budget
(`ARCH_ANDROID_AUTO.md` §1.2). The ESP32 then translates the committed point set
by `v·Δt` along `+y` and rotates by the accumulated heading delta before drawing.

**Redraw cost, computed.**

| Step | Work | Time |
|---|---|---|
| Transform 150 points (rotate + translate) | ~600 multiply-adds | **< 0.5 ms** |
| Draw 40 ways, halo + ink = 80 clipped strokes into the sprite | ~30–40 k sprite pixel writes (RAM) | **~3–5 ms** |
| Push a 140×140 box to the panel | 19,600 px at the measured **~1,700 px/ms** | **~11.5 ms** |
| **Total per frame** | | **~15–17 ms → ~60 FPS ceiling** |

Cross-checked against `FEATURES.md`, which measured ~16–20 FPS for ~200 points
*with heading-up rotation, full screen*; the geometry box is a quarter of the
screen, so 20–30 FPS with everything else the display is doing is a safe claim
and 60 FPS is the arithmetic ceiling.

**So: frame rate is not the constraint.** The ESP32 can animate this smoothly.
The 45 ms figure in `HARDWARE.md` is a *full-screen* push; the geometry box costs
a quarter of that.

### 7.4 Should it move? No — and the project already answered this

`FEATURES.md` is unusually explicit, and every relevant line points the same way:

- *"continuous traffic display (invites study, not glance)"* — refused.
- *"persistent battery percentage (a re-glance magnet — show it below 20%
  only)"* — refused.
- *"Full-block luminance inversion is the single most blur- and glare-robust
  encoding this panel has — large, low-spatial-frequency, and detected
  peripherally **without costing a glance**. Small text is the opposite: it needs
  foveation, which is the resource the whole design is trying to protect."*
- *"**Under 100 m to a turn: blank. Always.**"*

**Motion is the strongest involuntary attentional capture signal in peripheral
vision — stronger than colour, stronger than contrast.** A continuously sliding
map sits in the rider's lower peripheral field pulling foveation away from the
road, repeatedly, for the entire ride. That is precisely the resource
`FEATURES.md` says the whole design exists to protect, and a smooth-scrolling map
spends it continuously in exchange for information that is not changing —
because at 50 km/h with a 120 m box, **the picture is meaningfully the same for
several seconds at a time.**

Two further arguments against, both physical:

- **Vibration.** `FEATURES.md` already ruled out dashed lines because *"dashes
  blur to grey under vibration"*. A road line that is also translating adds
  motion blur to vibration blur. A static thin line under vibration is marginal;
  a moving one is worse.
- **Heat and power.** A handlebar in Bengaluru sun, with `FEATURES.md` recording
  panel failure at 70 °C. Continuous 20 FPS redraw plus a 5 Hz pose stream is a
  sustained load bought for a visual effect that costs attention.

### 7.5 The recommendation: step, don't animate — and be honest about the seam

**Redraw on new data only.** One repaint per geometry window, which is what
`geomKey()` already implements: *"the display repaints when this changes, so a
new window and an expiring one both trigger exactly one repaint."* The mechanism
is built and it is correct.

There is one real cost to admit. At 50 km/h (13.9 m/s), with `GEOM_DEPTH_M = 120`
across a ~140 px box, the scale is **0.86 m/px**, so the world moves **16 px/s**.
A 3-second window cadence means a **~48 px jump** at each update — visible, and
on the edge of jarring.

Three ways to resolve it, in order of preference:

1. **Send windows more often as the junction approaches.** Inside 150 m go to
   1 Hz: the step drops to 16 px, and the byte cost is still ~726 B/s at the
   worst moment of the ride, against a 2 kB/s floor. Away from junctions, drop
   back to one window per 3–5 s. **This is the answer.** It spends bandwidth
   exactly where attention is, and it makes the picture *fresher* rather than
   *smoother*, which is the distinction that matters.
2. **Move the marker, not the world.** Hold the junction fixed in the box and
   advance the rider dot toward it. One small object moves instead of the entire
   network, so the motion-capture cost collapses. It contradicts `geom.h`'s
   stated arrangement and would need a rewrite, so it is a considered
   alternative rather than a suggestion.
3. **Full dead reckoning at 15–20 FPS.** Technically fine (§7.3), and the wrong
   trade for this device.

**Direct answer to the question asked:** yes, the ESP32 can show a moving arrow
like Google Maps — it has the frame rate, the geometry pipeline and the rotation
already. **It should instead show a junction that steps as new data arrives, at
1 Hz near the maneuver and slower away from it, with the rider fixed at the
bottom.** Google's smooth map is designed for a phone in a cradle that a driver
may study; this display is designed to be understood without being studied, and
that difference is the whole project.

---

## 8. What I could not confirm

Stated plainly, because these are findings too.

- **HERE's 2026 free tier and its terms.** Three fetch attempts at
  `here.com/get-started/pricing`, `here.com/platform/pricing` and
  `developer.here.com/pricing` returned `ECONNRESET` twice and 404 once. I have
  **no** figure for HERE. §4.1 is therefore complete on TomTom and blank on HERE.
- **TomTom's caching, storage and personal-use terms.** The pricing page states
  the allowances (200 K traffic tiles/month, 2.5 K incident-detail calls/month)
  and explicitly defers restrictions to the T&Cs, which I did not read.
- **TomTom's Bengaluru traffic quality.** The Bengaluru city page exists in
  TomTom's Traffic Index (the URL resolves), which is strong evidence of probe
  coverage — but the page renders its numbers via JS and I could not read the
  rank, average speed, or travel time. Coverage: **inferred**. Quality relative
  to Google: **unknown**.
- **Any public API from Bengaluru Traffic Police.** I found none. Recording that
  as **unknown**, not as a negative — absence of a documented API is weak
  evidence.
- **That D8/R8 actually rejects GraphHopper's Java 25 class files.** The
  `<release>25</release>` in `pom.xml` is verified by reading it. The inference
  that Android's toolchain cannot consume the resulting bytecode follows from
  D8's documented ceiling but **I did not attempt a build.**
- **Planetiler wall-clock time for a 531 MB `southern-zone` extract.** I read the
  planet-scale benchmarks and the RAM/disk formulas, and scaled. **Not measured.**
- **On-device rerouting latency for BRouter or OsmAnd on an S24+.** No published
  benchmark found for any engine on modern Android hardware. §3.4 argues it is
  probably fine and declines to put a number on it. One evening settles it.
- **GPS course-over-ground stability at Bengaluru crawl speeds.** §7.2's
  10 km/h freeze threshold is a design inference from the physics and from
  `NAV_DATA.md`'s stationary-jitter observation, not a measurement on this phone.
- **`name:kn` coverage on Bengaluru roads.** Not measured; §2.4's label-language
  concern is therefore unquantified.
- **MapLibre `OfflineManager`'s current per-region tile limit.** Mapbox's
  ancestor had a 6,000-tile soft cap; I did not find the current MapLibre
  constant. §2.1 sidesteps it by recommending a pre-built local archive.
- **Whether BRouter's `.rd5` format could be extended to carry road names.**
  I verified names are absent from the output (`FormatJson.java`); I did not
  investigate whether the segment format has room for them.
- **The completeness of Bengaluru's `bridge`/`layer` tagging.** Unchanged from
  `ARCH_ANDROID_AUTO.md`'s addendum: 765 bridge-tagged and 929 layer-tagged
  arterials is a dense dataset, but Overpass cannot measure how many real
  flyovers are *missing* the tag. Phase 1's map view answers this on the first
  ride.

---

## Sources

**Measurements I ran myself, 28 Aug 2026** (Overpass data timestamp
`2026-08-28T04:43:31Z`, bbox `12.80,77.40,13.20,77.85`; Berlin control
`52.35,13.10,52.68,13.77`):

- Building counts: 810,507 total / 13,667 `building:levels` / 1,464 `height` /
  9,721 `name` — [Overpass API][ovp]
- Road counts: 210,170 drivable incl. service; 173,760 excl. service; 17,144
  arterials; 11,237 named arterials; 25,269 named drivable; 15,402 with `oneway`;
  16,969 `oneway=yes|-1`; 4,218 with `maxspeed`; **333** `type=restriction`
- Berlin control: 39,034 arterials; **1,795** restrictions; 109,730 `maxspeed`
- POI/address counts: 27,589 `amenity`; 11,566 `shop`; 31,664 `addr:housenumber`
- MVT tile sizes over Bengaluru and rural Karnataka — [OpenFreeMap][ofm] planet
  build `20260823_080002_pt`, `%{size_download}` on 62 real tiles
- Nine live geocoding queries against [Nominatim][nomapi] and [Photon][photonapi]
- `Content-Length` on [BRouter segments][brseg] and
  [OsmAnd's index manifest][osmidx]

**Read directly (verified):**

- [MapLibre Native `platform/android/VERSION`][mlnver] = 13.5.1 ·
  [`MapLibreAndroid/build.gradle.kts`][mlngradle] (minSdk 23, compileSdk 34) ·
  [getting-started guide][mlnstart] (`org.maplibre.gl:android-sdk`, Maven Central) ·
  [release tags][mlnrel]
- [MapLibre Navigation Android][mln] — README, CHANGELOG for v5.0.0 (2026-08-26),
  module layout, `OffRouteDetector`, `voice/AndroidSpeechPlayer`
- [Ferrostar guide][ferro] — *"not a routing engine, basemap, or search
  solution"* · [repo][ferrorepo]
- [BRouter `VoiceHint.java`][bvh] — the 18-value maneuver enum ·
  [`FormatJson.java`][bfj] — no road names in output
- [GraphHopper `pom.xml`][ghpom] — `<maven.compiler.target>25</maven.compiler.target>` ·
  [`docs/index.md`][ghdocs] — *"Offline routing is no longer officially supported"*
- [Valhalla README][valreadme] — *"is also used on iOS and Android devices"*,
  no Android artifact
- [Planetiler][pt] — RAM/disk formulas, planet benchmarks, OpenMapTiles default
  profile, MBTiles + PMTiles output
- [Protomaps basemap downloads][pmdl] — *"roughly 120 gigabytes… zoom levels
  from 0 to 15"*, ODbL Produced Work
- [OpenMapTiles README][omt] — BSD code, CC-BY schema, attribution requirement
- [Geofabrik India][gfi] — `southern-zone` **531 MB**
- [Nominatim Usage Policy][nompol] — 1 req/s, autocomplete prohibited, bans
- [Photon README][photon] — public API fair use, 95 GB / 64 GB RAM planet
  self-host · [India extract][photonin], 780 MB, **dated 2025-07-21**
- [GraphHopper `open-traffic-collection`][otc] — 122 lines, **zero India entries**
- [OSM wiki: Traffic data][osmtraffic] — OpenTraffic marked defunct
- [TomTom pricing][ttprice] · [TomTom Traffic Index, Bengaluru][ttbeng]

**Project documents relied on:** `ARCH_ANDROID_AUTO.md` (§2.2 plan of record,
§1.2 BLE budget, bridge/layer addendum), `NAV_DATA.md` (`progressSegments`,
next-maneuver closed, reroute 300–600 ms, stationary GPS jitter), `FEATURES.md`
(raster rejected, 16–20 FPS with rotation, foveation argument, handlebar
steering-input finding, `turn:lanes` 0.52%), `HARDWARE.md` (45 ms full-screen
push), `firmware/navigator/geom.h` and `geom.cpp`.

[ovp]: https://overpass-api.de/api/interpreter
[ofm]: https://tiles.openfreemap.org/planet
[nomapi]: https://nominatim.openstreetmap.org/
[photonapi]: https://photon.komoot.io/
[brseg]: https://brouter.de/brouter/segments4/
[osmidx]: https://download.osmand.net/get_indexes?xml
[mlnver]: https://github.com/maplibre/maplibre-native/blob/main/platform/android/VERSION
[mlngradle]: https://github.com/maplibre/maplibre-native/blob/main/platform/android/MapLibreAndroid/build.gradle.kts
[mlnstart]: https://maplibre.org/maplibre-native/android/examples/getting-started/
[mlnrel]: https://github.com/maplibre/maplibre-native/releases
[mln]: https://github.com/maplibre/maplibre-navigation-android
[ferro]: https://stadiamaps.github.io/ferrostar/
[ferrorepo]: https://github.com/stadiamaps/ferrostar
[bvh]: https://github.com/abrensch/brouter/blob/master/brouter-core/src/main/java/btools/router/VoiceHint.java
[bfj]: https://github.com/abrensch/brouter/blob/master/brouter-core/src/main/java/btools/router/FormatJson.java
[ghpom]: https://github.com/graphhopper/graphhopper/blob/master/pom.xml
[ghdocs]: https://github.com/graphhopper/graphhopper/blob/master/docs/index.md
[valreadme]: https://github.com/valhalla/valhalla/blob/master/README.md
[pt]: https://github.com/onthegomap/planetiler
[pmdl]: https://docs.protomaps.com/basemaps/downloads
[omt]: https://github.com/openmaptiles/openmaptiles
[gfi]: https://download.geofabrik.de/asia/india.html
[nompol]: https://operations.osmfoundation.org/policies/nominatim/
[photon]: https://github.com/komoot/photon
[photonin]: https://download1.graphhopper.com/public/extracts/by-country-code/in/
[otc]: https://github.com/graphhopper/open-traffic-collection
[osmtraffic]: https://wiki.openstreetmap.org/wiki/Traffic_data
[ttprice]: https://docs.tomtom.com/pricing
[ttbeng]: https://www.tomtom.com/traffic-index/city/bengaluru/
