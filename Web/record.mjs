// =====================================================================
// PULLMED — leitura do registro de emergencia
//
// Este proxy existe por duas razoes:
//
//  1. RATE LIMITING. O navegador nao sabe o proprio IP. Sem ele, o limite
//     de 20 leituras/minuto do banco nunca dispara. Aqui temos o IP, e o
//     enviamos como HASH (nunca em claro): o objetivo e detectar abuso,
//     nao vigiar socorristas.
//
//  2. A anon key fica no servidor, nao no HTML. Ela nao e um segredo de
//     verdade (a RLS e a defesa real), mas nao ha razao para publica-la.
//
// Nada mais e feito aqui: a decisao sobre QUAIS campos sao publicos vive
// na funcao emergency_record() do banco, em um lugar so.
// =====================================================================

import crypto from 'node:crypto';

const SUPABASE_URL = process.env.SUPABASE_URL;
const SUPABASE_ANON_KEY = process.env.SUPABASE_ANON_KEY;
const IP_SALT = process.env.IP_HASH_SALT || 'pullmed-default-salt-change-me';

export default async (request, context) => {
  const url = new URL(request.url);
  const token = url.searchParams.get('token') || '';

  // Rejeita de cara o que nao for um token de 32 hex. Bloqueia sondagem.
  if (!/^[0-9a-f]{32}$/.test(token)) {
    return json({ error: 'not_found' }, 404);
  }

  const ip =
    request.headers.get('x-nf-client-connection-ip') ||
    request.headers.get('x-forwarded-for')?.split(',')[0]?.trim() ||
    '';

  const ipHash = ip
    ? crypto.createHash('sha256').update(IP_SALT + ip).digest('hex').slice(0, 32)
    : null;

  const userAgent = (request.headers.get('user-agent') || '').slice(0, 200);

  try {
    const res = await fetch(`${SUPABASE_URL}/rest/v1/rpc/emergency_record`, {
      method: 'POST',
      headers: {
        apikey: SUPABASE_ANON_KEY,
        Authorization: `Bearer ${SUPABASE_ANON_KEY}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        p_token: token,
        p_ip_hash: ipHash,
        p_user_agent: userAgent,
      }),
    });

    if (!res.ok) {
      const body = await res.text();
      if (body.includes('rate_limited')) {
        return json({ error: 'rate_limited' }, 429);
      }
      return json({ error: 'unavailable' }, 502);
    }

    const record = await res.json();

    // null = token inexistente, pulseira revogada, ou dados apagados.
    // Os tres casos retornam a mesma resposta, de proposito: distinguir
    // "nao existe" de "foi revogado" entregaria informacao a quem sonda.
    if (record === null) {
      return json({ error: 'not_found' }, 404);
    }

    return json(record, 200);
  } catch (e) {
    return json({ error: 'unavailable' }, 502);
  }
};

function json(body, status) {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      'Content-Type': 'application/json',
      'Cache-Control': 'no-store',
      'X-Robots-Tag': 'noindex, nofollow',
      'Referrer-Policy': 'no-referrer',
    },
  });
}

export const config = { path: '/api/record' };
