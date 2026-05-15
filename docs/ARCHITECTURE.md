# Arquitectura — decisiones clave

> Documento vivo. Cada patrón acá existe **por una razón concreta** (casi siempre un bug que apareció). Si vas a tocar algo, leé el "por qué" antes.

---

## 1. ActividadesService es la única fuente de verdad del lifecycle

**Archivo:** `lib/services/actividades_service.dart`

**Regla:** todo lo que afecta el ciclo de vida de una actividad (crear, editar, completar, reabrir, eliminar) se hace **solo** via este service. La UI **no** programa/cancela notificaciones, **no** llama Google Calendar directo, **no** emite eventos.

**Por qué:**
Antes había 5 caminos para completar una actividad: Ficha, Mi Agenda (check ✓), Historia Clínica del cliente, Cronos (confirmar pendiente), VisitasService cuando cerraba una agendada. Solo **uno** cancelaba la notificación → notificaciones "zombies" que llegaban para actividades ya cerradas.

El fix fue arquitectónico: sacar toda la lógica de side effects de la UI y centralizarla en el service. Ahora cualquier camino queda cubierto automáticamente.

**Side effects que maneja el service:**
- `NotificationService.cancel(id)` / `schedule(...)` con el `id` **real** de la actividad en DB (no un random)
- `CalendarService.updateEvent()` / `deleteEvent()` si hay `google_event_id`
- `DataEvents.notifyActividades()` para refrescar pantallas suscriptas

**Aplicación:**
Si agregás un nuevo método que afecta una actividad, los side effects van en el service, **no** en la UI.

---

## 2. DataEvents como event bus global

**Archivo:** `lib/services/data_events.dart`

Son 3 `ValueNotifier<int>` globales:
```dart
DataEvents.actividades  // incrementa al crear/editar/completar/eliminar actividad
DataEvents.visitas      // incrementa al registrar visita
DataEvents.pedidos      // incrementa al cambiar pedidos
```

**Por qué:**
Badges en Acciones tab (actividades pendientes, visitas hoy, pedidos pendientes) se cargaban solo en `initState`. Si completabas una actividad desde Cronos, el badge en Acciones seguía mostrando el número viejo hasta reabrir la tab.

**Cómo usarlo:**

Servicio que escribe:
```dart
await PgService.execute('UPDATE ...');
DataEvents.notifyActividades();  // cualquier cosa que escuche se refresca
```

Pantalla que necesita refrescar:
```dart
@override
void initState() {
  super.initState();
  DataEvents.actividades.addListener(_reload);
}
@override
void dispose() {
  DataEvents.actividades.removeListener(_reload);
  super.dispose();
}
```

**No usar** si la pantalla ya se refresca de otra forma (ej: `Navigator.pop(context, true)` que dispara reload en el parent). Es para casos donde la escritura ocurre en un lugar distante y no hay navegación que la conecte.

---

## 3. Offline-first para clientes

**Archivos:** `lib/services/clientes_service.dart`, `lib/services/clientes_cache.dart`

Flujo de `ClientesService.getClientes()`:
1. Intento SQL Server con timeout 5s
2. Si devuelve → guardo en `ClientesCache` (SharedPreferences) + timestamp
3. Si falla → leo del cache
4. Si tampoco hay cache → throw

**Por qué:**
Los vendedores están todo el día fuera de la oficina sin VPN. La cartera de clientes cambia poco (altas/bajas mensuales). Era crítico que puedan usar Cronos, agendar actividades, registrar visitas sin VPN.

**Edge cases:**
- Cliente renombrado después de crear actividad → ver sección "Resolución de nombre denormalizado" en `HistoriaClinica`. El código manda, no el nombre cacheado.
- Cliente nuevo que no está en cache → Cronos dice "no encontrado" y sugiere conectar VPN y reintentar.
- Cache > 7 días → badge amarillo "puede estar desactualizada".

**Qué NO cachear:** scorecard, ventas, pedidos, facturas. Datos volátiles. Cache stale engañaría al vendor.

---

## 4. PromptService con fallback

**Archivo:** `lib/services/prompt_service.dart`

System prompts de agentes IA (Cronos y futuros) viven en Supabase tabla `agent_prompts`. Service:
- Cachea 5 minutos en memoria
- Reemplaza placeholders `{{vendedor}}`, `{{fecha}}`, `{{clientes}}` etc en runtime
- Si Supabase no responde, usa fallback hardcoded

**Por qué:**
Editar el prompt de Cronos sin recompilar ni publicar APK nueva. El user ajusta, corre un `UPDATE` en Supabase, y a los 5 minutos todo el equipo está con el prompt nuevo.

**Cómo agregar un agente nuevo:**
1. `INSERT INTO agent_prompts (agent_id, prompt, ...) VALUES ('cobrador', '...')`
2. Agregar fallback en `PromptService._fallbacks` por resiliencia
3. Desde el código: `final prompt = await PromptService.get('cobrador', vars)`

---

## 5. ClienteRouter universal

**Archivo:** `lib/services/cliente_router.dart`

`ClienteRouter.open(context, codigo, nombre?)` abre `ClienteDetailScreen` desde cualquier lugar donde aparezca un código de cliente. Cachea la cartera internamente.

**Por qué:**
Había 8+ lugares donde el nombre del cliente aparecía como texto "muerto" (ventas top 10, drill-downs, cards de Cronos, detalle de pedido, etc). Los vendedores esperaban poder tocar y ver la ficha. Centralizamos la lógica.

**Si hay varios clientes con mismo código:** no debería pasar — el código es único. Pero si pasa, toma el primero.

---

## 6. Notification ID = actividad.id real

**Archivo:** `lib/services/actividades_service.dart` (en `registrar()`)

Cuando creamos una actividad con fecha futura, la notificación se programa con:
```dart
await NotificationService.schedule(
  id: actividadId,  // el int real que devolvió INSERT ... RETURNING id
  ...
);
```

**Por qué:**
Antes el código era `id: DateTime.now().millisecondsSinceEpoch % 100000` (número random). Al completar/eliminar, `NotificationService.cancel(actividadId)` buscaba por el ID de DB pero la notif estaba registrada con un random → nunca matcheaba → notif se disparaba igual.

**Regla:** todo recurso externo que necesitamos poder referenciar después (cancelar, actualizar) debe usar un ID estable derivado de la entidad en DB. Nunca random.

---

## 7. Timezone AR en PgService

**Archivo:** `lib/services/pg_service.dart`

Cada vez que abrimos conexión:
```dart
await _conn!.execute("SET TIME ZONE 'America/Argentina/Buenos_Aires'");
```

**Por qué:**
Postgres server corre en UTC. Queries con `fecha_programada::date = CURRENT_DATE` resolvían con hora UTC del server, no hora local del vendedor. Una actividad a las 23:00 AR (02:00 UTC siguiente día) no aparecía en filtro "pendientes de hoy".

**Implicancia:** cualquier query nuevo con `CURRENT_DATE`, `::date`, `NOW()` ya asume hora AR del vendor. No hace falta más `AT TIME ZONE` manual.

---

## 8. SQL Migrations idempotentes

**Archivos:** `scripts/*.sql`

Todos los scripts usan:
- `CREATE TABLE IF NOT EXISTS ...`
- `ALTER TABLE ... ADD COLUMN IF NOT EXISTS ...`
- `INSERT ... ON CONFLICT (agent_id) DO NOTHING`
- `DROP TRIGGER IF EXISTS ...; CREATE TRIGGER ...`

**Por qué:**
Correr una migración 2 veces no debería romper. Si hay que repararla por cualquier motivo, la volvemos a correr. Si la llevamos a otro entorno, se aplica limpio.

---

## 9. UI no calcula ni oculta errores

**Patrón:** `try { ... } catch (e) { debugPrint(...); }` o mostrar un snackbar claro. Nunca `catch (_) {}`.

**Por qué:**
Antes la Acciones tab tenía catchs silenciosos → si SQL Server estaba caído, los badges mostraban 0 sin avisar al vendor que era error de VPN. Pensaba que estaba al día cuando en realidad no había conexión.

---

## 10. Estructura de constants y credenciales

`lib/config/constants.dart` es **gitignored**. Contiene desde v3.8.0:
- ~~OpenAI API key~~ — **removida en v3.8.0**, ahora vive en Supabase Secrets
- Supabase credentials (rol postgres — sigue siendo CRIT-3 documentado)
- SQL Server credentials (red interna VPN, no es CRIT)
- `openaiModel` (solo el nombre del modelo, no la key)
- `supabaseFunctionsUrl` (URL pública de las Edge Functions)

`lib/config/constants.example.dart` es el template versionado con placeholders tipo `"TU_PASSWORD"`. Cuando alguien clona el repo, copia este archivo a `constants.dart` y completa.

⚠️ **Deuda técnica residual (CRIT-3):** las credenciales de Supabase Postgres siguen compilándose al APK. Mitigado con release keystore (ADR-006) + force update + capacidad de rotar la pass. Migración completa pospuesta — ver [ADR-005](decisions/ADR-005-postergar-crit3-db-creds.md). El patrón usado para resolver CRIT-2 (OpenAI) está documentado en el §11 abajo y formalizado en [ADR-007](decisions/ADR-007-auth-via-vendedor-tokens.md).

---

## 11. Auth via vendedor_tokens y proxy de OpenAI vía Edge Functions

**Archivos:** `lib/services/auth_token_service.dart`, `lib/services/assistant_service.dart`, `lib/services/whisper_service.dart`, `supabase/functions/*`

**Patrón introducido en v3.8.0** para sacar la API key de OpenAI del cliente.

### Flujo

```
1. Login local (auth_service.dart) valida contra tabla usuarios con SHA-256
2. Auth exitoso → llama a Edge Function /auth-token con username+hash
3. La función emite un token random hex (32 bytes), upsert en vendedor_tokens
4. App guarda el token en flutter_secure_storage
5. Cada call a Cronos (chat o voz) → header "Authorization: Bearer <vendedor_token>"
6. Edge Function valida token → vendedor_nombre → rate limit → forward a OpenAI
7. Respuesta de OpenAI vuelve al cliente, costo se loggea en uso_llm
```

### Por qué

CRIT-2 del audit OWASP (mayo 2026): la OpenAI key estaba embebida en el APK y era extraíble con `strings`. Un APK filtrado podía drenar el cap de OpenAI. La solución arquitectónica fue mover la key a server-side (Supabase Secrets) e introducir un proxy autenticado.

### Aplicación

- **Cualquier llamada nueva a OpenAI desde la app** debe pasar por Edge Function. Nunca llamar a `api.openai.com` directo.
- **Si se agrega un endpoint nuevo de OpenAI** (ej: imágenes con DALL-E), crear nueva Edge Function siguiendo el patrón de `cronos-chat`/`cronos-transcribe`.
- **Para cualquier servicio externo similar** (no solo OpenAI): aplicar este patrón en lugar de embeber credenciales.
- El token de vendedor se revoca con `DELETE FROM vendedor_tokens WHERE vendedor_nombre = ...`. Útil para deshabilitar a un vendedor sin recompilar.
- El secret `OPENAI_API_KEY` se rota desde Supabase Dashboard sin tocar app ni recompilar.

### Anti-patterns para este patrón

- ❌ Llamar directo a OpenAI desde la app
- ❌ Guardar el token en `SharedPreferences` plano (debe ser `flutter_secure_storage`)
- ❌ Skipear la auth header en alguna call de testing/debug
- ❌ Activar `--verify-jwt` en las Edge Functions (validamos nosotros con vendedor_tokens; ver [ADR-007](decisions/ADR-007-auth-via-vendedor-tokens.md))

---

## 12. Roles y permisos via Session.can()

**Archivos:** `lib/services/auth_service.dart`, `lib/models/session.dart`, `lib/services/pg_service.dart`, `supabase/functions/auth-token/index.ts`

**Patrón introducido en v3.9.0** para integrar el sistema de roles compartido con Hermes Desktop.

### Flujo

```
1. Login: pg_service.verifyUser hace JOIN usuarios + roles, devuelve
   (role, vendedor_nombre, permisos) en una sola query.
2. AuthService.login aplica 2 gates:
   a) permisos['mobile.access'] debe ser true.
   b) vendedor_nombre debe estar presente (fallback al username durante transición).
3. Si pasan los gates, Session.set(permisos: ...) carga las keys con
   value=true en _permissions.
4. Cualquier widget con sensibilidad de permiso usa Session.current.can(key).
5. La Edge Function auth-token también lee vendedor_nombre de la DB
   (no del body) para emitir el token correctamente.
```

### Por qué

El admin del negocio (Hermes Desktop) gestiona roles centralmente. Mobile debía:
- Bloquear acceso a usuarios sin permiso (`mobile.access`).
- Resolver el `vendedor_nombre` real (no asumir `== username`).
- Mostrar/ocultar features según el rol sin recompilar.

Ver [ADR-008](decisions/ADR-008-roles-permisos-jsonb.md) para razones completas y alternativas descartadas.

### Aplicación

- **Cualquier feature nueva con sensibilidad de permiso** debe envolverse en `if (Session.current.can('mobile.xxx'))`. La key se registra en `permisos_catalog` desde Desktop.
- **Nunca asumir que `username == vendedor_nombre`**. Para cualquier query que filtre por vendedor, usar `Session.current.vendedorNombre`.
- **Para revocar acceso a un usuario**: el admin baja el flag en Desktop. La revocación se aplica al próximo login (no instantánea).
- **Si una key no está en el dict del rol, `can()` devuelve false** (cerrado por defecto). Esto significa que agregar permisos nuevos no rompe roles existentes.

### Anti-patterns para este patrón

- ❌ Usar `Session.current.username` para filtrar queries de datos del vendedor (usar `vendedorNombre`).
- ❌ Mostrar el botón en gris cuando no hay permiso (mejor: no mostrarlo).
- ❌ Hardcodear permisos en el código (deben venir del rol, no del username).
- ❌ Enviar `vendedor_nombre` a la Edge Function desde el cliente (la función debe leerlo de DB).
- ❌ Cachear `_permissions` fuera de Session (la verdad vive ahí).

### Notas operativas descubiertas en el rollout (v3.9.0 → v3.9.3)

- **El package `postgres` de Dart devuelve `jsonb` como `String`, no como `Map`.** El cliente Dart hace `jsonDecode` del valor. Defensivamente también soporta `Map` por si el driver cambia comportamiento en el futuro.
- **La columna `roles.permisos` puede ser `text` o `jsonb`** según cómo Hermes Desktop la haya regenerado. La query usa `COALESCE(r.permisos::text, '{}')` — el cast funciona con ambos tipos (no-op si es text, serializa si es jsonb). Esto desacopla a Mobile del schema exacto que mantenga Desktop.
- **El check de force update se ejecuta pre-login**, no post-login. Si el flow de auth se rompe en una versión, el device igual recibe el prompt de upgrade al abrir la app. Implementación en `LoginScreen._bootstrap()` antes de mostrar el form.
- **Agregar una key nueva en `permisos_catalog`** la hace aparecer automáticamente en el panel de roles de Hermes Desktop sin recompilar Desktop. Validado con `mobile.action.scorecard_drilldown` (v3.9.3) — proceso completo en `WORKFLOW.md` sección "Agregar un permiso nuevo".

---

## Anti-patterns a evitar

- ❌ Programar notificaciones con IDs random
- ❌ Cancelar notificaciones desde la UI en lugar del service
- ❌ `catch (_) {}` silencioso
- ❌ Queries con `CURRENT_DATE` asumiendo UTC (ya está arreglado en PgService pero ojo con nuevas queries)
- ❌ Cachear datos volátiles (scorecard, ventas, pedidos)
- ❌ Hardcodear prompts de LLM en el código (usar `agent_prompts`)
- ❌ Consumir listas de clientes sin pasar por `ClientesService` (se pierde offline-first + cache)
