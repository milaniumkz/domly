/**
 * Initialize all admin-driven configuration in Firestore
 * Run: cd functions && node scripts/init_app_config.js
 */

const admin = require('firebase-admin');

if (admin.apps.length === 0) {
  try {
    admin.initializeApp();
  } catch (e) {
    // Already initialized
  }
}

const db = admin.firestore();

async function main() {
  console.log('🚀 Initializing admin-driven config...\n');

  await initAppConfig();
  await initPackageInfo();
  await initAddonInfo();
  await initReferralConfig();
  await initAreaConfig();
  await initWorkerBonusConfig();
  await initUIContent();

  console.log('\n✅ All configurations initialized successfully!');
  console.log('\nCollections created/updated:');
  console.log('  ✓ app_config/main');
  console.log('  ✓ info_content/* (12 documents)');
  console.log('  ✓ referral_config/main');
  console.log('  ✓ area_config/main');
  console.log('  ✓ worker_bonus_config/main');
  console.log('  ✓ ui_content/*');
}

async function initAppConfig() {
  await db.collection('app_config').doc('main').set({
    version: '1.0.0',
    lastUpdated: admin.firestore.FieldValue.serverTimestamp(),
    maintenanceMode: false,
    cleaningFormula: {
      minutesPerSqm: 1.6,
      bufferMinutes: 30,
      maxMinutes: 480,
    },
    featuresEnabled: {
      packages: true,
      calculator: true,
      referrals: true,
      areaConfirmation: true,
      bonuses: true,
      subscriptions: true,
    },
  }, { merge: true });
  
  console.log('✓ app_config/main');
}

async function initPackageInfo() {
  const packages = [
    {
      id: '2x_month',
      key: '2x_month',
      name: '2 раза в месяц',
      title: '2 раза в месяц',
      shortInfo: 'Уборка 2 раза в месяц — идеально для поддержания чистоты',
      fullInfo: 'Пакет включает 2 уборки в месяц (каждые 2 недели). Подходит для тех, кто хочет поддерживать базовую чистоту без частых визитов. Включает все стандартные услуги: мытье полов, протирку пыли, уборку кухни и санузлов.',
      price: 24000,
      frequency: 2,
      isActive: true,
      sortOrder: 1,
      type: 'package',
      features: ['Мытье полов', 'Протирка пыли', 'Уборка кухни', 'Уборка санузлов'],
    },
    {
      id: '4x_month',
      key: '4x_month',
      name: '4 раза в месяц',
      title: '4 раза в месяц',
      shortInfo: 'Еженедельная уборка — оптимальный выбор для большинства',
      fullInfo: 'Пакет включает 4 уборки в месяц (каждую неделю). Самый популярный выбор для поддержания стабильной чистоты. Включает все стандартные услуги + возможность добавления дополнительных опций.',
      price: 40000,
      frequency: 4,
      isActive: true,
      sortOrder: 2,
      type: 'package',
      features: ['Все стандартные услуги', 'Дополнительные опции', 'Приоритетное назначение'],
      popular: true,
    },
    {
      id: '8x_month',
      key: '8x_month',
      name: '8 раз',
      title: '8 раз',
      shortInfo: 'Уборка 2 раза в неделю — максимальная чистота',
      fullInfo: 'Пакет включает 8 уборок в месяц (2 раза в неделю). Идеально для больших семей или тех, кто ценит идеальную чистоту. Включает все стандартные услуги и приоритетное назначение проверенных уборщиц.',
      price: 72000,
      frequency: 8,
      isActive: true,
      sortOrder: 3,
      type: 'package',
      features: ['Все стандартные услуги', 'Приоритетные уборщицы', 'Максимальная чистота'],
    },
    {
      id: 'quarter',
      key: 'quarter',
      name: 'Квартал',
      title: 'Квартал',
      shortInfo: 'Подписка на 3 месяца со скидкой 5%',
      fullInfo: 'Квартальная подписка позволяет сэкономить 5% на стоимости пакета. Оплата производится сразу за 3 месяца. Включает все преимущества выбранного пакета + приоритетную поддержку и возможность заморозки до 14 дней.',
      price: 114000,
      frequency: 4,
      isQuarterly: true,
      isActive: true,
      sortOrder: 4,
      type: 'package',
      discountPercent: 5,
      features: ['Экономия 5%', 'Приоритетная поддержка', 'Заморозка до 14 дней'],
    },
    {
      id: 'post_renovation',
      key: 'post_renovation',
      name: 'После ремонта',
      title: 'После ремонта',
      shortInfo: 'Генеральная уборка после ремонтных работ',
      fullInfo: 'Специализированная уборка после ремонта. Включает: удаление строительной пыли со всех поверхностей, мытье окон и рам, очистку плитки от затирки, вынос строительного мусора. Занимает 4-6 часов.',
      price: 50000,
      frequency: 1,
      isActive: true,
      sortOrder: 5,
      type: 'package',
      features: ['Удаление строительной пыли', 'Мытье окон', 'Очистка плитки', 'Вынос мусора'],
    },
    {
      id: 'general_cleaning',
      key: 'general_cleaning',
      name: 'Ген уборка',
      title: 'Ген уборка',
      shortInfo: 'Генеральная уборка всей квартиры',
      fullInfo: 'Полная генеральная уборка квартиры сверху донизу. Включает: мытье всех полов и поверхностей, протирку пыли во всех труднодоступных местах, уборку кухни (внутри шкафов, духовки, холодильника), уборку всех санузлов, мытье окон. Занимает 3-5 часов.',
      price: 45000,
      frequency: 1,
      isActive: true,
      sortOrder: 6,
      type: 'package',
      features: ['Глубокая уборка', 'Все поверхности', 'Кухня внутри', 'Санузлы', 'Мытье окон'],
    },
  ];

  for (const pkg of packages) {
    await db.collection('info_content').doc(pkg.key).set(pkg, { merge: true });
    console.log(`  ✓ info_content/${pkg.key}`);
  }
}

async function initAddonInfo() {
  const addons = [
    {
      id: 'window_standard',
      key: 'window_standard',
      title: 'Мытье окон стандарт',
      shortInfo: 'Мытье окон стандартного размера',
      fullInfo: 'Включает мытье стекол, рам и подоконников стандартных окон (ширина до 1.5м). Используется профессиональная химия для окон. Стоимость за 1 окно.',
      price: 3000,
      isActive: true,
      sortOrder: 1,
      type: 'addon',
      group: 'windows',
    },
    {
      id: 'window_panorama',
      key: 'window_panorama',
      title: 'Панорамные окна',
      shortInfo: 'Мытье панорамных окон',
      fullInfo: 'Мытье панорамных окон шириной более 1.5м. Включает мытье стекол, рам и подоконников. Стоимость за 1 окно.',
      price: 5500,
      isActive: true,
      sortOrder: 2,
      type: 'addon',
      group: 'windows',
    },
    {
      id: 'kitchen_full_set',
      key: 'kitchen_full_set',
      title: 'Кухня полный комплект',
      shortInfo: 'Полная уборка кухни со всеми поверхностями',
      fullInfo: 'Включает: мытье всех фасадов кухни (внутри и снаружи), протирку столешницы, фартука, внешней техники. Не включает мытье духовки и холодильника внутри (заказывается отдельно).',
      price: 6500,
      isActive: true,
      sortOrder: 3,
      type: 'addon',
      group: 'kitchen',
    },
  ];

  for (const addon of addons) {
    await db.collection('info_content').doc(addon.key).set(addon, { merge: true });
    console.log(`  ✓ info_content/${addon.key}`);
  }
}

async function initReferralConfig() {
  await db.collection('referral_config').doc('main').set({
    bonusPerReferral: 2000,
    milestoneCount: 5,
    milestoneBonus: 10000,
    apartmentTiers: [
      { count: 5, discount: 3 },
      { count: 10, discount: 7 },
      { count: 20, discount: 10 },
    ],
    title: 'Бонусы за приглашение',
    subtitle: 'Приглашай друзей и получай скидки',
    description: 'Отправь реферальную ссылку другу или подруге',
    bonusDescription: '2000 ₸ на доп. услуги после покупки пакета вашим рефералом',
    milestoneDescription: 'Пригласите 5 человек',
    infoNote: 'Бонусы за приглашение начисляются после покупки вашим рефералом любого пакета. Реферальные скидки (3%, 7%, 10%) действуют на все виды услуг на постоянной основе.',
    referralLinkEnabled: true,
    referralLinkGenerationRequiresPackage: false,
    lastUpdated: admin.firestore.FieldValue.serverTimestamp(),
  }, { merge: true });
  
  console.log('✓ referral_config/main');
}

async function initAreaConfig() {
  await db.collection('area_config').doc('main').set({
    bonusAmount: 3000,
    title: 'Подтверждение площади',
    description: 'Подтвердите площадь квартиры и получите бонус на доп. услуги',
    buttonText: 'Проверить / Подтвердить',
    uploadEnabled: true,
    techPlanRequired: false,
    bonusDescription: 'Бонус 3000 ₸ на дополнительные услуги',
    lastUpdated: admin.firestore.FieldValue.serverTimestamp(),
  }, { merge: true });
  
  console.log('✓ area_config/main');
}

async function initWorkerBonusConfig() {
  await db.collection('worker_bonus_config').doc('main').set({
    bonusesVisible: true,
    title: 'Бонусы и достижения',
    description: 'Ваши бонусы зависят от качества и количества выполненной работы',
    lastUpdated: admin.firestore.FieldValue.serverTimestamp(),
  }, { merge: true });
  
  console.log('✓ worker_bonus_config/main');
}

async function initUIContent() {
  const uiContent = [
    {
      id: 'calculator_header',
      key: 'calculator_header',
      title: 'Калькулятор услуг',
      subtitle: 'Рассчитайте стоимость и выберите услуги',
      isActive: true,
      type: 'ui_text',
    },
    {
      id: 'payment_terms',
      key: 'payment_terms',
      title: 'Условия оплаты',
      fullInfo: 'После нажатия "Оплатить" откроется форма для ввода номера KASPI.KZ. Менеджер выставит счет в ближайшее время, а пакет активируется после подтверждения оплаты.',
      isActive: true,
      type: 'ui_text',
    },
  ];

  for (const content of uiContent) {
    await db.collection('ui_content').doc(content.id).set(content, { merge: true });
    console.log(`  ✓ ui_content/${content.id}`);
  }
}

main().catch((err) => {
  console.error('❌ Error:', err);
  process.exit(1);
});
