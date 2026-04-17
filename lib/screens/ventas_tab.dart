import 'package:flutter/material.dart';
import '../config/theme.dart';
import '../models/session.dart';
import '../services/ventas_service.dart';
import '../services/drilldown_service.dart';
import '../widgets/kpi_card.dart';
import '../widgets/sales_chart.dart';
import '../widgets/month_selector.dart';
import '../widgets/mes_picker_sheet.dart';
import '../services/cliente_router.dart';

class VentasTab extends StatefulWidget {
  const VentasTab({super.key});

  @override
  State<VentasTab> createState() => _VentasTabState();
}

class _VentasTabState extends State<VentasTab>
    with AutomaticKeepAliveClientMixin {
  bool _loading = true;
  late int _mes, _anio;

  // KPIs
  double _facActual = 0, _facYoY = 0, _meta = 0;

  // Evolución
  List<Map<String, dynamic>> _evoActual = [];
  List<Map<String, dynamic>> _evoAnterior = [];

  // Top 10
  List<Map<String, dynamic>> _topClientes = [];
  List<Map<String, dynamic>> _topProductos = [];

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _mes = now.month;
    _anio = now.year;
    _load();
  }

  void _onMonthChanged(int mes, int anio) {
    setState(() { _mes = mes; _anio = anio; });
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final vendedor = Session.current.vendedorNombre;

    final results = await Future.wait([
      VentasService.getKpis(vendedor, _mes, _anio),
      VentasService.getEvolucion(vendedor, _mes, _anio),
      DrilldownService.topClientes(vendedor, _mes, _anio),
      DrilldownService.topProductos(vendedor, _mes, _anio),
    ]);

    if (!mounted) return;

    final kpis = results[0] as Map<String, double>;
    final evo = results[1] as Map<String, List<Map<String, dynamic>>>;

    setState(() {
      _facActual = kpis['facActual'] ?? 0;
      _facYoY = kpis['facYoY'] ?? 0;
      _meta = kpis['meta'] ?? 0;
      _evoActual = evo['actual'] ?? [];
      _evoAnterior = evo['anterior'] ?? [];
      _topClientes = results[2] as List<Map<String, dynamic>>;
      _topProductos = results[3] as List<Map<String, dynamic>>;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    final now = DateTime.now();
    final esMesNoActual = _mes != now.month || _anio != now.year;

    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.bgSidebar,
        title: const Text('Ventas', style: AppTextStyles.title),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: AppColors.textMuted),
            onPressed: _loading ? null : _load,
          ),
          IconButton(
            icon: Icon(Icons.calendar_month,
                color: esMesNoActual ? AppColors.warning : AppColors.textMuted, size: 20),
            tooltip: 'Cambiar mes',
            onPressed: () {
              showModalBottomSheet(
                context: context,
                backgroundColor: AppColors.bgCard,
                shape: const RoundedRectangleBorder(
                  borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
                ),
                builder: (_) => MesPickerSheet(
                  mesActual: _mes, anioActual: _anio,
                  onPicked: (m, a) { Navigator.pop(context); _onMonthChanged(m, a); },
                ),
              );
            },
          ),
        ],
      ),
      body: Column(
        children: [
          if (esMesNoActual) _bannerMesViendo(),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
                : RefreshIndicator(
                    onRefresh: _load,
                    color: AppColors.primary,
                    child: ListView(
                      padding: const EdgeInsets.all(12),
                      children: [
                        _buildKpis(),
                        const SizedBox(height: 12),
                        SalesChart(actual: _evoActual, anterior: _evoAnterior),
                        const SizedBox(height: 12),
                        _buildTopClientes(),
                        const SizedBox(height: 12),
                        _buildTopProductos(),
                        const SizedBox(height: 32),
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _bannerMesViendo() {
    return GestureDetector(
      onTap: () {
        final now = DateTime.now();
        _onMonthChanged(now.month, now.year);
      },
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        color: AppColors.warning.withOpacity(0.15),
        child: Row(
          children: [
            const Icon(Icons.history, color: AppColors.warning, size: 16),
            const SizedBox(width: 8),
            Expanded(child: Text(
              'Viendo ${MonthSelector.mesNombre(_mes)} $_anio',
              style: const TextStyle(color: AppColors.warning, fontSize: 12, fontWeight: FontWeight.w600),
            )),
            const Text('Volver a actual',
                style: TextStyle(color: AppColors.warning, fontSize: 11,
                    decoration: TextDecoration.underline)),
          ],
        ),
      ),
    );
  }

  Widget _buildKpis() {
    final pctObj = _meta > 0 ? (_facActual / _meta * 100) : 0.0;
    final pctYoY = _facYoY > 0 ? ((_facActual - _facYoY) / _facYoY * 100) : 0.0;
    final deltaYoY = _facActual - _facYoY;

    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: KpiCard(
                label: 'Facturación',
                value: '\$ ${_fmt(_facActual)}',
                icon: Icons.attach_money,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: KpiCard(
                label: '% vs Objetivo',
                value: _meta > 0 ? '${pctObj.toStringAsFixed(1)}%' : 'Sin meta',
                valueColor: _meta > 0
                    ? (pctObj >= 100 ? AppColors.success
                        : pctObj >= 70 ? AppColors.warning : AppColors.danger)
                    : AppColors.textMuted,
                icon: Icons.flag,
                subtitle: _meta > 0 ? 'Meta: \$ ${_fmt(_meta)}' : null,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: KpiCard(
                label: '% vs Año Anterior',
                value: _facYoY > 0 ? '${pctYoY >= 0 ? "+" : ""}${pctYoY.toStringAsFixed(1)}%' : 'Sin datos',
                valueColor: _facYoY > 0
                    ? (pctYoY >= 0 ? AppColors.success : AppColors.danger)
                    : AppColors.textMuted,
                icon: Icons.compare_arrows,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: KpiCard(
                label: 'Delta YoY',
                value: _facYoY > 0
                    ? '${deltaYoY >= 0 ? "+" : ""}\$ ${_fmt(deltaYoY)}'
                    : '-',
                valueColor: deltaYoY >= 0 ? AppColors.success : AppColors.danger,
                icon: Icons.trending_up,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildTopClientes() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: AppCardStyle.base(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Top 10 Clientes', style: AppTextStyles.title),
          const SizedBox(height: 8),
          if (_topClientes.isEmpty)
            const Text('Sin datos', style: AppTextStyles.muted)
          else
            ..._topClientes.asMap().entries.map((entry) {
              final i = entry.key;
              final c = entry.value;
              final monto = double.tryParse(c['Monto']?.toString() ?? '0') ?? 0;
              final facturas = c['Facturas']?.toString() ?? '0';
              final codigo = c['Codigo']?.toString();
              final nombre = c['Cliente']?.toString() ?? '';
              return InkWell(
                onTap: codigo != null
                    ? () => ClienteRouter.open(context, codigo, nombre: nombre)
                    : null,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 22,
                        child: Text('${i + 1}', style: TextStyle(
                          color: i < 3 ? AppColors.accent : AppColors.textMuted,
                          fontSize: 12, fontWeight: FontWeight.bold,
                        )),
                      ),
                      Expanded(
                        child: Text(nombre,
                            style: AppTextStyles.caption, maxLines: 1,
                            overflow: TextOverflow.ellipsis),
                      ),
                      Text('$facturas fc', style: AppTextStyles.muted),
                      const SizedBox(width: 8),
                      Text('\$ ${_fmt(monto)}',
                          style: AppTextStyles.caption.copyWith(fontWeight: FontWeight.bold)),
                      if (codigo != null) ...[
                        const SizedBox(width: 4),
                        const Icon(Icons.chevron_right,
                            color: AppColors.textMuted, size: 14),
                      ],
                    ],
                  ),
                ),
              );
            }),
        ],
      ),
    );
  }

  Widget _buildTopProductos() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: AppCardStyle.base(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Top 10 Productos', style: AppTextStyles.title),
          const SizedBox(height: 8),
          if (_topProductos.isEmpty)
            const Text('Sin datos', style: AppTextStyles.muted)
          else
            ..._topProductos.asMap().entries.map((entry) {
              final i = entry.key;
              final p = entry.value;
              final unidades = p['Unidades']?.toString() ?? '0';
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    SizedBox(
                      width: 22,
                      child: Text('${i + 1}', style: TextStyle(
                        color: i < 3 ? AppColors.accent : AppColors.textMuted,
                        fontSize: 12, fontWeight: FontWeight.bold,
                      )),
                    ),
                    Expanded(
                      child: Text(p['Producto']?.toString() ?? '',
                          style: AppTextStyles.caption, maxLines: 1,
                          overflow: TextOverflow.ellipsis),
                    ),
                    Text('$unidades uds',
                        style: AppTextStyles.caption.copyWith(fontWeight: FontWeight.bold)),
                  ],
                ),
              );
            }),
        ],
      ),
    );
  }

  String _fmt(double v) {
    final neg = v < 0;
    final s = v.abs().toStringAsFixed(0);
    final buf = StringBuffer();
    for (int i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buf.write('.');
      buf.write(s[i]);
    }
    return neg ? '-${buf.toString()}' : buf.toString();
  }
}
