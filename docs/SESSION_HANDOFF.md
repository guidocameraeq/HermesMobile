# Session Handoff

> **"Dónde quedamos hoy y qué sigue mañana."**
>
> Este archivo se **regenera completo** al cierre de cada sesión (antes de
> `/compact` o cuando el user dice "cerrá sesión"). Pensado para que la
> próxima sesión arranque sabiendo el estado real, sin depender del historial
> del chat (que se pierde con el compact).
>
> **Diferencia con `POST_COMPACT_PROMPT.md`:**
> - `POST_COMPACT_PROMPT.md` = lo que el **user pega** al inicio de una sesión nueva.
> - `SESSION_HANDOFF.md` = lo que **Claude escribe** al cierre de la sesión anterior.

**Última actualización:** 2026-05-07
**Sesión cerrada por:** Claude (auto al regenerar este archivo)

---

## 🎯 Estado actual

Hermes Mobile v3.8.0 publicado en GitHub Releases. La OpenAI API key ya no se compila al APK (CRIT-2 resuelto vía Supabase Edge Functions). El user tiene v3.8.0 instalada en su device de prueba (descargó el APK pero todavía no completó la validación de Cronos chat + voz). El force update a v3.8.0 está **listo para activar** pero esperamos la validación del user en device antes de empujarlo a todos los vendedores.

En esta sesión se reorganizó completo el sistema de documentación contra un modelo de 6 capas (identidad, decisiones, estado, sesión, visualización, reglas). Renombres en inglés, ADRs separados, archivos faltantes creados.

## ✅ Lo que se hizo en esta sesión (2026-05-07)

- Auditoría completa del sistema de documentación contra modelo de 6 capas
- Reorganización de archivos:
  - `ARQUITECTURA.md` → `ARCHITECTURE.md`
  - `ESTADO_ACTUAL.md` → `STATUS.md`
  - `TAREAS_PENDIENTES.md` → `TODO.md`
  - `PLAN_MAESTRO_HERMES_MOBILE.html` → `master-plan.html`
  - `decisiones/` → `decisions/`
- 3 archivos nuevos: `REJECTED.md`, `CHANGELOG.md`, `SESSION_HANDOFF.md` (este)
- 2 ADRs nuevos: ADR-006 (release keystore), ADR-007 (auth vía vendedor_tokens)
- Inconsistencia resuelta: ARCHITECTURE.md §10 actualizado (key fuera del APK)
- Reglas explícitas en CLAUDE.md sobre única fuente de verdad de pendientes (TODO.md)
- README.md raíz reescrito con identidad real

## ⏸️ Lo que quedó en curso

Nada en curso técnico-funcional. El refactor de docs queda **completo en este commit**. Esperando luz verde del user para:

1. Activar force update min_version=3.8.0
2. Rotar la OpenAI key vieja (3-5 días después del rollout)

## 🚧 Próximo paso al retomar

**Acción concreta:** activar force update con la query:
```sql
UPDATE app_config SET value='3.8.0', updated_at=NOW()
WHERE key='min_version_required';
```

Pre-requisito: el user confirma que probó Cronos chat + Cronos voz en su device con v3.8.0 instalada y todo funciona normal.

## ⚠️ Bloqueado por

User pendiente de validar v3.8.0 en device de prueba (Cronos chat + voz).

## 📂 Archivos tocados en esta sesión

```
Renombres (git mv):
  docs/ARQUITECTURA.md → docs/ARCHITECTURE.md
  docs/ESTADO_ACTUAL.md → docs/STATUS.md
  docs/TAREAS_PENDIENTES.md → docs/TODO.md
  docs/PLAN_MAESTRO_HERMES_MOBILE.html → docs/master-plan.html
  docs/decisiones/ → docs/decisions/

Nuevos:
  docs/REJECTED.md
  docs/CHANGELOG.md
  docs/SESSION_HANDOFF.md
  docs/decisions/ADR-006-release-keystore-propio.md
  docs/decisions/ADR-007-auth-via-vendedor-tokens.md

Modificados:
  CLAUDE.md (paths nuevos, nota POST_COMPACT vs SESSION_HANDOFF, regla TODO única fuente)
  README.md (reescrito con identidad real)
  docs/ARCHITECTURE.md (§10 actualizada para v3.8.0)
  docs/STATUS.md (tabla explícita de bloques agregada)
  docs/master-plan.html (referencias a TODO.md en lugar de duplicar lista)
  docs/decisions/README.md (índice actualizado con ADR-006 y ADR-007)
  docs/POST_COMPACT_PROMPT.md (paths nuevos)
```

## 💡 Contexto importante que no quedó en otros docs

- El user aprobó la rotación de la key vieja después del rollout (no inmediato), para que vendedores con APKs viejos no queden sin Cronos durante la ventana de actualización.
- El cap de OpenAI son $400/mes y está compartido con otros proyectos del workspace del user, por eso es importante el tracking granular en `uso_llm` (saber cuánto consume Hermes específicamente).
- La función `cronos-transcribe` no se probó end-to-end por falta de audio real, pero la estructura es idéntica a `cronos-chat` (helpers compartidos) y responde correctamente a auth inválida (401).
- Decisión de F.1: el user eligió Opción A2 (pragmática) en vez de A1 (literal) porque el contenido actual de `docs/` no es legacy real — fue refactorizado hace pocas horas y está alineado.

---

## Cómo se regenera este archivo

Sigue el checklist de pre-compactación documentado en CLAUDE.md sección "Pre-compact checklist". El proceso es:

1. Leer este archivo (versión anterior) para saber qué decir en "Lo que quedó en curso"
2. Sobrescribir completo con el estado nuevo
3. Mover lo de "En curso" actual a la sección "Lo que se hizo" si se completó
4. Actualizar timestamp arriba
5. Devolver al user un resumen con la lista de archivos tocados
