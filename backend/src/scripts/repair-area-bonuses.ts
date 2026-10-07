import {Database} from '../infrastructure/db/Database';
import {env} from '../common/env';
import {confirmArea} from '../modules/areaVerification';

async function main() {
  const db=new Database(env.databaseUrl);
  let credited=0;
  try {
    const checks=(await db.query(`SELECT DISTINCT ON(customer_id,COALESCE(address_id::text,'profile')) customer_id,address_id,COALESCE(approved_area,requested_area) AS area
      FROM quality_check_requests WHERE status='approved' AND COALESCE(approved_area,requested_area)>0
      ORDER BY customer_id,COALESCE(address_id::text,'profile'),updated_at DESC`)).rows;
    for(const check of checks) {
      credited+=await db.transaction(async client=>{
        const before=Number((await client.query('SELECT bonus_balance FROM app_users WHERE id=$1 FOR UPDATE',[check.customer_id])).rows[0].bonus_balance);
        await confirmArea(client,check.customer_id,check.address_id,Number(check.area));
        const after=Number((await client.query('SELECT bonus_balance FROM app_users WHERE id=$1',[check.customer_id])).rows[0].bonus_balance);
        return after>before?1:0;
      });
    }
    console.log('Area bonus reconciliation:',checks.length,'approved apartments checked;',credited,'missing rewards credited.');
  } finally {await db.close();}
}
main().catch(error=>{console.error('Area bonus reconciliation failed:',error.message);process.exitCode=1;});
