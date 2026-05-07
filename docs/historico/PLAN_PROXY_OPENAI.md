# Plan de acción — Proxy OpenAI vía Supabase Edge Functions

**Estado:** propuesto, sin ejecutar.
**Versión target:** v3.8.0
**Esfuerzo estimado:** 1 día completo (~6-8 horas)
**Prioridad:** alta — la OpenAI key está embebida en el APK y aunque hay cap mensual, un APK filtrado puede generar gasto antes de que se detecte.

---

## Objetivo

Sacar la API key de OpenAI del APK y moverla al servidor (Supabase Edge Functions). La app mandará sus requests al proxy con un token de autenticación; el proxy valida + reenvía a OpenAI con la key real (que nunca baja al cliente).

**Beneficios concretos:**

| Antes | Después |
|---|---|
| Key extraíble del APK con `strings` | Key vive solo en server (Supabase Secrets) |
| Cualquier vendedor con APK puede generar tráfico ilimitado | Rate limit + auth por vendedor |
| Para revocar acceso: rotar key + recompilar + force update | Para revocar: `UPDATE usuarios SET activo=FALSE`, efecto inmediato |
| Sin tracking granular de uso | Tabla `uso_llm` con cada request: vendedor, tokens, costo estimado, latencia |
| Cambiar key = recompilar | Cambiar key = update env var en Supabase, sin tocar app |

---

## Decisiones de diseño

### A. Mecanismo de autenticación

**Tres opciones, ordenadas por simplicidad:**

#### Opción 1 — Token compartido en `app_config` (más simple)
La app lee un token de `app_config.proxy_token` después del login. Lo manda en cada request al proxy. El proxy valida que el token coincida con el de `app_config`.

- ✅ Implementación rápida (no requiere migrar auth)
- ✅ Compatible con la auth actual de Hermes (tabla `usuarios`)
- ❌ Token compartido entre TODOS los vendedores — si se filtra, hay que rotar para todos
- ❌ No permite identificar QUÉ vendedor hizo cada request → tracking limitado

#### Opción 2 — Token por vendedor (intermedio) ⭐ **Recomendada**
Tabla nueva `vendedor_tokens(vendedor_nombre, token, created_at, last_used_at)`. Al login, la app pide un token, lo guarda en `flutter_secure_storage`, y lo manda en cada request al proxy. El proxy valida el token contra la tabla → sabe qué vendedor es → rate limit + log per-vendor.

- ✅ Identificación per-vendedor (analytics ricos en `uso_llm`)
- ✅ Revocación granular (`DELETE FROM vendedor_tokens WHERE vendedor_nombre = 'X'`)
- ✅ Sin migración de auth (sigue usando tabla `usuarios`)
- ❌ Requiere endpoint nuevo `/auth-token` para emitir tokens
- ❌ Más código que opción 1

#### Opción 3 — Migrar a Supabase Auth (más robusto)
Migrar la tabla `usuarios` a `auth.users` de Supabase. Cada vendedor recibe un JWT al login. El proxy valida el JWT con la lib oficial.

- ✅ JWT con expiración + refresh token
- ✅ bcrypt automático (resuelve HIGH-1 del audit)
- ✅ Es la "forma correcta" de hacer auth en Supabase
- ❌ Migración invasiva: tocar todo el flujo de auth (mobile + desktop si aplica)
- ❌ Cambia el modelo de roles
- ❌ Esfuerzo: 2-3 días extra

**Recomendación: Opción 2** para v3.8.0. Migrar a Supabase Auth (Opción 3) lo dejamos para una v4.0 cuando tenga sentido un cambio mayor.

### B. Endpoints del proxy

Dos Edge Functions, una por servicio externo:

```
POST /cronos-chat
  Auth: Bearer <vendedor_token>
  Body: { messages, model?, temperature?, max_tokens? }
  →  Proxy a https://api.openai.com/v1/chat/completions
  Response: el JSON de OpenAI tal cual

POST /cronos-transcribe
  Auth: Bearer <vendedor_token>
  Body: multipart con audio file + language
  →  Proxy a https://api.openai.com/v1/audio/transcriptions
  Response: { text }
```

### C. Rate limits

Por vendedor:
- **`cronos-chat`**: 100 req/hora, 500 req/día
- **`cronos-transcribe`**: 60 req/hora (audio cuesta más)

Si se excede → 429 con header `Retry-After`. La app maneja: muestra mensaje "Demasiadas consultas, esperá X minutos" sin cortar la sesión.

### D. Tabla `uso_llm`

```sql
CREATE TABLE uso_llm (
  id BIGSERIAL PRIMARY KEY,
  vendedor_nombre TEXT NOT NULL,
  endpoint TEXT NOT NULL,                -- 'chat' o 'transcribe'
  modelo TEXT,                           -- 'gpt-4o-mini', 'whisper-1'
  tokens_in INT,                         -- de openai usage.prompt_tokens
  tokens_out INT,                        -- de openai usage.completion_tokens
  costo_usd_estimado NUMERIC(10,5),      -- calculado en la edge function
  latencia_ms INT,
  status_code INT,
  error TEXT,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX idx_uso_llm_vendedor_fecha ON uso_llm(vendedor_nombre, created_at DESC);
CREATE INDEX idx_uso_llm_costo_fecha ON uso_llm(created_at DESC, costo_usd_estimado);
```

Reportes que habilita:
- "Top 10 vendedores por costo del mes"
- "Costo total proyectado vs cap de OpenAI"
- "Vendedores con uso anómalo (3x el promedio)"

### E. Manejo de la key existente

Durante el rollout, la app vieja (con la key embebida) sigue funcionando. Después de algunos días con todos los vendedores en v3.8.0, **rotar la key vieja** en OpenAI Dashboard:
1. Generar key nueva en OpenAI → registrarla como Supabase Secret `OPENAI_API_KEY`
2. Esperar X días para que todos actualicen
3. Revocar la key vieja en OpenAI

Mientras conviven:
- App vieja → llama a OpenAI directo con key embebida (vulnerable)
- App nueva → llama al proxy → proxy llama con key servidor

---

## Plan de fases

### Fase 1 — Setup Supabase Edge Functions (~1 h)

**Objetivo:** entorno funcional para escribir funciones Deno.

1. **1.1** Instalar Supabase CLI en la máquina dev
2. **1.2** `supabase login` + `supabase link --project-ref kelipnwleblnpupmlont`
3. **1.3** Crear estructura: `supabase/functions/cronos-chat/`, `supabase/functions/cronos-transcribe/`
4. **1.4** Configurar Secret: `supabase secrets set OPENAI_API_KEY=sk-proj-...`

**Archivos nuevos:** `supabase/config.toml`, `supabase/functions/_shared/`

### Fase 2 — Backend: tokens + tabla de uso (~1 h)

**Objetivo:** infraestructura para auth + tracking.

1. **2.1** Migración SQL `migration_proxy_setup.sql`:
   - `CREATE TABLE vendedor_tokens` (vendedor_nombre PK, token, created_at, last_used_at)
   - `CREATE TABLE uso_llm` (ver schema arriba)
   - RLS habilitado en ambas (lecturas solo desde service_role)
2. **2.2** Endpoint `auth-token`:
   - Recibe `{username, password_hash}` (mismo SHA-256 que hoy)
   - Valida contra `usuarios`
   - Genera token random (32 bytes hex)
   - Inserta/upsert en `vendedor_tokens`
   - Retorna `{token, vendedor_nombre, role}`

**Archivos nuevos:** `scripts/migration_proxy_setup.sql`, `supabase/functions/auth-token/index.ts`

### Fase 3 — Backend: cronos-chat function (~1.5 h)

**Objetivo:** proxy funcional de chat completions.

1. **3.1** `supabase/functions/cronos-chat/index.ts`:
   - Validar header `Authorization: Bearer <token>`
   - Lookup en `vendedor_tokens` → resolver `vendedor_nombre`
   - Rate limit check: count requests del vendedor en última hora desde `uso_llm`
     → si > 100, retornar 429
   - Forward request a OpenAI con `OPENAI_API_KEY`
   - Capturar response, extraer `usage` (tokens_in/out)
   - Calcular costo (gpt-4o-mini: $0.15/M in + $0.60/M out)
   - INSERT en `uso_llm`
   - Retornar response al cliente
2. **3.2** Compartir lógica de auth + log via `supabase/functions/_shared/`:
   - `_shared/auth.ts` — valida token
   - `_shared/log.ts` — INSERT en uso_llm
3. **3.3** Deploy: `supabase functions deploy cronos-chat`

**Archivos nuevos:** `supabase/functions/cronos-chat/index.ts`, `supabase/functions/_shared/*.ts`

### Fase 4 — Backend: cronos-transcribe function (~1 h)

**Objetivo:** proxy funcional para Whisper.

1. **4.1** `supabase/functions/cronos-transcribe/index.ts`:
   - Mismo flujo de auth + rate limit (con limite separado: 60/h)
   - Forward multipart a OpenAI Whisper
   - Loggear tokens_in (audio segundos × estimado de tokens) o costo plano por minuto ($0.006)
2. **4.2** Deploy

**Archivos nuevos:** `supabase/functions/cronos-transcribe/index.ts`

### Fase 5 — Migración del cliente Flutter (~2 h)

**Objetivo:** la app habla con el proxy en vez de OpenAI directo.

1. **5.1** `lib/services/auth_token_service.dart` (nuevo):
   - `getToken()` → lee de `flutter_secure_storage`
   - `requestNewToken(username, password_hash)` → POST a `/auth-token`
   - Llamado desde `AuthService.login()` después de validar credenciales
2. **5.2** Modificar `lib/services/assistant_service.dart`:
   - Cambiar `Uri.parse('https://api.openai.com/v1/chat/completions')` por
     `Uri.parse('${AppConfig.supabaseFunctionsUrl}/cronos-chat')`
   - Cambiar `Authorization: Bearer ${AppConfig.openaiApiKey}` por
     `Authorization: Bearer ${await AuthTokenService.getToken()}`
   - Manejar 429: mostrar mensaje al usuario, no reintentar
   - Manejar 401: token expirado/revocado → forzar re-login
3. **5.3** Modificar `lib/services/whisper_service.dart` igual
4. **5.4** Sacar `openaiApiKey` de `lib/config/constants.dart` (ya no se usa) — keep retrocompatibilidad por si una versión vieja la necesita
5. **5.5** Agregar `supabaseFunctionsUrl` a `constants.dart`

**Archivos modificados:** `assistant_service.dart`, `whisper_service.dart`, `auth_service.dart`, `constants.dart`, `constants.example.dart`
**Archivos nuevos:** `auth_token_service.dart`

### Fase 6 — Testing + rollout (~1 h)

**Objetivo:** validar end-to-end y desplegar gradualmente.

1. **6.1** Test local con `supabase functions serve` → llamar desde la app en dev
2. **6.2** Build APK v3.8.0 firmado con release keystore
3. **6.3** Instalar en 1 dispositivo de prueba (no rollout masivo todavía)
4. **6.4** Probar:
   - Login → obtiene token
   - Cronos chat → proxy reenvía OK, queda log en `uso_llm`
   - Cronos voz → mismo flujo
   - Rate limit: simular >100 requests/h → ver 429 y mensaje al usuario
   - Token revocado: borrar de `vendedor_tokens` → siguiente request 401 → re-login
5. **6.5** Si todo OK, publicar release v3.8.0 + force update con `min_version_required = '3.8.0'`
6. **6.6** Después de N días sin issues: rotar la key vieja en OpenAI Dashboard

### Fase 7 — Observabilidad (~30 min)

**Objetivo:** dashboard para monitorear costos.

1. **7.1** Queries de reporte en Supabase SQL Editor (no UI nueva por ahora):
   - "Top vendedores por costo del mes"
   - "Costo total proyectado vs cap"
   - "Errores 5xx del proxy"
2. **7.2** Documentar las queries en `docs/PLAN_MAESTRO_HERMES_MOBILE.html` (extender §20 Cronos Analytics)

### Fase 8 — Documentación (~30 min)

1. **8.1** Actualizar `CLAUDE.md` con la arquitectura nueva
2. **8.2** Actualizar `ARQUITECTURA.md` con el patrón "Auth via tokens y proxy a OpenAI"
3. **8.3** Actualizar `WORKFLOW.md` con cómo deployar/rotar funciones
4. **8.4** Actualizar plan maestro HTML con timeline v3.8.0 + nueva sección "Proxy OpenAI"

---

## Resumen de archivos tocados

### Nuevos
- `supabase/config.toml`
- `supabase/functions/_shared/auth.ts`
- `supabase/functions/_shared/log.ts`
- `supabase/functions/auth-token/index.ts`
- `supabase/functions/cronos-chat/index.ts`
- `supabase/functions/cronos-transcribe/index.ts`
- `scripts/migration_proxy_setup.sql`
- `lib/services/auth_token_service.dart`
- `docs/PLAN_PROXY_OPENAI.md` (este)

### Modificados
- `lib/services/auth_service.dart` (devuelve token después del login)
- `lib/services/assistant_service.dart` (apunta a proxy + auth con token)
- `lib/services/whisper_service.dart` (idem)
- `lib/config/constants.dart` (saca openaiApiKey, agrega supabaseFunctionsUrl)
- `lib/config/constants.example.dart` (template actualizado)
- `pubspec.yaml` (bump a 3.8.0+40)
- `CLAUDE.md`
- `docs/ARQUITECTURA.md`
- `docs/WORKFLOW.md`
- `docs/PLAN_MAESTRO_HERMES_MOBILE.html`

---

## Riesgos y mitigaciones

| Riesgo | Mitigación |
|---|---|
| Edge Functions caen → toda la app sin Cronos | Mostrar mensaje claro "Cronos temporalmente no disponible". Quick actions (bypass) siguen funcionando porque van directo a Supabase Postgres. |
| Token comprometido | Rate limit individual contiene el daño. Detección via `uso_llm` (anomalías per-vendedor). Revocación: 1 query DELETE. |
| Costos del proxy en sí | Supabase Free incluye 500k invocaciones/mes. Con 10 vendedores × 50 calls/día × 22 días = 11k/mes. Lejos del límite. |
| Latencia agregada | Edge Functions Supabase agregan ~100-200ms. Total LLM ~1700ms vs ~1500ms hoy. Aceptable. |
| Rollback necesario | Mantener la versión v3.7.x como fallback durante 2 semanas. Si algo se rompe en v3.8.0, force update a 3.7.x. |
| Pérdida de Edge Function deployment | Las funciones están versionadas en el repo (`supabase/functions/`). `supabase functions deploy <name>` desde cualquier máquina con CLI. |

---

## Pre-requisitos antes de arrancar

1. ✅ Supabase project activo (ya existe: kelipnwleblnpupmlont)
2. ✅ OpenAI API key con cap configurado (ya tiene cap $400)
3. ⏳ Supabase CLI instalado en la máquina dev → instalar antes de empezar
4. ⏳ Definir si vamos por Opción 2 (token por vendedor) — recomendada

---

## Cuándo arrancar

El user mencionó que quiere hacer esto **juntos** en una próxima sesión. Cuando llegue el momento:

1. Re-leer este documento
2. Confirmar que la opción de auth elegida sigue siendo Opción 2
3. Arrancar por Fase 1 secuencialmente
4. Marcar progreso en TodoWrite

Las 8 fases están diseñadas para hacerse en orden — cada una construye sobre la anterior. Pausas naturales después de Fase 2 (tabla lista, sin código), Fase 4 (backend completo, sin cliente migrado), Fase 5 (cliente migrado, sin testear) y Fase 6 (rollout completo).
