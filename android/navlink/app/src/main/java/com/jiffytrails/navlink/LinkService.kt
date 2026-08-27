package com.jiffytrails.navlink

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.net.Uri
import android.os.BatteryManager
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.PowerManager
import android.provider.Settings
import android.util.Log
import java.util.Calendar
import java.util.Locale
import java.util.TimeZone
import kotlin.math.abs
import kotlin.math.acos
import kotlin.math.asin
import kotlin.math.cos
import kotlin.math.sin

/**
 * Service-level state, as opposed to link-level state in [LinkState].
 *
 * [batteryOptimisationExempt] and [vendorWhitelistUnverifiable] exist because
 * the honest answer to "will this app survive a two-hour ride with the screen
 * off" is *it depends, and on some phones nobody can tell you*. PRIOR_ART.md
 * records NAVRIDER hitting exactly this on ColorOS, HyperOS/MIUI and
 * FuntouchOS: the vendor's own autostart / protected-app list is separate from
 * AOSP's battery-optimisation whitelist and has **no public API to read**. So
 * this reports what it can verify, flags what it cannot, and leaves the UI to
 * say so out loud rather than pretending.
 */
data class ServiceState(
    val running: Boolean = false,
    /** AOSP whitelist. Verifiable via PowerManager, and necessary but not sufficient. */
    val batteryOptimisationExempt: Boolean = false,
    /** This phone has a vendor killer list the app cannot query. Prompt the user manually. */
    val vendorWhitelistUnverifiable: Boolean = false,
    /** e.g. "ColorOS", for a UI that wants to name the settings screen. */
    val vendorSkin: String? = null,
    /** True once POST_NOTIFICATIONS is granted, or on API < 33 where it does not exist. */
    val notificationsAllowed: Boolean = true,
    val night: Boolean = false,
    /** Last phone battery percentage sent to the device, -1 if unknown. */
    val batteryPct: Int = -1,
    val error: String? = null,
)

/**
 * Foreground service that owns the [BleLink].
 *
 * Responsibilities, in order of how often they bite:
 *  1. Keep the process alive and the BLE link up while the phone is in a pocket
 *     with the screen off, which is the entire duty cycle of this product.
 *  2. Feed the device the two things only the phone knows: the clock and the
 *     battery (STATUS, ~30 s) and day/night polarity (CONFIG, on transition).
 *  3. Tell the UI the truth about whether it is actually allowed to do (1).
 *
 * The nav stream itself comes from elsewhere - the Maps parser calls
 * [submitNav] - so this file never touches notification listening or GPS.
 */
class LinkService : Service() {

    companion object {
        private const val TAG = "NAVLINK/svc"

        private const val CHANNEL_ID = "navlink.link"
        private const val NOTIF_ID = 42

        const val ACTION_START = "com.jiffytrails.navlink.START"
        const val ACTION_STOP = "com.jiffytrails.navlink.STOP"

        /** STATUS cadence. The clock only needs to be right to the minute. */
        private const val STATUS_INTERVAL_MS = 30_000L

        /**
         * Process-wide observable link state. Survives the service being stopped
         * and restarted, so a UI can bind to it at any point in its own lifecycle
         * without racing the service.
         */
        val link = StateStream(LinkState())

        /** Process-wide observable service state. See [ServiceState]. */
        val service = StateStream(ServiceState())

        @Volatile
        private var instance: LinkService? = null

        /**
         * Held so an update produced in the gap between the parser starting and
         * the service being up is not simply lost. One slot: latest wins.
         */
        @Volatile
        private var queuedNav: NavUpdate? = null

        fun start(context: Context) {
            val i = Intent(context, LinkService::class.java).setAction(ACTION_START)
            // startForegroundService, not startService: on O+ a background start
            // of a plain service throws. The five-second startForeground deadline
            // is met in onCreate.
            context.startForegroundService(i)
        }

        fun stop(context: Context) {
            context.startService(Intent(context, LinkService::class.java).setAction(ACTION_STOP))
        }

        /** The parser agent's entry point. Safe from any thread, any time. */
        fun submitNav(update: NavUpdate) {
            val svc = instance
            if (svc == null) {
                queuedNav = update
                return
            }
            svc.ble.submitNav(update)
        }

        /** Escape hatch for packet types this service does not own (CALL, NOTIFY, MEDIA). */
        fun sendPacket(frame: ByteArray, label: String) {
            instance?.ble?.send(frame, label)
        }

        /**
         * Re-reads the AOSP whitelist. Call after the user comes back from the
         * settings screen - there is no broadcast for this.
         */
        fun refreshPowerState(context: Context) {
            val pm = context.getSystemService(Context.POWER_SERVICE) as PowerManager
            val exempt = pm.isIgnoringBatteryOptimizations(context.packageName)
            val skin = vendorSkin()
            service.update {
                it.copy(
                    batteryOptimisationExempt = exempt,
                    vendorWhitelistUnverifiable = skin != null,
                    vendorSkin = skin,
                    notificationsAllowed = notificationsAllowed(context),
                )
            }
        }

        /**
         * Opens the system list of battery-optimised apps.
         *
         * Deliberately not ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS: that one
         * needs the REQUEST_IGNORE_BATTERY_OPTIMIZATIONS permission and is a Play
         * Store policy flashpoint. This one needs nothing and lands the user two
         * taps away. It does *not* cover the vendor lists - see [vendorSkin].
         */
        fun batteryOptimisationSettings(): Intent =
            Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS)

        /** App detail settings, the only reliable route to the vendor's own toggles. */
        fun appSettings(context: Context): Intent =
            Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS)
                .setData(Uri.fromParts("package", context.packageName, null))

        /**
         * Names the OEM skin when this phone is known to keep a second,
         * unqueryable kill list. Returns null when AOSP's whitelist is the whole
         * story and [ServiceState.batteryOptimisationExempt] can be trusted.
         */
        private fun vendorSkin(): String? {
            val m = Build.MANUFACTURER.lowercase(Locale.ROOT)
            return when {
                m.contains("xiaomi") || m.contains("redmi") || m.contains("poco") ->
                    "HyperOS / MIUI"
                m.contains("oppo") || m.contains("realme") || m.contains("oneplus") ->
                    "ColorOS"
                m.contains("vivo") || m.contains("iqoo") -> "FuntouchOS / OriginOS"
                m.contains("huawei") || m.contains("honor") -> "EMUI / MagicOS"
                m.contains("samsung") -> "One UI"
                m.contains("transsion") || m.contains("infinix") || m.contains("tecno") ->
                    "HiOS / XOS"
                else -> null
            }
        }

        private fun notificationsAllowed(context: Context): Boolean {
            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) return true
            return context.checkSelfPermission(android.Manifest.permission.POST_NOTIFICATIONS) ==
                    android.content.pm.PackageManager.PERMISSION_GRANTED
        }
    }

    private val ble by lazy { BleLink(this, link) }
    private val main = Handler(Looper.getMainLooper())
    private var wakeLock: PowerManager.WakeLock? = null
    private var unobserve: (() -> Unit)? = null

    private var lastPhase: LinkPhase? = null

    /** False if onCreate bailed out at startForeground, so onDestroy tears down nothing. */
    private var started = false

    /** Null until the first CONFIG is sent, so the first evaluation always transmits. */
    private var lastNightSent: Boolean? = null

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        instance = this
        createChannel()

        // startForeground must happen inside five seconds of the start request or
        // the system kills the process with a ForegroundServiceDidNotStartInTime
        // ANR, so it goes first and everything else follows.
        if (!goForeground(LinkPhase.IDLE)) return

        acquireWakeLock()
        refreshPowerState(this)
        service.update { it.copy(running = true, error = null) }

        // Both hooks fire on the BLE thread and are bounced to main, so the
        // periodic sender below is the only writer of lastNightSent.
        ble.onReady = {
            main.post {
                // The device came up knowing nothing: no clock, no battery, no
                // polarity. Everything it cannot derive gets restated here, on
                // every connect, not just the first.
                lastNightSent = null
                sendStatus()
                evaluateNight()
            }
        }
        ble.onNudge = {
            // The device prods after ~4 s of silence. BleLink answers it with the
            // current NAV by itself; the only case it cannot cover is "no route
            // has ever been submitted", where a STATUS keeps the idle clock alive
            // instead of letting the watchdog declare STALE.
            if (!ble.hasNav()) main.post { sendStatus() }
        }

        unobserve = link.observe { st ->
            if (st.phase != lastPhase) {
                lastPhase = st.phase
                updateNotification(st.phase)
            }
        }

        ble.start()
        queuedNav?.let { ble.submitNav(it); queuedNav = null }
        main.post(statusTicker)
        started = true
        Log.i(TAG, "started")
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == ACTION_STOP) {
            stopSelf()
            return START_NOT_STICKY
        }
        // START_STICKY: if the platform kills us for memory mid-ride we want to
        // come back. The restart arrives with a null intent, which onCreate
        // already handles because all the setup lives there.
        return START_STICKY
    }

    override fun onDestroy() {
        Log.i(TAG, "stopping")
        instance = null
        if (started) {
            started = false
            main.removeCallbacks(statusTicker)
            unobserve?.invoke()
            unobserve = null
            ble.onReady = null
            ble.onNudge = null
            ble.release()
        }
        releaseWakeLock()
        service.update { it.copy(running = false) }
        super.onDestroy()
    }

    // ------------------------------------------------------------- foreground

    private fun goForeground(phase: LinkPhase): Boolean {
        val notification = buildNotification(phase)
        return try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                // connectedDevice, and only that. The nav data is parsed from a
                // notification by another component, so this service never needs
                // the location type - which is what keeps the app off the
                // background-location review path entirely.
                startForeground(
                    NOTIF_ID,
                    notification,
                    ServiceInfo.FOREGROUND_SERVICE_TYPE_CONNECTED_DEVICE,
                )
            } else {
                startForeground(NOTIF_ID, notification)
            }
            true
        } catch (t: Throwable) {
            // Android 12+ refuses a foreground start from the background
            // (ForegroundServiceStartNotAllowedException). Start this from an
            // Activity, or from a component the platform considers foreground.
            Log.e(TAG, "startForeground refused: ${t.message}")
            service.update { it.copy(running = false, error = "cannot start in background") }
            stopSelf()
            false
        }
    }

    private fun createChannel() {
        val nm = getSystemService(NotificationManager::class.java) ?: return
        // IMPORTANCE_LOW: silent and collapsed. A persistent notification is the
        // rent paid for staying alive; it should not also be noise.
        val channel = NotificationChannel(
            CHANNEL_ID,
            "Handlebar link",
            NotificationManager.IMPORTANCE_LOW,
        ).apply {
            description = "Keeps the connection to the handlebar display alive during a ride."
            setShowBadge(false)
        }
        nm.createNotificationChannel(channel)
    }

    private fun buildNotification(phase: LinkPhase): Notification {
        val text = when (phase) {
            LinkPhase.IDLE -> "Starting"
            LinkPhase.BLUETOOTH_OFF -> "Bluetooth is off"
            LinkPhase.PERMISSION_REQUIRED -> "Bluetooth permission needed"
            LinkPhase.SCANNING -> "Looking for ${BleLink.DEVICE_NAME}"
            LinkPhase.CONNECTING -> "Connecting"
            LinkPhase.CONNECTED -> "Connected to ${BleLink.DEVICE_NAME}"
            LinkPhase.RECONNECTING -> "Waiting for ${BleLink.DEVICE_NAME}"
        }

        // Resolved at runtime so this file compiles without owning the manifest
        // or the launcher activity.
        val launch = packageManager.getLaunchIntentForPackage(packageName)
        val pending = launch?.let {
            PendingIntent.getActivity(
                this, 0, it,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )
        }

        return Notification.Builder(this, CHANNEL_ID)
            .setContentTitle("JiffyTrails")
            .setContentText(text)
            // A framework drawable, so this file adds nothing to res/. Swap for a
            // real monochrome icon when one exists.
            .setSmallIcon(android.R.drawable.stat_sys_data_bluetooth)
            .setOngoing(true)
            .setShowWhen(false)
            .setCategory(Notification.CATEGORY_SERVICE)
            .apply { pending?.let { setContentIntent(it) } }
            .build()
    }

    private fun updateNotification(phase: LinkPhase) {
        val nm = getSystemService(NotificationManager::class.java) ?: return
        try {
            nm.notify(NOTIF_ID, buildNotification(phase))
        } catch (t: Throwable) {
            Log.w(TAG, "notify failed: ${t.message}")
        }
    }

    /**
     * A partial wake lock, held for the life of the service.
     *
     * Not belt-and-braces: a foreground service is not exempt from the AP
     * suspending between wakeups when the screen is off, and the 1 Hz Handler
     * tick that drives the nav stream simply does not fire while it is
     * suspended. The symptom is a display that updates in bursts whenever
     * something else happens to wake the phone. The phone is expected to be on
     * the bike's charger or in a pocket for the duration of a ride, and the
     * service is only running while the rider asked for it to be.
     */
    private fun acquireWakeLock() {
        if (wakeLock != null) return
        val pm = getSystemService(Context.POWER_SERVICE) as? PowerManager ?: return
        wakeLock = pm.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "navlink:link").apply {
            setReferenceCounted(false)
            try {
                acquire()
            } catch (t: Throwable) {
                Log.w(TAG, "wakelock: ${t.message}")
            }
        }
    }

    private fun releaseWakeLock() {
        wakeLock?.let { if (it.isHeld) runCatching { it.release() } }
        wakeLock = null
    }

    // ------------------------------------------------------- periodic packets

    private val statusTicker = object : Runnable {
        override fun run() {
            main.postDelayed(this, STATUS_INTERVAL_MS)
            sendStatus()
            evaluateNight()
            // No broadcast exists for the whitelist changing, so it is re-read
            // here; the UI's prompt then disappears on its own once the user
            // grants it, without needing to know to come back and ask.
            refreshPowerState(this@LinkService)
        }
    }

    /**
     * STATUS carries the two facts the device physically cannot know: it has no
     * RTC, no network and no battery gauge of its own.
     */
    private fun sendStatus() {
        val pct = batteryPercent()
        val now = Calendar.getInstance()
        ble.send(
            PacketBuilder.status(
                batteryPct = pct,
                hour = now.get(Calendar.HOUR_OF_DAY),
                minute = now.get(Calendar.MINUTE),
            ),
            "STATUS",
        )
        service.update { it.copy(batteryPct = pct) }
    }

    private fun batteryPercent(): Int {
        val bm = getSystemService(Context.BATTERY_SERVICE) as? BatteryManager ?: return 0
        val pct = bm.getIntProperty(BatteryManager.BATTERY_PROPERTY_CAPACITY)
        return if (pct in 0..100) pct else 0
    }

    /**
     * Day/night polarity, sent only on a transition.
     *
     * The device inverts the whole panel on this bit, so a flap is a full-screen
     * flash in peripheral vision at 60 km/h - which is why the decision is made
     * here from a clock and not on the bars from a light sensor that would
     * strobe under every Bengaluru flyover.
     */
    private fun evaluateNight() {
        val night = SolarClock.isNight(System.currentTimeMillis())
        if (night == lastNightSent) return
        lastNightSent = night
        ble.send(PacketBuilder.config(night = night), "CONFIG")
        service.update { it.copy(night = night) }
        Log.i(TAG, "night=$night")
    }
}

/**
 * Sunrise and sunset from the standard NOAA/"sunrise equation" solar position
 * model, for a fixed position.
 *
 * **Why fixed and not the phone's actual position:** the only reason this
 * service would ever hold a location permission is this one bit, and taking
 * ACCESS_FINE_LOCATION would drag in a `location` foreground service type,
 * a runtime prompt, and a Play Store justification - for a value that moves
 * about four minutes per 100 km of longitude. Real astronomical sunset for
 * Bengaluru is strictly better than the fixed clock window the brief allowed as
 * a fallback: it tracks the ~40 minutes of seasonal drift exactly, and it is
 * still correct to within a couple of minutes anywhere in southern Karnataka.
 *
 * [lat] and [lon] are mutable so that a build which *does* have a location fix
 * - the parser side may well acquire one later - can set them once and get true
 * local sunset with no other change.
 */
object SolarClock {

    /** Bengaluru, MG Road. Overwrite if a real fix is available. */
    @Volatile var lat: Double = 12.9716
    @Volatile var lon: Double = 77.5946

    /**
     * Sunset is not darkness. The display should flip when the rider actually
     * needs it to, which is a little after the sun goes and a little before it
     * returns - roughly civil twilight at this latitude.
     */
    private const val MARGIN_MIN = 20

    /** Fallback window if the solar calculation cannot produce an event (polar cases). */
    private const val FALLBACK_NIGHT_FROM_HOUR = 19
    private const val FALLBACK_NIGHT_TO_HOUR = 6

    private const val ZENITH_DEG = -0.833          // refraction + solar radius
    private const val OBLIQUITY_DEG = 23.4397

    fun isNight(nowMs: Long, tz: TimeZone = TimeZone.getDefault()): Boolean {
        val events = riseSet(nowMs, tz) ?: return fallbackIsNight(nowMs, tz)
        val margin = MARGIN_MIN * 60_000L
        return nowMs >= events.second + margin || nowMs <= events.first - margin
    }

    /** Sunrise and sunset for the local calendar day containing [nowMs], as epoch millis. */
    fun riseSet(nowMs: Long, tz: TimeZone = TimeZone.getDefault()): Pair<Long, Long>? {
        // Anchor on local noon, not on "now": the solar day and the calendar day
        // do not share a boundary, and anchoring on the instant makes 23:00
        // resolve to tomorrow's sunset, which reads as daytime.
        val cal = Calendar.getInstance(tz).apply {
            timeInMillis = nowMs
            set(Calendar.HOUR_OF_DAY, 12)
            set(Calendar.MINUTE, 0)
            set(Calendar.SECOND, 0)
            set(Calendar.MILLISECOND, 0)
        }
        val jdNoon = julianDay(cal.timeInMillis)

        // Days since J2000 for this solar day. The longitude term is subtracted
        // with east-positive longitude: local solar noon happens *earlier* in UT
        // the further east you are.
        val n = Math.round(jdNoon - 2451545.0 - 0.0009 + lon / 360.0).toDouble()
        val jStar = n + 0.0009 - lon / 360.0

        val mDeg = (357.5291 + 0.98560028 * jStar).mod(360.0)
        val m = Math.toRadians(mDeg)
        val c = 1.9148 * sin(m) + 0.02 * sin(2 * m) + 0.0003 * sin(3 * m)
        val lambda = Math.toRadians((mDeg + c + 180.0 + 102.9372).mod(360.0))

        val jTransit = 2451545.0 + jStar + 0.0053 * sin(m) - 0.0069 * sin(2 * lambda)

        val decl = asin(sin(lambda) * sin(Math.toRadians(OBLIQUITY_DEG)))
        val phi = Math.toRadians(lat)
        val cosOmega = (sin(Math.toRadians(ZENITH_DEG)) - sin(phi) * sin(decl)) /
                (cos(phi) * cos(decl))
        if (abs(cosOmega) > 1.0) return null       // sun never rises or never sets here today

        val omega = Math.toDegrees(acos(cosOmega))
        return epochMillis(jTransit - omega / 360.0) to epochMillis(jTransit + omega / 360.0)
    }

    private fun fallbackIsNight(nowMs: Long, tz: TimeZone): Boolean {
        val h = Calendar.getInstance(tz).apply { timeInMillis = nowMs }.get(Calendar.HOUR_OF_DAY)
        return h >= FALLBACK_NIGHT_FROM_HOUR || h < FALLBACK_NIGHT_TO_HOUR
    }

    /** Unix epoch is Julian day 2440587.5; Julian days tick over at 12:00 UT. */
    private fun julianDay(ms: Long): Double = ms / 86_400_000.0 + 2440587.5

    private fun epochMillis(jd: Double): Long = ((jd - 2440587.5) * 86_400_000.0).toLong()
}
