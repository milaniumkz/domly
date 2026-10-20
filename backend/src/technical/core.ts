import {createHash,createHmac,randomBytes,timingSafeEqual} from 'node:crypto';
import {ApiError} from '../common/api';
import {Database} from '../infrastructure/db/Database';
import {Queryable} from '../domain/repositories/UnitOfWork';

export const permissions=['events.read','problems.manage','pii.read','files.preview','files.original','users.manage','dangerous','access.manage','rules.manage'];
export type Operator={id:string;login:string;display_name:string;owner:boolean;permissions:string[];user_scope:string[]|null;must_change_password:boolean;session_id:string;csrf:string};
export const health={failures:0,lastFailureAt:null as string|null,lastSuccessAt:null as string|null};
export const secretKey=()=>process.env.TECH_AUDIT_KEY??'';
export const hash=(v:string|Buffer)=>createHash('sha256').update(v).digest('hex');
export const randomToken=()=>randomBytes(32).toString('base64url');
export const canonical=(v:any):string=>JSON.stringify(v,(_k,x)=>x&&typeof x==='object'&&!Array.isArray(x)?Object.fromEntries(Object.entries(x).sort(([a],[b])=>(a<b?-1:a>b?1:0))):x);
export function seal(value:any){if(!secretKey())return null;return createHmac('sha256',secretKey()).update(canonical(value)).digest('hex');}
export function equal(a:string,b:string){const x=Buffer.from(a),y=Buffer.from(b);return x.length===y.length&&timingSafeEqual(x,y);}
const secrets=/password|passwd|парол|token|secret|cookie|authorization|credential|signature|private.?key|api.?key|otp|cvv|cvc|(^|_)pin($|_)/i;
const privateFields=/phone|телефон|email|name|address|street|house|apartment|user_name|user_agent|entrance|floor|intercom|access_comment|label|^text$|comment|hypothesis|confirmed_cause|device|ip$|gps|location|latitude|longitude|position/i;
export function safeText(v:unknown,max=500):string {
 return String(v??'').replace(/Bearer\s+\S+/gi,'Bearer [скрыто]').replace(/\beyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+/g,'[токен скрыт]')
 .replace(/((?:password|passwd|пароль|token|secret|api[_-]?key|authorization|cookie)\s*[:=]\s*)("[^"]*"|'[^']*'|[^\s,;]+)/gi,'$1[скрыто]')
 .replace(/\bapi_[A-Za-z0-9_-]{16,}/g,'[ключ скрыт]').replace(/([?&](?:token|signature|key|access_token|code)\s*=)[^&\s]+/gi,'$1[скрыто]')
 .replace(/\b\d{6}\b/g,'[код скрыт]').slice(0,max);
}
export function sanitize(v:any,pii=true,depth=0):any {
 if(depth>7)return '[ограничена глубина]';if(v===null||v===undefined)return v;
 if(v instanceof Date)return Number.isFinite(v.getTime())?v.toISOString():null;
 if(typeof v==='string')return safeText(v,1500);if(typeof v!=='object')return v;
 if(Array.isArray(v))return v.slice(0,100).map(x=>sanitize(x,pii,depth+1));
 return Object.fromEntries(Object.entries(v).slice(0,80).map(([k,x])=>[k,secrets.test(k)&&typeof x!=='boolean'?'[секрет скрыт]':!pii&&privateFields.test(k)?'[персональные данные скрыты]':sanitize(x,pii,depth+1)]));
}
export function can(op:Operator,permission:string){return op.owner||op.permissions.includes(permission);}
export function need(op:Operator,permission:string){if(!can(op,permission))throw new ApiError(403,'tech_forbidden','Нет отдельного технического разрешения: '+permission);}
export function scope(op:Operator,userId:string|null|undefined){if(op.user_scope&&(!userId||!op.user_scope.includes(userId)))throw new ApiError(403,'tech_scope_denied','Объект вне разрешённой области пользователей.');}
export function id(value:any){if(typeof value!=='string'||!/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(value))throw new ApiError(400,'invalid_id','Некорректный идентификатор.');return value;}
export function reason(body:any){const r=String(body.reason??'').trim();if(r.length<8||r.length>1000||body.confirm!==true)throw new ApiError(400,'reason_required','Укажите причину (8–1000 символов) и явное подтверждение.');return safeText(r,1000);}
export function collectorFailure(){health.failures++;health.lastFailureAt=new Date().toISOString();console.error('technical_collector_failed');}
export type AuditInput={accountId?:string;sessionId?:string;action:string;targetType?:string;targetId?:string;result?:string;payload?:any};
export async function audit(db:Database,input:AuditInput){return db.transaction(tx=>appendAudit(tx,input));}
export async function appendAudit(tx:Queryable,input:AuditInput){
 if(!secretKey())throw new ApiError(503,'technical_not_initialized','Технический аудит ещё не инициализирован.');
  await tx.query('SELECT pg_advisory_xact_lock(77412565)');
  const last=(await tx.query(`SELECT entry_hash FROM tech_audit ORDER BY seq DESC LIMIT 1`)).rows[0];
  const archived=last?null:(await tx.query('SELECT last_hash FROM tech_audit_archives ORDER BY last_seq DESC LIMIT 1')).rows[0];
  const entry={account_id:input.accountId??null,session_id:input.sessionId??null,action:input.action,target_type:input.targetType??null,target_id:input.targetId??null,result:input.result??'success',payload:sanitize(input.payload??{}),at:new Date().toISOString(),previous_hash:last?.entry_hash??archived?.last_hash??'GENESIS'};
  const signature=seal(entry)!;
  await tx.query(`INSERT INTO tech_audit(account_id,session_id,action,target_type,target_id,result,payload,at,previous_hash,entry_hash)
   VALUES($1,$2,$3,$4,$5,$6,$7,$8,$9,$10)`,[entry.account_id,entry.session_id,entry.action,entry.target_type,entry.target_id,entry.result,entry.payload,entry.at,entry.previous_hash,signature]);
  return signature;
}
export async function verifyAudit(db:Queryable,limit=1000){
 const rows=(await db.query('SELECT * FROM tech_audit ORDER BY seq DESC LIMIT $1',[limit])).rows.reverse();let failures=0;
 for(let i=0;i<rows.length;i++){
  const r=rows[i];const {account_id,session_id,action,target_type,target_id,result,payload,previous_hash}=r;
  const signature=seal({account_id,session_id,action,target_type,target_id,result,payload,at:new Date(r.at).toISOString(),previous_hash});
  if(signature!==r.entry_hash||(i>0&&rows[i-1].entry_hash!==previous_hash))failures++;
 }
 return {valid:secretKey()?failures===0:null,failures,checked:rows.length,firstSeq:rows[0]?.seq??null,lastSeq:rows.at(-1)?.seq??null,head:rows.at(-1)?.entry_hash??null,scope:'Последние '+limit+' записей; архивы и внешний контрольный хеш показываются отдельно.'};
}
export async function readRules(db:Queryable){const row=(await db.query('SELECT * FROM tech_rules WHERE id=1')).rows[0];return {...row,config:{geoDistanceKm:100,...row.config}};}
export const technicalSubjectSql=(a='e')=>`COALESCE(${a}.fields->>'subjectUserId',${a}.before_values->>'customer_id',${a}.after_values->>'customer_id',${a}.before_values->>'user_id',${a}.after_values->>'user_id',CASE WHEN ${a}.entity_type='users' AND (${a}.before_values IS NOT NULL OR ${a}.after_values IS NOT NULL) THEN ${a}.entity_id END)`;
export const technicalSubjectGuard=(parameter:string,a='e')=>`(${technicalSubjectSql(a)} IS NULL OR (${technicalSubjectSql(a)})::uuid=ANY(${parameter}::uuid[]))`;
export const technicalEventSubject=(r:any)=>r.fields?.subjectUserId??r.before_values?.customer_id??r.after_values?.customer_id??r.before_values?.user_id??r.after_values?.user_id??(r.entity_type==='users'&&(r.before_values||r.after_values)?r.entity_id:null);
export async function problem(db:Database,input:{kind?:string;severity?:string;fingerprint:string;title:string;code:string;recommendation:string;eventId?:string}){
 const row=(await db.query(`INSERT INTO tech_problems(fingerprint,kind,severity,title,error_code,recommendation,occurrences)
 VALUES($1,$2,$3,$4,$5,$6,1) ON CONFLICT(fingerprint) DO UPDATE SET last_seen=NOW(),occurrences=tech_problems.occurrences+1,
 status=CASE WHEN tech_problems.status='fixed' THEN 'new' ELSE tech_problems.status END,updated_at=NOW() RETURNING *`,
 [hash(input.fingerprint),input.kind??'error',input.severity??'warning',safeText(input.title),input.code,input.recommendation])).rows[0];
 if(input.eventId)await db.query('UPDATE tech_events SET problem_id=$2 WHERE id=$1',[input.eventId,row.id]);
 const alert=(await db.query(`UPDATE tech_problems SET last_alert_at=NOW() WHERE id=$1 AND
 (last_alert_at IS NULL OR last_alert_at<NOW()-INTERVAL '1 hour') RETURNING id`,[row.id])).rows[0];
 if(alert){const bucket=Math.floor(Date.now()/3600000);await db.query(`INSERT INTO tech_notifications(account_id,problem_id,event_id,importance,title,dedupe_key)
 SELECT id,$1,$2,$3,$4,$5 FROM tech_accounts WHERE disabled=FALSE AND (owner=TRUE OR 'events.read'=ANY(permissions)) AND (user_scope IS NULL OR EXISTS(SELECT 1 FROM tech_events e WHERE e.id=$2 AND e.user_id=ANY(tech_accounts.user_scope) AND ${technicalSubjectGuard('tech_accounts.user_scope')}))
 ON CONFLICT(account_id,dedupe_key) DO NOTHING`,[row.id,input.eventId??null,row.severity,'Требуется техническая проверка',`problem:${row.id}:${bucket}`]);}
 return row;
}
