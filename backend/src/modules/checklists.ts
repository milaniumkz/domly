import {Database} from '../infrastructure/db/Database';
import {ApiError} from '../common/api';
export const defaultRequiredTasks = ['Протереть пыль','Пропылесосить','Вымыть пол','Очистить кухню','Очистить санузел'];
export async function ensureChecklistReport(db: Database, order: any) {
  return db.transaction(async tx=>{
    await tx.query('SELECT id FROM service_orders WHERE id=$1 FOR UPDATE',[order.id]);
    const existing=(await tx.query('SELECT * FROM checklist_reports WHERE order_id=$1 ORDER BY created_at LIMIT 1',[order.id])).rows[0];
    if(existing && (existing.requirements_initialized || ['completed','cancelled'].includes(order.status))) return existing;
    const report=existing ?? (await tx.query("INSERT INTO checklist_reports(order_id,cleaner_id,status) VALUES($1,$2,'open') RETURNING *",[order.id,order.cleaner_id??null])).rows[0];
    const templates=(await tx.query(`SELECT i.title_ru,i.title_kk FROM checklist_templates t JOIN checklist_template_items i ON i.template_id=t.id WHERE t.active AND (t.package_id=$1 OR t.package_id IS NULL) ORDER BY i.sort_order,i.id`,[order.package_id??null])).rows;
    const required=templates.length?templates:defaultRequiredTasks.map(title_ru=>({title_ru,title_kk:null}));
    const addons=(await tx.query(`SELECT 'Доп. услуга: '||a.title_ru AS title_ru,a.title_kk FROM order_addons oa JOIN catalog_addons a ON a.id=oa.addon_id WHERE oa.order_id=$1 AND oa.payment_status='paid'`,[order.id])).rows;
    const saved=(await tx.query('SELECT * FROM checklist_report_items WHERE report_id=$1',[report.id])).rows;
    if(existing)await tx.query('UPDATE checklist_report_items SET required=FALSE WHERE report_id=$1',[report.id]);
    const seen=new Set<string>();
    for(const item of [...required,...addons]) {
      if(seen.has(item.title_ru))continue;seen.add(item.title_ru);
      const match=saved.find((row:any)=>row.title_ru===item.title_ru || row.title_ru===item.title_ru.replace(/^Доп\. услуга: /,''));
      if(match)await tx.query('UPDATE checklist_report_items SET required=TRUE,title_ru=$2,title_kk=$3 WHERE id=$1',[match.id,item.title_ru,item.title_kk]);
      else await tx.query('INSERT INTO checklist_report_items(report_id,title_ru,title_kk,required) VALUES($1,$2,$3,TRUE)',[report.id,item.title_ru,item.title_kk]);
    }
    return (await tx.query('UPDATE checklist_reports SET requirements_initialized=TRUE WHERE id=$1 RETURNING *',[report.id])).rows[0];
  });
}
export async function saveChecklist(db:Database, order:any, actor:string, titles:string[], note:string) {
  const report=await ensureChecklistReport(db,order);
  return db.transaction(async tx=>{
    const state=(await tx.query('SELECT status FROM service_orders WHERE id=$1 FOR UPDATE',[order.id])).rows[0];
    if(!['assigned','start_pending','in_progress'].includes(state?.status))throw new ApiError(409,'invalid_transition','Чек-лист завершённого заказа нельзя изменить.');
    const rows=(await tx.query('SELECT * FROM checklist_report_items WHERE report_id=$1 FOR UPDATE',[report.id])).rows;
    const selected=new Set(titles.map(t=>t.trim()).filter(Boolean));
    // The UI sends addon titles without the display prefix.
    for (const row of rows) {
      const bare = row.title_ru.replace(/^Доп\. услуга: /, '');
      if (selected.has(bare) || (row.title_kk && selected.has(row.title_kk))) selected.add(row.title_ru);
    }
    await tx.query(`UPDATE checklist_report_items SET checked=(title_ru=ANY($2::text[]) OR COALESCE(title_kk=ANY($2::text[]),FALSE)), checked_at=CASE WHEN title_ru=ANY($2::text[]) OR title_kk=ANY($2::text[]) THEN NOW() ELSE NULL END WHERE report_id=$1`,[report.id,[...selected]]);
    for(const title of selected)if(!rows.some((r:any)=>r.title_ru===title||r.title_kk===title||r.title_ru.replace(/^Доп\. услуга: /,'')===title))await tx.query('INSERT INTO checklist_report_items(report_id,title_ru,checked,checked_at,required) VALUES($1,$2,TRUE,NOW(),FALSE)',[report.id,title]);
    const missing=(await tx.query('SELECT id FROM checklist_report_items WHERE report_id=$1 AND required AND NOT checked',[report.id])).rows.length;
    return (await tx.query('UPDATE checklist_reports SET status=$2,cleaner_id=COALESCE($3,cleaner_id),note=$4,updated_at=NOW() WHERE id=$1 RETURNING *',[report.id,missing?'open':'completed',actor,note])).rows[0];
  });
}
