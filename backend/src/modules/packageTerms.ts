import {createHash} from 'node:crypto';
import {ApiError} from '../common/api';

export function packageConsentVersion(pkg: any): string | null {
  if (pkg.features?.requiresConsent !== true) return null;
  return createHash('sha256').update(JSON.stringify([
    pkg.name_ru,
    String(pkg.features.importantInfo ?? '').trim(),
    Array.isArray(pkg.features.items) ? pkg.features.items : [],
  ])).digest('hex');
}

export function isPostRenovation(pkg: any): boolean {
  return pkg?.features?.systemKey === 'post_renovation';
}

export function packageAllowsAddons(pkg: any): boolean {
  return pkg.features?.systemKey !== 'post_renovation' && pkg.features?.allowAddons !== false;
}

export function publicCatalogPackage(pkg: any) {
  return {...pkg, features: {...pkg.features, allowAddons: packageAllowsAddons(pkg), ...(isPostRenovation(pkg) ? {minutesPerM2:25, minimumBookingLeadHours:24} : {})}, consentVersion: packageConsentVersion(pkg)};
}

export function acceptPackageTerms(pkg: any, version: unknown) {
  const expected = packageConsentVersion(pkg);
  if (!expected) return null;
  if (!String(pkg.features.importantInfo ?? '').trim()) {
    throw new ApiError(409, 'package_terms_unavailable', 'Условия тарифа ещё не заполнены. Обратитесь в поддержку.');
  }
  if (version !== expected) {
    throw new ApiError(409, 'package_terms_required', 'Прочитайте актуальную важную информацию и подтвердите согласие.');
  }
  return {version: expected, acceptedAt: new Date().toISOString(),
    title: pkg.name_ru, importantInfo: pkg.features.importantInfo,
    items: pkg.features.items ?? []};
}

export function validatePackageBody(body: any, current?: any) {
  const value = (key: string, column: string, fallback: unknown) => body[key] ?? current?.[column] ?? fallback;
  for (const [key, column] of [['basePrice', 'base_price'], ['pricePerM2', 'price_per_m2']]) {
    const price = Number(value(key, column, 0));
    if (!Number.isFinite(price) || price < 0 || price > 100000000) {
      throw new ApiError(400, 'invalid_package', 'Укажите корректную цену тарифа.');
    }
  }
  const incoming = body.features ?? current?.features ?? {};
  const features = current?.features && !Array.isArray(current.features) && incoming && !Array.isArray(incoming)
    ? {...current.features, ...incoming} : incoming;
  if (!features || typeof features !== 'object') throw new ApiError(400, 'invalid_package', 'Проверьте настройки тарифа.');
  const count = Number(value('cleaningCount', 'cleaning_count', 1));
  const months = Number(value('months', 'months', 1));
  if (![count, months].every(n => Number.isInteger(n) && n > 0 && n <= 120)) {
    throw new ApiError(400, 'invalid_package', 'Укажите количество уборок и период тарифа.');
  }
  if (features.isSpecial === true && (count !== 1 || months !== 1 || features.isQuarterly === true)) {
    throw new ApiError(400, 'invalid_package', 'Специальный тариф оформляется на одну уборку.');
  }
  if (features.requiresConsent === true && !String(features.importantInfo ?? '').trim()) {
    throw new ApiError(400, 'invalid_package', 'Заполните важную информацию для клиента.');
  }
  if (String(features.importantInfo ?? '').length > 20000) throw new ApiError(400, 'invalid_package', 'Описание слишком длинное.');
  if (!String(value('nameRu', 'name_ru', '')).trim()) throw new ApiError(400, 'invalid_package', 'Укажите название тарифа.');
}
