# -*- coding: utf-8 -*-
"""
Assembly check on the NATIVE B-rep, in OCCT - a different geometry kernel from
the CGAL one OpenSCAD uses. Agreement between the two is worth more than either
alone, because a boolean bug in one will not be reproduced by the other.

The cap is turned over with a real ROTATION, never a mirror: a mirror is not a
motion a physical object can perform, and it reverses the chiral pawl notch.
"""
import math, cadquery as cq
from cadquery import exporters

FLIP = 26.55            # cap_h + z_capface
QT   = 55.0             # locked angle

ad = cq.importers.importStep("mount_adapter.step")
cp = cq.importers.importStep("mount_cap.step")

def placed(angle_deg, dz=0.0):
    s = cp.val().rotate((0, 0, 0), (1, 0, 0), 180)         # turn it over
    s = s.rotate((0, 0, 0), (0, 0, 1), angle_deg)          # twist to lock
    return s.translate(cq.Vector(0, 0, FLIP + dz))

A = ad.val()
print("adapter %10.3f mm3   cap %10.3f mm3" % (A.Volume(), cp.val().Volume()))
print()
print("  descent to the seat, at the entry angle")
for dz in (3.0, 1.0, 0.3, 0.0):
    v = A.intersect(placed(0.0, dz)).Volume()
    print("     lifted %4.1f mm    %8.3f mm3" % (dz, v))
print("  the turn, seated")
for a in (0.0, 15.0, 30.0, 45.0, QT):
    v = A.intersect(placed(a)).Volume()
    print("     %5.1f deg        %8.3f mm3%s" % (a, v, "   <- LOCKED" if a == QT else ""))
print("  lifting once locked")
for dz in (0.3, 0.5, 1.0, 3.0):
    v = A.intersect(placed(QT, dz)).Volume()
    print("     lifted %4.1f mm    %8.3f mm3" % (dz, v))
print("  turning past the lock")
for a in (58.0, 65.0):
    v = A.intersect(placed(a)).Volume()
    print("     %5.1f deg        %8.3f mm3" % (a, v))

# the rider's socket: a raised square 14.0 across flats, r 2.17, 2.0 tall
boss = (cq.Workplane("XY").rect(14.0, 14.0).extrude(2.0)
        .edges("|Z").fillet(2.17).val())
print()
print("  socket boss into our cavity   %8.4f mm3   (0 = it drops in)"
      % A.intersect(boss).Volume())
seat = A.intersect(cq.Workplane("XY").circle(30).extrude(0.02).val()).Volume()
print("  material in the first 0.02 mm %8.3f mm3  -> first-layer area %.0f mm2"
      % (seat, seat / 0.02))

for name, obj in (("mount_adapter", ad), ("mount_cap", cp)):
    exporters.export(obj, name + ".stl", exporters.ExportTypes.STL,
                     tolerance=0.001, angularTolerance=0.05)
print("\nwrote mount_adapter.stl and mount_cap.stl from the native B-rep")
