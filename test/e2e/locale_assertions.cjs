// Browser regression assertions: supply text captured from the rendered Flutter
// semantics tree, not source files or API payloads. Used by the isolated audit.
const assert = require('node:assert/strict');
const checks = {
  '/client/profile': [['Наш любимый Новичок', 'Біздің сүйікті Жаңадан келген адам'], ['Скидка пока не активирована', 'Жеңілдік әлі іске қосылмаған']],
  '/client/calculator': [['Итого за месяц', 'Айдағы жалпы']],
  '/cleaner/bonus': [['Ваши бонусы зависят от качества и количества выполненной работы', 'Сіздің бонустарыңыз орындалған жұмыстың сапасы мен санына байланысты']],
  '/payment-terms': [['После успешной оплаты пользователь возвращается в раздел заказов приложения.', null]],
};
module.exports = function assertLocalizedPage(route, text, locale) {
  if (locale !== 'kk' || !checks[route]) return;
  assert.ok(text.trim().length > 30, 'The page must be rendered before checking translations');
  for (const [source, expected] of checks[route]) {
    assert.ok(!text.includes(source), `Untranslated visible text on ${route}: ${source}`);
    if (expected) assert.ok(text.includes(expected), `Expected Kazakh text on ${route}: ${expected}`);
  }
};
