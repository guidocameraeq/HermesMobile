# ADR-002: SHA-256 sin salt aceptado para passwords

**Fecha:** 2026-05-06
**Estado:** Aceptado

## Contexto

Auditoría de seguridad de mayo 2026 identificó que `auth_service.dart:hashPassword()` usa SHA-256 sin salt para hashear las contraseñas de los vendedores antes de validarlas contra la tabla `usuarios`. Es una "bad practice" estándar en seguridad — el algoritmo correcto es bcrypt o argon2id con salt por usuario.

## Decisión

Mantenemos SHA-256 sin salt por ahora. No migramos a bcrypt.

## Razón

- **Threat model**: el atacante real es "vendedor descontento con APK en su teléfono", no "atacante con dump completo de la tabla `usuarios`".
- **Quién tiene acceso a la tabla**: Supabase (cloud, AWS, con sus propias garantías) y el admin (yo). Para que un atacante explote la falta de salt, primero tiene que **comprometer todo el Supabase** — escenario donde tener bcrypt no es la principal defensa, ya tenés problemas más grandes.
- **Compatibilidad con desktop**: Hermes Desktop también usa SHA-256 sin salt. Cambiar mobile rompe la coherencia, requiere migración coordinada.
- **Mitigación más simple disponible**: políticas de password fuertes (≥10 caracteres) hacen que rainbow tables sean inviables incluso sin salt.

## Alternativas consideradas

### Migrar a bcrypt con salt por usuario
- Pro: estándar de la industria
- Con: requiere migración coordinada mobile + desktop, agregar columna `password_hash_v2`, migrar progresivamente. Esfuerzo: 1-2 días.
- Descartado: ratio costo/beneficio muy bajo en este threat model.

### Migrar a Supabase Auth (auth.users)
- Pro: bcrypt automático + JWT con refresh + MFA opcional
- Con: refactor grande de auth, cambio de modelo de roles, ~2-3 días.
- Postergado: vale la pena si crecemos a >15 vendedores o cambia el threat model. Documentado en TAREAS_PENDIENTES.md como "Baja prioridad".

## Consecuencias

- Si la tabla `usuarios` se filtra → passwords débiles (cualquiera <10 chars sin caracteres especiales) caen rápido por rainbow tables.
- **Compromiso a futuro**: si crecemos a >15 vendedores, manejamos datos más sensibles, o adoptamos compliance formal (SOC 2, etc), revisar este ADR y migrar a bcrypt o Supabase Auth.
- **Mitigación recomendada**: cuando agregamos un vendedor nuevo, exigir password ≥10 caracteres con mezcla de tipos.
