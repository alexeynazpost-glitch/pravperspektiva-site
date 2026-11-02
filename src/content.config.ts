import { defineCollection, z } from 'astro:content';
import { glob } from 'astro/loaders';

// Статьи блога: один файл .md в папке src/content/blog/ = одна статья.
const blog = defineCollection({
  loader: glob({ pattern: '**/*.md', base: './src/content/blog' }),
  schema: z.object({
    title: z.string(), // заголовок H1
    seoTitle: z.string().optional(), // заголовок для Яндекса, если отличается
    description: z.string(), // описание для Яндекса
    rubric: z.enum(['posledstviya', 'procedura', 'mfc', 'dolgi', 'imushchestvo', 'semya']),
    summary: z.string(), // «Коротко:» под заголовком
    date: z.coerce.date(),
    updated: z.coerce.date().optional(),
    faq: z.array(z.object({ q: z.string(), a: z.string() })).default([]),
    draft: z.boolean().default(false),
  }),
});

export const collections = { blog };
