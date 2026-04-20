-- ============================================================================
--  Migración — campos extra para reporting rico (v3.6.0)
-- ============================================================================

-- 1. actividades_cliente.updated_at con trigger auto-update
ALTER TABLE actividades_cliente
  ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ DEFAULT NOW();

-- Backfill: las filas existentes usan created_at como updated_at inicial
UPDATE actividades_cliente
  SET updated_at = COALESCE(created_at, NOW())
  WHERE updated_at IS NULL;

-- Trigger: cualquier UPDATE refresca updated_at
CREATE OR REPLACE FUNCTION fn_actividades_cliente_upd()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_actividades_cliente_upd ON actividades_cliente;
CREATE TRIGGER trg_actividades_cliente_upd
  BEFORE UPDATE ON actividades_cliente
  FOR EACH ROW EXECUTE FUNCTION fn_actividades_cliente_upd();


-- 2. visitas.precision_m — precisión del fix GPS en metros
ALTER TABLE visitas
  ADD COLUMN IF NOT EXISTS precision_m DOUBLE PRECISION;


-- 3. visitas.vinculada_actividad_id — link a actividad agendada que esta visita cumple
ALTER TABLE visitas
  ADD COLUMN IF NOT EXISTS vinculada_actividad_id INTEGER;

-- FK opcional (con ON DELETE SET NULL para no romper si borran la actividad)
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.table_constraints
    WHERE constraint_name = 'visitas_vinculada_actividad_fk'
  ) THEN
    ALTER TABLE visitas
      ADD CONSTRAINT visitas_vinculada_actividad_fk
      FOREIGN KEY (vinculada_actividad_id)
      REFERENCES actividades_cliente(id)
      ON DELETE SET NULL;
  END IF;
END $$;

-- Indice para búsquedas por vinculación
CREATE INDEX IF NOT EXISTS idx_visitas_vinculada
  ON visitas(vinculada_actividad_id)
  WHERE vinculada_actividad_id IS NOT NULL;


-- Verificaciones
SELECT 'actividades_cliente.updated_at' AS campo,
       COUNT(*) FILTER (WHERE updated_at IS NOT NULL) AS con_valor,
       COUNT(*) AS total
FROM actividades_cliente
UNION ALL
SELECT 'visitas.precision_m', COUNT(*) FILTER (WHERE precision_m IS NOT NULL), COUNT(*)
FROM visitas
UNION ALL
SELECT 'visitas.vinculada_actividad_id',
       COUNT(*) FILTER (WHERE vinculada_actividad_id IS NOT NULL), COUNT(*)
FROM visitas;
