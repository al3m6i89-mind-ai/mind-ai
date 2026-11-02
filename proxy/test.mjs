// node proxy/test.mjs — checks routing, auth and key injection with a stubbed fetch.
import worker, { verifyIdToken, quotaCheck, _resetJwksForTest, Quota } from './src/index.js';
import { DatabaseSync } from 'node:sqlite';
import assert from 'node:assert/strict';

const seen = [];
globalThis.fetch = async (url, init) => {
  seen.push({ url: String(url), headers: init.headers });
  return new Response('ok', {
    status: 200,
    headers: { 'x-goog-upload-url': 'https://generativelanguage.googleapis.com/upload/v1beta/files?upload_id=9' },
  });
};
const env = { APP_TOKEN: 't', GEMINI_KEYS: 'k1, k2', GROQ_KEYS: 'q1' };
const req = (path, token = 't', method = 'POST', extra = {}) =>
  new Request('https://proxy.example' + path, {
    method,
    headers: { 'x-app-token': token, ...extra },
    body: method === 'GET' ? undefined : 'x',
  });

let r = await worker.fetch(req('/g/v1beta/models/m:x', 'bad'), env);
assert.equal(r.status, 401);
assert.equal(r.headers.get('x-proxy-error'), 'token');

r = await worker.fetch(req('/g/v1beta/models/gemini-flash-latest:streamGenerateContent?alt=sse', 't', 'POST', { 'x-key-slot': '1' }), env);
assert.equal(r.status, 200);
assert.equal(seen[0].url, 'https://generativelanguage.googleapis.com/v1beta/models/gemini-flash-latest:streamGenerateContent?alt=sse');
assert.equal(seen[0].headers.get('x-goog-api-key'), 'k2');
assert.equal(seen[0].headers.get('x-app-token'), null);
assert.equal(seen[0].headers.get('x-key-slot'), null);
assert.equal(r.headers.get('x-key-slot'), '1');
assert.equal(r.headers.get('x-goog-upload-url'), 'https://proxy.example/g/upload/v1beta/files?upload_id=9');

await worker.fetch(req('/q/v1/chat/completions'), env);
assert.equal(seen[1].url, 'https://api.groq.com/openai/v1/chat/completions');
assert.equal(seen[1].headers.get('authorization'), 'Bearer q1');

await worker.fetch(req('/p/v1/chat/completions'), env);
assert.equal(seen[2].url, 'https://text.pollinations.ai/openai');
assert.equal(seen[2].headers.get('authorization'), null);

r = await worker.fetch(req('/m/v1/chat/completions'), env);
assert.equal(r.status, 501);
assert.equal(r.headers.get('x-proxy-error'), 'unconfigured');

const cfg = await (await worker.fetch(req('/config', 't', 'GET'), env)).json();
assert.deepEqual([...new Set(cfg.chain.map((c) => c.p))], ['g', 'q', 'p']);

// Only the app's paths reach the services.
r = await worker.fetch(req('/g/v1beta/files', 't', 'GET'), env);
assert.equal(r.status, 403);
r = await worker.fetch(req('/q/v1/embeddings'), env);
assert.equal(r.status, 403);

// ---------- Firebase ID tokens ----------
const project = 'file-chat-224b4';
const { privateKey, publicKey } = await crypto.subtle.generateKey(
  { name: 'RSASSA-PKCS1-v1_5', modulusLength: 2048, publicExponent: new Uint8Array([1, 0, 1]), hash: 'SHA-256' }, true, ['sign', 'verify']);
const jwk = { ...(await crypto.subtle.exportKey('jwk', publicKey)), kid: 'k1', alg: 'RS256', use: 'sig' };
const enc = (o) => Buffer.from(JSON.stringify(o)).toString('base64url');
const now = Math.floor(Date.now() / 1000);
async function token(claims = {}, kid = 'k1') {
  const h = enc({ alg: 'RS256', kid, typ: 'JWT' });
  const p = enc({ aud: project, iss: `https://securetoken.google.com/${project}`, sub: 'user1', iat: now - 10, exp: now + 3600,
    firebase: { sign_in_provider: 'google.com' }, ...claims });
  const sig = await crypto.subtle.sign('RSASSA-PKCS1-v1_5', privateKey, new TextEncoder().encode(`${h}.${p}`));
  return `${h}.${p}.${Buffer.from(sig).toString('base64url')}`;
}
const realFetch = globalThis.fetch;
globalThis.fetch = async (url, init) => {
  if (String(url).includes('securetoken@system')) return Response.json({ keys: [jwk] }, { headers: { 'cache-control': 'max-age=600' } });
  return realFetch(url, init);
};
_resetJwksForTest();
assert.ok(await verifyIdToken(await token(), project));
assert.equal(await verifyIdToken(await token({ exp: now - 1 }), project), null, 'expired');
assert.equal(await verifyIdToken(await token({ aud: 'other' }), project), null, 'other project');
assert.equal(await verifyIdToken(await token({}, 'nope'), project), null, 'unknown key');
const t0 = await token();
const mid = t0.length - 20;
const tampered = t0.slice(0, mid) + (t0[mid] === 'A' ? 'B' : 'A') + t0.slice(mid + 1);
assert.equal(await verifyIdToken(tampered, project), null, 'bad signature');
assert.equal(await verifyIdToken(await token({ firebase: { sign_in_provider: 'password' }, email_verified: false }), project), null, 'unconfirmed email');
assert.ok(await verifyIdToken(await token({ firebase: { sign_in_provider: 'password' }, email_verified: true }), project));

// ---------- Quota ----------
const sqlOf = (db) => ({
  exec(q, ...binds) {
    const st = db.prepare(q);
    if (!/^\s*select/i.test(q)) { st.run(...binds); return { toArray: () => [], one: () => undefined }; }
    const rows = st.all(...binds);
    return { toArray: () => rows, one: () => rows[0] };
  },
});
const sql = sqlOf(new DatabaseSync(':memory:'));
const ask = (o) => quotaCheck(sql, { kind: 'ask', limit: 3, uid: 'u1', device: 'd1', ...o });
assert.deepEqual(ask({ qid: 'a' }), { ok: true, left: 2 });
assert.equal(ask({ qid: 'a' }).ok, true, 'same question, more requests');
assert.equal(ask({ qid: 'a' }).left, 2, 'not counted twice');
ask({ qid: 'b' });
assert.deepEqual(ask({ qid: 'c' }), { ok: true, left: 0 });
assert.deepEqual(ask({ qid: 'd' }), { ok: false, why: 'quota', left: 0 });
assert.equal(ask({ qid: 'e', uid: 'u2' }).ok, false, 'a new account on the same phone gets nothing');
assert.equal(ask({ qid: 'f', device: 'd2' }).ok, false, 'the same account on a new phone gets nothing');
assert.equal(ask({ qid: 'g', uid: 'u3', device: 'd3' }).ok, true, 'someone else is fine');
assert.equal(ask({ qid: 'a', now: Date.now() + 31 * 60000 }).ok, false, 'an old question id cannot be reused');
assert.equal(ask({ qid: 'h', now: Date.now() + 86400000 }).ok, true, 'a new day');
assert.equal(ask({ qid: '' }).ok, false, 'a question id is required');

// Through the worker, with the Durable Object.
const db = new DatabaseSync(':memory:');
const qo = new Quota({ storage: { sql: sqlOf(db) } });
const authEnv = { ...env, FIREBASE_PROJECT: project, QUOTA: { idFromName: (n) => n, get: () => ({ fetch: (u, i) => qo.fetch(new Request(u, i)) }) } };
const ai = async (extra) => worker.fetch(req('/q/v1/chat/completions', 't', 'POST', extra), authEnv);
r = await ai({});
assert.equal(r.status, 401);
assert.equal(r.headers.get('x-proxy-error'), 'auth');
const good = { 'x-user-token': await token({ sub: 'w1' }), 'x-device-id': 'dev', 'x-question-id': 'q1' };
r = await ai(good);
assert.equal(r.status, 200);
assert.equal(r.headers.get('x-quota-left'), '19');
const forwarded = seen.at(-1).headers;
for (const h of ['x-user-token', 'x-device-id', 'x-question-id']) assert.equal(forwarded.get(h), null, h + ' is not sent on');
for (let i = 2; i <= 20; i++) assert.equal((await ai({ ...good, 'x-question-id': 'q' + i })).status, 200);
r = await ai({ ...good, 'x-question-id': 'q21' });
assert.equal(r.status, 429);
assert.equal(r.headers.get('x-proxy-error'), 'quota');
r = await ai({ ...good, 'x-question-id': 'h1', 'x-kind': 'help' });
assert.equal(r.status, 200, 'the help assistant has its own allowance');
r = await worker.fetch(req('/quota', 't', 'GET', good), authEnv);
assert.deepEqual(await r.json(), { left: 0, limit: 20 });
r = await worker.fetch(req('/q/v1/chat/completions', 't', 'POST', { 'x-ci': 'k1, k2' }), authEnv);
assert.equal(r.status, 200, 'the deploy check passes with the server keys');
console.log('proxy ok');
