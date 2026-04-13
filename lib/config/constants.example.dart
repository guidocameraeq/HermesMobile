/// Configuración de conexión a bases de datos.
/// COPIA este archivo como constants.dart y completá con las credenciales reales.
/// constants.dart está excluido del repo (.gitignore).
class AppConfig {
  // ── Supabase / PostgreSQL ─────────────────────────────────────
  static const String pgHost = 'TU_HOST.pooler.supabase.com';
  static const int pgPort = 5432;
  static const String pgDb = 'postgres';
  static const String pgUser = 'postgres.TU_PROJECT_ID';
  static const String pgPass = 'TU_PASSWORD_SUPABASE';

  // ── SQL Server (red interna — requiere VPN) ───────────────────
  static const String sqlHost = '192.168.1.X';
  static const String sqlPort = '1433';
  static const String sqlDb = 'TU_DATABASE';
  static const String sqlUser = 'TU_USUARIO';
  static const String sqlPass = 'TU_PASSWORD';
  static const String sqlInstance = 'TU_INSTANCIA';
}
