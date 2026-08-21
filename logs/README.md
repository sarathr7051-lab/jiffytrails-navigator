# Ride logs

Captured output from `android/navdump/`.

Raw `.log` files are gitignored. Curated excerpts that demonstrate something
specific belong in `samples/`, with a note on what they show.

## Captured so far

| Date | Route | What it established |
|---|---|---|
| 19 Aug 2026 | Short evening loop, ~1 km | Distance countdown is continuous; deliberate wrong turn captured the rerouting state; four maneuver hashes |
| 20 Aug 2026 | Commute, ~6.7 km | Roundabout hash; full three-band distance ladder; confirmed rising distance is GPS jitter, not a wrong-way signal |

## Still wanted

U-turn, flyover, merge, keep-left/right, fork, sharp-left/right, exit/ramp.

Also: what Maps does when GPS drops — an underpass or covered parking. That's a
display state that has to be handled honestly and there's no data on it yet.
