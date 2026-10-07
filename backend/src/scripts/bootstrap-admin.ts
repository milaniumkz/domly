import bcrypt from 'bcryptjs';
import { env } from '../common/env';
import { Database } from '../infrastructure/db/Database';
import { normalizePhone } from '../modules/domainServices';

async function main() {
  const db = new Database(env.databaseUrl);
  const phone = normalizePhone(process.env.ADMIN_BOOTSTRAP_PHONE ?? '+77781110170');
  const fullName = process.env.ADMIN_BOOTSTRAP_NAME ?? 'DOMLY Superadmin';
  const password = process.env.ADMIN_BOOTSTRAP_PASSWORD;
  const resetPassword = process.env.ADMIN_BOOTSTRAP_RESET_PASSWORD === 'true';
  if (!password) throw new Error('ADMIN_BOOTSTRAP_PASSWORD is required');
  validateBootstrapPassword(password);
  const hash = await bcrypt.hash(password, 10);
  try {
    const admin = (await db.query<{ id: string; password_hash: string | null }>(
      `INSERT INTO app_users (phone, role, password_hash, full_name, status, is_phone_verified)
       VALUES ($1,'superadmin',$2,$4,'approved',TRUE)
       ON CONFLICT (phone) DO UPDATE SET
         role='superadmin',
         password_hash=CASE
           WHEN $3::boolean OR app_users.password_hash IS NULL THEN EXCLUDED.password_hash
           ELSE app_users.password_hash
         END,
         full_name=COALESCE(NULLIF(app_users.full_name,''), EXCLUDED.full_name),
         status='approved',
         is_phone_verified=TRUE,
         updated_at=NOW()
       RETURNING id, password_hash`,
      [phone, hash, resetPassword, fullName],
    )).rows[0];
    const settings: Record<string, unknown> = {
      baseCleaningMinutes: 120,
      minutesPerM2: 1.2,
      slotStartTimes: ['08:00', '10:00', '12:00', '14:00', '16:00'],
      qualityCheckHours: 48,
      bonusPaymentEnabled: true,
      defaultBonusMaxPercent: 50,
      minBookingDate: null,
      cleanerOfferTtlMinutes: 2,
      cleanerQuietHoursEnabled: false,
      cleanerQuietHoursStart: '23:00',
      cleanerQuietHoursEnd: '07:00',
      requireAvailableCleaner: true,
      allowCustomTime: false,
      scrollToPendingAfterAddonSelection: true,
      allowBonusForPackagePurchase: false,
      skipZeroAmountInvoice: true,
      qualityCheckRequiredAfterPackagePurchase: true,
      qualityCheckNotificationTitleRu: 'Назначена проверка площади',
      qualityCheckNotificationBodyRu: 'В течение 48 часов отдел контроля качества приедет к вам для проверки площади. Также вы можете пройти проверку в приложении, загрузив план квартиры.',
      qualityCheckNotificationTitleKk: 'Ауданды тексеру тағайындалды',
      qualityCheckNotificationBodyKk: '48 сағат ішінде сапаны бақылау бөлімі пәтер ауданын тексеру үшін келеді. Сонымен қатар қосымшада пәтер жоспарын жүктеп, тексеруден өте аласыз.',
      featureFlags: {
        preordersEnabled: true,
        qualityCheckEnabled: true,
        onlinePaymentEnabled: true,
        kaspiPaymentEnabled: true,
        bonusPaymentEnabled: true,
        cleanerManualAssignmentEnabled: true,
        inAppTrainingEnabled: true,
      },
      customerTabs: ['home', 'orders', 'profile', 'notifications', 'settings'],
      cleanerTabs: ['home', 'calendar', 'orders', 'messages', 'profile'],
      paymentFlow: {
        afterInvoiceAction: 'home',
        showPackagePurchaseButtonUntilPaid: true,
        showCleaningOrderButtonOnlyWithAvailableCleanings: true,
        requireBonusCheckbox: true,
        hideExternalInvoiceForZeroPayable: true,
      },
      uiBehavior: {
        customerHomeOrderCardAction: 'booking',
        addonSelectionAfterApply: 'pending_orders',
        packageSelectionPosition: 'center',
        bannerFit: 'contain',
        autoRotateImportantBanners: true,
        bottomNavEvenSpacing: true,
      },
      validationRules: {
        areaInput: 'decimal_round_up',
        requireAreaBeforePackage: true,
        requireQualityCheckPhotoAndArea: true,
        addressSearchLimit: 10,
        addressSearchRadiusKm: 50,
      },
      errorMessages: {
        unauthorized: {
          ru: 'Сессия истекла. Войдите заново.',
          kk: 'Сессия аяқталды. Қайта кіріңіз.',
        },
        paymentRequired: {
          ru: 'Сначала подтвердите оплату.',
          kk: 'Алдымен төлемді растаңыз.',
        },
        cleanerUnavailable: {
          ru: 'На это время нет свободной уборщицы. Выберите другое время.',
          kk: 'Бұл уақытта бос орындаушы жоқ. Басқа уақыт таңдаңыз.',
        },
      },
      appText: {
        qualityCheck48h: {
          ru: 'В течение 48 часов отдел контроля качества приедет к вам для проверки площади.',
          kk: '48 сағат ішінде сапаны бақылау бөлімі ауданды тексеру үшін келеді.',
        },
        bonusPaymentLabel: {
          ru: 'Оплатить бонусами',
          kk: 'Бонустармен төлеу',
        },
      },
    };
    for (const [key, value] of Object.entries(settings)) {
      await db.query(
        `INSERT INTO app_settings (key, value, updated_at) VALUES ($1,$2,NOW())
         ON CONFLICT (key) DO UPDATE SET value=EXCLUDED.value, updated_at=NOW()`,
        [key, JSON.stringify(value)],
      );
    }
    const translations = [
      ['error.unauthorized', 'Войдите в аккаунт заново.', 'Аккаунтқа қайта кіріңіз.', 'errors'],
      ['error.invalid_credentials', 'Неверный телефон или пароль.', 'Телефон немесе құпиясөз қате.', 'errors'],
      ['order.new_offer.title', 'Новый заказ', 'Жаңа тапсырыс', 'notifications'],
      ['order.new_offer.body', 'Вам поступил новый заказ на подтверждение.', 'Сізге растауға жаңа тапсырыс келді.', 'notifications'],
      ['payment.confirmed.title', 'Оплата подтверждена', 'Төлем расталды', 'notifications'],
    ];
    for (const [key, ru, kk, namespace] of translations) {
      await db.query(
        `INSERT INTO translations (key, ru, kk, namespace, updated_at) VALUES ($1,$2,$3,$4,NOW())
         ON CONFLICT (key) DO UPDATE SET ru=EXCLUDED.ru, kk=EXCLUDED.kk, namespace=EXCLUDED.namespace, updated_at=NOW()`,
        [key, ru, kk, namespace],
      );
    }
    const contentPages = [
      {
        slug: 'privacy-policy',
        titleRu: 'Политика конфиденциальности',
        titleKk: 'Құпиялылық саясаты',
        kind: 'legal',
        bodyRu: [
          '1. Какие данные собираются',
          'DOMLY может собирать имя, номер телефона, адрес, город, координаты дома, данные заказов, оплат, сообщений, фотографий отчетов, жалоб, отзывов и техническую информацию приложения.',
          '',
          '2. Для чего используются данные',
          'Данные нужны для регистрации, подтверждения адреса и площади, расчета стоимости, приема оплаты, назначения исполнителя, выполнения уборки, поддержки клиента, уведомлений и контроля качества.',
          '',
          '3. Передача данных',
          'DOMLY передает исполнителю только данные, необходимые для выполнения заказа: адрес, время, параметры уборки, чек-лист и контактные данные для связи по заказу. Данные оплаты обрабатываются платежными провайдерами.',
          '',
          '4. Хранение и защита',
          'DOMLY хранит данные в защищенной серверной инфраструктуре и применяет технические меры защиты доступа. Доступ к данным предоставляется только пользователю, исполнителю, администратору и сервисным ролям в рамках их задач.',
          '',
          '5. Права пользователя',
          'Пользователь может запросить уточнение, исправление или удаление своих данных через поддержку DOMLY, если хранение этих данных больше не требуется для исполнения обязательств и требований закона.',
          '',
          '6. Реквизиты организации',
          'Наименование: ТОО "DomLY"',
          'БИН: 260440000313',
          'Юридический адрес: Адрес уточняется',
          'Телефон: +7 777 040 9606',
          'Email: milaniumkz@yandex.kz',
        ].join('\n'),
        bodyKk: [
          '1. Қандай деректер жиналады',
          'DOMLY пайдаланушының аты-жөнін, телефон нөмірін, мекенжайын, қаласын, үй координаттарын, тапсырыстар, төлемдер, хабарламалар, есеп фотосуреттері, шағымдар, пікірлер және қосымшаның техникалық ақпаратын жинауы мүмкін.',
          '',
          '2. Деректер не үшін пайдаланылады',
          'Деректер тіркелу, мекенжай мен ауданды растау, құнын есептеу, төлем қабылдау, орындаушыны тағайындау, тазалық қызметін орындау, клиентті қолдау, хабарламалар және сапаны бақылау үшін қажет.',
          '',
          '3. Деректерді беру',
          'DOMLY орындаушыға тек тапсырысты орындауға қажетті деректерді береді: мекенжай, уақыт, тазалық параметрлері, чек-лист және тапсырыс бойынша байланыс деректері. Төлем деректерін төлем провайдерлері өңдейді.',
          '',
          '4. Сақтау және қорғау',
          'DOMLY деректерді қорғалған серверлік инфрақұрылымда сақтайды және қолжетімділікті қорғаудың техникалық шараларын қолданады. Деректерге қолжетімділік пайдаланушыға, орындаушыға, әкімшіге және қызметтік рөлдерге олардың міндеттері шегінде беріледі.',
          '',
          '5. Пайдаланушы құқықтары',
          'Пайдаланушы DOMLY қолдау қызметі арқылы өз деректерін нақтылауды, түзетуді немесе жоюды сұрай алады, егер бұл деректерді сақтау міндеттемелерді орындау және заң талаптары үшін қажет болмаса.',
          '',
          '6. Ұйым реквизиттері',
          'Атауы: ТОО "DomLY"',
          'БСН: 260440000313',
          'Заңды мекенжайы: Мекенжай нақтыланады',
          'Телефон: +7 777 040 9606',
          'Email: milaniumkz@yandex.kz',
        ].join('\n'),
      },
      {
        slug: 'public-offer',
        titleRu: 'Публичная оферта',
        titleKk: 'Жария оферта',
        kind: 'legal',
        bodyRu: [
          '1. Модель работы',
          'DOMLY принимает заявки клиента на уборку квартиры или дома, рассчитывает стоимость по выбранному пакету, площади и дополнительным услугам, принимает оплату и передает заказ исполнителю. Исполнитель выполняет уборку по чек-листу, клиент может общаться с исполнителем и поддержкой через приложение.',
          '',
          '2. Оплата',
          'Клиент оплачивает пакет уборки или дополнительные услуги банковской картой через интернет-эквайринг либо через Kaspi.kz. Заказ считается подтвержденным после успешной оплаты или подтверждения счета.',
          '',
          '3. Проверка площади',
          'Если площадь не подтверждена, DOMLY может запросить проверку квадратуры отделом контроля качества. После подтверждения площади стоимость заказа может быть пересчитана.',
          '',
          '4. Отмена и возврат',
          'Отмена и возврат рассматриваются администрацией DOMLY по обращению клиента. Возврат выполняется тем же способом, которым была произведена оплата, если это поддерживается платежной системой.',
          '',
          '5. Реквизиты организации',
          'Наименование: ТОО "DomLY"',
          'БИН: 260440000313',
          'Юридический адрес: Адрес уточняется',
          'Банк: АО «Банк ЦентрКредит»',
          'ИИК: KZ11 8562 2031 5395 7207',
          'БИК: KCJBKZKX',
          'КБе: 17',
          'Валюта: KZT',
          'Телефон: +7 777 040 9606',
          'Email: milaniumkz@yandex.kz',
        ].join('\n'),
        bodyKk: [
          '1. Жұмыс моделі',
          'DOMLY клиенттің пәтер немесе үй тазалау өтінімін қабылдайды, таңдалған пакет, аудан және қосымша қызметтер бойынша құнын есептейді, төлемді қабылдайды және тапсырысты орындаушыға береді. Орындаушы тазалықты чек-лист бойынша орындайды, клиент орындаушымен және қолдау қызметімен қосымша арқылы байланыса алады.',
          '',
          '2. Төлем',
          'Клиент тазалық пакетін немесе қосымша қызметтерді интернет-эквайринг арқылы банк картасымен немесе Kaspi.kz арқылы төлейді. Тапсырыс төлем сәтті өткеннен немесе шот расталғаннан кейін расталған болып саналады.',
          '',
          '3. Ауданды тексеру',
          'Егер аудан расталмаған болса, DOMLY сапаны бақылау бөлімі арқылы аудан тексерісін сұрата алады. Аудан расталғаннан кейін тапсырыс құны қайта есептелуі мүмкін.',
          '',
          '4. Бас тарту және қайтару',
          'Бас тарту және қайтару клиенттің өтініші бойынша DOMLY әкімшілігімен қаралады. Қайтару төлем жасалған тәсілмен орындалады, егер оны төлем жүйесі қолдаса.',
          '',
          '5. Ұйым реквизиттері',
          'Атауы: ТОО "DomLY"',
          'БСН: 260440000313',
          'Заңды мекенжайы: Мекенжай нақтыланады',
          'Банк: «Банк ЦентрКредит» АҚ',
          'ЖСК: KZ11 8562 2031 5395 7207',
          'БСК: KCJBKZKX',
          'КБе: 17',
          'Валюта: KZT',
          'Телефон: +7 777 040 9606',
          'Email: milaniumkz@yandex.kz',
        ].join('\n'),
      },
    ];
    for (const page of contentPages) {
      await db.query(
        `INSERT INTO content_pages (slug, title_ru, title_kk, body_ru, body_kk, kind, active)
         VALUES ($1,$2,$3,$4,$5,$6,TRUE)
         ON CONFLICT (slug) DO UPDATE SET
           title_ru=EXCLUDED.title_ru,
           title_kk=EXCLUDED.title_kk,
           body_ru=EXCLUDED.body_ru,
           body_kk=EXCLUDED.body_kk,
           kind=EXCLUDED.kind,
           updated_at=NOW()`,
        [page.slug, page.titleRu, page.titleKk, page.bodyRu, page.bodyKk, page.kind],
      );
    }
    console.log(`Superadmin ready: ${phone} (${admin?.id ?? 'created'})`);
    if (!resetPassword) console.log('Existing password is preserved unless ADMIN_BOOTSTRAP_RESET_PASSWORD=true.');
  } finally {
    await db.close();
  }
}

export function validateBootstrapPassword(password: string) {
  const normalized = password.toLowerCase();
  if (password.length < 8) throw new Error('ADMIN_BOOTSTRAP_PASSWORD must be at least 8 characters');
  if (normalized.includes('change_me') || normalized === 'password' || normalized === '12345678' || normalized === '123456') {
    throw new Error('ADMIN_BOOTSTRAP_PASSWORD must be changed from placeholder');
  }
}

if (require.main === module) {
  main().catch((error) => {
    console.error(error);
    process.exit(1);
  });
}
