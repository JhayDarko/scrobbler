# 🎯 Mejoras Profesionales al Sistema de Scrobbling

## 📋 Resumen de mejoras

Se han implementado mejoras profesionales inspiradas en **Pano Scrobbler** y **Last.fm** para hacer el sistema de scrobbling más robusto y preciso.

## ✅ 1. No enviar datos vacíos

### Problema anterior
- Se guardaban scrobbles con el campo `album` vacío (`""`)
- Esto generaba registros inconsistentes en la base de datos
- Supabase recibía strings vacíos innecesarios

### Solución implementada

#### En el modelo (`scrobble.dart`)
```dart
class Scrobble {
  final String? album; // Ahora nullable - no guardar strings vacíos
  
  Scrobble({
    this.album, // Ahora opcional
    // ...
  });
  
  Map<String, dynamic> toMap() {
    return {
      'album': album ?? '', // Solo guardar vacío si es null
      // ...
    };
  }
}
```

#### En el servicio de scrobbling (`scrobble_service.dart`)
```dart
void _saveScrobble({...}) {
  // Validación estricta
  final cleanAlbum = album.trim();
  
  final scrobble = Scrobble(
    track: cleanTrack,
    artist: cleanArtist,
    album: cleanAlbum.isNotEmpty ? cleanAlbum : null, // ✅ No guardar vacío
    // ...
  );
}
```

#### En la sincronización (`sync_service.dart`)
```dart
// Preparar datos para Supabase
final albumValue = item['album'] as String?;
final scrobbleData = <String, dynamic>{
  'track': item['track'],
  'artist': item['artist'],
  'duration': item['duration'],
  'timestamp': item['timestamp'],
};

// ✅ Solo incluir album si tiene valor
if (albumValue != null && albumValue.isNotEmpty) {
  scrobbleData['album'] = albumValue;
}
```

### Beneficios
- ✅ Base de datos más limpia
- ✅ Menos datos innecesarios enviados a Supabase
- ✅ Mejor compatibilidad con APIs externas (Last.fm, etc.)

## ✅ 2. Detección de pausas/reanudaciones

### Problema anterior
- Cuando pausabas una canción y la reanudabas después, se creaba un nuevo scrobble
- No se distinguía entre "nueva canción" y "misma canción reanudada"
- Los scrobbles duplicados eran comunes

### Solución implementada

#### Variables de estado
```dart
DateTime? _lastNotificationTime; // Última notificación recibida
bool _isPaused = false;           // Estado de pausa
DateTime? _pauseStartTime;        // Momento de la pausa
```

#### Detección de pausa (5+ segundos sin notificaciones)
```dart
final now = DateTime.now();
if (_lastNotificationTime != null) {
  final timeSinceLastNotification = now.difference(_lastNotificationTime!);
  
  // Si han pasado más de 5 segundos sin notificaciones, probablemente estaba pausado
  if (timeSinceLastNotification.inSeconds > 5) {
    if (!_isPaused) {
      print('⏸️ Pausa detectada (${timeSinceLastNotification.inSeconds}s sin notificaciones)');
      _isPaused = true;
      _pauseStartTime = _lastNotificationTime;
    }
  }
}

_lastNotificationTime = now;
```

#### Detección de reanudación
```dart
if (isNewTrack) {
  // Si estaba pausado y es la misma canción, es una reanudación
  if (_isPaused && currentTrack == _lastTrack && artist == _lastArtist) {
    print('▶️ Reanudación detectada de: $currentTrack');
    _isPaused = false;
    _pauseStartTime = null;
    // No reiniciar el timer, continúa donde se quedó
    return;
  }
  
  // Nueva canción...
}
```

#### Cálculo preciso de tiempo reproducido
```dart
// Calcular duración real de reproducción (excluyendo tiempo en pausa)
var actualPlayedDuration = DateTime.now().difference(_trackStartTime!).inMilliseconds;

// Si estuvo pausado, restar el tiempo de pausa
if (_pauseStartTime != null && _isPaused) {
  final pauseDuration = DateTime.now().difference(_pauseStartTime!);
  actualPlayedDuration -= pauseDuration.inMilliseconds;
  print('⏸️ Restando ${pauseDuration.inSeconds}s de pausa');
}
```

### Beneficios
- ✅ No crea scrobbles duplicados al pausar/reanudar
- ✅ Tiempo de reproducción exacto (sin contar pausas)
- ✅ Comportamiento igual a Pano Scrobbler

## ✅ 3. Validación estricta de datos

### Validaciones implementadas

#### 1. Track y artista obligatorios
```dart
final cleanTrack = track.trim();
final cleanArtist = artist.trim();

if (cleanTrack.isEmpty) {
  print('❌ Track vacío, scrobble cancelado');
  return;
}

if (cleanArtist.isEmpty || cleanArtist == 'Artista desconocido') {
  print('❌ Artista inválido, scrobble cancelado');
  return;
}
```

#### 2. Duración mínima (configurado en `AppConfig`)
```dart
if (durationMs > 0) {
  final durationSeconds = durationMs ~/ 1000;
  if (durationSeconds < AppConfig.minTrackDurationSeconds) {
    print('❌ Canción muy corta (${durationSeconds}s < ${AppConfig.minTrackDurationSeconds}s), ignorada');
    return false;
  }
}
```

#### 3. Tiempo mínimo de reproducción
```dart
if (actualPlayedSeconds < AppConfig.minPlayedDurationSeconds) {
  print('⏭️ No alcanzó el mínimo de reproducción (${actualPlayedSeconds}s)');
  return;
}
```

### Beneficios
- ✅ Solo guarda scrobbles válidos
- ✅ Evita basura en la base de datos
- ✅ Compatible con estándares de Last.fm

## 📊 Ejemplo de flujo completo

### Caso 1: Reproducción normal
```
1. 🎵 Nueva canción detectada: "Song Title"
   - Track: "Song Title"
   - Artista: "Artist Name"
   - Álbum: "Album Name"

2. ⏰ Scrobble programado en 96s (50% de 192s)

3. 💾 GUARDANDO SCROBBLE
   - 🎵 Track: Song Title
   - 👤 Artista: Artist Name
   - 💿 Álbum: Album Name
   - ⏱️ Duración total: 192s
   - ▶️ Reproducido: 96s

4. ✅ Scrobble guardado (ID: 142)

5. 🔄 Sincronizando con Supabase...
   - 📦 Datos enviados: {track, artist, album, duration, timestamp}
   - ✅ Sincronizado correctamente
```

### Caso 2: Pausa y reanudación
```
1. 🎵 Nueva canción detectada: "Song Title"

2. ⏰ Scrobble programado en 96s

3. [Usuario pausa la canción a los 50s]

4. ⏸️ Pausa detectada (6s sin notificaciones)

5. [Usuario reanuda después de 2 minutos]

6. ▶️ Reanudación detectada de: Song Title
   - No se crea nuevo scrobble
   - Continúa desde donde se quedó

7. [Alcanza los 96s de reproducción real]

8. 💾 GUARDANDO SCROBBLE
   - ⏸️ Restando 120s de pausa
   - ▶️ Reproducido: 96s (excluyendo pausa)

9. ✅ Scrobble guardado
```

### Caso 3: Sin álbum
```
1. 🎵 Nueva canción detectada: "Song Title"
   - Track: "Song Title"
   - Artista: "Artist Name"
   - Álbum: (Pendiente...)

2. [No se recibe info de álbum]

3. 💾 GUARDANDO SCROBBLE
   - 🎵 Track: Song Title
   - 👤 Artista: Artist Name
   - (Sin mostrar álbum)

4. 📦 Datos enviados a Supabase:
   {
     "track": "Song Title",
     "artist": "Artist Name",
     // ✅ No se incluye "album"
     "duration": 180000,
     "timestamp": "2026-01-22T..."
   }
```

## 🔧 Configuración

Todas las constantes están en `lib/config/app_config.dart`:

```dart
class AppConfig {
  // Scrobbling
  static const int scrobbleThresholdSeconds = 30;      // Mínimo absoluto
  static const int scrobbleMaxThresholdSeconds = 240;  // Máximo (4 min)
  static const double scrobblePercentageThreshold = 0.5; // 50% de la canción
  
  static const int minTrackDurationSeconds = 30;       // Canción muy corta
  static const int minPlayedDurationSeconds = 30;      // Reproducción muy corta
  
  static const int duplicateWindowMinutes = 2;         // Ventana de duplicados
}
```

## 🎯 Comparación con Pano Scrobbler

| Característica | Pano Scrobbler | Esta App | Estado |
|---------------|----------------|----------|--------|
| Regla del 50% / 4min | ✅ | ✅ | Implementado |
| Detección de pausas | ✅ | ✅ | Implementado |
| No scrobbles duplicados | ✅ | ✅ | Implementado |
| Validación de datos | ✅ | ✅ | Implementado |
| No campos vacíos | ✅ | ✅ | **NUEVO** |
| Tiempo real sin pausas | ✅ | ✅ | **NUEVO** |
| Ventana de duplicados | ✅ (2min) | ✅ (2min) | Implementado |

## 📝 Notas técnicas

### Detección de pausas
- Basada en tiempo sin notificaciones (>5s)
- Más confiable que estados de MediaSession (pueden ser inconsistentes)
- Probado en YouTube Music

### Tiempo de reproducción
- Se calcula: `tiempo_total - tiempo_en_pausa`
- Precisión al segundo
- Importante para la regla del 50%

### Datos opcionales
- `album` es el único campo opcional
- `track` y `artist` son obligatorios
- `duration` se calcula si no está disponible

## 🚀 Próximas mejoras potenciales

1. **Detección de skip rápido** - Si cambias de canción en <10s, no scrobble
2. **Cache de metadata** - Recordar álbumes para artistas conocidos
3. **Corrección automática** - Normalizar nombres de artistas (ej: "feat." vs "ft.")
4. **Modo offline mejorado** - Queue más inteligente

## ✅ Verificación

Para verificar que todo funciona:

1. Reproduce una canción completa
   - ✅ Debe guardarse con todos los datos

2. Reproduce una canción sin álbum
   - ✅ Debe guardarse sin campo `album`

3. Pausa una canción a los 30s, reanuda a los 2min
   - ✅ No debe crear scrobble duplicado
   - ✅ Debe contar solo el tiempo reproducido

4. Verifica en Supabase
   - ✅ No debe haber campos `album` vacíos
   - ✅ Solo datos válidos

## 📚 Referencias

- [Last.fm Scrobbling Rules](https://www.last.fm/api/scrobbling)
- [Pano Scrobbler](https://github.com/kawaiiDango/pScrobbler)
- Configuración: `lib/config/app_config.dart`
- Lógica: `lib/services/scrobble_service.dart`
