import { transitionOrder, releaseCleanerAssignment } from '../../modules/orderLifecycle';
import {confirmArea} from '../../modules/areaVerification';
import { verifyCleaner } from '../../modules/cleanerVerification';
import { qualifyReferral, referralDiscount } from '../../modules/referrals';
import { packageQuote } from '../../modules/packageQuote';
import { mobileRouter } from './mobile';
import { Router } from 'express';
import fs from 'fs/promises';
import multer from 'multer';
import path from 'path';
import { ok, asyncHandler, ApiError } from '../../common/api';
import { auth, signAccessToken, signRefreshToken, verifyRefreshToken } from '../../common/auth';
import { env, validateEnvConfig } from '../../common/env';
import { pageParams, first } from '../../common/sql';
import { Database } from '../../infrastructure/db/Database';
import { AuthService, BonusService, hashToken, normalizePhone, NotificationService, PaymentService, PricingService, SchedulingService } from '../../modules/domainServices';
import { defaultTranslations } from '../../modules/defaultTranslations';
import { AddressSearchService, normalizeText, PaymentGatewayService, StorageService, toLatin, WapiOtpService } from '../../modules/integrations';
import { createHash, randomUUID } from 'crypto';

export function buildV1Router(deps: {
  db: Database;
  authService: AuthService;
  notifications: NotificationService;
  bonuses: BonusService;
  payments: PaymentService;
  pricing: PricingService;
  scheduling: SchedulingService;
  storage: StorageService;
  paymentGateway: PaymentGatewayService;
  addressSearch: AddressSearchService;
  wapi: WapiOtpService;
}) {
  const router = Router();
  router.use(mobileRouter(deps.db));
  const upload = multer({ storage: multer.memoryStorage(), limits: { fileSize: 50 * 1024 * 1024 } });

  const cleanText = (value: unknown) => {
    const text = String(value ?? '').trim();
    return text.length > 0 ? text : null;
  };

  const cleanNumber = (value: unknown) => {
    const text = String(value ?? '').replace(',', '.').trim();
    if (!text) return null;
    const parsed = Number(text);
    if (!Number.isFinite(parsed)) {
      throw new ApiError(400, 'invalid_number', 'Проверьте площадь и координаты.');
    }
    return parsed;
  };

  const addressPayload = (body: Record<string, unknown>) => {
    const city = cleanText(body.city) ?? 'Астана';
    const street = cleanText(body.street);
    const house = cleanText(body.house);
    if (!street || !house) {
      throw new ApiError(400, 'address_required', 'Укажите улицу и номер дома.');
    }
    return {
      city,
      settlement: cleanText(body.settlement),
      street,
      house,
      apartment: cleanText(body.apartment),
      entrance: cleanText(body.entrance),
      floor: cleanText(body.floor),
      intercom: cleanText(body.intercom),
      accessComment: cleanText(body.accessComment),
      area: cleanNumber(body.area),
      latitude: cleanNumber(body.latitude),
      longitude: cleanNumber(body.longitude),
    };
  };

  const recordAudit = async (
    action: string,
    entityType: string,
    entityId: string | null,
    payload: Record<string, unknown> = {},
    actorId?: string | null,
  ) => {
    await deps.db.query(
      `INSERT INTO audit_logs (actor_id, action, entity_type, entity_id, payload)
       VALUES ($1,$2,$3,$4,$5)`,
      [actorId ?? null, action, entityType, entityId, payload],
    );
  };

  const normalizeKaspiPaymentStatus = (payload: Record<string, unknown>) => {
    const raw = String(payload.status ?? payload.paymentStatus ?? '').toLowerCase();
    if (['paid', 'approved', 'success', 'completed'].includes(raw)) return 'paid';
    if (['rejected', 'declined', 'failed', 'error'].includes(raw)) return 'rejected';
    if (['cancelled', 'canceled', 'expired'].includes(raw)) return 'cancelled';
    return 'pending';
  };

  const normalizeMoonAiKaspiStatus = (payload: Record<string, unknown>) => {
    const raw = String(payload.status ?? payload.paymentStatus ?? payload.invoiceStatus ?? '').toLowerCase();
    if (['paid', 'approved', 'success', 'completed', 'confirmed'].includes(raw)) return 'paid';
    if (['invoice_requested', 'invoice_sent', 'created', 'sent', 'issued'].includes(raw)) return 'invoice_requested';
    if (['rejected', 'declined', 'failed', 'error'].includes(raw)) return 'rejected';
    if (['cancelled', 'canceled', 'expired'].includes(raw)) return 'cancelled';
    return 'pending';
  };

  const verifyMoonAiWebhook = (req: any) => {
    if (!env.moonAiWebhookToken) {
      throw new ApiError(503, 'integration_not_configured', 'Webhook Moon AI не настроен.');
    }
    const authHeader = String(req.headers.authorization ?? '');
    const bearer = authHeader.toLowerCase().startsWith('bearer ') ? authHeader.slice(7).trim() : '';
    const token = String(req.headers['x-moonai-token'] ?? bearer);
    if (token !== env.moonAiWebhookToken) {
      throw new ApiError(401, 'unauthorized', 'Неверный токен webhook.');
    }
  };

  const normalizeBccPaymentStatus = (payload: Record<string, unknown>) => {
    const raw = String(payload.status ?? payload.STATUS ?? payload.result ?? payload.RESULT ?? payload.ACTION ?? '').toLowerCase();
    const response = String(payload.response ?? payload.RESPONSE ?? payload.rc ?? payload.RC ?? '');
    if (['approved', 'paid', 'success', 'completed', '0', '00'].includes(raw) || response === '00') return 'paid';
    if (['rejected', 'declined', 'failed', 'error'].includes(raw)) return 'rejected';
    if (['cancelled', 'canceled', 'expired'].includes(raw)) return 'cancelled';
    return 'pending';
  };

  const offerNextCleanerAndNotify = async (orderId: string, excludeCleanerIds: string[] = []) => {
    const settings = await readAppSettings(deps.db);
    const ttlMinutes = Number(settings.cleanerOfferTtlMinutes ?? 2);
    const offer = await deps.scheduling.offerNextCleaner(orderId, excludeCleanerIds, ttlMinutes) as any;
    if (!offer) return null;
    await deps.notifications.create({
      userId: offer.cleaner_id,
      titleRu: 'Новый заказ',
      bodyRu: 'Вам поступил новый заказ на подтверждение.',
      targetType: 'order_offer',
      targetId: orderId,
      dedupeKey: `order-offer-${orderId}-${offer.cleaner_id}-${new Date(offer.expires_at).toISOString()}`,
    });
    return offer;
  };

  const applyPackagePromotions = async (payment: any) => {
    if (!payment?.customer_id || !payment?.customer_package_id) return [];
    const packagePurchase = first<{
      id: string;
      package_id: string;
      customer_id: string;
      amount: string;
      bonus_amount: string;
    }>((await deps.db.query(
      `SELECT cp.id, cp.package_id, cp.customer_id, p.amount, p.bonus_amount
       FROM customer_packages cp
       JOIN payments p ON p.customer_package_id=cp.id
       WHERE cp.id=$1 AND p.id=$2`,
      [payment.customer_package_id, payment.id],
    )).rows);
    if (!packagePurchase) return [];
    const paidBaseAmount = Number(packagePurchase.amount) + Number(packagePurchase.bonus_amount ?? 0);
    const promotions = (await deps.db.query<{
      id: string;
      title_ru: string;
      title_kk: string | null;
      reward_type: string;
      reward_value: string;
      once_per_customer: boolean;
    }>(
      `SELECT id, title_ru, title_kk, reward_type, reward_value, once_per_customer
       FROM promotions
       WHERE active=TRUE
       AND (package_id IS NULL OR package_id=$1)
       AND (starts_at IS NULL OR starts_at<=NOW())
       AND (ends_at IS NULL OR ends_at>=NOW())
       ORDER BY created_at ASC`,
      [packagePurchase.package_id],
    )).rows;
    const applied = [];
    for (const promo of promotions) {
      const reward = promo.reward_type === 'percent'
        ? Math.round(paidBaseAmount * (Number(promo.reward_value) / 100))
        : Math.round(Number(promo.reward_value));
      if (reward <= 0) continue;
      const onceKey = promo.once_per_customer ? `${promo.id}:${packagePurchase.customer_id}` : null;
      const row = await deps.db.transaction(async () => {
        const redemption = first((await deps.db.query(
          `INSERT INTO promotion_redemptions
           (promotion_id, customer_id, customer_package_id, payment_id, reward_amount, once_key)
           VALUES ($1,$2,$3,$4,$5,$6)
           ON CONFLICT DO NOTHING
           RETURNING *`,
          [promo.id, packagePurchase.customer_id, packagePurchase.id, payment.id, reward, onceKey],
        )).rows);
        if (!redemption) return null;
        const user = first<{ bonus_balance: string }>((await deps.db.query(
          `UPDATE app_users SET bonus_balance=bonus_balance+$2, updated_at=NOW()
           WHERE id=$1 RETURNING bonus_balance`,
          [packagePurchase.customer_id, reward],
        )).rows);
        await deps.db.query(
          `INSERT INTO bonus_transactions (user_id, payment_id, type, amount, balance_after, reason_ru, reason_kk)
           VALUES ($1,$2,'accrual',$3,$4,$5,$6)`,
          [
            packagePurchase.customer_id,
            payment.id,
            reward,
            user?.bonus_balance ?? reward,
            `Бонус по акции: ${promo.title_ru}`,
            promo.title_kk ? `Акция бойынша бонус: ${promo.title_kk}` : null,
          ],
        );
        return redemption;
      });
      if (!row) continue;
      await deps.notifications.create({
        userId: packagePurchase.customer_id,
        titleRu: 'Начислены бонусы',
        titleKk: 'Бонустар есептелді',
        bodyRu: `По акции «${promo.title_ru}» начислено ${reward} бонусов.`,
        bodyKk: promo.title_kk ? `«${promo.title_kk}» акциясы бойынша ${reward} бонус есептелді.` : null,
        targetType: 'bonuses',
        targetId: String(payment.id),
        dedupeKey: `promotion-${promo.id}-${payment.id}`,
      });
      applied.push({ promotionId: promo.id, rewardAmount: reward });
    }
    return applied;
  };

  const applyPaidPayment = async (payment: any) => {
    if (!payment) return null;
    if (payment.status && payment.status !== 'paid') return payment;
    const acquiredPayment = await acquirePaymentApplication(deps.db, payment.id);
    if (!acquiredPayment) {
      return { ...payment, alreadyApplied: true };
    }
    payment = { ...payment, ...acquiredPayment };
    await recordAudit('payment.applied', 'payment', payment.id, {
      orderId: payment.order_id ?? null,
      customerPackageId: payment.customer_package_id ?? null,
      amount: payment.amount,
      bonusAmount: payment.bonus_amount,
      provider: payment.provider,
    });
    if (payment.customer_package_id) {
      await deps.db.query(
        `UPDATE customer_packages
         SET status='active', purchase_payment_id=COALESCE(purchase_payment_id, $2), updated_at=NOW()
         WHERE id=$1`,
        [payment.customer_package_id, payment.id],
      );
      payment.appliedPromotions = await applyPackagePromotions(payment);
      await qualifyReferral(deps.db, payment);
      payment.qualityCheck = await ensurePackageQualityCheck(deps.db, deps.notifications, payment.customer_package_id);
    }
    const preorderId = payment.payload?.preorderId;
    if (preorderId) {
      await deps.db.query(
        `UPDATE preorders
         SET status='paid', customer_package_id=COALESCE(customer_package_id, $2), payment_id=COALESCE(payment_id, $3), updated_at=NOW()
         WHERE id=$1`,
        [preorderId, payment.customer_package_id ?? null, payment.id],
      );
    }
    if (payment.order_id) {
      await deps.db.query(`UPDATE service_orders SET status=CASE WHEN cleaner_id IS NULL THEN 'pending_assignment' ELSE 'assigned' END, payable_amount=0, updated_at=NOW() WHERE id=$1`, [payment.order_id]);
      await deps.db.query(`UPDATE order_addons SET payment_status='paid' WHERE order_id=$1`, [payment.order_id]);
      const assigned = first<any>((await deps.db.query('SELECT cleaner_id FROM service_orders WHERE id=$1',[payment.order_id])).rows);
      if (!assigned?.cleaner_id) await offerNextCleanerAndNotify(payment.order_id);
    }
    if (payment.customer_id) {
      await deps.notifications.create({
        userId: payment.customer_id,
        titleRu: 'Оплата подтверждена',
        bodyRu: 'Платёж подтверждён.',
        targetType: payment.order_id ? 'order' : 'package',
        targetId: payment.order_id ?? payment.customer_package_id ?? '',
        dedupeKey: `payment-paid-${payment.id}`,
      });
    }
    return payment;
  };

  router.post('/auth/otp/request', asyncHandler(async (req, res) => {
    ok(res, await deps.authService.requestOtp(String(req.body.phone ?? '')));
  }));

  router.post('/auth/otp/verify', asyncHandler(async (req, res) => {
    const result = await deps.authService.verifyOtp(String(req.body.phone ?? ''), String(req.body.code ?? ''), req.body.role ?? 'customer');
    if ((result as any).isNew) {
      await deps.notifications.createAdminEvent({
        event: (result.user as any).role === 'cleaner' ? 'new_cleaner' : 'new_user',
        titleRu: (result.user as any).role === 'cleaner' ? 'Новая уборщица' : 'Новый пользователь',
        bodyRu: `Зарегистрирован номер ${(result.user as any).phone}.`,
        targetType: 'user',
        targetId: (result.user as any).id,
        dedupeKey: `new-user-${(result.user as any).id}`,
      });
    }
    ok(res, result);
  }));

  router.post('/auth/password/login', asyncHandler(async (req, res) => {
    ok(res, await deps.authService.loginWithPassword(String(req.body.phone ?? ''), String(req.body.password ?? '')));
  }));

  router.post('/auth/refresh', asyncHandler(async (req, res) => {
    const refreshToken = String(req.body.refreshToken ?? '');
    if (!refreshToken) throw new ApiError(401, 'unauthorized', 'Войдите в аккаунт заново.');
    const user = verifyRefreshToken(refreshToken);
    const nextRefreshToken = signRefreshToken(user);
    const accessToken = signAccessToken(user);
    await deps.db.transaction(async (tx) => {
      const session = first((await tx.query(
        `SELECT id FROM refresh_sessions
         WHERE user_id=$1 AND token_hash=$2 AND revoked_at IS NULL AND expires_at > NOW()
         FOR UPDATE`,
        [user.id, hashToken(refreshToken)],
      )).rows);
      if (!session) throw new ApiError(401, 'unauthorized', 'Сессия истекла. Войдите заново.');
      await tx.query(`UPDATE refresh_sessions SET revoked_at=NOW() WHERE id=$1`, [(session as any).id]);
      await tx.query(
        `INSERT INTO refresh_sessions (user_id, token_hash, expires_at)
         VALUES ($1,$2,NOW() + ($3 || ' seconds')::interval)`,
        [user.id, hashToken(nextRefreshToken), env.jwtRefreshTtlSeconds],
      );
    });
    ok(res, { accessToken, refreshToken: nextRefreshToken, user });
  }));

  router.post('/auth/logout', auth(), asyncHandler(async (req, res) => {
    ok(res, await deps.authService.logout({
      userId: req.user!.id,
      refreshToken: req.body.refreshToken ? String(req.body.refreshToken) : null,
      allDevices: req.body.allDevices === true,
      deviceToken: req.body.deviceToken ? String(req.body.deviceToken) : null,
    }));
  }));

  router.get('/me', auth(), asyncHandler(async (req, res) => {
    const user = first((await deps.db.query(`SELECT * FROM app_users WHERE id=$1`, [req.user!.id])).rows);
    const addresses = (await deps.db.query(
      `SELECT * FROM customer_addresses WHERE user_id=$1 ORDER BY is_primary DESC, created_at DESC`,
      [req.user!.id],
    )).rows;
    const safeUser = {...(user as any)};
    delete safeUser.password_hash;
    if (req.user!.role === 'customer') {
      const stats = first<any>((await deps.db.query('SELECT COUNT(*)::int AS total FROM user_referrals WHERE inviter_id=$1 AND qualified_at IS NOT NULL', [req.user!.id])).rows);
      const own = first<any>((await deps.db.query("SELECT 'DOMLY-' || u.numeric_id AS code FROM user_referrals r JOIN app_users u ON u.id=r.inviter_id WHERE r.customer_id=$1", [req.user!.id])).rows);
      Object.assign(safeUser, {referralCode: `DOMLY-${safeUser.numeric_id}`, referredByCode: own?.code,
        referralQualifiedCount: stats.total, referralDiscountPercent: await referralDiscount(deps.db,req.user!.id)});
    }
    ok(res, { ...safeUser, addresses });
  }));

  router.patch('/me', auth(), asyncHandler(async (req, res) => {
    const row = first((await deps.db.query(
      `UPDATE app_users SET full_name=COALESCE($2, full_name), email=COALESCE($3, email), language=COALESCE($4, language), updated_at=NOW()
       WHERE id=$1 RETURNING *`,
      [req.user!.id, req.body.fullName ?? null, req.body.email ?? null, req.body.language ?? null],
    )).rows);
    ok(res, row);
  }));

  router.get('/me/settings', auth(), asyncHandler(async (req, res) => {
    const user = first<{ language: string }>((await deps.db.query(
      `SELECT language FROM app_users WHERE id=$1`,
      [req.user!.id],
    )).rows);
    ok(res, {
      userId: req.user!.id,
      language: user?.language ?? 'ru',
      notificationsEnabled: true,
      bonusNotificationsEnabled: true,
      orderNotificationsEnabled: true,
    });
  }));

  router.patch('/me/settings', auth(), asyncHandler(async (req, res) => {
    const language = req.body.language ? String(req.body.language) : null;
    const row = language
      ? first((await deps.db.query(
        `UPDATE app_users SET language=$2, updated_at=NOW() WHERE id=$1 RETURNING language`,
        [req.user!.id, language],
      )).rows)
      : { language: 'ru' };
    ok(res, {
      userId: req.user!.id,
      language: (row as any)?.language ?? 'ru',
      notificationsEnabled: req.body.notificationsEnabled ?? true,
      bonusNotificationsEnabled: req.body.bonusNotificationsEnabled ?? true,
      orderNotificationsEnabled: req.body.orderNotificationsEnabled ?? true,
    });
  }));

  router.post('/me/device-tokens', auth(), asyncHandler(async (req, res) => {
    const row = first((await deps.db.query(
      `INSERT INTO device_tokens (user_id, platform, token) VALUES ($1,$2,$3)
       ON CONFLICT (token) DO UPDATE SET user_id=$1, platform=$2, enabled=TRUE, updated_at=NOW()
       RETURNING id`,
      [req.user!.id, req.body.platform, req.body.token],
    )).rows);
    ok(res, row, 201);
  }));

  router.delete('/me/device-tokens/:token', auth(), asyncHandler(async (req, res) => {
    const decodedToken = decodeURIComponent(String(req.params.token));
    const row = first((await deps.db.query(
      `UPDATE device_tokens SET enabled=FALSE, updated_at=NOW()
       WHERE user_id=$1 AND token=$2
       RETURNING id`,
      [req.user!.id, decodedToken],
    )).rows);
    ok(res, { disabled: Boolean(row) });
  }));

  router.post('/files', auth(), upload.single('file'), asyncHandler(async (req, res) => {
    if (!req.file) throw new ApiError(400, 'file_required', 'Выберите файл для загрузки.');
    const ext = extensionFromMime(req.file.mimetype);
    const rawFolder = String(req.body.folder ?? 'uploads');
    const folder = rawFolder
      .split('/')
      .map((part) => part.replace(/[^a-zA-Z0-9_-]/g, '').trim())
      .filter(Boolean)
      .join('/') || 'uploads';
    const objectKey = `${folder}/${req.user!.id}/${new Date().toISOString().slice(0, 10)}/${randomUUID()}${ext}`;
    const publicUrl = await deps.storage.uploadBuffer(objectKey, req.file.buffer, req.file.mimetype);
    const row = first((await deps.db.query(
      `INSERT INTO files (owner_id, bucket, object_key, mime_type, size_bytes, public_url)
       VALUES ($1,$2,$3,$4,$5,$6) RETURNING *`,
      [req.user!.id, env.minioBucket, objectKey, req.file.mimetype, req.file.size, publicUrl],
    )).rows);
    ok(res, row, 201);
  }));

  router.get('/admin/files/preview', auth(['admin','superadmin']), asyncHandler(async (req,res)=>{
    const url=String(req.query.url??'');
    const file=first<any>((await deps.db.query('SELECT bucket,object_key,mime_type,size_bytes FROM files WHERE public_url=$1 LIMIT 1',[url])).rows);
    if (!file) throw new ApiError(404,'not_found','Файл не найден.');
    if (Number(file.size_bytes)>20*1024*1024) throw new ApiError(413,'file_too_large','Файл слишком большой для предпросмотра.');
    const stream=await deps.storage.client.getObject(file.bucket,file.object_key);
    const chunks:Buffer[]=[];
    let size=0;
    for await (const chunk of stream) {
      size+=chunk.length;
      if (size>20*1024*1024) {stream.destroy();throw new ApiError(413,'file_too_large','Файл слишком большой для предпросмотра.');}
      chunks.push(Buffer.from(chunk));
    }
    res.setHeader('Cache-Control','private, no-store');
    ok(res,{mimeType:file.mime_type??'application/octet-stream',base64:Buffer.concat(chunks).toString('base64')});
  }));

  router.get('/users', auth(['admin', 'superadmin']), asyncHandler(async (req, res) => {
    const { limit, offset } = pageParams(req.query);
    const role = req.query.role ? String(req.query.role) : null;
    const rows = (await deps.db.query(
      `SELECT id, numeric_id, role, phone, full_name, email, status, rating, bonus_balance, created_at
       FROM app_users
       WHERE ($1::text IS NULL OR role::text=$1)
       ORDER BY created_at DESC LIMIT $2 OFFSET $3`,
      [role, limit, offset],
    )).rows;
    ok(res, rows);
  }));

  router.get('/users/:id', auth(['admin', 'superadmin']), asyncHandler(async (req, res) => {
    const user = first((await deps.db.query(`SELECT * FROM app_users WHERE id=$1`, [req.params.id])).rows);
    if (!user) throw new ApiError(404, 'not_found', 'Пользователь не найден.');
    const addresses = (await deps.db.query(`SELECT * FROM customer_addresses WHERE user_id=$1 ORDER BY is_primary DESC`, [req.params.id])).rows;
    const orders = (await deps.db.query(`SELECT * FROM service_orders WHERE customer_id=$1 OR cleaner_id=$1 ORDER BY created_at DESC LIMIT 50`, [req.params.id])).rows;
    const payments = (await deps.db.query(`SELECT * FROM payments WHERE customer_id=$1 ORDER BY created_at DESC LIMIT 50`, [req.params.id])).rows;
    const bonuses = (await deps.db.query(`SELECT * FROM bonus_transactions WHERE user_id=$1 ORDER BY created_at DESC LIMIT 100`, [req.params.id])).rows;
    ok(res, { user, addresses, orders, payments, bonuses });
  }));

  router.patch('/admin/users/:id', auth(['admin', 'superadmin']), asyncHandler(async (req, res) => {
    const allowedStatuses = new Set(['new', 'pending', 'approved', 'rejected', 'blocked']);
    if (req.body.status && !allowedStatuses.has(String(req.body.status))) {
      throw new ApiError(400, 'invalid_status', 'Укажите корректный статус пользователя.');
    }
    const row = first((await deps.db.query(
      `UPDATE app_users SET
         full_name=COALESCE($2, full_name),
         email=COALESCE($3, email),
         language=COALESCE($4, language),
         rating=COALESCE($5, rating),
         status=COALESCE($6, status),
         is_phone_verified=COALESCE($7, is_phone_verified),
         updated_at=NOW()
       WHERE id=$1
       RETURNING id, numeric_id, role, phone, full_name, email, language, rating, status, bonus_balance, is_phone_verified, created_at, updated_at`,
      [
        req.params.id,
        req.body.fullName ?? null,
        req.body.email ?? null,
        req.body.language ?? null,
        req.body.rating ?? null,
        req.body.status ?? null,
        typeof req.body.isPhoneVerified === 'boolean' ? req.body.isPhoneVerified : null,
      ],
    )).rows);
    if (!row) throw new ApiError(404, 'not_found', 'Пользователь не найден.');
    await recordAudit('user.updated', 'user', String(req.params.id), req.body, req.user?.id);
    ok(res, row);
  }));

  router.post('/admin/users/:id/confirm-area', auth(['admin', 'superadmin']), asyncHandler(async (req, res) => {
    const area = Number(req.body.actualArea ?? req.body.approvedArea ?? req.body.area ?? 0);
    if (!Number.isFinite(area) || area <= 0) throw new ApiError(400, 'invalid_area', 'Укажите корректную площадь.');
    const user = first((await deps.db.query(
      `SELECT id FROM app_users WHERE id=$1 AND role='customer'`,
      [req.params.id],
    )).rows);
    if (!user) throw new ApiError(404, 'not_found', 'Клиент не найден.');
    const address = await deps.db.transaction(async client=>{
      const address=await confirmArea(client,String(req.params.id),null,area);
      if (!address) throw new ApiError(404,'address_not_found','У клиента не заполнен адрес.');
      return address;
    });
    await deps.notifications.create({
      userId: String(req.params.id),
      titleRu: 'Площадь подтверждена',
      bodyRu: `Подтверждённая площадь квартиры: ${area} м².`,
      titleKk: 'Аудан расталды',
      bodyKk: `Пәтердің расталған ауданы: ${area} м².`,
      targetType: 'quality_check',
      targetId: String((address as any).id),
    });
    await recordAudit('user.area_confirmed', 'user', String(req.params.id), { area }, req.user?.id);
    ok(res, { address });
  }));

  router.post('/admin/users/:id/bonus-adjustment', auth(['admin', 'superadmin']), asyncHandler(async (req, res) => {
    const amount = Number(req.body.amount);
    if (!Number.isFinite(amount) || amount === 0) throw new ApiError(400, 'invalid_amount', 'Укажите сумму бонусов.');
    const reasonRu = String(req.body.reasonRu ?? req.body.reason ?? 'Корректировка бонусов');
    const reasonKk = req.body.reasonKk ? String(req.body.reasonKk) : null;
    const transaction = await deps.db.transaction(async (tx) => {
      const user = first<{ bonus_balance: string }>((await tx.query(
        `SELECT bonus_balance FROM app_users WHERE id=$1 FOR UPDATE`,
        [req.params.id],
      )).rows);
      if (!user) throw new ApiError(404, 'not_found', 'Пользователь не найден.');
      const nextBalance = Number(user.bonus_balance) + amount;
      if (nextBalance < 0) throw new ApiError(400, 'insufficient_balance', 'Недостаточно бонусов для списания.');
      const updated = first<{ bonus_balance: string }>((await tx.query(
        `UPDATE app_users SET bonus_balance=$2, updated_at=NOW() WHERE id=$1 RETURNING bonus_balance`,
        [req.params.id, nextBalance],
      )).rows);
      return first((await tx.query(
        `INSERT INTO bonus_transactions (user_id, type, amount, balance_after, reason_ru, reason_kk)
         VALUES ($1,'correction',$2,$3,$4,$5) RETURNING *`,
        [req.params.id, amount, updated?.bonus_balance ?? nextBalance, reasonRu, reasonKk],
      )).rows);
    });
    await recordAudit('user.bonus_adjusted', 'user', String(req.params.id), { amount, reasonRu, reasonKk }, req.user?.id);
    ok(res, transaction, 201);
  }));

  router.post('/addresses', auth(['customer']), asyncHandler(async (req, res) => {
    const address = addressPayload(req.body ?? {});
    const row = first((await deps.db.query(
      `INSERT INTO customer_addresses
       (user_id, city, settlement, street, house, apartment, entrance, floor, intercom, access_comment, area, latitude, longitude, is_primary)
       VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,TRUE)
       RETURNING *`,
      [
        req.user!.id,
        address.city,
        address.settlement,
        address.street,
        address.house,
        address.apartment,
        address.entrance,
        address.floor,
        address.intercom,
        address.accessComment,
        address.area,
        address.latitude,
        address.longitude,
      ],
    )).rows);
    ok(res, row, 201);
  }));

  router.get('/addresses', auth(['customer']), asyncHandler(async (req, res) => {
    ok(res, (await deps.db.query(
      `SELECT * FROM customer_addresses WHERE user_id=$1 ORDER BY is_primary DESC, created_at DESC`,
      [req.user!.id],
    )).rows);
  }));

  router.patch('/addresses/:id', auth(['customer']), asyncHandler(async (req, res) => {
    const address = addressPayload(req.body ?? {});
    const row = first((await deps.db.query(
      `UPDATE customer_addresses SET
       city=COALESCE($3,city), settlement=COALESCE($4,settlement), street=COALESCE($5,street), house=COALESCE($6,house),
       apartment=COALESCE($7,apartment), entrance=COALESCE($8,entrance), floor=COALESCE($9,floor),
       intercom=COALESCE($10,intercom), access_comment=COALESCE($11,access_comment),
       area=COALESCE($12,area), latitude=COALESCE($13,latitude), longitude=COALESCE($14,longitude), updated_at=NOW()
       WHERE id=$1 AND user_id=$2 RETURNING *`,
      [
        req.params.id,
        req.user!.id,
        address.city,
        address.settlement,
        address.street,
        address.house,
        address.apartment,
        address.entrance,
        address.floor,
        address.intercom,
        address.accessComment,
        address.area,
        address.latitude,
        address.longitude,
      ],
    )).rows);
    if (!row) throw new ApiError(404, 'not_found', 'Адрес не найден.');
    ok(res, row);
  }));

  router.get('/bonus/history', auth(['customer']), asyncHandler(async (req, res) => {
    ok(res, (await deps.db.query(
      `SELECT * FROM bonus_transactions WHERE user_id=$1 ORDER BY created_at DESC LIMIT 200`,
      [req.user!.id],
    )).rows);
  }));

  router.post('/bonus/transactions', auth(), asyncHandler(async (req, res) => {
    const targetUserId = ['admin', 'superadmin'].includes(req.user!.role)
      ? String(req.body.userId ?? req.user!.id)
      : req.user!.id;
    const amount = Number(req.body.amount);
    if (!Number.isFinite(amount) || amount === 0) throw new ApiError(400, 'invalid_amount', 'Укажите сумму бонусов.');
    const type = amount < 0 ? 'spend' : 'accrual';
    const reasonRu = String(req.body.reasonRu ?? req.body.reason ?? (amount < 0 ? 'Списание бонусов' : 'Начисление бонусов'));
    const reasonKk = req.body.reasonKk ? String(req.body.reasonKk) : null;
    const tx = await deps.db.transaction(async (client) => {
      const user = first<{ bonus_balance: string }>((await client.query(
        `SELECT bonus_balance FROM app_users WHERE id=$1 FOR UPDATE`,
        [targetUserId],
      )).rows);
      if (!user) throw new ApiError(404, 'not_found', 'Пользователь не найден.');
      const nextBalance = Number(user.bonus_balance) + amount;
      if (nextBalance < 0) throw new ApiError(400, 'insufficient_balance', 'Недостаточно бонусов.');
      const updated = first<{ bonus_balance: string }>((await client.query(
        `UPDATE app_users SET bonus_balance=$2, updated_at=NOW() WHERE id=$1 RETURNING bonus_balance`,
        [targetUserId, nextBalance],
      )).rows);
      return first((await client.query(
        `INSERT INTO bonus_transactions (user_id, order_id, payment_id, type, amount, balance_after, reason_ru, reason_kk)
         VALUES ($1,$2,$3,$4,$5,$6,$7,$8) RETURNING *`,
        [
          targetUserId,
          req.body.orderId || null,
          req.body.paymentId || null,
          type,
          amount,
          updated?.bonus_balance ?? nextBalance,
          reasonRu,
          reasonKk,
        ],
      )).rows);
    });
    ok(res, tx, 201);
  }));

  router.get('/packages/my', auth(['customer']), asyncHandler(async (req, res) => {
    ok(res, (await deps.db.query(
      `SELECT cp.*, p.name_ru, p.name_kk, p.description_ru, p.description_kk, p.cleaning_count, p.months
       FROM customer_packages cp
       JOIN catalog_packages p ON p.id=cp.package_id
       WHERE cp.customer_id=$1
       ORDER BY cp.created_at DESC`,
      [req.user!.id],
    )).rows);
  }));

  router.patch('/packages/my/:id', auth(['customer']), asyncHandler(async (req, res) => {
    const row = first((await deps.db.query(
      `UPDATE customer_packages SET
       status=COALESCE($3,status),
       freeze_until=COALESCE($4,freeze_until),
       scheduled_cleanings=COALESCE($5,scheduled_cleanings),
       available_cleanings=COALESCE($6,available_cleanings),
       updated_at=NOW()
       WHERE id=$1 AND customer_id=$2 RETURNING *`,
      [
        req.params.id,
        req.user!.id,
        req.body.status ?? null,
        req.body.freezeUntil ?? null,
        req.body.scheduledVisits ?? null,
        req.body.remainingCleanings ?? null,
      ],
    )).rows);
    if (!row) throw new ApiError(404, 'not_found', 'Пакет не найден.');
    ok(res, row);
  }));

  router.post('/order-requests', auth(['customer']), asyncHandler(async (req, res) => {
    const address = first((await deps.db.query(
      `SELECT id FROM customer_addresses WHERE user_id=$1 ORDER BY is_primary DESC, created_at DESC LIMIT 1`,
      [req.user!.id],
    )).rows);
    const row = first((await deps.db.query(
      `INSERT INTO preorders
       (customer_id, address_id, requested_date, preferred_time, area, status, payload)
       VALUES ($1,$2,CURRENT_DATE,'',COALESCE($3,0),'created',$4) RETURNING *`,
      [req.user!.id, (address as any)?.id ?? null, req.body.area ?? 0, req.body],
    )).rows);
    ok(res, row, 201);
  }));

  router.get('/cleaner/profile', auth(['cleaner']), asyncHandler(async (req, res) => {
    const profile = first((await deps.db.query(
      `SELECT u.id, u.numeric_id, u.phone, u.full_name, u.email, u.status, u.rating, u.created_at AS registered_at,
              cp.*
       FROM app_users u
       LEFT JOIN cleaner_profiles cp ON cp.user_id=u.id
       WHERE u.id=$1`,
      [req.user!.id],
    )).rows);
    const documents = (await deps.db.query(`SELECT d.*,f.public_url FROM cleaner_documents d LEFT JOIN files f ON f.id=d.file_id WHERE d.cleaner_id=$1 ORDER BY d.created_at DESC`, [req.user!.id])).rows;
    const zones = (await deps.db.query(
      `SELECT z.* FROM cleaner_zones cz JOIN service_zones z ON z.id=cz.zone_id WHERE cz.cleaner_id=$1 ORDER BY z.city, z.name_ru`,
      [req.user!.id],
    )).rows;
    ok(res, { profile, documents, zones });
  }));

  router.patch('/cleaner/profile', auth(['cleaner']), asyncHandler(async (req, res) => {
    const profile = await deps.db.transaction(async client => {
    await client.query('SELECT id FROM app_users WHERE id=$1 FOR UPDATE',[req.user!.id]);
    const zoneIds = req.body.zoneIds;
    if (zoneIds !== undefined) {
      if (!Array.isArray(zoneIds) || zoneIds.some((id:unknown)=>typeof id !== 'string' || !/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(id))) throw new ApiError(400,'invalid_zones','Выберите корректные районы.');
      const ids = [...new Set(zoneIds)];
      const zones = (await client.query('SELECT id FROM service_zones WHERE id=ANY($1::uuid[]) AND active=TRUE FOR SHARE',[ids])).rows;
      if (zones.length !== ids.length) throw new ApiError(400,'invalid_zones','Один из выбранных районов недоступен.');
      await client.query('DELETE FROM cleaner_zones WHERE cleaner_id=$1',[req.user!.id]);
      await client.query('INSERT INTO cleaner_zones(cleaner_id,zone_id) SELECT $1,unnest($2::uuid[])',[req.user!.id,ids]);
    }
    if (req.body.fullName || req.body.email) {
      await client.query(
        `UPDATE app_users SET full_name=COALESCE($2,full_name), email=COALESCE($3,email), updated_at=NOW() WHERE id=$1`,
        [req.user!.id, req.body.fullName ?? null, req.body.email ?? null],
      );
    }
    const profile = first((await client.query(
      `INSERT INTO cleaner_profiles
       (user_id, city, registration_status, verification_status, monthly_area_limit, daily_work_limit_minutes, sound_enabled, sound_volume, sound_key)
       VALUES ($1,COALESCE($2,'Астана'),'pending','pending',COALESCE($3,220),COALESCE($4,540),COALESCE($5,TRUE),COALESCE($6,100),COALESCE($7,'system'))
       ON CONFLICT (user_id) DO UPDATE SET
         city=COALESCE($2,cleaner_profiles.city),
         monthly_area_limit=COALESCE($3,cleaner_profiles.monthly_area_limit),
         daily_work_limit_minutes=COALESCE($4,cleaner_profiles.daily_work_limit_minutes),
         sound_enabled=COALESCE($5,cleaner_profiles.sound_enabled),
         sound_volume=COALESCE($6,cleaner_profiles.sound_volume),
         sound_key=COALESCE($7,cleaner_profiles.sound_key),
         updated_at=NOW()
       RETURNING *`,
      [
        req.user!.id,
        req.body.city ?? null,
        req.body.monthlyAreaLimit ?? null,
        req.body.dailyWorkLimitMinutes ?? null,
        req.body.soundEnabled ?? null,
        req.body.soundVolume ?? null,
        req.body.soundKey ?? null,
      ],
    )).rows);
    return profile;
    });
    ok(res, profile);
  }));

  router.post('/cleaner/documents', auth(['cleaner']), upload.single('file'), asyncHandler(async (req, res) => {
    if (!req.file) throw new ApiError(400, 'file_required', 'Загрузите документ.');
    const ext = extensionFromMime(req.file.mimetype);
    const objectKey = `${req.user!.id}/documents/${randomUUID()}${ext}`;
    const publicUrl = await deps.storage.uploadBuffer(objectKey, req.file.buffer, req.file.mimetype);
    const file = first((await deps.db.query(
      `INSERT INTO files (owner_id, bucket, object_key, mime_type, size_bytes, public_url)
       VALUES ($1,$2,$3,$4,$5,$6) RETURNING *`,
      [req.user!.id, 'domly', objectKey, req.file.mimetype, req.file.size, publicUrl],
    )).rows);
    const document = first((await deps.db.query(
      `INSERT INTO cleaner_documents (cleaner_id, type, file_id, status) VALUES ($1,$2,$3,'pending') RETURNING *`,
      [req.user!.id, req.body.type ?? 'document', (file as any).id],
    )).rows);
    await deps.db.query(
      `INSERT INTO cleaner_profiles (user_id, registration_status, verification_status)
       VALUES ($1,'pending','pending')
       ON CONFLICT (user_id) DO UPDATE SET registration_status='pending', verification_status='pending', updated_at=NOW()`,
      [req.user!.id],
    );
    await deps.notifications.createAdminEvent({
      event: 'new_cleaner',
      titleRu: 'Новая уборщица на проверку',
      bodyRu: 'Уборщица загрузила документы для верификации.',
      targetType: 'cleaner',
      targetId: req.user!.id,
      dedupeKey: `cleaner-documents-${req.user!.id}`,
    });
    ok(res, { file, document }, 201);
  }));

  router.post('/cleaner/verification', auth(['cleaner']), asyncHandler(async (req, res) => {
    const documents = Object.entries(req.body ?? {})
      .filter(([key, value]) => key !== 'expiresAt' && key !== 'expiryDate' && typeof value === 'string' && value.trim())
      .map(([type, url]) => ({ type, url: String(url).trim() }));
    if (documents.length === 0) {
      throw new ApiError(400, 'documents_required', 'Загрузите документы для проверки.');
    }
    const savedDocuments = [];
    for (const item of documents) {
      const file = first((await deps.db.query(
        `INSERT INTO files (owner_id, bucket, object_key, mime_type, public_url)
         VALUES ($1,$2,$3,$4,$5)
         ON CONFLICT (bucket, object_key) DO UPDATE SET public_url=EXCLUDED.public_url
         RETURNING *`,
        [req.user!.id, 'external', `cleaner-documents/${req.user!.id}/${item.type}`, null, item.url],
      )).rows);
      const document = first((await deps.db.query(
        `INSERT INTO cleaner_documents (cleaner_id, type, file_id, status)
         VALUES ($1,$2,$3,'pending')
         RETURNING *`,
        [req.user!.id, item.type, (file as any).id],
      )).rows);
      savedDocuments.push({ file, document });
    }
    const profile = first((await deps.db.query(
      `INSERT INTO cleaner_profiles (user_id, registration_status, verification_status)
       VALUES ($1,'pending','pending')
       ON CONFLICT (user_id) DO UPDATE SET registration_status='pending', verification_status='pending', updated_at=NOW()
       RETURNING *`,
      [req.user!.id],
    )).rows);
    await deps.notifications.createAdminEvent({
      event: 'new_cleaner',
      titleRu: 'Новая уборщица на проверку',
      bodyRu: 'Уборщица отправила документы для верификации.',
      targetType: 'cleaner',
      targetId: req.user!.id,
      dedupeKey: `cleaner-verification-${req.user!.id}`,
    });
    ok(res, { ok: true, cleanerId: req.user!.id, status: 'pending', profile, documents: savedDocuments }, 201);
  }));

  router.get('/catalog/packages', asyncHandler(async (_req, res) => {
    ok(res, (await deps.db.query(`SELECT * FROM catalog_packages WHERE active=TRUE ORDER BY cleaning_count, base_price`)).rows);
  }));

  router.get('/catalog/addons', asyncHandler(async (_req, res) => {
    ok(res, (await deps.db.query(
      `SELECT a.*, g.title_ru AS group_title_ru, g.title_kk AS group_title_kk
       FROM catalog_addons a LEFT JOIN addon_groups g ON g.id=a.group_id
       WHERE a.active=TRUE ORDER BY g.sort_order, a.sort_order, a.title_ru`,
    )).rows);
  }));

  router.get('/catalog/banners', asyncHandler(async (req, res) => {
    ok(res, (await deps.db.query(
      `SELECT * FROM banners WHERE active=TRUE AND placement=$1 ORDER BY sort_order, created_at DESC`,
      [req.query.placement ?? 'home_top'],
    )).rows);
  }));

  router.get('/geo/zones', asyncHandler(async (req,res)=>{
    const {limit,offset}=pageParams(req.query);
    ok(res,(await deps.db.query('SELECT * FROM service_zones WHERE active=TRUE AND ($1::text IS NULL OR city=$1) ORDER BY city,name_ru,id LIMIT $2 OFFSET $3',[req.query.city?String(req.query.city):null,limit,offset])).rows);
  }));

  router.get('/geo/cities', asyncHandler(async (req, res) => {
    const search = `%${normalizeText(String(req.query.search ?? ''))}%`;
    const { limit, offset } = pageParams(req.query);
    ok(res, (await deps.db.query(
      `SELECT * FROM city_directory
       WHERE domly_normalize_address(concat_ws(' ',name_ru,name_kk,array_to_string(aliases,' '))) LIKE $1
       ORDER BY name_ru LIMIT $2 OFFSET $3`, [search,limit,offset],
    )).rows);
  }));

  router.get('/geo/connected-houses', asyncHandler(async (req, res) => {
    const { limit, offset } = pageParams(req.query);
    const city = req.query.city ? String(req.query.city) : null;
    const search = req.query.search ? `%${String(req.query.search)}%` : null;
    ok(res, (await deps.db.query(
      `SELECT h.*, z.name_ru AS zone_name_ru, z.name_kk AS zone_name_kk
       FROM connected_houses h
       LEFT JOIN service_zones z ON z.id=h.zone_id
       WHERE h.active=TRUE
       AND ($1::text IS NULL OR h.city ILIKE $1)
       AND (
         $2::text IS NULL
         OR h.street_ru ILIKE $2 OR h.street_kk ILIKE $2
         OR h.residential_complex_ru ILIKE $2 OR h.residential_complex_kk ILIKE $2
         OR h.house ILIKE $2
       )
       ORDER BY h.city, h.street_ru, h.house
       LIMIT $3 OFFSET $4`,
      [city, search, limit, offset],
    )).rows);
  }));

  router.get('/geo/address-suggestions', asyncHandler(async (req, res) => {
    const query = String(req.query.search ?? req.query.q ?? '').trim();
    if (query.length < 2) {
      ok(res, { suggestions: [], source: 'empty' });
      return;
    }
    const city = req.query.city ? String(req.query.city) : null;
    const lat = req.query.lat ? Number(req.query.lat) : null;
    const lng = req.query.lng ? Number(req.query.lng) : null;
    const limit = Math.min(Number(req.query.limit ?? 10), 10);
    const radiusKm = Number(req.query.radiusKm ?? 50);
    const normalizedQuery = normalizeText(query);
    const localRows = (await deps.db.query<any>(
      `SELECT h.*, z.name_ru AS zone_name_ru, z.name_kk AS zone_name_kk
       FROM connected_houses h
       LEFT JOIN service_zones z ON z.id=h.zone_id
       WHERE ($1::text IS NULL OR h.city ILIKE $1)
       AND domly_normalize_address(concat_ws(' ',h.city,h.street_ru,h.street_kk,
           h.residential_complex_ru,h.residential_complex_kk,h.house)) LIKE ALL($2::text[])
       ORDER BY h.active DESC, h.city, h.street_ru, h.house
       LIMIT 100`,
      [city ? `%${city}%` : null, normalizedQuery.split(' ').filter(Boolean).map(token => `%${token}%`)],
    )).rows
      .map((house: any) => {
        const haystack = normalizeText([
          house.city,
          house.street_ru,
          house.street_kk,
          house.residential_complex_ru,
          house.residential_complex_kk,
          house.house,
        ].filter(Boolean).join(' '));
        const score = scoreAddressMatch(normalizedQuery, haystack);
        return { house, score };
      })
      .filter((row: any) => row.score > 0)
      .sort((a: any, b: any) => b.score - a.score)
      .slice(0, limit)
      .map(({ house }: any) => ({
        source: house.active ? 'connected_house' : 'address_directory',
        connected: house.active,
        id: house.id,
        label: formatHouseLabel(house),
        city: house.city,
        street: house.street_ru ?? house.street_kk,
        house: house.house,
        residentialComplex: house.residential_complex_ru ?? house.residential_complex_kk,
        entranceCount: house.entrance_count,
        zoneId: house.zone_id,
        zoneNameRu: house.zone_name_ru,
        zoneNameKk: house.zone_name_kk,
        lat: house.latitude,
        lng: house.longitude,
      }));
    if (localRows.length >= Math.min(3, limit)) {
      ok(res, { suggestions: localRows, source: 'connected_houses' });
      return;
    }
    const externalRows = await deps.addressSearch.externalSuggestions({
      query,
      city,
      lat,
      lng,
      radiusKm,
      limit: limit - localRows.length,
    });
    ok(res, { suggestions: [...localRows, ...externalRows].slice(0, limit), source: localRows.length ? 'mixed' : 'external' });
  }));

  router.get('/geo/reverse', asyncHandler(async (req, res) => {
    const lat = Number(req.query.lat), lng = Number(req.query.lng);
    if (!req.query.lat || !req.query.lng || !Number.isFinite(lat) || !Number.isFinite(lng) || Math.abs(lat)>90 || Math.abs(lng)>180) {
      throw new ApiError(400, 'invalid_coordinates', 'Проверьте координаты.');
    }
    ok(res, {suggestion: await deps.addressSearch.reverse(lat, lng)});
  }));

  router.post('/geo/service-address-requests', auth(['customer']), asyncHandler(async (req, res) => {
    const address = String(req.body.address ?? req.body.residentialComplex ?? '').trim();
    if (!address) throw new ApiError(400, 'address_required', 'Укажите адрес дома.');
    const residentialComplex = String(req.body.residentialComplex ?? address).trim();
    const row = first((await deps.db.query(
      `INSERT INTO service_address_requests
         (customer_id, city, residential_complex, address, address_place_id, entrance, apartment, area, latitude, longitude, status)
       VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,'waiting')
       RETURNING *`,
      [
        req.user!.id,
        req.body.city ?? null,
        residentialComplex,
        address,
        req.body.addressPlaceId ?? null,
        req.body.entrance ?? null,
        req.body.apartment ?? null,
        req.body.area ?? null,
        req.body.lat ?? req.body.latitude ?? null,
        req.body.lng ?? req.body.longitude ?? null,
      ],
    )).rows);
    await deps.notifications.createAdminEvent({
      event: 'address_request',
      titleRu: 'Новая заявка на подключение адреса',
      bodyRu: `Клиент отправил адрес: ${address}.`,
      targetType: 'address_request',
      targetId: String((row as any).id),
      dedupeKey: `address-request-${(row as any).id}`,
    });
    ok(res, {
      ok: true,
      houseId: (row as any).id,
      requestId: (row as any).id,
      status: 'IN_PROGRESS',
      address,
      residentialComplex,
      lat: (row as any).latitude,
      lng: (row as any).longitude,
    }, 201);
  }));

  router.get('/translations', asyncHandler(async (_req, res) => {
    ok(res, (await deps.db.query(`SELECT key, ru, kk, namespace, updated_at FROM translations ORDER BY namespace, key`)).rows);
  }));

  router.get('/content-pages', asyncHandler(async (req, res) => {
    const kind = req.query.kind ? String(req.query.kind) : null;
    ok(res, (await deps.db.query(
      `SELECT slug, title_ru, title_kk, body_ru, body_kk, kind, updated_at
       FROM content_pages
       WHERE active=TRUE AND ($1::text IS NULL OR kind=$1)
       ORDER BY kind, slug`,
      [kind],
    )).rows);
  }));

  router.get('/content-pages/:slug', asyncHandler(async (req, res) => {
    const page = first((await deps.db.query(
      `SELECT slug, title_ru, title_kk, body_ru, body_kk, kind, updated_at
       FROM content_pages
       WHERE slug=$1 AND active=TRUE`,
      [req.params.slug],
    )).rows);
    if (!page) throw new ApiError(404, 'not_found', 'Страница не найдена.');
    ok(res, page);
  }));

  router.get('/training/video-views', auth(), asyncHandler(async (req, res) => {
    ok(res, (await deps.db.query(
      `SELECT video_id, audience_type, completed, last_progress_seconds, viewed_at, updated_at
       FROM video_views
       WHERE user_id=$1
       ORDER BY updated_at DESC`,
      [req.user!.id],
    )).rows);
  }));

  router.post('/training/videos/:id/viewed', auth(), asyncHandler(async (req, res) => {
    const videoId = String(req.params.id ?? '').trim();
    if (!videoId) throw new ApiError(400, 'invalid_argument', 'Не указано видео.');
    const row = first((await deps.db.query(
      `INSERT INTO video_views (user_id, video_id, audience_type, completed, last_progress_seconds, viewed_at, updated_at)
       VALUES ($1,$2,$3,COALESCE($4,TRUE),COALESCE($5,0),NOW(),NOW())
       ON CONFLICT (user_id, video_id) DO UPDATE SET
         audience_type=EXCLUDED.audience_type,
         completed=EXCLUDED.completed,
         last_progress_seconds=EXCLUDED.last_progress_seconds,
         viewed_at=CASE WHEN EXCLUDED.completed THEN NOW() ELSE video_views.viewed_at END,
         updated_at=NOW()
       RETURNING *`,
      [
        req.user!.id,
        videoId,
        req.body.audienceType ?? req.user!.role,
        req.body.completed ?? true,
        req.body.lastProgressSeconds ?? 0,
      ],
    )).rows);
    ok(res, row, 201);
  }));

  router.get('/app/config', asyncHandler(async (req, res) => {
    const lang = String(req.query.lang ?? 'ru');
    const settings = await readAppSettings(deps.db);
    const translations = (await deps.db.query(`SELECT key, ru, kk, namespace FROM translations`)).rows;
    const packages = (await deps.db.query(`SELECT * FROM catalog_packages WHERE active=TRUE ORDER BY cleaning_count, base_price`)).rows;
    const addonGroups = (await deps.db.query(`SELECT * FROM addon_groups WHERE active=TRUE ORDER BY sort_order`)).rows;
    const addons = (await deps.db.query(`SELECT * FROM catalog_addons WHERE active=TRUE ORDER BY sort_order, title_ru`)).rows;
    const banners = (await deps.db.query(`SELECT * FROM banners WHERE active=TRUE ORDER BY placement, sort_order`)).rows;
    const promotions = (await deps.db.query(`SELECT * FROM promotions WHERE active=TRUE ORDER BY created_at DESC`)).rows;
    const contentPages = (await deps.db.query(
      `SELECT slug, title_ru, title_kk, kind, updated_at FROM content_pages WHERE active=TRUE ORDER BY kind, slug`,
    )).rows;
    ok(res, {
      lang,
      settings,
      translations,
      catalog: { packages, addonGroups, addons, banners, promotions },
      contentPages,
      rules: buildRuntimeConfig(settings).rules,
      backendDriven: buildRuntimeConfig(settings).backendDriven,
    });
  }));

  router.get('/app/bootstrap', asyncHandler(async (req, res) => {
    const lang = String(req.query.lang ?? 'ru');
    const settingsRows = (await deps.db.query<{ key: string; value: any; updated_at: Date }>(
      `SELECT key, value, updated_at FROM app_settings ORDER BY key`,
    )).rows;
    const settings = settingsRows.reduce((acc: Record<string, unknown>, row) => ({ ...acc, [row.key]: row.value }), {});
    const translations = (await deps.db.query(`SELECT key, ru, kk, namespace, updated_at FROM translations ORDER BY namespace, key`)).rows;
    const packages = (await deps.db.query(`SELECT * FROM catalog_packages WHERE active=TRUE ORDER BY cleaning_count, base_price`)).rows;
    const addonGroups = (await deps.db.query(`SELECT * FROM addon_groups WHERE active=TRUE ORDER BY sort_order`)).rows;
    const addons = (await deps.db.query(
      `SELECT a.*, g.title_ru AS group_title_ru, g.title_kk AS group_title_kk
       FROM catalog_addons a LEFT JOIN addon_groups g ON g.id=a.group_id
       WHERE a.active=TRUE ORDER BY g.sort_order, a.sort_order, a.title_ru`,
    )).rows;
    const banners = (await deps.db.query(`SELECT * FROM banners WHERE active=TRUE ORDER BY placement, sort_order, created_at DESC`)).rows;
    const promotions = (await deps.db.query(`SELECT * FROM promotions WHERE active=TRUE ORDER BY created_at DESC`)).rows;
    const contentPages = (await deps.db.query(
      `SELECT slug, title_ru, title_kk, body_ru, body_kk, kind, updated_at
       FROM content_pages WHERE active=TRUE ORDER BY kind, slug`,
    )).rows;
    const updatedAt = [
      ...settingsRows.map((row) => row.updated_at?.toISOString?.() ?? String(row.updated_at ?? '')),
      ...translations.map((row: any) => row.updated_at?.toISOString?.() ?? String(row.updated_at ?? '')),
      ...packages.map((row: any) => row.updated_at?.toISOString?.() ?? String(row.updated_at ?? '')),
      ...addons.map((row: any) => row.updated_at?.toISOString?.() ?? String(row.updated_at ?? '')),
      ...banners.map((row: any) => row.updated_at?.toISOString?.() ?? String(row.updated_at ?? '')),
      ...promotions.map((row: any) => row.updated_at?.toISOString?.() ?? String(row.updated_at ?? '')),
      ...contentPages.map((row: any) => row.updated_at?.toISOString?.() ?? String(row.updated_at ?? '')),
    ].filter(Boolean).sort().at(-1) ?? 'initial';
    const runtime = buildRuntimeConfig(settings);
    const payload = {
      lang,
      version: createHash('sha256').update(JSON.stringify({ settings, translations, packages, addonGroups, addons, banners, promotions, contentPages })).digest('hex').slice(0, 16),
      updatedAt,
      ...runtime,
      settings,
      translations,
      catalog: { packages, addonGroups, addons, banners, promotions },
      contentPages,
    };
    const etag = `"bootstrap-${payload.version}"`;
    res.setHeader('ETag', etag);
    res.setHeader('Cache-Control', 'no-cache');
    if (req.headers['if-none-match'] === etag) {
      res.status(304).end();
      return;
    }
    ok(res, payload);
  }));

  router.get('/app/versions', asyncHandler(async (_req, res) => {
    const versions = await buildAppVersions(deps.db);
    const etag = `"versions-${versions.version}"`;
    res.setHeader('ETag', etag);
    res.setHeader('Cache-Control', 'no-cache');
    if (_req.headers['if-none-match'] === etag) {
      res.status(304).end();
      return;
    }
    ok(res, versions);
  }));

  router.get('/app/runtime-config', asyncHandler(async (req, res) => {
    const settingsRows = (await deps.db.query<{ key: string; value: any; updated_at: Date }>(
      `SELECT key, value, updated_at FROM app_settings ORDER BY key`,
    )).rows;
    const settings = settingsRows.reduce((acc: Record<string, unknown>, row) => ({ ...acc, [row.key]: row.value }), {});
    const updatedAt = settingsRows
      .map((row) => row.updated_at?.toISOString?.() ?? String(row.updated_at ?? ''))
      .sort()
      .at(-1) ?? 'initial';
    const payload = {
      lang: String(req.query.lang ?? 'ru'),
      version: createHash('sha256').update(JSON.stringify(settings)).digest('hex').slice(0, 16),
      updatedAt,
      ...buildRuntimeConfig(settings),
    };
    const etag = `"runtime-${payload.version}"`;
    res.setHeader('ETag', etag);
    res.setHeader('Cache-Control', 'no-cache');
    if (req.headers['if-none-match'] === etag) {
      res.status(304).end();
      return;
    }
    ok(res, payload);
  }));

  router.post('/packages/quote', asyncHandler(async (req, res) => {
    ok(res, await packageQuote(deps.db, {...req.body, customerId: req.user?.id}));
  }));

  router.post('/packages/purchase', auth(['customer']), asyncHandler(async (req, res) => {
    const pkg = first<{ id: string; base_price: string; price_per_m2: string; cleaning_count: number; months: number }>((await deps.db.query(
      `SELECT * FROM catalog_packages WHERE id=$1 AND active=TRUE`,
      [req.body.packageId],
    )).rows);
    if (!pkg) throw new ApiError(404, 'not_found', 'Пакет не найден.');
    const address = first<{ id: string; area: string; city: string; settlement: string | null; street: string; house: string; apartment: string | null }>((await deps.db.query(
      `SELECT id, area, city, settlement, street, house, apartment FROM customer_addresses WHERE id=$1 AND user_id=$2`,
      [req.body.addressId, req.user!.id],
    )).rows);
    if (!address?.area) throw new ApiError(400, 'area_required', 'Заполните площадь квартиры в профиле.');
    const quote = await packageQuote(deps.db, {...req.body, area: Number(address.area), customerId: req.user!.id});
    const total = quote.monthlyPrice;
    const customerPackage = first((await deps.db.query(
      `INSERT INTO customer_packages (customer_id, package_id, address_id, total_cleanings, available_cleanings, months, status, purchase_config)
       VALUES ($1,$2,$3,$4,$4,$5,'pending_payment',$6) RETURNING *`,
      [req.user!.id, pkg.id, address.id, quote.cleaningCount, pkg.months, quote],
    )).rows);
    const payment = await deps.payments.createPayment({
      customerId: req.user!.id,
      customerPackageId: (customerPackage as { id: string }).id,
      provider: req.body.provider ?? 'kaspi',
      applyReferralDiscount: false,
      amount: total,
      useBonus: req.body.useBonus === true,
      requestedBonus: Number(req.body.requestedBonus ?? 0),
      invoicePhone: req.body.invoicePhone,
      payload: { kind: 'package_purchase', mInfo: formatPaymentAddress(address), quote },
    });
    await deps.notifications.createAdminEvent({
      event: 'new_payment',
      titleRu: 'Новая заявка на оплату',
      bodyRu: `Клиент покупает пакет на сумму ${total} ₸.`,
      targetType: 'payment',
      targetId: (payment.payment as any).id,
      dedupeKey: `payment-${(payment.payment as any).id}`,
    });
    if (payment.payableAmount === 0) {
      await applyPaidPayment(payment.payment);
    } else {
      const provider = await initProviderPayment(deps.paymentGateway, payment, req, 'Покупка пакета DOMLY');
      if (provider) await updatePaymentProviderPayload(deps.db, (payment.payment as any).id, provider);
    }
    ok(res, { customerPackage, ...payment });
  }));

  router.post('/orders', auth(['customer']), asyncHandler(async (req, res) => {
    const customerPackage = first<{ id: string; package_id: string; address_id: string; available_cleanings: number; total_cleanings: number; status: string; purchase_config: any; freeze_until?: string }>((await deps.db.query(
      `SELECT * FROM customer_packages WHERE id=$1 AND customer_id=$2`,
      [req.body.customerPackageId, req.user!.id],
    )).rows);
    if (!customerPackage || customerPackage.status !== 'active') throw new ApiError(402, 'payment_required', 'Сначала подтвердите оплату пакета.');
    if (customerPackage.freeze_until && String(req.body.date) <= String(customerPackage.freeze_until).slice(0,10)) throw new ApiError(409,'package_frozen','Пакет заморожен на выбранную дату.');
    if (customerPackage.available_cleanings <= 0) throw new ApiError(400, 'no_cleanings_left', 'В пакете не осталось доступных уборок.');
    const prepaid = (customerPackage.purchase_config?.addons ?? []) as any[];
    const prepaidIds = new Set(prepaid.map(item=>item.id));
    const addonIds = (Array.isArray(req.body.addonIds) ? req.body.addonIds : []).filter((id: string)=>!prepaidIds.has(id));
    const addons = addonIds.length
      ? (await deps.db.query<{ id: string; price: string; duration_minutes: number }>(`SELECT * FROM catalog_addons WHERE id = ANY($1::uuid[])`, [addonIds])).rows
      : [];
    const addonAmount = addons.reduce((sum: number, row) => sum + Number(row.price), 0);
    const duration = await estimateCleaningDurationMinutes(deps.db, customerPackage.address_id, addons) + prepaid.reduce((sum,item)=>sum+Number(item.durationMinutes ?? 0),0);
    const end = addMinutes(String(req.body.startTime), duration);
    const initialStatus = addonAmount > 0 ? 'pending_payment' : 'pending_assignment';
    const row = await deps.db.transaction(async (tx) => {
      const reserved = first((await tx.query(
        `UPDATE customer_packages
         SET available_cleanings=available_cleanings-1, updated_at=NOW()
         WHERE id=$1 AND customer_id=$2 AND status='active' AND available_cleanings > 0
         RETURNING id,available_cleanings,total_cleanings`,
        [customerPackage.id, req.user!.id],
      )).rows);
      if (!reserved) throw new ApiError(400, 'no_cleanings_left', 'В пакете не осталось доступных уборок.');
      const created = first<{ id: string }>((await tx.query(
        `INSERT INTO service_orders
         (customer_id, customer_package_id, address_id, package_id, scheduled_date, start_time, end_time, estimated_duration_minutes, addon_amount, total_amount, payable_amount, status)
         VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$9,$9,$10) RETURNING *`,
        [req.user!.id, customerPackage.id, customerPackage.address_id, customerPackage.package_id, req.body.date, req.body.startTime, end, duration, addonAmount, initialStatus],
      )).rows);
      for (const addon of addons) {
        await tx.query(
          `INSERT INTO order_addons (order_id, addon_id, price, duration_minutes, payment_status) VALUES ($1,$2,$3,$4,'pending')`,
          [created!.id, addon.id, addon.price, addon.duration_minutes ?? 0],
        );
      }
      for (const addon of prepaid) {
        if (addon.pricingType !== 'per_visit' && (reserved as any).available_cleanings !== (reserved as any).total_cleanings - 1) continue;
        await tx.query(`INSERT INTO order_addons (order_id,addon_id,price,duration_minutes,quantity,payment_status)
          VALUES ($1,$2,$3,$4,$5,'paid')`, [created!.id,addon.id,Number(addon.price),addon.durationMinutes ?? 0,addon.quantity]);
      }
      return created;
    });
    await deps.notifications.createAdminEvent({
      event: 'new_order',
      titleRu: 'Новый заказ',
      bodyRu: `Клиент оформил заказ на ${req.body.date} ${req.body.startTime}.`,
      targetType: 'order',
      targetId: row!.id,
      dedupeKey: `order-${row!.id}`,
    });
    const offer = addonAmount > 0 ? null : await offerNextCleanerAndNotify(row!.id);
    ok(res, { order: row, offer }, 201);
  }));

  router.post('/orders/:id/pay', auth(['customer']), asyncHandler(async (req, res) => {
    const order = first<{
      id: string;
      customer_id: string;
      total_amount: string;
      payable_amount: string;
      city: string;
      settlement: string | null;
      street: string;
      house: string;
      apartment: string | null;
    }>((await deps.db.query(
      `SELECT so.*, ca.city, ca.settlement, ca.street, ca.house, ca.apartment
       FROM service_orders so
       LEFT JOIN customer_addresses ca ON ca.id=so.address_id
       WHERE so.id=$1 AND so.customer_id=$2`,
      [req.params.id, req.user!.id],
    )).rows);
    if (!order) throw new ApiError(404, 'not_found', 'Заказ не найден.');
    if (Number(order.payable_amount) <= 0) throw new ApiError(409,'already_paid','Нет услуг к оплате.');
    const result = await deps.payments.createPayment({
      customerId: req.user!.id,
      orderId: order.id,
      provider: req.body.provider ?? 'kaspi',
      amount: Number(order.payable_amount),
      useBonus: req.body.useBonus === true,
      requestedBonus: Number(req.body.requestedBonus ?? 0),
      maxBonusPercent: Number(req.body.maxBonusPercent ?? 50),
      invoicePhone: req.body.invoicePhone,
      payload: { kind: 'order_payment', mInfo: formatPaymentAddress(order) },
    });
    await deps.notifications.createAdminEvent({
      event: 'new_payment',
      titleRu: 'Новая заявка на оплату',
      bodyRu: `Клиент оплачивает заказ на сумму ${result.payableAmount} ₸.`,
      targetType: 'payment',
      targetId: (result.payment as any).id,
      dedupeKey: `payment-${(result.payment as any).id}`,
    });
    if (result.payableAmount === 0) {
      await applyPaidPayment(result.payment);
    } else {
      const provider = await initProviderPayment(deps.paymentGateway, result, req, 'Оплата заказа DOMLY');
      if (provider) await updatePaymentProviderPayload(deps.db, (result.payment as any).id, provider);
    }
    ok(res, result);
  }));

  router.post('/orders/:id/offer-next-cleaner', auth(['admin', 'superadmin']), asyncHandler(async (req, res) => {
    const offer = await offerNextCleanerAndNotify(String(req.params.id));
    ok(res, { offer });
  }));

  router.get('/cleaner/offers', auth(['cleaner']), asyncHandler(async (req, res) => {
    ok(res, await deps.scheduling.cleanerOffers(req.user!.id));
  }));

  router.get('/cleaner/orders', auth(['cleaner']), asyncHandler(async (req, res) => {
    const rows = (await deps.db.query(
      `SELECT o.*, o.id AS order_id, o.numeric_id AS order_number,
              cu.full_name AS customer_name, cu.phone AS customer_phone,
              ca.city, ca.settlement, ca.street, ca.house, ca.apartment, ca.entrance, ca.access_comment, ca.area, ca.verified_area,
              pkg.name_ru AS package_name_ru, pkg.name_kk AS package_name_kk
       FROM service_orders o
       JOIN app_users cu ON cu.id=o.customer_id
       LEFT JOIN customer_addresses ca ON ca.id=o.address_id
       LEFT JOIN catalog_packages pkg ON pkg.id=o.package_id
       WHERE o.cleaner_id=$1
       ORDER BY o.scheduled_date DESC NULLS LAST, o.start_time DESC NULLS LAST, o.created_at DESC`,
      [req.user!.id],
    )).rows;
    ok(res, rows);
  }));

  router.post('/cleaner/offers/:id/accept', auth(['cleaner']), asyncHandler(async (req, res) => {
    const row = await deps.scheduling.acceptOfferById(String(req.params.id), req.user!.id);
    await deps.notifications.create({
      userId: (row as any).customer_id,
      titleRu: 'Уборщица назначена',
      bodyRu: 'Уборщица приняла ваш заказ.',
      targetType: 'order',
      targetId: (row as any).id,
    });
    ok(res, row);
  }));

  router.post('/cleaner/offers/:id/decline', auth(['cleaner']), asyncHandler(async (req, res) => {
    const currentOffer = first<{ order_id: string }>((await deps.db.query(
      `SELECT order_id FROM order_offers WHERE id=$1 AND cleaner_id=$2`,
      [req.params.id, req.user!.id],
    )).rows);
    const nextOffer = await deps.scheduling.declineOfferById(String(req.params.id), req.user!.id);
    if (nextOffer) {
      await deps.notifications.create({
        userId: (nextOffer as any).cleaner_id,
        titleRu: 'Новый заказ',
        bodyRu: 'Вам поступил новый заказ на подтверждение.',
        targetType: 'order_offer',
        targetId: (nextOffer as any).order_id,
        dedupeKey: `order-offer-${(nextOffer as any).order_id}-${(nextOffer as any).cleaner_id}`,
      });
    } else {
      await deps.notifications.createAdminEvent({
        event: 'new_order',
        titleRu: 'Нет свободной уборщицы',
        bodyRu: 'Все доступные уборщицы отказались или заняты.',
        targetType: 'order',
        targetId: currentOffer?.order_id,
        dedupeKey: `no-cleaner-${currentOffer?.order_id ?? req.params.id}`,
      });
    }
    ok(res, { nextOffer });
  }));

  router.post('/orders/:id/offers/accept', auth(['cleaner']), asyncHandler(async (req, res) => {
    const row = await deps.scheduling.acceptOffer(String(req.params.id), req.user!.id);
    await deps.notifications.create({
      userId: (row as any).customer_id,
      titleRu: 'Уборщица назначена',
      bodyRu: 'Уборщица приняла ваш заказ.',
      targetType: 'order',
      targetId: String(req.params.id),
    });
    ok(res, row);
  }));

  router.post('/orders/:id/offers/decline', auth(['cleaner']), asyncHandler(async (req, res) => {
    const nextOffer = await deps.scheduling.declineOffer(String(req.params.id), req.user!.id);
    if (nextOffer) {
      await deps.notifications.create({
        userId: (nextOffer as any).cleaner_id,
        titleRu: 'Новый заказ',
        bodyRu: 'Вам поступил новый заказ на подтверждение.',
        targetType: 'order_offer',
        targetId: String(req.params.id),
        dedupeKey: `order-offer-${String(req.params.id)}-${(nextOffer as any).cleaner_id}`,
      });
    } else {
      await deps.notifications.createAdminEvent({
        event: 'new_order',
        titleRu: 'Нет свободной уборщицы',
        bodyRu: 'Все доступные уборщицы отказались или заняты.',
        targetType: 'order',
        targetId: String(req.params.id),
        dedupeKey: `no-cleaner-${String(req.params.id)}`,
      });
    }
    ok(res, { nextOffer });
  }));

  router.get('/orders', auth(), asyncHandler(async (req, res) => {
    const where = req.user!.role === 'cleaner' ? 'o.cleaner_id=$1' : 'o.customer_id=$1';
    ok(res, (await deps.db.query(
      `SELECT o.*, p.name_ru AS package_name_ru, p.name_kk AS package_name_kk,
              ca.city, ca.settlement, ca.street, ca.house, ca.apartment, ca.entrance, ca.area,
              cu.full_name AS customer_name, cu.phone AS customer_phone,
              cl.full_name AS cleaner_name, cl.phone AS cleaner_phone,
              COALESCE((SELECT json_agg(json_build_object('id',a.id,'key',a.id,'label',a.title_ru,'quantity',oa.quantity,
                'price',oa.price,'durationMinutes',oa.duration_minutes,'paymentStatus',oa.payment_status))
                FROM order_addons oa JOIN catalog_addons a ON a.id=oa.addon_id WHERE oa.order_id=o.id),'[]'::json) AS addons
       FROM service_orders o
       LEFT JOIN catalog_packages p ON p.id=o.package_id
       LEFT JOIN customer_addresses ca ON ca.id=o.address_id
       LEFT JOIN app_users cu ON cu.id=o.customer_id
       LEFT JOIN app_users cl ON cl.id=o.cleaner_id
       WHERE ${where}
       ORDER BY o.created_at DESC`,
      [req.user!.id],
    )).rows);
  }));

  router.get('/orders/:id/details', auth(), asyncHandler(async (req, res) => {
    const isAdmin = req.user!.role === 'admin' || req.user!.role === 'superadmin';
    const order = first((await deps.db.query(
      `SELECT o.*, p.name_ru AS package_name_ru, p.name_kk AS package_name_kk,
              ca.city, ca.settlement, ca.street, ca.house, ca.apartment, ca.entrance, ca.area,
              cu.full_name AS customer_name, cu.phone AS customer_phone,
              cl.full_name AS cleaner_name, cl.phone AS cleaner_phone
       FROM service_orders o
       LEFT JOIN catalog_packages p ON p.id=o.package_id
       LEFT JOIN customer_addresses ca ON ca.id=o.address_id
       LEFT JOIN app_users cu ON cu.id=o.customer_id
       LEFT JOIN app_users cl ON cl.id=o.cleaner_id
       WHERE o.id=$1 AND ($2::boolean OR o.customer_id=$3 OR o.cleaner_id=$3)`,
      [req.params.id, isAdmin, req.user!.id],
    )).rows);
    if (!order) throw new ApiError(404, 'not_found', 'Заказ не найден.');
    const addons = (await deps.db.query(
      `SELECT oa.*, a.title_ru, a.title_kk, a.description_ru, a.description_kk, a.paid_separately
       FROM order_addons oa
       JOIN catalog_addons a ON a.id=oa.addon_id
       WHERE oa.order_id=$1
       ORDER BY oa.created_at ASC`,
      [req.params.id],
    )).rows;
    const payments = (await deps.db.query(
      `SELECT * FROM payments WHERE order_id=$1 ORDER BY created_at DESC`,
      [req.params.id],
    )).rows;
    ok(res, { order, addons, payments });
  }));

  const cancelOrder = async (req: any, res: any) => {
    const previous = await getVisibleOrder(deps.db, String(req.params.id), req.user!);
    const order = first<{ id: string; customer_id: string; cleaner_id: string | null; customer_package_id: string | null; bonus_spent: string }>((await deps.db.query(
      `UPDATE service_orders SET status='cancelled', cancelled_by=$2, cancellation_reason=$3, updated_at=NOW()
       WHERE id=$1 AND status NOT IN ('completed','cancelled') RETURNING *`,
      [req.params.id, req.user!.id, req.body.reason ?? null],
    )).rows);
    if (!order) throw new ApiError(404, 'not_found', 'Заказ не найден или уже отменён.');
    await deps.db.query(`INSERT INTO order_status_history(order_id,old_status,new_status,actor_id,comment) VALUES($1,$2,'cancelled',$3,$4)`, [order.id,(previous as any).status,req.user!.id,req.body.reason ?? null]);
    if (order.customer_package_id) {
      await deps.db.query(
        `UPDATE customer_packages SET available_cleanings=available_cleanings+1, updated_at=NOW() WHERE id=$1`,
        [order.customer_package_id],
      );
    }
    await deps.db.query(`UPDATE order_addons SET payment_status='cancelled' WHERE order_id=$1`, [order.id]);
    await deps.db.query(`UPDATE order_offers SET status='expired' WHERE order_id=$1 AND status='offered'`, [order.id]);
    const refundedPayments = await deps.payments.refundOrderPayments(order.id, 'Возврат за отменённый заказ');
    if (refundedPayments.length === 0 && Number(order.bonus_spent) > 0) {
      await deps.bonuses.refund(order.customer_id, Number(order.bonus_spent), 'Возврат бонусов за отменённый заказ', order.id);
    }
    await deps.notifications.create({
      userId: order.customer_id,
      titleRu: 'Заказ отменён',
      bodyRu: 'Заказ отменён. Бонусы и доп. услуги обновлены.',
      targetType: 'order',
      targetId: order.id,
      dedupeKey: `order-cancelled-${order.id}-customer`,
    });
    if (order.cleaner_id) {
      await deps.notifications.create({
        userId: order.cleaner_id,
        titleRu: 'Заказ отменён',
        bodyRu: 'Клиент или админ отменил заказ.',
        targetType: 'order',
        targetId: order.id,
        dedupeKey: `order-cancelled-${order.id}-cleaner`,
      });
    }
    await deps.notifications.createAdminEvent({
      event: 'new_order',
      titleRu: 'Заказ отменён',
      bodyRu: 'Проверьте платежи и возвраты по отменённому заказу.',
      targetType: 'order',
      targetId: order.id,
      dedupeKey: `order-cancelled-${order.id}-admin`,
    });
    ok(res, { order, refundedPayments });
  };
  router.post('/orders/:id/cancel', auth(['customer','admin','superadmin']), asyncHandler(cancelOrder));

  router.post('/orders/:id/confirm-start', auth(['customer']), asyncHandler(async (req, res) => {
    const order = await transitionOrder(deps.db, deps.notifications, String(req.params.id), req.user!, req.body.confirmed === true ? 'confirm_start' : 'reject_start');
    ok(res, { ok: true, orderId: order.id, confirmed: req.body.confirmed === true, order });
  }));

  router.get('/orders/:id/checklist', auth(), asyncHandler(async (req, res) => {
    const order = await getVisibleOrder(deps.db, String(req.params.id), req.user!);
    const report = await ensureChecklistReport(deps.db, order);
    const items = (await deps.db.query(
      `SELECT * FROM checklist_report_items WHERE report_id=$1 ORDER BY created_at ASC, id ASC`,
      [(report as any).id],
    )).rows;
    ok(res, { report, items });
  }));

  router.post('/orders/:id/checklist', auth(['cleaner', 'admin', 'superadmin']), asyncHandler(async (req, res) => {
    const order = await getVisibleOrder(deps.db, String(req.params.id), req.user!);
    if (req.user!.role === 'cleaner' && (order as any).cleaner_id !== req.user!.id) {
      throw new ApiError(403, 'forbidden', 'Нет доступа к этому заказу.');
    }
    const report = await ensureChecklistReport(deps.db, order);
    const titles = [
      ...(Array.isArray(req.body.completedTasks) ? req.body.completedTasks.map(String) : []),
      ...(Array.isArray(req.body.orderedAddons) ? req.body.orderedAddons.map(String) : []),
      ...(Array.isArray(req.body.addons) ? req.body.addons.map(String) : []),
    ].map((item) => item.trim()).filter(Boolean);
    await deps.db.query(`DELETE FROM checklist_report_items WHERE report_id=$1`, [(report as any).id]);
    for (const title of titles) {
      await deps.db.query(
        `INSERT INTO checklist_report_items (report_id, title_ru, checked, checked_at)
         VALUES ($1,$2,TRUE,NOW())`,
        [(report as any).id, title],
      );
    }
    const updated = first((await deps.db.query(
      `UPDATE checklist_reports SET status='completed', cleaner_id=COALESCE($2, cleaner_id), updated_at=NOW()
       WHERE id=$1 RETURNING *`,
      [(report as any).id, req.user!.id],
    )).rows);
    await deps.notifications.create({
      userId: (order as any).customer_id,
      titleRu: 'Чек-лист уборки заполнен',
      bodyRu: 'Уборщица отметила выполненные пункты по заказу.',
      targetType: 'checklist',
      targetId: String(req.params.id),
      dedupeKey: `checklist-saved-${req.params.id}-${Date.now()}`,
    });
    ok(res, { report: updated, items: titles });
  }));

  router.patch('/orders/:id/checklist/items/:itemId', auth(['cleaner', 'admin', 'superadmin']), asyncHandler(async (req, res) => {
    const order = await getVisibleOrder(deps.db, String(req.params.id), req.user!);
    if (req.user!.role === 'cleaner' && (order as any).cleaner_id !== req.user!.id) {
      throw new ApiError(403, 'forbidden', 'Этот чек-лист доступен только назначенной уборщице.');
    }
    const row = first((await deps.db.query(
      `UPDATE checklist_report_items i SET checked=$3, checked_at=CASE WHEN $3 THEN NOW() ELSE NULL END
       FROM checklist_reports r
       WHERE i.report_id=r.id AND r.order_id=$1 AND i.id=$2
       RETURNING i.*`,
      [req.params.id, req.params.itemId, req.body.checked === true],
    )).rows);
    if (!row) throw new ApiError(404, 'not_found', 'Пункт чек-листа не найден.');
    await deps.notifications.create({
      userId: (order as any).customer_id,
      titleRu: 'Чек-лист обновлён',
      bodyRu: 'Уборщица обновила чек-лист по заказу.',
      targetType: 'checklist',
      targetId: String(req.params.id),
    });
    ok(res, row);
  }));

  router.get('/orders/:id/photo-report', auth(), asyncHandler(async (req, res) => {
    const order = await getVisibleOrder(deps.db, String(req.params.id), req.user!);
    const row = first((await deps.db.query(
      `SELECT pr.*, u.full_name AS cleaner_name, u.phone AS cleaner_phone
       FROM photo_reports pr
       LEFT JOIN app_users u ON u.id=pr.cleaner_id
       WHERE pr.order_id=$1`,
      [req.params.id],
    )).rows);
    const anyOrder = order as any;
    const canSubmit = anyOrder.status === 'in_progress'
      && (!anyOrder.start_requires_customer_confirmation || anyOrder.cleaning_start_confirmed === true);
    ok(res, { report: row ?? null, canSubmit });
  }));

  router.post('/orders/:id/photo-report', auth(['cleaner', 'admin', 'superadmin']), asyncHandler(async (req, res) => {
    const order = await getVisibleOrder(deps.db, String(req.params.id), req.user!);
    const anyOrder = order as any;
    if (req.user!.role === 'cleaner' && anyOrder.cleaner_id !== req.user!.id) {
      throw new ApiError(403, 'forbidden', 'Фотоотчёт может отправить только назначенная уборщица.');
    }
    if (anyOrder.status !== 'in_progress') throw new ApiError(409, 'start_not_confirmed', 'Сначала клиент должен подтвердить начало уборки.');
    const photoUrls = Array.isArray(req.body.photoUrls)
      ? req.body.photoUrls.map(String).map((item: string) => item.trim()).filter(Boolean).slice(0, 10)
      : [];
    if (photoUrls.length < 3) {
      throw new ApiError(400, 'photos_required', 'Добавьте минимум 3 фото для отчёта.');
    }
    const row = first((await deps.db.query(
      `INSERT INTO photo_reports (order_id, cleaner_id, photo_urls)
       VALUES ($1,$2,$3)
       ON CONFLICT (order_id) DO UPDATE SET
         cleaner_id=EXCLUDED.cleaner_id,
         photo_urls=EXCLUDED.photo_urls,
         updated_at=NOW()
       RETURNING *`,
      [req.params.id, anyOrder.cleaner_id ?? req.user!.id, JSON.stringify(photoUrls)],
    )).rows);
    await deps.notifications.create({
      userId: anyOrder.customer_id,
      titleRu: 'Фотоотчёт загружен',
      titleKk: 'Фотоесеп жүктелді',
      bodyRu: 'Уборщица отправила фотоотчёт по уборке.',
      bodyKk: 'Тазалаушы жинау бойынша фотоесеп жіберді.',
      targetType: 'photo_report',
      targetId: String(req.params.id),
      dedupeKey: `photo-report-${req.params.id}-${Date.now()}`,
    });
    ok(res, row, 201);
  }));

  const changeOrderStatus = async (req: any, res: any) => {
    const order = await getVisibleOrder(deps.db, String(req.params.id), req.user!);
    const nextStatus = req.body.status === 'canceled' ? 'cancelled' : String(req.body.status ?? '');
    const allowed = ['assigned', 'in_progress', 'completed', 'cancelled'];
    if (!allowed.includes(nextStatus)) throw new ApiError(400, 'invalid_status', 'Недопустимый статус заказа.');
    if (req.user!.role === 'cleaner' && (order as any).cleaner_id !== req.user!.id) {
      throw new ApiError(403, 'forbidden', 'Этот заказ назначен другой уборщице.');
    }
    if (nextStatus === 'assigned' && !['pending_assignment', 'waiting_cleaner', 'assigned'].includes((order as any).status)) throw new ApiError(409, 'invalid_transition', 'Этот заказ нельзя назначить повторно.');
    if (nextStatus === 'assigned') {
      if ((order as any).status === 'assigned' && (!req.body.cleanerId || req.body.cleanerId === (order as any).cleaner_id)) { ok(res, order); return; }
      const cleanerId = req.body.cleanerId ?? (order as any).cleaner_id;
      if (req.user!.role === 'cleaner' && cleanerId !== req.user!.id) throw new ApiError(403,'forbidden','Нельзя назначить заказ другой уборщице.');
      if (!cleanerId) throw new ApiError(400, 'cleaner_required', 'Выберите уборщицу для назначения заказа.');
      if (cleanerId !== (order as any).cleaner_id) {
        const free = await deps.scheduling.cleanerAvailable(cleanerId, (order as any).scheduled_date, (order as any).start_time, (order as any).end_time);
        if (!free) throw new ApiError(400, 'cleaner_unavailable', 'Уборщица занята на это время. Выберите другую.');
      }
      const row = first((await deps.db.query(
        `UPDATE service_orders SET cleaner_id=$2, status='assigned', updated_at=NOW() WHERE id=$1 AND status IN ('pending_assignment','waiting_cleaner','assigned') RETURNING *`,
        [req.params.id, cleanerId],
      )).rows);
      if (!row) throw new ApiError(409,'invalid_transition','Статус заказа уже изменился. Обновите страницу.');
      await deps.db.query(
        `INSERT INTO order_status_history (order_id, old_status, new_status, actor_id, comment)
         VALUES ($1,$2,'assigned',$3,$4)`,
        [req.params.id, (order as any).status, req.user!.id, req.body.comment ?? null],
      );
      await deps.notifications.create({
        userId: cleanerId,
        titleRu: 'Назначен заказ',
        bodyRu: 'Вам назначен новый заказ.',
        targetType: 'order',
        targetId: String(req.params.id),
      });
      await deps.notifications.create({userId: (order as any).customer_id, titleRu:'Уборщица назначена', bodyRu:'Уборщица назначена на ваш заказ.', targetType:'order', targetId:String(req.params.id)});
      ok(res, row);
      return;
    }
    if (nextStatus === 'cancelled' && req.user!.role === 'cleaner') {
      const released = await releaseCleanerAssignment(deps.db,deps.notifications,String(req.params.id),req.user!.id);
      const declined = (await deps.db.query<{cleaner_id:string}>(`SELECT cleaner_id FROM order_offers WHERE order_id=$1 AND status IN ('declined','expired')`,[req.params.id])).rows.map(row=>row.cleaner_id);
      const offer = await offerNextCleanerAndNotify(String(req.params.id),[...new Set([req.user!.id,...declined])]);
      if (!offer) await deps.notifications.createAdminEvent({event:'new_order',titleRu:'Требуется другая уборщица',bodyRu:'Уборщица отказалась от назначения. Подберите замену.',targetType:'order',targetId:String(req.params.id)});
      ok(res, {order:released,nextOffer:offer});
      return;
    }
    if (nextStatus === 'cancelled') {
      req.body.reason = req.body.reason ?? req.body.comment;
      await cancelOrder(req, res);
      return;
    }
    const row = await transitionOrder(deps.db, deps.notifications, String(req.params.id), req.user!, nextStatus);
    ok(res, row);
  };
  router.post('/orders/:id/status', auth(['cleaner', 'admin', 'superadmin']), asyncHandler(changeOrderStatus));

  router.post('/orders/:id/reschedule', auth(['customer', 'admin', 'superadmin']), asyncHandler(async (req, res) => {
    const admin = ['admin', 'superadmin'].includes(req.user!.role);
    const order = first<any>((await deps.db.query(
      `SELECT * FROM service_orders WHERE id=$1 AND ($2::boolean=TRUE OR customer_id=$3)`,
      [req.params.id, admin, req.user!.id],
    )).rows);
    if (!order) throw new ApiError(404, 'not_found', 'Заказ не найден.');
    if (!['pending_assignment', 'waiting_cleaner', 'assigned', 'pending_payment'].includes(order.status)) throw new ApiError(409, 'invalid_transition', 'Этот заказ уже нельзя перенести.');
    const date = req.body.date ?? req.body.scheduledDate ?? order.scheduled_date;
    const startTime = req.body.time ?? req.body.startTime ?? order.start_time;
    if (!date || !startTime) throw new ApiError(400, 'invalid_request', 'Выберите дату и время уборки.');
    const duration = Number(order.estimated_duration_minutes ?? 0) > 0
      ? Number(order.estimated_duration_minutes)
      : await estimateCleaningDurationMinutes(deps.db, order.address_id, []);
    const endTime = addMinutes(String(startTime), duration);
    if (order.cleaner_id) {
      const free = await deps.scheduling.cleanerAvailable(order.cleaner_id, String(date), String(startTime), endTime, order.id);
      if (!free) throw new ApiError(400, 'cleaner_unavailable', 'Уборщица занята на это время. Выберите другое время.');
    }
    const row = first((await deps.db.query(
      `UPDATE service_orders
       SET scheduled_date=$2, start_time=$3, end_time=$4, updated_at=NOW()
       WHERE id=$1 AND status IN ('pending_assignment','waiting_cleaner','assigned','pending_payment')
       RETURNING *`,
      [req.params.id, date, startTime, endTime],
    )).rows);
    if (!row) throw new ApiError(409,'invalid_transition','Статус заказа уже изменился. Обновите страницу.');
    await deps.db.query(
      `INSERT INTO order_status_history (order_id, old_status, new_status, actor_id, comment)
       VALUES ($1,$2,$2,$3,$4)`,
      [req.params.id, order.status, req.user!.id, req.body.comment ?? 'Дата и время уборки изменены'],
    );
    await deps.notifications.create({userId:order.customer_id,titleRu:'Время уборки изменено',bodyRu:'Дата или время вашего заказа изменены.',targetType:'order',targetId:String(req.params.id)});
    if (order.cleaner_id) {
      await deps.notifications.create({
        userId: order.cleaner_id,
        titleRu: 'Время уборки изменено',
        bodyRu: 'Клиент изменил дату или время уборки.',
        targetType: 'order',
        targetId: String(req.params.id),
        dedupeKey: `order-rescheduled-${req.params.id}-${Date.now()}`,
      });
    }
    ok(res, row);
  }));

  router.post('/orders/:id/notify', auth(['customer', 'cleaner', 'admin', 'superadmin']), asyncHandler(async (req, res) => {
    const target = String(req.body.target ?? '').trim();
    if (!['customer', 'cleaner'].includes(target)) throw new ApiError(400, 'invalid_target', 'Укажите получателя уведомления.');
    const order = first<{ id: string; customer_id: string; cleaner_id: string | null; numeric_id: number }>((await deps.db.query(
      `SELECT id, customer_id, cleaner_id, numeric_id FROM service_orders WHERE id=$1`,
      [req.params.id],
    )).rows);
    if (!order) throw new ApiError(404, 'not_found', 'Заказ не найден.');
    if (req.user!.role === 'customer' && order.customer_id !== req.user!.id) throw new ApiError(403, 'forbidden', 'Нет доступа к заказу.');
    if (req.user!.role === 'cleaner' && order.cleaner_id !== req.user!.id) throw new ApiError(403, 'forbidden', 'Нет доступа к заказу.');
    const targetUserId = target === 'customer' ? order.customer_id : order.cleaner_id;
    if (!targetUserId) throw new ApiError(400, 'target_not_assigned', 'Получатель ещё не назначен.');
    const type = String(req.body.type ?? 'order_update');
    const notification = await deps.notifications.create({
      userId: targetUserId,
      titleRu: String(req.body.titleRu ?? 'Изменение по заказу'),
      titleKk: req.body.titleKk ?? null,
      bodyRu: String(req.body.bodyRu ?? `Заказ №${order.numeric_id} обновлён.`),
      bodyKk: req.body.bodyKk ?? null,
      targetType: type,
      targetId: order.id,
      dedupeKey: req.body.dedupeKey ?? `${type}-${order.id}-${Date.now()}`,
    });
    ok(res, { orderId: order.id, notification });
  }));

  router.post('/orders/:id/addon-requests', auth(['cleaner', 'admin', 'superadmin']), asyncHandler(async (req, res) => {
    const order = first<{ id: string; cleaner_id: string | null; customer_id: string; numeric_id: number }>((await deps.db.query(
      `SELECT id, cleaner_id, customer_id, numeric_id FROM service_orders WHERE id=$1`,
      [req.params.id],
    )).rows);
    if (!order) throw new ApiError(404, 'not_found', 'Заказ не найден.');
    if (req.user!.role === 'cleaner' && order.cleaner_id !== req.user!.id) throw new ApiError(403, 'forbidden', 'Нет доступа к заказу.');
    const addons = Array.isArray(req.body.addonsDetailed) ? req.body.addonsDetailed : [];
    if (!addons.length) throw new ApiError(400, 'invalid_request', 'Выберите доп. услуги.');
    const saved = [];
    for (const item of addons) {
      const addonId = String(item.addonId ?? item.id ?? '').trim();
      if (!addonId) continue;
      const addon = first<{ id: string; price: string; duration_minutes: number }>((await deps.db.query(
        `SELECT id, price, duration_minutes FROM catalog_addons WHERE id=$1`,
        [addonId],
      )).rows);
      if (!addon) continue;
      const row = first((await deps.db.query(
        `INSERT INTO order_addons (order_id, addon_id, quantity, price, duration_minutes, payment_status)
         VALUES ($1,$2,$3,$4,$5,'pending') RETURNING *`,
        [order.id, addon.id, Number(item.quantity ?? 1), Number(item.price ?? addon.price ?? 0), Number(item.durationMinutes ?? addon.duration_minutes ?? 0)],
      )).rows);
      saved.push(row);
    }
    await deps.notifications.create({
      userId: order.customer_id,
      titleRu: 'Уборщица предложила доп. услуги',
      bodyRu: `По заказу №${order.numeric_id} добавлены доп. услуги на подтверждение.`,
      targetType: 'addon_request',
      targetId: order.id,
      dedupeKey: `addon-request-${order.id}-${Date.now()}`,
    });
    ok(res, { requestId: order.id, orderId: order.id, addons: saved }, 201);
  }));

  router.post('/orders/:id/addon-requests/approve', auth(['customer', 'admin', 'superadmin']), asyncHandler(async (req, res) => {
    const admin = ['admin', 'superadmin'].includes(req.user!.role);
    const order = first<{ id: string; customer_id: string; payable_amount: string; total_amount: string }>((await deps.db.query(
      `SELECT id, customer_id, payable_amount, total_amount FROM service_orders WHERE id=$1 AND ($2::boolean=TRUE OR customer_id=$3)`,
      [req.params.id, admin, req.user!.id],
    )).rows);
    if (!order) throw new ApiError(404, 'not_found', 'Заказ не найден.');
    const addonTotal = first<{ amount: string }>((await deps.db.query(
      `SELECT COALESCE(SUM(price * quantity),0)::text AS amount FROM order_addons WHERE order_id=$1 AND payment_status='pending'`,
      [order.id],
    )).rows);
    const amount = Number(addonTotal?.amount ?? 0);
    if (!Number.isFinite(amount) || amount <= 0) throw new ApiError(400, 'invalid_amount', 'Нет доп. услуг к оплате.');
    const payment = await deps.payments.createPayment({
      customerId: order.customer_id,
      orderId: order.id,
      provider: req.body.paymentMethod === 'online' ? 'bcc' : 'kaspi',
      amount,
      useBonus: Boolean(req.body.bonusToSpend && Number(req.body.bonusToSpend) > 0),
      requestedBonus: Number(req.body.bonusToSpend ?? 0),
      maxBonusPercent: Number(req.body.maxBonusPercent ?? 50),
      invoicePhone: req.body.kaspiPhone ?? null,
      payload: { kind: 'addon_request_payment' },
    });
    ok(res, { requestId: req.params.id, paymentId: (payment as any).payment.id, ...payment });
  }));

  router.post('/orders/:id/addon-requests/reject', auth(['customer', 'admin', 'superadmin']), asyncHandler(async (req, res) => {
    await deps.db.query(`DELETE FROM order_addons WHERE order_id=$1 AND payment_status='pending'`, [req.params.id]);
    ok(res, { requestId: req.params.id, rejected: true });
  }));

  router.get('/addon-requests', auth(), asyncHandler(async (req, res) => {
    const values: unknown[] = [];
    const filters: string[] = [];
    if (req.user!.role === 'customer') {
      values.push(req.user!.id);
      filters.push(`o.customer_id=$${values.length}`);
    } else if (req.user!.role === 'cleaner') {
      values.push(req.user!.id);
      filters.push(`o.cleaner_id=$${values.length}`);
    } else if (req.query.orderId) {
      values.push(String(req.query.orderId));
      filters.push(`o.id=$${values.length}`);
    }
    if (req.query.status) {
      values.push(String(req.query.status));
      filters.push(`oa.payment_status=$${values.length}`);
    }
    const where = filters.length ? `WHERE ${filters.join(' AND ')}` : '';
    const rows = (await deps.db.query(
      `SELECT oa.*, oa.payment_status AS status, o.id AS order_id, o.customer_id, o.cleaner_id, o.scheduled_date, o.start_time, o.end_time,
              ca.title_ru AS addon_title_ru, ca.title_kk AS addon_title_kk,
              cu.full_name AS customer_name, cu.phone AS customer_phone,
              cl.full_name AS cleaner_name, cl.phone AS cleaner_phone
       FROM order_addons oa
       JOIN service_orders o ON o.id=oa.order_id
       JOIN catalog_addons ca ON ca.id=oa.addon_id
       JOIN app_users cu ON cu.id=o.customer_id
       LEFT JOIN app_users cl ON cl.id=o.cleaner_id
       ${where}
       ORDER BY oa.created_at DESC`,
      values,
    )).rows;
    ok(res, rows);
  }));

  router.get('/scheduling/available-slots', auth(), asyncHandler(async (req, res) => {
    const date = String(req.query.date);
    const settings = await readAppSettings(deps.db);
    const slots = Array.isArray(settings.slotStartTimes) ? settings.slotStartTimes.map(String) : ['08:00', '10:00', '12:00', '14:00', '16:00'];
    const addonIds = String(req.query.addonIds ?? '').split(',').map((id) => id.trim()).filter(Boolean);
    const addons = addonIds.length
      ? (await deps.db.query<{ duration_minutes: number }>(`SELECT duration_minutes FROM catalog_addons WHERE id = ANY($1::uuid[])`, [addonIds])).rows
      : [];
    const duration = Number(req.query.durationMinutes ?? 0) > 0
      ? Number(req.query.durationMinutes)
      : await estimateCleaningDurationMinutes(deps.db, req.query.addressId ? String(req.query.addressId) : undefined, addons);
    const available = [];
    for (const start of slots) {
      const end = addMinutes(start, duration);
      const cleaners = await deps.scheduling.availableCleaners(date, start, end, req.query.zoneId ? String(req.query.zoneId) : undefined);
      if (cleaners.length > 0) available.push({ startTime: start, endTime: end, cleanersCount: cleaners.length, durationMinutes: duration });
    }
    ok(res, available);
  }));

  router.get('/payouts', auth(['cleaner']), asyncHandler(async (req, res) => {
    ok(res, (await deps.db.query(`SELECT * FROM payouts WHERE cleaner_id=$1 ORDER BY created_at DESC`, [req.user!.id])).rows);
  }));

  router.post('/payouts', auth(['cleaner']), asyncHandler(async (req, res) => {
    const payoutType = String(req.body.payoutType ?? 'manual').trim() || 'manual';
    const balance = first<{ balance: string }>((await deps.db.query(
      `SELECT COALESCE(SUM(total_amount),0)::text AS balance
       FROM service_orders
       WHERE cleaner_id=$1 AND status='completed'`,
      [req.user!.id],
    )).rows);
    const pending = first<{ amount: string }>((await deps.db.query(
      `SELECT COALESCE(SUM(amount),0)::text AS amount FROM payouts WHERE cleaner_id=$1 AND status IN ('requested','approved')`,
      [req.user!.id],
    )).rows);
    const available = Number(balance?.balance ?? 0) - Number(pending?.amount ?? 0);
    const requested = req.body.amount == null || req.body.amount === '' ? available : Number(req.body.amount);
    const amount = Math.min(requested, available);
    if (!Number.isFinite(amount) || amount <= 0) throw new ApiError(400, 'invalid_amount', `Доступно к выводу ${Math.max(available, 0)} ₸.`);
    if (amount > available) throw new ApiError(400, 'insufficient_balance', `Доступно к выводу ${available} ₸.`);
    const row = first((await deps.db.query(
      `INSERT INTO payouts (cleaner_id, amount, payout_type, kaspi_phone, status) VALUES ($1,$2,$3,$4,'requested') RETURNING *`,
      [req.user!.id, amount, payoutType, req.body.kaspiPhone ?? null],
    )).rows);
    await deps.notifications.createAdminEvent({
      event: 'payout',
      titleRu: 'Новая заявка на выплату',
      bodyRu: `Уборщица запросила выплату ${amount} ₸.`,
      targetType: 'payout',
      targetId: (row as any).id,
      dedupeKey: `payout-${(row as any).id}`,
    });
    ok(res, row, 201);
  }));

  router.post('/admin/payouts', auth(['admin', 'superadmin']), asyncHandler(async (req, res) => {
    const cleanerId = String(req.body.cleanerId ?? '').trim();
    if (!cleanerId) throw new ApiError(400, 'cleaner_required', 'Выберите уборщицу.');
    const amount = Number(req.body.amount ?? 0);
    const payoutType = String(req.body.payoutType ?? 'weekly');
    const row = first((await deps.db.query(
      `INSERT INTO payouts (cleaner_id, amount, payout_type, kaspi_phone, status)
       VALUES ($1,$2,$3,$4,'requested') RETURNING *`,
      [cleanerId, Number.isFinite(amount) ? amount : 0, payoutType, req.body.kaspiPhone ?? null],
    )).rows);
    await deps.notifications.createAdminEvent({
      event: 'payout',
      titleRu: 'Создана заявка на выплату',
      bodyRu: 'Админ создал заявку на выплату уборщице.',
      targetType: 'payout',
      targetId: (row as any).id,
      dedupeKey: `admin-payout-${(row as any).id}`,
    });
    ok(res, row, 201);
  }));

  router.patch('/admin/payouts/:id', auth(['admin', 'superadmin']), asyncHandler(async (req, res) => {
    const status = String(req.body.status ?? '');
    if (!['requested', 'approved', 'paid', 'rejected'].includes(status)) {
      throw new ApiError(400, 'invalid_status', 'Недопустимый статус выплаты.');
    }
    const row = first((await deps.db.query(
      `UPDATE payouts SET status=$2, updated_at=NOW() WHERE id=$1 RETURNING *`,
      [req.params.id, status],
    )).rows);
    if (!row) throw new ApiError(404, 'not_found', 'Заявка на выплату не найдена.');
    ok(res, row);
  }));

  router.get('/admin/payouts/:id/details', auth(['admin', 'superadmin']), asyncHandler(async (req, res) => {
    const payout = first((await deps.db.query(
      `SELECT p.*, u.numeric_id AS cleaner_number, u.full_name AS cleaner_name, u.phone AS cleaner_phone,
              u.email AS cleaner_email, u.rating AS cleaner_rating, cp.city, cp.registration_status,
              cp.verification_status, cp.monthly_area_limit, cp.daily_work_limit_minutes, cp.verified_at
       FROM payouts p
       JOIN app_users u ON u.id=p.cleaner_id
       LEFT JOIN cleaner_profiles cp ON cp.user_id=u.id
       WHERE p.id=$1`,
      [req.params.id],
    )).rows);
    if (!payout) throw new ApiError(404, 'not_found', 'Заявка на выплату не найдена.');
    const zones = (await deps.db.query(
      `SELECT z.city, z.name_ru, z.name_kk
       FROM cleaner_zones cz
       JOIN service_zones z ON z.id=cz.zone_id
       WHERE cz.cleaner_id=$1
       ORDER BY z.city, z.name_ru`,
      [(payout as any).cleaner_id],
    )).rows;
    const orders = (await deps.db.query(
      `SELECT o.numeric_id, o.scheduled_date, o.start_time, o.end_time, o.status, o.total_amount,
              cu.full_name AS customer_name, cu.phone AS customer_phone
       FROM service_orders o
       LEFT JOIN app_users cu ON cu.id=o.customer_id
       WHERE o.cleaner_id=$1
       ORDER BY o.scheduled_date DESC, o.start_time DESC LIMIT 100`,
      [(payout as any).cleaner_id],
    )).rows;
    const payoutHistory = (await deps.db.query(
      `SELECT * FROM payouts WHERE cleaner_id=$1 ORDER BY created_at DESC LIMIT 50`,
      [(payout as any).cleaner_id],
    )).rows;
    ok(res, { payout, zones, orders, payoutHistory });
  }));

  router.post('/admin/orders/:id/assign-cleaner', auth(['admin', 'superadmin']), asyncHandler(async (req, res) => {
    req.body.status = 'assigned';
    await changeOrderStatus(req, res);
  }));

  router.patch('/admin/orders/:id', auth(['admin', 'superadmin']), asyncHandler(async (req, res) => {
    const status = req.body.status ?? req.body.orderStatus;
    if (status != null) {
      if (Object.keys(req.body).some(key => !['status','orderStatus','comment','reason','cleanerId'].includes(key))) throw new ApiError(400,'mixed_update','Изменяйте статус отдельно от других полей заказа.');
      req.body.status = status;
      await changeOrderStatus(req, res);
      return;
    }
    const allowed: Record<string, string> = {
      status: 'status',
      orderStatus: 'status',
      paymentStatus: 'payment_status',
      cleanerId: 'cleaner_id',
      scheduledDate: 'scheduled_date',
      startTime: 'start_time',
      endTime: 'end_time',
      totalAmount: 'total_amount',
      payableAmount: 'payable_amount',
    };
    const updates: string[] = [];
    const values: unknown[] = [req.params.id];
    for (const [key, column] of Object.entries(allowed)) {
      if (Object.prototype.hasOwnProperty.call(req.body, key)) {
        values.push(req.body[key]);
        updates.push(`${column}=$${values.length}`);
      }
    }
    if (!updates.length) throw new ApiError(400, 'empty_update', 'Нет данных для обновления заказа.');
    values.push(new Date());
    const row = first((await deps.db.query(
      `UPDATE service_orders SET ${updates.join(', ')}, updated_at=$${values.length} WHERE id=$1 RETURNING *`,
      values,
    )).rows);
    if (!row) throw new ApiError(404, 'not_found', 'Заказ не найден. Обновите страницу.');
    await recordAudit('order.updated', 'order', String(req.params.id), { fields: Object.keys(req.body) }, req.user?.id);
    ok(res, row);
  }));

  router.post('/payments/:id/confirm', auth(['admin', 'superadmin']), asyncHandler(async (req, res) => {
    const payment = await deps.payments.markPaid(String(req.params.id));
    if (!payment) throw new ApiError(404, 'not_found', 'Платёж не найден.');
    await recordAudit('payment.confirmed', 'payment', String(req.params.id), { source: 'admin' }, req.user?.id);
    ok(res, await applyPaidPayment(payment));
  }));

  router.post('/payments/:id/reject', auth(['admin', 'superadmin']), asyncHandler(async (req, res) => {
    const payment = first((await deps.db.query(
      `UPDATE payments SET status='failed', payload=payload || $2::jsonb, updated_at=NOW()
       WHERE id=$1 AND status NOT IN ('paid','refunded','cancelled')
       RETURNING *`,
      [req.params.id, { note: req.body.note ?? null }],
    )).rows);
    if (!payment) throw new ApiError(404, 'not_found', 'Платёж не найден или уже обработан.');
    await recordAudit('payment.rejected', 'payment', String(req.params.id), { note: req.body.note ?? null }, req.user?.id);
    ok(res, payment);
  }));

  router.post('/payments/:id/kaspi-invoice', auth(['customer']), asyncHandler(async (req, res) => {
    const payment = first((await deps.db.query(
      `SELECT * FROM payments WHERE id=$1 AND customer_id=$2`,
      [req.params.id, req.user!.id],
    )).rows);
    if (!payment) throw new ApiError(404, 'not_found', 'Платёж не найден.');
    if ((payment as any).status === 'paid') {
      ok(res, { payment, alreadyPaid: true });
      return;
    }
    const phone = String(req.body.invoicePhone ?? req.body.kaspiPhone ?? '').trim();
    if (!phone) throw new ApiError(400, 'phone_required', 'Укажите номер KASPI.KZ.');
    const updated = first((await deps.db.query(
      `UPDATE payments
       SET provider='kaspi', invoice_phone=$2, status='invoice_requested', updated_at=NOW()
       WHERE id=$1 AND status IN ('pending','invoice_requested')
       RETURNING *`,
      [req.params.id, phone],
    )).rows);
    if (!updated) throw new ApiError(400, 'invalid_payment_status', 'По этому платежу нельзя выставить счёт.');
    const provider = await initProviderPayment(deps.paymentGateway, { payment: updated, payableAmount: Number((updated as any).amount) }, req, 'Оплата DOMLY');
    if (provider) await updatePaymentProviderPayload(deps.db, String(req.params.id), provider);
    await deps.notifications.createAdminEvent({
      event: 'new_payment',
      titleRu: 'Заявка KASPI.KZ',
      bodyRu: `Клиент запросил счёт KASPI.KZ на сумму ${(updated as any).amount} ₸.`,
      targetType: 'payment',
      targetId: String(req.params.id),
      dedupeKey: `kaspi-invoice-${req.params.id}`,
    });
    ok(res, { payment: updated, kaspiPhone: phone, provider });
  }));

  router.post('/payments/:id/bcc-session', auth(['customer']), asyncHandler(async (req, res) => {
    const payment = first((await deps.db.query(
      `SELECT * FROM payments WHERE id=$1 AND customer_id=$2`,
      [req.params.id, req.user!.id],
    )).rows);
    if (!payment) throw new ApiError(404, 'not_found', 'Платёж не найден.');
    if ((payment as any).status === 'paid') {
      ok(res, { payment, alreadyPaid: true });
      return;
    }
    const updated = first((await deps.db.query(
      `UPDATE payments SET provider='bcc', updated_at=NOW()
       WHERE id=$1 AND status IN ('pending','invoice_requested')
       RETURNING *`,
      [req.params.id],
    )).rows);
    if (!updated) throw new ApiError(400, 'invalid_payment_status', 'По этому платежу нельзя открыть онлайн-оплату.');
    const provider = await initProviderPayment(deps.paymentGateway, { payment: updated, payableAmount: Number((updated as any).amount) }, req, 'Оплата DOMLY');
    if (provider) await updatePaymentProviderPayload(deps.db, String(req.params.id), provider);
    ok(res, { payment: updated, ...provider });
  }));

  router.post('/payments/:id/status-check', auth(['admin', 'superadmin']), asyncHandler(async (req, res) => {
    const payment = first((await deps.db.query(`SELECT * FROM payments WHERE id=$1`, [req.params.id])).rows);
    if (!payment) throw new ApiError(404, 'not_found', 'Платёж не найден.');
    const provider = (payment as any).provider === 'bcc'
      ? await deps.paymentGateway.createBccStatusCheck({
        paymentId: String(req.params.id),
        originalTrType: req.body.originalTrType ?? '1',
        language: req.body.language ?? 'ru',
      })
      : { providerPayload: { provider: (payment as any).provider, paymentId: req.params.id }, providerResponse: null, paymentUrl: null };
    await updatePaymentProviderPayload(deps.db, String(req.params.id), { statusCheck: provider });
    await recordPaymentEvent(deps.db, {
      paymentId: String(req.params.id),
      provider: (payment as any).provider,
      eventType: 'status_check',
      payload: provider,
    });
    ok(res, { payment, statusCheck: provider });
  }));

  router.post('/payments/:id/refund', auth(['admin', 'superadmin']), asyncHandler(async (req, res) => {
    const payment = first<{
      id: string;
      customer_id: string;
      order_id: string | null;
      provider: string;
      status: string;
      amount: string;
      bonus_amount: string;
      external_id: string | null;
    }>((await deps.db.query(`SELECT * FROM payments WHERE id=$1`, [req.params.id])).rows);
    if (!payment) throw new ApiError(404, 'not_found', 'Платёж не найден.');
    if (!['paid', 'pending', 'invoice_requested'].includes(payment.status)) {
      throw new ApiError(400, 'invalid_payment_status', 'Этот платёж нельзя вернуть в текущем статусе.');
    }
    const amount = Math.min(Number(req.body.amount ?? payment.amount), Number(payment.amount));
    if (Number(payment.bonus_amount) > 0) {
      await deps.bonuses.refund(payment.customer_id, Number(payment.bonus_amount), 'Возврат по платежу', payment.order_id ?? undefined, payment.id);
    }
    const provider = payment.provider === 'bcc' && amount > 0
      ? await deps.paymentGateway.createBccRefund({
        paymentId: payment.id,
        amount,
        referenceId: payment.external_id,
        language: req.body.language ?? 'ru',
      })
      : { providerPayload: { provider: payment.provider, paymentId: payment.id, amount }, providerResponse: null, paymentUrl: null };
    const updated = first((await deps.db.query(
      `UPDATE payments SET status='refunded', payload=payload || $2::jsonb, updated_at=NOW() WHERE id=$1 RETURNING *`,
      [payment.id, { refund: provider, refundReason: req.body.reason ?? null, refundedBy: req.user?.id }],
    )).rows);
    await recordPaymentEvent(deps.db, {
      paymentId: payment.id,
      provider: payment.provider,
      eventType: 'refund_requested',
      status: 'refunded',
      externalId: payment.external_id,
      payload: provider,
    });
    await recordAudit('payment.refund_requested', 'payment', payment.id, { amount, provider, reason: req.body.reason ?? null }, req.user?.id);
    ok(res, { payment: updated, refund: provider });
  }));

  router.post('/payments/bcc/connection-check', auth(['admin', 'superadmin']), asyncHandler(async (req, res) => {
    ok(res, await deps.paymentGateway.createBccConnectionCheck({ language: req.body.language ?? 'ru' }));
  }));

  router.post('/payments/kaspi/webhook', asyncHandler(async (req, res) => {
    const status = normalizeKaspiPaymentStatus(req.body);
    const paymentId = req.body.paymentId ?? req.body.orderId ?? req.body.id;
    const payment = first((await deps.db.query(
      `UPDATE payments
       SET status=CASE WHEN status IN ('cancelled','refunded') AND $2='paid' THEN status ELSE $2 END,
           external_id=COALESCE($3, external_id),
           payload=payload || $4::jsonb,
           updated_at=NOW()
       WHERE id::text=$1 OR external_id=$1 RETURNING *`,
      [paymentId, status, req.body.externalId ?? req.body.providerPaymentId ?? null, req.body],
    )).rows);
    await recordPaymentEvent(deps.db, {
      paymentId: payment?.id ?? null,
      provider: 'kaspi',
      eventType: 'webhook',
      status,
      externalId: req.body.externalId ?? req.body.providerPaymentId ?? null,
      idempotencyKey: req.body.eventId ?? req.body.id ?? req.body.paymentId ?? null,
      payload: req.body,
    });
    await recordAudit('payment.webhook.kaspi', 'payment', payment?.id ?? paymentId ?? null, { status, payload: req.body });
    if (payment?.status === 'paid') await applyPaidPayment(payment);
    ok(res, { accepted: true, payment });
  }));

  router.post('/payments/moon-ai/kaspi-status', asyncHandler(async (req, res) => {
    verifyMoonAiWebhook(req);
    const paymentKey = req.body.paymentId ?? req.body.orderId ?? req.body.externalId ?? req.body.invoiceId ?? req.body.id;
    if (!paymentKey) throw new ApiError(400, 'payment_id_required', 'Передайте paymentId или invoiceId платежа.');
    const status = normalizeMoonAiKaspiStatus(req.body);
    const externalId = req.body.externalId ?? req.body.invoiceId ?? req.body.providerPaymentId ?? null;
    const invoicePhoneRaw = req.body.invoicePhone ?? req.body.kaspiPhone ?? req.body.phone ?? null;
    const invoicePhone = invoicePhoneRaw ? normalizePhone(String(invoicePhoneRaw)) : null;
    const amount = req.body.amount == null ? null : Number(req.body.amount);
    if (amount !== null && !Number.isFinite(amount)) {
      throw new ApiError(400, 'invalid_amount', 'Сумма платежа должна быть числом.');
    }
    const eventTimeRaw = req.body.dateTime ?? req.body.eventTime ?? req.body.paidAt ?? req.body.createdAt ?? null;
    const eventTime = eventTimeRaw ? new Date(String(eventTimeRaw)) : null;
    if (eventTime && Number.isNaN(eventTime.getTime())) {
      throw new ApiError(400, 'invalid_datetime', 'Дата и время должны быть в формате ISO 8601.');
    }
    const payload = {
      moonAi: {
        ...req.body,
        receivedAt: new Date().toISOString(),
        normalizedStatus: status,
        normalizedPhone: invoicePhone,
      },
    };
    const existingPayment = first((await deps.db.query(
      `SELECT * FROM payments WHERE id::text=$1 OR external_id=$1 LIMIT 1`,
      [String(paymentKey)],
    )).rows);
    if (!existingPayment) throw new ApiError(404, 'payment_not_found', 'Платёж не найден.');
    const payment = first((await deps.db.query(
      `UPDATE payments
       SET status=CASE WHEN status IN ('cancelled','refunded') AND $2='paid' THEN status ELSE $2::payment_status END,
           external_id=COALESCE($3, external_id),
           invoice_phone=COALESCE($4, invoice_phone),
           paid_at=CASE WHEN $2='paid' THEN COALESCE($5, paid_at, NOW()) ELSE paid_at END,
           payload=payload || $6::jsonb,
           updated_at=NOW()
       WHERE id=$1
       RETURNING *`,
      [(existingPayment as any).id, status, externalId, invoicePhone, eventTime?.toISOString() ?? null, payload],
    )).rows);
    await recordPaymentEvent(deps.db, {
      paymentId: payment?.id ?? null,
      provider: 'kaspi',
      eventType: 'moon_ai_status',
      status,
      externalId,
      idempotencyKey: req.body.eventId ?? req.body.requestId ?? externalId ?? `${paymentKey}:${status}:${eventTimeRaw ?? ''}`,
      payload: { ...req.body, normalizedStatus: status, normalizedPhone: invoicePhone, amountMismatch: payment && amount !== null ? Number((payment as any).amount) !== amount : null },
    });
    await recordAudit('payment.webhook.moon_ai_kaspi', 'payment', payment?.id ?? String(paymentKey), {
      status,
      amount,
      invoicePhone,
      externalId,
      found: Boolean(payment),
    });
    if (amount !== null && Number((payment as any).amount) !== amount) {
      await deps.notifications.createAdminEvent({
        event: 'new_payment',
        titleRu: 'Платёж Moon AI: сумма не совпала',
        bodyRu: `Moon AI прислал ${amount} ₸, в DOMLY ожидается ${(payment as any).amount} ₸.`,
        targetType: 'payment',
        targetId: String((payment as any).id),
        dedupeKey: `moon-ai-amount-mismatch-${(payment as any).id}-${amount}`,
      });
    }
    if ((payment as any).status === 'paid') await applyPaidPayment(payment);
    ok(res, { accepted: true, paymentId: (payment as any).id, status, amount, invoicePhone });
  }));

  router.post('/payments/bcc/webhook', asyncHandler(async (req, res) => {
    const status = normalizeBccPaymentStatus(req.body);
    const paymentId = req.body.paymentId ?? req.body.ORDER ?? req.body.order;
    const externalId = req.body.orderId ?? req.body.externalId ?? req.body.RRN ?? req.body.rrn ?? req.body.INT_REF ?? req.body.intRef ?? null;
    const payment = first((await deps.db.query(
      `UPDATE payments
       SET status=CASE WHEN status IN ('cancelled','refunded') AND $2='paid' THEN status ELSE $2 END,
           external_id=COALESCE($3, external_id),
           payload=payload || $4::jsonb,
           updated_at=NOW()
       WHERE id::text=$1 OR external_id=$1 OR external_id=$3
       RETURNING *`,
      [paymentId ?? null, status, externalId, req.body],
    )).rows);
    await recordPaymentEvent(deps.db, {
      paymentId: payment?.id ?? null,
      provider: 'bcc',
      eventType: 'webhook',
      status,
      externalId,
      idempotencyKey: req.body.EVENT_ID ?? req.body.eventId ?? req.body.NONCE ?? req.body.ORDER ?? paymentId ?? null,
      payload: req.body,
    });
    await recordAudit('payment.webhook.bcc', 'payment', payment?.id ?? paymentId ?? null, { status, payload: req.body });
  if (payment?.status === 'paid') await applyPaidPayment(payment);
    ok(res, { accepted: true, payment });
  }));

  router.get('/payments/my', auth(['customer']), asyncHandler(async (req, res) => {
    const { limit, offset } = pageParams(req.query);
    ok(res, (await deps.db.query(
      `SELECT p.*, o.numeric_id AS order_number, o.scheduled_date, o.start_time, o.end_time,
              cp.id AS package_purchase_id, cp.total_cleanings, cp.available_cleanings,
              pkg.name_ru AS package_name_ru, pkg.name_kk AS package_name_kk
       FROM payments p
       LEFT JOIN service_orders o ON o.id=p.order_id
       LEFT JOIN customer_packages cp ON cp.id=p.customer_package_id
       LEFT JOIN catalog_packages pkg ON pkg.id=COALESCE(cp.package_id, o.package_id)
       WHERE p.customer_id=$1
       ORDER BY p.created_at DESC
       LIMIT $2 OFFSET $3`,
      [req.user!.id, limit, offset],
    )).rows);
  }));

  router.get('/payments', auth(['admin', 'superadmin']), asyncHandler(async (req, res) => {
    const { limit, offset } = pageParams(req.query);
    ok(res, (await deps.db.query(
      `SELECT p.*, u.full_name, u.phone, o.numeric_id AS order_number, cp.id AS package_purchase_id
       FROM payments p
       LEFT JOIN app_users u ON u.id=p.customer_id
       LEFT JOIN service_orders o ON o.id=p.order_id
       LEFT JOIN customer_packages cp ON cp.id=p.customer_package_id
       ORDER BY p.created_at DESC LIMIT $1 OFFSET $2`,
      [limit, offset],
    )).rows);
  }));

  router.get('/admin/orders/:id/details', auth(['admin', 'superadmin']), asyncHandler(async (req, res) => {
    const order = first((await deps.db.query(
      `SELECT o.*, cu.full_name AS customer_name, cu.phone AS customer_phone, cu.email AS customer_email,
              cl.full_name AS cleaner_name, cl.phone AS cleaner_phone,
              ca.city, ca.settlement, ca.street, ca.house, ca.apartment, ca.entrance, ca.area AS profile_area, ca.verified_area,
              cp.total_cleanings, cp.available_cleanings, p.name_ru AS package_name_ru, p.name_kk AS package_name_kk
       FROM service_orders o
       JOIN app_users cu ON cu.id=o.customer_id
       LEFT JOIN app_users cl ON cl.id=o.cleaner_id
       LEFT JOIN customer_addresses ca ON ca.id=o.address_id
       LEFT JOIN customer_packages cp ON cp.id=o.customer_package_id
       LEFT JOIN catalog_packages p ON p.id=o.package_id
       WHERE o.id=$1`,
      [req.params.id],
    )).rows);
    if (!order) throw new ApiError(404, 'not_found', 'Заказ не найден.');
    const addons = (await deps.db.query(
      `SELECT oa.*, a.title_ru, a.title_kk, a.description_ru, a.description_kk, a.paid_separately
       FROM order_addons oa
       JOIN catalog_addons a ON a.id=oa.addon_id
       WHERE oa.order_id=$1
       ORDER BY oa.created_at ASC`,
      [req.params.id],
    )).rows;
    const payments = (await deps.db.query(`SELECT * FROM payments WHERE order_id=$1 ORDER BY created_at DESC`, [req.params.id])).rows;
    const offers = (await deps.db.query(
      `SELECT oo.*, u.full_name AS cleaner_name, u.phone AS cleaner_phone
       FROM order_offers oo JOIN app_users u ON u.id=oo.cleaner_id
       WHERE oo.order_id=$1 ORDER BY oo.created_at DESC`,
      [req.params.id],
    )).rows;
    ok(res, { order, addons, payments, offers });
  }));

  router.get('/admin/payments/:id/details', auth(['admin', 'superadmin']), asyncHandler(async (req, res) => {
    const payment = first((await deps.db.query(
      `SELECT p.*, u.full_name AS customer_name, u.phone AS customer_phone, u.email AS customer_email,
              o.numeric_id AS order_number, o.scheduled_date, o.start_time, o.end_time,
              cp.total_cleanings, cp.available_cleanings, pkg.name_ru AS package_name_ru
       FROM payments p
       LEFT JOIN app_users u ON u.id=p.customer_id
       LEFT JOIN service_orders o ON o.id=p.order_id
       LEFT JOIN customer_packages cp ON cp.id=p.customer_package_id
       LEFT JOIN catalog_packages pkg ON pkg.id=cp.package_id
       WHERE p.id=$1`,
      [req.params.id],
    )).rows);
    if (!payment) throw new ApiError(404, 'not_found', 'Платёж не найден.');
    const orderAddons = (await deps.db.query(
      `SELECT oa.*, a.title_ru, a.title_kk FROM order_addons oa JOIN catalog_addons a ON a.id=oa.addon_id WHERE oa.order_id=$1`,
      [(payment as any).order_id],
    )).rows;
    const audit = (await deps.db.query(
      `SELECT al.*, actor.full_name AS actor_name, actor.phone AS actor_phone
       FROM audit_logs al
       LEFT JOIN app_users actor ON actor.id=al.actor_id
       WHERE al.entity_type='payment' AND al.entity_id=$1
       ORDER BY al.created_at DESC`,
      [req.params.id],
    )).rows;
    const events = (await deps.db.query(
      `SELECT * FROM payment_events WHERE payment_id=$1 ORDER BY created_at DESC`,
      [req.params.id],
    )).rows;
    ok(res, { payment, orderAddons, events, audit });
  }));

  router.get('/admin/cleaners/:id/details', auth(['admin', 'superadmin']), asyncHandler(async (req, res) => {
    const cleaner = first((await deps.db.query(
      `SELECT u.*, cp.city, cp.registration_status, cp.verification_status, cp.work_start_date,
              cp.monthly_area_limit, cp.daily_work_limit_minutes, cp.verified_at
       FROM app_users u
       LEFT JOIN cleaner_profiles cp ON cp.user_id=u.id
       WHERE u.id=$1 AND u.role='cleaner'`,
      [req.params.id],
    )).rows);
    if (!cleaner) throw new ApiError(404, 'not_found', 'Уборщица не найдена.');
    const documents = (await deps.db.query(`SELECT d.*,f.public_url FROM cleaner_documents d LEFT JOIN files f ON f.id=d.file_id WHERE d.cleaner_id=$1 ORDER BY d.created_at DESC`, [req.params.id])).rows;
    const zones = (await deps.db.query(
      `SELECT z.* FROM cleaner_zones cz JOIN service_zones z ON z.id=cz.zone_id WHERE cz.cleaner_id=$1 ORDER BY z.city, z.name_ru`,
      [req.params.id],
    )).rows;
    const orders = (await deps.db.query(
      `SELECT id, numeric_id, scheduled_date, start_time, end_time, status, area, total_amount
       FROM service_orders WHERE cleaner_id=$1 ORDER BY scheduled_date DESC, start_time DESC LIMIT 100`,
      [req.params.id],
    )).rows;
    ok(res, { cleaner, documents, zones, orders });
  }));

  router.post('/admin/cleaners', auth(['admin', 'superadmin']), asyncHandler(async (req, res) => {
    if (!req.body.phone) throw new ApiError(400, 'invalid_request', 'Укажите телефон уборщицы.');
    const phone = normalizePhone(String(req.body.phone));
    const cleaner = first((await deps.db.query(
      `INSERT INTO app_users (role, phone, full_name, email, language, status, is_phone_verified)
       VALUES ('cleaner',$1,$2,$3,COALESCE($4,'ru'),COALESCE($5,'pending'),TRUE)
       ON CONFLICT (phone) DO UPDATE SET
         role='cleaner',
         full_name=COALESCE(EXCLUDED.full_name, app_users.full_name),
         email=COALESCE(EXCLUDED.email, app_users.email),
         status=EXCLUDED.status,
         updated_at=NOW()
       RETURNING id, numeric_id, role, phone, full_name, email, status, created_at`,
      [phone, req.body.fullName ?? null, req.body.email ?? null, req.body.language ?? 'ru', req.body.status ?? 'pending'],
    )).rows);
    const profile = first((await deps.db.query(
      `INSERT INTO cleaner_profiles
         (user_id, city, registration_status, verification_status, work_start_date, monthly_area_limit, daily_work_limit_minutes, sound_enabled, sound_volume, sound_key)
       VALUES ($1,COALESCE($2,'Астана'),COALESCE($3,'pending'),COALESCE($4,'pending'),$5,COALESCE($6,220),COALESCE($7,540),COALESCE($8,TRUE),COALESCE($9,100),COALESCE($10,'system'))
       ON CONFLICT (user_id) DO UPDATE SET
         city=EXCLUDED.city,
         registration_status=EXCLUDED.registration_status,
         verification_status=EXCLUDED.verification_status,
         work_start_date=COALESCE(EXCLUDED.work_start_date, cleaner_profiles.work_start_date),
         monthly_area_limit=EXCLUDED.monthly_area_limit,
         daily_work_limit_minutes=EXCLUDED.daily_work_limit_minutes,
         sound_enabled=EXCLUDED.sound_enabled,
         sound_volume=EXCLUDED.sound_volume,
         sound_key=EXCLUDED.sound_key,
         updated_at=NOW()
       RETURNING *`,
      [
        (cleaner as any).id,
        req.body.city,
        req.body.registrationStatus ?? req.body.status ?? 'pending',
        req.body.verificationStatus ?? req.body.status ?? 'pending',
        req.body.workStartDate ?? null,
        req.body.monthlyAreaLimit,
        req.body.dailyWorkLimitMinutes,
        typeof req.body.soundEnabled === 'boolean' ? req.body.soundEnabled : true,
        req.body.soundVolume,
        req.body.soundKey,
      ],
    )).rows);
    await recordAudit('cleaner.created', 'cleaner', String((cleaner as any).id), { cleaner, profile }, req.user?.id);
    await deps.notifications.createAdminEvent({
      event: 'new_cleaner',
      titleRu: 'Уборщица добавлена',
      bodyRu: `Добавлена уборщица ${phone}.`,
      targetType: 'cleaner',
      targetId: String((cleaner as any).id),
      dedupeKey: `cleaner-created-${(cleaner as any).id}`,
    });
    ok(res, { cleaner, profile }, 201);
  }));

  router.patch('/admin/cleaners/:id', auth(['admin', 'superadmin']), asyncHandler(async (req, res) => {
    const allowedStatuses = new Set(['new', 'pending', 'approved', 'rejected', 'blocked']);
    if (req.body.status && !allowedStatuses.has(String(req.body.status))) {
      throw new ApiError(400, 'invalid_status', 'Укажите корректный статус уборщицы.');
    }
    const cleaner = first((await deps.db.query(
      `UPDATE app_users SET
         full_name=COALESCE($2, full_name),
         email=COALESCE($3, email),
         language=COALESCE($4, language),
         rating=COALESCE($5, rating),
         status=COALESCE($6, status),
         updated_at=NOW()
       WHERE id=$1 AND role='cleaner'
       RETURNING id, numeric_id, role, phone, full_name, email, language, rating, status, created_at, updated_at`,
      [req.params.id, req.body.fullName ?? null, req.body.email ?? null, req.body.language ?? null, req.body.rating ?? null, req.body.status ?? null],
    )).rows);
    if (!cleaner) throw new ApiError(404, 'not_found', 'Уборщица не найдена.');
    const profile = first((await deps.db.query(
      `INSERT INTO cleaner_profiles
         (user_id, city, registration_status, verification_status, work_start_date, monthly_area_limit, daily_work_limit_minutes, sound_enabled, sound_volume, sound_key)
       VALUES ($1,COALESCE($2,'Астана'),COALESCE($3,'pending'),COALESCE($4,'pending'),$5,COALESCE($6,220),COALESCE($7,540),COALESCE($8,TRUE),COALESCE($9,100),COALESCE($10,'system'))
       ON CONFLICT (user_id) DO UPDATE SET
         city=COALESCE($2, cleaner_profiles.city),
         registration_status=COALESCE($3, cleaner_profiles.registration_status),
         verification_status=COALESCE($4, cleaner_profiles.verification_status),
         work_start_date=COALESCE($5, cleaner_profiles.work_start_date),
         monthly_area_limit=COALESCE($6, cleaner_profiles.monthly_area_limit),
         daily_work_limit_minutes=COALESCE($7, cleaner_profiles.daily_work_limit_minutes),
         sound_enabled=COALESCE($8, cleaner_profiles.sound_enabled),
         sound_volume=COALESCE($9, cleaner_profiles.sound_volume),
         sound_key=COALESCE($10, cleaner_profiles.sound_key),
         updated_at=NOW()
       RETURNING *`,
      [
        req.params.id,
        req.body.city ?? null,
        req.body.registrationStatus ?? null,
        req.body.verificationStatus ?? null,
        req.body.workStartDate ?? null,
        req.body.monthlyAreaLimit ?? null,
        req.body.dailyWorkLimitMinutes ?? null,
        typeof req.body.soundEnabled === 'boolean' ? req.body.soundEnabled : null,
        req.body.soundVolume ?? null,
        req.body.soundKey ?? null,
      ],
    )).rows);
    await recordAudit('cleaner.updated', 'cleaner', String(req.params.id), req.body, req.user?.id);
    ok(res, { cleaner, profile });
  }));

  router.delete('/admin/cleaners/:id', auth(['admin', 'superadmin']), asyncHandler(async (req, res) => {
    const cleaner = first((await deps.db.query(
      `UPDATE app_users SET status='blocked', updated_at=NOW() WHERE id=$1 AND role='cleaner' RETURNING id, numeric_id, phone, full_name, status`,
      [req.params.id],
    )).rows);
    if (!cleaner) throw new ApiError(404, 'not_found', 'Уборщица не найдена.');
    await deps.db.query(
      `UPDATE cleaner_profiles SET registration_status='blocked', verification_status='blocked', updated_at=NOW() WHERE user_id=$1`,
      [req.params.id],
    );
    await recordAudit('cleaner.deactivated', 'cleaner', String(req.params.id), { reason: req.body?.reason ?? null }, req.user?.id);
    ok(res, { cleaner });
  }));

  router.patch('/admin/cleaners/:id/verification', auth(['admin', 'superadmin']), asyncHandler(async (req, res) => {
    ok(res, await verifyCleaner(deps.db,deps.notifications,String(req.params.id),String(req.body.status ?? ''),req.user!.id));
  }));

  router.put('/admin/cleaners/:id/zones', auth(['admin', 'superadmin']), asyncHandler(async (req, res) => {
    const cleaner = first((await deps.db.query(`SELECT id FROM app_users WHERE id=$1 AND role='cleaner'`, [req.params.id])).rows);
    if (!cleaner) throw new ApiError(404, 'not_found', 'Уборщица не найдена.');
    const zoneIds = Array.isArray(req.body.zoneIds) ? req.body.zoneIds : [];
    await deps.db.transaction(async (tx) => {
      await tx.query(`DELETE FROM cleaner_zones WHERE cleaner_id=$1`, [req.params.id]);
      for (const zoneId of zoneIds) {
        await tx.query(
          `INSERT INTO cleaner_zones (cleaner_id, zone_id) VALUES ($1,$2) ON CONFLICT DO NOTHING`,
          [req.params.id, zoneId],
        );
      }
    });
    const zones = (await deps.db.query(
      `SELECT z.* FROM cleaner_zones cz JOIN service_zones z ON z.id=cz.zone_id WHERE cz.cleaner_id=$1 ORDER BY z.city, z.name_ru`,
      [req.params.id],
    )).rows;
    ok(res, { zones });
  }));

  router.get('/admin/quality-checks/:id/details', auth(['admin', 'superadmin']), asyncHandler(async (req, res) => {
    const qualityCheck = first((await deps.db.query(
      `SELECT q.*, u.full_name AS customer_name, u.phone AS customer_phone, u.email AS customer_email,
              ca.city, ca.settlement, ca.street, ca.house, ca.apartment, ca.area, ca.verified_area
       FROM quality_check_requests q
       JOIN app_users u ON u.id=q.customer_id
       LEFT JOIN customer_addresses ca ON ca.id=q.address_id
       WHERE q.id=$1`,
      [req.params.id],
    )).rows);
    if (!qualityCheck) throw new ApiError(404, 'not_found', 'Заявка проверки площади не найдена.');
    const payments = (await deps.db.query(
      `SELECT * FROM payments
       WHERE customer_id=$1 AND (payload->>'qualityCheckId'=$2 OR created_at >= $3)
       ORDER BY created_at DESC LIMIT 20`,
      [(qualityCheck as any).customer_id, req.params.id, (qualityCheck as any).created_at],
    )).rows;
    const orders = (await deps.db.query(
      `SELECT o.numeric_id, o.status, o.scheduled_date, o.start_time, o.end_time, o.total_amount, o.payable_amount,
              pkg.name_ru AS package_name_ru, cl.full_name AS cleaner_name, cl.phone AS cleaner_phone
       FROM service_orders o
       LEFT JOIN catalog_packages pkg ON pkg.id=o.package_id
       LEFT JOIN app_users cl ON cl.id=o.cleaner_id
       WHERE o.customer_id=$1
       ORDER BY o.created_at DESC LIMIT 20`,
      [(qualityCheck as any).customer_id],
    )).rows;
    ok(res, { qualityCheck, payments, orders });
  }));

  router.get('/admin/complaints/:id/details', auth(['admin', 'superadmin']), asyncHandler(async (req, res) => {
    const complaint = first((await deps.db.query(
      `SELECT c.*, cu.full_name AS customer_name, cu.phone AS customer_phone,
              cu.email AS customer_email, cu.rating AS customer_rating, cu.bonus_balance AS customer_bonus_balance,
              cl.full_name AS cleaner_name, cl.phone AS cleaner_phone, cl.email AS cleaner_email, cl.rating AS cleaner_rating,
              o.numeric_id AS order_number, o.scheduled_date, o.start_time, o.end_time, o.status AS order_status,
              ca.city, ca.settlement, ca.street, ca.house, ca.apartment, ca.entrance, ca.area, ca.verified_area
       FROM complaints c
       LEFT JOIN app_users cu ON cu.id=c.customer_id
       LEFT JOIN app_users cl ON cl.id=c.cleaner_id
       LEFT JOIN service_orders o ON o.id=c.order_id
       LEFT JOIN customer_addresses ca ON ca.id=o.address_id
       WHERE c.id=$1`,
      [req.params.id],
    )).rows);
    if (!complaint) throw new ApiError(404, 'not_found', 'Жалоба не найдена.');
    const chats = (await deps.db.query(
      `SELECT ch.*,
              COALESCE(json_agg(json_build_object(
                'id', m.id,
                'senderId', m.sender_id,
                'senderName', s.full_name,
                'senderPhone', s.phone,
                'messageRu', m.message_ru,
                'messageKk', m.message_kk,
                'fileId', m.file_id,
                'fileUrl', f.public_url,
                'fileMimeType', f.mime_type,
                'createdAt', m.created_at
              ) ORDER BY m.created_at) FILTER (WHERE m.id IS NOT NULL), '[]') AS messages
       FROM chats ch
       LEFT JOIN chat_messages m ON m.chat_id=ch.id
       LEFT JOIN app_users s ON s.id=m.sender_id
       LEFT JOIN files f ON f.id=m.file_id
       WHERE ch.complaint_id=$1 OR ch.order_id=$2
       GROUP BY ch.id
       ORDER BY ch.created_at DESC`,
      [req.params.id, (complaint as any).order_id],
    )).rows;
    ok(res, { complaint, chats });
  }));

  router.get('/admin/reviews/:id/details', auth(['admin', 'superadmin']), asyncHandler(async (req, res) => {
    const review = first((await deps.db.query(
      `SELECT r.*, cu.full_name AS customer_name, cu.phone AS customer_phone,
              cu.email AS customer_email, cu.rating AS customer_rating,
              cl.full_name AS cleaner_name, cl.phone AS cleaner_phone, cl.email AS cleaner_email, cl.rating AS cleaner_rating,
              o.numeric_id AS order_number, o.scheduled_date, o.start_time, o.end_time, o.status AS order_status,
              ca.city, ca.settlement, ca.street, ca.house, ca.apartment, ca.area, ca.verified_area
       FROM reviews r
       LEFT JOIN app_users cu ON cu.id=r.customer_id
       LEFT JOIN app_users cl ON cl.id=r.cleaner_id
       LEFT JOIN service_orders o ON o.id=r.order_id
       LEFT JOIN customer_addresses ca ON ca.id=o.address_id
       WHERE r.id=$1`,
      [req.params.id],
    )).rows);
    if (!review) throw new ApiError(404, 'not_found', 'Отзыв не найден.');
    const cleanerRecentReviews = (await deps.db.query(
      `SELECT r.rating, r.comment, r.created_at, cu.full_name AS customer_name, o.numeric_id AS order_number
       FROM reviews r
       LEFT JOIN app_users cu ON cu.id=r.customer_id
       LEFT JOIN service_orders o ON o.id=r.order_id
       WHERE r.cleaner_id=$1
       ORDER BY r.created_at DESC LIMIT 20`,
      [(review as any).cleaner_id],
    )).rows;
    ok(res, { review, cleanerRecentReviews });
  }));

  router.get('/admin/checklist-reports/:id/details', auth(['admin', 'superadmin']), asyncHandler(async (req, res) => {
    const report = first((await deps.db.query(
      `SELECT cr.*, o.numeric_id AS order_number, o.scheduled_date, o.start_time, o.end_time, o.status AS order_status,
              cu.full_name AS customer_name, cu.phone AS customer_phone, cu.email AS customer_email,
              cl.full_name AS cleaner_name, cl.phone AS cleaner_phone, cl.email AS cleaner_email,
              ca.city, ca.settlement, ca.street, ca.house, ca.apartment, ca.entrance, ca.area, ca.verified_area,
              pkg.name_ru AS package_name_ru, pkg.name_kk AS package_name_kk
       FROM checklist_reports cr
       JOIN service_orders o ON o.id=cr.order_id
       JOIN app_users cu ON cu.id=o.customer_id
       LEFT JOIN app_users cl ON cl.id=cr.cleaner_id
       LEFT JOIN customer_addresses ca ON ca.id=o.address_id
       LEFT JOIN catalog_packages pkg ON pkg.id=o.package_id
       WHERE cr.id=$1`,
      [req.params.id],
    )).rows);
    if (!report) throw new ApiError(404, 'not_found', 'Чек-лист не найден.');
    const items = (await deps.db.query(
      `SELECT * FROM checklist_report_items WHERE report_id=$1 ORDER BY created_at ASC, id ASC`,
      [req.params.id],
    )).rows;
    const orderAddons = (await deps.db.query(
      `SELECT oa.*, a.title_ru, a.title_kk, a.paid_separately
       FROM order_addons oa
       JOIN catalog_addons a ON a.id=oa.addon_id
       WHERE oa.order_id=$1
       ORDER BY oa.created_at ASC`,
      [(report as any).order_id],
    )).rows;
    ok(res, { report, items, orderAddons });
  }));

  router.post('/quality-checks', auth(['customer']), upload.single('document'), asyncHandler(async (req, res) => {
    if (!req.body.area || !req.file) throw new ApiError(400, 'invalid_request', 'Укажите площадь и загрузите документ.');
    const ext = extensionFromMime(req.file.mimetype);
    const objectKey = `quality_checks/${req.user!.id}/${new Date().toISOString().slice(0, 10)}/${randomUUID()}${ext}`;
    const publicUrl = await deps.storage.uploadBuffer(objectKey, req.file.buffer, req.file.mimetype);
    const file = first((await deps.db.query(
      `INSERT INTO files (owner_id, bucket, object_key, mime_type, size_bytes, public_url)
       VALUES ($1,$2,$3,$4,$5,$6) RETURNING *`,
      [req.user!.id, env.minioBucket, objectKey, req.file.mimetype, req.file.size, publicUrl],
    )).rows);
    const row = first((await deps.db.query(
      `INSERT INTO quality_check_requests (customer_id, address_id, requested_area, status, document_file_id)
       VALUES ($1,$2,$3,'pending',$4) RETURNING *`,
      [req.user!.id, req.body.addressId ?? null, req.body.area, (file as any).id],
    )).rows);
    await deps.notifications.createAdminEvent({
      event: 'quality_check',
      titleRu: 'Проверка площади',
      bodyRu: 'Клиент отправил документы на проверку площади.',
      targetType: 'quality_check',
      targetId: (row as { id: string }).id,
      dedupeKey: `quality-check-${(row as { id: string }).id}`,
    });
    ok(res, { request: row, file }, 201);
  }));

  router.post('/quality-checks/from-file', auth(['customer']), asyncHandler(async (req, res) => {
    const area = Number(req.body.area ?? req.body.actualArea ?? req.body.requestedArea ?? 0);
    if (!Number.isFinite(area) || area <= 0) throw new ApiError(400, 'invalid_area', 'Укажите площадь.');
    const row = await deps.db.transaction(async (tx) => {
      if (req.body.addressId) {
        const address = first((await tx.query(
          'SELECT id FROM customer_addresses WHERE id=$1 AND user_id=$2 FOR UPDATE',
          [req.body.addressId, req.user!.id],
        )).rows);
        if (!address) throw new ApiError(404, 'not_found', 'Адрес не найден.');
      }
      let fileId: string | null = null;
      if (req.body.fileId || req.body.fileUrl) {
        const file = first((await tx.query(
          req.body.fileId
            ? 'SELECT id FROM files WHERE id=$1 AND owner_id=$2'
            : 'SELECT id FROM files WHERE public_url=$1 AND owner_id=$2',
          [req.body.fileId ?? req.body.fileUrl, req.user!.id],
        )).rows) as { id: string } | undefined;
        if (!file) throw new ApiError(404, 'file_not_found', 'Загрузите фото повторно.');
        fileId = file.id;
      }
      return first((await tx.query(
        `INSERT INTO quality_check_requests
         (customer_id, address_id, requested_area, status, document_file_id)
         VALUES ($1,$2,$3,'pending',$4) RETURNING *`,
        [req.user!.id, req.body.addressId ?? null, area, fileId],
      )).rows);
    });
    await deps.notifications.createAdminEvent({
      event: 'quality_check',
      titleRu: 'Проверка площади',
      bodyRu: 'Клиент отправил документы на проверку площади.',
      targetType: 'quality_check',
      targetId: (row as any).id,
      dedupeKey: `quality-check-${(row as any).id}`,
    });
    ok(res, { request: row }, 201);
  }));

  router.patch('/admin/quality-checks/:id', auth(['admin', 'superadmin']), asyncHandler(async (req, res) => {
    const allowed: Record<string, string> = {
      status: 'status',
      reviewStatus: 'status',
      approvedArea: 'approved_area',
      actualArea: 'approved_area',
      adminComment: 'admin_comment',
      recalculationAmount: 'recalculation_amount',
    };
    const updates: string[] = [];
    const values: unknown[] = [req.params.id];
    for (const [key, column] of Object.entries(allowed)) {
      if (Object.prototype.hasOwnProperty.call(req.body, key)) {
        const value = column === 'status'
          ? ({ verified: 'approved', resolved: 'approved', call_required: 'scheduled', open: 'pending' } as Record<string, string>)[req.body[key]] ?? req.body[key]
          : req.body[key];
        if (column === 'status' && !['pending','scheduled','approved','rejected','cancelled'].includes(value)) {
          throw new ApiError(400, 'invalid_status', 'Некорректный статус проверки площади.');
        }
        values.push(value);
        updates.push(`${column}=$${values.length}`);
      }
    }
    if (!updates.length) throw new ApiError(400, 'empty_update', 'Нет данных для обновления проверки площади.');
    values.push(req.user!.id);
    const adminParam = values.length;
    const row = await deps.db.transaction(async client=>{
    await client.query('SELECT id FROM quality_check_requests WHERE id=$1 FOR UPDATE',[req.params.id]);
    const updated = first<any>((await client.query(
      `UPDATE quality_check_requests
       SET ${updates.join(', ')}, admin_id=$${adminParam}, updated_at=NOW()
       WHERE id=$1 RETURNING *`,
      values,
    )).rows);
    if (!updated) throw new ApiError(404, 'not_found', 'Заявка проверки площади не найдена.');
    if (updated.status==='approved') {
      const area=Number(updated.approved_area??updated.requested_area);
      await confirmArea(client,updated.customer_id,updated.address_id,area);
      await client.query('UPDATE quality_check_requests SET approved_area=$2 WHERE id=$1',[updated.id,area]);
      updated.approved_area=area;
    }
    return updated;
    });
    await recordAudit('quality_check.updated', 'quality_check', String(req.params.id), { fields: Object.keys(req.body) }, req.user?.id);
    ok(res, row);
  }));

  router.post('/admin/quality-checks/:id/approve', auth(['admin', 'superadmin']), asyncHandler(async (req, res) => {
    const row = await deps.db.transaction(async client=>{
      const current=first<any>((await client.query('SELECT * FROM quality_check_requests WHERE id=$1 FOR UPDATE',[req.params.id])).rows);
      if (!current) throw new ApiError(404,'not_found','Заявка проверки площади не найдена.');
      const area=Number(req.body.approvedArea??current.approved_area??current.requested_area);
      await confirmArea(client,current.customer_id,current.address_id,area);
      return first<any>((await client.query(`UPDATE quality_check_requests SET status='approved',approved_area=$2,admin_id=$3,recalculation_amount=COALESCE($4,0),updated_at=NOW() WHERE id=$1 RETURNING *`,[req.params.id,area,req.user!.id,req.body.recalculationAmount??0])).rows)!;
    });
    await deps.notifications.create({
      userId: row.customer_id,
      titleRu: Number(req.body.recalculationAmount ?? 0) > 0 ? 'Перерасчёт площади' : 'Площадь подтверждена',
      bodyRu: Number(req.body.recalculationAmount ?? 0) > 0
        ? `После проверки площади сформирована доплата ${req.body.recalculationAmount} ₸.`
        : 'Площадь квартиры подтверждена.',
      targetType: Number(req.body.recalculationAmount ?? 0) > 0 ? 'payments' : 'quality_check',
      targetId: row.id,
    });
    if (Number(req.body.recalculationAmount ?? 0) > 0) {
      const address = row.address_id
        ? first<{ city: string; settlement: string | null; street: string; house: string; apartment: string | null }>((await deps.db.query(
          `SELECT city, settlement, street, house, apartment FROM customer_addresses WHERE id=$1`,
          [row.address_id],
        )).rows)
        : null;
      const payment = await deps.payments.createPayment({
        customerId: row.customer_id,
        amount: Number(req.body.recalculationAmount),
        provider: 'kaspi',
        payload: { kind: 'area_recalculation', qualityCheckId: row.id, mInfo: formatPaymentAddress(address) },
      });
      ok(res, { qualityCheck: row, payment });
      return;
    }
    ok(res, row);
  }));

  router.get('/notifications', auth(), asyncHandler(async (req, res) => {
    ok(res, (await deps.db.query(
      `SELECT n.*, COALESCE(n.read_at, nr.read_at) AS read_at
       FROM notifications n
       LEFT JOIN notification_reads nr ON nr.notification_id=n.id AND nr.user_id=$1
       WHERE n.user_id=$1 OR (n.user_id IS NULL AND n.role=$2)
       ORDER BY COALESCE(n.read_at, nr.read_at) NULLS FIRST, n.created_at DESC`,
      [req.user!.id, req.user!.role],
    )).rows);
  }));

  router.get('/notifications/unread-count', auth(), asyncHandler(async (req, res) => {
    const row = first<{ count: string }>((await deps.db.query(
      `SELECT COUNT(*)::text AS count
       FROM notifications n
       LEFT JOIN notification_reads nr ON nr.notification_id=n.id AND nr.user_id=$1
       WHERE (n.user_id=$1 OR (n.user_id IS NULL AND n.role=$2)) AND COALESCE(n.read_at, nr.read_at) IS NULL`,
      [req.user!.id, req.user!.role],
    )).rows);
    ok(res, { count: Number(row?.count ?? 0) });
  }));

  router.get('/admin/notifications', auth(['admin', 'superadmin']), asyncHandler(async (req, res) => {
    const { limit, offset } = pageParams(req.query);
    ok(res, (await deps.db.query(
      `SELECT n.*, COALESCE(n.read_at, nr.read_at) AS read_at
       FROM notifications n
       LEFT JOIN notification_reads nr ON nr.notification_id=n.id AND nr.user_id=$1
       WHERE (n.user_id IS NULL AND n.role IN ('admin','superadmin')) OR n.user_id=$1
       ORDER BY COALESCE(n.read_at, nr.read_at) NULLS FIRST, n.created_at DESC
       LIMIT $2 OFFSET $3`,
      [req.user!.id, limit, offset],
    )).rows);
  }));

  router.post('/admin/notifications', auth(['admin', 'superadmin']), asyncHandler(async (req, res) => {
    const targetRole = req.body.role ? String(req.body.role) as any : undefined;
    const targetUserId = req.body.userId ? String(req.body.userId) : undefined;
    if (!targetRole && !targetUserId) throw new ApiError(400, 'invalid_request', 'Выберите получателя уведомления.');
    ok(res, await deps.notifications.create({
      userId: targetUserId,
      role: targetRole,
      titleRu: String(req.body.titleRu ?? 'Уведомление'),
      titleKk: req.body.titleKk ?? null,
      bodyRu: String(req.body.bodyRu ?? ''),
      bodyKk: req.body.bodyKk ?? null,
      targetType: req.body.targetType ?? null,
      targetId: req.body.targetId ?? null,
      dedupeKey: req.body.dedupeKey ?? null,
    }), 201);
  }));

  router.post('/notifications', auth(), asyncHandler(async (req, res) => {
    const targetUserId = req.user!.role === 'admin' || req.user!.role === 'superadmin'
      ? (req.body.userId ? String(req.body.userId) : req.user!.id)
      : req.user!.id;
    ok(res, await deps.notifications.create({
      userId: targetUserId,
      titleRu: String(req.body.titleRu ?? req.body.title ?? 'Уведомление'),
      titleKk: req.body.titleKk ?? null,
      bodyRu: String(req.body.bodyRu ?? req.body.body ?? ''),
      bodyKk: req.body.bodyKk ?? null,
      targetType: req.body.targetType ?? req.body.type ?? null,
      targetId: req.body.targetId ?? null,
      dedupeKey: req.body.dedupeKey ?? null,
    }), 201);
  }));

  router.post('/admin/integrations/wapi/test-otp', auth(['admin', 'superadmin']), asyncHandler(async (req, res) => {
    if (!env.wapiToken || !env.wapiProfileId) throw new ApiError(400, 'integration_not_configured', 'WAPI не настроен.');
    const phone = normalizePhone(String(req.body.phone ?? ''));
    const code = String(req.body.code ?? Math.floor(100000 + Math.random() * 900000));
    if (!/^\d{4,8}$/.test(code)) throw new ApiError(400, 'invalid_code', 'Код должен содержать от 4 до 8 цифр.');
    await deps.wapi.sendOtp(phone, code);
    await recordAudit('integration.wapi_test_otp', 'integration', env.wapiProfileId || null, {
      phone,
      profileId: maskValue(env.wapiProfileId),
    }, req.user?.id);
    ok(res, { sent: true, phone, profileId: maskValue(env.wapiProfileId) });
  }));

  router.post('/notifications/:id/read', auth(), asyncHandler(async (req, res) => {
    const notificationRows = await deps.db.query(
      `SELECT * FROM notifications WHERE id=$1 AND (user_id=$2 OR (user_id IS NULL AND role=$3))`,
      [req.params.id, req.user!.id, req.user!.role],
    );
    const notification = first<any>(notificationRows.rows);
    if (!notification) throw new ApiError(404, 'not_found', 'Уведомление не найдено.');
    if (notification.user_id) {
      const updatedRows = await deps.db.query(
        `UPDATE notifications SET read_at=NOW() WHERE id=$1 AND user_id=$2 RETURNING *`,
        [req.params.id, req.user!.id],
      );
      ok(res, first(updatedRows.rows));
      return;
    }
    const readRows = await deps.db.query(
      `INSERT INTO notification_reads (notification_id, user_id, read_at)
       VALUES ($1,$2,NOW())
       ON CONFLICT (notification_id, user_id) DO UPDATE SET read_at=NOW()
       RETURNING *`,
      [req.params.id, req.user!.id],
    );
    const read = first(readRows.rows);
    ok(res, { ...notification, read_at: (read as any)?.read_at ?? new Date().toISOString() });
  }));

  router.post('/notifications/read-all', auth(), asyncHandler(async (req, res) => {
    const userRows = (await deps.db.query(
      `UPDATE notifications SET read_at=NOW()
       WHERE user_id=$1 AND read_at IS NULL
       RETURNING id`,
      [req.user!.id],
    )).rows;
    const roleRows = (await deps.db.query(
      `INSERT INTO notification_reads (notification_id, user_id, read_at)
       SELECT n.id, $1, NOW()
       FROM notifications n
       LEFT JOIN notification_reads nr ON nr.notification_id=n.id AND nr.user_id=$1
       WHERE n.user_id IS NULL AND n.role=$2 AND nr.notification_id IS NULL
       ON CONFLICT (notification_id, user_id) DO UPDATE SET read_at=NOW()
       RETURNING notification_id`,
      [req.user!.id, req.user!.role],
    )).rows;
    ok(res, { updated: userRows.length + roleRows.length });
  }));

  router.get('/chats', auth(), asyncHandler(async (req, res) => {
    const { limit, offset } = pageParams(req.query);
    const admin = ['admin', 'superadmin'].includes(req.user!.role);
    const rows = (await deps.db.query(
      admin
        ? `SELECT c.*,
             COUNT(cm.id)::int AS message_count,
             MAX(cm.created_at) AS last_message_at
           FROM chats c
           LEFT JOIN chat_messages cm ON cm.chat_id=c.id
           GROUP BY c.id
           ORDER BY COALESCE(MAX(cm.created_at), c.created_at) DESC
           LIMIT $1 OFFSET $2`
        : `SELECT c.*,
             cp.last_read_at,
             COUNT(cm.id)::int AS message_count,
             MAX(cm.created_at) AS last_message_at,
             COUNT(cm.id) FILTER (WHERE cm.sender_id<>$1 AND (cp.last_read_at IS NULL OR cm.created_at>cp.last_read_at))::int AS unread_count
           FROM chats c
           JOIN chat_participants cp ON cp.chat_id=c.id AND cp.user_id=$1
           LEFT JOIN chat_messages cm ON cm.chat_id=c.id
           GROUP BY c.id, cp.last_read_at
           ORDER BY COALESCE(MAX(cm.created_at), c.created_at) DESC
           LIMIT $2 OFFSET $3`,
      admin ? [limit, offset] : [req.user!.id, limit, offset],
    )).rows;
    ok(res, rows);
  }));

  router.get('/chats/:id/messages', auth(), asyncHandler(async (req, res) => {
    const admin = ['admin', 'superadmin'].includes(req.user!.role);
    if (!admin) {
      const participant = first((await deps.db.query(
        `SELECT 1 FROM chat_participants WHERE chat_id=$1 AND user_id=$2`,
        [req.params.id, req.user!.id],
      )).rows);
      if (!participant) throw new ApiError(403, 'forbidden', 'Нет доступа к этому чату.');
    }
    await deps.db.query(
      `UPDATE chat_participants SET last_read_at=NOW() WHERE chat_id=$1 AND user_id=$2`,
      [req.params.id, req.user!.id],
    );
    ok(res, (await deps.db.query(
      `SELECT cm.*, u.full_name AS sender_name, u.phone AS sender_phone, u.role AS sender_role,
              f.public_url AS file_url, f.mime_type AS file_mime_type, f.size_bytes AS file_size_bytes
       FROM chat_messages cm
       JOIN app_users u ON u.id=cm.sender_id
       LEFT JOIN files f ON f.id=cm.file_id
       WHERE cm.chat_id=$1
       ORDER BY cm.created_at ASC`,
      [req.params.id],
    )).rows);
  }));

  router.post('/chats', auth(), asyncHandler(async (req, res) => {
    const type = String(req.body.type ?? 'order');
    const row = first((await deps.db.query(
      `INSERT INTO chats (type, order_id, complaint_id) VALUES ($1,$2,$3) RETURNING *`,
      [type, req.body.orderId ?? null, req.body.complaintId ?? null],
    )).rows);
    const participantIds = new Set<string>([
      req.user!.id,
      ...(Array.isArray(req.body.participantIds) ? req.body.participantIds.map(String) : []),
    ]);
    if (req.body.orderId) {
      const order = first<any>((await deps.db.query(
        `SELECT customer_id, cleaner_id FROM service_orders WHERE id=$1`,
        [req.body.orderId],
      )).rows);
      if (order?.customer_id) participantIds.add(String(order.customer_id));
      if (order?.cleaner_id) participantIds.add(String(order.cleaner_id));
    }
    if (req.body.complaintId) {
      const complaint = first<any>((await deps.db.query(
        `SELECT customer_id, cleaner_id FROM complaints WHERE id=$1`,
        [req.body.complaintId],
      )).rows);
      if (complaint?.customer_id) participantIds.add(String(complaint.customer_id));
      if (complaint?.cleaner_id) participantIds.add(String(complaint.cleaner_id));
      const admins = (await deps.db.query<{ id: string }>(
        `SELECT id FROM app_users WHERE role IN ('admin','superadmin') AND status <> 'blocked'`,
      )).rows;
      for (const admin of admins) participantIds.add(admin.id);
    }
    for (const userId of participantIds) {
      await deps.db.query(`INSERT INTO chat_participants (chat_id, user_id) VALUES ($1,$2) ON CONFLICT DO NOTHING`, [(row as any).id, userId]);
    }
    ok(res, row, 201);
  }));

  router.post('/chats/:id/messages', auth(), upload.single('file'), asyncHandler(async (req, res) => {
    const admin = ['admin', 'superadmin'].includes(req.user!.role);
    if (!admin) {
      const participant = first((await deps.db.query(
        `SELECT 1 FROM chat_participants WHERE chat_id=$1 AND user_id=$2`,
        [req.params.id, req.user!.id],
      )).rows);
      if (!participant) throw new ApiError(403, 'forbidden', 'Нет доступа к этому чату.');
    }
    const messageRu = String(req.body.messageRu ?? req.body.message ?? '').trim();
    const messageKk = req.body.messageKk ? String(req.body.messageKk).trim() : null;
    let fileId: string | null = req.body.fileId ? String(req.body.fileId) : null;
    if (req.file) {
      const ext = extensionFromMime(req.file.mimetype);
      const objectKey = `chat/${req.params.id}/${req.user!.id}/${new Date().toISOString().slice(0, 10)}/${randomUUID()}${ext}`;
      const publicUrl = await deps.storage.uploadBuffer(objectKey, req.file.buffer, req.file.mimetype);
      const file = first<{ id: string }>((await deps.db.query(
        `INSERT INTO files (owner_id, bucket, object_key, mime_type, size_bytes, public_url)
         VALUES ($1,$2,$3,$4,$5,$6) RETURNING id`,
        [req.user!.id, env.minioBucket, objectKey, req.file.mimetype, req.file.size, publicUrl],
      )).rows);
      fileId = file?.id ?? null;
    }
    if (fileId) {
      const file = first((await deps.db.query(
        `SELECT 1 FROM files WHERE id=$1 AND (owner_id=$2 OR $3=TRUE)`,
        [fileId, req.user!.id, admin],
      )).rows);
      if (!file) throw new ApiError(404, 'file_not_found', 'Файл не найден или недоступен.');
    }
    if (!messageRu && !fileId) {
      throw new ApiError(400, 'message_required', 'Введите сообщение или прикрепите файл.');
    }
    const row = first((await deps.db.query(
      `INSERT INTO chat_messages (chat_id, sender_id, message_ru, message_kk, file_id)
       VALUES ($1,$2,$3,$4,$5)
       RETURNING *`,
      [req.params.id, req.user!.id, messageRu || null, messageKk, fileId],
    )).rows);
    await deps.db.query(
      `UPDATE chat_participants SET last_read_at=NOW() WHERE chat_id=$1 AND user_id=$2`,
      [req.params.id, req.user!.id],
    );
    const recipients = (await deps.db.query<{ user_id: string }>(
      `SELECT user_id FROM chat_participants WHERE chat_id=$1 AND user_id<>$2`,
      [req.params.id, req.user!.id],
    )).rows;
    for (const recipient of recipients) {
      await deps.notifications.create({
        userId: recipient.user_id,
        titleRu: 'Новое сообщение',
        bodyRu: 'Вам пришло сообщение в чате.',
        targetType: 'chat',
        targetId: String(req.params.id),
        dedupeKey: `chat-${req.params.id}-${(row as any).id}-${recipient.user_id}`,
      });
    }
    ok(res, row, 201);
  }));

  router.post('/chats/:id/read', auth(), asyncHandler(async (req, res) => {
    const row = first((await deps.db.query(
      `UPDATE chat_participants SET last_read_at=NOW()
       WHERE chat_id=$1 AND user_id=$2
       RETURNING chat_id, user_id, last_read_at`,
      [req.params.id, req.user!.id],
    )).rows);
    if (!row && !['admin', 'superadmin'].includes(req.user!.role)) {
      throw new ApiError(403, 'forbidden', 'Нет доступа к этому чату.');
    }
    ok(res, row ?? { chat_id: req.params.id, user_id: req.user!.id, last_read_at: new Date().toISOString() });
  }));

  router.get('/complaints', auth(['customer']), asyncHandler(async (req, res) => {
    ok(res, (await deps.db.query(
      `SELECT c.*, o.numeric_id AS order_number, cl.full_name AS cleaner_name, cl.phone AS cleaner_phone
       FROM complaints c
       LEFT JOIN service_orders o ON o.id=c.order_id
       LEFT JOIN app_users cl ON cl.id=c.cleaner_id
       WHERE c.customer_id=$1
       ORDER BY c.created_at DESC`,
      [req.user!.id],
    )).rows);
  }));

  router.post('/complaints', auth(['customer']), asyncHandler(async (req, res) => {
    const photoUrls = Array.isArray(req.body.photoUrls)
      ? req.body.photoUrls.map(String).map((item: string) => item.trim()).filter(Boolean).slice(0, 5)
      : [];
    if (req.body.photoUrl && photoUrls.length === 0) {
      photoUrls.push(String(req.body.photoUrl).trim());
    }
    const row = first((await deps.db.query(
      `INSERT INTO complaints (customer_id, cleaner_id, order_id, title, body, photo_urls)
       VALUES ($1,$2,$3,$4,$5,$6) RETURNING *`,
      [req.user!.id, req.body.cleanerId ?? null, req.body.orderId ?? null, req.body.title, req.body.body ?? null, JSON.stringify(photoUrls)],
    )).rows);
    const chat = first((await deps.db.query(
      `INSERT INTO chats (type, order_id, complaint_id)
       VALUES ('complaint',$1,$2)
       RETURNING *`,
      [req.body.orderId ?? null, (row as any).id],
    )).rows);
    await deps.db.query(
      `INSERT INTO chat_participants (chat_id, user_id)
       VALUES ($1,$2)
       ON CONFLICT DO NOTHING`,
      [(chat as any).id, req.user!.id],
    );
    const admins = (await deps.db.query<{ id: string }>(
      `SELECT id FROM app_users WHERE role IN ('admin','superadmin') AND status <> 'blocked'`,
    )).rows;
    for (const admin of admins) {
      await deps.db.query(
        `INSERT INTO chat_participants (chat_id, user_id)
         VALUES ($1,$2)
         ON CONFLICT DO NOTHING`,
        [(chat as any).id, admin.id],
      );
    }
    await deps.notifications.createAdminEvent({
      event: 'complaint',
      titleRu: 'Новая жалоба',
      bodyRu: `Клиент отправил жалобу №${(row as any).numeric_id}.`,
      targetType: 'complaint',
      targetId: (row as any).id,
      dedupeKey: `complaint-${(row as any).id}`,
    });
    ok(res, { complaint: row, chat }, 201);
  }));

  router.patch('/admin/complaints/:id', auth(['admin', 'superadmin']), asyncHandler(async (req, res) => {
    const row = first((await deps.db.query(
      `UPDATE complaints SET status=COALESCE($2,status), updated_at=NOW() WHERE id=$1 RETURNING *`,
      [req.params.id, req.body.status ?? null],
    )).rows);
    if (!row) throw new ApiError(404, 'not_found', 'Жалоба не найдена.');
    ok(res, row);
  }));

  router.get('/reviews', auth(), asyncHandler(async (req, res) => {
    const filters: string[] = [];
    const values: unknown[] = [];
    if (req.user!.role === 'customer') {
      values.push(req.user!.id);
      filters.push(`r.customer_id=$${values.length}`);
    } else if (req.user!.role === 'cleaner') {
      values.push(req.user!.id);
      filters.push(`r.cleaner_id=$${values.length}`);
    }
    const where = filters.length ? `WHERE ${filters.join(' AND ')}` : '';
    ok(res, (await deps.db.query(
      `SELECT r.*, cu.full_name AS customer_name, cu.phone AS customer_phone,
              cl.full_name AS cleaner_name, cl.phone AS cleaner_phone,
              o.numeric_id AS order_number, o.scheduled_date, o.start_time, o.end_time
       FROM reviews r
       LEFT JOIN app_users cu ON cu.id=r.customer_id
       LEFT JOIN app_users cl ON cl.id=r.cleaner_id
       LEFT JOIN service_orders o ON o.id=r.order_id
       ${where}
       ORDER BY r.created_at DESC`,
      values,
    )).rows);
  }));

  router.post('/reviews', auth(['customer']), asyncHandler(async (req, res) => {
    const positiveTraits = Array.isArray(req.body.positiveTraits) ? req.body.positiveTraits.map(String).filter(Boolean) : [];
    const negativeTraits = Array.isArray(req.body.negativeTraits) ? req.body.negativeTraits.map(String).filter(Boolean) : [];
    const row = first((await deps.db.query(
      `INSERT INTO reviews (customer_id, cleaner_id, order_id, rating, comment, photo_url, positive_traits, negative_traits)
       VALUES ($1,$2,$3,$4,$5,$6,$7,$8) RETURNING *`,
      [
        req.user!.id,
        req.body.cleanerId ?? null,
        req.body.orderId ?? null,
        req.body.rating,
        req.body.comment ?? null,
        req.body.photoUrl ?? null,
        JSON.stringify(positiveTraits),
        JSON.stringify(negativeTraits),
      ],
    )).rows);
    if (req.body.cleanerId) {
      await deps.db.query(
        `UPDATE app_users SET rating=(
          SELECT ROUND(AVG(rating)::numeric, 2) FROM reviews WHERE cleaner_id=$1
        ), updated_at=NOW() WHERE id=$1`,
        [req.body.cleanerId],
      );
    }
    await deps.notifications.createAdminEvent({
      event: 'review',
      titleRu: 'Новый отзыв',
      bodyRu: `Клиент оставил отзыв с оценкой ${req.body.rating}.`,
      targetType: 'review',
      targetId: (row as any).id,
      dedupeKey: `review-${(row as any).id}`,
    });
    ok(res, row, 201);
  }));

  router.get('/preorders', auth(['customer']), asyncHandler(async (req, res) => {
    const rows = (await deps.db.query(
      `SELECT pr.*, ca.city, ca.settlement, ca.street, ca.house, ca.apartment,
              pkg.name_ru AS package_name_ru, pkg.name_kk AS package_name_kk,
              pay.status AS payment_status, pay.amount AS payment_amount
       FROM preorders pr
       LEFT JOIN customer_addresses ca ON ca.id=pr.address_id
       LEFT JOIN catalog_packages pkg ON pkg.id=pr.package_id
       LEFT JOIN payments pay ON pay.id=pr.payment_id
       WHERE pr.customer_id=$1 AND pr.status <> 'cancelled'
       ORDER BY pr.created_at DESC`,
      [req.user!.id],
    )).rows;
    ok(res, rows);
  }));

  router.post('/preorders', auth(['customer']), asyncHandler(async (req, res) => {
    const row = first((await deps.db.query(
      `INSERT INTO preorders (customer_id, address_id, package_id, desired_date, desired_time, area, status)
       VALUES ($1,$2,$3,$4,$5,$6,'new') RETURNING *`,
      [req.user!.id, req.body.addressId ?? null, req.body.packageId ?? null, req.body.desiredDate, req.body.desiredTime ?? null, req.body.area ?? null],
    )).rows);
    await deps.notifications.createAdminEvent({
      event: 'preorder',
      titleRu: 'Новая предварительная запись',
      bodyRu: 'Клиент оставил предварительную запись.',
      targetType: 'preorder',
      targetId: (row as { id: string }).id,
      dedupeKey: `preorder-${(row as { id: string }).id}`,
    });
    ok(res, row, 201);
  }));

  router.post('/preorders/:id/pay', auth(['customer']), asyncHandler(async (req, res) => {
    const preorder = first<{
      id: string;
      customer_id: string;
      address_id: string | null;
      package_id: string | null;
      area: string | null;
      status: string;
    }>((await deps.db.query(
      `SELECT * FROM preorders WHERE id=$1 AND customer_id=$2`,
      [req.params.id, req.user!.id],
    )).rows);
    if (!preorder) throw new ApiError(404, 'not_found', 'Предварительная запись не найдена.');
    if (!['new', 'notified'].includes(preorder.status)) {
      throw new ApiError(400, 'invalid_preorder_status', 'Эту предварительную запись уже нельзя оплатить.');
    }
    if (!preorder.package_id) throw new ApiError(400, 'package_required', 'Выберите пакет для предварительной записи.');
    const pkg = first<{ id: string; base_price: string; price_per_m2: string; cleaning_count: number; months: number }>((await deps.db.query(
      `SELECT * FROM catalog_packages WHERE id=$1 AND active=TRUE`,
      [preorder.package_id],
    )).rows);
    if (!pkg) throw new ApiError(404, 'not_found', 'Пакет не найден.');
    const address = preorder.address_id
      ? first<{
        id: string;
        area: string | null;
        verified_area: string | null;
        city: string;
        settlement: string | null;
        street: string;
        house: string;
        apartment: string | null;
      }>((await deps.db.query(
        `SELECT id, area, verified_area, city, settlement, street, house, apartment FROM customer_addresses WHERE id=$1 AND user_id=$2`,
        [preorder.address_id, req.user!.id],
      )).rows)
      : null;
    const area = Number(address?.verified_area ?? address?.area ?? preorder.area ?? 0);
    if (!area || area <= 0) throw new ApiError(400, 'area_required', 'Укажите площадь квартиры.');
    const total = deps.pricing.calculatePackage(Number(pkg.base_price), Number(pkg.price_per_m2), area, pkg.cleaning_count, pkg.months);
    const customerPackage = first<{ id: string }>((await deps.db.query(
      `INSERT INTO customer_packages (customer_id, package_id, address_id, total_cleanings, available_cleanings, months, status, purchase_config)
       VALUES ($1,$2,$3,$4,$4,$5,'pending_payment',$6) RETURNING *`,
      [req.user!.id, pkg.id, preorder.address_id, pkg.cleaning_count, pkg.months],
    )).rows);
    const payment = await deps.payments.createPayment({
      customerId: req.user!.id,
      customerPackageId: customerPackage!.id,
      provider: req.body.provider ?? 'kaspi',
      applyReferralDiscount: false,
      amount: total,
      useBonus: req.body.useBonus === true,
      requestedBonus: Number(req.body.requestedBonus ?? 0),
      invoicePhone: req.body.invoicePhone,
      payload: { kind: 'preorder_package_purchase', preorderId: preorder.id, mInfo: formatPaymentAddress(address) },
    });
    await deps.notifications.createAdminEvent({
      event: 'new_payment',
      titleRu: 'Новая заявка на оплату',
      bodyRu: `Клиент оплачивает предварительную запись на сумму ${total} ₸.`,
      targetType: 'payment',
      targetId: (payment.payment as any).id,
      dedupeKey: `payment-${(payment.payment as any).id}`,
    });
    await deps.db.query(
      `UPDATE preorders SET customer_package_id=$2, payment_id=$3, updated_at=NOW() WHERE id=$1`,
      [preorder.id, customerPackage!.id, (payment.payment as any).id],
    );
    if (payment.payableAmount === 0) {
      await applyPaidPayment(payment.payment);
    } else {
      const provider = await initProviderPayment(deps.paymentGateway, payment, req, 'Оплата предварительной записи DOMLY');
      if (provider) await updatePaymentProviderPayload(deps.db, (payment.payment as any).id, provider);
    }
    ok(res, { preorderId: preorder.id, customerPackage, ...payment });
  }));

  router.post('/preorders/:id/cancel', auth(['customer']), asyncHandler(async (req, res) => {
    const row = first((await deps.db.query(
      `UPDATE preorders
       SET status='cancelled', admin_comment=COALESCE($3, admin_comment), updated_at=NOW()
       WHERE id=$1 AND customer_id=$2 AND status IN ('new','notified')
       RETURNING *`,
      [req.params.id, req.user!.id, req.body.reason ?? null],
    )).rows);
    if (!row) throw new ApiError(404, 'not_found', 'Активная предварительная запись не найдена.');
    await deps.notifications.createAdminEvent({
      event: 'preorder',
      titleRu: 'Предварительная запись отменена',
      bodyRu: 'Клиент отменил предварительную запись.',
      targetType: 'preorder',
      targetId: String(req.params.id),
      dedupeKey: `preorder-cancelled-${req.params.id}`,
    });
    ok(res, row);
  }));

  router.post('/admin/preorders/start', auth(['admin', 'superadmin']), asyncHandler(async (req, res) => {
    const rows = (await deps.db.query<{ id: string; customer_id: string }>(
      `UPDATE preorders SET status='notified', updated_at=NOW()
       WHERE status='new' RETURNING id, customer_id`,
    )).rows;
    for (const preorder of rows) {
      await deps.notifications.create({
        userId: preorder.customer_id,
        titleRu: 'DOMLY запущен',
        bodyRu: `Старт уборок назначен на ${req.body.startDate}. Оплатите предварительную запись в приложении.`,
        targetType: 'preorder',
        targetId: preorder.id,
        dedupeKey: `preorder-start-${preorder.id}`,
      });
    }
    ok(res, { notified: rows.length });
  }));

  router.patch('/admin/preorders/:id', auth(['admin', 'superadmin']), asyncHandler(async (req, res) => {
    const allowed = new Set(['new', 'notified', 'paid', 'worked', 'cancelled']);
    const status = req.body.status ? String(req.body.status) : null;
    if (status && !allowed.has(status)) throw new ApiError(400, 'invalid_status', 'Недопустимый статус предварительной записи.');
    const row = first((await deps.db.query(
      `UPDATE preorders
       SET status=COALESCE($2,status), admin_comment=COALESCE($3,admin_comment), updated_at=NOW()
       WHERE id=$1
       RETURNING *`,
      [req.params.id, status, req.body.adminComment ?? null],
    )).rows);
    if (!row) throw new ApiError(404, 'not_found', 'Предварительная запись не найдена.');
    await recordAudit('preorder.updated', 'preorder', String(req.params.id), { status, adminComment: req.body.adminComment ?? null }, req.user?.id);
    ok(res, row);
  }));

  router.post('/admin/settings', auth(['admin', 'superadmin']), asyncHandler(async (req, res) => {
    if (req.body.settings && typeof req.body.settings === 'object' && !Array.isArray(req.body.settings)) {
      const rows = [];
      for (const [key, value] of Object.entries(req.body.settings)) {
        rows.push(first((await deps.db.query(
          `INSERT INTO app_settings (key, value, updated_at) VALUES ($1,$2,NOW())
           ON CONFLICT (key) DO UPDATE SET value=$2, updated_at=NOW()
           RETURNING *`,
          [key, JSON.stringify(value)],
        )).rows));
      }
      await recordAudit('settings.bulk_updated', 'settings', null, { keys: Object.keys(req.body.settings) }, req.user?.id);
      ok(res, rows);
      return;
    }
    if (!req.body.key) throw new ApiError(400, 'invalid_request', 'Укажите ключ настройки.');
    const row = first((await deps.db.query(
      `INSERT INTO app_settings (key, value, updated_at) VALUES ($1,$2,NOW())
       ON CONFLICT (key) DO UPDATE SET value=$2, updated_at=NOW()
       RETURNING *`,
      [req.body.key, JSON.stringify(req.body.value)],
    )).rows);
    await recordAudit('settings.updated', 'settings', String(req.body.key), { value: req.body.value }, req.user?.id);
    ok(res, row);
  }));

  router.get('/admin/settings/meta', auth(['admin', 'superadmin']), asyncHandler(async (_req, res) => {
    const settings = await readAppSettings(deps.db);
    ok(res, buildRuntimeSettingsMeta(settings));
  }));

  router.get('/admin/settings', auth(['admin', 'superadmin']), asyncHandler(async (req, res) => {
    ok(res, (await deps.db.query(`SELECT key, value, updated_at FROM app_settings ORDER BY key`)).rows);
  }));

  router.post('/admin/audit', auth(['admin', 'superadmin']), asyncHandler(async (req, res) => {
    await recordAudit(
      String(req.body.action ?? 'admin.action'),
      req.body.entityType ? String(req.body.entityType) : null,
      req.body.entityId ? String(req.body.entityId) : null,
      req.body.payload ?? req.body,
      req.user?.id,
    );
    ok(res, { logged: true });
  }));

  router.get('/admin/integrations/status', auth(['admin', 'superadmin']), asyncHandler(async (_req, res) => {
    const minioBucketAvailable = await deps.storage.client.bucketExists(env.minioBucket).catch(() => false);
    const envReport = validateEnvConfig(env);
    const backup = await readBackupStatus();
    ok(res, {
      env: {
        ok: envReport.ok,
        issues: envReport.issues,
        warnings: envReport.warnings,
      },
      database: { configured: Boolean(env.databaseUrl) },
      redis: { configured: Boolean(env.redisUrl) },
      storage: {
        provider: 'minio',
        configured: Boolean(env.minioEndpoint && env.minioAccessKey && env.minioSecretKey),
        bucket: env.minioBucket,
        bucketAvailable: minioBucketAvailable,
      },
      wapi: {
        configured: Boolean(env.wapiToken && env.wapiProfileId),
        profileId: env.wapiProfileId ? maskValue(env.wapiProfileId) : null,
      },
      fcm: {
        configured: Boolean(env.fcmProjectId && env.fcmClientEmail && env.fcmPrivateKey),
        projectId: env.fcmProjectId || null,
      },
      payments: {
        kaspiConfigured: Boolean(env.kaspiMerchantId && env.kaspiApiKey && env.kaspiBaseUrl),
        bccConfigured: Boolean(env.bccMerchantId && env.bccTerminalId && env.bccNotifyUrl && env.bccReturnUrl),
      },
      geo: {
        osmConfigured: Boolean(env.osmNominatimUrl),
        yandexGeocoderConfigured: Boolean(env.yandexGeocoderApiKey),
        yandexGeosuggestConfigured: Boolean(env.yandexGeosuggestApiKey),
      },
      backup,
    });
  }));

  router.get('/admin/translations', auth(['admin', 'superadmin']), asyncHandler(async (req, res) => {
    const namespace = req.query.namespace ? String(req.query.namespace) : null;
    const missing = req.query.missing ? String(req.query.missing) : null;
    const search = req.query.search ? `%${String(req.query.search)}%` : null;
    const { limit, offset } = pageParams(req.query);
    ok(res, (await deps.db.query(
      `SELECT key, ru, kk, namespace, updated_at,
              (kk IS NULL OR btrim(kk)='') AS missing_kk
       FROM translations
       WHERE ($1::text IS NULL OR namespace=$1)
       AND (
         $2::text IS NULL
         OR ($2='kk' AND (kk IS NULL OR btrim(kk)=''))
         OR ($2='any' AND (ru IS NULL OR btrim(ru)='' OR kk IS NULL OR btrim(kk)=''))
       )
       AND ($3::text IS NULL OR key ILIKE $3 OR ru ILIKE $3 OR kk ILIKE $3)
       ORDER BY namespace, key
       LIMIT $4 OFFSET $5`,
      [namespace, missing, search, limit, offset],
    )).rows);
  }));

  router.get('/admin/translations/stats', auth(['admin', 'superadmin']), asyncHandler(async (_req, res) => {
    const rows = (await deps.db.query(
      `SELECT namespace,
              COUNT(*)::int AS total,
              COUNT(*) FILTER (WHERE ru IS NOT NULL AND btrim(ru)<>'')::int AS ru_filled,
              COUNT(*) FILTER (WHERE kk IS NOT NULL AND btrim(kk)<>'')::int AS kk_filled,
              COUNT(*) FILTER (WHERE kk IS NULL OR btrim(kk)='')::int AS kk_missing
       FROM translations
       GROUP BY namespace
       ORDER BY namespace`,
    )).rows;
    ok(res, rows);
  }));

  router.post('/admin/translations', auth(['admin', 'superadmin']), asyncHandler(async (req, res) => {
    const row = first((await deps.db.query(
      `INSERT INTO translations (key, ru, kk, namespace, updated_at) VALUES ($1,$2,$3,$4,NOW())
       ON CONFLICT (key) DO UPDATE SET ru=$2, kk=$3, namespace=$4, updated_at=NOW()
       RETURNING *`,
      [req.body.key, req.body.ru, req.body.kk ?? null, req.body.namespace ?? 'app'],
    )).rows);
    ok(res, row);
  }));

  router.post('/admin/translations/bulk', auth(['admin', 'superadmin']), asyncHandler(async (req, res) => {
    const items = Array.isArray(req.body.items) ? req.body.items : [];
    if (items.length === 0) throw new ApiError(400, 'invalid_request', 'Передайте список переводов.');
    const rows = [];
    for (const item of items) {
      if (!item.key || !item.ru) throw new ApiError(400, 'invalid_request', 'У каждого перевода должны быть key и ru.');
      rows.push(first((await deps.db.query(
        `INSERT INTO translations (key, ru, kk, namespace, updated_at) VALUES ($1,$2,$3,$4,NOW())
         ON CONFLICT (key) DO UPDATE SET ru=$2, kk=$3, namespace=$4, updated_at=NOW()
         RETURNING *`,
        [item.key, item.ru, item.kk ?? null, item.namespace ?? 'app'],
      )).rows));
    }
    ok(res, { updated: rows.length, rows });
  }));

  router.post('/admin/translations/sync-defaults', auth(['admin', 'superadmin']), asyncHandler(async (req, res) => {
    const overwrite = req.body.overwrite === true;
    let inserted = 0;
    let updated = 0;
    for (const item of defaultTranslations) {
      const result = await deps.db.query<{ inserted: boolean }>(
        `INSERT INTO translations (key, ru, kk, namespace, updated_at)
         VALUES ($1,$2,$3,$4,NOW())
         ON CONFLICT (key) DO UPDATE SET
           ru=CASE WHEN $5::boolean THEN EXCLUDED.ru ELSE translations.ru END,
           kk=CASE
             WHEN $5::boolean THEN EXCLUDED.kk
             WHEN translations.kk IS NULL OR btrim(translations.kk)='' THEN EXCLUDED.kk
             ELSE translations.kk
           END,
           namespace=EXCLUDED.namespace,
           updated_at=NOW()
         RETURNING (xmax = 0) AS inserted`,
        [item.key, item.ru, item.kk, item.namespace ?? 'app', overwrite],
      );
      if (result.rows[0]?.inserted) inserted += 1;
      else updated += 1;
    }
    ok(res, { inserted, updated, total: defaultTranslations.length, overwrite });
  }));

  router.post('/admin/catalog/packages', auth(['admin', 'superadmin']), asyncHandler(async (req, res) => {
    const row = first((await deps.db.query(
      `INSERT INTO catalog_packages
       (name_ru, name_kk, description_ru, description_kk, cleaning_count, months, base_price, price_per_m2, active, features)
       VALUES ($1,$2,$3,$4,$5,$6,$7,$8,COALESCE($9,TRUE),COALESCE($10,'{}'::jsonb))
       ON CONFLICT (name_ru, cleaning_count, months) DO UPDATE SET
         name_kk=EXCLUDED.name_kk,
         description_ru=EXCLUDED.description_ru,
         description_kk=EXCLUDED.description_kk,
         base_price=EXCLUDED.base_price,
         price_per_m2=EXCLUDED.price_per_m2,
         active=EXCLUDED.active,
         features=EXCLUDED.features,
         updated_at=NOW()
       RETURNING *`,
      [req.body.nameRu, req.body.nameKk ?? null, req.body.descriptionRu ?? null, req.body.descriptionKk ?? null, req.body.cleaningCount, req.body.months ?? 1, req.body.basePrice, req.body.pricePerM2 ?? 0, req.body.active, JSON.stringify(req.body.features ?? {})],
    )).rows);
    ok(res, row, 201);
  }));

  router.patch('/admin/catalog/packages/:id', auth(['admin', 'superadmin']), asyncHandler(async (req, res) => {
    const row = first((await deps.db.query(
      `UPDATE catalog_packages SET
       name_ru=COALESCE($2,name_ru), name_kk=COALESCE($3,name_kk),
       description_ru=COALESCE($4,description_ru), description_kk=COALESCE($5,description_kk),
       cleaning_count=COALESCE($6,cleaning_count), months=COALESCE($7,months),
       base_price=COALESCE($8,base_price), price_per_m2=COALESCE($9,price_per_m2),
       active=COALESCE($10,active), features=COALESCE($11,features), updated_at=NOW()
       WHERE id=$1 RETURNING *`,
      [req.params.id, req.body.nameRu ?? null, req.body.nameKk ?? null, req.body.descriptionRu ?? null, req.body.descriptionKk ?? null, req.body.cleaningCount ?? null, req.body.months ?? null, req.body.basePrice ?? null, req.body.pricePerM2 ?? null, req.body.active ?? null, req.body.features == null ? null : JSON.stringify(req.body.features)],
    )).rows);
    if (!row) throw new ApiError(404, 'not_found', 'Пакет не найден.');
    ok(res, row);
  }));

  router.post('/admin/catalog/addon-groups', auth(['admin', 'superadmin']), asyncHandler(async (req, res) => {
    const row = first((await deps.db.query(
      `WITH existing AS (
         SELECT id FROM addon_groups WHERE title_ru=$1 LIMIT 1
       ), updated AS (
         UPDATE addon_groups SET title_kk=$2, sort_order=COALESCE($3, sort_order), active=COALESCE($4, active), updated_at=NOW()
         WHERE id=(SELECT id FROM existing) RETURNING *
       ), inserted AS (
         INSERT INTO addon_groups (title_ru, title_kk, sort_order, active)
         SELECT $1,$2,COALESCE($3,0),COALESCE($4,TRUE)
         WHERE NOT EXISTS (SELECT 1 FROM existing)
         RETURNING *
       )
       SELECT * FROM updated UNION ALL SELECT * FROM inserted`,
      [req.body.titleRu, req.body.titleKk ?? null, req.body.sortOrder ?? 0, req.body.active ?? true],
    )).rows);
    ok(res, row, 201);
  }));

  router.patch('/admin/catalog/addon-groups/:id', auth(['admin', 'superadmin']), asyncHandler(async (req, res) => {
    const row = first((await deps.db.query(
      `UPDATE addon_groups SET
       title_ru=COALESCE($2,title_ru), title_kk=COALESCE($3,title_kk),
       sort_order=COALESCE($4,sort_order), active=COALESCE($5,active), updated_at=NOW()
       WHERE id=$1 RETURNING *`,
      [req.params.id, req.body.titleRu ?? null, req.body.titleKk ?? null, req.body.sortOrder ?? null, req.body.active ?? null],
    )).rows);
    if (!row) throw new ApiError(404, 'not_found', 'Группа доп. услуг не найдена.');
    ok(res, row);
  }));

  router.post('/admin/catalog/addons', auth(['admin', 'superadmin']), asyncHandler(async (req, res) => {
    const row = first((await deps.db.query(
      `WITH existing AS (
         SELECT id FROM catalog_addons WHERE (($1::uuid IS NULL AND group_id IS NULL) OR group_id=$1::uuid) AND title_ru=$2 LIMIT 1
       ), updated AS (
         UPDATE catalog_addons SET
           title_kk=$3, description_ru=$4, description_kk=$5, hint_ru=$6, hint_kk=$7,
           pricing_type=COALESCE($8, pricing_type), price=COALESCE($9, price),
           duration_minutes=COALESCE($10, duration_minutes), paid_separately=COALESCE($11, paid_separately),
           active=COALESCE($12, active), sort_order=COALESCE($13, sort_order), updated_at=NOW()
         WHERE id=(SELECT id FROM existing) RETURNING *
       ), inserted AS (
         INSERT INTO catalog_addons
         (group_id, title_ru, title_kk, description_ru, description_kk, hint_ru, hint_kk, pricing_type, price, duration_minutes, paid_separately, active, sort_order)
         SELECT $1,$2,$3,$4,$5,$6,$7,COALESCE($8,'fixed'),COALESCE($9,0),COALESCE($10,0),COALESCE($11,FALSE),COALESCE($12,TRUE),COALESCE($13,0)
         WHERE NOT EXISTS (SELECT 1 FROM existing)
         RETURNING *
       )
       SELECT * FROM updated UNION ALL SELECT * FROM inserted`,
      [req.body.groupId ?? null, req.body.titleRu, req.body.titleKk ?? null, req.body.descriptionRu ?? null, req.body.descriptionKk ?? null, req.body.hintRu ?? null, req.body.hintKk ?? null, req.body.pricingType ?? 'fixed', req.body.price ?? 0, req.body.durationMinutes ?? 0, req.body.paidSeparately ?? false, req.body.active ?? true, req.body.sortOrder ?? 0],
    )).rows);
    ok(res, row, 201);
  }));

  router.patch('/admin/catalog/addons/:id', auth(['admin', 'superadmin']), asyncHandler(async (req, res) => {
    const row = first((await deps.db.query(
      `UPDATE catalog_addons SET
       group_id=COALESCE($2,group_id), title_ru=COALESCE($3,title_ru), title_kk=COALESCE($4,title_kk),
       description_ru=COALESCE($5,description_ru), description_kk=COALESCE($6,description_kk),
       hint_ru=COALESCE($7,hint_ru), hint_kk=COALESCE($8,hint_kk),
       pricing_type=COALESCE($9,pricing_type), price=COALESCE($10,price), duration_minutes=COALESCE($11,duration_minutes),
       paid_separately=COALESCE($12,paid_separately), active=COALESCE($13,active), sort_order=COALESCE($14,sort_order), updated_at=NOW()
       WHERE id=$1 RETURNING *`,
      [req.params.id, req.body.groupId ?? null, req.body.titleRu ?? null, req.body.titleKk ?? null, req.body.descriptionRu ?? null, req.body.descriptionKk ?? null, req.body.hintRu ?? null, req.body.hintKk ?? null, req.body.pricingType ?? null, req.body.price ?? null, req.body.durationMinutes ?? null, req.body.paidSeparately ?? null, req.body.active ?? null, req.body.sortOrder ?? null],
    )).rows);
    if (!row) throw new ApiError(404, 'not_found', 'Доп. услуга не найдена.');
    ok(res, row);
  }));

  router.post('/admin/service-zones', auth(['admin', 'superadmin']), asyncHandler(async (req, res) => {
    const row = first((await deps.db.query(
      `INSERT INTO service_zones (name_ru, name_kk, city, polygon, active)
       VALUES ($1,$2,$3,$4,COALESCE($5,TRUE))
       ON CONFLICT (city, name_ru) DO UPDATE SET
         name_kk=EXCLUDED.name_kk, polygon=EXCLUDED.polygon, active=EXCLUDED.active
       RETURNING *`,
      [req.body.nameRu, req.body.nameKk ?? null, req.body.city, req.body.polygon == null ? null : JSON.stringify(req.body.polygon), req.body.active ?? true],
    )).rows);
    ok(res, row, 201);
  }));

  router.patch('/admin/service-zones/:id', auth(['admin', 'superadmin']), asyncHandler(async (req, res) => {
    const row = first((await deps.db.query(
      `UPDATE service_zones SET
       name_ru=COALESCE($2,name_ru), name_kk=COALESCE($3,name_kk), city=COALESCE($4,city),
       polygon=COALESCE($5,polygon), active=COALESCE($6,active)
       WHERE id=$1 RETURNING *`,
      [req.params.id, req.body.nameRu ?? null, req.body.nameKk ?? null, req.body.city ?? null, req.body.polygon == null ? null : JSON.stringify(req.body.polygon), req.body.active ?? null],
    )).rows);
    if (!row) throw new ApiError(404, 'not_found', 'Зона не найдена.');
    ok(res, row);
  }));

  router.post('/admin/connected-houses', auth(['admin', 'superadmin']), asyncHandler(async (req, res) => {
    const row = first((await deps.db.query(
      `INSERT INTO connected_houses
       (city, street_ru, street_kk, house, residential_complex_ru, residential_complex_kk, zone_id, latitude, longitude, active)
       VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,COALESCE($10,TRUE))
       ON CONFLICT (city, street_ru, house) DO UPDATE SET
         street_kk=EXCLUDED.street_kk,
         residential_complex_ru=EXCLUDED.residential_complex_ru,
         residential_complex_kk=EXCLUDED.residential_complex_kk,
         zone_id=EXCLUDED.zone_id,
         latitude=EXCLUDED.latitude,
         longitude=EXCLUDED.longitude,
         active=EXCLUDED.active
       RETURNING *`,
      [req.body.city, req.body.streetRu, req.body.streetKk ?? null, req.body.house, req.body.residentialComplexRu ?? null, req.body.residentialComplexKk ?? null, req.body.zoneId ?? null, req.body.latitude ?? null, req.body.longitude ?? null, req.body.active ?? true],
    )).rows);
    ok(res, row, 201);
  }));

  router.patch('/admin/connected-houses/:id', auth(['admin', 'superadmin']), asyncHandler(async (req, res) => {
    const row = first((await deps.db.query(
      `UPDATE connected_houses SET
       city=COALESCE($2,city), street_ru=COALESCE($3,street_ru), street_kk=COALESCE($4,street_kk),
       house=COALESCE($5,house), residential_complex_ru=COALESCE($6,residential_complex_ru),
       residential_complex_kk=COALESCE($7,residential_complex_kk), zone_id=COALESCE($8,zone_id),
       latitude=COALESCE($9,latitude), longitude=COALESCE($10,longitude), active=COALESCE($11,active)
       WHERE id=$1 RETURNING *`,
      [req.params.id, req.body.city ?? null, req.body.streetRu ?? null, req.body.streetKk ?? null, req.body.house ?? null, req.body.residentialComplexRu ?? null, req.body.residentialComplexKk ?? null, req.body.zoneId ?? null, req.body.latitude ?? null, req.body.longitude ?? null, req.body.active ?? null],
    )).rows);
    if (!row) throw new ApiError(404, 'not_found', 'Дом не найден.');
    ok(res, row);
  }));

  router.post('/admin/checklist-templates', auth(['admin', 'superadmin']), asyncHandler(async (req, res) => {
    const row = first((await deps.db.query(
      `INSERT INTO checklist_templates (package_id, title_ru, title_kk, active)
       VALUES ($1,$2,$3,COALESCE($4,TRUE)) RETURNING *`,
      [req.body.packageId ?? null, req.body.titleRu, req.body.titleKk ?? null, req.body.active ?? true],
    )).rows);
    ok(res, row, 201);
  }));

  router.patch('/admin/checklist-templates/:id', auth(['admin', 'superadmin']), asyncHandler(async (req, res) => {
    const row = first((await deps.db.query(
      `UPDATE checklist_templates SET
       package_id=COALESCE($2,package_id), title_ru=COALESCE($3,title_ru), title_kk=COALESCE($4,title_kk), active=COALESCE($5,active)
       WHERE id=$1 RETURNING *`,
      [req.params.id, req.body.packageId ?? null, req.body.titleRu ?? null, req.body.titleKk ?? null, req.body.active ?? null],
    )).rows);
    if (!row) throw new ApiError(404, 'not_found', 'Шаблон чек-листа не найден.');
    ok(res, row);
  }));

  router.post('/admin/checklist-templates/:id/items', auth(['admin', 'superadmin']), asyncHandler(async (req, res) => {
    const row = first((await deps.db.query(
      `INSERT INTO checklist_template_items (template_id, title_ru, title_kk, sort_order)
       VALUES ($1,$2,$3,COALESCE($4,0)) RETURNING *`,
      [req.params.id, req.body.titleRu, req.body.titleKk ?? null, req.body.sortOrder ?? 0],
    )).rows);
    ok(res, row, 201);
  }));

  router.patch('/admin/checklist-template-items/:id', auth(['admin', 'superadmin']), asyncHandler(async (req, res) => {
    const row = first((await deps.db.query(
      `UPDATE checklist_template_items SET
       title_ru=COALESCE($2,title_ru), title_kk=COALESCE($3,title_kk), sort_order=COALESCE($4,sort_order)
       WHERE id=$1 RETURNING *`,
      [req.params.id, req.body.titleRu ?? null, req.body.titleKk ?? null, req.body.sortOrder ?? null],
    )).rows);
    if (!row) throw new ApiError(404, 'not_found', 'Пункт шаблона не найден.');
    ok(res, row);
  }));

  router.post('/admin/banners', auth(['admin', 'superadmin']), asyncHandler(async (req, res) => {
    const row = first((await deps.db.query(
      `INSERT INTO banners
       (title_ru, title_kk, description_ru, description_kk, image_file_id, target_type, target_value, placement, sort_order, active)
       VALUES ($1,$2,$3,$4,$5,COALESCE($6,'modal'),$7,COALESCE($8,'home_top'),COALESCE($9,0),COALESCE($10,TRUE))
       RETURNING *`,
      [req.body.titleRu, req.body.titleKk ?? null, req.body.descriptionRu ?? null, req.body.descriptionKk ?? null, req.body.imageFileId ?? null, req.body.targetType ?? 'modal', req.body.targetValue ?? null, req.body.placement ?? 'home_top', req.body.sortOrder ?? 0, req.body.active ?? true],
    )).rows);
    ok(res, row, 201);
  }));

  router.patch('/admin/banners/:id', auth(['admin', 'superadmin']), asyncHandler(async (req, res) => {
    const row = first((await deps.db.query(
      `UPDATE banners SET
       title_ru=COALESCE($2,title_ru), title_kk=COALESCE($3,title_kk),
       description_ru=COALESCE($4,description_ru), description_kk=COALESCE($5,description_kk),
       image_file_id=COALESCE($6,image_file_id), target_type=COALESCE($7,target_type), target_value=COALESCE($8,target_value),
       placement=COALESCE($9,placement), sort_order=COALESCE($10,sort_order), active=COALESCE($11,active), updated_at=NOW()
       WHERE id=$1 RETURNING *`,
      [req.params.id, req.body.titleRu ?? null, req.body.titleKk ?? null, req.body.descriptionRu ?? null, req.body.descriptionKk ?? null, req.body.imageFileId ?? null, req.body.targetType ?? null, req.body.targetValue ?? null, req.body.placement ?? null, req.body.sortOrder ?? null, req.body.active ?? null],
    )).rows);
    if (!row) throw new ApiError(404, 'not_found', 'Баннер не найден.');
    ok(res, row);
  }));

  router.post('/admin/promotions', auth(['admin', 'superadmin']), asyncHandler(async (req, res) => {
    const row = first((await deps.db.query(
      `INSERT INTO promotions
       (title_ru, title_kk, description_ru, description_kk, package_id, reward_type, reward_value, max_bonus_spend_percent, once_per_customer, banner_file_id, active, starts_at, ends_at)
       VALUES ($1,$2,$3,$4,$5,COALESCE($6,'fixed'),COALESCE($7,0),$8,COALESCE($9,FALSE),$10,COALESCE($11,TRUE),$12,$13)
       RETURNING *`,
      [req.body.titleRu, req.body.titleKk ?? null, req.body.descriptionRu ?? null, req.body.descriptionKk ?? null, req.body.packageId ?? null, req.body.rewardType ?? 'fixed', req.body.rewardValue ?? 0, req.body.maxBonusSpendPercent ?? null, req.body.oncePerCustomer ?? false, req.body.bannerFileId ?? null, req.body.active ?? true, req.body.startsAt ?? null, req.body.endsAt ?? null],
    )).rows);
    ok(res, row, 201);
  }));

  router.patch('/admin/promotions/:id', auth(['admin', 'superadmin']), asyncHandler(async (req, res) => {
    const row = first((await deps.db.query(
      `UPDATE promotions SET
       title_ru=COALESCE($2,title_ru), title_kk=COALESCE($3,title_kk),
       description_ru=COALESCE($4,description_ru), description_kk=COALESCE($5,description_kk),
       package_id=COALESCE($6,package_id), reward_type=COALESCE($7,reward_type),
       reward_value=COALESCE($8,reward_value), max_bonus_spend_percent=COALESCE($9,max_bonus_spend_percent),
       once_per_customer=COALESCE($10,once_per_customer), banner_file_id=COALESCE($11,banner_file_id),
       active=COALESCE($12,active), starts_at=COALESCE($13,starts_at), ends_at=COALESCE($14,ends_at), updated_at=NOW()
       WHERE id=$1 RETURNING *`,
      [
        req.params.id,
        req.body.titleRu ?? null,
        req.body.titleKk ?? null,
        req.body.descriptionRu ?? null,
        req.body.descriptionKk ?? null,
        req.body.packageId ?? null,
        req.body.rewardType ?? null,
        req.body.rewardValue ?? null,
        req.body.maxBonusSpendPercent ?? null,
        req.body.oncePerCustomer ?? null,
        req.body.bannerFileId ?? null,
        req.body.active ?? null,
        req.body.startsAt ?? null,
        req.body.endsAt ?? null,
      ],
    )).rows);
    if (!row) throw new ApiError(404, 'not_found', 'Акция не найдена.');
    ok(res, row);
  }));

  router.post('/admin/content-pages', auth(['admin', 'superadmin']), asyncHandler(async (req, res) => {
    const row = first((await deps.db.query(
      `INSERT INTO content_pages (slug, title_ru, title_kk, body_ru, body_kk, kind, active)
       VALUES ($1,$2,$3,$4,$5,COALESCE($6,'info'),COALESCE($7,TRUE))
       ON CONFLICT (slug) DO UPDATE SET
         title_ru=EXCLUDED.title_ru,
         title_kk=EXCLUDED.title_kk,
         body_ru=EXCLUDED.body_ru,
         body_kk=EXCLUDED.body_kk,
         kind=EXCLUDED.kind,
         active=EXCLUDED.active,
         updated_at=NOW()
       RETURNING *`,
      [
        req.body.slug,
        req.body.titleRu,
        req.body.titleKk ?? null,
        req.body.bodyRu,
        req.body.bodyKk ?? null,
        req.body.kind ?? 'info',
        req.body.active ?? true,
      ],
    )).rows);
    ok(res, row, 201);
  }));

  router.patch('/admin/content-pages/:slug', auth(['admin', 'superadmin']), asyncHandler(async (req, res) => {
    const row = first((await deps.db.query(
      `UPDATE content_pages SET
       title_ru=COALESCE($2,title_ru), title_kk=COALESCE($3,title_kk),
       body_ru=COALESCE($4,body_ru), body_kk=COALESCE($5,body_kk),
       kind=COALESCE($6,kind), active=COALESCE($7,active), updated_at=NOW()
       WHERE slug=$1 RETURNING *`,
      [
        req.params.slug,
        req.body.titleRu ?? null,
        req.body.titleKk ?? null,
        req.body.bodyRu ?? null,
        req.body.bodyKk ?? null,
        req.body.kind ?? null,
        req.body.active ?? null,
      ],
    )).rows);
    if (!row) throw new ApiError(404, 'not_found', 'Страница не найдена.');
    ok(res, row);
  }));

  router.patch('/admin/:section/:id/active', auth(['admin', 'superadmin']), asyncHandler(async (req, res) => {
    const activeTables: Record<string, string> = {
      packages: 'catalog_packages',
      addons: 'catalog_addons',
      addonGroups: 'addon_groups',
      banners: 'banners',
      promotions: 'promotions',
      contentPages: 'content_pages',
      zones: 'service_zones',
      houses: 'connected_houses',
    };
    const table = activeTables[String(req.params.section)];
    if (!table) throw new ApiError(404, 'not_found', 'Раздел не найден.');
    const active = req.body.active;
    if (typeof active !== 'boolean') throw new ApiError(400, 'invalid_request', 'Передайте active: true или false.');
    const updatedTables = new Set(['catalog_packages', 'catalog_addons', 'addon_groups', 'banners', 'promotions', 'content_pages']);
    const setClause = updatedTables.has(table) ? 'active=$2, updated_at=NOW()' : 'active=$2';
    const row = first((await deps.db.query(
      `UPDATE ${table} SET ${setClause} WHERE id=$1 RETURNING *`,
      [req.params.id, active],
    )).rows);
    if (!row) throw new ApiError(404, 'not_found', 'Запись не найдена.');
    ok(res, row);
  }));

  router.get('/admin/:section', auth(['admin', 'superadmin']), asyncHandler(async (req, res) => {
    const allowed: Record<string, { table: string; base?: string; search?: string[] }> = {
      orders: { table: 'service_orders' },
      payments: { table: 'payments' },
      complaints: { table: 'complaints', search: ['title', 'body'] },
      reviews: { table: 'reviews', search: ['comment'] },
      checklistReports: { table: 'checklist_reports' },
      photoReports: { table: 'photo_reports' },
      cleaners: { table: 'app_users', base: `role='cleaner'`, search: ['full_name', 'phone', 'email'] },
      users: { table: 'app_users', base: `role='customer'`, search: ['full_name', 'phone', 'email'] },
      preorders: { table: 'preorders' },
      quality: { table: 'quality_check_requests' },
      addressRequests: { table: 'service_address_requests', search: ['city', 'residential_complex', 'address', 'entrance', 'apartment'] },
      payouts: { table: 'payouts' },
      audit: { table: 'audit_logs', search: ['action', 'entity_type', 'entity_id'] },
      zones: { table: 'service_zones', search: ['name_ru', 'name_kk', 'city'] },
      cities: { table: 'city_directory', search: ['name_ru', 'name_kk', 'region'] },
      houses: { table: 'connected_houses', search: ['city', 'street_ru', 'street_kk', 'house', 'residential_complex_ru', 'residential_complex_kk'] },
      checklistTemplates: { table: 'checklist_templates', search: ['title_ru', 'title_kk'] },
      packages: { table: 'catalog_packages', search: ['name_ru', 'name_kk', 'description_ru', 'description_kk'] },
      addons: { table: 'catalog_addons', search: ['title_ru', 'title_kk', 'description_ru', 'description_kk', 'hint_ru', 'hint_kk'] },
      addonGroups: { table: 'addon_groups', search: ['title_ru', 'title_kk'] },
      banners: { table: 'banners', search: ['title_ru', 'title_kk', 'description_ru', 'description_kk'] },
      promotions: { table: 'promotions', search: ['title_ru', 'title_kk', 'description_ru', 'description_kk'] },
      promotionRedemptions: { table: 'promotion_redemptions' },
      contentPages: { table: 'content_pages', search: ['slug', 'title_ru', 'title_kk', 'body_ru', 'body_kk', 'kind'] },
      videoViews: { table: 'video_views', search: ['video_id', 'audience_type'] },
    };
    const section = String(req.params.section);
    const config = allowed[section];
    if (!config) throw new ApiError(404, 'not_found', 'Раздел не найден.');
    const { limit, offset } = pageParams(req.query);
    const specialList = buildAdminListQuery(section, req.query, limit, offset);
    if (specialList) {
      ok(res, (await deps.db.query(specialList.sql, specialList.values)).rows);
      return;
    }
    const filters: string[] = [];
    const values: unknown[] = [];
    if (config.base) filters.push(config.base);
    if (req.query.status) {
      values.push(String(req.query.status));
      filters.push(`status::text=$${values.length}`);
    }
    if (req.query.dateFrom) {
      values.push(String(req.query.dateFrom));
      filters.push(`created_at >= $${values.length}::timestamptz`);
    }
    if (req.query.dateTo) {
      values.push(String(req.query.dateTo));
      filters.push(`created_at <= $${values.length}::timestamptz`);
    }
    if (req.query.search && config.search?.length) {
      values.push(`%${String(req.query.search)}%`);
      filters.push(`(${config.search.map((column) => `${column} ILIKE $${values.length}`).join(' OR ')})`);
    }
    values.push(limit, offset);
    const where = filters.length ? `WHERE ${filters.join(' AND ')}` : '';
    ok(res, (await deps.db.query(
      `SELECT * FROM ${config.table} ${where} ORDER BY created_at DESC LIMIT $${values.length - 1} OFFSET $${values.length}`,
      values,
    )).rows);
  }));

  return router;
}

function buildAdminListQuery(section: string, query: any, limit: number, offset: number) {
  const values: unknown[] = [];
  const filters: string[] = [];
  const addCommon = (alias: string, searchColumns: string[] = []) => {
    if (query.status) {
      values.push(String(query.status));
      filters.push(`${alias}.status::text=$${values.length}`);
    }
    if (query.dateFrom) {
      values.push(String(query.dateFrom));
      filters.push(`${alias}.created_at >= $${values.length}::timestamptz`);
    }
    if (query.dateTo) {
      values.push(String(query.dateTo));
      filters.push(`${alias}.created_at <= $${values.length}::timestamptz`);
    }
    if (query.search && searchColumns.length) {
      values.push(`%${String(query.search)}%`);
      filters.push(`(${searchColumns.map((column) => `${column} ILIKE $${values.length}`).join(' OR ')})`);
    }
  };
  const done = (select: string, order = 'created_at DESC') => {
    values.push(limit, offset);
    const where = filters.length ? `WHERE ${filters.join(' AND ')}` : '';
    return {
      sql: `${select} ${where} ORDER BY ${order} LIMIT $${values.length - 1} OFFSET $${values.length}`,
      values,
    };
  };
  if (section === 'orders') {
    addCommon('o', ['o.numeric_id::text', 'cu.full_name', 'cu.phone', 'cl.full_name', 'cl.phone', 'ca.street', 'ca.house']);
    return done(
      `SELECT o.*, cu.full_name AS customer_name, cu.phone AS customer_phone,
              cl.full_name AS cleaner_name, cl.phone AS cleaner_phone,
              ca.city, ca.settlement, ca.street, ca.house, ca.apartment, ca.verified_area,
              pkg.name_ru AS package_name_ru
       FROM service_orders o
       JOIN app_users cu ON cu.id=o.customer_id
       LEFT JOIN app_users cl ON cl.id=o.cleaner_id
       LEFT JOIN customer_addresses ca ON ca.id=o.address_id
       LEFT JOIN catalog_packages pkg ON pkg.id=o.package_id`,
      'o.created_at DESC',
    );
  }
  if (section === 'payments') {
    addCommon('p', ['p.numeric_id::text', 'u.full_name', 'u.phone', 'o.numeric_id::text', 'pkg.name_ru']);
    return done(
      `SELECT p.*, u.full_name AS customer_name, u.phone AS customer_phone,
              o.numeric_id AS order_number, cp.id AS package_purchase_id, pkg.name_ru AS package_name_ru,
              ca.city, ca.settlement, ca.street, ca.house, ca.apartment, ca.area, ca.verified_area
       FROM payments p
       LEFT JOIN app_users u ON u.id=p.customer_id
       LEFT JOIN service_orders o ON o.id=p.order_id
       LEFT JOIN customer_packages cp ON cp.id=p.customer_package_id
       LEFT JOIN catalog_packages pkg ON pkg.id=COALESCE(cp.package_id,o.package_id)
       LEFT JOIN customer_addresses ca ON ca.id=COALESCE(cp.address_id,o.address_id)`,
      'p.created_at DESC',
    );
  }
  if (section === 'preorders') {
    addCommon('pr', ['u.full_name', 'u.phone', 'pkg.name_ru', 'ca.street', 'ca.house']);
    return done(
      `SELECT pr.*, u.full_name AS customer_name, u.phone AS customer_phone,
              ca.city, ca.settlement, ca.street, ca.house, ca.apartment,
              pkg.name_ru AS package_name_ru, pay.status AS payment_status, pay.amount AS payment_amount
       FROM preorders pr
       JOIN app_users u ON u.id=pr.customer_id
       LEFT JOIN customer_addresses ca ON ca.id=pr.address_id
       LEFT JOIN catalog_packages pkg ON pkg.id=pr.package_id
       LEFT JOIN payments pay ON pay.id=pr.payment_id`,
      'pr.created_at DESC',
    );
  }
  if (section === 'quality') {
    addCommon('q', ['u.full_name', 'u.phone', 'ca.street', 'ca.house']);
    return done(
      `SELECT q.*, u.full_name AS customer_name, u.phone AS customer_phone,
              ca.city, ca.settlement, ca.street, ca.house, ca.apartment, ca.area, ca.verified_area,
              cp.id AS package_purchase_id, pkg.name_ru AS package_name_ru,
              f.public_url AS document_url, f.public_url AS "areaTechnicalPlanUrl"
       FROM quality_check_requests q
       JOIN app_users u ON u.id=q.customer_id
       LEFT JOIN customer_addresses ca ON ca.id=q.address_id
       LEFT JOIN files f ON f.id=q.document_file_id
       LEFT JOIN customer_packages cp ON cp.id=q.customer_package_id
       LEFT JOIN catalog_packages pkg ON pkg.id=cp.package_id`,
      'q.created_at DESC',
    );
  }
  if (section === 'payouts') {
    addCommon('p', ['u.full_name', 'u.phone', 'u.numeric_id::text']);
    return done(
      `SELECT p.*, u.numeric_id AS cleaner_number, u.full_name AS cleaner_name, u.phone AS cleaner_phone,
              cp.city, cp.registration_status, cp.verification_status
       FROM payouts p
       JOIN app_users u ON u.id=p.cleaner_id
       LEFT JOIN cleaner_profiles cp ON cp.user_id=u.id`,
      'p.created_at DESC',
    );
  }
  if (section === 'checklistReports') {
    addCommon('cr', ['o.numeric_id::text', 'cu.full_name', 'cu.phone', 'cl.full_name', 'cl.phone', 'pkg.name_ru']);
    return done(
      `SELECT cr.*, o.numeric_id AS order_number, o.scheduled_date, o.start_time, o.end_time, o.status AS order_status,
              cu.full_name AS customer_name, cu.phone AS customer_phone,
              cl.full_name AS cleaner_name, cl.phone AS cleaner_phone,
              pkg.name_ru AS package_name_ru
       FROM checklist_reports cr
       JOIN service_orders o ON o.id=cr.order_id
       JOIN app_users cu ON cu.id=o.customer_id
       LEFT JOIN app_users cl ON cl.id=cr.cleaner_id
       LEFT JOIN catalog_packages pkg ON pkg.id=o.package_id`,
      'cr.created_at DESC',
    );
  }
  if (section === 'checklistTemplates') {
    addCommon('ct', ['ct.title_ru', 'ct.title_kk', 'pkg.name_ru']);
    return done(
      `SELECT ct.*, pkg.name_ru AS package_name_ru,
              COALESCE(
                json_agg(
                  json_build_object(
                    'id', cti.id,
                    'title_ru', cti.title_ru,
                    'title_kk', cti.title_kk,
                    'sort_order', cti.sort_order
                  )
                  ORDER BY cti.sort_order ASC, cti.id ASC
                ) FILTER (WHERE cti.id IS NOT NULL),
                '[]'::json
              ) AS items
       FROM checklist_templates ct
       LEFT JOIN catalog_packages pkg ON pkg.id=ct.package_id
       LEFT JOIN checklist_template_items cti ON cti.template_id=ct.id
       GROUP BY ct.id, pkg.name_ru`,
      'ct.title_ru ASC',
    );
  }
  if (section === 'audit') {
    addCommon('al', ['al.action', 'al.entity_type', 'al.entity_id', 'u.full_name', 'u.phone', 'u.email', 'u.numeric_id::text']);
    return done(
      `SELECT al.*, u.numeric_id AS actor_number, u.full_name AS actor_name,
              u.phone AS actor_phone, u.email AS actor_email, u.role AS actor_role
       FROM audit_logs al
       LEFT JOIN app_users u ON u.id=al.actor_id`,
      'al.created_at DESC',
    );
  }
  if (section === 'users') {
    addCommon('u', ['u.numeric_id::text', 'u.full_name', 'u.phone', 'u.email']);
    filters.push(`u.role='customer'`);
    values.push(limit, offset);
    const where = filters.length ? `WHERE ${filters.join(' AND ')}` : '';
    return {
      sql: `SELECT u.id, u.numeric_id, u.full_name, u.phone, u.email, u.status, u.rating, u.bonus_balance, u.created_at,
                   COUNT(DISTINCT o.id)::int AS orders_count,
                   COUNT(DISTINCT pay.id)::int AS payments_count
            FROM app_users u
            LEFT JOIN service_orders o ON o.customer_id=u.id
            LEFT JOIN payments pay ON pay.customer_id=u.id
            ${where}
            GROUP BY u.id
            ORDER BY u.created_at DESC LIMIT $${values.length - 1} OFFSET $${values.length}`,
      values,
    };
  }
  if (section === 'cleaners') {
    addCommon('u', ['u.numeric_id::text', 'u.full_name', 'u.phone', 'u.email']);
    filters.push(`u.role='cleaner'`);
    values.push(limit, offset);
    const where = filters.length ? `WHERE ${filters.join(' AND ')}` : '';
    return {
      sql: `SELECT u.id, u.numeric_id, u.full_name, u.phone, u.email, u.status, u.rating, u.created_at,
                   cp.city, cp.registration_status, cp.verification_status, cp.verified_at,cp.work_start_date,
                   (SELECT COALESCE(jsonb_agg(jsonb_build_object('id',d.id,'type',d.type,'url',f.public_url,'status',d.status) ORDER BY d.created_at DESC),'[]'::jsonb)
                    FROM cleaner_documents d LEFT JOIN files f ON f.id=d.file_id WHERE d.cleaner_id=u.id) AS documents,
                   COUNT(DISTINCT o.id)::int AS orders_count
            FROM app_users u
            LEFT JOIN cleaner_profiles cp ON cp.user_id=u.id
            LEFT JOIN service_orders o ON o.cleaner_id=u.id
            ${where}
            GROUP BY u.id, cp.user_id
            ORDER BY u.created_at DESC LIMIT $${values.length - 1} OFFSET $${values.length}`,
      values,
    };
  }
  return null;
}

function extensionFromMime(mime: string): string {
  if (mime === 'image/jpeg') return '.jpg';
  if (mime === 'image/png') return '.png';
  if (mime === 'image/webp') return '.webp';
  if (mime === 'application/pdf') return '.pdf';
  return '';
}

function addMinutes(time: string, minutes: number): string {
  const [h, m] = time.split(':').map(Number);
  const total = h * 60 + m + minutes;
  return `${String(Math.floor(total / 60)).padStart(2, '0')}:${String(total % 60).padStart(2, '0')}`;
}

async function readAppSettings(db: Database): Promise<Record<string, any>> {
  return (await db.query<{ key: string; value: any }>(`SELECT key, value FROM app_settings`)).rows
    .reduce((acc: Record<string, any>, row) => ({ ...acc, [row.key]: row.value }), {});
}

async function versionFor(db: Database, key: string, sql: string) {
  const row = first<{ count: string; updated_at: string | null }>((await db.query(sql)).rows);
  const payload = { count: Number(row?.count ?? 0), updatedAt: row?.updated_at ?? null };
  return {
    key,
    ...payload,
    version: createHash('sha256').update(JSON.stringify(payload)).digest('hex').slice(0, 16),
  };
}

async function buildAppVersions(db: Database) {
  const sections = await Promise.all([
    versionFor(db, 'settings', `SELECT COUNT(*)::text AS count, MAX(updated_at)::text AS updated_at FROM app_settings`),
    versionFor(db, 'translations', `SELECT COUNT(*)::text AS count, MAX(updated_at)::text AS updated_at FROM translations`),
    versionFor(db, 'packages', `SELECT COUNT(*)::text AS count, MAX(updated_at)::text AS updated_at FROM catalog_packages WHERE active=TRUE`),
    versionFor(db, 'addons', `SELECT COUNT(*)::text AS count, MAX(updated_at)::text AS updated_at FROM catalog_addons WHERE active=TRUE`),
    versionFor(db, 'addonGroups', `SELECT COUNT(*)::text AS count, MAX(updated_at)::text AS updated_at FROM addon_groups WHERE active=TRUE`),
    versionFor(db, 'banners', `SELECT COUNT(*)::text AS count, MAX(updated_at)::text AS updated_at FROM banners WHERE active=TRUE`),
    versionFor(db, 'promotions', `SELECT COUNT(*)::text AS count, MAX(updated_at)::text AS updated_at FROM promotions WHERE active=TRUE`),
    versionFor(db, 'contentPages', `SELECT COUNT(*)::text AS count, MAX(updated_at)::text AS updated_at FROM content_pages WHERE active=TRUE`),
  ]);
  const bySection = sections.reduce<Record<string, Omit<(typeof sections)[number], 'key'>>>((acc, section) => {
    const { key, ...value } = section;
    acc[key] = value;
    return acc;
  }, {});
  return {
    generatedAt: new Date().toISOString(),
    version: createHash('sha256').update(JSON.stringify(bySection)).digest('hex').slice(0, 16),
    sections: bySection,
  };
}

export function buildRuntimeConfig(settings: Record<string, any>) {
  const deepMerge = <T extends Record<string, any>>(defaults: T, override: unknown): T => {
    if (!override || typeof override !== 'object' || Array.isArray(override)) return defaults;
    const out: Record<string, any> = { ...defaults };
    for (const [key, value] of Object.entries(override as Record<string, any>)) {
      if (value === undefined) continue;
      out[key] = value && typeof value === 'object' && !Array.isArray(value) && defaults[key] && typeof defaults[key] === 'object' && !Array.isArray(defaults[key])
        ? deepMerge(defaults[key], value)
        : value;
    }
    return out as T;
  };
  const defaultCustomerTierRules = [
    { tier: 'NEWBIE', labelRu: 'Наш любимый Новичок', labelKk: 'Біздің сүйікті Жаңадан бастаушы', minMonthlySpent: 0, maxMonthlySpent: 100000, discountPercent: 0, sortOrder: 0 },
    { tier: 'CLEANSTER', labelRu: 'Наш любимый Чистюля', labelKk: 'Біздің сүйікті Тазалық жанашыры', minMonthlySpent: 100000, maxMonthlySpent: 500000, discountPercent: 5, sortOrder: 1 },
    { tier: 'GURU', labelRu: 'Гуру чистоты', labelKk: 'Тазалық гуруы', minMonthlySpent: 500000, maxMonthlySpent: 1500000, discountPercent: 10, sortOrder: 2 },
    { tier: 'GOD', labelRu: 'Бог чистоты', labelKk: 'Тазалық құдайы', minMonthlySpent: 1500000, maxMonthlySpent: null, discountPercent: 10, sortOrder: 3 },
  ];
  const normalizeCustomerTierRules = (raw: unknown) => {
    const source = Array.isArray(raw) ? raw : defaultCustomerTierRules;
    const normalized = source
      .map((item: any, index: number) => {
        const fallback = defaultCustomerTierRules[index] ?? defaultCustomerTierRules.at(-1)!;
        const minMonthlySpent = Number(item?.minMonthlySpent ?? item?.minSpent ?? fallback.minMonthlySpent);
        const maxRaw = item?.maxMonthlySpent ?? item?.maxSpent ?? fallback.maxMonthlySpent;
        const maxMonthlySpent = maxRaw === null || maxRaw === undefined || maxRaw === '' ? null : Number(maxRaw);
        return {
          tier: String(item?.tier ?? fallback.tier).trim().toUpperCase(),
          labelRu: String(item?.labelRu ?? item?.label ?? fallback.labelRu),
          labelKk: String(item?.labelKk ?? fallback.labelKk),
          minMonthlySpent: Number.isFinite(minMonthlySpent) ? Math.max(0, minMonthlySpent) : fallback.minMonthlySpent,
          maxMonthlySpent: maxMonthlySpent !== null && Number.isFinite(maxMonthlySpent) ? Math.max(0, maxMonthlySpent) : null,
          discountPercent: Math.min(100, Math.max(0, Number(item?.discountPercent ?? fallback.discountPercent) || 0)),
          sortOrder: Number(item?.sortOrder ?? index),
        };
      })
      .filter((item) => item.tier && item.labelRu)
      .sort((a, b) => a.sortOrder - b.sortOrder || a.minMonthlySpent - b.minMonthlySpent);
    return normalized.length ? normalized : defaultCustomerTierRules;
  };
  const featureFlags = deepMerge({
    preordersEnabled: true,
    qualityCheckEnabled: true,
    onlinePaymentEnabled: true,
    kaspiPaymentEnabled: true,
    bonusPaymentEnabled: true,
    cleanerManualAssignmentEnabled: true,
    inAppTrainingEnabled: true,
  }, settings.featureFlags);
  const localization = deepMerge({
    enabledLanguages: settings.enabledLanguages ?? ['ru', 'kk'],
    defaultLanguage: settings.defaultLanguage ?? 'ru',
    translationMode: {
      liveSwitch: true,
      adminEditable: true,
      fallbackLanguage: 'ru',
      dynamicDataLocales: true,
    },
  }, settings.localization ?? { translationMode: settings.translationMode });
  const assignmentRules = deepMerge({
    requireAvailableCleanerForSlot: true,
    useCleanerLocationPriority: true,
    preventTimeOverlap: true,
    reassignOnCleanerConflict: true,
    respectMonthlyAreaLimit: true,
    respectDailyWorkMinutes: true,
    allowOverAreaLimitIfTimeAvailable: true,
  }, settings.assignmentRules);
  const orderRules = deepMerge({
    hidePreorderButtonAfterPreorderOrPackage: true,
    preorderMovesToOrdersOnlyAfterStartAndPayment: true,
    cancelRefundsBonuses: true,
    cancelRemovesPaidAddons: true,
    suppressDuplicateSearchingCleanerNotification: true,
    hideCleanerEarningsFromCleanerApp: true,
    showOnlyAvailableCleanerSlots: true,
    routeHomeEmptyOrderCardToBooking: true,
    blockCleaningOrderUntilPackagePaid: true,
    keepPreordersOutOfOrdersUntilPaid: true,
  }, settings.orderRules);
  const paymentFlow = deepMerge({
    afterInvoiceAction: 'home',
    showPackagePurchaseButtonUntilPaid: true,
    showCleaningOrderButtonOnlyWithAvailableCleanings: true,
    requireBonusCheckbox: true,
    hideExternalInvoiceForZeroPayable: true,
    invoiceAmountUsesPayableAfterBonus: true,
    createInvoiceOnlyAfterExplicitPaymentChoice: true,
    showPaymentBreakdownEverywhere: true,
  }, settings.paymentFlow);
  const addressSearch = deepMerge({
    primaryProvider: 'osm',
    fallbackProvider: 'yandex',
    fallbackOnlyOnEmptyOrError: true,
    cityFromGeolocation: true,
    radiusKm: 50,
    limit: 10,
    excludeOrganizations: true,
    includeResidentialComplexes: true,
    includeStreets: true,
    fillDestinationAutomatically: false,
    fromFieldFormat: 'street_house_settlement',
  }, settings.addressSearch);
  const uiBehavior = deepMerge({
    customerHomeOrderCardAction: 'booking',
    addonSelectionAfterApply: 'pending_orders',
    packageSelectionPosition: 'center',
    bannerFit: 'contain',
    autoRotateImportantBanners: true,
    bottomNavEvenSpacing: true,
    stickyAddonButtons: true,
    noEllipsisForImportantLabels: true,
    hideBackButtonOnBottomTabs: true,
  }, settings.uiBehavior);
  const validationRules = deepMerge({
    areaInput: 'decimal_round_up',
    requireAreaBeforePackage: true,
    requireQualityCheckPhotoAndArea: true,
    addressSearchLimit: 10,
    addressSearchRadiusKm: 50,
    blockQualitySubmitUntilComplete: true,
  }, settings.validationRules);
  const adminNotificationRules = deepMerge({
    enabled: true,
    events: ['new_user', 'new_cleaner', 'new_order', 'new_payment', 'quality_check', 'preorder', 'complaint', 'review', 'payout'],
    deepLinks: true,
    routeByTargetType: true,
  }, settings.adminNotificationRules);
  const contentRules = deepMerge({
    privacyPolicyEditable: true,
    offerEditable: true,
    bannerDetailsModal: true,
    importantBannersAutoRotate: true,
    hideRawImageUrlInModals: true,
  }, settings.contentRules);
  const trainingFlow = deepMerge({
    enabled: true,
    backendStepsEditable: true,
    interactiveMode: true,
    testOrderMode: true,
    resetKey: 'training_v2',
  }, settings.trainingFlow);
  const screenRules = deepMerge({
    ordersTabs: ['orders', 'package_purchases', 'cleaning_visits'],
    adminSortDefault: 'newest_first',
    adminDateFiltersEnabled: true,
    adminShowNumericIdsOnly: true,
    userIdsMode: 'sequential_numeric',
  }, settings.screenRules);
  const customerTierRules = normalizeCustomerTierRules(settings.customerTierRules);
  return {
    rules: {
      minBookingDate: settings.minBookingDate ?? null,
      qualityCheckHours: settings.qualityCheckHours ?? 48,
      bonusPaymentEnabled: settings.bonusPaymentEnabled ?? true,
      defaultBonusMaxPercent: settings.defaultBonusMaxPercent ?? 50,
      customerTierRules,
    },
    backendDriven: {
      featureFlags,
      localization,
      booking: {
        minBookingDate: settings.minBookingDate ?? null,
        slotStartTimes: settings.slotStartTimes ?? ['08:00', '10:00', '12:00', '14:00', '16:00'],
        requireAvailableCleaner: settings.requireAvailableCleaner ?? true,
        allowCustomTime: settings.allowCustomTime ?? false,
        scrollToPendingAfterAddonSelection: settings.scrollToPendingAfterAddonSelection ?? true,
        cleanerOfferTtlMinutes: settings.cleanerOfferTtlMinutes ?? 2,
        cleanerQuietHoursEnabled: settings.cleanerQuietHoursEnabled ?? false,
        cleanerQuietHoursStart: settings.cleanerQuietHoursStart ?? '23:00',
        cleanerQuietHoursEnd: settings.cleanerQuietHoursEnd ?? '07:00',
      },
      assignmentRules,
      pricing: {
        baseCleaningMinutes: settings.baseCleaningMinutes ?? 120,
        minutesPerM2: settings.minutesPerM2 ?? 1.2,
        defaultBonusMaxPercent: settings.defaultBonusMaxPercent ?? 50,
        allowBonusForPackagePurchase: settings.allowBonusForPackagePurchase ?? false,
        skipZeroAmountInvoice: settings.skipZeroAmountInvoice ?? true,
      },
      orderRules,
      qualityCheck: {
        hours: settings.qualityCheckHours ?? 48,
        requiredAfterPackagePurchase: settings.qualityCheckRequiredAfterPackagePurchase ?? true,
        notificationTitleRu: settings.qualityCheckNotificationTitleRu ?? 'Назначена проверка площади',
        notificationBodyRu: settings.qualityCheckNotificationBodyRu
          ?? 'В течение 48 часов отдел контроля качества приедет к вам для проверки площади. Также вы можете пройти проверку в приложении, загрузив план квартиры.',
        notificationTitleKk: settings.qualityCheckNotificationTitleKk ?? 'Ауданды тексеру тағайындалды',
        notificationBodyKk: settings.qualityCheckNotificationBodyKk
          ?? '48 сағат ішінде сапаны бақылау бөлімі пәтер ауданын тексеру үшін келеді. Сонымен қатар қосымшада пәтер жоспарын жүктеп, тексеруден өте аласыз.',
      },
      navigation: {
        customerTabs: settings.customerTabs ?? ['home', 'orders', 'profile', 'notifications', 'settings'],
        cleanerTabs: settings.cleanerTabs ?? ['home', 'calendar', 'orders', 'messages', 'profile'],
      },
      paymentFlow,
      addressSearch,
      adminNotificationRules,
      uiBehavior,
      contentRules,
      validationRules,
      trainingFlow,
      screenRules,
      customerTierRules,
      errorMessages: settings.errorMessages ?? {},
      appText: settings.appText ?? {},
    },
  };
}

export function buildRuntimeSettingsMeta(settings: Record<string, any>) {
  const runtime = buildRuntimeConfig(settings);
  const section = (key: string, titleRu: string, titleKk: string, fields: Array<Record<string, unknown>>) => ({
    key,
    titleRu,
    titleKk,
    value: (runtime.backendDriven as Record<string, unknown>)[key] ?? settings[key] ?? null,
    fields,
  });
  return {
    version: createHash('sha256').update(JSON.stringify(runtime.backendDriven)).digest('hex').slice(0, 16),
    sections: [
      section('paymentFlow', 'Оплата', 'Төлем', [
        { key: 'afterInvoiceAction', type: 'select', options: ['home', 'orders', 'payments'], ru: 'Куда вести после выставления счета' },
        { key: 'requireBonusCheckbox', type: 'boolean', ru: 'Требовать галочку для оплаты бонусами' },
        { key: 'invoiceAmountUsesPayableAfterBonus', type: 'boolean', ru: 'Выставлять счет только на остаток после бонусов' },
        { key: 'hideExternalInvoiceForZeroPayable', type: 'boolean', ru: 'Не создавать внешний счет при оплате 100% бонусами' },
        { key: 'showPaymentBreakdownEverywhere', type: 'boolean', ru: 'Показывать мини-чек во всех оплатах' },
      ]),
      section('orderRules', 'Заказы', 'Тапсырыстар', [
        { key: 'showOnlyAvailableCleanerSlots', type: 'boolean', ru: 'Показывать только время со свободной уборщицей' },
        { key: 'cancelRefundsBonuses', type: 'boolean', ru: 'Возвращать бонусы при отмене' },
        { key: 'cancelRemovesPaidAddons', type: 'boolean', ru: 'Удалять оплаченные допы при отмене заказа' },
        { key: 'hideCleanerEarningsFromCleanerApp', type: 'boolean', ru: 'Скрывать заработок у уборщицы' },
        { key: 'keepPreordersOutOfOrdersUntilPaid', type: 'boolean', ru: 'Не переносить предварительные записи в заказы до оплаты' },
      ]),
      section('assignmentRules', 'Назначение уборщиц', 'Орындаушыларды тағайындау', [
        { key: 'requireAvailableCleanerForSlot', type: 'boolean', ru: 'Требовать свободную уборщицу для слота' },
        { key: 'useCleanerLocationPriority', type: 'boolean', ru: 'Учитывать близость уборщицы к адресу' },
        { key: 'preventTimeOverlap', type: 'boolean', ru: 'Запрещать пересечение заказов по времени' },
        { key: 'reassignOnCleanerConflict', type: 'boolean', ru: 'Переназначать при конфликте времени' },
        { key: 'allowOverAreaLimitIfTimeAvailable', type: 'boolean', ru: 'Разрешать превышение м2, если хватает времени' },
      ]),
      section('addressSearch', 'Поиск адресов', 'Мекенжай іздеу', [
        { key: 'primaryProvider', type: 'select', options: ['osm', 'yandex'], ru: 'Основной провайдер' },
        { key: 'fallbackProvider', type: 'select', options: ['none', 'osm', 'yandex'], ru: 'Резервный провайдер' },
        { key: 'fallbackOnlyOnEmptyOrError', type: 'boolean', ru: 'Включать резерв только если нет результата или ошибка' },
        { key: 'radiusKm', type: 'number', min: 1, max: 100, ru: 'Радиус поиска, км' },
        { key: 'limit', type: 'number', min: 1, max: 20, ru: 'Количество подсказок' },
        { key: 'excludeOrganizations', type: 'boolean', ru: 'Не показывать заведения' },
        { key: 'includeResidentialComplexes', type: 'boolean', ru: 'Искать ЖК' },
      ]),
      section('uiBehavior', 'Поведение интерфейса', 'Интерфейс әрекеті', [
        { key: 'addonSelectionAfterApply', type: 'select', options: ['pending_orders', 'calendar'], ru: 'Что показывать после выбора допов' },
        { key: 'packageSelectionPosition', type: 'select', options: ['center', 'top'], ru: 'Позиция выбранного пакета' },
        { key: 'bannerFit', type: 'select', options: ['contain', 'cover'], ru: 'Отображение баннеров' },
        { key: 'stickyAddonButtons', type: 'boolean', ru: 'Фиксировать кнопки в модалке допов' },
        { key: 'noEllipsisForImportantLabels', type: 'boolean', ru: 'Не обрезать важные тексты' },
      ]),
      section('trainingFlow', 'Обучение', 'Оқыту', [
        { key: 'enabled', type: 'boolean', ru: 'Включить обучение' },
        { key: 'backendStepsEditable', type: 'boolean', ru: 'Шаги обучения редактируются на backend' },
        { key: 'interactiveMode', type: 'boolean', ru: 'Интерактивное обучение с подсветкой кнопок' },
        { key: 'testOrderMode', type: 'boolean', ru: 'Тестовый заказ в обучении не попадает уборщицам' },
        { key: 'resetKey', type: 'string', ru: 'Ключ версии обучения' },
      ]),
      section('screenRules', 'Экраны админки и приложения', 'Экран ережелері', [
        { key: 'ordersTabs', type: 'string_array', ru: 'Вкладки раздела заказов' },
        { key: 'adminSortDefault', type: 'select', options: ['newest_first', 'oldest_first'], ru: 'Сортировка в админке по умолчанию' },
        { key: 'adminDateFiltersEnabled', type: 'boolean', ru: 'Фильтры дат в админке' },
        { key: 'adminShowNumericIdsOnly', type: 'boolean', ru: 'Показывать числовые ID вместо UUID' },
      ]),
      section('customerTierRules', 'Статусы клиентов', 'Клиент мәртебелері', [
        { key: 'tier', type: 'string', ru: 'Код статуса' },
        { key: 'labelRu', type: 'string', ru: 'Название RU' },
        { key: 'labelKk', type: 'string', ru: 'Название KK' },
        { key: 'minMonthlySpent', type: 'number', min: 0, ru: 'Сумма от, ₸/месяц' },
        { key: 'maxMonthlySpent', type: 'number', min: 0, nullable: true, ru: 'Сумма до, ₸/месяц' },
        { key: 'discountPercent', type: 'number', min: 0, max: 100, ru: 'Скидка статуса, %' },
        { key: 'sortOrder', type: 'number', ru: 'Порядок' },
      ]),
    ],
  };
}

async function ensurePackageQualityCheck(db: Database, notifications: NotificationService, customerPackageId: string) {
  const settings = await readAppSettings(db);
  if (settings.qualityCheckRequiredAfterPackagePurchase === false) return null;
  const row = first<{
    customer_id: string;
    address_id: string | null;
    area: string | null;
    verified_area: string | null;
  }>((await db.query(
    `SELECT cp.customer_id, cp.address_id, ca.area, ca.verified_area
     FROM customer_packages cp
     LEFT JOIN customer_addresses ca ON ca.id=cp.address_id
     WHERE cp.id=$1`,
    [customerPackageId],
  )).rows);
  if (!row || row.verified_area) return null;
  const existing = first((await db.query(
    `SELECT * FROM quality_check_requests
     WHERE customer_package_id=$1 AND status IN ('pending','scheduled')
     ORDER BY created_at DESC LIMIT 1`,
    [customerPackageId],
  )).rows);
  const qualityCheck = existing ?? first((await db.query(
    `INSERT INTO quality_check_requests (customer_id, address_id, customer_package_id, requested_area, status)
     VALUES ($1,$2,$3,$4,'pending')
     RETURNING *`,
    [row.customer_id, row.address_id, customerPackageId, row.area],
  )).rows);
  if (!qualityCheck) return null;
  await notifications.create({
    userId: row.customer_id,
    titleRu: settings.qualityCheckNotificationTitleRu ?? 'Назначена проверка площади',
    titleKk: settings.qualityCheckNotificationTitleKk ?? 'Ауданды тексеру тағайындалды',
    bodyRu: settings.qualityCheckNotificationBodyRu
      ?? 'В течение 48 часов отдел контроля качества приедет к вам для проверки площади. Также вы можете пройти проверку в приложении, загрузив план квартиры.',
    bodyKk: settings.qualityCheckNotificationBodyKk
      ?? '48 сағат ішінде сапаны бақылау бөлімі пәтер ауданын тексеру үшін келеді. Сонымен қатар қосымшада пәтер жоспарын жүктеп, тексеруден өте аласыз.',
    targetType: 'quality_check',
    targetId: (qualityCheck as any).id,
    dedupeKey: `quality-check-package-${customerPackageId}`,
  });
  await notifications.createAdminEvent({
    event: 'quality_check',
    titleRu: 'Новая проверка площади',
    titleKk: 'Жаңа аудан тексерісі',
    bodyRu: 'Клиент оплатил пакет, требуется проверка площади.',
    bodyKk: 'Клиент пакет төледі, ауданын тексеру қажет.',
    targetType: 'quality_check',
    targetId: (qualityCheck as any).id,
    dedupeKey: `admin-quality-check-package-${customerPackageId}`,
  });
  return qualityCheck;
}

async function estimateCleaningDurationMinutes(
  db: Database,
  addressId?: string,
  addons: Array<{ duration_minutes?: number }> = [],
): Promise<number> {
  const settings = await readAppSettings(db);
  const baseMinutes = Number(settings.baseCleaningMinutes ?? 120);
  const minutesPerM2 = Number(settings.minutesPerM2 ?? 1.2);
  const address = addressId
    ? (await db.query<{ area: string; verified_area: string | null }>(
      `SELECT area, verified_area FROM customer_addresses WHERE id=$1`,
      [addressId],
    )).rows[0]
    : null;
  const area = Number(address?.verified_area ?? address?.area ?? 50);
  const addonMinutes = addons.reduce((sum, addon) => sum + Number(addon.duration_minutes ?? 0), 0);
  return Math.max(30, Math.round(baseMinutes + area * minutesPerM2 + addonMinutes));
}

async function initProviderPayment(
  gateway: PaymentGatewayService,
  paymentResult: { payment: unknown; payableAmount: number },
  req: any,
  description: string,
) {
  const payment = paymentResult.payment as any;
  if (!payment?.id || paymentResult.payableAmount <= 0) return null;
  if (payment.provider === 'kaspi') {
    return gateway.createKaspiInvoice({
      paymentId: payment.id,
      amount: paymentResult.payableAmount,
      phone: payment.invoice_phone ?? req.body.invoicePhone,
      description,
    });
  }
  if (payment.provider === 'bcc') {
    return gateway.createBccPayment({
      paymentId: payment.id,
      amount: paymentResult.payableAmount,
      description,
      clientIp: req.ip,
      language: req.user?.language ?? req.body.language ?? 'ru',
      mInfo: payment.payload?.mInfo ?? req.body.mInfo,
    });
  }
  return null;
}

function formatPaymentAddress(address?: {
  city?: string | null;
  settlement?: string | null;
  street?: string | null;
  house?: string | null;
  apartment?: string | null;
} | null): string {
  if (!address) return 'DOMLY service payment';
  const parts = [address.city, address.settlement, address.street, address.house, address.apartment ? `apt ${address.apartment}` : null]
    .filter(Boolean)
    .join(', ');
  return toLatin(parts || 'DOMLY service payment');
}

export async function updatePaymentProviderPayload(db: Database, paymentId: string, provider: unknown) {
  await db.query(
    `UPDATE payments SET payload=payload || $2::jsonb, external_id=COALESCE($3, external_id), updated_at=NOW() WHERE id=$1`,
    [
      paymentId,
      provider,
      (provider as any)?.externalOrderId
        ?? (provider as any)?.providerResponse?.id
        ?? (provider as any)?.providerResponse?.invoiceId
        ?? (provider as any)?.providerResponse?.paymentId
        ?? null,
    ],
  );
}

export async function recordPaymentEvent(
  db: Database,
  input: {
    paymentId?: string | null;
    provider: string;
    eventType: string;
    status?: string | null;
    externalId?: unknown;
    idempotencyKey?: unknown;
    payload: unknown;
  },
) {
  const payload = input.payload ?? {};
  const explicitKey = input.idempotencyKey ?? (input.externalId ? `${input.eventType}:${input.externalId}` : null);
  const idempotencyKey = String(explicitKey || createHash('sha256').update(JSON.stringify(payload)).digest('hex'));
  await db.query(
    `INSERT INTO payment_events (payment_id, provider, event_type, status, external_id, idempotency_key, payload)
     VALUES ($1,$2::payment_provider,$3,$4::payment_status,$5,$6,$7)
     ON CONFLICT (provider, idempotency_key) DO UPDATE SET
       payment_id=COALESCE(payment_events.payment_id, EXCLUDED.payment_id),
       status=COALESCE(EXCLUDED.status, payment_events.status),
       external_id=COALESCE(EXCLUDED.external_id, payment_events.external_id),
       payload=EXCLUDED.payload`,
    [
      input.paymentId ?? null,
      input.provider,
      input.eventType,
      input.status ?? null,
      input.externalId ? String(input.externalId) : null,
      idempotencyKey,
      payload,
    ],
  );
}

export async function acquirePaymentApplication(db: Database, paymentId: string) {
  return first((await db.query(
    `UPDATE payments
     SET applied_at=NOW(), updated_at=NOW()
     WHERE id=$1 AND applied_at IS NULL
     RETURNING *`,
    [paymentId],
  )).rows);
}

async function getVisibleOrder(db: Database, orderId: string, user: { id: string; role: string }) {
  const order = first((await db.query(`SELECT * FROM service_orders WHERE id=$1`, [orderId])).rows);
  if (!order) throw new ApiError(404, 'not_found', 'Заказ не найден.');
  const anyOrder = order as any;
  const canSee = ['admin', 'superadmin'].includes(user.role)
    || anyOrder.customer_id === user.id
    || anyOrder.cleaner_id === user.id;
  if (!canSee) throw new ApiError(403, 'forbidden', 'Нет доступа к этому заказу.');
  return order;
}

async function ensureChecklistReport(db: Database, order: unknown) {
  const anyOrder = order as any;
  const existing = first((await db.query(`SELECT * FROM checklist_reports WHERE order_id=$1`, [anyOrder.id])).rows);
  if (existing) return existing;

  const report = first((await db.query(
    `INSERT INTO checklist_reports (order_id, cleaner_id, status) VALUES ($1,$2,'open') RETURNING *`,
    [anyOrder.id, anyOrder.cleaner_id ?? null],
  )).rows);
  const reportId = (report as any).id;

  const templateItems = (await db.query(
    `SELECT cti.title_ru, cti.title_kk
     FROM checklist_templates ct
     JOIN checklist_template_items cti ON cti.template_id=ct.id
     WHERE ct.active=TRUE AND (ct.package_id=$1 OR ct.package_id IS NULL)
     ORDER BY cti.sort_order ASC`,
    [anyOrder.package_id ?? null],
  )).rows;
  for (const item of templateItems) {
    await db.query(
      `INSERT INTO checklist_report_items (report_id, title_ru, title_kk) VALUES ($1,$2,$3)`,
      [reportId, (item as any).title_ru, (item as any).title_kk ?? null],
    );
  }

  const addons = (await db.query(
    `SELECT a.title_ru, a.title_kk
     FROM order_addons oa
     JOIN catalog_addons a ON a.id=oa.addon_id
     WHERE oa.order_id=$1 AND oa.payment_status='paid'`,
    [anyOrder.id],
  )).rows;
  for (const addon of addons) {
    await db.query(
      `INSERT INTO checklist_report_items (report_id, title_ru, title_kk) VALUES ($1,$2,$3)`,
      [reportId, `Доп. услуга: ${(addon as any).title_ru}`, (addon as any).title_kk ? `Қосымша қызмет: ${(addon as any).title_kk}` : null],
    );
  }

  return report;
}

function scoreAddressMatch(query: string, text: string): number {
  if (!query || !text) return 0;
  if (text.includes(query)) return 100 + query.length;
  const tokens = query.split(' ').filter((token) => token.length > 1);
  if (tokens.length === 0) return 0;
  const matched = tokens.filter((token) => text.includes(token)).length;
  if (matched === 0) return 0;
  return matched * 20 - Math.max(0, tokens.length - matched) * 5;
}

function formatHouseLabel(house: any): string {
  const parts = [
    house.residential_complex_ru,
    [house.street_ru ?? house.street_kk, house.house].filter(Boolean).join(', '),
  ].filter(Boolean);
  return parts.length ? parts.join(' · ') : [house.city, house.street_ru, house.house].filter(Boolean).join(', ');
}

function maskValue(value: string): string {
  if (value.length <= 6) return '***';
  return `${value.slice(0, 3)}***${value.slice(-3)}`;
}

async function readBackupStatus() {
  const backupDir = process.env.BACKUP_DIR ?? '/backups';
  const manifestPath = process.env.BACKUP_MANIFEST ?? path.join(backupDir, 'manifest.jsonl');
  const intervalSeconds = Number(process.env.BACKUP_INTERVAL_SECONDS ?? 86400);
  try {
    const raw = await fs.readFile(manifestPath, 'utf8');
    const lines = raw.split('\n').map((line) => line.trim()).filter(Boolean);
    const latest = lines.length ? JSON.parse(lines[lines.length - 1]) : null;
    const createdAt = latest?.createdAt ? parseBackupStamp(String(latest.createdAt)) : null;
    const ageSeconds = createdAt ? Math.floor((Date.now() - createdAt.getTime()) / 1000) : null;
    const staleAfterSeconds = Number.isFinite(intervalSeconds) && intervalSeconds > 0 ? intervalSeconds * 2 : 172800;
    return {
      configured: true,
      manifestPath,
      ok: Boolean(latest) && (ageSeconds == null || ageSeconds <= staleAfterSeconds),
      latest,
      ageSeconds,
      warning: !latest
        ? 'Backup manifest пустой.'
        : ageSeconds != null && ageSeconds > staleAfterSeconds
          ? 'Последний backup старше допустимого интервала.'
          : null,
    };
  } catch (error) {
    return {
      configured: false,
      manifestPath,
      ok: false,
      latest: null,
      ageSeconds: null,
      warning: `Backup manifest не найден или недоступен: ${(error as Error).message}`,
    };
  }
}

function parseBackupStamp(value: string) {
  const match = value.match(/^(\d{4})(\d{2})(\d{2})T(\d{2})(\d{2})(\d{2})Z$/);
  if (!match) {
    const parsed = new Date(value);
    return Number.isNaN(parsed.getTime()) ? null : parsed;
  }
  const [, year, month, day, hour, minute, second] = match;
  return new Date(Date.UTC(Number(year), Number(month) - 1, Number(day), Number(hour), Number(minute), Number(second)));
}
