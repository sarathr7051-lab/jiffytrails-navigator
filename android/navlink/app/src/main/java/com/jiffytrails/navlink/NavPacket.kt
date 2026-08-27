package com.jiffytrails.navlink

/**
 * Wire format for the handlebar device. The authority is docs/BLE_PROTOCOL.md;
 * keep this in step with it and with firmware/navigator/nav_types.h.
 *
 * Framing is [type:u8][len:u8][payload...], little-endian, where **len is the
 * PAYLOAD length excluding the two header bytes**. That is load-bearing: the
 * NAV instruction has no terminator, so the device derives its extent as len
 * minus the 11-byte fixed block.
 *
 * The firmware treats len as advisory and bounds every read by the actual ATT
 * write length, so a miscount degrades rather than corrupts. Send it correctly
 * anyway.
 */
object Pkt {
    const val NAV = 0x01
    const val STATUS = 0x02
    const val CALL = 0x03
    const val MEDIA = 0x04
    const val TRIP = 0x05
    const val CONFIG = 0x06
    const val TRAFFIC = 0x07
    const val NOTIFY = 0x08
}

/** Maneuver codes. 0x20-0x2F is reserved for roundabout exit N. */
object Mv {
    const val UNKNOWN = 0x00        // renders "?" - never guess an arrow
    const val CONTINUE = 0x01
    const val TURN_LEFT = 0x02
    const val TURN_RIGHT = 0x03
    const val SLIGHT_LEFT = 0x04
    const val SLIGHT_RIGHT = 0x05
    const val SHARP_LEFT = 0x06
    const val SHARP_RIGHT = 0x07
    const val KEEP_LEFT = 0x08
    const val KEEP_RIGHT = 0x09
    const val UTURN_LEFT = 0x0A
    const val UTURN_RIGHT = 0x0B
    const val MERGE = 0x0C
    const val FORK_LEFT = 0x0D
    const val FORK_RIGHT = 0x0E
    const val EXIT_LEFT = 0x0F
    const val EXIT_RIGHT = 0x10
    const val ROUNDABOUT = 0x11
    const val FLYOVER = 0x12
    const val UNDERPASS = 0x13
    const val DESTINATION = 0x14
    const val FERRY = 0x15
    const val ROUNDABOUT_EXIT_BASE = 0x20

    fun roundaboutExit(n: Int): Int =
        if (n in 1..15) ROUNDABOUT_EXIT_BASE + n else ROUNDABOUT

    /** For logging. The device draws glyphs; this is for humans. */
    fun name(code: Int): String = when (code) {
        CONTINUE -> "CONTINUE"; TURN_LEFT -> "TURN_LEFT"; TURN_RIGHT -> "TURN_RIGHT"
        SLIGHT_LEFT -> "SLIGHT_LEFT"; SLIGHT_RIGHT -> "SLIGHT_RIGHT"
        SHARP_LEFT -> "SHARP_LEFT"; SHARP_RIGHT -> "SHARP_RIGHT"
        KEEP_LEFT -> "KEEP_LEFT"; KEEP_RIGHT -> "KEEP_RIGHT"
        UTURN_LEFT -> "UTURN_LEFT"; UTURN_RIGHT -> "UTURN_RIGHT"
        MERGE -> "MERGE"; FORK_LEFT -> "FORK_LEFT"; FORK_RIGHT -> "FORK_RIGHT"
        EXIT_LEFT -> "EXIT_LEFT"; EXIT_RIGHT -> "EXIT_RIGHT"
        ROUNDABOUT -> "ROUNDABOUT"; FLYOVER -> "FLYOVER"; UNDERPASS -> "UNDERPASS"
        DESTINATION -> "DESTINATION"; FERRY -> "FERRY"; UNKNOWN -> "UNKNOWN"
        in (ROUNDABOUT_EXIT_BASE + 1)..(ROUNDABOUT_EXIT_BASE + 15) ->
            "ROUNDABOUT_EXIT_${code - ROUNDABOUT_EXIT_BASE}"
        else -> "0x%02X".format(code)
    }
}

object NavFlag {
    const val ACTIVE = 1 shl 0
    const val REROUTING = 1 shl 1
    const val GPS_WEAK = 1 shl 2
    const val ARRIVED = 1 shl 3
}

/**
 * One navigation update, as parsed from the Maps notification.
 *
 * `nextManeuver` and `nextDistM` stay at their defaults: Google Maps does not
 * expose a next maneuver anywhere in the payload (NAV_DATA.md). They exist in
 * the protocol so an OsmAnd or Valhalla source could fill them later without a
 * wire change - see the data-source decision in FEATURES.md.
 */
data class NavUpdate(
    val maneuver: Int = Mv.UNKNOWN,
    val distM: Int = 0,
    val etaMin: Int = 0,
    val remaining100m: Int = 0,
    val instruction: String = "",
    val navActive: Boolean = false,
    val rerouting: Boolean = false,
    val gpsWeak: Boolean = false,
    val arrived: Boolean = false,
    val nextManeuver: Int = Mv.UNKNOWN,
    val nextDistM: Int = 0,
) {
    val flags: Int
        get() = (if (navActive) NavFlag.ACTIVE else 0) or
                (if (rerouting) NavFlag.REROUTING else 0) or
                (if (gpsWeak) NavFlag.GPS_WEAK else 0) or
                (if (arrived) NavFlag.ARRIVED else 0)
}

/**
 * Builds frames. Every method returns a complete frame ready to write.
 *
 * Strings are truncated on a UTF-8 code point boundary, never mid-sequence -
 * Bengaluru road names carry Kannada and a severed multi-byte sequence renders
 * as garbage on the device.
 */
object PacketBuilder {

    /** The device's INSTRUCTION_MAX is 64; leave room for its terminator. */
    private const val INSTRUCTION_MAX = 63
    private const val ALERT_TEXT_MAX = 39
    private const val ALERT_SRC_MAX = 19

    fun nav(u: NavUpdate): ByteArray {
        val text = utf8Trunc(u.instruction, INSTRUCTION_MAX)
        val payload = ByteArray(11 + text.size)
        var i = 0
        payload[i++] = u.maneuver.toByte()
        i = le16(payload, i, u.distM)
        payload[i++] = u.nextManeuver.toByte()
        i = le16(payload, i, u.nextDistM)
        i = le16(payload, i, u.etaMin)
        i = le16(payload, i, u.remaining100m)
        payload[i++] = u.flags.toByte()
        text.copyInto(payload, i)
        return frame(Pkt.NAV, payload)
    }

    /**
     * Clock is an optional tail. The device has no RTC and no network, so the
     * phone is its only time source - without this the idle screen has nothing
     * to say and falls back to "READY".
     */
    fun status(batteryPct: Int, hour: Int? = null, minute: Int? = null): ByteArray {
        val withClock = hour != null && minute != null
        val payload = ByteArray(if (withClock) 4 else 2)
        payload[0] = 0                                   // flags: no bits defined yet
        payload[1] = batteryPct.coerceIn(0, 100).toByte()
        if (withClock) {
            payload[2] = hour!!.coerceIn(0, 23).toByte()
            payload[3] = minute!!.coerceIn(0, 59).toByte()
        }
        return frame(Pkt.STATUS, payload)
    }

    /** state: 0 idle, 1 ringing, 2 active. */
    fun call(state: Int, name: String): ByteArray {
        val n = utf8Trunc(name, ALERT_TEXT_MAX)
        val payload = ByteArray(1 + n.size)
        payload[0] = state.toByte()
        n.copyInto(payload, 1)
        return frame(Pkt.CALL, payload)
    }

    /**
     * kind: 0 generic, 1 message, 2 email, 3 alert.
     *
     * Length-prefixed rather than NUL-separated, deliberately: MEDIA is the one
     * row in this protocol that splits on NUL, and a generic trailing-text
     * reader silently eats its second field.
     */
    fun notify(kind: Int, src: String, text: String): ByteArray {
        val s = utf8Trunc(src, ALERT_SRC_MAX)
        val t = utf8Trunc(text, ALERT_TEXT_MAX)
        val payload = ByteArray(2 + s.size + t.size)
        payload[0] = kind.toByte()
        payload[1] = s.size.toByte()
        s.copyInto(payload, 2)
        t.copyInto(payload, 2 + s.size)
        return frame(Pkt.NOTIFY, payload)
    }

    /**
     * Polarity comes from here, not from a sensor on the device. The phone
     * knows real local sunset for the actual position; a light sensor on the
     * bars would strobe under Bengaluru flyovers, and a polarity flap is a
     * full-panel flash in peripheral vision.
     */
    fun config(night: Boolean, brightness: Int = 0, units: Int = 0): ByteArray =
        frame(Pkt.CONFIG, byteArrayOf(
            brightness.toByte(), units.toByte(), if (night) 1 else 0
        ))

    // ------------------------------------------------------------- internals

    private fun frame(type: Int, payload: ByteArray): ByteArray {
        val out = ByteArray(2 + payload.size)
        out[0] = type.toByte()
        out[1] = payload.size.toByte()
        payload.copyInto(out, 2)
        return out
    }

    private fun le16(buf: ByteArray, at: Int, v: Int): Int {
        val x = v.coerceIn(0, 0xFFFF)
        buf[at] = (x and 0xFF).toByte()
        buf[at + 1] = ((x shr 8) and 0xFF).toByte()
        return at + 2
    }

    /**
     * Truncate to at most [max] bytes without splitting a UTF-8 sequence. Kotlin
     * substring counts UTF-16 units, which is the wrong unit twice over: a
     * Kannada character is one char but three bytes, and an emoji is two chars.
     */
    internal fun utf8Trunc(s: String, max: Int): ByteArray {
        val raw = s.toByteArray(Charsets.UTF_8)
        if (raw.size <= max) return raw
        var end = max
        while (end > 0 && (raw[end].toInt() and 0xC0) == 0x80) end--
        return raw.copyOf(end)
    }
}
