/**
 * Cloudflare Worker — Live Visitor Map API
 * Stores and returns visitor location data via KV
 */

const KV_KEY = 'visitors';
const TTL_SECONDS = 300; // 5 minutes

export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    const origin = request.headers.get('Origin') || '*';

    const corsHeaders = {
      'Access-Control-Allow-Origin': '*',
      'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
      'Access-Control-Allow-Headers': 'Content-Type',
    };

    if (request.method === 'OPTIONS') {
      return new Response(null, { headers: corsHeaders });
    }

    if (url.pathname !== '/visitors') {
      return new Response('Not found', { status: 404, headers: corsHeaders });
    }

    // GET — return all active visitors
    if (request.method === 'GET') {
      const raw = await env.VISITORS_KV.get(KV_KEY);
      const visitors = raw ? JSON.parse(raw) : [];

      // prune stale entries (older than 5 min)
      const cutoff = Date.now() - TTL_SECONDS * 1000;
      const active = visitors.filter(v => v.ts > cutoff);

      return new Response(JSON.stringify(active), {
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      });
    }

    // POST — save updated visitor list
    if (request.method === 'POST') {
      let visitors;
      try {
        visitors = await request.json();
      } catch {
        return new Response('Bad JSON', { status: 400, headers: corsHeaders });
      }

      if (!Array.isArray(visitors)) {
        return new Response('Expected array', { status: 400, headers: corsHeaders });
      }

      // prune stale before saving
      const cutoff = Date.now() - TTL_SECONDS * 1000;
      const active = visitors.filter(v => v.ts > cutoff);

      await env.VISITORS_KV.put(KV_KEY, JSON.stringify(active), {
        expirationTtl: TTL_SECONDS + 60,
      });

      return new Response(JSON.stringify({ ok: true, count: active.length }), {
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      });
    }

    return new Response('Method not allowed', { status: 405, headers: corsHeaders });
  },
};
