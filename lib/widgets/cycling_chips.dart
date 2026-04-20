import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../config/theme.dart';

/// Sugerencia con texto + icono + categoría.
class ChipSuggestion {
  final IconData icon;
  final String text;
  final Color color;
  const ChipSuggestion(this.icon, this.text, [this.color = AppColors.accent]);
}

/// Lista de chips que rotan estilo ticker: cada N segundos el de arriba
/// sale deslizándose y uno nuevo entra por abajo.
class CyclingChips extends StatefulWidget {
  final List<ChipSuggestion> pool;
  final int visibleCount;
  final Duration interval;
  final void Function(String) onTap;

  const CyclingChips({
    super.key,
    required this.pool,
    required this.onTap,
    this.visibleCount = 4,
    this.interval = const Duration(seconds: 4),
  });

  @override
  State<CyclingChips> createState() => _CyclingChipsState();
}

class _CyclingChipsState extends State<CyclingChips> {
  final GlobalKey<AnimatedListState> _listKey = GlobalKey<AnimatedListState>();
  late List<ChipSuggestion> _visible;
  int _nextIndex = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _visible = [];
    // Inicializar con visibleCount elementos del pool
    for (int i = 0; i < widget.visibleCount && i < widget.pool.length; i++) {
      _visible.add(widget.pool[i]);
      _nextIndex = (i + 1) % widget.pool.length;
    }
    // Insertar uno por uno con delay para la animación de entrada inicial
    Future.delayed(const Duration(milliseconds: 200), _startCycle);
  }

  void _startCycle() {
    if (!mounted) return;
    _timer = Timer.periodic(widget.interval, (_) => _rotate());
  }

  void _rotate() {
    if (!mounted || widget.pool.length <= widget.visibleCount) return;

    // Sacar el primero
    final removed = _visible.removeAt(0);
    _listKey.currentState?.removeItem(
      0,
      (ctx, anim) => _buildAnimated(removed, anim, exiting: true),
      duration: const Duration(milliseconds: 360),
    );

    // Agregar uno nuevo al final
    final nuevo = widget.pool[_nextIndex];
    _nextIndex = (_nextIndex + 1) % widget.pool.length;
    _visible.add(nuevo);
    _listKey.currentState?.insertItem(
      _visible.length - 1,
      duration: const Duration(milliseconds: 360),
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedList(
      key: _listKey,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      initialItemCount: _visible.length,
      itemBuilder: (ctx, i, anim) => _buildAnimated(_visible[i], anim),
    );
  }

  Widget _buildAnimated(ChipSuggestion s, Animation<double> anim, {bool exiting = false}) {
    // Animación: slide up + fade
    final slide = Tween<Offset>(
      begin: exiting ? const Offset(0, -0.8) : const Offset(0, 0.8),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: anim, curve: Curves.easeOutCubic));

    final fade = CurvedAnimation(parent: anim, curve: Curves.easeOut);

    return SizeTransition(
      sizeFactor: anim,
      axisAlignment: -1,
      child: FadeTransition(
        opacity: fade,
        child: SlideTransition(
          position: slide,
          child: Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: _Chip(
              suggestion: s,
              onTap: () {
                HapticFeedback.selectionClick();
                // Extraer texto sin prefijo "💡 " o similares
                widget.onTap(s.text);
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  final ChipSuggestion suggestion;
  final VoidCallback onTap;
  const _Chip({required this.suggestion, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: AppColors.bgCard,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: suggestion.color.withOpacity(0.18)),
        ),
        child: Row(
          children: [
            Container(
              width: 32, height: 32,
              decoration: BoxDecoration(
                color: suggestion.color.withOpacity(0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(suggestion.icon, color: suggestion.color, size: 16),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                suggestion.text,
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 13,
                  height: 1.3,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 6),
            Icon(Icons.north_east, color: suggestion.color.withOpacity(0.7), size: 14),
          ],
        ),
      ),
    );
  }
}
