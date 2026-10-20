import {Router} from 'express';
import {randomUUID} from 'node:crypto';
import {Database} from '../infrastructure/db/Database';
import {auth} from '../common/auth';
import {ApiError,asyncHandler,ok} from '../common/api';
import {eventSignature} from './collector';
import {safeText,problem} from './core';
export function telemetryRouter(db:Database){
 const router=Router();
 router.post('/telemetry/client-events',auth(),asyncHandler(async(req,res)=>{
  const events=req.body.events;
  if(!Array.isArray(events)||events.length>20)throw new ApiError(400,'invalid_events','Допускается до 20 событий.');
  const recent=(await db.query("SELECT COUNT(*)::int AS n FROM tech_events WHERE source='client' AND user_id=$1 AND started_at>NOW()-INTERVAL '1 minute'",[req.user!.id])).rows[0].n;
  if(recent>=120)throw new ApiError(429,'telemetry_limited','Превышен лимит событий устройства.');
  const account=(await db.query('SELECT full_name FROM app_users WHERE id=$1',[req.user!.id])).rows[0];
  for(const event of events){
   if(!['screen.open','ui.action.started','ui.action.completed','ui.action.failed','client.error','location.report'].includes(event.action))continue;
   const validId=(v:any)=>typeof v==='string'&&/^[a-zA-Z0-9_-]{8,80}$/.test(v)?v:null;
   let gps=null;
   if(event.action==='location.report'&&event.gps?.consent===true){const g=event.gps,t=Date.parse(g.timestamp);if(Number.isFinite(g.latitude)&&Math.abs(g.latitude)<=90&&Number.isFinite(g.longitude)&&Math.abs(g.longitude)<=180&&Number.isFinite(g.accuracy)&&g.accuracy>=0&&g.accuracy<=100000&&Number.isFinite(t)&&Math.abs(Date.now()-t)<86400000)gps={latitude:g.latitude,longitude:g.longitude,accuracy:g.accuracy,timestamp:new Date(t).toISOString(),source:'Сообщено устройством после разрешения',consent:true};}
   const fields={screen:safeText(event.screen,100),label:safeText(event.label,100),deviceTime:safeText(event.time,50),evidence:'Сообщено клиентом; не подтверждает выполнение серверной операции.'};
   const row=(await db.query(`INSERT INTO tech_events(id,request_id,user_id,user_name,user_role,client_session_id,operation_id,source,action,result,finished_at,platform,app_version,device,ip,gps,fields)
    VALUES($1,$2,$3,$4,$5,$6,$7,'client',$8,'reported',NOW(),$9,$10,$11,$12,$13,$14) RETURNING *`,[randomUUID(),req.techRequestId??randomUUID(),req.user!.id,account?.full_name??null,req.user!.role,validId(event.session),validId(event.operation),event.action,safeText(req.header('x-domly-platform'),50)||null,safeText(req.header('x-domly-version'),100)||null,safeText(req.header('user-agent'),160),req.ip??null,gps,fields])).rows[0];
   await db.query('UPDATE tech_events SET signature=$2 WHERE id=$1',[row.id,eventSignature(row)]);
   if(event.action==='client.error'){const known=['TypeError','StateError','FlutterError','RangeError','FormatException','NoSuchMethodError','AssertionError','UnsupportedError'];const code=known.includes(event.label)?event.label:'ClientError';await problem(db,{fingerprint:'client-error:'+code,code:'client_'+code,kind:'error',title:'Ошибка приложения, сообщённая устройством: '+code,eventId:row.id,recommendation:'Откройте экран и хронологию пользователя. Класс исключения сообщён устройством; исходный текст, ввод пользователя и секреты не собираются. Сопоставьте с серверными запросами и версией приложения.'});}
  }ok(res,{accepted:true});
 }));return router;
}
