import katex from 'katex';
import fs from 'fs';

const bank = JSON.parse(fs.readFileSync('../data/bank.json', 'utf8'));
const spans = [];   // [context, latex]

function collect(ctx, s) {
  if (!s) return;
  // pull out every $...$ span
  const re = /\$([^$]+)\$/g;
  let m;
  while ((m = re.exec(s)) !== null) spans.push([ctx, m[1]]);
  // an odd number of $ means an unbalanced span — that is a bug
  const count = (s.match(/\$/g) || []).length;
  if (count % 2 !== 0) spans.push([ctx + ' [UNBALANCED $]', null]);
}

for (const q of bank.questions) {
  collect(`${q.code} stem`, q.stem_latex);
  q.options_latex.forEach((o, i) => collect(`${q.code} opt${i}`, o));
  collect(`${q.code} answer`, q.answer_latex);
  q.solution_steps_latex.forEach((s, i) => collect(`${q.code} step${i}`, s));
}

for (const c of bank.concept_sections || []) {
  collect(`${c.chapter}-s${c.idx} title`, c.title);
  for (const [j, b] of (c.body || []).entries()) {
    if (b.text) collect(`${c.chapter}-s${c.idx} b${j}`, b.text);
    (b.lines || []).forEach((l, k) => collect(`${c.chapter}-s${c.idx} b${j}l${k}`, l));
    (b.head || []).forEach((h, k) => collect(`${c.chapter}-s${c.idx} b${j}h${k}`, h));
    (b.rows || []).forEach(r => r.forEach((cell, k) => collect(`${c.chapter}-s${c.idx} b${j}r${k}`, cell)));
    (b.items || []).forEach((it, k) => { collect(`${c.chapter}-s${c.idx} b${j}q${k}`, it.q); collect(`${c.chapter}-s${c.idx} b${j}a${k}`, it.a); });
  }
}

let bad = 0, unbalanced = 0;
const failures = [];
for (const [ctx, tex] of spans) {
  if (tex === null) { unbalanced++; failures.push([ctx, '(unbalanced $)']); continue; }
  try { katex.renderToString(tex, { throwOnError: true }); }
  catch (e) { bad++; failures.push([ctx, tex + '   ->  ' + e.message.split('\n')[0].slice(0, 70)]); }
}
console.log(`maths spans found : ${spans.length}`);
console.log(`parse failures    : ${bad}`);
console.log(`unbalanced $      : ${unbalanced}`);
if (failures.length) {
  console.log('\n--- failures (first 25) ---');
  for (const [c, f] of failures.slice(0, 25)) console.log(`  ${c.padEnd(22)} ${f}`);
  const codes = [...new Set(failures.map(f => f[0].split(' ')[0]))];
  console.log(`\naffected questions: ${codes.length} -> ${codes.slice(0,12).join(', ')}`);
}
