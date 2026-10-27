import { createHash, timingSafeEqual } from 'node:crypto';
import { env } from '../common/env';
import { ApiError } from '../common/api';
import { FcmService } from './integrations';
import type { Queryable } from '../domain/repositories/UnitOfWork';
import { Database } from '../infrastructure/db/Database';
import type { NotificationService } from './domainServices';
import {MoonMessengerError,sendMessengerFollowup} from './moonMessenger';

export function moonAiReady(): boolean {
  return env.moonAiEnabled && Boolean(env.moonAiChannelUrl && env.moonAiChannelApiKey && env.moonAiWebhookToken);
}
export function verifyMoonToken(headers: Record<string, any>) {
  if (!env.moonAiWebhookToken) throw new ApiError(503,'integration_not_configured','Moon AI не настроен.');
  const token=String(headers['x-moonai-token'] ?? String(headers.authorization ?? '').replace(/^Bearer\s+/i,''));
  const a=Buffer.from(token), b=Buffer.from(env.moonAiWebhookToken);
  if(a.length!==b.length || !timingSafeEqual(a,b)) throw new ApiError(401,'unauthorized','Неверный токен Moon AI.');
}
export async function ensureAssistantChat(db: Database, customerId: string) {
  return db.transaction(async tx=>{
    const chat=(await tx.query(`INSERT INTO chats(type,customer_id) VALUES('assistant',$1)
      ON CONFLICT(customer_id) WHERE type='assistant' DO UPDATE SET customer_id=EXCLUDED.customer_id RETURNING *`,[customerId])).rows[0];
    await tx.query('INSERT INTO chat_participants(chat_id,user_id) VALUES($1,$2) ON CONFLICT DO NOTHING',[chat.id,customerId]);
    return chat;
  });
}
export async function queueMoonInvoice(db: Database, payment: any, description: string) {
  if(!moonAiReady()) throw new ApiError(503,'integration_not_configured','Автоматическое выставление счёта пока не настроено.');
  const phone=String(payment.invoice_phone ?? '').replace(/\D/g,'');
  if(!/^7\d{10}$/.test(phone)) throw new ApiError(400,'invalid_phone','Укажите корректный номер Kaspi.');
  if(!['pending','invoice_requested'].includes(payment.status) || Number(payment.amount)<=0) throw new ApiError(409,'invalid_payment_status','Счёт уже обработан.');
  const chat=await ensureAssistantChat(db,payment.customer_id);
  const text=`Запрос счета Kaspi от приложения DOMLY. phone_number=${phone}; payment_sum=${Number(payment.amount)} KZT; описание: ${description}. Используй подключённую функцию create_order. Не меняй номер или сумму. Не создавай повторный счёт в этом служебном треде. Результат и статус оплаты отправляй в DOMLY через настроенный Custom API: phone, amount, status, dateTime, paymentId=${payment.id}. Сохрани paymentId именно этого счёта и передавай его при каждом изменении статуса; не подставляй ID другого счёта. Сообщи клиенту фактический результат.`;
  await db.transaction(async tx=>{
    const current=(await tx.query('SELECT * FROM payments WHERE id=$1 FOR UPDATE',[payment.id])).rows[0];
    if(!current || current.customer_id!==payment.customer_id || !['pending','invoice_requested'].includes(current.status)) throw new ApiError(409,'invalid_payment_status','Счёт уже обработан.');
    if(Number(current.amount)!==Number(payment.amount) || String(current.invoice_phone).replace(/\D/g,'')!==phone) throw new ApiError(409,'invoice_changed','Данные счёта изменились. Обновите экран.');
    const existing=(await tx.query('SELECT id FROM moon_ai_outbox WHERE dedupe_key=$1',[`invoice:${payment.id}`])).rows[0];
    if(!existing) await tx.query(`INSERT INTO moon_ai_outbox(customer_id,chat_id,payment_id,kind,dedupe_key,payload)
      VALUES($1,$2,$3,'invoice',$4,$5)`,[payment.customer_id,chat.id,payment.id,`invoice:${payment.id}`,{text}]);
    await tx.query("UPDATE payments SET status='invoice_requested',invoice_requested_at=COALESCE(invoice_requested_at,NOW()),updated_at=NOW() WHERE id=$1",[payment.id]);
  });
  const delivery=(await db.query('SELECT state FROM moon_ai_outbox WHERE dedupe_key=$1',[`invoice:${payment.id}`])).rows[0];
  if(['uncertain','failed'].includes(delivery?.state)) throw new ApiError(503,'invoice_delivery_unknown','Не удалось подтвердить выставление счёта. Обратитесь в поддержку, чтобы избежать повторного счёта.');
  return {provider:'moon_ai',queued:true,chatId:chat.id,paymentId:payment.id};
}
export async function scheduleCheckoutFollowup(db: Database, payment: any) {
  if(!env.moonAiEnabled || !payment?.customer_id || Number(payment.amount)<=0 || payment.status==='paid') return;
  const chat=await ensureAssistantChat(db,payment.customer_id);
  await db.query(`INSERT INTO moon_ai_outbox(customer_id,chat_id,payment_id,kind,dedupe_key,payload,run_after)
    VALUES($1,$2,$3,'abandoned_checkout',$4,$5,NOW()+INTERVAL '5 minutes') ON CONFLICT(dedupe_key) DO NOTHING`,
    [payment.customer_id,chat.id,payment.id,`followup:${payment.id}`,{text:`Служебное событие DOMLY: клиент начал оформление покупки, но не завершил оплату за 5 минут. Вежливо уточни, нужна ли помощь с оформлением или оплатой. Не создавай новый счёт без запроса клиента и не утверждай, что покупка оплачена.`}]);
}
export async function queueAssistantMessage(db: Queryable, chatId: string, customerId: string, messageId: string, text: string, fileUrl?: string) {
  if(!moonAiReady()) throw new ApiError(503,'integration_not_configured','Помощник временно недоступен.');
  await db.query(`INSERT INTO moon_ai_outbox(customer_id,chat_id,kind,dedupe_key,payload) VALUES($1,$2,'message',$3,$4) ON CONFLICT(dedupe_key) DO NOTHING`,
    [customerId,chatId,`message:${messageId}`,{text, ...(fileUrl?{fileUrl}: {})}]);
}
export async function processMoonOutbox(db: Database, send: typeof fetch=fetch) {
  if(!moonAiReady()) return {sent:0};
  const url=new URL(env.moonAiChannelUrl);
  if(url.protocol!=='https:' || !(url.hostname==='mooonai.com' || url.hostname.endsWith('.mooonai.com'))) throw new Error('invalid_moon_ai_channel_url');
  // A crash or uncertain HTTP result must not create duplicate Kaspi invoices.
  await db.query(`UPDATE moon_ai_outbox SET state='uncertain',failure_code='delivery_unknown'
    WHERE state='processing' AND started_at<NOW()-INTERVAL '2 minutes'`);
  let sent=0;
  for(let i=0;i<20;i++) {
    const row=await db.transaction(async tx=>{
      const row=(await tx.query(`SELECT o.* FROM moon_ai_outbox o WHERE o.state='pending' AND o.run_after<=NOW()
        AND NOT EXISTS(SELECT 1 FROM moon_ai_outbox running WHERE running.chat_id=o.chat_id AND running.state='processing')
        ORDER BY CASE WHEN o.kind='invoice' THEN 0 WHEN o.kind='area_verification' THEN 1 ELSE 2 END,o.created_at FOR UPDATE SKIP LOCKED LIMIT 1`)).rows[0];
      if(!row)return null;
      await tx.query('SELECT id FROM chats WHERE id=$1 FOR UPDATE',[row.chat_id]);
      if((await tx.query("SELECT 1 FROM moon_ai_outbox WHERE chat_id=$1 AND state='processing' LIMIT 1",[row.chat_id])).rows.length) return {busy:true};
      if(row.kind==='inactive_install') {
        await tx.query("UPDATE moon_ai_outbox SET state='cancelled',failure_code='no_whatsapp_phone',finished_at=NOW() WHERE id=$1",[row.id]);
        return {cancelled:true};
      }
      if(row.kind==='area_verification') {
        const eligible=(await tx.query(`SELECT 1 FROM quality_check_requests q JOIN customer_addresses a ON a.id=q.address_id
          JOIN app_users u ON u.id=q.customer_id
          WHERE q.id=$1 AND q.customer_id=$2 AND q.status='pending' AND q.document_file_id IS NULL
            AND a.verified_area IS NULL AND u.role='customer' AND u.status<>'blocked' AND u.deleted_at IS NULL
            AND NOT EXISTS(SELECT 1 FROM service_orders o WHERE o.customer_id=q.customer_id AND o.address_id=q.address_id
              AND (o.id=q.order_id OR o.customer_package_id=q.customer_package_id) AND o.status IN ('in_progress','completed'))`,[row.payload.qualityCheckId,row.customer_id])).rows.length;
        if(!eligible){await tx.query("UPDATE moon_ai_outbox SET state='cancelled',failure_code='area_check_no_longer_required',finished_at=NOW() WHERE id=$1",[row.id]);return {cancelled:true};}
      }
      if(row.kind==='inactive_signup') {
        if((await tx.query('SELECT 1 FROM payments WHERE customer_id=$1 LIMIT 1',[row.customer_id])).rows.length ||
          (await tx.query("SELECT 1 FROM moon_ai_outbox WHERE customer_id=$1 AND kind='message' LIMIT 1",[row.customer_id])).rows.length) {
          await tx.query("UPDATE moon_ai_outbox SET state='cancelled',finished_at=NOW() WHERE id=$1",[row.id]);return {cancelled:true};
        }
      }
      if(row.installation_id) {
        const guest=(await tx.query('SELECT * FROM assistant_installations WHERE id=$1 FOR UPDATE',[row.installation_id])).rows[0];
        if(!guest || guest.customer_id || (row.kind==='inactive_install' && (await tx.query("SELECT 1 FROM chat_messages WHERE chat_id=$1 AND sender_kind='guest' LIMIT 1",[row.chat_id])).rows.length)) {
          await tx.query("UPDATE moon_ai_outbox SET state='cancelled',finished_at=NOW() WHERE id=$1",[row.id]);return {cancelled:true};
        }
      }
      if(row.payment_id) {
        const p=(await tx.query('SELECT * FROM payments WHERE id=$1 FOR UPDATE',[row.payment_id])).rows[0];
        const purchased=(await tx.query("SELECT 1 FROM payments WHERE customer_id=$1 AND status='paid' AND COALESCE(paid_at,created_at) >= $2 LIMIT 1",[row.customer_id,row.created_at])).rows.length>0;
        const newer=row.kind==='abandoned_checkout' && (await tx.query("SELECT 1 FROM payments WHERE customer_id=$1 AND created_at>$2 AND status IN ('pending','invoice_requested') LIMIT 1",[row.customer_id,row.created_at])).rows.length>0;
        if(!p || ['paid','cancelled','refunded','rejected','failed'].includes(p.status) || (row.kind==='abandoned_checkout' && (purchased || newer))) {
          await tx.query("UPDATE moon_ai_outbox SET state='cancelled',finished_at=NOW() WHERE id=$1",[row.id]);return {cancelled:true};
        }
      }
      await tx.query("UPDATE moon_ai_outbox SET state='processing',started_at=NOW() WHERE id=$1",[row.id]);return row;
    });
    if(!row)break;if(row.cancelled || row.busy)continue;
    try {
      if(!['invoice','message'].includes(row.kind)) {
        const customer=(await db.query('SELECT phone,settings FROM app_users WHERE id=$1',[row.customer_id])).rows[0];
        if(customer?.settings?.whatsappOptOut===true)throw new MoonMessengerError('whatsapp_opted_out');
        const delivery=await sendMessengerFollowup({id:row.id,kind:row.kind,text:row.payload.text,phone:customer?.phone ?? ''},send);
        await db.query(`UPDATE moon_ai_outbox SET state='sent',provider_thread_id=$2,finished_at=NOW(),failure_code=NULL,
          payload=payload || $3::jsonb WHERE id=$1`,[row.id,delivery.threadId,{deliveryChannel:delivery.channel,messengerDelivery:delivery}]);
        sent++;continue;
      }
      const externalThread=row.kind==='invoice'?row.id:`assistant:${row.chat_id}`;
      const source=row.kind==='invoice'?`${env.moonAiSource}_invoice`:env.moonAiSource;
      const body:any={thread_id:externalThread,source,from_type:row.kind==='message'?'user':'manager',message_type:'text',data:{text:row.payload.text}};
      // API-channel manager messages are delivered to the conversation. Agent
      // execution requires from_type=user, including trusted app-generated intents.
      body.from_type='user';
      if(row.payload.fileUrl) {body.message_type='multi';body.data.attachments=[{url:row.payload.fileUrl,filename:'attachment'}];}
      const response=await send(url,{method:'POST',headers:{'X-API-Key':env.moonAiChannelApiKey,'Content-Type':'application/json'},body:JSON.stringify(body),signal:AbortSignal.timeout(15000)});
      const result:any=await response.json().catch(()=>null);
      if(!response.ok || result?.accepted!==true || result.external_thread_id!==externalThread) {
        await db.query("UPDATE moon_ai_outbox SET state=$2,failure_code=$3,finished_at=NOW() WHERE id=$1",[row.id,response.status>=500?'uncertain':'failed',`http_${response.status}`]);continue;
      }
      await db.query("UPDATE moon_ai_outbox SET state='sent',provider_thread_id=$2,finished_at=NOW() WHERE id=$1",[row.id,result.thread_id ?? null]);sent++;
    }catch(error) {
      if(error instanceof MoonMessengerError) {
        await db.query(`UPDATE moon_ai_outbox SET state=$2,failure_code=$3,finished_at=CASE WHEN $2='pending' THEN NULL ELSE NOW() END,
          run_after=CASE WHEN $2='pending' THEN NOW()+INTERVAL '5 minutes' ELSE run_after END WHERE id=$1`,
          [row.id,error.retryable?'pending':error.failureCode.includes('paused')||error.failureCode.includes('opted_out')||error.failureCode.includes('phone_unavailable')?'cancelled':'failed',error.failureCode]);
      } else await db.query("UPDATE moon_ai_outbox SET state='uncertain',failure_code='delivery_unknown',finished_at=NOW() WHERE id=$1",[row.id]);
    }
  }
  return {sent};
}
export async function acceptMoonChatEvent(db: Database, notifications: Pick<NotificationService,'create'>, event: any) {
  const id=String(event.event_id ?? ''),externalThread=String(event.external_thread_id ?? '');
  if(event.source===`${env.moonAiSource}_invoice`) return {accepted:true,ignored:true};
  if(event.source!==env.moonAiSource)throw new ApiError(400,'invalid_source','Неверный источник диалога.');
  // Old proactive API threads and native messenger conversations never enter the app.
  if(!externalThread.startsWith('assistant:'))return {accepted:true,ignored:true};
  const chatId=externalThread.slice('assistant:'.length);
  if(!id || !/^[0-9a-f-]{36}$/i.test(chatId)) throw new ApiError(400,'invalid_event','Нужны event_id и external_thread_id.');
  if(event.thread_id && event.thread_id!==`api:${env.moonAiSource}:${externalThread}`) throw new ApiError(400,'invalid_source','Неверный источник диалога.');
  const chat=(await db.query("SELECT * FROM chats WHERE id=$1 AND type IN ('assistant','assistant_guest')",[chatId])).rows[0];
  if(!chat) throw new ApiError(404,'chat_not_found','Диалог не найден.');
  if(!['agent_message','manager_message'].includes(event.event_type)) return {accepted:true,ignored:true};
  const text=String(event.message?.data?.text ?? '').trim();
  const attachments=event.message?.data?.attachments;
  // Keep complete external attachments in a separate JSON field; never fetch
  // arbitrary webhook URLs with server credentials.
  const files=Array.isArray(attachments)?attachments.filter((a:any)=>typeof a.url==='string'&&a.url.startsWith('https://')).map((a:any)=>({url:a.url,filename:String(a.filename ?? 'Файл')})):[];
  const content=[text,...files.map((f:any)=>`${f.filename}: ${f.url}`)].filter(Boolean).join('\n');
  if(!content) return {accepted:true,ignored:true};
  if(content.length>20000) throw new ApiError(400,'message_too_long','Сообщение слишком длинное.');
  const accepted=await db.transaction(async tx=>{
    await tx.query('SELECT id FROM chats WHERE id=$1 FOR UPDATE',[chatId]);
    const existing=(await tx.query('SELECT id FROM chat_messages WHERE chat_id=$1 AND external_event_id=$2',[chatId,id])).rows[0];
    if(existing)return {message:existing,duplicate:true};
    const request=(await tx.query(`SELECT id,created_at FROM moon_ai_outbox WHERE chat_id=$1 AND kind='message'
      AND state IN ('processing','sent') AND started_at>NOW()-INTERVAL '10 minutes'
      AND COALESCE(payload->>'assistantReplied','false')<>'true' ORDER BY created_at DESC LIMIT 1 FOR UPDATE`,[chatId])).rows[0];
    if(!request)return null;
    const message=(await tx.query(`INSERT INTO chat_messages(chat_id,sender_id,sender_kind,message_ru,external_event_id)
      VALUES($1,NULL,'assistant',$2,$3) ON CONFLICT(external_event_id) WHERE external_event_id IS NOT NULL DO NOTHING RETURNING id`,[chatId,content,id])).rows[0];
    await tx.query(`UPDATE moon_ai_outbox SET payload=payload || '{"assistantReplied":true}'::jsonb
      WHERE chat_id=$1 AND kind='message' AND state IN ('processing','sent')
      AND created_at<=(SELECT created_at FROM moon_ai_outbox WHERE id=$2)`,[chatId,request.id]);
    return {message,duplicate:!message};
  });
  if(!accepted)return {accepted:true,ignored:true};
  const {message}=accepted;
  // Notification has an independent dedupe key, so retries repair a push failure.
  if(chat.customer_id) {
    await notifications.create({userId:chat.customer_id,titleRu:'Помощник Domly',bodyRu:text.slice(0,160)||'Вам прислали файл.',targetType:'assistant_chat',targetId:chatId,dedupeKey:`moon-chat:${id}`});
  } else if(message) {
    const tokens=(await db.query('SELECT token FROM assistant_installation_tokens WHERE installation_id=$1',[chat.installation_id])).rows.map((t:any)=>t.token);
    await new FcmService().send(tokens,'Помощник Domly',text.slice(0,160)||'Новое сообщение',{targetType:'assistant_guest',targetId:chatId});
  }
  return {accepted:true,duplicate:accepted.duplicate};
}

type MoonPaymentStatusInput = {
 key: string; status: string; amount: number|null; phone: string|null;
 externalId: string|null; eventId: string; eventTime: string|null; payload: any;
};
export async function acceptMoonPaymentStatus(db: Database, input: MoonPaymentStatusInput) {
  return db.transaction(tx => applyMoonPaymentStatus(tx, input));
}
async function applyMoonPaymentStatus(tx: Queryable, input: MoonPaymentStatusInput) {
    const p=(await tx.query('SELECT * FROM payments WHERE id::text=$1 OR external_id=$1 LIMIT 1 FOR UPDATE',[input.key])).rows[0];
    if(!p) throw new ApiError(404,'payment_not_found','Платёж не найден.');
    if(p.provider!=='kaspi') throw new ApiError(409,'invalid_provider','Платёж не относится к Kaspi.');
    if(input.amount!==null && Math.round(Number(p.amount)*100)!==Math.round(input.amount*100)) throw new ApiError(409,'amount_mismatch','Сумма оплаты не совпадает со счётом.');
    if(input.phone && p.invoice_phone && input.phone.replace(/\D/g,'')!==String(p.invoice_phone).replace(/\D/g,'')) throw new ApiError(409,'phone_mismatch','Номер оплаты не совпадает со счётом.');
    if(input.status==='paid') {
      if(input.amount===null || Math.round(Number(p.amount)*100)!==Math.round(input.amount*100)) throw new ApiError(409,'amount_mismatch','Сумма оплаты не совпадает со счётом.');
      if(!input.phone || !p.invoice_phone || input.phone.replace(/\D/g,'')!==String(p.invoice_phone).replace(/\D/g,'')) throw new ApiError(409,'phone_mismatch','Номер оплаты не совпадает со счётом.');
    }
    if(input.externalId && p.external_id && input.externalId!==p.external_id) throw new ApiError(409,'invoice_mismatch','ID счёта не совпадает.');
    const event=(await tx.query(`INSERT INTO payment_events(payment_id,provider,event_type,status,external_id,idempotency_key,payload)
      VALUES($1,'kaspi','moon_ai_status',$2,$3,$4,$5) ON CONFLICT(provider,idempotency_key) DO NOTHING RETURNING id`,
      [p.id,input.status,input.externalId,input.eventId,input.payload])).rows[0];
    if(!event) {
      const original=(await tx.query("SELECT payment_id FROM payment_events WHERE provider='kaspi' AND idempotency_key=$1",[input.eventId])).rows[0];
      if(original?.payment_id!==p.id) throw new ApiError(409,'event_conflict','Событие уже относится к другому платежу.');
      return p;
    }
    if(['paid','refunded','cancelled'].includes(p.status)) return p;
    const updated=(await tx.query(`UPDATE payments SET status=$2::payment_status,external_id=COALESCE($3,external_id),
      paid_at=CASE WHEN $2='paid' THEN COALESCE($4::timestamptz,paid_at,NOW()) ELSE paid_at END,
      approval_source=CASE WHEN $2='paid' THEN 'moon_ai' ELSE approval_source END,
      approved_at=CASE WHEN $2='paid' THEN COALESCE($4::timestamptz,NOW()) ELSE approved_at END,
      payload=payload || $5::jsonb,updated_at=NOW() WHERE id=$1 RETURNING *`,
      [p.id,input.status,input.externalId,input.eventTime,{moonAi:input.payload}])).rows[0];
    if(input.status==='paid') await tx.query("UPDATE moon_ai_outbox SET state='cancelled',finished_at=NOW() WHERE customer_id=$1 AND kind='abandoned_checkout' AND state='pending'",[p.customer_id]);
    return updated;
}


export async function matchMoonPaymentStatus(db: Database, input: {
  phone: string; amount: number; status: 'invoice_sent'|'paid'|'rejected'|'cancelled'; dateTime: string; paymentId?: string;
}) {
  const paymentId = input.paymentId;
  if (paymentId !== undefined && (typeof paymentId !== 'string' || !/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(paymentId))) throw new ApiError(400, 'invalid_payment_id', 'Нужен корректный ID платежа.');
  const phone = input.phone.replace(/\D/g, '');
  if (!/^7\d{10}$/.test(phone)) throw new ApiError(400, 'invalid_phone', 'Нужен корректный номер Kaspi.');
  if (!Number.isFinite(input.amount) || input.amount <= 0) throw new ApiError(400, 'invalid_amount', 'Нужна положительная сумма платежа.');
  if (!/^\d{4}-\d{2}-\d{2}T.*(?:Z|[+-]\d{2}:\d{2})$/.test(input.dateTime)) throw new ApiError(400, 'invalid_datetime', 'Передайте дату и время события ISO 8601 с часовым поясом.');
  const time = new Date(input.dateTime);
  if (Number.isNaN(time.getTime()) || time.getTime() > Date.now() + 300000) throw new ApiError(400, 'invalid_datetime', 'Некорректное время события.');
  const amount = Math.round(input.amount * 100) / 100;
  const eventTime = time.toISOString();
  const fingerprint = createHash('sha256').update(JSON.stringify(paymentId ? [phone, amount, input.status, eventTime, paymentId.toLowerCase()] : [phone, amount, input.status, eventTime])).digest('hex');
  return db.transaction(async tx => {
    // Serialize all callbacks sharing this matching key, including duplicates.
    await tx.query('SELECT pg_advisory_xact_lock(hashtextextended($1,0))', [`moon:${phone}:${amount}`]);
    const old = (await tx.query('SELECT * FROM moon_ai_payment_callbacks WHERE fingerprint=$1', [fingerprint])).rows[0];
    if (old) {
      const payment = old.payment_id ? (await tx.query('SELECT * FROM payments WHERE id=$1', [old.payment_id])).rows[0] : null;
      return {resolution: old.resolution as string, duplicate: true, callbackId: old.id as string, candidateIds: old.candidate_ids as string[], payment};
    }
    // Use the original event time, not delivery time: delayed retries cannot
    // confirm a new invoice created after the bank event.
    const candidates = (await tx.query(`SELECT * FROM payments
      WHERE provider='kaspi' AND regexp_replace(invoice_phone,'[^0-9]','','g')=$1 AND amount=$2
        AND invoice_requested_at IS NOT NULL
        AND ($5::uuid IS NULL OR id=$5::uuid)
        AND ($5::uuid IS NOT NULL OR NOT EXISTS (SELECT 1 FROM payments retry
          WHERE retry.payload->>'retryOfPaymentId'=payments.id::text
          AND regexp_replace(retry.invoice_phone,'[^0-9]','','g')=$1 AND retry.amount=$2
          AND retry.invoice_requested_at<=$3::timestamptz))
        AND invoice_requested_at<=$3::timestamptz+INTERVAL '1 second'
        AND invoice_requested_at>=$3::timestamptz-CASE WHEN $4='invoice_sent' THEN INTERVAL '20 minutes' ELSE INTERVAL '72 hours' END
      ORDER BY invoice_requested_at DESC FOR UPDATE`, [phone, amount, eventTime, input.status, paymentId ?? null])).rows;
    const candidateIds = candidates.map(p => String(p.id));
    const resolution = candidates.length === 1 ? 'matched' : candidates.length ? 'ambiguous' : 'not_found';
    const payload = {phone, amount, status: input.status, dateTime: eventTime, ...(paymentId ? {paymentId} : {})};
    const callback = (await tx.query(`INSERT INTO moon_ai_payment_callbacks(fingerprint,phone,amount,status,event_time,payment_id,resolution,candidate_ids,payload)
      VALUES($1,$2,$3,$4,$5,$6,$7,$8,$9) RETURNING id`, [fingerprint, phone, amount, input.status, eventTime, resolution==='matched'?candidates[0].id:null, resolution, candidateIds, payload])).rows[0];
    if (resolution !== 'matched') {
      if (candidateIds.length) await tx.query(`UPDATE payments SET payload=payload || jsonb_build_object('moonAiReview',$2::jsonb) WHERE id=ANY($1::uuid[])`, [candidateIds, {reason: resolution, callbackId: callback.id, ...payload}]);
      return {resolution, duplicate: false, callbackId: callback.id as string, candidateIds, payment: null};
    }
    const payment = await applyMoonPaymentStatus(tx, {key: candidates[0].id, status: input.status==='invoice_sent'?'invoice_requested':input.status,
      amount, phone, externalId: null, eventId: `moon:${fingerprint}`, eventTime, payload});
    return {resolution, duplicate: false, callbackId: callback.id as string, candidateIds, payment};
  });
}

export async function scheduleSignupFollowup(db: Database, customerId: string) {
  if(!env.moonAiEnabled)return;
  const chat=await ensureAssistantChat(db,customerId);
  await db.query(`INSERT INTO moon_ai_outbox(customer_id,chat_id,kind,dedupe_key,payload,run_after)
    VALUES($1,$2,'inactive_signup',$3,$4,NOW()+INTERVAL '5 minutes') ON CONFLICT(dedupe_key) DO NOTHING`,
    [customerId,chat.id,`signup:${customerId}`,{text:'Служебное событие DOMLY: пользователь зарегистрировался 5 минут назад, но не начал оформление покупки. Поздоровайся, предложи помочь выбрать уборку. Не выставляй счёт без явного запроса клиента.'}]);
}
export async function ensureGuestSession(db: Database, key: string) {
  if(!moonAiReady()) throw new ApiError(503,'integration_not_configured','Помощник пока не подключён.');
  if(!/^[a-f0-9]{64}$/i.test(key)) throw new ApiError(400,'invalid_session','Некорректный ключ установки.');
  return db.transaction(async tx=>{
    const guest=(await tx.query(`INSERT INTO assistant_installations(key_hash) VALUES($1)
      ON CONFLICT(key_hash) DO UPDATE SET key_hash=EXCLUDED.key_hash RETURNING *`,[createHash('sha256').update(key).digest('hex')])).rows[0];
    if(guest.customer_id) throw new ApiError(409,'session_bound','Эта установка уже связана с аккаунтом.');
    const chat=(await tx.query(`INSERT INTO chats(type,installation_id) VALUES('assistant_guest',$1)
      ON CONFLICT(installation_id) WHERE type='assistant_guest' DO UPDATE SET installation_id=EXCLUDED.installation_id RETURNING id`,[guest.id])).rows[0];
    await tx.query('UPDATE assistant_installations SET chat_id=$2 WHERE id=$1',[guest.id,chat.id]);
    return {chatId:chat.id};
  });
}
export async function guestSession(db: Database, key: string) {
  if(!/^[a-f0-9]{64}$/i.test(key))throw new ApiError(401,'unauthorized','Войдите в гостевой чат заново.');
  const guest=(await db.query('SELECT * FROM assistant_installations WHERE key_hash=$1 AND customer_id IS NULL',[createHash('sha256').update(key).digest('hex')])).rows[0];
  if(!guest) throw new ApiError(401,'unauthorized','Гостевая сессия недоступна.');
  return guest;
}
export async function bindGuestSession(db: Database, key: string, customerId: string) {
  const hash=createHash('sha256').update(key).digest('hex');
  const target=await ensureAssistantChat(db,customerId);
  await db.transaction(async tx=>{
    const guest=(await tx.query('SELECT * FROM assistant_installations WHERE key_hash=$1 FOR UPDATE',[hash])).rows[0];
    if(!guest || (guest.customer_id && guest.customer_id!==customerId)) throw new ApiError(403,'forbidden','Эта установка недоступна.');
    await tx.query('UPDATE assistant_installations SET customer_id=$2 WHERE id=$1',[guest.id,customerId]);
    await tx.query("UPDATE moon_ai_outbox SET state='cancelled',finished_at=NOW() WHERE installation_id=$1 AND state='pending'",[guest.id]);
    await tx.query('DELETE FROM assistant_installation_tokens WHERE installation_id=$1',[guest.id]);
    // Leave guest transcript isolated; the signed-in chat is a separate scope.
  });
  return target;
}
