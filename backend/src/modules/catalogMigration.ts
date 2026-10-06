import { createHash } from 'node:crypto';
import { Database } from '../infrastructure/db/Database';

type LegacyRow = { id: string; data: Record<string, any> };
export type CatalogExport = Record<string, LegacyRow[]>;
function stableId(collection: string, id: string) {
  const hex = createHash('sha256').update(`domly-catalog:${collection}:${id}`).digest('hex');
  return `${hex.slice(0,8)}-${hex.slice(8,12)}-5${hex.slice(13,16)}-a${hex.slice(17,20)}-${hex.slice(20,32)}`;
}
function amount(value: unknown) {
  const number = Number(value);
  if (value == null || !Number.isFinite(number) || number < 0) throw Error('Invalid catalogue price');
  return number;
}
function label(data: Record<string, any>) {
  const text = String(data.name ?? data.label ?? data.title ?? '').trim();
  if (!text) throw Error('Missing catalogue title');
  return text;
}

// One-time migration only. Runtime applications never read Firestore.
// Source prices are per square metre, per visit; quarterly frequency is selected by the customer.
export async function importCatalog(db: Database, source: CatalogExport) {
  const packages = source.customer_packages;
  if (!packages?.length || !source.addon_groups_config?.length) throw Error('Incomplete catalogue export');
  const rates = Object.fromEntries(packages.filter(r => r.data.billingPeriodMonths === 1)
    .map(r => [r.data.cleaningsPerMonth, amount(r.data.price)]));
  const preparedPackages = packages.map(({id,data}) => {
    const quarterly = data.isQuarterly === true;
    const visits = quarterly ? 2 : Number(data.cleaningsPerMonth);
    const months = Number(data.billingPeriodMonths);
    if (!Number.isInteger(visits) || visits < 1 || !Number.isInteger(months) || months < 1) throw Error('Invalid package frequency');
    const features = {items:data.features ?? [],legacyId:id,isQuarterly:quarterly,
      discountPercent:amount(data.discountPercent ?? 0),sortOrder:data.sortOrder ?? 0,
      frequency:data.frequency,popular:data.popular === true,
      ...(quarterly ? {monthlyRates:rates,allowedMonthlyVisits:[2,4,8]} : {})};
    return {id:stableId('customer_packages',id),data,name:label(data),visits,months,
      rate:quarterly ? amount(rates[visits]) : amount(data.price),features};
  });
  const groups = source.addon_groups_config.map(({id,data}) => ({id:stableId('addon_groups_config',id),key:id,data,name:label(data)}));
  const addons = new Map<string,{id:string;groupId:string|null;data:Record<string,any>}>();
  // Group configuration is the current customer-facing catalogue, including embedded prices.
  for (const group of groups) for (const data of group.data.items ?? []) {
    if (!data.key) throw Error('Missing addon key');
    label(data);amount(data.price);
    addons.set(data.key,{id:stableId('addons_config',data.key),groupId:group.id,data});
  }
  // Preserve standalone services that are absent from the current groups.
  for (const row of source.addons_config ?? []) if (!addons.has(row.id)) {
    label(row.data);amount(row.data.price);
    addons.set(row.id,{id:stableId('addons_config',row.id),groupId:groups.find(g=>g.key===row.data.group)?.id ?? null,data:row.data});
  }
  const titleCounts = new Map<string,number>();
  for (const a of addons.values()) titleCounts.set(label(a.data),(titleCounts.get(label(a.data)) ?? 0)+1);
  const addonTitle = (a: {groupId:string|null;data:Record<string,any>}) => {
    const title=label(a.data);
    return (titleCounts.get(title) ?? 0)>1 ? `${groups.find(g=>g.id===a.groupId)?.name ?? 'Допуслуги'} · ${title}` : title;
  };
  const zones = (source.service_zones ?? []).map(r=>({...r,uuid:stableId('service_zones',r.id)}));
  const houses: Array<{data:Record<string,any>;street:string;number:string}> = [];
  let skippedHouses = 0;
  for (const row of source.houses ?? []) {
    const data = row.data;
    const parts = String(data.address ?? '').split(',').map(p=>p.trim()).filter(Boolean);
    if (/^(Астана|Astana|Nur-Sultan|Нур-Султан)$/i.test(parts[parts.length-1] ?? '')) parts.pop();
    const number = parts.pop() ?? '';
    const street = parts.join(', ');
    if (!street || !/^\d[\p{L}\p{N}/\- .]*$/u.test(number) || /Павлодар|Жетекши/i.test(street)) {skippedHouses++;continue;}
    houses.push({data,street,number});
  }
  return db.transaction(async tx => {
    await tx.query('SELECT pg_advisory_xact_lock(76197002)');
    for (const p of preparedPackages) await tx.query(`INSERT INTO catalog_packages
      (id,name_ru,name_kk,description_ru,cleaning_count,months,base_price,price_per_m2,active,features)
      VALUES($1,$2,$3,$4,$5,$6,0,$7,$8,$9)
      ON CONFLICT DO NOTHING`,
      [p.id,p.name,p.data.nameLocales?.kk ?? null,p.data.fullInfo || p.data.shortInfo || '',p.visits,p.months,p.rate,p.data.isActive!==false,p.features]);
    for (const g of groups) await tx.query(`INSERT INTO addon_groups(id,title_ru,title_kk,sort_order,active)
      VALUES($1,$2,$3,$4,$5) ON CONFLICT DO NOTHING`,
      [g.id,g.name,g.data.labelLocales?.kk ?? null,g.data.sortOrder ?? 0,g.data.isActive!==false]);
    const groupIds=new Map<string,string>();
    for (const g of groups) {
      const existing=(await tx.query<{id:string}>('SELECT id FROM addon_groups WHERE id=$1 OR title_ru=$2 ORDER BY (id=$1) DESC LIMIT 1',[g.id,g.name])).rows[0];
      groupIds.set(g.id,existing.id);
    }
    for (const a of addons.values()) {
      const d=a.data;
      await tx.query(`INSERT INTO catalog_addons(id,group_id,title_ru,title_kk,description_ru,hint_ru,pricing_type,price,duration_minutes,paid_separately,active,sort_order)
        VALUES($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12) ON CONFLICT DO NOTHING`,
        [a.id,a.groupId ? groupIds.get(a.groupId) : null,addonTitle(a),d.labelLocales?.kk ?? d.titleLocales?.kk ?? null,
         d.fullInfo || d.longDescription || d.description || d.shortInfo || '',d.note ?? '',
         d.pricingType ?? (d.supportsQuantity===false?'fixed_per_order':'fixed'),amount(d.price),d.durationMinutes ?? 0,d.separatePayment===true,d.isActive!==false,d.sortOrder ?? 0]);
    }
    for (const z of zones) await tx.query(`INSERT INTO service_zones(id,name_ru,name_kk,city,polygon,active)
      VALUES($1,$2,$3,$4,$5,$6) ON CONFLICT DO NOTHING`,
      [z.uuid,label(z.data),z.data.titleLocales?.kk ?? null,z.data.city,JSON.stringify(z.data.polygon ?? []),String(z.data.status).toLowerCase()==='active']);
    for (const h of houses) await tx.query(`INSERT INTO connected_houses(city,street_ru,house,residential_complex_ru,zone_id,latitude,longitude,active)
      VALUES($1,$2,$3,$4,$5,$6,$7,$8) ON CONFLICT(city,street_ru,house) DO NOTHING`,
      [h.data.city,h.street,h.number,h.data.residentialComplex ?? null,zones.find(z=>z.id===h.data.zoneId)?.uuid ?? null,h.data.lat ?? null,h.data.lng ?? null,String(h.data.status).toUpperCase()==='ACTIVE']);
    for (const pricing of source.pricing ?? []) for (const [key,value] of Object.entries(pricing.data)) {
      if (key==='addonCatalog' || key==='updatedAt') continue;
      await tx.query(`INSERT INTO app_settings(key,value) VALUES($1,$2) ON CONFLICT(key) DO NOTHING`,[key,JSON.stringify(value)]);
    }
    return {packages:preparedPackages.length,addonGroups:groups.length,addons:addons.size,zones:zones.length,houseRecords:houses.length,skippedHouses};
  });
}
