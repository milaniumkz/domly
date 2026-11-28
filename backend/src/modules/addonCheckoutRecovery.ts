import {Database} from '../infrastructure/db/Database';
import {BonusService,PaymentService} from './domainServices';
import type {NotificationService} from './domainServices';
import {moonAiReady,queueMoonInvoice} from './moonAi';
import {bookingLock} from './botBookingCapacity';

const kind='addon_edit_checkout';
export async function editableAddonCheckout(db:Database,orderId:string){
 return (await db.query(`SELECT p.* FROM payments p WHERE p.order_id=$1 AND p.status='pending'
  AND p.payload->>'kind'=$2 AND p.payload->>'addonCheckoutSelected' IS DISTINCT FROM 'true'
  AND NOT (p.payload ? 'paymentHtml') AND NOT EXISTS(SELECT 1 FROM moon_ai_outbox b WHERE b.payment_id=p.id AND b.kind='invoice')
  ORDER BY p.created_at DESC LIMIT 1 FOR UPDATE OF p`,[orderId,kind])).rows[0];
}

/** Persist the payment with the edit, so closing the payment picker cannot lose the bill. */
export async function persistAddonCheckout(db:Database,order:any,notifications?:Pick<NotificationService,'createAdminEvent'>){
 const pending=await editableAddonCheckout(db,order.id);
 if(Number(order.payable_amount)<=0){
  if(pending){await db.query("UPDATE payments SET status='cancelled',updated_at=NOW() WHERE id=$1 AND status='pending'",[pending.id]);
   await db.query("UPDATE moon_ai_outbox SET state='cancelled',finished_at=NOW() WHERE payment_id=$1 AND kind='abandoned_checkout' AND state='pending'",[pending.id]);}

  return null;
 }
 const previous=(await db.query(`SELECT provider,invoice_phone FROM payments WHERE order_id=$1 AND status='paid'
  ORDER BY paid_at DESC NULLS LAST,created_at DESC LIMIT 1`,[order.id])).rows[0];
 const phone=previous?.provider==='kaspi'&&/^7\d{10}$/.test(String(previous.invoice_phone??'').replace(/\D/g,''))?previous.invoice_phone:null;
 const recoveryAfter=new Date(Date.now()+120000).toISOString();
 let payment;
 if(pending){
  payment=(await db.query(`UPDATE payments SET amount=$2,provider=$3,invoice_phone=$4,
   payload=payload||jsonb_build_object('addonRecoveryAfter',$5::text),updated_at=NOW() WHERE id=$1 RETURNING *`,
   [pending.id,order.payable_amount,phone?'kaspi':'manual',phone,recoveryAfter])).rows[0];
 }else{
  payment=(await new PaymentService(db,new BonusService(db)).createPayment({customerId:order.customer_id,orderId:order.id,
   provider:phone?'kaspi':'manual',invoicePhone:phone??undefined,amount:Number(order.payable_amount),applyReferralDiscount:false,
   payload:{kind,addonRecoveryAfter:recoveryAfter}})).payment;
 }
 if(notifications)await notifications.createAdminEvent({event:'new_payment',titleRu:'Допуслуги ожидают оплаты',
  bodyRu:`Заказ №${order.numeric_id}: доплата ${order.payable_amount} ₸. Заявка на оплату сохранена.`,
  targetType:'payment',targetId:payment.id,dedupeKey:`addon-edit-checkout:${payment.id}:${order.payable_amount}`});
 return payment;
}

/** Only new edit intents are recovered; historical payments and explicit BCC choices are untouched. */
export async function recoverAddonCheckouts(db:Database,notifications:Pick<NotificationService,'create'|'createAdminEvent'>,paymentId?:string){
 const candidates=(await db.query(`SELECT p.id,p.order_id,p.customer_id FROM payments p WHERE p.status='pending' AND p.payload->>'kind'=$1 AND ($2::uuid IS NULL OR p.id=$2)
  AND (p.payload->>'addonRecoveryAfter')::timestamptz<=NOW() AND p.payload->>'addonRecoveryNotified' IS NULL
  AND NOT (p.payload ? 'paymentHtml') AND NOT EXISTS(SELECT 1 FROM moon_ai_outbox b WHERE b.payment_id=p.id AND b.kind='invoice')
  ORDER BY p.created_at LIMIT 20`,[kind,paymentId??null])).rows;
 let queued=0;
 for(const candidate of candidates)await db.atomic(async()=>{
  await db.query('SELECT pg_advisory_xact_lock(hashtextextended($1,0))',['order-payment:'+candidate.order_id]);
  await db.query('SELECT id FROM app_users WHERE id=$1 FOR UPDATE',[candidate.customer_id]);
  await db.query('SELECT pg_advisory_xact_lock(hashtextextended($1,0))',[bookingLock]);
  const p=(await db.query('SELECT * FROM payments WHERE id=$1 FOR UPDATE',[candidate.id])).rows[0];
  const o=(await db.query('SELECT * FROM service_orders WHERE id=$1 FOR UPDATE',[candidate.order_id])).rows[0];
  if(!p||p.status!=='pending'||p.payload.addonRecoveryNotified||p.payload.paymentHtml||!o||['cancelled','canceled','completed'].includes(o.status))return;
  if((await db.query("SELECT 1 FROM moon_ai_outbox WHERE payment_id=$1 AND kind='invoice'",[p.id])).rows.length)return;
  const actual=(await db.query(`SELECT COALESCE(SUM(price*quantity),0) amount FROM order_addons WHERE order_id=$1
   AND paid_separately=FALSE AND requires_customer_approval IS DISTINCT FROM TRUE AND payment_status IN ('pending','draft')`,[o.id])).rows[0];
  const conflict=(await db.query(`SELECT 1 FROM payments WHERE order_id=$1 AND id<>$2 AND
   (status IN ('pending','invoice_requested') OR (status='paid' AND COALESCE(paid_at,approved_at,created_at)>=$3)) LIMIT 1`,[o.id,p.id,p.created_at])).rows.length>0;
  const amountMatches=!conflict&&Math.round(Number(o.payable_amount)*100)===Math.round(Number(p.amount)*100)
   &&Math.round(Number(actual.amount)*100)===Math.round(Number(p.amount)*100)&&Number(p.amount)>0;
  if(amountMatches&&p.provider==='kaspi'&&p.invoice_phone&&p.payload.addonCheckoutSelected!==true&&moonAiReady()){
   const provider=await queueMoonInvoice(db,p,`Дополнительные услуги заказа №${o.numeric_id} DomLY`);
   await db.query('UPDATE payments SET payload=payload||$2::jsonb,updated_at=NOW() WHERE id=$1',[p.id,JSON.stringify(provider)]);
   await db.query("INSERT INTO audit_logs(action,entity_type,entity_id,payload) VALUES('payment.invoice_requested','payment',$1,$2::jsonb)",
    [p.id,JSON.stringify({source:'addon_edit_recovery',orderId:o.id})]);
   queued++;
   return;
  }
  await notifications.create({userId:o.customer_id,titleRu:'Завершите оплату допуслуг',
   bodyRu:`В заказе №${o.numeric_id} есть неоплаченные допуслуги. Откройте платёж и выберите способ оплаты.`,targetType:'payments',targetId:p.id,dedupeKey:`addon-checkout-required:${p.id}`});
  await notifications.createAdminEvent({event:'new_payment',titleRu:'Не завершено выставление счёта за допуслуги',
   bodyRu:`Заказ №${o.numeric_id}: требуется выбор оплаты или проверка счёта. Откройте платёж.`,targetType:'payment',targetId:p.id,dedupeKey:`addon-checkout-required:${p.id}`});
  await db.query("UPDATE payments SET payload=payload||jsonb_build_object('addonRecoveryNotified',true),updated_at=NOW() WHERE id=$1",[p.id]);
 });
 return {queued};
}
