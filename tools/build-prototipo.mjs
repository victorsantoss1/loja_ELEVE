// Gera prototipo/index.html e prototipo/telas.html a partir do design do canvas.
// Uso: node tools/build-prototipo.mjs
import { readFileSync, writeFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = join(dirname(fileURLToPath(import.meta.url)), '..');
const canvasDir = join(root, 'design', 'canvas');
const outDir = join(root, 'prototipo');

// O logo foi enviado ao canvas como arquivo próprio; aqui ele fica ao lado do HTML.
const LOGO_BLOB = '/_blob/6eb2233143ab3a22f544a783caa330fa';

function between(src, open, close) {
  const a = src.indexOf(open);
  const b = src.indexOf(close, a + open.length);
  if (a < 0 || b < 0) throw new Error(`Trecho não encontrado: ${open} … ${close}`);
  return { inner: src.slice(a + open.length, b), start: a, end: b + close.length };
}

const main = readFileSync(join(canvasDir, 'Main.dc.html'), 'utf8').replaceAll(LOGO_BLOB, 'eleve-logo.png');

const xdc = between(main, '<x-dc>', '</x-dc>').inner;
const helmet = between(xdc, '<helmet>', '</helmet>');
const head = helmet.inner.trim();
const template = (xdc.slice(0, helmet.start) + xdc.slice(helmet.end)).trim();

const scriptOpen = main.indexOf('<script type="text/x-dc"');
const scriptBodyStart = main.indexOf('>', scriptOpen) + 1;
const logic = main.slice(scriptBodyStart, main.indexOf('</script>', scriptBodyStart)).trim();

const index = `<!doctype html>
<html lang="pt-BR">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Eleve — Balcão (protótipo)</title>
<!-- Arquivo gerado por tools/build-prototipo.mjs a partir de design/canvas/Main.dc.html. Não edite à mão. -->
${head}
<style>html,body{height:100%}#root{height:100%}</style>
</head>
<body>
<template id="dc-template">
${template}
</template>
<div id="root"></div>
<script src="vendor/react.production.min.js"></script>
<script src="vendor/react-dom.production.min.js"></script>
<script src="dc-runtime.js"></script>
<script>
${logic}
DC.mount(Component);
</script>
</body>
</html>
`;
writeFileSync(join(outDir, 'index.html'), index);

// telas.html: todas as telas e estados lado a lado, como no canvas.
const canvas = JSON.parse(readFileSync(join(canvasDir, 'canvas.json'), 'utf8'));
const rows = { celular: [], estados: [], desktop: [] };
for (const file of canvas.order) {
  const board = canvas.boards[file];
  if (file === 'Main.dc.html') continue;
  const src = readFileSync(join(canvasDir, file), 'utf8');
  const cen = /cenario="([^"]+)"/.exec(src)?.[1];
  const perfil = /perfil="([^"]+)"/.exec(src)?.[1] ?? 'vendedor';
  if (!cen) continue;
  const item = { title: board.title ?? file, url: `index.html?cenario=${cen}&perfil=${perfil}`, w: board.w, h: board.h };
  if (board.w > 600) rows.desktop.push(item);
  else if (board.y < 2000) rows.celular.push(item);
  else rows.estados.push(item);
}

const esc = (s) => s.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/"/g, '&quot;');
const frame = (it) => `<figure>
  <figcaption><a href="${esc(it.url)}">${esc(it.title)}</a></figcaption>
  <iframe src="${esc(it.url)}" width="${it.w}" height="${it.h}" loading="lazy" title="${esc(it.title)}"></iframe>
</figure>`;
const section = (title, items) => `<section>
<h2>${title}</h2>
<div class="row">
${items.map(frame).join('\n')}
</div>
</section>`;

const telas = `<!doctype html>
<html lang="pt-BR">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Eleve — todas as telas</title>
<!-- Arquivo gerado por tools/build-prototipo.mjs. Não edite à mão. -->
<link href="https://fonts.googleapis.com/css2?family=Anton&family=Space+Mono:wght@700&display=swap" rel="stylesheet">
<style>
body{margin:0;padding:24px 16px 64px;background:#EDE5CE;color:#221B16;font-family:'Space Mono',ui-monospace,monospace}
h1{font-family:'Anton',Impact,sans-serif;font-weight:400;font-size:40px;text-transform:uppercase;margin:0 0 4px}
h2{font-family:'Anton',Impact,sans-serif;font-weight:400;font-size:28px;text-transform:uppercase;margin:40px 0 12px}
p{margin:0;font-size:14px}
.row{display:flex;gap:32px;overflow-x:auto;padding-bottom:16px}
figure{margin:0;flex:0 0 auto}
figcaption{font-size:13px;font-weight:700;margin-bottom:8px}
figcaption a{color:#221B16}
iframe{display:block;border:2px solid #221B16;border-radius:12px;background:#EDE5CE}
</style>
</head>
<body>
<h1>Eleve · Balcão</h1>
<p>Todas as telas do protótipo. Clique no título para abrir a tela sozinha; o primeiro link de cada tela é navegável.</p>
${section('Telas — celular', rows.celular)}
${section('Estados', rows.estados)}
${section('Desktop', rows.desktop)}
</body>
</html>
`;
writeFileSync(join(outDir, 'telas.html'), telas);

console.log(`ok: prototipo/index.html (${index.length} bytes), prototipo/telas.html (${rows.celular.length + rows.estados.length + rows.desktop.length} telas)`);
