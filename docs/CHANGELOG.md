# Changelog — Hermes Mobile

> Registro cronológico de qué se hizo en cada sesión/release significativa.
> Más granular que el timeline del `master-plan.html` (que es por release),
> más estructurado que `git log` (entradas semánticas con contexto).

## Formato

```markdown
## [YYYY-MM-DD] — Título corto
**Versión publicada (si aplica):** vX.Y.Z
**Trabajo:**
- Bullet describiendo qué se hizo
- Bullet 2
**Decisiones:** ADR-NNN, ADR-MMM (si se tomó alguna)
**Bloqueado por:** descripción (si aplica)
**Próximo paso:** qué sigue al retomar
```

---

## [2026-05-15] — v3.9.3 — Permiso scorecard_drilldown
**Versión publicada:** v3.9.3
**Trabajo:**
- Nueva key `mobile.action.scorecard_drilldown` registrada en `permisos_catalog` (grupo Acciones, orden 260, default false).
- `scorecard_tab.dart`: el `onTap` del `MetricCard` ahora respeta `Session.current.can('mobile.action.scorecard_drilldown')`. Si no, la card no es clickeable (sin animación de tap).
- Primera key agregada después del rollout v3.9 — sirve de plantilla para futuras keys.

---

## [2026-05-15] — Hotfix v3.9.2 (COALESCE text/jsonb)
**Versión publicada:** v3.9.2
**Trabajo:**
- **Fix**: la query con `COALESCE(r.permisos, '{}'::jsonb)` fallaba con `42804: COALESCE types text and jsonb cannot be matched` cuando la columna `roles.permisos` era `text` en lugar de `jsonb`. Hermes Desktop al actualizar roles está dejando la columna como `text` con un string JSON adentro.
- **Solución agnóstica**: cast a text en la query (`r.permisos::text`). Funciona con ambos tipos: si es text, no-op; si es jsonb, serializa a string. El cliente Dart sigue haciendo `jsonDecode` del String.
- Pubspec: 3.9.1+42 → 3.9.2+43.
**Próximo paso:** activar `min_version_required = '3.9.2'`.

---

## [2026-05-15] — Hotfix v3.9.1 (jsonb parsing + force update pre-login)
**Versión publicada:** v3.9.1
**Trabajo:**
- **Fix crítico**: el package `postgres` de Dart devuelve `jsonb` como `String`, no como `Map`. `pg_service.verifyUser` asumía Map → `permisos` quedaba vacío → gate `mobile.access` rechazaba a TODOS los usuarios. Ahora hace `jsonDecode` si llega como String (con fallback a Map por si un driver futuro cambia el comportamiento). Detectado por el user al probar v3.9.0 en device.
- **Force update pre-login**: el check de `min_version_required` se movió al `initState` de `LoginScreen` (antes era post-login). Si la versión local está bloqueada, se navega a `ForceUpdateScreen` sin permitir intento de login. Esto cubre el caso donde el flujo de login está roto en una versión y necesitamos forzar el upgrade igual.
- **Splash mínimo** mientras se chequea force update (CircularProgressIndicator).
- El check post-login en `_navigateAfterLogin` queda como defensa en profundidad por si la app está abierta cuando se sube `min_version_required`.
**Próximo paso:** activar `min_version_required = '3.9.1'` apenas el APK se publique en GitHub. Cualquier device con v3.9.0 va a ver el prompt de upgrade al próximo abrir.

---

## [2026-05-15] — Roles + permisos JSONB (v3.9.0)
**Versión publicada:** v3.9.0
**Trabajo:**
- Edge Function `auth-token` ahora lee `vendedor_nombre` de DB (Opción A — single source of truth). Permite que el username y el vendedor_nombre sean distintos (ej: `Franzo` → `FRANZO SERGIO`).
- `PgService.verifyUser` reescrito: devuelve record `(role, vendedorNombre, permisos)` en una sola query con JOIN a `roles` y `COALESCE` de permisos jsonb.
- `Session` extendido con `_permissions` (Set<String>) y helper `can(key)`. `set()` acepta el dict `permisos` y filtra las keys con value true.
- `AuthService.login` aplica 2 gates antes de poblar Session:
  - `permisos['mobile.access'] == true` — sino "Tu rol no tiene acceso a Hermes Mobile".
  - `vendedor_nombre` no nulo (con fallback al username durante transición) — sino "Tu usuario no tiene un vendedor asignado".
- 9 puntos de UI condicionados:
  - **Tabs (4)**: Scorecard / Cronos / Clientes / Acciones, según `mobile.tab_*`.
  - **Actividades**: crear (cliente_detail), completar/reabrir y eliminar (actividad_detail).
  - **Visita**: tile "Registrar visita" en acciones_tab. "Mis visitas" sigue siempre visible (lectura).
  - **Mic Cronos**: `_InputBar` acepta `canVoice`; si false, siempre Send y hint sin mención al micrófono.
  - **Feedback**: card en configuración solo si `mobile.action.dar_feedback`.
  - **Saldo CxC y facturas**: cliente_detail según `mobile.data.*`.
  - **Calendar sync**: configuración solo si `mobile.google_calendar.sync`.
- Smoke test post-deploy verificó que Franzo (username) recibe token con `vendedor_nombre = 'FRANZO SERGIO'`.
**Decisiones:** ADR-008 creado (roles + permisos JSONB con gates de acceso).
**Próximo paso:** validar 6 casos de prueba en device + activar force update a 3.9.0 cuando OK.

---

## [2026-05-07] — Refactor completo del sistema de docs (2 bloques)
**Versión publicada:** ninguna (meta-documentación solamente)

### Bloque 1 (commit `85dbb39`) — Reorganización inicial al modelo de 6 capas
- Auditoría completa contra modelo de 6 capas (identidad, decisiones, estado, sesión, visualización, reglas).
- Decisión: Opción A2 (renombrar in-place + crear faltantes), nombres en inglés, mantener ADRs separados.
- Renombres con `git mv` (preserva historia):
  - `ARQUITECTURA.md` → `ARCHITECTURE.md`
  - `ESTADO_ACTUAL.md` → `STATUS.md`
  - `TAREAS_PENDIENTES.md` → `TODO.md`
  - `PLAN_MAESTRO_HERMES_MOBILE.html` → `master-plan.html`
  - `decisiones/` → `decisions/`
- Archivos creados: `REJECTED.md`, `CHANGELOG.md` (este), `SESSION_HANDOFF.md`.
- ADRs nuevos: ADR-006 (release keystore), ADR-007 (auth via vendedor_tokens).
- ARCHITECTURE.md §10 actualizado para reflejar que la OpenAI key ya no se compila al APK (v3.8.0); §11 nuevo formaliza el patrón de proxy via Edge Functions.
- README.md (raíz) reescrito con identidad real del proyecto.

### Bloque 2 (commit `800e21e`) — HTML como dashboard maestro completo
- HTML §19 Pendientes Técnicos: reescrito como **espejo completo** de TODO.md (15 cards con criticidad 🔴🟠🟡🟢, no más resumen).
- HTML §3.0 Panorámica de bloques: tabla nueva al inicio de §3, espejo de STATUS.md (19 bloques).
- HTML §23 Decisiones Arquitectónicas: sección nueva con todos los ADRs (título + razón corta + link a archivo full).
- 5 comentarios HTML invisibles `<!-- Source of truth: -->` en §2, §3, §4, §19, §23.
- Nota al pie del HTML explicando rol de dashboard autocontenido (caja oscura azul-violeta).
- CLAUDE.md sección "El Plan Maestro HTML" reescrita como REGLA ABSOLUTA con tabla "cuando cambia X → actualizar Y".
- CLAUDE.md Proceso 6 (Compact del chat) ampliado con Pre-Compact Checklist completo de 7 pasos. Paso 6 incluye verificación obligatoria del HTML contra todos los markdowns relevantes.
- Fixes de paths rotos en ADR-002 y ADR-005 (TAREAS_PENDIENTES.md → TODO.md, fix de path roto, no cambio de decisión).
- Nota arriba en `historico/PLAN_PROXY_OPENAI.md` con mapeo de equivalencias de paths.
- 13 checks de validación post-implementación, todos pasando. Evidencia concreta en 5 puntos presentada al user antes del push.

**Decisiones:** ADR-006, ADR-007 creados (en Bloque 1).
**Próximo paso:** activar force update min_version=3.8.0 cuando user valide v3.8.0 en device.

### Bloque 3 — Discusiones meta + primer simulacro Pre-Compact (commit `bd4dc83`)
- Honestidad explícita sobre qué hago automático vs qué requiere disparador del user.
- 4 capas de defensa identificadas: CLAUDE.md autoload, SESSION_HANDOFF, POST_COMPACT_PROMPT, memoria local.
- 2 reflejos recomendados al user: "cerrá sesión" antes del compact + pegar POST_COMPACT_PROMPT al iniciar sesión nueva.
- **Primer simulacro real del Pre-Compact Checklist ejecutado.** El Paso 6 de verificación HTML detectó 6 inconsistencias que solo conteos no veían:
  1. "Última versión: v3.5.1" hardcodeado en HTML
  2. "Paquetes Flutter instalados (v3.5.1)"
  3. Stats panel "40 releases" vs git con 39 tags
  4. "CRIT-3 Migrar credenciales DB" vs TODO.md "de DB"
  5. Diagrama ASCII "Hermes Mobile v3.5"
  6. TOC "Historial v1.0 → v3.5"
  Todos fixeados en el commit. Conclusión: la verificación item-por-item con `diff` (no solo conteos) es necesaria.

### Bloque 4 — Extracción del protocolo a archivo dedicado (commit `0dd6bbc`)
- `docs/COMPACTION_PROTOCOL.md` NUEVO (215 líneas) con todo el Proceso 6 movido desde CLAUDE.md.
- CLAUDE.md aliviado de 486 → 405 líneas (−81 líneas), Proceso 6 reemplazado por sección corta de 22 líneas con resumen + link al archivo dedicado.
- **Alineación con P3 y P4** de los 4 proyectos del sistema: protocolo en archivo dedicado en todos.
- Convención de nombre con underscore (`COMPACTION_PROTOCOL.md`) coherente con `SESSION_HANDOFF.md` y `POST_COMPACT_PROMPT.md`.
- Aprovechado para enriquecer el protocolo con:
  - Marco introductorio con disparadores
  - Sección de queries bash listas para verificación item-por-item del HTML
  - Sección "Lecciones aprendidas" documentando los 6 fallos del primer simulacro
  - Sección "Cómo se mantiene este archivo"

### Bloque 5 — Segundo simulacro Pre-Compact (esta misma entrada)
- Ejecución del Pre-Compact Checklist siguiendo el protocolo recién extraído.
- Verificación HTML item-por-item: 19 bloques, 15 pendientes, 7 ADRs — todos consistentes con markdowns.
- SESSION_HANDOFF, CHANGELOG y TODO regenerados con estado de cierre.

## [2026-05-06] — Proxy OpenAI server-side (v3.8.0)
**Versión publicada:** v3.8.0
**Trabajo:**
- Setup Supabase CLI con Personal Access Token del user.
- Migración SQL: tablas `vendedor_tokens` + `uso_llm` con RLS habilitado.
- 3 Edge Functions Deno deployadas: `auth-token`, `cronos-chat`, `cronos-transcribe`.
- Helpers compartidos en `_shared/auth.ts` (validación token, rate limit, logUso).
- Cliente Flutter migrado: `auth_token_service.dart` (nuevo), `assistant_service.dart` y `whisper_service.dart` apuntan al proxy.
- `constants.dart`: removida `openaiApiKey`, agregado `supabaseFunctionsUrl`.
- Verificación: `strings app-release.apk | grep "sk-proj"` → 0 resultados.
- Smoke test e2e completo: cronos-chat funciona, log en `uso_llm` verificado.
- Fix de precisión: `costo_usd_estimado NUMERIC(10,5) → NUMERIC(10,7)`.
- Force update **NO** activado (esperando validación en device del user).
**Decisiones:** sigue patrón establecido en ADR-005 (postergar CRIT-3 que es DB, atacar CRIT-2 que es OpenAI).
**Próximo paso:** user valida v3.8.0 en device → activar force update → 3-5 días después rotar key vieja en OpenAI.

## [2026-05-06 (sesión previa)] — Security hardening (v3.7.3)
**Versión publicada:** v3.7.3
**Trabajo:**
- Release keystore propio RSA 2048 generado (`keystore/hermes-release.jks`, gitignored).
- `build.gradle.kts` configurado para firmar release con keystore propio (fallback debug si no existe `key.properties`).
- RLS habilitado en `app_config` y `cronos_logs`.
- `network_security_config.xml` declarado: solo CAs del sistema, rechaza user-installed certs.
- Migración del rollout: APKs viejos firmados con clave debug → vendedores tienen que desinstalar+reinstalar v3.7.3 una sola vez.
**Decisiones:** ADR-001 a ADR-005 creados consolidando decisiones tomadas hasta el momento.
**Próximo paso:** ejecutar plan del proxy OpenAI (PLAN_PROXY_OPENAI.md).

## [Sesiones anteriores]

Para versiones < v3.7.3 ver el timeline completo en
[docs/master-plan.html §2](master-plan.html). Cada release tiene su entry
con descripción narrativa.

---

## Cómo se mantiene este archivo

**Agregar entrada nueva cuando:**
- Se publica un release (versión bump + tag + GitHub release con APK)
- Una sesión incluye trabajo significativo aunque no haya release (refactor de docs, decisiones tomadas, planes nuevos)

**No agregar:**
- Sesiones de chat que no produjeron cambios
- Cambios menores tipo typo fix (van directo al commit, no acá)

**Convenciones:**
- Una entrada por día (si hay múltiples sesiones del mismo día, consolidar)
- Más nuevo arriba
- Si hubo release: mencionar versión en el header
- Decisiones siempre referencian ADR-NNN, no se duplica el contenido
