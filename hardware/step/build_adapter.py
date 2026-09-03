# -*- coding: utf-8 -*-
"""
NATIVE B-rep of the mount adapter - built from analytic surfaces, not converted
from a mesh. Every cylinder here is a real cylindrical face and every rounded
corner a real fillet, so the STEP a CAD package opens is exact rather than a
64-sided approximation of a circle.

Dimensions are the ones mount_v4.scad computes; they are restated as literals
below and checked against the OpenSCAD render by volume and bounding box.
Nothing here is derived from the STL.
"""
import math
import cadquery as cq

# ---- the stack, from mount_v4.scad -------------------------------------
plate_r, floor_t          = 20.0, 4.2
cav_flats, cav_r, cav_dep = 14.5, 2.42, 2.2
floor_under               = 2.0
z_floor                   = 4.2
z_lug_t, z_lip_b, z_collar = 7.35, 7.65, 10.25
collar_h, collar_ir, collar_or = 6.05, 15.3, 18.5
qt_lip_r                  = 11.5
qt_twist                  = 55.0
lip_t                     = 2.6
ins_bore, ins_wall, ins_len = 4.0, 1.9, 5.7
scr_clear_d               = 3.4
pawl_r, pawl_l, pawl_t, pawl_b = 23.2, 18.0, 1.6, 8.0
pawl_tooth, pawl_tooth_w, pawl_tab = 2.1, 5.0, 3.0
pawl_root_x, pawl_lobe_r  = 16.0, 4.5
pawl_root_y, pawl_relief_x = 16.0, 12.0       # the spring's real length
tooth_grow                = 2.3
lead_reach, lead_h        = 2.1, 1.2          # 30 deg lead-in
pawl_ramp                 = 1.03923           # 60 deg release flanks
r_face                    = pawl_r - pawl_tooth   # 21.10
cap_skirt_or              = 22.9
LUG_AT   = [0.0, 120.0, 240.0]
LUG_W    = [48.0, 34.0, 34.0]                 # key lug 48, not 44
SLOT_W   = [54.0, 44.0, 44.0]

def sector(r_in, r_out, z0, z1, a_mid, a_w):
    """A true annular sector: two cylindrical faces, two planar ones."""
    a0, a1 = a_mid - a_w / 2.0, a_mid + a_w / 2.0
    R = 3.0 * r_out
    pts = [(0.0, 0.0)]
    n = max(2, int(a_w // 30) + 2)
    for i in range(n + 1):
        a = math.radians(a0 + (a1 - a0) * i / n)
        pts.append((R * math.cos(a), R * math.sin(a)))
    wedge = cq.Workplane("XY").polyline(pts).close().extrude(z1 - z0).translate((0, 0, z0))
    ring = (cq.Workplane("XY").circle(r_out).circle(r_in)
              .extrude(z1 - z0).translate((0, 0, z0)))
    return ring.intersect(wedge)

# ---- the plate: convex hull of the O40 disc and the pawl lobe -----------
cx, cy, r2 = pawl_root_x, pawl_r + pawl_t / 2.0, pawl_lobe_r
d = math.hypot(cx, cy)
alpha, beta = math.atan2(cy, cx), math.acos((plate_r - r2) / d)
quad = []
for s in (+1, -1):
    a = alpha + s * beta
    quad.append((plate_r * math.cos(a), plate_r * math.sin(a)))
    quad.append((cx + r2 * math.cos(a), cy + r2 * math.sin(a)))
quad = [quad[0], quad[1], quad[3], quad[2]]
plate = (cq.Workplane("XY").circle(plate_r).extrude(floor_t)
         .union(cq.Workplane("XY").moveTo(cx, cy).circle(r2).extrude(floor_t))
         .union(cq.Workplane("XY").polyline(quad).close().extrude(floor_t)))
# The relief that makes the blade a spring. Without it the hull fuses to the
# blade from x = -1 outward and the flexing span is 5.5 mm, not 18.5 - root
# strain 14.3 % against ASA's ~2 % yield. Cut from the plate ALONE, before the
# blade is unioned in, or it would saw the blade's own lower 4.2 mm off.
plate = plate.cut(cq.Workplane("XY")
                  .box(plate_r + 2 + pawl_relief_x, 12.0, floor_t + 0.2,
                       centered=False)
                  .translate((-plate_r - 2, pawl_r - 1.5, -0.1)))

# ---- collar wall, sunk 0.6 into the plate so it is one solid ------------
collar = (cq.Workplane("XY").circle(collar_or).extrude(collar_h + 0.6)
          .translate((0, 0, z_floor - 0.6))
          .cut(cq.Workplane("XY").circle(collar_ir).extrude(collar_h + 0.2)
               .translate((0, 0, z_floor - 0.1))))

# ---- the lip, a flat shoulder the lugs bear against ---------------------
lip = (cq.Workplane("XY").circle(collar_or).circle(qt_lip_r)
       .extrude(lip_t).translate((0, 0, z_lip_b)))

# The slots are cut from the collar and the lip TOGETHER. Cutting them from
# the lip alone leaves the wall standing in the outer 1.0 mm of every slot -
# the slot reaches collar_ir + 1.0, deliberately past the bore, so the lug has
# somewhere to sit. That mistake reads as +101.8 mm3 against the OpenSCAD
# original, which is how it was caught.
collar = collar.union(lip)
for at, sw in zip(LUG_AT, SLOT_W):
    collar = collar.cut(sector(qt_lip_r - 1.0, collar_ir + 1.0,
                               z_lip_b - 0.1, z_lip_b + lip_t + 0.1, at, sw))

# ---- hard stops: rotation cannot run on to the next slot ----------------
stops = None
for at, lw in zip(LUG_AT, LUG_W):
    s = sector(qt_lip_r + 0.3, collar_ir, z_floor, z_lug_t,
               at + qt_twist + lw / 2.0 + 3.0, 4.0)
    stops = s if stops is None else stops.union(s)

# ---- insert boss, also sunk 0.6 ----------------------------------------
boss = (cq.Workplane("XY").circle(ins_bore / 2.0 + ins_wall)
        .extrude(ins_len + 0.6).translate((0, 0, z_floor - 0.6)))

# ---- the pawl: blade, tooth, arc face, conical lead-in ------------------
blade = (cq.Workplane("XY")
         .box(pawl_t, pawl_root_y + pawl_l / 2.0, pawl_b, centered=False)
         .translate((pawl_r, -pawl_root_y, 0)))
tooth = (cq.Workplane("XY")
         .box(pawl_tooth + tooth_grow + pawl_t + pawl_tab, pawl_tooth_w, pawl_b,
              centered=False)
         .translate((pawl_r - pawl_tooth - tooth_grow, pawl_l / 2.0 - pawl_tooth_w, 0)))
# the arc face, concentric with the skirt it grips
tooth = tooth.cut(cq.Workplane("XY").circle(r_face).extrude(pawl_b + 0.2)
                  .translate((0, 0, -0.1)))
# the lead-in: reach and height are separate, giving a 30 deg ramp that clears
# cap_skirt_or instead of ending on a square ledge
r_top = r_face + lead_reach * (lead_h + 0.2) / lead_h
cone = (cq.Solid.makeCone(r_face, r_top, lead_h + 0.2)
        .locate(cq.Location(cq.Vector(0, 0, pawl_b - lead_h))))
tooth = tooth.cut(cq.Workplane("XY").add(cone))
# the two ramped flanks at 60 deg - how it comes off again, since the release
# tab sits under the cap where no finger can pull it outward
for sgn in (1.0, -1.0):
    y_at = pawl_l / 2.0 if sgn > 0 else pawl_l / 2.0 - pawl_tooth_w
    sl   = sgn * pawl_ramp / (cap_skirt_or - r_face)
    xa   = r_face - tooth_grow - 1.0
    xb   = pawl_r + pawl_t + pawl_tab + 1.0
    tooth = tooth.cut(cq.Workplane("XY").polyline([
        (xa, y_at + (xa - cap_skirt_or) * sl), (xb, y_at + (xb - cap_skirt_or) * sl),
        (xb, y_at + sgn * 10.0), (xa, y_at + sgn * 10.0)]).close()
        .extrude(pawl_b + 0.2).translate((0, 0, -0.1)))
pawl = blade.union(tooth).rotate((0, 0, 0), (0, 0, 1), 90)

# ---- assemble, then cut ------------------------------------------------
part = plate.union(collar).union(stops).union(boss).union(pawl)

part = part.cut(cq.Workplane("XY").circle(ins_bore / 2.0).extrude(ins_len)
                .translate((0, 0, z_floor + 0.1)))
cav = (cq.Workplane("XY").rect(cav_flats, cav_flats).extrude(cav_dep + 0.1)
       .translate((0, 0, -0.1)).edges("|Z").fillet(cav_r))
part = part.cut(cav)
part = part.cut(cq.Workplane("XY").circle(scr_clear_d / 2.0)
                .extrude(floor_under + 0.2).translate((0, 0, cav_dep - 0.1)))
for a in (60.0, 180.0, 300.0):
    part = part.cut(cq.Workplane("XY").circle(1.5).extrude(floor_t + 0.2)
                    .translate(((collar_ir - 1.5) * math.cos(math.radians(a)),
                                (collar_ir - 1.5) * math.sin(math.radians(a)), -0.1)))

sh = part.val()
bb = sh.BoundingBox()
print("solids           %d" % len(sh.Solids()))
print("volume           %.3f mm3" % sh.Volume())
print("bbox    x %8.3f .. %8.3f" % (bb.xmin, bb.xmax))
print("        y %8.3f .. %8.3f" % (bb.ymin, bb.ymax))
print("        z %8.3f .. %8.3f" % (bb.zmin, bb.zmax))
print("faces            %d   (planar+analytic B-rep, not tessellated)" % len(sh.Faces()))
cq.exporters.export(part, "mount_adapter.step", cq.exporters.ExportTypes.STEP)
cq.exporters.export(part, "mount_adapter_native.stl",
                    cq.exporters.ExportTypes.STL, tolerance=0.001, angularTolerance=0.05)
print("wrote mount_adapter.step")
