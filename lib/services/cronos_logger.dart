import 'package:flutter/foundation.dart';
import '../models/session.dart';
import 'pg_service.dart';

/// Logger fire-and-forget de turnos del LLM Cronos.
///
/// Escribe a `cronos_logs` sin bloquear la conversación. Si la DB no responde
/// (sin VPN, etc), debugPrint y seguir — no es crítico para el flujo.
///
/// Uso típico desde `AssistantService`:
/// ```
/// CronosLogger.log(
///   userMsg: ...,
///   responseRaw: ...,
///   responseMensaje: ...,
///   accionesCount: ...,
///   parseOk: true,
///   latenciaMs: ...,
///   modelo: 'gpt-4o-mini',
/// ); // sin await
/// ```
class CronosLogger {
  /// Registra un turno. Fire-and-forget: el caller NO debería await.
  static Future<void> log({
    required String userMsg,
    String? responseRaw,
    String? responseMensaje,
    int accionesCount = 0,
    bool parseOk = true,
    int? latenciaMs,
    String? modelo,
  }) async {
    try {
      await PgService.execute(
        'INSERT INTO cronos_logs '
        '(vendedor_nombre, user_msg, response_raw, response_mensaje, '
        ' acciones_count, parse_ok, latencia_ms, modelo) '
        'VALUES (@vendedor, @msg, @raw, @mensaje, @count, @ok, @lat, @model)',
        {
          'vendedor': Session.current.vendedorNombre,
          'msg': userMsg,
          'raw': responseRaw,
          'mensaje': responseMensaje,
          'count': accionesCount,
          'ok': parseOk,
          'lat': latenciaMs,
          'model': modelo,
        },
      );
    } catch (e) {
      debugPrint('[CronosLogger] log fail: $e');
    }
  }
}
