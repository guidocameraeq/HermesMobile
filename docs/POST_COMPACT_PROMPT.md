# Prompt post-compact

Pegá este bloque al reanudar después de un compact del chat:

---

```
Estoy retomando trabajo en Hermes Mobile después de un compact del chat.
Antes de responder nada, necesito que te orientes leyendo estos archivos en orden:

1. D:\SAAS\APK\docs\ESTADO_ACTUAL.md — qué hay y qué estábamos haciendo
2. D:\SAAS\APK\CLAUDE.md — stack, servicios, patrones arquitectónicos
3. D:\SAAS\APK\docs\ARQUITECTURA.md — decisiones clave que NO se pueden recrear (la "razón" detrás de cada patrón)
4. D:\SAAS\APK\docs\WORKFLOW.md — cómo hacemos commits, releases, migraciones
5. C:\Users\clientes\.claude\projects\d--SAAS\memory\MEMORY.md — índice de memoria
6. D:\SAAS\APK\docs\PLAN_MAESTRO_HERMES_MOBILE.html — plan maestro con bloques completos y pendientes (abrilo y listá las secciones para conocer qué hay)

Contexto importante que no entra en los archivos:
- La key de OpenAI sigue en el APK (pendiente #1 técnica): mover a Supabase Edge Function
- Google Calendar OAuth está pre-configurado pero faltan test users (mails de vendedores)
- El user habla coloquial argentino, agenda por voz (Whisper), usa Cronos todo el tiempo
- Las SQL migrations van en scripts/*.sql y son siempre idempotentes
- El sandbox bloquea writes directos a Supabase prod; solo paso `dangerouslyDisableSandbox: true` cuando el user autoriza

Después de leer, confirmame en 3 bullets:
1. En qué versión estamos y qué se publicó último
2. Cuál es el pendiente #1 por impacto
3. Qué patrón arquitectónico es clave si tocamos activities/notificaciones/Cronos

Después te digo qué vamos a hacer.
```

---

## Uso

El user copia/pega el bloque de arriba (entre ```) en el primer mensaje post-compact. Yo leo los archivos, devuelvo los 3 bullets de confirmación, y quedo orientado sin depender de la conversación perdida.

## Si alguno de esos archivos no existe (regresión o reset)

Fallback: leer en este orden
- `C:\Users\clientes\.claude\projects\d--SAAS\memory\*.md` (memoria de Claude — sobrevive cualquier compact)
- `D:\SAAS\APK\CLAUDE.md`
- `D:\SAAS\APK\docs\PLAN_MAESTRO_HERMES_MOBILE.html`
- Últimos 10 commits: `git log --oneline -20`

Con eso + pubspec + un vistazo a `lib/services/` se puede reconstruir el contexto en unos minutos.
