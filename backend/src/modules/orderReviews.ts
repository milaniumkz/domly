import {ApiError} from '../common/api';
import {Database} from '../infrastructure/db/Database';
import {first} from '../common/sql';

export async function saveOrderReview(db:Database,actor:{id:string;role:string},input:any) {
  const rating=Number(input.rating);
  if(!Number.isInteger(rating)||rating<1||rating>5)throw new ApiError(400,'invalid_rating','Выберите оценку от 1 до 5.');
  if(!input.orderId)throw new ApiError(400,'order_required','Выберите заказ для оценки.');
  return db.transaction(async tx=>{
    const order=first<any>((await tx.query('SELECT * FROM service_orders WHERE id=$1 FOR UPDATE',[input.orderId])).rows);
    if(!order)throw new ApiError(404,'not_found','Заказ не найден.');
    const cleaner=actor.role==='cleaner';
    if(!['customer','cleaner'].includes(actor.role)||(cleaner?order.cleaner_id:order.customer_id)!==actor.id)throw new ApiError(403,'forbidden','Оценить можно только участника своего заказа.');
    if(order.status!=='completed')throw new ApiError(409,'order_not_completed','Оценить можно после завершения уборки.');
    if(!order.cleaner_id)throw new ApiError(409,'cleaner_required','У заказа не назначена уборщица.');
    const existing=first<any>((await tx.query('SELECT id FROM reviews WHERE order_id=$1 AND author_role=$2 ORDER BY created_at DESC LIMIT 1',[order.id,actor.role])).rows);
    const positive=Array.isArray(input.positiveTraits)?input.positiveTraits.map(String).filter(Boolean):[];
    const negative=Array.isArray(input.negativeTraits)?input.negativeTraits.map(String).filter(Boolean):[];
    const params=[order.customer_id,order.cleaner_id,order.id,rating,input.comment??null,input.photoUrl??null,JSON.stringify(positive),JSON.stringify(negative),actor.role];
    const review=first<any>((await tx.query(existing?`UPDATE reviews SET rating=$1,comment=$2,photo_url=$3,positive_traits=$4,negative_traits=$5 WHERE id=$6 RETURNING *`:
      `INSERT INTO reviews(customer_id,cleaner_id,order_id,rating,comment,photo_url,positive_traits,negative_traits,author_role) VALUES($1,$2,$3,$4,$5,$6,$7,$8,$9) RETURNING *`,existing?[rating,input.comment??null,input.photoUrl??null,JSON.stringify(positive),JSON.stringify(negative),existing.id]:params)).rows)!;
    const target=cleaner?order.customer_id:order.cleaner_id;
    const column=cleaner?'customer_id':'cleaner_id';
    await tx.query(`UPDATE app_users SET rating=(SELECT ROUND(AVG(rating)::numeric,2) FROM reviews WHERE ${column}=$1 AND author_role=$2),updated_at=NOW() WHERE id=$1`,[target,actor.role]);
    return {review,created:!existing,target};
  });
}
