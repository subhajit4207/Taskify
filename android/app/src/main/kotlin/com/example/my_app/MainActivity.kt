package com.example.my_app

import android.content.Intent
import android.content.Context
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import org.json.JSONArray

class MainActivity : FlutterActivity() {

    companion object {
        var eventSink: EventChannel.EventSink? = null
    }

    private val SETTINGS_CHANNEL = "notification_listener/settings"
    private val EVENTS_CHANNEL = "notification_listener/events"
    private val STORAGE_NAME = "notification_listener_store"
    private val STORAGE_KEY = "pending_notifications"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            SETTINGS_CHANNEL
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "openNotificationAccessSettings" -> {
                    startActivity(Intent(Settings.ACTION_NOTIFICATION_LISTENER_SETTINGS))
                    result.success(true)
                }

                "getPendingNotifications" -> {
                    val prefs = getSharedPreferences(STORAGE_NAME, Context.MODE_PRIVATE)
                    val jsonString = prefs.getString(STORAGE_KEY, "[]") ?: "[]"
                    result.success(jsonString)
                }

                "clearPendingNotifications" -> {
                    val prefs = getSharedPreferences(STORAGE_NAME, Context.MODE_PRIVATE)
                    prefs.edit().putString(STORAGE_KEY, "[]").apply()
                    result.success(true)
                }

                else -> result.notImplemented()
            }
        }

        EventChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            EVENTS_CHANNEL
        ).setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                eventSink = events
            }

            override fun onCancel(arguments: Any?) {
                eventSink = null
            }
        })
    }
}