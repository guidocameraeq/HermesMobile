import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import '../config/theme.dart';

/// Gráfico de evolución de ventas: barras (año actual) + línea (año anterior).
class SalesChart extends StatelessWidget {
  final List<Map<String, dynamic>> actual;   // [{Anio, Mes, Monto}]
  final List<Map<String, dynamic>> anterior; // [{Anio, Mes, Monto}]

  const SalesChart({
    super.key,
    required this.actual,
    required this.anterior,
  });

  static const _meses = [
    '', 'Ene', 'Feb', 'Mar', 'Abr', 'May', 'Jun',
    'Jul', 'Ago', 'Sep', 'Oct', 'Nov', 'Dic',
  ];

  @override
  Widget build(BuildContext context) {
    if (actual.isEmpty) {
      return const SizedBox(
        height: 200,
        child: Center(child: Text('Sin datos', style: AppTextStyles.muted)),
      );
    }

    // Construir barras del año actual
    final barGroups = <BarChartGroupData>[];
    double maxVal = 0;

    for (int i = 0; i < actual.length; i++) {
      final monto = double.tryParse(actual[i]['Monto']?.toString() ?? '0') ?? 0;
      if (monto > maxVal) maxVal = monto;
      barGroups.add(BarChartGroupData(
        x: i,
        barRods: [
          BarChartRodData(
            toY: monto / 1e6, // en millones
            color: AppColors.primary,
            width: 20,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
          ),
        ],
      ));
    }

    // Construir línea del año anterior
    final lineSpots = <FlSpot>[];
    // Index anterior por mes para alinear con actual
    final anteriorMap = <int, double>{};
    for (final a in anterior) {
      final mes = int.tryParse(a['Mes']?.toString() ?? '0') ?? 0;
      final monto = double.tryParse(a['Monto']?.toString() ?? '0') ?? 0;
      anteriorMap[mes] = monto;
      if (monto > maxVal) maxVal = monto;
    }
    for (int i = 0; i < actual.length; i++) {
      final mes = int.tryParse(actual[i]['Mes']?.toString() ?? '0') ?? 0;
      final montoAnt = anteriorMap[mes] ?? 0;
      lineSpots.add(FlSpot(i.toDouble(), montoAnt / 1e6));
    }

    final maxY = (maxVal / 1e6) * 1.15; // 15% de margen arriba

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: AppCardStyle.base(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(child: Text('Evolución de Ventas', style: AppTextStyles.title)),
              // Leyenda
              _legendDot(AppColors.primary, 'Actual'),
              const SizedBox(width: 10),
              _legendDot(AppColors.textMuted, 'Año ant.'),
            ],
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 200,
            child: BarChart(
              BarChartData(
                maxY: maxY > 0 ? maxY : 1,
                alignment: BarChartAlignment.spaceAround,
                barGroups: barGroups,
                borderData: FlBorderData(show: false),
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  horizontalInterval: maxY > 0 ? maxY / 4 : 1,
                  getDrawingHorizontalLine: (_) => FlLine(
                    color: AppColors.border,
                    strokeWidth: 0.5,
                  ),
                ),
                titlesData: FlTitlesData(
                  topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 40,
                      getTitlesWidget: (value, meta) {
                        return Text(
                          '${value.toStringAsFixed(0)}M',
                          style: const TextStyle(
                            color: AppColors.textMuted, fontSize: 10),
                        );
                      },
                    ),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      getTitlesWidget: (value, meta) {
                        final idx = value.toInt();
                        if (idx < 0 || idx >= actual.length) return const SizedBox();
                        final mes = int.tryParse(
                            actual[idx]['Mes']?.toString() ?? '0') ?? 0;
                        return Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text(
                            _meses[mes.clamp(1, 12)],
                            style: const TextStyle(
                              color: AppColors.textMuted, fontSize: 10),
                          ),
                        );
                      },
                    ),
                  ),
                ),
                barTouchData: BarTouchData(
                  touchTooltipData: BarTouchTooltipData(
                    getTooltipColor: (_) => AppColors.bgCardHover,
                    getTooltipItem: (group, groupIdx, rod, rodIdx) {
                      final mes = int.tryParse(
                          actual[group.x]['Mes']?.toString() ?? '0') ?? 0;
                      return BarTooltipItem(
                        '${_meses[mes.clamp(1, 12)]}\n\$ ${_fmtM(rod.toY)}M',
                        const TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      );
                    },
                  ),
                ),
                extraLinesData: ExtraLinesData(
                  extraLinesOnTop: false,
                ),
              ),
            ),
          ),
          // Línea del año anterior como overlay simple (spots debajo del gráfico)
          if (lineSpots.isNotEmpty && anterior.isNotEmpty) ...[
            const SizedBox(height: 8),
            SizedBox(
              height: 40,
              child: LineChart(
                LineChartData(
                  minY: 0,
                  maxY: maxY > 0 ? maxY : 1,
                  lineBarsData: [
                    LineChartBarData(
                      spots: lineSpots,
                      isCurved: true,
                      color: AppColors.textMuted,
                      barWidth: 2,
                      dotData: FlDotData(
                        show: true,
                        getDotPainter: (_, __, ___, ____) => FlDotCirclePainter(
                          radius: 3,
                          color: AppColors.textMuted,
                          strokeColor: AppColors.bgCard,
                          strokeWidth: 1,
                        ),
                      ),
                      belowBarData: BarAreaData(show: false),
                    ),
                  ],
                  borderData: FlBorderData(show: false),
                  gridData: const FlGridData(show: false),
                  titlesData: const FlTitlesData(show: false),
                  lineTouchData: const LineTouchData(enabled: false),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _legendDot(Color color, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(width: 8, height: 8,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 4),
        Text(label, style: const TextStyle(color: AppColors.textMuted, fontSize: 10)),
      ],
    );
  }

  String _fmtM(double v) {
    if (v >= 1000) return '${(v / 1000).toStringAsFixed(1)}B';
    return v.toStringAsFixed(1);
  }
}
