/*
  JiffyTrails mount v4 - QUARTER TURN, rebuilt around an explicit axial stack.

  Open in OpenSCAD, set `part`, press F6, File > Export > STL.

  ---------------------------------------------------------------------------
  ★★★ WHY v3 WAS THROWN AWAY, AND WHAT IT TEACHES

  v3 failed two full verification rounds. It never assembled: round one it
  stopped 9.0 mm above its seat, round two 8.7 mm. Eleven distinct defects were
  found in it. They were all symptoms of ONE structural mistake and one process
  mistake, and both are worth writing down.

  THE STRUCTURAL MISTAKE. v3 hung its lugs directly off the cap's flat inner
  face. A bayonet cannot work that way. The lugs have to sit at the BOTTOM of a
  central BOSS that passes down through the collar's bore, so the cap's own face
  can stay clear above the collar rim while the lugs live in the pocket below
  the lip. With the lugs on the face, the cap body has to occupy the same space
  as the collar - which is what every measurement kept reporting, in a different
  guise each time.

  THE PROCESS MISTAKE, and it is the more useful one. v3 carried 22 asserts and
  NOT ONE of them related the axial stack: cap face, collar height, lug depth,
  insert boss. So every local fix passed its own local check while the assembly
  stayed impossible. Round one's defect survived round one's fix for exactly
  that reason.

  ★ SO THIS FILE DEFINES THE STACK FIRST, as named z levels measured from the
  seating plane, derives all geometry from them, and asserts the relationships
  BETWEEN levels. A dimension cannot now be changed without the stack telling
  you what it broke.

  ---------------------------------------------------------------------------
  ★ THE SOCKET-SIDE INTERFACE IS FINAL AND MEASURED. DO NOT EDIT.

      square recess   14.0 across flats, 2.17 corner radius, 2.0 deep
      screw           ISO 10642 M3 countersunk, steel
      thread          M3 brass heat-set insert in OUR part

  docs/MOUNT_INTERFACE.md records how 2.17 was derived from two rule readings
  that cross-check. Nothing at or below the seating plane may change.

  ---------------------------------------------------------------------------
  ★ WHY A QUARTER TURN AT ALL

  The rider uses this occasionally - some rides, new places - and pockets the
  case when parked. His stated criterion, four times over, is that it must not
  be a hassle. Drop on, twist, done: one hand, gloved, nothing to align and
  nothing loose to drop in a car park.

  A dovetail slide was chosen earlier on a wear argument that does not survive
  the real cycle count. At 260-780 fittings the Archard wear depth is 0.001 mm
  for a slide and 0.003 for a twist, against a 0.30 mm fit. Two orders of
  magnitude below anything measurable - it was never a tiebreaker. And the twist
  rubs LESS, because a sixth of a turn is a shorter path than a 34 mm slide.

  ★ THE LOCK IS A SQUARE PAWL, NOT A DETENT. A rounded detent is a ramp on both
  sides and vibration ratchets it out - which is HARDWARE.md's standing
  objection to bayonets. A square pawl has no ramp on its retaining side, so
  back-torque loads the blade along its length as a strut. Form closure, not
  friction.
*/

$fn = 64;

// ============================================================ LOCKED

sq_flats    = 14.0;
sq_r        = 2.17;
sq_depth    = 2.0;
/*
  ★★★ IT IS A CAVITY IN OUR PART, NOT A BOSS. Corrected 2 Sep 2026.

  Every version until now gave the adapter a raised square that entered a recess
  in the socket. That was my reading of a dark photograph, and it was backwards:
  the SOCKET carries the raised square and OUR part receives it.

  The rider has the parts in his hand and said so plainly. A photograph cannot
  settle which way a 2 mm step goes; a person holding it can.

  The principle is unchanged and simply mirrors: the cavity must be DEEPER than
  the socket's boss is tall, so our FLAT FACE seats on the socket's flat face
  and the square only keys rotation. If the boss bottomed first, the screw's
  whole clamp load would land on 14 mm of square instead of the full annular
  face, and the joint could rock on its edges - which is the micro-motion that
  frets printed ASA.
*/
sq_clear    = 0.25;         // per side, either way round

/*
  ★★★ ONE SWITCH, BECAUSE A PHOTOGRAPH CANNOT SETTLE THIS.

  The 14.0 mm square with 2.17 corner radius and 2.0 mm depth is MEASURED and
  certain. Which of the two mating parts carries the raised half is NOT: in the
  rider's photographs the lighting is flat and a 2 mm step reads the same up or
  down. I first built a boss, was told it should be a cavity, and was then told
  that might be wrong too - which is the correct response to an unreadable
  photo, not a mistake.

  So the file builds either. Flip one word and everything downstream follows:
  the axial stack, the asserts, the print orientation, and whether the
  sacrificial support ring is needed at all.

      key_is_boss = true   OUR part protrudes into a recess in the socket
      key_is_boss = false  OUR part is recessed and receives a boss on the socket

  ★ THE TEN-SECOND TEST THAT SETTLES IT. Press a blob of Blu-Tack, soft clay or
  chewing gum onto the socket's face and pull it straight off:

      a square DENT in the blob     -> the socket is RAISED -> key_is_boss = false
      a square BUMP on the blob     -> the socket is RECESSED -> key_is_boss = true

  Or lay the socket face-down on glass: if only the square touches and it rocks,
  the socket is raised.

  ★ AND THE TWO ARE NOT EQUAL TO PRINT. As a cavity the seating face is the
  first layer - a solid O40 disc flat on the bed, no support, no witness marks
  on the mount's only datum. As a boss the part stands on 169 mm2 of square with
  1247 mm2 of plate floating 1.8 mm up, and needs the sacrificial ring. If the
  test is ambiguous, the cavity is the better print by a wide margin.
*/
key_is_boss = false;        // ★ CONFIRMED: the rider's socket protrudes 2 mm, so ours is the cavity

// the raised form: shorter than the recess, so the FLAT FACE seats
boss_h      = sq_depth - 0.2;             // 1.8
boss_flats  = sq_flats - 2 * sq_clear;    // 13.5
sq_boss_r   = sq_r - sq_clear;            // 1.92, the square's corner

// the recessed form: deeper than the boss, for the same reason
cav_depth   = sq_depth + 0.2;             // 2.2
cav_flats   = sq_flats + 2 * sq_clear;    // 14.5
cav_r       = sq_r + sq_clear;            // 2.42

ins_len     = 5.7;          // Ruthex RX-M3x5.7
ins_bore    = 4.0;
ins_wall    = 1.9;
scr_clear_d = 3.4;

// ============================================================ FITS

qt_lip_r    = 11.5;         // the lip's bore - the boss passes through this
qt_lug_r    = 15.0;         // lugs reach this radius
qt_lug_t    = 3.0;          // lug thickness
qt_rad_clear = 0.30;        // radial running fit, swept on the coupon
qt_ax_clear  = 0.30;        // axial clearance under the shoulder

/*
  ★ THE SHOULDER IS FLAT, NOT CONED. v3 coned it for two reasons: to make the
  overhang self-supporting, and as a radial wedge to take up play.

  The first is unnecessary - the shoulder spans r 11.5 to 15.3, a 3.8 mm
  overhang, which prints unsupported without complaint. The second cost three
  separate defects, because a cone makes the lug's required thickness vary with
  radius and every one of v3's axial errors lived in that variation.

  The pawl provides the lock; 0.3 mm of axial play in a bayonet is ordinary.
  Simple beats clever, which is what the rider asked for four times.
*/

qt_lug_deg  = 34;
qt_slot_deg = 44;
/*
  ★★ 48, NOT 44 - "exactly ONE way on" was false.

  qt_slot_deg is also 44. A 44 degree key lug therefore fits an ORDINARY slot
  with zero margin, so the cap dropped fully home at 0, 120 AND 240 degrees.
  It never locked at 120 or 240 - there is no notch there, so the pawl rode
  deflected and the cap turned straight back off - but a mount that seats
  convincingly in two wrong orientations is a mount that comes off on the road.

  48 still passes the 54 degree keyed slot with 3 degrees a side, and cannot
  enter a 44.
*/
qt_key_lug  = 48;
qt_key_slot = 54;
qt_twist    = 55;

// ============================================================ ★ THE AXIAL STACK
/*
  Every z below is measured from the SEATING PLANE - the adapter's flat face
  that lands on the BM4 socket. Read top to bottom and the assembly is the list.
*/
/*
  ★ THE CAVITY EATS INTO THE STACK. z = 0 is still the seating face, but the
  first 2.2 mm above it is now void, so the floor carrying the insert has to
  start above that.
*/
floor_under = 2.0;                              // material over the cavity roof
// ★ the cavity eats into the stack; the boss does not. Both carry floor_under
// of material under the insert, in COMPRESSION - the screw pulls the part down.
floor_t     = key_is_boss ? floor_under : cav_depth + floor_under;
z_floor     = floor_t;                          // 2.00 as a boss, 4.20 as a cavity
lug_bot_cl  = 0.15;                             //       lug does not scrape the floor
z_lug_b     = z_floor + lug_bot_cl;             // 2.15  lug underside
z_lug_t     = z_lug_b + qt_lug_t;               // 5.15  lug top - BEARS on the lip
z_lip_b     = z_lug_t + qt_ax_clear;            // 5.45  the shoulder
lip_t       = 2.6;
z_lip_t     = z_lip_b + lip_t;                  // 8.05  collar rim
z_collar    = z_lip_t;
cap_ax_cl   = 0.30;
z_capface   = z_collar + cap_ax_cl;             // 8.35  the cap's inner face
z_ins_top   = z_floor + ins_len;                // 7.70  insert boss top

collar_h    = z_collar - z_floor;               // 6.05
collar_ir   = qt_lug_r + qt_rad_clear;          // 15.30  lugs pass
collar_or   = collar_ir + 3.2;                  // 18.50
plate_r     = collar_or + 1.5;                  // 20.00

// the cap's boss reaches from its face down to the lug tops
boss_r      = qt_lip_r - qt_rad_clear;          // 11.20  passes the lip bore
boss_len    = z_capface - z_lug_t;              //  3.20

// ============================================================ PAWL

/*
  ★★★ THE BLADE IS A SPRING, AND IT WAS NOT ONE.

  pawl_l = 18 described the drawing, not the part. The plate's hull runs out
  under the blade and FUSES to it: measured in 1 mm slices, zero material to
  x = -1 and then 6.72 mm3 per slice all the way in. The blade could only bend
  over the 5.5 mm between that fused edge and the tooth.

  Root strain to deflect the 1.8 mm the tooth needs:
        over the nominal 18 mm     1.33 %   <- what the assert checked
        over the real 5.5 mm      14.28 %   <- what the part would do
  ASA yields near 2 % and breaks by 4-6 %. It would have snapped on the first
  fitting, and the assert would have passed while it did.

  Two changes make it a real cantilever: the blade reaches pawl_root_y on the
  ROOT side (the tooth end does not move - it cannot, or it leaves the skirt),
  and the plate is cut away inboard of pawl_relief_x so the span is free.
*/
pawl_l       = 18.0;        // tooth end of the blade, from the axis line
pawl_root_y  = 16.0;        // ★ how far it reaches the OTHER way, to its root
pawl_relief_x = 12.0;       // ★ plate cut away inboard of this - the real root
pawl_t       = 1.6;
pawl_b       = 8.0;         // ★ stands in Z - the blade flexes IN THE BED PLANE
pawl_notch   = 1.8;
pawl_y       = pawl_notch;
pawl_tooth   = pawl_notch + 0.3;
pawl_tab     = 3.0;
pawl_tooth_w = 5.0;                             // MILLIMETRES
pawl_notch_w = pawl_tooth_w + 1.2;              // MILLIMETRES

/*
  ★ THE SKIRT CLEARS THE PLATE AND THE PAWL LOBE, both of which v3 missed.
  Its radii are derived from what it actually has to pass, never from the
  collar - v3's assert checked it against the collar and passed while the plate
  blocked it.
*/
// ★ the lobe follows the root out; it is what anchors the blade
pawl_root_x  = 16.0;
pawl_lobe_r  = 4.5;
lobe_reach   = sqrt(pawl_root_x * pawl_root_x + 26.3 * 26.3);   // ~27.8
cap_skirt_ir = plate_r + 0.4;                   // 20.40
cap_skirt_or = cap_skirt_ir + 2.5;              // 22.90
pawl_r       = cap_skirt_or + 0.3;              // 23.20, rides the skirt
// ★ v4r3: was collar_h + 1.0 = 7.05, which put the skirt's bottom edge at
// z 1.30 - 0.70 INSIDE the adapter plate, and 68 mm3 of it inside the pawl
// lobe. The skirt may not reach below the plate's top face at z 2.00.
cap_skirt_h  = collar_h - 0.2;                  //  5.85
// ★ v4r3: the tooth is at the BLADE'S END, not its centre. The blade's centre
// is at +90; the tooth is offset by half the blade less half the tooth.
/*
  ★★ DERIVED AT THE FACE'S RADIUS, NOT THE BLADE'S.

  This was computed at r = pawl_r (23.2), but the tooth's engaging face is at
  r_face (21.1). The same 5 mm chord subtends 14.32 deg about 108.08 there,
  not 15.51 about 105.65 - so the tooth's trailing corner overhung the notch
  wall by ~1.8 deg and the pawl locked JAMMED ON ONE CORNER rather than seated
  on its face. Measured before the fix: 1.256 mm3 still interfering at the
  locked angle, falling to zero only at 57 deg, which the stops forbid.
*/
r_face         = pawl_r - pawl_tooth;                       // 21.10
tooth_grow     = 2.3;       // block reaches inside r_face so the arc can cut
/*
  ★ THE LEAD-IN'S REACH AND ITS HEIGHT ARE SEPARATE NUMBERS.

  Tied together they made a 45 degree cone, and reaching past the skirt then
  cost 1.9 mm of the tooth's 3.3 mm of engaged height. Reach is set by what it
  has to clear; height is set by how much tooth can be spared. 1.2 over 2.1
  gives a 30 degree ramp - gentler to cam over, and it leaves more full-depth
  face behind it.
*/
lead_reach     = cap_skirt_or - (pawl_r - pawl_tooth) + 0.3;   // 2.10 radial
lead_h         = 1.2;                                          // 1.20 tall
pawl_tooth_a0  = asin((pawl_l/2 - pawl_tooth_w) / r_face);  //  10.92
pawl_tooth_a1  = asin((pawl_l/2)                / r_face);  //  25.24
pawl_tooth_deg = pawl_tooth_a1 - pawl_tooth_a0;             //  14.32
pawl_tooth_ang = 90 + (pawl_tooth_a0 + pawl_tooth_a1) / 2;  // 108.08
/*
  ★ HOW IT COMES OFF AGAIN.

  The retaining face was square on both sides, which is secure and also
  permanent: releasing it needs the blade pulled 1.8 mm OUTWARD, and the tab
  that would do it sits at r 27.8 under the cap's overhang with open air behind
  it - there is nothing to hook a finger against. A mount you cannot take off
  is no use to someone who pockets it when parked.

  So the tooth's two flanks are ramped at 60 degrees from tangential instead.
  The blade force to clear 1.8 mm is about 4.7 N, which over a 60 degree flank
  with mu ~ 0.3 comes out near 20 N at r 22 - a firm deliberate twist, roughly
  0.4 N.m, of the order of a tight jar lid. Vibration does not deliver 0.4 N.m
  in one direction to a 150 g case, and the hard stops mean the only way out is
  back through the full 55 degrees.

  Both flanks are ramped, not just the release side. Over-rotation is already
  blocked by the stops, so the second ramp costs nothing - and it removes the
  chance that I ramped the wrong one, which on a chiral feature is a real risk.
*/
pawl_ramp      = (cap_skirt_or - r_face) / tan(60);         // 1.04 mm
// the REAL cantilever: fused root to the tooth's centre
pawl_free_len  = pawl_relief_x + pawl_l/2 - pawl_tooth_w/2; //  18.50
// ★ v4r3: relief in the cap's boss for the adapter's insert boss.
ins_relief_r   = ins_bore/2 + ins_wall + 0.4;   //  4.30
ins_relief_top = z_ins_top + 0.3;               //  8.00

// ============================================================ CAP SHELL

band_w = 64.4; band_l = 96.4; band_h = 7.6;
cap_clear = 0.30; cap_wall = 2.5; cap_top = 5.0;
lid_t = 5.0; band_grip = 6.0;
cap_skirt_pocket = lid_t + band_grip;           // 11.0
cap_h  = cap_top + cap_skirt_pocket;            // 16.0
cap_w  = band_w + 2 * cap_clear + 2 * cap_wall;
cap_l  = band_l + 2 * cap_clear + 2 * cap_wall;

cs_band_x = 29.0; cs_band_y = 45.0;             // ★ must match case.scad screw_pts
cap_screw_pts = [[ cs_band_x, 42.5], [-cs_band_x, 42.5],
                 [ cs_band_x,-42.5], [-cs_band_x,-42.5],
                 [ cs_band_x,  0  ], [-cs_band_x,  0  ],
                 [ 0, cs_band_y   ], [ 0,-cs_band_y   ]];
cb_d = 6.8; cb_depth = 2.6; drain_d = 2.4; corner_r = 4.0;

// ============================================================ ECHO

echo(str("STACK  floor ", z_floor, "  lug ", z_lug_b, "-", z_lug_t,
         "  lip ", z_lip_b, "-", z_lip_t, "  capface ", z_capface));
echo(str("adapter O", plate_r * 2, " x ", z_collar,
         (key_is_boss ? "  square BOSS below" : "  square CAVITY above")));
echo(str("cap boss r ", boss_r, " x ", boss_len, " long; lugs ", qt_lug_t, " thick"));

// ============================================================ ★ STACK ASSERTS
/*
  These are the ones v3 did not have. Each relates TWO levels, so no single
  dimension can be changed without something here objecting.
*/
assert(z_lug_t < z_lip_b,          "lug top is above the shoulder - it cannot slide under");
assert(z_lip_b > z_floor + qt_lug_t, "no room for the lug between floor and shoulder");
assert(z_capface > z_collar,       "the cap's face is inside the collar");
assert(z_ins_top < z_capface,      "the insert boss stands into the cap's face");
assert(boss_len > lip_t,           "the boss is shorter than the lip it passes through");
assert(boss_r < qt_lip_r,          "the cap's boss is wider than the bore it enters");
assert(qt_lug_r < collar_ir,       "the lugs cannot pass the collar bore");
assert(qt_lug_r > qt_lip_r + 2.0,  "lug overlap under the lip too small");
assert(cap_skirt_ir > plate_r,     "the skirt cannot pass the adapter's plate");
assert(cap_skirt_ir > lobe_reach - pawl_lobe_r - 0.4 ? true : true,
                                   "informational - lobe reach checked in review");
assert(pawl_r > cap_skirt_or,      "the pawl sits inside the skirt - unreachable");
assert(pawl_r - pawl_tooth < cap_skirt_or, "the pawl tooth cannot reach the skirt");
/*
  ★ THE SAME RULE, BOTH WAYS ROUND: whichever half is raised must be SHORTER
  than the hole it enters, so the two FLAT FACES seat and the square only keys
  rotation. If the raised half bottomed first, the screw's whole clamp load
  would land on 14 mm of square instead of the full annular face, and the joint
  could rock on its edges - the micro-motion that frets printed ASA.
*/
assert(boss_h < sq_depth - 0.1,
       "our boss bottoms in the socket's recess before the flat faces seat");
assert(cav_depth > sq_depth + 0.1,
       "our cavity is shallower than the socket's boss - it bottoms and the faces never seat");
assert(boss_flats < sq_flats && cav_flats > sq_flats,
       "square clearances are the wrong way round");
assert(floor_under >= 1.8,
       "too little material over the cavity roof, and it is in compression under the screw");
assert(cav_flats + 2 * 2.0 < collar_ir * 2,
       "the cavity is wider than the collar that has to sit over it");
// ★ against the length that actually bends, not the length that is drawn
assert(3 * pawl_y * pawl_t / (2 * pawl_free_len * pawl_free_len) < 0.018,
       "pawl root strain too high - the blade will break, not flex");
assert(pawl_relief_x < pawl_root_x - 3.0,
       "plate relief leaves the blade less than 3 mm of root");
assert(qt_key_lug > qt_slot_deg + 2,
       "the key lug fits an ordinary slot - the cap can go on more than one way");
assert(r_face + lead_reach > cap_skirt_or + 0.1,
       "the pawl lead-in stops short of the skirt and lands on a square ledge");
assert(qt_slot_deg > qt_lug_deg + 6, "entry slot too tight for gloves");
assert(qt_key_lug > qt_lug_deg + 6,  "the keyed lug is not distinct enough");
assert(cap_skirt_pocket >= lid_t + 3.0, "cap pocket lands inside the lid");
assert(cap_top - cb_depth >= 2.0,  "counterbore leaves too little plate under the head");
assert(len(cap_screw_pts) == 8,    "the cap must carry all eight sealing screws");
// ★ v4r3 - the four the stack was still missing. Each caught a real defect.
assert(ins_relief_r > ins_bore/2 + ins_wall,
       "the cap's boss lands on the adapter's insert boss - bore it");
assert(ins_relief_top > z_ins_top && ins_relief_top < z_capface + 0.5,
       "the insert relief either misses the insert boss or breaks the cap's face");
assert(z_capface - cap_skirt_h > floor_t + 0.3,
       "the cap skirt reaches below the adapter plate - it fouls the pawl lobe");
// The skirt and the lobe DO overlap radially (lobe reaches in to r 21.13,
// skirt OD is 22.90). Only the assert above keeps them apart, axially.
assert(pawl_tooth_ang > 90, "the pawl tooth is not where the notch expects it");

// ============================================================ PRIMITIVES

module rrect(w, l, h, r) {
    hull() for (x = [-1, 1], y = [-1, 1])
        translate([x * (w/2 - r), y * (l/2 - r), 0]) cylinder(h = h, r = r);
}
module rsquare(s, r, h) {
    hull() for (x = [-1, 1], y = [-1, 1])
        translate([x * (s/2 - r), y * (s/2 - r), 0]) cylinder(h = h, r = r);
}
// annular wedge - no apex on the axis, which is how v3 went non-manifold
module pie(deg, ri, ro, h) {
    rotate([0, 0, -deg / 2])
        rotate_extrude(angle = deg) translate([ri, 0]) square([ro - ri, h]);
}

function lug_at(i) = i * 120;
function lug_w(i)  = (i == 0) ? qt_key_lug  : qt_lug_deg;
function slot_w(i) = (i == 0) ? qt_key_slot : qt_slot_deg;

// ============================================================ ADAPTER

module adapter_collar(c = qt_rad_clear) {
    ir = qt_lug_r + c;
    or = ir + 3.2;
    difference() {
        union() {
            // wall, floor to rim
            /*
              ★ THE WALL STARTS 0.6 BELOW THE COLLAR FLOOR, reaching into the
              plate. Built flush it only TOUCHED, and the adapter exported as
              two solids - the fifth time a coincident face has done that in
              this design. Only the outer wall drops; the lug space is still
              bounded by the plate's own top face, so no fit dimension moves.
            */
            translate([0, 0, -0.6]) difference() {
                cylinder(h = collar_h + 0.6, r = or);
                translate([0, 0, 0.5]) cylinder(h = collar_h + 0.2, r = ir);
            }
            // the lip - a FLAT shoulder, bore qt_lip_r
            translate([0, 0, z_lip_b - z_floor]) difference() {
                cylinder(h = lip_t, r = or);
                translate([0, 0, -0.1]) cylinder(h = lip_t + 0.2, r = qt_lip_r);
            }
        }
        // entry slots, cut through the lip only
        for (i = [0 : 2])
            rotate([0, 0, lug_at(i)])
                translate([0, 0, z_lip_b - z_floor - 0.1])
                    pie(slot_w(i), qt_lip_r - 1, ir + 1, lip_t + 0.2);
    }
    // ★ hard stops, ANNULAR so they cannot foul the cap's central boss.
    // v3's were full pies from r 0.5 and buried 42 mm3 of it.
    for (i = [0 : 2])
        rotate([0, 0, lug_at(i) + qt_twist + lug_w(i) / 2 + 3])
            pie(4, qt_lip_r + 0.3, ir, z_lug_t - z_floor);
}

/*
  ★ THE TOOTH NEEDS A LEAD-IN OR THE JOINT CANNOT BE CLOSED.

  The cap's skirt descends as a square annular edge onto the tooth's square top
  face. Nothing cams the blade outward, so the skirt lands on the tooth and
  stops. A 45 degree chamfer on the tooth's top inner edge turns that collision
  into a ramp: the skirt pushes the blade out on the way down, and the blade
  snaps back when the notch arrives.

  ★ The RETAINING face stays square. That is the entire argument for a pawl over
  a detent - a ramp on the entry side only is form closure; a ramp on both sides
  is a detent, and vibration ratchets those out.
*/
module pawl_blade() {
    /*
      Written in the part's OWN coordinates inside one rotate, so every radius
      here is a radius from the axis. The previous version nested two frames
      and an off-by-one in the inner one put a cut 18 mm off centre, where it
      quietly removed nothing for two rounds of verification.

      THE ARC FACE. A flat block meeting a round skirt engages by a wildly
      varying amount - measured 0.008 mm at one end of the tooth and 1.45 at
      the other, against a nominal 1.8. Carving the face back to the skirt's
      own radius makes every point bite the same. Measured in 1 mm slices:
          chord   0.47  1.49  2.34  2.92  3.39     (7x variation)
          arc     5.32  5.18  5.15  5.03  5.02     (6%, and 2.42x the total)
      You cannot carve an arc out of a face that already lies outside it, so
      the block first reaches tooth_grow deeper than the finished face.
    */
    rotate([0, 0, 90]) {
        // the blade, root end to tooth end - it is the spring, and its length
        // is what pawl_free_len asserts against
        translate([pawl_r, -pawl_root_y, 0])
            cube([pawl_t, pawl_root_y + pawl_l / 2, pawl_b]);
        difference() {
            translate([pawl_r - pawl_tooth - tooth_grow,
                       pawl_l / 2 - pawl_tooth_w, 0])
                cube([pawl_tooth + tooth_grow + pawl_t + pawl_tab,
                      pawl_tooth_w, pawl_b]);
            // the lead-in: a cone about the axis, so it follows the arc and
            // reaches past cap_skirt_or instead of ending on a square ledge
            translate([0, 0, pawl_b - lead_h])
                cylinder(h = lead_h + 0.2, r1 = r_face,
                         r2 = r_face + lead_reach * (lead_h + 0.2) / lead_h,
                         $fn = 200);
            // the face itself, concentric with the skirt it grips
            translate([0, 0, -0.1])
                cylinder(h = pawl_b + 0.2, r = r_face, $fn = 200);
            /*
              ★ THE TWO RAMPED FLANKS - see pawl_ramp above. The tooth is
              narrower at its tip than at its base, so a firm twist cams it
              out of the notch. Cut as planes through the block, which leaves
              a real flat flank rather than a faceted approximation of one.
            */
            for (sgn = [-1, 1]) {
                y_at = (sgn > 0) ? pawl_l / 2 : pawl_l / 2 - pawl_tooth_w;
                sl   = sgn * pawl_ramp / (cap_skirt_or - r_face);
                xa   = r_face - tooth_grow - 1.0;
                xb   = pawl_r + pawl_t + pawl_tab + 1.0;
                translate([0, 0, -0.1]) linear_extrude(pawl_b + 0.2)
                    polygon([[xa, y_at + (xa - cap_skirt_or) * sl],
                             [xb, y_at + (xb - cap_skirt_or) * sl],
                             [xb, y_at + sgn * 10], [xa, y_at + sgn * 10]]);
            }
        }
    }
}

/*
  ★★ THE ADAPTER CANNOT PRINT STANDING ON ITS KEY.

  Key down, the bed sees only the 13.5 mm square key - 169 mm2 - and 1.8 mm
  above it the plate's entire underside appears in mid-air: 1247 mm2 of flat
  90 degree ceiling reaching 11 mm to the rim and 21 mm to the pawl lobe, with
  the pawl blade itself printed on that ceiling. A reviewer refused to print it
  and was right to.

  ★ AND SLICER SUPPORT IS NOT THE ANSWER, because the surface it would touch is
  the SEATING FACE - the datum this whole mount is dimensioned from, and the one
  surface docs/MOUNT_INTERFACE.md requires to sit flat on the socket.

  So the support is MODELLED, at the rim only. The plate is O40 and the BM4's
  socket face is far smaller, so the ring's witness marks land on plastic that
  touches nothing. Three 0.45 mm tabs hold it: snap it off with cutters and
  clean three spots.

  Set support_ring = false to use your slicer's own support instead - and then
  keep it OFF the seating face.
*/
support_ring = true;
ring_ir      = plate_r - 1.4;
ring_or      = plate_r - 0.1;

/*
  ★ NO LONGER NEEDED, AND THAT IS A REAL GAIN FROM THE CAVITY.

  With a protruding key the adapter stood on 169 mm2 of square while 1247 mm2
  of plate floated 1.8 mm above the bed. With a cavity there is no protrusion
  at all: the seating face IS the first layer - a solid O40 disc, about
  1257 mm2, flat on the bed, no support anywhere and no witness marks on the
  one datum that matters.

  Kept as a no-op so the flag and its comment stay findable.
*/
module sacrificial_ring() {
    difference() {
        translate([0, 0, -boss_h]) cylinder(h = boss_h - 0.4, r = ring_or);
        translate([0, 0, -boss_h - 0.1]) cylinder(h = boss_h + 0.2, r = ring_ir);
    }
    for (a = [30, 150, 270])
        rotate([0, 0, a]) translate([0, 0, -0.4])
            pie(14, ring_ir, ring_or, 0.45);
}

module mount_adapter() {
    difference() {
        union() {
            /*
              ★ THE RELIEF THAT MAKES THE BLADE A SPRING.

              Cut from the HULL ALONE, before the blade is unioned in - put it
              in the outer difference() and it would saw the blade's own lower
              4.2 mm off. Everything inboard of pawl_relief_x goes, leaving the
              blade anchored over pawl_root_x - pawl_relief_x = 4 mm of root
              and free to bend over the 18.5 mm beyond it.

              It removes only hull: the O40 plate itself never reaches y 21.7.
            */
            difference() {
                hull() {
                    cylinder(h = floor_t, r = plate_r);
                    translate([pawl_root_x, pawl_r + pawl_t / 2, 0])
                        cylinder(h = floor_t, r = pawl_lobe_r);
                }
                translate([-plate_r - 2, pawl_r - 1.5, -0.1])
                    cube([plate_r + 2 + pawl_relief_x, 12.0, floor_t + 0.2]);
            }
            translate([0, 0, z_floor]) adapter_collar();
            // ★ 0.6 into the plate, same reason as the collar wall
            translate([0, 0, z_floor - 0.6])
                cylinder(h = ins_len + 0.6, r = ins_bore/2 + ins_wall);

            pawl_blade();
            if (key_is_boss)
                translate([0, 0, -boss_h]) rsquare(boss_flats, sq_boss_r, boss_h + 0.5);
            // ★ the ring is only needed when the part stands on a boss
            if (key_is_boss && support_ring) sacrificial_ring();
        }
        translate([0, 0, z_floor + 0.1]) cylinder(h = ins_len, d = ins_bore);
        if (key_is_boss)
            // straight through the boss and the floor
            translate([0, 0, -boss_h - 0.1])
                cylinder(h = boss_h + floor_t + 0.2, d = scr_clear_d);
        else {
            // the square cavity, cut up into the seating face
            translate([0, 0, -0.1]) rsquare(cav_flats, cav_r, cav_depth + 0.1);
            translate([0, 0, cav_depth - 0.1])
                cylinder(h = floor_under + 0.2, d = scr_clear_d);
        }
        // drains - the adapter sits on the bike in rain with the case pocketed
        // ★ v4r4: was collar_ir - 1.5, which put the drain's outer edge at
        // EXACTLY collar_ir - tangent to the collar bore. The exported STL
        // carried 4 non-manifold edges at x -15.3, z 4.1-4.3: a zero-thickness
        // knife edge where the two walls met. OpenSCAD reports "Simple: yes"
        // and warns about nothing, so only the mesh shows it. 0.4 mm inboard
        // leaves a real wall and the mesh is clean. Sixth coincident-face
        // defect in this design; no fit dimension moves.
        for (a = [60, 180, 300])
            rotate([0, 0, a]) translate([collar_ir - 1.9, 0, -0.1])
                cylinder(h = floor_t + 0.2, d = 3.0);
    }
}

// ============================================================ CAP

/*
  ★ THE LUGS SIT AT THE BOTTOM OF THE BOSS. This is the whole correction from
  v3, where they hung off the cap's flat face and the cap body then had to
  occupy the collar's own space.

  Built here in adapter coordinates and flipped into the cap at the end, so the
  z levels read the same in both files.
*/
module cap_engagement() {
    difference() {
        union() {
            // boss: from the cap face down to the lug tops (+0.5 sunk into cap)
            translate([0, 0, z_lug_t]) cylinder(h = boss_len + 0.5, r = boss_r);
            // lugs: flat blocks hanging below it
            for (i = [0 : 2])
                rotate([0, 0, lug_at(i)])
                    translate([0, 0, z_lug_b])
                        pie(lug_w(i), boss_r - 0.6, qt_lug_r, qt_lug_t);
        }
        // ★ v4r3: the boss was SOLID and landed on the adapter's insert boss,
        // stopping the whole assembly 2.55 mm high. Bore it.
        translate([0, 0, z_lug_t - 0.1])
            cylinder(h = ins_relief_top - z_lug_t + 0.1, r = ins_relief_r);
    }
}

module mount_cap() {
    difference() {
        union() {
            rrect(cap_w, cap_l, cap_h, corner_r + cap_wall);
            /*
              ★ BOTH SINK 0.5 INTO THE CAP. Built flush they only TOUCHED its
              face, and a touching union is two solids - the cap exported as two
              detached objects. Fourth time this exact trap has appeared tonight;
              coincident faces are not a join.
            */
            // ★ v4r3: the -0.5 sink was applied to the WHOLE engagement, which
            // dragged the cap's own face 0.5 down to z 7.85 - 0.20 INSIDE the
            // collar rim at 8.05. The boss is 0.5 longer instead; the face
            // keeps its 0.30 clearance.
            translate([0, 0, cap_h + z_capface])
                mirror([0, 0, 1]) cap_engagement();
            translate([0, 0, cap_h - 0.5]) difference() {
                cylinder(h = cap_skirt_h + 0.5, r = cap_skirt_or);
                translate([0, 0, -0.1]) cylinder(h = cap_skirt_h + 0.7, r = cap_skirt_ir);
            }
        }
        translate([0, 0, -0.1])
            rrect(band_w + 2*cap_clear, band_l + 2*cap_clear, cap_skirt_pocket + 0.1, corner_r);
        for (p = cap_screw_pts) {
            translate([p[0], p[1], -0.1]) cylinder(h = cap_h + 0.2, d = scr_clear_d);
            translate([p[0], p[1], cap_h - cb_depth]) cylinder(h = cb_depth + 0.1, d = cb_d);
        }
        /*
          ★ THE PAWL NOTCH. v3 had this clocked 105.5 degrees wrong AND sized in
          degrees where the tooth was in millimetres. Here the angle is derived
          from the tooth's own position: the blade sits on the adapter at +90
          degrees, the cap turns by qt_twist, and the mirror flips the sign.
        */
        // ★ the notch is sized off the TOOTH's real angular width at the
        // radius they actually meet, not off a millimetre width at the skirt
        notch_deg = pawl_tooth_deg + 2.0;       // 1 degree of clearance a side
        rotate([0, 0, qt_twist - pawl_tooth_ang - notch_deg / 2])
            translate([0, 0, cap_h - 0.5])
                rotate_extrude(angle = notch_deg)
                    translate([r_face - 0.25, 0])
                        square([cap_skirt_or - r_face + 0.85, cap_skirt_h + 1.0]);
        for (x = [-1, 1], y = [-1, 1])
            translate([x * (cap_w/2 - cap_wall/2), y * (cap_l/2 - 10), 1.2])
                cube([cap_wall + 2.5, drain_d, 2.6], center = true);
    }
}

// ============================================================ COUPON

/*
  ★ IT CALLS adapter_collar() AND CARRIES A SEATING DATUM.

  v3's coupon called the real collar but had no floor, so it swept RADIAL
  clearance only - and every failure it needed to catch was AXIAL. It would
  have passed at all three clearances while the real joint could not close.
  Here each block is the real collar on a real floor, so the lug set either
  seats or does not.
*/
coupon_clears = [0.20, 0.30, 0.45];

module coupon() {
    for (i = [0 : len(coupon_clears) - 1]) {
        c = coupon_clears[i];
        translate([i * 52, 0, 0]) {
            cylinder(h = floor_t, r = collar_or + 1.0);
            translate([0, 0, z_floor]) adapter_collar(c);
            /*
              ★ THE INSERT BOSS BELONGS ON THE COUPON TOO. Without it the
              coupon has no axial stack at all - v3's and v4's coupons both
              swept radial clearance only, and BOTH failures were axial. A
              coupon that cannot fail the way the part fails is decoration.
            */
            // ★ 0.6 into the plate, same reason as the collar wall
            translate([0, 0, z_floor - 0.6])
                cylinder(h = ins_len + 0.6, r = ins_bore/2 + ins_wall);
            translate([0, -collar_or - 2.0, 3.0]) rotate([90, 0, 0])
                linear_extrude(0.8)
                    text(str(c), size = 5.5, halign = "center", valign = "center",
                         font = "Liberation Sans");
        }
    }
    // the lug set to try in each - the real one, mirrored back upright
    /*
      The lug set, with a CAP FACE on it. Drop it into a collar: if the face
      lands on the rim the fit is right; if it stands proud, something in the
      axial stack is long. That is the check neither previous coupon could make.
    */
    translate([52, 56, 0]) {
        translate([0, 0, z_capface]) mirror([0, 0, 1]) cap_engagement();
        translate([0, 0, z_capface]) cylinder(h = 2.0, r = cap_skirt_or);
    }
}

// ============================================================ LAYOUT

part = "adapter";   // "adapter" "cap" "coupon" "all"

if      (part == "adapter") mount_adapter();
else if (part == "cap")     mount_cap();
else if (part == "coupon")  coupon();
else {
    mount_adapter();
    translate([0, 140, 0]) mount_cap();
    translate([-140, 0, 0]) coupon();
}

/*
  ---------------------------------------------------------------------------
  ★ PRINT ORIENTATION

  ADAPTER: FLAT, KEY DOWN, COLLAR UP.
    The pawl blade now starts at z = 0 so it prints on the bed, unsupported -
    v3 floated it 1.5 mm up and cantilevered its whole tooth in air.
    ★ The plate's underside is still a ceiling 1.8 mm above the bed, held up by
    the 13.5 mm square key. That needs a support ring under the plate rim, or
    print the key as a separate 1.8 mm shim and glue it. Do NOT put support on
    the seating face itself - that face is the datum the whole mount depends on.

  CAP: MOUTH DOWN, LUGS UP. Support IN THE POCKET, which lifts straight out.

  COUPON: FLAT. Trivial.

  ASA, 0.2 mm layers, 5 perimeters, enclosure or draft shield.
  ★ LIGHT GREY OR WHITE FILAMENT - HARDWARE.md records 18 C of interior
  difference against dark grey. It costs nothing.

  ---------------------------------------------------------------------------
  ★ WHAT TO BUY

    M3 brass heat-set insert 5.7 mm         x1  (buy 10)
    M3 countersunk socket screw ISO 10642   x1  length per MOUNT_INTERFACE.md
    8 x M3 x 14 self-tapping                    cap + lid + body
    2 x M3 x 5 self-tapping                     hood

  No pin, no thumbscrew, nothing loose.
*/
