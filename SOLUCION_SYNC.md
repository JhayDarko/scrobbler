# 🚀 Corrección del problema de sincronización con Supabase

## 📋 Resumen del problema

Los scrobbles se guardaban **correctamente en SQLite local** pero **NO aparecían en Supabase**. Los logs mostraban "✅ Scrobble sincronizado" sin errores, pero los datos no estaban en la nube.

### Causa raíz identificada
**Row Level Security (RLS)** de Supabase estaba rechazando silenciosamente las inserciones porque no había políticas configuradas para el rol `anon`.

## ✅ Soluciones implementadas

### 1. Mejora en captura de respuestas
```dart
// ANTES: Insert silencioso (no detectaba errores de RLS)
await _supabase.from('scrobbles').insert(scrobbleData);

// AHORA: Forzamos respuesta con .select() para detectar errores
final response = await _supabase
    .from('scrobbles')
    .insert(scrobbleData)
    .select() // ← Esto fuerza a Supabase a retornar respuesta
    .timeout(const Duration(seconds: 10));

print('📨 Respuesta de Supabase: $response');
```

### 2. Función de diagnóstico automático
Se agregó `diagnosticSupabase()` en `SyncService` que verifica:
- ✅ Conexión a Supabase
- ✅ Existencia de la tabla
- ✅ Permisos de lectura (SELECT)
- ✅ Permisos de escritura (INSERT) ← El problema estaba aquí
- ✅ Detecta automáticamente si RLS está bloqueando

### 3. Página de diagnóstico en la UI
Nueva página accesible desde **Configuración → Diagnóstico de Supabase**:
- Muestra estadísticas locales (total de scrobbles, sin sincronizar)
- Ejecuta test completo de Supabase
- Muestra resultados con íconos visuales ✅/❌
- **Proporciona soluciones automáticas** si detecta problemas de RLS

### 4. Logging mejorado
```dart
print('   📦 Datos a enviar: $scrobbleData');
print('   📨 Respuesta de Supabase: $response');
```

## 🛠️ Cómo usar el diagnóstico

1. **Abre la app**
2. **Ve a Configuración** (icono de tuerca)
3. **Click en "Diagnóstico de Supabase"**
4. **Presiona "Ejecutar diagnóstico"**
5. **Revisa los resultados**:
   - Si "Puede insertar" está en ❌ rojo → Sigue las instrucciones en pantalla
   - Si todo está en ✅ verde → La sincronización debería funcionar

## 🔧 Solución al problema de RLS

### Opción 1: Desactivar RLS (rápido, solo para desarrollo)
1. Ve a [Supabase Dashboard](https://supabase.com/dashboard)
2. Authentication → Policies
3. Tabla `scrobbles`
4. Click en **Disable RLS**

⚠️ **Advertencia**: Esto deja la tabla completamente abierta.

### Opción 2: Crear política de INSERT (recomendado)
Ejecuta este SQL en el **SQL Editor** de Supabase:

```sql
-- Permitir inserts desde la app (rol anon)
CREATE POLICY "Allow anon insert"
ON scrobbles
FOR INSERT
TO anon
WITH CHECK (true);

-- (Opcional) Permitir lecturas
CREATE POLICY "Allow anon select"
ON scrobbles
FOR SELECT
TO anon
USING (true);
```

## ✅ Verificación de la solución

### Paso 1: Ejecutar diagnóstico
```
Configuración → Diagnóstico de Supabase → Ejecutar diagnóstico
```

Deberías ver:
- ✅ Conexión a Supabase
- ✅ Tabla existe
- ✅ Puede leer
- ✅ Puede insertar ← **Este debe estar en verde**

### Paso 2: Probar con música real
1. Reproduce una canción en YouTube Music
2. Espera el tiempo de scrobble (50% o 4 minutos)
3. Verifica en los logs: `📨 Respuesta de Supabase: ...`
4. Ve a Supabase Dashboard → Table Editor → scrobbles
5. Deberías ver el nuevo scrobble

### Paso 3: Verificar scrobbles pendientes
En la página de diagnóstico, verifica:
- **Sin sincronizar**: Debería ser 0 (o disminuir después de sincronizar)

## 📊 Archivos modificados

1. **`lib/services/sync_service.dart`**
   - Agregado `.select()` al insert para forzar respuesta
   - Agregado logging de datos enviados y respuesta recibida
   - Nueva función `diagnosticSupabase()`

2. **`lib/pages/diagnostic_page.dart`** ← NUEVO
   - UI completa para diagnóstico
   - Muestra estadísticas locales
   - Ejecuta tests automáticos
   - Proporciona soluciones

3. **`lib/pages/settings_page.dart`**
   - Agregado botón "Diagnóstico de Supabase"

4. **`docs/SUPABASE_RLS_FIX.md`** ← NUEVO
   - Documentación técnica completa
   - Explicación del problema RLS
   - Múltiples opciones de solución
   - Ejemplos de SQL

## 🎯 Próximos pasos

1. ✅ **Aplicar la solución de RLS** (Opción 1 o 2 arriba)
2. ✅ **Ejecutar el diagnóstico** desde la app
3. ✅ **Reproducir música** y verificar sincronización
4. ✅ **Verificar en Supabase** que aparecen los datos

## 📝 Notas importantes

- El código de la app estaba **correcto**
- La configuración de Supabase URL/keys estaba **correcta**
- El problema era **configuración de seguridad de Supabase** (RLS)
- Ahora la app **detecta automáticamente** este tipo de problemas
- El diagnóstico es **reutilizable** para futuros problemas

## 🔗 Referencias

- Documentación completa: `docs/SUPABASE_RLS_FIX.md`
- Código de diagnóstico: `lib/services/sync_service.dart` → `diagnosticSupabase()`
- UI de diagnóstico: `lib/pages/diagnostic_page.dart`

---

**¿Dudas?** Ejecuta el diagnóstico y sigue las instrucciones en pantalla. Si el problema persiste, revisa `docs/SUPABASE_RLS_FIX.md` para detalles técnicos.
