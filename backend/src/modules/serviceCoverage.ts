import {Database} from '../infrastructure/db/Database';
import {ApiError} from '../common/api';
import {NotificationService} from './domainServices';
import {ensureAssistantChat} from './moonAi';
export async function checkServiceAddress(db:Database,addressId:string,area=true){
 try{await db.query('SELECT domly_assert_service_address($1,$2)',[addressId,area]);}
 catch(error:any){if(error.code==='PZ001')throw new ApiError(409,'outside_service_zone','Адрес вне активных зон обслуживания. Можно отправить только заявку на подключение адреса.');if(error.code==='PZ002')throw new ApiError(409,'address_area_reverification_required','Заполните новый адрес и загрузите новый технический план для подтверждения площади.');throw error;}
}
export async function requestAddressConnection(db:Database,notifications:NotificationService,addressId:string,customerId:string){
 return db.atomic(async()=>{
  await db.query('SELECT pg_advisory_xact_lock(hashtextextended($1,0))',['address-connection:'+addressId]);
  const a=(await db.query('SELECT * FROM customer_addresses WHERE id=$1 AND user_id=$2',[addressId,customerId])).rows[0];if(!a)return null;
  const key='coverage:'+addressId;
  let row=(await db.query("SELECT * FROM service_address_requests WHERE customer_id=$1 AND address_place_id=$2 AND status='waiting' ORDER BY created_at DESC LIMIT 1",[customerId,key])).rows[0];
  if(row)return row;
  row=(await db.query(`INSERT INTO service_address_requests(customer_id,city,residential_complex,address,address_place_id,entrance,apartment,area,latitude,longitude)
   VALUES($1,$2,$3,$4,$5,$6,$7,$8,$9,$10) RETURNING *`,[customerId,a.city,a.residential_complex,[a.settlement,a.street,a.house].filter(Boolean).join(', '),key,a.entrance,a.apartment,a.area,a.latitude,a.longitude])).rows[0];
  await notifications.createAdminEvent({event:'address_request',titleRu:'Заявка на подключение адреса вне зоны',bodyRu:'Клиент запросил обслуживание адреса за пределами активных зон. Покупка и уборка не оформлены.',targetType:'address_request',targetId:row.id,dedupeKey:'coverage-request:'+row.id});
  return row;
 });
}
export async function invalidateServiceAddress(db:Database,notifications:NotificationService,addressId:string,customerId:string){
 return db.atomic(async()=>{
  await db.query('SELECT id FROM app_users WHERE id=$1 FOR UPDATE',[customerId]);
  await db.query('SELECT id FROM quality_check_requests WHERE address_id=$1 ORDER BY id FOR UPDATE',[addressId]);
  const a=(await db.query('SELECT * FROM customer_addresses WHERE id=$1 AND user_id=$2 FOR UPDATE',[addressId,customerId])).rows[0];if(!a)throw new ApiError(404,'not_found','Адрес не найден.');
  if(a.service_status==='needs_new_address')return {alreadyInvalidated:true};
  await db.query("UPDATE app_users SET settings=settings||'{\"requiresAddressReverification\":true}'::jsonb WHERE id=$1",[customerId]);
  await db.query("UPDATE customer_addresses SET service_status='needs_new_address',verified_area=NULL,latitude=NULL,longitude=NULL,area_reverification_required=TRUE,area_invalidated_at=NOW(),updated_at=NOW() WHERE id=$1",[addressId]);
  await db.query("UPDATE quality_check_requests SET status='rejected',admin_comment=concat_ws(E'\\n',admin_comment,'Адрес вне зоны. Нужен новый адрес и новый технический план.'),updated_at=NOW() WHERE address_id=$1 AND status IN ('pending','scheduled','approved')",[addressId]);
  await db.query("UPDATE moon_ai_outbox SET state='cancelled',failure_code='address_replacement_required',finished_at=NOW() WHERE customer_id=$1 AND kind='area_verification' AND state='pending'",[customerId]);
  const text='Ваш текущий адрес находится вне действующих зон обслуживания DomLY. Откройте приложение → Профиль → измените адрес на новый адрес в зоне обслуживания. Затем загрузите технический план нового адреса и подтвердите его площадь. До этого оформить покупку пакета и новую уборку по старому адресу нельзя. Ваш оплаченный пакет и платёж сохранены. Если новый адрес тоже вне зоны, отправьте заявку на подключение адреса.';
  await notifications.create({userId:customerId,titleRu:'Укажите новый адрес и подтвердите площадь',bodyRu:text,targetType:'address_request',targetId:addressId,dedupeKey:'replace-outside-address:'+addressId});
  const chat=await ensureAssistantChat(db,customerId);
  const outbox=(await db.query("INSERT INTO moon_ai_outbox(customer_id,chat_id,kind,dedupe_key,payload) VALUES($1,$2,'address_reverification',$3,$4) ON CONFLICT(dedupe_key) DO NOTHING RETURNING id",[customerId,chat.id,'replace-outside-address:'+addressId,{text,addressId}])).rows[0];
  await db.query("INSERT INTO audit_logs(action,entity_type,entity_id,payload) VALUES('address.outside_zone_invalidated','address',$1,$2)",[addressId,{customerId,previousVerifiedArea:a.verified_area,previousServiceStatus:a.service_status,requiresNewAddress:true,requiresFreshAreaDocument:true,whatsappOutboxId:outbox?.id??null}]);
  return {invalidated:true,notificationQueued:true,whatsappOutboxId:outbox?.id??null};
 });
}
