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
  MV_FERRY         = 0x15,

  /*
    DEPART - "head toward X", the first step of a route.

    Maps draws the SAME chipIcon for this as for continue-straight; NAV_DATA.md
    records the hash c2a2c91 as "CONTINUE / depart" and it has done since the
    first ride. One bitmap, two meanings.

    They are not the same instruction. Maps' own banner shows the maneuver at
    the END of a depart step - so while the notification carried the continue
    glyph, the phone was showing a right turn onto the road we were heading
    toward, and the panel drew a confident straight arrow. Reported from a real
    ride in Kochi; the rider took the correct turn only because he knew it.

    The icon cannot distinguish them, so the phone splits them on the title and
    falls back to CONTINUE when it cannot. Drawing "you are setting off along
    this road" is true; drawing "go straight through what is ahead" was not.
  */
  MV_DEPART        = 0x16
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
  PKT_TRAFFIC = 0x07,
  PKT_NOTIFY  = 0x08    // added 26 Aug 2026, see docs/BLE_PROTOCOL.md
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

// How long the arrival screen holds before falling back to idle.
static const uint32_t ARRIVAL_DWELL_MS = 30000;

// ------------------------------------------------------------- NavState

// --------------------------------------------------------------- alerts

enum : uint8_t { CALL_IDLE = 0, CALL_RINGING = 1, CALL_ACTIVE = 2 };
enum : uint8_t { NOTIFY_GENERIC = 0, NOTIFY_MESSAGE = 1, NOTIFY_EMAIL = 2, NOTIFY_ALERT = 3 };

static const size_t ALERT_TEXT_MAX = 40;
static const size_t ALERT_SRC_MAX  = 20;

// A notification is transient by design. Persisting it would turn the band
// into a second thing to read on every glance, which is the failure this
// pattern exists to avoid.
static const uint32_t NOTIFY_DWELL_MS = 6000;

static const size_t INSTRUCTION_MAX = 64;   // 60 chars observed in the wild

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
  uint8_t  clockHour = 0;
  uint8_t  clockMin  = 0;
  bool     clockValid = false;

  // --- from PKT_CONFIG ---
  // Polarity comes from the phone, which knows real local sunset for the
  // actual lat/long. Deliberately NOT from a light sensor: Bengaluru flyovers
  // and underpasses would strobe the screen, and a polarity flap is a
  // full-panel flash in peripheral vision - the exact night-vision insult the
  // mode exists to prevent. Garmin splits it the same way: slow signal drives
  // polarity, fast signal drives brightness.
  bool     night = false;

  // --- from PKT_CALL / PKT_NOTIFY ---
  uint8_t  callState  = CALL_IDLE;
  char     callName[ALERT_TEXT_MAX] = {0};
  uint8_t  notifyKind = NOTIFY_GENERIC;
  char     notifySrc[ALERT_SRC_MAX]  = {0};
  char     notifyText[ALERT_TEXT_MAX] = {0};
  uint32_t notifyAtMs = 0;      // arrival time, for the dwell timeout

  // --- link health, owned by the watchdog ---
  bool     linkUp       = false;   // BLE connected
  bool     stale        = false;   // no arrival within STALE_MS
  uint32_t lastPacketMs = 0;       // millis() of the last arrival, any type
  uint32_t packetCount  = 0;       // arrivals, not changes

  // --- arrival latch, owned by the watchdog ---
  // Maps drops its notification ~4.7 s after arrival, which clears nav_active.
  // Without a latch the arrival screen would flash past and land on IDLE.
  uint32_t arrivedAtMs  = 0;
  bool     showArrival  = false;

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
  UI_ARRIVED,        // you are there. Latched, because Maps drops the route
  UI_IDLE,           // nav_active == 0. Clock. NEVER a maneuver
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
  if (s.showArrival) return UI_ARRIVED;
  if (!s.navActive()) return UI_IDLE;
  if (s.rerouting()) return UI_REROUTING;
  /*
    A distance of zero is not a distance.

    Maps reports "continue, 0 m" whenever the next maneuver is where you already
    are — most obviously at the moment of departure, when the route ahead is
    still kilometres long. Treating that as "under 30 m" put the rider on the
    inverted turn-now screen, with no road name, no ETA and no distance
    remaining, while stationary at the start of a 3.4 km route.

    Claiming an imminent turn on the strength of a zero is the dangerous
    direction to be wrong in, so zero falls through to the far screen, which is
    the one that can actually say something useful — road name, arrival time and
    distance to go.
  */
  if (s.dist_m == 0)   return UI_NAV_FAR;
  if (s.dist_m <  30)  return UI_NAV_NOW;
  if (s.dist_m < 100)  return UI_NAV_COMMITTED;
  if (s.dist_m <= 500) return UI_NAV_APPROACH;
  return UI_NAV_FAR;
}

// ---------------------------------------------------------------- the band

/*
  The strip along the bottom. It does double duty: arrival and remaining
  distance while there is time to read them, and an inverted alert block when
  something happens. Blank costs nothing — that is the whole point of the
  pattern. An element that is empty in the normal case consumes no glance
  until it fires.

  Full-block inversion is used for alerts because it is the most
  blur-and-glare-robust encoding this panel has: a large, low-spatial-frequency
  luminance event, which is exactly what peripheral vision is built to detect.
*/
enum BandContent : uint8_t {
  BAND_BLANK,    // nothing. A turn is imminent, or the link is in trouble
  BAND_CALL,     // inverted, persists while ringing
  BAND_NOTIFY,   // inverted, self-dismisses after NOTIFY_DWELL_MS
  BAND_FOOTER    // arrival time and distance remaining
};

/*
  One place decides what the band shows, for the same reason screenFor()
  exists. The ordering is the design:

  Nothing may cover the turn once committed. BUILD_PLAN Stage 9 says alerts are
  "suppressed below 100 m to a maneuver", and that outranks every alert
  regardless of urgency — a missed call costs nothing, a missed junction in
  Bengaluru traffic costs a great deal.
*/
inline BandContent bandFor(const NavState& s, UiScreen scr, uint32_t nowMs) {
  if (scr == UI_NAV_COMMITTED || scr == UI_NAV_NOW) return BAND_BLANK;
  if (scr == UI_DISCONNECTED || scr == UI_STALE)    return BAND_BLANK;

  // Any call, ringing or answered. Originally this tested RINGING alone, and
  // nothing ever displayed: Samsung's dialer runs as a foreground service, so
  // its *ringing* notification already carries FLAG_ONGOING_EVENT and the phone
  // side classified every call as answered. Distinguishing the two is not worth
  // a rule that can silence the feature entirely - a call is worth showing
  // either way, and the band is suppressed near a turn regardless.
  if (s.callState != CALL_IDLE) return BAND_CALL;

  if (s.notifyText[0] != '\0' && (nowMs - s.notifyAtMs) < NOTIFY_DWELL_MS) {
    return BAND_NOTIFY;
  }

  return (scr == UI_NAV_FAR) ? BAND_FOOTER : BAND_BLANK;
}
