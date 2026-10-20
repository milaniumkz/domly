'use strict';
const fs=require('fs'),path=require('path'),crypto=require('crypto');
const {createRequire}=require('module'),appRequire=createRequire('/app/package.json');
const {Pool}=appRequire('pg'),bcrypt=appRequire('bcryptjs'),webpush=appRequire('web-push');
(async()=>{
 const dir=process.argv[2];if(!dir||!dir.startsWith('/'))throw Error('Absolute deployment path required');
 const shared=path.join(dir,'shared'),envPath=path.join(shared,'backend.env');
 const original=fs.readFileSync(envPath,'utf8');const values=Object.fromEntries(original.split('\n').filter(l=>/^[A-Z][A-Z0-9_]*=/.test(l)).map(l=>{const i=l.indexOf('=');return[l.slice(0,i),l.slice(i+1).replace(/^['"]|['"]$/g,'')];}));
 const db=new Pool({connectionString:values.DATABASE_URL});
 const accounts=await db.query('SELECT id FROM tech_accounts WHERE owner=TRUE');
 if(accounts.rows.length&&!values.TECH_AUDIT_KEY){await db.end();throw Error('Restore the existing audit key before recovery');}
 const added={};if(!values.TECH_AUDIT_KEY)added.TECH_AUDIT_KEY=crypto.randomBytes(48).toString('base64url');
 if(!values.TECH_VAPID_PUBLIC_KEY||!values.TECH_VAPID_PRIVATE_KEY){const pair=webpush.generateVAPIDKeys();added.TECH_VAPID_PUBLIC_KEY=pair.publicKey;added.TECH_VAPID_PRIVATE_KEY=pair.privateKey;}
 added.TECH_PRIVATE_BUCKET=values.TECH_PRIVATE_BUCKET||'domly-technical-private';
 const next=original.split('\n').filter(l=>!Object.keys(added).some(k=>l.startsWith(k+'='))).join('\n')+'\n'+Object.entries(added).map(([k,v])=>k+'='+v).join('\n')+'\n';
 fs.copyFileSync(envPath,path.join(shared,'backend.before-technical.env'));fs.chmodSync(path.join(shared,'backend.before-technical.env'),0o600);
 fs.writeFileSync(envPath,next,{mode:0o600});fs.chmodSync(envPath,0o600);fs.writeFileSync(path.join(dir,'current/backend/.env'),next,{mode:0o600});
 Object.assign(process.env,values,added);
 const envBackup=path.join(dir,'backups','technical-config-'+new Date().toISOString().replace(/[:.]/g,'-'));fs.mkdirSync(envBackup,{recursive:true,mode:0o700});fs.writeFileSync(path.join(envBackup,'backend.env'),next,{mode:0o600});
 const {StorageService}=appRequire('./dist/modules/integrations.js');const {ensurePrivateBucket}=appRequire('./dist/technical/files.js');await ensurePrivateBucket(new StorageService());
 try{
  if(!accounts.rows.length){
   const publicKey=Buffer.from(process.env.TECH_RECIPIENT_PUBLIC_KEY||'','base64').toString();
   if(!publicKey.includes('BEGIN PUBLIC KEY'))throw Error('Encrypted recipient key required for first initialization');
   const password=crypto.randomBytes(24).toString('base64url');
   const encrypted=crypto.publicEncrypt({key:publicKey,oaepHash:'sha256',padding:crypto.constants.RSA_PKCS1_OAEP_PADDING},Buffer.from(JSON.stringify({url:'https://domly.kz/api/tech/',login:'owner',password,mustChangePassword:true}))).toString('base64');
   const owner=await db.query('INSERT INTO tech_accounts(login,password_hash,display_name,owner) VALUES($1,$2,$3,TRUE) RETURNING id',['owner',await bcrypt.hash(password,12),'Владелец Domly']);
   fs.writeFileSync(path.join(shared,'technical-initial-access.encrypted'),encrypted,{mode:0o600});
   const {Database}=appRequire('./dist/infrastructure/db/Database.js'),auditDb=new Database(values.DATABASE_URL);try{await appRequire('./dist/technical/core.js').audit(auditDb,{accountId:owner.rows[0].id,action:'technical.owner_initialized',payload:{method:'Encrypted GitHub workflow initialization',recipientPublicKeyHash:crypto.createHash('sha256').update(publicKey).digest('hex')}});}finally{await auditDb.close();}
   console.log(JSON.stringify({initialized:true,encryptedAccess:encrypted}));
  }else console.log(JSON.stringify({initialized:true,ownerAlreadyExists:true,credentialsNotReset:true}));
 }finally{await db.end();}
})().catch(()=>{console.error('technical_initialization_failed; inspect privately on server');process.exitCode=1;});
