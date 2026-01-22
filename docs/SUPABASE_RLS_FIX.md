# Solución al problema de sincronización con Supabase

## 🔍 Diagnóstico

El problema de sincronización donde los scrobbles se guardan localmente pero NO aparecen en Supabase se debe a **Row Level Security (RLS)**.

### Síntomas
- ✅ Los scrobbles se guardan en SQLite local
- ✅ Los logs muestran "Scrobble sincronizado"
- ❌ NO hay errores en los logs
- ❌ Los datos NO aparecen en la tabla de Supabase

### Causa raíz
Supabase tiene Row Level Security (RLS) activado por defecto en todas las tablas. Esto significa que aunque el `anon` key sea válido, las inserciones se **rechazan silenciosamente** si no hay una política que las permita.

## 🛠️ Solución

### Opción 1: Desactivar RLS (desarrollo/testing)

1. Ve a tu proyecto en [Supabase Dashboard](https://supabase.com/dashboard)
2. Abre **Authentication → Policies**
3. Selecciona la tabla `scrobbles`
4. Click en **Disable RLS** (esquina superior derecha)

⚠️ **ADVERTENCIA**: Esto deja la tabla completamente abierta. Solo para desarrollo/testing.

### Opción 2: Crear política de INSERT (recomendado)

1. Ve a **Authentication → Policies**
2. Selecciona la tabla `scrobbles`
3. Click en **New Policy**
4. Selecciona **For full customization**
5. Configura:
   - **Policy name**: `Allow anon insert`
   - **Allowed operation**: `INSERT`
   - **Target roles**: `anon`
   - **USING expression**: `true`
   - **WITH CHECK expression**: `true`

O ejecuta este SQL directamente en el **SQL Editor**:

```sql
-- Crear política para permitir inserts desde la app
CREATE POLICY "Allow anon insert"
ON scrobbles
FOR INSERT
TO anon
WITH CHECK (true);

-- (Opcional) Crear política para permitir lecturas
CREATE POLICY "Allow anon select"
ON scrobbles
FOR SELECT
TO anon
USING (true);

-- (Opcional) Crear política para permitir updates
CREATE POLICY "Allow anon update"
ON scrobbles
FOR UPDATE
TO anon
USING (true)
WITH CHECK (true);

-- (Opcional) Crear política para permitir deletes
CREATE POLICY "Allow anon delete"
ON scrobbles
FOR DELETE
TO anon
USING (true);
```

### Opción 3: Políticas con autenticación de usuario (producción)

Si planeas agregar autenticación con `auth.users()`:

```sql
-- Política para que los usuarios solo vean sus propios scrobbles
CREATE POLICY "Users can view own scrobbles"
ON scrobbles
FOR SELECT
TO authenticated
USING (auth.uid() = user_id);

-- Política para que los usuarios solo inserten con su propio ID
CREATE POLICY "Users can insert own scrobbles"
ON scrobbles
FOR INSERT
TO authenticated
WITH CHECK (auth.uid() = user_id);
```

**Nota**: Esto requiere agregar una columna `user_id UUID REFERENCES auth.users(id)` a la tabla.

## ✅ Verificación

### Método 1: Usar la app

1. Abre la app
2. Ve a **Configuración**
3. Click en **Diagnóstico de Supabase**
4. Verifica que todos los checks estén en ✅ verde:
   - Conexión a Supabase
   - Tabla existe
   - Puede leer
   - **Puede insertar** ← Este debe estar en ✅

### Método 2: Verificar manualmente en Supabase

1. Ve a **Table Editor**
2. Selecciona la tabla `scrobbles`
3. Verifica que aparezcan los nuevos registros

### Método 3: SQL Query

Ejecuta en el SQL Editor:

```sql
-- Ver todos los scrobbles
SELECT * FROM scrobbles ORDER BY timestamp DESC LIMIT 10;

-- Ver políticas activas
SELECT * FROM pg_policies WHERE tablename = 'scrobbles';

-- Ver estado de RLS
SELECT tablename, rowsecurity 
FROM pg_tables 
WHERE tablename = 'scrobbles';
```

## 🧪 Mejoras implementadas en el código

### 1. Captura de respuesta en insert
```dart
final response = await _supabase
    .from('scrobbles')
    .insert(scrobbleData)
    .select() // Forzar respuesta para detectar errores de RLS
    .timeout(const Duration(seconds: 10));
```

### 2. Función de diagnóstico
```dart
await SyncService().diagnosticSupabase();
```

### 3. Página de diagnóstico en la UI
- Accesible desde Configuración → Diagnóstico de Supabase
- Muestra estado de conexión, lectura, escritura
- Sugerencias automáticas si detecta problemas de RLS

## 📊 Datos de ejemplo

Si quieres verificar que RLS funciona correctamente, intenta insertar manualmente:

```sql
-- Insertar scrobble de prueba (debe funcionar después de la política)
INSERT INTO scrobbles (track, artist, album, duration, timestamp)
VALUES ('TEST', 'TEST ARTIST', 'TEST ALBUM', 180, NOW());

-- Verificar que se insertó
SELECT * FROM scrobbles WHERE track = 'TEST';

-- Limpiar
DELETE FROM scrobbles WHERE track = 'TEST';
```

## 🎯 Próximos pasos recomendados

1. ✅ Aplicar una de las soluciones RLS arriba
2. ✅ Ejecutar el diagnóstico desde la app
3. ✅ Reproducir música y verificar que se sincronice
4. ✅ Verificar en Supabase Dashboard que aparecen los datos

## 📝 Notas técnicas

- El problema NO estaba en el código de Flutter/Dart
- El problema NO estaba en la configuración de Supabase URL/keys
- El problema ERA que RLS rechaza silenciosamente sin lanzar excepciones cuando usas `.insert()` sin `.select()`
- Ahora con `.select()` forzamos una respuesta que revela errores de RLS

## 🔗 Referencias

- [Supabase Row Level Security](https://supabase.com/docs/guides/auth/row-level-security)
- [Supabase Policies](https://supabase.com/docs/guides/auth/row-level-security#policies)
- [PostgreSQL Policies](https://www.postgresql.org/docs/current/sql-createpolicy.html)
