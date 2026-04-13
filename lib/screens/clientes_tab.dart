import 'package:flutter/material.dart';
import '../config/theme.dart';

/// Placeholder — se completa en Fase 3.
class ClientesTab extends StatelessWidget {
  const ClientesTab({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.bgSidebar,
        title: const Text('Clientes', style: AppTextStyles.title),
      ),
      body: const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.people_outline, color: AppColors.textMuted, size: 56),
            SizedBox(height: 16),
            Text('Próximamente', style: AppTextStyles.caption),
            SizedBox(height: 4),
            Text(
              'Listado de clientes con búsqueda\ny última compra.',
              style: AppTextStyles.muted,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
