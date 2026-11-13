import {Router} from 'express';
import {asyncHandler,ok,ApiError} from '../../common/api';
import {Database} from '../../infrastructure/db/Database';
import {customer,optionalId,botCatalog,botCustomerContext} from '../../modules/botIntegration';
import {packageQuote} from '../../modules/packageQuote';
import {verifyOrderingToken,orderingOperation,auditBot} from '../../modules/botOrdering';
import {pendingBookingCount} from '../../modules/botBookingCapacity';
import {randomUUID} from 'node:crypto';

type Operations={purchasePackage:(req:any)=>Promise<any>;createOrder:(req:any)=>Promise<any>;availableSlots:(req:any)=>Promise<any>;verifyPayment:(payment:any)=>Promise<any>};
export function botOrderingRouter(db:Database,ops:Operations){
 const router=Router(),prefix='/integrations/moon-ai/ordering';
 router.use(prefix,(req,res,next)=>{try{verifyOrderingToken(req.headers);res.set('Cache-Control','no-store');next();}catch(error){next(error);}});
 const route=(name:string,work:(req:any,user:any)=>Promise<any>,mutating=false)=>asyncHandler(async(req,res)=>{
   let user:any;const requestId=randomUUID();
   try{
     if(name!=='catalog')user=await customer(db,req.method==='GET'?req.query.phone:req.body.phone);
     const run=()=>work(req,user);
     const data=mutating?await orderingOperation(db,name,req.body,req.header('Idempotency-Key'),run,user?.id):await run();
     if(!mutating)await auditBot(db,name,{customerId:user?.id,requestId,result:'success'});
     ok(res,data);
   }catch(error){
     // orderingOperation logs failures after rollback; customer lookup failures also remain visible.
     if(!mutating||!user)await auditBot(db,name,{customerId:user?.id,requestId,result:'error',code:error instanceof ApiError?error.code:'internal_error'});
     throw error;
   }
 });
 const context=(req:any,user:any,body:any)=>({body,query:req.query,botOrdering:true,user:{id:user.id,phone:user.phone,role:'customer'},ip:req.ip});
 const id=(value:unknown)=>{const result=optionalId(value);if(!result)throw new ApiError(400,'invalid_id','Укажите UUID.');return result;};
 router.get(prefix+'/catalog',route('catalog',req=>botCatalog(db,req.query.area)));
 router.get(prefix+'/customer',route('customer',req=>botCustomerContext(db,req.query.phone)));
 router.post(prefix+'/quote',route('quote',async(req,user)=>{
   const address=(await db.query('SELECT * FROM customer_addresses WHERE id=$1 AND user_id=$2',[id(req.body.addressId),user.id])).rows[0];
   if(!address)throw new ApiError(404,'address_not_found','Адрес клиента не найден.');
   return packageQuote(db,{packageId:id(req.body.packageId),area:Number(address.area),customerId:user.id,cleaningsPerMonth:req.body.cleaningsPerMonth,addonsDetailed:req.body.addonsDetailed});
 }));
 router.post(prefix+'/packages',route('package_purchase',async(req,user)=>{
   if(req.body.confirmedByCustomer!==true)throw new ApiError(400,'customer_consent_required','Получите согласие клиента на тариф, адрес и сумму.');
   const provider=req.body.provider??'kaspi';
   if(!['kaspi','bcc'].includes(provider))throw new ApiError(400,'invalid_provider','Выберите kaspi или bcc.');
   const result=await ops.purchasePackage(context(req,user,{packageId:id(req.body.packageId),addressId:id(req.body.addressId),cleaningsPerMonth:req.body.cleaningsPerMonth,addonsDetailed:req.body.addonsDetailed,acceptedTermsVersion:req.body.acceptedTermsVersion,provider,invoicePhone:user.phone,paymentMethod:provider==='bcc'?'online':'kaspi',useBonus:false}));
   const payment=(await db.query('SELECT * FROM payments WHERE id=$1',[result.payment.id])).rows[0];
   return {...result,payment,createdBy:'bot',bot:'MooonAI'};
 },true));
 router.post(prefix+'/payments/verify',route('payment_verify',async(req,user)=>{
   let payment=(await db.query('SELECT * FROM payments WHERE id=$1 AND customer_id=$2',[id(req.body.paymentId),user.id])).rows[0];
   if(!payment)throw new ApiError(404,'not_found','Платёж клиента не найден.');
   // Only existing trusted provider callbacks / a BCC bank query can make it paid.
   payment=await ops.verifyPayment(payment);
   const purchase=payment.customer_package_id?(await db.query('SELECT id,status,available_cleanings FROM customer_packages WHERE id=$1 AND customer_id=$2',[payment.customer_package_id,user.id])).rows[0]:null;
   return {payment:{id:payment.id,status:payment.status,provider:payment.provider},customerPackage:purchase,readyToBook:payment.status==='paid'&&purchase?.status==='active',source:payment.provider==='bcc'?'bank_status':'trusted_payment_callback'};
 },true));
 router.get(prefix+'/slots',route('available_slots',async(req,user)=>{
   const purchase=(await db.query('SELECT id,address_id FROM customer_packages WHERE id=$1 AND customer_id=$2 AND status=\'active\'',[id(req.query.customerPackageId),user.id])).rows[0];
   if(!purchase)throw new ApiError(402,'payment_required','Нужен оплаченный активный пакет клиента.');
   const slots=await ops.availableSlots({...context(req,user,{}),query:{date:req.query.date,customerPackageId:purchase.id,addressId:purchase.address_id,addonsDetailed:req.query.addonsDetailed}});
   const result=[];
   for(const slot of slots){const count=Math.max(0,slot.cleanersCount-await pendingBookingCount(db,String(req.query.date),slot.startTime,slot.durationMinutes));if(count>0)result.push({...slot,cleanersCount:count});}
   return result;
 }));
 router.post(prefix+'/orders',route('order_create',async(req,user)=>{
   if(req.body.confirmedByCustomer!==true)throw new ApiError(400,'customer_consent_required','Получите согласие клиента на дату и время.');
   return ops.createOrder(context(req,user,{customerPackageId:id(req.body.customerPackageId),date:req.body.date,startTime:req.body.startTime,addonsDetailed:req.body.addonsDetailed}));
 },true));
 return router;
}
