# 🚀 Servicio Foreground Persistente

## 📋 Resumen de mejoras

Se ha convertido el servicio de scrobbling en un **servicio foreground persistente** que sobrevive a:
- ✅ Cierre de la app
- ✅ "Clear All" en recientes
- ✅ Reinicio del dispositivo
- ✅ Modos de ahorro de batería

## 🎯 1. Servicio Foreground

### ¿Qué es un servicio foreground?

Un **foreground service** en Android es un servicio que:
- Muestra una notificación persistente
- Tiene **prioridad alta** - el sistema NO lo mata fácilmente
- Funciona incluso cuando la app está cerrada
- Sobrevive a "Clear All" en recientes

### Cambios implementados

#### Notificación persistente mejorada
```dart
const AndroidNotificationChannel channel = AndroidNotificationChannel(
  'scrobbler_service',
  'Scrobbler Service',
  description: 'Monitorizando música en segundo plano',
  importance: Importance.high, // ✅ Alta prioridad
  showBadge: true,
  playSound: false,
  enableVibration: false,
);
```

#### Configuración del servicio
```dart
await service.configure(
  androidConfiguration: AndroidConfiguration(
    onStart: onStartCallback,
    isForegroundMode: true, // ✅ CRÍTICO: Modo foreground
    autoStart: true,
    autoStartOnBoot: true,
    initialNotificationTitle: '🎵 Scrobbler Activo',
    initialNotificationContent: 'Monitoreando tu música en segundo plano',
  ),
);
```

#### Notificación dinámica con estadísticas
```dart
// Actualiza la notificación cada 30 segundos con información útil
final content = _scrobblesProcessed > 0
    ? "✅ $_scrobblesProcessed scrobbles • Último hace ${elapsed}min"
    : "🎧 Esperando música...";

service.setForegroundNotificationInfo(
  title: "🎵 Scrobbler Activo",
  content: content,
);
```

**Ejemplo de notificación:**
```
🎵 Scrobbler Activo
✅ 15 scrobbles • Último hace 2min
```

## 🐕 2. Watchdog mejorado

### Sistema de vigilancia de doble capa

#### Capa 1: Watchdog nativo (AlarmManager)
- Verifica cada **5 minutos** (antes 15 min)
- Usa AlarmManager del sistema (no se puede matar)
- Reinicia el servicio si está detenido
- Sobrevive a "Clear All"

```kotlin
private const val CHECK_INTERVAL_MS = 5 * 60 * 1000L // 5 minutos

alarmManager.setExactAndAllowWhileIdle(
    AlarmManager.ELAPSED_REALTIME_WAKEUP,
    triggerTime,
    pendingIntent
)
```

#### Capa 2: RestartService
- Servicio nativo dedicado a reiniciar
- Se ejecuta en proceso separado
- Activado automáticamente al inicio

### Beneficios del watchdog
- ✅ Detecta si el servicio se detuvo
- ✅ Reinicia automáticamente
- ✅ Funciona incluso en Doze mode
- ✅ Múltiples capas de protección

## 📱 3. Configuración AndroidManifest

### Permisos agregados
```xml
<!-- Servicio persistente -->
<uses-permission android:name="android.permission.FOREGROUND_SERVICE"/>
<uses-permission android:name="android.permission.FOREGROUND_SERVICE_DATA_SYNC"/>

<!-- Watchdog -->
<uses-permission android:name="android.permission.SCHEDULE_EXACT_ALARM"/>
<uses-permission android:name="android.permission.USE_EXACT_ALARM"/>

<!-- Inicio automático -->
<uses-permission android:name="android.permission.RECEIVE_BOOT_COMPLETED"/>
<uses-permission android:name="android.permission.WAKE_LOCK"/>
```

### Configuración del servicio
```xml
<service
    android:name="id.flutter.flutter_background_service.BackgroundService"
    android:permission="android.permission.FOREGROUND_SERVICE"
    android:foregroundServiceType="dataSync"
    android:exported="true"
    android:stopWithTask="false"         <!-- No se detiene al cerrar app -->
    android:enabled="true"
    android:directBootAware="true"       <!-- Funciona antes de desbloquear -->
/>
```

## 🔄 4. Flujo de funcionamiento

### Al iniciar la app
```
1. App inicia
2. initializeService() se ejecuta
3. Se crea canal de notificación de alta prioridad
4. Se configura BackgroundService en modo foreground
5. Se inicia RestartService (capa de seguridad)
6. Se programa Watchdog cada 5 minutos
7. ✅ Notificación persistente aparece en el panel
```

### Durante ejecución normal
```
1. BackgroundService corre en foreground
2. Notificación siempre visible: "🎵 Scrobbler Activo"
3. Cada 2s: Verifica cola de eventos
4. Cada 30s: Actualiza estadísticas en notificación
5. Cada 5min: Watchdog verifica que esté corriendo
```

### Al cerrar la app (botón atrás)
```
1. UI de Flutter se cierra
2. BackgroundService SIGUE corriendo (stopWithTask=false)
3. Notificación persistente SIGUE visible
4. ✅ Música continúa siendo monitoreada
```

### Al hacer "Clear All"
```
1. Android intenta matar el proceso
2. BackgroundService sobrevive (foreground service)
3. Si se mata, RestartService lo reinicia
4. Watchdog verifica en 5min y reinicia si es necesario
5. ✅ Servicio vuelve a estar activo
```

### Al reiniciar el dispositivo
```
1. Android inicia
2. BootReceiver detecta BOOT_COMPLETED
3. autoStartOnBoot activa el servicio
4. Watchdog se programa automáticamente
5. ✅ Todo vuelve a funcionar sin intervención
```

## 📊 Comparación antes/después

| Escenario | Antes | Ahora |
|-----------|-------|-------|
| Cerrar app | ❌ Se detiene | ✅ Continúa |
| Clear All | ❌ Se detiene | ✅ Continúa |
| Reiniciar | ❌ Manual | ✅ Automático |
| Ahorro batería | ❌ Se detiene | ✅ Continúa |
| Notificación | ⚠️ A veces | ✅ Siempre |
| Watchdog | 15min | 5min |

## 🎮 Pruebas para verificar

### Prueba 1: Cerrar la app
```
1. Abre la app
2. Verifica que la notificación "🎵 Scrobbler Activo" esté visible
3. Presiona el botón atrás para cerrar
4. ✅ La notificación DEBE seguir visible
5. Reproduce música en YouTube Music
6. ✅ Los scrobbles DEBEN guardarse
```

### Prueba 2: Clear All
```
1. Abre la app
2. Presiona el botón de recientes
3. Presiona "Clear All" o desliza la app para cerrarla
4. ✅ La notificación DEBE seguir visible
5. Reproduce música
6. ✅ Los scrobbles DEBEN guardarse
```

### Prueba 3: Reinicio del dispositivo
```
1. Verifica que la app esté configurada
2. Reinicia el teléfono
3. Espera a que inicie
4. ✅ La notificación DEBE aparecer automáticamente
5. No abras la app manualmente
6. Reproduce música
7. ✅ Los scrobbles DEBEN guardarse
```

### Prueba 4: Watchdog
```
1. Fuerza detener el servicio desde Configuración del sistema
   (Settings → Apps → Scrobbler → Force Stop)
2. Espera 5 minutos
3. ✅ El servicio DEBE reiniciarse automáticamente
4. ✅ La notificación DEBE volver a aparecer
```

## 🔧 Configuración personalizada

### Cambiar intervalo del watchdog

En `WatchdogReceiver.kt`:
```kotlin
// Cambiar de 5 a 3 minutos (más agresivo)
private const val CHECK_INTERVAL_MS = 3 * 60 * 1000L
```

### Cambiar frecuencia de actualización de notificación

En `background_service_entry.dart`:
```dart
// Cambiar de 30s a 10s (actualización más frecuente)
Timer.periodic(const Duration(seconds: 10), (timer) async {
  await scrobbleLogic.updateNotification();
});
```

### Personalizar notificación

En `service_initializer.dart`:
```dart
initialNotificationTitle: 'Tu título personalizado',
initialNotificationContent: 'Tu mensaje personalizado',
```

## ⚙️ Cómo funciona técnicamente

### Foreground Service
Android considera **crítico** un servicio foreground porque:
1. Muestra notificación visible al usuario
2. Usuario está "consciente" de que algo está corriendo
3. Sistema le da **prioridad alta** para no matarlo
4. Usa memoria de forma "legítima"

### AlarmManager
- Parte del sistema operativo Android
- Programa alarmas exactas independientes de la app
- Sobrevive a:
  - Clear All
  - Force Stop (se reprograma al reiniciar)
  - Doze mode (setExactAndAllowWhileIdle)
  - App Standby

### stopWithTask=false
- Normalmente, un servicio se detiene cuando la tarea (app) termina
- Con `stopWithTask=false`, el servicio IGNORA el ciclo de vida de la app
- Continúa ejecutándose incluso si la app está completamente cerrada

### directBootAware=true
- Permite que el servicio inicie **antes** de que el usuario desbloquee el teléfono
- Útil después de reiniciar el dispositivo

## 🎯 Beneficios

### Para el usuario
- ✅ No necesita mantener la app abierta
- ✅ No se pierde música si cierra la app
- ✅ Funciona "set and forget"
- ✅ Notificación informa el estado

### Para el desarrollador
- ✅ Servicio confiable
- ✅ Múltiples capas de protección
- ✅ Logs claros para debugging
- ✅ Estadísticas en tiempo real

## 📝 Notas importantes

### Consumo de batería
- El servicio foreground **usa batería**
- Pero es minimal: solo verifica cola cada 2s
- La notificación lo hace "transparente" al usuario
- El usuario puede desinstalarlo si no le gusta

### Notificación persistente
- **NO se puede ocultar** (requisito de Android)
- Esto es **intencional** y **bueno**:
  - Usuario sabe que algo está corriendo
  - Transparencia con el usuario
  - Android considera esto "responsable"

### Clear All vs Force Stop
- **Clear All**: El servicio sobrevive ✅
- **Force Stop**: Android mata TODO, pero watchdog reinicia en 5min ✅

### Xiaomi/MIUI
En dispositivos Xiaomi puede ser necesario:
1. Settings → Battery & Performance
2. Battery Saver → App Battery Saver
3. Buscar "Scrobbler"
4. Seleccionar "No restrictions"

## 🚀 Archivos modificados

1. **`lib/services/service_initializer.dart`**
   - Canal de notificación: `Importance.high`
   - Watchdog mejorado (5min)
   - Mejor logging

2. **`lib/services/background_service_entry.dart`**
   - Notificación dinámica con estadísticas
   - Actualización cada 30s
   - Contador de scrobbles

3. **`android/app/src/main/kotlin/.../WatchdogReceiver.kt`**
   - Intervalo: 15min → 5min
   - Más agresivo

4. **`android/app/src/main/AndroidManifest.xml`**
   - `stopWithTask="false"`
   - `enabled="true"`
   - `directBootAware="true"`

## ✅ Resumen

El servicio ahora es **prácticamente imposible de matar**:
- ✅ Foreground service con notificación persistente
- ✅ Watchdog cada 5 minutos
- ✅ RestartService de respaldo
- ✅ Auto-inicio en boot
- ✅ Sobrevive a Clear All
- ✅ Funciona en Doze mode
- ✅ Información en tiempo real

**El scrobbler está SIEMPRE activo** 🎵
