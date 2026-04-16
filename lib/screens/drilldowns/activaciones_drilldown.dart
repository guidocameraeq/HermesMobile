import 'package:flutter/material.dart';
import '../../config/theme.dart';
import '../../services/pg_service.dart';

class ActivacionesDrilldown extends StatefulWidget {
  final String vendedor;
  final int mes, anio;

  const ActivacionesDrilldown({
    super.key, required this.vendedor, required this.mes, required this.anio,
  });

  @override
  State<ActivacionesDrilldown> createState() => _ActivacionesState();
}

class _ActivacionesState extends State<ActivacionesDrilldown> {
  List<Map<String, dynamic>> _rows = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final data = await PgService.query(
      'SELECT cliente_codigo, cliente_nombre FROM activaciones '
      'WHERE vendedor_nombre = @vendedor AND mes = @mes AND anio = @anio '
      'ORDER BY cliente_nombre',
      {'vendedor': widget.vendedor, 'mes': widget.mes, 'anio': widget.anio},
    );
    if (!mounted) return;
    setState(() { _rows = data; _loading = false; });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.bgSidebar,
        title: Text('Activaciones — ${_rows.length}', style: AppTextStyles.title),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
          : _rows.isEmpty
              ? const Center(child: Text('Sin activaciones este mes', style: AppTextStyles.caption))
              : ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: _rows.length,
                  itemBuilder: (_, i) {
                    final r = _rows[i];
                    return Container(
                      margin: const EdgeInsets.only(bottom: 6),
                      padding: const EdgeInsets.all(12),
                      decoration: AppCardStyle.base(borderColor: AppColors.success),
                      child: Row(
                        children: [
                          const Icon(Icons.flash_on, color: AppColors.success, size: 20),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(r['cliente_nombre']?.toString() ?? '',
                                    style: AppTextStyles.body),
                                Text('Código: ${r['cliente_codigo']}',
                                    style: AppTextStyles.muted),
                              ],
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
    );
  }
}
