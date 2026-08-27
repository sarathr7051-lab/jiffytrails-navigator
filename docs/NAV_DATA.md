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

**7. Instruction strings are long.** Up to 60 characters observed
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

---

## ★ Unmined fields — test these before writing more parser

Researched 26 Aug 2026 against the Android 16 ProgressStyle docs and the
decompiled One UI key set. None of these have been tested on the actual device;
they are ranked by value-to-effort.

### 1. `android.shortCriticalText` — test this first

`EXTRA_SHORT_CRITICAL_TEXT`, API 36, set via
`Notification.Builder#setShortCriticalText`. It is **Maps' own string, already
shortened by Google to fit a status-bar chip** — the documentation's own
examples are `"3 min"` and `"2.1 mi"`.

Three reasons it is the highest-value read in the payload:

- It is exactly the format a handlebar display wants, which is the answer to
  parser rule 7 (60-char instructions against 16–20 characters of room).
- It is **AOSP, not Samsung** — so if Maps populates it, it may resolve the
  portability warning at the top of this document.
- It costs one `getString`.

### 2. `android.when` + `showChronometer` + `chronometerCountDown`

The live-update spec names these as the way to put a countdown in the chip. If
Maps sets `when` to the arrival timestamp, that is **ETA as epoch millis** —
locale-proof, and it replaces regex-parsing `"Arrive 12:08 pm"` entirely.

### 3. Samsung Now Bar keys not in the table above

`.nowbarPrimaryInfo` and `.nowbarSecondaryInfo` are **separate** from
`.primaryInfo` / `.secondaryInfo`. If populated they are pre-shortened for a
smaller surface — same value as `shortCriticalText`. Also worth one line of
logging each: `.chipExpandedText`, `.chipBgColor` (may encode severity),
`.secondaryInfoIcon`.

### 4. `Notification.FLAG_PROMOTED_ONGOING`

A cleaner "this is a live nav update" test than string-sniffing. Complements
the removal debounce rather than replacing it.

### 5. `notification.actions[]`

Not display data — each is a live `PendingIntent` the service can fire. A
handlebar button could mute voice guidance. **Genuinely dangerous:** action
indices are locale-dependent and misfiring "Exit navigation" mid-ride is the
worst available failure. Match on action title, and require a long press.

---

## ★ Correction: "two things that do not exist" is wrong about the protocol

The section above says there is no next-maneuver field and no lane data. That
is true **of the notification**. It is not true of Android Auto.

Reverse-engineered Maps/AA protobufs (`mrmees/open-android-auto`) show message
`0x8006 NavigationNotification` carrying:

```
NavigationStep { NavigationManeuver maneuver; NavigationText instruction;
                 repeated NavigationLane lanes; NavigationRoadInfo road_info; }
NavigationManeuver { ManeuverType type; int32 roundabout_exit_number;
                     int32 roundabout_turn_angle; }
NavigationLaneDirection { LaneShape shape; bool is_recommended; }
```

`steps` is **repeated** — the next maneuver is in there. `ManeuverType` is a
50-value enum that would **replace the entire icon-hash table with an integer**,
including the keep-left / fork / sharp / ramp cases listed as "not yet
captured", and gives roundabout exit as a structured int rather than scraped
from `title`. `0x8007` adds time-to-next-maneuver, which the notification does
not have.

**Why it is still not the answer.** The phone runs a head-unit server on
**TCP 5277** — the port `adb forward` targets for the Desktop Head Unit — so an
on-device app connecting to `127.0.0.1:5277` is architecturally plausible.
But **that server must be started by hand from Android Auto's developer-mode
overflow menu every session**, which is fatal for a helmet-on-and-ride
workflow. The practical version needs a Pi-class board doing USB-accessory AA.

Filed as: the only honest source for lane guidance and next-maneuver, at
roughly 50× the effort of everything else here. Worth knowing before investing
further in the icon-hash table.

---

## What to stop extracting

A reviewer pushed back on three things in this document. Two of the arguments
are good.

**Drop the `largeIcon` hash column.** It is a second hash of the same maneuver
`chipIcon` already identifies — two tables, one bit of information, double the
maintenance every time Maps changes its glyphs.

**`progressSegments` is beautiful and wrong for this device.** It is the most
expensive thing in the payload to parse (Bundle array, colour-int lookup,
segment counts that change underneath you), it renders as a multi-colour bar
that cannot be read in under a second, and — the decisive point — **a rider
cannot act on it.** You cannot reroute from a handlebar, and on a motorcycle
you filter through the red section anyway. If anything survives, reduce the
whole array to one boolean: heavy traffic within 2 km, yes or no.

This retroactively justifies the traffic bar being absent from the shipped
display. It was dropped because `NavState` had no field for it; it should stay
dropped on merit.

**The route progress bar costs three defensive mechanisms** — drift (rule 3),
reroute reset, and silent route replacement (rule 6) — to render "you are 40%
there". ETA says the same thing in one field with none of the defence. Keep
reading `progressMax` for route-replacement detection; stop drawing the bar.

**Not accepted:** the same reviewer ranked GPS speed as the top addition.
Rejected — the Speed 400 has a speedometer six inches away. See FEATURES.md.

---

## Probe results — measured on the S24+, 27 Aug 2026

The "unmined fields" section above was speculation. These are the real values,
logged from a live route on Moulana Azad Rd.

```
PROBE shortCriticalText=<null>  showChronometer=false countDown=false
      when=0min from now
      nowbarPrimary=0 m
      nowbarSecondary=towards Moulana Azad Rd
      flags=0x4016a
```

### Two hopes killed

**`android.shortCriticalText` is null.** It was ranked the highest-value
unmined field — Google's own pre-shortened string, AOSP rather than Samsung, one
`getString`. Maps does not populate it. It would also have been the fix for the
portability warning at the top of this document, so **that warning stands**.

**No chronometer ETA.** `showChronometer` and `chronometerCountDown` are both
false and `when` is unset, so there is no epoch-millis arrival time. ETA must
keep coming from the `"Arrive ..."` regex on `subText`, with all the locale
fragility that implies.

### One real find

**`nowbarSecondaryInfo` carries a pre-shortened road name**, phrased as
`"towards Moulana Azad Rd"`. `nowbarPrimaryInfo` carries the distance in the
same compact form.

That is directly useful. Parser rule 7 exists because instructions reach 60
characters against roughly 16–20 of legible room; this field is already short
because Samsung sized it for the Now Bar. **Prefer it over truncating
`android.title`.**

Caveat: it is a Samsung One UI key, so using it deepens rather than reduces the
One UI dependency. Worth it — a truncated road name is barely better than none.

### Confirmed present

`flags=0x4016a` includes **`FLAG_PROMOTED_ONGOING`**, verified independently in
a `dumpsys notification` capture alongside `category=navigation`. So the
Android 16 Live Updates path is definitely what this phone is on, and that flag
is a cleaner "this is a live nav update" test than sniffing content.

---

## Complete extras dump — 27 Aug 2026, and the next-maneuver question closed

Captured live from `dumpsys notification --noredact` on the S24+ during a route,
at a moment when Maps was rendering **"Then →"** in its own UI. Every extra:

```
android.title                = "Head toward Moulana Azad Rd"
android.text                 = null
android.subText              = "Arrive 3:40 pm"
android.shortCriticalText    = ""            (set, but empty)
android.progress             = 0
android.progressMax          = 12729
android.progressPoints       = []
android.progressSegments     = [{length=12729, colorInt=-16731905, id=0}]
android.progressTrackerIcon  = RESOURCE gs_progress
android.largeIcon            = BITMAP 101x101
android.template             = Notification$ProgressStyle
android.showChronometer      = false
android.showWhen             = false
android.requestPromotedOngoing = true
android.reduced.images       = true
android.styledByProgress     = false
android.infoText             = null
android.remoteInputHistory   = null

android.ongoingActivityNoti.primaryInfo        = "0 m"
android.ongoingActivityNoti.secondaryInfo      = "towards Moulana Azad Rd"
android.ongoingActivityNoti.nowbarPrimaryInfo  = "0 m"
android.ongoingActivityNoti.nowbarSecondaryInfo= "towards Moulana Azad Rd"
android.ongoingActivityNoti.chipExpandedText   = "0 m"
android.ongoingActivityNoti.chipIcon           = BITMAP 135x135
android.ongoingActivityNoti.nowbarIcon         = BITMAP 135x135
android.ongoingActivityNoti.secondIcon         = BITMAP 135x135
android.ongoingActivityNoti.chipBgColor        = -16777216
android.ongoingActivityNoti.style              = 1
android.ongoingActivityNoti.actionType         = 1
```

### The next maneuver is not there. Tested, not assumed.

Every text field says the same thing. And the three 135×135 bitmaps were
classified against each other while "Then →" was on screen:

```
PROBE-ICONS chip=CONTINUE second=CONTINUE nowbar=CONTINUE (all same)
```

**`secondIcon` is a duplicate**, despite the name — the assumption in the field
table above is correct. Maps computes the next maneuver and renders it in its own
UI without publishing it anywhere a listener can reach.

This closes the question properly. "Two things that do not exist" was inferred
from ride logs; it is now verified against a complete dump at the exact moment
the data would have had to be present.

The only source that carries a next maneuver remains the Android Auto protocol
(`repeated NavigationStep`), and its practical cost is unchanged — see the
correction section above.

### Also confirmed here

- **`shortCriticalText` is an empty string, not absent.** Maps sets the field and
  leaves it blank, so it is a deliberate non-use rather than an oversight.
- **`progressSegments` had one segment** covering the whole route on this trip —
  no traffic detail to read even if we wanted it.
- **`requestPromotedOngoing = true`** alongside `FLAG_PROMOTED_ONGOING` in flags.

### Operational note: reinstalling the app silently breaks the listener

After every `installDebug` the listener stays *listed* in
`enabled_notification_listeners` and in `dumpsys notification`, but delivers
nothing. It looks bound and is not. Toggle it, or from a shell:

```
adb shell cmd notification disallow_listener com.jiffytrails.navlink/com.jiffytrails.navlink.NavListenerService
adb shell cmd notification allow_listener    com.jiffytrails.navlink/com.jiffytrails.navlink.NavListenerService
```

This wasted a debugging round: the symptom is a display frozen on old data with
a healthy-looking link, which is indistinguishable from a firmware fault.

---

## Can Maps be made to publish more? (27 Aug 2026)

A four-thread sweep of every plausible route: Maps settings, disabling Live
Updates, One UI features, Android listener APIs, other Maps surfaces,
AccessibilityService, audio capture, Shizuku, root, and alternative nav apps.

**The current dump is the ceiling for the notification channel**, and it is a
*higher* ceiling than the pre-ProgressStyle notification ever was.

### The downgrade hypothesis was wrong - do not disable Live Updates

Gadgetbridge's docs tell users to turn Live Updates off, which reads like
evidence that the older notification carried more. It does not. Checked against
two independent parsers - Gadgetbridge's `GoogleMapsNotificationHandler` and
`3v1n0/GMapsParser` - the old format's *complete* field set was:

    distance-to-turn, one instruction string, remaining duration,
    remaining distance (rounded), ETA, one maneuver bitmap, rerouting flag

No second maneuver. No lanes. No maneuver enum. No road-name field.

Gadgetbridge's advice is not "the new format is poorer"; it is "our parser has
not been updated for it". Their maintainers could not reproduce it off a Pixel
and closed the issue with a docs change. We have already done what they haven't.

Downgrading would *lose* us `progressSegments` and metre-resolution remaining
distance, and reintroduce version-fragile `RemoteViews` scraping. Also
structurally: a promoted Live Update **may not carry a custom content view at
all**, so there is provably nothing for RemoteViews reflection to find here.

### Old vs new

| Datum | Old | New (ours) |
|---|---|---|
| Remaining distance | `subText`, rounded "5.2 km" | `progressMax - progress`, **metres** |
| Traffic ahead | - | **`progressSegments`** |
| Remaining duration | `subText` "12 min" | derived from ETA - now |
| Everything else | equivalent | equivalent |

### The one datum still on the table: `progressSegments`

Google's guidance is that segments "colorize a state and duration of traffic",
and that segment colours change as traffic does. Our capture had **one blue
segment** (`0xFF00B0FF`, Material Light Blue A400 - Maps' no-traffic colour)
because the route was clear.

**On a congested route this should return an ordered list of `{length,
colorInt}` - a distance-indexed traffic profile of the road ahead.** That is
real structured data we are currently discarding. Re-dump during rush hour.

Unverified but strongly implied: `getProgressMax()` is documented as "the sum of
the lengths of all Segments", so 12729 is summed segment length, i.e. metres of
route. Consistent with what we already compute.

### Confirmed dead, with reasons

- **Every Maps setting.** The full Navigation settings set touches voice,
  buildings, media controls, incident alerts and the speedometer. None affect
  notification payload. The speed limit is never published anywhere reachable -
  not even in the Android Auto schema. Source it from OSM `maxspeed` if wanted.
- **Every One UI feature.** Now Bar, AOD, Edge panels, DeX, Bixby Routines, Now
  Brief are all render-side; redaction never affects a bound listener.
  Structurally decisive: **the Now Bar renders from the same notification we
  read.** If Samsung could show "Then, right", it would be in our bundle.
- **Every listener API.** `Ranking`, `getSnoozedNotifications`,
  `requestListenerHints`, `setNotificationsShown`, shortcut/LocusId lookups, and
  the Android 16 promoted-notification APIs. Notification content is 100%
  author-controlled; the platform never enriches it and no consumer can ask the
  poster for more. There is no "give me the rich version" call.
- **Wear OS.** The Data Layer enforces matching package name *and signature*; a
  local app cannot observe Maps' traffic. It is not richer anyway - Google's own
  docs say lane guidance may not appear on the watch.
- **Voice-guidance capture + STT.** The spoken phrase does contain the "then",
  but `AudioPlaybackCapture` can only capture `USAGE_MEDIA`, `USAGE_GAME` and
  `USAGE_UNKNOWN`. Navigation uses `USAGE_ASSISTANCE_NAVIGATION_GUIDANCE`, which
  is not capturable. Closed.
- **Widgets, PiP, Maps Go, share-trip, broadcasts, content providers.** No
  outbound API. Gadgetbridge's maintainers state it flatly: the Maps app
  provides no API on Android.
- **Assistant Driving Mode.** Removed April 2025. Nothing to hook.

### AccessibilityService - fails on the use case, not the technology

It would work: `canRetrieveWindowContent` reads other apps' node trees, and
`FLAG_SECURE` does not block it. Whether Maps exposes the "Then" card, lane
strip and speed badge as individual nodes is **unknown** - and notably, *no one
has ever published a dump of the Maps navigation node tree, and not one
open-source project scrapes Maps navigation this way.* Everyone uses the
notification or OCR. That absence is itself a finding.

**The disqualifier:** a service can only read the *currently active window*.
Screen off or Maps backgrounded means no tree and no event stream. Maps has no
PiP nav mode to fall back on. This is exactly why every prior project uses the
notification - it survives screen-off because a foreground service posts it.

Additional live threats: Android 13+ Restricted Settings (and reports that One
UI 8.5 offers no "Allow restricted settings" item at all); Android 14+
`accessibilityDataSensitive`, a one-line change Maps could ship that would
silently kill this; Android 17 blocking it outright under Advanced Protection.

Worth a 30-minute experiment to convert the unknowns into facts. Not worth
building on, and never as the sole source.

### Where the data actually lives: Android Auto

The AA protobuf schema is the only place Google publishes what we want:

    NavigationStep  { maneuver; road; repeated NavigationLane lanes; cue }
    NavigationState { repeated NavigationStep steps; ... }

`steps` is **repeated** - that is the next maneuver. `lanes[].lane_directions`
is lane guidance. `road.name` is the road name. And the phone can talk AA to
itself: AA ships a head unit server, and self-mode head units exist.

The cost is the problem. `aasdk` ships **no** navigation-status handler; the
request for one is open and unanswered. The work is forking a head unit,
advertising `NavigationStatusService`, implementing the cluster messages, and
bridging to BLE - while running the whole projection stack including an H.264
video sink we do not want, on a phone, on a motorcycle, in the sun. Plus TLS
certificates extracted from the AA APK, which Google rotates.

**Weeks of work, terms-violating, breaks on every AA update. Not proceeding.**

### If we ever abandon Maps: fork OsmAnd

Best effort-to-reward trade by a wide margin. Its AIDL `ADirectionInfo` today
carries only `distanceTo`, `turnType`, `isLeftSide` - the request to widen it is
open and unimplemented. **But OsmAnd computes everything internally**: it ships
"Second next turn", "Lanes" and speed-limit widgets. Widening the AIDL in a fork
is a small change to a GPLv3 codebase, and Gadgetbridge's existing OsmAnd
integration is a working reference for the consumer side.

Also viable: MapLibre Navigation Android (secondary instructions and lanes by
construction). Sygic's Fleet SDK has the richest documented broadcast anywhere -
`DirCommandSecondary`, `NextStreet`, `SpeedLimit`, `LaneData[n]` - but is gated
behind a sales agreement. Not a hobbyist path.

### Regional note

Lane guidance launched in the US/Canada and 15+ European countries; **no
confirmation it exists in India at all.** For our region the lane question may
be moot regardless of channel - which is consistent with the 0.52% OSM
`turn:lanes` coverage that closed the feature in FEATURES.md.

India does have two-wheeler mode with landmark-based guidance. Worth comparing
the notification in driving vs two-wheeler mode; landmarks may surface in
`secondaryInfo`.

### Untested, cheap, worth trying

- **Settings > Navigation > Glanceable directions** (off by default). Described
  as putting turn-by-turn on the lock screen "using regular system
  notifications", including before you tap Start. Probably changes *when* the
  notification is posted rather than what it contains, but it is one tap.
- **Iterate the whole Samsung bundle** rather than probing known keys. A
  decompiled key list (kirillshsh/nowbar-sdk) names `style`, `firstIcon`,
  `secondaryInfoIcon`, per-segment colour keys and more that we never dumped.
  None carries a maneuver, second step or lanes - it is more of the same kind of
  data - but enumeration is free.
- **Re-dump after any major Maps or OS update.** Android 17 adds
  `Notification.MetricStyle` (up to three label/value/unit metrics). If Maps
  adopts it, that is three more structured numeric fields.
