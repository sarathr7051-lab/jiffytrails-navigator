/*
  nav_types.h — the contract every module shares.

  NavState is the single source of truth. BLE writes it, the watchdog
  annotates it, the display renders it and nothing else. No module reaches
  into another; if something is not in here, the display cannot know it.

  Codes and framing come from docs/BLE_PROTOCOL.md. Keep them in step.
*/

#pragma once
#include <Arduino.h>

// ------------------------------------------------------------- maneuvers

enum : uint8_t {
  MV_UNKNOWN       = 0x00,   // renders "?" — never guess an arrow
  MV_CONTINUE      = 0x01,
  MV_TURN_LEFT     = 0x02,
  MV_TURN_RIGHT    = 0x03,
  MV_SLIGHT_LEFT   = 0x04,
  MV_SLIGHT_RIGHT  = 0x05,
  MV_SHARP_LEFT    = 0x06,
  MV_SHARP_RIGHT   = 0x07,
  MV_KEEP_LEFT     = 0x08,
  MV_KEEP_RIGHT    = 0x09,
  MV_UTURN_LEFT    = 0x0A,
  MV_UTURN_RIGHT   = 0x0B,
  MV_MERGE         = 0x0C,
  MV_FORK_LEFT     = 0x0D,
  MV_FORK_RIGHT    = 0x0E,
  MV_EXIT_LEFT     = 0x0F,
  MV_EXIT_RIGHT    = 0x10,
  MV_ROUNDABOUT    = 0x11,
  MV_FLYOVER       = 0x12,   // Maps does not distinguish these — see NAV_DATA.md
  MV_UNDERPASS     = 0x13,
  MV_DESTINATION   = 0x14,
  MV_FERRY         = 0x15
};

// 0x20-0x2F reserved for ROUNDABOUT_EXIT_N. Confirmed necessary: roundabout
// icons differ per exit, and another project independently needed 16 variants.
static const uint8_t MV_ROUNDABOUT_EXIT_BASE = 0x20;

// --------------------------------------------------------- packet types

enum : uint8_t {
  PKT_NAV     = 0x01,
  PKT_STATUS  = 0x02,
  PKT_CALL    = 0x03,
  PKT_MEDIA   = 0x04,
  PKT_TRIP    = 0x05,
  PKT_CONFIG  = 0x06,
  PKT_TRAFFIC = 0x07
};

// NAV flags
static const uint8_t NAV_ACTIVE    = 1 << 0;
static const uint8_t NAV_REROUTING = 1 << 1;
static const uint8_t NAV_GPS_WEAK  = 1 << 2;
static const uint8_t NAV_ARRIVED   = 1 << 3;

// ------------------------------------------------------------- timing

// Watchdog counts packet ARRIVALS, not value changes. NAV_DATA.md measured
// 64 seconds with no field changing in slow traffic while Maps kept posting
// at ~1 Hz — a change-based watchdog has no workable threshold.
static const uint32_t STALE_MS = 10000;

// ------------------------------------------------------------- NavState

static const size_t INSTRUCTION_MAX = 64;   // 59 chars observed in the wild

struct NavState {
  // --- from PKT_NAV ---
  uint8_t  maneuver       = MV_UNKNOWN;
  uint16_t dist_m         = 0;
  uint8_t  next_maneuver  = MV_UNKNOWN;   // reserved: Maps does not expose it
  uint16_t next_dist_m    = 0;            // reserved
  uint16_t eta_min        = 0;
  uint16_t remaining_100m = 0;
  uint8_t  flags          = 0;
  char     instruction[INSTRUCTION_MAX] = {0};

  // --- from PKT_STATUS ---
  uint8_t  phoneBatteryPct = 0;

  // --- link health, owned by the watchdog ---
  bool     linkUp       = false;   // BLE connected
  bool     stale        = false;   // no arrival within STALE_MS
  uint32_t lastPacketMs = 0;       // millis() of the last arrival, any type
  uint32_t packetCount  = 0;       // arrivals, not changes

  bool navActive() const { return flags & NAV_ACTIVE;    }
  bool rerouting() const { return flags & NAV_REROUTING; }
  bool gpsWeak()   const { return flags & NAV_GPS_WEAK;  }
  bool arrived()   const { return flags & NAV_ARRIVED;   }
};

// What the display should actually be showing. Derived, never stored — the
// whole point is that a stale maneuver can never survive a state change.
enum UiScreen : uint8_t {
  UI_DISCONNECTED,   // link down. Distinct from stale: the link itself is gone
  UI_STALE,          // link up, data stopped
  UI_IDLE,           // nav_active == 0. Clock and trip. NEVER a maneuver
  UI_REROUTING,      // arrow suppressed — the old turn is no longer true
  UI_NAV_FAR,        // > 500 m
  UI_NAV_APPROACH,   // 500-100 m
  UI_NAV_COMMITTED,  // < 100 m
  UI_NAV_NOW         // < 30 m, inverted
};

// Single place the precedence is decided. Order matters: link and freshness
// outrank content, so no failure can leave a maneuver on screen.
inline UiScreen screenFor(const NavState& s) {
  if (!s.linkUp)     return UI_DISCONNECTED;
  if (s.stale)       return UI_STALE;
  if (!s.navActive()) return UI_IDLE;
  if (s.rerouting()) return UI_REROUTING;
  if (s.dist_m <  30) return UI_NAV_NOW;
  if (s.dist_m < 100) return UI_NAV_COMMITTED;
  if (s.dist_m <= 500) return UI_NAV_APPROACH;
  return UI_NAV_FAR;
}
