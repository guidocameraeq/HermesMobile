# Prompt post-compact

Pegá este bloque al reanudar después de un compact del chat:

---

```
Estoy retomando trabajo en Hermes Mobile después de un compact del chat.
Antes de responder nada, necesito que te orientes leyendo estos archivos en orden:

1. D:\SAAS\APK\docs\SESSION_HANDOFF.md — dónde quedamos al cierre de la sesión anterior
2. D:\SAAS\APK\docs\STATUS.md — versión actual + tabla de bloques completos
3. D:\SAAS\APK\docs\TODO.md — qué está pendiente, ordenado por criticidad (🔴/🟠/🟡/🟢) — ÚNICA fuente de pendientes
4. D:\SAAS\APK\CLAUDE.md — stack, patrones arquitectónicos, mapa completo de docs, 6 procesos estandarizados
5. D:\SAAS\APK\docs\ARCHITECTURE.md — decisiones de arquitectura con razón
6. D:\SAAS\APK\docs\WORKFLOW.md — release, signing, migrations, force update
7. D:\SAAS\APK\docs\decisions\README.md — índice de ADRs (si tocamos algo postergado, leer también el ADR específico)
8. D:\SAAS\APK\docs\REJECTED.md — opciones descartadas con razón (evita re-debatir)
9. D:\SAAS\APK\docs\CHANGELOG.md — registro cronológico por sesión/release
10. C:\Users\clientes\.claude\projects\d--SAAS\memory\MEMORY.md — índice de memoria local
11. D:\SAAS\APK\docs\master-plan.html — plan completo (abrir en browser, listar secciones)

Contexto importante que no entra en los archivos:
- El user habla coloquial argentino, agenda por voz (Whisper), usa Cronos todo el tiempo
- Las SQL migrations van en scripts/*.sql y son siempre idempotentes
- El sandbox bloquea writes a prod Supabase; solo paso `dangerouslyDisableSandbox: true` cuando el user autoriza explícitamente
- App distribuida sideload privado, no en Play Store (ver ADR-001)

Después de leer, confirmame en 4 bullets:
1. Versión actual + último release
2. Tarea #1 urgente de TODO.md
3. Patrón arquitectónico clave si tocamos activities/notificaciones/Cronos
4. Algún ADR relevante si hay decisión postergada que pueda surgir

Después te digo qué vamos a hacer.
```

---

## Uso

El user copia/pega el bloque de arriba (entre ```) en el primer mensaje post-compact. Yo leo los archivos en orden, devuelvo los 4 bullets de confirmación, y quedo orientado sin depender de la conversación perdida.

## Procesos que tengo que seguir post-compact

Una vez orientado, sigo los **procesos estandarizados** documentados en `CLAUDE.md` sección "🔄 Procesos estandarizados":

1. Cada release publicado → checklist de actualización de docs
2. Patrón arquitectónico nuevo → ARCHITECTURE.md + memoria
3. Bloque del plan completado → mover en HTML + memoria + tareas
4. Tarea/idea/deuda nueva → primero a TODO.md
5. Decisión técnica con trade-offs → ADR nuevo
6. Compact (este flujo) → leer + confirmar

## Si alguno de esos archivos no existe (regresión total o reset)

Fallback en orden:
- `C:\Users\clientes\.claude\projects\d--SAAS\memory\*.md` — memoria local, sobrevive todo
- `D:\SAAS\APK\CLAUDE.md` — onboarding completo
- `D:\SAAS\APK\docs\master-plan.html`
- Últimos 20 commits: `git log --oneline -20`
- Glob de `lib/services/` + `pubspec.yaml`

Con eso se reconstruye el contexto en minutos.

## Cómo se mantiene este archivo

Actualizar este archivo cuando:
- Se agrega/quita un archivo crítico de docs
- Cambia el orden recomendado de lectura
- Cambia el contexto operativo (ej: nuevas convenciones del user)
- Se agrega un proceso nuevo en CLAUDE.md
