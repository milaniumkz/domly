// Owner authorized 850 KZT/m² on 2026-11-09. Only the current catalogue tariff.
async function setPostRenovationRate(db,id,operationId) {
 return db.transaction(async tx=>{
  const previous=(await tx.query('SELECT * FROM catalog_packages WHERE id=$1 FOR UPDATE',[id])).rows[0];
  if(!previous || previous.features?.systemKey!=='post_renovation' || previous.cleaning_count!==1 || previous.months!==1)
   throw Error('Expected post-renovation tariff missing');
  if(Number(previous.price_per_m2)===850 && Number(previous.base_price)===0 && previous.features.pricingType==='per_m2')
   return {alreadyApplied:true,id};
  if(![95,850].includes(Number(previous.price_per_m2)) || Number(previous.base_price)!==0)
   throw Error('Catalogue price changed since review');
  const current=(await tx.query(`UPDATE catalog_packages SET price_per_m2=850,base_price=0,
    features=features||'{"pricingType":"per_m2"}'::jsonb,updated_at=NOW() WHERE id=$1 RETURNING *`,[id])).rows[0];
  await tx.query("INSERT INTO audit_logs(action,entity_type,entity_id,payload) VALUES('catalog.post_renovation.rate.authorized','catalog_package',$1,$2::jsonb)",
    [id,JSON.stringify({previous,current,operationId,reason:'Owner instructed 850 KZT/m² on 2026-11-09'})]);
  return {applied:true,previous,current,operationId};
 });
}
module.exports={setPostRenovationRate};
if(!module.parent){
 const {Database}=require('./dist/infrastructure/db/Database');
 const db=new Database(process.env.DATABASE_URL);
 setPostRenovationRate(db,'c72a5389-c683-4037-9a39-2688de30f41f',process.env.RATE_OPERATION_ID)
  .then(result=>console.log(JSON.stringify(result)))
  .catch(()=>{console.error('Post-renovation tariff update failed');process.exitCode=1;})
  .finally(()=>db.close());
}
