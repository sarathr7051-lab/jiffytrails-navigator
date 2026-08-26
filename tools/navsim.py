#!/usr/bin/env python3
"""navsim.py - pretend to be the phone, so the ESP32 can be tested without one.

The Android app does not exist yet. This stands in for it: a BLE central that
connects to the navigator, writes packets exactly as docs/BLE_PROTOCOL.md
specifies, and prints every packet as hex next to its decoded meaning so the
output can be read side by side with the ESP32's serial monitor.

The important mode is --ride. It replays a Bengaluru route at 1 Hz using the
real Google Maps behaviours documented in docs/NAV_DATA.md - in particular the
distance quantisation, where values are ROUNDED TO THE BAND rather than stepped
through it, so at speed the digits visibly skip. A smooth countdown would
flatter the display and hide the flicker that matters.

Requires Python 3.9+ and bleak:

    py -m pip install bleak

Nothing here opens a COM port or flashes anything. It only talks BLE.
"""

from __future__ import annotations

import argparse
import asyncio
import random
import struct
import sys
import time
from dataclasses import dataclass
from typing import Callable, Dict, List, Optional, Sequence, Tuple

# --------------------------------------------------------------------------
# Protocol constants - keep in step with docs/BLE_PROTOCOL.md and
# firmware/navigator/nav_types.h. If those change, change these.
# --------------------------------------------------------------------------

SERVICE_UUID = "6e400001-b5a3-f393-e0a9-e50e24dcca9e"
CHAR_WRITE_UUID = "6e400002-b5a3-f393-e0a9-e50e24dcca9e"   # central -> ESP32
CHAR_NOTIFY_UUID = "6e400003-b5a3-f393-e0a9-e50e24dcca9e"  # ESP32 -> central

# navigator.ino advertises this. If it changes there, pass --name.
DEFAULT_DEVICE_NAME = "JiffyTrails"

# Packet types
PKT_NAV = 0x01
PKT_STATUS = 0x02
PKT_CALL = 0x03
PKT_MEDIA = 0x04
PKT_TRIP = 0x05
PKT_CONFIG = 0x06
PKT_TRAFFIC = 0x07

PKT_NAMES: Dict[int, str] = {
    PKT_NAV: "NAV",
    PKT_STATUS: "STATUS",
    PKT_CALL: "CALL",
    PKT_MEDIA: "MEDIA",
    PKT_TRIP: "TRIP",
    PKT_CONFIG: "CONFIG",
    PKT_TRAFFIC: "TRAFFIC",
}

# Maneuver codes
MV_UNKNOWN = 0x00
MV_CONTINUE = 0x01
MV_TURN_LEFT = 0x02
MV_TURN_RIGHT = 0x03
MV_SLIGHT_LEFT = 0x04
MV_SLIGHT_RIGHT = 0x05
MV_SHARP_LEFT = 0x06
MV_SHARP_RIGHT = 0x07
MV_KEEP_LEFT = 0x08
MV_KEEP_RIGHT = 0x09
MV_UTURN_LEFT = 0x0A
MV_UTURN_RIGHT = 0x0B
MV_MERGE = 0x0C
MV_FORK_LEFT = 0x0D
MV_FORK_RIGHT = 0x0E
MV_EXIT_LEFT = 0x0F
MV_EXIT_RIGHT = 0x10
MV_ROUNDABOUT = 0x11
MV_FLYOVER = 0x12
MV_UNDERPASS = 0x13
MV_DESTINATION = 0x14
MV_FERRY = 0x15
MV_ROUNDABOUT_EXIT_BASE = 0x20

MV_NAMES: Dict[int, str] = {
    MV_UNKNOWN: "UNKNOWN",
    MV_CONTINUE: "CONTINUE",
    MV_TURN_LEFT: "TURN_LEFT",
    MV_TURN_RIGHT: "TURN_RIGHT",
    MV_SLIGHT_LEFT: "SLIGHT_LEFT",
    MV_SLIGHT_RIGHT: "SLIGHT_RIGHT",
    MV_SHARP_LEFT: "SHARP_LEFT",
    MV_SHARP_RIGHT: "SHARP_RIGHT",
    MV_KEEP_LEFT: "KEEP_LEFT",
    MV_KEEP_RIGHT: "KEEP_RIGHT",
    MV_UTURN_LEFT: "UTURN_LEFT",
    MV_UTURN_RIGHT: "UTURN_RIGHT",
    MV_MERGE: "MERGE",
    MV_FORK_LEFT: "FORK_LEFT",
    MV_FORK_RIGHT: "FORK_RIGHT",
    MV_EXIT_LEFT: "EXIT_LEFT",
    MV_EXIT_RIGHT: "EXIT_RIGHT",
    MV_ROUNDABOUT: "ROUNDABOUT",
    MV_FLYOVER: "FLYOVER",
    MV_UNDERPASS: "UNDERPASS",
    MV_DESTINATION: "DESTINATION",
    MV_FERRY: "FERRY",
}

# NAV flag bits
NAV_ACTIVE = 1 << 0
NAV_REROUTING = 1 << 1
NAV_GPS_WEAK = 1 << 2
NAV_ARRIVED = 1 << 3

FLAG_NAMES: Sequence[Tuple[int, str]] = (
    (NAV_ACTIVE, "nav_active"),
    (NAV_REROUTING, "rerouting"),
    (NAV_GPS_WEAK, "gps_weak"),
    (NAV_ARRIVED, "arrived"),
)

# The fixed part of a NAV payload, before the instruction string:
#   u8 maneuver, u16 dist_m, u8 next_maneuver, u16 next_dist_m,
#   u16 eta_min, u16 remaining_100m, u8 flags
NAV_FIXED_STRUCT = struct.Struct("<BHBHHHB")
NAV_FIXED_LEN = NAV_FIXED_STRUCT.size          # 11
assert NAV_FIXED_LEN == 11

INSTRUCTION_MAX = 64      # firmware buffer, nav_types.h
STALE_MS = 10_000         # firmware watchdog, nav_types.h
MAX_PAYLOAD = 255         # len is a u8


def maneuver_name(code: int) -> str:
    """Human name for a maneuver code, including the reserved roundabout range."""
    if code in MV_NAMES:
        return MV_NAMES[code]
    if MV_ROUNDABOUT_EXIT_BASE <= code <= MV_ROUNDABOUT_EXIT_BASE + 0x0F:
        return "ROUNDABOUT_EXIT_%d" % (code - MV_ROUNDABOUT_EXIT_BASE)
    return "INVALID"


def flags_str(flags: int) -> str:
    """Render a NAV flags byte as 0x01[nav_active]."""
    names = [name for bit, name in FLAG_NAMES if flags & bit]
    unknown = flags & ~(NAV_ACTIVE | NAV_REROUTING | NAV_GPS_WEAK | NAV_ARRIVED)
    if unknown:
        names.append("undefined:0x%02X" % unknown)
    return "0x%02X[%s]" % (flags, ",".join(names) if names else "none")


# --------------------------------------------------------------------------
# Encoding
# --------------------------------------------------------------------------


def frame(pkt_type: int, payload: bytes) -> bytes:
    """Wrap a payload in [type:u8][len:u8]. len is the payload length."""
    if len(payload) > MAX_PAYLOAD:
        raise ValueError(
            "payload is %d bytes; len is a single byte so %d is the maximum. "
            "Shorten the instruction string." % (len(payload), MAX_PAYLOAD)
        )
    return bytes([pkt_type & 0xFF, len(payload)]) + payload


def encode_nav(
    maneuver: int,
    dist_m: int,
    next_maneuver: int = MV_UNKNOWN,
    next_dist_m: int = 0,
    eta_min: int = 0,
    remaining_100m: int = 0,
    flags: int = NAV_ACTIVE,
    instruction: str = "",
) -> bytes:
    """Build a complete PKT_NAV packet.

    The instruction is UTF-8, not NUL terminated - its length is implied by the
    packet length. The firmware's buffer is INSTRUCTION_MAX bytes, so anything
    longer is trimmed here on a UTF-8 character boundary rather than being sent
    as a deliberate overflow. Use --garbage if you want to test the overflow.
    """
    body = instruction.encode("utf-8")
    if len(body) > INSTRUCTION_MAX - 1:
        body = body[: INSTRUCTION_MAX - 1]
        while body and (body[-1] & 0xC0) == 0x80:   # do not split a UTF-8 char
            body = body[:-1]
    payload = NAV_FIXED_STRUCT.pack(
        maneuver & 0xFF,
        dist_m & 0xFFFF,
        next_maneuver & 0xFF,
        next_dist_m & 0xFFFF,
        eta_min & 0xFFFF,
        remaining_100m & 0xFFFF,
        flags & 0xFF,
    ) + body
    return frame(PKT_NAV, payload)


def encode_status(flags: int, phone_battery_pct: int) -> bytes:
    return frame(PKT_STATUS, bytes([flags & 0xFF, phone_battery_pct & 0xFF]))


def encode_call(state: int, name: str) -> bytes:
    return frame(PKT_CALL, bytes([state & 0xFF]) + name.encode("utf-8"))


def encode_media(state: int, title: str, artist: str) -> bytes:
    body = title.encode("utf-8") + b"\x00" + artist.encode("utf-8")
    return frame(PKT_MEDIA, bytes([state & 0xFF]) + body)


def encode_trip(
    distance_m: int, duration_min: int, speed_kmh_x10: int, max_speed_kmh_x10: int
) -> bytes:
    return frame(
        PKT_TRIP,
        struct.pack(
            "<IHHH",
            distance_m & 0xFFFFFFFF,
            duration_min & 0xFFFF,
            speed_kmh_x10 & 0xFFFF,
            max_speed_kmh_x10 & 0xFFFF,
        ),
    )


def encode_config(brightness: int, units: int) -> bytes:
    return frame(PKT_CONFIG, bytes([brightness & 0xFF, units & 0xFF]))


# --------------------------------------------------------------------------
# Decoding - used to print what we just sent, and to prove a hex string means
# what the test plan claims it means.
# --------------------------------------------------------------------------


def hexs(data: bytes) -> str:
    return " ".join("%02X" % b for b in data)


def _safe_text(raw: bytes) -> str:
    try:
        return '"%s"' % raw.decode("utf-8")
    except UnicodeDecodeError:
        return '<%d bytes, not valid UTF-8: %s>' % (len(raw), hexs(raw))


def decode_packet(data: bytes) -> str:
    """Decode a framed packet into one readable line.

    Never raises. Malformed input is described, because describing exactly how
    a packet is malformed is the whole point of --garbage.
    """
    if len(data) == 0:
        return "MALFORMED empty write, 0 bytes"
    if len(data) == 1:
        return "MALFORMED 1 byte (0x%02X) - header needs 2" % data[0]

    ptype, plen = data[0], data[1]
    payload = data[2:]
    name = PKT_NAMES.get(ptype, "UNKNOWN_TYPE(0x%02X)" % ptype)
    notes: List[str] = []

    if len(payload) < plen:
        notes.append(
            "TRUNCATED len=%d but only %d payload bytes present" % (plen, len(payload))
        )
    elif len(payload) > plen:
        notes.append(
            "TRAILING len=%d but %d payload bytes present; %d extra"
            % (plen, len(payload), len(payload) - plen)
        )
    payload = payload[:plen]

    if ptype not in PKT_NAMES:
        notes.append("type not in the protocol table - firmware must ignore it")
        return "%s len=%d %s" % (name, plen, " | ".join(notes))

    body = ""
    if ptype == PKT_NAV:
        if len(payload) < NAV_FIXED_LEN:
            notes.append(
                "NAV payload is %d bytes, needs at least %d for the fixed fields"
                % (len(payload), NAV_FIXED_LEN)
            )
        else:
            (mv, dist, nmv, ndist, eta, rem, flags) = NAV_FIXED_STRUCT.unpack(
                payload[:NAV_FIXED_LEN]
            )
            instr = payload[NAV_FIXED_LEN:]
            body = (
                "maneuver=%s(0x%02X) dist=%d m next=%s(0x%02X)/%d m "
                "eta=%d min remaining=%.1f km flags=%s instr=%s"
                % (
                    maneuver_name(mv), mv, dist,
                    maneuver_name(nmv), nmv, ndist,
                    eta, rem / 10.0, flags_str(flags), _safe_text(instr),
                )
            )
            if maneuver_name(mv) == "INVALID":
                notes.append("maneuver 0x%02X is not a defined code - "
                             "firmware must render '?', never guess" % mv)
            if len(instr) > INSTRUCTION_MAX - 1:
                notes.append(
                    "instruction is %d bytes, firmware buffer is %d - must be "
                    "truncated, not overflowed" % (len(instr), INSTRUCTION_MAX)
                )
    elif ptype == PKT_STATUS:
        if len(payload) < 2:
            notes.append("STATUS needs 2 bytes, got %d" % len(payload))
        else:
            body = "flags=0x%02X phone_battery=%d%%" % (payload[0], payload[1])
    elif ptype == PKT_CALL:
        if len(payload) < 1:
            notes.append("CALL needs at least 1 byte")
        else:
            states = {0: "idle", 1: "ringing", 2: "active"}
            body = "state=%s(%d) name=%s" % (
                states.get(payload[0], "?"), payload[0], _safe_text(payload[1:])
            )
    elif ptype == PKT_MEDIA:
        if len(payload) < 1:
            notes.append("MEDIA needs at least 1 byte")
        else:
            states = {0: "stop", 1: "play", 2: "pause"}
            title, _, artist = payload[1:].partition(b"\x00")
            body = "state=%s(%d) title=%s artist=%s" % (
                states.get(payload[0], "?"), payload[0],
                _safe_text(title), _safe_text(artist),
            )
    elif ptype == PKT_TRIP:
        if len(payload) < 10:
            notes.append("TRIP needs 10 bytes, got %d" % len(payload))
        else:
            dist, dur, spd, mx = struct.unpack("<IHHH", payload[:10])
            body = "distance=%d m duration=%d min speed=%.1f km/h max=%.1f km/h" % (
                dist, dur, spd / 10.0, mx / 10.0
            )
    elif ptype == PKT_CONFIG:
        if len(payload) < 2:
            notes.append("CONFIG needs 2 bytes, got %d" % len(payload))
        else:
            br = "auto" if payload[0] == 0 else "%d%%" % payload[0]
            body = "brightness=%s units=%d" % (br, payload[1])
    elif ptype == PKT_TRAFFIC:
        body = "%d payload bytes (segment list)" % len(payload)

    out = "%s len=%d %s" % (name, plen, body)
    if notes:
        out += "  <<< " + " | ".join(notes)
    return out.rstrip()


def expected_screen(data: bytes) -> Optional[str]:
    """What the display should be showing after this packet.

    Mirrors screenFor() in firmware/navigator/nav_types.h so the operator can
    check the panel against a printed expectation instead of remembering the
    precedence rules. Only meaningful for a well-formed NAV packet.
    """
    if len(data) < 2 + NAV_FIXED_LEN or data[0] != PKT_NAV:
        return None
    if len(data) - 2 < data[1]:
        return None
    mv, dist, _nmv, _nd, _eta, _rem, flags = NAV_FIXED_STRUCT.unpack(
        data[2 : 2 + NAV_FIXED_LEN]
    )
    if not flags & NAV_ACTIVE:
        return "UI_IDLE - clock and trip stats, NEVER a maneuver"
    if flags & NAV_REROUTING:
        return "UI_REROUTING - 'REROUTING', arrow SUPPRESSED"
    extra = "  (+ gps_weak corner warning)" if flags & NAV_GPS_WEAK else ""
    if flags & NAV_ARRIVED:
        extra += "  (+ arrived)"
    if dist < 30:
        return "UI_NAV_NOW - full-screen arrow, inverted colours" + extra
    if dist < 100:
        return "UI_NAV_COMMITTED - full-screen arrow + distance, nothing else" + extra
    if dist <= 500:
        return "UI_NAV_APPROACH - distance large, arrow large, ETA drops off" + extra
    return "UI_NAV_FAR - instruction, medium distance, ETA, remaining km" + extra


# --------------------------------------------------------------------------
# Google Maps data behaviour, from docs/NAV_DATA.md
# --------------------------------------------------------------------------


def quantise(m: int) -> int:
    """Round a distance to the band Google Maps reports it in.

        > 1 km        100 m steps
        1 km - 300 m   50 m steps
        < 300 m        10 m steps

    Rounding to the band - not stepping through it - is why the digits skip at
    speed (290 -> 270 -> 250). Identical to quantise() in
    firmware/ui_mock/ui_mock.ino so the two can be compared directly.
    """
    if m > 1000:
        return (m // 100) * 100
    if m >= 300:
        return (m // 50) * 50
    return (m // 10) * 10


@dataclass(frozen=True)
class Leg:
    """One maneuver of the scripted route."""
    maneuver: int
    instruction: str
    length_m: int
    cruise_kmh: float


# A plausible Bengaluru route. Roads match firmware/ui_mock/ui_mock.ino so the
# simulated ride and the offline mock tell the same story. Leg 3 carries the
# 59-character instruction actually observed in NAV_DATA.md, which is the worst
# case the display has to survive.
ROUTE: Sequence[Leg] = (
    Leg(MV_CONTINUE, "Old Madras Rd", 2400, 55.0),
    Leg(MV_TURN_RIGHT, "TC Palya Main Rd", 620, 40.0),
    Leg(MV_SLIGHT_RIGHT,
        "Slight right at Horamavu Agara Circle onto Horamavu Agara Rd", 480, 35.0),
    Leg(MV_ROUNDABOUT, "Hennur Main Rd", 550, 30.0),
    Leg(MV_TURN_LEFT, "Kammanahalli Main Rd", 430, 35.0),
    Leg(MV_MERGE, "Outer Ring Rd", 900, 60.0),
    Leg(MV_UTURN_LEFT, "Banaswadi Rd", 380, 25.0),
    Leg(MV_DESTINATION, "Arriving", 260, 20.0),
)

# Named single-state screens for --screen. Each is (packet builder, what to look
# for). Held indefinitely at 1 Hz so the panel can be photographed.
ScreenBuilder = Callable[[], bytes]

SCREENS: Dict[str, Tuple[ScreenBuilder, str]] = {
    "far": (
        lambda: encode_nav(MV_CONTINUE, 1200, MV_TURN_RIGHT, 300, 14, 42,
                           NAV_ACTIVE, "Old Madras Rd"),
        "UI_NAV_FAR: 1.2 km, instruction, ETA 14 min, 4.2 km remaining",
    ),
    "approach": (
        lambda: encode_nav(MV_TURN_RIGHT, 350, MV_TURN_LEFT, 120, 11, 32,
                           NAV_ACTIVE, "TC Palya Main Rd"),
        "UI_NAV_APPROACH: 350 m, big distance, big arrow",
    ),
    "committed": (
        lambda: encode_nav(MV_TURN_LEFT, 80, MV_CONTINUE, 400, 9, 24,
                           NAV_ACTIVE, "Kammanahalli Main Rd"),
        "UI_NAV_COMMITTED: 80 m, full-screen arrow and distance, nothing else",
    ),
    "now": (
        lambda: encode_nav(MV_TURN_RIGHT, 20, MV_CONTINUE, 500, 8, 21,
                           NAV_ACTIVE, "TC Palya Main Rd"),
        "UI_NAV_NOW: 20 m, INVERTED colours",
    ),
    "idle": (
        lambda: encode_nav(MV_UNKNOWN, 0, MV_UNKNOWN, 0, 0, 0, 0x00, ""),
        "UI_IDLE: clock and trip stats. No maneuver, no arrow, no leftover text",
    ),
    "rerouting": (
        lambda: encode_nav(MV_TURN_RIGHT, 120, MV_UNKNOWN, 0, 12, 30,
                           NAV_ACTIVE | NAV_REROUTING, "Rerouting"),
        "UI_REROUTING: 'REROUTING', arrow SUPPRESSED even though maneuver=TURN_RIGHT",
    ),
    "gps_weak": (
        lambda: encode_nav(MV_CONTINUE, 500, MV_TURN_LEFT, 200, 10, 28,
                           NAV_ACTIVE | NAV_GPS_WEAK, "Outer Ring Rd"),
        "Normal nav screen plus a SMALL corner warning. Must not take over the screen",
    ),
    "arrived": (
        lambda: encode_nav(MV_DESTINATION, 0, MV_UNKNOWN, 0, 0, 0,
                           NAV_ACTIVE | NAV_ARRIVED, "Arriving"),
        "Arrival state: destination flag, 0 m",
    ),
    "unknown": (
        lambda: encode_nav(MV_UNKNOWN, 240, MV_UNKNOWN, 0, 7, 18,
                           NAV_ACTIVE, "Unnamed road"),
        "Maneuver UNKNOWN must render '?', never a guessed arrow",
    ),
    "longtext": (
        lambda: encode_nav(MV_SLIGHT_RIGHT, 700, MV_UNKNOWN, 0, 16, 51, NAV_ACTIVE,
                           "Slight right at Horamavu Agara Circle onto Horamavu Agara Rd"),
        "59-character instruction. Road name must survive; drop the maneuver "
        "prefix, not the tail",
    ),
    "roundabout": (
        lambda: encode_nav(MV_ROUNDABOUT_EXIT_BASE + 3, 200, MV_UNKNOWN, 0, 9, 22,
                           NAV_ACTIVE, "Hennur Main Rd"),
        "Reserved roundabout-exit code 0x23. Either a roundabout glyph or '?' - "
        "but never a plain turn arrow",
    ),
    "battery": (
        lambda: encode_status(0x00, 42),
        "STATUS packet: phone battery 42%. Should not disturb the nav screen",
    ),
    "trip": (
        lambda: encode_trip(18_420, 47, 342, 786),
        "TRIP packet: 18.42 km, 47 min, 34.2 km/h avg, 78.6 km/h max",
    ),
}

# --------------------------------------------------------------------------
# Malformed packets for --garbage. Each is (label, bytes, what must happen).
# --------------------------------------------------------------------------


def _noise(n: int) -> bytes:
    """n bytes of repeatable pseudo-random rubbish."""
    rng = random.Random(7)
    return bytes(rng.randrange(256) for _ in range(n))


def garbage_cases() -> List[Tuple[str, bytes, str]]:
    good = encode_nav(MV_TURN_RIGHT, 100, MV_TURN_LEFT, 80, 12, 32,
                      NAV_ACTIVE, "Old Madras Rd")
    cases: List[Tuple[str, bytes, str]] = [
        ("empty write", b"",
         "ignored; no crash, no state change"),
        ("header only, 1 byte", b"\x01",
         "ignored; 2 bytes are needed before len can even be read"),
        ("header with no payload", b"\x01\x18",
         "ignored; len claims 24 bytes and none arrived"),
        ("NAV truncated mid-payload", good[:8],
         "ignored; must NOT parse the bytes it did get"),
        ("NAV len larger than payload", bytes([0x01, 0xFF]) + good[2:],
         "ignored; len must be checked against the actual write length"),
        ("NAV len smaller than payload", bytes([0x01, 0x05]) + good[2:],
         "ACCEPTED by this firmware and rendered in full - len is treated as "
         "advisory and reads are bounded by the ATT write length instead. The "
         "safety property under test is that nothing is read past the end of "
         "the write, not which policy is chosen"),
        ("BUILD_PLAN's own buggy example, len=0x0F for a 24-byte payload",
         bytes([0x01, 0x0F]) + good[2:],
         "ACCEPTED and rendered in full, for the same reason. A stricter "
         "peripheral would drop it - which is why the Android app must send "
         "0x18"),
        ("NAV len=0", b"\x01\x00",
         "ignored; a NAV payload is at least 11 bytes"),
        ("NAV fixed fields one byte short",
         bytes([0x01, NAV_FIXED_LEN - 1]) + good[2 : 2 + NAV_FIXED_LEN - 1],
         "ignored; 11 bytes are required before the instruction"),
        ("unknown packet type 0x7F", bytes([0x7F, 0x04, 0xDE, 0xAD, 0xBE, 0xEF]),
         "no screen change - but it SHOULD still feed the stale watchdog, "
         "because freshness is measured in arrivals and the link is "
         "demonstrably alive"),
        ("packet type 0x00", bytes([0x00, 0x02, 0x01, 0x02]),
         "ignored; 0x00 is not a defined type"),
        ("instruction 200 bytes, no terminator",
         frame(PKT_NAV,
               NAV_FIXED_STRUCT.pack(MV_TURN_LEFT, 90, 0, 0, 5, 12, NAV_ACTIVE)
               + b"A" * 200),
         "truncated to %d bytes and still NUL terminated. No stack smash, no "
         "reboot" % INSTRUCTION_MAX),
        ("instruction with invalid UTF-8",
         frame(PKT_NAV,
               NAV_FIXED_STRUCT.pack(MV_TURN_LEFT, 90, 0, 0, 5, 12, NAV_ACTIVE)
               + b"Old \xff\xfe Rd"),
         "rendered as something, or dropped - but not a crash or garbled screen"),
        ("instruction containing an embedded NUL",
         frame(PKT_NAV,
               NAV_FIXED_STRUCT.pack(MV_TURN_LEFT, 90, 0, 0, 5, 12, NAV_ACTIVE)
               + b"Old\x00Madras Rd"),
         "truncated at the NUL at worst; never a buffer overrun"),
        ("maneuver code 0xFF",
         encode_nav(0xFF, 150, MV_UNKNOWN, 0, 6, 15, NAV_ACTIVE, "Mystery Rd"),
         "renders '?' - a confidently wrong arrow is worse than no arrow"),
        ("flags with undefined bits set",
         encode_nav(MV_TURN_LEFT, 150, MV_UNKNOWN, 0, 6, 15, 0xF1, "Old Madras Rd"),
         "bit 0 still honoured, unknown bits ignored, no odd screen"),
        ("dist_m at u16 maximum",
         encode_nav(MV_CONTINUE, 65535, MV_UNKNOWN, 0, 0, 0, NAV_ACTIVE, "Far away"),
         "renders 65535 m or 65.5 km without wrapping or overflowing the field"),
        ("256 bytes of random noise",
         _noise(256),
         "ignored; the parser must not be steerable by noise"),
        ("valid NAV after all of the above", good,
         "ACCEPTED and displayed correctly. This is the real test: the parser "
         "must still work"),
    ]
    return cases


# --------------------------------------------------------------------------
# Printing
# --------------------------------------------------------------------------


class Printer:
    """All console output goes through here so timestamps line up."""

    def __init__(self, show_expect: bool = True) -> None:
        self.show_expect = show_expect
        self.quiet = False       # count packets but do not print them
        self.tx_count = 0
        self.tx_bytes = 0

    @staticmethod
    def _ts() -> str:
        return time.strftime("%H:%M:%S") + ".%03d" % (int(time.time() * 1000) % 1000)

    def info(self, msg: str) -> None:
        print("%s      %s" % (self._ts(), msg), flush=True)

    def rule(self, title: str = "") -> None:
        line = "-" * 72
        if title:
            line = ("--- %s " % title).ljust(72, "-")
        print(line, flush=True)

    def tx(self, data: bytes, note: str = "") -> None:
        self.tx_count += 1
        self.tx_bytes += len(data)
        if self.quiet:
            return
        print("%s TX %3dB  %s" % (self._ts(), len(data), hexs(data)), flush=True)
        print("%s          %s" % (" " * 12, decode_packet(data)), flush=True)
        if note:
            print("%s          EXPECT: %s" % (" " * 12, note), flush=True)
        elif self.show_expect:
            screen = expected_screen(data)
            if screen:
                print("%s          EXPECT: %s" % (" " * 12, screen), flush=True)

    def rx(self, data: bytes) -> None:
        print("%s RX %3dB  %s" % (self._ts(), len(data), hexs(data)), flush=True)
        try:
            text = data.decode("utf-8").strip()
        except UnicodeDecodeError:
            text = ""
        if text and text.isprintable():
            print("%s          notify text: %r" % (" " * 12, text), flush=True)
        else:
            print("%s          %s" % (" " * 12, decode_packet(bytes(data))), flush=True)


# --------------------------------------------------------------------------
# BLE link
# --------------------------------------------------------------------------


def _import_bleak():
    """Import bleak with an error a non-Python-developer can act on."""
    try:
        from bleak import BleakClient, BleakScanner            # noqa: F401
        from bleak.exc import BleakError                       # noqa: F401
    except ImportError:
        sys.stderr.write(
            "\nERROR: the 'bleak' package is not installed.\n\n"
            "  Fix: open PowerShell and run\n"
            "      py -m pip install bleak\n\n"
            "  If 'py' is not recognised, install Python 3.9 or newer from\n"
            "  python.org and tick 'Add python.exe to PATH' during setup.\n\n"
        )
        raise SystemExit(2)
    import bleak
    return bleak


class Link:
    """A connected navigator, or a clear explanation of why there isn't one."""

    def __init__(self, printer: Printer, args: argparse.Namespace) -> None:
        self.p = printer
        self.args = args
        self.client = None            # type: ignore[assignment]
        self.write_uuid = CHAR_WRITE_UUID
        self.write_response = bool(args.with_response)
        self._disconnected = asyncio.Event()

    # ---------------------------------------------------------------- scan

    async def find_device(self):
        _import_bleak()
        from bleak import BleakScanner
        from bleak.exc import BleakError

        target = self.args.address or self.args.name
        self.p.info("Scanning %.0f s for %r ..." % (self.args.scan_timeout, target))
        try:
            devices = await BleakScanner.discover(timeout=self.args.scan_timeout)
        except BleakError as exc:
            raise SystemExit(
                "\nERROR: the Bluetooth scan failed: %s\n\n"
                "  Check, in this order:\n"
                "   1. Bluetooth is switched ON  (Settings > Bluetooth & devices)\n"
                "   2. The laptop actually has Bluetooth LE - most do since 2015\n"
                "   3. No other app is holding the adapter (close nRF Connect for\n"
                "      Desktop, or any BLE tool that is scanning)\n" % exc
            )
        except OSError as exc:
            raise SystemExit(
                "\nERROR: Windows refused access to the Bluetooth radio: %s\n\n"
                "  Turn Bluetooth on, then run this again. If it is already on,\n"
                "  toggle it off and on once - the Windows BLE stack gets stuck.\n"
                % exc
            )

        if self.args.address:
            wanted = self.args.address.lower().replace("-", ":")
            for d in devices:
                if d.address.lower().replace("-", ":") == wanted:
                    return d
        else:
            wanted = self.args.name.lower()
            for d in devices:
                if d.name and wanted in d.name.lower():
                    return d

        named = sorted(
            "  %s  %s" % (d.address, d.name or "(no name)")
            for d in devices if d.name
        )
        listing = "\n".join(named) if named else "  (nothing advertising a name)"
        raise SystemExit(
            "\nERROR: no BLE device matching %r was found in %.0f seconds.\n\n"
            "  Devices seen:\n%s\n\n"
            "  Check, in this order:\n"
            "   1. The ESP32 is powered and its serial monitor shows it advertising\n"
            "   2. The name matches. The firmware chooses it in the bleBegin()\n"
            "      call in navigator.ino. If it advertises as something else, pass\n"
            "        --name <that name>\n"
            "      or use the address from the list above with --address\n"
            "   3. Nothing else is already connected to it. A BLE peripheral\n"
            "      accepts one central at a time - close nRF Connect on the phone\n"
            "   4. Windows has NOT paired with it. This protocol needs no pairing;\n"
            "      if it appears under Settings > Bluetooth, remove the device\n"
            % (target, self.args.scan_timeout, listing)
        )

    # ------------------------------------------------------------- connect

    async def connect(self) -> None:
        _import_bleak()
        from bleak import BleakClient
        from bleak.exc import BleakError

        device = await self.find_device()
        self.p.info("Found %s (%s). Connecting ..." % (device.name, device.address))

        def on_disconnect(_client) -> None:
            self.p.info("*** BLE DISCONNECTED - the display must show "
                        "'PHONE DISCONNECTED' ***")
            self._disconnected.set()

        self.client = BleakClient(device, disconnected_callback=on_disconnect,
                                  timeout=self.args.connect_timeout)
        try:
            await self.client.connect()
        except BleakError as exc:
            raise SystemExit(
                "\nERROR: connect failed: %s\n\n"
                "  Usually one of:\n"
                "   - something else is already connected to the ESP32\n"
                "   - the ESP32 rebooted mid-connect; watch its serial output\n"
                "   - Windows cached a stale pairing. Settings > Bluetooth &\n"
                "     devices > find it > Remove device, then retry\n" % exc
            )
        except asyncio.TimeoutError:
            raise SystemExit(
                "\nERROR: connect timed out after %.0f s.\n\n"
                "  Move the laptop within a couple of metres of the ESP32 and\n"
                "  try again. If it still fails, power-cycle the ESP32.\n"
                % self.args.connect_timeout
            )

        self._disconnected.clear()
        await self._check_services()
        try:
            self.p.info("Negotiated MTU: %d bytes "
                        "(the protocol asks for 185)" % self.client.mtu_size)
        except Exception:
            pass
        await self._subscribe()

    async def _check_services(self) -> None:
        """Confirm the Nordic UART-style service and characteristics are there."""
        client = self.client
        assert client is not None
        try:
            services = client.services
            if services is None and hasattr(client, "get_services"):
                services = await client.get_services()   # bleak < 0.21
        except Exception as exc:                                # pragma: no cover
            raise SystemExit("ERROR: service discovery failed: %s" % exc)

        svc = services.get_service(SERVICE_UUID)
        if svc is None:
            # The collection is iterable on current bleak; fall back to the
            # underlying dict on older releases.
            try:
                all_services = list(services)
            except TypeError:                                   # pragma: no cover
                all_services = list(services.services.values())
            found = "\n".join("  %s" % s.uuid for s in all_services)
            raise SystemExit(
                "\nERROR: connected, but the navigator service was not found.\n\n"
                "  Expected: %s\n"
                "  The device is advertising these services instead:\n%s\n\n"
                "  This means the ESP32 firmware is not the navigator build, or\n"
                "  the UUIDs in ble.cpp do not match docs/BLE_PROTOCOL.md.\n"
                % (SERVICE_UUID, found or "  (none)")
            )

        write_char = None
        notify_char = None
        for ch in svc.characteristics:
            if ch.uuid.lower() == CHAR_WRITE_UUID:
                write_char = ch
            elif ch.uuid.lower() == CHAR_NOTIFY_UUID:
                notify_char = ch

        if write_char is None:
            raise SystemExit(
                "\nERROR: the service exists but the write characteristic\n"
                "  %s is missing. The firmware must expose it with WRITE or\n"
                "  WRITE_NO_RESPONSE. Check ble.cpp.\n" % CHAR_WRITE_UUID
            )

        props = list(write_char.properties)
        self.p.info("Write characteristic properties: %s" % ", ".join(props))
        if not self.args.with_response:
            # Prefer write-without-response: that is what a phone streaming at
            # 1 Hz will do, and it is the path most likely to expose tearing.
            self.write_response = "write-without-response" not in props
        if self.write_response and "write" not in props:
            raise SystemExit(
                "\nERROR: --with-response was requested but the characteristic\n"
                "  does not support acknowledged writes (properties: %s).\n"
                "  Drop --with-response.\n" % ", ".join(props)
            )
        self.p.info("Writing %s response."
                    % ("WITH" if self.write_response else "WITHOUT"))

        if notify_char is None:
            self.p.info("WARNING: notify characteristic %s not found. The ESP32 "
                        "cannot talk back; --ride will still work."
                        % CHAR_NOTIFY_UUID)
        self._notify_present = notify_char is not None

    async def _subscribe(self) -> None:
        if not getattr(self, "_notify_present", False):
            return
        client = self.client
        assert client is not None

        def handler(_sender, data: bytearray) -> None:
            self.p.rx(bytes(data))

        try:
            await client.start_notify(CHAR_NOTIFY_UUID, handler)
            self.p.info("Subscribed to notifications on %s" % CHAR_NOTIFY_UUID)
        except Exception as exc:
            self.p.info("WARNING: could not subscribe to notifications: %s" % exc)

    # --------------------------------------------------------------- write

    @property
    def connected(self) -> bool:
        return self.client is not None and self.client.is_connected

    async def reattach(self) -> bool:
        """Rescan and reconnect after the link drops.

        This is the laptop half of the walk-30-m-away test. Nothing here needs
        a keypress, so if it recovers, recovery really was unaided.
        """
        started = time.monotonic()
        self.p.rule("LINK LOST - reconnecting")
        self.p.info("The ESP32 must be re-advertising on its own. No button is "
                    "pressed at either end.")
        attempt = 0
        while time.monotonic() - started < self.args.reconnect_timeout:
            attempt += 1
            try:
                await self.connect()
            except SystemExit as exc:
                lines = [ln for ln in str(exc).splitlines() if ln.strip()]
                self.p.info("Attempt %d: %s"
                            % (attempt, lines[0] if lines else "not found yet"))
                await asyncio.sleep(1.0)
                continue
            except Exception as exc:                            # pragma: no cover
                self.p.info("Attempt %d failed: %s" % (attempt, exc))
                await asyncio.sleep(1.0)
                continue
            took = time.monotonic() - started
            self.p.rule("RECONNECTED in %.1f s" % took)
            if took <= 10.0:
                self.p.info("PASS: within the 10 s the Stage 5 gate requires.")
            else:
                self.p.info("FAIL: took longer than 10 s. Check the ESP32 "
                            "restarts advertising in its disconnect callback.")
            return True
        self.p.info("FAIL: no reconnection within %.0f s."
                    % self.args.reconnect_timeout)
        return False

    async def send(self, data: bytes, note: str = "") -> bool:
        """Write one packet. Returns False if the link has gone for good."""
        self.p.tx(data, note)
        if self.args.dry_run:
            return True
        for attempt in (1, 2):
            client = self.client
            if client is None or not client.is_connected:
                if self.args.reconnect and attempt == 1:
                    if await self.reattach():
                        continue
                self.p.info("Link is down - packet not sent.")
                return False
            from bleak.exc import BleakError
            try:
                await client.write_gatt_char(
                    self.write_uuid, data, response=self.write_response
                )
                return True
            except BleakError as exc:
                self.p.info("Write failed: %s" % exc)
                if self.args.reconnect and attempt == 1:
                    if await self.reattach():
                        continue
                return False
            except Exception as exc:                            # pragma: no cover
                self.p.info("Write failed: %s" % exc)
                return False
        return False

    async def close(self) -> None:
        if self.args.dry_run or self.client is None:
            return
        try:
            if self.client.is_connected:
                await self.client.disconnect()
        except Exception:
            pass


# --------------------------------------------------------------------------
# Modes
# --------------------------------------------------------------------------


async def mode_scan(args: argparse.Namespace, p: Printer) -> int:
    _import_bleak()
    from bleak import BleakScanner

    p.info("Scanning %.0f s for anything advertising ..." % args.scan_timeout)
    devices = await BleakScanner.discover(timeout=args.scan_timeout)
    if not devices:
        p.info("Nothing found. Bluetooth on? ESP32 powered and advertising?")
        return 1
    p.rule("devices seen")
    for d in sorted(devices, key=lambda x: (x.name or "~", x.address)):
        mark = ""
        if d.name and args.name.lower() in d.name.lower():
            mark = "   <-- matches --name %s" % args.name
        print("  %-20s  %s%s" % (d.address, d.name or "(no name)", mark))
    p.rule()
    p.info("Use --name <name> or --address <addr> with the other modes.")
    return 0


async def mode_ride(link: Link, args: argparse.Namespace, p: Printer) -> int:
    """Replay a scripted route at 1 Hz with the real Maps data behaviour."""
    rng = random.Random(args.seed)
    period = 1.0 / args.rate

    total_route_m = sum(leg.length_m for leg in ROUTE)
    p.rule("RIDE")
    p.info("%d legs, %.1f km, sending at %.1f Hz. Speed multiplier %.1fx."
           % (len(ROUTE), total_route_m / 1000.0, args.rate, args.speed_mult))
    p.info("Distances are QUANTISED per NAV_DATA.md - the digits are supposed "
           "to skip. That is not a bug in the firmware.")
    p.info("Ctrl+C to stop. Navigation always ends with explicit nav_active=0.")
    p.rule()

    # Scheduled events, so a reviewer sees the awkward states without waiting
    # for them to happen by chance.
    reroute_leg, reroute_at_m, reroute_ticks = 3, 200, 4      # missed turn
    gpsweak_leg, gpsweak_at_m, gpsweak_ticks = 5, 500, 8      # underpass
    reroute_left = 0
    gpsweak_left = 0
    reroute_done = False
    gpsweak_done = False

    tick = 0
    for index, leg in enumerate(ROUTE):
        dist_m = float(leg.length_m)
        legs_after = sum(l.length_m for l in ROUTE[index + 1 :])

        while dist_m > 0:
            # --- flags ------------------------------------------------
            flags = NAV_ACTIVE
            if (not reroute_done and index == reroute_leg
                    and dist_m <= reroute_at_m and reroute_left == 0):
                reroute_left = reroute_ticks
            if reroute_left > 0:
                flags |= NAV_REROUTING
                reroute_left -= 1
                if reroute_left == 0:
                    reroute_done = True

            if (not gpsweak_done and index == gpsweak_leg
                    and dist_m <= gpsweak_at_m and gpsweak_left == 0):
                gpsweak_left = gpsweak_ticks
            if gpsweak_left > 0:
                flags |= NAV_GPS_WEAK
                gpsweak_left -= 1
                if gpsweak_left == 0:
                    gpsweak_done = True

            # --- distances --------------------------------------------
            shown = quantise(int(dist_m))

            # NAV_DATA.md rule 3: progressMax drifts as Maps re-estimates, so
            # remaining distance is recomputed every packet and never cached.
            remaining_m = shown + legs_after
            drift = 1.0 + rng.uniform(-0.03, 0.03)
            remaining_100m = max(0, int(round(remaining_m * drift / 100.0)))

            speed_kmh = max(8.0, leg.cruise_kmh)
            eta_min = max(1, int(round((remaining_m * drift / 1000.0)
                                       / max(12.0, speed_kmh * 0.62) * 60.0)))

            # next_maneuver is reserved - Maps does not expose it (NAV_DATA.md).
            # Sent as UNKNOWN/0 so the firmware is tested against reality, not
            # against a field it will never receive.
            pkt = encode_nav(
                maneuver=leg.maneuver,
                dist_m=shown,
                next_maneuver=MV_UNKNOWN,
                next_dist_m=0,
                eta_min=eta_min,
                remaining_100m=remaining_100m,
                flags=flags,
                instruction="Rerouting" if flags & NAV_REROUTING else leg.instruction,
            )
            note = ""
            if flags & NAV_REROUTING:
                note = ("UI_REROUTING - 'REROUTING' and NO ARROW, even though "
                        "maneuver is still %s" % maneuver_name(leg.maneuver))
            if not await link.send(pkt, note):
                p.info("Link lost during the ride.")
                return 1

            # A phone sends STATUS occasionally; interleave it so the firmware
            # is exercised on a mixed stream, not a NAV-only one.
            tick += 1
            if tick % 30 == 0:
                await link.send(encode_status(0x00, max(5, 96 - tick // 30 * 3)))

            await asyncio.sleep(period)

            # --- advance ----------------------------------------------
            # A little jitter plus deceleration into the maneuver, so quantised
            # values skip irregularly the way real ones do.
            approach = 0.45 if dist_m < 120 else (0.75 if dist_m < 300 else 1.0)
            step = (speed_kmh / 3.6) * approach * args.speed_mult
            step *= 1.0 + rng.uniform(-0.15, 0.15)
            if flags & NAV_REROUTING:
                step *= 0.5
            dist_m -= step

        p.info("--- reached %s (%s) ---"
               % (leg.instruction, maneuver_name(leg.maneuver)))

    # Arrival, then the explicit end. Silence is ambiguous; nav_active=0 is not.
    p.rule("ARRIVAL")
    for _ in range(5):
        await link.send(encode_nav(MV_DESTINATION, 0, MV_UNKNOWN, 0, 0, 0,
                                   NAV_ACTIVE | NAV_ARRIVED, "Arriving"))
        await asyncio.sleep(period)

    p.rule("NAVIGATION ENDED")
    p.info("Sending nav_active=0. The display must drop to the idle screen "
           "immediately and must NOT keep the last maneuver.")
    for _ in range(8):
        await link.send(encode_nav(MV_UNKNOWN, 0, MV_UNKNOWN, 0, 0, 0, 0x00, ""),
                        "UI_IDLE - clock and trip. If an arrow or a road name "
                        "is still on screen, that is a FAILURE.")
        await asyncio.sleep(period)

    p.info("Ride complete. %d packets, %d bytes." % (p.tx_count, p.tx_bytes))
    return 0


async def mode_screen(link: Link, args: argparse.Namespace, p: Printer) -> int:
    name = args.screen.lower()
    if name not in SCREENS:
        raise SystemExit(
            "\nERROR: unknown screen %r.\n\n  Available:\n%s\n"
            % (args.screen,
               "\n".join("    %-12s %s" % (k, v[1]) for k, v in SCREENS.items()))
        )
    builder, description = SCREENS[name]
    p.rule("SCREEN: %s" % name)
    p.info(description)
    p.info("Held at %.1f Hz so the watchdog stays quiet. Photograph the panel "
           "at arm's length. Ctrl+C to stop." % args.rate)
    p.rule()
    period = 1.0 / args.rate
    while True:
        if not await link.send(builder(), description):
            return 1
        await asyncio.sleep(period)


async def mode_stale(link: Link, args: argparse.Namespace, p: Printer) -> int:
    """Send normally, then stop dead. Proves the 10 s watchdog fires."""
    period = 1.0 / args.rate
    warmup = args.stale_warmup
    p.rule("STALE WATCHDOG")
    p.info("Sending normally for %d s, then stopping while staying CONNECTED."
           % warmup)
    p.info("The link stays up, so 'PHONE DISCONNECTED' would be the wrong "
           "screen. Expect 'STALE' and a dimmed panel.")
    p.rule()

    for i in range(int(warmup * args.rate)):
        pkt = encode_nav(MV_TURN_RIGHT, 350 - (i % 5) * 10, MV_UNKNOWN, 0,
                         11, 32, NAV_ACTIVE, "TC Palya Main Rd")
        if not await link.send(pkt):
            return 1
        await asyncio.sleep(period)

    stopped = time.monotonic()
    p.rule("PACKETS STOPPED")
    p.info("Nothing more will be sent. STALE_MS is %d ms." % STALE_MS)
    p.info("Watch the panel and the ESP32 serial output. Note the time the "
           "screen changes.")

    deadline = args.stale_hold
    reported = False
    while time.monotonic() - stopped < deadline:
        await asyncio.sleep(1.0)
        elapsed = time.monotonic() - stopped
        p.info("+%2d s  (link is %s)"
               % (round(elapsed), "up" if link.connected else "DOWN"))
        if not reported and elapsed >= STALE_MS / 1000.0:
            p.info("^^ the watchdog SHOULD have fired by now. If a maneuver is "
                   "still on screen, that is a FAILURE. If the screen says "
                   "'PHONE DISCONNECTED' rather than 'STALE', the firmware is "
                   "confusing a dead link with dead data - also a failure.")
            reported = True

    p.rule("RESUMING")
    p.info("Sending again. The display must return to the nav screen within "
           "one packet - no reboot, no button press.")
    for _ in range(10):
        if not await link.send(encode_nav(MV_TURN_RIGHT, 200, MV_UNKNOWN, 0,
                                          9, 28, NAV_ACTIVE,
                                          "TC Palya Main Rd")):
            return 1
        await asyncio.sleep(period)
    return 0


async def mode_flood(link: Link, args: argparse.Namespace, p: Printer) -> int:
    """Send far faster than 1 Hz, looking for tearing and heap growth."""
    hz = args.flood_rate
    seconds = args.flood_seconds
    p.rule("FLOOD")
    p.info("Sending at %.0f Hz for %d s - roughly %dx the real rate."
           % (hz, seconds, int(hz)))
    p.info("Watching for: torn or flickering digits, a partially drawn arrow, "
           "a watchdog reset, and free-heap drift in the ESP32 serial output.")
    p.info("Note the free heap NOW and again at the end. A few hundred bytes "
           "of jitter is fine; a steady downward slope is a leak.")
    p.rule()

    period = 1.0 / hz
    sent = 0
    started = time.monotonic()
    # Values change on every packet, so any redraw skipping shows up rather
    # than being hidden by an unchanged frame.
    p.show_expect = False
    every = max(1, int(round(hz)))          # print roughly one line per second
    while time.monotonic() - started < seconds:
        d = 500 - (sent % 470)
        pkt = encode_nav(MV_TURN_LEFT if sent % 2 else MV_TURN_RIGHT,
                         d, MV_UNKNOWN, 0, 9, 24, NAV_ACTIVE,
                         "Kammanahalli Main Rd" if sent % 2 else "Outer Ring Rd")
        # Every packet is sent; only one in `every` is printed, or the console
        # becomes the bottleneck instead of the ESP32.
        p.quiet = not (sent < 5 or sent % every == 0)
        ok = await link.send(pkt)
        p.quiet = False
        if not ok:
            p.info("Link failed after %d packets - that is itself a result." % sent)
            return 1
        sent += 1
        await asyncio.sleep(period)

    p.show_expect = True
    elapsed = time.monotonic() - started
    p.rule("FLOOD DONE")
    p.info("%d packets in %.1f s (%.1f Hz actual)." % (sent, elapsed, sent / elapsed))
    p.info("Now settling back to 1 Hz. The display must recover to a clean, "
           "steady screen with no leftover artefacts.")
    for _ in range(10):
        if not await link.send(encode_nav(MV_TURN_RIGHT, 250, MV_UNKNOWN, 0,
                                          10, 30, NAV_ACTIVE,
                                          "TC Palya Main Rd")):
            return 1
        await asyncio.sleep(1.0)
    p.info("Check the ESP32's free heap against the value you noted. If it has "
           "dropped by more than a kilobyte, look for an allocation in the "
           "packet handler.")
    return 0


async def mode_garbage(link: Link, args: argparse.Namespace, p: Printer) -> int:
    """Malformed packets. The firmware must reject each one and stay usable."""
    cases = garbage_cases()
    p.rule("GARBAGE")
    p.info("%d malformed packets, %.1f s apart. Between each one the display "
           "must NOT change, must NOT flicker, and the ESP32 must NOT reboot."
           % (len(cases), args.garbage_delay))
    p.info("Watch the serial output for a rejection message per packet, and "
           "watch the free heap for growth.")
    p.rule()

    # Establish a known-good screen first, so any change is visible.
    good = encode_nav(MV_TURN_RIGHT, 100, MV_TURN_LEFT, 80, 12, 32,
                      NAV_ACTIVE, "Old Madras Rd")
    p.info("Baseline: a valid packet. Note exactly what is on screen.")
    if not await link.send(good):
        return 1
    await asyncio.sleep(2.0)

    for i, (label, data, expect) in enumerate(cases, 1):
        p.rule("%d/%d  %s" % (i, len(cases), label))
        if not await link.send(data, expect):
            p.info("Link dropped on case %d (%s). That is a FAILURE: malformed "
                   "input must not kill the connection." % (i, label))
            return 1
        await asyncio.sleep(args.garbage_delay)

    p.rule("GARBAGE DONE")
    p.info("If the final valid packet rendered correctly and the ESP32 never "
           "rebooted, the parser passes.")
    return 0


def mode_nrf(p: Printer) -> int:
    """Print hex strings for nRF Connect. No BLE, no laptop dependency."""
    p.rule("nRF Connect hex strings")
    print("Paste into the write characteristic %s\n" % CHAR_WRITE_UUID)

    entries: List[Tuple[str, bytes]] = [
        ("Normal NAV - TURN_RIGHT 100 m, 'Old Madras Rd' "
         "(the BUILD_PLAN worked example, corrected)",
         encode_nav(MV_TURN_RIGHT, 100, MV_TURN_LEFT, 80, 12, 32,
                    NAV_ACTIVE, "Old Madras Rd")),
        ("Under 30 m - inverted screen",
         encode_nav(MV_TURN_RIGHT, 20, MV_UNKNOWN, 0, 8, 21,
                    NAV_ACTIVE, "TC Palya Main Rd")),
        ("Rerouting - arrow must be suppressed",
         encode_nav(MV_TURN_RIGHT, 120, MV_UNKNOWN, 0, 12, 30,
                    NAV_ACTIVE | NAV_REROUTING, "Rerouting")),
        ("nav_active = 0 - idle screen, never a maneuver",
         encode_nav(MV_UNKNOWN, 0, MV_UNKNOWN, 0, 0, 0, 0x00, "")),
        ("gps_weak - small corner warning only",
         encode_nav(MV_CONTINUE, 500, MV_UNKNOWN, 0, 10, 28,
                    NAV_ACTIVE | NAV_GPS_WEAK, "Outer Ring Rd")),
        ("Unknown maneuver - must render '?'",
         encode_nav(MV_UNKNOWN, 240, MV_UNKNOWN, 0, 7, 18,
                    NAV_ACTIVE, "Unnamed road")),
        ("Malformed - len says 24, only 11 payload bytes sent",
         bytes([0x01, 0x18, 0x03, 0x64, 0x00, 0x02, 0x50, 0x00,
                0x0C, 0x00, 0x20, 0x00, 0x01])),
        ("Malformed - unknown packet type 0x7F",
         bytes([0x7F, 0x04, 0xDE, 0xAD, 0xBE, 0xEF])),
        ("STATUS - phone battery 42%", encode_status(0x00, 42)),
    ]
    for label, data in entries:
        print("%s" % label)
        print("  %s" % hexs(data))
        print("  -> %s" % decode_packet(data))
        screen = expected_screen(data)
        if screen:
            print("  -> %s" % screen)
        print()
    return 0


def mode_selftest(p: Printer) -> int:
    """Encode/decode round trip, and check the BUILD_PLAN example by hand."""
    p.rule("SELF TEST - no hardware needed")
    failures = 0

    def check(label: str, ok: bool, detail: str = "") -> None:
        nonlocal failures
        print("  [%s] %s%s" % ("PASS" if ok else "FAIL", label,
                               ("  - " + detail) if detail else ""))
        if not ok:
            failures += 1

    check("NAV fixed fields are 11 bytes", NAV_FIXED_LEN == 11,
          "got %d" % NAV_FIXED_LEN)

    pkt = encode_nav(MV_TURN_RIGHT, 100, MV_TURN_LEFT, 80, 12, 32,
                     NAV_ACTIVE, "Old Madras Rd")
    check("worked example encodes to 26 bytes", len(pkt) == 26,
          "got %d" % len(pkt))
    check("worked example declares len=0x18 (24)", pkt[1] == 24,
          "got 0x%02X" % pkt[1])
    check("body bytes match BUILD_PLAN",
          pkt[2:13] == bytes([0x03, 0x64, 0x00, 0x02, 0x50, 0x00,
                              0x0C, 0x00, 0x20, 0x00, 0x01]),
          hexs(pkt[2:13]))
    check("instruction round-trips",
          pkt[13:] == "Old Madras Rd".encode("utf-8"))

    print()
    print("  BUILD_PLAN.md Stage 5 prints this string:")
    print("      01 0F 03 64 00 02 50 00 0C 00 20 00 01 + \"Old Madras Rd\"")
    print("  Field order and every value in it are CORRECT. The length byte is")
    print("  NOT. 0x0F = 15, but the payload is 11 fixed bytes + 13 instruction")
    print("  bytes = 24 = 0x18. Corrected:")
    print("      %s" % hexs(pkt))
    print("      -> %s" % decode_packet(pkt))
    print()

    bad = bytes([0x01, 0x0F, 0x03, 0x64, 0x00, 0x02, 0x50, 0x00,
                 0x0C, 0x00, 0x20, 0x00, 0x01]) + b"Old Madras Rd"
    print("  What the uncorrected string decodes to:")
    print("      %s" % decode_packet(bad))
    print()

    for label, data, _ in garbage_cases():
        try:
            decode_packet(data)
        except Exception as exc:                                # pragma: no cover
            check("decoder survives %r" % label, False, str(exc))
    check("decoder survives every garbage case", True)

    for m, want in ((3450, 3400), (1001, 1000), (1000, 1000), (950, 950),
                    (949, 900), (301, 300), (299, 290), (29, 20), (9, 0)):
        got = quantise(m)
        check("quantise(%d) == %d" % (m, want), got == want, "got %d" % got)

    for name, (builder, _) in SCREENS.items():
        data = builder()
        check("screen %r encodes cleanly" % name, len(data) >= 2)

    print()
    p.rule("%d failure(s)" % failures)
    return 1 if failures else 0


# --------------------------------------------------------------------------
# Entry point
# --------------------------------------------------------------------------


def build_parser() -> argparse.ArgumentParser:
    ap = argparse.ArgumentParser(
        prog="navsim.py",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        description=(
            "Stand in for the Android app: connect to the ESP32 navigator over "
            "BLE and write protocol packets, printing each as hex plus its "
            "decoded meaning."
        ),
        epilog=(
            "Examples:\n"
            "  py navsim.py --scan                     what is advertising nearby\n"
            "  py navsim.py --selftest                 check encoding, no hardware\n"
            "  py navsim.py --nrf                      hex strings for nRF Connect\n"
            "  py navsim.py --ride                     full scripted route at 1 Hz\n"
            "  py navsim.py --screen now               hold the <30 m screen\n"
            "  py navsim.py --stale                    prove the 10 s watchdog\n"
            "  py navsim.py --flood                    20 Hz, look for tearing\n"
            "  py navsim.py --garbage                  malformed packets\n"
            "  py navsim.py --ride --reconnect         survive a walk out of range\n"
            "  py navsim.py --ride --dry-run           print packets, send nothing\n"
        ),
    )
    mode = ap.add_mutually_exclusive_group(required=True)
    mode.add_argument("--ride", action="store_true",
                      help="replay a scripted Bengaluru route at 1 Hz")
    mode.add_argument("--screen", metavar="NAME",
                      help="hold one state so it can be photographed. "
                           "Names: " + ", ".join(SCREENS))
    mode.add_argument("--stale", action="store_true",
                      help="send, then stop, to prove the 10 s watchdog fires")
    mode.add_argument("--flood", action="store_true",
                      help="send far faster than 1 Hz to check for tearing "
                           "and heap growth")
    mode.add_argument("--garbage", action="store_true",
                      help="send malformed and truncated packets")
    mode.add_argument("--scan", action="store_true",
                      help="list nearby BLE devices and exit")
    mode.add_argument("--nrf", action="store_true",
                      help="print hex strings to paste into nRF Connect; "
                           "no Bluetooth used")
    mode.add_argument("--selftest", action="store_true",
                      help="verify encoding and decoding offline; "
                           "no Bluetooth used")

    conn = ap.add_argument_group("connection")
    conn.add_argument("--name", default=DEFAULT_DEVICE_NAME,
                      help="advertised name to match, case-insensitive "
                           "substring (default: %(default)s)")
    conn.add_argument("--address", default=None,
                      help="connect by BLE address instead of name")
    conn.add_argument("--scan-timeout", type=float, default=10.0,
                      metavar="SEC", help="scan duration (default: %(default)s)")
    conn.add_argument("--connect-timeout", type=float, default=20.0,
                      metavar="SEC", help="connect timeout (default: %(default)s)")
    conn.add_argument("--with-response", action="store_true",
                      help="use acknowledged writes; the default picks "
                           "write-without-response when the firmware offers it")
    conn.add_argument("--dry-run", action="store_true",
                      help="do everything except touch Bluetooth - prints the "
                           "packets a mode would send")
    conn.add_argument("--reconnect", action="store_true",
                      help="rescan and reconnect automatically if the link "
                           "drops, timing the recovery. This is the laptop "
                           "half of the walk-30-m-away test")
    conn.add_argument("--reconnect-timeout", type=float, default=60.0,
                      metavar="SEC",
                      help="give up reconnecting after this long "
                           "(default: %(default)s)")

    tune = ap.add_argument_group("tuning")
    tune.add_argument("--rate", type=float, default=1.0, metavar="HZ",
                      help="packet rate for --ride/--screen/--stale "
                           "(default: %(default)s, which is what Maps does)")
    tune.add_argument("--speed-mult", type=float, default=1.0, metavar="X",
                      help="ride speed multiplier. 1.0 is realistic (~10 min); "
                           "4.0 compresses the route and makes the digits skip "
                           "harder (default: %(default)s)")
    tune.add_argument("--seed", type=int, default=20260826,
                      help="RNG seed, so a run can be repeated exactly")
    tune.add_argument("--stale-warmup", type=float, default=10.0, metavar="SEC",
                      help="seconds of normal traffic before going quiet")
    tune.add_argument("--stale-hold", type=float, default=25.0, metavar="SEC",
                      help="seconds of silence to hold (default: %(default)s)")
    tune.add_argument("--flood-rate", type=float, default=20.0, metavar="HZ",
                      help="packets per second in --flood (default: %(default)s)")
    tune.add_argument("--flood-seconds", type=float, default=30.0, metavar="SEC",
                      help="duration of --flood (default: %(default)s)")
    tune.add_argument("--garbage-delay", type=float, default=1.5, metavar="SEC",
                      help="pause between malformed packets")
    return ap


async def run(args: argparse.Namespace, p: Printer) -> int:
    if args.scan:
        return await mode_scan(args, p)

    link = Link(p, args)
    if args.dry_run:
        p.info("DRY RUN - no Bluetooth will be used. Packets are printed only.")
    else:
        await link.connect()
        p.info("Connected. The display should leave 'PHONE DISCONNECTED'.")

    try:
        if args.ride:
            return await mode_ride(link, args, p)
        if args.screen:
            return await mode_screen(link, args, p)
        if args.stale:
            return await mode_stale(link, args, p)
        if args.flood:
            return await mode_flood(link, args, p)
        if args.garbage:
            return await mode_garbage(link, args, p)
        return 2
    finally:
        await link.close()


def main(argv: Optional[Sequence[str]] = None) -> int:
    args = build_parser().parse_args(argv)
    p = Printer()

    if sys.version_info < (3, 9):
        sys.stderr.write(
            "ERROR: this needs Python 3.9 or newer; you are running %d.%d.\n"
            "  Install a current Python from python.org and run it with 'py'.\n"
            % sys.version_info[:2]
        )
        return 2

    if args.selftest:
        return mode_selftest(p)
    if args.nrf:
        return mode_nrf(p)

    # Guard the numbers that could otherwise hang or divide by zero. A wrong
    # flag should say so, not sit there looking busy.
    for flag, value, low in (("--rate", args.rate, 0.05),
                             ("--speed-mult", args.speed_mult, 0.05),
                             ("--flood-rate", args.flood_rate, 0.05)):
        if value < low:
            sys.stderr.write("ERROR: %s must be at least %.2f; you gave %s.\n"
                             % (flag, low, value))
            return 2

    try:
        return asyncio.run(run(args, p))
    except KeyboardInterrupt:
        print()
        p.info("Stopped by Ctrl+C.")
        p.info("NOTE: stopping here leaves the ESP32 with no packets. It should "
               "go STALE after %d s, then 'PHONE DISCONNECTED' once the link "
               "drops. Both are correct." % (STALE_MS // 1000))
        return 130


if __name__ == "__main__":
    sys.exit(main())
