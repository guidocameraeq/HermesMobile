# ADR-008: Roles y permisos como JSONB con gates de acceso

**Fecha:** 2026-05-15
**Estado:** Aceptado

## Contexto

Hasta v3.8.x el control de acceso en Hermes Mobile era binario: si un usuario podía loguear contra `usuarios`, veía toda la app. El campo `usuarios.role` existía pero no se usaba para restringir nada en Mobile (en Desktop sí se chequeaba puntualmente).

Hermes Desktop introdujo en mayo 2026 un sistema de roles compartido entre ambas apps:
- Tabla `roles` con permisos en JSONB (era TEXT).
- Catálogo `permisos_catalog` con todas las keys disponibles.
- Columna `usuarios.vendedor_nombre` que vincula un usuario con su entidad de negocio en SQL Server (puede ser distinta del username — ej: username `Franzo` → vendedor `FRANZO SERGIO`).

Necesitábamos que Mobile honre el contrato: gates de acceso, UI condicional, y resolución correcta del vendedor.

## Decisión

1. **Mobile lee permisos del rol vía JOIN en el login**:
   ```sql
   SELECT u.role, u.vendedor_nombre, COALESCE(r.permisos, '{}'::jsonb) AS permisos
   FROM usuarios u LEFT JOIN roles r ON r.nombre = u.role
   WHERE LOWER(u.username) = LOWER(@user) AND u.password_hash = @hash
   ```

2. **2 gates obligatorios antes de poblar la sesión**:
   - `permisos['mobile.access'] == true` — sino "tu rol no tiene acceso a Hermes Mobile".
   - `vendedor_nombre` no nulo (con fallback al `username` durante la transición) — sino "tu usuario no tiene un vendedor asignado".

3. **`Session.current.permissions`** es un `Set<String>` con las keys que tienen `value=true`. Helper `Session.current.can(key)` para chequeos en widgets.

4. **UI condicional** envuelve cada widget afectado en `if (Session.current.can('mobile.xxx'))`. Nada de "botón gris deshabilitado": el widget se construye o no se construye.

5. **Edge Function `auth-token` también lee `vendedor_nombre` de DB** (Opción A — single source of truth). El cliente no manda el vendedor_nombre — la función lo resuelve sola y lo upsertea en `vendedor_tokens`. Esto evita que un APK comprometido emita tokens a nombre de cualquier vendedor.

6. **Cache simple en memoria al login**. Cambios de rol en Desktop se aplican al próximo login. (Revalidación al volver de background queda como nice-to-have postergado.)

## Razón

- **Single source of truth para el `vendedor_nombre`**: vive en `usuarios`, lo leen tanto Mobile como la Edge Function. Si el admin cambia el binding, todos los consumidores ven el cambio sin redeploy.
- **Cerrado por defecto**: si una key no está en el dict del rol, `can()` devuelve false. Agregar permisos nuevos no rompe roles existentes (no aparece la feature hasta que el admin la habilite explícitamente).
- **No confiar en el cliente**: la Edge Function nunca acepta `vendedor_nombre` desde el body. Resolverlo server-side blinda contra APKs comprometidos.
- **Fallback de transición sin sorpresas**: usuarios que ya estaban funcionando (Leonardo, donde username == vendedor_nombre) siguen funcionando aunque la columna `vendedor_nombre` esté NULL para ellos.
- **Misma estructura que `PromptService`**: cargar config remoto en memoria + fallback. Patrón consolidado del proyecto.

## Alternativas consideradas

### Permisos como filas en una tabla `usuario_permisos`
- Pro: queries SQL más naturales para introspección
- Con: más joins en el login, más mantenimiento del schema, no hay diferencia funcional con JSONB para el use case (10s de keys, lectura completa al login)
- Descartado.

### App manda `vendedor_nombre` a la Edge Function (Opción B descartada)
- Pro: la función se mantiene tonta, no toca DB para resolver
- Con: APK comprometido podría emitir tokens a nombre de otro vendedor
- Descartado, ver `REJECTED.md`.

### Validación per-request del rol en cada Edge Function (no solo al login)
- Pro: cambios de permisos se aplican al instante
- Con: latencia adicional en cada call de Cronos, complica el caching
- Descartado para este sprint, considerar si el admin necesita revocar acceso urgente.

### Rebuild de la Session al volver del background
- Pro: invalidación cuasi-inmediata de cambios de rol sin re-login
- Con: requiere lógica adicional en `WidgetsBindingObserver`, manejo de estados parciales
- Postergado a una v3.9.1+ si se necesita.

## Consecuencias

- **Cualquier botón/sección/tab nueva con sensibilidad de permiso debe usar `Session.current.can(key)`**. Documentado como anti-pattern dejarlo siempre visible.
- **Agregar un permiso nuevo es 2 cambios**: registrar la key en `permisos_catalog` desde Desktop, y envolver el widget con `Session.current.can(...)` en Mobile. Roles existentes no lo tendrán hasta que el admin lo active.
- **Cambios de rol no se aplican en caliente** — siempre requieren re-login. Aviso al usuario en docs.
- **Si en el futuro `permisos_catalog` se vuelve grande y queremos que Desktop edite permisos sin recompilar Mobile**, la solución actual ya cubre — Mobile lee lo que esté en jsonb sin saber qué keys existen.
- **El fallback `vendedor_nombre ?? username` es transitorio**. Una vez confirmado que todos los usuarios reales tienen la columna seteada, removerlo en una v3.10+ para fallar explícito si falta.
