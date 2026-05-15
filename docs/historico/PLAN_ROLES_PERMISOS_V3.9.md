# Plan de Implementación — Roles & Permisos en Hermes Mobile (v3.9.0)

**Fecha:** 2026-05-15
**Versión target:** v3.9.0+41
**Goal:** Implementar el contrato de roles + permisos JSONB definido por Hermes Desktop, con 2 gates de acceso (`mobile.access` + `vendedor_nombre` no nulo) y 9 puntos de UI condicional.

**Architecture:** Mobile lee `roles.permisos` (jsonb) y `usuarios.vendedor_nombre` con un JOIN en el login. Carga las keys con `value=true` en `Session.current.permissions` (Set<String>). Cada widget condicionable se envuelve en `if (Session.current.can('...'))`. La Edge Function `auth-token` también lee `vendedor_nombre` de DB (Opción A — single source of truth).

**Tech Stack:** Flutter/Dart + postgres package + Supabase (PostgreSQL + Edge Functions Deno).

**Compatibilidad:** durante la transición, si `vendedor_nombre IS NULL` se usa fallback `username.trim()` para no romper a Leonardo.

---

## Pre-flight — verificación del schema (lo hace Desktop, Mobile valida)

Antes de tocar código, confirmar que la base ya tiene los cambios. Si algo falta, frenar y avisar al user.

- [ ] **Step 0.1: Verificar columna `usuarios.vendedor_nombre`**

Ejecutar (con sandbox normal — es solo SELECT, no toca data):

```bash
export PGHOST='aws-0-us-west-2.pooler.supabase.com' PGPORT=5432 \
       PGDATABASE=postgres PGUSER='postgres.kelipnwleblnpupmlont' \
       PGPASSWORD='hJoG2x1ZCRnLVMCp'
/d/SAAS/VisorFacturacion/venv/Scripts/python.exe -c "
import psycopg2, os
conn = psycopg2.connect(host=os.environ['PGHOST'], port=os.environ['PGPORT'],
    dbname=os.environ['PGDATABASE'], user=os.environ['PGUSER'],
    password=os.environ['PGPASSWORD'], sslmode='require')
cur = conn.cursor()
cur.execute(\"SELECT column_name, data_type, is_nullable FROM information_schema.columns WHERE table_name='usuarios' ORDER BY ordinal_position\")
for r in cur.fetchall(): print(r)
cur.execute(\"SELECT column_name, data_type FROM information_schema.columns WHERE table_name='roles' ORDER BY ordinal_position\")
print('---roles---')
for r in cur.fetchall(): print(r)
"
```

Expected output incluye:
- `('vendedor_nombre', 'text', 'YES')` en usuarios
- `('permisos', 'jsonb', ...)` en roles (no `text`)
- `('updated_at', 'timestamp with time zone', ...)` en roles

Si **no** está, frenar y avisar al user para que lo aplique desde Hermes Desktop antes de continuar.

- [ ] **Step 0.2: Verificar usuarios de prueba**

```bash
/d/SAAS/VisorFacturacion/venv/Scripts/python.exe -c "
import psycopg2, os
conn = psycopg2.connect(host=os.environ['PGHOST'], port=os.environ['PGPORT'],
    dbname=os.environ['PGDATABASE'], user=os.environ['PGUSER'],
    password=os.environ['PGPASSWORD'], sslmode='require')
cur = conn.cursor()
cur.execute(\"SELECT username, role, vendedor_nombre FROM usuarios ORDER BY username\")
for r in cur.fetchall(): print(r)
cur.execute(\"SELECT nombre, permisos->>'mobile.access' AS mob_access FROM roles ORDER BY nombre\")
print('---roles permisos---')
for r in cur.fetchall(): print(r)
"
```

Expected:
- `('Franzo', 'vendedor', 'FRANZO SERGIO')`
- `('TRINCHERI LEONARDO', 'vendedor', 'TRINCHERI LEONARDO')`
- Rol `vendedor` con `mobile.access = 'true'`
- Rol `viewer` con `mobile.access = 'false'` o NULL

---

## Fase 1 — Backend (Edge Function `auth-token`)

Esta fase va primero porque la función queda **compatible con clientes viejos y nuevos**: aún si la app no manda nada nuevo, la función ahora lee `vendedor_nombre` de la DB y lo usa. Eso es la Opción A confirmada.

### Task 1: Edge Function `auth-token` lee `vendedor_nombre` de DB

**Files:**
- Modify: `supabase/functions/auth-token/index.ts:60-89`

- [ ] **Step 1.1: Editar el SELECT y el upsert**

Reemplazar el bloque actual:

```typescript
  const { data: usuario, error } = await sb
    .from('usuarios')
    .select('username, role')
    .ilike('username', username)
    .eq('password_hash', passwordHash)
    .maybeSingle();
```

Por:

```typescript
  const { data: usuario, error } = await sb
    .from('usuarios')
    .select('username, role, vendedor_nombre')
    .ilike('username', username)
    .eq('password_hash', passwordHash)
    .maybeSingle();
```

Y reemplazar:

```typescript
  const token = generateToken();
  const vendedorNombre = (usuario.username as string).trim();
```

Por:

```typescript
  const token = generateToken();
  // Single source of truth: usar vendedor_nombre de la DB.
  // Fallback al username durante la transición (usuarios viejos sin vendedor_nombre cargado).
  const vendedorFromDb = (usuario.vendedor_nombre as string | null)?.trim();
  const vendedorNombre = (vendedorFromDb && vendedorFromDb.length > 0)
    ? vendedorFromDb
    : (usuario.username as string).trim();
```

- [ ] **Step 1.2: Deploy de la función**

```bash
cd /d/SAAS/APK
supabase functions deploy auth-token --no-verify-jwt --project-ref kelipnwleblnpupmlont
```

Expected: `Deployed Function auth-token`.

Si pide login: `supabase login --token <PAT del user en sesión anterior>`.

- [ ] **Step 1.3: Smoke test con curl**

Pedir un token para Franzo (password = el que el user me confirme; placeholder `<PWD_FRANZO>`):

```bash
HASH=$(echo -n "<PWD_FRANZO>" | sha256sum | cut -d' ' -f1)
curl -s -X POST \
  -H "Content-Type: application/json" \
  -d "{\"username\":\"Franzo\",\"password_hash\":\"$HASH\"}" \
  https://kelipnwleblnpupmlont.supabase.co/functions/v1/auth-token
```

Expected JSON: `{"token":"<64hex>","vendedor_nombre":"FRANZO SERGIO","role":"vendedor"}`.

- [ ] **Step 1.4: Verificar fila en `vendedor_tokens`**

```bash
/d/SAAS/VisorFacturacion/venv/Scripts/python.exe -c "
import psycopg2, os
conn = psycopg2.connect(host=os.environ['PGHOST'], port=os.environ['PGPORT'],
    dbname=os.environ['PGDATABASE'], user=os.environ['PGUSER'],
    password=os.environ['PGPASSWORD'], sslmode='require')
cur = conn.cursor()
cur.execute(\"SELECT vendedor_nombre, LEFT(token, 8) || '...' AS token_prefix, created_at FROM vendedor_tokens ORDER BY created_at DESC LIMIT 5\")
for r in cur.fetchall(): print(r)
"
```

Expected: la última fila debe tener `vendedor_nombre = 'FRANZO SERGIO'` (no `'Franzo'`).

- [ ] **Step 1.5: Commit**

```bash
git add supabase/functions/auth-token/index.ts
git commit -m "$(cat <<'EOF'
feat(auth-token): leer vendedor_nombre de DB con fallback a username

La Edge Function ahora resuelve vendedor_nombre desde la columna
nueva en usuarios, no del body. Single source of truth para el
campo que se loggea en vendedor_tokens y uso_llm. Fallback al
username durante la transición.

Refs ADR-008 (en preparación).

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Fase 2 — Auth core en Mobile (sin UI todavía)

### Task 2: Extender `PgService.verifyUser()` para devolver más campos

**Files:**
- Modify: `lib/services/pg_service.dart:35-47`

- [ ] **Step 2.1: Reemplazar `verifyUser()` por una versión nueva**

Reemplazar el método actual (líneas 35-47) por:

```dart
  /// Verifica credenciales y devuelve role + vendedor_nombre + permisos del rol.
  /// Retorna null si las credenciales son inválidas.
  ///
  /// `permisos` es un Map con todas las keys del rol; el caller decide cuáles
  /// considerar "habilitadas" (típicamente las que tienen value true).
  static Future<({String role, String? vendedorNombre, Map<String, dynamic> permisos})?>
      verifyUser(String username, String hash) async {
    final conn = await _getConn();
    final result = await conn.execute(
      Sql.named(
        'SELECT u.role, u.vendedor_nombre, COALESCE(r.permisos, \'{}\'::jsonb) AS permisos '
        'FROM usuarios u '
        'LEFT JOIN roles r ON r.nombre = u.role '
        'WHERE LOWER(u.username) = LOWER(@user) AND u.password_hash = @hash',
      ),
      parameters: {'user': username.trim(), 'hash': hash},
    );
    if (result.isEmpty) return null;
    final row = result.first.toColumnMap();
    final permisosRaw = row['permisos'];
    final Map<String, dynamic> permisos = permisosRaw is Map
        ? Map<String, dynamic>.from(permisosRaw)
        : <String, dynamic>{};
    return (
      role: (row['role'] as String?) ?? '',
      vendedorNombre: row['vendedor_nombre'] as String?,
      permisos: permisos,
    );
  }
```

- [ ] **Step 2.2: Verificar `flutter analyze`**

```bash
cd /d/SAAS/APK
flutter analyze --no-fatal-infos lib/services/pg_service.dart
```

Expected: `No issues found!` (puede haber warnings de `withOpacity` en otros archivos — ignorar). El archivo `auth_service.dart` puede dar error porque la signatura de `verifyUser` cambió — eso lo arreglamos en Task 4.

### Task 3: Extender `Session` con permisos

**Files:**
- Modify: `lib/models/session.dart` (rewrite completo)

- [ ] **Step 3.1: Reemplazar el archivo completo**

```dart
/// Sesión del usuario actualmente logueado.
/// Se puebla al hacer login y se limpia al cerrar sesión.
class Session {
  static Session? _instance;

  String username = '';
  String vendedorNombre = '';
  String role = '';

  Set<String> _permissions = const <String>{};

  Session._();

  static Session get current {
    _instance ??= Session._();
    return _instance!;
  }

  void set({
    required String username,
    required String vendedorNombre,
    required String role,
    Map<String, dynamic> permisos = const <String, dynamic>{},
  }) {
    this.username = username;
    this.vendedorNombre = vendedorNombre;
    this.role = role;
    _permissions = permisos.entries
        .where((e) => e.value == true)
        .map((e) => e.key)
        .toSet();
  }

  void clear() {
    username = '';
    vendedorNombre = '';
    role = '';
    _permissions = const <String>{};
  }

  bool get isLoggedIn => username.isNotEmpty;

  /// Devuelve true si el rol del usuario tiene la key habilitada.
  /// Si la key no existe en el dict del rol, se asume false (cerrado por defecto).
  bool can(String key) => _permissions.contains(key);
}
```

- [ ] **Step 3.2: Verificar analyze**

```bash
flutter analyze --no-fatal-infos lib/models/session.dart
```

Expected: `No issues found!`.

### Task 4: Modificar `AuthService.login()` con los 2 gates

**Files:**
- Modify: `lib/services/auth_service.dart:25-55`

- [ ] **Step 4.1: Reemplazar el bloque del try**

Reemplazar todo el bloque entre `try {` (línea 25) y `} catch (e) {` (línea 50) por:

```dart
    try {
      final hash = hashPassword(password);
      final auth = await PgService.verifyUser(username, hash);

      if (auth == null) {
        return (ok: false, errorMsg: 'Usuario o contraseña incorrectos.');
      }

      // Gate 1: el rol debe tener mobile.access habilitado.
      final permisos = auth.permisos;
      if (permisos['mobile.access'] != true) {
        return (
          ok: false,
          errorMsg: 'Tu rol no tiene acceso a Hermes Mobile.\nContactá al administrador.',
        );
      }

      // Gate 2: debe haber un vendedor asignado.
      // Fallback al username durante la transición (usuarios viejos sin vendedor_nombre).
      final vnDb = auth.vendedorNombre?.trim();
      final vendedorEfectivo = (vnDb != null && vnDb.isNotEmpty)
          ? vnDb
          : username.trim();

      if (vendedorEfectivo.isEmpty) {
        return (
          ok: false,
          errorMsg: 'Tu usuario no tiene un vendedor asignado.\nContactá al administrador.',
        );
      }

      Session.current.set(
        username: username.trim(),
        vendedorNombre: vendedorEfectivo,
        role: auth.role,
        permisos: permisos,
      );

      // Pedir un token de proxy al server. Si falla, no rompemos el login —
      // Cronos no funciona pero el resto de la app sí. El user re-loguea
      // cuando vuelva conectividad y se reintenta.
      await AuthTokenService.requestNewToken(
        username: username.trim(),
        passwordHash: hash,
      );

      return (ok: true, errorMsg: '');
    } catch (e) {
```

- [ ] **Step 4.2: Verificar analyze de toda la app**

```bash
flutter analyze --no-fatal-infos
```

Expected: `No issues found!` (warnings menores OK). Si hay errores en otros archivos por la signatura de `verifyUser`, no debería — solo se llama desde `auth_service.dart`.

- [ ] **Step 4.3: Build APK para confirmar que compila**

```bash
export JAVA_HOME="/c/Program Files/Microsoft/jdk-17.0.18.8-hotspot"
export PATH="$JAVA_HOME/bin:/c/tools/flutter/bin:/c/Android/cmdline-tools/latest/bin:$PATH"
export ANDROID_HOME="/c/Android"
flutter build apk --debug
```

Expected: `Built build/app/outputs/flutter-apk/app-debug.apk`. (Usamos debug para iterar rápido; release lo dejamos para el final.)

- [ ] **Step 4.4: Commit del bloque auth**

```bash
git add lib/services/pg_service.dart lib/models/session.dart lib/services/auth_service.dart
git commit -m "$(cat <<'EOF'
feat(auth): integrar gates mobile.access + vendedor_nombre + permisos en Session

- PgService.verifyUser ahora hace JOIN con roles y devuelve role,
  vendedor_nombre y el dict permisos (jsonb).
- Session expone Set<String> _permissions y helper can(key).
- AuthService.login aplica 2 gates antes de poblar Session:
  1) permisos['mobile.access'] debe ser true.
  2) vendedor_nombre no nulo (fallback al username durante transición).
- Mensajes de error específicos por cada gate.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Fase 3 — UI condicional: Tabs

### Task 5: `home_screen.dart` construye tabs según `mobile.tab_*`

**Files:**
- Modify: `lib/screens/home_screen.dart` (rewrite del state)

- [ ] **Step 5.1: Reemplazar la lista const de `_tabs` por construcción dinámica**

Reemplazar líneas 18-26 (`class _HomeScreenState extends State<HomeScreen> { ... final _tabs = const ...`) por:

```dart
class _HomeScreenState extends State<HomeScreen> {
  int _currentIndex = 0;

  late final List<_TabSpec> _visibleTabs;

  @override
  void initState() {
    super.initState();
    _visibleTabs = _buildVisibleTabs();
    HomeController.register((i) {
      if (mounted && i < _visibleTabs.length) setState(() => _currentIndex = i);
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final pending = NotificationService.pendingActividadId;
      if (pending != null && mounted) {
        NotificationService.pendingActividadId = null;
        Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => ActividadDetailScreen(actividadId: pending),
        ));
      }
    });
  }

  List<_TabSpec> _buildVisibleTabs() {
    final s = Session.current;
    final tabs = <_TabSpec>[];
    if (s.can('mobile.tab_scorecard')) {
      tabs.add(_TabSpec(
        screen: const ScorecardTab(),
        item: const BottomNavigationBarItem(
          icon: Icon(Icons.bar_chart_rounded),
          label: 'Scorecard',
        ),
      ));
    }
    if (s.can('mobile.tab_cronos')) {
      tabs.add(_TabSpec(
        screen: const AssistantScreen(),
        item: BottomNavigationBarItem(
          icon: _cronosNavIcon(AppColors.navUnselected),
          activeIcon: _cronosNavIcon(AppColors.navSelected),
          label: 'Cronos',
        ),
      ));
    }
    if (s.can('mobile.tab_clientes')) {
      tabs.add(_TabSpec(
        screen: const ClientesTab(),
        item: const BottomNavigationBarItem(
          icon: Icon(Icons.people_outline),
          label: 'Clientes',
        ),
      ));
    }
    if (s.can('mobile.tab_acciones')) {
      tabs.add(_TabSpec(
        screen: const AccionesTab(),
        item: const BottomNavigationBarItem(
          icon: Icon(Icons.apps),
          label: 'Acciones',
        ),
      ));
    }
    return tabs;
  }
```

- [ ] **Step 5.2: Reemplazar el `build()` para usar `_visibleTabs`**

Reemplazar el método `build()` (línea 52 en adelante) por:

```dart
  @override
  Widget build(BuildContext context) {
    if (_visibleTabs.isEmpty) {
      // Edge case: rol con mobile.access pero sin ninguna tab habilitada.
      return const Scaffold(
        backgroundColor: AppColors.bg,
        body: Center(
          child: Padding(
            padding: EdgeInsets.all(32),
            child: Text(
              'Tu rol no tiene ninguna pantalla habilitada.\nContactá al administrador.',
              textAlign: TextAlign.center,
              style: AppTextStyles.body,
            ),
          ),
        ),
      );
    }
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: IndexedStack(
        index: _currentIndex,
        children: _visibleTabs.map((t) => t.screen).toList(),
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (i) => setState(() => _currentIndex = i),
        type: BottomNavigationBarType.fixed,
        items: _visibleTabs.map((t) => t.item).toList(),
      ),
    );
  }
```

- [ ] **Step 5.3: Agregar la clase `_TabSpec` al final del archivo**

Antes del cierre del archivo (después del último `}`), agregar:

```dart
class _TabSpec {
  final Widget screen;
  final BottomNavigationBarItem item;
  const _TabSpec({required this.screen, required this.item});
}
```

- [ ] **Step 5.4: Agregar import de Session**

Al tope del archivo, junto a los otros imports, agregar:

```dart
import '../models/session.dart';
import '../config/text_styles.dart';
```

(Si `text_styles.dart` no existe con ese path, buscar dónde vive `AppTextStyles` y usar el path correcto. Está usado en otros screens — el de configuracion_screen.dart importa de '../config/theme.dart'. Adaptar.)

- [ ] **Step 5.5: Verificar analyze + build**

```bash
flutter analyze --no-fatal-infos lib/screens/home_screen.dart
flutter build apk --debug
```

- [ ] **Step 5.6: Commit**

```bash
git add lib/screens/home_screen.dart
git commit -m "$(cat <<'EOF'
feat(home): construir bottom nav tabs según mobile.tab_* permisos

Cada tab del bottom nav (Scorecard, Cronos, Clientes, Acciones) se
muestra solo si el rol tiene la key correspondiente. Si el rol no tiene
ninguna tab habilitada, se muestra un mensaje en lugar de un Scaffold vacío.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Fase 4 — UI condicional: Actividades

### Task 6: `cliente_detail_screen.dart` — botón "Cargar actividad"

**Files:**
- Modify: `lib/screens/cliente_detail_screen.dart:168-193`

- [ ] **Step 6.1: Envolver el segundo `_QuickActionBtn` en un if**

Reemplazar el método `_buildQuickActions()` (líneas 168-193) por:

```dart
  Widget _buildQuickActions(Cliente c) {
    final canCrear = Session.current.can('mobile.action.crear_actividad');
    return Row(
      children: [
        Expanded(
          child: _QuickActionBtn(
            icon: Icons.category,
            label: 'Análisis de líneas',
            onTap: () => Navigator.push(context, MaterialPageRoute(
              builder: (_) => LineasAnalysisScreen(
                clienteCodigo: c.codigo,
                clienteNombre: c.nombre,
              ),
            )),
          ),
        ),
        if (canCrear) ...[
          const SizedBox(width: 8),
          Expanded(
            child: _QuickActionBtn(
              icon: Icons.add_circle_outline,
              label: 'Cargar actividad',
              onTap: () => _openActividadForm(c),
            ),
          ),
        ],
      ],
    );
  }
```

- [ ] **Step 6.2: Asegurar el import de Session**

Al tope del archivo, si no está, agregar:

```dart
import '../models/session.dart';
```

### Task 7: `cliente_detail_screen.dart` — secciones de datos sensibles

- [ ] **Step 7.1: Envolver Saldo CxC y Facturas con permisos**

En `build()` (líneas 110-145), reemplazar el bloque con `widget.cliente.saldo > 0` y `_saldoDocs.isNotEmpty` por uno que también chequee permisos:

```dart
                  _buildHeader(c),
                  const SizedBox(height: 12),
                  _buildQuickActions(c),
                  const SizedBox(height: 16),
                  if (Session.current.can('mobile.data.saldo_cxc') &&
                      widget.cliente.saldo > 0) ...[
                    _buildSaldoCard(),
                    const SizedBox(height: 16),
                  ],
                  _buildLineasResumen(c),
                  const SizedBox(height: 16),
                  HistoriaClinica(
                    entries: _timeline.take(10).toList(),
                    onVerMas: _timeline.length > 10 ? () {} : null,
                    onCompletar: _completarActividad,
                    onTap: (id) async {
                      await Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => ActividadDetailScreen(actividadId: id),
                        ),
                      );
                      if (mounted) _load();
                    },
                  ),
                  const SizedBox(height: 16),
                  _buildEvolucion(),
                  const SizedBox(height: 16),
                  if (Session.current.can('mobile.data.facturas_pendientes')) ...[
                    _buildFacturas(),
                    if (_saldoDocs.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      _buildSaldoDetalle(),
                    ],
                  ],
                  const SizedBox(height: 32),
```

- [ ] **Step 7.2: Verificar analyze + build**

```bash
flutter analyze --no-fatal-infos lib/screens/cliente_detail_screen.dart
flutter build apk --debug
```

- [ ] **Step 7.3: Commit Tasks 6 + 7**

```bash
git add lib/screens/cliente_detail_screen.dart
git commit -m "$(cat <<'EOF'
feat(cliente_detail): condicionar acciones y datos sensibles según permisos

- Botón "Cargar actividad" solo visible si mobile.action.crear_actividad.
- Sección Saldo CxC solo visible si mobile.data.saldo_cxc.
- Sección Facturas pendientes (resumen + detalle) solo visible si
  mobile.data.facturas_pendientes.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

### Task 8: `actividad_detail_screen.dart` — botones completar y eliminar

**Files:**
- Modify: `lib/screens/actividad_detail_screen.dart:341-353` (AppBar) y `:488-503` (botón completar)

- [ ] **Step 8.1: Envolver el IconButton "Eliminar" en condicional**

Reemplazar el bloque `actions: [...]` del AppBar (línea 346-352) por:

```dart
        actions: [
          if (Session.current.can('mobile.action.eliminar_actividad'))
            IconButton(
              icon: const Icon(Icons.delete_outline, color: AppColors.danger),
              onPressed: _eliminar,
              tooltip: 'Eliminar',
            ),
        ],
```

- [ ] **Step 8.2: Envolver el botón "Marcar como completada" / "Reabrir"**

Reemplazar el bloque del botón (líneas 488-503) por:

```dart
                    if (Session.current.can('mobile.action.completar_actividad')) ...[
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        height: 48,
                        child: ElevatedButton.icon(
                          onPressed: _toggleCompletada,
                          icon: Icon(_esCompletada ? Icons.replay : Icons.check, size: 20),
                          label: Text(_esCompletada ? 'Reabrir actividad' : 'Marcar como completada',
                              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _esCompletada ? AppColors.textMuted : AppColors.success,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                        ),
                      ),
                    ],
```

(Nota: el `const SizedBox(height: 12)` queda dentro del `if` también para que cuando no haya botón no se dibuje el espacio extra arriba.)

- [ ] **Step 8.3: Asegurar el import de Session**

Al tope, si no está:

```dart
import '../models/session.dart';
```

- [ ] **Step 8.4: Verificar y commit**

```bash
flutter analyze --no-fatal-infos lib/screens/actividad_detail_screen.dart
flutter build apk --debug
git add lib/screens/actividad_detail_screen.dart
git commit -m "$(cat <<'EOF'
feat(actividad_detail): condicionar botones eliminar y completar/reabrir

- IconButton de eliminar en AppBar solo visible si mobile.action.eliminar_actividad.
- Botón Marcar como completada/Reabrir solo visible si mobile.action.completar_actividad.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Fase 5 — UI condicional: resto

### Task 9: `acciones_tab.dart` — Tile "Registrar visita"

**Files:**
- Modify: `lib/screens/acciones_tab.dart:111-132`

- [ ] **Step 9.1: Envolver el Tile en condicional**

Reemplazar el bloque actual del primer `Row` de Campo (líneas 112-122) por:

```dart
            _section('Campo'),
            Row(children: [
              if (Session.current.can('mobile.action.registrar_visita')) ...[
                Expanded(child: _Tile(
                  icon: Icons.add_location_alt,
                  label: 'Registrar visita',
                  color: AppColors.success,
                  onTap: () async {
                    await Navigator.push(context, MaterialPageRoute(
                      builder: (_) => const VisitaClientePickerScreen()));
                    _loadVisitasHoy();
                  },
                )),
                const SizedBox(width: 8),
              ],
              Expanded(child: _Tile(
                icon: Icons.location_on,
                label: 'Mis visitas',
                color: AppColors.accent,
                badge: _visitasHoy > 0 ? '$_visitasHoy hoy' : null,
                onTap: () => Navigator.push(context, MaterialPageRoute(
                    builder: (_) => const MisVisitasScreen())),
              )),
            ]),
```

(Decisión: "Mis visitas" sigue visible aunque no pueda registrar, porque es solo lectura de su historial.)

- [ ] **Step 9.2: Asegurar import de Session**

```dart
import '../models/session.dart';
```

### Task 10: `assistant_screen.dart` — botón micrófono

**Files:**
- Modify: `lib/screens/assistant_screen.dart:1227-1290`

- [ ] **Step 10.1: Agregar parámetro `canVoice` al `_InputBar`**

Reemplazar el bloque de `class _InputBar` (líneas 1227-1290) por:

```dart
/// Barra de input que alterna entre mic (sin texto) y send (con texto).
/// Si `canVoice` es false, siempre muestra el botón Send (deshabilitado si no hay texto)
/// y el hint cambia para no mencionar el micrófono.
class _InputBar extends StatelessWidget {
  final TextEditingController controller;
  final bool hasText;
  final bool disabled;
  final bool canVoice;
  final VoidCallback onSend;
  final VoidCallback onMic;

  const _InputBar({
    required this.controller,
    required this.hasText,
    required this.disabled,
    required this.canVoice,
    required this.onSend,
    required this.onMic,
  });

  @override
  Widget build(BuildContext context) {
    final hintText = canVoice
        ? (hasText ? 'Escribí tu mensaje...' : 'Escribí o tocá el micrófono')
        : 'Escribí tu mensaje...';
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 12),
      decoration: const BoxDecoration(
        color: AppColors.bgSidebar,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: controller,
                style: AppTextStyles.body,
                minLines: 1,
                maxLines: 4,
                enabled: !disabled,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => onSend(),
                decoration: InputDecoration(
                  hintText: hintText,
                  hintStyle: AppTextStyles.muted,
                  filled: true,
                  fillColor: AppColors.bgCard,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(22),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                ),
              ),
            ),
            const SizedBox(width: 8),
            // Si no puede usar voz, siempre Send (disabled si no hay texto).
            // Si puede usar voz, alterna entre Mic y Send según haya texto.
            if (!canVoice)
              _SendBtn(onTap: (disabled || !hasText) ? null : onSend)
            else
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 220),
                transitionBuilder: (w, a) => ScaleTransition(scale: a, child: w),
                child: hasText
                    ? _SendBtn(onTap: disabled ? null : onSend, key: const ValueKey('send'))
                    : _MicBtn(onTap: disabled ? null : onMic, key: const ValueKey('mic')),
              ),
          ],
        ),
      ),
    );
  }
}
```

- [ ] **Step 10.2: Pasar `canVoice` desde el caller del `_InputBar`**

Buscar dónde se instancia `_InputBar(...)` en el archivo (con `Grep _InputBar(` o `_InputBar\\(`) y agregar el parámetro nuevo. Probablemente está en el `build()` del state principal de `AssistantScreen`. Agregar:

```dart
            _InputBar(
              controller: _ctrl,
              hasText: _hasText,
              disabled: _sending || _transcribing,
              canVoice: Session.current.can('mobile.action.cronos_voice'),
              onSend: _send,
              onMic: _recordAndTranscribe,
            ),
```

(Adaptar nombres de variables a los reales del archivo.)

- [ ] **Step 10.3: Asegurar import de Session**

```dart
import '../models/session.dart';
```

- [ ] **Step 10.4: Verificar analyze + build**

```bash
flutter analyze --no-fatal-infos lib/screens/assistant_screen.dart
flutter build apk --debug
```

### Task 11: `configuracion_screen.dart` — feedback + Calendar

**Files:**
- Modify: `lib/screens/configuracion_screen.dart:241-289`

- [ ] **Step 11.1: Envolver Calendar card y Feedback en condicionales**

Reemplazar el bloque de las líneas 240-289 (las secciones Google Calendar y Feedback) por:

```dart
          if (Session.current.can('mobile.google_calendar.sync')) ...[
            const SizedBox(height: 14),
            // ── Google Calendar ──────────────────────────────
            _buildCalendarCard(),
          ],

          const SizedBox(height: 14),

          // ── App ─────────────────────────────────────────
          Container(
            padding: const EdgeInsets.all(16),
            decoration: AppCardStyle.base(),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Aplicación', style: AppTextStyles.title),
                const SizedBox(height: 10),
                _row('Versión', 'v$_appVersion'),
                const _Row('Plataforma', 'Android'),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: _checkingUpdate ? null : _checkUpdate,
                    icon: _checkingUpdate
                        ? const SizedBox(width: 16, height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.accent))
                        : const Icon(Icons.system_update, size: 18),
                    label: Text(_checkingUpdate
                        ? 'Buscando...'
                        : _updateAvailable != null
                            ? 'Actualización disponible'
                            : 'Estás al día'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: _updateAvailable != null ? AppColors.success : AppColors.textMuted,
                      side: BorderSide(
                        color: _updateAvailable != null
                            ? AppColors.success.withOpacity(0.5)
                            : AppColors.border,
                      ),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                  ),
                ),
              ],
            ),
          ),

          if (Session.current.can('mobile.action.dar_feedback')) ...[
            const SizedBox(height: 14),
            // ── Feedback ────────────────────────────────────
            _expandable('Enviar feedback', Icons.chat_bubble_outline, _buildFeedbackBody()),
          ],
```

- [ ] **Step 11.2: Verificar analyze + build**

```bash
flutter analyze --no-fatal-infos lib/screens/configuracion_screen.dart
flutter build apk --debug
```

- [ ] **Step 11.3: Commit Tasks 9 + 10 + 11**

```bash
git add lib/screens/acciones_tab.dart lib/screens/assistant_screen.dart lib/screens/configuracion_screen.dart
git commit -m "$(cat <<'EOF'
feat(ui): condicionar visita, mic Cronos, feedback y Calendar según permisos

- acciones_tab: tile "Registrar visita" solo si mobile.action.registrar_visita.
- assistant_screen: _InputBar acepta canVoice. Si false, siempre Send y
  hint sin mención al micrófono. Lee Session.can('mobile.action.cronos_voice').
- configuracion_screen: card Google Calendar solo si mobile.google_calendar.sync;
  feedback expandable solo si mobile.action.dar_feedback.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Fase 6 — Documentación

### Task 12: ADR-008 documentando el patrón

**Files:**
- Create: `docs/decisions/ADR-008-roles-permisos-jsonb.md`

- [ ] **Step 12.1: Crear el archivo ADR-008**

```markdown
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
```

### Task 13: `ARCHITECTURE.md` §12 nuevo

**Files:**
- Modify: `docs/ARCHITECTURE.md` (agregar al final)

- [ ] **Step 13.1: Agregar sección §12 al final del archivo**

Antes del bloque `## Anti-patterns a evitar` final, insertar:

```markdown
---

## 12. Roles y permisos via Session.can()

**Archivos:** `lib/services/auth_service.dart`, `lib/models/session.dart`, `lib/services/pg_service.dart`, `supabase/functions/auth-token/index.ts`

**Patrón introducido en v3.9.0** para integrar el sistema de roles compartido con Hermes Desktop.

### Flujo

```
1. Login: pg_service.verifyUser hace JOIN usuarios + roles, devuelve
   (role, vendedor_nombre, permisos) en una sola query.
2. AuthService.login aplica 2 gates:
   a) permisos['mobile.access'] debe ser true.
   b) vendedor_nombre debe estar presente (fallback al username durante transición).
3. Si pasan los gates, Session.set(permisos: ...) carga las keys con
   value=true en _permissions.
4. Cualquier widget con sensibilidad de permiso usa Session.current.can(key).
5. La Edge Function auth-token también lee vendedor_nombre de la DB
   (no del body) para emitir el token correctamente.
```

### Por qué

El admin del negocio (Hermes Desktop) gestiona roles centralmente. Mobile debía:
- Bloquear acceso a usuarios sin permiso (`mobile.access`).
- Resolver el `vendedor_nombre` real (no asumir `== username`).
- Mostrar/ocultar features según el rol sin recompilar.

Ver [ADR-008](decisions/ADR-008-roles-permisos-jsonb.md) para razones completas y alternativas descartadas.

### Aplicación

- **Cualquier feature nueva con sensibilidad de permiso** debe envolverse en `if (Session.current.can('mobile.xxx'))`. La key se registra en `permisos_catalog` desde Desktop.
- **Nunca asumir que `username == vendedor_nombre`**. Para cualquier query que filtre por vendedor, usar `Session.current.vendedorNombre`.
- **Para revocar acceso a un usuario**: el admin baja el flag en Desktop. La revocación se aplica al próximo login (no instantánea).
- **Si una key no está en el dict del rol, `can()` devuelve false** (cerrado por defecto). Esto significa que agregar permisos nuevos no rompe roles existentes.

### Anti-patterns para este patrón

- ❌ Usar `Session.current.username` para filtrar queries de datos del vendedor (usar `vendedorNombre`).
- ❌ Mostrar el botón en gris cuando no hay permiso (mejor: no mostrarlo).
- ❌ Hardcodear permisos en el código (deben venir del rol, no del username).
- ❌ Enviar `vendedor_nombre` a la Edge Function desde el cliente (la función debe leerlo de DB).
- ❌ Cachear `_permissions` fuera de Session (la verdad vive ahí).
```

### Task 14: Actualizar STATUS, TODO, CHANGELOG, master-plan.html

- [ ] **Step 14.1: Actualizar `docs/STATUS.md`**

Cambiar la fecha del snapshot a 2026-05-15, versión actual a v3.9.0+41, agregar fila a la tabla de bloques:

```markdown
| **Roles y permisos** (extra) | Sistema de permisos jsonb + 2 gates de acceso + UI condicional | ✅ Completo | v3.9.0 |
```

Y agregar sección al inicio (después de v3.8.0):

```markdown
## v3.9.0 — Roles y permisos JSONB + UI condicional

Integración del sistema de roles compartido con Hermes Desktop.

**Componentes:**
- Query de login con JOIN a `roles` para traer permisos en jsonb
- 2 gates: `mobile.access` + `vendedor_nombre` no nulo
- `Session.can(key)` consultable desde cualquier widget
- 9 puntos de UI condicionados (4 tabs + 5 acciones/secciones)
- Edge Function `auth-token` también lee `vendedor_nombre` de DB

**Verificación:**
- Login con Franzo (username ≠ vendedor_nombre) entra y carga datos de FRANZO SERGIO
- Login con viewer es rechazado con mensaje específico
- Cambios de permisos en Desktop se aplican al próximo login
```

- [ ] **Step 14.2: Actualizar `docs/TODO.md`**

Mover a "Completadas recientemente":

```markdown
- ✅ **2026-05-15** Sistema de roles + permisos JSONB integrado (v3.9.0). 2 gates de acceso, 9 puntos de UI condicional, ADR-008 creado.
```

Y agregar como tarea 🟡 (no urgente) en su categoría:

```markdown
### Quitar fallback de transición `vendedor_nombre ?? username`
- **Qué:** una vez confirmado que todos los usuarios productivos tienen `vendedor_nombre` cargado, remover el fallback en `auth_service.dart` y `auth-token/index.ts`. Que falle explícito si falta.
- **Por qué:** el fallback fue para no romper a Leonardo durante la migración. Ya cumplió su rol.
- **Cuándo:** después de 2-4 semanas con v3.9.0 estable.
- **Esfuerzo:** 15 min (2 líneas de código + redeploy de Edge Function).
- **Origen:** ADR-008.
```

- [ ] **Step 14.3: Actualizar `docs/CHANGELOG.md`**

Agregar al tope:

```markdown
## [2026-05-15] — Roles + permisos JSONB (v3.9.0)
**Versión publicada:** v3.9.0
**Trabajo:**
- Edge Function `auth-token` ahora lee `vendedor_nombre` de DB (Opción A — single source of truth).
- `PgService.verifyUser` reescrito para devolver record con (role, vendedor_nombre, permisos) en una sola query con JOIN a `roles`.
- `Session` extendido con `_permissions` (Set<String>) y helper `can(key)`.
- `AuthService.login` aplica 2 gates: `mobile.access` y `vendedor_nombre` no nulo (con fallback transitorio al username).
- 9 puntos de UI condicionados: 4 tabs + crear/completar/eliminar actividad + registrar visita + mic Cronos + feedback + Saldo CxC + facturas + Calendar.
**Decisiones:** ADR-008 (roles + permisos JSONB con gates).
**Próximo paso:** validar con los 6 casos de prueba en device + activar force update a 3.9.0 cuando OK.
```

- [ ] **Step 14.4: Actualizar `docs/master-plan.html`**

Aplicar el patrón documentado en `COMPACTION_PROTOCOL.md` §6 — actualizar:
- Header version → v3.9.0
- §2 timeline → nuevo item v3.9.0
- §3.0 panorámica → nueva fila "Roles y permisos"
- §19 → quitar tareas que se completaron, agregar "Quitar fallback transitorio"
- §23 → agregar fila ADR-008
- Stats panel → +1 release
- Footer → versión actual

Verificar item-por-item con queries bash de `COMPACTION_PROTOCOL.md` §6.A.

- [ ] **Step 14.5: Actualizar `docs/decisions/README.md`**

Agregar fila al índice:

```markdown
| [008](ADR-008-roles-permisos-jsonb.md) | Roles y permisos como JSONB con gates de acceso | Aceptado | 2026-05-15 |
```

- [ ] **Step 14.6: Commit de docs**

```bash
git add docs/decisions/ADR-008-roles-permisos-jsonb.md \
        docs/decisions/README.md \
        docs/ARCHITECTURE.md \
        docs/STATUS.md \
        docs/TODO.md \
        docs/CHANGELOG.md \
        docs/master-plan.html
git commit -m "$(cat <<'EOF'
docs: ADR-008 + actualizar status/todo/changelog para v3.9.0

- ADR-008: Roles y permisos como JSONB con 2 gates de acceso.
- ARCHITECTURE.md §12: patrón Session.can() y por qué la Edge Function
  resuelve vendedor_nombre server-side.
- STATUS, TODO, CHANGELOG, master-plan.html actualizados al estado v3.9.0.
- decisions/README.md: índice ampliado.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Fase 7 — Release v3.9.0

### Task 15: Bump de versión + build release

- [ ] **Step 15.1: Bump pubspec**

Editar `pubspec.yaml:19`:

```yaml
version: 3.9.0+41
```

- [ ] **Step 15.2: Build release**

```bash
export JAVA_HOME="/c/Program Files/Microsoft/jdk-17.0.18.8-hotspot"
export PATH="$JAVA_HOME/bin:/c/tools/flutter/bin:/c/Android/cmdline-tools/latest/bin:$PATH"
export ANDROID_HOME="/c/Android"
flutter analyze --no-fatal-infos
flutter build apk --release
```

Expected: `Built build/app/outputs/flutter-apk/app-release.apk (~57 MB)`.

- [ ] **Step 15.3: Validar firma del APK**

```bash
$JAVA_HOME/bin/keytool -printcert -jarfile build/app/outputs/flutter-apk/app-release.apk
```

Expected: `SHA1: 73:9D:EE:58:75:E6:18:B4:3D:6C:DA:49:3B:B7:3C:B0:C9:83:F7:0F` (release keystore).

### Task 16: Tag + GitHub release

- [ ] **Step 16.1: Commit del bump y tag**

```bash
git add pubspec.yaml
git commit -m "$(cat <<'EOF'
chore: bump version to 3.9.0+41

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
git push
git tag -a v3.9.0 -m "Release v3.9.0 — Roles y permisos JSONB"
git push origin v3.9.0
```

- [ ] **Step 16.2: Crear GitHub release con APK**

Usar el flujo de `docs/WORKFLOW.md` (curl + git credential fill). Body:

```
## Roles y permisos integrados con Hermes Desktop

- Login con JOIN a `roles` trae permisos jsonb del rol en una sola query.
- 2 gates obligatorios al loguear:
  • `mobile.access` debe estar habilitado en el rol.
  • Tu usuario debe tener un vendedor asignado.
- 9 puntos de UI ahora respetan permisos: 4 tabs (Scorecard/Cronos/Clientes/Acciones), crear/completar/eliminar actividad, registrar visita, micrófono Cronos, feedback, Saldo CxC, facturas, Calendar.
- Edge Function `auth-token` también lee `vendedor_nombre` de DB para emitir el token con el binding correcto.

Cambios de rol en Hermes Desktop se aplican al próximo login del usuario.

APK: ~57 MB
```

### Task 17: Activar force update post-validación

- [ ] **Step 17.1: NO activar force update todavía**

Esperar a que el user valide los 6 casos en su device (Fase 8).

Cuando confirme OK:

```sql
UPDATE app_config SET value='3.9.0', updated_at=NOW()
WHERE key='min_version_required';
```

---

## Fase 8 — Validación post-release (los 6 casos)

Ejecutar **en device del user con APK v3.9.0 instalado**.

- [ ] **Caso 1 — Login con Leonardo (retro-compat)**
  - Username: `TRINCHERI LEONARDO` / Password: el habitual
  - Expected: entra a la app, ve scorecard con sus datos reales (porque vendedor_nombre = TRINCHERI LEONARDO)
  - Si falla: revisar fila en `usuarios` que tenga vendedor_nombre cargado igual al username

- [ ] **Caso 2 — Login con Franzo (caso nuevo, username ≠ vendedor_nombre)**
  - Username: `Franzo` / Password: el que el user me confirme
  - Expected: entra y ve datos de FRANZO SERGIO en scorecard, clientes, etc
  - Verificación SQL: `SELECT vendedor_nombre FROM vendedor_tokens WHERE token = (token de la sesión)` → debe ser 'FRANZO SERGIO'

- [ ] **Caso 3 — Login con Guido (admin sin vendedor)**
  - Username: `Guido`
  - Expected: rechazo con mensaje "Tu usuario no tiene un vendedor asignado. Contactá al administrador."

- [ ] **Caso 4 — Login con Matias (viewer, sin mobile.access)**
  - Username: `Matias`
  - Expected: rechazo con mensaje "Tu rol no tiene acceso a Hermes Mobile. Contactá al administrador."

- [ ] **Caso 5 — Cronos con Franzo loggea con vendedor correcto**
  - Logueado como Franzo, mandar un mensaje a Cronos
  - Verificación SQL: `SELECT vendedor_nombre, endpoint, status_code, modelo FROM uso_llm ORDER BY created_at DESC LIMIT 3;` → la fila más reciente debe tener `vendedor_nombre = 'FRANZO SERGIO'`

- [ ] **Caso 6 — Edición de rol en Desktop se aplica al re-login**
  - Logueado como Franzo, ver que el botón "Eliminar" actividad no aparece (vendedor por default no tiene `mobile.action.eliminar_actividad`)
  - En Desktop: editar rol `vendedor`, activar `mobile.action.eliminar_actividad`
  - En Mobile: cerrar sesión y volver a entrar con Franzo
  - Expected: ahora el IconButton de eliminar aparece en el AppBar de actividad
  - Volver a desactivarlo en Desktop, re-login → desaparece

---

## Cierre — actualizar SESSION_HANDOFF antes del próximo compact

Cuando todo esté validado y se active el force update, ejecutar el protocolo de `docs/COMPACTION_PROTOCOL.md` para que la próxima sesión sepa que v3.9.0 está estable.

---

## Resumen de archivos tocados

```
NUEVOS:
  docs/decisions/ADR-008-roles-permisos-jsonb.md

MODIFICADOS (código):
  supabase/functions/auth-token/index.ts
  lib/services/pg_service.dart
  lib/models/session.dart
  lib/services/auth_service.dart
  lib/screens/home_screen.dart
  lib/screens/cliente_detail_screen.dart
  lib/screens/actividad_detail_screen.dart
  lib/screens/acciones_tab.dart
  lib/screens/assistant_screen.dart
  lib/screens/configuracion_screen.dart
  pubspec.yaml

MODIFICADOS (docs):
  docs/ARCHITECTURE.md
  docs/STATUS.md
  docs/TODO.md
  docs/CHANGELOG.md
  docs/master-plan.html
  docs/decisions/README.md
```

---

## Riesgos y mitigaciones

| Riesgo | Mitigación |
|---|---|
| Schema en Supabase no aplicado todavía | Pre-flight checks en Step 0.1 frenan si falta algo |
| Usuario sin `vendedor_nombre` cargado se queda afuera | Fallback `vendedor_nombre ?? username` durante transición |
| Tab Cronos oculta para un rol que tenía acceso → no puede pedir token | El gate `mobile.access` es para entrar a la app entera; si entra puede pedir token aunque la tab no esté |
| Cambios de rol en Desktop no se ven hasta próximo login | Documentado al user, opcional revalidar al volver de background en v3.9.1 |
| Edge Function deployada antes que APK → APKs viejos siguen funcionando | OK: Opción A es backwards-compatible (la función ignora el body si no manda nada nuevo) |
| APK v3.9.0 instalado pero Edge Function vieja todavía | Riesgo bajo: el token se sigue emitiendo, solo el `vendedor_nombre` queda con el username viejo. Resolver deployando primero la función (Fase 1 antes de Fase 7) |
