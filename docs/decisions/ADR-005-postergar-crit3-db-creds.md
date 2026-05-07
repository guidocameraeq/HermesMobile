# ADR-005: Postergar migración de credenciales DB a Edge Functions (CRIT-3)

**Fecha:** 2026-05-06
**Estado:** Aceptado

## Contexto

Auditoría de seguridad de mayo 2026 identificó CRIT-3: las credenciales del rol `postgres` (Supabase) están en `lib/config/constants.dart` y se compilan al APK. Son extraíbles con `strings app-release.apk`. Es el mismo problema que tenía la OpenAI key (CRIT-2), que ya resolvimos con un proxy via Edge Functions en v3.8.0.

## Decisión

**Postergamos** la migración de credenciales DB a Edge Functions. La pass de Postgres sigue compilándose al APK por ahora. Mitigamos con keystore propio + capacidad de rotar la pass + force update.

## Razón

- **Esfuerzo masivo**: refactorizar TODOS los servicios que usan `PgService` directo (scorecard_service, clientes_service, actividades_service, visitas_service, drilldown_service, lineas_service, etc — son ~10 services). Cada uno hoy ejecuta SQL directo; tendríamos que mover toda esa lógica a Edge Functions o exponer una API de queries.
- **Threat model contenido**: si se filtra el APK, podemos:
  1. Generar pass nueva en Supabase Dashboard (1 minuto)
  2. Actualizar `constants.dart` + recompilar (15 min)
  3. Force update (vendedores actualizan en horas)
  4. Revocar la conexión vieja (la sesión PG se cierra)

  El daño en la ventana de vulnerabilidad es contenido: el rol `postgres` puede dañar la DB pero no puede sacar dinero ni dar instrucciones a OpenAI. RLS habilitado limita aún más.

- **CRIT-2 era distinto**: la OpenAI key permite **gastar dinero** del cap mensual ($400). El daño era directo y monetario. Por eso priorizamos.
- **CRIT-3 requiere acceso primero**: el atacante necesita el APK físicamente o haber accedido al repo privado. Para los 10 vendedores, escenario poco probable.

## Alternativas consideradas

### Migrar todo a Edge Functions ahora
- Esfuerzo: 3-5 días de refactor + testing
- Beneficio: cierre completo de credenciales en APK
- Descartado: prioridad demasiado baja para el costo

### Migrar a Supabase Auth + RLS efectivo
- Cada vendedor tiene un JWT, RLS filtra por vendedor automáticamente, no necesitamos rol admin en el cliente
- Esfuerzo: 2-3 días + migración de tabla usuarios a auth.users
- Postergado a una v4.0 si se justifica con escala o threat model nuevo

### Mantener `pgPass` pero rotarla periódicamente
- Mitigación parcial: cada 3 meses, rotar pass + force update
- Aceptable como práctica continua. Se documenta en TAREAS_PENDIENTES.md como tarea recurrente.

## Consecuencias

- **APKs filtrados pueden conectarse a DB con la pass del momento**. Mitigado con rotación + force update + RLS habilitado.
- **Compromiso a futuro**: si crecemos a >15 vendedores, agregamos features con datos sensibles, o adoptamos compliance, **revisar este ADR**. Probablemente combinarlo con migración a Supabase Auth (ADR a crear cuando llegue ese momento).
- **Tarea recurrente documentada**: rotar pass de Postgres post-rollout v3.8.0 + cada 3-6 meses como práctica.
