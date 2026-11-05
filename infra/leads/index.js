// Приём заявок с сайта yustika.ru (Yandex Cloud Functions, Node.js).
// 1) проверяет заявку, 2) сохраняет в закрытый бакет (серверы в РФ),
// 3) присылает письмо на почту и сообщение в MAX.
// Секреты приходят через переменные окружения функции, в коде их нет.

const ALLOWED = (process.env.ALLOWED_ORIGINS || 'https://yustika.ru,https://www.yustika.ru').split(',');
const FORMS = { callback: 'Обратный звонок', booking: 'Запись на разбор' };
const FIELDS = { contact: 'Контакт', name: 'Имя', when: 'Когда удобно', format: 'Формат', day: 'День', time: 'Время', about: 'О ситуации' };

const clip = (v, n) => String(v ?? '').replace(/[\u0000-\u0008\u000B-\u001F]/g, '').trim().slice(0, n);

function cors(origin) {
  const ok = ALLOWED.includes(origin);
  return {
    'Access-Control-Allow-Origin': ok ? origin : ALLOWED[0],
    'Access-Control-Allow-Methods': 'POST, OPTIONS',
    'Access-Control-Allow-Headers': 'Content-Type',
    'Access-Control-Max-Age': '86400',
    Vary: 'Origin',
  };
}

const reply = (code, origin, obj) => ({ statusCode: code, headers: { ...cors(origin), 'Content-Type': 'application/json' }, body: JSON.stringify(obj) });

async function saveLead(token, lead) {
  const d = new Date(lead.receivedAt);
  const key = `leads/${d.toISOString().slice(0, 7)}/${lead.receivedAt.replace(/[:.]/g, '-')}-${lead.id}.json`;
  const r = await fetch(`https://storage.yandexcloud.net/${process.env.LEADS_BUCKET}/${key}`, {
    method: 'PUT',
    headers: { 'X-YaCloud-SubjectToken': token, 'Content-Type': 'application/json; charset=utf-8' },
    body: JSON.stringify(lead, null, 2),
  });
  if (!r.ok) throw new Error('storage ' + r.status);
}

async function sendMail(token, subject, text) {
  const r = await fetch('https://postbox.cloud.yandex.net/v2/email/outbound-emails', {
    method: 'POST',
    headers: { 'X-YaCloud-SubjectToken': token, 'Content-Type': 'application/json' },
    body: JSON.stringify({
      FromEmailAddress: `Сайт Юстика <${process.env.MAIL_FROM}>`,
      Destination: { ToAddresses: [process.env.MAIL_TO] },
      Content: { Simple: { Subject: { Data: subject, Charset: 'UTF-8' }, Body: { Text: { Data: text, Charset: 'UTF-8' } } } },
    }),
  });
  if (!r.ok) throw new Error('postbox ' + r.status + ' ' + (await r.text()).slice(0, 200));
}

async function sendMax(text) {
  const r = await fetch(`https://platform-api2.max.ru/messages?user_id=${process.env.MAX_USER_ID}`, {
    method: 'POST',
    headers: { Authorization: process.env.MAX_BOT_TOKEN, 'Content-Type': 'application/json' },
    body: JSON.stringify({ text }),
  });
  if (!r.ok) throw new Error('max ' + r.status);
}

module.exports.handler = async (event, context) => {
  const origin = (event.headers && (event.headers.Origin || event.headers.origin)) || '';
  if (event.httpMethod === 'OPTIONS') return reply(204, origin, {});
  if (event.httpMethod !== 'POST') return reply(405, origin, { ok: false });
  if (!ALLOWED.includes(origin)) return reply(403, origin, { ok: false });

  let data;
  try {
    const raw = event.isBase64Encoded ? Buffer.from(event.body || '', 'base64').toString('utf8') : event.body || '';
    if (raw.length > 10000) return reply(413, origin, { ok: false });
    data = JSON.parse(raw);
  } catch {
    return reply(400, origin, { ok: false });
  }
  // Ловушка для спам-ботов: скрытое поле, человек его не заполняет
  if (data.company) return reply(200, origin, { ok: true });

  const lead = {
    id: Math.random().toString(36).slice(2, 10),
    receivedAt: new Date().toISOString(),
    form: FORMS[data.form] ? data.form : 'other',
    page: clip(data.page, 200),
  };
  for (const k of Object.keys(FIELDS)) {
    const v = clip(data[k], k === 'about' ? 2000 : 200);
    if (v) lead[k] = v;
  }
  if (!lead.contact) return reply(422, origin, { ok: false, error: 'contact' });

  const title = `${FORMS[lead.form] || 'Заявка'}: ${lead.contact}`;
  const lines = Object.entries(FIELDS).filter(([k]) => lead[k]).map(([k, l]) => `${l}: ${lead[k]}`);
  const time = new Date(lead.receivedAt).toLocaleString('ru-RU', { timeZone: 'Europe/Moscow' });
  const text = [`Новая заявка с сайта yustika.ru`, `Тип: ${FORMS[lead.form] || 'другое'}`, ...lines, `Страница: ${lead.page || '—'}`, `Время: ${time} (МСК)`].join('\n');

  const token = context && context.token && context.token.access_token;
  const results = await Promise.allSettled([
    saveLead(token, lead),
    sendMail(token, title, text),
    sendMax('🔔 ' + text),
  ]);
  const failed = results.map((r, i) => (r.status === 'rejected' ? ['storage', 'mail', 'max'][i] + ': ' + r.reason.message : null)).filter(Boolean);
  if (failed.length) console.error('lead', lead.id, 'partial failure', failed.join('; '));
  // Заявка принята, если сохранилась или дошло хотя бы одно уведомление
  if (failed.length === 3) return reply(502, origin, { ok: false });
  return reply(200, origin, { ok: true });
};
