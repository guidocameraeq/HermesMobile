import 'package:flutter/material.dart';
import '../config/theme.dart';

/// Placeholder — se completa en Fase 5.
class VentasTab extends StatelessWidget {
  const VentasTab({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.bgSidebar,
        title: const Text('Ventas', style: AppTextStyles.title),
      ),
      body: const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.trending_up, color: AppColors.textMuted, size: 56),
            SizedBox(height: 16),
            Text('Próximamente', style: AppTextStyles.caption),
            SizedBox(height: 4),
            Text(
              'KPIs de ventas, gráficos de evolución\ny top clientes/productos.',
              style: AppTextStyles.muted,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
