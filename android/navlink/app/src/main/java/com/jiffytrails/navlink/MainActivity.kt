package com.jiffytrails.navlink

import android.Manifest
import android.content.Intent
import android.graphics.Color
import android.graphics.Typeface
import android.os.Build
import android.os.Bundle
import android.provider.Settings
import android.util.TypedValue
import android.view.Gravity
import android.view.ViewGroup.LayoutParams.MATCH_PARENT
import android.view.ViewGroup.LayoutParams.WRAP_CONTENT
import android.widget.Button
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.TextView
import androidx.activity.result.contract.ActivityResultContracts
import androidx.appcompat.app.AppCompatActivity
import androidx.core.content.ContextCompat

/**
 * Setup and status. Nothing about navigation happens here - the listener and
 * the link service do that whether this screen is open or not.
 *
 * The job of this activity is the boring half that decides whether the whole
 * thing works: three grants that are easy to miss and produce silent failure
 * rather than an error. Every one is shown with its current state, so "why is
 * my display blank" has an answer on one screen.
 *
 * Built in code rather than XML deliberately - it is a diagnostics panel for
 * one user, and a layout file would be more to keep in step than it is worth.
 */
class MainActivity : AppCompatActivity() {

    private lateinit var status: TextView
    private lateinit var permissionsText: TextView

    private val requestPerms =
        registerForActivityResult(ActivityResultContracts.RequestMultiplePermissions()) {
            refresh()
        }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        val pad = dp(20)
        val root = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(pad, pad, pad, pad)
        }

        root.addView(heading("JiffyTrails"))
        root.addView(body("Relays Google Maps navigation to the handlebar display."))

        permissionsText = body("")
        root.addView(sectionLabel("Setup"))
        root.addView(permissionsText)

        root.addView(button("Grant Bluetooth permissions") {
            val missing = btPermissions().filter { p ->
                ContextCompat.checkSelfPermission(this, p) != android.content.pm.PackageManager.PERMISSION_GRANTED
            }.toMutableList()
            if (Build.VERSION.SDK_INT >= 33 &&
                ContextCompat.checkSelfPermission(this, Manifest.permission.POST_NOTIFICATIONS)
                != android.content.pm.PackageManager.PERMISSION_GRANTED
            ) {
                missing += Manifest.permission.POST_NOTIFICATIONS
            }
            if (missing.isEmpty()) refresh() else requestPerms.launch(missing.toTypedArray())
        })

        root.addView(button("Notification access") {
            // No runtime prompt exists for this one; it is a Settings screen.
            startActivity(Intent(Settings.ACTION_NOTIFICATION_LISTENER_SETTINGS))
        })

        root.addView(button("Battery optimisation") {
            startActivity(LinkService.batteryOptimisationSettings())
        })

        root.addView(sectionLabel("Link"))
        status = body("")
        root.addView(status)

        root.addView(button("Start link") {
            // Must be started from the foreground: Android 12+ refuses a
            // background foreground-service start, and the listener service can
            // find itself in exactly that position after a reboot.
            LinkService.start(this)
            refresh()
        })
        root.addView(button("Stop link") {
            LinkService.stop(this)
            refresh()
        })

        setContentView(ScrollView(this).apply {
            addView(root, LinearLayout.LayoutParams(MATCH_PARENT, WRAP_CONTENT))
        })

        LinkService.link.observe { runOnUiThread { refresh() } }
        LinkService.service.observe { runOnUiThread { refresh() } }
    }

    override fun onResume() {
        super.onResume()
        // Both notification access and the battery whitelist are granted on a
        // Settings screen with no broadcast back, so the only reliable moment
        // to re-read them is when this activity returns to the foreground.
        LinkService.refreshPowerState(this)
        refresh()
    }

    private fun refresh() {
        val svc = LinkService.service.value
        val link = LinkService.link.value

        val btGranted = btPermissions().all { p ->
            ContextCompat.checkSelfPermission(this, p) == android.content.pm.PackageManager.PERMISSION_GRANTED
        }

        permissionsText.text = buildString {
            appendLine("${tick(btGranted)}  Bluetooth permissions")
            appendLine("${tick(notificationAccessGranted())}  Notification access")
            appendLine("${tick(svc.batteryOptimisationExempt)}  Battery optimisation exempt")
            if (svc.vendorWhitelistUnverifiable) {
                appendLine()
                appendLine(
                    "This phone (${svc.vendorSkin}) has a second autostart list " +
                    "with no public API, so the app cannot confirm it. If the link " +
                    "dies mid-ride, that list is the first place to look."
                )
            }
        }.trimEnd()

        status.text = buildString {
            appendLine("Phase      ${link.phase}")
            appendLine("MTU        ${link.mtu}")
            appendLine("Sent       ${link.packetsSent}   failed ${link.packetsFailed}")
            link.error?.let { appendLine("Last error $it") }
        }.trimEnd()
    }

    /**
     * The same split BleLink enforces. Inlined rather than imported: below
     * Android 12 a BLE scan is location-capable and the platform wants
     * ACCESS_FINE_LOCATION instead of the newer pair.
     */
    private fun btPermissions(): Array<String> =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            arrayOf(Manifest.permission.BLUETOOTH_SCAN, Manifest.permission.BLUETOOTH_CONNECT)
        } else {
            arrayOf(Manifest.permission.ACCESS_FINE_LOCATION)
        }

    private fun notificationAccessGranted(): Boolean {
        val flat = Settings.Secure.getString(contentResolver, "enabled_notification_listeners")
        return flat?.contains(packageName) == true
    }

    private fun tick(ok: Boolean) = if (ok) "[x]" else "[ ]"

    // ------------------------------------------------------------- tiny views

    private fun heading(t: String) = TextView(this).apply {
        text = t
        setTextSize(TypedValue.COMPLEX_UNIT_SP, 26f)
        setTypeface(typeface, Typeface.BOLD)
    }

    private fun sectionLabel(t: String) = TextView(this).apply {
        text = t.uppercase()
        setTextSize(TypedValue.COMPLEX_UNIT_SP, 12f)
        setTypeface(typeface, Typeface.BOLD)
        setTextColor(Color.GRAY)
        setPadding(0, dp(20), 0, dp(6))
    }

    private fun body(t: String) = TextView(this).apply {
        text = t
        setTextSize(TypedValue.COMPLEX_UNIT_SP, 14f)
        typeface = Typeface.MONOSPACE
    }

    private fun button(t: String, onClick: () -> Unit) = Button(this).apply {
        text = t
        gravity = Gravity.START or Gravity.CENTER_VERTICAL
        setOnClickListener { onClick() }
    }

    private fun dp(v: Int) = (v * resources.displayMetrics.density).toInt()
}
