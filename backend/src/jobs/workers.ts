import { Queue, Worker } from 'bullmq';
import IORedis from 'ioredis';
import { env, validateEnvForRuntime } from '../common/env';
import { Database } from '../infrastructure/db/Database';
import { FcmService } from '../modules/integrations';
import { SchedulingService } from '../modules/domainServices';
import { closeRealtimeBus, configureRealtimeBus, publishToUser } from '../realtime/sse';

validateEnvForRuntime();

const db = new Database(env.databaseUrl);
const fcm = new FcmService();
const scheduling = new SchedulingService(db);
const connection = new IORedis(env.redisUrl, { maxRetriesPerRequest: null });
const maintenanceQueue = new Queue('maintenance', { connection });
configureRealtimeBus(env.redisUrl);
const workers: Worker[] = [];

async function readSettings() {
  return (await db.query<{ key: string; value: any }>(`SELECT key, value FROM app_settings`)).rows
    .reduce<Record<string, any>>((acc, row) => {
      acc[row.key] = row.value;
      return acc;
    }, {});
}

async function notifyUser(userId: string, titleRu: string, bodyRu: string, targetType?: string, targetId?: string, dedupeKey?: string) {
  const row = (await db.query<{ id: string }>(
    `INSERT INTO notifications (user_id, title_ru, body_ru, target_type, target_id, dedupe_key)
     VALUES ($1,$2,$3,$4,$5,$6)
     ON CONFLICT (user_id, dedupe_key) DO NOTHING
     RETURNING id`,
    [userId, titleRu, bodyRu, targetType ?? null, targetId ?? null, dedupeKey ?? null],
  )).rows[0];
  const tokens = (await db.query<{ token: string }>(
    `SELECT token FROM device_tokens WHERE user_id=$1 AND enabled=TRUE`,
    [userId],
  )).rows.map((row) => row.token);
  await fcm.send(tokens, titleRu, bodyRu, {
    targetType: targetType ?? '',
    targetId: targetId ?? '',
    notificationId: row?.id ?? '',
  });
  if (row) {
    await publishToUser(userId, {
      type: 'notification',
      notification: {
        id: row.id,
        user_id: userId,
        title_ru: titleRu,
        body_ru: bodyRu,
        target_type: targetType ?? null,
        target_id: targetId ?? null,
      },
    });
  }
}

async function notifyRole(role: string, titleRu: string, bodyRu: string, targetType?: string, targetId?: string, dedupeKey?: string) {
  const users = (await db.query<{ id: string }>(`SELECT id FROM app_users WHERE role=$1 AND status <> 'blocked'`, [role])).rows;
  await Promise.all(users.map((user) => notifyUser(user.id, titleRu, bodyRu, targetType, targetId, dedupeKey ? `${dedupeKey}-${user.id}` : undefined)));
}

workers.push(new Worker('notifications', async (job) => {
  const { userId, role, titleRu, bodyRu, targetType, targetId } = job.data;
  const tokens = (await db.query<{ token: string }>(
    userId
      ? `SELECT token FROM device_tokens WHERE user_id=$1 AND enabled=TRUE`
      : `SELECT dt.token FROM device_tokens dt JOIN app_users u ON u.id=dt.user_id WHERE u.role=$1 AND dt.enabled=TRUE`,
    userId ? [userId] : [role],
  )).rows.map((row) => row.token);
  await fcm.send(tokens, titleRu, bodyRu, { targetType: targetType ?? '', targetId: targetId ?? '' });
  if (userId) {
    await publishToUser(userId, {
      type: 'notification',
      notification: { user_id: userId, title_ru: titleRu, body_ru: bodyRu, target_type: targetType ?? null, target_id: targetId ?? null },
    });
  }
}, { connection }));

workers.push(new Worker('cleaner-alarms', async (job) => {
  const { cleanerId, orderId, titleRu, bodyRu, notificationId } = job.data;
  const tokens = (await db.query<{ token: string }>(
    `SELECT token FROM device_tokens WHERE user_id=$1 AND enabled=TRUE`,
    [cleanerId],
  )).rows.map((row) => row.token);
  await fcm.send(tokens, titleRu ?? 'Новый заказ', bodyRu ?? 'Вам поступил новый заказ. Откройте приложение.', {
    targetType: 'order_offer',
    targetId: orderId,
    notificationId: notificationId ?? '',
    alarm: 'true',
  });
  await publishToUser(cleanerId, {
    type: 'cleaner_alarm',
    orderId,
    notificationId: notificationId ?? '',
  });
}, { connection }));

workers.push(new Worker('payments', async (job) => {
  await db.query(
    `INSERT INTO audit_logs (action, entity_type, entity_id, payload) VALUES ($1,$2,$3,$4)`,
    [job.name, 'payment', job.data.paymentId ?? null, job.data],
  );
}, { connection }));

workers.push(new Worker('maintenance', async (job) => {
  if (job.name === 'cleanup-expired-auth') {
    const otp = (await db.query<{ count: string }>(
      `WITH deleted AS (
         DELETE FROM auth_otp_codes
         WHERE expires_at < NOW() - INTERVAL '1 day'
            OR consumed_at < NOW() - INTERVAL '1 day'
         RETURNING id
       )
       SELECT COUNT(*)::text AS count FROM deleted`,
    )).rows[0]?.count ?? '0';
    const sessions = (await db.query<{ count: string }>(
      `WITH deleted AS (
         DELETE FROM refresh_sessions
         WHERE expires_at < NOW() - INTERVAL '30 days'
            OR revoked_at < NOW() - INTERVAL '30 days'
         RETURNING id
       )
       SELECT COUNT(*)::text AS count FROM deleted`,
    )).rows[0]?.count ?? '0';
    const tokens = (await db.query<{ count: string }>(
      `WITH deleted AS (
         DELETE FROM device_tokens
         WHERE enabled=FALSE AND updated_at < NOW() - INTERVAL '30 days'
         RETURNING id
       )
       SELECT COUNT(*)::text AS count FROM deleted`,
    )).rows[0]?.count ?? '0';
    await db.query(
      `INSERT INTO audit_logs (action, entity_type, payload) VALUES ($1,$2,$3)`,
      ['maintenance.cleanup_expired_auth', 'maintenance', { otp: Number(otp), refreshSessions: Number(sessions), deviceTokens: Number(tokens) }],
    );
    return;
  }

  if (job.name !== 'expire-order-offers') return;
  const expired = (await db.query<{ order_id: string; cleaner_id: string }>(
    `UPDATE order_offers
     SET status='expired'
     WHERE status='offered' AND expires_at <= NOW()
     RETURNING order_id, cleaner_id`,
  )).rows;
  const orderIds = [...new Set(expired.map((row) => row.order_id))];
  const settings = await readSettings();
  const ttlMinutes = Number(settings.cleanerOfferTtlMinutes ?? 2);
  for (const orderId of orderIds) {
    const order = (await db.query<{ status: string; cleaner_id: string | null }>(
      `SELECT status, cleaner_id FROM service_orders WHERE id=$1`,
      [orderId],
    )).rows[0];
    if (!order || order.cleaner_id || ['cancelled', 'completed', 'assigned', 'in_progress'].includes(order.status)) continue;
    const excluded = (await db.query<{ cleaner_id: string }>(
      `SELECT cleaner_id FROM order_offers WHERE order_id=$1 AND status IN ('declined','expired','accepted')`,
      [orderId],
    )).rows.map((row) => row.cleaner_id);
    const offer = await scheduling.offerNextCleaner(orderId, excluded, ttlMinutes) as any;
    if (offer) {
      await notifyUser(
        offer.cleaner_id,
        'Новый заказ',
        'Вам поступил новый заказ на подтверждение.',
        'order_offer',
        orderId,
        `order-offer-${orderId}-${offer.cleaner_id}`,
      );
    } else {
      await notifyRole(
        'admin',
        'Нет свободной уборщицы',
        'Заказ ожидает ручного назначения.',
        'order',
        orderId,
        `order-no-cleaner-${orderId}`,
      );
      await notifyRole(
        'superadmin',
        'Нет свободной уборщицы',
        'Заказ ожидает ручного назначения.',
        'order',
        orderId,
        `order-no-cleaner-${orderId}`,
      );
    }
  }
}, { connection }));

void maintenanceQueue.add('expire-order-offers', {}, {
  jobId: 'expire-order-offers',
  repeat: { every: 60_000 },
  removeOnComplete: true,
});

void maintenanceQueue.add('cleanup-expired-auth', {}, {
  jobId: 'cleanup-expired-auth',
  repeat: { every: 3_600_000 },
  removeOnComplete: true,
});

async function shutdown(signal: string) {
  await Promise.all(workers.map((worker) => worker.close().catch(() => undefined)));
  await Promise.all([
    maintenanceQueue.close().catch(() => undefined),
    closeRealtimeBus().catch(() => undefined),
    connection.quit().catch(() => undefined),
    db.close().catch(() => undefined),
  ]);
  process.exit(signal === 'SIGTERM' || signal === 'SIGINT' ? 0 : 1);
}

process.once('SIGTERM', () => void shutdown('SIGTERM'));
process.once('SIGINT', () => void shutdown('SIGINT'));
