package com.jiffytrails.navlink

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

/**
 * Fire one wrist alert from a terminal, so the path can be proved without
 * starting a route:
 *
 *     adb shell am broadcast -a com.jiffytrails.navlink.TEST_WRIST \
 *         -n com.jiffytrails.navlink/.WristTestReceiver
 *
 * then watch for the post in logcat:
 *
 *     adb logcat -s NAVLINK/wrist
 *
 * ★ DEBUG BUILDS ONLY, and it lives in src/debug precisely so that is
 * structural rather than a promise. It has to be exported to be reachable from
 * the shell, and an exported receiver that posts a notification is a surface
 * any app on the phone could poke. That is a fair trade for a build that only
 * ever lands on one developer's handset, and no trade at all for a release
 * build, which does not contain this class or its manifest entry.
 *
 * MainActivity's "Send a test alert" button does the same thing and ships in
 * every build - it needs no export because the tap is already inside the app.
 */
class WristTestReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        WristAlert.test(context.applicationContext)
    }
}
