import 'package:flutter/material.dart';
import '../config/theme.dart';

class KpiCard extends StatelessWidget {
  final String label;
  final String value;
  final String? subtitle;
  final Color? valueColor;
  final IconData? icon;

  const KpiCard({
    super.key,
    required this.label,
    required this.value,
    this.subtitle,
    this.valueColor,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: AppCardStyle.base(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (icon != null) ...[
                Icon(icon, size: 14, color: AppColors.textMuted),
                const SizedBox(width: 6),
              ],
              Expanded(
                child: Text(label, style: AppTextStyles.muted,
                    maxLines: 1, overflow: TextOverflow.ellipsis),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: TextStyle(
              color: valueColor ?? AppColors.textPrimary,
              fontSize: 17,
              fontWeight: FontWeight.bold,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 2),
            Text(subtitle!, style: AppTextStyles.muted,
                maxLines: 1, overflow: TextOverflow.ellipsis),
          ],
        ],
      ),
    );
  }
}
