const {Pool}=require('pg');
(async()=>{
const p=new Pool({connectionString:process.env.DATABASE_URL});const c=await p.connect();
try {
await c.query('BEGIN READ ONLY');
const tables=(await c.query("SELECT tablename FROM pg_tables WHERE schemaname='public' ORDER BY tablename")).rows;
const counts={};for(const {tablename:t} of tables){if(!/^[a-z_]+$/.test(t))throw Error('Unexpected identifier');counts[t]=Number((await c.query(`SELECT COUNT(*) n FROM "${t}"`)).rows[0].n);}
const roles=(await c.query('SELECT role,COUNT(*)::int count FROM app_users GROUP BY role ORDER BY role')).rows;
const admins=(await c.query("SELECT id,numeric_id,role,status,deleted_at,RIGHT(phone,4) phone_suffix FROM app_users WHERE role IN ('admin','superadmin') ORDER BY id")).rows;
const fks=(await c.query(`SELECT conrelid::regclass::text child,confrelid::regclass::text parent,pg_get_constraintdef(oid) definition FROM pg_constraint WHERE contype='f' AND connamespace='public'::regnamespace ORDER BY 1,2`)).rows;
const legacy=(await c.query('SELECT collection_name,COUNT(*)::int count FROM legacy_firestore_documents GROUP BY 1 ORDER BY 1')).rows;
await c.query('COMMIT');console.log('USER_PURGE_AUDIT='+JSON.stringify({counts,roles,admins,fks,legacy}));
}finally{c.release();await p.end();}
})().catch(()=>{console.error('Purge audit failed');process.exitCode=1;});
