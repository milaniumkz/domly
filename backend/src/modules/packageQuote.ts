import { referralDiscount } from './referrals';
import { ApiError } from '../common/api';
import { first } from '../common/sql';
import { Queryable } from '../domain/repositories/UnitOfWork';

export async function packageQuote(db: Queryable, input: Record<string, any>) {
  const pkg = first<any>((await db.query('SELECT * FROM catalog_packages WHERE id=$1 AND active=TRUE', [input.packageId])).rows);
  if (!pkg) throw new ApiError(404, 'package_not_found', 'Пакет не найден.');
  if (Number(pkg.cleaning_count) <= 0 || Number(pkg.months) <= 0) throw new ApiError(400,'invalid_package','Проверьте настройки пакета.');
  const area = Number(input.area);
  if (!Number.isFinite(area) || area <= 0 || area > 10000) throw new ApiError(400, 'area_required', 'Укажите площадь квартиры.');
  const cleaningCount = Number(pkg.cleaning_count) * Number(pkg.months);
  const base = Math.round((Number(pkg.base_price) + Number(pkg.price_per_m2) * area) * cleaningCount);
  const selected = Array.isArray(input.addonsDetailed) ? input.addonsDetailed : [];
  if (selected.length > 100) throw new ApiError(400, 'invalid_addons', 'Слишком много дополнительных услуг.');
  const addons = [];
  const ids = new Set<string>();
  for (const item of selected) {
    const id = String(item.id ?? item.key ?? '');
    if (ids.has(id)) throw new ApiError(400, 'invalid_addons', 'Услуга указана дважды.');
    ids.add(id);
    const quantity = Number(item.quantity ?? 1);
    if (!Number.isInteger(quantity) || quantity < 1 || quantity > 100) throw new ApiError(400, 'invalid_addons', 'Проверьте количество услуг.');
    const addon = first<any>((await db.query('SELECT * FROM catalog_addons WHERE id=$1 AND active=TRUE', [id])).rows);
    if (!addon) throw new ApiError(400, 'invalid_addons', 'Дополнительная услуга недоступна.');
    const unit = Number(addon.price) * (['per_m2','per_sqm'].includes(addon.pricing_type) ? area : 1);
    const total = Math.round(unit * quantity * (addon.pricing_type === 'per_visit' ? cleaningCount : 1));
    addons.push({id, durationMinutes: Number(addon.duration_minutes ?? 0) * quantity, pricingType: addon.pricing_type, title: addon.title_ru, quantity, price: unit, total, separate: addon.paid_separately});
  }
  const addonTotal = addons.reduce((sum, item) => sum + item.total, 0);
  const discountRate = Math.max(0, Math.min(100, Number(pkg.features?.discountPercent ?? 0))) / 100;
  const discountAmount = Math.round(base * discountRate);
  const referralPercent = input.customerId ? await referralDiscount(db, input.customerId) : 0;
  const referralAmount = Math.round((base + addonTotal - discountAmount) * referralPercent / 100);
  return {referralDiscountPercent: referralPercent, referralDiscountAmount: referralAmount, packageId: pkg.id, perCleaningPrice: Math.round(base / cleaningCount), cleaningCount,
    billingPeriodMonths: Number(pkg.months), subtotal: base + addonTotal, monthlyPrice: base + addonTotal - discountAmount - referralAmount,
    discountRate, discountAmount, addonTotalPrice: addonTotal, addonsBillableTotal: addonTotal,
    addonsSeparatePaymentTotal: 0, separatePaymentAddons: [], addons};
}
