import {Router} from 'express';
import path from 'node:path';
import {asyncHandler,ok,ApiError} from '../../common/api';
import {Database} from '../../infrastructure/db/Database';
import {NotificationService} from '../../modules/domainServices';
import {verifyMoonToken} from '../../modules/moonAi';
import {botCatalog,botCustomerContext,botConfirmArea,botScheduleVisit,optionalId} from '../../modules/botIntegration';
import {packageQuote} from '../../modules/packageQuote';

export function botRouter(db:Database,notifications:NotificationService) {
  const router=Router();
  router.get('/integrations/moon-ai/docs/:file',asyncHandler(async(req,res)=>{
    const files:Record<string,string>={'catalog.pdf':'domly-bot-catalog.pdf','area-verification.pdf':'domly-bot-area-verification.pdf','customer-mobile-guide.pdf':'domly-customer-mobile-guide.pdf','customer-mobile-guide.md':'domly-customer-mobile-guide.md'};
    const filename=files[String(req.params.file)];
    if(typeof filename!=='string')throw new ApiError(404,'not_found','Документ не найден.');
    res.type(filename.endsWith('.md')?'text/markdown':'application/pdf').attachment(filename).sendFile(path.resolve(__dirname,'../../../docs',filename));
  }));
  const protectedRoute=(handler:any)=>asyncHandler(async(req,res)=>{
    verifyMoonToken(req.headers);
    res.set('Cache-Control','no-store');
    ok(res,await handler(req));
  });
  router.get('/integrations/moon-ai/catalog',protectedRoute((req:any)=>botCatalog(db,req.query.area)));
  router.post('/integrations/moon-ai/catalog/quote',protectedRoute(async(req:any)=>{
    if(!optionalId(req.body.packageId))throw new ApiError(400,'package_required','Укажите packageId.');
    let addons=req.body.addonsDetailed;
    if(typeof addons==='string'){try{addons=JSON.parse(addons);}catch{throw new ApiError(400,'invalid_addons','Нужен JSON-массив допуслуг.');}}
    if(addons!==undefined&&!Array.isArray(addons))throw new ApiError(400,'invalid_addons','Нужен массив допуслуг.');
    for(const addon of addons??[])if(!optionalId(addon?.id??addon?.key))throw new ApiError(400,'invalid_addons','Укажите UUID допуслуги.');
    const quote=await packageQuote(db,{packageId:req.body.packageId,area:req.body.area,cleaningsPerMonth:req.body.cleaningsPerMonth,addonsDetailed:addons});
    return {...quote,currency:'KZT',totalPrice:quote.monthlyPrice,perCleaningAfterDiscount:Math.round(quote.monthlyPrice/quote.cleaningCount*100)/100};
  }));
  router.get('/integrations/moon-ai/customer-context',protectedRoute((req:any)=>botCustomerContext(db,req.query.phone)));
  router.post('/integrations/moon-ai/area/confirm',protectedRoute((req:any)=>botConfirmArea(db,notifications,req.body)));
  router.post('/integrations/moon-ai/area/schedule-visit',protectedRoute((req:any)=>botScheduleVisit(db,notifications,req.body)));
  return router;
}
