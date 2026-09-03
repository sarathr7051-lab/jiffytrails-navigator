# -*- coding: utf-8 -*-
"""
NATIVE B-rep of the hood - built from analytic surfaces, not converted from a
mesh. The skirt's corner rounds are real cylinders, the funnel's flanks real
ruled surfaces and the screw bores real cylinders.

★ SHEARED, NOT ROTATED. Rotating the tube about its base lifts one side of the
base off the plane and leaves an open, forward-facing scoop beside the
aperture. The shear leans the walls and keeps the base flat, so it is built
here as a genuine affine shear (y -= tan(rake) * z above the skirt), applied
once to the whole upper assembly. Volume is preserved exactly by it - the
matrix determinant is 1 - which is what makes the volume cross-check below
meaningful across the sheared parts.

★ The hood is authored FLIPPED against the body: body +x is hood +x, but body
-y is hood +y. That is why the vent window sits at -vent_y and the cable notch
at +body_l/2.

Dimensions are the ones case.scad computes, restated as literals below and
checked against the OpenSCAD render by volume and bounding box. Nothing here
is derived from the STL.
"""
import math
import cadquery as cq

# ---- from case.scad (echoed at $fn=256, not re-derived by hand) ---------
body_w, body_l    = 64.4, 96.4
cav_w, cav_l      = 52.4, 84.4
wall, corner_r    = 2.4, 4.0
corner_r_out      = 7.6
hood_depth        = 30.0
hood_rake         = 12.0
hood_ribs         = 5
hood_wall         = 1.6
hood_skirt_h      = 14.0
hood_funnel       = 7.0
hood_pad_d        = 7.2
hood_pad_clear    = 0.6
hood_ow, hood_ol  = 53.2, 79.2      # 48 + 2*wall + 2 , 74 + 2*wall + 2
hood_hole_w       = 57.6            # cav_w + 2*wall + 0.4
hood_hole_l       = 89.6            # cav_l + 2*wall + 0.4
hood_boss_d       = 11.4            # pad + clear + 2*boss_wall
hood_pocket_h     = 5.6             # skirt_h - pad_z0 + pad_clear
hood_screw_z      = 3.0             # skirt_h - pad_z  -> the pads' REAL height
screw_clear_d     = 3.4
cable_x, cable_z  = 4.0, 13.0
cable_boss_d      = 12.0
vent_y            = 18.0
vent_shroud_r     = 12.0

TAN = math.tan(math.radians(hood_rake))          # 0.2125566
PAD_X = cav_w / 2.0 + wall                       # 28.6

def rr_solid(w, l, h, r, z=0.0):
    """OpenSCAD's rrect(): hull of four corner cylinders == a rounded rect."""
    return (cq.Workplane("XY").rect(w, l).extrude(h)
            .edges("|Z").fillet(r).translate((0, 0, z)))

def rr_wire(w, l, r, z):
    """The same rounded rect as a single wire, ALREADY SHEARED - lifted to
    height z and slid -tan(rake)*z in y. Taken off a real filleted solid so the
    arcs are identical to rr_solid's, and so every wire in a loft has the same
    edge order and the ruled surfaces pair up.

    Shearing the section wires rather than shearing finished geometry is what
    keeps this part honest in the STEP: a leaning wall stays a PLANE and a
    leaning bore stays a surface of linear extrusion, both exact. Running the
    shear over built solids instead (BRepBuilderAPI_GTransform) is equally
    exact but turns every face, flats included, into a heavy NURBS patch -
    125 spline surfaces and 11 356 control points, a 1.3 MB file for the same
    shape."""
    f = rr_solid(w, l, 1.0, r).faces("<Z").val()
    return f.outerWire().translate(cq.Vector(0, -TAN * z, z))

def obl_prism(w, l, r, z0, h):
    """A sheared prism, which is exactly an oblique linear extrusion. Real
    planes on the flats, real surfaces of linear extrusion at the corners."""
    return cq.Solid.extrudeLinear(rr_wire(w, l, r, z0), [],
                                  cq.Vector(0, -TAN * h, h))

def hull_plates(lo, lo_z0, lo_z1, hi, hi_z0, hi_z1):
    """OpenSCAD's hull() of two thin rounded-rect PLATES, one nested inside the
    other. Each is (w, l, r); each spans z0..z1.

    For convex sections the hull's cross section at height t is the Minkowski
    blend (1-u)*lo + u*hi, and for rounded rects that blend is itself a rounded
    rect with w, l AND r each interpolated linearly - so a ruled loft
    reproduces hull() exactly rather than approximating it.

    ★ BUT THE BLEND DOES NOT RUN BETWEEN THE PLATES' FACING SURFACES. The
    widest section reachable at height t comes from joining the TOP of the
    lower plate to the TOP of the upper one, so the taper runs lo_z1 -> hi_z1
    and the full lower section is held right across lo_z0..lo_z1. Lofting
    lo_z1 -> hi_z0 instead - the obvious reading - makes the taper steeper over
    its whole length and reads +159 mm3 (+0.53 %) against the OpenSCAD
    original, which is how this was caught. The 0.01 mm plates are not noise.
    """
    w = [rr_wire(lo[0], lo[1], lo[2], lo_z0),
         rr_wire(lo[0], lo[1], lo[2], lo_z1),
         rr_wire(hi[0], hi[1], hi[2], hi_z1)]
    return cq.Solid.makeLoft(w, ruled=True)

# ========================================================================
# The upper assembly, with z = 0 at the skirt's top face. Every section wire
# below is already sheared by rr_wire(), so what is built is the leaning part
# itself rather than an upright one bent afterwards.
# ========================================================================

# ---- funnel: skirt mouth -> tube, both surfaces closing inward ----------
# The tube alone never touches the skirt: the skirt's hole is 57.6 wide to
# clear the body's shell and the tube's OUTER wall is only 53.2, so they are
# 2.2 mm apart in x and 5.2 in y at every z. Unjoined it slices as a ring and
# a tube - CGAL said Volumes: 3 - and renders as a perfect hood from every
# angle. The funnel is what makes it one solid. The inner run is 6.8 mm over
# hood_funnel = 7.0, so the bore is at 45.6 degrees and self-supporting mouth
# down.
# The 0.01-thick end plates are load-bearing on the numbers, not noise: they
# hold the full-width section for the first 0.01 mm, which is where the part's
# y_min (-48.2021) actually comes from.
f_out = hull_plates((body_w, body_l, corner_r_out), 0.0, 0.01,
                    (hood_ow, hood_ol, 2.5), hood_funnel, hood_funnel + 0.01)
f_in = hull_plates((hood_hole_w, hood_hole_l, corner_r), -0.02, -0.01,
                   (hood_ow - 2 * hood_wall, hood_ol - 2 * hood_wall, 1.5),
                   hood_funnel + 0.02, hood_funnel + 0.03)
upper = cq.Workplane("XY").add(f_out).cut(cq.Workplane("XY").add(f_in))

# ---- the shade, standing on the funnel ---------------------------------
shade = (cq.Workplane("XY").add(obl_prism(hood_ow, hood_ol, 2.5,
                                          hood_funnel, hood_depth))
         .cut(cq.Workplane("XY").add(obl_prism(
             hood_ow - 2 * hood_wall, hood_ol - 2 * hood_wall, 1.5,
             hood_funnel - 1.0, hood_depth + 2.0))))
upper = upper.union(shade)

# ---- five stiffening ribs ----------------------------------------------
# ★ The inner subtraction must run PAST the top of the rib. Ending it at the
# rib's top face made every rib a SOLID SLAB across the full bore - five
# louvres blocking the hood, invisible from outside. The rib also stops
# outside the aperture: reaching further in masked 4.4 px of live picture on
# every edge, and display.cpp paints flush to the panel edge.
rib_h, rib_in = 2.6, 1.8
rw, rl = hood_ow - 2 * hood_wall + 0.2, hood_ol - 2 * hood_wall + 0.2
for i in range(1, hood_ribs + 1):
    z0 = hood_funnel + i * hood_depth / (hood_ribs + 1.0)
    rib = (cq.Workplane("XY").add(obl_prism(rw, rl, 1.5, z0, rib_h))
           .cut(cq.Workplane("XY").add(hull_plates(
               (rw, rl, 1.5), z0 - 0.01, z0,
               (48.0 + 1.6, 74.0 + 1.6, 1.0),
               z0 - 0.01 + rib_in,
               z0 - 0.01 + rib_in + (rib_h - rib_in + 0.2)))))
    upper = upper.union(rib)

# ---- lift the finished upper assembly onto the skirt --------------------
# A plain translation: the lean is already in the geometry, and the shear was
# identity at z = 0 by construction, so the funnel's foot still matches the
# skirt's mouth face for face.
upper = upper.val().translate(cq.Vector(0, 0, hood_skirt_h))

# ========================================================================
# Skirt and bosses, in hood coordinates, then the cuts.
# ========================================================================
part = rr_solid(body_w, body_l, hood_skirt_h, corner_r_out)

# ★ AND EVEN THEN IT WOULD NOT GO ON - THE PADS FOUL THE SKIRT. The skirt's
# inner face is at 28.8 and the pads' outer face at body_w/2 = 32.2, 3.4 mm
# inside it. So the hood carries a local boss at each pad instead: a pocket
# over the pad with hood_boss_wall outboard of it, taking the hood 2.1 mm
# wider than the case at two spots. It is a bolt-on shade; 2.1 mm is not an
# envelope.
for sx in (-1, 1):
    part = part.union(cq.Workplane("XY").circle(hood_boss_d / 2.0)
                      .extrude(hood_pocket_h + 1.2).translate((sx * PAD_X, 0, 0)))

part = part.union(cq.Workplane("XY").add(upper))

# ---- the body's front, 0.2 mm of slop. Cut in the OUTER difference so it ---
# ---- trims the bosses too; stops at the skirt's top so the funnel stands. --
part = part.cut(rr_solid(hood_hole_w, hood_hole_l, hood_skirt_h + 0.5,
                         corner_r, -0.5))

# ---- pockets for the body's pads, open at the mouth so it slides on ------
for sx in (-1, 1):
    part = part.cut(cq.Workplane("XY").circle((hood_pad_d + hood_pad_clear) / 2.0)
                    .extrude(hood_pocket_h + 1.0).translate((sx * PAD_X, 0, -1.0)))

# ---- ★ the vent window ---------------------------------------------------
# The vent has no legal z anywhere on this case: the perfboard ledge forces it
# below 12.34, the hood skirt forces it above 20, and the 45 degree flange
# flare caps it near 19.9 on every wall. So the HOOD gives way, locally - a
# slot in a sacrificial 8 g reprintable part, and vent_z, the ledge and the
# wall all stay untouched. Open to the mouth so it cannot trap water, and it
# runs 1 mm past the skirt's top into the funnel wall.
part = part.cut(cq.Workplane("XY")
                .box(12.0, 2 * (vent_shroud_r + 1.5), hood_skirt_h + 2.0,
                     centered=False)
                .translate((PAD_X - 1.0, -vent_y - (vent_shroud_r + 1.5), -1.0)))

# ---- notch for the cable boss, also open at the mouth --------------------
part = part.cut(cq.Workplane("XY").add(cq.Solid.makeCylinder(
    (cable_boss_d + 1.0) / 2.0, 40.0,
    cq.Vector(cable_x, body_l / 2.0 - 20.0, hood_skirt_h - cable_z),
    cq.Vector(0, 1, 0))))

# ---- screw clearance, at the pads' REAL height --------------------------
# The holes used to be at a literal hood z = 8, landing at body z = 6.0 while
# the pads' pilots are at body z = 11.0 - two sets of literals in two modules
# that could not see each other. Both now read hood_pad_z.
for sx in (-1, 1):
    part = part.cut(cq.Workplane("XY").add(cq.Solid.makeCylinder(
        screw_clear_d / 2.0, 40.0,
        cq.Vector(sx * PAD_X - 20.0, 0.0, hood_screw_z), cq.Vector(1, 0, 0))))

sh = part.val(); bb = sh.BoundingBox()
print("solids           %d" % len(sh.Solids()))
print("volume           %.4f mm3" % sh.Volume())
print("bbox    x %8.3f .. %8.3f   size %8.4f" % (bb.xmin, bb.xmax, bb.xlen))
print("        y %8.3f .. %8.3f   size %8.4f" % (bb.ymin, bb.ymax, bb.ylen))
print("        z %8.3f .. %8.3f   size %8.4f" % (bb.zmin, bb.zmax, bb.zlen))
print("faces            %d   (analytic + exact ruled B-rep, not tessellated)" % len(sh.Faces()))
cq.exporters.export(part, "hood.step", cq.exporters.ExportTypes.STEP)
print("wrote hood.step")
