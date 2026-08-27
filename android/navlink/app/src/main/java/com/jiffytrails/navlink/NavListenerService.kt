package com.jiffytrails.navlink

import android.app.Notification
import android.content.Intent
import android.os.Handler
import android.os.Looper
import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification
import android.util.Log

/**
 * The only thing that touches the notification stream.
 *
 * Parsing lives in MapsParser and the radio lives in LinkService; this class
 * exists to bridge them and to own the timing that neither can. It deliberately
 * holds no navigation state of its own - a second copy of the truth is how a
 * display ends up showing something nothing believes any more.
 *
 * Two pieces of timing live here because they are Android's, not the parser's:
 *
 *  - Android is flaky about rebinding a listener after a reinstall, so
 *    onListenerConnected re-reads the active notifications rather than waiting
 *    for the next post. Without this the app looks dead after every rebuild
 *    until navigation restarts.
 *  - The parser's end-of-route decision is debounced by ~15 s (Maps removes and
 *    immediately re-posts its notification mid-navigation), and a debounce needs
 *    something to fire it. Nothing else arrives during that window by
 *    definition, so a Handler drives poll().
 */
class NavListenerService : NotificationListenerService() {

    companion object {
        private const val TAG = "NAVLINK"
        private const val MAPS_PKG = "com.google.android.apps.maps"

        /** Cheap enough to run often; the parser's own deadline decides. */
        private const val POLL_MS = 1000L
    }

    private val parser by lazy { MapsParser(this) }
    private val handler = Handler(Looper.getMainLooper())

    private val poller = object : Runnable {
        override fun run() {
            parser.poll()?.let { push(it) }
            handler.postDelayed(this, POLL_MS)
        }
    }

    override fun onListenerConnected() {
        super.onListenerConnected()
        Log.i(TAG, "listener connected")

        // The link should be up before navigation starts, not after the first
        // packet - the device shows PHONE DISCONNECTED until a central appears,
        // and that is the screen the rider sees while pulling on gloves.
        LinkService.start(this)

        // Rebind after a reinstall does not replay what is already showing.
        runCatching { activeNotifications }
            .onSuccess { active -> active?.forEach { handleIfMaps(it) } }
            .onFailure { Log.w(TAG, "activeNotifications unavailable: ${it.message}") }

        handler.removeCallbacks(poller)
        handler.post(poller)
    }

    override fun onListenerDisconnected() {
        handler.removeCallbacks(poller)
        parser.reset()
        Log.w(TAG, "listener disconnected")
        super.onListenerDisconnected()
    }

    override fun onNotificationPosted(sbn: StatusBarNotification) {
        handleIfMaps(sbn)
        relayAlert(sbn)
    }

    override fun onNotificationRemoved(sbn: StatusBarNotification) {
        if (sbn.packageName != MAPS_PKG) return
        // Not the end of the route yet. Maps removes and re-posts constantly
        // during navigation; the parser starts a timer and poll() decides.
        parser.onRemoved(sbn)
    }

    private fun handleIfMaps(sbn: StatusBarNotification) {
        if (sbn.packageName != MAPS_PKG) return
        parser.onPosted(sbn)?.let { push(it) }
    }

    private fun push(update: NavUpdate) {
        LinkService.submitNav(update)
    }

    /**
     * Calls and messages, forwarded to the alert band.
     *
     * Read from the notification stream rather than from TelephonyManager: a
     * CallStyle notification carries the caller's name and costs no extra
     * permission, whereas READ_PHONE_STATE is a runtime grant for the same
     * information. Android 12 standardised CallStyle, which is why the category
     * test is reliable enough to act on.
     *
     * The device decides whether any of this is shown - under 100 m to a turn
     * the alert band is blank regardless of what arrives here.
     */
    private fun relayAlert(sbn: StatusBarNotification) {
        if (sbn.packageName == MAPS_PKG || sbn.packageName == packageName) return

        val n = sbn.notification ?: return
        val extras = n.extras ?: return
        val title = extras.getCharSequence(Notification.EXTRA_TITLE)?.toString().orEmpty()
        val text = extras.getCharSequence(Notification.EXTRA_TEXT)?.toString().orEmpty()

        if (n.category == Notification.CATEGORY_CALL) {
            /*
              Measured on the S24+: Samsung's incallui posts a CallStyle
              notification with title = the caller's name, text = "Incoming
              call", and FLAG_ONGOING_EVENT set *while it is still ringing* —
              because the dialer runs as a foreground service.

              An earlier version read that flag as "answered" and reported every
              call as active, which the device then declined to display. The
              flag says nothing about call state on this phone, so ringing is
              inferred from the text and the device shows either case anyway.
            */
            val ringing = text.contains("incoming", ignoreCase = true) ||
                          text.contains("calling", ignoreCase = true)
            val state = if (ringing) 1 else 2
            LinkService.sendPacket(
                PacketBuilder.call(state, title.ifBlank { text.ifBlank { "Call" } }), "CALL")
            return
        }

        if (sbn.isOngoing) return          // media, downloads, persistent status
        if (title.isBlank() && text.isBlank()) return

        val kind = when (n.category) {
            Notification.CATEGORY_MESSAGE -> 1
            Notification.CATEGORY_EMAIL -> 2
            Notification.CATEGORY_ALARM, Notification.CATEGORY_ERROR -> 3
            else -> 0
        }
        LinkService.sendPacket(PacketBuilder.notify(kind, title, text), "NOTIFY")
    }
}
