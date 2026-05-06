# Estado actual — Hermes Mobile

> Snapshot para Claude post-compact. Actualizar en cada release.

**Fecha del snapshot:** 2026-05-06
**Versión actual:** v3.7.3+39 (security hardening — sin release todavía)
**Último release publicado:** v3.7.2
**APK URL:** https://github.com/guidocameraeq/HermesMobile/releases/tag/v3.7.2

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
4. ✅ `docs/ESTADO_ACTUAL.md` (este archivo) creado
5. ✅ `docs/ARQUITECTURA.md` creado
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
