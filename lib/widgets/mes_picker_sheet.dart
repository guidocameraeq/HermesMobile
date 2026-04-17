import 'package:flutter/material.dart';
import '../config/theme.dart';

/// Bottom sheet para elegir mes/año — reemplaza el MonthSelector arriba de cada tab.
/// El default siempre es el mes actual; este picker permite ver meses cerrados.
class MesPickerSheet extends StatefulWidget {
  final int mesActual;
  final int anioActual;
  final void Function(int mes, int anio) onPicked;

  const MesPickerSheet({
    super.key,
    required this.mesActual,
    required this.anioActual,
    required this.onPicked,
  });

  @override
  State<MesPickerSheet> createState() => _MesPickerSheetState();
}

class _MesPickerSheetState extends State<MesPickerSheet> {
  late int _anio;
  static const _meses = [
    'Ene','Feb','Mar','Abr','May','Jun','Jul','Ago','Sep','Oct','Nov','Dic'
  ];

  @override
  void initState() {
    super.initState();
    _anio = widget.anioActual;
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final anios = [now.year - 2, now.year - 1, now.year];

    return SafeArea(
      child: Container(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text('Elegir mes', style: AppTextStyles.title),
                ),
                TextButton(
                  onPressed: () {
                    widget.onPicked(now.month, now.year);
                  },
                  child: const Text('Mes actual',
                      style: TextStyle(color: AppColors.accent, fontSize: 12)),
                ),
              ],
            ),
            const SizedBox(height: 8),
            // Selector de año
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: anios.map((a) {
                final sel = a == _anio;
                return GestureDetector(
                  onTap: () => setState(() => _anio = a),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                    decoration: BoxDecoration(
                      color: sel ? AppColors.primary : AppColors.bg,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text('$a', style: TextStyle(
                      color: sel ? Colors.white : AppColors.textMuted,
                      fontWeight: sel ? FontWeight.bold : FontWeight.normal,
                      fontSize: 13,
                    )),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 16),
            // Grid de meses
            GridView.count(
              crossAxisCount: 4,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              childAspectRatio: 1.8,
              crossAxisSpacing: 8,
              mainAxisSpacing: 8,
              children: List.generate(12, (i) {
                final mes = i + 1;
                final isFuture = _anio > now.year ||
                    (_anio == now.year && mes > now.month);
                final isSelected = mes == widget.mesActual && _anio == widget.anioActual;
                final isCurrent = mes == now.month && _anio == now.year;

                return GestureDetector(
                  onTap: isFuture ? null : () => widget.onPicked(mes, _anio),
                  child: Container(
                    decoration: BoxDecoration(
                      color: isSelected
                          ? AppColors.primary
                          : isCurrent
                              ? AppColors.success.withOpacity(0.15)
                              : AppColors.bg,
                      borderRadius: BorderRadius.circular(8),
                      border: isCurrent && !isSelected
                          ? Border.all(color: AppColors.success, width: 1)
                          : null,
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      _meses[i],
                      style: TextStyle(
                        color: isFuture
                            ? AppColors.textMuted.withOpacity(0.3)
                            : isSelected
                                ? Colors.white
                                : isCurrent
                                    ? AppColors.success
                                    : AppColors.textPrimary,
                        fontWeight: isSelected || isCurrent
                            ? FontWeight.bold : FontWeight.normal,
                        fontSize: 13,
                      ),
                    ),
                  ),
                );
              }),
            ),
          ],
        ),
      ),
    );
  }
}
