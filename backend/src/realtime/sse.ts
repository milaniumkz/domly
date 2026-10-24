import { Router } from 'express';
import IORedis from 'ioredis';
import { auth } from '../common/auth';

const realtimeChannel = 'domly:realtime';
const clients = new Set<{ userId: string; write: (payload: string) => void; close: () => void }>();
let publisher: IORedis | null = null;
let subscriber: IORedis | null = null;

export function buildRealtimeRouter(): Router {
  const router = Router();
  router.get('/', auth([], { allowQueryToken: true }), (req, res) => {
    res.writeHead(200, {
      'Content-Type': 'text/event-stream',
      'Cache-Control': 'no-cache',
      Connection: 'keep-alive',
      'X-Accel-Buffering': 'no',
    });
    const client = {
      userId: req.user!.id,
      close: () => res.end(),
      write: (payload: string) => res.write(`event: message\ndata: ${payload}\n\n`),
    };
    clients.add(client);
    client.write(JSON.stringify({ type: 'connected' }));
    const heartbeat = setInterval(() => {
      res.write(`event: ping\ndata: ${JSON.stringify({ time: new Date().toISOString() })}\n\n`);
    }, 25_000);
    req.on('close', () => {
      clearInterval(heartbeat);
      clients.delete(client);
    });
  });
  return router;
}

export function emitToUser(userId: string, event: unknown): void {
  emitToUsers([userId], event);
}

function emitToUsers(userIds: string[], event: unknown): void {
  const recipients = new Set(userIds);
  const payload = JSON.stringify(event);
  for (const client of clients) {
    if (recipients.has(client.userId)) {
      client.write(payload);
      if ((event as {type?:string} | null)?.type === 'auth.revoked') { clients.delete(client); client.close(); }
    }
  }
}

export function revokeRealtimeSessions(userId: string): void {
  const event = {type: 'auth.revoked'};
  emitToUser(userId, event);
  // Do not hold a support operation open during a Redis outage.
  if (publisher) void publishToUser(userId, event).catch(() => undefined);
}

export function configureRealtimeBus(redisUrl: string): void {
  if (publisher || subscriber) return;
  publisher = new IORedis(redisUrl, { maxRetriesPerRequest: null, lazyConnect: true });
  subscriber = new IORedis(redisUrl, { maxRetriesPerRequest: null });
  subscriber.subscribe(realtimeChannel).catch(() => undefined);
  subscriber.on('message', (_channel, message) => {
    try {
      const event = JSON.parse(message) as { userId?: string; userIds?: string[]; payload?: unknown };
      if (Array.isArray(event.userIds) && event.userIds.length <= 250 && event.userIds.every(id => typeof id === 'string')) {
        emitToUsers(event.userIds, event.payload ?? {});
      } else if (typeof event.userId === 'string' && event.userId) {
        emitToUser(event.userId, event.payload ?? {});
      }
    } catch {
      // Ignore malformed realtime events; API response path must not fail because of SSE.
    }
  });
}

export async function publishToUser(userId: string, event: unknown, requireBroker = false): Promise<void> {
  if (!publisher) {
    emitToUser(userId, event);
    return;
  }
  try {
    await publisher.publish(realtimeChannel, JSON.stringify({ userId, payload: event }));
  } catch (error) {
    if (requireBroker) throw error;
    emitToUser(userId, event);
  }
}

/** Recipients are resolved from live account state by the caller, not a cached role. */
export async function publishToUsers(userIds: string[], event: unknown, requireBroker = false): Promise<void> {
  const recipients = [...new Set(userIds)];
  if (!publisher) { emitToUsers(recipients, event); return; }
  for (let offset = 0; offset < recipients.length; offset += 250) {
    const batch = recipients.slice(offset, offset + 250);
    try { await publisher.publish(realtimeChannel, JSON.stringify({userIds: batch, payload: event})); }
    catch (error) { if (requireBroker) throw error; emitToUsers(batch, event); }
  }
}

export async function closeRealtimeBus(): Promise<void> {
  await Promise.all([
    publisher?.quit().catch(() => undefined),
    subscriber?.quit().catch(() => undefined),
  ]);
  publisher = null;
  subscriber = null;
}
