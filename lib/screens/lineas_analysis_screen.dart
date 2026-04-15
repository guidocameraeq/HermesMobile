import 'package:flutter/material.dart';
import '../config/theme.dart';
import '../services/lineas_service.dart';

class LineasAnalysisScreen extends StatefulWidget {
  final String clienteCodigo;
  final String clienteNombre;

  const LineasAnalysisScreen({
    super.key,
    required this.clienteCodigo,
    required this.clienteNombre,
  });

  @override
  State<LineasAnalysisScreen> createState() => _LineasAnalysisState();
}

class _LineasAnalysisState extends State<LineasAnalysisScreen> {
  List<LineaCliente> _compra = [];
  List<String> _oportunidades = [];
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
      LineasService.lineasCliente(widget.clienteCodigo),
      LineasService.oportunidades(widget.clienteCodigo),
    ]);
    if (!mounted) return;
    setState(() {
      _compra = results[0] as List<LineaCliente>;
      _oportunidades = results[1] as List<String>;
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
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(widget.clienteNombre, style: AppTextStyles.title,
                  maxLines: 1, overflow: TextOverflow.ellipsis),
              if (!_loading)
                Text(
                  '${_compra.length} de ${_compra.length + _oportunidades.length} líneas',
                  style: AppTextStyles.muted,
                ),
            ],
          ),
          bottom: TabBar(
            indicatorColor: AppColors.primary,
            labelColor: AppColors.textPrimary,
            unselectedLabelColor: AppColors.textMuted,
            tabs: [
              Tab(text: 'Compra (${_compra.length})'),
              Tab(text: 'Oportunidad (${_oportunidades.length})'),
            ],
          ),
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
            : Column(
                children: [
                  // Búsqueda
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: TextField(
                      style: AppTextStyles.body,
                      decoration: InputDecoration(
                        hintText: 'Buscar línea...',
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
                      _buildCompraList(),
                      _buildOportunidadList(),
                    ]),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _buildCompraList() {
    final filtered = _compra.where((l) {
      if (_search.isEmpty) return true;
      return l.nombre.toLowerCase().contains(_search);
    }).toList();

    if (filtered.isEmpty) {
      return const Center(child: Text('Sin resultados', style: AppTextStyles.caption));
    }

    final maxMonto = _compra.fold<double>(0, (m, l) => l.monto > m ? l.monto : m);

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      itemCount: filtered.length,
      itemBuilder: (_, i) {
        final l = filtered[i];
        final pct = maxMonto > 0 ? (l.monto / maxMonto) : 0.0;

        return Container(
          margin: const EdgeInsets.only(bottom: 6),
          padding: const EdgeInsets.all(12),
          decoration: AppCardStyle.base(borderColor: AppColors.success),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.check_circle, color: AppColors.success, size: 16),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(l.nombre, style: AppTextStyles.body,
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                  ),
                  Text('\$ ${_fmt(l.monto)}',
                      style: AppTextStyles.caption.copyWith(fontWeight: FontWeight.bold)),
                ],
              ),
              const SizedBox(height: 6),
              // Barra visual
              ClipRRect(
                borderRadius: BorderRadius.circular(3),
                child: LinearProgressIndicator(
                  value: pct.clamp(0, 1).toDouble(),
                  minHeight: 6,
                  backgroundColor: AppColors.border,
                  valueColor: const AlwaysStoppedAnimation<Color>(AppColors.success),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '${l.articulos} artículos  ·  ${l.unidades.toStringAsFixed(0)} unidades',
                style: AppTextStyles.muted,
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildOportunidadList() {
    final filtered = _oportunidades.where((l) {
      if (_search.isEmpty) return true;
      return l.toLowerCase().contains(_search);
    }).toList();

    if (filtered.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.celebration, color: AppColors.success, size: 48),
            SizedBox(height: 12),
            Text('Este cliente compra todas las líneas', style: AppTextStyles.caption),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      itemCount: filtered.length,
      itemBuilder: (_, i) {
        return Container(
          margin: const EdgeInsets.only(bottom: 6),
          padding: const EdgeInsets.all(12),
          decoration: AppCardStyle.base(borderColor: AppColors.warning),
          child: Row(
            children: [
              Icon(Icons.lightbulb_outline,
                  color: AppColors.warning.withOpacity(0.8), size: 18),
              const SizedBox(width: 10),
              Expanded(
                child: Text(filtered[i], style: AppTextStyles.body),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AppColors.warning.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Text('Oportunidad',
                    style: TextStyle(color: AppColors.warning, fontSize: 10,
                        fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        );
      },
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
