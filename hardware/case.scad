/*
  JiffyTrails enclosure - BACK-OPENING. Parametric, printable.

  Open in OpenSCAD (free, openscad.org), press F6, File > Export > STL.

  ---------------------------------------------------------------------------
  ★ WHY THIS OPENS AT THE BACK

  The previous version opened at the front: a tub facing the rider, with the
  lid carrying the window and the hood. Six independent reviews took it apart
  and the failures clustered in one place - the sealing line ran right around
  the display glass, which is the most crowded and least forgiving line on the
  whole case.

    - All four screw bosses stood inside the display's footprint. The module
      could not be lowered into the box at all.
    - The gasket groove had no inner wall: it spanned radius 25.4-27.4 against
      a cavity wall at 26.2, so it opened into the box. A 2.0 mm groove does
      not fit a 2.4 mm rim, and poured sealant would have run onto the boards.
    - Nothing sealed the window. A 1.0 mm gap sat between the glass and the
      lid, and the aperture was an open hole into the electronics.
    - The lid could not clamp a gasket over an 82 mm span with four corner
      screws - computed deflection was larger than the entire squeeze budget.
    - It needed a hole in a sealed wall for USB, or the firmware could never be
      updated by cable again.

  Turning it round dissolves all five rather than solving them:

    THE FRONT IS CLOSED FOR GOOD, with the panel bonded behind it.
    THE BACK IS THE LID - a plain plate, no window, no hood, nothing to align.

  The sealing line moves onto a flat rim with nothing near it. The screws move
  clear of the display. USB is reached by taking the back off. And - the part
  that matters most on a one-shot print - every dimension we are not sure of
  moves into bezel(), a 5 g part that reprints in eight minutes.

  ---------------------------------------------------------------------------
  ★ THE ONE RULE THAT KEEPS THIS SAFE TO PRINT

  bezel() is the ONLY module allowed to read disp_active_w, disp_active_l or
  disp_active_off. Nothing else may reference them.

  Those three are the numbers sourced from a drawing for a DIFFERENT board -
  an LCDWIKI MSP2806, where the panel's ribbon is bonded along the header edge.
  The board actually purchased is a SmartElex with the ribbon on a mid-board
  ZIF connector fed through a slot, and a reviewer measuring the vendor's own
  photograph found its mounting holes evenly spaced where the MSP2806's are
  lopsided. That was the whole reason to believe the glass sits off-centre.

  So the body and the lid - the expensive prints - are built entirely from
  dimensions that cannot move: the 50.0 x 82.0 PCB outline, verified twice.

  ---------------------------------------------------------------------------
  PRINT SETTINGS

  ASA, light coloured. Not PETG and never PLA - docs/HARDWARE.md has the
  arithmetic: PETG's HDT is 65-80 C against an estimated sealed interior of
  53-70 C in Bengaluru sun. ASA gives ~105 C service and does not yellow.

  0.2 mm layers, 5 perimeters (four is the usual watertight threshold; a sealed
  case earns the fifth), 30-40% infill, ENCLOSURE OR DRAFT SHIELD MANDATORY -
  ASA delaminating mid-print on a 100 mm part in a draught is the likeliest way
  to lose the one print available.

  ORIENTATION
    body   FRONT FACE DOWN. Puts the sealing rim on top where it prints
           accurately with no elephant's foot, and the flange flares outward
           going up at 45 degrees so it is self-supporting. 5 mm brim - the
           first layer is a picture frame and adhesion is not optional.
    lid    OUTER FACE DOWN. The warning that used to stand here - a 4 mm
           picture frame and a 56 x 88 unsupported bridge - described the mount
           plate's keying recess, and that recess was deleted with the rest of
           the dovetail mount. Measured on the current part: 6085.8 mm2, ONE
           solid shell, no bridge anywhere and no overhang steeper than 45
           degrees. It is now the easiest print of the set.
    bezel  flat, trivial. 0 mm2 of overhang.
    hood   MOUTH DOWN. 856.8 mm2 in TWO islands - the vent window cuts the
           skirt ring through its full height, so the two halves are not joined
           until the print closes over the window at z 15. Brim both.
           That window ceiling is also the only real bridge in the set: 27 mm.
    mount  see mount_v4.scad. The adapter goes SEATING FACE DOWN - since the
           square became a cavity that face is the first layer, 1248 mm2 flat
           on the bed with no support and no witness marks on the one datum
           that has to be true.
*/

/*
  ★ AT THE TOP, AND `include` NOT `use`.

  This sat at line 631 - below most of the file - until 29 Aug 2026, when a new
  assert referencing dt_base and dt_top was added above it and silently
  evaluated them as undef. `include` pastes at its own location, so everything
  before it cannot see these constants, and OpenSCAD reports that as a warning
  and carries on. Same family as the original bug that created this file:
  `use` imports modules but NOT variables, so dt_h read as undef and nothing
  said so.

  Constants come from ONE file and it is read FIRST.
*/
// ============================================================ PARAMETERS

/* [Display - the two the body depends on are VERIFIED] */
disp_pcb_w      = 50.0;    // VERIFIED twice: drawing, and photo of this board
/*
  ★ 82.0, NOT 86.0. Rider-measured 29 Aug 2026, and cross-checked by his own
  independent route: the white panel frame is 70 mm and sits centred with 6 mm
  of board at each end. 70 + 6 + 6 = 82. Two readings agreeing by different
  means is stronger than either alone.

  The MSP2806 drawing says 86. This is the clearest confirmation yet that the
  board in hand is a different product - and it makes the case 4 mm shorter.
*/
disp_pcb_l      = 82.0;
/*
  Rider-measured 5.0 mm (0.5 cm) glass face to PCB back, against the MSP2806
  drawing 4.40. Taking the measured, larger figure: too deep costs a fraction
  of a millimetre of cavity, too shallow presses the lid onto the panel.
*/
disp_t          = 5.0;
/*
  ★ THE PANEL FRAME STANDS PROUD OF THE PCB. Rider-measured, 29 Aug 2026:
  the white plastic carrier around the glass projects about 0.6 mm BEYOND the
  board edge on both long sides, evenly.

  So the widest part of the module is 51.2 mm, not 50.0 - and the display
  locating ribs were built to a 50.6 mm pocket, which would have stopped the
  module 0.6 mm out and been blamed on print tolerance. Nothing in any
  datasheet mentions this; it took someone holding the part.
*/
disp_frame_proud = 0.35;   // measured; was assumed 0.6
disp_widest      = disp_pcb_w + 2 * disp_frame_proud;

/* [Display - ★ UNVERIFIED. Used ONLY by bezel(), which is 5 g to reprint] */
disp_active_w   = 43.2;    // fixed by 240 px x 0.18 mm - safe
disp_active_l   = 57.6;    // fixed by 320 px x 0.18 mm - safe
/*
  ★★ THE ONE NUMBER TO MEASURE BEFORE PRINTING THE BEZEL.

  How far the lit area sits from centre, toward the far (non-header) end.
  4.90 comes from the MSP2806 drawing and its justification does not survive
  on this board - see the header. Light the screen all white and measure from
  each END edge to where the light starts:

      the two ends roughly equal      ->  0
      header end bigger by about 6    ->  2.90
      header end bigger by about 10   ->  4.90   (what this file assumes)
*/
/*
  ★ 3.5 mm, MEASURED - replacing the 4.90 inherited from the wrong drawing.

  Screen lit white: 14.0 mm of board at the header end, 7.0 at the far end, on
  an 82 mm board. That gives a lit span of 61.0 where the panel can only be
  57.6 (320 px x 0.18), so BOTH readings are 1.70 mm wide.

  A bias that is equal at both ends is what backlight glow does - it spills
  past the pixels by the same amount all round. It inflates the span and leaves
  the difference alone, so the offset is safe to take from the difference:

      (14.0 - 7.0) / 2 = 3.5 mm toward the far end

  Not 0, not 4.90. And it is only used by bezel() - 5 g if this is still wrong.
*/
disp_active_off = 3.5;

/* [The stack, front to back - this is what sets the depth] */
bezel_t         = 1.5;
/*
  ★ Display PCB back face -> perfboard top face. THE decision that sets how
  thick this thing is.

  ★ The header projects 10.0 mm behind the PCB - RIDER-MEASURED. The 8.38 that
  used to be quoted here (2.54 strip + 5.84 pin) is the MSP2806 drawing again.
  It does not change the gap, which is set by the socket and the strip and not
  by the pin - but it means 7.46 mm of free pin goes into an 8.5 mm socket
  rather than 5.84. Engagement is DEEPER than the drawing predicted. Do not
  re-derive anything from 8.38.

    11.0  a 2.54 mm female socket on the perfboard, display plugged in.
          ★ CHOSEN by the rider, 29 Aug 2026 - and NOT for the reason the
          old note here argued.

          That note recommended clipping, on the grounds that the display is
          bonded to the front and "never has to come off". True, and it is
          also the trap, because THE LID IS AT THE BACK. Clip the pins and
          solder wires to them and the display and the perfboard become one
          object whose front end is glued into the case. There is then no way
          to get the perfboard out at all: every repair is nine wires
          desoldered blind, inside a box, against a bonded panel.

          With a socket: undo eight screws, unplug once, and the whole
          electronics module lifts out of the back. The display stays put.

          It is also the only REVERSIBLE choice. Socket now and the pins can
          still be clipped later if the depth is ever wanted back. Clip now
          and they are too short to socket ever again.

          Costs 4.5 mm. Both the socket body (~8.5) and the header's own
          plastic strip (2.54) count - a review put this at 8.5 by omitting
          the strip.

    6.5   pins CLIPPED to a ~2 mm stub, wires soldered to them. Rejected
          above. Also puts a soldering iron on the only display there is.
    2.5   pins pushed THROUGH the perfboard. Rejected: a review found the
          header misses a centred 50 x 70 perfboard's last hole row by 1.3 mm,
          and it solders the only display permanently to the board.
*/
hdr_gap         = 11.04;   // 8.5 socket + 2.54 strip. Exact, not rounded.

/*
  ★ THE FLOOR UNDER hdr_gap, WHICH THE DEPTH SUM NEVER ACCOUNTED FOR.

  hdr_gap looks like free depth and someone will eventually try to shave it.
  It is not free: the display's own FOLDED RIBBON stands 4.0 mm proud of its
  PCB back and sits MID-BOARD - directly over the perfboard. It is a flat
  bundle of hair-fine conductors. Crease it and the display is dead, with no
  repair and no spare.

      hdr_gap floor  =  4.0 ribbon + 1.5 clearance  =  5.5 mm   ALWAYS

  The SD socket is another 3.0 mm, but the perfboard is 12.0 mm shorter than
  the display (82.0 board, 70.0 perfboard - it said 13 while disp_pcb_l still
  said 86) and the overhang falls at the far end, over exactly that socket - so
  the SD socket is clear by geometry rather than by height.

  At 11.04 there is 7.0 mm of air over the ribbon. Comfortable, and the reason
  the socket option was never in danger here.
*/
disp_back_max   = 4.0;     // tallest thing on the display's BACK face
/*
  ★ AND THE OTHER SIDE OF THE SAME GAP, which the first version of this assert
  forgot. hdr_gap is not just "display back to perfboard" - BOTH faces have
  things standing in it:

      from the display:   folded ribbon            4.0   crushable
      from the perfboard: clipped header tails
                          plus their solder        1.5   the build doc's limit
      air between them, minimum                    1.0
                                                  -----
      true floor under hdr_gap                     6.5

  The old guard checked 4.0 + 1.5 = 5.5 and would have passed a gap that put
  the ribbon 1.5 mm inside the solder. It never fired because hdr_gap is 11.04,
  so it looked like a working assert - which is the more dangerous kind.
*/
perf_face_max   = 1.5;     // clipped tails + dressed solder, display face
assert(hdr_gap >= disp_back_max + perf_face_max + 1.0,
       "hdr_gap crushes the display's folded ribbon against the perfboard's solder");
echo(str("header gap ", hdr_gap, " - clear air over the ribbon: ",
         hdr_gap - disp_back_max - perf_face_max, " mm"));
perf_t          = 1.6;
/*
  ★ THE PERFBOARD OUTLINE, WHICH NOTHING IN THIS FILE USED TO KNOW.

  A standard 50 x 70 board. It is quoted in prose twice above - "a centred
  50 x 70 perfboard's last hole row" and "the perfboard is shorter than the
  display" - and until the retention ledges below it existed nowhere as a
  number, which is exactly how the case ended up with nothing holding it.
*/
perf_w          = 50.0;
perf_l          = 70.0;
/*
  ESP32 on male header pins through the perfboard: 2.54 strip + 1.6 PCB +
  6.0 JST connector. The JST is the tallest thing on the board and this build
  has no battery, so desoldering it would take this to 7.2 and the case to
  36.3 mm.

  ★ THE JST STAYS. Rider's call, 29 Aug 2026: thickness is not what will
  bite on this bike, and a first build is the wrong time to take an iron to
  the only ESP32 there is. It can still come off later - a two-pin connector
  on a net nothing uses is the safest desoldering practice that exists, and
  the case is printed after the electronics work, not before.
*/
mcu_stack       = 10.2;
retain_pad      = 2.0;     // closed-cell foam on the lid, pushes the stack forward

/* [Shell] */
wall            = 2.4;
front_t         = 3.0;     // closed front, carries the window opening
lid_t           = 5.0;     // ★ 5 mm. Deflection between screws goes as t^-3
land_w          = 6.0;     // sealing land: 0.8 + 4.0 foam + 1.2, and also
                           // exactly what a 2.5 mm self-tapping boss needs
inner_clear     = 1.2;
corner_r        = 4.0;
corner_r_out    = 7.6;

/* [Seal] */
/*
  ★ CLOSED-CELL FOAM TAPE, not an O-cord, and the vent is why.

  With a working pressure vent the gasket never sees the 13.3 kPa thermal
  vacuum that would otherwise make this box a pump. What is left is driven rain
  at ~300-460 Pa. An O-cord is built for bar-level sealing and pays for it in
  tolerance: 25% squeeze on a 2 mm cord is 0.5 mm, usable band +/-0.15 mm - and
  an ASA part this size bows 0.3-0.8 mm as it cools. The gasket would be
  defeated by warp alone, before it ever met water.

  3 mm foam closing to 2 mm is 33% compression with a +/-0.5 mm usable band,
  which covers the warp with room to spare. Closing force drops to ~5 N per
  screw, which is also what makes self-tapping screws viable.

  ★ BUY CLOSED-CELL EPDM, NOT OPEN-CELL POLYURETHANE. Most cheap "foam tape"
  is open cell and wicks like a sponge. Test it: cut a piece, hold it under
  water and squeeze. Open cell streams bubbles and stays wet.
*/
foam_w          = 4.0;
foam_d          = 2.0;     // channel depth; 3 mm tape closes to 2 mm
spigot_h        = 2.5;     // labyrinth - see lid()
spigot_clear    = 0.2;

/* [Fasteners] */
/*
  8 x M3 x 12 self-tapping into blind holes. Not heat-set inserts: those need
  a 4.0 mm bore and 1.6 mm of wall either side, which costs 2.4 mm of envelope
  in both directions, and they need eight iron-driven insertions into a part
  that cannot be reprinted. Required preload here is ~5 N per screw against a
  strip torque forty times that, and the land-on-land hard stop absorbs
  over-tightening, so the thread never sees abuse.

  Every hole is BLIND, bottoming in solid ASA. A screw hole is a dead end, not
  a leak path - which is what makes it safe to run them through the foam band.

  ★ THE MOUNT PLATE'S FOUR ARE M3 x 8, NOT x 12. Different joint, different
  sum, and an M3 x 12 there bottoms out before the plate is tight - it feels
  tight and carries no preload at all. The arithmetic is in the MOUNT PLATE
  section, and lid() says why the pilot had to get deeper.
*/
screw_pilot_d   = 2.5;
screw_clear_d   = 3.4;
screw_depth     = 9.0;
/*
  ★ screw_head_d WAS DECLARED AND REFERENCED NOWHERE.

  Which is the fingerprint of a counterbore that was specified in prose and
  never cut. Two things were standing proud because of it, both of them
  assembly-stoppers rather than cosmetic:

    - the lid's eight heads sit on the lid's OUTER face, and the mount plate
      covers that whole face. The plate rocked on eight 2.4 mm pips.
    - the mount plate's own four heads sat on z = 9.0, which is also the face
      the dovetail adapter beds against. 2.4 mm of head against 0.29 mm of
      dovetail clearance: the case jammed 2 mm before it seated.

  Both are now cut - see mount_plate(). screw_head_h is the other half of the
  pair and has to exist for either depth to be checkable.

  6.0 x 2.4 is an M3 PAN head (DIN 7981 ST3.5: 5.6 dia, 2.4 high) with a little
  over on the diameter.

  ★ AND IT HAS TO BE THE PAN HEAD, NOT A SOCKET CAP, FOR THE EIGHT LID SCREWS.
  A DIN 912 cap is 5.5 x 3.0. The lid screw at (0, band_y) ends up underneath
  the mount plate's dovetail slot, whose floor is only 2.71 mm above the plate's
  underside; a 2.4 mm head clears that floor by 0.31 mm and a 3.0 mm one stands
  0.29 mm INTO the slot and jams the adapter. The assert in the MOUNT PLATE
  section states this in the only place it can be seen. The four mount-plate
  screws are counterbored deep enough to take either.
*/

/*
  The mount-plate joint: four M3 through the plate into blind pilots in the
  lid's outer face. Named here because the arithmetic that sets the screw
  LENGTH spans three modules, and it was wrong for as long as it was implicit.
  The sum, the asserts and the reason for every number are in the MOUNT PLATE
  section, next to mount_plate_t which half of it depends on.
*/
                           // face. Blind: lid_t - this must stay >= 1.0.

/* [Openings] */
/*
  ★ VENT: 6.0 MINIMUM, NOT 3.0.

  The thermal argument is right and the vent is mandatory - a sealed 50 mL box
  quenched from 70 C to 25 C pulls 13.3 kPa, which is 1.36 m of water head and
  nothing holds that. But the residual pressure is set by the MEMBRANE'S FLOW
  RESISTANCE, not by the hole. Rain-jacket ePTFE passes about 1 L/m2/s at
  100 Pa, so:

      Dia 3   ->  13.2 mbar = 135 mm of head on a 60 s quench
      Dia 6   ->   3.8 mbar =  39 mm
      Dia 10  ->   1.4 mbar =  14 mm

  "Under 1 mbar" was optimistic by more than tenfold at Dia 3. Open it up; it
  is free.
*/
vent_d          = 6.0;
vent_seat_d     = 12.0;    // membrane bonding land, inside
vent_seat_t     = 0.6;
/*
  ★ POTTED CABLE ENTRY, NOT A GLAND. An M8 gland's Dia 14 locknut needs 16 mm
  of clear wall face on the inside and fouls the ESP32 at every plausible
  position - which is why the old design's gland never worked out. A printed
  tube filled with neutral-cure silicone seals better, needs no internal
  hardware, and costs nothing.
*/
cable_bore_d    = 4.5;     // ★ MEASURE the cable: paper strip, circ / 3.1416
/*
  ★★ 12.0, NOT 8.5, so the anchor chamber can exist at all.

  cable_in has declared a 6 mm anchor chamber since the file was written and
  never cut one: placed inboard it removes 5 mm3 of open cavity air, and placed
  outboard into an 8.5 boss it leaves 0.25 mm of wall. The case gets lifted by
  its cable, silicone fails in PEEL at the bore mouth, and the result is an
  invisible leak path - so the chamber is worth having.

  O12 leaves 2.0 mm of wall around a O8 chamber. The boss sits at cable_x 4.0
  on the -y end face, spanning x -2 to 10 inside a shell half-width of 28.6, so
  it costs nothing anywhere.
*/
cable_boss_d    = 12.0;
/*
  ★★ cable_in IS NOW USED, AND IT IS AN ANCHOR CHAMBER.

  It was declared and referenced in no module - the same fingerprint as
  screw_head_d before it. Worse, what it implied did not exist: the potting was
  a plain O4.5 bore with nothing for the silicone to key into.

  The case gets lifted by its cable sometimes; everyone does it. Silicone in a
  smooth bore fails in PEEL at the mouth, invisibly, and the result is a leak
  path you cannot see. So the bore opens into a wider chamber INSIDE the wall:
  put a cable tie on the cable inside the case, pull it back into the chamber,
  and pot around it. The tie cannot pass back out through the O4.5 mouth, so
  the pull goes into ASA rather than into the adhesion of the silicone.

  Free, and it converts the seal's worst load case into a mechanical stop.
*/
cable_in        = 6.0;     // depth of the anchor chamber, inside the wall
cable_chamber_d = 8.0;     // wide enough to trap a 2.5 mm cable tie head
cable_out       = 4.0;
/*
  ★ BOTH PENETRATIONS ARE OFFSET DELIBERATELY - they collide with the screw
  ring if left on centre. The vent on the +x wall at y=0 lands exactly on the
  mid-side screw, and a centred cable boss overlaps the mid-end screw by
  0.15 mm in z. Neither would have shown up in a render.
*/
/*
  ★ 4.0, NOT 16.0 - THE END RIB WAS STANDING IN THE POTTING BORE.

  Same cause as the vent above and found the same way: 1.273 mm3 of the -y end
  rib (x = 14, so it spans x 10 -> 18) inside the Dia 4.5 bore, rising 0.755 mm
  off the bore's floor across x 14.32 -> 17.68. cable_x was 16.0, which is the
  dead centre of that rib.

  A rib in this particular bore is worse than a rib anywhere else, because the
  entry is POTTED. Silicone poured round an obstruction does not fill behind
  it; it bridges, and the void it leaves is a path with water at one end.

  ★ THE OUTBOARD MOVE LOOKS OBVIOUS AND IS NOT AVAILABLE. Two limits close on
  each other and the window between them is a tenth of a millimetre:

      bore must clear the rib's outer end at x = 18      cable_x >= 20.25
      boss must stay on the FLAT part of the end face,
      whose corner arc starts at x = 24.6 (r = 4.0)      cable_x <= 20.35

  Measured, not argued: the boss's embedded section holds at 22.6615 mm3 for
  every cable_x up to 20.35 and drops to 22.0078 at 22.0, which is the boss
  beginning to hang off the corner radius. A potting chamber whose wall runs
  off a curve is not a potting chamber.

  So inboard, into the 20 mm window between the two end ribs (x -10 to +10),
  and as near the middle of it as the bore's own diameter allows. Both margins
  measured on the rendered meshes:

      cable_x = 16.0   INTERFERES with the end rib, 1.273 mm3
      cable_x =  4.0   3.9362 mm to the end ribs
                       8.0900 mm to the mid-end screw pilot at (0, -45)

  ★ AND THE REASON THIS USED TO BE OFF CENTRE IS GONE. The note above says a
  centred boss "overlaps the mid-end screw by 0.15 mm in z". At the cable_z and
  screw_depth this file now carries, a boss centred at x = 0 clears that pilot
  by 8.09 mm - it was true of some earlier stack and nothing re-checked it.
  4.0 is not offset to dodge the screw; it is offset because that is where the
  most room is, and it keeps the bore wholly on one side of the centre line.
*/
cable_x         = 4.0;     // in the window between the two end ribs
/*
  ★ 13.0, NOT 11.0. At 11.0 the O4.5 bore spans z 8.75-13.25 while the
  display's back face is at z 9.5 and the display covers x = +/-25, which
  contains cable_x wherever it has been put (16.0 then, 4.0 now) - so 0.75 mm
  of the bore's roof was blind against the display's own edge, and the potting
  silicone would have been pushed against it. The argument is about z and does
  not move when cable_x does.
  At 13.0 the bore spans 10.75-15.25, entirely behind the display, and
  still clears the flange flare, which starts at body_h - 11.2 = 23.14. (That
  number read 27.6 here, left over from a taller body_h; the vent_z block ten
  lines down had the right one, so the file disagreed with itself about where
  the flare begins. Both now say 23.14.) The clearance is 6.96 mm, measured
  from the TEARDROP APEX at 16.18 rather than the round bore's 15.25 - the
  apex is the part that would break out.
*/
cable_z         = 13.0;
/*
  ★ 18.0, NOT 22.0 - THE RIB WAS SITTING IN THE MEMBRANE'S BONDING LAND.

  Found by probe, not by eye. disp_ribs() is unioned AFTER the difference(),
  so no cut in this file touches it: material the ribs add back into a bore
  simply stays there. Rendering the +30 side rib intersected with the seat gave
  2.997 mm3 of solid rib inside the Dia 12 land, at y 26.00-27.98, x 26.2-26.8.

  That is not a clearance problem, it is the whole point of the seat. The land
  exists so the ePTFE patch has something FLAT to bond to; a rib crossing its
  +y edge means the patch tents over a 2 mm ramp on one side and the bond line
  has a channel under it. A vent that leaks is worse than no vent - it is a
  hole with a story attached.

    seat at 22.0   y 16 -> 28   against the +30 rib at y 26 -> 34   -2.00
    seat at 18.0   y 12 -> 24   against the same rib               +2.00

  The rib was NOT the thing to move. It is a locating feature bearing on the
  display's own edge, and the display is the part with no spare; shortening it
  would trade a sealing problem for a location problem. The vent has no reason
  to be at any particular y, so the vent moved.

  Still between the screws, which was the original constraint: the mid-side
  screw is at y = 0 and the corner at y = 42.5. And the y = 0 side rib ends at
  y = 4, so the land's other edge clears that by 8.00.
*/
vent_y          = 18.0;    // between the corner and mid-side screws
/*
  *** 12.0, NOT 21.2. *** Two reasons, found 29 Aug 2026:

    - at 21.2 the bore's apex reached z 25.44, breaking out through the 45
      degree flange flare that starts at body_h - 11.2 = 23.14.
    - the membrane seat (O12, centred on the bore) spanned z 15.2-27.2, and
      the perfboard retention ledge bears at z 20.54. The ledge would have run
      straight across the middle of the bonding land, so the ePTFE patch could
      not have been laid flat - or at all.

  At 12.0 the seat spans z 6-18 and the ledge's BEARING FACE is at 20.54, so
  that reads as 2.54 mm of clearance - and it is 2.54 mm of clearance to the
  wrong feature. The ledge that now exists has a 45 degree underside chamfer
  whose toe meets the cavity wall at z = ledge_z - ledge_cham = 18.34, which is
  0.34 mm above the top of the bonding land. That is the real number, it is the
  tightest clearance anywhere on the ledge, and it is positive only because
  vent_z came down to 12.0. The assert below guards it; if vent_z ever rises
  again it fires at 18.34 - not at 20.54.
*/
vent_z          = 12.0;

/* [Hood - separate part, bolts on] */
hood_depth      = 30.0;
hood_rake       = 12;      // set AFTER the rider settles the mount angle
hood_ribs       = 5;
hood_wall       = 1.6;
/*
  ★ 4.0, NOT 5.0. The hood is a 30 mm lever on two small pads and it is the
  first thing a knee, a car park fall or a garage doorframe touches. That is
  correct - it is the sacrificial part, 8 g and reprintable. What was NOT
  acceptable is that shearing a pad opened a hole into the sealed cavity:
  the assert passed with EXACTLY 1.00 mm of ASA behind each blind pilot, which
  is the minimum it allows and no margin at all. 4.0 leaves 2.00 mm.

  The screw loses 1 mm of thread and gains a case that survives its own
  sacrificial part failing.
*/
hood_pilot_len  = 4.0;     // blind, into the side pads. See body() - this used
                           // to be a 12 mm through bore into the sealed cavity.
/*
  ★ THE PAD AND THE SKIRT ARE ONE JOINT AND THEY WERE WRITTEN AS TWO.

  body() drew the pads from literals and hood() drew its screw holes from
  different literals, and the two ended up 5.0 mm apart in z - the hood's holes
  landed at body z = 6.0 against pads pilots at 11.0. The hood could not be
  bolted on at all, and nothing said so because they are in different modules
  and neither render shows the other.

  ONE set of numbers now, read by both. If you move a pad, the hood follows.
*/
hood_pad_d      = 7.2;             // the pads on the body's sides
hood_pad_z0     = front_t + 6;     // pad bottom,  body z =  9.0
hood_pad_h      = 14.0;            // pad height,  body z -> 23.0
hood_pad_z      = front_t + 8;     // pilot centre, body z = 11.0
hood_skirt_h    = 14.0;            // skirt covers body z 0 -> 14
hood_funnel     = 7.0;             // skirt mouth -> tube. See hood().
hood_pad_clear  = 0.6;             // hood's pocket over the body's pad
hood_boss_wall  = 1.8;             // hood material outboard of that pocket
/*
  ★ M3 x 5, NOT 6. hood_pilot_len came down from 5.0 to 4.0 so there is 2.00 mm
  of ASA behind each blind pad pilot instead of exactly 1.00 - the hood is the
  first thing a fall or a doorframe touches, and shearing a pad must not open a
  hole into the sealed cavity. That costs a millimetre of thread, and the assert
  below caught the screw bottoming before the hood was tight. 5 mm restores the
  margin: engagement 2.5, pilot 4.0, 1.5 spare.
*/
hood_screw_len  = 5.0;             // M3 x 6 into the pad. Not x 12.

/*
  [Display locating ribs]

  ★ THESE WERE LITERALS INSIDE disp_ribs() AND THAT IS HOW TWO BORES ENDED UP
  WITH A RIB IN THEM. The ribs are unioned AFTER the difference(), so nothing
  cut in this file removes them - they are the one feature that can silently
  reoccupy a hole. Named here so the vent and the cable entry can be ASSERTED
  clear of them instead of assumed clear of them.
*/
rib_side_y      = [-30, 0, 30];   // side ribs, along the long walls
rib_end_x       = [-14, 14];      // end ribs, across the short walls
rib_w           = 2.0;
rib_l           = 8.0;

/* [Print] */
$fn             = 64;

// ============================================================ DERIVED

cav_w = disp_pcb_w + 2 * inner_clear;          // 52.4
cav_l = disp_pcb_l + 2 * inner_clear;          // 84.4  (said 88.4 - stale from
                                               //        disp_pcb_l = 86.0)
cav_d = bezel_t + disp_t + hdr_gap + perf_t + mcu_stack + retain_pad;

body_w = cav_w + 2 * land_w;                   // 64.4
body_l = cav_l + 2 * land_w;                   // 96.4   (said 100.4 - same)
body_h = front_t + cav_d;                      // outer face to sealing face
case_h = body_h + lid_t;

z_land  = body_h;                              // the sealing face
band_x  = cav_w / 2 + land_w / 2 - 0.2;        // foam centreline
band_y  = cav_l / 2 + land_w / 2 - 0.2;

// Eight screws. Pitch must stay under ~45 mm for a 5 mm lid; the longest gap
// here is 42.5 along the sides and 29.1 across the ends - corner (29.0, 42.5)
// to end (0, 45.0) is sqrt(29.0^2 + 2.5^2) = 29.1, not the 32.2 that stood
// here. 32.2 is body_w/2, which is not a screw pitch at all.
screw_pts = [[ band_x,  42.5], [-band_x,  42.5],
             [ band_x, -42.5], [-band_x, -42.5],
             [ band_x,   0  ], [-band_x,   0  ],
             [ 0,     band_y ], [ 0,    -band_y]];

/*
  ★ THE LOCK SCREW MUST ACTUALLY REACH THE DOVETAIL.
  Bore starts at x = 32.3 and runs inward. The flank it has to bear on sits at
  the bore's own height, half way down the seated dovetail.
*/

/*
  ============================================================================
  ★ PERFBOARD RETENTION LEDGES - AND THE 0.8 mm SHELF THAT DID NOT REACH.

  Until now NOTHING held the perfboard. The stack arithmetic placed it - the
  cav_d sum has perf_t in it - but placement is not retention: the board sat on
  nine header pins and a pad of foam, free to slide the length of the cavity
  and shear the pins it was plugged into.

  ★ THE FIRST PROPOSAL WAS ARITHMETICALLY WRONG AND HAD TO BE THROWN OUT.
  It read "0.8 mm shelf, 50.6 mm clear between lips", which is two features
  described as if they were one. Do the sum:

      cavity half-width                        26.2
      a 0.8 mm shelf reaches inboard to        25.4
      a centred 50.0 board's edge sits at      25.0
                                              ------
      overlap                                  -0.4   THE BOARD FALLS PAST IT

  The 50.6 figure is right, but it belongs to the LIP - the fence that stops
  the board sliding sideways - and a lip at 25.3 cannot also be the shelf that
  holds it up, because the board's edge is inboard of it. They are two
  projections at two heights and the file now says so:

      SHELF  x 26.2 -> 24.0,  top face at ledge_z.  1.0 mm under each edge.
      LIP    x 26.2 -> 25.3,  ledge_z -> +2.0.      50.6 clear, board is 50.0.

  ★ THE BEARING HEIGHT IS NOT A CHOICE. It is the running total of the stack
  above it, which is the only way it can never disagree with cav_d:

      front_t 3.0 + bezel_t 1.5 + disp_t 5.0 + hdr_gap 11.04  =  20.54

  ★ THE UNDERSIDE IS CHAMFERED BECAUSE THE BODY PRINTS FRONT FACE DOWN.
  +z is up on the bed, so a shelf projecting 2.2 mm inboard is 2.2 mm of
  unsupported horizontal overhang - it would droop onto the display's ribbon
  space and print as a fringe. Ramped at 45 degrees (run == projection, which
  is what the assert checks) it is self-supporting, and the ramp is not a
  chamfer bolted onto a shelf: it IS the shelf, a triangular gusset whose top
  face is the bearing face. Nothing is added and nothing overhangs.

  ★ THE STOPS FACE THE FAR END. The board is pushed toward the header end and
  the two tabs at y = +28.5 stop it going the other way; a 70 mm board against
  them reaches y = -41.5 against a cavity end at -42.2, which is 0.7 mm and is
  the tightest fit in the box. That is what the last assert here is about.
  ============================================================================
*/
ledge_z      = front_t + bezel_t + disp_t + hdr_gap;   // 20.54 - board's front face
ledge_in_x   = 24.0;       // shelf reaches this far inboard
ledge_lip_x  = 25.3;       // lip inner face -> 50.6 clear between the two
ledge_lip_h  = 2.0;
ledge_proj   = cav_w / 2 - ledge_in_x;                 // 2.2
ledge_cham   = ledge_proj;                             // 45 deg: run == projection
ledge_bury   = 1.0;        // how far the profile is buried in the wall, so the
                           // union has no coplanar faces to argue about
ledge_y0     = -38.0;
ledge_y1     =  26.0;
ledge_stop_y =  28.5;
ledge_stop_l =   3.0;

assert(ledge_in_x < perf_w / 2,
       "the shelf does not reach under the board - the perfboard drops straight past it");
assert(ledge_lip_x > perf_w / 2,
       "the lips are closer together than the board is wide - it will not go in");
assert(2 * ledge_lip_x - perf_w <= 1.0,
       "more than 1 mm of slop between the lips - the board rattles");
assert(ledge_lip_h > perf_t,
       "the lip is shorter than the board it is meant to capture");
assert(ledge_cham >= ledge_proj,
       "the shelf's underside is steeper than 45 degrees - it will droop, printing front face down");
/*
  ★ FIVE THINGS LIVE IN THIS CAVITY ALREADY AND THE LEDGE CLEARS ALL OF THEM.
  Every one of these was checked by rendering the intersection and finding it
  empty, not by looking at it. The numbers are the margins.
*/
assert(ledge_z - ledge_cham > front_t + bezel_t + disp_t + 2.0,
       "the ledge fouls the display locating ribs");
assert(ledge_z - ledge_cham > vent_z + vent_seat_d / 2,
       "the ledge runs across the vent's membrane bonding land - the patch cannot be laid flat");
assert(ledge_in_x > cable_x + cable_bore_d / 2,
       "the ledge runs into the cable bore");
assert(ledge_z + ledge_lip_h < body_h - spigot_h,
       "the lip fouls the lid's spigot - the lid cannot close");
assert(ledge_z + ledge_lip_h < z_land - screw_depth,
       "the lip reaches up into the blind screw pilots");
assert(ledge_bury < wall,
       "the ledge profile is buried deeper than the wall is thick - it breaks out of the case");
assert(ledge_y0 > -cav_l / 2 && ledge_stop_y + ledge_stop_l < cav_l / 2,
       "the ledge runs out of the cavity");
assert(ledge_stop_y - perf_l > -cav_l / 2,
       "a board pushed against the stop tabs overhangs the near end of the cavity");
/*
  And the board's CORNER has to fit the cavity's corner radius, which the
  straight-edge check above cannot see.
*/
ledge_corner_d = sqrt(pow(perf_w / 2 - (cav_w / 2 - (corner_r - wall)), 2) +
                      pow(perf_l - ledge_stop_y - (cav_l / 2 - (corner_r - wall)), 2));
assert(ledge_corner_d <= corner_r - wall,
       "the perfboard's near corners foul the cavity's corner radius");

echo(str("ledge: bears at z=", ledge_z, ", board overlap ", perf_w / 2 - ledge_in_x,
         " mm/side, ", 2 * ledge_lip_x, " clear between lips, lip proud of board ",
         ledge_lip_h - perf_t));
echo(str("ledge clearances - ribs ", ledge_z - ledge_cham - (front_t + bezel_t + disp_t + 2.0),
         ", vent seat ", ledge_z - ledge_cham - (vent_z + vent_seat_d / 2),
         ", cable bore ", ledge_in_x - (cable_x + cable_bore_d / 2),
         ", lid spigot ", body_h - spigot_h - (ledge_z + ledge_lip_h),
         ", screw pilots ", z_land - screw_depth - (ledge_z + ledge_lip_h)));
/*
  ============================================================================
  ★ NOTHING MAY STAND INSIDE A BORE, AND ONLY disp_ribs() CAN.

  Three of these were found at once by intersecting every cut in body() with
  the finished solid and looking for a result that was not empty. Every hit was
  a display rib, because the ribs are the only geometry unioned AFTER the
  difference(): a cut removes material, and then a rib puts some of it back,
  and the render is beautiful either way.

  These are the three, and they are asserted rather than remembered.
  ============================================================================
*/
function gap1d(a0, a1, b0, b1) = (b0 >= a1) ? b0 - a1 : (b1 <= a0) ? a0 - b1 : -1;

vent_land_y0  = vent_y  - vent_seat_d  / 2;
vent_land_y1  = vent_y  + vent_seat_d  / 2;
cable_bore_x0 = cable_x - cable_bore_d / 2;
cable_bore_x1 = cable_x + cable_bore_d / 2;
vent_rib_gap  = min([for (ry = rib_side_y)
                        gap1d(vent_land_y0, vent_land_y1, ry - rib_l / 2, ry + rib_l / 2)]);
cable_rib_gap = min([for (rx = rib_end_x)
                        gap1d(cable_bore_x0, cable_bore_x1, rx - rib_l / 2, rx + rib_l / 2)]);

assert(vent_rib_gap > 1.0,
       "a display side rib is standing in the vent's membrane bonding land - the patch cannot bond flat");
assert(cable_rib_gap > 1.0,
       "a display end rib is standing in the potted cable bore - the silicone will bridge it and leave a void");
/*
  And the boss the silicone is poured into has to sit on the FLAT part of the
  end face. Past x = 24.6 that face is the corner radius.
*/
assert(abs(cable_x) + cable_boss_d / 2 <= cav_w / 2 + wall - corner_r,
       "the cable boss hangs off the end face's corner radius - the potting chamber has no flat wall");
/*
  Not a rib, but it belongs with them because it was found by the same sweep:
  the hood pad pilot used to run clean through the wall into the cavity.
*/
assert(body_w / 2 - hood_pilot_len >= cav_w / 2 + 1.0,
       "the hood pad pilot breaks through into the sealed cavity");

echo(str("bores vs ribs - vent land ", vent_land_y0, " to ", vent_land_y1,
         ", clear of the side ribs by ", vent_rib_gap,
         "; cable bore ", cable_bore_x0, " to ", cable_bore_x1,
         ", clear of the end ribs by ", cable_rib_gap));

/*
  ============================================================================
  ★ THE HOOD'S NUMBERS, AT FILE SCOPE SO THEY CAN BE ASSERTED.

  They were locals inside hood(), which is why hood() could disagree with
  body() about where the mounting pads are for as long as it did. An assert
  cannot see a local.
  ============================================================================
*/
hood_ow      = 48.0 + 2 * hood_wall + 2;      // tube outer
hood_ol      = 74.0 + 2 * hood_wall + 2;
hood_hole_w  = cav_w + 2 * wall + 0.4;        // skirt's mouth, over the body
hood_hole_l  = cav_l + 2 * wall + 0.4;
hood_boss_d  = hood_pad_d + hood_pad_clear + 2 * hood_boss_wall;
hood_pocket_h = hood_skirt_h - hood_pad_z0 + hood_pad_clear;
hood_screw_z  = hood_skirt_h - hood_pad_z;    // hole in the hood's own frame
// how far the funnel's INNER surface has to close in; at 45 degrees the
// funnel must be at least this tall or it prints as a droop into the bore
hood_funnel_run = max((hood_hole_l - (hood_ol - 2 * hood_wall)) / 2,
                      (hood_hole_w - (hood_ow - 2 * hood_wall)) / 2);
hood_grip    = (cav_w / 2 + wall + hood_boss_d / 2) - body_w / 2;
hood_engage  = hood_screw_len - hood_grip;

assert(hood_funnel >= hood_funnel_run,
       "the hood's funnel is steeper than 45 degrees - it droops into the bore, printed mouth down");
assert((hood_pad_d + hood_pad_clear) / 2 + cav_w / 2 + wall > body_w / 2,
       "the hood's pad pocket does not clear the pad - the hood will not go on");
assert(hood_pocket_h >= hood_skirt_h - hood_pad_z0,
       "the hood's pad pocket is shorter than the part of the pad inside the skirt");
assert(hood_skirt_h - hood_pad_z - screw_clear_d / 2 > 0.5,
       "the hood's screw hole runs off the mouth of the skirt");
assert(hood_skirt_h - cable_z - (cable_boss_d + 1.0) / 2 < 0,
       "the hood's cable notch is closed at the mouth - the hood cannot slide past the cable boss");
assert(hood_engage >= 2.0,
       "under 2 mm of thread is holding the hood on");
assert(hood_engage <= hood_pilot_len - 0.5,
       "the hood screw bottoms in the pad's pilot before the hood is tight");
echo(str("hood: funnel ", hood_funnel, " (needs ", hood_funnel_run,
         "), boss O", hood_boss_d, " reaching x=", cav_w / 2 + wall + hood_boss_d / 2,
         " over a pad face at ", body_w / 2,
         "; screw M3 x ", hood_screw_len, ", grip ", hood_grip, ", thread ", hood_engage,
         " in a ", hood_pilot_len, " pilot"));
echo(str("hood overall: skirt ", hood_skirt_h, " + funnel ", hood_funnel,
         " + shade ", hood_depth, " = ", hood_skirt_h + hood_funnel + hood_depth, " mm"));

echo(str("board against the stops: near edge at y=", ledge_stop_y - perf_l,
         ", cavity end at ", -cav_l / 2, ", corner fit ", ledge_corner_d,
         " into ", corner_r - wall));

echo(str("cavity ", cav_w, " x ", cav_l, " x ", cav_d));
echo(str("body   ", body_w, " x ", body_l, " x ", body_h));
echo(str("CASE   ", body_w, " x ", body_l, " x ", case_h, " mm"));

// ============================================================ PRIMITIVES

module rrect(w, l, h, r) {
    hull() for (x = [-1, 1], y = [-1, 1])
        translate([x * (w / 2 - r), y * (l / 2 - r), 0])
            cylinder(h = h, r = r);
}

/*
  ★ TEARDROP for every HORIZONTAL hole. A round hole printed axis-horizontal
  bridges its own diameter at the crown and sags 0.2-0.4 mm, out of round, on
  the exact face a seal touches - and the usual repair is drilling a finished,
  sealed part with swarf falling inside it. The 45 degree roof is
  self-supporting and leaves the bore round everywhere a seal meets it.
*/
module teardrop_2d(d) {
    r = d / 2;
    union() {
        circle(r = r);
        polygon([[-r * cos(45), r * sin(45)],
                 [ r * cos(45), r * sin(45)],
                 [ 0,           r * sqrt(2)]]);
    }
}
module teardrop_y(d, h) { rotate([90, 0, 0]) linear_extrude(h, center = true) teardrop_2d(d); }
module teardrop_x(d, h) { rotate([90, 0, 0]) rotate([0, 90, 0])
                              linear_extrude(h, center = true) teardrop_2d(d); }

// ============================================================ BODY

/*
  The sealed shell. Front face at z = 0, sealing rim at z = body_h, cavity
  opening toward +z (the rider's side is -z).
*/
module body() {
    difference() {
        union() {
            // main shell
            rrect(cav_w + 2 * wall, cav_l + 2 * wall, body_h, corner_r);
            // flange block carrying the seal and the screws, flared in at 45
            // degrees from below so it prints without support
            translate([0, 0, body_h - 11.2]) hull() {
                rrect(cav_w + 2 * wall, cav_l + 2 * wall, 0.01, corner_r);
                translate([0, 0, 3.6])
                    rrect(body_w, body_l, 0.01, corner_r_out);
            }
            translate([0, 0, body_h - 7.6]) rrect(body_w, body_l, 7.6, corner_r_out);
            // hood mounting pads, y = 0 each side, bringing the mid-body to
            // exactly body_w so they cost no envelope at all - which is also
            // why the HOOD has to bulge over them. See hood().
            for (x = [-1, 1])
                translate([x * (cav_w / 2 + wall), 0, hood_pad_z0])
                    cylinder(h = hood_pad_h, d = hood_pad_d);
            // cable entry boss
            translate([cable_x, -body_l / 2, cable_z])
                rotate([90, 0, 0]) cylinder(h = cable_out * 2, d = cable_boss_d, center = true);
            /*
              ★★ INSIDE THE union(), NOT AFTER THE difference() - 2 Sep 2026.

              Added after it, the shroud was immune to the two cuts it sits on
              top of, and it re-filled both: 49.4 mm3 of solid inside the O6
              vent bore over the bore's whole upper half for 3.0 mm, and
              28.2 mm3 - 42% - of the O12 membrane land, because the 0.5 mm
              the gusset is sunk to make it merge is sunk straight into the
              0.6 mm seat. Measured on the rendered mesh, both.

              That is disp_ribs()'s own warning happening to a different
              feature: material unioned after the difference cannot be cut by
              anything in this file. The ribs must stay outside because the
              cavity would eat them; the shroud is entirely at x >= 28.1 and
              no cut here touches it except the two that must.
            */
            vent_shroud();
        }

        // cavity, opening at the back
        translate([0, 0, front_t]) rrect(cav_w, cav_l, cav_d + 1, corner_r - wall);

        // window opening. Sized from the PCB outline, NOT from the active area
        // - 48 x 74 leaves 1.0 mm of overlap on the 50 mm glass width, which is
        // all there is, and the bezel behind it does the precise work.
        translate([0, 0, -1]) rrect(48.0, 74.0, front_t + 2, 2.0);
        // outer relief so rain sheds off the aperture rather than pooling in it
        translate([0, 0, -0.01]) hull() {
            rrect(51.0, 77.0, 0.01, 2.5);
            translate([0, 0, 1.5]) rrect(48.0, 74.0, 0.01, 2.0);
        }

        // blind screw holes, from the sealing face down
        for (p = screw_pts)
            translate([p[0], p[1], z_land - screw_depth])
                cylinder(h = screw_depth + 0.1, d = screw_pilot_d);

        /*
          *** THESE TWO PILOTS WENT STRAIGHT THROUGH INTO THE ELECTRONICS. ***

          Found while checking the retention ledges past every hole in the wall.
          It is the vent bug again, exactly - a centred cylinder, and nobody
          asked where the far end came out:

              cylinder(h = 12, center = true) at x = 28.6  ->  x 22.60 to 34.60
              pad's outer face                                 x = 32.20
              cavity's inner wall face                         x = 26.20

          So the bore left the pad correctly at 32.20 and then kept going, out
          through the cavity face at 26.20 and 3.6 mm into the box. Two Ø2.5
          holes, one each side, at y = 0 and z = 11.0, from open air into a case
          whose entire design argument is that it is sealed. Confirmed by
          rendering the bore intersected with the cavity solid: not empty, and
          reaching x = +/-26.2.

          It could not be seen. The holes are hidden under the hood's skirt on
          the outside and behind the display on the inside, and the render is
          perfect from every angle.

          A pilot only needs to be a pilot. 5.0 mm inward from the pad face
          spans x 27.20 to 32.20 - the full 6.0 mm of material there less a
          1.0 mm blind floor, and an M3 self-tapper takes 5 mm of thread
          happily. Blind, like every other hole in this case.

          Written centred on its own midpoint so the two sides cannot drift
          apart, and 0.1 proud of the pad face so the mouth is a clean opening
          rather than a coplanar cut.
        */
        for (x = [-1, 1])
            translate([x * (body_w / 2 - hood_pilot_len / 2 + 0.05), 0, front_t + 8])
                rotate([0, 90, 0])
                    cylinder(h = hood_pilot_len + 0.1, d = screw_pilot_d, center = true);

        // cable bore
        translate([cable_x, -body_l / 2, cable_z]) teardrop_y(cable_bore_d, 40);
        /*
          ★ THE CHAMBER RUNS OUTBOARD, INTO THE BOSS. It used to run inboard
          from the cavity face - 5.9 of its 6.0 mm in open cavity air, removing
          nothing. A cable tie clamped on the cable inside this chamber cannot
          pass back out through the O4.5 mouth, so the pull goes into ASA
          instead of into the silicone's adhesion.
        */
        translate([cable_x, -(cav_l / 2) - cable_in, cable_z]) rotate([-90, 0, 0])
            cylinder(h = cable_in + 0.1, d = cable_chamber_d);

        // vent, on the same downward face as the cable so every penetration
        // points at the ground
        translate([0, vent_y, vent_z]) {
            /*
              *** 29 Aug 2026 - THIS DRILLED THROUGH BOTH WALLS. ***

              teardrop_x centres its extrusion, so a length of 200 ran from
              x = -100 to +100 and pierced the -x wall as well: a bare 6 mm
              hole straight into the electronics, with no membrane seat on
              that side and no way to see it from outside. The case was not
              sealed at all, and it rendered perfectly.

              45.2 +/- 20 spans x 25.2 to 65.2 - one millimetre of bite into
              the cavity, out through the +x wall, and nowhere near the other.
            */
            translate([cav_w / 2 + 19, 0, 0]) teardrop_x(vent_d, 40);
            /*
              ★★ THE MEMBRANE MOVED TO THE OUTSIDE FACE, 29 Aug 2026.

              It was recessed into the CAVITY side, and that is backwards for
              every load it sees. Rain at 300-460 Pa, a pressure-washer jet, and
              the 13.3 kPa thermal vacuum the vent exists for ALL push inward -
              so all three were trying to PEEL the patch off its land. A bonded
              patch in peel is a patch with a countdown on it.

              On the outside, every one of those loads presses it ONTO the land.
              The only load that lifts it is the case warming up and venting
              outward, which is a few hundred pascals and the direction ePTFE
              passes freely anyway.

              The recess also stops being a cup that collects Kochi road slurry
              on the inside where nobody can see it silting up.
            */
            translate([cav_w / 2 + wall - vent_seat_t, 0, 0]) rotate([0, 90, 0])
                cylinder(h = vent_seat_t + 0.1, d = vent_seat_d);
        }
    }

    // Display locating ribs. ★ These bear on the PCB OUTLINE (50.0 x 82.0,
    // verified) rather than on the four mounting holes, whose insets came from
    // the wrong board and were measured wrong even there. A rib cannot miss an
    // edge; a post can miss a hole by 2 mm and scrap the print.
    disp_ribs();

    /*
      ★ ADDED AFTER THE difference(), LIKE THE RIBS, AND THAT IS DELIBERATE.
      Inside the union these would be cut away by the cavity, which is the one
      subtraction that covers every millimetre they occupy. Outside it they are
      also immune to the screw, vent and cable cuts - so being outside is
      exactly why the clearance asserts up in DERIVED have to exist. Nothing
      else is checking, and a render will not tell you.
    */
    perf_ledges();

    /*
      ★ AND THESE TWO ARE CALLED, WHICH IS NOT AS OBVIOUS AS IT SOUNDS.

      disp_lip() was defined on 29 Aug 2026 and never called. The file rendered
      clean, every assert passed, and the part simply did not have the feature -
      it existed in the source and not in the geometry, which is this project's
      signature defect and the sixth recorded instance of it. An uncalled module
      is invisible to every check there is except looking for the call.
    */
    disp_lip();
    // vent_shroud() has MOVED into the union() above - see the note there.
}

/*
  ★ THE FAR-END LIP - what stops the display chattering, added 29 Aug 2026.

  The display is held sideways by disp_ribs() and forward by the bezel and the
  closed front. NOTHING held it backward once the perfboard moved onto ledges:
  the old load path ran lid foam -> ESP32 -> perfboard -> socket -> display, and
  the ledges interrupt it.

  ★ AND THE SOCKET IS NOT THE ANSWER, though a previous review thought it might
  be. Its 14 pins sit in a row at the header end; they resist rotation about an
  axis PARALLEL TO THEIR OWN ROW with essentially no stiffness. So against the
  far end lifting, the socket is not weak - it is not in the load path at all.

  What actually happens: hdr_gap 11.04 minus the 4.0 ribbon minus 1.5 of solder
  leaves 5.54 mm of clear air. The far end lifts into it and slams back at
  60-120 Hz. Chatter, not a single pull-out, is what kills the panel.

  This lip form-closes that end. The display goes in by sliding its far edge
  under the lip - the cavity gives 1.2 mm of y travel at each end, against the
  1.5 mm the lip needs - and then the header end drops. A 45 degree gusset above
  it keeps it self-supporting printing FRONT FACE DOWN, the same trick
  perf_ledges() uses.

  ★ IT IS A BACKSTOP, NOT THE RESTRAINT. The restraint is a closed-cell foam pad
  on the perfboard's display face at the far end - see HARDWARE.md. Sized: pad at
  y = +22 on a 60 mm arm against 7.9 N at y = 0 on a 38 mm arm needs 5.0 N;
  30 x 20 mm of EPDM at 20% compression gives 9-15 N. Margin 1.8-3.0x, and the
  lid's own foam beats the reaction by 5x so the perfboard stays on its ledges.

  ★★ THE ADHESIVE GOES ON THE PERFBOARD. Not the panel, not the body. A 40 rupee
  part carries the glue, so a cooked display costs a display - not the 180 g
  one-shot body it would otherwise be welded into.
*/
/*
  ★★ 2.1, NOT 1.5 - and the number never meant what its comment said.

  disp_lip_t is the lip's whole y thickness, and 1.2 of it merely spans
  inner_clear before it reaches the PCB at all. So 1.5 gave 0.30 mm of actual
  overlap, not 1.5. Measured: the lip runs y 40.70-42.20 against a PCB edge
  at 41.00.

  The ceiling is how far the display can slide to get under it: inner_clear is
  1.2 mm at each end, so 0.9 mm of overlap leaves 0.3 of insertion margin.
  Three times the grip, for 0.6 mm of plastic.
*/
disp_lip_t      = inner_clear + 0.9;   // 2.1 -> 0.9 mm of real overlap
/*
  ★★ THE LIP HAS TO STAND OFF THE PANEL, NOT REST ON IT.

  disp_lip_z0 was exactly front_t + bezel_t + disp_t - the PCB's back face,
  with nothing between them. The body prints front-down, so that underside is
  a 2.105 mm one-sided cantilever printed over air: 26 mm long, unsupported,
  49.2 mm2 of it. A 2 mm ledge bridges perfectly well in ASA, but it droops
  0.1-0.2 mm at the tip, and with zero clearance every bit of that droop lands
  on the display.

  The obvious fix - a 45 degree gusset underneath - cannot be used. The only
  space under the lip is inner_clear, and inner_clear is precisely the gap the
  panel slides through to get beneath the lip in the first place. Filling it
  would make the display uninstallable, which is a worse defect than the one
  it cures.

  So the lip stands off instead. 0.25 mm is more than the droop and far less
  than the panel can rattle, and it is still caught long before it could clear
  its seat.
*/
disp_lip_gap    = 0.25;                               // droop clearance
disp_lip_z0     = front_t + bezel_t + disp_t + disp_lip_gap;   //  9.75
disp_lip_z1     = disp_lip_z0 + 1.5;                  // 11.25
disp_lip_w      = 26.0;           // across the end wall, clear of the SD corner

// ★ what matters is the OVERLAP, not the lip's own thickness
disp_lip_overlap = disp_lip_t - inner_clear;
assert(disp_lip_overlap >= 0.8,
       "display lip barely touches the PCB - it will not stop the panel chattering");
assert(disp_lip_overlap <= inner_clear - 0.2,
       "display lip overhangs further than the panel can slide to clear it");
assert(disp_lip_gap >= 0.2 && disp_lip_gap <= 0.4,
       "display lip either rests on the panel or lets it rattle");
assert(disp_lip_z1 <= front_t + bezel_t + disp_t + 2.0,
       "display lip stands proud into the header gap");

module disp_lip() {
    // +y end only. The header, and the socket that must clear it, are at -y.
    translate([0, disp_pcb_l / 2 + inner_clear - disp_lip_t / 2, 0])
        hull() {
            translate([0, 0, disp_lip_z0]) cube([disp_lip_w, disp_lip_t, 0.01], center = true);
            translate([0, 0, disp_lip_z1]) cube([disp_lip_w, disp_lip_t, 0.01], center = true);
            // 45 degree gusset up to the wall, so it prints unsupported
            translate([0, disp_lip_t / 2, disp_lip_z1 + disp_lip_t])
                cube([disp_lip_w, 0.01, 0.01], center = true);
        }
}

/*
  ★ THE VENT SHROUD - a roof over the membrane, added 29 Aug 2026.

  With the patch on the outside it is exposed, and this wall faces sideways: a
  wheel-thrown stone or a jet-wash nozzle would take it off. A 3 mm lip above
  and to each side deflects both, while leaving the bottom fully open so water
  runs straight off and nothing can pool against the membrane.

  Printed FRONT FACE DOWN this is a horizontal ledge on a vertical wall, so its
  underside is a 45 degree gusset - the same trick perf_ledges() and disp_lip()
  use, and the reason it needs no support.
*/
/*
  ★★ 12.0, NOT 9.0. The shroud was capping the very membrane it protects.

  vent_shroud_r - vent_shroud_p was 9.0 - 3.0 = 6.00 - which is vent_seat_d/2
  EXACTLY. So the gusset's base landed on the edge of the O12 bonding land, and
  since the gusset is sunk 0.5 mm into the wall to merge, it sank into the
  recess. Measured: 28.2 mm3 inside the recess, 197.6 mm3 across the land's
  column, 0.10 mm off the wall face. The ePTFE patch could not have been fitted.

  12.0 gives a 9.0 mm gusset base, 3.0 mm clear of the land all round.
*/
vent_shroud_r  = vent_seat_d / 2 + 6.0;    // 12.0
vent_shroud_t  = 2.4;
vent_shroud_p  = 3.0;                      // how far it stands off the wall

module vent_shroud() {
    x0 = cav_w / 2 + wall;                 // the outer wall face
    translate([x0, vent_y, vent_z]) rotate([0, 90, 0]) {
        difference() {
            hull() {
                // the roof itself, standing off the wall
                translate([0, 0, vent_shroud_p - vent_shroud_t])
                    cylinder(h = vent_shroud_t, r = vent_shroud_r);
                // 45 degree gusset, reaching 0.5 INTO the wall - built flush
                // it merely touched, and CGAL reported the body as two solids
                translate([0, 0, -0.5])
                    cylinder(h = 0.01, r = vent_shroud_r - vent_shroud_p);
            }
            // open the BOTTOM half so water cannot pool against the patch
            translate([-vent_shroud_r - 1, -vent_shroud_r - 1, -1])
                cube([2 * vent_shroud_r + 2, vent_shroud_r + 1, vent_shroud_p + 2]);
            /*
              ★★ AND OPEN THE MIDDLE, OR THE MEMBRANE CANNOT BE FITTED.

              hull() does not build a roof on a gusset - it fills the standoff
              solid. Measured: 119.98 mm3 of ASA sitting over the outer half of
              the O12 bonding land, with the land floor at x 28.000 and the
              shroud's underside at x 28.700. Nobody is laying a 12 mm adhesive
              patch into a 0.7 mm gap. The vent bore itself was clear, so every
              airflow check passed while the part stayed unbuildable - the third
              time this shroud has collided with its own land.

              Cutting the bore through turns the puck into a C-shaped collar:
              the land is completely open from the front, the rim still stands
              3 mm proud to take a knock and deflect water running down the
              wall, and the bottom stays open so nothing pools. What it gives
              up is head-on cover, which the membrane does not need - ePTFE is
              rated in kilopascals and driven rain at 100 km/h is 463 Pa.
            */
            translate([0, 0, -1])
                cylinder(h = vent_shroud_p + 2, d = vent_seat_d + 1.0);
        }
    }
}

module disp_ribs() {
    rz = front_t + bezel_t;                     // ribs start behind the bezel
    rh = disp_t + 2.0;
    // ★ Pocket sized on the WIDEST part - the proud frame, not the PCB.
    px = disp_widest / 2 + 0.3;
    py = disp_pcb_l / 2 + 0.3;                  // ends: frame is flush there
    for (s = [-1, 1]) {
        for (y = rib_side_y)
            translate([s * (px + 1.0), y, rz]) rib(rib_w, rib_l, rh);
        for (x = rib_end_x)
            translate([x, s * (py + 1.0), rz]) rotate([0, 0, 90]) rib(rib_w, rib_l, rh);
    }
}

/*
  The retention ledge, as ONE cross-section in the x-z plane swept along y.

  Drawn from the chamfer's toe at the cavity wall, in over the 45 degree ramp
  to the shelf's inner edge, out along the bearing face to the lip, up the lip
  and back into the wall. A shelf whose underside is the ramp cannot be built
  from a shelf plus a chamfer without their meeting plane showing up as a seam
  in the render and a shear line in the print; one closed profile has neither.

  lip_x == ledge_in_x collapses the bearing-face segment to zero length, which
  is what turns the same profile into a stop tab - full projection, full
  height, so it catches the board's corner over the same 1.0 mm the shelf does.
*/
module ledge_profile(lip_x) {
    x_out = cav_w / 2 + ledge_bury;
    polygon(concat(
        [[cav_w / 2,  ledge_z - ledge_cham],
         [ledge_in_x, ledge_z]],
        lip_x > ledge_in_x ? [[lip_x, ledge_z]] : [],
        [[lip_x, ledge_z + ledge_lip_h],
         [x_out, ledge_z + ledge_lip_h],
         [x_out, ledge_z - ledge_cham]]));
}

// Swept from y0 to y1. linear_extrude runs in +z, so the profile is drawn in
// x-z and laid down by the same rotate the teardrops use.
module ledge_run(lip_x, y0, y1) {
    translate([0, y1, 0]) rotate([90, 0, 0])
        linear_extrude(y1 - y0) ledge_profile(lip_x);
}

module ledge_side() {
    ledge_run(ledge_lip_x, ledge_y0, ledge_y1);
    ledge_run(ledge_in_x,  ledge_stop_y, ledge_stop_y + ledge_stop_l);
}

module perf_ledges() {
    ledge_side();
    mirror([1, 0, 0]) ledge_side();
}

// A rib with a 45 degree lead-in on its back edge, so the module drops in
// rather than having to be threaded past a square shoulder.
module rib(w, l, h) {
    hull() {
        translate([0, 0, 0]) cube([w, l, 0.01], center = true);
        translate([0, 0, h - 1.5]) cube([w, l, 0.01], center = true);
        translate([0, 0, h]) cube([w * 0.2, l, 0.01], center = true);
    }
}

// ============================================================ LID

/*
  A plain plate. No window, no hood, nothing to line up - which is the entire
  point of turning the case round.
*/
module lid() {
    difference() {
        union() {
            rrect(body_w, body_l, lid_t, corner_r_out);
            // Rim ring. Its inner 1.0 mm drops into the cavity mouth as a
            // SPIGOT: water reaching the perimeter must cross the outer joint,
            // then 4 mm of compressed foam, then a 0.2 x 2.5 mm annular gap.
            // No straight-line path in, and the spigot costs zero envelope
            // because it uses cavity space nothing occupies at the lid plane.
            /*
              *** 29 Aug 2026 - THE LID COULD NOT CLOSE. ***

              The outer rrect was cav_w + 2*wall, which is the SHELL's outer
              size (57.2 x 89.2, half-width 28.6) - not the cavity's inner size.
              The ring came out 3.6 mm wide spanning x 25.0 to 28.6, while the
              cavity mouth ends at 26.2. So 2.4 mm of it stood ON the body's
              sealing land and the lid sat 2.5 mm proud all the way round.
              Zero seal contact, and tightening eight M3s would have bowed and
              cracked a 100 g plate over a rigid interference.

              The comment below was right the whole time - "its inner 1.0 mm
              drops into the cavity mouth". The geometry was building something
              else. Sized off the cavity now, so it is a 1.0 mm ring at
              x 25.0-26.0 with 0.2 mm of clearance per side.
            */
            translate([0, 0, lid_t]) difference() {
                rrect(cav_w - 2 * spigot_clear, cav_l - 2 * spigot_clear,
                      spigot_h, max(0.5, corner_r - wall));
                translate([0, 0, -0.5])
                    rrect(cav_w - 2 * spigot_clear - 2.0,
                          cav_l - 2 * spigot_clear - 2.0,
                          spigot_h + 1, max(0.5, corner_r - wall));
            }
        }
        /*
          *** 29 Aug 2026 - THERE WAS NO FOAM CHANNEL. ***

          lid_t + spigot_h - foam_d = 5.5, but the plate's rim face is at 5.0.
          The cut started half a millimetre ABOVE the surface it was supposed
          to groove, so it removed nothing from the plate and only nicked the
          outer root of the spigot. The 3 mm EPDM tape had no gland, no 33%
          compression stop, and the "land-on-land hard stop" this file claims
          elsewhere did not exist - the screws would simply have crushed the
          tape to permanent set with nothing setting the closed gap.

          From the rim face DOWN: z 3.0 to 5.0, 2.0 mm deep. 3 mm tape closes
          to 2 mm = 33%, which is the number the seal section is written around.
        */
        translate([0, 0, lid_t - foam_d]) difference() {
            rrect(2 * band_x + foam_w, 2 * band_y + foam_w, foam_d + 1, corner_r_out - 1);
            translate([0, 0, -0.5])
                rrect(2 * band_x - foam_w, 2 * band_y - foam_w, foam_d + 2,
                      max(0.5, corner_r_out - 1 - foam_w));
        }
        // screw clearance
        for (p = screw_pts)
            translate([p[0], p[1], -0.1])
                cylinder(h = lid_t + spigot_h + 1, d = screw_clear_d);
        /*
          ==================================================================
          ★★ DELETED 29 Aug 2026 - the keying recess and its four pilots.
          ==================================================================

          Both existed to locate and bolt mount_plate() onto this face. The
          mount no longer bolts to the lid at all: mount_v4.scad's cap wraps
          the case and grips the body's own flange band, so the mount load
          never passes through the sealing screws. That was the point of the
          change - the sealing land is exactly 6.000 mm wide, the gasket takes
          4.0 of it, and neither an insert (7.2) nor a nut pocket (6.5) will
          EVER fit there. Those eight threads can never be upgraded, so they
          must not carry structural load.

          Three things this recovers, and the first is the reason to be glad:

            - THE LID GETS ITS SOLID FIRST LAYER BACK. The recess made the
              first five layers a 4 mm picture frame around a 56.4 x 88.4
              bridge, on a 64 x 96 ASA part. The file claimed a "solid
              64 x 100 first layer" throughout and a probe found it false.
              Now the claim is true.
            - Four blind pilots disappear from the outside of a sealed case,
              each with 1.00 mm of ASA between its floor and the cavity.
            - The whole M3x12-bottoms-out problem documented at length here
              disappears with the joint that caused it.

          The eight sealing screws now run CAP -> LID -> BODY as one fastener
          set, and get 2.4 mm longer. See mount_v4.scad's cap_screw_pts - and
          those eight positions are now CHECKED against screw_pts below rather
          than merely asserted to match, since they live in two separate files.
        */
    }
}

// ============================================================ BEZEL

/*
  ★ THE ONLY PART THAT READS THE UNVERIFIED NUMBERS.

  5 g, about eight minutes. Print it first, offer it to the lit display, and
  check the aperture before anything expensive goes on the bed. If the offset
  turns out wrong you reprint this, not the body.

  Matte black. It sits 3 mm behind the front face and forms a small hood of its
  own around the glass. The aperture is the active area plus 2 mm all round:
  overshoot lands on the panel's own black border (2.90 mm at the narrowest),
  never on bare PCB, so it buys +/-2 mm of measurement error.
*/
module bezel() {
    difference() {
        rrect(cav_w - 0.4, cav_l - 0.4, bezel_t, corner_r - wall);
        translate([0, disp_active_off, -0.5])
            rrect(disp_active_w + 4.0, disp_active_l + 4.0, bezel_t + 1, 1.5);
    }
}

// ============================================================ HOOD

/*
  Separate part, bolted to the two side pads. Matte black - the one place
  colour does real work. Per HARDWARE.md this is the largest single readability
  gain available, worth more than any backlight change.

  ★ SHEARED, NOT ROTATED. Rotating the tube about its base lifts one side of
  the base off the plane - the far wall's bottom edge rose 6.7 mm and the flat
  cut only removed material below z=0, leaving an open slot the width of the
  hood right beside the aperture. At road speed that is a forward-facing scoop.
  A shear leans the walls and leaves the base flat and fully seated.
*/
hood_shear = [[1, 0, 0, 0], [0, 1, -tan(hood_rake), 0], [0, 0, 1, 0], [0, 0, 0, 1]];

/*
  ============================================================================
  ★ THIS PART PRINTED AS TWO LOOSE OBJECTS AND COULD NOT BE FITTED TO THE CASE.

  Nobody had rendered it against the body. Three defects, all found by probe,
  none visible in a render of the hood on its own:

  1. THE TUBE WAS NOT ATTACHED TO THE SKIRT. CGAL reported Volumes: 3 for one
     part - one outer volume and TWO solids. The skirt's mouth has to clear the
     body's shell, so its hole is cav_w + 2*wall + 0.4 = 57.6 wide; the tube's
     OUTER wall is ow = 53.2. They are 2.2 mm apart in x and 5.2 in y and they
     never touch at any z. It slices as a ring and a tube, and the render is
     a perfect hood from every angle.

     Joined by a FUNNEL: outer body_w -> ow, inner the skirt's hole -> the
     tube's bore, over hood_funnel. Both surfaces close inward going away from
     the mouth, so printed mouth-down every layer sits on a larger one. The
     inner run is (89.6 - 76.0)/2 = 6.8, so hood_funnel must be at least that
     for 45 degrees - the assert holds it. The tube now stands on the funnel,
     which makes the part hood_funnel longer overall; hood_depth is untouched.

  2. THE SCREW HOLES MISSED THE PADS BY 5.0 mm. The holes were at hood z = 8,
     and the hood mounts translate([0,0,14]) rotate([180,0,0]), so they landed
     at body z = 14 - 8 = 6.0. The pads' pilots are at body z = 11.0. Two sets
     of literals in two modules, 5 mm apart, and neither module can see the
     other. Both now read hood_pad_z, so the hole is at hood z = 14 - 11 = 3.0
     by construction and cannot drift again.

  3. ★ AND EVEN THEN IT WOULD NOT GO ON - THE PADS FOUL THE SKIRT.
     This one is not in the brief; it turned up when the placed hood was
     intersected with the body: 188.9 mm3 of solid overlap at the pads and a
     further 124.9 mm3 at the CABLE BOSS. Both are unavoidable in principle:

         skirt's inner face   cav_w/2 + wall + 0.2  =  28.8
         pad's outer face     body_w/2              =  32.2   3.4 mm inside it
         cable boss           4.0 mm proud of the body's end face

     and the pads reach body_w on purpose - that is the "cost no envelope"
     note in body(). A skirt whose outside is also body_w cannot both clear
     them and have anything left for a screw to bear on. So the hood carries
     a local BOSS at each pad: a pocket over the pad and hood_boss_wall of
     material outboard of it, taking the hood 2.1 mm wider than the case at
     two spots. It is a bolt-on shade; 2.1 mm is not an envelope.

     The pockets and the cable notch are open at the skirt's mouth, so the
     hood still slides straight on.

  hood_depth and hood_rake are untouched. hood_rake is still a placeholder.
  ============================================================================
*/
module hood() {
    ow = hood_ow; ol = hood_ol;                  // local aliases only - every
    hole_w = hood_hole_w; hole_l = hood_hole_l;  // one of these is defined in
    boss_d = hood_boss_d;                        // DERIVED and asserted there
    pocket_h = hood_pocket_h;
    screw_z  = hood_screw_z;

    difference() {
        union() {
            // skirt blank - the body's front is cut out of it below
            rrect(body_w, body_l, hood_skirt_h, corner_r_out);
            // local bosses over the body's pads
            for (x = [-1, 1])
                translate([x * (cav_w / 2 + wall), 0, 0])
                    cylinder(h = pocket_h + 1.2, d = boss_d);
            // funnel joining the skirt's mouth to the tube, sheared with the
            // tube so the two bores are one continuous surface
            translate([0, 0, hood_skirt_h]) multmatrix(hood_shear) difference() {
                hull() {
                    rrect(body_w, body_l, 0.01, corner_r_out);
                    translate([0, 0, hood_funnel]) rrect(ow, ol, 0.01, 2.5);
                }
                hull() {
                    translate([0, 0, -0.02]) rrect(hole_w, hole_l, 0.01, corner_r);
                    translate([0, 0, hood_funnel + 0.02])
                        rrect(ow - 2 * hood_wall, ol - 2 * hood_wall, 0.01, 1.5);
                }
            }
            // the shade itself, standing on the funnel
            translate([0, 0, hood_skirt_h]) multmatrix(hood_shear)
                translate([0, 0, hood_funnel]) difference() {
                    rrect(ow, ol, hood_depth, 2.5);
                    translate([0, 0, -1]) rrect(ow - 2 * hood_wall, ol - 2 * hood_wall,
                                                hood_depth + 2, 1.5);
                }
            for (i = [1 : hood_ribs])
                translate([0, 0, hood_skirt_h]) multmatrix(hood_shear)
                    translate([0, 0, hood_funnel + i * hood_depth / (hood_ribs + 1)])
                        hood_rib(ow, ol);
        }
        // The body's front, with 0.2 mm of slop. Cut in the OUTER difference
        // so it trims the bosses too - inside the skirt they would foul the
        // shell. Stops at the skirt's top so the funnel is untouched.
        translate([0, 0, -0.5]) rrect(hole_w, hole_l, hood_skirt_h + 0.5, corner_r);
        // pockets for the body's pads, open at the mouth so it slides on
        for (x = [-1, 1])
            translate([x * (cav_w / 2 + wall), 0, -1])
                cylinder(h = pocket_h + 1, d = hood_pad_d + hood_pad_clear);
        /*
          ★★ THE VENT WINDOW - because the hood could not go on at all.

          Measured 224.4 mm3 of interference with the vent shroud, 2.80 mm deep
          over the skirt's full height: 56% of the shroud sat inside the hood.

          And the vent has no legal z anywhere on this case. The perfboard ledge
          forces vent_z below 12.34; the hood skirt forces it above 20; and the
          45 degree flange flare caps it near 19.9 on EVERY wall - so moving the
          vent to another face does not help. vent_seat_d cannot rescue it
          either: the two constraints are jointly satisfiable only below O4.34
          against a O6.0 bore.

          So the HOOD gives way, locally. A window through its skirt costs a
          slot in a sacrificial 8 g reprintable part and keeps every other
          number in this file - vent_z, the ledge, the wall, all untouched.

          Body +x is hood +x, but body -y is hood +y, so the window sits at
          -vent_y. Open to the mouth, so it cannot trap water.
        */
        translate([cav_w / 2 + wall - 1.0, -vent_y - (vent_shroud_r + 1.5), -1])
            cube([12.0, 2 * (vent_shroud_r + 1.5), hood_skirt_h + 2]);

        // notch for the cable boss, also open at the mouth. Body -y is hood +y.
        translate([cable_x, body_l / 2, hood_skirt_h - cable_z])
            rotate([90, 0, 0]) cylinder(h = 40, d = cable_boss_d + 1.0, center = true);
        // screw clearance, at the pads' real height
        for (x = [-1, 1])
            translate([x * (cav_w / 2 + wall), 0, screw_z])
                rotate([0, 90, 0]) cylinder(h = 40, d = screw_clear_d, center = true);
    }
}

/*
  ★ THE SUBTRACTION MUST RUN PAST THE TOP OF THE RIB. A first attempt gave the
  inner profile a height of 0.01, so the cut ended below the rib's top face and
  every rib printed as a SOLID SLAB across the full bore - five of them, like
  louvres, blocking the hood completely. It looked perfect from outside; a
  section render caught it.

  The rib also stops OUTSIDE the aperture. Reaching inward past it masked
  4.4 px of live picture on every edge, and display.cpp paints flush to the
  panel edge - so that was content, not margin.
*/
module hood_rib(ow, ol) {
    rib_h = 2.6; rib_in = 1.8;
    difference() {
        rrect(ow - 2 * hood_wall + 0.2, ol - 2 * hood_wall + 0.2, rib_h, 1.5);
        translate([0, 0, -0.01]) hull() {
            rrect(ow - 2 * hood_wall + 0.2, ol - 2 * hood_wall + 0.2, 0.01, 1.5);
            translate([0, 0, rib_in])
                rrect(48.0 + 1.6, 74.0 + 1.6, rib_h - rib_in + 0.2, 1.0);
        }
    }
}

// ============================================================ MOUNT PLATE

/*
  Separate so the lid prints outer-face-down on a solid 64 x 100 first layer,
  and so the mount can change later without touching the sealed case.
*/
/*
  ★ 8.0, NOT 6.0. At 6.0 the dovetail slot cut CLEAN THROUGH the plate: the
  slot floor computed to z 0.70 against a plate underside at z 1.00, so there
  was -0.30 mm of material under it. The part rendered as a plausible-looking
  plate with a slot in it and would have printed as a plate with a hole in it.
  8.0 leaves 2.71 mm of floor - the 1.70 written here was measured to the wrong
  end of the offset profile, and the render says 3.71 for the floor against a
  1.00 underside. The floor is not the load path anyway, the dovetail flanks
  are - but 2.71 is the number every counterbore below has to live inside, so
  it had to be right.
*/

/*
  ★ THE SLOT MUST RUN OUT TO AN EDGE - the third time this has bitten.

  Cut at its own length, dovetail_female() is a closed rectangular pocket in
  the middle of the plate: correct profile, and nothing can ever slide into it.
  It caught me on the old case's receiver, again on the first back-plate, and
  again here. The profile looks right in every render, which is exactly why it
  keeps surviving inspection.

  Open at the TOP of the case, closed at the bottom, so the device drops down
  onto the mount and gravity seats it against the stop rather than being the
  force trying to pull it off.
*/

/*
  ★ THE SLOT'S OWN NUMBERS, DERIVED RATHER THAN READ OFF A RENDER.

  Everything below this line - both counterbores, the plate's floor, whether a
  screw head fits under the slot - is measured against the female slot, and the
  female is dt_profile() grown by offset(dt_clear). offset() moves each edge
  along its own normal, so the widest half-width is NOT dt_top/2 + dt_clear:

      run per rise on the flank      m  = (dt_top - dt_base) / (2 * dt_h) = 0.7
      the top edge rises by                dt_clear            -> +m*dt_clear
      the flank moves out along its normal -> dt_clear*sqrt(1+m^2)
      half-width  = dt_top/2 + dt_clear*(m + sqrt(1+m^2))      = 11.576

  and the slot is cut from the outer face DOWNWARD, so its floor - the deepest
  point, which is also where it is widest - is dt_h + dt_clear below that face.
  Both confirmed against the rendered slot: x +/-11.5762, z 3.7100 to 9.3100.
*/

// The four screws that hold the plate to the lid. Named because lid() drills
// the pilots and mount_plate() drills the clearance holes, and two hard-coded
// 18/34 pairs in two modules is the drift this file keeps getting caught by.

/*
  ============================================================================
  ★ THE COUNTERBORES. screw_head_d EXISTED AND NOTHING WAS CUT FOR IT.

  ---------------------------------------------------------------------------
  1. THE PLATE'S OWN FOUR HEADS, on the plate's OUTER face at z = 9.0.

  That face is not a free surface. It is the face the BM4 adapter beds against,
  and the only gap between them is the dovetail's own clearance - 0.29 mm at
  the top of the male. A 2.4 mm head against 0.29 mm of clearance means the
  case stops 2.1 mm before it seats, every time, and it feels like the dovetail
  is too tight rather than like four screws are in the way.

  Counterbored 3.5 mm deep. The depth is NOT just "enough to swallow a head":

      swallows an M3 pan head            2.4       1.1 mm to spare
      swallows a DIN 912 socket cap      3.0       0.5 mm to spare
      leaves under it   8.0 - 3.5    =   4.5 mm    of plate
      and it removes 3.5 mm of GRIP, which is where the thread comes from

  That last line is the real reason for 3.5 rather than 3.0 - see the screw
  length sum below. Sideways it has to miss the slot: 18.0 - 3.4 = 14.6 against
  a slot half-width of 11.576, so 3.02 mm, and the plate edge is 10.8 mm away
  on the other side.

  ---------------------------------------------------------------------------
  2. THE LID'S EIGHT HEADS, and why they are NOT counterbored in the lid.

  This was the obvious fix and it does not exist. Both ways of cutting it into
  the lid are blocked, and by margins that are not arguable:

      DOWNWARD  the heads sit on the lid's outer face at z = 0, and the FOAM
                CHANNEL is cut into the other face from z = 3.0 to 5.0 - and
                every one of the eight screws is deliberately inside the foam
                band. So there is 3.0 mm of web, and a 2.4 mm head needs 2.6.
                0.4 mm of ASA over the gasket gland, under a screw head. It
                would crack on the first assembly and the seal would then be
                bearing the screw.

      SIDEWAYS  band_x is 29.0 and the lid's edge is at 32.2, so 3.2 mm - and
                at the four corner screws the rounded corner (centre 24.6,40.6,
                r 7.6) leaves only 7.6 - |(29.0,42.5)-(24.6,40.6)| = 2.807 mm.
                A 6.0 head is 3.0 mm of radius. It breaks OUT of the lid's edge
                by 0.19 mm before any clearance is added.

  Which is worth saying plainly: an M3 head does not fit inside this lid
  anywhere on the screw ring. The head is as wide as the land it stands on.

  So the relief goes in the MOUNT PLATE's underside instead - eight pockets,
  3.0 mm deep over 2.4 mm heads, leaving 5.0 mm of plate. The plate is the
  cheap, reprintable, non-sealing part; the lid is neither. Two consequences,
  both deliberate:

      - at the four corners and the mid-side screws the pocket opens onto the
        plate's own edge (2.807 mm of edge against a 3.4 mm radius), so the
        skirt is scalloped. It costs nothing and it drains.

      - ★ AT (0, +45) THE POCKET BREAKS THROUGH INTO THE DOVETAIL SLOT, and it
        is meant to. That screw is the only one of the eight that lands under
        the slot's run, and there are just 2.71 mm of floor over it - a 3.0 mm
        pocket leaves 0.29. A 0.29 mm film is not a floor, it is a thing that
        renders and does not print, which is the exact failure this file exists
        to stop. So it is opened: a clean 6.8 hole in the slot floor.

        That is only safe because the head TOP lands at 1.0 + 2.4 = 3.40, and
        the slot floor is at 3.71 - the head stays 0.31 mm below the slot and
        never enters it. The adapter's male never touches the floor either
        (0.29 mm clear) and when seated it only reaches y = +25, well short of
        +45. The assert below is what holds that 0.31, and it is why
        screw_head_h must not quietly become 3.0 for a box of socket caps.

  ---------------------------------------------------------------------------
  3. AND NO, MOVING THE +34 PAIR IS NOT THE BETTER ANSWER.

  The review suggested taking the plate's +y screw pair from y = +34 to y = -34
  "behind the seated adapter" instead of counterboring. Two findings against it:

      - it is aimed at the wrong screws. Seated, the adapter's 56 x 46 plate
        covers case-plate y = -21 to +25, so NEITHER pair is under it. What
        actually fouls is the INSERTION sweep: the adapter enters at the open
        end and its plate sweeps every y from +48.2 down to +25, which is the
        +34 pair and not the -34 pair. The -34 pair clears by 13 mm at rest and
        is never swept. So the +34 pair is the only one with a problem.

      - and y = -34 is already taken, by the pair that is fine. Putting all
        four on one line 34 mm off centre leaves the plate cantilevered ~62 mm
        over the end that carries the dovetail load, hanging on nothing.

  Counterbore. All four, not just the +34 pair: the feature costs 4.5 mm of a
  9 mm plate, it keeps the part symmetric, and an asymmetric pair of screws
  that must not be swapped is a defect waiting for a rebuild.
  ============================================================================
*/

/*
  ★ AND THE SCREW LENGTH, WHICH IS THE WHOLE POINT OF THE COUNTERBORE.

      head bears on the counterbore floor at  8.0 - 3.5     = 4.5 into the plate
      plate below that, plus the keying spigot  4.5 + 1.0   = 5.5   GRIP
      M3 x 8, so thread in the lid              8.0 - 5.5   = 2.5   ENGAGEMENT
      lid pilot, recess floor to blind end      4.0 - 1.0   = 3.0
      spare before it bottoms                   3.0 - 2.5   = 0.5

  An M3 x 12 - which is what the header recommends, and it is right for the
  eight SEALING screws, where the grip is 5.0 of lid against a 9.0 pilot in the
  body - is wrong here. It would want 12.0 - 5.5 = 6.5 mm of thread, and this
  lid cannot offer it: 5.0 thick, the hole starts 1.0 down in the keying
  recess, and 1.0 has to stay under it because a through hole here opens the
  sealed case. 3.0 is all there will ever be.
*/

// Counterbores for the plate's OWN four heads, sunk from the outer face - the
// face the adapter beds on. Cut 0.1 proud of that face so there is no coplanar
// lid to argue with.
// ============================================================ LAYOUT

part = "all";   // "all" "body" "lid" "bezel" "hood"

if      (part == "body")       body();
else if (part == "lid")        lid();
else if (part == "bezel")      bezel();
else if (part == "hood")       hood();
else {
    body();
    translate([body_w + 12, 0, 0]) lid();
    translate([-(body_w + 12), 0, 0]) bezel();
    translate([0, body_l + 14, 0]) hood();
}

/*
  ★ PRINT ORDER

  1. bezel  - 5 g. Offer it to the lit display and check the aperture registers
              before anything expensive is committed.
  2. mount_v4.scad part="coupon" - proves the bayonet fit before the
              real parts are committed.
  3. lid, hood, then mount_v4.scad part="adapter" and part="cap".
  4. body   - the long print, and the last one, once everything else has proved
              its numbers.
*/
