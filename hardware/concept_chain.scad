/*
  concept_chain.scad - NOT A PRINTABLE PART.

  Answers one question: how does the case actually get onto the bike?

  Five things in a row, bottom to top. Two of them you already own and are not
  printing. The clamp's detailed shape is being redesigned, so it is drawn here
  as a simple block - what this file is trying to get right is the ORDER and
  WHAT GRIPS WHAT, not the fillets.

  Render:
    -D 'X=1'   exploded, so you can see the joints
    -D 'X=0'   assembled, as it sits on the bike
*/

$fn = 48;
X   = 1;      // explode factor

BAR   = 22;   // handlebar diameter
BALL  = 17;   // ★ the ball on your bike - BOBO 17 mm
CW    = 44;   // clamp block
CD    = 32;

CASE_W = 64.4;
CASE_L = 96.4;
CASE_H = 34.8;

module rr(w, l, h, r = 4) {
    hull() for (x = [-1, 1], y = [-1, 1])
        translate([x * (w/2 - r), y * (l/2 - r)]) cylinder(h = h, r = r);
}

// ---------- 1. YOURS. The handlebar. ----------
module handlebar() {
    color("#3A4245")
        translate([-90, 0, 0]) rotate([0, 90, 0]) cylinder(h = 180, d = BAR);
}

// ---------- 2. YOURS. The BOBO bar clamp, with the ball on top. ----------
module bar_clamp() {
    color("#1C2124") {
        difference() {
            translate([0, 0, -2]) rr(34, 30, 22, 6);
            translate([-30, 0, 0]) rotate([0, 90, 0]) cylinder(h = 60, d = BAR);
            translate([-1.4, -20, -14]) cube([2.8, 40, 12]);   // pinch split
        }
        translate([0, 0, 20]) cylinder(h = 8, d = 9);          // stem
        translate([0, 0, 28 + BALL/2 - 1]) sphere(d = BALL);   // ★ THE BALL
    }
}

// ---------- 3. OURS, PRINTED. Two halves that close around the ball. ----------
/*
  Drawn as plain blocks on purpose. The real shapes are being redesigned - what
  matters here is that they are SEPARATE, they meet at the ball's equator, and
  two bolts pull them together. Nothing snaps over anything.
*/
module clamp_lower() {
    color("#A2552A") difference() {
        translate([0, 0, -13]) rr(CW, CD, 13, 4);
        translate([0, 0, 0]) sphere(d = BALL - 0.3);
        translate([0, 0, -20]) cylinder(h = 12, d1 = 22, d2 = 11);  // stem relief
        for (x = [-1, 1]) translate([x * 16, 0, -14]) cylinder(h = 16, d = 4.4);
    }
}
module clamp_upper() {
    color("#C4703A") difference() {
        union() {
            rr(CW, CD, 13, 4);
            translate([0, 0, 13]) dovetail_male_block();
        }
        sphere(d = BALL - 0.3);
        for (x = [-1, 1]) translate([x * 16, 0, -1]) cylinder(h = 20, d = 4.4);
    }
}
module dovetail_male_block() {
    translate([0, CD/2, 0]) rotate([90, 0, 0])
        linear_extrude(CD)
            polygon([[-13, 0], [13, 0], [17, 6], [-17, 6]]);
}

// ---------- 4. OURS, PRINTED. Plate bonded to the back of the case. ----------
module mount_plate() {
    color("#B9C2C0") difference() {
        rr(CASE_W, CASE_L, 7, 7.6);
        // the slot the dovetail slides into - open at the TOP so the case
        // drops down on and gravity seats it
        translate([0, 18, -0.5]) rotate([90, 0, 0])
            linear_extrude(80)
                polygon([[-13.3, -0.5], [13.3, -0.5], [17.3, 6.3], [-17.3, 6.3]]);
    }
}

// ---------- 5. OURS, PRINTED. The case itself. ----------
module case_block() {
    color("#8E9A97") rr(CASE_W, CASE_L, CASE_H, 7.6);
    color("#23282B") translate([0, 6, CASE_H]) difference() {
        rr(52, 78, 26, 3);
        translate([0, 0, -1]) rr(47, 73, 28, 2);
    }
}

// ============================================================ STACK

handlebar();
bar_clamp();

zball = 28 + BALL/2 - 1;                   // ball centre height

translate([0, 0, zball - 14 * X])          clamp_lower();
translate([0, 0, zball + 14 * X])          clamp_upper();
translate([0, 0, zball + 19 + 30 * X])     rotate([0, 180, 0]) mount_plate();
translate([0, 0, zball + 26 + 52 * X])     case_block();
