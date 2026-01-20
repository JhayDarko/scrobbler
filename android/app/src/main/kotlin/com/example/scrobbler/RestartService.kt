package com.example.scrobbler

import android.app.Service
import android.content.Intent
import android.os.IBinder
import android.util.Log
import id.flutter.flutter_background_service.BackgroundService

/**
 * Servicio nativo liviano que se reinicia automáticamente cuando 
 * el usuario hace "Clear All" en el gestor de tareas.
 * 
 * Este servicio reinicia el BackgroundService de Flutter para mantener
 * la detección de música siempre activa.
 */
class RestartService : Service() {
    companion object {
        private const val TAG = "RestartService"
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        Log.d(TAG, "RestartService iniciado")
        return START_STICKY // Android reinicia el servicio si lo mata
    }

    override fun onTaskRemoved(rootIntent: Intent?) {
        super.onTaskRemoved(rootIntent)
        Log.d(TAG, "⚠️ App cerrada con Clear All - Reiniciando servicios...")
        
        // Reiniciar el Background Service de Flutter
        try {
            val restartIntent = Intent(applicationContext, BackgroundService::class.java)
            startService(restartIntent)
            Log.d(TAG, "✅ Background Service reiniciado exitosamente")
        } catch (e: Exception) {
            Log.e(TAG, "❌ Error reiniciando Background Service: ${e.message}")
        }
        
        // Reiniciar este mismo servicio para seguir monitoreando
        val restartServiceIntent = Intent(applicationContext, RestartService::class.java)
        startService(restartServiceIntent)
        
        stopSelf()
    }

    override fun onDestroy() {
        super.onDestroy()
        Log.d(TAG, "RestartService destruido - Reintentando iniciar...")
        
        // Si Android destruye este servicio, intentamos reiniciarlo
        val restartIntent = Intent(applicationContext, RestartService::class.java)
        startService(restartIntent)
    }
}
