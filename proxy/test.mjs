// node proxy/test.mjs — checks routing, auth and key injection with a stubbed fetch.
import worker, { emailAllowed, verifyIdToken, quotaCheck, _resetJwksForTest, Quota, subscriptionUntil, saveSub, premiumUntil } from './src/index.js';
import { PRODUCT } from './src/play.js';
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
assert.ok(await verifyIdToken(await token({ firebase: { sign_in_provider: 'password' }, email_verified: true, email: 'ali@gmail.com' }), project));
assert.equal(await verifyIdToken(await token({ firebase: { sign_in_provider: 'password' }, email_verified: true, email: 'x@mailinator.com' }), project), null,
  'a throwaway mail service made through the sign-up API is refused');
assert.equal(emailAllowed('ali+2@gmail.com'), false);
assert.equal(emailAllowed('a.li@gmail.com'), false, 'Gmail dot variants');
assert.equal(emailAllowed('a.li@hotmail.com'), true);
assert.equal(emailAllowed('ALI@Outlook.com'), true);
assert.equal(emailAllowed(''), false);
assert.ok(await verifyIdToken(await token({ firebase: { sign_in_provider: 'google.com' }, email: 'a.b@company.com' }), project), 'Google accounts are not limited');

// Path tricks do not reach other endpoints.
for (const p of ['/g/v1beta/models/gemini..%2f..%2ftunedModels:generateContent', '/g/v1beta/tunedModels', '/g/v1beta/models/x:generateContent/extra',
  '/q/v1/files', '/g/upload/v1beta/files/../../v1beta/cachedContents']) {
  const res = await worker.fetch(req(p), env);
  assert.ok([403, 404].includes(res.status), p + ' -> ' + res.status);
}

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
assert.deepEqual(ask({ qid: 'a' }), { ok: true, left: 2, fresh: true });
assert.equal(ask({ qid: 'a' }).ok, true, 'same question, more requests');
assert.equal(ask({ qid: 'a' }).left, 2, 'not counted twice');
ask({ qid: 'b' });
assert.deepEqual(ask({ qid: 'c' }), { ok: true, left: 0, fresh: true });
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
assert.deepEqual(await r.json(), { left: 0, limit: 20, plan: 'free', until: 0, verify: false });
r = await ai({ ...good, 'x-question-id': 'q22', 'x-plan': 'premium' });
assert.equal(r.status, 429, 'saying "premium" does not unlock the paid limits');
r = await ai({ ...good, 'x-question-id': 'v1', 'x-kind': 'voice' });
assert.equal(r.status, 200, 'voice has its own allowance');
assert.equal(r.headers.get('x-quota-limit'), '30');

// Voice: speech to text only on Groq.
r = await worker.fetch(req('/q/v1/audio/transcriptions'), env);
assert.equal(r.status, 200);
assert.equal(seen.at(-1).url, 'https://api.groq.com/openai/v1/audio/transcriptions');
r = await worker.fetch(req('/o/v1/audio/transcriptions'), { ...env, OPENROUTER_KEYS: 'o1' });
assert.equal(r.status, 403, 'not on other services');

// Public pages need no app token.
for (const path of ['/privacy', '/delete']) {
  r = await worker.fetch(new Request('https://proxy.example' + path), env);
  assert.equal(r.status, 200, path);
  assert.match(r.headers.get('content-type'), /text\/html/);
  assert.match(await r.text(), /5azuy2@gmail\.com/);
}

// Subscriptions.
const tnow = Date.now();
const item = (ms, productId = PRODUCT) => [{ productId, expiryTime: new Date(tnow + ms).toISOString() }];
assert.ok(subscriptionUntil({ subscriptionState: 'SUBSCRIPTION_STATE_ACTIVE', lineItems: item(86400000, 'file_chat_premium_yearly') }, tnow) > tnow, 'the yearly plan counts');
assert.equal(subscriptionUntil({ subscriptionState: 'SUBSCRIPTION_STATE_ACTIVE', lineItems: item(86400000, 'other') }, tnow), 0, 'other products do not');
assert.ok(subscriptionUntil({ subscriptionState: 'SUBSCRIPTION_STATE_ACTIVE', lineItems: item(86400000) }, tnow) > tnow);
assert.ok(subscriptionUntil({ subscriptionState: 'SUBSCRIPTION_STATE_CANCELED', lineItems: item(86400000) }, tnow) > tnow, 'cancelled keeps access until the end');
assert.equal(subscriptionUntil({ subscriptionState: 'SUBSCRIPTION_STATE_EXPIRED', lineItems: item(86400000) }, tnow), 0);
assert.equal(subscriptionUntil({ subscriptionState: 'SUBSCRIPTION_STATE_ACTIVE', lineItems: item(-1000) }, tnow), 0);
assert.equal(subscriptionUntil({ subscriptionState: 'SUBSCRIPTION_STATE_ACTIVE', lineItems: [{ productId: 'other', expiryTime: new Date(tnow + 9e6).toISOString() }] }, tnow), 0);
const sdb = sqlOf(new DatabaseSync(':memory:'));
assert.equal(saveSub(sdb, { token: 'T1', uid: 'a', expiry: tnow + 1000, tnow }).ok, true);
assert.equal(premiumUntil(sdb, 'a', tnow), tnow + 1000);
assert.equal(saveSub(sdb, { token: 'T1', uid: 'b', expiry: tnow + 1000, tnow }).why, 'other-account', 'one subscription, one account');
assert.equal(premiumUntil(sdb, 'a', tnow + 2000), 0, 'expired');

// /purchase checks the token with Google Play, then the account gets the paid limits.
r = await worker.fetch(req('/purchase', 't', 'POST', good), authEnv);
assert.equal(r.status, 503, 'without a service account nothing is unlocked');
const pk = await crypto.subtle.generateKey({ name: 'RSASSA-PKCS1-v1_5', modulusLength: 2048, publicExponent: new Uint8Array([1, 0, 1]), hash: 'SHA-256' }, true, ['sign', 'verify']);
const pkcs8 = Buffer.from(await crypto.subtle.exportKey('pkcs8', pk.privateKey)).toString('base64');
const sa = JSON.stringify({ client_email: 'play@x.iam.gserviceaccount.com', private_key: `-----BEGIN PRIVATE KEY-----\n${pkcs8}\n-----END PRIVATE KEY-----\n` });
const stubFetch = globalThis.fetch;
let playState = 'SUBSCRIPTION_STATE_ACTIVE';
globalThis.fetch = async (url, init) => {
  url = String(url);
  if (url === 'https://oauth2.googleapis.com/token') {
    const jwt = new URLSearchParams(init.body).get('assertion').split('.');
    const ok = await crypto.subtle.verify('RSASSA-PKCS1-v1_5', pk.publicKey, Buffer.from(jwt[2], 'base64url'), new TextEncoder().encode(jwt[0] + '.' + jwt[1]));
    assert.ok(ok, 'the OAuth assertion is signed with the service account key');
    return Response.json({ access_token: 'AT', expires_in: 3600 });
  }
  if (url.startsWith('https://androidpublisher.googleapis.com/')) {
    assert.equal(init.headers.authorization, 'Bearer AT');
    assert.match(url, /applications\/com\.zuhair\.file_chat\/purchases\/subscriptionsv2\/tokens\/purchase-token-123$/);
    return Response.json({ subscriptionState: playState, lineItems: item(30 * 86400000) });
  }
  return stubFetch(url, init);
};
const playEnv = { ...authEnv, PLAY_SERVICE_ACCOUNT: sa };
const buy = (body, h = good) => worker.fetch(new Request('https://proxy.example/purchase', {
  method: 'POST', headers: { 'x-app-token': 't', ...h }, body: JSON.stringify(body) }), playEnv);
r = await buy({ purchaseToken: 'purchase-token-123' });
let j = await r.json();
assert.equal(j.premium, true);
r = await worker.fetch(req('/quota', 't', 'GET', good), playEnv);
j = await r.json();
assert.equal(j.plan, 'premium');
assert.equal(j.limit, 300);
r = await ai({ ...good, 'x-question-id': 'q23' });
assert.equal(r.status, 200, 'a verified subscriber can keep asking');
const other = { ...good, 'x-user-token': await token({ sub: 'w2' }), 'x-device-id': 'dev2' };
j = await (await buy({ purchaseToken: 'purchase-token-123' }, other)).json();
assert.deepEqual([j.premium, j.why], [false, 'other-account'], 'the same purchase cannot unlock another account');
playState = 'SUBSCRIPTION_STATE_EXPIRED';
const third = { ...good, 'x-user-token': await token({ sub: 'w3' }) };
j = await (await buy({ purchaseToken: 'purchase-token-123' }, third)).json();
assert.equal(j.premium, false);
assert.equal((await buy({ purchaseToken: '../x' })).status, 400);
globalThis.fetch = stubFetch;

// Deleting the account removes its subscription; counts stay until they expire.
r = await worker.fetch(req('/account', 't', 'DELETE', good), playEnv);
assert.equal(r.status, 200);
r = await worker.fetch(req('/quota', 't', 'GET', good), playEnv);
j = await r.json();
assert.deepEqual([j.plan, j.left, j.verify], ['free', 0, true], 'deleting does not hand out new free questions');
r = await worker.fetch(req('/account', 't', 'DELETE', {}), authEnv);
assert.equal(r.status, 401);

// The owner's dashboard.
const adminEnv = { ...authEnv, ADMIN_EMAILS: 'boss@gmail.com, other@hotmail.com' };
const bossTok = await token({ sub: 'boss', email: 'Boss@gmail.com', email_verified: true, firebase: { sign_in_provider: 'google.com' } });
r = await worker.fetch(req('/admin', 't', 'GET', good), adminEnv);
assert.equal(r.status, 403, 'other accounts cannot open it');
r = await worker.fetch(req('/admin', 't', 'GET', {}), adminEnv);
assert.equal(r.status, 401);
r = await worker.fetch(req('/admin', 't', 'GET', { 'x-user-token': await token({ sub: 'fake', email: 'boss@gmail.com', email_verified: false }) }), adminEnv);
assert.equal(r.status, 403, 'an unconfirmed address is not enough');
const userTok = await token({ sub: 'u-mail', email: 'sara@hotmail.com', email_verified: true, firebase: { sign_in_provider: 'password' } });
r = await worker.fetch(req('/q/v1/chat/completions', 't', 'POST', { 'x-user-token': userTok, 'x-device-id': 'dd', 'x-question-id': 's1' }), adminEnv);
assert.equal(r.status, 200);
await worker.fetch(req('/q/v1/chat/completions', 't', 'POST', { 'x-user-token': userTok, 'x-device-id': 'dd', 'x-question-id': 's1' }), adminEnv);
r = await worker.fetch(req('/admin', 't', 'GET', { 'x-user-token': bossTok }), adminEnv);
assert.equal(r.status, 200);
j = await r.json();
const sara = j.users.find((u) => u.uid === 'u-mail');
assert.deepEqual([sara.email, sara.provider, sara.questions, sara.today], ['sara@hotmail.com', 'password', 1, 1], 'one question even with two requests');
assert.ok(j.totals.users >= 1 && j.totals.questionsToday >= 1 && j.days.length === 14);
assert.equal(j.totals.byEmail, 1);

// The owner has the paid plan without a practical limit.
j = await (await worker.fetch(req('/quota', 't', 'GET', { 'x-user-token': bossTok }), adminEnv)).json();
assert.deepEqual([j.plan, j.limit >= 100000, j.until > Date.now() + 50 * 365 * 86400000], ['premium', true, true]);
for (let i = 0; i < 25; i++) {
  r = await worker.fetch(req('/q/v1/chat/completions', 't', 'POST', { 'x-user-token': bossTok, 'x-question-id': 'boss' + i }), adminEnv);
  assert.equal(r.status, 200, 'owner question ' + i);
}

// A lifetime account: the paid plan with its usual limit, forever, and no dashboard.
const lifeEnv = { ...adminEnv, LIFETIME_EMAILS: 'friend@gmail.com' };
const friendTok = await token({ sub: 'friend', email: 'Friend@gmail.com', email_verified: true, firebase: { sign_in_provider: 'google.com' } });
j = await (await worker.fetch(req('/quota', 't', 'GET', { 'x-user-token': friendTok }), lifeEnv)).json();
assert.deepEqual([j.plan, j.limit, j.until > Date.now() + 50 * 365 * 86400000], ['premium', 300, true]);
assert.equal((await worker.fetch(req('/admin', 't', 'GET', { 'x-user-token': friendTok }), lifeEnv)).status, 403, 'no dashboard');
const unconfirmedTok = await token({ sub: 'friend2', email: 'friend@gmail.com', email_verified: false, firebase: { sign_in_provider: 'password' } });
r = await worker.fetch(req('/quota', 't', 'GET', { 'x-user-token': unconfirmedTok }), lifeEnv);
assert.ok(r.status === 401 || (await r.json()).plan === 'free', 'an unconfirmed address does not get it');

// Blocking from the dashboard.
const adminPost = (body, tok = bossTok) => worker.fetch(new Request('https://proxy.example/admin', {
  method: 'POST', headers: { 'x-app-token': 't', 'x-user-token': tok }, body: JSON.stringify(body) }), adminEnv);
assert.equal((await adminPost({ uid: 'u-mail', block: true }, userTok)).status, 403, 'only the owner can block');
assert.equal((await adminPost({ uid: 'boss', block: true })).status, 400, 'the owner cannot lock himself out');
assert.equal((await adminPost({ uid: 'u-mail', block: true })).status, 200);
r = await worker.fetch(req('/q/v1/chat/completions', 't', 'POST', { 'x-user-token': userTok, 'x-device-id': 'dd', 'x-question-id': 's2' }), adminEnv);
assert.deepEqual([r.status, r.headers.get('x-proxy-error')], [403, 'blocked']);
r = await worker.fetch(req('/quota', 't', 'GET', { 'x-user-token': userTok }), adminEnv);
assert.equal(r.status, 403, 'a blocked account gets nothing');
j = await (await worker.fetch(req('/admin', 't', 'GET', { 'x-user-token': bossTok }), adminEnv)).json();
assert.equal(j.users.find((u) => u.uid === 'u-mail').blocked, 1);
assert.equal(j.totals.blocked, 1);
assert.equal((await adminPost({ uid: 'u-mail', block: false })).status, 200);
r = await worker.fetch(req('/q/v1/chat/completions', 't', 'POST', { 'x-user-token': userTok, 'x-device-id': 'dd', 'x-question-id': 's3' }), adminEnv);
assert.equal(r.status, 200, 'unblocked');
r = await worker.fetch(req('/q/v1/chat/completions', 't', 'POST', { 'x-ci': 'k1, k2' }), authEnv);
assert.equal(r.status, 200, 'the deploy check passes with the server keys');
console.log('proxy ok');
