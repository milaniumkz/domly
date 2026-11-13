import {createHash,timingSafeEqual,randomUUID} from 'node:crypto';
import {ApiError} from '../common/api';
import {env} from '../common/env';
import {Database} from '../infrastructure/db/Database';

export function verifyOrderingToken(headers:Record<string,unknown>) {
  const secret=env.moonAiOrderingToken;
  if(secret.length<32)throw new ApiError(503,'integration_not_configured','API оформления ботом не настроен.');
  const supplied=headers['x-moonai-ordering-token'];
  if(typeof supplied!=='string'||Buffer.byteLength(supplied)!==Buffer.byteLength(secret)||!timingSafeEqual(Buffer.from(supplied),Buffer.from(secret)))
    throw new ApiError(401,'unauthorized','Неверный токен интеграции.');
}
export async function auditBot(db:Database,operation:string,input:{customerId?:string;requestId:string;entityType?:string;entityId?:string;result:string;code?:string;replay?:boolean}) {
  await db.query(`INSERT INTO audit_logs(actor_id,action,entity_type,entity_id,payload) VALUES(NULL,$1,$2,$3,$4)`,
    ['bot.moon-ai.'+operation,input.entityType??'bot_action',input.entityId??input.customerId??input.requestId,
      {actorKind:'bot',actorName:'MooonAI',...input}]);
}
/** The response and all database changes commit together. Never accept payment status from the caller. */
export async function orderingOperation(db:Database,operation:string,body:any,key:unknown,work:()=>Promise<any>,customerId?:string) {
  const requestId=typeof key==='string'?key:randomUUID();
  if(typeof key!=='string'||!/^[A-Za-z0-9_.:-]{8,128}$/.test(key)){
    await auditBot(db,operation,{customerId,requestId,result:'error',code:'idempotency_key_required'});
    throw new ApiError(400,'idempotency_key_required','Передайте стабильный Idempotency-Key (8–128 символов).');
  }
  const fingerprint=createHash('sha256').update(JSON.stringify(body)).digest('hex');
  try {
    return await db.atomic(async()=>{
      await db.query('SELECT pg_advisory_xact_lock(hashtextextended($1,0))',['bot:'+key]);
      const previous=(await db.query('SELECT * FROM bot_ordering_requests WHERE request_key=$1',[key])).rows[0];
      if(previous){
        if(previous.operation!==operation||previous.fingerprint!==fingerprint)throw new ApiError(409,'idempotency_conflict','Ключ уже использован для другой операции.');
        await auditBot(db,operation,{customerId,requestId,result:'success',replay:true});
        return previous.response;
      }
      const result=await work();
      const entityType=result.order?'order':result.payment?'payment':result.customerPackage?'customer_package':'bot_action';
      const entityId=result.order?.id??result.payment?.id??result.customerPackage?.id;
      await auditBot(db,operation,{customerId,requestId,entityType,entityId,result:'success'});
      if(operation==='package_purchase'&&result.payment?.id)await db.query("UPDATE payments SET payload=payload || $2::jsonb WHERE id=$1",[result.payment.id,{createdBy:'bot',bot:'MooonAI',botRequestId:key}]);
      if(operation==='package_purchase'&&result.customerPackage?.id)await db.query("UPDATE customer_packages SET purchase_config=purchase_config || $2::jsonb WHERE id=$1",[result.customerPackage.id,{createdBy:'bot',bot:'MooonAI',botRequestId:key}]);
      await db.query('INSERT INTO bot_ordering_requests(request_key,operation,fingerprint,customer_id,response) VALUES($1,$2,$3,$4,$5)',[key,operation,fingerprint,customerId??null,result]);
      return result;
    });
  }catch(error){
    await auditBot(db,operation,{customerId,requestId,result:'error',code:error instanceof ApiError?error.code:'internal_error'});
    throw error;
  }
}
