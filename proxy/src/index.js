// File Chat proxy: keeps the AI services' keys on the server and forwards the
// app's requests, adding a key. Bodies are streamed through, not parsed, so
// large files and long answers cost almost no CPU.
//
// Secrets (set from GitHub by .github/workflows/proxy-deploy.yml):
//   APP_TOKEN         shared with the app; requests without it are refused
//   GEMINI_KEYS       one or more Google AI Studio keys, comma-separated
//   GROQ_KEYS, MISTRAL_KEYS, OPENROUTER_KEYS, CEREBRAS_KEYS   optional, comma-separated
//   POLLINATIONS_TOKEN                                         optional

const PROVIDERS = {
  g: { base: 'https://generativelanguage.googleapis.com', keys: 'GEMINI_KEYS', header: 'x-goog-api-key' },
  q: { base: 'https://api.groq.com/openai', keys: 'GROQ_KEYS', header: 'authorization' },
  m: { base: 'https://api.mistral.ai', keys: 'MISTRAL_KEYS', header: 'authorization' },
  o: { base: 'https://openrouter.ai/api', keys: 'OPENROUTER_KEYS', header: 'authorization' },
  c: { base: 'https://api.cerebras.ai', keys: 'CEREBRAS_KEYS', header: 'authorization' },
  // Works without a key; a token only raises its limits.
  p: { base: 'https://text.pollinations.ai', keys: 'POLLINATIONS_TOKEN', header: 'authorization', optional: true, chat: 'openai' },
};

// The order the app tries services in. Served at /config so models can be
// changed here without updating the app. Services without keys are left out.
// `vision`: the model reads images (Gemini always does).
const CHAIN = [
  { backend: 'gemini', model: 'gemini-flash-latest', p: 'g' },
  { backend: 'gemini', model: 'gemini-flash-lite-latest', p: 'g' },
  // Pro is not in Gemini's free tier; add it here once billing is on:
  // { backend: 'gemini', model: 'gemini-pro-latest', p: 'g' },
  { backend: 'openai', model: 'openai/gpt-oss-120b', p: 'q' },
  { backend: 'openai', model: 'openai/gpt-oss-20b', p: 'q' },
  { backend: 'openai', model: 'mistral-medium-latest', p: 'm', vision: true },
  { backend: 'openai', model: 'mistral-small-latest', p: 'm', vision: true },
  { backend: 'openai', model: 'gpt-oss-120b', p: 'c' },
  { backend: 'openai', model: 'openrouter/free', p: 'o', vision: true },
  { backend: 'openai', model: 'openai', p: 'p', vision: true },
];

const keysOf = (env, name) =>
  String(env[name] || '')
    .split(',')
    .map((k) => k.trim())
    .filter(Boolean);

const refuse = (status, why) => new Response(why, { status, headers: { 'x-proxy-error': why } });

export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    if (!env.APP_TOKEN || request.headers.get('x-app-token') !== env.APP_TOKEN) return refuse(401, 'token');

    if (url.pathname === '/config') {
      const chain = CHAIN.filter((c) => PROVIDERS[c.p].optional || keysOf(env, PROVIDERS[c.p].keys).length);
      return Response.json({ chain }, { headers: { 'cache-control': 'no-store' } });
    }

    // /<service>/<path on that service>
    const [, id, ...rest] = url.pathname.split('/');
    const p = PROVIDERS[id];
    if (!p) return refuse(404, 'route');

    const keys = keysOf(env, p.keys);
    if (!keys.length && !p.optional) return refuse(501, 'unconfigured');

    let path = rest.join('/');
    if (p.chat && path === 'v1/chat/completions') path = p.chat;
    const target = new URL(p.base + '/' + path + url.search);

    const headers = new Headers(request.headers);
    for (const h of ['x-app-token', 'x-key-slot', 'host', 'cf-connecting-ip', 'x-forwarded-for', 'x-real-ip']) headers.delete(h);
    // Several keys spread the free quota. A Gemini upload can only be read with
    // the key that made it, so the app may ask for the same key again by slot.
    let slot = -1;
    if (keys.length) {
      const asked = parseInt(request.headers.get('x-key-slot') ?? '', 10);
      slot = Number.isInteger(asked) && asked >= 0 ? asked % keys.length : Math.floor(Math.random() * keys.length);
      headers.set(p.header, p.header === 'authorization' ? `Bearer ${keys[slot]}` : keys[slot]);
    }

    const res = await fetch(target, {
      method: request.method,
      headers,
      body: ['GET', 'HEAD'].includes(request.method) ? undefined : request.body,
      redirect: 'follow',
    });
    const out = new Headers(res.headers);
    if (slot >= 0) out.set('x-key-slot', String(slot));
    // Gemini's upload session URL is sent back through the proxy as well.
    const up = out.get('x-goog-upload-url');
    if (up && up.startsWith(p.base)) out.set('x-goog-upload-url', `${url.origin}/${id}${up.slice(p.base.length)}`);
    return new Response(res.body, { status: res.status, headers: out });
  },
};
