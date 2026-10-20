import {eventSignature} from './collector';
import {Router,Request,Response,NextFunction} from 'express';
import path from 'node:path';
import {createHmac,randomBytes} from 'node:crypto';
import bcrypt from 'bcryptjs';
import sharp from 'sharp';
import {Database} from '../infrastructure/db/Database';
import {StorageService} from '../modules/integrations';
import {ApiError,asyncHandler,ok} from '../common/api';
import {env} from '../common/env';
import {Operator,permissions,need,can,scope,id,reason,audit,appendAudit,hash,randomToken,equal,sanitize,safeText,secretKey,readRules,verifyAudit,collectorFailure} from './core';
import {runtimeStatus,validPush,cleanupTechnical} from './runtime';
import {privateBucket} from './files';

export function technicalRouter(db:Database,storage:StorageService,redis?:{ping:()=>Promise<string>}){
 const router=Router(),assets=path.resolve(__dirname,'../../technical');
 router.use((_req,res,next)=>{res.set({'Cache-Control':'no-store','X-Content-Type-Options':'nosniff','Referrer-Policy':'no-referrer','X-Frame-Options':'DENY',
  'Content-Security-Policy':"default-src 'none'; script-src 'self'; style-src 'self'; img-src 'self' blob:; connect-src 'self'; worker-src 'self'; manifest-src 'self'; frame-ancestors 'none'; base-uri 'none'; form-action 'self'; object-src 'none'"});next();});
 for(const file of ['panel.js','panel.css','service-worker.js','favicon.svg','manifest.webmanifest'])router.get('/'+file,(_req,res)=>{if(file==='service-worker.js')res.set('Service-Worker-Allowed','/api/tech/');res.sendFile(path.join(assets,file));});
 router.get('/',(req,res)=>{if(req.originalUrl.split('?')[0]==='/api/tech')return res.redirect('/api/tech/');res.sendFile(path.join(assets,'index.html'));});
 const cookieName='domly_technical';
 const tokenFor=(req:Request)=>{const value=String(req.headers.cookie??'').split(';').map(x=>x.trim()).find(x=>x.startsWith(cookieName+'='))?.slice(cookieName.length+1);return /^[a-zA-Z0-9_-]{40,90}$/.test(value??'')?value!:'';};
 const csrfFor=(token:string)=>createHmac('sha256',token).update('domly-tech-csrf-v1').digest('base64url');
 const opFor=(res:Response)=>res.locals.operator as Operator;
 const auditRoute=(req:Request,res:Response,next:NextFunction)=>{
  res.once('finish',()=>{const op=opFor(res);void audit(db,{accountId:op?.id,sessionId:op?.session_id,action:'technical.request',targetType:'technical_route',targetId:req.path.replace(/[0-9a-f]{8}-[0-9a-f-]{27}/gi,':id'),result:res.statusCode<400?'success':'failure',payload:{method:req.method,status:res.statusCode,filterNames:Object.keys(req.query)}}).catch(collectorFailure);});next();
 };
 router.use('/api',auditRoute);
 router.post('/api/login',asyncHandler(async(req,res)=>{
  const loginOrigin=req.header('origin');if(loginOrigin&&loginOrigin!==new URL(env.publicApiUrl).origin&&!(process.env.NODE_ENV!=='production'&&/^http:\/\/(localhost|127\.0\.0\.1)(:\d+)?$/.test(loginOrigin)))throw new ApiError(403,'invalid_origin','Недопустимый источник входа.');
  if(!secretKey())throw new ApiError(503,'technical_not_initialized','Владелец должен инициализировать отдельный технический доступ.');
  const login=String(req.body.login??'').trim().toLowerCase(),password=String(req.body.password??'');
  if(!/^[a-z0-9_.-]{3,40}$/.test(login)||password.length>128)throw new ApiError(401,'tech_login_failed','Неверный технический логин или пароль.');
  const identityHash=hash(login),ipHash=hash((req.ip??'unknown')+secretKey());
  const attemptId=await db.transaction(async tx=>{
   await tx.query('SELECT pg_advisory_xact_lock(hashtextextended($1,0))',['tech-login-ip:'+ipHash]);
   const count=(await tx.query(`SELECT COUNT(*)::int AS n FROM tech_login_attempts WHERE success=FALSE AND created_at>NOW()-INTERVAL '15 minutes' AND (identity_hash=$1 OR ip_hash=$2)`,[identityHash,ipHash])).rows[0].n;
   if(count>=10)throw new ApiError(429,'too_many_attempts','Слишком много попыток. Повторите через 15 минут.');
   return (await tx.query('INSERT INTO tech_login_attempts(identity_hash,ip_hash,success) VALUES($1,$2,FALSE) RETURNING id',[identityHash,ipHash])).rows[0].id;
  });
  const account=(await db.query('SELECT * FROM tech_accounts WHERE login=$1',[login])).rows[0];
  const dummy='$2a$12$1n3XGVvTf5slwd8ykQIWzOgsOQOQtk4OLlI2lsHwUckGB.eWQZiKW';
  const verified=await bcrypt.compare(password,account?.password_hash??dummy);
  await db.query('UPDATE tech_login_attempts SET success=$2 WHERE id=$1',[attemptId,Boolean(verified&&account&&!account.disabled)]);
  if(!account||account.disabled||!verified){await audit(db,{action:'technical.login',result:'failure',payload:{identityHash,ipHash}});throw new ApiError(401,'tech_login_failed','Неверный технический логин или пароль.');}
  const token=randomToken();
  const session=await db.transaction(async tx=>{
   const row=(await tx.query("INSERT INTO tech_sessions(account_id,token_hash,expires_at) VALUES($1,$2,NOW()+INTERVAL '8 hours') RETURNING id",[account.id,hash(token)])).rows[0];
   await appendAudit(tx,{accountId:account.id,sessionId:row.id,action:'technical.login',payload:{ipHash}});return row;
  });
  res.cookie(cookieName,token,{httpOnly:true,secure:process.env.NODE_ENV==='production',sameSite:'strict',path:'/api/tech',maxAge:8*3600000});
  ok(res,{id:account.id,login:account.login,displayName:account.display_name,owner:account.owner,permissions:account.owner?permissions:account.permissions,userScope:account.user_scope,mustChangePassword:account.must_change_password,csrf:csrfFor(token),sessionId:session.id});
 }));
 router.use('/api',asyncHandler(async(req,res,next)=>{
  const token=tokenFor(req);if(!token)throw new ApiError(401,'tech_unauthorized','Войдите через отдельный технический логин.');
  const row=(await db.query(`SELECT a.*,s.id AS session_id FROM tech_sessions s JOIN tech_accounts a ON a.id=s.account_id
   WHERE s.token_hash=$1 AND s.revoked_at IS NULL AND s.expires_at>NOW() AND s.last_seen_at>NOW()-INTERVAL '30 minutes' AND a.disabled=FALSE`,[hash(token)])).rows[0];
  if(!row)throw new ApiError(401,'tech_unauthorized','Техническая сессия истекла или завершена.');
  const op:Operator={id:row.id,login:row.login,display_name:row.display_name,owner:row.owner,permissions:row.permissions,user_scope:row.user_scope,must_change_password:row.must_change_password,session_id:row.session_id,csrf:csrfFor(token)};
  res.locals.operator=op;
  if(!['GET','HEAD'].includes(req.method)){
   const origin=req.header('origin');if(origin&&origin!==new URL(env.publicApiUrl).origin&&!(process.env.NODE_ENV!=='production'&&/^http:\/\/(localhost|127\.0\.0\.1)(:\d+)?$/.test(origin)))throw new ApiError(403,'invalid_origin','Недопустимый источник действия.');
   if(!equal(req.header('x-tech-csrf')??'',op.csrf))throw new ApiError(403,'invalid_csrf','Обновите страницу и повторите подтверждённое действие.');
  }
  if(row.must_change_password&&!['/me','/password','/logout'].includes(req.path))throw new ApiError(403,'tech_password_change_required','Сначала смените временный пароль.');
  await db.query('UPDATE tech_sessions SET last_seen_at=NOW() WHERE id=$1',[row.session_id]);next();
 }));
 router.get('/api/me',asyncHandler(async(_req,res)=>{const op=opFor(res);ok(res,{...op,permissions:op.owner?permissions:op.permissions,webPushConfigured:Boolean(process.env.TECH_VAPID_PUBLIC_KEY),vapidPublicKey:process.env.TECH_VAPID_PUBLIC_KEY??null});}));
 router.post('/api/logout',asyncHandler(async(_req,res)=>{await db.query('UPDATE tech_sessions SET revoked_at=NOW() WHERE id=$1',[opFor(res).session_id]);res.clearCookie(cookieName,{path:'/api/tech'});ok(res,{loggedOut:true});}));
 router.post('/api/password',asyncHandler(async(req,res)=>{
  const op=opFor(res),nextPassword=String(req.body.newPassword??'');
  if(nextPassword.length<12||nextPassword.length>128)throw new ApiError(400,'weak_password','Новый пароль должен содержать 12–128 символов.');
  const current=(await db.query('SELECT password_hash FROM tech_accounts WHERE id=$1',[op.id])).rows[0];
  if(!await bcrypt.compare(String(req.body.currentPassword??''),current.password_hash))throw new ApiError(403,'reauth_failed','Текущий пароль не подтверждён.');
  if(await bcrypt.compare(nextPassword,current.password_hash))throw new ApiError(400,'password_reused','Выберите другой пароль.');
  const passwordHash=await bcrypt.hash(nextPassword,12);
  await db.transaction(async tx=>{
   await tx.query('UPDATE tech_accounts SET password_hash=$2,must_change_password=FALSE,updated_at=NOW() WHERE id=$1',[op.id,passwordHash]);
   await tx.query('UPDATE tech_sessions SET revoked_at=NOW() WHERE account_id=$1 AND id<>$2',[op.id,op.session_id]);
   await appendAudit(tx,{accountId:op.id,sessionId:op.session_id,action:'technical.password_changed',payload:{otherSessionsRevoked:true}});
  });ok(res,{changed:true});
 }));
 const reauth=async(req:Request,op:Operator)=>{const row=(await db.query('SELECT password_hash FROM tech_accounts WHERE id=$1',[op.id])).rows[0];if(!await bcrypt.compare(String(req.body.operatorPassword??''),row.password_hash))throw new ApiError(403,'reauth_failed','Повторно подтвердите свой технический пароль.');};
 const required=(permission:string)=>asyncHandler(async(_req,res,next)=>{need(opFor(res),permission);next();});
 router.get('/api/overview',required('events.read'),asyncHandler(async(_req,res)=>{ok(res,await runtimeStatus(db,storage,redis));}));
 function paging(req:Request){const limit=Math.max(1,Math.min(100,Number(req.query.limit)||40)),page=Math.max(1,Math.min(10000,Number(req.query.page)||1));return {limit,page,offset:(page-1)*limit};}
 function eventFilters(req:Request,op:Operator){
  const clauses:string[]=['TRUE'],values:any[]=[];
  const add=(sql:string,value:any)=>{values.push(value);clauses.push(sql.replace('?',String(values.length)));};
  if(op.user_scope)add('e.user_id=ANY($?::uuid[])',op.user_scope);
  if(req.query.user)add('e.user_id=$?::uuid',id(req.query.user));
  if(req.query.problem)add('e.problem_id=$?::uuid',id(req.query.problem));
  if(req.query.request)add('e.request_id=$?::uuid',id(req.query.request));
  if(req.query.session){if(!/^[a-zA-Z0-9_-]{8,80}$/.test(String(req.query.session)))throw new ApiError(400,'invalid_session','Некорректный ID сеанса.');add('e.client_session_id=$?',req.query.session);}
  if(req.query.session&&!req.query.user)clauses.push('e.user_id IS NULL');
  if(req.query.operation){if(!/^[a-zA-Z0-9_-]{8,80}$/.test(String(req.query.operation)))throw new ApiError(400,'invalid_operation','Некорректный ID обращения.');add('e.operation_id=$?',req.query.operation);}
  if(req.query.object)add('e.entity_id=$?',String(req.query.object).slice(0,80));
  if(req.query.result)add('e.result=$?',String(req.query.result).slice(0,30));
  if(req.query.version)add('e.app_version=$?',String(req.query.version).slice(0,100));
  if(req.query.organization)clauses.push('FALSE');
  for(const [key,column,sign] of [['from','started_at','>='],['to','started_at','<=']])if(req.query[key]){const d=new Date(String(req.query[key]));if(!Number.isFinite(d.getTime()))throw new ApiError(400,'invalid_date','Проверьте дату фильтра.');add(`e.${column}${sign}$?`,d.toISOString());}
  if(req.query.q)add('(e.action ILIKE $1 OR e.error_code ILIKE $1 OR e.entity_id ILIKE $1)'.replace(/\$1/g,'$?'),'%'+String(req.query.q).slice(0,100)+'%');
  // Repeated placeholders in the single search condition must share one parameter.
  const last=clauses.at(-1);if(last?.includes('$?'))clauses[clauses.length-1]=last.replaceAll('$?','$'+values.length);
  return {where:clauses.join(' AND '),values};
 }
 const present=(row:any,op:Operator)=>sanitize(row,can(op,'pii.read'));
 router.get('/api/events',required('events.read'),asyncHandler(async(req,res)=>{
  const op=opFor(res),p=paging(req),f=eventFilters(req,op),asc=req.query.order==='asc';
  const rows=(await db.query(`SELECT e.* FROM tech_events e WHERE ${f.where} ORDER BY e.started_at ${asc?'ASC':'DESC'},e.id ${asc?'ASC':'DESC'} LIMIT $${f.values.length+1} OFFSET $${f.values.length+2}`,[...f.values,p.limit+1,p.offset])).rows;
  ok(res,{items:rows.slice(0,p.limit).map(r=>present(r,op)),hasMore:rows.length>p.limit,page:p.page,scope:{user:req.query.user??null,session:req.query.session??null,operation:req.query.operation??null,request:req.query.request??null,object:req.query.object??null,organization:'Не применимо к Domly'},coverage:'Серверные события и сообщённые устройством действия после внедрения. Порядок — по времени регистрации сервером; время устройства сообщается отдельно и может отличаться. Пробелы не восстановлены; отсутствие продолжения не доказывает прекращение работы.'});
 }));
 router.get('/api/events/:id',required('events.read'),asyncHandler(async(req,res)=>{
  const op=opFor(res),row=(await db.query('SELECT * FROM tech_events WHERE id=$1',[id(req.params.id)])).rows[0];if(!row)throw new ApiError(404,'not_found','Событие не найдено.');scope(op,row.user_id);
  const files=can(op,'files.preview')?(await db.query('SELECT id,file_id,owner_id,created_at,decision,reason,original_available FROM tech_files WHERE event_id=$1',[row.id])).rows:[];
  const referencedFiles=can(op,'files.preview')&&row.result==='success'&&/^[0-9a-f-]{36}$/i.test(row.fields?.fileId??'')?(await db.query('SELECT id,owner_id,mime_type,size_bytes,created_at FROM files WHERE id=$1 AND owner_id=$2',[row.fields.fileId,row.user_id])).rows:[];
  const {signature,...raw}=row;ok(res,{event:present(row,op),signatureVerified:signature?eventSignature(raw)===signature:null,filesThisAction:files,referencedFilesThisAction:referencedFiles,otherMaterialsNote:'Связанные ниже текущие материалы объекта не являются файлами именно этого действия.'});
 }));
 router.get('/api/problems',required('events.read'),asyncHandler(async(req,res)=>{
  const op=opFor(res),p=paging(req),values:any[]=[];let where='TRUE';
  if(op.user_scope){values.push(op.user_scope);where+=' AND EXISTS(SELECT 1 FROM tech_events e WHERE e.problem_id=p.id AND e.user_id=ANY($1::uuid[]))';}
  for(const key of ['status','kind','severity'])if(req.query[key]){values.push(String(req.query[key]).slice(0,30));where+=` AND p.${key}=$${values.length}`;}
  if(req.query.q){values.push('%'+String(req.query.q).slice(0,100)+'%');where+=` AND p.title ILIKE $${values.length}`;}
  const rows=(await db.query(`SELECT p.*,(SELECT COUNT(DISTINCT user_id)::int FROM tech_events e WHERE e.problem_id=p.id) AS affected_users FROM tech_problems p WHERE ${where} ORDER BY p.last_seen DESC LIMIT $${values.length+1} OFFSET $${values.length+2}`,[...values,p.limit+1,p.offset])).rows;
  ok(res,{items:rows.slice(0,p.limit).map(r=>present(r,op)),hasMore:rows.length>p.limit,page:p.page});
 }));
 async function problemAccess(op:Operator,problemId:string){if(op.user_scope&&!(await db.query('SELECT 1 FROM tech_events WHERE problem_id=$1 AND user_id=ANY($2::uuid[]) LIMIT 1',[problemId,op.user_scope])).rows.length)throw new ApiError(403,'tech_scope_denied','Проблема вне области доступа.');}
 router.get('/api/problems/:id',required('events.read'),asyncHandler(async(req,res)=>{
  const op=opFor(res),problemId=id(req.params.id);await problemAccess(op,problemId);
  const row=(await db.query('SELECT * FROM tech_problems WHERE id=$1',[problemId])).rows[0];if(!row)throw new ApiError(404,'not_found','Проблема не найдена.');
  const comments=(await db.query('SELECT c.*,a.display_name FROM tech_problem_comments c JOIN tech_accounts a ON a.id=c.account_id WHERE problem_id=$1 ORDER BY c.created_at LIMIT 200',[problemId])).rows;
  const versions=(await db.query(`SELECT app_version,COUNT(*)::int AS events FROM tech_events WHERE problem_id=$1 AND ($2::uuid[] IS NULL OR user_id=ANY($2)) GROUP BY app_version`,[problemId,op.user_scope])).rows;
  const users=(await db.query('SELECT user_id,MAX(user_name) AS user_name,COUNT(*)::int AS events FROM tech_events WHERE problem_id=$1 AND user_id IS NOT NULL AND ($2::uuid[] IS NULL OR user_id=ANY($2)) GROUP BY user_id ORDER BY MIN(started_at) LIMIT 100',[problemId,op.user_scope])).rows;
  ok(res,{problem:present(row,op),comments:present(comments,op),versions,users:present(users,op),retainedEventsNote:'Количество повторений включает историю; часть отдельных событий может быть удалена по политике хранения.'});
 }));
 router.patch('/api/problems/:id',required('problems.manage'),asyncHandler(async(req,res)=>{
  const op=opFor(res),problemId=id(req.params.id);await problemAccess(op,problemId);const r=reason(req.body);
  const status=String(req.body.status??'investigating');if(!['new','investigating','confirmed','dismissed','fixed'].includes(status))throw new ApiError(400,'invalid_status','Некорректный статус.');
  if(status==='fixed'&&(!String(req.body.fixedVersion??'').trim()||String(req.body.verificationNote??'').trim().length<12||req.body.verificationPassed!==true))throw new ApiError(400,'verification_required','Для закрытия нужны исправляющая версия и результат проверки, подтверждённый оператором.');
  const assigned=req.body.assignedTo?id(req.body.assignedTo):null;
  const result=await db.transaction(async tx=>{
   const before=(await tx.query('SELECT * FROM tech_problems WHERE id=$1 FOR UPDATE',[problemId])).rows[0];if(!before)throw new ApiError(404,'not_found','Проблема не найдена.');
   const row=(await tx.query(`UPDATE tech_problems SET status=$2,assigned_to=$3,confirmed_cause=$4,hypothesis=$5,fixed_version=$6,verification_note=$7,verified_at=CASE WHEN $2='fixed' THEN NOW() ELSE NULL END,updated_at=NOW() WHERE id=$1 RETURNING *`,
   [problemId,status,assigned,safeText(req.body.confirmedCause??'',2000)||null,safeText(req.body.hypothesis??'',2000)||null,status==='fixed'?safeText(req.body.fixedVersion,100):null,status==='fixed'?safeText(req.body.verificationNote,2000):null])).rows[0];
   await tx.query('INSERT INTO tech_problem_comments(problem_id,account_id,text) VALUES($1,$2,$3)',[problemId,op.id,safeText(req.body.comment??r,2000)]);
   await appendAudit(tx,{accountId:op.id,sessionId:op.session_id,action:'problem.updated',targetType:'problem',targetId:problemId,payload:{reason:r,before,after:row}});return row;
  });ok(res,result);
 }));
 router.get('/api/users',required('events.read'),asyncHandler(async(req,res)=>{
  const op=opFor(res),p=paging(req),values:any[]=[];let where='u.deleted_at IS NULL';
  if(op.user_scope){values.push(op.user_scope);where+=' AND u.id=ANY($1::uuid[])';}
  if(req.query.q){values.push('%'+String(req.query.q).slice(0,100)+'%');where+=can(op,'pii.read')?` AND (u.phone ILIKE $${values.length} OR u.full_name ILIKE $${values.length} OR u.id::text ILIKE $${values.length})`:` AND u.id::text ILIKE $${values.length}`;}
  if(req.query.role){values.push(String(req.query.role));where+=` AND u.role::text=$${values.length}`;}
  const rows=(await db.query(`SELECT u.id,u.full_name,u.phone,u.role,u.status,u.last_login_at,u.created_at,u.password_change_required,
   (SELECT COUNT(*)::int FROM refresh_sessions s WHERE s.user_id=u.id AND s.revoked_at IS NULL AND s.expires_at>NOW()) AS active_sessions FROM app_users u WHERE ${where} ORDER BY u.created_at DESC LIMIT $${values.length+1} OFFSET $${values.length+2}`,[...values,p.limit+1,p.offset])).rows;
  ok(res,{items:rows.slice(0,p.limit).map(r=>present(r,op)),hasMore:rows.length>p.limit,page:p.page,organizations:'В этом проекте отсутствуют. Организация не определяется по IP.'});
 }));
 router.get('/api/users/:id',required('events.read'),asyncHandler(async(req,res)=>{
  const op=opFor(res),userId=id(req.params.id);scope(op,userId);
  const row=(await db.query('SELECT id,full_name,phone,role,status,last_login_at,created_at,password_change_required,auth_version FROM app_users WHERE id=$1',[userId])).rows[0];if(!row)throw new ApiError(404,'not_found','Пользователь не найден.');
  const sessions=(await db.query('SELECT id,created_at,expires_at,revoked_at,ip,user_agent FROM refresh_sessions WHERE user_id=$1 ORDER BY created_at DESC LIMIT 50',[userId])).rows;
  ok(res,present({user:row,sessions,passwordLoginApplicable:['admin','superadmin'].includes(row.role),identityNote:'Неудачная попытка входа указывает целевой аккаунт, а не доказанную личность исполнителя.'},op));
 }));
 router.post('/api/users/:id/operation',required('users.manage'),asyncHandler(async(req,res)=>{
  const op=opFor(res),userId=id(req.params.id);scope(op,userId);const r=reason(req.body),action=String(req.body.action);
  if(!['block','unblock','revoke_sessions','temporary_password'].includes(action))throw new ApiError(400,'invalid_operation','Операция не разрешена.');
  need(op,'dangerous');await reauth(req,op);
  const temporary=action==='temporary_password'?randomBytes(18).toString('base64url'):null;
  const passwordHash=temporary?await bcrypt.hash(temporary,12):null;
  await db.transaction(async tx=>{
   const user=(await tx.query('SELECT id,role,status FROM app_users WHERE id=$1 AND deleted_at IS NULL FOR UPDATE',[userId])).rows[0];if(!user)throw new ApiError(404,'not_found','Пользователь не найден.');
   if(action==='temporary_password'&&!['admin','superadmin'].includes(user.role))throw new ApiError(409,'otp_account','Клиент и уборщица входят по коду. Временный пароль для этого способа входа не используется.');
   if(action==='block')await tx.query("UPDATE app_users SET status='blocked',auth_version=auth_version+1,updated_at=NOW() WHERE id=$1",[userId]);
   if(action==='unblock'){
    // Cleaner verification is a separate business decision; unblocking must not approve documents.
    await tx.query("UPDATE app_users SET status=CASE WHEN role='cleaner' THEN 'pending'::profile_status ELSE 'approved'::profile_status END,auth_version=auth_version+1,updated_at=NOW() WHERE id=$1",[userId]);
   }
   if(action==='revoke_sessions')await tx.query('UPDATE app_users SET auth_version=auth_version+1 WHERE id=$1',[userId]);
   if(action==='temporary_password')await tx.query('UPDATE app_users SET password_hash=$2,password_change_required=TRUE,auth_version=auth_version+1,updated_at=NOW() WHERE id=$1',[userId,passwordHash]);
   await tx.query('UPDATE refresh_sessions SET revoked_at=NOW() WHERE user_id=$1 AND revoked_at IS NULL',[userId]);
   await tx.query('UPDATE device_tokens SET enabled=FALSE WHERE user_id=$1',[userId]);
   await appendAudit(tx,{accountId:op.id,sessionId:op.session_id,action:'support.'+action,targetType:'user',targetId:userId,payload:{reason:r,before:user,after:{status:action==='block'?'blocked':action==='unblock'?(user.role==='cleaner'?'pending':'approved'):user.status},sessionsRevoked:true}});
  });ok(res,{done:true,...(temporary?{temporaryPassword:temporary,mustChangePassword:true}:{}),note:'Существующий пароль не раскрывается. Временный показывается только в этом ответе.'});
 }));
 router.get('/api/files',required('files.preview'),asyncHandler(async(req,res)=>{
  const op=opFor(res),p=paging(req),values:any[]=[];let where='TRUE';
  if(op.user_scope){values.push(op.user_scope);where+=' AND owner_id=ANY($1::uuid[])';}
  if(req.query.user){values.push(id(req.query.user));where+=` AND owner_id=$${values.length}`;}
  if(req.query.event){values.push(id(req.query.event));where+=` AND event_id=$${values.length}`;}
  if(req.query.decision){values.push(String(req.query.decision));where+=` AND decision=$${values.length}`;}
  const rows=(await db.query(`SELECT id,file_id,event_id,owner_id,mime_type,size_bytes,sha256,document_type,decision,reason,algorithm_version,rules_version,quarantined,original_available,review_status,created_at FROM tech_files WHERE ${where} ORDER BY created_at DESC LIMIT $${values.length+1} OFFSET $${values.length+2}`,[...values,p.limit+1,p.offset])).rows;
  ok(res,{items:rows.slice(0,p.limit).map(r=>present(r,op)),hasMore:rows.length>p.limit,page:p.page,coverage:'Точные связи с действием доступны новым загрузкам. Старые материалы можно открыть из конкретного объекта; автор и время берутся из files, а не предполагаются.'});
 }));
 async function fileFor(op:Operator,fileId:string){
  const row=(await db.query('SELECT * FROM tech_files WHERE id=$1',[fileId])).rows[0];if(row){scope(op,row.owner_id);return row;}
  const legacy=(await db.query('SELECT id,owner_id,bucket,object_key,mime_type,size_bytes,technical_sha256 AS sha256,created_at FROM files WHERE id=$1',[fileId])).rows[0];
  if(!legacy)throw new ApiError(404,'not_found','Файл не найден.');scope(op,legacy.owner_id);return {...legacy,file_id:legacy.id,decision:'legacy',original_available:true,reason:'Материал существовал до технического сбора. Его принадлежность конкретному действию не восстановлена.'};
 }
 router.get('/api/files/:id',required('files.preview'),asyncHandler(async(req,res)=>{const op=opFor(res);const row=await fileFor(op,id(req.params.id));const {bucket,object_key,...metadata}=row;ok(res,present(metadata,op));}));
 async function fileBytes(row:any){if(!row.original_available)throw new ApiError(410,'original_missing','Оригинал не сохранился или удалён по политике хранения.');
  const stat=await storage.client.statObject(row.bucket,row.object_key).catch(()=>null);if(!stat)throw new ApiError(503,'storage_unavailable','Хранилище недоступно либо объект отсутствует; оригинал не подменяется.');
  if(stat.size>50*1024*1024)throw new ApiError(413,'file_too_large','Файл превышает лимит безопасного просмотра 50 МБ.');
  const stream=await storage.client.getObject(row.bucket,row.object_key);const chunks:Buffer[]=[];let size=0;for await(const chunk of stream){size+=chunk.length;if(size>50*1024*1024){stream.destroy();throw new ApiError(413,'file_too_large','Файл слишком большой.');}chunks.push(Buffer.from(chunk));}return Buffer.concat(chunks);
 }
 router.get('/api/files/:id/preview',required('files.preview'),asyncHandler(async(req,res)=>{
  const op=opFor(res);need(op,'pii.read');const row=await fileFor(op,id(req.params.id));
  if(!String(row.mime_type).startsWith('image/'))throw new ApiError(415,'preview_unavailable','Встроенный просмотр доступен изображениям; документ скачивается отдельно по разрешению оригиналов.');
  await audit(db,{accountId:op.id,sessionId:op.session_id,action:'file.preview',targetType:'file',targetId:row.id,payload:{ownerId:row.owner_id}});
  const bytes=await fileBytes(row);const image=await sharp(bytes,{limitInputPixels:40000000}).rotate().resize({width:1800,height:1800,fit:'inside',withoutEnlargement:true}).jpeg({quality:90}).toBuffer().catch(()=>{throw new ApiError(415,'preview_unavailable','Формат не поддерживает безопасное создание превью; запросите оригинал при наличии разрешения.');});res.type('image/jpeg').send(image);
 }));
 router.get('/api/files/:id/original',required('files.original'),asyncHandler(async(req,res)=>{
  const op=opFor(res);need(op,'pii.read');const row=await fileFor(op,id(req.params.id));
  await audit(db,{accountId:op.id,sessionId:op.session_id,action:'file.original',targetType:'file',targetId:row.id,payload:{ownerId:row.owner_id}});
  const bytes=await fileBytes(row);if(row.sha256&&hash(bytes)!==row.sha256)throw new ApiError(409,'checksum_mismatch','Контрольная сумма оригинала не совпадает. Просмотр остановлен.');
  res.set('Content-Security-Policy',"sandbox; default-src 'none'");res.attachment('original-'+row.id+(({ 'application/pdf':'.pdf','image/png':'.png','image/jpeg':'.jpg','image/webp':'.webp','image/heic':'.heic','image/heif':'.heif','image/gif':'.gif'} as Record<string,string>)[String(row.mime_type)]??'.bin')).type('application/octet-stream').send(bytes);
 }));
 router.post('/api/files/:id/review',required('problems.manage'),asyncHandler(async(req,res)=>{
  const op=opFor(res);need(op,'files.preview');const row=await fileFor(op,id(req.params.id)),r=reason(req.body),status=String(req.body.status);
  if(!['confirmed','dismissed','reviewed'].includes(status)||!row.algorithm_version)throw new ApiError(400,'invalid_review','Выберите результат проверки нового технического файла.');
  await db.transaction(async tx=>{await tx.query('UPDATE tech_files SET review_status=$2,reviewed_by=$3,review_note=$4 WHERE id=$1',[row.id,status,op.id,r]);await appendAudit(tx,{accountId:op.id,sessionId:op.session_id,action:'file.reviewed',targetType:'file',targetId:row.id,payload:{status,reason:r,doesNotApproveBusinessDocument:true}});});ok(res,{reviewed:true,note:'Это техническая оценка. Отклонённый файл не становится утверждённым документом основного процесса.'});
 }));
 router.get('/api/objects/:type/:id/materials',required('files.preview'),asyncHandler(async(req,res)=>{
  const op=opFor(res),objectId=id(req.params.id);let ids:string[]=[],owner:string|null=null;
  if(req.params.type==='quality-checks'){const q=(await db.query('SELECT customer_id,document_file_id FROM quality_check_requests WHERE id=$1',[objectId])).rows[0];if(q){owner=q.customer_id;ids=q.document_file_id?[q.document_file_id]:[];}}
  else if(req.params.type==='users'||req.params.type==='cleaners'){owner=objectId;ids=(await db.query('SELECT file_id FROM cleaner_documents WHERE cleaner_id=$1',[objectId])).rows.map(r=>r.file_id);}
  else if(req.params.type==='orders'){const o=(await db.query('SELECT customer_id FROM service_orders WHERE id=$1',[objectId])).rows[0];owner=o?.customer_id??null;const reports=(await db.query('SELECT photo_urls FROM photo_reports WHERE order_id=$1',[objectId])).rows;const urls=reports.flatMap(r=>Array.isArray(r.photo_urls)?r.photo_urls:[]).filter(x=>typeof x==='string');ids=urls.length?(await db.query('SELECT id FROM files WHERE public_url=ANY($1::text[])',[urls])).rows.map(r=>r.id):[];}
  else throw new ApiError(400,'unsupported_object','Тип объекта не поддерживает просмотр материалов.');
  if(!owner)throw new ApiError(404,'not_found','Объект не найден.');scope(op,owner);
  const rows=ids.length?(await db.query('SELECT id,owner_id,mime_type,size_bytes,created_at FROM files WHERE id=ANY($1::uuid[])',[ids])).rows:[];
  ok(res,{items:present(rows,op),label:'Остальные текущие материалы объекта. Они не приписываются выбранному действию и могут быть загружены позже другим участником.'});
 }));
 router.get('/api/notifications',required('events.read'),asyncHandler(async(req,res)=>{
  const op=opFor(res),p=paging(req);const rows=(await db.query('SELECT * FROM tech_notifications WHERE account_id=$1 ORDER BY created_at DESC LIMIT $2 OFFSET $3',[op.id,p.limit+1,p.offset])).rows;
  ok(res,{items:rows.slice(0,p.limit),hasMore:rows.length>p.limit,page:p.page,pushConfigured:Boolean(process.env.TECH_VAPID_PUBLIC_KEY)});
 }));
 router.post('/api/notifications/:id/ack',required('events.read'),asyncHandler(async(req,res)=>{const op=opFor(res);const row=(await db.query('UPDATE tech_notifications SET acknowledged_at=COALESCE(acknowledged_at,NOW()),acknowledged_by=$2 WHERE id=$1 AND account_id=$2 RETURNING id',[id(req.params.id),op.id])).rows[0];if(!row)throw new ApiError(404,'not_found','Уведомление не найдено.');ok(res,row);}));
 router.post('/api/notifications/mute',required('events.read'),asyncHandler(async(req,res)=>{const minutes=Math.max(0,Math.min(1440,Number(req.body.minutes)||0));await db.query("UPDATE tech_accounts SET muted_until=NOW()+($2||' minutes')::interval WHERE id=$1",[opFor(res).id,minutes]);ok(res,{mutedMinutes:minutes,criticalBypassesMute:true});}));
 router.post('/api/push',required('events.read'),asyncHandler(async(req,res)=>{
  const op=opFor(res),s=req.body.subscription;if(!s||!validPush(String(s.endpoint))||typeof s.keys?.auth!=='string'||typeof s.keys?.p256dh!=='string'||s.endpoint.length>2048||s.keys.auth.length>200||s.keys.p256dh.length>300)throw new ApiError(400,'invalid_subscription','Недопустимая подписка браузера.');
  if(!process.env.TECH_VAPID_PUBLIC_KEY)throw new ApiError(503,'push_not_configured','Web Push не настроен.');
  const endpointHash=hash(s.endpoint);const prior=(await db.query('SELECT account_id FROM tech_push_subscriptions WHERE endpoint_hash=$1',[endpointHash])).rows[0];if(prior&&prior.account_id!==op.id)throw new ApiError(409,'subscription_owned','Подписка принадлежит другому техническому аккаунту.');
  await db.query(`INSERT INTO tech_push_subscriptions(account_id,endpoint_hash,subscription) VALUES($1,$2,$3) ON CONFLICT(endpoint_hash) DO UPDATE SET subscription=EXCLUDED.subscription,disabled=FALSE`,[op.id,endpointHash,{endpoint:s.endpoint,keys:{auth:s.keys.auth,p256dh:s.keys.p256dh}}]);ok(res,{saved:true});
 }));
 router.delete('/api/push',asyncHandler(async(_req,res)=>{await db.query('UPDATE tech_push_subscriptions SET disabled=TRUE WHERE account_id=$1',[opFor(res).id]);ok(res,{disabled:true});}));
 router.get('/api/operators',required('events.read'),asyncHandler(async(_req,res)=>{ok(res,(await db.query('SELECT id,login,display_name,owner,disabled FROM tech_accounts ORDER BY display_name')).rows);}));
 router.get('/api/access',required('access.manage'),asyncHandler(async(_req,res)=>{ok(res,{permissions,accounts:(await db.query('SELECT id,login,display_name,owner,permissions,user_scope,disabled,must_change_password FROM tech_accounts ORDER BY created_at')).rows});}));
 router.post('/api/access',required('access.manage'),asyncHandler(async(req,res)=>{
  const op=opFor(res);if(!op.owner)throw new ApiError(403,'owner_required','Создавать технический доступ может владелец.');const r=reason(req.body);await reauth(req,op);
  const login=String(req.body.login??'').trim().toLowerCase();if(!/^[a-z0-9_.-]{3,40}$/.test(login))throw new ApiError(400,'invalid_login','Логин: 3–40 латинских букв, цифр, точек, дефисов.');
  const perms=Array.isArray(req.body.permissions)?req.body.permissions.filter((p:any)=>permissions.includes(p)):[];
  const userScope=Array.isArray(req.body.userScope)?req.body.userScope.map(id):null;
  const temporary=randomBytes(18).toString('base64url'),passwordHash=await bcrypt.hash(temporary,12);
  const account=await db.transaction(async tx=>{const row=(await tx.query('INSERT INTO tech_accounts(login,password_hash,display_name,permissions,user_scope) VALUES($1,$2,$3,$4,$5) RETURNING id,login',[login,passwordHash,safeText(req.body.displayName??login,100),perms,userScope])).rows[0];await appendAudit(tx,{accountId:op.id,sessionId:op.session_id,action:'technical.account_created',targetId:row.id,payload:{reason:r,permissions:perms,userScope}});return row;});
  ok(res,{...account,temporaryPassword:temporary,mustChangePassword:true});
 }));
 router.patch('/api/access/:id',required('access.manage'),asyncHandler(async(req,res)=>{
  const op=opFor(res);if(!op.owner)throw new ApiError(403,'owner_required','Изменять доступ может владелец.');const accountId=id(req.params.id),r=reason(req.body);await reauth(req,op);
  const row=(await db.query('SELECT * FROM tech_accounts WHERE id=$1',[accountId])).rows[0];if(!row)throw new ApiError(404,'not_found','Учётная запись не найдена.');if(row.owner)throw new ApiError(409,'owner_protected','Изменение владельца выполняется через защищённую серверную процедуру.');
  const perms=Array.isArray(req.body.permissions)?req.body.permissions.filter((p:any)=>permissions.includes(p)):row.permissions;
  const userScope=req.body.userScope===null?null:Array.isArray(req.body.userScope)?req.body.userScope.map(id):row.user_scope;
  const temporary=req.body.resetPassword===true?randomBytes(18).toString('base64url'):null;const pw=temporary?await bcrypt.hash(temporary,12):null;
  await db.transaction(async tx=>{await tx.query('UPDATE tech_accounts SET permissions=$2,user_scope=$3,disabled=$4,password_hash=COALESCE($5,password_hash),must_change_password=CASE WHEN $5 IS NULL THEN must_change_password ELSE TRUE END,updated_at=NOW() WHERE id=$1',[accountId,perms,userScope,req.body.disabled??row.disabled,pw]);await tx.query('UPDATE tech_sessions SET revoked_at=NOW() WHERE account_id=$1',[accountId]);await appendAudit(tx,{accountId:op.id,sessionId:op.session_id,action:'technical.account_changed',targetId:accountId,payload:{reason:r,permissions:perms,userScope,disabled:req.body.disabled??row.disabled,passwordReset:Boolean(temporary)}});});ok(res,{changed:true,...(temporary?{temporaryPassword:temporary}:{}),sessionsRevoked:true});
 }));
 router.get('/api/rules',required('rules.manage'),asyncHandler(async(_req,res)=>{ok(res,await readRules(db));}));
 router.patch('/api/rules',required('rules.manage'),asyncHandler(async(req,res)=>{
  const op=opFor(res),r=reason(req.body);await reauth(req,op);const old=await readRules(db),config={...old.config};
  const ranges:Record<string,[number,number]>={geoDistanceKm:[5,20000],eventsDays:[1,365],quarantineDays:[1,90],auditDays:[30,3650],failedLoginThreshold:[3,100],deniedThreshold:[3,1000],massOperationThreshold:[20,10000],uploadThreshold:[3,1000],blankDocumentStdDev:[0,5],blurReject:[0,2],blurReview:[0,100]};
  for(const [key,v]of Object.entries(req.body.config??{})){const range=ranges[key],n=Number(v);if(!range||!Number.isFinite(n)||n<range[0]||n>range[1])throw new ApiError(400,'invalid_rule','Некорректное значение правила '+key);config[key]=n;}
  const row=await db.transaction(async tx=>{const updated=(await tx.query('UPDATE tech_rules SET version=version+1,config=$1,updated_at=NOW() WHERE id=1 RETURNING *',[config])).rows[0];await appendAudit(tx,{accountId:op.id,sessionId:op.session_id,action:'technical.rules_changed',payload:{reason:r,before:old,after:updated}});return updated;});ok(res,row);
 }));
 router.get('/api/audit',required('access.manage'),asyncHandler(async(req,res)=>{const p=paging(req);ok(res,{items:(await db.query('SELECT * FROM tech_audit ORDER BY seq DESC LIMIT $1 OFFSET $2',[p.limit,p.offset])).rows,verification:await verifyAudit(db,2000),archives:(await db.query('SELECT id,first_seq,last_seq,sha256,rows,created_at FROM tech_audit_archives ORDER BY last_seq DESC LIMIT 50')).rows});}));
 router.get('/api/audit/archives/:id',required('access.manage'),asyncHandler(async(req,res)=>{
  const op=opFor(res);need(op,'files.original');const row=(await db.query('SELECT * FROM tech_audit_archives WHERE id=$1',[id(req.params.id)])).rows[0];if(!row)throw new ApiError(404,'not_found','Архив не найден.');
  await audit(db,{accountId:op.id,sessionId:op.session_id,action:'audit.archive_downloaded',targetId:row.id});
  const bytes=await fileBytes({bucket:privateBucket(),object_key:row.object_key,original_available:true});if(hash(bytes)!==row.sha256)throw new ApiError(409,'checksum_mismatch','Не совпадает контрольная сумма архива.');res.type('application/gzip').attachment('technical-audit-'+row.first_seq+'-'+row.last_seq+'.ndjson.gz').send(bytes);
 }));
 router.post('/api/maintenance/retention',required('dangerous'),asyncHandler(async(req,res)=>{const op=opFor(res);reason(req.body);await reauth(req,op);await audit(db,{accountId:op.id,sessionId:op.session_id,action:'maintenance.retention_requested',payload:{reason:reason(req.body)}});await cleanupTechnical(db,storage);ok(res,{completed:true,scope:'Ограниченная порция очистки по действующей политике; не произвольная команда или SQL.'});}));
 return router;
}
