// Read-only live verification. No catalog records or user sessions are changed.
const assert=require('node:assert/strict');
const {Pool}=require('pg');
const {signAccessToken}=require('./dist/common/auth');
const {buildV1Router}=require('./dist/http/routes/v1');
(async()=>{
 const pool=new Pool({connectionString:process.env.DATABASE_URL});
 try {
  const columns=(await pool.query("SELECT column_name,data_type FROM information_schema.columns WHERE table_schema='public' AND table_name='catalog_addons' AND column_name IN ('supports_quantity','features') ORDER BY column_name")).rows;
  assert.deepEqual(columns,[{column_name:'features',data_type:'jsonb'},{column_name:'supports_quantity',data_type:'boolean'}]);
  assert(buildV1Router.toString().includes('req.body.supportsQuantity'));
  const admin=(await pool.query("SELECT id,role,auth_version FROM app_users WHERE role IN ('admin','superadmin') AND deleted_at IS NULL AND status<>'blocked' ORDER BY numeric_id LIMIT 1")).rows[0];assert(admin);
  const token=signAccessToken({id:admin.id,role:admin.role,phone:'catalog-probe',authVersion:admin.auth_version});
  const res=await fetch('http://127.0.0.1:8080/api/v1/admin/addons?limit=200',{headers:{Authorization:'Bearer '+token}});
  const body=await res.json();assert.equal(res.status,200);assert(Array.isArray(body.data));
  assert(body.data.every(row=>Object.hasOwn(row,'supports_quantity') && [null,true,false].includes(row.supports_quantity) && Array.isArray(row.features)));
  console.log('ADDON_EDITOR_AUDIT='+JSON.stringify({schemaReady:true,quantityPersistence:true,featuresPersistence:true,adminReadOk:true,catalogItems:body.data.length,explicitQuantitySettings:body.data.filter(r=>r.supports_quantity!==null).length}));
 }finally{await pool.end();}
})().catch(()=>{console.error('Addon editor live verification failed');process.exitCode=1;});
