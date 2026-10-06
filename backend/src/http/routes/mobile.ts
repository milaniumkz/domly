import { updateOrderAddons } from '../../modules/orderAddons';
import { Router } from 'express';
import { randomUUID } from 'crypto';
import { auth, verifyAccessToken } from '../../common/auth';
import { ApiError, asyncHandler, ok } from '../../common/api';
import { Database } from '../../infrastructure/db/Database';
import { first } from '../../common/sql';

export function mobileRouter(db: Database) {
  const router = Router();
  // Deleted accounts must not retain access through an unexpired JWT.
  router.use(asyncHandler(async (req, _res, next) => {
    const token = req.header('authorization')?.replace(/^Bearer /, '') || (req.path.startsWith('/realtime') ? String(req.query.access_token ?? '') : '');
    if (token) {
      let user;
      try { user = verifyAccessToken(token); } catch { return next(); }
      const row = first<any>((await db.query('SELECT deleted_at FROM app_users WHERE id=$1', [user.id])).rows);
      if (!row || row.deleted_at) throw new ApiError(401, 'unauthorized', 'Аккаунт удалён.');
      req.user = user;
    }
    next();
  }));

  router.delete('/me', auth(['customer', 'cleaner']), asyncHandler(async (req, res) => {
    await db.transaction(async tx => {
      const busy = first((await tx.query(`SELECT id FROM service_orders WHERE (customer_id=$1 OR cleaner_id=$1)
        AND status NOT IN ('completed','cancelled','canceled') LIMIT 1`, [req.user!.id])).rows);
      if (busy) throw new ApiError(409, 'active_orders', 'Завершите или отмените текущие заказы перед удалением аккаунта.');
      await tx.query('DELETE FROM device_tokens WHERE user_id=$1', [req.user!.id]);
      await tx.query('UPDATE refresh_sessions SET revoked_at=NOW() WHERE user_id=$1', [req.user!.id]);

      await tx.query(`UPDATE customer_addresses SET city='Удалено',settlement=NULL,street='Удалено',house='-',apartment=NULL,entrance=NULL,floor=NULL,intercom=NULL,access_comment=NULL,area=NULL,latitude=NULL,longitude=NULL
        WHERE user_id=$1`, [req.user!.id]);
      await tx.query("UPDATE cleaner_profiles SET registration_status='blocked',verification_status='blocked',updated_at=NOW() WHERE user_id=$1",[req.user!.id]);
      await tx.query('DELETE FROM house_waitlist WHERE user_id=$1',[req.user!.id]);
      await tx.query(`UPDATE app_users SET phone=$2, full_name=NULL, email=NULL, password_hash=NULL,
        firebase_uid=NULL, status='blocked', deleted_at=NOW(), updated_at=NOW() WHERE id=$1`,
        [req.user!.id, `deleted-${randomUUID()}`]);
    });
    ok(res, { deleted: true });
  }));

  router.post('/orders/:id/addons', auth(['customer']), asyncHandler(async (req,res) => {
    ok(res, await updateOrderAddons(db,String(req.params.id),req.user!.id,req.body.addonsDetailed));
  }));

  router.post('/packages/my/:id/freeze', auth(['customer']), asyncHandler(async (req,res) => {
    const setting = first<any>((await db.query("SELECT value FROM app_settings WHERE key='maxPackageFreezeDays'")).rows);
    const days = Number(req.body.days);
    if (!Number.isInteger(days) || days < 1 || days > Number(setting?.value ?? 30)) throw new ApiError(400,'invalid_freeze','Проверьте срок заморозки.');
    const pkg = first((await db.query(`UPDATE customer_packages SET freeze_until=CURRENT_DATE+$3::integer,updated_at=NOW()
      WHERE id=$1 AND customer_id=$2 AND status='active' RETURNING *`,[req.params.id,req.user!.id,days])).rows);
    if (!pkg) throw new ApiError(404,'package_not_found','Активный пакет не найден.');
    ok(res,pkg);
  }));

  router.get('/referrals', auth(['customer']), asyncHandler(async (req, res) => {
    const user = first<any>((await db.query('SELECT numeric_id, bonus_balance FROM app_users WHERE id=$1', [req.user!.id])).rows);
    const stats = first<any>((await db.query(`SELECT COUNT(*)::int AS invited,
      COUNT(*) FILTER (WHERE qualified_at IS NOT NULL)::int AS qualified FROM user_referrals WHERE inviter_id=$1`, [req.user!.id])).rows);
    const own = first<any>((await db.query(`SELECT 'DOMLY-' || u.numeric_id AS code FROM user_referrals r
      JOIN app_users u ON u.id=r.inviter_id WHERE r.customer_id=$1`, [req.user!.id])).rows);
    const code = `DOMLY-${user.numeric_id}`;
    ok(res, { referralCode: code, referredByCode: own?.code ?? null,
      referralLink: `https://domly.kz/customer/?ref=${encodeURIComponent(code)}`,
      invited: stats.invited, invitedCount: stats.invited, registered: stats.invited, paid: stats.qualified,
      referralQualifiedCount: stats.qualified, bonusPoints: Number(user.bonus_balance) });
  }));

  router.post('/referrals', auth(['customer']), asyncHandler(async (req, res) => {
    const code = String(req.body.code ?? '').trim().toUpperCase();
    if (!/^DOMLY-\d+$/.test(code)) throw new ApiError(400, 'invalid_referral', 'Проверьте реферальный код.');
    const inviter = first<any>((await db.query(`SELECT id FROM app_users WHERE numeric_id=$1 AND role='customer' AND deleted_at IS NULL`, [code.slice(6)])).rows);
    if (!inviter || inviter.id === req.user!.id) throw new ApiError(400, 'invalid_referral', 'Код приглашения недействителен.');
    await db.transaction(async tx => {
      await tx.query('SELECT id FROM app_users WHERE id=$1 FOR UPDATE', [req.user!.id]);
      const existing = first<any>((await tx.query('SELECT inviter_id FROM user_referrals WHERE customer_id=$1', [req.user!.id])).rows);
      if (existing && existing.inviter_id !== inviter.id) throw new ApiError(409, 'referral_already_set', 'Код приглашения уже указан.');
      const paid = first((await tx.query(`SELECT id FROM payments WHERE customer_id=$1 AND status='paid' LIMIT 1`, [req.user!.id])).rows);
      if (!existing && paid) throw new ApiError(409, 'referral_too_late', 'Код нужно указать до первой оплаты.');
      await tx.query('INSERT INTO user_referrals (customer_id, inviter_id) VALUES ($1,$2) ON CONFLICT DO NOTHING', [req.user!.id, inviter.id]);
    });
    ok(res, { applied: true });
  }));

  router.get('/geo/houses/:id/stats', asyncHandler(async (req, res) => {
    const house = first<any>((await db.query('SELECT * FROM connected_houses WHERE id=$1', [req.params.id])).rows);
    if (!house) throw new ApiError(404, 'not_found', 'Дом не найден.');
    const count = first<any>((await db.query('SELECT COUNT(*)::int AS total FROM house_waitlist WHERE house_id=$1', [house.id])).rows).total;
    const thresholdRow = first<any>((await db.query("SELECT value FROM app_settings WHERE key='houseActivationThreshold'")).rows);
    const threshold = Math.max(1, Number(thresholdRow?.value ?? 20));
    ok(res, { house: { ...house, address: `${house.street_ru} ${house.house}`, threshold,
      current_users: count, total_users: count, status: house.active ? 'ACTIVE' : 'IN_PROGRESS' },
      progress: Math.min(count / threshold, 1), remaining: Math.max(threshold - count, 0),
      activationText: house.active ? 'Дом уже подключён.' : 'Заявка на подключение дома сохранена.', packageBreakdown: {} });
  }));
  router.get('/geo/houses/:id/waitlist', auth(), asyncHandler(async (req, res) => {
    // Customers see only their own entry, never their neighbours' identities.
    ok(res, (await db.query('SELECT id, house_id AS "houseId", created_at AS "createdAt" FROM house_waitlist WHERE house_id=$1 AND user_id=$2', [req.params.id, req.user!.id])).rows);
  }));
  router.post('/geo/houses/:id/waitlist', auth(['customer']), asyncHandler(async (req, res) => {
    const house = first((await db.query('SELECT id FROM connected_houses WHERE id=$1', [req.params.id])).rows);
    if (!house) throw new ApiError(404, 'not_found', 'Дом не найден.');
    await db.query(`INSERT INTO house_waitlist (house_id,user_id,source) VALUES ($1,$2,$3)
      ON CONFLICT (house_id,user_id) DO NOTHING`, [req.params.id, req.user!.id, String(req.body.source ?? 'app').slice(0, 100)]);
    ok(res, { joined: true, houseId: req.params.id });
  }));
  router.post('/geo/houses/:id/invite', auth(['customer']), asyncHandler(async (req, res) => {
    const house = first((await db.query('SELECT id FROM connected_houses WHERE id=$1', [req.params.id])).rows);
    if (!house) throw new ApiError(404, 'not_found', 'Дом не найден.');
    ok(res, { houseId: req.params.id, inviteLink: `https://domly.kz/customer/#/client/house-waitlist?houseId=${encodeURIComponent(String(req.params.id))}` });
  }));

  router.get('/training/videos', asyncHandler(async (req, res) => {
    const audience = String(req.query.audience ?? 'client');
    ok(res, (await db.query(`SELECT id, title, description, url, url AS "videoUrl", category, audience_type AS "audienceType",
      published_at AS "publishedAt", active AS "isActive" FROM training_videos
      WHERE active=TRUE AND audience_type IN ($1,'both') ORDER BY published_at DESC`, [audience])).rows);
  }));
  router.get('/training/videos/:id', asyncHandler(async (req, res) => {
    const video = first((await db.query(`SELECT id, title, description, url, url AS "videoUrl", category, audience_type AS "audienceType",
      published_at AS "publishedAt", active AS "isActive" FROM training_videos WHERE id=$1 AND active=TRUE`, [req.params.id])).rows);
    if (!video) throw new ApiError(404, 'not_found', 'Видео не найдено.');
    ok(res, video);
  }));
  router.get('/admin/referrals', auth(['admin','superadmin']), asyncHandler(async (_req,res) => {
    ok(res,(await db.query(`SELECT inviter_id AS id,COUNT(*)::int AS invited,COUNT(*)::int AS registered,
      COUNT(*) FILTER (WHERE qualified_at IS NOT NULL)::int AS paid,SUM(reward_amount) AS bonus
      FROM user_referrals GROUP BY inviter_id`)).rows);
  }));

  router.get('/admin/videos', auth(['admin','superadmin']), asyncHandler(async (_req, res) => {
    ok(res, (await db.query(`SELECT id, title, description, url, url AS "videoUrl", category, audience_type AS "audienceType",
      published_at AS "publishedAt", active AS "isActive" FROM training_videos ORDER BY published_at DESC`)).rows);
  }));
  router.post('/admin/videos', auth(['admin','superadmin']), asyncHandler(async (req, res) => {
    const url = String(req.body.url ?? req.body.videoUrl ?? '').trim();
    let parsed;
    try { parsed = new URL(url); } catch { throw new ApiError(400, 'invalid_video', 'Укажите HTTPS-ссылку на видео.'); }
    if (parsed.protocol !== 'https:' || !String(req.body.title ?? '').trim()) throw new ApiError(400, 'invalid_video', 'Укажите название и HTTPS-ссылку.');
    const row = first((await db.query(`INSERT INTO training_videos (id,title,description,url,audience_type,active,category)
      VALUES ($1,$2,$3,$4,$5,$6,$7) ON CONFLICT(id) DO UPDATE SET title=EXCLUDED.title,
      description=EXCLUDED.description,url=EXCLUDED.url,audience_type=EXCLUDED.audience_type,active=EXCLUDED.active,category=EXCLUDED.category RETURNING *`,
      [req.body.id || randomUUID(), req.body.title, req.body.description ?? '', url, req.body.audienceType ?? 'both', req.body.isActive !== false, req.body.category ?? ''])).rows);
    ok(res, row);
  }));
  return router;
}
