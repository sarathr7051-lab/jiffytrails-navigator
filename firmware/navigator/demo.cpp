/*
  demo.cpp - scripted state for reviewing the interface without a phone.

  Everything here writes NavState and nothing else. It draws nothing itself and
  knows nothing about the display, which is the whole point: what you judge on
  the panel is the real renderer, at mount distance, in real light.

  The glyph parade is the one that earns its keep. tools/ascii_glyphs.pl proves
  an arrow is geometrically what it claims to be, but it cannot tell you whether
  a fork reads as a fork at 700 mm through a visor. This can.
*/

#include <Arduino.h>
#include "demo.h"
#include "display.h"
#include "glyph_data.h"

namespace {

enum Mode : uint8_t { M_OFF, M_GLYPHS, M_RIDE, M_ALERTS };   // M_ prefix: plain
                                                             // GLYPHS collides with
                                                             // the glyph table.

Mode     mode      = M_OFF;
uint32_t stepAtMs  = 0;
uint16_t step      = 0;

const uint32_t GLYPH_MS = 1800;   // long enough to look, short enough to sit through
const uint32_t ALERT_MS = 3500;

// Short names, drawn as the road name so the parade says what it is showing.
// Deliberately not derived from the enum - a name is for a human, and
// "SLIGHT RIGHT" reads better at a glance than MV_SLIGHT_RIGHT.
const char* nameFor(uint8_t code) {
  switch (code) {
    case MV_CONTINUE:     return "Continue";
    case MV_TURN_LEFT:    return "Turn left";
    case MV_TURN_RIGHT:   return "Turn right";
    case MV_SLIGHT_LEFT:  return "Slight left";
    case MV_SLIGHT_RIGHT: return "Slight right";
    case MV_SHARP_LEFT:   return "Sharp left";
    case MV_SHARP_RIGHT:  return "Sharp right";
    case MV_KEEP_LEFT:    return "Keep left";
    case MV_KEEP_RIGHT:   return "Keep right";
    case MV_FORK_LEFT:    return "Fork left";
    case MV_FORK_RIGHT:   return "Fork right";
    case MV_EXIT_LEFT:    return "Exit left";
    case MV_EXIT_RIGHT:   return "Exit right";
    case MV_UTURN_LEFT:   return "U-turn left";
    case MV_UTURN_RIGHT:  return "U-turn right";
    case MV_MERGE:        return "Merge";
    case MV_ROUNDABOUT:   return "Roundabout";
    case MV_FLYOVER:      return "Flyover";
    case MV_UNDERPASS:    return "Underpass";
    case MV_FERRY:        return "Ferry";
    case MV_DESTINATION:  return "Destination";
    default:              return "Unknown";
  }
}

// The parade: everything in the glyph table, then the cases the table does not
// cover - two roundabout exits, and the "?" that an unrecognised icon draws.
// Those last three are exactly the ones nobody remembers to look at.
const uint8_t EXTRA[] = { (uint8_t)(MV_ROUNDABOUT_EXIT_BASE + 2),
                          (uint8_t)(MV_ROUNDABOUT_EXIT_BASE + 3),
                          MV_UNKNOWN };
const uint8_t EXTRA_N = sizeof(EXTRA) / sizeof(EXTRA[0]);

// A short ride. Distances are the ones that cross every band boundary, so the
// screen changes are what you are watching for, not the numbers.
struct Leg { uint8_t mv; const char* road; uint16_t from; };
const Leg RIDE_LEGS[] = {
  { MV_CONTINUE,     "Kammanahalli Main Rd", 1200 },
  { MV_TURN_RIGHT,   "TC Palya Main Rd",      620 },
  { MV_EXIT_LEFT,    "Old Madras Rd",         480 },
  { MV_FORK_RIGHT,   "Bhattarahalli",         300 },
  { MV_ROUNDABOUT,   "Whitefield Rd",         180 },
  { MV_DESTINATION,  "Fort Kochi Beach",      140 },
};
const uint8_t RIDE_N = sizeof(RIDE_LEGS) / sizeof(RIDE_LEGS[0]);

uint16_t rideDist = 0;
uint8_t  rideLeg  = 0;

void baseline(NavState& s) {
  // A demo must look like a healthy link or screenFor() will show DISCONNECTED
  // over the top of it. This is the only place anything fakes link health.
  s.linkUp       = true;
  s.stale        = false;
  s.lastPacketMs = millis();
  s.packetCount++;
  s.night        = false;
  s.clockValid   = true;
  s.clockHour    = 18;
  s.clockMin     = 42;
  s.phoneBatteryPct = 82;
}

void clearAlerts(NavState& s) {
  s.callState    = CALL_IDLE;
  s.callName[0]  = '\0';
  s.notifyText[0]= '\0';
  s.notifySrc[0] = '\0';
}

void start(Mode m, const char* what) {
  mode     = m;
  step     = 0;
  stepAtMs = millis();
  rideLeg  = 0;
  rideDist = RIDE_LEGS[0].from;
  Serial.printf("demo: %s\n", what);
  displayInvalidate();
}

}  // namespace

bool demoActive() { return mode != M_OFF; }

bool demoSerial() {
  if (!Serial.available()) return false;
  const int c = Serial.read();
  switch (c) {
    case 'g': start(M_GLYPHS, "glyph parade - every maneuver, 1.8 s each"); return true;
    case 'r': start(M_RIDE,   "scripted ride");                             return true;
    case 'a': start(M_ALERTS, "alerts - call and message, riding and parked"); return true;
    case 'b': displayBootBegin(); displayBootStage(2); displayBootFinish(true);
              displayInvalidate();
              Serial.println("demo: boot replayed"); return true;
    case 'x': mode = M_OFF; displayInvalidate();
              Serial.println("demo: off - display handed back to the phone");
              return true;
    default:  return false;
  }
}

void demoTick(NavState& s) {
  const uint32_t now = millis();
  baseline(s);

  switch (mode) {

    case M_GLYPHS: {
      if (now - stepAtMs >= GLYPH_MS) { step++; stepAtMs = now; }
      const uint16_t total = GLYPH_COUNT + EXTRA_N;
      if (step >= total) step = 0;

      const uint8_t code = (step < GLYPH_COUNT) ? GLYPHS[step].code
                                                : EXTRA[step - GLYPH_COUNT];
      clearAlerts(s);
      s.maneuver = code;
      s.flags    = NAV_ACTIVE;
      // 250 m puts it on the approach screen: the 96 px glyph box, which is the
      // size most turns are actually read at.
      s.dist_m         = 250;
      s.eta_min        = 12;
      s.remaining_100m = 34;
      snprintf(s.instruction, INSTRUCTION_MAX, "%s", nameFor(code));
      break;
    }

    case M_RIDE: {
      if (now - stepAtMs >= 700) {
        stepAtMs = now;
        // Counts down in the quantisation Maps actually uses, so the digits
        // skip the way they do on a real ride rather than ticking smoothly.
        const uint16_t q = (rideDist > 500) ? 100 : (rideDist > 100) ? 50 : 10;
        rideDist = (rideDist > q) ? (uint16_t)(rideDist - q) : 0;
        if (rideDist == 0) {
          if (++rideLeg >= RIDE_N) { rideLeg = 0; }
          rideDist = RIDE_LEGS[rideLeg].from;
        }
      }
      const Leg& leg = RIDE_LEGS[rideLeg];
      clearAlerts(s);
      s.maneuver = leg.mv;
      s.flags    = NAV_ACTIVE;
      s.dist_m   = rideDist;
      s.eta_min  = (uint16_t)(4 + rideDist / 90);
      s.remaining_100m = (uint16_t)(8 + rideDist / 12);
      snprintf(s.instruction, INSTRUCTION_MAX, "%s", leg.road);
      break;
    }

    case M_ALERTS: {
      if (now - stepAtMs >= ALERT_MS) { step = (step + 1) % 4; stepAtMs = now;
                                        displayInvalidate(); }
      clearAlerts(s);
      // Steps 0-1 ride with an alert; 2-3 are parked, where the alert should
      // take the whole screen rather than a 50 px strip.
      const bool riding = (step < 2);
      s.flags    = riding ? NAV_ACTIVE : 0;
      s.maneuver = MV_TURN_RIGHT;
      s.dist_m   = riding ? 700 : 0;
      s.eta_min  = 9;
      s.remaining_100m = 21;
      snprintf(s.instruction, INSTRUCTION_MAX, "%s", "Kammanahalli Main Rd");

      if (step == 0 || step == 2) {
        s.callState = CALL_RINGING;
        snprintf(s.callName, ALERT_TEXT_MAX, "%s", "Amma");
      } else {
        s.notifyKind = NOTIFY_MESSAGE;
        snprintf(s.notifySrc,  ALERT_SRC_MAX,  "%s", "Appa");
        snprintf(s.notifyText, ALERT_TEXT_MAX, "%s", "Reached home safely? Call me");
        s.notifyAtMs = now;      // keep it inside its dwell for the whole step
      }
      break;
    }

    default: break;
  }
}
