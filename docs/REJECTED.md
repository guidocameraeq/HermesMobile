# Opciones rechazadas

> Decisiones que **no** tomamos, con la razón. Evita re-debatuir lo mismo en
> sesiones futuras. Cada vez que descartamos una opción durante una decisión
> arquitectónica, queda registrada acá referenciando el ADR donde figura como
> "alternativa considerada".

## Formato de cada entrada

```
### [Año-Mes] Opción descartada
**Contexto:** qué decisión motivó evaluar esta opción.
**Por qué se descartó:** razón principal.
**Referencia:** ADR-NNN (link al detalle completo).
**Reconsiderar si:** condición que justificaría volver a evaluarla.
```

---

## Inventario actual

### 2026-04 — Google Play Closed Testing
**Contexto:** distribución de la app a vendedores.
**Por qué se descartó:** review de Google puede frenar features urgentes; los vendedores necesitan cuenta Google + aceptar invitación al closed testing; review puede rechazar APKs por OpenAI key embedded (problema histórico, ya resuelto).
**Referencia:** [ADR-001](decisions/ADR-001-distribucion-privada.md).
**Reconsiderar si:** crecemos a >50 vendedores o aparece compliance formal (SOC 2, ISO 27001).

### 2026-04 — MDM (Microsoft Intune, Scalefusion, Hexnode, etc.)
**Contexto:** ídem distribución (alternativa para silent updates).
**Por qué se descartó:** $3-7/dispositivo/mes, requiere enrolar cada teléfono (factory reset usualmente), vendedores pierden control sobre su dispositivo.
**Referencia:** [ADR-001](decisions/ADR-001-distribucion-privada.md).
**Reconsiderar si:** equipo >20 vendedores con celulares de empresa (no BYOD).

### 2026-04 — Shorebird (code push de Flutter)
**Contexto:** updates "obligatorios" sin requerir tap del usuario en el instalador.
**Por qué se descartó:** ~$30/mes en plan medio, dependencia externa con riesgo de lock-in, no cubre cambios nativos (Manifest, deps, assets).
**Referencia:** [ADR-004](decisions/ADR-004-force-update-no-shorebird.md).
**Reconsiderar si:** los updates de Dart-only se vuelven >5/mes y la fricción del tap del usuario se traduce en updates atrasados frecuentes.

### 2026-05 — bcrypt + salt para hashing de passwords
**Contexto:** auditoría OWASP detectó SHA-256 sin salt (HIGH-1).
**Por qué se descartó:** threat model interno no justifica el costo; requiere migración coordinada con desktop Python (Hermes Desktop también usa SHA-256); mitigación más simple disponible (passwords ≥10 caracteres).
**Referencia:** [ADR-002](decisions/ADR-002-sha256-sin-salt.md).
**Reconsiderar si:** dump de tabla `usuarios` se vuelve riesgo realista, crece equipo a >15 vendedores, o se adopta compliance formal.

### 2026-05 — SSL pinning
**Contexto:** auditoría OWASP detectó M5 (Insecure Communication) parcial — sin pinning, app confía en cualquier CA del sistema.
**Por qué se descartó:** la red de los vendedores no es hostil (móvil + WiFi domiciliario, no proxies corporativos); `network_security_config.xml` ya rechaza user-installed certs (cubre 90% de MITM realistas); pinning agrega fragilidad operativa cuando OpenAI o Supabase rotan certs.
**Referencia:** [ADR-003](decisions/ADR-003-sin-ssl-pinning.md).
**Reconsiderar si:** manejamos datos altamente sensibles (info bancaria, números de tarjeta, datos personales protegidos por ley).

### 2026-05 — Migración inmediata de credenciales DB a Edge Functions (CRIT-3)
**Contexto:** auditoría OWASP detectó que `pgPass` está embebido en el APK, igual que tenía la OpenAI key (CRIT-2 ya resuelto en v3.8.0).
**Por qué se descartó:** refactor masivo (~10 services), beneficio menor que CRIT-2 (no permite gastar dinero externo, daño contenido), mitigación robusta disponible (release keystore + force update + rotación periódica de pass).
**Referencia:** [ADR-005](decisions/ADR-005-postergar-crit3-db-creds.md).
**Reconsiderar si:** crecemos a >15 vendedores, agregamos features con datos sensibles, o adoptamos compliance.

### 2026-05 — Migración a Supabase Auth (auth.users)
**Contexto:** evaluado durante diseño del proxy OpenAI (Opción 3 en plan original — auth via JWT real con bcrypt automático).
**Por qué se descartó:** invasivo (migración de tabla `usuarios` a `auth.users`, cambio de modelo de roles), 2-3 días de esfuerzo extra, no necesario para resolver CRIT-2 (que la opción de tokens propios ya cubre).
**Referencia:** [ADR-007](decisions/ADR-007-auth-via-vendedor-tokens.md).
**Reconsiderar si:** crecemos a >15 vendedores o cambia el threat model (compliance, MFA, refresh tokens reales).

### 2026-05 — Activar `--verify-jwt` en las Edge Functions
**Contexto:** durante deploy de cronos-chat / cronos-transcribe / auth-token, Supabase ofrece validación automática del JWT del Bearer.
**Por qué se descartó:** validamos nosotros con `vendedor_tokens` (token random hex, no JWT), no usamos Supabase Auth. Activar `--verify-jwt` rechazaría requests porque el token no es JWT válido de Supabase.
**Referencia:** [ADR-007](decisions/ADR-007-auth-via-vendedor-tokens.md).
**Reconsiderar si:** migramos a Supabase Auth (escenario que invalidaría todo este enfoque).

---

## Cómo se mantiene este archivo

**Agregar entrada cuando:**
- Se descarta una opción durante una decisión técnica que se documenta como ADR
- Se evalúa una herramienta/servicio externo y se decide no adoptarlo
- Se considera una "best practice" estándar y se elige no aplicarla

**No agregar:**
- Bugs descartados o features postergadas (eso va a `TODO.md`)
- Decisiones triviales sin trade-offs reales

**Si una decisión rechazada se reconsidera y se adopta:**
- Mover la entrada a una sección "Reconsideradas y adoptadas" al final del archivo (no eliminar)
- Crear ADR nuevo que documente el cambio
- Marcar el ADR original como "Reemplazado por ADR-NNN"
