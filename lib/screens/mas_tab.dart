import 'package:flutter/material.dart';
import '../config/theme.dart';
import '../models/session.dart';
import '../services/auth_service.dart';
import '../services/pg_service.dart';
import 'login_screen.dart';

class MasTab extends StatefulWidget {
  const MasTab({super.key});

  @override
  State<MasTab> createState() => _MasTabState();
}

class _MasTabState extends State<MasTab> with AutomaticKeepAliveClientMixin {
  final _feedbackCtrl = TextEditingController();
  bool _sendingFeedback = false;
  String _feedbackMsg = '';

  @override
  bool get wantKeepAlive => true;

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
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
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
                      Text(
                        'Rol: ${session.role}',
                        style: AppTextStyles.caption,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // ── Info de la app ────────────────────────────────────
          Container(
            padding: const EdgeInsets.all(16),
            decoration: AppCardStyle.base(),
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Hermes Mobile', style: AppTextStyles.title),
                SizedBox(height: 8),
                _InfoRow(label: 'Versión', value: '1.0.0'),
                _InfoRow(label: 'Build', value: '1'),
                _InfoRow(label: 'Plataforma', value: 'Android'),
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
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    child: _sendingFeedback
                        ? const SizedBox(
                            width: 18, height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white),
                          )
                        : const Text('Enviar'),
                  ),
                ),
              ],
            ),
          ),

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
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          ),

          const SizedBox(height: 32),
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
