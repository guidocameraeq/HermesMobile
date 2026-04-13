import 'package:flutter/material.dart';
import '../config/theme.dart';

class MonthSelector extends StatelessWidget {
  final int mes;
  final int anio;
  final void Function(int mes, int anio) onChanged;

  const MonthSelector({
    super.key,
    required this.mes,
    required this.anio,
    required this.onChanged,
  });

  static const _mesesCortos = [
    '', 'Ene', 'Feb', 'Mar', 'Abr', 'May', 'Jun',
    'Jul', 'Ago', 'Sep', 'Oct', 'Nov', 'Dic',
  ];

  static const _mesesLargos = [
    '', 'Enero', 'Febrero', 'Marzo', 'Abril', 'Mayo', 'Junio',
    'Julio', 'Agosto', 'Septiembre', 'Octubre', 'Noviembre', 'Diciembre',
  ];

  static String mesNombre(int m) => _mesesLargos[m.clamp(1, 12)];

  /// Genera los últimos 12 meses desde el actual hacia atrás.
  List<(int mes, int anio)> _buildMonths() {
    final now = DateTime.now();
    final result = <(int, int)>[];
    for (int i = 0; i < 12; i++) {
      var m = now.month - i;
      var a = now.year;
      while (m <= 0) {
        m += 12;
        a--;
      }
      result.add((m, a));
    }
    return result.reversed.toList(); // orden cronológico
  }

  @override
  Widget build(BuildContext context) {
    final months = _buildMonths();

    // Encontrar el índice del mes seleccionado
    final selectedIdx = months.indexWhere((e) => e.$1 == mes && e.$2 == anio);

    return Container(
      color: AppColors.bgSidebar,
      height: 44,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: months.length,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        controller: ScrollController(
          initialScrollOffset:
              selectedIdx >= 0 ? (selectedIdx * 72.0 - 100).clamp(0, double.infinity) : 0,
        ),
        itemBuilder: (ctx, i) {
          final (m, a) = months[i];
          final selected = m == mes && a == anio;

          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
            child: ChoiceChip(
              label: Text(
                a == DateTime.now().year
                    ? _mesesCortos[m]
                    : '${_mesesCortos[m]} $a',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: selected ? FontWeight.bold : FontWeight.normal,
                  color: selected ? Colors.white : AppColors.textMuted,
                ),
              ),
              selected: selected,
              onSelected: (_) => onChanged(m, a),
              selectedColor: AppColors.primary,
              backgroundColor: AppColors.bgCard,
              side: BorderSide.none,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 8),
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              visualDensity: VisualDensity.compact,
            ),
          );
        },
      ),
    );
  }
}
