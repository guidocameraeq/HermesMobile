# Hermes Mobile — App Android para Equipo Comercial

## Proyecto
- **Ruta:** `D:\SAAS\APK`
- **Stack:** Flutter (Dart) + SQL Server (jTDS/JDBC via sql_conn) + Supabase/PostgreSQL (postgres package)
- **Punto de entrada:** `lib/main.dart`
- **Build:** `flutter build apk --release` → `build/app/outputs/flutter-apk/app-release.apk`
- **Min SDK Android:** 26 (Android 8+)
- **Java:** JDK 17 (`C:\Program Files\Microsoft\jdk-17.0.18.8-hotspot`)

## Relación con Hermes Desktop
- El desktop (`D:\SAAS\VisorFacturacion`) es la app de admin: crea métricas, asigna objetivos, gestiona usuarios
- Esta app mobile es **read-only para vendedores**: muestra los mismos datos
- Ambas comparten las mismas fuentes: Supabase para metas, SQL Server para datos reales
- Los objetivos se sincronizan automáticamente porque leen las mismas tablas

## Arquitectura
```
lib/
├── config/
│   ├── constants.dart         # Credenciales (GITIGNORED)
│   └── constants.example.dart # Template sin credenciales
├── models/
│   ├── session.dart           # Singleton de sesión del usuario
│   └── scorecard_item.dart    # Modelo de métrica (nombre, meta, real, %)
├── services/
│   ├── auth_service.dart      # Login SHA-256 vs Supabase usuarios
│   ├── pg_service.dart        # Conexión directa PostgreSQL (Supabase)
│   ├── sql_service.dart       # Conexión SQL Server via jTDS (VPN)
│   ├── scorecard_service.dart # Orquestador: Supabase targets + SQL Server reales
│   └── calculator_service.dart# Cálculo de métricas (queries SQL)
├── screens/
│   ├── login_screen.dart      # Pantalla de login
│   └── scorecard_screen.dart  # Pantalla principal (scorecard)
└── widgets/
    └── metric_card.dart       # Tarjeta de métrica reutilizable
```

## Conexiones

### SQL Server (red interna — requiere VPN)
- Driver: jTDS 1.3.1 via `packages/sql_conn/` (paquete local modificado)
- Connection string: `jdbc:jtds:sqlserver://IP:PORT/DB;instance=INSTANCIA;ssl=off`
- Tablas: `fydvtsEstadisticas`, `fydvtsClientesXLinea`, `fydvtsPedidos`
- Solo lectura, queries parametrizadas con `?`

### Supabase PostgreSQL (cloud — sin VPN)
- Paquete: `postgres` (conexión directa, no REST API)
- Tablas: `usuarios`, `metricas_pool`, `asignaciones`, `cuotas_clientes`, `analytics`

## Credenciales
- `lib/config/constants.dart` está en `.gitignore` — NUNCA commitear
- `constants.example.dart` es el template para nuevos clones
- Las credenciales están hardcodeadas en el APK compilado (aceptable para app interna)

## Patrones
- **Services:** Clases estáticas con métodos `Future<T>` — sin instanciación
- **Session:** Singleton `Session.current` con username, vendedorNombre, role
- **Queries SQL Server:** Usar `?` como placeholder (estilo JDBC), pasar `List<Object?>` como params
- **Queries PostgreSQL:** Usar `@param` como placeholder (estilo postgres package)
- **Errores:** `SqlService.lastError` guarda el último error para diagnóstico
- **Métricas:** `CalculatorService.calcular(funcionId, vendedor, mes, anio, paramsJson)` → `(double, String)`

## Métricas implementadas
| funcionId | Descripción |
|-----------|-------------|
| facturacion | Facturas (2205) - NC (2206) |
| aperturas | Clientes que compraron por primera vez |
| tasa_conversion | % clientes activos que compraron |
| reactivacion | Clientes inactivos >N días que compraron |
| foco_unidades | SUM unidades/importe de artículos específicos |
| incorporaciones | Alias de foco_unidades |

## Build
```bash
export JAVA_HOME="/c/Program Files/Microsoft/jdk-17.0.18.8-hotspot"
export ANDROID_HOME="/c/Android"
export PATH="$JAVA_HOME/bin:/c/tools/flutter/bin:$ANDROID_HOME/cmdline-tools/latest/bin:$PATH"
flutter build apk --release
```

## IDE
- El IDE NO tiene el SDK de Flutter configurado → los errores de análisis son falsos positivos
- Verificar sintaxis con: `flutter analyze`
