const test=require('node:test'),assert=require('node:assert/strict'),crypto=require('node:crypto');
const {parseEnv,liveValues,replaceEnv,decrypt,seal}=require('./configure_bcc_live.cjs');
const fixture={BCC_TERMINAL_ID:'90040001',BCC_MERCHANT_ID:'FIXTURE',BCC_PRIVATE_KEY:'1234567890ABCDEF1234567890ABCDEF',BCC_NOTIFY_USER:'fixture-user',BCC_NOTIFY_PASSWORD:'fixture-password-123456',callbackRegistered:true};
test('live configuration rejects sandbox keys, terminal and newline injection',()=>{
 for(const changed of [{BCC_TERMINAL_ID:'88888881'},{BCC_PRIVATE_KEY:'6BB0AC02E47BDF73D98FEB777F3B5294'},{BCC_MERCHANT_ID:'bad\nSECRET=value'}])assert.throws(()=>liveValues({...fixture,...changed},{}));
 const values=liveValues({...fixture,BCC_NOTIFY_USER:undefined,BCC_NOTIFY_PASSWORD:undefined},{BCC_NOTIFY_USER:'existing-user',BCC_NOTIFY_PASSWORD:'existing-password'});
 assert.equal(values.BCC_MODE,'live');assert.equal(values.BCC_GATEWAY_URL,'https://3dsecure.bcc.kz/webview');
 assert.equal(values.BCC_NOTIFY_PASSWORD,'existing-password');assert.ok(values.BCC_NOTIFY_URL.includes(':443/'));
 assert.throws(()=>liveValues(fixture,{PUBLIC_API_URL:'http://domly.kz'}));
 assert.throws(()=>liveValues({...fixture,BCC_NOTIFY_USER:undefined,BCC_NOTIFY_PASSWORD:undefined},{}));
 assert.throws(()=>liveValues({...fixture,BCC_NOTIFY_PASSWORD:undefined},{}));
});
test('only BCC fields change and unrelated provider configuration survives',()=>{
 const before='MOON_AI_TOKEN=preserve-me\nBCC_MODE=test\n# keep comment\n';
 const text=replaceEnv(before,liveValues(fixture,{})),values=parseEnv(text);
 assert.equal(values.MOON_AI_TOKEN,'preserve-me');assert.equal(values.BCC_MODE,'live');assert.ok(text.includes('# keep comment'));
 assert.equal((text.match(/^BCC_MODE=/gm)||[]).length,1);
 assert.throws(()=>replaceEnv(before,{BCC_PRIVATE_KEY:'bad\nKEY=secret'}));
});
test('encrypted workflow payload and encrypted report roundtrip without plaintext values',()=>{
 const pair=crypto.generateKeyPairSync('rsa',{modulusLength:4096});
 const publicKey=pair.publicKey.export({type:'spki',format:'der'}).toString('base64');
 const envelope=seal(publicKey,fixture);
 assert.ok(!envelope.includes(fixture.BCC_PRIVATE_KEY));assert.deepEqual(decrypt(pair.privateKey,envelope),fixture);
 const other=crypto.generateKeyPairSync('rsa',{modulusLength:2048});assert.throws(()=>decrypt(other.privateKey,envelope));
});
test('bank rejection preserves configuration; activation backs up and rollback preserves later unrelated edits',async()=>{
 const fs=require('node:fs'),os=require('node:os'),path=require('node:path');
 const {run}=require('./configure_bcc_live.cjs'),root=fs.mkdtempSync(path.join(os.tmpdir(),'bcc-live-test-'));
 const pair=crypto.generateKeyPairSync('rsa',{modulusLength:4096}),pub=pair.publicKey.export({type:'spki',format:'der'}).toString('base64');
 fs.mkdirSync(path.join(root,'shared/bcc-live'),{recursive:true});fs.mkdirSync(path.join(root,'current/backend'),{recursive:true});
 const old='BCC_MODE=test\nMOON_AI_TOKEN=unchanged\n';
 for(const file of ['shared/backend.env','current/backend/.env'])fs.writeFileSync(path.join(root,file),old);
 fs.writeFileSync(path.join(root,'shared/bcc-live/transfer-private.pem'),pair.privateKey.export({type:'pkcs8',format:'pem'}));
 fs.writeFileSync(path.join(root,'envelope'),seal(pub,fixture));fs.writeFileSync(path.join(root,'report-key'),pub);
 const services={env:{},bccSign:()=> 'fixture-signature',bccNonce:()=> 'fixture',bccTimestamp:()=> '20300101000000',postBccFields:async()=>({ACTION:'3',RC:'-22'})};
 const log=console.log;console.log=()=>{};
 try{
  await assert.rejects(()=>run(root,'apply',path.join(root,'envelope'),path.join(root,'report-key'),services));
  assert.equal(fs.readFileSync(path.join(root,'shared/backend.env'),'utf8'),old);
  services.postBccFields=async()=>({ACTION:'3',RC:'78'});
  fs.writeFileSync(path.join(root,'envelope'),seal(pub,{...fixture,callbackRegistered:false}));
  await assert.rejects(()=>run(root,'apply',path.join(root,'envelope'),path.join(root,'report-key'),services));
  assert.equal(fs.readFileSync(path.join(root,'shared/backend.env'),'utf8'),old);
  fs.writeFileSync(path.join(root,'envelope'),seal(pub,fixture));
  await run(root,'apply',path.join(root,'envelope'),path.join(root,'report-key'),services);
  assert.equal(parseEnv(fs.readFileSync(path.join(root,'shared/backend.env'),'utf8')).BCC_MODE,'live');
  assert.equal(fs.statSync(path.join(root,'shared/backend.env')).mode&0o777,0o600);
  assert.equal(fs.readFileSync(path.join(root,'shared/bcc-live/previous.env'),'utf8'),old);
  assert.equal(fs.existsSync(path.join(root,'shared/bcc-live/transfer-private.pem')),false);
  fs.appendFileSync(path.join(root,'shared/backend.env'),'NEW_SETTING=preserve\n');
  await run(root,'rollback');
  const restored=parseEnv(fs.readFileSync(path.join(root,'shared/backend.env'),'utf8'));
  assert.equal(restored.BCC_MODE,'test');assert.equal(restored.MOON_AI_TOKEN,'unchanged');assert.equal(restored.NEW_SETTING,'preserve');
 }finally{console.log=log;fs.rmSync(root,{recursive:true,force:true});}
});
