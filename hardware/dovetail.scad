/*
  dovetail.scad - the male/female interface, defined ONCE.

  ---------------------------------------------------------------------------
  ★ WHY THIS FILE EXISTS

  These constants are needed by two files: mount.scad makes the male, case.scad
  cuts the female. They must agree exactly or the parts do not fit.

  They used to live in mount.scad, which case.scad pulled in with `use`. That
  does not work, and it fails SILENTLY:

    - `use` imports modules but NOT variables. So `dt_h` read from case.scad is
      undef, and any arithmetic on it silently produces nonsense.
    - Worse, case.scad can declare its own dt_* variables in the same
      namespace. A maintainer "documenting the dovetail" in case.scad gets a
      file that reads correctly, renders without a warning, and is wrong. That
      was tested: setting dt_h = 12 in case.scad left the slot cut at 6.0.

  A dimensional audit named this as the highest-risk drift pair in the project.
  So the constants live here, both files `include` this, and there is exactly
  one place to change them.

  ★ NEVER copy a value out of this file into another one. Include it.
*/

// ============================================================ CONSTANTS

/*
  ★ NARROWED from 26/34/6 after a review found the mount plate lid screws
  breaking into the slot: at dt_top 34 the slot half-width was 17.3 while the
  screws inner edge sat at 16.3 - a 1.0 mm intersection, on four screws.

  15/22 over 5 gives a slot half-width of 11.55 and 4.75 mm of clearance. The
  flank is atan(5 / 3.5) = 55 degrees, still self-supporting, and the joint is
  hugely overbuilt either way - a structural review put the dovetail root at
  SF 20 in the direction that matters.
*/
dt_base   = 15.0;   // narrow face, against the plate
dt_top    = 22.0;   // wide face - the part that cannot be pulled straight out
dt_h      = 5.0;
dt_len    = 34.0;
dt_clear  = 0.30;   // printed fit, per face. See the sweep note below.

/*
  ★ PRINT THE SWEEP, NOT A FIT TEST.

  The usual advice is "print a test coupon, judge it, adjust, reprint". That
  assumes iteration, and there is exactly one print here.

  So print the male plate THREE times at dt_clear 0.20 / 0.30 / 0.45, each with
  its number embossed on the face. Try all three, keep the one that slides with
  a firm thumb push and does not rock, and put the other two in the tail bag as
  road spares. About 30 g of filament, and it converts a number that has to be
  guessed right into one that is simply selected.
*/

// ============================================================ PROFILE

/*
  ★ ONE profile, grown by offset() for the female.

  The first version added dt_clear as a pure X offset to the polygon's corners
  while also raising the top by dt_clear. That adds rise without run, so the
  female flank was NOT parallel to the male's - 0.255 mm of clearance at the
  root and 0.091 mm at the tip. 0.091 is inside a normal printer's error before
  elephant's foot is counted, so it would have bound at the tip while being
  sloppy at the root, and raising dt_clear could never fix both at once.

  offset(delta) moves every edge along its own normal, so the flanks stay
  exactly parallel and the clearance is uniform. Verified: at delta = 0.30 the
  slope stays 4.4/6.6 = 0.6667, identical to the male's 4/6.
*/
module dt_profile(grow = 0) {
    offset(delta = grow)
        polygon([[-dt_base / 2, 0], [ dt_base / 2, 0],
                 [ dt_top  / 2, dt_h], [-dt_top  / 2, dt_h]]);
}

// Male: a straight extruded taper. No undercut, nothing to bridge - which is
// the whole reason this replaced a three-lug bayonet.
module dovetail_male(len = dt_len) {
    translate([0, len / 2, 0]) rotate([90, 0, 0])
        linear_extrude(len) dt_profile(0);
}

/*
  Female. REQUIRES a length - there is no default on purpose.

  Cut at its own length it is a closed rectangular pocket that nothing can ever
  slide into. That mistake has been made three times in this project: on the
  quarter-turn receiver, on the first back-plate, and on the mount plate. It
  renders correctly every time, which is exactly why it keeps surviving
  inspection. Making the argument mandatory forces the caller to think about
  which end is open.
*/
module dovetail_female(len) {
    assert(!is_undef(len),
           "dovetail_female needs a length - and it must run out to an edge, or nothing can slide in");
    translate([0, len / 2, -0.01]) rotate([90, 0, 0])
        linear_extrude(len) dt_profile(dt_clear);
}
