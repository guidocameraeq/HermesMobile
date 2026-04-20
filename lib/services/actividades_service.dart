import '../models/session.dart';
import 'pg_service.dart';
import 'calendar_service.dart';

/// CRUD de actividades comerciales por cliente — Supabase.
class ActividadesService {
  static const tipos = [
    'Llamada', 'Visita', 'Propuesta', 'Presentación', 'Reunión', 'Recordatorio', 'Otro',
  ];

  /// Registra una actividad. Retorna el id creado.
  /// Si Google Calendar está en modo auto y tiene fecha, sincroniza.
  static Future<int?> registrar({
    required String clienteCodigo,
    required String clienteNombre,
    required String tipo,
    String? descripcion,
    String? fechaProgramada, // ISO 8601
    String origen = 'manual',
  }) async {
    final params = <String, Object?>{
      'vendedor': Session.current.vendedorNombre,
      'cliente': clienteCodigo,
      'nombre': clienteNombre,
      'tipo': tipo.toLowerCase(),
      'desc': descripcion,
      'origen': origen,
    };

    String fechaCol = '';
    if (fechaProgramada != null) {
      params['fecha'] = fechaProgramada;
      fechaCol = ', fecha_programada';
    }

    final rows = await PgService.query(
      'INSERT INTO actividades_cliente '
      '(vendedor_nombre, cliente_codigo, cliente_nombre, tipo, descripcion, origen$fechaCol) '
      'VALUES (@vendedor, @cliente, @nombre, @tipo, @desc, @origen${fechaProgramada != null ? ", @fecha" : ""}) '
      'RETURNING id',
      params,
    );
    final id = rows.isNotEmpty ? int.tryParse(rows.first['id']?.toString() ?? '') : null;

    // Sincronización automática con Google Calendar si corresponde
    if (id != null && fechaProgramada != null && await CalendarService.I.isAuto) {
      final dt = DateTime.tryParse(fechaProgramada);
      if (dt != null && dt.isAfter(DateTime.now())) {
        final eventId = await CalendarService.I.createEvent(
          titulo: '${tipo[0].toUpperCase()}${tipo.substring(1)} — $clienteNombre',
          inicio: dt,
          duracion: const Duration(minutes: 30),
          descripcion: descripcion,
        );
        if (eventId != null) {
          await PgService.execute(
            'UPDATE actividades_cliente SET google_event_id = @eid WHERE id = @id',
            {'eid': eventId, 'id': id},
          );
        }
      }
    }
    return id;
  }

  /// Guarda un google_event_id en una actividad (linking manual).
  static Future<void> setGoogleEventId(int id, String? eventId) async {
    await PgService.execute(
      'UPDATE actividades_cliente SET google_event_id = @eid '
      'WHERE id = @id AND vendedor_nombre = @vendedor',
      {'eid': eventId, 'id': id, 'vendedor': Session.current.vendedorNombre},
    );
  }

  /// Actividades de un cliente (más recientes primero).
  static Future<List<Map<String, dynamic>>> porCliente(
      String clienteCodigo, {int limit = 10}) async {
    return PgService.query(
      'SELECT id, tipo, descripcion, resultado, fecha_programada, completada, '
      'origen, created_at FROM actividades_cliente '
      'WHERE cliente_codigo = @cliente AND vendedor_nombre = @vendedor '
      'ORDER BY created_at DESC LIMIT $limit',
      {'cliente': clienteCodigo, 'vendedor': Session.current.vendedorNombre},
    );
  }

  /// Actividades pendientes del vendedor (no completadas, con fecha próxima).
  static Future<List<Map<String, dynamic>>> pendientes() async {
    return PgService.query(
      'SELECT id, cliente_codigo, cliente_nombre, tipo, descripcion, '
      'fecha_programada, created_at FROM actividades_cliente '
      'WHERE vendedor_nombre = @vendedor AND completada = FALSE '
      'ORDER BY fecha_programada ASC NULLS LAST, created_at DESC '
      'LIMIT 20',
      {'vendedor': Session.current.vendedorNombre},
    );
  }

  /// Marcar como completada.
  static Future<void> completar(int id) async {
    await PgService.execute(
      'UPDATE actividades_cliente SET completada = TRUE, completada_at = NOW() '
      'WHERE id = @id AND vendedor_nombre = @vendedor',
      {'id': id, 'vendedor': Session.current.vendedorNombre},
    );
  }

  /// Reabrir (marcar como no completada).
  static Future<void> reabrir(int id) async {
    await PgService.execute(
      'UPDATE actividades_cliente SET completada = FALSE, completada_at = NULL '
      'WHERE id = @id AND vendedor_nombre = @vendedor',
      {'id': id, 'vendedor': Session.current.vendedorNombre},
    );
  }

  /// Actualizar descripción y/o fecha programada. Sincroniza Calendar si tiene event_id.
  static Future<void> actualizar({
    required int id,
    String? descripcion,
    String? fechaProgramada,
  }) async {
    final params = <String, Object?>{
      'id': id,
      'vendedor': Session.current.vendedorNombre,
    };
    final sets = <String>[];
    if (descripcion != null) {
      sets.add('descripcion = @desc');
      params['desc'] = descripcion;
    }
    sets.add('fecha_programada = @fecha');
    params['fecha'] = fechaProgramada;

    if (sets.isEmpty) return;
    await PgService.execute(
      'UPDATE actividades_cliente SET ${sets.join(", ")} '
      'WHERE id = @id AND vendedor_nombre = @vendedor',
      params,
    );

    // Sincronizar con Calendar si esta actividad tiene evento asociado
    final act = await porId(id);
    final eventId = act?['google_event_id']?.toString();
    if (eventId != null && eventId.isNotEmpty && fechaProgramada != null) {
      final dt = DateTime.tryParse(fechaProgramada);
      if (dt != null) {
        final tipo = act?['tipo']?.toString() ?? '';
        final cliente = act?['cliente_nombre']?.toString() ?? '';
        await CalendarService.I.updateEvent(
          eventId: eventId,
          titulo: '${tipo.isNotEmpty ? "${tipo[0].toUpperCase()}${tipo.substring(1)}" : "Actividad"} — $cliente',
          inicio: dt,
          duracion: const Duration(minutes: 30),
          descripcion: descripcion,
        );
      }
    }
  }

  /// Eliminar actividad. Si tiene evento en Calendar, también lo borra.
  static Future<void> eliminar(int id) async {
    final act = await porId(id);
    final eventId = act?['google_event_id']?.toString();

    await PgService.execute(
      'DELETE FROM actividades_cliente '
      'WHERE id = @id AND vendedor_nombre = @vendedor',
      {'id': id, 'vendedor': Session.current.vendedorNombre},
    );

    if (eventId != null && eventId.isNotEmpty) {
      await CalendarService.I.deleteEvent(eventId);
    }
  }

  /// Obtener una actividad por id.
  static Future<Map<String, dynamic>?> porId(int id) async {
    final rows = await PgService.query(
      'SELECT id, cliente_codigo, cliente_nombre, tipo, descripcion, '
      'fecha_programada, completada, completada_at, origen, created_at, google_event_id '
      'FROM actividades_cliente '
      'WHERE id = @id AND vendedor_nombre = @vendedor',
      {'id': id, 'vendedor': Session.current.vendedorNombre},
    );
    return rows.firstOrNull;
  }

  /// Conteo de pendientes (para badge).
  static Future<int> conteoPendientes() async {
    final rows = await PgService.query(
      'SELECT COUNT(*) AS n FROM actividades_cliente '
      'WHERE vendedor_nombre = @vendedor AND completada = FALSE',
      {'vendedor': Session.current.vendedorNombre},
    );
    return int.tryParse(rows.firstOrNull?['n']?.toString() ?? '0') ?? 0;
  }

  /// Actividades completadas (últimas N).
  static Future<List<Map<String, dynamic>>> completadas({int limit = 20}) async {
    return PgService.query(
      'SELECT id, cliente_codigo, cliente_nombre, tipo, descripcion, '
      'completada_at, created_at FROM actividades_cliente '
      'WHERE vendedor_nombre = @vendedor AND completada = TRUE '
      'ORDER BY completada_at DESC LIMIT $limit',
      {'vendedor': Session.current.vendedorNombre},
    );
  }

  /// Pendientes de hoy.
  static Future<List<Map<String, dynamic>>> pendientesHoy() async {
    return PgService.query(
      'SELECT id, cliente_codigo, cliente_nombre, tipo, descripcion, '
      'fecha_programada, created_at FROM actividades_cliente '
      'WHERE vendedor_nombre = @vendedor AND completada = FALSE '
      'AND (fecha_programada::date = CURRENT_DATE '
      '     OR (fecha_programada IS NULL AND created_at::date = CURRENT_DATE)) '
      'ORDER BY fecha_programada ASC NULLS LAST',
      {'vendedor': Session.current.vendedorNombre},
    );
  }

  /// Pendientes de un cliente específico.
  static Future<List<Map<String, dynamic>>> pendientesPorCliente(String clienteCodigo) async {
    return PgService.query(
      'SELECT id, cliente_codigo, cliente_nombre, tipo, descripcion, '
      'fecha_programada, created_at FROM actividades_cliente '
      'WHERE vendedor_nombre = @vendedor AND cliente_codigo = @cliente '
      'AND completada = FALSE '
      'ORDER BY fecha_programada ASC NULLS LAST, created_at DESC',
      {'vendedor': Session.current.vendedorNombre, 'cliente': clienteCodigo},
    );
  }

  /// Pendientes de mañana (fecha_programada = CURRENT_DATE + 1).
  static Future<List<Map<String, dynamic>>> pendientesManana() async {
    return PgService.query(
      'SELECT id, cliente_codigo, cliente_nombre, tipo, descripcion, '
      'fecha_programada, created_at FROM actividades_cliente '
      'WHERE vendedor_nombre = @vendedor AND completada = FALSE '
      'AND fecha_programada::date = CURRENT_DATE + INTERVAL \'1 day\' '
      'ORDER BY fecha_programada ASC',
      {'vendedor': Session.current.vendedorNombre},
    );
  }

  /// Pendientes vencidas — con fecha < hoy y no completadas.
  static Future<List<Map<String, dynamic>>> pendientesVencidas() async {
    return PgService.query(
      'SELECT id, cliente_codigo, cliente_nombre, tipo, descripcion, '
      'fecha_programada, created_at FROM actividades_cliente '
      'WHERE vendedor_nombre = @vendedor AND completada = FALSE '
      'AND fecha_programada IS NOT NULL '
      'AND fecha_programada::date < CURRENT_DATE '
      'ORDER BY fecha_programada DESC',
      {'vendedor': Session.current.vendedorNombre},
    );
  }

  /// Pendientes de este mes calendario.
  static Future<List<Map<String, dynamic>>> pendientesMes() async {
    return PgService.query(
      'SELECT id, cliente_codigo, cliente_nombre, tipo, descripcion, '
      'fecha_programada, created_at FROM actividades_cliente '
      'WHERE vendedor_nombre = @vendedor AND completada = FALSE '
      'AND fecha_programada >= date_trunc(\'month\', CURRENT_DATE) '
      'AND fecha_programada <  date_trunc(\'month\', CURRENT_DATE) + INTERVAL \'1 month\' '
      'ORDER BY fecha_programada ASC',
      {'vendedor': Session.current.vendedorNombre},
    );
  }

  /// Pendientes de un día específico (ISO yyyy-MM-dd).
  static Future<List<Map<String, dynamic>>> pendientesFecha(String iso) async {
    return PgService.query(
      'SELECT id, cliente_codigo, cliente_nombre, tipo, descripcion, '
      'fecha_programada, created_at FROM actividades_cliente '
      'WHERE vendedor_nombre = @vendedor AND completada = FALSE '
      'AND fecha_programada::date = @fecha::date '
      'ORDER BY fecha_programada ASC',
      {'vendedor': Session.current.vendedorNombre, 'fecha': iso},
    );
  }

  /// Pendientes de esta semana calendario (lunes a domingo inclusive).
  static Future<List<Map<String, dynamic>>> pendientesSemana() async {
    return PgService.query(
      'SELECT id, cliente_codigo, cliente_nombre, tipo, descripcion, '
      'fecha_programada, created_at FROM actividades_cliente '
      'WHERE vendedor_nombre = @vendedor AND completada = FALSE '
      'AND fecha_programada >= date_trunc(\'week\', CURRENT_DATE) '
      'AND fecha_programada <  date_trunc(\'week\', CURRENT_DATE) + INTERVAL \'7 days\' '
      'ORDER BY fecha_programada ASC',
      {'vendedor': Session.current.vendedorNombre},
    );
  }
}
