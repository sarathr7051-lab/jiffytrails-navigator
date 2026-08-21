# JiffyTrails Navigator — Project State & Handoff

**Paste this whole file into a new session to continue.** It contains every
decision, finding and dead end so far, so nothing needs rediscovering.

Last updated: 20 August 2026, ~22:00 IST

---

## OPENING PROMPT FOR A NEW SESSION

> I'm building a DIY motorcycle navigation display for my Triumph Speed 400 in
> Bangalore — an ESP32 + TFT device on the handlebar that shows turn-by-turn
> maneuvers fed over BLE from Google Maps on my phone, so the phone can stay in
> my pocket. This document is the full project state from a previous session:
> what's decided, what's proven, and where I'm stuck. Read it, then help me
> continue from the "CURRENT BLOCKER" section.
>
> I'm a DSP engineer, comfortable with C++ and embedded work, but new to
> soldering and to Android development. Be direct about what won't work rather
> than optimistic.

---

## 1. The project

Handlebar-mounted navigation instrument. **Phone stays in pocket**, does all
routing. ESP32 device shows current maneuver, distance to it, and ETA at a
glance. Target: never miss a turn on Bangalore's flyovers, service roads and
rapid successive junctions.

**Rider:** Sarath, Horamavu Agara, Bengaluru 560113
**Phone:** Samsung S24+, Android 16 / One UI
**Bike:** Triumph Speed 400 (has a USB-C accessory socket)

**Why build not buy:** the RE Tripper (~₹4,750) plugs into the Royal Enfield
harness and pairs via the RE app — it won't fit a Triumph, and owners report it
shows only direction and distance with no ETA. Beeline costs several times more.

---

## 2. Hardware bought

Robocraze order **356739**, delivered 20 Aug 2026, **₹1,468**.

| Item | SKU | Notes |
|---|---|---|
| ESP32 **LOLIN32** | TIFCC0110 | USB-C, **CH340** (not CP2102 as listed), LiPo JST |
| **SmartElex 2.8" TFT** 240×320 | TIFDP0094 | ILI9341, SPI, non-touch |
| MB102 830-point breadboard | — | |
| Jumper wires M2M / M2F / F2F, 20 ea | TIFCW0037/38/39 | |

**ESP32 headers arrived UNSOLDERED.** Display headers are pre-soldered.

### ★ Two hardware facts learned the hard way

**1. The USB chip is CH340, not CP2102.** The product listing was wrong. Windows
has a built-in CH340 driver, so no install is needed. Time was wasted installing
the Silicon Labs CP210x driver for nothing. Board enumerates as
**USB-SERIAL CH340 (COM10)**.

**2. The display module has an onboard AMS1117 regulator and needs 5V on VCC
and LED.** Confirmed by a visible 3-legged SOT-23 chip near VCC, and by the
vendor manual which shows VCC → 5V and LED → 5V. At 3.3V input the regulator's
~1.1V dropout leaves ~2.2V and the panel stays completely dark. Signal lines
stay at 3.3V logic — the module has level shifters.

**This also simplifies the final build:** the bike's USB gives 5V, which feeds
both the ESP32 and the display directly.

---

## 3. Pin mapping — LOLIN32 ⇄ ILI9341

| Display | LOLIN32 | Note |
|---|---|---|
| **VCC** | **5V** | NOT 3.3V — see above |
| GND | `G` | |
| CS | 15 | |
| RESET | **16** | **NOT 4** — GPIO4 isn't broken out on LOLIN32 |
| DC | 2 | |
| SDI (MOSI) | 23 | |
| SCK | 18 | |
| SDO (MISO) | 19 | |
| **LED** | **5V** | backlight |

If the module has T_CS / T_CLK / T_DIN / T_DO / T_IRQ, leave unconnected except
**T_CS → 3.3V** so the touch controller stays off the shared SPI bus.

**No series resistors.** The vendor manual's 10K resistors are for a 5V Arduino.

### Board pin labels observed
`3V`, `G`, `EN`, `VP`, `VN`, and a `+` **which is the JST battery connector, not
a header pin**. `VP`/`VN` are GPIO36/39 analog inputs, not power.

### Arduino IDE setup (working)
- IDE **2.3.10** from arduino.cc — **not** the Microsoft Store version (that's
  1.6.11 from 2016 and sandboxed)
- Boards URL: `https://raw.githubusercontent.com/espressif/arduino-esp32/gh-pages/package_esp32_index.json`
- Board: **WEMOS LOLIN32**, Port **COM10**
- Upload button is the **→ arrow**. The bug icon is the JTAG debugger and fails
  with "unable to open ftdi device" — that's expected, not an error to fix.

`User_Setup.h` for TFT_eSPI (already written to
`Documents\Arduino\libraries\TFT_eSPI\User_Setup.h`):

```cpp
#define USER_SETUP_INFO "LOLIN32 ILI9341 2.8in"
#define ILI9341_DRIVER
#define TFT_MISO 19
#define TFT_MOSI 23
#define TFT_SCLK 18
#define TFT_CS   15
#define TFT_DC    2
#define TFT_RST  16
#define LOAD_GLCD
#define LOAD_FONT2
#define LOAD_FONT4
#define LOAD_FONT6
#define LOAD_FONT7
#define LOAD_FONT8
#define LOAD_GFXFF
#define SMOOTH_FONT
#define SPI_FREQUENCY       40000000
#define SPI_READ_FREQUENCY  20000000
```

**Restart the IDE after editing this file** — it caches library config.

---

## 4. ★★ THE NAVIGATION DATA — SOLVED, this is the crown jewel

This was the gate the whole project rested on. **PASSED**, verified across two
real rides.

Google Maps on Android 16 uses the **ProgressStyle / Live Updates** notification
API — structured typed extras, **not** custom RemoteViews. No view-tree scraping
needed. Read via `NotificationListenerService`, filter `category == "navigation"`.

### Field mapping

| Need | Extras key |
|---|---|
| Distance to maneuver | `android.ongoingActivityNoti.primaryInfo` |
| Instruction text | `android.title` |
| Road turning onto | `android.ongoingActivityNoti.secondaryInfo` |
| ETA (clock time) | `android.subText` — "Arrive 8:07 pm" |
| Distance travelled (m) | `android.progress` |
| Total route length (m) | `android.progressMax` |
| Maneuver icon | `android.ongoingActivityNoti.chipIcon` |
| Traffic ahead | `android.progressSegments` |

`nowbarIcon` and `secondIcon` duplicate `chipIcon`. `largeIcon` is a
higher-detail version of the same maneuver.

### ★ Maneuver icon hash table (32×32 alpha-channel hash)

**Zero collisions across two rides, eight different roads.** Stable and
repeatable.

| chip hash | largeIcon hash | Maneuver | Confirmations |
|---|---|---|---|
| `c2a2c91` | `578152d3` | CONTINUE / depart | 6× |
| `d0883793` | `434a10a9` | **TURN LEFT** | 9× |
| `93f8340f` | `cd4ca7c1` | **TURN RIGHT** | 7× |
| `d5fc816e` | `93650589` | **SLIGHT RIGHT** | 5× |
| `26582277` | `cc2f9709` | **ROUNDABOUT** | 1× |
| `23c3f60f` | `7942b5a4` | DESTINATION (flag) | 1× |
| `83534611` | — | Maps logo — non-nav states only | — |

Icons are `type=1` (bitmap), so no resource name available; the pixel hash is
the identifier. Roundabout **exit number is not in the icon** — parse from
`title` ("take the 3rd exit").

**Still uncollected:** U-turn, flyover, merge, keep-left/right, fork,
sharp-left/right, exit/ramp. Collect opportunistically. Unknown hash → render
UNKNOWN, never guess.

### Distance quantisation

```
> 1 km       100 m steps    3.4, 3.3 … 1.0 km
1 km–300 m    50 m steps    950, 900 … 350, 300
< 300 m       10 m steps    290, 280 … 20, 10, 0
```

~1 Hz updates. The 10 m granularity under 300 m is what makes the close-approach
screen worth building.

### Parser rules — all learned from real logs

1. **`title` sometimes carries a distance prefix.** `"700 m · Slight right onto
   X"` far out, plain `"Turn left onto X"` under ~50 m. Strip
   `^\d+(\.\d+)? (m|km) · `
2. **`primaryInfo` is not always a distance.** At the moment of the turn it
   holds the road name. Validate `^\d+ m$` or `^\d+\.\d+ km$`; on failure treat
   as no-distance.
3. **`progressMax` is not constant.** Observed 851 → 1196 → 804 → 604 in one
   journey. Recompute remaining every packet, never cache.
4. **`secondaryInfo` sometimes echoes the maneuver** ("Turn right"). Suppress
   when it duplicates the instruction.
5. **`subText` also carries traffic alerts.** Only trust when it starts with
   "Arrive".

### State detection

| State | Signature |
|---|---|
| Rerouting | `primaryInfo == "Rerouting..."`, `subText == "Arrive "`, no chipIcon |
| Arriving | `title == "Arriving"`, `progressMax == 0`, no ProgressStyle template |
| Ended | notification removed |

Reroute recovery measured at **300 ms**.

### progressSegments — free traffic bar

Segment lengths sum exactly to `progressMax`. Segment [0] is grey and its length
**always equals `progress`** — self-describing: travelled portion first, then
traffic ahead.

| colorInt | Hex | Meaning |
|---|---|---|
| −9276814 | 0xFF727272 | grey — travelled |
| −16731905 | 0xFF00B0FF | blue — normal |
| −24576 | 0xFFFFA000 | amber — slow |
| −769226 | 0xFFF44336 | red — heavy |

A thin colour strip at the bottom of the display showing traffic ahead in
metres. Nothing else in the setup can do this.

### ★ Two things that DO NOT exist

- **No next-maneuver field.** The "LEFT then RIGHT in 80 m" panel from the
  original spec is impossible with Google Maps. **Dropped.**
- **Rising distance is NOT a wrong-way signal.** Tested: stationary at a signal,
  distance drifted 30 → 40 → 50 m from GPS jitter alone. A warning built on this
  would fire at every traffic light in Bangalore. Use the explicit
  `"Rerouting..."` state.

### Watchdog

At 2 km out in slow traffic, **64 seconds passed with no content change** while
Maps was still posting at ~1 Hz. **Count notification arrivals, not value
changes.** 10 s threshold.

---

## 5. BLE protocol (designed, not yet implemented)

ESP32 = GATT **peripheral**; phone connects as central, writes at ~1 Hz. Request
MTU 185 on connect.

```
Service        6e400001-b5a3-f393-e0a9-e50e24dcca9e
Char (write)   6e400002-b5a3-f393-e0a9-e50e24dcca9e   phone → ESP32
Char (notify)  6e400003-b5a3-f393-e0a9-e50e24dcca9e   ESP32 → phone
```

Framing: `[type:u8][len:u8][payload…]`, little-endian.

| Type | Name | Payload |
|---|---|---|
| 0x01 | NAV | `u8 maneuver, u16 dist_m, u8 next_maneuver, u16 next_dist_m, u16 eta_min, u16 remaining_100m, u8 flags, utf8 instruction` |
| 0x02 | STATUS | `u8 flags, u8 phone_battery_pct` |
| 0x03 | CALL | `u8 state, utf8 name` |
| 0x04 | MEDIA | `u8 state, utf8 title \0 artist` |
| 0x05 | TRIP | `u32 distance_m, u16 duration_min, u16 speed_x10, u16 max_speed_x10` |
| 0x06 | CONFIG | `u8 brightness (0=auto), u8 units` |
| 0x07 | TRAFFIC | segment list |

NAV flags: bit0 nav_active, bit1 rerouting, bit2 gps_weak, bit3 arrived.

Maneuver codes:
```
0x00 UNKNOWN     0x06 SHARP_LEFT    0x0C MERGE        0x12 FLYOVER
0x01 CONTINUE    0x07 SHARP_RIGHT   0x0D FORK_LEFT    0x13 UNDERPASS
0x02 TURN_LEFT   0x08 KEEP_LEFT     0x0E FORK_RIGHT   0x14 DESTINATION
0x03 TURN_RIGHT  0x09 KEEP_RIGHT    0x0F EXIT_LEFT    0x15 FERRY
0x04 SLIGHT_LEFT 0x0A UTURN_LEFT    0x10 EXIT_RIGHT
0x05 SLIGHT_RIGHT 0x0B UTURN_RIGHT  0x11 ROUNDABOUT
```
Reserve 0x20–0x2F for roundabout-exit-N.

**Typed messages from day one** — a nav-only struct would need rewriting on both
sides when caller ID and trip stats arrive later.

---

## 6. UI design

| Range | Display |
|---|---|
| > 500 m | Instruction, medium distance, ETA, remaining km, traffic strip |
| 500–100 m | Distance large, arrow large, ETA drops |
| < 100 m | Full-screen arrow + distance only |
| < 30 m | Inverted colours |

**Failure states matter more than the happy path:**

| Condition | Display |
|---|---|
| No packet 10 s | Dim, "STALE" |
| BLE disconnected | "PHONE DISCONNECTED" |
| nav_active = 0 | Clock + trip stats — **never a stale maneuver** |
| rerouting | "REROUTING", suppress arrow |

Landscape. Black on white. Arrows as **vector paths**, not bitmaps. TFT_eSPI
**sprites for the distance field only** — a full-screen sprite won't fit in plain
ESP32 RAM.

---

## 7. Decisions and rationale

**Kept**
- 2.8" non-touch over 2.4" — bigger digits, and no touch overlay means ~10–20%
  more light through the panel
- LOLIN32 over 38-pin NodeMCU — smaller, fits behind the display; USB-C
- Traffic strip — free from data already present
- OTA firmware update — **mandatory**, verify twice before sealing the case

**Cut, with reasons**
- **GPS module** — the phone is a better GPS and already in the loop. Saves
  ₹400, 45 mA, an antenna, cold-start delay
- **Magnetometer** — motorcycle magnetics; GPS course works while moving
- **Vibration motors** — small ERM motors cannot be felt through the bars on a
  running 398cc single. Signal-to-noise, not tuning
- **Next-maneuver panel** — data doesn't exist (§4)
- **Internal battery** — no lithium in a hot enclosure on a bike
- **Heat-set inserts** — hex pockets with plain M3 nuts, ₹20, no tools

**Recommended, deliberately deferred:** ₹1,200–1,500 Bluetooth helmet headset.
Voice tells you *when*, screen tells you *what*. Makes the display a
confirmation layer rather than safety-critical.

---

## 8. Mount and enclosure (designed, not built)

**Existing:** BOBO **BM4** Jaw-Grip, part BB-BM-004-001002. Rated 500 g; device
~120 g. Chain: handlebar clamp → 17 mm ball → socket bracket with pinch knob →
copper jaw plate. **The copper jaw plate is the broken part and gets discarded.**

**Approach:** print an adapter mounting to the *socket bracket* in place of the
copper plate, presenting a 3-lug **Garmin-style quarter-turn**. Enclosure back
carries the male boss.

**Why quarter-turn over a clamp screw:** friction joints walk loose under
vibration. Quarter-turn traps three lugs behind solid shoulders — shear plane,
nothing to unwind. Sprung detent for the click and to stop back-off.

**★ OPEN:** photos of the socket bracket's rear face show a circular interface
with a central screw and a four-lobed keyed pattern — possibly BOBO's own
twist-lock. If so, no custom quarter-turn needed. Test by hand: grip the head,
hold the clamp, try twisting.

**Enclosure ~94 × 58 × 20 mm** (display PCB ~50 × 86 mm, landscape).
- **PETG or ASA — never PLA** (softens ~55 °C; a case in Bangalore sun exceeds
  that and sags)
- **Form-in-place gasket**: 2 × 1.5 mm groove filled with clear RTV, cured with
  the case closed over cling film
- **Window**: 2 mm polycarbonate bonded to the *inside* of the bezel so pressure
  seats it
- **Cable gland on the bottom face** with a drip loop
- **★ ePTFE pressure vent, Ø3 mm** — the part everyone omits. A sealed box in
  sun reaches 60 °C+; cold rain contracts the air and pulls water past the
  gasket. Cut membrane from an old rain jacket
- Blind screw bosses; light colour; sunshade hood; slight downward tilt

Print: 0.2 mm layers, **4 perimeters** (lugs take the load), 30–40% infill,
sealing face flat on the bed.

A friend is buying a 3D printer. **Ask for a tolerance test** — a plate with
5 mm holes at nominal, +0.2, +0.4 — and report which one an M4 slides through.

---

## 9. Status

**DONE**
- Stage 1: NavDump app built and installed (`com.jiffytrails.navdump`, project
  at `C:\dev\NavDump`, Android Studio Quail 3)
- **Stage 2: data gate PASSED** — two rides logged and fully analysed (§4)
- **Stage 3: ESP32 alive** — Arduino IDE 2.3.10, esp32 core 3.3.11, blink
  uploaded and verified. Serial reports: ESP32-D0WDQ6-V3 rev 3.1, dual core,
  240 MHz, MAC 2c:bc:bb:92:48:3c

**★★ CURRENT BLOCKER — Stage 4, display**

The display shows **no backlight at all**. Two candidate causes, not yet
separated:

1. **Power rail.** Module has an AMS1117 and wants 5V, but the LOLIN32 does not
   break out 5V to any header pin. The `+` next to the white connector is the
   JST battery terminal (3.7–4.2 V, only live with a battery or during
   charging), not USB 5V.
2. **Contact.** The ESP32's headers are **unsoldered**, so `3V` and `G` may be
   making no contact at all. USB upload works because that path doesn't touch
   the headers.

**Options for 5V:** solder a wire to the USB-C **VBUS** pad, or power the
display from a separate USB source (phone charger + cut cable) sharing a common
ground with the ESP32. The latter needs no soldering and would isolate cause 1
from cause 2 immediately.

**Both paths converge on: solder the ESP32 headers.**

**NEXT ACTIONS**
1. Get ESP32 headers soldered — Chandan Electronics, Kammanahalli (WhatsApp
   first, ~₹50, 5 min) or a ₹550–900 60W adjustable kit
2. Buy a **multimeter** (~₹500) — the guessing about whether voltage reaches a
   pin has to stop
3. Buy **digital calipers** (~₹400) — every enclosure dimension depends on them
4. Solve 5V, wire the display, run `Read_User_Setup` then
   `TFT_graphicstest_one_lib`
5. **★ THE SUNLIGHT TEST** — black on white, biggest font, outdoors 12:00–14:00

**Gate at step 5.** Readable → proceed. Marginal → anti-glare film + sunshade
hood, and the helmet headset becomes more valuable. Unreadable → display class
changes and the budget breaks (transflective Sharp Memory LCD is ₹3,000+).

**Free and ongoing:** leave NavDump installed, collect missing maneuver hashes
on ordinary rides. An Outer Ring Road trip should net several.

---

## 10. Money

| | ₹ |
|---|---|
| Spent — Robocraze | 1,468 |
| Soldering kit | 550–900 |
| Multimeter | 500 |
| Calipers | 400 |
| 3D printing (friend's printer) | ~200 filament |
| PC sheet, RTV, gland, fasteners, film | ~640 |
| **Projected** | **~3,800–4,100** |

Optional: helmet BT headset ₹1,200–1,500. TPMS (generic BLE sensors sniffed
passively — **not Fobo**, it's encrypted) ₹1,800–3,000, deferred.

---

## 11. Companion files

| File | Purpose |
|---|---|
| `NavDumpService_v3.kt`, `NavLog.kt`, `MainActivity.kt`, `AndroidManifest.xml` | Diagnostic Android app. v3 emits one compact SUM line per update plus full dumps on structural change |
| `BUILD_PLAN.md` | Twelve-stage plan with gates and test criteria |
| `mount-design.html` | Technical drawings: exploded assembly, quarter-turn interface, sealing section |

Log retrieval:
```
adb pull /sdcard/Android/data/com.jiffytrails.navdump/files/navdump.log
```
If permission denied on Android 11+:
```
adb exec-out run-as com.jiffytrails.navdump cat <path> > navdump.log
```

---

## 12. Time-wasters to avoid repeating

- **Don't install the CP210x driver.** The board is CH340; Windows handles it.
- **Don't use the Microsoft Store Arduino IDE.** It's 1.6.11 and sandboxed.
- **Don't click the bug icon** to upload. That's the JTAG debugger; it fails
  with "unable to open ftdi device" and that's expected.
- **Don't chase the onboard LED pin.** GPIO 5 didn't visibly work; the upload
  log ("Hash of data verified") is the real proof of success.
- **Don't wire display VCC to 3.3V.** AMS1117 dropout leaves ~2.2V, panel dark.
- **Don't add the 10K series resistors** from the vendor manual — those are for
  a 5V Arduino.
- **Don't build a wrong-way warning from rising distance.** GPS jitter at
  traffic signals will trigger it constantly.
- **Don't spend more time optimising component prices.** An evening went into a
  ₹100 spread. The real risks are the sunlight test and the data source.

---

## 13. Honest assessment on productising

Prototype working is ~20% of the distance and the rest isn't engineering. The
notification parser is fine for a personal device — if Maps changes format you
spend an evening fixing it — but fatal for a product, because one Maps update
breaks every unit in the field simultaneously. Google also restricts
notification-listener permission on the Play Store, and this is exactly the use
case they scrutinise.

The fix is owning the routing (Mapbox Navigation SDK, HERE, or self-hosted
Valhalla). Then WPC/ETA equipment approval for a BLE device in India, BIS
compliance, and liability for a safety-adjacent device.

Realistic path if it works well: open-source design or kit for enthusiasts. No
app store, no certification burden, community maintains the parser.
