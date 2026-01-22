# 🎵 Mejoras en la Lógica de Scrobbling

## 📊 Implementación Profesional - Estándares de Last.fm y Pano Scrobbler

### 🎯 Cambios Implementados

#### 1. **Regla del 50% o 4 Minutos** (Estándar de Last.fm)

La nueva lógica sigue el estándar de la industria:

- ✅ **50% de la canción**: Para canciones cortas/medianas
- ✅ **4 minutos máximo**: Para canciones muy largas
- ✅ **30 segundos mínimo**: Requisito absoluto

**Ejemplo:**
```dart
// Canción de 3 minutos → scrobble a los 90 segundos (50%)
// Canción de 10 minutos → scrobble a los 4 minutos (máximo)
// Canción de 1 minuto → scrobble a los 30 segundos (mínimo)
```

#### 2. **Prevención Inteligente de Duplicados**

**Antes:**
- Solo verificaba constraint UNIQUE en base de datos
- Podía guardar la misma canción múltiples veces si cambiaba el timestamp

**Ahora:**
- ✅ **Ventana de tiempo**: No permite duplicados dentro de 2 minutos
- ✅ **Validación en memoria**: Evita procesamiento innecesario
- ✅ **Doble verificación**: En servicio y en base de datos
- ✅ **Permite repeticiones válidas**: Fuera de la ventana de tiempo

```dart
// Mismo track + artista en < 2 minutos = IGNORADO
// Mismo track + artista en > 2 minutos = PERMITIDO (replay válido)
```

#### 3. **Validación de Duración Mínima**

**Requisitos implementados:**

- ⏱️ **Canción mínima**: 30 segundos de duración total
- ⏱️ **Reproducción mínima**: 30 segundos efectivos reproducidos
- 🎵 **Canciones cortas**: Automáticamente rechazadas

**Casos de uso:**
```dart
❌ Anuncios de 15 segundos → No se guardan
❌ Intros/outros cortos → No se guardan  
✅ Canciones normales → Se guardan correctamente
✅ Canciones largas (>8min) → Scrobble a los 4 minutos
```

#### 4. **Manejo de Skips y Cambios Rápidos**

**Mejoras:**

- 🎯 **Detección de skip**: Si cambias antes del mínimo, no guarda
- 📊 **Duración real**: Registra cuánto realmente escuchaste
- 🔄 **Finalización inteligente**: Guarda la canción anterior si cumple requisitos

**Flujo:**
```
Usuario reproduce canción A (3 min)
→ 20 segundos después cambia a canción B
→ Canción A NO se guarda (< 30s)

Usuario reproduce canción C (4 min)
→ 2 minutos después cambia a canción D  
→ Canción C SÍ se guarda (> 50% alcanzado)
```

#### 5. **Logs Informativos Mejorados**

**Antes:**
```
⏱️ 30s alcanzados. Guardando en BD...
✅ Scrobble guardado correctamente (ID: 123)
```

**Ahora:**
```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
💾 GUARDANDO SCROBBLE
   🎵 Track: Bohemian Rhapsody
   👤 Artista: Queen
   💿 Álbum: A Night at the Opera
   ⏱️ Duración total: 354s
   ▶️ Reproducido: 180s
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
✅ Scrobble guardado (ID: 123)
```

### 🏗️ Arquitectura Mejorada

#### Estado de Reproducción Extendido

```dart
class ScrobbleService {
  // Estado básico
  String? _lastTrack;
  String? _lastArtist;
  String? _lastAlbum;
  DateTime? _trackStartTime;
  int? _totalDuration;
  
  // Nuevos campos profesionales
  bool _hasBeenScrobbled;          // Evita duplicados en misma sesión
  DateTime? _lastScrobbleTimestamp; // Tracking de tiempo
  Timer? _scrobbleTimer;            // Control preciso
}
```

#### Métodos Nuevos

1. **`_calculateScrobbleDelay()`** - Calcula cuándo hacer scrobble
2. **`_isNewTrack()`** - Detección inteligente de nueva canción
3. **`_isValidForScrobble()`** - Validaciones profesionales
4. **`_saveScrobble()`** - Guardado con validaciones completas
5. **`_finalizePreviousScrobble()`** - Manejo de cambios de canción

#### Base de Datos Mejorada

```dart
// Nuevo método en DBHelper
Future<int> insertScrobble(Scrobble scrobble) async {
  // 1. Verificar duplicados recientes (2 min)
  // 2. Ignorar si existe duplicado
  // 3. Insertar con conflictAlgorithm.ignore
  // 4. Retornar 0 si fue ignorado, ID si fue guardado
}

// Nuevo método de validación
Future<bool> isDuplicate(track, artist, timestamp) async {
  // Busca en ventana de ±2 minutos
}
```

### 📈 Comparación: Antes vs Ahora

| Característica | Antes | Ahora |
|----------------|-------|-------|
| **Umbral de scrobble** | Fijo: 30s | Dinámico: 50% o 4min |
| **Duración mínima** | No validaba | 30s requeridos |
| **Duplicados** | Solo constraint DB | Ventana de 2min + validación |
| **Skips** | Guardaba parciales | Descarta si < mínimo |
| **Canciones largas** | Esperaba mucho | Máximo 4 minutos |
| **Logs** | Básicos | Detallados y estructurados |
| **Validaciones** | Mínimas | Profesionales completas |

### 🎨 Configuración

Todas las constantes están en `lib/config/app_config.dart`:

```dart
class AppConfig {
  // Duración mínima de una canción válida
  static const int minTrackDurationSeconds = 30;
  
  // Umbrales de scrobbling
  static const int scrobbleThresholdSeconds = 30;      // Mínimo
  static const int scrobbleMaxThresholdSeconds = 240;  // 4 minutos
  static const double scrobblePercentageThreshold = 0.5; // 50%
  
  // Ventana anti-duplicados
  static const int duplicateWindowMinutes = 2;
  
  // Mínimo de reproducción efectiva
  static const int minPlayedDurationSeconds = 30;
}
```

### 🔍 Casos de Prueba

#### ✅ Caso 1: Canción Normal
```
Duración: 3:30 (210s)
Umbral: 105s (50%)
Usuario escucha: 2:00 (120s) ✅
Resultado: SCROBBLE GUARDADO
```

#### ✅ Caso 2: Canción Larga
```
Duración: 10:00 (600s)
Umbral: 240s (4min máximo)
Usuario escucha: 5:00 (300s) ✅
Resultado: SCROBBLE GUARDADO (a los 4min)
```

#### ❌ Caso 3: Skip Rápido
```
Duración: 4:00 (240s)
Umbral: 120s (50%)
Usuario escucha: 0:15 (15s) ❌
Resultado: NO GUARDADO (< 30s mínimo)
```

#### ❌ Caso 4: Duplicado
```
Canción: "Bohemian Rhapsody"
Último scrobble: Hace 1 minuto
Nueva reproducción: Ahora ❌
Resultado: IGNORADO (ventana 2min)
```

#### ✅ Caso 5: Repetición Válida
```
Canción: "Bohemian Rhapsody"
Último scrobble: Hace 5 minutos
Nueva reproducción: Ahora ✅
Resultado: SCROBBLE GUARDADO (fuera ventana)
```

### 🐛 Manejo de Errores

**Escenarios cubiertos:**

1. ✅ Track vacío → Rechazado
2. ✅ Artista desconocido → Advertencia pero permite
3. ✅ Sin duración → Usa mínimo de 30s
4. ✅ Canción muy corta → Rechazada
5. ✅ Reproducción muy corta → Rechazada
6. ✅ Error en DB → Catch y log
7. ✅ Duplicados → Ignorados silenciosamente

### 📝 Logs de Ejemplo

**Scrobble exitoso:**
```
🎶 NUEVA CANCIÓN DETECTADA (Background)
   🎵 Track: Stairway to Heaven
   👤 Artista: Led Zeppelin
   💿 Álbum: Led Zeppelin IV
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
⏰ Scrobble programado en 240s
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
💾 GUARDANDO SCROBBLE
   🎵 Track: Stairway to Heaven
   👤 Artista: Led Zeppelin
   💿 Álbum: Led Zeppelin IV
   ⏱️ Duración total: 482s
   ▶️ Reproducido: 240s
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
✅ Scrobble guardado (ID: 456)
```

**Scrobble rechazado:**
```
⏩ Canción muy corta (15s < 30s), ignorada
```

```
🚫 Scrobble duplicado detectado, ignorando
```

```
⏭️ No alcanzó el mínimo de reproducción (20s < 30s)
```

### 🚀 Beneficios

1. **Precisión**: Solo guarda scrobbles válidos y significativos
2. **Eficiencia**: Evita duplicados y escrituras innecesarias
3. **Estándares**: Compatible con Last.fm y otros servicios
4. **Flexibilidad**: Configuración centralizada y fácil de ajustar
5. **Debugging**: Logs detallados para diagnóstico
6. **Profesionalismo**: Comportamiento predecible y documentado

### 📚 Referencias

- [Last.fm Scrobbling Guide](https://www.last.fm/api/scrobbling)
- Pano Scrobbler behavior
- Scroball implementation
- Simple Scrobbler logic

---

**Implementado por:** Sistema de mejoras automáticas  
**Fecha:** 22 de enero de 2026  
**Versión:** 2.0 - Lógica profesional de scrobbling
