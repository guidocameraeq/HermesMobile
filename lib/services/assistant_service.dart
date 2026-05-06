import 'dart:convert';
import 'package:http/http.dart' as http;
import '../config/constants.dart';
import '../models/cliente.dart';
import '../models/session.dart';
import 'clientes_service.dart';
import 'actividades_service.dart';
import 'visitas_service.dart';
import 'prompt_service.dart';
import 'cronos_logger.dart';
import 'auth_token_service.dart';

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
  final bool completable; // pendiente_item con botón "Completar" directo

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
    this.completable = false,
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

/// Acciones rápidas — chips fijos de la pantalla de bienvenida que
/// bypasean al LLM. Cada una corre una query directa contra la DB.
/// Latencia <300ms, sin costo de tokens, 100% determinístico.
enum QuickAction {
  pendientesHoy,
  pendientesManana,
  pendientesSemana,
  pendientesVencidas,
  visitasHoy,
  proximaTarea,
}

extension QuickActionInfo on QuickAction {
  /// Texto que se muestra en el chip Y como mensaje del usuario en el chat.
  String get label => switch (this) {
    QuickAction.pendientesHoy     => 'Pendientes de hoy',
    QuickAction.pendientesManana  => 'Pendientes de mañana',
    QuickAction.pendientesSemana  => 'Pendientes de esta semana',
    QuickAction.pendientesVencidas=> 'Pendientes vencidas',
    QuickAction.visitasHoy        => 'Visitas de hoy',
    QuickAction.proximaTarea      => 'Mi próxima tarea',
  };

  /// Mensaje del assistant cuando NO hay resultados.
  String get emptyMsg => switch (this) {
    QuickAction.pendientesHoy     => 'No tenés pendientes para hoy.',
    QuickAction.pendientesManana  => 'No tenés pendientes para mañana.',
    QuickAction.pendientesSemana  => 'No tenés pendientes esta semana.',
    QuickAction.pendientesVencidas=> 'No tenés pendientes vencidas. 👍',
    QuickAction.visitasHoy        => 'No registraste visitas hoy.',
    QuickAction.proximaTarea      => 'No tenés próximas tareas agendadas.',
  };

  /// Mensaje del assistant cuando hay resultados.
  String okMsg(int count) => switch (this) {
    QuickAction.pendientesHoy     => 'Tenés $count pendiente${count == 1 ? "" : "s"} para hoy:',
    QuickAction.pendientesManana  => 'Tenés $count pendiente${count == 1 ? "" : "s"} para mañana:',
    QuickAction.pendientesSemana  => 'Esta semana tenés $count pendiente${count == 1 ? "" : "s"}:',
    QuickAction.pendientesVencidas=> 'Tenés $count actividad${count == 1 ? "" : "es"} vencida${count == 1 ? "" : "s"}:',
    QuickAction.visitasHoy        => 'Hoy registraste $count visita${count == 1 ? "" : "s"}:',
    QuickAction.proximaTarea      => 'Tu próxima tarea:',
  };
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
  static List<AssistantAction> _rowsToPendienteItems(
      List<Map<String, dynamic>> items, {bool completable = false}) {
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
        completable: completable,
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

    // Truncar a últimos 10 mensajes para limitar tokens-in y evitar drift
    // del modelo cuando la conversación es larga. El historial completo
    // se preserva en memoria para el scroll del chat en la UI.
    const historialMax = 10;
    final recent = _historial.length > historialMax
        ? _historial.sublist(_historial.length - historialMax)
        : _historial;

    final messages = <Map<String, String>>[
      {'role': 'system', 'content': systemPrompt},
      ...recent,
    ];

    final stopwatch = Stopwatch()..start();
    final token = await AuthTokenService.getToken();
    if (token == null || token.isEmpty) {
      throw Exception('Sesión expirada. Volvé a iniciar sesión.');
    }
    final response = await http.post(
      Uri.parse('${AppConfig.supabaseFunctionsUrl}/cronos-chat'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
      body: json.encode({
        'model': AppConfig.openaiModel,
        'messages': messages,
        'temperature': 0.3,
        'max_tokens': 1500,
      }),
    ).timeout(const Duration(seconds: 20));
    stopwatch.stop();
    final latenciaMs = stopwatch.elapsedMilliseconds;

    if (response.statusCode == 401) {
      // Token revocado o perdido — forzar re-login
      await AuthTokenService.clearToken();
      throw Exception('Sesión expirada. Volvé a iniciar sesión.');
    }

    if (response.statusCode == 429) {
      throw Exception('Estás haciendo demasiadas consultas. Esperá unos minutos.');
    }

    if (response.statusCode != 200) {
      // Log del fallo HTTP (sin await)
      CronosLogger.log(
        userMsg: userMessage,
        responseRaw: response.body,
        parseOk: false,
        latenciaMs: latenciaMs,
        modelo: AppConfig.openaiModel,
      );
      throw Exception('Error del asistente (${response.statusCode})');
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

          // Si se filtró por cliente y hay UN solo pendiente, las cards salen
          // con botón "Completar" directo (resuelve el flujo "ya llamé a X"
          // sin requerir otro round-trip al LLM).
          final autoCompletar =
              clienteMatchQ != null && clienteMatchQ.isNotEmpty && items.length == 1;
          actions.addAll(_rowsToPendienteItems(items, completable: autoCompletar));
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

      // Log fire-and-forget del turno parseado correctamente
      CronosLogger.log(
        userMsg: userMessage,
        responseRaw: content,
        responseMensaje: mensaje,
        accionesCount: actions.length,
        parseOk: true,
        latenciaMs: latenciaMs,
        modelo: AppConfig.openaiModel,
      );

      return AssistantResult(mensaje: mensaje, actions: actions);
    } catch (_) {
      // JSON inválido — el modelo respondió en texto plano o cortado
      CronosLogger.log(
        userMsg: userMessage,
        responseRaw: content,
        parseOk: false,
        latenciaMs: latenciaMs,
        modelo: AppConfig.openaiModel,
      );
      return AssistantResult(mensaje: content, actions: []);
    }
  }

  /// Normaliza texto para fuzzy match: lowercase + sin tildes + sin signos.
  /// Whisper a veces transcribe "Garcia" / "García" / "garcía" indistinto.
  static String _normalize(String s) {
    final lower = s.toLowerCase().trim();
    const accents = 'áàäâãéèëêíìïîóòöôõúùüûñç';
    const plain   = 'aaaaaeeeeiiiiooooouuuunc';
    final buf = StringBuffer();
    for (final ch in lower.runes) {
      final c = String.fromCharCode(ch);
      final i = accents.indexOf(c);
      if (i >= 0) {
        buf.write(plain[i]);
      } else if (RegExp(r'[a-z0-9 ]').hasMatch(c)) {
        buf.write(c);
      }
      // resto (puntuación, símbolos) se ignora
    }
    // colapsar espacios múltiples
    return buf.toString().replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  /// Resuelve un cliente_match contra la cartera. Retorna todos los candidatos
  /// que coincidan — la UI muestra opciones si hay más de uno.
  static Future<List<Cliente>> _fuzzyMatchClientes(String query) async {
    final clientes = await _getClientes();
    final qRaw = query.toLowerCase().trim();
    final qNorm = _normalize(query);

    // 1. Match exacto por código (no se normaliza, los códigos son alfanuméricos)
    final byCode = clientes.where((c) => c.codigo == qRaw).toList();
    if (byCode.length == 1) return byCode;

    if (qNorm.isEmpty) return [];

    // 2. Match por contención en nombre (normalizado)
    final words = qNorm.split(' ').where((w) => w.isNotEmpty).toList();
    final matches = clientes.where((c) {
      final nameNorm = _normalize(c.nombre);
      return nameNorm.contains(qNorm) ||
          (words.length > 1 && words.every((w) => nameNorm.contains(w)));
    }).toList();

    return matches;
  }

  /// Ejecuta el núcleo de una consulta_pendientes una vez resuelto el cliente
  /// (usado cuando el usuario elige entre candidatos ambiguos).
  static Future<List<AssistantAction>> consultaPendientesResuelta(
      Cliente cliente) async {
    final items = await ActividadesService.pendientesPorCliente(cliente.codigo);
    return _rowsToPendienteItems(items);
  }

  /// Ejecuta una acción rápida sin pasar por el LLM. Determinística + barata.
  /// Mantiene el mismo formato de respuesta que `sendMessage` para que la UI
  /// no necesite distinguir el origen.
  ///
  /// La acción también se registra en `_historial` (user + assistant) para
  /// que si después el vendedor escribe libre, el modelo tenga contexto.
  static Future<AssistantResult> executeQuickAction(QuickAction qa) async {
    final stopwatch = Stopwatch()..start();
    _historial.add({'role': 'user', 'content': qa.label});

    List<Map<String, dynamic>> items;
    List<AssistantAction> actions;
    String mensaje;

    switch (qa) {
      case QuickAction.pendientesHoy:
        items = await ActividadesService.pendientesHoy();
        actions = _rowsToPendienteItems(items);
        break;
      case QuickAction.pendientesManana:
        items = await ActividadesService.pendientesManana();
        actions = _rowsToPendienteItems(items);
        break;
      case QuickAction.pendientesSemana:
        items = await ActividadesService.pendientesSemana();
        actions = _rowsToPendienteItems(items);
        break;
      case QuickAction.pendientesVencidas:
        items = await ActividadesService.pendientesVencidas();
        actions = _rowsToPendienteItems(items);
        break;
      case QuickAction.visitasHoy:
        items = await VisitasService.visitasHoy();
        actions = _rowsToVisitaItems(items);
        break;
      case QuickAction.proximaTarea:
        items = await ActividadesService.pendientes();
        // pendientes() ordena por fecha asc → primero es el más próximo
        items = items.take(1).toList();
        actions = _rowsToPendienteItems(items);
        break;
    }

    mensaje = items.isEmpty ? qa.emptyMsg : qa.okMsg(items.length);

    // Mantener historial coherente — si después el user escribe, el LLM
    // ve este intercambio como contexto.
    _historial.add({'role': 'assistant', 'content': mensaje});

    stopwatch.stop();

    // Log fire-and-forget — modelo='bypass' permite distinguir del tráfico LLM
    CronosLogger.log(
      userMsg: qa.label,
      responseMensaje: mensaje,
      accionesCount: actions.length,
      parseOk: true,
      latenciaMs: stopwatch.elapsedMilliseconds,
      modelo: 'bypass',
    );

    return AssistantResult(mensaje: mensaje, actions: actions);
  }
}
