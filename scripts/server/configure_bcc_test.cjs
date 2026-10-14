// Only public BCC sandbox settings. Production credentials are not logged or replaced.
const fs=require('node:fs'),path=require('node:path');
const base=process.argv[2];
const shared=path.join(base,'shared/backend.env'),current=path.join(base,'current/backend/.env');
const original=fs.readFileSync(fs.existsSync(shared)?shared:current,'utf8');
const values=Object.fromEntries(original.split('\n').filter(line=>line.includes('=')&&!line.startsWith('#')).map(line=>{const at=line.indexOf('=');return [line.slice(0,at),line.slice(at+1).replace(/^['"]|['"]$/g,'')];}));
if(values.BCC_MODE==='live')throw new Error('Refusing to replace a live BCC configuration with sandbox settings.');
const publicUrl=new URL(values.PUBLIC_API_URL || 'https://domly.kz');
if(publicUrl.protocol!=='https:')throw new Error('Public API URL must use HTTPS.');
publicUrl.port='443';
// URL.toString removes default ports; BCC requires the explicit :443 spelling.
const notifyUrl=`https://${publicUrl.hostname}:443/api/v1/payments/bcc/webhook`;
const settings={BCC_MODE:'test',BCC_NOTIFY_URL:notifyUrl,BCC_RETURN_URL:'https://domly.kz/customer/#/client/payment-history'};
const backup=path.join(base,'backups','bcc-test-config-'+new Date().toISOString().replace(/[:.]/g,'-'));
fs.mkdirSync(backup,{recursive:true,mode:0o700});fs.writeFileSync(path.join(backup,'backend.env'),original,{mode:0o600});
const lines=original.split('\n').filter(line=>!Object.hasOwn(settings,line.split('=')[0]));
const text=lines.join('\n').replace(/\n*$/,'\n')+Object.entries(settings).map(([key,value])=>`${key}=${value}`).join('\n')+'\n';
for(const target of [shared,current]){fs.writeFileSync(target+'.bcc.tmp',text,{mode:0o600});fs.renameSync(target+'.bcc.tmp',target);fs.chmodSync(target,0o600);}
console.log('BCC sandbox enabled. Configuration backed up. Live payment credentials preserved.');
