# Hermes Mobile

App Android Flutter para el equipo comercial de ~10 vendedores en Argentina. Plataforma CRM con asistente IA por voz, agenda, notificaciones, GPS, integración con Google Calendar y login biométrico.

[![Versión](https://img.shields.io/badge/versión-v3.8.0-2563EB)](https://github.com/guidocameraeq/HermesMobile/releases/latest) · [![Distribución](https://img.shields.io/badge/distribución-privada%20sideload-orange)](docs/decisions/ADR-001-distribucion-privada.md) · [![Min SDK](https://img.shields.io/badge/Android-8.0%2B%20%28SDK%2026%29-green)](https://developer.android.com/about/versions/oreo)

---

## Qué es

Hermes Mobile es la mitad móvil de un sistema CRM bidireccional. La otra mitad ([`Hermes Desktop`](https://github.com/guidocameraeq/Teacup), repo separado) es la app de admin que vive en la oficina: configura métricas, asigna objetivos, gestiona usuarios y consume reportes.

Mobile es el "lado del vendedor en la calle":
- Lee scorecard, ventas, pedidos y saldos de cuenta corriente del SQL Server interno (vía VPN)
- Escribe actividades comerciales, visitas con GPS y prospectos a Supabase (cloud, sin VPN)
- Cronos: asistente IA con voz (Whisper API) que agenda actividades en lenguaje natural
- Funciona offline para tareas en el campo — usa cache local cuando no hay VPN

## Stack

| Capa | Tecnología |
|---|---|
| Framework | Flutter / Dart |
| Min SDK | 26 (Android 8+) |
| DB cloud | Supabase PostgreSQL (sin VPN) |
| DB interna | SQL Server via jTDS (con VPN) |
| LLM | OpenAI GPT-4o-mini (vía Supabase Edge Functions proxy) |
| STT | OpenAI Whisper (vía proxy) |
| Calendar | Google Calendar API (OAuth) |
| Notifs | flutter_local_notifications + timezone |
| Biométrico | local_auth + flutter_secure_storage |
| Edge Functions | Supabase (Deno) — auth-token, cronos-chat, cronos-transcribe |

## Distribución

Hermes Mobile **no se distribuye en Google Play Store**. Es una app interna privada que se instala manualmente en los teléfonos de los vendedores. Los APKs firmados se publican en [GitHub Releases](https://github.com/guidocameraeq/HermesMobile/releases) (repo privado).

Los updates se manejan con un mecanismo propio: banner en Configuración (soft) + `app_config.min_version_required` para force update remoto sin recompilar. Detalle en [`docs/WORKFLOW.md`](docs/WORKFLOW.md).

## Documentación

Toda la doc viva del proyecto está en [`docs/`](docs/). Estructura siguiendo modelo de 6 capas:

- 🏗️ [`ARCHITECTURE.md`](docs/ARCHITECTURE.md) — patrones arquitectónicos críticos con razón detrás
- 📌 [`STATUS.md`](docs/STATUS.md) — snapshot de la versión actual + tabla de bloques
- ✅ [`TODO.md`](docs/TODO.md) — tareas pendientes (única fuente de verdad accionable)
- 📝 [`CHANGELOG.md`](docs/CHANGELOG.md) — registro cronológico por sesión/release
- 🗂️ [`decisions/`](docs/decisions/) — Architecture Decision Records (ADRs)
- ❌ [`REJECTED.md`](docs/REJECTED.md) — opciones descartadas y por qué (evita re-debatir)
- 📊 [`master-plan.html`](docs/master-plan.html) — plan maestro con timeline + secciones (abrir en browser)
- 🔧 [`WORKFLOW.md`](docs/WORKFLOW.md) — release, signing, migrations, OAuth setup
- 🔄 [`SESSION_HANDOFF.md`](docs/SESSION_HANDOFF.md) — dónde quedamos al cerrar la última sesión

[`CLAUDE.md`](CLAUDE.md) (raíz) tiene las reglas operativas de cómo se mantiene esta documentación. Cualquier cambio significativo en el código debe tener su contraparte en `docs/`.

## Build

```bash
export JAVA_HOME="/c/Program Files/Microsoft/jdk-17.0.18.8-hotspot"
export ANDROID_HOME="/c/Android"
export PATH="$JAVA_HOME/bin:/c/tools/flutter/bin:$ANDROID_HOME/cmdline-tools/latest/bin:$PATH"
flutter build apk --release
# Output: build/app/outputs/flutter-apk/app-release.apk (~58 MB)
```

Requiere `keystore/hermes-release.jks` + `android/key.properties` (ambos gitignored). Si no existen, build cae a debug signing con warning. Detalle: [`docs/decisions/ADR-006-release-keystore-propio.md`](docs/decisions/ADR-006-release-keystore-propio.md).

## Convenciones

- **Idioma:** código y docs técnicos en castellano argentino.
- **Commits:** prefijos `feat:` / `fix:` / `refactor:` / `docs:` / `chore:`. Mensajes en castellano.
- **SQL migrations:** todas idempotentes (`IF NOT EXISTS`, `ON CONFLICT`). Viven en `scripts/*.sql`.
- **Servicios:** clases con métodos estáticos en `lib/services/`. Sin instanciación.
- **Side effects:** centralizados en services, no en UI (ver `ActividadesService` como referencia).

## Estructura

```
APK/
├── lib/                          # Código Flutter (Dart)
│   ├── services/                 # Servicios (auth, pg, sql, cronos, calendar, etc)
│   ├── screens/                  # Pantallas (scorecard, agenda, configuración, etc)
│   ├── widgets/                  # Componentes reusables
│   ├── models/                   # Models y DTOs
│   ├── config/                   # constants.dart (gitignored), theme, etc
│   └── main.dart                 # Entry point
├── android/                      # Config Android nativa
│   ├── app/build.gradle.kts      # Lee key.properties para signing release
│   └── key.properties            # Gitignored — credenciales del keystore
├── keystore/                     # Gitignored — RSA 2048 release keystore
├── scripts/                      # Migraciones SQL idempotentes
├── supabase/                     # Edge Functions (Deno) + config CLI
│   └── functions/                # auth-token, cronos-chat, cronos-transcribe
├── docs/                         # Toda la doc viva del proyecto
├── packages/                     # Plugins locales (sql_conn jTDS)
└── pubspec.yaml                  # Dependencias + versión
```

## Repos relacionados

- [Hermes Desktop](https://github.com/guidocameraeq/Teacup) (repo `Teacup`) — admin app Python/CustomTkinter
