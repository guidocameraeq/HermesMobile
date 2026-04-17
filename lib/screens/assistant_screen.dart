import 'package:flutter/material.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import '../config/theme.dart';
import '../models/session.dart';
import '../services/assistant_service.dart';
import '../services/actividades_service.dart';

class AssistantScreen extends StatefulWidget {
  const AssistantScreen({super.key});

  @override
  State<AssistantScreen> createState() => _AssistantState();
}

class _AssistantState extends State<AssistantScreen> {
  final _textCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  final _messages = <_ChatMessage>[];
  bool _sending = false;

  // Speech to text
  final stt.SpeechToText _speech = stt.SpeechToText();
  bool _speechAvailable = false;
  bool _isListening = false;

  @override
  void initState() {
    super.initState();
    _initSpeech();
    // Mensaje de bienvenida
    _messages.add(_ChatMessage(
      isUser: false,
      text: 'Hola ${Session.current.vendedorNombre.split(' ').first}, soy tu asistente. '
          'Decime qué necesitás y lo anoto.\n\n'
          'Podés escribir o usar el micrófono. Por ejemplo:\n'
          '"Recordame mañana a las 10 que llame a García"',
    ));
  }

  Future<void> _initSpeech() async {
    _speechAvailable = await _speech.initialize(
      onError: (error) {
        if (mounted) setState(() => _isListening = false);
      },
      onStatus: (status) {
        if (status == 'done' || status == 'notListening') {
          if (mounted) setState(() => _isListening = false);
        }
      },
    );
    setState(() {});
  }

  void _startListening() {
    if (!_speechAvailable) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Micrófono no disponible'), backgroundColor: AppColors.danger),
      );
      return;
    }
    setState(() => _isListening = true);
    _speech.listen(
      onResult: (result) {
        if (result.finalResult) {
          _textCtrl.text = result.recognizedWords;
          setState(() => _isListening = false);
        }
      },
      localeId: 'es_AR',
      listenFor: const Duration(seconds: 30),
      pauseFor: const Duration(seconds: 3),
    );
  }

  void _stopListening() {
    _speech.stop();
    setState(() => _isListening = false);
  }

  Future<void> _send() async {
    final text = _textCtrl.text.trim();
    if (text.isEmpty || _sending) return;

    setState(() {
      _messages.add(_ChatMessage(isUser: true, text: text));
      _sending = true;
    });
    _textCtrl.clear();
    _scrollToBottom();

    try {
      final action = await AssistantService.sendMessage(text);

      if (!mounted) return;

      if (action.esActividad) {
        setState(() {
          _messages.add(_ChatMessage(
            isUser: false,
            text: action.mensaje,
            action: action,
          ));
        });
      } else {
        setState(() {
          _messages.add(_ChatMessage(isUser: false, text: action.mensaje));
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _messages.add(_ChatMessage(
          isUser: false,
          text: 'Error: ${e.toString().replaceFirst('Exception: ', '')}',
          isError: true,
        ));
      });
    } finally {
      if (mounted) setState(() => _sending = false);
      _scrollToBottom();
    }
  }

  void _scrollToBottom() {
    Future.delayed(const Duration(milliseconds: 100), () {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(
          _scrollCtrl.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _confirmAction(AssistantAction action) async {
    try {
      await ActividadesService.registrar(
        clienteCodigo: action.clienteResuelto?.codigo ?? '',
        clienteNombre: action.clienteResuelto?.nombre ?? action.clienteMatch ?? '',
        tipo: action.accion,
        descripcion: action.nota,
        fechaProgramada: action.cuando,
        origen: 'hermes_flash',
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Actividad guardada: ${action.accionLabel}'
            '${action.tieneCliente ? " — ${action.clienteResuelto!.nombre}" : ""}',
          ),
          backgroundColor: AppColors.success,
          duration: const Duration(seconds: 3),
        ),
      );
      setState(() {
        _messages.add(_ChatMessage(isUser: false, text: 'Guardado en la historia del cliente.'));
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error al guardar: $e'), backgroundColor: AppColors.danger),
      );
    }
    _scrollToBottom();
  }

  @override
  void dispose() {
    _textCtrl.dispose();
    _scrollCtrl.dispose();
    _speech.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.bgSidebar,
        title: const Row(
          children: [
            Icon(Icons.flash_on, color: AppColors.accent, size: 20),
            SizedBox(width: 8),
            Text('Hermes Flash', style: AppTextStyles.title),
          ],
        ),
      ),
      body: Column(
        children: [
          // Chat messages
          Expanded(
            child: ListView.builder(
              controller: _scrollCtrl,
              padding: const EdgeInsets.all(12),
              itemCount: _messages.length,
              itemBuilder: (_, i) => _buildMessage(_messages[i]),
            ),
          ),
          // Indicador de "escribiendo"
          if (_sending)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Row(
                children: [
                  SizedBox(width: 16, height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.accent)),
                  SizedBox(width: 8),
                  Text('Pensando...', style: AppTextStyles.muted),
                ],
              ),
            ),
          // Indicador de escuchando
          if (_isListening)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              color: AppColors.danger.withOpacity(0.1),
              child: const Row(
                children: [
                  Icon(Icons.mic, color: AppColors.danger, size: 20),
                  SizedBox(width: 8),
                  Text('Escuchando...', style: TextStyle(color: AppColors.danger, fontSize: 13)),
                  Spacer(),
                  Text('Hablá y esperá', style: AppTextStyles.muted),
                ],
              ),
            ),
          // Input bar
          _buildInputBar(),
        ],
      ),
    );
  }

  Widget _buildMessage(_ChatMessage msg) {
    return Align(
      alignment: msg.isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(12),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.82,
        ),
        decoration: BoxDecoration(
          color: msg.isUser
              ? AppColors.primary
              : msg.isError
                  ? AppColors.danger.withOpacity(0.15)
                  : AppColors.bgCard,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(14),
            topRight: const Radius.circular(14),
            bottomLeft: Radius.circular(msg.isUser ? 14 : 4),
            bottomRight: Radius.circular(msg.isUser ? 4 : 14),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              msg.text,
              style: TextStyle(
                color: msg.isUser
                    ? Colors.white
                    : msg.isError
                        ? AppColors.danger
                        : AppColors.textPrimary,
                fontSize: 13,
              ),
            ),
            if (msg.action != null) ...[
              const SizedBox(height: 10),
              _buildActionCard(msg.action!),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildActionCard(AssistantAction action) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.bg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.accent.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (action.tieneCliente)
            _actionRow(Icons.person, 'Cliente',
                '${action.clienteResuelto!.nombre} (${action.clienteResuelto!.codigo})')
          else if (action.clienteMatch != null)
            _actionRow(Icons.person_search, 'Cliente',
                '${action.clienteMatch} (no encontrado)'),
          _actionRow(Icons.category, 'Acción', action.accionLabel),
          if (action.cuando != null)
            _actionRow(Icons.schedule, 'Cuándo', action.cuandoFmt),
          if (action.nota.isNotEmpty)
            _actionRow(Icons.note, 'Nota', action.nota),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () => _confirmAction(action),
                  icon: const Icon(Icons.check, size: 16),
                  label: const Text('Confirmar', style: TextStyle(fontSize: 13)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.success,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    padding: const EdgeInsets.symmetric(vertical: 8),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _actionRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 14, color: AppColors.accent),
          const SizedBox(width: 8),
          SizedBox(width: 55, child: Text('$label:', style: AppTextStyles.muted)),
          Expanded(child: Text(value, style: AppTextStyles.body)),
        ],
      ),
    );
  }

  Widget _buildInputBar() {
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 12),
      decoration: const BoxDecoration(
        color: AppColors.bgSidebar,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            // Botón micrófono
            GestureDetector(
              onTap: _isListening ? _stopListening : _startListening,
              child: Container(
                width: 44, height: 44,
                decoration: BoxDecoration(
                  color: _isListening ? AppColors.danger : AppColors.accent.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(22),
                ),
                child: Icon(
                  _isListening ? Icons.stop : Icons.mic,
                  color: _isListening ? Colors.white : AppColors.accent,
                  size: 22,
                ),
              ),
            ),
            const SizedBox(width: 8),
            // Campo de texto
            Expanded(
              child: TextField(
                controller: _textCtrl,
                style: AppTextStyles.body,
                maxLines: 3,
                minLines: 1,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => _send(),
                decoration: InputDecoration(
                  hintText: 'Escribí o hablá...',
                  hintStyle: AppTextStyles.muted,
                  filled: true,
                  fillColor: AppColors.bgCard,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(20),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                ),
              ),
            ),
            const SizedBox(width: 8),
            // Botón enviar
            GestureDetector(
              onTap: _sending ? null : _send,
              child: Container(
                width: 44, height: 44,
                decoration: BoxDecoration(
                  color: AppColors.primary,
                  borderRadius: BorderRadius.circular(22),
                ),
                child: const Icon(Icons.send, color: Colors.white, size: 20),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ChatMessage {
  final bool isUser;
  final String text;
  final AssistantAction? action;
  final bool isError;

  _ChatMessage({
    required this.isUser,
    required this.text,
    this.action,
    this.isError = false,
  });
}
