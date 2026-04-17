import 'dart:convert';
import 'package:http/http.dart' as http;
import '../config/constants.dart';
import '../models/cliente.dart';
import '../models/session.dart';
import 'clientes_service.dart';

/// Respuesta parseada del asistente IA.
class AssistantAction {
  final String tipo;        // actividad, consulta, otro
  final String? clienteMatch;
  final String accion;      // llamada, visita, propuesta, reunion, recordatorio, otro
  final String? cuando;     // ISO 8601 datetime
  final String nota;
  final String mensaje;     // respuesta amigable
  final Cliente? clienteResuelto; // después del fuzzy match

  AssistantAction({
    required this.tipo,
    this.clienteMatch,
    required this.accion,
    this.cuando,
    required this.nota,
    required this.mensaje,
    this.clienteResuelto,
  });

  bool get esActividad => tipo == 'actividad';
  bool get tieneCliente => clienteResuelto != null;

  String get cuandoFmt {
    if (cuando == null) return 'Sin fecha';
    final dt = DateTime.tryParse(cuando!);
    if (dt == null) return cuando!;
    return '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year} '
        '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }

  String get accionLabel => switch (accion) {
    'llamada' => 'Llamada',
    'visita' => 'Visita',
    'propuesta' => 'Propuesta',
    'reunion' => 'Reunión',
    'recordatorio' => 'Recordatorio',
    _ => accion,
  };
}

/// Servicio del asistente IA — llama a OpenAI y parsea la respuesta.
class AssistantService {
  static List<Cliente>? _clientesCache;

  /// Carga la cartera de clientes del vendedor (se cachea).
  static Future<List<Cliente>> _getClientes() async {
    _clientesCache ??= await ClientesService.getClientes(
      Session.current.vendedorNombre,
    );
    return _clientesCache!;
  }

  /// Limpia cache (si cambia de vendedor o se quiere refrescar).
  static void clearCache() => _clientesCache = null;

  /// Arma el prompt del sistema con la cartera del vendedor.
  static Future<String> _buildSystemPrompt() async {
    final clientes = await _getClientes();
    final vendedor = Session.current.vendedorNombre;
    final now = DateTime.now();
    final fecha = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';

    // Lista de clientes compacta para el contexto
    final clientesStr = clientes
        .where((c) => c.esActivo)
        .map((c) => '${c.codigo}: ${c.nombre}')
        .join('\n');

    return '''Sos un asistente comercial para vendedores de una empresa de productos químicos y artísticos. Tu trabajo es interpretar mensajes del vendedor y extraer acciones comerciales.

El vendedor se llama: $vendedor
Fecha y hora actual: $fecha ${now.hour}:${now.minute.toString().padLeft(2, '0')}

La cartera de clientes activos del vendedor es:
$clientesStr

INSTRUCCIONES:
1. Cuando el vendedor te dice algo, respondé SIEMPRE con un JSON válido.
2. Si menciona un cliente, poné en "cliente_match" el texto que usó (nombre parcial, apellido, etc.)
3. Interpretá fechas relativas: "mañana" = fecha de mañana, "el lunes" = próximo lunes, "la semana que viene" = etc.
4. Si no entendés algo o falta información, usá tipo "consulta" y preguntá en el mensaje.
5. Sé breve y amigable en el mensaje.

Formato de respuesta (JSON puro, sin markdown, sin backticks):
{"tipo":"actividad","cliente_match":"garcia","accion":"llamada","cuando":"2026-04-18T10:00:00","nota":"ver propuesta","mensaje":"Listo, te agendo llamar a García mañana a las 10."}

Tipos de acción válidos: llamada, visita, propuesta, reunion, recordatorio, otro
Tipos de respuesta: actividad (cuando hay una acción a registrar), consulta (cuando preguntás algo), otro (conversación general)''';
  }

  /// Envía un mensaje al LLM y retorna la acción parseada.
  static Future<AssistantAction> sendMessage(String userMessage) async {
    final systemPrompt = await _buildSystemPrompt();

    final response = await http.post(
      Uri.parse('https://api.openai.com/v1/chat/completions'),
      headers: {
        'Authorization': 'Bearer ${AppConfig.openaiApiKey}',
        'Content-Type': 'application/json',
      },
      body: json.encode({
        'model': AppConfig.openaiModel,
        'messages': [
          {'role': 'system', 'content': systemPrompt},
          {'role': 'user', 'content': userMessage},
        ],
        'temperature': 0.3,
        'max_tokens': 300,
      }),
    ).timeout(const Duration(seconds: 15));

    if (response.statusCode != 200) {
      throw Exception('Error OpenAI: ${response.statusCode} — ${response.body}');
    }

    final data = json.decode(response.body);
    final content = data['choices'][0]['message']['content'] as String;

    // Parsear JSON de la respuesta (puede venir con backticks)
    final jsonStr = content
        .replaceAll('```json', '')
        .replaceAll('```', '')
        .trim();

    try {
      final parsed = json.decode(jsonStr) as Map<String, dynamic>;

      // Fuzzy match del cliente
      Cliente? clienteResuelto;
      final clienteMatch = parsed['cliente_match']?.toString();
      if (clienteMatch != null && clienteMatch.isNotEmpty) {
        clienteResuelto = await _fuzzyMatchCliente(clienteMatch);
      }

      return AssistantAction(
        tipo: parsed['tipo']?.toString() ?? 'otro',
        clienteMatch: clienteMatch,
        accion: parsed['accion']?.toString() ?? 'otro',
        cuando: parsed['cuando']?.toString(),
        nota: parsed['nota']?.toString() ?? '',
        mensaje: parsed['mensaje']?.toString() ?? content,
        clienteResuelto: clienteResuelto,
      );
    } catch (_) {
      // Si no puede parsear JSON, devolver como mensaje conversacional
      return AssistantAction(
        tipo: 'otro',
        accion: 'otro',
        nota: '',
        mensaje: content,
      );
    }
  }

  /// Fuzzy match contra la cartera del vendedor.
  /// Retorna el primer cliente que matchea, o null.
  static Future<Cliente?> _fuzzyMatchCliente(String query) async {
    final clientes = await _getClientes();
    final q = query.toLowerCase().trim();

    // Match exacto por código
    final byCode = clientes.where((c) => c.codigo == q).toList();
    if (byCode.length == 1) return byCode.first;

    // Match por nombre (contains)
    final matches = clientes.where((c) =>
        c.nombre.toLowerCase().contains(q) ||
        q.split(' ').every((word) => c.nombre.toLowerCase().contains(word))
    ).toList();

    if (matches.length == 1) return matches.first;
    if (matches.isNotEmpty) return matches.first; // tomar el primero si hay varios

    return null;
  }

  /// Busca clientes que matchean (para cuando hay ambigüedad).
  static Future<List<Cliente>> buscarClientes(String query) async {
    final clientes = await _getClientes();
    final q = query.toLowerCase().trim();
    return clientes.where((c) =>
        c.nombre.toLowerCase().contains(q) ||
        c.codigo.toLowerCase().contains(q)
    ).take(5).toList();
  }
}
