import { PAGES } from './pages.js';
// Constants live in their own module: everything the main module exports must be a
// handler or a function for the Workers runtime.
import { PACKAGE, PRODUCT } from './play.js';

// File Chat proxy: keeps the AI services' keys on the server and forwards the
// app's requests, adding a key. Bodies are streamed through, not parsed, so
// large files and long answers cost almost no CPU.
//
// Secrets (set from GitHub by .github/workflows/proxy-deploy.yml):
//   APP_TOKEN         shared with the app; requests without it are refused
//   GEMINI_KEYS       one or more Google AI Studio keys, comma-separated
//   GROQ_KEYS, MISTRAL_KEYS, OPENROUTER_KEYS, CEREBRAS_KEYS   optional, comma-separated
//   POLLINATIONS_TOKEN                                         optional
//   PLAY_SERVICE_ACCOUNT  optional: JSON key of a Google Cloud service account that
//                     has access to the app in Play Console. Without it nobody gets
//                     the paid plan's limits, because a purchase cannot be checked.
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

const LIMITS = {
  ask: { free: 20, premium: 300 }, // premium only for a subscription checked with Google Play (see /purchase)
  help: { free: 40, premium: 40 },
  voice: { free: 30, premium: 300 }, // spoken questions turned into text
};
// The owner's accounts (ADMIN_EMAILS): the paid plan, without a practical limit.
const OWNER_LIMIT = 100000;
const OWNER_UNTIL = Date.parse('2100-01-01T00:00:00Z');

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
  // Speech to text, on Groq only.
  q: [/^v1\/audio\/transcriptions$/],
};
const allowedPath = (id, path, method) => {
  if (id === 'g') return ALLOWED.g.some((r) => r.test(path)) && (method === 'POST' || /^v1beta\/files\//.test(path));
  if (path === 'v1/models') return method === 'GET';
  if (id === 'q' && ALLOWED.q.some((r) => r.test(path))) return method === 'POST';
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
    // Email accounts count only once the address is confirmed, and only with the
    // mail services the app allows (the app checks too, but Firebase's sign-up
    // API can be called without the app).
    if (claims.firebase?.sign_in_provider === 'password') {
      if (claims.email_verified !== true || !emailAllowed(claims.email)) return null;
    }
    return claims;
  } catch {
    return null;
  }
}
// Same list as Auth.emailDomains in the app.
const EMAIL_DOMAINS = new Set(['gmail.com', 'googlemail.com', 'hotmail.com', 'outlook.com', 'live.com', 'msn.com',
  'yahoo.com', 'icloud.com', 'me.com', 'hotmail.co.uk', 'outlook.sa', 'hotmail.fr']);
/** One account per inbox: known mail services, no "+tag" aliases, and Gmail
 * addresses in the app's form (no dots, which Gmail ignores). */
export function emailAllowed(email) {
  const m = /^([^@\s]+)@([^@\s]+)$/.exec(String(email || '').toLowerCase());
  if (!m) return false;
  const [, local, domain] = m;
  if (!EMAIL_DOMAINS.has(domain) || local.includes('+')) return false;
  if ((domain === 'gmail.com' || domain === 'googlemail.com') && local.includes('.')) return false;
  return true;
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
  return { ok: true, left: Math.max(0, limit - n - 1), fresh: true };
}

export function quotaStatus(sql, { uid, device, kind, limit, now = Date.now() }) {
  const r = quotaCheck(sql, { uid, device, qid: '', kind, limit, now });
  return { left: r.left, limit };
}

// ---------- Subscriptions (checked with Google Play, kept with the quota) ----------
const subsTable = (sql) =>
  sql.exec(`CREATE TABLE IF NOT EXISTS subs (token TEXT PRIMARY KEY, uid TEXT, expiry INTEGER, checked INTEGER)`);

/** Until when [uid] has the paid plan (ms), or 0. */
export function premiumUntil(sql, uid, now = Date.now()) {
  subsTable(sql);
  const r = sql.exec('SELECT MAX(expiry) AS e FROM subs WHERE uid = ? AND expiry > ?', uid, now).one();
  return r.e || 0;
}

/** Records a purchase Google confirmed. One subscription belongs to the first account that sent it. */
export function saveSub(sql, { token, uid, expiry, now = Date.now() }) {
  subsTable(sql);
  const row = sql.exec('SELECT uid, expiry FROM subs WHERE token = ?', token).toArray()[0];
  if (row && row.uid !== uid && row.expiry > now) return { ok: false, why: 'other-account' };
  sql.exec('INSERT OR REPLACE INTO subs (token, uid, expiry, checked) VALUES (?, ?, ?, ?)', token, uid, expiry, now);
  return { ok: true, until: premiumUntil(sql, uid, now) };
}

/** Removes the account's subscription records. Question counts are kept until
 * they expire (3 days), or deleting would hand out new free questions. */
export function forget(sql, uid) {
  subsTable(sql);
  statsTables(sql);
  sql.exec('DELETE FROM subs WHERE uid = ?', uid);
  sql.exec('DELETE FROM users WHERE uid = ?', uid);
  return { ok: true };
}

// ---------- Users and daily totals, for the owner's dashboard ----------
const statsTables = (sql) => {
  sql.exec(`CREATE TABLE IF NOT EXISTS users (uid TEXT PRIMARY KEY, email TEXT, provider TEXT,
            first INTEGER, last INTEGER, questions INTEGER DEFAULT 0, voice INTEGER DEFAULT 0)`);
  // Accounts the owner blocked (kept apart from users, so deleting an account does not unblock it).
  sql.exec('CREATE TABLE IF NOT EXISTS blocked (uid TEXT PRIMARY KEY, email TEXT, at INTEGER)');
  sql.exec('CREATE TABLE IF NOT EXISTS stats (day TEXT, kind TEXT, n INTEGER, PRIMARY KEY (day, kind))');
};

/** Remembers who asked (account ID, email, sign-in method, first and last time) and counts the question. */
export function noteUse(sql, { uid, email, provider, kind, fresh, now = Date.now() }) {
  statsTables(sql);
  sql.exec(`INSERT INTO users (uid, email, provider, first, last) VALUES (?, ?, ?, ?, ?)
            ON CONFLICT(uid) DO UPDATE SET email = excluded.email, provider = excluded.provider, last = excluded.last`,
  uid, email || '', provider || '', now, now);
  if (!fresh) return;
  if (kind === 'ask') sql.exec('UPDATE users SET questions = questions + 1 WHERE uid = ?', uid);
  if (kind === 'voice') sql.exec('UPDATE users SET voice = voice + 1 WHERE uid = ?', uid);
  sql.exec(`INSERT INTO stats (day, kind, n) VALUES (?, ?, 1) ON CONFLICT(day, kind) DO UPDATE SET n = n + 1`, today(now), kind);
}

export function isBlocked(sql, uid) {
  statsTables(sql);
  return sql.exec('SELECT 1 AS b FROM blocked WHERE uid = ?', uid).toArray().length > 0;
}

/** Blocks or unblocks an account (by its ID, as shown on the dashboard). */
export function setBlocked(sql, { uid, block, now = Date.now() }) {
  statsTables(sql);
  if (block) {
    const email = sql.exec('SELECT email FROM users WHERE uid = ?', uid).toArray()[0]?.email || '';
    sql.exec('INSERT OR REPLACE INTO blocked (uid, email, at) VALUES (?, ?, ?)', uid, email, now);
  } else {
    sql.exec('DELETE FROM blocked WHERE uid = ?', uid);
  }
  return { ok: true, blocked: Boolean(block) };
}

/** Everything the dashboard shows. */
export function dashboard(sql, now = Date.now()) {
  statsTables(sql);
  subsTable(sql);
  quotaCheck(sql, { uid: '', device: '', qid: '', kind: 'ask', limit: 0, now }); // makes sure table q exists
  const one = (q, ...b) => sql.exec(q, ...b).one();
  const day = today(now);
  const dayStart = Date.parse(day + 'T00:00:00Z');
  const days = [];
  for (let i = 13; i >= 0; i--) {
    const d = today(now - i * 86400000);
    const row = { day: d, ask: 0, help: 0, voice: 0, users: 0 };
    for (const r of sql.exec('SELECT kind, n FROM stats WHERE day = ?', d).toArray()) row[r.kind] = r.n;
    const start = Date.parse(d + 'T00:00:00Z');
    row.users = one('SELECT COUNT(*) AS n FROM users WHERE first >= ? AND first < ?', start, start + 86400000).n;
    days.push(row);
  }
  const users = sql.exec(`SELECT u.uid, u.email, u.provider, u.first, u.last, u.questions, u.voice,
      (SELECT COUNT(*) FROM q WHERE q.uid = u.uid AND q.day = ? AND q.kind = 'ask') AS today,
      (SELECT MAX(expiry) FROM subs WHERE subs.uid = u.uid AND subs.expiry > ?) AS premiumUntil,
      (SELECT COUNT(*) FROM blocked b WHERE b.uid = u.uid) AS blocked
      FROM users u ORDER BY u.last DESC LIMIT 500`, day, now).toArray();
  return {
    now,
    totals: {
      users: one('SELECT COUNT(*) AS n FROM users').n,
      newToday: one('SELECT COUNT(*) AS n FROM users WHERE first >= ?', dayStart).n,
      activeToday: one('SELECT COUNT(*) AS n FROM users WHERE last >= ?', dayStart).n,
      active7: one('SELECT COUNT(*) AS n FROM users WHERE last >= ?', now - 7 * 86400000).n,
      subscribers: one('SELECT COUNT(DISTINCT uid) AS n FROM subs WHERE expiry > ?', now).n,
      questionsToday: days.at(-1).ask,
      voiceToday: days.at(-1).voice,
      helpToday: days.at(-1).help,
      questionsAll: one('SELECT COALESCE(SUM(questions), 0) AS n FROM users').n,
      byGoogle: one("SELECT COUNT(*) AS n FROM users WHERE provider = 'google.com'").n,
      byEmail: one("SELECT COUNT(*) AS n FROM users WHERE provider = 'password'").n,
      blocked: one('SELECT COUNT(*) AS n FROM blocked').n,
    },
    days,
    users,
  };
}

/** Quota with the limit of the account's plan. */
export function planned(sql, body, now = Date.now()) {
  if (isBlocked(sql, body.uid)) return { ok: false, why: 'blocked', left: 0, limit: 0, plan: 'free', until: 0 };
  const until = body.owner ? OWNER_UNTIL : premiumUntil(sql, body.uid, now);
  const plan = until > now ? 'premium' : 'free';
  const limit = body.owner ? OWNER_LIMIT : LIMITS[body.kind][plan];
  const args = { ...body, limit, now };
  const r = body.op === 'status' ? quotaStatus(sql, args) : quotaCheck(sql, args);
  if (body.op !== 'status' && r.ok) noteUse(sql, { ...body, fresh: r.fresh, now });
  return { ...r, limit, plan, until };
}

export class Quota {
  constructor(ctx) {
    this.sql = ctx.storage.sql;
  }
  async fetch(request) {
    const body = await request.json();
    if (body.op === 'save-sub') return Response.json(saveSub(this.sql, body));
    if (body.op === 'forget') return Response.json(forget(this.sql, body.uid));
    if (body.op === 'dashboard') return Response.json(dashboard(this.sql));
    if (body.op === 'block') return Response.json(setBlocked(this.sql, body));
    return Response.json(planned(this.sql, body));
  }
}

async function quota(env, body) {
  const stub = env.QUOTA.get(env.QUOTA.idFromName('global'));
  const res = await stub.fetch('https://quota/', { method: 'POST', body: JSON.stringify(body) });
  return res.json();
}

/** Signed-in user and quota for an AI request. Returns a refusal Response, or the headers to add. */
const kindOf = (request) => {
  const k = request.headers.get('x-kind');
  return k === 'help' || k === 'voice' ? k : 'ask';
};

const ciCall = (request, env) => env.GEMINI_KEYS && request.headers.get('x-ci') === env.GEMINI_KEYS;
const signedIn = (request, env) => verifyIdToken(request.headers.get('x-user-token') || '', env.FIREBASE_PROJECT);

/** Signed-in user and quota for an AI request. Returns a refusal Response, or the headers to add. */
async function admit(request, env, statusOnly = false) {
  if (!env.FIREBASE_PROJECT) return { headers: {} };
  // The deploy check in CI proves it holds the server's keys instead of signing in.
  if (ciCall(request, env)) return { headers: {} };
  const claims = await signedIn(request, env);
  if (!claims) return { refuse: refuse(401, 'auth') };
  const kind = kindOf(request);
  const device = (request.headers.get('x-device-id') || '').slice(0, 64);
  const qid = (request.headers.get('x-question-id') || '').slice(0, 64);
  const r = await quota(env, {
    op: statusOnly ? 'status' : 'check', uid: claims.sub, device, qid, kind,
    email: claims.email || claims.phone_number || '', provider: claims.firebase?.sign_in_provider || '',
    owner: isAdmin(claims, env),
  });
  const headers = {
    'x-quota-left': String(r.left),
    'x-quota-limit': String(r.limit),
    'x-plan': r.plan,
    'x-premium-until': String(r.until || 0),
  };
  if (r.why === 'blocked') return { refuse: refuse(403, 'blocked') };
  if (!statusOnly && !r.ok) return { refuse: refuse(429, r.why, headers) };
  return { headers };
}

// ---------- Google Play (service account → OAuth token → Play Developer API) ----------
const b64urlOf = (bytes) => btoa(String.fromCharCode(...new Uint8Array(bytes))).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
let playToken = { value: null, until: 0 };

async function playAccessToken(env, now = Date.now()) {
  if (playToken.value && now < playToken.until) return playToken.value;
  const sa = JSON.parse(env.PLAY_SERVICE_ACCOUNT);
  const sec = Math.floor(now / 1000);
  const enc = (o) => b64urlOf(new TextEncoder().encode(JSON.stringify(o)));
  const unsigned = enc({ alg: 'RS256', typ: 'JWT' }) + '.' + enc({
    iss: sa.client_email,
    scope: 'https://www.googleapis.com/auth/androidpublisher',
    aud: 'https://oauth2.googleapis.com/token',
    iat: sec,
    exp: sec + 3600,
  });
  const pem = sa.private_key.replace(/-----[^-]+-----/g, '').replace(/\s/g, '');
  const key = await crypto.subtle.importKey('pkcs8', Uint8Array.from(atob(pem), (c) => c.charCodeAt(0)),
    { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' }, false, ['sign']);
  const sig = await crypto.subtle.sign('RSASSA-PKCS1-v1_5', key, new TextEncoder().encode(unsigned));
  const res = await fetch('https://oauth2.googleapis.com/token', {
    method: 'POST',
    headers: { 'content-type': 'application/x-www-form-urlencoded' },
    body: `grant_type=urn%3Aietf%3Aparams%3Aoauth%3Agrant-type%3Ajwt-bearer&assertion=${unsigned}.${b64urlOf(sig)}`,
  });
  if (!res.ok) throw new Error('oauth ' + res.status);
  const j = await res.json();
  playToken = { value: j.access_token, until: now + (j.expires_in - 120) * 1000 };
  return playToken.value;
}

/** Until when (ms) a Play subscription purchase gives the paid plan; 0 if it does not. */
export function subscriptionUntil(sub, now = Date.now()) {
  const states = ['SUBSCRIPTION_STATE_ACTIVE', 'SUBSCRIPTION_STATE_IN_GRACE_PERIOD', 'SUBSCRIPTION_STATE_CANCELED'];
  if (!sub || !states.includes(sub.subscriptionState)) return 0;
  const item = (sub.lineItems || []).find((l) => l.productId === PRODUCT);
  const until = item ? Date.parse(item.expiryTime) : 0;
  return until > now ? until : 0;
}

async function checkPurchase(request, env) {
  if (!env.FIREBASE_PROJECT) return refuse(501, 'unconfigured');
  const claims = await signedIn(request, env);
  if (!claims) return refuse(401, 'auth');
  if (!env.PLAY_SERVICE_ACCOUNT) return refuse(503, 'unconfigured');
  let body;
  try {
    body = await request.json();
  } catch {
    return refuse(400, 'body');
  }
  const token = String(body.purchaseToken || '');
  if (!/^[A-Za-z0-9._\-]{10,1000}$/.test(token)) return refuse(400, 'body');
  const access = await playAccessToken(env);
  const res = await fetch(`https://androidpublisher.googleapis.com/androidpublisher/v3/applications/${PACKAGE}/purchases/subscriptionsv2/tokens/${token}`,
    { headers: { authorization: `Bearer ${access}` } });
  if (res.status === 404 || res.status === 410 || res.status === 400) return Response.json({ premium: false, until: 0 });
  if (!res.ok) return refuse(502, 'play');
  const until = subscriptionUntil(await res.json());
  if (!until) return Response.json({ premium: false, until: 0 });
  const r = await quota(env, { op: 'save-sub', token, uid: claims.sub, expiry: until });
  if (!r.ok) return Response.json({ premium: false, until: 0, why: r.why });
  return Response.json({ premium: true, until: r.until });
}

/** True for the owner's accounts (ADMIN_EMAILS in wrangler.toml), signed in with a confirmed address. */
export function isAdmin(claims, env) {
  const admins = String(env.ADMIN_EMAILS || '').toLowerCase().split(',').map((e) => e.trim()).filter(Boolean);
  return Boolean(claims && claims.email_verified === true && admins.includes(String(claims.email || '').toLowerCase()));
}

async function adminStats(request, env) {
  if (!env.FIREBASE_PROJECT) return refuse(501, 'unconfigured');
  const claims = await signedIn(request, env);
  if (!claims) return refuse(401, 'auth');
  if (!isAdmin(claims, env)) return refuse(403, 'admin');
  if (request.method === 'POST') {
    let body;
    try {
      body = await request.json();
    } catch {
      return refuse(400, 'body');
    }
    const uid = String(body.uid || '');
    if (!uid || uid.length > 128) return refuse(400, 'body');
    if (uid === claims.sub) return refuse(400, 'self');
    return Response.json(await quota(env, { op: 'block', uid, block: body.block === true }));
  }
  return Response.json(await quota(env, { op: 'dashboard' }), { headers: { 'cache-control': 'no-store' } });
}

async function forgetAccount(request, env) {
  if (!env.FIREBASE_PROJECT) return Response.json({ ok: true });
  const claims = await signedIn(request, env);
  if (!claims) return refuse(401, 'auth');
  return Response.json(await quota(env, { op: 'forget', uid: claims.sub }));
}

export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    // Public pages that Google Play and sign-in providers link to.
    if (request.method === 'GET' && PAGES[url.pathname]) {
      return new Response(PAGES[url.pathname], {
        headers: { 'content-type': 'text/html; charset=utf-8', 'cache-control': 'public, max-age=3600' },
      });
    }
    if (!env.APP_TOKEN || request.headers.get('x-app-token') !== env.APP_TOKEN) return refuse(401, 'token');

    if (url.pathname === '/quota') {
      const a = await admit(request, env, true);
      if (a.refuse) return a.refuse;
      const h = a.headers;
      return Response.json({
        left: Number(h['x-quota-left'] ?? -1),
        limit: Number(h['x-quota-limit'] ?? -1),
        plan: h['x-plan'] || 'free',
        until: Number(h['x-premium-until'] || 0),
        verify: Boolean(env.PLAY_SERVICE_ACCOUNT),
      }, { headers: { 'cache-control': 'no-store' } });
    }
    if (url.pathname === '/purchase' && request.method === 'POST') return checkPurchase(request, env);
    if (url.pathname === '/account' && request.method === 'DELETE') return forgetAccount(request, env);
    if (url.pathname === '/admin' && ['GET', 'POST'].includes(request.method)) return adminStats(request, env);

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
