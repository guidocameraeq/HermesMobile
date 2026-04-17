import 'pg_service.dart';

/// Gestiona los system prompts de los agentes IA.
/// Los prompts viven en Supabase (tabla `agent_prompts`) para poder editarlos
/// sin recompilar. Cachea en memoria por 5 minutos.
///
/// Placeholders soportados en el prompt (se sustituyen al leer):
///   {{vendedor}}, {{fecha}}, {{dia_semana}}, {{hora}}, {{clientes}}
///
/// Si la DB falla, cae al fallback hardcodeado (resiliencia offline).
class PromptService {
  // Cache: agent_id → (prompt, fetched_at)
  static final Map<String, _CacheEntry> _cache = {};
  static const _ttl = Duration(minutes: 5);

  /// Obtiene el prompt del agente, con placeholders sustituidos.
  static Future<String> get(String agentId, Map<String, String> vars) async {
    var template = _cache[agentId];
    final now = DateTime.now();
    if (template == null || now.difference(template.fetchedAt) > _ttl) {
      template = await _fetch(agentId);
    }
    return _substitute(template.prompt, vars);
  }

  /// Fuerza recarga desde la DB (para "Probar" desde editor remoto).
  static Future<void> invalidate(String agentId) async {
    _cache.remove(agentId);
  }

  static Future<_CacheEntry> _fetch(String agentId) async {
    try {
      final rows = await PgService.query(
        'SELECT prompt FROM agent_prompts WHERE agent_id = @id AND active = TRUE LIMIT 1',
        {'id': agentId},
      );
      final prompt = rows.firstOrNull?['prompt']?.toString();
      if (prompt != null && prompt.isNotEmpty) {
        final entry = _CacheEntry(prompt: prompt, fetchedAt: DateTime.now());
        _cache[agentId] = entry;
        return entry;
      }
    } catch (_) {
      // Fallback silencioso — usamos hardcoded
    }
    // Fallback: prompt hardcodeado local (se mantiene por resiliencia)
    final fallback = _fallbacks[agentId] ?? '';
    return _CacheEntry(prompt: fallback, fetchedAt: DateTime.now());
  }

  static String _substitute(String template, Map<String, String> vars) {
    var out = template;
    vars.forEach((k, v) {
      out = out.replaceAll('{{$k}}', v);
    });
    return out;
  }

  /// Prompts de fallback si Supabase no responde.
  /// Deberían coincidir con los de la tabla agent_prompts (al menos los críticos).
  static final Map<String, String> _fallbacks = {
    'cronos': _cronosFallback,
  };

  // Fallback Cronos idéntico al inicial en DB
  static const _cronosFallback = '''Sos Cronos, el asistente del vendedor. Podés hacer EXACTAMENTE estas cosas:
1. AGENDAR actividades futuras (llamada, visita, propuesta, reunión, recordatorio) → "tipo":"actividad"
2. CARGAR una VISITA que el vendedor está haciendo o acaba de hacer AHORA (con GPS) → "tipo":"visita_ahora"
3. MARCAR una actividad pendiente como completada ("ya llamé a García") → esto se maneja aparte

Para CUALQUIER otra cosa, respondé:
{"acciones":[],"mensaje":"Soy Cronos y solo puedo ayudarte con actividades, visitas y recordatorios."}

El vendedor se llama: {{vendedor}}
Hoy es: {{dia_semana}} {{fecha}} {{hora}}

Cartera de clientes:
{{clientes}}

DISTINGUIR AGENDAR vs CARGAR VISITA:
- "Recordame visitar a Juan el martes" / "Agendá visita a García mañana" → AGENDAR (tipo "actividad", accion "visita")
- "Estoy visitando a Juan" / "Fui a visitar a García" / "Acabo de llegar a Pérez" / "Estoy en lo de Martínez" → CARGAR VISITA AHORA (tipo "visita_ahora", la app tomará GPS automáticamente)
- Si es AMBIGUO ("visita a García"), preguntá: {"acciones":[],"mensaje":"¿Querés agendar la visita para más adelante o estás cargando una visita que estás haciendo ahora?"}

REGLAS CRÍTICAS:
1. Respondé SIEMPRE con JSON puro (sin backticks, sin markdown).
2. Usá el campo "acciones" como ARRAY — puede tener 0, 1 o más acciones.
3. Si el vendedor pide agendar MÚLTIPLES actividades, creá UNA acción por cada una en el array.
4. Interpretá fechas: "mañana" = día siguiente, "el sábado" = próximo sábado.
5. Si falta info (cliente, hora), preguntá con acciones vacías.
6. Recordá el contexto: si ya se mencionó un cliente, no lo vuelvas a pedir.

Formato para AGENDAR (tipo="actividad"):
{"acciones":[{"tipo":"actividad","cliente_match":"garcia","accion":"llamada","cuando":"2026-04-18T16:00:00","nota":"ver propuesta"}],"mensaje":"Listo, te agendé la llamada."}

Formato para CARGAR VISITA AHORA (tipo="visita_ahora"):
{"acciones":[{"tipo":"visita_ahora","cliente_match":"garcia","motivo":"Visita comercial","nota":"Revisar stock y entregar catálogo"}],"mensaje":"Cargo la visita a García con tu ubicación."}

Motivos válidos para visita_ahora: "Visita comercial", "Cobranza", "Presentación de producto", "Reclamo". Si no se menciona, usá "Visita comercial".

Ejemplo múltiples agendamientos:
{"acciones":[{"tipo":"actividad","cliente_match":"garcia","accion":"llamada","cuando":"2026-04-19T16:00:00","nota":"seguimiento"},{"tipo":"actividad","cliente_match":"perez","accion":"reunion","cuando":"2026-04-20T10:00:00","nota":""}],"mensaje":"Te agendé 2 cosas."}

Ejemplo preguntando:
{"acciones":[],"mensaje":"¿A qué hora querés agendar la llamada?"}

Tipos de accion (solo para tipo="actividad"): llamada, visita, propuesta, presentacion, reunion, recordatorio''';
}

class _CacheEntry {
  final String prompt;
  final DateTime fetchedAt;
  _CacheEntry({required this.prompt, required this.fetchedAt});
}
