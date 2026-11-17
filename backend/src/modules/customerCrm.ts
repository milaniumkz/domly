import {Database} from '../infrastructure/db/Database';
import {ApiError} from '../common/api';

export const crmStages=['new','working','purchased','refused','processed'];
export async function crmCustomer(db:Database,id:string){
 if(!/^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$/i.test(id))throw new ApiError(400,'invalid_id','Укажите ID клиента.');
 const user=(await db.query("SELECT id,full_name,phone FROM app_users WHERE id=$1 AND role='customer'",[id])).rows[0];
 if(!user)throw new ApiError(404,'customer_not_found','Клиент не найден.');return user;
}
export async function customerCrmList(db:Database,q:Record<string,unknown>){
 const limit=Number(q.limit??30),offset=Number(q.offset??0),stage=String(q.stage??'all'),account=String(q.account??'all'),purchase=String(q.purchase??'all'),area=String(q.area??'all'),notes=String(q.notes??'all'),profile=String(q.profile??'all'),sort=String(q.sort??'newest');
 const order:Record<string,string>={newest:'created_at DESC,id DESC',oldest:'created_at,id',name:'full_name NULLS LAST,id',spent:'paid_total DESC,id',activity:'crm_updated_at DESC NULLS LAST,id'};
 if(!Number.isInteger(limit)||limit<1||limit>200||!Number.isInteger(offset)||offset<0||!['all',...crmStages].includes(stage)||!['all','active','blocked','deleted','deleted_paid'].includes(account)||!['all','paid','pending','cancelled','never_paid','none'].includes(purchase)||!['all','verified','unverified','missing'].includes(area)||!['all','with','without'].includes(notes)||!['all','filled','new'].includes(profile)||!order[sort])throw new ApiError(400,'invalid_request','Проверьте фильтры клиентов.');
 const values:unknown[]=[limit,offset],filters=["u.role='customer'"];const bind=(v:unknown)=>{values.push(v);return '$'+values.length;};
 for(const [key,op] of [['dateFrom','>='],['dateTo','<=']])if(q[key]){const d=new Date(String(q[key]));if(!Number.isFinite(d.getTime()))throw new ApiError(400,'invalid_request','Проверьте даты регистрации.');filters.push(`u.created_at ${op} ${bind(d.toISOString())}::timestamptz`);}
 const search=String(q.search??'').trim();if(search){const needle=bind('%'+search+'%');filters.push(`(concat_ws(' ',u.full_name,u.phone,u.email,u.numeric_id::text,a.city,a.street,a.house,a.apartment) ILIKE ${needle} OR EXISTS(SELECT 1 FROM admin_customer_notes search_note WHERE search_note.customer_id=u.id AND search_note.body ILIKE ${needle}))`);}
 const addressFilters=['loc.user_id=u.id'];
 if(q.city)addressFilters.push(`loc.city ILIKE ${bind('%'+String(q.city).trim()+'%')}`);
 if(q.house)addressFilters.push(`concat_ws(' ',loc.street,loc.house) ILIKE ${bind('%'+String(q.house).trim()+'%')}`);
 if(area==='verified')addressFilters.push('loc.verified_area>0');
 if(area==='unverified')addressFilters.push("trim(loc.street)<>'' AND trim(loc.house)<>'' AND COALESCE(loc.verified_area,0)<=0");
 if(addressFilters.length>1)filters.push(`EXISTS(SELECT 1 FROM customer_addresses loc WHERE ${addressFilters.join(' AND ')})`);
 if(account==='active')filters.push("u.deleted_at IS NULL AND u.status<>'blocked'");
 if(account==='blocked')filters.push("u.status='blocked'");if(account.startsWith('deleted'))filters.push('u.deleted_at IS NOT NULL');if(account==='deleted_paid')filters.push('COALESCE(pay.paid_count,0)>0');
 if(stage!=='all')filters.push(`COALESCE(crm.stage,CASE WHEN COALESCE(pay.paid_count,0)>0 THEN 'purchased' ELSE 'new' END)=${bind(stage)}`);
 const hasAddress="EXISTS(SELECT 1 FROM customer_addresses loc WHERE loc.user_id=u.id AND trim(loc.street)<>'' AND trim(loc.house)<>'')";
 const verified='EXISTS(SELECT 1 FROM customer_addresses loc WHERE loc.user_id=u.id AND loc.verified_area>0)';
 if(area==='missing')filters.push('NOT '+hasAddress);
 if(profile==='filled')filters.push("COALESCE(trim(u.full_name),'')<>'' AND "+hasAddress);if(profile==='new')filters.push("COALESCE(trim(u.full_name),'')=''");
 if(purchase==='paid')filters.push('COALESCE(pay.paid_count,0)>0');if(purchase==='never_paid')filters.push('COALESCE(pay.paid_count,0)=0');if(purchase==='pending')filters.push('COALESCE(pay.pending_count,0)>0');if(purchase==='cancelled')filters.push('COALESCE(pay.cancelled_count,0)>0');if(purchase==='none')filters.push('COALESCE(pk.package_count,0)=0 AND COALESCE(pay.total_count,0)=0');
 if(notes==='with')filters.push('COALESCE(nt.notes_count,0)>0');if(notes==='without')filters.push('COALESCE(nt.notes_count,0)=0');
 for(const [key,op] of [['paidMin','>='],['paidMax','<=']])if(q[key]!==undefined&&q[key]!==''){const n=Number(q[key]);if(!Number.isFinite(n)||n<0)throw new ApiError(400,'invalid_request','Проверьте сумму оплат.');filters.push(`COALESCE(pay.paid_total,0) ${op} ${bind(n)}`);}
 return (await db.query(`WITH pay AS (
  SELECT customer_id,COUNT(*) total_count,COUNT(*) FILTER(WHERE status='paid') paid_count,COALESCE(SUM(amount+bonus_amount) FILTER(WHERE status='paid'),0) paid_total,
   COUNT(*) FILTER(WHERE status IN ('pending','invoice_requested')) pending_count,COUNT(*) FILTER(WHERE status='cancelled') cancelled_count
  FROM payments GROUP BY customer_id
 ), nt AS (SELECT customer_id,COUNT(*)::int notes_count,MAX(updated_at) notes_updated_at FROM admin_customer_notes GROUP BY customer_id),
 pk AS (SELECT cp.customer_id,COUNT(*) package_count,
  COUNT(*) FILTER(WHERE EXISTS(SELECT 1 FROM payments p WHERE p.customer_package_id=cp.id AND p.status IN ('paid','refunded')))::int paid_package_count,
  COALESCE(SUM(cp.available_cleanings) FILTER(WHERE cp.status IN ('active','frozen') AND EXISTS(SELECT 1 FROM payments p WHERE p.customer_package_id=cp.id AND p.status='paid')),0) remaining_paid_cleanings,
  ARRAY_AGG(DISTINCT COALESCE(cp.purchase_config#>>'{packageSnapshot,name_ru}',pkg.name_ru)) package_names
  FROM customer_packages cp LEFT JOIN catalog_packages pkg ON pkg.id=cp.package_id GROUP BY cp.customer_id),
 matching AS MATERIALIZED (SELECT u.id,u.numeric_id,u.full_name,u.phone,u.email,u.status,u.created_at,u.updated_at,u.deleted_at,(SELECT MAX(d.restore_until) FROM account_deletion_requests d WHERE d.user_id=u.id AND d.restored_at IS NULL AND d.anonymized_at IS NULL) restore_until,u.bonus_balance,
   a.city,a.street,a.house,a.apartment,a.entrance,a.floor,a.residential_complex,a.area,a.verified_area,concat_ws(', ',a.city,a.street,a.house,a.apartment) address,
   COALESCE(pay.paid_total,0) paid_total,COALESCE(pay.paid_count,0) paid_count,COALESCE(pay.pending_count,0) pending_count,COALESCE(pay.cancelled_count,0) cancelled_count,
   COALESCE(pk.paid_package_count,0) paid_package_count,COALESCE(pk.remaining_paid_cleanings,0) remaining_paid_cleanings,COALESCE(pk.package_names,ARRAY[]::text[]) package_names,
   COALESCE(crm.stage,CASE WHEN COALESCE(pay.paid_count,0)>0 THEN 'purchased' ELSE 'new' END) crm_stage,COALESCE(crm.revision,0) crm_revision,
   GREATEST(crm.updated_at,nt.notes_updated_at) crm_updated_at,COALESCE(nt.notes_count,0) notes_count
  FROM app_users u LEFT JOIN pay ON pay.customer_id=u.id LEFT JOIN pk ON pk.customer_id=u.id LEFT JOIN nt ON nt.customer_id=u.id LEFT JOIN admin_customer_crm crm ON crm.customer_id=u.id
  LEFT JOIN LATERAL(SELECT * FROM customer_addresses WHERE user_id=u.id ORDER BY is_primary DESC,updated_at DESC,id LIMIT 1) a ON TRUE
  WHERE ${filters.join(' AND ')}), visible AS(SELECT * FROM matching ORDER BY ${order[sort]} LIMIT $1 OFFSET $2), details AS (
  SELECT v.*,(SELECT COALESCE(jsonb_agg(to_jsonb(loc)),'[]'::jsonb) FROM customer_addresses loc WHERE loc.user_id=v.id) addresses,latest.preview latest_note FROM visible v LEFT JOIN LATERAL(SELECT LEFT(body,200) preview FROM admin_customer_notes WHERE customer_id=v.id ORDER BY created_at DESC,id DESC LIMIT 1) latest ON TRUE
 ) SELECT (SELECT COUNT(*)::int FROM matching) total,(SELECT COUNT(*)::int FROM matching WHERE paid_count>0) paid_customers,
 (SELECT COUNT(*)::int FROM matching WHERE notes_count>0) customers_with_notes,
 COALESCE(jsonb_agg(to_jsonb(d) ORDER BY ${order[sort]}) FILTER(WHERE d.id IS NOT NULL),'[]') items FROM details d`,values)).rows[0];
}
