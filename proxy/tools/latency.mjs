// Measures how long the live proxy takes to start and finish an answer, per
// model and thinking setting, with the app's real instructions and a small PDF.
// Usage: URL=... APP_TOKEN=... CI_KEY=... node proxy/tools/latency.mjs
import { readFileSync } from 'node:fs';

const { URL: base, APP_TOKEN, CI_KEY } = process.env;
const dart = readFileSync(new URL('../../lib/core/ai.dart', import.meta.url), 'utf8');
const system = dart.match(/const _system = '''\n([\s\S]*?)''';/)[1];

// A one-page PDF with a line of text, built by hand.
function pdf(text) {
  const objs = [
    '<< /Type /Catalog /Pages 2 0 R >>',
    '<< /Type /Pages /Kids [3 0 R] /Count 1 >>',
    '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Contents 4 0 R /Resources << /Font << /F1 5 0 R >> >> >>',
    null,
    '<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>',
  ];
  const stream = `BT /F1 14 Tf 72 700 Td (${text}) Tj ET`;
  objs[3] = `<< /Length ${stream.length} >>\nstream\n${stream}\nendstream`;
  let out = '%PDF-1.4\n';
  const offs = [];
  objs.forEach((o, i) => { offs.push(out.length); out += `${i + 1} 0 obj\n${o}\nendobj\n`; });
  const x = out.length;
  out += `xref\n0 ${objs.length + 1}\n0000000000 65535 f \n` + offs.map((o) => `${String(o).padStart(10, '0')} 00000 n \n`).join('');
  out += `trailer\n<< /Size ${objs.length + 1} /Root 1 0 R >>\nstartxref\n${x}\n%%EOF`;
  return Buffer.from(out).toString('base64');
}
const doc = pdf('Invoice 4471. Total due: 1,250 OMR. Due date: 3 March 2027.');

async function time(model, thinking, question) {
  const body = {
    contents: [{ role: 'user', parts: [
      { text: '[ملف مرفق: invoice.pdf]' },
      { inline_data: { mime_type: 'application/pdf', data: doc } },
      { text: question },
    ] }],
    systemInstruction: { parts: [{ text: system }] },
    ...(thinking == null ? {} : { generationConfig: { thinkingConfig: { thinkingBudget: thinking } } }),
  };
  const t0 = Date.now();
  let first = null, text = '';
  try {
    const r = await fetch(`${base}/g/v1beta/models/${model}:streamGenerateContent?alt=sse`, {
      method: 'POST',
      headers: { 'content-type': 'application/json', 'x-app-token': APP_TOKEN, 'x-ci': CI_KEY },
      body: JSON.stringify(body),
      signal: AbortSignal.timeout(30000),
    });
    const head = Date.now() - t0;
    if (!r.ok) return `${model} think=${thinking}: HTTP ${r.status} after ${head}ms ${(await r.text()).slice(0, 160)}`;
    const dec = new TextDecoder();
    for await (const chunk of r.body) {
      const s = dec.decode(chunk);
      for (const m of s.matchAll(/"text":\s*"((?:[^"\\]|\\.)*)"/g)) {
        if (first == null) first = Date.now() - t0;
        text += JSON.parse(`"${m[1]}"`);
      }
    }
    return `${model} think=${thinking}: headers ${head}ms, first text ${first}ms, done ${Date.now() - t0}ms — ${text.replace(/\s+/g, ' ').slice(0, 90)}`;
  } catch (e) {
    return `${model} think=${thinking}: error ${e.message} after ${Date.now() - t0}ms`;
  }
}

for (const q of ['احفظ الملف', 'كم المبلغ المستحق ومتى؟']) {
  console.log(`\nQ: ${q}`);
  for (const [m, t] of [
    ['gemini-flash-lite-latest', null], ['gemini-flash-latest', null], ['gemini-flash-latest', 512],
    ['gemini-flash-latest', 0], ['gemini-pro-latest', null],
  ]) {
    console.log(await time(m, t, q));
  }
}
