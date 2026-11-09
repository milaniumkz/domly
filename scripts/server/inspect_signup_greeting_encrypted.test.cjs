const test=require('node:test');
const assert=require('node:assert/strict');
const fs=require('node:fs');
const vm=require('node:vm');
const crypto=require('node:crypto');
const source=fs.readFileSync(__dirname+'/inspect_signup_greeting_encrypted.cjs','utf8');
test('support report reads one account, never writes or exposes plaintext, and decrypts with the private key',async()=>{
 const pair=crypto.generateKeyPairSync('rsa',{modulusLength:2048});
 const publicKey=pair.publicKey.export({type:'spki',format:'der'}).toString('base64');
 const queries=[];let output='',errors='',released=false,ended=false;
 const fakeId='fixture-account-secret';
 const client={release(){released=true;},async query(sql,values){
  queries.push({sql,values});assert.match(sql,/^(SELECT|BEGIN READ ONLY|ROLLBACK)/);
  if(sql.includes('FROM app_users'))return {rows:[{id:fakeId,registered_at:'2026-11-03T05:00:00Z',status:'active',deleted:false,is_phone_verified:true,whatsapp_opt_out:false}]};
  if(sql.includes('SELECT kind,state'))return {rows:[{kind:'inactive_signup',state:'cancelled',created_at:'2026-11-03T05:00:00Z',failure_code:null}]};
  if(sql.includes('SELECT MIN'))return {rows:[{first_checkout_at:'2026-11-03T05:01:00Z',first_assistant_message_at:null}]};
  return {rows:[]};
 }};
 class Pool{async connect(){return client;}async end(){ended=true;}}
 const processMock={env:{DATABASE_URL:'fixture-only',TARGET_PHONE_SHA256:'a'.repeat(64),REPORT_PUBLIC_KEY_B64:publicKey},stdout:{write(s){output+=s;}}};
 await vm.runInNewContext(source,{require:n=>n==='pg'?{Pool}:require(n),Buffer,process:processMock,console:{error(s){errors+=s;}}});
 assert.equal(errors,'');assert.equal(processMock.exitCode,undefined);assert.ok(released&&ended);
 assert.ok(queries.every(q=>!q.sql.includes('SELECT *')));
 assert.equal(output.includes(fakeId),false);assert.equal(output.includes('2026-11-03'),false);assert.equal(output.includes('cancelled'),false);
 const envelope=JSON.parse(output);
 const key=crypto.privateDecrypt({key:pair.privateKey,padding:crypto.constants.RSA_PKCS1_OAEP_PADDING,oaepHash:'sha256'},Buffer.from(envelope.key,'base64'));
 const decipher=crypto.createDecipheriv('aes-256-gcm',key,Buffer.from(envelope.iv,'base64'));
 decipher.setAuthTag(Buffer.from(envelope.tag,'base64'));
 const plain=Buffer.concat([decipher.update(Buffer.from(envelope.data,'base64')),decipher.final()]).toString();
 assert.equal(plain.includes(fakeId),false);
 const report=JSON.parse(plain);assert.equal(report.accountFound,true);
 assert.equal(report.accounts[0].entries[0].state,'cancelled');assert.equal(report.accounts[0].activity.first_checkout_at,'2026-11-03T05:01:00Z');
});
