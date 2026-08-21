# JiffyTrails Navigator

A handlebar-mounted turn-by-turn navigation display for motorcycles. The phone
stays in your pocket and does the routing; an ESP32 device on the bars shows the
current maneuver, distance to it, and arrival time at a glance.

Built for a **Triumph Speed 400** in Bengaluru, where flyovers, service roads and
rapid successive junctions make "arrow pointing at the destination" navigation
useless.

**Status:** working prototype in progress. The navigation data pipeline is
proven; the display hardware is being brought up.

---

## Why

Nothing on the market does this for a non-Royal-Enfield bike. The RE Tripper
(~₹4,750) plugs into the RE wiring harness and pairs through the RE app, and
owner reports say it shows only direction and distance — no ETA. Beeline costs
several times more.

Target cost: under ₹4,000 including tools.

---

## How it works

```
   ANDROID PHONE  (pocket, screen off)
   Google Maps navigating normally
              │
              │  NotificationListenerService reads the ongoing
              │  navigation notification, parses it, and pushes
              │  typed packets at ~1 Hz
              ▼
          BLE GATT
              │
              ▼
        ESP32 (LOLIN32)
              │
              ▼
     2.8" ILI9341 TFT, 240×320
```

Running Maps with the screen off draws a fraction of what a mounted phone does —
on a four-hour ride that's the difference between arriving at 15% and 60%.

---

## ★ The interesting bit

Google Maps has no public API for live guidance. But on **Android 16** it uses
the **ProgressStyle / Live Updates** notification API, which exposes structured
typed extras — not the custom RemoteViews layout that older parsers had to
scrape.

This repo documents the full field mapping, a verified maneuver-icon hash table,
the distance quantisation bands, and the parser rules — all derived from real
rides, not guesswork.

See **[docs/NAV_DATA.md](docs/NAV_DATA.md)**. That's the part worth reading even
if you never build the hardware.

---

## Repo layout

| Path | Contents |
|---|---|
| `docs/NAV_DATA.md` | ★ Google Maps notification reverse-engineering — field mapping, icon hashes, parser rules |
| `docs/BLE_PROTOCOL.md` | Wire format between phone and ESP32 |
| `docs/HARDWARE.md` | Parts, pin mapping, wiring, costs |
| `docs/BUILD_PLAN.md` | Twelve-stage plan with gates and test criteria |
| `docs/PROJECT_STATE.md` | Full running state — decisions, findings, dead ends |
| `android/navdump/` | Diagnostic app that dumps and decodes nav notifications |
| `firmware/navigator/` | ESP32 firmware (in progress) |
| `hardware/mount-design.html` | Technical drawings — quarter-turn mount, sealed enclosure |
| `logs/` | Captured ride logs |

---

## Current status

**Done**
- Navigation data source proven across two real rides
- Six maneuver icon hashes confirmed with zero collisions
- Android diagnostic app working
- ESP32 toolchain verified — compiles, uploads, hash-verified

**In progress**
- Display bring-up (headers need soldering)

**Next gate**
- ★ Daylight readability test. A ~250 cd/m² TFT against 100,000 lux of Bangalore
  noon is the single biggest unknown in the project.

---

## Hardware

| Part | ~₹ |
|---|---|
| ESP32 LOLIN32 | 449 |
| SmartElex 2.8" ILI9341 TFT, non-touch | 815 |
| Breadboard + jumper wires | 204 |
| Soldering kit + multimeter | 1,000 |
| Enclosure, mount, fasteners, sealing | ~840 |
| **Total** | **~3,300** |

Deliberately excluded, with reasons in
[docs/PROJECT_STATE.md](docs/PROJECT_STATE.md): GPS module, magnetometer,
vibration motors, internal battery.

---

## Safety

This is a glanceable instrument, not something to read while riding. It is
designed so that losing the connection produces an obvious failure state rather
than a stale instruction — a navigator that confidently shows the wrong arrow is
worse than one showing nothing.

Voice guidance through a helmet headset remains the better primary channel. This
display is the confirmation layer: audio tells you *when*, the screen tells you
*what*.

---

## Licence

MIT. See [LICENSE](LICENSE).

Not affiliated with Google, Triumph, or BOBO. Notification parsing relies on
undocumented internals and may break with any Maps update.
