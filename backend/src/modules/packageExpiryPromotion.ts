import {randomUUID} from 'node:crypto';
import {Database} from '../infrastructure/db/Database';
import type {NotificationService} from './domainServices';

export const expiryPromotionSetting='packageExpiryPromotion';
type Pause={id:string;startsAt:string;endsAt?:string};
export async function readExpiryPromotion(db:Database,lock=false){
 const value=(await db.query(`SELECT value FROM app_settings WHERE key=$1${lock?' FOR SHARE':''}`,[expiryPromotionSetting])).rows[0]?.value;
 const intervals:Pause[]=Array.isArray(value?.intervals)?value.intervals:[];
 return {intervals,active:intervals.some(p=>!p.endsAt)};
}
export async function setExpiryPromotion(db:Database,active:boolean,now=Date.now()){
 return db.atomic(async()=>{
  await db.query("INSERT INTO app_settings(key,value) VALUES($1,'{\"intervals\":[]}'::jsonb) ON CONFLICT(key) DO NOTHING",[expiryPromotionSetting]);
  const row=(await db.query('SELECT value FROM app_settings WHERE key=$1 FOR UPDATE',[expiryPromotionSetting])).rows[0];
  const intervals:Pause[]=row.value.intervals??[];let current=intervals.find(p=>!p.endsAt);let changed=false;
  if(active&&!current){current={id:randomUUID(),startsAt:new Date(now).toISOString()};intervals.push(current);changed=true;}
  else if(!active&&current){current.endsAt=new Date(Math.max(now,Date.parse(current.startsAt))).toISOString();changed=true;}
  await db.query('UPDATE app_settings SET value=$2::jsonb WHERE key=$1',[expiryPromotionSetting,JSON.stringify({intervals})]);
  if(changed)await db.query("INSERT INTO audit_logs(action,entity_type,entity_id,payload) VALUES($1,'setting',$2,$3::jsonb)",[active?'package.expiry_promotion_enabled':'package.expiry_promotion_disabled',expiryPromotionSetting,JSON.stringify({campaignId:current?.id,active})]);
  return {active,campaign:current,intervals};
 });
}

/** On resumption, move deadlines by the pause duration once. No old credits are restored. */
export async function applyFinishedExpiryPauses(db:Database,pkg:any,periods:any[],intervals:Pause[]){
 if(pkg.status!=='active'||!periods.length)return;
 const applied={...(pkg.expiry_pause_offsets??{})};let changed=false;
 const paidAt=new Date(periods[0].starts_at).getTime();
 for(const pause of intervals){
  if(!pause.endsAt||applied[pause.id]!==undefined)continue;
  const start=Math.max(Date.parse(pause.startsAt),paidAt);
  const ms=Math.max(0,Date.parse(pause.endsAt)-start);
  if(ms){
   await db.query(`UPDATE customer_package_periods SET
    starts_at=CASE WHEN period_index>0 AND starts_at>=$2::timestamptz THEN starts_at+$3::bigint*INTERVAL '1 millisecond' ELSE starts_at END,
    ends_at=ends_at+$3::bigint*INTERVAL '1 millisecond'
    WHERE customer_package_id=$1 AND ends_at>$2::timestamptz`,[pkg.id,new Date(start).toISOString(),ms]);
   for(const p of periods)if(new Date(p.ends_at).getTime()>start){
    if(Number(p.period_index)>0&&new Date(p.starts_at).getTime()>=start)p.starts_at=new Date(new Date(p.starts_at).getTime()+ms);
    p.ends_at=new Date(new Date(p.ends_at).getTime()+ms);
   }
  }
  applied[pause.id]=ms;changed=true;
 }
 if(changed){
  const updated=(await db.query(`UPDATE customer_packages SET expiry_pause_offsets=$2::jsonb,
   period_end=($3::timestamptz AT TIME ZONE 'Asia/Almaty')::date,updated_at=NOW() WHERE id=$1 RETURNING period_end`,
   [pkg.id,JSON.stringify(applied),periods.at(-1).ends_at])).rows[0];
  pkg.expiry_pause_offsets=applied;pkg.period_end=updated.period_end;
 }
}

export async function announceExpiryPromotion(db:Database,notifications:Pick<NotificationService,'create'>,campaign:Pause){
 let cursor='00000000-0000-0000-0000-000000000000',recipients=0,created=0;
 for(;;){
  const rows=(await db.query(`SELECT id FROM app_users WHERE deleted_at IS NULL AND created_at<=$2::timestamptz AND id>$1
   ORDER BY id LIMIT 100`,[cursor,campaign.startsAt])).rows;
  if(!rows.length)break;
  for(const user of rows){
   const n=await notifications.create({userId:user.id,titleRu:'Ваши уборки сохранятся',titleKk:'Тазалауларыңыз сақталады',
    bodyRu:'Если вы получили уведомление о скором сгорании пакета, не переживайте — мы сделали для вас исключение. Оставшиеся уборки в вашем пакете в ближайшее время не сгорят. Постарайтесь использовать их в срок.',
    bodyKk:'Пакетіңіздің мерзімі жақында аяқталатыны туралы хабарлама алсаңыз, алаңдамаңыз — сіз үшін ерекшелік жасадық. Пакетіңіздегі қалған тазалаулар жақын арада жойылмайды. Оларды уақытында пайдаланып қалуға тырысыңыз.',
    targetType:'info',targetId:campaign.id,dedupeKey:`package-expiry-promo:${campaign.id}`});
   recipients++;if(n)created++;
  }
  cursor=rows.at(-1).id;
 }
 return {recipients,created};
}
