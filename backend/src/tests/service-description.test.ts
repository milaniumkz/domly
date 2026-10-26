import test from 'node:test';
import assert from 'node:assert/strict';
import { formatAddonRecord, formatServiceDescription } from '../modules/serviceDescription';

test('legacy oven paragraphs and included items render without a new client', () => {
  const source = 'Удаление жира.  В стоимость входит:  Очистка стенок.  Очистка дверцы.  Размер техники: духовка до 70 литров.';
  assert.equal(formatServiceDescription(source), 'Удаление жира.\n\nВ стоимость входит:\n• Очистка стенок.\n• Очистка дверцы.\n\nРазмер техники: духовка до 70 литров.');
  const result = formatServiceDescription(source);
  assert.equal(formatServiceDescription(result), result);
});

test('preserves explicit paragraphs, ordinary text, amounts and missing values', () => {
  for (const value of [null, undefined, '', 'Цена: 2  500.00 ₸', 'Текст. Обычный текст.', 'Входит:\n\n• Пункт 1.\n• Пункт 2.', 'Слово  слово  слово', 'Абзац.\r\nВторой абзац.']) {
    assert.equal(formatServiceDescription(value), value);
  }
});

test('formats both languages without changing source records or business fields', () => {
  const row = { id:'oven', price:'2500.00', duration_minutes:25, description_ru:'Описание.  Что входит:  Первый пункт.  Второй пункт.', description_kk:'Сипаттама.  Құнына кіреді:  Бірінші.  Екінші.' };
  const result = formatAddonRecord(row);
  assert.equal(result.price,row.price);
  assert.equal(result.duration_minutes,row.duration_minutes);
  assert.ok(result.description_ru.includes('\n• Первый'));
  assert.ok(result.description_kk.includes('\n• Бірінші'));
  assert.ok(!row.description_ru.includes('\n'));
});
