import 'package:flutter/material.dart';
import '../config/theme.dart';
import '../services/visitas_service.dart';

class MisVisitasScreen extends StatefulWidget {
  const MisVisitasScreen({super.key});

  @override
  State<MisVisitasScreen> createState() => _MisVisitasState();
}

class _MisVisitasState extends State<MisVisitasScreen> {
  List<Map<String, dynamic>> _visitas = [];
  bool _loading = true;
  bool _showWeek = false; // false = hoy, true = semana

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final data = _showWeek
        ? await VisitasService.visitasSemana()
        : await VisitasService.visitasHoy();
    if (!mounted) return;
    setState(() {
      _visitas = data;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.bgSidebar,
        title: Text(
          _showWeek ? 'Visitas de la semana' : 'Visitas de hoy',
          style: AppTextStyles.title,
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: AppColors.textMuted),
            onPressed: _loading ? null : _load,
          ),
        ],
      ),
      body: Column(
        children: [
          // Toggle hoy / semana
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                _toggleChip('Hoy', !_showWeek),
                const SizedBox(width: 8),
                _toggleChip('Esta semana', _showWeek),
                const Spacer(),
                Text(
                  '${_visitas.length} visitas',
                  style: AppTextStyles.muted,
                ),
              ],
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
                : _visitas.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.location_off, color: AppColors.textMuted, size: 48),
                            const SizedBox(height: 12),
                            Text(
                              _showWeek ? 'Sin visitas esta semana' : 'Sin visitas hoy',
                              style: AppTextStyles.caption,
                            ),
                          ],
                        ),
                      )
                    : RefreshIndicator(
                        onRefresh: _load,
                        color: AppColors.primary,
                        child: ListView.builder(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          itemCount: _visitas.length,
                          itemBuilder: (_, i) => _VisitaTile(visita: _visitas[i]),
                        ),
                      ),
          ),
        ],
      ),
    );
  }

  Widget _toggleChip(String label, bool selected) {
    return ChoiceChip(
      label: Text(label, style: TextStyle(
        fontSize: 12,
        color: selected ? Colors.white : AppColors.textMuted,
        fontWeight: selected ? FontWeight.bold : FontWeight.normal,
      )),
      selected: selected,
      onSelected: (_) {
        setState(() => _showWeek = label == 'Esta semana');
        _load();
      },
      selectedColor: AppColors.primary,
      backgroundColor: AppColors.bgCard,
      side: BorderSide.none,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      visualDensity: VisualDensity.compact,
      padding: const EdgeInsets.symmetric(horizontal: 8),
    );
  }
}

class _VisitaTile extends StatelessWidget {
  final Map<String, dynamic> visita;
  const _VisitaTile({required this.visita});

  Color _motivoColor(String motivo) {
    switch (motivo) {
      case 'Visita comercial': return AppColors.primary;
      case 'Cobranza': return AppColors.warning;
      case 'Presentación de producto': return AppColors.success;
      case 'Reclamo': return AppColors.danger;
      default: return AppColors.textMuted;
    }
  }

  @override
  Widget build(BuildContext context) {
    final motivo = visita['motivo']?.toString() ?? '';
    final cliente = visita['cliente_nombre']?.toString() ?? '';
    final notas = visita['notas']?.toString() ?? '';
    final createdAt = visita['created_at'];
    String hora = '';
    String fecha = '';
    if (createdAt != null) {
      final dt = createdAt is DateTime ? createdAt : DateTime.tryParse(createdAt.toString());
      if (dt != null) {
        hora = '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
        fecha = '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}';
      }
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: AppCardStyle.base(),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.location_on, color: _motivoColor(motivo), size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(cliente, style: AppTextStyles.body,
                    maxLines: 1, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: _motivoColor(motivo).withOpacity(0.12),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(motivo, style: TextStyle(
                    color: _motivoColor(motivo), fontSize: 10, fontWeight: FontWeight.bold)),
                ),
                if (notas.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(notas, style: AppTextStyles.muted,
                      maxLines: 2, overflow: TextOverflow.ellipsis),
                ],
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(hora, style: AppTextStyles.caption.copyWith(fontWeight: FontWeight.bold)),
              Text(fecha, style: AppTextStyles.muted),
            ],
          ),
        ],
      ),
    );
  }
}
