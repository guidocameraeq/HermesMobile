import 'dart:async';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import '../config/constants.dart';
import 'auth_token_service.dart';

/// Graba audio y transcribe con Whisper API de OpenAI.
/// Reemplaza a speech_to_text (local) por mejor calidad en español AR.
class WhisperService {
  static final _recorder = AudioRecorder();
  static String? _currentPath;
  static DateTime? _startTime;

  /// ¿Permiso de micrófono disponible?
  static Future<bool> hasPermission() => _recorder.hasPermission();

  /// ¿Está grabando ahora mismo?
  static Future<bool> isRecording() => _recorder.isRecording();

  /// Stream de amplitud (0-1 aproximado) para animar la onda sonora.
  static Stream<double> amplitudeStream({
    Duration interval = const Duration(milliseconds: 120),
  }) async* {
    while (await _recorder.isRecording()) {
      final a = await _recorder.getAmplitude();
      // amplitude viene en dBFS (0 = máximo, -60+ = silencio). Normalizo 0-1.
      final db = a.current;
      final norm = ((db + 45) / 45).clamp(0.0, 1.0);
      yield norm;
      await Future.delayed(interval);
    }
  }

  /// Inicia grabación a archivo temporal m4a.
  static Future<void> start() async {
    if (await _recorder.isRecording()) return;
    final dir = await getTemporaryDirectory();
    final path = '${dir.path}/cronos_${DateTime.now().millisecondsSinceEpoch}.m4a';
    _currentPath = path;
    _startTime = DateTime.now();
    await _recorder.start(
      const RecordConfig(
        encoder: AudioEncoder.aacLc,
        sampleRate: 16000,
        numChannels: 1,
        bitRate: 64000,
      ),
      path: path,
    );
  }

  /// Duración transcurrida desde que inició la grabación (live).
  static Duration get elapsed =>
      _startTime == null ? Duration.zero : DateTime.now().difference(_startTime!);

  /// Detiene y devuelve el path al archivo (o null si hubo error).
  static Future<String?> stop() async {
    final path = await _recorder.stop();
    _startTime = null;
    return path ?? _currentPath;
  }

  /// Cancela grabación y borra archivo.
  static Future<void> cancel() async {
    if (await _recorder.isRecording()) {
      await _recorder.stop();
    }
    _startTime = null;
    if (_currentPath != null) {
      final f = File(_currentPath!);
      if (await f.exists()) await f.delete();
    }
    _currentPath = null;
  }

  /// Envía el audio a Whisper API y retorna la transcripción.
  /// Lanza excepción si falla.
  static Future<String> transcribe(String audioPath) async {
    final file = File(audioPath);
    if (!await file.exists()) {
      throw Exception('Archivo de audio no encontrado');
    }

    final token = await AuthTokenService.getToken();
    if (token == null || token.isEmpty) {
      throw Exception('Sesión expirada. Volvé a iniciar sesión.');
    }

    final uri = Uri.parse('${AppConfig.supabaseFunctionsUrl}/cronos-transcribe');
    final req = http.MultipartRequest('POST', uri);
    req.headers['Authorization'] = 'Bearer $token';
    // model lo fuerza el server a whisper-1 — no le creemos al cliente.
    req.fields['language'] = 'es';
    req.fields['response_format'] = 'text';
    // Prompt sutil para orientar el modelo al dominio comercial argentino
    req.fields['prompt'] =
        'Conversación comercial en español argentino. Nombres de clientes y acciones como llamar, visitar, agendar, reunión, propuesta, recordatorio.';
    req.files.add(await http.MultipartFile.fromPath('file', audioPath));

    final resp = await req.send().timeout(const Duration(seconds: 60));
    final body = await resp.stream.bytesToString();

    // Limpieza: borrar el archivo después de transcribir
    try {
      await file.delete();
    } catch (_) {}

    if (resp.statusCode == 401) {
      await AuthTokenService.clearToken();
      throw Exception('Sesión expirada. Volvé a iniciar sesión.');
    }
    if (resp.statusCode == 429) {
      throw Exception('Demasiadas grabaciones seguidas. Esperá un momento.');
    }
    if (resp.statusCode != 200) {
      throw Exception('Error transcribiendo (${resp.statusCode})');
    }

    return body.trim();
  }
}
