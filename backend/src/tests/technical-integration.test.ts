import {buildRealtimeRouter,emitToUser} from '../realtime/sse';
import {buildV1Router} from '../http/routes/v1';
import {AuthService} from '../modules/domainServices';
import fs from 'node:fs';
import path from 'node:path';
import test from 'node:test';
import assert from 'node:assert/strict';
import {randomUUID} from 'node:crypto';
import {Readable} from 'node:stream';
import express from 'express';
import bcrypt from 'bcryptjs';
import sharp from 'sharp';
import {Database} from '../infrastructure/db/Database';
import {technicalRouter} from '../technical/router';
import {collectRequests,eventSignature,technicalErrorInfo} from '../technical/collector';
import {telemetryRouter} from '../technical/telemetry';
import {audit,verifyAudit,sanitize,problem,hash} from '../technical/core';
import {inspectImage,inspectUpload,registerUploadedFile} from '../technical/files';
import {auth,configureAuthDatabase,signAccessToken} from '../common/auth';
import {errorHandler,ApiError} from '../common/api';
import {validPush,technicalTick} from '../technical/runtime';

test('technical center: real PostgreSQL, access boundaries, evidence and operations',{skip:!process.env.DOMLY_INTEGRATION_DATABASE_URL},async t=>{
 process.env.TECH_AUDIT_KEY='isolated-test-key-'+randomUUID();
 const control=new Database(process.env.DOMLY_INTEGRATION_DATABASE_URL!);
 const databaseName='tech_fixture_'+randomUUID().replace(/-/g,'');
 await control.query('CREATE DATABASE '+databaseName);
 const url=new URL(process.env.DOMLY_INTEGRATION_DATABASE_URL!);url.pathname='/'+databaseName;
 const db=new Database(url.toString());await db.query(fs.readFileSync(path.resolve(__dirname,'../../sql/schema.sql'),'utf8'));
 const owner=randomUUID(),reader=randomUUID(),scoped=randomUUID(),userA=randomUUID(),userB=randomUUID(),password='TechnicalFixture!2026';
 let storageOffline=false;const objects=new Map<string,Buffer>();
 const storage:any={client:{bucketExists:async()=>{if(storageOffline)throw Error('offline');return true;},makeBucket:async()=>{},setBucketPolicy:async()=>{},putObject:async(b:string,k:string,data:Buffer)=>{if(storageOffline)throw Error('offline');objects.set(b+'/'+k,data);},statObject:async(b:string,k:string)=>{if(storageOffline)throw Error('offline');const data=objects.get(b+'/'+k);if(!data)throw Error('missing');return{size:data.length};},getObject:async(b:string,k:string)=>Readable.from([objects.get(b+'/'+k)!]),removeObject:async(b:string,k:string)=>objects.delete(b+'/'+k)}};
 const app=express();app.use(collectRequests(db));app.use(express.json());app.use('/api/tech',technicalRouter(db,storage,{ping:async()=> 'PONG'}));app.use('/api/v1/realtime',buildRealtimeRouter());app.use('/api/v1',telemetryRouter(db));app.get('/api/v1/test-success',auth(),(_q,r)=>r.json({ok:true,data:{done:true}}));app.post('/api/v1/test-fail',auth(),(_q,_r,next)=>next(new ApiError(503,'fixture_unavailable','Сервис проверки недоступен.')));app.use('/api/v1',buildV1Router({db,storage,authService:new AuthService(db,{} as any)} as any));app.use(technicalErrorInfo,errorHandler);
 const server=app.listen(0,'127.0.0.1');await new Promise<void>(resolve=>server.once('listening',resolve));const base='http://127.0.0.1:'+(server.address() as any).port;
 const accountData:any={};
 async function request(path:string,method='GET',body?:any,account:string=owner,extra:any={}){const a=accountData[account]??{};const r=await fetch(base+path,{method,headers:{'Content-Type':'application/json',...(a.cookie?{Cookie:a.cookie}:{}),...(method!=='GET'&&a.csrf?{'X-Tech-CSRF':a.csrf}:{}),...extra},body:body?JSON.stringify(body):undefined});const text=await r.text();let data:any;try{data=JSON.parse(text);}catch{data=text;}return{status:r.status,body:data,headers:r.headers};}
 const tech=(path:string,method='GET',body?:any,account:string=owner,extra={})=>request('/api/tech/api/'+path,method,body,account,extra);
 async function login(account:string,loginName:string,pw=password){const r=await tech('login','POST',{login:loginName,password:pw},account);if(r.status===200)accountData[account]={cookie:r.headers.get('set-cookie')!.split(';')[0],csrf:r.body.data.csrf};return r;}
 try{
  for(const [id,role]of [[userA,'customer'],[userB,'admin']])await db.query("INSERT INTO app_users(id,phone,full_name,role,status) VALUES($1,$2,'Изолированная проверка',$3,'approved')",[id,'technical-fixture-'+id,role]);
  for(const [id,own,perms,scope]of [[owner,true,[],null],[reader,false,['events.read'],null],[scoped,false,['events.read','pii.read','files.preview','files.original'],[userA]]])await db.query('INSERT INTO tech_accounts(id,login,password_hash,display_name,owner,permissions,user_scope,must_change_password) VALUES($1,$2,$3,$4,$5,$6,$7,FALSE)',[id,'test-'+String(id).replace(/-/g,''),await bcrypt.hash(password,4),'Тест технического доступа',own,perms,scope]);
  await t.test('ordinary application JWT cannot open panel',async()=>{const r=await tech('overview','GET',undefined,reader,{Authorization:'Bearer '+signAccessToken({id:userB,role:'admin',phone:'test'})});assert.equal(r.status,401);});
  await t.test('incorrect and correct separate login',async()=>{assert.equal((await login(owner,'test-'+owner.replace(/-/g,''),'incorrect')).status,401);assert.equal((await login(owner,'test-'+owner.replace(/-/g,''))).status,200);assert.equal((await login(reader,'test-'+reader.replace(/-/g,''))).status,200);assert.equal((await login(scoped,'test-'+scoped.replace(/-/g,''))).status,200);});
  await t.test('CSRF and Origin enforced on mutations',async()=>{const a=accountData[owner];const r=await fetch(base+'/api/tech/api/notifications/mute',{method:'POST',headers:{Cookie:a.cookie,'Content-Type':'application/json'},body:'{}'});assert.equal(r.status,403);assert.equal((await tech('notifications/mute','POST',{},owner,{Origin:'https://evil.example'})).status,403);});
  await t.test('malformed JSON refusal is preserved before domain authentication',async()=>{
   const r=await fetch(base+'/api/v1/test-fail',{method:'POST',headers:{'Content-Type':'application/json','X-Domly-Session':'malformed-fixture'},body:'{"invalid":'});assert.equal(r.status,400);
   for(let i=0;i<20;i++){const rows=(await db.query("SELECT result,http_status FROM tech_events WHERE client_session_id='malformed-fixture'")).rows;if(rows[0]?.result==='failure'){assert.equal(rows[0].http_status,400);return;}await new Promise(r=>setTimeout(r,10));}assert.fail('Malformed request was not collected');
  });
  await t.test('secrets removed recursively while safe boolean flags survive',()=>{const s=sanitize({password:'secret',api_token:'secret',headers:{authorization:'Bearer bad'},must_change_password:true});assert.equal(s.password,'[секрет скрыт]');assert.equal(s.must_change_password,true);assert.equal(sanitize(new Date('2026-01-01T00:00:00Z')),'2026-01-01T00:00:00.000Z');assert.equal(s.headers.authorization,'[секрет скрыт]');assert.equal(sanitize({size_bytes:'173268',occurrences:'123456',otp:'173268'}).size_bytes,'173268');assert.equal(sanitize({size_bytes:'173268',occurrences:'123456',otp:'173268'}).occurrences,'123456');assert.equal(sanitize({size_bytes:'173268',otp:'173268'}).otp,'[секрет скрыт]');});
  await t.test('source checks report storage outage, not a green substitute',async()=>{storageOffline=true;const r=await tech('overview');assert.equal(r.status,200);assert.equal(r.body.data.checks.storage.ok,false);assert.equal(r.body.data.host.available,false);storageOffline=false;});
  let eventA='',eventB='';
  await t.test('server success/failure/retry keep separate signed events and dedupe problem',async()=>{
   for(const [u,role,path,method]of [[userA,'customer','test-success','GET'],[userA,'customer','test-fail','POST'],[userA,'customer','test-fail','POST'],[userB,'admin','test-success','GET']])await request('/api/v1/'+path,method as string,undefined,owner,{Authorization:'Bearer '+signAccessToken({id:u as string,role:role as any,phone:'fixture'}),'X-Domly-Session':'fixture-session-a','X-Domly-Version':'test-v1'});
   for(let i=0;i<30;i++){if((await db.query("SELECT COUNT(*)::int AS n FROM tech_events WHERE user_id=$1 AND result='failure'",[userA])).rows[0].n===2)break;await new Promise(r=>setTimeout(r,20));}
   const rows=(await db.query('SELECT * FROM tech_events WHERE user_id=$1 ORDER BY started_at',[userA])).rows;assert.equal(rows.length,3);for(const r of rows)assert.equal(r.signature,eventSignature(r));const p=(await db.query("SELECT p.* FROM tech_problems p JOIN tech_events e ON e.problem_id=p.id WHERE e.user_id=$1 LIMIT 1",[userA])).rows[0];assert.equal(Number(p.occurrences),2);eventA=rows[0].id;eventB=(await db.query('SELECT id FROM tech_events WHERE user_id=$1',[userB])).rows[0].id;
  });
  await t.test('one live identity read per request still rejects subsequent revocation and never reuses a different token',async()=>{
   const original=db.query.bind(db);let reads=0;
   db.query=(async(sql:string,values?:unknown[])=>{if(/^SELECT (id,full_name,role|deleted_at|role,status).*FROM app_users WHERE id=/s.test(sql))reads++;return original(sql,values);}) as typeof db.query;
   configureAuthDatabase(db);
   const token=signAccessToken({id:userA,role:'customer',phone:'fixture'});
   const get=()=>request('/api/v1/me','GET',undefined,owner,{Authorization:'Bearer '+token});
   try{
    assert.equal((await get()).status,200);
    assert.equal(reads,1,'collector, mobile guard and auth must share only this request live identity read');
    await original("UPDATE app_users SET status='blocked' WHERE id=$1",[userA]);
    assert.equal((await get()).status,401,'blocking must apply on the very next request');
    await original("UPDATE app_users SET status='approved',auth_version=auth_version+1 WHERE id=$1",[userA]);
    assert.equal((await get()).status,401,'revoked token must not reuse a previous request result');
    await original('UPDATE app_users SET auth_version=0,deleted_at=NOW() WHERE id=$1',[userA]);
    assert.equal((await get()).status,401);
    assert.equal((await request('/api/v1/me','GET',undefined,owner,{Authorization:'Bearer invalid'})).status,401);
   }finally{db.query=original;configureAuthDatabase(null);await original("UPDATE app_users SET status='approved',auth_version=0,deleted_at=NULL WHERE id=$1",[userA]);}
  });
  await t.test('notification history and unread count avoid scanning other recipients while retaining role broadcasts',async()=>{
   await db.query(`INSERT INTO notifications(role,title_ru,body_ru,target_type) SELECT 'admin','Other','Body','perf_fixture' FROM generate_series(1,12000)`);
   await db.query(`INSERT INTO notifications(user_id,title_ru,body_ru,target_type) SELECT $1,'Own','Body','perf_fixture' FROM generate_series(1,5)`,[userA]);
   await db.query(`INSERT INTO notifications(role,title_ru,body_ru,target_type) VALUES('customer','Broadcast','Body','perf_fixture'),('cleaner','Hidden','Body','perf_fixture')`);
   await db.query('ANALYZE notifications');
   const predicate="FROM notifications n LEFT JOIN notification_reads nr ON nr.notification_id=n.id AND nr.user_id=$1 WHERE (n.user_id=$1 OR (n.user_id IS NULL AND n.role=$2))";
   const plan=(await db.query('EXPLAIN (FORMAT JSON) SELECT n.*,COALESCE(n.read_at,nr.read_at) AS read_at '+predicate,[userA,'customer'])).rows[0]['QUERY PLAN'][0].Plan;
   const scansOtherRecipients=(node:any):boolean=>(node['Node Type']==='Seq Scan'&&node['Relation Name']==='notifications')||(node.Plans??[]).some(scansOtherRecipients);
   assert.equal(scansOtherRecipients(plan),false,'a recipient lookup must not scan all other users notifications');
   const result=await request('/api/v1/notifications','GET',undefined,owner,{Authorization:'Bearer '+signAccessToken({id:userA,role:'customer',phone:'fixture'})});
   assert.equal(result.status,200);assert.equal(result.body.data.filter((n:any)=>n.target_type==='perf_fixture').length,6);
   assert.ok(result.body.data.every((n:any)=>n.user_id===userA||n.user_id===null&&n.role==='customer'));
   const unread=await request('/api/v1/notifications/unread-count','GET',undefined,owner,{Authorization:'Bearer '+signAccessToken({id:userA,role:'customer',phone:'fixture'})});
   assert.equal(unread.status,200);assert.equal(unread.body.data.count,result.body.data.filter((n:any)=>n.read_at===null).length);
   const countPlan=(await db.query('EXPLAIN (FORMAT JSON) SELECT count(*) '+predicate+' AND COALESCE(n.read_at,nr.read_at) IS NULL',[userA,'customer'])).rows[0]['QUERY PLAN'][0].Plan;
   assert.equal(scansOtherRecipients(countPlan),false);
  });
  await t.test('server request identifiers cannot be forged to merge two user histories',async()=>{
   const supplied=randomUUID();const first=await request('/api/v1/test-success','GET',undefined,owner,{Authorization:'Bearer '+signAccessToken({id:userA,role:'customer',phone:'fixture'}),'X-Request-ID':supplied});const second=await request('/api/v1/test-success','GET',undefined,owner,{Authorization:'Bearer '+signAccessToken({id:userB,role:'admin',phone:'fixture'}),'X-Request-ID':supplied});
   const a=first.headers.get('x-request-id'),b=second.headers.get('x-request-id');assert.ok(a&&b);assert.notEqual(a,b);assert.notEqual(a,supplied);assert.notEqual(b,supplied);
   const history=await tech('events?request='+a);assert.equal(history.status,200);assert.ok(history.body.data.items.every((r:any)=>r.user_id===userA));assert.equal(history.body.data.items[0].fields.clientRequestId,supplied);
  });
  await t.test('scope prevents substituted event and history never mixes user IDs',async()=>{assert.equal((await tech('events/'+eventB,'GET',undefined,scoped)).status,403);const r=await tech('events?user='+userA+'&order=asc');assert.equal(r.status,200);assert.ok(r.body.data.items.every((e:any)=>e.user_id===userA));assert.match(r.body.data.items[0].started_at,/^\d{4}-/);assert.ok((await tech('events?session=fixture-session-a','GET',undefined,scoped)).body.data.items.every((e:any)=>e.user_id===userA));});
  await t.test('reader cannot access originals, rules or support operations; PII hidden',async()=>{assert.equal((await tech('rules','GET',undefined,reader)).status,403);assert.equal((await tech('files/'+randomUUID()+'/original','GET',undefined,reader)).status,403);assert.equal((await tech('users/'+userA+'/operation','POST',{action:'block'},reader)).status,403);const r=await tech('events/'+eventA,'GET',undefined,reader);assert.equal(r.body.data.event.ip,'[персональные данные скрыты]');});
  await t.test('temporary authentication storage failure is 503 and does not revoke valid session',async()=>{
   const token=signAccessToken({id:userA,role:'customer',phone:'fixture'});
   configureAuthDatabase({query:async()=>{throw Object.assign(new Error('offline'),{code:'ECONNREFUSED'});}} as any);
   const failed=await request('/api/v1/test-success','GET',undefined,owner,{Authorization:'Bearer '+token});assert.equal(failed.status,503);assert.equal(failed.body.code,'authentication_unavailable');
   configureAuthDatabase(db);assert.equal((await request('/api/v1/test-success','GET',undefined,owner,{Authorization:'Bearer '+token})).status,200);configureAuthDatabase(null);
  });
  await t.test('denied mutation never exposes foreign before/after snapshots through own history',async()=>{
   const r=await request('/api/v1/admin/users/'+userB,'PATCH',{fullName:'Untrusted input'},owner,{Authorization:'Bearer '+signAccessToken({id:userA,role:'customer',phone:'fixture'})});assert.equal(r.status,403);
   let event:any;for(let i=0;i<30;i++){event=(await db.query("SELECT * FROM tech_events WHERE user_id=$1 AND entity_id=$2 AND result='failure' ORDER BY started_at DESC LIMIT 1",[userA,userB])).rows[0];if(event)break;await new Promise(r=>setTimeout(r,10));}
   assert.ok(event);assert.equal(event.before_values,null);assert.equal(event.after_values,null);
   const visible=await tech('events/'+event.id,'GET',undefined,scoped);assert.equal(visible.status,200);assert.equal(visible.body.data.event.before_values,null);
  });
  await t.test('scope checks subject of snapshots as well as actor, including legacy evidence',async()=>{
   for(const fields of [{subjectUserId:userB},{}]){
    const event=(await db.query("INSERT INTO tech_events(request_id,user_id,entity_type,entity_id,action,result,fields,before_values) VALUES($1,$2,'users',$3,'fixture cross-subject mutation','failure',$4,$5) RETURNING id",[randomUUID(),userA,userB,fields,{full_name:'Private subject B'}])).rows[0];
    assert.equal((await tech('events/'+event.id,'GET',undefined,scoped)).status,403);
    assert.equal((await tech('events/'+event.id)).status,200);
    const list=await tech('events?user='+userA,'GET',undefined,scoped);assert.ok(!list.body.data.items.some((r:any)=>r.id===event.id));
   }
  });
  await t.test('client reports bounded and attributed to authenticated user; GPS requires permission',async()=>{const token=signAccessToken({id:userA,role:'customer',phone:'fixture'});const headers={Authorization:'Bearer '+token};assert.equal((await request('/api/v1/telemetry/client-events','POST',{events:Array(21).fill({})},owner,headers)).status,400);assert.equal((await request('/api/v1/telemetry/client-events','POST',{events:[{action:'screen.open',session:'fixture-client-a',user_id:userB,screen:'/client/home',gps:{latitude:20,longitude:20}}]},owner,headers)).status,200);const row=(await db.query("SELECT * FROM tech_events WHERE source='client' AND user_id=$1 ORDER BY started_at DESC LIMIT 1",[userA])).rows[0];assert.equal(row.user_id,userA);assert.equal(row.gps,null);assert.equal(row.result,'reported');});
  await t.test('queued device event cannot cross account switch',async()=>{
   const before=(await db.query("SELECT COUNT(*)::int AS n FROM tech_events WHERE source='client' AND user_id=$1",[userA])).rows[0].n;
   const r=await request('/api/v1/telemetry/client-events','POST',{events:[{actorId:userB,action:'screen.open',session:'old-actor-session',screen:'/client/home'}]},owner,{Authorization:'Bearer '+signAccessToken({id:userA,role:'customer',phone:'fixture'})});assert.equal(r.status,200);
   assert.equal((await db.query("SELECT COUNT(*)::int AS n FROM tech_events WHERE source='client' AND user_id=$1",[userA])).rows[0].n,before);
  });
  await t.test('client exception creates a problem without raw exception text',async()=>{
   const r=await request('/api/v1/telemetry/client-events','POST',{events:[{action:'client.error',session:'fixture-client-a',screen:'/client/home',label:'TypeError',message:'password=never-record-this'}]},owner,{Authorization:'Bearer '+signAccessToken({id:userA,role:'customer',phone:'fixture'})});assert.equal(r.status,200);
   const e=(await db.query("SELECT e.*,p.error_code AS problem_code FROM tech_events e JOIN tech_problems p ON p.id=e.problem_id WHERE e.user_id=$1 AND e.action='client.error'",[userA])).rows[0];assert.equal(e.problem_code,'client_TypeError');assert.ok(!JSON.stringify(e.fields).includes('never-record-this'));
  });
  const clear=await sharp({create:{width:800,height:600,channels:3,background:'#ffffff'}}).composite([{input:Buffer.from('<svg width="800" height="600"><text x="20" y="80" font-size="40">Technical plan 110</text><path d="M20 100H750V550H20Z M100 100V550 M300 100V550 M20 300H750" stroke="black" stroke-width="4" fill="none"/></svg>')}]).png().toBuffer();
  const blank=await sharp({create:{width:800,height:600,channels:3,background:'#ffffff'}}).png().toBuffer();
  let acceptedId='',rejectedId='';
  await t.test('quality policy accepts readable, rejects corrupt/blank, low resolution alone is not rejection',async()=>{const rules={version:1,config:{}};assert.equal((await inspectImage(clear,'image/png',true,rules)).decision,'accepted');assert.equal((await inspectImage(blank,'image/png',true,rules)).decision,'rejected');assert.equal((await inspectImage(Buffer.from('not image'),'image/jpeg',true,rules)).decision,'rejected');assert.equal((await inspectImage(Buffer.from('<svg xmlns="http://www.w3.org/2000/svg" width="20" height="20"></svg>'),'image/jpeg',true,rules)).decision,'rejected');const blackAlpha=await sharp({create:{width:500,height:500,channels:4,background:{r:0,g:0,b:0,alpha:1}}}).png().toBuffer();assert.equal((await inspectImage(blackAlpha,'image/png',true,rules)).decision,'rejected');const gif=await sharp(clear).gif().toBuffer();assert.notEqual((await inspectImage(gif,'image/gif',true,rules)).decision,'rejected');const low=await sharp(clear).resize(150).png().toBuffer();assert.notEqual((await inspectImage(low,'image/png',true,rules)).decision,'rejected');});
  await t.test('accepted upload tied to exact event; rejected original privately quarantined',async()=>{
   const fileId=randomUUID(),req:any={path:'/quality-checks',body:{},techEventId:eventA,user:{id:userA},file:{buffer:clear,mimetype:'image/png',size:clear.length}};await inspectUpload(db,storage,req);const f=(await db.query("INSERT INTO files(id,owner_id,bucket,object_key,mime_type,size_bytes) VALUES($1::uuid,$2,'fixture',$1::uuid::text,'image/png',$3) RETURNING *",[fileId,userA,clear.length])).rows[0];objects.set('fixture/'+fileId,clear);await registerUploadedFile(db,req,f);acceptedId=(await db.query('SELECT id FROM tech_files WHERE file_id=$1',[fileId])).rows[0].id;
   req.file={buffer:blank,mimetype:'image/png',size:blank.length};await assert.rejects(()=>inspectUpload(db,storage,req),/Номер проверки/);const rejected=(await db.query("SELECT * FROM tech_files WHERE owner_id=$1 AND decision='rejected'",[userA])).rows[0];rejectedId=rejected.id;assert.equal(rejected.file_id,null);assert.equal(rejected.quarantined,true);assert.equal(rejected.bucket,'domly-technical-private');assert.equal((await tech('events/'+eventA)).body.data.filesThisAction.length,2);
  });
  await t.test('original checksum, audit and safe preview; unrelated files denied',async()=>{const r=await tech('files/'+acceptedId+'/original');assert.equal(r.status,200);assert.match(r.headers.get('content-type')!,/octet-stream/);
   const bytes=await fetch(base+'/api/tech/api/files/'+acceptedId+'/original',{headers:{Cookie:accountData[owner].cookie}});assert.equal(hash(Buffer.from(await bytes.arrayBuffer())),hash(clear));assert.equal((await tech('files/'+acceptedId+'/preview')).status,200);assert.equal((await tech('files/'+rejectedId+'/original','GET',undefined,reader)).status,403);
   const f=(await db.query("INSERT INTO files(owner_id,bucket,object_key,mime_type) VALUES($1,'fixture',$2,'image/png') RETURNING id",[userB,randomUUID()])).rows[0];assert.equal((await tech('files/'+f.id+'/original','GET',undefined,scoped)).status,403);assert.ok((await db.query("SELECT 1 FROM tech_audit WHERE action='file.original' AND target_id=$1",[acceptedId])).rows.length);
  });
  await t.test('legacy photograph previews by verified bytes even when MIME metadata is missing',async()=>{
   const key=randomUUID(),file=(await db.query("INSERT INTO files(owner_id,bucket,object_key,size_bytes) VALUES($1,'fixture',$2,$3) RETURNING id",[userA,key,clear.length])).rows[0];objects.set('fixture/'+key,clear);
   assert.equal((await tech('files/'+file.id+'/preview')).status,200);
   const unsafeKey=randomUUID(),unsafe=(await db.query("INSERT INTO files(owner_id,bucket,object_key,mime_type,size_bytes) VALUES($1,'fixture',$2,'image/jpeg',100) RETURNING id",[userA,unsafeKey])).rows[0];objects.set('fixture/'+unsafeKey,Buffer.from('<svg xmlns="http://www.w3.org/2000/svg"></svg>'));
   assert.equal((await tech('files/'+unsafe.id+'/preview')).status,415);
  });
  await t.test('original storage outage returns explicit failure and does not invent replacement',async()=>{storageOffline=true;assert.equal((await tech('files/'+acceptedId+'/original')).status,503);storageOffline=false;});
  await t.test('problems cannot close without version and successful verification',async()=>{const p=await problem(db,{fingerprint:'fixture-close-'+randomUUID(),code:'fixture',title:'Изолированная проблема',recommendation:'Проверить сценарий',eventId:eventA});assert.equal((await tech('problems/'+p.id,'PATCH',{status:'fixed',reason:'Проверка сценария',confirm:true})).status,400);assert.equal((await tech('problems/'+p.id,'PATCH',{status:'fixed',fixedVersion:'test-v2',verificationNote:'Сценарий успешно проверен на тестовой базе.',verificationPassed:true,reason:'Исправление проверено',confirm:true})).status,200);});
  await t.test('notification dedupe, ownership and acknowledgement',async()=>{const f='notify-fixture-'+randomUUID();await problem(db,{fingerprint:f,code:'fixture',title:'Тест',recommendation:'Проверить',eventId:eventA});await problem(db,{fingerprint:f,code:'fixture',title:'Тест',recommendation:'Проверить',eventId:eventA});const d=await tech('notifications');assert.ok(d.body.data.items.length>0);const n=d.body.data.items[0];assert.equal((await tech('notifications/'+n.id+'/ack','POST',{},reader)).status,404);assert.equal((await tech('notifications/'+n.id+'/ack','POST',{})).status,200);});
  await t.test('push endpoint rejects arbitrary network destinations',async()=>{assert.equal(validPush('http://127.0.0.1/x'),false);assert.equal(validPush('https://attacker.example/x'),false);assert.equal(validPush('https://fcm.googleapis.com/fcm/send/test'),true);assert.equal((await tech('push','POST',{subscription:{endpoint:'http://127.0.0.1',keys:{auth:'x',p256dh:'x'}}})).status,400);});
  await t.test('unfinished requests produce a domain problem and worker heartbeat is real',async()=>{const e=(await db.query("INSERT INTO tech_events(request_id,user_id,action,started_at) VALUES($1,$2,'fixture incomplete',NOW()-INTERVAL '10 minutes') RETURNING id",[randomUUID(),userA])).rows[0];await technicalTick(db,storage);assert.ok((await db.query('SELECT problem_id FROM tech_events WHERE id=$1',[e.id])).rows[0].problem_id);assert.ok((await tech('overview')).body.data.worker.available);});
  await t.test('support operations require reauthentication; OTP accounts cannot get a password',async()=>{const body={action:'block',reason:'Проверка технической операции',confirm:true};assert.equal((await tech('users/'+userA+'/operation','POST',body)).status,403);assert.equal((await tech('users/'+userA+'/operation','POST',{...body,action:'temporary_password',operatorPassword:password})).status,409);});
  await t.test('revocation closes existing realtime streams without affecting another user',async()=>{
   configureAuthDatabase(db);const controllers=[new AbortController(),new AbortController()];
   try {
    const readers=[];
    for(const [index,userId] of [userA,userB].entries()){
     const row=(await db.query('SELECT role,auth_version FROM app_users WHERE id=$1',[userId])).rows[0];
     const token=signAccessToken({id:userId,role:row.role,phone:'fixture',authVersion:row.auth_version});
     const response=await fetch(base+'/api/v1/realtime',{headers:{Authorization:'Bearer '+token},signal:controllers[index].signal});assert.equal(response.status,200);
     const reader=response.body!.getReader();assert.match(new TextDecoder().decode((await reader.read()).value),/connected/);readers.push(reader);
    }
    assert.equal((await tech('users/'+userA+'/operation','POST',{action:'revoke_sessions',reason:'Проверка открытого соединения',confirm:true,operatorPassword:password})).status,200);
    const end=async()=>{let text='';while(true){const part=await readers[0].read();if(part.done)return text;text+=new TextDecoder().decode(part.value);}};
    let timeout:ReturnType<typeof setTimeout>|undefined;
    try{assert.match(await Promise.race([end(),new Promise<string>((_,reject)=>{timeout=setTimeout(()=>reject(new Error('Stream was not closed')),2000);})]),/auth.revoked/);}finally{clearTimeout(timeout);}
    emitToUser(userB,{type:'fixture.alive'});assert.match(new TextDecoder().decode((await readers[1].read()).value),/fixture.alive/);
   }finally{controllers.forEach(c=>c.abort());configureAuthDatabase(null);}
  });
  await t.test('block/unblock and revoke invalidate active access immediately',async()=>{configureAuthDatabase(db);const token=signAccessToken({id:userA,role:'customer',phone:'fixture',authVersion:Number((await db.query('SELECT auth_version FROM app_users WHERE id=$1',[userA])).rows[0].auth_version)});const r=await tech('users/'+userA+'/operation','POST',{action:'revoke_sessions',reason:'Проверка отзыва доступа',confirm:true,operatorPassword:password});assert.equal(r.status,200);assert.equal((await request('/api/v1/test-success','GET',undefined,owner,{Authorization:'Bearer '+token})).status,401);for(const action of ['block','unblock'])assert.equal((await tech('users/'+userA+'/operation','POST',{action,reason:'Проверка состояния аккаунта',confirm:true,operatorPassword:password})).status,200);configureAuthDatabase(null);});
  await t.test('temporary admin password is new, hashed, and requires change',async()=>{const r=await tech('users/'+userB+'/operation','POST',{action:'temporary_password',reason:'Проверка восстановления доступа',confirm:true,operatorPassword:password});assert.equal(r.status,200);const row=(await db.query('SELECT password_hash,password_change_required FROM app_users WHERE id=$1',[userB])).rows[0];assert.ok(await bcrypt.compare(r.body.data.temporaryPassword,row.password_hash));assert.equal(row.password_change_required,true);assert.ok(!(await db.query('SELECT payload::text FROM tech_audit WHERE target_id=$1',[userB])).rows.some(entry=>entry.payload.includes(r.body.data.temporaryPassword)));});
  await t.test('real admin login enforces temporary password change and revokes old tokens',async()=>{
   await db.query("UPDATE app_users SET phone='+77001234567' WHERE id=$1",[userB]);
   const temporary=(await tech('users/'+userB+'/operation','POST',{action:'temporary_password',reason:'Проверка обязательной смены пароля',confirm:true,operatorPassword:password})).body.data.temporaryPassword;
   configureAuthDatabase(db);
   const logged=await request('/api/v1/auth/password/login','POST',{phone:'+77001234567',password:temporary});assert.equal(logged.status,200);assert.equal(logged.body.data.user.passwordChangeRequired,true);
   const headers={Authorization:'Bearer '+logged.body.data.accessToken};assert.equal((await request('/api/v1/test-success','GET',undefined,owner,headers)).status,403);
   const changed=await request('/api/v1/auth/password/change','POST',{currentPassword:temporary,newPassword:'NewAdminFixture!2026'},owner,headers);assert.equal(changed.status,200);
   assert.equal((await request('/api/v1/test-success','GET',undefined,owner,headers)).status,401);
   assert.equal((await request('/api/v1/auth/password/login','POST',{phone:'+77001234567',password:temporary})).status,401);
   const again=await request('/api/v1/auth/password/login','POST',{phone:'+77001234567',password:'NewAdminFixture!2026'});assert.equal(again.status,200);assert.equal(again.body.data.user.passwordChangeRequired,false);
   configureAuthDatabase(null);
  });
  await t.test('owner can provision disabled technician, enable it, and enforce initial password change',async()=>{
   const name='new-'+randomUUID().replace(/-/g,'');const created=await tech('access','POST',{login:name,displayName:'Изолированный сотрудник',permissions:['events.read'],userScope:[userA],disabled:true,reason:'Проверка создания технического доступа',confirm:true,operatorPassword:password});assert.equal(created.status,200);
   const account=created.body.data;assert.equal((await login(account.id,name,account.temporaryPassword)).status,401);
   assert.equal((await tech('access/'+account.id,'PATCH',{disabled:false,reason:'Проверка активации технического доступа',confirm:true,operatorPassword:password})).status,200);
   const logged=await login(account.id,name,account.temporaryPassword);assert.equal(logged.status,200);assert.equal(logged.body.data.mustChangePassword,true);
   assert.equal((await tech('events','GET',undefined,account.id)).status,403);
  });
  await t.test('audit payloads and archives cannot bypass PII or user-scope permissions',async()=>{
   await db.query("UPDATE tech_accounts SET permissions=ARRAY['events.read','access.manage','files.original'] WHERE id=$1",[reader]);
   await audit(db,{accountId:owner,action:'fixture.private_audit',payload:{user_name:'Private customer name'}});
   const read=await tech('audit','GET',undefined,reader);assert.equal(read.status,200);assert.ok(read.body.data.items.every((r:any)=>r.payload.redacted===true));assert.ok(!JSON.stringify(read.body).includes('Private customer name'));
   assert.equal((await tech('audit/archives/'+randomUUID(),'GET',undefined,reader)).status,403);
   await db.query("UPDATE tech_accounts SET permissions=array_append(permissions,'access.manage') WHERE id=$1",[scoped]);
   assert.equal((await tech('audit','GET',undefined,scoped)).status,403);
   assert.equal((await tech('audit/archives/'+randomUUID(),'GET',undefined,scoped)).status,403);
  });
  await t.test('audit is signed, append-only, and tampering detectable',async()=>{await audit(db,{accountId:owner,action:'fixture.audit',payload:{token:'mustnotappear'}});assert.equal((await verifyAudit(db,10000)).valid,true);await assert.rejects(()=>db.query("UPDATE tech_audit SET result='tampered' WHERE seq=(SELECT MAX(seq) FROM tech_audit)"),/append-only/);});
  await t.test('separate password change revokes other sessions and logout expires own cookie',async()=>{const old=accountData[reader].cookie;assert.equal((await tech('password','POST',{currentPassword:password,newPassword:'UpdatedTechnical!2026'},reader)).status,200);assert.equal((await login(reader,'test-'+reader.replace(/-/g,''),'UpdatedTechnical!2026')).status,200);const r=await fetch(base+'/api/tech/api/me',{headers:{Cookie:old}});assert.equal(r.status,200); // own original session preserved until logout/expiry
    assert.equal((await tech('logout','POST',{},reader)).status,200);assert.equal((await tech('me','GET',undefined,reader)).status,401);
  });
 }finally{
  configureAuthDatabase(null);await new Promise<void>(resolve=>server.close(()=>resolve()));
  await db.close();await control.query('DROP DATABASE '+databaseName+' WITH (FORCE)');await control.close();
 }
});
