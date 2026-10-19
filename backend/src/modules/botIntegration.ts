import {createHash} from 'node:crypto';
import {ApiError} from '../common/api';
import {Database} from '../infrastructure/db/Database';
import {Queryable} from '../domain/repositories/UnitOfWork';
import {normalizePhone, NotificationService} from './domainServices';
import {confirmArea} from './areaVerification';
import {packageQuote} from './packageQuote';

const uuid=/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
export function optionalId(value:unknown) {
  if(value===undefined || value===null)return null;
  if(typeof value!=='string'||!uuid.test(value))throw new ApiError(400,'invalid_id','Некорректный идентификатор.');
  return value;
}
async function customer(db:Queryable, phone:unknown, lock=false) {
  const normalized=normalizePhone(String(phone??''));
  if(!/^\+7\d{10}$/.test(normalized))throw new ApiError(400,'invalid_phone','Укажите номер клиента в формате +7XXXXXXXXXX.');
  const rows=(await db.query(`SELECT id,phone FROM app_users WHERE phone=$1 AND role='customer'
    AND status<>'blocked' AND deleted_at IS NULL ${lock?'FOR UPDATE':''}`,[normalized])).rows;
  if(rows.length!==1)throw new ApiError(404,'customer_not_found','Активный клиент не найден.');
  return rows[0];
}
export async function botCatalog(db:Database,areaValue?:unknown) {
  const area=areaValue===undefined?undefined:Number(areaValue);
  if(area!==undefined && (!Number.isFinite(area)||area<=0||area>10000))throw new ApiError(400,'invalid_area','Площадь должна быть от 0 до 10000 м².');
  return db.transaction(async tx=>{
    await tx.query('SET TRANSACTION ISOLATION LEVEL REPEATABLE READ READ ONLY');
    const packages=(await tx.query('SELECT * FROM catalog_packages WHERE active=TRUE ORDER BY months,cleaning_count,id')).rows;
    const groups=(await tx.query('SELECT id,title_ru,title_kk,sort_order,active FROM addon_groups ORDER BY sort_order,id')).rows;
    const addons=(await tx.query(`SELECT id,group_id,title_ru,title_kk,description_ru,description_kk,hint_ru,hint_kk,
      pricing_type,price,duration_minutes,paid_separately FROM catalog_addons WHERE active=TRUE ORDER BY sort_order,id`)).rows;
    const result=[];
    for(const pkg of packages) {
      const features=pkg.features??{};
      const quotes=[];
      if(area!==undefined)for(const frequency of features.isQuarterly?[2,4,8]:[Number(pkg.cleaning_count)]) {
        const quote=await packageQuote(tx,{packageId:pkg.id,area,cleaningsPerMonth:frequency});
        quotes.push({...quote,totalPrice:quote.monthlyPrice,perCleaningAfterDiscount:Math.round(quote.monthlyPrice/quote.cleaningCount*100)/100});
      }
      result.push({...pkg,includedServices:Array.isArray(features)?features:features.items??[],quotes});
    }
    return {currency:'KZT',area:area??null,generatedAt:new Date().toISOString(),packages:result,addonGroups:groups,addons,
      pricingNotes:{totalPrice:'Весь период пакета, включая скидку. Не ежемесячный платёж.',
        addonPricing:'per_m2/per_sqm: за м²; per_visit: за каждый визит; остальные: один раз за указанное количество.',
        includedServices:'Состав из каталога; пустое описание означает, что оно не заполнено. Не придумывать услуги.'}};
  });
}
export async function botCustomerContext(db:Database,phone:unknown) {
  const user=await customer(db,phone);
  const addresses=(await db.query(`SELECT id,city,street,house,apartment,area,verified_area,is_primary FROM customer_addresses WHERE user_id=$1`,[user.id])).rows;
  const requests=(await db.query(`SELECT q.id,q.address_id,q.customer_package_id,q.order_id,q.requested_area,q.approved_area,q.status,q.scheduled_at,
    q.document_file_id IS NOT NULL AS document_submitted,
    EXISTS(SELECT 1 FROM service_orders o WHERE o.customer_id=q.customer_id AND o.address_id=q.address_id AND (o.id=q.order_id OR o.customer_package_id=q.customer_package_id) AND o.status IN ('in_progress','completed')) AS cleaning_already_started
    FROM quality_check_requests q WHERE q.customer_id=$1 AND q.status IN ('pending','scheduled','approved') ORDER BY q.created_at DESC LIMIT 30`,[user.id])).rows;
  const orders=(await db.query(`SELECT id,address_id,customer_package_id,status,scheduled_date,start_time FROM service_orders
    WHERE customer_id=$1 AND status NOT IN ('cancelled','completed') ORDER BY scheduled_date,start_time LIMIT 30`,[user.id])).rows;
  return {phone:user.phone,addresses,qualityChecks:requests,orders,appUrl:'https://domly.kz/customer/#/client/area-confirmation'};
}
function eventInput(input:any) {
  if(typeof input.eventId!=='string'||input.eventId.length<8||input.eventId.length>180)throw new ApiError(400,'event_id_required','Нужен стабильный eventId длиной 8–180 символов.');
  optionalId(input.qualityCheckId);
  if(!input.qualityCheckId)throw new ApiError(400,'quality_check_required','Укажите заявку qualityCheckId из customer-context.');
}
async function requestForCustomer(tx:Queryable,input:any,userId:string) {
  const q=(await tx.query('SELECT * FROM quality_check_requests WHERE id=$1 AND customer_id=$2 FOR UPDATE',[input.qualityCheckId,userId])).rows[0];
  if(!q||!q.address_id)throw new ApiError(404,'quality_check_not_found','Заявка с адресом клиента не найдена.');
  if(['rejected','cancelled'].includes(q.status))throw new ApiError(409,'quality_check_closed','Заявка закрыта.');
  const address=(await tx.query('SELECT * FROM customer_addresses WHERE id=$1 AND user_id=$2 FOR UPDATE',[q.address_id,userId])).rows[0];
  if(!address)throw new ApiError(404,'address_not_found','Адрес не найден.');
  return {q,address};
}
function money(n:number){return Math.round(n*100)/100;}
export function areaQuote(snapshot:any,area:number) {
  const base=Math.round((snapshot.basePrice+snapshot.pricePerM2*area)*snapshot.cleaningCount);
  const addonTotal=(snapshot.addons??[]).reduce((sum:number,a:any)=>sum+Math.round(a.unitPrice*(['per_m2','per_sqm'].includes(a.pricingType)?area:1)*a.quantity*(a.pricingType==='per_visit'?snapshot.cleaningCount:1)),0);
  const discount=Math.round(base*snapshot.discountRate);
  return Math.max(0,base+addonTotal-discount-Math.round((base+addonTotal-discount)*snapshot.referralDiscountPercent/100));
}
async function recalculate(tx:Queryable,userId:string,q:any,address:any,area:number,eventId:string) {
  const packages=(await tx.query(`SELECT cp.*,p.amount AS paid_cash,p.bonus_amount AS paid_bonus,p.status AS purchase_status
    FROM customer_packages cp LEFT JOIN payments p ON p.id=cp.purchase_payment_id
    WHERE cp.customer_id=$1 AND cp.address_id=$2 AND (cp.id=$3 OR cp.status='active') ORDER BY cp.id FOR UPDATE OF cp`,[userId,address.id,q.customer_package_id])).rows;
  const results=[];
  for(const cp of packages) {
    if(cp.status!=='active'||cp.purchase_status!=='paid')throw new ApiError(409,'package_not_paid','Перерасчёт требует оплаченного пакета.');
    const config=cp.purchase_config??{};
    let baseline=config.areaPricingBaseline;
    if(!baseline) {
      let snapshot=config.pricingSnapshot;
      if(!snapshot) {
        // Old purchases are reconstructed only when the saved quote matches the tariff exactly.
        const pkg=(await tx.query('SELECT * FROM catalog_packages WHERE id=$1',[cp.package_id])).rows[0];
        const previousArea=Number(address.area);
        const count=Number(config.cleaningCount);
        const base=Number(config.subtotal)-Number(config.addonTotalPrice??0);
        let rate=Number(pkg?.price_per_m2);
        if(pkg?.features?.isQuarterly)rate=Number((await tx.query(`SELECT price_per_m2 FROM catalog_packages WHERE months=1 AND cleaning_count=$1 AND active=TRUE ORDER BY updated_at DESC LIMIT 1`,[config.cleaningsPerMonth])).rows[0]?.price_per_m2);
        if(!pkg||!Number.isFinite(base)||!(count>0)||!(previousArea>0)||Math.round((Number(pkg.base_price)+rate*previousArea)*count)!==base)
          throw new ApiError(409,'pricing_snapshot_required','Не удалось безопасно восстановить исходный тариф. Требуется проверка администратором.');
        snapshot={basePrice:Number(pkg.base_price),pricePerM2:rate,cleaningCount:count,discountRate:Number(config.discountRate??0),referralDiscountPercent:Number(config.referralDiscountPercent??0),
          addons:(config.addons??[]).map((a:any)=>({...a,unitPrice:Number(a.price)/(['per_m2','per_sqm'].includes(a.pricingType)?previousArea:1)}))};
      }
      baseline={snapshot,area:Number(address.area),total:Number(config.monthlyPrice)};
      if(!Number.isFinite(baseline.total)||areaQuote(snapshot,baseline.area)!==baseline.total || money(Number(cp.paid_cash)+Number(cp.paid_bonus))!==baseline.total)
        throw new ApiError(409,'pricing_snapshot_required','Исходная стоимость не совпадает с оплатой; требуется проверка администратора.');
    }
    const prior=(await tx.query(`SELECT a.*,p.status AS payment_status,p.amount,p.external_id,p.invoice_requested_at,p.payload AS payment_payload
      FROM area_package_adjustments a LEFT JOIN payments p ON p.id=a.payment_id WHERE a.customer_package_id=$1 FOR UPDATE OF a`,[cp.id])).rows;
    if(prior.some((a:any)=>a.payment_id))await tx.query('SELECT id FROM payments WHERE id=ANY($1::uuid[]) ORDER BY id FOR UPDATE',[prior.filter((a:any)=>a.payment_id).map((a:any)=>a.payment_id)]);
    for(const a of prior)if(a.payment_id&&['pending','invoice_requested'].includes(a.payment_status)) {
      if(a.payment_status==='invoice_requested'||a.external_id||a.invoice_requested_at||a.payment_payload?.providerPayload||a.payment_payload?.paymentHtml)
        throw new ApiError(409,'active_adjustment_invoice','Предыдущий счёт перерасчёта ещё активен. Сначала завершите или отмените его.');
      // Lock the payment too: a concurrent invoice request/settlement must not be overwritten.
      const cancelled=await tx.query(`UPDATE payments SET status='cancelled',updated_at=NOW() WHERE id=$1 AND status='pending'
        AND external_id IS NULL AND invoice_requested_at IS NULL AND NOT(payload ? 'providerPayload') AND NOT(payload ? 'paymentHtml') RETURNING id`,[a.payment_id]);
      if(!cancelled.rows.length)throw new ApiError(409,'active_adjustment_invoice','Статус доплаты изменился. Повторите проверку.');
    }
    const settled=money(baseline.total+prior.reduce((n:number,a:any)=>n+(a.payment_status==='paid'?Number(a.amount):0)-Number(a.bonus_credit),0));
    const total=areaQuote(baseline.snapshot,area), delta=money(total-settled);
    let paymentId=null;
    if(delta>0)paymentId=(await tx.query(`INSERT INTO payments(customer_id,provider,status,amount,invoice_phone,payload)
      VALUES($1,'kaspi','pending',$2,(SELECT phone FROM app_users WHERE id=$1),$3) RETURNING id`,[userId,delta,
      {kind:'area_recalculation',customerPackageId:cp.id,qualityCheckId:q.id,area,eventId,mInfo:[address.city,address.street,address.house,address.apartment?'кв. '+address.apartment:null].filter(Boolean).join(', ')}])).rows[0].id;
    if(delta<0) {
      const balance=(await tx.query('UPDATE app_users SET bonus_balance=bonus_balance+$2,updated_at=NOW() WHERE id=$1 RETURNING bonus_balance',[userId,-delta])).rows[0].bonus_balance;
      await tx.query(`INSERT INTO bonus_transactions(user_id,type,amount,balance_after,reason_ru,reason_kk,dedupe_key)
        VALUES($1,'accrual',$2,$3,'Возврат за перерасчёт площади','Аудан қайта есептелгені үшін қайтарым',$4)`,[userId,-delta,balance,`area-recalculation:${eventId}:${cp.id}`]);
    }
    await tx.query(`INSERT INTO area_package_adjustments(customer_package_id,event_id,payment_id,bonus_credit,old_total,new_total)
      VALUES($1,$2,$3,$4,$5,$6)`,[cp.id,eventId,paymentId,Math.max(0,-delta),settled,total]);
    await tx.query(`UPDATE customer_packages SET purchase_config=purchase_config || $2::jsonb,updated_at=NOW() WHERE id=$1`,[cp.id,
      {areaPricingBaseline:baseline,areaRecalculation:{area,totalPrice:total,delta,paymentId,eventId,scope:'whole_package'},monthlyPrice:total}]);
    // Existing bookings contain only extra-service amounts; never overwrite these with the package price.
    await tx.query(`UPDATE service_orders SET area=$2,updated_at=NOW() WHERE customer_package_id=$1 AND status NOT IN ('completed','cancelled','in_progress')`,[cp.id,area]);
    results.push({customerPackageId:cp.id,scope:'whole_package',cleaningCount:baseline.snapshot.cleaningCount,oldTotal:settled,totalPrice:total,delta,
      paymentId,bonusCredit:Math.max(0,-delta),paymentStatus:paymentId?'pending':null});
  }
  return results;
}
export async function botConfirmArea(db:Database,notifications:NotificationService,input:any) {
  eventInput(input);
  const area=Number(input.actualArea);
  if(!Number.isFinite(area)||area<=0||area>10000||Math.abs(area*100-Math.round(area*100))>0.00001)throw new ApiError(400,'invalid_area','Площадь должна быть положительным числом, до двух знаков после запятой.');
  const evidence=input.evidence??{documentUrl:input.documentUrl,documentType:input.documentType,readable:input.readable===true||input.readable==='true',addressMatches:input.addressMatches===true||input.addressMatches==='true',totalApartmentAreaConfirmed:input.totalApartmentAreaConfirmed===true||input.totalApartmentAreaConfirmed==='true'};
  if(!evidence||evidence.documentType!=='technical_plan'||evidence.readable!==true||evidence.addressMatches!==true||evidence.totalApartmentAreaConfirmed!==true||typeof evidence.documentUrl!=='string')
    throw new ApiError(422,'plan_not_verified','Нужен читаемый техплан с совпадающим адресом и однозначной общей площадью квартиры.');
  let documentUrl:URL;
  try{documentUrl=new URL(evidence.documentUrl);}catch{throw new ApiError(400,'invalid_document_url','Укажите HTTPS-ссылку на техплан.');}
  if(documentUrl.protocol!=='https:'||documentUrl.username||documentUrl.password||evidence.documentUrl.length>4000)throw new ApiError(400,'invalid_document_url','Укажите HTTPS-ссылку на техплан.');
  const normalized={phone:normalizePhone(String(input.phone??'')),qualityCheckId:input.qualityCheckId,actualArea:area,evidence:{documentUrl:evidence.documentUrl,documentType:evidence.documentType,readable:evidence.readable,addressMatches:evidence.addressMatches,totalApartmentAreaConfirmed:evidence.totalApartmentAreaConfirmed}};
  const hash=createHash('sha256').update(JSON.stringify(normalized)).digest('hex');
  const result=await db.transaction(async tx=>{
    const user=await customer(tx,input.phone,true);
    const old=(await tx.query('SELECT * FROM bot_area_events WHERE event_id=$1',[input.eventId])).rows[0];
    if(old) {
      if(old.customer_id!==user.id||old.request_hash!==hash)throw new ApiError(409,'event_conflict','eventId уже использован с другими данными.');
      return {...old.result,duplicate:true};
    }
    const {q,address}=await requestForCustomer(tx,input,user.id);
    const recalculations=Number(address.verified_area)===area&&q.status==='approved'?[]:await recalculate(tx,user.id,q,address,area,input.eventId);
    await confirmArea(tx,user.id,address.id,area);
    const delta=recalculations.reduce((n:number,r:any)=>n+r.delta,0);
    await tx.query(`UPDATE quality_check_requests SET status='approved',approved_area=$2,recalculation_amount=$3,updated_at=NOW() WHERE id=$1`,[q.id,area,delta]);
    const response={customerId:user.id,qualityCheckId:q.id,addressId:address.id,confirmedArea:area,status:'approved',recalculations,duplicate:false};
    await tx.query(`INSERT INTO bot_area_events(event_id,customer_id,request_hash,result,evidence) VALUES($1,$2,$3,$4,$5)`,[input.eventId,user.id,hash,response,evidence]);
    await tx.query(`INSERT INTO audit_logs(action,entity_type,entity_id,payload) VALUES('area.confirmed_by_bot','quality_check',$1,$2)`,[q.id,{eventId:input.eventId,...response,evidence}]);
    return response;
  });
  await notifications.create({userId:result.customerId,titleRu:'Площадь подтверждена',titleKk:'Аудан расталды',
    bodyRu:`Площадь квартиры: ${area} м². ${result.recalculations.some((r:any)=>r.delta>0)?'Сформирована доплата — откройте платежи.':result.recalculations.some((r:any)=>r.bonusCredit>0)?'Разница возвращена бонусами.':'Проверка завершена.'}`,
    targetType:'quality_check',targetId:result.qualityCheckId,dedupeKey:`bot-area:${input.eventId}`});
  return result;
}
export async function botScheduleVisit(db:Database,notifications:NotificationService,input:any) {
  eventInput(input);
  const at=String(input.scheduledAt??'');
  if(![true,'true'].includes(input.customerConsent)||![true,'true'].includes(input.documentDeclined)||!/(Z|[+-]\d{2}:\d{2})$/.test(at)||!Number.isFinite(Date.parse(at)))
    throw new ApiError(400,'visit_consent_required','Нужны отказ от техплана, согласие клиента и будущая дата с часовым поясом.');
  const result=await db.transaction(async tx=>{
    const user=await customer(tx,input.phone,true);
    const hash=createHash('sha256').update(JSON.stringify({kind:'schedule_visit',phone:user.phone,qualityCheckId:input.qualityCheckId,scheduledAt:new Date(at).toISOString()})).digest('hex');
    const prior=(await tx.query('SELECT * FROM bot_area_events WHERE event_id=$1',[input.eventId])).rows[0];
    if(prior){if(prior.customer_id!==user.id||prior.request_hash!==hash)throw new ApiError(409,'event_conflict','eventId уже использован с другими данными.');return {...prior.result,duplicate:true};}
    if(Date.parse(at)<=Date.now())throw new ApiError(400,'visit_consent_required','Выберите будущее время проверки.');
    const {q,address}=await requestForCustomer(tx,input,user.id);
    if(q.status==='approved'||address.verified_area)throw new ApiError(409,'area_already_verified','Площадь уже подтверждена.');
    const firstOrder=(await tx.query(`SELECT scheduled_date::text,start_time::text,status FROM service_orders WHERE customer_id=$1 AND address_id=$2 AND status NOT IN ('cancelled','completed') ORDER BY scheduled_date,start_time LIMIT 1`,[user.id,address.id])).rows[0];
    if(firstOrder?.status==='in_progress'||(firstOrder?.scheduled_date&&firstOrder?.start_time&&Date.parse(at)>=Date.parse(`${firstOrder.scheduled_date}T${firstOrder.start_time}+05:00`)))
      throw new ApiError(409,'visit_after_cleaning','Проверка должна быть до начала уборки. Согласуйте другое время с отделом качества.');
    if(q.scheduled_at&&new Date(q.scheduled_at).getTime()!==Date.parse(at))throw new ApiError(409,'visit_already_scheduled','Визит уже согласован на другое время. Изменение согласует отдел качества.');
    const row=(await tx.query(`UPDATE quality_check_requests SET status='scheduled',scheduled_at=$2,admin_comment=concat_ws(E'\n',admin_comment,$3::text),updated_at=NOW() WHERE id=$1 RETURNING id,status,scheduled_at`,[q.id,at,q.scheduled_at?null:'Клиент через WhatsApp отказался от документа и согласовал время. Требуется назначить сотрудника отдела качества.'])).rows[0];
    await tx.query(`INSERT INTO audit_logs(action,entity_type,entity_id,payload) VALUES('quality_check.visit_requested_by_bot','quality_check',$1,$2)`,[q.id,{eventId:input.eventId,scheduledAt:at,customerConsent:true}]);
    const result={...row,customerId:user.id,controllerAssignment:'pending',message:'Время клиента передано отделу качества. Назначение сотрудника требует подтверждения отдела.'};
    await tx.query('INSERT INTO bot_area_events(event_id,customer_id,request_hash,result,evidence) VALUES($1,$2,$3,$4,$5)',[input.eventId,user.id,hash,result,{documentDeclined:true,customerConsent:true}]);
    return result;
  });
  await notifications.createAdminEvent({event:'quality_check',titleRu:'Согласовано время проверки площади',bodyRu:`Клиент предложил визит ${at}. Назначьте сотрудника и подтвердите визит.`,targetType:'quality_check',targetId:result.id,dedupeKey:`bot-quality-visit:${result.id}:${new Date(at).toISOString()}`});
  await notifications.create({userId:result.customerId,titleRu:'Запрос визита отправлен',bodyRu:'Выбранное время передано отделу качества. Ожидайте подтверждения сотрудника.',targetType:'quality_check',targetId:result.id,dedupeKey:`bot-quality-visit:${result.id}:${new Date(at).toISOString()}`});
  return result;
}
