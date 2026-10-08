import {ApiError} from '../common/api';
export function validatePromotionBody(body:any,partial=false) {
  const bad=(message:string)=>{throw new ApiError(400,'invalid_request',message);};
  if(!partial || body.titleRu!==undefined) if(typeof body.titleRu!=='string'||!body.titleRu.trim())bad('Укажите название акции.');
  if(body.packageId && (typeof body.packageId!=='string'||!/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(body.packageId)))bad('Выберите пакет из списка.');
  if(body.rewardType!==undefined && !['fixed','percent'].includes(body.rewardType))bad('Выберите фиксированную сумму или процент.');
  if(body.rewardValue!==undefined && (!Number.isFinite(Number(body.rewardValue))||Number(body.rewardValue)<0|| (body.rewardType==='percent' && Number(body.rewardValue)>100)))bad('Укажите корректную сумму или процент бонуса.');
  if(body.maxBonusSpendPercent!=null && (!Number.isFinite(Number(body.maxBonusSpendPercent))||Number(body.maxBonusSpendPercent)<0||Number(body.maxBonusSpendPercent)>100))bad('Лимит списания должен быть от 0 до 100%.');
  if(body.presentation!=null && (typeof body.presentation!=='object'||Array.isArray(body.presentation)))bad('Некорректное оформление акции.');
}
