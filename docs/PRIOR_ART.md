# Prior art

Surveyed 22 Aug 2026. What already exists, what is worth taking, and what is
worth avoiding.

**Nothing found does this exact combination** — Google Maps → Android
`NotificationListenerService` → BLE → ESP32 + ILI9341 + TFT_eSPI — and nothing
with a real star count is both alive and licensed for reuse. But every
individual piece exists somewhere, and two of the non-obvious gotchas below
would each have cost an evening to rediscover.

---

## Take these

### Notification-removal debounce — [DEMP1993/Drive-assistant-android-app][demp]

Kotlin · pushed 23 Aug 2026 · same architecture as this project, freshly written

**Maps removes and immediately re-posts its notification during active
navigation.** Treating `onNotificationRemoved` as "route ended" makes the
display flap between navigating and idle mid-ride. Fix is a ~15 s debounce
(`NAV_END_DELAY_MS`). Written up in `NAV_DATA.md` under state detection.

Its other idea — skip maneuver classification entirely, render the icon to a
40×40 monochrome bitmap and ship the raw bits (~200 bytes) — is a legitimate
fallback if icon identification ever breaks.

### ESP32-initiated refresh — [alexanderlavrushko/BLE-HUD-navigation-ESP32][lav]

C · 169★ · abandoned Jul 2022 · **no licence file, so no legal reuse**

The most-starred project in this space. Data source is Sygic on iOS, so the
phone half is irrelevant, but the ESP32 half is this build. One idea worth
copying: **the ESP32 sends an empty indication when the phone goes quiet**,
prompting a refresh rather than waiting. Directly relevant, because Maps can go
64 s without changing a field in slow traffic.

Its 38-value maneuver enum includes **16 roundabout variants** (handedness ×
exit bearing), which independently validates reserving `0x20`–`0x2F` for
roundabout exits in `BLE_PROTOCOL.md`.

The live fork [pigro141/…-LilygoTDisplayS3][pig] uses TFT_eSPI directly and adds
a display state machine. Note it asserts MIT over an unlicensed upstream, which
is legally shaky — read it, don't copy from it.

### Protocol shape — [deanthecoder/SteedPilot][steed]

C/C++ · MIT · active

The best-designed BLE protocol found. Versioned JSON with two packet types:
`state` (full replace, on maneuver or route change) and `update` (partial
patch, frequent, for distance and progress), plus a heartbeat. Explicit route
lifecycle driving device-side screens, including `NO PHONE` after 10 s silence.

Worth comparing against our typed binary framing. Ours is more compact; theirs
is more evolvable. The idea worth stealing regardless is **full-replace versus
partial-patch as distinct packet types**, which removes a whole class of
"display drifted out of sync" bugs.

### Maneuver vocabulary — Gadgetbridge + [Bangle.js apps][bangle]

AGPL-3.0 / MIT · both active

Gadgetbridge's `NavigationInfoSpec` is an 18-value action enum; the Bangle.js
`messagegui` app enumerates 16 canonical action strings (`continue`, `left`,
`left_slight`, `keep_left`, `uturn_left`, `roundabout_left`, `finish`, …) and
carries a 1-bit arrow bitmap per case. A sane, proven-size vocabulary that maps
cleanly onto what Maps actually emits.

It also swaps roundabout art for left- and right-hand traffic — relevant here,
since India is left-hand and most icon sets assume right.

**Pragmatic shortcut worth considering:** implement Nordic UART Service and the
Bangle.js `GB({t:"nav",…})` handshake on the ESP32, and let Gadgetbridge be the
Android app. Zero Android code to write and a maintained parser — at the cost of
OsmAnd rather than Google Maps as the source, and AGPL.

---

## Investigate, do not assume

### Resource-name maneuver classification — [Kiroha/byd-dashcast][byd]

Java · 69★ · MIT · pushed 23 Aug 2026

Resolves the maneuver by **resource entry name** rather than by pixels:

```java
int resId = n.getSmallIcon().getResId();
String name = createPackageContext(pkg, 0).getResources()
                .getResourceEntryName(resId).toLowerCase(Locale.ROOT);
```

then substring-matches against a 33-entry table (`arrow_right`, `slight_left`,
`u_turn_right`, `roundabout_cw`, `merge_left`, `tollbooth`, …). If it works it
is **locale-independent and version-tolerant** — strictly better than hashing.

**But it probably does not apply to us as written.** It reads `smallIcon`, and
our own logs show `smallIcon` resolving to `nav_notification_icon` — a generic
Maps icon, not a maneuver — while the maneuver arrives as `chipIcon` with
`type=1` (bitmap), which carries no resource name to read.

Most likely this reflects a pre-Live-Updates Maps layout. **Worth one
experiment**, not a rewrite: check whether any icon field on our setup is
`type=2` with a name that varies by maneuver. If not, pixel matching stays.

Its ordered `TEXT_KEYWORD_MAP` fallback (most-specific-first, so "u-turn right"
beats "right") is a good pattern regardless.

### RemoteViews walking — [3v1n0/GMapsParser][gmp]

Kotlin · 54★ · LGPL-3.0 · **abandoned Jun 2023**

The reference pre-Live-Updates parser. Inflates the notification's RemoteViews
and walks the view tree **by resource entry name** (`nav_title`,
`nav_description`, `nav_time`) rather than regexing text.

Largely superseded for us — under ProgressStyle the data arrives as typed
extras and `contentView` never appears. Kept here because it is the fallback
path if Maps ever reverts or if Live Updates is disabled on the phone. Its
`NavigationData.diff()` (only push changed fields over the wire) is a good idea
independent of all this.

---

## Closest analogues

- **[rabbihossain/BikeNavESP32][bikenav]** — ESP32 + ST7796 + LVGL, explicitly
  aimed at the Royal Enfield Tripper / Beeline Moto niche. **No licence**, so no
  reuse, and the Android companion is unpublished. Its 40 icon names are a clean
  taxonomy worth reading. Sends the maneuver as an integer index into an image
  array — same shape as our approach.
- **[CitizenOneX/gmaps_nav_hud_frame][frame]** — Maps notification → Brilliant
  Labs Frame glasses, Flutter, BSD-3. Documents the same "existing sessions only
  update roughly every minute" gotcha we measured as 64 s.

## Avoid

- **[ManDrake-hub/Navigator][mandrake]** — right architecture, but `NavParser.kt`
  is pure Italian-language regex (`"tournez à droite"`, `"sei arrivato"`).
  Locale-locked and brittle. A worked example of what not to do.
- **Android Auto as a data source** ([mossyhub/openautolink][oal] is the only
  serious attempt) — reverse-engineered protocol, USB/WiFi transport, head-unit
  persona required. One developer cites 600+ hours. Worse fragility than
  notification reading, not better.
- **Dead or trivial**, listed so they are not rediscovered: `appleshaman/
  CarPlayBLE` (181★ but abandoned 2024), `RaysceneNS/MotoHud` (dead 2018),
  `shreyasgokhale/bikelane` and `mrmattuschka/yokai` (Komoot, dead 2022),
  `prabir-rout/BikeNav-v1.0`, `meghundul/WaveTurn`, `IamThejus/MotoNav`,
  `hyutrn/Mini-Oled-Navigation`.

---

## The maker scene — crowded at the demo, empty at the product

**ProntoFPV is a person, not a product.** A Tamil-language Indian tech and drone
creator, ~19.3K Instagram followers, no company and nothing for sale. His
"ProNav V2" reel did **1.87 M plays, 66 K likes, 385 comments**, and a helmet
version ("NavMet P1") followed in Aug 2026. Across five nav posts he has
published **no price, no shop link, no schematic, and no repo** — and the
comments are wall-to-wall "price?", "how do I buy this", "code link plz",
unanswered.

At least four independent people arrived at **this exact architecture** —
Android notification scraping → BLE → small ESP32 TFT:

| Who | Notes |
|---|---|
| [maisonsmd/esp32-google-maps][mai] | Closest match to this build. Notification scraping, LVGL, ESP32-C6. Open source, working. |
| [appleshaman/CarPlayBLE][cpb] | 181★, GPL-3.0, TTGO T-Display. Abandoned 2024. |
| u/MuchAssumption6114 | ESP32-C3 + OLED, ships the maneuver **bitmap** rather than classifying it. Repo URL not locatable. |
| ProntoFPV | Viral, closed, unpublished. |

**Worth a serious look: [fbiego/chronos-esp32][chr]** — 174★, MIT, plus a free
Android app. The ESP32 presents as a smartwatch over BLE and receives
notifications, music, phone battery **and turn-by-turn navigation**. It solves
the entire phone side generically, with an app someone else maintains.

The trade-off is real, though: adopting it means giving up the
`progressSegments` traffic profile and the parser documented in `NAV_DATA.md`,
which is the one genuinely novel asset here. Worth evaluating as a fallback if
maintaining an Android app becomes the thing that kills the project.

### Commercial context for this bike specifically

**Triumph has an official Beeline partnership.** The Triumph-branded Beeline is
~$279 and explicitly lists the Speed 400 as compatible. Royal Enfield Tripper,
Blucap Moto and Thork Racing DMD occupy the rest of the slot. Nothing DIY on
Tindie or Crowd Supply.

### The read that matters

The idea is not novel and the implementation is solved several times over. What
is conspicuously unsolved is **everything after the demo** — not one of these
makers ships, sells, or reliably open-sources.

ProntoFPV's 1.87 M views with 385 unanswered "how do I buy this" comments is
simultaneously proof the demand is real and proof that converting a viral reel
into a weatherproof, sunlight-readable, mountable object is where everyone
stalls.

**That stall point is exactly the sunlight gate this project already gates on.**
The differentiating work here is not the BLE protocol or the notification
parser — those are commodity. It is the enclosure, the IP rating, and a display
legible at noon: the three things every project on this list either skips, tapes
together, or openly admits it has not done.

Relevant to that: [Volos Projects — "ESP32 E-Bike Dashboard You Can See in
Sunlight"][volos] (May 2026) solves it with an **RLCD**, which is the same
reflective-display conclusion the brightness research reached independently.

## What this survey did not change

Our own vector arrow glyphs stay. The two available icon sets
(pigro141's 64×64 4bpp PROGMEM art, BikeNavESP32's 40 LVGL images) are both
licence-encumbered, and vector paths remain smaller in flash and scale to any
band size, which bitmaps do not.

The binary packet framing in `BLE_PROTOCOL.md` stays too. Everything found
either uses JSON, which is heavier on BLE, or an undocumented byte layout.

[demp]: https://github.com/DEMP1993/Drive-assistant-android-app
[lav]: https://github.com/alexanderlavrushko/BLE-HUD-navigation-ESP32
[pig]: https://github.com/pigro141/BLE-HUD-navigation-ESP32-LilygoTDisplayS3
[steed]: https://github.com/deanthecoder/SteedPilot
[bangle]: https://github.com/espruino/BangleApps
[byd]: https://github.com/Kiroha/byd-dashcast
[gmp]: https://github.com/3v1n0/GMapsParser
[bikenav]: https://github.com/rabbihossain/BikeNavESP32
[frame]: https://github.com/CitizenOneX/gmaps_nav_hud_frame
[mandrake]: https://github.com/ManDrake-hub/Navigator
[oal]: https://github.com/mossyhub/openautolink
[mai]: https://github.com/maisonsmd/esp32-google-maps
[cpb]: https://github.com/appleshaman/CarPlayBLE
[chr]: https://github.com/fbiego/chronos-esp32
[volos]: https://www.youtube.com/watch?v=EKnZ7ZisUj4

---

## NAVRIDER (navrider.in) — the closest peer, and a different architecture

Surveyed 27 Aug 2026. An Indian two-wheeler navigation device, Bangalore
jurisdiction, "prototype in active testing", launch stated as end of 2026.
Instagram first posts **3–4 Aug 2026**, ~266 followers.

**Scale, honestly:** no founder names, no LinkedIn page, no funding, no press,
no MCA or Startup India record, and the ToS never names a legal entity. This is
a one- or two-person prototype with a good marketing site — a peer project, not
a funded competitor. Their build log runs **~4 months from first pixel to
rideable prototype**.

### ★ They do not scrape Google Maps — and that is the whole difference

Their `/permissions/` page is effectively a negative confession: Location,
Bluetooth, battery-optimisation exemption, and Notifications marked *optional*
for "ride/pairing/firmware-update alerts", with the explicit note that
*"nothing about navigation itself depends on this one."* **No
NotificationListenerService. No AccessibilityService.**

They don't need one, because they own the navigation session end to end. Their
privacy policy names the whole stack:

| Component | Role |
|---|---|
| **Self-hosted Valhalla** on Oracle Cloud, Mumbai | the actual routing |
| Google Maps Platform | place search, geocoding, directions |
| Mapbox | map display and routing |
| Cloudflare | serves their map-tile service |
| Open-Meteo | weather along route |
| Firebase | auth, database, push, analytics |

### The architectural fork this exposes

| | This project | NAVRIDER |
|---|---|---|
| Source | scrape the Maps notification | own the route, self-hosted Valhalla |
| Cost | free | an always-free ARM VM |
| Traffic | **Google's, which is excellent** | OSM-based, no live traffic |
| Route geometry | **none — cannot draw a line** | full polyline |
| Lookahead | none, Maps gives one turn | whole route |
| Speed limits | none | from the routing response |
| Destination entry | Maps does it | must be built |
| Fragility | breaks ~annually | stable API |

**Valhalla returns an encoded polyline (6-digit precision) plus maneuvers plus
speed limits.** That is exactly the data notification-scraping can never
provide, and it is the same engine the lane-guidance research independently
recommended — see FEATURES.md, where `turn_lanes` gives per-lane `valid` and
`active` bitmasks. Someone is now running that stack in production for this
exact product category, in Mumbai, on the free tier.

### Confirmed: route polyline, no basemap

Instagram bio, verbatim: *"India's first compact motorcycle navigation device
with **Route Polyline display**."* Note the walk-back — their launch post said
"full map display" and the next day's reel said "route poly line". Marketing
still overclaims ("World's first real-time maps"), but the product renders route
geometry as vectors.

**Independent validation of the vector decision in this project's FEATURES.md.**
Not a compromise forced by weak hardware — the right design for a glanceable
bike display.

### Hardware

**1.75" round AMOLED**, CNC unibody, USB-C, BLE 5.0, internal battery, universal
bar clamp. No published IP rating, only "water resistant".

*Inference, not stated:* that panel points hard at the **Waveshare
ESP32-S3-Touch-AMOLED-1.75** — 466×466 QSPI, ESP32-S3R8 with **8 MB PSRAM**.
Which is the same board the map-feasibility research named as the upgrade path.
Their bring-up captions ("driving every segment", "after a driver change") fit a
QSPI panel story.

Phone-tethered, **no onboard GNSS** — device-side data they store is only MAC,
firmware version and last-seen.

Their hero image alt text reads *"mounted on **Triumph** handlebar"*.

### Worth stealing

- **Self-hosted Valhalla on an Oracle always-free ARM VM.** The headline.
- **Send geometry over BLE, not pixels.** Decimated polyline plus maneuver
  metadata; the device redraws locally at GPS rate. Survives a stuttering link.
- **OTA firmware over BLE from the companion app** — they had it working by
  17 April. Removes the COM-port flashing loop entirely, which matters here
  given the rule about never opening the port from a script.
- **Dark theme with a saturated blue route line** won their readability
  shootout against light, green and red. *Caveat: they are on AMOLED and this
  project is on a TFT, so the result may not transfer to the sunlight gate.*
- **Open-Meteo** — free, no key, no attribution burden.
- **The battery-optimisation whitelist problem is real.** They name ColorOS,
  HyperOS/MIUI and FuntouchOS, and admit the vendor toggles have no public API
  so the app cannot verify completion. If our Android app dies mid-ride, that is
  why.

### Not open source

No GitHub org, no SDK, no attribution page, and **the app is not on either
store yet** — so the Play Store OSS-licences screen, which would enumerate their
whole Android dependency tree, does not exist. Worth re-checking once they ship;
it is the single most informative artifact they will ever publish.

### "CNS"

No such term appears anywhere in connection with them. Most likely a mishearing
of **CNC** — "CNC UNIBODY" is a headline feature on their site. Recorded so it
is not chased again.
