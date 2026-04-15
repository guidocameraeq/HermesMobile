import 'package:flutter/material.dart';
import '../config/theme.dart';
import '../models/session.dart';
import '../services/auth_service.dart';
import '../services/pg_service.dart';
import '../services/update_service.dart';
import '../services/error_logger.dart';
import '../services/visitas_service.dart';
import 'login_screen.dart';
import 'visita_cliente_picker.dart';
import 'mis_visitas_screen.dart';

class MasTab extends StatefulWidget {
  const MasTab({super.key});

  @override
  State<MasTab> createState() => _MasTabState();
}

class _MasTabState extends State<MasTab> with AutomaticKeepAliveClientMixin {
  final _feedbackCtrl = TextEditingController();
  bool _sendingFeedback = false;
  String _feedbackMsg = '';

  // Updates
  ReleaseInfo? _updateAvailable;
  bool _checkingUpdate = false;
  bool _downloading = false;
  double _downloadProgress = 0;
  String _appVersion = '...';

  // Visitas
  int _visitasHoy = 0;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _loadVersion();
    _checkUpdate();
    _loadVisitasHoy();
  }

  Future<void> _loadVersion() async {
    final v = await UpdateService.currentVersion();
    if (mounted) setState(() => _appVersion = v);
  }

  Future<void> _loadVisitasHoy() async {
    try {
      final count = await VisitasService.conteoHoy();
      if (mounted) setState(() => _visitasHoy = count);
    } catch (_) {}
  }

  Future<void> _checkUpdate() async {
    setState(() => _checkingUpdate = true);
    final release = await UpdateService.checkForUpdate();
    if (mounted) {
      setState(() {
        _updateAvailable = release;
        _checkingUpdate = false;
      });
    }
  }

  Future<void> _downloadUpdate() async {
    if (_updateAvailable == null) return;
    setState(() {
      _downloading = true;
      _downloadProgress = 0;
    });

    final ok = await UpdateService.downloadAndInstall(
      _updateAvailable!,
      onProgress: (p) {
        if (mounted) setState(() => _downloadProgress = p);
      },
    );

    if (mounted) {
      setState(() => _downloading = false);
      if (!ok) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No se pudo instalar la actualización'),
            backgroundColor: AppColors.danger,
          ),
        );
      }
    }
  }

  void _logout() {
    AuthService.logout();
    Navigator.of(context, rootNavigator: true).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (_) => false,
    );
  }

  Future<void> _sendFeedback() async {
    final msg = _feedbackCtrl.text.trim();
    if (msg.isEmpty) return;

    setState(() {
      _sendingFeedback = true;
      _feedbackMsg = '';
    });

    try {
      await PgService.execute(
        'INSERT INTO feedback (usuario, mensaje, modulo, estado) '
        "VALUES (@user, @msg, 'mobile', 'pendiente')",
        {'user': Session.current.username, 'msg': msg},
      );
      _feedbackCtrl.clear();
      if (mounted) {
        setState(() {
          _sendingFeedback = false;
          _feedbackMsg = 'Enviado correctamente';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _sendingFeedback = false;
          _feedbackMsg = 'Error: $e';
        });
      }
    }
  }

  @override
  void dispose() {
    _feedbackCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final session = Session.current;

    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.bgSidebar,
        title: const Text('Más', style: AppTextStyles.title),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ── Banner de actualización ────────────────────────────
          if (_updateAvailable != null) _buildUpdateBanner(),

          // ── Visitas ─────────────────────────────────────────
          Row(
            children: [
              Expanded(
                child: _MenuTile(
                  icon: Icons.add_location_alt,
                  label: 'Registrar visita',
                  color: AppColors.success,
                  onTap: () async {
                    await Navigator.push(context,
                        MaterialPageRoute(builder: (_) => const VisitaClientePickerScreen()));
                    _loadVisitasHoy();
                  },
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _MenuTile(
                  icon: Icons.location_on,
                  label: 'Mis visitas',
                  color: AppColors.accent,
                  badge: _visitasHoy > 0 ? '$_visitasHoy hoy' : null,
                  onTap: () => Navigator.push(context,
                      MaterialPageRoute(builder: (_) => const MisVisitasScreen())),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // ── Perfil ──────────────────────────────────────────
          Container(
            padding: const EdgeInsets.all(16),
            decoration: AppCardStyle.base(),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 24,
                  backgroundColor: AppColors.primary,
                  child: Text(
                    session.vendedorNombre.isNotEmpty
                        ? session.vendedorNombre[0].toUpperCase()
                        : '?',
                    style: const TextStyle(
                      color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(session.vendedorNombre, style: AppTextStyles.title),
                      const SizedBox(height: 2),
                      Text('Rol: ${session.role}', style: AppTextStyles.caption),
                    ],
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // ── Info de la app + buscar actualizaciones ────────────
          Container(
            padding: const EdgeInsets.all(16),
            decoration: AppCardStyle.base(),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Hermes Mobile', style: AppTextStyles.title),
                const SizedBox(height: 8),
                _InfoRow(label: 'Versión', value: 'v$_appVersion'),
                const _InfoRow(label: 'Plataforma', value: 'Android'),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: _checkingUpdate ? null : _checkUpdate,
                    icon: _checkingUpdate
                        ? const SizedBox(
                            width: 16, height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.accent),
                          )
                        : const Icon(Icons.system_update, size: 18),
                    label: Text(_checkingUpdate
                        ? 'Buscando...'
                        : _updateAvailable != null
                            ? 'Actualización disponible'
                            : 'Estás al día'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: _updateAvailable != null ? AppColors.success : AppColors.textMuted,
                      side: BorderSide(
                        color: _updateAvailable != null
                            ? AppColors.success.withOpacity(0.5)
                            : AppColors.border,
                      ),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // ── Feedback ──────────────────────────────────────────
          Container(
            padding: const EdgeInsets.all(16),
            decoration: AppCardStyle.base(),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Enviar comentario', style: AppTextStyles.title),
                const SizedBox(height: 4),
                const Text(
                  'Reportá un error o sugerencia al administrador.',
                  style: AppTextStyles.muted,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _feedbackCtrl,
                  style: AppTextStyles.body,
                  maxLines: 3,
                  decoration: InputDecoration(
                    hintText: 'Escribí tu comentario...',
                    hintStyle: AppTextStyles.muted,
                    filled: true,
                    fillColor: AppColors.bg,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: AppColors.border),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: AppColors.border),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: AppColors.primary),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                if (_feedbackMsg.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(
                      _feedbackMsg,
                      style: TextStyle(
                        color: _feedbackMsg.startsWith('Error')
                            ? AppColors.danger
                            : AppColors.success,
                        fontSize: 12,
                      ),
                    ),
                  ),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _sendingFeedback ? null : _sendFeedback,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    child: _sendingFeedback
                        ? const SizedBox(
                            width: 18, height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : const Text('Enviar'),
                  ),
                ),
              ],
            ),
          ),

          // ── Errores recientes ────────────────────────────────
          if (ErrorLogger.recent.isNotEmpty) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: AppCardStyle.base(),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Expanded(child: Text('Errores recientes', style: AppTextStyles.title)),
                      GestureDetector(
                        onTap: () => setState(() => ErrorLogger.clear()),
                        child: const Text('Limpiar', style: TextStyle(
                          color: AppColors.textMuted, fontSize: 11)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  ...ErrorLogger.recent.take(5).map((e) => Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(e.timeStr, style: AppTextStyles.muted),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text('${e.source}: ${e.message}',
                            style: const TextStyle(color: AppColors.danger, fontSize: 11),
                            maxLines: 2, overflow: TextOverflow.ellipsis),
                        ),
                      ],
                    ),
                  )),
                ],
              ),
            ),
          ],

          const SizedBox(height: 24),

          // ── Cerrar sesión ──────────────────────────────────────
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _logout,
              icon: const Icon(Icons.logout, size: 18),
              label: const Text('Cerrar sesión'),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.danger,
                side: BorderSide(color: AppColors.danger.withOpacity(0.5)),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          ),

          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _buildUpdateBanner() {
    final release = _updateAvailable!;
    final sizeMb = (release.apkSize / 1024 / 1024).toStringAsFixed(1);

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.success.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.success.withOpacity(0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.system_update, color: AppColors.success, size: 22),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Nueva versión: ${release.tagName}',
                  style: AppTextStyles.title.copyWith(color: AppColors.success),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(release.name, style: AppTextStyles.caption),
          Text('$sizeMb MB', style: AppTextStyles.muted),
          const SizedBox(height: 12),

          if (_downloading) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: _downloadProgress,
                minHeight: 8,
                backgroundColor: AppColors.border,
                valueColor: const AlwaysStoppedAnimation<Color>(AppColors.success),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Descargando... ${(_downloadProgress * 100).toStringAsFixed(0)}%',
              style: AppTextStyles.muted,
            ),
          ] else
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _downloadUpdate,
                icon: const Icon(Icons.download, size: 18),
                label: const Text('Descargar e instalar'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.success,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;
  const _InfoRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: AppTextStyles.caption),
          Text(value, style: AppTextStyles.muted),
        ],
      ),
    );
  }
}

class _MenuTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final String? badge;
  final VoidCallback onTap;

  const _MenuTile({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
    this.badge,
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
        child: Column(
          children: [
            Icon(icon, color: color, size: 28),
            const SizedBox(height: 8),
            Text(label, style: TextStyle(
              color: color, fontSize: 12, fontWeight: FontWeight.w600),
              textAlign: TextAlign.center,
            ),
            if (badge != null) ...[
              const SizedBox(height: 4),
              Text(badge!, style: AppTextStyles.muted),
            ],
          ],
        ),
      ),
    );
  }
}
