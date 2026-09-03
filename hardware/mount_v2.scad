/*
  JiffyTrails mount v2 - the adapter, the cap, and a tolerance coupon.

  Open in OpenSCAD, set `part`, press F6, File > Export > STL.

  ---------------------------------------------------------------------------
  WHAT CHANGED FROM mount.scad, AND WHY THAT FILE IS DEAD

  mount.scad bolted a printed plate THROUGH the BM4's aluminium phone plate.
  Two rider reports killed it: the plate is GLUED ON and does not come off, and
  it is not aluminium - the BM4 is polymer throughout, the only metal anywhere
  being one ISO 10642 M3 countersunk steel screw.

  So the adapter now REPLACES the phone plate rather than bolting to it. It
  drops into the socket's own square recess and is pulled down by the socket's
  own screw, into a brass heat-set insert - which is exactly what BOBO did in
  their moulded part, for the same reason.

  ---------------------------------------------------------------------------
  ★ EVERY SOCKET-SIDE NUMBER HERE IS MEASURED. See docs/MOUNT_INTERFACE.md.

      square recess   14.0 across flats, 2.17 corner radius, 2.0 deep
      screw           ISO 10642 M3 countersunk, steel, currently 10 mm

  The 2.17 radius was not measured directly - it is DERIVED, and that is why it
  is trustworthy. The rider measured 14.0 across the flats and 18.0 corner to
  corner. A sharp 14.0 square has a 19.799 diagonal; the 1.8 mm shortfall is
  what rounded corners do, and it pins the radius:

      (s/2 - r)*sqrt(2) + r = 9.0,  s = 14.0   ->   r = 2.171

  Two independent readings resolving to one plausible moulded geometry is far
  stronger than either alone.

  ---------------------------------------------------------------------------
  ★ WHY A SLIDE AND NOT A TWIST

  Decided on stability, not preference. The rider fits and removes this twice a
  day - about 3,650 times over five years, roughly 113 m of dry ASA on ASA with
  road grit in it. Both wear. Only one recovers:

    - A dovetail is a WEDGE. As the flanks wear, the case settles further down
      the 55 degree taper and re-closes. Machine tool ways are dovetails for
      this reason.
    - A bayonet's wear goes straight into axial slack that nothing can take up,
      because the shoulders fix the position. Loose is permanent, and its lugs
      sit in a blind pocket where a cracked one is invisible.

  Contact area 415 mm2 against 82. And the clinching argument: the cap grips
  the case's flange band, and the case is a RECTANGLE. You cannot twist a
  rectangle onto anything.

  ---------------------------------------------------------------------------
  ★★ THE FINDING THAT MADE THE CHOICE WORTH ANYTHING

  The old dovetail was not touching. dovetail.scad's female uses
  offset(delta = dt_clear), which grows EVERY edge along its normal - including
  the top. So the slot came out 5.60 tall over a 5.00 rail, and the case landed
  on its flat face before the taper ever met. The wedge carried nothing: 178 g
  hammering through 0.30 mm of free play at 60-120 Hz on a flat face that
  cannot take up a micron of its own wear.

  Here the roof is relieved by ROOF_RELIEF and the flanks get a running fit
  only, so the taper is the sole seat. Asserted below.

  ---------------------------------------------------------------------------
  ★ THE LOCK IS A STEEL PIN, NOT A SCREW

  The thumbscrew is gone. It retained by pressing on a flank, which is friction,
  and HARDWARE.md argues engine vibration walks friction joints loose. It needed
  a tool. And it has been found broken FOUR separate times in this project -
  four independent failures of one feature is the feature telling you something.

  A 3 mm steel pin through both cap walls and the case boss is double shear: no
  thread to unwind, no wedge to walk out, nothing depending on how hard it was
  pushed. Its wear mode is right - the hole elongates slightly and keeps
  holding; it cannot progress to release. And it is inspectable at arm's length
  with gloves on: the pin is either through or it is not.
*/

include <dovetail.scad>

$fn = 64;

// ============================================================ SOCKET SIDE

/* [Measured - docs/MOUNT_INTERFACE.md. Do not edit without re-measuring.] */
sq_flats    = 14.0;    // across flats
sq_r        = 2.17;    // corner radius, derived from the 18.0 diagonal
sq_depth    = 2.0;     // recess depth

/*
  ★ THE BOSS IS DELIBERATELY SHORTER THAN THE RECESS.

  If the boss bottoms first, the screw's whole clamp load lands on a 14 mm
  square instead of the full annular face, and the joint can rock on the boss's
  edges. That rocking is the micro-motion that frets printed ASA. The part's
  FLAT FACE must seat; the boss only keys rotation.
*/
sq_clear    = 0.25;    // per side, printed boss into a moulded pocket
boss_h      = 1.8;     // against a 2.0 recess

/* [The insert - Ruthex RX-M3x5.7 or equivalent] */
ins_len     = 5.7;
ins_bore    = 4.0;     // manufacturer's recommended hole
ins_wall    = 1.8;     // ASA around it
scr_clear_d = 3.4;     // M3 clearance through the floor

// ============================================================ DOVETAIL FIT

/*
  ★ ROOF RELIEF IS WHAT MAKES THE FLANKS THE SEAT.

  Flank gap comes from dt_clear (0.30). The roof must be relieved by MORE than
  that, or the rail's top lands before its flanks do and we are back to a
  clearance fit on a flat face.
*/
flank_clear = dt_clear;      // 0.30, running fit on the taper

/*
  ★★★ AND THE PROFILE WAS UPSIDE DOWN. Found 29 Aug 2026 by two independent
  reviews, both measuring rather than reading.

  A dovetail groove must be WIDE INSIDE and NARROW AT ITS MOUTH, so the rail's
  wide end is trapped. Mine was narrow at the floor and wide at the mouth - a
  V-groove opening the wrong way. The rail was not captured at all; it lifted
  straight out. Measured: zero interference with the rail raised 2 mm.

  Compounding it, the rails were placed FROM slot_top_hw - the groove's widest
  half-width - so the profile cut removed nothing from them. Horizontal slices
  came back at a constant 1173 mm2 through the full height: two plain blocks
  with vertical faces and no taper anywhere. Building the block SOLID and
  cutting the groove out of it makes that failure impossible to repeat.

  ★ AND THE FLOOR IS RELIEVED, NOT THE ROOF. Measured seating drops on the old
  geometry: floor contact at 0.100 mm, flanks at 0.523 mm. The flat root face
  landed first, by 5.2x - so the wedge carried nothing and the whole reason for
  choosing a slide over a twist evaporated. The 0.100 was not even a designed
  clearance; it was the -0.1 modelling epsilon. FLOOR_RELIEF now exceeds the
  0.523 the flanks need, so the taper is the only seat.
*/
flank_slope   = ((dt_top - dt_base) / 2) / dt_h;              // 0.700
flank_norm    = flank_clear / cos(atan(flank_slope));         // 0.3662
FLOOR_RELIEF  = 1.00;                                         // > 0.523
/*
  ★★ AND A MOUTH RELIEF, WHICH THE FLOOR RELIEF ALONE DID NOT GIVE.

  Relieving the floor was necessary and not sufficient. The rail's root is the
  CAP'S OWN FACE - so with the groove only FLOOR_RELIEF deeper than the rail is
  tall, the cap's face lands flat on the adapter's face at 0.000 mm while the
  flanks still need 0.523 mm to close. Measured by a review: "the flanks do not
  seat; the rail root seats on the rails' end faces."

  That is the SAME defect a third time, in a third place: first the roof, then
  the floor, now the mouth. Each time a flat face beat the taper to contact.
  The groove must be deeper than the rail at BOTH ends, so nothing flat can
  touch anywhere and the wedge is the only thing bearing.

      groove depth 7.0 = dt_h 5.0 + FLOOR_RELIEF 1.0 + MOUTH_RELIEF 1.0
      cap face sits 1.000 clear, and 0.477 clear once the flanks seat
*/
MOUTH_RELIEF  = 1.00;
slot_mouth_hw = dt_base / 2 + flank_norm;                     //  7.8662
slot_deep_hw  = dt_top  / 2 + flank_norm;                     // 11.3662

// ============================================================ ADAPTER

plate_w     = 50.0;
plate_l     = 46.0;
floor_t     = 1.8;     // under the insert. In COMPRESSION - the screw pulls down
base_t      = floor_t + ins_len;                 // 7.5
rail_h      = dt_h + FLOOR_RELIEF + MOUTH_RELIEF;   // 7.00
adapter_h   = base_t + rail_h;                   // 14.00

/*
  ★★ THE FLANKS MUST STAY PARALLEL, AND MY FIRST VERSION DID NOT.

  I wrote slot_base_hw = dt_base/2 + flank_clear and slot_top_hw = dt_top/2 +
  flank_clear, with the roof at dt_h + flank_clear. That grows X by 0.30 AND
  raises the top by 0.30 - rise without run - so the female flank came out at
  slope 0.660 against the male's 0.700. Contact was then two LINE contacts on
  the rail's top corners, not face contact on the flanks. Everything the slide
  was chosen for depends on face contact.

  It is also the exact defect dovetail.scad already documents and warns about
  ("the old X-offset gave 0.255 mm at root, 0.091 at tip"). I reintroduced it
  in a file whose header explains why it must not happen.

  A clearance measured PERPENDICULAR to the flank is flank_clear / cos(angle).
  The flank sits 34.99 degrees off vertical, so 0.30 perpendicular is 0.3662
  horizontal - and the roof is then lifted SEPARATELY by ROOF_RELIEF.
*/

// ============================================================ CAP

/*
  The cap grips the case body's FLANGE BAND rather than bolting to the lid.
  case.scad puts that band at full envelope 64.4 x 96.4 over z 26.74 to 34.34 -
  7.6 mm tall, right around the case, with a 45 degree flare below it that is a
  free self-centring lead-in and a positive bottom stop.

  ★ WHY NOT THE LID. The sealing land is exactly 6.000 mm wide and the gasket
  gland takes 4.0 of it. An M3 heat-set insert needs 7.2; a nut pocket needs
  ~6.5. NEITHER WILL EVER FIT - so the eight lid screws are permanently
  condemned to be threads cut directly into printed ASA, on every future
  revision. Those same threads are the only thing storing the gasket's preload
  AND the joint opened for USB access. One un-upgradeable fastener set cannot
  do three incompatible jobs.
*/
band_w      = 64.4;
band_l      = 96.4;
band_h      = 7.6;
cap_clear   = 0.30;    // per side, over the band
cap_wall    = 2.5;
/*
  ★★ 5.0, BECAUSE THE CAP NOW CARRIES THE EIGHT SCREWS - AND BECAUSE IT
  DID NOT CARRY ANYTHING AT ALL UNTIL 29 Aug 2026.

  The first version of mount_cap() was a rectangular pocket 0.30 mm larger than
  the case on every side, with NO screw, NO clip, NO lip and NO detent. The
  header comment said the eight sealing screws "run up through the cap"; the
  geometry contained no holes. The case was retained by nothing, and the escape
  direction is straight out toward the rider, where neither gravity nor airflow
  opposes it.

  A feature that exists in prose and not in geometry is this project's
  signature defect - four previous instances are documented in case.scad and
  dovetail.scad. This was the fifth, and mine.

  5.0 leaves 2.4 mm of plate under a 2.6 mm counterbore.
*/
cap_top     = 5.0;

/*
  ★ THE SKIRT HAS TO CLEAR THE LID, NOT JUST GRIP THE BAND.

  First attempt: 8.0, sized to "cover the 7.6 mm flange band". It rendered, it
  asserted clean, and it was wrong - because the LID sits ON TOP of that band,
  5.0 mm of it, and the cap approaches from outside the lid. An 8.0 pocket puts
  the cap's roof 3.5 mm INSIDE the lid.

  Caught by exporting the STL and reading its bounding box against the case,
  not by any check in this file - the old assert compared the skirt to the band
  alone and was happy. That is the signature failure of this whole project:
  a number that is self-consistent and describes the wrong thing.

      lid                      5.00
      band grip, of 7.6        6.00
                              -----
      pocket depth            11.00
*/
lid_t       = 5.0;     // case.scad
band_grip   = 6.0;     // how far down the 7.6 band the skirt reaches
cap_skirt   = lid_t + band_grip;   // 11.0

cap_w       = band_w + 2 * cap_clear + 2 * cap_wall;   // 70.0
cap_l       = band_l + 2 * cap_clear + 2 * cap_wall;   // 102.0
cap_h       = cap_top + cap_skirt;                     // 11.5

/*
  ★ THE PIN BLOCKS THE EXIT. IT DOES NOT PASS THROUGH THE RAIL.

  My first attempt put the pin through the cap, at right angles to the slide,
  intending it to pierce the seated rail. Two things were wrong. It was in the
  wrong part - at that height it passed through open air, not through the cap's
  walls - and piercing a 5.0 mm tall rail with a 3.2 mm pin leaves 0.9 mm of
  material above and below, which is not a load path, it is a perforation.

  The pin does not need to pierce anything. The dovetail's undercut already
  form-closes every direction except the slide, so the ONLY job left is to stop
  the case travelling back out. A bar across the slot does that, in double
  shear, bearing on the rail's end face - and it sits in the ADAPTER, through
  its two rails, where there is solid material to carry it.
*/
/*
  ★ THE EIGHT SEALING SCREWS RUN CAP -> LID -> BODY. One fastener set, one
  joint, instead of two in series. These MUST match case.scad's screw_pts:

      band_x = cav_w/2 + land_w/2 - 0.2 = 26.2 + 3.0 - 0.2 = 29.0
      band_y = cav_l/2 + land_w/2 - 0.2 = 42.2 + 3.0 - 0.2 = 45.0

  ★ AND THEY ARE COUNTERBORED, all eight. The two at (0, +/-45) are swept by
  the adapter as it slides on - a proud head there jams the joint before it
  seats, which is a defect already found once on the old mount plate. The other
  six are counterbored for symmetry and because a proud head is a water trap.
*/
cs_band_x   = 29.0;
cs_band_y   = 45.0;
cap_screw_pts = [[ cs_band_x,  42.5], [-cs_band_x,  42.5],
                 [ cs_band_x, -42.5], [-cs_band_x, -42.5],
                 [ cs_band_x,   0  ], [-cs_band_x,   0  ],
                 [ 0,  cs_band_y   ], [ 0, -cs_band_y   ]];
cb_d        = 6.8;
cb_depth    = 2.6;

pin_d       = 3.2;     // 3 mm steel dowel, running fit
/*
  ★ AND IT SITS HARD AGAINST THE RAIL'S END, not "just beyond" it.

  My first number was dt_len/2 + 2.5, which the end-clearance assert rejected by
  0.1 mm. The fix is not to shave the margin - it is that 2.5 mm was wrong to
  begin with. A blocking pin set back from what it blocks IS 2.5 mm of free
  travel, and free travel in a joint that sees 60-120 Hz is a hammer.

  dt_len/2 + pin_d/2 puts the pin's surface exactly on the rail's end face.
  The 0.2 is assembly clearance and nothing more - the case slides fully home,
  THEN the pin drops in behind it.
*/
dt_stop_y   = dt_len / 2;          // the closed end, where the rail lands
// ★ NEGATIVE: the pin must sit at the OPEN end, behind the seated rail. At +y
// it would have been guarding the end that is already solid.
pin_y       = -(dt_len / 2 + pin_d / 2 + 0.2);
drain_d     = 2.4;

corner_r    = 4.0;

// ============================================================ DERIVED

echo(str("adapter ", plate_w, " x ", plate_l, " x ", adapter_h,
         "  (boss ", boss_h, " below)"));
echo(str("cap     ", cap_w, " x ", cap_l, " x ", cap_h));
echo(str("slot: mouth ", slot_mouth_hw * 2, ", deep ", slot_deep_hw * 2,
         ", floor relief ", FLOOR_RELIEF, " - undercut, flanks seat"));
echo(str("screw: needs floor ", floor_t, " + insert ", ins_len,
         " = ", floor_t + ins_len, " mm past the socket face"));

// ============================================================ ASSERTS

assert(boss_h < sq_depth - 0.1,
       "square boss bottoms out - the flat face must seat, not the boss");
// ★ the flanks must seat BEFORE the flat root face, or the wedge carries
// nothing. The rail can drop flank_norm/flank_slope before the tapers meet.
assert(FLOOR_RELIEF > flank_norm / flank_slope + 0.2,
       "floor relief too small - the rail's flat root lands before its flanks");
// ★ the whole mechanism argument dies if these two are not parallel
assert(abs((slot_deep_hw - slot_mouth_hw) / dt_h - flank_slope) < 1e-6,
       "slot flanks are not parallel to the rail's - contact is on the corners");
// ★ a groove wider at its mouth than inside is a V, not a dovetail
assert(slot_deep_hw > slot_mouth_hw + 1.0,
       "groove is not undercut - the rail lifts straight out");
assert(len(cap_screw_pts) == 8,
       "the cap must carry all eight sealing screws or it retains nothing");
assert(cap_top - cb_depth >= 2.0,
       "counterbore leaves too little plate under the screw head");
assert(floor_t >= 1.5,
       "floor under the insert too thin");
assert(ins_bore + 2 * ins_wall < sq_flats,
       "insert boss wider than the square key it sits in");
assert(base_t > ins_len + 1.0,
       "base plate too thin for the insert");
assert(slot_deep_hw * 2 + 6 < plate_w,
       "slot wider than the plate it is cut in");
assert(dt_len <= plate_l - 4,
       "dovetail longer than the adapter");
assert(cap_skirt >= lid_t + 3.0,
       "cap pocket too shallow - its roof lands inside the lid");
assert(band_grip <= band_h,
       "skirt reaches past the flange band onto the 45 degree flare");
assert(band_grip >= 4.0,
       "too little of the flange band gripped to react the mount moment");
// the pin sits mid-height in the adapter's rails, and must bear on the male
// rail's end face - so it has to overlap the rail's own 5.0 mm height
assert(rail_h / 2 - pin_d / 2 > 1.2,
       "pin hole leaves too little material below it in the adapter rail");
assert(rail_h / 2 + pin_d / 2 < rail_h - 1.2,
       "pin hole breaks out of the top of the adapter rail");
assert(rail_h / 2 - pin_d / 2 < dt_h,
       "pin sits above the seated rail and would block nothing");
assert(abs(pin_y) + pin_d / 2 < plate_l / 2 - 2,
       "pin hole runs off the end of the adapter");
assert(pin_y < 0 && dt_stop_y > 0,
       "pin and stop must be at opposite ends or one direction is unguarded");
assert(MOUTH_RELIEF > flank_norm / flank_slope + 0.2,
       "mouth relief too small - the cap's face lands before the flanks seat");
// the cap's drain slots pass within a whisker of the corner screws
assert(31.25 - (cs_band_x + scr_clear_d / 2) > 0.4,
       "cap drain slot breaks into the corner screw hole");
assert(atan(dt_h / ((dt_top - dt_base) / 2)) > 45,
       "dovetail flank not self-supporting");

// ============================================================ PRIMITIVES

module rrect(w, l, h, r) {
    hull() for (x = [-1, 1], y = [-1, 1])
        translate([x * (w/2 - r), y * (l/2 - r), 0]) cylinder(h = h, r = r);
}

// Rounded square, across-flats `s`, corner radius `r`.
module rsquare(s, r, h) {
    hull() for (x = [-1, 1], y = [-1, 1])
        translate([x * (s/2 - r), y * (s/2 - r), 0]) cylinder(h = h, r = r);
}

/*
  The female slot profile. NOT dovetail.scad's dt_profile(dt_clear) - that
  grows the top edge too, which is the defect this file exists to fix.
  Flanks grow by flank_clear; the roof is lifted by ROOF_RELIEF instead.
*/
/*
  y = 0 is the groove FLOOR; y = rail_h is its MOUTH, at the adapter's top.
  Wide at the floor, narrow at the mouth - which is what traps the rail.

  ★ PARAMETERISED BY CLEARANCE ON PURPOSE. The tolerance coupon calls this with
  each candidate value, so it tests the SAME construction the real part uses. A
  review found the previous coupon still built its slots the old, non-parallel
  way - so the number the rider would have picked off it described a fit that no
  longer existed anywhere. A calibration piece that does not share its geometry
  with the part is worse than no calibration piece.
*/
module slot_profile_c(c) {
    fn = c / cos(atan(flank_slope));
    mh = dt_base / 2 + fn;
    dh = dt_top  / 2 + fn;
    ty = FLOOR_RELIEF + dt_h;          // top of the taper
    polygon([[-dh, -0.1], [ dh, -0.1],
             [ dh, FLOOR_RELIEF],      // floor relief: nothing flat below
             [ mh, ty],                // the taper - the ONLY bearing surface
             [ mh, rail_h + 0.1],      // mouth relief: nothing flat above
             [-mh, rail_h + 0.1],
             [-mh, ty],
             [-dh, FLOOR_RELIEF]]);
}
module slot_profile() { slot_profile_c(flank_clear); }

// ============================================================ PART A

module mount_adapter() {
    difference() {
        union() {
            rrect(plate_w, plate_l, base_t, corner_r);
            /*
              ★ THE 0.5 OVERLAPS ARE NOT SLOP - THEY ARE WHAT MAKES THIS ONE
              SOLID. Built flush, the rails met the plate on a single plane and
              the key met it on 0.01 mm, and CGAL reported `Volumes: 2` - the
              part would have sliced as two separate objects and printed as
              loose pieces. Coincident faces are not a join. Every added solid
              here reaches INTO the one it lands on.
            */
            // ★ SOLID, then the groove is cut out of it. Placing two separate
            // rails is what let the groove fail to exist at all.
            translate([0, 0, base_t - 0.5])
                rrect(plate_w, plate_l, rail_h + 0.5, corner_r);
            translate([0, 0, -boss_h])
                rsquare(sq_flats - 2 * sq_clear, sq_r, boss_h + 0.5);
        }

        /*
          ★★ THE GROOVE IS CLOSED AT +y. IT USED TO RUN OUT BOTH ENDS.

          A review measured it: one pin blocks +y travel and NOTHING stopped -y.
          The cap could walk straight off the far end of the adapter, on the
          road, with the pin fitted and looking correct.

          Open at -y so the case slides on; a solid stop at +y so it cannot
          pass through. dovetail.scad's warning is about a slot closed at BOTH
          ends - a closed pocket nothing can enter. One end closed is a STOP,
          which is what a slide wants.
        */
        translate([0, (dt_stop_y - plate_l/2 - 1) / 2, base_t]) rotate([90, 0, 0])
            linear_extrude(dt_stop_y + plate_l/2 + 1, center = true) slot_profile();

        // insert bore, from the slot floor down
        translate([0, 0, base_t - ins_len])
            cylinder(h = ins_len + 0.1, d = ins_bore);
        // screw clearance, all the way through including the key
        translate([0, 0, -boss_h - 0.1])
            cylinder(h = boss_h + floor_t + 0.2, d = scr_clear_d);

        // ★ the locking pin: straight through both rails, across the slot
        translate([0, pin_y, base_t + rail_h / 2]) rotate([0, 90, 0])
            cylinder(h = plate_w + 2, d = pin_d, center = true);

        /*
          ★ DRAINS AT THE CLOSED END. The adapter stays on the bike in the rain
          with the case in the rider's pocket, so the groove is an open channel
          pointing at the sky - and it is closed at +y, which makes it a gutter
          with one end blocked. Water and road grit collect against the stop,
          then get ground into the flanks the next time the case slides on.
          Grit in a dovetail is a lapping compound.

          Two O3 holes through the floor at the closed end, where it pools.
        */
        for (x = [-1, 1])
            translate([x * 5.0, dt_stop_y - 4.0, -boss_h - 1])
                cylinder(h = base_t + boss_h + 2, d = 3.0);
    }
}

// ============================================================ PART B

module mount_cap() {
    difference() {
        union() {
            rrect(cap_w, cap_l, cap_h, corner_r + cap_wall);
            // the male rail. Its profile runs 0.5 BELOW the cap's face for the
            // same reason as the adapter's rails - see the note there. The
            // functional taper, 0 to dt_h, is untouched.
            translate([0, 0, cap_h]) rotate([90, 0, 0])
                linear_extrude(dt_len, center = true)
                    polygon([[-dt_base/2, -0.5], [dt_base/2, -0.5],
                             [ dt_top/2, dt_h], [-dt_top/2, dt_h]]);
        }
        // the pocket the case's flange band drops into
        translate([0, 0, -0.1])
            rrect(band_w + 2 * cap_clear, band_l + 2 * cap_clear,
                  cap_skirt + 0.1, corner_r);
        // the eight screws, and their counterbores on the outer face
        for (p = cap_screw_pts) {
            translate([p[0], p[1], -0.1])
                cylinder(h = cap_h + 0.2, d = scr_clear_d);
            translate([p[0], p[1], cap_h - cb_depth])
                cylinder(h = cb_depth + 0.1, d = cb_d);
        }

        /*
          ★ DRAINS THAT ACTUALLY DRAIN. The first pair were O2.4 bores at
          x = +/-33.75 - entirely inside a wall spanning 32.5 to 35.0, so they
          never broke into the pocket. They drained nothing and were two 4 mm
          deep dirt holes in the rim. These cut from inside the pocket clean
          through the wall.
        */
        for (x = [-1, 1], y = [-1, 1])
            translate([x * 33.75, y * (cap_l/2 - 10), 1.2])
                cube([cap_wall + 2.5, drain_d, 2.6], center = true);
    }
}

// ============================================================ COUPON

/*
  ★ PRINT THIS FIRST. About 6 g and ten minutes.

  Three slot sections at three clearances on one plate, plus one male stub. Try
  the stub in each. Take the TIGHTEST that slides without forcing - it will
  loosen with wear, and the wedge takes that up, so erring tight is right.
  Then set flank_clear to the winner and print the real parts.
*/
coupon_clears = [0.20, 0.30, 0.45];

module coupon() {
    blk_w = 30; blk_l = 22; blk_h = rail_h + 3.0;   // 3 mm of floor under the groove
    for (i = [0 : len(coupon_clears) - 1]) {
        c = coupon_clears[i];
        translate([i * 40, 0, 0]) {
            difference() {
                rrect(blk_w, blk_l, blk_h, 2);
                translate([0, 0, blk_h - rail_h]) rotate([90, 0, 0])
                    linear_extrude(blk_l + 2, center = true) slot_profile_c(c);
            }
            // ★ on the SIDE face, not the top - the groove leaves only 3.6 mm
            // of top face, and the previous labels sat outside the block
            // entirely as three loose numerals on the bed.
            translate([blk_w/2 - 0.2, 0, blk_h/2]) rotate([90, 0, 90])
                linear_extrude(0.8)
                    text(str(c), size = 5.5, halign = "center", valign = "center",
                         font = "Liberation Sans");
        }
    }
    // the male stub to try in each
    translate([40, 34, 0]) {
        rrect(30, 20, 3, 2);
        translate([0, 0, 3]) rotate([90, 0, 0])
            linear_extrude(18, center = true) dt_profile(0);
    }
}

// ============================================================ LAYOUT

part = "adapter";   // "adapter" "cap" "coupon" "all"

if      (part == "adapter") mount_adapter();
else if (part == "cap")     mount_cap();
else if (part == "coupon")  coupon();
else {
    mount_adapter();
    translate([0, 90, 0]) mount_cap();
    translate([-100, 0, 0]) coupon();
}

/*
  ---------------------------------------------------------------------------
  ★ PRINT ORIENTATION AND WHY

  ADAPTER: FLAT, KEY DOWN, RAILS UP. No supports.
    The dovetail flanks sit at 55 degrees from horizontal, self-supporting.
    Layers then run in the plate's plane, so the flanks are loaded in
    compression roughly normal to the layers - FDM's strong direction, the one
    where layers cannot delaminate. The key's root is loaded in shear along the
    layer planes, which is why it is short and wide rather than tall.

  CAP: MOUTH DOWN, RAIL UP. No supports.
    The skirt's inner pocket is a plain prismatic bore printed as a vertical
    wall. The rail on top is self-supporting for the same reason as the
    adapter's slot. Printed the other way up, the pocket roof would be a
    64 x 96 bridge - unprintable.

  COUPON: FLAT. Trivial.

  ASA, 0.2 mm layers, 5 perimeters, 30-40% infill, enclosure or draft shield.

  ---------------------------------------------------------------------------
  ★ WHAT TO BUY

    M3 brass heat-set insert, 5.7 mm       x1   (buy 10, you will use them)
    M3 countersunk socket screw, ISO 10642 x1   LENGTH: see below
    3 mm steel dowel pin, ~30 mm           x1   or a split pin / clevis pin

  ★ THE SCREW LENGTH IS NOT 10 mm ANY MORE. The original clamps the socket
  plus BOBO's own thin plate. Ours needs to reach through the socket, our
  1.8 mm floor, and 5.7 mm of insert. Measure how much screw protrudes when it
  is wound fully home into the bare socket, add 7.5, and buy the next size up.
  An M3 x 14 or M3 x 16 countersunk is a few rupees and almost certainly right.
*/
