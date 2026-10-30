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
        const val ACTION_SCENARIOS = "com.jiffytrails.navlink.TEST_SCENARIOS"

        /** Fast enough to sit through, slow enough to read a wrist. */
        private const val DEFAULT_STEP_MS = 1000

        /** An honest city speed on a Speed 400; override with --ei kmh. */
        private const val DEFAULT_KMH = 45

        @Volatile
        private var riding = false
    }

    override fun onReceive(context: Context, intent: Intent) {
        val ctx = context.applicationContext
        when (intent.action) {
            ACTION_RIDE -> ride(
                ctx,
                intent.getIntExtra("step_ms", DEFAULT_STEP_MS),
                intent.getIntExtra("kmh", DEFAULT_KMH),
            )
            ACTION_SCENARIOS -> scenarios(ctx)
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
    private fun ride(ctx: Context, stepMs: Int, kmh: Int) {
        val mps = kmh / 3.6          // metres closed per 1 Hz tick
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
                Log.i(TAG, "=== ride starting: $kmh km/h, ${stepMs} ms tick ===")
                /*
                  Honest city spacing: turns a few hundred metres to most of a
                  kilometre apart, not the every-250-metres of a demo. The
                  900 m leg is there on purpose - it is the longest realistic
                  gap between the "next turn is a left" buzz and the "it is now"
                  buzz, and the one that shows whether two buzzes per turn
                  leaves too long a silence in the middle.
                */
                val legs = listOf(
                    Triple(Mv.DEPART, "Panampilly Nagar", 200),
                    Triple(Mv.TURN_RIGHT, "Sahodaran Ayyappan Road", 600),
                    Triple(Mv.TURN_LEFT, "Old Madras Road", 900),
                    Triple(Mv.roundaboutExit(2), "Kundannoor Junction", 500),
                )

                var remaining = legs.sumOf { it.third }.toDouble()
                for ((maneuver, road, length) in legs) {
                    var d = length.toDouble()
                    while (d > 0) {
                        WristAlert.onUpdate(
                            ctx,
                            NavUpdate(
                                maneuver = maneuver,
                                distM = quantise(d.toInt()),
                                instruction = road,
                                navActive = true,
                                etaMin = (remaining / (mps * 60)).toInt().coerceAtLeast(1),
                                remaining100m = (remaining / 100).toInt(),
                            ),
                        )
                        Thread.sleep(stepMs.toLong())
                        d -= mps
                        remaining -= mps
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

    /**
     * Every scenario, played through the REAL decision logic, posting nothing.
     *
     * The clock is advanced by hand rather than waited on, so twenty minutes
     * of riding takes a millisecond and the whole set can be re-run after every
     * tweak to the thresholds. What it is checking is not that code runs, but
     * that a rider gets a useful amount of warning at every speed they might
     * actually be doing - including the ones that break a distance-based rule:
     * a jam, an open road, and a turn that appears when it is already close.
     */
    private fun scenarios(ctx: Context) {
        Thread {
            WristAlert.dryRun = true
            var t = 0L
            WristAlert.clock = { t }
            try {
                data class Leg(val mv: Int, val road: String, val m: Int)

                fun run(name: String, kmhAt: (Int) -> Double, legs: List<Leg>) {
                    WristAlert.clear(ctx)
                    t += 60_000
                    Log.i(TAG, "")
                    Log.i(TAG, "######## $name")
                    var tick = 0
                    for (leg in legs) {
                        var d = leg.m.toDouble()
                        var guard = 0
                        while (d > 0 && guard++ < 4000) {
                            val kmh = kmhAt(tick)
                            WristAlert.onUpdate(
                                ctx,
                                NavUpdate(
                                    maneuver = leg.mv, distM = quantise(d.toInt()),
                                    instruction = leg.road, navActive = true,
                                ),
                            )
                            t += 1000
                            tick++
                            d -= kmh / 3.6
                        }
                    }
                    WristAlert.onUpdate(ctx, NavUpdate(navActive = false))
                }

                val city = listOf(
                    Leg(Mv.DEPART, "Panampilly Nagar", 200),
                    Leg(Mv.TURN_RIGHT, "Sahodaran Ayyappan Road", 600),
                    Leg(Mv.TURN_LEFT, "Old Madras Road", 900),
                    Leg(Mv.roundaboutExit(2), "Kundannoor Junction", 500),
                )

                run("STEADY 45 km/h", { 45.0 }, city)
                run("SLOW CITY 18 km/h - traffic", { 18.0 }, city)
                run("OPEN ROAD 70 km/h", { 70.0 }, city)
                run("ACCELERATING 20 -> 65 km/h", { i -> (20 + i * 0.4).coerceAtMost(65.0) }, city)
                run("STOP-START - lights every 40 s", { i -> if ((i / 40) % 2 == 0) 35.0 else 2.0 }, city)
                run("TURN APPEARS CLOSE - 150 m at 50 km/h", { 50.0 }, listOf(
                    Leg(Mv.TURN_LEFT, "Chittoor Road", 150),
                    Leg(Mv.TURN_RIGHT, "Banerji Road", 1800),
                ))
                run("LONG GAP - 3 km between turns at 55 km/h", { 55.0 }, listOf(
                    Leg(Mv.TURN_RIGHT, "NH 66", 3000),
                    Leg(Mv.TURN_LEFT, "Seaport Airport Road", 700),
                ))
                Log.i(TAG, "######## scenarios done")
            } catch (e: Throwable) {
                Log.w(TAG, "scenarios failed: ${e.message}")
            } finally {
                WristAlert.clock = { android.os.SystemClock.elapsedRealtime() }
                WristAlert.dryRun = false
                WristAlert.clear(ctx)
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
