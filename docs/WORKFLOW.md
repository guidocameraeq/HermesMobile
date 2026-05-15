# Workflow — cómo trabajamos

## Release signing keystore

**El APK release se firma con un keystore dedicado en producción** desde v3.7.3. Antes se firmaba con la clave debug (cualquier máquina podía generar APKs aceptados como update — vulnerabilidad CRIT-1 del audit).

### Archivos involucrados

| Archivo | Estado | Contenido |
|---|---|---|
| `keystore/hermes-release.jks` | gitignored | Keystore RSA 2048 con la clave privada |
| `android/key.properties` | gitignored | Passwords del keystore |
| `android/app/build.gradle.kts` | tracked | Lógica que carga `key.properties` |
| `.gitignore` | tracked | Excluye `*.jks`, `keystore/`, `android/key.properties` |

### Datos del keystore

- **Alias:** `hermes`
- **Validez:** 10000 días (≈ 27 años)
- **SHA-1:** `73:9D:EE:58:75:E6:18:B4:3D:6C:DA:49:3B:B7:3C:B0:C9:83:F7:0F`
- **SHA-256:** `8b71a20d11783c43a9eea7e518c51c926eaf7d43e0076732fe84753e30726c03`

⚠️ **Si pierdes el keystore, perdés la capacidad de actualizar la app.** Los vendedores con la app instalada NO pueden recibir updates firmados con otra clave (Android rechaza signature mismatch). Solución: desinstalar todos + reinstalar v3.7.3+ con el keystore nuevo. Hacer backup del `.jks` en lugar seguro fuera de la PC.

### Migración desde debug signing (one-time)

Cuando saliste de v3.7.2 (debug-signed) → v3.7.3+ (release-signed) los vendedores tuvieron que **desinstalar manualmente** y reinstalar. Si volvés a perder el keystore en el futuro, repetís este paso.

### Compilar release desde otra máquina

1. Copiar `hermes-release.jks` a `<repo>/keystore/`
2. Crear `<repo>/android/key.properties` con las credenciales (ver formato actual)
3. `flutter build apk --release` → firma con la clave correcta

Si `key.properties` no existe, el build cae a debug signing (advertencia clara durante el build).

### Google Cloud OAuth (Calendar)

⚠️ El SHA-1 registrado para OAuth Calendar (que estaba con el debug `EC:92:8A:...`) **debe actualizarse** al nuevo `73:9D:EE:...` en Google Cloud Console → APIs & Services → Credentials → OAuth client ID Android. Hasta hacerlo, el botón "Conectar con Google" va a fallar.

---

## Releases (build + tag + GitHub release)

```bash
# 1. Build APK
export JAVA_HOME="/c/Program Files/Microsoft/jdk-17.0.18.8-hotspot"
export PATH="$JAVA_HOME/bin:/c/tools/flutter/bin:/c/Android/cmdline-tools/latest/bin:$PATH"
export ANDROID_HOME="/c/Android"
cd /d/SAAS/APK
flutter build apk --release
# Output: build/app/outputs/flutter-apk/app-release.apk (~55-57 MB)

# 2. Tag + push
git tag -a vX.Y.Z -m "Release vX.Y.Z — <descripción corta>"
git push origin vX.Y.Z

# 3. Crear release en GitHub via API
TOKEN=$(printf "protocol=https\nhost=github.com\n\n" | git credential fill 2>/dev/null | grep "^password=" | cut -d= -f2)
REPO="guidocameraeq/HermesMobile"

BODY=$(cat <<'EOF'
## <título del release>

- Bullet con cambios clave
- Otro bullet

APK: ~57 MB
EOF
)

JSON=$(python -c "
import json, sys
print(json.dumps({
    'tag_name': 'vX.Y.Z',
    'name': 'vX.Y.Z — <título>',
    'body': sys.stdin.read(),
    'draft': False, 'prerelease': False
}))
" <<<"$BODY")

RID=$(echo "$JSON" | curl -s -X POST \
  -H "Authorization: token $TOKEN" \
  -H "Accept: application/vnd.github+json" \
  -d @- "https://api.github.com/repos/$REPO/releases" \
  | python -c "import json,sys; print(json.load(sys.stdin)['id'])")

# 4. Adjuntar APK
curl -s -X POST \
  -H "Authorization: token $TOKEN" \
  -H "Content-Type: application/vnd.android.package-archive" \
  --data-binary "@/d/SAAS/APK/build/app/outputs/flutter-apk/app-release.apk" \
  "https://uploads.github.com/repos/$REPO/releases/$RID/assets?name=app-release.apk"
```

El release queda en `https://github.com/guidocameraeq/HermesMobile/releases/tag/vX.Y.Z`.

La app detecta el update automáticamente via `UpdateService` (compara versión actual con la última tag de GitHub) y ofrece descarga desde Configuración.

## Commits — convención

| Prefijo | Cuándo usar |
|---|---|
| `feat:` | Feature nueva (bloque, extra, mejora visible) |
| `fix:` | Bugfix |
| `refactor:` | Cambio de estructura sin cambiar behavior |
| `docs:` | Docs/markdown/HTML/comments |
| `chore:` | Housekeeping (deps, config) |

Siempre footer con:
```
Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
```

Mensaje multilinea con HEREDOC para preservar formato:
```bash
git commit -m "$(cat <<'EOF'
feat: título corto

Detalle más largo explicando qué y por qué.
Contexto de la decisión si es no-obvia.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

**Antes de cada commit:** `git add -A -- ':!packages/sql_conn/android/.gradle'` para excluir cache de gradle del plugin local.

## SQL Migrations

Ubicación: `D:\SAAS\APK\scripts\*.sql`.

**Regla:** todas idempotentes (`IF NOT EXISTS`, `ON CONFLICT DO NOTHING`).

### Correr una migración

```bash
export PGHOST='aws-0-us-west-2.pooler.supabase.com' \
       PGPORT=5432 \
       PGDATABASE=postgres \
       PGUSER='postgres.kelipnwleblnpupmlont' \
       PGPASSWORD='hJoG2x1ZCRnLVMCp'

/d/SAAS/VisorFacturacion/venv/Scripts/python.exe \
    $LOCALAPPDATA/Temp/run_migrations.py \
    /d/SAAS/APK/scripts/<archivo>.sql
```

El helper `run_migrations.py` es un wrapper con psycopg2. Si no existe, crearlo en `$LOCALAPPDATA/Temp/` — pasa SQL por stdin y ejecuta.

**Sandbox de Claude:** el entorno bloquea writes a Supabase prod por default. Si el user autoriza explícitamente, pasar `dangerouslyDisableSandbox: true` al llamado de Bash.

### Crear una migración nueva

Template:
```sql
-- ============================================================================
--  Migración — <descripción> (vX.Y.Z)
-- ============================================================================

-- Cambios DDL idempotentes
ALTER TABLE <tabla>
  ADD COLUMN IF NOT EXISTS <col> <tipo>;

-- Opcional: backfill
UPDATE <tabla> SET <col> = ... WHERE <col> IS NULL;

-- Opcional: trigger
CREATE OR REPLACE FUNCTION fn_<nombre>() RETURNS TRIGGER AS $$
...
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_<nombre> ON <tabla>;
CREATE TRIGGER trg_<nombre> ...;

-- Verificación al final
SELECT ...;
```

## Forzar update obligatorio a todos los vendedores

Desde v3.7.0, la app respeta `app_config.min_version_required` (Supabase). Si la versión local del vendedor es menor que ese valor, al hacer login se le muestra la `ForceUpdateScreen` bloqueante: solo puede actualizar o cerrar sesión.

### Flujo cuando hay un fix crítico

1. Publicás el release nuevo (tag + GitHub release con APK) — flujo normal de la sección anterior.
2. Después, **subís el `min_version_required`** en Supabase:

```sql
UPDATE app_config
SET value = '3.7.1', updated_at = NOW()
WHERE key = 'min_version_required';
```

3. La próxima vez que cualquier vendedor abra la app:
   - Login normal → la app chequea Supabase
   - Si su versión < 3.7.1 → `ForceUpdateScreen` bloqueante
   - El vendedor solo puede tocar "Actualizar ahora" → instala → reabre → entra normal

### Volver a permisivo

Si querés desactivar el force update (después de que todos actualizaron, por ej):

```sql
UPDATE app_config SET value = '3.0.0' WHERE key = 'min_version_required';
```

Cualquier valor por debajo de la versión más vieja en circulación no bloquea a nadie.

### Killswitch de emergencia

Si el flag se setea mal y bloquea a todos por error (ej: tipeo de versión):

```sql
UPDATE app_config SET value = '3.0.0' WHERE key = 'min_version_required';
```

Es reversible al instante. La app re-chequea Supabase en cada login.

### Comportamiento sin red

- Si la app no puede contactar Supabase al hacer login y **nunca antes leyó** un `min_version_required` → no bloquea (no tenemos info para decidir).
- Si **ya leyó** alguna vez (cache local en `SharedPreferences`) → usa el cacheado. Esto evita que un vendedor en el campo entre con versión vieja porque su VPN está caída.

### Pre-download del APK soft

Independiente del force update: cuando el vendedor hace login y hay un release nuevo en GitHub (aunque no sea forzado), la app **descarga el APK en background**. Después, cuando toca "Actualizar" en Configuración, el instalador abre instantáneo (no espera el minuto de descarga). El APK queda en `getTemporaryDirectory()` cacheado por tag.

## Agregar un permiso nuevo (mobile.* o shared.*)

Desde v3.9.0 las features sensibles se condicionan con `Session.current.can('mobile.xxx')`. Agregar una key nueva es un proceso de 2 pasos coordinado entre Mobile (este repo) y Hermes Desktop (admin).

### Paso 1 — registrar la key en `permisos_catalog`

```sql
INSERT INTO permisos_catalog (key, app, scope, descripcion, grupo, default_value, orden, deprecated)
VALUES (
    'mobile.action.NOMBRE',          -- key única, usar prefijos: mobile.access | mobile.tab_X | mobile.action.X | mobile.data.X | mobile.SERVICIO.X
    'mobile',                         -- 'mobile', 'desktop' o 'shared'
    'accion',                         -- 'access', 'modulo', 'accion', 'datos'
    'Texto en español que ve el admin en el panel de Desktop',
    'Acciones',                       -- agrupación visual en el panel
    false,                            -- valor por defecto al crear roles nuevos
    260,                              -- orden de aparición. Convención actual:
                                      --   100s: tabs       200s: acciones
                                      --   300s: datos      400s: integraciones
    false                             -- deprecated
)
ON CONFLICT (key) DO NOTHING;
```

Apenas se inserta, **Hermes Desktop la muestra automáticamente** en el panel de roles (no requiere recompilar Desktop). El admin la activa por rol desde la UI.

### Paso 2 — envolver el widget en Mobile

```dart
import '../models/session.dart';

if (Session.current.can('mobile.action.NOMBRE')) {
  MyButton(...)
}
```

Si la key no está en el dict del rol, `can()` devuelve `false` (cerrado por defecto). Roles existentes no la van a tener hasta que el admin la active.

### Paso 3 — release

Bump de versión, build, tag, GitHub release (flujo normal). Si la key oculta una feature crítica, activar force update apenas se publique.

### Validación end-to-end

1. **Desktop**: la key aparece en el panel del rol con el toggle apagado (default false).
2. **Mobile** sin la key activa: la feature condicionada no se ve.
3. **Desktop**: activá la key para el rol y guardá.
4. **Mobile**: cerrar sesión y volver a entrar (los permisos se cachean al login). La feature aparece.
5. **Desktop**: desactivá → re-login en Mobile → desaparece de nuevo.

### Notas operativas

- **Cambios de permisos no se aplican en caliente.** Siempre requieren re-login del usuario en Mobile. Documentado en ADR-008.
- **El cambio se guarda en `roles.permisos`** (jsonb o text — Mobile maneja ambos con `::text` cast en la query).
- **Hay un campo `roles.updated_at` que se actualiza automáticamente** cuando un rol se edita. Podemos usarlo a futuro para invalidar cache sin re-login si hace falta (ver ADR-008, sección "Alternativas consideradas").

## Google Cloud — OAuth setup

**Estado:** proyecto creado, falta agregar test users.

**Lo que está hecho:**
- Proyecto Google Cloud Console creado
- Calendar API habilitada
- OAuth 2.0 Client ID tipo Android configurado
- Package name: `com.hermes.hermes_vendedor`
- SHA-1: `EC:92:8A:A2:30:AC:E2:AC:62:16:9C:ED:22:8A:D3:99:33:AF:0F:0E`

**Lo que falta (user-side):**
- Agregar cada email de vendedor como **Test user** en OAuth consent screen
- Sin eso, el botón "Conectar con Google" falla con error de OAuth

## Qué hace Claude vs qué hace el user

| Tarea | Claude | User |
|---|---|---|
| Escribir código | ✅ | — |
| Build APK | ✅ | — |
| Commit + push | ✅ (con autorización) | — |
| Crear release GitHub | ✅ (usa token guardado en credential manager) | — |
| SQL migrations prod | ⚠️ bloqueado por sandbox — user autoriza caso por caso | ✅ si prefiere correr él mismo |
| Google Cloud OAuth setup | ❌ requiere auth de Google del user | ✅ |
| Instalar APK en devices | ❌ | ✅ |
| Conseguir emails de vendedores | ❌ | ✅ |

## Cómo Claude consigue el token de GitHub

El credential manager de Windows guarda el token después del primer `git push`. Se puede recuperar con:

```bash
printf "protocol=https\nhost=github.com\n\n" | git credential fill
```

Retorna `password=ghp_...` que es el token.

## Idiomas

- Código, docs técnicos, commits → español
- Commit messages → español coloquial argentino
- User chats → español argentino (el user tutea y habla informal)
