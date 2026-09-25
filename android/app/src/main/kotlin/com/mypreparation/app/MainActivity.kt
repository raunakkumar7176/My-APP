package com.mypreparation.app

import android.content.res.Configuration
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/// Test-integrity native support: screenshot/screen-recording prevention
/// (FLAG_SECURE, toggled only while a live test is on screen — never a
/// permanent restriction) and multi-window/split-screen entry detection.
/// Flutter is the event detector; this activity only reports what the OS
/// tells it and applies the window flag Flutter asks for. No security
/// decision is made here — the server (rpc_record_integrity_event) is the
/// authority on counts/thresholds/auto-submit.
class MainActivity : FlutterActivity() {
    private val integrityChannelName = "my_praperation/integrity"
    private var integrityChannel: MethodChannel? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, integrityChannelName)
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "setSecureFlag" -> {
                    val enabled = call.argument<Boolean>("enabled") ?: false
                    if (enabled) {
                        window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
                    } else {
                        window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
                    }
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
        integrityChannel = channel
    }

    override fun onMultiWindowModeChanged(isInMultiWindowMode: Boolean, newConfig: Configuration) {
        super.onMultiWindowModeChanged(isInMultiWindowMode, newConfig)
        integrityChannel?.invokeMethod(
            "onMultiWindowModeChanged",
            mapOf("isInMultiWindowMode" to isInMultiWindowMode)
        )
    }

    override fun onDestroy() {
        // Never leave FLAG_SECURE set past this activity's lifetime — it is
        // a per-window flag anyway, but clear it explicitly for clarity.
        window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
        integrityChannel = null
        super.onDestroy()
    }
}
