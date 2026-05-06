// auth-token — emite/refresca un token de acceso para un vendedor.
// La app llama acá después del login local (validar contra usuarios).
//
// POST /auth-token
//   body: { username: string, password_hash: string }
//   200:  { token: string, vendedor_nombre: string, role: string }
//   401:  { error: 'invalid credentials' }
//
// El password_hash es SHA-256 (mismo formato que la app y desktop ya usan).
// La función valida contra la tabla `usuarios`, genera un token random hex,
// lo upsertea en vendedor_tokens, y lo retorna.

import { adminClient, corsHeaders, handleCors } from '../_shared/auth.ts';

function generateToken(): string {
  // 32 bytes = 64 hex chars. Suficiente entropía.
  const bytes = new Uint8Array(32);
  crypto.getRandomValues(bytes);
  return Array.from(bytes).map((b) => b.toString(16).padStart(2, '0')).join('');
}

Deno.serve(async (req: Request) => {
  const cors = handleCors(req);
  if (cors) return cors;

  if (req.method !== 'POST') {
    return new Response(JSON.stringify({ error: 'method not allowed' }), {
      status: 405,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    });
  }

  let body: { username?: string; password_hash?: string };
  try {
    body = await req.json();
  } catch {
    return new Response(JSON.stringify({ error: 'invalid json' }), {
      status: 400,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    });
  }

  const username = body.username?.trim();
  const passwordHash = body.password_hash?.trim();

  if (!username || !passwordHash) {
    return new Response(
      JSON.stringify({ error: 'username and password_hash required' }),
      {
        status: 400,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      },
    );
  }

  const sb = adminClient();

  // Validar credenciales contra la tabla usuarios (case insensitive en username,
  // mismo patrón que pg_service.dart:verifyUser)
  const { data: usuario, error } = await sb
    .from('usuarios')
    .select('username, role')
    .ilike('username', username)
    .eq('password_hash', passwordHash)
    .maybeSingle();

  if (error || !usuario) {
    return new Response(JSON.stringify({ error: 'invalid credentials' }), {
      status: 401,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    });
  }

  // Generar nuevo token y upsert (1 token vivo por vendedor; tokens viejos
  // del mismo vendedor se sobreescriben).
  const token = generateToken();
  const vendedorNombre = (usuario.username as string).trim();

  const { error: upsertError } = await sb
    .from('vendedor_tokens')
    .upsert(
      {
        vendedor_nombre: vendedorNombre,
        token,
        created_at: new Date().toISOString(),
        last_used_at: null,
      },
      { onConflict: 'vendedor_nombre' },
    );

  if (upsertError) {
    return new Response(
      JSON.stringify({ error: 'failed to issue token', details: upsertError.message }),
      {
        status: 500,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      },
    );
  }

  return new Response(
    JSON.stringify({
      token,
      vendedor_nombre: vendedorNombre,
      role: usuario.role,
    }),
    {
      status: 200,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    },
  );
});
