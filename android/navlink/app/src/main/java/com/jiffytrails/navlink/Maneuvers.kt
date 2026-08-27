package com.jiffytrails.navlink

import android.content.Context
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.drawable.Icon
import android.util.Log
import java.util.Locale

/**
 * Notification icon -> [Mv] code.
 *
 * Three tiers, cheapest and most durable first. Every tier may return UNKNOWN;
 * none of them is allowed to guess. BLE_PROTOCOL.md: "An unrecognised icon hash
 * maps to 0x00 UNKNOWN and renders as a question mark. Never guess - a
 * confidently wrong arrow is worse than no arrow."
 *
 *  1. **Resource entry name.** Locale-independent and survives Google redrawing
 *     the artwork (PRIOR_ART.md, Kiroha/byd-dashcast). NAV_DATA.md says the
 *     maneuver arrives as `chipIcon` with `type=1`, which has no name - so this
 *     tier is expected to miss today. It costs one reflective call and it is the
 *     tier that keeps working across a Maps update, so it stays first.
 *  2. **Exact pixel hash**, rendered 32x32 and hashed on the alpha channel, byte
 *     for byte the same arithmetic NavDumpService uses. That is what makes the
 *     measured table in NAV_DATA.md ("zero collisions across five rides")
 *     directly usable here.
 *  3. **Fuzzy bitmap match** - each row of the thresholded 32x32 bitmap packed
 *     into one Int, matched by XOR + [Integer.bitCount], best match under
 *     [MAX_DIFF_BITS] wins. Gadgetbridge's approach, recorded in PRIOR_ART.md as
 *     an improvement on exact hashing, which is brittle across DPI, theme and
 *     Maps versions: one antialiased edge pixel changes the scalar hash
 *     completely but moves the bitmap by one bit.
 *
 * Anything unmatched is logged **as ASCII art** in a form that pastes straight
 * into [SEEDED], so a new maneuver costs a table edit rather than a debugging
 * session with the bike on the centre stand.
 */
object Maneuvers {

    private const val TAG = "NAVLINK"

    /** NavDumpService renders at 32; the NAV_DATA.md hashes were measured there. */
    private const val N = 32
    private const val RAMP = " .:-=+*#%@"

    /**
     * A pixel counts as ink above this alpha. 28 is not arbitrary - NavDump's art
     * picks `RAMP[a * 9 / 255]`, so a blank cell is exactly `a <= 28`. Using the
     * same cut means art pasted out of a log describes the same bitmap the live
     * path computes, which is the whole point of logging it.
     */
    private const val ALPHA_ON = 28

    /** Gadgetbridge accepts under 32 differing bits; here that is 32 of 1024. */
    private const val MAX_DIFF_BITS = 32

    /**
     * If the runner-up (a *different* maneuver) is within this many bits of the
     * winner, the two glyphs are too close to call and we return UNKNOWN. Left
     * and right arrows are mirror images: a near-tie between them is exactly the
     * junction failure this project refuses to ship.
     */
    private const val AMBIGUOUS_WITHIN = 8

    /** Runtime-learned signatures are bounded; a stuck classifier must not leak. */
    private const val LEARN_CAP = 64

    private const val TYPE_BITMAP = 1
    private const val TYPE_RESOURCE = 2

    /** [code] plus how it was reached, for one log line per maneuver change. */
    data class Match(val code: Int, val via: String) {
        val known: Boolean get() = code != Mv.UNKNOWN
    }

    private val UNMATCHED = Match(Mv.UNKNOWN, "no-match")

    // ---------------------------------------------------------------- tier 1

    /**
     * Substring table, **most specific first** - the scan takes the first hit, so
     * `merge_left` must be tested before `left` or it classifies as a turn.
     * Pattern from byd-dashcast's ordered TEXT_KEYWORD_MAP (PRIOR_ART.md).
     */
    private val BY_NAME: List<Pair<String, Int>> = listOf(
        "u_turn_left" to Mv.UTURN_LEFT,
        "uturn_left" to Mv.UTURN_LEFT,
        "u_turn_right" to Mv.UTURN_RIGHT,
        "uturn_right" to Mv.UTURN_RIGHT,
        // Bare "u-turn" with no handedness: India is left-hand traffic, so a
        // U-turn crosses to the right. Both codes mean "reverse direction" - the
        // loop direction is the only thing at stake, not the maneuver.
        "u_turn" to Mv.UTURN_RIGHT,
        "uturn" to Mv.UTURN_RIGHT,
        "roundabout" to Mv.ROUNDABOUT,
        "rotary" to Mv.ROUNDABOUT,
        "sharp_left" to Mv.SHARP_LEFT,
        "sharp_right" to Mv.SHARP_RIGHT,
        "slight_left" to Mv.SLIGHT_LEFT,
        "slight_right" to Mv.SLIGHT_RIGHT,
        "keep_left" to Mv.KEEP_LEFT,
        "keep_right" to Mv.KEEP_RIGHT,
        "fork_left" to Mv.FORK_LEFT,
        "fork_right" to Mv.FORK_RIGHT,
        "ramp_left" to Mv.EXIT_LEFT,
        "ramp_right" to Mv.EXIT_RIGHT,
        "exit_left" to Mv.EXIT_LEFT,
        "exit_right" to Mv.EXIT_RIGHT,
        // Handedness unknown; MERGE is one code either way.
        "merge" to Mv.MERGE,
        "ferry" to Mv.FERRY,
        "flyover" to Mv.FLYOVER,
        "underpass" to Mv.UNDERPASS,
        "destination" to Mv.DESTINATION,
        "arrive" to Mv.DESTINATION,
        "flag" to Mv.DESTINATION,
        "depart" to Mv.CONTINUE,
        "straight" to Mv.CONTINUE,
        "continue" to Mv.CONTINUE,
        "left" to Mv.TURN_LEFT,
        "right" to Mv.TURN_RIGHT,
    )

    /**
     * Icons that are known **not** to be maneuvers. Matching these silences the
     * unrecognised-icon art dump, which would otherwise fire once a second in
     * every non-navigating state. Names and the logo hash are from NAV_DATA.md.
     */
    private val IGNORED_NAMES = setOf("nav_notification_icon", "gs_progress")
    private val IGNORED_HASHES = setOf("83534611")

    // ---------------------------------------------------------------- tier 2

    /**
     * Measured `chipIcon` hashes, NAV_DATA.md "Maneuver icon hash table". The
     * `largeIcon` column is deliberately not mirrored here - same information,
     * double the maintenance (NAV_DATA.md, "What to stop extracting").
     *
     * These are only valid for this rendering method. Change [N], [render]'s
     * arithmetic or the drawable bounds and every one of them is wrong.
     */
    private val BY_HASH: Map<String, Int> = mapOf(
        "c2a2c91" to Mv.CONTINUE,          // CONTINUE / depart, 5 rides
        "d0883793" to Mv.TURN_LEFT,        // 5 rides
        "93f8340f" to Mv.TURN_RIGHT,       // 5 rides
        "d5fc816e" to Mv.SLIGHT_RIGHT,     // 4 rides
        "7df5b514" to Mv.SLIGHT_LEFT,      // 1 ride
        "39a0a4e2" to Mv.UTURN_RIGHT,      // table says "U-TURN"; see BY_NAME note
        "57dfa08f" to Mv.MERGE,            // MERGE / JOIN, 2 rides
        // Roundabout glyphs are exit-specific (NAV_DATA.md: "Roundabout icons
        // vary by exit"). This one was captured on a 3rd-exit roundabout, so the
        // hash carries the exit number. `title` overrides it when it has one -
        // see [refineRoundabout].
        "26582277" to Mv.roundaboutExit(3),
        "77f6aaf" to Mv.ROUNDABOUT,        // straight through, no exit number
        "23c3f60f" to Mv.DESTINATION,      // flag
    )

    // ---------------------------------------------------------------- tier 3

    private class Sig(val code: Int, val label: String, val rows: IntArray)

    /**
     * Fuzzy reference bitmaps.
     *
     * **Empty on purpose.** NAV_DATA.md publishes scalar hashes, not bitmaps, and
     * inventing arrow art to fill this table would be guessing at the one thing
     * this parser is not allowed to guess at. It fills two ways:
     *
     *  - at runtime, from every icon tier 1 or tier 2 identifies positively, so a
     *    maneuver seen once this ride survives an antialiasing or theme change
     *    that breaks its exact hash later in the same ride;
     *  - permanently, by pasting the art this class logs for an unrecognised icon
     *    straight in here as `art(Mv.X, "label", "....", ...)`.
     */
    private val SEEDED: List<Sig> = listOf(
        // art(Mv.KEEP_LEFT, "keep-left",
        //     "                                ",
        //     ... 32 rows of 32 chars, blank = transparent ...
        // ),
    )

    private val refs = ArrayList<Sig>(LEARN_CAP).apply { addAll(SEEDED) }
    private val loggedArt = HashSet<String>()

    // ------------------------------------------------------------------ api

    /**
     * Classify [icon]. [title] is only consulted to recover a roundabout exit
     * number (NAV_DATA.md: the exit number is also present in `title`); it never
     * decides *which* maneuver, because text is locale-locked and ManDrake-hub/
     * Navigator is in PRIOR_ART.md's "avoid" list for exactly that.
     */
    @Synchronized
    fun classify(ctx: Context, icon: Icon?, title: String? = null): Match {
        if (icon == null) return Match(Mv.UNKNOWN, "no-icon")

        val name = resName(ctx, icon)?.lowercase(Locale.ROOT)
        if (name != null) {
            if (name in IGNORED_NAMES) return Match(Mv.UNKNOWN, "non-maneuver res=$name")
            val hit = BY_NAME.firstOrNull { name.contains(it.first) }
            if (hit != null) {
                val code = refineRoundabout(hit.second, title)
                // Learn the pixels under a name we trust, so tier 3 can carry this
                // maneuver if the name ever disappears mid-session.
                learn(code, "res=$name", renderRows(ctx, icon))
                return Match(code, "res=$name")
            }
        }

        val r = render(ctx, icon) ?: return Match(Mv.UNKNOWN, "no-drawable")
        if (r.hash in IGNORED_HASHES) return Match(Mv.UNKNOWN, "non-maneuver hash=${r.hash}")

        BY_HASH[r.hash]?.let { code ->
            val refined = refineRoundabout(code, title)
            learn(refined, "hash=${r.hash}", r.rows)
            return Match(refined, "hash=${r.hash}")
        }

        fuzzy(r.rows)?.let { m ->
            return Match(refineRoundabout(m.code, title), m.via)
        }

        logUnrecognised(icon, r, name)
        return UNMATCHED
    }

    /** Drops learned signatures. Call when the listener reconnects. */
    @Synchronized
    fun reset() {
        refs.clear()
        refs.addAll(SEEDED)
        loggedArt.clear()
    }

    // -------------------------------------------------------------- matching

    /**
     * NAV_DATA.md reserves a code range rather than one ROUNDABOUT code, and lists
     * `title` as the fallback source for the exit number. `title` wins when it has
     * one: it is per-notification, where the hash-implied number is whatever a
     * single measured ride happened to be.
     */
    private fun refineRoundabout(code: Int, title: String?): Int {
        val isRoundabout = code == Mv.ROUNDABOUT ||
                code in (Mv.ROUNDABOUT_EXIT_BASE + 1)..(Mv.ROUNDABOUT_EXIT_BASE + 15)
        if (!isRoundabout) return code
        val n = exitFromTitle(title) ?: return code
        return Mv.roundaboutExit(n)
    }

    private val RE_ORDINAL_EXIT = Regex("""(\d+)\s*(?:st|nd|rd|th)\s+exit""", RegexOption.IGNORE_CASE)
    private val RE_EXIT_N = Regex("""exit\s+(\d+)""", RegexOption.IGNORE_CASE)

    /**
     * "Take the 3rd exit onto ..." -> 3. Requires the word "exit", so a house
     * number or a road called "5th Cross" cannot be mistaken for one. English
     * only, which is why it refines an icon match and never replaces it.
     */
    internal fun exitFromTitle(title: String?): Int? {
        if (title.isNullOrEmpty()) return null
        val m = RE_ORDINAL_EXIT.find(title) ?: RE_EXIT_N.find(title) ?: return null
        return m.groupValues[1].toIntOrNull()?.takeIf { it in 1..15 }
    }

    /** XOR + bitCount over the 32 packed rows. Lower is closer. */
    private fun diff(a: IntArray, b: IntArray): Int {
        var d = 0
        for (i in 0 until N) d += Integer.bitCount(a[i] xor b[i])
        return d
    }

    private fun fuzzy(rows: IntArray): Match? {
        var best: Sig? = null
        var bestDiff = Int.MAX_VALUE
        for (s in refs) {
            val d = diff(rows, s.rows)
            if (d < bestDiff) { best = s; bestDiff = d }
        }
        val win = best
        if (win == null || bestDiff >= MAX_DIFF_BITS) return null

        var rivalDiff = Int.MAX_VALUE          // closest ref with a *different* code
        for (s in refs) {
            if (s.code == win.code) continue
            val d = diff(rows, s.rows)
            if (d < rivalDiff) rivalDiff = d
        }
        if (rivalDiff - bestDiff < AMBIGUOUS_WITHIN) {
            Log.w(TAG, "icon ambiguous: ${Mv.name(win.code)} at $bestDiff bits vs a rival " +
                    "at $rivalDiff - refusing to guess")
            return null
        }
        return Match(win.code, "fuzzy=${win.label}/${bestDiff}b")
    }

    /**
     * Only ever called with a code from tier 1 or tier 2. Learning from a fuzzy
     * match would let one near-miss drag the reference set onto the wrong glyph.
     */
    private fun learn(code: Int, label: String, rows: IntArray?) {
        if (rows == null || code == Mv.UNKNOWN || refs.size >= LEARN_CAP) return
        // Skip if any existing ref is already this close - either it is the same
        // glyph again (nothing to add) or it belongs to another maneuver, and
        // storing a near-collision would make every later match ambiguous.
        for (s in refs) if (diff(rows, s.rows) < MAX_DIFF_BITS) return
        refs.add(Sig(code, label, rows))
    }

    // ------------------------------------------------------------- rendering

    private class Rendered(val hash: String, val rows: IntArray, val art: String)

    private fun renderRows(ctx: Context, icon: Icon): IntArray? = render(ctx, icon)?.rows

    /**
     * One pass produces all three views of the icon: NavDumpService's scalar hash
     * (bit-identical arithmetic - `hash * 31 + (a shr 5)` seeded at 17 - so the
     * NAV_DATA.md table applies), the packed rows for fuzzy matching, and the
     * ASCII art for the log.
     */
    private fun render(ctx: Context, icon: Icon): Rendered? = try {
        val d = icon.loadDrawable(ctx)
        if (d == null) null else {
            val bmp = Bitmap.createBitmap(N, N, Bitmap.Config.ARGB_8888)
            d.setBounds(0, 0, N, N)
            d.draw(Canvas(bmp))

            var hash = 17
            val rows = IntArray(N)
            val art = StringBuilder(N * (N + 1))
            for (y in 0 until N) {
                var row = 0
                for (x in 0 until N) {
                    val a = Color.alpha(bmp.getPixel(x, y))
                    hash = hash * 31 + (a shr 5)
                    if (a > ALPHA_ON) row = row or (1 shl x)
                    art.append(RAMP[a * (RAMP.length - 1) / 255])
                }
                rows[y] = row
                art.append('\n')
            }
            bmp.recycle()
            Rendered(Integer.toHexString(hash), rows, art.toString())
        }
    } catch (t: Throwable) {
        Log.w(TAG, "icon render failed: ${t.message}")
        null
    }

    /**
     * Prefers the resource name over pixels. Reflection because `getResId` is not
     * public SDK; lifted from NavDumpService, where it is proven against the real
     * notification.
     */
    private fun resName(ctx: Context, icon: Icon): String? = try {
        if (icon.type != TYPE_RESOURCE) null else {
            val resId = Icon::class.java.getMethod("getResId").invoke(icon) as Int
            val pkg = Icon::class.java.getMethod("getResPackage").invoke(icon) as? String
            val res = if (pkg.isNullOrEmpty()) ctx.resources
            else ctx.packageManager.getResourcesForApplication(pkg)
            res.getResourceEntryName(resId)
        }
    } catch (t: Throwable) { null }

    /**
     * The recovery path. An unknown icon is a table entry that has not been
     * written yet, so log everything needed to write it - and log it once per
     * distinct hash, not once per second.
     */
    private fun logUnrecognised(icon: Icon, r: Rendered, name: String?) {
        if (!loggedArt.add(r.hash)) return
        val kind = if (icon.type == TYPE_BITMAP) "bitmap" else "type=${icon.type}"
        val out = StringBuilder()
        out.append("UNRECOGNISED maneuver icon  hash=").append(r.hash)
            .append("  ").append(kind)
            .append(if (name != null) "  res=$name" else "")
            .append("\n  add to Maneuvers.BY_HASH as \"").append(r.hash)
            .append("\" to Mv.?, or paste the art below into Maneuvers.SEEDED:\n")
        for (line in r.art.lineSequence()) {
            if (line.isEmpty()) continue
            out.append("    \"").append(line).append("\",\n")
        }
        Log.w(TAG, out.toString())
    }

    /**
     * Builds a reference signature from logged ASCII art: any non-blank cell is
     * ink, which is the same threshold [render] applies to the live bitmap.
     * Tolerates short or long rows rather than throwing - a typo in a pasted table
     * must not take the service down mid-ride.
     */
    @Suppress("unused")   // called only from [SEEDED], which is empty until a ride fills it
    private fun art(code: Int, label: String, vararg rows: String): Sig {
        if (rows.size != N) Log.w(TAG, "art($label): ${rows.size} rows, expected $N")
        val packed = IntArray(N)
        for (y in 0 until minOf(N, rows.size)) {
            var row = 0
            val s = rows[y]
            for (x in 0 until minOf(N, s.length)) if (s[x] != ' ') row = row or (1 shl x)
            packed[y] = row
        }
        return Sig(code, label, packed)
    }
}
