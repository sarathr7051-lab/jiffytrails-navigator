# Feature decisions

One entry per proposed feature: what it would do, what it costs, and the
decision with its reasoning. Rejected features stay here with the reason, so
they are not re-proposed and re-researched.

---

## Lane guidance — REJECTED on data availability

**Proposed:** show which lane to take alongside the maneuver arrow, the way
Google Maps and Android Auto do.

### The measurement that decided it

Overpass query against the Bengaluru bbox `(12.80, 77.40, 13.20, 77.85)`,
run 26 Aug 2026:

| Query | Ways |
|---|---|
| `way["turn:lanes"]` | **43** |
| `way["highway"~"^(primary\|secondary\|trunk\|motorway)$"]` | **8,249** |

**0.52% coverage.** Reproduce with:

```
[out:json][timeout:180];way["turn:lanes"](12.80,77.40,13.20,77.85);out count;
```

### Why that kills every option, not just one

Mapbox Directions returns `intersections[].lanes` and is free at this volume.
OsmAnd computes lanes offline. Valhalla and OSRM can be self-hosted. **All four
read the same `turn:lanes` tags in OSM.** They are not better data — they are
the same data with the hard parts pre-solved. At 0.52% the display would show
lane guidance so rarely that it would never be trusted, and silence is
indistinguishable from "one lane, no choice".

Also ruled out along the way:

- **OsmAnd's AIDL API does not export lane data.** Verified against
  `IOsmAndAidlInterface.aidl` — `registerForNavigationUpdates` delivers turn
  type and distance only. OsmAnd's own UI renders lanes from `.obf` files, so
  the data exists in-process but is not exported. Patching it is legitimate for
  personal use (GPLv3, no distribution) but is ~15–30 h and costs Google traffic.
- **Android Auto is unreachable.** Cluster access needs
  `android.car.permission.CAR_INSTRUMENT_CLUSTER_CONTROL`, a privileged
  OEM-platform permission, and the API is shaped for nav apps to *push* to a
  cluster — there is no supported path to receive another app's lane data.
- **Google's Navigation SDK has real lane objects** (`Lane`, `LaneDirection`,
  `isRecommended`) but is a contract-gated Mobility product. Not available.

### The one thread left unpulled

**No structured lane field was found in the Maps notification** — and notably,
Gadgetbridge resorts to image-matching the icon just to recover the *turn type*,
which suggests the notification is poor in structured data generally.

But nobody has checked whether the instruction **text** carries lane phrasing —
Maps says "Use the left 2 lanes to turn left" in-app and in voice. If that string
reaches `android.title`, Google's own India lane data (far better than OSM's)
becomes available for free, and the feature is back on.

**Ten-minute check:** dump the complete extras bundle at a junction with lane
guidance and grep for "lane". Until then this is unknown, not absent.

### Even with data, the standard UI is wrong here

Worth recording, because it changes what to build if the text check succeeds.

At handlebar distance (~700 mm eye-to-display) on this 2.8" panel, 1 px ≈ 0.87
arc-minutes. ISO 15008 wants 20 arc-min for a feature, 12 absolute minimum:

| ISO level | arc-min | pixels |
|---|---|---|
| Recommended | 20 | 23 px |
| Acceptable | 16 | 18 px |
| Minimum | 12 | 14 px |

A conventional 5-cell lane strip on 320 px gives 64 px cells — the *block* is
legible, but the discriminating feature (shaft angle, arrowhead) is ~12–14 px
and stroke width ~5 px ≈ 4 arc-min. **Far below anything ISO endorses.** And a
5-lane array exceeds the subitizing limit (1–4 items read instantly, 5+ must be
counted), so it cannot be read in a glance at all.

The per-lane arrow is also **redundant** — the big maneuver arrow already says
what the turn is. What it does not say is where laterally to be.

**If lane data ever arrives, build a lateral-position bar, not an arrow strip:**
a 288×20 px band at the bottom, a 3 px rule spanning the width as "the road",
and one solid block at the proportional position of the valid lanes. Position
along a line is a pre-attentive judgement — the fastest kind. Costs 28 px,
costs the arrow and distance nothing, and survives a move to a monochrome
reflective panel unchanged, because it encodes valid/invalid as **solid versus
nothing** rather than as a contrast ratio.

Monochrome encoding rules worth keeping regardless: solid fill vs thin outline
is the strongest channel; size is a good second; **never** use dashed-vs-solid
(dashes blur to grey under vibration) or dithered grey (reads as filled once
blurred, inverting the meaning).

### Decision — CLOSED, 26 Aug 2026

**Not building it.** Sarath's call, made on the coverage number.

The notification-text check was offered and declined — reasonably, since even a
positive result leads to the lowest-contrast, finest-detail element on the
screen, which is the first thing glare destroys and the last thing this project
needs before the sunlight gate is settled.

**Do not reopen this** without new evidence. If it ever comes back, the
lateral-position bar above is the design, not an arrow strip.

Note also that on a Bengaluru motorcycle, where lane discipline is notional and
filtering is normal, "take the left 2 lanes" is worth considerably less than it
is to a car on a US freeway.

---

## Map layout — RASTER REJECTED, VECTOR RECOMMENDED

**Proposed:** show an actual map behind or beside the turn arrow, rather than
just the arrow.

### Raster tiles on the LOLIN32: architecturally impossible

Not "hard" — three independent reasons, any one of them fatal.

**1. There is no framebuffer.** A 320×240 RGB565 buffer is 153,600 bytes.
TFT_eSPI's author states plainly that on ESP32 "a 16-bit colour Sprite is
limited to about 200x200 pixels (~80Kbytes)". With NimBLE resident, measured
free heap is **100–180 KB**, and the largest *contiguous* block is smaller
still. It does not fit, and this is the library author saying so about this
exact chip.

**2. There is no rotation.** Heading-up requires the source bitmap to cover the
rotated view's circumscribing square: √(320² + 240²) = **400 px**, so
400 × 400 × 2 = **320,000 bytes resident** — twice the entire free heap. Plus an
inverse transform per destination pixel: 76,800 per frame, with cache-hostile
non-sequential reads.

**3. There is no tile source.** No SD slot is wired. Wiring one means sharing
SPI with the display; at the ~0.4–1 MB/s Arduino `SD` actually achieves,
pulling one screen of tile data costs ~154 ms **before** the 45 ms display push.
About 5 FPS before anything is drawn.

### What the prior art shows

| Project | Board | PSRAM | Approach | Rotation |
|---|---|---|---|---|
| Gupta AMOLED map | ESP32-S3R8 | **8 MB, essential** | raw RGB565 tiles | none |
| IceNav-v3 | ESP32-S3 | **8 MB required** | PNG / vector | yes (with PSRAM) |
| macebio/bikegps | ESP32-C6 | none | JPEG blocks, 172×320 | none |
| lspr98/bike-computer-32 | ESP32-**C3** | none | **vector binary** | **60 FPS** |
| lavrushko BLE-trail-nav | ESP32 classic | none | **BLE primitives from phone** | — |

**Every raster project on a full-size screen needs PSRAM. Every PSRAM-less
project either shrinks the screen or goes vector.** Gupta's framebuffer alone is
434 KB — more than this chip's entire SRAM — and his map is north-up anyway.

### The number that decides it

Rotating a raster costs 2 multiply-adds per **pixel** — 76,800 of them.
Rotating a polyline costs 2 multiply-adds per **vertex** — about 200.

**384× the work for the identical visual result.**

Related, and counter-intuitive: **scrolling was never the problem.** At 50 km/h,
zoom 16 at Bengaluru's latitude is 2.33 m/px, so the map translates at **6 px
per second**. Two or three FPS would be visually fine. It is rotation that
demands 13–40× that frame rate — and rotation is exactly what raster cannot do
here.

### Vector route rendering: recommended

Phone decimates the route polyline (Ramer–Douglas–Peucker, ~10 m), clips to a
~1 km window, projects to a local metric frame, and sends it.

- **Payload:** 200 points × 4 bytes (int16 decimetres) = **800 bytes.** Two BLE
  notifications at a 517-byte MTU. Add a road-class byte and 10–15 surrounding
  roads still fits under 4 KB.
- **ESP32 work:** rotate ~200 points (microseconds), draw ~200 wide lines
  touching 4–10% of the screen. Render into a 4bpp (38 KB) or 8bpp (77 KB)
  sprite — both fit comfortably.
- **Result:** ~16–20 FPS **with heading-up rotation included**, on the board
  already owned, over the BLE link already built, with no SD card.

An ESP32-C3 — weaker than the LOLIN32 — renders vector maps at 60 FPS.

**It also pulls in the same direction as the sunlight gate.** A raster basemap
is inherently low-contrast, thin-lined and mid-toned — the worst case for glare.
A bright vector route on a plain background is the highest-contrast thing this
panel can display. Raster fights the gate; vector helps it.

### If raster is ever wanted anyway

**Waveshare ESP32-S3-Touch-LCD-2.8**, ~$25–30: ESP32-S3, 8 MB PSRAM, 16 MB
flash, 240×320 ST7789 (same form factor), **microSD already on board**, 6-axis
IMU, battery connector. Removes all three blockers at once.

Do **not** buy the ESP32-2432S028R "Cheap Yellow Display" — classic ESP32, no
PSRAM, i.e. the exact wall already hit.

Bengaluru tile storage, for reference: ~2,100 tiles at z16 → 275 MB raw RGB565,
137 MB indexed 8bpp, ~45 MB JPEG. Storage was never the constraint.

### Decision

**Vector first, on the existing board.** If the basemap is genuinely missed
later, buy the $25 S3 board and add raster tiles *underneath* the vector layer
already built. That ordering costs nothing and de-risks everything.

### Decision — 26 Aug 2026

**Vector route line, on the existing board.** Sarath's call. Build it after the
BLE link exists, since it rides on the same transport. No board purchase.

---

## AI desk buddy — SPLIT: visual half yes, voice half needs a new board

**Proposed:** the device doubles as an AI companion / ambient display on the
desk when it is not on the bike.

### The config gate that settles it

XiaoZhi (`78/xiaozhi-esp32`, 29k★, MIT, active) is the dominant project in this
space, and it *does* have a first-class plain-ESP32 target — a 4 MB flash build
matching this board exactly. But its own `Kconfig.projbuild` gates the
interesting parts:

```
Wakenet model without AFE   depends on IDF_TARGET_ESP32 && SPIRAM
Wakenet model with AFE      depends on (ESP32S3 || ESP32P4) && SPIRAM
Multinet (custom wake word) depends on (ESP32S3 || ESP32P4) && SPIRAM
Audio processor             depends on (ESP32S3 || ESP32P4) && SPIRAM
Camera menu                 depends on !IDF_TARGET_ESP32
```

**No PSRAM means no wake word, no acoustic echo cancellation, no camera.** Not a
porting problem — an explicit dependency. The underlying reason is the audio
front end: AEC ~114 KB, noise suppression ~27 KB, AFE layer ~73 KB. Over 200 KB
of internal SRAM on a chip where WiFi, TLS and the display already contend for
~150–250 KB.

### What genuinely runs on the LOLIN32 today — software only

- **Ambient dashboard** — weather, clock, calendar, transit, pomodoro. Saturated
  with working code; the "Cheap Yellow Display" community is effectively this
  hardware.
- **LLM-generated daily briefing over HTTPS.** Best done with the
  [`kyleturman/home-dashboard`][khd] pattern (300★, MIT): a small server hits the
  APIs, calls Claude, renders the layout, and returns a **pre-rendered image or
  pre-wrapped text**. The microcontroller does no JSON parsing, holds no API key,
  and owns no layout code. On a 4 MB no-PSRAM board this is not a compromise,
  it is the correct design — and it keeps the API key off a device that lives on
  a motorbike.
- **Ask-a-question without a mic** — ESP32 serves a small LAN page, question
  typed on the phone, answer renders on the TFT. No STT, no cost.
- **Animated character with moods** — [`FluxGarage/RoboEyes`][re] (801★, GPL-3.0)
  is a pure Adafruit_GFX drawing library: happy / tired / angry, autoblink, idle
  drift. No PSRAM, no AI. Drive the mood from data (calendar density, weather)
  rather than conversation.
- **Phone notification mirror** — [`fbiego/chronos-esp32`][chr] (174★, MIT) pairs
  over BLE and delivers notifications, weather, phone battery, time sync **and
  turn-by-turn navigation**. Note it therefore serves *both* roles.

### What needs a cheap part (~₹1,000 total)

| Part | ~Cost | Unlocks |
|---|---|---|
| INMP441 I2S mic | ₹400 | **Push-to-talk voice.** I2S DMA chunks streamed over WebSocket to own server → Whisper → LLM. No PSRAM needed because audio is never buffered whole. Working repos exist. |
| MAX98357A + speaker | ₹500 | Spoken replies, if the server sends low-bitrate PCM so the ESP32 decodes nothing |
| microSD module | ₹300 | Fonts, sprite sheets, animation frames. Relieves flash pressure for *assets*, not code |
| Reed switch or ID resistor | ₹100 | Deterministic dock detection |

**The real ceiling is 4 MB flash**, and no cheap part fixes it. TLS + LVGL +
fonts + audio libraries get uncomfortable.

### What genuinely requires a different board

All PSRAM/SIMD-gated, none of it a porting effort: always-on wake word, AEC and
barge-in, offline command words, OpenAI's Realtime voice-to-voice (ESP32-S3
only, full stop), on-device LLM inference (needs ESP-DSP SIMD that only exists
on S3), and camera.

On-device LLM is worth dismissing explicitly: the flagship demo runs a
**260K-parameter** TinyStories model at 19 tok/s on an S3. A newer build reaches
28.9M params at ~9.5 tok/s. These are toys, not assistants. Do not chase this.

**If voice is wanted: `ESP32-S3-DevKitC-1-N16R8`, ~$15–20.** 16 MB flash, 8 MB
PSRAM, keeps the existing ILI9341 and wiring, unlocks the entire stack.

### Dual-mode detection

No canonical open-source project does context-switching personalities. The
mechanisms are well understood though:

- **WiFi SSID presence** — zero hardware, fails safe (out of the house = bike).
  Best primary signal.
- **Dock ID resistor on an ADC pin** — pennies, deterministic. Good override.
- **BLE connection state** — phone pushing nav = bike mode.
- **Not VBUS sense** — USB-powered in both modes, so it tells us nothing.

Note **WiFi + BLE coexistence on plain ESP32 costs real RAM.** Running one radio
per mode is better, which dual-mode gives for free. Keep it as one firmware with
a mode branch, not two OTA slots — 4 MB flash will not hold two app partitions
plus a filesystem once TLS and fonts are in.

**And the cleanest answer of all:** if an S3 is bought for voice, put the S3 on
the desk and leave the LOLIN32 on the bike. Two devices, no dual-mode problem,
no compromise on either side.

[khd]: https://github.com/kyleturman/home-dashboard
[re]: https://github.com/FluxGarage/RoboEyes
[chr]: https://github.com/fbiego/chronos-esp32
