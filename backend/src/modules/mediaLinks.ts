import {createHmac,timingSafeEqual} from 'crypto';
import {RequestHandler} from 'express';
import {env} from '../common/env';
import {ApiError} from '../common/api';
import {verifyAccessToken} from '../common/auth';
import {Database} from '../infrastructure/db/Database';

const routePath='/api/v1/files/media';
const lifetime=4*3600;
const validKey=(key:string)=>key.length>0 && key.length<2048 && !key.split('/').some(p=>!p||p==='.'||p==='..') && !/[\\\x00-\x1f]/.test(key);
function signature(key:string,expires:number) {
  return createHmac('sha256',env.jwtAccessSecret).update(`domly-media-v1\n${key}\n${expires}`).digest('hex');
}
export function verifyMediaLink(key:string,expires:string,provided:string,checkExpiry=true) {
  const end=Number(expires);
  if (!validKey(key)||!Number.isSafeInteger(end)||! /^[a-f0-9]{64}$/.test(provided)) return false;
  if (checkExpiry && (end<=Date.now()/1000 || end>Date.now()/1000+lifetime+3600)) return false;
  return timingSafeEqual(Buffer.from(provided,'hex'),Buffer.from(signature(key,end),'hex'));
}
function signedKey(value:string) {
  if(!value.startsWith(env.publicApiUrl.replace(/\/$/,'')+'/'))return null;
  try {
    const url=new URL(value),base=new URL(env.publicApiUrl);
    if(url.origin!==base.origin||url.pathname!==routePath)return null;
    const key=url.searchParams.get('key')??'';
    return verifyMediaLink(key,url.searchParams.get('expires')??'',url.searchParams.get('signature')??'',false)?key:null;
  }catch{return null;}
}
export function storageKey(value:string) {
  const signed=signedKey(value);
  if(signed)return signed;
  if(!value.startsWith(env.minioPublicUrl.replace(/\/$/,'')+'/'))return null;
  try {
    const url=new URL(value),base=new URL(env.minioPublicUrl);
    const prefix=base.pathname.replace(/\/$/,'')+'/';
    if(url.origin!==base.origin||!url.pathname.startsWith(prefix))return null;
    const key=decodeURIComponent(url.pathname.slice(prefix.length));
    return validKey(key)?key:null;
  }catch{return null;}
}
export function canonicalMediaUrl(value:string) {
  const key=signedKey(value);
  return key?env.minioPublicUrl.replace(/\/$/,'')+'/'+key:value;
}
export function httpsMediaUrl(value:string) {
  const key=storageKey(value);
  if(!key)return value;
  // Stable URLs within an hour keep image caches useful across live polling.
  const expires=Math.floor(Date.now()/3600000)*3600+lifetime;
  const url=new URL(routePath,env.publicApiUrl);
  url.searchParams.set('key',key);url.searchParams.set('expires',String(expires));url.searchParams.set('signature',signature(key,expires));
  return url.toString();
}
export function mapMediaValues(value:any,convert:(value:string)=>string):any {
  if(typeof value==='string')return convert(value);
  if(Array.isArray(value))return value.map(item=>mapMediaValues(item,convert));
  if(value && Object.getPrototypeOf(value)===Object.prototype)return Object.fromEntries(Object.entries(value).map(([key,item])=>[key,mapMediaValues(item,convert)]));
  return value;
}
export function mediaLinksMiddleware(db:Database):RequestHandler {
  return (req,res,next)=>{
    const json=res.json.bind(res);
    res.json=(value:any)=>json(mapMediaValues(value,httpsMediaUrl));
    void (async()=>{
      // Do not mint a private file capability from another user's guessed raw URL.
      if(req.body && !['GET','HEAD'].includes(req.method)) {
        const rawKeys=new Set<string>();
        mapMediaValues(req.body,value=>{const key=storageKey(value);if(key&&!signedKey(value))rawKeys.add(key);return value;});
        if(rawKeys.size) {
          let user;
          try {user=verifyAccessToken(req.header('authorization')?.replace(/^Bearer /,'')??'');}catch{throw new ApiError(401,'unauthorized','Войдите в аккаунт.');}
          if(!['admin','superadmin'].includes(user.role)) {
            const own=(await db.query<{object_key:string}>('SELECT object_key FROM files WHERE bucket=$1 AND owner_id=$2 AND object_key=ANY($3::text[])',[env.minioBucket,user.id,[...rawKeys]])).rows;
            if(own.length!==rawKeys.size)throw new ApiError(403,'forbidden','Нет доступа к этому файлу.');
          }
        }
        req.body=mapMediaValues(req.body,canonicalMediaUrl);
      }
      next();
    })().catch(next);
  };
}
