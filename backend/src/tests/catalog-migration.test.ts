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
    assert.equal(quote.cleaningCount,6);assert.equal(quote.monthlyPrice,48600);
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
