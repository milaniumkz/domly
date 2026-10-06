import cors from 'cors';
import express from 'express';
import IORedis from 'ioredis';
import swaggerUi from 'swagger-ui-express';
import { SchedulerService } from '../application/use-cases/SchedulerService';
import { CalendarController } from '../calendar/http/CalendarController';
import { CalendarBookingService } from '../calendar/services/CalendarBookingService';
import { CustomPackageController } from '../custom-package/http/CustomPackageController';
import { PostgresCustomPackageRepository } from '../custom-package/repositories/PostgresCustomPackageRepository';
import { CustomPackageService } from '../custom-package/services/CustomPackageService';
import { PricingEngine } from '../custom-package/services/PricingEngine';
import { errorHandler, ok } from '../common/api';
import { env, validateEnvForRuntime } from '../common/env';
import { buildRealtimeRouter, closeRealtimeBus, configureRealtimeBus } from '../realtime/sse';
import { AuthService, BonusService, NotificationService, PaymentService, PricingService, SchedulingService } from '../modules/domainServices';
import { AddressSearchService, buildQueues, FcmService, PaymentGatewayService, StorageService, WapiOtpService } from '../modules/integrations';
import { PostgresCalendarRepository } from '../calendar/repositories/PostgresCalendarRepository';
import { Database } from '../infrastructure/db/Database';
import { ConsoleLogger } from '../infrastructure/logging/Logger';
import { PostgresAssignmentRepository } from '../infrastructure/repositories/PostgresAssignmentRepository';
import { PostgresCleanerRepository } from '../infrastructure/repositories/PostgresCleanerRepository';
import { PostgresOrderRepository } from '../infrastructure/repositories/PostgresOrderRepository';
import { CleanerController } from './controllers/CleanerController';
import { ScheduleController } from './controllers/ScheduleController';
import { SchedulerController } from './controllers/SchedulerController';
import { openApiSpec } from './openapi';
import { buildRouter } from './routes';
import { buildV1Router } from './routes/v1';

validateEnvForRuntime();

const db = new Database(env.databaseUrl);
const logger = new ConsoleLogger();

const cleanerRepository = new PostgresCleanerRepository(db);
const orderRepository = new PostgresOrderRepository(db);
const assignmentRepository = new PostgresAssignmentRepository(db);
const calendarRepository = new PostgresCalendarRepository(db);
const customPackageRepository = new PostgresCustomPackageRepository(db);

const schedulerService = new SchedulerService(cleanerRepository, orderRepository, assignmentRepository, db, logger);
const calendarService = new CalendarBookingService(calendarRepository, db);
const customPackageService = new CustomPackageService(customPackageRepository, new PricingEngine(), db);

const app = express();
app.disable('x-powered-by');
app.use(cors());
app.use(express.json({ limit: '10mb' }));

const wapi = new WapiOtpService();
const fcm = new FcmService();
const storage = new StorageService();
const readinessRedis = new IORedis(env.redisUrl, { maxRetriesPerRequest: null, lazyConnect: true });
const bonuses = new BonusService(db);
const queues = buildQueues();
configureRealtimeBus(env.redisUrl);

app.get('/health', async (_req, res) => {
  await db.query('SELECT 1');
  ok(res, { status: 'ok', service: 'domly-backend', time: new Date().toISOString() });
});

app.get('/ready', async (_req, res) => {
  const checks = {
    database: await db.query('SELECT 1').then(() => ({ ok: true })).catch(() => ({ ok: false })),
    redis: await readinessRedis.ping().then(() => ({ ok: true })).catch(() => ({ ok: false })),
    minio: await storage.client.bucketExists(env.minioBucket).then((exists) => ({ ok: exists, bucket: env.minioBucket, bucketExists: exists })).catch(() => ({ ok: false, bucket: env.minioBucket, bucketExists: false })),
    wapi: { ok: Boolean(env.wapiToken && env.wapiProfileId), configured: Boolean(env.wapiToken && env.wapiProfileId) },
    fcm: { ok: Boolean(env.fcmProjectId && env.fcmClientEmail && env.fcmPrivateKey), configured: Boolean(env.fcmProjectId && env.fcmClientEmail && env.fcmPrivateKey) },
  };
  const ready = checks.database.ok && checks.redis.ok && checks.minio.ok;
  res.status(ready ? 200 : 503).json({ ok: ready, data: { status: ready ? 'ready' : 'not_ready', checks, time: new Date().toISOString() } });
});

app.use('/api/docs', swaggerUi.serve, swaggerUi.setup(openApiSpec));

app.use('/api/v1', buildV1Router({
  db,
  authService: new AuthService(db, wapi),
  notifications: new NotificationService(db, fcm, queues),
  bonuses,
  payments: new PaymentService(db, bonuses),
  pricing: new PricingService(),
  scheduling: new SchedulingService(db),
  storage,
  paymentGateway: new PaymentGatewayService(),
  addressSearch: new AddressSearchService(),
  wapi,
}));
app.use('/api/v1/realtime', buildRealtimeRouter());

app.use('/api/v1/legacy', buildRouter(
  new SchedulerController(schedulerService),
  new CleanerController(schedulerService),
  new ScheduleController(orderRepository),
  new CalendarController(calendarService),
  new CustomPackageController(customPackageService),
));

app.use(errorHandler);

const server = app.listen(env.port, () => {
  logger.info('domly_backend_started', { port: env.port });
});

async function shutdown(signal: string) {
  logger.info('domly_backend_stopping', { signal });
  server.close(async () => {
    await Promise.all([
      readinessRedis.quit().catch(() => undefined),
      queues.close().catch(() => undefined),
      closeRealtimeBus().catch(() => undefined),
      db.close().catch(() => undefined),
    ]);
    logger.info('domly_backend_stopped', { signal });
    process.exit(0);
  });
  setTimeout(() => process.exit(1), 10_000).unref();
}

process.once('SIGTERM', () => void shutdown('SIGTERM'));
process.once('SIGINT', () => void shutdown('SIGINT'));
