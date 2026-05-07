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

### Bloque 3 — Discusiones meta sobre el sistema (no commits)
- Honestidad explícita sobre qué hago automático vs qué requiere disparador del user.
- 4 capas de defensa identificadas: CLAUDE.md autoload, SESSION_HANDOFF, POST_COMPACT_PROMPT, memoria local.
- 2 reflejos recomendados al user: "cerrá sesión" antes del compact + pegar POST_COMPACT_PROMPT al iniciar sesión nueva.
- Simulacro de Pre-Compact Checklist ejecutado al cierre de la sesión (esta entrada y la regeneración de SESSION_HANDOFF son parte de ese simulacro).

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
