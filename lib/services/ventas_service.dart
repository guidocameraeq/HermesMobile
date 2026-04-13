import 'sql_service.dart';
import 'pg_service.dart';

/// Queries para el módulo de Ventas del vendedor.
class VentasService {
  /// KPIs del vendedor: facturación mes actual, mes anterior, mismo mes año anterior.
  /// Retorna { facActual, facAnterior, facYoY, meta }.
  static Future<Map<String, double>> getKpis(
      String vendedor, int mes, int anio) async {
    // Mes actual
    final facActual = await _facturacionMes(vendedor, mes, anio);

    // Mismo mes año anterior
    final facYoY = await _facturacionMes(vendedor, mes, anio - 1);

    // Meta del mes (desde Supabase — asignación de facturación)
    double meta = 0;
    try {
      final asigs = await PgService.getAsignaciones(vendedor, mes, anio);
      for (final a in asigs) {
        if (a['funcion_id'] == 'facturacion') {
          meta = a['valor_meta'] as double;
          break;
        }
      }
    } catch (_) {}

    return {
      'facActual': facActual,
      'facYoY': facYoY,
      'meta': meta,
    };
  }

  static Future<double> _facturacionMes(
      String vendedor, int mes, int anio) async {
    final rows = await SqlService.query(
      '''SELECT NumeraTipoTipo, SUM(SubTotalNetoLocal) AS Total
         FROM [EQ-DBGA].[dbo].[fydvtsEstadisticas]
         WHERE NumeraTipoTipo IN (2205, 2206)
           AND YEAR(Fecha) = ? AND MONTH(Fecha) = ?
           AND VendedorNombre = ?
         GROUP BY NumeraTipoTipo''',
      [anio, mes, vendedor],
    );
    double totalF = 0, totalNC = 0;
    for (final r in rows) {
      final tipo = int.tryParse(r['NumeraTipoTipo']?.toString() ?? '') ?? 0;
      final val = double.tryParse(r['Total']?.toString() ?? '0') ?? 0;
      if (tipo == 2205) totalF = val;
      if (tipo == 2206) totalNC = val.abs();
    }
    return totalF - totalNC;
  }

  /// Evolución mensual: últimos 6 meses + mismos 6 meses del año anterior.
  /// Retorna { actual: [{mes, anio, monto}], anterior: [{mes, anio, monto}] }
  static Future<Map<String, List<Map<String, dynamic>>>> getEvolucion(
      String vendedor, int mes, int anio) async {
    // Últimos 6 meses del año actual/reciente
    final rowsActual = await SqlService.query(
      '''SELECT YEAR(Fecha) AS Anio, MONTH(Fecha) AS Mes,
              SUM(CASE WHEN NumeraTipoTipo = 2205 THEN SubTotalNetoLocal
                       WHEN NumeraTipoTipo = 2206 THEN -ABS(SubTotalNetoLocal)
                       ELSE 0 END) AS Monto
         FROM [EQ-DBGA].[dbo].[fydvtsEstadisticas]
         WHERE NumeraTipoTipo IN (2205, 2206)
           AND VendedorNombre = ?
           AND Fecha >= DATEADD(MONTH, -5, DATEFROMPARTS(?, ?, 1))
           AND Fecha < DATEADD(MONTH, 1, DATEFROMPARTS(?, ?, 1))
         GROUP BY YEAR(Fecha), MONTH(Fecha)
         ORDER BY Anio, Mes''',
      [vendedor, anio, mes, anio, mes],
    );

    // Mismos 6 meses del año anterior
    final rowsAnterior = await SqlService.query(
      '''SELECT YEAR(Fecha) AS Anio, MONTH(Fecha) AS Mes,
              SUM(CASE WHEN NumeraTipoTipo = 2205 THEN SubTotalNetoLocal
                       WHEN NumeraTipoTipo = 2206 THEN -ABS(SubTotalNetoLocal)
                       ELSE 0 END) AS Monto
         FROM [EQ-DBGA].[dbo].[fydvtsEstadisticas]
         WHERE NumeraTipoTipo IN (2205, 2206)
           AND VendedorNombre = ?
           AND Fecha >= DATEADD(MONTH, -5, DATEFROMPARTS(?, ?, 1))
           AND Fecha < DATEADD(MONTH, 1, DATEFROMPARTS(?, ?, 1))
         GROUP BY YEAR(Fecha), MONTH(Fecha)
         ORDER BY Anio, Mes''',
      [vendedor, anio - 1, mes, anio - 1, mes],
    );

    return {
      'actual': rowsActual,
      'anterior': rowsAnterior,
    };
  }
}
