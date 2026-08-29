/*
  JiffyTrails enclosure - parametric, printable.

  Open in OpenSCAD (free, openscad.org), press F6, then File > Export > STL.
  Every dimension worth changing is at the top; nothing below the PARAMETERS
  block needs editing to get a different fit.

  Print in ASA, light coloured. Not PETG and never PLA - docs/HARDWARE.md has
  the arithmetic: PETG's HDT is 65-80 C against an estimated sealed interior of
  53-70 C in Bengaluru sun, and an 18 C interior difference has been measured
  between dark-grey and light-grey enclosures. ASA gives ~105 C service and
  does not yellow.

  0.2 mm layers, 4 perimeters (the mount lugs carry all the load), 30-40%
  infill.

  ORIENTATION: BODY MOUNT-FACE DOWN. LID SEALING-FACE DOWN, HOOD UP.

  This used to say "sealing face flat on the bed" for the body, which is
  backwards and loses the print. Sealing-face-down, the body's first layer is a
  282 mm picture-frame loop 1.2 mm wide - 338 sq mm of bed contact on a part
  that shrinks half a percent - and the tub floor then has to bridge 52 x 88 mm
  of open air.

  Mount-face down gives a full 57 x 93 mm first layer, puts the sealing rim on
  top where it prints accurately with no elephant's foot, and turns the
  quarter-turn undercut into a hole opening upward rather than an overhang.

  ---------------------------------------------------------------------------
  ★ TWO THINGS TO DO BEFORE YOU PRINT

  1. THE BOARD NUMBERS ARE NOW MEASURED, not assumed - see
     docs/COMPONENT_DIMENSIONS.md, which traced the display to an LCDWIKI
     MSP2806 and found a dimensioned drawing. Two of the first version's
     assumptions were wrong and both would have ruined a print: the module is
     4.40 mm thick rather than the bare PCB's 1.6, and its glass sits 4.90 mm
     off centre. Change them only against a better source.

  2. DECIDE THE WINDOW. HARDWARE.md flags a real conflict: a polycarbonate
     window with an air gap in front of the panel adds two air/plastic
     interfaces at ~4% reflection each, and air-gap stacks lose 8-20% of light
     against under 5% for bonded ones. On a 250-nit panel already losing to
     glare that is unaffordable.

     window_mode = "none"  - the bezel seals against the panel's own glass.
                             Best optically. Requires a clean gasket line on
                             the module's glass, so measure that face.
     window_mode = "bonded"- 2 mm polycarbonate optically bonded to the panel
                             with clear silicone. No air layer, and the case
                             does not care which you choose - the aperture is
                             the same. Set it for the record.

     There is deliberately no air-gap option. It is the obvious build and it is
     the one the numbers reject.
*/

// ============================================================ PARAMETERS

/* [Boards - MEASURE THESE] */
// Display module PCB, the 2.8" ILI9341 carrier
disp_pcb_w      = 50.0;    // across the short edge
disp_pcb_l      = 86.0;    // along the long edge
disp_pcb_t      = 4.40;   // ★ MODULE thickness, glass+tape+PCB - NOT the bare
                           // 1.6 mm PCB. At 1.6 the lid pressed on the glass.
// Active glass area, centred on the PCB unless you say otherwise
disp_active_w   = 43.2;
disp_active_l   = 57.6;
disp_active_off = 4.90;   // ★ NOT centred. The COG driver eats 8.7 mm of border
                           // at the header end against 2.9 at the far end, so
                           // the glass sits 4.90 toward the far end. At 0 the
                           // aperture crops picture on one side and shows bare
                           // PCB on the other.

// ESP32 WEMOS LOLIN32
mcu_w           = 25.4;
mcu_l           = 58.0;
/*
  HARD-WIRED, so no headers. 1.6 PCB + the tallest thing on the top face,
  which is NOT the WROOM module (3.10) or the USB-C receptacle (~3.2) but the
  JST LiPo connector at ~6 mm - and we do not even use it.

  Desoldering that connector would save about 3 mm of case thickness. Worth
  knowing; not worth a first-time solderer risking the board over.
*/
mcu_stack       = 7.6;
perf_t          = 1.6;     // the perfboard itself

/*
  ★ THE DISPLAY HEADER DECIDES THE THICKNESS.

  The module ships with a 9-pin male header soldered to it, and those pins face
  straight at the perfboard. There is no arrangement where they are simply
  ignored, so pick how they are dealt with - the three answers differ by 11 mm
  of case.

  "plug"      Header pins go THROUGH the perfboard, into the hole grid they
              already match at 2.54 mm, and are soldered on the far side and
              clipped flush. No desoldering, nine fewer wires, and the joint is
              mechanical as well as electrical. The ESP32 then lives on the
              BACK face of the perfboard. RECOMMENDED.

  "removed"   Header desoldered, wires soldered into the bare holes. Thinnest,
              and the hardest thing in this whole build for a first-time
              solderer - nine pins in a shared plastic strip cannot be removed
              one at a time, and a lifted pad is unrepairable here.

  "clearance" Header left alone, short jumpers to the board. Easiest to build
              and worst to own: a 31 mm case, and nine connectors that engine
              vibration is free to work loose.
*/
header_mode     = "plug";
header_gap      = (header_mode == "plug")      ? 2.5     // plastic strip only
                : (header_mode == "clearance") ? 11.5    // strip plus full pin
                :                                1.5;    // "removed" - just air
disp_gap        = header_gap;

/* [Shell] */
wall            = 2.4;     // 4 perimeters at 0.4 mm nozzle, sealed
floor_t         = 2.4;
lid_t           = 2.4;
inner_clear     = 1.2;     // slop around the boards
corner_r        = 4.0;

/* [Seal] */
// Form-in-place gasket: print the groove, fill with clear RTV, close the case
// over cling film and let it cure. About 30 rupees and a perfect match.
gasket_w        = 2.0;
gasket_d        = 1.5;

/* [Hood] */
// The largest single readability gain available - worth more than any
// backlight change. Matte black, ribbed inside. Print separately if you want
// two colours; it bolts to the same bezel face.
hood_depth      = 30.0;    // 25-35 in HARDWARE.md; 30 is the middle
hood_rake       = 12;      // degrees, top lip forward to shade a low sun
hood_ribs       = 5;

/* [Openings] */
/*
  ★ HOLE SIZES CARRY PRINT COMPENSATION. A 0.4 mm nozzle undersizes a vertical
  hole by 0.1-0.25 mm on diameter; a HORIZONTAL hole loses that plus 0.2-0.4 mm
  at the unsupported crown, where it also droops out of round. Both of these
  are horizontal, and both are sealing surfaces, so nominal is not good enough.
  They are also teardropped - see teardrop_x() - so the crown self-supports.
*/
vent_d          = 3.4;     // ePTFE vent. Nominal 3.0 + 0.4 print allowance.
                           // Do not omit this hole - HARDWARE.md has the
                           // thermal arithmetic and it is what stops the case
                           // pumping water in as it cools.
gland_d         = 8.8;     // M8 gland needs an 8.5 mm panel hole; 8.0 printed
                           // horizontally comes out near 7.6 and oval, and the
                           // thread will not pass. 8.8 lands on 8.5.
                           // MEASURE THE CABLE FIRST - paper strip round it,
                           // circumference / 3.14. Over 5 mm needs a PG7, whose
                           // 12.5 mm hole does NOT fit a 15.1 mm cavity wall;
                           // tell me and the case grows to suit.
gland_x         = 0;       // offset across the end wall, to dodge the USB port

/* [Fasteners] */
// Blind bosses: the screw never breaches the sealed volume.
screw_d         = 3.0;
boss_d          = 7.0;
boss_blind_t    = 1.6;     // material left at the bottom of the hole

/* [Mount] */
/*
  DOVETAIL SLOT in the back - see hardware/mount.scad, which owns the profile.

  This was a three-lug quarter turn until a structural review took it apart.
  The lugs could not clear the shoulder, the ring left 0.7 mm of free axial
  play with nothing preloading it, and the detent that was supposed to stop it
  backing off existed only in the documentation. A bayonet is an undercut, and
  an undercut is the hardest thing to print correctly.

  A dovetail is a straight extruded taper. Same shear joint, nothing to bridge,
  and one M3 thumbscrew locks it positively instead of by friction.
*/
use <mount.scad>
mount_dovetail  = true;    // false prints a plain back, decide the mount later
/*
  Deep enough for the 6 mm dovetail plus 2 mm of backing, so the slot never
  reaches the sealed floor. The floor is the face this whole enclosure exists
  to keep watertight; nothing gets cut into it.
*/
dt_boss_t       = 8.0;

/* [Choices] */
window_mode     = "none";  // "none" or "bonded" - see the header
$fn             = 64;

// ============================================================ DERIVED

inner_w = disp_pcb_w + 2 * inner_clear;
inner_l = disp_pcb_l + 2 * inner_clear;
// The stack, floor upward: ESP32, perfboard, the header gap, then the display
// facing out through the lid. Totals with a 2.4 floor and a 2.4 lid:
//
//     "plug"       4.4 + 2.5 + 1.6 + 7.6 + 1.0  =  17.1  ->  21.9 mm case
//     "removed"    4.4 + 1.5 + 1.6 + 7.6        =  15.1  ->  19.9 mm case
//     "clearance"  4.4 + 11.5 + 1.6 + 7.6 + 1.0 =  26.1  ->  30.9 mm case
//
// Two millimetres is what "plug" costs over desoldering a nine-pin header by
// hand. That is a good trade.
inner_h = perf_t + mcu_stack + disp_gap + disp_pcb_t + ((header_mode == "removed") ? 0 : 1.0);

body_w  = inner_w + 2 * wall;
body_l  = inner_l + 2 * wall;
body_h  = inner_h + floor_t + lid_t;

// Screw positions: inset from each corner, clear of the boards.
boss_inset = wall + boss_d / 2 - 0.4;

// ============================================================ PARTS

module rrect(w, l, h, r) {
    hull() for (x = [-1, 1], y = [-1, 1])
        translate([x * (w / 2 - r), y * (l / 2 - r), 0])
            cylinder(h = h, r = r);
}

/*
  ★ TEARDROP, not a circle, for every HORIZONTAL hole.

  A round hole printed with its axis horizontal has an unsupported crown: the
  top of the bore is a bridge over its own diameter, and it sags. On an 8.8 mm
  gland hole that is a 0.2-0.4 mm droop, out of round, on the exact face a
  gland's washer has to seal against - and the usual repair is to drill a
  finished, sealed part, dropping swarf inside it.

  A teardrop puts a 45 degree roof over the bore so every layer is supported by
  the one below. The flat flanks rise from the circle's 45 degree chord to an
  apex at r*sqrt(2), which is exactly 45 degrees and prints unsupported. The
  bore stays fully round everywhere a seal touches it; only the waste above the
  centreline changes shape.
*/
module teardrop_2d(d) {
    r = d / 2;
    union() {
        circle(r = r);
        polygon([[-r * cos(45), r * sin(45)],
                 [ r * cos(45), r * sin(45)],
                 [ 0,           r * sqrt(2)]]);
    }
}

// Axis along Y (through an end wall), apex toward +Z.
module teardrop_y(d, h) {
    rotate([90, 0, 0]) linear_extrude(h, center = true) teardrop_2d(d);
}

// Axis along X (through a side wall), apex toward +Z.
module teardrop_x(d, h) {
    rotate([90, 0, 0]) rotate([0, 90, 0])
        linear_extrude(h, center = true) teardrop_2d(d);
}

// The sealed tub: boards live here, screws never break through the floor.
module body() {
    difference() {
        rrect(body_w, body_l, body_h - lid_t, corner_r);

        // Cavity
        translate([0, 0, floor_t])
            rrect(inner_w, inner_l, inner_h + 1, max(0.5, corner_r - wall));

        // Gasket groove, in the sealing face
        translate([0, 0, body_h - lid_t - gasket_d])
            difference() {
                rrect(inner_w + wall, inner_l + wall, gasket_d + 1, corner_r - 0.8);
                translate([0, 0, -0.5])
                    rrect(inner_w + wall - 2 * gasket_w,
                          inner_l + wall - 2 * gasket_w, gasket_d + 2,
                          max(0.5, corner_r - 0.8 - gasket_w));
            }

        // Cable gland, through the LOWER END WALL. Drip loop hangs below it.
        //
        // This used to sit at y = -body_l/2 + 22, which is 22 mm INSIDE the
        // cavity - the hole cut nothing at all and the box printed sealed.
        // It has to be centred on the wall plane to pierce it.
        translate([gland_x, -body_l / 2, floor_t + inner_h / 2])
            teardrop_y(gland_d, wall * 3);

        // Pressure vent. A sealed box in the sun reaches 60 C+, and cold rain
        // then contracts the air and pulls water past the gasket. The part most
        // DIY builds leave out, and the reason they flood.
        translate([body_w / 2 - wall, 0, floor_t + inner_h - 5])
            teardrop_x(vent_d, wall * 3);
    }

    // Blind screw bosses
    for (x = [-1, 1], y = [-1, 1])
        translate([x * (body_w / 2 - boss_inset), y * (body_l / 2 - boss_inset), floor_t])
            difference() {
                cylinder(h = inner_h - gasket_d, d = boss_d);
                translate([0, 0, boss_blind_t])
                    cylinder(h = inner_h, d = screw_d * 0.85);   // self-tapping
            }
}

// The lid carries the window aperture and the hood.
module lid() {
    difference() {
        union() {
            rrect(body_w, body_l, lid_t, corner_r);
            // Hood follows the APERTURE, not the lid. The glass sits 4.90 mm
            // off centre, so a hood centred on the lid shades one edge of the
            // picture and throws the rest of its shadow onto bare plastic.
            translate([0, disp_active_off, lid_t]) hood();
        }

        // Viewing aperture. Same for both window modes - the difference is
        // whether polycarbonate is bonded in front of the glass, not the hole.
        translate([0, disp_active_off, -1])
            rrect(disp_active_w, disp_active_l, lid_t + 2, 1.5);

        // Screw clearance
        for (x = [-1, 1], y = [-1, 1])
            translate([x * (body_w / 2 - boss_inset), y * (body_l / 2 - boss_inset), -1])
                cylinder(h = lid_t + 2, d = screw_d + 0.4);
    }
}

/*
  Matte black, ribbed inside. Print separately in black if you can - it is the
  one part where colour does real work rather than looking nice.

  ★ SHEARED, NOT ROTATED. This is the fix for the worst defect in the lid.

  It used to be `rotate([hood_rake,0,0])` applied to the whole 30 mm tube,
  followed by a flat cut removing everything below z=0. Rotating a tube about
  its base lifts one side of the base off the plane: the far wall's bottom edge
  rose to 32.2 x sin(12) = 6.69 mm, and the flat cut only removes material
  BELOW z=0, so it never brought that wall back down. The result was a 6.7 mm
  tall open slot along half the hood's perimeter, immediately beside an already
  open aperture - a forward-facing scoop feeding rain straight into the case at
  road speed. It also made the true hood height 36 mm rather than 30.

  A shear leans the walls while leaving the base plane exactly where it is. The
  bottom face stays flat and fully seated all the way round, the walls end up
  12 degrees off vertical (78 degrees from horizontal - comfortably printable),
  and there is nothing to bridge.
*/
hood_shear = [[1, 0, 0,                0],
              [0, 1, -tan(hood_rake),  0],
              [0, 0, 1,                0],
              [0, 0, 0,                1]];

module hood() {
    hood_ow = disp_active_w + 2 * wall + 2;
    hood_ol = disp_active_l + 2 * wall + 2;

    difference() {
        multmatrix(hood_shear) rrect(hood_ow, hood_ol, hood_depth, 2.5);
        multmatrix(hood_shear) translate([0, 0, -1])
            rrect(disp_active_w + 2, disp_active_l + 2, hood_depth + 2, 1.5);
    }

    /*
      Flared skirt at the root. A 30 mm cantilever meeting a flat plate at a
      sharp 90 degrees puts the joint on a single layer interface loaded in
      peel, which is ASA's weakest direction - one knock in a pannier snaps the
      hood off. 3 mm out over 3 mm up is 45 degrees, so it prints unsupported.
    */
    multmatrix(hood_shear) hull() {
        rrect(hood_ow + 6, hood_ol + 6, 0.01, 2.5);
        translate([0, 0, 3]) rrect(hood_ow, hood_ol, 0.01, 2.5);
    }

    // Ribs scatter the glancing light that would otherwise bounce off a smooth
    // inner wall straight onto the glass.
    for (i = [1 : hood_ribs])
        multmatrix(hood_shear)
            translate([0, 0, i * hood_depth / (hood_ribs + 1)]) hood_rib();
}

/*
  ★ CHAMFERED UNDERSIDE. A rib springing 1.8 mm inward from the bore in a single
  layer is an unsupported horizontal ledge, five times over, right round a
  200 mm perimeter - and supports inside a 30 mm hood are miserable to remove.
  Growing it inward over 1.8 mm of rise makes it a 45 degree slope instead.

  The outer edge is 0.2 mm proud of the bore rather than exactly coincident with
  it: zero-overlap unions are a classic source of slicer artefacts.
*/
module hood_rib() {
    rib_h  = 2.6;
    rib_in = 1.8;   // chamfer rise; above this the rib is at full reach
    difference() {
        rrect(disp_active_w + 2.2, disp_active_l + 2.2, rib_h, 1.5);
        /*
          ★ THE SUBTRACTION MUST RUN PAST THE TOP OF THE RIB.

          The first version gave the inner profile a height of 0.01, so the hull
          ended at z=1.81 while the rib block ran to 2.6. Above 1.81 nothing was
          subtracted at all and each rib printed as a SOLID SLAB across the full
          bore - five of them, stacked like louvres, completely blocking the
          hood. A section render caught it; from outside it looked fine.

          Giving the inner profile real height carries the cut through to 2.8.
        */
        translate([0, 0, -0.01]) hull() {
            rrect(disp_active_w + 2.2, disp_active_l + 2.2, 0.01, 1.5);
            /*
              ★ THE RIB MUST STOP OUTSIDE THE APERTURE. It used to reach in to
              disp_active_w - 1.6, which is 0.8 mm INSIDE the aperture on every
              side - so all five ribs overhung the live picture by 4.4 px per
              edge. display.cpp paints flush to the panel edge (its own comment:
              "112 + 208 = 320, flush to the edge"), so that is content being
              masked, not margin.

              +0.8 leaves the ribs standing 0.4 mm clear of the aperture all
              round. They still shade the wall; they no longer shade the screen.
            */
            translate([0, 0, rib_in])
                rrect(disp_active_w + 0.8, disp_active_l + 0.8,
                      rib_h - rib_in + 0.2, 1.0);
        }
    }
}

/*
  The dovetail slot: a pedestal on the back of the case with the female profile
  cut into its outer face.

  ★ FULL FOOTPRINT, NOT A DISC. The previous version was a Ø40 pad, which meant
  the 57.2 x 93.2 body sprang out of a 40 mm circle at 6 mm height - 4074 sq mm
  of 90-degree overhang on every side. The body is printed mount-face down, so
  that disc was the first layer, and the whole case was hanging off it. There is
  no fillet that rescues a 26 mm horizontal run over 6 mm of rise.

  Making the pedestal the full body outline costs about 14 g and makes the part
  printable. It is also a raised pedestal rather than a pocket sunk inward,
  because the floor is 2.4 mm and the slot needs 6 - cutting it inward would
  breach the sealed volume.
*/
/*
  ★ THE SLOT MUST RUN OUT TO AN EDGE. Cut at its own length it is a closed
  rectangular pocket in the middle of the back - correct profile, and nothing
  can ever slide into it. It has to be open at one end.

  Open at the TOP of the case, closed at the bottom: the case then drops down
  onto the mount and gravity seats it against the stop, rather than being the
  force trying to pull it off. The thumbscrew is backup, not the only thing
  holding it.
*/
dt_stop_y  = -15.0;                  // closed end - the positive stop
dt_open_y  = body_l / 2 + 4;         // runs past the top edge
dt_slot_l  = dt_open_y - dt_stop_y;

module mount_dovetail_boss() {
    difference() {
        translate([0, 0, -dt_boss_t]) rrect(body_w, body_l, dt_boss_t, corner_r);
        // dovetail_female() opens +Z from its own origin, so it sits on the
        // pedestal's OUTER face and cuts inward, leaving 2 mm of backing.
        translate([0, (dt_stop_y + dt_open_y) / 2, -dt_boss_t])
            dovetail_female(dt_slot_l);
        // Thumbscrew bears on the flank of the seated dovetail, which spans
        // dt_stop_y .. dt_stop_y + 30, so y = 0 is comfortably inside it.
        translate([0, 0, -dt_boss_t]) dovetail_lock_cut();
    }
}

// ============================================================ LAYOUT

// Set one of these to render a single part for export.
part = "all";     // "all", "body", "lid"

if (part == "all") {
    union() { body(); if (mount_dovetail) mount_dovetail_boss(); }
    translate([body_w + 12, 0, 0]) lid();
} else if (part == "body") {
    union() { body(); if (mount_dovetail) mount_dovetail_boss(); }
} else if (part == "lid") {
    lid();
}

/*
  ★ PRINT mount.scad PART "fittest" FIRST. Two discs, about six grams and ten
  minutes, and it proves the lug and slot geometry engages before anything
  expensive is committed. If it binds, raise qt_clear by 0.1 and reprint the
  test alone.

  Then the body, then the lid.

  Everything here is driven by measured numbers from docs/COMPONENT_DIMENSIONS.md
  rather than by assumption. Three things were wrong in earlier versions and each
  would have wasted a print: the display module is 4.40 mm thick and not the bare
  PCB 1.6, its glass sits 4.90 mm off centre rather than centred, and the cable
  gland was positioned 22 mm inside the cavity where it cut nothing at all.
*/
