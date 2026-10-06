import test from 'node:test';
import assert from 'node:assert/strict';
import { randomUUID } from 'node:crypto';
import express from 'express';
import { AddressInfo } from 'node:net';
import { Database } from '../infrastructure/db/Database';
import { mobileRouter } from '../http/routes/mobile';
import { errorHandler } from '../common/api';
import { signAccessToken } from '../common/auth';
import { packageQuote } from '../modules/packageQuote';
import { updateOrderAddons } from '../modules/orderAddons';
import { qualifyReferral } from '../modules/referrals';

test('mobile backend persistence, permissions, pricing and account lifecycle', {skip: !process.env.DOMLY_INTEGRATION_DATABASE_URL}, async t => {
  const db = new Database(process.env.DOMLY_INTEGRATION_DATABASE_URL!);
  const customer = randomUUID(), inviter = randomUUID(), admin = randomUUID();
  const house = randomUUID(), pkg = randomUUID(), addon = randomUUID(), cp = randomUUID(), payment = randomUUID(), video = randomUUID(), order = randomUUID();
  const app = express();
  app.use(express.json(), mobileRouter(db), errorHandler);
  const server = app.listen(0, '127.0.0.1');
  await new Promise<void>(resolve => server.once('listening', resolve));
  const base = `http://127.0.0.1:${(server.address() as AddressInfo).port}`;
  const token = (id: string, role: 'customer'|'admin') => signAccessToken({id,role,phone: `test-${id}`});
  async function request(path: string, method='GET', body?: object, id=customer, role: 'customer'|'admin'='customer') {
    const response = await fetch(base+path, {method, headers: {'Authorization': `Bearer ${token(id,role)}`, 'Content-Type':'application/json'}, body: body ? JSON.stringify(body) : undefined});
    return {status: response.status, json: await response.json() as any};
  }
  try {
    for (const [id,role] of [[customer,'customer'],[inviter,'customer'],[admin,'admin']]) {
      await db.query('INSERT INTO app_users (id,phone,role) VALUES ($1,$2,$3)', [id,`test-${id}`,role]);
    }
    await db.query("INSERT INTO connected_houses (id,city,street_ru,house,active) VALUES ($1,'Астана','Тестовая','1',FALSE)", [house]);
    await db.query("INSERT INTO catalog_packages (id,name_ru,cleaning_count,months,base_price,price_per_m2) VALUES ($1,'Тест',2,3,100,10)", [pkg]);
    await db.query("INSERT INTO catalog_addons (id,title_ru,price) VALUES ($1,'Тестовый доп',25)", [addon]);
    await t.test('waitlist persists and deduplicates joins', async () => {
      for (let i=0;i<2;i++) assert.equal((await request(`/geo/houses/${house}/waitlist`,'POST',{})).status,200);
      const rows = await request(`/geo/houses/${house}/waitlist`);
      assert.equal(rows.json.data.length,1);
      assert.equal((await request(`/geo/houses/${house}/stats`)).json.data.house.current_users,1);
      assert.equal((await request(`/geo/houses/${house}/waitlist`,'GET',undefined,inviter)).json.data.length,0);
    });
    await t.test('referrals reject self codes and persist one inviter', async () => {
      const own = await request('/referrals');
      assert.equal((await request('/referrals','POST',{code:own.json.data.referralCode})).status,400);
      const ref = await request('/referrals','GET',undefined,inviter);
      assert.equal((await request('/referrals','POST',{code:ref.json.data.referralCode})).status,200);
      assert.equal((await request('/referrals')).json.data.referredByCode,ref.json.data.referralCode);
    });
    await t.test('video catalogue reflects admin updates and rejects customer writes', async () => {
      assert.equal((await request('/admin/videos','POST',{id:video,title:'Видео',url:'https://example.com/video',audienceType:'client'})).status,403);
      assert.equal((await request('/admin/videos','POST',{id:video,title:'Видео',url:'https://example.com/video',audienceType:'client'},admin,'admin')).status,200);
      const detail = (await request(`/training/videos/${video}`)).json.data;
      assert.equal(detail.url,'https://example.com/video');
      assert.equal(detail.videoUrl,'https://example.com/video');
      assert.ok((await request('/training/videos?audience=client')).json.data.some((row: any)=>row.id===video));
      assert.ok(!(await request('/training/videos?audience=cleaner')).json.data.some((row: any)=>row.id===video));
    });
    await t.test('server prices package and addons from database, ignoring client amount', async () => {
      const quote = await packageQuote(db,{packageId:pkg,area:50,amount:1,addonsDetailed:[{key:addon,quantity:2,price:1}]});
      assert.equal(quote.cleaningCount,6);
      assert.equal(quote.monthlyPrice,3650);
      await assert.rejects(packageQuote(db,{packageId:pkg,area:50,addonsDetailed:[{key:addon,quantity:-1}]}));
    });
    await t.test('referral reward is credited once for repeated payment application', async () => {
      await db.query('INSERT INTO customer_packages (id,customer_id,package_id,total_cleanings,available_cleanings) VALUES ($1,$2,$3,2,2)', [cp,customer,pkg]);
      await db.query("INSERT INTO payments (id,customer_id,customer_package_id,provider,status,amount) VALUES ($1,$2,$3,'manual','paid',100)", [payment,customer,cp]);
      for(let i=0;i<2;i++) await qualifyReferral(db,{id:payment,customer_id:customer,customer_package_id:cp});
      const balance = (await db.query('SELECT bonus_balance FROM app_users WHERE id=$1',[inviter])).rows[0];
      assert.equal(Number(balance.bonus_balance),2000);
      assert.equal((await request('/referrals','GET',undefined,inviter)).json.data.paid,1);
    });
    await t.test('addon edits persist server prices and protect paid quantities', async () => {
      await db.query("INSERT INTO service_orders (id,customer_id,customer_package_id,package_id,scheduled_date,start_time,end_time,estimated_duration_minutes,status) VALUES ($1,$2,$3,$4,CURRENT_DATE+1,'10:00','12:00',120,'pending_assignment')",[order,customer,cp,pkg]);
      const result=await updateOrderAddons(db,order,customer,[{key:addon,quantity:2,price:1}]);
      assert.equal(result.payableAmount,50);
      assert.equal((await request(`/orders/${order}/addons`,'POST',{addonsDetailed:[{key:addon,quantity:2}]},inviter)).status,404);
      await db.query("UPDATE order_addons SET payment_status='paid' WHERE order_id=$1",[order]);
      await assert.rejects(updateOrderAddons(db,order,customer,[]));
      assert.equal((await db.query('SELECT quantity FROM order_addons WHERE order_id=$1',[order])).rows[0].quantity,'2.00');
    });
    await t.test('account with an active order cannot be deleted',async()=>{
      assert.equal((await request('/me','DELETE')).status,409);
      await db.query("UPDATE service_orders SET status='completed' WHERE id=$1",[order]);
    });
    await t.test('account deletion revokes access and anonymizes identity', async () => {
      assert.equal((await request('/me','DELETE')).status,200);
      assert.equal((await request('/referrals')).status,401);
      const user=(await db.query('SELECT phone,deleted_at FROM app_users WHERE id=$1',[customer])).rows[0];
      assert.ok(user.deleted_at);
      assert.ok(user.phone.startsWith('deleted-'));
    });
  } finally {
    await new Promise<void>((resolve,reject)=>server.close(error=>error?reject(error):resolve()));
    await db.query('DELETE FROM bonus_transactions WHERE payment_id=$1',[payment]);
    await db.query('DELETE FROM payments WHERE id=$1',[payment]);
    await db.query('DELETE FROM service_orders WHERE id=$1',[order]);
    await db.query('DELETE FROM customer_packages WHERE id=$1',[cp]);
    await db.query('DELETE FROM user_referrals WHERE customer_id=$1',[customer]);
    await db.query('DELETE FROM house_waitlist WHERE house_id=$1',[house]);
    await db.query('DELETE FROM connected_houses WHERE id=$1',[house]);
    await db.query('DELETE FROM training_videos WHERE id=$1',[video]);
    await db.query('DELETE FROM catalog_addons WHERE id=$1',[addon]);
    await db.query('DELETE FROM catalog_packages WHERE id=$1',[pkg]);
    await db.query('DELETE FROM app_users WHERE id=ANY($1::uuid[])',[[customer,inviter,admin]]);
    await db.close();
  }
});

test('temporary delivery fallback completes backend login and the code is single-use', {skip: !process.env.DOMLY_INTEGRATION_DATABASE_URL}, async () => {
  const {AuthService} = await import('../modules/domainServices');
  const {env} = await import('../common/env');
  const {ApiError} = await import('../common/api');
  const {randomInt} = await import('node:crypto');
  const db = new Database(process.env.DOMLY_INTEGRATION_DATABASE_URL!);
  const id=randomUUID(), phone='+7700'+randomInt(1000000,10000000);
  const original=env.otpFailureFallbackUntil;
  try {
    await db.query("INSERT INTO app_users (id,phone,role) VALUES ($1,$2,'customer')",[id,phone]);
    env.otpFailureFallbackUntil=new Date(Date.now()+60000).toISOString();
    const service=new AuthService(db,{sendOtp:async()=>{throw new ApiError(503,'integration_error','Provider unavailable');}} as any);
    const sent=await service.requestOtp(phone);
    const session=await service.verifyOtp(phone,sent.fallbackCode!);
    assert.equal(session.user.id,id);
    assert.equal(session.user.role,'customer');
    assert.ok(session.accessToken);
    assert.ok(session.refreshToken);
    await assert.rejects(()=>service.verifyOtp(phone,sent.fallbackCode!),(e:any)=>e.code==='invalid_otp');
  } finally {
    env.otpFailureFallbackUntil=original;
    await db.query('DELETE FROM refresh_sessions WHERE user_id=$1',[id]);
    await db.query('DELETE FROM auth_otp_codes WHERE phone=$1',[phone]);
    await db.query('DELETE FROM app_users WHERE id=$1',[id]);
    await db.close();
  }
});
