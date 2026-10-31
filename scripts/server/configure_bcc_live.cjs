'use strict';
// No plaintext credentials are accepted as workflow inputs or printed to logs.
const fs=require('node:fs'),path=require('node:path'),crypto=require('node:crypto');
const GATEWAY='https://3dsecure.bcc.kz/webview';
function parseEnv(text){const out={};for(const line of text.split(/\r?\n/)){const m=line.match(/^([A-Z_][A-Z0-9_]*)=(.*)$/);if(m)out[m[1]]=m[2].replace(/^(['"])(.*)\1$/,'$2');}return out;}
function liveValues(input,previous){
 const required=['BCC_MERCHANT_ID','BCC_TERMINAL_ID','BCC_PRIVATE_KEY'];
 if(!input||typeof input!=='object'||required.some(k=>typeof input[k]!=='string'||!input[k]))throw Error('Incomplete BCC credentials');
 if(!/^\d{8}$/.test(input.BCC_TERMINAL_ID)||['88888881','88888888'].includes(input.BCC_TERMINAL_ID))throw Error('A live terminal is required');
 if(!/^[0-9A-Fa-f]{32}$/.test(input.BCC_PRIVATE_KEY)||input.BCC_PRIVATE_KEY.toUpperCase()==='6BB0AC02E47BDF73D98FEB777F3B5294')throw Error('A live MAC key is required');
 if(!/^[A-Za-z0-9_-]{1,64}$/.test(input.BCC_MERCHANT_ID))throw Error('Invalid merchant identifier');
 if(Boolean(input.BCC_NOTIFY_USER)!==Boolean(input.BCC_NOTIFY_PASSWORD))throw Error('Both callback credentials are required');
 const notifyUser=input.BCC_NOTIFY_USER||previous.BCC_NOTIFY_USER;
 const notifyPassword=input.BCC_NOTIFY_PASSWORD||previous.BCC_NOTIFY_PASSWORD;
 if(!notifyUser||!notifyPassword)throw Error('Configure bank callback credentials before activation');
 if(input.BCC_NOTIFY_USER&&!/^[A-Za-z0-9._-]{1,64}$/.test(notifyUser))throw Error('Invalid callback username');
 if(input.BCC_NOTIFY_PASSWORD&&!/^[A-Za-z0-9._~-]{16,128}$/.test(notifyPassword))throw Error('Invalid callback password format');
 const origin=new URL(previous.PUBLIC_API_URL||'https://domly.kz');
 if(origin.protocol!=='https:'||origin.hostname!=='domly.kz')throw Error('Unexpected application origin');
 const name=input.BCC_MERCHANT_NAME||'DOMLY';if(!/^[A-Za-z0-9 ._-]{1,64}$/.test(name))throw Error('Invalid merchant name');
 return {BCC_MODE:'live',BCC_GATEWAY_URL:GATEWAY,BCC_MERCHANT_ID:input.BCC_MERCHANT_ID,BCC_TERMINAL_ID:input.BCC_TERMINAL_ID,BCC_MERCHANT_NAME:name,BCC_PRIVATE_KEY:input.BCC_PRIVATE_KEY.toUpperCase(),BCC_NOTIFY_URL:'https://domly.kz:443/api/v1/payments/bcc/webhook',BCC_RETURN_URL:'https://domly.kz/customer/#/client/payment-history',BCC_NOTIFY_USER:notifyUser,BCC_NOTIFY_PASSWORD:notifyPassword};
}
function replaceEnv(text,values){return text.split(/\r?\n/).filter(line=>!Object.hasOwn(values,line.split('=')[0])).join('\n').replace(/\n*$/,'\n')+Object.entries(values).map(([k,v])=>{if(/[\r\n]/.test(v))throw Error('Invalid multiline configuration');return k+'='+v;}).join('\n')+'\n';}
function atomicWrite(file,text){fs.mkdirSync(path.dirname(file),{recursive:true,mode:0o700});const temp=file+'.bcc-live.tmp';fs.writeFileSync(temp,text,{mode:0o600});if(fs.existsSync(file)){const owner=fs.statSync(file);fs.chownSync(temp,owner.uid,owner.gid);}fs.renameSync(temp,file);fs.chmodSync(file,0o600);}
function decrypt(privateKey,envelope){return JSON.parse(crypto.privateDecrypt({key:privateKey,oaepHash:'sha256',padding:crypto.constants.RSA_PKCS1_OAEP_PADDING},Buffer.from(envelope.trim(),'base64')).toString());}
function seal(publicKey,value){return crypto.publicEncrypt({key:crypto.createPublicKey({key:Buffer.from(publicKey,'base64'),format:'der',type:'spki'}),oaepHash:'sha256',padding:crypto.constants.RSA_PKCS1_OAEP_PADDING},Buffer.from(JSON.stringify(value))).toString('base64');}
async function run(base,action,inputFile,reportKeyFile,services){
 if(!path.isAbsolute(base))throw Error('An absolute deployment root is required');
 const secure=path.join(base,'shared','bcc-live'),shared=path.join(base,'shared/backend.env'),current=path.join(base,'current/backend/.env');
 const original=fs.readFileSync(fs.existsSync(shared)?shared:current,'utf8'),previous=parseEnv(original);
 fs.mkdirSync(secure,{recursive:true,mode:0o700});fs.chmodSync(secure,0o700);
 const keyFile=path.join(secure,'transfer-private.pem');
 if(action==='prepare'){
  if(!fs.existsSync(keyFile)){const pair=crypto.generateKeyPairSync('rsa',{modulusLength:4096});atomicWrite(keyFile,pair.privateKey.export({type:'pkcs8',format:'pem'}));}
  const key=crypto.createPublicKey(fs.readFileSync(keyFile)).export({type:'spki',format:'der'}).toString('base64');
  console.log('BCC_TRANSFER_PUBLIC_KEY='+key);
  console.log(JSON.stringify({mode:previous.BCC_MODE||'disabled',callbackCredentialsPresent:Boolean(previous.BCC_NOTIFY_USER&&previous.BCC_NOTIFY_PASSWORD)}));return;
 }
 if(action==='rollback'){
  const saved=path.join(secure,'previous.env');if(!fs.existsSync(saved))throw Error('No saved BCC configuration to restore');
  const snapshot=parseEnv(fs.readFileSync(saved,'utf8'));
  const keys=['BCC_MODE','BCC_GATEWAY_URL','BCC_MERCHANT_ID','BCC_TERMINAL_ID','BCC_MERCHANT_NAME','BCC_PRIVATE_KEY','BCC_NOTIFY_URL','BCC_RETURN_URL','BCC_NOTIFY_USER','BCC_NOTIFY_PASSWORD'];
  const restored=replaceEnv(original,Object.fromEntries(keys.map(key=>[key,snapshot[key]??(key==='BCC_MODE'?'disabled':'')])));
  for(const target of [shared,current])atomicWrite(target,restored);
  console.log('Previous configuration restored.');return;
 }
 if(!['probe','apply'].includes(action))throw Error('Unsupported BCC operation');
 const input=decrypt(fs.readFileSync(keyFile),fs.readFileSync(inputFile,'utf8'));
 if(action==='apply'&&input.callbackRegistered!==true)throw Error('Bank callback registration must be confirmed before activation');
 const values=liveValues(input,previous);
 // Use the installed, tested gateway implementation, without creating payments or charging a card.
 const apiRoot='/app/dist';
 const {env}=services||require(path.join(apiRoot,'common/env.js'));
 Object.assign(env,{bccMode:'live',bccGatewayUrl:GATEWAY,bccMerchantId:values.BCC_MERCHANT_ID,bccTerminalId:values.BCC_TERMINAL_ID,bccPrivateKey:values.BCC_PRIVATE_KEY,bccMerchantName:values.BCC_MERCHANT_NAME,bccNotifyUrl:values.BCC_NOTIFY_URL,bccNotifyUser:values.BCC_NOTIFY_USER,bccNotifyPassword:values.BCC_NOTIFY_PASSWORD});
 const {bccSign,bccTimestamp,bccNonce,postBccFields}=services||require(path.join(apiRoot,'modules/bcc.js'));
 const reference='98'+Date.now();
 const query={ORDER:reference,TERMINAL:values.BCC_TERMINAL_ID,TIMESTAMP:bccTimestamp(),TRTYPE:'90',TRAN_TRTYPE:'1',LANG:'ru',MERCH_GMT:'0',NONCE:bccNonce()};
 const result=await postBccFields({...query,P_SIGN:bccSign(query,values.BCC_PRIVATE_KEY)});
 console.log(JSON.stringify({bankReached:true,operation:'status-of-nonexistent-payment',rc:String(result.RC).replace(/[^0-9-]/g,''),charged:false}));
 const allowedMissing=['-15','-23','-24','78'];
 if(!allowedMissing.includes(String(result.RC)))throw Error('Bank preflight did not confirm a valid request; RC='+String(result.RC).replace(/[^0-9-]/g,''));
 if(action==='probe')return;
 const reportKey=reportKeyFile?fs.readFileSync(reportKeyFile,'utf8').trim():'';
 if(!reportKey)throw Error('A public report encryption key is required before activation');
 const report={url:values.BCC_NOTIFY_URL,method:'POST',port:443,tls:'1.2',terminal:values.BCC_TERMINAL_ID,username:values.BCC_NOTIFY_USER,password:values.BCC_NOTIFY_PASSWORD};
 const sealedReport=seal(reportKey,report);
 const backup=path.join(base,'backups','bcc-live-'+new Date().toISOString().replace(/[:.]/g,'-'));
 fs.mkdirSync(backup,{recursive:true,mode:0o700});atomicWrite(path.join(backup,'backend.env'),original);atomicWrite(path.join(secure,'previous.env'),original);
 const text=replaceEnv(original,values);
 try{for(const target of [shared,current])atomicWrite(target,text);}
 catch(error){for(const target of [shared,current])atomicWrite(target,original);throw error;}
 console.log('Live BCC configuration applied; backup created; unrelated settings preserved.');
 console.log('BCC_BANK_REGISTRATION_ENVELOPE='+sealedReport);
 fs.unlinkSync(keyFile);
}
module.exports={parseEnv,liveValues,replaceEnv,decrypt,seal,run};
if(require.main===module)run(...process.argv.slice(2)).catch(error=>{console.error('BCC operation failed; activation was not confirmed. Code:',error.code||'BCC_CONFIG_FAILED');process.exitCode=1;});
