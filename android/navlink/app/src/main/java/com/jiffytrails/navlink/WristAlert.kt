package com.jiffytrails.navlink

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.SystemClock
import android.util.Log
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat

/**
 * The turn, on a wrist band, as an ORDINARY notification.
 *
 * Why this exists: the Galaxy Fit3 mirrors normal notifications and nothing
 * else. Google Maps' navigation notification is an ongoing/live one, so Maps
 * does not even appear in Galaxy Wearable's per-app list - there is no setting
 * to turn on. NavLink already parses every turn for the handlebar display, so
 * it posts its own plain notification that the band is willing to mirror.
 *
 * ★ A BACKUP PATH, AND IT BEHAVES LIKE ONE. The handlebar display is the
 * instrument. Everything here runs AFTER the BLE write, wrapped by the caller,
 * so a failure in this file can never delay or break the display. Where the two
 * disagree the display is right: it carries the exact distance, this rounds.
 *
 * ★ EVERYTHING BELOW WAS MEASURED ON THE BAND, AND EVERY UNTESTED ASSUMPTION
 * CAME BACK WRONG. In order:
 *
 *  - The title is about TEN characters, not seventeen. The band's own button
 *    reads "Block notificatic", but that sits in the body, which is wider; the
 *    title shares its row with the app icon. Photographs of a real ride caught
 *    "RIGHT 175" losing its "m".
 *  - The band STACKS updates rather than replacing them - six rows of one road
 *    name from a single leg. Cancelling before posting cures it, and a
 *    cancelled-then-reposted notification is a NEW arrival, so an update can no
 *    longer be made silent.
 *  - The band cannot hold a notification on screen. Always-On Display shows the
 *    watch face, and AOD costs 13 days of battery down to 3.5. So a silent
 *    update lands on a sleeping screen and is read by nobody.
 *
 * Those three together force the design: nothing is sent unless it buzzes,
 * because the buzz is what wakes the screen and puts the words in front of the
 * rider. Between turns the wrist holds the last turn for TIMEOUT_MS and then
 * goes empty, which is the honest state - there is nothing to do yet.
 */
object WristAlert {

    private const val TAG = "NAVLINK/wrist"

    /*
      ★ v2 BECAUSE A CHANNEL IS IMMUTABLE ONCE CREATED. Android will not let an
      app change an existing channel's vibration - only the user can - so a new
      pattern needs a new id, and the old channel is deleted on first use.
      Galaxy Wearable's switch is per APP, not per channel, so the band does not
      need re-enabling.
    */
    private val CHANNEL_IDS_OLD = listOf("wrist_turns", "wrist_turns_v2")
    const val CHANNEL_ID = "wrist_turns_v3"
    const val CHANNEL_NAME = "Wrist turn alerts"

    /**
     * One id, reused forever. The wrist must hold exactly one turn - the
     * current one - and a fresh id per maneuver would leave a scrollable
     * history of turns already taken.
     */
    const val NOTIF_ID = 0x5731

    private const val PREFS = "navlink"
    private const val KEY_ENABLED = "wrist_alerts_enabled"

    /*
      ★ SECONDS TO THE TURN, NOT METRES TO IT.

      This used to buzz when a turn became current and again at 200 m, and a
      real ride showed that wrong twice over. 200 m is sixteen seconds at
      45 km/h, nine at 80, and thirty-six in slow traffic - the same warning
      arrives far too late on an open road and far too early in a jam. And on a
      900 m leg the two buzzes sat 58 seconds apart, a long silence when you are
      trying not to miss a junction.

      So the warnings are placed in TIME, against the speed the rider is
      actually doing, measured from how fast the distance is closing. The same
      three moments then mean the same thing at any speed:

        120 s - there is a turn coming, and what kind
         60 s - it is the next thing to happen
         30 s - get into position for it
         12 s - it is now

      ★ FOUR, NOT THREE. Three left gaps of up to 33 seconds on a long leg
      and the rider asked for more - a wrist that has said nothing for half a
      minute reads as a wrist that has stopped working, and the whole point of
      a backup instrument is that you can tell it is still there.

      At 45 km/h those land near 1500 m, 560 m and 190 m. In traffic at 18 km/h,
      600 m, 225 m and 75 m. At 70 km/h, 2.3 km, 875 m and 290 m. The rider gets
      the same time to react on every road.
    */
    private val THRESHOLDS_S = intArrayOf(120, 60, 30, 12)

    /*
      ★ NO TWO WARNINGS CLOSER TOGETHER THAN THIS, except the last one.

      Found by dry-running the thresholds before they reached a wrist. If a turn
      appears when it is ALREADY inside 120 s - which is most turns in a city -
      that threshold fires at once and the 45 s one lands seconds later. At a
      steady 45 km/h the two came 8 seconds apart: a double-buzz saying nothing
      new, which trains a rider to ignore it.

      The final warning is exempt. It means "now", and a rider who has just been
      told about a turn still needs telling when to act on it.

      ★ 12 s, DOWN FROM 20. With four thresholds instead of three the real
      gaps are smaller by design, and a 20 s floor was swallowing the extra
      warnings it was supposed to let through.
    */
    private const val MIN_GAP_MS = 12_000L

    /** Until the distance has moved twice there is nothing to measure. */
    private const val DEFAULT_MPS = 12.5        // 45 km/h

    /** Below this the rider is stopped; time-to-turn would be meaningless. */
    private const val MIN_MPS = 1.5
    private const val MAX_MPS = 40.0

    /** A maneuver seen again within this window is a Maps flicker, not a turn. */
    private const val REFLIP_MS = 20_000L

    /**
     * How long the turn stays available on the wrist.
     *
     * ★ 120 s, NOT 60. The band flashes a notification for a few seconds then
     * returns to the watch face, and no setting lengthens that - only the
     * general Screen timeout exists, and Samsung's manual does not say
     * notifications follow it. So a rider who misses the flash has to raise a
     * wrist and swipe back, and this is how long they have. Still short enough
     * that a dead app clears itself rather than leaving a turn already taken.
     */
    private const val TIMEOUT_MS = 120_000L

    /*
      ★ PLAIN TEXT ARROWS, AND THE EMOJI EXPERIMENT IS REVERTED.

      Emoji draw several times larger than text glyphs, so they looked like the
      answer to "the arrow is too small in daylight". On the wrist they were
      worse, and the rider's reason is one no amount of reasoning here would
      have produced: the band renders a notification on a BLUE background, and
      Samsung's emoji arrows are themselves blue. Blue on blue. The monochrome
      glyphs below are drawn in the notification's text colour - white on that
      blue - so they are smaller and far easier to tell apart, which is the
      thing that actually matters at a glance.

      Size lost to contrast gained. Worth remembering if anyone is tempted by
      emoji again: measure them where they will be read, not where they are
      written.
    */
    private const val L_ARROW = "←"        // left
    private const val R_ARROW = "→"        // right
    private const val UP_ARROW = "↑"       // straight on
    private const val UL_ARROW = "↖"       // slight / keep left
    private const val UR_ARROW = "↗"       // slight / keep right
    private const val U_TURN = "↩"         // u-turn
    private const val RNDBT = "↻"          // roundabout
    private const val FLAG = ""                  // arrival says it in words

    /**
     * Cancel the old notification before posting the new one.
     *
     * ★ ON, because the band stacks otherwise. The cost is that a
     * cancelled-then-reposted notification is a NEW arrival, so setOnlyAlertOnce
     * can no longer keep an update silent - and that cost is now zero, because
     * nothing is sent unless it is meant to buzz.
     */
    private const val CANCEL_BEFORE_POST = true

    // ------------------------------------------------------------------ state

    private var currentManeuver = Mv.UNKNOWN
    private var lastPosted: String? = null

    /** One bit per entry in THRESHOLDS_S, cleared when the maneuver changes. */
    private var firedMask = 0

    // Speed, measured rather than assumed: how fast the distance is closing.
    private var lastDistM = -1
    private var lastDistAtMs = 0L
    private var speedMps = 0.0
    private var lastBuzzAtMs = 0L

    /** maneuver code -> elapsedRealtime when it stopped being current. */
    private val leftAt = HashMap<Int, Long>()

    /**
     * Log the decision without posting it. Lets a whole ride - or a dozen rides
     * at different speeds - run through the REAL logic in a millisecond, so the
     * thresholds can be tuned without buzzing anybody's wrist.
     */
    @Volatile
    var dryRun = false

    /**
     * Where "now" comes from. Swappable because the speed estimate is measured
     * against this clock, so a dry run with a frozen clock would measure
     * nothing and every threshold would read as unreached.
     */
    @Volatile
    var clock: () -> Long = { SystemClock.elapsedRealtime() }

    // ----------------------------------------------------------------- on/off

    fun isEnabled(ctx: Context): Boolean =
        ctx.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .getBoolean(KEY_ENABLED, true)

    fun setEnabled(ctx: Context, on: Boolean) {
        ctx.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .edit().putBoolean(KEY_ENABLED, on).apply()
        if (!on) clear(ctx)
        Log.i(TAG, "wrist alerts ${if (on) "ON" else "OFF"}")
    }

    // ------------------------------------------------------------------- main

    /**
     * Called for every parsed update, after the BLE write.
     *
     * Synchronized because the listener's callbacks and the 1 Hz poller are not
     * guaranteed to share a thread, and the threshold and speed rules are all
     * read-modify-write on shared state.
     */
    @Synchronized
    fun onUpdate(ctx: Context, u: NavUpdate) {
        if (!isEnabled(ctx)) return

        if (!u.navActive) {
            clear(ctx)
            return
        }

        if (u.arrived) {
            if (currentManeuver != Mv.DESTINATION) {
                currentManeuver = Mv.DESTINATION
                firedMask = -1          // nothing closer left to announce
                post(ctx, headline(Mv.DESTINATION, ""),
                     detail(Mv.DESTINATION, u.instruction), buzz = true)
            }
            return
        }

        // Hold, do not guess. Both are transient and the wrist keeps the last
        // true thing it was told - the same rule the display follows.
        if (u.rerouting) {
            // Never seen on a real ride. Logged so the first one tells us what
            // Maps actually does here instead of us guessing afterwards.
            RideLog.line(ctx, "rerouting - holding last turn")
            return
        }
        if (u.maneuver == Mv.UNKNOWN) return

        val now = clock()
        val changed = u.maneuver != currentManeuver

        if (changed) {
            val wasCurrentAt = leftAt[u.maneuver]
            val reflip = wasCurrentAt != null && now - wasCurrentAt < REFLIP_MS
            if (currentManeuver == Mv.UNKNOWN) RideLog.session(ctx, "navigation started")
            if (currentManeuver != Mv.UNKNOWN) leftAt[currentManeuver] = now
            currentManeuver = u.maneuver
            if (!reflip) {
                firedMask = 0
                /*
                  ★ AND THE GAP RULE RESETS WITH IT.

                  Dry-running caught this: the minimum gap was measured across
                  the boundary between two turns, so a roundabout arriving just
                  after the previous turn's "now" buzz had its FIRST warning
                  swallowed, and was announced only 15 seconds before the rider
                  had to act. The gap stops one turn being announced twice in a
                  breath; it must never stop a new turn being announced at all.
                */
                lastBuzzAtMs = 0L
            }
            lastDistM = -1              // speed carries over; the baseline cannot
            if (reflip) Log.i(TAG, "re-flip to ${Mv.name(u.maneuver)}, thresholds kept")
        }

        /*
          Measure the speed rather than assume it.

          Distance to the next turn closes at road speed, so the difference
          between two updates IS the speed, and it costs no sensor, no
          permission and no battery. Smoothed hard because Maps quantises
          distance - 10 m steps below 300 m - so a single pair of readings can
          be 12% out at a dead steady speed; measured at 14.0 m/s against a true
          12.5. Absurd values are discarded rather than smoothed in: a reroute
          or a GPS jump can make the distance leap.
        */
        if (lastDistM > 0 && u.distM in 1 until lastDistM) {
            val dt = (now - lastDistAtMs) / 1000.0
            if (dt >= 0.5) {
                val v = (lastDistM - u.distM) / dt
                if (v in MIN_MPS..MAX_MPS) {
                    speedMps = if (speedMps < MIN_MPS) v else 0.85 * speedMps + 0.15 * v
                }
            }
        }
        lastDistM = u.distM
        lastDistAtMs = now

        // Every update, not just the ones that buzz: the raw distance stream and
        // what the estimator made of it are the whole point of recording a ride.
        RideLog.line(
            ctx,
            "%-14s %5d m  v=%4.1f m/s  %s".format(
                Mv.name(u.maneuver), u.distM, speedMps, u.instruction,
            ),
        )

        if (!buzzes(u.maneuver) || u.distM <= 0) return

        val mps = if (speedMps >= MIN_MPS) speedMps else DEFAULT_MPS
        val secs = u.distM / mps

        // Fire every threshold crossed, once each. A turn that appears already
        // inside fifteen seconds trips all three at once and still buzzes
        // exactly once, which is right: there is only one thing left to say.
        var buzz = false
        val last = THRESHOLDS_S.size - 1
        for (i in THRESHOLDS_S.indices) {
            val bit = 1 shl i
            if (firedMask and bit != 0 || secs > THRESHOLDS_S[i]) continue
            firedMask = firedMask or bit
            if (i != last && lastBuzzAtMs != 0L && now - lastBuzzAtMs < MIN_GAP_MS) {
                Log.i(TAG, "  (${THRESHOLDS_S[i]}s crossed too soon after the last - silent)")
                RideLog.line(ctx, "  SILENT ${THRESHOLDS_S[i]}s suppressed by the gap rule")
                continue
            }
            buzz = true
        }
        if (!buzz) return
        lastBuzzAtMs = now

        Log.i(TAG, "%d m at %.1f m/s = %.0f s to turn".format(u.distM, mps, secs))
        RideLog.line(
            ctx,
            "BUZZ %s  %d m at %.1f m/s = %.0f s to turn".format(
                Mv.name(u.maneuver), u.distM, mps, secs,
            ),
        )
        post(ctx, headline(u.maneuver, distance(u.distM)),
             detail(u.maneuver, u.instruction), buzz = true)
    }

    @Synchronized
    fun clear(ctx: Context) {
        if (currentManeuver != Mv.UNKNOWN) RideLog.line(ctx, "navigation ended, wrist cleared")
        currentManeuver = Mv.UNKNOWN
        firedMask = 0
        lastPosted = null
        lastBuzzAtMs = 0L
        lastDistM = -1
        speedMps = 0.0
        leftAt.clear()
        if (!dryRun) runCatching { NotificationManagerCompat.from(ctx).cancel(NOTIF_ID) }
    }

    /**
     * Does the wearable REPLACE an updated notification, or stack it? Posts the
     * same id repeatedly with only the distance changing. Deliberately bypasses
     * every gate - the point is to send what the real path now suppresses.
     */
    fun stackTest(ctx: Context, cancelFirst: Boolean, count: Int, gapMs: Long) {
        ensureChannel(ctx)
        Log.i(TAG, "=== stack test: $count updates, cancelFirst=$cancelFirst ===")
        Thread {
            for (i in 0 until count) {
                val m = 500 - i * 100
                post(
                    ctx, headline(Mv.TURN_LEFT, "$m m"), detail(Mv.TURN_LEFT, "Old Madras Road"),
                    buzz = (i == 0), force = true, cancelFirst = cancelFirst,
                )
                Thread.sleep(gapMs)
            }
            Log.i(TAG, "=== stack test done (cancelFirst=$cancelFirst) ===")
        }.apply { isDaemon = true }.start()
    }

    /** Setup self-test: posts one alert exactly as a real turn would. */
    fun test(ctx: Context) {
        ensureChannel(ctx)
        Log.i(TAG, "test alert requested")
        post(ctx, headline(Mv.TURN_LEFT, "200 m"), detail(Mv.TURN_LEFT, "Old Madras Road"),
             buzz = true, force = true)
    }

    // ------------------------------------------------------------- the notice

    private fun post(
        ctx: Context,
        title: String,
        body: String,
        buzz: Boolean,
        force: Boolean = false,
        cancelFirst: Boolean = CANCEL_BEFORE_POST,
    ) {
        val text = "$title\u0000$body"
        if (!force && !buzz && text == lastPosted) return
        lastPosted = text

        if (dryRun) {
            Log.i(TAG, "    DRY  \"$title\" / \"$body\"${if (buzz) "  BUZZ" else ""}")
            return
        }

        ensureChannel(ctx)

        val tap = PendingIntent.getActivity(
            ctx, 0,
            Intent(ctx, MainActivity::class.java)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )

        val n = NotificationCompat.Builder(ctx, CHANNEL_ID)
            .setSmallIcon(android.R.drawable.ic_menu_compass)
            .setContentTitle(title)
            .setContentText(body)
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            /*
              ★ CATEGORY IS DELIBERATELY NOT SET. NAVIGATION would be the honest
              label, and that is exactly the risk: Samsung's mirroring is what we
              are trying to satisfy, and a navigation-categorised notification is
              a plausible thing for it to filter - which is the situation this
              whole file exists to work around.
            */
            .setOngoing(false)          // ongoing is what the band refuses to mirror
            .setAutoCancel(true)
            .setShowWhen(false)
            .setOnlyAlertOnce(!buzz)
            .setTimeoutAfter(TIMEOUT_MS)
            .setContentIntent(tap)
            .build()

        /*
          On 33+ POST_NOTIFICATIONS is a runtime grant and posting without it
          throws nothing - it simply does not appear, on the phone or the wrist.
          Logged because silence is the failure mode: a wrist that never buzzes
          looks identical whether the grant is missing, the band is unpaired, or
          the app is switched off in Galaxy Wearable.
        */
        runCatching {
            val nm = NotificationManagerCompat.from(ctx)
            if (cancelFirst) nm.cancel(NOTIF_ID)
            nm.notify(NOTIF_ID, n)
        }
            .onSuccess { Log.i(TAG, "posted \"$title\" / \"$body\" buzz=$buzz channel=$CHANNEL_ID") }
            .onFailure { Log.w(TAG, "post failed (POST_NOTIFICATIONS?): ${it.message}") }
    }

    private fun ensureChannel(ctx: Context) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val nm = ctx.getSystemService(NotificationManager::class.java) ?: return
        if (nm.getNotificationChannel(CHANNEL_ID) != null) return
        CHANNEL_IDS_OLD.forEach { old -> runCatching { nm.deleteNotificationChannel(old) } }

        val ch = NotificationChannel(
            CHANNEL_ID, CHANNEL_NAME, NotificationManager.IMPORTANCE_HIGH
        ).apply {
            description = "The next turn, mirrored to a wrist band while riding."
            enableVibration(true)
            /*
              ★ ONE LONG PULSE. Two short taps were tried on the rider's
              suggestion and reverted on his evidence: through a jacket sleeve
              at road speed they were "sometimes not able to feel it". A single
              sustained buzz has more energy in it and survives being felt
              through clothing, which is the only place this has to work.
            */
            vibrationPattern = longArrayOf(0, 650)
            /*
              Vibrate, but make no sound. IMPORTANCE_HIGH is what gets the
              notification mirrored promptly rather than queued, but the default
              sound that comes with it is pure cost: the phone is in a pocket
              under a jacket and the rider is in a helmet, so a chime per turn is
              heard by nobody and still wakes the screen.
            */
            setSound(null, null)
            enableLights(false)
            setShowBadge(false)
        }
        nm.createNotificationChannel(ch)
        Log.i(TAG, "channel created: $CHANNEL_NAME")
    }

    // -------------------------------------------------------------- the words

    /**
     * "Straight on" does not buzz.
     *
     * DEPART is included for the same reason: Maps draws it with the SAME icon
     * as continue-straight (NAV_DATA.md records one hash for both), it means
     * "set off along this road", and buzzing a wrist to announce that a ride has
     * started is how a band gets muted.
     */
    private fun buzzes(code: Int): Boolean =
        code != Mv.CONTINUE && code != Mv.DEPART

    /**
     * The headline, to a HARD ~10-CHARACTER BUDGET - an arrow and a distance.
     *
     * Measured twice, and the first measurement was wrong. The band's own button
     * reads "Block notificatic", seventeen characters, so 15 looked safe. It is
     * not: that button is in the BODY, which is wider. The TITLE shares its row
     * with the app icon, and photographs of a real ride showed "RIGHT 175"
     * losing its "m" and "START NOW" losing its "W". Anything longer clips or
     * marquees left-to-right, unreadable at 50 km/h through a visor.
     *
     * Everything else - sharp, keep, fork, merge, and the road name - lives in
     * detail(), where the body wraps and has room.
     */
    private fun headline(code: Int, dist: String): String {
        val d = if (dist.isEmpty()) "" else " $dist"
        return when (code) {
            Mv.TURN_LEFT, Mv.SHARP_LEFT, Mv.FORK_LEFT, Mv.EXIT_LEFT -> "$L_ARROW$d"
            Mv.TURN_RIGHT, Mv.SHARP_RIGHT, Mv.FORK_RIGHT, Mv.EXIT_RIGHT, Mv.MERGE -> "$R_ARROW$d"
            Mv.SLIGHT_LEFT, Mv.KEEP_LEFT -> "$UL_ARROW$d"
            Mv.SLIGHT_RIGHT, Mv.KEEP_RIGHT -> "$UR_ARROW$d"
            Mv.UTURN_LEFT, Mv.UTURN_RIGHT -> "$U_TURN$d"
            Mv.ROUNDABOUT -> "$RNDBT$d"
            Mv.CONTINUE, Mv.DEPART, Mv.FLYOVER, Mv.UNDERPASS -> "$UP_ARROW$d"
            Mv.DESTINATION -> "ARRIVED"
            Mv.FERRY -> "FERRY$d"
            in (Mv.ROUNDABOUT_EXIT_BASE + 1)..(Mv.ROUNDABOUT_EXIT_BASE + 15) ->
                "$RNDBT${code - Mv.ROUNDABOUT_EXIT_BASE}$d"
            else -> "?$d"
        }
    }

    /**
     * The body: what kind of turn, then the road.
     *
     * Where everything the title had to drop goes. The body wraps over several
     * lines on the band - a photograph showed "Sahodaran Ayyappan Road" across
     * two quite happily - so there is room here and none up there. The rider's
     * words: the road name is not important while riding. It keeps its place,
     * just not at the cost of the direction.
     */
    private fun detail(code: Int, road: String): String {
        val kind = when (code) {
            Mv.TURN_LEFT -> "Left"
            Mv.TURN_RIGHT -> "Right"
            Mv.SLIGHT_LEFT -> "Bear left"
            Mv.SLIGHT_RIGHT -> "Bear right"
            Mv.SHARP_LEFT -> "Sharp left"
            Mv.SHARP_RIGHT -> "Sharp right"
            Mv.KEEP_LEFT -> "Keep left"
            Mv.KEEP_RIGHT -> "Keep right"
            Mv.UTURN_LEFT, Mv.UTURN_RIGHT -> "U-turn"
            Mv.MERGE -> "Merge"
            Mv.FORK_LEFT -> "Fork left"
            Mv.FORK_RIGHT -> "Fork right"
            Mv.EXIT_LEFT -> "Exit left"
            Mv.EXIT_RIGHT -> "Exit right"
            Mv.ROUNDABOUT -> "Roundabout"
            Mv.CONTINUE -> "Straight on"
            Mv.DEPART -> "Set off"
            Mv.DESTINATION -> "Arrived"
            Mv.FLYOVER -> "Flyover"
            Mv.UNDERPASS -> "Underpass"
            Mv.FERRY -> "Ferry"
            in (Mv.ROUNDABOUT_EXIT_BASE + 1)..(Mv.ROUNDABOUT_EXIT_BASE + 15) ->
                "Roundabout, exit ${code - Mv.ROUNDABOUT_EXIT_BASE}"
            else -> "Turn"
        }
        return if (road.isBlank()) kind else "$kind · $road"
    }

    /**
     * A coarse ladder, and every step ROUNDS DOWN.
     *
     * Down, because the error then always says the turn is nearer than it is - a
     * rider who looks up early loses nothing, one who looks up late has already
     * missed it.
     *
     * ★ "NOW", NOT "0 m". Rounding down in 25 m steps turned everything under
     * 25 m into "0 m", seen on the band reading "LEFT - 0 m" while still 24
     * metres short of the junction. Zero is not a distance anywhere in this
     * project; screenFor() in nav_types.h refuses to treat it as one on the
     * handlebar for exactly the same reason.
     */
    private fun distance(m: Int): String = when {
        m >= 1000 -> "%.1f km".format(m / 1000.0)
        m >= 300 -> "${(m / 100) * 100} m"
        m >= 25 -> "${(m / 25) * 25} m"
        else -> "NOW"
    }
}
