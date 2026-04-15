import 'package:flutter/material.dart';
import '../config/theme.dart';
import '../models/session.dart';
import '../services/pedidos_service.dart';
import '../widgets/month_selector.dart';
import '../widgets/kpi_card.dart';
import 'pedido_detail_screen.dart';

class PedidosScreen extends StatefulWidget {
  const PedidosScreen({super.key});

  @override
  State<PedidosScreen> createState() => _PedidosState();
}

class _PedidosState extends State<PedidosScreen> {
  List<Map<String, dynamic>> _pedidos = [];
  Map<String, dynamic> _kpis = {};
  bool _loading = true;
  String _search = '';
  String _filtro = 'Todos'; // Todos | Pendientes | Facturados
  late int _mes, _anio;

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
      PedidosService.getPedidos(vendedor, _mes, _anio),
      PedidosService.getKpis(vendedor, _mes, _anio),
    ]);
    if (!mounted) return;
    setState(() {
      _pedidos = results[0] as List<Map<String, dynamic>>;
      _kpis = results[1] as Map<String, dynamic>;
      _loading = false;
    });
  }

  List<Map<String, dynamic>> get _filtered {
    return _pedidos.where((p) {
      final estado = p['Estado']?.toString() ?? '';
      final cantPend = double.tryParse(p['CantPendiente']?.toString() ?? '0') ?? 0;
      final label = PedidosService.estadoLabel(estado, cantPend);

      // Filtro estado
      if (_filtro == 'Pendientes' && label != 'Pendiente') return false;
      if (_filtro == 'Cerrados' && label != 'Cerrado') return false;

      // Búsqueda
      if (_search.isNotEmpty) {
        final q = _search.toLowerCase();
        final cliente = p['Cliente']?.toString().toLowerCase() ?? '';
        final numero = p['Numero']?.toString().toLowerCase() ?? '';
        return cliente.contains(q) || numero.contains(q);
      }
      return true;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filtered;

    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.bgSidebar,
        title: const Text('Pedidos', style: AppTextStyles.title),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: AppColors.textMuted),
            onPressed: _loading ? null : _load,
          ),
        ],
      ),
      body: Column(
        children: [
          MonthSelector(mes: _mes, anio: _anio, onChanged: _onMonthChanged),
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
                        _buildSearchAndFilters(),
                        const SizedBox(height: 8),
                        if (filtered.isEmpty)
                          const Padding(
                            padding: EdgeInsets.all(32),
                            child: Center(child: Text('Sin pedidos', style: AppTextStyles.caption)),
                          )
                        else
                          ...filtered.map((p) => _PedidoTile(
                            pedido: p,
                            onTap: () => Navigator.push(context, MaterialPageRoute(
                              builder: (_) => PedidoDetailScreen(
                                numero: p['Numero']?.toString() ?? '',
                                cliente: p['Cliente']?.toString() ?? '',
                                fecha: p['Fecha']?.toString() ?? '',
                                estado: p['Estado']?.toString() ?? '',
                                cantPendiente: double.tryParse(p['CantPendiente']?.toString() ?? '0') ?? 0,
                              ),
                            )),
                          )),
                        const SizedBox(height: 32),
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildKpis() {
    final pendientes = _kpis['Pendientes'] ?? 0;
    final montoPend = _kpis['MontoPendiente'] as double? ?? 0;
    final cerrados = _kpis['Cerrados'] ?? 0;

    return Row(
      children: [
        Expanded(child: KpiCard(
          label: 'Pendientes',
          value: '$pendientes',
          subtitle: '\$ ${_fmt(montoPend)}',
          valueColor: pendientes > 0 ? AppColors.success : AppColors.textMuted,
          icon: Icons.hourglass_bottom,
        )),
        const SizedBox(width: 8),
        Expanded(child: KpiCard(
          label: 'Cerrados',
          value: '$cerrados',
          icon: Icons.check_circle_outline,
        )),
      ],
    );
  }

  Widget _buildSearchAndFilters() {
    return Column(
      children: [
        TextField(
          style: AppTextStyles.body,
          decoration: InputDecoration(
            hintText: 'Buscar por cliente o nro pedido...',
            hintStyle: AppTextStyles.muted,
            prefixIcon: const Icon(Icons.search, color: AppColors.textMuted, size: 20),
            filled: true,
            fillColor: AppColors.bgCard,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide.none,
            ),
            contentPadding: const EdgeInsets.symmetric(vertical: 10),
          ),
          onChanged: (v) => setState(() => _search = v),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            _chip('Todos'),
            const SizedBox(width: 6),
            _chip('Pendientes'),
            const SizedBox(width: 6),
            _chip('Cerrados'),
            const Spacer(),
            Text('${_filtered.length} pedidos', style: AppTextStyles.muted),
          ],
        ),
      ],
    );
  }

  Widget _chip(String label) {
    final selected = _filtro == label;
    return ChoiceChip(
      label: Text(label, style: TextStyle(
        fontSize: 12,
        color: selected ? Colors.white : AppColors.textMuted,
        fontWeight: selected ? FontWeight.bold : FontWeight.normal,
      )),
      selected: selected,
      onSelected: (_) => setState(() => _filtro = label),
      selectedColor: AppColors.primary,
      backgroundColor: AppColors.bgCard,
      side: BorderSide.none,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      visualDensity: VisualDensity.compact,
      padding: const EdgeInsets.symmetric(horizontal: 6),
    );
  }

  String _fmt(double v) {
    final s = v.abs().toStringAsFixed(0);
    final buf = StringBuffer();
    for (int i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buf.write('.');
      buf.write(s[i]);
    }
    return v < 0 ? '-${buf.toString()}' : buf.toString();
  }
}

class _PedidoTile extends StatelessWidget {
  final Map<String, dynamic> pedido;
  final VoidCallback onTap;

  const _PedidoTile({required this.pedido, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final numero = pedido['Numero']?.toString() ?? '';
    final cliente = pedido['Cliente']?.toString() ?? '';
    final items = pedido['Items']?.toString() ?? '0';
    final estado = pedido['Estado']?.toString() ?? '';
    final cantPend = double.tryParse(pedido['CantPendiente']?.toString() ?? '0') ?? 0;
    final montoTotal = double.tryParse(pedido['MontoTotal']?.toString() ?? '0') ?? 0;
    final montoPend = double.tryParse(pedido['MontoPendiente']?.toString() ?? '0') ?? 0;

    final label = PedidosService.estadoLabel(estado, cantPend);
    final color = Color(PedidosService.estadoColor(estado, cantPend));

    final fechaStr = pedido['Fecha']?.toString().split(' ').first ?? '';

    // Monto a mostrar: pendiente si es pendiente, total si ya facturado
    final montoShow = label == 'Pendiente' ? montoPend : montoTotal;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(14),
        decoration: AppCardStyle.base(borderColor: color),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(numero, style: AppTextStyles.caption.copyWith(fontWeight: FontWeight.bold),
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                ),
                Text(fechaStr, style: AppTextStyles.muted),
              ],
            ),
            const SizedBox(height: 4),
            Text(cliente, style: AppTextStyles.body,
                maxLines: 1, overflow: TextOverflow.ellipsis),
            const SizedBox(height: 6),
            Row(
              children: [
                Text('$items items', style: AppTextStyles.muted),
                const SizedBox(width: 8),
                Text('\$ ${_fmt(montoShow)}',
                    style: AppTextStyles.caption.copyWith(fontWeight: FontWeight.bold)),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(label, style: TextStyle(
                    color: color, fontSize: 10, fontWeight: FontWeight.bold)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _fmt(double v) {
    final s = v.abs().toStringAsFixed(0);
    final buf = StringBuffer();
    for (int i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buf.write('.');
      buf.write(s[i]);
    }
    return v < 0 ? '-${buf.toString()}' : buf.toString();
  }
}
