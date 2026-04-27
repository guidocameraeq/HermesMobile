-- ============================================================================
--  Migración — app_config (v3.6.1)
-- ============================================================================
--  Tabla key-value para configuración remota de la app sin necesidad de
--  recompilar/releasear. Hoy se usa para:
--    - min_version_required: versión mínima que se acepta. Si la versión
--      local es menor, la app muestra ForceUpdateScreen al login y bloquea
--      hasta que el vendedor actualice.
--
--  Cómo forzar un update a todos los vendedores:
--    UPDATE app_config SET value='3.6.1', updated_at=NOW()
--    WHERE key='min_version_required';
--
--  Cómo deshabilitar el force update (volver a permisivo):
--    UPDATE app_config SET value='3.0.0', updated_at=NOW()
--    WHERE key='min_version_required';
-- ============================================================================

CREATE TABLE IF NOT EXISTS app_config (
  key TEXT PRIMARY KEY,
  value TEXT NOT NULL,
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Valor inicial permisivo: cualquier versión >= 3.0.0 puede entrar.
-- Subimos solo cuando hace falta forzar update (bugfix crítico, etc).
INSERT INTO app_config (key, value)
VALUES ('min_version_required', '3.0.0')
ON CONFLICT (key) DO NOTHING;

-- Verificación
SELECT key, value, updated_at FROM app_config ORDER BY key;
