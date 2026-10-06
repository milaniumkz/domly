import test from 'node:test';
import assert from 'node:assert/strict';
import {randomUUID} from 'node:crypto';
import express from 'express';
import {AddressInfo} from 'node:net';
import {Database} from '../infrastructure/db/Database';
import {buildV1Router} from '../http/routes/v1';
import {errorHandler} from '../common/api';
import {signAccessToken} from '../common/auth';
import {NotificationService} from '../modules/domainServices';
import {verifyCleaner} from '../modules/cleanerVerification';

test('admin operations against real PostgreSQL', {skip:!process.env.DOMLY_INTEGRATION_DATABASE_URL},async t=>{
  const db=new Database(process.env.DOMLY_INTEGRATION_DATABASE_URL!);
  const admin=randomUUID(),cleaner=randomUUID(),customer=randomUUID(),file=randomUUID();
  const catalogIds: Record<string,string> = {};
  const housePrefix='admin-address-'+randomUUID();
  let failPush=false;
  const notifications=new NotificationService(db,{send:async()=>{if(failPush)throw Error('Provider offline');return {sent:0};}} as any);
  const app=express();
  app.use(express.json(),buildV1Router({db,notifications} as any),errorHandler);
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
      assert.equal(Number((await db.query('SELECT COUNT(*) FROM audit_logs WHERE actor_id=$1',[admin])).rows[0].count),1);
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
