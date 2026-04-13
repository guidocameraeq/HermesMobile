import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:open_filex/open_filex.dart';

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
}
