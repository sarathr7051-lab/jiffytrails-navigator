# The BM4 mount interface — MEASURED

Rider-measured 29 Aug 2026 with a steel rule, from a disassembled BOBO BM4
(`Model: BM4 (2023)`, S/N BM00234725 — read off the plate's own moulding).

This file supersedes everything in `COMPONENT_DIMENSIONS.md` §3 and the mount
narrative in `hardware/mount.scad`. Both of those describe a metal ball socket
and an aluminium phone plate. **Neither is metal.** The only metal in the whole
mount is the screw.

---

## 1. The square key — MEASURED, and self-consistent

The socket face carries a square recess. The phone plate carries a matching
raised square pad. The square is what stops the display rotating about the
screw; nothing else does.

| | |
|---|---|
| Across flats | **14.0 mm** |
| Corner to corner | **18.0 mm** |
| Corner radius | **2.17 mm** — derived, see below |
| **Recess depth** | **2.0 mm** |

★ **The two measurements check each other, which is why this is trustworthy.**
A square with sharp corners and a 14.0 mm side has a diagonal of

```
14.0 * sqrt(2) = 19.799 mm
```

The rider measured **18.0**. That 1.8 mm shortfall is exactly what rounded
corners do, and it pins the radius. With half-diagonal 9.0:

```
(s/2 - r) * sqrt(2) + r = 9.0        s = 14.0
(7 - r) * 1.41421 + r   = 9.0
9.8995 - 0.41421 r      = 9.0
                      r = 2.171 mm
```

Two independently taken readings resolving to one plausible moulded geometry is
far stronger evidence than either alone. Treat both as MEASURED.

---

## 2. The screw — a standard catalogue part

| | Measured | ISO 10642 M3 |
|---|---|---|
| Head diameter | **6.0 mm** | 6.0 |
| Head height | **2.0 mm** | 1.7 |
| Total length | **10 mm** | — |
| Thread length | **8 mm** | — |
| Thread dia (paper strip, 10 mm circumference / pi) | **3.18 mm** | 3.0 nominal |

**It is an M3 x 10 countersunk socket-head screw, ISO 10642, 90 degrees.**
Three independent numbers agree with the standard. Steel — the only metal part
in the mount.

Consequence: **screw length is not a design constraint.** A longer M3 CSK costs
a few rupees anywhere. Design the joint to the thickness it needs, then specify

```
screw length = 10 + (thickness our part adds above the original plate)
```

Do not compromise the mechanism to fit the 10 mm screw that came in the box.

---

## 3. ★ Which way the screw goes — and why it changes the design

From the rider's photographs:

- the **phone plate's back** has a **brass heat-set insert** at the centre of
  its raised square pad — visible as a knurled gold ring in black plastic;
- the **socket face** has a **plain through-hole** at the centre of its square
  recess.

So the assembly is:

```
   screw  ->  through the socket's plain hole
          ->  into the BRASS INSERT in the plate
```

**Our printed part replaces the plate, so our part must carry the female
thread.** An earlier working rule in this project — "plain clearance hole, no
thread in printed plastic" — assumed the opposite direction and is withdrawn.

**Use an M3 brass heat-set insert, melted in with a soldering iron.** This is
not a compromise: it is exactly what BOBO did in their own moulded part, for
exactly the same reason. A printed thread on a vibrating motorcycle is the
thing to avoid; a brass insert is the standard answer to that, costs about
5 rupees, and the rider already owns the iron.

---

## 4. Still UNKNOWN

- **Diameter of the circular land** around the square recess. Only needed if
  the 14 mm square proves marginal in shear, in which case a second
  anti-rotation feature further out from the axis is the obvious fix. The rider
  reports it as not protruding, so a boss confined to the 2.0 mm recess clears
  it either way.
- **Insert depth in the original plate** — governs how much thread engagement
  the original design considered sufficient.
- **Depth of the round boss inside the square recess.** The socket face has a
  raised circular feature around the screw hole; our boss must clear it or
  pocket for it.

---

## 5. Corrections this forces elsewhere

| File | Claim | Status |
|---|---|---|
| `COMPONENT_DIMENSIONS.md` §3 | metal ball socket, aluminium plate | **WRONG** — all polymer except the screw |
| `hardware/mount.scad` header | "BM4's aluminium plate" | **WRONG** — plastic |
| `hardware/mount.scad` ★ block | plate joint is a Hirth coupling; never print a mating spline | **UNSUPPORTED.** It is a plain square key. Four independent lines of evidence found no teeth anywhere, and the rider's own part confirms a smooth rounded square. A printed square boss is viable. |
| `hardware/mount.scad` line ~50 | "BM4 arm + plate + adapter 11.0 mm -> 245 N" | **UNFOUNDED** — the standard BM4 has no arm; the main unit attaches directly to the ball. Re-derive the moment arm. |
| `COMPONENT_DIMENSIONS.md` §3.1 | ball diameter "UNKNOWN, a well-founded guess" | **UPGRADE to VERIFIED 17 mm** — two BOBO sources plus a dimensioned manufacturer photograph. |

---

## 6. What the printed mount part therefore needs

1. A **square boss** on its underside: 14.0 across flats less a running
   clearance, 2.17 mm corner radius, and **shorter than the 2.0 mm recess** —
   about 1.8 mm — so our part's FLAT FACE seats on the socket's flat face and
   the boss never bottoms out. A boss that bottoms first carries the clamp load
   on 14 mm of square instead of on the whole face, and leaves the joint able
   to rock.
2. An **M3 brass heat-set insert** on the centre line, with its boss and pilot
   bore sized to the insert's datasheet and enough wall around it.
3. The **female half of the case joint** on its top face — slide or twist, still
   being decided on stability grounds.
4. A **90 degree countersink is NOT needed on our part** — the screw head lands
   on the socket, not on us. Our part sees the insert only.
