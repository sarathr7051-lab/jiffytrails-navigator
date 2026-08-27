package com.jiffytrails.navlink

import android.app.Notification
import android.content.Context
import android.graphics.drawable.Icon
import android.os.Bundle
import android.os.SystemClock
import android.service.notification.StatusBarNotification
import android.util.Log
import java.util.Calendar
import kotlin.math.abs
import kotlin.math.roundToInt

/**
 * Google Maps ongoing notification -> [NavUpdate].
 *
 * The field mapping and every rule enforced below come from docs/NAV_DATA.md,
 * which was written by getting each one wrong first; the rule numbers in the
 * comments are its "Parser rules" section. The removal debounce comes from
 * docs/PRIOR_ART.md.
 *
 * Drive it from a NotificationListenerService:
 *
 *     override fun onNotificationPosted(sbn: StatusBarNotification) {
 *         parser.onPosted(sbn)?.let { link.send(it) }
 *     }
 *     override fun onNotificationRemoved(sbn: StatusBarNotification) {
 *         parser.onRemoved(sbn)          // arms the debounce, emits nothing
 *     }
 *     // and on the same ~1 Hz tick that keeps the device's stale watchdog fed:
 *     parser.poll()?.let { link.send(it) }
 *
 * [poll] is where end-of-route comes from, so it must be called even when Maps
 * has gone quiet - that is the entire point of the debounce.
 *
 * Not thread-safe by itself; listener callbacks and the tick are expected on one
 * thread. The mutable state is small enough that a caller wanting otherwise can
 * wrap the three entry points.
 */
class MapsParser(context: Context) {

    private val ctx: Context = context.applicationContext

    companion object {
        private const val TAG = "NAVLINK"

        const val MAPS_PKG = "com.google.android.apps.maps"

        /**
         * NAV_DATA.md: this single check removes traffic alerts and Samsung's
         * Aggregate_NormalNotificationSection wrapper.
         */
        private const val CATEGORY_NAV = "navigation"

        /**
         * PRIOR_ART.md / DEMP1993's NAV_END_DELAY_MS. Maps removes and instantly
         * re-posts its notification during active navigation; without this the
         * display flaps to idle and back mid-ride.
         *
         * Deliberately *not* shared with the device's 10 s stale watchdog, which
         * NAV_DATA.md calls out as a different timer with a different job.
         */
        private const val NAV_END_DELAY_MS = 15_000L

        // Samsung One UI "Live Notification" extras. NAV_DATA.md's warning block
        // flags these as probably One UI only: on a Pixel they may all be null,
        // which degrades to a no-distance, no-icon state rather than nonsense.
        private const val K_PRIMARY = "android.ongoingActivityNoti.primaryInfo"
        private const val K_SECONDARY = "android.ongoingActivityNoti.secondaryInfo"
        private const val K_CHIP_ICON = "android.ongoingActivityNoti.chipIcon"
        private const val K_NOWBAR_IC = "android.ongoingActivityNoti.nowbarIcon"
        private const val K_SECOND_IC = "android.ongoingActivityNoti.secondIcon"
        private const val K_NOWBAR_PRI = "android.ongoingActivityNoti.nowbarPrimaryInfo"
        private const val K_NOWBAR_SEC = "android.ongoingActivityNoti.nowbarSecondaryInfo"

        // "towards Moulana Azad Rd" -> "Moulana Azad Rd"
        private val RE_TOWARDS = Regex("""^\s*(towards|toward|to)\s+""", RegexOption.IGNORE_CASE)

        // AOSP.
        private const val K_TITLE = "android.title"
        private const val K_TEXT = "android.text"
        private const val K_SUBTEXT = "android.subText"
        private const val K_PROGRESS = "android.progress"
        private const val K_PROG_MAX = "android.progressMax"

        /** EXTRA_SHORT_CRITICAL_TEXT, API 36. String literal so compileSdk < 36 builds. */
        private const val K_SHORT_CRIT = "android.shortCriticalText"
        private const val K_SHOW_CHRONO = "android.showChronometer"
        private const val K_CHRONO_DOWN = "android.chronometerCountDown"

        /** Rule 1: `"700 m · Slight right onto ..."`. The distance is already ours. */
        private val RE_DIST_PREFIX = Regex("""^\d+(\.\d+)?\s*(m|km)\s*·\s*""")

        /**
         * Rule 2: `primaryInfo` is a distance, a road name, or the maneuver text.
         * Anchored hard - anything that is not exactly a distance is a
         * no-distance state, never something to put on the display.
         *
         * `"3 km"` with no decimal is not accepted because it does not occur:
         * NAV_DATA.md's quantisation table steps in 100 m above 1 km, so every
         * kilometre value carries one decimal place.
         */
        private val RE_DIST_M = Regex("""^(\d+) m$""")
        private val RE_DIST_KM = Regex("""^(\d+\.\d+) km$""")

        /** Rule 5: `subText` also carries traffic alerts. */
        private const val ARRIVE_PREFIX = "Arrive"
        private val RE_CLOCK = Regex("""(\d{1,2}):(\d{2})\s*([ap])\.?\s?m\.?""", RegexOption.IGNORE_CASE)
        private val RE_CLOCK_24 = Regex("""(\d{1,2}):(\d{2})""")

        // State signatures, NAV_DATA.md "State detection".
        private const val T_STARTING = "starting navigation"
        private const val T_ARRIVING = "arriving"
        private const val P_REROUTING = "rerouting"

        /**
         * Rule 6: a route can be replaced with no rerouting state - observed
         * `progressMax` 11909 -> 7448 six seconds apart. But rule 3 says
         * `progressMax` also *drifts* (7486 -> 7780, and 851 -> 1196 -> 804 within
         * one journey), so neither an absolute nor a relative test works alone.
         * Both must fire: the 11909 -> 7448 case is 4461 m and 37%, the drift
         * cases are all under 400 m.
         */
        private const val ROUTE_REPLACED_M = 2_000
        private const val ROUTE_REPLACED_FRAC = 0.25

        /**
         * Rule 7: instructions run to 60 characters and there is room for roughly
         * 16-20 at a glanceable size. Above this we prefer the road name to the
         * full sentence - see [chooseInstruction].
         */
        private const val GLANCE_CHARS = 20

        /** Rule 7 again: `title` writes "Rd/Street", `secondaryInfo` "Rd / Street". */
        private val RE_SLASH_SPACES = Regex("""\s*/\s*""")

        /**
         * English connectors, last-resort only. Used to drop a maneuver prefix the
         * arrow already conveys when `secondaryInfo` is unavailable - which is the
         * non-Samsung case the warning block in NAV_DATA.md predicts.
         */
        private val CONNECTORS = listOf(" onto ", " towards ", " toward ", " on ", " at ")

    }

    // --------------------------------------------------------------- state

    /** Elapsed-realtime deadline for the debounced end-of-route; 0 = not armed. */
    private var pendingEndAt = 0L
    private var activeKey: String? = null
    private var navActive = false
    private var lastArrived = false

    /**
     * Arrival **clock time**, minutes past midnight - not a countdown. Holding the
     * target rather than the remaining minutes means a packet with no readable
     * `subText` still gets a correct ETA instead of a stale or blank one, and it
     * cannot silently age.
     */
    private var arrivalMinuteOfDay: Int? = null

    /** Last good route figures, held only to freeze the bar while rerouting. */
    private var heldRemaining100m = 0
    private var heldEtaMin = 0

    /**
     * Last distance that actually parsed.
     *
     * Rule 2 says primaryInfo is not always a distance - mid-turn it carries
     * the road name or the maneuver text instead. Defaulting those packets to
     * zero put "0 m" on the handlebar while the rider was still 40 m from the
     * junction, and alternated with the correct value as primaryInfo flipped
     * back and forth. Zero on that display means turn now.
     *
     * Holding the last good value freezes the number for a beat instead of
     * lying about it. Route end and arrival are signalled by navActive and the
     * arrived flag, so nothing depends on distance decaying to zero.
     */
    private var heldDistM = 0
    private var lastProgressMax = 0

    private var lastManeuver = -1
    private var lastProbe: String? = null
    private var lastEtaCompare: String? = null

    // ----------------------------------------------------------------- api

    /**
     * Returns an update for every Google Maps navigation notification, or null if
     * the notification is not one. It does not deduplicate: NAV_DATA.md's
     * watchdog section requires the device to count *arrivals*, not changes, so
     * suppressing an unchanged packet here would starve it. Whether to re-send an
     * identical frame is the BLE layer's call.
     */
    fun onPosted(sbn: StatusBarNotification): NavUpdate? {
        if (sbn.packageName != MAPS_PKG) return null
        val n = sbn.notification ?: return null
        if (n.category != CATEGORY_NAV) return null
        val ex = n.extras ?: return null

        // A nav notification reappeared, so the removal that armed the timer was a
        // re-post, not the end of the route (PRIOR_ART.md).
        if (pendingEndAt != 0L) {
            Log.d(TAG, "nav notification re-posted; end-of-route cancelled " +
                    "${pendingEndAt - SystemClock.elapsedRealtime()} ms before it would have fired")
            pendingEndAt = 0L
        }
        activeKey = sbn.key
        navActive = true

        probeUnmined(n, ex)

        val title = str(ex, K_TITLE) ?: ""
        val text = str(ex, K_TEXT) ?: ""
        val primary = str(ex, K_PRIMARY)
        val secondary = str(ex, K_SECONDARY)
        val subText = str(ex, K_SUBTEXT)
        val progress = int(ex, K_PROGRESS)
        val progressMax = int(ex, K_PROG_MAX)
        val icon = iconOf(ex, K_CHIP_ICON) ?: iconOf(ex, K_NOWBAR_IC) ?: iconOf(ex, K_SECOND_IC)

        noteProgressMax(progressMax)

        // NAV_DATA.md "State detection". `title` carries an ellipsis in two of the
        // four signatures, so these are prefix tests, and lowercased because the
        // casing is Maps' presentation choice, not a contract.
        val lower = title.lowercase()
        val rerouting = primary != null && primary.lowercase().startsWith(P_REROUTING)
        val arriving = lower.startsWith(T_ARRIVING) ||
                (progressMax == 0 && icon == null && text.startsWith("at "))
        val starting = lower.startsWith(T_STARTING)

        val update = when {
            // Order matters: "Arriving" outranks everything, and a reroute has no
            // icon so it must be caught before the navigating branch tries to
            // classify one.
            arriving -> arrivingUpdate(text)
            rerouting -> reroutingUpdate()
            starting -> startingUpdate()
            else -> navigatingUpdate(
                title, primary, secondary, subText, progress, progressMax, icon,
                whenEtaMinutes(n, ex),
                str(ex, K_NOWBAR_SEC),
            )
        }

        lastArrived = update.arrived
        if (update.maneuver != lastManeuver) {
            lastManeuver = update.maneuver
            Log.d(TAG, "maneuver -> ${Mv.name(update.maneuver)}  ${update.distM} m  " +
                    "\"${update.instruction}\"  eta=${update.etaMin} rem=${update.remaining100m}")
        }
        return update
    }

    /**
     * Arms the end-of-route debounce. Emits nothing - the route is only over when
     * [poll] says so, [NAV_END_DELAY_MS] later with no nav notification in
     * between.
     */
    fun onRemoved(sbn: StatusBarNotification) {
        if (sbn.packageName != MAPS_PKG) return
        if (!navActive) return
        // A removed notification may arrive with its category intact; when it does
        // not, fall back to the key of the one we are tracking so an unrelated
        // Maps notification cannot arm the timer.
        val cat = sbn.notification?.category
        if (cat != CATEGORY_NAV && sbn.key != activeKey) return
        if (pendingEndAt != 0L) return
        pendingEndAt = SystemClock.elapsedRealtime() + NAV_END_DELAY_MS
        Log.d(TAG, "nav notification removed; end-of-route in $NAV_END_DELAY_MS ms unless it returns")
    }

    /**
     * Call on the regular tick. Returns the end-of-route update exactly once, when
     * the debounce expires.
     *
     * NAV_DATA.md measures arrival-to-removal at 4.7 s, so arrival is confirmed
     * roughly 15 s after Maps drops the notification. For an arrival that is fine.
     */
    fun poll(): NavUpdate? {
        if (pendingEndAt == 0L || SystemClock.elapsedRealtime() < pendingEndAt) return null
        pendingEndAt = 0L
        val arrived = lastArrived
        resetRoute()
        Log.d(TAG, "route ended (debounce expired), arrived=$arrived")
        // navActive false is what makes the device drop to the clock; `arrived` is
        // carried through so it can say why.
        return NavUpdate(navActive = false, arrived = arrived)
    }

    /** Elapsed-realtime deadline, for a caller that would rather post a delayed message than poll. */
    fun pendingEndDeadline(): Long? = pendingEndAt.takeIf { it != 0L }

    val isNavActive: Boolean get() = navActive

    /**
     * Clears everything, learned icon signatures included. For
     * onListenerConnected / onListenerDisconnected, where the notification stream
     * itself restarts.
     */
    fun reset() {
        resetRoute()
        Maneuvers.reset()
    }

    /**
     * Per-route state only. Learned icon signatures survive, because the glyph set
     * belongs to the installed Maps build, not to the route.
     */
    private fun resetRoute() {
        pendingEndAt = 0L
        activeKey = null
        navActive = false
        lastArrived = false
        arrivalMinuteOfDay = null
        heldRemaining100m = 0
        heldEtaMin = 0
        heldDistM = 0
        lastProgressMax = 0
        lastManeuver = -1
        lastProbe = null
        lastEtaCompare = null
    }

    // -------------------------------------------------------------- states

    private fun startingUpdate(): NavUpdate {
        // No template, no icon, no distance. Active so the device does not show the
        // idle clock, UNKNOWN so it draws "?" rather than an invented arrow.
        return NavUpdate(
            maneuver = Mv.UNKNOWN,
            instruction = "Starting",
            navActive = true,
        )
    }

    /**
     * NAV_DATA.md: rerouting zeroes `progress` but keeps `progressMax`, so a
     * naively recomputed bar snaps to 0% and back - three times in the first 90
     * seconds of one ride. Freeze the route figures instead of redrawing them.
     * The maneuver is dropped outright: `chipIcon` is null here and the previous
     * arrow no longer describes the road.
     */
    private fun reroutingUpdate() = NavUpdate(
        maneuver = Mv.UNKNOWN,
        distM = 0,
        etaMin = heldEtaMin,
        remaining100m = heldRemaining100m,
        instruction = "",
        navActive = true,
        rerouting = true,
    )

    /**
     * `text` is `"at <destination>"`. DESTINATION here is the one maneuver taken
     * from text rather than pixels, and it is not a junction call - it cannot
     * point the rider the wrong way, which is the failure the never-guess rule
     * exists to prevent.
     */
    private fun arrivingUpdate(text: String) = NavUpdate(
        maneuver = Mv.DESTINATION,
        distM = 0,
        etaMin = 0,
        remaining100m = 0,
        instruction = text.removePrefix("at ").trim().ifEmpty { "Arriving" },
        navActive = true,
        arrived = true,
    )

    private fun navigatingUpdate(
        title: String,
        primary: String?,
        secondary: String?,
        subText: String?,
        progress: Int,
        progressMax: Int,
        icon: Icon?,
        whenEta: Int?,
        nowbarSec: String?,
    ): NavUpdate {
        val stripped = RE_DIST_PREFIX.replace(title, "")            // rule 1
        val match = Maneuvers.classify(ctx, icon, title)
        // Rule 2: a packet with no readable distance holds the last one rather
        // than claiming zero. See heldDistM.
        val parsedDist = parseDistance(primary)
        if (parsedDist != null) heldDistM = parsedDist
        val distM = parsedDist ?: heldDistM

        // Rule 3: recompute every packet, never cache. `progressMax` drifted
        // 7486 -> 7780 -> 7659 -> 7486 over 45 s of ordinary riding.
        val remaining100m =
            if (progressMax > 0) ((progressMax - progress).coerceAtLeast(0)) / 100 else 0
        heldRemaining100m = remaining100m

        val etaMin = resolveEta(subText, whenEta)
        heldEtaMin = etaMin

        return NavUpdate(
            maneuver = match.code,
            distM = distM,
            etaMin = etaMin,
            remaining100m = remaining100m,
            instruction = chooseInstruction(stripped, secondary, primary, match.known, nowbarSec),
            navActive = true,
            // Nothing in the payload reports GPS quality, and NAV_DATA.md tested
            // and rejected rising distance as a proxy - it drifts 30 -> 50 m at a
            // stationary traffic signal.
            gpsWeak = false,
        )
    }

    // --------------------------------------------------------------- rules

    /** Rule 2. Returns null - not zero - so callers can tell "no distance" from "0 m". */
    private fun parseDistance(primary: String?): Int? {
        if (primary == null) return null
        RE_DIST_M.find(primary)?.let { return it.groupValues[1].toIntOrNull() }
        RE_DIST_KM.find(primary)?.let { m ->
            val km = m.groupValues[1].toDoubleOrNull() ?: return null
            return (km * 1000).roundToInt()
        }
        return null
    }

    /** Rule 6. Only logs and clears held state; there is no wire flag for it. */
    private fun noteProgressMax(max: Int) {
        val prev = lastProgressMax
        lastProgressMax = max
        if (prev <= 0 || max <= 0) return
        val delta = abs(max - prev)
        if (delta >= ROUTE_REPLACED_M && delta >= prev * ROUTE_REPLACED_FRAC) {
            Log.i(TAG, "route replaced: progressMax $prev -> $max (no rerouting state)")
            // Everything held belongs to the old route.
            arrivalMinuteOfDay = null
            heldRemaining100m = 0
            heldEtaMin = 0
            heldDistM = 0
            lastArrived = false
        }
    }

    /**
     * Rules 4 and 7. The device gets one string, and the end of it is what gets
     * truncated on render - so when the full instruction cannot fit, send the road
     * name rather than a sentence that will lose its road name.
     *
     * `secondaryInfo` is the road being turned onto and is structured, so it is
     * preferred over cutting the title on an English connector. It is suppressed
     * when it merely echoes the maneuver (rule 4: with no named destination it
     * returns "Turn right").
     */
    private fun chooseInstruction(
        stripped: String,
        secondary: String?,
        primary: String?,
        maneuverKnown: Boolean,
        nowbarSec: String? = null,
    ): String {
        // Measured 27 Aug 2026: nowbarSecondaryInfo carries a pre-shortened road
        // name, phrased "towards Moulana Azad Rd". Samsung sized it for the Now
        // Bar, so it is already inside the ~16-20 characters this display can
        // render legibly - which is the whole problem rule 7 describes. Strip the
        // connector and prefer it over truncating a 60-character instruction.
        //
        // It is a One UI key, so this deepens the Samsung dependency. Worth it: a
        // truncated road name is barely better than none.
        nowbarSec?.let { nb ->
            val road = RE_TOWARDS.replace(nb, "").trim()
            if (road.isNotEmpty() && road.length <= GLANCE_CHARS) return road
        }

        val road = secondary
            ?.let { RE_SLASH_SPACES.replace(it, "/") }               // "Rd / St" -> "Rd/St"
            ?.takeIf { it.isNotEmpty() && !echoes(it, stripped) }

        if (stripped.isEmpty()) {
            // Rule 2's second case: at the moment of the turn `primaryInfo` holds
            // the road name, which is better than an empty display.
            return road ?: primary?.takeIf { parseDistance(it) == null } ?: ""
        }
        if (stripped.length <= GLANCE_CHARS) return stripped

        // Only drop the maneuver words when the arrow actually conveys them. With
        // an UNKNOWN maneuver the device draws "?", so the words are all the rider
        // has and the full string goes out.
        if (!maneuverKnown) return stripped

        road?.let { if (it.length < stripped.length) return it }
        return dropManeuverPrefix(stripped) ?: stripped
    }

    /** Normalised comparison; `title` and `secondaryInfo` differ in spacing around "/". */
    private fun echoes(secondary: String, title: String): Boolean {
        val s = norm(secondary)
        val t = norm(title)
        return s == t || t.startsWith(s)
    }

    private fun norm(s: String) =
        RE_SLASH_SPACES.replace(s, "/").trim().lowercase()

    /**
     * "Slight right at Horamavu Agara Circle onto Horamavu Agara Rd" ->
     * "Horamavu Agara Rd". " onto " introduces the road being turned onto, so the
     * *last* one wins; any other connector is only a prefix boundary, so the
     * first one wins and the rest of the string is kept.
     */
    private fun dropManeuverPrefix(s: String): String? {
        val onto = s.lastIndexOf(" onto ")
        if (onto >= 0) return s.substring(onto + 6).trim().ifEmpty { null }
        for (c in CONNECTORS) {
            val i = s.indexOf(c)
            if (i > 0) return s.substring(i + c.length).trim().ifEmpty { null }
        }
        return null
    }

    // ----------------------------------------------------------------- eta

    /**
     * NAV_DATA.md unmined field 2: `android.when` plus `chronometerCountDown`
     * would be the arrival time as epoch millis, which is locale-proof and would
     * retire [parseClockMinutes] entirely. Untested on the device, so this is a
     * fallback and a log line, not the primary source.
     *
     * Returns null unless `when` is a *future* timestamp - a `when` equal to the
     * post time is just the post time, which is what most notifications set.
     */
    private fun whenEtaMinutes(n: Notification, ex: Bundle): Int? {
        val w = n.`when`
        if (w <= 0L || !bool(ex, K_CHRONO_DOWN)) return null
        val delta = w - System.currentTimeMillis()
        if (delta <= 0L || delta > 24 * 60 * 60 * 1000L) return null
        return (delta / 60_000L).toInt()
    }

    /**
     * "Arrive 12:08 pm" is the proven source; `when` is the candidate replacement.
     * Both are computed so a single ride's logcat answers whether the AOSP field
     * can take over, and `when` is used only where the proven path has nothing.
     */
    private fun resolveEta(subText: String?, whenEta: Int?): Int {
        val fromText = etaMinutes(subText)
        if (whenEta != null) {
            val verdict = if (abs(whenEta - fromText) <= 1) "agrees" else "DIFFERS"
            val line = "eta subText=$fromText min, when=$whenEta min ($verdict)"
            if (line != lastEtaCompare) {
                lastEtaCompare = line
                Log.i(TAG, "PROBE $line")
            }
            if (fromText == 0) return whenEta
        }
        return fromText
    }

    /**
     * Rule 5: `subText` is only an ETA when it starts with "Arrive"; otherwise it
     * is a traffic alert, and during a reroute it is the truncated "Arrive ".
     *
     * The arrival *clock time* is what gets held, and the countdown is recomputed
     * from it on every packet, so a packet with unreadable `subText` produces a
     * correct ETA rather than a stale one.
     */
    private fun etaMinutes(subText: String?): Int {
        if (subText != null && subText.startsWith(ARRIVE_PREFIX, ignoreCase = true)) {
            parseClockMinutes(subText.substring(ARRIVE_PREFIX.length))?.let {
                arrivalMinuteOfDay = it
            }
        }
        val target = arrivalMinuteOfDay ?: return 0
        val cal = Calendar.getInstance()
        val nowMin = cal.get(Calendar.HOUR_OF_DAY) * 60 + cal.get(Calendar.MINUTE)
        var d = target - nowMin
        // A route never runs 23 hours, so a large negative means the arrival is
        // past midnight; a small one is clock rounding.
        if (d < -60) d += 24 * 60
        return d.coerceAtLeast(0)
    }

    /**
     * "12:08 pm" -> minutes past midnight. Regex rather than SimpleDateFormat: the
     * separator Maps uses before "pm" is sometimes a narrow no-break space, and a
     * failed parse must be a missing ETA, never an exception on the listener
     * thread. Latin digits only - a non-Latin-numeral locale falls back to no ETA.
     */
    private fun parseClockMinutes(s: String): Int? {
        val t = s.trim()
        if (t.isEmpty()) return null                                  // reroute's "Arrive "
        RE_CLOCK.find(t)?.let { m ->
            var h = m.groupValues[1].toIntOrNull() ?: return null
            val min = m.groupValues[2].toIntOrNull() ?: return null
            val pm = m.groupValues[3].equals("p", ignoreCase = true)
            if (h == 12) h = 0
            if (pm) h += 12
            return h * 60 + min
        }
        RE_CLOCK_24.find(t)?.let { m ->
            val h = m.groupValues[1].toIntOrNull() ?: return null
            val min = m.groupValues[2].toIntOrNull() ?: return null
            if (h !in 0..23 || min !in 0..59) return null
            return h * 60 + min
        }
        return null
    }

    // --------------------------------------------------- unmined-field probe

    /**
     * NAV_DATA.md "Unmined fields" 1 and 2, neither of which has been seen on the
     * real device. This costs a few getters and logs only when the answer changes,
     * so it can stay in the shipping build until the questions are settled.
     *
     *  - `android.shortCriticalText` is AOSP (API 36) and is Maps' own string
     *    pre-shortened for a status-bar chip. If it is populated it answers rule 7
     *    outright and may answer the Samsung-portability warning too.
     *  - `android.when` with `chronometerCountDown` would be the ETA as epoch
     *    millis, replacing the "Arrive 12:08 pm" regex above. Its raw state is
     *    logged here; [resolveEta] logs it against the regex-derived value.
     *
     * `flags` is logged raw because FLAG_PROMOTED_ONGOING (unmined field 4) is a
     * compileSdk 36 constant; the bit can be identified by diffing these values.
     */
    private fun probeUnmined(n: Notification, ex: Bundle) {
        val short = str(ex, K_SHORT_CRIT)
        val showChrono = bool(ex, K_SHOW_CHRONO)
        val countDown = bool(ex, K_CHRONO_DOWN)
        val whenMs = n.`when`
        val nowbarPri = str(ex, K_NOWBAR_PRI)
        val nowbarSec = str(ex, K_NOWBAR_SEC)

        val whenDeltaMin = if (whenMs > 0) ((whenMs - System.currentTimeMillis()) / 60_000L) else Long.MIN_VALUE
        val sig = "$short|$showChrono|$countDown|${whenMs > 0}|$nowbarPri|$nowbarSec|${n.flags}"
        if (sig == lastProbe) return
        lastProbe = sig

        /*
          Is secondIcon the *next* maneuver?

          NAV_DATA.md assumes nowbarIcon and secondIcon merely duplicate chipIcon,
          but that was never tested and the name is suspicious. A full extras dump
          confirmed no *text* field anywhere carries a next maneuver, yet Maps
          plainly renders "Then ->" in its own UI, so that glyph exists somewhere
          and three same-sized bitmaps is where to look.

          If these two ever classify differently while "Then" is on screen, the
          next maneuver is available after all — which would close the one gap
          BLE_PROTOCOL.md has reserved fields waiting for.
        */
        val chipCode = Maneuvers.classify(ctx, iconOf(ex, K_CHIP_ICON)).code
        val secondCode = Maneuvers.classify(ctx, iconOf(ex, K_SECOND_IC)).code
        val nowbarCode = Maneuvers.classify(ctx, iconOf(ex, K_NOWBAR_IC)).code

        Log.i(TAG, "PROBE shortCriticalText=${short ?: "<null>"}" +
                "  showChronometer=$showChrono countDown=$countDown" +
                "  when=${if (whenMs > 0) "${whenDeltaMin}min from now" else "<unset>"}" +
                "  nowbarPrimary=${nowbarPri ?: "<null>"} nowbarSecondary=${nowbarSec ?: "<null>"}" +
                "  flags=0x${Integer.toHexString(n.flags)}")

        Log.i(TAG, "PROBE-ICONS chip=${Mv.name(chipCode)} second=${Mv.name(secondCode)} " +
                "nowbar=${Mv.name(nowbarCode)} " +
                if (secondCode != chipCode) "*** SECOND DIFFERS ***" else "(all same)")
    }

    // ------------------------------------------------------------- helpers

    /**
     * Extras arrive as CharSequence, and Maps uses a narrow no-break space before
     * "pm" and around "·"; normalising here means every regex above can assume a
     * plain space. Returns null rather than "-" - a missing field is a state, not
     * a string to display.
     */
    private fun str(ex: Bundle, key: String): String? = try {
        @Suppress("DEPRECATION")
        (ex.get(key) as? CharSequence)?.toString()
            ?.let { plainSpaces(it) }?.trim()
            ?.takeIf { it.isNotEmpty() }
    } catch (t: Throwable) { null }

    /**
     * No-break space (U+00A0) and narrow no-break space (U+202F) -> plain space.
     * Written as codepoints, not char literals: both are invisible in an editor,
     * and a "space" in this file that is not a space would be an excellent way to
     * lose an afternoon.
     */
    private fun plainSpaces(s: String): String {
        val out = StringBuilder(s.length)
        for (c in s) out.append(if (c.code == 0x00A0 || c.code == 0x202F) ' ' else c)
        return out.toString()
    }

    private fun int(ex: Bundle, key: String): Int = try {
        ex.getInt(key, 0)
    } catch (t: Throwable) { 0 }

    private fun bool(ex: Bundle, key: String): Boolean = try {
        ex.getBoolean(key, false)
    } catch (t: Throwable) { false }

    private fun iconOf(ex: Bundle, key: String): Icon? = try {
        @Suppress("DEPRECATION")
        ex.get(key) as? Icon
    } catch (t: Throwable) { null }
}
