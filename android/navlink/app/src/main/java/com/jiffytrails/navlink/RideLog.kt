package com.jiffytrails.navlink

import android.content.Context
import android.util.Log
import java.io.File
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/**
 * A log of what the wrist was actually told, written to the phone rather than
 * to logcat.
 *
 * WHY THIS EXISTS, measured rather than assumed: this handset keeps about
 * ELEVEN MINUTES of logcat. 178,000 lines in a 5 MiB ring buffer that Samsung
 * caps - `logcat -G 64M` is refused - and roughly 16,000 lines a minute from
 * the rest of the system. Our own lines from an evening of testing were gone
 * by the time we looked, and `logpersist` is stripped on this firmware. So a
 * ride read back afterwards over adb would show nothing at all.
 *
 * That matters because every number in WristAlert - the 120/60/30/12 second
 * warnings, the gap rule, and above all the speed estimate - was tuned against
 * a simulator. None of it has ever seen real Google Maps output on a real road.
 * This file is the only way the first real ride tells us anything more precise
 * than "it felt off somewhere".
 *
 * It is deliberately dumb and cannot disturb the thing it measures:
 *
 *   - append-only, one short line per update, opened and closed per write, so
 *     there is no handle to leak and nothing buffered to lose if the process
 *     dies mid-ride;
 *   - every call wrapped, so a full disk or a revoked directory logs a warning
 *     and returns instead of throwing into the alert path;
 *   - size-capped, so a forgotten navigation session cannot fill the phone;
 *   - silent during a dry run, so the scenario harness still costs nothing.
 *
 * Private storage, so it needs no permission and no sdcard. Pull it with:
 *
 *     adb exec-out run-as com.jiffytrails.navlink cat files/ride-log.txt
 */
object RideLog {

    private const val TAG = "NAVLINK/wrist"
    private const val NAME = "ride-log.txt"

    /** About fifteen hours of 1 Hz navigation. A ride is well under a megabyte. */
    private const val MAX_BYTES = 4L * 1024 * 1024

    private val stamp = SimpleDateFormat("MM-dd HH:mm:ss.SSS", Locale.UK)

    @Volatile
    private var full = false

    fun line(ctx: Context, text: String) {
        if (WristAlert.dryRun) return
        runCatching {
            val f = File(ctx.filesDir, NAME)
            if (f.length() > MAX_BYTES) {
                if (!full) {
                    full = true
                    Log.w(TAG, "ride log full at ${f.length()} bytes - no longer recording")
                }
                return
            }
            f.appendText("${stamp.format(Date())}  $text\n")
        }.onFailure {
            // Never twice: a failing disk would otherwise log once per second.
            if (!full) {
                full = true
                Log.w(TAG, "ride log unavailable: ${it.message}")
            }
        }
    }

    /** Marks a boundary so separate rides are told apart in one file. */
    fun session(ctx: Context, why: String) {
        full = false
        line(ctx, "---- $why ----")
    }

    fun path(ctx: Context): String = File(ctx.filesDir, NAME).absolutePath
}
