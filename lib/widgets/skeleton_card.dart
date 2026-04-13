import 'package:flutter/material.dart';
import '../config/theme.dart';

/// Tarjeta shimmer que simula una MetricCard mientras carga.
class SkeletonCard extends StatefulWidget {
  const SkeletonCard({super.key});

  @override
  State<SkeletonCard> createState() => _SkeletonCardState();
}

class _SkeletonCardState extends State<SkeletonCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
    _anim = Tween<double>(begin: 0.3, end: 0.7).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _anim,
      builder: (_, __) {
        final opacity = _anim.value;
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
              // Título
              _bar(width: 140, height: 14, opacity: opacity),
              const SizedBox(height: 14),
              // Dos cajas (Real / Meta)
              Row(
                children: [
                  Expanded(child: _box(height: 50, opacity: opacity)),
                  const SizedBox(width: 12),
                  Expanded(child: _box(height: 50, opacity: opacity)),
                ],
              ),
              const SizedBox(height: 14),
              // Barra de progreso
              _bar(width: double.infinity, height: 8, opacity: opacity),
              const SizedBox(height: 10),
              // Texto inferior
              _bar(width: 200, height: 10, opacity: opacity),
            ],
          ),
        );
      },
    );
  }

  Widget _bar({required double height, required double opacity, double? width}) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: AppColors.border.withOpacity(opacity),
        borderRadius: BorderRadius.circular(4),
      ),
    );
  }

  Widget _box({required double height, required double opacity}) {
    return Container(
      height: height,
      decoration: BoxDecoration(
        color: AppColors.bg.withOpacity(opacity),
        borderRadius: BorderRadius.circular(8),
      ),
    );
  }
}

/// Skeleton para la lista de clientes.
class SkeletonClienteTile extends StatefulWidget {
  const SkeletonClienteTile({super.key});

  @override
  State<SkeletonClienteTile> createState() => _SkeletonClienteTileState();
}

class _SkeletonClienteTileState extends State<SkeletonClienteTile>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
    _anim = Tween<double>(begin: 0.3, end: 0.7).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _anim,
      builder: (_, __) {
        final op = _anim.value;
        return Container(
          margin: const EdgeInsets.only(bottom: 6),
          padding: const EdgeInsets.all(12),
          decoration: AppCardStyle.base(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(child: _bar(160, 13, op)),
                  _bar(45, 16, op),
                ],
              ),
              const SizedBox(height: 8),
              _bar(120, 10, op),
              const SizedBox(height: 6),
              _bar(180, 10, op),
            ],
          ),
        );
      },
    );
  }

  Widget _bar(double w, double h, double op) {
    return Container(
      width: w, height: h,
      decoration: BoxDecoration(
        color: AppColors.border.withOpacity(op),
        borderRadius: BorderRadius.circular(4),
      ),
    );
  }
}
