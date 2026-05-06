// cronos-transcribe — proxy a OpenAI Whisper (audio transcription).
//
// POST /cronos-transcribe
//   headers: Authorization: Bearer <vendedor_token>
//   body: multipart/form-data con campo "file" (audio m4a) + "language" + "prompt"
//   200:  { text: "transcripción" }   (response_format=text de Whisper)
//   401, 429, 500/502: ver cronos-chat
//
// Rate limit por vendedor: 60 requests/hora.
// Costo Whisper: $0.006 / minuto.

import {
  authVendedor,
  corsHeaders,
  countRecentRequests,
  handleCors,
  logUso,
} from '../_shared/auth.ts';

const RATE_LIMIT_PER_HOUR = 60;

Deno.serve(async (req: Request) => {
  const cors = handleCors(req);
  if (cors) return cors;

  if (req.method !== 'POST') {
    return new Response('method not allowed', {
      status: 405,
      headers: corsHeaders,
    });
  }

  const start = Date.now();

  // 1) Auth
  const vendedor = await authVendedor(req);
  if (!vendedor) {
    return new Response(JSON.stringify({ error: 'invalid or missing token' }), {
      status: 401,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    });
  }

  // 2) Rate limit
  const recentCount = await countRecentRequests(vendedor, 'transcribe', 1);
  if (recentCount >= RATE_LIMIT_PER_HOUR) {
    logUso({
      vendedorNombre: vendedor,
      endpoint: 'transcribe',
      latenciaMs: Date.now() - start,
      statusCode: 429,
      error: `rate limit ${recentCount}/${RATE_LIMIT_PER_HOUR}`,
    });
    return new Response(
      JSON.stringify({
        error: `Rate limit excedido (${RATE_LIMIT_PER_HOUR} req/h). Esperá un poco.`,
      }),
      {
        status: 429,
        headers: {
          ...corsHeaders,
          'Content-Type': 'application/json',
          'Retry-After': '900',
        },
      },
    );
  }

  // 3) Forward del multipart a OpenAI tal cual viene
  const openaiKey = Deno.env.get('OPENAI_API_KEY');
  if (!openaiKey) {
    return new Response(JSON.stringify({ error: 'server misconfigured' }), {
      status: 500,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    });
  }

  // Re-armar el FormData del request entrante para reenviar a OpenAI
  // (no podemos pipear el body crudo porque OpenAI espera multipart con
  // boundary específico; reconstruirlo es lo más confiable).
  let formData: FormData;
  try {
    formData = await req.formData();
  } catch (e) {
    const err = e instanceof Error ? e.message : 'invalid multipart';
    logUso({
      vendedorNombre: vendedor,
      endpoint: 'transcribe',
      latenciaMs: Date.now() - start,
      statusCode: 400,
      error: err,
    });
    return new Response(JSON.stringify({ error: 'invalid multipart', details: err }), {
      status: 400,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    });
  }

  // Forzar el modelo a whisper-1 (no permitir que el cliente elija otro)
  formData.set('model', 'whisper-1');

  let openaiResp: Response;
  try {
    openaiResp = await fetch('https://api.openai.com/v1/audio/transcriptions', {
      method: 'POST',
      headers: { 'Authorization': `Bearer ${openaiKey}` },
      body: formData,
    });
  } catch (e) {
    const err = e instanceof Error ? e.message : 'fetch failed';
    logUso({
      vendedorNombre: vendedor,
      endpoint: 'transcribe',
      latenciaMs: Date.now() - start,
      statusCode: 502,
      error: err,
    });
    return new Response(JSON.stringify({ error: 'OpenAI unreachable', details: err }), {
      status: 502,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    });
  }

  const respText = await openaiResp.text();
  const latencyMs = Date.now() - start;

  // No conocemos la duración del audio sin parsearlo, así que estimamos
  // costo en base a la latencia (proxy crudo). Para tracking más fino,
  // podríamos parsear metadata del .m4a, pero el costo es chico.
  // Whisper $0.006/min → fallback estimado $0.005 por call.
  const costoEstimado = openaiResp.ok ? 0.005 : 0;

  logUso({
    vendedorNombre: vendedor,
    endpoint: 'transcribe',
    modelo: 'whisper-1',
    costoUsd: costoEstimado,
    latenciaMs: latencyMs,
    statusCode: openaiResp.status,
    error: openaiResp.ok ? undefined : respText.slice(0, 500),
  });

  return new Response(respText, {
    status: openaiResp.status,
    headers: {
      ...corsHeaders,
      'Content-Type': openaiResp.headers.get('Content-Type') ?? 'text/plain',
    },
  });
});
