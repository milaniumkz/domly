const fs=require('fs'),assert=require('assert/strict');
module.exports=async({p,local,session,fixture,root})=>{
 assert.equal(new URL(process.env.DATABASE_URL).pathname,'/domly_audit_20261023');
 const {Database}=require('/workspace/domly/backend/dist/infrastructure/db/Database');
 const {signAccessToken}=require('/workspace/domly/backend/dist/common/auth');
 const db=new Database(process.env.DATABASE_URL);
 const account=JSON.parse(fs.readFileSync(root+'/private/atomic-ui-account.json'));
 assert.equal(account.user.id,session.user.id);
 try {
  await db.query("UPDATE service_orders SET status='assigned',cleaner_id=$2 WHERE id=$1",[account.orderId,fixture.accounts[1].user.id]);
  await db.query("INSERT INTO order_addons(order_id,addon_id,quantity,price,payment_status) VALUES($1,$2,1,2000,'pending')",[account.orderId,fixture.addon]);
  const paidBefore=(await db.query("SELECT count(*)::int AS n FROM order_addons WHERE order_id=$1 AND payment_status='paid'",[account.orderId])).rows[0].n;
  const foreign=fixture.accounts[0].user;assert.notEqual(foreign.id,session.user.id);
  const response=await local.post('http://127.0.0.1:8082/api/v1/orders/'+account.orderId+'/addon-requests/reject',{headers:{Authorization:'Bearer '+signAccessToken(foreign)},data:{}});
  assert.equal(response.status(),404);
  assert.equal((await db.query("SELECT count(*)::int AS n FROM order_addons WHERE order_id=$1 AND payment_status='pending'",[account.orderId])).rows[0].n,1);
  await p.reload();await p.waitForTimeout(2500);await p.evaluate(()=>document.querySelector('flt-semantics-placeholder')?.click());await p.waitForTimeout(1500);
  await p.getByText('Согласование доп. услуг',{exact:true}).waitFor();
  await p.screenshot({path:root+'/evidence/addon-request-ui-after.png'});
  const reject=p.waitForResponse(r=>r.request().method()==='POST'&&new URL(r.url()).pathname==='/api/v1/orders/'+account.orderId+'/addon-requests/reject');
  await p.getByRole('button',{name:'Отклонить',exact:true}).click();
  assert.equal((await reject).status(),200);
  await p.getByText('Доп. услуги отклонены',{exact:true}).waitFor();
  await p.getByText('Согласование доп. услуг',{exact:true}).waitFor({state:'hidden',timeout:10000});
  assert.equal((await db.query("SELECT count(*)::int AS n FROM order_addons WHERE order_id=$1 AND payment_status='pending'",[account.orderId])).rows[0].n,0);
  assert.equal((await db.query("SELECT count(*)::int AS n FROM order_addons WHERE order_id=$1 AND payment_status='paid'",[account.orderId])).rows[0].n,paidBefore);
  await p.screenshot({path:root+'/evidence/addon-rejection-ui-success.png'});
  const result={foreignRejected:404,foreignRequestChangedNothing:true,proposalVisible:true,ownerClickedReject:200,pendingAfter:0,paidPreserved:paidBefore};
  fs.writeFileSync(root+'/evidence/addon-rejection-ui.json',JSON.stringify(result,null,2));console.log(JSON.stringify(result));
 }finally{await db.close();}
};
