plugins {
    alias(libs.plugins.android.application)
}

android {
    namespace = "com.jiffytrails.navlink"
    compileSdk {
        version = release(37)
    }

    defaultConfig {
        applicationId = "com.jiffytrails.navlink"
        // 26 matches NavDump. NotificationListenerService and BLE central both
        // work well below this; the floor is really Android 8's background
        // execution limits, which is what forces the foreground service.
        minSdk = 26
        targetSdk = 37
        versionCode = 1
        versionName = "1.0"
    }

    buildTypes {
        release {
            optimization {
                enable = false
            }
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }
}

dependencies {
    implementation(libs.androidx.core.ktx)
    implementation(libs.androidx.appcompat)
    implementation(libs.androidx.activity.ktx)
    testImplementation(libs.junit)
}
