# Tareas pendientes — Hermes Mobile

> **Fuente única de verdad operativa.** Este archivo consolida todas las
> tareas pendientes (operativas, técnicas, de infra) en un solo lugar.
> El plan maestro HTML tiene la versión "linda" para humanos; este es el
> versión accionable que se mantiene siempre actualizado.
>
> **Última actualización:** 2026-05-07

---

## 🔴 Urgente — bloquea operación o seguridad

### Cargar SHA-1 nuevo en Google Cloud OAuth (Calendar)
- **Qué:** actualizar SHA-1 en https://console.cloud.google.com/apis/credentials → OAuth client Android del proyecto "Hermes Mobile"
- **Valor nuevo:** `73:9D:EE:58:75:E6:18:B4:3D:6C:DA:49:3B:B7:3C:B0:C9:83:F7:0F`
- **Valor viejo a reemplazar:** `EC:92:8A:A2:30:AC:E2:AC:62:16:9C:ED:22:8A:D3:99:33:AF:0F:0E` (debug)
- **Impacto si no se hace:** botón "Conectar con Google Calendar" falla. Resto de la app OK.
- **Quién:** user (requiere acceso a Google Cloud Console del workspace)
- **Esfuerzo:** 5 min
- **Origen:** v3.7.3 (cambio de keystore)

### Activar force update a v3.8.0
- **Qué:** `UPDATE app_config SET value='3.8.0' WHERE key='min_version_required';`
- **Impacto si no se hace:** vendedores siguen con APKs viejos que tienen la OpenAI key embebida (CRIT-2 sigue con superficie de exposición hasta que todos actualicen)
- **Pre-requisito:** que el user haya validado v3.8.0 en su device de prueba
- **Quién:** Claude ejecuta cuando el user da OK
- **Esfuerzo:** 30 segundos
- **Origen:** v3.8.0 rollout

---

## 🟠 Alta — hacer pronto pero no inmediato

### Rotar la OpenAI API key vieja
- **Qué:**
  1. Generar key nueva en https://platform.openai.com/api-keys
  2. Editar Secret `OPENAI_API_KEY` en Supabase Dashboard → Functions → Secrets
  3. Revocar la key vieja (`sk-proj-WxHg2...`) en OpenAI
- **Impacto:** APKs viejos que aún anden dando vueltas (en repo, en celulares no actualizados) dejan de funcionar al instante para OpenAI
- **Pre-requisito:** todos los vendedores activos en v3.8.0 (esperar 3-5 días tras force update)
- **Quién:** user (genera key) + Claude opcional (carga en Supabase)
- **Esfuerzo:** 3 minutos
- **Origen:** cierre completo de CRIT-2

### Limpiar APK assets viejos de GitHub Releases
- **Qué:** eliminar `app-release.apk` de v3.6.0, v3.7.0, v3.7.1, v3.7.2, v3.7.3 (mantener tags + release notes)
- **Impacto:** ya no se puede descargar un APK con la key vieja embebida desde el repo
- **Quién:** Claude via API de GitHub (5 min)
- **Esfuerzo:** 5 min
- **Origen:** defensa en profundidad post v3.8.0

### Recopilar emails de vendedores para Google Calendar
- **Qué:** recopilar el gmail de cada vendedor que va a usar Calendar
- **Por qué:** Google Cloud OAuth está en modo "Testing" — solo emails registrados como Test Users pueden completar el flow
- **Pasos siguientes:** agregar cada email en OAuth consent screen → Test users
- **Quién:** user (recopilación) + después agregar en Console
- **Esfuerzo:** depende de coordinación con el equipo
- **Origen:** v3.1 (Google Calendar) — pendiente desde abril

---

## 🟡 Media — mejoras importantes pero no críticas

### CRIT-3 — Migrar credenciales de DB a Edge Functions
- **Qué:** sacar `pgPass` de `constants.dart`. Todas las queries pasan por Edge Functions con auth de vendedor.
- **Por qué:** mismo problema que CRIT-2 con OpenAI key, pero para DB. Sigue siendo extraíble del APK.
- **Mitigación actual:** release keystore + force update permite rotar pass de Postgres + recompilar rápido si se filtra
- **Esfuerzo:** grande (refactor de TODOS los servicios que usan PgService directo)
- **Cuándo:** sin urgencia. Atacar cuando crezca el equipo o cambie el threat model.

### Rotar password de Postgres después del rollout v3.8.0
- **Qué:**
  1. Cambiar password del rol `postgres` en Supabase Dashboard
  2. Actualizar `lib/config/constants.dart` con el password nuevo
  3. Actualizar el secret en Supabase Edge Functions también si lo usan (revisar)
  4. Buildear v3.8.1 + force update
- **Impacto:** mata la capacidad de cualquier APK viejo de conectarse a la DB con la pass vieja
- **Pre-requisito:** todos los vendedores en v3.8.0
- **Esfuerzo:** 30 minutos
- **Origen:** mitigación parcial de CRIT-3

### Notificaciones con acciones rápidas (Android Action Buttons)
- **Qué:** botones "Posponer 10 min" y "Completada" en el panel de notificaciones nativo (sin abrir la app)
- **Tech:** `AndroidNotificationAction` + background isolate (`@pragma('vm:entry-point')`)
- **Esfuerzo:** ~80 LOC + testing con app totalmente cerrada
- **Origen:** plan maestro §19 desde marzo

### Soft-delete de actividades
- **Qué:** cambiar `ActividadesService.eliminar()` de DELETE hard a `UPDATE SET eliminada_at=NOW()`
- **Por qué:** permite recuperar accidentes + auditoría
- **Esfuerzo:** ~30 min (1 query change + filtros en lecturas)

---

## 🟢 Baja — nice to have

### Drill-downs del scorecard más accionables
- Mejorar contenido para que cada drill-down sugiera acciones concretas (aprovechar LLM)
- Esfuerzo: medio

### Verificación de saldos CxC con Hermes Desktop
- Comparar que coinciden los saldos entre app y desktop
- Esfuerzo: chico

### Mapa de visitas en Hermes Desktop (no en mobile)
- Leaflet en WebView, heatmap por zona/vendedor

### Pantalla de gestión de prompts en Hermes Desktop
- UI para editar `agent_prompts` con preview, versionar, rollback

### Dashboard de Cronos Analytics en Hermes Desktop
- Documentado en plan maestro §20 — queries SQL listas, falta UI
- Esfuerzo: 1 día

### Migración a Supabase Auth (en lugar de auth custom)
- Resolvería HIGH-1 (bcrypt automático) + JWT real con refresh tokens
- Esfuerzo: 2-3 días (migración de tabla usuarios + cambios coordinados con desktop)
- Cuándo: si crecemos a >15 vendedores o si el threat model cambia

---

## 📅 Bloques pendientes del plan original

Estos son bloques completos del plan maestro, no items sueltos. Detalle completo en [`docs/master-plan.html`](master-plan.html) §13–§18.

| Bloque | Descripción | Prioridad | Estado |
|---|---|---|---|
| **C** | Embudo CRM de Prospectos | Alta | Pendiente |
| **F** | Matriz de Potencial | Alta | Pendiente |
| **D** | Leads desde Google Forms | Media | Pendiente |
| **G** | Relevamiento PDV | Media | Pendiente |
| **H** | Objetivo de Visitas Diarias | Media | Pendiente |
| **J** | Push Notifications (FCM) | Baja | ~70% (falta solo FCM server-side) |

---

## 🔄 Cómo se mantiene este archivo

**Actualizar este archivo cuando:**
1. Se completa una tarea → moverla a `## ✅ Completadas recientemente` (sección al final, mantener últimos 30 días) o eliminar si es vieja
2. Surge una tarea nueva → agregar en la categoría de criticidad correspondiente
3. Cambia la prioridad de algo → moverlo entre secciones
4. Se agrega contexto nuevo a una tarea existente → editar in-place

**No actualizar acá:**
- Cosas que se hacen y se terminan en la misma sesión (no son tareas pendientes)
- Tareas efímeras de la conversación actual (eso va en TodoWrite)

**Sincronización con otros docs:**
- El plan maestro HTML tiene la versión narrada para humanos
- Este archivo tiene la versión operativa accionable
- Si hay desfase, este manda

---

## ✅ Completadas recientemente

### Mayo 2026
- ✅ **2026-05-07** Refactor del sistema de docs al modelo de 6 capas + HTML como dashboard maestro completo (commits `85dbb39`, `800e21e`)
- ✅ **2026-05-07** ADR-006 (release keystore) y ADR-007 (auth via vendedor_tokens) creados formalizando patrones de v3.7.3 y v3.8.0
- ✅ **2026-05-07** Pre-Compact Checklist y POST_COMPACT_PROMPT estructurados con 4 capas de defensa
- ✅ **2026-05-06** Release keystore propio (CRIT-1) — v3.7.3
- ✅ **2026-05-06** RLS en `app_config` y `cronos_logs` (HIGH-2) — v3.7.3
- ✅ **2026-05-06** `network_security_config.xml` (MED-3) — v3.7.3
- ✅ **2026-05-06** Proxy OpenAI via Edge Functions (CRIT-2) — v3.8.0
- ✅ **2026-05-06** Smoke test del proxy validado end-to-end
