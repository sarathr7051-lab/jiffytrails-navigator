# BLE protocol

Phone ⇄ ESP32. The ESP32 is the GATT **peripheral**; the phone connects as
central and writes packets at ~1 Hz.

Request MTU 185 on connect so instruction strings fit in one write.

## UUIDs

```
Service        6e400001-b5a3-f393-e0a9-e50e24dcca9e
Char (write)   6e400002-b5a3-f393-e0a9-e50e24dcca9e   phone → ESP32
Char (notify)  6e400003-b5a3-f393-e0a9-e50e24dcca9e   ESP32 → phone
```

## Framing

```
[type:u8][len:u8][payload…]
```

Little-endian throughout.

**`len` is the PAYLOAD length — it excludes the two header bytes.** Stated
explicitly because it is load-bearing: the NAV instruction string has no length
prefix and no terminator, so its extent is derived as `len` minus the 11-byte
fixed block. Getting this wrong truncates or overruns every road name.

A receiver should treat `len` as advisory and bound it by the actual ATT write
length. This data originates from a phone parsing an undocumented notification
format that has broken roughly annually; a wrong length must drop a packet, never
corrupt state.

| Type | Name | Payload |
|---|---|---|
| 0x01 | NAV | `u8 maneuver, u16 dist_m, u8 next_maneuver, u16 next_dist_m, u16 eta_min, u16 remaining_100m, u8 flags, utf8 instruction` |
| 0x02 | STATUS | `u8 flags, u8 phone_battery_pct` |
| 0x03 | CALL | `u8 state (0 idle / 1 ringing / 2 active), utf8 name` |
| 0x04 | MEDIA | `u8 state (0 stop / 1 play / 2 pause), utf8 title \0 artist` |
| 0x05 | TRIP | `u32 distance_m, u16 duration_min, u16 speed_kmh_x10, u16 max_speed_kmh_x10` |
| 0x06 | CONFIG | `u8 brightness (0 = auto, 1-100 manual), u8 units` |
| 0x07 | TRAFFIC | segment list derived from `progressSegments` |
| 0x08 | NOTIFY | `u8 kind, u8 src_len, utf8 src, utf8 text` |

`0x08 NOTIFY` — added 26 Aug 2026. `kind`: 0 generic, 1 message, 2 email,
3 alert. `src` is the app or sender shown as the small tag; `text` is the body
and runs to the end of the payload.

**Length-prefixed, not NUL-separated, deliberately.** `0x04 MEDIA` is the only
row that splits on NUL, and a generic trailing-text reader silently eats its
second field. A length prefix cannot be misread that way.

NAV flags:

| Bit | Meaning |
|---|---|
| 0 | nav_active |
| 1 | rerouting |
| 2 | gps_weak |
| 3 | arrived |

### ⚠ Three rows above cannot be implemented as written

Found 26 Aug 2026 while building the firmware against this document. Recorded
rather than invented, because guessing a wire format here would guarantee an
interop break later.

**`0x02 STATUS` — the `flags` byte has no documented bits.** Nowhere in the doc
set says what any bit means. The firmware parses the byte for framing
correctness and discards it. It is deliberately *not* folded into `NavState.flags`,
which is the NAV flag word — merging them would corrupt navigation state.

**`0x07 TRAFFIC` — "segment list derived from `progressSegments`" is a pointer,
not a format.** No count, no per-segment layout, no colour encoding, no units.
Unimplementable. It also has a downstream consequence: `NavState` has no traffic
field, so **the traffic bar from `ui_mock` is not in the shipped display**.
Restoring it needs this row specified first. Drawing fake segments would be a
lie about the road ahead.

**`0x04 MEDIA` — NUL is a field separator here and nowhere else.** `utf8 title
\0 artist` is the only payload that splits on NUL. NAV and CALL both end in a
single trailing UTF-8 field that runs to the end of the payload, so a generic
"read the rest as text" helper — which is what the firmware has — will silently
drop the artist. Whoever writes that handler needs to know.

### Two more gaps worth stating

**`INSTRUCTION_MAX` is 64, but MTU 185 permits a 172-byte payload.** The MTU
rationale above ("so strings fit in one write") is true of the wire and not of
the display buffer: a long instruction arrives intact and is then truncated on
render. Longest observed is 60 characters, so there is headroom — but it is
three characters, not the margin the MTU figure implies.

**Instruction text is not null-terminated on the wire.** Its extent is `len`
minus the 11-byte fixed block. A receiver should still stop at the first NUL if
a sender appends one, and must truncate on a UTF-8 code point boundary —
Bengaluru road names carry Kannada, and a severed multi-byte sequence renders as
garbage.

`next_maneuver` and `next_dist_m` are reserved. Google Maps does not expose
them (see NAV_DATA.md); they exist so an OsmAnd or Mapbox source can fill them
without a protocol change.

## Maneuver codes

```
0x00 UNKNOWN        0x09 KEEP_RIGHT      0x12 FLYOVER
0x01 CONTINUE       0x0A UTURN_LEFT      0x13 UNDERPASS
0x02 TURN_LEFT      0x0B UTURN_RIGHT     0x14 DESTINATION
0x03 TURN_RIGHT     0x0C MERGE           0x15 FERRY
0x04 SLIGHT_LEFT    0x0D FORK_LEFT
0x05 SLIGHT_RIGHT   0x0E FORK_RIGHT
0x06 SHARP_LEFT     0x0F EXIT_LEFT
0x07 SHARP_RIGHT    0x10 EXIT_RIGHT
0x08 KEEP_LEFT      0x11 ROUNDABOUT
```

`0x20`–`0x2F` reserved for ROUNDABOUT_EXIT_N.

An unrecognised icon hash maps to `0x00 UNKNOWN` and renders as a question
mark. **Never guess** — a confidently wrong arrow is worse than no arrow.

## Why typed messages

A fixed nav-only struct would have to be rewritten on both sides when caller ID,
media info or trip stats are added. Type-and-length framing costs two bytes per
packet and about ten lines of code, and makes every later addition free.

## Display rules

The ESP32 must never show a stale maneuver. Required states:

| Condition | Display |
|---|---|
| No packet for 10 s | Dim screen, "STALE" |
| BLE disconnected | "PHONE DISCONNECTED" |
| `nav_active == 0` | Clock and trip stats — never a maneuver |
| `rerouting` | "REROUTING", arrow suppressed |
| `gps_weak` | Small corner warning |

The watchdog counts **packet arrivals**, not value changes. See NAV_DATA.md for
why that distinction matters.
