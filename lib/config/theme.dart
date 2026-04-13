import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Paleta de colores centralizada — consistente con Hermes Desktop.
class AppColors {
  // ── Fondos ────────────────────────────────────────────────────
  static const bg = Color(0xFF0A0C10);
  static const bgSidebar = Color(0xFF161B22);
  static const bgCard = Color(0xFF1C2333);
  static const bgCardHover = Color(0xFF212A3D);
  static const bgInput = Color(0xFF1C2333);

  // ── Acentos ───────────────────────────────────────────────────
  static const primary = Color(0xFF2563EB);
  static const accent = Color(0xFF4A9EFF);

  // ── Estados ───────────────────────────────────────────────────
  static const success = Color(0xFF10B981);
  static const warning = Color(0xFFF59E0B);
  static const danger = Color(0xFFEF4444);

  // ── Texto ─────────────────────────────────────────────────────
  static const textPrimary = Color(0xFFF8FAFC);
  static const textSecondary = Color(0xFF94A3B8);
  static const textMuted = Color(0xFF64748B);

  // ── Bordes ────────────────────────────────────────────────────
  static const border = Color(0xFF2D3748);

  // ── Bottom Nav ────────────────────────────────────────────────
  static const navBg = Color(0xFF111827);
  static const navSelected = Color(0xFF2563EB);
  static const navUnselected = Color(0xFF64748B);
}

/// Estilos de texto reutilizables.
class AppTextStyles {
  static const title = TextStyle(
    color: AppColors.textPrimary,
    fontSize: 16,
    fontWeight: FontWeight.w600,
  );
  static const body = TextStyle(
    color: AppColors.textPrimary,
    fontSize: 14,
  );
  static const caption = TextStyle(
    color: AppColors.textSecondary,
    fontSize: 12,
  );
  static const muted = TextStyle(
    color: AppColors.textMuted,
    fontSize: 11,
  );
  static const h1 = TextStyle(
    color: AppColors.textPrimary,
    fontSize: 28,
    fontWeight: FontWeight.bold,
    letterSpacing: 1.5,
  );
  static const subtitle = TextStyle(
    color: AppColors.textSecondary,
    fontSize: 14,
  );
}

/// Decoración estándar de tarjetas.
class AppCardStyle {
  static BoxDecoration base({Color? borderColor}) => BoxDecoration(
        color: AppColors.bgCard,
        borderRadius: BorderRadius.circular(12),
        border: borderColor != null
            ? Border.all(color: borderColor.withOpacity(0.4), width: 1)
            : null,
      );
}

/// ThemeData completo para MaterialApp.
ThemeData buildAppTheme() {
  return ThemeData(
    brightness: Brightness.dark,
    colorScheme: const ColorScheme.dark(
      primary: AppColors.primary,
      secondary: AppColors.accent,
      surface: AppColors.bgCard,
      error: AppColors.danger,
    ),
    scaffoldBackgroundColor: AppColors.bg,
    fontFamily: 'Roboto',
    useMaterial3: true,
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.bgSidebar,
      foregroundColor: AppColors.textPrimary,
      elevation: 0,
      systemOverlayStyle: SystemUiOverlayStyle(
        statusBarColor: AppColors.bgSidebar,
        statusBarIconBrightness: Brightness.light,
      ),
    ),
    inputDecorationTheme: const InputDecorationTheme(
      filled: true,
      fillColor: AppColors.bgInput,
    ),
    bottomNavigationBarTheme: const BottomNavigationBarThemeData(
      backgroundColor: AppColors.navBg,
      selectedItemColor: AppColors.navSelected,
      unselectedItemColor: AppColors.navUnselected,
      type: BottomNavigationBarType.fixed,
      selectedLabelStyle: TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
      unselectedLabelStyle: TextStyle(fontSize: 11),
      elevation: 8,
    ),
  );
}
