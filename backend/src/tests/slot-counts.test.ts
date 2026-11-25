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

test('team planning splits money exactly without multiplying the customer price',async()=>{
 const {equalShares,minimumTeamSize,teamEndTime,teamDurationAfterAddonChange}=await import('../modules/cleaningTeam');
 assert.deepEqual([250,250.01,500,500.01,800].map(minimumTeamSize),[1,2,2,3,4]);
 assert.deepEqual(equalShares(100,3),[33.34,33.33,33.33]);
 assert.equal(equalShares(8455,3).reduce((n,x)=>n+Math.round(x*100),0),845500);
 assert.equal(teamEndTime('18:00',360),'00:00');
 const timing={required_cleaners:2,labor_duration_minutes:201,estimated_duration_minutes:101,status:'assigned'};
 assert.deepEqual(teamDurationAfterAddonChange(timing,0,1),{labor:202,duration:101});
 assert.deepEqual(teamDurationAfterAddonChange(timing,0,30,1),{labor:231,duration:131});
 assert.throws(()=>minimumTeamSize(0));assert.throws(()=>equalShares(1,0));
});

test('whole team is reserved atomically, daily area counts each share and renovation expands for time',{skip:!process.env.DOMLY_INTEGRATION_DATABASE_URL},async()=>{
 const {planCleaningTeam,reserveCleaningTeam}=await import('../modules/cleaningTeam');
 const db=new Database(process.env.DOMLY_INTEGRATION_DATABASE_URL!),customer=randomUUID(),cleaners=[randomUUID(),randomUUID(),randomUUID()],orders=[randomUUID(),randomUUID()],legacy=randomUUID();
 const day='2041-06-03',zone=randomUUID();
 try{
  await db.query("INSERT INTO app_users(id,phone,role,status) VALUES($1,$2,'customer','approved')",[customer,'team-'+customer]);
  await db.query("INSERT INTO service_zones(id,name_ru,city) VALUES($1,'Team fixture','Астана')",[zone]);
  for(const cleaner of cleaners){
   await db.query("INSERT INTO app_users(id,phone,role,status) VALUES($1,$2,'cleaner','approved')",[cleaner,'team-'+cleaner]);
   await db.query("INSERT INTO cleaner_profiles(user_id,verification_status) VALUES($1,'approved')",[cleaner]);
   await db.query('INSERT INTO cleaner_zones(cleaner_id,zone_id) VALUES($1,$2)',[cleaner,zone]);
   const schedule=(await db.query("INSERT INTO cleaner_work_schedule_requests(cleaner_id,week_start,days,status) VALUES($1,'2041-06-03','[]','approved') RETURNING id",[cleaner])).rows[0];
   await db.query("INSERT INTO cleaner_working_days(cleaner_id,work_date,start_time,end_time,request_id) VALUES($1,$2,'08:00','18:00',$3)",[cleaner,day,schedule.id]);
  }
  const base={date:day,startTime:'08:00',area:400,laborMinutes:640,zoneId:zone};
  const plan=(await planCleaningTeam(db,base))!;
  assert.equal(plan.requiredCleaners,2);assert.equal(plan.durationMinutes,320);assert.equal(plan.endTime,'13:20');assert.deepEqual(plan.areaShares,[200,200]);
  const attempts=await Promise.allSettled(orders.map(id=>db.transaction(async tx=>{
   await tx.query("SELECT pg_advisory_xact_lock(hashtextextended('domly:booking-create-reschedule',0))");
   const candidate=await planCleaningTeam(tx,base);if(!candidate)throw new Error('No complete team');
   await tx.query("INSERT INTO service_orders(id,customer_id,scheduled_date,start_time,end_time,estimated_duration_minutes,status,area,total_amount) VALUES($1,$2,$3,'08:00',$4,$5,'pending_assignment',400,100)",[id,customer,day,candidate.endTime,candidate.durationMinutes]);
   await reserveCleaningTeam(tx,id,candidate);return id;
  })));
  assert.equal(attempts.filter(r=>r.status==='fulfilled').length,1);
  assert.equal(attempts.filter(r=>r.status==='rejected').length,1);
  const winner=(attempts.find(r=>r.status==='fulfilled') as PromiseFulfilledResult<string>).value;
  const workloads=(await db.query('SELECT * FROM cleaner_order_workloads WHERE id=$1',[winner])).rows;
  assert.equal(workloads.length,2);assert.equal(workloads.reduce((n,r)=>n+Number(r.area),0),400);assert.equal(workloads.reduce((n,r)=>n+Number(r.total_amount),0),100);
  assert.equal(await planCleaningTeam(db,base),null);
  await db.query("INSERT INTO service_orders(id,customer_id,scheduled_date,start_time,end_time,estimated_duration_minutes,status,area) VALUES($1,$2,$3,'08:00','09:00',60,'waiting_cleaner',20)",[legacy,customer,day]);
  await assert.rejects(new SchedulingService(db).assignOrder(legacy,workloads[0].cleaner_id,customer),(e:any)=>e.code==='cleaner_unavailable');

  await db.query("UPDATE service_orders SET status='completed' WHERE id=$1",[winner]);
  assert.equal(await planCleaningTeam(db,{...base,startTime:'14:00',area:501}),null);
  await db.query("UPDATE service_orders SET status='cancelled' WHERE id=$1",[winner]);
  const renovation=(await planCleaningTeam(db,{...base,area:50,laborMinutes:1250,expandForTime:true}))!;
  assert.equal(renovation.requiredCleaners,2);assert.equal(renovation.durationMinutes,625);
  assert.equal(await planCleaningTeam(db,{...base,area:50,laborMinutes:1250}),null);
 }finally{
  await db.query('DELETE FROM service_orders WHERE id=ANY($1::uuid[])',[[...orders,legacy]]);
  await db.query('DELETE FROM service_zones WHERE id=$1',[zone]);
  await db.query('DELETE FROM app_users WHERE id=ANY($1::uuid[])',[[customer,...cleaners]]);await db.close();
 }
});

test('team accepts individually, replaces only the refusal, completes after last report and shares customer reviews',{skip:!process.env.DOMLY_INTEGRATION_DATABASE_URL},async()=>{
 const {planCleaningTeam,reserveCleaningTeam}=await import('../modules/cleaningTeam');
 const {NotificationService}=await import('../modules/domainServices');
 const {transitionOrder}=await import('../modules/orderLifecycle');
 const {ensureChecklistReport}=await import('../modules/checklists');
 const {saveOrderReview}=await import('../modules/orderReviews');
 const {updateOrderAddons}=await import('../modules/orderAddons');
 const db=new Database(process.env.DOMLY_INTEGRATION_DATABASE_URL!),service=new SchedulingService(db);
 const customer=randomUUID(),cleaners=[randomUUID(),randomUUID(),randomUUID()],orderId=randomUUID(),following=randomUUID(),addon=randomUUID(),zone=randomUUID(),day='2042-06-03';
 const notifications=new NotificationService(db,{send:async()=>({sent:0})} as any);
 try{
  await db.query("INSERT INTO app_users(id,phone,role,status) VALUES($1,$2,'customer','approved')",[customer,'team-life-'+customer]);
  await db.query("INSERT INTO service_zones(id,name_ru,city) VALUES($1,'Team lifecycle','Астана')",[zone]);
  for(const cleaner of cleaners){
   await db.query("INSERT INTO app_users(id,phone,role,status) VALUES($1,$2,'cleaner','approved')",[cleaner,'team-life-'+cleaner]);
   await db.query("INSERT INTO cleaner_profiles(user_id,verification_status) VALUES($1,'approved')",[cleaner]);
   await db.query('INSERT INTO cleaner_zones(cleaner_id,zone_id) VALUES($1,$2)',[cleaner,zone]);
   const schedule=(await db.query("INSERT INTO cleaner_work_schedule_requests(cleaner_id,week_start,days,status) VALUES($1,'2042-06-02','[]','approved') RETURNING id",[cleaner])).rows[0];
   await db.query("INSERT INTO cleaner_working_days(cleaner_id,work_date,start_time,end_time,request_id) VALUES($1,$2,'08:00','18:00',$3)",[cleaner,day,schedule.id]);
  }
  const plan=(await planCleaningTeam(db,{date:day,startTime:'08:00',area:400,laborMinutes:640,zoneId:zone}))!;
  await db.query("INSERT INTO service_orders(id,customer_id,scheduled_date,start_time,end_time,estimated_duration_minutes,status,area,total_amount) VALUES($1,$2,$3,'08:00',$4,320,'pending_assignment',400,100)",[orderId,customer,day,plan.endTime]);
  await reserveCleaningTeam(db,orderId,plan);
  const offers=await service.offerNextCleaner(orderId) as any;
  assert.equal(offers.teamOffers.length,2);
  const first=offers.teamOffers[0].cleaner_id,refused=offers.teamOffers[1].cleaner_id;
  assert.equal((await service.acceptOffer(orderId,first) as any).status,'pending_assignment');
  const next=await service.declineOffer(orderId,refused) as any;
  assert.ok(next);assert.notEqual(next.cleaner_id,refused);assert.notEqual(next.cleaner_id,first);
  assert.equal((await db.query('SELECT status FROM order_team_members WHERE order_id=$1 AND cleaner_id=$2',[orderId,first])).rows[0].status,'accepted');
  const assigned=await service.acceptOffer(orderId,next.cleaner_id) as any;
  assert.equal(assigned.status,'assigned');
  await db.query("INSERT INTO service_orders(id,customer_id,cleaner_id,scheduled_date,start_time,end_time,estimated_duration_minutes,status,area) VALUES($1,$2,$3,$4,'14:00','15:00',60,'assigned',20)",[following,customer,first,day]);
  await db.query("INSERT INTO catalog_addons(id,title_ru,price,duration_minutes,active) VALUES($1,'Team addon fixture',100,120,TRUE)",[addon]);
  await assert.rejects(updateOrderAddons(db,orderId,customer,[{id:addon,quantity:1}]),(e:any)=>e.code==='cleaner_unavailable');
  assert.equal((await db.query('SELECT estimated_duration_minutes FROM service_orders WHERE id=$1',[orderId])).rows[0].estimated_duration_minutes,320);
  assert.equal((await db.query('SELECT COUNT(*)::int n FROM order_addons WHERE order_id=$1',[orderId])).rows[0].n,0);
  await db.query('UPDATE catalog_addons SET duration_minutes=60 WHERE id=$1',[addon]);
  const extended=await updateOrderAddons(db,orderId,customer,[{id:addon,quantity:1}]);
  assert.equal((extended.order as any).estimated_duration_minutes,350);assert.equal((extended.order as any).labor_duration_minutes,700);
  await db.query("UPDATE order_addons SET payment_status='paid' WHERE order_id=$1",[orderId]);
  await db.query('UPDATE service_orders SET payable_amount=0 WHERE id=$1',[orderId]);

  assert.equal((await db.query('SELECT domly_order_has_cleaner($1,$2) allowed',[orderId,next.cleaner_id])).rows[0].allowed,true);
  await transitionOrder(db,notifications,orderId,{id:first,role:'cleaner'},'in_progress');
  await transitionOrder(db,notifications,orderId,{id:customer,role:'customer'},'confirm_start');
  await transitionOrder(db,notifications,orderId,{id:next.cleaner_id,role:'cleaner'},'in_progress');
  await assert.rejects(transitionOrder(db,notifications,orderId,{id:first,role:'cleaner'},'completed'),(e:any)=>e.code==='checklist_required');
  const reports=[];
  for(const id of [first,next.cleaner_id]){
   const report=await ensureChecklistReport(db,{...assigned,cleaner_id:id,report_cleaner_id:id,status:'in_progress'});reports.push(report.id);
   await db.query('UPDATE checklist_report_items SET checked=TRUE WHERE report_id=$1',[report.id]);
   await db.query("INSERT INTO team_photo_reports(order_id,cleaner_id,photo_urls) VALUES($1,$2,'[\"fixture/1\",\"fixture/2\",\"fixture/3\"]')",[orderId,id]);
  }
  assert.notEqual(reports[0],reports[1]);
  await transitionOrder(db,notifications,orderId,{id:first,role:'cleaner'},'completed');
  assert.equal((await db.query('SELECT status FROM service_orders WHERE id=$1',[orderId])).rows[0].status,'in_progress');
  await transitionOrder(db,notifications,orderId,{id:next.cleaner_id,role:'cleaner'},'completed');
  assert.equal((await db.query('SELECT status FROM service_orders WHERE id=$1',[orderId])).rows[0].status,'completed');
  const review=await saveOrderReview(db,{id:customer,role:'customer'},{orderId,rating:5,comment:'Fixture team review'});
  assert.equal(review.results.length,2);
  for(const id of [first,next.cleaner_id]){
   assert.equal(Number((await db.query('SELECT rating FROM app_users WHERE id=$1',[id])).rows[0].rating),5);
   await saveOrderReview(db,{id,role:'cleaner'},{orderId,rating:4});
  }
  assert.equal((await db.query('SELECT COUNT(*)::int n FROM reviews WHERE order_id=$1',[orderId])).rows[0].n,4);
 }finally{
  await db.query('DELETE FROM notifications WHERE target_id=$1',[orderId]);
  await db.query('DELETE FROM reviews WHERE order_id=$1',[orderId]);
  await db.query('DELETE FROM service_orders WHERE id=ANY($1::uuid[])',[[orderId,following]]);
  await db.query('DELETE FROM catalog_addons WHERE id=$1',[addon]);
  await db.query('DELETE FROM service_zones WHERE id=$1',[zone]);
  await db.query('DELETE FROM app_users WHERE id=ANY($1::uuid[])',[[customer,...cleaners]]);await db.close();
 }
});
