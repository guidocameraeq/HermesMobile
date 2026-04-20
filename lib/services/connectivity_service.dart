import 'dart:async';
import 'dart:io';
import '../config/constants.dart';

/// Detecta si SQL Server está alcanzable (VPN activa).
/// Expone un stream para que la UI reaccione al cambio.
class ConnectivityService {
  static final _controller = StreamController<bool>.broadcast();
  static bool _lastKnown = true; // optimismo inicial

  /// Stream que emite true si SQL accesible, false si no.
  static Stream<bool> get onChange => _controller.stream;

  /// Último estado conocido (sin ping nuevo).
  static bool get lastKnown => _lastKnown;

  /// Ping rápido (TCP connect con timeout) — NO usa jTDS.
  /// Actualiza _lastKnown y emite al stream si cambia.
  static Future<bool> ping({Duration timeout = const Duration(seconds: 2)}) async {
    bool result;
    try {
      final socket = await Socket.connect(
        AppConfig.sqlHost,
        int.parse(AppConfig.sqlPort),
        timeout: timeout,
      );
      socket.destroy();
      result = true;
    } catch (_) {
      result = false;
    }
    _notify(result);
    return result;
  }

  /// Marca la conectividad como fallida (ej: cuando una query dió timeout).
  static void markFailed() => _notify(false);

  /// Marca la conectividad como OK (ej: query que devolvió datos).
  static void markOk() => _notify(true);

  static void _notify(bool value) {
    if (value != _lastKnown) {
      _lastKnown = value;
      _controller.add(value);
    } else {
      _lastKnown = value; // no emitir si no cambió
    }
  }
}
