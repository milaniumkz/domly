import {Database} from '../infrastructure/db/Database';
import {ApiError} from '../common/api';

export function botActionTitle(action:string){
 const key=action.replace(/^bot\.moon-ai\./,'');
 const labels:Record<string,string>={catalog:'Просмотр каталога услуг','moon-ai.catalog':'Просмотр каталога услуг',quote:'Расчёт стоимости пакета','catalog.quote':'Расчёт стоимости пакета',customer:'Проверка данных клиента','moon-ai.customer-context':'Проверка данных клиента',package_purchase:'Оформление пакета и счёта',payment_verify:'Проверка оплаты',order_create:'Бронирование уборки',available_slots:'Поиск свободного времени','area.confirm':'Подтверждение площади','area.schedule-visit':'Запись на проверку площади','area.confirmed_by_bot':'Подтверждение площади','quality_check.visit_requested_by_bot':'Запись на проверку площади','payment.webhook.moon_ai_kaspi':'Получение статуса оплаты от Kaspi'};
 return labels[key]??'Действие бота';
}
export function botAuditContext(input:any){
 const out:Record<string,unknown>={};
 for(const key of ['packageId','customerPackageId','addressId','paymentId','orderId','qualityCheckId','date','startTime','scheduledAt','provider','area','cleaningsPerMonth','confirmedByCustomer']){
  const value=input?.[key];if(['string','number','boolean'].includes(typeof value))out[key]=typeof value==='string'?value.slice(0,160):value;
 }
 if(Array.isArray(input?.addonsDetailed))out.addons=input.addonsDetailed.slice(0,100).map((a:any)=>({id:a?.id,quantity:a?.quantity??1}));
 return out;
}
export function botAuditSnapshot(result:any){
 const out:any={};
 const pick=(source:any,keys:string[])=>Object.fromEntries(keys.filter(k=>source?.[k]!==undefined).map(k=>[k,source[k]]));
 if(result?.payment)out.payment=pick(result.payment,['id','status','amount','bonus_amount','provider','customer_package_id','order_id']);
 if(result?.order)out.order=pick(result.order,['id','numeric_id','status','scheduled_date','start_time','end_time','estimated_duration_minutes','cleaner_id','customer_package_id','total_amount','payable_amount']);
 if(result?.customerPackage)out.customerPackage=pick(result.customerPackage,['id','status','total_cleanings','available_cleanings','address_id']);
 if(result?.monthlyPrice!==undefined)out.quote=pick(result,['packageId','monthlyPrice','cleaningCount','area','cleaningsPerMonth','discountRate','discountPercent']);
 if(result?.readyToBook!==undefined)out.readyToBook=result.readyToBook;
 return out;
}
const uuid=(v:any)=>typeof v==='string'&&/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(v)?v:null;
function eventView(row:any){
 const errors:Record<string,string>={outside_service_zone:'Адрес вне действующих зон. Доступна только заявка на подключение.',address_area_reverification_required:'Нужно указать новый адрес и подтвердить его площадь новым техническим планом.',slot_unavailable:'На выбранное время нет свободного исполнителя.',customer_booking_overlap:'У клиента уже есть уборка в это время.',customer_not_found:'Активный клиент с таким номером не найден.',payment_required:'Пакет ещё не оплачен или не активен.',no_cleanings_left:'В пакете не осталось доступных уборок.',area_required:'Не заполнена площадь квартиры.',address_not_found:'Адрес клиента не найден.',invalid_id:'Передан неверный номер записи.',idempotency_conflict:'Номер запроса уже использован для другого действия.',idempotency_key_required:'Не указан номер запроса для защиты от повторов.',customer_consent_required:'Не передано согласие клиента.',package_terms_required:'Клиенту нужно подтвердить актуальные условия тарифа.',addons_payment_required:'Сначала нужно оплатить дополнительные услуги.',integration_not_configured:'Внешний сервис не настроен.',internal_error:'Операция не выполнена из-за ошибки сервера.',booking_from_tomorrow:'Нельзя заказать уборку на сегодня.',document_required:'Не загружен технический план квартиры.'};
 const p=row.payload??{};
 return {id:row.id,title:botActionTitle(row.action),createdAt:row.created_at,result:p.result??'success',resultLabel:p.result==='error'?'Ошибка':p.replay?'Повтор запроса':'Выполнено',errorCode:p.code??null,errorMessage:p.result==='error'?(errors[p.code]??'Бот не смог завершить действие. Требуется проверка.') :null,requestId:p.requestId??null,
 customer:row.customer_id?{id:row.customer_id,name:row.customer_name??'Клиент',phone:row.customer_phone??null}:null,
 amount:row.action_amount??p.snapshot?.payment?.amount??p.snapshot?.quote?.monthlyPrice??null,entityType:row.entity_type,entityId:row.entity_id};
}
const base=`FROM audit_logs a LEFT JOIN bot_ordering_requests r ON r.request_key=a.payload->>'requestId'
 LEFT JOIN app_users u ON u.id::text=COALESCE(a.payload->>'customerId',r.customer_id::text)
 LEFT JOIN payments pay ON pay.id::text=CASE WHEN a.entity_type='payment' THEN a.entity_id ELSE COALESCE(a.payload#>>'{snapshot,payment,id}',r.response#>>'{payment,id}') END`;
const columns=`a.*,u.id AS customer_id,NULLIF(u.full_name,'') AS customer_name,u.phone AS customer_phone,
 COALESCE(a.payload#>>'{snapshot,payment,amount}',a.payload#>>'{snapshot,quote,monthlyPrice}',r.response#>>'{payment,amount}',pay.amount::text) AS action_amount`;
export async function listBotAudit(db:Database,query:any){
 const limit=Math.min(100,Math.max(1,Math.trunc(Number(query.limit)||30))),offset=Math.min(1000000,Math.max(0,Math.trunc(Number(query.offset)||0)));
 const search=String(query.search??'').slice(0,200);
 const known=['catalog','moon-ai.catalog','quote','catalog.quote','customer','moon-ai.customer-context','package_purchase','payment_verify','order_create','available_slots','area.confirm','area.schedule-visit','area.confirmed_by_bot','quality_check.visit_requested_by_bot','payment.webhook.moon_ai_kaspi'];
 const matching=known.map(a=>a.startsWith('payment.')||a.endsWith('_by_bot')?a:'bot.moon-ai.'+a).filter(a=>botActionTitle(a).toLowerCase().replace(/ё/g,'е').includes(search.toLowerCase().replace(/ё/g,'е')));
 const rows=(await db.query(`SELECT ${columns} ${base} WHERE a.actor_id IS NULL AND a.payload->>'actorKind'='bot'
 AND ($1::text='' OR u.full_name ILIKE $2 OR u.phone ILIKE $2 OR a.entity_id ILIKE $2 OR a.payload->>'requestId' ILIKE $2 OR a.action ILIKE $2 OR a.action=ANY($5::text[]))
 ORDER BY a.created_at DESC,a.id DESC LIMIT $3 OFFSET $4`,[search,'%'+search+'%',limit,offset,matching])).rows;
 return rows.map(eventView);
}
export async function botAuditDetails(db:Database,id:string){
 if(!uuid(id))throw new ApiError(400,'invalid_id','Некорректный номер записи.');
 const row=(await db.query(`SELECT ${columns},r.response AS replay_response ${base} WHERE a.id=$1 AND a.actor_id IS NULL AND a.payload->>'actorKind'='bot'`,[id])).rows[0];
 if(!row)throw new ApiError(404,'not_found','Запись бота не найдена.');
 const payload=row.payload??{},response=row.replay_response??{},snapshot=payload.snapshot??botAuditSnapshot(response),context=payload.context??{};
 let customerId=uuid(row.customer_id??payload.customerId);
 const owned=async(table:string,columns:string,id:any)=>{
  if(!uuid(id))return null;
  return (await db.query(`SELECT ${columns} FROM ${table} WHERE id=$1 AND ($2::uuid IS NULL OR customer_id=$2)`,[id,customerId])).rows[0]??null;
 };
 const orderId=row.entity_type==='order'?row.entity_id:response.order?.id??snapshot.order?.id??context.orderId;
 const paymentId=row.entity_type==='payment'?row.entity_id:response.payment?.id??snapshot.payment?.id??context.paymentId;
 const payment=await owned('payments','id,customer_id,customer_package_id,order_id,amount,bonus_amount,status,provider,created_at,paid_at',paymentId);
 const order=await owned('service_orders','id,numeric_id,customer_id,customer_package_id,address_id,cleaner_id,scheduled_date,start_time,end_time,estimated_duration_minutes,status,total_amount,addon_amount,payable_amount',orderId??payment?.order_id);
 customerId=customerId??payment?.customer_id??order?.customer_id??null;
 const packageId=response.customerPackage?.id??snapshot.customerPackage?.id??order?.customer_package_id??payment?.customer_package_id??context.customerPackageId;
 const purchase=await owned('customer_packages','id,customer_id,package_id,address_id,purchase_payment_id,total_cleanings,available_cleanings,status,period_start,period_end,purchase_config',packageId);
 const customer=customerId?(await db.query('SELECT id,full_name AS name,phone FROM app_users WHERE id=$1',[customerId])).rows[0]:null;
 const addressId=order?.address_id??purchase?.address_id??uuid(context.addressId);
 const address=addressId&&customerId?(await db.query('SELECT id,city,settlement,street,house,apartment,area,verified_area FROM customer_addresses WHERE id=$1 AND user_id=$2',[addressId,customerId])).rows[0]:null;
 const cleaner=order?.cleaner_id?(await db.query('SELECT id,full_name AS name,phone FROM app_users WHERE id=$1',[order.cleaner_id])).rows[0]:null;
 const packagePayment=purchase?.purchase_payment_id&&purchase.purchase_payment_id!==payment?.id?await owned('payments','id,amount,bonus_amount,status,provider,created_at,paid_at',purchase.purchase_payment_id):null;
 const tariffId=purchase?.package_id??uuid(context.packageId);
 const tariff=tariffId?(await db.query('SELECT id,name_ru,cleaning_count,months FROM catalog_packages WHERE id=$1',[tariffId])).rows[0]:null;
 const addons=order?(await db.query('SELECT a.title_ru AS name,oa.quantity,oa.price,oa.payment_status,oa.paid_separately FROM order_addons oa LEFT JOIN catalog_addons a ON a.id=oa.addon_id WHERE oa.order_id=$1',[order.id])).rows:[];
 const requestedAddons=[];
 for(const addon of context.addons??[]){if(uuid(addon.id)){const item=(await db.query('SELECT title_ru AS name FROM catalog_addons WHERE id=$1',[addon.id])).rows[0];requestedAddons.push({name:item?.name??'Дополнительная услуга',quantity:addon.quantity});}}
 return {addons,requestedAddons,event:{...eventView(row),customer:customer??null},context,snapshot,customer:customer??null,address:address??null,cleaner:cleaner??null,order,payment,packagePayment,
 package:purchase?{id:purchase.id,name:purchase.purchase_config?.packageSnapshot?.name_ru??tariff?.name_ru,totalCleanings:purchase.total_cleanings,availableCleanings:purchase.available_cleanings,status:purchase.status,periodStart:purchase.period_start,periodEnd:purchase.period_end}:null,
 tariff:tariff??null,detailsAvailable:Object.keys(context).length>0||Object.keys(snapshot).length>0||!!order||!!payment||!!purchase,
 note:!Object.keys(context).length&&!Object.keys(snapshot).length?'Для этой старой записи параметры запроса не сохранялись. Показаны только достоверно связанные данные.':null};
}
