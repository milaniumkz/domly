// Explicitly authorized 2026-10-27: quarterly rate 95 KZT/m²/visit.
// Existing purchases, invoices and other catalogue records are not changed.
async function setQuarterlyRate(db, id, operationId) {
  return db.transaction(async tx => {
    const previous=(await tx.query('SELECT * FROM catalog_packages WHERE id=$1 FOR UPDATE',[id])).rows[0];
    if (!previous || previous.features?.isQuarterly!==true || Number(previous.months)!==3)
      throw Error('Expected quarterly package missing');
    if (Number(previous.price_per_m2)===95) return {alreadyApplied:true,id};
    if (Number(previous.price_per_m2)!==180) throw Error('Tariff changed since review');
    const current=(await tx.query('UPDATE catalog_packages SET price_per_m2=95,updated_at=NOW() WHERE id=$1 RETURNING *',[id])).rows[0];
    await tx.query("INSERT INTO audit_logs(action,entity_type,entity_id,payload) VALUES('catalog.quarterly.rate.authorized','catalog_package',$1,$2::jsonb)",
      [id,JSON.stringify({previous,current,operationId,reason:'Owner approved 95 KZT/m²/visit on 2026-10-27'})]);
    return {applied:true,previous,current,operationId};
  });
}
module.exports={setQuarterlyRate};
if (!module.parent) {
  const {Database}=require('./dist/infrastructure/db/Database');
  const db=new Database(process.env.DATABASE_URL);
  setQuarterlyRate(db,'84d2ee9d-0693-598d-a1ea-e36d74ce847e',process.env.RATE_OPERATION_ID)
    .then(result=>console.log(JSON.stringify(result)))
    .catch(e=>{console.error(e.message);process.exitCode=1;})
    .finally(()=>db.close());
}
