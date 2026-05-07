# ADR-001: Distribución privada, no Play Store

**Fecha:** 2026-04-22
**Estado:** Aceptado

## Contexto

Hermes Mobile es una app interna usada por ~10 vendedores de una empresa argentina. La pregunta de cómo distribuirla apareció varias veces: ¿la subimos a Google Play Store (closed testing / production), usamos un MDM, o seguimos con sideload manual?

## Decisión

Distribución sideload manual via APKs publicados en GitHub Releases (repo privado). El admin instala la app personalmente en cada dispositivo de los vendedores. Updates posteriores via banner en Configuración + force update remoto cuando hace falta.

## Razón

- **Equipo chico** (~10 vendedores) — el costo de setup de Play Store o MDM no se justifica
- **App interna privada** — no hay razón para que esté en un store público
- **Control total del flujo** — el admin decide qué versión está vigente y cuándo se fuerza update
- **Cero costo** — Google Play Developer cuesta $25, MDM cuesta ~$3-7 por dispositivo/mes
- **Velocidad de iteración** — sin review de Play, los releases salen en minutos
- **Compatibilidad con cuenta gratuita "limited distribution" de Google (sept 2026+)** — hasta 20 dispositivos sin trámite

## Alternativas consideradas

### Google Play — Closed Testing
- Pro: auto-update nativo, sin tap del usuario
- Con: review de Google (puede rechazar por OpenAI key embedded), 1-3 días de propagación, vendedores necesitan cuenta Google + aceptar invitación
- Descartado: review puede frenar features urgentes

### MDM (Microsoft Intune, Scalefusion, etc.)
- Pro: 100% silencioso, push remoto de APKs
- Con: $3-7/dispositivo/mes, requiere enrolar cada teléfono (factory reset), vendedores pierden control sobre su dispositivo
- Descartado: overkill para 10 vendedores

### Shorebird (code push para Flutter)
- Cubre solo cambios Dart-only (~80% del trabajo). Cambios nativos siguen requiriendo APK manual.
- Costo: ~$30/mes en plan medio
- Descartado: agrega dependencia externa cuando el flujo manual ya funciona. Ver ADR-004.

## Consecuencias

- **Updates requieren acción del usuario**: tocar "Actualizar" + confirmar instalador. Mitigado con force update + pre-download para latencia mínima (15-30s end-to-end).
- **Cada update post-keystore-change requiere desinstalar + reinstalar**: trade-off del release keystore (ver ADR-XXX cuando se cree). Una sola vez por cambio de firma.
- **A partir de septiembre 2027 (estimado)**: Argentina entra en la lista de países con verificación de developer obligatoria. Necesitaremos registrar la cuenta en Google (cuenta gratuita "limited distribution" cubre hasta 20 dispositivos).
- **No hay protección contra extracción de APK del dispositivo**: el threat model real (vendedor descontento) sigue siendo posible. Mitigado en parte con keystore propio + rotación de credenciales periódica.
