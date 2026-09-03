/*
  JiffyTrails mount v3 - QUARTER TURN. Adapter, cap, and a fit coupon.

  Open in OpenSCAD, set `part`, press F6, File > Export > STL.

  ---------------------------------------------------------------------------
  ★ WHY THIS REPLACES THE DOVETAIL IN mount_v2.scad

  The slide was chosen on a wear argument that does not survive the rider's
  real usage. Every analysis assumed twice a day - 3,650 fit/remove cycles and
  113 m of ASA on ASA - and a dovetail won because a wedge takes up its own
  wear while a bayonet's wear becomes permanent slack.

  He actually uses it for "some rides, or when going somewhere new". Call it
  260-780 cycles. Re-run at the real number:

      path per cycle      slide 68 mm      twist 28 mm   (a sixth of a turn
                                                          is SHORTER than a
                                                          34 mm slide)
      total path          18-53 m          7-22 m
      Archard wear depth  0.001 mm         0.003 mm
      against a fit clearance of           0.30 mm

  Two orders of magnitude below anything measurable. The mechanism was real
  and was never large enough to decide anything. Strength does not separate
  them either - three 34 degree lugs give 61 mm2 of root shear against a 35 N
  peak, which is 0.57 MPa and a safety factor near 30. Both are overbuilt.

  What is left is the rider's own criterion, stated four times: it must not be
  a hassle. Drop on, twist, done - one hand, gloved, nothing to align and
  nothing to drop in a car park. The loose pin is deleted.

  ---------------------------------------------------------------------------
  ★★ THE ROTATION LOCK IS A SQUARE PAWL, NOT A DETENT

  HARDWARE.md's objection to a bayonet was always the same: vibration walks
  friction joints loose. That is true of a ROUNDED detent, which is a ramp on
  both sides and can ratchet its way out under 60-120 Hz.

  A square pawl cannot. Its retaining face is at 90 degrees, so back-torque
  loads the blade as a strut ALONG its length rather than bending it, and
  there is no ramp to cam out over. That is form closure, not friction, and it
  answers the objection rather than arguing with it.

  Blade sizing, and the reason the earlier "snap clips are impossible here"
  verdict does not carry over: that clip was trapped in 1.2 mm of side
  clearance inside the case, so it had to be short and thick. This one is in
  open air on the adapter's face.

      L 18.0   t 1.6   b 8.0   deflection 1.5 mm
      root strain  3yt/2L^2  =  1.11%      (ASA yields near 2.5%)
      release force 3EIy/L^3 =  4.0 N      (a gloved thumb does not notice)

  Strain enters as L squared, so eighteen millimetres of length costs a fifth
  of the strain twelve would.

  Fatigue: 260-780 fittings is ~520-1560 flexes. ASA's endurance limit sits
  near 30-40% of static strength at 10^6 cycles; we are at 44% for 1.5x10^3.
  Roughly 700x short of where that limit is even measured. Not a driver.

  ★ AND IT FAILS SAFE. If the blade cracks, axial retention is untouched - the
  lugs are still under the cone and the case stays on. What is lost is the
  lock, and reaching the release slots still needs 60 degrees of deliberate
  rotation against the cone's preload. It is also the inspectable failure: the
  blade sits on the outside at arm's length, unlike a cracked lug in a blind
  pocket, which was the old file's own objection to bayonets.

  ---------------------------------------------------------------------------
  ★ THE SOCKET-SIDE INTERFACE IS FINAL AND MEASURED. DO NOT EDIT.

      square recess   14.0 across flats, 2.17 corner radius, 2.0 deep
      screw           ISO 10642 M3 countersunk, steel
      thread          M3 brass heat-set insert in OUR part

  See docs/MOUNT_INTERFACE.md for how the 2.17 was derived from two rule
  readings that cross-check. Everything above that plane is open; nothing at
  or below it is.
*/

$fn = 64;

// ============================================================ LOCKED - socket side

sq_flats    = 14.0;    // measured, across flats
sq_r        = 2.17;    // derived from the 18.0 diagonal
sq_depth    = 2.0;     // measured
sq_clear    = 0.25;    // per side, printed boss into a moulded pocket
boss_h      = 1.8;     // deliberately < sq_depth: the FLAT FACE seats

ins_len     = 5.7;     // Ruthex RX-M3x5.7 or equivalent
ins_bore    = 4.0;     // manufacturer's recommended hole
ins_wall    = 1.9;
scr_clear_d = 3.4;

// ============================================================ BAYONET

qt_lip_r     = 11.5;   // shoulder inner radius - lugs trap under this
qt_lug_r     = 15.0;   // lugs reach this radius
qt_lug_t     = 3.0;    // lug thickness
qt_clear     = 0.30;   // running fit, swept on the coupon before committing
qt_cone      = 45;     // shoulder angle. Self-supporting AND a radial wedge.

/*
  ★ ONE LUG IS WIDER THAN THE OTHER TWO, AND SO IS ITS SLOT.

  Three-fold symmetry gives three entry positions, two of them with the screen
  sideways. In the rain, in a hurry, that is three chances to get it wrong and
  no feedback until it is on. Keyed, it drops the last few millimetres in
  exactly ONE orientation and sits flat; any other position stands proud and
  visibly wobbles.
*/
/*
  ★★★ THE LUG'S TAPER WAS INVERTED, AND THAT IS WHY NOTHING ASSEMBLED.

  Work out the space the lug has to fill. The lip's underside is a 45 degree
  cone running from (r = collar_ir, z = lug_space) up to (r = qt_lip_r,
  z = lug_space + cone_rise). So the headroom under it is

      TALL at small radius   (7.1 mm at r 11.5)
      SHORT at large radius  (3.6 mm at r 15.3)

  The lug must therefore be THICK at its inner edge and THIN at its rim. Mine
  was the exact opposite - thin inside, thick outside - so it fouled the lip
  before it entered and the cap stopped 9 mm high. No amount of moving parts
  fixes an inverted shape.

      lug_h_out   at r = qt_lug_r   = qt_lug_t
      lug_h_in    at r = qt_lip_r   = qt_lug_t + lug_cone
*/
lug_cone     = 3.5;    // = qt_lug_r - qt_lip_r, so the cone is 45 degrees
qt_lug_deg   = 34;
qt_slot_deg  = 44;
qt_key_lug   = 44;     // the wide lug
qt_key_slot  = 54;     // and its slot
qt_twist     = 55;     // how far you turn it, to a hard stop

// ============================================================ PAWL

/*
  ★★ THE PAWL HAD NOTHING TO GRIP. Found 2 Sep 2026, by asking what its tooth
  actually touched.

  The first draft put the blade outside the collar at r 19.1 with its tooth
  pointing inward - straight at the collar's own wall. The cap's lugs are
  INSIDE the collar at r 11.5-15.0, with 3 mm of adapter between them and the
  tooth. It engaged the adapter. It locked nothing. A decorative flap that
  rendered, asserted and exported perfectly.

  The fix gives the cap a short SKIRT that comes down over the collar, with a
  blind notch in its OUTER face. The pawl rides that face during the twist and
  drops into the notch at the stop. Tooth inward, thumb outward, both in open
  air where a gloved hand can reach.

      skirt inner r   collar_or + 0.4   = 18.9
      skirt outer r                       21.4
      notch depth                          1.8   -> pawl deflection 1.8
      root strain  3yt/2L^2                1.33%  (ASA yields near 2.5%)
*/
pawl_l       = 18.0;
pawl_t       = 1.6;
pawl_b       = 8.0;    // width, standing in Z - see PRINT ORIENTATION
pawl_notch   = 1.8;    // notch depth in the cap's skirt
pawl_y       = pawl_notch;              // the tooth must clear the notch
pawl_tooth   = pawl_notch + 0.3;        // reaches into it with margin
pawl_tab     = 3.0;    // thumb tab, standing proud of the blade

/*
  ★★ pawl_w WAS USED AS MILLIMETRES AND AS DEGREES. One constant, two units.

  The tooth was built as a 5.0 MM straight cube; the notch was swept as a 5.0
  DEGREE sector, which at r 19.6 is 2.39 mm of arc. Less than half the tooth
  could ever enter, and it would have landed on the notch's end edges. Two
  separate names now, and the notch is derived from the tooth so they cannot
  drift apart.
*/
pawl_tooth_w = 5.0;                                   // millimetres, the tooth
pawl_notch_w = pawl_tooth_w + 1.2;                    // millimetres, with entry slop

/*
  ★★ THE SKIRT WAS SMALLER THAN THE PLATE IT SLIDES OVER.

  18.9 was chosen against collar_or (18.5) and the assert checked only that.
  The adapter's plate is plate_r = 20.0, and the skirt has to pass it - so the
  cap jammed 8 mm above its seat. The assert passed while measuring the wrong
  member, which is the same failure as the cap pocket that had no room for the
  lid. Both radii are now derived from plate_r, not from the collar.
*/
cap_skirt_ir = 20.0 + 0.4;                            // clears plate_r
cap_skirt_or = cap_skirt_ir + 2.5;
cap_skirt_h  = 10.3;

// ============================================================ ADAPTER

/*
  ★ THE INSERT BOSS STANDS UP INTO THE COLLAR'S BORE, which is empty space.
  Sinking it into a thick base plate instead cost 5.5 mm of height for nothing:
  a bayonet's centre carries no load, it only needs a clearance path for the
  screw. The floor under the insert is 2.0 mm and it is in COMPRESSION - the
  screw pulls the adapter down onto the socket - which is the direction printed
  layers are strongest.
*/
floor_t     = 2.0;
ins_boss_r  = ins_bore / 2 + ins_wall;              // 3.9
collar_ir   = qt_lug_r + qt_clear;                  // 15.3, lugs pass
collar_or   = collar_ir + 3.2;                      // 18.5
lug_space   = qt_lug_t + qt_clear;                  // 3.30
cone_rise   = (collar_ir - qt_lip_r) * tan(qt_cone);// 3.80
lip_t       = 2.2;
collar_h    = lug_space + cone_rise + lip_t;        // 9.30
adapter_h   = floor_t + collar_h;                   // 11.30

plate_r     = collar_or + 1.5;                      // 20.0, the adapter's disc
/*
  ★ AND A LOBE UNDER THE PAWL'S ROOT. The blade rides at r 21.7, outside the
  20.0 disc - so as first drawn it was attached to nothing and the adapter
  exported as TWO solids. A cantilever needs its root supported and its free
  end free; only the root gets the lobe.
*/
pawl_root_x = 9.0;
pawl_lobe_r = 4.5;

// ============================================================ CAP

band_w      = 64.4;    // case.scad's flange band
band_l      = 96.4;
band_h      = 7.6;
cap_clear   = 0.30;
cap_wall    = 2.5;
cap_top     = 5.0;
lid_t       = 5.0;     // ★ must match case.scad
band_grip   = 6.0;
cap_skirt   = lid_t + band_grip;                    // 11.0
cap_h       = cap_top + cap_skirt;                  // 16.0
cap_w       = band_w + 2 * cap_clear + 2 * cap_wall;
cap_l       = band_l + 2 * cap_clear + 2 * cap_wall;

cs_band_x   = 29.0;    // ★ must match case.scad's screw_pts
cs_band_y   = 45.0;
cap_screw_pts = [[ cs_band_x,  42.5], [-cs_band_x,  42.5],
                 [ cs_band_x, -42.5], [-cs_band_x, -42.5],
                 [ cs_band_x,   0  ], [-cs_band_x,   0  ],
                 [ 0,  cs_band_y   ], [ 0, -cs_band_y   ]];
cb_d        = 6.8;
cb_depth    = 2.6;
drain_d     = 2.4;
corner_r    = 4.0;

// ============================================================ DERIVED

echo(str("adapter  O", plate_r * 2, " x ", adapter_h, "  (key ", boss_h, " below)"));
echo(str("cap      ", cap_w, " x ", cap_l, " x ", cap_h));
echo(str("bayonet  lug r ", qt_lip_r, "-", qt_lug_r, ", cone ", qt_cone,
         " deg rising ", cone_rise, ", twist ", qt_twist, " deg"));
echo(str("pawl     ", pawl_l, " x ", pawl_t, " x ", pawl_b,
         ", strain ", 3 * pawl_y * pawl_t / (2 * pawl_l * pawl_l) * 100, "%"));

// ============================================================ ASSERTS

assert(boss_h < sq_depth - 0.1,
       "square key bottoms out - the flat face must seat, not the key");
assert(ins_boss_r * 2 < qt_lip_r * 2 - 2,
       "insert boss fouls the bayonet's bore");
assert(floor_t >= 1.8, "floor under the insert too thin");
assert(qt_lug_r > qt_lip_r + 2.0,
       "lug overlap too small - it would pull straight through the lip");
assert(qt_slot_deg > qt_lug_deg + 6,
       "entry slot too tight for a gloved hand");
assert(qt_key_slot > qt_key_lug + 6, "keyed slot too tight");
assert(qt_key_lug > qt_lug_deg + 6,
       "the keyed lug is not distinct enough to force one orientation");
assert(qt_twist * 3 < 360 - qt_key_slot - 2 * qt_slot_deg,
       "twist angle overruns the next slot - it would fall through");
// ★ the pawl's whole viability
assert(3 * pawl_y * pawl_t / (2 * pawl_l * pawl_l) < 0.018,
       "pawl root strain above 1.8% - it will not survive repeated flexing");
assert(pawl_tooth > pawl_y + 0.2,
       "pawl tooth shallower than its own deflection - it can cam out");
// ★ the tooth must reach the cap's skirt and nothing else
assert(pawl_r > cap_skirt_or,
       "pawl blade sits inside the cap's skirt - the thumb cannot reach it");
assert(pawl_r - pawl_tooth < cap_skirt_or,
       "pawl tooth does not reach the skirt - it would lock nothing");
assert(cap_skirt_ir > collar_or + 0.2,
       "cap skirt fouls the adapter's collar");
assert(cap_skirt_h >= collar_h,
       "cap skirt too short to cover the collar it grips");
// ★ the blade's root must actually sit on material
assert(pawl_root_x + pawl_lobe_r > 0 &&
       sqrt(pow(pawl_root_x, 2) + pow(pawl_r + pawl_t, 2)) - pawl_lobe_r < plate_r + pawl_lobe_r,
       "pawl root is not over the adapter's plate - the blade floats");
assert(3 * pawl_y * pawl_t / (2 * pawl_l * pawl_l) < 0.018,
       "pawl root strain above 1.8% after the notch depth changed");
assert(cap_skirt >= lid_t + 3.0,
       "cap pocket too shallow - its roof lands inside the lid");
assert(band_grip <= band_h, "skirt reaches past the band onto the flare");
assert(cap_top - cb_depth >= 2.0,
       "counterbore leaves too little plate under the screw head");
assert(len(cap_screw_pts) == 8,
       "the cap must carry all eight sealing screws or it retains nothing");

// ============================================================ PRIMITIVES

module rrect(w, l, h, r) {
    hull() for (x = [-1, 1], y = [-1, 1])
        translate([x * (w/2 - r), y * (l/2 - r), 0]) cylinder(h = h, r = r);
}
module rsquare(s, r, h) {
    hull() for (x = [-1, 1], y = [-1, 1])
        translate([x * (s/2 - r), y * (s/2 - r), 0]) cylinder(h = h, r = r);
}
/*
  ★ AN ANNULAR WEDGE, NOT A PIE SLICE. The first version intersected a cylinder
  with a triangle whose apex sat exactly on the rotation axis - two faces
  meeting along a line, which is the textbook way to make a mesh non-manifold.
  OpenSCAD warned on export and the geometry looked perfect.

  Starting at r 0.5 removes the apex entirely. Nothing here needs the centre;
  it is a clearance bore in every caller.
*/
module pie(deg, r, h) {
    rotate([0, 0, -deg / 2])
        rotate_extrude(angle = deg)
            translate([0.5, 0]) square([r - 0.5, h]);
}

// the three angular positions; index 0 is the KEYED one
function lug_at(i) = i * 120;
function lug_w(i)  = (i == 0) ? qt_key_lug  : qt_lug_deg;
function slot_w(i) = (i == 0) ? qt_key_slot : qt_slot_deg;

// ============================================================ ADAPTER

module adapter_collar(c = qt_clear) {
    ir = qt_lug_r + c;
    or = ir + 3.2;
    difference() {
        union() {
            // the collar wall
            difference() {
                cylinder(h = collar_h, r = or);
                translate([0, 0, -0.1]) cylinder(h = collar_h + 0.2, r = ir);
            }
            /*
              *** THE LIP AND ITS CONE ARE ONE ANNULUS, cut from a solid ring.

              Drawn as a separate cylinder(r1, r2) the cone was a SOLID frustum -
              it filled the whole bore, precisely where the cap's central boss
              has to go, so the joint could never have assembled. It also met the
              wall on a coincident face, which split the collar into two solids
              and exported non-manifold. Three failures from one shape, and the
              render looked correct throughout.

              The inner surface cones from collar_ir at the bottom to qt_lip_r at the
              top - a 45 degree overhang, self-supporting printed collar-up -
              then runs straight for the lip.
            */
            translate([0, 0, lug_space]) difference() {
                cylinder(h = cone_rise + lip_t, r = or);
                translate([0, 0, -0.1])
                    cylinder(h = cone_rise + 0.1, r1 = ir, r2 = qt_lip_r);
                translate([0, 0, cone_rise])
                    cylinder(h = lip_t + 0.2, r = qt_lip_r);
            }
        }
        // entry slots, cut through the lip and its cone
        for (i = [0 : 2])
            rotate([0, 0, lug_at(i)])
                translate([0, 0, lug_space - 0.1])
                    pie(slot_w(i), ir + 1, collar_h);
    }
}

module mount_adapter() {
    difference() {
        union() {
            hull() {
                cylinder(h = floor_t, r = plate_r);
                translate([pawl_root_x, pawl_r + pawl_t / 2, 0])
                    cylinder(h = floor_t, r = pawl_lobe_r);
            }
            translate([0, 0, floor_t]) adapter_collar();
            // the insert boss, standing up into the empty bore
            translate([0, 0, floor_t]) cylinder(h = ins_len, r = ins_boss_r);
            // the key, below the seating face
            translate([0, 0, -boss_h])
                rsquare(sq_flats - 2 * sq_clear, sq_r, boss_h + 0.5);
            pawl_blade();
            /*
              ★★ A HARD STOP. There was none: the lug space was a plain bore for
              the full 360 degrees, so past the intended 55 degrees the case
              reached the NEXT slot and lifted straight off. Verified - a lug
              placed at 120 degrees met zero interference.

              One block per lug, at the far side of the intended travel.
            */
            for (i = [0 : 2])
                rotate([0, 0, lug_at(i) + qt_twist + lug_w(i) / 2 + 3])
                    translate([0, 0, floor_t])
                        pie(4, collar_ir, lug_space);
        }
        // insert bore, from the top of its boss down
        translate([0, 0, floor_t + 0.1])
            cylinder(h = ins_len, d = ins_bore);
        // screw clearance, through the floor and the key
        translate([0, 0, -boss_h - 0.1])
            cylinder(h = boss_h + floor_t + 0.2, d = scr_clear_d);
        // drains: the adapter lives on the bike in the rain with the case in
        // a pocket, so the collar is an open cup pointing at the sky
        for (a = [60, 180, 300])
            rotate([0, 0, a]) translate([collar_ir - 1.5, 0, -0.1])
                cylinder(h = floor_t + 0.2, d = 3.0);
    }
}

// ============================================================ PAWL

/*
  ★ THE BLADE DEFLECTS IN THE BED PLANE, and that is not a detail.

  Laid flat on the adapter's face, tangential, tooth outward, its 8 mm width
  standing in Z: bending stress then runs ALONG the extruded roads and the
  layer interfaces see no tension. At 1.6 mm thick it is all perimeter, no
  infill, no seam.

  Deflecting it in Z instead would put the root in tension ACROSS the layer
  bonds. That is the printed hinge that snaps on its third use, and it is the
  one orientation of this part I would refuse to print.
*/
pawl_r  = cap_skirt_or + 0.3;   // the blade rides just outside the cap's skirt

module pawl_blade() {
    rotate([0, 0, 90]) translate([pawl_r, -pawl_l / 2, floor_t - 0.5]) {
        // ★ -0.5 so the blade reaches INTO the base plate. Built flush it only
        // touched, and a touching union is two solids, not one.
        cube([pawl_t, pawl_l, pawl_b + 0.5]);                       // the blade
        /*
          ★ ONE block through the blade, not a tooth and a tab meeting it
          separately. Drawn as two they shared an edge with the blade - three
          bodies along one line - and the adapter exported NON-MANIFOLD. It
          rendered, it asserted, it looked right; a slicer would have had to
          guess. Tooth inward, tab outward, one solid passing through.
        */
        translate([-pawl_tooth, pawl_l - pawl_tooth_w, 0])
            cube([pawl_tooth + pawl_t + pawl_tab, pawl_tooth_w, pawl_b + 0.5]);
    }
}

// ============================================================ CAP

lug_h_in = qt_lug_t + lug_cone;      // 6.5, at the inner edge

module cap_lugs() {
    for (i = [0 : 2])
        rotate([0, 0, lug_at(i)])
            difference() {
                intersection() {
                    pie(lug_w(i), qt_lug_r + 1, lug_h_in + 1);
                    // thick inside, thin outside - the mirror of the lip above it
                    union() {
                        cylinder(h = qt_lug_t, r = qt_lug_r);
                        translate([0, 0, qt_lug_t])
                            cylinder(h = lug_cone, r1 = qt_lug_r, r2 = qt_lip_r);
                    }
                }
                translate([0, 0, -0.1])
                    cylinder(h = lug_h_in + 1.2, r = qt_lip_r);
            }
}

module mount_cap() {
    difference() {
        union() {
            rrect(cap_w, cap_l, cap_h, corner_r + cap_wall);
            translate([0, 0, cap_h]) {
                /*
                  ★★ qt_lip_r + 1.0 WAS THE BORE'S OWN RADIUS PLUS A MILLIMETRE.
                  A boss wider than the hole it enters. It jammed on the lip and
                  the cap never descended - measured 1.0 mm of radial
                  interference over 218 degrees of lip. It must be SMALLER.
                */
                cylinder(h = lug_h_in, r = qt_lip_r - 0.4);   // the central boss
                cap_lugs();
                // ★ the skirt the pawl grips - see the PAWL block
                difference() {
                    cylinder(h = cap_skirt_h, r = cap_skirt_or);
                    translate([0, 0, -0.1])
                        cylinder(h = cap_skirt_h + 0.2, r = cap_skirt_ir);
                }
            }
        }
        // the pocket the case's flange band drops into
        translate([0, 0, -0.1])
            rrect(band_w + 2 * cap_clear, band_l + 2 * cap_clear,
                  cap_skirt + 0.1, corner_r);
        // the eight sealing screws, counterbored on the outer face
        for (p = cap_screw_pts) {
            translate([p[0], p[1], -0.1]) cylinder(h = cap_h + 0.2, d = scr_clear_d);
            translate([p[0], p[1], cap_h - cb_depth])
                cylinder(h = cb_depth + 0.1, d = cb_d);
        }
        /*
          ★ THE PAWL'S NOTCH, at the locked angle. Blind, so the tooth drops in
          and stops; a notch running the skirt's full height would let the pawl
          slide past and lock nothing. The entry side is ramped so the twist
          rides the tooth out; the retaining side is SQUARE, which is what makes
          this form closure rather than a detent that can ratchet loose.
        */
        /*
          ★ THE NOTCH, sized in MILLIMETRES and clocked to where the pawl is.
          Swept as a sector wide enough for pawl_notch_w of arc at the skirt's
          own radius - not a bare 5 degrees, which was 2.4 mm.
        */
        rotate([0, 0, qt_twist - (pawl_notch_w / 2 / cap_skirt_or) * 180 / PI])
            translate([0, 0, cap_h + 1.5])
                rotate_extrude(angle = (pawl_notch_w / cap_skirt_or) * 180 / PI)
                    translate([cap_skirt_or - pawl_notch, 0])
                        square([pawl_notch + 0.6, pawl_b - 1.0]);

        // drains, cut from inside the pocket clean through the wall
        for (x = [-1, 1], y = [-1, 1])
            translate([x * (cap_w/2 - cap_wall/2), y * (cap_l/2 - 10), 1.2])
                cube([cap_wall + 2.5, drain_d, 2.6], center = true);
    }
}

// ============================================================ COUPON

/*
  ★ PRINT THIS FIRST. Three collars at three clearances, plus one lug set.
  Try the lug set in each and take the TIGHTEST that twists without forcing -
  it loosens with wear, and the cone takes that up, so erring tight is right.
  Then set qt_clear to the winner.

  It shares slot_w/lug_w and the cone with the real parts by construction, so
  it cannot drift into testing a geometry that no longer exists - which is
  exactly what happened to the dovetail coupon in mount_v2.
*/
coupon_clears = [0.20, 0.30, 0.45];

module coupon() {
    for (i = [0 : len(coupon_clears) - 1]) {
        c = coupon_clears[i];
        translate([i * 46, 0, 0]) {
            difference() {
                union() {
                    cylinder(h = 2.0, r = collar_or);
                    translate([0, 0, 2.0]) adapter_collar(c);
                }
                translate([0, 0, -0.1]) cylinder(h = 3, d = 8);
            }
            translate([0, -collar_or - 1.0, 3.0]) rotate([90, 0, 0])
                linear_extrude(0.8)
                    text(str(c), size = 5.5, halign = "center", valign = "center",
                         font = "Liberation Sans");
        }
    }
    translate([46, 52, 0]) {
        cylinder(h = 3.0, r = qt_lip_r + 1.0);
        translate([0, 0, 3.0]) cap_lugs();
    }
}

/*
  ★★ THE COUPON NOW CALLS THE REAL COLLAR. It used to be a 35-LINE COPY of it,
  so the "cannot drift by construction" claim in the header was simply false -
  and it is the exact failure the dovetail coupon had before it. A calibration
  piece that does not share geometry with the part calibrates nothing.
*/

// ============================================================ LAYOUT

part = "adapter";   // "adapter" "cap" "coupon" "all"

if      (part == "adapter") mount_adapter();
else if (part == "cap")     mount_cap();
else if (part == "coupon")  coupon();
else {
    mount_adapter();
    translate([0, 130, 0]) mount_cap();
    translate([-120, 0, 0]) coupon();
}

/*
  ---------------------------------------------------------------------------
  ★ PRINT ORIENTATION

  ADAPTER: FLAT, KEY DOWN, COLLAR UP. No supports.
    The lip's underside is a 45 degree cone, so it is self-supporting where a
    flat shoulder would bridge. The pawl lies in the bed plane, which is the
    whole reason it survives being flexed. Bed contact is the full O40 disc.

  CAP: MOUTH DOWN, LUGS UP. Support IN THE POCKET ONLY.
    The pocket's roof is a 65 x 97 ceiling and it does need support - the
    alternative hangs a 70 x 102 body off a 30 mm boss, which is worse. The
    support lifts straight out of an open pocket.

  COUPON: FLAT. Trivial.

  ASA, 0.2 mm layers, 5 perimeters, 30-40% infill, enclosure or draft shield.
  ★ LIGHT GREY OR WHITE FILAMENT. HARDWARE.md records an 18 C interior
  difference against dark grey, which is the entire width of the thermal
  estimate. It costs nothing and it is the best value in the project.

  ---------------------------------------------------------------------------
  ★ WHAT TO BUY

    M3 brass heat-set insert, 5.7 mm       x1   (buy 10)
    M3 countersunk socket screw ISO 10642  x1   see MOUNT_INTERFACE.md for length
    8 x M3 x 14 self-tapping                    the cap+lid+body stack
    2 x M3 x 5 self-tapping                     the hood

  No pin. No thumbscrew. Nothing loose.
*/
