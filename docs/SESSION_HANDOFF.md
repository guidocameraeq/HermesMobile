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

**Última actualización:** 2026-05-07 (cierre de sesión)
**Sesión cerrada por:** Claude (Pre-Compact Checklist ejecutado)

---

## 🎯 Estado actual

Hermes Mobile **v3.8.0** sigue siendo la versión vigente. Ningún cambio de código en la app esta sesión — todo el trabajo fue de meta-documentación.

El sistema de documentación quedó **reorganizado completo** según modelo de 6 capas con el HTML como dashboard maestro autocontenido (no más vitrina con links). 13 checks de validación pasaron, evidencia concreta presentada al user, commits pusheados.

El force update a v3.8.0 sigue **sin activar**, esperando que el user valide Cronos chat + voz en su device de prueba con la app v3.8.0 ya instalada.

## ✅ Lo que se hizo en esta sesión (2026-05-07)

### Bloque 1 — Refactor inicial del sistema de docs (commits anteriores en la sesión)
- Auditoría inicial contra modelo de 6 capas (Identidad, Decisiones, Estado, Sesión, Visualización, Reglas)
- Renombres con `git mv`:
  - `ARQUITECTURA.md → ARCHITECTURE.md`
  - `ESTADO_ACTUAL.md → STATUS.md`
  - `TAREAS_PENDIENTES.md → TODO.md`
  - `PLAN_MAESTRO_HERMES_MOBILE.html → master-plan.html`
  - `decisiones/ → decisions/`
- Archivos nuevos: `REJECTED.md`, `CHANGELOG.md`, `SESSION_HANDOFF.md`
- ADRs nuevos: `ADR-006-release-keystore-propio.md`, `ADR-007-auth-via-vendedor-tokens.md`
- ARCHITECTURE.md §10 actualizado (key fuera del APK) + §11 nuevo (auth via vendedor_tokens + Edge Functions proxy)
- README.md raíz reescrito desde el default de `flutter create`

### Bloque 2 — Auditoría profunda + HTML como dashboard maestro (commit 800e21e)
- HTML §19 Pendientes Técnicos: reescrito como **espejo completo** de TODO.md (15 cards con criticidad 🔴🟠🟡🟢, no más resumen)
- HTML §3.0 Panorámica de bloques: tabla nueva al inicio de §3, espejo de STATUS.md (19 bloques)
- HTML §23 Decisiones Arquitectónicas: sección nueva con todos los ADRs (título + razón corta + link)
- 5 comentarios HTML invisibles `<!-- Source of truth: -->` en §2, §3, §4, §19, §23
- Nota al pie del HTML explicando rol de dashboard autocontenido
- CLAUDE.md sección "El Plan Maestro HTML" reescrita como REGLA ABSOLUTA con tabla "cuando cambia X → actualizar Y"
- CLAUDE.md Proceso 6 (Compact) ampliado con Pre-Compact Checklist completo de 7 pasos
- 13 checks de validación post-implementación, todos pasando
- Evidencia concreta presentada en 5 puntos antes del push final

### Bloque 3 — Discusiones meta sobre el sistema
- Honestidad sobre qué hago automático vs qué requiere disparador del user
- 4 capas de defensa identificadas (CLAUDE.md autoload, SESSION_HANDOFF, POST_COMPACT_PROMPT, memoria local)
- 2 reflejos recomendados al user: "cerrá sesión" antes del compact + pegar POST_COMPACT_PROMPT al iniciar sesión nueva
- Lista resumen de pendientes y bloques entregada al user

## ⏸️ Lo que quedó en curso

Nada técnico-funcional en curso. Esta sesión cerró completa el trabajo de meta-docs.

El **simulacro de Pre-Compact Checklist** (este mismo flujo) está en ejecución mientras se escribe este archivo — al terminarlo, se entrega al user el resumen + el prompt post-compact.

## 🚧 Próximo paso al retomar

**Acción concreta de máxima prioridad** (🔴 Urgente en TODO.md):

1. **Confirmar con el user** si probó Cronos chat + voz en su device con v3.8.0 ya instalada.
2. Si dice OK → ejecutar:
   ```sql
   UPDATE app_config SET value='3.8.0', updated_at=NOW()
   WHERE key='min_version_required';
   ```
3. Eso activa el force update para todos los vendedores en versiones < 3.8.0.

**Acción operativa del user** que sigue pendiente:
- Actualizar SHA-1 en Google Cloud Console (OAuth Calendar Android) al nuevo `73:9D:EE:58:75:E6:18:B4:3D:6C:DA:49:3B:B7:3C:B0:C9:83:F7:0F`. Hasta que se haga, el botón "Conectar con Google Calendar" falla.

## ⚠️ Bloqueado por

User pendiente de validar v3.8.0 en device de prueba (Cronos chat + voz funcionando contra el proxy).

## 📂 Archivos tocados en esta sesión

```
COMMITS:
  85dbb39 — docs: align documentation system to 6-layer model
            (refactor inicial: renombres + archivos nuevos + ADRs)
  800e21e — docs: align documentation system to 6-layer model
            (HTML como dashboard maestro completo + checklist pre-compact)

RENOMBRES (git mv, preservan historia):
  docs/ARQUITECTURA.md         → docs/ARCHITECTURE.md
  docs/ESTADO_ACTUAL.md        → docs/STATUS.md
  docs/TAREAS_PENDIENTES.md    → docs/TODO.md
  docs/PLAN_MAESTRO_HERMES_MOBILE.html → docs/master-plan.html
  docs/decisiones/             → docs/decisions/

NUEVOS:
  docs/REJECTED.md
  docs/CHANGELOG.md
  docs/SESSION_HANDOFF.md (este archivo)
  docs/decisions/ADR-006-release-keystore-propio.md
  docs/decisions/ADR-007-auth-via-vendedor-tokens.md

MODIFICADOS:
  CLAUDE.md (mapa de docs + 6 procesos + regla absoluta del HTML +
             pre-compact checklist completo + nota POST_COMPACT vs HANDOFF)
  README.md (reescrito completo con identidad real)
  docs/ARCHITECTURE.md (§10 actualizada para v3.8.0 + §11 nuevo)
  docs/STATUS.md (tabla de bloques + nota histórica con renombres)
  docs/TODO.md (referencia a master-plan.html actualizada)
  docs/master-plan.html (§3.0 panorámica + §19 espejo TODO + §23 ADRs +
                         5 comentarios source-of-truth + nota al pie)
  docs/POST_COMPACT_PROMPT.md (orden de lectura ampliado a 11 archivos)
  docs/decisions/README.md (índice con ADR-006 + ADR-007)
  docs/decisions/ADR-002-sha256-sin-salt.md (fix path: TAREAS_PENDIENTES → TODO)
  docs/decisions/ADR-005-postergar-crit3-db-creds.md (fix path idem)
  docs/historico/PLAN_PROXY_OPENAI.md (nota arriba con mapeo de paths viejos)
```

## 💡 Contexto importante que no quedó en otros docs

- **El user aceptó explícitamente el trabajo doble** de mantener info en markdown + HTML, a cambio de la experiencia visual unificada del dashboard. Esto está documentado en CLAUDE.md sección "El Plan Maestro HTML" como regla absoluta.
- **El user me pidió que sea honesto sobre limitaciones del sistema** y le entregué un análisis sin endulzar: 95% confianza en releases formales, 70-80% en cambios menores, ~70% en detección automática de "cosas que necesitan ADR" mencionadas casualmente en chat.
- **Los 2 reflejos clave del user para mantener el sistema:** decirme "cerrá sesión" antes del compact + pegar POST_COMPACT_PROMPT al iniciar sesión nueva.
- **Decisión de F.1 anterior (sesión previa, ya documentada):** el user eligió Opción A2 (pragmática) sobre A1 (literal) para evitar destruir trabajo recién hecho moviendo todo a `legacy/`.
- **Excepción explícita aplicada hoy a la regla "ADRs son inmutables":** ADR-002 y ADR-005 fueron editados para fix de path roto (TAREAS_PENDIENTES.md → TODO.md). El cambio NO toca la decisión documentada, solo la referencia rota. Documentado en commit message.
- **Archivos en `docs/historico/` quedaron inmutables:** el `PLAN_PROXY_OPENAI.md` mantiene paths viejos en su contenido original; se agregó una nota al inicio con el mapeo de equivalencias para no confundir.
- **Cap de OpenAI sigue en $400/mes** compartido con otros proyectos del workspace del user. Force update de v3.8.0 + rotación de key vieja cerrarán definitivamente CRIT-2.

---

## Cómo se regenera este archivo

Sigue el checklist documentado en CLAUDE.md sección "Proceso 6 — Compact del chat" → "6.A Pre-compact checklist". El proceso es:

1. Leer este archivo (versión anterior) para saber qué decir en "Lo que quedó en curso"
2. Sobrescribir completo con el estado nuevo
3. Mover lo de "En curso" actual a la sección "Lo que se hizo" si se completó
4. Actualizar timestamp arriba
5. Devolver al user un resumen con la lista de archivos tocados
