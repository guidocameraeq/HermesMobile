import 'package:flutter/material.dart';
import '../config/theme.dart';

/// Entrada unificada del timeline (visita o actividad).
class TimelineEntry {
  final String tipo;       // llamada, visita, propuesta, etc.
  final String? descripcion;
  final DateTime fecha;
  final String origen;     // 'visita_gps', 'manual', 'hermes_flash'
  final bool completada;
  final int? id;           // id de actividades_cliente (para completar)

  TimelineEntry({
    required this.tipo,
    this.descripcion,
    required this.fecha,
    required this.origen,
    this.completada = true,
    this.id,
  });

  IconData get icon => switch (tipo) {
    'llamada' => Icons.phone,
    'visita' || 'visita comercial' || 'cobranza' || 'presentación de producto' || 'reclamo'
        => Icons.location_on,
    'propuesta' => Icons.description,
    'presentacion' || 'presentación' => Icons.present_to_all,
    'reunion' || 'reunión' => Icons.groups,
    'recordatorio' => Icons.alarm,
    _ => Icons.note,
  };

  Color get color => switch (tipo) {
    'llamada' => AppColors.primary,
    'visita' || 'visita comercial' || 'cobranza' || 'presentación de producto' || 'reclamo'
        => AppColors.success,
    'propuesta' => AppColors.warning,
    'recordatorio' => AppColors.accent,
    _ => AppColors.textMuted,
  };

  String get tipoLabel {
    final t = tipo[0].toUpperCase() + tipo.substring(1);
    if (origen == 'hermes_flash') return '$t (Flash)';
    if (origen == 'visita_gps') return '$t (GPS)';
    return t;
  }

  String get fechaFmt {
    final now = DateTime.now();
    final diff = now.difference(fecha).inDays;
    final hora = '${fecha.hour.toString().padLeft(2, '0')}:${fecha.minute.toString().padLeft(2, '0')}';
    if (diff == 0) return 'Hoy $hora';
    if (diff == 1) return 'Ayer $hora';
    return '${fecha.day.toString().padLeft(2, '0')}/${fecha.month.toString().padLeft(2, '0')} $hora';
  }
}

/// Widget de historia clínica — timeline cronológico.
class HistoriaClinica extends StatelessWidget {
  final List<TimelineEntry> entries;
  final VoidCallback? onVerMas;
  final void Function(int id)? onCompletar;
  final void Function(int id)? onTap;

  const HistoriaClinica({
    super.key,
    required this.entries,
    this.onVerMas,
    this.onCompletar,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    if (entries.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: AppCardStyle.base(),
        child: const Column(
          children: [
            Icon(Icons.history, color: AppColors.textMuted, size: 32),
            SizedBox(height: 8),
            Text('Sin actividades registradas', style: AppTextStyles.caption),
            Text('Cargá una actividad o registrá una visita', style: AppTextStyles.muted),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: AppCardStyle.base(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Historia Clínica', style: AppTextStyles.title),
          const SizedBox(height: 12),
          ...entries.map((e) => _TimelineTile(
            entry: e,
            onCompletar: e.id != null && !e.completada && onCompletar != null
                ? () => onCompletar!(e.id!)
                : null,
            onTap: e.id != null && onTap != null ? () => onTap!(e.id!) : null,
          )),
          if (onVerMas != null) ...[
            const SizedBox(height: 8),
            Center(
              child: TextButton(
                onPressed: onVerMas,
                child: const Text('Ver más...', style: TextStyle(color: AppColors.accent, fontSize: 12)),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _TimelineTile extends StatelessWidget {
  final TimelineEntry entry;
  final VoidCallback? onCompletar;
  final VoidCallback? onTap;

  const _TimelineTile({required this.entry, this.onCompletar, this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Icono + línea
          Column(
            children: [
              Container(
                width: 28, height: 28,
                decoration: BoxDecoration(
                  color: entry.color.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(entry.icon, color: entry.color, size: 14),
              ),
            ],
          ),
          const SizedBox(width: 10),
          // Contenido
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(entry.tipoLabel,
                        style: TextStyle(color: entry.color, fontSize: 12, fontWeight: FontWeight.bold)),
                    const Spacer(),
                    Text(entry.fechaFmt, style: AppTextStyles.muted),
                  ],
                ),
                if (entry.descripcion != null && entry.descripcion!.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(entry.descripcion!, style: AppTextStyles.caption,
                      maxLines: 2, overflow: TextOverflow.ellipsis),
                ],
                if (!entry.completada && onCompletar != null) ...[
                  const SizedBox(height: 4),
                  GestureDetector(
                    onTap: onCompletar,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: AppColors.success.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Text('Marcar completada',
                          style: TextStyle(color: AppColors.success, fontSize: 10, fontWeight: FontWeight.bold)),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
      ),
    );
  }
}
