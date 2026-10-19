import {env} from '../common/env';
import {ApiError} from '../common/api';

export function moonMessengerReady(): boolean {
  return Boolean(env.moonAiEnabled && env.moonAiRestApiKey && /^\d+$/.test(env.moonAiOrganizationId) && /^\d+$/.test(env.moonAiAgentId));
}
export function messengerPhone(value: unknown): string {
  let phone=String(value ?? '').replace(/\D/g,'');
  if(phone.length===11 && phone.startsWith('8'))phone='7'+phone.slice(1);
  return /^7\d{10}$/.test(phone)?phone:'';
}
export class MoonMessengerError extends ApiError {
  constructor(public readonly failureCode:string,public readonly retryable=false) {super(503,failureCode,'Не удалось отправить сообщение в WhatsApp.');}
}

// Native messenger conversations never share the application's API-channel thread.
export async function sendMessengerFollowup(input:{id:string;kind:string;text:string;phone:string},send:typeof fetch=fetch) {
  if(!moonMessengerReady())throw new MoonMessengerError('whatsapp_not_configured',true);
  const phone=messengerPhone(input.phone);
  if(!phone)throw new MoonMessengerError('whatsapp_phone_unavailable');
  const base=`https://core.mooonai.com/api/v1/organizations/${env.moonAiOrganizationId}/agents/${env.moonAiAgentId}`;
  async function request(path:string,method='GET',body?:unknown) {
    let response:Response;
    try {response=await send(base+path,{method,headers:{Authorization:`Bearer ${env.moonAiRestApiKey}`,...(body===undefined?{}:{'Content-Type':'application/json'})},
      ...(body===undefined?{}:{body:JSON.stringify(body)}),
      // Background messenger calls have a separate deadline from login codes.
      signal:AbortSignal.timeout(45000)});}
    catch(error){if(method==='GET')throw new MoonMessengerError('whatsapp_lookup_unavailable',true);throw error;}
    const value:any=await response.json().catch(()=>null);
    if(!response.ok)throw new MoonMessengerError(`whatsapp_http_${response.status}`,method==='GET');
    if(value===null)throw new MoonMessengerError('whatsapp_response_unknown',method==='GET');
    return value;
  }
  const found=await request('/threads?'+new URLSearchParams({phone_number:phone,messengers:'whatsapp_business',limit:'100'}));
  if(!Array.isArray(found?.results))throw new MoonMessengerError('whatsapp_lookup_invalid',true);
  const threads=found.results.filter((thread:any)=>thread.channel_type==='whatsapp_business'
    && messengerPhone(thread.metadata?.phone_number)===phone);
  threads.sort((a:any,b:any)=>Date.parse(b.last_message?.at ?? b.modified ?? b.created ?? 0)-Date.parse(a.last_message?.at ?? a.modified ?? a.created ?? 0));
  // Respect a manager's pause, including a customer's request not to be contacted.
  const thread=threads[0];
  if(thread && thread.status!=='active')throw new MoonMessengerError('whatsapp_conversation_paused');
  const reference=`domly:${input.kind}:${input.id}`;
  const intro=input.kind==='area_verification'
    ? 'Перед уборкой нужно подтвердить площадь квартиры. Пришлите в этот WhatsApp-чат чёткий технический план с адресом и общей площадью квартиры. Либо откройте Domly → Профиль → Подтвердить площадь и загрузите техплан: https://domly.kz/customer/#/client/area-confirmation . Если не хотите отправлять документ, напишите — согласуем дату и время проверки отделом качества до уборки.'
    : input.kind==='inactive_signup'
    ? 'Вы зарегистрировались в Domly. Подскажем, как выбрать и оформить уборку.'
    : 'Вы начали оформление уборки в Domly, но оплата пока не завершена. Можем помочь с оформлением или оплатой.';
  if(thread && Date.parse(thread.free_form_window_expires_at ?? '')>Date.now()+30000) {
    const result=await request(`/threads/${encodeURIComponent(thread.id)}/messages`,'POST',{
      data:{text:`Здравствуйте! ${intro} Напишите нам, если нужна помощь.`},message_type:'text',from_type:'manager',
    });
    if(!result?.id)throw new MoonMessengerError('whatsapp_response_unknown');
    // MooonAI pauses AI after a manager message; resume the previously active bot.
    await request(`/threads/${encodeURIComponent(thread.id)}/status`,'PATCH',{status:'active'});
    return {threadId:String(thread.id),delivery:'message',messageId:String(result.id),channel:thread.channel_type,reference};
  }
  const templateId=Number(env.moonAiWabaTemplateId);
  if(!Number.isInteger(templateId)||templateId<=0||!/^\d+$/.test(env.moonAiWabaChannelId))
    throw new MoonMessengerError('whatsapp_template_not_configured',true);
  const templates=await request(`/channels/${env.moonAiWabaChannelId}/whatsapp-templates?status=APPROVED`);
  const template=(templates?.templates ?? []).find((item:any)=>item.id===templateId && item.status==='APPROVED');
  if(!template)throw new MoonMessengerError('whatsapp_template_not_approved',true);
  const variables={'1':intro};
  if(thread) {
    const result=await request(`/threads/${encodeURIComponent(thread.id)}/whatsapp-template`,'POST',{template_id:templateId,variables});
    if(!result?.thread_id)throw new MoonMessengerError('whatsapp_response_unknown');
    await request(`/threads/${encodeURIComponent(result.thread_id)}/status`,'PATCH',{status:'active'});
    return {threadId:String(result.thread_id),delivery:'template',channel:'whatsapp_business'};
  }
  const result=await request(`/channels/${env.moonAiWabaChannelId}/whatsapp-chat/initiate`,'POST',{
    phone:'+'+phone,template_id:templateId,variables,wait_for_delivery:false,
  });
  if(!result?.thread_id || !['enqueued','delivered'].includes(result.delivery_status))
    throw new MoonMessengerError('whatsapp_delivery_'+String(result?.delivery_status ?? 'unknown').replace(/[^a-z_]/g,''));
  await request(`/threads/${encodeURIComponent(result.thread_id)}/status`,'PATCH',{status:'active'});
  return {threadId:String(result.thread_id),delivery:result.delivery_status,channel:'whatsapp_business'};
}
