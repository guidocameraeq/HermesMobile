import '../models/session.dart';
import 'pg_service.dart';

/// Tracking de eventos a la tabla analytics de Supabase.
/// Fire-and-forget — nunca bloquea la UI ni lanza errores.
class AnalyticsService {
  static Future<void> track(String evento, {String? modulo, String? detalle}) async {
    try {
      final user = Session.current.username;
      if (user.isEmpty) return;

      await PgService.execute(
        'INSERT INTO analytics (usuario, evento, modulo, detalle) '
        'VALUES (@user, @evento, @modulo, @detalle)',
        {
          'user': user,
          'evento': evento,
          'modulo': modulo,
          'detalle': detalle,
        },
      );
    } catch (_) {
      // Silencioso — analytics nunca debe romper la app
    }
  }
}
