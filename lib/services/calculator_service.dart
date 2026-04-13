import 'dart:convert';
import 'sql_service.dart';

/// Traducción de calculadora.py al Dart.
/// Usa queries parametrizadas con ? (estilo JDBC/jTDS).
class CalculatorService {
  // ── Días hábiles (Lun-Vie, sin feriados en MVP) ────────────────────────────
  static (int total, int transcurridos) diasHabiles(int anio, int mes) {
    final hoy = DateTime.now();
    final ultimoDia = DateTime(anio, mes + 1, 0).day;
    int total = 0, transcurridos = 0;

    for (int d = 1; d <= ultimoDia; d++) {
      final dt = DateTime(anio, mes, d);
      if (dt.weekday < 1 || dt.weekday > 5) continue;
      total++;
      final esPasado = anio < hoy.year ||
          (anio == hoy.year && mes < hoy.month) ||
          (anio == hoy.year && mes == hoy.month && d <= hoy.day);
      if (esPasado) transcurridos++;
    }
    return (total, transcurridos);
  }

  static double ritmoEsperado(int anio, int mes) {
    final (total, transcurridos) = diasHabiles(anio, mes);
    if (total == 0) return 1.0;
    return transcurridos / total;
  }

  // ── Facturación Neta ───────────────────────────────────────────────────────
  static Future<(double, String)> calcFacturacion(
    String vendedor, int mes, int anio, Map<String, dynamic> params) async {

    final rows = await SqlService.query(
      '''SELECT NumeraTipoTipo, SUM(SubTotalNetoLocal) AS Total
         FROM [EQ-DBGA].[dbo].[fydvtsEstadisticas]
         WHERE NumeraTipoTipo IN (2205, 2206)
           AND YEAR(Fecha) = ?
           AND MONTH(Fecha) = ?
           AND VendedorNombre = ?
         GROUP BY NumeraTipoTipo''',
      [anio, mes, vendedor],
    );

    if (rows.isEmpty) return (0.0, 'Sin datos');
    double totalF = 0, totalNC = 0;
    for (final r in rows) {
      final tipo = int.tryParse(r['NumeraTipoTipo'].toString()) ?? 0;
      final val = double.tryParse(r['Total'].toString()) ?? 0.0;
      if (tipo == 2205) totalF = val;
      if (tipo == 2206) totalNC = val.abs();
    }
    final resultado = totalF - totalNC;
    return (resultado,
        'Facturas (\$ ${_fmt(totalF)}) − NC (\$ ${_fmt(totalNC)})');
  }

  // ── Apertura de Cuentas Nuevas ─────────────────────────────────────────────
  static Future<(double, String)> calcAperturas(
    String vendedor, int mes, int anio, Map<String, dynamic> params) async {

    final rows = await SqlService.query(
      '''SELECT COUNT(DISTINCT e1.ClienteCodigo) AS Aperturas
         FROM [EQ-DBGA].[dbo].[fydvtsEstadisticas] e1
         WHERE YEAR(e1.Fecha) = ?
           AND MONTH(e1.Fecha) = ?
           AND e1.NumeraTipoTipo = 2205
           AND e1.VendedorNombre = ?
           AND NOT EXISTS (
               SELECT 1 FROM [EQ-DBGA].[dbo].[fydvtsEstadisticas] e2
               WHERE e2.ClienteCodigo = e1.ClienteCodigo
                 AND e2.NumeraTipoTipo = 2205
                 AND e2.Fecha < DATEFROMPARTS(?, ?, 1)
           )''',
      [anio, mes, vendedor, anio, mes],
    );

    if (rows.isEmpty) return (0.0, 'Sin datos de aperturas');
    final val = double.tryParse(rows.first['Aperturas'].toString()) ?? 0.0;
    return (val, 'Apertura de Cuentas: ${val.toStringAsFixed(0)} nuevas.');
  }

  // ── Tasa de Conversión (Cobertura) ────────────────────────────────────────
  static Future<(double, String)> calcTasaConversion(
    String vendedor, int mes, int anio, Map<String, dynamic> params) async {

    final rowsActivos = await SqlService.query(
      '''SELECT COUNT(DISTINCT ClienteCodigo) AS Total
         FROM [EQ-DBGA].[dbo].[fydvtsClientesXLinea]
         WHERE ClienteSituacion = 'Activo normal'
           AND VendedorNombre = ?''',
      [vendedor],
    );

    final cartera = double.tryParse(
        rowsActivos.firstOrNull?['Total']?.toString() ?? '0') ?? 0.0;
    if (cartera <= 0) return (0.0, 'Cartera activa 0.');

    final rowsVentas = await SqlService.query(
      '''SELECT COUNT(DISTINCT ClienteCodigo) AS Facturados
         FROM [EQ-DBGA].[dbo].[fydvtsEstadisticas]
         WHERE YEAR(Fecha) = ?
           AND MONTH(Fecha) = ?
           AND NumeraTipoTipo = 2205
           AND VendedorNombre = ?''',
      [anio, mes, vendedor],
    );

    final fact = double.tryParse(
        rowsVentas.firstOrNull?['Facturados']?.toString() ?? '0') ?? 0.0;
    final tc = (fact / cartera) * 100;
    return (tc,
        'Cobertura: ${fact.toStringAsFixed(0)} de ${cartera.toStringAsFixed(0)} activos.');
  }

  // ── Reactivación de Cuentas ───────────────────────────────────────────────
  static Future<(double, String)> calcReactivacion(
    String vendedor, int mes, int anio, Map<String, dynamic> params) async {

    final dias = int.tryParse(params['dias_inactivo']?.toString() ?? '180') ?? 180;

    final rows = await SqlService.query(
      '''SELECT COUNT(DISTINCT e1.ClienteCodigo) AS Reactivados
         FROM [EQ-DBGA].[dbo].[fydvtsEstadisticas] e1
         CROSS APPLY (
             SELECT MAX(e2.Fecha) AS MaxFecha
             FROM [EQ-DBGA].[dbo].[fydvtsEstadisticas] e2
             WHERE e2.ClienteCodigo = e1.ClienteCodigo
               AND e2.NumeraTipoTipo = 2205
               AND e2.Fecha < DATEFROMPARTS(?, ?, 1)
         ) prev
         WHERE YEAR(e1.Fecha) = ?
           AND MONTH(e1.Fecha) = ?
           AND e1.NumeraTipoTipo = 2205
           AND e1.VendedorNombre = ?
           AND prev.MaxFecha <= DATEADD(day, ?, DATEFROMPARTS(?, ?, 1))''',
      [anio, mes, anio, mes, vendedor, -dias, anio, mes],
    );

    if (rows.isEmpty) return (0.0, 'Sin datos de reactivación');
    final val = double.tryParse(rows.first['Reactivados'].toString()) ?? 0.0;
    return (val, 'Reactivados (> $dias días): ${val.toStringAsFixed(0)} clientes.');
  }

  // ── Foco Artículos ────────────────────────────────────────────────────────
  static Future<(double, String)> calcFocoUnidades(
    String vendedor, int mes, int anio, Map<String, dynamic> params) async {

    final List articulos = params['articulos'] ?? [];
    if (articulos.isEmpty) {
      return (0.0, 'Sin artículos configurados. Ver desktop.');
    }
    final modo = params['modo'] ?? 'unidades';
    final esImporte = (modo == 'importe');
    final col = esImporte ? 'SUM(SubTotalNetoLocal)' : 'SUM(Cantidad)';
    // Artículos vienen de nuestra propia DB, interpolación controlada
    final phs = articulos
        .map((a) => "'${a.toString().replaceAll("'", "''")}'")
        .join(',');

    final rows = await SqlService.query(
      '''SELECT $col AS Total
         FROM [EQ-DBGA].[dbo].[fydvtsEstadisticas]
         WHERE NumeraTipoTipo IN (2205, 2206)
           AND ArticuloCodigo IN ($phs)
           AND YEAR(Fecha) = ?
           AND MONTH(Fecha) = ?
           AND VendedorNombre = ?''',
      [anio, mes, vendedor],
    );

    final val = double.tryParse(rows.firstOrNull?['Total']?.toString() ?? '0') ?? 0.0;
    final arts = articulos.take(3).join(', ');
    final etiq = esImporte ? 'Importe' : 'Unidades';
    return (val, 'SUM($etiq) artículos foco: [$arts${articulos.length > 3 ? "..." : ""}]');
  }

  // ── Incorporaciones Cargas ─────────────────────────────────────────────────
  static Future<(double, String)> calcIncorporacionesCargas(
    String vendedor, int mes, int anio, Map<String, dynamic> params) async {

    final List conjuntos = params['conjuntos'] ?? [];
    if (conjuntos.isEmpty) {
      return (0.0, 'Sin conjuntos/cargas configurados. Ver desktop.');
    }

    int total = 0;
    final detalles = <String>[];

    for (final conj in conjuntos) {
      final conjCod = conj.toString().replaceAll("'", "''");

      // Clientes que compraron esta carga en el mes actual
      final rowsMes = await SqlService.query(
        '''SELECT DISTINCT ClienteCodigo
           FROM [EQ-DBGA].[dbo].[fydvtsEstadisticas]
           WHERE ConjuntoCodigo = '$conjCod'
             AND NumeraTipoTipo = 2205
             AND YEAR(Fecha) = ? AND MONTH(Fecha) = ?
             AND VendedorNombre = ?''',
        [anio, mes, vendedor],
      );
      if (rowsMes.isEmpty) continue;
      final clientesMes = rowsMes.map((r) => r['ClienteCodigo']?.toString()).toSet();

      // Clientes que compraron esta carga ANTES del mes actual
      final rowsHist = await SqlService.query(
        '''SELECT DISTINCT ClienteCodigo
           FROM [EQ-DBGA].[dbo].[fydvtsEstadisticas]
           WHERE ConjuntoCodigo = '$conjCod'
             AND NumeraTipoTipo = 2205
             AND Fecha < DATEFROMPARTS(?, ?, 1)''',
        [anio, mes],
      );
      final clientesHist = rowsHist.map((r) => r['ClienteCodigo']?.toString()).toSet();

      final nuevos = clientesMes.difference(clientesHist).length;
      total += nuevos;
      if (nuevos > 0) detalles.add('$conjCod: $nuevos nuevos');
    }

    var formula = 'Incorporaciones: $total (cargas a clientes nuevos)';
    if (detalles.isNotEmpty) {
      formula += '\n${detalles.take(5).join(", ")}';
    }
    return (total.toDouble(), formula);
  }

  // ── Pendientes: suma desde fydvtsPedidos ──────────────────────────────────
  static Future<double> _getPendiente(String vendedor, String col) async {
    final rows = await SqlService.query(
      '''SELECT SUM($col) AS PendVal
         FROM [EQ-DBGA].[dbo].[fydvtsPedidos]
         WHERE Estado = 'Pendiente' AND CantidadPendiente > 0
           AND VendedorNombre = ?''',
      [vendedor],
    );
    return double.tryParse(rows.firstOrNull?['PendVal']?.toString() ?? '0') ?? 0.0;
  }

  // ── Dispatcher ────────────────────────────────────────────────────────────
  static Future<(double, String)> calcular(
    String funcionId, String vendedor, int mes, int anio, String paramsJson, {
    bool inclPendientes = false,
  }) async {
    Map<String, dynamic> params = {};
    try { params = json.decode(paramsJson) as Map<String, dynamic>; } catch (_) {}

    var (valor, formula) = switch (funcionId) {
      'facturacion' => await calcFacturacion(vendedor, mes, anio, params),
      'aperturas' => await calcAperturas(vendedor, mes, anio, params),
      'tasa_conversion' => await calcTasaConversion(vendedor, mes, anio, params),
      'reactivacion' => await calcReactivacion(vendedor, mes, anio, params),
      'foco_unidades' || 'incorporaciones' => await calcFocoUnidades(vendedor, mes, anio, params),
      'incorporaciones_cargas' => await calcIncorporacionesCargas(vendedor, mes, anio, params),
      _ => (0.0, 'Función "$funcionId" no soportada en mobile.'),
    };

    // Agregar pendientes si corresponde
    if (inclPendientes && valor > 0) {
      double pend = 0;
      switch (funcionId) {
        case 'facturacion':
          pend = await _getPendiente(vendedor, 'SubTotalNetoPendienteLocal');
          break;
        case 'foco_unidades':
        case 'incorporaciones':
          final modo = params['modo'] ?? 'unidades';
          final col = modo == 'importe' ? 'SubTotalNetoPendienteLocal' : 'CantidadPendiente';
          pend = await _getPendiente(vendedor, col);
          break;
      }
      if (pend > 0) {
        valor += pend;
        formula += ' + Pend (${_fmt(pend)})';
      }
    }

    return (valor, formula);
  }

  static String _fmt(double v) {
    final s = v.toStringAsFixed(0);
    final buf = StringBuffer();
    final len = s.length;
    for (int i = 0; i < len; i++) {
      if (i > 0 && (len - i) % 3 == 0) buf.write('.');
      buf.write(s[i]);
    }
    return buf.toString();
  }
}
