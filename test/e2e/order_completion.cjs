const fs=require('fs'),assert=require('assert/strict');
module.exports=async({p,root,session})=>{
assert.equal(new URL(process.env.DATABASE_URL).pathname,'/domly_audit_20261023');
const {Database}=require('/workspace/domly/backend/dist/infrastructure/db/Database');const db=new Database(process.env.DATABASE_URL),fn='audit_ui_order_completion';
const state=async()=>({orders:Number((await db.query('SELECT count(*)::int AS n FROM service_orders WHERE customer_id=$1',[session.user.id])).rows[0].n),visits:(await db.query('SELECT available_cleanings FROM customer_packages WHERE customer_id=$1',[session.user.id])).rows[0].available_cleanings});
try{
 const before=await state();
 const card=p.getByRole('button',{name:/^Текущая подписка/}).first();await card.scrollIntoViewIfNeeded();await card.click();
 await p.getByText('Календарь уборок',{exact:true}).waitFor();
 await p.getByRole('button',{name:/^28,.*октября/}).click();
 await p.getByText('Выберите время',{exact:true}).waitFor();await p.getByText(/^08:00/).first().click();
 await p.getByRole('button',{name:'Без допов',exact:true}).click();
 await db.query(`CREATE FUNCTION ${fn}() RETURNS trigger LANGUAGE plpgsql AS $$ BEGIN IF NEW.scope='order_create' AND NEW.user_id='${session.user.id}'::uuid AND NEW.status_code=201 THEN RAISE EXCEPTION 'injected completion failure'; END IF; RETURN NEW; END $$`);
 await db.query(`CREATE TRIGGER ${fn} BEFORE UPDATE ON api_idempotency FOR EACH ROW EXECUTE FUNCTION ${fn}()`);
 const submit=async()=>{const response=p.waitForResponse(r=>r.request().method()==='POST'&&new URL(r.url()).pathname==='/api/v1/orders');await p.getByRole('button',{name:'Подтвердить выбранную дату',exact:true}).click();return response;};
 assert.equal((await submit()).status(),500);assert.deepEqual(await state(),before);await p.screenshot({path:root+'/evidence/order-completion-ui-error.png'});
 await db.query(`DROP TRIGGER ${fn} ON api_idempotency`);
 await p.waitForTimeout(700);const response=await submit();assert.equal(response.status(),201);const body=await response.json();const after=await state();assert.equal(after.orders,before.orders+1);assert.equal(after.visits,before.visits-1);
 const recorded=(await db.query("SELECT response,status_code FROM api_idempotency WHERE user_id=$1 AND scope='order_create' AND response->'data'->'order'->>'id'=$2",[session.user.id,body.data.order.id])).rows;assert.equal(recorded.length,1);assert.equal(recorded[0].status_code,201);
 await p.waitForTimeout(1500);await p.screenshot({path:root+'/evidence/order-completion-ui-success.png'});
 const result={failureHttp:500,unchangedAfterFailure:true,retryHttp:201,before,after,replayResponseStored:true,viaVisibleButtons:true};fs.writeFileSync(root+'/evidence/order-completion-ui.json',JSON.stringify(result,null,2));console.log(result);
}finally{await db.query(`DROP TRIGGER IF EXISTS ${fn} ON api_idempotency`);await db.query(`DROP FUNCTION IF EXISTS ${fn}()`);await db.close();}
};
