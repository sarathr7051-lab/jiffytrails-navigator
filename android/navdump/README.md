# NavDump

Diagnostic app. Reads Google Maps' ongoing navigation notification and dumps
everything in it, so you can find out what data is actually available before
building anything that depends on it.

## What it does

- Filters to `category == "navigation"` from Maps, OsmAnd or Organic Maps
- Recurses into nested Bundles and arrays — opens up `progressSegments`
- Renders **every** Icon found anywhere in the extras as 32×32 ASCII art, plus a
  stable hash, printed once per distinct hash so the log stays small
- Resolves icon resource names where the icon is `type=2`
- Emits **one compact SUM line per update** so a whole ride is readable:

```
SUM 20:04:16.2 | 700 m | 700 m · Slight right onto Horamavu Agara Main Rd
               | Horamavu Agara Main Rd | Arrive 8:07 pm | 56/851 | chip=d5fc816e
```

- Full dumps only when the key set or an icon changes, plus a checkpoint every
  60 s
- Writes to a file so you can ride with the phone in your pocket and read it
  afterwards

## Build

Android Studio → New Project → **Empty Views Activity** (Views, not Compose).

| Field | Value |
|---|---|
| Package | `com.jiffytrails.navdump` |
| Language | Kotlin |
| Min SDK | 26 |

Keep the project out of OneDrive and out of paths containing spaces or
non-ASCII characters.

Copy `AndroidManifest.xml` and the three `.kt` files into place. No extra Gradle
dependencies. Check `res/values/themes.xml` defines `Theme.NavDump` and matches
the manifest.

## Run

1. Install, tap **Grant access**, enable NavDump in Android's notification
   access list
2. Settings → Apps → NavDump → Battery → **Unrestricted**. On Samsung also check
   Battery → Background usage limits and remove it from Sleeping apps
3. Start Maps navigation and check entries appear

**If the log stays empty**, toggle notification access off and back on. Android
is flaky about rebinding a listener service after a reinstall — do this after
every rebuild.

## Retrieving the log

```
adb pull /sdcard/Android/data/com.jiffytrails.navdump/files/navdump.log
```

If permission is denied on Android 11+:

```
adb exec-out run-as com.jiffytrails.navdump cat \
  /sdcard/Android/data/com.jiffytrails.navdump/files/navdump.log > navdump.log
```

Or use the in-app **Copy** button — the buffer holds 3000 entries, enough for a
full ride.

## Reading it

See [../../docs/NAV_DATA.md](../../docs/NAV_DATA.md) for what the fields mean
and what to look for.
