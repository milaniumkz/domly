import {Router} from 'express';
import {Database} from '../../infrastructure/db/Database';
import {auth} from '../../common/auth';
import {ApiError,asyncHandler,ok} from '../../common/api';
import {crmCustomer,crmStages,customerCrmList} from '../../modules/customerCrm';

export function customerCrmRouter(db:Database){
 const r=Router(),root='/admin/customer-crm';r.use(root,auth(['admin','superadmin']),(_req,res,next)=>{res.set('Cache-Control','no-store');next();});
 r.get(root,asyncHandler(async(req,res)=>{ok(res,await customerCrmList(db,req.query));}));
 r.patch(root+'/:id',asyncHandler(async(req,res)=>{
  await crmCustomer(db,String(req.params.id));const stage=req.body.stage,revision=Number(req.body.revision);
  if(!crmStages.includes(stage)||!Number.isInteger(revision)||revision<0)throw new ApiError(400,'invalid_request','Проверьте этап работы с клиентом.');
  const crm=await db.atomic(async()=>{
   await db.query('SELECT id FROM app_users WHERE id=$1 FOR UPDATE',[req.params.id]);
   const old=(await db.query('SELECT revision FROM admin_customer_crm WHERE customer_id=$1',[req.params.id])).rows[0];
   if(Number(old?.revision??0)!==revision)throw new ApiError(409,'crm_changed','Данные уже изменены другим администратором. Обновите список.');
   const row=(await db.query(`INSERT INTO admin_customer_crm(customer_id,stage,updated_by) VALUES($1,$2,$3)
    ON CONFLICT(customer_id) DO UPDATE SET stage=EXCLUDED.stage,updated_by=EXCLUDED.updated_by,updated_at=NOW(),revision=admin_customer_crm.revision+1 RETURNING *`,[req.params.id,stage,req.user!.id])).rows[0];
   await db.query("INSERT INTO audit_logs(actor_id,action,entity_type,entity_id,payload) VALUES($1,'customer.crm_stage','customer',$2,$3)",[req.user!.id,req.params.id,{stage}]);return row;
  });ok(res,crm);
 }));
 r.get(root+'/:id/notes',asyncHandler(async(req,res)=>{
  await crmCustomer(db,String(req.params.id));const limit=Number(req.query.limit??50),offset=Number(req.query.offset??0);
  if(!Number.isInteger(limit)||limit<1||limit>100||!Number.isInteger(offset)||offset<0)throw new ApiError(400,'invalid_request','Проверьте параметры заметок.');
  const notes=(await db.query(`SELECT n.*,COALESCE(a.full_name,'Администратор') author_name,COALESCE(editor.full_name,'Администратор') editor_name
   FROM admin_customer_notes n LEFT JOIN app_users a ON a.id=n.author_id LEFT JOIN app_users editor ON editor.id=n.updated_by
   WHERE n.customer_id=$1 ORDER BY n.created_at DESC,n.id DESC LIMIT $2 OFFSET $3`,[req.params.id,limit,offset])).rows;
  const total=(await db.query('SELECT COUNT(*)::int n FROM admin_customer_notes WHERE customer_id=$1',[req.params.id])).rows[0].n;ok(res,{items:notes,total});
 }));
 const save=(edit:boolean)=>asyncHandler(async(req,res)=>{
  await crmCustomer(db,String(req.params.id));const body=req.body.body;
  if(typeof body!=='string'||!body.trim()||body.trim().length>10000)throw new ApiError(400,'invalid_note','Заметка должна содержать от 1 до 10000 символов.');
  if(edit&&(!/^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$/i.test(String(req.params.noteId))||!Number.isInteger(req.body.revision)||req.body.revision<1))throw new ApiError(400,'invalid_request','Проверьте версию заметки.');
  const note=await db.atomic(async()=>{
   const row=edit?(await db.query(`UPDATE admin_customer_notes SET body=$3,updated_by=$4,updated_at=NOW(),revision=revision+1
    WHERE id=$1 AND customer_id=$2 AND revision=$5 RETURNING *`,[req.params.noteId,req.params.id,body.trim(),req.user!.id,req.body.revision])).rows[0]
    :(await db.query('INSERT INTO admin_customer_notes(customer_id,author_id,updated_by,body) VALUES($1,$2,$2,$3) RETURNING *',[req.params.id,req.user!.id,body.trim()])).rows[0];
   if(!row)throw new ApiError(409,'note_changed','Заметка уже изменена. Обновите её перед сохранением.');
   // The text is intentionally absent from audit/technical event payloads.
   await db.query("INSERT INTO audit_logs(actor_id,action,entity_type,entity_id,payload) VALUES($1,$2,'customer',$3,$4)",[req.user!.id,edit?'customer.note_updated':'customer.note_added',req.params.id,{noteId:row.id,revision:row.revision}]);return row;
  });ok(res,note,edit?200:201);
 });
 r.post(root+'/:id/notes',save(false));r.patch(root+'/:id/notes/:noteId',save(true));return r;
}
