package com.jiffytrails.navlink

import android.Manifest
import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothDevice
import android.bluetooth.BluetoothGatt
import android.bluetooth.BluetoothGattCallback
import android.bluetooth.BluetoothGattCharacteristic
import android.bluetooth.BluetoothGattDescriptor
import android.bluetooth.BluetoothManager
import android.bluetooth.BluetoothProfile
import android.bluetooth.BluetoothStatusCodes
import android.bluetooth.le.ScanCallback
import android.bluetooth.le.ScanFilter
import android.bluetooth.le.ScanResult
import android.bluetooth.le.ScanSettings
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.os.Build
import android.os.Handler
import android.os.HandlerThread
import android.os.Looper
import android.os.ParcelUuid
import android.os.SystemClock
import android.util.Log
import java.util.UUID
import java.util.concurrent.CopyOnWriteArrayList

/**
 * A tiny observable. Deliberately not StateFlow or LiveData: this module has no
 * Gradle dependencies beyond the Kotlin stdlib, and the whole contract is
 * "hold a value, tell me when it changes, on the main thread".
 *
 * Emission is deduplicated by equality, so a data class holder never wakes the
 * UI for a state that did not actually move.
 */
class StateStream<T>(initial: T) {

    private val main = Handler(Looper.getMainLooper())
    private val listeners = CopyOnWriteArrayList<(T) -> Unit>()

    @Volatile
    var value: T = initial
        private set

    /** Replaces the value. Safe from any thread; listeners always run on main. */
    fun set(next: T) {
        if (next == value) return
        value = next
        for (l in listeners) main.post { l(next) }
    }

    /** Read-modify-write. Not atomic across threads; every caller here is the BLE thread. */
    fun update(block: (T) -> T) = set(block(value))

    /** Registers [listener], immediately replays the current value, returns an unsubscriber. */
    fun observe(listener: (T) -> Unit): () -> Unit {
        listeners.add(listener)
        val now = value
        main.post { listener(now) }
        return { listeners.remove(listener) }
    }
}

/** What the link is doing, in the order a rider would care about it. */
enum class LinkPhase {
    /** Not started, or stopped. */
    IDLE,

    /** Bluetooth is off at the system level. Nothing to do but wait for it. */
    BLUETOOTH_OFF,

    /** BLUETOOTH_SCAN / BLUETOOTH_CONNECT (or, below API 31, location) not granted. */
    PERMISSION_REQUIRED,

    /** Looking for the peripheral's advertisement. */
    SCANNING,

    /** Found it; connecting, discovering, negotiating MTU, subscribing. */
    CONNECTING,

    /** Connected, MTU exchanged, notifications on. Packets are flowing. */
    CONNECTED,

    /** Was connected, lost it, waiting for the device to advertise again. */
    RECONNECTING,
}

/**
 * Everything a UI needs to render the link honestly, and nothing it does not.
 *
 * Times are [SystemClock.elapsedRealtime] because they are only ever used as
 * "how long ago", and wall-clock time can jump backwards when the phone syncs.
 */
data class LinkState(
    val phase: LinkPhase = LinkPhase.IDLE,
    val deviceAddress: String? = null,
    /** Negotiated ATT MTU. 23 until the exchange completes; usable payload is this minus 3. */
    val mtu: Int = 23,
    /** elapsedRealtime of the last packet the stack accepted, 0 if none yet. */
    val lastPacketAtMs: Long = 0L,
    /** elapsedRealtime of the last keep-alive nudge from the device, 0 if none yet. */
    val lastNudgeAtMs: Long = 0L,
    val packetsSent: Long = 0L,
    val packetsFailed: Long = 0L,
    /** Consecutive failed connect attempts; drives the backoff. Zero when healthy. */
    val retries: Int = 0,
    /** Human-readable, last error only. Null once the link recovers. */
    val error: String? = null,
) {
    val connected: Boolean get() = phase == LinkPhase.CONNECTED

    /** True once the MTU exchange has landed and a 26-byte NAV frame will actually fit. */
    val mtuSufficient: Boolean get() = mtu - 3 >= 64
}

/**
 * GATT central for the handlebar navigator.
 *
 * The peripheral is `firmware/navigator/ble.cpp`: it advertises the service UUID
 * in the advertisement and its name in the scan response (a 128-bit UUID leaves
 * no room for both in 31 bytes), accepts framed packets on the write
 * characteristic, and notifies a single 0x00 byte as a keep-alive prod when it
 * has heard nothing for ~4 s.
 *
 * Threading: every field below is touched only on [bleHandler]'s thread. Public
 * entry points post onto it, so callers can be anywhere. GATT callbacks arrive
 * on a binder thread and are immediately re-posted, which is also what makes the
 * one-operation-at-a-time queue safe.
 *
 * No coroutines: the module carries no Gradle dependencies, and kotlinx-coroutines
 * is one. A single-threaded Handler is the honest equivalent here anyway - the
 * GATT API is callback-driven and demands exactly this serialisation.
 */
class BleLink(
    context: Context,
    val state: StateStream<LinkState> = StateStream(LinkState()),
) {

    companion object {
        private const val TAG = "NAVLINK/ble"

        /** Advertised name. Matched case-insensitively; see [matchesTarget]. */
        const val DEVICE_NAME = "JiffyTrails"

        val SERVICE_UUID: UUID = UUID.fromString("6e400001-b5a3-f393-e0a9-e50e24dcca9e")
        val WRITE_UUID: UUID = UUID.fromString("6e400002-b5a3-f393-e0a9-e50e24dcca9e")
        val NOTIFY_UUID: UUID = UUID.fromString("6e400003-b5a3-f393-e0a9-e50e24dcca9e")

        /** Client Characteristic Configuration. Writing 0x0001 here is what actually subscribes. */
        private val CCCD_UUID: UUID = UUID.fromString("00002902-0000-1000-8000-00805f9b34fb")

        /**
         * Matches PREFERRED_MTU in ble.cpp. Non-negotiable: the default ATT MTU of
         * 23 carries 20 bytes of payload, and a NAV frame with a road name is 26.
         * Without the exchange, long packets are refused at the L2CAP layer while
         * short ones sail through - the failure looks like "only some maneuvers
         * appear", which is a horrible thing to chase. No NAV is sent until
         * onMtuChanged has returned.
         */
        const val TARGET_MTU = 185

        /** Design rate. The device redraws on change; the radio costs power regardless. */
        private const val MIN_NAV_INTERVAL_MS = 900L

        /**
         * Resend the current NAV even if nothing changed, if nothing at all has
         * been written for this long. The device's watchdog counts packet
         * *arrivals*, not value changes (nav_types.h: 64 s of unchanging values
         * were measured in traffic), and it declares STALE at 10 s. Dedup alone
         * would therefore blank the display on a slow road. 5 s leaves margin.
         */
        private const val NAV_HEARTBEAT_MS = 5_000L

        /** Drives the heartbeat above; also the only periodic work on this thread. */
        private const val TICK_MS = 1_000L

        /**
         * Android sometimes never calls back for an operation. Without this the
         * queue wedges permanently and the link goes quiet while still reporting
         * "connected", which is the worst of both.
         */
        private const val OP_TIMEOUT_MS = 5_000L

        /** Direct connects have no useful timeout of their own before ~30 s. */
        private const val CONNECT_TIMEOUT_MS = 15_000L

        /** Restart a scan that has produced nothing; some stacks quietly stop delivering. */
        private const val SCAN_RESTART_MS = 60_000L

        /**
         * Android throttles an app that starts more than 5 scans in 30 s and then
         * silently returns no results at all. Never restart faster than this.
         */
        private const val SCAN_START_MIN_GAP_MS = 7_000L

        /** Connect-failure backoff. Capped low: "walk 30 m away and back" must recover fast. */
        private val BACKOFF_MS = longArrayOf(500, 1_000, 2_000, 4_000, 8_000)
    }

    private val ctx: Context = context.applicationContext
    private val btManager = ctx.getSystemService(Context.BLUETOOTH_SERVICE) as? BluetoothManager
    private val adapter: BluetoothAdapter? get() = btManager?.adapter

    private val thread = HandlerThread("navlink-ble").apply { start() }
    private val bleHandler = Handler(thread.looper)

    /** Invoked on the BLE thread the moment the link becomes usable. Send initial state here. */
    var onReady: (() -> Unit)? = null

    /**
     * Invoked on the BLE thread when the device prods us. It is a request to
     * restate, not data - see [handleNotification].
     */
    var onNudge: (() -> Unit)? = null

    // ------------------------------------------------------------ mutable state
    // BLE thread only, all of it.

    private var running = false
    private var scanning = false
    private var gatt: BluetoothGatt? = null
    private var writeChr: BluetoothGattCharacteristic? = null
    private var ready = false
    private var knownAddress: String? = null
    private var lastScanStartAt = 0L
    private var lastScanResultAt = 0L
    private var retries = 0

    /** Backoff deadline. The 1 Hz tick also calls ensureRunning, and without this it would outvote it. */
    private var nextAttemptAt = 0L

    /**
     * Latest NAV from the parser. Latest wins; intermediate updates are not a
     * queue. Volatile only so [hasNav] can be read off-thread.
     */
    @Volatile
    private var pendingNav: ByteArray? = null

    /** Last NAV actually written, for de-duplication. */
    private var sentNav: ByteArray? = null

    private var lastNavWriteAt = 0L
    private var lastAnyWriteAt = 0L

    /** One outstanding GATT operation, ever. Overlapping ones fail silently. */
    private val queue = ArrayDeque<Op>()
    private var inFlight: Op? = null

    private class Op(val label: String, val exec: () -> Boolean)

    // ------------------------------------------------------------- public API

    /** Idempotent. Safe to call from any thread. */
    fun start() = bleHandler.post {
        if (running) return@post
        running = true
        registerAdapterReceiver()
        bleHandler.postDelayed(tick, TICK_MS)
        Log.i(TAG, "start")
        ensureRunning()
    }

    /** Tears the link down and stops all retrying. The HandlerThread stays alive for restart. */
    fun stop() = bleHandler.post {
        if (!running) return@post
        running = false
        Log.i(TAG, "stop")
        bleHandler.removeCallbacks(tick)
        unregisterAdapterReceiver()
        stopScan()
        teardownGatt()
        pendingNav = null
        sentNav = null
        state.update { it.copy(phase = LinkPhase.IDLE, mtu = 23, deviceAddress = null) }
    }

    /** Releases the worker thread. Only for a real shutdown; [start] will not work after it. */
    fun release() {
        stop()
        bleHandler.post { thread.quitSafely() }
    }

    /**
     * The 1 Hz nav stream. Latest wins: call as often as the parser likes.
     * De-duplication and rate limiting happen here, not at the call site.
     */
    fun submitNav(update: NavUpdate) = submitNavFrame(PacketBuilder.nav(update))

    /** As [submitNav], for a caller that has already built the frame. */
    fun submitNavFrame(frame: ByteArray) = bleHandler.post {
        pendingNav = frame
        flushNav(force = false)
    }

    /**
     * One-shot packet: STATUS, CONFIG, CALL, NOTIFY. Not de-duplicated - callers
     * of this decide their own cadence, and every one of them is rare.
     */
    fun send(frame: ByteArray, label: String) = bleHandler.post {
        if (!ready) return@post
        enqueue(label) { writeFrame(frame) }
    }

    /**
     * Whether a NAV has ever been submitted. Lets the owner answer a keep-alive
     * nudge with something else when there is no route to restate.
     */
    fun hasNav(): Boolean = pendingNav != null

    /** Forgets the de-dup cache so the next tick rewrites the current NAV verbatim. */
    fun resendNav() = bleHandler.post {
        sentNav = null
        flushNav(force = true)
    }

    // -------------------------------------------------------------- lifecycle

    /**
     * The single decision point: given adapter, permissions and what we already
     * know, get from wherever we are to connected. Called on start, on every
     * disconnect, on adapter state change, and from the tick.
     */
    private fun ensureRunning() {
        if (!running) return

        val a = adapter
        if (a == null) {
            fail(LinkPhase.IDLE, "no Bluetooth adapter on this device")
            return
        }
        if (!a.isEnabled) {
            // Not an error the app can fix. Everything is torn down; the adapter
            // receiver will call back in here when the user turns it on.
            stopScan()
            teardownGatt()
            state.update { it.copy(phase = LinkPhase.BLUETOOTH_OFF, mtu = 23) }
            return
        }

        missingPermission()?.let {
            stopScan()
            fail(LinkPhase.PERMISSION_REQUIRED, "missing permission: $it")
            return
        }

        if (gatt != null) return          // connected or mid-connect; nothing to do
        if (SystemClock.elapsedRealtime() < nextAttemptAt) return

        val addr = knownAddress
        if (addr != null) {
            // Known device: park a background connection rather than scan. The
            // controller re-establishes it the instant the ESP32 advertises
            // again, with no scan cost and no wakeups - which is exactly the
            // "walk 30 m away and come back, no button press" acceptance test.
            connectTo(a.getRemoteDevice(addr), autoConnect = true)
        } else {
            startScan()
        }
    }

    private val tick = object : Runnable {
        override fun run() {
            if (!running) return
            bleHandler.postDelayed(this, TICK_MS)

            if (ready) {
                flushNav(force = false)   // carries the heartbeat resend
            } else {
                ensureRunning()

                // A scan that has gone deaf looks identical to a device that is
                // simply absent, so restart it periodically rather than trust it.
                val now = SystemClock.elapsedRealtime()
                if (scanning && now - lastScanResultAt > SCAN_RESTART_MS &&
                    now - lastScanStartAt > SCAN_RESTART_MS
                ) {
                    Log.i(TAG, "scan produced nothing for ${SCAN_RESTART_MS / 1000}s, restarting")
                    stopScan()
                    startScan()
                }
            }
        }
    }

    // ------------------------------------------------------------------ scan

    private val scanCallback = object : ScanCallback() {
        override fun onScanResult(callbackType: Int, result: ScanResult) {
            bleHandler.post {
                lastScanResultAt = SystemClock.elapsedRealtime()
                if (!running || gatt != null) return@post
                if (!matchesTarget(result)) return@post
                Log.i(TAG, "found ${result.device.address} rssi=${result.rssi}")
                stopScan()
                // First contact is a direct connect: autoConnect=true can take
                // many seconds to fire the first time, and the rider is standing
                // next to the bike waiting for it.
                connectTo(result.device, autoConnect = false)
            }
        }

        override fun onBatchScanResults(results: MutableList<ScanResult>) {
            results.forEach { onScanResult(ScanSettings.CALLBACK_TYPE_ALL_MATCHES, it) }
        }

        override fun onScanFailed(errorCode: Int) {
            bleHandler.post {
                scanning = false
                // 2 = APPLICATION_REGISTRATION_FAILED, usually the 5-scans-per-30s
                // throttle or a stale registration after a Bluetooth restart.
                Log.w(TAG, "scan failed, code $errorCode")
                state.update { it.copy(error = "scan failed ($errorCode)") }
                scheduleRetry()
            }
        }
    }

    /**
     * The service UUID filter is not just tidiness: an unfiltered scan returns
     * nothing at all while the screen is off, which is every minute of a ride.
     */
    private fun startScan() {
        if (scanning || gatt != null) return
        val scanner = adapter?.bluetoothLeScanner ?: return

        val now = SystemClock.elapsedRealtime()
        val since = now - lastScanStartAt
        if (lastScanStartAt != 0L && since < SCAN_START_MIN_GAP_MS) {
            bleHandler.postDelayed({ if (running) startScan() }, SCAN_START_MIN_GAP_MS - since)
            return
        }

        val filters = listOf(
            ScanFilter.Builder().setServiceUuid(ParcelUuid(SERVICE_UUID)).build()
        )
        val settings = ScanSettings.Builder()
            .setScanMode(ScanSettings.SCAN_MODE_LOW_LATENCY)
            .setCallbackType(ScanSettings.CALLBACK_TYPE_ALL_MATCHES)
            .build()

        try {
            scanner.startScan(filters, settings, scanCallback)
        } catch (t: Throwable) {                 // SecurityException, or a dead adapter mid-call
            Log.w(TAG, "startScan threw: ${t.message}")
            state.update { it.copy(error = "scan: ${t.message}") }
            return
        }

        scanning = true
        lastScanStartAt = now
        lastScanResultAt = now
        Log.i(TAG, "scanning for $DEVICE_NAME")
        state.update {
            it.copy(
                phase = if (it.phase == LinkPhase.RECONNECTING) it.phase else LinkPhase.SCANNING,
                error = null,
            )
        }
    }

    private fun stopScan() {
        if (!scanning) return
        scanning = false
        try {
            adapter?.bluetoothLeScanner?.stopScan(scanCallback)
        } catch (t: Throwable) {
            Log.w(TAG, "stopScan threw: ${t.message}")
        }
    }

    /**
     * The filter already guarantees the service UUID. The name is checked here
     * rather than in a second ScanFilter because the peripheral puts its name in
     * the *scan response*, and a name ScanFilter is offloaded to the controller
     * on some chipsets where it then matches nothing. A missing name is accepted:
     * the 128-bit service UUID is specific enough on its own.
     */
    private fun matchesTarget(result: ScanResult): Boolean {
        val advertised = result.scanRecord?.deviceName
        return advertised == null || advertised.equals(DEVICE_NAME, ignoreCase = true)
    }

    // --------------------------------------------------------------- connect

    /**
     * The transport-explicit connectGatt overload is marked deprecated as of
     * API 37 in favour of a BluetoothGattConnectionSettings form that does not
     * exist below it. minSdk here is 26, so this stays until the floor moves.
     * TRANSPORT_LE is passed explicitly because the default picks BR/EDR for a
     * device that has ever been paired classically, and then nothing works.
     */
    @Suppress("DEPRECATION")
    private fun connectTo(device: BluetoothDevice, autoConnect: Boolean) {
        if (gatt != null) return
        Log.i(TAG, "connecting to ${device.address} (autoConnect=$autoConnect)")
        state.update {
            it.copy(
                phase = if (autoConnect) LinkPhase.RECONNECTING else LinkPhase.CONNECTING,
                deviceAddress = device.address,
            )
        }
        gatt = try {
            device.connectGatt(ctx, autoConnect, gattCallback, BluetoothDevice.TRANSPORT_LE)
        } catch (t: Throwable) {
            Log.w(TAG, "connectGatt threw: ${t.message}")
            null
        }
        if (gatt == null) {
            scheduleRetry()
            return
        }
        // autoConnect has no deadline by design - it is a parked connection, and
        // waiting forever is the correct behaviour for a device that is simply
        // out of range. Only the eager path gets a timeout.
        if (!autoConnect) bleHandler.postDelayed(connectTimeout, CONNECT_TIMEOUT_MS)
    }

    private val connectTimeout = Runnable {
        if (!running || ready) return@Runnable
        Log.w(TAG, "connect timed out")
        state.update { it.copy(error = "connect timed out") }
        teardownGatt()
        scheduleRetry()
    }

    /**
     * Backoff between connect attempts. Capped at 8 s deliberately: the gate in
     * BUILD_PLAN.md is "reconnects unaided within 10 s", so a minute-long backoff
     * would fail the acceptance test even though it would eventually work.
     */
    private fun scheduleRetry() {
        if (!running) return
        val delay = BACKOFF_MS[minOf(retries, BACKOFF_MS.size - 1)]
        retries++
        nextAttemptAt = SystemClock.elapsedRealtime() + delay
        state.update { it.copy(retries = retries) }
        bleHandler.postDelayed({ if (running) ensureRunning() }, delay)
    }

    /**
     * Closing is not optional. Every connectGatt claims one of a small, global
     * pool of client interfaces, and a gatt that is disconnected but not closed
     * never gives its one back. Leak enough of them and the phone cannot connect
     * to *anything* over BLE until it is rebooted - which reads as "our app
     * broke Bluetooth".
     */
    private fun teardownGatt() {
        bleHandler.removeCallbacks(connectTimeout)
        val g = gatt
        gatt = null
        writeChr = null
        ready = false
        queue.clear()
        inFlight = null
        bleHandler.removeCallbacks(opTimeout)
        if (g != null) {
            try {
                g.disconnect()
                g.close()
            } catch (t: Throwable) {
                Log.w(TAG, "close threw: ${t.message}")
            }
        }
    }

    // ---------------------------------------------------------- gatt callbacks

    private val gattCallback = object : BluetoothGattCallback() {

        override fun onConnectionStateChange(g: BluetoothGatt, status: Int, newState: Int) {
            bleHandler.post {
                if (g !== gatt) {            // a callback from a gatt we already closed
                    try { g.close() } catch (_: Throwable) {}
                    return@post
                }
                when (newState) {
                    BluetoothProfile.STATE_CONNECTED -> {
                        bleHandler.removeCallbacks(connectTimeout)
                        knownAddress = g.device.address
                        retries = 0; nextAttemptAt = 0L
                        state.update {
                            it.copy(phase = LinkPhase.CONNECTING, retries = 0, error = null)
                        }
                        Log.i(TAG, "connected, discovering services")
                        // Service discovery first, then MTU, then subscribe: three
                        // GATT operations that must not overlap, chained through
                        // their own callbacks rather than fired together.
                        //
                        // Every GATT call here can throw SecurityException if
                        // BLUETOOTH_CONNECT is revoked while connected, so each
                        // one is caught rather than allowed to kill the service.
                        val discovering = try {
                            g.discoverServices()
                        } catch (t: SecurityException) {
                            false
                        }
                        if (!discovering) {
                            state.update { it.copy(error = "discoverServices refused") }
                            teardownGatt(); scheduleRetry()
                        }
                    }

                    BluetoothProfile.STATE_DISCONNECTED -> {
                        val wasReady = ready
                        Log.i(TAG, "disconnected, status=$status (wasReady=$wasReady)")
                        teardownGatt()
                        sentNav = null      // device forgets everything across a link drop
                        state.update {
                            it.copy(
                                phase = if (running) LinkPhase.RECONNECTING else LinkPhase.IDLE,
                                mtu = 23,
                                // status 133 is Android's catch-all GATT_ERROR and is
                                // usually noise on a retry, so it is not surfaced as an
                                // error unless it keeps happening.
                                error = if (wasReady || status == 0) null else it.error,
                            )
                        }
                        if (!running) return@post
                        if (wasReady) {
                            // A clean drop from a healthy link: the device is
                            // rebooting or we rode out of range. Park an
                            // autoConnect immediately, no backoff.
                            retries = 0; nextAttemptAt = 0L
                            ensureRunning()
                        } else {
                            scheduleRetry()
                        }
                    }
                }
            }
        }

        override fun onServicesDiscovered(g: BluetoothGatt, status: Int) {
            bleHandler.post {
                if (g !== gatt) return@post
                val svc = g.getService(SERVICE_UUID)
                val write = svc?.getCharacteristic(WRITE_UUID)
                val notify = svc?.getCharacteristic(NOTIFY_UUID)
                if (status != BluetoothGatt.GATT_SUCCESS || write == null || notify == null) {
                    Log.w(TAG, "service discovery failed ($status) or characteristics missing")
                    state.update { it.copy(error = "device is missing the nav service") }
                    // Not our device after all, or a stale service cache. Forget
                    // the address so the next attempt scans afresh.
                    knownAddress = null
                    teardownGatt(); scheduleRetry()
                    return@post
                }
                writeChr = write

                // MTU before anything is written. See TARGET_MTU.
                val requested = try {
                    g.requestMtu(TARGET_MTU)
                } catch (t: SecurityException) {
                    false
                }
                if (!requested) {
                    state.update { it.copy(error = "requestMtu refused") }
                    teardownGatt(); scheduleRetry()
                }
            }
        }

        override fun onMtuChanged(g: BluetoothGatt, mtu: Int, status: Int) {
            bleHandler.post {
                if (g !== gatt) return@post
                Log.i(TAG, "mtu=$mtu status=$status (payload ${mtu - 3})")
                state.update { it.copy(mtu = mtu) }
                if (mtu - 3 < 64) {
                    // Not fatal - short packets still work - but long road names
                    // will be silently refused, so say so rather than let it look
                    // like a parser bug later.
                    Log.w(TAG, "MTU is small; instructions over ${mtu - 14} bytes will not fit")
                }
                subscribe(g)
            }
        }

        override fun onDescriptorWrite(
            g: BluetoothGatt,
            descriptor: BluetoothGattDescriptor,
            status: Int,
        ) {
            bleHandler.post {
                if (g !== gatt) return@post
                if (descriptor.uuid != CCCD_UUID) return@post
                if (status != BluetoothGatt.GATT_SUCCESS) {
                    // Subscription is how we hear the keep-alive nudge. Without it
                    // the link still works, so this is a warning, not a teardown.
                    Log.w(TAG, "CCCD write failed ($status); no nudges will arrive")
                }
                becomeReady()
            }
        }

        @Deprecated("Pre-33 signature; the 33+ overload below delegates here.")
        override fun onCharacteristicChanged(
            g: BluetoothGatt,
            characteristic: BluetoothGattCharacteristic,
        ) {
            @Suppress("DEPRECATION")
            val value = characteristic.value ?: return
            bleHandler.post { handleNotification(characteristic.uuid, value) }
        }

        override fun onCharacteristicChanged(
            g: BluetoothGatt,
            characteristic: BluetoothGattCharacteristic,
            value: ByteArray,
        ) {
            bleHandler.post { handleNotification(characteristic.uuid, value) }
        }

        override fun onCharacteristicWrite(
            g: BluetoothGatt,
            characteristic: BluetoothGattCharacteristic,
            status: Int,
        ) {
            bleHandler.post { completeOp(status) }
        }
    }

    private fun subscribe(g: BluetoothGatt) {
        val notify = g.getService(SERVICE_UUID)?.getCharacteristic(NOTIFY_UUID)
        if (notify == null) { becomeReady(); return }

        // Two halves, both required: this one routes notifications to us locally,
        // the CCCD write tells the peripheral to send them at all. Doing only the
        // first is the classic "my callback never fires".
        val ok = try {
            g.setCharacteristicNotification(notify, true)
        } catch (t: Throwable) {
            false
        }
        val cccd = notify.getDescriptor(CCCD_UUID)
        if (!ok || cccd == null) { becomeReady(); return }

        val on = BluetoothGattDescriptor.ENABLE_NOTIFICATION_VALUE
        val accepted = try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                g.writeDescriptor(cccd, on) == BluetoothStatusCodes.SUCCESS
            } else {
                @Suppress("DEPRECATION")
                run { cccd.value = on; g.writeDescriptor(cccd) }
            }
        } catch (t: Throwable) {
            false
        }
        if (!accepted) becomeReady()   // no callback is coming; do not wait for one
    }

    private fun becomeReady() {
        if (ready || gatt == null) return
        ready = true
        retries = 0; nextAttemptAt = 0L
        lastAnyWriteAt = 0L
        sentNav = null                 // the device just came up knowing nothing
        Log.i(TAG, "link ready")
        state.update { it.copy(phase = LinkPhase.CONNECTED, retries = 0, error = null) }
        onReady?.invoke()
        flushNav(force = true)
    }

    /**
     * The device notifies exactly one thing: a single 0x00 byte, when it has
     * heard nothing for ~4 s (navigator.ino, nudgeIfQuiet). It is a prompt to
     * restate, not data - there is no uplink protocol to parse. Anything longer
     * is logged and ignored rather than guessed at.
     */
    private fun handleNotification(uuid: UUID, value: ByteArray) {
        if (uuid != NOTIFY_UUID) return
        state.update { it.copy(lastNudgeAtMs = SystemClock.elapsedRealtime()) }
        if (value.size != 1) {
            Log.w(TAG, "unexpected ${value.size}-byte notification, ignored")
            return
        }
        sentNav = null                 // the nudge means "tell me again", so bypass dedup
        flushNav(force = true)
        onNudge?.invoke()
    }

    // ----------------------------------------------------------- write queue

    /**
     * Rate limit, de-duplicate, heartbeat. Three rules in one place:
     *  - never faster than MIN_NAV_INTERVAL_MS,
     *  - never the same bytes twice in a row,
     *  - unless nothing has been written for NAV_HEARTBEAT_MS, in which case
     *    write anyway because the device counts arrivals, not changes.
     */
    private fun flushNav(force: Boolean) {
        if (!ready) return
        val frame = pendingNav ?: return
        val now = SystemClock.elapsedRealtime()

        if (!force && now - lastNavWriteAt < MIN_NAV_INTERVAL_MS) return

        val unchanged = sentNav?.contentEquals(frame) == true
        val silentFor = if (lastAnyWriteAt == 0L) Long.MAX_VALUE else now - lastAnyWriteAt
        if (!force && unchanged && silentFor < NAV_HEARTBEAT_MS) return

        lastNavWriteAt = now
        sentNav = frame
        enqueue("NAV") { writeFrame(frame) }
    }

    private fun enqueue(label: String, exec: () -> Boolean) {
        // Android's GATT allows exactly one outstanding operation per connection.
        // Firing a second before the first calls back does not error - it just
        // does nothing, which is how a nav display quietly freezes.
        queue.addLast(Op(label, exec))
        pump()
    }

    private fun pump() {
        if (inFlight != null) return
        val op = queue.removeFirstOrNull() ?: return
        inFlight = op
        val accepted = try {
            op.exec()
        } catch (t: Throwable) {
            Log.w(TAG, "${op.label} threw: ${t.message}")
            false
        }
        if (!accepted) {
            // Refused before it reached the radio (busy, congested, or gone).
            // Drop it: at 1 Hz the next packet is more current than this one, and
            // clearing the dedup cache guarantees there will be one.
            inFlight = null
            sentNav = null
            state.update { it.copy(packetsFailed = it.packetsFailed + 1) }
            pump()
            return
        }
        bleHandler.postDelayed(opTimeout, OP_TIMEOUT_MS)
    }

    private val opTimeout = Runnable {
        val op = inFlight ?: return@Runnable
        Log.w(TAG, "${op.label} never called back; unblocking the queue")
        inFlight = null
        sentNav = null
        state.update { it.copy(packetsFailed = it.packetsFailed + 1, error = "write timed out") }
        pump()
    }

    private fun completeOp(status: Int) {
        bleHandler.removeCallbacks(opTimeout)
        val op = inFlight
        inFlight = null
        if (op != null && status == BluetoothGatt.GATT_SUCCESS) {
            val now = SystemClock.elapsedRealtime()
            lastAnyWriteAt = now
            state.update {
                it.copy(lastPacketAtMs = now, packetsSent = it.packetsSent + 1, error = null)
            }
        } else if (op != null) {
            Log.w(TAG, "${op.label} failed, status=$status")
            sentNav = null
            state.update { it.copy(packetsFailed = it.packetsFailed + 1) }
        }
        pump()
    }

    /**
     * Write-without-response where the characteristic offers it, which ble.cpp
     * does (WRITE | WRITE_NR). At 1 Hz there is nothing to gain from waiting for
     * an ATT response, and a response-write can stall behind link-layer retries.
     * The completion callback still fires for a no-response write - it means "the
     * stack took it", which is exactly what the queue needs to know.
     */
    private fun writeFrame(frame: ByteArray): Boolean {
        val g = gatt ?: return false
        val chr = writeChr ?: return false

        val noResponse =
            (chr.properties and BluetoothGattCharacteristic.PROPERTY_WRITE_NO_RESPONSE) != 0
        val type = if (noResponse) {
            BluetoothGattCharacteristic.WRITE_TYPE_NO_RESPONSE
        } else {
            BluetoothGattCharacteristic.WRITE_TYPE_DEFAULT
        }

        return try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                g.writeCharacteristic(chr, frame, type) == BluetoothStatusCodes.SUCCESS
            } else {
                @Suppress("DEPRECATION")
                run {
                    chr.writeType = type
                    chr.value = frame
                    g.writeCharacteristic(chr)
                }
            }
        } catch (t: SecurityException) {
            // BLUETOOTH_CONNECT revoked mid-ride. The platform usually kills the
            // process outright when that happens; if it does not, a refused write
            // keeps the queue moving instead of taking the service down.
            false
        }
    }

    // ------------------------------------------------------- adapter watching

    private var adapterReceiver: BroadcastReceiver? = null

    /** Bluetooth off/on is an acceptance test in its own right (BUILD_PLAN stage 6). */
    private fun registerAdapterReceiver() {
        if (adapterReceiver != null) return
        val r = object : BroadcastReceiver() {
            override fun onReceive(c: Context?, intent: Intent?) {
                val s = intent?.getIntExtra(BluetoothAdapter.EXTRA_STATE, -1) ?: return
                bleHandler.post {
                    when (s) {
                        BluetoothAdapter.STATE_OFF, BluetoothAdapter.STATE_TURNING_OFF -> {
                            // The stack has already dropped everything; close our
                            // handles so they are not left dangling across the restart.
                            stopScan()
                            teardownGatt()
                            state.update { it.copy(phase = LinkPhase.BLUETOOTH_OFF, mtu = 23) }
                        }
                        BluetoothAdapter.STATE_ON -> {
                            retries = 0; nextAttemptAt = 0L
                            ensureRunning()
                        }
                    }
                }
            }
        }
        val filter = IntentFilter(BluetoothAdapter.ACTION_STATE_CHANGED)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            ctx.registerReceiver(r, filter, Context.RECEIVER_NOT_EXPORTED)
        } else {
            @Suppress("UnspecifiedRegisterReceiverFlag")
            ctx.registerReceiver(r, filter)
        }
        adapterReceiver = r
    }

    private fun unregisterAdapterReceiver() {
        val r = adapterReceiver ?: return
        adapterReceiver = null
        try { ctx.unregisterReceiver(r) } catch (_: Throwable) {}
    }

    // ---------------------------------------------------------------- helpers

    private fun fail(phase: LinkPhase, message: String) {
        Log.w(TAG, message)
        state.update { it.copy(phase = phase, error = message) }
    }

    /**
     * Returns the first missing permission, or null.
     *
     * Below API 31 there is no BLUETOOTH_SCAN: a BLE scan is a location-capable
     * operation and the platform demands ACCESS_FINE_LOCATION instead. minSdk is
     * 26, so both eras are live. On 31+ the manifest carries `neverForLocation`,
     * which is what lets the app skip location entirely.
     */
    private fun missingPermission(): String? {
        val needed = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            arrayOf(Manifest.permission.BLUETOOTH_SCAN, Manifest.permission.BLUETOOTH_CONNECT)
        } else {
            arrayOf(Manifest.permission.ACCESS_FINE_LOCATION)
        }
        return needed.firstOrNull {
            ctx.checkSelfPermission(it) != PackageManager.PERMISSION_GRANTED
        }
    }

    /** For a UI that wants to prompt. Same list [missingPermission] enforces. */
    fun requiredRuntimePermissions(): Array<String> =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            arrayOf(Manifest.permission.BLUETOOTH_SCAN, Manifest.permission.BLUETOOTH_CONNECT)
        } else {
            arrayOf(Manifest.permission.ACCESS_FINE_LOCATION)
        }
}
