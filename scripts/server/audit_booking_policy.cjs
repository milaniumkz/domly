// Read-only production verification: no customer, purchase or order is created.
const assert=require('node:assert/strict');
const {Pool}=require('pg');
const {signAccessToken}=require('./dist/common/auth');
const {validateBookingStart,earliestBookingDate,isBookableDate}=require('./dist/modules/bookingValidation');
(async()=>{
  const pool=new Pool({connectionString:process.env.DATABASE_URL});
  try {
    const now=Date.now(),today=new Date(now+5*3600000).toISOString().slice(0,10),tomorrow=earliestBookingDate(now);
    assert.equal(isBookableDate(today,now),false);assert.equal(isBookableDate(tomorrow,now),true);
    assert.throws(()=>validateBookingStart(today,'18:00',now),e=>e.code==='booking_from_tomorrow');
    validateBookingStart(tomorrow,'08:00',now);
    const admin=(await pool.query("SELECT id,role,auth_version FROM app_users WHERE role IN ('admin','superadmin') AND deleted_at IS NULL AND status<>'blocked' ORDER BY numeric_id LIMIT 1")).rows[0];
    assert(admin,'An active administrator is required for the read-only API probe');
    const token=signAccessToken({id:admin.id,role:admin.role,phone:'server-policy-probe',authVersion:admin.auth_version});
    const response=await fetch('http://127.0.0.1:8080/api/v1/scheduling/available-slots?date='+today,{headers:{Authorization:'Bearer '+token}});
    const body=await response.json();assert.equal(response.status,200);assert.deepEqual(body.data,[]);
    const methods=await (await fetch('http://127.0.0.1:8080/api/v1/payments/methods')).json();
    assert.equal(methods.data.online,true);assert.equal(methods.data.onlineTest,false);
    console.log('BOOKING_POLICY_AUDIT='+JSON.stringify({today,earliestBookingDate:tomorrow,todaySlots:body.data.length,todayRejected:true,tomorrowAllowed:true,payments:methods.data}));
  }finally{await pool.end();}
})().catch(()=>{console.error('Booking policy verification failed');process.exitCode=1;});
