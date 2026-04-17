import 'dart:convert';
import 'sql_service.dart';

/// Queries de drill-down — detalle de cada métrica del scorecard.
class DrilldownService {
  // ── Facturación: top clientes + top productos del vendedor ─────
  static Future<List<Map<String, dynamic>>> topClientes(
      String vendedor, int mes, int anio) async {
    return SqlService.query(
      '''SELECT TOP 10
            e.ClienteCodigo AS Codigo,
            COALESCE(MAX(c.ClienteNombre),
                     MAX(CAST(e.ClienteCodigo AS VARCHAR))) AS Cliente,
            SUM(e.SubTotalNetoLocal) AS Monto,
            COUNT(DISTINCT e.Numero) AS Facturas
         FROM [EQ-DBGA].[dbo].[fydvtsEstadisticas] e
         LEFT JOIN [EQ-DBGA].[dbo].[fydvtsClientesXLinea] c
             ON e.ClienteCodigo = c.ClienteCodigo
         WHERE e.VendedorNombre = ?
           AND YEAR(e.Fecha) = ? AND MONTH(e.Fecha) = ?
           AND e.NumeraTipoTipo IN (2205, 2206)
         GROUP BY e.ClienteCodigo
         ORDER BY Monto DESC''',
      [vendedor, anio, mes],
    );
  }

  static Future<List<Map<String, dynamic>>> topProductos(
      String vendedor, int mes, int anio) async {
    return SqlService.query(
      '''SELECT TOP 10
            MAX(ArticuloNombre) AS Producto,
            SUM(Cantidad) AS Unidades
         FROM [EQ-DBGA].[dbo].[fydvtsEstadisticas]
         WHERE VendedorNombre = ?
           AND YEAR(Fecha) = ? AND MONTH(Fecha) = ?
           AND NumeraTipoTipo IN (2205, 2206)
         GROUP BY ArticuloCodigo
         ORDER BY Unidades DESC''',
      [vendedor, anio, mes],
    );
  }

  // ── Tasa de Conversión: compraron / no compraron ──────────────
  static Future<List<Map<String, dynamic>>> compraron(
      String vendedor, int mes, int anio) async {
    return SqlService.query(
      '''SELECT e.ClienteCodigo,
            MAX(c.ClienteNombre) AS ClienteNombre,
            MAX(c.ClienteCategoria) AS Canal,
            SUM(e.SubTotalNetoLocal) AS Importe,
            MAX(e.Fecha) AS Fecha
         FROM [EQ-DBGA].[dbo].[fydvtsEstadisticas] e
         LEFT JOIN [EQ-DBGA].[dbo].[fydvtsClientesXLinea] c
            ON c.ClienteCodigo = e.ClienteCodigo
           AND c.VendedorNombre = e.VendedorNombre
         WHERE YEAR(e.Fecha) = ? AND MONTH(e.Fecha) = ?
           AND e.NumeraTipoTipo = 2205
           AND e.VendedorNombre = ?
         GROUP BY e.ClienteCodigo
         ORDER BY SUM(e.SubTotalNetoLocal) DESC''',
      [anio, mes, vendedor],
    );
  }

  static Future<List<Map<String, dynamic>>> noCompraron(
      String vendedor, int mes, int anio) async {
    return SqlService.query(
      '''SELECT c.ClienteCodigo, c.ClienteNombre,
            c.ClienteCategoria AS Canal,
            MAX(e.Fecha) AS UltimaCompra,
            DATEDIFF(day, MAX(e.Fecha), GETDATE()) AS DiasInactivo
         FROM [EQ-DBGA].[dbo].[fydvtsClientesXLinea] c
         LEFT JOIN [EQ-DBGA].[dbo].[fydvtsEstadisticas] e
            ON e.ClienteCodigo = c.ClienteCodigo
           AND e.NumeraTipoTipo = 2205
         WHERE c.ClienteSituacion = 'Activo normal'
           AND c.VendedorNombre = ?
           AND c.ClienteCodigo NOT IN (
                SELECT DISTINCT ClienteCodigo
                FROM [EQ-DBGA].[dbo].[fydvtsEstadisticas]
                WHERE YEAR(Fecha) = ? AND MONTH(Fecha) = ?
                  AND NumeraTipoTipo = 2205
                  AND VendedorNombre = ?
           )
         GROUP BY c.ClienteCodigo, c.ClienteNombre, c.ClienteCategoria
         ORDER BY DiasInactivo DESC''',
      [vendedor, anio, mes, vendedor],
    );
  }

  // ── Foco Artículos: facturas + resumen por artículo ───────────
  static Future<List<Map<String, dynamic>>> focoFacturas(
      String vendedor, int mes, int anio, List<String> articulos) async {
    if (articulos.isEmpty) return [];
    final phs = articulos.map((a) => "'${a.replaceAll("'", "''")}'").join(',');
    return SqlService.query(
      '''SELECT e.Numero, MAX(e.Fecha) AS Fecha,
            MAX(e.ClienteCodigo) AS ClienteCodigo,
            MAX(c.ClienteNombre) AS ClienteNombre,
            SUM(e.SubTotalNetoLocal) AS Monto
         FROM [EQ-DBGA].[dbo].[fydvtsEstadisticas] e
         LEFT JOIN [EQ-DBGA].[dbo].[fydvtsClientesXLinea] c
            ON c.ClienteCodigo = e.ClienteCodigo
           AND c.VendedorNombre = e.VendedorNombre
         WHERE YEAR(e.Fecha) = ? AND MONTH(e.Fecha) = ?
           AND e.NumeraTipoTipo IN (2205, 2206)
           AND e.VendedorNombre = ?
           AND e.ArticuloCodigo IN ($phs)
         GROUP BY e.Numero
         ORDER BY MAX(e.Fecha) DESC''',
      [anio, mes, vendedor],
    );
  }

  static Future<List<Map<String, dynamic>>> focoResumen(
      String vendedor, int mes, int anio, List<String> articulos) async {
    if (articulos.isEmpty) return [];
    final phs = articulos.map((a) => "'${a.replaceAll("'", "''")}'").join(',');
    return SqlService.query(
      '''SELECT e.ArticuloCodigo, MAX(e.ArticuloNombre) AS Nombre,
            SUM(e.Cantidad) AS Unidades, SUM(e.SubTotalNetoLocal) AS Importe
         FROM [EQ-DBGA].[dbo].[fydvtsEstadisticas] e
         WHERE YEAR(e.Fecha) = ? AND MONTH(e.Fecha) = ?
           AND e.NumeraTipoTipo IN (2205, 2206)
           AND e.VendedorNombre = ?
           AND e.ArticuloCodigo IN ($phs)
         GROUP BY e.ArticuloCodigo
         ORDER BY SUM(e.SubTotalNetoLocal) DESC''',
      [anio, mes, vendedor],
    );
  }

  // ── Aperturas: detalle de clientes nuevos ─────────────────────
  static Future<List<Map<String, dynamic>>> aperturasDetalle(
      String vendedor, int mes, int anio) async {
    return SqlService.query(
      '''SELECT e1.ClienteCodigo,
            MAX(c.ClienteNombre) AS ClienteNombre,
            MIN(e1.Fecha) AS PrimeraCompra,
            SUM(e1.SubTotalNetoLocal) AS Importe
         FROM [EQ-DBGA].[dbo].[fydvtsEstadisticas] e1
         LEFT JOIN [EQ-DBGA].[dbo].[fydvtsClientesXLinea] c
            ON c.ClienteCodigo = e1.ClienteCodigo
         WHERE YEAR(e1.Fecha) = ? AND MONTH(e1.Fecha) = ?
           AND e1.NumeraTipoTipo = 2205
           AND e1.VendedorNombre = ?
           AND NOT EXISTS (
               SELECT 1 FROM [EQ-DBGA].[dbo].[fydvtsEstadisticas] e2
               WHERE e2.ClienteCodigo = e1.ClienteCodigo
                 AND e2.NumeraTipoTipo = 2205
                 AND e2.Fecha < DATEFROMPARTS(?, ?, 1)
           )
         GROUP BY e1.ClienteCodigo
         ORDER BY Importe DESC''',
      [anio, mes, vendedor, anio, mes],
    );
  }

  // ── Reactivación: detalle de clientes reactivados ─────────────
  static Future<List<Map<String, dynamic>>> reactivacionDetalle(
      String vendedor, int mes, int anio, int diasInactivo) async {
    return SqlService.query(
      '''SELECT e1.ClienteCodigo,
            MAX(c.ClienteNombre) AS ClienteNombre,
            prev.MaxFecha AS UltimaCompraAnterior,
            DATEDIFF(day, prev.MaxFecha, MIN(e1.Fecha)) AS DiasInactivo,
            SUM(e1.SubTotalNetoLocal) AS Importe
         FROM [EQ-DBGA].[dbo].[fydvtsEstadisticas] e1
         LEFT JOIN [EQ-DBGA].[dbo].[fydvtsClientesXLinea] c
            ON c.ClienteCodigo = e1.ClienteCodigo
         CROSS APPLY (
             SELECT MAX(e2.Fecha) AS MaxFecha
             FROM [EQ-DBGA].[dbo].[fydvtsEstadisticas] e2
             WHERE e2.ClienteCodigo = e1.ClienteCodigo
               AND e2.NumeraTipoTipo = 2205
               AND e2.Fecha < DATEFROMPARTS(?, ?, 1)
         ) prev
         WHERE YEAR(e1.Fecha) = ? AND MONTH(e1.Fecha) = ?
           AND e1.NumeraTipoTipo = 2205
           AND e1.VendedorNombre = ?
           AND prev.MaxFecha <= DATEADD(day, ?, DATEFROMPARTS(?, ?, 1))
         GROUP BY e1.ClienteCodigo, prev.MaxFecha
         ORDER BY DiasInactivo DESC''',
      [anio, mes, anio, mes, vendedor, -diasInactivo, anio, mes],
    );
  }
}
