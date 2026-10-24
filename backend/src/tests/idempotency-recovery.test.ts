import test from 'node:test';
import assert from 'node:assert/strict';
import {randomUUID} from 'node:crypto';
import express from 'express';
import {Database} from '../infrastructure/db/Database';
import {idempotent,idempotentTransaction} from '../common/idempotency';
import {ApiError,asyncHandler,errorHandler,ok} from '../common/api';

test('late failure cannot overwrite a successfully recovered request', {skip:!process.env.DOMLY_INTEGRATION_DATABASE_URL}, async()=>{
  const db=new Database(process.env.DOMLY_INTEGRATION_DATABASE_URL!);
  const user=randomUUID(),key=randomUUID();let calls=0;
  let releaseFailure!:()=>void, failureWaiting!:()=>void;
  const waiting=new Promise<void>(resolve=>{failureWaiting=resolve;});
  const release=new Promise<void>(resolve=>{releaseFailure=resolve;});
  const original=db.query.bind(db);
  db.query=(async(sql:string,values?:unknown[])=>{
    if(sql.startsWith('UPDATE api_idempotency SET response=')&&values?.[4]===500){failureWaiting();await release;}
    return original(sql,values);
  }) as typeof db.query;
  const app=express();app.use(express.json());
  // Authentication is outside this isolated protocol test; all requests use
  // one synthetic actor and the real PostgreSQL idempotency table.
  app.use((req,_res,next)=>{req.user={id:user,role:'customer',phone:'fixture'};next();});
  app.post('/order',idempotent(db,'recovery_fixture',{recoverPending:true}),asyncHandler(async(req,res)=>{
    const data=await idempotentTransaction(db,req,async()=>{
      if(++calls===1)throw new ApiError(500,'fixture_failure','Сбой до сохранения заказа.');
      return (await db.query("INSERT INTO service_orders(customer_id,status) VALUES($1,'pending_assignment') RETURNING id",[user])).rows[0];
    },201);
    ok(res,data,201);
  }));app.use(errorHandler);
  const server=app.listen(0,'127.0.0.1');await new Promise<void>(resolve=>server.once('listening',resolve));
  const url='http://127.0.0.1:'+(server.address() as any).port+'/order';
  const send=()=>fetch(url,{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({idempotencyKey:key})});
  try{
    await original("INSERT INTO app_users(id,phone,role) VALUES($1,$2,'customer')",[user,'recovery-'+user]);
    const first=send();await Promise.race([waiting,new Promise((_,reject)=>setTimeout(()=>reject(Error('Failure was not intercepted')),5000))]);
    const second=await send();assert.equal(second.status,201);const success=await second.json();
    releaseFailure();assert.equal((await first).status,500);
    const third=await send();assert.equal(third.status,201);assert.deepEqual(await third.json(),success);
    assert.equal(calls,2,'Only the failed attempt and one successful recovery may execute');
    assert.equal((await original('SELECT count(*)::int AS n FROM service_orders WHERE customer_id=$1',[user])).rows[0].n,1);
    const row=(await original("SELECT status_code,response FROM api_idempotency WHERE user_id=$1 AND scope='recovery_fixture' AND key=$2",[user,key])).rows[0];
    assert.equal(row.status_code,201);assert.deepEqual(row.response,success);
  }finally{
    releaseFailure();await new Promise<void>(resolve=>server.close(()=>resolve()));
    db.query=original;await original('DELETE FROM service_orders WHERE customer_id=$1',[user]);
    await original('DELETE FROM api_idempotency WHERE user_id=$1',[user]);await original('DELETE FROM app_users WHERE id=$1',[user]);await db.close();
  }
});
