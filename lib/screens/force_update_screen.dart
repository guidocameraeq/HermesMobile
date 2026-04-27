import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../config/theme.dart';
import '../services/update_service.dart';
import '../services/auth_service.dart';
import 'login_screen.dart';

/// Pantalla bloqueante full-screen — el vendedor solo puede actualizar
/// o cerrar sesión. Sin back, sin escape, sin botón "después".
///
/// Se muestra cuando `UpdateService.checkForceUpdate()` retorna != null
/// (la versión local es menor a `app_config.min_version_required`).
class ForceUpdateScreen extends StatefulWidget {
  final ReleaseInfo release;
  const ForceUpdateScreen({super.key, required this.release});

  @override
  State<ForceUpdateScreen> createState() => _ForceUpdateScreenState();
}

class _ForceUpdateScreenState extends State<ForceUpdateScreen> {
  bool _installing = false;
  double _progress = 0;
  String? _error;

  Future<void> _install() async {
    if (_installing) return;
    setState(() {
      _installing = true;
      _error = null;
      _progress = 0;
    });
    HapticFeedback.mediumImpact();

    try {
      final ok = await UpdateService.installOrDownload(
        widget.release,
        onProgress: (p) {
          if (mounted) setState(() => _progress = p);
        },
      );
      if (!mounted) return;
      if (!ok) {
        setState(() {
          _installing = false;
          _error = 'No se pudo abrir el instalador. Reintentá.';
        });
      }
      // Si ok=true, Android tomó el control con el dialog del instalador.
      // Cuando el vendedor confirme + instale + reabra → el chequeo
      // pasa y queda dentro de la app normalmente.
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _installing = false;
        _error = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  Future<void> _logout() async {
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.bgCard,
        title: const Text('¿Cerrar sesión?',
            style: TextStyle(color: AppColors.textPrimary)),
        content: const Text(
          'No vas a poder volver a usar Hermes hasta que actualices a la última versión.',
          style: TextStyle(color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Cerrar sesión',
                style: TextStyle(color: AppColors.danger)),
          ),
        ],
      ),
    );
    if (confirmar != true || !mounted) return;

    AuthService.logout();
    if (!mounted) return;
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (_) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false, // bloquea el back de Android
      child: Scaffold(
        backgroundColor: AppColors.bg,
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 40, 24, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Hero icon
                Center(
                  child: Container(
                    width: 96,
                    height: 96,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: const LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [AppColors.warning, AppColors.danger],
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.warning.withOpacity(0.4),
                          blurRadius: 30,
                          spreadRadius: 4,
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.system_update_alt,
                      color: Colors.white,
                      size: 48,
                    ),
                  ),
                ),

                const SizedBox(height: 28),

                // Título
                const Text(
                  'Actualización requerida',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 24,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Esta versión de Hermes ya no se acepta. Actualizá para seguir usando la app.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 13,
                    height: 1.45,
                  ),
                ),

                const SizedBox(height: 28),

                // Card con versión disponible
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppColors.bgCard,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.new_releases,
                          color: AppColors.success, size: 18),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Versión ${widget.release.tagName.replaceFirst("v", "")} disponible',
                          style: const TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      Text(
                        _formatSize(widget.release.apkSize),
                        style: const TextStyle(
                          color: AppColors.textMuted,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 20),

                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.danger.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                            color: AppColors.danger.withOpacity(0.4)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.error_outline,
                              color: AppColors.danger, size: 16),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              _error!,
                              style: const TextStyle(
                                color: AppColors.danger,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                if (_installing)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: Column(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: LinearProgressIndicator(
                            value: _progress > 0 ? _progress : null,
                            minHeight: 6,
                            backgroundColor: AppColors.bgCard,
                            valueColor: const AlwaysStoppedAnimation(
                                AppColors.primary),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _progress >= 1
                              ? 'Abriendo instalador…'
                              : _progress > 0
                                  ? 'Descargando ${(_progress * 100).toInt()}%'
                                  : 'Iniciando descarga…',
                          style: const TextStyle(
                            color: AppColors.textMuted,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),

                // Botón principal
                ElevatedButton.icon(
                  onPressed: _installing ? null : _install,
                  icon: const Icon(Icons.download, size: 18),
                  label: const Text(
                    'Actualizar ahora',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                    elevation: 0,
                  ),
                ),

                const SizedBox(height: 12),

                // Escape: cerrar sesión (escape de emergencia)
                TextButton(
                  onPressed: _installing ? null : _logout,
                  child: const Text(
                    'Cerrar sesión',
                    style: TextStyle(
                      color: AppColors.textMuted,
                      fontSize: 12,
                    ),
                  ),
                ),

                const SizedBox(height: 8),
                const Text(
                  'Si tenés problemas, contactá al admin.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: AppColors.textMuted,
                    fontSize: 10,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _formatSize(int bytes) {
    if (bytes <= 0) return '';
    final mb = bytes / (1024 * 1024);
    return '${mb.toStringAsFixed(1)} MB';
  }
}
