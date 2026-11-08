import {ApiError} from '../common/api';

export function apartmentNumber(value:unknown):string|null {
  const number=String(value??'').trim().replace(/^[\s,;'"«»]+|[\s,;'"«»]+$/g,'');
  if(!number)return null;
  if(number.length>64||/[,;\r\n]/.test(number)) {
    throw new ApiError(400,'invalid_apartment','Укажите номер квартиры целиком, без запятых и других адресов.');
  }
  return number;
}
