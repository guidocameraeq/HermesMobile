import '../models/cliente.dart';
import 'sql_service.dart';
import 'clientes_cache.dart';
import 'connectivity_service.dart';

/// Resultado enriquecido de una carga de clientes.
class ClientesResult {
  final List<Cliente> clientes;
  final bool fromCache;
  final DateTime? cacheTimestamp;
  final List<String> clientesRemovidos;

  ClientesResult({
    required this.clientes,
    required this.fromCache,
    required this.cacheTimestamp,
    required this.clientesRemovidos,
  });
}

/// Queries de clientes — SQL Server con cache local como fallback.
class ClientesService {
  /// Resultado enriquecido de getClientes — incluye metadata de cache.
  /// Hoy [getClientes] devuelve solo la lista (compat). [getClientesWithMeta]
  /// devuelve toda la info para la UI.
  static Future<ClientesResult> getClientesWithMeta(
      String vendedor, {bool forceRefresh = false}) async {
    // Intento live (SQL Server vía VPN)
    if (!forceRefresh || true) {
      try {
        final live = await _fetchFromSql(vendedor);
        // Detectar clientes removidos comparando con cache previo
        final prev = await ClientesCache.load(vendedor);
        final removidos = <String>{};
        if (prev != null) {
          final codsVivos = live.map((c) => c.codigo).toSet();
          for (final c in prev) {
            if (!codsVivos.contains(c.codigo)) removidos.add(c.nombre);
          }
        }
        await ClientesCache.save(vendedor, live);
        ConnectivityService.markOk();
        return ClientesResult(
          clientes: live,
          fromCache: false,
          cacheTimestamp: DateTime.now(),
          clientesRemovidos: removidos.toList(),
        );
      } catch (_) {
        ConnectivityService.markFailed();
      }
    }

    // Fallback: cache
    final cached = await ClientesCache.load(vendedor);
    if (cached != null) {
      final ts = await ClientesCache.lastUpdate(vendedor);
      return ClientesResult(
        clientes: cached,
        fromCache: true,
        cacheTimestamp: ts,
        clientesRemovidos: const [],
      );
    }

    // Sin cache y sin VPN
    throw Exception(
        'Sin conexión VPN y sin lista local guardada. Conectate a la VPN al menos una vez para descargar tu cartera.');
  }

  /// Compat: lista simple (usa cache como fallback silenciosamente).
  static Future<List<Cliente>> getClientes(String vendedor) async {
    final r = await getClientesWithMeta(vendedor);
    return r.clientes;
  }

  /// Query real al SQL Server.
  static Future<List<Cliente>> _fetchFromSql(String vendedor) async {
    final results = await Future.wait([
      SqlService.query(
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
      ),
      SqlService.query(
        '''SELECT ClienteCodigo,
                SUM(ImpPendiente) AS Saldo,
                MAX(Atraso) AS MaxAtraso
           FROM [EQ-DBGA].[dbo].[fydvtsCtasCtes]
           WHERE VendedorNombre = ? AND ImpPendiente > 0
           GROUP BY ClienteCodigo''',
        [vendedor],
      ),
    ]);
    final rowsClientes = results[0];
    final rowsSaldos = results[1];

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

  /// Resuelve el nombre actual de un cliente desde cache local (si existe).
  /// Sirve para mostrar el nombre más reciente aunque una actividad vieja
  /// tenga el nombre anterior guardado.
  static Future<String?> nombreActualDesdeCache(
      String vendedor, String codigo) async {
    final cached = await ClientesCache.load(vendedor);
    if (cached == null) return null;
    try {
      return cached.firstWhere((c) => c.codigo == codigo).nombre;
    } catch (_) {
      return null;
    }
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
