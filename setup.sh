#!/bin/bash
set -e
mkdir -p "$(dirname 'build.gradle.kts')"
cat > 'build.gradle.kts' <<'ENDOFFILE_X'
plugins {
    id("com.android.application") version "8.5.2" apply false
    id("org.jetbrains.kotlin.android") version "1.9.24" apply false
}
ENDOFFILE_X
mkdir -p "$(dirname 'settings.gradle.kts')"
cat > 'settings.gradle.kts' <<'ENDOFFILE_X'
pluginManagement {
    repositories { google(); mavenCentral(); gradlePluginPortal() }
}
dependencyResolutionManagement {
    repositoriesMode.set(RepositoriesMode.FAIL_ON_PROJECT_REPOS)
    repositories { google(); mavenCentral() }
}
rootProject.name = "SleepTimer"
include(":app")
ENDOFFILE_X
mkdir -p "$(dirname 'gradle.properties')"
cat > 'gradle.properties' <<'ENDOFFILE_X'
org.gradle.jvmargs=-Xmx2048m
android.useAndroidX=true
kotlin.code.style=official
ENDOFFILE_X
mkdir -p "$(dirname 'app/build.gradle.kts')"
cat > 'app/build.gradle.kts' <<'ENDOFFILE_X'
plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
}
android {
    namespace = "com.sleeptimer"
    compileSdk = 34
    defaultConfig {
        applicationId = "com.sleeptimer"
        minSdk = 26
        targetSdk = 34
        versionCode = 1
        versionName = "1.0"
    }
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    kotlinOptions { jvmTarget = "17" }
}
ENDOFFILE_X
mkdir -p "$(dirname 'app/src/main/AndroidManifest.xml')"
cat > 'app/src/main/AndroidManifest.xml' <<'ENDOFFILE_X'
<?xml version="1.0" encoding="utf-8"?>
<manifest xmlns:android="http://schemas.android.com/apk/res/android">
    <uses-permission android:name="android.permission.WAKE_LOCK" />
    <uses-permission android:name="android.permission.USE_EXACT_ALARM" />
    <uses-permission android:name="android.permission.SCHEDULE_EXACT_ALARM" android:maxSdkVersion="32" />
    <application
        android:label="@string/app_name"
        android:theme="@android:style/Theme.DeviceDefault.Light">
        <activity android:name=".MainActivity" android:exported="true">
            <intent-filter>
                <action android:name="android.intent.action.MAIN" />
                <category android:name="android.intent.category.LAUNCHER" />
            </intent-filter>
        </activity>
        <receiver android:name=".SleepReceiver" android:exported="false" />
        <service
            android:name=".SleepAccessibilityService"
            android:exported="true"
            android:label="@string/app_name"
            android:permission="android.permission.BIND_ACCESSIBILITY_SERVICE">
            <intent-filter>
                <action android:name="android.accessibilityservice.AccessibilityService" />
            </intent-filter>
            <meta-data
                android:name="android.accessibilityservice"
                android:resource="@xml/accessibility_config" />
        </service>
    </application>
</manifest>
ENDOFFILE_X
mkdir -p "$(dirname 'app/src/main/java/com/sleeptimer/MainActivity.kt')"
cat > 'app/src/main/java/com/sleeptimer/MainActivity.kt' <<'ENDOFFILE_X'
package com.sleeptimer

import android.app.Activity
import android.content.Intent
import android.os.Bundle
import android.provider.Settings
import android.text.InputType
import android.widget.*

class MainActivity : Activity() {
    private lateinit var status: TextView
    private lateinit var minutes: EditText
    private val prefs by lazy { getSharedPreferences("cfg", MODE_PRIVATE) }
    private fun dp(v: Int) = (v * resources.displayMetrics.density).toInt()

    private fun btn(t: String, f: () -> Unit) = Button(this).apply {
        text = t; isAllCaps = false; setOnClickListener { f() }
    }

    override fun onCreate(b: Bundle?) {
        super.onCreate(b)
        val root = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(dp(20), dp(40), dp(20), dp(20))
        }
        root.addView(TextView(this).apply { text = "Sleep Timer"; textSize = 26f })

        root.addView(TextView(this).apply { text = "\nKitne minute baad?"; textSize = 16f })
        minutes = EditText(this).apply { inputType = InputType.TYPE_CLASS_NUMBER; setText("30") }
        root.addView(minutes)

        val row = LinearLayout(this).apply { orientation = LinearLayout.HORIZONTAL }
        for (m in listOf(15, 30, 60, 90)) {
            row.addView(btn("$m") { minutes.setText("$m") },
                LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f))
        }
        root.addView(row)

        root.addView(TextView(this).apply { text = "\nTimer khatam hone par:"; textSize = 16f })
        val opts = listOf(
            "bt" to "Bluetooth off", "hotspot" to "Hotspot off", "data" to "Mobile data off",
            "airplane" to "Airplane mode on", "lock" to "Screen lock"
        )
        for ((k, label) in opts) {
            root.addView(CheckBox(this).apply {
                text = label
                isChecked = prefs.getBoolean(k, k != "airplane")
                setOnCheckedChangeListener { _, v -> prefs.edit().putBoolean(k, v).apply() }
            })
        }

        root.addView(btn("Start timer") {
            val m = minutes.text.toString().toIntOrNull() ?: 30
            val fade = minOf(30000L, m * 30000L)
            SleepReceiver.schedule(this, m * 60000L - fade, fade)
            status.text = "Timer chalu: $m minute baad sab band hoga.\nAb screen band kar sakte ho."
        })
        root.addView(btn("Cancel timer") {
            SleepReceiver.cancel(this); status.text = "Timer cancel ho gaya."
        })
        root.addView(btn("Test abhi (5 second me)") {
            SleepReceiver.schedule(this, 1000, 5000)
            status.text = "Test chalu. Screen lock hone tak ruko."
        })
        root.addView(btn("Accessibility permission kholo") {
            startActivity(Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS))
        })
        root.addView(btn("App info kholo (Restricted settings)") {
            startActivity(Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
                android.net.Uri.parse("package:$packageName")))
        })

        status = TextView(this).apply { textSize = 14f; setPadding(0, dp(16), 0, 0) }
        root.addView(status)
        setContentView(ScrollView(this).apply { addView(root) })
    }

    override fun onResume() {
        super.onResume()
        val on = SleepAccessibilityService.instance != null
        val log = prefs.getString("log", "-")
        status.text = "Accessibility: ${if (on) "ON ✅" else "OFF ❌"}\n\nAakhri result:\n$log"
    }
}
ENDOFFILE_X
mkdir -p "$(dirname 'app/src/main/java/com/sleeptimer/SleepAccessibilityService.kt')"
cat > 'app/src/main/java/com/sleeptimer/SleepAccessibilityService.kt' <<'ENDOFFILE_X'
package com.sleeptimer

import android.accessibilityservice.AccessibilityService
import android.content.Context
import android.media.AudioManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.PowerManager
import android.view.KeyEvent
import android.view.accessibility.AccessibilityEvent
import android.view.accessibility.AccessibilityNodeInfo
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

class SleepAccessibilityService : AccessibilityService() {

    companion object {
        @Volatile var instance: SleepAccessibilityService? = null
    }

    private val h = Handler(Looper.getMainLooper())
    private var wl: PowerManager.WakeLock? = null
    private var origVol = -1
    private var am: AudioManager? = null
    private val log = StringBuilder()

    override fun onServiceConnected() { instance = this }
    override fun onAccessibilityEvent(e: AccessibilityEvent?) {}
    override fun onInterrupt() {}
    override fun onDestroy() { instance = null; cancelAll(); super.onDestroy() }

    private fun prefs() = getSharedPreferences("cfg", Context.MODE_PRIVATE)

    fun cancelAll() {
        h.removeCallbacksAndMessages(null)
        am?.let { if (origVol >= 0) it.setStreamVolume(AudioManager.STREAM_MUSIC, origVol, 0) }
        origVol = -1
        if (wl?.isHeld == true) wl?.release()
    }

    fun startFade(fadeMs: Long) {
        cancelAll()
        log.clear()
        val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
        wl = pm.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "sleeptimer:run").apply { acquire(180000) }
        val a = getSystemService(Context.AUDIO_SERVICE) as AudioManager
        am = a
        origVol = a.getStreamVolume(AudioManager.STREAM_MUSIC)
        var cur = origVol
        val interval = maxOf(fadeMs / maxOf(origVol, 1), 100L)
        val r = object : Runnable {
            override fun run() {
                if (cur > 0) {
                    cur--
                    a.setStreamVolume(AudioManager.STREAM_MUSIC, cur, 0)
                    h.postDelayed(this, interval)
                } else finishAudio(a)
            }
        }
        h.post(r)
    }

    private fun finishAudio(a: AudioManager) {
        a.dispatchMediaKeyEvent(KeyEvent(KeyEvent.ACTION_DOWN, KeyEvent.KEYCODE_MEDIA_PAUSE))
        a.dispatchMediaKeyEvent(KeyEvent(KeyEvent.ACTION_UP, KeyEvent.KEYCODE_MEDIA_PAUSE))
        log.append("Music pause bheja\n")
        h.postDelayed({
            if (origVol >= 0) a.setStreamVolume(AudioManager.STREAM_MUSIC, origVol, 0)
            origVol = -1
            runToggles()
        }, 700)
    }

    private fun runToggles() {
        val done = mutableSetOf<String>()
        performGlobalAction(GLOBAL_ACTION_QUICK_SETTINGS)
        h.postDelayed({ pass(done) }, 1500)
        h.postDelayed({ pass(done) }, 3000)
        h.postDelayed({
            if (prefs().getBoolean("lock", true)) {
                performGlobalAction(GLOBAL_ACTION_LOCK_SCREEN)
                log.append("Screen lock kiya\n")
            }
            val t = SimpleDateFormat("dd MMM HH:mm", Locale.getDefault()).format(Date())
            prefs().edit().putString("log", "$t\n$log").apply()
            if (wl?.isHeld == true) wl?.release()
        }, 4500)
    }

    // key, keywords, chahiye ON ya OFF
    private fun targets() = listOf(
        Triple("bt", listOf("bluetooth"), false),
        Triple("hotspot", listOf("hotspot"), false),
        Triple("data", listOf("mobile data", "cellular data", "mobile network"), false),
        Triple("airplane", listOf("airplane", "flight mode", "aeroplane"), true)
    )

    private fun pass(done: MutableSet<String>) {
        val roots = mutableListOf<AccessibilityNodeInfo>()
        rootInActiveWindow?.let { roots.add(it) }
        try { windows.forEach { w -> w.root?.let { roots.add(it) } } } catch (_: Exception) {}
        val nodes = mutableListOf<AccessibilityNodeInfo>()
        roots.forEach { walk(it, nodes) }

        for ((key, words, wantOn) in targets()) {
            if (key in done || !prefs().getBoolean(key, key != "airplane")) continue
            val tile = nodes.firstNotNullOfOrNull { n ->
                val lab = listOfNotNull(n.text, n.contentDescription).joinToString(" ").lowercase()
                if (words.any { lab.contains(it) }) clickable(n) else null
            }
            if (tile == null) { if (done.size >= 0 && key !in done) log.append("$key: tile nahi mila\n"); continue }
            val on = stateOf(tile)
            when {
                on == null -> log.append("$key: state pata nahi chala, skip\n")
                on == wantOn -> log.append("$key: pehle se sahi\n")
                else -> { tile.performAction(AccessibilityNodeInfo.ACTION_CLICK); log.append("$key: toggle kiya\n") }
            }
            done.add(key)
        }
    }

    private fun walk(n: AccessibilityNodeInfo?, out: MutableList<AccessibilityNodeInfo>) {
        if (n == null) return
        out.add(n)
        for (i in 0 until n.childCount) walk(n.getChild(i), out)
    }

    private fun clickable(n: AccessibilityNodeInfo): AccessibilityNodeInfo? {
        var x: AccessibilityNodeInfo? = n
        repeat(5) { if (x == null) return null; if (x!!.isClickable) return x; x = x!!.parent }
        return null
    }

    private fun stateOf(c: AccessibilityNodeInfo): Boolean? {
        if (c.isCheckable) return c.isChecked
        val l = mutableListOf<AccessibilityNodeInfo>()
        walk(c, l)
        val text = l.joinToString(" ") {
            val sd = if (Build.VERSION.SDK_INT >= 30) it.stateDescription else null
            listOfNotNull(it.text, it.contentDescription, sd).joinToString(" ")
        }.lowercase()
        return when {
            Regex("\\boff\\b").containsMatchIn(text) -> false
            Regex("\\bon\\b").containsMatchIn(text) -> true
            else -> null
        }
    }
}
ENDOFFILE_X
mkdir -p "$(dirname 'app/src/main/java/com/sleeptimer/SleepReceiver.kt')"
cat > 'app/src/main/java/com/sleeptimer/SleepReceiver.kt' <<'ENDOFFILE_X'
package com.sleeptimer

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

class SleepReceiver : BroadcastReceiver() {
    override fun onReceive(c: Context, i: Intent) {
        val fade = i.getLongExtra("fade", 30000L)
        val s = SleepAccessibilityService.instance
        if (s != null) s.startFade(fade)
        else c.getSharedPreferences("cfg", Context.MODE_PRIVATE).edit()
            .putString("log", "Timer baja par Accessibility service band thi. Permission check karo.").apply()
    }

    companion object {
        private fun pi(c: Context, fade: Long): PendingIntent {
            val i = Intent(c, SleepReceiver::class.java).putExtra("fade", fade)
            return PendingIntent.getBroadcast(c, 1, i, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        }

        fun schedule(c: Context, delayMs: Long, fadeMs: Long) {
            val am = c.getSystemService(Context.ALARM_SERVICE) as AlarmManager
            val at = System.currentTimeMillis() + delayMs
            try {
                am.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, at, pi(c, fadeMs))
            } catch (e: SecurityException) {
                am.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, at, pi(c, fadeMs))
            }
        }

        fun cancel(c: Context) {
            val am = c.getSystemService(Context.ALARM_SERVICE) as AlarmManager
            am.cancel(pi(c, 0))
            SleepAccessibilityService.instance?.cancelAll()
        }
    }
}
ENDOFFILE_X
mkdir -p "$(dirname 'app/src/main/res/xml/accessibility_config.xml')"
cat > 'app/src/main/res/xml/accessibility_config.xml' <<'ENDOFFILE_X'
<?xml version="1.0" encoding="utf-8"?>
<accessibility-service xmlns:android="http://schemas.android.com/apk/res/android"
    android:accessibilityEventTypes="typeWindowStateChanged"
    android:accessibilityFeedbackType="feedbackGeneric"
    android:accessibilityFlags="flagRetrieveInteractiveWindows|flagReportViewIds"
    android:canRetrieveWindowContent="true"
    android:notificationTimeout="100"
    android:description="@string/service_desc" />
ENDOFFILE_X
mkdir -p "$(dirname 'app/src/main/res/values/strings.xml')"
cat > 'app/src/main/res/values/strings.xml' <<'ENDOFFILE_X'
<resources>
    <string name="app_name">Sleep Timer</string>
    <string name="service_desc">Timer khatam hone par music band karta hai, Bluetooth/hotspot/data off karta hai aur phone lock karta hai.</string>
</resources>
ENDOFFILE_X
