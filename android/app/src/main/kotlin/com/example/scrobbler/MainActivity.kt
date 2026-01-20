package com.example.scrobbler

import android.content.ComponentName
import android.content.Intent
import android.provider.Settings
import android.text.TextUtils
import androidx.annotation.NonNull
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val METHOD_CHANNEL = "com.example.scrobbler/notifications_method"
    private val RESTART_CHANNEL = "com.example.scrobbler/restart_service"

    override fun configureFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // Configurar MethodChannel para permisos
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, METHOD_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "isPermissionGranted" -> {
                    result.success(isNotificationServiceEnabled())
                }
                "requestPermission" -> {
                    startActivity(Intent(Settings.ACTION_NOTIFICATION_LISTENER_SETTINGS))
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }
        
        // Configurar MethodChannel para RestartService
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, RESTART_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "startRestartService" -> {
                    try {
                        val restartIntent = Intent(this, RestartService::class.java)
                        startService(restartIntent)
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("ERROR", "Failed to start RestartService: ${e.message}", null)
                    }
                }
                "startWatchdog" -> {
                    try {
                        WatchdogReceiver.scheduleNext(applicationContext)
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("ERROR", "Failed to start Watchdog: ${e.message}", null)
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun isNotificationServiceEnabled(): Boolean {
        val pkgName = packageName
        val flat = Settings.Secure.getString(contentResolver, "enabled_notification_listeners")
        if (!TextUtils.isEmpty(flat)) {
            val names = flat.split(":")
            for (name in names) {
                val cn = ComponentName.unflattenFromString(name)
                if (cn != null) {
                    if (TextUtils.equals(pkgName, cn.packageName)) {
                        return true
                    }
                }
            }
        }
        return false
    }
}
