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
    return _conn!;
  }

  /// Verifica credenciales: retorna el role si OK, null si falla.
  static Future<String?> verifyUser(String username, String hash) async {
    final conn = await _getConn();
    final result = await conn.execute(
      Sql.named(
        'SELECT role FROM usuarios '
        'WHERE LOWER(username) = LOWER(@user) AND password_hash = @hash',
      ),
      parameters: {'user': username.trim(), 'hash': hash},
    );
    if (result.isEmpty) return null;
    return result.first[0] as String?;
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
               m.nombre,
               m.descripcion,
               m.tipo_dato,
               m.funcion_id,
               m.params_json
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

  static Future<void> close() async {
    await _conn?.close();
    _conn = null;
  }
}
