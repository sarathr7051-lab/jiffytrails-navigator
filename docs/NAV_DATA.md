# Google Maps navigation data on Android 16

Reverse-engineered from real rides, August 2026.
Samsung S24+, Android 16 / One UI, Google Maps current release.

**If you're building anything that needs live turn-by-turn data from Google
Maps on Android, this is the document to read.**

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
| Arrival time | `android.subText` — e.g. `"Arrive 8:07 pm"` |
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

**Zero collisions across two rides and eight different roads.** Hashes are
stable and repeatable — the same maneuver type produces the same hash on
different roads, hours apart.

| chipIcon | largeIcon | Maneuver | Confirmations |
|---|---|---|---|
| `c2a2c91` | `578152d3` | CONTINUE / depart | 6 |
| `d0883793` | `434a10a9` | TURN LEFT | 9 |
| `93f8340f` | `cd4ca7c1` | TURN RIGHT | 7 |
| `d5fc816e` | `93650589` | SLIGHT RIGHT | 5 |
| `26582277` | `cc2f9709` | ROUNDABOUT | 1 |
| `23c3f60f` | `7942b5a4` | DESTINATION (flag) | 1 |
| `83534611` | — | Maps logo — non-nav states only | — |

`progressTrackerIcon` resolves to resource `gs_progress`; `smallIcon` in
non-navigating states resolves to `nav_notification_icon`.

**Not yet captured:** U-turn, flyover, merge, keep-left/right, fork,
sharp-left/right, exit/ramp.

**Roundabout exit number is not encoded in the icon** — parse it from `title`
(`"At the roundabout, take the 3rd exit onto North Ave"`).

The hash depends on your rendering method. Use the code in
`android/navdump/` to generate hashes matching this table, or regenerate your
own — the point is that *some* stable hash exists, not that these specific
values are universal.

---

## Distance quantisation

```
> 1 km        100 m steps    3.4, 3.3, 3.2 … 1.0 km
1 km – 300 m   50 m steps    950, 900, 850 … 350, 300
< 300 m        10 m steps    290, 280 … 20, 10, 0
```

Updates arrive at roughly 1 Hz. The 10 m granularity inside 300 m is what makes
a close-approach display worth building.

---

## Parser rules

Every one of these was learned by getting it wrong first.

**1. `title` sometimes carries a distance prefix.**
Far out: `"700 m · Slight right onto Horamavu Agara Main Rd"`.
Under ~50 m: `"Slight right onto Horamavu Agara Main Rd"`.
Strip `^\d+(\.\d+)? (m|km) · ` — you already have the distance from
`primaryInfo`.

**2. `primaryInfo` is not always a distance.**
At the moment of the turn it holds the road name instead. Validate against
`^\d+ m$` or `^\d+\.\d+ km$`; on failure, treat it as a no-distance state
rather than displaying the string.

**3. `progressMax` is not constant.**
Observed shifting 851 → 1196 → 804 → 604 within a single journey as the route
was re-estimated and rerouted. Recompute remaining distance on every packet.
Never cache it.

**4. `secondaryInfo` sometimes echoes the maneuver.**
When the turn has no named destination it returns `"Turn right"` rather than a
road name. Suppress it when it duplicates the instruction.

**5. `subText` also carries traffic alerts.**
Only trust it as an ETA when it starts with `"Arrive"`.

---

## State detection

| State | Signature |
|---|---|
| Rerouting | `primaryInfo == "Rerouting..."`, `subText == "Arrive "` (truncated), no chipIcon |
| Arriving | `title == "Arriving"`, `progressMax == 0`, no ProgressStyle template |
| Ended | notification removed |

Reroute recovery measured at **300 ms** from the rerouting state to a fresh
route with a new `progressMax`.

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
