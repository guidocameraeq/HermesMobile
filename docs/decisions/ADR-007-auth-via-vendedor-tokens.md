# ADR-007: Auth via vendedor_tokens y proxy de OpenAI vía Edge Functions

**Fecha:** 2026-05-06
**Estado:** Aceptado

## Contexto

CRIT-2 del audit OWASP de mayo 2026: la API key de OpenAI (`sk-proj-...`) estaba embebida en `lib/config/constants.dart` y se compilaba al APK release. Era extraíble en segundos con `strings app-release.apk | grep "sk-proj"`. ProGuard/R8 ofuscan nombres de clases pero no strings literales.

Riesgo concreto: cualquier APK filtrado (vendedor descontento, ex-empleado, error operativo) permitía al atacante usar la key contra OpenAI hasta que se detectara y revocara — drenando el cap mensual ($400 USD compartido con otros proyectos del workspace).

Necesitábamos sacar la key del APK. Esto implicaba decidir cómo autenticar al cliente contra el server (proxy) sin volver a tener el problema de "credenciales en el APK".

## Decisión

Implementamos **3 Edge Functions Deno en Supabase** + **tabla `vendedor_tokens`** + helpers compartidos:

1. **`auth-token`**: recibe `{username, password_hash}` (mismo SHA-256 que ya usa la app contra `usuarios`), valida, emite token random hex (32 bytes = 64 chars), upsertea en `vendedor_tokens`, retorna al cliente.
2. **`cronos-chat`**: proxy a `https://api.openai.com/v1/chat/completions`. Valida Bearer token contra `vendedor_tokens` → resuelve `vendedor_nombre` → rate limit (100 req/h) → forward → loggea en `uso_llm` con tokens y costo USD estimado.
3. **`cronos-transcribe`**: idem para Whisper. Rate limit 60 req/h.

La key de OpenAI vive como **Supabase Secret** `OPENAI_API_KEY`, accesible solo desde el runtime de las funciones, no exposable al cliente.

Las funciones se deployan con `--no-verify-jwt` (validamos nosotros con vendedor_tokens, no usamos Supabase Auth).

El cliente Flutter usa `lib/services/auth_token_service.dart` (nuevo en v3.8.0) que guarda el token en `flutter_secure_storage` y lo manda en cada call a Cronos.

## Razón

- **Resuelve CRIT-2 completamente**: `strings app-release.apk | grep "sk-proj"` devuelve 0 en v3.8.0+. La key vive solo server-side.
- **Auth identifiable per-vendedor**: cada token está asociado a un `vendedor_nombre`. Permite tracking granular, rate limit individual, revocación selectiva (`DELETE FROM vendedor_tokens WHERE vendedor_nombre = 'X'` deshabilita a un vendedor sin recompilar la app).
- **Compatible con auth existente**: no migramos a Supabase Auth (que sería invasivo). El token se emite con la misma SHA-256 que ya validaba la app — cero cambios de UX.
- **Costo cero**: Supabase Free incluye 500k invocaciones/mes. Uso esperado con 10 vendedores = ~11k/mes (lejos del límite).
- **Rotación de key sin tocar app**: cambiar `OPENAI_API_KEY` en Supabase Dashboard se propaga al siguiente cold start de las funciones (~minutos). Sin recompilar APK, sin force update.
- **Tracking en `uso_llm`**: cada call deja una fila con tokens_in/out, costo USD estimado, latencia, status. Base para analytics de costo per-vendedor.

## Alternativas consideradas

### Token compartido en `app_config` (Opción 1 del plan original)
- Pro: implementación mínima, no requiere tabla nueva
- Con: token único entre TODOS los vendedores; si se filtra hay que rotar para todos. No permite identificar quién hizo cada request.
- Descartado: pierde el valor de tracking + revocación granular.

### Migrar a Supabase Auth (Opción 3 del plan original)
- Pro: JWT real con expiración + refresh + opcional MFA + bcrypt automático
- Con: refactor invasivo de auth, migración de tabla `usuarios` a `auth.users`, cambio de modelo de roles, 2-3 días extra.
- Descartado: scope excesivo para resolver CRIT-2. Documentado para futuro en TODO.md.

### Rotar la OpenAI key cada vez sin proxy
- Pro: cero código nuevo
- Con: no resuelve nada — la nueva key sigue compilada al próximo APK. Solo cierra ataques en curso, no previene nuevos.
- Descartado: trata el síntoma, no la causa.

### Activar `--verify-jwt` en las Edge Functions
- Pro: Supabase valida el JWT automáticamente
- Con: rechaza nuestros vendedor_tokens (que no son JWT válidos de Supabase Auth). Forzaría migrar a Supabase Auth.
- Descartado: incompatible con la decisión de auth propia. Documentado también en `REJECTED.md`.

### Llamar a OpenAI desde la app pero con una API key gateway tipo OpenRouter / Apicat / Cloudflare AI Gateway
- Pro: rotación automática, monitoring incluido
- Con: dependencia externa adicional, costo extra, no tenemos auth de vendedor (cualquiera con la URL puede usar el gateway)
- Descartado: agregaría más vendor lock-in sin resolver auth de vendedor.

## Consecuencias

- **Cualquier nueva integración con servicios externos sigue este patrón**: si en el futuro agregamos imágenes (DALL-E), TTS (ElevenLabs), o cualquier API con key, va via Edge Function. Anti-pattern documentado en `ARCHITECTURE.md` §11.
- **APKs viejos (v3.7.x) siguen funcionando con la key embebida vieja** hasta que se rote. Esto se hace 3-5 días después del rollout v3.8.0 para que ningún vendedor quede sin Cronos en la transición.
- **Si la key vieja se filtra antes de la rotación**: tenemos rate limit per-vendedor + cap mensual + capacidad de revocar via OpenAI Dashboard. Daño contenido.
- **Latencia agregada ~100-200ms por la Edge Function**: medido en smoke test (3.3s end-to-end vs ~1.5s directo a OpenAI). Aceptable para uso interactivo de Cronos.
- **CRIT-3 (credenciales DB en APK) sigue sin resolver**: ver [ADR-005](ADR-005-postergar-crit3-db-creds.md) por qué se posterga. El patrón de este ADR-007 es la base sobre la cual eventualmente se resolverá CRIT-3 (refactor de todos los services que usan PgService → Edge Functions).
- **Compromiso a futuro**: si crecemos a >15 vendedores o necesitamos refresh tokens reales / MFA, considerar migración a Supabase Auth (escenario que reemplazaría este ADR-007 con uno nuevo).
