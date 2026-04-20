import 'package:flutter/material.dart';
import '../config/theme.dart';

/// Wrapper que aplica un efecto shimmer (brillo que se desplaza) a su child.
class _ShimmerBox extends StatelessWidget {
  final double? width;
  final double height;
  final double radius;
  final double progress; // 0..1 — avance del gradiente
  const _ShimmerBox({
    this.width,
    required this.height,
    required this.progress,
    this.radius = 4,
  });

  @override
  Widget build(BuildContext context) {
    // Gradiente 3 colores: base → highlight → base. La posición del highlight
    // se mueve de izquierda a derecha en función de progress.
    final base = AppColors.border.withOpacity(0.35);
    final highlight = AppColors.textMuted.withOpacity(0.25);
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        gradient: LinearGradient(
          begin: Alignment(-1.2 + progress * 2.4, 0),
          end: Alignment(-0.2 + progress * 2.4, 0),
          colors: [base, highlight, base],
          stops: const [0, 0.5, 1],
        ),
      ),
    );
  }
}

/// Tarjeta shimmer que simula una MetricCard mientras carga.
class SkeletonCard extends StatefulWidget {
  const SkeletonCard({super.key});

  @override
  State<SkeletonCard> createState() => _SkeletonCardState();
}

class _SkeletonCardState extends State<SkeletonCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, __) {
        final p = _ctrl.value;
        return Container(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.bgCard,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.border.withOpacity(0.3)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _ShimmerBox(width: 140, height: 14, progress: p),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(child: _ShimmerBox(height: 50, progress: p, radius: 8)),
                  const SizedBox(width: 12),
                  Expanded(child: _ShimmerBox(height: 50, progress: p, radius: 8)),
                ],
              ),
              const SizedBox(height: 14),
              _ShimmerBox(height: 8, progress: p),
              const SizedBox(height: 10),
              _ShimmerBox(width: 200, height: 10, progress: p),
            ],
          ),
        );
      },
    );
  }
}

/// Skeleton para la lista de clientes con shimmer.
class SkeletonClienteTile extends StatefulWidget {
  const SkeletonClienteTile({super.key});

  @override
  State<SkeletonClienteTile> createState() => _SkeletonClienteTileState();
}

class _SkeletonClienteTileState extends State<SkeletonClienteTile>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, __) {
        final p = _ctrl.value;
        return Container(
          margin: const EdgeInsets.only(bottom: 6),
          padding: const EdgeInsets.all(12),
          decoration: AppCardStyle.base(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(child: _ShimmerBox(width: 160, height: 13, progress: p)),
                  _ShimmerBox(width: 45, height: 16, progress: p),
                ],
              ),
              const SizedBox(height: 8),
              _ShimmerBox(width: 120, height: 10, progress: p),
              const SizedBox(height: 6),
              _ShimmerBox(width: 180, height: 10, progress: p),
            ],
          ),
        );
      },
    );
  }
}

/// Loader inicial del Scorecard — aparece ANTES de los skeletons,
/// muestra un icono animado + texto "Cargando objetivos...".
class ScorecardHeroLoader extends StatefulWidget {
  const ScorecardHeroLoader({super.key});
  @override
  State<ScorecardHeroLoader> createState() => _ScorecardHeroLoaderState();
}

class _ScorecardHeroLoaderState extends State<ScorecardHeroLoader>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 1800),
    )..repeat();
  }

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, __) {
        final t = _ctrl.value;
        final scale = 1 + 0.08 * (0.5 - (t - 0.5).abs()) * 2;
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 40),
          child: Column(
            children: [
              Transform.scale(
                scale: scale,
                child: Container(
                  width: 80, height: 80,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: const LinearGradient(
                      begin: Alignment.topLeft, end: Alignment.bottomRight,
                      colors: [AppColors.accent, AppColors.primary],
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.accent.withOpacity(0.3 + 0.3 * (0.5 - (t - 0.5).abs()) * 2),
                        blurRadius: 28, spreadRadius: 4,
                      ),
                    ],
                  ),
                  child: const Icon(Icons.bar_chart_rounded, color: Colors.white, size: 40),
                ),
              ),
              const SizedBox(height: 20),
              const Text('Cargando tus objetivos', style: TextStyle(
                color: AppColors.textPrimary, fontSize: 15, fontWeight: FontWeight.w600,
              )),
              const SizedBox(height: 6),
              _DotsIndicator(ctrl: _ctrl),
            ],
          ),
        );
      },
    );
  }
}

class _DotsIndicator extends StatelessWidget {
  final AnimationController ctrl;
  const _DotsIndicator({required this.ctrl});
  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(3, (i) {
        final phase = (ctrl.value - i * 0.2) % 1;
        final y = -3 * (phase < 0.3 ? (1 - (phase / 0.3 - 0.5).abs() * 2) : 0);
        final op = 0.35 + 0.65 * (phase < 0.3 ? 1 - (phase / 0.3 - 0.5).abs() * 2 : 0);
        return Padding(
          padding: EdgeInsets.only(right: i < 2 ? 5 : 0),
          child: Transform.translate(
            offset: Offset(0, y.toDouble()),
            child: Container(
              width: 6, height: 6,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.accent.withOpacity(op.clamp(0.3, 1.0)),
              ),
            ),
          ),
        );
      }),
    );
  }
}
