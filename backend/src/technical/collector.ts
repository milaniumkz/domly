import {randomUUID} from 'node:crypto';
import {Request,Response,NextFunction} from 'express';
import {Database} from '../infrastructure/db/Database';
import {verifyAccessToken} from '../common/auth';
import {health,collectorFailure,sanitize,safeText,problem,seal} from './core';

declare global {namespace Express {interface Request {techEventId?:string;techRequestId?:string;techFileReview?:any;technicalError?:{code:string;kind:string};}}}
const uuid=/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const fields=new Set(['status','role','area','actualArea','approvedArea','amount','quantity','packageId','customerPackageId','addressId','date','startTime','scheduledAt','provider','active','reviewStatus','paymentId','orderId','fileId','folder','type','full_name','fullName','homeAddress','street','city','house','apartment','entrance','verified_area','requested_area','scheduled_date','start_time','end_time','cleaner_id','customer_id','user_id','payment_status']);
const bodyFields=(body:any)=>Object.fromEntries(Object.entries(body??{}).filter(([k])=>fields.has(k)).map(([k,v])=>[k,sanitize(v)]));
export function eventSignature(row:any){const keys=['id','request_id','user_id','user_name','user_role','auth_session_id','client_session_id','operation_id','source','action','entity_type','entity_id','result','started_at','finished_at','duration_ms','http_status','error_code','user_message','failure_reason','platform','app_version','device','ip','gps','fields','before_values','after_values'];return seal(Object.fromEntries(keys.map(k=>[k,row[k] instanceof Date?row[k].toISOString():row[k]??null])));}

function entity(path:string){
 const pieces=path.split('/').filter(Boolean);const key=pieces.findIndex(x=>uuid.test(x));
 const type=key>0?pieces[key-1]:pieces.at(-1)??'api';return {type:safeText(type,80),id:key>=0?pieces[key]:null};
}
export function collectRequests(db:Database){return async(req:Request,res:Response,next:NextFunction)=>{
 if(!req.path.startsWith('/api/v1')||req.path.startsWith('/api/v1/realtime')||req.path.includes('/files/media')||req.path.includes('/integrations/moon-ai/docs'))return next();
 const clientRequestId=uuid.test(String(req.headers['x-request-id']))?String(req.headers['x-request-id']):null;
 const clientCorrelation=clientRequestId?{clientRequestId,clientRequestIdSource:'Сообщено клиентом; не является серверным идентификатором запроса.'}:{};
 const requestId=randomUUID();req.techRequestId=requestId;res.setHeader('X-Request-ID',requestId);
 const started=Date.now(),target=entity(req.path),eventId=randomUUID();req.techEventId=eventId;
 let identity:any=null;try{const raw=String(req.headers.authorization??'');if(raw.startsWith('Bearer ')){const jwt=verifyAccessToken(raw.slice(7));identity=(await db.query('SELECT id,full_name,role FROM app_users WHERE id=$1',[jwt.id])).rows[0];if(identity)identity.sessionId=jwt.sessionId;}}catch{}
 let identityEvidence=identity?'Подписанный токен доступа; разрешение операции проверяется отдельно.':'Исполнитель не установлен.';
 try{if(!identity&&/^\/api\/v1\/auth\/(password\/login|otp\/request|otp\/verify)$/.test(req.path)){let phone=String(req.body?.phone??'').replace(/[^0-9]/g,'');if(phone.length===11&&phone.startsWith('8'))phone='7'+phone.slice(1);if(phone.length===11){identity=(await db.query('SELECT id,full_name,role FROM app_users WHERE phone=$1',['+'+phone])).rows[0];if(identity)identityEvidence='Указан телефон этого аккаунта; личность отправителя ещё не подтверждена.';}}}catch{collectorFailure();}
 if(req.path==='/api/v1/quality-checks/from-file')target.type='quality-checks';
 if(identity&&req.path==='/api/v1/cleaner/verification'){target.type='users';target.id=identity.id;}
 if(identity&&req.path==='/api/v1/me'){target.type='users';target.id=identity.id;}
 const header=(name:string,max=80)=>safeText(req.header(name)??'',max)||null;
 const clientSession=/^[a-zA-Z0-9_-]{8,80}$/.test(req.header('x-domly-session')??'')?req.header('x-domly-session'):null;
 const op=/^[a-zA-Z0-9_-]{8,80}$/.test(req.header('x-domly-operation')??'')?req.header('x-domly-operation'):null;
 let before:any=null,subjectUserId:string|null=null;
 const targetTable:Record<string,string>={orders:'service_orders',users:'app_users',addresses:'customer_addresses','quality-checks':'quality_check_requests',payments:'payments'};
 const table=targetTable[target.type];
 const ownerColumn:Record<string,string>={orders:'customer_id',users:'id',addresses:'user_id','quality-checks':'customer_id',payments:'customer_id'};
 const readState=async(objectId:string,actor:any)=>{
  if(!table||!actor?.id)return null;
  const owner=ownerColumn[target.type],staff=['admin','superadmin'].includes(actor.role);
  const r=(await db.query(`SELECT to_jsonb(t)-'password_hash'-'payload'-'settings' AS state FROM ${table} t
   WHERE id=$1 AND ($2::boolean OR ${owner}=$3::uuid ${target.type==='orders'?'OR cleaner_id=$3::uuid':''})`,[objectId,staff,actor.id])).rows[0];
  return r?{values:bodyFields(r.state),subject:r.state[owner]??null}:null;
 };
 if(table&&target.id&&identity&&['POST','PATCH','DELETE'].includes(req.method))try{const state=await readState(target.id,identity);before=state?.values??null;subjectUserId=state?.subject??null;}catch{collectorFailure();}
 try{await db.query(`INSERT INTO tech_events(id,request_id,user_id,user_name,user_role,client_session_id,operation_id,action,entity_type,entity_id,platform,app_version,device,ip,fields,before_values)
 VALUES($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,$14,$15,$16)`,[eventId,requestId,identity?.id??null,identity?.full_name??null,identity?.role??null,clientSession,op,safeText(req.method+' '+req.path.replace(/[0-9a-f]{8}-[0-9a-f-]{27}/gi,':id'),240),target.type,target.id,header('x-domly-platform'),header('x-domly-version'),header('user-agent',160),req.ip??req.socket.remoteAddress??null,{...bodyFields(req.body),identityEvidence,...clientCorrelation},null]);health.lastSuccessAt=new Date().toISOString();}catch{collectorFailure();}
 let responseError:any=null,resultId:any=null,responseUser:any=null;
 const json=res.json.bind(res);res.json=((value:any)=>{
  if(value?.ok===false)responseError={code:safeText(value.code,100),message:safeText(value.message)};
  const data=value?.data;if(data?.user?.id&&req.path.startsWith('/api/v1/auth/'))responseUser=data.user;resultId=data?.file?.id??data?.order?.id??data?.payment?.id??data?.id??null;
  return json(value);
 }) as any;
 let ended=false;
 const finish=(interrupted=false)=>{
  if(ended)return;ended=true;
  void (async()=>{
   let user=req.user??responseUser??identity;
   if(!user&&/^\/api\/v1\/auth\/(password\/login|otp\/request|otp\/verify)$/.test(req.path)){
    let phone=String(req.body?.phone??'').replace(/[^0-9]/g,'');if(phone.length===11&&phone.startsWith('8'))phone='7'+phone.slice(1);
    if(phone.length===11){user=(await db.query('SELECT id,full_name,role FROM app_users WHERE phone=$1',['+'+phone])).rows[0];if(user)identityEvidence='Указан телефон аккаунта; личность отправителя ещё не подтверждена.';}
   }
   if(responseUser)identityEvidence='Успешная серверная проверка входа. Дальнейшие действия определяются отдельными событиями.';
   const result=interrupted?'interrupted':res.statusCode>=400?'failure':'success';
   const entityId=target.id??(uuid.test(String(resultId))?resultId:null);let after=null;
   const denied=[401,403].includes(res.statusCode);
   if(denied){before=null;subjectUserId=null;}
   if(!denied&&table&&entityId&&['POST','PATCH','DELETE'].includes(req.method))try{const state=await readState(entityId,user);after=state?.values??null;subjectUserId=subjectUserId??state?.subject??null;}catch{collectorFailure();}
   const row=(await db.query(`UPDATE tech_events SET result=$2,finished_at=NOW(),duration_ms=$3,http_status=$4,error_code=$5,user_message=$6,failure_reason=$7,
    before_values=$15,user_name=COALESCE(user_name,$14),fields=$13,auth_session_id=$12,user_id=COALESCE($8,user_id),user_role=COALESCE($9,user_role),entity_id=COALESCE(entity_id,$10),after_values=$11 WHERE id=$1 RETURNING *`,
    [eventId,result,Math.min(2147483647,Date.now()-started),interrupted?null:res.statusCode,responseError?.code??req.technicalError?.code??null,responseError?.message??null,
    interrupted?'Соединение закрыто до ответа. Дальнейшее состояние операции необходимо проверить.':req.technicalError?req.technicalError.kind+' ('+req.technicalError.code+')':responseError?.code??null,user?.id??null,user?.role??null,entityId,after,user?.sessionId??null,{...bodyFields(req.body),identityEvidence,...clientCorrelation,...(subjectUserId?{subjectUserId}:{})},user?.full_name??null,before])).rows[0];
   if(!row)return;
   await db.query('UPDATE tech_events SET signature=$2 WHERE id=$1',[eventId,eventSignature(row)]);
   if(result==='failure'&&res.statusCode>=500)await problem(db,{fingerprint:row.action+':'+row.error_code+':'+row.failure_reason,code:row.error_code??'server_error',title:'Ошибка серверной операции: '+row.action,severity:'critical',eventId,
    recommendation:'Откройте точное сообщение и хронологию. Проверьте связанный сервис, входные поля и установленную версию. Причину подтверждайте фактами.'});
   health.lastSuccessAt=new Date().toISOString();
  })().catch(collectorFailure);
 };
 res.once('finish',()=>finish());res.once('close',()=>finish(!res.writableFinished));next();
};}
export function technicalErrorInfo(error:any,req:Request,_res:Response,next:NextFunction){
 req.technicalError={code:/^[a-z0-9_]{1,80}$/i.test(String(error.code??''))?String(error.code):'unhandled_error',kind:safeText(error.name??'Error',80)+(/^[a-z0-9_]{1,120}$/i.test(String(error.constraint??''))?' · ограничение '+error.constraint:'')};next(error);
}
