import test from 'node:test';
import assert from 'node:assert/strict';
import { randomUUID } from 'node:crypto';
import { Database } from '../infrastructure/db/Database';
import { SchedulingService } from '../modules/domainServices';

test('batched calendar preserves overlap boundaries, zones and approved verification', {skip:!process.env.DOMLY_INTEGRATION_DATABASE_URL}, async()=>{
 const db=new Database(process.env.DOMLY_INTEGRATION_DATABASE_URL!),service=new SchedulingService(db);
 const customer=randomUUID(),cleaner=randomUUID(),pending=randomUUID(),zone=randomUUID(),empty=randomUUID(),order=randomUUID();
 const slots=[{startTime:'08:00',endTime:'10:00'},{startTime:'10:00',endTime:'12:00'},{startTime:'11:00',endTime:'13:00'},{startTime:'12:00',endTime:'14:00'}];
 try{
  for(const [id,role] of [[customer,'customer'],[cleaner,'cleaner'],[pending,'cleaner']])await db.query("INSERT INTO app_users(id,phone,role,status) VALUES($1,$2,$3,'approved')",[id,'slot-'+id,role]);
  await db.query("INSERT INTO cleaner_profiles(user_id,verification_status) VALUES($1,'approved'),($2,'pending')",[cleaner,pending]);
  for(const id of [zone,empty])await db.query("INSERT INTO service_zones(id,name_ru,city) VALUES($1,$2,'Астана')",[id,'Тест-'+id]);
  await db.query('INSERT INTO cleaner_zones(cleaner_id,zone_id) VALUES($1,$3),($2,$3)',[cleaner,pending,zone]);
  await db.query("INSERT INTO service_orders(id,customer_id,cleaner_id,scheduled_date,start_time,end_time,status) VALUES($1,$2,$3,'2039-02-03','10:00','12:00','assigned')",[order,customer,cleaner]);
  const result=await service.availableSlotCounts('2039-02-03',slots,zone);
  assert.deepEqual(result.map(s=>s.cleanersCount),[1,0,0,1]);
  assert.deepEqual(result.map(s=>s.startTime),slots.map(s=>s.startTime));
  assert.deepEqual((await service.availableSlotCounts('2039-02-03',slots,empty)).map(s=>s.cleanersCount),[0,0,0,0]);
  assert.deepEqual(await service.availableSlotCounts('2039-02-03',[],zone),[]);
  for(const status of ['cancelled','completed']){
   await db.query('UPDATE service_orders SET status=$2 WHERE id=$1',[order,status]);
   assert.deepEqual((await service.availableSlotCounts('2039-02-03',slots,zone)).map(s=>s.cleanersCount),[1,1,1,1]);
  }
  const all=await service.availableSlotCounts('2039-02-03',slots);
  for(let i=0;i<slots.length;i++)assert.equal(all[i].cleanersCount,(await service.availableCleaners('2039-02-03',slots[i].startTime,slots[i].endTime)).length);
 }finally{
  await db.query('DELETE FROM service_orders WHERE id=$1',[order]);
  await db.query('DELETE FROM service_zones WHERE id=ANY($1::uuid[])',[[zone,empty]]);
  await db.query('DELETE FROM app_users WHERE id=ANY($1::uuid[])',[[customer,cleaner,pending]]);await db.close();
 }
});
