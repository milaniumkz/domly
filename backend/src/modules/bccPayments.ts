import { ApiError } from '../common/api';
import { Database } from '../infrastructure/db/Database';
import { bccConfig, bccResultStatus, postBccFields } from './bcc';
import type { PaymentGatewayService } from './integrations';

// Callback/return data is only a signal to ask the bank; never a payment proof.
export async function reconcileBccPayment(db: Database, gateway: PaymentGatewayService, payment: any,
  send: typeof postBccFields = postBccFields) {
  const purchase = payment.payload?.providerPayload;
  if (payment.provider!=='bcc' || !purchase?.ORDER || !payment.external_id) throw new ApiError(409,'bcc_session_missing','Сначала откройте онлайн-оплату.');
  const config = bccConfig();
  if (purchase.TERMINAL!==config.terminalId || payment.payload?.bccTestMode!==config.test) throw new ApiError(409,'bcc_environment_changed','Режим банка изменён. Откройте оплату снова.');
  const request = await gateway.createBccStatusCheck({paymentId:payment.id,externalOrderId:purchase.ORDER});
  const result = await send(request.providerPayload);
  const status = bccResultStatus(result);
  if (String(result.ORDER ?? '')!==String(purchase.ORDER) || String(result.TERMINAL ?? '')!==config.terminalId)
    throw new ApiError(502,'bcc_payment_mismatch','Ответ банка относится к другому платежу.');
  if (status==='paid' && (Math.round(Number(result.AMOUNT ?? result.TRAN_AMOUNT)*100)!==Math.round(Number(payment.amount)*100)
    || String(result.CURRENCY ?? '')!=='398')) throw new ApiError(502,'bcc_amount_mismatch','Сумма в ответе банка не совпадает с платежом.');
  return db.transaction(async tx=>{
    const current = (await tx.query('SELECT * FROM payments WHERE id=$1 FOR UPDATE',[payment.id])).rows[0];
    if (!current) throw new ApiError(404,'not_found','Платёж не найден.');
    if (['paid','refunded'].includes(current.status)) return {payment:current,testMode:config.test,bankStatus:status,changed:false};
    const oldBankStatus = current.payload?.bccBankStatus;
    // The public sandbox key cannot prove a real purchase. Preserve manual approval.
    const nextStatus = config.test && status==='paid' ? current.status : status;
    const updated = (await tx.query(
      `UPDATE payments SET status=$2::payment_status, payload=payload || $3::jsonb,
       approval_source=CASE WHEN $2::text='paid' THEN 'bcc' ELSE approval_source END,
       approved_at=CASE WHEN $2::text='paid' THEN COALESCE(approved_at,NOW()) ELSE approved_at END,
       paid_at=CASE WHEN $2::text='paid' THEN COALESCE(paid_at,NOW()) ELSE paid_at END,updated_at=NOW() WHERE id=$1 RETURNING *`,
      [payment.id,nextStatus,{bccTestMode:config.test,bccBankStatus:status,bccBankResult:result,bccLastCheckedAt:new Date().toISOString()}],
    )).rows[0];
    return {payment:updated,testMode:config.test,bankStatus:status,changed:oldBankStatus!==status};
  });
}
