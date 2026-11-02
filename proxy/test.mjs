// node proxy/test.mjs — checks routing, auth and key injection with a stubbed fetch.
import worker from './src/index.js';
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
console.log('proxy ok');
