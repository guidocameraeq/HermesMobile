import 'dart:collection';
import '../models/session.dart';
import 'pg_service.dart';

/// Log de errores en memoria + Supabase.
/// Guarda los últimos 20 errores en memoria para diagnóstico.
/// Intenta persistir en Supabase (fire-and-forget).
class ErrorLogger {
  static final _logs = Queue<ErrorEntry>();
  static const _maxEntries = 20;

  /// Registra un error.
  static void log(String source, String message) {
    final entry = ErrorEntry(
      timestamp: DateTime.now(),
      source: source,
      message: message,
    );

    _logs.addFirst(entry);
    if (_logs.length > _maxEntries) _logs.removeLast();

    // Intentar persistir en Supabase (silencioso)
    _persist(entry);
  }

  static Future<void> _persist(ErrorEntry entry) async {
    try {
      final user = Session.current.username;
      if (user.isEmpty) return;

      await PgService.execute(
        'INSERT INTO analytics (usuario, evento, modulo, detalle) '
        "VALUES (@user, 'error', @source, @msg)",
        {'user': user, 'source': entry.source, 'msg': entry.message},
      );
    } catch (_) {
      // Si falla persistir, al menos queda en memoria
    }
  }

  /// Últimos errores (más reciente primero).
  static List<ErrorEntry> get recent => _logs.toList();

  /// Limpiar logs en memoria.
  static void clear() => _logs.clear();
}

class ErrorEntry {
  final DateTime timestamp;
  final String source;
  final String message;

  ErrorEntry({
    required this.timestamp,
    required this.source,
    required this.message,
  });

  String get timeStr =>
      '${timestamp.hour.toString().padLeft(2, '0')}:'
      '${timestamp.minute.toString().padLeft(2, '0')}:'
      '${timestamp.second.toString().padLeft(2, '0')}';
}
