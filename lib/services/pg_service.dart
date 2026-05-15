import 'dart:convert';
import 'package:postgres/postgres.dart';
import '../config/constants.dart';

/// Conexión directa a Supabase via PostgreSQL (psycopg2-equivalent en Dart).
/// NO requiere VPN — Supabase es cloud.
class PgService {
  static Connection? _conn;

  static Future<Connection> _getConn() async {
    if (_conn != null) {
      try {
        await _conn!.execute('SELECT 1');
        return _conn!;
      } catch (_) {
        _conn = null;
      }
    }
    _conn = await Connection.open(
      Endpoint(
        host: AppConfig.pgHost,
        port: AppConfig.pgPort,
        database: AppConfig.pgDb,
        username: AppConfig.pgUser,
        password: AppConfig.pgPass,
      ),
      settings: const ConnectionSettings(sslMode: SslMode.require),
    );
    // Forzar timezone Argentina para que CURRENT_DATE y ::date resuelvan
    // en hora local del vendedor, no UTC del server.
    // Sin esto, una actividad a las 23:00 AR mostraría fuera de filtro "hoy".
    await _conn!.execute("SET TIME ZONE 'America/Argentina/Buenos_Aires'");
    return _conn!;
  }

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
        // Cast a text en la query: agnóstico al tipo de la columna permisos
        // (text o jsonb). El resultado siempre es String JSON; el cliente
        // hace jsonDecode. Evita el COALESCE de tipos mixtos.
        'SELECT u.role, u.vendedor_nombre, COALESCE(r.permisos::text, \'{}\') AS permisos '
        'FROM usuarios u '
        'LEFT JOIN roles r ON r.nombre = u.role '
        'WHERE LOWER(u.username) = LOWER(@user) AND u.password_hash = @hash',
      ),
      parameters: {'user': username.trim(), 'hash': hash},
    );
    if (result.isEmpty) return null;
    final row = result.first.toColumnMap();
    // jsonb llega como String desde el package postgres (Dart). Defensivo:
    // si por alguna razón ya viene como Map (driver futuro), también lo soporta.
    final permisosRaw = row['permisos'];
    final Map<String, dynamic> permisos;
    if (permisosRaw is Map) {
      permisos = Map<String, dynamic>.from(permisosRaw);
    } else if (permisosRaw is String && permisosRaw.isNotEmpty) {
      final decoded = jsonDecode(permisosRaw);
      permisos = decoded is Map
          ? Map<String, dynamic>.from(decoded)
          : <String, dynamic>{};
    } else {
      permisos = <String, dynamic>{};
    }
    return (
      role: (row['role'] as String?) ?? '',
      vendedorNombre: row['vendedor_nombre'] as String?,
      permisos: permisos,
    );
  }

  /// Trae las asignaciones del vendedor para el mes/año dado,
  /// joinando metricas_pool para obtener nombre, funcion_id, etc.
  static Future<List<Map<String, dynamic>>> getAsignaciones(
    String vendedor,
    int mes,
    int anio,
  ) async {
    final conn = await _getConn();
    final result = await conn.execute(
      Sql.named('''
        SELECT a.id, a.valor_meta,
               m.id        AS metrica_id,
               COALESCE(a.alias, m.nombre) AS nombre,
               m.descripcion,
               m.tipo_dato,
               m.funcion_id,
               COALESCE(a.params_override, m.params_json) AS params_json
        FROM asignaciones a
        JOIN metricas_pool m ON a.metrica_id = m.id
        WHERE a.vendedor_nombre = @vendedor
          AND a.mes  = @mes
          AND a.anio = @anio
          AND m.activa = 1
        ORDER BY m.nombre
      '''),
      parameters: {
        'vendedor': vendedor,
        'mes': mes,
        'anio': anio,
      },
    );

    return result.map((row) {
      final cols = row.toColumnMap();
      return {
        'id': cols['id'],
        'valor_meta': double.parse(cols['valor_meta'].toString()),
        'metrica_id': cols['metrica_id'],
        'nombre': cols['nombre'],
        'descripcion': cols['descripcion'] ?? '',
        'tipo_dato': cols['tipo_dato'] ?? 'int',
        'funcion_id': cols['funcion_id'],
        'params_json': cols['params_json'] ?? '{}',
      };
    }).toList();
  }

  /// Ejecuta un INSERT/UPDATE/DELETE (no retorna filas).
  static Future<void> execute(String sql, Map<String, Object?> params) async {
    final conn = await _getConn();
    await conn.execute(Sql.named(sql), parameters: params);
  }

  /// Ejecuta un SELECT genérico contra Supabase. Retorna lista de maps.
  static Future<List<Map<String, dynamic>>> query(
    String sql, [Map<String, Object?>? params,]
  ) async {
    final conn = await _getConn();
    final result = await conn.execute(
      Sql.named(sql),
      parameters: params ?? {},
    );
    return result.map((row) {
      final cols = row.toColumnMap();
      return Map<String, dynamic>.from(cols);
    }).toList();
  }

  static Future<void> close() async {
    await _conn?.close();
    _conn = null;
  }
}
