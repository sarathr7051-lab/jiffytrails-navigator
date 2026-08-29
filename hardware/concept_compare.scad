/*
  concept_compare.scad - NOT A PRINTABLE PART.

  A picture, built to answer one question: should the case open at the FRONT
  (where the screen is) or at the BACK (where the mount is)?

  Everything here is deliberately simplified. Real geometry lives in case.scad.
  The only thing this file is trying to get right is WHERE THE RED RING IS,
  because the red ring is the sealing line and its position is the whole
  decision.

  Render:
    openscad -o a.png --imgsize=1400,1100 --camera=... -D 'opt="A"' concept_compare.scad
    opt = "A"  front-opening  (what case.scad does today)
    opt = "B"  back-opening   (what the seal review recommends)
*/

$fn = 32;
opt = "A";
X   = 1;    // explode multiplier; 0 assembles it

// ---- shared sizes, near enough to the real thing ----
W   = 57;   L  = 93;   // case outline, option A
Wb  = 64;   Lb = 100;  // case outline, option B (wider flange for a real seal)
DW  = 50;   DL = 86;   // display module
AW  = 43;   AL = 58;   // active glass

module rr(w, l, h, r = 4) {
    hull() for (x = [-1, 1], y = [-1, 1])
        translate([x * (w/2 - r), y * (l/2 - r)]) cylinder(h = h, r = r);
}

// The display module: green PCB, black glass, a header stub on one edge.
module display() {
    color("#2E5548") rr(DW, DL, 1.6, 2);
    color("#12181A") translate([0, 5, 1.6]) rr(AW, AL, 1.2, 1);
    color("#C08A46") translate([0, -DL/2 + 3, -2.6]) cube([34, 2.6, 2.6], center = true);
}

// The sealing line. This is the point of the whole drawing.
module seal_ring(w, l, r = 4) {
    color("#C4342A")
    difference() {
        rr(w, l, 1.2, r);
        translate([0, 0, -0.5]) rr(w - 8, l - 8, 2.2, max(0.5, r - 4));
    }
}

module hood(w, l, d) {
    color("#23282B")
    difference() {
        rr(w + 6, l + 6, d, 3);
        translate([0, 0, -1]) rr(w, l, d + 2, 2);
    }
}

// ============================================================ OPTION A

/*
  Front-opening. The tub faces the rider; the lid carries the window and the
  hood; the seal ring therefore runs right around the display glass - the
  hardest place on the whole case to seal, and the place where any error shows
  as cropped picture.
*/
module option_A() {
    // hood + lid, lifted off
    translate([0, 0, 34 * X]) {
        color("#B9C2C0") difference() {
            rr(W, L, 2.4);
            translate([0, 5, -1]) rr(AW, AL, 5, 1.5);    // the aperture
        }
        translate([0, 5, 2.4]) hood(AW, AL, 18);
    }
    // THE SEAL - up at the top of the tub, encircling the window
    translate([0, 0, 22 + 20 * X]) seal_ring(W, L);
    // display, dropped in from the front
    translate([0, 0, 16 + 10 * X]) display();
    // the tub
    color("#9AA6AB") difference() {
        rr(W, L, 22);
        translate([0, 0, 2.4]) rr(W - 5, L - 5, 22, 2);
    }
    // mount pad, moulded into the closed back
    color("#6E7B80") translate([0, 0, -6]) rr(W, L, 6);
}

// ============================================================ OPTION B

/*
  Back-opening. The front is a permanently closed bezel with the panel bonded
  behind it; the lid is a plain plate on the mount side. The seal ring moves to
  a flat rim with nothing near it, the screw bosses move out of the display's
  way, and the aperture moves into a separate 5 g frame that can be reprinted
  if the measurement turns out wrong.
*/
module option_B() {
    /*
      Drawn SCREEN-UP, exactly like option A, so the two pictures compare
      directly. The difference you are looking for is which way the parts come
      apart: in A they lift off the front, in B they come off the back.
    */
    // body: closed front wall on TOP, cavity opening downward
    color("#9AA6AB") difference() {
        translate([0, 0, -24]) rr(Wb, Lb, 24);
        translate([0, 0, -24]) rr(Wb - 12, Lb - 12, 21, 2);  // cavity opens down
        translate([0, 5, -4]) rr(48, 74, 6, 2);              // window opening
    }
    // hood on the front, outside the sealed volume, bolted on
    translate([0, 5, 20 * X]) hood(AW, AL, 18);

    // the reprintable bezel frame - every unverified number lives in this part
    translate([0, 0, -5 + 9 * X]) {
        color("#23282B") difference() {
            rr(52, 88, 1.5, 2);
            translate([0, 5, -1]) rr(47, 62, 4, 1.5);
        }
    }
    // display, bonded up behind the frame
    translate([0, 0, -8 - 3 * X]) display();

    // THE SEAL - on a plain flat rim at the BACK, nothing near it
    translate([0, 0, -26 - 14 * X]) seal_ring(Wb, Lb, 7);
    // plain lid, no window, no hood, nothing to line up
    translate([0, 0, -32 - 22 * X]) color("#B9C2C0") rr(Wb, Lb, 5, 7);
    // mount plate, bolted to the outside of the lid
    translate([0, 0, -40 - 30 * X]) color("#6E7B80") rr(Wb, Lb, 6, 7);
}

// ============================================================ LAYOUT

if (opt == "A") option_A();
else            option_B();
