// Envelope is RSA-OAEP + AES-256-GCM. Plaintext secrets never enter argv/logs.
const fs=require('node:fs'),path=require('node:path'),crypto=require('node:crypto');
const base=process.argv[2];
try {
  const packet=JSON.parse(fs.readFileSync(0,'utf8'));
  const key=crypto.privateDecrypt({key:fs.readFileSync(path.join(base,'shared/moon-config-key.pem')),oaepHash:'sha256'},Buffer.from(packet.key,'base64'));
  const decipher=crypto.createDecipheriv('aes-256-gcm',key,Buffer.from(packet.iv,'base64'));
  decipher.setAuthTag(Buffer.from(packet.tag,'base64'));
  const config=JSON.parse(Buffer.concat([decipher.update(Buffer.from(packet.data,'base64')),decipher.final()]).toString());
  const allowed=new Set(['MOON_AI_ENABLED','MOON_AI_CHANNEL_URL','MOON_AI_CHANNEL_API_KEY','MOON_AI_WEBHOOK_TOKEN','MOON_AI_SOURCE']);
  for(const [name,value]of Object.entries(config)) {
    if(!allowed.has(name)||typeof value!=='string'||/[\r\n\0\"\'\s\$#]/.test(value))throw new Error('invalid config');
  }
  if(config.MOON_AI_ENABLED!=='true'||!config.MOON_AI_CHANNEL_URL?.startsWith('https://core.mooonai.com/'))throw new Error('invalid endpoint');
  const shared=path.join(base,'shared/backend.env'),current=path.join(base,'current/backend/.env');
  const original=fs.readFileSync(fs.existsSync(shared)?shared:current,'utf8');
  const backup=path.join(base,'backups','moon-config-'+new Date().toISOString().replace(/[:.]/g,'-'));
  fs.mkdirSync(backup,{recursive:true,mode:0o700});fs.writeFileSync(path.join(backup,'backend.env'),original,{mode:0o600});
  const lines=original.split('\n').filter(line=>!allowed.has(line.split('=')[0]));
  const text=lines.join('\n').replace(/\n*$/,'\n')+Object.entries(config).map(([name,value])=>name+'='+value).join('\n')+'\n';
  for(const target of [shared,current]) {fs.writeFileSync(target+'.moon.tmp',text,{mode:0o600});fs.renameSync(target+'.moon.tmp',target);fs.chmodSync(target,0o600);}
  fs.unlinkSync(path.join(base,'shared/moon-config-key.pem'));
  console.log('Moon AI settings updated; previous configuration backed up.');
} catch (_) {console.error('Encrypted Moon AI configuration could not be applied.');process.exitCode=1;}
