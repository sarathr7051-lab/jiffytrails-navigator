/*
  concept_options.scad - PICTURES, not printable parts.

  Three ways to grip the same ball. Each is drawn cut in half down the middle
  so you can see how it actually holds, because from the outside they all look
  like a block with a hole.

  Colours are consistent across all three:
     dark grey  = the bike's ball and stem. Yours. Never printed.
     silver     = a BOUGHT metal part
     orange     = a PRINTED part
     black      = rubber
     red        = a bought steel fastener

  Render:  -D 'opt="A"'  or  "B"  or  "C"
*/

$fn = 72;
opt = "A";

BALL = 17.0;

module ball_and_stem() {
    color("#3A4245") {
        sphere(d = BALL);
        translate([0, 0, -20]) cylinder(h = 22, d = 9);
    }
}

module rr(w, l, h, r = 4) {
    hull() for (x = [-1, 1], y = [-1, 1])
        translate([x*(w/2 - r), y*(l/2 - r)]) cylinder(h = h, r = r);
}

// The male dovetail, common to all three - it is what the case slides onto.
module dovetail(len = 34) {
    translate([0, len/2, 0]) rotate([90, 0, 0])
        linear_extrude(len) polygon([[-7.5,0],[7.5,0],[11,5],[-11,5]]);
}

// ============================================================ A

/*
  A - A BOUGHT METAL SOCKET, plus ONE printed plate.

  The socket is exactly what is already on your bike: a slotted metal collet
  with a threaded collar that screws down and squeezes it onto the ball. We
  print nothing that touches the ball. The single printed part is a flat plate
  that bolts to the socket's own face and carries the dovetail.

  ONE printed part. The ball never touches plastic.
*/
module opt_A() {
    ball_and_stem();
    // metal collet body
    color("#AEB8BC") difference() {
        translate([0, 0, -2]) cylinder(h = 16, d = 26);
        translate([0, 0, 1]) sphere(d = BALL + 0.2);
        translate([0, 0, -3]) cylinder(h = 6, d = 13);
        for (a = [0:90:359]) rotate([0, 0, a])
            translate([-0.8, 0, 4]) cube([1.6, 20, 12]);       // collet slits
    }
    // threaded collar
    color("#9AA5A9") difference() {
        translate([0, 0, 6]) cylinder(h = 9, d = 31);
        translate([0, 0, 5]) cylinder(h = 11, d = 25.4);
    }
    // the ONE printed part
    color("#C4703A") translate([0, 0, 14]) {
        rr(44, 34, 5);
        translate([0, 0, 5]) dovetail();
    }
    color("#B03A2E") for (x = [-1, 1])
        translate([x*17, 0, 12]) cylinder(h = 12, d = 4.4);     // 2 bolts
}

// ============================================================ B

/*
  B - TWO PRINTED CUPS bolted together round the ball, with a rubber liner,
  plus a separate plate for the dovetail.

  Nothing springs. You lay the ball in the lower cup, put the upper cup on,
  and two bolts pull them together. The black rubber is what actually grips.

  THREE printed parts. This is the current proposal.
*/
module opt_B() {
    ball_and_stem();
    color("#1A1A1A") difference() {                             // rubber liner
        sphere(d = BALL + 4);
        sphere(d = BALL);
        translate([0, 0, -22]) cylinder(h = 22, d = 13);
    }
    // lower cup
    color("#A2552A") difference() {
        translate([0, 0, -15]) rr(52, 34, 13);
        translate([0, 0, 2]) sphere(r = 10);
        translate([0, 0, -16]) cylinder(h = 10, r1 = 11.9, r2 = 6);
        for (x = [-1, 1]) translate([x*20, 0, -16]) cylinder(h = 15, d = 5.5);
    }
    // upper cup - the SAME part, flipped
    color("#C4703A") difference() {
        translate([0, 0, 2]) rr(52, 34, 13);
        translate([0, 0, -2]) sphere(r = 10);
        for (x = [-1, 1]) translate([x*20, 0, 1]) cylinder(h = 15, d = 5.5);
    }
    // separate dovetail plate
    color("#D4854A") translate([0, 0, 17]) {
        rr(52, 34, 4);
        translate([0, 0, 4]) dovetail();
    }
    color("#B03A2E") for (x = [-1, 1])
        translate([x*20, 0, -18]) cylinder(h = 42, d = 4.4);
}

// ============================================================ C

/*
  C - ONE PRINTED COLLET with the dovetail on top, squeezed by a hose clip.

  The way BOBO does it, and the way you suggested. Slits let the fingers open
  so the ball can be pushed in; a stainless hose clip in the groove then
  squeezes them shut.

  ONE printed part plus a 20-rupee clip. Fewer parts than BOBO.

  ★ THE OPEN QUESTION, and it is the whole reason this is not already the
  answer: the fingers have to BEND to let the ball past. On BOBO's part the
  plastic is moulded with its molecules running along the fingers. On a printed
  part the layer lines run straight ACROSS the finger root - the weakest
  possible direction for something that has to flex. Whether printed ASA
  survives that is being computed now.
*/
module opt_C() {
    ball_and_stem();
    color("#1A1A1A") difference() {                             // rubber liner
        sphere(d = BALL + 3);
        sphere(d = BALL);
        translate([0, 0, -22]) cylinder(h = 22, d = 13);
    }
    color("#C4703A") difference() {
        union() {
            translate([0, 0, -10]) cylinder(h = 26, d = 30);
            translate([0, 0, 16]) { rr(44, 34, 4);
                translate([0, 0, 4]) dovetail(); }
        }
        translate([0, 0, 1.5]) sphere(d = BALL + 3);
        translate([0, 0, -11]) cylinder(h = 12, d1 = 22, d2 = 13);
        // the slits that make the fingers - THE risk
        for (a = [0:60:359]) rotate([0, 0, a])
            translate([-1, 0, 0]) cube([2, 20, 18]);
        translate([0, 0, 8]) difference() {                      // clip groove
            cylinder(h = 5, d = 34);
            cylinder(h = 5, d = 27);
        }
    }
    color("#B03A2E") difference() {                             // hose clip
        translate([0, 0, 8.5]) cylinder(h = 4, d = 31.5);
        translate([0, 0, 8]) cylinder(h = 5, d = 29.5);
    }
}

// ============================================================ LAYOUT

// Cut in half so the grip is visible.
difference() {
    if      (opt == "A") opt_A();
    else if (opt == "B") opt_B();
    else                 opt_C();
    // Remove the FAR half, so the camera looks straight at the cut face.
    translate([-100, 0, -60]) cube([200, 200, 160]);
}
