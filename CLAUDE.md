# Hermes Mobile — CLAUDE.md

> Archivo de orientación para Claude. Mantenelo alineado con el código. Si hay divergencia, el código manda y actualizás este archivo.

## Estado actual
- **Versión:** v3.5.1+34 (36 releases totales)
- **Repo:** https://github.com/guidocameraeq/HermesMobile (privado)
- **Ruta local:** `D:\SAAS\APK`
- **Entry point:** `lib/main.dart`

## Qué es esta app
App Android Flutter para un equipo comercial de ~10 vendedores en Argentina. Evolucionó de un visor de scorecard (read-only) a una plataforma CRM completa con asistente IA por voz, notificaciones, GPS, sincronización con Google Calendar y login biométrico.

**Relación con Hermes Desktop** (`D:\SAAS\VisorFacturacion`): el desktop es la app de admin (crea métricas, asigna objetivos, gestiona usuarios). El mobile lee los mismos datos y escribe actividades/visitas/prospectos que el desktop después consume.

## Estructura de navegación
- **Bottom nav (4 tabs):** Scorecard · Cronos · Clientes · Acciones
- **Drawer lateral** (hamburguesa top-left): menú completo + acceso a Configuración
- **Avatar top-right:** Configuración (perfil, huella, updates, feedback, logout)

## Stack
| Capa | Tecnología |
|---|---|
| Framework | Flutter / Dart |
| Min SDK | 26 (Android 8+) |
| Java | JDK 17 (`C:\Program Files\Microsoft\jdk-17.0.18.8-hotspot`) |
| DB cloud | Supabase PostgreSQL (sin VPN) |
| DB interna | SQL Server via jTDS (con VPN) |
| LLM | OpenAI GPT-4o-mini |
| STT | OpenAI Whisper |
| Calendar | Google Calendar API (OAuth) |
| Notifs | flutter_local_notifications + timezone |
| Biométrico | local_auth + flutter_secure_storage |
| Audio | record (para Whisper) |
| Cache offline | shared_preferences |

## Servicios (`lib/services/`)

| Service | Rol |
|---|---|
| `auth_service` | Login SHA-256 contra Supabase `usuarios` |
| `pg_service` | Conexión PostgreSQL singleton. Setea timezone AR al abrir. |
| `sql_service` | Conexión SQL Server via jTDS (VPN). |
| `scorecard_service` | Orquestador: Supabase targets + SQL reales |
| `calculator_service` | Motor de métricas (queries parametrizadas) |
| `clientes_service` | Cartera vendor. Offline-first: SQL primero, cache como fallback. |
| `clientes_cache` | Persist cartera en SharedPreferences + timestamp |
| `actividades_service` | **Fuente única de verdad** del lifecycle de actividades (CRUD + notifs + calendar + events) |
| `visitas_service` | Registrar visitas GPS + linkear a actividad agendada si el usuario lo pide |
| `pedidos_service` | Lectura de pedidos del vendor |
| `notification_service` | `flutter_local_notifications` wrapper, tz AR |
| `whisper_service` | Grabación + POST multipart a Whisper API |
| `assistant_service` | Cronos: manda mensajes al LLM, parsea acciones, fuzzy match clientes |
| `prompt_service` | Lee system prompts de Supabase `agent_prompts` con cache 5min + fallback hardcoded |
| `calendar_service` | Google Calendar CRUD de eventos, linkeado via `google_event_id` |
| `biometric_service` | Login con huella + credenciales cifradas |
| `cliente_router` | `open(context, codigo)` abre ficha de cliente desde cualquier lugar |
| `connectivity_service` | Detecta si SQL Server responde (ping rápido) para banner "Sin VPN" |
| `data_events` | **Event bus global** (ValueNotifier). Services notifyXxx() tras write; pantallas se suscriben para refrescar |
| `drilldown_service` | Queries específicas de los drill-downs del scorecard |
| `lineas_service` | Análisis de líneas de producto por cliente |
| `update_service` | Check de updates desde GitHub Releases + descarga/instalación de APK |
| `analytics_service` | Track de uso a Supabase `analytics` |
| `error_logger` | Buffer en memoria de errores recientes (visible en Configuración) |

## Patrones arquitectónicos críticos

### 1. `ActividadesService` es la única fuente de verdad del lifecycle
UI **nunca** programa/cancela notifs, nunca llama Calendar directo, nunca emite eventos. Solo llama al service. El service se encarga de:
- Programar notif con `id = actividad.id real` (no random)
- Sincronizar con Google Calendar si está en modo auto
- Emitir `DataEvents.notifyActividades()`

Razón: antes había 5 caminos para completar actividad y solo 1 cancelaba la notif → notif zombies. Fix arquitectónico: todo centralizado.

### 2. `DataEvents` como event bus global
`ValueNotifier<int>` para `actividades`, `visitas`, `pedidos`. Services incrementan post-write. Pantallas usan `addListener` en initState, `removeListener` en dispose. Ejemplo: Acciones tab escucha los 3 y recarga badges en vivo.

### 3. Offline-first para clientes
`ClientesService.getClientes()` intenta SQL Server con timeout. Si falla → `ClientesCache` (SharedPreferences). Si tampoco hay → throw. UI muestra indicador "actualizado hace X".

### 4. `PromptService` con fallback
Cronos (y futuros agentes) leen su system prompt de Supabase `agent_prompts` con cache 5min. Si Supabase no responde, usa fallback hardcoded. Permite editar prompts en producción sin recompilar.

### 5. `ClienteRouter.open(context, codigo)`
Cualquier lista con nombre de cliente usa este helper → tap abre `ClienteDetailScreen`. Antes había 8 lugares donde el nombre era "dead text". Ahora es universal.

### 6. `PgService` setea timezone AR al conectar
```dart
await conn.execute("SET TIME ZONE 'America/Argentina/Buenos_Aires'");
```
Razón: queries con `CURRENT_DATE` y `::date` deben resolver en hora local del vendor, no UTC del server. Sin esto, una actividad a las 23:00 AR no aparecía en filtro "hoy".

### 7. SQL migrations idempotentes
Todo `scripts/*.sql` usa `CREATE/ALTER ... IF NOT EXISTS` y `ON CONFLICT DO NOTHING`. Se puede correr varias veces sin romper.

## Build

```bash
export JAVA_HOME="/c/Program Files/Microsoft/jdk-17.0.18.8-hotspot"
export ANDROID_HOME="/c/Android"
export PATH="$JAVA_HOME/bin:/c/tools/flutter/bin:$ANDROID_HOME/cmdline-tools/latest/bin:$PATH"
flutter build apk --release
# Output: build/app/outputs/flutter-apk/app-release.apk (~57 MB)
```

## SQL Migrations

Las migraciones viven en `D:\SAAS\APK\scripts\*.sql`. Para correrlas uso el venv de VisorFacturacion (tiene psycopg2):

```bash
export PGHOST='aws-0-us-west-2.pooler.supabase.com' PGPORT=5432 \
       PGDATABASE=postgres PGUSER='postgres.kelipnwleblnpupmlont' \
       PGPASSWORD='hJoG2x1ZCRnLVMCp'
/d/SAAS/VisorFacturacion/venv/Scripts/python.exe \
    $LOCALAPPDATA/Temp/run_migrations.py \
    /d/SAAS/APK/scripts/<archivo>.sql
```

**Sandbox block:** el entorno bloquea writes a prod Supabase. Pasar `dangerouslyDisableSandbox: true` al Bash call solo si el user autoriza explícitamente.

## Credenciales

`lib/config/constants.dart` está en `.gitignore` — **nunca commitear**. Tiene:
- OpenAI API key (GPT + Whisper)
- Supabase credentials
- SQL Server credentials

`lib/config/constants.example.dart` es el template con placeholders para nuevos clones.

⚠️ **Pendiente alta prioridad:** la key de OpenAI está embebida en el APK compilado y es extraíble con `strings app-release.apk | grep "sk-proj"`. Plan: moverla a Supabase Edge Function como proxy. Ver Plan Maestro HTML sección "Proxy API key OpenAI".

## Tablas Supabase (PostgreSQL)

- **Auth / config:** `usuarios`, `roles`
- **Métricas:** `metricas_pool`, `asignaciones`, `cuotas_clientes`, `targets`, `activaciones`
- **CRM mobile:** `visitas` (con `precision_m`, `vinculada_actividad_id`), `actividades_cliente` (con `updated_at`, `google_event_id`)
- **Agentes IA:** `agent_prompts` (Cronos + futuros agentes)
- **Analytics:** `analytics`, `feedback`

## Tablas SQL Server (read-only via VPN)

`fydvtsEstadisticas`, `fydvtsClientesXLinea`, `fydvtsPedidos`, `fydvtsCtasCtes`, `fydgnrArticulos`.

## Convenciones

- **Dart style:** services son clases con métodos estáticos (`Future<T>`). No instanciación.
- **SQL Server:** placeholders `?` estilo JDBC, pasar `List<Object?>` como params.
- **PostgreSQL:** placeholders `@param` estilo `postgres` package.
- **Commits:** `feat: ...` / `fix: ...` / `refactor: ...` / `docs: ...`. Siempre con `Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>`.
- **Errors:** `error_logger` recuerda los últimos 20; visible en Configuración para debug en campo.

## IDE

El IDE NO tiene el SDK de Flutter configurado → los errores de análisis tipo `missing-module` son falsos positivos. Verificar con `flutter analyze`.

## Puntos ciegos conocidos (acumulados)

- **OpenAI key en APK** (prioridad alta — mover a Edge Function)
- **Google Calendar OAuth** — proyecto creado en Google Cloud, falta agregar test users (emails de los vendedores reales)
- **No hay soft-delete** de actividades (DELETE hard hoy)
- **No hay Push FCM** desde servidor (futuro bloque J)
- **Notificaciones acciones rápidas** (Posponer/Completar desde el panel) — pendiente técnico

## 🗺️ Mapa completo de documentación

Esta es la **fuente única de verdad** sobre qué archivo existe, dónde está, y para qué sirve. Si tenés que buscar algo, empezá acá.

> **Modelo de 6 capas (auditoría 2026-05-07):** la documentación está organizada según un modelo arquitectónico que cubre identidad, decisiones, estado, sesión, visualización y reglas. Nombres en inglés (estándar global, mejor reconocimiento por IDEs), contenido en castellano argentino.

### Estructura de carpetas

```
D:\SAAS\APK\
├── CLAUDE.md                        ← Capa 6: reglas para Claude (este archivo)
├── README.md                        ← Capa 1: identidad del repo
└── docs\
    ├── ARCHITECTURE.md              ← Capa 1: patrones arquitectónicos con razón
    ├── DECISIONS.md → carpeta decisions/  ← Capa 2: ADRs separados (mejor que un archivo único)
    ├── REJECTED.md                  ← Capa 2: opciones descartadas con razón
    ├── STATUS.md                    ← Capa 3: snapshot del estado actual + tabla de bloques
    ├── TODO.md                      ← Capa 3: ⭐ ÚNICA FUENTE de tareas pendientes accionables
    ├── CHANGELOG.md                 ← Capa 3: registro cronológico por sesión/release
    ├── SESSION_HANDOFF.md           ← Capa 4: dónde quedamos al cerrar la sesión (Claude lo escribe)
    ├── master-plan.html             ← Capa 5: documento "lindo" para humanos (browser)
    ├── WORKFLOW.md                  ← Procesos operativos (release, signing, migrations)
    ├── POST_COMPACT_PROMPT.md       ← Bloque copy-paste para que el USER pegue al inicio de sesión
    ├── decisions\                   ← ADRs separados (patrón Nygard)
    │   ├── README.md                ← formato y reglas + índice
    │   ├── ADR-001-distribucion-privada.md
    │   ├── ADR-002-sha256-sin-salt.md
    │   ├── ADR-003-sin-ssl-pinning.md
    │   ├── ADR-004-force-update-no-shorebird.md
    │   ├── ADR-005-postergar-crit3-db-creds.md
    │   ├── ADR-006-release-keystore-propio.md
    │   └── ADR-007-auth-via-vendedor-tokens.md
    └── historico\                   ← planes ya ejecutados (referencia, no se actualizan)
        └── PLAN_PROXY_OPENAI.md     ← ejecutado en v3.8.0
```

### ⚠️ Diferencia crítica: POST_COMPACT_PROMPT.md vs SESSION_HANDOFF.md

Estos archivos **se confunden fácilmente** pero son distintos:

| Aspecto | `POST_COMPACT_PROMPT.md` | `SESSION_HANDOFF.md` |
|---|---|---|
| **Quién lo escribe** | Es estático, lo mantenemos cuando cambia el orden de lectura | Lo escribe Claude (yo) al cerrar la sesión |
| **Cuándo se usa** | El user lo copia/pega al INICIO de una sesión nueva | Lo leo yo al inicio para saber dónde quedamos |
| **Contenido** | Lista de archivos a leer, instrucciones para reorientarme | Estado actual + último trabajo + próximo paso concreto |
| **Frecuencia de cambio** | Raro (solo si cambia la estructura de docs) | Cada cierre de sesión (sobrescribir completo) |
| **Es para** | Mí, vía pegado del user | Mí, leído del archivo |

### Memoria local de Claude (fuera del repo)

```
C:\Users\clientes\.claude\projects\d--SAAS\memory\
├── MEMORY.md                        ← índice de memorias (1 línea por archivo)
├── project_hermes_mobile.md         ← stack/servicios/patrones críticos
├── project_hermes_mobile_roadmap.md ← roadmap CRM
└── feedback_*.md                    ← feedback puntual del user
```

Estos se cargan **automáticamente** al inicio de cada sesión nueva (incluyendo post-compact). Son la red de seguridad si todo lo del repo se pierde.

### Tabla de qué archivo modificar para qué

| Si querés... | El archivo es... |
|---|---|
| Saber qué versión está vigente y qué bloques están completos | `docs/STATUS.md` |
| Ver el plan completo del proyecto (gráfico, timeline, secciones) | `docs/master-plan.html` |
| Ver/agregar tareas pendientes operativas (**fuente única**) | `docs/TODO.md` |
| Entender por qué un patrón está implementado así | `docs/ARCHITECTURE.md` |
| Saber cómo hacer release/signing/migrations | `docs/WORKFLOW.md` |
| Ver por qué descartamos una "best practice" estándar | `docs/decisions/ADR-NNN-*.md` |
| Ver la lista de opciones descartadas y por qué | `docs/REJECTED.md` |
| Ver el registro cronológico por sesión/release | `docs/CHANGELOG.md` |
| Saber dónde quedamos al cerrar la sesión anterior | `docs/SESSION_HANDOFF.md` |
| Reorientar Claude tras un compact (lo pega el user) | `docs/POST_COMPACT_PROMPT.md` |
| Encontrar contexto de un plan ya ejecutado | `docs/historico/` |
| Stack técnico, servicios, patrones arquitectónicos | `CLAUDE.md` (este) |

### 🚨 REGLA ABSOLUTA — única fuente de verdad de pendientes

**`docs/TODO.md` es la ÚNICA fuente de verdad para tareas pendientes accionables.**

- ✅ `STATUS.md` puede tener un resumen del estado de bloques (ej: "Bloque C pendiente"). NO duplica lista de tareas.
- ✅ `master-plan.html` §19 muestra cards visuales destacadas. NO duplica la lista — referencia a `TODO.md`.
- ✅ `SESSION_HANDOFF.md` puede mencionar 1-2 tareas relevantes al contexto de cierre. NO es la lista completa.
- ❌ NO crear listas de pendientes en otros archivos. Si encontrás una, consolidala en `TODO.md` y reemplazala por una referencia.

Si hay desfase entre `TODO.md` y otro doc, **`TODO.md` manda**. Actualizar el otro doc para que refleje (o referencie sin duplicar).

---

## 🔄 Procesos estandarizados (REGLAS QUE DEBO SEGUIR)

Estos son procesos **automáticos** que sigo cuando ocurre el disparador correspondiente. No son sugerencias, son obligaciones.

### Proceso 1 — Cada release publicado

**Disparador:** hago `git tag vX.Y.Z` + creo GitHub release con APK adjunto.

**Checklist obligatorio (antes de considerar el release "hecho"):**
1. ✅ `pubspec.yaml` con versión nueva
2. ✅ APK firmado con release keystore (validar con `apksigner verify --print-certs`)
3. ✅ `docs/STATUS.md` con snapshot de la versión nueva
4. ✅ `docs/master-plan.html` actualizado:
   - Header: version-tag + fecha
   - Stats: releases totales (+1), versión actual
   - Timeline: nuevo item con descripción narrativa
   - Footer: versión actual
5. ✅ Si el release completa una tarea de `TODO.md`, moverla a "Completadas recientemente"
6. ✅ Commit con prefijo `docs:` (puede ir en el mismo commit del feat o aparte)
7. ✅ Push tag + release notes en GitHub

### Proceso 2 — Patrón arquitectónico nuevo

**Disparador:** introduzco un patrón reusable que afecta varios archivos (ej: DataEvents, ClienteRouter, RLS pattern, etc).

**Checklist:**
1. ✅ `docs/ARCHITECTURE.md` con sección nueva: contexto, decisión, razón, cómo aplicarlo
2. ✅ `CLAUDE.md` (este archivo) con mención breve en "Patrones arquitectónicos críticos"
3. ✅ Si el patrón es bien crítico (afecta el día a día de cualquier feature futura), también en `project_hermes_mobile.md` (memoria)
4. ✅ Si el patrón cambia la roadmap o cierra una deuda, mencionarlo en plan maestro HTML

### Proceso 3 — Bloque del plan original completado

**Disparador:** terminamos un bloque de letra (C, D, F, G, H, J, etc) o un sub-bloque significativo.

**Checklist:**
1. ✅ Plan maestro HTML: mover de "pendientes" a "completados", actualizar TOC (`pending` → `done`)
2. ✅ `project_hermes_mobile_roadmap.md` (memoria): marcar como completado
3. ✅ `docs/TODO.md`: si tenía tareas asociadas, moverlas a completadas
4. ✅ `docs/STATUS.md`: mencionar el bloque en el resumen de la versión

### Proceso 4 — Tarea/idea/deuda técnica nueva

**Disparador:** el user menciona una mejora futura, o yo encuentro algo que vale la pena guardar.

**Checklist:**
1. ✅ `docs/TODO.md` con la tarea categorizada por criticidad (🔴/🟠/🟡/🟢) — **siempre acá primero**
2. ✅ Si es plan grande (días de trabajo), crear archivo dedicado en `docs/` (ej: `PLAN_FEATURE_X.md`)
3. ✅ Plan maestro HTML §19 Pendientes Técnicos: agregar `<div class="card">` con prioridad y esfuerzo
4. ✅ Cuando se ejecuta el plan grande, **moverlo a `docs/historico/`** después de release

### Proceso 5 — Decisión técnica con trade-offs no obvios

**Disparador:** descartamos una "best practice" estándar, o elegimos entre varias opciones técnicas.

**Checklist:**
1. ✅ Crear `docs/decisions/ADR-NNN-titulo-corto.md` con formato estándar (ver `docs/decisions/README.md`)
2. ✅ Actualizar el índice en `docs/decisions/README.md`
3. ✅ Numeración secuencial sin saltos
4. ✅ ADRs son **inmutables**: si la decisión cambia, crear ADR nuevo que reemplace, no editar el viejo

### Proceso 6 — Compact del chat

**Disparador:** el user dice "voy a comprimir" / "cerrá sesión" / "compact ya" / `/compact`.

#### 6.A — Pre-compact checklist (lo ejecuto YO antes de que el user haga /compact)

```
═══════════════════════════════════════════════════════
PRE-COMPACT CHECKLIST — Hermes Mobile
═══════════════════════════════════════════════════════

[ ] 1. Releer para verificar consistencia:
      - docs/STATUS.md (lo que está en curso)
      - docs/TODO.md (qué quedó pendiente esta sesión)
      - docs/CHANGELOG.md (entrada del día, si existe)
      - docs/SESSION_HANDOFF.md (versión anterior antes de sobrescribir)

[ ] 2. Actualizar OBLIGATORIO los markdowns:
      [ ] docs/SESSION_HANDOFF.md — sobrescribir completo:
          • Estado actual
          • Lo que se hizo
          • Lo que quedó en curso
          • Próximo paso CONCRETO
          • Bloqueos (si hay)
          • Archivos tocados
          • Contexto importante del chat

      [ ] docs/CHANGELOG.md — nueva entrada al tope con fecha de hoy:
          • Versión publicada (si aplica)
          • Trabajo (bullets)
          • Decisiones (ADRs creados)
          • Próximo paso

      [ ] docs/TODO.md:
          • Mover tareas completadas a sección "Completadas recientemente"
          • Agregar tareas nuevas surgidas

[ ] 3. Si hubo decisiones técnicas hoy:
      [ ] Crear ADR-NNN en docs/decisions/ (numeración sin saltos)
      [ ] Actualizar índice en docs/decisions/README.md

[ ] 4. Si se descartaron opciones hoy:
      [ ] Agregar entradas en docs/REJECTED.md

[ ] 5. Si cambió arquitectura:
      [ ] Actualizar docs/ARCHITECTURE.md

[ ] 6. ⭐ VERIFICAR Y REGENERAR docs/master-plan.html
      Confirmar que el HTML refleja el estado actual COMPLETO de:
      [ ] docs/STATUS.md (todos los bloques en §3.0)
      [ ] docs/TODO.md (todos los pendientes en §19, con criticidades)
      [ ] docs/decisions/ (todas las ADRs en §23, título + razón)
      [ ] docs/CHANGELOG.md (timeline §2 actualizado)
      [ ] header + footer + stats (versión actual, releases totales)

      Si alguna sección del HTML quedó atrás respecto al markdown,
      regenerarla AHORA antes del compact. Markdown manda, HTML refleja.

[ ] 7. Devolver al user resumen estructurado con paths:

═══════════════════════════════════════════════════════
RESUMEN PRE-COMPACT — [fecha]
═══════════════════════════════════════════════════════

Archivos actualizados:
- docs/SESSION_HANDOFF.md ✅
- docs/CHANGELOG.md ✅ (entrada nueva)
- docs/TODO.md ✅ (X tareas movidas)
- docs/decisions/ADR-XXX-*.md ✅ (si aplica)
- docs/REJECTED.md ✅ (si aplica)
- docs/ARCHITECTURE.md ✅ (si aplica)
- docs/master-plan.html ✅ (secciones X, Y, Z regeneradas)

Próximo paso al retomar:
[acción concreta]

Bloqueos pendientes:
[si hay]

Estás listo para /compact.
═══════════════════════════════════════════════════════
```

#### 6.B — Lo que pasa automáticamente

- Las memorias en `C:\Users\clientes\.claude\projects\d--SAAS\memory\` se cargan al iniciar la sesión nueva (no se pierden).

#### 6.C — Lo que tiene que hacer el user

Pegar el contenido de `docs/POST_COMPACT_PROMPT.md` como primer mensaje de la sesión nueva.

#### 6.D — Lo que hago yo en la sesión nueva (post-compact)

1. Leer `docs/SESSION_HANDOFF.md` (dónde quedamos)
2. Leer `docs/STATUS.md` (versión actual + bloques)
3. Leer `docs/TODO.md` (qué está pendiente — única fuente)
4. Leer `CLAUDE.md` (este archivo — stack, patrones, procesos)
5. Leer `docs/ARCHITECTURE.md` (patrones)
6. Leer `docs/WORKFLOW.md` (cómo hacer cosas operativas)
7. Si la conversación va a tocar una decisión postergada, leer `docs/decisions/ADR-NNN-*.md`
8. Si la conversación va a tocar una opción que parecía válida, chequear `docs/REJECTED.md` antes de proponerla
9. Si toco el master-plan.html, abrirlo y revisar la sección a editar siguiendo los comentarios `<!-- Source of truth: -->`

---

## El Plan Maestro HTML es el dashboard maestro autocontenido

`docs/master-plan.html` es **el dashboard del proyecto Hermes Mobile**. El user lo abre en el browser y quiere ver TODO el estado del proyecto sin abrir ningún markdown. Es autocontenido y completo, no es vitrina con links.

### 🚨 REGLA ABSOLUTA — Actualización OBLIGATORIA

**`master-plan.html` debe actualizarse cada vez que cambia uno de estos archivos:**

| Cuando cambia... | Actualizar en HTML | Sección |
|---|---|---|
| `docs/STATUS.md` | Tabla de bloques (§3.0) | §3 Fases Completadas |
| `docs/TODO.md` | Lista completa de pendientes con criticidades | §19 Pendientes Técnicos |
| `docs/decisions/ADR-*.md` (nuevo, modificado, superado) | Tabla de ADRs (título + razón corta) | §23 Decisiones Arquitectónicas |
| `docs/CHANGELOG.md` (nueva entrada) | Timeline item nuevo | §2 Historial de Versiones |
| `docs/ARCHITECTURE.md` (cambio de stack/patrón) | Stack en §4 + posible mención en §22 | §4 Infraestructura |

**El HTML refleja contenido COMPLETO de los markdowns, no resumen.** Es el dashboard que el usuario abre para ver el proyecto entero de un vistazo. Trabajo doble aceptado a cambio de experiencia visual unificada.

### Si hay desfase entre HTML y markdown

**Markdown manda.** Tomar el contenido del markdown como fuente de verdad y propagarlo al HTML. Nunca al revés.

### Cómo identificar qué sección actualizar

Cada sección principal del HTML lleva un **comentario HTML invisible** indicando su fuente de verdad:

```html
<!-- Source of truth: docs/STATUS.md -->
<!-- Sync rule: when STATUS.md changes, mirror full block table here. -->
<h2 id="completado">3. Fases Completadas</h2>
```

Buscar `<!-- Source of truth:` en el HTML para ubicar qué sección refleja qué markdown.

### Qué tiene que reflejar siempre

1. **Header + stats**: badge de versión, número de releases, fecha de última actualización.
2. **Footer**: versión actual.
3. **§2 Timeline**: refleja `CHANGELOG.md` — un item por release publicado.
4. **§3 Tabla panorámica de bloques**: espejo de `STATUS.md`.
5. **§19 Pendientes**: lista completa con criticidades 🔴🟠🟡🟢, refleja `TODO.md`.
6. **§23 Decisiones**: tabla con todos los ADRs (título + razón corta), refleja `decisions/`.
7. **TOC**: cada sección nueva debe estar en el `<div class="toc">`.

### Reglas para editar el HTML

- **Mantener el estilo existente**: usar las clases CSS que ya están definidas (`badge-done`, `badge-pending`, `card done`, `card pending`, `timeline-item done`, `info`, `success`, `highlight`, etc). No inventar clases nuevas a menos que sea para una sección categórica nueva.
- **Validar después de cada cambio**: el archivo es HTML puro renderizable en cualquier browser. Verificar con un parser simple que las etiquetas queden balanceadas.
- **Renumerar cuidadosamente** si insertás secciones nuevas: la numeración (§1, §2, ...) debe quedar consistente en TOC, headers y referencias internas.
- **Preservar `class="page-break"`** en headings importantes para mantener el formato impreso.
- **Las tablas con queries SQL van en `<pre>`** dentro de `<div class="card">` para mantener legibilidad.

### Filosofía

El plan maestro **no es opcional ni decorativo**. El user lo usa como guía operativa diaria. Si algo cambia en los markdowns y no se refleja acá, el dashboard miente. Si surge una decisión importante y no queda asentada acá, el user no la ve. Antes de cerrar cualquier ciclo de trabajo significativo, preguntate: **"¿el dashboard refleja esto en versión completa, no resumida?"**. Si la respuesta es no, actualizalo en el mismo commit.

---

## ⚠️ Anti-patterns a evitar

- ❌ Documentar una decisión solo en el chat (se pierde con el compact)
- ❌ Crear archivos .md sueltos fuera de `docs/` o `docs/decisions/` o `docs/historico/`
- ❌ Editar un ADR ya creado (crear uno nuevo que reemplace)
- ❌ Saltarse el checklist de release porque "es un cambio chico"
- ❌ Mover un plan ejecutado a `docs/historico/` sin antes confirmar que está cerrado
- ❌ Modificar `docs/master-plan.html` con clases CSS inventadas — usar las existentes
