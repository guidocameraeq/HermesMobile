import 'dart:convert';
import 'package:flutter/material.dart';
import '../../config/theme.dart';
import '../../services/sql_service.dart';
import 'oportunidades_cargas_screen.dart';

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

      // Clientes que compraron esta carga este mes + nombre de la carga
      final rowsMes = await SqlService.query(
        '''SELECT DISTINCT e.ClienteCodigo,
              MAX(c.ClienteNombre) AS ClienteNombre,
              MAX(e.ConjuntoNombre) AS CargaNombre,
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
        final cargaNombre = r['CargaNombre']?.toString() ?? conjCod;
        final entry = {
          'ClienteNombre': r['ClienteNombre']?.toString() ?? cli,
          'ClienteCodigo': cli,
          'CargaNombre': cargaNombre,
          'CargaCodigo': conjCod,
          'Fecha': r['Fecha']?.toString().split(' ').first ?? '',
        };
        if (histSet.contains(cli)) {
          noComputaron.add(entry);
        } else {
          computaron.add(entry);
        }
      }
    }

    if (!mounted) return;
    setState(() {
      _computaron = computaron;
      _noComputaron = noComputaron;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: AppColors.bg,
        appBar: AppBar(
          backgroundColor: AppColors.bgSidebar,
          title: const Text('Incorporaciones Cargas', style: AppTextStyles.title),
          bottom: TabBar(
            indicatorColor: AppColors.primary,
            labelColor: AppColors.textPrimary,
            unselectedLabelColor: AppColors.textMuted,
            tabs: [
              Tab(text: 'Nuevos (${_computaron.length})'),
              Tab(text: 'Repetidos (${_noComputaron.length})'),
            ],
          ),
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
            : _conjuntos.isEmpty
                ? const Center(child: Text('Sin conjuntos configurados', style: AppTextStyles.caption))
                : Column(
                    children: [
                      Expanded(
                        child: TabBarView(children: [
                          _buildList(_computaron, AppColors.success, Icons.check_circle),
                          _buildList(_noComputaron, AppColors.textMuted, Icons.replay),
                        ]),
                      ),
                      // Botón Oportunidades
                      Padding(
                        padding: const EdgeInsets.all(16),
                        child: SizedBox(
                          width: double.infinity,
                          height: 48,
                          child: ElevatedButton.icon(
                            onPressed: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => OportunidadesCargasScreen(
                                  vendedor: widget.vendedor,
                                  conjuntos: _conjuntos,
                                ),
                              ),
                            ),
                            icon: const Icon(Icons.lightbulb_outline, size: 20),
                            label: const Text('Ver Oportunidades',
                                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.warning,
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              elevation: 0,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
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
                    Text(r['ClienteNombre']?.toString() ?? '',
                        style: AppTextStyles.body, maxLines: 1, overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: AppColors.accent.withOpacity(0.12),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            r['CargaNombre']?.toString() ?? '',
                            style: const TextStyle(color: AppColors.accent, fontSize: 10, fontWeight: FontWeight.bold),
                            maxLines: 1, overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const Spacer(),
                        Text(r['Fecha']?.toString() ?? '', style: AppTextStyles.muted),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
