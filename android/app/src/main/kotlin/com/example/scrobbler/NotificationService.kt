package com.example.scrobbler

import android.app.Notification
import android.content.Context
import android.content.SharedPreferences
import android.media.MediaMetadata
import android.media.session.MediaController
import android.media.session.MediaSession
import android.os.Build
import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification
import android.util.Log
import org.json.JSONArray
import org.json.JSONObject

class NotificationService : NotificationListenerService() {

    companion object {
        private const val TAG = "NotificationService"
        private const val PREFS_NAME = "FlutterSharedPreferences" // Estándar de shared_preferences plugin
        private const val KEY_QUEUE = "flutter.scrobble_queue" // "flutter." prefijo obligatorio
    }

    override fun onListenerConnected() {
        super.onListenerConnected()
        Log.d(TAG, "🔌 SERVICIO DE NOTIFICACIONES CONECTADO Y ESCUCHANDO")
    }

    override fun onListenerDisconnected() {
        super.onListenerDisconnected()
        Log.d(TAG, "🔌 SERVICIO DE NOTIFICACIONES DESCONECTADO")
    }

    override fun onNotificationPosted(sbn: StatusBarNotification?) {
        super.onNotificationPosted(sbn)
        
        if (sbn == null) return
        
        val packageName = sbn.packageName
        
        // LOG: Todas las notificaciones recibidas para debugging
        Log.d(TAG, "📱 Notificación recibida de: $packageName")
        
        // Filtrar solo YouTube Music
        if (packageName != "com.google.android.apps.youtube.music") {
            Log.d(TAG, "⏭️ Ignorando paquete: $packageName")
            return
        }
        
        Log.d(TAG, "✅ Procesando notificación de YouTube Music")

        try {
            val extras = sbn.notification.extras
            var title = extras.getString("android.title")
            var text = extras.getCharSequence("android.text")?.toString()
            var subText = extras.getCharSequence("android.subText")?.toString()
            var album = ""
            var duration: Long = 0
            var artist = ""

            // --- FASE 1: Extracción Visual ---
            if (!subText.isNullOrEmpty()) {
                if (subText != "YouTube Music" && subText != "Siguiente" && subText != "Anterior") {
                    album = subText
                }
            }
            if (album.isEmpty() && !text.isNullOrEmpty() && text!!.contains(" • ")) {
                val parts = text!!.split(" • ")
                if (parts.size > 1) album = parts[1].trim()
            }
            if (!text.isNullOrEmpty()) {
                 if (text!!.contains(" • ")) {
                     artist = text!!.split(" • ")[0].trim()
                 } else {
                     artist = text!!
                 }
            }

            // --- FASE 2: Metadata ---
            val token = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                extras.getParcelable(Notification.EXTRA_MEDIA_SESSION, MediaSession.Token::class.java)
            } else {
                @Suppress("DEPRECATION")
                extras.getParcelable(Notification.EXTRA_MEDIA_SESSION)
            }
            
            if (token != null) {
                val controller = MediaController(this, token)
                val metadata = controller.metadata
                
                if (metadata != null) {
                    val metaTitle = metadata.getString(MediaMetadata.METADATA_KEY_TITLE)
                    val metaArtist = metadata.getString(MediaMetadata.METADATA_KEY_ARTIST)
                    val metaAlbum = metadata.getString(MediaMetadata.METADATA_KEY_ALBUM)
                    val metaDuration = metadata.getLong(MediaMetadata.METADATA_KEY_DURATION)
                    
                    if (!metaTitle.isNullOrEmpty()) title = metaTitle
                    if (!metaArtist.isNullOrEmpty()) artist = metaArtist
                    if (!metaAlbum.isNullOrEmpty()) album = metaAlbum
                    if (metaDuration > 0) duration = metaDuration
                }
            }

            // --- FASE 3: Guardar en Cola Persistente (JSON) ---
            if (!title.isNullOrEmpty()) {
                val eventJson = JSONObject()
                eventJson.put("timestamp", System.currentTimeMillis())
                eventJson.put("title", title)
                eventJson.put("artist", artist)
                eventJson.put("album", album)
                eventJson.put("duration", duration)
                eventJson.put("source", packageName)

                saveToQueue(eventJson)
                Log.d(TAG, "💾 Evento guardado en cola: $title")
            }

        } catch (e: Exception) {
            Log.e(TAG, "Error procesando notificación", e)
        }
    }

    private fun saveToQueue(item: JSONObject) {
        val prefs: SharedPreferences = getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        val currentQueueStr = prefs.getString(KEY_QUEUE, "[]")
        
        try {
            val queue = JSONArray(currentQueueStr)
            queue.put(item)
            
            // Limitamos la cola a los últimos 50 eventos para no saturar memoria
            val finalQueue = if (queue.length() > 50) {
                 val newQueue = JSONArray()
                 for (i in (queue.length() - 50) until queue.length()) {
                     newQueue.put(queue.get(i))
                 }
                 newQueue
            } else {
                queue
            }

            prefs.edit().putString(KEY_QUEUE, finalQueue.toString()).apply()
        } catch (e: Exception) {
            Log.e(TAG, "Error guardando en cola JSON", e)
        }
    }
}
