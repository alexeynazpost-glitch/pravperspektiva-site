import { defineConfig } from 'astro/config';
import sitemap from '@astrojs/sitemap';

// Пока сайт не запущен, PUBLIC_NOINDEX=1 закрывает его от поисковиков.
const noindex = process.env.PUBLIC_NOINDEX !== '0';

export default defineConfig({
  site: 'https://yustika.ru',
  trailingSlash: 'always',
  build: { format: 'directory', inlineStylesheets: 'always' },
  integrations: noindex ? [] : [sitemap({ filter: (p) => !p.includes('/404') })],
  compressHTML: true,
});
