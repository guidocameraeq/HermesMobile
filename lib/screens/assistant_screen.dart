import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../config/theme.dart';
import '../models/session.dart';
import '../services/assistant_service.dart';
import '../services/actividades_service.dart';
import '../services/notification_service.dart';
import '../services/visitas_service.dart';
import '../services/whisper_service.dart';
import '../models/cliente.dart';
import '../widgets/app_drawer.dart';
import '../widgets/recording_overlay.dart';
import '../widgets/cronos_info_sheet.dart';
import '../widgets/cycling_chips.dart';
import 'package:geolocator/geolocator.dart';

class AssistantScreen extends StatefulWidget {
  const AssistantScreen({super.key});

  @override
  State<AssistantScreen> createState() => _AssistantState();
}

class _AssistantState extends State<AssistantScreen>
    with TickerProviderStateMixin, AutomaticKeepAliveClientMixin {
  final _textCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  final _messages = <_ChatMessage>[];
  final Set<AssistantAction> _confirmadas = {};
  final Map<AssistantAction, Cliente> _elegidos = {}; // cliente resuelto manualmente

  bool _sending = false;
  bool _transcribing = false;
  bool _hasText = false;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    AssistantService.resetConversation();
    _textCtrl.addListener(() {
      final has = _textCtrl.text.trim().isNotEmpty;
      if (has != _hasText) setState(() => _hasText = has);
    });
  }

  // ── Envío de mensajes ──────────────────────────────────────────
  Future<void> _sendText(String text) async {
    final t = text.trim();
    if (t.isEmpty || _sending) return;
    setState(() {
      _messages.add(_ChatMessage(isUser: true, text: t));
      _sending = true;
    });
    _textCtrl.clear();
    _scrollToBottom();

    try {
      final result = await AssistantService.sendMessage(t);
      if (!mounted) return;
      setState(() {
        _messages.add(_ChatMessage(
          isUser: false,
          text: result.mensaje,
          actions: result.tieneAcciones ? result.actions : null,
        ));
      });
      HapticFeedback.selectionClick();
    } catch (e) {
      if (!mounted) return;
      setState(() => _messages.add(_ChatMessage(
        isUser: false,
        text: 'Error: ${e.toString().replaceFirst('Exception: ', '')}',
        isError: true,
      )));
    } finally {
      if (mounted) setState(() => _sending = false);
      _scrollToBottom();
    }
  }

  Future<void> _send() => _sendText(_textCtrl.text);

  // ── Grabación / Whisper ────────────────────────────────────────
  Future<void> _recordAndTranscribe() async {
    final ok = await WhisperService.hasPermission();
    if (!ok) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Permiso de micrófono denegado'),
        backgroundColor: AppColors.danger,
      ));
      return;
    }

    final audioPath = await RecordingOverlay.show(context);
    if (audioPath == null || !mounted) return;

    // Burbuja placeholder del usuario con mic + dots mientras transcribe
    final placeholder = _ChatMessage(
      isUser: true, text: '', isTranscribing: true);
    setState(() {
      _transcribing = true;
      _messages.add(placeholder);
    });
    _scrollToBottom();
    HapticFeedback.selectionClick();

    try {
      final text = await WhisperService.transcribe(audioPath);
      if (!mounted) return;
      setState(() {
        _messages.remove(placeholder);
        _transcribing = false;
      });
      if (text.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('No se captó voz'),
          backgroundColor: AppColors.warning,
        ));
        return;
      }
      await _sendText(text);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _messages.remove(placeholder);
        _transcribing = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Error transcribiendo: ${e.toString().replaceFirst('Exception: ', '')}'),
        backgroundColor: AppColors.danger,
      ));
    }
  }

  /// Cliente efectivo: el resuelto automático o el elegido por el usuario.
  Cliente? _clienteFinal(AssistantAction action) =>
      action.clienteResuelto ?? _elegidos[action];

  /// Callback desde _VisitaAhoraCard con motivo, GPS y decisión de cerrar.
  Future<void> _confirmVisitaAhora(AssistantAction action, String motivo,
      Position pos, int? cerrarActividadId) async {
    if (_confirmadas.contains(action)) return;
    final cliente = _clienteFinal(action);
    if (cliente == null) return;
    HapticFeedback.mediumImpact();
    try {
      await VisitasService.registrar(
        clienteCodigo: cliente.codigo,
        clienteNombre: cliente.nombre,
        latitud: pos.latitude,
        longitud: pos.longitude,
        motivo: motivo,
        notas: action.nota.isNotEmpty ? action.nota : null,
        precisionM: pos.accuracy,
        cerrarActividadId: cerrarActividadId,
      );
      if (!mounted) return;
      setState(() => _confirmadas.add(action));

      if (cerrarActividadId != null) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Visita registrada y actividad agendada cerrada.'),
          backgroundColor: AppColors.success,
          duration: Duration(seconds: 3),
        ));
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Error: ${e.toString().replaceFirst("Exception: ", "")}'),
        backgroundColor: AppColors.danger,
      ));
    }
  }

  /// Usuario elige un cliente de la lista de candidatos.
  void _elegirCliente(AssistantAction action, Cliente cliente) {
    HapticFeedback.selectionClick();
    setState(() => _elegidos[action] = cliente);

    // Si la acción es consulta_ambigua, expandir la consulta ahora con el cliente elegido
    if (action.tipo == 'consulta_ambigua') {
      _expandirConsultaCliente(action, cliente);
    }
  }

  Future<void> _expandirConsultaCliente(AssistantAction action, Cliente cliente) async {
    try {
      final items = await AssistantService.consultaPendientesResuelta(cliente);
      if (!mounted) return;
      setState(() {
        if (items.isEmpty) {
          _messages.add(_ChatMessage(
            isUser: false,
            text: '${cliente.nombre} no tiene pendientes.',
          ));
        } else {
          _messages.add(_ChatMessage(
            isUser: false,
            text: 'Pendientes de ${cliente.nombre}:',
            actions: items,
          ));
        }
      });
      _scrollToBottom();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Error: $e'), backgroundColor: AppColors.danger));
    }
  }

  // ── Confirmar acción ───────────────────────────────────────────
  Future<void> _confirmAction(AssistantAction action) async {
    if (_confirmadas.contains(action)) return;
    final cliente = _clienteFinal(action);

    HapticFeedback.mediumImpact();
    try {
      if (action.esPendiente && action.actividadId != null) {
        await ActividadesService.completar(action.actividadId!);
      } else {
        if (cliente == null && action.clienteMatch != null) {
          throw Exception('Elegí el cliente primero');
        }
        await ActividadesService.registrar(
          clienteCodigo: cliente?.codigo ?? '',
          clienteNombre: cliente?.nombre ?? action.clienteMatch ?? '',
          tipo: action.accion,
          descripcion: action.nota,
          fechaProgramada: action.cuando,
          origen: 'cronos',
        );
        if (action.cuando != null) {
          final dt = DateTime.tryParse(action.cuando!);
          if (dt != null && dt.isAfter(DateTime.now())) {
            final nombre = cliente?.nombre ?? action.clienteMatch ?? '';
            await NotificationService.schedule(
              id: DateTime.now().millisecondsSinceEpoch % 100000,
              title: '${action.accionLabel}${nombre.isNotEmpty ? " — $nombre" : ""}',
              body: action.nota.isNotEmpty ? action.nota : 'Actividad agendada',
              scheduledDate: dt,
            );
          }
        }
      }
      if (!mounted) return;
      setState(() => _confirmadas.add(action));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Error: ${e.toString().replaceFirst("Exception: ", "")}'),
        backgroundColor: AppColors.danger,
      ));
    }
  }

  // ── Chips de bienvenida ────────────────────────────────────────
  void _tapSuggestion(String text) {
    _textCtrl.text = text;
    _send();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(
          _scrollCtrl.position.maxScrollExtent + 80,
          duration: const Duration(milliseconds: 260),
          curve: Curves.easeOutCubic,
        );
      }
    });
  }

  @override
  void dispose() {
    _textCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  // ────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Scaffold(
      backgroundColor: AppColors.bg,
      drawer: const AppDrawer(currentTab: 1),
      appBar: AppBar(
        backgroundColor: AppColors.bgSidebar,
        elevation: 0,
        title: InkWell(
          onTap: () => CronosInfoSheet.show(context),
          borderRadius: BorderRadius.circular(8),
          child: Row(
            children: [
              _CronosBadge(),
              const SizedBox(width: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    const Text('Cronos', style: AppTextStyles.title),
                    const SizedBox(width: 4),
                    Icon(Icons.info_outline,
                        size: 12, color: AppColors.textMuted.withOpacity(0.6)),
                  ]),
                  Text(
                    _sending ? 'pensando...' :
                    _transcribing ? 'transcribiendo...' : 'en línea',
                    style: TextStyle(
                      color: _sending || _transcribing
                          ? AppColors.accent : AppColors.success,
                      fontSize: 10,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        actions: const [AppBarAvatar()],
      ),
      body: Column(
        children: [
          Expanded(
            child: _messages.isEmpty
                ? _Welcome(onChip: _tapSuggestion)
                : ListView.builder(
                    controller: _scrollCtrl,
                    padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
                    itemCount: _messages.length + (_sending ? 1 : 0),
                    itemBuilder: (_, i) {
                      if (i == _messages.length) return const _TypingBubble();
                      return _MessageBubble(
                        key: ValueKey(_messages[i]),
                        msg: _messages[i],
                        confirmadas: _confirmadas,
                        elegidos: _elegidos,
                        onConfirm: _confirmAction,
                        onConfirmVisita: _confirmVisitaAhora,
                        onElegir: _elegirCliente,
                      );
                    },
                  ),
          ),
          _InputBar(
            controller: _textCtrl,
            hasText: _hasText,
            disabled: _sending || _transcribing,
            onSend: _send,
            onMic: _recordAndTranscribe,
          ),
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════
//  WIDGETS
// ══════════════════════════════════════════════════════════════════

/// Avatar pequeño con pulse sutil para el AppBar.
class _CronosBadge extends StatefulWidget {
  @override
  State<_CronosBadge> createState() => _CronosBadgeState();
}

class _CronosBadgeState extends State<_CronosBadge>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
    )..repeat(reverse: true);
  }

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, __) {
        final t = _ctrl.value;
        return Container(
          width: 34, height: 34,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: const LinearGradient(
              begin: Alignment.topLeft, end: Alignment.bottomRight,
              colors: [AppColors.accent, AppColors.primary],
            ),
            boxShadow: [
              BoxShadow(
                color: AppColors.accent.withOpacity(0.35 + 0.25 * t),
                blurRadius: 8 + 6 * t, spreadRadius: 1,
              ),
            ],
          ),
          child: const Icon(Icons.auto_awesome, color: Colors.white, size: 18),
        );
      },
    );
  }
}

/// Pantalla de bienvenida con chips de sugerencias.
class _Welcome extends StatelessWidget {
  final void Function(String) onChip;
  const _Welcome({required this.onChip});

  // Pool amplio — se muestran 4 a la vez y rotan
  static const _pool = <ChipSuggestion>[
    ChipSuggestion(Icons.phone_outlined, 'Recordame llamar a García mañana a las 10', AppColors.primary),
    ChipSuggestion(Icons.checklist, '¿Qué tengo pendiente hoy?', AppColors.accent),
    ChipSuggestion(Icons.event, 'Agendá reunión con Pérez el jueves a las 15', AppColors.success),
    ChipSuggestion(Icons.rocket_launch_outlined, 'Propuesta para Rodríguez la semana que viene', AppColors.warning),
    ChipSuggestion(Icons.location_on, 'Estoy visitando a López', AppColors.success),
    ChipSuggestion(Icons.calendar_month, '¿Qué tengo esta semana?', AppColors.accent),
    ChipSuggestion(Icons.history_toggle_off, '¿Qué actividades tengo vencidas?', AppColors.danger),
    ChipSuggestion(Icons.skip_next, '¿Cuál es mi próxima tarea?', AppColors.accent),
    ChipSuggestion(Icons.flight_land, '¿Qué tarea tengo más lejos en el tiempo?', AppColors.accent),
    ChipSuggestion(Icons.person_search, '¿Qué pendientes tengo con García?', AppColors.primary),
    ChipSuggestion(Icons.check_circle_outline, 'Ya llamé a García', AppColors.success),
    ChipSuggestion(Icons.repeat, 'Llamada a Pérez cada martes durante 4 semanas', AppColors.warning),
    ChipSuggestion(Icons.done_all, '¿Qué visité esta semana?', AppColors.accent),
    ChipSuggestion(Icons.request_quote_outlined, 'Pasé a cobrarle a Martínez', AppColors.success),
    ChipSuggestion(Icons.alarm, 'Recordatorio: mandar factura a López mañana', AppColors.warning),
  ];

  @override
  Widget build(BuildContext context) {
    final nombre = Session.current.vendedorNombre.split(' ').first;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const SizedBox(height: 16),
          GestureDetector(
            onTap: () => CronosInfoSheet.show(context),
            child: _HeroIcon(),
          ),
          const SizedBox(height: 20),
          Text('Hola $nombre', style: const TextStyle(
            color: AppColors.textPrimary,
            fontSize: 24, fontWeight: FontWeight.w600,
          )),
          const SizedBox(height: 6),
          InkWell(
            onTap: () => CronosInfoSheet.show(context),
            borderRadius: BorderRadius.circular(6),
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Soy Cronos, tu asistente de agenda',
                    style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
                  ),
                  SizedBox(width: 4),
                  Icon(Icons.info_outline, color: AppColors.accent, size: 13),
                ],
              ),
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Probá alguna de estas ideas, o decímelo a tu manera',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.textMuted, fontSize: 11),
          ),
          const SizedBox(height: 20),
          CyclingChips(
            pool: _pool,
            visibleCount: 4,
            interval: const Duration(seconds: 4),
            onTap: onChip,
          ),
          const SizedBox(height: 18),
          const Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.mic, color: AppColors.textMuted, size: 14),
              SizedBox(width: 6),
              Text('También podés hablar', style: TextStyle(
                color: AppColors.textMuted, fontSize: 11,
              )),
            ],
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }
}

class _HeroIcon extends StatefulWidget {
  @override
  State<_HeroIcon> createState() => _HeroIconState();
}

class _HeroIconState extends State<_HeroIcon>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 3000),
    )..repeat();
  }

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, __) {
        final t = (_ctrl.value * 2 * 3.14159);
        final scale = 1 + 0.04 * (0.5 - (_ctrl.value - 0.5).abs()) * 2;
        return Transform.scale(
          scale: scale,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Container(
                width: 90, height: 90,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft, end: Alignment.bottomRight,
                    colors: [AppColors.accent, AppColors.primary],
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.accent.withOpacity(0.4),
                      blurRadius: 30, spreadRadius: 6,
                    ),
                  ],
                ),
                child: Transform.rotate(
                  angle: t * 0.2,
                  child: const Icon(Icons.auto_awesome, color: Colors.white, size: 44),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _AnimatedChip extends StatefulWidget {
  final int index;
  final String text;
  final IconData icon;
  final VoidCallback onTap;

  const _AnimatedChip({
    required this.index,
    required this.text,
    required this.icon,
    required this.onTap,
  });

  @override
  State<_AnimatedChip> createState() => _AnimatedChipState();
}

class _AnimatedChipState extends State<_AnimatedChip>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _opacity;
  late final Animation<Offset> _slide;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 380),
    );
    _opacity = CurvedAnimation(parent: _ctrl, curve: Curves.easeOut);
    _slide = Tween(begin: const Offset(0, 0.2), end: Offset.zero)
        .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic));
    Future.delayed(Duration(milliseconds: 100 + widget.index * 70), () {
      if (mounted) _ctrl.forward();
    });
  }

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _opacity,
      child: SlideTransition(
        position: _slide,
        child: Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: InkWell(
            onTap: () {
              HapticFeedback.selectionClick();
              widget.onTap();
            },
            borderRadius: BorderRadius.circular(14),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: AppColors.bgCard,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppColors.accent.withOpacity(0.15)),
              ),
              child: Row(
                children: [
                  Icon(widget.icon, color: AppColors.accent, size: 18),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(widget.text, style: AppTextStyles.caption.copyWith(
                      color: AppColors.textPrimary, fontSize: 13)),
                  ),
                  const Icon(Icons.north_east,
                      color: AppColors.textMuted, size: 14),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Bubble de mensaje con animación de entrada.
class _MessageBubble extends StatefulWidget {
  final _ChatMessage msg;
  final Set<AssistantAction> confirmadas;
  final Map<AssistantAction, Cliente> elegidos;
  final Future<void> Function(AssistantAction) onConfirm;
  final Future<void> Function(AssistantAction, String motivo, Position pos, int? cerrarActividadId) onConfirmVisita;
  final void Function(AssistantAction, Cliente) onElegir;

  const _MessageBubble({
    super.key,
    required this.msg,
    required this.confirmadas,
    required this.elegidos,
    required this.onConfirm,
    required this.onConfirmVisita,
    required this.onElegir,
  });

  @override
  State<_MessageBubble> createState() => _MessageBubbleState();
}

class _MessageBubbleState extends State<_MessageBubble>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _opacity;
  late final Animation<Offset> _slide;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 220),
    );
    _opacity = CurvedAnimation(parent: _ctrl, curve: Curves.easeOut);
    _slide = Tween(
      begin: Offset(widget.msg.isUser ? 0.1 : -0.1, 0.15),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic));
    _ctrl.forward();
  }

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  /// Dispatcher: elige qué tipo de card renderizar según el action.
  Widget _dispatchCard(AssistantAction a) {
    if (a.esVisitaAhora) {
      return _VisitaAhoraCard(
        action: a,
        confirmada: widget.confirmadas.contains(a),
        clienteElegido: widget.elegidos[a],
        onConfirm: (motivo, pos, idCerrar) =>
            widget.onConfirmVisita(a, motivo, pos, idCerrar),
        onElegir: (c) => widget.onElegir(a, c),
      );
    }
    if (a.esVisitaRegistrada) {
      return _VisitaRegistradaCard(action: a);
    }
    return _ActionCard(
      action: a,
      confirmada: widget.confirmadas.contains(a),
      clienteElegido: widget.elegidos[a],
      onConfirm: () => widget.onConfirm(a),
      onElegir: (c) => widget.onElegir(a, c),
    );
  }

  @override
  Widget build(BuildContext context) {
    final m = widget.msg;
    // Burbuja especial mientras Whisper transcribe
    if (m.isTranscribing) {
      return FadeTransition(
        opacity: _opacity,
        child: SlideTransition(
          position: _slide,
          child: const _TranscribingBubble(),
        ),
      );
    }
    return FadeTransition(
      opacity: _opacity,
      child: SlideTransition(
        position: _slide,
        child: Align(
          alignment: m.isUser ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.all(12),
            constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width * 0.82,
            ),
            decoration: BoxDecoration(
              gradient: m.isUser
                  ? const LinearGradient(
                      begin: Alignment.topLeft, end: Alignment.bottomRight,
                      colors: [AppColors.primary, Color(0xFF3B82F6)],
                    )
                  : null,
              color: m.isUser
                  ? null
                  : m.isError
                      ? AppColors.danger.withOpacity(0.15)
                      : AppColors.bgCard,
              borderRadius: BorderRadius.only(
                topLeft: const Radius.circular(16),
                topRight: const Radius.circular(16),
                bottomLeft: Radius.circular(m.isUser ? 16 : 4),
                bottomRight: Radius.circular(m.isUser ? 4 : 16),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  m.text,
                  style: TextStyle(
                    color: m.isUser
                        ? Colors.white
                        : m.isError
                            ? AppColors.danger
                            : AppColors.textPrimary,
                    fontSize: 14, height: 1.35,
                  ),
                ),
                if (m.actions != null && m.actions!.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  ...m.actions!.map((a) => Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: _dispatchCard(a),
                  )),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Tarjeta de acción con animación al confirmar.
class _ActionCard extends StatelessWidget {
  final AssistantAction action;
  final bool confirmada;
  final Cliente? clienteElegido;
  final VoidCallback onConfirm;
  final void Function(Cliente) onElegir;

  const _ActionCard({
    required this.action,
    required this.confirmada,
    required this.clienteElegido,
    required this.onConfirm,
    required this.onElegir,
  });

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.96, end: 1),
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
      builder: (_, scale, child) => Transform.scale(scale: scale, child: child),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: confirmada
              ? AppColors.success.withOpacity(0.1)
              : AppColors.bg,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: confirmada
                ? AppColors.success
                : AppColors.accent.withOpacity(0.3),
            width: confirmada ? 1.5 : 1,
          ),
        ),
        child: Stack(
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (action.tieneCliente)
                  _row(Icons.person, 'Cliente',
                      '${action.clienteResuelto!.nombre} (${action.clienteResuelto!.codigo})')
                else if (clienteElegido != null)
                  _row(Icons.person, 'Cliente',
                      '${clienteElegido!.nombre} (${clienteElegido!.codigo})')
                else if (action.candidatos != null && action.candidatos!.isNotEmpty)
                  _candidatosPicker()
                else if (action.clienteMatch != null)
                  _row(Icons.person_search, 'Cliente',
                      '${action.clienteMatch} (no encontrado)'),
                _row(Icons.category_outlined, 'Acción', action.accionLabel),
                if (action.cuando != null)
                  _row(Icons.schedule, 'Cuándo', action.cuandoFmt),
                if (action.nota.isNotEmpty)
                  _row(Icons.notes, 'Nota', action.nota),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: confirmada ? null : onConfirm,
                    icon: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 260),
                      transitionBuilder: (w, a) =>
                          ScaleTransition(scale: a, child: w),
                      child: Icon(
                        confirmada ? Icons.check_circle : Icons.check,
                        key: ValueKey(confirmada),
                        size: 16,
                      ),
                    ),
                    label: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 260),
                      child: Text(
                        confirmada
                            ? (action.esPendiente ? 'Completada' : 'Agendada')
                            : (action.esPendiente ? 'Completar' : 'Confirmar'),
                        key: ValueKey(confirmada),
                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.success,
                      foregroundColor: Colors.white,
                      disabledBackgroundColor: AppColors.success,
                      disabledForegroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      elevation: 0,
                    ),
                  ),
                ),
              ],
            ),
            // Check animado arriba a la derecha
            Positioned(
              top: 0, right: 0,
              child: AnimatedScale(
                scale: confirmada ? 1 : 0,
                duration: const Duration(milliseconds: 260),
                curve: Curves.elasticOut,
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: AppColors.success,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.success.withOpacity(0.6),
                        blurRadius: 8, spreadRadius: 1,
                      ),
                    ],
                  ),
                  child: const Icon(Icons.check, color: Colors.white, size: 14),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _candidatosPicker() {
    final cands = action.candidatos!;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.person_search, size: 14, color: AppColors.warning),
              const SizedBox(width: 8),
              Text('Hay ${cands.length} clientes con ese nombre:',
                  style: const TextStyle(color: AppColors.warning, fontSize: 11,
                      fontWeight: FontWeight.w600)),
            ],
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: cands.map((c) => InkWell(
              onTap: () => onElegir(c),
              borderRadius: BorderRadius.circular(8),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: AppColors.accent.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppColors.accent.withOpacity(0.4)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.person, size: 12, color: AppColors.accent),
                    const SizedBox(width: 5),
                    Text(c.nombre,
                        style: const TextStyle(color: AppColors.textPrimary, fontSize: 11)),
                    const SizedBox(width: 4),
                    Text('(${c.codigo})',
                        style: const TextStyle(color: AppColors.textMuted, fontSize: 10)),
                  ],
                ),
              ),
            )).toList(),
          ),
        ],
      ),
    );
  }

  Widget _row(IconData icon, String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 14, color: AppColors.accent),
            const SizedBox(width: 8),
            SizedBox(width: 60, child: Text('$label:', style: AppTextStyles.muted)),
            Expanded(child: Text(value, style: AppTextStyles.body)),
          ],
        ),
      );
}

/// Burbuja del USUARIO mientras Whisper transcribe el audio.
/// Muestra ícono de micrófono + dots animados + "Transcribiendo...".
class _TranscribingBubble extends StatefulWidget {
  const _TranscribingBubble();
  @override
  State<_TranscribingBubble> createState() => _TranscribingBubbleState();
}

class _TranscribingBubbleState extends State<_TranscribingBubble>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 900),
    )..repeat();
  }

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerRight,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft, end: Alignment.bottomRight,
            colors: [AppColors.primary, Color(0xFF3B82F6)],
          ),
          borderRadius: BorderRadius.only(
            topLeft: Radius.circular(16),
            topRight: Radius.circular(16),
            bottomLeft: Radius.circular(16),
            bottomRight: Radius.circular(4),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.mic, color: Colors.white70, size: 14),
            const SizedBox(width: 8),
            const Text('Transcribiendo',
                style: TextStyle(color: Colors.white, fontSize: 12)),
            const SizedBox(width: 6),
            AnimatedBuilder(
              animation: _ctrl,
              builder: (_, __) {
                return Row(
                  mainAxisSize: MainAxisSize.min,
                  children: List.generate(3, (i) {
                    final phase = (_ctrl.value - i * 0.2) % 1;
                    final y = -3 * (phase < 0.3 ? (1 - (phase / 0.3 - 0.5).abs() * 2) : 0);
                    final op = 0.4 + 0.6 * (phase < 0.3 ? 1 - (phase / 0.3 - 0.5).abs() * 2 : 0);
                    return Padding(
                      padding: EdgeInsets.only(right: i < 2 ? 3 : 0),
                      child: Transform.translate(
                        offset: Offset(0, y.toDouble()),
                        child: Container(
                          width: 5, height: 5,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.white.withOpacity(op.clamp(0.4, 1.0)),
                          ),
                        ),
                      ),
                    );
                  }),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

/// Indicador de "Cronos está pensando..." con 3 dots animados.
class _TypingBubble extends StatefulWidget {
  const _TypingBubble();
  @override
  State<_TypingBubble> createState() => _TypingBubbleState();
}

class _TypingBubbleState extends State<_TypingBubble>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 900),
    )..repeat();
  }

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: AppColors.bgCard,
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(16),
            topRight: Radius.circular(16),
            bottomLeft: Radius.circular(4),
            bottomRight: Radius.circular(16),
          ),
        ),
        child: AnimatedBuilder(
          animation: _ctrl,
          builder: (_, __) {
            return Row(
              mainAxisSize: MainAxisSize.min,
              children: List.generate(3, (i) {
                final phase = (_ctrl.value - i * 0.2) % 1;
                final y = -4 * (phase < 0.3 ? (1 - (phase / 0.3 - 0.5).abs() * 2) : 0);
                final op = 0.4 + 0.6 * (phase < 0.3 ? 1 - (phase / 0.3 - 0.5).abs() * 2 : 0);
                return Padding(
                  padding: EdgeInsets.only(right: i < 2 ? 5 : 0),
                  child: Transform.translate(
                    offset: Offset(0, y.toDouble()),
                    child: Container(
                      width: 7, height: 7,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: AppColors.accent.withOpacity(op.clamp(0.3, 1.0)),
                      ),
                    ),
                  ),
                );
              }),
            );
          },
        ),
      ),
    );
  }
}

/// Barra de input que alterna entre mic (sin texto) y send (con texto).
class _InputBar extends StatelessWidget {
  final TextEditingController controller;
  final bool hasText;
  final bool disabled;
  final VoidCallback onSend;
  final VoidCallback onMic;

  const _InputBar({
    required this.controller,
    required this.hasText,
    required this.disabled,
    required this.onSend,
    required this.onMic,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 12),
      decoration: const BoxDecoration(
        color: AppColors.bgSidebar,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: controller,
                style: AppTextStyles.body,
                minLines: 1,
                maxLines: 4,
                enabled: !disabled,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => onSend(),
                decoration: InputDecoration(
                  hintText: hasText ? 'Escribí tu mensaje...' : 'Escribí o tocá el micrófono',
                  hintStyle: AppTextStyles.muted,
                  filled: true,
                  fillColor: AppColors.bgCard,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(22),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                ),
              ),
            ),
            const SizedBox(width: 8),
            // Botón que alterna entre Mic y Send
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 220),
              transitionBuilder: (w, a) => ScaleTransition(scale: a, child: w),
              child: hasText
                  ? _SendBtn(onTap: disabled ? null : onSend, key: const ValueKey('send'))
                  : _MicBtn(onTap: disabled ? null : onMic, key: const ValueKey('mic')),
            ),
          ],
        ),
      ),
    );
  }
}

class _SendBtn extends StatelessWidget {
  final VoidCallback? onTap;
  const _SendBtn({super.key, this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 48, height: 48,
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft, end: Alignment.bottomRight,
            colors: [AppColors.primary, Color(0xFF3B82F6)],
          ),
          borderRadius: BorderRadius.circular(24),
          boxShadow: onTap == null ? null : [
            BoxShadow(
              color: AppColors.primary.withOpacity(0.4),
              blurRadius: 12, spreadRadius: 1,
            ),
          ],
        ),
        child: const Icon(Icons.arrow_upward, color: Colors.white, size: 22),
      ),
    );
  }
}

class _MicBtn extends StatelessWidget {
  final VoidCallback? onTap;
  const _MicBtn({super.key, this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 48, height: 48,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft, end: Alignment.bottomRight,
            colors: [AppColors.accent, AppColors.primary],
          ),
          borderRadius: BorderRadius.circular(24),
          boxShadow: onTap == null ? null : [
            BoxShadow(
              color: AppColors.accent.withOpacity(0.4),
              blurRadius: 12, spreadRadius: 1,
            ),
          ],
        ),
        child: const Icon(Icons.mic, color: Colors.white, size: 22),
      ),
    );
  }
}

/// Modelo de mensaje del chat.
class _ChatMessage {
  final bool isUser;
  final String text;
  final List<AssistantAction>? actions;
  final bool isError;
  final bool isTranscribing; // placeholder mientras Whisper transcribe

  _ChatMessage({
    required this.isUser,
    required this.text,
    this.actions,
    this.isError = false,
    this.isTranscribing = false,
  });
}

// ══════════════════════════════════════════════════════════════════
//  _VisitaAhoraCard — GPS en vivo + chips de motivo
// ══════════════════════════════════════════════════════════════════
class _VisitaAhoraCard extends StatefulWidget {
  final AssistantAction action;
  final bool confirmada;
  final Cliente? clienteElegido;
  final Future<void> Function(String motivo, Position pos, int? cerrarActividadId) onConfirm;
  final void Function(Cliente) onElegir;

  const _VisitaAhoraCard({
    required this.action,
    required this.confirmada,
    required this.clienteElegido,
    required this.onConfirm,
    required this.onElegir,
  });

  @override
  State<_VisitaAhoraCard> createState() => _VisitaAhoraCardState();
}

class _VisitaAhoraCardState extends State<_VisitaAhoraCard> {
  static const _motivos = ['Visita comercial', 'Cobranza', 'Presentación de producto', 'Reclamo'];

  late String _motivo;
  Position? _position;
  String? _gpsError;
  bool _obteniendo = true;
  bool _confirmando = false;

  // Match con actividad agendada
  Map<String, dynamic>? _agendada;
  bool _buscandoAgendada = false;
  bool _cerrarAgendada = false; // default OFF — el vendedor decide explícito

  @override
  void initState() {
    super.initState();
    _motivo = widget.action.motivo ?? 'Visita comercial';
    if (!_motivos.contains(_motivo)) _motivo = 'Visita comercial';
    if (!widget.confirmada) {
      _obtenerGps();
      _buscarAgendada();
    }
  }

  Future<void> _buscarAgendada() async {
    final cli = widget.clienteElegido ?? widget.action.clienteResuelto;
    if (cli == null) return;
    setState(() => _buscandoAgendada = true);
    try {
      final match = await VisitasService.buscarVisitaAgendadaHoy(cli.codigo);
      if (!mounted) return;
      setState(() {
        _agendada = match;
        _buscandoAgendada = false;
      });
    } catch (_) {
      if (mounted) setState(() => _buscandoAgendada = false);
    }
  }

  @override
  void didUpdateWidget(covariant _VisitaAhoraCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Si recién se resolvió el cliente (vía chip), buscamos agendada
    final prevCli = oldWidget.clienteElegido ?? oldWidget.action.clienteResuelto;
    final nowCli = widget.clienteElegido ?? widget.action.clienteResuelto;
    if (prevCli?.codigo != nowCli?.codigo && nowCli != null && _agendada == null) {
      _buscarAgendada();
    }
  }

  Future<void> _obtenerGps() async {
    setState(() { _obteniendo = true; _gpsError = null; });
    try {
      final pos = await VisitasService.obtenerGps();
      if (!mounted) return;
      setState(() { _position = pos; _obteniendo = false; });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _gpsError = e.toString().replaceFirst('Exception: ', '');
        _obteniendo = false;
      });
    }
  }

  Cliente? get _clienteFinal =>
      widget.action.clienteResuelto ?? widget.clienteElegido;

  Future<void> _onTapConfirm() async {
    if (_confirmando || widget.confirmada) return;
    if (_clienteFinal == null) return;
    if (_position == null) {
      await _obtenerGps();
      if (_position == null) return;
    }
    final idCerrar = (_cerrarAgendada && _agendada != null)
        ? int.tryParse(_agendada!['id'].toString())
        : null;
    setState(() => _confirmando = true);
    await widget.onConfirm(_motivo, _position!, idCerrar);
    if (mounted) setState(() => _confirmando = false);
  }

  @override
  Widget build(BuildContext context) {
    final puedeConfirmar = _clienteFinal != null && _position != null && !widget.confirmada;

    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.96, end: 1),
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
      builder: (_, scale, child) => Transform.scale(scale: scale, child: child),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: widget.confirmada
              ? AppColors.success.withOpacity(0.12)
              : AppColors.bg,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: widget.confirmada
                ? AppColors.success
                : AppColors.success.withOpacity(0.35),
            width: widget.confirmada ? 1.5 : 1,
          ),
        ),
        child: Stack(
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(5),
                      decoration: BoxDecoration(
                        color: AppColors.success.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Icon(Icons.my_location,
                          size: 13, color: AppColors.success),
                    ),
                    const SizedBox(width: 8),
                    const Text('VISITA CON GPS', style: TextStyle(
                      color: AppColors.success,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.2,
                    )),
                  ],
                ),
                const SizedBox(height: 12),

                // Cliente
                _sectionLabel('CLIENTE'),
                const SizedBox(height: 4),
                _clienteSection(),

                const SizedBox(height: 12),

                // Motivo — chips tocables
                _sectionLabel('MOTIVO'),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6, runSpacing: 6,
                  children: _motivos.map((m) {
                    final sel = m == _motivo;
                    return InkWell(
                      onTap: widget.confirmada ? null : () {
                        HapticFeedback.selectionClick();
                        setState(() => _motivo = m);
                      },
                      borderRadius: BorderRadius.circular(16),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: sel ? AppColors.success : AppColors.bgCard,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: sel ? AppColors.success : AppColors.border,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (sel) ...[
                              const Icon(Icons.check, color: Colors.white, size: 11),
                              const SizedBox(width: 4),
                            ],
                            Text(m, style: TextStyle(
                              color: sel ? Colors.white : AppColors.textSecondary,
                              fontSize: 11,
                              fontWeight: sel ? FontWeight.w600 : FontWeight.normal,
                            )),
                          ],
                        ),
                      ),
                    );
                  }).toList(),
                ),

                // Nota (si hay)
                if (widget.action.nota.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  _sectionLabel('NOTA'),
                  const SizedBox(height: 4),
                  Text(widget.action.nota, style: AppTextStyles.body),
                ],

                // Actividad agendada detectada — pregunta explícita
                if (_agendada != null) ...[
                  const SizedBox(height: 14),
                  _agendadaPrompt(),
                ],

                const SizedBox(height: 12),

                // GPS status
                _sectionLabel('UBICACIÓN'),
                const SizedBox(height: 6),
                _gpsSection(),

                const SizedBox(height: 14),

                // Botón
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: (puedeConfirmar && !_confirmando) ? _onTapConfirm : null,
                    icon: _confirmando
                        ? const SizedBox(width: 14, height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : Icon(widget.confirmada ? Icons.check_circle : Icons.my_location, size: 16),
                    label: Text(
                      widget.confirmada
                          ? 'Visita registrada'
                          : _obteniendo
                              ? 'Esperando GPS...'
                              : _clienteFinal == null
                                  ? 'Elegí el cliente'
                                  : 'Registrar visita',
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.success,
                      foregroundColor: Colors.white,
                      disabledBackgroundColor: widget.confirmada
                          ? AppColors.success
                          : AppColors.textMuted.withOpacity(0.3),
                      disabledForegroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      elevation: 0,
                    ),
                  ),
                ),
              ],
            ),
            // Check animado arriba a la derecha
            Positioned(
              top: 0, right: 0,
              child: AnimatedScale(
                scale: widget.confirmada ? 1 : 0,
                duration: const Duration(milliseconds: 260),
                curve: Curves.elasticOut,
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: AppColors.success,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.success.withOpacity(0.6),
                        blurRadius: 8, spreadRadius: 1,
                      ),
                    ],
                  ),
                  child: const Icon(Icons.check, color: Colors.white, size: 14),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _agendadaPrompt() {
    final m = _agendada!;
    final fechaStr = _fmtHora(m['fecha_programada']?.toString());
    final desc = m['descripcion']?.toString() ?? '';
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.accent.withOpacity(0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.accent.withOpacity(0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const Icon(Icons.schedule, size: 14, color: AppColors.accent),
            const SizedBox(width: 6),
            const Expanded(
              child: Text('Tenés una visita agendada para hoy',
                  style: TextStyle(color: AppColors.accent, fontSize: 11,
                      fontWeight: FontWeight.w700, letterSpacing: 0.5)),
            ),
          ]),
          const SizedBox(height: 6),
          Text('📅 Hoy a las $fechaStr${desc.isNotEmpty ? "  ·  \"$desc\"" : ""}',
              style: AppTextStyles.body),
          const SizedBox(height: 8),
          const Text('¿Querés cerrarla con esta visita?',
              style: AppTextStyles.muted),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(
              child: InkWell(
                onTap: () => setState(() => _cerrarAgendada = false),
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  decoration: BoxDecoration(
                    color: !_cerrarAgendada ? AppColors.textMuted.withOpacity(0.25) : Colors.transparent,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: !_cerrarAgendada ? AppColors.textMuted : AppColors.border,
                    ),
                  ),
                  alignment: Alignment.center,
                  child: Text('No, dejarla pendiente',
                      style: TextStyle(
                        color: !_cerrarAgendada ? AppColors.textPrimary : AppColors.textMuted,
                        fontSize: 11,
                        fontWeight: !_cerrarAgendada ? FontWeight.w600 : FontWeight.normal,
                      )),
                ),
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: InkWell(
                onTap: () => setState(() => _cerrarAgendada = true),
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  decoration: BoxDecoration(
                    color: _cerrarAgendada ? AppColors.success : Colors.transparent,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: _cerrarAgendada ? AppColors.success : AppColors.border,
                    ),
                  ),
                  alignment: Alignment.center,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (_cerrarAgendada) ...[
                        const Icon(Icons.check, color: Colors.white, size: 12),
                        const SizedBox(width: 4),
                      ],
                      Text('Sí, cerrarla',
                          style: TextStyle(
                            color: _cerrarAgendada ? Colors.white : AppColors.textMuted,
                            fontSize: 11,
                            fontWeight: _cerrarAgendada ? FontWeight.w600 : FontWeight.normal,
                          )),
                    ],
                  ),
                ),
              ),
            ),
          ]),
        ],
      ),
    );
  }

  String _fmtHora(String? iso) {
    if (iso == null) return '--:--';
    final d = DateTime.tryParse(iso);
    if (d == null) return '--:--';
    return '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  }

  Widget _sectionLabel(String t) => Text(t, style: const TextStyle(
    color: AppColors.textMuted,
    fontSize: 9,
    fontWeight: FontWeight.w700,
    letterSpacing: 1.2,
  ));

  Widget _clienteSection() {
    final c = _clienteFinal;
    if (c != null) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: AppColors.bgCard,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(children: [
          const Icon(Icons.person, size: 13, color: AppColors.accent),
          const SizedBox(width: 6),
          Expanded(child: Text(c.nombre,
              style: AppTextStyles.body,
              maxLines: 1, overflow: TextOverflow.ellipsis)),
          Text('(${c.codigo})', style: AppTextStyles.muted),
        ]),
      );
    }

    final cands = widget.action.candidatos;
    if (cands != null && cands.isNotEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Hay ${cands.length} posibles:', style: const TextStyle(
              color: AppColors.warning, fontSize: 10)),
          const SizedBox(height: 4),
          Wrap(
            spacing: 6, runSpacing: 6,
            children: cands.map((c) => InkWell(
              onTap: widget.confirmada ? null : () => widget.onElegir(c),
              borderRadius: BorderRadius.circular(8),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: AppColors.accent.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppColors.accent.withOpacity(0.4)),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.person, size: 11, color: AppColors.accent),
                  const SizedBox(width: 4),
                  Text(c.nombre,
                      style: const TextStyle(color: AppColors.textPrimary, fontSize: 11)),
                  const SizedBox(width: 3),
                  Text('(${c.codigo})',
                      style: const TextStyle(color: AppColors.textMuted, fontSize: 10)),
                ]),
              ),
            )).toList(),
          ),
        ],
      );
    }

    return Text(widget.action.clienteMatch ?? 'Sin cliente',
        style: const TextStyle(color: AppColors.danger, fontSize: 12));
  }

  Widget _gpsSection() {
    if (widget.confirmada) {
      return Row(children: [
        const Icon(Icons.check_circle, color: AppColors.success, size: 14),
        const SizedBox(width: 6),
        if (_position != null)
          Text('${_position!.latitude.toStringAsFixed(5)}, ${_position!.longitude.toStringAsFixed(5)}',
              style: AppTextStyles.caption)
        else
          const Text('Registrada', style: AppTextStyles.caption),
      ]);
    }

    if (_obteniendo) {
      return Row(children: const [
        SizedBox(width: 14, height: 14,
            child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.accent)),
        SizedBox(width: 8),
        Text('Obteniendo GPS...', style: AppTextStyles.caption),
      ]);
    }

    if (_gpsError != null) {
      return Row(children: [
        const Icon(Icons.error_outline, color: AppColors.danger, size: 14),
        const SizedBox(width: 6),
        Expanded(child: Text(_gpsError!,
            style: const TextStyle(color: AppColors.danger, fontSize: 11))),
        TextButton(
          onPressed: _obtenerGps,
          child: const Text('Reintentar', style: TextStyle(fontSize: 11)),
        ),
      ]);
    }

    if (_position != null) {
      final prec = _position!.accuracy.toStringAsFixed(0);
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: AppColors.success.withOpacity(0.08),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.success.withOpacity(0.3)),
        ),
        child: Row(children: [
          const Icon(Icons.location_on, color: AppColors.success, size: 14),
          const SizedBox(width: 6),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${_position!.latitude.toStringAsFixed(5)}, ${_position!.longitude.toStringAsFixed(5)}',
                    style: AppTextStyles.caption),
                Text('Precisión: ${prec}m',
                    style: AppTextStyles.muted),
              ],
            ),
          ),
        ]),
      );
    }

    return const Text('Sin datos', style: AppTextStyles.muted);
  }
}

// ══════════════════════════════════════════════════════════════════
//  _VisitaRegistradaCard — display read-only de visita ya hecha
// ══════════════════════════════════════════════════════════════════
class _VisitaRegistradaCard extends StatelessWidget {
  final AssistantAction action;
  const _VisitaRegistradaCard({required this.action});

  @override
  Widget build(BuildContext context) {
    final cuandoDt = action.cuando != null ? DateTime.tryParse(action.cuando!) : null;
    String fechaStr = '';
    if (cuandoDt != null) {
      final d = cuandoDt;
      fechaStr = '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')} '
          '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
    }
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.bg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.accent.withOpacity(0.2)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.location_on, color: AppColors.success, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(action.clienteResuelto?.nombre ?? action.clienteMatch ?? '',
                    style: AppTextStyles.body.copyWith(fontWeight: FontWeight.w600)),
                if (action.motivo != null && action.motivo!.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: AppColors.success.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(action.motivo!, style: const TextStyle(
                        color: AppColors.success, fontSize: 9,
                        fontWeight: FontWeight.bold,
                      )),
                    ),
                  ),
                if (action.nota.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(action.nota, style: AppTextStyles.muted,
                      maxLines: 2, overflow: TextOverflow.ellipsis),
                ],
              ],
            ),
          ),
          if (fechaStr.isNotEmpty)
            Text(fechaStr, style: AppTextStyles.muted),
        ],
      ),
    );
  }
}
