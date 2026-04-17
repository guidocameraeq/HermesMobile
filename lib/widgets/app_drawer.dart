import 'package:flutter/material.dart';
import '../config/theme.dart';
import '../models/session.dart';
import '../screens/home_controller.dart';
import '../screens/agenda_screen.dart';
import '../screens/mis_visitas_screen.dart';
import '../screens/visita_cliente_picker.dart';
import '../screens/pedidos_screen.dart';
import '../screens/ventas_tab.dart';
import '../screens/configuracion_screen.dart';

/// Drawer lateral — contiene TODO el menú de la app.
/// Las 4 tabs principales (Scorecard/Cronos/Clientes/Acciones) se pueden
/// cambiar desde acá; el resto son pantallas pushadas.
class AppDrawer extends StatelessWidget {
  final int currentTab;
  const AppDrawer({super.key, required this.currentTab});

  @override
  Widget build(BuildContext context) {
    final session = Session.current;
    final inicial = session.vendedorNombre.isNotEmpty
        ? session.vendedorNombre[0].toUpperCase()
        : '?';

    return Drawer(
      backgroundColor: AppColors.bgSidebar,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── Header con usuario ────────────────────────
            Container(
              padding: const EdgeInsets.fromLTRB(18, 20, 18, 16),
              decoration: const BoxDecoration(
                border: Border(bottom: BorderSide(color: AppColors.border)),
              ),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 24,
                    backgroundColor: AppColors.primary,
                    child: Text(inicial, style: const TextStyle(
                      color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(session.vendedorNombre, style: AppTextStyles.title,
                            maxLines: 1, overflow: TextOverflow.ellipsis),
                        Text(session.role, style: AppTextStyles.muted),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // ── Navegación principal (tabs) ────────────────
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(vertical: 8),
                children: [
                  _sectionLabel('NAVEGACIÓN'),
                  _tabItem(context, Icons.bar_chart_rounded, 'Scorecard', 0),
                  _tabItem(context, Icons.schedule_send, 'Cronos', 1),
                  _tabItem(context, Icons.people_outline, 'Clientes', 2),
                  _tabItem(context, Icons.apps, 'Acciones', 3),

                  const SizedBox(height: 8),
                  _sectionLabel('HERRAMIENTAS'),
                  _pushItem(context, Icons.event_note, 'Mi Agenda',
                      const AgendaScreen()),
                  _pushItem(context, Icons.add_location_alt, 'Registrar visita',
                      const VisitaClientePickerScreen()),
                  _pushItem(context, Icons.location_on, 'Mis visitas',
                      const MisVisitasScreen()),
                  _pushItem(context, Icons.inventory_2_outlined, 'Pedidos',
                      const PedidosScreen()),
                  _pushItem(context, Icons.trending_up, 'Ventas',
                      const VentasTab()),

                  const SizedBox(height: 8),
                  _sectionLabel('CUENTA'),
                  _pushItem(context, Icons.settings, 'Configuración',
                      const ConfiguracionScreen()),
                ],
              ),
            ),

            Container(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              decoration: const BoxDecoration(
                border: Border(top: BorderSide(color: AppColors.border)),
              ),
              child: Text('Hermes Mobile',
                  style: AppTextStyles.muted.copyWith(fontSize: 10),
                  textAlign: TextAlign.center),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionLabel(String label) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 10, 20, 6),
    child: Text(label, style: TextStyle(
      color: AppColors.textMuted,
      fontSize: 10,
      fontWeight: FontWeight.w700,
      letterSpacing: 1.2,
    )),
  );

  Widget _tabItem(BuildContext context, IconData icon, String label, int index) {
    final selected = index == currentTab;
    return InkWell(
      onTap: () {
        Navigator.pop(context); // cerrar drawer
        HomeController.switchTab(index);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        decoration: BoxDecoration(
          color: selected ? AppColors.primary.withOpacity(0.12) : Colors.transparent,
          border: Border(
            left: BorderSide(
              color: selected ? AppColors.primary : Colors.transparent,
              width: 3,
            ),
          ),
        ),
        child: Row(
          children: [
            Icon(icon,
                color: selected ? AppColors.primary : AppColors.textSecondary,
                size: 20),
            const SizedBox(width: 14),
            Text(label, style: TextStyle(
              color: selected ? AppColors.textPrimary : AppColors.textSecondary,
              fontSize: 14,
              fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
            )),
          ],
        ),
      ),
    );
  }

  Widget _pushItem(BuildContext context, IconData icon, String label, Widget dest) {
    return InkWell(
      onTap: () {
        Navigator.pop(context);
        Navigator.push(context, MaterialPageRoute(builder: (_) => dest));
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 11),
        child: Row(
          children: [
            Icon(icon, color: AppColors.textSecondary, size: 20),
            const SizedBox(width: 14),
            Expanded(
              child: Text(label, style: const TextStyle(
                color: AppColors.textSecondary, fontSize: 14)),
            ),
            const Icon(Icons.chevron_right, color: AppColors.textMuted, size: 18),
          ],
        ),
      ),
    );
  }
}

/// Icono-avatar reutilizable para el AppBar (top-right) — abre Configuración.
class AppBarAvatar extends StatelessWidget {
  const AppBarAvatar({super.key});

  @override
  Widget build(BuildContext context) {
    final inicial = Session.current.vendedorNombre.isNotEmpty
        ? Session.current.vendedorNombre[0].toUpperCase()
        : '?';
    return Padding(
      padding: const EdgeInsets.only(right: 10),
      child: GestureDetector(
        onTap: () => Navigator.push(context,
            MaterialPageRoute(builder: (_) => const ConfiguracionScreen())),
        child: CircleAvatar(
          radius: 16,
          backgroundColor: AppColors.primary,
          child: Text(inicial, style: const TextStyle(
            color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold)),
        ),
      ),
    );
  }
}
