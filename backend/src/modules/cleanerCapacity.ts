import {Queryable} from '../domain/repositories/UnitOfWork';
import {ApiError} from '../common/api';

export const cleanerAreaNorm=220;
export const cleanerDailyAreaMaximum=250;
export const cleanerOvertimeMinutes=120;

export function orderAreaSql(order:string){
 return `COALESCE(NULLIF(${order}.area,0),(SELECT COALESCE(a.verified_area,a.area) FROM customer_addresses a WHERE a.id=${order}.address_id),0)`;
}
export function cleanerSlotAllowedSql(cleaner:string,date:string,start:string,end:string,duration:string,area:string,exclude='NULL'){
 return `domly_cleaner_slot_allowed((${cleaner})::uuid,(${date})::date,(${start})::time,(${end})::time,(${duration})::int,(${area})::numeric,(${exclude})::uuid)`;
}
export async function assertCleanerCapacity(db:Queryable,cleanerId:string,date:any,start:string,end:string,duration:number,orderId:string){
 const row=(await db.query(`SELECT ${cleanerSlotAllowedSql('$1','$2','$3','$4','$5',"domly_order_cleaner_area(o.id,$1)",'o.id')} allowed FROM service_orders o WHERE o.id=$6`,[cleanerId,date,start,end,duration,orderId])).rows[0];
 if(!row?.allowed)throw new ApiError(409,'cleaner_capacity_exceeded','Уборщица недоступна: уборка должна закончиться не позднее двух часов после смены, а общая площадь за день не должна превышать 250 м². Выберите другое время или дату.');
}
