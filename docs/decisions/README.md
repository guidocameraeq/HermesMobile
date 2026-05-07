# Decisiones arquitectónicas (ADRs)

Esta carpeta contiene **Architecture Decision Records (ADRs)** — documentos cortos que registran decisiones técnicas importantes con su contexto y razón detrás.

## Por qué existen los ADRs

Sin ADRs, las decisiones se discuten una vez, se aplican, y se olvidan. Después alguien (yo después de un compact, otro dev) ve algo "raro" en el código, no entiende por qué está así, y propone "mejorarlo" — replicando un debate ya cerrado.

Los ADRs evitan eso: cada decisión queda con **su razón explícita** y **las alternativas que descartamos**, así nadie re-debatuje lo mismo.

## Cuándo crear un ADR

Crear un ADR cuando:
- Se toma una decisión arquitectónica con trade-offs no obvios
- Se descarta una "best practice" estándar por una razón específica al proyecto
- Se elige entre varias opciones técnicas y la elección puede sorprender más adelante
- Se posterga deliberadamente un trabajo importante

**No crear un ADR para:**
- Decisiones obvias (ej: "usamos HTTPS")
- Cambios menores que se deshacen fácil
- Implementación rutinaria sin trade-offs

## Formato

Cada ADR es un archivo `ADR-NNN-titulo-corto.md` con esta estructura:

```markdown
# ADR-NNN: Título corto

**Fecha:** YYYY-MM-DD
**Estado:** Aceptado | Reemplazado por ADR-XXX | Obsoleto

## Contexto
Qué situación motiva esta decisión.

## Decisión
Qué decidimos hacer.

## Razón
Por qué lo decidimos así.

## Alternativas consideradas
Las opciones que evaluamos y por qué no las elegimos.

## Consecuencias
Qué cambia con esto. Qué nos compromete a futuro.
```

## Reglas

1. **Inmutables**: una vez creado un ADR, **no se edita**. Si la decisión cambia, se crea un ADR nuevo que indique "Reemplaza a ADR-XXX" y se actualiza el estado del viejo a "Reemplazado".
2. **Numeración secuencial**: ADR-001, ADR-002, ... sin saltar números.
3. **Cortos**: 1 página máximo. Si hace falta más, va a un plan dedicado en `docs/` o `docs/historico/`.
4. **Específicos**: una decisión por ADR. No mezclar.

## Índice de ADRs

| # | Título | Estado | Fecha |
|---|---|---|---|
| [001](ADR-001-distribucion-privada.md) | Distribución privada, no Play Store | Aceptado | 2026-04-22 |
| [002](ADR-002-sha256-sin-salt.md) | SHA-256 sin salt aceptado por threat model interno | Aceptado | 2026-05-06 |
| [003](ADR-003-sin-ssl-pinning.md) | Sin SSL pinning (red de vendedores no es hostil) | Aceptado | 2026-05-06 |
| [004](ADR-004-force-update-no-shorebird.md) | Force update via app_config en lugar de Shorebird | Aceptado | 2026-04-25 |
| [005](ADR-005-postergar-crit3-db-creds.md) | Postergar migración de credenciales DB a Edge Functions (CRIT-3) | Aceptado | 2026-05-06 |
| [006](ADR-006-release-keystore-propio.md) | Release keystore propio para firmar APKs (CRIT-1 resuelto) | Aceptado | 2026-05-06 |
| [007](ADR-007-auth-via-vendedor-tokens.md) | Auth via vendedor_tokens y proxy OpenAI vía Edge Functions (CRIT-2 resuelto) | Aceptado | 2026-05-06 |
