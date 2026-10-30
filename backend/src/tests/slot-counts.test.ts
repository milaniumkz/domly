import test from 'node:test';
import assert from 'node:assert/strict';
import { randomUUID } from 'node:crypto';
import { Database } from '../infrastructure/db/Database';
import { SchedulingService } from '../modules/domainServices';

test('batched calendar preserves overlap boundaries, zones and approved verification', {skip:!process.env.DOMLY_INTEGRATION_DATABASE_URL}, async()=>{
 const db=new Database(process.env.DOMLY_INTEGRATION_DATABASE_URL!),service=new SchedulingService(db);
 const customer=randomUUID(),cleaner=randomUUID(),pending=randomUUID(),off=randomUUID(),zone=randomUUID(),empty=randomUUID(),order=randomUUID();
 const slots=[{startTime:'08:00',endTime:'10:00'},{startTime:'10:00',endTime:'12:00'},{startTime:'11:00',endTime:'13:00'},{startTime:'12:00',endTime:'14:00'}];
 try{
  for(const [id,role] of [[customer,'customer'],[cleaner,'cleaner'],[pending,'cleaner'],[off,'cleaner']])await db.query("INSERT INTO app_users(id,phone,role,status) VALUES($1,$2,$3,'approved')",[id,'slot-'+id,role]);
  await db.query("INSERT INTO cleaner_profiles(user_id,verification_status) VALUES($1,'approved'),($2,'pending'),($3,'approved')",[cleaner,pending,off]);
  for(const id of [zone,empty])await db.query("INSERT INTO service_zones(id,name_ru,city) VALUES($1,$2,'Астана')",[id,'Тест-'+id]);
  await db.query('INSERT INTO cleaner_zones(cleaner_id,zone_id) VALUES($1,$4),($2,$4),($3,$4)',[cleaner,pending,off,zone]);
  const schedule=(await db.query("INSERT INTO cleaner_work_schedule_requests(cleaner_id,week_start,days,status) VALUES($1,'2039-01-31','[]','approved') RETURNING id",[cleaner])).rows[0];
  await db.query("INSERT INTO cleaner_working_days(cleaner_id,work_date,start_time,end_time,request_id) VALUES($1,'2039-02-03','08:00','18:00',$2),($1,'2039-02-04','00:00','02:00',$2)",[cleaner,schedule.id]);
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
  await db.query("UPDATE service_orders SET status='assigned',start_time='18:00',end_time='00:41',estimated_duration_minutes=401 WHERE id=$1",[order]);
  const night=[{startTime:'00:00',endTime:'01:00'},{startTime:'00:41',endTime:'01:41'}];
  assert.deepEqual((await service.availableSlotCounts('2039-02-04',night,zone)).map(s=>s.cleanersCount),[0,1]);
  assert.equal(await service.cleanerAvailable(cleaner,'2039-02-04','00:00','01:00'),false);
  assert.equal(await service.cleanerAvailable(cleaner,'2039-02-04','00:41','01:41'),true);
  assert.equal((await service.availableCleaners('2039-02-04','00:00','01:00',zone,db,true)).length,0);
  await db.query("UPDATE service_orders SET status='completed' WHERE id=$1",[order]);
  await db.query("UPDATE cleaner_work_schedule_requests SET status='pending' WHERE id=$1",[schedule.id]);
  assert.deepEqual((await service.availableSlotCounts('2039-02-03',slots,zone)).map(s=>s.cleanersCount),[0,0,0,0]);
  await db.query("UPDATE cleaner_work_schedule_requests SET status='approved' WHERE id=$1",[schedule.id]);
  assert.deepEqual((await service.availableSlotCounts('2039-02-05',slots,zone)).map(s=>s.cleanersCount),[0,0,0,0]);
  const all=await service.availableSlotCounts('2039-02-03',slots);
  for(let i=0;i<slots.length;i++)assert.equal(all[i].cleanersCount,(await service.availableCleaners('2039-02-03',slots[i].startTime,slots[i].endTime,undefined,db,true)).length);
 }finally{
  await db.query('DELETE FROM service_orders WHERE id=$1',[order]);
  await db.query('DELETE FROM service_zones WHERE id=ANY($1::uuid[])',[[zone,empty]]);
  await db.query('DELETE FROM app_users WHERE id=ANY($1::uuid[])',[[customer,cleaner,pending,off]]);await db.close();
 }
});
