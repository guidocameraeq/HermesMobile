import 'package:flutter/material.dart';
import '../config/theme.dart';
import '../models/session.dart';
import '../services/visitas_service.dart';
import '../services/pedidos_service.dart';
import '../services/actividades_service.dart';
import '../services/update_service.dart';
import '../widgets/app_drawer.dart';
import 'visita_cliente_picker.dart';
import 'mis_visitas_screen.dart';
import 'pedidos_screen.dart';
import 'agenda_screen.dart';
import 'ventas_tab.dart';
import 'configuracion_screen.dart';

class AccionesTab extends StatefulWidget {
  const AccionesTab({super.key});

  @override
  State<AccionesTab> createState() => _AccionesTabState();
}

class _AccionesTabState extends State<AccionesTab> with AutomaticKeepAliveClientMixin {
  int _visitasHoy = 0;
  int _pedidosPend = 0;
  int _actividadesPend = 0;

  ReleaseInfo? _updateAvailable;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _loadAll();
    _checkUpdate();
  }

  Future<void> _loadAll() async {
    _loadVisitasHoy();
    _loadPedidosPend();
    _loadActividadesPend();
  }

  Future<void> _loadVisitasHoy() async {
    try {
      final c = await VisitasService.conteoHoy();
      if (mounted) setState(() => _visitasHoy = c);
    } catch (_) {}
  }

  Future<void> _loadActividadesPend() async {
    try {
      final c = await ActividadesService.conteoPendientes();
      if (mounted) setState(() => _actividadesPend = c);
    } catch (_) {}
  }

  Future<void> _loadPedidosPend() async {
    try {
      final c = await PedidosService.conteoPendientes(Session.current.vendedorNombre);
      if (mounted) setState(() => _pedidosPend = c);
    } catch (_) {}
  }

  Future<void> _checkUpdate() async {
    final r = await UpdateService.checkForUpdate();
    if (mounted) setState(() => _updateAvailable = r);
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Scaffold(
      backgroundColor: AppColors.bg,
      drawer: const AppDrawer(currentTab: 3),
      appBar: AppBar(
        backgroundColor: AppColors.bgSidebar,
        title: const Text('Acciones', style: AppTextStyles.title),
        actions: const [AppBarAvatar()],
      ),
      body: RefreshIndicator(
        color: AppColors.primary,
        onRefresh: () async { await _loadAll(); await _checkUpdate(); },
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (_updateAvailable != null) _buildUpdateBanner(),

            _section('Campo'),
            Row(children: [
              Expanded(child: _Tile(
                icon: Icons.add_location_alt,
                label: 'Registrar visita',
                color: AppColors.success,
                onTap: () async {
                  await Navigator.push(context, MaterialPageRoute(
                    builder: (_) => const VisitaClientePickerScreen()));
                  _loadVisitasHoy();
                },
              )),
              const SizedBox(width: 8),
              Expanded(child: _Tile(
                icon: Icons.location_on,
                label: 'Mis visitas',
                color: AppColors.accent,
                badge: _visitasHoy > 0 ? '$_visitasHoy hoy' : null,
                onTap: () => Navigator.push(context, MaterialPageRoute(
                    builder: (_) => const MisVisitasScreen())),
              )),
            ]),
            const SizedBox(height: 10),

            _section('Agenda'),
            Row(children: [
              Expanded(child: _Tile(
                icon: Icons.event_note,
                label: 'Mi Agenda',
                color: AppColors.warning,
                badge: _actividadesPend > 0 ? '$_actividadesPend pend.' : null,
                onTap: () async {
                  await Navigator.push(context, MaterialPageRoute(
                    builder: (_) => const AgendaScreen()));
                  _loadActividadesPend();
                },
              )),
              const SizedBox(width: 8),
              Expanded(child: _Tile(
                icon: Icons.inventory_2_outlined,
                label: 'Pedidos',
                color: AppColors.primary,
                badge: _pedidosPend > 0 ? '$_pedidosPend pend.' : null,
                onTap: () async {
                  await Navigator.push(context, MaterialPageRoute(
                    builder: (_) => const PedidosScreen()));
                  _loadPedidosPend();
                },
              )),
            ]),
            const SizedBox(height: 10),

            _section('Análisis'),
            _Tile(
              icon: Icons.trending_up,
              label: 'Ventas',
              color: AppColors.accent,
              fullWidth: true,
              onTap: () => Navigator.push(context, MaterialPageRoute(
                  builder: (_) => const VentasTab())),
            ),

            const SizedBox(height: 24),

            OutlinedButton.icon(
              onPressed: () => Navigator.push(context, MaterialPageRoute(
                  builder: (_) => const ConfiguracionScreen())),
              icon: const Icon(Icons.settings, size: 18),
              label: const Text('Configuración'),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.textSecondary,
                side: const BorderSide(color: AppColors.border),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),

            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Widget _section(String label) => Padding(
    padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
    child: Text(label.toUpperCase(), style: TextStyle(
      color: AppColors.textMuted, fontSize: 10,
      fontWeight: FontWeight.w700, letterSpacing: 1.2)),
  );

  Widget _buildUpdateBanner() {
    final r = _updateAvailable!;
    return GestureDetector(
      onTap: () => Navigator.push(context, MaterialPageRoute(
          builder: (_) => const ConfiguracionScreen())),
      child: Container(
        margin: const EdgeInsets.only(bottom: 16),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.success.withOpacity(0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.success.withOpacity(0.4)),
        ),
        child: Row(children: [
          const Icon(Icons.system_update, color: AppColors.success, size: 22),
          const SizedBox(width: 10),
          Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Actualización disponible: ${r.tagName}',
                  style: AppTextStyles.body.copyWith(
                      color: AppColors.success, fontWeight: FontWeight.w600)),
              const Text('Tocá para ir a Configuración', style: AppTextStyles.muted),
            ],
          )),
          const Icon(Icons.chevron_right, color: AppColors.success),
        ]),
      ),
    );
  }
}

class _Tile extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final String? badge;
  final VoidCallback onTap;
  final bool fullWidth;

  const _Tile({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
    this.badge,
    this.fullWidth = false,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: color.withOpacity(0.08),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withOpacity(0.25)),
        ),
        child: fullWidth
            ? Row(children: [
                Icon(icon, color: color, size: 28),
                const SizedBox(width: 12),
                Expanded(child: Text(label,
                    style: TextStyle(color: color, fontSize: 14,
                        fontWeight: FontWeight.w600))),
                Icon(Icons.chevron_right, color: color.withOpacity(0.6)),
              ])
            : Column(children: [
                Icon(icon, color: color, size: 28),
                const SizedBox(height: 8),
                Text(label, textAlign: TextAlign.center, style: TextStyle(
                    color: color, fontSize: 12, fontWeight: FontWeight.w600)),
                if (badge != null) ...[
                  const SizedBox(height: 4),
                  Text(badge!, style: AppTextStyles.muted),
                ],
              ]),
      ),
    );
  }
}
