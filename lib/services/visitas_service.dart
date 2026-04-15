import 'package:geolocator/geolocator.dart';
import '../models/session.dart';
import 'pg_service.dart';

/// Servicio de visitas GPS — escritura y lectura desde Supabase.
class VisitasService {
  static const motivos = [
    'Visita comercial',
    'Cobranza',
    'Presentación de producto',
    'Reclamo',
  ];

  /// Obtiene la ubicación GPS actual.
  /// Retorna Position o lanza excepción con mensaje claro.
  static Future<Position> obtenerGps() async {
    // Verificar que el servicio de ubicación esté activo
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      throw Exception('Activá la ubicación (GPS) en tu celular.');
    }

    // Verificar permisos
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        throw Exception('Permiso de ubicación denegado. Habilitalo en Ajustes.');
      }
    }
    if (permission == LocationPermission.deniedForever) {
      throw Exception(
          'Permiso de ubicación bloqueado permanentemente.\n'
          'Andá a Ajustes → Apps → Hermes → Permisos → Ubicación.');
    }

    // Obtener posición
    return Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        timeLimit: Duration(seconds: 15),
      ),
    );
  }

  /// Registra una visita en Supabase.
  static Future<void> registrar({
    required String clienteCodigo,
    required String clienteNombre,
    required double latitud,
    required double longitud,
    required String motivo,
    String? notas,
  }) async {
    await PgService.execute(
      '''INSERT INTO visitas
         (vendedor_nombre, cliente_codigo, cliente_nombre, latitud, longitud, motivo, notas)
         VALUES (@vendedor, @cliente, @nombre, @lat, @lng, @motivo, @notas)''',
      {
        'vendedor': Session.current.vendedorNombre,
        'cliente': clienteCodigo,
        'nombre': clienteNombre,
        'lat': latitud,
        'lng': longitud,
        'motivo': motivo,
        'notas': notas,
      },
    );
  }

  /// Visitas del vendedor de hoy.
  static Future<List<Map<String, dynamic>>> visitasHoy() async {
    return PgService.query(
      '''SELECT id, cliente_codigo, cliente_nombre, motivo, notas,
              latitud, longitud, created_at
         FROM visitas
         WHERE vendedor_nombre = @vendedor
           AND created_at::date = CURRENT_DATE
         ORDER BY created_at DESC''',
      {'vendedor': Session.current.vendedorNombre},
    );
  }

  /// Visitas del vendedor de esta semana.
  static Future<List<Map<String, dynamic>>> visitasSemana() async {
    return PgService.query(
      '''SELECT id, cliente_codigo, cliente_nombre, motivo, notas,
              latitud, longitud, created_at
         FROM visitas
         WHERE vendedor_nombre = @vendedor
           AND created_at >= date_trunc('week', CURRENT_DATE)
         ORDER BY created_at DESC''',
      {'vendedor': Session.current.vendedorNombre},
    );
  }

  /// Últimas visitas a un cliente específico.
  static Future<List<Map<String, dynamic>>> visitasCliente(
      String clienteCodigo, {int limit = 5}) async {
    return PgService.query(
      '''SELECT id, motivo, notas, latitud, longitud, created_at
         FROM visitas
         WHERE cliente_codigo = @cliente
           AND vendedor_nombre = @vendedor
         ORDER BY created_at DESC
         LIMIT $limit''',
      {
        'cliente': clienteCodigo,
        'vendedor': Session.current.vendedorNombre,
      },
    );
  }

  /// Cantidad de visitas de hoy (para badge).
  static Future<int> conteoHoy() async {
    final rows = await PgService.query(
      '''SELECT COUNT(*) AS total FROM visitas
         WHERE vendedor_nombre = @vendedor
           AND created_at::date = CURRENT_DATE''',
      {'vendedor': Session.current.vendedorNombre},
    );
    return int.tryParse(rows.firstOrNull?['total']?.toString() ?? '0') ?? 0;
  }
}
