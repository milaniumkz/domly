import {Database} from '../infrastructure/db/Database';
import {BonusService} from './domainServices';

/** Runs in the same ambient transaction as the authenticated provider callback. */
export async function applyKaspiCancellation(db:Database,payment:any,eventTime:string|null) {
 await db.query('SELECT id FROM app_users WHERE id=$1 FOR UPDATE',[payment.customer_id]);
 payment=(await db.query('SELECT * FROM payments WHERE id=$1 FOR UPDATE',[payment.id])).rows[0];
 if(!payment||payment.provider!=='kaspi'||payment.status!=='cancelled'||payment.paid_at)return;
 if(payment.payload?.kaspiCancellation?.appliedAt)return;
 const result:any={at:eventTime??new Date().toISOString(),appliedAt:new Date().toISOString(),source:'kaspi',scope:'payment',cancelledOrderIds:[],cancelledAddonIds:[],bonusReturned:0};
 const refund=async(p:any)=>{
  const net=Number((await db.query("SELECT COALESCE(-SUM(amount),0) AS n FROM bonus_transactions WHERE user_id=$1 AND payment_id=$2 AND type IN ('spend','refund')",[p.customer_id,p.id])).rows[0].n);
  if(net>0){await new BonusService(db).refund(p.customer_id,net,'Возврат бонусов: счёт Kaspi отменён',p.order_id??undefined,p.id,db);result.bonusReturned+=net;
   if(p.order_id)await db.query('UPDATE service_orders SET bonus_spent=GREATEST(0,bonus_spent-$2) WHERE id=$1',[p.order_id,net]);}
 };
 const cancelOrder=async(order:any)=>{
  if(!['draft','pending_payment','pending_assignment','waiting_cleaner','assigned'].includes(order.status)){result.requiresReview=true;return false;}
  await db.query("UPDATE service_orders SET status='cancelled',cancellation_reason='Счёт Kaspi отменён',updated_at=NOW() WHERE id=$1",[order.id]);
  await db.query("INSERT INTO order_status_history(order_id,old_status,new_status,comment) VALUES($1,$2,'cancelled','Счёт Kaspi отменён')",[order.id,order.status]);
  await db.query("UPDATE order_offers SET status='expired' WHERE order_id=$1 AND status='offered'",[order.id]);
  await db.query("UPDATE order_addons SET payment_status='cancelled' WHERE order_id=$1 AND payment_status IN ('draft','pending','invoice_requested') AND paid_separately=FALSE",[order.id]);
  result.cancelledOrderIds.push(order.id);return true;
 };
 if(payment.customer_package_id){
  const pkg=(await db.query('SELECT * FROM customer_packages WHERE id=$1 FOR UPDATE',[payment.customer_package_id])).rows[0];
  const others=(await db.query("SELECT id,status FROM payments WHERE customer_package_id=$1 AND id<>$2 AND status IN ('paid','draft','pending','invoice_requested')",[payment.customer_package_id,payment.id])).rows;
  const started=(await db.query("SELECT 1 FROM service_orders WHERE customer_package_id=$1 AND status IN ('in_progress','completed') LIMIT 1",[payment.customer_package_id])).rows.length;
  if(pkg?.status==='pending_payment'&&!others.length&&!started){
   result.scope='package';
   await db.query("UPDATE preorders SET status='cancelled',updated_at=NOW() WHERE customer_package_id=$1 AND status IN ('new','notified')",[pkg.id]);
   await db.query("UPDATE customer_packages SET status='cancelled',updated_at=NOW() WHERE id=$1",[pkg.id]);
   for(const order of (await db.query("SELECT * FROM service_orders WHERE customer_package_id=$1 AND status NOT IN ('completed','cancelled') ORDER BY id FOR UPDATE",[pkg.id])).rows)await cancelOrder(order);
   for(const p of (await db.query('SELECT * FROM payments WHERE customer_package_id=$1 ORDER BY id FOR UPDATE',[pkg.id])).rows)await refund(p);
  }else{result.retainedReason=others.length?'other_payment_exists':started?'cleaning_started':'package_not_pending';if(started)result.requiresReview=true;}
 }else if(payment.order_id){
  const order=(await db.query('SELECT * FROM service_orders WHERE id=$1 FOR UPDATE',[payment.order_id])).rows[0];
  if(order){
   const otherPending=(await db.query("SELECT 1 FROM payments WHERE order_id=$1 AND id<>$2 AND status IN ('draft','pending','invoice_requested') LIMIT 1",[order.id,payment.id])).rows.length;
   const paidBase=(await db.query(`SELECT 1 FROM payments WHERE status='paid' AND
    (order_id=$1 OR customer_package_id=$2) LIMIT 1`,[order.id,order.customer_package_id])).rows.length;
   if(otherPending){result.retainedReason='other_payment_exists';}
   else if(paidBase||payment.payload?.kind==='addon_request_payment'){
    result.scope='addons';
    if(order.status==='pending_payment'&&!order.cleaner_id)result.readyOrderIds=[order.id];
    const removed=(await db.query(`UPDATE order_addons SET payment_status='cancelled' WHERE order_id=$1
     AND payment_status IN ('draft','pending','invoice_requested') AND paid_separately=FALSE
     AND requires_customer_approval IS DISTINCT FROM TRUE RETURNING id,price,quantity,duration_minutes`,[order.id])).rows;
    result.cancelledAddonIds=removed.map(r=>r.id);
    const minutes=removed.reduce((n,r)=>n+Number(r.duration_minutes),0);
    const totals=(await db.query(`SELECT COALESCE(SUM(price*quantity),0) total,
     COALESCE(SUM(price*quantity) FILTER(WHERE payment_status IN ('pending','invoice_requested')),0) pending
     FROM order_addons WHERE order_id=$1 AND paid_separately=FALSE AND requires_customer_approval IS DISTINCT FROM TRUE
     AND payment_status NOT IN ('cancelled','rejected','refunded')`,[order.id])).rows[0];
    await db.query(`UPDATE service_orders SET addon_amount=$2,total_amount=base_amount+$2,payable_amount=$3,
     estimated_duration_minutes=GREATEST(1,estimated_duration_minutes-$4),
     end_time=start_time+GREATEST(1,estimated_duration_minutes-$4)*INTERVAL '1 minute',
     status=CASE WHEN status='pending_payment' THEN CASE WHEN cleaner_id IS NULL THEN 'pending_assignment' ELSE 'assigned' END ELSE status END,
     updated_at=NOW() WHERE id=$1`,[order.id,totals.total,totals.pending,minutes]);
    await db.query('UPDATE checklist_reports SET requirements_initialized=FALSE WHERE order_id=$1',[order.id]);await refund(payment);
   }else{result.scope='order';if(await cancelOrder(order))await refund(payment);}
  }
 }else await refund(payment);
 await db.query(`UPDATE moon_ai_outbox SET state='cancelled',failure_code='payment_cancelled',finished_at=NOW()
  WHERE payment_id=$1 AND state='pending' AND kind IN ('invoice','abandoned_checkout')`,[payment.id]);
 await db.query(`UPDATE payments SET payload=payload || jsonb_build_object('kaspiCancellation',$2::jsonb) WHERE id=$1`,[payment.id,result]);
 await db.query(`INSERT INTO audit_logs(action,entity_type,entity_id,payload) VALUES('payment.kaspi_cancelled','payment',$1,$2)`,[payment.id,{...result,actorKind:'bot',actorName:'MooonAI',customerId:payment.customer_id}]);
}
