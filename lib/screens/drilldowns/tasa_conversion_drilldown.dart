import 'package:flutter/material.dart';
import '../../config/theme.dart';
import '../../services/drilldown_service.dart';

class TasaConversionDrilldown extends StatefulWidget {
  final String vendedor;
  final int mes, anio;

  const TasaConversionDrilldown({
    super.key,
    required this.vendedor,
    required this.mes,
    required this.anio,
  });

  @override
  State<TasaConversionDrilldown> createState() => _TasaConversionState();
}

class _TasaConversionState extends State<TasaConversionDrilldown> {
  List<Map<String, dynamic>> _compraron = [];
  List<Map<String, dynamic>> _noCompraron = [];
  bool _loading = true;
  String _search = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final results = await Future.wait([
      DrilldownService.compraron(widget.vendedor, widget.mes, widget.anio),
      DrilldownService.noCompraron(widget.vendedor, widget.mes, widget.anio),
    ]);
    if (!mounted) return;
    setState(() {
      _compraron = results[0];
      _noCompraron = results[1];
      _loading = false;
    });
  }

  Color _inactividadColor(int? dias) {
    if (dias == null) return const Color(0xFFB91C1C); // nunca compró → rojo oscuro
    if (dias > 180) return AppColors.danger;
    if (dias > 90) return AppColors.warning;
    if (dias > 30) return const Color(0xFFFCD34D); // amarillo claro
    return AppColors.textMuted;
  }

  String _inactividadLabel(int? dias) {
    if (dias == null) return 'Nunca compró';
    if (dias > 365) return '${(dias / 30).floor()} meses';
    return '$dias días';
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: AppColors.bg,
        appBar: AppBar(
          backgroundColor: AppColors.bgSidebar,
          title: const Text('Tasa de Conversión', style: AppTextStyles.title),
          bottom: TabBar(
            indicatorColor: AppColors.primary,
            labelColor: AppColors.textPrimary,
            unselectedLabelColor: AppColors.textMuted,
            tabs: [
              Tab(text: 'Compraron (${_compraron.length})'),
              Tab(text: 'No compraron (${_noCompraron.length})'),
            ],
          ),
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
            : Column(
                children: [
                  // Barra de búsqueda
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: TextField(
                      style: AppTextStyles.body,
                      decoration: InputDecoration(
                        hintText: 'Buscar cliente...',
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
                      onChanged: (v) => setState(() => _search = v.toLowerCase()),
                    ),
                  ),
                  Expanded(
                    child: TabBarView(children: [
                      _buildCompraronList(),
                      _buildNoCompraronList(),
                    ]),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _buildCompraronList() {
    final filtered = _compraron.where((c) {
      if (_search.isEmpty) return true;
      return (c['ClienteNombre']?.toString() ?? '').toLowerCase().contains(_search);
    }).toList();

    if (filtered.isEmpty) {
      return const Center(child: Text('Sin resultados', style: AppTextStyles.caption));
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      itemCount: filtered.length,
      itemBuilder: (_, i) {
        final c = filtered[i];
        final importe = double.tryParse(c['Importe']?.toString() ?? '0') ?? 0;
        final canal = c['Canal']?.toString() ?? '';
        return Container(
          margin: const EdgeInsets.only(bottom: 6),
          padding: const EdgeInsets.all(12),
          decoration: AppCardStyle.base(borderColor: AppColors.success),
          child: Row(
            children: [
              const Icon(Icons.check_circle, color: AppColors.success, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(c['ClienteNombre']?.toString() ?? '', style: AppTextStyles.body),
                    if (canal.isNotEmpty)
                      Text(canal, style: AppTextStyles.muted),
                  ],
                ),
              ),
              Text('\$ ${_fmt(importe)}', style: AppTextStyles.caption.copyWith(fontWeight: FontWeight.bold)),
            ],
          ),
        );
      },
    );
  }

  Widget _buildNoCompraronList() {
    final filtered = _noCompraron.where((c) {
      if (_search.isEmpty) return true;
      return (c['ClienteNombre']?.toString() ?? '').toLowerCase().contains(_search);
    }).toList();

    if (filtered.isEmpty) {
      return const Center(child: Text('Sin resultados', style: AppTextStyles.caption));
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      itemCount: filtered.length,
      itemBuilder: (_, i) {
        final c = filtered[i];
        final dias = int.tryParse(c['DiasInactivo']?.toString() ?? '');
        final color = _inactividadColor(dias);
        final canal = c['Canal']?.toString() ?? '';
        return Container(
          margin: const EdgeInsets.only(bottom: 6),
          padding: const EdgeInsets.all(12),
          decoration: AppCardStyle.base(borderColor: color),
          child: Row(
            children: [
              Container(
                width: 8, height: 8,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(c['ClienteNombre']?.toString() ?? '', style: AppTextStyles.body),
                    if (canal.isNotEmpty) Text(canal, style: AppTextStyles.muted),
                  ],
                ),
              ),
              Text(
                _inactividadLabel(dias),
                style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.bold),
              ),
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
