import 'dart:convert';
import 'package:flutter/material.dart';
import '../../config/theme.dart';
import '../../services/drilldown_service.dart';

class ReactivacionDrilldown extends StatefulWidget {
  final String vendedor;
  final int mes, anio;
  final String paramsJson;

  const ReactivacionDrilldown({
    super.key,
    required this.vendedor, required this.mes, required this.anio,
    required this.paramsJson,
  });

  @override
  State<ReactivacionDrilldown> createState() => _ReactivacionDrilldownState();
}

class _ReactivacionDrilldownState extends State<ReactivacionDrilldown> {
  List<Map<String, dynamic>> _rows = [];
  bool _loading = true;
  int _diasInactivo = 180;

  @override
  void initState() {
    super.initState();
    try {
      final p = json.decode(widget.paramsJson) as Map<String, dynamic>;
      _diasInactivo = int.tryParse(p['dias_inactivo']?.toString() ?? '180') ?? 180;
    } catch (_) {}
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final data = await DrilldownService.reactivacionDetalle(
        widget.vendedor, widget.mes, widget.anio, _diasInactivo);
    if (!mounted) return;
    setState(() { _rows = data; _loading = false; });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.bgSidebar,
        title: Text('Reactivados — ${_rows.length}', style: AppTextStyles.title),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(28),
          child: Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text('Inactivos > $_diasInactivo días que compraron',
                style: AppTextStyles.muted),
          ),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
          : _rows.isEmpty
              ? const Center(child: Text('Sin reactivaciones', style: AppTextStyles.caption))
              : ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: _rows.length,
                  itemBuilder: (_, i) {
                    final r = _rows[i];
                    final dias = int.tryParse(r['DiasInactivo']?.toString() ?? '0') ?? 0;
                    final importe = double.tryParse(r['Importe']?.toString() ?? '0') ?? 0;
                    return Container(
                      margin: const EdgeInsets.only(bottom: 6),
                      padding: const EdgeInsets.all(12),
                      decoration: AppCardStyle.base(borderColor: AppColors.warning),
                      child: Row(
                        children: [
                          const Icon(Icons.replay, color: AppColors.warning, size: 20),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(r['ClienteNombre']?.toString() ?? '',
                                    style: AppTextStyles.body),
                                Text('Estuvo inactivo $dias días',
                                    style: AppTextStyles.muted),
                              ],
                            ),
                          ),
                          Text('\$ ${_fmt(importe)}',
                              style: AppTextStyles.caption.copyWith(fontWeight: FontWeight.bold)),
                        ],
                      ),
                    );
                  },
                ),
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
