package com.jiffytrails.navdump

import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.drawable.Drawable
import android.graphics.drawable.Icon
import android.os.Bundle
import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification
import android.util.Log
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/**
 * v3 — built for reading a real ride afterwards.
 *
 * The problem with v2 on the road: ~60 lines per second is unreadable. So v3
 * emits one compact SUM line per update, and a full dump only when something
 * structurally new happens (new keys appear, or any icon changes). That makes
 * the distance countdown and the maneuver changes visible at a glance.
 *
 *   SUM 19:41:36.4 | 350 m | Turn right onto Horamavu Agara Rd
 *                  | towards 1st Cross Rd | Arrive 8:00 pm | 1203/4603 | chip=a1b2c3d4
 *
 * Also: only cat=navigation is logged, icons are rendered at 32px for better
 * discrimination between similar arrows, and where Maps ships an icon as a
 * resource we resolve its actual name (e.g. ic_maneuver_turn_right), which is
 * far more robust than a pixel hash.
 */
class NavDumpService : NotificationListenerService() {

    companion object {
        const val TAG = "NAVDUMP"

        private val WATCHED = setOf(
            "com.google.android.apps.maps",
            "net.osmand",
            "net.osmand.plus",
            "app.organicmaps"
        )

        private val TIME = SimpleDateFormat("HH:mm:ss.S", Locale.US)
        private const val ART_N = 32
        private const val RAMP = " .:-=+*#%@"

        // Keys we pull out for the compact summary line.
        private const val K_PRIMARY   = "android.ongoingActivityNoti.primaryInfo"
        private const val K_SECONDARY = "android.ongoingActivityNoti.secondaryInfo"
        private const val K_CHIP_TEXT = "android.ongoingActivityNoti.chipExpandedText"
        private const val K_CHIP_ICON = "android.ongoingActivityNoti.chipIcon"
        private const val K_NOWBAR_IC = "android.ongoingActivityNoti.nowbarIcon"
        private const val K_SECOND_IC = "android.ongoingActivityNoti.secondIcon"
        private const val K_TITLE     = "android.title"
        private const val K_SUBTEXT   = "android.subText"
        private const val K_PROGRESS  = "android.progress"
        private const val K_PROG_MAX  = "android.progressMax"

        /** Force a full dump at least this often, as a checkpoint. */
        private const val FULL_DUMP_INTERVAL_MS = 60_000L
    }

    private val seenIcons = HashSet<String>()
    private var lastKeySet: String? = null
    private var lastIconSig: String? = null
    private var lastSumLine: String? = null
    private var lastFullDumpAt = 0L

    override fun onListenerConnected() {
        seenIcons.clear()
        lastKeySet = null
        lastIconSig = null
        lastSumLine = null
        lastFullDumpAt = 0L
        emit("=== listener connected at ${TIME.format(Date())} ===")
    }

    override fun onNotificationPosted(sbn: StatusBarNotification) {
        if (sbn.packageName !in WATCHED) return
        val n = sbn.notification
        val ex = n.extras ?: return

        // Only real turn-by-turn. Kills traffic alerts and the Samsung
        // "Aggregate_NormalNotificationSection" wrapper in one go.
        if (n.category != "navigation") return

        val now = System.currentTimeMillis()

        // ----- icon signature -----
        val chip   = iconOf(ex, K_CHIP_ICON)
        val nowbar = iconOf(ex, K_NOWBAR_IC)
        val second = iconOf(ex, K_SECOND_IC)
        val chipH   = idOf(chip)
        val nowbarH = idOf(nowbar)
        val secondH = idOf(second)
        val iconSig = "$chipH|$nowbarH|$secondH|${idOf(n.smallIcon)}|${idOf(n.getLargeIcon())}"

        // ----- compact summary -----
        val sum = buildString {
            append("SUM ").append(TIME.format(Date()))
            append(" | ").append(str(ex, K_PRIMARY))
            append(" | ").append(str(ex, K_TITLE))
            append(" | ").append(str(ex, K_SECONDARY))
            append(" | ").append(str(ex, K_SUBTEXT))
            append(" | ").append(num(ex, K_PROGRESS)).append('/').append(num(ex, K_PROG_MAX))
            append(" | chip=").append(chipH)
            if (nowbarH != chipH) append(" nowbar=").append(nowbarH)
            if (secondH != chipH) append(" second=").append(secondH)
            val ct = str(ex, K_CHIP_TEXT)
            if (ct != str(ex, K_PRIMARY)) append(" chipText=").append(ct)
        }

        // ----- decide: summary only, or full dump too? -----
        val keySet = ex.keySet().sorted().joinToString(",")
        val structuralChange = keySet != lastKeySet || iconSig != lastIconSig
        val checkpointDue = now - lastFullDumpAt > FULL_DUMP_INTERVAL_MS

        if (sum == lastSumLine && !structuralChange) return
        lastSumLine = sum

        if (structuralChange || checkpointDue) {
            lastKeySet = keySet
            lastIconSig = iconSig
            lastFullDumpAt = now

            val out = StringBuilder()
            out.append("--- FULL ").append(TIME.format(Date()))
                .append("  id=").append(sbn.id)
                .append("  cat=").append(n.category ?: "-")
                .append(if (structuralChange) "  [structure/icon changed]" else "  [checkpoint]")
                .append('\n')
            for (key in ex.keySet().sorted()) {
                @Suppress("DEPRECATION")
                val v = try { ex.get(key) } catch (t: Throwable) { "<read error>" }
                dump(out, "  ", key, v)
            }
            dump(out, "  ", "smallIcon", n.smallIcon)
            dump(out, "  ", "largeIcon", n.getLargeIcon())
            emit(out.toString())
        }

        emit(sum)
    }

    override fun onNotificationRemoved(sbn: StatusBarNotification) {
        if (sbn.packageName !in WATCHED) return
        if (sbn.notification?.category != "navigation") return
        lastSumLine = null
        lastKeySet = null
        emit("--- ${TIME.format(Date())}  NAVIGATION ENDED (notification removed)")
    }

    private fun emit(s: String) {
        Log.d(TAG, s)
        NavLog.append(applicationContext, s)
    }

    // ----- small helpers for the summary line -----

    private fun str(ex: Bundle, key: String): String = try {
        @Suppress("DEPRECATION")
        (ex.get(key) as? CharSequence)?.toString() ?: "-"
    } catch (t: Throwable) { "-" }

    private fun num(ex: Bundle, key: String): String = try {
        @Suppress("DEPRECATION")
        ex.get(key)?.toString() ?: "-"
    } catch (t: Throwable) { "-" }

    private fun iconOf(ex: Bundle, key: String): Icon? = try {
        @Suppress("DEPRECATION")
        ex.get(key) as? Icon
    } catch (t: Throwable) { null }

    /**
     * Prefers the resource name over a pixel hash. If Maps ships the arrow as
     * a resource we get something like "ic_maneuver_turn_right", which won't
     * break when Google redraws the artwork.
     */
    private fun idOf(icon: Icon?): String {
        if (icon == null) return "null"
        resName(icon)?.let { return it }
        return render(icon).first
    }

    private fun resName(icon: Icon): String? = try {
        if (icon.type != 2) null else {
            val resId = Icon::class.java.getMethod("getResId").invoke(icon) as Int
            val pkg = Icon::class.java.getMethod("getResPackage").invoke(icon) as? String
            val res = if (pkg.isNullOrEmpty()) resources
            else packageManager.getResourcesForApplication(pkg)
            res.getResourceEntryName(resId)
        }
    } catch (t: Throwable) { null }

    // ----- recursive full dump -----

    private fun dump(out: StringBuilder, indent: String, key: String, v: Any?) {
        when (v) {
            null -> out.append(indent).append(key).append(" = null\n")

            is Icon -> {
                val name = resName(v)
                val (hash, art) = render(v)
                out.append(indent).append(key)
                    .append(" = Icon(type=").append(v.type).append(") ")
                    .append(if (name != null) "res=$name " else "")
                    .append("hash=").append(hash).append('\n')
                if (seenIcons.add(hash)) out.append(art)
            }

            is Bundle -> {
                out.append(indent).append(key).append(" = Bundle {\n")
                try {
                    v.classLoader = javaClass.classLoader
                    for (k in v.keySet().sorted()) {
                        @Suppress("DEPRECATION")
                        val inner = try { v.get(k) } catch (t: Throwable) { "<err>" }
                        dump(out, "$indent    ", k, inner)
                    }
                } catch (t: Throwable) {
                    out.append(indent).append("    <unparcel failed>\n")
                }
                out.append(indent).append("}\n")
            }

            is Array<*> -> {
                out.append(indent).append(key).append(" = [\n")
                v.forEachIndexed { i, item -> dump(out, "$indent    ", "[$i]", item) }
                out.append(indent).append("]\n")
            }

            is List<*> -> {
                out.append(indent).append(key).append(" = [\n")
                v.forEachIndexed { i, item -> dump(out, "$indent    ", "[$i]", item) }
                out.append(indent).append("]\n")
            }

            is Bitmap -> out.append(indent).append(key)
                .append(" = Bitmap(").append(v.width).append('x').append(v.height).append(")\n")

            is CharSequence -> out.append(indent).append(key)
                .append(" = \"").append(v.toString().replace("\n", "\\n")).append("\"\n")

            else -> out.append(indent).append(key).append(" = ").append(v.toString()).append('\n')
        }
    }

    // ----- icon rendering -----

    private fun render(icon: Icon?): Pair<String, String> {
        if (icon == null) return "null" to ""
        return try {
            val d: Drawable = icon.loadDrawable(applicationContext)
                ?: return "no-drawable" to ""
            val bmp = Bitmap.createBitmap(ART_N, ART_N, Bitmap.Config.ARGB_8888)
            d.setBounds(0, 0, ART_N, ART_N)
            d.draw(Canvas(bmp))

            var hash = 17
            val art = StringBuilder()
            for (y in 0 until ART_N) {
                art.append("      |")
                for (x in 0 until ART_N) {
                    val a = Color.alpha(bmp.getPixel(x, y))
                    hash = hash * 31 + (a shr 5)
                    art.append(RAMP[a * (RAMP.length - 1) / 255])
                }
                art.append("|\n")
            }
            bmp.recycle()
            Integer.toHexString(hash) to art.toString()
        } catch (t: Throwable) {
            "err" to "      <icon error: ${t.message}>\n"
        }
    }
}
