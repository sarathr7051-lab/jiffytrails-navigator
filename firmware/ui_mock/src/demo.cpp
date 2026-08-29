// ---------------------------------------------------------------------------
// GENERATED COPY - DO NOT EDIT.
//
// Source of truth: firmware/navigator/demo.cpp
// Regenerate:      perl tools/sync_ui_mock.pl
//
// arduino-cli and the Arduino IDE both copy a sketch before compiling it, so
// this sketch cannot #include across to firmware/navigator/. This file is a
// verbatim copy. Edit the original; `perl tools/sync_ui_mock.pl --check` fails
// if the two have diverged.
// ---------------------------------------------------------------------------
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
#include "geom.h"

namespace {

enum Mode : uint8_t { M_OFF, M_GLYPHS, M_RIDE, M_ALERTS, M_JUNC, M_FLOW };   // M_ prefix: plain
                                                             // GLYPHS collides with
                                                             // the glyph table.

Mode     mode      = M_OFF;
uint32_t stepAtMs  = 0;
uint16_t step      = 0;

const uint32_t GLYPH_MS = 1800;   // long enough to look, short enough to sit through
const uint32_t ALERT_MS = 3500;
const uint32_t JUNC_MS  = 3000;   // long enough to work out what you are seeing

// Short names, drawn as the road name so the parade says what it is showing.
// Deliberately not derived from the enum - a name is for a human, and
// "SLIGHT RIGHT" reads better at a glance than MV_SLIGHT_RIGHT.
const char* nameFor(uint8_t code) {
  // The exit-numbered block is a RANGE, so it cannot be a switch label - and
  // without this the last frames of the parade were labelled "Unknown" while
  // drawing a perfectly good roundabout with a digit in it. The three frames
  // the parade exists to make somebody look at were the three it mislabelled.
  static char rab[24];
  if (code > MV_ROUNDABOUT_EXIT_BASE && code <= MV_ROUNDABOUT_EXIT_BASE + 0x0F) {
    snprintf(rab, sizeof(rab), "Roundabout, exit %d", code - MV_ROUNDABOUT_EXIT_BASE);
    return rab;
  }

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

/*
  A real route, ridden at a real speed.

  The Panampilly Nagar to Fort Kochi Beach run, because that is the route this
  display was actually tested on and "Moulana Azad Rd" is what it had on screen
  when the alert bug was photographed. Every new glyph appears at least once,
  so the parade is not the only place they get looked at.

  Distances are leg lengths in metres, not screen values. The rider moves at a
  speed, the distance falls out of that, and only the DISPLAY is quantised to
  the bands Maps uses. That ordering matters: quantising the model instead of
  the display gives a number that ticks down smoothly and then jumps, which is
  the opposite of what a real ride looks like.
*/
struct Leg { uint8_t mv; const char* road; uint16_t len; };
const Leg RIDE_LEGS[] = {
  // DEPART, not CONTINUE. The first step of a real route is "head toward X",
  // and Maps draws the same icon for both - which is what put a confident
  // straight arrow on the panel against a banner showing a turn. The demo
  // starts the way a route actually starts.
  { MV_DEPART,       "Panampilly Nagar Rd", 1200 },   // crosses the km boundary
  { MV_TURN_RIGHT,   "Moulana Azad Rd",      620 },
  { MV_FORK_RIGHT,   "Thevara Ferry Rd",     380 },
  { MV_EXIT_LEFT,    "Kochi-Fort Rd",        300 },
  { MV_ROUNDABOUT,   "Calvetty Rd",          220 },
  { MV_SHARP_LEFT,   "Tower Rd",             160 },
  { MV_DESTINATION,  "Fort Kochi Beach",     120 },
};
const uint8_t RIDE_N = sizeof(RIDE_LEGS) / sizeof(RIDE_LEGS[0]);

/*
  Metres per tick, at a 250 ms tick.

  30 km/h is 8.3 m/s, which is honest Bengaluru traffic, but at 1x a 900 m leg
  takes just under two minutes and nobody watches that. Time runs at 4x, so a
  tick is one simulated second: 8 m normally, 4 m inside the last 100 m where a
  rider is already braking for the turn. The quantisation still does the work -
  the number skips 700, 600, 500 the way it does on the road, just sooner.
*/
const uint32_t RIDE_TICK_MS = 250;
const uint16_t SPEED_CRUISE = 8;
const uint16_t SPEED_TURN   = 4;

uint16_t rideDist = 0;      // metres to the next maneuver
uint8_t  rideLeg  = 0;
uint32_t arriveAt  = 0;     // millis() when the arrival screen started
bool     juncBuilt = false; // geometry is rebuilt on step change, not per tick
int8_t   nightOverride = -1;  // -1 leave alone, 0 force day, 1 force night

// Metres left on the whole route, for the footer. Recomputed rather than
// cached, for the same reason the real parser recomputes it: NAV_DATA.md
// measured progressMax drifting within a minute, so a cached total is a lie.
uint32_t routeRemaining() {
  uint32_t m = rideDist;
  for (uint8_t i = rideLeg + 1; i < RIDE_N; i++) m += RIDE_LEGS[i].len;
  return m;
}

/*
  Synthetic junctions, in the frame the phone will send: x right, y forward,
  decimetres, already rotated heading-up. These exist so the renderer can be
  judged on the panel before any of the Android side of ARCH_ANDROID_AUTO.md
  exists - the same reason the glyph parade exists.

  All three are cases where an arrow is not enough, which is the only
  justification for drawing a map at all.
*/
/*
  Every way runs OFF the edge of the window rather than stopping inside it, and
  the road you are on starts BEHIND you.

  The first version had three short stubs radiating from a point, and on the
  panel it read as a pitchfork icon rather than a junction - which is exactly
  what it was. Roads that terminate in mid-air are the difference between a map
  and a symbol. The window is 120 m deep and about 120 m wide at this scale, so
  anything past roughly +-700 dm laterally or 1250 dm forward is clipped, which
  is what makes the edges look cut rather than drawn.
*/
/*
  LAYERS ARE RELATIVE, and that is the whole trick here.

  The first version put the route on layer 1 for its entire length. Its halo -
  the 25 px casing an elevated way carries - was then centred on (0,380), the
  exact vertex the service road branches from, and ate the first 12 px of it.
  The service road appeared to start in mid-air. That is the pitchfork failure
  arriving through the layer field instead of through the coordinates.

  Splitting the route into an at-grade half and an elevated half only moved the
  problem: the elevated half's halo then bit its own at-grade half, and the
  route narrowed where the ramp lifts off.

  The fix is to stop raising the route at all and LOWER the road it crosses.
  Nothing else changes visually - a halo only cares about the difference - and
  now every way that MEETS another shares its layer, while the only pair that
  CROSSES differs. A halo must break what a road crosses and never what it
  meets, and expressing it this way makes that true by construction.

  The service road also stops ON the cross road rather than running through it.
  It is at grade; it joins that junction, it does not fly over it, and a road
  that ended past it would have to be broken to stay honest.
*/
void juncFlyover() {
  geomBegin();
  // The cross road, one level down - the only thing here that is crossed.
  geomWay(-1, 0);  geomPt(-1100, 720); geomPt(1100, 700);
  // A minor street behind the junction, for context. Real windows are not tidy.
  geomWay(0, 0);   geomPt(-1100, 240); geomPt(-300, 250); geomPt(-260, -300);
  // The service road you are NOT taking: peels left, stays at grade, and joins
  // the cross road rather than crossing it.
  geomWay(0, 0);   geomPt(0, 380); geomPt(-260, 640); geomPt(-420, 712);
  // Your path: from behind you, through the junction, over the cross road.
  geomWay(0, GEOM_TAKEN);
  geomPt(0, -350); geomPt(0, 380); geomPt(200, 700); geomPt(430, 1400);
  geomCommit(millis());
}

void juncFork() {
  geomBegin();
  // A cross street beyond the fork, so the branches go somewhere.
  geomWay(0, 0);  geomPt(-1100, 1080); geomPt(1100, 1050);
  // The two branches not taken, both running off the top.
  geomWay(0, 0);  geomPt(0, 430); geomPt(-330, 780); geomPt(-620, 1400);
  geomWay(0, 0);  geomPt(0, 430); geomPt(-40, 900);  geomPt(-30, 1400);
  // Yours: from behind you, through the split, off the top right.
  geomWay(0, GEOM_TAKEN);
  geomPt(0, -350); geomPt(0, 430); geomPt(300, 800); geomPt(560, 1400);
  geomCommit(millis());
}

/*
  Ring centre (0, 640), radius 260. Every coordinate below is a literal.

  It used to build the ring and the arms in loops from sinf/cosf. That was
  tidier to read and it made the geometry invisible to tools/ascii_junction.pl,
  which only parses literal integers - so the preview showed a bare ring with
  no arms at all and looked like a bug in the renderer. Data a tool cannot read
  is data nobody checks before it is flashed.

  Arm angles are deliberately uneven. Evenly spaced exits are the tell of a
  drawing rather than a map, and no real roundabout has them.
*/
void juncRoundabout() {
  geomBegin();

  // Five arms, each starting ON the ring and running off the window.
  geomWay(0, 0);           geomPt(-248,  717); geomPt(-1100,  980);  // north-west
  geomWay(0, 0);           geomPt( -60,  893); geomPt( -180, 1400);  // north
  geomWay(0, GEOM_TAKEN);  geomPt( 231,  760); geomPt(  980, 1150);  // 2nd exit
  geomWay(0, 0);           geomPt( 250,  567); geomPt( 1100,  320);  // east
  geomWay(0, 0);           geomPt(-253,  580); geomPt(-1100,  380);  // west

  // The ring, drawn after the arms so it sits over their ends. Twelve points.
  geomWay(0, 0);
  geomPt(   0, 380); geomPt( 130, 415); geomPt( 225, 510); geomPt( 260, 640);
  geomPt( 225, 770); geomPt( 130, 865); geomPt(   0, 900); geomPt(-130, 865);
  geomPt(-225, 770); geomPt(-260, 640); geomPt(-225, 510); geomPt(-130, 415);
  geomPt(   0, 380);

  // Your entry, from behind you up to the ring.
  geomWay(0, GEOM_TAKEN);  geomPt(0, -350); geomPt(0, 380);
  geomCommit(millis());
}

void baseline(NavState& s) {
  // A demo must look like a healthy link or screenFor() will show DISCONNECTED
  // over the top of it. This is the only place anything fakes link health.
  s.linkUp       = true;
  s.stale        = false;
  s.lastPacketMs = millis();
  s.packetCount++;

  // Clear the arrival latch. It outranks everything below it in screenFor(),
  // and the watchdog that normally clears it is not running during a demo - so
  // starting a demo just after a real arrival would have pinned the display to
  // the ARRIVED screen and ignored every keypress.
  s.showArrival  = false;
  s.arrivedAtMs  = 0;

  /*
    Night, only if somebody asked for it.

    baseline() must NOT force night off - doing that destroyed night mode
    permanently on the road, because night has one writer and CONFIG arrives
    only on connect and on a polarity change. But ui_mock has no phone at all,
    so without an override the night palette is untestable there: the inverted
    set, the amber turn-now bars, the warm text.

    -1 leaves NavState alone, which is the real firmware behaviour and the
    default. The n key sets it.
  */
  if (nightOverride >= 0) s.night = (nightOverride != 0);

  /*
    s.night is deliberately NOT touched.

    It used to be forced false here, and that was the one faked field with no
    way back. Every other value baseline() invents - the clock, the battery -
    is refreshed by PKT_STATUS at about 1 Hz, so it self-heals within a second
    of 'x'. night has exactly one writer, handleConfig, and CONFIG arrives on
    connect and on a polarity change and at no other time.

    So starting a demo at night flooded the panel white, and stopping it left
    the panel white indefinitely. That is precisely the failure the palette
    comments spend two paragraphs arguing must never happen.
  */
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
  geomClear();          // a demo must never inherit the previous one's roads
  juncBuilt = false;
  mode     = m;
  step     = 0;
  stepAtMs = millis();
  rideLeg  = 0;
  rideDist = RIDE_LEGS[0].len;
  arriveAt = 0;
  Serial.printf("demo: %s\n", what);
  displayInvalidate();
}

}  // namespace

// Start a demo without a keypress. The ui_mock sketch uses this to come up
// already riding, since it has no phone to wait for and no BLE to hand back to.
void demoForce(char what) {
  switch (what) {
    case 'g': start(M_GLYPHS, "glyph parade"); break;
    case 'r': start(M_RIDE,   "scripted ride"); break;
    case 'a': start(M_ALERTS, "alerts"); break;
    case 'j': start(M_JUNC,   "junctions"); break;
    case 'f': start(M_FLOW,   "full flow"); break;
    default: break;
  }
}

bool demoActive() { return mode != M_OFF; }

bool demoSerial(NavState& s) {
  if (!Serial.available()) return false;
  const int c = Serial.read();
  switch (c) {
    case 'g': start(M_GLYPHS, "glyph parade - every maneuver, 1.8 s each"); return true;
    case 'r': start(M_RIDE,   "scripted ride");                             return true;
    case 'a': start(M_ALERTS, "alerts - call and message, riding and parked"); return true;
    case 'j': start(M_JUNC,   "junctions - flyover, fork, roundabout");        return true;
    case 'f': start(M_FLOW,   "FULL FLOW - every screen, in ride order");      return true;
    case 'n':
      nightOverride = (nightOverride == 1) ? 0 : 1;
      displayInvalidate();
      Serial.printf("demo: night %s\n", nightOverride ? "ON" : "OFF");
      return true;
    case 'b': displayBootBegin(); displayBootStage(2); displayBootFinish(true);
              displayInvalidate();
              Serial.println("demo: boot replayed"); return true;
    /*
      geomClear on the way OUT, not just on the way in.

      It used to live only in start(), so pressing 'x' left the committed view
      alive for GEOM_MAX_AGE_MS. With a phone connected and a real route
      running, the display then drew the synthetic Kochi roundabout in the
      glyph box - a fabricated map of roads that do not exist, standing where
      the actual instruction should be, for six seconds after the demo was
      supposedly handed back.

      Invisible on the bench, because with no phone UI_DISCONNECTED outranks it
      and hides the symptom. That is what makes it a road bug.
    */
    /*
      ★ AND UNDO WHAT THE DEMO WROTE. Clearing `mode` was never enough.

      demoTick has been writing fabricated NAV into the shared NavState, and
      baseline() has been setting linkUp = true, stale = false and stamping
      lastPacketMs. So after x, with a phone connected, the invented "Fort
      Kochi Beach" maneuver kept rendering as a live instruction - and
      indefinitely, because STATUS packets kept the freshness clock alive.

      nightOverride was the worse half: handleConfig is its only other writer
      and CONFIG arrives on connect and on a solar transition only, so pressing
      n then x left the panel inverted until the next sunrise. That is exactly
      the failure the comment above spends two paragraphs saying must never
      happen, reintroduced through the override.
    */
    case 'x': mode = M_OFF;
              nightOverride = -1;
              s.flags         = 0;
              s.maneuver      = MV_UNKNOWN;
              s.next_maneuver = MV_UNKNOWN;
              s.dist_m        = 0;
              s.next_dist_m   = 0;
              s.instruction[0] = 0;
              s.callState     = 0;
              s.notifyText[0] = 0;
              s.notifySrc[0]  = 0;
              // Hand the watchdog the truth immediately rather than letting it
              // vouch for a demo's timestamps for another ten seconds.
              s.lastPacketMs  = millis() - STALE_MS - 1;
              s.lastNavMs     = millis() - STALE_MS - 1;
              geomClear(); displayInvalidate();
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
      clearAlerts(s);

      // Arrived: hold the arrival screen, then start the route again.
      if (arriveAt) {
        s.flags       = NAV_ACTIVE | NAV_ARRIVED;
        s.showArrival = true;
        s.arrivedAtMs = arriveAt;
        s.maneuver    = MV_DESTINATION;
        s.dist_m      = 0;
        snprintf(s.instruction, INSTRUCTION_MAX, "%s", "Fort Kochi Beach");
        if (now - arriveAt >= 8000) {          // shorter than the real dwell
          arriveAt = 0; rideLeg = 0; rideDist = RIDE_LEGS[0].len;
          displayInvalidate();
        }
        break;
      }

      if (now - stepAtMs >= RIDE_TICK_MS) {
        stepAtMs = now;
        const uint16_t v = (rideDist <= 100) ? SPEED_TURN : SPEED_CRUISE;
        rideDist = (rideDist > v) ? (uint16_t)(rideDist - v) : 0;

        if (rideDist == 0) {
          if (rideLeg + 1 >= RIDE_N) { arriveAt = now; break; }
          rideLeg++;
          rideDist = RIDE_LEGS[rideLeg].len;
        }
      }

      const Leg& leg  = RIDE_LEGS[rideLeg];
      const uint32_t left = routeRemaining();

      /*
        Quantise only what is shown. NAV_DATA.md's measured bands: 100 m above
        500, 50 m from 100 to 500, 10 m below. The phone does this rounding for
        real, and display.cpp deliberately does not re-round, so the demo has to
        arrive with a value that has already been through it.
      */
      const uint16_t q = (rideDist > 500) ? 100 : (rideDist > 100) ? 50 : 10;
      s.dist_m = (uint16_t)((rideDist / q) * q);

      s.maneuver = leg.mv;
      s.flags    = NAV_ACTIVE;
      // 8 m/s is 30 km/h, so metres/8 is seconds; +30 rounds to the nearest
      // minute rather than always down, which is what an ETA does.
      s.eta_min        = (uint16_t)((left / 8 + 30) / 60);
      s.remaining_100m = (uint16_t)(left / 100);
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
        /*
          stepAtMs, NOT now.

          notifyAtMs is an ARRIVAL TIME. Re-stamping it every tick made every
          frame look like a freshly arrived message, and both redraw keys are
          built from it - the parked one in displayRender and the band one on
          the nav path - so the screen repainted at loop rate. That is the
          flicker, on both the riding and the parked alert steps.

          stepAtMs is stable within a step, and ALERT_MS is 3500 against a
          6000 ms dwell, so the alert stays up for the whole step without ever
          claiming to be new.
        */
        s.notifyAtMs = stepAtMs;
      }
      break;
    }

    case M_FLOW: {
      /*
        The whole product, once through, in the order a ride actually happens.

        Every other mode shows one thing well. This one exists to answer a
        different question - does the sequence hold together - and to reach the
        four screens no other mode ever draws: REROUTING, STALE, DISCONNECTED,
        and a real arrival with its 30 s dwell.

        Each phase narrates itself on the serial line, so what is on the panel
        and why is never a guess.
      */
      static const struct { uint32_t ms; const char* say; } PHASE[] = {
        { 4000,  "1/9  parked - clock, PARKED, the road and the resting dot"   },
        { 5000,  "2/9  parked message - takes the whole screen, self-clears"   },
        { 5000,  "3/9  DEPART - head toward, NOT a straight-through arrow"     },
        { 0,     "4/9  riding - bands, alert at 700 m, junction at 300 m"      },
        { 3500,  "5/9  REROUTING - arrow suppressed, the old turn is not true" },
        { 3500,  "6/9  STALE - link up, data stopped"                          },
        { 3500,  "7/9  DISCONNECTED - the link itself is gone"                 },
        { 14000, "8/9  ARRIVED - watch it hold; it repaints itself every 10 s" },
        { 2500,  "9/9  back to parked"                                         },
      };
      const uint8_t PHASE_N = sizeof(PHASE) / sizeof(PHASE[0]);

      if (step >= PHASE_N) step = 0;

      // Phase 3 is the ride and ends on arrival, not on a timer.
      const bool timed = (PHASE[step].ms != 0);
      if (timed && now - stepAtMs >= PHASE[step].ms) {
        step = (step + 1) % PHASE_N;
        stepAtMs = now;
        rideLeg = 0; rideDist = RIDE_LEGS[0].len; arriveAt = 0;
        geomClear();
        displayInvalidate();
        Serial.printf("flow: %s\n", PHASE[step].say);
      }

      clearAlerts(s);
      s.flags = 0;

      switch (step) {
        case 0: case 8:                       // parked
          break;

        case 1:                               // parked, message
          s.notifyKind = NOTIFY_MESSAGE;
          snprintf(s.notifySrc,  ALERT_SRC_MAX,  "%s", "Appa");
          snprintf(s.notifyText, ALERT_TEXT_MAX, "%s", "Reached home safely? Call me");
          s.notifyAtMs = stepAtMs;            // arrival time, not now - see M_ALERTS
          break;

        case 2:                               // departing
          s.flags    = NAV_ACTIVE;
          s.maneuver = MV_DEPART;
          s.dist_m   = 600;
          s.eta_min  = 9;
          s.remaining_100m = 30;
          snprintf(s.instruction, INSTRUCTION_MAX, "%s", "Panampilly Nagar Rd");
          break;

        case 3: {                             // the ride
          if (arriveAt) {                     // reached the end - move on
            step = 4; stepAtMs = now; geomClear(); displayInvalidate();
            Serial.printf("flow: %s\n", PHASE[4].say);
            break;
          }
          if (now - stepAtMs >= RIDE_TICK_MS) {
            stepAtMs = now;
            const uint16_t v = (rideDist <= 100) ? SPEED_TURN : SPEED_CRUISE;
            rideDist = (rideDist > v) ? (uint16_t)(rideDist - v) : 0;
            if (rideDist == 0) {
              if (rideLeg + 1 >= RIDE_N) { arriveAt = now; break; }
              rideLeg++; rideDist = RIDE_LEGS[rideLeg].len;
            }
          }
          const Leg& leg = RIDE_LEGS[rideLeg];
          const uint32_t left = routeRemaining();
          const uint16_t q = (rideDist > 500) ? 100 : (rideDist > 100) ? 50 : 10;

          s.flags    = NAV_ACTIVE;
          s.maneuver = leg.mv;
          s.dist_m   = (uint16_t)((rideDist / q) * q);
          s.eta_min  = (uint16_t)((left / 8 + 30) / 60);
          s.remaining_100m = (uint16_t)(left / 100);
          snprintf(s.instruction, INSTRUCTION_MAX, "%s", leg.road);

          // A message while riding, once, in the far band - where it gets a
          // strip rather than the screen, and where it is allowed at all.
          if (rideLeg == 0 && s.dist_m <= 700 && s.dist_m > 500) {
            s.notifyKind = NOTIFY_MESSAGE;
            snprintf(s.notifySrc,  ALERT_SRC_MAX,  "%s", "Amma");
            snprintf(s.notifyText, ALERT_TEXT_MAX, "%s", "Where are you?");
            s.notifyAtMs = now - 1000;        // steady inside its dwell
          }

          // Junction geometry on the approach to the first real turn.
          if (rideLeg == 1 && s.dist_m <= 400 && s.dist_m >= 150) {
            if (!juncBuilt) { juncFlyover(); juncBuilt = true; }
          } else if (juncBuilt) {
            geomClear(); juncBuilt = false;
          }
          break;
        }

        case 4:                               // rerouting
          s.flags    = NAV_ACTIVE | NAV_REROUTING;
          s.maneuver = MV_TURN_RIGHT;
          s.dist_m   = 240;
          snprintf(s.instruction, INSTRUCTION_MAX, "%s", "Moulana Azad Rd");
          break;

        case 5:                               // stale - link up, data stopped
          s.flags       = NAV_ACTIVE;
          s.maneuver    = MV_TURN_RIGHT;
          s.dist_m      = 240;
          s.stale       = true;
          break;

        case 6:                               // disconnected
          s.linkUp = false;
          break;

        case 7:                               // arrived
          s.flags       = NAV_ACTIVE | NAV_ARRIVED;
          s.showArrival = true;
          s.arrivedAtMs = stepAtMs;
          s.maneuver    = MV_DESTINATION;
          s.dist_m      = 0;
          snprintf(s.instruction, INSTRUCTION_MAX, "%s", "Fort Kochi Beach");
          break;
      }
      break;
    }

    case M_JUNC: {
      /*
        Three junctions on rotation, each rebuilt every tick so the view stays
        inside GEOM_MAX_AGE_MS and the staleness path is exercised rather than
        bypassed. Held at 300 m - the approach band, the one place a junction
        drawing has time to be read.
      */
      bool rebuild = !juncBuilt;
      if (now - stepAtMs >= JUNC_MS) { step = (step + 1) % 3; stepAtMs = now; rebuild = true; }

      static const char* const NAMES[] = { "Flyover, keep right",
                                           "Three-way fork",
                                           "Roundabout, 2nd exit" };
      /*
        Only on a step change. Rebuilding every tick re-stamps the commit time,
        which changes geomKey(), which asks the display to repaint the glyph box
        every loop - a flicker with no new information in it. The rebuild
        interval is well inside GEOM_MAX_AGE_MS, so the view never goes stale
        between steps.
      */
      if (rebuild) {
        if (step == 0)      juncFlyover();
        else if (step == 1) juncFork();
        else                juncRoundabout();
        juncBuilt = true;
      }

      clearAlerts(s);
      // The arrow the phone would have sent anyway. It is suppressed while
      // geometry is up, but it must still be right: below 100 m the geometry
      // stands down and this is what the rider gets.
      s.maneuver = (step == 2) ? (uint8_t)(MV_ROUNDABOUT_EXIT_BASE + 2)
                               : MV_SLIGHT_RIGHT;
      s.flags    = NAV_ACTIVE;
      s.dist_m   = 300;
      s.eta_min  = 9;
      s.remaining_100m = 34;
      snprintf(s.instruction, INSTRUCTION_MAX, "%s", NAMES[step]);
      break;
    }

    default: break;
  }
}
