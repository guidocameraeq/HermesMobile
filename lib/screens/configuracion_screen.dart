import 'package:flutter/material.dart';
import '../config/theme.dart';
import '../models/session.dart';
import '../services/auth_service.dart';
import '../services/biometric_service.dart';
import '../services/calendar_service.dart';
import '../services/update_service.dart';
import '../services/pg_service.dart';
import '../services/error_logger.dart';
import 'login_screen.dart';

class ConfiguracionScreen extends StatefulWidget {
  const ConfiguracionScreen({super.key});

  @override
  State<ConfiguracionScreen> createState() => _ConfiguracionState();
}

class _ConfiguracionState extends State<ConfiguracionScreen> {
  final _feedbackCtrl = TextEditingController();
  bool _sendingFeedback = false;
  String _feedbackMsg = '';

  String _appVersion = '...';
  ReleaseInfo? _updateAvailable;
  bool _checkingUpdate = false;
  bool _downloading = false;
  double _downloadProgress = 0;

  bool _bioDisponible = false;
  bool _bioHabilitado = false;

  String _calMode = 'off';       // off | manual | auto
  String? _calAccount;
  bool _calConnecting = false;

  @override
  void initState() {
    super.initState();
    _loadVersion();
    _loadBio();
    _loadCalendar();
    _checkUpdate();
  }

  Future<void> _loadCalendar() async {
    final mode = await CalendarService.I.getMode();
    final acc = await CalendarService.I.getAccount();
    if (mounted) setState(() { _calMode = mode; _calAccount = acc; });
  }

  Future<void> _loadVersion() async {
    final v = await UpdateService.currentVersion();
    if (mounted) setState(() => _appVersion = v);
  }

  Future<void> _loadBio() async {
    final d = await BiometricService.disponible();
    final h = await BiometricService.habilitado();
    if (mounted) setState(() { _bioDisponible = d; _bioHabilitado = h; });
  }

  Future<void> _checkUpdate() async {
    setState(() => _checkingUpdate = true);
    final r = await UpdateService.checkForUpdate();
    if (mounted) setState(() { _updateAvailable = r; _checkingUpdate = false; });
  }

  Future<void> _downloadUpdate() async {
    if (_updateAvailable == null) return;
    setState(() { _downloading = true; _downloadProgress = 0; });
    final ok = await UpdateService.installOrDownload(
      _updateAvailable!,
      onProgress: (p) { if (mounted) setState(() => _downloadProgress = p); },
    );
    if (!mounted) return;
    setState(() => _downloading = false);
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No se pudo instalar la actualización'),
            backgroundColor: AppColors.danger),
      );
    }
  }

  Future<void> _connectCalendar() async {
    setState(() => _calConnecting = true);
    try {
      final email = await CalendarService.I.connect();
      await CalendarService.I.setMode('manual');
      if (!mounted) return;
      setState(() { _calAccount = email; _calMode = 'manual'; _calConnecting = false; });
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Conectado como $email'),
        backgroundColor: AppColors.success,
      ));
    } catch (e) {
      if (!mounted) return;
      setState(() => _calConnecting = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Error conectando: ${e.toString().replaceFirst("Exception: ", "")}'),
        backgroundColor: AppColors.danger,
      ));
    }
  }

  Future<void> _disconnectCalendar() async {
    await CalendarService.I.disconnect();
    if (!mounted) return;
    setState(() { _calAccount = null; _calMode = 'off'; });
  }

  Future<void> _setCalMode(String mode) async {
    await CalendarService.I.setMode(mode);
    if (mounted) setState(() => _calMode = mode);
  }

  Future<void> _toggleBio() async {
    if (_bioHabilitado) {
      await BiometricService.deshabilitar();
      if (!mounted) return;
      setState(() => _bioHabilitado = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Huella desactivada'),
            backgroundColor: AppColors.textMuted),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Cerrá sesión e ingresá con contraseña para activar la huella'),
          backgroundColor: AppColors.accent,
        ),
      );
    }
  }

  Future<void> _sendFeedback() async {
    final msg = _feedbackCtrl.text.trim();
    if (msg.isEmpty) return;
    setState(() { _sendingFeedback = true; _feedbackMsg = ''; });
    try {
      await PgService.execute(
        'INSERT INTO feedback (usuario, mensaje, modulo, estado) '
        "VALUES (@user, @msg, 'mobile', 'pendiente')",
        {'user': Session.current.username, 'msg': msg},
      );
      _feedbackCtrl.clear();
      if (mounted) setState(() {
        _sendingFeedback = false;
        _feedbackMsg = 'Enviado correctamente';
      });
    } catch (e) {
      if (mounted) setState(() {
        _sendingFeedback = false;
        _feedbackMsg = 'Error: $e';
      });
    }
  }

  Future<void> _logout() async {
    await BiometricService.deshabilitar();
    AuthService.logout();
    if (!mounted) return;
    Navigator.of(context, rootNavigator: true).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (_) => false,
    );
  }

  @override
  void dispose() { _feedbackCtrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final session = Session.current;
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.bgSidebar,
        title: const Text('Configuración', style: AppTextStyles.title),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (_updateAvailable != null) _buildUpdateBanner(),

          // ── Perfil ──────────────────────────────────────
          Container(
            padding: const EdgeInsets.all(16),
            decoration: AppCardStyle.base(),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 28,
                  backgroundColor: AppColors.primary,
                  child: Text(
                    session.vendedorNombre.isNotEmpty
                        ? session.vendedorNombre[0].toUpperCase() : '?',
                    style: const TextStyle(color: Colors.white,
                        fontSize: 22, fontWeight: FontWeight.bold),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(session.vendedorNombre, style: AppTextStyles.title),
                      const SizedBox(height: 2),
                      Text('Usuario: ${session.username}', style: AppTextStyles.caption),
                      Text('Rol: ${session.role}', style: AppTextStyles.muted),
                    ],
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 14),

          // ── Seguridad ───────────────────────────────────
          if (_bioDisponible)
            Container(
              decoration: AppCardStyle.base(),
              child: SwitchListTile(
                value: _bioHabilitado,
                onChanged: (_) => _toggleBio(),
                activeColor: AppColors.success,
                title: const Text('Login con huella', style: AppTextStyles.body),
                subtitle: Text(_bioHabilitado ? 'Activo' : 'Inactivo',
                    style: AppTextStyles.muted),
                secondary: Icon(
                  _bioHabilitado ? Icons.fingerprint : Icons.fingerprint_outlined,
                  color: _bioHabilitado ? AppColors.success : AppColors.textMuted,
                ),
              ),
            ),

          const SizedBox(height: 14),

          // ── Google Calendar ──────────────────────────────
          _buildCalendarCard(),

          const SizedBox(height: 14),

          // ── App ─────────────────────────────────────────
          Container(
            padding: const EdgeInsets.all(16),
            decoration: AppCardStyle.base(),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Aplicación', style: AppTextStyles.title),
                const SizedBox(height: 10),
                _row('Versión', 'v$_appVersion'),
                const _Row('Plataforma', 'Android'),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: _checkingUpdate ? null : _checkUpdate,
                    icon: _checkingUpdate
                        ? const SizedBox(width: 16, height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.accent))
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

          const SizedBox(height: 14),

          // ── Feedback ────────────────────────────────────
          _expandable('Enviar feedback', Icons.chat_bubble_outline, _buildFeedbackBody()),

          // ── Errores recientes ───────────────────────────
          if (ErrorLogger.recent.isNotEmpty) ...[
            const SizedBox(height: 14),
            _expandable(
              'Errores recientes (${ErrorLogger.recent.length})',
              Icons.warning_amber_outlined,
              _buildErroresBody(),
            ),
          ],

          const SizedBox(height: 20),

          // ── Cerrar sesión ───────────────────────────────
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

          const SizedBox(height: 30),
        ],
      ),
    );
  }

  Widget _buildCalendarCard() {
    final connected = _calAccount != null;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: AppCardStyle.base(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 36, height: 36,
                decoration: BoxDecoration(
                  color: connected
                      ? AppColors.success.withOpacity(0.15)
                      : AppColors.bg,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(Icons.event_available,
                    color: connected ? AppColors.success : AppColors.textMuted,
                    size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Google Calendar', style: AppTextStyles.body),
                    Text(
                      connected ? _calAccount! : 'Desconectado',
                      style: AppTextStyles.muted,
                      maxLines: 1, overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              if (connected)
                IconButton(
                  icon: const Icon(Icons.logout, color: AppColors.textMuted, size: 18),
                  tooltip: 'Desconectar',
                  onPressed: _disconnectCalendar,
                ),
            ],
          ),
          const SizedBox(height: 12),
          if (!connected) ...[
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _calConnecting ? null : _connectCalendar,
                icon: _calConnecting
                    ? const SizedBox(width: 16, height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.link, size: 18),
                label: Text(_calConnecting ? 'Conectando...' : 'Conectar con Google'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
              ),
            ),
          ] else ...[
            const Text('Modo de sincronización', style: AppTextStyles.muted),
            const SizedBox(height: 6),
            _modeChip('off', 'Desactivado', Icons.toggle_off),
            _modeChip('manual', 'Manual — botón en cada actividad', Icons.touch_app),
            _modeChip('auto', 'Automático — toda actividad nueva', Icons.sync),
          ],
        ],
      ),
    );
  }

  Widget _modeChip(String value, String label, IconData icon) {
    final sel = _calMode == value;
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: InkWell(
        onTap: () => _setCalMode(value),
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: sel ? AppColors.primary.withOpacity(0.15) : AppColors.bg,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: sel ? AppColors.primary : AppColors.border,
              width: sel ? 1.5 : 1,
            ),
          ),
          child: Row(
            children: [
              Icon(icon, size: 16,
                  color: sel ? AppColors.primary : AppColors.textMuted),
              const SizedBox(width: 10),
              Expanded(
                child: Text(label, style: TextStyle(
                  color: sel ? AppColors.textPrimary : AppColors.textSecondary,
                  fontSize: 12,
                  fontWeight: sel ? FontWeight.w600 : FontWeight.normal,
                )),
              ),
              if (sel)
                const Icon(Icons.check_circle, color: AppColors.primary, size: 16),
            ],
          ),
        ),
      ),
    );
  }

  Widget _expandable(String title, IconData icon, Widget body) {
    return Container(
      decoration: AppCardStyle.base(),
      clipBehavior: Clip.antiAlias,
      child: Theme(
        data: Theme.of(context).copyWith(
          dividerColor: Colors.transparent,
          listTileTheme: const ListTileThemeData(tileColor: Colors.transparent),
        ),
        child: ExpansionTile(
          iconColor: AppColors.textMuted,
          collapsedIconColor: AppColors.textMuted,
          leading: Icon(icon, color: AppColors.textSecondary, size: 20),
          title: Text(title, style: AppTextStyles.body),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          children: [body],
        ),
      ),
    );
  }

  Widget _buildFeedbackBody() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Reportá un error o sugerencia al administrador.',
            style: AppTextStyles.muted),
        const SizedBox(height: 10),
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
                ? const SizedBox(width: 18, height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Text('Enviar'),
          ),
        ),
      ],
    );
  }

  Widget _buildErroresBody() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Align(
          alignment: Alignment.centerRight,
          child: GestureDetector(
            onTap: () => setState(() => ErrorLogger.clear()),
            child: const Text('Limpiar',
                style: TextStyle(color: AppColors.textMuted, fontSize: 11)),
          ),
        ),
        const SizedBox(height: 4),
        ...ErrorLogger.recent.take(10).map((e) => Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(e.timeStr, style: AppTextStyles.muted),
              const SizedBox(width: 8),
              Expanded(
                child: Text('${e.source}: ${e.message}',
                  style: const TextStyle(color: AppColors.danger, fontSize: 11),
                  maxLines: 3, overflow: TextOverflow.ellipsis),
              ),
            ],
          ),
        )),
      ],
    );
  }

  Widget _row(String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: AppTextStyles.caption),
        Text(value, style: AppTextStyles.muted),
      ],
    ),
  );

  Widget _buildUpdateBanner() {
    final r = _updateAvailable!;
    final sizeMb = (r.apkSize / 1024 / 1024).toStringAsFixed(1);
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
          Row(children: [
            const Icon(Icons.system_update, color: AppColors.success, size: 22),
            const SizedBox(width: 8),
            Expanded(child: Text('Nueva versión: ${r.tagName}',
                style: AppTextStyles.title.copyWith(color: AppColors.success))),
          ]),
          const SizedBox(height: 8),
          Text(r.name, style: AppTextStyles.caption),
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
            Text('Descargando... ${(_downloadProgress * 100).toStringAsFixed(0)}%',
                style: AppTextStyles.muted),
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

class _Row extends StatelessWidget {
  final String label;
  final String value;
  const _Row(this.label, this.value);

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
