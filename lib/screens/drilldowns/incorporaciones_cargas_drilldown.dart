import 'dart:convert';
import 'package:flutter/material.dart';
import '../../config/theme.dart';
import '../../services/sql_service.dart';

class IncorporacionesCargasDrilldown extends StatefulWidget {
  final String vendedor;
  final int mes, anio;
  final String paramsJson;

  const IncorporacionesCargasDrilldown({
    super.key,
    required this.vendedor, required this.mes, required this.anio,
    required this.paramsJson,
  });

  @override
  State<IncorporacionesCargasDrilldown> createState() => _State();
}

class _State extends State<IncorporacionesCargasDrilldown> {
  List<Map<String, dynamic>> _computaron = [];
  List<Map<String, dynamic>> _noComputaron = [];
  List<Map<String, dynamic>> _oportunidades = [];
  List<String> _conjuntos = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    try {
      final p = json.decode(widget.paramsJson) as Map<String, dynamic>;
      _conjuntos = (p['conjuntos'] as List?)?.map((e) => e.toString()).toList() ?? [];
    } catch (_) {}
    _load();
  }

  Future<void> _load() async {
    if (_conjuntos.isEmpty) {
      setState(() => _loading = false);
      return;
    }
    setState(() => _loading = true);

    final computaron = <Map<String, dynamic>>[];
    final noComputaron = <Map<String, dynamic>>[];

    for (final conj in _conjuntos) {
      final conjCod = conj.replaceAll("'", "''");

      // Clientes que compraron esta carga este mes
      final rowsMes = await SqlService.query(
        '''SELECT DISTINCT e.ClienteCodigo,
              MAX(c.ClienteNombre) AS ClienteNombre,
              MAX(e.Fecha) AS Fecha
           FROM [EQ-DBGA].[dbo].[fydvtsEstadisticas] e
           LEFT JOIN [EQ-DBGA].[dbo].[fydvtsClientesXLinea] c
              ON c.ClienteCodigo = e.ClienteCodigo
           WHERE e.ConjuntoCodigo = '$conjCod' AND e.NumeraTipoTipo = 2205
             AND YEAR(e.Fecha) = ? AND MONTH(e.Fecha) = ?
             AND e.VendedorNombre = ?
           GROUP BY e.ClienteCodigo''',
        [widget.anio, widget.mes, widget.vendedor],
      );

      // Clientes que compraron esta carga ANTES
      final rowsHist = await SqlService.query(
        '''SELECT DISTINCT ClienteCodigo
           FROM [EQ-DBGA].[dbo].[fydvtsEstadisticas]
           WHERE ConjuntoCodigo = '$conjCod' AND NumeraTipoTipo = 2205
             AND Fecha < DATEFROMPARTS(?, ?, 1)''',
        [widget.anio, widget.mes],
      );
      final histSet = rowsHist.map((r) => r['ClienteCodigo']?.toString()).toSet();

      for (final r in rowsMes) {
        final cli = r['ClienteCodigo']?.toString() ?? '';
        final entry = {
          'ClienteNombre': r['ClienteNombre']?.toString() ?? cli,
          'ClienteCodigo': cli,
          'Carga': conjCod,
          'Fecha': r['Fecha']?.toString().split(' ').first ?? '',
        };
        if (histSet.contains(cli)) {
          noComputaron.add(entry);
        } else {
          computaron.add(entry);
        }
      }
    }

    // Oportunidades: clientes activos que NO tienen ninguna de las cargas
    final conjPhs = _conjuntos.map((c) => "'${c.replaceAll("'", "''")}'").join(',');
    final rowsOport = await SqlService.query(
      '''SELECT c.ClienteCodigo, c.ClienteNombre
         FROM [EQ-DBGA].[dbo].[fydvtsClientesXLinea] c
         WHERE c.VendedorNombre = ? AND c.ClienteSituacion = 'Activo normal'
           AND c.ClienteCodigo NOT IN (
               SELECT DISTINCT ClienteCodigo FROM [EQ-DBGA].[dbo].[fydvtsEstadisticas]
               WHERE ConjuntoCodigo IN ($conjPhs) AND NumeraTipoTipo = 2205
           )
         ORDER BY c.ClienteNombre''',
      [widget.vendedor],
    );

    if (!mounted) return;
    setState(() {
      _computaron = computaron;
      _noComputaron = noComputaron;
      _oportunidades = rowsOport;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        backgroundColor: AppColors.bg,
        appBar: AppBar(
          backgroundColor: AppColors.bgSidebar,
          title: const Text('Incorporaciones Cargas', style: AppTextStyles.title),
          bottom: TabBar(
            indicatorColor: AppColors.primary,
            labelColor: AppColors.textPrimary,
            unselectedLabelColor: AppColors.textMuted,
            labelStyle: const TextStyle(fontSize: 12),
            tabs: [
              Tab(text: 'Nuevos (${_computaron.length})'),
              Tab(text: 'Repetidos (${_noComputaron.length})'),
              Tab(text: 'Oportunidad (${_oportunidades.length})'),
            ],
          ),
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
            : _conjuntos.isEmpty
                ? const Center(child: Text('Sin conjuntos configurados', style: AppTextStyles.caption))
                : TabBarView(children: [
                    _buildList(_computaron, AppColors.success, Icons.check_circle),
                    _buildList(_noComputaron, AppColors.textMuted, Icons.replay),
                    _buildOportunidades(),
                  ]),
      ),
    );
  }

  Widget _buildList(List<Map<String, dynamic>> items, Color color, IconData icon) {
    if (items.isEmpty) {
      return const Center(child: Text('Sin resultados', style: AppTextStyles.caption));
    }
    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: items.length,
      itemBuilder: (_, i) {
        final r = items[i];
        return Container(
          margin: const EdgeInsets.only(bottom: 6),
          padding: const EdgeInsets.all(12),
          decoration: AppCardStyle.base(borderColor: color),
          child: Row(
            children: [
              Icon(icon, color: color, size: 18),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(r['ClienteNombre']?.toString() ?? '', style: AppTextStyles.body),
                    Text('Carga: ${r['Carga']}  ·  ${r['Fecha']}', style: AppTextStyles.muted),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildOportunidades() {
    if (_oportunidades.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.celebration, color: AppColors.success, size: 48),
            SizedBox(height: 12),
            Text('Todos los clientes activos ya tienen estas cargas',
                style: AppTextStyles.caption),
          ],
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: _oportunidades.length,
      itemBuilder: (_, i) {
        final r = _oportunidades[i];
        return Container(
          margin: const EdgeInsets.only(bottom: 6),
          padding: const EdgeInsets.all(12),
          decoration: AppCardStyle.base(borderColor: AppColors.warning),
          child: Row(
            children: [
              Icon(Icons.lightbulb_outline, color: AppColors.warning.withOpacity(0.8), size: 18),
              const SizedBox(width: 10),
              Expanded(child: Text(r['ClienteNombre']?.toString() ?? '', style: AppTextStyles.body)),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AppColors.warning.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Text('Sin cargas', style: TextStyle(
                    color: AppColors.warning, fontSize: 10, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        );
      },
    );
  }
}
