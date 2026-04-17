import 'package:flutter/material.dart';
import '../config/theme.dart';
import '../models/cliente.dart';
import '../models/session.dart';
import '../services/cuotas_service.dart';
import '../screens/cliente_detail_screen.dart';

/// Widget de cuotas por cliente — carga bajo demanda.
class CuotasGrid extends StatefulWidget {
  final int mes, anio;
  final bool inclPend;

  const CuotasGrid({
    super.key,
    required this.mes,
    required this.anio,
    required this.inclPend,
  });

  @override
  State<CuotasGrid> createState() => _CuotasGridState();
}

class _CuotasGridState extends State<CuotasGrid> {
  CuotasResult? _data;
  bool _loading = false;
  bool _loaded = false;
  String _error = '';

  Future<void> _load() async {
    setState(() { _loading = true; _error = ''; });
    try {
      final data = await CuotasService.loadCuotas(
        Session.current.vendedorNombre, widget.mes, widget.anio,
        inclPend: widget.inclPend,
      );
      if (!mounted) return;
      setState(() { _data = data; _loading = false; _loaded = true; });
    } catch (e) {
      if (!mounted) return;
      setState(() { _loading = false; _error = 'Error: $e'; });
    }
  }

  @override
  void didUpdateWidget(CuotasGrid old) {
    super.didUpdateWidget(old);
    if (old.mes != widget.mes || old.anio != widget.anio || old.inclPend != widget.inclPend) {
      _loaded = false;
      _data = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded && !_loading) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: SizedBox(
          width: double.infinity,
          height: 44,
          child: OutlinedButton.icon(
            onPressed: _load,
            icon: const Icon(Icons.grid_view, size: 18),
            label: const Text('Ver cuotas por cliente'),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.accent,
              side: BorderSide(color: AppColors.accent.withOpacity(0.4)),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
          ),
        ),
      );
    }

    if (_loading) {
      return const Padding(
        padding: EdgeInsets.all(32),
        child: Center(child: CircularProgressIndicator(color: AppColors.primary)),
      );
    }

    if (_error.isNotEmpty) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Text(_error, style: const TextStyle(color: AppColors.danger, fontSize: 12)),
      );
    }

    final data = _data;
    if (data == null || data.clientes.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Text('Sin cuotas asignadas para este período', style: AppTextStyles.muted),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Text('Cuotas por Cliente', style: AppTextStyles.title),
        ),
        // Resumen semáforo
        _buildResumen(data.resumen),
        const SizedBox(height: 8),
        // Lista de clientes
        ...data.clientes.map((c) => _ClienteCuotaTile(
          cuota: c,
          onTap: () => Navigator.push(context, MaterialPageRoute(
            builder: (_) => ClienteDetailScreen(
              cliente: Cliente(
                codigo: c.codigo, nombre: c.nombre,
                categoria: c.categoria, situacion: 'Activo normal',
                localidad: '', provincia: '',
              ),
            ),
          )),
        )),
      ],
    );
  }

  Widget _buildResumen(CuotasResumen r) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: [
          _SemaforoCard(label: 'Verde', count: r.verdes, monto: r.montoVerde, color: AppColors.success),
          const SizedBox(width: 6),
          _SemaforoCard(label: 'Amarillo', count: r.amarillos, monto: r.montoAmarillo, color: AppColors.warning),
          const SizedBox(width: 6),
          _SemaforoCard(label: 'Rojo', count: r.rojos, monto: r.montoRojo, color: AppColors.danger),
          const SizedBox(width: 6),
          _SemaforoCard(label: 'Sin meta', count: r.sinMeta, monto: r.montoSinMeta, color: AppColors.textMuted),
        ],
      ),
    );
  }
}

class _SemaforoCard extends StatelessWidget {
  final String label;
  final int count;
  final double monto;
  final Color color;

  const _SemaforoCard({required this.label, required this.count, required this.monto, required this.color});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
        decoration: BoxDecoration(
          color: color.withOpacity(0.08),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withOpacity(0.2)),
        ),
        child: Column(
          children: [
            Text('$count', style: TextStyle(color: color, fontSize: 18, fontWeight: FontWeight.bold)),
            Text(label, style: TextStyle(color: color, fontSize: 9)),
            const SizedBox(height: 2),
            Text('\$${_fmtK(monto)}', style: const TextStyle(color: AppColors.textMuted, fontSize: 9)),
          ],
        ),
      ),
    );
  }

  String _fmtK(double v) {
    if (v >= 1e6) return '${(v / 1e6).toStringAsFixed(1)}M';
    if (v >= 1e3) return '${(v / 1e3).toStringAsFixed(0)}K';
    return v.toStringAsFixed(0);
  }
}

class _ClienteCuotaTile extends StatelessWidget {
  final CuotaCliente cuota;
  final VoidCallback onTap;

  const _ClienteCuotaTile({required this.cuota, required this.onTap});

  Color get _color => switch (cuota.semaforo) {
    'verde' => AppColors.success,
    'amarillo' => AppColors.warning,
    'rojo' => AppColors.danger,
    _ => AppColors.textMuted,
  };

  String get _icon => switch (cuota.semaforo) {
    'verde' => '🟢',
    'amarillo' => '🟡',
    'rojo' => '🔴',
    _ => '⚪',
  };

  @override
  Widget build(BuildContext context) {
    final pct = cuota.pct;
    final c = _color;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
        padding: const EdgeInsets.all(12),
        decoration: AppCardStyle.base(borderColor: c),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(cuota.nombre, style: AppTextStyles.body,
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                ),
                if (cuota.categoria.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: Text(cuota.categoria, style: AppTextStyles.muted),
                  ),
                Text(_icon, style: const TextStyle(fontSize: 14)),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Text('Meta: \$ ${_fmt(cuota.meta)}', style: AppTextStyles.muted),
                const Spacer(),
                Text('Real: \$ ${_fmt(cuota.total)}',
                    style: TextStyle(color: c, fontSize: 12, fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(3),
                    child: LinearProgressIndicator(
                      value: (pct / 100).clamp(0, 1).toDouble(),
                      minHeight: 6,
                      backgroundColor: AppColors.border,
                      valueColor: AlwaysStoppedAnimation<Color>(c),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Text('${pct.toStringAsFixed(0)}%',
                    style: TextStyle(color: c, fontSize: 12, fontWeight: FontWeight.bold)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _fmt(double v) {
    if (v <= 0) return '-';
    final s = v.toStringAsFixed(0);
    final buf = StringBuffer();
    for (int i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buf.write('.');
      buf.write(s[i]);
    }
    return buf.toString();
  }
}
