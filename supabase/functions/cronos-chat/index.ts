// cronos-chat — proxy a OpenAI Chat Completions con auth + rate limit + log.
//
// POST /cronos-chat
//   headers: Authorization: Bearer <vendedor_token>
//   body: { model, messages, temperature?, max_tokens? }   (formato OpenAI)
//   200:  el JSON de OpenAI tal cual
//   401:  token inválido / expirado
//   429:  rate limit excedido (header Retry-After con segundos)
//   500/502/...: error de OpenAI o interno
//
// Rate limit por vendedor: 100 requests/hora exitosas en endpoint chat.

import {
  authVendedor,
  corsHeaders,
  countRecentRequests,
  handleCors,
  logUso,
} from '../_shared/auth.ts';

const RATE_LIMIT_PER_HOUR = 100;

// Costo gpt-4o-mini (al 2026-05): $0.15/M tokens-in, $0.60/M tokens-out
function calcCostoChat(modelo: string, tokensIn: number, tokensOut: number): number {
  if (modelo.startsWith('gpt-4o-mini')) {
    return (tokensIn * 0.15 + tokensOut * 0.60) / 1_000_000;
  }
  if (modelo.startsWith('gpt-4o')) {
    return (tokensIn * 2.50 + tokensOut * 10.00) / 1_000_000;
  }
  // Fallback conservador para modelos no listados
  return (tokensIn * 1.0 + tokensOut * 3.0) / 1_000_000;
}

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
  const recentCount = await countRecentRequests(vendedor, 'chat', 1);
  if (recentCount >= RATE_LIMIT_PER_HOUR) {
    logUso({
      vendedorNombre: vendedor,
      endpoint: 'chat',
      latenciaMs: Date.now() - start,
      statusCode: 429,
      error: `rate limit ${recentCount}/${RATE_LIMIT_PER_HOUR}`,
    });
    return new Response(
      JSON.stringify({
        error: `Rate limit excedido (${RATE_LIMIT_PER_HOUR} req/h). Esperá un poco e intentá de nuevo.`,
      }),
      {
        status: 429,
        headers: {
          ...corsHeaders,
          'Content-Type': 'application/json',
          'Retry-After': '600',
        },
      },
    );
  }

  // 3) Forward a OpenAI
  let body: Record<string, unknown>;
  try {
    body = await req.json();
  } catch {
    return new Response(JSON.stringify({ error: 'invalid json' }), {
      status: 400,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    });
  }

  const openaiKey = Deno.env.get('OPENAI_API_KEY');
  if (!openaiKey) {
    return new Response(JSON.stringify({ error: 'server misconfigured' }), {
      status: 500,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    });
  }

  let openaiResp: Response;
  try {
    openaiResp = await fetch('https://api.openai.com/v1/chat/completions', {
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${openaiKey}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify(body),
    });
  } catch (e) {
    const err = e instanceof Error ? e.message : 'fetch failed';
    logUso({
      vendedorNombre: vendedor,
      endpoint: 'chat',
      modelo: body.model as string | undefined,
      latenciaMs: Date.now() - start,
      statusCode: 502,
      error: err,
    });
    return new Response(JSON.stringify({ error: 'OpenAI unreachable', details: err }), {
      status: 502,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    });
  }

  // 4) Capturar response y métricas, log de uso, devolver al cliente
  const respText = await openaiResp.text();
  const latencyMs = Date.now() - start;

  let tokensIn = 0;
  let tokensOut = 0;
  let modelo = (body.model as string) ?? 'unknown';
  if (openaiResp.ok) {
    try {
      const respJson = JSON.parse(respText);
      tokensIn = respJson.usage?.prompt_tokens ?? 0;
      tokensOut = respJson.usage?.completion_tokens ?? 0;
      modelo = respJson.model ?? modelo;
    } catch {
      // No bloqueamos: si el JSON viene mal, igual reenviamos al cliente
    }
  }

  logUso({
    vendedorNombre: vendedor,
    endpoint: 'chat',
    modelo,
    tokensIn,
    tokensOut,
    costoUsd: openaiResp.ok ? calcCostoChat(modelo, tokensIn, tokensOut) : 0,
    latenciaMs: latencyMs,
    statusCode: openaiResp.status,
    error: openaiResp.ok ? undefined : respText.slice(0, 500),
  });

  return new Response(respText, {
    status: openaiResp.status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  });
});
