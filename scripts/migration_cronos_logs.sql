-- ============================================================================
--  Migración — cronos_logs (v3.6.0)
-- ============================================================================
--  Tabla de logs estructurados de turnos del LLM Cronos.
--  Sirve para observabilidad: detectar parse failures, latencias altas,
--  iterar el system prompt con datos reales de uso.
--
--  El logger escribe fire-and-forget (sin await) desde la app — si falla
--  por VPN/conectividad, no afecta la conversación.
-- ============================================================================

CREATE TABLE IF NOT EXISTS cronos_logs (
  id BIGSERIAL PRIMARY KEY,
  vendedor_nombre TEXT NOT NULL,
  user_msg TEXT NOT NULL,
  response_raw TEXT,
  response_mensaje TEXT,
  acciones_count INT DEFAULT 0,
  parse_ok BOOLEAN DEFAULT TRUE,
  latencia_ms INT,
  modelo TEXT,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Lookup principal: ver últimos turnos de un vendedor
CREATE INDEX IF NOT EXISTS idx_cronos_logs_vendedor_fecha
  ON cronos_logs(vendedor_nombre, created_at DESC);

-- Lookup operativo: encontrar parse failures recientes
CREATE INDEX IF NOT EXISTS idx_cronos_logs_parse_fail
  ON cronos_logs(created_at DESC) WHERE parse_ok = FALSE;

-- Verificación
SELECT 'cronos_logs creada' AS status,
       COUNT(*) AS filas_existentes
FROM cronos_logs;
