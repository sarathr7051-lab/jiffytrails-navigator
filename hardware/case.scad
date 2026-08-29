/*
  JiffyTrails enclosure - BACK-OPENING. Parametric, printable.

  Open in OpenSCAD (free, openscad.org), press F6, File > Export > STL.

  ---------------------------------------------------------------------------
  ★ WHY THIS OPENS AT THE BACK

  The previous version opened at the front: a tub facing the rider, with the
  lid carrying the window and the hood. Six independent reviews took it apart
  and the failures clustered in one place - the sealing line ran right around
  the display glass, which is the most crowded and least forgiving line on the
  whole case.

    - All four screw bosses stood inside the display's footprint. The module
      could not be lowered into the box at all.
    - The gasket groove had no inner wall: it spanned radius 25.4-27.4 against
      a cavity wall at 26.2, so it opened into the box. A 2.0 mm groove does
      not fit a 2.4 mm rim, and poured sealant would have run onto the boards.
    - Nothing sealed the window. A 1.0 mm gap sat between the glass and the
      lid, and the aperture was an open hole into the electronics.
    - The lid could not clamp a gasket over an 82 mm span with four corner
      screws - computed deflection was larger than the entire squeeze budget.
    - It needed a hole in a sealed wall for USB, or the firmware could never be
      updated by cable again.

  Turning it round dissolves all five rather than solving them:

    THE FRONT IS CLOSED FOR GOOD, with the panel bonded behind it.
    THE BACK IS THE LID - a plain plate, no window, no hood, nothing to align.

  The sealing line moves onto a flat rim with nothing near it. The screws move
  clear of the display. USB is reached by taking the back off. And - the part
  that matters most on a one-shot print - every dimension we are not sure of
  moves into bezel(), a 5 g part that reprints in eight minutes.

  ---------------------------------------------------------------------------
  ★ THE ONE RULE THAT KEEPS THIS SAFE TO PRINT

  bezel() is the ONLY module allowed to read disp_active_w, disp_active_l or
  disp_active_off. Nothing else may reference them.

  Those three are the numbers sourced from a drawing for a DIFFERENT board -
  an LCDWIKI MSP2806, where the panel's ribbon is bonded along the header edge.
  The board actually purchased is a SmartElex with the ribbon on a mid-board
  ZIF connector fed through a slot, and a reviewer measuring the vendor's own
  photograph found its mounting holes evenly spaced where the MSP2806's are
  lopsided. That was the whole reason to believe the glass sits off-centre.

  So the body and the lid - the expensive prints - are built entirely from
  dimensions that cannot move: the 50.0 x 86.0 PCB outline, verified twice.

  ---------------------------------------------------------------------------
  PRINT SETTINGS

  ASA, light coloured. Not PETG and never PLA - docs/HARDWARE.md has the
  arithmetic: PETG's HDT is 65-80 C against an estimated sealed interior of
  53-70 C in Bengaluru sun. ASA gives ~105 C service and does not yellow.

  0.2 mm layers, 5 perimeters (four is the usual watertight threshold; a sealed
  case earns the fifth), 30-40% infill, ENCLOSURE OR DRAFT SHIELD MANDATORY -
  ASA delaminating mid-print on a 100 mm part in a draught is the likeliest way
  to lose the one print available.

  ORIENTATION
    body   FRONT FACE DOWN. Puts the sealing rim on top where it prints
           accurately with no elephant's foot, and the flange flares outward
           going up at 45 degrees so it is self-supporting. 5 mm brim - the
           first layer is a picture frame and adhesion is not optional.
    lid    OUTER FACE DOWN. A solid 64 x 100 first layer, the best in the set.
    bezel, hood, mount plate  flat, trivial.
*/

// ============================================================ PARAMETERS

/* [Display - the two the body depends on are VERIFIED] */
disp_pcb_w      = 50.0;    // VERIFIED twice: drawing, and photo of this board
/*
  ★ 82.0, NOT 86.0. Rider-measured 29 Aug 2026, and cross-checked by his own
  independent route: the white panel frame is 70 mm and sits centred with 6 mm
  of board at each end. 70 + 6 + 6 = 82. Two readings agreeing by different
  means is stronger than either alone.

  The MSP2806 drawing says 86. This is the clearest confirmation yet that the
  board in hand is a different product - and it makes the case 4 mm shorter.
*/
disp_pcb_l      = 82.0;
/*
  Rider-measured 5.0 mm (0.5 cm) glass face to PCB back, against the MSP2806
  drawing 4.40. Taking the measured, larger figure: too deep costs a fraction
  of a millimetre of cavity, too shallow presses the lid onto the panel.
*/
disp_t          = 5.0;
/*
  ★ THE PANEL FRAME STANDS PROUD OF THE PCB. Rider-measured, 29 Aug 2026:
  the white plastic carrier around the glass projects about 0.6 mm BEYOND the
  board edge on both long sides, evenly.

  So the widest part of the module is 51.2 mm, not 50.0 - and the display
  locating ribs were built to a 50.6 mm pocket, which would have stopped the
  module 0.6 mm out and been blamed on print tolerance. Nothing in any
  datasheet mentions this; it took someone holding the part.
*/
disp_frame_proud = 0.35;   // measured; was assumed 0.6
disp_widest      = disp_pcb_w + 2 * disp_frame_proud;

/* [Display - ★ UNVERIFIED. Used ONLY by bezel(), which is 5 g to reprint] */
disp_active_w   = 43.2;    // fixed by 240 px x 0.18 mm - safe
disp_active_l   = 57.6;    // fixed by 320 px x 0.18 mm - safe
/*
  ★★ THE ONE NUMBER TO MEASURE BEFORE PRINTING THE BEZEL.

  How far the lit area sits from centre, toward the far (non-header) end.
  4.90 comes from the MSP2806 drawing and its justification does not survive
  on this board - see the header. Light the screen all white and measure from
  each END edge to where the light starts:

      the two ends roughly equal      ->  0
      header end bigger by about 6    ->  2.90
      header end bigger by about 10   ->  4.90   (what this file assumes)
*/
/*
  ★ 3.5 mm, MEASURED - replacing the 4.90 inherited from the wrong drawing.

  Screen lit white: 14.0 mm of board at the header end, 7.0 at the far end, on
  an 82 mm board. That gives a lit span of 61.0 where the panel can only be
  57.6 (320 px x 0.18), so BOTH readings are 1.70 mm wide.

  A bias that is equal at both ends is what backlight glow does - it spills
  past the pixels by the same amount all round. It inflates the span and leaves
  the difference alone, so the offset is safe to take from the difference:

      (14.0 - 7.0) / 2 = 3.5 mm toward the far end

  Not 0, not 4.90. And it is only used by bezel() - 5 g if this is still wrong.
*/
disp_active_off = 3.5;

/* [The stack, front to back - this is what sets the depth] */
bezel_t         = 1.5;
/*
  ★ Display PCB back face -> perfboard top face. THE decision that sets how
  thick this thing is. The 14-pin header projects 8.38 mm behind the PCB:
  2.54 of plastic strip plus 5.84 of bare pin.

    6.5   pins CLIPPED to a ~2 mm stub and wires soldered to them.
          RECOMMENDED. The display is bonded to the front and never has to come
          off, so nothing is lost by clipping - and the pins are the only thing
          standing between us and a thin case.
    11.0  a 2.54 mm female socket on the perfboard, display plugged in.
          Serviceable, and 4.5 mm thicker. Note the socket body (~8.5) AND the
          header's plastic strip (2.54) both count - a review put this at 8.5
          by omitting the strip.
    2.5   pins pushed THROUGH the perfboard. Rejected: a review found the
          header misses a centred 50 x 70 perfboard's last hole row by 1.3 mm,
          and it solders the only display permanently to the board.
*/
hdr_gap         = 6.5;
perf_t          = 1.6;
/*
  ESP32 on male header pins through the perfboard: 2.54 strip + 1.6 PCB +
  6.0 JST connector. The JST is the tallest thing on the board and this build
  has no battery, so desoldering it takes this to 7.2 and the whole case to
  31.2 mm. A two-pin connector on an unused net is the ideal practice target -
  but it is your board and your call.
*/
mcu_stack       = 10.2;
retain_pad      = 2.0;     // closed-cell foam on the lid, pushes the stack forward

/* [Shell] */
wall            = 2.4;
front_t         = 3.0;     // closed front, carries the window opening
lid_t           = 5.0;     // ★ 5 mm. Deflection between screws goes as t^-3
land_w          = 6.0;     // sealing land: 0.8 + 4.0 foam + 1.2, and also
                           // exactly what a 2.5 mm self-tapping boss needs
inner_clear     = 1.2;
corner_r        = 4.0;
corner_r_out    = 7.6;

/* [Seal] */
/*
  ★ CLOSED-CELL FOAM TAPE, not an O-cord, and the vent is why.

  With a working pressure vent the gasket never sees the 13.3 kPa thermal
  vacuum that would otherwise make this box a pump. What is left is driven rain
  at ~300-460 Pa. An O-cord is built for bar-level sealing and pays for it in
  tolerance: 25% squeeze on a 2 mm cord is 0.5 mm, usable band +/-0.15 mm - and
  an ASA part this size bows 0.3-0.8 mm as it cools. The gasket would be
  defeated by warp alone, before it ever met water.

  3 mm foam closing to 2 mm is 33% compression with a +/-0.5 mm usable band,
  which covers the warp with room to spare. Closing force drops to ~5 N per
  screw, which is also what makes self-tapping screws viable.

  ★ BUY CLOSED-CELL EPDM, NOT OPEN-CELL POLYURETHANE. Most cheap "foam tape"
  is open cell and wicks like a sponge. Test it: cut a piece, hold it under
  water and squeeze. Open cell streams bubbles and stays wet.
*/
foam_w          = 4.0;
foam_d          = 2.0;     // channel depth; 3 mm tape closes to 2 mm
spigot_h        = 2.5;     // labyrinth - see lid()
spigot_clear    = 0.2;

/* [Fasteners] */
/*
  8 x M3 x 12 self-tapping into blind holes. Not heat-set inserts: those need
  a 4.0 mm bore and 1.6 mm of wall either side, which costs 2.4 mm of envelope
  in both directions, and they need eight iron-driven insertions into a part
  that cannot be reprinted. Required preload here is ~5 N per screw against a
  strip torque forty times that, and the land-on-land hard stop absorbs
  over-tightening, so the thread never sees abuse.

  Every hole is BLIND, bottoming in solid ASA. A screw hole is a dead end, not
  a leak path - which is what makes it safe to run them through the foam band.
*/
screw_pilot_d   = 2.5;
screw_clear_d   = 3.4;
screw_depth     = 9.0;
screw_head_d    = 6.0;

/* [Openings] */
/*
  ★ VENT: 6.0 MINIMUM, NOT 3.0.

  The thermal argument is right and the vent is mandatory - a sealed 50 mL box
  quenched from 70 C to 25 C pulls 13.3 kPa, which is 1.36 m of water head and
  nothing holds that. But the residual pressure is set by the MEMBRANE'S FLOW
  RESISTANCE, not by the hole. Rain-jacket ePTFE passes about 1 L/m2/s at
  100 Pa, so:

      Dia 3   ->  13.2 mbar = 135 mm of head on a 60 s quench
      Dia 6   ->   3.8 mbar =  39 mm
      Dia 10  ->   1.4 mbar =  14 mm

  "Under 1 mbar" was optimistic by more than tenfold at Dia 3. Open it up; it
  is free.
*/
vent_d          = 6.0;
vent_seat_d     = 12.0;    // membrane bonding land, inside
vent_seat_t     = 0.6;
/*
  ★ POTTED CABLE ENTRY, NOT A GLAND. An M8 gland's Dia 14 locknut needs 16 mm
  of clear wall face on the inside and fouls the ESP32 at every plausible
  position - which is why the old design's gland never worked out. A printed
  tube filled with neutral-cure silicone seals better, needs no internal
  hardware, and costs nothing.
*/
cable_bore_d    = 4.5;     // ★ MEASURE the cable: paper strip, circ / 3.1416
cable_boss_d    = 8.5;
cable_in        = 6.0;
cable_out       = 4.0;
/*
  ★ BOTH PENETRATIONS ARE OFFSET DELIBERATELY - they collide with the screw
  ring if left on centre. The vent on the +x wall at y=0 lands exactly on the
  mid-side screw, and a centred cable boss overlaps the mid-end screw by
  0.15 mm in z. Neither would have shown up in a render.
*/
cable_x         = 16.0;    // off centre, clear of the mid-end screw
cable_z         = 11.0;    // low on the wall, well under the flange
vent_y          = 22.0;    // between the corner and mid-side screws
vent_z          = 21.2;

/* [Hood - separate part, bolts on] */
hood_depth      = 30.0;
hood_rake       = 12;      // set AFTER the rider settles the mount angle
hood_ribs       = 5;
hood_wall       = 1.6;

/* [Print] */
$fn             = 64;

// ============================================================ DERIVED

cav_w = disp_pcb_w + 2 * inner_clear;          // 52.4
cav_l = disp_pcb_l + 2 * inner_clear;          // 88.4
cav_d = bezel_t + disp_t + hdr_gap + perf_t + mcu_stack + retain_pad;

body_w = cav_w + 2 * land_w;                   // 64.4
body_l = cav_l + 2 * land_w;                   // 100.4
body_h = front_t + cav_d;                      // outer face to sealing face
case_h = body_h + lid_t;

z_land  = body_h;                              // the sealing face
band_x  = cav_w / 2 + land_w / 2 - 0.2;        // foam centreline
band_y  = cav_l / 2 + land_w / 2 - 0.2;

// Eight screws. Pitch must stay under ~45 mm for a 5 mm lid; the longest gap
// here is 42.5 along the sides and 32.2 across the ends.
screw_pts = [[ band_x,  42.5], [-band_x,  42.5],
             [ band_x, -42.5], [-band_x, -42.5],
             [ band_x,   0  ], [-band_x,   0  ],
             [ 0,     band_y ], [ 0,    -band_y]];

echo(str("cavity ", cav_w, " x ", cav_l, " x ", cav_d));
echo(str("body   ", body_w, " x ", body_l, " x ", body_h));
echo(str("CASE   ", body_w, " x ", body_l, " x ", case_h, " mm"));

// ============================================================ PRIMITIVES

module rrect(w, l, h, r) {
    hull() for (x = [-1, 1], y = [-1, 1])
        translate([x * (w / 2 - r), y * (l / 2 - r), 0])
            cylinder(h = h, r = r);
}

/*
  ★ TEARDROP for every HORIZONTAL hole. A round hole printed axis-horizontal
  bridges its own diameter at the crown and sags 0.2-0.4 mm, out of round, on
  the exact face a seal touches - and the usual repair is drilling a finished,
  sealed part with swarf falling inside it. The 45 degree roof is
  self-supporting and leaves the bore round everywhere a seal meets it.
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
module teardrop_y(d, h) { rotate([90, 0, 0]) linear_extrude(h, center = true) teardrop_2d(d); }
module teardrop_x(d, h) { rotate([90, 0, 0]) rotate([0, 90, 0])
                              linear_extrude(h, center = true) teardrop_2d(d); }

// ============================================================ BODY

/*
  The sealed shell. Front face at z = 0, sealing rim at z = body_h, cavity
  opening toward +z (the rider's side is -z).
*/
module body() {
    difference() {
        union() {
            // main shell
            rrect(cav_w + 2 * wall, cav_l + 2 * wall, body_h, corner_r);
            // flange block carrying the seal and the screws, flared in at 45
            // degrees from below so it prints without support
            translate([0, 0, body_h - 11.2]) hull() {
                rrect(cav_w + 2 * wall, cav_l + 2 * wall, 0.01, corner_r);
                translate([0, 0, 3.6])
                    rrect(body_w, body_l, 0.01, corner_r_out);
            }
            translate([0, 0, body_h - 7.6]) rrect(body_w, body_l, 7.6, corner_r_out);
            // hood mounting pads, y = 0 each side, bringing the mid-body to
            // exactly body_w so they cost no envelope at all
            for (x = [-1, 1])
                translate([x * (cav_w / 2 + wall), 0, front_t + 6])
                    cylinder(h = 14, d = 7.2);
            // cable entry boss
            translate([cable_x, -body_l / 2, cable_z])
                rotate([90, 0, 0]) cylinder(h = cable_out * 2, d = cable_boss_d, center = true);
        }

        // cavity, opening at the back
        translate([0, 0, front_t]) rrect(cav_w, cav_l, cav_d + 1, corner_r - wall);

        // window opening. Sized from the PCB outline, NOT from the active area
        // - 48 x 74 leaves 1.0 mm of overlap on the 50 mm glass width, which is
        // all there is, and the bezel behind it does the precise work.
        translate([0, 0, -1]) rrect(48.0, 74.0, front_t + 2, 2.0);
        // outer relief so rain sheds off the aperture rather than pooling in it
        translate([0, 0, -0.01]) hull() {
            rrect(51.0, 77.0, 0.01, 2.5);
            translate([0, 0, 1.5]) rrect(48.0, 74.0, 0.01, 2.0);
        }

        // blind screw holes, from the sealing face down
        for (p = screw_pts)
            translate([p[0], p[1], z_land - screw_depth])
                cylinder(h = screw_depth + 0.1, d = screw_pilot_d);

        // hood pad pilots
        for (x = [-1, 1])
            translate([x * (cav_w / 2 + wall), 0, front_t + 8])
                rotate([0, 90, 0]) cylinder(h = 12, d = screw_pilot_d, center = true);

        // cable bore
        translate([cable_x, -body_l / 2, cable_z]) teardrop_y(cable_bore_d, 40);

        // vent, on the same downward face as the cable so every penetration
        // points at the ground
        translate([0, vent_y, vent_z]) {
            teardrop_x(vent_d, 200);
            // Membrane seat, recessed into the cavity-side face of the wall so
            // the patch has a flat land to bond to. It used to float 3.4 mm
            // inside the cavity, bonded to nothing.
            translate([cav_w / 2, 0, 0]) rotate([0, 90, 0])
                cylinder(h = vent_seat_t, d = vent_seat_d);
        }
    }

    // Display locating ribs. ★ These bear on the PCB OUTLINE (50.0 x 86.0,
    // verified) rather than on the four mounting holes, whose insets came from
    // the wrong board and were measured wrong even there. A rib cannot miss an
    // edge; a post can miss a hole by 2 mm and scrap the print.
    disp_ribs();
}

module disp_ribs() {
    rz = front_t + bezel_t;                     // ribs start behind the bezel
    rh = disp_t + 2.0;
    // ★ Pocket sized on the WIDEST part - the proud frame, not the PCB.
    px = disp_widest / 2 + 0.3;
    py = disp_pcb_l / 2 + 0.3;                  // ends: frame is flush there
    for (s = [-1, 1]) {
        for (y = [-30, 0, 30])
            translate([s * (px + 1.0), y, rz]) rib(2.0, 8.0, rh);
        for (x = [-14, 14])
            translate([x, s * (py + 1.0), rz]) rotate([0, 0, 90]) rib(2.0, 8.0, rh);
    }
}

// A rib with a 45 degree lead-in on its back edge, so the module drops in
// rather than having to be threaded past a square shoulder.
module rib(w, l, h) {
    hull() {
        translate([0, 0, 0]) cube([w, l, 0.01], center = true);
        translate([0, 0, h - 1.5]) cube([w, l, 0.01], center = true);
        translate([0, 0, h]) cube([w * 0.2, l, 0.01], center = true);
    }
}

// ============================================================ LID

/*
  A plain plate. No window, no hood, nothing to line up - which is the entire
  point of turning the case round.
*/
module lid() {
    difference() {
        union() {
            rrect(body_w, body_l, lid_t, corner_r_out);
            // Rim ring. Its inner 1.0 mm drops into the cavity mouth as a
            // SPIGOT: water reaching the perimeter must cross the outer joint,
            // then 4 mm of compressed foam, then a 0.2 x 2.5 mm annular gap.
            // No straight-line path in, and the spigot costs zero envelope
            // because it uses cavity space nothing occupies at the lid plane.
            translate([0, 0, lid_t]) difference() {
                rrect(cav_w + 2 * wall, cav_l + 2 * wall, spigot_h, corner_r);
                translate([0, 0, -0.5])
                    rrect(cav_w - 2 * spigot_clear - 2.0,
                          cav_l - 2 * spigot_clear - 2.0,
                          spigot_h + 1, max(0.5, corner_r - wall));
            }
        }
        // foam channel in the rim face
        translate([0, 0, lid_t + spigot_h - foam_d]) difference() {
            rrect(2 * band_x + foam_w, 2 * band_y + foam_w, foam_d + 1, corner_r_out - 1);
            translate([0, 0, -0.5])
                rrect(2 * band_x - foam_w, 2 * band_y - foam_w, foam_d + 2,
                      max(0.5, corner_r_out - 1 - foam_w));
        }
        // screw clearance
        for (p = screw_pts)
            translate([p[0], p[1], -0.1])
                cylinder(h = lid_t + spigot_h + 1, d = screw_clear_d);
        // mount plate keying recess and its pilots, on the outer face
        translate([0, 0, -0.01]) rrect(body_w - 8, body_l - 8, 1.0, corner_r_out - 4);
        for (x = [-1, 1], y = [-1, 1])
            translate([x * 18, y * 34, -0.1])
                cylinder(h = 3.6, d = screw_pilot_d);
    }
}

// ============================================================ BEZEL

/*
  ★ THE ONLY PART THAT READS THE UNVERIFIED NUMBERS.

  5 g, about eight minutes. Print it first, offer it to the lit display, and
  check the aperture before anything expensive goes on the bed. If the offset
  turns out wrong you reprint this, not the body.

  Matte black. It sits 3 mm behind the front face and forms a small hood of its
  own around the glass. The aperture is the active area plus 2 mm all round:
  overshoot lands on the panel's own black border (2.90 mm at the narrowest),
  never on bare PCB, so it buys +/-2 mm of measurement error.
*/
module bezel() {
    difference() {
        rrect(cav_w - 0.4, cav_l - 0.4, bezel_t, corner_r - wall);
        translate([0, disp_active_off, -0.5])
            rrect(disp_active_w + 4.0, disp_active_l + 4.0, bezel_t + 1, 1.5);
    }
}

// ============================================================ HOOD

/*
  Separate part, bolted to the two side pads. Matte black - the one place
  colour does real work. Per HARDWARE.md this is the largest single readability
  gain available, worth more than any backlight change.

  ★ SHEARED, NOT ROTATED. Rotating the tube about its base lifts one side of
  the base off the plane - the far wall's bottom edge rose 6.7 mm and the flat
  cut only removed material below z=0, leaving an open slot the width of the
  hood right beside the aperture. At road speed that is a forward-facing scoop.
  A shear leans the walls and leaves the base flat and fully seated.
*/
hood_shear = [[1, 0, 0, 0], [0, 1, -tan(hood_rake), 0], [0, 0, 1, 0], [0, 0, 0, 1]];

module hood() {
    ow = 48.0 + 2 * hood_wall + 2;
    ol = 74.0 + 2 * hood_wall + 2;
    difference() {
        union() {
            // skirt that clamps over the body's front
            difference() {
                rrect(body_w, body_l, 14, corner_r_out);
                translate([0, 0, -0.5])
                    rrect(cav_w + 2 * wall + 0.4, cav_l + 2 * wall + 0.4, 15, corner_r);
            }
            translate([0, 0, 14]) multmatrix(hood_shear)
                difference() {
                    rrect(ow, ol, hood_depth, 2.5);
                    translate([0, 0, -1]) rrect(ow - 2 * hood_wall, ol - 2 * hood_wall,
                                                hood_depth + 2, 1.5);
                }
            for (i = [1 : hood_ribs])
                translate([0, 0, 14]) multmatrix(hood_shear)
                    translate([0, 0, i * hood_depth / (hood_ribs + 1)]) hood_rib(ow, ol);
        }
        for (x = [-1, 1])
            translate([x * (cav_w / 2 + wall), 0, 8])
                rotate([0, 90, 0]) cylinder(h = 20, d = screw_clear_d, center = true);
    }
}

/*
  ★ THE SUBTRACTION MUST RUN PAST THE TOP OF THE RIB. A first attempt gave the
  inner profile a height of 0.01, so the cut ended below the rib's top face and
  every rib printed as a SOLID SLAB across the full bore - five of them, like
  louvres, blocking the hood completely. It looked perfect from outside; a
  section render caught it.

  The rib also stops OUTSIDE the aperture. Reaching inward past it masked
  4.4 px of live picture on every edge, and display.cpp paints flush to the
  panel edge - so that was content, not margin.
*/
module hood_rib(ow, ol) {
    rib_h = 2.6; rib_in = 1.8;
    difference() {
        rrect(ow - 2 * hood_wall + 0.2, ol - 2 * hood_wall + 0.2, rib_h, 1.5);
        translate([0, 0, -0.01]) hull() {
            rrect(ow - 2 * hood_wall + 0.2, ol - 2 * hood_wall + 0.2, 0.01, 1.5);
            translate([0, 0, rib_in])
                rrect(48.0 + 1.6, 74.0 + 1.6, rib_h - rib_in + 0.2, 1.0);
        }
    }
}

// ============================================================ MOUNT PLATE

/*
  Separate so the lid prints outer-face-down on a solid 64 x 100 first layer,
  and so the mount can change later without touching the sealed case.
*/
include <dovetail.scad>   // shared constants - see that file for why not `use`
/*
  ★ 8.0, NOT 6.0. At 6.0 the dovetail slot cut CLEAN THROUGH the plate: the
  slot floor computed to z 0.70 against a plate underside at z 1.00, so there
  was -0.30 mm of material under it. The part rendered as a plausible-looking
  plate with a slot in it and would have printed as a plate with a hole in it.
  8.0 leaves 1.70 mm of floor - and the floor is not the load path anyway, the
  dovetail flanks are.
*/
mount_plate_t = 8.0;

/*
  ★ THE SLOT MUST RUN OUT TO AN EDGE - the third time this has bitten.

  Cut at its own length, dovetail_female() is a closed rectangular pocket in
  the middle of the plate: correct profile, and nothing can ever slide into it.
  It caught me on the old case's receiver, again on the first back-plate, and
  again here. The profile looks right in every render, which is exactly why it
  keeps surviving inspection.

  Open at the TOP of the case, closed at the bottom, so the device drops down
  onto the mount and gravity seats it against the stop rather than being the
  force trying to pull it off.
*/
dt_stop_y = -15.0;
dt_open_y = body_l / 2 + 4;

module mount_plate() {
    difference() {
        union() {
            /*
              ★ 0.8 mm SMALLER than the recess it drops into. It used to be
              rrect(body_w - 8, body_l - 8) - byte-identical to lid()s cut, so
              the clearance was exactly ZERO and the plate could not be fitted
              at all. Two features generated from the same expression in two
              places look right and interfere by construction.
            */
            rrect(body_w - 8.8, body_l - 8.8, 1.0, corner_r_out - 4);   // keying spigot
            translate([0, 0, 1.0]) rrect(body_w, body_l, mount_plate_t, corner_r_out);
        }
        // Slot cut from the OUTER face inward, running off the top edge.
        translate([0, (dt_stop_y + dt_open_y) / 2, 1.0 + mount_plate_t])
            mirror([0, 0, 1]) dovetail_female(dt_open_y - dt_stop_y);
        /*
          ★ THE LOCK SCREW, AND WHY IT IS NOT dovetail_lock_cut().

          That module put the hole's centre at exactly z = 1.0 + 6.0 = 7.00 -
          the plate's own top face. Half the bore was in open air, so it printed
          as a GROOVE ACROSS THE FACE rather than a hole, and a thumbscrew had
          nothing to pass through. It was also Ø3.4, which is M3 *clearance* -
          so even as a proper hole the screw would have fallen straight through.

          This is the same class of defect as the quarter turn's phantom detent
          and it is the third time a "lock" has existed in prose and not in
          geometry. So: a real blind bore, at the seated dovetail's mid-height,
          sized for an M3 to CUT ITS OWN THREAD in 14.9 mm of solid plastic, and
          reaching far enough in that the screw tip bears on the dovetail flank.
        */
        translate([32.2 + 0.1, 0, 1.0 + mount_plate_t - (dt_h + 0.30) / 2])
            rotate([0, -90, 0]) cylinder(h = 18, d = 2.5);
        for (x = [-1, 1], y = [-1, 1])
            translate([x * 18, y * 34, -0.1])
                cylinder(h = 12, d = screw_clear_d);
    }
}

// ============================================================ LAYOUT

part = "all";   // "all" "body" "lid" "bezel" "hood" "mountplate"

if      (part == "body")       body();
else if (part == "lid")        lid();
else if (part == "bezel")      bezel();
else if (part == "hood")       hood();
else if (part == "mountplate") mount_plate();
else {
    body();
    translate([body_w + 12, 0, 0]) lid();
    translate([-(body_w + 12), 0, 0]) bezel();
    translate([0, body_l + 14, 0]) hood();
    translate([body_w + 12, body_l + 14, 0]) mount_plate();
}

/*
  ★ PRINT ORDER

  1. bezel  - 5 g. Offer it to the lit display and check the aperture registers
              before anything expensive is committed.
  2. mount.scad part="fittest" - proves the dovetail clearance.
  3. lid, hood, mount plate.
  4. body   - the long print, and the last one, once everything else has proved
              its numbers.
*/
