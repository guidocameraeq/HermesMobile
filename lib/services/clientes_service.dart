import '../models/cliente.dart';
import 'sql_service.dart';

/// Queries de clientes — todo vía SQL Server (VPN).
class ClientesService {
  /// Lista de clientes del vendedor con última compra y saldo CxC.
  static Future<List<Cliente>> getClientes(String vendedor) async {
    // 1. Clientes del vendedor con última compra
    final rowsClientes = await SqlService.query(
      '''SELECT c.ClienteCodigo, c.ClienteNombre, c.ClienteCategoria,
              c.ClienteSituacion, c.LocalidadNombre, c.ProvinciaNombre,
              MAX(e.Fecha) AS UltimaCompra
         FROM [EQ-DBGA].[dbo].[fydvtsClientesXLinea] c
         LEFT JOIN [EQ-DBGA].[dbo].[fydvtsEstadisticas] e
            ON e.ClienteCodigo = c.ClienteCodigo
           AND e.NumeraTipoTipo = 2205
         WHERE c.VendedorNombre = ?
         GROUP BY c.ClienteCodigo, c.ClienteNombre, c.ClienteCategoria,
                  c.ClienteSituacion, c.LocalidadNombre, c.ProvinciaNombre
         ORDER BY c.ClienteNombre''',
      [vendedor],
    );

    // 2. Saldos CxC agrupados por cliente
    final rowsSaldos = await SqlService.query(
      '''SELECT ClienteCodigo,
              SUM(ImpPendiente) AS Saldo,
              MAX(Atraso) AS MaxAtraso
         FROM [EQ-DBGA].[dbo].[fydvtsCtasCtes]
         WHERE VendedorNombre = ? AND ImpPendiente > 0
         GROUP BY ClienteCodigo''',
      [vendedor],
    );

    // Index saldos por código
    final saldoMap = <String, (double saldo, int atraso)>{};
    for (final r in rowsSaldos) {
      final cod = r['ClienteCodigo']?.toString() ?? '';
      final saldo = double.tryParse(r['Saldo']?.toString() ?? '0') ?? 0;
      final atraso = int.tryParse(r['MaxAtraso']?.toString() ?? '0') ?? 0;
      saldoMap[cod] = (saldo, atraso);
    }

    return rowsClientes.map((r) {
      final cod = r['ClienteCodigo']?.toString() ?? '';
      final saldoData = saldoMap[cod];
      DateTime? ultimaCompra;
      final fechaStr = r['UltimaCompra']?.toString();
      if (fechaStr != null && fechaStr != 'null') {
        ultimaCompra = DateTime.tryParse(fechaStr);
      }

      return Cliente(
        codigo: cod,
        nombre: r['ClienteNombre']?.toString() ?? '',
        categoria: r['ClienteCategoria']?.toString() ?? '',
        situacion: r['ClienteSituacion']?.toString() ?? '',
        localidad: r['LocalidadNombre']?.toString() ?? '',
        provincia: r['ProvinciaNombre']?.toString() ?? '',
        ultimaCompra: ultimaCompra,
        saldo: saldoData?.$1 ?? 0,
        maxAtraso: saldoData?.$2 ?? 0,
      );
    }).toList();
  }

  /// Evolución mensual de un cliente (últimos 6 meses).
  static Future<List<Map<String, dynamic>>> evolucionMensual(
      String clienteCodigo) async {
    return SqlService.query(
      '''SELECT YEAR(Fecha) AS Anio, MONTH(Fecha) AS Mes,
              SUM(CASE WHEN NumeraTipoTipo = 2205 THEN SubTotalNetoLocal
                       WHEN NumeraTipoTipo = 2206 THEN -ABS(SubTotalNetoLocal)
                       ELSE 0 END) AS Monto,
              COUNT(DISTINCT Numero) AS Facturas
         FROM [EQ-DBGA].[dbo].[fydvtsEstadisticas]
         WHERE ClienteCodigo = ?
           AND NumeraTipoTipo IN (2205, 2206)
           AND Fecha >= DATEADD(MONTH, -6, GETDATE())
         GROUP BY YEAR(Fecha), MONTH(Fecha)
         ORDER BY Anio, Mes''',
      [clienteCodigo],
    );
  }

  /// Últimas facturas de un cliente.
  static Future<List<Map<String, dynamic>>> ultimasFacturas(
      String clienteCodigo) async {
    return SqlService.query(
      '''SELECT TOP 20 Numero, MAX(Fecha) AS Fecha,
              SUM(SubTotalNetoLocal) AS Monto, MAX(NumeraTipoTipo) AS Tipo
         FROM [EQ-DBGA].[dbo].[fydvtsEstadisticas]
         WHERE ClienteCodigo = ? AND NumeraTipoTipo IN (2205, 2206)
         GROUP BY Numero
         ORDER BY MAX(Fecha) DESC''',
      [clienteCodigo],
    );
  }

  /// Detalle de saldo CxC de un cliente (documentos pendientes).
  static Future<List<Map<String, dynamic>>> saldoDetalle(
      String clienteCodigo) async {
    return SqlService.query(
      '''SELECT Numero, Fecha, FechaVto, ImpPendiente, Atraso, AtrasoDetalle,
              NumeraTipoNombre
         FROM [EQ-DBGA].[dbo].[fydvtsCtasCtes]
         WHERE ClienteCodigo = ? AND ImpPendiente > 0
         ORDER BY Atraso DESC''',
      [clienteCodigo],
    );
  }
}
