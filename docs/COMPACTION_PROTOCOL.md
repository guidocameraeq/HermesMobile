# Protocolo de compactación — Hermes Mobile

> **Qué es esto:** el protocolo completo que ejecuto antes y después de un
> `/compact` del chat para garantizar continuidad de contexto entre sesiones.
> Vive en archivo dedicado para mantener consistencia con otros proyectos
> (P3, P4) y para alivianar `CLAUDE.md` (que solo guarda un resumen + link).
>
> **Disparadores (frases del user):**
> - "voy a comprimir"
> - "cerrá sesión"
> - "compact ya"
> - `/compact`
>
> **Cuándo se aplica:** sesiones de trabajo significativas que el user
> quiere cerrar antes de comprimir el chat. Sesiones triviales sin cambios
> no requieren ejecutar el protocolo completo (pero el user puede pedirlo
> igual).

---

## 6.A — Pre-compact Checklist (lo ejecuto YO antes de que el user haga /compact)

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

[ ] 7. Devolver al user resumen estructurado con paths.
```

### Verificación item-por-item del HTML (no solo conteos)

El simulacro real del 2026-05-07 demostró que verificar **solo conteos** (X items en markdown = X items en HTML) **no detecta drift de títulos o versiones hardcodeadas**. La verificación correcta del Paso 6 incluye:

```bash
# Diff de títulos TODO.md vs HTML §19
grep -E "^### " docs/TODO.md | grep -v "Mayo|Junio|..." | sed 's/^### //' | sort > /tmp/todo.txt
sed -n '/<h2 id="pendientes-tecnicos"/,/<h2 id="cronos-analytics"/p' docs/master-plan.html | \
  grep -E 'card-header' | sed -E 's/.*card-header">//; s/ <span.*//; s/<\/div>//' | sort > /tmp/html.txt
diff /tmp/todo.txt /tmp/html.txt

# Diff de bloques STATUS.md vs HTML §3.0 (regex que captura nombres con espacios)
sed -n '/^| Bloque /,/^---/p' docs/STATUS.md | grep -E "^\| \*\*" | \
  sed -E 's/^\| \*\*([^*]+)\*\*.*/\1/' | sort > /tmp/sb.txt
sed -n '/<h3>3.0 Panorámica/,/<h3>3.1 Base/p' docs/master-plan.html | \
  grep -oE '<td><strong>[^<]+</strong>' | sed 's|<td><strong>||;s|</strong>||' | sort > /tmp/hb.txt
diff /tmp/sb.txt /tmp/hb.txt

# Versiones hardcodeadas que no deberían estar (sin contexto histórico)
grep -nE "v3\.[5-7]" docs/master-plan.html | grep -vE "timeline-version|tag/v3\."

# Validación HTML estructura
python -c "
from html.parser import HTMLParser
class V(HTMLParser):
    def __init__(self): super().__init__(); self.stack=[]; self.errs=[]
    def handle_starttag(self,t,a):
        if t not in ('br','hr','meta','img','input','link','source','col'): self.stack.append(t)
    def handle_endtag(self,t):
        if not self.stack: self.errs.append(f'close {t}'); return
        if self.stack[-1]!=t: self.errs.append(f'mismatch'); self.stack.pop() if self.stack[-1]==t else 0
        else: self.stack.pop()
v=V()
with open(r'docs/master-plan.html','r',encoding='utf-8') as f: v.feed(f.read())
print('OK' if not v.errs and not v.stack else f'errs={v.errs[:2]}')
"
```

---

## 6.B — Formato del resumen al user (Paso 7 del checklist)

Cuando termino el checklist, devuelvo al user este bloque estructurado:

```
═══════════════════════════════════════════════════════
RESUMEN PRE-COMPACT — [fecha]
═══════════════════════════════════════════════════════

Archivos actualizados:
- docs/SESSION_HANDOFF.md ✅ (sobrescrito completo)
- docs/CHANGELOG.md ✅ (entrada del día)
- docs/TODO.md ✅ (X tareas movidas a Completadas)
- docs/decisions/ADR-XXX-*.md ✅ (si aplica)
- docs/REJECTED.md ✅ (si aplica)
- docs/ARCHITECTURE.md ✅ (si aplica)
- docs/master-plan.html ✅ (secciones X, Y, Z regeneradas)

Verificación HTML ↔ markdowns:
- N bloques STATUS.md = N filas HTML §3.0 ✅
- N pendientes TODO.md = N cards HTML §19 ✅
- N ADRs decisions/ = N referencias HTML §23 ✅
- HTML estructura válida ✅

Versión actual: vX.Y.Z
Último commit: [hash] (pusheado)

Próximo paso al retomar:
→ [acción concreta]

Bloqueos pendientes:
→ [si hay]

⚠️ Hay archivos modificados sin commit. ¿Querés que commitee
   antes del compact, o los dejamos así?

═══════════════════════════════════════════════════════
ESTÁS LISTO PARA /compact
═══════════════════════════════════════════════════════
```

---

## 6.C — Lo que pasa automáticamente durante el `/compact`

- Las memorias en `C:\Users\clientes\.claude\projects\d--SAAS\memory\` se cargan al iniciar la sesión nueva (sobreviven al compact, no se pierden).
- `CLAUDE.md` se carga automáticamente al iniciar la sesión nueva (autoload de Claude Code).

## 6.D — Lo que tiene que hacer el user al iniciar sesión nueva

Pegar el contenido completo de [`docs/POST_COMPACT_PROMPT.md`](POST_COMPACT_PROMPT.md) como **primer mensaje** de la sesión nueva. Eso me dispara la lectura ordenada de los 11 archivos de contexto + me obliga a confirmarte 4 bullets de orientación antes de hacer cualquier cosa.

## 6.E — Lo que hago yo en la sesión nueva (post-compact)

Cuando el user pega el `POST_COMPACT_PROMPT.md`:

1. Leer `docs/SESSION_HANDOFF.md` (dónde quedamos al cierre de la sesión anterior)
2. Leer `docs/STATUS.md` (versión actual + tabla de bloques)
3. Leer `docs/TODO.md` (qué está pendiente — única fuente operativa)
4. Leer `CLAUDE.md` (stack, patrones, procesos estandarizados)
5. Leer `docs/ARCHITECTURE.md` (patrones arquitectónicos críticos)
6. Leer `docs/WORKFLOW.md` (release, signing, migrations operativas)
7. Si la conversación va a tocar una decisión postergada, leer `docs/decisions/ADR-NNN-*.md`
8. Si la conversación va a tocar una opción que parecía válida, chequear `docs/REJECTED.md` antes de proponerla
9. Si toco el `master-plan.html`, abrirlo y revisar la sección a editar siguiendo los comentarios `<!-- Source of truth: -->`

Después devuelvo los 4 bullets de confirmación y espero la próxima instrucción del user.

---

## Lecciones aprendidas del primer simulacro real (2026-05-07)

Cuando ejecuté el Pre-Compact Checklist por primera vez en condiciones reales, el **Paso 6 (verificar HTML)** detectó **6 inconsistencias** que la verificación rápida (solo conteos) había dejado pasar:

| # | Desfase | Causa raíz |
|---|---|---|
| 1 | "Última versión: v3.5.1" hardcodeado en HTML | Texto histórico no actualizado en releases sucesivos |
| 2 | "Paquetes Flutter instalados (v3.5.1)" | Misma raíz |
| 3 | Stats panel "40 releases" vs git con 39 tags | Off-by-one al sumar el release siguiente anticipado |
| 4 | "CRIT-3 Migrar credenciales DB" vs TODO.md "de DB" | Drift de wording por edición separada |
| 5 | Diagrama ASCII "Hermes Mobile v3.5" | Texto literal no monitoreado |
| 6 | TOC "Historial v1.0 → v3.5" | Rango desactualizado |

**Conclusión:** la verificación item-por-item con `diff` (no solo conteos) es **necesaria** para detectar drift acumulado. Las queries del paso 6.A "Verificación item-por-item del HTML" arriba son las correctas.

---

## Cómo se mantiene este archivo

**Actualizar este archivo cuando:**
- Cambia el orden o contenido de los pasos del checklist
- Se agrega un archivo nuevo a `docs/` que requiere actualización pre-compact
- Se descubren patrones nuevos de drift que vale la pena verificar
- Cambia el formato del resumen pre-compact al user

**No actualizar acá:**
- Cambios menores de wording (mantener el documento estable)
- Procesos de otros disparadores (release, ADR, etc — esos viven en `CLAUDE.md` Procesos 1-5)
