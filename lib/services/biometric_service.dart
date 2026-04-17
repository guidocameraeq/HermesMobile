import 'package:local_auth/local_auth.dart';
import 'package:local_auth_android/local_auth_android.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Servicio de login biométrico (huella) + almacenamiento seguro de credenciales.
class BiometricService {
  static final _auth = LocalAuthentication();
  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  static const _kUser = 'hermes_saved_user';
  static const _kPass = 'hermes_saved_pass';
  static const _kEnabled = 'hermes_biometric_enabled';

  /// ¿El dispositivo tiene biometría (huella/cara) configurada?
  static Future<bool> disponible() async {
    try {
      final supported = await _auth.isDeviceSupported();
      if (!supported) return false;
      final can = await _auth.canCheckBiometrics;
      if (!can) return false;
      final biometrics = await _auth.getAvailableBiometrics();
      return biometrics.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  /// Pide huella digital. Retorna true si autenticó correctamente.
  static Future<bool> autenticar({
    String motivo = 'Autenticate para ingresar a Hermes',
  }) async {
    try {
      return await _auth.authenticate(
        localizedReason: motivo,
        authMessages: const [
          AndroidAuthMessages(
            signInTitle: 'Hermes',
            cancelButton: 'Cancelar',
            biometricHint: '',
            biometricNotRecognized: 'Huella no reconocida',
            biometricRequiredTitle: 'Huella requerida',
          ),
        ],
        options: const AuthenticationOptions(
          biometricOnly: true,
          stickyAuth: true,
        ),
      );
    } catch (_) {
      return false;
    }
  }

  /// Guarda credenciales y habilita biometría.
  static Future<void> habilitar(String username, String password) async {
    await _storage.write(key: _kUser, value: username);
    await _storage.write(key: _kPass, value: password);
    await _storage.write(key: _kEnabled, value: '1');
  }

  /// Deshabilita biometría y borra credenciales.
  static Future<void> deshabilitar() async {
    await _storage.delete(key: _kUser);
    await _storage.delete(key: _kPass);
    await _storage.delete(key: _kEnabled);
  }

  /// ¿Está habilitado el login biométrico para esta app?
  static Future<bool> habilitado() async {
    final v = await _storage.read(key: _kEnabled);
    return v == '1';
  }

  /// Lee las credenciales guardadas. Retorna null si no hay.
  static Future<({String username, String password})?> leerCredenciales() async {
    final u = await _storage.read(key: _kUser);
    final p = await _storage.read(key: _kPass);
    if (u == null || p == null) return null;
    return (username: u, password: p);
  }
}
