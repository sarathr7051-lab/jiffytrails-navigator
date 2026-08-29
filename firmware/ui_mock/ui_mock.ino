/*
  ui_mock.ino - the whole interface, no phone, no BLE.

  Upload this to look at the display. It boots straight into the scripted ride
  from Panampilly Nagar to Fort Kochi Beach and runs it on a loop: distances
  count down at a real speed, the screen crosses every band, every maneuver
  glyph appears, and the route ends on the arrival screen before starting over.

  It renders through the navigator's own display.cpp and glyph tables - see
  src/shared.cpp - so it cannot show you a UI the device does not have. That is
  the one thing the old ui_mock could not promise, and the reason it was
  eventually showing arrows the firmware had stopped drawing.

  Serial, 115200:
    f   the FULL FLOW - every screen in ride order (this is where it starts)
    n   toggle night mode - there is no phone here to send it
    r   the scripted ride
    g   glyph parade - every maneuver, named as it draws
    a   alerts - call and message, riding and parked
    b   replay the boot sequence
    x   freeze on the current frame

  The other sketch, firmware/navigator/, is the real thing: same screens, but
  driven by the phone over BLE. It has the same serial keys, so anything you
  find here can be reproduced there without unplugging anything.

  Hardware and the TFT_eSPI config trap are in docs/HARDWARE.md. Read the
  sketchbook section there before editing any User_Setup.h.
*/

#include "src/nav_types.h"
#include "src/display.h"
#include "src/demo.h"

// The one instance, exactly as the navigator has it. The demo writes it and
// the display reads it; nothing here decides anything in between.
static NavState state;

void setup() {
  Serial.begin(115200);
  delay(200);
  Serial.println(F("\nJiffyTrails ui_mock - display only, no phone"));
  Serial.println(F("keys: r ride   g glyphs   a alerts   b boot   x freeze"));

  displayBegin();

  // The same boot sequence the real firmware plays, minus the wait for a
  // phone. The waypoint finishes hollow rather than amber, because there is no
  // radio in this build and a filled dot would be claiming a link that cannot
  // exist - the same lie as a stale maneuver, just prettier.
  displayBootBegin();
  displayBootStage(1);
  displayBootStage(2);
  displayBootFinish(false);

  // Straight into the full flow: every screen, in the order a ride happens.
  demoForce('f');
}

void loop() {
  demoSerial();
  demoTick(state);
  displaySetNight(state.night);
  displayTick();          // no-op unless MISO is wired; see displayBegin's probe
  displayRender(state);
}
