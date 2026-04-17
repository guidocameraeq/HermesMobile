import 'dart:convert';
import 'package:http/http.dart' as http;
import '../config/constants.dart';
import '../models/cliente.dart';
import '../models/session.dart';
import 'clientes_service.dart';
import 'actividades_service.dart';

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

    return '''Sos Cronos, el asistente de agenda del vendedor. SOLO podés hacer 3 cosas:
1. AGENDAR actividades y recordatorios ("recordame llamar a García mañana")
2. LISTAR pendientes ("qué tengo pendiente")
3. MARCAR como completada ("ya llamé a García")

Para CUALQUIER otra cosa (preguntas, conversación, chistes, consultas de datos), respondé:
{"tipo":"rechazo","accion":"otro","nota":"","mensaje":"Soy Cronos y solo puedo ayudarte con actividades y recordatorios. Decime qué tenés que hacer y te lo anoto."}

El vendedor se llama: $vendedor
Fecha y hora actual: $fecha ${now.hour}:${now.minute.toString().padLeft(2, '0')}

Cartera de clientes del vendedor:
$clientesStr

REGLAS:
- Respondé SIEMPRE con JSON puro (sin backticks, sin markdown).
- Si menciona un cliente, poné en "cliente_match" el texto que usó.
- Interpretá fechas: "mañana" = fecha de mañana, "el lunes" = próximo lunes, etc.
- Si falta info (ej: no dijo a qué cliente), preguntá con tipo "consulta".
- Sé breve y amigable.

Formato JSON:
{"tipo":"actividad","cliente_match":"garcia","accion":"llamada","cuando":"2026-04-18T10:00:00","nota":"ver propuesta","mensaje":"Listo, te agendo llamar a García mañana a las 10."}

Tipos de acción: llamada, visita, propuesta, presentacion, reunion, recordatorio
Tipos de respuesta: actividad, consulta, pendientes, completar, rechazo''';
  }

  /// Detecta consultas de pendientes y las resuelve sin LLM.
  static Future<AssistantAction?> _checkPendientes(String msg) async {
    final q = msg.toLowerCase();
    final esPendientes = q.contains('pendiente') || q.contains('tengo que hacer') ||
        q.contains('mi agenda') || q.contains('qué tengo') || q.contains('que tengo') ||
        q.contains('mis actividades') || q.contains('tareas');

    if (!esPendientes) return null;

    final items = await ActividadesService.pendientes();
    if (items.isEmpty) {
      return AssistantAction(
        tipo: 'pendientes', accion: 'otro', nota: '',
        mensaje: 'No tenés actividades pendientes. Todo al día.',
      );
    }

    final buf = StringBuffer('Tenés ${items.length} actividades pendientes:\n\n');
    for (final item in items.take(10)) {
      final tipo = item['tipo']?.toString() ?? '';
      final cliente = item['cliente_nombre']?.toString() ?? '';
      final desc = item['descripcion']?.toString() ?? '';
      final fecha = item['fecha_programada'];
      String fechaStr = '';
      if (fecha != null) {
        final dt = fecha is DateTime ? fecha : DateTime.tryParse(fecha.toString());
        if (dt != null) {
          final now = DateTime.now();
          final diff = dt.difference(now);
          if (diff.inDays == 0) fechaStr = ' (hoy ${dt.hour}:${dt.minute.toString().padLeft(2, '0')})';
          else if (diff.inDays == 1) fechaStr = ' (mañana ${dt.hour}:${dt.minute.toString().padLeft(2, '0')})';
          else fechaStr = ' (${dt.day}/${dt.month})';
        }
      }
      buf.write('• ${tipo[0].toUpperCase()}${tipo.substring(1)}$fechaStr');
      if (cliente.isNotEmpty) buf.write(' — $cliente');
      if (desc.isNotEmpty) buf.write(': $desc');
      buf.write('\n');
    }

    return AssistantAction(
      tipo: 'pendientes', accion: 'otro', nota: '',
      mensaje: buf.toString().trim(),
    );
  }

  /// Envía un mensaje al LLM y retorna la acción parseada.
  static Future<AssistantAction> sendMessage(String userMessage) async {
    // Detección pre-LLM: consulta de pendientes (no necesita IA)
    final pendientesResult = await _checkPendientes(userMessage);
    if (pendientesResult != null) return pendientesResult;

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
