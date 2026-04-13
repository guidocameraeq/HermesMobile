import '../models/scorecard_item.dart';
import '../config/constants.dart';
import 'pg_service.dart';
import 'sql_service.dart';
import 'calculator_service.dart';

class ScorecardService {
  /// Carga el scorecard completo para el vendedor/mes/año.
  /// Primero trae los targets de Supabase (sin VPN),
  /// luego calcula los valores reales desde SQL Server (requiere VPN).
  static Future<List<ScorecardItem>> loadScorecard(
    String vendedor,
    int mes,
    int anio, {
    bool inclPendientes = false,
  }) async {
    // 1. Traer asignaciones de Supabase
    final asigs = await PgService.getAsignaciones(vendedor, mes, anio);

    if (asigs.isEmpty) return [];

    // 2. Construir items con metas (sin valores reales aún)
    final items = asigs.map((a) {
      return ScorecardItem(
        metricaId: a['metrica_id'] as int,
        nombre: a['nombre'] as String,
        descripcion: a['descripcion'] as String? ?? '',
        tipoDato: a['tipo_dato'] as String? ?? 'int',
        funcionId: a['funcion_id'] as String,
        paramsJson: a['params_json'] as String? ?? '{}',
        valorMeta: a['valor_meta'] as double,
      );
    }).toList();

    // 3. Conectar al SQL Server
    final sqlOk = await SqlService.connect();

    if (!sqlOk) {
      final err = SqlService.lastError.isNotEmpty
          ? SqlService.lastError
          : 'No se pudo conectar al SQL Server (${AppConfig.sqlHost}:${AppConfig.sqlPort})';
      for (final item in items) {
        item.error = true;
        item.cargado = true;
        item.formula = err;
      }
      return items;
    }

    // 4. Calcular cada métrica en paralelo
    final futures = items.map((item) async {
      try {
        final (valor, formula) = await CalculatorService.calcular(
          item.funcionId,
          vendedor,
          mes,
          anio,
          item.paramsJson,
          inclPendientes: inclPendientes,
        );
        item.valorReal = valor;
        item.formula = formula;
        item.cargado = true;
        item.error = false;
      } catch (e) {
        item.error = true;
        item.cargado = true;
        item.formula = 'Error: ${e.toString()}';
      }
    });

    await Future.wait(futures);
    return items;
  }
}
