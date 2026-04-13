import 'dart:convert';
import 'package:flutter/material.dart';
import '../../config/theme.dart';
import '../../services/drilldown_service.dart';

class FocoDrilldown extends StatefulWidget {
  final String vendedor;
  final int mes, anio;
  final String paramsJson;

  const FocoDrilldown({
    super.key,
    required this.vendedor,
    required this.mes,
    required this.anio,
    required this.paramsJson,
  });

  @override
  State<FocoDrilldown> createState() => _FocoDrilldownState();
}

class _FocoDrilldownState extends State<FocoDrilldown> {
  List<Map<String, dynamic>> _facturas = [];
  List<Map<String, dynamic>> _resumen = [];
  List<String> _articulos = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    try {
      final p = json.decode(widget.paramsJson) as Map<String, dynamic>;
      _articulos = (p['articulos'] as List?)?.map((e) => e.toString()).toList() ?? [];
    } catch (_) {}
    _load();
  }

  Future<void> _load() async {
    if (_articulos.isEmpty) {
      setState(() => _loading = false);
      return;
    }
    setState(() => _loading = true);
    final results = await Future.wait([
      DrilldownService.focoFacturas(widget.vendedor, widget.mes, widget.anio, _articulos),
      DrilldownService.focoResumen(widget.vendedor, widget.mes, widget.anio, _articulos),
    ]);
    if (!mounted) return;
    setState(() {
      _facturas = results[0];
      _resumen = results[1];
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
          title: const Text('Artículos Foco', style: AppTextStyles.title),
          bottom: const TabBar(
            indicatorColor: AppColors.primary,
            labelColor: AppColors.textPrimary,
            unselectedLabelColor: AppColors.textMuted,
            tabs: [
              Tab(text: 'Por Artículo'),
              Tab(text: 'Facturas'),
            ],
          ),
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
            : _articulos.isEmpty
                ? const Center(child: Text('Sin artículos configurados', style: AppTextStyles.caption))
                : TabBarView(children: [
                    _buildResumenList(),
                    _buildFacturasList(),
                  ]),
      ),
    );
  }

  Widget _buildResumenList() {
    // Artículos con venta
    final conVenta = <String>{};
    for (final r in _resumen) {
      conVenta.add(r['ArticuloCodigo']?.toString() ?? '');
    }
    // Artículos sin venta
    final sinVenta = _articulos.where((a) => !conVenta.contains(a)).toList();

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        ..._resumen.map((r) {
          final unidades = r['Unidades']?.toString() ?? '0';
          final importe = double.tryParse(r['Importe']?.toString() ?? '0') ?? 0;
          return Container(
            margin: const EdgeInsets.only(bottom: 6),
            padding: const EdgeInsets.all(12),
            decoration: AppCardStyle.base(borderColor: AppColors.success),
            child: Row(
              children: [
                const Icon(Icons.check_circle, color: AppColors.success, size: 18),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(r['Nombre']?.toString() ?? r['ArticuloCodigo']?.toString() ?? '',
                          style: AppTextStyles.body),
                      Text('Código: ${r['ArticuloCodigo']}', style: AppTextStyles.muted),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text('$unidades uds', style: AppTextStyles.caption.copyWith(fontWeight: FontWeight.bold)),
                    Text('\$ ${_fmt(importe)}', style: AppTextStyles.muted),
                  ],
                ),
              ],
            ),
          );
        }),
        // Artículos sin venta (en rojo)
        ...sinVenta.map((code) => Container(
              margin: const EdgeInsets.only(bottom: 6),
              padding: const EdgeInsets.all(12),
              decoration: AppCardStyle.base(borderColor: AppColors.danger),
              child: Row(
                children: [
                  const Icon(Icons.cancel, color: AppColors.danger, size: 18),
                  const SizedBox(width: 10),
                  Expanded(child: Text(code, style: AppTextStyles.body)),
                  const Text('Sin ventas', style: TextStyle(color: AppColors.danger, fontSize: 12, fontWeight: FontWeight.bold)),
                ],
              ),
            )),
      ],
    );
  }

  Widget _buildFacturasList() {
    if (_facturas.isEmpty) {
      return const Center(child: Text('Sin facturas', style: AppTextStyles.caption));
    }
    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: _facturas.length,
      itemBuilder: (_, i) {
        final f = _facturas[i];
        final monto = double.tryParse(f['Monto']?.toString() ?? '0') ?? 0;
        return Container(
          margin: const EdgeInsets.only(bottom: 6),
          padding: const EdgeInsets.all(12),
          decoration: AppCardStyle.base(),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Nro ${f['Numero']}', style: AppTextStyles.body),
                    Text(f['ClienteNombre']?.toString() ?? '', style: AppTextStyles.muted),
                  ],
                ),
              ),
              Text('\$ ${_fmt(monto)}', style: AppTextStyles.caption.copyWith(fontWeight: FontWeight.bold)),
            ],
          ),
        );
      },
    );
  }

  String _fmt(double v) {
    final s = v.toStringAsFixed(0);
    final buf = StringBuffer();
    for (int i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buf.write('.');
      buf.write(s[i]);
    }
    return buf.toString();
  }
}
