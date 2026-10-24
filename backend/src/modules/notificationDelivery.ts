import {randomUUID} from 'node:crypto';
import {Database} from '../infrastructure/db/Database';
import type {NotificationInput} from './domainServices';

type Delivery = (row: any, input: NotificationInput) => Promise<void>;
/** Claim committed work only. A lease permits recovery after a worker restart. */
export async function processNotificationDeliveries(db: Database, deliver: Delivery, limit=32) {
 const token=randomUUID();
 const rows=(await db.query(`WITH pending AS (
   SELECT notification_id FROM notification_deliveries
   WHERE delivered_at IS NULL AND available_at<=NOW() AND (lease_until IS NULL OR lease_until<NOW())
   ORDER BY available_at,created_at LIMIT $1 FOR UPDATE SKIP LOCKED
 ) UPDATE notification_deliveries d SET lease_token=$2,lease_until=NOW()+INTERVAL '5 minutes',attempts=attempts+1
 FROM pending WHERE d.notification_id=pending.notification_id RETURNING d.*`,[limit,token])).rows;
 let next=0,delivered=0,failed=0;
 await Promise.all(Array.from({length:Math.min(4,rows.length)},async()=>{
  while(next<rows.length){const item=rows[next++];
   try {
    const row=(await db.query('SELECT * FROM notifications WHERE id=$1',[item.notification_id])).rows[0];
    if(row)await deliver(row,item.payload);
    await db.query(`UPDATE notification_deliveries SET delivered_at=NOW(),lease_until=NULL,lease_token=NULL,last_error=NULL
      WHERE notification_id=$1 AND lease_token=$2`,[item.notification_id,token]);
    delivered++;
   } catch(error) {
    failed++;
    await db.query(`UPDATE notification_deliveries SET lease_until=NULL,lease_token=NULL,last_error=$3,
      available_at=NOW()+($4::int*INTERVAL '1 second') WHERE notification_id=$1 AND lease_token=$2`,
      [item.notification_id,token,error instanceof Error?error.name:'DeliveryError',Math.min(300,2**Math.min(item.attempts,8))]);
   }
  }
 }));
 return {claimed:rows.length,delivered,failed};
}
