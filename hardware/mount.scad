/*
  JiffyTrails mount - ONE printed part.

  Open in OpenSCAD, set `part`, press F6, File > Export > STL.

  ---------------------------------------------------------------------------
  WHAT THIS IS

  A flat plate with the dovetail ridge on top. It bolts to the BOBO BM4's own
  aluminium phone plate. That is the whole mount.

      handlebar -> BM4 clamp -> ball -> collet + collar -> arm
        -> BM4's splined joint + brass thumbscrew   <- untouched, still yours
        -> BM4's aluminium plate                    <- untouched, still yours
        -> THIS PART                                <- the only thing printed
        -> case slides down onto the dovetail, pin locks it

  ---------------------------------------------------------------------------
  ★ WHY THERE IS NO PRINTED BALL CLAMP HERE ANY MORE

  Two earlier versions of this file tried to print one - first a quarter-turn
  bayonet, then a two-piece bolted clamp. Fourteen defects between them, and
  underneath those a result that killed the whole idea: a RIGID printed socket
  has no working size. Bigger than the ball and it touches at the rim with the
  clearance growing as you tighten; smaller and it is two knife edges at
  284 MPa, six times ASA's yield at 60 C; exactly equal and there is no
  interference, so no grip at all.

  All of which was solving a problem that did not exist. The rider has the
  entire BM4 mount - clamp, ball, collet, collar, arm and aluminium plate. Only
  the JAW that grips the phone broke, and we are not using the jaw.

  ★ AND DO NOT PRINT A MATING SPLINE. The BM4's plate joint is a Hirth
  coupling - two discs of radial teeth squeezed by one screw. Hirth halves have
  to be made as a MATCHED PAIR; two separately manufactured halves mismatch and
  lose 50-70% of their capacity, and FDM cannot hold that tooth pitch against
  an injection-moulded mate. Printed Hirth joints do work when BOTH halves are
  printed together - which is not our case. Bolt to the aluminium plate and let
  BOBO's own matched pair do its job.

  ---------------------------------------------------------------------------
  IT ALSO MAKES THE LOAD SMALLER

  The load on the ball is a moment - case weight times its distance from the
  ball centre. Keeping BOBO's metal arm and plate gives the shortest stack of
  anything considered:

      two printed cups + dovetail plate     17.0 mm   ->  289 N of clamp force
      one cup with an integral dovetail     31.5 mm   ->  393 N
      THIS: BM4 arm + plate + adapter       11.0 mm   ->  245 N

  So the proven metal ball joint is being asked for about 25% LESS than the
  printed clamp would have needed. Nothing anywhere is stretched.
*/

include <dovetail.scad>

$fn = 48;

// ============================================================ PARAMETERS

plate_w   = 56.0;
plate_l   = 46.0;
plate_t   = 6.0;
plate_r   = 4.0;

/*
  ★ M4 MINIMUM, AND 0.4 N.m MAXIMUM.

  Head bearing stress on ASA, which yields near 15 MPa sustained at 60 C:

      M4 at 0.4 N.m   500 N   14.6 MPa   ok
      M4 at 1.0 N.m  1250 N   36.4 MPa   crushes it
      M4 at 2.0 N.m  2500 N   72.8 MPa   crushes it
      M3 at 0.4 N.m           35.7 MPa   crushes it even at design torque

  So M3 is not "a smaller option", it is wrong. And there is no torque figure
  to hit - nip it up until it stops turning easily and stop. Use nyloc nuts or
  threadlock, because you cannot hold this joint with tension.
*/
bolt_d    = 4.5;    // M4 clearance
cbore_d   = 8.5;    // counterbore so heads sit flush - they foul the case
cbore_t   = 3.0;    // mount plate otherwise

/*
  AMPS is the industry four-hole pattern: 38 x 30 mm. Screw size is NOT part of
  the standard (M4 and M5 both appear), so drill to fit whatever you have.

  The 38 mm span has to run ACROSS the dovetail - the other way round does not
  fit on this plate.
*/
amps_x    = 19.0;   // 38 mm span, across the dovetail
amps_y    = 15.0;   // 30 mm span, along it

// ============================================================ DERIVED

plate_h   = plate_t + dt_h;

/*
  ★ WHERE IT IS SAFE TO DRILL, if you drill the blank yourself.

  |x| between 12 and 25 mm, ANY y. That keeps clear of the dovetail root on the
  inside and the plate edge on the outside.

  Do NOT drill near the ends. The dovetail runs the full 34 mm, so there is
  only 6 mm of plate beyond it there - not enough for a bolt head.
*/
drill_x_min = dt_top / 2 + 1.0;
drill_x_max = plate_w / 2 - cbore_d / 2 - 2.0;

echo(str("plate ", plate_w, " x ", plate_l, " x ", plate_t, ", total height ", plate_h));
echo(str("safe drilling zone: |x| = ", drill_x_min, " to ", drill_x_max, ", any y"));

// ============================================================ ASSERTS

/*
  Every one of the fourteen defects in the two failed versions of this file was
  a collision or a sign error - not one was a judgement call. These lines are
  the design review, and they run on F5.
*/
assert(drill_x_max > drill_x_min + 4,
       "no usable drilling zone - plate too narrow or dovetail too wide");
assert(amps_x - cbore_d/2 > dt_top/2 + 1.0,
       "AMPS counterbore fouls the dovetail overhang");
assert(amps_x + cbore_d/2 < plate_w/2 - 2.0,
       "AMPS counterbore too close to the plate edge");
assert(amps_y + cbore_d/2 < plate_l/2 - 2.0,
       "AMPS counterbore runs off the end of the plate");
assert(dt_len <= plate_l,
       "dovetail longer than the plate it sits on");
assert(atan(dt_h / ((dt_top - dt_base)/2)) > 45,
       "dovetail flank not self-supporting - it needs support material");
assert(cbore_t < plate_t - 1.5,
       "counterbore leaves too little material under the bolt head");

// ============================================================ PARTS

module rrect(w, l, h, r) {
    hull() for (x = [-1, 1], y = [-1, 1])
        translate([x*(w/2 - r), y*(l/2 - r), 0]) cylinder(h = h, r = r);
}

module plate_body() {
    rrect(plate_w, plate_l, plate_t, plate_r);
    translate([0, 0, plate_t]) dovetail_male(dt_len);
}

/*
  ★ THE ONE TO PRINT. A blank - no holes at all.

  Lay it on the BM4's aluminium plate, mark through that plate's own holes with
  a nail, and drill. A blank fits 100% of bolt patterns with zero measurement,
  which is strictly better than any pattern guessed from a photograph - and it
  means nothing has to be measured before the print goes on the bed.

  Drill 4.5 mm through, then open the top 3 mm with an 8 mm bit so the heads
  sit flush. Or use countersunk M4. Proud heads foul the case's mount plate.
*/
module adapter_blank() {
    plate_body();
}

/*
  Fallback, if the aluminium plate turns out unusable and a commercial 17 mm
  ball AMPS plate is bought instead (~800-1200 rupees, fully known numbers).
*/
module adapter_amps() {
    difference() {
        plate_body();
        for (x = [-1, 1], y = [-1, 1]) translate([x*amps_x, y*amps_y, -0.1]) {
            cylinder(h = plate_h + 1, d = bolt_d);
            cylinder(h = cbore_t + 0.1, d = cbore_d);
        }
    }
}

// A 14 mm slice, printed in the SAME orientation on the SAME plate, so it can
// be tried in each mount-plate variant by hand before anything is bolted up.
module dovetail_stub() {
    intersection() {
        plate_body();
        translate([-plate_w, -7, -1]) cube([2*plate_w, 14, plate_h + 2]);
    }
}

// ============================================================ LAYOUT

part = "blank";   // "blank" "amps" "stub" "all"

if      (part == "blank") adapter_blank();
else if (part == "amps")  adapter_amps();
else if (part == "stub")  dovetail_stub();
else {
    adapter_blank();
    translate([plate_w + 8, 0, 0]) adapter_amps();
    translate([0, plate_l + 10, 0]) dovetail_stub();
}

/*
  ★ PRINT ORIENTATION: FLAT, DOVETAIL UP. No supports, and none are needed.

  The dovetail's flanks sit at 55 degrees from horizontal, comfortably
  self-supporting. Layers then run in the plate's plane, so the bending load is
  along them - the strong direction - rather than across them.

  0.2 mm layers, 5 perimeters, 40% infill. About 17 g each.

  ---------------------------------------------------------------------------
  ★ ONE THING THE PIVOT COST US, AND HOW TO GET IT BACK

  The abandoned printed clamp carried a 2 mm butyl liner, and that rubber was
  doing real damping - it cut the assembly's resonant Q from about 50 to about
  7. Bolting metal to plastic gets none of that.

  case.scad already puts foam in the dovetail slot, which helps. Add a thin
  rubber sheet between this plate and the BM4's aluminium one as well. Cut it
  from the same inner tube, it costs nothing, and it recovers most of what the
  liner was doing.
*/
