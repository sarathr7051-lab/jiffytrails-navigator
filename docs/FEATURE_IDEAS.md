# Feature study — what else would make this meaningfully better

Researched 27 Aug 2026. Scope: everything *except* road geometry, which
`ARCH_ANDROID_AUTO.md` has just settled. This document asks what pairs well with
that decision, and what earns a place on a screen with room for one dominant
element, two fixed secondaries, and one exception band that is already occupied.

Nothing rejected in `FEATURES.md` is re-proposed. Where something adjacent comes
up — speed, traffic, battery percentage — it is listed under **Rejected** with
the number that kills it, so it is killed twice rather than reopened.

---

## The two structural findings

Everything below follows from these. They matter more than any individual
feature.

### 1. The exception slot already has an owner

The design has exactly one element that costs nothing while blank: the bottom
band, y=190–240, arbitrated by `bandFor()`. It currently holds calls and
messages. **Every new "warn me when X" idea is therefore not competing for empty
space — it is competing with the call alert**, and the precedence table has to be
extended rather than the layout.

Proposed precedence, highest first, all still suppressed below 100 m:

| Rank | State | Why it outranks the next |
|---|---|---|
| 0 | **NO NAV DATA** (parse failure) | takes the *dominant* slot, not the band — it invalidates the arrow |
| 1 | **RAIN AHEAD** | changes what the rider does in the next ten minutes |
| 2 | CALL ringing | not actionable on a bike, but socially time-critical |
| 3 | Message / notification | self-dismissing, lowest stakes |

### 2. Off-navigation is the unclaimed 80%, and it is free

The device is powered whenever the bike is on. A rider who navigates for 20% of
their saddle time — generous, in a city they know — spends **four fifths of
screen-on time on the idle screen**, which today shows a clock and trip stats.

Anything that lives *only* there satisfies constraint 2 by construction: it
cannot compromise the navigation screens because it is not on them. **This is
the cheapest square metre of real estate in the whole design, and almost nothing
is on it.**

It also produces the single best pairing argument for the vector window that
`ARCH_ANDROID_AUTO.md` recommends: **that feature does not need a route.** It
queries a local OSM extract around the rider's own GPS fix. With no route
active, the same code, the same tiles and the same `0x09 GEOM` packet draw a
heading-up sketch of the roads around you. The route line is simply absent. One
build, two features, and the second one is the answer to "what does this thing do
for the other 80% of the time".

---

## Ranked summary

### Build now

| # | Feature | Effort | One-line reason |
|---|---|---|---|
| 1 | **Backlight low-side switch, before perfboard** | ₹5, 2 h | Not a feature — an unbuilt prerequisite that `BUILD_PLAN.md` Stage 9 already depends on. Its deadline is Stage 11, and it is a rebuild after that. |
| 2 | **Parse-failure state** | ~20 lines | Closes the one failure mode that looks healthy and is not: listener dead, link green, display quietly idle, rider misses the turn. |
| 3 | **One physical button** | ₹200, ~8 h | Converts a fixed two-secondary budget into an unlimited on-demand page budget. Every idea below that "isn't worth permanent space" becomes affordable. |
| 4 | **Silent ride log** (GPX + packet telemetry) | ~6 h Android | Zero display cost. It is the instrument that decides every later feature, in a project that decides on evidence. |
| 5 | **Reroute hold ≤1 s** | ~1 h | Measured reroute recovery is 300–600 ms; blanking the arrow three times in 90 s is worse than holding it for one second. |

### Build later

| # | Feature | Effort | One-line reason |
|---|---|---|---|
| 6 | **Rain ahead, from radar** | ~20 h Android | The real Bengaluru hazard, exception-only, free — *but verify Bengaluru radar coverage first; it may not exist.* |
| 7 | **Idle-screen local map** | ~0 h extra | Falls out of the vector window for free; fills the unclaimed 80%. |
| 8 | **Notification whitelist** | ~4 h Android | The group-riding feature actually worth building: let one WhatsApp thread through, mute the rest. Improves the band by making it quieter. |
| 9 | **Ride-end summary card** | ~3 h | Turns every ride into a measurement without costing a single riding-second. |
| 10 | **Fuel as a button page** | ~4 h | Rides free on the OSM extract. Worthless in the city (nearest pump ≈ 0.9 km), real on a highway run. |
| 11 | ~~OTA over BLE~~ — **already covered** | 0 h | `BUILD_PLAN.md` Stage 10 does this over WiFi and gates on it. Listed only to close it: do not build a second transport. |
| 12 | **Arrival hold, 60 s** | ~2 h | Cheap. Does not solve last-mile — nothing here can, because Maps never publishes the destination. |

### Rejected

| Feature | The number or fact that kills it |
|---|---|
| Speed-limit / over-speed warning | **2,231 of 9,398** arterial ways carry `maxspeed` = **23.7%**. Silent three times in four; a wrong limit is worse than none. |
| Speed-camera alerts | **37** mapped `highway=speed_camera` nodes across the whole metro bbox. Silence indistinguishable from safe. |
| Rain *timing* ("rain in 12 min") | RainViewer's free tier is **past radar only — no nowcast**. Self-extrapolation is optical flow on 13 frames, and it will be wrong. |
| Open-Meteo `minutely_15` as a nowcast | Outside North America and Central Europe it is **interpolated from hourly**. Verified in their own docs. Not a nowcast at all. |
| Group riding by position sharing | Needs N riders running a debug-signed personal app plus a server. The device has not completed one ride solo. |
| Fuel *warning* / range tracking | The bike measures actual level, warns at ~3 L, and prints range-to-empty. We would be estimating from trip distance. Strictly worse. |
| Persistent trip stats during navigation | Displaces the arrow or the distance for something no rider acts on mid-turn. |
| Traffic bar, any form | Already killed twice (`NAV_DATA.md`, `FEATURES.md`). A rider cannot reroute from a handlebar and filters through the red anyway. Agreed; stays dead. |
| Ambient temperature, AQI, altitude, compass-to-home | You feel the first two, the third is a toy, and the fourth is a toy 95% of the time in a city you know. |
| Bike telemetry (fuel level, gear, revs) | No accessible bus. Speed 400 diagnostics are proprietary, and this violates "no sensors on the device". |

---

# The ideas, in full

## 1. Backlight low-side switch — an unbuilt prerequisite with a hard deadline

**Not a new idea. `BUILD_PLAN.md` Stage 9 already plans auto-dim, and
`BLE_PROTOCOL.md` already specifies "dim screen, STALE". Neither can execute,
because `LED` is tied straight to `3V`.** It is on this list because it is the
only thing here that other planned work is blocked on, and because its deadline
is a soldering iron rather than a decision.

**What.** N-channel logic-level MOSFET (AO3400, ₹5) between the backlight cathode
and ground, gate on GPIO 17 — which `User_Setup.h` already reserves as `TFT_BL`,
commented out.

**Cost.** One part, two solder joints, ~2 h including the ramp curve. Zero BLE,
zero screen, zero glance.

**Why the direct-drive shortcut is not available.** The backlight is 60–100 mA;
an ESP32 pin is 40 mA absolute maximum and ~12 mA comfortable. Moving the wire to
GPIO 17 is somewhere between unreliable and destructive.

**What it unblocks that is not already in the plan — night luminance.** Stage 9
frames auto-dim around tunnels and streetlight strobing. The larger case is
unlit road: the device switches day/night *polarity* but not *luminance*, and a
250 cd/m² white field subtending roughly 4.7° × 3.5° at 700 mm is a glare source
pointed at a dark-adapted eye. Polarity inversion shrinks the lit area; it does
nothing to the peak.

`PRIOR_ART.md` records that reviewers credit Beeline's sunlight readability to
"anti-glare coating and auto-backlight — not raw brightness". This is one of the
two levers named by the closest commercial analogue, and the project has neither.

### ★ One warning about the Stage 9 LDR that is worth more than the part costs

**Mount the sensor where it sees the sky, not inside the hood.** `HARDWARE.md`
calls for a 25–35 mm matte-black ribbed hood, which is the largest single
readability gain available — and a hood is, by construction, a device for making
the area in front of the panel dark. An LDR sitting in that shadow reads "dim" at
noon and **turns the backlight down in direct sunlight**, which is the precise
inverse of what is wanted and would look exactly like a panel failure.

Put the LDR on the outside top face, and clamp the auto-dim curve so it can never
command less than full brightness while the day/night state says day.

**The deadline is physical.** `HARDWARE.md` already says decide before soldering
to perfboard; Stage 11 seals the case. After that, adding a gate driver is not a
retrofit, it is a rebuild.

---

## 2. Parse-failure state — the trust feature

**What.** The Android app currently produces NAV packets when it can parse the
Maps notification. Add the inverse assertion: **if a notification with
`category == "navigation"` and `FLAG_PROMOTED_ONGOING` exists, but no NAV packet
has been emitted for 10 s, send an explicit failure state.** The ESP32 shows
`NO NAV DATA` in the *dominant* slot — not the band.

**Cost.** One NAV flag bit (bit 4, `parse_fail`), ~20 lines of Kotlin, one
firmware screen. No new packet type. No screen space, because it displaces an
arrow that is already wrong.

**Why it earns its place.** `NAV_DATA.md` documents this exact failure, having
lost a debugging session to it:

> "the symptom is a display frozen on old data with a healthy-looking link,
> which is indistinguishable from a firmware fault."

The 10 s watchdog defends the *transport*. It does not defend the *parser*. If
the listener dies, or Maps changes its keys — which `NAV_DATA.md` says happens
roughly annually — the phone keeps sending STATUS, the link stays green, the
display drops to the idle clock, and **everything looks correct.** The rider
learns something is wrong by missing a junction.

This is the difference between a device that fails loudly and one that fails
silently, and it is the single cheapest thing on this list. What makes a rider
stop trusting a display is not that it broke; it is that it broke and looked
fine.

**Related, and nearly free:** `BUILD_PLAN.md` Stage 10 already puts a version
string on a boot screen. Add two things to it while it is being written — a
~200 ms full-white then full-black flash (a panel self-test that also reveals
dead pixels and solar-clearing spots, which `HARDWARE.md` warns are a real
failure mode for this panel in sun) and the initial link state. ~1.5 s at
power-on, zero cost while riding.

---

## 3. One physical button — yes, and one is strictly better than two

**Short answer to the brief's question: yes, disproportionately, and the reason
is not the actions it triggers. It is that it changes the shape of the glance
budget.**

Today every candidate feature must beat something already on screen, permanently.
That is a brutal test and it is correct — but it means the answer to "is trip
distance worth showing?" is *no*, forever, because it is worth less than the
things already there *all the time*.

**A button converts a fixed two-secondary budget into an on-demand N-page
budget.** Trip stats, fuel, rain detail, link diagnostics, group gap — each costs
zero pixels and zero glances until the rider decides it is worth one. The
question changes from "is this worth displacing the ETA?" to "is this worth a
deliberate press?", which several ideas pass and none of them passed before.

### The mapping

| Gesture | Navigating | Idle |
|---|---|---|
| Short press | cycle the **secondary band** through pages: ETA → trip → rain → link | cycle the **whole screen**: clock → trip → rain → local map → diagnostics |
| Long press (>1 s) | mark waypoint (phone logs GPS + timestamp) | reset trip |
| Any press below 100 m to a maneuver | **ignored, silently** | — |

That last row is constraint 2, enforced in one place, the same way `bandFor()`
and `screenFor()` already work. A page opened by a press must also **time out
back to the default after ~8 s** — otherwise a forgotten press leaves the wrong
thing on screen at the next junction, which is exactly the failure the whole
design avoids.

### Why exactly one, not two

Two buttons is worse, and this is the non-obvious part. Under gloves, without
looking, the rider must first identify *which* button — a discrimination task
that either costs a glance or produces a mis-press. One button is one location
and one motion; short versus long is a *duration*, which needs no precision and
no proprioception. The rider's hand does not leave the grip zone and their eyes
do not leave the road.

Two buttons only start to win when there is a genuine two-axis task
(next/previous, up/down). There isn't one here. A single cyclic list of three or
four pages is navigable forward-only.

**If a second control is ever added, make it a different *kind*** — a
bar-end paddle, or a switch under the left thumb — so it is distinguishable by
position and feel rather than by counting.

### The hardware is the hard part

Firmware is trivial: internal pull-up, 100 nF to ground, 50 ms software debounce.
The real problem is that a switch on the *enclosure* requires taking a hand off
the bar to reach the display, which defeats the purpose.

The right answer is a **momentary switch in a 22 mm handlebar clamp**, two-core
cable into the existing gland alongside the power feed, mounted for the left
thumb. ~₹200. It must be operable with a winter/monsoon glove: that means a
raised, domed actuator with ≥8 N of travel feedback, not a flush tactile dome.

Do not use a BLE remote. The ESP32 would need to run a central role alongside the
peripheral role, and `FEATURES.md` has already recorded that radio coexistence on
plain ESP32 costs real RAM. Two wires cost nothing.

---

## 4. Silent ride log

**What.** The Android app writes a per-ride record: GPX track at 1 Hz, plus a
parallel event log of every packet sent, every parse failure, every BLE
disconnect, every stale window, and the round-trip latency of the link.

**Cost.** ~6 h Kotlin. **Zero display, zero BLE, zero glance.** It needs
`ACCESS_FINE_LOCATION`, which the vector window in `ARCH_ANDROID_AUTO.md`
already requires — so if that feature is built, this one is free of its only
real cost. Storage: a 30-minute ride at 1 Hz is ~1,800 points ≈ 90 kB GPX.

**Why it earns its place.** This project's method is to kill features on
measurements. It currently has no instrument. Every question the next study will
ask — *does the arrow suffice at messy junctions? how often does the link drop?
how many junctions are actually flyovers we drew flat? is 100 m the right alert
suppression radius?* — is answerable from a log and unanswerable without one.

`ARCH_ANDROID_AUTO.md` explicitly defers its own decision pending "5–10 real
rides". Those rides are worth ten times more with a log than without.

**What to show on screen: almost nothing.** `BUILD_PLAN.md` Stage 9 already puts
trip stats on the idle screen, which is the right place — it is the unclaimed
80% and costs the navigation screens nothing. Add a button page for the same
numbers so they are reachable mid-ride without displacing anything, and stop
there. Live trip stats *during* navigation would displace the arrow or the
distance for a number no rider acts on mid-turn.

**Note the log is not the TRIP packet.** `0x05 TRIP` is four numbers for
display. This is a file on the phone that the display never sees, and the two
should not be conflated — the display wants three digits, the log wants
everything.

---

## 5. Reroute hold, ≤1 s

**What.** `BLE_PROTOCOL.md` says rerouting suppresses the arrow. Instead: hold
the last arrow at reduced emphasis (outline rather than fill) with the distance
replaced by `—`, for up to **1 second**. If rerouting persists past that, blank
and show `REROUTING` as specified today.

**Cost.** ~1 h firmware. One timer.

**Why it earns its place, numerically.** `NAV_DATA.md` measured reroute recovery
at **300–600 ms**, and observed **three reroutes in the first 90 seconds of one
ride**. Under the current rule, that is three full blank-and-restore cycles in a
minute and a half. A display that flickers between states is a display the rider
stops trusting — and the doc already names that failure ("the display drops to
the idle screen and back mid-ride") when arguing for the removal debounce. This
is the same argument applied to the same symptom from the other direction.

**The honest counter-argument**, recorded because it is real: a reroute sometimes
means the turn was missed, in which case the held arrow is *wrong* for up to a
second. The mitigation is why the distance goes to `—` and the fill goes to
outline: the display stops asserting a distance it no longer knows, which is the
part that would actually mislead. The arrow shape is the part the rider has
already read.

Judgement call, flagged as such. Worth trying and worth reverting if a ride shows
it feels wrong.

---

## 6. Rain ahead — the best idea here, gated on one unverified fact

**What.** The phone samples weather-radar imagery along the rider's direction of
travel and reports the distance to the nearest significant echo. The display
shows an exception band: `RAIN 8 km`. Blank when dry, which is most of the time.

**Why rain and not "weather".** Temperature, humidity, AQI and the day's forecast
are things the rider already knows or cannot act on. A rain cell 8 km ahead is a
decision: pull over now and put the jacket on while dry, take the flyover instead
of the underpass that floods, or accept it. That decision must be made *minutes*
before the rain, from inside a helmet, without being able to see behind or above.
This is the one weather datum that is both unknowable to the rider and
actionable by them.

### What the free APIs actually give — measured, not assumed

**Open-Meteo cannot do this, and this is the finding that reshapes the feature.**
Their documentation states that 15-minutely data is "based on NOAA HRRR model for
North America and DWD ICON-D2 and Météo-France AROME model for Central Europe",
and that **"If 15-minutely data is requested for other regions data is
interpolated from 1-hourly to 15-minutely."** A live query for Bengaluru
(12.97, 77.59) returns a clean 15-minute grid that is arithmetic, not
observation. It is an hourly global model wearing a nowcast costume.

Verified. Free tier is generous — 600 calls/min, 5,000/hour, **10,000/day**, no
API key — but the resolution is not there.

**RainViewer can, with a hard limit.** Their public API example states the
personal-use tier plainly:

> "Max zoom: Level 7 (512px tiles), Color scheme: Universal Blue only,
> Data: **Past radar data only (no forecast/nowcast, no satellite)**,
> Format: PNG only"

A live `weather-maps.json` fetch on 27 Aug 2026 returned **13 past frames at
600 s spacing** (2 h 50 min) and an **empty `nowcast` array**, consistent with
that. Tile URL form is
`{host}{path}/{size}/{z}/{x}/{y}/{color}/{options}.png`.

The zoom-7 cap sounds crippling and is not. At z7 with 512 px tiles there are 128
tiles around the globe, so one tile spans 40,075 / 128 × cos(13°) = **305 km**,
which is **596 m per pixel** at Bengaluru's latitude. Against a 30 km lookahead
that is 50 samples. Ample.

Bandwidth: Bengaluru sits inside one or two tiles. A mostly-transparent 512 px
PNG is 10–60 kB, refreshed every 10 minutes → **~17 B/s**, ~200 kB for a
half-hour ride. Nothing.

### The design that follows from "no nowcast"

**Do not compute a time-to-rain.** With only past frames, that means estimating
cell motion by cross-correlating consecutive radar images — optical flow on 13
noisy frames on a phone. It will produce a confident number that is sometimes
badly wrong, which is the exact thing this project refuses to ship.

**Report distance instead.** Sample the latest frame along a ±10° corridor ahead
of the rider's GPS course, every 500 m out to 30 km, and send the distance to the
first echo above a threshold. `RAIN 8 km` is robust, needs no motion estimation,
degrades to silence rather than to a lie, and is what the rider can act on.

**One optional refinement that is genuinely cheap.** Convective cells travel with
the mid-level steering flow, which Open-Meteo serves free as a pressure-level
variable. A live query returned **`wind_speed_700hPa` = 45.6 km/h,
`wind_direction_700hPa` = 294°** for Bengaluru. Comparing the steering vector to
the bearing of the echo tells you whether the cell is closing on you or drifting
away — one extra field, no image processing, and it upgrades `RAIN 8 km` to
`RAIN 8 km ↓` (closing) versus `RAIN 8 km ·` (drifting). Add it only after the
distance version has been ridden with.

### Cost

| | |
|---|---|
| Phone | ~20 h: tile fetch + cache, `BitmapFactory` decode, Universal Blue palette → intensity lookup, corridor sampling |
| BLE | **3 bytes** — `u8 intensity, u16 distance_100m`. New type `0x0A RAIN` |
| Firmware | one band state, one precedence row in `bandFor()` |
| Screen | **zero when dry** — exception-only |
| Glance | one large word and one number, ~0.3 s, and only when it matters |

### ★ The gate: verify Bengaluru radar coverage before writing any code

This is the `turn:lanes` discipline applied to a new dataset, and it must not be
skipped. RainViewer lists **27 radar stations for India**. Whether one of them
covers Bengaluru is **unverified, and there is reason for doubt**: press coverage
as recent as 2021–2025 has Bengaluru "tentatively planned" for a C-band DWR and
carries headlines to the effect that the city needs one. The nearest confirmed
Karnataka installation is **Mangaluru**, ~300 km away, with a stated 250–300 km
range — which puts Bengaluru at or beyond the edge, where beam height above
ground makes low-level rain invisible.

**The ten-minute check:** open rainviewer.com's live map during a monsoon shower
in Bengaluru and look at whether there is an echo over the city or a hole. If it
is a hole, this feature is dead and you have spent ten minutes — the same trade
the lane-guidance Overpass query made.

If it is dead, the fallback is honest but much weaker: Open-Meteo hourly
`precipitation_probability` as a pre-ride check **on the phone, not on the
display**. That is a decision made at the door, not at the handlebar, and it does
not belong on this device.

**Sources:** [Open-Meteo docs](https://open-meteo.com/en/docs) ·
[Open-Meteo pricing](https://open-meteo.com/en/pricing) ·
[RainViewer API](https://www.rainviewer.com/api/weather-maps-api.html) ·
[RainViewer public-tier terms](https://github.com/rainviewer/rainviewer-api-example/blob/master/README.md) ·
[RainViewer coverage](https://www.rainviewer.com/coverage.html) ·
[Deccan Herald — Bengaluru needs DWRs](https://www.deccanherald.com/india/karnataka/bengaluru/city-needs-doppler-weather-radars-2021933)

---

## 7. Idle-screen local map — free, once the vector window exists

**What.** When no route is active, the display shows the heading-up local road
sketch that `ARCH_ANDROID_AUTO.md` §2.2 already specifies, with no route line on
it.

**Cost.** **Approximately zero incremental.** Same MBTiles store, same MVT
decode, same `0x09 GEOM` packet, same ESP32 tile cache and rotation. The only new
code is a branch in `screenFor()` that renders GEOM without a route overlay.

**Why it earns its place.** It is the answer to structural finding 2. It is also
the strongest argument *for* building the vector window at all, because it
doubles the fraction of riding time during which that work is visible — from the
~20% spent navigating to ~100% of screen-on time.

**The honest caveat.** A local road sketch with no route is decoration, not
information, in a city you know. Its real value is in the two cases where you do
not know it: a wrong turn into an unfamiliar layout, and riding somewhere new
without having bothered to set a destination. That is a modest but genuine
value, and it is free, which is why it ranks where it does rather than higher.

It also inherits the sunlight caveat that `ARCH_ANDROID_AUTO.md` §4.3 already
recorded: thin road lines are the first thing glare destroys. On the idle screen
that matters less, because nothing depends on reading it.

---

## 8. Notification whitelist — the group-riding feature worth building

**What.** Let the Android app hold a list of allowed senders or threads. Alerts
from those reach the band; everything else is dropped at the phone, never
transmitted.

**Cost.** ~4 h Kotlin plus a settings screen. **Zero BLE, zero firmware, zero
screen space.** It is a filter on a feature that already exists.

**Why this is the group-riding answer.** The brief asks about group riding, and
the obvious version — position sharing, gap-to-the-rider-behind — is rejected
below. But the actual coordination problem on a group tour is *messages*: "fuel
stop at the next pump", "pulled over, left indicator", "wrong turn, wait". Those
arrive as WhatsApp notifications, which this device **already displays.**

The reason it isn't useful today is signal-to-noise. On an unfiltered phone the
band lights up for OTPs, delivery updates and family group chatter, and a rider
who has learned the band is usually noise stops reading it — which silently
destroys the call alert too. **A whitelist does not add a feature; it rescues one
that is at risk of being tuned out.**

For a group ride the whitelist is a single entry: that ride's WhatsApp group.
Everything else goes quiet for the duration.

**Bonus, free:** the same mechanism is the correct implementation of a
do-not-disturb mode. One toggle, zero new surface.

---

## 9. Ride-end summary card

**What.** For ~10 s after arrival (or after the 15 s navigation-end debounce
fires), the display shows: distance, duration, packets received, packets dropped,
seconds spent STALE, number of disconnects, number of parse failures.

**Cost.** ~3 h. Counters the firmware already increments or trivially can.
**Zero cost during the ride** — it is on screen only when the ride is over and
the bike is presumably stopped or slowing.

**Why it earns its place.** It answers "should I trust this thing?" with numbers
instead of a feeling, once per ride, at the only moment when reading numbers is
free. `PROJECT_STATE.md`'s method is measurement; this is the measurement, shown
to the person who has to decide whether to keep riding with it.

It also makes the silent log (#4) actionable without a laptop. If the card says
`STALE 47 s / 3 disconnects`, you know to pull the log. If it says `0 / 0`, you
don't.

---

## 10. Fuel — a button page for touring, and nothing at all in the city

**The brief asks whether the value is the WARNING or the NEAREST STATION. The
answer is: neither, in Bengaluru, and the nearest station on a highway run.**

### The warning is dead, and the bike killed it

The Speed 400 has a 13 L tank, an 8-bar gauge, a low-fuel lamp at ~3 L, **and a
range-to-empty readout**. The lamp fires with roughly **66–84 km of reserve**
(3 L × 22–28 km/l), after roughly **220–280 km** of riding.

Any warning this device could produce would be computed from *trip distance since
an assumed fill*, which requires the rider to tell it when they filled up and
requires trusting a fuel-economy constant against Bengaluru's traffic variance.
The bike measures the actual level. **We would be replacing a measurement with an
estimate, in order to duplicate a lamp six inches away** — structurally the same
mistake as the speedometer, and it is rejected for the same reason.

Garmin's zumo ships trip-distance fuel tracking with dynamic fuel stops. That is
the right feature for a *car-derived* device on a bike whose fuel data it cannot
read. It is the wrong feature here, because here the instrument cluster already
does it better.

### The nearest station is worthless in the city — with arithmetic

731 fuel stations in the Bengaluru bbox `(12.80, 77.40, 13.20, 77.85)`. That box
is 44.5 × 48.8 km = **2,172 km²**, so station density is **0.336 per km²**. For a
roughly uniform distribution the expected distance to the nearest one is
`0.5 / √λ` = **0.86 km**.

**In Bengaluru you are essentially never more than a kilometre from fuel.** A
display that tells you the nearest pump is 900 m away is telling you something
you would have found by continuing to ride. The feature has no city value at all.

### Where it does have value

A highway run — Bengaluru to Chikkamagaluru, Mysuru, the coast — where station
spacing goes from under a kilometre to tens of kilometres and 73% brand coverage
in OSM starts to matter (a named HP or IOCL is a real station; an unnamed node
may be a closed shed).

**Therefore: a button page, not a warning, not a permanent element.**
Press → `FUEL 11.2 km ↰ HP`. Costs zero until pressed, which is exactly the
budget a feature with this hit rate deserves.

**And it is nearly free if the vector window is built.** The phone will already
hold an offline OSM extract queried around the rider's position; `amenity=fuel`
is one more layer in the same tiles, one more query against the same SQLite file.
No new data source, no new permission, no network. That is the pairing the brief
asked about, and it is the strongest one on this list after the idle map.

---

## 11. OTA — already planned over WiFi. Do **not** build the BLE version.

**Correcting a tempting idea rather than proposing one.** `PRIOR_ART.md` notes
NAVRIDER had OTA-over-BLE working by 17 April and lists it under "worth
stealing". It is not worth stealing, because `BUILD_PLAN.md` **Stage 10 already
specifies ArduinoOTA over WiFi, with two successive updates as a hard gate before
the case is sealed.** That covers the entire risk.

**Why WiFi is the right transport here and BLE is not.**

- The failure this protects against is *"the case is glued and the firmware is
  wrong"*. That update happens in a garage or on a desk, in home-WiFi range —
  exactly Stage 10's stated model ("joins home WiFi when in range, otherwise
  carries on"). Roadside firmware updates are not a real scenario.
- BLE OTA at MTU 185 moves a ~700 kB image at the conservative ~2 kB/s figure
  `ARCH_ANDROID_AUTO.md` costed — **about six minutes**, against seconds over
  WiFi, with far more code to get a rollback right.
- It duplicates a gate that already exists. Two mechanisms for the same job is
  two things to keep working.

**Two notes on Stage 10 as written, worth having.**

- **WiFi and BLE coexistence on plain ESP32 costs real RAM** — `FEATURES.md`
  already records this. Not a problem here, because OTA runs parked with no
  phone connected: **tear the BLE stack down before bringing WiFi up**, rather
  than running both.
- **Flash budget, checked.** 4 MB board. `FEATURES.md` warns that two OTA app
  partitions plus a filesystem will not fit "once TLS and fonts are in" — but
  that warning was written about the *desk-buddy* build with WiFi, TLS and LVGL
  resident. The bike firmware has none of those. Stock `min_spiffs` gives
  **1.9 MB × 2 app slots**; this sketch is nowhere near that.

**The genuinely new item hiding here is not OTA — it is what OTA is for.**
`NAV_DATA.md` says the Maps format breaks roughly annually, and when it does the
fix is usually on the phone. Which means the thing worth protecting is the
*Android* app's update path, not the firmware's: a sideloaded debug-signed APK
with no update mechanism, on a Samsung that aggressively kills background
services. Keep the Gradle install path scripted and the listener re-enable
commands from `NAV_DATA.md` in the repo, because that is the update you will
actually make under time pressure.

---

## 12. Arrival and last-mile — a 60 s hold, and an honest admission

**What is achievable.** On `arrived`, hold the final road name and a large
`ARRIVED` for 60 s before falling back to the idle screen. ~2 h firmware, no new
data.

**Why it is worth the two hours.** Maps drops its notification **4.7 s after
arrival**, and the required 15 s removal debounce means the device confirms the
end of the route about 15 s later still. In that window the rider is doing the
hardest part of the journey — finding the actual gate among three — and the
display has already reverted to a clock. Holding the last thing it knew is
strictly better than showing nothing.

**Why this device cannot solve last-mile properly, stated plainly.** Every good
last-mile feature — "destination on your left", distance-to-door, a parking
suggestion, a final-approach compass — needs the **destination coordinate**, and
`NAV_DATA.md` has verified against a complete `dumpsys` dump that Maps publishes
no such thing. The AA schema has `Destination.location` as a `LatLng`, and
`ARCH_ANDROID_AUTO.md` has already disqualified that path on the manual
head-unit-server button before every ride.

So: no last-mile feature. Do not chase one. If the project ever owns the route
(Valhalla, OsmAnd fork), last-mile becomes available for free as a side effect,
and that is the right time to build it — not before.

---

# Rejected, with the reasons

## Speed limits and over-speed warning — REJECTED on coverage

Tempting, because unlike *speed* this is genuinely not on the instrument cluster:
the Speed 400 shows how fast you are going, not how fast you may. And Bengaluru
enforcement is camera-based and unforgiving.

**Measured, Overpass, same bbox, 27 Aug 2026:**

```
[out:json][timeout:180];
way["maxspeed"]["highway"~"^(motorway|trunk|primary|secondary)(_link)?$"]
   (12.80,77.40,13.20,77.85);
out count;
```

| Query | Ways |
|---|---:|
| Arterials with `maxspeed` | **2,231** |
| All arterials (from `ARCH_ANDROID_AUTO.md`) | **9,398** |
| **Coverage** | **23.7%** |

This is far better than `turn:lanes`' 0.52%, and it is still not enough — and the
reason is the same one recorded there. **Silence is indistinguishable from "no
limit posted".** A warning that is absent on three arterials in four teaches the
rider that absence means safe, which is false 76% of the time.

There is a second, worse problem specific to this tag: `maxspeed` in OSM is often
a *default* inferred by a mapper rather than a signed limit, and it goes stale
when limits change. A lane-guidance blank is merely useless; a wrong speed limit
is confidently wrong, which `BLE_PROTOCOL.md` already names as the failure mode
worth avoiding above all ("never guess — a confidently wrong arrow is worse than
no arrow").

**Not building it.** Revisit only if someone systematically surveys the 50–200
junctions actually ridden, the same way the lane-guidance doc scoped it.

## Speed-camera alerts — REJECTED on coverage, harder

```
[out:json][timeout:180];
node["highway"="speed_camera"](12.80,77.40,13.20,77.85);
out count;
```

**37 nodes.** Across a metro of 13 million people that runs automated enforcement
at scale. The dataset is not incomplete, it is decorative.

Same failure mode as above, amplified: a camera warning that is silent almost
everywhere trains exactly the wrong reflex.

## Group riding by position sharing — REJECTED on bootstrap

**What it would be.** Every rider's phone publishes position to a shared channel;
the display shows the gap to the furthest-back rider, and flags anyone stopped or
off-route.

**Why it does not survive.** It requires N riders each running a personal,
debug-signed, sideloaded Android app, plus a broker (Firebase free tier or
self-hosted MQTT would both work — this is not the blocker). The device has not
completed a single real ride *solo*. Building a multi-device feature before the
single-device case is validated is the ordering error `FEATURES.md` already
called out when deferring Valhalla.

**And the failure mode is bad in a specific way.** A stale gap reading says the
rider behind is 400 m back when they went down 4 km back. A safety feature that
degrades into false reassurance is worse than no feature — the same argument that
killed the speed-limit warning, applied to people.

**Revisit** when a second unit exists. Not before. See #8 for the 80% version
that costs four hours and needs nobody else's hardware.

## Live traffic, in any form — STAYS REJECTED

`NAV_DATA.md` and `FEATURES.md` have both killed this, and the reduced version
("one boolean: heavy traffic within 2 km") was left on the table. Taking it off
the table: the exception band now has three better claimants (parse failure,
rain, calls), a rider cannot reroute from a handlebar, and on a motorcycle you
filter through the red section regardless. It was right the first two times.

## Persistent trip stats, media, battery percentage, temperature, AQI, altitude, compass-to-home

All fail the same test in the same way: permanently on screen, never acted upon,
and a re-glance magnet. `FEATURES.md` has already disposed of media and battery
percentage; the rest join them. Every one of them is available on a button page
at zero cost, which is where they belong if they belong anywhere.

**★ One live contradiction between the docs, found while checking this.**
`BUILD_PLAN.md` Stage 9 task 1 says *"Caller ID + now-playing … Send CALL and
MEDIA packets"*, and `BLE_PROTOCOL.md` carries `0x04 MEDIA`. But `FEATURES.md`
records now-playing as **still refused** — "text you must parse, no navigational
value". The build plan is the older document and the decision post-dates it.
**Do not implement `0x04 MEDIA`.** Leave the protocol row reserved and delete
the task from Stage 9, or it will get built by whoever reads the plan and not
the decision — and `BLE_PROTOCOL.md` already warns that MEDIA is the one packet
whose NUL-separated layout breaks the generic trailing-text reader. It is the
most expensive row in the protocol and the least wanted.

## Bike telemetry — REJECTED on access

Fuel level, gear position, revs and coolant temperature would all be genuinely
useful and none is reachable. The Speed 400's diagnostic connector is
proprietary, there is no owner-accessible CAN broadcast, and reading it would
require a sensor on the device — which constraint 4 forbids, correctly.

---

# What the prior art does that this does not

Cross-checked against `PRIOR_ART.md`. Four items, three of which are covered
above.

| Prior art | Does this project have it? |
|---|---|
| **Auto-backlight** (Beeline — credited for its sunlight readability) | **Planned (Stage 9), unbuildable today.** The MOSFET is missing. Item #1. |
| **OTA over BLE** (NAVRIDER, working April 2026) | **Equivalent already planned** over WiFi (Stage 10). Item #11 — do not build the BLE one. |
| **ESP32-initiated refresh** (lavrushko — empty indication when the phone goes quiet) | **No, and it is ~1 h.** `NAV_DATA.md` measured 64 s with no field change in slow traffic; the ESP32 currently cannot distinguish that from a dead phone except by the arrival counter. A device-initiated poll turns a passive watchdog into an active handshake. Worth doing alongside #2. |
| **Waypoints, "skip to next POI", compass mode** (Beeline) | **No, and correctly so** — all three require owning the route, which `FEATURES.md` has decided against for sequencing reasons that have not expired. |

---

# Confidence register

Stated plainly, matching the house style.

**Verified by direct query or direct reading:**

- Open-Meteo `minutely_15` is interpolated from hourly outside NA / Central
  Europe — their own documentation.
- Open-Meteo free tier: 600/min, 5,000/hour, 10,000/day, no key.
- Open-Meteo serves `wind_speed_700hPa` / `wind_direction_700hPa` free —
  live query returned 45.6 km/h from 294° over Bengaluru.
- RainViewer public tier: past radar only, no nowcast, z7 max, 512 px,
  Universal Blue, PNG. Live `weather-maps.json` returned 13 past frames at
  600 s spacing and an empty nowcast array.
- `maxspeed` on Bengaluru arterials: **2,231 / 9,398 = 23.7%** (Overpass,
  27 Aug 2026).
- `highway=speed_camera` in the Bengaluru bbox: **37 nodes** (Overpass,
  27 Aug 2026).

**Inferred, not measured:**

- Fuel-station mean nearest-neighbour distance of 0.86 km assumes a roughly
  uniform distribution. Real stations cluster on arterials, so the figure is
  optimistic *along a road* and pessimistic in the interior of a residential
  block. The conclusion — under a kilometre, effectively always — is robust to
  that.
- RainViewer tile bandwidth (10–60 kB per mostly-transparent 512 px PNG) is an
  estimate from typical PNG behaviour, not a measurement.
- Android effort figures throughout are estimates in the same units
  `ARCH_ANDROID_AUTO.md` used, and should be read with the same scepticism.

**Unknown, and load-bearing:**

- **Whether weather radar actually covers Bengaluru.** This gates item #6
  entirely. Press coverage suggests the city has been "tentatively planned" for a
  C-band DWR rather than having one, and the nearest confirmed Karnataka
  installation is Mangaluru at ~300 km. RainViewer lists 27 India stations
  without saying where. **Ten-minute check specified in §6. Do it before writing
  code.**
- Whether the RainViewer Universal Blue palette maps cleanly to intensity bands
  without empirical calibration. Their colour-scheme page exists; its contents
  were not read.
- Whether a glove-operable momentary switch of the right feel is available
  locally at the ₹200 estimate. The mechanism is trivial; the ergonomics are the
  part that decides whether the button gets used.

---

# The thing this document is not allowed to skip

None of the above changes the project's gate. `HARDWARE.md`'s arithmetic still
says **ACR ≈ 1.17 : 1** against a requirement of 5 : 1 in Bengaluru noon sun, and
`PRIOR_ART.md` still says the stall point for every project in this space is
"converting a viral reel into a weatherproof, sunlight-readable, mountable
object".

Item #1 — backlight PWM — is on the build-now list partly because it is the only
item here that pulls in the same direction as that gate. Everything else on this
list is worth building **after** a noon ride settles whether the panel stays.
