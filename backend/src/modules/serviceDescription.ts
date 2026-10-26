/** Repair paragraph separators flattened by older single-line admin inputs.
 * Existing multiline content is authoritative and is never reformatted.
 * Only punctuation followed by multiple horizontal spaces is a boundary;
 * ordinary wrapping, decimal values, prices and single-space prose stay intact.
 */
export function formatServiceDescription<T>(value: T): T | string {
  if (typeof value !== 'string' || /[\r\n]/.test(value)) return value;
  const parts = value.split(/(?<=[.!?:])[ \t\u00a0]{2,}(?=\S)/);
  if (parts.length < 3) return value;
  let inList = false;
  return parts.map((part, index) => {
    const heading = /^(?:В стоимость входит|Что входит|В стоимость не входит|Что не входит|Условия оказания услуги|Стоимость услуги|Размер техники|Маңызды|Қызмет көрсету шарттары|Құнына кіреді|Құнына кірмейді)\s*:/i.test(part);
    if (heading) {
      inList = /^(?:В стоимость входит|Что входит|В стоимость не входит|Что не входит|Условия оказания услуги|Қызмет көрсету шарттары|Құнына кіреді|Құнына кірмейді)\s*:\s*$/i.test(part);
      return (index ? '\n\n' : '') + part;
    }
    return (index ? (inList ? '\n' : '\n\n') : '') + (inList && !/^[•●\-–]\s/.test(part) ? '• ' : '') + part;
  }).join('');
}

export function formatAddonRecord<T extends Record<string, any>>(row: T): T {
  const result = { ...row };
  for (const key of ['description_ru', 'description_kk', 'hint_ru', 'hint_kk'] as const) {
    if (key in row) (result as Record<string, any>)[key] = formatServiceDescription(row[key]);
  }
  return result;
}
