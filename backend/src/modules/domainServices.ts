import { Queryable } from '../domain/repositories/UnitOfWork';
import { referralDiscount } from './referrals';
import crypto from 'crypto';
import bcrypt from 'bcryptjs';
import { Database } from '../infrastructure/db/Database';
import { ApiError } from '../common/api';
import { first } from '../common/sql';
import { AuthUser, signAccessToken, signRefreshToken } from '../common/auth';
import { env } from '../common/env';
import { WapiOtpService, FcmService } from './integrations';
import { publishToUser } from '../realtime/sse';

export class AuthService {
  constructor(private readonly db: Database, private readonly wapi: WapiOtpService) {}

  async requestOtp(phone: string) {
    const normalized = normalizePhone(phone);
    const code = String(crypto.randomInt(100000, 1000000));
    const codeHash = await bcrypt.hash(code, 8);
    await this.db.query(
      `INSERT INTO auth_otp_codes (phone, code_hash, expires_at) VALUES ($1, $2, NOW() + INTERVAL '5 minutes')`,
      [normalized, codeHash],
    );
    const until = Date.parse(env.otpFailureFallbackUntil);
    const fallbackActive = Number.isFinite(until) && until > Date.now();
    let mayShowCode = false;
    if (env.otpShowCode || fallbackActive) {
      const user = first<{role: string; status: string}>((await this.db.query(
        'SELECT role,status FROM app_users WHERE phone=$1', [normalized],
      )).rows);
      mayShowCode = !user || (['customer','cleaner'].includes(user.role)
        && !['blocked','rejected'].includes(user.status));
    }
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
       WHERE phone=$1 AND consumed_at IS NULL AND expires_at > NOW()
       ORDER BY created_at DESC LIMIT 1`,
      [normalized],
    )).rows);
    if (!otp || !(await bcrypt.compare(code, otp.code_hash))) {
      throw new ApiError(400, 'invalid_otp', 'Неверный или истекший код.');
    }
    await this.db.query(`UPDATE auth_otp_codes SET consumed_at=NOW() WHERE id=$1`, [otp.id]);
    const existingUser = first<{ id: string }>((await this.db.query(
      `SELECT id FROM app_users WHERE phone=$1`,
      [normalized],
    )).rows);
    const user = first<AuthUser>((await this.db.query(
      `INSERT INTO app_users (phone, role, is_phone_verified)
       VALUES ($1, $2, TRUE)
       ON CONFLICT (phone) DO UPDATE SET is_phone_verified=TRUE, last_login_at=NOW()
       RETURNING id, role, phone`,
      [normalized, role],
    )).rows);
    if (!user) throw new ApiError(500, 'auth_failed', 'Не удалось войти. Попробуйте позже.');
    const refreshToken = signRefreshToken(user);
    await this.db.query(
      `INSERT INTO refresh_sessions (user_id, token_hash, expires_at)
       VALUES ($1,$2,NOW() + ($3 || ' seconds')::interval)`,
      [user.id, hashToken(refreshToken), env.jwtRefreshTtlSeconds],
    );
    return { user, accessToken: signAccessToken(user), refreshToken, isNew: !existingUser };
  }

  async loginWithPassword(phone: string, password: string) {
    const normalized = normalizePhone(phone);
    const user = first<AuthUser & { password_hash: string | null; status: string }>((await this.db.query(
      `SELECT id, role, phone, password_hash, status
       FROM app_users
       WHERE phone=$1 AND role IN ('admin','superadmin','cleaner')`,
      [normalized],
    )).rows);
    if (!user?.password_hash || !(await bcrypt.compare(password, user.password_hash))) {
      throw new ApiError(401, 'invalid_credentials', 'Неверный телефон или пароль.');
    }
    if (user.status === 'blocked') throw new ApiError(403, 'blocked', 'Аккаунт заблокирован.');
    const authUser: AuthUser = { id: user.id, role: user.role, phone: user.phone };
    const refreshToken = signRefreshToken(authUser);
    await this.db.query(
      `INSERT INTO refresh_sessions (user_id, token_hash, expires_at)
       VALUES ($1,$2,NOW() + ($3 || ' seconds')::interval)`,
      [user.id, hashToken(refreshToken), env.jwtRefreshTtlSeconds],
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
      [input.userId ?? null, input.role ?? null, input.titleRu, input.titleKk ?? null, input.bodyRu, input.bodyKk ?? null, input.targetType ?? null, input.targetId ?? null, input.dedupeKey ?? null],
    )).rows);
    return { notification: row, created: Boolean(row) };
  }

  async deliver(row: { id: string; user_id: string | null; role: string | null }, input: NotificationInput) {
    try {
      if (row?.user_id) {
        await publishToUser(row.user_id, { type: 'notification', notification: row });
      } else if (row?.role) {
        const users = (await this.db.query<{ id: string }>(
          `SELECT id FROM app_users WHERE role=$1 AND status <> 'blocked'`,
          [row.role],
        )).rows;
        for (const user of users) await publishToUser(user.id, { type: 'notification', notification: row });
      }
      const tokens = (await this.db.query<{ token: string }>(
        input.userId
          ? `SELECT token FROM device_tokens WHERE user_id=$1 AND enabled=TRUE`
          : `SELECT dt.token FROM device_tokens dt JOIN app_users u ON u.id=dt.user_id WHERE u.role=$1 AND dt.enabled=TRUE`,
        input.userId ? [input.userId] : [input.role],
      )).rows.map((r: { token: string }) => r.token);
      const isCleanerOrderOffer = Boolean(input.userId && input.targetType === 'order_offer');
      if (!isCleanerOrderOffer) {
        await this.fcm.send(tokens, input.titleRu, input.bodyRu, {
          targetType: input.targetType ?? '',
          targetId: input.targetId ?? '',
          notificationId: row?.id ?? '',
        });
      }
      if (input.userId && input.targetType === 'order_offer') {
        const delay = await this.cleanerAlarmDelayMs();
        await this.queues?.cleanerAlarms?.add('cleaner-order-alarm', {
          cleanerId: input.userId,
          orderId: input.targetId,
          titleRu: input.titleRu,
          bodyRu: input.bodyRu,
          notificationId: row?.id ?? '',
        }, { delay, attempts: 3, removeOnComplete: true });
      }
    } catch (error) {
      console.warn('[notifications] Delivery failed; notification remains stored', error instanceof Error ? error.name : 'unknown');
    }
  }

  async create(input: NotificationInput) {
    const saved = await this.persist(input);
    if (saved.created && saved.notification) await this.deliver(saved.notification, input);
    return saved.notification;
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
    return this.db.transaction(async () => {
      const user = first<{ bonus_balance: string }>((await this.db.query(
        `UPDATE app_users SET bonus_balance=bonus_balance+$2, updated_at=NOW() WHERE id=$1 RETURNING bonus_balance`,
        [userId, amount],
      )).rows);
      return first((await this.db.query(
        `INSERT INTO bonus_transactions (user_id, order_id, payment_id, type, amount, balance_after, reason_ru, reason_kk)
         VALUES ($1,$2,$3,'accrual',$4,$5,$6,$7) RETURNING *`,
        [userId, orderId ?? null, paymentId ?? null, amount, user?.bonus_balance ?? amount, reasonRu, reasonKk ?? null],
      )).rows);
    });
  }

  async spend(userId: string, amount: number, reasonRu: string, orderId?: string, paymentId?: string) {
    if (amount <= 0) return null;
    return this.db.transaction(async () => {
      const user = first<{ bonus_balance: string }>((await this.db.query(
        `SELECT bonus_balance FROM app_users WHERE id=$1 FOR UPDATE`,
        [userId],
      )).rows);
      if (!user || Number(user.bonus_balance) < amount) {
        throw new ApiError(400, 'not_enough_bonuses', 'Недостаточно бонусов для оплаты.');
      }
      const updated = first<{ bonus_balance: string }>((await this.db.query(
        `UPDATE app_users SET bonus_balance=bonus_balance-$2, updated_at=NOW() WHERE id=$1 RETURNING bonus_balance`,
        [userId, amount],
      )).rows);
      return first((await this.db.query(
        `INSERT INTO bonus_transactions (user_id, order_id, payment_id, type, amount, balance_after, reason_ru)
         VALUES ($1,$2,$3,'spend',$4,$5,$6) RETURNING *`,
        [userId, orderId ?? null, paymentId ?? null, -Math.abs(amount), updated?.bonus_balance ?? 0, reasonRu],
      )).rows);
    });
  }

  async refund(userId: string, amount: number, reasonRu: string, orderId?: string, paymentId?: string) {
    if (amount <= 0) return null;
    return this.db.transaction(async () => {
      const updated = first<{ bonus_balance: string }>((await this.db.query(
        `UPDATE app_users SET bonus_balance=bonus_balance+$2, updated_at=NOW() WHERE id=$1 RETURNING bonus_balance`,
        [userId, amount],
      )).rows);
      return first((await this.db.query(
        `INSERT INTO bonus_transactions (user_id, order_id, payment_id, type, amount, balance_after, reason_ru)
         VALUES ($1,$2,$3,'refund',$4,$5,$6) RETURNING *`,
        [userId, orderId ?? null, paymentId ?? null, amount, updated?.bonus_balance ?? amount, reasonRu],
      )).rows);
    });
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
    const user = first<{ bonus_balance: string }>((await this.db.query(
      `SELECT bonus_balance FROM app_users WHERE id=$1`,
      [input.customerId],
    )).rows);
    const referralPercent = input.applyReferralDiscount === false ? 0 : await referralDiscount(this.db,input.customerId);
    const referralAmount = Math.round(input.amount * referralPercent / 100);
    input = {...input, amount: input.amount - referralAmount, payload: {...input.payload, referralDiscountPercent: referralPercent, referralDiscountAmount: referralAmount}};
    const pricing = new PricingService();
    const split = input.useBonus
      ? pricing.splitBonus(input.amount, input.requestedBonus ?? input.amount, Number(user?.bonus_balance ?? 0), input.maxBonusPercent ?? 50)
      : { bonus: 0, payable: input.amount };
    const payment = first<{ id: string }>((await this.db.query(
      `INSERT INTO payments (customer_id, order_id, customer_package_id, provider, status, amount, bonus_amount, invoice_phone, payload)
       VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9) RETURNING *`,
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
      await this.bonus.spend(input.customerId, split.bonus, 'Оплата бонусами', input.orderId, payment?.id);
      if (input.orderId) {
        await this.db.query(`UPDATE service_orders SET bonus_spent=bonus_spent+$2, payable_amount=$3 WHERE id=$1`, [input.orderId, split.bonus, split.payable]);
      }
    }
    return { payment, bonusSpent: split.bonus, payableAmount: split.payable };
  }

  async markPaid(paymentId: string) {
    return first<{ id: string; customer_id: string; customer_package_id: string | null; order_id: string | null }>((await this.db.query(
      `UPDATE payments
       SET status='paid',
           paid_at=COALESCE(paid_at, NOW()),
           updated_at=NOW()
       WHERE id=$1 AND status NOT IN ('cancelled','refunded')
       RETURNING *`,
      [paymentId],
    )).rows);
  }

  async refundOrderPayments(orderId: string, reasonRu: string) {
    const payments = (await this.db.query<{
      id: string;
      customer_id: string;
      status: string;
      amount: string;
      bonus_amount: string;
      provider: string;
    }>(
      `SELECT id, customer_id, status, amount, bonus_amount, provider
       FROM payments
       WHERE order_id=$1 AND status IN ('pending','invoice_requested','paid')`,
      [orderId],
    )).rows;
    for (const payment of payments) {
      if (Number(payment.bonus_amount) > 0) {
        await this.bonus.refund(payment.customer_id, Number(payment.bonus_amount), reasonRu, orderId, payment.id);
      }
      const nextStatus = payment.status === 'paid' && Number(payment.amount) > 0 ? 'refunded' : 'cancelled';
      await this.db.query(
        `UPDATE payments
         SET status=$2, payload=payload || $3::jsonb, updated_at=NOW()
         WHERE id=$1`,
        [payment.id, nextStatus, { refundReason: reasonRu, refundRequestedAt: new Date().toISOString() }],
      );
    }
    return payments;
  }
}

export class SchedulingService {
  constructor(private readonly db: Database) {}

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

  async availableCleaners(date: string, startTime: string, endTime: string, zoneId?: string) {
    const zoneJoin = zoneId ? `JOIN cleaner_zones cz ON cz.cleaner_id=u.id AND cz.zone_id=$4` : '';
    const params = zoneId ? [date, startTime, endTime, zoneId] : [date, startTime, endTime];
    return (await this.db.query(
      `SELECT u.id, u.full_name, u.phone
       FROM app_users u
       JOIN cleaner_profiles cp ON cp.user_id=u.id
       ${zoneJoin}
       WHERE u.role='cleaner' AND u.status='approved' AND cp.verification_status='approved'
       AND NOT EXISTS (
         SELECT 1 FROM service_orders o
         WHERE o.cleaner_id=u.id AND o.scheduled_date=$1
         AND o.status NOT IN ('cancelled','completed')
         AND o.start_time < $3::time AND o.end_time > $2::time
       )
       ORDER BY u.created_at ASC`,
      params,
    )).rows;
  }

  async offerNextCleaner(orderId: string, excludeCleanerIds: string[] = [], ttlMinutes = 15) {
    const order = first<{ id: string; scheduled_date: string; start_time: string; end_time: string; address_id: string }>((await this.db.query(
      `SELECT id, scheduled_date, start_time, end_time, address_id FROM service_orders WHERE id=$1`,
      [orderId],
    )).rows);
    if (!order?.scheduled_date || !order.start_time || !order.end_time) {
      throw new ApiError(400, 'invalid_order_time', 'У заказа не указаны дата и время.');
    }
    const cleaners = await this.availableCleaners(order.scheduled_date, order.start_time, order.end_time);
    const next = cleaners.find((cleaner: any) => !excludeCleanerIds.includes(cleaner.id));
    if (!next) {
      await this.db.query(`UPDATE service_orders SET status='waiting_cleaner', updated_at=NOW() WHERE id=$1`, [orderId]);
      return null;
    }
    return first((await this.db.query(
      `INSERT INTO order_offers (order_id, cleaner_id, status, expires_at)
       VALUES ($1,$2,'offered',NOW() + ($3::int * INTERVAL '1 minute'))
       ON CONFLICT (order_id, cleaner_id) DO UPDATE SET status='offered', expires_at=NOW() + ($3::int * INTERVAL '1 minute'), created_at=NOW()
       RETURNING *`,
      [orderId, next.id, Math.max(1, Math.round(ttlMinutes))],
    )).rows);
  }

  async cleanerOffers(cleanerId: string) {
    return (await this.db.query(
      `SELECT oo.*, o.numeric_id AS order_number, o.scheduled_date, o.start_time, o.end_time,
              o.estimated_duration_minutes, o.area, ca.city, ca.street, ca.house, ca.apartment,
              u.full_name AS customer_name, u.phone AS customer_phone
       FROM order_offers oo
       JOIN service_orders o ON o.id=oo.order_id
       JOIN app_users u ON u.id=o.customer_id
       LEFT JOIN customer_addresses ca ON ca.id=o.address_id
       WHERE oo.cleaner_id=$1 AND oo.status='offered' AND oo.expires_at > NOW()
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
    const order = first<{ scheduled_date: string; start_time: string; end_time: string }>((await this.db.query(
      `SELECT scheduled_date, start_time, end_time FROM service_orders WHERE id=$1`,
      [orderId],
    )).rows);
    if (!order) throw new ApiError(404, 'not_found', 'Заказ не найден.');
    if (!(await this.cleanerAvailable(cleanerId, order.scheduled_date, order.start_time, order.end_time))) {
      throw new ApiError(400, 'cleaner_unavailable', 'Это время уже занято другим заказом.');
    }
    return this.db.transaction(async () => {
      const current = first<{ id: string }>((await this.db.query(
        `SELECT id FROM order_offers
         WHERE order_id=$1 AND cleaner_id=$2 AND status='offered' AND expires_at > NOW()`,
        [orderId, cleanerId],
      )).rows);
      if (!current) throw new ApiError(404, 'offer_not_found', 'Предложение заказа уже недоступно.');
      await this.db.query(`UPDATE order_offers SET status='expired' WHERE order_id=$1 AND cleaner_id<>$2`, [orderId, cleanerId]);
      await this.db.query(`UPDATE order_offers SET status='accepted' WHERE order_id=$1 AND cleaner_id=$2`, [orderId, cleanerId]);
      return first((await this.db.query(
        `UPDATE service_orders SET cleaner_id=$2, status='assigned', updated_at=NOW() WHERE id=$1 RETURNING *`,
        [orderId, cleanerId],
      )).rows);
    });
  }

  async declineOffer(orderId: string, cleanerId: string) {
    await this.db.query(`UPDATE order_offers SET status='declined' WHERE order_id=$1 AND cleaner_id=$2`, [orderId, cleanerId]);
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
