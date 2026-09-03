# -*- coding: utf-8 -*-
"""
NATIVE B-rep of the body - built from analytic surfaces, not converted from a
mesh. Every bore is a real cylinder, the 45 degree flange flare a real cone at
the corners and a real plane on the flats, and every corner round a real
cylindrical face. The mesh route was never an option here: at the tolerance
this part needs, the STL is a quarter of a gigabyte.

The sealed shell. Front face at z = 0, sealing rim at z = body_h, cavity
opening toward +z (the rider's side is -z).

Built in case.scad's own order - union everything, then cut, then union the
ribs, ledges and lip AFTERWARDS. That order is not cosmetic: the ribs and the
ledges must land after the difference because the cavity is the one
subtraction that covers every millimetre they occupy and would eat them, while
the vent shroud must land INSIDE the union because it sits on top of two cuts
it has to receive.

Dimensions are the ones case.scad computes, restated as literals below and
checked against the OpenSCAD render by volume and bounding box. Nothing here
is derived from the STL.
"""
import math
import cadquery as cq

# ---- from case.scad (echoed at $fn=256, not re-derived by hand) ---------
disp_pcb_l        = 82.0
disp_widest       = 50.7           # PCB 50.0 + 2 x 0.35 of proud panel frame
cav_w, cav_l      = 52.4, 84.4
cav_d             = 31.34
body_w, body_l    = 64.4, 96.4
body_h            = 34.34
wall, front_t     = 2.4, 3.0
corner_r          = 4.0
corner_r_out      = 7.6
inner_clear       = 1.2
bezel_t, disp_t   = 1.5, 5.0
z_land            = 34.34
screw_pilot_d     = 2.5
screw_depth       = 9.0
hood_pad_d        = 7.2
hood_pad_z0       = 9.0
hood_pad_h        = 14.0
hood_pilot_len    = 4.0
cable_x, cable_z  = 4.0, 13.0
cable_bore_d      = 4.5
cable_boss_d      = 12.0
cable_in, cable_out, cable_chamber_d = 6.0, 4.0, 8.0
vent_y, vent_z    = 18.0, 12.0
vent_d            = 6.0
vent_seat_d       = 12.0
vent_seat_t       = 0.6
vent_shroud_r     = 12.0
vent_shroud_t     = 2.4
vent_shroud_p     = 3.0
ledge_z           = 20.54
ledge_in_x        = 24.0
ledge_lip_x       = 25.3
ledge_lip_h       = 2.0
ledge_cham        = 2.2
ledge_bury        = 1.0
ledge_y0, ledge_y1     = -38.0, 26.0
ledge_stop_y, ledge_stop_l = 28.5, 3.0
disp_lip_t        = 2.1
disp_lip_z0, disp_lip_z1 = 9.75, 11.25
disp_lip_w        = 26.0
rib_w, rib_l      = 2.0, 8.0
RIB_SIDE_Y = [-30.0, 0.0, 30.0]
RIB_END_X  = [-14.0, 14.0]
SCREW_PTS = [(29.0, 42.5), (-29.0, 42.5), (29.0, -42.5), (-29.0, -42.5),
             (29.0, 0.0), (-29.0, 0.0), (0.0, 45.0), (0.0, -45.0)]

# ------------------------------------------------------------------ helpers

def rr_solid(w, l, h, r, z=0.0):
    """OpenSCAD's rrect(): hull of four corner cylinders == a rounded rect."""
    return (cq.Workplane("XY").rect(w, l).extrude(h)
            .edges("|Z").fillet(r).translate((0, 0, z)))

def rr_wire(w, l, r, z):
    """The same rounded rect as one wire, for lofting - taken off a real
    filleted solid so every wire in a loft has identical edge order."""
    return rr_solid(w, l, 1.0, r).faces("<Z").val().outerWire().translate(
        cq.Vector(0, 0, z))

def rr_hull(a, az0, az1, b, bz0, bz1):
    """OpenSCAD's hull() of two thin rounded-rect PLATES, one nested inside the
    other. a is the lower plate (w, l, r) spanning az0..az1, b the upper.

    ★ THE TAPER DOES NOT RUN BETWEEN THE PLATES' FACING SURFACES. The widest
    section reachable at any height comes from joining the SMALL plate's far
    face to the BIG plate's near face, so the big plate's own thickness sits
    outside the taper entirely. Reading it the obvious way - facing surface to
    facing surface - makes the taper steeper over its whole length; on the hood
    that error read +0.53 %. The 0.01 mm plates are load-bearing, not noise.

    For convex sections the hull's cross section is the Minkowski blend of the
    two, and for rounded rects that blend is another rounded rect with w, l AND
    r each interpolated linearly - so a ruled loft is hull(), exactly."""
    if a[0] >= b[0]:                       # lower plate is the bigger one
        loft = cq.Solid.makeLoft([rr_wire(*a, z=az1), rr_wire(*b, z=bz1)], True)
        prism = rr_solid(a[0], a[1], az1 - az0, a[2], az0)
    else:                                  # upper plate is the bigger one
        loft = cq.Solid.makeLoft([rr_wire(*a, z=az0), rr_wire(*b, z=bz0)], True)
        prism = rr_solid(b[0], b[1], bz1 - bz0, b[2], bz0)
    return cq.Workplane("XY").add(loft).union(cq.Workplane("XY").add(prism))

def hull2d(pts):
    """Monotone-chain convex hull. Used for the hull()s whose members all share
    one extent - rib() and disp_lip() - which makes them prisms of a 2D hull
    and lets them be built exactly rather than lofted."""
    pts = sorted(set((round(x, 9), round(y, 9)) for x, y in pts))
    def half(ps):
        out = []
        for p in ps:
            while len(out) > 1 and ((out[-1][0] - out[-2][0]) * (p[1] - out[-2][1])
                                    - (out[-1][1] - out[-2][1]) * (p[0] - out[-2][0])) <= 0:
                out.pop()
            out.append(p)
        return out
    return half(pts)[:-1] + half(pts[::-1])[:-1]

def prism_xz(pts2d, y0, y1):
    """A closed x-z profile swept along y, which is how case.scad lays down
    every extruded profile: linear_extrude runs in +z and rotate([90,0,0])
    puts it on its side."""
    return (cq.Workplane("XZ").polyline(pts2d).close()
            .extrude(y1 - y0).translate((0, y1, 0)))

# ================================================================== UNION

# ---- main shell ---------------------------------------------------------
part = rr_solid(cav_w + 2 * wall, cav_l + 2 * wall, body_h, corner_r)

# ---- flange block carrying the seal and the screws ----------------------
# Flared in at 45 degrees from below so it prints without support: the cores
# of the two sections are identical (49.2 x 81.2), so the whole flare is the
# corner radius growing 4.0 -> 7.6 over 3.6 mm of rise. That makes its flats
# real planes and its corners real cones.
part = part.union(rr_hull((cav_w + 2 * wall, cav_l + 2 * wall, corner_r),
                          body_h - 11.2, body_h - 11.19,
                          (body_w, body_l, corner_r_out),
                          body_h - 7.6, body_h - 7.59))
part = part.union(rr_solid(body_w, body_l, 7.6, corner_r_out, body_h - 7.6))

# ---- hood mounting pads, y = 0 each side --------------------------------
# They bring the mid-body to exactly body_w, so they cost no envelope at all -
# which is also why the HOOD has to bulge over them.
for sx in (-1, 1):
    part = part.union(cq.Workplane("XY").circle(hood_pad_d / 2.0)
                      .extrude(hood_pad_h)
                      .translate((sx * (cav_w / 2 + wall), 0, hood_pad_z0)))

# ---- cable entry boss ---------------------------------------------------
part = part.union(cq.Workplane("XY").add(cq.Solid.makeCylinder(
    cable_boss_d / 2.0, cable_out * 2,
    cq.Vector(cable_x, -body_l / 2.0 - cable_out, cable_z), cq.Vector(0, 1, 0))))

# ---- ★★ the vent shroud, INSIDE the union and not after the difference --
# Added after it, the shroud was immune to the two cuts it sits on top of and
# re-filled both: 49.4 mm3 of solid inside the O6 vent bore and 28.2 mm3 - 42 %
# - of the O12 membrane land. Material unioned after a difference cannot be cut
# by anything in this file.
# The form is a C-shaped collar: a 45 degree gusset reaching 0.5 INTO the wall
# (built flush it merely touched, and CGAL called the body two solids), a rim
# standing vent_shroud_p proud, the bottom half open so nothing pools against
# the patch, and the middle bored right through - hull() does not build a roof
# on a gusset, it fills the standoff solid, and 119.98 mm3 of ASA over the
# bonding land left a 0.7 mm gap nobody can lay a 12 mm patch into.
shroud = (cq.Workplane("XY").add(cq.Solid.makeCone(
              vent_shroud_r - vent_shroud_p, vent_shroud_r,
              vent_shroud_p - vent_shroud_t + 0.5,
              cq.Vector(0, 0, -0.5), cq.Vector(0, 0, 1)))
          .union(cq.Workplane("XY").circle(vent_shroud_r)
                 .extrude(vent_shroud_t)
                 .translate((0, 0, vent_shroud_p - vent_shroud_t)))
          .cut(cq.Workplane("XY").box(2 * vent_shroud_r + 2, vent_shroud_r + 1,
                                      vent_shroud_p + 2, centered=False)
               .translate((-vent_shroud_r - 1, -vent_shroud_r - 1, -1)))
          .cut(cq.Workplane("XY").circle((vent_seat_d + 1.0) / 2.0)
               .extrude(vent_shroud_p + 2).translate((0, 0, -1))))
part = part.union(shroud.rotate((0, 0, 0), (0, 1, 0), 90)
                  .translate((cav_w / 2 + wall, vent_y, vent_z)))

# =============================================================== DIFFERENCE

# ---- cavity, opening at the back ---------------------------------------
part = part.cut(rr_solid(cav_w, cav_l, cav_d + 1, corner_r - wall, front_t))

# ---- window opening -----------------------------------------------------
# Sized from the PCB OUTLINE, not from the active area: 48 x 74 leaves 1.0 mm
# of overlap on the 50 mm glass width, which is all there is, and the bezel
# behind it does the precise work.
part = part.cut(rr_solid(48.0, 74.0, front_t + 2, 2.0, -1.0))
# outer relief so rain sheds off the aperture rather than pooling in it
part = part.cut(rr_hull((51.0, 77.0, 2.5), -0.01, 0.0,
                        (48.0, 74.0, 2.0), 1.49, 1.50))

# ---- blind screw holes, from the sealing face down ----------------------
for x, y in SCREW_PTS:
    part = part.cut(cq.Workplane("XY").circle(screw_pilot_d / 2.0)
                    .extrude(screw_depth + 0.1)
                    .translate((x, y, z_land - screw_depth)))

# ---- *** the hood pilots, which went straight through into the box *** --
# A centred cylinder(h = 12) at x = 28.6 spanned x 22.60 to 34.60: it left the
# pad correctly at 32.20 and kept going, out through the cavity face at 26.20
# and 3.6 mm into the electronics. Two O2.5 holes from open air into a case
# whose entire design argument is that it is sealed, hidden under the hood's
# skirt outside and behind the display inside.
# A pilot only needs to be a pilot: hood_pilot_len inward from the pad face,
# written centred on its own midpoint so the two sides cannot drift apart, and
# 0.1 proud of that face so the mouth is a clean opening.
for sx in (-1, 1):
    xm = sx * (body_w / 2.0 - hood_pilot_len / 2.0 + 0.05)
    part = part.cut(cq.Workplane("XY").add(cq.Solid.makeCylinder(
        screw_pilot_d / 2.0, hood_pilot_len + 0.1,
        cq.Vector(xm - (hood_pilot_len + 0.1) / 2.0, 0, front_t + 8),
        cq.Vector(1, 0, 0))))

# ---- cable bore, a TEARDROP -----------------------------------------
# ★ Every horizontal hole is a teardrop. A round hole printed axis-horizontal
# bridges its own diameter at the crown and sags 0.2-0.4 mm, out of round, on
# the exact face a seal touches - and the usual repair is drilling a finished,
# sealed part with swarf falling inside it.
r = cable_bore_d / 2.0
tri = [(cable_x - r * math.cos(math.radians(45)), cable_z + r * math.sin(math.radians(45))),
       (cable_x + r * math.cos(math.radians(45)), cable_z + r * math.sin(math.radians(45))),
       (cable_x, cable_z + r * math.sqrt(2))]
part = part.cut(cq.Workplane("XY").add(cq.Solid.makeCylinder(
    r, 40.0, cq.Vector(cable_x, -body_l / 2.0 - 20.0, cable_z), cq.Vector(0, 1, 0))))
part = part.cut(prism_xz(tri, -body_l / 2.0 - 20.0, -body_l / 2.0 + 20.0))

# ---- ★ the chamber runs OUTBOARD, into the boss -------------------------
# It used to run inboard from the cavity face - 5.9 of its 6.0 mm in open
# cavity air, removing nothing. A cable tie clamped inside this chamber cannot
# pass back out through the O4.5 mouth, so the pull goes into ASA instead of
# into the silicone's adhesion.
part = part.cut(cq.Workplane("XY").add(cq.Solid.makeCylinder(
    cable_chamber_d / 2.0, cable_in + 0.1,
    cq.Vector(cable_x, -(cav_l / 2.0) - cable_in, cable_z), cq.Vector(0, 1, 0))))

# ---- vent, on the same downward face as the cable ----------------------
# *** teardrop_x centres its extrusion, so a length of 200 ran x -100 to +100
# and pierced the -x wall as well: a bare 6 mm hole straight into the
# electronics, no membrane seat on that side and no way to see it from
# outside. 45.2 +/- 20 spans x 25.2 to 65.2 - one millimetre of bite into the
# cavity, out through the +x wall, and nowhere near the other.
rv = vent_d / 2.0
vx = cav_w / 2.0 + 19.0
part = part.cut(cq.Workplane("XY").add(cq.Solid.makeCylinder(
    rv, 40.0, cq.Vector(vx - 20.0, vent_y, vent_z), cq.Vector(1, 0, 0))))
vtri = [(vent_y - rv * math.cos(math.radians(45)), vent_z + rv * math.sin(math.radians(45))),
        (vent_y + rv * math.cos(math.radians(45)), vent_z + rv * math.sin(math.radians(45))),
        (vent_y, vent_z + rv * math.sqrt(2))]
part = part.cut(cq.Workplane("YZ").polyline(vtri).close()
                .extrude(40.0).translate((vx - 20.0, 0, 0)))

# ---- ★★ the membrane land, on the OUTSIDE face -------------------------
# Recessed into the cavity side it was backwards for every load it sees: rain
# at 300-460 Pa, a jet wash and the 13.3 kPa thermal vacuum the vent exists for
# ALL push inward, so all three were trying to PEEL the patch off its land.
# Outside, every one of them presses it on.
part = part.cut(cq.Workplane("XY").add(cq.Solid.makeCylinder(
    vent_seat_d / 2.0, vent_seat_t + 0.1,
    cq.Vector(cav_w / 2.0 + wall - vent_seat_t, vent_y, vent_z), cq.Vector(1, 0, 0))))

# ============================== AFTER THE DIFFERENCE, AND DELIBERATELY SO

# ---- display locating ribs ---------------------------------------------
# ★ They bear on the PCB OUTLINE (50.0 x 82.0, verified) rather than on the
# four mounting holes, whose insets came from the wrong board and were measured
# wrong even there. A rib cannot miss an edge; a post can miss a hole by 2 mm
# and scrap the print. The pocket is sized on the WIDEST part - the proud panel
# frame, not the PCB. The 45 degree lead-in on the back edge lets the module
# drop in rather than be threaded past a square shoulder.
rz, rh = front_t + bezel_t, disp_t + 2.0
px = disp_widest / 2.0 + 0.3
py = disp_pcb_l / 2.0 + 0.3
rib_pts = hull2d([(sx * rib_w / 2.0, z) for sx in (-1, 1) for z in (-0.005, 0.005)] +
                 [(sx * rib_w / 2.0, z) for sx in (-1, 1) for z in (rh - 1.5 - 0.005, rh - 1.5 + 0.005)] +
                 [(sx * rib_w * 0.2 / 2.0, z) for sx in (-1, 1) for z in (rh - 0.005, rh + 0.005)])
rib = prism_xz(rib_pts, -rib_l / 2.0, rib_l / 2.0)
for s in (-1, 1):
    for y in RIB_SIDE_Y:
        part = part.union(rib.translate((s * (px + 1.0), y, rz)))
    for x in RIB_END_X:
        part = part.union(rib.rotate((0, 0, 0), (0, 0, 1), 90)
                          .translate((x, s * (py + 1.0), rz)))

# ---- perfboard retention ledges ----------------------------------------
# ONE closed cross-section in x-z swept along y: from the chamfer's toe at the
# cavity wall, in over the 45 degree ramp to the shelf's inner edge, out along
# the bearing face to the lip, up the lip and back into the wall. A shelf whose
# underside is the ramp cannot be built from a shelf plus a chamfer without
# their meeting plane showing as a seam in the render and a shear line in the
# print. lip_x == ledge_in_x collapses the bearing face to zero length, which
# turns the same profile into a stop tab.
x_out = cav_w / 2.0 + ledge_bury
def ledge_profile(lip_x):
    p = [(cav_w / 2.0, ledge_z - ledge_cham), (ledge_in_x, ledge_z)]
    if lip_x > ledge_in_x:
        p.append((lip_x, ledge_z))
    return p + [(lip_x, ledge_z + ledge_lip_h), (x_out, ledge_z + ledge_lip_h),
                (x_out, ledge_z - ledge_cham)]
for mirror in (1, -1):
    for lip_x, y0, y1 in ((ledge_lip_x, ledge_y0, ledge_y1),
                          (ledge_in_x, ledge_stop_y, ledge_stop_y + ledge_stop_l)):
        pr = [(mirror * x, z) for x, z in ledge_profile(lip_x)]
        part = part.union(prism_xz(pr, y0, y1))

# ---- ★ the far-end lip, and it IS called -------------------------------
# disp_lip() was defined once and never called: the file rendered clean, every
# assert passed, and the part simply did not have the feature. An uncalled
# module is invisible to every check there is except looking for the call.
# It form-closes the end nothing else holds - hdr_gap less the ribbon and the
# solder leaves 5.54 mm of clear air for the far end to lift into and slam back
# at 60-120 Hz, and chatter is what kills the panel. It stands off the panel by
# disp_lip_gap rather than resting on it, and its 45 degree gusset keeps it
# self-supporting printing front face down. +y end only: the header and its
# socket are at -y.
ly = disp_pcb_l / 2.0 + inner_clear - disp_lip_t / 2.0
lip_pts = hull2d(
    [(ly + sy * disp_lip_t / 2.0, z) for sy in (-1, 1)
     for z in (disp_lip_z0 - 0.005, disp_lip_z0 + 0.005,
               disp_lip_z1 - 0.005, disp_lip_z1 + 0.005)] +
    [(ly + disp_lip_t / 2.0 + sy * 0.005, z) for sy in (-1, 1)
     for z in (disp_lip_z1 + disp_lip_t - 0.005, disp_lip_z1 + disp_lip_t + 0.005)])
part = part.union(cq.Workplane("YZ").polyline(lip_pts).close()
                  .extrude(disp_lip_w).translate((-disp_lip_w / 2.0, 0, 0)))

sh = part.val(); bb = sh.BoundingBox()
print("solids           %d" % len(sh.Solids()))
print("volume           %.4f mm3" % sh.Volume())
print("bbox    x %8.3f .. %8.3f   size %8.4f" % (bb.xmin, bb.xmax, bb.xlen))
print("        y %8.3f .. %8.3f   size %8.4f" % (bb.ymin, bb.ymax, bb.ylen))
print("        z %8.3f .. %8.3f   size %8.4f" % (bb.zmin, bb.zmax, bb.zlen))
print("faces            %d   (planar+analytic B-rep, not tessellated)" % len(sh.Faces()))
cq.exporters.export(part, "body.step", cq.exporters.ExportTypes.STEP)
print("wrote body.step")
