# Status — Hermes Mobile

> **Snapshot del estado actual del proyecto.** Para tareas pendientes
> accionables, fuente única es [`TODO.md`](TODO.md). Este archivo solo
> resume "qué versión hay y qué bloques completos / en curso".

**Fecha del snapshot:** 2026-05-15
**Versión actual:** v3.9.3+44 (roles + permisos validado end-to-end)
**Último release publicado:** v3.9.3
**APK URL:** https://github.com/guidocameraeq/HermesMobile/releases/tag/v3.9.3
**Force update activo:** `min_version_required = '3.9.3'`

---

## Tabla de bloques del plan original

| Bloque | Descripción | Estado | Versión |
|---|---|---|---|
| **Base** | Scorecard, Clientes, Ventas, Pedidos, Visitas GPS | ✅ Completo | v1.0–v2.2 |
| **A** | Visitas GPS con geolocalización | ✅ Completo | v1.8.0 |
| **B** | Análisis de líneas de producto en ficha | ✅ Completo | v1.7.0 |
| **E** | Historia Clínica (actividades por cliente + timeline) | ✅ Completo | v2.5–v2.8 |
| **I** | Mi Agenda + Notificaciones locales | ✅ Completo | v2.7–v2.8 |
| **K** | Rediseño UX (drawer, config, linking universal) | ✅ Completo | v2.9.0 |
| **L** | Google Calendar (off/manual/auto) | ✅ Completo | v3.1.0 |
| **P** | Módulo Pedidos (pendientes/cerrados) | ✅ Completo | v1.9.x |
| **Cronos** (extra) | Asistente IA + Whisper + Edge Functions proxy | ✅ Completo | v2.3 → v3.8.0 |
| **Biométrico** (extra) | Login con huella | ✅ Completo | v2.8.0 |
| **Force Update** (extra) | Killswitch remoto via `app_config` | ✅ Completo | v3.7.0 |
| **Identidad visual** (extra) | Iconos Hermes + Cronos custom | ✅ Completo | v3.7.0–v3.7.2 |
| **Security hardening** (extra) | Keystore release, RLS, network_security_config | ✅ Completo | v3.7.3 |
| **Roles y permisos** (extra) | Sistema de permisos JSONB + 2 gates + 9 puntos UI condicional | ✅ Completo | v3.9.0 |
| **C** | Embudo CRM de Prospectos | ⏳ Pendiente | — |
| **F** | Matriz de Potencial | ⏳ Pendiente | — |
| **D** | Leads desde Google Forms | ⏳ Pendiente | — |
| **G** | Relevamiento PDV | ⏳ Pendiente | — |
| **H** | Objetivo de Visitas Diarias | ⏳ Pendiente | — |
| **J** | Push Notifications (FCM) | 🟡 ~70% | falta solo FCM server-side |

**Para detalle granular de tareas pendientes** (operativas, técnicas, deudas):
ver [`TODO.md`](TODO.md). Este archivo NO duplica la lista — solo resume bloques.

---

## v3.9.0 → v3.9.3 — Roles y permisos JSONB (rollout completo)

Integración del sistema de roles compartido con Hermes Desktop, validada end-to-end con catálogo de permisos administrable.

**Componentes (v3.9.0):**
- Query de login con JOIN a `roles` para traer permisos en jsonb (con `COALESCE(r.permisos::text, '{}')` — agnóstico al tipo de columna desde v3.9.2)
- 2 gates: `mobile.access` + `vendedor_nombre` no nulo (con fallback transitorio al username)
- `Session.can(key)` consultable desde cualquier widget
- 10 puntos de UI condicionados (4 tabs + crear/completar/eliminar actividad + registrar visita + mic Cronos + feedback + Saldo CxC + facturas + Calendar + scorecard drill-down desde v3.9.3)
- Edge Function `auth-token` también lee `vendedor_nombre` de DB (Opción A — single source of truth)

**Hotfixes en el rollout:**
- **v3.9.1**: el package `postgres` de Dart devuelve `jsonb` como `String`, no como `Map`. Fix: `jsonDecode` en lugar de `is Map`. Force update movido a pre-login (antes era post-login) para que un device con app rota igual reciba el prompt de upgrade.
- **v3.9.2**: la columna `roles.permisos` puede ser `text` en vez de `jsonb` según cómo Desktop la haya regenerado. Fix: cast `r.permisos::text` en la query, agnóstico al tipo de columna.
- **v3.9.3**: agregada key `mobile.action.scorecard_drilldown` en `permisos_catalog`. Validado end-to-end: registro la key en catalog → Desktop la muestra automáticamente en el panel de roles → admin la activa/desactiva por rol → Mobile lo respeta tras re-login.

**Verificación end-to-end:**
- Login con Franzo (username `Franzo` ≠ vendedor_nombre `FRANZO SERGIO`) entra y carga datos del vendedor real ✅
- Login con viewer es rechazado con mensaje específico ✅
- Agregar key nueva en `permisos_catalog` → aparece automática en panel Desktop sin recompilar Desktop ✅
- Toggle de permiso en Desktop → se ve reflejado en Mobile tras re-login ✅

Ver [ADR-008](decisions/ADR-008-roles-permisos-jsonb.md) y [ARCHITECTURE.md §12](ARCHITECTURE.md).

## v3.8.0 — Proxy OpenAI server-side (CRIT-2 del audit resuelto)

La API key de OpenAI **ya no se compila al APK**. Vive solo en Supabase Secrets, accesible desde Edge Functions con auth de vendedor.

**Componentes:**
- 3 Edge Functions (Deno) en Supabase: `auth-token`, `cronos-chat`, `cronos-transcribe`
- 2 tablas nuevas: `vendedor_tokens`, `uso_llm` (con RLS)
- Cliente Flutter migrado: `auth_token_service.dart` (nuevo), `assistant_service.dart` y `whisper_service.dart` apuntan al proxy
- `constants.dart`: removida `openaiApiKey`, agregado `supabaseFunctionsUrl`
- Rate limit per-vendedor: 100 chat/h, 60 transcribe/h
- Tabla `uso_llm` con tracking granular: tokens, costo USD estimado, latencia, status

**Verificación:** `strings app-release.apk | grep "sk-proj"` → 0 resultados.

**Pendiente operativo:**
- Cargar `OPENAI_API_KEY` en Supabase Dashboard → Functions → Secrets (5 min, browser)
- Validar v3.8.0 en device de prueba
- Después de N días con todos en v3.8.0: rotar la key vieja en OpenAI Dashboard



## v3.7.3 — Security hardening (sin release todavía)

Tras la auditoría de seguridad de mayo 2026 (resultado en este doc anterior), se aplicaron las correcciones críticas:

- **Release keystore propio** (CRIT-1 del audit). Antes el APK release se firmaba con la clave debug — cualquier dev con Android Studio podía generar un APK aceptado como update legítimo. Ahora se firma con `keystore/hermes-release.jks` (gitignored, RSA 2048, validez 10000 días).
  - SHA-1 nuevo: `73:9D:EE:58:75:E6:18:B4:3D:6C:DA:49:3B:B7:3C:B0:C9:83:F7:0F`
  - **Acción pendiente:** actualizar este SHA-1 en Google Cloud Console → OAuth client Android (sino el botón "Conectar con Google" falla).
  - **Migración:** los vendedores con app debug-signed (v3.7.2 o anterior) deben **desinstalar y reinstalar** v3.7.3+ una sola vez. Android rechaza updates con firma distinta.
- **RLS habilitado** en `app_config` y `cronos_logs` (HIGH-2). Hoy no protege porque la app conecta como rol postgres, pero deja la base lista para Edge Functions con anon key + JWT.
- **`network_security_config.xml`** declarado explícitamente. Confía solo en CAs del sistema (no user-installed). Previene MITM con certs custom.
- **Force update activo**: `min_version_required = '3.7.2'` (antes del rollout v3.7.3 lo subiremos a `'3.7.3'`).

**Pendiente para v3.8.0** (sprint juntos): proxy OpenAI vía Supabase Edge Functions. Plan completo en `docs/PLAN_PROXY_OPENAI.md`.

## v3.7.0 — Force Update + Identidad visual

## v3.7.0 — Force Update + Identidad visual (listo para release)

- **Force update remoto** vía tabla nueva `app_config` en Supabase. Si la versión local del vendedor < `min_version_required`, al login se muestra `ForceUpdateScreen` bloqueante (solo "Actualizar ahora" o cerrar sesión). Reversible al instante con un UPDATE.
- **Pre-download del APK** en background al detectar release nuevo. Cuando el vendedor toca "Actualizar", el instalador abre instantáneo (sin esperar 1 min de descarga).
- **Migración SQL aplicada**: `app_config` con row inicial `min_version_required = '3.0.0'` (permisivo).
- **Icono propio del APK**: Hermes (line art clásico, mensajero alado) reemplaza el icono Flutter default. Generado con `flutter_launcher_icons` en todas las densidades (mdpi → xxxhdpi) + adaptive icon Android 8+.
- **Icono propio de Cronos**: anciano alado con guadaña + reloj de arena reemplaza la estrella Material `Icons.auto_awesome` en 3 lugares (HeroIcon welcome, CronosBadge AppBar, CronosInfoSheet). Usa `Image.asset` con `colorBlendMode: BlendMode.srcIn` para teñir dinámicamente (1 asset, color flexible). Animaciones existentes intactas.

Archivos nuevos: `lib/screens/force_update_screen.dart`, `scripts/migration_app_config.sql`, `assets/icons/hermes.png`, `assets/icons/cronos.png`.
Archivos modificados: `lib/services/update_service.dart` (extendido), `lib/screens/login_screen.dart` (gate post-login), `lib/screens/configuracion_screen.dart` (usa pre-download), `lib/screens/assistant_screen.dart` (HeroIcon + CronosBadge), `lib/widgets/cronos_info_sheet.dart`, `pubspec.yaml` (assets + flutter_launcher_icons config), `android/app/src/main/res/mipmap-*/ic_launcher.png` (5 densidades regeneradas), `android/app/src/main/res/values/colors.xml` (nuevo, color de fondo del adaptive icon).

## v3.6.0 — Cronos quick actions, logging y robustez

- **Quick actions** en bienvenida: 6 chips fijos (Pendientes hoy/mañana/semana, Vencidas, Próxima tarea, Visitas hoy) que bypasean al LLM con queries directas (<300ms).
- **Historial truncado** a últimos 10 mensajes al armar request al LLM.
- **`max_tokens` 1500** (era 500) para evitar JSON cortado con multi-acción.
- **Fuzzy match normalizado** (sin tildes, sin signos) — soluciona Whisper con acentos.
- **Auto-completar pendiente único**: card con border verde + "Marcar como hecha" cuando filtrar por cliente devuelve 1 ítem.
- **Logging estructurado** en `cronos_logs` (Supabase) — fire-and-forget. Permite iterar el prompt con datos reales de uso.
- Tabla nueva: `cronos_logs` (id, vendedor, msg, raw, mensaje, count, parse_ok, latencia, modelo, created_at) + 2 índices.

---

## Qué compila y qué no

- ✅ `flutter build apk --release` funciona end-to-end (~55 MB)
- ✅ `flutter analyze --no-fatal-infos` limpio (solo warnings menores de `withOpacity` deprecated que son noise)
- ✅ SQL migrations en `scripts/` corrieron todas en Supabase

## Último ciclo de trabajo (último release → hoy)

El release v3.5.1 agrupa varios commits que venían acumulándose:

1. **Offline-first cache de clientes** (9cead88) — `ClientesCache`, banner Sin VPN, shimmer en skeletons del scorecard, indicador "actualizado hace X" en Clientes tab.

2. **Campos DB para reporting** (0a59ca2) — migración que agrega `actividades_cliente.updated_at` (con trigger auto-update), `visitas.precision_m` (accuracy GPS), `visitas.vinculada_actividad_id` (FK a actividades).

3. **UX visita↔actividad explícita** (0c9868e) — el auto-cierre silencioso de actividad agendada cuando se registraba una visita GPS se convirtió en pregunta visual con 2 botones. Ahora el vendedor decide.

4. **Fix crítico de notificaciones zombies** (d96c0b8) — dos bugs:
   - Cancelación dispersa: solo 1 de 5 caminos cancelaba la notif
   - ID random: notif se programaba con `DateTime.now() % 100000`, se intentaba cancelar con `actividad.id` → nunca matcheaba
   Fix arquitectónico: todo el lifecycle en `ActividadesService`.

5. **DataEvents broadcaster + timezone + logging** (5ac872a) — event bus global para refrescar badges en vivo, `SET TIME ZONE 'America/Argentina/Buenos_Aires'` al conectar PG, `debugPrint` en catchs silenciosos.

## Bugs abiertos conocidos

- **Key OpenAI embebida en APK** (prioridad alta, ver proxy pendiente)
- **Google Calendar OAuth incompleto** — proyecto creado, falta agregar test users (mails de vendedores reales)
- **No hay soft-delete** de actividades
- **No hay Push FCM** desde servidor (bloque J pendiente)
- **Notifs con acciones rápidas** (Posponer/Completar desde panel Android) — pendiente técnico documentado

## Deudas técnicas menores

- `shared_preferences` agregado como dep pero sin entrada explícita (lo usa `clientes_cache` vía dependencia transitiva)
- Algunos `catch (_)` quedan en módulos que no se tocaron en la auditoría
- `withOpacity` deprecated en varios widgets, no bloquea pero sería bueno migrar a `withValues`

## Qué estábamos haciendo

**Preparación para compact del chat.** Se ejecutó el plan en `C:\Users\clientes\.claude\plans\graceful-imagining-rivest.md`:

1. ✅ Release v3.5.1 publicado
2. ✅ Plan maestro HTML actualizado
3. ✅ `CLAUDE.md` reescrito
4. ✅ `docs/ESTADO_ACTUAL.md` creado *(renombrado a `STATUS.md` en 2026-05-07)*
5. ✅ `docs/ARQUITECTURA.md` creado *(renombrado a `ARCHITECTURE.md` en 2026-05-07)*
6. ✅ `docs/WORKFLOW.md` creado
7. ✅ `docs/POST_COMPACT_PROMPT.md` creado
8. ✅ Memorias de Claude actualizadas

Después del compact, el user va a usar el prompt en `docs/POST_COMPACT_PROMPT.md` para re-orientar a la nueva instancia.

## Próximos pasos recomendados (orden sugerido)

| # | Tarea | Prioridad | Esfuerzo |
|---|---|---|---|
| 1 | Proxy OpenAI key → Supabase Edge Functions | 🔴 Alta | 1 día |
| 2 | Notificaciones con acciones rápidas (Posponer/Completar desde panel) | 🟡 Media | ~80 LOC |
| 3 | Finalizar OAuth Google Calendar (agregar test users) | 🟡 Media | 5 min cuando tengamos mails |
| 4 | Bloque C — Embudo CRM de Prospectos | 🔴 Alta | Grande |
| 5 | Bloque F — Matriz de Potencial | 🔴 Alta | Medio |

## Quién usa la app

- ~10 vendedores de una empresa argentina de productos químicos / pinturas
- Idioma: español argentino coloquial
- Uso principal: Cronos por voz (Whisper) mientras están en movimiento
- Frecuencia: varias veces al día, casi siempre fuera de la oficina (sin VPN hasta que volvían)

## Cómo se prueba un cambio

1. Hacer el cambio
2. `flutter analyze --no-fatal-infos` → limpio
3. `flutter build apk --release` → compila
4. Opcional: instalar el APK en un device de prueba y validar el flujo
5. Commit + push
6. Tag + GitHub release (ver `docs/WORKFLOW.md`)
