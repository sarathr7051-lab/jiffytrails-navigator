# tools — testing the navigator without a phone

`navsim.py` pretends to be the Android app that does not exist yet. It connects
to the ESP32 over BLE from a Windows laptop and writes protocol packets exactly
as `docs/BLE_PROTOCOL.md` specifies, printing every packet as hex next to what
it means, so the laptop console and the ESP32 serial monitor can be read side by
side.

It never opens a COM port and never flashes anything. Keep the Arduino IDE's
serial monitor open at 115200 while it runs — that is half the test.

The acceptance tests it is built for are in `docs/STAGE5_TEST_PLAN.md`.

---

## Install

You need Python 3.9 or newer. **This machine does not have Python yet.**

1. Get it from [python.org/downloads](https://www.python.org/downloads/) —
   the "Windows installer (64-bit)".
2. During setup, tick **Add python.exe to PATH**. If you miss it, the `py`
   command below will not exist and you will have to re-run the installer.
3. Do *not* use the Microsoft Store stub. Typing `python` on a fresh Windows 11
   opens the Store instead of running anything; that is the stub, not Python.
4. Then, in PowerShell:

```powershell
py -m pip install bleak
```

`bleak` is the only dependency. It talks to the Windows BLE stack directly — no
dongle, no driver, no pairing.

Check it worked, with no hardware attached:

```powershell
py C:\dev\jiffytrails-navigator\tools\navsim.py --selftest
```

Every line should say `PASS`. This also prints the corrected version of the
worked example from `BUILD_PLAN.md` (see "The spec bug", below).

---

## Find the device first

```powershell
py navsim.py --scan
```

This lists everything advertising nearby. The ESP32 advertises as
**`JiffyTrails`** (`DEVICE_NAME` in `navigator.ino`), which is what every other
mode matches by default. If the firmware advertises something else, add
`--name <name>` or `--address <address>` to any command below.

**Do not pair the ESP32 in Windows Bluetooth settings.** This protocol needs no
pairing, and a stale Windows pairing is the most common reason a connect starts
failing after it previously worked. If it shows up under Settings → Bluetooth &
devices, remove it.

Only one central can be connected at a time. Close nRF Connect on the phone
before running the laptop tool, and vice versa.

---

## The modes

Run everything from this folder, or give the full path to the script.

### `--ride` — the one that matters

```powershell
py navsim.py --ride
```

Replays a scripted Bengaluru route at 1 Hz: eight legs, about 6 km, roughly ten
minutes. It uses the real Google Maps behaviours from `docs/NAV_DATA.md`, not a
tidy simulation:

- **Distances are quantised** — 100 m steps above 1 km, 50 m from 1 km down to
  300 m, 10 m below 300 m.
- **Values are rounded to the band, not stepped through it**, so at speed the
  digits *skip*: 290 → 270 → 250 → 230. This is deliberate. A smooth countdown
  would flatter the display and hide the flicker that actually matters.
- **The remaining distance drifts** by a few percent every packet, because
  `progressMax` does. It must be recomputed on every packet, never cached.
- **`next_maneuver` is always UNKNOWN/0**, because Google Maps does not expose
  a next maneuver. Anything the display does with that field must survive it
  being empty forever.
- A **rerouting** state fires on leg 4 and a **gps_weak** state on leg 6.
- The route ends with an explicit **`nav_active = 0`**. Silence is ambiguous;
  "not navigating" is not.

Useful flags:

| Flag | Effect |
|---|---|
| `--speed-mult 4` | Ride four times faster. Same 1 Hz packet rate, so the digits skip much harder — the worst case for the distance field |
| `--reconnect` | Rescan and reconnect if the link drops, and time the recovery. This is the laptop half of the walk-30-m-away test |
| `--seed 1234` | Change the jitter. The same seed always replays identically |
| `--dry-run` | Print the packets without touching Bluetooth |

**Correct behaviour:** every packet on the laptop console has a matching line on
the ESP32 serial. The distance on the panel matches the `dist=` field in the
decoded line. During the reroute the screen says REROUTING and **no arrow is
drawn**, even though the packet still carries `maneuver=ROUNDABOUT`. At the end
the panel drops to the idle screen and keeps no trace of the last maneuver.

### `--screen <name>` — hold one state for a photograph

```powershell
py navsim.py --screen now
```

Holds a single state at 1 Hz indefinitely, so the watchdog stays quiet and you
can photograph the panel at arm's length. Ctrl+C to stop.

| Name | State |
|---|---|
| `far` | 1.2 km — instruction, medium distance, ETA, remaining km |
| `approach` | 350 m — distance large, arrow large |
| `committed` | 80 m — full-screen arrow and distance, nothing else |
| `now` | 20 m — inverted colours |
| `idle` | `nav_active = 0` — clock and trip stats, never a maneuver |
| `rerouting` | REROUTING, arrow suppressed |
| `gps_weak` | Normal nav screen plus a small corner warning |
| `arrived` | Destination reached |
| `unknown` | Maneuver `0x00` — must render `?`, never a guessed arrow |
| `longtext` | The 59-character instruction observed in the wild |
| `roundabout` | Reserved code `0x23` (roundabout, exit 3) |
| `battery` | A STATUS packet — must not disturb the nav screen |
| `trip` | A TRIP packet |

**Correct behaviour:** anything you cannot read in half a second at arm's length
is too small. That is the actual test.

### `--stale` — prove the 10 s watchdog fires

```powershell
py navsim.py --stale
```

Sends normally for ten seconds, then stops dead **while staying connected**, and
counts the seconds out loud. After 25 s it starts sending again.

**Correct behaviour:** the panel dims and shows STALE about 10 s after the last
packet. It must **not** show PHONE DISCONNECTED — the link is still up, and
confusing a dead link with dead data is a failure. When packets resume, the nav
screen returns within one packet, with no reset and no button press.

This is the test that catches a change-based watchdog. `NAV_DATA.md` measured
64 seconds with no field changing at all while Maps kept posting at 1 Hz, so the
watchdog must count packet *arrivals*.

### `--flood` — tearing and heap growth

```powershell
py navsim.py --flood
```

Sends at 20 Hz for 30 seconds — roughly twenty times the real rate — with values
that change on every packet, then settles back to 1 Hz. Tune with
`--flood-rate` and `--flood-seconds`.

**Note the ESP32's free heap before and after.** A few hundred bytes of jitter is
normal; a steady downward slope is a leak in the packet handler.

**Correct behaviour:** no torn digits, no half-drawn arrow, no reset, no heap
trend. Dropping packets under flood is fine — the display cannot usefully redraw
at 20 Hz anyway — but it must never render a partial frame. Afterwards the panel
settles to a clean, steady screen.

### `--garbage` — malformed input

```powershell
py navsim.py --garbage
```

Sends every malformed packet in the tool's list, a second and a half apart:
empty writes, truncated payloads, a length byte that lies in both directions,
unknown packet types, a 200-byte instruction against a 64-byte buffer, invalid
UTF-8, an embedded NUL, an undefined maneuver code, and 256 bytes of noise. It
starts from a known-good screen and **ends with a valid packet**.

**Correct behaviour:** the ESP32 does not reboot, the BLE link stays up, free
heap is unchanged, and the final valid packet renders correctly. That last one
is the real test — a parser that rejects everything afterwards has failed just
as badly as one that crashes.

Each packet's `EXPECT:` line says whether it should be rejected or accepted, so
read those rather than assuming every case leaves the screen alone. Two of them
are *supposed* to be accepted: the current firmware treats the `len` byte as
advisory and bounds every read by the ATT write length instead, so a `len` that
undercounts is tolerated while a `len` that overcounts is dropped. The safety
property under test is that nothing is ever read past the end of the write.

The undefined maneuver code must render `?`. A confidently wrong arrow is worse
than no arrow.

### `--nrf` — hex strings for the phone

```powershell
py navsim.py --nrf
```

Prints the packets as hex, with decodes, ready to paste into nRF Connect's write
field. No Bluetooth is used, so this works on any machine. Same strings as
`docs/STAGE5_TEST_PLAN.md`.

### `--selftest` — check the tool, not the firmware

```powershell
py navsim.py --selftest
```

Encoding and decoding round trips, the quantisation bands, and every named
screen — all offline. Run this after changing the script, and before blaming the
firmware for anything.

---

## Reading the output

```
14:22:07.412 TX  26B  01 18 03 64 00 02 50 00 0C 00 20 00 01 4F 6C 64 20 4D 61 64 72 61 73 20 52 64
             NAV len=24 maneuver=TURN_RIGHT(0x03) dist=100 m next=UNKNOWN(0x00)/0 m eta=12 min remaining=3.2 km flags=0x01[nav_active] instr="Old Madras Rd"
             EXPECT: UI_NAV_COMMITTED - full-screen arrow + distance, nothing else
```

- `TX` is laptop → ESP32, `RX` is a notification coming back.
- The decode line is what the bytes *say*. Compare it with the ESP32 serial
  line for the same instant — they must agree field for field.
- The `EXPECT` line is what the panel should be showing, derived from
  `screenFor()` in `firmware/navigator/nav_types.h`. If the decode is right and
  the panel disagrees with EXPECT, the bug is in the display, not the parser.

---

## The spec bug

`docs/BUILD_PLAN.md` Stage 5 gives this worked example:

```
01 0F 03 64 00 02 50 00 0C 00 20 00 01 + "Old Madras Rd"
```

**The field order and every value in it are correct. The length byte is not.**

The NAV payload is 11 fixed bytes (`u8 + u16 + u8 + u16 + u16 + u16 + u8`) plus
the 13-byte instruction — 24 bytes, `0x18`. The example says `0x0F`, which is
15, and matches neither the 11 bytes printed after it nor the 24 the packet
actually carries. Corrected:

```
01 18 03 64 00 02 50 00 0C 00 20 00 01 4F 6C 64 20 4D 61 64 72 61 73 20 52 64
```

Everything in this folder and in `docs/STAGE5_TEST_PLAN.md` uses the corrected
form. Details in the test plan.

---

## When it does not work

| Symptom | Cause |
|---|---|
| `'py' is not recognized` | Python is not installed, or PATH was not ticked during install. Re-run the installer |
| `python` opens the Microsoft Store | That is the Store stub. Install real Python from python.org |
| `bleak is not installed` | `py -m pip install bleak` |
| `no BLE device matching 'JiffyTrails'` | Wrong name — run `--scan` and pass `--name`. Or the ESP32 is not advertising: check its serial output. Or something else is already connected to it |
| Scan finds nothing at all | Bluetooth is off. Toggle it off and on once; the Windows BLE stack gets stuck |
| Connects, then "navigator service was not found" | The ESP32 is running different firmware, or the UUIDs in `ble.cpp` do not match `docs/BLE_PROTOCOL.md` |
| Connect worked yesterday, fails today | Windows cached a pairing. Settings → Bluetooth & devices → find it → Remove device |
| Everything stalls after a few minutes | Something else grabbed the adapter. Close nRF Connect for Desktop |
