import 'package:flutter/material.dart';
import '../config/theme.dart';
import '../models/cliente.dart';
import '../services/clientes_service.dart';

class ClienteDetailScreen extends StatefulWidget {
  final Cliente cliente;
  const ClienteDetailScreen({super.key, required this.cliente});

  @override
  State<ClienteDetailScreen> createState() => _ClienteDetailState();
}

class _ClienteDetailState extends State<ClienteDetailScreen> {
  List<Map<String, dynamic>> _evolucion = [];
  List<Map<String, dynamic>> _facturas = [];
  List<Map<String, dynamic>> _saldoDocs = [];
  bool _loading = true;

  static const _meses = [
    '', 'Ene', 'Feb', 'Mar', 'Abr', 'May', 'Jun',
    'Jul', 'Ago', 'Sep', 'Oct', 'Nov', 'Dic',
  ];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final results = await Future.wait([
      ClientesService.evolucionMensual(widget.cliente.codigo),
      ClientesService.ultimasFacturas(widget.cliente.codigo),
      ClientesService.saldoDetalle(widget.cliente.codigo),
    ]);
    if (!mounted) return;
    setState(() {
      _evolucion = results[0];
      _facturas = results[1];
      _saldoDocs = results[2];
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.cliente;

    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.bgSidebar,
        title: Text(c.nombre, style: AppTextStyles.title,
            maxLines: 1, overflow: TextOverflow.ellipsis),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
          : RefreshIndicator(
              onRefresh: _load,
              color: AppColors.primary,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  _buildHeader(c),
                  const SizedBox(height: 16),
                  if (widget.cliente.saldo > 0) ...[
                    _buildSaldoCard(),
                    const SizedBox(height: 16),
                  ],
                  _buildEvolucion(),
                  const SizedBox(height: 16),
                  _buildFacturas(),
                  if (_saldoDocs.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    _buildSaldoDetalle(),
                  ],
                  const SizedBox(height: 32),
                ],
              ),
            ),
    );
  }

  Widget _buildHeader(Cliente c) {
    Color sitColor = c.esBaja ? AppColors.danger
        : c.esActivo ? AppColors.success : AppColors.textMuted;
    String sitLabel = c.esBaja ? 'Baja' : c.esActivo ? 'Activo' : 'Inactivo';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: AppCardStyle.base(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 22,
                backgroundColor: sitColor.withOpacity(0.2),
                child: Text(c.nombre.isNotEmpty ? c.nombre[0] : '?',
                    style: TextStyle(color: sitColor, fontSize: 18, fontWeight: FontWeight.bold)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(c.nombre, style: AppTextStyles.title),
                    Text('Código: ${c.codigo}', style: AppTextStyles.muted),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: sitColor.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(sitLabel, style: TextStyle(
                  color: sitColor, fontSize: 11, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _detailRow(Icons.category, c.categoria),
          if (c.localidad.isNotEmpty || c.provincia.isNotEmpty)
            _detailRow(Icons.location_on, [c.localidad, c.provincia].where((s) => s.isNotEmpty).join(', ')),
          if (c.ultimaCompra != null)
            _detailRow(Icons.calendar_today,
                'Última compra: ${_fmtDate(c.ultimaCompra!)} (${c.diasSinComprar} días)'),
        ],
      ),
    );
  }

  Widget _detailRow(IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        children: [
          Icon(icon, size: 14, color: AppColors.textMuted),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: AppTextStyles.caption)),
        ],
      ),
    );
  }

  Widget _buildSaldoCard() {
    final c = widget.cliente;
    final atrasado = c.maxAtraso > 0;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.bgCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: atrasado ? AppColors.warning.withOpacity(0.4) : AppColors.border,
        ),
      ),
      child: Row(
        children: [
          Icon(Icons.account_balance_wallet,
              color: atrasado ? AppColors.warning : AppColors.textMuted, size: 24),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Saldo Cuenta Corriente', style: AppTextStyles.caption),
                const SizedBox(height: 2),
                Text(c.saldoFmt, style: AppTextStyles.title.copyWith(
                  color: atrasado ? AppColors.warning : AppColors.textPrimary,
                )),
              ],
            ),
          ),
          if (atrasado)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: AppColors.warning.withOpacity(0.15),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text('${c.maxAtraso}d atraso', style: const TextStyle(
                color: AppColors.warning, fontSize: 11, fontWeight: FontWeight.bold)),
            ),
        ],
      ),
    );
  }

  Widget _buildEvolucion() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: AppCardStyle.base(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Evolución últimos 6 meses', style: AppTextStyles.title),
          const SizedBox(height: 12),
          if (_evolucion.isEmpty)
            const Text('Sin datos', style: AppTextStyles.muted)
          else ...[
            // Total
            Builder(builder: (_) {
              double total = 0;
              int totalFact = 0;
              for (final e in _evolucion) {
                total += double.tryParse(e['Monto']?.toString() ?? '0') ?? 0;
                totalFact += int.tryParse(e['Facturas']?.toString() ?? '0') ?? 0;
              }
              return Text(
                'Total: \$ ${_fmt(total)} en $totalFact facturas',
                style: AppTextStyles.caption,
              );
            }),
            const SizedBox(height: 12),
            // Barras
            ..._evolucion.reversed.map((e) {
              final monto = double.tryParse(e['Monto']?.toString() ?? '0') ?? 0;
              final mes = int.tryParse(e['Mes']?.toString() ?? '0') ?? 0;
              final anio = int.tryParse(e['Anio']?.toString() ?? '0') ?? 0;
              final maxMonto = _evolucion.fold<double>(
                  0, (m, r) => (double.tryParse(r['Monto']?.toString() ?? '0') ?? 0) > m
                      ? (double.tryParse(r['Monto']?.toString() ?? '0') ?? 0) : m);
              final pct = maxMonto > 0 ? (monto / maxMonto) : 0.0;

              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    SizedBox(
                      width: 55,
                      child: Text('${_meses[mes.clamp(1, 12)]} $anio',
                          style: AppTextStyles.muted),
                    ),
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(3),
                        child: LinearProgressIndicator(
                          value: pct.clamp(0, 1).toDouble(),
                          minHeight: 14,
                          backgroundColor: AppColors.border,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            monto >= 0 ? AppColors.primary : AppColors.danger,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    SizedBox(
                      width: 80,
                      child: Text('\$ ${_fmt(monto)}',
                          style: AppTextStyles.caption.copyWith(fontWeight: FontWeight.bold),
                          textAlign: TextAlign.right),
                    ),
                  ],
                ),
              );
            }),
          ],
        ],
      ),
    );
  }

  Widget _buildFacturas() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: AppCardStyle.base(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Últimas facturas (${_facturas.length})', style: AppTextStyles.title),
          const SizedBox(height: 8),
          if (_facturas.isEmpty)
            const Text('Sin facturas', style: AppTextStyles.muted)
          else
            ..._facturas.take(15).map((f) {
              final monto = double.tryParse(f['Monto']?.toString() ?? '0') ?? 0;
              final tipo = int.tryParse(f['Tipo']?.toString() ?? '2205') ?? 2205;
              final esNC = tipo == 2206;
              final fechaStr = f['Fecha']?.toString().split(' ').first ?? '';

              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    Icon(
                      esNC ? Icons.remove_circle_outline : Icons.receipt_outlined,
                      size: 14,
                      color: esNC ? AppColors.danger : AppColors.textMuted,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text('Nro ${f['Numero']}', style: AppTextStyles.caption),
                    ),
                    Text(fechaStr, style: AppTextStyles.muted),
                    const SizedBox(width: 12),
                    Text(
                      '${esNC ? "- " : ""}\$ ${_fmt(monto.abs())}',
                      style: TextStyle(
                        color: esNC ? AppColors.danger : AppColors.textPrimary,
                        fontSize: 12, fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              );
            }),
        ],
      ),
    );
  }

  Widget _buildSaldoDetalle() {
    double totalSaldo = 0;
    for (final d in _saldoDocs) {
      totalSaldo += double.tryParse(d['ImpPendiente']?.toString() ?? '0') ?? 0;
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: AppCardStyle.base(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(child: Text('Documentos pendientes', style: AppTextStyles.title)),
              Text('\$ ${_fmt(totalSaldo)}',
                  style: AppTextStyles.caption.copyWith(fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(height: 8),
          ..._saldoDocs.take(20).map((d) {
            final imp = double.tryParse(d['ImpPendiente']?.toString() ?? '0') ?? 0;
            final atraso = int.tryParse(d['Atraso']?.toString() ?? '0') ?? 0;
            final vencido = atraso > 0;
            final fechaVto = d['FechaVto']?.toString().split(' ').first ?? '';

            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  Icon(
                    vencido ? Icons.warning_amber : Icons.schedule,
                    size: 14,
                    color: vencido ? AppColors.warning : AppColors.textMuted,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(d['Numero']?.toString() ?? '', style: AppTextStyles.caption),
                        Text(
                          vencido ? 'Vencido $fechaVto ($atraso días)' : 'Vence $fechaVto',
                          style: TextStyle(
                            color: vencido ? AppColors.warning : AppColors.textMuted,
                            fontSize: 10,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Text('\$ ${_fmt(imp)}', style: TextStyle(
                    color: vencido ? AppColors.warning : AppColors.textPrimary,
                    fontSize: 12, fontWeight: FontWeight.bold,
                  )),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  String _fmtDate(DateTime dt) {
    return '${dt.day.toString().padLeft(2, '0')}/'
        '${dt.month.toString().padLeft(2, '0')}/${dt.year}';
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
