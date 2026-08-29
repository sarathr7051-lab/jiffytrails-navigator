/*
  view_assembled.scad - NOT A PRINTABLE PART.

  Stacks the case parts in their fitted positions so the thing can be looked at
  from any angle. Every part comes from case.scad via `use`, so this file
  cannot drift from the real geometry - it can only place it.

  Render:
    openscad -o v.png --imgsize=1400,1100 --projection=p --camera=... view_assembled.scad
    -D 'show_hood=false'   drop the hood to see the body
    -D 'cut=true'          section it in half down the long axis
*/

use <case.scad>

// Derived values from case.scad, restated here because `use` imports modules
// but not variables. If case.scad's dimensions change, echo them and update
// these four - they are for VIEWING ONLY and nothing is printed from them.
body_w   = 64.4;
body_l   = 96.4;
body_h   = 29.8;    // front face to sealing face
lid_t    = 5.0;
case_h   = body_h + lid_t;
front_t  = 3.0;
bezel_t  = 1.5;

show_hood  = true;
show_lid   = true;
show_bezel = true;
cut        = false;

module assembly() {
    color("#9AA6AB") body();

    // Lid: modelled outer-face-at-zero with its rim pointing +z, so it flips
    // over and drops its rim into the cavity mouth.
    if (show_lid)
        color("#B9C2C0") translate([0, 0, case_h]) rotate([180, 0, 0]) lid();

    // Bezel sits just behind the closed front, inside the cavity.
    if (show_bezel)
        color("#23282B") translate([0, 0, front_t]) bezel();

    // Hood: skirt clamps over the front of the body, tube points forward.
    if (show_hood)
        color("#2A2F32") translate([0, 0, 14]) rotate([180, 0, 0]) hood();
}

if (cut) {
    difference() {
        assembly();
        // Remove the half NEAREST the default camera, so the cut face is what
        // you see rather than the outside of the surviving half.
        translate([-200, -400, -100]) cube([400, 400, 400]);
    }
} else {
    assembly();
}
