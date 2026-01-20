package com.example.scrobbler

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.SystemClock
import android.util.Log
import id.flutter.flutter_background_service.BackgroundService

/**
 * Watchdog (Perro guardián) que verifica periódicamente si el BackgroundService está corriendo.
 * 
 * Se ejecuta cada 15 minutos mediante AlarmManager (manejado por el sistema operativo).
 * Si detecta que el BackgroundService no está corriendo, lo reinicia automáticamente.
 * 
 * Este mecanismo sobrevive a "Clear All" porque AlarmManager es independiente del proceso de la app.
 */
class WatchdogReceiver : BroadcastReceiver() {
    companion object {
        private const val TAG = "WatchdogReceiver"
        private const val CHECK_INTERVAL_MS = 15 * 60 * 1000L // 15 minutos
        
        /**
         * Programa el próximo check del watchdog
         */
        fun scheduleNext(context: Context) {
            val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
            val intent = Intent(context, WatchdogReceiver::class.java)
            val pendingIntent = PendingIntent.getBroadcast(
                context,
                0,
                intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
            
            val triggerTime = SystemClock.elapsedRealtime() + CHECK_INTERVAL_MS
            
            // Usar setExactAndAllowWhileIdle para que funcione incluso en Doze mode
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                alarmManager.setExactAndAllowWhileIdle(
                    AlarmManager.ELAPSED_REALTIME_WAKEUP,
                    triggerTime,
                    pendingIntent
                )
            } else {
                alarmManager.setExact(
                    AlarmManager.ELAPSED_REALTIME_WAKEUP,
                    triggerTime,
                    pendingIntent
                )
            }
            
            Log.d(TAG, "⏰ Próximo watchdog check programado en 15 minutos")
        }
    }
    
    override fun onReceive(context: Context, intent: Intent) {
        Log.d(TAG, "🐕 Watchdog ejecutándose - Verificando estado del servicio...")
        
        // Verificar si el BackgroundService está corriendo
        // NOTA: No hay API directa para verificar si un Service está corriendo
        // Pero podemos intentar iniciarlo, y si ya está corriendo, no pasa nada
        try {
            val serviceIntent = Intent(context, BackgroundService::class.java)
            context.startService(serviceIntent)
            Log.d(TAG, "✅ BackgroundService verificado/reiniciado")
        } catch (e: Exception) {
            Log.e(TAG, "❌ Error reiniciando BackgroundService: ${e.message}")
        }
        
        // Programar el próximo check
        scheduleNext(context)
    }
}
