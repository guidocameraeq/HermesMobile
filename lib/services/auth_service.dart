import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'pg_service.dart';
import 'auth_token_service.dart';
import '../models/session.dart';

class AuthService {
  /// Hashea la contraseña con SHA-256 (igual que el desktop Python).
  static String hashPassword(String password) {
    final bytes = utf8.encode(password);
    return sha256.convert(bytes).toString();
  }

  /// Autentica al usuario contra Supabase.
  /// Si OK, puebla Session.current y retorna true.
  /// Si falla, retorna false con [errorMsg].
  static Future<({bool ok, String errorMsg})> login(
    String username,
    String password,
  ) async {
    if (username.trim().isEmpty || password.isEmpty) {
      return (ok: false, errorMsg: 'Ingresá usuario y contraseña.');
    }

    try {
      final hash = hashPassword(password);
      final auth = await PgService.verifyUser(username, hash);

      if (auth == null) {
        return (ok: false, errorMsg: 'Usuario o contraseña incorrectos.');
      }

      // Gate 1: el rol debe tener mobile.access habilitado.
      final permisos = auth.permisos;
      if (permisos['mobile.access'] != true) {
        return (
          ok: false,
          errorMsg: 'Tu rol no tiene acceso a Hermes Mobile.\nContactá al administrador.',
        );
      }

      // Gate 2: debe haber un vendedor asignado.
      // Fallback al username durante la transición (usuarios viejos sin vendedor_nombre).
      final vnDb = auth.vendedorNombre?.trim();
      final vendedorEfectivo = (vnDb != null && vnDb.isNotEmpty)
          ? vnDb
          : username.trim();

      if (vendedorEfectivo.isEmpty) {
        return (
          ok: false,
          errorMsg: 'Tu usuario no tiene un vendedor asignado.\nContactá al administrador.',
        );
      }

      Session.current.set(
        username: username.trim(),
        vendedorNombre: vendedorEfectivo,
        role: auth.role,
        permisos: permisos,
      );

      // Pedir un token de proxy al server. Si falla, no rompemos el login —
      // Cronos no funciona pero el resto de la app sí. El user re-loguea
      // cuando vuelva conectividad y se reintenta.
      await AuthTokenService.requestNewToken(
        username: username.trim(),
        passwordHash: hash,
      );

      return (ok: true, errorMsg: '');
    } catch (e) {
      return (
        ok: false,
        errorMsg: 'Error de conexión con Supabase.\n${e.toString()}',
      );
    }
  }

  static Future<void> logout() async {
    Session.current.clear();
    await AuthTokenService.clearToken();
  }
}
