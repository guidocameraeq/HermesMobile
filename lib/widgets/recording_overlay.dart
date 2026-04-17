import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../config/theme.dart';
import '../services/whisper_service.dart';

/// Overlay full-screen que muestra durante la grabación de voz.
/// Devuelve el path del audio grabado al stop, o null si cancela.
class RecordingOverlay extends StatefulWidget {
  const RecordingOverlay({super.key});

  /// Abre el overlay como modal. Retorna el path del audio o null.
  static Future<String?> show(BuildContext context) async {
    return showGeneralDialog<String>(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black87,
      transitionDuration: const Duration(milliseconds: 180),
      pageBuilder: (ctx, _, __) => const RecordingOverlay(),
      transitionBuilder: (ctx, anim, __, child) => FadeTransition(
        opacity: anim,
        child: ScaleTransition(
          scale: Tween(begin: 0.9, end: 1.0).animate(
            CurvedAnimation(parent: anim, curve: Curves.easeOutCubic),
          ),
          child: child,
        ),
      ),
    );
  }

  @override
  State<RecordingOverlay> createState() => _RecordingOverlayState();
}

class _RecordingOverlayState extends State<RecordingOverlay>
    with SingleTickerProviderStateMixin {
  Duration _elapsed = Duration.zero;
  Timer? _timer;
  double _amplitude = 0;
  StreamSubscription? _ampSub;
  bool _completed = false; // evita doble cleanup

  @override
  void initState() {
    super.initState();
    HapticFeedback.mediumImpact();
    _start();
  }

  Future<void> _start() async {
    try {
      await WhisperService.start();
      _timer = Timer.periodic(const Duration(milliseconds: 100), (_) {
        if (mounted) setState(() => _elapsed = WhisperService.elapsed);
      });
      _ampSub = WhisperService.amplitudeStream().listen((v) {
        if (mounted) setState(() => _amplitude = v);
      });
    } catch (e) {
      if (mounted) {
        Navigator.pop(context, null);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No se pudo iniciar la grabación: $e'),
              backgroundColor: AppColors.danger),
        );
      }
    }
  }

  Future<void> _stop() async {
    if (_completed) return;
    _completed = true;
    HapticFeedback.lightImpact();
    _timer?.cancel();
    await _ampSub?.cancel();
    final path = await WhisperService.stop();
    if (!mounted) return;
    Navigator.of(context).pop(path);
  }

  Future<void> _cancel() async {
    if (_completed) return;
    _completed = true;
    HapticFeedback.lightImpact();
    _timer?.cancel();
    await _ampSub?.cancel();
    await WhisperService.cancel();
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _ampSub?.cancel();
    // Si se cerró por back/gesto sin usar Listo/Cancelar, limpiar grabación
    if (!_completed) {
      WhisperService.cancel();
    }
    super.dispose();
  }

  String get _timeStr {
    final m = _elapsed.inMinutes.toString().padLeft(1, '0');
    final s = (_elapsed.inSeconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _PulseCircle(amplitude: _amplitude),
            const SizedBox(height: 40),
            Text(_timeStr, style: const TextStyle(
              color: Colors.white, fontSize: 36,
              fontWeight: FontWeight.w300, letterSpacing: 2,
            )),
            const SizedBox(height: 8),
            const Text('Grabando...',
                style: TextStyle(color: Colors.white60, fontSize: 13)),
            const SizedBox(height: 60),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _RoundBtn(
                  icon: Icons.close,
                  color: AppColors.danger,
                  small: true,
                  label: 'Cancelar',
                  onTap: _cancel,
                ),
                const SizedBox(width: 32),
                _RoundBtn(
                  icon: Icons.check,
                  color: AppColors.success,
                  small: false,
                  label: 'Listo',
                  onTap: _stop,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _PulseCircle extends StatefulWidget {
  final double amplitude;
  const _PulseCircle({required this.amplitude});

  @override
  State<_PulseCircle> createState() => _PulseCircleState();
}

class _PulseCircleState extends State<_PulseCircle>
    with TickerProviderStateMixin {
  late final AnimationController _baseCtrl;

  @override
  void initState() {
    super.initState();
    _baseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat();
  }

  @override
  void dispose() {
    _baseCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final extraSize = 40 + (widget.amplitude * 80);
    return AnimatedBuilder(
      animation: _baseCtrl,
      builder: (_, __) {
        // Dos aros pulsantes con delay
        return SizedBox(
          width: 260,
          height: 260,
          child: Stack(
            alignment: Alignment.center,
            children: [
              _ring(_baseCtrl.value, extraSize.toDouble()),
              _ring((_baseCtrl.value + 0.5) % 1, extraSize.toDouble()),
              // Núcleo reactivo
              AnimatedContainer(
                duration: const Duration(milliseconds: 100),
                width: 100 + (widget.amplitude * 30),
                height: 100 + (widget.amplitude * 30),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      AppColors.accent,
                      AppColors.primary,
                    ],
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.accent.withOpacity(0.4 + widget.amplitude * 0.4),
                      blurRadius: 30 + widget.amplitude * 40,
                      spreadRadius: 4 + widget.amplitude * 10,
                    ),
                  ],
                ),
                child: const Icon(Icons.mic, color: Colors.white, size: 44),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _ring(double t, double extra) {
    final size = 120 + t * (140 + extra);
    final opacity = (1 - t).clamp(0.0, 1.0);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: AppColors.accent.withOpacity(opacity * 0.5),
          width: 2,
        ),
      ),
    );
  }
}

class _RoundBtn extends StatelessWidget {
  final IconData icon;
  final Color color;
  final bool small;
  final String label;
  final VoidCallback onTap;

  const _RoundBtn({
    required this.icon,
    required this.color,
    required this.small,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final size = small ? 56.0 : 72.0;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        GestureDetector(
          onTap: onTap,
          child: Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color,
              boxShadow: [
                BoxShadow(
                  color: color.withOpacity(0.4),
                  blurRadius: 18,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: Icon(icon, color: Colors.white, size: small ? 24 : 32),
          ),
        ),
        const SizedBox(height: 8),
        Text(label, style: const TextStyle(color: Colors.white70, fontSize: 12)),
      ],
    );
  }
}
