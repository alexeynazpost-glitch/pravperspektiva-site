import type { APIRoute } from 'astro';

// Пока сайт в разработке — закрыт для всех роботов.
export const GET: APIRoute = () => {
  const noindex = import.meta.env.PUBLIC_NOINDEX !== '0';
  const body = noindex
    ? 'User-agent: *\nDisallow: /\n'
    : 'User-agent: *\nDisallow: /404/\nDisallow: /*?\n\nSitemap: https://pravperspektiva.ru/sitemap-index.xml\n';
  return new Response(body, { headers: { 'Content-Type': 'text/plain; charset=utf-8' } });
};
