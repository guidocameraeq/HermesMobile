import 'package:flutter/material.dart';
import '../../config/theme.dart';
import '../../services/drilldown_service.dart';

class AperturasDrilldown extends StatefulWidget {
  final String vendedor;
  final int mes, anio;

  const AperturasDrilldown({
    super.key, required this.vendedor, required this.mes, required this.anio,
  });

  @override
  State<AperturasDrilldown> createState() => _AperturasDrilldownState();
}

class _AperturasDrilldownState extends State<AperturasDrilldown> {
  List<Map<String, dynamic>> _rows = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final data = await DrilldownService.aperturasDetalle(
        widget.vendedor, widget.mes, widget.anio);
    if (!mounted) return;
    setState(() { _rows = data; _loading = false; });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.bgSidebar,
        title: Text('Aperturas — ${_rows.length} nuevos', style: AppTextStyles.title),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
          : _rows.isEmpty
              ? const Center(child: Text('Sin cuentas nuevas este mes', style: AppTextStyles.caption))
              : ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: _rows.length,
                  itemBuilder: (_, i) {
                    final r = _rows[i];
                    final importe = double.tryParse(r['Importe']?.toString() ?? '0') ?? 0;
                    return Container(
                      margin: const EdgeInsets.only(bottom: 6),
                      padding: const EdgeInsets.all(12),
                      decoration: AppCardStyle.base(borderColor: AppColors.success),
                      child: Row(
                        children: [
                          const Icon(Icons.person_add, color: AppColors.success, size: 20),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(r['ClienteNombre']?.toString() ?? r['ClienteCodigo']?.toString() ?? '',
                                    style: AppTextStyles.body),
                                Text('Primera compra: ${r['PrimeraCompra']?.toString().split(' ').first ?? ''}',
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
