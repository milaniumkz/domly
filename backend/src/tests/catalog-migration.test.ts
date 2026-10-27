import test from 'node:test';
import assert from 'node:assert/strict';
import { randomUUID } from 'node:crypto';
import { Database } from '../infrastructure/db/Database';
import { importCatalog, CatalogExport } from '../modules/catalogMigration';
import { packageQuote } from '../modules/packageQuote';

test('catalogue migration preserves per-square-metre rates and admin edits', {skip:!process.env.DOMLY_INTEGRATION_DATABASE_URL},async()=>{
  const db=new Database(process.env.DOMLY_INTEGRATION_DATABASE_URL!);
  const prefix='migration-test-'+randomUUID();
  const source:CatalogExport={
    customer_packages:[
      {id:prefix+'monthly',data:{name:prefix+'monthly',price:180,cleaningsPerMonth:2,billingPeriodMonths:1,features:['Уборка']}},
      {id:prefix+'quarter',data:{name:prefix+'quarter',price:95,isQuarterly:true,billingPeriodMonths:3,discountPercent:10}},
    ],
    addon_groups_config:[{id:prefix,data:{label:prefix,items:[{key:prefix,label:prefix,price:1500,durationMinutes:20}]}}],
    houses:[{id:prefix,data:{city:prefix,address:'Тестовая, 14, '+prefix,status:'INACTIVE'}}],
  };
  // Use a parseable Astana address but fixture city for isolation.
  source.houses[0].data.address='Тестовая, 14';
  try {
    await assert.rejects(importCatalog(db,{...source,service_zones:[{id:prefix,data:{title:prefix}}]}));
    assert.equal((await db.query('SELECT id FROM catalog_packages WHERE name_ru LIKE $1',[prefix+'%'])).rows.length,0,'all inserts roll back on failure');
    const counts=await importCatalog(db,source);
    assert.equal(counts.packages,2);assert.equal(counts.addons,1);
    const rows=(await db.query('SELECT * FROM catalog_packages WHERE name_ru LIKE $1',[prefix+'%'])).rows;
    const monthly=rows.find(r=>r.months===1),quarter=rows.find(r=>r.months===3);
    assert.equal(Number(monthly.base_price),0);assert.equal(Number(monthly.price_per_m2),180);
    assert.equal((await packageQuote(db,{packageId:monthly.id,area:50})).monthlyPrice,18000);
    const quote=await packageQuote(db,{packageId:quarter.id,area:50,cleaningsPerMonth:2});
    assert.equal(Number(quarter.price_per_m2),95);
    assert.equal(quote.cleaningCount,6);assert.equal(quote.monthlyPrice,25650);
    await assert.rejects(packageQuote(db,{packageId:quarter.id,area:50,cleaningsPerMonth:3}));
    await db.query('UPDATE catalog_packages SET price_per_m2=190 WHERE id=$1',[monthly.id]);
    await importCatalog(db,source);
    assert.equal((await db.query('SELECT id FROM catalog_packages WHERE name_ru LIKE $1',[prefix+'%'])).rows.length,2);
    assert.equal((await packageQuote(db,{packageId:monthly.id,area:50})).monthlyPrice,19000,'repeat migration retains admin price edits');
  } finally {
    await db.query('DELETE FROM catalog_addons WHERE title_ru=$1',[prefix]);
    await db.query('DELETE FROM addon_groups WHERE title_ru=$1',[prefix]);
    await db.query('DELETE FROM connected_houses WHERE city=$1',[prefix]);
    await db.query('DELETE FROM catalog_packages WHERE name_ru LIKE $1',[prefix+'%']);
    await db.query('DELETE FROM service_zones WHERE name_ru=$1',[prefix]);
    await db.close();
  }
});

test('quarterly quote uses its own editable tariff for every frequency', async () => {
  const pkg = {id: randomUUID(), cleaning_count:2, months:3, base_price:0,
    price_per_m2:95, features:{isQuarterly:true,discountPercent:10,
      monthlyRates:{2:180,4:120,8:95}}};
  const db = {query: async (sql:string) => {
    if (sql.includes('WHERE id=$1')) return {rows:[pkg]};
    throw new Error('Quarterly price must not be replaced by a monthly tariff');
  }} as any;
  for (const [visits,total] of [[2,51300],[4,102600],[8,205200]]) {
    const quote=await packageQuote(db,{packageId:pkg.id,area:100,cleaningsPerMonth:visits});
    assert.equal(quote.monthlyPrice,total);
    assert.equal(quote.pricingSnapshot.pricePerM2,95);
    assert.equal(quote.cleaningCount,visits*3);
  }
  await assert.rejects(packageQuote(db,{packageId:pkg.id,area:100,cleaningsPerMonth:3}));
  pkg.price_per_m2=100;
  assert.equal((await packageQuote(db,{packageId:pkg.id,area:100,cleaningsPerMonth:4})).monthlyPrice,108000,
    'later admin changes must remain effective');
});

test('authorized quarterly rate update preserves other fields and is idempotent', {skip:!process.env.DOMLY_INTEGRATION_DATABASE_URL},async()=>{
  const db=new Database(process.env.DOMLY_INTEGRATION_DATABASE_URL!);
  const id=randomUUID();
  const {setQuarterlyRate}=require('../../../scripts/server/set_quarterly_rate.cjs');
  try {
    await db.query(`INSERT INTO catalog_packages(id,name_ru,cleaning_count,months,base_price,price_per_m2,features)
      VALUES($1,$2,2,3,0,180,'{"isQuarterly":true,"discountPercent":10}')`,[id,'quarter-rate-test-'+id]);
    const before=(await db.query('SELECT * FROM catalog_packages WHERE id=$1',[id])).rows[0];
    const applied=await setQuarterlyRate(db,id,'isolated-regression');
    assert.equal(applied.applied,true);
    const after=(await db.query('SELECT * FROM catalog_packages WHERE id=$1',[id])).rows[0];
    assert.equal(Number(after.price_per_m2),95);
    for(const key of Object.keys(before).filter(k=>!['price_per_m2','updated_at'].includes(k)))assert.deepEqual(after[key],before[key]);
    assert.equal((await setQuarterlyRate(db,id,'repeat')).alreadyApplied,true);
    const logs=(await db.query("SELECT payload FROM audit_logs WHERE entity_id=$1 AND action='catalog.quarterly.rate.authorized'",[id])).rows;
    assert.equal(logs.length,1);assert.equal(Number(logs[0].payload.previous.price_per_m2),180);
    await db.query('UPDATE catalog_packages SET price_per_m2=100 WHERE id=$1',[id]);
    await assert.rejects(setQuarterlyRate(db,id,'stale'));
    assert.equal(Number((await db.query('SELECT price_per_m2 FROM catalog_packages WHERE id=$1',[id])).rows[0].price_per_m2),100);
  }finally{
    await db.query("DELETE FROM audit_logs WHERE entity_id=$1 AND action='catalog.quarterly.rate.authorized'",[id]);
    await db.query('DELETE FROM catalog_packages WHERE id=$1',[id]);await db.close();
  }
});
