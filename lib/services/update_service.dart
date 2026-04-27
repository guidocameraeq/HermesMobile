import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:open_filex/open_filex.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'pg_service.dart';

/// Info de una release disponible en GitHub.
class ReleaseInfo {
  final String tagName;     // "v1.3.0"
  final String name;        // "v1.3.0 - Título"
  final String body;        // Release notes markdown
  final String apkUrl;      // URL directa al .apk
  final int apkSize;        // Bytes

  const ReleaseInfo({
    required this.tagName,
    required this.name,
    required this.body,
    required this.apkUrl,
    required this.apkSize,
  });
}

/// Sistema de auto-actualización via GitHub Releases.
class UpdateService {
  static const _repo = 'guidocameraeq/HermesMobile';

  /// Compara la versión local con la última release de GitHub.
  /// Retorna ReleaseInfo si hay update, null si estamos al día.
  static Future<ReleaseInfo?> checkForUpdate() async {
    try {
      final packageInfo = await PackageInfo.fromPlatform();
      final currentVersion = packageInfo.version; // "1.2.2"

      final response = await http.get(
        Uri.parse('https://api.github.com/repos/$_repo/releases/latest'),
        headers: {'Accept': 'application/vnd.github.v3+json'},
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode != 200) return null;

      final data = json.decode(response.body) as Map<String, dynamic>;
      final tagName = data['tag_name']?.toString() ?? '';
      final remoteVersion = tagName.replaceFirst('v', '');

      if (!_isNewer(remoteVersion, currentVersion)) return null;

      // Buscar el asset .apk
      final assets = data['assets'] as List? ?? [];
      final apkAsset = assets.firstWhere(
        (a) => (a['name']?.toString() ?? '').endsWith('.apk'),
        orElse: () => null,
      );
      if (apkAsset == null) return null;

      return ReleaseInfo(
        tagName: tagName,
        name: data['name']?.toString() ?? tagName,
        body: data['body']?.toString() ?? '',
        apkUrl: apkAsset['browser_download_url']?.toString() ?? '',
        apkSize: apkAsset['size'] as int? ?? 0,
      );
    } catch (_) {
      return null;
    }
  }

  /// Descarga el APK y abre el instalador de Android.
  /// [onProgress] recibe 0.0–1.0 con el progreso de descarga.
  static Future<bool> downloadAndInstall(
    ReleaseInfo release, {
    void Function(double progress)? onProgress,
  }) async {
    try {
      final dir = await getTemporaryDirectory();
      final filePath = '${dir.path}/hermes_update.apk';
      final file = File(filePath);

      // Descargar con progreso
      final request = http.Request('GET', Uri.parse(release.apkUrl));
      final streamedResponse = await request.send().timeout(
        const Duration(minutes: 5),
      );

      final totalBytes = streamedResponse.contentLength ?? release.apkSize;
      int receivedBytes = 0;
      final sink = file.openWrite();

      await for (final chunk in streamedResponse.stream) {
        sink.add(chunk);
        receivedBytes += chunk.length;
        if (totalBytes > 0) {
          onProgress?.call(receivedBytes / totalBytes);
        }
      }
      await sink.close();

      // Abrir el instalador de Android
      final result = await OpenFilex.open(filePath);
      return result.type == ResultType.done;
    } catch (_) {
      return false;
    }
  }

  /// Compara dos versiones semver: retorna true si remote > current.
  static bool _isNewer(String remote, String current) {
    final r = remote.split('.').map((s) => int.tryParse(s) ?? 0).toList();
    final c = current.split('.').map((s) => int.tryParse(s) ?? 0).toList();
    while (r.length < 3) r.add(0);
    while (c.length < 3) c.add(0);
    for (int i = 0; i < 3; i++) {
      if (r[i] > c[i]) return true;
      if (r[i] < c[i]) return false;
    }
    return false;
  }

  /// Versión actual del app.
  static Future<String> currentVersion() async {
    final info = await PackageInfo.fromPlatform();
    return info.version;
  }

  // ── Force update (mecanismo remoto via Supabase app_config) ──────────
  static const _kCacheMinVersion = 'force_update_min_version_cached';

  /// Lee `min_version_required` de Supabase. Si no se puede contactar,
  /// usa el último valor cacheado en SharedPreferences.
  /// Retorna `null` si no se pudo determinar (sin red + sin cache).
  static Future<String?> _fetchMinVersion() async {
    try {
      final rows = await PgService.query(
        "SELECT value FROM app_config WHERE key = 'min_version_required' LIMIT 1",
        const {},
      );
      final remote = rows.firstOrNull?['value']?.toString();
      if (remote != null && remote.isNotEmpty) {
        // Cachear para próximas veces (incl. modo offline)
        try {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString(_kCacheMinVersion, remote);
        } catch (_) {}
        return remote;
      }
    } catch (e) {
      debugPrint('[UpdateService] fetchMinVersion fail, using cache: $e');
    }

    // Fallback: último valor conocido
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(_kCacheMinVersion);
    } catch (_) {
      return null;
    }
  }

  /// Devuelve el ReleaseInfo si hace falta forzar update, null si no.
  ///
  /// Lógica:
  ///   1. Lee `min_version_required` de Supabase (con fallback a cache).
  ///   2. Si versión local >= min → no forzamos, retorna null.
  ///   3. Si local < min → busca el ReleaseInfo más reciente para que
  ///      el ForceUpdateScreen lo tenga listo.
  ///   4. Si no hay red ni cache → null (no bloqueamos sin información).
  static Future<ReleaseInfo?> checkForceUpdate() async {
    final minRequired = await _fetchMinVersion();
    if (minRequired == null) return null;

    final pkg = await PackageInfo.fromPlatform();
    final localVersion = pkg.version;

    if (!_isNewer(minRequired, localVersion)) return null;

    // Hace falta forzar — traemos el release más reciente para descarga
    return checkForUpdate();
  }

  // ── Pre-download en background (mejora UX de updates soft) ────────────
  static const _kPredownloadedTag = 'predownloaded_tag';
  static const _kPredownloadedPath = 'predownloaded_path';

  /// Devuelve la ruta del APK ya descargado para esta release, o null.
  static Future<String?> getPredownloadedApk(String tagName) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cachedTag = prefs.getString(_kPredownloadedTag);
      final cachedPath = prefs.getString(_kPredownloadedPath);
      if (cachedTag != tagName || cachedPath == null) return null;
      final f = File(cachedPath);
      if (!await f.exists()) return null;
      return cachedPath;
    } catch (_) {
      return null;
    }
  }

  /// Descarga el APK en background SIN abrir el instalador. Idempotente:
  /// si el APK de esa release ya está en cache, no hace nada.
  /// Llamarlo después del login con `unawaited(...)` — no bloquea UI.
  static Future<void> predownload(ReleaseInfo release) async {
    try {
      final existing = await getPredownloadedApk(release.tagName);
      if (existing != null) return;

      final dir = await getTemporaryDirectory();
      final filePath = '${dir.path}/hermes_${release.tagName}.apk';
      final file = File(filePath);

      final request = http.Request('GET', Uri.parse(release.apkUrl));
      final streamedResponse =
          await request.send().timeout(const Duration(minutes: 5));
      final sink = file.openWrite();
      await streamedResponse.stream.pipe(sink);

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kPredownloadedTag, release.tagName);
      await prefs.setString(_kPredownloadedPath, filePath);
      debugPrint('[UpdateService] predownload OK: ${release.tagName}');
    } catch (e) {
      debugPrint('[UpdateService] predownload fail: $e');
    }
  }

  /// Si ya está pre-descargado, abre el instalador directo.
  /// Si no, hace `downloadAndInstall` normal.
  static Future<bool> installOrDownload(
    ReleaseInfo release, {
    void Function(double)? onProgress,
  }) async {
    final predownloaded = await getPredownloadedApk(release.tagName);
    if (predownloaded != null) {
      onProgress?.call(1.0);
      final result = await OpenFilex.open(predownloaded);
      return result.type == ResultType.done;
    }
    return downloadAndInstall(release, onProgress: onProgress);
  }
}
