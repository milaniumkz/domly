import {Readable} from 'node:stream';
import test from 'node:test';
import assert from 'node:assert/strict';
import {randomUUID} from 'node:crypto';
import express from 'express';
import {AddressInfo} from 'node:net';
import {Database} from '../infrastructure/db/Database';
import {buildV1Router} from '../http/routes/v1';
import {errorHandler} from '../common/api';
import {signAccessToken,signRefreshToken,verifyAccessToken} from '../common/auth';
import {NotificationService,SchedulingService,hashToken} from '../modules/domainServices';
import {verifyCleaner} from '../modules/cleanerVerification';

test('admin operations against real PostgreSQL', {skip:!process.env.DOMLY_INTEGRATION_DATABASE_URL},async t=>{
  const db=new Database(process.env.DOMLY_INTEGRATION_DATABASE_URL!);
  const admin=randomUUID(),cleaner=randomUUID(),customer=randomUUID(),file=randomUUID();
  const catalogIds: Record<string,string> = {};
  const housePrefix='admin-address-'+randomUUID();
  let failPush=false;
  const notifications=new NotificationService(db,{send:async()=>{if(failPush)throw Error('Provider offline');return {sent:0};}} as any);
  const app=express();
  app.use(express.json(),buildV1Router({db,notifications,payments:{refundOrderPayments:async()=>[]},scheduling:new SchedulingService(db),storage:{client:{getObject:async()=>Readable.from([Buffer.from('test image')])}}} as any),errorHandler);
  const server=app.listen(0,'127.0.0.1');
  await new Promise<void>(resolve=>server.once('listening',resolve));
  const base='http://127.0.0.1:'+(server.address() as AddressInfo).port;
  async function request(path:string,method='GET',body?:object,asCustomer=false) {
    const token=signAccessToken({id:asCustomer?customer:admin,role:asCustomer?'customer':'superadmin',phone:'fixture'});
    const res=await fetch(base+path,{method,headers:{Authorization:'Bearer '+token,'Content-Type':'application/json'},body:body?JSON.stringify(body):undefined});
    return {status:res.status,json:await res.json() as any};
  }
  try {
    for(const [id,role] of [[admin,'superadmin'],[cleaner,'cleaner'],[customer,'customer']])await db.query("INSERT INTO app_users(id,phone,role,status,full_name) VALUES($1,$2,$3,'pending','Тестовая анкета')",[id,'admin-test-'+id,role]);
    await db.query('INSERT INTO cleaner_profiles(user_id) VALUES($1)',[cleaner]);
    await db.query("INSERT INTO files(id,owner_id,bucket,object_key,public_url) VALUES($1,$2,'test',$3,'https://example.com/document')",[file,cleaner,file]);
    await db.query("INSERT INTO cleaner_documents(cleaner_id,type,file_id) VALUES($1,'selfieUrl',$2)",[cleaner,file]);
    await t.test('admin session refresh rotates tokens and preserves access after reopening',async()=>{
      const original=signRefreshToken({id:admin,role:'superadmin',phone:'fixture'});
      await db.query("INSERT INTO refresh_sessions(user_id,token_hash,expires_at) VALUES($1,$2,NOW()+INTERVAL '30 days')",[admin,hashToken(original)]);
      let token=original;
      for(let i=0;i<3;i++) {
        const response=await request('/auth/refresh','POST',{refreshToken:token});
        assert.equal(response.status,200);
        const next=response.json.data;
        assert.notEqual(next.refreshToken,token);
        assert.equal(verifyAccessToken(next.accessToken).id,admin);
        assert.equal((await fetch(base+'/admin/quality',{headers:{Authorization:'Bearer '+next.accessToken}})).status,200);
        assert.equal((await request('/auth/refresh','POST',{refreshToken:token})).status,401);
        token=next.refreshToken;
      }
      assert.equal((await request('/auth/refresh','POST',{refreshToken:'invalid'})).status,401);
    });
    await t.test('order start confirmation, completion, ownership and retry are consistent',async()=>{
      const order=randomUUID();
      await db.query("INSERT INTO service_orders(id,customer_id,cleaner_id,status) VALUES($1,$2,$3,'assigned')",[order,customer,cleaner]);
      async function cleanerRequest(path:string,body:object) {
        const token=signAccessToken({id:cleaner,role:'cleaner',phone:'fixture'});
        const res=await fetch(base+path,{method:'POST',headers:{Authorization:'Bearer '+token,'Content-Type':'application/json'},body:JSON.stringify(body)});
        return {status:res.status,json:await res.json() as any};
      }
      try {
        const other=randomUUID();
        await db.query("INSERT INTO app_users(id,phone,role,status) VALUES($1,$2,'customer','approved')",[other,'order-owner-'+other]);
        try {
          const token=signAccessToken({id:other,role:'customer',phone:'fixture'});
          for (const path of ['cancel','confirm-start']) {
            const res=await fetch(base+`/orders/${order}/${path}`,{method:'POST',headers:{Authorization:'Bearer '+token,'Content-Type':'application/json'},body:JSON.stringify({confirmed:true})});
            assert.ok([403,404].includes(res.status));
          }
          assert.equal((await db.query('SELECT status FROM service_orders WHERE id=$1',[order])).rows[0].status,'assigned');
        } finally {await db.query('DELETE FROM app_users WHERE id=$1',[other]);}
        assert.equal((await cleanerRequest(`/orders/${order}/status`,{status:'completed'})).status,409);
        assert.equal((await cleanerRequest(`/orders/${order}/photo-report`,{photoUrls:['a','b','c']})).status,409);
        const start=await cleanerRequest(`/orders/${order}/status`,{status:'in_progress'});
        assert.equal(start.status,200);
        assert.equal(start.json.data.status,'start_pending');
        assert.equal(start.json.data.start_requires_customer_confirmation,true);
        assert.equal((await request(`/orders/${order}/confirm-start`,'POST',{confirmed:false},true)).status,200);
        assert.equal((await cleanerRequest(`/orders/${order}/status`,{status:'in_progress'})).status,200);
        const confirm=await request(`/orders/${order}/confirm-start`,'POST',{confirmed:true},true);
        assert.equal(confirm.status,200);
        assert.equal(confirm.json.data.order.status,'in_progress');
        assert.equal(confirm.json.data.order.cleaning_start_confirmed,true);
        assert.ok(confirm.json.data.order.started_at);
        const count=Number((await db.query('SELECT COUNT(*) AS count FROM notifications WHERE target_id=$1',[order])).rows[0].count);
        assert.equal((await request(`/orders/${order}/confirm-start`,'POST',{confirmed:true},true)).status,200);
        assert.equal(Number((await db.query('SELECT COUNT(*) AS count FROM notifications WHERE target_id=$1',[order])).rows[0].count),count);
        assert.equal((await request(`/orders/${order}/photo-report`,'GET',undefined,true)).json.data.canSubmit,true);
        assert.equal((await cleanerRequest(`/orders/${order}/status`,{status:'completed'})).status,409);
        assert.equal((await cleanerRequest(`/orders/${order}/photo-report`,{photoUrls:['a','b','c']})).status,201);
        const complete=await cleanerRequest(`/orders/${order}/status`,{status:'completed'});
        assert.equal(complete.status,200);
        assert.ok(complete.json.data.completed_at);
        assert.equal((await cleanerRequest(`/orders/${order}/status`,{status:'completed'})).status,200);
        assert.equal((await cleanerRequest(`/orders/${order}/status`,{status:'in_progress'})).status,409);
        assert.equal((await request(`/orders/${order}/reschedule`,'POST',{date:'2030-01-01',time:'10:00'},true)).status,409);
        assert.equal((await request(`/orders/${order}/cancel`,'POST',{},true)).status,404);
        const history=(await db.query('SELECT new_status FROM order_status_history WHERE order_id=$1 ORDER BY created_at',[order])).rows.map((row:any)=>row.new_status);
        assert.deepEqual(history,['start_pending','assigned','start_pending','in_progress','completed']);
        const notices=(await db.query('SELECT user_id,title_ru FROM notifications WHERE target_id=$1',[order])).rows;
        assert.ok(notices.some((row:any)=>row.user_id===customer&&row.title_ru==='Уборка завершена'));
        assert.ok(notices.every((row:any)=>[customer,cleaner].includes(row.user_id)));
      } finally {
        await db.query('DELETE FROM notifications WHERE target_id=$1',[order]);
        await db.query('DELETE FROM service_orders WHERE id=$1',[order]);
      }
    });
    await t.test('rescheduling and cancellation notify both parties and retain history',async()=>{
      const order=randomUUID();
      await db.query("INSERT INTO service_orders(id,customer_id,cleaner_id,status,scheduled_date,start_time,end_time,estimated_duration_minutes) VALUES($1,$2,$3,'assigned','2031-01-01','10:00','12:00',120)",[order,customer,cleaner]);
      try {
        const move=await request(`/orders/${order}/reschedule`,'POST',{date:'2031-01-02',time:'13:00'},true);
        assert.equal(move.status,200);
        assert.equal(String(move.json.data.start_time),'13:00:00');
        assert.equal((await request(`/orders/${order}/cancel`,'POST',{reason:'test'},true)).status,200);
        assert.equal((await db.query('SELECT status FROM service_orders WHERE id=$1',[order])).rows[0].status,'cancelled');
        assert.equal((await request(`/orders/${order}/cancel`,'POST',{},true)).status,404);
        assert.equal((await request(`/orders/${order}/status`,'POST',{status:'in_progress'})).status,409);
        const history=(await db.query('SELECT new_status FROM order_status_history WHERE order_id=$1 ORDER BY created_at',[order])).rows;
        assert.deepEqual(history.map((row:any)=>row.new_status),['assigned','cancelled']);
        const notices=(await db.query('SELECT user_id,title_ru FROM notifications WHERE target_id=$1',[order])).rows;
        for(const user of [customer,cleaner]) {
          assert.ok(notices.some((row:any)=>row.user_id===user&&row.title_ru==='Время уборки изменено'));
          assert.ok(notices.some((row:any)=>row.user_id===user&&row.title_ru==='Заказ отменён'));
        }
      } finally {
        await db.query('DELETE FROM notifications WHERE target_id=$1',[order]);
        await db.query('DELETE FROM service_orders WHERE id=$1',[order]);
      }
    });
    await t.test('personal notifications never leak through role membership',async()=>{
      const other=randomUUID();
      const ids=[randomUUID(),randomUUID(),randomUUID()];
      await db.query("INSERT INTO app_users(id,phone,role,status) VALUES($1,$2,'customer','approved')",[other,'notification-test-'+other]);
      try {
        for(const [id,user,role] of [[ids[0],customer,'customer'],[ids[1],other,'customer'],[ids[2],null,'customer']]) {
          await db.query("INSERT INTO notifications(id,user_id,role,title_ru,body_ru) VALUES($1,$2,$3,'Test','Test')",[id,user,role]);
        }
        const rows=(await request('/notifications','GET',undefined,true)).json.data;
        assert.ok(rows.some((row:any)=>row.id===ids[0]));
        assert.ok(rows.some((row:any)=>row.id===ids[2]));
        assert.ok(!rows.some((row:any)=>row.id===ids[1]));
        assert.equal((await request('/notifications/'+ids[1]+'/read','POST',{},true)).status,404);
        const before=(await request('/notifications/unread-count','GET',undefined,true)).json.data.count;
        await request('/notifications/'+ids[0]+'/read','POST',{},true);
        assert.equal((await request('/notifications/unread-count','GET',undefined,true)).json.data.count,before-1);
        assert.equal((await request('/notifications/read-all','POST',{},true)).status,200);
        assert.equal((await db.query('SELECT read_at FROM notifications WHERE id=$1',[ids[1]])).rows[0].read_at,null);
        assert.equal((await db.query('SELECT COUNT(*)::int AS count FROM notification_reads WHERE notification_id=$1 AND user_id=$2',[ids[1],customer])).rows[0].count,0);
      } finally {
        await db.query('DELETE FROM notifications WHERE id=ANY($1::uuid[])',[ids]);
        await db.query('DELETE FROM app_users WHERE id=$1',[other]);
      }
    });
    await t.test('cleaner zones load, persist, clear and reject inactive selections',async()=>{
      const active=randomUUID(),inactive=randomUUID();
      const token=signAccessToken({id:cleaner,role:'cleaner',phone:'fixture'});
      async function cleanerRequest(body?:object) {
        const res=await fetch(base+'/cleaner/profile',{method:body?'PATCH':'GET',headers:{Authorization:'Bearer '+token,'Content-Type':'application/json'},body:body?JSON.stringify(body):undefined});
        return {status:res.status,json:await res.json() as any};
      }
      try {
        await db.query("INSERT INTO service_zones(id,name_ru,city,active) VALUES($1,'Test Active','Test',TRUE),($2,'Test Inactive','Test',FALSE)",[active,inactive]);
        const zones=(await request('/geo/zones?city=Test')).json.data;
        assert.ok(zones.some((row:any)=>row.id===active));
        assert.ok(!zones.some((row:any)=>row.id===inactive));
        assert.equal((await fetch(base+'/admin/zones',{headers:{Authorization:'Bearer '+token}})).status,403);
        assert.equal((await cleanerRequest({zoneIds:[active,active]})).status,200);
        assert.deepEqual((await cleanerRequest()).json.data.zones.map((z:any)=>z.id),[active]);
        assert.equal((await cleanerRequest({soundVolume:50})).status,200);
        assert.equal((await cleanerRequest()).json.data.zones.length,1);
        assert.equal((await cleanerRequest({zoneIds:[inactive],fullName:'Must Roll Back'})).status,400);
        assert.equal((await cleanerRequest()).json.data.profile.full_name,'Тестовая анкета');
        assert.equal((await cleanerRequest()).json.data.zones.length,1);
        assert.equal((await cleanerRequest({zoneIds:[]})).status,200);
        assert.equal((await cleanerRequest()).json.data.zones.length,0);
      } finally {await db.query('DELETE FROM cleaner_zones WHERE cleaner_id=$1',[cleaner]);await db.query('DELETE FROM service_zones WHERE id=ANY($1::uuid[])',[[active,inactive]]);}
    });
    await t.test('area approval credits bonus once across both endpoints and retries',async()=>{
      const address=randomUUID(),check=randomUUID();
      const initial=Number((await db.query('SELECT bonus_balance FROM app_users WHERE id=$1',[customer])).rows[0].bonus_balance);
      try {
        await db.query("INSERT INTO customer_addresses(id,user_id,city,street,house,area,is_primary) VALUES($1,$2,'Астана','Test','1',90,TRUE)",[address,customer]);
        await db.query("INSERT INTO quality_check_requests(id,customer_id,address_id,requested_area) VALUES($1,$2,$3,100)",[check,customer,address]);
        assert.equal((await request('/admin/quality-checks/'+check,'PATCH',{status:'approved',approvedArea:100})).status,200);
        assert.equal(Number((await db.query('SELECT bonus_balance FROM app_users WHERE id=$1',[customer])).rows[0].bonus_balance),initial+2000);
        assert.equal(Number((await db.query('SELECT verified_area FROM customer_addresses WHERE id=$1',[address])).rows[0].verified_area),100);
        const repeated=await Promise.all([request('/admin/quality-checks/'+check+'/approve','POST',{approvedArea:100}),request('/admin/users/'+customer+'/confirm-area','POST',{actualArea:100})]);
        for(const res of repeated) assert.equal(res.status,200);
        assert.equal(Number((await db.query('SELECT bonus_balance FROM app_users WHERE id=$1',[customer])).rows[0].bonus_balance),initial+2000);
        const history=(await request('/bonus/history','GET',undefined,true)).json.data;
        assert.equal(history.filter((row:any)=>row.dedupe_key==='area-confirmation:'+customer+':'+address).length,1);
        assert.equal((await request('/admin/quality-checks/'+check+'/approve','POST',{approvedArea:-5})).status,400);
      } finally {
        await db.query('DELETE FROM quality_check_requests WHERE id=$1',[check]);
        await db.query('DELETE FROM bonus_transactions WHERE user_id=$1',[customer]);
        await db.query('UPDATE app_users SET bonus_balance=$2 WHERE id=$1',[customer,initial]);
        await db.query('DELETE FROM customer_addresses WHERE id=$1',[address]);
      }
    });
    await t.test('dispatched order reaches cleaner and acceptance keeps it in cleaner orders',async()=>{
      const order=randomUUID();
      const token=signAccessToken({id:cleaner,role:'cleaner',phone:'fixture'});
      const service=new SchedulingService(db);
      try {
        await db.query("UPDATE app_users SET status='approved' WHERE id=$1",[cleaner]);
        await db.query("UPDATE cleaner_profiles SET verification_status='approved' WHERE user_id=$1",[cleaner]);
        await db.query("INSERT INTO service_orders(id,customer_id,scheduled_date,start_time,end_time,estimated_duration_minutes,area,status) VALUES($1,$2,'2030-01-02','10:00','12:00',120,100,'pending_assignment')",[order,customer]);
        const candidates=await service.availableCleaners('2030-01-02','10:00','12:00');
        const offer=await service.offerNextCleaner(order,candidates.filter((c:any)=>c.id!==cleaner).map((c:any)=>c.id)) as any;
        assert.equal(offer.cleaner_id,cleaner);
        const remaining=Date.parse(offer.expires_at)-Date.now();
        assert.ok(remaining>110000 && remaining<=120000,'Default offer expires after two minutes');
        const offersResponse=await fetch(base+'/cleaner/offers',{headers:{Authorization:'Bearer '+token}});
        assert.equal(offersResponse.status,200);
        const offers=(await offersResponse.json() as any).data;
        assert.equal(offers.find((row:any)=>row.order_id===order).id,offer.id);
        assert.ok(Date.parse(offers.find((row:any)=>row.order_id===order).expires_at)>Date.now());
        assert.equal((await request('/orders/'+order+'/offers/accept','POST',{},true)).status,403);
        const responses=await Promise.all([service.acceptOffer(order,cleaner),service.acceptOffer(order,cleaner)].map(p=>p.then(()=>200,error=>error.statusCode??error.status??409)));
        assert.equal(responses.filter(status=>status===200).length,1);
        const accepted=(await (await fetch(base+'/cleaner/orders',{headers:{Authorization:'Bearer '+token}})).json() as any).data.find((row:any)=>row.id===order);
        assert.equal(accepted.cleaner_id,cleaner);assert.equal(accepted.status,'assigned');assert.ok(accepted.scheduled_date);
        assert.ok(!(await service.cleanerOffers(cleaner)).some((row:any)=>row.order_id===order));
      } finally {
        await db.query('DELETE FROM order_offers WHERE order_id=$1',[order]);
        await db.query('DELETE FROM service_orders WHERE id=$1',[order]);
        await db.query("UPDATE app_users SET status='pending' WHERE id=$1",[cleaner]);
        await db.query("UPDATE cleaner_profiles SET verification_status='pending' WHERE user_id=$1",[cleaner]);
      }
    });
    await t.test('document preview reads stored objects only and rejects customer access',async()=>{
      const url='https://example.com/document';
      const preview=await request('/admin/files/preview?url='+encodeURIComponent(url));
      assert.equal(preview.status,200);
      assert.equal(Buffer.from(preview.json.data.base64,'base64').toString(),'test image');
      assert.equal((await request('/admin/files/preview?url='+encodeURIComponent(url),'GET',undefined,true)).status,403);
      assert.equal((await request('/admin/files/preview?url=http%3A%2F%2Flocalhost%2Fprivate')).status,404);
    });
    await t.test('all admin list sections load and deny customer access',async()=>{
      for(const section of ['cities','orders','payments','complaints','reviews','checklistReports','photoReports','cleaners','users','preorders','quality','addressRequests','payouts','audit','zones','houses','checklistTemplates','packages','addons','addonGroups','banners','promotions','promotionRedemptions','contentPages','videoViews']) {
        assert.equal((await request('/admin/'+section)).status,200,section);
        assert.equal((await request('/admin/'+section,'GET',undefined,true)).status,403,section+' permissions');
      }
      const rows=(await request('/admin/cleaners?status=pending&search=Тестовая')).json.data;
      const row=rows.find((item:any)=>item.id===cleaner);
      assert.equal(row.full_name,'Тестовая анкета');
      assert.equal(row.verification_status,'pending');
      assert.equal(row.documents[0].url,'https://example.com/document');
      assert.equal((await request('/admin/cleaners/'+cleaner+'/details')).json.data.documents[0].public_url,'https://example.com/document');
    });
    await t.test('all cities and address matches beyond the first 500 are available',async()=>{
      assert.equal((await request('/geo/cities?limit=200')).json.data.length,90);
      assert.equal((await request('/geo/cities?search=Капчагай')).json.data[0].name_ru,'Конаев');
      assert.equal((await request('/geo/cities?search=Косшы')).json.data[0].name_ru,'Косшы');
      await db.query(`INSERT INTO connected_houses(city,street_ru,house,active)
        SELECT $1,'Ааа тест',n::text,FALSE FROM generate_series(1,501) n`,[housePrefix]);
      await db.query(`INSERT INTO connected_houses(city,street_ru,house,active) VALUES($1,'Момышұлы','14',FALSE)`,[housePrefix]);
      const rows=(await request('/geo/address-suggestions?city='+housePrefix+'&search=Момышулы%2014&limit=1')).json.data.suggestions;
      assert.equal(rows.length,1);assert.equal(rows[0].house,'14');
      assert.equal(rows[0].source,'address_directory');assert.equal(rows[0].connected,false);
    });
    await t.test('admin can create, edit and hide catalogue and geography records',async()=>{
      const name=housePrefix;
      const pkg=await request('/admin/catalog/packages','POST',{nameRu:name,cleaningCount:2,months:1,basePrice:0,pricePerM2:180,features:['Поддерживающая уборка']});
      assert.equal(pkg.status,201);catalogIds.pkg=pkg.json.data.id;
      assert.equal((await request('/admin/catalog/packages/'+catalogIds.pkg,'PATCH',{nameRu:name+' edited',pricePerM2:190})).status,200);
      assert.equal((await request('/admin/packages/'+catalogIds.pkg+'/active','PATCH',{active:false})).status,200);
      const group=await request('/admin/catalog/addon-groups','POST',{titleRu:name});
      assert.equal(group.status,201);catalogIds.group=group.json.data.id;
      const addon=await request('/admin/catalog/addons','POST',{titleRu:name,groupId:catalogIds.group,price:2000,durationMinutes:30});
      assert.equal(addon.status,201);catalogIds.addon=addon.json.data.id;
      assert.equal((await request('/admin/catalog/addons/'+catalogIds.addon,'PATCH',{price:2500})).status,200);
      const zone=await request('/admin/service-zones','POST',{nameRu:name,city:housePrefix,polygon:[{lat:51.1,lng:71.4},{lat:51.2,lng:71.4},{lat:51.1,lng:71.5}]});
      assert.equal(zone.status,201);catalogIds.zone=zone.json.data.id;
      assert.equal((await request('/admin/service-zones/'+catalogIds.zone,'PATCH',{polygon:[{lat:51.1,lng:71.4}]})).status,200);
      const house=await request('/admin/connected-houses','POST',{city:housePrefix,streetRu:'Тестовая',house:'15',zoneId:catalogIds.zone,active:false});
      assert.equal(house.status,201);catalogIds.house=house.json.data.id;
      assert.equal((await request('/admin/connected-houses/'+catalogIds.house,'PATCH',{active:true})).status,200);
    });
    await t.test('payment cards include customer, package, address and creation date',async()=>{
      const address=randomUUID(),purchase=randomUUID(),payment=randomUUID();
      try {
        await db.query("INSERT INTO customer_addresses(id,user_id,city,street,house,apartment,area,verified_area) VALUES($1,$2,'Астана','Test Street','14','5',100,100)",[address,customer]);
        await db.query('INSERT INTO customer_packages(id,customer_id,package_id,address_id,total_cleanings,available_cleanings) VALUES($1,$2,$3,$4,2,2)',[purchase,customer,catalogIds.pkg,address]);
        await db.query("INSERT INTO payments(id,customer_id,customer_package_id,provider,status,amount,invoice_phone) VALUES($1,$2,$3,'kaspi','invoice_requested',22000,'+77000000000')",[payment,customer,purchase]);
        const row=(await request('/admin/payments')).json.data.find((item:any)=>item.id===payment);
        assert.equal(row.customer_name,'Тестовая анкета');
        assert.equal(row.customer_phone,'admin-test-'+customer);
        assert.equal(row.package_name_ru,housePrefix+' edited');
        assert.equal(row.street,'Test Street');assert.equal(row.house,'14');assert.equal(row.apartment,'5');
        assert.equal(Number(row.verified_area),100);
        assert.ok(row.created_at);assert.equal(row.invoice_phone,'+77000000000');
      } finally {
        await db.query('DELETE FROM payments WHERE id=$1',[payment]);
        await db.query('DELETE FROM customer_packages WHERE id=$1',[purchase]);
        await db.query('DELETE FROM customer_addresses WHERE id=$1',[address]);
      }
    });
    await t.test('failed notification persistence rolls back the entire decision',async()=>{
      await assert.rejects(verifyCleaner(db,{persist:async()=>{throw Error('Storage failure');}} as any,cleaner,'approved',admin));
      const state=(await db.query('SELECT u.status,cp.verification_status FROM app_users u JOIN cleaner_profiles cp ON cp.user_id=u.id WHERE u.id=$1',[cleaner])).rows[0];
      assert.equal(state.status,'pending');assert.equal(state.verification_status,'pending');
      assert.equal((await db.query('SELECT status FROM cleaner_documents WHERE cleaner_id=$1',[cleaner])).rows[0].status,'pending');
    });
    await t.test('approve is atomic and repeated clicks do not duplicate notifications',async()=>{
      failPush=true;
      for(let i=0;i<2;i++)assert.equal((await request('/admin/cleaners/'+cleaner+'/verification','PATCH',{status:'approved'})).status,200);
      const state=(await db.query('SELECT u.status,cp.verification_status,cp.verified_at FROM app_users u JOIN cleaner_profiles cp ON cp.user_id=u.id WHERE u.id=$1',[cleaner])).rows[0];
      assert.equal(state.status,'approved');assert.equal(state.verification_status,'approved');assert.ok(state.verified_at);
      assert.equal((await db.query('SELECT status FROM cleaner_documents WHERE cleaner_id=$1',[cleaner])).rows[0].status,'approved');
      assert.equal(Number((await db.query('SELECT COUNT(*) FROM notifications WHERE user_id=$1',[cleaner])).rows[0].count),1);
      assert.equal(Number((await db.query("SELECT COUNT(*) FROM audit_logs WHERE actor_id=$1 AND action='cleaner.verification'",[admin])).rows[0].count),1);
    });
    await t.test('reject, block and pending keep user, profile and documents consistent',async()=>{
      failPush=false;
      for(const status of ['rejected','blocked','pending']){
        const res=await request('/admin/cleaners/'+cleaner+'/verification','PATCH',{status});
        assert.equal(res.status,200);assert.equal(res.json.data.cleaner.status,status);assert.equal(res.json.data.profile.verification_status,status);assert.equal(res.json.data.profile.verified_at,null);
        assert.equal((await db.query('SELECT status FROM cleaner_documents WHERE cleaner_id=$1',[cleaner])).rows[0].status,status);
      }
      assert.equal((await request('/admin/cleaners/'+cleaner+'/verification','PATCH',{status:'wrong'})).status,400);
      assert.equal((await request('/admin/cleaners/'+customer+'/verification','PATCH',{status:'approved'})).status,404);
    });
    await t.test('area photo request persists an owned file and admin can review it',async()=>{
      const ownFile=randomUUID();
      await db.query("INSERT INTO files(id,owner_id,bucket,object_key,public_url) VALUES($1::uuid,$2,'test',$1::text,'https://example.com/area-plan')",[ownFile,customer]);
      try {
        assert.equal((await request('/quality-checks/from-file','POST',{actualArea:100,fileId:file},true)).status,404);
        assert.equal((await request('/quality-checks/from-file','POST',{actualArea:100,addressId:randomUUID(),fileId:ownFile},true)).status,404);
        assert.equal((await request('/quality-checks/from-file','POST',{actualArea:100,fileUrl:'upload-error://fake'},true)).status,404);
        assert.equal((await request('/quality-checks/from-file','POST',{actualArea:100,fileUrl:'https://example.com/area-plan'},true)).status,201);
        const result=await request('/quality-checks/from-file','POST',{actualArea:100,fileId:ownFile},true);
        assert.equal(result.status,201);assert.equal(result.json.data.request.document_file_id,ownFile);
        const rows=(await request('/admin/quality')).json.data;
        assert.equal(rows.find((row:any)=>row.id===result.json.data.request.id).areaTechnicalPlanUrl,'https://example.com/area-plan');
        assert.equal((await request('/admin/quality-checks/'+result.json.data.request.id,'PATCH',{adminComment:'Проверено',approvedArea:100,status:'approved'})).status,200);
        assert.equal((await request('/quality-checks/from-file','POST',{actualArea:0,fileId:ownFile},true)).status,400);
      } finally {
        await db.query('DELETE FROM quality_check_requests WHERE customer_id=$1',[customer]);
        await db.query('DELETE FROM files WHERE id=$1',[ownFile]);
      }
    });
    await t.test('complaints are scoped to the customer and available to admin',async()=>{
      await db.query("INSERT INTO complaints(customer_id,title,body) VALUES($1,'Тестовая жалоба','Тест')",[customer]);
      assert.equal((await request('/complaints','GET',undefined,true)).status,200);
      const res=await request('/admin/complaints');assert.equal(res.status,200);assert.ok(res.json.data.some((row:any)=>row.customer_id===customer));
      assert.equal((await request('/complaints')).status,403);
    });
  } finally {
    await new Promise<void>(resolve=>server.close(()=>resolve()));
    await db.query('DELETE FROM connected_houses WHERE city=$1',[housePrefix]);
    if(catalogIds.zone)await db.query('DELETE FROM service_zones WHERE id=$1',[catalogIds.zone]);
    if(catalogIds.addon)await db.query('DELETE FROM catalog_addons WHERE id=$1',[catalogIds.addon]);
    if(catalogIds.group)await db.query('DELETE FROM addon_groups WHERE id=$1',[catalogIds.group]);
    if(catalogIds.pkg)await db.query('DELETE FROM catalog_packages WHERE id=$1',[catalogIds.pkg]);
    await db.query('DELETE FROM complaints WHERE customer_id=$1',[customer]);
    await db.query('DELETE FROM audit_logs WHERE actor_id=$1',[admin]);
    await db.query('DELETE FROM cleaner_documents WHERE cleaner_id=$1',[cleaner]);
    await db.query('DELETE FROM files WHERE id=$1',[file]);
    await db.query('DELETE FROM app_users WHERE id=ANY($1::uuid[])',[[admin,cleaner,customer]]);
    await db.close();
  }
});
