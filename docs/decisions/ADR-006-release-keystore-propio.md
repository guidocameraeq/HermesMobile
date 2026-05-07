# ADR-006: Release keystore propio para firmar APKs

**Fecha:** 2026-05-06
**Estado:** Aceptado

## Contexto

Hasta v3.7.2, el APK release de Hermes se firmaba con la **clave debug** que Android Studio genera automáticamente (`~/.android/debug.keystore` con password `android`). La auditoría de seguridad de mayo 2026 identificó esto como **CRIT-1**: cualquier dev con Android Studio puede generar APKs firmados con la misma clave debug, y Android los aceptaría como "update legítimo" de la app — permitiendo impersonación del proyecto vía un APK falso enviado por WhatsApp/email/etc.

Adicionalmente, la SHA-1 de la clave debug puede variar entre máquinas (cada PC tiene su propia debug.keystore generada localmente), por lo que cualquier intento de compilar desde otra máquina rompe la cadena de firma — los vendedores no pueden actualizar (Android rechaza signature mismatch).

## Decisión

Generamos un **keystore RSA 2048 dedicado** para release (`keystore/hermes-release.jks`), gitignored, con validez de 10000 días (~27 años). El password vive en `android/key.properties` también gitignored. `build.gradle.kts` lo lee y firma releases con esa clave; si `key.properties` no existe (clones nuevos sin acceso al keystore), cae a debug signing como fallback con warning.

SHA-1 oficial: `73:9D:EE:58:75:E6:18:B4:3D:6C:DA:49:3B:B7:3C:B0:C9:83:F7:0F`
SHA-256: `8b71a20d11783c43a9eea7e518c51c926eaf7d43e0076732fe84753e30726c03`

## Razón

- **CRIT-1 mata cualquier garantía de identidad de la app**: sin esto, "que Android verifique la firma del update" no defiende de nada porque la firma debug es genérica.
- **Necesario para futuros mecanismos de seguridad**: el plan de force update (ADR-004) y el rollout de v3.8.0 con proxy (ADR-007) asumen que solo nosotros podemos generar APKs aceptados. Si la firma es debug, todo eso pierde valor.
- **Costo bajo**: 1 hora de setup, no requiere infraestructura adicional.
- **Condición previa al alta de la app a Google Cloud OAuth**: el SHA-1 registrado debe ser estable.

## Alternativas consideradas

### Mantener debug signing (status quo previo)
- Pro: cero esfuerzo
- Con: vulnerabilidad CRIT-1 abierta
- Descartado: vuelve sin sentido cualquier mecanismo de seguridad arriba

### Google Play App Signing (Play subiendo el upload key, gestionando la signing key)
- Pro: Google maneja la rotación, backups, etc
- Con: requiere subir la app a Play Store (descartado en ADR-001)
- Descartado: incompatible con distribución privada

### Hardware Security Module (HSM) cloud (Google Cloud KMS, AWS CloudHSM)
- Pro: máxima seguridad de la signing key
- Con: complejidad operativa enorme para 10 vendedores, costo, dependencia externa
- Descartado: overkill total

## Consecuencias

- **Migración one-time forzada**: cualquier vendedor con APK debug-signed (v3.7.2 o anterior) tuvo que **desinstalar y reinstalar** v3.7.3+ una sola vez. Android rechaza updates con firma distinta. Hecho durante el rollout de v3.7.3.
- **Perder el `.jks` = perder capacidad de actualizar**: si se pierde el keystore, los vendedores con la app instalada no pueden recibir nunca más un update firmado por la misma clave. Mitigación: **backup del `.jks` en lugar seguro fuera de la PC**. Ya documentado en `WORKFLOW.md`.
- **OAuth setup requiere re-registro**: el SHA-1 debug viejo (`EC:92:8A:A2:30:AC:E2:AC:62:16:9C:ED:22:8A:D3:99:33:AF:0F:0E`) registrado en Google Cloud Console debe reemplazarse por el nuevo. Tarea operativa documentada en `TODO.md`.
- **Compilar desde otra máquina requiere distribuir el keystore**: cualquier máquina que genere release debe tener acceso al `.jks` y al password de `key.properties`. Hoy: una sola máquina. Si hace falta más de una, transferir por canal seguro (no commitear, no email plano).
- **Compromiso a futuro**: si aparece colaborador externo con permisos de release, considerar Google Play App Signing o HSM cloud. Mientras seamos un equipo de 1, esto alcanza.
