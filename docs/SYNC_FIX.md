# 🔄 Correcciones de Sincronización con Supabase

## 🔴 Problemas Identificados y Solucionados

### Problema Principal
Los scrobbles dejaban de sincronizarse en algún momento y quedaban pendientes indefinidamente.

---

## ✅ Soluciones Implementadas

### 1. **⏱️ Timeouts Implementados**

**Problema:** Las peticiones a Supabase podían quedarse colgadas indefinidamente.

**Solución:**
```dart
// Timeout global de 30 segundos para toda la sincronización
await _syncWithTimeout();

// Timeout individual de 10 segundos por cada scrobble
await _supabase.from('scrobbles').insert(data).timeout(
  const Duration(seconds: 10),
);
```

**Beneficio:** Evita que la app se quede esperando indefinidamente por una respuesta.

---

### 2. **🔒 Estado `_isSyncing` Garantizado**

**Problema:** El flag `_isSyncing` no se reseteaba en todos los escenarios de error.

**Solución:**
```dart
try {
  final result = await _syncWithTimeout();
  _isSyncing = false;  // ✅ Siempre se resetea
  return result;
} catch (e) {
  _isSyncing = false;  // ✅ Siempre se resetea
  // ...
}
```

**Beneficio:** Previene que la sincronización quede bloqueada permanentemente.

---

### 3. **✔️ Validación de Datos**

**Problema:** Se enviaban datos inválidos a Supabase, causando errores silenciosos.

**Solución:**
```dart
String? _validateScrobbleData(Map<String, dynamic> item) {
  if (track vacío) return 'Track vacío';
  if (artista vacío) return 'Artista vacío';
  if (timestamp faltante) return 'Timestamp faltante';
  if (duración inválida) return 'Duración inválida';
  return null; // ✅ Válido
}
```

**Acción:** Los scrobbles inválidos se marcan como sincronizados para no reintentarlos.

**Beneficio:** Evita reintentos infinitos de datos que nunca funcionarán.

---

### 4. **🔍 Detección Inteligente de Errores**

**Problema:** Todos los errores se trataban igual, causando reintentos innecesarios.

**Solución:**
```dart
// Errores de red → Reintentar
_isNetworkError(error) {
  return error.contains('socket') ||
         error.contains('timeout') ||
         error.contains('connection');
}

// Errores de duplicado → Marcar como sincronizado
_isDuplicateError(error) {
  return error.contains('duplicate') ||
         error.contains('unique constraint');
}

// Errores de validación → No reintentar
```

**Beneficio:** Cada tipo de error se maneja apropiadamente.

---

### 5. **📝 Logs Detallados y Estructurados**

**Antes:**
```
🔄 Iniciando sincronización...
✅ Scrobble 123 sincronizado
❌ Error sincronizando scrobble 456: [error genérico]
```

**Ahora:**
```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
🔄 INICIANDO SINCRONIZACIÓN
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
📤 Encontrados 10 scrobbles pendientes
   🎵 Sincronizando: Bohemian Rhapsody - Queen
   ✅ Scrobble 123 sincronizado
   🎵 Sincronizando: Hotel California - Eagles
   ❌ Error en scrobble 124: Sin conexión a internet
🔌 Sin conexión, deteniendo sincronización
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
📊 RESULTADO DE SINCRONIZACIÓN
   ✅ Exitosos: 1
   ❌ Errores: 1
   📈 Total procesados: 2/10
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

**Beneficio:** Fácil diagnóstico de problemas.

---

### 6. **🔁 Retry Inteligente**

**Problema:** Retry recursivo podía crear loops infinitos.

**Solución:**
```dart
// Solo reintentar errores de red
if (_shouldRetry(error)) {
  return await _retrySync();
}

// Máximo 3 reintentos con backoff exponencial
_retrySync() {
  if (_retryCount >= _maxRetries) {
    return SyncResult(success: false, message: 'Máximo alcanzado');
  }
  
  _retryCount++;
  await Future.delayed(Duration(seconds: _retryCount * 2));
  return await syncData();
}
```

**Beneficio:** Reintentos controlados solo cuando tiene sentido.

---

### 7. **🚫 Manejo de Duplicados en Servidor**

**Problema:** Si Supabase tenía un duplicado, fallaba y seguía reintentando.

**Solución:**
```dart
if (_isDuplicateError(e)) {
  print('📝 Duplicado en servidor, marcando como sincronizado');
  await _dbHelper.markAsSynced(item['id']);
  skippedCount++;
}
```

**Beneficio:** Duplicados se resuelven automáticamente.

---

## 🎯 Casos de Uso Cubiertos

### ✅ Caso 1: Sincronización Normal
```
Usuario tiene 50 scrobbles pendientes
→ Internet disponible
→ Todos se sincronizan exitosamente
Resultado: 50/50 sincronizados ✅
```

### ✅ Caso 2: Sin Internet
```
Usuario tiene 20 scrobbles pendientes
→ Sin conexión
→ Primer scrobble falla
→ Detiene y programa reintento
Resultado: 0/20 sincronizados, reintentará en 2s
```

### ✅ Caso 3: Timeout
```
Usuario tiene 10 scrobbles
→ Servidor Supabase lento
→ Timeout a los 30 segundos
→ Reintenta después
Resultado: Procesados parcialmente, reintenta lo pendiente
```

### ✅ Caso 4: Datos Inválidos
```
Usuario tiene 5 scrobbles
→ 2 tienen track vacío (datos corruptos)
→ Se marcan como sincronizados (omitidos)
→ 3 válidos se sincronizan
Resultado: 3/5 sincronizados, 2 omitidos ✅
```

### ✅ Caso 5: Duplicados
```
Usuario sincroniza 10 scrobbles
→ 3 ya existen en Supabase
→ Se detectan como duplicados
→ Se marcan como sincronizados
Resultado: 7 nuevos + 3 omitidos = 10/10 ✅
```

---

## 🔧 Configuración

Las constantes están en `app_config.dart`:

```dart
class AppConfig {
  static const int maxSyncRetries = 3;
}
```

**Timeouts hardcoded en sync_service.dart:**
- Timeout global: 30 segundos
- Timeout por scrobble: 10 segundos
- Timeout de conexión: 5 segundos

---

## 📊 Comparación: Antes vs Ahora

| Característica | Antes | Ahora |
|----------------|-------|-------|
| **Timeout** | ❌ No | ✅ 30s global, 10s individual |
| **Validación de datos** | ❌ No | ✅ Sí |
| **Reset de estado** | ⚠️ A veces | ✅ Siempre |
| **Manejo de duplicados** | ❌ Falla | ✅ Auto-resuelve |
| **Detección de errores** | ⚠️ Básica | ✅ Inteligente |
| **Logs** | ⚠️ Mínimos | ✅ Detallados |
| **Retry** | ⚠️ Puede loops | ✅ Controlado |
| **Datos inválidos** | ❌ Reintentos infinitos | ✅ Se omiten |

---

## 🐛 Debugging

### Ver logs de sincronización:

```bash
flutter logs | grep -i "sincronización\|scrobble"
```

### Logs clave a buscar:

- ✅ `INICIANDO SINCRONIZACIÓN` → Comenzó
- ✅ `RESULTADO DE SINCRONIZACIÓN` → Terminó
- ⚠️ `Sin conexión, deteniendo` → Error de red
- ⚠️ `Timeout` → Servidor lento/caído
- ⚠️ `inválido` → Datos corruptos
- ✅ `Duplicado en servidor` → Auto-resuelto

---

## 🚀 Próximos Pasos Recomendados

1. **Monitoreo**: Implementar analytics para trackear tasa de éxito
2. **Notificaciones**: Avisar al usuario si falla repetidamente
3. **Limpieza**: Limpiar scrobbles sincronizados viejos automáticamente
4. **Batch sync**: Enviar múltiples scrobbles en una sola petición

---

## 📝 Resumen

**Problema principal resuelto:**  
Los scrobbles dejaban de sincronizarse debido a:
- ❌ Timeouts indefinidos
- ❌ Estado bloqueado
- ❌ Datos inválidos
- ❌ Duplicados no manejados
- ❌ Errores mal clasificados

**Ahora:**
- ✅ Timeouts controlados
- ✅ Estado siempre se resetea
- ✅ Validación de datos
- ✅ Duplicados auto-resueltos
- ✅ Errores clasificados y manejados
- ✅ Logs detallados para debugging
- ✅ Retry inteligente

**Resultado:**  
Sincronización robusta y confiable que no se bloquea nunca. 🎉

---

**Actualizado:** 22 de enero de 2026  
**Versión:** 2.1 - Sincronización robusta
