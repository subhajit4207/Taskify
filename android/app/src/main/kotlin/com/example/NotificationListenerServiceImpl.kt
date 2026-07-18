package com.example.my_app

import android.app.Notification
import android.content.Context
import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification
import org.json.JSONArray
import org.json.JSONObject

class NotificationListenerServiceImpl : NotificationListenerService() {

    private val allowedPackages = setOf(
        "com.whatsapp",
        "com.google.android.gm",
        "org.telegram.messenger",
        "com.discord"
    )

    private val storageName = "notification_listener_store"
    private val storageKey = "pending_notifications"

    override fun onNotificationPosted(sbn: StatusBarNotification) {
        val packageName = sbn.packageName ?: return
        if (!allowedPackages.contains(packageName)) return

        val extras = sbn.notification.extras
        val title = extras.getString(Notification.EXTRA_TITLE) ?: ""
        val text = extras.getCharSequence(Notification.EXTRA_TEXT)?.toString() ?: ""
        val subText = extras.getCharSequence(Notification.EXTRA_SUB_TEXT)?.toString() ?: ""
        val bigText = extras.getCharSequence(Notification.EXTRA_BIG_TEXT)?.toString() ?: ""

        val body = when {
            bigText.isNotBlank() -> bigText
            text.isNotBlank() -> text
            else -> ""
        }

        if (title.isBlank() && body.isBlank()) return

        val payload = mapOf(
            "packageName" to packageName,
            "title" to title,
            "body" to body,
            "subText" to subText,
            "postedAt" to System.currentTimeMillis()
        )

        saveNotification(payload)
        MainActivity.eventSink?.success(payload)
    }

    private fun saveNotification(payload: Map<String, Any>) {
        val prefs = getSharedPreferences(storageName, Context.MODE_PRIVATE)
        val existing = prefs.getString(storageKey, "[]") ?: "[]"
        val jsonArray = JSONArray(existing)

        val jsonObject = JSONObject()
        payload.forEach { (key, value) ->
            jsonObject.put(key, value)
        }

        jsonArray.put(jsonObject)
        prefs.edit().putString(storageKey, jsonArray.toString()).apply()
    }
}