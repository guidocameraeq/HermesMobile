-- ============================================================================
--  Migración — proxy OpenAI (v3.8.0)
-- ============================================================================
--  Crea las 2 tablas que el proxy de OpenAI necesita:
--
--  - vendedor_tokens: token por vendedor para autenticar contra Edge Functions.
--    Se emite en login (auth-token function) y se usa en cada request a
--    cronos-chat / cronos-transcribe.
--
--  - uso_llm: tracking granular de cada llamada al LLM/Whisper. Permite
--    monitorear costo per-vendedor, detectar abuso, y aplicar rate limit
--    (las queries de rate limit cuentan filas de uso_llm en última hora).
-- ============================================================================

-- ── 1. vendedor_tokens ────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS vendedor_tokens (
  vendedor_nombre TEXT PRIMARY KEY,
  token TEXT NOT NULL UNIQUE,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  last_used_at TIMESTAMPTZ
);

CREATE INDEX IF NOT EXISTS idx_vendedor_tokens_lookup
  ON vendedor_tokens(token);

-- RLS: nadie accede via anon. Solo service_role (Edge Functions) puede
-- leer/escribir.
ALTER TABLE vendedor_tokens ENABLE ROW LEVEL SECURITY;

-- ── 2. uso_llm ────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS uso_llm (
  id BIGSERIAL PRIMARY KEY,
  vendedor_nombre TEXT NOT NULL,
  endpoint TEXT NOT NULL,                  -- 'chat' | 'transcribe'
  modelo TEXT,                             -- 'gpt-4o-mini', 'whisper-1'
  tokens_in INT,                           -- prompt_tokens (chat) o NULL
  tokens_out INT,                          -- completion_tokens (chat) o NULL
  audio_seg INT,                           -- duración del audio (transcribe) o NULL
  costo_usd_estimado NUMERIC(10,5),        -- calculado en la Edge Function
  latencia_ms INT,
  status_code INT NOT NULL,
  error TEXT,                              -- mensaje si status != 200
  created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_uso_llm_vendedor_fecha
  ON uso_llm(vendedor_nombre, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_uso_llm_costo_fecha
  ON uso_llm(created_at DESC, costo_usd_estimado);

-- Para rate limit: contar requests de un vendedor en última hora
CREATE INDEX IF NOT EXISTS idx_uso_llm_rate_limit
  ON uso_llm(vendedor_nombre, endpoint, created_at DESC)
  WHERE status_code = 200;

-- RLS: nadie via anon. Solo service_role.
ALTER TABLE uso_llm ENABLE ROW LEVEL SECURITY;

-- ── Verificación ──────────────────────────────────────────────────────────
SELECT tablename, rowsecurity
FROM pg_tables
WHERE schemaname = 'public'
  AND tablename IN ('vendedor_tokens', 'uso_llm')
ORDER BY tablename;
