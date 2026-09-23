package com.example.browser_flutter

import android.content.Context
import android.net.wifi.WifiManager
import android.os.PowerManager
import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

// AudioServiceActivity keeps the Flutter engine alive while the service runs.
class MainActivity : AudioServiceActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val app = applicationContext
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "vox/keepalive")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "acquire" -> {
                        KeepAlive.acquire(app, (call.argument<Int>("timeoutMs") ?: 0).toLong())
                        result.success(true)
                    }
                    "release" -> { KeepAlive.release(); result.success(true) }
                    else -> result.notImplemented()
                }
            }
    }
}

/** Process-wide so it survives Activity recreation. */
object KeepAlive {
    private var wake: PowerManager.WakeLock? = null
    private var wifi: WifiManager.WifiLock? = null

    @Synchronized
    fun acquire(ctx: Context, timeoutMs: Long) {
        if (wake == null) {
            val pm = ctx.getSystemService(Context.POWER_SERVICE) as PowerManager
            wake = pm.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "vox:reading")
                .apply { setReferenceCounted(false) }
        }
        if (timeoutMs > 0) wake?.acquire(timeoutMs) else wake?.acquire()

        if (wifi == null) {
            val wm = ctx.applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager
            wifi = wm.createWifiLock(WifiManager.WIFI_MODE_FULL_HIGH_PERF, "vox:reading")
                .apply { setReferenceCounted(false) }
        }
        wifi?.acquire()
    }

    @Synchronized
    fun release() {
        wake?.let { if (it.isHeld) it.release() }
        wifi?.let { if (it.isHeld) it.release() }
    }
}