import 'dart:io';
import 'package:sql_conn/sql_conn.dart';
import '../config/constants.dart';

/// Conexión a SQL Server via jTDS (JDBC) — requiere VPN activa.
class SqlService {
  static bool _connected = false;
  static String lastError = '';

  // connectionId incluye parámetros JDBC extras para jTDS
  static String get _connId =>
      'hermes;instance=${AppConfig.sqlInstance};ssl=off';

  /// Test TCP puro — ¿el puerto está abierto?
  static Future<String> _testTcp() async {
    try {
      final socket = await Socket.connect(
        AppConfig.sqlHost,
        int.parse(AppConfig.sqlPort),
        timeout: const Duration(seconds: 8),
      );
      final remoteAddr = '${socket.remoteAddress.address}:${socket.remotePort}';
      socket.destroy();
      return 'OK ($remoteAddr)';
    } on SocketException catch (e) {
      return 'FALLO: ${e.osError?.message ?? e.message}';
    } catch (e) {
      return 'FALLO: $e';
    }
  }

  /// Conecta al SQL Server. Retorna true si OK.
  static Future<bool> connect() async {
    if (_connected) return true;
    lastError = '';

    // Paso 1: test TCP
    final tcpResult = await _testTcp();
    final tcpOk = tcpResult.startsWith('OK');

    if (!tcpOk) {
      lastError = 'TCP ${AppConfig.sqlHost}:${AppConfig.sqlPort} → $tcpResult\n'
          'Verificá que la VPN esté activa y rutee a 192.168.1.x';
      return false;
    }

    // Paso 2: conexión jTDS/JDBC
    try {
      final ok = await SqlConn.connect(
        connectionId: _connId,
        host: AppConfig.sqlHost,
        port: int.parse(AppConfig.sqlPort),
        database: AppConfig.sqlDb,
        username: AppConfig.sqlUser,
        password: AppConfig.sqlPass,
      );
      _connected = ok;
      if (!ok) {
        lastError = 'TCP OK pero jTDS retornó false.\n'
            'Host: ${AppConfig.sqlHost}:${AppConfig.sqlPort}\n'
            'Instance: ${AppConfig.sqlInstance}\n'
            'DB: ${AppConfig.sqlDb} | User: ${AppConfig.sqlUser}';
      }
      return ok;
    } on SqlConnException catch (e) {
      lastError = 'jTDS error: ${e.message}';
      _connected = false;
      return false;
    } catch (e) {
      lastError = 'Error inesperado: $e';
      _connected = false;
      return false;
    }
  }

  /// Ejecuta una query SELECT.
  /// Usa '?' como placeholder para params (estilo JDBC).
  static Future<List<Map<String, dynamic>>> query(
    String sql, [
    List<Object?>? params,
  ]) async {
    if (!_connected) {
      final ok = await connect();
      if (!ok) return [];
    }
    try {
      final rows = await SqlConn.read(_connId, sql, params: params);
      return rows.map((r) => Map<String, dynamic>.from(r)).toList();
    } on SqlConnException catch (e) {
      lastError = 'Query error: ${e.message}';
      return [];
    } catch (e) {
      lastError = 'Query error: $e';
      return [];
    }
  }

  static Future<void> disconnect() async {
    try {
      await SqlConn.disconnect(_connId);
    } catch (_) {}
    _connected = false;
  }
}
