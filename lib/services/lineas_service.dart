import 'sql_service.dart';

/// Análisis de líneas de producto por cliente.
/// Usa JOIN fydvtsEstadisticas + fydgnrArticulos para obtener LineaNombre.
class LineasService {
  // Cache de todas las líneas (cambian muy poco)
  static List<String>? _todasCache;

  /// Todas las líneas de producto activas del catálogo.
  static Future<List<String>> todasLasLineas() async {
    if (_todasCache != null) return _todasCache!;

    final rows = await SqlService.query(
      '''SELECT DISTINCT a.LineaNombre
         FROM [EQ-DBGA].[dbo].[fydgnrArticulos] a
         WHERE a.LineaNombre IS NOT NULL AND a.LineaNombre != ''
           AND a.LineaNombre != '-'
         ORDER BY a.LineaNombre''',
    );

    _todasCache = rows
        .map((r) => r['LineaNombre']?.toString() ?? '')
        .where((l) => l.isNotEmpty)
        .toList();
    return _todasCache!;
  }

  /// Líneas que un cliente compra (últimos 12 meses) con monto y unidades.
  /// Retorna lista ordenada por monto descendente.
  static Future<List<LineaCliente>> lineasCliente(String clienteCodigo) async {
    final rows = await SqlService.query(
      '''SELECT ISNULL(a.LineaNombre, 'Sin Linea') AS Linea,
              SUM(CASE WHEN e.NumeraTipoTipo = 2205 THEN e.SubTotalNetoLocal
                       WHEN e.NumeraTipoTipo = 2206 THEN -ABS(e.SubTotalNetoLocal)
                       ELSE 0 END) AS Monto,
              SUM(e.Cantidad) AS Unidades,
              COUNT(DISTINCT e.ArticuloCodigo) AS Articulos
         FROM [EQ-DBGA].[dbo].[fydvtsEstadisticas] e
         JOIN [EQ-DBGA].[dbo].[fydgnrArticulos] a ON e.ArticuloCodigo = a.ArticuloCodigo
         WHERE e.ClienteCodigo = ?
           AND e.NumeraTipoTipo IN (2205, 2206)
           AND e.Fecha >= DATEADD(MONTH, -12, GETDATE())
         GROUP BY a.LineaNombre
         ORDER BY SUM(CASE WHEN e.NumeraTipoTipo = 2205 THEN e.SubTotalNetoLocal
                           WHEN e.NumeraTipoTipo = 2206 THEN -ABS(e.SubTotalNetoLocal)
                           ELSE 0 END) DESC''',
      [clienteCodigo],
    );

    return rows.map((r) => LineaCliente(
      nombre: r['Linea']?.toString() ?? '',
      monto: double.tryParse(r['Monto']?.toString() ?? '0') ?? 0,
      unidades: double.tryParse(r['Unidades']?.toString() ?? '0') ?? 0,
      articulos: int.tryParse(r['Articulos']?.toString() ?? '0') ?? 0,
    )).where((l) => l.nombre.isNotEmpty && l.nombre != '-').toList();
  }

  /// Líneas que el cliente NO compra (oportunidad de venta).
  static Future<List<String>> oportunidades(String clienteCodigo) async {
    final todas = await todasLasLineas();
    final compra = await lineasCliente(clienteCodigo);
    final compraSet = compra.map((l) => l.nombre).toSet();
    return todas.where((l) => !compraSet.contains(l)).toList();
  }

  /// Resumen rápido: cuántas líneas compra vs total.
  static Future<(int compra, int total)> resumen(String clienteCodigo) async {
    final todas = await todasLasLineas();
    final compra = await lineasCliente(clienteCodigo);
    return (compra.length, todas.length);
  }
}

/// Modelo de línea de producto por cliente.
class LineaCliente {
  final String nombre;
  final double monto;
  final double unidades;
  final int articulos;

  LineaCliente({
    required this.nombre,
    required this.monto,
    required this.unidades,
    required this.articulos,
  });
}
