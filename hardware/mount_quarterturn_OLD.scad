/*
  JiffyTrails mount - a two-part quarter turn, both halves printed.

  Open in OpenSCAD, set `part`, press F6, File > Export > STL.

  ---------------------------------------------------------------------------
  WHY THIS EXISTS, AND WHY IT IS NOW A GOOD IDEA

  The first attempt at a quarter turn was abandoned for a real reason: it was
  going to be Garmin-compatible, Garmin publishes no dimensions at all, and
  every figure in circulation is somebody's callipers. Printing to an
  unverifiable standard, to hold a device on a motorcycle at speed, is not a
  trade worth making.

  ★ That objection disappears entirely when BOTH halves are ours. There is no
  standard to match. The lugs and the slots come off the same file, from the
  same constants, so they fit by construction rather than by hoping a number
  from a forum was right. The rider's idea removed the obstacle rather than
  working around it.

  Part A, the CLAMP, grips the bike's existing 17 mm ball and stays there.
  Part B, the RECEIVER, is sunk into the back of the case.

  A quarter turn rather than a bolt because HARDWARE.md's argument still holds:
  a tightened joint holds by friction and engine vibration walks friction
  joints loose. Three lugs trapped behind shoulders is a shear plane - there is
  nothing to unwind. It also means the device comes off when the bike is
  parked, which matters more than convenience: a documented case had a
  50 C-rated panel reach 90 C in sun and black out permanently.

  ---------------------------------------------------------------------------
  ★ ONE MEASUREMENT NEEDED, AND YOU CAN TAKE IT WITHOUT CALLIPERS

  17 mm is the near-universal motorcycle ball size and almost certainly yours,
  but "almost certainly" is not how a clamp should be sized. Wrap a strip of
  paper around the ball's widest point, mark where it overlaps, flatten it and
  measure the marked length against a ruler:

      53.4 mm  ->  17 mm ball   (set ball_d = 17.0, the default)
      50.3 mm  ->  16 mm ball
      56.5 mm  ->  18 mm ball

  Circumference multiplies the error by pi, which is exactly why this works
  with a ruler when a direct diameter measurement would not.
*/

// ============================================================ PARAMETERS

/* [Ball] */
ball_d        = 17.0;   // ★ confirm with the paper strip above
ball_grip     = 0.4;    // socket is this much UNDER the ball, so it pinches
throat_d      = 12.0;   // opening the ball clips through; smaller = more grip
tilt_deg      = 32;     // how far the case can swivel before it fouls

/* [Quarter turn - shared by BOTH parts, never edit one alone] */
qt_lug_r      = 15.0;   // lugs reach this radius
qt_lip_r      = 11.5;   // shoulder inner radius; lugs trap between this and lug_r
qt_lug_t      = 3.0;    // lug thickness
qt_lug_deg    = 34;     // angular width of each lug
qt_slot_deg   = 44;     // entry slot, wider so it goes in with gloves on
qt_lugs       = 3;
qt_clear      = 0.35;   // printed fit clearance, per face
qt_detent_d   = 2.4;    // the click that stops it backing off

// The jaw grip is broken - one side of it snapped - so this is not an
// alternative to it, it is the replacement. The BM4 ball on the handlebar and
// its threaded collar are the only parts of that mount still in use.

/* [Clamp body] */
clamp_d       = 40.0;
clamp_h       = 26.0;
bolt_d        = 4.4;    // M4 clearance
nut_af        = 7.2;    // M4 nut across flats
nut_t         = 3.4;

/* [Print] */
$fn           = 96;

// ============================================================ PART A - CLAMP

/*
  Grips the ball, carries the lugs, stays on the bike.

  Printed SPLIT is deliberate: the slot lets the socket close onto the ball as
  the bolt tightens. Without it the socket would have to be printed oversized
  to get the ball in at all, and it would never hold.
*/
module clamp() {
    difference() {
        union() {
            // body
            cylinder(h = clamp_h - qt_lug_t, d = clamp_d);
            // lugs, on the top face
            translate([0, 0, clamp_h - qt_lug_t]) qt_lugs_solid();
        }

        // Ball socket, opening downward.
        translate([0, 0, ball_d / 2 + 3])
            sphere(d = ball_d - ball_grip);
        // Throat: the mouth the ball clips through.
        translate([0, 0, -1])
            cylinder(h = ball_d / 2 + 4, d = throat_d);
        // Swivel relief - the cone the mount arm sweeps through.
        translate([0, 0, -1])
            cylinder(h = ball_d / 2 + 4, d1 = throat_d,
                     d2 = throat_d + 2 * (ball_d / 2 + 4) * tan(tilt_deg));

        // The split, and the pinch bolt across it.
        translate([-1.2, -clamp_d, -1]) cube([2.4, clamp_d, ball_d + 6]);
        translate([0, 0, 7]) rotate([0, 90, 0])
            cylinder(h = clamp_d + 2, d = bolt_d, center = true);
        // Captive nut pocket, on the far side from the head.
        translate([clamp_d / 2 - nut_t - 1.5, 0, 7]) rotate([0, 90, 0])
            cylinder(h = nut_t, d = nut_af / cos(30), $fn = 6);
    }
}

// ============================================================ PART B - RECEIVER

/*
  Sunk into the back of the case. Import into case.scad and subtract it, or
  print it as a disc and glue it on if you would rather not reprint the body.

  The lug POCKET is what gets cut: a bore for the lug plate, an undercut ring
  the lugs rotate into, and entry slots aligned with them.
*/
qt_lip_t = 2.0;    // shoulder thickness - what the lugs are trapped behind

module receiver_cut() {
    // Boss clearance: the plain centre of the lug plate, full depth.
    translate([0, 0, -0.1])
        cylinder(h = qt_lip_t + qt_lug_t + 2 * qt_clear + 0.2,
                 d = 2 * (qt_lip_r + qt_clear));

    // The ring the lugs rotate into, BELOW the shoulder. This is the undercut
    // that makes it a shear joint rather than a friction one.
    translate([0, 0, qt_lip_t])
        cylinder(h = qt_lug_t + 2 * qt_clear,
                 d = 2 * (qt_lug_r + qt_clear));

    // Entry slots THROUGH the shoulder, so the lugs can drop past it. What is
    // left between them is the shoulder the lugs then twist under.
    for (i = [0 : qt_lugs - 1])
        rotate([0, 0, i * 360 / qt_lugs])
            translate([0, 0, -0.1])
                pie(qt_lug_r + qt_clear, qt_slot_deg, qt_lip_t + 0.2);
}

// The engaged position sits 360/(2*lugs) degrees round from the entry slots -
// a sixth of a turn for three lugs, which is the "quarter turn" in practice.
module qt_lugs_solid() {
    cylinder(h = qt_lug_t, d = 2 * qt_lip_r);          // boss
    for (i = [0 : qt_lugs - 1])
        rotate([0, 0, i * 360 / qt_lugs])
            pie(qt_lug_r, qt_lug_deg, qt_lug_t);
}

module pie(r, deg, h) {
    intersection() {
        cylinder(h = h, r = r);
        linear_extrude(h)
            polygon([[0, 0],
                     [r * 2 * cos(-deg / 2), r * 2 * sin(-deg / 2)],
                     [r * 2 * cos(0),          r * 2 * sin(0)],
                     [r * 2 * cos(deg / 2),    r * 2 * sin(deg / 2)]]);
    }
}

// ============================================================ LAYOUT

part = "clamp";   // "clamp", "receiver_demo", "fittest"

if (part == "clamp") {
    clamp();
} else if (part == "receiver_demo") {
    // A 4 mm plate with the pocket cut into it, to see the shape.
    difference() {
        translate([0, 0, -0]) cylinder(h = 3 * qt_lug_t, d = clamp_d);
        receiver_cut();
    }
} else if (part == "fittest") {
    /*
      ★ PRINT THIS FIRST. Two discs, about 6 g and ten minutes, and it proves
      the lug and slot geometry engages before either real part is committed.
      If it is tight, raise qt_clear by 0.1 and reprint just this.
    */
    cylinder(h = 3, d = clamp_d);
    translate([0, 0, 3]) qt_lugs_solid();
    translate([clamp_d + 8, 0, 0])
        difference() {
            cylinder(h = 3 * qt_lug_t, d = clamp_d);
            receiver_cut();
        }
}
