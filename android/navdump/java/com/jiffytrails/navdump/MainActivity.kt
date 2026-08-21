package com.jiffytrails.navdump

import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.content.Intent
import android.graphics.Typeface
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import android.view.View
import android.view.ViewGroup.LayoutParams.MATCH_PARENT
import android.view.ViewGroup.LayoutParams.WRAP_CONTENT
import android.widget.Button
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.TextView
import android.widget.Toast
import androidx.appcompat.app.AppCompatActivity

class MainActivity : AppCompatActivity() {

    private lateinit var status: TextView
    private lateinit var logView: TextView
    private lateinit var scroll: ScrollView
    private val ui = Handler(Looper.getMainLooper())

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        val root = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(24, 24, 24, 24)
        }

        status = TextView(this).apply { textSize = 13f }
        root.addView(status, LinearLayout.LayoutParams(MATCH_PARENT, WRAP_CONTENT))

        val row = LinearLayout(this).apply { orientation = LinearLayout.HORIZONTAL }
        row.addView(Button(this).apply {
            text = "Grant access"
            setOnClickListener {
                startActivity(Intent(Settings.ACTION_NOTIFICATION_LISTENER_SETTINGS))
            }
        })
        row.addView(Button(this).apply {
            text = "Copy"
            setOnClickListener {
                val cm = getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
                cm.setPrimaryClip(ClipData.newPlainText("navdump", NavLog.snapshot()))
                Toast.makeText(this@MainActivity, "Copied", Toast.LENGTH_SHORT).show()
            }
        })
        row.addView(Button(this).apply {
            text = "Clear"
            setOnClickListener {
                NavLog.clear(applicationContext)
                logView.text = ""
            }
        })
        root.addView(row, LinearLayout.LayoutParams(MATCH_PARENT, WRAP_CONTENT))

        logView = TextView(this).apply {
            textSize = 10f
            typeface = Typeface.MONOSPACE
            setTextIsSelectable(true)
        }
        scroll = ScrollView(this).apply { addView(logView) }
        root.addView(scroll, LinearLayout.LayoutParams(MATCH_PARENT, 0, 1f))

        setContentView(root)
    }

    override fun onResume() {
        super.onResume()

        val granted = Settings.Secure
            .getString(contentResolver, "enabled_notification_listeners")
            ?.contains(packageName) == true

        status.text = if (granted) {
            "Listener: GRANTED\n${NavLog.logPath(this)}"
        } else {
            "Listener: NOT GRANTED\nTap 'Grant access', enable NavDump in the list."
        }

        logView.text = NavLog.snapshot()
        scroll.post { scroll.fullScroll(View.FOCUS_DOWN) }

        NavLog.listener = { line ->
            ui.post {
                logView.append(line + "\n")
                scroll.post { scroll.fullScroll(View.FOCUS_DOWN) }
            }
        }
    }

    override fun onPause() {
        super.onPause()
        NavLog.listener = null
    }
}
