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

### Decision — DEFERRED, 26 Aug 2026

**Skipped for now, to be built later.** The bike side is unfinished and the
sunlight gate is unresolved; adding a second product now is how projects die.

Sarath asked specifically whether a mic and speaker can be added to this board.
**Answer: yes, and it buys push-to-talk — not a wake word.**

| Part | ~₹ | Notes |
|---|---|---|
| INMP441 I2S mic | 400 | Audio streams as I2S DMA chunks straight out over WebSocket. Never buffered whole, so no PSRAM needed. |
| MAX98357A + speaker | 500 | Have the server send low-bitrate PCM so the ESP32 decodes nothing. |

Flow: button → stream to own server → Whisper → LLM → text/audio back. Working
repos exist for exactly this on plain ESP32 and ESP32-C3.

What it will **not** do is always-on "hey buddy" — that needs the AFE, that
needs PSRAM, and no external part fixes it. If that turns out to matter, the
answer is a **$15–20 ESP32-S3-DevKitC-1-N16R8** as a separate desk unit, leaving
this board on the bike.

Start with the visual half — dashboard, briefing, notification mirror,
RoboEyes. It needs no parts at all and proves the idea before any money is spent.

---

## Power: battery vs cable — CABLE, NO BATTERY

**Proposed:** run from the bike now, add a battery later so it works when the
bike is off.

### The charger can't do what it looks like it can

The LOLIN32's charge IC is a **TP4054**; the regulator is an **ME6211**
(3.3 V, 500 mA LDO). The board's 5 V pin is **just VBUS** — it reads 0 V on
battery — which means the ME6211's input is the **BAT node**, i.e. the load
hangs off the charger's output.

**There is no power-path IC.** That topology has a specific documented failure:
the charger terminates when current falls to C/10, and it cannot tell charge
current from load current. With ~200 mA of load against a ~50 mA threshold, it
**never terminates**, and the cell sits float-held at 4.2 V indefinitely.

**There is also no battery protection of any kind** — no over-discharge, no
over-current, no cell temperature sensing. TP4054 has no NTC pin. All protection
would have to come from a protected cell.

*Verify in 60 seconds:* unpowered, check continuity from the JST "+" pad to the
ME6211 input, and from the 5 V pad to the same pin. If BAT+ beeps and 5 V does
not, the topology is confirmed.

### Runtime — an earlier claim corrected

An earlier guess that the backlight would limit this to about an hour was
**wrong**. Measured LOLIN32 draw is 55.7 mA awake at 3.7 V; add 35–80 mA for
connected BLE, 6–10 mA for the display controller, 60–100 mA for the backlight.
Call it **200 mA**.

Usable capacity is ~80% of rated, because the ME6211 needs ~3.56 V in at that
load:

| Cell | Runtime @200 mA |
|---|---|
| 1000 mAh | ~4 h |
| 2000 mAh | ~8 h |

So runtime was never the problem. **Fit is:** a 2000 mAh pouch is 10.2 mm thick
in a 20 mm enclosure that already holds a 2.8" TFT and a headered LOLIN32.

### ★ Safety — do not put a LiPo in this enclosure

Not primarily a fire argument. Thermal runaway needs 150 °C+; solar heating
will never get there. The realistic outcomes, in order:

1. **The cell becomes a consumable.** Battery University: 60 °C at 100% charge
   leaves **60% capacity after three months**. This device float-holds at 4.2 V
   in a hot box — the worst square on that table.
2. **Pouch swelling in a sealed rigid box.** A pouch has no CID, no PTC, no
   calibrated vent. It protects itself *by swelling*. In sealed PETG it has
   nowhere to go but into the PCB.
3. **Charging above 45 °C on every sunny day.** This is the one path that does
   lead somewhere dangerous — lithium plating creates internal shorts that
   initiate runaway later, at normal temperatures. Cell datasheets say charge
   0–45 °C; estimated parked interior is **53–63 °C light PETG, 65–70 °C dark**.
   The TP4054 will charge a 60 °C cell without complaint.

### The thermal finding that outranks the battery question

**The display fails before anything else.** 2.8" ILI9341 modules are rated
**operating −20 to +70 °C**. Solar radiation raises display surface temperature
**40–50 °C above ambient**, and a documented case had a 50 °C-rated panel reach
**90 °C in sun and black out completely**, with repeated exposure causing
permanent "solar clearing" spots.

**PETG is also wrong.** HDT 65–80 °C, Tg 75–85 °C — inside the estimated
interior range. **Use light-coloured ASA:** better UV stability, ~105 °C
service, no yellowing. This supersedes the PETG guidance in `HARDWARE.md`.

### What the industry does

The **Chigee AIO-5 Lite** — the closest commercial analogue, permanently
handlebar-mounted, always-on, IP67, rated −20 to +65 °C — **contains no battery
at all** and runs on bike power. Thinkware dashcams use supercapacitors and ship
a thermal protection mode that degrades above 65 °C, a manufacturer conceding
in-vehicle temperatures routinely exceed that. Garmin Zumo XT publishes
operating −15 to +55 °C but **charging 0 to +45 °C**.

### Decision: cable power, no battery

The device does not need one. NVS is already **power-fail safe** by design —
entries are written atomically with a CRC and an incomplete write is discarded
on next boot — so a sudden power cut costs nothing.

**Build order:**

1. **Get off USB.** Solder bike switched 5 V to the LOLIN32's 5 V and GND pads;
   the micro-USB connector is not a vibration-rated interconnect. Add
   **SMBJ6.0A** TVS (*not* 5.0A — that sits inside the USB tolerance band and
   will cook), 220 µF **hybrid/polymer** cap (a standard 85 °C electrolytic
   dries out fast at 60 °C), 100 nF ceramics, ferrite bead, 1 A polyfuse.
2. **Measure, don't estimate.** A USB power meter inline, and a logging
   thermometer sealed in the enclosure parked in sun for a week. Both numbers
   above are estimates and both decide the design.
3. **Fix thermal** — light ASA, ePTFE vent, backlight on PWM.
4. **Graceful shutdown, if wanted.** See the sizing below — the trick is to shed
   load first, which turns a supercapacitor subsystem into a single capacitor.

### The Triumph socket — verified from the handbook

The Speed 400 / Scrambler 400 X owner's handbook, p.64 and the fuse tables:

- **5 V output, loads up to 2.4 A** — 8× this device's draw.
- **Fuse 8, USB socket, 5 A**, in fuse box 1 under the seat.

**Use the factory socket rather than tapping 12 V.** Its buck converter *is* the
transient barrier: load-dump energy is absorbed there, not downstream. Tapping
raw 12 V means personally solving 6–16 V continuous, **18 V for 400 ms**,
**26 V for 60 s of jump start** (DC — no TVS helps), and ~35–40 V clamped load
dump, for no benefit this device needs. Note the popular cheap MP1584 module is
28 V max and **fails the jump-start case outright**.

Motorcycles differ from cars here in a way that helps: a permanent-magnet
alternator has no field winding to de-excite, so the classic 400 ms field-decay
load dump does not exist in the same form. But the battery is small — a
**YTX9-BS, 12 V 8 Ah** — so the rail is less stiff and switching transients from
horn, indicators and fan are proportionally larger than in a car.

**Still unverified: whether the socket is ignition-switched or always live.**
The handbook does not say; the fuse layout suggests it sits behind the main
relay, and owners report it only works with the engine running. That is
inference. **Measure it** — a USB power meter answers it and gives the real
current limit at the same time. It matters: if the socket is always live, a dev
board drawing even 10 mA flattens an 8 Ah battery in a couple of weeks parked.

### Hold-up sizing — shed load first

An earlier figure of "2200 µF ≈ 50 ms" was optimistic. The arithmetic is
C = I·Δt/ΔV, and with the backlight and radio still running at ~250 mA against a
1 V usable drop, **20 ms needs 5,000 µF** and 50 ms needs 12,500 µF. That is a
lot of electrolytic to strap to a handlebar.

**So shed load in the first millisecond.** The ignition-sense interrupt kills the
backlight and stops the radio, dropping to ~50 mA — and then **20 ms needs only
1,000 µF**. One capacitor, not a subsystem.

**Do not use a supercapacitor.** An uncharged supercap is a short at power-on;
against the socket's 2.4 A limit it will either trip the limit or make it fold
back and never start. It needs a soft-start path and an isolating diode — a real
design, not a two-part addition.

**Better still, avoid needing hold-up at all:** write state to NVS when it
*changes*, debounced, during normal riding. Then key-off requires no write and
the problem evaporates. Keep volatile state in RTC slow memory, which survives
deep sleep without touching flash.

Note the ESP32's own brownout detector trips at ~2.43–2.80 V, *below* the 3.0 V
recommended minimum — by the time it fires the chip has been out of spec for a
while. It is a last-resort reset, not a power-fail warning. Generate the warning
upstream with the ignition-sense pin.

### The protection stack, under ₹100

PPTC (0.5 A hold, ≥6 V rated) → **SMBJ6.0A** TVS → P-channel FET for reverse
polarity (~10–25 mV drop, versus 0.35–0.45 V for a Schottky, which this rail
cannot spare) → pi filter (10 µF – ferrite – 10 µF + 100 nF) → 1000 µF hold-up
behind an isolating Schottky.

Two traps: **MLCCs lose most of their capacitance under DC bias** — a 10 µF
6.3 V 0603 X5R at 5 V may deliver 2–4 µF, so specify 16 V or 25 V parts. And a
PPTC is a **fire-prevention device, not a semiconductor protector** — time to
trip at 2× hold is seconds.

---

## Alerts: calls and notifications — BUILT

**Proposed:** show incoming calls and phone notifications without harming the
navigation view.

### The pattern: a band that is blank until it matters

Bottom strip, y=190–240. It does double duty and therefore **costs no extra
pixels**:

| State | Band shows |
|---|---|
| Far from a turn, nothing happening | arrival time, distance remaining |
| Incoming call | **whole band inverts** — black block, white text, persists while ringing |
| Notification | same inversion, **self-dismisses after 6 s** |
| **Under 100 m to a turn** | **blank. Always.** |
| Link down or stale | blank |

Precedence lives in one function, `bandFor()`, for the same reason `screenFor()`
exists.

### Why inversion rather than text

Full-block luminance inversion is the single most blur- and glare-robust
encoding this panel has — large, low-spatial-frequency, and detected
peripherally without costing a glance. Small text is the opposite: it needs
foveation, which is the resource the whole design is trying to protect.

### Why alerts lose to the turn, always

BUILD_PLAN Stage 9 already said "suppressed below 100 m to a maneuver", and
that is right regardless of how urgent the alert feels. **A missed call costs
nothing. A missed junction in Bengaluru traffic costs a great deal.** Alerts
under 100 m are not queued for later either — by the time the turn is done the
notification is stale, and a stale alert is noise.

### Speed: deliberately NOT added

Research ranked current speed as the highest-value addition — every reference
device has it, and it is free from phone GPS. **Rejected on local knowledge:
the Speed 400 has a speedometer six inches away.** Duplicating an instrument
the rider already has is pure cost. Recorded so it is not re-proposed.

### Protocol

`0x03 CALL` was already specified and is now implemented. `0x08 NOTIFY` is new:
`u8 kind, u8 src_len, utf8 src, utf8 text`, length-prefixed rather than
NUL-separated because `0x04 MEDIA` is the one row that splits on NUL and a
generic trailing-text reader eats its second field.

Still refused, per the research: now-playing (text you must parse, no
navigational value), continuous traffic display (invites study, not glance),
persistent battery percentage (a re-glance magnet — show it below 20% only).

---

## Lane guidance — REOPENED and re-closed, 26 Aug 2026

Revisited after asking whether the phone's gyroscope plus an open-source map
could do what Google does. The answer reframes the feature.

### The reframe: lane guidance does not need to know your lane

"Use the left 2 lanes to turn left" is **advisory**. Google's classic lane
guidance does not know which lane you are in. Neither does OsmAnd's lane widget
nor Valhalla's lane output. They all read map data and tell you where to *be*.

"Which lane am I in" is a **different, optional, and far harder** feature. It
was never needed for what was asked. That kills the gyroscope question before
the physics does.

### But the physics kills it too

**A car lane change produces lateral acceleration. A motorcycle lane change is
engineered not to.** The rider leans precisely so the resultant of gravity and
centripetal force stays aligned with the bike's vertical axis — so in a
coordinated lean the lateral accelerometer reading is *near zero by
construction*. The signal every car-based algorithm integrates is not there.

What remains is a roll-rate doublet, shared with cornering, filtering, swerving
round a pothole, and a rider shifting weight. On Bengaluru roads all of those
happen constantly. And MEMS bias drift grows position error as t², reaching
metres within seconds — you cannot resolve 3.5 m against that.

Handlebar mounting makes it worse: the phone measures *steering input* on top of
chassis motion.

### What Google actually did — the decisive data point

Google has dual-frequency GNSS, 3D building models, planet-scale ML and its own
HD map. Its "Live lane guidance" — the feature that says which lane you are
*currently* in — **uses the car's front-facing camera** with AI lane-marking
detection. Shipped on the Polestar 4, Google Built-in only.

**If a camera is the cheapest path for Google, an ESP32 and a phone gyro will
not beat it.** And on Bengaluru's marking quality a camera would struggle too.

### And Google does not offer lane guidance in India at all

Classic lane guidance is pure map data from Google's proprietary road
attribution — US, Canada, Japan, ~20 European countries. **India is not on the
list.** The feature being asked for is one Google itself does not provide here.

### Positioning, for the record

- **S24+ is dual-frequency (L1+L5, E1+E5a)** — confirmed. Standalone accuracy
  tops out at **2–3 m** against a **3.5 m** Indian lane (IRC standard). Not
  lane-level, and wrong in ways you cannot detect.
- Raw `GnssMeasurement` with RTK: the Google Smartphone Decimeter Challenge
  first went below 1 m in 2023–24 — **offline, post-processed, by a funded
  expert**. Real-time urban RTK fixes **under ~35%** of the time even with good
  hardware. On a vibrating, body-shadowed, handlebar-mounted phone, worse.
- **Survey of India CORS** exists (1,105 stations, NTRIP, ±3 cm) but free
  subscription is government and academic only. Free community casters have no
  Bengaluru base within range.

### The map data is still the blocker

Unchanged at **0.52%**. And the alternatives have closed further:

| Source | Lane turn data for Bengaluru? |
|---|---|
| **Mappls / MapmyIndia** | **Yes** — Routing API returns a lanes array. Opaque pricing, mandatory logo, free plan terminable. Swaps Google dependence for Mappls dependence |
| Overture Maps | **No** — `lanes` was *removed from the schema*, never populated |
| TomTom Orbis Lane Model | Germany-first, no India commitment, automotive licensing |
| HERE | Lane attributes exist; India coverage undocumented, not in the free REST tier |
| Bhuvan / ISRO / NHAI | No lane topology at all |

### The tractable path, if it is ever wanted

1. **30-minute sanity check first.** Install OsmAnd, enable the Lanes widget,
   ride two or three usual routes. It renders `turn:lanes` straight from OSM, so
   **whatever it shows is the ceiling** for any OSM-based system. Do this before
   writing any code.
2. **Tag your own junctions.** You do not ride 8,249 ways — you ride perhaps
   50–200 junctions regularly. JOSM over Esri World Imagery (legally traceable
   for OSM), verified against your own memory. **20–50 hours, one-time**, and it
   is upstream, so it fixes OsmAnd and Organic Maps for everyone else too.
3. **Self-host Valhalla.** With `turn_lanes` enabled each maneuver carries a
   `lanes` array with per-lane `directions`, `valid` and `active` bitmasks —
   `active` is exactly "the lanes to be in for this turn". Server-side, zero
   positioning required, straight over BLE.

That combination is genuine independence from Google, and the only real cost is
bounded manual mapping of your own commute.

### The better answer for Bengaluru

Where `turn:lanes` is absent, emit a coarse **"keep left" / "keep right"** hint
from OSM's `lanes` count plus turn direction, with staged warnings at 300 / 150
/ 50 m.

On arterials where lane discipline is weak enough that "lane 2 of 4" is a
fiction on the ground, **"get to the left edge, turn in 200 m" is the genuinely
actionable instruction** — and it needs no lane data and no lane-level
positioning at all.

### Decision — still closed

**Not building it.** The reframe removes the gyro question entirely, the physics
would have killed it anyway, Google does not offer this in India, and the map
data remains at 0.52%. The OsmAnd sanity check is the only cheap next step, and
it is a 30-minute errand, not a project.

---

## Data source: keep scraping Maps, do not switch to Valhalla — 27 Aug 2026

**Proposed:** replace notification scraping with self-hosted Valhalla, as
NAVRIDER does (see PRIOR_ART.md).

### Decision: no. Not now, and the reason is sequencing rather than merit.

### What Valhalla would genuinely give

Route geometry (the polyline needed to draw a line at all), lookahead past the
current turn, speed limits, lane data where tagged, and a stable API that does
not break roughly annually. All real, none of it available from the
notification.

### What it would cost

**Maps currently does four jobs beyond supplying data:** destination entry,
routing, rerouting, and off-route detection. The app only listens.

Valhalla hands all four back. It needs search and geocoding, a UI to choose a
destination, route calculation, deviation detection and re-request logic. That
is a real navigation app, and it is weeks of work to arrive back at today's
functionality.

**And it costs Google's live traffic**, which in Bengaluru is arguably the most
valuable single thing Maps provides. Valhalla on OSM has none.

### There is no easy middle, and this was checked

For lane guidance the answer was a one-shot enrichment query alongside Maps.
That pattern does not transfer. To draw a route you need *the route*, and the
notification gives a distance, not coordinates — so Valhalla cannot be asked for
the same route without knowing the destination, which Maps never discloses.

It is a genuine fork.

### The deciding argument

**The device has not completed a single real ride.** Switching architecture to
solve a problem that has not been experienced is the wrong order. Whether the
route line is missed is an empirical question, and Beeline built a product on
the premise that an arrow is sufficient.

### Why waiting is cheap

The protocol is already source-agnostic, by design. `BLE_PROTOCOL.md` states
that `next_maneuver` and `next_dist_m` are reserved *"so an OsmAnd or Mapbox
source can fill them without a protocol change."*

**The firmware does not care where packets originate.** Switching later costs
the Android work and nothing else — no firmware, no protocol, no display work is
wasted.

### Revisit on any of these

1. **After 5–10 real rides**, if the arrow proves insufficient at Bengaluru's
   messier junctions and the route line is actively wanted.
2. **When Maps breaks the format.** It does roughly annually and Gadgetbridge is
   already stuck on it. Migration becomes forced, and a scoped Valhalla path is
   then insurance rather than a project.
3. **If lane guidance becomes worth building** — Valhalla is already the
   recommended path there, so the two decisions collapse into one.

### One argument against, worth keeping

If the sunlight gate forces a monochrome reflective panel, a thin route line is
among the first things glare destroys. That weakens the case for switching
rather than strengthening it.
