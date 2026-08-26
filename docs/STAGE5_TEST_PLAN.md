# Stage 5 acceptance tests — BLE link and protocol

The Stage 5 gate in `BUILD_PLAN.md` is one sentence: *"Round-trip works,
reconnect is automatic."* This document is that sentence made concrete enough to
fail.

There are two paths through it. They test the same firmware and either is
sufficient for the gate:

- **nRF Connect** on the phone. No laptop, no Python. Paste hex by hand. Good
  for the single-packet tests, hopeless for anything timed.
- **`tools/navsim.py`** on the Windows laptop. Needs Python and `bleak`. This is
  the only way to run the ride, the watchdog, the flood and the garbage tests,
  because they all depend on packet *timing*.

Keep the Arduino IDE serial monitor open at 115200 throughout. Half of every
test below is reading the ESP32's own account of what it received.

---

## ★ The worked example in BUILD_PLAN.md is wrong

`BUILD_PLAN.md` Stage 5 says to send:

```
01 0F 03 64 00 02 50 00 0C 00 20 00 01     + "Old Madras Rd"
```

**Verified by hand against the spec. The field order and every value are
correct. The length byte is not.**

Decoding it field by field against
`u8 maneuver, u16 dist_m, u8 next_maneuver, u16 next_dist_m, u16 eta_min, u16 remaining_100m, u8 flags, utf8 instruction`:

| Bytes | Field | Value | Matches the expected output? |
|---|---|---|---|
| `01` | type | PKT_NAV | yes |
| `0F` | len | 15 | **no — see below** |
| `03` | maneuver | TURN_RIGHT | yes |
| `64 00` | dist_m | 100 | yes |
| `02` | next_maneuver | TURN_LEFT | yes |
| `50 00` | next_dist_m | 80 | yes |
| `0C 00` | eta_min | 12 | yes |
| `20 00` | remaining_100m | 32 → 3.2 km | yes |
| `01` | flags | nav_active | yes |
| `4F 6C 64 …` | instruction | "Old Madras Rd" | yes |

The payload is 11 fixed bytes (1+2+1+2+2+2+1) plus a 13-byte instruction —
**24 bytes, `0x18`**. `0x0F` is 15, and 15 is not the payload length (24), not
the frame length (26), not the fixed-field length (11), not the instruction
length (13), and not the 11 bytes actually printed after it in the plan. It
matches nothing under any reading.

**Corrected string — use this one everywhere:**

```
01 18 03 64 00 02 50 00 0C 00 20 00 01 4F 6C 64 20 4D 61 64 72 61 73 20 52 64
```

26 bytes total. `tools/navsim.py --selftest` re-derives this from the spec and
prints both versions, so the correction can be re-checked rather than trusted.

### Two related things the spec should say and does not

**1. `len` counts the payload, not the frame.** `[type:u8][len:u8][payload…]`
implies it, but it is never stated, and it matters: the NAV instruction has no
length prefix and no terminator, so `len` is the only thing that describes it.

How `ble.cpp` resolves this is worth knowing before you interpret any result
below. It treats **`len` as advisory** and bounds every read by the **ATT write
length**, which is the only length the radio actually guarantees:

- `len > arrived` → the write was truncated or corrupt. **Frame dropped.**
- `len < arrived` → **tolerated**, and the full write is parsed.

That second rule is why BUILD_PLAN's buggy `01 0F …` string *works* on this
firmware: 15 is less than the 24 bytes that arrive, so it is accepted and the
road name appears. The firmware is being deliberately generous to a phone that
miscounts.

That does not make the example correct, and it does not let the Android app off:
**it must send `0x18`**, because a stricter peripheral — including any future
rewrite of this one — is entitled to drop a frame whose length byte disagrees
with its contents. Test A5 covers the direction that must always be rejected.

Whatever policy is chosen, the safety property is the same: **never read past
the end of the write**, and reject any NAV frame with fewer than 11 payload
bytes.

**2. `STALE_MS` is contradicted inside the plan.** `BLE_PROTOCOL.md` says
*"No packet for 10 s"*, and `nav_types.h` sets `STALE_MS = 10000`. But
`BUILD_PLAN.md` Stage 7 says *"No packet 5 s"* and *"Watchdog:
`millis() - lastPacket > 5000`"*. **10 s is correct** — it is the value in the
shared header, and `NAV_DATA.md` derives it. Stage 7 of BUILD_PLAN.md should be
corrected. Test 4 below assumes 10 s.

Minor: `BUILD_PLAN.md`'s Stage 5 packet table omits `0x07 TRAFFIC`, which
`BLE_PROTOCOL.md` has. And `NAV_DATA.md` calls
`"Slight right at Horamavu Agara Circle onto Horamavu Agara Rd"` a 59-character
string; it is 60. Still inside `INSTRUCTION_MAX` (64), but only just — the
buffer holds 63 characters plus a NUL, so it has three characters of headroom,
not four.

---

## Path A — nRF Connect, no laptop

1. Power the ESP32. Serial should show it advertising.
2. nRF Connect → SCAN → find **`JiffyTrails`** (`DEVICE_NAME` in
   `navigator.ino`) → CONNECT.
3. Expand service `6E400001-B5A3-F393-E0A9-E50E24DCCA9E`.
4. On characteristic `6E400002-…` tap the **up arrow** (write). Set the format
   to **BYTE ARRAY**, paste a string below, SEND.
5. On characteristic `6E400003-…` tap **Subscribe** first, so anything the ESP32
   notifies back is visible.

Paste the hex without spaces if nRF Connect rejects them. Each string is given
here spaced for reading.

### A1 · Normal NAV packet

```
01 18 03 64 00 02 50 00 0C 00 20 00 01 4F 6C 64 20 4D 61 64 72 61 73 20 52 64
```

TURN_RIGHT, 100 m, next TURN_LEFT 80 m, ETA 12 min, 3.2 km remaining, active,
"Old Madras Rd".

**Serial must print:** `TURN_RIGHT, 100 m, next TURN_LEFT 80 m, ETA 12, 3.2 km,
active, "Old Madras Rd"`.
**Screen must show:** UI_NAV_COMMITTED — full-screen arrow and distance, nothing
else. 100 m is the boundary; per `screenFor()`, `dist_m < 100` is COMMITTED, so
exactly 100 falls in APPROACH. Confirm which one you get and that it matches
`screenFor()` rather than looking plausible.

### A2 · Under 30 m — the inverted screen

```
01 1B 03 14 00 00 00 00 08 00 15 00 01 54 43 20 50 61 6C 79 61 20 4D 61 69 6E 20 52 64
```

TURN_RIGHT, 20 m, no next maneuver, ETA 8, 2.1 km, active, "TC Palya Main Rd".

**Screen must show:** UI_NAV_NOW — inverted colours, full-screen arrow, 20 m.
Nothing else on screen.

### A3 · Rerouting — the arrow must disappear

```
01 14 03 78 00 00 00 00 0C 00 1E 00 03 52 65 72 6F 75 74 69 6E 67
```

TURN_RIGHT, 120 m, flags `0x03` = nav_active + rerouting, "Rerouting".

**Screen must show:** "REROUTING", **arrow suppressed** — even though the packet
still carries `maneuver = TURN_RIGHT` and a distance. This is the whole point:
the old turn is no longer true, and a firmware that keeps drawing the arrow
because the field is still populated has failed.

Send A1 immediately after. The arrow must come straight back. `NAV_DATA.md`
measured reroute recovery at 300–600 ms, so there is no excuse for a slow
return.

### A4 · nav_active = 0 — navigation ended

```
01 0B 00 00 00 00 00 00 00 00 00 00 00
```

All-zero NAV payload, 11 bytes, flags `0x00`.

**Screen must show:** the idle screen — clock and trip stats. **No arrow, no
distance, no leftover road name.** Send A1 first so there is a maneuver on
screen to fail to clear.

This is the test that catches a display which only ever overwrites fields
instead of switching state.

### A5 · Malformed — the length byte lies

```
01 18 03 64 00 02 50 00 0C 00 20 00 01
```

Identical to A1 but with the instruction cut off: `len` claims 24 payload bytes,
only 11 arrive.

**Must be rejected.** Serial should say so. The screen must not change at all —
not even to a partly updated maneuver. A firmware that reads the 11 valid bytes
and shrugs at the missing 13 will read past the end of the buffer on the day a
real packet is truncated by a short MTU.

### A6 · Malformed — unknown packet type

```
7F 04 DE AD BE EF
```

**No screen change**, no serial error storm. Unknown types are the
forward-compatibility feature the whole framing exists for.

It must, however, still **feed the stale watchdog**. Freshness is measured in
packet arrivals, and an unknown type proves the link is alive just as well as a
NAV packet does. Confirm on serial that the arrival was counted.

### A7 · Malformed — a one-byte write

```
01
```

**Must be ignored.** Two bytes are needed before `len` can even be read.

### A8 · Malformed — NAV with len = 0

```
01 00
```

**Must be ignored.** A NAV payload is at least 11 bytes.

### A9 · Extras worth pasting

| What | Hex |
|---|---|
| gps_weak, 500 m, CONTINUE, "Outer Ring Rd" | `01 18 01 F4 01 00 00 00 0A 00 1C 00 05 4F 75 74 65 72 20 52 69 6E 67 20 52 64` |
| Unknown maneuver → must render `?` | `01 17 00 F0 00 00 00 00 07 00 12 00 01 55 6E 6E 61 6D 65 64 20 72 6F 61 64` |
| Far band, 1.2 km | `01 18 01 B0 04 03 2C 01 0E 00 2A 00 01 4F 6C 64 20 4D 61 64 72 61 73 20 52 64` |
| Approach band, 350 m | `01 1B 03 5E 01 02 78 00 0B 00 20 00 01 54 43 20 50 61 6C 79 61 20 4D 61 69 6E 20 52 64` |
| Committed band, 80 m | `01 1F 02 50 00 01 90 01 09 00 18 00 01 4B 61 6D 6D 61 6E 61 68 61 6C 6C 69 20 4D 61 69 6E 20 52 64` |
| Arrived, DESTINATION, flags `0x09` | `01 13 14 00 00 00 00 00 00 00 00 00 09 41 72 72 69 76 69 6E 67` |
| Roundabout exit 3, reserved code `0x23` | `01 19 23 C8 00 00 00 00 09 00 16 00 01 48 65 6E 6E 75 72 20 4D 61 69 6E 20 52 64` |
| STATUS, phone battery 42% | `02 02 00 2A` |

`gps_weak` must be a **small corner warning** over an otherwise normal nav
screen, not a takeover. The unknown maneuver must render `?` — a confidently
wrong arrow is worse than no arrow. The reserved roundabout code may render a
roundabout glyph or `?`, but never a plain turn arrow.

`navsim.py --nrf` prints this list with decodes, if you would rather copy it
from a terminal than a table.

---

## Path B — navsim.py from the laptop

Setup is in `tools/README.md`. In short: install Python, `py -m pip install
bleak`, then `py navsim.py --scan` to confirm `JiffyTrails` is advertising.

Note the advertisement carries the 128-bit service UUID, which fills the 31-byte
advertising packet — the name comes from the scan response, so a scanner set to
passive scanning will show the device with no name. `--scan` uses active
scanning and will show it.

Run each test from `C:\dev\jiffytrails-navigator\tools`.

### Test 1 · Round trip

```powershell
py navsim.py --screen approach
```

**Pass:** the tool connects, reports the negotiated MTU, finds the service and
both characteristics, subscribes to notifications, and the panel shows the
350 m approach screen within one second. Every laptop `TX` line has a matching
ESP32 serial line agreeing field for field.

**Fail:** service not found (wrong firmware or wrong UUIDs); write rejected;
serial disagrees with the decoded line.

On Windows the central cannot request an MTU — WinRT negotiates it. The ESP32
must ask for 185 on connect. The tool prints what was agreed. A write can carry
`MTU − 3` bytes; the longest packet used here is 73 bytes, so anything from 76
up is sufficient. If the reported MTU is 23 (the default), long instructions
will be truncated by the stack and Test 3 will fail for a reason that is not the
display's fault.

### Test 2 · Every distance band, photographed

```powershell
py navsim.py --screen far
py navsim.py --screen approach
py navsim.py --screen committed
py navsim.py --screen now
```

Each holds indefinitely. Photograph the panel **at arm's length — mount height,
not reading distance**, sunglasses on if you ride with them.

**Pass:** each band is readable in under half a second. Anything you have to
look at twice is too small.

Also run `--screen longtext`, which sends the 60-character instruction observed
in the wild. **Pass:** the road name survives. Per `NAV_DATA.md`, truncating
from the end destroys the useful half — drop the maneuver prefix instead, since
the arrow already conveys it.

And `--screen unknown` and `--screen roundabout`, per A9 above.

### Test 3 · The ride ★

```powershell
py navsim.py --ride
```

Eight legs, about 6 km, roughly ten minutes at 1 Hz. This is the test that
matters, because it is the only one that feeds the display data shaped like real
data.

Watch for, in order of importance:

1. **Quantised distances.** The digits skip: 290 → 270 → 250 → 230. They are
   *supposed* to. If the display smooths or interpolates them, it is inventing
   data. The `dist=` field in the console is ground truth.
2. **The reroute on leg 4.** Screen says REROUTING and the arrow disappears,
   then comes back on the next normal packet.
3. **The gps_weak stretch on leg 6.** Small corner warning, nav screen otherwise
   unchanged.
4. **`next_maneuver` is always UNKNOWN/0**, because Google Maps has no such
   field. Whatever the display does with it must survive it being empty for the
   entire ride.
5. **Remaining distance drifts** by a few percent every packet, because
   `progressMax` does. The display must not treat a decrease-then-increase as an
   error.
6. **The ending.** The ride finishes with five `arrived` packets and then eight
   explicit `nav_active = 0` packets. The panel must drop to the idle screen and
   keep no trace of the last maneuver.

Then run it again hard:

```powershell
py navsim.py --ride --speed-mult 4
```

Same 1 Hz packet rate, four times the ground speed, so the digits skip in much
larger jumps. **Pass:** no flicker, no tearing, the distance field redraws
cleanly at every jump.

### Test 4 · The stale watchdog ★

```powershell
py navsim.py --stale
```

Ten seconds of normal traffic, then silence **while staying connected**, then
traffic again after 25 s.

**Pass:** about 10 s after the last packet the panel dims and shows STALE. When
packets resume, the nav screen returns within one packet — no reset, no button.

**Fail, three distinct ways:**

- The maneuver is still on screen after 10 s. The watchdog did not fire.
- The panel shows PHONE DISCONNECTED. The link is still up; the firmware is
  confusing a dead link with dead data. These are separate states in
  `screenFor()` and must stay separate — one means "look at your phone", the
  other means "the phone is here but not talking".
- The panel goes stale at 5 s. That is the wrong constant — see the
  BUILD_PLAN Stage 7 contradiction above. `STALE_MS` is 10000.

The watchdog must count **packet arrivals, not value changes**. `NAV_DATA.md`
measured 64 seconds in slow traffic with no field changing at all while Maps
kept posting at 1 Hz. To prove the firmware got this right, hold `--screen far`
for two minutes: the values never change, and the display must **never** go
stale.

### Test 5 · Flood

```powershell
py navsim.py --flood
```

20 Hz for 30 seconds — about twenty times the real rate — with values changing
on every packet, then back to 1 Hz.

**Note the ESP32's free heap before and after.**

**Pass:** no torn digits, no half-drawn arrow, no reset, no watchdog trip, and
free heap flat to within a few hundred bytes. Dropping packets under flood is
fine and expected; rendering a partial frame is not. Afterwards the panel
settles clean.

**Fail:** free heap trending steadily down — an allocation in the packet
handler. Or the panel left with artefacts from the last fast frame.

### Test 6 · Garbage ★

```powershell
py navsim.py --garbage
```

Every malformed packet in the tool's list, 1.5 s apart: empty writes, truncated
payloads, a length byte that lies in both directions, unknown types, a 200-byte
instruction against a 64-byte buffer, invalid UTF-8, an embedded NUL, maneuver
`0xFF`, `dist_m` at the u16 maximum, 256 bytes of noise. It starts from a
known-good screen and **ends with a valid packet**.

Each case prints an `EXPECT:` line saying whether it should be rejected or
accepted — read those rather than assuming every case leaves the screen alone.
Two are *supposed* to be accepted, under the advisory-`len` rule above.

**Note the ESP32's free heap before and after.**

**Pass:** every case behaves as its `EXPECT:` line says; the ESP32 does not
reboot (watch for a boot banner on serial); the BLE link stays up; free heap is
unchanged; and the **final valid packet renders correctly**.

That last clause is the real test. A parser that latches into a rejecting state
and ignores everything afterwards has failed exactly as badly as one that
crashes — and it fails silently, which is worse.

Two specific things to look for:
- Maneuver `0xFF` must render `?`.
- The 200-byte instruction must be truncated to fit `INSTRUCTION_MAX` **and
  still be NUL terminated**. This is the buffer-overflow case; a reboot here is
  a stack smash, not a rejection.

### Test 7 · Reconnect — walk 30 m away and back ★

This is the gate condition from `BUILD_PLAN.md`, and the one most likely to be
declared passed without actually being tested.

```powershell
py navsim.py --ride --reconnect
```

Then, carrying the laptop:

1. Wait until the ride is running and the panel is showing maneuvers.
2. Walk **30 m away** from the ESP32 — far enough that the link genuinely drops.
   The console prints `*** BLE DISCONNECTED ***` and the panel must change to
   PHONE DISCONNECTED. If it does not drop, go further; through a wall is
   better than down a corridor.
3. Stay out of range for at least 30 seconds, so this is a real disconnect and
   not a momentary glitch.
4. Walk back.

**Pass, all four conditions:**

- The panel showed **PHONE DISCONNECTED** while away — not STALE, and not a
  frozen maneuver.
- The link comes back **within 10 s** of returning to range. The tool times this
  and prints `RECONNECTED in N.N s` with a PASS or FAIL against the 10 s gate.
- **No button is pressed at either end.** No reset on the ESP32, no keypress on
  the laptop, no re-running the script. If you touched anything, the test did
  not pass.
- The ride resumes and the panel shows live maneuvers again.

**Fail:** the ESP32 stopped advertising after the disconnect. This is the usual
cause, and it is a one-line fix in the NimBLE disconnect callback — restart
advertising there, not only at boot.

Run it in both directions: also test the ESP32 losing power and coming back
while the tool keeps running.

**nRF Connect equivalent:** connect, walk away with the phone, walk back. nRF
Connect will not reconnect on its own, so this only tests that the ESP32 is
advertising again — tap CONNECT and confirm it works without touching the
ESP32. That is a weaker test than Path B, which is why the reconnect test is the
one argument for installing Python.

---

## The gate

Stage 5 passes when **all** of these are true:

| # | Condition | Test |
|---|---|---|
| 1 | A valid NAV packet round-trips and renders correctly | A1 / Test 1 |
| 2 | All four distance bands render and are readable at arm's length | Test 2 |
| 3 | Rerouting suppresses the arrow | A3 / Test 3 |
| 4 | `nav_active = 0` clears the maneuver completely | A4 / Test 3 |
| 5 | Stale fires at 10 s, and never fires on unchanging values | Test 4 |
| 6 | Stale and disconnected are distinct screens | Tests 4 and 7 |
| 7 | Malformed packets are rejected and a valid one still works after | A5–A8 / Test 6 |
| 8 | No reboot, no heap growth, under flood or garbage | Tests 5 and 6 |
| 9 | Reconnect within 10 s, unaided, no button at either end | Test 7 |

→ Stage 6.

Anything that fails, fix before writing the Android app. Every one of these
becomes ten times harder to diagnose once there is a phone in the loop, because
you can no longer tell which end is lying.

---

## Path A2 — vectors for the features added 26 Aug 2026

Alerts, arrival, clock and day/night landed after this plan was written. Byte
counts and ASCII verified, not hand-typed.

Send these on characteristic `6E400002-…`, BYTE ARRAY format, same as Path A.

### A10 · Incoming call

```
03 05 01 41 6D 6D 61
```

CALL, state 1 (ringing), name "Amma".

**Expect:** the bottom band **inverts to a solid black block** with white text —
tag "CALL", body "Amma". It persists while ringing.

Clear it with state 0:

```
03 01 00
```

### A11 · Notification

```
08 12 01 08 57 68 61 74 73 41 70 70 52 65 61 63 68 65 64 3F
```

NOTIFY, kind 1 (message), src "WhatsApp", text "Reached?".

**Expect:** band inverts, tag "WhatsApp", body "Reached?". **It must disappear
by itself after 6 seconds** — that is `NOTIFY_DWELL_MS`, and a notification that
persists has become a second thing to read on every glance.

### A12 · ★ The suppression rule — the important one

Send A11, then **within 6 seconds** send A2 (the 20 m packet).

**Expect: the band goes blank.** Not "the alert moves", not "the alert shrinks"
— blank. Under 100 m to a turn nothing may cover the maneuver, and the alert is
not queued for afterwards either.

This is the single most important behaviour in the alert feature. If the alert
survives A2, that is a bug and the turn is being obscured.

### A13 · Arrival

```
01 0F 14 00 00 00 00 00 00 00 00 00 09 48 6F 6D 65
```

NAV, maneuver DESTINATION, 0 m, flags `0x09` = nav_active + arrived,
instruction "Home".

**Expect:** destination flag glyph, "ARRIVED", and "Home". **It must hold for
about 30 seconds** (`ARRIVAL_DWELL_MS`) before falling back to idle — Maps drops
its notification about 4.7 s after arrival, so without the latch this screen
would flash past.

### A14 · Clock

```
02 04 00 4E 0E 23
```

STATUS, flags 0, battery 78%, 14:35.

**Expect:** nothing visible yet — then send `01 02 00 00` (a NAV with
nav_active = 0) to drop to idle, and the idle screen should show **14:35**
instead of READY.

Battery at 78% must **not** appear. It only shows at 20% or below — try
`02 04 00 0F 0E 23` (15%) and it should appear bottom-right.

### A15 · Day / night

```
06 03 00 00 01     night on
06 03 00 00 00     night off
```

**Expect on night:** the whole display inverts — near-black ground, and the text
should be **grey, not white**. If the text looks pure white, the grey-text change
did not take, and the point of night mode is lost.

The alert band should now be a **grey block with black text**, not a white
flash. Re-run A10 with night on to confirm.
