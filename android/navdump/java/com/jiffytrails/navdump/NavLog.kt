package com.jiffytrails.navdump

import android.content.Context
import java.io.File

/**
 * Keeps the last N entries in memory for the UI, and appends everything to a
 * file so you can review a whole ride afterwards.
 *
 * File lives at:
 *   /sdcard/Android/data/com.jiffytrails.navdump/files/navdump.log
 *
 * Pull it with:
 *   adb pull /sdcard/Android/data/com.jiffytrails.navdump/files/navdump.log
 */
object NavLog {

    private const val MAX_ENTRIES = 3000
    private const val FILENAME = "navdump.log"

    private val buf = ArrayDeque<String>()

    @Volatile
    var listener: ((String) -> Unit)? = null

    @Synchronized
    fun append(ctx: Context, text: String) {
        buf.addLast(text)
        while (buf.size > MAX_ENTRIES) buf.removeFirst()
        try {
            File(ctx.getExternalFilesDir(null), FILENAME).appendText(text + "\n")
        } catch (_: Throwable) {
            // logging must never crash the listener
        }
        listener?.invoke(text)
    }

    @Synchronized
    fun snapshot(): String = buf.joinToString("\n")

    @Synchronized
    fun clear(ctx: Context) {
        buf.clear()
        try {
            File(ctx.getExternalFilesDir(null), FILENAME).delete()
        } catch (_: Throwable) {
        }
    }

    fun logPath(ctx: Context): String =
        File(ctx.getExternalFilesDir(null), FILENAME).absolutePath
}
