import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../config/theme.dart';
import '../models/session.dart';
import '../services/assistant_service.dart';
import '../services/actividades_service.dart';
import '../services/notification_service.dart';
import '../services/visitas_service.dart';
import '../services/whisper_service.dart';
import '../widgets/app_drawer.dart';
import '../widgets/recording_overlay.dart';

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

    setState(() => _transcribing = true);
    HapticFeedback.selectionClick();
    try {
      final text = await WhisperService.transcribe(audioPath);
      if (!mounted) return;
      setState(() => _transcribing = false);
      if (text.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('No se captó voz'),
          backgroundColor: AppColors.warning,
        ));
        return;
      }
      // Envío directo — es lo que el usuario esperaba
      await _sendText(text);
    } catch (e) {
      if (!mounted) return;
      setState(() => _transcribing = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Error transcribiendo: ${e.toString().replaceFirst('Exception: ', '')}'),
        backgroundColor: AppColors.danger,
      ));
    }
  }

  // ── Confirmar acción ───────────────────────────────────────────
  Future<void> _confirmAction(AssistantAction action) async {
    if (_confirmadas.contains(action)) return;
    HapticFeedback.mediumImpact();
    try {
      if (action.esPendiente && action.actividadId != null) {
        await ActividadesService.completar(action.actividadId!);
      } else if (action.esVisitaAhora) {
        // Cargar visita con GPS actual
        if (action.clienteResuelto == null) {
          throw Exception('Necesito saber a qué cliente estás visitando');
        }
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Row(children: [
            SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)),
            SizedBox(width: 12),
            Text('Obteniendo ubicación GPS...'),
          ]),
          duration: Duration(seconds: 8),
        ));
        final pos = await VisitasService.obtenerGps();
        if (!mounted) return;
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        await VisitasService.registrar(
          clienteCodigo: action.clienteResuelto!.codigo,
          clienteNombre: action.clienteResuelto!.nombre,
          latitud: pos.latitude,
          longitud: pos.longitude,
          motivo: action.motivo ?? 'Visita comercial',
          notas: action.nota.isNotEmpty ? action.nota : null,
        );
      } else {
        await ActividadesService.registrar(
          clienteCodigo: action.clienteResuelto?.codigo ?? '',
          clienteNombre: action.clienteResuelto?.nombre ?? action.clienteMatch ?? '',
          tipo: action.accion,
          descripcion: action.nota,
          fechaProgramada: action.cuando,
          origen: 'cronos',
        );
        if (action.cuando != null) {
          final dt = DateTime.tryParse(action.cuando!);
          if (dt != null && dt.isAfter(DateTime.now())) {
            final cliente = action.clienteResuelto?.nombre ?? action.clienteMatch ?? '';
            await NotificationService.schedule(
              id: DateTime.now().millisecondsSinceEpoch % 100000,
              title: '${action.accionLabel}${cliente.isNotEmpty ? " — $cliente" : ""}',
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
        title: Row(
          children: [
            _CronosBadge(),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Cronos', style: AppTextStyles.title),
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
                        onConfirm: _confirmAction,
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

  @override
  Widget build(BuildContext context) {
    final nombre = Session.current.vendedorNombre.split(' ').first;
    final suggestions = [
      ('💡 Recordame llamar a García mañana a las 10', Icons.phone_outlined),
      ('📋 ¿Qué tengo pendiente hoy?', Icons.checklist),
      ('📅 Agendá reunión con Pérez el jueves a las 15', Icons.event),
      ('🚀 Propuesta comercial para Rodríguez la semana que viene', Icons.rocket_launch_outlined),
    ];

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const SizedBox(height: 20),
            _HeroIcon(),
            const SizedBox(height: 24),
            Text('Hola $nombre', style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 24, fontWeight: FontWeight.w600,
            )),
            const SizedBox(height: 6),
            const Text(
              'Soy Cronos, tu asistente de agenda.\nDecime qué tenés que hacer.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.textSecondary, fontSize: 13, height: 1.4),
            ),
            const SizedBox(height: 32),
            ...suggestions.asMap().entries.map((e) => _AnimatedChip(
                  index: e.key,
                  text: e.value.$1,
                  icon: e.value.$2,
                  onTap: () => onChip(e.value.$1.replaceFirst(RegExp(r'^[^\s]+\s'), '')),
                )),
            const SizedBox(height: 24),
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
          ],
        ),
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
  final Future<void> Function(AssistantAction) onConfirm;

  const _MessageBubble({
    super.key,
    required this.msg,
    required this.confirmadas,
    required this.onConfirm,
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

  @override
  Widget build(BuildContext context) {
    final m = widget.msg;
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
                    child: _ActionCard(
                      action: a,
                      confirmada: widget.confirmadas.contains(a),
                      onConfirm: () => widget.onConfirm(a),
                    ),
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
  final VoidCallback onConfirm;

  const _ActionCard({
    required this.action,
    required this.confirmada,
    required this.onConfirm,
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
                if (action.esVisitaAhora)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Row(
                      children: [
                        const Icon(Icons.my_location, size: 14, color: AppColors.success),
                        const SizedBox(width: 6),
                        Text('VISITA CON GPS AHORA',
                            style: TextStyle(
                              color: AppColors.success,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 1,
                            )),
                      ],
                    ),
                  ),
                if (action.tieneCliente)
                  _row(Icons.person, 'Cliente',
                      '${action.clienteResuelto!.nombre} (${action.clienteResuelto!.codigo})')
                else if (action.clienteMatch != null)
                  _row(Icons.person_search, 'Cliente',
                      '${action.clienteMatch} (no encontrado)'),
                if (!action.esVisitaAhora)
                  _row(Icons.category_outlined, 'Acción', action.accionLabel),
                if (action.esVisitaAhora)
                  _row(Icons.badge_outlined, 'Motivo', action.motivo ?? 'Visita comercial'),
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
                        confirmada
                            ? Icons.check_circle
                            : (action.esVisitaAhora ? Icons.my_location : Icons.check),
                        key: ValueKey(confirmada),
                        size: 16,
                      ),
                    ),
                    label: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 260),
                      child: Text(
                        confirmada
                            ? (action.esPendiente ? 'Completada'
                                : action.esVisitaAhora ? 'Visita registrada'
                                : 'Agendada')
                            : (action.esPendiente ? 'Completar'
                                : action.esVisitaAhora ? 'Cargar con mi ubicación'
                                : 'Confirmar'),
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

  _ChatMessage({
    required this.isUser,
    required this.text,
    this.actions,
    this.isError = false,
  });
}
