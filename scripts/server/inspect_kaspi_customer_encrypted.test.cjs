const test=require('node:test'),assert=require('node:assert/strict'),vm=require('node:vm'),fs=require('node:fs'),crypto=require('node:crypto');
const source=fs.readFileSync(__dirname+'/inspect_kaspi_customer_encrypted.cjs','utf8');
test('invoice diagnosis only reads and produces encrypted evidence',async()=>{
 const pair=crypto.generateKeyPairSync('rsa',{modulusLength:2048});let output='',error='';const calls=[];
 class Pool{async connect(){return {release(){},query:async(sql,args)=>{
  assert.match(sql,/^(SELECT|BEGIN READ ONLY|ROLLBACK)/);
  if(sql.includes('FROM app_users'))return {rows:[{id:'private-fixture',full_name:'Madina fixture',phone_suffix:'0000'}]};
  if(sql.includes('FROM payments p'))return {rows:[{id:'payment-fixture',status:'invoice_requested',amount:100}]};
  if(sql.includes('FROM moon_ai_outbox'))return {rows:[{payment_id:'payment-fixture',provider_thread_id:'thread-fixture',state:'sent'}]};
  return {rows:[]};
 }};}async end(){}}
 const ctx={require:n=>n==='pg'?{Pool}:require(n),Buffer,AbortSignal,
 process:{env:{TARGET_NAME_B64:Buffer.from('Мадина').toString('base64'),REPORT_PUBLIC_KEY_B64:pair.publicKey.export({type:'spki',format:'der'}).toString('base64'),MOON_AI_REST_API_KEY:'fixture-key'},stdout:{write:s=>output+=s}},console:{error:s=>error+=s},
 fetch:async(url,init)=>{calls.push({url,init});assert.equal(init.method,'GET');return {status:200,json:async()=>({results:[{message_type:'text',data:{text:'Invoice could not be issued: fixture error'}}]})};}};
 await vm.runInNewContext(source,ctx);assert.equal(error,'');assert.equal(calls.length,1);
 assert.equal(output.includes('Madina'),false);assert.equal(output.includes('private-fixture'),false);
 const p=JSON.parse(output);const key=crypto.privateDecrypt({key:pair.privateKey,padding:crypto.constants.RSA_PKCS1_OAEP_PADDING,oaepHash:'sha256'},Buffer.from(p.key,'base64'));
 const d=crypto.createDecipheriv('aes-256-gcm',key,Buffer.from(p.iv,'base64'));d.setAuthTag(Buffer.from(p.tag,'base64'));
 const r=JSON.parse(Buffer.concat([d.update(Buffer.from(p.data,'base64')),d.final()]));
 assert.equal(r.payments[0].status,'invoice_requested');assert.match(r.upstream[0].messages[0].data,/fixture error/);assert.equal(r.matches[0].id,undefined);
});
