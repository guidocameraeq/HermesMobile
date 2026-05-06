-- ============================================================================
--  Migración — RLS en app_config y cronos_logs (v3.7.3)
-- ============================================================================
--  Habilita Row Level Security en las tablas que faltaban. No protege HOY
--  porque la app conecta como rol `postgres` (admin) que bypassea RLS, pero
--  deja la base lista para cuando migremos a Edge Functions con anon key
--  + JWT — ahí RLS se vuelve la única defensa.
-- ============================================================================

-- 1) app_config: lectura pública (todos los vendedores leen min_version),
--    escritura solo desde service_role (Edge Functions / admin SQL).
ALTER TABLE app_config ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS app_config_read_all ON app_config;
CREATE POLICY app_config_read_all
  ON app_config FOR SELECT
  USING (true);

-- Sin política de INSERT/UPDATE/DELETE → bloqueado para anon.
-- service_role bypassea RLS automáticamente.

-- 2) cronos_logs: cada vendedor solo puede ver/insertar SUS propios logs.
--    Para que esto funcione cuando migremos a JWT, asumimos que el JWT
--    incluye un claim `vendedor_nombre` accesible vía auth.jwt().
ALTER TABLE cronos_logs ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS cronos_logs_select_own ON cronos_logs;
CREATE POLICY cronos_logs_select_own
  ON cronos_logs FOR SELECT
  USING (
    -- Cuando uses JWT con claim vendedor_nombre:
    vendedor_nombre = (auth.jwt() ->> 'vendedor_nombre')
    -- O si todavía conectas como postgres, esto siempre devuelve true
    -- porque postgres bypassea RLS de todas formas.
  );

DROP POLICY IF EXISTS cronos_logs_insert_own ON cronos_logs;
CREATE POLICY cronos_logs_insert_own
  ON cronos_logs FOR INSERT
  WITH CHECK (
    vendedor_nombre = (auth.jwt() ->> 'vendedor_nombre')
  );

-- DELETE/UPDATE: nadie. Los logs son inmutables.

-- Verificación
SELECT tablename, rowsecurity
FROM pg_tables
WHERE schemaname = 'public'
  AND tablename IN ('app_config', 'cronos_logs')
ORDER BY tablename;
