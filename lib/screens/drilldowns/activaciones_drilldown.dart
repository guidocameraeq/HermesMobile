import 'package:flutter/material.dart';
import '../../config/theme.dart';
import '../../services/pg_service.dart';
import '../../services/cliente_router.dart';

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
                    final codigo = r['cliente_codigo']?.toString();
                    final nombre = r['cliente_nombre']?.toString() ?? '';
                    return InkWell(
                      onTap: codigo != null
                          ? () => ClienteRouter.open(context, codigo, nombre: nombre)
                          : null,
                      child: Container(
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
                                  Text(nombre, style: AppTextStyles.body),
                                  Text('Código: $codigo', style: AppTextStyles.muted),
                                ],
                              ),
                            ),
                            if (codigo != null)
                              const Icon(Icons.chevron_right,
                                  color: AppColors.textMuted, size: 16),
                          ],
                        ),
                      ),
                    );
                  },
                ),
    );
  }
}
