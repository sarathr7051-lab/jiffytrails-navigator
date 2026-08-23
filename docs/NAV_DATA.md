# Google Maps navigation data on Android 16

Reverse-engineered from real rides, August 2026.
Samsung S24+, Android 16 / One UI, Google Maps current release.

**If you're building anything that needs live turn-by-turn data from Google
Maps on Android, this is the document to read.**

> ## ⚠ UNVERIFIED: half of these keys are probably Samsung-only
>
> Flagged 22 Aug 2026 from a literature review, **not yet tested.** The field
> list below appears to mix two different APIs:
>
> - `android.progress`, `android.progressMax`, `android.progressSegments`,
>   `android.title` are **AOSP**. `EXTRA_PROGRESS_SEGMENTS` is confirmed as the
>   literal string `"android.progressSegments"` in `android.app.Notification`.
> - `android.ongoingActivityNoti.primaryInfo`, `.secondaryInfo`, `.chipIcon`
>   appear to be **Samsung One UI** extras — the One UI 7 "Live Notifications /
>   Now Bar" keys — rather than AOSP. The fullest public key list is
>   [Akexorcist's writeup][ake], which enumerates exactly these and describes
>   them as Samsung-specific.
>
> Everything here was captured on a **Samsung S24+**, so a One UI dependency
> would not have shown up. If it holds, then on a Pixel or any non-Samsung
> Android 16 device **the distance and road-name reads return null** and this
> parser produces nothing usable.
>
> The AOSP-portable equivalents to check are
> `Notification.Builder.setShortCriticalText()` (status-bar chip text, API 36)
> and `ProgressStyle.setProgressTrackerIcon()`, plus plain `android.title` /
> `android.text` / `android.subText`.
>
> **To verify:** run NavDump on any non-Samsung Android 16 phone and dump the
> extras. If confirmed, retitle this document as a *Samsung One UI + Android 16*
> mapping and add an AOSP branch to the parser. Until then, treat portability
> beyond Samsung as unproven.
>
> [ake]: https://akexorcist.dev/live-notifications-and-now-bar-in-samsung-one-ui-7-as-developer-en/

---

## Summary

Google Maps has no public API for live guidance. The usual workaround is to
read its ongoing notification via `NotificationListenerService` — historically a
miserable job, because Maps used custom `RemoteViews` and you had to inflate the
view tree and scrape TextViews.

**That's no longer true on Android 16.** Maps now uses the **ProgressStyle /
Live Updates** notification API, and everything arrives as structured typed
extras. `contentView` never even appears.

Filter on `category == "navigation"`. That single check removes traffic alerts
and Samsung's `Aggregate_NormalNotificationSection` wrapper.

---

## Field mapping

| What you want | Extras key |
|---|---|
| Distance to next maneuver | `android.ongoingActivityNoti.primaryInfo` |
| Instruction text | `android.title` |
| Road being turned onto | `android.ongoingActivityNoti.secondaryInfo` |
| Arrival time | `android.subText` — e.g. `"Arrive 12:08 pm"` |
| Distance travelled, metres | `android.progress` |
| Total route length, metres | `android.progressMax` |
| Maneuver icon | `android.ongoingActivityNoti.chipIcon` |
| Traffic profile ahead | `android.progressSegments` |

`nowbarIcon` and `secondIcon` duplicate `chipIcon`. `largeIcon` is a
higher-detail rendering of the same maneuver. `progressPoints` was empty on
every route observed.

Remaining distance = `progressMax − progress`, in metres.

---

## ★ Maneuver icon hash table

Icons arrive as `type=1` (bitmap), so there's no resource name to read. The
approach that works: render the drawable at 32×32, hash the alpha channel.

**Zero collisions across five rides.** Hashes are stable and repeatable — the
same maneuver produces the same hash on different roads, days apart.

| chipIcon | largeIcon | Maneuver | Rides seen |
|---|---|---|---|
| `c2a2c91` | `578152d3` | CONTINUE / depart | 5 |
| `d0883793` | `434a10a9` | TURN LEFT | 5 |
| `93f8340f` | `cd4ca7c1` | TURN RIGHT | 5 |
| `d5fc816e` | `93650589` | SLIGHT RIGHT | 4 |
| `7df5b514` | `26dfba7b` | SLIGHT LEFT | 1 |
| `39a0a4e2` | `f07041be` | U-TURN | 1 |
| `57dfa08f` | `eea7511` | MERGE / JOIN | 2 |
| `26582277` | `cc2f9709` | ROUNDABOUT — exit 3 | 1 |
| `77f6aaf` | `1c712aea` | ROUNDABOUT — straight through | 1 |
| `23c3f60f` | `7942b5a4` | DESTINATION (flag) | 1 |
| `83534611` | — | Maps logo — non-nav states only | — |

`progressTrackerIcon` resolves to resource `gs_progress`; `smallIcon` in
non-navigating states resolves to `nav_notification_icon`.

**★ Roundabout icons vary by exit.** "Take the 3rd exit" and "continue straight"
produce different hashes. Expect a family of roundabout glyphs and reserve a
code range rather than a single ROUNDABOUT code. The exit number is also present
in `title` as a fallback.

**★ Flyovers are not distinguished.** Rides along NH 44 and NH 75 including
elevated sections produced no flyover-specific icon — Maps renders them as MERGE
or an ordinary turn. If you were hoping for a "TAKE FLYOVER" instruction, it
doesn't exist in this data.

**Not yet captured:** keep-left/right, fork, sharp-left/right, exit/ramp.

The hash depends on your rendering method. Use the code in `android/navdump/` to
generate hashes matching this table, or regenerate your own — the point is that
*some* stable hash exists, not that these specific values are universal.

---

## Distance quantisation

```
> 1 km        100 m steps    3.4, 3.3, 3.2 … 1.0 km
1 km – 300 m   50 m steps    950, 900, 850 … 350, 300
< 300 m        10 m steps    290, 280 … 20, 10, 0
```

Updates arrive at roughly 1 Hz. **Values are rounded to the band, not stepped
through it** — at speed you'll see 290 → 270 → 250 → 230, skipping increments.
Don't assume every value appears.

The 10 m granularity inside 300 m is what makes a close-approach display worth
building.

---

## Parser rules

Every one of these was learned by getting it wrong first.

**1. `title` sometimes carries a distance prefix.**
Far out: `"700 m · Slight right onto Horamavu Agara Main Rd"`.
Under ~50 m: `"Slight right onto Horamavu Agara Main Rd"`.
Strip `^\d+(\.\d+)? (m|km) · ` — you already have the distance from
`primaryInfo`.

**2. `primaryInfo` is not always a distance.** It holds three different kinds of
value:
- a distance — `"350 m"`, `"1.5 km"` — the normal case
- the road name at the moment of the turn — `"TC Palya Main Rd"`
- the maneuver text itself — `"Turn left"`

Validate against `^\d+ m$` or `^\d+\.\d+ km$`; on failure treat it as a
no-distance state rather than displaying the string.

**3. `progressMax` is not constant, and not only on reroutes.** Observed drifting
7486 → 7780 → 7659 → 7486 over 45 seconds of ordinary riding as Maps
continuously re-estimated. Also 851 → 1196 → 804 → 604 within one journey.
Recompute remaining distance on every packet. Never cache it.

**4. `secondaryInfo` sometimes echoes the maneuver.**
When the turn has no named destination it returns `"Turn right"` rather than a
road name. Suppress it when it duplicates the instruction.

**5. `subText` also carries traffic alerts.**
Only trust it as an ETA when it starts with `"Arrive"`.

**6. Routes can be replaced with no rerouting state.** Observed `progressMax`
dropping 11909 → 7448 with `progress` resetting, six seconds apart, and no
`"Rerouting..."` ever appearing. Treat a large `progressMax` change as a route
replacement in its own right.

**7. Instruction strings are long.** Up to 59 characters observed
(`"Slight right at Horamavu Agara Circle onto Horamavu Agara Rd"`). At a
glanceable size on a 320 px display you have room for roughly 16–20. Truncating
from the end destroys the road name, which is the useful part — better to drop
the maneuver prefix, since the arrow already conveys it. Note `title` writes
`Rd/Street` while `secondaryInfo` writes `Rd / Street`.

---

## State detection

| State | Signature |
|---|---|
| Starting | `title == "Starting navigation…"`, `progressMax == 0`, no ProgressStyle template, no `ongoingActivityNoti` keys |
| Navigating | ProgressStyle template present, `chipIcon` non-null |
| Rerouting | `primaryInfo == "Rerouting..."`, `subText == "Arrive "` (truncated), `chipIcon` null |
| Arriving | `title == "Arriving"`, `text == "at <destination>"`, `progressMax == 0`, no template |
| Ended | notification removed — **but see the debounce warning below** |

**★ Rerouting zeroes `progress` but keeps `progressMax`.** A progress bar
computed naively will snap to 0% and back on every reroute — three times in the
first 90 seconds of one ride. Freeze the bar during rerouting instead of
redrawing it.

Reroute recovery measured between **300 ms and 600 ms**. Budget one second.

Arrival to notification-removed measured at **4.7 seconds**.

### ★ Do not treat `onNotificationRemoved` as "navigation ended"

Found in another project's source, not yet reproduced here, but it fits the
mechanism and is cheap to defend against.

**Maps removes and immediately re-posts its notification repeatedly during
active navigation.** A listener that treats removal as the end of the route
will flap — the display drops to the idle screen and back mid-ride, which is
exactly the "never show a stale or wrong state" failure the UI is built to
avoid, arrived at from the opposite direction.

The fix others have landed on is a **debounce of about 15 seconds**: start a
timer on removal, cancel it if a navigation notification reappears, and only
declare the route over when the timer expires. Reference implementation:
`MapsNotificationListenerService.kt` in
[DEMP1993/Drive-assistant-android-app][demp] (`NAV_END_DELAY_MS`).

Note this interacts with the 4.7 s arrival-to-removal figure above: a 15 s
debounce means arrival is confirmed ~15 s after Maps drops the notification.
For an arrival that is fine. Do not reuse the same timer for the stale
watchdog, which needs to fire in 10 s.

[demp]: https://github.com/DEMP1993/Drive-assistant-android-app

---

## progressSegments — a free traffic bar

Segment lengths sum exactly to `progressMax`. Segment `[0]` is grey and its
length **always equals `progress`**, so the array is self-describing: the
travelled portion first, then the traffic profile ahead.

| colorInt | Hex | Meaning |
|---|---|---|
| −9276814 | `0xFF727272` | grey — already travelled |
| −16731905 | `0xFF00B0FF` | blue — normal flow |
| −24576 | `0xFFFFA000` | amber — slow |
| −769226 | `0xFFF44336` | red — heavy |

Each segment is a `Bundle` with `colorInt`, `id`, `length`, `semanticStyle`.
Segment count varies as traffic ahead clears — four segments early in a ride
collapsing to two by the end is normal.

This gives you a live traffic profile of the road ahead in metres, which is
arguably more useful than anything else in the payload.

---

## Two things that do not exist

**No next-maneuver field.** There is nothing anywhere in the payload describing
the maneuver *after* the current one. A "LEFT then RIGHT in 80 m" display is
not possible with Google Maps as the data source.

**Rising distance is not a wrong-way signal.** Tempting idea: if the distance
to the maneuver increases, you're heading away from it, so warn earlier than
Maps does. Tested and rejected — while stationary at a traffic signal the
distance drifted 30 → 40 → 50 m from GPS jitter alone. Such a warning would
fire at every signal. Use the explicit `"Rerouting..."` state instead.

---

## Watchdog design

At 2 km from a maneuver in slow traffic, **64 seconds passed with no change in
any field**. Maps was still posting at ~1 Hz; the content simply didn't change
because the distance was quantised to 100 m steps.

**A stale-data watchdog must count notification arrivals, not value changes.**
With arrival-based counting, 10 s is a safe threshold. With change-based
counting, no threshold works.

Note also that GPS stalls produce frozen values with live packets — distance
stuck at 500 m for ten seconds with `progress` unchanged, then a jump. That's
real and should not trigger the watchdog.

---

## Fragility

This is undocumented internal behaviour. It can change with any Maps update,
and the format differs across Android versions and locales.

Fine for a device you own — if it breaks you spend an evening on the parser.
Not viable as a product: one Maps update would break every unit in the field
simultaneously, and Google restricts notification-listener permission for Play
Store apps in ways that make this exact use case hard to ship.

If you need this commercially, own the routing instead: Mapbox Navigation SDK,
HERE, or self-hosted Valhalla.

---

## Reproducing this

`android/navdump/` contains a diagnostic app that dumps every field, renders
icons as ASCII art, resolves resource names where available, and emits one
compact summary line per update so a whole ride is readable afterwards.

```
adb pull /sdcard/Android/data/com.jiffytrails.navdump/files/navdump.log
```

If permission is denied on Android 11+:

```
adb exec-out run-as com.jiffytrails.navdump cat \
  /sdcard/Android/data/com.jiffytrails.navdump/files/navdump.log > navdump.log
```
