import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import '../config/constants.dart';

/// Gestiona el token de acceso al proxy de Edge Functions.
///
/// Flujo:
///   1. Tras un login exitoso (AuthService.login), llamar a
///      `requestNewToken(username, passwordHash)` para obtener un token.
///   2. El token se guarda en flutter_secure_storage.
///   3. Cada llamada a /cronos-chat o /cronos-transcribe lee el token
///      con `getToken()` y lo manda en el header Authorization.
///   4. Si el server responde 401 (token revocado/perdido), forzar
///      re-login (ya manejamos esto desde AuthService).
class AuthTokenService {
  static const _kToken = 'hermes_proxy_token';

  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  /// Cache en memoria — evita ir a SharedPreferences en cada call a Cronos.
  static String? _cached;

  /// Lee el token desde memoria o storage. Null si no hay.
  static Future<String?> getToken() async {
    if (_cached != null) return _cached;
    final saved = await _storage.read(key: _kToken);
    _cached = saved;
    return saved;
  }

  /// Pide un token nuevo al endpoint /auth-token.
  /// Lo guarda en memoria + storage.
  /// Retorna `true` si OK.
  static Future<bool> requestNewToken({
    required String username,
    required String passwordHash,
  }) async {
    try {
      final resp = await http.post(
        Uri.parse('${AppConfig.supabaseFunctionsUrl}/auth-token'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'username': username,
          'password_hash': passwordHash,
        }),
      ).timeout(const Duration(seconds: 12));

      if (resp.statusCode != 200) {
        debugPrint('[AuthTokenService] auth-token failed ${resp.statusCode}: ${resp.body}');
        return false;
      }

      final data = json.decode(resp.body) as Map<String, dynamic>;
      final token = data['token']?.toString();
      if (token == null || token.isEmpty) return false;

      _cached = token;
      await _storage.write(key: _kToken, value: token);
      return true;
    } catch (e) {
      debugPrint('[AuthTokenService] error: $e');
      return false;
    }
  }

  /// Borra el token (en logout o en 401 del proxy).
  static Future<void> clearToken() async {
    _cached = null;
    await _storage.delete(key: _kToken);
  }
}
