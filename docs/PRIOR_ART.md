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
