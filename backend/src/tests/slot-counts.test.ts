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

test('approved shift permits two hours overtime, daily cap counts completed work and concurrent accepts cannot exceed 250 m²',{skip:!process.env.DOMLY_INTEGRATION_DATABASE_URL},async()=>{
 const db=new Database(process.env.DOMLY_INTEGRATION_DATABASE_URL!),service=new SchedulingService(db);
 const customer=randomUUID(),a=randomUUID(),b=randomUUID(),address=randomUUID(),completed=randomUUID(),assigned=randomUUID(),full=randomUUID(),cancelled=randomUUID(),tooLong=randomUUID(),tooLarge=randomUUID(),first=randomUUID(),second=randomUUID();
 const orderIds=[completed,assigned,full,cancelled,tooLong,tooLarge,first,second],day='2039-07-06';
 try {
  for(const [id,role] of [[customer,'customer'],[a,'cleaner'],[b,'cleaner']])await db.query("INSERT INTO app_users(id,phone,role,status) VALUES($1,$2,$3,'approved')",[id,'capacity-'+id,role]);
  await db.query("INSERT INTO cleaner_profiles(user_id,verification_status) VALUES($1,'approved'),($2,'approved')",[a,b]);
  await db.query("INSERT INTO customer_addresses(id,user_id,city,street,house,area,verified_area) VALUES($1,$2,'Астана','Fixture','1',110,100)",[address,customer]);
  for(const id of [a,b]){
   const schedule=(await db.query("INSERT INTO cleaner_work_schedule_requests(cleaner_id,week_start,days,status) VALUES($1,'2039-07-04','[]','approved') RETURNING id",[id])).rows[0];
   await db.query("INSERT INTO cleaner_working_days(cleaner_id,work_date,start_time,end_time,request_id) VALUES($1,$2,'08:00','18:00',$3)",[id,day,schedule.id]);
  }
  await db.query("INSERT INTO service_orders(id,customer_id,cleaner_id,address_id,scheduled_date,start_time,end_time,status,area) VALUES($1,$5,$6,$8,$9,'08:00','09:00','completed',NULL),($2,$5,$6,NULL,$9,'10:00','12:00','assigned',120),($3,$5,$7,NULL,$9,'08:00','15:00','completed',250),($4,$5,$6,NULL,$9,'08:00','09:00','cancelled',999)",[completed,assigned,full,cancelled,customer,a,b,address,day]);
  const intervals=[{startTime:'18:00',endTime:'20:00',durationMinutes:120},{startTime:'18:00',endTime:'20:01',durationMinutes:121},{startTime:'17:00',endTime:'20:00',durationMinutes:180},{startTime:'18:00',endTime:'19:59',durationMinutes:121}];
  assert.deepEqual((await service.availableSlotCounts(day,intervals,undefined,{area:30})).map(s=>s.cleanersCount),[1,0,1,0]);
  assert.deepEqual((await service.availableSlotCounts(day,intervals,undefined,{area:30.01})).map(s=>s.cleanersCount),[0,0,0,0]);
  assert.equal((await service.availableCleaners(day,'18:00','20:00',undefined,db,true,120,30)).length,1);
  assert.equal((await service.availableCleaners(day,'18:00','20:01',undefined,db,true,121,30)).length,0);
  assert.equal((await service.availableSlotCounts(day,[intervals[0]],undefined,{area:120,excludeOrderId:assigned,cleanerId:a}))[0].cleanersCount,1);
  // If another cleaner has room, the client must still see this slot.
  await db.query("UPDATE service_orders SET status='cancelled' WHERE id=$1",[full]);
  assert.equal((await service.availableSlotCounts(day,[intervals[0]],undefined,{area:31}))[0].cleanersCount,1);
  await db.query("UPDATE service_orders SET status='completed' WHERE id=$1",[full]);
  for(const [id,area,start,end,minutes] of [[tooLong,20,'18:00','20:01',121],[tooLarge,31,'18:00','20:00',120],[first,20,'14:00','15:00',60],[second,20,'16:00','17:00',60]]){
   await db.query("INSERT INTO service_orders(id,customer_id,scheduled_date,start_time,end_time,estimated_duration_minutes,area,status) VALUES($1,$2,$3,$4,$5,$6,$7,'waiting_cleaner')",[id,customer,day,start,end,minutes,area]);
  }
  assert.equal(await service.offerNextCleaner(tooLong),null);assert.equal(await service.offerNextCleaner(tooLarge),null);
  await assert.rejects(service.assignOrder(tooLong,a,customer),(e:any)=>e.code==='cleaner_capacity_exceeded');
  await assert.rejects(service.assignOrder(tooLarge,a,customer),(e:any)=>e.code==='cleaner_capacity_exceeded');
  for(const id of [first,second])await db.query("INSERT INTO order_offers(order_id,cleaner_id,status,expires_at) VALUES($1,$2,'offered',NOW()+INTERVAL '10 minutes')",[id,a]);
  const accepted=await Promise.allSettled([service.acceptOffer(first,a),service.acceptOffer(second,a)]);
  assert.equal(accepted.filter(r=>r.status==='fulfilled').length,1);
  assert.equal(accepted.filter(r=>r.status==='rejected'&&r.reason.code==='cleaner_capacity_exceeded').length,1);
  assert.equal((await db.query("SELECT COUNT(*)::int n FROM service_orders WHERE id=ANY($1::uuid[]) AND cleaner_id=$2",[[first,second],a])).rows[0].n,1);
  const remaining=(await service.availableSlotCounts(day,[intervals[0]],undefined,{area:10}))[0].cleanersCount;
  assert.equal(remaining,1);assert.equal((await service.availableSlotCounts(day,[intervals[0]],undefined,{area:10.01}))[0].cleanersCount,0);
 }finally {
  await db.query('DELETE FROM order_offers WHERE order_id=ANY($1::uuid[])',[orderIds]);
  await db.query('DELETE FROM order_status_history WHERE order_id=ANY($1::uuid[])',[orderIds]);
  await db.query('DELETE FROM service_orders WHERE id=ANY($1::uuid[])',[orderIds]);
  await db.query('DELETE FROM customer_addresses WHERE id=$1',[address]);
  await db.query('DELETE FROM app_users WHERE id=ANY($1::uuid[])',[[customer,a,b]]);await db.close();
 }
});
