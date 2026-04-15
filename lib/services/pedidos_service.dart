import 'sql_service.dart';

/// Queries de pedidos — tabla fydvtsPedidos (SQL Server, VPN).
class PedidosService {
  /// Lista de pedidos agrupados por Numero, filtrado por vendedor y mes.
  static Future<List<Map<String, dynamic>>> getPedidos(
      String vendedor, int mes, int anio) async {
    return SqlService.query(
      '''SELECT Numero, MAX(Fecha) AS Fecha, MAX(ClienteNombre) AS Cliente,
              MAX(ClienteCodigo) AS ClienteCodigo,
              MAX(Estado) AS Estado,
              COUNT(*) AS Items,
              SUM(Cantidad) AS CantTotal,
              SUM(CantidadAplicada) AS CantAplicada,
              SUM(CantidadPendiente) AS CantPendiente,
              SUM(SubTotalNetoPedidoLocal) AS MontoTotal,
              SUM(SubTotalNetoPendienteLocal) AS MontoPendiente
         FROM [EQ-DBGA].[dbo].[fydvtsPedidos]
         WHERE VendedorNombre = ?
           AND YEAR(Fecha) = ? AND MONTH(Fecha) = ?
         GROUP BY Numero
         ORDER BY MAX(Fecha) DESC''',
      [vendedor, anio, mes],
    );
  }

  /// Detalle de un pedido: líneas de artículos.
  static Future<List<Map<String, dynamic>>> getDetalle(String numero) async {
    return SqlService.query(
      '''SELECT ArticuloCodigo, ArticuloNombre, LineaNombre,
              Cantidad, CantidadAplicada, CantidadPendiente,
              Precio, SubTotalNetoPedidoLocal, SubTotalNetoPendienteLocal,
              Estado
         FROM [EQ-DBGA].[dbo].[fydvtsPedidos]
         WHERE Numero = ?
         ORDER BY ArticuloNombre''',
      [numero],
    );
  }

  /// KPIs del período para el vendedor.
  static Future<Map<String, dynamic>> getKpis(
      String vendedor, int mes, int anio) async {
    final rows = await SqlService.query(
      '''SELECT COUNT(DISTINCT Numero) AS TotalPedidos,
              COUNT(DISTINCT CASE WHEN Estado = 'Pendiente' AND CantidadPendiente > 0
                    THEN Numero END) AS Pendientes,
              SUM(CASE WHEN Estado = 'Pendiente'
                    THEN SubTotalNetoPendienteLocal ELSE 0 END) AS MontoPendiente,
              SUM(CASE WHEN Estado IN ('Cancelado','Anulado')
                    THEN SubTotalNetoPedidoLocal ELSE 0 END) AS MontoFacturado
         FROM [EQ-DBGA].[dbo].[fydvtsPedidos]
         WHERE VendedorNombre = ?
           AND YEAR(Fecha) = ? AND MONTH(Fecha) = ?''',
      [vendedor, anio, mes],
    );
    if (rows.isEmpty) {
      return {'TotalPedidos': 0, 'Pendientes': 0, 'MontoPendiente': 0.0, 'MontoFacturado': 0.0};
    }
    final r = rows.first;
    return {
      'TotalPedidos': int.tryParse(r['TotalPedidos']?.toString() ?? '0') ?? 0,
      'Pendientes': int.tryParse(r['Pendientes']?.toString() ?? '0') ?? 0,
      'MontoPendiente': double.tryParse(r['MontoPendiente']?.toString() ?? '0') ?? 0.0,
      'MontoFacturado': double.tryParse(r['MontoFacturado']?.toString() ?? '0') ?? 0.0,
    };
  }

  /// Cantidad de pedidos pendientes (para badge).
  static Future<int> conteoPendientes(String vendedor) async {
    final rows = await SqlService.query(
      '''SELECT COUNT(DISTINCT Numero) AS N
         FROM [EQ-DBGA].[dbo].[fydvtsPedidos]
         WHERE VendedorNombre = ?
           AND Estado = 'Pendiente' AND CantidadPendiente > 0''',
      [vendedor],
    );
    return int.tryParse(rows.firstOrNull?['N']?.toString() ?? '0') ?? 0;
  }

  /// Interpreta el estado para el vendedor.
  static String estadoLabel(String estado, double cantPendiente) {
    if (estado == 'Pendiente') return 'Pendiente';
    if (estado == 'Anulado' && cantPendiente > 0) return 'Parcial';
    return 'Facturado';
  }

  static int estadoColor(String estado, double cantPendiente) {
    if (estado == 'Pendiente') return 0xFF10B981; // verde
    if (estado == 'Anulado' && cantPendiente > 0) return 0xFFF59E0B; // naranja
    return 0xFF2563EB; // azul
  }
}
