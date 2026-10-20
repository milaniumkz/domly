import {Worker} from 'bullmq';
import {randomUUID} from 'node:crypto';
import {Database} from '../infrastructure/db/Database';
import {collectorFailure,problem,safeText} from './core';
import {eventSignature} from './collector';
export function observeWorker(db:Database,worker:Worker){
 const active=new Map<string,Promise<string>>();
 worker.on('active',job=>{
  if(worker.name==='moon-ai')return; // The empty 2-second outbox poll is represented by its heartbeat.
  const eventId=randomUUID(),key=String(job.id);
  const objectId=String(job.data?.orderId??job.data?.paymentId??'');
  const value=db.query(`INSERT INTO tech_events(id,request_id,source,action,entity_type,entity_id,fields,app_version)
   VALUES($1,$2,'worker',$3,$4,$5,$6,$7)`,[eventId,randomUUID(),'job.'+safeText(worker.name,60)+'.'+safeText(job.name,80),job.data?.orderId?'orders':job.data?.paymentId?'payments':'job',objectId||key,{actor:'Система, фоновая задача',queue:worker.name,jobId:key},process.env.APP_RELEASE??null]).then(()=>eventId);
  active.set(key,value);void value.catch(collectorFailure);
 });
 async function finish(job:any,failed:boolean,error?:any){
  if(!job)return;const key=String(job.id),started=active.get(key);active.delete(key);
  try{
   const eventId=started?await started:null;let row:any;
   if(eventId)row=(await db.query(`UPDATE tech_events SET result=$2,finished_at=NOW(),duration_ms=LEAST(2147483647,GREATEST(0,EXTRACT(EPOCH FROM (NOW()-started_at))*1000))::int,error_code=$3,failure_reason=$4 WHERE id=$1 RETURNING *`,[eventId,failed?'failure':'success',failed?'background_job_failed':null,failed?safeText(error?.name??'Error',80):null])).rows[0];
   if(row)await db.query('UPDATE tech_events SET signature=$2 WHERE id=$1',[row.id,eventSignature(row)]);
   if(failed)await problem(db,{kind:'job',severity:'critical',fingerprint:'job:'+worker.name+':'+job.name,code:'background_job_failed',title:'Ошибка фоновой задачи '+safeText(worker.name,80),eventId:row?.id,recommendation:'Проверьте очередь и события объекта. Содержимое задания и секреты не журналируются; исполнитель — система, а не пользователь.'});
  }catch{collectorFailure();}
 }
 worker.on('completed',job=>{void finish(job,false);});worker.on('failed',(job,error)=>{void finish(job,true,error);});
}
