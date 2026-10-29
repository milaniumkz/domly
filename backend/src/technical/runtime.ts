import {domainRules} from './domainRules';
import os from 'node:os';
import fs from 'node:fs/promises';
import {gzipSync} from 'node:zlib';
import webpush from 'web-push';
import {Database} from '../infrastructure/db/Database';
import {StorageService} from '../modules/integrations';
import {env} from '../common/env';
import {hash,secretKey,seal,readRules,problem,collectorFailure,verifyAudit,health} from './core';
import {privateBucket,ensurePrivateBucket} from './files';

export async function readHostStatus(){
 try{const data=JSON.parse(await fs.readFile(process.env.TECH_STATUS_FILE??'/run/domly-status/status.json','utf8'));const {signature,...payload}=data;
  if(!secretKey()||seal(payload)!==signature)return {available:false,reason:'Контрольная подпись источника состояния не совпадает.'};
  const stale=Date.now()-Date.parse(payload.observedAt)>180000;return {...payload,available:!stale,stale,source:'Подписанный агент мониторинга хоста'};
 }catch{return {available:false,reason:'Источник мониторинга хоста недоступен; показатели не подставляются.'};}
}
export async function runtimeStatus(db:Database,storage:StorageService,redis?:{ping:()=>Promise<string>}){
 const observedAt=new Date().toISOString();
 const checks:any={api:{ok:true,source:'Этот запрос API',checkedAt:observedAt},database:await db.query('SELECT 1').then(()=>({ok:true,checkedAt:observedAt})).catch(()=>({ok:false,checkedAt:observedAt})),storage:await storage.client.bucketExists(env.minioBucket).then(ok=>({ok,checkedAt:observedAt})).catch(()=>({ok:false,checkedAt:observedAt}))};
 checks.redis=redis?await redis.ping().then(()=>({ok:true,checkedAt:observedAt})).catch(()=>({ok:false,checkedAt:observedAt})):{ok:null,reason:'Источник Redis не передан.'};
 const [counts,worker,host,audit]=await Promise.all([
  db.query(`SELECT (SELECT COUNT(*)::int FROM tech_problems WHERE status='new') AS new_problems, (SELECT COUNT(*)::int FROM tech_problems WHERE status IN ('new','investigating','confirmed')) AS open_problems,
  (SELECT COUNT(*)::int FROM tech_problems WHERE severity='critical' AND status NOT IN ('fixed','dismissed')) AS critical,
  (SELECT COUNT(DISTINCT user_id)::int FROM tech_events WHERE (result IN ('failure','interrupted') OR action='client.error') AND started_at>NOW()-INTERVAL '24 hours') AS affected_users,
  (SELECT COUNT(*)::int FROM tech_problems WHERE kind IN ('security','domain') AND status NOT IN ('fixed','dismissed')) AS anomalies,
  (SELECT COUNT(*)::int FROM tech_files WHERE decision IN ('rejected','manual_review') AND review_status='pending') AS files_to_review,
  (SELECT COUNT(*)::int FROM tech_events WHERE result='started' AND started_at<NOW()-INTERVAL '5 minutes') AS unresolved_requests,
  (SELECT COUNT(*)::int FROM tech_push_deliveries WHERE status IN ('failed','retry')) AS push_errors`),
  db.query("SELECT * FROM tech_heartbeats WHERE service='worker'"),readHostStatus(),verifyAudit(db,1000)
 ]);
 const beat=worker.rows[0];
 let disk:any;try{const s=await fs.statfs('/app').catch(()=>fs.statfs(process.cwd()));disk={scope:'Файловая система контейнера API',availableBytes:s.bavail*s.bsize,totalBytes:s.blocks*s.bsize};}catch{disk={available:null,reason:'Не удалось измерить файловую систему контейнера.'};}
 return {observedAt,lastSuccessfulUpdate:observedAt,checks,counts:counts.rows[0],worker:beat?{...beat,available:Date.now()-new Date(beat.observed_at).getTime()<90000}:{available:false,reason:'Нет сигнала worker.'},
  resources:{scope:'Процесс API, не весь сервер',rssBytes:process.memoryUsage().rss,heapBytes:process.memoryUsage().heapUsed,uptimeSeconds:Math.floor(process.uptime()),disk},
  host,release:process.env.APP_RELEASE??'не передана',collector:{...health,configured:Boolean(secretKey())},audit,
  organizations:{applicable:false,reason:'В DomLY нет модели организаций. Область доступа — пользователи, квартиры, заказы и кластеры; организация не определяется по IP.'},
  historyCoverage:'Сбор начинается с установки этой версии. Незаписанные ранее действия и локальные действия старых клиентов восстановить нельзя.'};
}
function validPush(endpoint:string){try{const u=new URL(endpoint);return u.protocol==='https:'&&(u.hostname==='fcm.googleapis.com'||u.hostname.endsWith('.push.apple.com')||u.hostname==='updates.push.services.mozilla.com'||u.hostname.endsWith('.notify.windows.com'))&&!u.username&&!u.password;}catch{return false;}}
export {validPush};
async function pushTick(db:Database){
 if(!process.env.TECH_VAPID_PUBLIC_KEY||!process.env.TECH_VAPID_PRIVATE_KEY)return;
 webpush.setVapidDetails('https://domly.kz/api/tech/',process.env.TECH_VAPID_PUBLIC_KEY,process.env.TECH_VAPID_PRIVATE_KEY);
 await db.query(`INSERT INTO tech_push_deliveries(notification_id,subscription_id)
 SELECT n.id,s.id FROM tech_notifications n JOIN tech_push_subscriptions s ON s.account_id=n.account_id AND s.disabled=FALSE
 JOIN tech_accounts a ON a.id=n.account_id AND a.disabled=FALSE
 WHERE n.created_at>s.created_at-INTERVAL '1 minute' AND n.acknowledged_at IS NULL AND (n.importance='critical' OR a.muted_until IS NULL OR a.muted_until<NOW())
 ON CONFLICT DO NOTHING`);
 const rows=(await db.query(`SELECT d.id,s.id AS subscription_id,s.subscription,n.id AS notification_id,n.problem_id,n.event_id,n.importance
 FROM tech_push_deliveries d JOIN tech_push_subscriptions s ON s.id=d.subscription_id JOIN tech_notifications n ON n.id=d.notification_id
 JOIN tech_accounts a ON a.id=s.account_id
 WHERE d.status IN ('pending','retry') AND d.next_attempt<=NOW() AND s.disabled=FALSE AND a.disabled=FALSE AND n.acknowledged_at IS NULL
 AND (n.importance='critical' OR a.muted_until IS NULL OR a.muted_until<NOW()) ORDER BY d.next_attempt LIMIT 5`)).rows;
 for(const row of rows){
  const acquired=(await db.query("UPDATE tech_push_deliveries SET status='sending',attempts=attempts+1 WHERE id=$1 AND status IN ('pending','retry') RETURNING attempts",[row.id])).rows[0];if(!acquired)continue;
  try{
   if(!validPush(row.subscription.endpoint))throw {statusCode:400};
   const url='/api/tech/#'+(row.problem_id?'problems/'+row.problem_id:'notifications');
   await webpush.sendNotification(row.subscription,JSON.stringify({severity:row.importance,title:row.importance==='critical'?'Критическое событие DomLY':'Событие технической панели',body:'Откройте техническую панель для проверки.',tag:row.notification_id,url}),{TTL:86400,urgency:row.importance==='critical'?'high':'normal',timeout:5000});
   await db.query("UPDATE tech_push_deliveries SET status='sent',sent_at=NOW(),failure_code=NULL WHERE id=$1",[row.id]);
  }catch(e:any){
   const expired=[404,410].includes(e.statusCode);
   if(expired)await db.query('UPDATE tech_push_subscriptions SET disabled=TRUE WHERE id=$1',[row.subscription_id]);
   await db.query(`UPDATE tech_push_deliveries SET status=$2,failure_code=$3,next_attempt=NOW()+INTERVAL '5 minutes' WHERE id=$1`,[row.id,expired?'expired':acquired.attempts>=12?'failed':'retry','push_'+(Number(e.statusCode)||'unavailable')]);
  }
 }
 await db.query("UPDATE tech_push_deliveries SET status='retry',failure_code='worker_interrupted',next_attempt=NOW() WHERE status='sending' AND next_attempt<NOW()-INTERVAL '5 minutes'");
}
async function detectAnomalies(db:Database){
 const rules=(await readRules(db)).config;
 const rows=(await db.query(`SELECT user_id,COUNT(*)::int AS attempts,COUNT(*) FILTER(WHERE http_status IN (401,403))::int AS denied,
 COUNT(*) FILTER(WHERE source='server' AND action NOT LIKE '%telemetry%' AND action NOT LIKE '%auth/refresh%' AND (action LIKE 'POST %' OR action LIKE 'PATCH %' OR action LIKE 'DELETE %'))::int AS mutations,
 COUNT(*) FILTER(WHERE error_code='file_quality_rejected')::int AS rejected_files
 FROM tech_events WHERE started_at>NOW()-INTERVAL '10 minutes' AND user_id IS NOT NULL GROUP BY user_id`)).rows;
 for(const r of rows){
  const tests=[['access_denied',r.denied,Number(rules.deniedThreshold), 'Повторные отказы доступа','security'],['mass_operations',r.mutations,Number(rules.massOperationThreshold),'Необычно много запросов на изменение за 10 минут','domain'],['rejected_uploads',r.rejected_files,Number(rules.uploadThreshold),'Повторные отклонённые загрузки','security']];
  for(const [code,count,threshold,title,kind] of tests)if(Number(count)>=Number(threshold)){
   const fingerprint='rule:'+code+':'+r.user_id+':'+Math.floor(Date.now()/600000);
   if(!(await db.query('SELECT 1 FROM tech_problems WHERE fingerprint=$1',[hash(fingerprint)])).rows.length){
    const p=await problem(db,{kind:String(kind),fingerprint,code:String(code),title:String(title),recommendation:`Правило версии ${(await readRules(db)).version}: ${count} событий за 10 минут, порог ${threshold}. Это сигнал для проверки, не доказательство нарушения. Откройте события аккаунта; личность не определяется по IP.`});
    await db.query(`UPDATE tech_events SET problem_id=COALESCE(problem_id,$2) WHERE user_id=$1 AND started_at>NOW()-INTERVAL '10 minutes'`,[r.user_id,p.id]);
   }
  }
 }
 const roleChanges=(await db.query(`SELECT id,user_id,entity_id FROM tech_events WHERE action LIKE 'PATCH %users%' AND fields ? 'role' AND result='success' AND started_at>NOW()-INTERVAL '10 minutes' AND problem_id IS NULL LIMIT 20`)).rows;
 for(const r of roleChanges)await problem(db,{kind:'security',fingerprint:'role-change:'+r.id,code:'role_changed',title:'Изменена роль аккаунта',eventId:r.id,recommendation:'Сверьте исполнителя, причину и разрешённую роль до/после изменения. Само изменение не доказывает злоупотребление.'});
 const unfinished=(await db.query("SELECT id FROM tech_events WHERE result='started' AND started_at<NOW()-INTERVAL '5 minutes' AND problem_id IS NULL LIMIT 20")).rows;
 for(const r of unfinished)await problem(db,{kind:'domain',fingerprint:'unfinished-request',code:'request_not_completed',title:'Серверное обращение без записанного завершения',eventId:r.id,recommendation:'Проверьте результат в предметном объекте и поздние события. Возможны перезапуск сервера и обрыв связи; отсутствие событий не доказывает, что клиент прекратил работу.'});
 const counts=(await db.query(`SELECT COUNT(*)::int AS n FROM tech_login_attempts WHERE success=FALSE AND created_at>NOW()-INTERVAL '15 minutes'`)).rows[0];
 if(counts.n>=Number(rules.failedLoginThreshold)){
  const f='tech-bruteforce:'+Math.floor(Date.now()/900000);if(!(await db.query('SELECT 1 FROM tech_problems WHERE fingerprint=$1',[hash(f)])).rows.length)
   await problem(db,{kind:'security',fingerprint:f,code:'technical_login_failures',title:'Повторные неудачные входы в техническую панель',recommendation:'Смотрите отдельный аудит входов. Сработал порог попыток; не устанавливайте личность по IP.'});
 }
}
export async function cleanupTechnical(db:Database,storage:StorageService){
 const rules=(await readRules(db)).config;
 const expired=(await db.query('SELECT id,bucket,object_key FROM tech_files WHERE quarantined=TRUE AND original_available=TRUE AND expires_at<NOW() LIMIT 30')).rows;
 for(const f of expired){await storage.client.removeObject(f.bucket,f.object_key);await db.query("UPDATE tech_files SET original_available=FALSE,reason=reason || ' Оригинал удалён по политике хранения.' WHERE id=$1",[f.id]);}
 await db.query(`DELETE FROM tech_events WHERE id IN (SELECT id FROM tech_events WHERE started_at<NOW()-($1||' days')::interval ORDER BY started_at LIMIT 1000)`,[rules.eventsDays]);
 await db.query("DELETE FROM tech_files WHERE quarantined=TRUE AND original_available=FALSE AND created_at<NOW()-INTERVAL '90 days' AND event_id IS NULL");
 await db.query("DELETE FROM tech_login_attempts WHERE created_at<NOW()-INTERVAL '30 days'");
 await db.query("DELETE FROM tech_sessions WHERE expires_at<NOW()-INTERVAL '7 days'");
 // Audit is archived with chain boundary and checksum before removing old database rows.
 if(!secretKey())return;
 await db.transaction(async tx=>{
  await tx.query('SELECT pg_advisory_xact_lock(77412565)');
  const rows=(await tx.query(`SELECT * FROM tech_audit WHERE at<NOW()-($1||' days')::interval ORDER BY seq LIMIT 1000`,[Math.max(30,Number(rules.auditDays))])).rows;
  if(!rows.length)return;
  const bytes=gzipSync(Buffer.from(rows.map(r=>JSON.stringify(r)).join('\n'))),key='audit/'+rows[0].seq+'-'+rows.at(-1).seq+'.ndjson.gz';
  await ensurePrivateBucket(storage);await storage.client.putObject(privateBucket(),key,bytes,bytes.length,{'Content-Type':'application/gzip'});
  await tx.query('INSERT INTO tech_audit_archives(first_seq,last_seq,previous_hash,last_hash,sha256,object_key,rows) VALUES($1,$2,$3,$4,$5,$6,$7)',[rows[0].seq,rows.at(-1).seq,rows[0].previous_hash,rows.at(-1).entry_hash,hash(bytes),key,rows.length]);
  await tx.query("SELECT set_config('domly.tech_archive','on',true)");await tx.query('DELETE FROM tech_audit WHERE seq=ANY($1::bigint[])',[rows.map(r=>r.seq)]);
 });
}
let busy=false,lastCleanup=0;
export async function technicalTick(db:Database,storage:StorageService,queues:Record<string,any>={}){
 if(busy)return;busy=true;
 try{
  const states:any={collector:{...health},release:process.env.APP_RELEASE??null,queues:{},technicalInitialized:Boolean(secretKey())};
  for(const [name,q] of Object.entries(queues))try{states.queues[name]=await q.getJobCounts('waiting','active','completed','failed','delayed');}catch{states.queues[name]={available:false};}
  await db.query("INSERT INTO tech_heartbeats(service,state) VALUES('worker',$1) ON CONFLICT(service) DO UPDATE SET observed_at=NOW(),state=EXCLUDED.state",[states]);
  if(secretKey()){await pushTick(db);await detectAnomalies(db);await domainRules(db);if(Date.now()-lastCleanup>3600000){await cleanupTechnical(db,storage);lastCleanup=Date.now();}}
 }catch{collectorFailure();}finally{busy=false;}
}
