package com.jiffytrails.navlink

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log

/**
 * Wrist alerts, driven from a terminal, so the path can be proved without
 * sitting on the bike.
 *
 * One alert:
 *
 *     adb shell am broadcast -a com.jiffytrails.navlink.TEST_WRIST \
 *         -n com.jiffytrails.navlink/.WristTestReceiver
 *
 * A whole scripted ride - five legs, every distance band, counting down:
 *
 *     adb shell am broadcast -a com.jiffytrails.navlink.TEST_RIDE \
 *         -n com.jiffytrails.navlink/.WristTestReceiver
 *     adb shell am broadcast -a com.jiffytrails.navlink.TEST_RIDE \
 *         -n com.jiffytrails.navlink/.WristTestReceiver --ei step_ms 300
 *
 * then watch what the wrist is being told:
 *
 *     adb logcat -s NAVLINK/wrist
 *
 * Does the band replace an updated notification or stack it? Run both arms
 * and count the rows on the wrist:
 *
 *     ... -a com.jiffytrails.navlink.TEST_STACK --ei cancel 0
 *     ... -a com.jiffytrails.navlink.TEST_STACK --ei cancel 1
 *
 * ★ THE RIDE DRIVES THE REAL PATH. It builds NavUpdate objects and hands them
 * to WristAlert.onUpdate(), exactly as NavListenerService does for a live
 * route. Nothing here is a special case the production code would not take, so
 * what the band does during a simulated ride is what it will do on the road.
 *
 * ★ DEBUG BUILDS ONLY, and it lives in src/debug precisely so that is
 * structural rather than a promise. The receiver has to be exported to be
 * reachable from the shell, and an exported receiver that posts notifications
 * is a surface any app on the phone could poke. Fair for a build that lands on
 * one handset; absent entirely from release, which does not contain this class
 * or its manifest entry.
 */
class WristTestReceiver : BroadcastReceiver() {

    companion object {
        private const val TAG = "NAVLINK/wrist"
        const val ACTION_ONE = "com.jiffytrails.navlink.TEST_WRIST"
        const val ACTION_RIDE = "com.jiffytrails.navlink.TEST_RIDE"
        const val ACTION_STACK = "com.jiffytrails.navlink.TEST_STACK"

        /** Fast enough to sit through, slow enough to read a wrist. */
        private const val DEFAULT_STEP_MS = 1000

        /** ~43 km/h, an honest city speed on a Speed 400. */
        private const val SPEED_MPS = 12

        @Volatile
        private var riding = false
    }

    override fun onReceive(context: Context, intent: Intent) {
        val ctx = context.applicationContext
        when (intent.action) {
            ACTION_RIDE -> ride(ctx, intent.getIntExtra("step_ms", DEFAULT_STEP_MS))
            ACTION_STACK -> WristAlert.stackTest(
                ctx,
                cancelFirst = intent.getIntExtra("cancel", 0) == 1,
                count = intent.getIntExtra("count", 5),
                gapMs = intent.getIntExtra("gap_ms", 2500).toLong(),
            )
            else -> WristAlert.test(ctx)
        }
    }

    /**
     * A real ride, in real time.
     *
     * Ticks at 1 Hz like Google Maps does, and closes the distance at a
     * genuine city speed rather than a fixed step per update - so the gaps
     * between wrist updates are the gaps a rider would actually feel, and the
     * whole thing runs about two minutes. The earlier version stepped a fixed
     * amount per tick, which made a 500 m leg take as long as a 150 m one and
     * told you nothing about pacing.
     *
     * Distances are quantised exactly as Maps quantises them (NAV_DATA.md):
     * 100 m steps above 1 km, 50 m down to 300 m, 10 m below. That is what
     * makes the digits skip at speed instead of counting smoothly, and it is
     * the input WristAlert's own band() gate has to cope with.
     *
     * It exercises every rule: DEPART and CONTINUE must stay silent, each turn
     * must buzz exactly twice, the roundabout must name its exit inside the
     * character budget, and arrival must buzz once and then clear the wrist.
     */
    private fun ride(ctx: Context, stepMs: Int) {
        if (riding) {
            Log.i(TAG, "ride already running, ignoring")
            return
        }
        riding = true

        // The foreground service keeps this process alive, so a plain thread
        // outlives the broadcast. Returning immediately keeps the receiver
        // inside its window.
        Thread {
            try {
                Log.i(TAG, "=== ride starting: ${SPEED_MPS * 36 / 10} km/h, ${stepMs} ms tick ===")
                val legs = listOf(
                    Triple(Mv.DEPART, "Panampilly Nagar", 150),
                    Triple(Mv.TURN_RIGHT, "Sahodaran Ayyappan Road", 350),
                    Triple(Mv.roundaboutExit(2), "Kundannoor Junction", 300),
                    Triple(Mv.TURN_LEFT, "Old Madras Road", 250),
                    Triple(Mv.SLIGHT_RIGHT, "Marine Drive", 200),
                )

                var remaining = legs.sumOf { it.third }
                for ((maneuver, road, length) in legs) {
                    var d = length
                    while (d > 0) {
                        WristAlert.onUpdate(
                            ctx,
                            NavUpdate(
                                maneuver = maneuver,
                                distM = quantise(d),
                                instruction = road,
                                navActive = true,
                                etaMin = (remaining / (SPEED_MPS * 60)).coerceAtLeast(1),
                                remaining100m = remaining / 100,
                            ),
                        )
                        Thread.sleep(stepMs.toLong())
                        d -= SPEED_MPS
                        remaining -= SPEED_MPS
                    }
                }

                WristAlert.onUpdate(
                    ctx,
                    NavUpdate(
                        maneuver = Mv.DESTINATION,
                        distM = 0,
                        instruction = "Marine Drive",
                        navActive = true,
                        arrived = true,
                    ),
                )
                Thread.sleep(5000)

                // End of route, exactly as the parser emits it. The wrist must
                // go clear rather than hold the last turn.
                WristAlert.onUpdate(ctx, NavUpdate(navActive = false))
                Log.i(TAG, "=== ride finished, wrist cleared ===")
            } catch (t: Throwable) {
                Log.w(TAG, "ride aborted: ${t.message}")
            } finally {
                riding = false
            }
        }.apply { isDaemon = true }.start()
    }

    /** Maps' own distance ladder - see NAV_DATA.md. */
    private fun quantise(m: Int): Int = when {
        m > 1000 -> (m / 100) * 100
        m > 300 -> (m / 50) * 50
        else -> (m / 10) * 10
    }
}
