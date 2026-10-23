import {createHash} from 'crypto';
import {RequestHandler} from 'express';
import {Database} from '../infrastructure/db/Database';
import {ApiError} from './api';

/** Persist the result before replying; concurrent retries do not repeat a purchase. */
export function idempotent(db: Database, scope: string): RequestHandler {
  return (req,res,next) => { void (async()=>{
    const raw=req.header('Idempotency-Key') ?? req.body?.idempotencyKey;
    if(raw===undefined) {next();return;}
    if(typeof raw!=='string'||!raw.trim()||raw.length>128)throw new ApiError(400,'invalid_idempotency_key','Некорректный ключ повторного запроса.');
    const key=raw.trim(), user=req.user!.id;
    const fingerprint=createHash('sha256').update(JSON.stringify(req.body)).digest('hex');
    const claimed=(await db.query(`INSERT INTO api_idempotency(user_id,scope,key,fingerprint) VALUES($1,$2,$3,$4) ON CONFLICT DO NOTHING RETURNING key`,[user,scope,key,fingerprint])).rows.length>0;
    if(!claimed){
      for(let attempt=0;attempt<100;attempt++){
        const saved=(await db.query('SELECT fingerprint,response,status_code FROM api_idempotency WHERE user_id=$1 AND scope=$2 AND key=$3',[user,scope,key])).rows[0];
        if(saved?.fingerprint!==fingerprint)throw new ApiError(409,'idempotency_conflict','Этот запрос уже использован для другой операции.');
        if(saved?.response!==null && saved?.response!==undefined){res.status(saved.status_code).json(saved.response);return;}
        await new Promise(resolve=>setTimeout(resolve,100));
      }
      throw new ApiError(409,'operation_pending','Запрос уже обрабатывается. Обновите статус оплаты.');
    }
    const json=res.json.bind(res);
    res.json=((body:unknown)=>{const status=res.statusCode;void db.query(`UPDATE api_idempotency SET response=$4::jsonb,status_code=$5,completed_at=NOW() WHERE user_id=$1 AND scope=$2 AND key=$3`,[user,scope,key,JSON.stringify(body),status])
      .then(()=>json(body)).catch(()=>{res.json=json;next(new ApiError(503,'operation_pending','Проверяем результат операции. Обновите статус оплаты.'));});return res;}) as typeof res.json;
    next();
  })().catch(next);};
}
