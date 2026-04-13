import 'package:flutter/material.dart';
import '../../config/theme.dart';
import '../../services/drilldown_service.dart';

class FacturacionDrilldown extends StatefulWidget {
  final String vendedor;
  final int mes, anio;

  const FacturacionDrilldown({
    super.key,
    required this.vendedor,
    required this.mes,
    required this.anio,
  });

  @override
  State<FacturacionDrilldown> createState() => _FacturacionDrilldownState();
}

class _FacturacionDrilldownState extends State<FacturacionDrilldown> {
  List<Map<String, dynamic>> _clientes = [];
  List<Map<String, dynamic>> _productos = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final results = await Future.wait([
      DrilldownService.topClientes(widget.vendedor, widget.mes, widget.anio),
      DrilldownService.topProductos(widget.vendedor, widget.mes, widget.anio),
    ]);
    if (!mounted) return;
    setState(() {
      _clientes = results[0];
      _productos = results[1];
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
          title: const Text('Facturación — Detalle', style: AppTextStyles.title),
          bottom: const TabBar(
            indicatorColor: AppColors.primary,
            labelColor: AppColors.textPrimary,
            unselectedLabelColor: AppColors.textMuted,
            tabs: [
              Tab(text: 'Top Clientes'),
              Tab(text: 'Top Productos'),
            ],
          ),
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
            : TabBarView(children: [
                _buildClientesList(),
                _buildProductosList(),
              ]),
      ),
    );
  }

  Widget _buildClientesList() {
    if (_clientes.isEmpty) {
      return const Center(child: Text('Sin datos', style: AppTextStyles.caption));
    }
    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: _clientes.length,
      itemBuilder: (_, i) {
        final c = _clientes[i];
        final monto = double.tryParse(c['Monto']?.toString() ?? '0') ?? 0;
        final facturas = c['Facturas']?.toString() ?? '0';
        return Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.all(14),
          decoration: AppCardStyle.base(),
          child: Row(
            children: [
              CircleAvatar(
                radius: 16,
                backgroundColor: AppColors.primary.withOpacity(0.2),
                child: Text('${i + 1}', style: const TextStyle(color: AppColors.primary, fontSize: 12, fontWeight: FontWeight.bold)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(c['Cliente']?.toString() ?? '', style: AppTextStyles.body),
                    Text('$facturas facturas', style: AppTextStyles.muted),
                  ],
                ),
              ),
              Text('\$ ${_fmt(monto)}', style: AppTextStyles.title.copyWith(fontSize: 14)),
            ],
          ),
        );
      },
    );
  }

  Widget _buildProductosList() {
    if (_productos.isEmpty) {
      return const Center(child: Text('Sin datos', style: AppTextStyles.caption));
    }
    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: _productos.length,
      itemBuilder: (_, i) {
        final p = _productos[i];
        final unidades = p['Unidades']?.toString() ?? '0';
        return Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.all(14),
          decoration: AppCardStyle.base(),
          child: Row(
            children: [
              CircleAvatar(
                radius: 16,
                backgroundColor: AppColors.accent.withOpacity(0.2),
                child: Text('${i + 1}', style: const TextStyle(color: AppColors.accent, fontSize: 12, fontWeight: FontWeight.bold)),
              ),
              const SizedBox(width: 12),
              Expanded(child: Text(p['Producto']?.toString() ?? '', style: AppTextStyles.body)),
              Text('$unidades uds', style: AppTextStyles.caption.copyWith(fontWeight: FontWeight.bold)),
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
