import {Database} from '../infrastructure/db/Database';
import {randomUUID} from 'node:crypto';
import {hash,problem,readRules} from './core';
import {eventSignature} from './collector';
export async function domainRules(db:Database){
 const rules=await readRules(db),version=rules.version;
 const rows=(await db.query(`SELECT p.id,p.customer_id,p.order_id,p.status AS payment_status,o.status AS order_status,p.updated_at
 FROM payments p JOIN service_orders o ON o.id=p.order_id
 WHERE p.id=(SELECT p2.id FROM payments p2 WHERE p2.order_id=p.order_id ORDER BY p2.created_at DESC,p2.id DESC LIMIT 1) AND p.updated_at<NOW()-INTERVAL '5 minutes' AND p.updated_at>NOW()-INTERVAL '30 days'
 AND ((p.status IN ('pending','invoice_requested','draft','rejected','cancelled') AND o.status IN ('searching','in_progress','assigned','start_pending','completed'))
 OR (p.status='paid' AND o.status IN ('pending_payment','awaiting_payment','payment_pending')))
 ORDER BY p.updated_at DESC LIMIT 20`)).rows;
 for(const r of rows){
  const fingerprint='payment-order-mismatch:'+r.id+':'+r.payment_status+':'+r.order_status;
  if((await db.query('SELECT 1 FROM tech_problems WHERE fingerprint=$1',[hash(fingerprint)])).rows.length)continue;
  const event=(await db.query(`INSERT INTO tech_events(request_id,user_id,source,action,entity_type,entity_id,result,finished_at,fields)
   VALUES($1,$2,'worker','domain.payment_order_state','orders',$3,'reported',NOW(),$4) RETURNING *`,[randomUUID(),r.customer_id,r.order_id,{rule:'payment_order_state',rulesVersion:version,paymentId:r.id,paymentStatus:r.payment_status,orderStatus:r.order_status,observation:'Несогласованные состояния дольше пяти минут; требуется проверка, это не доказанная причина.'}])).rows[0];
  await db.query('UPDATE tech_events SET signature=$2 WHERE id=$1',[event.id,eventSignature(event)]);
  await problem(db,{kind:'domain',severity:'critical',fingerprint,code:'payment_order_state',title:'Состояния заказа и платежа требуют проверки',eventId:event.id,recommendation:'Сверьте платёж, историю статусов и callback интеграции. Автоматически деньги и статусы не изменяются.'});
 }
 const locations=(await db.query(`SELECT e.*,a.latitude AS address_lat,a.longitude AS address_lon,a.id AS address_id FROM tech_events e
 JOIN LATERAL(SELECT id,latitude,longitude FROM customer_addresses WHERE user_id=e.user_id AND is_primary=TRUE AND latitude IS NOT NULL AND longitude IS NOT NULL ORDER BY updated_at DESC LIMIT 1)a ON TRUE
 WHERE e.action='location.report' AND e.gps IS NOT NULL AND e.started_at>NOW()-INTERVAL '10 minutes' AND e.problem_id IS NULL LIMIT 20`)).rows;
 for(const r of locations){const g=r.gps;if(g.consent!==true||Number(g.accuracy)>1000)continue;const rad=(n:number)=>n*Math.PI/180,lat=rad(Number(g.latitude)-Number(r.address_lat)),lon=rad(Number(g.longitude)-Number(r.address_lon));const h=Math.sin(lat/2)**2+Math.cos(rad(Number(g.latitude)))*Math.cos(rad(Number(r.address_lat)))*Math.sin(lon/2)**2;const km=6371*2*Math.atan2(Math.sqrt(h),Math.sqrt(Math.max(0,1-h)));
 if(km>Number(rules.config.geoDistanceKm??100))await problem(db,{kind:'domain',fingerprint:'location-distance:'+r.user_id+':'+Math.floor(Date.now()/86400000),code:'location_distance',title:'Геопозиция устройства далеко от основного адреса',eventId:r.id,recommendation:`Устройство сообщило GPS с разрешением; расстояние около ${Math.round(km)} км при точности ${Math.round(g.accuracy)} м. Пользователь может находиться в поездке; это не нарушение и не подтверждение личности. Проверьте актуальность адреса и координат. Версия правила ${version}.`});
 }
}
