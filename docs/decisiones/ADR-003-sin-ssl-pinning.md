# ADR-003: Sin SSL pinning

**Fecha:** 2026-05-06
**Estado:** Aceptado

## Contexto

Auditoría de seguridad de mayo 2026 identificó que la app no implementa SSL pinning. Confía en cualquier CA del sistema (lo declaramos explícito en `network_security_config.xml`: solo CAs del sistema, no user-installed). Esto significa que un atacante con un cert empresarial mal configurado o malware con privilegios de admin podría hacer MITM.

## Decisión

No implementamos SSL pinning.

## Razón

- **Red de los vendedores no es hostil**: trabajan con redes móviles + WiFi domiciliarios, no proxies corporativos que rompan TLS.
- **`network_security_config.xml` rechaza user-installed certs** (v3.7.3): esto cubre el 90% de los casos de MITM realistas (malware, certs empresariales custom).
- **Pinning es frágil**: cuando OpenAI o Supabase rotan certificados, hay que actualizar la app. Sin actualización a tiempo, los vendedores quedan sin Cronos.
- **Threat model**: el atacante real no tiene capacidad de MITM contra vendedores en campo. Está documentado en CLAUDE.md.

## Alternativas consideradas

### SSL pinning con `ssl_pinning_plugin` o config nativa
- Pro: defensa contra MITM con cert custom
- Con: agrega fragilidad operativa (rotación de certs requiere release de la app), agrega dependencia
- Descartado: ratio costo/beneficio muy bajo

### Pinning solo de CAs raíz (no leaf certs)
- Más estable a rotaciones
- Pero también más débil — cualquier cert firmado por la CA raíz pinned es válido
- Descartado: si vamos a hacer pinning, queremos hacerlo bien o no hacerlo

## Consecuencias

- Si un vendedor tiene un dispositivo rooteado **y** un atacante físico le instala un cert custom **y** el atacante está en su red, podría interceptar tráfico Hermes-Supabase. Escenario muy específico, baja probabilidad.
- **Compromiso a futuro**: si en algún momento manejamos datos altamente sensibles (info bancaria, números de tarjeta, datos personales protegidos por ley), revisar este ADR.
