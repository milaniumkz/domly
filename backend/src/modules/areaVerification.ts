import {ApiError} from '../common/api';
import {first} from '../common/sql';
import {Queryable} from '../domain/repositories/UnitOfWork';

export async function confirmArea(client:Queryable,userId:string,addressId:string|null,area:number) {
  if (!Number.isFinite(area) || area<=0) throw new ApiError(400,'invalid_area','Укажите корректную площадь.');
  const user=first<{id:string}>((await client.query("SELECT id FROM app_users WHERE id=$1 AND role='customer' FOR UPDATE",[userId])).rows);
  if (!user) throw new ApiError(404,'not_found','Клиент не найден.');
  const address=first<any>((await client.query(`UPDATE customer_addresses SET area=$3,verified_area=$3,updated_at=NOW()
    WHERE user_id=$1 AND id=COALESCE($2::uuid,(SELECT id FROM customer_addresses WHERE user_id=$1 ORDER BY is_primary DESC,created_at DESC LIMIT 1)) RETURNING *`,[userId,addressId,area])).rows);
  if (addressId && !address) throw new ApiError(404,'address_not_found','Адрес клиента не найден.');
  const key='area-confirmation:'+userId+':'+(address?.id??'profile');
  const existing=(await client.query('SELECT id FROM bonus_transactions WHERE dedupe_key=$1',[key])).rows;
  if (!existing.length) {
    const balance=first<{bonus_balance:string}>((await client.query('UPDATE app_users SET bonus_balance=bonus_balance+2000,updated_at=NOW() WHERE id=$1 RETURNING bonus_balance',[userId])).rows)!;
    await client.query(`INSERT INTO bonus_transactions(user_id,type,amount,balance_after,reason_ru,reason_kk,dedupe_key)
      VALUES($1,'accrual',2000,$2,'Бонус за подтверждение площади','Ауданды растау бонусы',$3)`,[userId,balance.bonus_balance,key]);
  }
  return address;
}
