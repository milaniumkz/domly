export function first<T>(rows: T[]): T | null {
  return rows.length > 0 ? rows[0] : null;
}

export function pageParams(query: { limit?: unknown; offset?: unknown }) {
  const limit = Math.min(Math.max(Number(query.limit ?? 50), 1), 200);
  const offset = Math.max(Number(query.offset ?? 0), 0);
  return { limit, offset };
}

export function localize(row: Record<string, unknown>, base: string, lang = 'ru'): string {
  const value = row[`${base}_${lang}`] ?? row[`${base}_ru`] ?? row[base];
  return typeof value === 'string' ? value : '';
}
