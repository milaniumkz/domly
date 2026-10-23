const fs=require('fs'),assert=require('assert/strict');
module.exports=async({p,session,root})=>{
 assert.equal(new URL(process.env.DATABASE_URL).pathname,'/domly_audit_20261023');
 assert.ok(['localhost','127.0.0.1'].includes(new URL(process.env.DATABASE_URL).hostname));
 const {Database}=require('/workspace/domly/backend/dist/infrastructure/db/Database');
 const db=new Database(process.env.DATABASE_URL),account=JSON.parse(fs.readFileSync(root+'/private/atomic-ui-account.json'));
 assert.equal(account.user.id,session.user.id);const fn='audit_ui_cancel_failure';
 const state=async()=>({order:(await db.query('SELECT status FROM service_orders WHERE id=$1',[account.orderId])).rows[0].status,balance:Number((await db.query('SELECT bonus_balance FROM app_users WHERE id=$1',[session.user.id])).rows[0].bonus_balance),visits:(await db.query('SELECT available_cleanings FROM customer_packages WHERE id=$1',[account.customerPackageId])).rows[0].available_cleanings});
 try {
  const before=await state();assert.equal(before.balance,8000);assert.equal(before.visits,4);
  await db.query(`CREATE FUNCTION ${fn}() RETURNS trigger LANGUAGE plpgsql AS $$ BEGIN IF NEW.order_id='${account.orderId}'::uuid AND NEW.new_status='cancelled' THEN RAISE EXCEPTION 'injected cancellation failure'; END IF; RETURN NEW; END $$`);
  await db.query(`CREATE TRIGGER ${fn} BEFORE INSERT ON order_status_history FOR EACH ROW EXECUTE FUNCTION ${fn}()`);
  async function cancel(){
   await p.reload();await p.waitForTimeout(2000);await p.evaluate(()=>document.querySelector('flt-semantics-placeholder')?.click());await p.waitForTimeout(1000);
   await p.getByRole('button',{name:'Отменить',exact:true}).first().click();
   const response=p.waitForResponse(r=>r.request().method()==='POST'&&new URL(r.url()).pathname.endsWith('/orders/'+account.orderId+'/cancel'));
   await p.getByRole('button',{name:/^Да, отменить$|^Отменить уборку$|^Отменить заказ$/}).last().click();
   return await response;
  }
  assert.equal((await cancel()).status(),500);assert.deepEqual(await state(),before);await p.screenshot({path:root+'/evidence/cancel-atomicity-ui-error.png'});
  await db.query(`DROP TRIGGER ${fn} ON order_status_history`);
  assert.equal((await cancel()).status(),200);const after=await state();assert.deepEqual(after,{order:'cancelled',balance:10000,visits:5});
  assert.equal((await db.query("SELECT id FROM notifications WHERE user_id=$1 AND dedupe_key=$2",[session.user.id,'order-cancelled-'+account.orderId+'-customer'])).rows.length,1);
  await p.waitForTimeout(1000);await p.screenshot({path:root+'/evidence/cancel-atomicity-ui-success.png'});
  const result={failureHttp:500,failureLeftStateUnchanged:true,retryHttp:200,after,notificationStored:true,viaVisibleButtons:true};fs.writeFileSync(root+'/evidence/cancel-atomicity-ui.json',JSON.stringify(result,null,2));console.log(JSON.stringify(result));
 } finally {await db.query(`DROP TRIGGER IF EXISTS ${fn} ON order_status_history`);await db.query(`DROP FUNCTION IF EXISTS ${fn}()`);await db.close();}
};
