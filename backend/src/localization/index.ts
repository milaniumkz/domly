import catalog from './kazakh.json';
import {Queryable} from '../domain/repositories/UnitOfWork';
const normalize=(text:string)=>text.replace(/\s+/g,' ').trim();
const escape=(text:string)=>text.replace(/[.*+?^${}()|[\]\\]/g,'\\$&');
const templates=Object.entries(catalog).filter(([source])=>/\{p\d+\}/.test(source)).map(([source,translation])=>{
 const parameters=source.match(/\{p\d+\}/g)!;
 const parts=source.split(/\{p\d+\}/);
 return {parameters,translation,pattern:new RegExp('^'+parts.map(escape).join('(.{1,512}?)')+'$'),length:parts.join('').length};
}).sort((a,b)=>b.length-a.length);
export function translateKazakh(source:string):string {
 const text=normalize(source),exact=(catalog as Record<string,string>)[text];if(exact)return exact;
 for(const template of templates){const match=template.pattern.exec(text);if(!match)continue;let value=template.translation;template.parameters.forEach((parameter,i)=>{value=value.split(parameter).join(match[i+1]);});return value;}
 return source;
}
export async function sendLocalizedPush(db:Queryable,fcm:{send:Function},input:{userId?:string;role?:string;titleRu:string;bodyRu:string;titleKk?:string;bodyKk?:string},data:Record<string,string>,options:{requireDelivery?:boolean}={}){
 const tokens=(await db.query<{token:string;language:string}>(
  `SELECT dt.token,u.language FROM device_tokens dt JOIN app_users u ON u.id=dt.user_id
   WHERE dt.enabled=TRUE AND u.deleted_at IS NULL AND u.status<>'blocked' AND ${input.userId?'u.id=$1':'u.role=$1'}`,[input.userId??input.role])).rows;
 for(const locale of ['ru','kk']){
  const group=tokens.filter(t=>(t.language==='kk'?'kk':'ru')===locale).map(t=>t.token);
  if(group.length){const result=await fcm.send(group,locale==='kk'?(input.titleKk||translateKazakh(input.titleRu)):input.titleRu,locale==='kk'?(input.bodyKk||translateKazakh(input.bodyRu)):input.bodyRu,data);
   const invalidTokens=Array.isArray(result?.invalidTokens)?result.invalidTokens:[];
   if(invalidTokens.length)await db.query('UPDATE device_tokens SET enabled=FALSE,updated_at=NOW() WHERE token=ANY($1::text[])',[invalidTokens]);
   if(options.requireDelivery && ((result?.retryableFailed ?? result?.failed ?? 0)>0 || result?.skipped===true || result?.error))throw new Error('PushDeliveryFailed');
  }
 }
}
