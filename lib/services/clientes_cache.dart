import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/cliente.dart';

/// Cache persistente de la lista de clientes del vendedor.
/// Usa SharedPreferences (no sensible, se lee instantáneo).
/// Key por vendedor para evitar mezcla entre logins.
class ClientesCache {
  static String _keyData(String vendedor) => 'clientes_cache_${vendedor.toLowerCase()}';
  static String _keyTs(String vendedor)   => 'clientes_cache_ts_${vendedor.toLowerCase()}';

  /// Persiste la lista con timestamp.
  static Future<void> save(String vendedor, List<Cliente> clientes) async {
    if (vendedor.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    final json = jsonEncode(clientes.map((c) => c.toJson()).toList());
    await prefs.setString(_keyData(vendedor), json);
    await prefs.setString(_keyTs(vendedor), DateTime.now().toIso8601String());
  }

  /// Carga la lista cacheada (null si no hay).
  static Future<List<Cliente>?> load(String vendedor) async {
    if (vendedor.isEmpty) return null;
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_keyData(vendedor));
    if (raw == null) return null;
    try {
      final list = jsonDecode(raw) as List;
      return list.map((j) => Cliente.fromJson(j as Map<String, dynamic>)).toList();
    } catch (_) {
      return null;
    }
  }

  /// Timestamp de la última vez que se guardó cache (null si nunca).
  static Future<DateTime?> lastUpdate(String vendedor) async {
    if (vendedor.isEmpty) return null;
    final prefs = await SharedPreferences.getInstance();
    final iso = prefs.getString(_keyTs(vendedor));
    return iso == null ? null : DateTime.tryParse(iso);
  }

  /// Etiqueta legible de antigüedad ("hace 2 días", "hace 1h").
  static String ageLabel(DateTime? ts) {
    if (ts == null) return 'sin cache';
    final diff = DateTime.now().difference(ts);
    if (diff.inMinutes < 2) return 'recién actualizado';
    if (diff.inMinutes < 60) return 'hace ${diff.inMinutes} min';
    if (diff.inHours < 24) return 'hace ${diff.inHours}h';
    if (diff.inDays == 1) return 'ayer';
    return 'hace ${diff.inDays} días';
  }

  /// ¿El cache es considerado "viejo"? (más de 7 días)
  static bool isStale(DateTime? ts) {
    if (ts == null) return true;
    return DateTime.now().difference(ts).inDays > 7;
  }

  /// Borra el cache (al cerrar sesión por ejemplo).
  static Future<void> clear(String vendedor) async {
    if (vendedor.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyData(vendedor));
    await prefs.remove(_keyTs(vendedor));
  }
}
