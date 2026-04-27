# Workflow — cómo trabajamos

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
