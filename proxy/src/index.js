// File Chat proxy: keeps the AI services' keys on the server and forwards the
// app's requests, adding a key. Bodies are streamed through, not parsed, so
// large files and long answers cost almost no CPU.
//
// Secrets (set from GitHub by .github/workflows/proxy-deploy.yml):
//   APP_TOKEN         shared with the app; requests without it are refused
//   GEMINI_KEYS       one or more Google AI Studio keys, comma-separated
//   GROQ_KEYS, MISTRAL_KEYS, OPENROUTER_KEYS, CEREBRAS_KEYS   optional, comma-separated
//   POLLINATIONS_TOKEN                                         optional
// Vars (wrangler.toml):
//   FIREBASE_PROJECT  when set, every AI request needs a signed-in user's Firebase
//                     ID token (x-user-token) and counts against the daily quota
//
// Quota: a Durable Object (Quota, SQLite storage) counts questions per user and
// per device each UTC day, so a new account or a reinstall does not reset the
// free questions. One question is one x-question-id; all the requests made while
// answering it (fallbacks, uploads) share that id.

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
  // Lite answers in under a second; the full Flash model often stalls on the free tier.
  { backend: 'gemini', model: 'gemini-flash-lite-latest', p: 'g' },
  { backend: 'gemini', model: 'gemini-flash-latest', p: 'g' },
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

const refuse = (status, why, extra = {}) =>
  new Response(why, { status, headers: { 'x-proxy-error': why, ...extra } });

export const LIMITS = {
  ask: { free: 20, premium: 300 }, // premium is the app's claim until Play purchases are verified here
  help: { free: 40, premium: 40 },
};
const QUESTION_WINDOW_MS = 30 * 60 * 1000; // one question id stays usable this long
const QUESTION_MAX_REQUESTS = 150; // and for this many requests (uploads poll while files process)

// Paths the app uses on each service; anything else is refused so the keys
// cannot be used for other calls.
const ALLOWED = {
  g: [
    /^v1beta\/models\/[a-z0-9.\-]+:(stream)?[gG]enerateContent$/,
    /^upload\/v1beta\/files$/,
    /^v1beta\/files\/[a-z0-9\-]+$/,
  ],
  openai: [/^v1\/chat\/completions$/, /^v1\/models$/],
};
const allowedPath = (id, path, method) => {
  if (id === 'g') return ALLOWED.g.some((r) => r.test(path)) && (method === 'POST' || /^v1beta\/files\//.test(path));
  if (path === 'v1/models') return method === 'GET';
  return ALLOWED.openai.some((r) => r.test(path)) && method === 'POST';
};

// ---------- Firebase ID tokens (RS256, Google's public keys) ----------
const JWKS_URL = 'https://www.googleapis.com/service_accounts/v1/jwk/securetoken@system.gserviceaccount.com';
let jwks = { keys: null, until: 0 };
const b64url = (s) => Uint8Array.from(atob(s.replace(/-/g, '+').replace(/_/g, '/').padEnd(Math.ceil(s.length / 4) * 4, '=')), (c) => c.charCodeAt(0));
const jsonPart = (s) => JSON.parse(new TextDecoder().decode(b64url(s)));

async function googleKeys(now) {
  if (jwks.keys && now < jwks.until) return jwks.keys;
  const res = await fetch(JWKS_URL);
  if (!res.ok) throw new Error('jwks ' + res.status);
  const age = /max-age=(\d+)/.exec(res.headers.get('cache-control') || '');
  jwks = { keys: (await res.json()).keys, until: now + (age ? Number(age[1]) : 3600) * 1000 };
  return jwks.keys;
}

/** Returns the token's claims, or null when it is not a valid, current token for this project. */
export async function verifyIdToken(token, project, now = Date.now()) {
  try {
    const [h, p, sig] = token.split('.');
    const header = jsonPart(h);
    const claims = jsonPart(p);
    if (header.alg !== 'RS256') return null;
    const sec = now / 1000;
    if (claims.aud !== project || claims.iss !== `https://securetoken.google.com/${project}`) return null;
    if (!claims.sub || claims.exp <= sec || claims.iat > sec + 300) return null;
    const jwk = (await googleKeys(now)).find((k) => k.kid === header.kid);
    if (!jwk) return null;
    const key = await crypto.subtle.importKey('jwk', jwk, { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' }, false, ['verify']);
    const ok = await crypto.subtle.verify('RSASSA-PKCS1-v1_5', key, b64url(sig), new TextEncoder().encode(`${h}.${p}`));
    if (!ok) return null;
    // Email accounts count only once the address is confirmed.
    if (claims.firebase?.sign_in_provider === 'password' && claims.email_verified !== true) return null;
    return claims;
  } catch {
    return null;
  }
}
export const _resetJwksForTest = () => (jwks = { keys: null, until: 0 });

// ---------- Quota (Durable Object with SQLite) ----------
const today = (now) => new Date(now).toISOString().slice(0, 10);

/** The counting rules, separate from storage so they can be tested with any SQLite. */
export function quotaCheck(sql, { uid, device, qid, kind, limit, now = Date.now() }) {
  sql.exec(`CREATE TABLE IF NOT EXISTS q (day TEXT, kind TEXT, uid TEXT, device TEXT, qid TEXT,
            first INTEGER, hits INTEGER, PRIMARY KEY (day, kind, uid, qid))`);
  const day = today(now);
  const used = () => {
    const byUser = sql.exec('SELECT COUNT(*) AS n FROM q WHERE day = ? AND kind = ? AND uid = ?', day, kind, uid).one().n;
    const byDevice = device
      ? sql.exec('SELECT COUNT(*) AS n FROM q WHERE day = ? AND kind = ? AND device = ?', day, kind, device).one().n
      : 0;
    return Math.max(byUser, byDevice);
  };
  if (!qid) return { ok: false, why: 'question', left: Math.max(0, limit - used()) };
  const row = sql.exec('SELECT first, hits FROM q WHERE day = ? AND kind = ? AND uid = ? AND qid = ?', day, kind, uid, qid).toArray()[0];
  if (row) {
    if (now - row.first > QUESTION_WINDOW_MS || row.hits >= QUESTION_MAX_REQUESTS) {
      return { ok: false, why: 'question', left: Math.max(0, limit - used()) };
    }
    sql.exec('UPDATE q SET hits = hits + 1 WHERE day = ? AND kind = ? AND uid = ? AND qid = ?', day, kind, uid, qid);
    return { ok: true, left: Math.max(0, limit - used()) };
  }
  const n = used();
  if (n >= limit) return { ok: false, why: 'quota', left: 0 };
  sql.exec('INSERT INTO q (day, kind, uid, device, qid, first, hits) VALUES (?, ?, ?, ?, ?, ?, 1)', day, kind, uid, device || '', qid, now);
  if (Math.random() < 0.01) sql.exec('DELETE FROM q WHERE day < ?', today(now - 3 * 86400000));
  return { ok: true, left: Math.max(0, limit - n - 1) };
}

export function quotaStatus(sql, { uid, device, kind, limit, now = Date.now() }) {
  const r = quotaCheck(sql, { uid, device, qid: '', kind, limit, now });
  return { left: r.left, limit };
}

export class Quota {
  constructor(ctx) {
    this.sql = ctx.storage.sql;
  }
  async fetch(request) {
    const body = await request.json();
    const out = body.op === 'status' ? quotaStatus(this.sql, body) : quotaCheck(this.sql, body);
    return Response.json(out);
  }
}

async function quota(env, body) {
  const stub = env.QUOTA.get(env.QUOTA.idFromName('global'));
  const res = await stub.fetch('https://quota/', { method: 'POST', body: JSON.stringify(body) });
  return res.json();
}

/** Signed-in user and quota for an AI request. Returns a refusal Response, or the headers to add. */
async function admit(request, env, kindOverride) {
  if (!env.FIREBASE_PROJECT) return { headers: {} };
  // The deploy check in CI proves it holds the server's keys instead of signing in.
  if (env.GEMINI_KEYS && request.headers.get('x-ci') === env.GEMINI_KEYS) return { headers: {} };
  const claims = await verifyIdToken(request.headers.get('x-user-token') || '', env.FIREBASE_PROJECT);
  if (!claims) return { refuse: refuse(401, 'auth') };
  const kind = kindOverride || (request.headers.get('x-kind') === 'help' ? 'help' : 'ask');
  const plan = request.headers.get('x-plan') === 'premium' ? 'premium' : 'free';
  const limit = LIMITS[kind][plan];
  const device = (request.headers.get('x-device-id') || '').slice(0, 64);
  const qid = (request.headers.get('x-question-id') || '').slice(0, 64);
  const r = await quota(env, { op: kindOverride ? 'status' : 'check', uid: claims.sub, device, qid, kind, limit });
  const headers = { 'x-quota-left': String(r.left), 'x-quota-limit': String(limit) };
  if (!kindOverride && !r.ok) return { refuse: refuse(429, r.why, headers) };
  return { headers };
}

export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    if (!env.APP_TOKEN || request.headers.get('x-app-token') !== env.APP_TOKEN) return refuse(401, 'token');

    if (url.pathname === '/quota') {
      const a = await admit(request, env, request.headers.get('x-kind') === 'help' ? 'help' : 'ask');
      if (a.refuse) return a.refuse;
      return Response.json({ left: Number(a.headers['x-quota-left'] ?? -1), limit: Number(a.headers['x-quota-limit'] ?? -1) }, { headers: { 'cache-control': 'no-store' } });
    }

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
    if (!allowedPath(id, path, request.method)) return refuse(403, 'path');
    const admitted = await admit(request, env);
    if (admitted.refuse) return admitted.refuse;
    if (p.chat && path === 'v1/chat/completions') path = p.chat;
    const target = new URL(p.base + '/' + path + url.search);

    const headers = new Headers(request.headers);
    for (const h of ['x-app-token', 'x-key-slot', 'x-user-token', 'x-ci', 'x-device-id', 'x-question-id', 'x-kind', 'x-plan',
      'authorization', 'x-goog-api-key', 'host', 'cf-connecting-ip', 'x-forwarded-for', 'x-real-ip']) headers.delete(h);
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
    for (const [k, v] of Object.entries(admitted.headers)) out.set(k, v);
    // Gemini's upload session URL is sent back through the proxy as well.
    const up = out.get('x-goog-upload-url');
    if (up && up.startsWith(p.base)) out.set('x-goog-upload-url', `${url.origin}/${id}${up.slice(p.base.length)}`);
    return new Response(res.body, { status: res.status, headers: out });
  },
};
