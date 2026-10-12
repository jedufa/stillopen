package com.stillopen.app

import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
import android.util.Patterns
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.android.FlutterActivity
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val initialExtras = mutableListOf<Map<String, Any?>>()
    private var extrasSink: EventChannel.EventSink? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "stillopen/notification_settings"
        ).setMethodCallHandler { call, result ->
            if (call.method != "openNotificationSettings") {
                result.notImplemented()
            } else {
                try {
                    val settings = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                        Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS)
                            .putExtra(Settings.EXTRA_APP_PACKAGE, packageName)
                    } else {
                        Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
                            Uri.parse("package:$packageName"))
                    }
                    startActivity(settings)
                    result.success(null)
                } catch (error: Exception) {
                    result.error("settings_unavailable", "Could not open notification settings", null)
                }
            }
        }
        captureMixedShareText(intent, initial = true)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "stillopen/incoming_share_extras"
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "getInitialShareExtras" -> result.success(initialExtras.toList())
                "resetInitialShareExtras" -> {
                    initialExtras.clear()
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
        EventChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "stillopen/incoming_share_extras_stream"
        ).setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                extrasSink = events
            }

            override fun onCancel(arguments: Any?) {
                extrasSink = null
            }
        })
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        captureMixedShareText(intent, initial = false)
    }

    private fun captureMixedShareText(intent: Intent?, initial: Boolean) {
        if (intent == null) return
        if (intent.action != Intent.ACTION_SEND && intent.action != Intent.ACTION_SEND_MULTIPLE) return
        val text = intent.getStringExtra(Intent.EXTRA_TEXT)?.trim().orEmpty()
        if (text.isBlank()) return
        val clipData = intent.clipData
        val hasClipUri = (0 until (clipData?.itemCount ?: 0)).any { index ->
            clipData?.getItemAt(index)?.uri != null
        }
        val hasStream = intent.hasExtra(Intent.EXTRA_STREAM) || hasClipUri
        if (!hasStream) return
        val payload = mapOf(
            "text" to text,
            "isUrl" to Patterns.WEB_URL.matcher(text).find(),
            "action" to (intent.action ?: ""),
        )
        if (initial) {
            initialExtras.add(payload)
        } else {
            extrasSink?.success(listOf(payload))
        }
    }
}
