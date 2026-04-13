import 'package:flutter/material.dart';
import '../models/scorecard_item.dart';
import '../services/calculator_service.dart';

class MetricCard extends StatelessWidget {
  final ScorecardItem item;
  final double ritmo; // ritmo esperado del mes (0.0–1.0)

  const MetricCard({
    super.key,
    required this.item,
    required this.ritmo,
  });

  Color _semaphoreColor() {
    if (!item.cargado || item.error) return const Color(0xFF64748B);
    final pct = item.pctLogro;
    if (pct >= ritmo) return const Color(0xFF10B981);         // Verde
    if (pct >= ritmo * 0.80) return const Color(0xFFF59E0B); // Amarillo
    return const Color(0xFFEF4444);                           // Rojo
  }

  String _semaphoreIcon() {
    if (!item.cargado || item.error) return '⏳';
    final pct = item.pctLogro;
    if (pct >= ritmo) return '✅';
    if (pct >= ritmo * 0.80) return '⚠️';
    return '🔴';
  }

  @override
  Widget build(BuildContext context) {
    final color = _semaphoreColor();
    final pctLogro = item.pctLogro.clamp(0.0, 1.5);

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF1C2333),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.4), width: 1),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Header ─────────────────────────────────────────
            Row(
              children: [
                Expanded(
                  child: Text(
                    item.nombre,
                    style: const TextStyle(
                      color: Color(0xFFF8FAFC),
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                Text(
                  _semaphoreIcon(),
                  style: const TextStyle(fontSize: 18),
                ),
              ],
            ),

            const SizedBox(height: 12),

            // ── Valores Real / Meta ─────────────────────────────
            Row(
              children: [
                Expanded(
                  child: _ValueBox(
                    label: 'Real',
                    value: item.valorRealFmt,
                    color: color,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _ValueBox(
                    label: 'Meta',
                    value: item.valorMetaFmt,
                    color: const Color(0xFF64748B),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 12),

            // ── Barra de progreso ───────────────────────────────
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: pctLogro.clamp(0.0, 1.0),
                minHeight: 8,
                backgroundColor: const Color(0xFF2D3748),
                valueColor: AlwaysStoppedAnimation<Color>(color),
              ),
            ),

            const SizedBox(height: 6),

            // ── % logro y ritmo esperado ────────────────────────
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  item.cargado && !item.error
                      ? '${(item.pctLogro * 100).toStringAsFixed(1)}% logrado'
                      : '',
                  style: TextStyle(
                    color: color,
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  'Ritmo esperado: ${(ritmo * 100).toStringAsFixed(0)}%',
                  style: const TextStyle(
                    color: Color(0xFF64748B),
                    fontSize: 12,
                  ),
                ),
              ],
            ),

            // ── Fórmula / nota ──────────────────────────────────
            if (item.formula.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                item.formula,
                style: const TextStyle(
                  color: Color(0xFF94A3B8),
                  fontSize: 11,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ValueBox extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _ValueBox({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF0A0C10),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: Color(0xFF64748B),
              fontSize: 11,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: TextStyle(
              color: color,
              fontSize: 15,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}
