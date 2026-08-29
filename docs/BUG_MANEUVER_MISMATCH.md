# BUG: handlebar showed CONTINUE while Maps' banner showed a right turn

Status: **investigation complete** (diagnostic only — no code changed).
Fixes are specified at the end and deliberately not applied.
Opened 29 Aug 2026. Route: Kochi, Jawahar Rd northbound toward Moulana Azad Rd.

## The observation

Rider reports the handlebar display showed "continue / go straight" while Google
Maps' own in-app banner showed a right-turn arrow, "450 m", "Moulana Azad Rd".
He took the correct turn only because he knew the road. He recalls turning
*left*; the screenshot says the next maneuver is a *right* onto Moulana Azad Rd.
The screenshot is the harder evidence.

Three things may disagree:
1. Maps' in-app banner
2. The notification our app parses
3. The physical turn

## Contents

- [0. What the wire byte must have been](#0-what-the-wire-byte-must-have-been)
- [1. Can the notification lag the banner?](#1-can-the-notification-lag-the-in-app-banner)
- [2. Can classify() return CONTINUE for a turn icon?](#2-can-maneuversclassify-return-continue-for-a-turn-icon)
- [3. Can the parser HOLD a stale maneuver?](#3-can-the-parser-hold-a-stale-maneuver)
- [4. Distance updating without maneuver](#4-is-there-a-path-where-distance-updates-but-maneuver-does-not)
- [5. The 15 s removal debounce and step boundaries](#5-does-the-15-s-removal-debounce-interact-badly-with-a-step-change)
- [6. Logging: what exists, what to add](#6-logging-what-exists-and-the-one-line-to-add)
- [7. Ranked conclusions](#7-ranked-conclusions)
- [Proposed fixes — not applied](#proposed-fixes--specified-deliberately-not-applied)

## Method and confidence labels

Every claim below is one of:

- **VERIFIED** — I read the code path, file and line cited.
- **INFERRED** — follows from verified code plus measured data in NAV_DATA.md,
  but the specific combination was not itself observed.
- **UNKNOWN** — no evidence either way in this repo. Named as such rather than
  guessed at.

Files read in full: `MapsParser.kt`, `Maneuvers.kt`, `NavListenerService.kt`,
`NavPacket.kt`; `LinkService.kt` and `BleLink.kt` for the nav path;
`firmware/navigator/ble.cpp`, `display.cpp`, `maneuvers.cpp`, `navigator.ino`
for what the wire byte becomes on the panel.

---

## 0. What the wire byte must have been

Before anything else, one deduction narrows the search sharply.

The rider reports a **straight-ahead arrow**, not a question mark.

- `Mv.UNKNOWN` is `0x00` and the firmware draws it as a **"?"**, not an arrow —
  `firmware/navigator/maneuvers.cpp:166-170` ("Never guess an arrow - say so
  instead"), and the `?` is drawn in font 4 precisely because it must be legible.
- `firmware/navigator/ble.cpp:152-176` (`handleNav`) copies the maneuver byte
  into `NavState` verbatim. There is no hold, no substitution, no "keep the last
  known" path. **VERIFIED.**
- `firmware/navigator/display.cpp:676-677` draws `s.maneuver` through
  `drawManeuver()` unless `geomValid()` — and the moving-map geometry is only
  ever populated by `demo.cpp` (`geomBegin`/`geomWay`/`geomPt` appear in
  `demo.cpp`, `geom.cpp`, `geom.h` and nowhere else), which is serial-triggered
  (`navigator.ino:91-92`) and cannot arm on a ride. **VERIFIED.**

**Conclusion: the byte on the wire was genuinely `0x01 Mv.CONTINUE`.** Every
explanation that ends in UNKNOWN — a null icon, a render failure, an unmatched
hash, the ambiguity guard firing — is therefore ruled out, because all of them
produce `0x00` and a "?" on the panel. This eliminates a large part of the
hypothesis space in one step.

---

## 1. Can the notification lag the in-app banner?

### What is measured

NAV_DATA.md contains **one** simultaneous comparison of Maps' own UI against the
notification, and it is decisive enough to be the centre of this whole
investigation. `docs/NAV_DATA.md:479-528`, captured from
`dumpsys notification --noredact` **"at a moment when Maps was rendering
'Then →' in its own UI"**, on a live route **on Moulana Azad Rd** — the same
road as the incident:

```
android.title                                   = "Head toward Moulana Azad Rd"
android.ongoingActivityNoti.primaryInfo         = "0 m"
android.ongoingActivityNoti.secondaryInfo       = "towards Moulana Azad Rd"
android.ongoingActivityNoti.nowbarSecondaryInfo = "towards Moulana Azad Rd"
android.ongoingActivityNoti.chipIcon            = BITMAP 135x135

PROBE-ICONS chip=CONTINUE second=CONTINUE nowbar=CONTINUE (all same)
```

So: **Maps drew a turn in its own UI while all three notification bitmaps
classified CONTINUE.** That is measured, not inferred.

### What that dump would have put on the handlebar

Trace the same extras through our parser:

| Field | Path | Result |
|---|---|---|
| maneuver | `MapsParser.kt:383` → `Maneuvers.classify` → `BY_HASH["c2a2c91"]` (`Maneuvers.kt:144`) | `Mv.CONTINUE` — straight arrow |
| distance | `MapsParser.kt:385-388`, `parseDistance` `MapsParser.kt:416-424`, `RE_DIST_M` `MapsParser.kt:103` | `"450 m"` → `450` |
| instruction | `chooseInstruction` `MapsParser.kt:468-471`: `nowbarSec` `"towards Moulana Azad Rd"` → `RE_TOWARDS` (`MapsParser.kt:77`) strips the connector → `"Moulana Azad Rd"`, 15 chars ≤ `GLANCE_CHARS` 20 → **returned immediately** | `"Moulana Azad Rd"` |

Panel: **[straight arrow] · 450 · "Moulana Azad Rd"**.
Banner: **↱ · 450 m · Moulana Azad Rd**.

**Identical in every field except the arrow.** That is the rider's report, and it
is reproducible from a dump already committed to this repository. **VERIFIED**
that this state exists and that our code renders it exactly this way;
**INFERRED** that it is what the rider actually saw.

### So: is it a lag?

Almost certainly **not**, and this matters for how it gets fixed.

- A lag would be bounded by Maps' ~1 Hz post rate (NAV_DATA.md:130) plus our own
  ~1.9 s worst case (section 4). At Kochi city speeds that is tens of metres, not
  **450**. A 450 m disagreement is roughly 35-50 s of riding. Nothing in the
  notification pipeline can hold a value that long while the distance keeps
  counting — the distance and the maneuver come out of the *same bundle*
  (`MapsParser.kt:213-220`), so a stale maneuver would arrive with a stale
  distance too. **VERIFIED** from the code structure.
- The measured dump gives a mechanism that needs no lag at all: at that instant
  the notification was describing a **"Head toward …" (depart) step**, whose
  chipIcon is the straight/depart glyph, while Maps' banner was already
  depicting the **maneuver that terminates that step** — the right turn onto
  Moulana Azad Rd.

**The root cause is semantic, not temporal: the banner depicts the maneuver at
the END of the current step; `chipIcon` (at least during a depart step) depicts
the travel action of the step itself.** NAV_DATA.md's own hash table names this
collision explicitly — `c2a2c91` is labelled **"CONTINUE / depart"**
(`NAV_DATA.md:89`), and `Maneuvers.kt:144` copies that comment forward. One hash,
two meanings, and we map both to a confident straight arrow.

### The part that is genuinely unknown

Whether this generalises beyond the depart step — i.e. whether `chipIcon` shows
the continue glyph for the whole of *any* long straight step while the banner
shows the terminating turn — is **UNKNOWN**. Evidence pulls both ways:
`TURN LEFT` and `TURN RIGHT` hashes were each seen on 5 rides
(`NAV_DATA.md:90-91`), so `chipIcon` certainly does show turns at some point in
the approach. Nothing in the docs records *at what distance* it switches.

That single unknown is what section 6's log line is designed to close, and it is
closeable in one ride.

**Verdict on question 1: "the notification lags its own banner" is ruled out as
the explanation. The weaker and better-supported claim — "the notification and
the banner do not always depict the same maneuver, and the depart step is a
measured instance" — stands, and is largely not our bug. Our bug is rendering it
as a confident straight arrow rather than as something the rider can read as
'not a junction call'.**

---

## 2. Can `Maneuvers.classify()` return CONTINUE for a turn icon?

Walking all three tiers of `Maneuvers.kt:196-227`.

### Tier 1 — resource entry name (`Maneuvers.kt:199-210`)

**Dead today. VERIFIED.** `resName` (`Maneuvers.kt:357-365`) returns null unless
`icon.type == TYPE_RESOURCE` (2), and NAV_DATA.md:509 records
`chipIcon = BITMAP 135x135`, i.e. type 1. Tier 1 cannot have produced this.

One latent hazard worth recording even so: `BY_NAME` (`Maneuvers.kt:86-123`) is
an **unanchored substring** scan taken first-hit, and the CONTINUE keywords sit
*above* the turn keywords —

```
"depart" to Mv.CONTINUE,      // Maneuvers.kt:118
"straight" to Mv.CONTINUE,    // :119
"continue" to Mv.CONTINUE,    // :120
"left" to Mv.TURN_LEFT,       // :121
"right" to Mv.TURN_RIGHT,     // :122
```

so a hypothetical Maps resource named `ic_continue_right` or
`ic_straight_then_right` classifies as **CONTINUE**. The header comment
(`Maneuvers.kt:82-85`) states the ordering rule as "most specific first" and it
is correctly applied for `merge_left` vs `left`, but "continue"/"straight" are
*generic* tokens sitting above the turn tokens rather than below them. **Not the
cause here** (tier 1 never runs), but it is a real latent path to a wrong
CONTINUE the day Maps ships resource icons. Ranked #7 below.

### Tier 2 — exact pixel hash (`Maneuvers.kt:212-219`)

`BY_HASH["c2a2c91"] → Mv.CONTINUE` (`Maneuvers.kt:144`). For a turn glyph to land
here it would have to *collide* with the continue glyph's hash.

The hash is `hash * 31 + (alpha shr 5)` seeded at 17 over 1024 pixels
(`Maneuvers.kt:330-341`), accumulating into a 32-bit Int. NAV_DATA.md:83 reports
"zero collisions across five rides" over ten glyphs. A collision between two of
a ten-element set in a 32-bit space is negligible. **Ruled out** as a practical
explanation, though note this is a statistical argument, not a proof.

The far more likely tier-2 behaviour is the one described in section 1: **no
collision at all — Maps genuinely sent `c2a2c91`, and `c2a2c91` genuinely means
"CONTINUE *or* depart".** The ambiguity is in the table, not in the matcher.

### Tier 3 — fuzzy bitmap match (`Maneuvers.kt:221-223`, `fuzzy` at :274-296)

Two real structural findings here, one reassuring and one not.

**The learning invariant holds. VERIFIED.** `learn()` is called from exactly two
places: `Maneuvers.kt:207` (tier 1 hit) and `Maneuvers.kt:217` (tier 2 hit). The
fuzzy branch at `Maneuvers.kt:221-223` returns without learning. So a fuzzy match
can never seed the reference set, and the "one near-miss drags the set onto the
wrong glyph" failure the comment at `Maneuvers.kt:298-301` warns about **cannot
happen**. `SEEDED` (`Maneuvers.kt:177-182`) is empty, so `refs` contains only
tier-1/tier-2-confirmed signatures.

`learn()` is further guarded at `Maneuvers.kt:307`: it refuses to add a signature
within `MAX_DIFF_BITS` (32) of *any* existing ref, of any code. So the reference
set is guaranteed pairwise ≥32 bits apart. Conservative and correct.

**`AMBIGUOUS_WITHIN` is not protective in the case that matters. VERIFIED.**
`fuzzy` (`Maneuvers.kt:284-294`):

```kotlin
var rivalDiff = Int.MAX_VALUE          // closest ref with a *different* code
for (s in refs) {
    if (s.code == win.code) continue
    val d = diff(rows, s.rows)
    if (d < rivalDiff) rivalDiff = d
}
if (rivalDiff - bestDiff < AMBIGUOUS_WITHIN) { ...refuse... }
```

`rivalDiff` initialises to `Int.MAX_VALUE`. If `refs` currently holds signatures
of **only one distinct code**, the loop never assigns, `rivalDiff - bestDiff`
overflows to an enormous positive number, and the guard passes unconditionally.
The *only* remaining gate is `bestDiff < MAX_DIFF_BITS` at `Maneuvers.kt:282`.

This is reachable. `refs` is cleared on every listener reconnect
(`MapsParser.reset()` → `Maneuvers.reset()`, `MapsParser.kt:302-305`, called from
`NavListenerService.kt:77`), and CONTINUE is by far the most frequent glyph on a
route, so **"refs contains exactly one signature, and it is CONTINUE" is the
normal state for the first minutes of every ride.** In that window the ambiguity
guard is inert by construction.

Note also that `AMBIGUOUS_WITHIN` is a *relative margin*, not an absolute quality
test: a winner at 31 bits with a rival at 40 bits is accepted, even though 31
bits is a poor match.

**But it still probably did not cause this. INFERRED.** For the hole to bite, a
right-turn glyph would have to render within **32 of 1024 bits** (3.1%) of the
continue glyph. Both glyphs carry roughly 150-200 set pixels at 32×32
(`SPEC_MANEUVER_ICONS.md` puts shaft width at 16% and head base at 52% of the
box), and a straight arrow versus a right-turn arrow differ across the entire
upper-right quadrant — order 100-200 bits, not 31. So the fuzzy path is a real
defect in the guard but an implausible cause of *this* report. Ranked #4.

**Verdict on question 2: `classify()` returning CONTINUE for a turn glyph is
possible in principle via the tier-3 hole, but the far simpler reading is that
it was handed the genuine CONTINUE/depart glyph and classified it correctly.
The mis-mapping is in `BY_HASH`'s one-hash-two-meanings entry, not in the
matcher.**

---

## 3. Can the parser HOLD a stale maneuver?

**No. VERIFIED, and this is the cleanest result in the investigation.**

Every carried-forward field in `MapsParser`, exhaustively:

| Field | Declared | Held where | Can it stale the maneuver? |
|---|---|---|---|
| `heldDistM` | `MapsParser.kt:179` | `:385-388` — `parsedDist ?: heldDistM` | No. Distance only. |
| `arrivalMinuteOfDay` | `:160` | `:566-571` | No. And it holds the *clock target*, recomputing the countdown each packet, so it cannot silently age (`:557-563`). |
| `heldRemaining100m` | `:164` | `:394` (overwritten every navigating packet), read only by `reroutingUpdate` `:349` | No. |
| `heldEtaMin` | `:165` | `:398`, same shape | No. |
| `lastProgressMax` | `:180` | `:428-429` | No — route-replacement detection only. |
| `lastManeuver` | `:182` | `:248-252` | **No — used only to gate a log line.** Never read back into an update. |
| `lastArrived` | `:155` | `:247`, read by `poll()` `:284` | No. |

The maneuver itself: `navigatingUpdate` computes `match` at `MapsParser.kt:383`
and assigns `maneuver = match.code` at `MapsParser.kt:400`. There is no `?:`, no
fallback, no previous value in that expression. **When the icon is missing or
unclassifiable, `Mv.UNKNOWN` is sent, not the previous value.** `classify`
returns `Match(Mv.UNKNOWN, "no-icon")` for a null icon (`Maneuvers.kt:197`),
`"no-drawable"` for a render failure (`Maneuvers.kt:212`), and `UNMATCHED`
(`Maneuvers.kt:77`, `:226`) for an unmatched bitmap.

The other three state branches also send fixed maneuvers, never held ones:
`startingUpdate` → `UNKNOWN` (`:331-336`), `reroutingUpdate` → `UNKNOWN`
(`:345-353`, with an explicit comment that the previous arrow no longer describes
the road), `arrivingUpdate` → `DESTINATION` (`:361-369`).

Combined with section 0 — UNKNOWN renders as "?" — **the "held maneuver with a
fresh distance" failure the brief calls the dangerous combination is not
reachable in this codebase.** If it had happened, the rider would have seen a
question mark, which is exactly the design intent.

The *inverse* hold is real and is by design: `heldDistM` freezes the **distance**
while the maneuver keeps updating (`MapsParser.kt:166-179` documents why — a
naive zero put "0 m" on the panel 40 m from a junction). That is the safe
direction: a frozen number beside a live arrow, not a live number beside a frozen
arrow.

---

## 4. Is there a path where distance updates but maneuver does not?

Yes — and structurally it is unavoidable, because the two fields have entirely
independent sources: the maneuver is a **bitmap** (`chipIcon`,
`MapsParser.kt:220`), the distance is a **string** (`primaryInfo`,
`MapsParser.kt:216`). They fail independently.

**Direction A — distance updates, maneuver constant.** This is the *normal*
appearance of a long step, and it is exactly what section 1 describes: the
distance counts 450 → 400 → 350 while `chipIcon` stays on the depart/continue
glyph. Nothing anywhere in the stack flags it, because nothing can tell it apart
from a genuine "continue straight for 450 m".

This is the heart of why the failure was invisible:

- `MapsParser.kt:248-252` logs **only when the maneuver changes**, so a whole
  450 m approach on a wrong-but-constant CONTINUE produces exactly **one** log
  line, timestamped at the start.
- `BleLink.flushNav` (`BleLink.kt:814-832`) de-duplicates on the whole frame, so
  every distance tick still writes and the device's arrival-counting watchdog
  (`BleLink.kt:169-176`) stays fed.
- The firmware redraws on the new distance and keeps drawing the same arrow.

**A stale maneuver with a counting-down distance looks perfectly healthy at every
layer**, which is what the brief anticipated — the only correction is that here
the maneuver is not *stale*, it is *faithfully reproduced and semantically
wrong*.

**Direction B — maneuver updates, distance frozen.** `heldDistM`
(`MapsParser.kt:385-388`) when `primaryInfo` carries a road name or the maneuver
text instead of a distance (rule 2, `NAV_DATA.md:150-157`). Deliberate, safe,
documented.

**Minor finding — up to ~1.9 s of added latency on a maneuver change.**
`BleLink.flushNav:819` drops a submission that arrives within
`MIN_NAV_INTERVAL_MS` = 900 ms (`BleLink.kt:167`) of the last write; the frame is
retained in `pendingNav` and goes out on the next 1 Hz tick
(`BleLink.kt:385-391`, `TICK_MS` = 1000). So worst case a genuine step change is
delayed ~1.9 s. Correct behaviour for a radio budget, worth knowing, and **three
orders of magnitude too small to explain 450 m**.

---

## 5. Does the 15 s removal debounce interact badly with a step change?

**No. A step boundary cannot be swallowed. VERIFIED.**

The debounce is strictly additive — it gates *end-of-route only*, and never gates
a posted notification:

- `MapsParser.onPosted` (`:195-254`) parses and returns an update on **every**
  Maps navigation notification. The debounce appears in it only at `:203-207`,
  where a re-post *cancels* a pending end-of-route and logs how much time was
  left. It does not `return` early, does not suppress, does not merge.
- `MapsParser.onRemoved` (`:261-272`) arms `pendingEndAt` and explicitly emits
  nothing.
- `MapsParser.poll` (`:281-290`) is the only consumer of the timer and only ever
  produces `NavUpdate(navActive = false)`.
- `NavListenerService` mirrors this exactly: `onNotificationPosted` →
  `handleIfMaps` → `parser.onPosted(...)?.let { push(it) }`
  (`NavListenerService.kt:82-85, 104-107`); `onNotificationRemoved` for the Maps
  package returns immediately after arming (`:87-93`).

So a remove/re-post straddling a step change delivers the new step on the
re-post, in the normal way. The only loss during a remove/re-post gap is that no
new packet arrives — and NAV_DATA.md:203-225 is explicit that this gap is
sub-second in practice.

Two adjacent observations, neither causal here:

- `parser.reset()` on `onListenerDisconnected` (`NavListenerService.kt:77`)
  clears `Maneuvers.refs`. That is the mechanism that makes the section-2 tier-3
  hole reachable — after a reconnect the reference set is empty and refills with
  CONTINUE first.
- `MapsParser.resetRoute()` (`:311-324`) clears `heldDistM` and `lastManeuver`
  but deliberately preserves learned signatures (`:307-310` comment: "the glyph
  set belongs to the installed Maps build, not to the route"). Correct.

---

## 6. Logging: what exists, and the one line to add

### What already exists

| Log | Location | Fires when | Would it have settled this? |
|---|---|---|---|
| `maneuver -> NAME  N m  "instr" eta= rem=` | `MapsParser.kt:248-252` | **only when the maneuver code changes** | No. One line for the whole 450 m approach, and it does not say *why* CONTINUE was chosen. |
| `PROBE shortCriticalText=… nowbarSecondary=… flags=…` | `MapsParser.kt:654-658` | only when the **text** signature changes (`:633-635`) | Partly — it would show `title` and `nowbarSecondary`. But it omits the icon hash entirely. |
| `PROBE-ICONS chip=… second=… nowbar=…` | `MapsParser.kt:660-662` | same text-signature gate | No. Gated on *text* change, so during a long step it is silent, and it logs maneuver names without hashes or tiers. |
| `icon ambiguous: … refusing to guess` | `Maneuvers.kt:291-293` | fuzzy near-tie | Only for a case that ends in UNKNOWN, i.e. not this one. |
| `UNRECOGNISED maneuver icon hash=… <ASCII art>` | `Maneuvers.kt:372-386` | once per distinct unmatched hash | Only for a case that ends in UNKNOWN. |

**The most galling gap: `Match.via` already carries the answer and is never
logged anywhere.** `Maneuvers.kt:73` defines `data class Match(val code: Int,
val via: String)`, and `via` is populated with exactly the discriminating string
— `"res=<name>"`, `"hash=c2a2c91"`, `"fuzzy=<label>/12b"`, `"no-icon"`,
`"no-match"`. It is computed on every classification, threaded through
`navigatingUpdate` (`MapsParser.kt:383`), read only for `match.known`
(`MapsParser.kt:404`), and thrown away. **The tier that produced the answer is
already known and discarded.**

Note also that a **successful fuzzy match logs nothing at all** — no warning, no
`via` — so if the tier-3 hole in section 2 ever does bite, there is currently no
trace of it.

### The single extra log line

Add to `MapsParser.navigatingUpdate`, immediately after
`val match = Maneuvers.classify(ctx, icon, title)` (`MapsParser.kt:383`), with
one new field `private var lastIconSig: String? = null` beside `lastManeuver`
(`MapsParser.kt:182`), cleared in `resetRoute()` (`MapsParser.kt:311-324`):

```kotlin
val iconSig = "${match.code}|${match.via}|$title"
if (iconSig != lastIconSig) {
    lastIconSig = iconSig
    Log.i(TAG, "ICON ${Mv.name(match.code)} via=${match.via} d=${parseDistance(primary)}m " +
            "title=\"$title\" primary=\"$primary\" secondary=\"$secondary\"")
}
```

Why this one line is sufficient, and why each piece earns its place:

- **`via`** names the tier and, for tier 2, *contains the raw hash*. It separates
  the three surviving hypotheses outright: `via=hash=c2a2c91` confirms Maps sent
  the genuine continue/depart glyph (#1); `via=hash=93f8340f` arriving late
  confirms a real lag (#2); `via=fuzzy=…` confirms the tier-3 hole (#4).
- **`title`** is the decisive datum and is currently only logged on a text
  change. `"Head toward Moulana Azad Rd"` versus `"Turn right onto Moulana Azad
  Rd"` settles section 1's remaining unknown — whether the notification was on
  the depart step or on the turn step — in a single glance.
- **The distance** turns the log into a distance-indexed trace, which is what
  answers the one thing NAV_DATA.md never recorded: **at what distance does
  `chipIcon` switch from the continue glyph to the turn glyph?**
- **Gating on the signature, not on the maneuver code**, is the fix for the
  existing blind spot. `MapsParser.kt:248` fires on `update.maneuver !=
  lastManeuver` and is therefore silent for exactly the 450 m in which the bug
  lives; including `via` and `title` in the key makes it fire on every genuine
  *step* change while still staying quiet at ~1 Hz on a long straight.

One ride down Jawahar Rd produces a line per step and closes the question.

**Cheaper variant, if only a diff to an existing line is acceptable:** append
`via=${match.via}` and `title="$title"` to `MapsParser.kt:250` and widen its
trigger at `:248` to include the title. Same information, one fewer field, but it
loses the distance-indexed trace that answers the switch-over question.

---

## 7. Ranked conclusions

| # | Explanation | Confidence | Ours? |
|---|---|---|---|
| 1 | **`chipIcon` depicted the depart/"Head toward" step while Maps' banner depicted the right turn that terminates it.** One hash, `c2a2c91`, means both CONTINUE and depart (`NAV_DATA.md:89`, `Maneuvers.kt:144`); we render both as a confident straight arrow. Reproducible from the dump at `NAV_DATA.md:479-528`, captured on the same road, showing `title="Head toward Moulana Azad Rd"` + `PROBE-ICONS chip=CONTINUE` while Maps drew "Then →". Traced through `chooseInstruction` (`MapsParser.kt:468-471`) the panel would read **[straight] 450 "Moulana Azad Rd"** against a banner of **↱ 450 m Moulana Azad Rd** — every field matching except the arrow. | **High** for the mechanism; **inferred** that it is what the rider saw | Not a parse bug. **Our bug is presenting it as a confident junction call.** |
| 2 | Rider glanced at the panel and took the screenshot at different moments; his "left" recollection is imprecise, so his "straight" may be too. | Medium, and compatible with #1 | Not ours |
| 3 | Maps' notification genuinely lags its own banner across a step boundary. | **Low as the cause; UNKNOWN as a phenomenon** — no measurement exists either way. Bounded by ~1 Hz posting plus ≤1.9 s of our own rate limit (`BleLink.kt:167,819`), i.e. tens of metres. Cannot produce 450 m. | Not ours; mitigation only |
| 4 | Tier-3 fuzzy matched the turn glyph onto a learned CONTINUE signature. The guard hole is **real and verified** (`Maneuvers.kt:284-294`: `rivalDiff` stays `Int.MAX_VALUE` when `refs` holds one distinct code, so `AMBIGUOUS_WITHIN` is inert — the normal state early in every ride, since `refs` is cleared on reconnect at `NavListenerService.kt:77`). But it needs a right-turn glyph within 32/1024 bits of the continue glyph, ~5× closer than two different arrows plausibly render. | Low as the cause; the **defect is confirmed** and should be fixed on its own merit | **Ours** |
| 5 | Latent: `BY_NAME`'s unanchored substring scan puts `"straight"`/`"continue"`/`"depart"` above `"left"`/`"right"` (`Maneuvers.kt:118-122`), so a resource named `ic_continue_right` would classify CONTINUE. | Not the cause — tier 1 is dead while `chipIcon` is `type=1` (`NAV_DATA.md:509`, `Maneuvers.kt:358`) | **Ours**, latent |
| — | Stale/held maneuver in the parser | **RULED OUT.** Maneuver is never held (`MapsParser.kt:400`); every failure path returns UNKNOWN, and UNKNOWN draws "?" not an arrow (`maneuvers.cpp:166-170`). The rider saw an arrow. | — |
| — | 15 s removal debounce swallowing a step boundary | **RULED OUT.** `onPosted` parses and emits unconditionally; the debounce gates only `poll()`'s end-of-route (`MapsParser.kt:195-254, 261-290`). | — |
| — | Firmware holding or substituting a maneuver | **RULED OUT.** `handleNav` applies the byte verbatim (`ble.cpp:152-176`); moving-map geometry is demo-only (`navigator.ino:91-92`). | — |

**Plain statement, as asked for:** the most likely explanation is *not* that Maps'
notification lags its own banner. It is that **the notification and the banner
depict different things** — the banner shows the maneuver at the end of the
current step, `chipIcon` (measurably, during a depart step) shows the step's own
travel action — and our table collapses the two meanings of `c2a2c91` into one
confident straight arrow. That is mostly "not our bug", but the mitigation is
squarely ours, because a confident wrong arrow at a junction is the one failure
this project's whole design refuses to ship.

---

## Proposed fixes — specified, deliberately NOT applied

### F1 — stop rendering "depart" as "continue" (addresses #1)

`c2a2c91` means two things. Split them using `title`, which is safe here in a way
the `Maneuvers.kt:190-193` rule anticipates: text would decide *depart vs
continue*, never *left vs right*, so it cannot point the rider the wrong way.

1. Add `Mv.DEPART` to `NavPacket.kt` (next free code after `FERRY = 0x15`, i.e.
   `0x16`), plus its `Mv.name` arm.
2. In `MapsParser.navigatingUpdate`, after `MapsParser.kt:383`: if
   `match.code == Mv.CONTINUE` and `title` matches
   `^\s*(head|start|depart|proceed)\b` (case-insensitive), substitute
   `Mv.DEPART`.
3. Firmware: a distinct `G_DEPART` glyph — the spec's own reasoning at
   `SPEC_MANEUVER_ICONS.md:759-764` (the destination pennant is deliberately not
   the maneuver head, so it cannot read as a right turn) applies directly: a
   depart mark must not read as "the road ahead is straight". A shaft with an
   origin dot at its foot, no junction implied.
4. Update `BLE_PROTOCOL.md` and `firmware/navigator/nav_types.h` together.

This does not recover the turn — nothing can, `NAV_DATA.md:517-536` closes that —
but it stops the panel *asserting* straight-on when Maps is asserting a turn.

### F2 — make `AMBIGUOUS_WITHIN` actually protective (addresses #4)

In `Maneuvers.fuzzy` (`Maneuvers.kt:284-294`), the margin test must not pass by
default when there is no rival. Add an absolute quality floor alongside it:

```kotlin
// A margin test with no rival is not a test. Require the winner to be a
// genuinely good match before trusting a set that has nothing to compare it to.
private const val LONE_REF_MAX_BITS = 12    // vs MAX_DIFF_BITS = 32

if (rivalDiff == Int.MAX_VALUE && bestDiff > LONE_REF_MAX_BITS) {
    Log.w(TAG, "icon fuzzy=${Mv.name(win.code)} at $bestDiff bits with no rival " +
            "to check against - refusing to guess")
    return null
}
if (rivalDiff - bestDiff < AMBIGUOUS_WITHIN) { /* existing guard */ }
```

Also guard the subtraction itself against the `Int.MAX_VALUE` sentinel rather
than relying on overflow arithmetic to produce a large positive.

### F3 — log a successful fuzzy match (addresses the section-6 blind spot)

`fuzzy` returns `Match(win.code, "fuzzy=${win.label}/${bestDiff}b")`
(`Maneuvers.kt:295`) and nothing records it. The `ICON` line in section 6 covers
this for free once `via` is logged; if the ICON line is not adopted, add a
one-shot `Log.i` in `fuzzy` keyed on `win.label`.

### F4 — reorder `BY_NAME` (addresses #5, latent)

Move `"depart"`, `"straight"`, `"continue"` (`Maneuvers.kt:118-120`) **below**
`"left"` and `"right"` (`:121-122`), or anchor the generic entries. The
"most specific first" rule the header states (`:82-85`) is not currently
satisfied for these three.

