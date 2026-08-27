# Motorcycle Navigator — Staged Build Plan

Triumph Speed 400 · Bengaluru · phone stays in pocket

**Principle: every stage has a gate.** Don't buy or build for stage N+1 until
stage N's test passes. Two gates in this plan can change the whole architecture
(Stage 2 and Stage 5). Reaching them cheaply and early is the entire strategy.

---

## Status

| | |
|---|---|
| Spent | ₹1,468 (Robocraze order 356739) + soldering kit and multimeter |
| Done | Stages 1–3, Stage 4 Test A, Stage 5, and Stage 6 built |
| **Next** | **Ride it.** The chain works on the bench; every remaining unknown needs a road |

---

# STAGE 1 — Toolchain and NavDump

**Goal:** working Android build environment, NavDump installed and logging.

**Needs:** nothing new. Windows laptop, phone, data cable.

### Tasks
1. Install Android Studio. Project at `C:\dev\NavDump` — **not** Documents or
   Desktop, those are OneDrive-redirected and Gradle produces baffling
   file-lock errors inside syncing folders.
2. Defender exclusions: `C:\dev`, `~\.gradle`, `~\AppData\Local\Android\Sdk`.
3. Add `...\Android\Sdk\platform-tools` to PATH so `adb` works anywhere.
4. New Project → Empty Views Activity → package `com.jiffytrails.navdump`,
   Kotlin, minSdk 26, Kotlin DSL.
5. Drop in the four files. Run.
6. Grant notification access. Set Battery → **Unrestricted**. On Xiaomi /
   OnePlus / Samsung also add to the OEM autostart list — separate setting.

### Test
Start Maps navigation to anywhere. Switch to NavDump. Entries appear within
1–2 seconds.

**If empty:** toggle notification access off and on (Android is flaky about
rebinding after a reinstall — do this every rebuild). Reboot if that fails.
Confirm Maps is in turn-by-turn, not route preview.

### Gate
Log entries appearing while stationary. → Stage 2

---

# STAGE 2 — The data gate ★

**Goal:** find out whether Google Maps gives us what this project needs.
This is the single most important stage. Everything downstream depends on it.

**Needs:** nothing. A 20+ minute ride.

### Tasks
1. Navigate somewhere 20+ min away with varied turns — include a flyover, a
   service road, and a junction if you can.
2. Lock the phone, pocket it, ride.
3. Deliberately miss one turn to capture rerouting.
4. Pull the log:
   `adb pull /sdcard/Android/data/com.jiffytrails.navdump/files/navdump.log`

### Five questions to answer from the log

| # | Question | Why it matters |
|---|---|---|
| 1 | Does distance update ~1/sec continuously? | If it only ticks every 500 m, "20 m — TAKE RIGHT" is impossible |
| 2 | Is text in `ex android.title/text`, or only in `contentView`? | Determines parser fragility |
| 3 | Does `largeIcon hash` stay stable per maneuver type? | Stable → lookup table. Drifting → coarse classifier |
| 4 | Is a next-maneuver present anywhere? | The "LEFT then RIGHT in 80 m" screen depends on it |
| 5 | What appears during reroute / tunnel / arrival? | These are states the display must handle honestly |

### Gate
- **Q1 yes + Q2 answered + Q3 stable** → continue with Google Maps
- **Q1 no, or Q3 unusable** → pivot to OsmAnd's AIDL API. Same hardware, same
  protocol, different data source. Install OsmAnd, repeat this stage.
- Q4 no → drop the next-maneuver panel from the UI. Not fatal.

---

# STAGE 3 — ESP32 alive

**Goal:** toolchain to board.

**Needs:** ESP32, micro-USB data cable (charge-only cables are the classic
day-one failure).

### Tasks
1. Arduino IDE 2.x from arduino.cc. Board: **WEMOS LOLIN32** (not "ESP32 Dev
   Module" — this board has its own entry).
2. No driver install needed. The USB chip is **CH340**, not CP2102, despite the
   listing; Windows has a built-in driver. Port was COM10, later COM11.
3. Blink. Then a sketch printing chip revision, free heap, MAC address.

### Test
Serial monitor at 115200 shows the chip info. LED blinks. Reflashing works
repeatedly without holding BOOT.

### Gate
Reliable flash + serial. → Stage 4

---

# STAGE 4 — Display, and the sunlight gate ★

**Goal:** TFT rendering, and an answer on daylight readability.

**Needs:** display, breadboard, jumpers. No resistors — the vendor manual
specifies 10K series resistors because it assumes a 5V Arduino. Your ESP32 is
natively 3.3V. Wire straight through.

### Wiring

| Display | ESP32 |
|---|---|
| VCC | 3V3 |
| GND | GND |
| CS | GPIO 15 |
| RESET | GPIO **16** |
| DC | GPIO 2 |
| SDI (MOSI) | GPIO 23 |
| SCK | GPIO 18 |
| SDO (MISO) | GPIO 19 |
| LED | 3V3 |

### Tasks
1. TFT_eSPI library. Edit `User_Setup.h` — **the live one**; see the sketchbook
   section of `HARDWARE.md` first, this is where three sessions were lost.
   Use `ILI9341_2_DRIVER`, the pins above, and `SPI_FREQUENCY 27000000`.
2. Run the library's graphics test.
3. Build a mock nav screen — landscape, black on white, biggest possible
   distance digits, arrow, instruction text.
4. Try both orientations and both polarities (black-on-white vs white-on-black).

### Test A — function ✅ PASSED 22 Aug 2026
`TFT_graphicstest_one_lib` renders graphics and text correctly through all
rotations. No flicker, colours correct. Took `ILI9341_2_DRIVER` at 27 MHz —
full story in `HARDWARE.md`.

### Test B — SUNLIGHT ★ ← YOU ARE HERE
Flash `firmware/sunlight_test/sunlight_test.ino`. It cycles the six real
display states, including the two maximum-legibility cases, and prints the
current screen over serial so photographs can be matched up afterwards.

Take it outside between 12:00 and 14:00. Arm's length — mount height, not
reading distance. Sunglasses on if you ride with them. Try direct sun falling
on the screen, and shaded by your body. Power it from a USB power bank.

**Caveat that affects the result:** LED is wired to `3V`, so the backlight is
running below its rated brightness. If the answer is marginal, drive LED from a
5V source before concluding anything — see HARDWARE.md.

### Gate
- **Readable** → carry on, cost ₹0
- **Marginal** → first retry with LED on 5V. Still marginal → matte anti-glare
  film ₹100 + printed sunshade hood. Note in the project log that the answer was
  marginal; it raises the value of voice guidance later
- **Unreadable in all orientations** → stop. This is the branch that breaks the
  budget. Options: transflective Sharp Memory LCD (₹3,000+, monochrome), or
  accept the device is a shade-and-dusk instrument with voice carrying daylight

---

# STAGE 5 — BLE link and protocol

**Goal:** phone ↔ ESP32, with a protocol designed for everything, not just nav.

**Needs:** nothing new.

### Protocol

ESP32 is the GATT **peripheral**. Phone connects as central and writes packets
at ~1 Hz. Request MTU 185 at connect so strings fit.

```
Service        6e400001-b5a3-f393-e0a9-e50e24dcca9e
Char (write)   6e400002-b5a3-f393-e0a9-e50e24dcca9e   phone → ESP32
Char (notify)  6e400003-b5a3-f393-e0a9-e50e24dcca9e   ESP32 → phone
```

**Every packet:** `[type:u8][len:u8][payload…]`, little-endian.

| Type | Name | Payload |
|---|---|---|
| 0x01 | NAV | `u8 maneuver, u16 dist_m, u8 next_maneuver, u16 next_dist_m, u16 eta_min, u16 remaining_100m, u8 flags, utf8 instruction` |
| 0x02 | STATUS | `u8 flags, u8 phone_battery_pct` |
| 0x03 | CALL | `u8 state (0 idle/1 ringing/2 active), utf8 name` |
| 0x04 | MEDIA | `u8 state (0 stop/1 play/2 pause), utf8 title \0 artist` |
| 0x05 | TRIP | `u32 distance_m, u16 duration_min, u16 speed_kmh_x10, u16 max_speed_kmh_x10` |
| 0x06 | CONFIG | `u8 brightness (0=auto, 1-100 manual), u8 units` |
| 0x07 | TRAFFIC | segment list derived from `progressSegments` |

NAV flags: bit0 nav_active, bit1 rerouting, bit2 gps_weak, bit3 arrived.

`len` is the **payload** length, excluding the two header bytes. This matters:
the NAV instruction has no length prefix and no terminator, so its extent is
`len` minus the 11-byte fixed block.

### Maneuver codes

```
0x00 UNKNOWN          0x0C MERGE
0x01 CONTINUE         0x0D FORK_LEFT
0x02 TURN_LEFT        0x0E FORK_RIGHT
0x03 TURN_RIGHT       0x0F EXIT_LEFT
0x04 SLIGHT_LEFT      0x10 EXIT_RIGHT
0x05 SLIGHT_RIGHT     0x11 ROUNDABOUT
0x06 SHARP_LEFT       0x12 FLYOVER
0x07 SHARP_RIGHT      0x13 UNDERPASS
0x08 KEEP_LEFT        0x14 DESTINATION
0x09 KEEP_RIGHT       0x15 FERRY
0x0A UTURN_LEFT
0x0B UTURN_RIGHT
```

Reserve 0x20–0x2F for roundabout-exit-N if the logs show Maps distinguishes
them.

**Why typed messages now:** a fixed nav-only struct would have to be rewritten
on both sides when caller ID arrives in Stage 9. Two extra bytes and ten lines
buys that away.

### Tasks
1. ESP32: NimBLE-Arduino peripheral, advertise, accept writes, parse by type,
   print to serial.
2. Test client: nRF Connect on the phone. Write hex by hand.
3. Auto-reconnect on both sides. Test by walking out of range and back.

### Test
Send `01 18 03 64 00 02 50 00 0C 00 20 00 01` + "Old Madras Rd" from nRF
Connect. ESP32 serial prints: TURN_RIGHT, 100 m, next TURN_LEFT 80 m, ETA 12,
3.2 km, active, "Old Madras Rd".

As a single paste-ready string:

```
01 18 03 64 00 02 50 00 0C 00 20 00 01 4F 6C 64 20 4D 61 64 72 61 73 20 52 64
```

**Corrected 26 Aug 2026** — this example previously read `01 0F …`, and `0x0F`
is 15, which matches nothing: not the payload (24), the frame (26), the fixed
block (11) or the instruction (13). The payload is 11 fixed bytes plus 13 for
"Old Madras Rd" = 24 = **`0x18`**. Every other field in the example was correct.

The firmware tolerates the old string because it bounds `len` by the actual
write length, but the Android app must send `0x18`.

Walk 30 m away, come back. Reconnects unaided within 10 s.

### Gate
Round-trip works, reconnect is automatic. → Stage 6

---

# STAGE 6 — Android app: parse and transmit

**Goal:** the real companion app.

**Needs:** nothing new. Reuses NavDump's listener.

### Tasks
1. New project, or extend NavDump. Foreground service with a persistent
   notification (Android kills background BLE otherwise).
2. `NavSource` interface with a `GMapsNotificationSource` implementation —
   parse exactly what Stage 2's log showed, not what you hoped for.
3. Maneuver classifier: icon hash → code. Build the table from the log's ASCII
   art. Unknown hash → 0x00, never a wrong guess.
4. BLE central: scan, connect, request MTU, write NAV at 1 Hz.
5. Send NAV with `nav_active=0` when navigation stops. Silence is ambiguous;
   an explicit "not navigating" is not.

### Test
1. Phone in pocket, ESP32 on serial. Navigate a route. Serial shows correct
   maneuvers and a smoothly counting-down distance.
2. Kill Maps mid-route → ESP32 receives nav_active=0 within 2 s.
3. Turn phone Bluetooth off and on → reconnects without touching either device.
4. Screen off for 15 minutes → packets still arriving.

### Gate
20-minute route, correct data throughout, no manual intervention. → Stage 7

### Status — BUILT 27 Aug 2026, gate not yet run

`android/navlink` is a complete Gradle project, installed and working end to
end: Maps → NotificationListenerService → BLE → panel. Verified on a live route
with the road name, arrival time and distance remaining all correct on screen.

The bench proved: MTU 185 negotiated, 80+ packets with zero failures, the clock
arriving, the maneuver arrow correct, night mode inverting, and the far /
approach / committed bands switching.

**Four bugs were found by looking at hardware. Review caught none of them.**

- A parse failure rendering as `0 m` — and rule 2 fires during *ordinary*
  navigation, so it flickered mid-route.
- A zero distance treated as an imminent turn, hiding the one screen with
  something to say.
- A blank band painting white on the inverted screen.
- The main row misaligned by 30 px.

Three of those were layout arithmetic. That is now held by `static_assert`
rather than by attention.

**Still open, and only a road will settle them:**

1. **The gate itself** — 20 minutes, no intervention.
2. **An incoming call produced nothing on the display.** The listener matches on
   `CATEGORY_CALL`; Samsung's dialer may not set it. Needs a call while
   connected, then a `dumpsys notification` capture to see what it really sends.
3. **Screen off for 15 minutes** — untested. The vendor autostart list is the
   likeliest failure, and it has no API to check.
4. **Reconnect** — walk 30 m away and back, no button press at either end.
5. **The Now Bar fields alternate** roughly every second between two layouts, so
   the road name may flicker between sources. Watch while moving; the fix is to
   latch the last non-null value.

---

# STAGE 7 — UI and honesty

**Goal:** a display you can read in one glance that never lies.

**Needs:** nothing new.

### Distance-band states

| Range | Display |
|---|---|
| > 500 m | Instruction, medium distance, ETA, remaining km, next-maneuver strip |
| 500–100 m | Distance large, arrow large, ETA drops off |
| < 100 m | Full-screen arrow + distance. Nothing else |
| < 30 m | Inverted colours |
| Post-maneuver | Immediately switch to next |

### Failure states — these matter more than the happy path

| Condition | Display |
|---|---|
| No packet 10 s | Dim screen, "STALE" |
| BLE disconnected | "PHONE DISCONNECTED" |
| nav_active=0 | Clock + trip stats. **Never a stale maneuver** |
| rerouting | "REROUTING", suppress the arrow |
| gps_weak | Small warning corner |

### Tasks
1. TFT_eSPI sprites for the distance field only — full-screen sprites won't fit
   in plain ESP32 RAM. Partial sprite prevents the flicker of redrawing a large
   number every second.
2. Draw maneuver arrows as vector paths, not bitmaps. Scalable, tiny.
3. Watchdog: `millis() - lastPacket > 10000` → stale. Ten seconds, not five —
   NAV_DATA.md measured 64 s with no field changing while Maps kept posting at
   ~1 Hz, so the threshold has to clear a long quiet stretch. Counts arrivals,
   never value changes.

### Test
- Unplug the phone's Bluetooth mid-navigation. Screen must change within 10 s.
- Photograph the screen at each distance band at arm's length. Anything you
  can't read in under half a second is too small.
- Force every failure state manually and confirm none of them ever leave a
  stale instruction on screen.

### Gate
All five failure states render correctly. Every band readable at a glance.

---

# STAGE 8 — Bangalore road testing

**Goal:** find out what the real world does to it. Still on breadboard, taped
to the bar or held by a passenger — do **not** build the enclosure yet.

### Test matrix

| Scenario | Watching for |
|---|---|
| Simple left/right | Baseline correctness |
| Flyover entry and exit | Does Maps distinguish it, or is it just "keep left"? |
| Service road vs main | The Bangalore-specific failure case |
| U-turn | Icon classified correctly |
| Rapid left-right < 100 m apart | Does next-maneuver arrive in time to help? |
| Complicated junction | Is one arrow enough information? |
| Deliberate missed turn | Reroute state, and how fast it recovers |
| Underpass / GPS loss | Stale detection fires |
| Phone out of range | Disconnect state |
| 45+ minute ride | Thermal, memory leaks, BLE stability |

Keep a note per ride: what confused you, what you'd want bigger, what you
didn't need on screen.

### Gate
Ten scenarios pass. You've ridden a real route and not missed a turn.
→ commit to hardware

---

# STAGE 9 — Extra features

**Goal:** everything the protocol already anticipated.

**Needs:** LDR + 10k resistor (~₹15) **or** BH1750 (~₹120). The LDR is
genuinely sufficient — you need bright/dim/dark, not calibrated lux.

### Tasks
1. **Caller ID + now-playing.** `MediaSessionManager` on Android needs
   notification-listener permission and nothing else — already granted. Send
   CALL and MEDIA packets. Display as a bottom strip, suppressed below 100 m to
   a maneuver.
2. **Trip stats.** Phone computes from its own GPS, sends TRIP. Display on the
   idle screen when not navigating.
3. **Auto-dim.** LDR on GPIO 34 (3.3V → LDR → GPIO34 → 10k → GND), or BH1750 on
   I2C (SDA 21, SCL 22). PWM the display's LED pin. Smooth over ~2 s or it
   flickers under streetlights.

### Test
- Ring the phone mid-navigation → caller name appears, and does *not* obscure a
  maneuver under 100 m.
- Ride from daylight into a tunnel → backlight ramps smoothly, no flicker.
- Ride at night past streetlights → no strobing.

---

# STAGE 10 — OTA, before anything is sealed ★

**Goal:** never need a cable again.

**Needs:** nothing.

### Tasks
1. ArduinoOTA. Device joins home WiFi when in range, otherwise carries on.
2. Version string on the boot screen so you can confirm an update landed.
3. Update **twice** over the air, including one where the new firmware changes
   something visible.

### Test
Flash a firmware over WiFi that changes the boot version string. Reboot.
Confirm. Then do it again from the changed firmware — this proves the OTA
partition rotation works, which a single update does not.

### Gate
Two successive OTA updates, no cable. **Do not proceed until this passes.**
Discovering OTA is broken after the case is glued is a bad afternoon.

---

# STAGE 11 — Hardware build

**Goal:** a mounted device.

### Buy list

| Item | ~₹ |
|---|---|
| Soldering iron, solder, flux, wick | 400–1,200 |
| Perfboard, berg strips, heat-shrink | 240 |
| Wire stripper, flush cutters | 350 |
| Multimeter | 600 |
| Right-angle USB-C cable 30 cm | 200 |
| SMBJ5.0A TVS, 470 µF low-ESR, 1 A inline fuse | 140 |
| 3D printed case — **PETG or ASA, never PLA** | 300–600 |
| 2 mm polycarbonate window + anti-glare film | 200 |
| Silicone gasket cord, M3 screws, heat-set inserts | 300 |
| Rubber grommets for vibration isolation | 100 |
| Printed adapter onto your existing BOBO clamp | 100 |

Borrowing the iron and multimeter and using a friend's printer takes this from
~₹2,900 to ~₹1,200.

**PLA softens near 55 °C.** A dark case parked in Bangalore sun exceeds that.
Your case will sag. PETG or ASA.

### Tasks
1. Solder to perfboard. Test after **every** connection, not at the end.
2. Power conditioning: TVS across 5V, 470 µF bulk, fuse in line. The bike's
   harness produces transients when the ignition cuts.
3. Case: display footprint 50 × 86 mm, landscape → roughly 94 × 58 × 20 mm.
   Light colour to reduce heat soak. Integrated sunshade hood.
4. Mount on the BOBO clamp with rubber isolation.

### Test
- Continuity on every joint before powering up.
- 30-minute vibration test: device on the running bike, stationary, watching
  for resets or flicker.
- Water test: shower head on the sealed case for 5 minutes, unpowered, then
  open and check for ingress. Do this before you trust it in rain.
- Thermal: parked in direct sun for 1 hour, then check the case hasn't
  deformed and it still boots.

---

# STAGE 12 — Validation

Progressive: 15 min → 30 min → 1 hr → 2 hr → first rain → first long trip.

After each, check: any resets, any BLE drops, any stale-data events, case
temperature, whether anything has worked loose.

---

# Gate summary

| Gate | Kills or reshapes the project if failed |
|---|---|
| **Stage 2** — Maps data usable? | Forces pivot to OsmAnd |
| **Stage 4** — readable at noon? | Forces display class change; breaks budget |
| **Stage 10** — OTA works? | Forces the case to stay openable |

Stages 2 and 4 both cost effectively nothing and can be reached within a week
of the parts arriving. Reach them before spending anything further.
