import {Database} from '../infrastructure/db/Database';
import {ApiError} from '../common/api';

export const bookingLock='domly:booking-create-reschedule';
/** Pending orders consume capacity too, even before a cleaner accepts them.
 * Subtract every overlapping pending job conservatively: never promise the same
 * remaining cleaner to two callers. Assigned jobs are excluded by the scheduler.
 */
export async function pendingBookingCount(db:Database,date:string,start:string,duration:number){
 return Number((await db.query(`SELECT COUNT(*)::int AS count FROM service_orders o
  WHERE o.cleaner_id IS NULL AND o.status NOT IN ('cancelled','completed')
  AND o.scheduled_date+o.start_time < $1::date+$2::time+$3::int*INTERVAL '1 minute'
  AND cleaning_end_at(o.scheduled_date,o.start_time,o.end_time,o.estimated_duration_minutes)>$1::date+$2::time`,[date,start,duration])).rows[0].count);
}
export async function checkBotBookingCapacity(db:Database,customerId:string,date:string,start:string,duration:number,freeCleaners:number){
 const overlap=(await db.query(`SELECT id FROM service_orders o WHERE customer_id=$1 AND status NOT IN ('cancelled','completed')
  AND o.scheduled_date+o.start_time < $2::date+$3::time+$4::int*INTERVAL '1 minute'
  AND cleaning_end_at(o.scheduled_date,o.start_time,o.end_time,o.estimated_duration_minutes)>$2::date+$3::time LIMIT 1`,[customerId,date,start,duration])).rows[0];
 if(overlap)throw new ApiError(409,'customer_booking_overlap','У клиента уже есть уборка в это время.');
 if(freeCleaners<=await pendingBookingCount(db,date,start,duration))throw new ApiError(409,'slot_unavailable','На это время нет свободных уборщиц. Загрузите доступное время заново.');
}
