// offerPayload is prepended from the reviewed JSON by the operator workflow.
const {Pool}=require('pg');const crypto=require('crypto');
const hash=text=>crypto.createHash('sha256').update(text).digest('hex');
(async()=>{
 if(offerPayload.slug!=='public-offer'||hash(offerPayload.bodyRu)!==offerPayload.bodySha256)throw Error('Invalid reviewed document');
 const pool=new Pool({connectionString:process.env.DATABASE_URL,max:1});const client=await pool.connect();
 try {
  await client.query('BEGIN');
  const old=(await client.query("SELECT * FROM content_pages WHERE slug='public-offer' FOR UPDATE")).rows[0];
  if(!old)throw Error('Original offer missing');
  if(hash(old.body_ru)===offerPayload.bodySha256){await client.query('ROLLBACK');console.log(JSON.stringify({alreadyPublished:true,sha256:offerPayload.bodySha256}));return;}
  if(hash(old.body_ru)!==offerPayload.expectedPreviousSha256)throw Error('Offer changed since comparison');
  const updated=(await client.query("UPDATE content_pages SET title_ru=$1,body_ru=$2,body_kk=NULL,active=TRUE,updated_at=NOW() WHERE id=$3 RETURNING id,slug,updated_at",[offerPayload.titleRu,offerPayload.bodyRu,old.id])).rows[0];
  await client.query("INSERT INTO audit_logs(action,entity_type,entity_id,payload) VALUES('content.offer.published','content_page',$1,$2::jsonb)",[old.id,JSON.stringify({source:'Публичная_оферта_DOMLY.docx',previous:old,sha256:offerPayload.bodySha256,operationId:process.env.OFFER_OPERATION_ID})]);
  await client.query('COMMIT');console.log(JSON.stringify({published:true,...updated,sha256:offerPayload.bodySha256,characters:offerPayload.bodyRu.length,previous:old}));
 }catch(e){await client.query('ROLLBACK');throw e;}finally{client.release();await pool.end();}
})().catch(e=>{console.error(e.message);process.exitCode=1;});
