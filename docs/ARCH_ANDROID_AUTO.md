# Getting road geometry onto the display

Architecture feasibility study, 27 Aug 2026.
Question asked: **is there any architecture that can put the shape of the road
ahead on this display — fork, slip road, five-exit roundabout, flyover versus the
road under it — and is it feasible?**

Not lane guidance. That is closed (FEATURES.md) and stays closed.

---

## Summary — the one-paragraph answer

**Android Auto cannot do it, for a reason that has nothing to do with effort.**
The AA navigation channel carries maneuver metadata only: turn type, road name,
lanes, cue text, distance. There is no polyline, no road shape, no coordinate
stream anywhere in it. Verified twice, independently. A fully working self-mode
head unit — six weeks of work, a certificate you are not entitled to, and a
manual button press before every ride — would deliver a *better icon* and a
*second maneuver*, and would still not draw a junction. **AA is answering a
different question than the one being asked.**

The thing that does answer it is far cheaper than AA and does not touch Google
at all: **an offline OSM vector-tile extract on the phone, queried around the
rider's own GPS position, shipping ~700 bytes of line segments per 240 m window
over the BLE link that already exists.** It keeps Google's routing, Google's
traffic and Google's destination entry exactly as they are today, it needs no
routing engine, no server, no destination knowledge, and it is the only option
on this list that can distinguish a flyover from the road beneath it — which is
the specific Bengaluru failure that prompted the question, and which
`NAV_DATA.md` has already recorded Google Maps as *not* publishing.

Ranked recommendation is in §4. Short version: **do a 400-byte one-shot junction
sketch first as a one-evening spike, then build the vector window if it proves
useful.** Do not build Android Auto.

---

# 1. Android Auto

## 1.1 Does any AA channel carry geometry? No. Verified.

Two independent sources agree, and one of them is Google's.

**Source A — AOSP, authoritative, Apache-2.0.**
[`car-lib/src/android/car/navigation/navigation_state.proto`][aospproto] is
Google's own published schema for navigation state handed to a vehicle. Complete
structure:

```
NavigationStateProto {
  repeated Step steps;            // in execution order
  repeated Destination destinations;
  Road current_road;
  ServiceStatus service_status;
  repeated DataAuthorization data_authorizations;
}

Step { Distance distance; Maneuver maneuver; repeated Lane lanes;
       ImageReference lanes_image; Cue cue; bool is_imminent;
       Road road; Timestamp estimated_time_at_end_of_step; }

Maneuver.Type          // 54 values, UNKNOWN=0 .. DESTINATION_RIGHT=53
Lane { repeated LaneDirection lane_directions; }
LaneDirection { Shape shape; bool is_highlighted; }
ImageReference { string content_uri; double aspect_ratio; bool is_tintable; }
Cue { repeated CueElement elements; string alternate_text; }
CueElement { string text; ImageReference image; }
Road { string name; }
Destination { string title; string address; Distance distance;
              Timestamp estimated_time_at_arrival; string zone_id;
              LatLng location; Traffic traffic; ... }
LatLng { double latitude; double longitude; }
```

**The only coordinates in the entire schema are `Destination.location`** — the
lat/lon of where you are eventually going. No shape, no polyline, no vertex
list, no bearing, no node. `Road` is a string, not a geometry.

**Source B — reverse-engineered AA projection protocol.**
[`mrmees/open-android-auto`, `docs/channels/nav.md`][oaanav] documents channel 11
`NAVIGATION_STATUS`:

| ID | Message | Direction |
|---|---|---|
| 0x8001 | InstrumentClusterStart | HU → Phone |
| 0x8002 | InstrumentClusterStop | HU → Phone |
| 0x8003 | NavigationState | Phone → HU |
| 0x8004 | NavigationTurnEvent | Phone → HU |
| 0x8005 | LegacyNavigationTurnEvent | Phone → HU |
| 0x8006 | NavigationNotification | Phone → HU |
| 0x8007 | NavigationNextTurnDistanceEvent | Phone → HU |
| 0x8008 | VehicleEnergyForecast | Phone → HU |

Its own statement of purpose: the channel delivers *"real-time turn events,
distance updates, and navigation state changes so the HU can display guidance
**without projecting the full map**."* That sentence is the whole finding. The
channel exists precisely so that a head unit that cannot render a map still gets
turn arrows. Geometry is deliberately not in it, because geometry goes down the
video channel as pixels.

**Confidence.** Source A is verified — Google's own file, read directly. Source B
is corroborating rather than primary: its auto-generated `protocol-reference.md`
covers *"80 messages, 8 enums (of 1940 total in APK)"* and does **not** include
`NavigationNotification`, so the exact field list quoted in `NAV_DATA.md` is
inferred from the channel write-up, not extracted. The *conclusion* — no
geometry — does not depend on that, because Source A is dispositive.

**One genuinely interesting mechanism, for the record.** The head unit
advertises, in `NavigationChannel`:

```proto
message NavigationChannel { uint32 minimum_interval_ms = 1; uint32 type = 2;
                            NavigationImageOptions image_options = 3; }
message NavigationImageOptions { int32 width = 1; int32 height = 2;
                                 int32 colour_depth_bits = 3; }
```
— [`aasdk_proto/NavigationImageOptionsData.proto`][aasdknav]

So the HU declares *"render me turn images at W×H at N bits"* and the phone
renders maneuver bitmaps to that spec. A head unit could ask for 96×96 at 1 bit
and get a clean maneuver glyph for free, replacing the icon-hash table in
`NAV_DATA.md` outright. That is real and useful — and it is still an **icon**,
not a junction. It does not answer the question.

## 1.2 If it is video — the byte budget, computed

The map on Android Auto is H.264. Verified from Google's own Head Unit
Integration Guide: *"H.264 elementary byte stream"*, Baseline Profile, minimum
required mode 800×480, optional 1280×720 and 1920×1080, 30–60 FPS
([HUIG][huig]; corroborated by [`aasdk` `VideoResolutionEnum.proto`][aasdkres]
= `{NONE, _480p, _720p, _1080p}` and `VideoFPSEnum.proto` = `{NONE, _30, _60}`).

**The projected surface is the whole UI, not the map.** HUIG: *"The HU MUST
display projected video full-screen on the primary center console display."*
`open-android-auto`'s video channel doc: *"The phone renders its entire Android
Auto UI (Coolwalk layout, maps, media cards, assistant) into a video surface."*
So a frame grab is a screenshot of Coolwalk, with the map partly occluded by the
turn card, the status bar and the media strip.

There is a `CLUSTER` display type — a second video channel described as
*"navigation map or turn card"* — which would be map-only. That is documented in
the reverse-engineered spec and **not** in the HUIG, which never mentions
secondary displays. Treat cluster-over-projection as **unverified**.

### The arithmetic

Link. Current setting is ATT MTU 185 → 182-byte payloads. That is a setting, not
a ceiling: `requestMtu(517)` on Android and NimBLE on the ESP32 both support 517,
and `FEATURES.md` already assumes it for the polyline case. Three budgets:

| Case | MTU | Conn. interval | Sustained app-layer |
|---|---|---|---|
| Conservative (today's assumption) | 185 | 40 ms | **~2 kB/s** |
| Tuned | 517 | 15 ms | ~10 kB/s |
| Theoretical ceiling | 517 | 15 ms, 4 PDU/event | ~40 kB/s |

Frame sizes, raw:

| Target | 1 bpp | 4 bpp | 16 bpp |
|---|---|---|---|
| 160×120 | **2,400 B** | 9,600 B | 38,400 B |
| 320×240 | 9,600 B | 38,400 B | 153,600 B |

Frame rate delivered:

| | 2 kB/s | 10 kB/s | 40 kB/s |
|---|---|---|---|
| 160×120 1 bpp, raw | 0.83 fps | 4.2 fps | 16.7 fps |
| 160×120 1 bpp, RLE ×6 (≈400 B) | 5.0 fps | 25 fps | — |
| 320×240 1 bpp, raw | 0.21 fps | 1.0 fps | 4.2 fps |
| 320×240 4 bpp, raw | 0.05 fps | 0.26 fps | 1.0 fps |

**So the honest answer is not "absurd".** A thresholded 160×120 image, run-length
encoded, moves at 3–6 fps over the link as it is configured *today*, and
`FEATURES.md` already established that a map only translates at ~6 px/s at
50 km/h, so 3 fps is visually ample. Bandwidth is not the blocker. Saying
otherwise would be wrong.

### What actually kills it

**1. Thresholding a downscaled map render destroys exactly what you want.**
An 800×480 Coolwalk frame downscaled 5× to 160×120: a road drawn 5 px wide at
source becomes 1 px, anti-aliased to mid-grey, and a 1-bit threshold turns it
into a dashed line or nothing at all. `FEATURES.md` already recorded that dashes
blur to grey under vibration and that dithered grey inverts its own meaning.
You would have to run edge detection and re-stroke — at which point you have
built a vector extractor, badly, from pixels, having thrown away the vectors the
phone already had.

**2. Cumulative traffic, against the alternative.** A 30-minute ride:

| | Per unit | Ride total |
|---|---|---|
| Video, 160×120 1 bpp RLE @ 3 fps | 400 B × 3/s | **2.16 MB** |
| Vector window, 240 m box, 1 per 18 s | ~700 B | **~70 kB** |
| Whole decimated route polyline, once | ~1.6 kB | **1.6 kB** |

**~30× to ~1,300× more traffic for a worse picture.** And a dropped video frame
is a blank screen; a dropped vector window costs nothing because the device
re-renders locally from the copy it already holds.

**3. The manual button.** Verified from Google's own DHU documentation
([developer.android.com/training/cars/testing/dhu][dhu]): the phone's head unit
server is started from Android Auto → overflow menu → **Start head unit server**,
listed under *"Running the DHU (each session)"*, listening on TCP 5277. This is
not a one-time toggle. Helmet on, gloves on, bike running, and the workflow is
"unlock phone, open Android Auto, open overflow menu, tap Start head unit
server". That alone disqualifies it as a daily-riding architecture, before any
code is written.

**4. Projection takes the phone.** While AA is projecting, the phone is in car
mode. You do not get to also use it as a phone.

**5. Battery.** Continuous H.264 encode (phone, hardware, but a live encoder
session), continuous decode in your app, continuous downscale/threshold/RLE at
3 fps, plus BLE at 1.2 kB/s, plus AA's own service, on a handlebar in Bengaluru
sun. `FEATURES.md` already records the display panel failing at 70 °C; this adds
a sustained SoC load on top.

**Verdict: technically possible, and pointless.** It costs weeks and delivers a
degraded raster of data the phone had in vector form all along.

## 1.3 Cost of a self-mode head unit — confirming and correcting prior research

Prior research recorded: *"aasdk ships no navigation-status handler (request open
and unanswered), and TLS certs must be extracted from the AA APK with Google
rotating them."* Both halves need adjustment.

**On the handler — half right, and now out of date.**
Verified: `f1xpl/aasdk` ships the *channel descriptor* protos
(`NavigationChannelData.proto`, `NavigationImageOptionsData.proto`,
`NavigationFocusRequestMessage.proto`) but no message handler; and
`openDsh/openauto`'s `Service/` directory contains
`{Audio, AudioInput, Bluetooth, Input, MediaAudio, Sensor, SpeechAudio,
SystemAudio, Video}Service.hpp` and **no `NavigationStatusService`**. So the
mainline Raspberry-Pi head units genuinely do not implement it.

**Correction:** [`mossyhub/openautolink`][oal] — the same project `PRIOR_ART.md`
lists under "Avoid" — maintains a fork of `opencardev/aasdk` on branch
`openautolink` that *"adds navigation and EV energy-model extensions"*, ships
cluster/HUD support, and requires Android Auto 17.4+. Its architecture is
directly relevant: *"the native layer handles the Android Auto protocol, TLS,
framing, and channels; Kotlin owns transport, video, audio, sensors, input, and
UI."* That is aasdk-via-NDK inside an Android app — precisely the shape a
self-mode head unit on the S24+ would take. **So the navigation-status handler
now exists in a fork, and someone has already done the Android/NDK bring-up.**
This lowers the effort estimate materially. It does not change the conclusion,
because the data still contains no geometry.

**On the certificates — confirmed, and the mechanism is worse than "extracted".**
HUIG, verbatim: *"Google provides HU certificates to integrators"*, X.509 with
*"RSA with 2048 bit keys"*, and integrators must *"securely store keys and pass
those keys to the receiver library on request."* There is no self-signing path
and no public CA. Every open-source head unit works by using a certificate it
was not issued. I could **not** confirm a specific documented Google rotation
event that broke openauto — searching found protocol-compatibility breakage
(`f1xpl/aasdk` PR #35, closed unmerged 2020) but no certificate-expiry incident.
Record that as **unknown**, not as fact. What *is* certain is that the credential
is Google's to revoke, and that using it is a terms violation regardless of
whether it has been revoked yet.

**Effort, honestly.**

| Path | Estimate |
|---|---|
| From scratch, no reuse | `PRIOR_ART.md` cites one developer at 600+ h ≈ 15 full-time weeks |
| Reusing `openautolink`'s aasdk fork via NDK, nav-status only | **3–6 weeks of evenings**, ~80–150 h |
| Plus keeping it alive across AA releases | open-ended; AA ships monthly |

## 1.4 A lighter way to speak just enough AA? Partly — and it does not help

The handshake is: version request/response → TLS (needs the HU cert) →
AuthComplete → ServiceDiscoveryRequest/Response (you declare your channels) →
ChannelOpenRequest per channel. `InstrumentClusterStart (0x8001)` is HU → Phone,
so the head unit explicitly asks for nav status to begin.

Two reductions look available:

- **Advertise a video channel and never decode it.** Accept the H.264 stream and
  drop every buffer. Costs a socket read, not a decoder. HUIG says the HU *MUST*
  display projected video, but that is a certification requirement, not something
  the phone can observe.
- **Skip input entirely** by starting navigation on the phone *before* connecting,
  and letting guidance transfer to projection.

That would leave: version + TLS + service discovery + a discarded video channel +
nav status. Plausibly 40% of the full stack.

**Confidence: inferred, not verified.** Whether Maps publishes nav state to a
head unit that never takes video focus is untested and I could not find anyone
who has tried. It is the one AA experiment that would be cheap enough to justify
— and it would still return no geometry, so it is worth doing only if the
*second maneuver* and the 54-value `Maneuver.Type` enum are wanted for their own
sake.

---

# 2. Architectures that actually deliver geometry

## 2.1 Routing engines — what each returns

| Engine | Route geometry | Per-step geometry | Junction shape | Runs where |
|---|---|---|---|---|
| **Valhalla** | encoded polyline, **6-digit precision** | `begin_shape_index` / `end_shape_index` per maneuver | via `trace_attributes`, see below | self-host / VPS |
| **OSRM** | `polyline` (p5), `polyline6`, or GeoJSON; `overview=simplified\|full\|false` | per-step `geometry` | **`intersections[]` in the route response — best in class** | self-host |
| **GraphHopper** | encoded polyline (Google format), RDP-simplified | per-instruction interval | none structured | server **or on-device Java** |
| **BRouter** | **GPX track only**, via Android Service AIDL | no turn instructions at all | none | fully on-device, no server |

**Valhalla** — verified from the API reference: *"a shape which is an encoded
polyline of the route path with 6 digits decimal precision"*, and maneuvers carry
`begin_shape_index` / `end_shape_index`, `roundabout_exit_count`, and a `sign`
object with exit number / branch / toward. There is **no `lanes` field on the
maneuver in the documented reference** — `turn_lanes` output exists behind a
build option (`FEATURES.md`) but is not in the base schema. Note the
`shape_index` pair is exactly what you need to send *only the geometry around the
next maneuver* rather than the whole route.

**Valhalla's real find is `trace_attributes`**, which is map-matching, not
routing. Feed it the route shape and request node attributes, and you get, per
node ([map-matching API reference][valmm]):

```
node.intersecting_edge.begin_heading            // degrees CW from north
node.intersecting_edge.driveability             // forward | backward | both
node.intersecting_edge.from_edge_name_consistency
node.intersecting_edge.to_edge_name_consistency
node.intersecting_edge.cyclability / .walkability
node.fork                                       // bool
node.type
edge.begin_heading / edge.end_heading
edge.begin_shape_index / edge.end_shape_index
```

**That is a structured description of every branch at every junction on the
route.** `node.fork` is literally "this is a fork". Cost: one extra request.

**OSRM gives the same thing in the route response, with no second call** —
verified from the v5 API docs. Each step carries `intersections[]`:

```
location   [lon, lat]
bearings[] 0–359, "all available roads at the intersection", 0 = true north
entry[]    bool, 1:1 with bearings — which are legally enterable
in / out   indices into bearings — the road you came from, the road you take
classes[]  road classes available at the exit
lanes[]    Lane objects (optional)
```

Plus `StepManeuver.bearing_before` / `bearing_after` / `type` / `modifier` /
`exit`. Mapbox Directions returns the same shape because it is OSRM-derived.

**BRouter** is worth two sentences and no more: it runs entirely on-device with
no server, which is attractive, but it *"is then written as a GPX file"* and
produces no turn instructions. It is a bicycle route planner, not a guidance
engine. Wrong tool.

**GraphHopper on-device** is the sleeper of this row: pure Java, memory-mapped
Contraction Hierarchies, *"Germany-wide queries with only 32MB in a few
seconds"*. It would run inside the existing Android app with no server and no
VPS. But the official Android demo was **removed at GraphHopper 2.0**, so you are
maintaining an unsupported integration.

### What a polyline costs over BLE

Take a typical 12 km Bengaluru ride.

| Encoding | Points | Bytes | Notifications @ MTU 185 | Time @ 2 kB/s |
|---|---|---|---|---|
| Valhalla polyline6, verbatim | ~1,200 | ~12 kB | 66 | 6.0 s |
| RDP @ 10 m, int16 **metres**, route-local frame, 4 B/pt | ~400 | **1.6 kB** | 9 | 0.8 s |
| RDP @ 10 m, int8 delta pairs with int16 escapes | ~400 | ~0.9 kB | 5 | 0.45 s |

`int16` metres spans ±32.7 km — a whole Bengaluru route in one frame, at 1 m
resolution, against a display showing ~1 km across 320 px = 3.1 m/px. **1 m
resolution is four times finer than the screen can show.** Do the decimation on
the phone, as `FEATURES.md` already specifies.

ESP32 cost: 1.6 kB resident against 100–180 kB free heap. Rotation is ~400
multiply-adds. `FEATURES.md` already measured this class of work at 16–20 FPS
with heading-up rotation included.

**Sending a route polyline is a solved, cheap problem.** Getting a route to send
is the expensive part, and `FEATURES.md` already decided against it — correctly,
because owning the route means owning destination entry, rerouting, off-route
detection, and losing Google's Bengaluru traffic.

## 2.2 On-device geometry without routing — the option that wins

**This is the finding of the study.** It was not on the original list of
alternatives and it should have been.

You do not need the route to draw the road. You need the *roads*. And the phone
can hold every road in Karnataka locally and query them against its own GPS fix,
with no server, no destination, no routing engine, and no knowledge of where
Google is sending you.

### The mechanism

1. Phone holds an offline vector-tile extract of the Bengaluru metro area.
2. At ~1 Hz, take the fused GPS fix and heading.
3. Read the covering z14 tile from a local **MBTiles** file — which is just
   SQLite, built into Android: `SELECT tile_data FROM tiles WHERE zoom_level=14
   AND tile_column=? AND tile_row=?`.
4. Gunzip, decode MVT. A z14 tile at 13°N spans 40,075,016 × cos(13°) / 2¹⁴ =
   **2,382 m**, and MVT extent 4096 gives **0.58 m per unit** — already integer,
   already quantised, four times finer than the display.
5. Clip the `transportation` layer to a 240 m box ahead of the rider, keep
   `class`, `layer`, `brunnel` (bridge/tunnel), simplify with RDP at 3 m.
6. Emit line segments in a rider-local frame.

### The byte budget

Bengaluru arterial junction, 240 m × 240 m window: typically 10–40 ways,
60–150 vertices after simplification.

```
[type 0x09 GEOM][len]
  i16 origin_lat_e5_offset, i16 origin_lon_e5_offset   // window anchor
  u8  polyline_count
  per polyline:
    u8  class      (motorway/trunk/primary/secondary/residential/service/link)
    i8  layer      (-2..+2 — THE FLYOVER BIT)
    u8  vertex_count
    per vertex: i16 x_dm, i16 y_dm   // decimetres, rider-local, ±3,276.7 m
```

| Item | Bytes |
|---|---|
| 150 vertices × 4 | 600 |
| 40 polyline headers × 3 | 120 |
| Window header | 6 |
| **Total** | **~726 B** |

Five notifications at MTU 185, two at MTU 517.

**Refresh economics.** At 50 km/h (13.9 m/s) a 240 m window holding 180 m of
lookahead needs replacing every ~60 m = 4.3 s. One window per 3 s = **242 B/s**,
which is 12% of the conservative 2 kB/s budget.

**Better: tile the cache.** Split into 256 m tiles, keep a 3×3 grid resident on
the ESP32 (9 × ~700 B = **6.3 kB** — trivial against 100–180 kB free heap), and
transfer only newly-entered tiles. At 50 km/h you cross a tile boundary every
~18 s → **~39 B/s average**. The link is effectively idle. On a repeated commute
the ESP32 re-enters cached tiles constantly and transfers nothing at all.

ESP32 render: rotate ~150 points (microseconds), draw ~40 wide lines into the
4bpp 320×240 sprite (38 kB) already planned in `FEATURES.md`. Same order of work
as the route line already costed there.

### Why this specifically answers the flyover problem

`NAV_DATA.md`, verbatim: *"Flyovers are not distinguished. Rides along NH 44 and
NH 75 including elevated sections produced no flyover-specific icon."*

OSM tags the flyover carriageway `bridge=yes` and `layer=1`; the service road
below is `layer=0`. Rendering the elevated carriageway as a thick line and the
road beneath as thin, from a single `layer` byte per polyline, **is the exact
disambiguation Google refuses to publish**. No other architecture on this list
delivers it — Android Auto included, because `Maneuver.Type` has no flyover
value either.

**Verify before building.** Coverage is the thing that killed lane guidance and
it must be checked here too. Run this against the same Bengaluru bbox
`FEATURES.md` used:

```
[out:json][timeout:180];
( way["bridge"]["highway"~"^(motorway|trunk|primary|secondary)(_link)?$"]
      (12.80,77.40,13.20,77.85); );
out count;
```
and compare against the 8,249 arterial ways already counted. `layer` and
`bridge` are among the oldest and most consistently applied tags in OSM, so this
should not repeat the 0.52% `turn:lanes` disaster — but **that is an expectation,
not a measurement.** Two minutes of Overpass settles it, and it should be settled
before any code is written.

### Libraries — what is practical on Android

| Approach | Verdict |
|---|---|
| **MBTiles (SQLite) + MVT decoder** | **Recommended.** SQLite is in Android. MVT decoders exist as small pure-Java libs (`no.ecc.vectortile:vector-tile-java`, `com.wdtinc:mapbox-vector-tile`). No renderer, no GL, no native code. |
| **PMTiles** | Same data, single file, range-reads; `pmtiles extract` cuts an arbitrary bbox or GeoJSON region from a remote planet archive ([docs][pmt]). Java reader support is **unknown** — check before committing. MBTiles is the safe choice. |
| **Mapsforge `MapFile` reader** | Well-trodden on Android, documented read API returning ways with lat/lon and tags. But the smallest published India extract containing Karnataka is `southern-zone.map` at **520 MB** (verified, [download.mapsforge.org][mfd]); you would cut your own with the Mapsforge Writer. |
| **MapLibre Native + `querySourceFeatures`** | Works, but drags in a full GL renderer to answer a geometry question. Wrong weight class. |
| **Overpass API** | 1–3 s latency, rate-limited, network-dependent. Unusable while riding; **excellent for offline preprocessing** of your regular junctions. |

**Data sizing.** Geofabrik has no Karnataka extract — India's subregions are six
zones, of which `southern-zone` is **531 MB** `.osm.pbf` and the whole of India
is **1.6 GB** (verified, [download.geofabrik.de/asia/india.html][gfi]). But you
do not want a PBF; you want tiles. A Bengaluru metro box of roughly 40 × 40 km at
z14 is ~17 × 17 = **289 tiles**; at typical OpenMapTiles sizes that is on the
order of **20–30 MB** including z12–z13. *(Estimated, not measured — the tile
count is arithmetic, the per-tile size is not.)* Nothing on a phone with a
256 GB store.

### What it costs you

- **`ACCESS_FINE_LOCATION` and a location-typed foreground service.** Today's
  notification listener needs **no location permission at all**. This adds one,
  plus Android 14+ `FOREGROUND_SERVICE_LOCATION`, plus the Play Store friction
  that comes with it if this ever ships.
- **Continuous 1 Hz GPS.** Roughly 30–60 mW on top of what the app draws now.
  Real, but small next to the display backlight at 60–100 mA (`FEATURES.md`).
- **MVT decode.** A ~60 kB tile decodes in ~10–30 ms on an S24+; at most one new
  tile every ~18 s. Negligible. *(Estimated.)*
- **Samsung background killing** is unchanged — the foreground service already
  exists for BLE; this adds a service type to the manifest, not a new process.
  The battery-optimisation whitelist problem NAVRIDER documents applies exactly
  as it already does.

### And the fragility argument, which is the strongest one

**This is the only option that makes the existing architecture *less* fragile.**
Google Maps breaks its notification format roughly annually. Today that takes the
whole display down. With a local geometry source, a Maps break costs you the
maneuver arrow and the distance — and the road ahead keeps drawing, from data on
the phone that no vendor can change under you.

## 2.3 Junction view — no open data exists

Two sentences, as promised.

Garmin's photoReal / Bird's Eye junction views ship as licensed `.jcv` files
bundled with City Navigator map products; Mapbox's `MapboxJunctionView` renders
imagery its docs gate behind *"contact your Mapbox sales representative"*. Both
are proprietary artwork derived from commercial HD road databases, and **no open
equivalent exists** — OSM has no junction-diagram data and no renderer produces
one.

**Beeline is the useful data point, and it argues the other way.** Beeline Moto
II renders *"just the next move"*, explicitly *"no maps"* — a large arrow and a
distance — and routes from Mapbox. A company sold a motorcycle navigation product
on the premise that the arrow is sufficient. `FEATURES.md` already used this
argument to defer Valhalla; it applies here too, and it is the main reason §4
recommends spiking before building.

## 2.4 OsmAnd and MapLibre Navigation

**OsmAnd's AIDL exposes no geometry.** Verified: `ADirectionInfo` has exactly
three fields — `int distanceTo`, `int turnType`, `boolean isLeftSide`. The
interface exposes 90+ methods including `calculateRoute(CalculateRouteParams)`,
`navigate`, `navigateGpx`, `navigateSearch`, and
`registerForNavigationUpdates(ANavigationUpdateParams, IOsmAndAidlCallback)` —
but `calculateRoute` returns `boolean`, and the update callback delivers
`ADirectionInfo`. No shape, no coordinates, no GPX of the computed route.

**Could it be made to?** Yes, and it remains the best effort-to-reward fork on
this list, exactly as prior research said. OsmAnd computes the full route
internally and already renders second-next-turn and lane widgets from `.obf`
data. Widening the AIDL is a small change to a GPLv3 codebase, legitimate for
personal use with no distribution, and `FEATURES.md` costs it at 15–30 h.

**But it does not win here**, because it hands you the same fork §2.1 already
rejected: OsmAnd routes, so you lose Google's Bengaluru traffic and inherit
destination entry. §2.2 gets geometry while keeping Google. **Fork OsmAnd only
if you have already decided to leave Maps.**

**MapLibre Navigation Android** — MIT, no telemetry, actively developed
(965 commits, mid-migration to Kotlin Multiplatform), forked from **Mapbox
Navigation SDK v0.19** (not v1, as sometimes claimed) and speaking the Mapbox
Directions response format, so it accepts any self-hosted OSRM or Valhalla that
emits that shape — including `intersections[].bearings`. It is a complete
turn-by-turn UI, which is far more than this project needs; its value is as a
reference implementation of the response format, not as a dependency.

## 2.5 "The junction ahead looks like THIS" in a few hundred bytes — four ways

Ranked cheapest first.

| # | Encoding | Bytes | What it conveys | Flyover? |
|---|---|---|---|---|
| 1 | Branch bearings only: `u8 n, u8 bearing[n] (deg/2), u8 entry_mask, u8 taken` | **8 B** | schematic star — fork / Y / 5-way | **No** — both branches share a bearing |
| 2 | Bearings + attributes: add `u8 class, i8 layer, u8 stub_len` per branch | **~40 B** | schematic with elevation and road importance | **Yes** |
| 3 | Phone-rendered 1-bit junction sketch, 96×72 | **864 B** | a real drawing, thick strokes, phone-quality | Yes |
| 4 | Vector window, §2.2 | **~726 B** | true geometry, curvature, re-renders on device | Yes |

**#1 is a trap.** It is the obvious minimal encoding and it fails on precisely
the Bengaluru case that prompted the question: a flyover and the road under it
leave the junction on nearly the same bearing. A stick star shows one line.

**#3 deserves attention as a first step.** The phone has full map data and a real
renderer. Let it draw a clean, heading-up, thick-stroked, high-contrast line
drawing of the junction — *not* a downscaled screenshot, which is what §1.2
kills — and ship the bits once per junction, not once per frame. 96×72 at 1 bpp
is 864 B, roughly 0.4 s at 2 kB/s, sent once when the junction comes within
300 m. This is `DEMP1993`'s ship-the-icon-bitmap idea (`PRIOR_ART.md`)
generalised from a maneuver glyph to a junction sketch. It needs **zero geometry
code on the ESP32** — blit and done.

Its limits are real: no rotation on the device, so it is frozen at the heading it
was rendered for; and no smooth update as you approach. But it is one evening of
work and it answers the only question that matters — *is seeing the junction
shape actually useful on a real Bengaluru ride?* — before 50–80 h go into #4.

---

# 3. What breaks, per architecture

| Risk | Notification only (today) | + §2.2 vector window | Own routing | Android Auto |
|---|---|---|---|---|
| Maps notification format churn (~annual) | **total loss** | maneuver lost, road shape survives | none | none |
| Google rotates HU certificates | — | — | — | **total loss, no recourse** |
| AA protocol change (monthly releases) | — | — | — | **high** |
| Terms of service | grey (notification listener) | grey, unchanged | clean | **clear violation** |
| Manual per-ride setup | none | none | none | **"Start head unit server", every session** |
| Loses Google live traffic | no | **no** | **yes** | no |
| Battery, always-on service | today's baseline | +1 Hz GPS, ~30–60 mW | +GPS +routing | **+H.264 encode/decode, large** |
| Samsung background killing | already handled | unchanged | unchanged | worse — more processes |
| New Android permission needed | none | **`ACCESS_FINE_LOCATION`** | location | many |
| OSM data quality | — | **unmeasured — run the Overpass query** | same | — |

Two entries deserve emphasis.

**The AA certificate is not a technical risk, it is a permission you do not
have.** HUIG says Google issues HU certificates to integrators. Everything built
on an extracted certificate is running on a credential that can be revoked
without notice and whose use is a terms violation today, working or not. For a
personal device this is a real but tolerable risk; `PRIOR_ART.md` already notes
it is not a product path.

**The §2.2 OSM-quality risk is the one that killed lane guidance**, and it must
be measured the same way, with the same Overpass method, before anything is
built. `bridge` and `layer` should be far better covered than `turn:lanes` —
they are older, simpler, and visible from imagery — but "should be" is what
0.52% looked like before someone counted.

---

# 4. Recommendation

Ranked by value ÷ (effort × fragility).

### 1. Two Overpass queries and a spike. ~1 evening.

Before anything else:

- Run the `bridge` / `layer` coverage query in §2.2 against the Bengaluru bbox.
  If coverage is poor, most of this document is moot and you have spent ten
  minutes.
- Build encoding **#3** — the phone renders a 96×72 1-bit junction sketch from
  offline OSM data and ships 864 bytes when the next maneuver comes inside
  300 m; the ESP32 blits it into the existing display. One new packet type, no
  ESP32 geometry code, no change to anything that works today.

Then ride with it. `FEATURES.md` records that *"the device has not completed a
single real ride"* and that switching architecture to solve an unexperienced
problem is the wrong order. That argument has not expired. This spike converts
"would seeing the junction help?" from an opinion into an observation, for the
cost of one evening.

### 2. The vector window, §2.2. ~50–80 h.

Only if the spike says yes. Android ~30–50 h (MBTiles store, MVT decode,
rider-local projection, clipping, RDP, tile-cache protocol), ESP32 ~15–25 h
(3×3 tile cache, rotate, draw by class and layer), pipeline ~5 h.

Why it ranks where it does:

- **It is the only option that delivers the thing actually asked for** — true
  road shape, including flyover versus underpass.
- **It costs Google nothing.** Routing, traffic, rerouting and destination entry
  stay exactly as they are.
- **It reduces total fragility** rather than adding to it (§2.2, last point).
- **It rides on decisions already made.** `FEATURES.md` chose vector over raster
  and costed the render; `BLE_PROTOCOL.md` is typed-and-length-framed so a new
  `0x09 GEOM` type costs two bytes and ten lines.
- Multi-week, and the user has said multi-week is acceptable. Be clear that
  50–80 h is real: that is two to three months of evenings.

### 3. Keep the notification scraper and add nothing.

**This is a serious option and it is not far behind.** Beeline sold a product on
the arrow alone (§2.3). The sunlight gate is unresolved, and `FEATURES.md`
already recorded that *"if the sunlight gate forces a monochrome reflective
panel, a thin route line is among the first things glare destroys"* — which
applies to junction geometry too, and more so, since junction lines are thinner
than a route line.

It does not win outright only because of the fragility argument: today, one Maps
update takes the entire display down, and §2.2 is the only proposal that
survives that.

**Against, though, in §2.2's favour on legibility:** a junction diagram is a
*coarse* judgement, unlike lane guidance. At 700 mm, 1 px ≈ 0.87 arc-min
(`FEATURES.md`); a branch drawn across a 100 px arm subtends **87 arc-min**,
against ISO 15008's 20 arc-min recommendation. Junction *shape* clears the bar by
4×, where the lane-arrow shaft angle failed it at 4 arc-min. Junction geometry is
a legitimate feature where lane guidance was not, and the arithmetic says so.

### 4. Fork OsmAnd's AIDL. 15–30 h.

Best value *if and only if* you have already decided to leave Google Maps. Gives
geometry, second maneuver, lanes and speed limits in one change. Costs Bengaluru
traffic. `FEATURES.md`'s revisit triggers still govern: after 5–10 real rides, or
when Maps breaks the format.

### 5. Self-host Valhalla / own the route.

Unchanged from `FEATURES.md`: weeks of work to arrive back at today's
functionality, minus Google's traffic. Its geometry is genuinely better than
§2.2's — a real route line, not just local roads — but §2.2 gets 80% of the
visual value for 20% of the disruption. Revisit when Maps forces the migration.

### 6. Android Auto nav-state subscription. 3–6 weeks.

Delivers the second maneuver and a 54-value `Maneuver.Type` enum that would
replace the icon-hash table. **Delivers no geometry.** Needs a certificate you
are not entitled to and a manual button press before every ride. The manual
button alone is disqualifying for a helmet-on workflow.

### 7. Android Auto video relay. 4–10 weeks.

Bandwidth is survivable (3–6 fps at 160×120 1-bit RLE on today's link — the
arithmetic in §1.2 does not condemn it). Everything else does: a 1-bit threshold
of a downscaled anti-aliased map render destroys the thin lines that *are* the
information; you ship 30–1,300× more bytes than the vector path for a worse
picture; and you still press the button before every ride.

**Do not build this.**

---

# 5. What I could not confirm

Stated plainly, because these are findings.

- **Whether Google Maps publishes nav state to a head unit that never takes video
  focus.** The single cheap AA experiment. Untested by anyone I could find.
- **Whether the `CLUSTER` display type is reachable over the projection protocol
  from a self-mode head unit.** Documented in the reverse-engineered spec, absent
  from Google's HUIG.
- **Any specific incident of Google rotating AA head-unit certificates and
  breaking open-source head units.** Widely repeated; I found protocol-
  compatibility breakage but no certificate-expiry event. The *risk* is real; the
  *history* is unverified.
- **The exact field list of AA `NavigationNotification (0x8006)`.** The
  auto-generated reference in `open-android-auto` covers 80 of 1,940 APK
  messages and does not include it. The channel write-up does. Trust the
  conclusion (no geometry — corroborated by AOSP) more than the field list.
- **`bridge` / `layer` OSM coverage in Bengaluru.** Not measured. §2.2 depends on
  it. Query provided.
- **Real per-tile MVT sizes for a Bengaluru z14 extract.** Tile count is
  arithmetic; byte sizes are estimated.
- **Java PMTiles reader maturity on Android.** Unknown. MBTiles/SQLite avoids
  the question.

---

## Sources

Verified by direct reading:

- [AOSP `navigation_state.proto`][aospproto] — Google's own navigation state schema
- [`mrmees/open-android-auto` navigation channel][oaanav] · [video channel][oaavid]
- [Android Auto Head Unit Integration Guide (cached)][huig] — video specs, certificates
- [Google DHU documentation][dhu] — "Start head unit server", TCP 5277
- [`aasdk` `VideoResolutionEnum.proto`][aasdkres] · [`VideoFPSEnum.proto`][aasdkfps] · [`VideoConfigData.proto`][aasdkvcd] · [`NavigationChannelData.proto`][aasdknavch] · [`NavigationImageOptionsData.proto`][aasdknav]
- [`openDsh/openauto` service headers][odsh] — no NavigationStatusService
- [`mossyhub/openautolink`][oal] — nav extensions in an aasdk fork
- [OSRM v5 API reference][osrm] — `intersections[]`, bearings, entry
- [Valhalla turn-by-turn API reference][valtbt] · [map-matching API reference][valmm]
- [OsmAnd `IOsmAndAidlInterface.aidl`][aidl] · [`ADirectionInfo.java`][adi]
- [MapLibre Navigation Android][mln]
- [Geofabrik India extracts][gfi] · [Mapsforge India maps][mfd] · [Protomaps `pmtiles extract`][pmt]
- [Mapbox junction views][mbjv] · [Garmin junction view][gjv] · [Beeline Moto][bmoto]
- [BRouter Android service][brs]
- [GraphHopper][gh]

[aospproto]: https://android.googlesource.com/platform/packages/services/Car/+/master/car-lib/src/android/car/navigation/navigation_state.proto
[oaanav]: https://github.com/mrmees/open-android-auto/blob/main/docs/channels/nav.md
[oaavid]: https://github.com/mrmees/open-android-auto/blob/main/docs/channels/video.md
[huig]: https://milek7.pl/.stuff/galdocs/huig13_cache.html
[dhu]: https://developer.android.com/training/cars/testing/dhu
[aasdkres]: https://github.com/f1xpl/aasdk/blob/master/aasdk_proto/VideoResolutionEnum.proto
[aasdkfps]: https://github.com/f1xpl/aasdk/blob/master/aasdk_proto/VideoFPSEnum.proto
[aasdkvcd]: https://github.com/f1xpl/aasdk/blob/master/aasdk_proto/VideoConfigData.proto
[aasdknavch]: https://github.com/f1xpl/aasdk/blob/master/aasdk_proto/NavigationChannelData.proto
[aasdknav]: https://github.com/f1xpl/aasdk/blob/master/aasdk_proto/NavigationImageOptionsData.proto
[odsh]: https://github.com/openDsh/openauto/tree/master/include/f1x/openauto/autoapp/Service
[oal]: https://github.com/mossyhub/openautolink
[osrm]: https://project-osrm.org/docs/v5.24.0/api/#intersection-object
[valtbt]: https://github.com/valhalla/valhalla-docs/blob/master/turn-by-turn/api-reference.md
[valmm]: https://github.com/valhalla/valhalla-docs/blob/master/map-matching/api-reference.md
[aidl]: https://github.com/osmandapp/OsmAnd/blob/master/OsmAnd-api/src/net/osmand/aidlapi/IOsmAndAidlInterface.aidl
[adi]: https://github.com/osmandapp/OsmAnd/blob/master/OsmAnd-api/src/net/osmand/aidlapi/navigation/ADirectionInfo.java
[mln]: https://github.com/maplibre/maplibre-navigation-android
[gfi]: https://download.geofabrik.de/asia/india.html
[mfd]: https://download.mapsforge.org/maps/v5/asia/india/
[pmt]: https://docs.protomaps.com/pmtiles/cli
[mbjv]: https://docs.mapbox.com/android/navigation/guides/ui-components/junctions/
[gjv]: https://support.garmin.com/en-US/?faq=Umn3OMB08f3iXuuEyML7o6
[bmoto]: https://beeline.co/pages/beeline-moto
[brs]: https://zod.github.io/brouter/developers/android_service.html
[gh]: https://github.com/graphhopper/graphhopper

---

## Addendum: the coverage check, run (27 Aug 2026)

The study says settle coverage before writing code. Settled. Overpass, same
Bengaluru bbox `FEATURES.md` used (12.80,77.40,13.20,77.85):

| Query | Ways |
|---|---:|
| Arterials (`motorway\|trunk\|primary\|secondary`, incl. `_link`) | **9,398** |
| ...of those, tagged `bridge` | **765** |
| ...of those, tagged `layer` | **929** |

**This is not the 0.52% story, and the difference is structural rather than
just larger.** `turn:lanes` had to be present on nearly every way a rider
approaches a junction on, so 0.52% meant the feature was blank 99.5% of the
time. `bridge` only has to be present on ways that *are* bridges — and most
roads are not bridges. 765 tagged bridge segments across the metro is a dense
dataset, not a sparse one.

What this does **not** measure is the fraction of real flyovers that carry the
tag; Overpass cannot answer that, because an untagged flyover is
indistinguishable from a road. So the honest statement is: there is plenty of
bridge data, and whether it is *complete* is unknown. That is a far better
starting position than lane guidance ever had, and it is checkable on the first
ride — a flyover the display draws flat is a missing tag, and it is fixable in
OSM by the person who found it.
