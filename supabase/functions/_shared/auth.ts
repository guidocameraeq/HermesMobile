// Helpers compartidos para auth y logging de las Edge Functions de Cronos.
// Importable desde auth-token, cronos-chat, cronos-transcribe.

import { createClient, SupabaseClient } from 'jsr:@supabase/supabase-js@2';

/** Cliente Postgres con service_role (bypassea RLS, full access). */
export function adminClient(): SupabaseClient {
  return createClient(
    Deno.env.get('SUPABASE_URL') ?? '',
    Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '',
    { auth: { persistSession: false } },
  );
}

/** Resuelve el vendedor a partir del header Authorization: Bearer <token>.
 *  Retorna nombre del vendedor o null si el token no existe. */
export async function authVendedor(req: Request): Promise<string | null> {
  const authHeader = req.headers.get('Authorization') ?? '';
  if (!authHeader.startsWith('Bearer ')) return null;
  const token = authHeader.slice(7).trim();
  if (!token) return null;

  const sb = adminClient();
  const { data, error } = await sb
    .from('vendedor_tokens')
    .select('vendedor_nombre')
    .eq('token', token)
    .maybeSingle();

  if (error || !data) return null;

  // Update last_used_at fire-and-forget (no bloqueamos la request)
  sb.from('vendedor_tokens')
    .update({ last_used_at: new Date().toISOString() })
    .eq('vendedor_nombre', data.vendedor_nombre)
    .then(() => {});

  return data.vendedor_nombre as string;
}

/** Cuenta requests exitosos del vendedor en el endpoint en últimas N horas.
 *  Usado para rate limit. */
export async function countRecentRequests(
  vendedorNombre: string,
  endpoint: 'chat' | 'transcribe',
  hours: number,
): Promise<number> {
  const sb = adminClient();
  const cutoff = new Date(Date.now() - hours * 3600_000).toISOString();
  const { count, error } = await sb
    .from('uso_llm')
    .select('*', { count: 'exact', head: true })
    .eq('vendedor_nombre', vendedorNombre)
    .eq('endpoint', endpoint)
    .eq('status_code', 200)
    .gte('created_at', cutoff);
  if (error) return 0;
  return count ?? 0;
}

/** Inserta una fila en uso_llm. Fire-and-forget desde el caller (sin await). */
export async function logUso(params: {
  vendedorNombre: string;
  endpoint: 'chat' | 'transcribe';
  modelo?: string;
  tokensIn?: number;
  tokensOut?: number;
  audioSeg?: number;
  costoUsd?: number;
  latenciaMs: number;
  statusCode: number;
  error?: string;
}): Promise<void> {
  const sb = adminClient();
  await sb.from('uso_llm').insert({
    vendedor_nombre: params.vendedorNombre,
    endpoint: params.endpoint,
    modelo: params.modelo ?? null,
    tokens_in: params.tokensIn ?? null,
    tokens_out: params.tokensOut ?? null,
    audio_seg: params.audioSeg ?? null,
    costo_usd_estimado: params.costoUsd ?? null,
    latencia_ms: params.latenciaMs,
    status_code: params.statusCode,
    error: params.error ?? null,
  });
}

/** Standard CORS headers para que la app móvil (cualquier origen) llame. */
export const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers':
    'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};

export function handleCors(req: Request): Response | null {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }
  return null;
}
