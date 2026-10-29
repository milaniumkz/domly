import {approvedWorkStartSql} from './workingSchedule';
import {translateKazakh,sendLocalizedPush} from '../localization';
import {scheduleSignupFollowup, scheduleCheckoutFollowup} from './moonAi';
import { Queryable } from '../domain/repositories/UnitOfWork';
import { referralDiscount } from './referrals';
import crypto from 'crypto';
import { passwordCrypto as bcrypt } from '../common/passwordCrypto';
import { Database } from '../infrastructure/db/Database';
import { ApiError } from '../common/api';
import { first } from '../common/sql';
import { AuthUser, signAccessToken, signRefreshToken } from '../common/auth';
import { env } from '../common/env';
import { WapiOtpService, FcmService } from './integrations';
import { publishToUser, publishToUsers } from '../realtime/sse';

function assertOtpAccountActive(user: {status?: string;deleted_at?: unknown} | undefined) {
  if(user?.deleted_at)throw new ApiError(403,'account_deleted','Аккаунт удалён. В течение 30 дней его можно восстановить через поддержку.');
  if (user?.status === 'blocked') throw new ApiError(403, 'account_blocked', 'Аккаунт заблокирован. Обратитесь в поддержку.');
  if (user?.status === 'rejected') throw new ApiError(403, 'account_rejected', 'Заявка аккаунта отклонена. Обратитесь в поддержку.');
}

export class AuthService {
  constructor(private readonly db: Database, private readonly wapi: WapiOtpService) {}

  async requestOtp(phone: string, role?: AuthUser['role']) {
    if (role !== undefined && !['customer','cleaner'].includes(role)) throw new ApiError(400, 'invalid_role', 'Недопустимый тип аккаунта.');
    const normalized = normalizePhone(phone);
    const user = first<{role: string; status: string}>((await this.db.query(
      'SELECT role,status,deleted_at FROM app_users WHERE phone=$1 AND role=$2', [normalized,role ?? 'customer'],
    )).rows);
    assertOtpAccountActive(user);
    const code = String(crypto.randomInt(100000, 1000000));
    const codeHash = await bcrypt.hash(code, 8);
    await this.db.query(
      `INSERT INTO auth_otp_codes (phone, code_hash, role, expires_at) VALUES ($1, $2, $3, NOW() + INTERVAL '5 minutes')`,
      [normalized, codeHash, role ?? null],
    );
    const until = Date.parse(env.otpFailureFallbackUntil);
    const fallbackActive = Number.isFinite(until) && until > Date.now();
    const mayShowCode = (env.otpShowCode || env.otpFailureFallback || fallbackActive)
      && (!user || ['customer','cleaner'].includes(user.role));
    try {
      await this.wapi.sendOtp(normalized, code);
    } catch (error) {
      if (!mayShowCode) throw error;
      return {phone: normalized, expiresInSeconds: 300, codeSent: false, deliveryFailed: true, fallbackCode: code};
    }
    return { phone: normalized, expiresInSeconds: 300, codeSent: true,
      ...(env.otpShowCode && mayShowCode ? {fallbackCode: code} : {}) };
  }

  async verifyOtp(phone: string, code: string, role: AuthUser['role'] = 'customer') {
    if (!['customer','cleaner'].includes(role)) throw new ApiError(400, 'invalid_role', 'Недопустимый тип аккаунта.');
    const normalized = normalizePhone(phone);
    const otp = first<{ id: string; code_hash: string }>((await this.db.query(
      `SELECT id, code_hash FROM auth_otp_codes
       WHERE phone=$1 AND (role=$2 OR role IS NULL) AND consumed_at IS NULL AND expires_at > NOW()
       ORDER BY created_at DESC LIMIT 1`,
      [normalized,role],
    )).rows);
    if (!otp || !(await bcrypt.compare(code, otp.code_hash))) {
      throw new ApiError(400, 'invalid_otp', 'Неверный или истекший код.');
    }
    const existingUser = first<{ id: string; status: string }>((await this.db.query(
      `SELECT id,status,deleted_at FROM app_users WHERE phone=$1 AND role=$2`,
      [normalized,role],
    )).rows);
    assertOtpAccountActive(existingUser);
    const consumed = await this.db.query(
      `UPDATE auth_otp_codes SET consumed_at=NOW()
       WHERE id=$1 AND consumed_at IS NULL AND expires_at>NOW() RETURNING id`, [otp.id],
    );
    if (!consumed.rows.length) throw new ApiError(400, 'invalid_otp', 'Неверный или истекший код.');
    const user = first<AuthUser>((await this.db.query(
      `INSERT INTO app_users (phone, role, is_phone_verified)
       VALUES ($1, $2, TRUE)
       ON CONFLICT (phone,role) DO UPDATE SET is_phone_verified=TRUE, last_login_at=NOW()
       RETURNING id, role, phone, auth_version AS "authVersion", password_change_required AS "passwordChangeRequired"`,
      [normalized, role],
    )).rows);
    if (!user) throw new ApiError(500, 'auth_failed', 'Не удалось войти. Попробуйте позже.');
    user.sessionId=crypto.randomUUID();
    const refreshToken = signRefreshToken(user);
    await this.db.query(
      `INSERT INTO refresh_sessions (user_id, token_hash, expires_at,id)
       VALUES ($1,$2,NOW() + ($3 || ' seconds')::interval,$4)`,
      [user.id, hashToken(refreshToken), env.jwtRefreshTtlSeconds,user.sessionId],
    );
    if(!existingUser && user.role==='customer') await scheduleSignupFollowup(this.db,user.id);
    return { user, accessToken: signAccessToken(user), refreshToken, isNew: !existingUser };
  }

  async loginWithPassword(phone: string, password: string) {
    const normalized = normalizePhone(phone);
    const candidates = (await this.db.query<AuthUser & { password_hash: string | null; status: string }>(
      `SELECT id, role, phone, password_hash, status, auth_version AS "authVersion", password_change_required AS "passwordChangeRequired"
       FROM app_users
       WHERE phone=$1 AND role IN ('admin','superadmin','cleaner')`,
      [normalized],
    )).rows;
    // Never select an arbitrary profile when multiple password accounts share a phone.
    const matches = [];
    for (const candidate of candidates) {
      if (candidate.password_hash && await bcrypt.compare(password,candidate.password_hash)) matches.push(candidate);
    }
    const user = matches.length === 1 ? matches[0] : null;
    if (!user?.password_hash) {
      throw new ApiError(401, 'invalid_credentials', 'Неверный телефон или пароль.');
    }
    if (user.status === 'blocked') throw new ApiError(403, 'blocked', 'Аккаунт заблокирован.');
    const authUser: AuthUser = { sessionId:crypto.randomUUID(), id: user.id, role: user.role, phone: user.phone, authVersion:user.authVersion, passwordChangeRequired:user.passwordChangeRequired };
    const refreshToken = signRefreshToken(authUser);
    await this.db.query(
      `INSERT INTO refresh_sessions (user_id, token_hash, expires_at,id)
       VALUES ($1,$2,NOW() + ($3 || ' seconds')::interval,$4)`,
      [user.id, hashToken(refreshToken), env.jwtRefreshTtlSeconds,authUser.sessionId],
    );
    return { user: authUser, accessToken: signAccessToken(authUser), refreshToken };
  }

  async logout(input: { userId: string; refreshToken?: string | null; allDevices?: boolean; deviceToken?: string | null }) {
    if (input.refreshToken) {
      await this.db.query(
        `UPDATE refresh_sessions SET revoked_at=NOW()
         WHERE user_id=$1 AND token_hash=$2 AND revoked_at IS NULL`,
        [input.userId, hashToken(input.refreshToken)],
      );
    } else if (input.allDevices === true) {
      await this.db.query(
        `UPDATE refresh_sessions SET revoked_at=NOW()
         WHERE user_id=$1 AND revoked_at IS NULL`,
        [input.userId],
      );
    }
    if (input.deviceToken) {
      await this.db.query(
        `UPDATE device_tokens SET enabled=FALSE, updated_at=NOW()
         WHERE user_id=$1 AND token=$2`,
        [input.userId, input.deviceToken],
      );
    }
    return { loggedOut: true };
  }
}

export interface NotificationInput {
    userId?: string;
    role?: AuthUser['role'];
    titleRu: string;
    bodyRu: string;
    titleKk?: string;
    bodyKk?: string;
    targetType?: string;
    targetId?: string;
    dedupeKey?: string;
}


export class NotificationService {
  constructor(private readonly db: Database, private readonly fcm: FcmService, private readonly queues?: { cleanerAlarms?: { add: Function } }) {}

  private async cleanerAlarmDelayMs(): Promise<number> {
    const rows = (await this.db.query<{ key: string; value: any }>(
      `SELECT key, value FROM app_settings
       WHERE key IN ('cleanerQuietHoursEnabled','cleanerQuietHoursStart','cleanerQuietHoursEnd')`,
    )).rows;
    const settings = Object.fromEntries(rows.map((row) => [row.key, row.value]));
    if (settings.cleanerQuietHoursEnabled !== true) return 1000;
    const start = String(settings.cleanerQuietHoursStart ?? '23:00');
    const end = String(settings.cleanerQuietHoursEnd ?? '07:00');
    const now = new Date();
    const nowMinutes = now.getHours() * 60 + now.getMinutes();
    const [startHour, startMinute] = start.split(':').map(Number);
    const [endHour, endMinute] = end.split(':').map(Number);
    const startMinutes = startHour * 60 + startMinute;
    const endMinutes = endHour * 60 + endMinute;
    const inQuiet = startMinutes <= endMinutes
      ? nowMinutes >= startMinutes && nowMinutes < endMinutes
      : nowMinutes >= startMinutes || nowMinutes < endMinutes;
    if (!inQuiet) return 1000;
    const wake = new Date(now);
    wake.setHours(endHour, endMinute, 0, 0);
    if (nowMinutes >= startMinutes) wake.setDate(wake.getDate() + 1);
    return Math.max(1000, wake.getTime() - now.getTime());
  }

  async persist(input: NotificationInput, queryable: Queryable = this.db) {
    if (!input.userId && input.role && input.dedupeKey) {
      const existing = first((await queryable.query(
        `SELECT * FROM notifications WHERE user_id IS NULL AND role=$1 AND dedupe_key=$2 LIMIT 1`,
        [input.role, input.dedupeKey],
      )).rows);
      if (existing) return { notification: existing, created: false };
    }
    const row = first<{ id: string; user_id: string | null; role: string | null }>((await queryable.query(
      `INSERT INTO notifications (user_id, role, title_ru, title_kk, body_ru, body_kk, target_type, target_id, dedupe_key)
       VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9)
       ON CONFLICT (user_id, dedupe_key) DO NOTHING
       RETURNING *`,
      [input.userId ?? null, input.role ?? null, input.titleRu, input.titleKk ?? translateKazakh(input.titleRu), input.bodyRu, input.bodyKk ?? translateKazakh(input.bodyRu), input.targetType ?? null, input.targetId ?? null, input.dedupeKey ?? null],
    )).rows);
    return { notification: row, created: Boolean(row) };
  }

  async deliver(row: { id: string; user_id: string | null; role: string | null }, input: NotificationInput, options: {throwOnError?: boolean} = {}) {
    try {
      if (input.userId && input.targetType === 'order_offer') {
        const active = (await this.db.query(`SELECT 1 FROM order_offers f JOIN service_orders o ON o.id=f.order_id
          WHERE f.order_id=$1 AND f.cleaner_id=$2 AND f.status='offered' AND f.expires_at>NOW()
          AND o.status IN ('pending_assignment','waiting_cleaner') AND o.cleaner_id IS NULL
          AND ${approvedWorkStartSql('f.cleaner_id','o.scheduled_date','o.start_time')} LIMIT 1`,
          [input.targetId,input.userId])).rows.length;
        if (!active) return; // An offer can expire or be cancelled while delivery is queued.
      }
      if (row?.user_id) {
        await publishToUser(row.user_id, { type: 'notification', notification: row },options.throwOnError);
      } else if (row?.role) {
        const users = (await this.db.query<{ id: string }>(
          `SELECT id FROM app_users WHERE role=$1 AND status <> 'blocked'`,
          [row.role],
        )).rows;
        await publishToUsers(users.map(user => user.id), { type: 'notification', notification: row },options.throwOnError);
      }
      const isCleanerOrderOffer = Boolean(input.userId && input.targetType === 'order_offer');
      if (!isCleanerOrderOffer) {
        await sendLocalizedPush(this.db,this.fcm,input,{
          targetType: input.targetType ?? '',targetId: input.targetId ?? '',notificationId: row?.id ?? '',
        },{requireDelivery:options.throwOnError});
      }
      if (input.userId && input.targetType === 'order_offer') {
        const delay = await this.cleanerAlarmDelayMs();
        await this.queues?.cleanerAlarms?.add('cleaner-order-alarm', {
          cleanerId: input.userId,
          orderId: input.targetId,
          titleRu: input.titleRu,
          bodyRu: input.bodyRu,
          notificationId: row?.id ?? '',
        }, { delay, attempts: 3, removeOnComplete: true, jobId: `notification-${row.id}` });
      }
    } catch (error) {
      console.warn('[notifications] Delivery failed; notification remains stored', error instanceof Error ? error.name : 'unknown');
      if (options.throwOnError) throw error;
    }
  }

  async create(input: NotificationInput) {
    return this.db.atomic(async () => {
      const saved = await this.persist(input);
      if (saved.created && saved.notification) {
        await this.db.query(`INSERT INTO notification_deliveries(notification_id,payload) VALUES($1,$2::jsonb)
          ON CONFLICT(notification_id) DO NOTHING`, [saved.notification.id,JSON.stringify(input)]);
      }
      return saved.notification;
    });
  }

  async createAdminEvent(input: {
    event: string;
    titleRu: string;
    bodyRu: string;
    titleKk?: string;
    bodyKk?: string;
    targetType?: string;
    targetId?: string;
    dedupeKey?: string;
  }) {
    const settings = first<{ value: any }>((await this.db.query(
      `SELECT value FROM app_settings WHERE key='adminNotificationRules'`,
    )).rows)?.value ?? {};
    if (settings.enabled === false) return [];
    const events = Array.isArray(settings.events) ? settings.events.map(String) : [];
    if (events.length && !events.includes(input.event)) return [];
    const created = [];
    for (const role of ['admin', 'superadmin'] as const) {
      const row = await this.create({
        role,
        titleRu: input.titleRu,
        titleKk: input.titleKk,
        bodyRu: input.bodyRu,
        bodyKk: input.bodyKk,
        targetType: input.targetType,
        targetId: input.targetId,
        dedupeKey: input.dedupeKey ? `admin-event-${role}-${input.dedupeKey}` : undefined,
      });
      if (row) created.push(row);
    }
    return created;
  }
}

export class PricingService {
  calculatePackage(basePrice: number, pricePerM2: number, area: number, cleaningCount: number, months: number): number {
    return Math.round((basePrice + pricePerM2 * area) * cleaningCount * months);
  }

  calculateAddon(price: number, quantity: number): number {
    return Math.round(price * Math.max(quantity, 1));
  }

  splitBonus(total: number, requested: number, balance: number, maxPercent: number): { bonus: number; payable: number } {
    const allowed = Math.min(total * (maxPercent / 100), total, requested, balance);
    const bonus = Math.max(0, Math.round(allowed));
    return { bonus, payable: Math.max(0, total - bonus) };
  }
}

export class BonusService {
  constructor(private readonly db: Database) {}

  async accrue(userId: string, amount: number, reasonRu: string, reasonKk?: string, orderId?: string, paymentId?: string) {
    if (amount <= 0) return null;
    return this.db.transaction(async tx => {
      const user = first<{ bonus_balance: string }>((await tx.query(
        `UPDATE app_users SET bonus_balance=bonus_balance+$2, updated_at=NOW() WHERE id=$1 RETURNING bonus_balance`,
        [userId, amount],
      )).rows);
      return first((await tx.query(
        `INSERT INTO bonus_transactions (user_id, order_id, payment_id, type, amount, balance_after, reason_ru, reason_kk)
         VALUES ($1,$2,$3,'accrual',$4,$5,$6,$7) RETURNING *`,
        [userId, orderId ?? null, paymentId ?? null, amount, user?.bonus_balance ?? amount, reasonRu, reasonKk ?? null],
      )).rows);
    });
  }

  async spend(userId: string, amount: number, reasonRu: string, orderId?: string, paymentId?: string, transaction?: Queryable) {
    if (amount <= 0) return null;
    const work = async (tx: Queryable) => {
      const user = first<{ bonus_balance: string }>((await tx.query(
        `SELECT bonus_balance FROM app_users WHERE id=$1 FOR UPDATE`,
        [userId],
      )).rows);
      if (!user || Number(user.bonus_balance) < amount) {
        throw new ApiError(400, 'not_enough_bonuses', 'Недостаточно бонусов для оплаты.');
      }
      const updated = first<{ bonus_balance: string }>((await tx.query(
        `UPDATE app_users SET bonus_balance=bonus_balance-$2, updated_at=NOW() WHERE id=$1 RETURNING bonus_balance`,
        [userId, amount],
      )).rows);
      return first((await tx.query(
        `INSERT INTO bonus_transactions (user_id, order_id, payment_id, type, amount, balance_after, reason_ru)
         VALUES ($1,$2,$3,'spend',$4,$5,$6) RETURNING *`,
        [userId, orderId ?? null, paymentId ?? null, -Math.abs(amount), updated?.bonus_balance ?? 0, reasonRu],
      )).rows);
    };
    return transaction ? work(transaction) : this.db.transaction(work);
  }

  async refund(userId: string, amount: number, reasonRu: string, orderId?: string, paymentId?: string, transaction?: Queryable) {
    if (amount <= 0) return null;
    const work = async (tx: Queryable) => {
      const updated = first<{ bonus_balance: string }>((await tx.query(
        `UPDATE app_users SET bonus_balance=bonus_balance+$2, updated_at=NOW() WHERE id=$1 RETURNING bonus_balance`,
        [userId, amount],
      )).rows);
      return first((await tx.query(
        `INSERT INTO bonus_transactions (user_id, order_id, payment_id, type, amount, balance_after, reason_ru)
         VALUES ($1,$2,$3,'refund',$4,$5,$6) RETURNING *`,
        [userId, orderId ?? null, paymentId ?? null, amount, updated?.bonus_balance ?? amount, reasonRu],
      )).rows);
    };
    return transaction ? work(transaction) : this.db.transaction(work);
  }
}

export class PaymentService {
  constructor(private readonly db: Database, private readonly bonus: BonusService) {}

  async createPayment(input: {
    customerId: string;
    amount: number;
    provider: 'kaspi' | 'bcc' | 'manual';
    orderId?: string;
    customerPackageId?: string;
    applyReferralDiscount?: boolean;
    useBonus?: boolean;
    requestedBonus?: number;
    maxBonusPercent?: number;
    invoicePhone?: string;
    payload?: Record<string, unknown>;
  }) {
    const result = await this.db.transaction(async tx => {
      const user = first<{ bonus_balance: string }>((await tx.query(
        `SELECT bonus_balance FROM app_users WHERE id=$1 FOR UPDATE`,
        [input.customerId],
      )).rows);
      const referralPercent = input.applyReferralDiscount === false ? 0 : await referralDiscount(tx,input.customerId);
      const referralAmount = Math.round(input.amount * referralPercent / 100);
      input = {...input, amount: input.amount - referralAmount, payload: {...input.payload, referralDiscountPercent: referralPercent, referralDiscountAmount: referralAmount}};
      const pricing = new PricingService();
      const split = input.useBonus
        ? pricing.splitBonus(input.amount, input.requestedBonus ?? input.amount, Number(user?.bonus_balance ?? 0), input.maxBonusPercent ?? 50)
        : { bonus: 0, payable: input.amount };
      const payment = first<{ id: string }>((await tx.query(
        `INSERT INTO payments (customer_id, order_id, customer_package_id, provider, status, amount, bonus_amount, invoice_phone, payload, approval_source, approved_at, paid_at)
         VALUES ($1,$2,$3,$4,$5::payment_status,$6,$7,$8,$9,CASE WHEN $5::payment_status='paid' THEN 'bonus' END,CASE WHEN $5::payment_status='paid' THEN NOW() END,CASE WHEN $5::payment_status='paid' THEN NOW() END) RETURNING *`,
        [
          input.customerId,
          input.orderId ?? null,
          input.customerPackageId ?? null,
          split.payable === 0 ? 'bonus' : input.provider,
          split.payable === 0 ? 'paid' : 'pending',
          split.payable,
          split.bonus,
          input.invoicePhone ?? null,
          input.payload ?? {},
        ],
      )).rows);
      if (split.bonus > 0) {
        await this.bonus.spend(input.customerId, split.bonus, 'Оплата бонусами', input.orderId, payment?.id, tx);
        if (input.orderId) {
          await tx.query(`UPDATE service_orders SET bonus_spent=bonus_spent+$2, payable_amount=$3 WHERE id=$1`, [input.orderId, split.bonus, split.payable]);
        }
      }
      return { payment, bonusSpent: split.bonus, payableAmount: split.payable };
    });
    await scheduleCheckoutFollowup(this.db, result.payment);
    return result;
  }

  async markPaid(paymentId: string, approvedBy?: string) {
    return first<{ id: string; customer_id: string; customer_package_id: string | null; order_id: string | null }>((await this.db.query(
      `UPDATE payments
       SET status='paid',
           paid_at=COALESCE(paid_at, NOW()),
           approval_source=CASE WHEN status='paid' THEN approval_source ELSE 'manual' END,
           approved_by=CASE WHEN status='paid' THEN approved_by ELSE $2::uuid END,
           approved_at=CASE WHEN status='paid' THEN approved_at ELSE NOW() END,
           updated_at=NOW()
       WHERE id=$1 AND status NOT IN ('cancelled','refunded')
       RETURNING *`,
      [paymentId, approvedBy ?? null],
    )).rows);
  }

  async refundOrderPayments(orderId: string, reasonRu: string, transaction?: Queryable) {
    const work = async (tx: Queryable) => {
    const owner = (await tx.query<{customer_id: string}>(
      'SELECT customer_id FROM service_orders WHERE id=$1', [orderId])).rows[0];
    if (!owner) return [];
    await tx.query('SELECT id FROM app_users WHERE id=$1 FOR UPDATE', [owner.customer_id]);
    const order = (await tx.query<{bonus_spent: string}>(
      'SELECT bonus_spent FROM service_orders WHERE id=$1 FOR UPDATE', [orderId])).rows[0];
    const allPayments = (await tx.query<{
      id: string; customer_id: string; status: string; amount: string; bonus_amount: string; provider: string;
    }>('SELECT id,customer_id,status,amount,bonus_amount,provider FROM payments WHERE order_id=$1 ORDER BY id FOR UPDATE', [orderId])).rows;
    const ledger = (await tx.query<{type: string; amount: string; payment_id: string | null}>(
      "SELECT type,amount,payment_id FROM bonus_transactions WHERE order_id=$1 AND user_id=$2 AND type IN ('spend','refund')",
      [orderId, owner.customer_id])).rows;
    const spends = ledger.filter(row => row.type === 'spend');
    const refunded = ledger.filter(row => row.type === 'refund');
    // The ledger is authoritative. Older orders without debit rows retain the
    // existing field-based fallback, but previous refunds are always deducted.
    const debit = spends.length ? spends.reduce((sum, row) => sum - Number(row.amount), 0)
      : Math.max(Number(order.bonus_spent), allPayments.reduce((sum, row) => sum + Number(row.bonus_amount), 0));
    let remaining = Math.max(0, debit - refunded.reduce((sum, row) => sum + Number(row.amount), 0));
    for (const payment of allPayments) {
      const prior = refunded.filter(row => row.payment_id === payment.id).reduce((sum, row) => sum + Number(row.amount), 0);
      const amount = Math.min(remaining, Math.max(0, Number(payment.bonus_amount) - prior));
      if (amount > 0) {
        await this.bonus.refund(owner.customer_id, amount, reasonRu, orderId, payment.id, tx);
        remaining -= amount;
      }
    }
    if (remaining > 0) await this.bonus.refund(owner.customer_id, remaining, reasonRu, orderId, undefined, tx);
    const payments = allPayments.filter(payment => ['pending','invoice_requested','paid'].includes(payment.status));
    for (const payment of payments) {
      const nextStatus = payment.status === 'paid' && Number(payment.amount) > 0 ? 'refunded' : 'cancelled';
      await tx.query(
        `UPDATE payments SET status=$2, payload=payload || $3::jsonb, updated_at=NOW() WHERE id=$1`,
        [payment.id, nextStatus, { refundReason: reasonRu, refundRequestedAt: new Date().toISOString() }],
      );
    }
    return payments;
    };
    return transaction ? work(transaction) : this.db.transaction(work);
  }
}

export class SchedulingService {
  constructor(private readonly db: Database) {}

  async assignOrder(orderId: string, cleanerId: string, actorId: string, comment?: string) {
    return this.db.transaction(async tx => {
      // Match acceptOffer's lock order so assignments and offers share one schedule lock.
      const cleaner = (await tx.query("SELECT id FROM app_users WHERE id=$1 AND role='cleaner' FOR UPDATE", [cleanerId])).rows[0];
      if (!cleaner) throw new ApiError(400, 'cleaner_required', 'Выберите уборщицу для назначения заказа.');
      const order = first<any>((await tx.query('SELECT * FROM service_orders WHERE id=$1 FOR UPDATE', [orderId])).rows);
      if (!order) throw new ApiError(404, 'not_found', 'Заказ не найден.');
      if (Number(order.payable_amount) > 0) throw new ApiError(409, 'payment_required', 'Сначала оплатите допуслуги.');
      if (!['pending_assignment','waiting_cleaner','assigned'].includes(order.status)) throw new ApiError(409, 'invalid_transition', 'Этот заказ нельзя назначить повторно.');
      if (order.status === 'assigned' && order.cleaner_id === cleanerId) return {order, changed: false};
      const overlap = (await tx.query(`SELECT id FROM service_orders WHERE cleaner_id=$1 AND scheduled_date=$2
        AND status NOT IN ('cancelled','completed') AND start_time<$4::time AND end_time>$3::time AND id<>$5 LIMIT 1`,
        [cleanerId,order.scheduled_date,order.start_time,order.end_time,orderId])).rows;
      if (overlap.length) throw new ApiError(400, 'cleaner_unavailable', 'Уборщица занята на это время. Выберите другую.');
      const updated = first((await tx.query("UPDATE service_orders SET cleaner_id=$2,status='assigned',updated_at=NOW() WHERE id=$1 RETURNING *", [orderId,cleanerId])).rows);
      await tx.query("UPDATE order_offers SET status='expired' WHERE order_id=$1 AND status='offered'", [orderId]);
      await tx.query("INSERT INTO order_status_history(order_id,old_status,new_status,actor_id,comment) VALUES($1,$2,'assigned',$3,$4)", [orderId,order.status,actorId,comment ?? null]);
      return {order:updated, changed:true};
    });
  }

  async cleanerAvailable(cleanerId: string, date: string, startTime: string, endTime: string, excludeOrderId?: string): Promise<boolean> {
    const overlap = first<{ id: string }>((await this.db.query(
      `SELECT id FROM service_orders
       WHERE cleaner_id=$1 AND scheduled_date=$2 AND status NOT IN ('cancelled','completed')
       AND start_time < $4::time AND end_time > $3::time
       AND ($5::uuid IS NULL OR id<>$5::uuid)
       LIMIT 1`,
      [cleanerId, date, startTime, endTime, excludeOrderId ?? null],
    )).rows);
    return !overlap;
  }

  async availableCleaners(date: string, startTime: string, endTime: string, zoneId?: string, queryable: Queryable = this.db, requireWorkingHours=false) {
    const zoneJoin = zoneId ? `JOIN cleaner_zones cz ON cz.cleaner_id=u.id AND cz.zone_id=$4` : '';
    const params = zoneId ? [date, startTime, endTime, zoneId] : [date, startTime, endTime];
    return (await queryable.query(
      `SELECT u.id, u.full_name, u.phone
       FROM app_users u
       JOIN cleaner_profiles cp ON cp.user_id=u.id
       ${zoneJoin}
       WHERE u.role='cleaner' AND u.status='approved' AND cp.verification_status='approved'
       ${requireWorkingHours ? 'AND '+approvedWorkStartSql('u.id','$1','$2') : ''}
       AND NOT EXISTS (
         SELECT 1 FROM service_orders o
         WHERE o.cleaner_id=u.id AND o.scheduled_date=$1
         AND o.status NOT IN ('cancelled','completed')
         AND o.start_time < $3::time AND o.end_time > $2::time
       )
       ORDER BY u.created_at ASC, u.id ASC`,
      params,
    )).rows;
  }

  async availableSlotCounts(date: string, slots: Array<{ startTime: string; endTime: string }>, zoneId?: string) {
    if (!slots.length) return [];
    // Count all requested intervals in one round trip. Do not transfer every
    // cleaner's name/phone five times just to calculate array lengths.
    const rows = (await this.db.query<{ ordinal: string; count: number }>(`
      SELECT s.ordinal, (
        SELECT COUNT(*)::int FROM app_users u
        JOIN cleaner_profiles cp ON cp.user_id=u.id
        ${zoneId ? 'JOIN cleaner_zones cz ON cz.cleaner_id=u.id AND cz.zone_id=$4' : ''}
        WHERE u.role='cleaner' AND u.status='approved' AND cp.verification_status='approved'
          AND NOT EXISTS (
            SELECT 1 FROM service_orders o WHERE o.cleaner_id=u.id AND o.scheduled_date=$1
              AND o.status NOT IN ('cancelled','completed')
              AND o.start_time<s.ends AND o.end_time>s.starts
          )
      ) AS count
      FROM unnest($2::time[], $3::time[]) WITH ORDINALITY AS s(starts,ends,ordinal)
      ORDER BY s.ordinal`,
    zoneId ? [date,slots.map(s=>s.startTime),slots.map(s=>s.endTime),zoneId]
      : [date,slots.map(s=>s.startTime),slots.map(s=>s.endTime)])).rows;
    return rows.map(row=>({...slots[Number(row.ordinal)-1],cleanersCount:row.count}));
  }

  async offerNextCleaner(orderId: string, excludeCleanerIds: string[] = [], ttlMinutes = 2) {
    return this.db.transaction(async client => {
      const order = first<any>((await client.query(
        `SELECT * FROM service_orders WHERE id=$1 FOR UPDATE`,
        [orderId],
      )).rows);
      if (!order || Number(order.payable_amount ?? 0) > 0 || order.cleaner_id || !['pending_assignment','waiting_cleaner'].includes(order.status)) return null;
      if (!order?.scheduled_date || !order.start_time || !order.end_time) {
        throw new ApiError(400, 'invalid_order_time', 'У заказа не указаны дата и время.');
      }
      const active = first((await client.query(
        "SELECT * FROM order_offers WHERE order_id=$1 AND status='offered' AND expires_at>NOW()",
        [orderId],
      )).rows);
      if (active) return active;
      const cleaners = await this.availableCleaners(order.scheduled_date, order.start_time, order.end_time, undefined, client,true);
      const history = (await client.query<{cleaner_id: string}>(
        'SELECT cleaner_id FROM order_offers WHERE order_id=$1 ORDER BY created_at ASC, id ASC',
        [orderId],
      )).rows;
      // Prefer cleaners who have not had a turn. Once everyone has, offer to
      // the least recently contacted available cleaner, including a sole cleaner.
      const next = cleaners.find((cleaner: any) => !excludeCleanerIds.includes(cleaner.id))
        ?? history.map(row => cleaners.find((cleaner: any) => cleaner.id === row.cleaner_id)).find(Boolean)
        ?? cleaners[0];
      if (!next) {
        await client.query(`UPDATE service_orders SET status='waiting_cleaner', updated_at=NOW() WHERE id=$1`, [orderId]);
        return null;
      }
      return first((await client.query(
        `INSERT INTO order_offers (order_id, cleaner_id, status, expires_at)
         VALUES ($1,$2,'offered',NOW() + ($3::int * INTERVAL '1 minute'))
         ON CONFLICT (order_id, cleaner_id) DO UPDATE SET status='offered', expires_at=NOW() + ($3::int * INTERVAL '1 minute'), created_at=NOW()
         RETURNING *`,
        [orderId, next.id, Math.max(1, Math.round(ttlMinutes))],
      )).rows);
    });
  }

  async cleanerOffers(cleanerId: string) {
    return (await this.db.query(
      `SELECT oo.*, o.numeric_id AS order_number, o.scheduled_date, o.start_time, o.end_time,
              o.estimated_duration_minutes, COALESCE(ca.verified_area,ca.area,o.area) AS area, ca.city, ca.street, ca.house, ca.apartment,
              pkg.name_ru AS package_name_ru,
              u.full_name AS customer_name, u.phone AS customer_phone
       FROM order_offers oo
       JOIN service_orders o ON o.id=oo.order_id
       JOIN app_users u ON u.id=o.customer_id
       LEFT JOIN customer_addresses ca ON ca.id=o.address_id
       LEFT JOIN catalog_packages pkg ON pkg.id=o.package_id
       WHERE ${approvedWorkStartSql('oo.cleaner_id','o.scheduled_date','o.start_time')} AND oo.cleaner_id=$1 AND oo.status='offered' AND oo.expires_at > NOW() AND o.cleaner_id IS NULL AND o.status IN ('pending_assignment','waiting_cleaner') AND o.payable_amount <= 0
       ORDER BY oo.created_at ASC`,
      [cleanerId],
    )).rows;
  }

  async getOffer(offerId: string, cleanerId?: string) {
    return first((await this.db.query(
      `SELECT oo.*, o.customer_id, o.scheduled_date, o.start_time, o.end_time
       FROM order_offers oo
       JOIN service_orders o ON o.id=oo.order_id
       WHERE oo.id=$1 AND ($2::uuid IS NULL OR oo.cleaner_id=$2)`,
      [offerId, cleanerId ?? null],
    )).rows);
  }

  async acceptOfferById(offerId: string, cleanerId: string) {
    const offer = await this.getOffer(offerId, cleanerId) as any;
    if (!offer || offer.status !== 'offered' || new Date(offer.expires_at).getTime() <= Date.now()) {
      throw new ApiError(404, 'offer_not_found', 'Предложение заказа уже недоступно.');
    }
    return this.acceptOffer(offer.order_id, cleanerId);
  }

  async declineOfferById(offerId: string, cleanerId: string) {
    const offer = await this.getOffer(offerId, cleanerId) as any;
    if (!offer) throw new ApiError(404, 'offer_not_found', 'Предложение заказа не найдено.');
    return this.declineOffer(offer.order_id, cleanerId);
  }

  async acceptOffer(orderId: string, cleanerId: string) {
    return this.db.transaction(async client=>{
      await client.query('SELECT id FROM app_users WHERE id=$1 FOR UPDATE',[cleanerId]);
      const order=first<any>((await client.query('SELECT * FROM service_orders WHERE id=$1 FOR UPDATE',[orderId])).rows);
      if(!order)throw new ApiError(404,'not_found','Заказ не найден.');
      if(Number(order.payable_amount ?? 0) > 0 || order.cleaner_id || !['pending_assignment','waiting_cleaner'].includes(order.status))throw new ApiError(409,'order_unavailable','Заказ уже недоступен для принятия.');
      const working=(await client.query(`SELECT 1 WHERE ${approvedWorkStartSql('$1','$2','$3')}`,[cleanerId,order.scheduled_date,order.start_time])).rows[0];
      if(!working)throw new ApiError(409,'outside_working_hours','Начало заказа не входит в утверждённый график работы.');
      const overlap=(await client.query(`SELECT id FROM service_orders WHERE cleaner_id=$1 AND scheduled_date=$2
        AND status NOT IN ('cancelled','completed') AND start_time<$4::time AND end_time>$3::time AND id<>$5 LIMIT 1`,[cleanerId,order.scheduled_date,order.start_time,order.end_time,orderId])).rows;
      if(overlap.length)throw new ApiError(400,'cleaner_unavailable','Это время уже занято другим заказом.');
      const current=first((await client.query(`SELECT id FROM order_offers WHERE order_id=$1 AND cleaner_id=$2 AND status='offered' AND expires_at>NOW() FOR UPDATE`,[orderId,cleanerId])).rows);
      if(!current)throw new ApiError(404,'offer_not_found','Предложение заказа уже недоступно.');
      await client.query("UPDATE order_offers SET status='expired' WHERE order_id=$1 AND cleaner_id<>$2",[orderId,cleanerId]);
      await client.query("UPDATE order_offers SET status='accepted' WHERE order_id=$1 AND cleaner_id=$2",[orderId,cleanerId]);
      await client.query(`INSERT INTO order_status_history(order_id,old_status,new_status,actor_id) VALUES($1,$2,'assigned',$3)`, [orderId,order.status,cleanerId]);
      return first((await client.query("UPDATE service_orders SET cleaner_id=$2,status='assigned',updated_at=NOW() WHERE id=$1 RETURNING *",[orderId,cleanerId])).rows);
    });
  }

  async declineOffer(orderId: string, cleanerId: string) {
    await this.db.transaction(async client => {
      const order=first<any>((await client.query('SELECT * FROM service_orders WHERE id=$1 FOR UPDATE',[orderId])).rows);
      if (!order || order.cleaner_id || !['pending_assignment','waiting_cleaner'].includes(order.status)) throw new ApiError(409,'order_unavailable','Заказ уже недоступен.');
      const declined=(await client.query(`UPDATE order_offers SET status='declined' WHERE order_id=$1 AND cleaner_id=$2 AND status='offered' AND expires_at>NOW() RETURNING id`,[orderId,cleanerId])).rows;
      if (!declined.length) throw new ApiError(409,'offer_unavailable','Предложение уже недоступно.');
    });
    const declined = (await this.db.query<{ cleaner_id: string }>(
      `SELECT cleaner_id FROM order_offers WHERE order_id=$1 AND status IN ('declined','expired')`,
      [orderId],
    )).rows.map((row) => row.cleaner_id);
    return this.offerNextCleaner(orderId, declined);
  }
}

export function normalizePhone(phone: string): string {
  const digits = phone.replace(/\D/g, '');
  if (digits.length === 10) return `+7${digits}`;
  if (digits.length === 11 && digits.startsWith('8')) return `+7${digits.slice(1)}`;
  if (digits.length === 11 && digits.startsWith('7')) return `+${digits}`;
  return phone.startsWith('+') ? phone : `+${digits}`;
}

export function hashToken(token: string): string {
  return crypto.createHash('sha256').update(token).digest('hex');
}
