import { defineConfig } from 'astro/config';
import sitemap from '@astrojs/sitemap';
import fs from 'node:fs';
import path from 'node:path';

// Рубрики блога, в которых есть опубликованные статьи: пустые рубрики не попадают в карту сайта
const blogDir = './src/content/blog';
const live = new Set();
const walk = (d) => fs.existsSync(d) ? fs.readdirSync(d, { withFileTypes: true }).flatMap((e) => e.isDirectory() ? walk(path.join(d, e.name)) : e.name.endsWith('.md') ? [path.join(d, e.name)] : []) : [];
for (const f of walk(blogDir)) {
  const fm = (fs.readFileSync(f, 'utf8').match(/^---\n([\s\S]*?)\n---/) || [])[1] || '';
  if (/^draft:\s*true/m.test(fm)) continue;
  const r = (fm.match(/^rubric:\s*['"]?([\w-]+)/m) || [])[1];
  live.add('blog');
  if (r) live.add(r);
}
const keep = (p) => {
  if (p.includes('/404')) return false;
  const m = p.match(/\/blog\/(?:([\w-]+)\/)?$/);
  if (m) return live.has(m[1] || 'blog');
  return true;
};

// Пока сайт не запущен, PUBLIC_NOINDEX=1 закрывает его от поисковиков.
const noindex = process.env.PUBLIC_NOINDEX !== '0';

export default defineConfig({
  site: 'https://fedeta.ru',
  trailingSlash: 'always',
  build: { format: 'directory', inlineStylesheets: 'always' },
  integrations: noindex ? [] : [sitemap({ filter: keep })],
  compressHTML: true,
});
