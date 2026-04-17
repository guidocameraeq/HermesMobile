import 'pg_service.dart';
import 'sql_service.dart';

/// Datos de cuotas por cliente: meta vs facturación real.
class CuotaCliente {
  final String codigo;
  final String nombre;
  final String categoria; // Mayorista/Minorista
  final double meta;
  final double facturado;
  final double pendiente;
  final String semaforo; // verde, amarillo, rojo, gris

  CuotaCliente({
    required this.codigo,
    required this.nombre,
    required this.categoria,
    required this.meta,
    required this.facturado,
    this.pendiente = 0,
    required this.semaforo,
  });

  double get total => facturado + pendiente;
  double get pct => meta > 0 ? (total / meta * 100) : 0;
}

class CuotasResumen {
  final int verdes, amarillos, rojos, sinMeta;
  final double montoVerde, montoAmarillo, montoRojo, montoSinMeta;

  CuotasResumen({
    required this.verdes, required this.amarillos,
    required this.rojos, required this.sinMeta,
    required this.montoVerde, required this.montoAmarillo,
    required this.montoRojo, required this.montoSinMeta,
  });
}

class CuotasResult {
  final List<CuotaCliente> clientes;
  final CuotasResumen resumen;
  CuotasResult({required this.clientes, required this.resumen});
}

class CuotasService {
  /// Carga cuotas + facturación + padrón + pendientes, los cruza y retorna.
  static Future<CuotasResult> loadCuotas(
    String vendedor, int mes, int anio, {bool inclPend = false,}
  ) async {
    // Q1: Cuotas desde Supabase (sin VPN)
    final cuotasFut = PgService.query(
      'SELECT cliente_codigo, cliente_nombre, importe_meta '
      'FROM cuotas_clientes '
      'WHERE vendedor_nombre = @vendedor AND mes = @mes AND anio = @anio',
      {'vendedor': vendedor, 'mes': mes, 'anio': anio},
    );

    // Q2-Q4: SQL Server en paralelo
    final sqlFutures = <Future<List<Map<String, dynamic>>>>[
      // Q2: Facturación por cliente
      SqlService.query(
        '''SELECT ClienteCodigo,
              SUM(CASE WHEN NumeraTipoTipo = 2205 THEN SubTotalNetoLocal
                       WHEN NumeraTipoTipo = 2206 THEN -ABS(SubTotalNetoLocal)
                       ELSE 0 END) AS Facturado
           FROM [EQ-DBGA].[dbo].[fydvtsEstadisticas]
           WHERE YEAR(Fecha) = ? AND MONTH(Fecha) = ?
             AND VendedorNombre = ? AND NumeraTipoTipo IN (2205, 2206)
           GROUP BY ClienteCodigo''',
        [anio, mes, vendedor],
      ),
      // Q3: Padrón
      SqlService.query(
        '''SELECT DISTINCT ClienteCodigo, ClienteNombre, ClienteCategoria
           FROM [EQ-DBGA].[dbo].[fydvtsClientesXLinea]
           WHERE VendedorNombre = ? AND ClienteSituacion = 'Activo normal' ''',
        [vendedor],
      ),
    ];
    if (inclPend) {
      // Q4: Pendientes
      sqlFutures.add(SqlService.query(
        '''SELECT ClienteCodigo, SUM(SubTotalNetoPendienteLocal) AS Pendiente
           FROM [EQ-DBGA].[dbo].[fydvtsPedidos]
           WHERE VendedorNombre = ? AND Estado = 'Pendiente' AND CantidadPendiente > 0
           GROUP BY ClienteCodigo''',
        [vendedor],
      ));
    }

    // Ejecutar todo en paralelo
    final results = await Future.wait([cuotasFut, ...sqlFutures]);
    final cuotasRows = results[0];
    final factRows = results[1];
    final padronRows = results[2];
    final pendRows = inclPend && results.length > 3 ? results[3] : <Map<String, dynamic>>[];

    // Index facturación por código
    final factMap = <String, double>{};
    for (final r in factRows) {
      factMap[r['ClienteCodigo']?.toString() ?? ''] =
          double.tryParse(r['Facturado']?.toString() ?? '0') ?? 0;
    }

    // Index padrón por código
    final padronMap = <String, Map<String, String>>{};
    for (final r in padronRows) {
      final cod = r['ClienteCodigo']?.toString() ?? '';
      padronMap[cod] = {
        'nombre': r['ClienteNombre']?.toString() ?? cod,
        'categoria': r['ClienteCategoria']?.toString() ?? '',
      };
    }

    // Index pendientes por código
    final pendMap = <String, double>{};
    for (final r in pendRows) {
      pendMap[r['ClienteCodigo']?.toString() ?? ''] =
          double.tryParse(r['Pendiente']?.toString() ?? '0') ?? 0;
    }

    // Merge: cuotas + facturación + padrón
    final clientes = <CuotaCliente>[];
    final codigosConCuota = <String>{};

    for (final c in cuotasRows) {
      final cod = c['cliente_codigo']?.toString() ?? '';
      codigosConCuota.add(cod);
      final meta = double.tryParse(c['importe_meta']?.toString() ?? '0') ?? 0;
      final fact = factMap[cod] ?? 0;
      final pend = pendMap[cod] ?? 0;
      final padron = padronMap[cod];
      final nombre = padron?['nombre'] ?? c['cliente_nombre']?.toString() ?? cod;
      final categoria = padron?['categoria'] ?? '';

      final total = fact + pend;
      final pct = meta > 0 ? (total / meta * 100) : 0;
      final semaforo = meta <= 0 ? 'gris'
          : pct >= 100 ? 'verde'
          : pct >= 51 ? 'amarillo' : 'rojo';

      clientes.add(CuotaCliente(
        codigo: cod, nombre: nombre, categoria: categoria,
        meta: meta, facturado: fact, pendiente: pend, semaforo: semaforo,
      ));
    }

    // Clientes que facturaron pero NO tienen cuota
    for (final e in factMap.entries) {
      if (!codigosConCuota.contains(e.key) && e.value > 0) {
        final padron = padronMap[e.key];
        clientes.add(CuotaCliente(
          codigo: e.key,
          nombre: padron?['nombre'] ?? e.key,
          categoria: padron?['categoria'] ?? '',
          meta: 0, facturado: e.value, pendiente: pendMap[e.key] ?? 0,
          semaforo: 'gris',
        ));
      }
    }

    // Ordenar por % descendente
    clientes.sort((a, b) => b.pct.compareTo(a.pct));

    // Calcular resumen
    int verdes = 0, amarillos = 0, rojos = 0, sinMeta = 0;
    double mVerde = 0, mAmarillo = 0, mRojo = 0, mSinMeta = 0;
    for (final c in clientes) {
      switch (c.semaforo) {
        case 'verde':   verdes++;   mVerde += c.total;
        case 'amarillo': amarillos++; mAmarillo += c.total;
        case 'rojo':    rojos++;    mRojo += c.total;
        default:        sinMeta++;  mSinMeta += c.total;
      }
    }

    return CuotasResult(
      clientes: clientes,
      resumen: CuotasResumen(
        verdes: verdes, amarillos: amarillos, rojos: rojos, sinMeta: sinMeta,
        montoVerde: mVerde, montoAmarillo: mAmarillo,
        montoRojo: mRojo, montoSinMeta: mSinMeta,
      ),
    );
  }
}
