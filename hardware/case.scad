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
  infill, sealing face flat on the bed.

  ---------------------------------------------------------------------------
  ★ TWO THINGS TO DO BEFORE YOU PRINT

  1. MEASURE the three boards with calipers and put the numbers in below. The
     defaults are typical for these parts, not measured from yours, and a case
     is the one thing in this project that cannot be fixed in software.

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
disp_pcb_t      = 1.6;
// Active glass area, centred on the PCB unless you say otherwise
disp_active_w   = 43.2;
disp_active_l   = 57.6;
disp_active_off = 0.0;     // shift of the active area along the long axis

// ESP32 WEMOS LOLIN32
mcu_w           = 26.0;
mcu_l           = 58.0;
mcu_stack       = 14.0;    // board + headers + wiring, worst case

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
vent_d          = 3.0;     // ePTFE pressure vent. Do not omit this.
gland_d         = 8.0;     // cable gland, bottom face, drip loop below
gland_from_end  = 22.0;

/* [Fasteners] */
// Blind bosses: the screw never breaches the sealed volume.
screw_d         = 3.0;
boss_d          = 7.0;
boss_blind_t    = 1.6;     // material left at the bottom of the hole

/* [Mount] */
// ★ UNVERIFIED. Garmin quarter-turn lug geometry is a de-facto standard and
// these are the commonly quoted figures, but they are NOT measured from your
// BOBO BM4 socket. Print mount_test_plate() on its own first - it is a 3 g,
// four-minute print - and confirm it clicks before committing a whole case.
mount_plate_d   = 26.0;
mount_lug_w     = 8.0;
mount_lug_t     = 2.4;
mount_lug_r     = 11.5;    // centre to outer face of lug
mount_boss_h    = 6.0;

/* [Choices] */
window_mode     = "none";  // "none" or "bonded" - see the header
$fn             = 64;

// ============================================================ DERIVED

inner_w = disp_pcb_w + 2 * inner_clear;
inner_l = disp_pcb_l + 2 * inner_clear;
inner_h = disp_pcb_t + mcu_stack + 2.0;      // 2 mm for wiring above the MCU

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

        // Cable gland, bottom face. Drip loop goes below it.
        translate([0, -body_l / 2 + gland_from_end, floor_t + inner_h / 2])
            rotate([90, 0, 0]) cylinder(h = wall * 3, d = gland_d, center = true);

        // Pressure vent. A sealed box in the sun reaches 60 C+, and cold rain
        // then contracts the air and pulls water past the gasket. The part most
        // DIY builds leave out, and the reason they flood.
        translate([body_w / 2 - wall, 0, floor_t + inner_h - 5])
            rotate([0, 90, 0]) cylinder(h = wall * 3, d = vent_d, center = true);
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
            translate([0, 0, lid_t]) hood();
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

// Matte black, ribbed inside. Print this separately in black if you can - it is
// the one part where colour does real work rather than looking nice.
module hood() {
    difference() {
        rotate([hood_rake, 0, 0])
            difference() {
                rrect(disp_active_w + 2 * wall + 2, disp_active_l + 2 * wall + 2,
                      hood_depth, 2.5);
                translate([0, 0, -1])
                    rrect(disp_active_w + 2, disp_active_l + 2, hood_depth + 2, 1.5);
            }
        // Open the bottom face so the rake does not trap a lip
        translate([0, 0, -hood_depth]) cube([200, 200, 2 * hood_depth], center = true);
    }

    // Ribs: they scatter the glancing light that would otherwise bounce off a
    // smooth inner wall straight onto the glass.
    rotate([hood_rake, 0, 0])
        for (i = [1 : hood_ribs])
            translate([0, 0, i * hood_depth / (hood_ribs + 1)])
                difference() {
                    rrect(disp_active_w + 2, disp_active_l + 2, 0.8, 1.5);
                    translate([0, 0, -0.5])
                        rrect(disp_active_w - 1.6, disp_active_l - 1.6, 2, 1.0);
                }
}

/*
  Garmin-style 3-lug quarter turn, on the back of the body.

  Quarter turn rather than a clamp screw because a tightened joint holds by
  friction and engine vibration walks friction joints loose. Three lugs behind
  solid shoulders is a shear plane - there is nothing to unwind.
*/
module mount_plate() {
    difference() {
        union() {
            cylinder(h = mount_boss_h, d = mount_plate_d);
            for (a = [0, 120, 240]) rotate([0, 0, a])
                translate([0, 0, mount_boss_h - mount_lug_t])
                    linear_extrude(mount_lug_t)
                        polygon([[0,0],
                                 [mount_lug_r, -mount_lug_w/2],
                                 [mount_lug_r,  mount_lug_w/2]]);
        }
        translate([0, 0, -1]) cylinder(h = mount_boss_h + 2, d = mount_plate_d - 8);
    }
}

// Print this ALONE first. 3 g, four minutes, and it tells you whether the lug
// numbers above are right before you commit two hours to a whole case.
module mount_test_plate() {
    difference() {
        union() {
            cylinder(h = 3, d = mount_plate_d + 8);
            translate([0, 0, 3]) mount_plate();
        }
        translate([0, 0, -1]) cylinder(h = 2, d = mount_plate_d - 8);
    }
}

// ============================================================ LAYOUT

// Set one of these to render a single part for export.
part = "all";     // "all", "body", "lid", "mount", "mounttest"

if (part == "all") {
    body();
    translate([body_w + 10, 0, 0]) lid();
    translate([0, body_l + 20, 0]) mount_test_plate();
} else if (part == "body") {
    union() {
        body();
        translate([0, 0, -mount_boss_h]) mount_plate();
    }
} else if (part == "lid") {
    lid();
} else if (part == "mount") {
    mount_plate();
} else if (part == "mounttest") {
    mount_test_plate();
}
