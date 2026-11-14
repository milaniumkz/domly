import {createHash} from 'node:crypto';

type CatalogRow = Record<string, any>;
type Tariff = {base: number; rate: number};
type Candidate = {source: string; nameRu: string; nameKk: string; tariff?: Tariff; ambiguous: boolean};

const money = new Intl.NumberFormat('ru-RU', {maximumFractionDigits: 2});
const normalize = (value: unknown) => typeof value === 'string' ? value.replace(/\s+/g, ' ').trim() : '';
const text = (value: unknown) => typeof value === 'string' ? value.trim() : '';
const keyFor = (source: string) => 't_' + createHash('sha1').update(source, 'utf8').digest('hex').slice(0, 16);

function price(value: unknown): number | undefined {
  if (typeof value !== 'number' && (typeof value !== 'string' || !/^-?\d+(?:\.\d+)?$/.test(value.trim()))) return;
  const amount = Number(value);
  if (Number.isFinite(amount) && amount >= 0 && amount <= 100000000) return amount === 0 ? 0 : amount;
}

function locale(row: CatalogRow | undefined, language: 'ru' | 'kk'): string {
  return text(row?.[language]) || text(row?.locales?.[language]);
}

function suffix({base, rate}: Tariff, language: 'ru' | 'kk'): string {
  if (rate === 0) return `${money.format(base)} ₸/${language === 'ru' ? 'уборка' : 'тазалау'}`;
  if (base === 0) return `${money.format(rate)} ₸/м²`;
  return `${money.format(base)} ₸ + ${money.format(rate)} ₸/м²`;
}

/** Display base tariffs through the existing client's text catalogue, without changing package names or prices. */
export function withCatalogPriceTranslations(rows: readonly CatalogRow[], packages: readonly CatalogRow[]): CatalogRow[] {
  const byKey = new Map<string, CatalogRow>();
  const bySource = new Map<string, CatalogRow>();
  const indexes = new Map<string, number>();
  rows.forEach((row, index) => {
    if (typeof row.key === 'string') {
      byKey.set(row.key, row);
      indexes.set(row.key, index);
    }
    const source = normalize(row.source);
    if (source) bySource.set(source, row);
  });
  const existing = (source: string) => byKey.get(keyFor(source)) ?? bySource.get(source);
  const candidates = new Map<string, Candidate>();
  for (const pkg of packages) {
    if (pkg.active !== true) continue;
    const nameRu = normalize(pkg.name_ru), nameKk = normalize(pkg.name_kk);
    if (!nameRu) continue;
    const base = price(pkg.base_price), rate = price(pkg.price_per_m2);
    const tariff = base === undefined || rate === undefined ? undefined : {base, rate};
    for (const source of new Set([nameRu, nameKk].filter(Boolean))) {
      const previous = candidates.get(source);
      if (previous) {
        // A shared translation cannot truthfully represent different tariffs, including an unknown one.
        if (!tariff || !previous.tariff || tariff.base !== previous.tariff.base || tariff.rate !== previous.tariff.rate) previous.ambiguous = true;
      } else {
        candidates.set(source, {source, nameRu, nameKk, tariff, ambiguous: !tariff});
      }
    }
  }

  const result = [...rows];
  for (const {source, nameRu, nameKk, tariff, ambiguous} of candidates.values()) {
    if (ambiguous || !tariff) continue;
    const key = keyFor(source), keyedRow = byKey.get(key);
    // Do not overwrite a malformed entry that uses this key for another source.
    if (keyedRow && normalize(keyedRow.source) && normalize(keyedRow.source) !== source) continue;
    const row = existing(source), primary = existing(nameRu);
    const ru = locale(row, 'ru') || locale(primary, 'ru') || nameRu;
    const kk = locale(row, 'kk') || locale(primary, 'kk') || nameKk;
    const translated: CatalogRow = {
      ...row,
      key,
      source,
      namespace: row?.namespace ?? 'catalog',
      ru: `${ru} · ${suffix(tariff, 'ru')}`,
      ...(kk ? {kk: `${kk} · ${suffix(tariff, 'kk')}`} : {}),
    };
    const index = indexes.get(key);
    if (index === undefined) result.push(translated);
    else result[index] = translated;
  }
  return result;
}
