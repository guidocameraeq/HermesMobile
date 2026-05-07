# ADR-004: Force update via app_config en lugar de Shorebird

**Fecha:** 2026-04-25
**Estado:** Aceptado

## Contexto

En abril 2026 evaluamos cómo manejar updates "obligatorios" para vendedores. Las opciones eran: (a) dejar updates 100% opcionales (status quo, mal para fixes críticos), (b) usar Shorebird (code push de Flutter), (c) implementar nuestro propio mecanismo de force update.

## Decisión

Implementamos force update propio: tabla `app_config` en Supabase con un campo `min_version_required`. Si la versión local < ese valor, al login se muestra `ForceUpdateScreen` bloqueante. Reversible al instante con un UPDATE en Supabase. Sin dependencias externas.

## Razón

- **Simplicidad**: 1 tabla + 1 service + 1 screen. No hay vendor externo para gestionar.
- **Sin costo recurrente**: Shorebird cuesta ~$30/mes en plan medio. Para una app interna con 10 vendedores no se justifica.
- **Sin lock-in**: si Shorebird sube precio o cierra, hay que reescribir el flujo. Nuestro código está en nuestro repo.
- **Cubre el caso real**: el escenario "obligar a actualizar" se resuelve igual con ambos enfoques. La UX final (1 tap del vendedor en el instalador) es la misma porque Android no permite silent updates sin Play Store/MDM.
- **Killswitch reversible**: 1 query SQL para activar, 1 query para desactivar. Comprobado en producción.

## Alternativas consideradas

### Shorebird (code push)
- Pro: updates silenciosos sin reinstalar, ~80% de cambios típicos cubiertos (Dart-only)
- Con: $30/mes, dependencia externa, no cubre cambios nativos (Manifest, deps, assets)
- Descartado: el costo/lock-in no se justifica para 10 vendedores

### Google Play Closed Testing (auto-update nativo)
- Cubierto en ADR-001. Descartado por el review process y la cuenta de developer.

### MDM
- Cubierto en ADR-001. Descartado por costo.

## Consecuencias

- **Cada force update sigue requiriendo el tap del vendedor en el instalador de Android**. Es la limitación de sideload (no es un problema de nuestro mecanismo). Mitigado con pre-download del APK en background — el instalador abre instantáneo.
- **Latencia de propagación**: hasta 24-48h para que todos los vendedores vean el bloqueo (depende de cuándo abran la app).
- **Compromiso a futuro**: si crecemos mucho y una operación de "fix urgente" se vuelve frecuente, evaluar Shorebird con datos reales (cuántos updates de Dart-only por mes).
