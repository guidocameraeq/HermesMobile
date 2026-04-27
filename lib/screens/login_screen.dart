import 'dart:async';
import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import '../services/analytics_service.dart';
import '../services/biometric_service.dart';
import '../services/update_service.dart';
import 'home_screen.dart';
import 'force_update_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _userCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  bool _loading = false;
  bool _obscurePass = true;
  String _errorMsg = '';

  bool _bioHabilitado = false;
  bool _bioDisponible = false;

  @override
  void initState() {
    super.initState();
    _checkBio();
  }

  Future<void> _checkBio() async {
    final disp = await BiometricService.disponible();
    final hab = await BiometricService.habilitado();
    if (!mounted) return;
    setState(() {
      _bioDisponible = disp;
      _bioHabilitado = hab;
    });
    // Auto-trigger si está habilitado
    if (disp && hab) {
      _loginBiometrico();
    }
  }

  Future<void> _loginBiometrico() async {
    final ok = await BiometricService.autenticar();
    if (!ok || !mounted) return;
    final creds = await BiometricService.leerCredenciales();
    if (creds == null || !mounted) return;
    setState(() => _loading = true);

    final result = await AuthService.login(creds.username, creds.password);
    if (!mounted) return;

    if (result.ok) {
      AnalyticsService.track('login', modulo: 'auth_bio');
      await _navigateAfterLogin();
    } else {
      // Credenciales guardadas inválidas → borrarlas y pedir login normal
      await BiometricService.deshabilitar();
      setState(() {
        _loading = false;
        _bioHabilitado = false;
        _errorMsg = 'Las credenciales guardadas no son válidas. Ingresá manualmente.';
      });
    }
  }

  Future<void> _preguntarHabilitarBio(String user, String pass) async {
    if (!_bioDisponible) return;
    if (await BiometricService.habilitado()) return;

    final aceptar = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF1C2333),
        title: const Text(
          '¿Usar huella digital?',
          style: TextStyle(color: Color(0xFFF8FAFC)),
        ),
        content: const Text(
          'Podés ingresar a Hermes con tu huella la próxima vez sin escribir usuario ni contraseña.',
          style: TextStyle(color: Color(0xFFCBD5E1), fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Ahora no', style: TextStyle(color: Color(0xFF94A3B8))),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF2563EB)),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Sí, activar'),
          ),
        ],
      ),
    );

    if (aceptar == true) {
      // Confirmar con huella antes de guardar
      final ok = await BiometricService.autenticar(
        motivo: 'Confirmá tu huella para activar el login biométrico',
      );
      if (ok) {
        await BiometricService.habilitar(user, pass);
      }
    }
  }

  /// Decide a dónde ir después de un login exitoso:
  ///  - Si hay force update pendiente → ForceUpdateScreen (bloqueante)
  ///  - Si no → HomeScreen + pre-download del APK soft en background
  Future<void> _navigateAfterLogin() async {
    final force = await UpdateService.checkForceUpdate();
    if (!mounted) return;

    if (force != null) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => ForceUpdateScreen(release: force)),
      );
      return;
    }

    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => const HomeScreen()),
    );

    // Soft update: pre-descargar APK si hay release nuevo. Sin await — corre
    // en background, cuando el vendedor toque "actualizar" en Configuración
    // ya está listo y el instalador abre instantáneo.
    unawaited(_predownloadIfAvailable());
  }

  Future<void> _predownloadIfAvailable() async {
    try {
      final release = await UpdateService.checkForUpdate();
      if (release != null) {
        await UpdateService.predownload(release);
      }
    } catch (_) {}
  }

  Future<void> _login() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _loading = true;
      _errorMsg = '';
    });

    final user = _userCtrl.text;
    final pass = _passCtrl.text;
    final result = await AuthService.login(user, pass);

    if (!mounted) return;

    if (result.ok) {
      AnalyticsService.track('login', modulo: 'auth');
      await _preguntarHabilitarBio(user, pass);
      if (!mounted) return;
      await _navigateAfterLogin();
    } else {
      setState(() {
        _loading = false;
        _errorMsg = result.errorMsg;
      });
    }
  }

  @override
  void dispose() {
    _userCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0C10),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(32),
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // ── Logo Hermes ────────────────────────────────
                Container(
                  width: 96,
                  height: 96,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [Color(0xFF4A9EFF), Color(0xFF2563EB)],
                    ),
                    borderRadius: BorderRadius.circular(24),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF2563EB).withOpacity(0.4),
                        blurRadius: 24,
                        spreadRadius: 2,
                      ),
                    ],
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(10),
                    child: Image.asset(
                      'assets/icons/hermes.png',
                      color: Colors.white,
                      colorBlendMode: BlendMode.srcIn,
                      fit: BoxFit.contain,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Hermes',
                  style: TextStyle(
                    color: Color(0xFFF8FAFC),
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.5,
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Scorecard de Vendedor',
                  style: TextStyle(
                    color: Color(0xFF94A3B8),
                    fontSize: 14,
                  ),
                ),

                const SizedBox(height: 40),

                // ── Botón huella (si está habilitado) ──────────
                if (_bioDisponible && _bioHabilitado) ...[
                  GestureDetector(
                    onTap: _loading ? null : _loginBiometrico,
                    child: Container(
                      width: 96,
                      height: 96,
                      decoration: BoxDecoration(
                        color: const Color(0xFF2563EB).withOpacity(0.15),
                        borderRadius: BorderRadius.circular(48),
                        border: Border.all(
                          color: const Color(0xFF2563EB),
                          width: 2,
                        ),
                      ),
                      child: const Icon(
                        Icons.fingerprint,
                        color: Color(0xFF2563EB),
                        size: 56,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Ingresar con huella',
                    style: TextStyle(color: Color(0xFFCBD5E1), fontSize: 14),
                  ),
                  const SizedBox(height: 20),
                  const Divider(color: Color(0xFF2D3748)),
                  const SizedBox(height: 12),
                  const Text(
                    'O usar contraseña',
                    style: TextStyle(color: Color(0xFF64748B), fontSize: 12),
                  ),
                  const SizedBox(height: 16),
                ],

                // ── Campo Usuario ──────────────────────────────
                TextFormField(
                  controller: _userCtrl,
                  style: const TextStyle(color: Color(0xFFF8FAFC)),
                  decoration: _inputDecoration('Usuario', Icons.person_outline),
                  textInputAction: TextInputAction.next,
                  autocorrect: false,
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) ? 'Ingresá tu usuario' : null,
                ),

                const SizedBox(height: 16),

                // ── Campo Contraseña ───────────────────────────
                TextFormField(
                  controller: _passCtrl,
                  style: const TextStyle(color: Color(0xFFF8FAFC)),
                  obscureText: _obscurePass,
                  decoration: _inputDecoration(
                    'Contraseña',
                    Icons.lock_outline,
                    suffix: IconButton(
                      icon: Icon(
                        _obscurePass ? Icons.visibility_off : Icons.visibility,
                        color: const Color(0xFF64748B),
                        size: 20,
                      ),
                      onPressed: () =>
                          setState(() => _obscurePass = !_obscurePass),
                    ),
                  ),
                  textInputAction: TextInputAction.done,
                  onFieldSubmitted: (_) => _login(),
                  validator: (v) =>
                      (v == null || v.isEmpty) ? 'Ingresá tu contraseña' : null,
                ),

                const SizedBox(height: 12),

                // ── Mensaje de error ───────────────────────────
                if (_errorMsg.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEF4444).withOpacity(0.12),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: const Color(0xFFEF4444).withOpacity(0.3),
                      ),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.error_outline,
                            color: Color(0xFFEF4444), size: 16),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _errorMsg,
                            style: const TextStyle(
                              color: Color(0xFFEF4444),
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                const SizedBox(height: 24),

                // ── Botón Ingresar ─────────────────────────────
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton(
                    onPressed: _loading ? null : _login,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF2563EB),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      elevation: 0,
                    ),
                    child: _loading
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Text(
                            'Ingresar',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  InputDecoration _inputDecoration(String label, IconData icon, {Widget? suffix}) {
    return InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(color: Color(0xFF64748B)),
      prefixIcon: Icon(icon, color: const Color(0xFF64748B), size: 20),
      suffixIcon: suffix,
      filled: true,
      fillColor: const Color(0xFF1C2333),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: Color(0xFF2D3748)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: Color(0xFF2563EB)),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: Color(0xFFEF4444)),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: Color(0xFFEF4444)),
      ),
    );
  }
}
