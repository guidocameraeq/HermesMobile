import 'dart:convert';
import 'package:http/http.dart' as http;
import '../config/constants.dart';
import '../models/cliente.dart';
import '../models/session.dart';
import 'clientes_service.dart';
import 'actividades_service.dart';
import 'visitas_service.dart';
import 'prompt_service.dart';

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
  final String? motivo;   // para visita_ahora
  final List<Cliente>? candidatos; // varios matches — usuario debe elegir

  AssistantAction({
    required this.tipo,
    this.clienteMatch,
    required this.accion,
    this.cuando,
    required this.nota,
    required this.mensaje,
    this.clienteResuelto,
    this.actividadId,
    this.motivo,
    this.candidatos,
  });

  bool get esActividad => tipo == 'actividad';
  bool get esPendiente => tipo == 'pendiente_item';
  bool get esVisitaAhora => tipo == 'visita_ahora';
  bool get esVisitaRegistrada => tipo == 'visita_registrada';
  bool get tieneCliente => clienteResuelto != null;
  bool get necesitaDesambiguacion =>
      clienteResuelto == null && candidatos != null && candidatos!.length > 1;

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
    final hora = '${now.hour}:${now.minute.toString().padLeft(2, '0')}';

    final clientesStr = clientes
        .where((c) => c.esActivo)
        .map((c) => '${c.codigo}: ${c.nombre}')
        .join('\n');

    return PromptService.get('cronos', {
      'vendedor': vendedor,
      'fecha': fecha,
      'dia_semana': diaSemana,
      'hora': hora,
      'clientes': clientesStr,
    });
  }

  /// Transforma filas de visitas (ya hechas, con GPS) en AssistantActions de solo lectura.
  static List<AssistantAction> _rowsToVisitaItems(List<Map<String, dynamic>> items) {
    final out = <AssistantAction>[];
    for (final item in items.take(10)) {
      final cliente = item['cliente_nombre']?.toString() ?? '';
      final codigo = item['cliente_codigo']?.toString() ?? '';
      final motivo = item['motivo']?.toString() ?? '';
      final notas = item['notas']?.toString() ?? '';
      final createdAt = item['created_at']?.toString();

      out.add(AssistantAction(
        tipo: 'visita_registrada',
        accion: 'visita',
        clienteMatch: cliente,
        cuando: createdAt,
        nota: notas,
        mensaje: '',
        motivo: motivo,
        clienteResuelto: cliente.isNotEmpty ? Cliente(
          codigo: codigo, nombre: cliente, categoria: '', situacion: '',
          localidad: '', provincia: '',
        ) : null,
      ));
    }
    return out;
  }

  /// Transforma filas de actividades_cliente en AssistantActions tipo pendiente_item.
  static List<AssistantAction> _rowsToPendienteItems(List<Map<String, dynamic>> items) {
    final out = <AssistantAction>[];
    for (final item in items.take(15)) {
      final id = int.tryParse(item['id']?.toString() ?? '');
      final tipo = item['tipo']?.toString() ?? 'otro';
      final cliente = item['cliente_nombre']?.toString() ?? '';
      final codigo = item['cliente_codigo']?.toString() ?? '';
      final desc = item['descripcion']?.toString() ?? '';
      final fecha = item['fecha_programada']?.toString();

      out.add(AssistantAction(
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
    return out;
  }

  /// Envía un mensaje al LLM con historial completo.
  static Future<AssistantResult> sendMessage(String userMessage) async {
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
        final tipoAccion = map['tipo']?.toString() ?? 'actividad';

        // Consulta de pendientes: app ejecuta la query y expande en tarjetas
        if (tipoAccion == 'consulta_pendientes') {
          final filtroFecha = map['filtro_fecha']?.toString() ?? 'todos';
          final fechaEspecifica = map['fecha_especifica']?.toString();
          final clienteMatchQ = map['cliente_match']?.toString();
          final orden = map['orden']?.toString() ?? 'proxima';
          final limite = int.tryParse(map['limite']?.toString() ?? '15') ?? 15;
          List<Map<String, dynamic>> items;

          if (clienteMatchQ != null && clienteMatchQ.isNotEmpty) {
            final cands = await _fuzzyMatchClientes(clienteMatchQ);
            if (cands.isEmpty) {
              items = [];
            } else if (cands.length == 1) {
              items = await ActividadesService.pendientesPorCliente(cands.first.codigo);
            } else {
              actions.add(AssistantAction(
                tipo: 'consulta_ambigua',
                clienteMatch: clienteMatchQ,
                accion: 'consulta',
                nota: filtroFecha,
                mensaje: '',
                candidatos: cands,
              ));
              continue;
            }
          } else if (fechaEspecifica != null && fechaEspecifica.isNotEmpty) {
            items = await ActividadesService.pendientesFecha(fechaEspecifica);
          } else if (filtroFecha == 'hoy') {
            items = await ActividadesService.pendientesHoy();
          } else if (filtroFecha == 'manana') {
            items = await ActividadesService.pendientesManana();
          } else if (filtroFecha == 'semana') {
            items = await ActividadesService.pendientesSemana();
          } else if (filtroFecha == 'mes') {
            items = await ActividadesService.pendientesMes();
          } else if (filtroFecha == 'vencidas') {
            items = await ActividadesService.pendientesVencidas();
          } else {
            items = await ActividadesService.pendientes();
          }

          // Post-proceso: orden y límite
          if (orden == 'ultima') {
            items = List.of(items);
            items.sort((a, b) {
              final af = a['fecha_programada']?.toString();
              final bf = b['fecha_programada']?.toString();
              if (af == null && bf == null) return 0;
              if (af == null) return 1;
              if (bf == null) return -1;
              return bf.compareTo(af);
            });
          }
          if (limite > 0 && items.length > limite) {
            items = items.take(limite).toList();
          }

          actions.addAll(_rowsToPendienteItems(items));
          continue;
        }

        // Consulta de visitas GPS ya hechas
        if (tipoAccion == 'consulta_visitas') {
          final filtroFecha = map['filtro_fecha']?.toString() ?? 'hoy';
          final clienteMatchQ = map['cliente_match']?.toString();
          List<Map<String, dynamic>> items;

          if (clienteMatchQ != null && clienteMatchQ.isNotEmpty) {
            final cands = await _fuzzyMatchClientes(clienteMatchQ);
            if (cands.length == 1) {
              items = await VisitasService.visitasCliente(cands.first.codigo, limit: 10);
            } else if (cands.length > 1) {
              actions.add(AssistantAction(
                tipo: 'consulta_ambigua',
                clienteMatch: clienteMatchQ,
                accion: 'visitas',
                nota: filtroFecha,
                mensaje: '',
                candidatos: cands,
              ));
              continue;
            } else {
              items = [];
            }
          } else if (filtroFecha == 'hoy') {
            items = await VisitasService.visitasHoy();
          } else if (filtroFecha == 'semana') {
            items = await VisitasService.visitasSemana();
          } else if (filtroFecha == 'mes') {
            items = await VisitasService.visitasMes();
          } else {
            items = await VisitasService.visitasHoy();
          }

          actions.addAll(_rowsToVisitaItems(items));
          continue;
        }

        // Actividad / visita_ahora: resolver cliente con posibles candidatos
        final clienteMatch = map['cliente_match']?.toString();
        Cliente? clienteResuelto;
        List<Cliente>? candidatos;
        if (clienteMatch != null && clienteMatch.isNotEmpty) {
          final cands = await _fuzzyMatchClientes(clienteMatch);
          if (cands.length == 1) {
            clienteResuelto = cands.first;
          } else if (cands.length > 1) {
            candidatos = cands;
          }
        }

        actions.add(AssistantAction(
          tipo: tipoAccion,
          clienteMatch: clienteMatch,
          accion: map['accion']?.toString() ?? (tipoAccion == 'visita_ahora' ? 'visita' : 'otro'),
          cuando: map['cuando']?.toString(),
          nota: map['nota']?.toString() ?? '',
          mensaje: mensaje,
          clienteResuelto: clienteResuelto,
          motivo: map['motivo']?.toString(),
          candidatos: candidatos,
        ));
      }

      return AssistantResult(mensaje: mensaje, actions: actions);
    } catch (_) {
      return AssistantResult(mensaje: content, actions: []);
    }
  }

  /// Resuelve un cliente_match contra la cartera. Retorna todos los candidatos
  /// que coincidan — la UI muestra opciones si hay más de uno.
  static Future<List<Cliente>> _fuzzyMatchClientes(String query) async {
    final clientes = await _getClientes();
    final q = query.toLowerCase().trim();

    // 1. Match exacto por código
    final byCode = clientes.where((c) => c.codigo == q).toList();
    if (byCode.length == 1) return byCode;

    // 2. Match por contención en nombre
    final matches = clientes.where((c) =>
        c.nombre.toLowerCase().contains(q) ||
        q.split(' ').every((word) => c.nombre.toLowerCase().contains(word))
    ).toList();

    return matches;
  }

  /// Ejecuta el núcleo de una consulta_pendientes una vez resuelto el cliente
  /// (usado cuando el usuario elige entre candidatos ambiguos).
  static Future<List<AssistantAction>> consultaPendientesResuelta(
      Cliente cliente) async {
    final items = await ActividadesService.pendientesPorCliente(cliente.codigo);
    return _rowsToPendienteItems(items);
  }
}
