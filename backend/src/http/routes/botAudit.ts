import {Router} from 'express';
import {auth} from '../../common/auth';
import {asyncHandler,ok} from '../../common/api';
import {Database} from '../../infrastructure/db/Database';
import {listBotAudit,botAuditDetails} from '../../modules/botAudit';
export function botAuditRouter(db:Database){
 const router=Router();
 router.get('/admin/bot-actions',auth(['admin','superadmin']),asyncHandler(async(req,res)=>{ok(res,await listBotAudit(db,req.query));}));
 router.get('/admin/bot-actions/:id',auth(['admin','superadmin']),asyncHandler(async(req,res)=>{ok(res,await botAuditDetails(db,String(req.params.id)));}));
 return router;
}
