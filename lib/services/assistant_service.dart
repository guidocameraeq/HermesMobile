import 'dart:convert';
import 'package:http/http.dart' as http;
import '../config/constants.dart';
import '../models/cliente.dart';
import '../models/session.dart';
import 'clientes_service.dart';
import 'actividades_service.dart';

/// Respuesta parseada del asistente IA.
class AssistantAction {
  final String tipo;
  final String? clienteMatch;
  final String accion;
  final String? cuando;
  final String nota;
  final String mensaje;
  final Cliente? clienteResuelto;
  final int? actividadId; // para completar desde pendientes

  AssistantAction({
    required this.tipo,
    this.clienteMatch,
    required this.accion,
    this.cuando,
    required this.nota,
    required this.mensaje,
    this.clienteResuelto,
    this.actividadId,
  });

  bool get esActividad => tipo == 'actividad';
  bool get esPendiente => tipo == 'pendiente_item';
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
    'presentacion' => 'Presentación',
    'reunion' => 'Reunión',
    'recordatorio' => 'Recordatorio',
    _ => accion,
  };
}

/// Resultado que puede contener 1 o más acciones.
class AssistantResult {
  final String mensaje;
  final List<AssistantAction> actions;

  AssistantResult({required this.mensaje, required this.actions});

  bool get tieneAcciones => actions.isNotEmpty;
}

/// Servicio del asistente IA — con historial de conversación.
class AssistantService {
  static List<Cliente>? _clientesCache;

  // Historial de conversación (se mantiene mientras la pantalla está abierta)
  static final List<Map<String, String>> _historial = [];

  static Future<List<Cliente>> _getClientes() async {
    _clientesCache ??= await ClientesService.getClientes(
      Session.current.vendedorNombre,
    );
    return _clientesCache!;
  }

  static void clearCache() => _clientesCache = null;

  /// Limpia el historial (al abrir la pantalla de nuevo).
  static void resetConversation() => _historial.clear();

  static Future<String> _buildSystemPrompt() async {
    final clientes = await _getClientes();
    final vendedor = Session.current.vendedorNombre;
    final now = DateTime.now();
    final fecha = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    final diaSemana = ['Lunes','Martes','Miércoles','Jueves','Viernes','Sábado','Domingo'][now.weekday - 1];

    final clientesStr = clientes
        .where((c) => c.esActivo)
        .map((c) => '${c.codigo}: ${c.nombre}')
        .join('\n');

    return '''Sos Cronos, el asistente de agenda del vendedor. SOLO podés hacer estas cosas:
1. AGENDAR actividades y recordatorios
2. MARCAR como completada ("ya llamé a García")

Para CUALQUIER otra cosa, respondé:
{"acciones":[],"mensaje":"Soy Cronos y solo puedo ayudarte con actividades y recordatorios."}

El vendedor se llama: $vendedor
Hoy es: $diaSemana $fecha ${now.hour}:${now.minute.toString().padLeft(2, '0')}

Cartera de clientes:
$clientesStr

REGLAS CRÍTICAS:
1. Respondé SIEMPRE con JSON puro (sin backticks, sin markdown).
2. Usá el campo "acciones" como ARRAY — puede tener 0, 1 o más acciones.
3. Si el vendedor pide agendar MÚLTIPLES actividades, creá UNA acción por cada una en el array.
4. Interpretá fechas: "mañana" = día siguiente, "el sábado" = próximo sábado, "los próximos 2 sábados" = 2 fechas.
5. Si falta info (cliente, hora), preguntá con acciones vacías.
6. Recordá el contexto de la conversación — si ya se mencionó un cliente, no lo vuelvas a pedir.

Formato JSON (SIEMPRE este formato):
{"acciones":[{"cliente_match":"garcia","accion":"llamada","cuando":"2026-04-18T16:00:00","nota":"ver propuesta"}],"mensaje":"Listo, te agendé la llamada."}

Ejemplo con múltiples:
{"acciones":[{"cliente_match":"garcia","accion":"llamada","cuando":"2026-04-19T16:00:00","nota":"seguimiento"},{"cliente_match":"garcia","accion":"llamada","cuando":"2026-04-26T16:00:00","nota":"seguimiento"}],"mensaje":"Te agendé 2 llamadas a García: sábado 19 y sábado 26."}

Ejemplo preguntando info faltante:
{"acciones":[],"mensaje":"¿A qué hora querés agendar la llamada?"}

Tipos de acción: llamada, visita, propuesta, presentacion, reunion, recordatorio''';
  }

  /// Detecta consultas de pendientes — devuelve resultado con tarjetas.
  static Future<AssistantResult?> _checkPendientes(String msg) async {
    final q = msg.toLowerCase();
    final esPendientes = q.contains('pendiente') || q.contains('tengo que hacer') ||
        q.contains('mi agenda') || q.contains('qué tengo') || q.contains('que tengo') ||
        q.contains('mis actividades') || q.contains('tareas');

    if (!esPendientes) return null;

    final items = await ActividadesService.pendientes();
    if (items.isEmpty) {
      return AssistantResult(
        mensaje: 'No tenés actividades pendientes. Todo al día.',
        actions: [],
      );
    }

    // Crear una tarjeta por cada actividad pendiente
    final actions = <AssistantAction>[];
    for (final item in items.take(10)) {
      final id = int.tryParse(item['id']?.toString() ?? '');
      final tipo = item['tipo']?.toString() ?? 'otro';
      final cliente = item['cliente_nombre']?.toString() ?? '';
      final codigo = item['cliente_codigo']?.toString() ?? '';
      final desc = item['descripcion']?.toString() ?? '';
      final fecha = item['fecha_programada']?.toString();

      actions.add(AssistantAction(
        tipo: 'pendiente_item',
        accion: tipo,
        clienteMatch: cliente,
        cuando: fecha,
        nota: desc,
        mensaje: '',
        actividadId: id,
        clienteResuelto: cliente.isNotEmpty ? Cliente(
          codigo: codigo, nombre: cliente, categoria: '', situacion: '',
          localidad: '', provincia: '',
        ) : null,
      ));
    }

    return AssistantResult(
      mensaje: 'Tenés ${items.length} actividades pendientes:',
      actions: actions,
    );
  }

  /// Envía un mensaje al LLM con historial completo.
  static Future<AssistantResult> sendMessage(String userMessage) async {
    // Detección pre-LLM: pendientes
    final pendientesResult = await _checkPendientes(userMessage);
    if (pendientesResult != null) return pendientesResult;

    // Agregar mensaje del usuario al historial
    _historial.add({'role': 'user', 'content': userMessage});

    final systemPrompt = await _buildSystemPrompt();

    // Armar mensajes con historial completo
    final messages = <Map<String, String>>[
      {'role': 'system', 'content': systemPrompt},
      ..._historial,
    ];

    final response = await http.post(
      Uri.parse('https://api.openai.com/v1/chat/completions'),
      headers: {
        'Authorization': 'Bearer ${AppConfig.openaiApiKey}',
        'Content-Type': 'application/json',
      },
      body: json.encode({
        'model': AppConfig.openaiModel,
        'messages': messages,
        'temperature': 0.3,
        'max_tokens': 500,
      }),
    ).timeout(const Duration(seconds: 15));

    if (response.statusCode != 200) {
      throw Exception('Error OpenAI: ${response.statusCode}');
    }

    final data = json.decode(response.body);
    final content = data['choices'][0]['message']['content'] as String;

    // Guardar respuesta en historial
    _historial.add({'role': 'assistant', 'content': content});

    // Parsear JSON
    final jsonStr = content
        .replaceAll('```json', '').replaceAll('```', '').trim();

    try {
      final parsed = json.decode(jsonStr) as Map<String, dynamic>;
      final mensaje = parsed['mensaje']?.toString() ?? content;
      final accionesList = parsed['acciones'] as List? ?? [];

      final actions = <AssistantAction>[];
      for (final a in accionesList) {
        final map = a as Map<String, dynamic>;
        final clienteMatch = map['cliente_match']?.toString();
        Cliente? clienteResuelto;
        if (clienteMatch != null && clienteMatch.isNotEmpty) {
          clienteResuelto = await _fuzzyMatchCliente(clienteMatch);
        }

        actions.add(AssistantAction(
          tipo: 'actividad',
          clienteMatch: clienteMatch,
          accion: map['accion']?.toString() ?? 'otro',
          cuando: map['cuando']?.toString(),
          nota: map['nota']?.toString() ?? '',
          mensaje: mensaje,
          clienteResuelto: clienteResuelto,
        ));
      }

      return AssistantResult(mensaje: mensaje, actions: actions);
    } catch (_) {
      return AssistantResult(mensaje: content, actions: []);
    }
  }

  static Future<Cliente?> _fuzzyMatchCliente(String query) async {
    final clientes = await _getClientes();
    final q = query.toLowerCase().trim();

    final byCode = clientes.where((c) => c.codigo == q).toList();
    if (byCode.length == 1) return byCode.first;

    final matches = clientes.where((c) =>
        c.nombre.toLowerCase().contains(q) ||
        q.split(' ').every((word) => c.nombre.toLowerCase().contains(word))
    ).toList();

    if (matches.length == 1) return matches.first;
    if (matches.isNotEmpty) return matches.first;
    return null;
  }
}
