// Общие данные сайта. Всё, что помечено ЗАПОЛНИТЬ, — ждёт данных от Алексея.

export const site = {
  name: 'Юстика',
  tagline: 'Банкротство физлиц и ИП',
  url: 'https://yustika.ru',
  expert: 'Алексей Назаркин',
  expertRole: 'Руководитель «Юстики», 10 лет в банкротстве физлиц',
  phone: '+7 (995) 157-89-88',
  phoneHref: 'tel:+79951578988',
  phoneE164: '+79951578988',
  hours: 'Ежедневно с 8:00 до 20:00',
  officeHours: 'Офис: пн–пт, сб–вс — по записи',
  address: 'Сергиев Посад, пр. Красной Армии, 212Б, офис 13',
  addressShort: 'Сергиев Посад, пр. Красной Армии, 212Б, оф. 13',
  addressStreet: 'пр. Красной Армии, 212Б, офис 13',
  city: 'Сергиев Посад',
  region: 'Московская область',
  mapUrl: 'https://yandex.ru/maps/?text=' + encodeURIComponent('Сергиев Посад, проспект Красной Армии, 212Б'),
  requisites: 'ИП Назаркин Вячеслав Владимирович · ИНН 644300063770 · ОГРНИП 304644317400020',
  ipName: 'ИП Назаркин Вячеслав Владимирович',
  inn: '644300063770',
  ogrnip: '304644317400020',
  // ЗАПОЛНИТЬ: ссылки на мессенджеры (пока ведут на страницу контактов)
  messengers: [
    { name: 'MAX', href: '', primary: true },
    { name: 'Telegram', href: '' },
    { name: 'ВКонтакте', href: '' },
  ],
  // ЗАПОЛНИТЬ: почта для запросов по персональным данным
  email: 'info@yustika.ru',
  disclaimer:
    'Банкротство влечет негативные последствия, в том числе ограничения на получение кредита и повторное банкротство в течение пяти лет. Предварительно обратитесь к своему кредитору и в МФЦ.',
};

export const messengerHref = (m: { href: string }) => m.href || '/kontakty/#srazu';

export const nav = [
  { href: '/#uslugi', label: 'Услуги' },
  { href: '/ceny/', label: 'Цены' },
  { href: '/kejsy/', label: 'Кейсы' },
  { href: '/blog/', label: 'Блог' },
  { href: '/o-kompanii/', label: 'О нас' },
  { href: '/kontakty/', label: 'Контакты' },
];

export const services = [
  { href: '/bankrotstvo-fizlic/', label: 'Судебное банкротство' },
  { href: '/bankrotstvo-cherez-mfc/', label: 'Банкротство через МФЦ' },
  { href: '/konsultaciya/', label: 'Бесплатная консультация' },
  { href: '/bankrotstvo-ip/', label: 'Банкротство ИП' },
  { href: '/bankrotstvo-s-ipotekoj/', label: 'Банкротство с ипотекой и авто' },
  { href: '/zayavlenie-kreditora/', label: 'Если на банкротство подал кредитор' },
  { href: '/zashchita-ot-kollektorov/', label: 'Защита от коллекторов' },
  { href: '/snyatie-aresta-so-schetov/', label: 'Снятие арестов со счетов' },
  { href: '/osparivanie-dolgov/', label: 'Отмена судебного приказа' },
  { href: '/restrukturizaciya-dolgov/', label: 'Реструктуризация долгов' },
];

export const cityLinks = [
  { slug: 'pushkino', label: 'Пушкино' },
  { slug: 'mytishchi', label: 'Мытищи' },
  { slug: 'korolev', label: 'Королёв' },
  { slug: 'shchelkovo', label: 'Щёлково' },
  { slug: 'dmitrov', label: 'Дмитров' },
];

export const blogRubrics = [
  { slug: 'posledstviya', label: 'Последствия и жизнь после' },
  { slug: 'procedura', label: 'Как проходит процедура' },
  { slug: 'mfc', label: 'Банкротство через МФЦ' },
  { slug: 'dolgi', label: 'Какие долги списываются' },
  { slug: 'imushchestvo', label: 'Имущество' },
  { slug: 'semya', label: 'Семья' },
];

export const prices = [
  { cond: 'Если у вас 1–3 кредитора и нет имущества', price: '100 000 ₽', note: 'или 10 000 ₽ в месяц на 10 месяцев' },
  { cond: 'Если 4–5 кредиторов и нет имущества', price: '110 000 ₽', note: 'или 11 000 ₽ в месяц на 10 месяцев' },
  { cond: 'Если 6–10 кредиторов и нет имущества', price: '130 000 ₽', note: 'или 13 000 ₽ в месяц на 10 месяцев' },
  {
    cond: 'Если есть ипотека, авто, залог или недвижимость — при любом числе кредиторов. Или кредиторов больше 10',
    price: 'обычно 150 000–170 000 ₽',
    note: 'точную сумму и рассрочку — после бесплатного разбора',
    accent: true,
  },
];

export const mandatoryCosts =
  'Обязательные расходы по закону — отдельно: вознаграждение финансового управляющего 25 000 ₽ (вносится на депозит суда), публикации и почта — обычно около 20 000 ₽ в сумме. Точная стоимость фиксируется в договоре.';
