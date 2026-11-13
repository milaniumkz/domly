import {Router} from 'express';
import {auth} from '../../common/auth';
import {asyncHandler,ok,ApiError} from '../../common/api';
import {Database} from '../../infrastructure/db/Database';
import {NotificationService} from '../../modules/domainServices';
import {randomUUID} from 'node:crypto';
import {verifyOrderingToken,auditBot} from '../../modules/botOrdering';
import {customer} from '../../modules/botIntegration';
import {checkServiceAddress,requestAddressConnection} from '../../modules/serviceCoverage';
export function serviceCoverageRouter(db:Database,notifications:NotificationService){
 const r=Router();
 r.use((req,res,next)=>{
  if(!((req.method==='POST'&&req.path==='/addresses')||(req.method==='PATCH'&&/^\/addresses\/[^/]+$/.test(req.path)))){next();return;}
  const send=res.json.bind(res);
  res.json=((body:any)=>{
   res.json=send;
   void(async()=>{
    const a=body?.data;
    if(body?.ok&&a?.id&&a.user_id===req.user?.id&&(await db.query('SELECT domly_service_zones_enforced() AS enabled')).rows[0].enabled){
     const covered=(await db.query('SELECT domly_location_in_service_zone($1,$2,$3,$4,$5) AS covered',[a.city,a.street,a.house,a.latitude,a.longitude])).rows[0].covered;
     a.service_available=covered&&a.service_status!=='needs_new_address';
     if(!covered)await requestAddressConnection(db,notifications,a.id,req.user!.id);
     else if(a.area_reverification_required)await notifications.create({userId:req.user!.id,titleRu:'Подтвердите площадь нового адреса',bodyRu:'Новый адрес сохранён. Загрузите новый технический план квартиры для подтверждения площади. Нажмите на уведомление, чтобы открыть загрузку документа.',targetType:'area_verification',targetId:a.id,dedupeKey:'new-address-plan:'+a.id+':'+new Date(a.area_invalidated_at).toISOString()});
    }
    send(body);
   })().catch(next);return res;
  }) as typeof res.json;
  next();
 });
 r.get('/addresses',auth(['customer']),asyncHandler(async(req,res)=>{ok(res,(await db.query(`SELECT a.*,CASE WHEN domly_service_zones_enforced() THEN a.service_status<>'needs_new_address' AND domly_location_in_service_zone(a.city,a.street,a.house,a.latitude,a.longitude) ELSE lower(a.city) IN ('астана','astana') END AS service_available,
 EXISTS(SELECT 1 FROM quality_check_requests q JOIN files f ON f.id=q.document_file_id WHERE q.address_id=a.id AND q.status IN ('pending','approved') AND (a.area_invalidated_at IS NULL OR f.created_at>=a.area_invalidated_at)) AS area_proof_submitted
 FROM customer_addresses a WHERE user_id=$1 ORDER BY is_primary DESC,created_at DESC`,[req.user!.id])).rows);}));
 r.use(asyncHandler(async(req,res,next)=>{
  const path=req.path,method=req.method;
  const botPurchase=method==='POST'&&path==='/integrations/moon-ai/ordering/packages';
  const botBooking=method==='POST'&&path==='/integrations/moon-ai/ordering/orders';
  const purchase=botPurchase||(method==='POST'&&path==='/packages/purchase');
  const booking=botBooking||(method==='POST'&&path==='/orders');
  const slots=method==='GET'&&path==='/scheduling/available-slots';
  const move=method==='POST'&&/^\/orders\/[^/]+\/reschedule$/.test(path);
  if(!purchase&&!booking&&!slots&&!move){next();return;}
  let user:any;
  if(botPurchase||botBooking){verifyOrderingToken(req.headers);user={...await customer(db,req.body.phone),role:'customer'};}
  else{await new Promise<void>((resolve,reject)=>auth()(req,res,(error?:any)=>error?reject(error):resolve()));user=req.user!;}
  let addressId:string|undefined;
  if(purchase)addressId=req.body.addressId;
  else if(move){const id=path.split('/')[2];addressId=(await db.query('SELECT address_id FROM service_orders WHERE id=$1 AND (customer_id=$2 OR $3::boolean)',[id,user.id,['admin','superadmin'].includes(user.role)])).rows[0]?.address_id;}
  else{const id=booking?req.body.customerPackageId:req.query.customerPackageId;addressId=id?(await db.query('SELECT address_id FROM customer_packages WHERE id=$1 AND customer_id=$2',[id,user.id])).rows[0]?.address_id:String(req.query.addressId??'')||undefined;}
  if(!addressId){next();return;}
  try{await checkServiceAddress(db,addressId,!purchase);}
  catch(error){if((botPurchase||botBooking)&&error instanceof ApiError)await auditBot(db,botPurchase?'package_purchase':'order_create',{customerId:user.id,requestId:req.header('Idempotency-Key')??randomUUID(),result:'error',code:error.code});if(error instanceof ApiError&&error.code==='outside_service_zone'&&method==='POST'){await requestAddressConnection(db,notifications,addressId,user.id);throw new ApiError(409,error.code,'Адрес вне действующих зон. Создана заявка на подключение адреса. Купить пакет или заказать уборку по этому адресу пока нельзя.');}throw error;}
  next();
 }));
 return r;
}
