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

### Decision

**Do not build.** Revisit only if the notification-text check finds lane
phrasing. Even then, sequence it after the sunlight gate — lane guidance is the
lowest-contrast, finest-detail element on the screen and the first thing glare
destroys.

Note also that on a Bengaluru motorcycle, where lane discipline is notional and
filtering is normal, "take the left 2 lanes" is worth considerably less than it
is to a car on a US freeway.
