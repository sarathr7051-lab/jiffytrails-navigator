package com.jiffytrails.navlink

import android.app.Notification
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
 * Why this exists at all: the Galaxy Fit3 mirrors normal notifications and
 * nothing else. Google Maps' navigation notification is an ongoing/live one, so
 * Maps does not even appear in Galaxy Wearable's per-app list — there is no
 * setting to turn on, and no amount of configuration will produce one. NavLink
 * already parses every turn for the handlebar display, so the cheapest path to
 * a wrist buzz is for NavLink to post its own plain notification that the band
 * is willing to mirror.
 *
 * ★ THIS IS A BACKUP PATH AND MUST BEHAVE LIKE ONE.
 *
 * The handlebar display is the primary instrument. Everything here is called
 * AFTER the BLE write and wrapped by the caller, so a failure in this file can
 * never delay or break the display. If the two ever disagree, the display is
 * right: it carries the exact distance, this rounds.
 *
 * ★ THE BATTERY RULE, WHICH SHAPES MOST OF THE DESIGN
 *
 * The band is charged about once a week and its notification list is kept
 * deliberately short. Every buzz and every silent update is a Bluetooth packet
 * to the wrist, so:
 *
 *   - at most TWO buzzes per maneuver: once when the turn becomes the next one,
 *     and once when it first comes inside BUZZ_NEAR_M;
 *   - "straight on" never buzzes at all;
 *   - the text is re-posted only when the words would actually change, which is
 *     why the distance is shown on a coarse ladder rather than at the 10 m
 *     granularity Maps gives below 300 m. At 10 m steps the last 300 m of every
 *     leg would be thirty wrist updates.
 *
 * ★ WHAT IT REFUSES TO SAY
 *
 * Maps' stream is noisy in three specific ways, all of them recorded in
 * docs/NAV_DATA.md, and each one would otherwise reach the wrist as a spurious
 * buzz:
 *
 *   - `progressMax` drifts (851 -> 1196 -> 804 observed in one journey). Nothing
 *     here reads it. The band is told about the next maneuver and its distance,
 *     never about distance remaining, so the drift has nothing to land on.
 *   - UNKNOWN maneuvers and `rerouting` blips arrive mid-route. Both leave the
 *     wrist showing whatever it already had rather than guessing - the same rule
 *     the display follows, for the same reason: a confidently wrong arrow is
 *     worse than no arrow.
 *   - Maps flips between two maneuvers and back within a few seconds. Returning
 *     to a maneuver that was current less than REFLIP_MS ago updates the text
 *     but does not buzz again.
 */
object WristAlert {

    private const val TAG = "NAVLINK/wrist"

    /** Shown to the user in Settings and in Galaxy Wearable's per-app list. */
    const val CHANNEL_ID = "wrist_turns"
    const val CHANNEL_NAME = "Wrist turn alerts"

    /**
     * One id, reused forever. The wrist must hold exactly one turn - the
     * current one - and posting under a fresh id per maneuver would leave a
     * scrollable history of turns already taken on the band.
     */
    const val NOTIF_ID = 0x5731

    private const val PREFS = "navlink"
    private const val KEY_ENABLED = "wrist_alerts_enabled"

    /** The second buzz: the turn is close enough to act on. */
    private const val BUZZ_NEAR_M = 200

    /** A maneuver seen again within this window is a Maps flicker, not a turn. */
    private const val REFLIP_MS = 20_000L

    /**
     * Android removes the notification itself after this.
     *
     * The failure this guards is specific: if the app is killed, the phone
     * loses the listener, or the ride simply ends without a clean
     * nav_active = 0, a stale turn would otherwise sit on the wrist
     * indefinitely. Sixty seconds is longer than any gap between Maps updates
     * on a live route and short enough that a dead route clears itself.
     */
    private const val TIMEOUT_MS = 60_000L

    // ------------------------------------------------------------------ state

    private var currentManeuver = Mv.UNKNOWN
    private var buzzedNear = false
    private var lastPosted: String? = null

    /** maneuver code -> elapsedRealtime when it stopped being current. */
    private val leftAt = HashMap<Int, Long>()

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
     * Synchronized because the notification listener's callbacks and the 1 Hz
     * poller are not guaranteed to be the same thread, and the re-flip and
     * once-only rules below are all read-modify-write on shared state.
     */
    @Synchronized
    fun onUpdate(ctx: Context, u: NavUpdate) {
        if (!isEnabled(ctx)) return

        // End of route. Covers both the explicit nav_active = 0 the parser
        // emits and a route that simply stops being active.
        if (!u.navActive) {
            clear(ctx)
            return
        }

        if (u.arrived) {
            if (currentManeuver != Mv.DESTINATION) {
                currentManeuver = Mv.DESTINATION
                buzzedNear = true          // nothing closer to announce
                post(ctx, "ARRIVED", u.instruction, buzz = true)
            }
            return
        }

        // Hold, do not guess. Both of these are transient and the wrist keeps
        // the last true thing it was told.
        if (u.rerouting) return
        if (u.maneuver == Mv.UNKNOWN) return

        val now = SystemClock.elapsedRealtime()
        var buzz = false

        if (u.maneuver != currentManeuver) {
            val wasCurrentAt = leftAt[u.maneuver]
            val reflip = wasCurrentAt != null && now - wasCurrentAt < REFLIP_MS

            if (currentManeuver != Mv.UNKNOWN) leftAt[currentManeuver] = now
            currentManeuver = u.maneuver
            buzzedNear = false

            buzz = !reflip && buzzes(u.maneuver)
            if (reflip) Log.i(TAG, "re-flip to ${Mv.name(u.maneuver)}, text only")
        }

        // The close-approach buzz, once per maneuver. Guarded on distM > 0
        // because Maps reports "0 m" whenever the next maneuver is where you
        // already are - most obviously at departure, with kilometres still to
        // run. The display learned this the same way; see screenFor() in
        // nav_types.h.
        if (!buzzedNear && u.distM in 1 until BUZZ_NEAR_M && buzzes(u.maneuver)) {
            buzzedNear = true
            buzz = true
        }

        post(ctx, "${plainName(u.maneuver)} · ${distance(u.distM)}", u.instruction, buzz)
    }

    @Synchronized
    fun clear(ctx: Context) {
        currentManeuver = Mv.UNKNOWN
        buzzedNear = false
        lastPosted = null
        leftAt.clear()
        runCatching { NotificationManagerCompat.from(ctx).cancel(NOTIF_ID) }
    }

    /** Setup self-test: posts one alert exactly as a real turn would. */
    fun test(ctx: Context) {
        ensureChannel(ctx)
        Log.i(TAG, "test alert requested")
        post(ctx, "LEFT · 200 m", "Old Madras Road", buzz = true, force = true)
    }

    // ------------------------------------------------------------- the notice

    private fun post(
        ctx: Context,
        title: String,
        body: String,
        buzz: Boolean,
        force: Boolean = false,
    ) {
        val text = "$title\u0000$body"

        // Re-posting identical words costs a Bluetooth packet to the wrist and
        // buys nothing. A buzz always goes out, because that is the event.
        if (!force && !buzz && text == lastPosted) return
        lastPosted = text

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
              ★ CATEGORY IS DELIBERATELY NOT SET.

              NAVIGATION would be the honest label, and that is exactly the risk:
              Samsung's mirroring is what we are trying to satisfy, and a
              navigation-categorised notification is a plausible thing for it to
              filter out - which is the situation this whole file exists to work
              around. An uncategorised notification is the most ordinary thing
              the band can be handed.
            */
            .setOngoing(false)          // ongoing is what the band refuses to mirror
            .setAutoCancel(true)
            .setShowWhen(false)         // a clock on a wrist that has one already
            .setOnlyAlertOnce(!buzz)    // false = buzz now; true = update in place
            .setTimeoutAfter(TIMEOUT_MS)
            .setContentIntent(tap)
            .build()

        /*
          On 33+ POST_NOTIFICATIONS is a runtime grant and posting without it
          throws nothing - it simply does not appear, on the phone or the wrist.
          Caught and logged because silence is the failure mode: a wrist that
          never buzzes looks identical whether the grant is missing, the band is
          not paired, or the app in Galaxy Wearable is switched off.
        */
        runCatching { NotificationManagerCompat.from(ctx).notify(NOTIF_ID, n) }
            .onSuccess {
                Log.i(TAG, "posted \"$title\" / \"$body\" buzz=$buzz channel=$CHANNEL_ID")
            }
            .onFailure { Log.w(TAG, "post failed (POST_NOTIFICATIONS?): ${it.message}") }
    }

    private fun ensureChannel(ctx: Context) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val nm = ctx.getSystemService(NotificationManager::class.java) ?: return
        if (nm.getNotificationChannel(CHANNEL_ID) != null) return

        val ch = NotificationChannel(
            CHANNEL_ID, CHANNEL_NAME, NotificationManager.IMPORTANCE_HIGH
        ).apply {
            description = "The next turn, mirrored to a wrist band while riding."
            enableVibration(true)
            /*
              Vibrate, but do not make a sound.

              IMPORTANCE_HIGH is what gets the notification mirrored promptly and
              buzzed rather than queued silently. The default sound that normally
              comes with it is pure cost here: the phone is in a pocket under a
              jacket and the rider is wearing a helmet, so a chime per turn is
              heard by nobody and still wakes the screen. One line to change if
              it is ever wanted.
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
     * "set off along this road", and buzzing a wrist to announce that the ride
     * has started is the kind of notification that gets a band muted.
     */
    private fun buzzes(code: Int): Boolean =
        code != Mv.CONTINUE && code != Mv.DEPART

    /**
     * Plain words, not protocol names. The band has one small line and the
     * rider has one glance; `Mv.name()` is for logs and says "TURN_LEFT".
     */
    private fun plainName(code: Int): String = when (code) {
        Mv.TURN_LEFT -> "LEFT"
        Mv.TURN_RIGHT -> "RIGHT"
        Mv.SLIGHT_LEFT -> "BEAR LEFT"
        Mv.SLIGHT_RIGHT -> "BEAR RIGHT"
        Mv.SHARP_LEFT -> "SHARP LEFT"
        Mv.SHARP_RIGHT -> "SHARP RIGHT"
        Mv.KEEP_LEFT -> "KEEP LEFT"
        Mv.KEEP_RIGHT -> "KEEP RIGHT"
        Mv.UTURN_LEFT, Mv.UTURN_RIGHT -> "U-TURN"
        Mv.MERGE -> "MERGE"
        Mv.FORK_LEFT -> "FORK LEFT"
        Mv.FORK_RIGHT -> "FORK RIGHT"
        Mv.EXIT_LEFT -> "EXIT LEFT"
        Mv.EXIT_RIGHT -> "EXIT RIGHT"
        Mv.ROUNDABOUT -> "ROUNDABOUT"
        Mv.FLYOVER -> "FLYOVER"
        Mv.UNDERPASS -> "UNDERPASS"
        Mv.DESTINATION -> "ARRIVE"
        Mv.FERRY -> "FERRY"
        Mv.CONTINUE -> "STRAIGHT ON"
        Mv.DEPART -> "SET OFF"
        in (Mv.ROUNDABOUT_EXIT_BASE + 1)..(Mv.ROUNDABOUT_EXIT_BASE + 15) ->
            "ROUNDABOUT, EXIT ${code - Mv.ROUNDABOUT_EXIT_BASE}"
        else -> "TURN"
    }

    /**
     * A coarse ladder, and every step ROUNDS DOWN.
     *
     * Two reasons for the coarseness, one for the direction. Coarse because
     * each distinct string is a wrist update and Maps gives 10 m steps below
     * 300 m, which would be thirty of them per leg. Down, because the error
     * then always says the turn is nearer than it is - a rider who looks up
     * early loses nothing, and one who looks up late has already missed it.
     */
    private fun distance(m: Int): String = when {
        m >= 1000 -> "%.1f km".format(m / 1000.0)
        m >= 300 -> "${(m / 100) * 100} m"
        else -> "${(m / 25) * 25} m"
    }
}
